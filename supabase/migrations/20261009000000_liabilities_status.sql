-- Why a bank isn't giving us card statements. The call was failing silently, so a card with no due date looked the
-- same whether the bank can't do it, the product wasn't consented to, or something broke — and Next 14 quietly left
-- thousands of dollars of card payments out of the picture.
alter table items add column liabilities_status text;
alter table items add column liabilities_at timestamptz;
