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
      status = 'confirmed',
      razorpay_order_id = p_razorpay_order_id,
      razorpay_payment_id = p_razorpay_payment_id
  where id = v_order_id;

  return v_order || jsonb_build_object('payment_status', 'paid', 'status', 'confirmed');
end;
$$;

revoke all on function public.zivra_place_paid_order(jsonb, text, text) from public, anon, authenticated;
grant execute on function public.zivra_place_paid_order(jsonb, text, text) to service_role;


-- ZIVRA private shipping voucher: free shipping only; product subtotal is unchanged.
-- The code is accepted by anyone who knows it and is never rendered on the public site.
create or replace function public.zivra_place_order_with_voucher(
  payload jsonb,
  p_voucher_code text
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
  if upper(trim(coalesce(p_voucher_code, ''))) <> 'ZV-OWNER-7KQ9-M4PX' then
    raise exception 'Invalid voucher code';
  end if;
  v_order := public.zivra_place_order(payload);
  v_order_id := (v_order->>'id')::uuid;
  update public.orders
     set shipping = 0,
         total = subtotal
   where id = v_order_id;
  return v_order || jsonb_build_object('shipping', 0, 'total', (v_order->>'subtotal')::numeric, 'voucher_applied', true);
end;
$$;

revoke all on function public.zivra_place_order_with_voucher(jsonb, text) from public;
grant execute on function public.zivra_place_order_with_voucher(jsonb, text) to anon, authenticated;

create or replace function public.zivra_place_paid_order_with_voucher(
  payload jsonb,
  p_razorpay_order_id text,
  p_razorpay_payment_id text,
  p_voucher_code text
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
  if upper(trim(coalesce(p_voucher_code, ''))) <> 'ZV-OWNER-7KQ9-M4PX' then
    raise exception 'Invalid voucher code';
  end if;
  v_order := public.zivra_place_paid_order(payload, p_razorpay_order_id, p_razorpay_payment_id);
  v_order_id := (v_order->>'id')::uuid;
  update public.orders
     set shipping = 0,
         total = subtotal
   where id = v_order_id;
  return v_order || jsonb_build_object('shipping', 0, 'total', (v_order->>'subtotal')::numeric, 'voucher_applied', true);
end;
$$;

revoke all on function public.zivra_place_paid_order_with_voucher(jsonb, text, text, text) from public, anon, authenticated;
grant execute on function public.zivra_place_paid_order_with_voucher(jsonb, text, text, text) to service_role;


-- Repair already-paid online orders that were left in pending by the earlier RPC.
update public.orders
set status = 'confirmed'
where payment_method = 'online'
  and payment_status = 'paid'
  and status = 'pending';
