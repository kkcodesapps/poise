-- Card statements: what's due, when, and the minimum — from Wallet (Apple Card) or Plaid liabilities (bank cards).
alter table accounts add column statement_due date;
alter table accounts add column statement_amount numeric(14,2);
alter table accounts add column minimum_due numeric(14,2);
