import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={ "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}});
serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST") return reply({error:"Method not allowed"},405);
 try{
  const keyId=Deno.env.get("RAZORPAY_KEY_ID"), secret=Deno.env.get("RAZORPAY_KEY_SECRET");
  if(!keyId||!secret) return reply({error:"Razorpay is not configured on the server."},503);
  const url=Deno.env.get("SUPABASE_URL")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db=createClient(url,service);
  const body=await req.json(), items=body.items;\n  const voucherCode=String(body.voucher_code||"").trim().toUpperCase();\n  if(voucherCode && voucherCode!=="ZV-OWNER-7KQ9-M4PX") return reply({error:"Invalid voucher code."},400);
  if(!Array.isArray(items)||!items.length||items.length>20) return reply({error:"Invalid cart."},400);
  let subtotal=0;
  for(const item of items){
   const qty=Number(item.quantity);
   if(!Number.isInteger(qty)||qty<1||qty>20) return reply({error:"Invalid item quantity."},400);
   const {data:p,error}=await db.from("products").select("id,price,stock,is_active").eq("id",item.product_id).single();
   if(error||!p||!p.is_active||p.stock<qty) return reply({error:"A product is unavailable or out of stock."},409);
   subtotal+=Number(p.price)*qty;
  }
  const shipping=voucherCode?0:(subtotal>=1999?0:99);\n  const total=subtotal+shipping, amount=Math.round(total*100);
  if(!Number.isSafeInteger(amount)||amount<100) return reply({error:"Invalid payment amount."},400);
  const auth=btoa(keyId+":"+secret);
  const response=await fetch("https://api.razorpay.com/v1/orders",{method:"POST",headers:{"Authorization":"Basic "+auth,"Content-Type":"application/json"},body:JSON.stringify({amount,currency:"INR",receipt:"zivra_"+crypto.randomUUID().replaceAll("-","").slice(0,20),notes:{store:"ZIVRA"}})});
  const result=await response.json();
  if(!response.ok) return reply({error:result?.error?.description||"Razorpay could not create the payment order."},502);
  return reply({key_id:keyId,razorpay_order_id:result.id,amount:result.amount,currency:result.currency});
 }catch(e){console.error(e);return reply({error:e instanceof Error?e.message:"Payment setup failed."},500)}
});