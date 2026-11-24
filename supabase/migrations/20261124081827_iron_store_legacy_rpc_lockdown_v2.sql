-- Prevent legacy checkout RPCs and client-side discount usage-count tampering.
revoke all on function public.iron_place_order_v2(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.iron_restore_cancelled_order_stock_v2() from public,anon,authenticated;
revoke update on public.iron_store_discounts_v2 from authenticated;
grant update(code,percent_off,is_active,expires_at,max_uses) on public.iron_store_discounts_v2 to authenticated;
