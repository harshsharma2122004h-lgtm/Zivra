-- ZIVRA premium storefront + customer account foundation
-- Apply only after reviewing in Supabase SQL Editor. Additive migration: does not replace existing checkout RPCs.
begin;

alter table public.products
  add column if not exists subcategory text,
  add column if not exists theme text not null default 'streetwear',
  add column if not exists images jsonb not null default '[]'::jsonb,
  add column if not exists variants jsonb not null default '[]'::jsonb,
  add column if not exists product_badges text[] not null default '{}',
  add column if not exists product_status text not null default 'published',
  add column if not exists is_featured boolean not null default false,
  add column if not exists is_new_arrival boolean not null default false,
  add column if not exists is_bestseller boolean not null default false;

alter table public.orders
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists tracking_number text,
  add column if not exists tracking_url text,
  add column if not exists shipped_at timestamptz,
  add column if not exists delivered_at timestamptz;

create index if not exists orders_user_created_idx
  on public.orders(user_id, created_at desc) where user_id is not null;

create table if not exists public.zivra_customer_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.zivra_customer_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'Home',
  recipient_name text not null,
  phone text not null,
  address_line text not null,
  city text not null,
  state text not null default 'Rajasthan',
  pincode text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists zivra_addresses_user_idx
  on public.zivra_customer_addresses(user_id, is_default desc, created_at desc);

create table if not exists public.zivra_wishlist (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, product_id)
);
create index if not exists zivra_wishlist_product_idx on public.zivra_wishlist(product_id);

-- Published content can be read by shoppers. Only server-verified admins can change it.
create table if not exists public.zivra_site_content (
  id text primary key,
  theme text not null check (theme in ('streetwear','sanganeri','global')),
  content jsonb not null default '{}'::jsonb,
  is_published boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.zivra_customer_profiles enable row level security;
alter table public.zivra_customer_addresses enable row level security;
alter table public.zivra_wishlist enable row level security;
alter table public.zivra_site_content enable row level security;

drop policy if exists "Customer manages own profile" on public.zivra_customer_profiles;
create policy "Customer manages own profile" on public.zivra_customer_profiles
  for all to authenticated using (user_id = auth.uid() or public.zivra_is_admin())
  with check (user_id = auth.uid() or public.zivra_is_admin());

drop policy if exists "Customer manages own addresses" on public.zivra_customer_addresses;
create policy "Customer manages own addresses" on public.zivra_customer_addresses
  for all to authenticated using (user_id = auth.uid() or public.zivra_is_admin())
  with check (user_id = auth.uid() or public.zivra_is_admin());

drop policy if exists "Customer manages own wishlist" on public.zivra_wishlist;
create policy "Customer manages own wishlist" on public.zivra_wishlist
  for all to authenticated using (user_id = auth.uid() or public.zivra_is_admin())
  with check (user_id = auth.uid() or public.zivra_is_admin());

drop policy if exists "Public reads published site content" on public.zivra_site_content;
create policy "Public reads published site content" on public.zivra_site_content
  for select to anon, authenticated using (is_published = true or public.zivra_is_admin());

drop policy if exists "Admins manage site content" on public.zivra_site_content;
create policy "Admins manage site content" on public.zivra_site_content
  for all to authenticated using (public.zivra_is_admin())
  with check (public.zivra_is_admin());

-- Customers can read only their own account-linked orders; admins retain existing access.
drop policy if exists "Customers view own orders" on public.orders;
create policy "Customers view own orders" on public.orders
  for select to authenticated using (user_id = auth.uid() or public.zivra_is_admin());

drop policy if exists "Customers view own order items" on public.order_items;
create policy "Customers view own order items" on public.order_items
  for select to authenticated using (
    exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.zivra_is_admin()))
  );

commit;

-- Notes:
-- 1) Existing guest orders remain guest orders; do not auto-attach by email without verified ownership.
-- 2) Supabase Auth OTP settings/provider configuration must be completed in the Supabase dashboard.
-- 3) Link newly authenticated orders to auth.uid() only after checkout flow is explicitly tested.
-- 4) Product variant JSON shape and image upload storage bucket/policies must be finalized before enabling variant stock deduction.
-- 5) Never expose service_role keys in browser code. Admin checks use app_metadata.role = 'admin'.