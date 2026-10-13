-- Sign in with Apple hands the app a one-time authorization code; the server swaps it for a refresh token and keeps it
-- (encrypted like provider tokens) so "Delete everything" can revoke the Apple sign-in, which App Review requires.
create table if not exists public.apple_tokens (
  user_id uuid primary key references auth.users(id) on delete cascade,
  refresh_token_enc bytea not null,
  created_at timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;
-- No policies on purpose: only the service role (Edge Functions) reads or writes this table.
