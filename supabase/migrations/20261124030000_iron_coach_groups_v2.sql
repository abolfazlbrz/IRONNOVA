-- Private coach groups and group chat.
create table if not exists public.iron_coach_groups_v2(
 id uuid primary key default gen_random_uuid(),
 coach_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 80),
 created_at timestamptz not null default now()
);
create index if not exists idx_iron_coach_groups_coach_v2 on public.iron_coach_groups_v2(coach_id,created_at desc);
create table if not exists public.iron_coach_group_members_v2(
 group_id uuid not null references public.iron_coach_groups_v2(id) on delete cascade,
 student_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(group_id,student_id)
);
create index if not exists idx_iron_group_members_student_v2 on public.iron_coach_group_members_v2(student_id,group_id);
create table if not exists public.iron_coach_group_messages_v2(
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.iron_coach_groups_v2(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 4000),
 created_at timestamptz not null default now()
);
create index if not exists idx_iron_group_messages_created_v2 on public.iron_coach_group_messages_v2(group_id,created_at desc);
alter table public.iron_coach_groups_v2 enable row level security;
alter table public.iron_coach_group_members_v2 enable row level security;
alter table public.iron_coach_group_messages_v2 enable row level security;
create or replace function public.iron_is_group_member_v2(p_group_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
 select auth.uid() is not null and exists(
  select 1 from public.iron_coach_group_members_v2 m where m.group_id=p_group_id and m.student_id=auth.uid()
 );
$function$;
create or replace function public.iron_is_group_coach_v2(p_group_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
 select auth.uid() is not null and exists(
  select 1 from public.iron_coach_groups_v2 g where g.id=p_group_id and g.coach_id=auth.uid()
 );
$function$;
revoke all on function public.iron_is_group_member_v2(uuid),public.iron_is_group_coach_v2(uuid) from public,anon;
grant execute on function public.iron_is_group_member_v2(uuid),public.iron_is_group_coach_v2(uuid) to authenticated;

drop policy if exists iron_coach_groups_select_member_v2 on public.iron_coach_groups_v2;
create policy iron_coach_groups_select_member_v2 on public.iron_coach_groups_v2 for select to authenticated
using(coach_id=auth.uid() or public.iron_is_group_member_v2(id));
drop policy if exists iron_group_members_select_v2 on public.iron_coach_group_members_v2;
create policy iron_group_members_select_v2 on public.iron_coach_group_members_v2 for select to authenticated
using(student_id=auth.uid() or public.iron_is_group_coach_v2(group_id));
drop policy if exists iron_group_messages_select_v2 on public.iron_coach_group_messages_v2;
create policy iron_group_messages_select_v2 on public.iron_coach_group_messages_v2 for select to authenticated
using(public.iron_is_group_coach_v2(group_id) or public.iron_is_group_member_v2(group_id));
drop policy if exists iron_group_messages_insert_v2 on public.iron_coach_group_messages_v2;
create policy iron_group_messages_insert_v2 on public.iron_coach_group_messages_v2 for insert to authenticated
with check(sender_id=auth.uid() and (public.iron_is_group_coach_v2(group_id) or public.iron_is_group_member_v2(group_id)));
revoke all on public.iron_coach_groups_v2,public.iron_coach_group_members_v2,public.iron_coach_group_messages_v2 from anon,authenticated;
grant select on public.iron_coach_groups_v2,public.iron_coach_group_members_v2 to authenticated;
grant select,insert on public.iron_coach_group_messages_v2 to authenticated;

create or replace function public.iron_create_group_v2(p_name text,p_student_ids uuid[])
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_group_id uuid; v_count integer;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'نام گروه باید بین ۲ تا ۸۰ نویسه باشد'; end if;
 if coalesce(array_length(p_student_ids,1),0) not between 1 and 100 then raise exception 'حداقل یک شاگرد و حداکثر ۱۰۰ شاگرد انتخاب کن'; end if;
 if not exists(select 1 from public.iron_account_roles_v2 r where r.user_id=v_uid and r.role='coach' and r.status='approved') then
  raise exception 'فقط مربی تأییدشده می‌تواند گروه بسازد';
 end if;
 select count(distinct x) into v_count from unnest(p_student_ids) as x;
 if v_count<>array_length(p_student_ids,1) then raise exception 'شناسه شاگرد تکراری است'; end if;
 if exists(select 1 from unnest(p_student_ids) as x where not exists(
  select 1 from public.iron_coach_students_v2 l where l.coach_id=v_uid and l.student_id=x and l.status='approved'
 )) then raise exception 'همه اعضای گروه باید شاگرد متصل و تأییدشده باشند'; end if;
 insert into public.iron_coach_groups_v2(coach_id,name) values(v_uid,trim(p_name)) returning id into v_group_id;
 insert into public.iron_coach_group_members_v2(group_id,student_id) select v_group_id,x from unnest(p_student_ids) as x;
 return v_group_id;
end;
$function$;
revoke all on function public.iron_create_group_v2(text,uuid[]) from public,anon;
grant execute on function public.iron_create_group_v2(text,uuid[]) to authenticated;
