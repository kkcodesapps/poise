import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { classifyCategory, merchantKey, type Role } from "./classify.ts";
import { triggerMerchantWatches } from "./sync.ts";

// Apple Card, Apple Cash and Savings arrive from the phone (FinanceKit), not from a provider webhook.
// The app sends what Wallet holds; this module turns it into the same rows the Plaid sync writes.

/** Amounts are unsigned; `debit` says which way the money went (a charge on a card, a withdrawal from cash). */
export interface WalletAccount {
  id: string; name: string; description?: string | null; institution: string; currency: string;
  kind: "asset" | "liability"; creditLimit?: number | null;
}
export interface WalletMoney { amount: number; debit: boolean }
export interface WalletBalance { accountID: string; available?: WalletMoney | null; booked?: WalletMoney | null; asOf: string }
export interface WalletTransaction {
  id: string; accountID: string; amount: number; currency: string; debit: boolean;
  description: string; merchant?: string | null; mcc?: number | null; type: string; status: string;
  date: string; postedDate?: string | null;                 // local calendar days, yyyy-mm-dd
}
/** "These are all of this account's transactions since `since` (or ever, when null) — drop anything else you hold." */
export interface WalletPrune { accountID: string; since?: string | null; keep: string[] }
export interface WalletPayload {
  accounts?: WalletAccount[]; balances?: WalletBalance[];
  transactions?: WalletTransaction[]; prune?: WalletPrune | null;
}

export interface WalletItem { id: string; user_id: string; complete: string[] }

/** One item per user for everything read from Wallet. `sync_cursor` holds which accounts have their full history here. */
export async function ensureWalletItem(db: SupabaseClient, userID: string): Promise<WalletItem> {
  const { data, error } = await db.from("items").upsert({
    user_id: userID, provider: "financekit", provider_item_id: userID,
    institution_id: "apple", institution_name: "Apple", status: "ok",
  }, { onConflict: "provider,provider_item_id" }).select("id, user_id, sync_cursor").single();
  if (error) throw error;
  let complete: string[] = [];
  try { const parsed = JSON.parse(data.sync_cursor ?? "{}"); if (Array.isArray(parsed.complete)) complete = parsed.complete; } catch { /* fresh item */ }
  return { id: data.id, user_id: data.user_id, complete };
}

// Wallet's indicator means two different things. Balances follow accounting: money you hold is a debit balance,
// money you owe is a credit balance. Transactions read like a statement: a debit is money leaving (a charge, a
// withdrawal), a credit is money arriving (a payment, a refund, Daily Cash). Both confirmed against real Apple Card data.
const signed = (m: WalletMoney | null | undefined, positiveWhenDebit: boolean): number | null =>
  m == null ? null : (m.debit === positiveWhenDebit ? m.amount : -m.amount);
const outflow = (t: WalletTransaction): boolean => t.debit;

function roleFor(a: WalletAccount): Role {
  if (a.kind === "liability") return "credit";
  return /savings/i.test(`${a.name} ${a.description ?? ""}`) ? "savings" : "spending";
}

/** Upserts the Wallet accounts (role only on insert, as with Plaid) and returns FinanceKit account id → accounts.id. */
export async function upsertWalletAccounts(db: SupabaseClient, item: WalletItem, accounts: WalletAccount[], balances: WalletBalance[]): Promise<Map<string, string>> {
  if (accounts.length) {
    const byAccount = new Map(balances.map((b) => [b.accountID, b]));
    const rows = accounts.map((a) => {
      const b = byAccount.get(a.id);
      const liability = a.kind === "liability";
      // Cards: current = what's owed (positive), available = credit left. Cash/savings: signed balances as they are.
      const owed = signed(b?.booked ?? b?.available, false) ?? 0;
      const current = liability ? owed : (signed(b?.booked, true) ?? signed(b?.available, true) ?? 0);
      const available = liability
        ? (a.creditLimit != null ? Math.max(0, a.creditLimit - owed) : null)
        : signed(b?.available, true);
      return {
        item_id: item.id, user_id: item.user_id, provider_account_id: a.id,
        name: a.name, mask: null, type: liability ? "credit" : "depository", subtype: a.name.toLowerCase(),
        available, current, credit_limit: a.creditLimit ?? null, currency: a.currency || "USD",
        balance_at: b?.asOf ?? new Date().toISOString(),
      };
    });
    const { data: existing } = await db.from("accounts").select("provider_account_id").eq("item_id", item.id);
    const known = new Set((existing ?? []).map((r: { provider_account_id: string }) => r.provider_account_id));
    const withRole = rows.map((r, i) => (known.has(r.provider_account_id) ? r : { ...r, role: roleFor(accounts[i]) }));
    const { error } = await db.from("accounts").upsert(withRole, { onConflict: "item_id,provider_account_id" });
    if (error) throw error;
  }
  const { data } = await db.from("accounts").select("id, provider_account_id").eq("item_id", item.id);
  return new Map((data ?? []).map((r: { id: string; provider_account_id: string }) => [r.provider_account_id, r.id]));
}

