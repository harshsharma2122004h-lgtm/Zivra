import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  try {
    const keyId = Deno.env.get("RAZORPAY_KEY_ID"), secret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !secret) return reply({ error: "Razorpay is not configured on the server." }, 503);
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await req.json(), rawItems = body.items, c = body.customer || {};

    // Validate delivery details BEFORE taking money, so a paid checkout can always become an order.
    const customer = {
      customer_name: String(c.name || "").trim(), email: String(c.email || "").trim().toLowerCase(),
      phone: String(c.phone || "").trim(), address: String(c.address || "").trim(),
      city: String(c.city || "").trim(), pincode: String(c.pincode || "").trim(),
    };
    if (!customer.customer_name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(customer.email) || !customer.phone || !customer.address || !customer.city || !customer.pincode)
      return reply({ error: "Please provide valid delivery and contact details." }, 400);

    const voucherCode = String(body.voucher_code || "").trim();
    let freeShipping = false;
    if (voucherCode) {
      const { data: ok, error: vErr } = await db.rpc("zivra_voucher_ok", { p_code: voucherCode });
      if (vErr) { console.error("[create] voucher check failed", vErr.message); return reply({ error: "Voucher could not be checked right now." }, 500); }
      if (!ok) return reply({ error: "Invalid voucher code." }, 400);
      freeShipping = true;
    }

    if (!Array.isArray(rawItems) || !rawItems.length || rawItems.length > 20) return reply({ error: "Invalid cart." }, 400);
    const items: { product_id: string; quantity: number; size: string; color: string }[] = [];
    let subtotal = 0;
    for (const item of rawItems) {
      const qty = Number(item.quantity), pid = String(item.product_id || "");
      if (!UUID.test(pid) || !Number.isInteger(qty) || qty < 1 || qty > 20) return reply({ error: "Invalid cart item." }, 400);
      const { data: p, error } = await db.from("products").select("id,price,stock,is_active").eq("id", pid).single();
      if (error || !p || !p.is_active || p.stock < qty) return reply({ error: "A product is unavailable or out of stock." }, 409);
      subtotal += Number(p.price) * qty;
      items.push({ product_id: pid, quantity: qty, size: String(item.size || "M").slice(0, 20), color: String(item.color || "Default").slice(0, 40) });
    }
    const shipping = freeShipping ? 0 : (subtotal >= 1999 ? 0 : 99);
    const amount = Math.round((subtotal + shipping) * 100);
    if (!Number.isSafeInteger(amount) || amount < 100) return reply({ error: "Invalid payment amount." }, 400);

    const response = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST", headers: { Authorization: "Basic " + btoa(keyId + ":" + secret), "Content-Type": "application/json" },
      body: JSON.stringify({ amount, currency: "INR", receipt: "zivra_" + crypto.randomUUID().replaceAll("-", "").slice(0, 20), notes: { store: "ZIVRA" } }),
    });
    const result = await response.json();
    if (!response.ok) { console.error("[create] razorpay order failed", JSON.stringify(result)); return reply({ error: result?.error?.description || "Razorpay could not create the payment order." }, 502); }

    // Durable ledger row: maps this Razorpay order to the validated cart/customer/amount.
    const { error: ledgerError } = await db.from("zivra_payment_intents").insert({
      razorpay_order_id: result.id, amount_paise: result.amount, free_shipping: freeShipping, customer, items,
    });
    if (ledgerError) { console.error("[create] ledger insert failed", ledgerError.message); return reply({ error: "Could not start payment safely. No money was taken. Please try again." }, 500); }

    console.log("[create] intent saved", result.id, result.amount);
    return reply({ key_id: keyId, razorpay_order_id: result.id, amount: result.amount, currency: result.currency });
  } catch (e) {
    console.error("[create] unexpected", e);
    return reply({ error: e instanceof Error ? e.message : "Payment setup failed." }, 500);
  }
});