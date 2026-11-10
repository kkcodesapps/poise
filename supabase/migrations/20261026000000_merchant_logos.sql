-- Logos for merchants Plaid gives none for: Apple Card and Wallet rows, and plenty of big brands on bank cards too.
-- Looked up once per merchant by the hourly job (Logo.dev search, then its image), copied into our own storage, and
-- shared by everyone — a merchant is never asked about twice, and phones never talk to Logo.dev at all.

-- The phone's merchant key (Transaction.merchantKey): lowercase, anything but letters becomes a space, spaces collapsed.
create or replace function merchant_key(m text) returns text language sql immutable as $$
  select trim(regexp_replace(regexp_replace(lower(m), '[^[:alpha:] ]', ' ', 'g'), ' +', ' ', 'g'))
$$;

create table merchant_logos (
  merchant_key text primary key,
  domain text,
  logo_url text,                -- our copy in storage; null when nothing was found
  source text not null,         -- 'logo.dev' | 'manual'
  checked_at timestamptz not null default now()
);
-- No policies: rows say which merchants exist across every user, so a phone only ever reads its own through my_merchant_logos.
alter table merchant_logos enable row level security;

-- The logos for the caller's own merchants.
create or replace function my_merchant_logos() returns table (merchant_key text, logo_url text)
language sql stable security definer set search_path = public as $$
  select l.merchant_key, l.logo_url from merchant_logos l
  where l.logo_url is not null
    and l.merchant_key in (select distinct merchant_key(t.merchant) from transactions t where t.user_id = auth.uid() and t.deleted_at is null)
$$;
revoke all on function my_merchant_logos() from public, anon;
grant execute on function my_merchant_logos() to authenticated;

-- Merchants still without a face, most charged first: no Plaid logo on any of their rows, and never looked up (or a
-- miss more than 30 days old, since brands get added).
create or replace function logo_candidates(n int) returns table (merchant_key text, merchant text, charges bigint)
language sql stable set search_path = public as $$
  with keyed as (
    select merchant_key(merchant) k, merchant, logo_url from transactions
    where deleted_at is null and kind in ('spend', 'refund')
  ), plaid as (select distinct k from keyed where logo_url is not null)
  select k, mode() within group (order by merchant), count(*) from keyed
  where k <> '' and k not in (select k from plaid)
    and not exists (select 1 from merchant_logos l where l.merchant_key = keyed.k and (l.logo_url is not null or l.checked_at > now() - interval '30 days'))
  group by k order by count(*) desc limit n
$$;
revoke all on function logo_candidates(int) from public, anon, authenticated;

insert into storage.buckets (id, name, public) values ('logos', 'logos', true) on conflict (id) do nothing;
