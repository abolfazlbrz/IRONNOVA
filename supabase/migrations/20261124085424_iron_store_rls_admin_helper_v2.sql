create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to anon, authenticated;
create or replace function private.iron_is_main_admin_v2()
returns boolean language sql stable security definer set search_path=''
as $function$
 select coalesce((select a.is_main_admin from public.iron_admins_v2 a
 where a.user_id=(select auth.uid()) limit 1),false)
 where (select auth.uid()) is not null;
$function$;
revoke all on function private.iron_is_main_admin_v2() from public;
grant execute on function private.iron_is_main_admin_v2() to anon,authenticated;
drop policy if exists iron_store_products_read_v2 on public.iron_store_products_v2;
create policy iron_store_products_read_v2 on public.iron_store_products_v2 for select to anon,authenticated using ((is_active and approval_status='approved') or seller_id=(select auth.uid()) or (select private.iron_is_main_admin_v2()));
drop policy if exists iron_store_products_insert_v2 on public.iron_store_products_v2;
create policy iron_store_products_insert_v2 on public.iron_store_products_v2 for insert to authenticated with check ((seller_id=(select auth.uid()) and approval_status='pending' and exists(select 1 from public.iron_account_roles_v2 r where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved')) or (select private.iron_is_main_admin_v2()));
drop policy if exists iron_store_products_update_v2 on public.iron_store_products_v2;
create policy iron_store_products_update_v2 on public.iron_store_products_v2 for update to authenticated using (seller_id=(select auth.uid()) or (select private.iron_is_main_admin_v2())) with check (seller_id=(select auth.uid()) or (select private.iron_is_main_admin_v2()));
drop policy if exists iron_store_products_delete_v2 on public.iron_store_products_v2;
create policy iron_store_products_delete_v2 on public.iron_store_products_v2 for delete to authenticated using ((seller_id=(select auth.uid()) and approval_status='pending') or (select private.iron_is_main_admin_v2()));