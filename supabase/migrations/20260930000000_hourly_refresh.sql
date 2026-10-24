-- Freshness without anyone asking. Every hour the schedule calls refresh-all, which asks each bank for anything new;
-- Plaid's webhook brings the rows and sends the push, so a charge reaches the phone with the app closed. A quiet hour
-- sends nothing — pushes only ever come from new rows.
--
-- Runs every hour of the day; the function itself skips the small hours in the user's own timezone, which keeps the
-- window right across daylight saving. The key it sends lives in the vault, never here.
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'poise-hourly-refresh',
  '0 * * * *',
  $$
  select net.http_post(
    url := 'https://ckncxuxpianojeskebnt.supabase.co/functions/v1/refresh-all',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-key', (select decrypted_secret from vault.decrypted_secrets where name = 'poise_cron_key')
    ),
    body := '{}'::jsonb
  );
  $$
);
