-- Multi-seller store: coach-owned products, admin approval, discounts, seller orders and notifications.
alter table public.iron_store_products_v2
  add column if not exists seller_id uuid references auth.users(id) on delete set null,
  add column if not exists approval_status text not null default 'approved';
alter table public.iron_store_products_v2
  drop constraint if exists iron_store_products_v2_approval_status_check;
alter table public.iron_store_products_v2
  add constraint iron_store_products_v2_approval_status_check
  check (approval_status in ('pending','approved','rejected'));
do $$
declare v_admin uuid;
begin
  select user_id into v_admin from public.iron_admins_v2 where is_main_admin=true limit 1;
  if v_admin is not null then
    update public.iron_store_products_v2 set seller_id=v_admin where seller_id is null;
  end if;
end $$;

create table if not exists public.iron_store_discounts_v2 (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9_-]{4,32}$'),
  percent_off integer not null check (percent_off between 1 and 90),
  is_active boolean not null default true,
  expires_at timestamptz,
  max_uses integer check (max_uses is null or max_uses > 0),
  used_count integer not null default 0 check (used_count >= 0),
  created_at timestamptz not null default now()
);
create index if not exists idx_iron_store_discounts_seller on public.iron_store_discounts_v2(seller_id,created_at desc);
alter table public.iron_store_discounts_v2 enable row level security;
revoke all on public.iron_store_discounts_v2 from anon,public,authenticated;
grant select,insert,update,delete on public.iron_store_discounts_v2 to authenticated;
drop policy if exists iron_store_discounts_select_owner_v2 on public.iron_store_discounts_v2;
create policy iron_store_discounts_select_owner_v2 on public.iron_store_discounts_v2
for select to authenticated using (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);
drop policy if exists iron_store_discounts_insert_seller_v2 on public.iron_store_discounts_v2;
create policy iron_store_discounts_insert_seller_v2 on public.iron_store_discounts_v2
for insert to authenticated with check (
 seller_id=(select auth.uid())
 and exists(select 1 from public.iron_account_roles_v2 r where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved')
);
drop policy if exists iron_store_discounts_update_owner_v2 on public.iron_store_discounts_v2;
create policy iron_store_discounts_update_owner_v2 on public.iron_store_discounts_v2
for update to authenticated using (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
) with check (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);
drop policy if exists iron_store_discounts_delete_owner_v2 on public.iron_store_discounts_v2;
create policy iron_store_discounts_delete_owner_v2 on public.iron_store_discounts_v2
for delete to authenticated using (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

create table if not exists public.iron_store_order_sellers_v2 (
 order_id uuid not null references public.iron_store_orders_v2(id) on delete cascade,
 seller_id uuid not null references auth.users(id) on delete cascade,
 subtotal_toman bigint not null check(subtotal_toman>=0),
 discount_toman bigint not null default 0 check(discount_toman>=0),
 status text not null default 'awaiting_payment'
   check(status in ('awaiting_payment','paid','processing','shipped','delivered','cancelled','rejected')),
 receipt_path text,
 updated_at timestamptz not null default now(),
 primary key(order_id,seller_id)
);
create index if not exists idx_iron_store_order_sellers_seller on public.iron_store_order_sellers_v2(seller_id,updated_at desc);
alter table public.iron_store_order_sellers_v2 enable row level security;
revoke all on public.iron_store_order_sellers_v2 from anon,public,authenticated;
grant select on public.iron_store_order_sellers_v2 to authenticated;
drop policy if exists iron_store_order_sellers_read_v2 on public.iron_store_order_sellers_v2;
create policy iron_store_order_sellers_read_v2 on public.iron_store_order_sellers_v2
for select to authenticated using (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_store_orders_v2 o where o.id=order_id and o.user_id=(select auth.uid()))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

create table if not exists public.iron_store_notifications_v2 (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references auth.users(id) on delete cascade,
 order_id uuid references public.iron_store_orders_v2(id) on delete cascade,
 event_type text not null check(event_type in ('new_order','receipt_uploaded','order_status')),
 message text not null,
 read_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists idx_iron_store_notifications_seller on public.iron_store_notifications_v2(seller_id,created_at desc);
alter table public.iron_store_notifications_v2 enable row level security;
revoke all on public.iron_store_notifications_v2 from anon,public,authenticated;
grant select on public.iron_store_notifications_v2 to authenticated;
grant update(read_at) on public.iron_store_notifications_v2 to authenticated;
drop policy if exists iron_store_notifications_select_seller_v2 on public.iron_store_notifications_v2;
create policy iron_store_notifications_select_seller_v2 on public.iron_store_notifications_v2
for select to authenticated using(seller_id=(select auth.uid()));
drop policy if exists iron_store_notifications_read_seller_v2 on public.iron_store_notifications_v2;
create policy iron_store_notifications_read_seller_v2 on public.iron_store_notifications_v2
for update to authenticated using(seller_id=(select auth.uid()))
with check(seller_id=(select auth.uid()));

alter table public.iron_store_orders_v2
  add column if not exists subtotal_toman bigint not null default 0,
  add column if not exists discount_toman bigint not null default 0,
  add column if not exists discount_code text;

drop policy if exists iron_store_products_read_v2 on public.iron_store_products_v2;
create policy iron_store_products_read_v2 on public.iron_store_products_v2
for select to authenticated using (
 (is_active and approval_status='approved')
 or seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);
drop policy if exists iron_store_products_admin_write_v2 on public.iron_store_products_v2;
create policy iron_store_products_insert_v2 on public.iron_store_products_v2
for insert to authenticated with check (
 (seller_id=(select auth.uid()) and approval_status='pending'
  and exists(select 1 from public.iron_account_roles_v2 r where r.user_id=(select auth.uid()) and r.role='coach' and r.status='approved'))
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);
create policy iron_store_products_update_v2 on public.iron_store_products_v2
for update to authenticated using (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
) with check (
 seller_id=(select auth.uid())
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);
create policy iron_store_products_delete_v2 on public.iron_store_products_v2
for delete to authenticated using (
 (seller_id=(select auth.uid()) and approval_status='pending')
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
);

create or replace function public.iron_store_protect_product_approval_v2()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin) then return new; end if;
 if tg_op='UPDATE' and (old.seller_id is distinct from new.seller_id or old.approval_status is distinct from new.approval_status) then
   raise exception 'تغییر مالک یا وضعیت تأیید محصول فقط در اختیار مدیر اصلی است';
 end if;
 if new.seller_id is distinct from auth.uid() then raise exception 'مالک محصول معتبر نیست'; end if;
 return new;
end;
$function$;
revoke all on function public.iron_store_protect_product_approval_v2() from public,anon,authenticated;
drop trigger if exists iron_store_protect_product_approval_v2 on public.iron_store_products_v2;
create trigger iron_store_protect_product_approval_v2 before insert or update on public.iron_store_products_v2
for each row execute function public.iron_store_protect_product_approval_v2();

create or replace function public.iron_admin_review_store_product_v2(p_product_id uuid,p_approve boolean)
returns text language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null or not exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin) then
   raise exception 'فقط مدیر اصلی می‌تواند محصول را بررسی کند';
 end if;
 update public.iron_store_products_v2
 set approval_status=case when p_approve then 'approved' else 'rejected' end,
     is_active=case when p_approve then true else false end,
     updated_at=now()
 where id=p_product_id and approval_status='pending';
 if not found then raise exception 'محصول در انتظار بررسی پیدا نشد'; end if;
 return case when p_approve then 'محصول تأیید و در فروشگاه منتشر شد' else 'محصول رد شد' end;
end;
$function$;
revoke all on function public.iron_admin_review_store_product_v2(uuid,boolean) from public,anon;
grant execute on function public.iron_admin_review_store_product_v2(uuid,boolean) to authenticated;

create or replace function public.iron_place_order_v3(p_items jsonb,p_shipping jsonb,p_discount_code text default null)
returns table(order_id uuid,total_toman bigint,subtotal_toman bigint,discount_toman bigint)
language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid(); v_item jsonb; v_product_id uuid; v_qty integer;
 v_product record; v_main_admin uuid; v_total bigint:=0; v_subtotal bigint:=0;
 v_discount bigint:=0; v_items jsonb:='[]'::jsonb; v_shipping jsonb;
 v_seller_totals jsonb:='{}'::jsonb; v_seller_key text; v_seller_id uuid;
 v_seller_subtotal bigint; v_code record; v_seller_discount bigint:=0; v_code_text text;
 v_order_id uuid;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
 if p_items is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'سبد خرید معتبر نیست'; end if;
 if p_shipping is null or jsonb_typeof(p_shipping) is distinct from 'object'
   or length(trim(coalesce(p_shipping->>'name',''))) < 3
   or length(trim(coalesce(p_shipping->>'phone',''))) < 8
   or length(trim(coalesce(p_shipping->>'address',''))) < 12 then raise exception 'اطلاعات ارسال کامل نیست'; end if;
 select user_id into v_main_admin from public.iron_admins_v2 where is_main_admin=true limit 1;
 if v_main_admin is null then raise exception 'حساب فروشنده اصلی تنظیم نشده است'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  begin v_product_id:=(v_item->>'product_id')::uuid; v_qty:=(v_item->>'quantity')::integer;
  exception when others then raise exception 'شناسه یا تعداد محصول معتبر نیست'; end;
  if v_product_id is null or v_qty is null or v_qty<1 or v_qty>20 then raise exception 'تعداد یا شناسه محصول معتبر نیست'; end if;
  select id,name,price_toman,stock,is_active,approval_status,seller_id into v_product
  from public.iron_store_products_v2 where id=v_product_id for update;
  if not found or not v_product.is_active or v_product.approval_status<>'approved' then raise exception 'محصول در دسترس نیست'; end if;
  if v_product.stock<v_qty then raise exception 'موجودی محصول % کافی نیست',v_product.name; end if;
  update public.iron_store_products_v2 set stock=stock-v_qty,updated_at=now() where id=v_product_id;
  v_seller_id:=coalesce(v_product.seller_id,v_main_admin);
  v_subtotal:=v_subtotal+(v_product.price_toman*v_qty);
  v_seller_key:=v_seller_id::text;
  v_seller_totals:=jsonb_set(v_seller_totals,array[v_seller_key],to_jsonb(coalesce((v_seller_totals->>v_seller_key)::bigint,0)+(v_product.price_toman*v_qty)),true);
  v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_product.id,'seller_id',v_seller_id,'name',v_product.name,'unit_price_toman',v_product.price_toman,'quantity',v_qty));
 end loop;
 v_code_text:=nullif(upper(trim(coalesce(p_discount_code,''))),'');
 if v_code_text is not null then
  select * into v_code from public.iron_store_discounts_v2 d
  where d.code=v_code_text and d.is_active and (d.expires_at is null or d.expires_at>now())
    and (d.max_uses is null or d.used_count<d.max_uses)
  for update;
  if not found then raise exception 'کد تخفیف معتبر یا فعال نیست'; end if;
  v_seller_key:=v_code.seller_id::text;
  v_seller_subtotal:=coalesce((v_seller_totals->>v_seller_key)::bigint,0);
  if v_seller_subtotal=0 then raise exception 'این کد تخفیف برای محصولات این سبد معتبر نیست'; end if;
  v_seller_discount:=floor(v_seller_subtotal*v_code.percent_off/100.0)::bigint;
  v_discount:=v_seller_discount;
  update public.iron_store_discounts_v2 set used_count=used_count+1 where id=v_code.id;
 end if;
 v_total:=greatest(0,v_subtotal-v_discount);
 v_shipping:=jsonb_build_object('name',trim(p_shipping->>'name'),'phone',trim(p_shipping->>'phone'),'address',trim(p_shipping->>'address'));
 insert into public.iron_store_orders_v2(user_id,items,total_toman,subtotal_toman,discount_toman,discount_code,shipping_info,status)
 values(v_uid,v_items,v_total,v_subtotal,v_discount,v_code_text,v_shipping,'pending')
 returning id into v_order_id;
 for v_seller_key in select jsonb_object_keys(v_seller_totals) loop
  v_seller_id:=v_seller_key::uuid;
  v_seller_subtotal:=(v_seller_totals->>v_seller_key)::bigint;
  v_seller_discount:=case when v_code_text is not null and v_code.seller_id=v_seller_id then v_discount else 0 end;
  insert into public.iron_store_order_sellers_v2(order_id,seller_id,subtotal_toman,discount_toman,status)
  values(v_order_id,v_seller_id,v_seller_subtotal,v_seller_discount,'awaiting_payment');
  insert into public.iron_store_notifications_v2(seller_id,order_id,event_type,message)
  values(v_seller_id,v_order_id,'new_order','سفارش جدید در فروشگاه IRONNOVA ثبت شد.');
 end loop;
 return query select v_order_id,v_total,v_subtotal,v_discount;
