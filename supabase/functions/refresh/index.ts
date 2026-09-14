import { json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { upsertAccounts, type ItemRow } from "../_shared/sync.ts";

// On-demand freshness: fresh balances now, and a provider-side transaction refresh (the webhook brings the rows).
// Rate-limited per item so foreground / pull-to-refresh can't run up the bill.
const MIN_INTERVAL_MS = 15 * 60 * 1000;

Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const { trigger = "foreground", force = false } = await req.json().catch(() => ({})) as { trigger?: string; force?: boolean };
  const db = admin();
  const { data: items } = await db.from("items")
    .select("id, user_id, provider_item_id, access_token_enc, sync_cursor, last_refreshed_at, status")
    .eq("user_id", user.id).eq("provider", "plaid").neq("status", "error");

  const results: Record<string, string> = {};
  for (const item of items ?? []) {
    const age = item.last_refreshed_at ? Date.now() - new Date(item.last_refreshed_at).getTime() : Infinity;
    if (!force && age < MIN_INTERVAL_MS) { results[item.id] = "recent"; continue; }
    try {
      const token = await decrypt(item.access_token_enc);
      const bal = await plaid<{ accounts: PlaidAccount[] }>("/accounts/balance/get", { access_token: token });
      await upsertAccounts(db, item as ItemRow, bal.accounts);
      await plaid("/transactions/refresh", { access_token: token });
      await db.from("items").update({ last_refreshed_at: new Date().toISOString() }).eq("id", item.id);
      await db.from("refresh_log").insert({ item_id: item.id, trigger, cost_units: 1 });
      results[item.id] = "refreshed";
    } catch (e) {
      results[item.id] = e instanceof PlaidError ? e.code : "error";
      if (e instanceof PlaidError && e.code === "ITEM_LOGIN_REQUIRED") await db.from("items").update({ status: "relink" }).eq("id", item.id);
    }
  }
  return json({ results });
});
