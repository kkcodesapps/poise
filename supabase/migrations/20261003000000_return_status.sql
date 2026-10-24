-- Where a return has got to, in Amazon's own words. A refund that is on its way shouldn't look the same as one that
-- has been forgotten, and the user shouldn't have to tell Poise which it is.
alter table order_items add column return_status text;
alter table order_items add column return_note text;
