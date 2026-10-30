-- ZIVRA launch hardening: COD-only until a verified payment gateway is integrated.
-- Run once in Supabase SQL Editor after the base supabase-schema.sql.
alter table public.orders
  drop constraint if exists orders_payment_method_check;

alter table public.orders
  add constraint orders_payment_method_check
  check (payment_method = 'cod');
