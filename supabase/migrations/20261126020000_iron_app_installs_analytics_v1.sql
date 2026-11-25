-- Track unique Android installations without collecting personal identifiers.
create table if not exists public.iron_app_installs_v1 (
  install_id uuid primary key,
  platform text not null default 'android'
    check (platform in ('android')),
  installed_at timestamptz not null default now()
);

alter table public.iron_app_installs_v1 enable row level security;

revoke all on table public.iron_app_installs_v1 from anon, authenticated;
grant insert on table public.iron_app_installs_v1 to anon, authenticated;
grant select on table public.iron_app_installs_v1 to authenticated;
grant all on table public.iron_app_installs_v1 to service_role;

drop policy if exists iron_app_installs_insert_v1 on public.iron_app_installs_v1;
create policy iron_app_installs_insert_v1
  on public.iron_app_installs_v1
  for insert
  to anon, authenticated
  with check (platform = 'android');

drop policy if exists iron_app_installs_main_admin_read_v1 on public.iron_app_installs_v1;
create policy iron_app_installs_main_admin_read_v1
  on public.iron_app_installs_v1
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.iron_admins_v2 a
      where a.user_id = (select auth.uid())
        and a.is_main_admin is true
    )
  );

comment on table public.iron_app_installs_v1 is
  'Anonymous unique Android installation registrations for IRONNOVA; no personal identifiers are stored.';
