-- ZIVRA Supabase starter schema
-- Run once in Supabase Dashboard -> SQL Editor.
-- Admin authorization uses the server-managed app_metadata.role = 'admin'.
-- Never set admin role from user-editable user_metadata.

create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text unique,
  name text not null,
  description text not null default '',
  category text not null check (category in ('Streetwear','Ethnic','Accessories')),
  price numeric(10,2) not null check (price >= 0),
  compare_at_price numeric(10,2) check (compare_at_price is null or compare_at_price >= price),
  stock integer not null default 0 check (stock >= 0),
  image_url text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('ZV-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  customer_name text not null,
  email text not null,
  phone text not null,
  address text not null,
  city text not null,
  pincode text not null,
  payment_method text not null check (payment_method in ('cod','online')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  status text not null default 'pending' check (status in ('pending','confirmed','processing','shipped','delivered','cancelled')),
  subtotal numeric(10,2) not null check (subtotal >= 0),
  shipping numeric(10,2) not null default 0 check (shipping >= 0),
  total numeric(10,2) not null check (total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  sku text,
  quantity integer not null check (quantity > 0 and quantity <= 20),
  size text not null default 'M',
  color text not null default 'Default',
  unit_price numeric(10,2) not null check (unit_price >= 0),
  line_total numeric(10,2) not null check (line_total >= 0)
);

create index if not exists products_active_category_idx on public.products(is_active, category);
create index if not exists orders_created_at_idx on public.orders(created_at desc);
create index if not exists order_items_order_id_idx on public.order_items(order_id);

create or replace function public.zivra_is_admin()
returns boolean
language sql stable
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products"
on public.products for select
using (is_active = true or public.zivra_is_admin());

drop policy if exists "Admins manage products" on public.products;
create policy "Admins manage products"
on public.products for all
using (public.zivra_is_admin())
with check (public.zivra_is_admin());

drop policy if exists "Admins view orders" on public.orders;
create policy "Admins view orders"
on public.orders for select
using (public.zivra_is_admin());

drop policy if exists "Admins update orders" on public.orders;
create policy "Admins update orders"
on public.orders for update
using (public.zivra_is_admin())
with check (public.zivra_is_admin());

drop policy if exists "Admins view order items" on public.order_items;
create policy "Admins view order items"
on public.order_items for select
using (public.zivra_is_admin());

-- Guest checkout: prices and totals are recalculated from the database.
-- The browser cannot directly insert orders or choose the final order total.
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
  v_subtotal numeric(10,2) := 0;
  v_shipping numeric(10,2) := 0;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty integer;
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

  insert into public.orders(customer_name,email,phone,address,city,pincode,payment_method,subtotal,shipping,total)
  values(v_name,v_email,v_phone,v_address,v_city,v_pincode,v_payment,0,0,0)
  returning id, order_number into v_order_id, v_order_number;

  for v_item in select value from jsonb_array_elements(payload->'items')
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 20 then raise exception 'Invalid item quantity'; end if;

    select * into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid and is_active = true
    for update;

    if not found then raise exception 'A product in your cart is unavailable'; end if;
    if v_product.stock < v_qty then raise exception 'Insufficient stock for %', v_product.name; end if;

    v_subtotal := v_subtotal + (v_product.price * v_qty);
    insert into public.order_items(order_id,product_id,product_name,sku,quantity,size,color,unit_price,line_total)
    values(v_order_id,v_product.id,v_product.name,v_product.sku,v_qty,
      left(coalesce(v_item->>'size','M'),20),
      left(coalesce(v_item->>'color','Default'),40),
      v_product.price,v_product.price*v_qty);

    update public.products set stock = stock - v_qty, updated_at = now()
    where id = v_product.id;
  end loop;

  v_shipping := case when v_subtotal >= 1999 then 0 else 99 end;
  update public.orders
  set subtotal=v_subtotal, shipping=v_shipping, total=v_subtotal+v_shipping
  where id=v_order_id;

  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,
    'subtotal',v_subtotal,'shipping',v_shipping,'total',v_subtotal+v_shipping);
exception when others then
  raise;
end;
$$;

revoke all on function public.zivra_place_order(jsonb) from public;
grant execute on function public.zivra_place_order(jsonb) to anon, authenticated;

-- Important launch notes:
-- 1) Add products to public.products from the Admin Panel after admin auth is connected.
-- 2) In Supabase Auth, set app_metadata.role = 'admin' for the approved admin user.
-- 3) Online payment is NOT activated by this schema. Connect a payment provider/server webhook first.
-- 4) Add CAPTCHA/rate limiting before accepting public guest orders at scale.