type PFC = [primary: string, detailed: string];

/** Merchant category code → the same primary/detailed vocabulary Plaid uses, so one classifier serves both. */
function categoryForMCC(m: number): PFC {
  const between = (a: number, b: number) => m >= a && m <= b;
  const oneOf = (...codes: number[]) => codes.includes(m);
  if (between(1500, 1799) || between(5200, 5271) || between(5712, 5722) || oneOf(5983, 5996, 4225, 4214)) return ["HOME_IMPROVEMENT", "HOME_IMPROVEMENT_OTHER"];
  if (m === 6513) return ["RENT_AND_UTILITIES", "RENT_AND_UTILITIES_RENT"];
  if (m === 4814) return ["RENT_AND_UTILITIES", "RENT_AND_UTILITIES_TELEPHONE"];
  if (m === 4816) return ["RENT_AND_UTILITIES", "RENT_AND_UTILITIES_INTERNET_AND_CABLE"];
  if (m === 4900) return ["RENT_AND_UTILITIES", "RENT_AND_UTILITIES_GAS_AND_ELECTRICITY"];
  if (m === 4899) return ["ENTERTAINMENT", "ENTERTAINMENT_TV_AND_MOVIES"];
  if (oneOf(5411, 5422, 5441, 5451, 5462, 5499, 5300)) return ["FOOD_AND_DRINK", "FOOD_AND_DRINK_GROCERIES"];
  if (m === 5814) return ["FOOD_AND_DRINK", "FOOD_AND_DRINK_FAST_FOOD"];
  if (between(5811, 5813)) return ["FOOD_AND_DRINK", "FOOD_AND_DRINK_RESTAURANT"];
  if (m === 5921) return ["FOOD_AND_DRINK", "FOOD_AND_DRINK_BEER_WINE_AND_LIQUOR"];
  if (between(3000, 3299) || m === 4511) return ["TRAVEL", "TRAVEL_FLIGHTS"];
  if (between(3501, 3999) || between(7011, 7012)) return ["TRAVEL", "TRAVEL_LODGING"];
  if (oneOf(4411, 4722, 7032, 7033)) return ["TRAVEL", "TRAVEL_OTHER_TRAVEL"];
  if (between(3351, 3441)) return ["TRANSPORTATION", "TRANSPORTATION_OTHER_TRANSPORTATION"];
  if (oneOf(5541, 5542)) return ["TRANSPORTATION", "TRANSPORTATION_GAS"];
  if (m === 4121) return ["TRANSPORTATION", "TRANSPORTATION_TAXIS_AND_RIDE_SHARES"];
  if (m === 7523) return ["TRANSPORTATION", "TRANSPORTATION_PARKING"];
  if (m === 4784) return ["TRANSPORTATION", "TRANSPORTATION_TOLLS"];
  if (oneOf(4011, 4111, 4112, 4131)) return ["TRANSPORTATION", "TRANSPORTATION_PUBLIC_TRANSIT"];
  if (oneOf(4582, 4789, 5571, 5599) || between(5531, 5533) || between(7531, 7549)) return ["TRANSPORTATION", "TRANSPORTATION_OTHER_TRANSPORTATION"];
  if (m === 5912) return ["MEDICAL", "MEDICAL_PHARMACIES_AND_SUPPLEMENTS"];
  if (between(8011, 8099) || oneOf(4119, 5975, 5976)) return ["MEDICAL", "MEDICAL_OTHER_MEDICAL"];
  if (oneOf(7230, 7297, 7298, 5977)) return ["PERSONAL_CARE", "PERSONAL_CARE_HAIR_AND_BEAUTY"];
  if (oneOf(7210, 7211, 7216)) return ["PERSONAL_CARE", "PERSONAL_CARE_LAUNDRY_AND_DRY_CLEANING"];
  if (oneOf(7941, 7997)) return ["PERSONAL_CARE", "PERSONAL_CARE_GYMS_AND_FITNESS_CENTERS"];
  if (oneOf(5815, 5817, 5818)) return ["ENTERTAINMENT", "ENTERTAINMENT_MUSIC_AND_AUDIO"];
  if (m === 5816) return ["ENTERTAINMENT", "ENTERTAINMENT_VIDEO_GAMES"];
  if (oneOf(7832, 7841) || between(7911, 7999)) return ["ENTERTAINMENT", "ENTERTAINMENT_OTHER_ENTERTAINMENT"];
  if (oneOf(5960, 6300)) return ["GENERAL_SERVICES", "GENERAL_SERVICES_INSURANCE"];
  if (between(8211, 8299)) return ["GENERAL_SERVICES", "GENERAL_SERVICES_EDUCATION"];
  if (m === 8351) return ["GENERAL_SERVICES", "GENERAL_SERVICES_CHILDCARE"];
  if (m === 4215) return ["GENERAL_SERVICES", "GENERAL_SERVICES_POSTAGE_AND_SHIPPING"];
  if (m === 8398 || between(9211, 9399)) return ["GOVERNMENT_AND_NON_PROFIT", "GOVERNMENT_AND_NON_PROFIT_OTHER"];
  if (between(6010, 6012) || oneOf(6051, 6211)) return ["GENERAL_SERVICES", "GENERAL_SERVICES_FINANCIAL"];
  if (oneOf(742, 7299) || between(7311, 7399) || between(8111, 8999)) return ["GENERAL_SERVICES", "GENERAL_SERVICES_OTHER"];
  if (oneOf(5732, 4812)) return ["GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_ELECTRONICS"];
  if (m === 5995) return ["GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_PET_SUPPLIES"];
  if (between(5611, 5699)) return ["GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_CLOTHING_AND_ACCESSORIES"];
  if (between(5013, 5199) || between(5309, 5399) || between(5931, 5999) || oneOf(5733, 5734, 5735, 5940, 5941)) return ["GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_OTHER"];
  return ["GENERAL_SERVICES", "GENERAL_SERVICES_OTHER"];
}

