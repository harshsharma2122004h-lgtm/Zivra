-- ZIVRA order management + customer tracking repair
-- Run this whole file once in Supabase Dashboard -> SQL Editor.

-- Ensure admin can read and update orders using the server-managed JWT role.
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

-- Public tracking reveals only the order matching both order number and checkout email.
create or replace function public.zivra_track_order(p_order_number text, p_email text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'order_number', o.order_number,
    'status', o.status,
    'payment_method', o.payment_method,
    'payment_status', o.payment_status,
    'total', o.total,
    'created_at', o.created_at
  )
  from public.orders o
  where upper(o.order_number) = upper(trim(p_order_number))
    and lower(o.email) = lower(trim(p_email))
  limit 1;
$$;

revoke all on function public.zivra_track_order(text,text) from public;
grant execute on function public.zivra_track_order(text,text) to anon, authenticated;
