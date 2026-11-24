create table if not exists public.iron_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'android' check (platform in ('android','ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint iron_push_tokens_user_token_key unique (user_id, token)
);

create index if not exists iron_push_tokens_user_id_idx
  on public.iron_push_tokens(user_id);

alter table public.iron_push_tokens enable row level security;

drop policy if exists iron_push_tokens_select_own on public.iron_push_tokens;
create policy iron_push_tokens_select_own
  on public.iron_push_tokens for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists iron_push_tokens_insert_own on public.iron_push_tokens;
create policy iron_push_tokens_insert_own
  on public.iron_push_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists iron_push_tokens_update_own on public.iron_push_tokens;
create policy iron_push_tokens_update_own
  on public.iron_push_tokens for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists iron_push_tokens_delete_own on public.iron_push_tokens;
create policy iron_push_tokens_delete_own
  on public.iron_push_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.iron_push_tokens to authenticated;
