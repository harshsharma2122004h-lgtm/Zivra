-- ZIVRA public storefront catalog + guest COD checkout permissions
-- Run in Supabase Dashboard -> SQL Editor as project owner.

grant usage on schema public to anon, authenticated;

-- Allow the public storefront to read only active products.
drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products"
on public.products
for select
to anon, authenticated
using (is_active = true);

grant select on table public.products to anon, authenticated;

-- Guest checkout is handled only by the validated SECURITY DEFINER RPC.
grant execute on function public.zivra_place_order(jsonb) to anon, authenticated;

-- Keep direct guest writes blocked; the RPC creates orders and order items.
revoke insert, update, delete on public.orders from anon, authenticated;
revoke insert, update, delete on public.order_items from anon, authenticated;
