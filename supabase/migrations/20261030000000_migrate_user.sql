-- An anonymous user's data moves onto the account they just signed in with, in one transaction. Every public table with
-- a user_id column is moved, so a table added later can't be left behind and then cascade-deleted along with the
-- anonymous user — order_items was, until now. Called by the migrate-user function, which deletes the old user after.
create or replace function migrate_user(old_id uuid, new_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t text;
  n bigint;
  moved jsonb := '{}';
  -- An account with nothing in it yet takes the anonymous user's choices; one already in use keeps its own.
  fresh boolean := not exists (select 1 from transactions where user_id = new_id);
begin
  if old_id = new_id then return moved; end if;

  -- Rows that can exist once per user. Where both sides have one, only one survives the move.
  if fresh then
    delete from settings where user_id = new_id and exists (select 1 from settings where user_id = old_id);
  else
    delete from settings where user_id = old_id and exists (select 1 from settings where user_id = new_id);
  end if;
  delete from devices d where d.user_id = old_id and exists (select 1 from devices x where x.user_id = new_id and x.apns_token = d.apns_token);
  delete from merchant_rules r where r.user_id = old_id and exists (select 1 from merchant_rules x where x.user_id = new_id and x.matcher = r.matcher);
  delete from order_items o where o.user_id = old_id and exists (select 1 from order_items x where x.user_id = new_id and x.order_ref = o.order_ref);
  delete from apple_tokens where user_id = old_id and exists (select 1 from apple_tokens where user_id = new_id);

  -- Wallet is one connection per person, keyed by their user id. It follows the user; if the account already has its
  -- own, the anonymous one goes, since the same Wallet twice would double every Apple Card row.
  if exists (select 1 from items where user_id = new_id and provider = 'financekit') then
    delete from items where user_id = old_id and provider = 'financekit';
  else
    update items set provider_item_id = new_id::text where user_id = old_id and provider = 'financekit' and provider_item_id = old_id::text;
  end if;

  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables x on x.table_schema = c.table_schema and x.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'user_id' and x.table_type = 'BASE TABLE'
    order by c.table_name
  loop
    execute format('update public.%I set user_id = $2 where user_id = $1', t) using old_id, new_id;
    get diagnostics n = row_count;
    if n > 0 then moved := moved || jsonb_build_object(t, n); end if;
  end loop;
  return moved;
end $$;
revoke all on function migrate_user(uuid, uuid) from public, anon, authenticated;
