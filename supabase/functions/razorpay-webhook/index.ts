import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { finalizePayment, hmacHex, safeEqual } from "../_shared/finalize.ts";

// Server-to-server safety net: Razorpay calls this when a payment is captured, even if the
// customer closed the tab. Configure RAZORPAY_WEBHOOK_SECRET in Supabase and Razorpay.
serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const whSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET"), secret = Deno.env.get("RAZORPAY_KEY_SECRET"), keyId = Deno.env.get("RAZORPAY_KEY_ID");
  if (!whSecret || !secret || !keyId) { console.error("[webhook] secrets not configured"); return new Response("Not configured", { status: 503 }); }
  const raw = await req.text();
  const sig = (req.headers.get("x-razorpay-signature") || "").toLowerCase();
  if (!sig || !safeEqual(await hmacHex(whSecret, raw), sig)) { console.warn("[webhook] bad signature"); return new Response("Bad signature", { status: 401 }); }
  try {
    const event = JSON.parse(raw);
    if (event.event !== "payment.captured") return new Response("ignored", { status: 200 });
    const p = event.payload?.payment?.entity;
    const orderId = String(p?.order_id || ""), paymentId = String(p?.id || "");
    if (!/^order_[A-Za-z0-9]+$/.test(orderId) || !/^pay_[A-Za-z0-9]+$/.test(paymentId)) return new Response("ignored", { status: 200 });
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const result = await finalizePayment(db, { keyId, secret }, orderId, paymentId);
    console.log("[webhook] result", orderId, paymentId, result.ok ? "ok" : result.code);
    return new Response(result.ok || !result.retryable ? "ok" : "retry", { status: result.ok || !result.retryable ? 200 : 500 });
  } catch (e) {
    console.error("[webhook] unexpected", e);
    return new Response("error", { status: 500 });
  }
});
