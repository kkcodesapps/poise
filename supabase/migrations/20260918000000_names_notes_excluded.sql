-- "What was this?": a display name per merchant (rule) or per charge, a free-text note, and "leave it out of the math".
-- All three are the user's; nothing on the sync path writes them.
alter table merchant_rules add column display_name text;
alter table transactions add column display_name text;
alter table transactions add column excluded boolean not null default false;
