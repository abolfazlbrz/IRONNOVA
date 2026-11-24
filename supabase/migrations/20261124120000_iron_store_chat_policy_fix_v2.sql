drop policy if exists iron_store_messages_select_participants_v2 on public.iron_store_messages_v2;
create policy iron_store_messages_select_participants_v2 on public.iron_store_messages_v2
for select to authenticated using (
 (select auth.uid()) in (seller_id,buyer_id)
 and exists(select 1 from public.iron_store_products_v2 p
   where p.id=iron_store_messages_v2.product_id
     and p.seller_id=iron_store_messages_v2.seller_id)
);
