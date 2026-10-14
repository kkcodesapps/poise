-- "Tell me when the price moves": a watch on a price item (matcher = "merchant|<key>" or "named|<name key>").
alter table watches drop constraint if exists watches_kind_check;
alter table watches add constraint watches_kind_check check (kind in ('refund', 'merchant', 'price'));
