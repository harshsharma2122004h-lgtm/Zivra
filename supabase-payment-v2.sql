-- ZIVRA payment finalization v2
-- Required by supabase/functions/_shared/finalize.ts.
-- Run once in Supabase SQL Editor after supabase-payment-idempotency.sql.

create or replace function public.zivra_place_paid_order_v2(
  payload jsonb,
  p_razorpay_order_id text,
  p_razorpay_payment_id text,
  p_free_shipping boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order jsonb;
  v_existing public.orders%rowtype;
  v_order_id uuid;
  v_shipping numeric(10,2);
  v_total numeric(10,2);
begin
  if p_razorpay_order_id !~ '^order_[A-Za-z0-9]+$'
     or p_razorpay_payment_id !~ '^pay_[A-Za-z0-9]+$' then
    raise exception 'Invalid payment reference';
  end if;

  select * into v_existing
  from public.orders
  where razorpay_order_id = p_razorpay_order_id
     or razorpay_payment_id = p_razorpay_payment_id
  limit 1;

  if found then
    if v_existing.razorpay_order_id is distinct from p_razorpay_order_id
       or v_existing.razorpay_payment_id is distinct from p_razorpay_payment_id then
      raise exception 'Payment reference is already linked to another order';
    end if;
    return jsonb_build_object(
      'id',v_existing.id,'order_number',v_existing.order_number,
      'subtotal',v_existing.subtotal,'shipping',v_existing.shipping,
      'total',v_existing.total,'payment_status',v_existing.payment_status,
      'status',v_existing.status,'duplicate',true
    );
  end if;

  -- This RPC recalculates product prices, locks stock rows and creates the order.
  v_order := public.zivra_place_order(payload);
  v_order_id := (v_order->>'id')::uuid;
  v_shipping := case when coalesce(p_free_shipping,false) then 0 else (v_order->>'shipping')::numeric end;
  v_total := (v_order->>'subtotal')::numeric + v_shipping;

  update public.orders
     set payment_status = 'paid',
         status = 'confirmed',
         razorpay_order_id = p_razorpay_order_id,
         razorpay_payment_id = p_razorpay_payment_id,
         shipping = v_shipping,
         total = v_total
   where id = v_order_id;

  return v_order || jsonb_build_object(
    'shipping',v_shipping,'total',v_total,
    'payment_status','paid','status','confirmed','duplicate',false
  );
end;
$$;

revoke all on function public.zivra_place_paid_order_v2(jsonb,text,text,boolean) from public, anon, authenticated;
grant execute on function public.zivra_place_paid_order_v2(jsonb,text,text,boolean) to service_role;
