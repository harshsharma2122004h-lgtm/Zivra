-- ZIVRA payment idempotency hardening
-- Run once in Supabase SQL Editor after the existing Razorpay columns/indexes exist.
-- The order creation and payment-reference write happen in one transaction.
create or replace function public.zivra_place_paid_order(
  payload jsonb,
  p_razorpay_order_id text,
  p_razorpay_payment_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order jsonb;
  v_order_id uuid;
begin
  if p_razorpay_order_id !~ '^order_[A-Za-z0-9]+$'
     or p_razorpay_payment_id !~ '^pay_[A-Za-z0-9]+$' then
    raise exception 'Invalid payment reference';
  end if;

  -- Unique indexes on orders make a repeated payment callback fail atomically.
  if exists (
    select 1 from public.orders
    where razorpay_order_id = p_razorpay_order_id
       or razorpay_payment_id = p_razorpay_payment_id
  ) then
    raise exception 'This payment has already been applied to an order';
  end if;

  v_order := public.zivra_place_order(payload);
  v_order_id := (v_order->>'id')::uuid;

  update public.orders
  set payment_status = 'paid',
      razorpay_order_id = p_razorpay_order_id,
      razorpay_payment_id = p_razorpay_payment_id
  where id = v_order_id;

  return v_order || jsonb_build_object('payment_status', 'paid');
end;
$$;

revoke all on function public.zivra_place_paid_order(jsonb, text, text) from public, anon, authenticated;
grant execute on function public.zivra_place_paid_order(jsonb, text, text) to service_role;
