create or replace function public.iron_public_coach_directory_v1()
returns table (
  user_id uuid,
  full_name text,
  specialty text,
  bio text,
  credentials text,
  photo_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'برای مشاهده مربیان باید وارد حساب کاربری شوی';
  end if;

  return query
  select p.user_id, p.full_name, p.specialty, p.bio, p.credentials, p.photo_url
  from public.iron_coach_profiles_v2 p
  join public.iron_account_roles_v2 r on r.user_id = p.user_id
  where r.role = 'coach'
    and r.status = 'approved'
    and p.public_visible is true
  order by p.updated_at desc nulls last, p.full_name asc;
end;
$$;

revoke all on function public.iron_public_coach_directory_v1() from public;
revoke all on function public.iron_public_coach_directory_v1() from anon;
grant execute on function public.iron_public_coach_directory_v1() to authenticated;
