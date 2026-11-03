-- ZIVRA Offers & Site Studio
-- Run this migration in the Supabase SQL Editor for the project used by ZIVRA.
create extension if not exists pgcrypto;

create table if not exists public.zivra_offers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 90),
  code text unique,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0 and (discount_type <> 'percent' or discount_value <= 100)),
  scope text not null default 'all' check (scope in ('all','category','product')),
  target text,
  minimum_order numeric(12,2) not null default 0 check (minimum_order >= 0),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or expires_at > starts_at),
  check ((scope = 'all' and target is null) or (scope <> 'all' and target is not null and char_length(target) > 0))
);
create index if not exists zivra_offers_active_expiry_idx on public.zivra_offers (is_active, starts_at, expires_at);
create unique index if not exists zivra_offers_code_upper_unique on public.zivra_offers (upper(code)) where code is not null;

create table if not exists public.zivra_site_settings (
  id text primary key default 'default' check (id = 'default'),
  store_name text not null default 'ZIVRA',
  logo_url text not null default '',
  announcement text not null default '',
  footer_text text not null default '',
  theme text not null default 'heritage' check (theme in ('heritage','minimal','editorial','bold','soft')),
  primary_color text not null default '#24211d' check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  accent_color text not null default '#c8a979' check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  background_color text not null default '#f5f3ef' check (background_color ~ '^#[0-9A-Fa-f]{6}$'),
  heading_font text not null default 'Georgia, serif',
  card_style text not null default 'classic' check (card_style in ('classic','rounded','editorial','compact')),
  badge_style text not null default 'pill' check (badge_style in ('pill','ribbon','minimal')),
  motion text not null default 'subtle' check (motion in ('subtle','smooth','none')),
  corner_radius integer not null default 10 check (corner_radius between 0 and 24),
  show_discount_badges boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.zivra_site_settings (id) values ('default') on conflict (id) do nothing;

alter table public.zivra_offers enable row level security;
alter table public.zivra_site_settings enable row level security;

drop policy if exists "Public can read active ZIVRA offers" on public.zivra_offers;
create policy "Public can read active ZIVRA offers" on public.zivra_offers for select to anon, authenticated
  using (is_active = true and starts_at <= now() and (expires_at is null or expires_at > now()));
drop policy if exists "Admins manage ZIVRA offers" on public.zivra_offers;
create policy "Admins manage ZIVRA offers" on public.zivra_offers for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Public can read ZIVRA site settings" on public.zivra_site_settings;
create policy "Public can read ZIVRA site settings" on public.zivra_site_settings for select to anon, authenticated using (id = 'default');
drop policy if exists "Admins manage ZIVRA site settings" on public.zivra_site_settings;
create policy "Admins manage ZIVRA site settings" on public.zivra_site_settings for all to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

grant select on public.zivra_offers to anon, authenticated;
grant insert, update, delete on public.zivra_offers to authenticated;
grant select on public.zivra_site_settings to anon, authenticated;
grant insert, update, delete on public.zivra_site_settings to authenticated;
