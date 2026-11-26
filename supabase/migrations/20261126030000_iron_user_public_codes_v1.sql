create table if not exists public.iron_user_public_codes_v1 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  public_code text not null unique check (public_code ~ '^[0-9]{6}$'),
  created_at timestamptz not null default now()
);
alter table public.iron_user_public_codes_v1 enable row level security;
revoke all on table public.iron_user_public_codes_v1 from anon, authenticated;
grant all on table public.iron_user_public_codes_v1 to service_role;

create or replace function public.iron_assign_user_code_v1(p_user_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_code text; v_existing text; v_attempt integer;
begin
  if p_user_id is null then raise exception 'شناسه کاربر معتبر نیست'; end if;
  select public_code into v_existing from public.iron_user_public_codes_v1 where user_id=p_user_id;
  if found then return v_existing; end if;
  for v_attempt in 1..100 loop
    v_code := lpad((floor(random()*900000)::integer+100000)::text,6,'0');
    begin
      insert into public.iron_user_public_codes_v1(user_id,public_code) values(p_user_id,v_code);
      return v_code;
    exception when unique_violation then
      select public_code into v_existing from public.iron_user_public_codes_v1 where user_id=p_user_id;
      if found then return v_existing; end if;
    end;
  end loop;
  raise exception 'ساخت کد اختصاصی ممکن نشد؛ دوباره تلاش کنید';
end;
$$;

create or replace function public.iron_handle_new_user_code_v1()
returns trigger language plpgsql security definer set search_path = '' as $$
begin perform public.iron_assign_user_code_v1(new.id); return new; end;
$$;
drop trigger if exists iron_assign_public_code_after_signup_v1 on auth.users;
create trigger iron_assign_public_code_after_signup_v1 after insert on auth.users
for each row execute function public.iron_handle_new_user_code_v1();

do $$
declare v_user record;
begin
  for v_user in select id from auth.users loop perform public.iron_assign_user_code_v1(v_user.id); end loop;
end;
$$;

create or replace function public.iron_get_my_public_code_v1()
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid:=auth.uid(); v_code text;
begin
  if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
  v_code:=public.iron_assign_user_code_v1(v_uid);
  return v_code;
end;
$$;

create or replace function public.iron_request_coach_connection_by_code_v1(p_code text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_student uuid:=auth.uid(); v_coach uuid; v_existing_status text;
begin
  if v_student is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then raise exception 'کد باید دقیقاً شش رقم باشد'; end if;
  if not exists(select 1 from public.iron_account_roles_v2 where user_id=v_student and role='student' and status='approved') then
    raise exception 'این قابلیت برای حساب شاگرد تأییدشده فعال است';
  end if;
  select c.user_id into v_coach from public.iron_user_public_codes_v1 c
  join public.iron_account_roles_v2 r on r.user_id=c.user_id
  where c.public_code=p_code and r.role='coach' and r.status='approved' limit 1;
  if v_coach is null then raise exception 'کد پیدا نشد یا متعلق به مربی تأییدشده نیست'; end if;
  if v_coach=v_student then raise exception 'امکان اتصال به حساب خودتان وجود ندارد'; end if;
  select status into v_existing_status from public.iron_coach_students_v2
  where coach_id=v_coach and student_id=v_student limit 1;
  if v_existing_status='approved' then return 'قبلاً به این مربی متصل شده‌ای'; end if;
  if v_existing_status='pending' then return 'درخواست قبلی هنوز در انتظار بررسی مربی است'; end if;
  insert into public.iron_coach_students_v2(coach_id,student_id,status)
  values(v_coach,v_student,'pending')
  on conflict(coach_id,student_id) do update set status='pending',created_at=now();
  return 'درخواست اتصال برای مربی ارسال شد';
end;
$$;

create or replace function public.iron_lookup_linked_student_by_code_v1(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_coach uuid:=auth.uid(); v_student uuid;
begin
  if v_coach is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then raise exception 'کد شاگرد باید دقیقاً شش رقم باشد'; end if;
  if not exists(select 1 from public.iron_account_roles_v2 where user_id=v_coach and role='coach' and status='approved') then
    raise exception 'فقط مربی تأییدشده می‌تواند برنامه ثبت کند';
  end if;
  select c.user_id into v_student from public.iron_user_public_codes_v1 c
  join public.iron_account_roles_v2 r on r.user_id=c.user_id
  join public.iron_coach_students_v2 l on l.student_id=c.user_id and l.coach_id=v_coach and l.status='approved'
  where c.public_code=p_code and r.role='student' and r.status='approved' limit 1;
  if v_student is null then raise exception 'شاگرد تأییدشده متصل با این کد پیدا نشد'; end if;
  return v_student;
end;
$$;

create or replace function public.iron_admin_assign_coach_by_code_v1(p_code text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_target uuid; v_name text;
begin
  if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 where user_id=auth.uid() and is_main_admin=true) then
    raise exception 'فقط مدیر اصلی اجازه ارتقای کاربر به مربی را دارد';
  end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then raise exception 'کد کاربر باید دقیقاً شش رقم باشد'; end if;
  select c.user_id,coalesce(p.full_name,'') into v_target,v_name
  from public.iron_user_public_codes_v1 c left join public.profiles p on p.id=c.user_id
  where c.public_code=p_code limit 1;
  if v_target is null then raise exception 'کاربری با این کد پیدا نشد'; end if;
  if v_target=auth.uid() then raise exception 'برای ارتقای حساب خودتان از این مسیر استفاده نکنید'; end if;
  insert into public.iron_account_roles_v2(user_id,role,status) values(v_target,'coach','approved')
  on conflict(user_id) do update set role='coach',status='approved',updated_at=now();
  insert into public.iron_coach_profiles_v2(user_id,full_name) values(v_target,v_name)
  on conflict(user_id) do update set
    full_name=case when coalesce(public.iron_coach_profiles_v2.full_name,'')='' then excluded.full_name else public.iron_coach_profiles_v2.full_name end,
    updated_at=now();
  return 'کاربر با موفقیت به مربی تأییدشده ارتقا یافت';
end;
$$;

create or replace function public.iron_admin_set_access_by_code_v1(p_code text,p_is_admin boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_target uuid;
begin
  if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 where user_id=auth.uid() and is_main_admin=true) then
    raise exception 'فقط مدیر اصلی اجازه مدیریت مدیران را دارد';
  end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' or p_is_admin is null then raise exception 'کد شش‌رقمی و وضعیت دسترسی معتبر وارد کنید'; end if;
  select user_id into v_target from public.iron_user_public_codes_v1 where public_code=p_code limit 1;
  if v_target is null then raise exception 'کاربری با این کد پیدا نشد'; end if;
  if p_is_admin then
    insert into public.iron_admins_v2(user_id,is_main_admin) values(v_target,false) on conflict(user_id) do nothing;
    return 'دسترسی مدیر اضافه شد';
  end if;
  if exists(select 1 from public.iron_admins_v2 where user_id=v_target and is_main_admin=true) then raise exception 'حذف مدیر اصلی مجاز نیست'; end if;
  delete from public.iron_admins_v2 where user_id=v_target and is_main_admin=false;
  return 'دسترسی مدیر لغو شد';
end;
$$;

revoke all on function public.iron_assign_user_code_v1(uuid) from public,anon,authenticated;
revoke all on function public.iron_handle_new_user_code_v1() from public,anon,authenticated;
revoke all on function public.iron_get_my_public_code_v1() from public,anon;
revoke all on function public.iron_request_coach_connection_by_code_v1(text) from public,anon;
revoke all on function public.iron_lookup_linked_student_by_code_v1(text) from public,anon;
revoke all on function public.iron_admin_assign_coach_by_code_v1(text) from public,anon;
revoke all on function public.iron_admin_set_access_by_code_v1(text,boolean) from public,anon;
grant execute on function public.iron_get_my_public_code_v1() to authenticated;
grant execute on function public.iron_request_coach_connection_by_code_v1(text) to authenticated;
grant execute on function public.iron_lookup_linked_student_by_code_v1(text) to authenticated;
grant execute on function public.iron_admin_assign_coach_by_code_v1(text) to authenticated;
grant execute on function public.iron_admin_set_access_by_code_v1(text,boolean) to authenticated;
