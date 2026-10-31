-- ZIVRA admin order permissions repair.
-- Run this whole file once in Supabase Dashboard -> SQL Editor.
-- This file only repairs admin read/update permissions; it does NOT replace
-- the richer zivra_track_order function installed by supabase-dispatch-tracking-patch.sql.

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Admins view orders" on public.orders;
create policy "Admins view orders" on public.orders
for select to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins update orders" on public.orders;
create policy "Admins update orders" on public.orders
for update to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins view order items" on public.order_items;
create policy "Admins view order items" on public.order_items
for select to authenticated
using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

grant select, update on public.orders to authenticated;
grant select on public.order_items to authenticated;
