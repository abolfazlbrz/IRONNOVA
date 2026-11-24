-- Complete store media access and seller-facing order visibility.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('iron-store-products','iron-store-products',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists iron_store_product_media_insert_v2 on storage.objects;
create policy iron_store_product_media_insert_v2 on storage.objects
for insert to authenticated with check (
 bucket_id='iron-store-products'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and (
  exists(select 1 from public.iron_account_roles_v2 r where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved')
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 )
);
drop policy if exists iron_store_product_media_delete_v2 on storage.objects;
create policy iron_store_product_media_delete_v2 on storage.objects
for delete to authenticated using (
 bucket_id='iron-store-products'
 and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 )
);

drop policy if exists iron_store_discounts_insert_seller_v2 on public.iron_store_discounts_v2;
create policy iron_store_discounts_insert_seller_v2 on public.iron_store_discounts_v2
for insert to authenticated with check (
 seller_id=(select auth.uid())
 and (
  exists(select 1 from public.iron_account_roles_v2 r where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved')
  or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 )
);

drop policy if exists iron_store_orders_select_owner_admin_v2 on public.iron_store_orders_v2;
create policy iron_store_orders_select_owner_admin_v2 on public.iron_store_orders_v2
for select to authenticated using (
 user_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 or exists(select 1 from public.iron_store_order_sellers_v2 s where s.order_id=iron_store_orders_v2.id and s.seller_id=(select auth.uid()))
);
