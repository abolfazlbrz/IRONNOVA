create or replace function public.iron_admin_set_coach_status_v2(p_coach_id uuid,p_status text)
returns text
language plpgsql
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
  if p_status not in ('pending','approved','rejected','suspended') then
    raise exception 'وضعیت انتخاب‌شده معتبر نیست';
  end if;
  update public.iron_account_roles_v2
  set status=p_status,updated_at=now()
  where user_id=p_coach_id and role='coach';
  if not found then raise exception 'حساب مربی پیدا نشد'; end if;
  return 'وضعیت مربی به‌روزرسانی شد';
end;
$$;
revoke all on function public.iron_admin_set_coach_status_v2(uuid,text) from public,anon;
grant execute on function public.iron_admin_set_coach_status_v2(uuid,text) to authenticated;