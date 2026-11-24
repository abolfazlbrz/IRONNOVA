drop function if exists public.iron_admin_pending_coaches_v2();
create function public.iron_admin_pending_coaches_v2()
returns table(
 user_id uuid,
 full_name text,
 specialty text,
 bio text,
 credentials text,
 phone text,
 photo_url text,
 experience_years integer,
 city text,
 training_modes text[],
 achievements text,
 requested_at timestamptz
)
language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null or not exists(
  select 1 from public.iron_admins_v2 a
  where a.user_id=auth.uid() and a.is_main_admin=true
 ) then
  raise exception 'فقط مدیر اصلی اجازه مشاهده درخواست‌ها را دارد';
 end if;
 return query
 select r.user_id,
  coalesce(p.full_name,''),
  coalesce(p.specialty,''),
  coalesce(p.bio,''),
  coalesce(p.credentials,''),
  coalesce(p.phone,''),
  coalesce(p.photo_url,''),
  coalesce(p.experience_years,0),
  coalesce(p.city,''),
  coalesce(p.training_modes,array[]::text[]),
  coalesce(p.achievements,''),
  r.created_at
 from public.iron_account_roles_v2 r
 left join public.iron_coach_profiles_v2 p on p.user_id=r.user_id
 where r.role='coach' and r.status='pending'
 order by r.created_at asc;
end;
$function$;
revoke all on function public.iron_admin_pending_coaches_v2() from public,anon;
grant execute on function public.iron_admin_pending_coaches_v2() to authenticated;
