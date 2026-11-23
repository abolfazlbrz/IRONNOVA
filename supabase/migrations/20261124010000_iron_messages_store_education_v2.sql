-- IRONNOVA messaging, store, education and secure order flow
-- Applied to Supabase project hcdcllknzxllyuptlwpy on 2026-11-24.

create table if not exists public.iron_messages_v2 (
 id uuid primary key default gen_random_uuid(),
 coach_id uuid not null references auth.users(id) on delete cascade,
 student_id uuid not null references auth.users(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check (char_length(trim(body)) between 1 and 4000),
 attachment_url text,
 created_at timestamptz not null default now(),
 read_at timestamptz,
 constraint iron_messages_v2_distinct_participants check (coach_id <> student_id),
 constraint iron_messages_v2_sender_check check (sender_id = coach_id or sender_id = student_id)
);
create index if not exists idx_iron_messages_pair_created_v2 on public.iron_messages_v2(coach_id,student_id,created_at desc);
create index if not exists idx_iron_messages_sender_v2 on public.iron_messages_v2(sender_id);
create index if not exists idx_iron_messages_student_created_v2 on public.iron_messages_v2(student_id,created_at desc);
alter table public.iron_messages_v2 enable row level security;
drop policy if exists iron_messages_select_linked_v2 on public.iron_messages_v2;
create policy iron_messages_select_linked_v2 on public.iron_messages_v2 for select to authenticated
using (auth.uid() in (coach_id,student_id) and exists(
 select 1 from public.iron_coach_students_v2 l
 where l.coach_id=iron_messages_v2.coach_id and l.student_id=iron_messages_v2.student_id and l.status='approved'
));
drop policy if exists iron_messages_insert_sender_v2 on public.iron_messages_v2;
create policy iron_messages_insert_sender_v2 on public.iron_messages_v2 for insert to authenticated
with check (sender_id=auth.uid() and auth.uid() in (coach_id,student_id) and exists(
 select 1 from public.iron_coach_students_v2 l
 where l.coach_id=iron_messages_v2.coach_id and l.student_id=iron_messages_v2.student_id and l.status='approved'
));
drop policy if exists iron_messages_update_recipient_v2 on public.iron_messages_v2;
create policy iron_messages_update_recipient_v2 on public.iron_messages_v2 for update to authenticated
using (auth.uid()=case when sender_id=coach_id then student_id else coach_id end)
with check (auth.uid()=case when sender_id=coach_id then student_id else coach_id end);
revoke all on public.iron_messages_v2 from anon,authenticated;
grant select,insert on public.iron_messages_v2 to authenticated;
grant update(read_at) on public.iron_messages_v2 to authenticated;

create table if not exists public.iron_store_products_v2 (
 id uuid primary key default gen_random_uuid(),
 name text not null check(char_length(trim(name)) between 2 and 120),
 description text not null default '',
 category text not null default 'عمومی',
 price_toman bigint not null check(price_toman >= 0),
 image_url text,
 stock integer not null default 0 check(stock >= 0),
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.iron_store_products_v2 enable row level security;
drop policy if exists iron_store_products_read_v2 on public.iron_store_products_v2;
create policy iron_store_products_read_v2 on public.iron_store_products_v2 for select to authenticated
using (is_active or exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
drop policy if exists iron_store_products_admin_write_v2 on public.iron_store_products_v2;
create policy iron_store_products_admin_write_v2 on public.iron_store_products_v2 for all to authenticated
using (exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin))
with check (exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
revoke all on public.iron_store_products_v2 from anon,authenticated;
grant select,insert,update,delete on public.iron_store_products_v2 to authenticated;

create table if not exists public.iron_store_orders_v2 (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items) between 1 and 50),
 total_toman bigint not null check(total_toman >= 0),
 status text not null default 'pending' check(status in ('pending','awaiting_payment','paid','processing','shipped','delivered','cancelled','rejected')),
 shipping_info jsonb not null default '{}'::jsonb check(jsonb_typeof(shipping_info)='object'),
 receipt_url text,
 admin_note text not null default '',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists idx_iron_store_orders_user_created_v2 on public.iron_store_orders_v2(user_id,created_at desc);
alter table public.iron_store_orders_v2 enable row level security;
drop policy if exists iron_store_orders_select_owner_admin_v2 on public.iron_store_orders_v2;
create policy iron_store_orders_select_owner_admin_v2 on public.iron_store_orders_v2 for select to authenticated
using(user_id=auth.uid() or exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
drop policy if exists iron_store_orders_insert_owner_v2 on public.iron_store_orders_v2;
create policy iron_store_orders_insert_owner_v2 on public.iron_store_orders_v2 for insert to authenticated
with check(user_id=auth.uid() and status='pending' and receipt_url is null and admin_note='');
drop policy if exists iron_store_orders_admin_update_v2 on public.iron_store_orders_v2;
create policy iron_store_orders_admin_update_v2 on public.iron_store_orders_v2 for update to authenticated
using(exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin))
with check(exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
revoke all on public.iron_store_orders_v2 from anon,authenticated;
grant select,update on public.iron_store_orders_v2 to authenticated;

create table if not exists public.iron_education_v2 (
 id uuid primary key default gen_random_uuid(),
 title text not null check(char_length(trim(title)) between 2 and 160),
 description text not null default '',
 category text not null default 'عمومی',
 video_url text not null check(video_url ~ '^https://'),
 thumbnail_url text,
 is_published boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.iron_education_v2 enable row level security;
drop policy if exists iron_education_read_published_v2 on public.iron_education_v2;
create policy iron_education_read_published_v2 on public.iron_education_v2 for select to authenticated
using(is_published or exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
drop policy if exists iron_education_admin_write_v2 on public.iron_education_v2;
create policy iron_education_admin_write_v2 on public.iron_education_v2 for all to authenticated
using(exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin))
with check(exists(select 1 from public.iron_admins_v2 a where a.user_id=auth.uid() and a.is_main_admin));
revoke all on public.iron_education_v2 from anon,authenticated;
grant select,insert,update,delete on public.iron_education_v2 to authenticated;

create or replace function public.iron_place_order_v2(p_items jsonb,p_shipping jsonb)
returns table(order_id uuid,total_toman bigint)
language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid(); v_item jsonb; v_product_id uuid; v_qty integer;
 v_product record; v_total bigint:=0; v_items jsonb:='[]'::jsonb; v_shipping jsonb;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب کاربری شوید'; end if;
 if p_items is null or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'سبد خرید معتبر نیست'; end if;
 if p_shipping is null or jsonb_typeof(p_shipping) is distinct from 'object'
    or length(trim(coalesce(p_shipping->>'name',''))) < 3
    or length(trim(coalesce(p_shipping->>'phone',''))) < 8
    or length(trim(coalesce(p_shipping->>'address',''))) < 12 then raise exception 'اطلاعات ارسال کامل نیست'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  begin v_product_id := (v_item->>'product_id')::uuid; v_qty := (v_item->>'quantity')::integer;
  exception when others then raise exception 'شناسه یا تعداد محصول معتبر نیست'; end;
  if v_product_id is null or v_qty is null or v_qty<1 or v_qty>20 then raise exception 'تعداد یا شناسه محصول معتبر نیست'; end if;
  select id,name,price_toman,stock,is_active into v_product from public.iron_store_products_v2 where id=v_product_id for update;
  if not found or not v_product.is_active then raise exception 'محصول در دسترس نیست'; end if;
  if v_product.stock<v_qty then raise exception 'موجودی محصول % کافی نیست',v_product.name; end if;
  update public.iron_store_products_v2 set stock=stock-v_qty,updated_at=now() where id=v_product_id;
  v_total:=v_total+(v_product.price_toman*v_qty);
  v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_product.name,'unit_price_toman',v_product.price_toman,'quantity',v_qty));
 end loop;
 v_shipping:=jsonb_build_object('name',trim(p_shipping->>'name'),'phone',trim(p_shipping->>'phone'),'address',trim(p_shipping->>'address'));
 return query insert into public.iron_store_orders_v2 as inserted(user_id,items,total_toman,shipping_info,status)
 values(v_uid,v_items,v_total,v_shipping,'pending') returning inserted.id,inserted.total_toman;
end;
$function$;
revoke all on function public.iron_place_order_v2(jsonb,jsonb) from public,anon;
grant execute on function public.iron_place_order_v2(jsonb,jsonb) to authenticated;

create or replace function public.iron_restore_cancelled_order_stock_v2()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_item jsonb;
begin
 if new.status='cancelled' and old.status is distinct from 'cancelled' then
  for v_item in select value from jsonb_array_elements(old.items) loop
   update public.iron_store_products_v2 set stock=stock+greatest(0,coalesce((v_item->>'quantity')::integer,0)),updated_at=now()
   where id=(v_item->>'product_id')::uuid;
  end loop;
 end if;
 return new;
end;
$function$;
revoke all on function public.iron_restore_cancelled_order_stock_v2() from public,anon,authenticated;
drop trigger if exists iron_restore_cancelled_order_stock_v2 on public.iron_store_orders_v2;
create trigger iron_restore_cancelled_order_stock_v2 after update of status on public.iron_store_orders_v2
for each row execute function public.iron_restore_cancelled_order_stock_v2();

insert into public.iron_store_products_v2(name,description,category,price_toman,stock,is_active)
select v.name,v.description,v.category,v.price,v.stock,true
from (values
 ('شیکر ورزشی','شیکر درب‌دار برای ترکیب نوشیدنی‌های ورزشی','لوازم ورزشی',250000::bigint,20),
 ('کش تمرینی','کش مقاومتی برای تمرین در خانه و گرم‌کردن','تمرین خانگی',180000::bigint,30),
 ('دستکش بدنسازی','دستکش تمرین عمومی','لوازم ورزشی',420000::bigint,15),
 ('قمقمه ورزشی','قمقمه قابل حمل برای آب‌رسانی تمرین','لوازم ورزشی',220000::bigint,25),
 ('طناب ورزشی','طناب ساده برای تمرین هوازی','تمرین خانگی',160000::bigint,20)
) as v(name,description,category,price,stock)
where not exists(select 1 from public.iron_store_products_v2 p where p.name=v.name);
