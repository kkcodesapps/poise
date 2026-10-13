-- One-time logo backfill per Plaid item (the sync only carries new/changed rows).
alter table items add column logos_backfilled_at timestamptz;
