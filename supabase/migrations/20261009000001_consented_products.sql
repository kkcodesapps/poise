-- What a bank connection is actually allowed to read. Going through "Allow" doesn't guarantee the bank granted the
-- product, and without this the only symptom is a card that silently never gets a due date.
alter table items add column consented_products text[];
