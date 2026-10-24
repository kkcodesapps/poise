import { env, json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin } from "../_shared/db.ts";
import { upsertAccounts, type ItemRow } from "../_shared/sync.ts";
import { updateStatements } from "../_shared/liabilities.ts";

// Freshness without anyone asking for it. A schedule calls this every hour of the waking day; it asks each bank for
// anything new, and Plaid's webhook brings the rows and sends the push — so a charge reaches the phone with the app
// closed, the way Apple Card already does. A quiet hour sends nothing: the push only ever comes from new rows.
//
// Called by pg_cron, not by the app, so it authenticates on a shared key rather than a user's session.

/** Long enough that the hourly schedule always passes and a retry never doubles up. */
const MIN_INTERVAL_MS = 50 * 60 * 1000;
/** The user's day. There's no point asking a bank about 3am until morning, and it halves the calls. */
const WAKING = { from: 7, to: 23, zone: "America/Chicago" };

function hourIn(zone: string): number {
  const hour = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", hour12: false }).format(new Date());
  return Number(hour) % 24;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-key") !== env("CRON_KEY")) return json({ error: "unauthorized" }, 401);

  const hour = hourIn(WAKING.zone);
  const force = new URL(req.url).searchParams.get("force") === "1";
  if (!force && (hour < WAKING.from || hour > WAKING.to)) return json({ skipped: "asleep", hour });

  const db = admin();
  const { data: items } = await db.from("items")
    .select("id, user_id, provider_item_id, access_token_enc, sync_cursor, last_refreshed_at, status")
    .eq("provider", "plaid").neq("status", "error");

  const results: Record<string, string> = {};
  for (const item of items ?? []) {
    const age = item.last_refreshed_at ? Date.now() - new Date(item.last_refreshed_at).getTime() : Infinity;
    if (!force && age < MIN_INTERVAL_MS) { results[item.id] = "recent"; continue; }
    try {
      const token = await decrypt(item.access_token_enc);
      // Balances are cheap and keep the card pages honest; the refresh is what makes Plaid go and ask the bank.
      const bal = await plaid<{ accounts: PlaidAccount[] }>("/accounts/balance/get", { access_token: token });
      await upsertAccounts(db, item as ItemRow, bal.accounts);
      // Due dates move every month, and Next 14 is built on them.
      await updateStatements(db, item as ItemRow, token);
      await plaid("/transactions/refresh", { access_token: token });
      await db.from("items").update({ last_refreshed_at: new Date().toISOString() }).eq("id", item.id);
      await db.from("refresh_log").insert({ item_id: item.id, trigger: "scheduled", cost_units: 1 });
      results[item.id] = "refreshed";
    } catch (e) {
      // A bank that needs re-linking, or Plaid's own rate limit: note it and carry on to the next one.
      results[item.id] = e instanceof PlaidError ? e.code : "error";
      if (e instanceof PlaidError && e.code === "ITEM_LOGIN_REQUIRED") await db.from("items").update({ status: "relink" }).eq("id", item.id);
    }
  }
  return json({ hour, results });
});
