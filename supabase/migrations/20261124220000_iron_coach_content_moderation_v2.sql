-- Enforce approved-coach status for public/private learning content and give the main admin moderation access.
drop policy if exists iron_coach_content_select_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_select_v2 on public.iron_coach_content_v2
for select to authenticated using (
 coach_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 or (is_published and visibility='public' and exists(
   select 1 from public.iron_account_roles_v2 r
   where r.user_id=iron_coach_content_v2.coach_id and r.role='coach' and r.status='approved'
 ))
 or (is_published and visibility='private'
   and exists(select 1 from public.iron_account_roles_v2 r
     where r.user_id=iron_coach_content_v2.coach_id and r.role='coach' and r.status='approved')
   and exists(select 1 from public.iron_coach_students_v2 l
     where l.coach_id=iron_coach_content_v2.coach_id and l.student_id=(select auth.uid()) and l.status='approved')
 )
);

drop policy if exists iron_coach_content_insert_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_insert_v2 on public.iron_coach_content_v2
for insert to authenticated with check (
 (coach_id=(select auth.uid()) and exists(select 1 from public.iron_account_roles_v2 r
  where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

drop policy if exists iron_coach_content_update_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_update_v2 on public.iron_coach_content_v2
for update to authenticated using (
 (coach_id=(select auth.uid()) and exists(select 1 from public.iron_account_roles_v2 r
  where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
) with check (
 (coach_id=(select auth.uid()) and exists(select 1 from public.iron_account_roles_v2 r
  where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

drop policy if exists iron_coach_content_delete_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_delete_v2 on public.iron_coach_content_v2
for delete to authenticated using (
 (coach_id=(select auth.uid()) and exists(select 1 from public.iron_account_roles_v2 r
  where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

drop policy if exists iron_coach_content_storage_select_v2 on storage.objects;
create policy iron_coach_content_storage_select_v2 on storage.objects
for select to authenticated using (
 bucket_id='iron-coach-content-v2' and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
  or exists(select 1 from public.iron_coach_content_v2 c
    join public.iron_account_roles_v2 r on r.user_id=c.coach_id and r.role='coach' and r.status='approved'
    where c.file_path=objects.name and c.is_published and (
     c.visibility='public'
     or (c.visibility='private' and exists(select 1 from public.iron_coach_students_v2 l
       where l.coach_id=c.coach_id and l.student_id=(select auth.uid()) and l.status='approved'))
    )
  )
 )
);

drop policy if exists iron_coach_content_storage_insert_v2 on storage.objects;
create policy iron_coach_content_storage_insert_v2 on storage.objects
for insert to authenticated with check (
 bucket_id='iron-coach-content-v2' and (
  ((storage.foldername(name))[1]=(select auth.uid())::text and exists(
   select 1 from public.iron_account_roles_v2 r
   where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 )
);

drop policy if exists iron_coach_content_storage_delete_v2 on storage.objects;
create policy iron_coach_content_storage_delete_v2 on storage.objects
for delete to authenticated using (
 bucket_id='iron-coach-content-v2' and (
  ((storage.foldername(name))[1]=(select auth.uid())::text and exists(
   select 1 from public.iron_account_roles_v2 r
   where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 )
);
