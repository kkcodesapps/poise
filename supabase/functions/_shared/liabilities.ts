import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { plaid, PlaidError } from "./plaid.ts";
import type { ItemRow } from "./sync.ts";

interface Liabilities {
  liabilities?: {
    credit?: { account_id: string; next_payment_due_date: string | null; minimum_payment_amount: number | null; last_statement_balance: number | null }[];
  };
}

/** Card statements from Plaid: when the next payment is due, what the statement was, and the minimum.
 *
 * This is the only place the dates behind Next 14 come from, so when it fails the screen silently leaves a card's
 * payment out — the reason is recorded on the item rather than swallowed, so a card with no due date can say why.
 */
export async function updateStatements(db: SupabaseClient, item: ItemRow, token: string) {
  let status = "ok";
  try {
    const res = await plaid<Liabilities>("/liabilities/get", { access_token: token });
    const credit = res.liabilities?.credit ?? [];
    if (!credit.length) status = "no_credit_accounts";
    for (const c of credit) {
      await db.from("accounts").update({ statement_due: c.next_payment_due_date, statement_amount: c.last_statement_balance, minimum_due: c.minimum_payment_amount })
        .eq("item_id", item.id).eq("provider_account_id", c.account_id);
    }
  } catch (e) {
    // PRODUCTS_NOT_SUPPORTED, ADDITIONAL_CONSENT_REQUIRED, an institution that simply doesn't share it — all look the
    // same from the screen, and all mean the same thing to the user: this card's payment isn't in the forecast.
    status = e instanceof PlaidError ? e.code : "error";
  }
  await db.from("items").update({ liabilities_status: status, liabilities_at: new Date().toISOString() }).eq("id", item.id);
}
