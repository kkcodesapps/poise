-- Security advisor clean-up.
--
-- 1. refresh_log was the real hole: a table in the exposed schema with no row-level security at all, so one signed-in
--    user could read every user's refresh history. Nothing on the client reads it — it exists so the cost of provider
--    refreshes can be counted — so it's locked shut entirely. Edge Functions use the service role and bypass RLS.
alter table refresh_log enable row level security;

-- 2. Every policy was written without naming a role, which in Postgres means `public` — the policy is evaluated for
--    the anon role too. A request carrying only the publishable key has no auth.uid(), so it matched nothing and no
--    data was ever exposed; but saying `authenticated` is what was meant, and it's what the app always is (even an
--    anonymous sign-in is an authenticated role).
alter policy "own rows" on accounts to authenticated;
alter policy "own rows" on categories to authenticated;
alter policy "own rows" on devices to authenticated;
alter policy "own rows" on insights to authenticated;
alter policy "own rows" on items to authenticated;
alter policy "own rows" on merchant_rules to authenticated;
alter policy "own rows" on order_items to authenticated;
alter policy "own row" on settings to authenticated;
alter policy "own rows" on streams to authenticated;
alter policy "own rows" on transactions to authenticated;
alter policy "own row" on users to authenticated;
alter policy "own rows" on watches to authenticated;

-- 3. handle_new_user() is a trigger function running as its definer. A trigger doesn't need EXECUTE granted to the
--    client roles, and leaving it there let a signed-in user call it directly.
revoke execute on function public.handle_new_user() from anon, authenticated;

-- 4. pg_net can make the database issue HTTP requests. Its functions had no explicit grants, which means execute by
--    default to everyone, and both client roles have usage on its schema. The hourly refresh calls it as the postgres
--    role, so taking it away from the client roles costs nothing and closes the surface.
revoke execute on all functions in schema net from anon, authenticated;
