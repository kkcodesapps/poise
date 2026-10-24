-- The earlier revoke named anon and authenticated, but the grant was held by PUBLIC — which both inherit from — so
-- nothing actually changed. Taking it from PUBLIC is what closes it. The trigger still fires: triggers run as the
-- table owner and don't consult EXECUTE grants.
revoke execute on function public.handle_new_user() from public;

-- Same for pg_net: the HTTP functions had no explicit grants, which means PUBLIC. The hourly refresh calls them as
-- postgres, which is the owner and unaffected.
revoke execute on all functions in schema net from public;
