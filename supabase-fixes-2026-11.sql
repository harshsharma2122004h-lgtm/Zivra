-- ZIVRA repair migration (Nov 2026)
-- Run ONCE in Supabase Dashboard -> SQL Editor, BEFORE pushing the matching code.
-- Safe to re-run. Does not delete any orders, products or customers.
--
-- What this does
--  1. COD duplicate protection at DATABASE level (idempotency key on orders).
--  2. Voucher moved out of source code into a private table (hash only) and
--     matched ignoring case / spaces / dash style, same for COD and online.
--  3. Payment ledger (zivra_payment_intents): every Razorpay order is recorded
--     with validated cart + customer BEFORE checkout opens, so a captured
--     payment can always be turned into an order, exactly once.
--  4. Idempotent paid-order functions (repeat callback returns the same order).
--  5. Email log constraint fixed so the owner alert can be logged.

-- ---------------------------------------------------------------- 1. COD idempotency
alter table public.orders add column if not exists idempotency_key text;
create unique index if not exists orders_idempotency_key_uidx
  on public.orders(idempotency_key) where idempotency_key is not null;

-- ---------------------------------------------------------------- 2. Private voucher
create table if not exists public.zivra_vouchers (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  label text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.zivra_vouchers enable row level security;
revoke all on public.zivra_vouchers from anon, authenticated;

-- sha256 of the normalised owner voucher (upper-case letters+digits only).
-- The real code is NOT stored anywhere in the repository or database.
insert into public.zivra_vouchers(code_hash, label)
values ('8cae4dbb58fb1393e61ace8796b89b34052854c5ccb31f8238dc883ef9a8cac8', 'Owner free-shipping voucher')
on conflict (code_hash) do nothing;

create or replace function public.zivra_voucher_ok(p_code text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.zivra_vouchers v
    where v.active
      and v.code_hash = encode(sha256(convert_to(
            regexp_replace(upper(coalesce(p_code, '')), '[^A-Z0-9]', '', 'g'), 'UTF8')), 'hex')
  );
$$;
revoke all on function public.zivra_voucher_ok(text) from public, anon, authenticated;
grant execute on function public.zivra_voucher_ok(text) to service_role;

-- ---------------------------------------------------------------- 3. zivra_place_order (idempotent)
-- Same rules as before (prices/stock/shipping from the database); adds idempotency.
create or replace function public.zivra_place_order(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_name text := trim(coalesce(payload->>'customer_name',''));
  v_email text := lower(trim(coalesce(payload->>'email','')));
  v_phone text := trim(coalesce(payload->>'phone',''));
  v_address text := trim(coalesce(payload->>'address',''));
  v_city text := trim(coalesce(payload->>'city',''));
  v_pincode text := trim(coalesce(payload->>'pincode',''));
  v_payment text := coalesce(payload->>'payment_method','cod');
  v_key text := nullif(left(trim(coalesce(payload->>'idempotency_key','')), 80), '');
  v_subtotal numeric(10,2) := 0;
  v_shipping numeric(10,2) := 0;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty integer;
  v_existing record;
begin
  if v_name = '' or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or v_phone = '' or v_address = '' or v_city = '' or v_pincode = '' then
    raise exception 'Please provide valid delivery and contact details';
  end if;
  if v_payment not in ('cod','online') then raise exception 'Invalid payment method'; end if;
  if jsonb_typeof(payload->'items') <> 'array'
     or jsonb_array_length(payload->'items') < 1
     or jsonb_array_length(payload->'items') > 20 then
    raise exception 'Invalid cart';
  end if;

  if v_key is not null then
    select id, order_number, subtotal, shipping, total into v_existing
    from public.orders where idempotency_key = v_key;
    if found then
      return jsonb_build_object('id',v_existing.id,'order_number',v_existing.order_number,
        'subtotal',v_existing.subtotal,'shipping',v_existing.shipping,'total',v_existing.total,'duplicate',true);
    end if;
  end if;

  insert into public.orders(customer_name,email,phone,address,city,pincode,payment_method,subtotal,shipping,total,idempotency_key)
  values(v_name,v_email,v_phone,v_address,v_city,v_pincode,v_payment,0,0,0,v_key)
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning id, order_number into v_order_id, v_order_number;

  if v_order_id is null then
    select id, order_number, subtotal, shipping, total into v_existing
    from public.orders where idempotency_key = v_key;
    return jsonb_build_object('id',v_existing.id,'order_number',v_existing.order_number,
      'subtotal',v_existing.subtotal,'shipping',v_existing.shipping,'total',v_existing.total,'duplicate',true);
  end if;

  for v_item in select value from jsonb_array_elements(payload->'items')
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 20 then raise exception 'Invalid item quantity'; end if;
    select * into v_product from public.products
    where id = (v_item->>'product_id')::uuid and is_active = true for update;
    if not found then raise exception 'A product in your cart is unavailable'; end if;
    if v_product.stock < v_qty then raise exception 'Insufficient stock for %', v_product.name; end if;
    v_subtotal := v_subtotal + (v_product.price * v_qty);
    insert into public.order_items(order_id,product_id,product_name,sku,quantity,size,color,unit_price,line_total)
    values(v_order_id,v_product.id,v_product.name,v_product.sku,v_qty,
      left(coalesce(v_item->>'size','M'),20), left(coalesce(v_item->>'color','Default'),40),
      v_product.price,v_product.price*v_qty);
    update public.products set stock = stock - v_qty, updated_at = now() where id = v_product.id;
  end loop;

  v_shipping := case when v_subtotal >= 1999 then 0 else 99 end;
  update public.orders set subtotal=v_subtotal, shipping=v_shipping, total=v_subtotal+v_shipping where id=v_order_id;
  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,
    'subtotal',v_subtotal,'shipping',v_shipping,'total',v_subtotal+v_shipping);
end;
$$;

create or replace function public.zivra_place_order_with_voucher(payload jsonb, p_voucher_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_order jsonb;
begin
  if not public.zivra_voucher_ok(p_voucher_code) then raise exception 'Invalid voucher code'; end if;
  v_order := public.zivra_place_order(payload);
  if coalesce((v_order->>'duplicate')::boolean, false) then return v_order; end if;
  update public.orders set shipping=0,total=subtotal where id=(v_order->>'id')::uuid;
  return v_order || jsonb_build_object('shipping',0,'total',(v_order->>'subtotal')::numeric,'voucher_applied',true);
end;
$$;

-- ---------------------------------------------------------------- 4. Paid orders (idempotent)
create or replace function public.zivra_place_paid_order_v2(
  payload jsonb, p_razorpay_order_id text, p_razorpay_payment_id text, p_free_shipping boolean default false
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_order jsonb; v_existing record; v_id uuid;
  v_shipping numeric(10,2); v_total numeric(10,2);
begin
  if p_razorpay_order_id !~ '^order_[A-Za-z0-9]+$'
     or p_razorpay_payment_id !~ '^pay_[A-Za-z0-9]+$' then raise exception 'Invalid payment reference'; end if;
  perform pg_advisory_xact_lock(hashtext(p_razorpay_order_id));
  select id,order_number,subtotal,shipping,total,payment_status,status into v_existing
  from public.orders where razorpay_order_id=p_razorpay_order_id or razorpay_payment_id=p_razorpay_payment_id limit 1;
  if found then
    return jsonb_build_object('id',v_existing.id,'order_number',v_existing.order_number,
      'subtotal',v_existing.subtotal,'shipping',v_existing.shipping,'total',v_existing.total,
      'payment_status',v_existing.payment_status,'status',v_existing.status,'duplicate',true);
  end if;
  v_order := public.zivra_place_order(payload - 'idempotency_key');
  v_id := (v_order->>'id')::uuid;
  update public.orders set payment_status='paid',status='confirmed',
    razorpay_order_id=p_razorpay_order_id,razorpay_payment_id=p_razorpay_payment_id,
    shipping=case when p_free_shipping then 0 else shipping end,
    total=case when p_free_shipping then subtotal else total end
  where id=v_id returning shipping,total into v_shipping,v_total;
  return v_order || jsonb_build_object('shipping',v_shipping,'total',v_total,'payment_status','paid','status','confirmed');
end;
$$;
revoke all on function public.zivra_place_paid_order_v2(jsonb,text,text,boolean) from public,anon,authenticated;
grant execute on function public.zivra_place_paid_order_v2(jsonb,text,text,boolean) to service_role;

create or replace function public.zivra_place_paid_order(payload jsonb,p_razorpay_order_id text,p_razorpay_payment_id text)
returns jsonb language sql security definer set search_path=public,pg_temp
as $$ select public.zivra_place_paid_order_v2(payload,p_razorpay_order_id,p_razorpay_payment_id,false) $$;
revoke all on function public.zivra_place_paid_order(jsonb,text,text) from public,anon,authenticated;
grant execute on function public.zivra_place_paid_order(jsonb,text,text) to service_role;

create or replace function public.zivra_place_paid_order_with_voucher(payload jsonb,p_razorpay_order_id text,p_razorpay_payment_id text,p_voucher_code text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.zivra_voucher_ok(p_voucher_code) then raise exception 'Invalid voucher code'; end if;
  return public.zivra_place_paid_order_v2(payload,p_razorpay_order_id,p_razorpay_payment_id,true);
end;
$$;
revoke all on function public.zivra_place_paid_order_with_voucher(jsonb,text,text,text) from public,anon,authenticated;
grant execute on function public.zivra_place_paid_order_with_voucher(jsonb,text,text,text) to service_role;

-- ---------------------------------------------------------------- 5. Payment ledger
create table if not exists public.zivra_payment_intents (
  razorpay_order_id text primary key,
  amount_paise integer not null check (amount_paise >= 100),
  free_shipping boolean not null default false,
  customer jsonb not null,
  items jsonb not null,
  status text not null default 'created' check (status in ('created','fulfilled','needs_review')),
  razorpay_payment_id text, order_id uuid references public.orders(id) on delete set null,
  email_status text, last_error text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists zivra_payment_intents_status_idx on public.zivra_payment_intents(status,created_at desc);
alter table public.zivra_payment_intents enable row level security;
revoke all on public.zivra_payment_intents from anon,authenticated;
drop policy if exists "Admins view payment intents" on public.zivra_payment_intents;
create policy "Admins view payment intents" on public.zivra_payment_intents
for select to authenticated using ((auth.jwt()->'app_metadata'->>'role')='admin');
grant select on public.zivra_payment_intents to authenticated;

-- ---------------------------------------------------------------- 6. Email log constraint
alter table public.zivra_email_logs drop constraint if exists zivra_email_logs_email_type_check;
alter table public.zivra_email_logs add constraint zivra_email_logs_email_type_check
check (email_type in ('received','admin_alert','confirmed','processing','shipped','out_for_delivery','delivered','cancelled'));
notify pgrst, 'reload schema';
