create or replace function public.iron_lookup_linked_students_by_codes_v1(p_codes text[])
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coach uuid := auth.uid();
  v_result uuid[];
  v_count integer;
begin
  if v_coach is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
  if not exists(select 1 from public.iron_account_roles_v2 where user_id=v_coach and role='coach' and status='approved') then
    raise exception 'فقط مربی تأییدشده می‌تواند گروه بسازد';
  end if;
  if p_codes is null or cardinality(p_codes)<1 or cardinality(p_codes)>50 then
    raise exception 'بین ۱ تا ۵۰ کد شاگرد وارد کنید';
  end if;
  if exists(select 1 from unnest(p_codes) c where c !~ '^[0-9]{6}$') then
    raise exception 'تمام کدها باید دقیقاً شش رقم باشند';
  end if;
  if (select count(distinct c) from unnest(p_codes) c) <> cardinality(p_codes) then
    raise exception 'کد تکراری در فهرست وجود دارد';
  end if;
  select array_agg(c.user_id order by array_position(p_codes,c.public_code))
  into v_result
  from public.iron_user_public_codes_v1 c
  join public.iron_account_roles_v2 r on r.user_id=c.user_id
  join public.iron_coach_students_v2 l on l.student_id=c.user_id and l.coach_id=v_coach and l.status='approved'
  where c.public_code = any(p_codes) and r.role='student' and r.status='approved';
  v_count := coalesce(cardinality(v_result),0);
  if v_count <> cardinality(p_codes) then
    raise exception 'یک یا چند کد متعلق به شاگرد تأییدشده و متصل شما نیست';
  end if;
  return v_result;
end;
$$;
revoke all on function public.iron_lookup_linked_students_by_codes_v1(text[]) from public,anon;
grant execute on function public.iron_lookup_linked_students_by_codes_v1(text[]) to authenticated;