alter table public.iron_education_v2
  add column if not exists coach_id uuid null references auth.users(id) on delete set null;

create index if not exists iron_education_v2_coach_id_idx
  on public.iron_education_v2 (coach_id)
  where coach_id is not null;

drop policy if exists iron_education_coach_insert_v1 on public.iron_education_v2;
create policy iron_education_coach_insert_v1
  on public.iron_education_v2
  for insert
  to authenticated
  with check (
    is_published = true
    and coach_id = (select auth.uid())
    and exists (
      select 1 from public.iron_account_roles_v2 r
      where r.user_id = (select auth.uid())
        and r.role = 'coach'
        and r.status = 'approved'
    )
  );
