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
  if(expected.length!==signature.length||!crypto.subtle.timingSafeEqual) {
   if(expected!==signature.toLowerCase()) return reply({error:"Payment signature verification failed."},400);
  } else {
   let diff=0;for(let i=0;i<expected.length;i++) diff|=expected.charCodeAt(i)^signature.toLowerCase().charCodeAt(i);
   if(diff!==0) return reply({error:"Payment signature verification failed."},400);
  }
  const url=Deno.env.get("SUPABASE_URL")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,keyId=Deno.env.get("RAZORPAY_KEY_ID");
  if(!keyId) return reply({error:"Razorpay Key ID is not configured."},503);
  const db=createClient(url,service);
  const paymentResponse=await fetch("https://api.razorpay.com/v1/payments/"+paymentId,{headers:{"Authorization":"Basic "+btoa(keyId+":"+secret)}});
  const paymentData=await paymentResponse.json();
  if(!paymentResponse.ok||paymentData.order_id!==orderId||paymentData.status!=="captured") return reply({error:"Razorpay has not confirmed a captured payment."},400);
  const customer=body.customer||{},items=body.items;
  if(!Array.isArray(items)||!items.length||items.length>20) return reply({error:"Invalid cart."},400);
  let subtotal=0;
  for(const item of items){
   const qty=Number(item.quantity);
   if(!Number.isInteger(qty)||qty<1||qty>20) return reply({error:"Invalid item quantity."},400);
   const {data:p,error}=await db.from("products").select("id,price,stock,is_active").eq("id",item.product_id).single();
   if(error||!p||!p.is_active||p.stock<qty) return reply({error:"A product is unavailable or out of stock. Contact ZIVRA support for your payment refund."},409);
   subtotal+=Number(p.price)*qty;
  }
  const expectedAmount=Math.round((subtotal+(subtotal>=1999?0:99))*100);
  if(Number(paymentData.amount)!==expectedAmount||paymentData.currency!=="INR") return reply({error:"Paid amount does not match this cart. Contact ZIVRA support."},400);
  const payload={customer_name:String(customer.name||""),email:String(customer.email||""),phone:String(customer.phone||""),address:String(customer.address||""),city:String(customer.city||""),pincode:String(customer.pincode||""),payment_method:"online",items};
  const {data:placed,error}=await db.rpc("zivra_place_order",{payload});
  if(error) throw error;
  const {error:paymentError}=await db.from("orders").update({payment_status:"paid",razorpay_order_id:orderId,razorpay_payment_id:paymentId}).eq("id",placed.id);
  if(paymentError) throw paymentError;
  return reply({ok:true,order_id:placed.id,order_number:placed.order_number,total:placed.total,payment_id:paymentId});
 }catch(e){console.error(e);return reply({error:e instanceof Error?e.message:"Payment could not be verified and order was not completed."},500)}
});