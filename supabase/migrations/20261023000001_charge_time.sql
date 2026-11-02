-- When a charge actually happened. Banks date charges by their own clock (Robinhood by UTC, so an evening purchase in
-- Chicago lands on tomorrow), so the day is worked out on the phone, in its time zone, from:
--   authorized_at: the provider's authorisation time, when it gives a real one (not a placeholder midnight);
--   seen_at:       when Poise first saw the charge. It can't have happened later than that, and a posted charge
--                  keeps the time its pending twin was first seen.
alter table transactions add column authorized_at timestamptz;
alter table transactions add column seen_at timestamptz not null default now();

update transactions set seen_at = created_at;
update transactions t set seen_at = p.created_at
  from transactions p
  where t.pending_txn_id is not null and p.account_id = t.account_id and p.provider_txn_id = t.pending_txn_id and p.created_at < t.seen_at;
