import type { PlaidAccount, PlaidTransaction } from "./plaid.ts";

export type Kind = "spend" | "income" | "transfer" | "cc_payment" | "refund" | "untracked";
export type Category = "home" | "groceries" | "dining" | "transport" | "shopping" | "subscriptions" | "health" | "fun" | "other";
export type Role = "spending" | "savings" | "credit" | "other";

/** Account role from the provider's type/subtype. The user can change it later. */
export function roleFor(a: PlaidAccount): Role {
  if (a.type === "credit") return "credit";
  if (a.type === "depository") {
    const s = (a.subtype ?? "").toLowerCase();
    if (s === "savings" || s === "money market" || s === "cd") return "savings";
    return "spending";
  }
  return "other";
}

/** Nine buckets from Plaid's personal finance category. Merchant rules override this at sync time. */
export function classify(t: PlaidTransaction): { kind: Kind; category: Category | null } {
  const primary = t.personal_finance_category?.primary ?? "";
  const detailed = t.personal_finance_category?.detailed ?? "";
  const inflow = t.amount < 0;
  const spend = (category: Category): { kind: Kind; category: Category | null } =>
    inflow ? { kind: "refund", category } : { kind: "spend", category };   // money back at a spend category is a refund

  switch (primary) {
    case "INCOME": return { kind: "income", category: null };
    case "TRANSFER_IN":
    case "TRANSFER_OUT": return { kind: "transfer", category: null };
    case "LOAN_PAYMENTS":
      if (detailed === "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT") return { kind: "cc_payment", category: null };
      return spend("home");
    case "BANK_FEES": return spend("other");
    case "FOOD_AND_DRINK":
      return spend(detailed === "FOOD_AND_DRINK_GROCERIES" ? "groceries" : "dining");
    case "TRANSPORTATION": return spend("transport");
    case "TRAVEL": return spend("fun");
    case "RENT_AND_UTILITIES":
    case "HOME_IMPROVEMENT": return spend("home");
    case "MEDICAL":
    case "PERSONAL_CARE": return spend("health");
    case "GENERAL_MERCHANDISE": return spend("shopping");
    case "ENTERTAINMENT":
      return spend(/TV_AND_MOVIES|MUSIC_AND_AUDIO|VIDEO_GAMES/.test(detailed) ? "subscriptions" : "fun");
    case "GENERAL_SERVICES": return spend("other");
    default:
      if (inflow) return { kind: "income", category: null };
      return spend("other");
  }
}

/** Fee detection for the Leaks tab; stored via provider_category, surfaced by the client. */
export const isFee = (t: PlaidTransaction) => (t.personal_finance_category?.primary ?? "") === "BANK_FEES";

/** Normalized merchant key for rules: lower-case, digits and punctuation stripped. */
export const merchantKey = (name: string) => name.toLowerCase().replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim();
