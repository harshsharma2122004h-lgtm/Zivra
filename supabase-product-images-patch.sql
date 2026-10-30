-- ZIVRA product photo uploads (run once in Supabase SQL Editor)
-- Creates a public-read bucket; only signed-in ZIVRA admins can upload/change/delete files.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Product images are publicly viewable" on storage.objects;
create policy "Product images are publicly viewable"
on storage.objects for select
to public
using (bucket_id = 'product-images');

drop policy if exists "ZIVRA admins can upload product images" on storage.objects;
create policy "ZIVRA admins can upload product images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
);

drop policy if exists "ZIVRA admins can update product images" on storage.objects;
create policy "ZIVRA admins can update product images"
on storage.objects for update
to authenticated
using (
  bucket_id = 'product-images'
  and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
)
with check (
  bucket_id = 'product-images'
  and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
);

drop policy if exists "ZIVRA admins can delete product images" on storage.objects;
create policy "ZIVRA admins can delete product images"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'product-images'
  and (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
);
