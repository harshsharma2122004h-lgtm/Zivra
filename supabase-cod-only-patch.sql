-- ZIVRA Razorpay Live Payments
-- Run this once in Supabase Dashboard -> SQL Editor.
-- Removes the temporary COD-only guard and stores unique gateway payment references.
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders
  add constraint orders_payment_method_check check (payment_method in ('cod','online'));
alter table public.orders
  add column if not exists razorpay_order_id text,
  add column if not exists razorpay_payment_id text;
create unique index if not exists orders_razorpay_order_id_uidx
  on public.orders(razorpay_order_id) where razorpay_order_id is not null;
create unique index if not exists orders_razorpay_payment_id_uidx
  on public.orders(razorpay_payment_id) where razorpay_payment_id is not null;
