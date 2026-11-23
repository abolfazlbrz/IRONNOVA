-- Coach-owned content library visible to all approved linked students.
create table if not exists public.iron_coach_content_v2 (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 2 and 120),
  description text not null default '',
  content_type text not null check (content_type in ('video','image','pdf','link')),
  file_path text,
  external_url text,
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint iron_coach_content_v2_source_check check (
    (content_type = 'link' and external_url is not null and file_path is null)
    or (content_type <> 'link' and file_path is not null and external_url is null)
  )
);
create index if not exists idx_iron_coach_content_v2_coach_created
  on public.iron_coach_content_v2(coach_id, created_at desc);
alter table public.iron_coach_content_v2 enable row level security;
revoke all on public.iron_coach_content_v2 from anon, public;
grant select, insert, update, delete on public.iron_coach_content_v2 to authenticated;

drop policy if exists iron_coach_content_select_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_select_v2 on public.iron_coach_content_v2
for select to authenticated
using (
  coach_id = (select auth.uid())
  or (
    is_published
    and exists (
      select 1 from public.iron_coach_students_v2 l
      where l.coach_id = iron_coach_content_v2.coach_id
        and l.student_id = (select auth.uid())
        and l.status = 'approved'
    )
  )
);

drop policy if exists iron_coach_content_insert_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_insert_v2 on public.iron_coach_content_v2
for insert to authenticated
with check (
  coach_id = (select auth.uid())
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
);

drop policy if exists iron_coach_content_update_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_update_v2 on public.iron_coach_content_v2
for update to authenticated
using (
  coach_id = (select auth.uid())
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
)
with check (
  coach_id = (select auth.uid())
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
);

drop policy if exists iron_coach_content_delete_v2 on public.iron_coach_content_v2;
create policy iron_coach_content_delete_v2 on public.iron_coach_content_v2
for delete to authenticated
using (
  coach_id = (select auth.uid())
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'iron-coach-content-v2',
  'iron-coach-content-v2',
  false,
  52428800,
  array['video/mp4','video/webm','image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do nothing;

drop policy if exists iron_coach_content_storage_insert_v2 on storage.objects;
create policy iron_coach_content_storage_insert_v2 on storage.objects
for insert to authenticated
with check (
  bucket_id = 'iron-coach-content-v2'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
);

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
        and exists (
          select 1 from public.iron_coach_students_v2 l
          where l.coach_id = c.coach_id
            and l.student_id = (select auth.uid())
            and l.status = 'approved'
        )
    )
  )
);

drop policy if exists iron_coach_content_storage_delete_v2 on storage.objects;
create policy iron_coach_content_storage_delete_v2 on storage.objects
for delete to authenticated
using (
  bucket_id = 'iron-coach-content-v2'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.iron_account_roles_v2 r
    where r.user_id = (select auth.uid())
      and r.role = 'coach' and r.status = 'approved'
  )
);
