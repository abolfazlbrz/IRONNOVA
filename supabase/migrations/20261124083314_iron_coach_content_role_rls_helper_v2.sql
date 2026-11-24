-- RLS-safe helper: role rows are intentionally private, so policies must check coach approval through a definer function.
create or replace function public.iron_is_approved_coach_v2(p_coach_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
 select exists(
  select 1 from public.iron_account_roles_v2 r
  where r.user_id=p_coach_id and r.role='coach' and r.status='approved'
 );
$function$;
revoke all on function public.iron_is_approved_coach_v2(uuid) from public,anon;
grant execute on function public.iron_is_approved_coach_v2(uuid) to authenticated;

drop policy if exists iron_coach_content_select_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_select_v2 on public.iron_coach_content_v2
for select to authenticated using (
 coach_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 or (is_published and visibility='public' and public.iron_is_approved_coach_v2(coach_id))
 or (is_published and visibility='private'
   and public.iron_is_approved_coach_v2(coach_id)
   and exists(select 1 from public.iron_coach_students_v2 l
     where l.coach_id=iron_coach_content_v2.coach_id and l.student_id=(select auth.uid()) and l.status='approved')
 )
);

drop policy if exists iron_coach_content_storage_select_v2 on storage.objects;
create policy iron_coach_content_storage_select_v2 on storage.objects
for select to authenticated using (
 bucket_id='iron-coach-content-v2' and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
  or exists(select 1 from public.iron_coach_content_v2 c
    where c.file_path=objects.name and c.is_published
      and public.iron_is_approved_coach_v2(c.coach_id)
      and (c.visibility='public' or (c.visibility='private' and exists(
       select 1 from public.iron_coach_students_v2 l
       where l.coach_id=c.coach_id and l.student_id=(select auth.uid()) and l.status='approved'
      )))
  )
 )
);
