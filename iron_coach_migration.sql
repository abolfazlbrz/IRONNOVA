-- IRONNOVA coach/student module migration
alter table public.iron_coach_profiles
  add column if not exists coach_approved boolean not null default false;

create or replace function public.iron_set_role(p_role text, p_display_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_role not in ('coach','student') then raise exception 'Invalid role'; end if;
  insert into public.iron_coach_profiles(user_id, display_name, role)
  values (auth.uid(), coalesce(p_display_name,''), p_role)
  on conflict (user_id) do update set display_name = excluded.display_name;
end;
$$;

create or replace function public.iron_claim_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_inv public.iron_coach_invites%rowtype;
begin
  select * into v_inv from public.iron_coach_invites
  where invite_code::text = trim(p_code) and claimed_by is null and expires_at > now()
  for update;
  if not found then raise exception 'Invite code invalid or expired'; end if;
  if v_inv.coach_id = auth.uid() then raise exception 'Cannot claim own invite'; end if;
  update public.iron_coach_invites set claimed_by = auth.uid() where invite_code = v_inv.invite_code;
  insert into public.iron_coach_links(coach_id, student_id, status)
  values (v_inv.coach_id, auth.uid(), 'pending')
  on conflict (coach_id, student_id) do update set status='pending', updated_at=now();
  return v_inv.invite_code;
end;
$$;

create or replace function public.iron_create_invite()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_code uuid;
begin
  if not exists (
    select 1 from public.iron_coach_profiles
    where user_id = auth.uid() and role = 'coach' and coach_approved = true
  ) then
    raise exception 'Coach account is not approved';
  end if;
  insert into public.iron_coach_invites(coach_id, invite_code, expires_at)
  values (auth.uid(), gen_random_uuid(), now() + interval '7 days')
  returning invite_code into v_code;
  return v_code;
end;
$$;

create or replace function public.iron_publish_plan(p_student uuid, p_title text, p_plan jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.iron_coach_profiles
    where user_id = auth.uid() and role = 'coach' and coach_approved = true
  ) then raise exception 'Coach account is not approved'; end if;
  if not exists (
    select 1 from public.iron_coach_links
    where coach_id = auth.uid() and student_id = p_student and status = 'accepted'
  ) then raise exception 'Student is not linked'; end if;
  insert into public.iron_coach_plans(coach_id, student_id, title, plan, version, published)
  values (auth.uid(), p_student, p_title, p_plan, 1, true)
  ;
end;
$$;

create or replace function public.iron_add_student_log(p_type text, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.iron_coach_profiles
    where user_id = auth.uid() and role = 'student'
  ) then raise exception 'Student profile required'; end if;
  if p_type not in ('workout','sleep','nutrition','weight','note') then
    raise exception 'Invalid log type';
  end if;
  insert into public.iron_student_logs(student_id, log_type, payload)
  values (auth.uid(), p_type, p_payload)
  ;
end;
$$;

revoke all on function public.iron_set_role(text,text) from public;
revoke all on function public.iron_claim_invite(text) from public;
revoke all on function public.iron_create_invite() from public;
revoke all on function public.iron_publish_plan(uuid,text,jsonb) from public;
revoke all on function public.iron_add_student_log(text,jsonb) from public;
grant execute on function public.iron_set_role(text,text) to authenticated;
grant execute on function public.iron_claim_invite(text) to authenticated;
grant execute on function public.iron_create_invite() to authenticated;
grant execute on function public.iron_publish_plan(uuid,text,jsonb) to authenticated;
grant execute on function public.iron_add_student_log(text,jsonb) to authenticated;

-- پس از اجرای migration، مدیر باید حساب مربی را با UUID واقعی تأیید کند:
-- update public.iron_coach_profiles set coach_approved = true
-- where user_id = 'COACH_AUTH_USER_UUID' and role = 'coach';
