-- Allow only approved coaches and the main admin to publish education media.
-- Coach uploads are stored under their own auth.uid() folder in Storage.
drop policy if exists iron_education_coach_insert_v1 on public.iron_education_v2;
create policy iron_education_coach_insert_v1
on public.iron_education_v2
for insert
to authenticated
with check (
  is_published = true
  and exists (
    select 1
    from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach'
      and r.status = 'approved'
  )
);

drop policy if exists iron_education_media_coach_insert_v1 on storage.objects;
create policy iron_education_media_coach_insert_v1
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'iron-education-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1
    from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach'
      and r.status = 'approved'
  )
);
