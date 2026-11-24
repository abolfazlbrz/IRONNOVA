-- Public/private coach education visibility and GIF support.
alter table public.iron_coach_content_v2
  add column if not exists visibility text not null default 'private';
alter table public.iron_coach_content_v2
  drop constraint if exists iron_coach_content_v2_visibility_check;
alter table public.iron_coach_content_v2
  add constraint iron_coach_content_v2_visibility_check
  check (visibility in ('public','private'));

drop policy if exists iron_coach_content_select_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_select_v2 on public.iron_coach_content_v2
for select to authenticated
using (
  coach_id = (select auth.uid())
  or (
    is_published
    and visibility = 'public'
  )
  or (
    is_published
    and visibility = 'private'
    and exists (
      select 1 from public.iron_coach_students_v2 l
      where l.coach_id = iron_coach_content_v2.coach_id
        and l.student_id = (select auth.uid())
        and l.status = 'approved'
    )
  )
);

update storage.buckets
set allowed_mime_types = array['video/mp4','video/webm','image/jpeg','image/png','image/webp','image/gif','application/pdf']
where id = 'iron-coach-content-v2';

drop policy if exists iron_coach_content_storage_select_v2 on storage.objects;
create policy iron_coach_content_storage_select_v2 on storage.objects
for select to authenticated
using (
  bucket_id = 'iron-coach-content-v2'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.iron_coach_content_v2 c
      where c.file_path = storage.objects.name
        and c.is_published
        and (
          c.visibility = 'public'
          or (
            c.visibility = 'private'
            and exists (
              select 1 from public.iron_coach_students_v2 l
              where l.coach_id = c.coach_id
                and l.student_id = (select auth.uid())
                and l.status = 'approved'
            )
          )
        )
    )
  )
);
