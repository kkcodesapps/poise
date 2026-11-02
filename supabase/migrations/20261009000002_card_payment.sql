-- How each card gets paid. One toggle decided it for every card, which is wrong the moment two cards are paid
-- differently — and the statement balance and the whole balance are different sums on any card used since it closed.
-- Null means "whatever Settings says new cards do", so changing the default still moves cards nobody has decided about.
alter table accounts add column pays text check (pays in ('statement', 'full', 'minimum', 'fixed'));
alter table accounts add column pays_fixed_amount numeric(14,2);

-- The old global toggle becomes the default for newly linked cards. True meant "pay in full", which in practice meant
-- the statement balance — that was the only figure a provider gave us.
alter table settings add column new_cards_pay text not null default 'statement'
  check (new_cards_pay in ('statement', 'full', 'minimum', 'fixed'));
update settings set new_cards_pay = case when pays_cc_in_full then 'statement' else 'minimum' end;
