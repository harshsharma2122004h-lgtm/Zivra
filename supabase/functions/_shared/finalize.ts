import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export type Db = ReturnType<typeof createClient>;

export type FinalizeResult =
  | { ok: true; order_id: string; order_number: string; total: number; payment_id: string; email_sent: boolean; duplicate: boolean }
  | { ok: false; code: "no_intent" | "not_captured" | "mismatch" | "needs_review" | "error"; error: string; retryable: boolean; payment_id: string };

const enc = new TextEncoder();
export const toHex = (bytes: Uint8Array) => Array.from(bytes).map((x) => x.toString(16).padStart(2, "0")).join("");

export async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(message))));
}

export function safeEqual(a: string, b: string): boolean {
  let diff = a.length ^ b.length;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}

async function razorpay(keyId: string, secret: string, path: string, init: RequestInit = {}) {
  const res = await fetch("https://api.razorpay.com/v1" + path, {
    ...init,
    headers: { Authorization: "Basic " + btoa(keyId + ":" + secret), "Content-Type": "application/json" },
  });
  let data: any = {};
  try { data = await res.json(); } catch { /* keep {} */ }
  return { ok: res.ok, status: res.status, data };
}

async function setIntent(db: Db, razorpayOrderId: string, patch: Record<string, unknown>) {
  const { error } = await db.from("zivra_payment_intents")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("razorpay_order_id", razorpayOrderId);
  if (error) console.error("[finalize] could not update payment intent", razorpayOrderId, error.message);
}

async function sendReceivedEmail(db: Db, orderId: string): Promise<{ sent: boolean; detail: string }> {
  try {
    const { data, error } = await db.functions.invoke("send-order-email", { body: { order_id: orderId, type: "received" } });
    if (error) return { sent: false, detail: "failed: " + error.message };
    const sent = data?.ok === true && data?.customer_email_sent !== false && data?.owner_notified !== false;
    return { sent, detail: sent ? "sent" : "partial: " + JSON.stringify(data).slice(0, 300) };
  } catch (e) {
    return { sent: false, detail: "failed: " + (e instanceof Error ? e.message : String(e)) };
  }
}

export async function finalizePayment(
  db: Db,
  cfg: { keyId: string; secret: string },
  razorpayOrderId: string,
  paymentId: string,
): Promise<FinalizeResult> {
  const fail = (code: any, error: string, retryable: boolean): FinalizeResult =>
    ({ ok: false, code, error, retryable, payment_id: paymentId });

  const { data: intent, error: intentError } = await db.from("zivra_payment_intents")
    .select("*").eq("razorpay_order_id", razorpayOrderId).maybeSingle();
  if (intentError) { console.error("[finalize] ledger read failed", intentError.message); return fail("error", "Could not read payment record.", true); }
  if (!intent) {
    console.error("[finalize] no ledger row for", razorpayOrderId, paymentId);
    return fail("no_intent", "This payment has no saved checkout record. Contact ZIVRA support with your payment ID.", false);
  }

  if (intent.status === "fulfilled" && intent.order_id) {
    const { data: order } = await db.from("orders").select("id,order_number,total").eq("id", intent.order_id).maybeSingle();
    if (order) {
      let emailSent = intent.email_status === "sent";
      if (!emailSent) {
        const mail = await sendReceivedEmail(db, order.id);
        emailSent = mail.sent;
        await setIntent(db, razorpayOrderId, { email_status: mail.detail });
      }
      return { ok: true, order_id: order.id, order_number: order.order_number, total: Number(order.total), payment_id: paymentId, email_sent: emailSent, duplicate: true };
    }
  }

  let pay = await razorpay(cfg.keyId, cfg.secret, "/payments/" + paymentId);
  if (!pay.ok) { console.error("[finalize] razorpay lookup failed", pay.status, JSON.stringify(pay.data)); return fail("error", "Could not confirm payment with Razorpay yet.", true); }
  if (pay.data.order_id !== razorpayOrderId || pay.data.currency !== "INR" || Number(pay.data.amount) !== Number(intent.amount_paise)) {
    console.error("[finalize] payment mismatch", razorpayOrderId, paymentId, pay.data.order_id, pay.data.amount);
    await setIntent(db, razorpayOrderId, { status: "needs_review", razorpay_payment_id: paymentId, last_error: "Payment does not match checkout record" });
    return fail("mismatch", "Paid amount does not match this checkout. Contact ZIVRA support.", false);
  }
  if (pay.data.status === "authorized") {
    const cap = await razorpay(cfg.keyId, cfg.secret, "/payments/" + paymentId + "/capture", {
      method: "POST", body: JSON.stringify({ amount: intent.amount_paise, currency: "INR" }),
    });
    console.log("[finalize] capture attempt", paymentId, cap.status);
    pay = await razorpay(cfg.keyId, cfg.secret, "/payments/" + paymentId);
  }
  if (pay.data.status !== "captured") {
    console.warn("[finalize] payment not captured yet", paymentId, pay.data.status);
    return fail("not_captured", "Payment is still being confirmed by the bank.", true);
  }

  const payload = { ...(intent.customer as object), payment_method: "online", items: intent.items };
  const { data: placed, error: rpcError } = await db.rpc("zivra_place_paid_order_v2", {
    payload, p_razorpay_order_id: razorpayOrderId, p_razorpay_payment_id: paymentId, p_free_shipping: !!intent.free_shipping,
  });

  let orderId: string | undefined, orderNumber: string | undefined, total = 0, duplicate = false;
  if (rpcError) {
    console.error("[finalize] order RPC failed", razorpayOrderId, paymentId, rpcError.message);
    const { data: existing } = await db.from("orders").select("id,order_number,total")
      .or("razorpay_payment_id.eq." + paymentId + ",razorpay_order_id.eq." + razorpayOrderId).maybeSingle();
    if (!existing) {
      const permanent = /insufficient stock|unavailable|invalid cart|valid delivery/i.test(rpcError.message);
      await setIntent(db, razorpayOrderId, {
        status: permanent ? "needs_review" : "created", razorpay_payment_id: paymentId, last_error: rpcError.message.slice(0, 500),
      });
      return fail(permanent ? "needs_review" : "error",
        permanent ? "Payment received but the order could not be completed (" + rpcError.message + "). ZIVRA will refund or fix it — contact support with your payment ID."
                  : "Payment received; order is being finalised.", !permanent);
    }
    orderId = existing.id; orderNumber = existing.order_number; total = Number(existing.total); duplicate = true;
  } else {
    orderId = placed.id; orderNumber = placed.order_number; total = Number(placed.total); duplicate = !!placed.duplicate;
    if (Math.round(total * 100) !== Number(intent.amount_paise)) {
      console.warn("[finalize] order total differs from amount paid", orderNumber, total, intent.amount_paise);
    }
  }

  await setIntent(db, razorpayOrderId, { status: "fulfilled", order_id: orderId, razorpay_payment_id: paymentId, last_error: null });

  const mail = await sendReceivedEmail(db, orderId!);
  await setIntent(db, razorpayOrderId, { email_status: mail.detail });
  console.log("[finalize] order saved", orderNumber, "email:", mail.detail);

  return { ok: true, order_id: orderId!, order_number: orderNumber!, total, payment_id: paymentId, email_sent: mail.sent, duplicate };
}
