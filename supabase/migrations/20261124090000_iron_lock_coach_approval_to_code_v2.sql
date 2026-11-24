-- Prevent direct coach approval; approval must consume a valid one-time code.
create or replace function public.iron_admin_set_coach_status_v2(p_coach_id uuid,p_status text)
returns text language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin) then
   raise exception 'فقط مدیر اصلی می‌تواند وضعیت مربی را تغییر دهد';
 end if;
 if p_status not in ('rejected','suspended','pending') then
   raise exception 'تأیید نهایی مربی فقط با کد شش‌رقمی یک‌بارمصرف انجام می‌شود';
 end if;
 update public.iron_account_roles_v2 set status=p_status,updated_at=now()
 where user_id=p_coach_id and role='coach';
 if not found then raise exception 'حساب مربی پیدا نشد'; end if;
 if p_status in ('rejected','suspended') then
   update public.iron_coach_verification_codes_v2 set used_at=now()
   where coach_id=p_coach_id and used_at is null;
 end if;
 return 'وضعیت حساب مربی به‌روزرسانی شد';
end;
$function$;
revoke all on function public.iron_admin_set_coach_status_v2(uuid,text) from public,anon;
grant execute on function public.iron_admin_set_coach_status_v2(uuid,text) to authenticated;
