-- ZIVRA: disable guest checkout at the database/API layer.
-- Run this once in Supabase SQL Editor after deploying the matching storefront change.
-- The browser now requires an active customer session before checkout.
revoke execute on function public.zivra_place_order(jsonb) from anon;
grant execute on function public.zivra_place_order(jsonb) to authenticated;
