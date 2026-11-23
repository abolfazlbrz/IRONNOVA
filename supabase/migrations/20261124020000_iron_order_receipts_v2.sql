-- Private order-receipt storage and owner submission RPC.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('iron-order-receipts','iron-order-receipts',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists iron_order_receipts_insert_owner_v2 on storage.objects;
create policy iron_order_receipts_insert_owner_v2 on storage.objects for insert to authenticated
with check(bucket_id='iron-order-receipts' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists iron_order_receipts_select_owner_admin_v2 on storage.objects;
create policy iron_order_receipts_select_owner_admin_v2 on storage.objects for select to authenticated
using(bucket_id='iron-order-receipts' and (
 (storage.foldername(name))[1]=auth.uid()::text
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin)
));

create or replace function public.iron_submit_order_receipt_v2(p_order_id uuid,p_receipt_path text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
 if p_receipt_path is null or left(p_receipt_path,length(v_uid::text)+1)<>v_uid::text||'/' then
  raise exception 'مسیر فایل رسید معتبر نیست';
 end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='iron-order-receipts' and o.name=p_receipt_path) then
  raise exception 'فایل رسید در فضای ذخیره‌سازی پیدا نشد';
 end if;
 update public.iron_store_orders_v2 set receipt_url=p_receipt_path,status='awaiting_payment',updated_at=now()
 where id=p_order_id and user_id=v_uid and status='pending' and receipt_url is null;
 if not found then raise exception 'سفارش برای ثبت رسید در دسترس نیست'; end if;
 return 'رسید پرداخت ثبت شد و در انتظار بررسی مدیریت است';
end;
$function$;
revoke all on function public.iron_submit_order_receipt_v2(uuid,text) from public,anon;
grant execute on function public.iron_submit_order_receipt_v2(uuid,text) to authenticated;
