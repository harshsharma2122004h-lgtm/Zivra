-- ZIVRA product editor and image storage compatibility patch
-- Run AFTER supabase-schema.sql in Supabase SQL Editor.
-- Safe to re-run. Does not modify existing products or order records.

begin;

alter table public.products
  add column if not exists brand text not null default '',
  add column if not exists fabric text not null default '',
  add column if not exists fit text not null default '',
  add column if not exists highlights text not null default '',
  add column if not exists care text not null default '',
  add column if not exists sizes jsonb not null default '{}'::jsonb,
  add column if not exists colors jsonb not null default '[]'::jsonb,
  add column if not exists images jsonb not null default '[]'::jsonb;

-- Product photos are served through public URLs; only approved admins can upload,
-- replace, or delete objects in this bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "ZIVRA product images are publicly readable" on storage.objects;
create policy "ZIVRA product images are publicly readable"
on storage.objects for select
to public
using (bucket_id = 'product-images');

drop policy if exists "ZIVRA admins upload product images" on storage.objects;
create policy "ZIVRA admins upload product images"
on storage.objects for insert
to authenticated
with check (bucket_id = 'product-images' and public.zivra_is_admin());

drop policy if exists "ZIVRA admins update product images" on storage.objects;
create policy "ZIVRA admins update product images"
on storage.objects for update
to authenticated
using (bucket_id = 'product-images' and public.zivra_is_admin())
with check (bucket_id = 'product-images' and public.zivra_is_admin());

drop policy if exists "ZIVRA admins delete product images" on storage.objects;
create policy "ZIVRA admins delete product images"
on storage.objects for delete
to authenticated
using (bucket_id = 'product-images' and public.zivra_is_admin());

commit;
