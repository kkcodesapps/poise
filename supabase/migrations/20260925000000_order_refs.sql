-- The merchant's own order number for a charge, read on the device from an account the user connected
-- (Amazon today). Never written by a sync: providers don't carry it, which is the whole reason it exists here.
alter table transactions add column order_ref text;
