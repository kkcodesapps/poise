-- What was in an order, read from the merchant's own page on the user's device. One row per order, not per charge:
-- Amazon charges per shipment, so two charges can share an order and its contents.
create table order_items (
  user_id uuid not null references users (id) on delete cascade,
  order_ref text not null,
  items jsonb not null default '[]',
  subtotal numeric(14,2),
  tax numeric(14,2),
  total numeric(14,2),
  fetched_at timestamptz not null default now(),
  primary key (user_id, order_ref)
);
alter table order_items enable row level security;
create policy "own rows" on order_items for all using (user_id = auth.uid());
