-- IRONNOVA education media storage bucket and admin-only write policies
-- The app uploads to this exact bucket name: iron-education-media.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'iron-education-media',
  'iron-education-media',
  true,
  52428800,
  array['image/jpeg','image/png','image/webp','image/gif','image/avif','video/mp4','video/webm','video/quicktime']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists iron_education_media_public_read_v2 on storage.objects;
create policy iron_education_media_public_read_v2
on storage.objects for select
to public
using (bucket_id = 'iron-education-media');

drop policy if exists iron_education_media_admin_insert_v2 on storage.objects;
create policy iron_education_media_admin_insert_v2
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'iron-education-media'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.iron_admins_v2 a
    where a.user_id = auth.uid() and a.is_main_admin
  )
);

drop policy if exists iron_education_media_admin_update_v2 on storage.objects;
create policy iron_education_media_admin_update_v2
on storage.objects for update
to authenticated
using (
  bucket_id = 'iron-education-media'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.iron_admins_v2 a
    where a.user_id = auth.uid() and a.is_main_admin
  )
)
with check (
  bucket_id = 'iron-education-media'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.iron_admins_v2 a
    where a.user_id = auth.uid() and a.is_main_admin
  )
);

drop policy if exists iron_education_media_admin_delete_v2 on storage.objects;
create policy iron_education_media_admin_delete_v2
on storage.objects for delete
to authenticated
using (
  bucket_id = 'iron-education-media'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.iron_admins_v2 a
    where a.user_id = auth.uid() and a.is_main_admin
  )
);
