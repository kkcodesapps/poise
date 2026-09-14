-- Poise — server schema (Postgres / Supabase). One row per user; RLS keeps users apart.
-- Money is numeric(14,2), signed the same way as the app: negative = out, positive = in.

create extension if not exists pgcrypto;

create type account_role as enum ('spending', 'savings', 'credit', 'other');
create type item_status as enum ('ok', 'relink', 'error');
create type txn_kind as enum ('spend', 'income', 'transfer', 'cc_payment', 'refund', 'untracked');
create type spend_category as enum ('home', 'groceries', 'dining', 'transport', 'shopping', 'subscriptions', 'health', 'fun', 'other');
create type classified_by as enum ('auto', 'rule', 'user');
create type stream_kind as enum ('subscription', 'bill', 'income');
create type cadence as enum ('weekly', 'biweekly', 'monthly', 'quarterly', 'annual');
create type stream_status as enum ('active', 'ended', 'changed');

create table users (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  apns_token text not null,
  env text not null default 'production',
  updated_at timestamptz not null default now(),
  unique (user_id, apns_token)
);

create table items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  provider text not null,                      -- 'plaid' | 'teller' | 'financekit'
  provider_item_id text not null,
  access_token_enc bytea,                      -- encrypted at rest; never leaves the server
  institution_id text,
  institution_name text,
  status item_status not null default 'ok',
  sync_cursor text,                             -- provider sync position (next_cursor)
  last_synced_at timestamptz,
  last_refreshed_at timestamptz,
  refresh_count_month int not null default 0,
  created_at timestamptz not null default now(),
  unique (provider, provider_item_id)
);

create table accounts (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items (id) on delete cascade,
  user_id uuid not null references users (id) on delete cascade,
  provider_account_id text not null,
  name text not null,
  mask text,
  type text,
  subtype text,
  role account_role not null default 'other',
  available numeric(14,2),
  current numeric(14,2) not null default 0,
  credit_limit numeric(14,2),
  currency text not null default 'USD',
  balance_at timestamptz,
  unique (item_id, provider_account_id)
);

create table transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts (id) on delete cascade,
  user_id uuid not null references users (id) on delete cascade,
  provider_txn_id text not null,
  pending boolean not null default false,
  pending_txn_id text,                          -- provider id of the pending row this posted row replaces
  amount numeric(14,2) not null,
  currency text not null default 'USD',
  merchant text not null,
  raw_name text,
  authorized_date date,
  posted_date date not null,
  display_date date generated always as (coalesce(authorized_date, posted_date)) stored,
  kind txn_kind not null default 'spend',
  category spend_category,
  provider_category text,
  classified_by classified_by not null default 'auto',
  pair_id uuid,                                 -- other side of a transfer / card payment, or the charge a refund nets against
  stream_id uuid,
  note text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (account_id, provider_txn_id)
);
create index transactions_user_display_date on transactions (user_id, display_date desc) where deleted_at is null;

create table merchant_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  matcher text not null,                        -- normalized merchant name
  category spend_category,
  kind txn_kind,
  created_at timestamptz not null default now(),
  unique (user_id, matcher)
);

create table streams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  merchant text not null,
  kind stream_kind not null,
  cadence cadence not null,
  amount_avg numeric(14,2) not null,
  amount_last numeric(14,2) not null,
  amount_prev numeric(14,2),
  first_seen date not null,
  last_seen date not null,
  next_expected date not null,
  status stream_status not null default 'active',
  dismissed_until date
);

create table insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  type text not null,                           -- crunch | duplicate | price_up | fee | pace | positive | new_stream | renewal
  rank int not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz
);

create table settings (
  user_id uuid primary key references users (id) on delete cascade,
  payday_override date,
  pays_cc_in_full boolean not null default true,
  kept_target numeric(5,4),                     -- null = beat last month
  committed_savings numeric(14,2) not null default 0,
  notif_prefs jsonb not null default '{"spend": true, "heads_up": true, "weekly_review": true}',
  faceid boolean not null default false
);

create table refresh_log (
  id bigserial primary key,
  item_id uuid not null references items (id) on delete cascade,
  trigger text not null,                        -- webhook | foreground | pull | scheduled
  cost_units int not null default 1,
  at timestamptz not null default now()
);

-- Row-level security: every table is scoped to auth.uid().
alter table users enable row level security;
alter table devices enable row level security;
alter table items enable row level security;
alter table accounts enable row level security;
alter table transactions enable row level security;
alter table merchant_rules enable row level security;
alter table streams enable row level security;
alter table insights enable row level security;
alter table settings enable row level security;

create policy "own row" on users for all using (id = auth.uid());
create policy "own rows" on devices for all using (user_id = auth.uid());
create policy "own rows" on items for select using (user_id = auth.uid());          -- writes only via Edge Functions (service role)
create policy "own rows" on accounts for all using (user_id = auth.uid());
create policy "own rows" on transactions for all using (user_id = auth.uid());
create policy "own rows" on merchant_rules for all using (user_id = auth.uid());
create policy "own rows" on streams for all using (user_id = auth.uid());
create policy "own rows" on insights for all using (user_id = auth.uid());
create policy "own row" on settings for all using (user_id = auth.uid());
