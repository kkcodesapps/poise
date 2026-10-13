-- Merchant logos from Plaid (logo_url, else the first counterparty's). Wallet rows never have one.
alter table transactions add column logo_url text;
