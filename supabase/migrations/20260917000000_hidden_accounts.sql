-- Accounts the user has taken out of the math. Sync never touches these columns, so a provider re-sending the
-- account on every refresh cannot bring it back; only the user can, from the account's page.
alter table accounts add column hidden boolean not null default false;
alter table accounts add column hidden_at timestamptz;
