-- Rate-limit coach verification attempts to five guesses per issued code.
alter table public.iron_coach_verification_codes_v2
  add column if not exists attempts smallint not null default 0,
  add column if not exists locked_at timestamptz;

create or replace function public.iron_verify_coach_code_v2(p_code text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_row record;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if p_code is null or p_code !~ '^[0-9]{6}$' then return 'کد باید دقیقاً شش رقم باشد'; end if;
 select id,code_hash,salt,attempts into v_row
 from public.iron_coach_verification_codes_v2
 where coach_id=v_uid and used_at is null and locked_at is null and expires_at>now()
 order by created_at desc limit 1 for update;
 if not found then return 'کد تأیید وجود ندارد، منقضی شده یا پس از پنج تلاش قفل شده است.'; end if;
 if md5(v_row.salt||p_code)<>v_row.code_hash then
   update public.iron_coach_verification_codes_v2
   set attempts=attempts+1,
       locked_at=case when attempts+1>=5 then now() else null end
   where id=v_row.id;
   if v_row.attempts+1>=5 then return 'پنج بار کد اشتباه وارد شد؛ این کد قفل شد و باید مدیر کد تازه صادر کند.'; end if;
   return 'کد نادرست است. تعداد تلاش باقی‌مانده: '||(4-v_row.attempts)::text;
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
