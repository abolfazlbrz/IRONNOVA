-- Release seller discount usage when that seller rejects/cancels an order.
create or replace function public.iron_seller_update_order_v2(p_order_id uuid,p_status text)
returns text language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid();
 v_current text;
 v_items jsonb;
 v_item jsonb;
 v_count integer;
 v_all_paid boolean;
 v_all_processing boolean;
 v_all_shipped boolean;
 v_all_delivered boolean;
 v_any_rejected boolean;
 v_discount_code text;
 v_seller_discount bigint;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if p_status not in ('paid','processing','shipped','delivered','cancelled','rejected') then
  raise exception 'وضعیت سفارش معتبر نیست';
 end if;
 select status,discount_toman into v_current,v_seller_discount
 from public.iron_store_order_sellers_v2
 where order_id=p_order_id and seller_id=v_uid and receipt_path is not null
 for update;
 if not found then raise exception 'این سفارش برای فروشگاه شما نیست یا رسیدی برای آن ثبت نشده است'; end if;
 if v_current in ('delivered','cancelled','rejected') then
  raise exception 'این سفارش قبلاً به وضعیت نهایی رسیده است';
 end if;
 if p_status='paid' and v_current<>'awaiting_payment' then raise exception 'تأیید پرداخت فقط پس از دریافت رسید و در وضعیت انتظار پرداخت ممکن است'; end if;
 if p_status='processing' and v_current<>'paid' then raise exception 'ابتدا پرداخت را تأیید کن'; end if;
 if p_status='shipped' and v_current<>'processing' then raise exception 'ابتدا سفارش را در حال آماده‌سازی قرار بده'; end if;
 if p_status='delivered' and v_current<>'shipped' then raise exception 'ابتدا سفارش را ارسال‌شده ثبت کن'; end if;
 if p_status in ('cancelled','rejected') and v_current not in ('awaiting_payment','paid','processing') then
  raise exception 'در این مرحله امکان رد یا لغو سفارش وجود ندارد';
 end if;

 if p_status in ('cancelled','rejected') then
  select items,discount_code into v_items,v_discount_code
  from public.iron_store_orders_v2 where id=p_order_id;
  for v_item in
   select value from jsonb_array_elements(coalesce(v_items,'[]'::jsonb)) as x(value)
   where value->>'seller_id'=v_uid::text
  loop
   update public.iron_store_products_v2
   set stock=stock+greatest(0,coalesce((v_item->>'quantity')::integer,0)),updated_at=now()
   where id=(v_item->>'product_id')::uuid and seller_id=v_uid;
  end loop;
  if v_discount_code is not null and coalesce(v_seller_discount,0)>0 then
   update public.iron_store_discounts_v2
   set used_count=greatest(0,used_count-1),updated_at=now()
   where seller_id=v_uid and code=v_discount_code;
  end if;
 end if;

 update public.iron_store_order_sellers_v2
 set status=p_status,updated_at=now()
 where order_id=p_order_id and seller_id=v_uid;
 insert into public.iron_store_notifications_v2(seller_id,order_id,event_type,message)
 values(v_uid,p_order_id,'order_status','وضعیت سفارش توسط فروشنده به‌روزرسانی شد: '||p_status);

 select count(*),
  bool_and(status in ('paid','processing','shipped','delivered')),
  bool_and(status in ('processing','shipped','delivered')),
  bool_and(status in ('shipped','delivered')),
  bool_and(status='delivered'),
  bool_or(status in ('rejected','cancelled'))
 into v_count,v_all_paid,v_all_processing,v_all_shipped,v_all_delivered,v_any_rejected
 from public.iron_store_order_sellers_v2 where order_id=p_order_id;
 update public.iron_store_orders_v2
 set status=case
  when v_any_rejected then 'rejected'
  when v_all_delivered then 'delivered'
  when v_all_shipped then 'shipped'
  when v_all_processing then 'processing'
  when v_all_paid then 'paid'
  else 'awaiting_payment'
 end,updated_at=now()
 where id=p_order_id;
 return 'وضعیت سفارش فروشگاه شما ثبت شد';
end;
$function$;
revoke all on function public.iron_seller_update_order_v2(uuid,text) from public,anon;
grant execute on function public.iron_seller_update_order_v2(uuid,text) to authenticated;
