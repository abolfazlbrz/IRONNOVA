create or replace function public.iron_admin_issue_coach_code_v2(p_coach_id uuid)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_code text; v_salt text;
begin
 if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin) then
  raise exception 'فقط مدیر اصلی می‌تواند کد تأیید صادر کند';
 end if;
 if not exists(select 1 from public.iron_account_roles_v2 r where r.user_id=p_coach_id and r.role='coach' and r.status='pending') then
  raise exception 'درخواست مربی در انتظار تأیید پیدا نشد';
 end if;
 v_code:=lpad((100000+(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint%900000))::text,6,'0');
 v_salt:=md5(gen_random_uuid()::text||clock_timestamp()::text||p_coach_id::text);
 update public.iron_coach_verification_codes_v2 set used_at=now()
 where coach_id=p_coach_id and used_at is null;
 insert into public.iron_coach_verification_codes_v2(coach_id,code_hash,salt,created_by,expires_at)
 values(p_coach_id,md5(v_salt||v_code),v_salt,auth.uid(),now()+interval '24 hours');
 return v_code;
end;
$function$;
revoke all on function public.iron_admin_issue_coach_code_v2(uuid) from public,anon;
grant execute on function public.iron_admin_issue_coach_code_v2(uuid) to authenticated;
