import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { finalizePayment, hmacHex, safeEqual } from "../_shared/finalize.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Browser callback after Razorpay Checkout. The browser sends ONLY the Razorpay ids + signature;
// cart, customer and amount come from the server-side ledger written by create-razorpay-order.
// Business outcomes are returned with HTTP 200 and { ok:false, error, retryable } so the page can show the real message.
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  try {
    const secret = Deno.env.get("RAZORPAY_KEY_SECRET"), keyId = Deno.env.get("RAZORPAY_KEY_ID");
    if (!secret || !keyId) { console.error("[verify] Razorpay secrets missing"); return reply({ ok: false, error: "Payment service is not configured.", retryable: false }, 503); }
    const body = await req.json();
    const orderId = String(body.razorpay_order_id || ""), paymentId = String(body.razorpay_payment_id || ""), signature = String(body.razorpay_signature || "");
    if (!/^order_[A-Za-z0-9]+$/.test(orderId) || !/^pay_[A-Za-z0-9]+$/.test(paymentId) || !/^[a-f0-9]{64}$/i.test(signature)) {
      console.warn("[verify] malformed verification details");
      return reply({ ok: false, error: "Invalid payment verification details.", retryable: false }, 400);
    }
    const expected = await hmacHex(secret, orderId + "|" + paymentId);
    if (!safeEqual(expected, signature.toLowerCase())) {
      console.warn("[verify] bad signature", orderId, paymentId);
      return reply({ ok: false, error: "Payment signature verification failed.", retryable: false }, 400);
    }
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const result = await finalizePayment(db, { keyId, secret }, orderId, paymentId);
    console.log("[verify] result", orderId, paymentId, result.ok ? "ok" : result.code);
    return reply(result);
  } catch (e) {
    console.error("[verify] unexpected", e);
    return reply({ ok: false, error: "Payment could not be verified right now.", retryable: true }, 500);
  }
});