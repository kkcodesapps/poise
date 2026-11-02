-- Subscriptions stops being a category. A category says what a charge was for; whether it repeats — a subscription
-- or a bill — is worked out on the phone from the stream, so a gym can be Health and a subscription at once.
-- Two new built-ins take its place: Entertainment (streaming, music, games) and Tech (apps, cloud, devices).

-- Rows filed under it go where they belong. Merchants with an obvious home first; everything else that was there
-- (Netflix, Spotify, Disney+, Peacock, Nintendo, a cinema) is entertainment.
update transactions set category = case
    when merchant ~* '^(apple|icloud|cursor|google (one|storage)|microsoft|adobe|dropbox|github|openai|chatgpt)\M' then 'tech'
    when merchant ~* '^amazon' or raw_name ~* '^amazon prime' then 'shopping'
    when merchant ~* '^uber' then 'transport'
    when merchant ~* '^headspace' then 'health'
    else 'entertainment'
  end
  where category = 'subscriptions';

-- Charges the bank auto-filed that the new mapping now puts elsewhere: Apple anywhere, and electronics.
update transactions set category = 'tech'
  where classified_by = 'auto' and kind in ('spend', 'refund')
    and (merchant ~* '^(apple|icloud)\M' or provider_category = 'GENERAL_MERCHANDISE_ELECTRONICS');

-- Rules that filed a merchant under it.
update merchant_rules set category = case
    when matcher ~ '^amazon' then 'shopping'
    when matcher ~ '^(apple|icloud|cursor)' then 'tech'
    when matcher ~ '^uber' then 'transport'
    else 'entertainment'
  end
  where category = 'subscriptions';

-- Settings keyed by category id.
update settings set category_lens = category_lens - 'subscriptions' where category_lens ? 'subscriptions';
update settings set watched_categories = (
    select coalesce(jsonb_agg(distinct case when v = 'subscriptions' then 'entertainment' else v end), '[]')
    from jsonb_array_elements_text(watched_categories) v)
  where watched_categories ? 'subscriptions';
