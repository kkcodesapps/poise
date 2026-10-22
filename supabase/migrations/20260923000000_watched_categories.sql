-- "Tell me when this costs more than usual" for a category (built-in id or a custom category's uuid).
alter table settings add column watched_categories jsonb not null default '[]';
