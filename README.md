# Poise

How you're doing, in one sentence.

Poise is a native iOS spending tracker. It links your bank accounts, shows every charge on the day you actually paid, and leads with a verdict — how far ahead you are, how much you've kept this month, and the one thing worth doing about it — instead of a dashboard.

## Status

Early. Design is done; the app is being built.

## Stack

- iOS 18, Swift 6, SwiftUI
- `PoiseKit` — the engine (classification, transfer/refund pairing, recurring detection, the verdict math), headless and tested
- Supabase (Postgres, Edge Functions) for bank sync and push