/** What kind of money movement this is. Type first (fees, interest, payments, transfers), then the merchant code. */
function categoryFor(t: WalletTransaction, liability: boolean, out: boolean): PFC {
  const inflow = !out;
  const cardPayment: PFC = ["LOAN_PAYMENTS", "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT"];
  switch (t.type) {
    case "fee": return ["BANK_FEES", "BANK_FEES_OTHER_BANK_FEES"];
    case "interest": return out ? ["BANK_FEES", "BANK_FEES_INTEREST_CHARGE"] : ["INCOME", "INCOME_INTEREST_EARNED"];
    case "dividend": return ["INCOME", "INCOME_DIVIDENDS"];
    case "directDeposit": return ["INCOME", "INCOME_WAGES"];
    case "deposit": return liability && inflow ? cardPayment : ["INCOME", "INCOME_OTHER_INCOME"];
    case "transfer":
      if (liability) { if (inflow) return cardPayment; break; }
      return out ? ["TRANSFER_OUT", "TRANSFER_OUT_ACCOUNT_TRANSFER"] : ["TRANSFER_IN", "TRANSFER_IN_ACCOUNT_TRANSFER"];
    case "billPayment":
    case "standingOrder":
    case "directDebit":
      if (liability && inflow) return cardPayment;
      break;
    case "atm":
    case "withdrawal":
      if (!liability) return out ? ["TRANSFER_OUT", "TRANSFER_OUT_WITHDRAWAL"] : ["TRANSFER_IN", "TRANSFER_IN_DEPOSIT"];
      break;
  }
  // Money into a card that isn't a merchant refund is the statement being paid.
  if (liability && inflow && t.type !== "refund" && t.mcc == null && /payment|thank you/i.test(t.description)) return cardPayment;
  // Money arriving in Apple Cash with no merchant behind it: someone sent it.
  if (!liability && inflow && t.mcc == null && (t.type === "unknown" || t.type === "adjustment")) return ["INCOME", "INCOME_OTHER_INCOME"];
  if (t.mcc != null) return categoryForMCC(t.mcc);
  if (t.type === "refund") return ["GENERAL_MERCHANDISE", "GENERAL_MERCHANDISE_OTHER"];
  return ["GENERAL_SERVICES", "GENERAL_SERVICES_OTHER"];
}

const pendingStatuses = new Set(["pending", "authorized", "memo"]);

