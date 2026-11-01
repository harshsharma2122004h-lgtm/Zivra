import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={ "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});
const hex=(bytes:Uint8Array)=>Array.from(bytes).map(x=>x.toString(16).padStart(2,"0")).join("");
serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST") return reply({error:"Method not allowed"},405);
 try{
  const secret=Deno.env.get("RAZORPAY_KEY_SECRET");
  if(!secret) return reply({error:"Razorpay secret is not configured."},503);
  const body=await req.json();
  const orderId=String(body.razorpay_order_id||""),paymentId=String(body.razorpay_payment_id||""),signature=String(body.razorpay_signature||"");
  if(!/^order_[A-Za-z0-9]+$/.test(orderId)||!/^pay_[A-Za-z0-9]+$/.test(paymentId)||!/^[a-f0-9]{64}$/i.test(signature)) return reply({error:"Invalid payment verification details."},400);
  const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const digest=new Uint8Array(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(orderId+"|"+paymentId)));
  const expected=hex(digest);
  const supplied=signature.toLowerCase();
  let diff=expected.length ^ supplied.length;
  for(let i=0;i<expected.length;i++) diff |= expected.charCodeAt(i) ^ (supplied.charCodeAt(i) || 0);
  if(diff!==0) return reply({error:"Payment signature verification failed."},400);
  const url=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,keyId=Deno.env.get("RAZORPAY_KEY_ID");
  if(!keyId) return reply({error:"Razorpay Key ID is not configured."},503);
  const db=createClient(url,service);
  const paymentResponse=await fetch("https://api.razorpay.com/v1/payments/"+paymentId,{headers:{"Authorization":"Basic "+btoa(keyId+":"+secret)}});
  const paymentData=await paymentResponse.json();
  if(!paymentResponse.ok||paymentData.order_id!==orderId||paymentData.status!=="captured") return reply({error:"Razorpay has not confirmed a captured payment."},400);
  const customer=body.customer||{},items=body.items;
  const voucherCode=String(body.voucher_code||"").trim().toUpperCase();
  if(voucherCode && voucherCode!=="ZV-OWNER-7KQ9-M4PX") return reply({error:"Invalid voucher code."},400);
  if(!Array.isArray(items)||!items.length||items.length>20) return reply({error:"Invalid cart."},400);
  let subtotal=0;
  for(const item of items){
   const qty=Number(item.quantity);
   if(!Number.isInteger(qty)||qty<1||qty>20) return reply({error:"Invalid item quantity."},400);
   const {data:p,error}=await db.from("products").select("id,price,stock,is_active").eq("id",item.product_id).single();
   if(error||!p||!p.is_active||p.stock<qty) return reply({error:"A product is unavailable or out of stock. Contact ZIVRA support for your payment refund."},409);
   subtotal+=Number(p.price)*qty;
  }
  const shipping=voucherCode?0:(subtotal>=1999?0:99);
  const expectedAmount=Math.round((subtotal+shipping)*100);
  if(Number(paymentData.amount)!==expectedAmount||paymentData.currency!=="INR") return reply({error:"Paid amount does not match this cart. Contact ZIVRA support."},400);
  const payload={customer_name:String(customer.name||""),email:String(customer.email||""),phone:String(customer.phone||""),address:String(customer.address||""),city:String(customer.city||""),pincode:String(customer.pincode||""),payment_method:"online",items};
  const {data:placed,error}=await db.rpc(voucherCode?"zivra_place_paid_order_with_voucher":"zivra_place_paid_order",voucherCode?{
   payload,
   p_razorpay_order_id:orderId,
   p_razorpay_payment_id:paymentId,
   p_voucher_code:voucherCode
  }:{payload,p_razorpay_order_id:orderId,p_razorpay_payment_id:paymentId});
  if(error) {
   // A repeated callback may arrive after a successful order. Never create a second order.
   const {data:existing}=await db.from("orders")
    .select("id,order_number,total,payment_status")
    .eq("razorpay_payment_id",paymentId)
    .maybeSingle();
   if(existing?.payment_status==="paid") {
    return reply({ok:true,order_id:existing.id,order_number:existing.order_number,total:existing.total,payment_id:paymentId});
   }
   throw error;
  }
  return reply({ok:true,order_id:placed.id,order_number:placed.order_number,total:placed.total,payment_id:paymentId});
 }catch(e){console.error(e);return reply({error:e instanceof Error?e.message:"Payment could not be verified and order was not completed."},500)}
});