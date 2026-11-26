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
  if exists(select 1 from public.iron_coach_students_v2 where student_id=v_target and status in ('pending','approved')) then
    raise exception 'این کاربر اتصال فعال یا در انتظار به‌عنوان شاگرد دارد؛ ابتدا اتصال‌های شاگردی را تعیین تکلیف کنید';
  end if;
  insert into public.iron_account_roles_v2(user_id,role,status) values(v_target,'coach','approved')
  on conflict(user_id) do update set role='coach',status='approved',updated_at=now();
  insert into public.iron_coach_profiles_v2(user_id,full_name) values(v_target,v_name)
  on conflict(user_id) do update set
    full_name=case when coalesce(public.iron_coach_profiles_v2.full_name,'')='' then excluded.full_name else public.iron_coach_profiles_v2.full_name end,
    updated_at=now();
  return 'کاربر با موفقیت به مربی تأییدشده ارتقا یافت';
end;
$$;
revoke all on function public.iron_admin_assign_coach_by_code_v1(text) from public,anon;
grant execute on function public.iron_admin_assign_coach_by_code_v1(text) to authenticated;