-- "Charged twice?" is a question the user can turn off per merchant (two "both are real" answers, or the merchant page).
-- Detection stays on the device and in notify.ts; this only says where not to ask.
alter table settings add column dup_muted jsonb not null default '[]';