end;
$function$;
revoke all on function public.iron_place_order_v3(jsonb,jsonb,text) from public,anon;
grant execute on function public.iron_place_order_v3(jsonb,jsonb,text) to authenticated;

create or replace function public.iron_submit_order_receipt_v2(p_order_id uuid,p_receipt_path text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
 if p_receipt_path is null or left(p_receipt_path,length(v_uid::text)+1)<>v_uid::text||'/' then raise exception 'مسیر فایل رسید معتبر نیست'; end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='iron-order-receipts' and o.name=p_receipt_path) then raise exception 'فایل رسید پیدا نشد'; end if;
 update public.iron_store_orders_v2 set receipt_url=p_receipt_path,status='awaiting_payment',updated_at=now()
 where id=p_order_id and user_id=v_uid and status='pending' and receipt_url is null;
 if not found then raise exception 'سفارش برای ثبت رسید در دسترس نیست'; end if;
 update public.iron_store_order_sellers_v2 set receipt_path=p_receipt_path,updated_at=now()
 where order_id=p_order_id;
 insert into public.iron_store_notifications_v2(seller_id,order_id,event_type,message)
 select seller_id,p_order_id,'receipt_uploaded','رسید پرداخت سفارش بارگذاری شد و منتظر بررسی شماست.'
 from public.iron_store_order_sellers_v2 where order_id=p_order_id;
 return 'رسید پرداخت برای فروشنده یا فروشندگان سفارش ارسال شد';
