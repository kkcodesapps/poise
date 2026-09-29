-- "Not a subscription": recurring streams the user has dismissed, by stream id ("spend|<merchant key>").
-- Detection stays on the device; this only hides what it finds.
alter table settings add column dismissed_streams jsonb not null default '[]';
