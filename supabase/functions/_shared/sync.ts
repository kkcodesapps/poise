import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { plaid, type PlaidAccount, type SyncResponse } from "./plaid.ts";
import { decrypt } from "./crypto.ts";
import { classify, merchantKey, roleFor } from "./classify.ts";

export interface ItemRow {
  id: string;
  user_id: string;
  provider_item_id: string;
  access_token_enc: string;
  sync_cursor: string | null;
}

/** Upserts the provider's accounts for an item and returns provider_account_id → accounts.id. */
export async function upsertAccounts(db: SupabaseClient, item: ItemRow, accounts: PlaidAccount[]): Promise<Map<string, string>> {
  if (accounts.length) {
    const rows = accounts.map((a) => ({
      item_id: item.id,
      user_id: item.user_id,
      provider_account_id: a.account_id,
      name: a.official_name ?? a.name,
      mask: a.mask ?? null,
      type: a.type,
      subtype: a.subtype ?? null,
      available: a.balances.available ?? null,
      current: a.balances.current ?? 0,
      credit_limit: a.balances.limit ?? null,
      currency: a.balances.iso_currency_code ?? "USD",
      balance_at: new Date().toISOString(),
    }));
    // Role is only set on insert so the user's choice survives later syncs.
    const { data: existing } = await db.from("accounts").select("provider_account_id").eq("item_id", item.id);
    const known = new Set((existing ?? []).map((r: { provider_account_id: string }) => r.provider_account_id));
    const withRole = rows.map((r, i) => (known.has(r.provider_account_id) ? r : { ...r, role: roleFor(accounts[i]) }));
    const { error } = await db.from("accounts").upsert(withRole, { onConflict: "item_id,provider_account_id" });
    if (error) throw error;
  }
  const { data } = await db.from("accounts").select("id, provider_account_id").eq("item_id", item.id);
  return new Map((data ?? []).map((r: { id: string; provider_account_id: string }) => [r.provider_account_id, r.id]));
}

/** Walks /transactions/sync from the stored position, applying merchant rules, until the provider has no more. */
export async function syncItem(db: SupabaseClient, item: ItemRow): Promise<{ added: number; modified: number; removed: number }> {
  const token = await decrypt(item.access_token_enc);
  const { data: ruleRows } = await db.from("merchant_rules").select("matcher, category, kind").eq("user_id", item.user_id);
  const rules = new Map((ruleRows ?? []).map((r: { matcher: string; category: string | null; kind: string | null }) => [r.matcher, r]));

  let cursor = item.sync_cursor ?? undefined;
  let hasMore = true;
  const totals = { added: 0, modified: 0, removed: 0 };

  while (hasMore) {
    const res = await plaid<SyncResponse>("/transactions/sync", {
      access_token: token,
      cursor,
      count: 500,
      options: { include_personal_finance_category: true },
    });
    const accountIDs = await upsertAccounts(db, item, res.accounts ?? []);

    const rows = [...res.added, ...res.modified].flatMap((t) => {
      const accountID = accountIDs.get(t.account_id);
      if (!accountID) return [];
      const merchant = t.merchant_name ?? t.name;
      const auto = classify(t);
      const rule = rules.get(merchantKey(merchant));
      return [{
        account_id: accountID,
        user_id: item.user_id,
        provider_txn_id: t.transaction_id,
        pending: t.pending,
        pending_txn_id: t.pending_transaction_id ?? null,
        amount: -t.amount,
        currency: t.iso_currency_code ?? "USD",
        merchant,
        raw_name: t.name,
        authorized_date: t.authorized_date ?? null,
        posted_date: t.date,
        kind: rule?.kind ?? auto.kind,
        category: rule?.category ?? auto.category,
        provider_category: t.personal_finance_category?.detailed ?? null,
        classified_by: rule ? "rule" : "auto",
      }];
    });
    if (rows.length) {
      const { data: written, error } = await db.from("transactions").upsert(rows, { onConflict: "account_id,provider_txn_id" }).select("id, merchant, posted_date, kind, pending");
      if (error) throw error;
      await triggerMerchantWatches(db, item.user_id, written ?? []);
    }
    if (res.removed.length) {
      const { error } = await db.from("transactions")
        .update({ deleted_at: new Date().toISOString() })
        .eq("user_id", item.user_id)
        .in("provider_txn_id", res.removed.map((r) => r.transaction_id));
      if (error) throw error;
    }

    totals.added += res.added.length; totals.modified += res.modified.length; totals.removed += res.removed.length;
    cursor = res.next_cursor; hasMore = res.has_more;
    const { error } = await db.from("items")
      .update({ sync_cursor: cursor, last_synced_at: new Date().toISOString(), status: "ok" })
      .eq("id", item.id);
    if (error) throw error;
  }
  return totals;
}


/** A charge from a merchant the user asked to be told about: mark the watch triggered (the push rides on this later). */
async function triggerMerchantWatches(db: SupabaseClient, userID: string, rows: { id: string; merchant: string; posted_date: string; kind: string }[]) {
  const { data: watches } = await db.from("watches").select("id, matcher, created_at").eq("user_id", userID).eq("kind", "merchant").eq("status", "watching");
  if (!watches?.length) return;
  for (const w of watches) {
    const hit = rows.find((r) => (r.kind === "spend" || r.kind === "untracked") && merchantKey(r.merchant) === w.matcher && new Date(r.posted_date) > new Date(w.created_at));
    if (hit) await db.from("watches").update({ status: "triggered", resolved_at: new Date().toISOString(), resolved_transaction_id: hit.id }).eq("id", w.id);
  }
}
