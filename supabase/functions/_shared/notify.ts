import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { merchantKey } from "./classify.ts";
import { pushPrefs, sendPush } from "./apns.ts";

// What a sync should tell the phone about. Runs after rows are written; never on an item's first walk.

export interface WrittenRow {
  id: string; merchant: string; posted_date: string; kind: string; pending: boolean;
  amount: number; provider_category: string | null; account_id: string; created_at: string; category: string | null;
  pending_txn_id?: string | null;
}

const money = (n: number) => `$${Math.abs(n).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`;
const money0 = (n: number) => `$${Math.round(Math.abs(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`;
const pretty = (s: string) => { const t = s.replace(/[*#/]+/g, " ").replace(/\s+/g, " ").trim(); return /^[^a-z]*$/.test(t) && t.replace(/[^A-Za-z]/g, "").length > 3 ? t.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()) : t; };
const builtIn: Record<string, string> = { home: "Home", groceries: "Groceries", dining: "Dining", transport: "Transport", shopping: "Shopping", subscriptions: "Subscriptions", health: "Health", fun: "Fun", other: "Other" };

export async function notifyAfterSync(db: SupabaseClient, userID: string, written: WrittenRow[], opts: { firstSync: boolean }) {
  if (opts.firstSync || !written.length) return;
  const now = Date.now();
  const cutoff = new Date(now - 3 * 86_400_000).toISOString().slice(0, 10);
  // Rows inserted by this very sync (the upsert echoes updates too), and recent enough to be news.
  const fresh = written.filter((r) => now - new Date(r.created_at).getTime() < 120_000 && r.posted_date >= cutoff);
  if (!fresh.length) return;
  const prefs = await pushPrefs(db, userID);
  const { data: accts } = await db.from("accounts").select("id, name, hidden").in("id", [...new Set(fresh.map((r) => r.account_id))]);
  const accountName = new Map((accts ?? []).map((a: { id: string; name: string }) => [a.id, a.name]));
  const hiddenIDs = new Set((accts ?? []).filter((a: { hidden: boolean }) => a.hidden).map((a: { id: string }) => a.id));
  const rows = fresh.filter((r) => !hiddenIDs.has(r.account_id));
  if (!rows.length) return;

  const categoryName = async (id: string | null) => {
    if (!id) return null;
    if (builtIn[id]) return builtIn[id];
    const { data } = await db.from("categories").select("name").eq("id", id).maybeSingle();
    return data?.name ?? null;
  };

  // --- new spend: one push per sync, batched when several land together
  const isFee = (r: WrittenRow) => (r.provider_category ?? "").startsWith("BANK_FEES");
  const spend = rows.filter((r) => (r.kind === "spend" || r.kind === "untracked") && r.amount < 0 && !isFee(r));   // fees get their own line
  if (prefs.spend && spend.length && spend.length <= 20) {
    if (spend.length === 1) {
      const r = spend[0];
      const cat = await categoryName(r.category);
      await sendPush(db, userID, {
        kind: "spend", title: `${money(r.amount)} at ${pretty(r.merchant)}${cat ? ` · ${cat}` : ""}`,
        body: `${r.pending ? "Pending · " : ""}${accountName.get(r.account_id) ?? "Your account"}`,
        data: { transaction: r.id }, collapseID: `spend-${r.id}`,
      });
    } else {
      const total = spend.reduce((a, r) => a + Math.abs(r.amount), 0);
      const names = [...new Set(spend.map((r) => pretty(r.merchant)))].slice(0, 3).join(", ");
      await sendPush(db, userID, { kind: "spend", title: `${spend.length} charges · ${money(total)}`, body: names + (spend.length > 3 ? " and more" : ""), data: { tab: "home" } });
    }
  }

  if (!prefs.heads_up) return;

  // --- fees
  for (const r of rows.filter((r) => isFee(r) && r.amount < 0)) {
    await sendPush(db, userID, { kind: "heads", title: `${money(r.amount)} fee at ${pretty(r.merchant)}`, body: "Fees add up in Leaks. Banks often waive the first one you ask about.", data: { transaction: r.id }, collapseID: `fee-${r.id}` });
  }

  // --- charged twice: same merchant, same card, same amount, same day — the shape of one purchase posting twice.
  // Mirrors Anomalies.duplicates on the phone: nothing under $10, nothing habitual, nothing the user muted.
  const { data: prefRow } = await db.from("settings").select("dup_muted").eq("user_id", userID).maybeSingle();
  const muted = new Set<string>((prefRow?.dup_muted ?? []) as string[]);
  for (const r of spend) {
    if (Math.abs(r.amount) < 10 || muted.has(merchantKey(r.merchant))) continue;
    const { data: twins } = await db.from("transactions").select("id, merchant, posted_date, pending, provider_txn_id, pending_txn_id").eq("user_id", userID).eq("amount", r.amount)
      .eq("account_id", r.account_id).eq("posted_date", r.posted_date).neq("id", r.id).is("deleted_at", null).limit(5);
    // Two charges means two rows in the same state. A pending row and the posted row it becomes are one charge —
    // whether the provider links them (`pending_txn_id`) or just leaves both behind for a sync or two.
    type Twin = { id: string; merchant: string; posted_date: string; pending: boolean; provider_txn_id: string; pending_txn_id: string | null };
    const twin = (twins ?? []).find((t: Twin) =>
      merchantKey(t.merchant) === merchantKey(r.merchant)
      && t.pending === r.pending                                   // one pending, one posted = the same charge settling
      && t.provider_txn_id !== r.pending_txn_id                    // …and when the provider says so outright
      && t.pending_txn_id == null);
    if (!twin) continue;
    const from = new Date(new Date(r.posted_date).getTime() - 90 * 86_400_000).toISOString().slice(0, 10);
    const { data: same } = await db.from("transactions").select("id, merchant").eq("user_id", userID).eq("amount", r.amount)
      .gte("posted_date", from).lte("posted_date", r.posted_date).is("deleted_at", null).limit(50);
    const habitual = (same ?? []).filter((t: { merchant: string }) => merchantKey(t.merchant) === merchantKey(r.merchant)).length >= 4;
    if (habitual) continue;
    await sendPush(db, userID, { kind: "heads", title: `Charged twice at ${pretty(r.merchant)}?`, body: `${money(r.amount)} twice today on the same card. Tap to look.`, data: { transaction: r.id, insight: `dup-${r.id}` }, collapseID: `dup-${r.id}` });
  }

  // --- a subscription the user marked cancelled, billing again: the top leak, and a push the moment it lands.
  const { data: cancelRow } = await db.from("settings").select("cancelled_streams").eq("user_id", userID).maybeSingle();
  const cancelled = (cancelRow?.cancelled_streams ?? {}) as Record<string, string>;
  for (const r of spend) {
    const key = `spend|${merchantKey(r.merchant)}`;
    const since = Object.entries(cancelled).find(([id]) => id === key || id.startsWith(`${key}|`))?.[1];
    if (!since || r.posted_date < since) continue;
    await sendPush(db, userID, { kind: "heads", title: `${pretty(r.merchant)} charged you after you cancelled`, body: `${money(r.amount)} on ${r.posted_date.slice(5).replace("-", "/")} — you marked it cancelled ${since.slice(5).replace("-", "/")}. Dispute it, or cancel again.`, data: { transaction: r.id, insight: `cancelled-${r.id}` }, collapseID: `cancelled-${r.id}` });
  }

  // --- a tracked item bought at a different price. Only merchant items can be matched here: a name the user gives a
  // charge isn't known until they give it, so those show up in the app the moment they do.
  const { data: priceWatches } = await db.from("watches").select("id, matcher").eq("user_id", userID).eq("kind", "price").eq("status", "watching");
  const tracked = new Set<string>((priceWatches ?? []).map((w: { matcher: string }) => w.matcher));
  if (tracked.size) {
    for (const r of spend) {
      const key = `merchant|${merchantKey(r.merchant)}`;
      if (!tracked.has(key)) continue;
      const { data: earlier } = await db.from("transactions").select("amount, merchant").eq("user_id", userID).eq("kind", "spend").eq("pending", false)
        .lt("posted_date", r.posted_date).is("deleted_at", null).order("posted_date", { ascending: false }).limit(60);
      const prices = (earlier ?? []).filter((t: { merchant: string }) => merchantKey(t.merchant) === merchantKey(r.merchant)).slice(0, 12).map((t: { amount: number }) => Math.abs(t.amount)).sort((a, b) => a - b);
      if (prices.length < 2) continue;
      const usual = prices.length % 2 ? prices[(prices.length - 1) / 2] : (prices[prices.length / 2 - 1] + prices[prices.length / 2]) / 2;
      const price = Math.abs(r.amount), diff = price - usual;
      if (Math.abs(diff) < Math.max(0.5, usual * 0.03)) continue;
      const pct = Math.round(Math.abs(diff) / usual * 100);
      await sendPush(db, userID, { kind: "heads", title: `${pretty(r.merchant)} · ${money(price)}, usually ${money(usual)}`, body: `${diff > 0 ? "Up" : "Down"} ${money(diff)} — ${pct}% ${diff > 0 ? "more" : "less"} for the same thing. Tap for the history.`, data: { item: key }, collapseID: `price-${key}`.slice(0, 64) });
    }
  }

  // --- a refund you were waiting on
  const refunds = rows.filter((r) => r.kind === "refund" && r.amount > 0);
  if (refunds.length) {
    const { data: waiting } = await db.from("watches").select("id, matcher, merchant").eq("user_id", userID).eq("kind", "refund").in("status", ["waiting", "overdue"]);
    for (const r of refunds) {
      const w = (waiting ?? []).find((w: { matcher: string }) => w.matcher === merchantKey(r.merchant));
      if (w) await sendPush(db, userID, { kind: "heads", title: `${pretty(w.merchant)} refund arrived · ${money(r.amount)}`, body: "The watch closes itself the next time Poise opens.", data: { transaction: r.id }, collapseID: `refund-${w.id}` });
    }
  }
}

/** A merchant the user asked to hear about just charged again. Called where the watch is marked triggered. */
export async function notifyWatchTriggered(db: SupabaseClient, userID: string, merchant: string, amount: number, transactionID: string) {
  const prefs = await pushPrefs(db, userID);
  if (!prefs.heads_up) return;
  await sendPush(db, userID, { kind: "heads", title: `${pretty(merchant)} charged again · ${money(amount)}`, body: "You asked to hear about it. Tap to look.", data: { transaction: transactionID }, collapseID: `watch-${transactionID}` });
}

export { money0 };
