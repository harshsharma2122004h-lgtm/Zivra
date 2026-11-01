import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};
const corsHeaders = (req: Request) => ({
  ...cors,
  "Access-Control-Allow-Headers": req.headers.get("Access-Control-Request-Headers") ||
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Vary": "Origin, Access-Control-Request-Headers",
});
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const titles: Record<string,string> = {
  received: "We’ve received your order",
  confirmed: "Your ZIVRA order is confirmed",
  processing: "Your ZIVRA order is being prepared",
  shipped: "Your ZIVRA order is on its way",
  out_for_delivery: "Your ZIVRA order is out for delivery",
  delivered: "Your ZIVRA order has been delivered",
};
const headings: Record<string,string> = {
  received: "ORDER RECEIVED", confirmed: "ORDER CONFIRMED", processing: "PREPARING YOUR ORDER",
  shipped: "ON THE WAY", out_for_delivery: "OUT FOR DELIVERY", delivered: "DELIVERED",
};
const intro: Record<string,string> = {
  received: "Thank you for choosing ZIVRA. Your order has reached us successfully.",
  confirmed: "Good news — your order is confirmed. We’re getting everything ready.",
  processing: "Our team is carefully preparing your selected pieces.",
  shipped: "Your parcel has left us. Use the shipment details below to follow its journey.",
  out_for_delivery: "Your parcel is with the delivery partner and is expected to reach you soon.",
  delivered: "Your ZIVRA order has been marked delivered. We hope you love it.",
};
const esc = (v: unknown) => String(v ?? "").replace(/[&<>"]/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]!));
const money = (v: unknown) => "₹" + Number(v || 0).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function renderEmail(kind: string, order: any, items: any[]) {
  const accent = kind === "received" ? "#d52b35" : kind === "shipped" || kind === "out_for_delivery" ? "#191919" : kind === "delivered" ? "#555" : "#b91f2b";
  const rows = items.map((x:any) => `<tr><td style="padding:12px 8px;border-bottom:1px solid #e8e8e8"><b>${esc(x.product_name)}</b><br><span style="color:#777;font-size:12px">Size ${esc(x.size)} · ${esc(x.color)} · Qty ${Number(x.quantity)}</span></td><td align="right" style="padding:12px 8px;border-bottom:1px solid #e8e8e8;white-space:nowrap">${money(x.line_total)}</td></tr>`).join("");
  const shipment = ["shipped","out_for_delivery"].includes(kind) ? `<div style="margin:22px 0;padding:18px;background:#f5f5f5;border-left:4px solid ${accent}"><b>SHIPMENT DETAILS</b><p style="margin:10px 0 4px">Courier: ${esc(order.courier_name || "Not provided")}</p><p style="margin:4px 0">Tracking / AWB: ${esc(order.tracking_number || "Not provided")}</p>${order.tracking_url ? `<a href="${esc(order.tracking_url)}" style="display:inline-block;margin-top:10px;padding:12px 18px;background:${accent};color:#fff;text-decoration:none;font-weight:bold">TRACK YOUR ORDER</a>` : ""}</div>` : "";
  const accentBlock = kind === "received" ? "background:#fff0f0;border:1px solid #f3c7ca" : kind === "delivered" ? "background:#f1f1f1;border:1px solid #ddd" : "background:#f7f7f7;border:1px solid #e5e5e5";
  const address = [order.address,order.city,order.pincode].filter(Boolean).join(", ");
  const html = `<!doctype html><html><body style="margin:0;background:#eeeeee;font-family:Arial,Helvetica,sans-serif;color:#191919"><div style="max-width:640px;margin:24px auto;background:#fff"><div style="padding:24px 30px;background:#111;color:#fff;border-bottom:6px solid #d52b35"><div style="font-size:28px;font-weight:900;letter-spacing:7px">ZIVRA</div><div style="font-size:10px;letter-spacing:3px;color:#ddd;margin-top:6px">STYLE IN EVERY DETAIL</div></div><div style="padding:30px"><div style="font-size:11px;letter-spacing:3px;font-weight:bold;color:${accent}">${headings[kind]}</div><h1 style="font-size:30px;line-height:1.15;margin:12px 0 10px">${titles[kind]}</h1><p style="font-size:15px;line-height:1.7;color:#555">${esc(order.customer_name)}, ${intro[kind]}</p><div style="padding:18px;margin:22px 0;${accentBlock}"><div style="font-size:10px;letter-spacing:2px;color:#666">ORDER NUMBER</div><div style="font-size:23px;font-weight:900;margin-top:5px">${esc(order.order_number)}</div><div style="font-size:12px;color:#666;margin-top:7px">${new Date(order.created_at).toLocaleString("en-IN",{dateStyle:"medium",timeStyle:"short",timeZone:"Asia/Kolkata"})}</div></div><h2 style="font-size:16px;border-bottom:2px solid #191919;padding-bottom:10px">YOUR ORDER</h2><table role="presentation" width="100%" cellspacing="0" cellpadding="0">${rows}</table><div style="padding:16px 8px;text-align:right"><span style="color:#666;font-size:13px">Order total</span><div style="font-size:25px;font-weight:900;margin-top:5px">${money(order.total)}</div><div style="font-size:12px;color:#666;margin-top:5px">Payment: Cash on Delivery</div></div>${shipment}<div style="margin-top:22px;padding:18px;background:#f7f7f7"><b style="font-size:13px">DELIVERY ADDRESS</b><p style="font-size:13px;line-height:1.6;color:#555;margin-bottom:0">${esc(address)}<br>Phone: ${esc(order.phone)}</p></div><p style="font-size:13px;line-height:1.7;color:#555;margin-top:25px">Need help? Contact <a href="mailto:Zivrasupport@gmail.com" style="color:#c12631">Zivrasupport@gmail.com</a>.</p></div><div style="padding:20px 30px;background:#111;color:#bbb;font-size:11px;line-height:1.7">THANK YOU FOR SHOPPING WITH ZIVRA<br><span style="color:#fff;font-weight:bold;letter-spacing:2px">ZIVRA SUPPORT</span><br>This is an order-related service email.</div></div></body></html>`;
  const text = `ZIVRA — ${titles[kind]}\nOrder: ${order.order_number}\nCustomer: ${order.customer_name}\nItems: ${items.map((x:any)=>x.product_name+" x "+x.quantity+" — "+money(x.line_total)).join("; ")}\nTotal: ${money(order.total)}\nPayment: Cash on Delivery\nDelivery: ${address}\nCourier: ${order.courier_name||"—"}\nTracking: ${order.tracking_number||"—"}\n${order.tracking_url||""}\nSupport: Zivrasupport@gmail.com`;
  return { subject: `ZIVRA | ${titles[kind]} | ${order.order_number}`, html, text };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const body = await req.json();
    const orderId = String(body.order_id || "");
    const kind = String(body.type || "");
    if (!/^[0-9a-f-]{36}$/i.test(orderId) || !titles[kind]) return json({ error: "Invalid order or email type" }, 400);

    const adminDb = createClient(url, serviceKey);
    if (kind !== "received") {
      if (!token) return json({ error: "Admin sign-in required" }, 401);
      const authClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
      const { data: { user }, error: authError } = await authClient.auth.getUser();
      if (authError || user?.app_metadata?.role !== "admin") return json({ error: "Admin access required" }, 403);
    }

    const { data: order, error: orderError } = await adminDb.from("orders").select("*,order_items(*)").eq("id", orderId).single();
    if (orderError || !order) return json({ error: "Order not found" }, 404);
    if (kind === "received") {
      const { data: prior } = await adminDb.from("zivra_email_logs").select("id").eq("order_id",orderId).eq("email_type","received").limit(1).maybeSingle();
      if (prior) return json({ ok: true, already_sent: true });
    }
    if (!order.email) return json({ error: "Customer email is missing" }, 400);
    if (["shipped","out_for_delivery"].includes(kind) && (!order.courier_name || !order.tracking_number || !order.tracking_url)) return json({ error: "Save courier, AWB and tracking URL before sending this email." }, 400);

    const scriptUrl = Deno.env.get("GMAIL_SCRIPT_URL");
    const scriptToken = Deno.env.get("GMAIL_SCRIPT_TOKEN");
    if (!scriptUrl || !scriptToken) return json({ error: "Email service is not configured. Add GMAIL_SCRIPT_URL and GMAIL_SCRIPT_TOKEN to Supabase Edge Function secrets." }, 503);
    const mail = renderEmail(kind, order, order.order_items || []);
    const relayPayload = JSON.stringify({
      token: scriptToken,
      to: order.email,
      subject: mail.subject,
      htmlBody: mail.html,
      textBody: mail.text,
      replyTo: "Zivrasupport@gmail.com",
      orderId,
      emailType: kind,
    });
    // Follow the Apps Script ContentService redirect automatically.
    // Google may convert the response redirect to GET; manually reposting the body
    // to the redirected googleusercontent URL can fail after Gmail has already sent.
    const sendResponse = await fetch(scriptUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: relayPayload,
      redirect: "follow",
    });
    const relayResponseText = await sendResponse.text();
    let sendResult: any = {};
    try {
      sendResult = JSON.parse(relayResponseText);
    } catch {
      console.error("ZIVRA Gmail relay returned non-JSON:", sendResponse.status, sendResponse.headers.get("content-type"), relayResponseText.slice(0, 1200));
      return json({
        error: "Google Apps Script returned an unexpected response. Check that the Web App URL ends in /exec and that its latest deployment is active.",
        relay_status: sendResponse.status,
        relay_content_type: sendResponse.headers.get("content-type") || "unknown",
      }, 502);
    }
    if (!sendResponse.ok || sendResult.ok !== true) {
      console.error("ZIVRA Gmail delivery failed:", sendResponse.status, sendResult);
      return json({
        error: sendResult.error || "Gmail could not send this email.",
        relay_status: sendResponse.status,
      }, 502);
    }

    const { error: logError } = await adminDb.from("zivra_email_logs").insert({ order_id: orderId, email_type: kind, recipient: order.email, sent_by: kind === "received" ? "checkout" : "admin" });
    if (logError) console.error("ZIVRA email log insert failed:", logError);
    return json({ ok: true, recipient: order.email, type: kind });
  } catch (error) {
    console.error("ZIVRA email error:", error);
    return json({ error: error instanceof Error ? error.message : "Email could not be sent" }, 500);
  }
});
