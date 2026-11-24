-- One-time six-digit coach verification codes and pending coach profile submission.
drop policy if exists iron_coach_profile_insert_own on public.iron_coach_profiles_v2;
create policy iron_coach_profile_insert_own on public.iron_coach_profiles_v2
for insert to authenticated with check (
 user_id=(select auth.uid())
 and exists(select 1 from public.iron_account_roles_v2 r
   where r.user_id=(select auth.uid()) and r.role='coach' and r.status in ('pending','approved'))
);
drop policy if exists iron_coach_profile_update_own on public.iron_coach_profiles_v2;
create policy iron_coach_profile_update_own on public.iron_coach_profiles_v2
for update to authenticated using (
 user_id=(select auth.uid())
 and exists(select 1 from public.iron_account_roles_v2 r
   where r.user_id=(select auth.uid()) and r.role='coach' and r.status in ('pending','approved'))
) with check (
 user_id=(select auth.uid())
 and exists(select 1 from public.iron_account_roles_v2 r
   where r.user_id=(select auth.uid()) and r.role='coach' and r.status in ('pending','approved'))
);
drop policy if exists iron_coach_profile_select_v2 on public.iron_coach_profiles_v2;
create policy iron_coach_profile_select_v2 on public.iron_coach_profiles_v2
for select to authenticated using (
 user_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 or exists(select 1 from public.iron_coach_students_v2 cs
   where cs.coach_id=iron_coach_profiles_v2.user_id
     and cs.student_id=(select auth.uid()) and cs.status='approved')
);

create table if not exists public.iron_coach_verification_codes_v2 (
 id uuid primary key default gen_random_uuid(),
 coach_id uuid not null references auth.users(id) on delete cascade,
 code_hash text not null,
 salt text not null,
 created_by uuid not null references auth.users(id),
 expires_at timestamptz not null,
 used_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists idx_iron_coach_verification_active_v2
 on public.iron_coach_verification_codes_v2(coach_id,expires_at desc) where used_at is null;
alter table public.iron_coach_verification_codes_v2 enable row level security;
revoke all on public.iron_coach_verification_codes_v2 from anon,public,authenticated;

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
 v_code:=lpad((floor(random()*900000)+100000)::integer::text,6,'0');
 v_salt:=md5(random()::text||clock_timestamp()::text||p_coach_id::text);
 update public.iron_coach_verification_codes_v2 set used_at=now()
 where coach_id=p_coach_id and used_at is null;
 insert into public.iron_coach_verification_codes_v2(coach_id,code_hash,salt,created_by,expires_at)
 values(p_coach_id,md5(v_salt||v_code),v_salt,auth.uid(),now()+interval '24 hours');
 return v_code;
end;
$function$;
revoke all on function public.iron_admin_issue_coach_code_v2(uuid) from public,anon;
grant execute on function public.iron_admin_issue_coach_code_v2(uuid) to authenticated;

create or replace function public.iron_verify_coach_code_v2(p_code text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_row record;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if p_code is null or p_code !~ '^[0-9]{6}$' then raise exception 'کد باید دقیقاً شش رقم باشد'; end if;
 select id,code_hash,salt into v_row
 from public.iron_coach_verification_codes_v2
 where coach_id=v_uid and used_at is null and expires_at>now()
 order by created_at desc limit 1 for update;
 if not found or md5(v_row.salt||p_code)<>v_row.code_hash then
   raise exception 'کد تأیید نادرست یا منقضی شده است';
 end if;
 update public.iron_coach_verification_codes_v2 set used_at=now() where id=v_row.id;
 update public.iron_account_roles_v2 set status='approved',updated_at=now()
 where user_id=v_uid and role='coach' and status='pending';
 if not found then raise exception 'درخواست مربی در وضعیت قابل تأیید نیست'; end if;
 return 'حساب مربی تأیید شد. اکنون امکانات مربی فعال است.';
end;
$function$;
revoke all on function public.iron_verify_coach_code_v2(text) from public,anon;
grant execute on function public.iron_verify_coach_code_v2(text) to authenticated;

create or replace function public.iron_review_coach_v2(p_coach_id uuid,p_approve boolean)
returns text language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin) then
   raise exception 'فقط مدیر اصلی اجازه بررسی مربی را دارد';
 end if;
 if p_approve then
   return 'برای تأیید نهایی، ابتدا رزومه و عکس را بررسی و سپس کد شش‌رقمی صادر کنید.';
 end if;
 update public.iron_account_roles_v2 set status='rejected',updated_at=now()
 where user_id=p_coach_id and role='coach' and status='pending';
 if not found then raise exception 'درخواست مربی معتبر یا در انتظار بررسی نیست'; end if;
 return 'درخواست مربی رد شد';
end;
$function$;
revoke all on function public.iron_review_coach_v2(uuid,boolean) from public,anon;
grant execute on function public.iron_review_coach_v2(uuid,boolean) to authenticated;
