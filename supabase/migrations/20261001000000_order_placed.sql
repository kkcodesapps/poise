-- The day an order was placed, which is the day the thing was actually bought. A card authorises when the seller
-- ships and posts later still, and Apple Card reports no authorisation date at all — so for those the charge was
-- landing in the feed days after the purchase.
alter table order_items add column placed_at date;
