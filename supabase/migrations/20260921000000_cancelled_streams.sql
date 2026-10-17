-- Leaks, round two: subscriptions the user marked cancelled (stream id → the date), and streams re-filed by hand
-- (stream id → "subscription" | "bill"). Detection stays on the device; the server reads cancelled_streams to push
-- "charged you after you cancelled".
alter table settings add column cancelled_streams jsonb not null default '{}';
alter table settings add column stream_kinds jsonb not null default '{}';
