-- Custom categories + watches (refund watches, merchant alerts). Built-in categories stay implicit in the app;
-- the user's lens overrides for built-ins live in settings.category_lens.

create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  name text not null,
  symbol text not null default 'tag',
  lens text not null default 'wants' check (lens in ('needs', 'wants', 'kept')),
  sort int not null default 0,
  created_at timestamptz not null default now()
);
alter table categories enable row level security;
create policy "own rows" on categories for all using (user_id = auth.uid());

alter table settings add column category_lens jsonb not null default '{}';

-- A category is now a built-in name ("dining") or a custom category id — plain text.
alter table transactions alter column category type text using category::text;
alter table merchant_rules alter column category type text using category::text;
drop type spend_category;

create table watches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  kind text not null check (kind in ('refund', 'merchant')),
  transaction_id uuid references transactions (id) on delete set null,
  merchant text not null,
  matcher text not null,
  expected_amount numeric(14,2),
  nudge_days int not null default 14,
  note text,
  status text not null default 'waiting' check (status in ('waiting', 'overdue', 'arrived', 'watching', 'triggered', 'closed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_transaction_id uuid references transactions (id) on delete set null
);
create index watches_user_open on watches (user_id) where status in ('waiting', 'overdue', 'watching');
alter table watches enable row level security;
create policy "own rows" on watches for all using (user_id = auth.uid());
