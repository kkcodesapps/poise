import { json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { upsertAccounts, type ItemRow } from "../_shared/sync.ts";

// On-demand freshness: fresh balances now, and a provider-side transaction refresh (the webhook brings the rows).
// Rate-limited per item so foreground / pull-to-refresh can't run up the bill.
const MIN_INTERVAL_MS = 15 * 60 * 1000;

interface Liabilities { liabilities?: { credit?: { account_id: string; next_payment_due_date: string | null; minimum_payment_amount: number | null; last_statement_balance: number | null }[] } }

interface GetResponse { transactions: { transaction_id: string; logo_url?: string | null; counterparties?: { logo_url?: string | null }[] | null }[]; total_transactions: number }

/** Rows that arrived before logos were stored get theirs once, from /transactions/get. Only logo_url is touched. */
async function backfillLogos(db: ReturnType<typeof admin>, item: ItemRow, token: string) {
  try {
    const end = new Date(), start = new Date(end.getTime() - 90 * 86_400_000);
    const day = (d: Date) => d.toISOString().slice(0, 10);
    let offset = 0, total = 1;
    while (offset < total && offset < 1500) {
      const res = await plaid<GetResponse>("/transactions/get", { access_token: token, start_date: day(start), end_date: day(end), options: { count: 500, offset } });
      total = res.total_transactions;
      for (const t of res.transactions) {
        const logo = t.logo_url ?? t.counterparties?.find((c) => c.logo_url)?.logo_url ?? null;
        if (logo) await db.from("transactions").update({ logo_url: logo }).eq("user_id", item.user_id).eq("provider_txn_id", t.transaction_id).is("logo_url", null);
      }
      offset += res.transactions.length || 500;
    }
    await db.from("items").update({ logos_backfilled_at: new Date().toISOString() }).eq("id", item.id);
  } catch { /* try again next refresh */ }
}

/** Card statements from Plaid, where the Item has the liabilities product. Items linked without it just skip. */
async function updateStatements(db: ReturnType<typeof admin>, item: ItemRow, token: string) {
  try {
    const res = await plaid<Liabilities>("/liabilities/get", { access_token: token });
    for (const c of res.liabilities?.credit ?? []) {
      await db.from("accounts").update({ statement_due: c.next_payment_due_date, statement_amount: c.last_statement_balance, minimum_due: c.minimum_payment_amount })
        .eq("item_id", item.id).eq("provider_account_id", c.account_id);
    }
  } catch { /* PRODUCTS_NOT_SUPPORTED / not consented: the card page just won't show a statement */ }
}

Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const { trigger = "foreground", force = false } = await req.json().catch(() => ({})) as { trigger?: string; force?: boolean };
  const db = admin();
  const { data: items } = await db.from("items")
    .select("id, user_id, provider_item_id, access_token_enc, sync_cursor, last_refreshed_at, status, logos_backfilled_at")
    .eq("user_id", user.id).eq("provider", "plaid").neq("status", "error");

  const results: Record<string, string> = {};
  for (const item of items ?? []) {
    const age = item.last_refreshed_at ? Date.now() - new Date(item.last_refreshed_at).getTime() : Infinity;
    if (!force && age < MIN_INTERVAL_MS) { results[item.id] = "recent"; continue; }
    try {
      const token = await decrypt(item.access_token_enc);
      const bal = await plaid<{ accounts: PlaidAccount[] }>("/accounts/balance/get", { access_token: token });
      await upsertAccounts(db, item as ItemRow, bal.accounts);
      await updateStatements(db, item as ItemRow, token);
      if (!item.logos_backfilled_at) await backfillLogos(db, item as ItemRow, token);
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
