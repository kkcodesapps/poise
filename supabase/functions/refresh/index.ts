import { json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { upsertAccounts, type ItemRow } from "../_shared/sync.ts";
import { updateStatements } from "../_shared/liabilities.ts";
import { recordConsent } from "../_shared/itemdiag.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

// On-demand freshness: asks each bank for anything new (the webhook brings the rows) and for fresh balances.
// Rate-limited per item so foreground / pull-to-refresh can't run up the bill. It answers as soon as the banks are
// marked asked; the asking itself runs after the reply, because Plaid holds /transactions/refresh open while it talks to
// the bank — about 20 seconds for Barclays — and a pull used to wait out every bank in turn, a minute in all.
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

/** One bank: the refresh that brings new rows, then fresh balances, due dates, what it shares, and old logos once. */
async function ask(db: ReturnType<typeof admin>, item: ItemRow & { logos_backfilled_at: string | null }, trigger: string) {
  try {
    const token = await decrypt(item.access_token_enc);
    await plaid("/transactions/refresh", { access_token: token });
    await db.from("refresh_log").insert({ item_id: item.id, trigger, cost_units: 1 });
    const bal = await plaid<{ accounts: PlaidAccount[] }>("/accounts/balance/get", { access_token: token });
    await upsertAccounts(db, item, bal.accounts);
    await updateStatements(db, item, token);
    await recordConsent(db, item, token);
    if (!item.logos_backfilled_at) await backfillLogos(db, item, token);
  } catch (e) {
    if (e instanceof PlaidError && e.code === "ITEM_LOGIN_REQUIRED") await db.from("items").update({ status: "relink" }).eq("id", item.id);
  }
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
  const work: Promise<unknown>[] = [];
  for (const item of items ?? []) {
    const age = item.last_refreshed_at ? Date.now() - new Date(item.last_refreshed_at).getTime() : Infinity;
    if (!force && age < MIN_INTERVAL_MS) { results[item.id] = "recent"; continue; }
    // Marked before the reply, so a second pull straight after is "recent" rather than a second bill.
    await db.from("items").update({ last_refreshed_at: new Date().toISOString() }).eq("id", item.id);
    results[item.id] = "refreshed";
    work.push(ask(db, item as ItemRow & { logos_backfilled_at: string | null }, trigger));
  }
  EdgeRuntime.waitUntil(Promise.allSettled(work));
  return json({ results });
});
