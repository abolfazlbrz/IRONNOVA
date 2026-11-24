-- Buyer/seller product inquiry chat, restricted to the product owner and the buyer.
alter table public.iron_store_notifications_v2
  drop constraint if exists iron_store_notifications_v2_event_type_check;
alter table public.iron_store_notifications_v2
  add constraint iron_store_notifications_v2_event_type_check
  check(event_type in ('new_order','receipt_uploaded','order_status','message'));

create table if not exists public.iron_store_messages_v2 (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.iron_store_products_v2(id) on delete cascade,
 seller_id uuid not null references auth.users(id) on delete cascade,
 buyer_id uuid not null references auth.users(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 3000),
 read_at timestamptz,
 created_at timestamptz not null default now(),
 constraint iron_store_messages_distinct_participants_v2 check(seller_id<>buyer_id),
 constraint iron_store_messages_sender_v2 check(sender_id=seller_id or sender_id=buyer_id)
);
create index if not exists idx_iron_store_messages_thread_v2
 on public.iron_store_messages_v2(product_id,buyer_id,created_at);
alter table public.iron_store_messages_v2 enable row level security;
revoke all on public.iron_store_messages_v2 from anon,public,authenticated;
grant select on public.iron_store_messages_v2 to authenticated;
grant update(read_at) on public.iron_store_messages_v2 to authenticated;

drop policy if exists iron_store_messages_select_participants_v2 on public.iron_store_messages_v2;
create policy iron_store_messages_select_participants_v2 on public.iron_store_messages_v2
for select to authenticated using (
 (select auth.uid()) in (seller_id,buyer_id)
 and exists(select 1 from public.iron_store_products_v2 p
   where p.id=product_id and p.seller_id=seller_id)
);
drop policy if exists iron_store_messages_read_recipient_v2 on public.iron_store_messages_v2;
create policy iron_store_messages_read_recipient_v2 on public.iron_store_messages_v2
for update to authenticated using (
 (select auth.uid()) in (seller_id,buyer_id) and sender_id<>(select auth.uid())
) with check (
 (select auth.uid()) in (seller_id,buyer_id) and sender_id<>(select auth.uid())
);

create or replace function public.iron_store_send_message_v2(p_product_id uuid,p_buyer_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid(); v_seller uuid; v_id uuid;
begin
 if v_uid is null then raise exception 'ابتدا وارد حساب شوید'; end if;
 if p_body is null or char_length(trim(p_body)) not between 1 and 3000 then raise exception 'متن پیام معتبر نیست'; end if;
 select seller_id into v_seller from public.iron_store_products_v2
 where id=p_product_id and seller_id is not null;
 if not found or v_seller=p_buyer_id then raise exception 'محصول یا گفت‌وگو معتبر نیست'; end if;
 if v_uid<>v_seller and v_uid<>p_buyer_id then raise exception 'اجازه ارسال پیام در این گفت‌وگو را ندارید'; end if;
 if v_uid=p_buyer_id and not exists(select 1 from public.iron_store_products_v2
   where id=p_product_id and is_active and approval_status='approved') then
   raise exception 'این محصول برای گفت‌وگو در دسترس نیست';
 end if;
 if v_uid=v_seller and not exists(select 1 from public.iron_store_messages_v2
   where product_id=p_product_id and buyer_id=p_buyer_id and seller_id=v_seller) then
   raise exception 'خریدار هنوز گفت‌وگویی با شما آغاز نکرده است';
 end if;
 insert into public.iron_store_messages_v2(product_id,seller_id,buyer_id,sender_id,body)
 values(p_product_id,v_seller,p_buyer_id,v_uid,trim(p_body)) returning id into v_id;
 if v_uid=p_buyer_id then
  insert into public.iron_store_notifications_v2(seller_id,event_type,message)
  values(v_seller,'message','پیام جدیدی درباره یکی از محصولات فروشگاه دریافت کردید.');
 end if;
 return v_id;
end;
$function$;
revoke all on function public.iron_store_send_message_v2(uuid,uuid,text) from public,anon;
grant execute on function public.iron_store_send_message_v2(uuid,uuid,text) to authenticated;
