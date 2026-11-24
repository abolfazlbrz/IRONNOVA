-- The seller, not the administrator, is the only party allowed to confirm payment/order status.
drop policy if exists iron_store_orders_admin_update_v2 on public.iron_store_orders_v2;
revoke update on public.iron_store_orders_v2 from authenticated;
drop policy if exists iron_order_receipts_select_owner_admin_v2 on storage.objects;
create policy iron_order_receipts_select_buyer_seller_v2 on storage.objects
for select to authenticated using (
 bucket_id='iron-order-receipts'
 and (
  (storage.foldername(name))[1]=(select auth.uid())::text
  or exists(select 1 from public.iron_store_order_sellers_v2 s
    where s.seller_id=(select auth.uid()) and s.receipt_path=storage.objects.name)
 )
);
