-- Public storefront browsing is available without sign-in; checkout remains authenticated.
grant select on public.iron_store_products_v2 to anon;
drop policy if exists iron_store_products_read_v2 on public.iron_store_products_v2;
create policy iron_store_products_read_v2 on public.iron_store_products_v2
for select to anon,authenticated using (
 (is_active and approval_status='approved')
 or seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a
   where a.user_id=(select auth.uid()) and a.is_main_admin)
);