end;
$function$;
revoke all on function public.iron_submit_order_receipt_v2(uuid,text) from public,anon;
grant execute on function public.iron_submit_order_receipt_v2(uuid,text) to authenticated;

create or replace function public.iron_seller_update_order_v2(p_order_id uuid,p_status text)
returns text language plpgsql security definer set search_path=''
as $function$
declare v_uid uuid:=auth.uid(); v_count integer; v_all_paid boolean;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if p_status not in ('paid','processing','shipped','delivered','cancelled','rejected') then raise exception 'وضعیت سفارش معتبر نیست'; end if;
 update public.iron_store_order_sellers_v2 set status=p_status,updated_at=now()
 where order_id=p_order_id and seller_id=v_uid and receipt_path is not null;
 if not found then raise exception 'این سفارش برای فروشگاه شما نیست یا رسیدی برای آن ثبت نشده است'; end if;
 insert into public.iron_store_notifications_v2(seller_id,order_id,event_type,message)
 values(v_uid,p_order_id,'order_status','وضعیت سفارش توسط فروشنده به‌روزرسانی شد: '||p_status);
 select count(*),bool_and(status in ('paid','processing','shipped','delivered')) into v_count,v_all_paid
 from public.iron_store_order_sellers_v2 where order_id=p_order_id;
 if v_count=1 then
   update public.iron_store_orders_v2 set status=p_status,updated_at=now() where id=p_order_id;
 elsif v_all_paid then
   update public.iron_store_orders_v2 set status='paid',updated_at=now() where id=p_order_id;
 end if;
 return 'وضعیت سفارش فروشگاه شما ثبت شد';
end;
$function$;
revoke all on function public.iron_seller_update_order_v2(uuid,text) from public,anon;
grant execute on function public.iron_seller_update_order_v2(uuid,text) to authenticated;

drop policy if exists iron_order_receipts_select_owner_admin_v2 on storage.objects;
create policy iron_order_receipts_select_owner_admin_v2 on storage.objects for select to authenticated
using(bucket_id='iron-order-receipts' and (
 (storage.foldername(name))[1]=(select auth.uid())::text
 or exists(select 1 from public.iron_admins_v2 a where a.user_id=(select auth.uid()) and a.is_main_admin)
 or exists(select 1 from public.iron_store_order_sellers_v2 s where s.seller_id=(select auth.uid()) and s.receipt_path=storage.objects.name)
));
