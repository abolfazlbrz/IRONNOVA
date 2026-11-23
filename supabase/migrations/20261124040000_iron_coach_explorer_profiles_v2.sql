alter table public.iron_coach_profiles_v2
  add column if not exists experience_years integer not null default 0,
  add column if not exists city text not null default '',
  add column if not exists training_modes text[] not null default '{}',
  add column if not exists achievements text not null default '',
  add column if not exists public_visible boolean not null default true;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='iron_coach_profiles_experience_years_check') then
    alter table public.iron_coach_profiles_v2 add constraint iron_coach_profiles_experience_years_check check (experience_years between 0 and 60);
  end if;
end $$;

create or replace function public.iron_explore_coaches_v2()
returns table (
  user_id uuid,
  full_name text,
  specialty text,
  bio text,
  credentials text,
  photo_url text,
  experience_years integer,
  city text,
  training_modes text[],
  achievements text,
  student_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.full_name, p.specialty, p.bio, p.credentials, p.photo_url,
         p.experience_years, p.city, p.training_modes, p.achievements,
         count(distinct cs.student_id) filter (where cs.status='approved')::bigint
  from public.iron_coach_profiles_v2 p
  join public.iron_account_roles_v2 r on r.user_id=p.user_id
  left join public.iron_coach_students_v2 cs on cs.coach_id=p.user_id
  where auth.uid() is not null
    and r.role='coach' and r.status='approved' and p.public_visible=true
  group by p.user_id
  order by p.full_name asc;
$$;

create or replace function public.iron_request_coach_connection_v2(p_coach_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := auth.uid();
  v_existing_status text;
begin
  if v_student is null then raise exception 'ابتدا وارد حساب کاربری شو'; end if;
  if p_coach_id is null or p_coach_id=v_student then raise exception 'شناسه مربی معتبر نیست'; end if;
  if not exists (
    select 1 from public.iron_account_roles_v2
    where user_id=v_student and role='student' and status='approved'
  ) then raise exception 'این قابلیت برای حساب شاگرد تأییدشده فعال است'; end if;
  if not exists (
    select 1 from public.iron_account_roles_v2
    where user_id=p_coach_id and role='coach' and status='approved'
  ) then raise exception 'این مربی تأییدشده یا فعال نیست'; end if;

  select status into v_existing_status
  from public.iron_coach_students_v2
  where coach_id=p_coach_id and student_id=v_student
  limit 1;

  if v_existing_status='approved' then return 'قبلاً به این مربی متصل شده‌ای'; end if;
  if v_existing_status='pending' then return 'درخواست قبلی هنوز در انتظار بررسی مربی است'; end if;

  if v_existing_status is null then
    insert into public.iron_coach_students_v2(coach_id,student_id,status)
    values(p_coach_id,v_student,'pending');
  else
    update public.iron_coach_students_v2
    set status='pending',created_at=now()
    where coach_id=p_coach_id and student_id=v_student;
  end if;
  return 'درخواست اتصال برای مربی ارسال شد';
end;
$$;

create or replace function public.iron_admin_coaches_overview_v2()
returns table (
  user_id uuid,
  full_name text,
  specialty text,
  status text,
  experience_years integer,
  city text,
  student_count bigint,
  pending_count bigint,
  profile_updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.iron_admins_v2
    where user_id=auth.uid() and is_main_admin=true
  ) then
    raise exception 'فقط مدیر اصلی دسترسی دارد';
  end if;
  return query
  select r.user_id, coalesce(p.full_name,''), coalesce(p.specialty,''), r.status,
         coalesce(p.experience_years,0), coalesce(p.city,''),
         count(cs.id) filter (where cs.status='approved')::bigint,
         count(cs.id) filter (where cs.status='pending')::bigint,
         p.updated_at
  from public.iron_account_roles_v2 r
  left join public.iron_coach_profiles_v2 p on p.user_id=r.user_id
  left join public.iron_coach_students_v2 cs on cs.coach_id=r.user_id
  where r.role='coach'
  group by r.user_id,p.full_name,p.specialty,r.status,p.experience_years,p.city,p.updated_at
  order by case r.status when 'pending' then 0 when 'approved' then 1 when 'suspended' then 2 else 3 end, p.full_name;
end;
$$;

revoke all on function public.iron_explore_coaches_v2() from public, anon;
revoke all on function public.iron_request_coach_connection_v2(uuid) from public, anon;
revoke all on function public.iron_admin_coaches_overview_v2() from public, anon;
grant execute on function public.iron_explore_coaches_v2() to authenticated;
grant execute on function public.iron_request_coach_connection_v2(uuid) to authenticated;
grant execute on function public.iron_admin_coaches_overview_v2() to authenticated;