/** Trims a raw descriptor when Wallet gives no merchant name ("APPLE.COM/BILL 866-712-7753 CA" → "APPLE.COM/BILL"); the app title-cases shouting. */
function merchantName(t: WalletTransaction): string {
  if (t.merchant?.trim()) return t.merchant.trim();
  const words = t.description.replace(/\s+/g, " ").trim().split(" ").filter((w) => !/^[\d\-()#*]+$/.test(w));
  if (words.length > 1 && /^[A-Z]{2}$/.test(words[words.length - 1])) words.pop();   // trailing state code
  return words.slice(0, 3).join(" ") || "Apple";
}

/** Writes accounts, balances and transactions, then prunes what Wallet no longer lists. Returns counts for the app. */
export async function applyWallet(db: SupabaseClient, item: WalletItem, body: WalletPayload): Promise<{ accounts: number; transactions: number; pruned: number; complete: string[] }> {
  const accountIDs = await upsertWalletAccounts(db, item, body.accounts ?? [], body.balances ?? []);
  const { data: accountRows } = await db.from("accounts").select("id, type").eq("item_id", item.id);
  const liabilityIDs = new Set((accountRows ?? []).filter((a: { type: string | null }) => a.type === "credit").map((a: { id: string }) => a.id));

  const { data: ruleRows } = await db.from("merchant_rules").select("matcher, category, kind").eq("user_id", item.user_id);
  const rules = new Map((ruleRows ?? []).map((r: { matcher: string; category: string | null; kind: string | null }) => [r.matcher, r]));

  const incoming = body.transactions ?? [];
  const rejected = incoming.filter((t) => t.status === "rejected").map((t) => t.id);
  const rows = incoming.filter((t) => t.status !== "rejected").flatMap((t) => {
    const accountID = accountIDs.get(t.accountID);
    if (!accountID) return [];
    const liability = liabilityIDs.has(accountID);
    const out = outflow(t);
    const [primary, detailed] = categoryFor(t, liability, out);
    const auto = classifyCategory(primary, detailed, !out);
    const merchant = merchantName(t);
    const rule = rules.get(merchantKey(merchant));
    return [{
      account_id: accountID,
      user_id: item.user_id,
      provider_txn_id: t.id,
      pending: pendingStatuses.has(t.status),
      pending_txn_id: null,
      amount: out ? -Math.abs(t.amount) : Math.abs(t.amount),
      currency: t.currency || "USD",
      merchant,
      raw_name: t.description,
      authorized_date: t.date,
      posted_date: t.postedDate ?? t.date,
      kind: rule?.kind ?? auto.kind,
      category: rule?.category ?? auto.category,
      provider_category: detailed,
      classified_by: rule ? "rule" : "auto",
      deleted_at: null,                                  // back in Wallet's list = back in the feed
    }];
  });
  if (rows.length) {
    const { data: written, error } = await db.from("transactions").upsert(rows, { onConflict: "account_id,provider_txn_id" }).select("id, merchant, posted_date, kind, pending");
    if (error) throw error;
    await triggerMerchantWatches(db, item.user_id, written ?? []);
  }

  let pruned = 0;
  const gone = new Set(rejected);
  if (body.prune) {
    const accountID = accountIDs.get(body.prune.accountID);
    if (accountID) {
      const keep = new Set(body.prune.keep);
      let q = db.from("transactions").select("id, provider_txn_id").eq("account_id", accountID).is("deleted_at", null);
      if (body.prune.since) q = q.gte("authorized_date", body.prune.since);
      const { data: held, error } = await q;
      if (error) throw error;
      for (const r of held ?? []) if (!keep.has(r.provider_txn_id)) gone.add(r.provider_txn_id);
    }
  }
  if (gone.size) {
    const ids = [...gone];
    for (let i = 0; i < ids.length; i += 200) {
      const { error } = await db.from("transactions")
        .update({ deleted_at: new Date().toISOString() })
        .eq("user_id", item.user_id)
        .in("provider_txn_id", ids.slice(i, i + 200));
      if (error) throw error;
    }
    pruned = ids.length;
  }
  // A prune with no `since` means the whole history is here now; later syncs for that account can send the window only.
  const complete = body.prune && body.prune.since == null && !item.complete.includes(body.prune.accountID)
    ? [...item.complete, body.prune.accountID] : item.complete;
  const { error } = await db.from("items")
    .update({ last_synced_at: new Date().toISOString(), status: "ok", sync_cursor: JSON.stringify({ complete }) })
    .eq("id", item.id);
  if (error) throw error;
  return { accounts: body.accounts?.length ?? 0, transactions: rows.length, pruned, complete };
}
