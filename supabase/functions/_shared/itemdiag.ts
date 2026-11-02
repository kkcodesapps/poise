import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { plaid } from "./plaid.ts";
import type { ItemRow } from "./sync.ts";

interface ItemGet {
  item?: { available_products?: string[]; billed_products?: string[]; consented_products?: string[] };
}

/** What this connection is actually allowed to read. "Allow" can complete without the bank granting the product, and
 *  without this the only symptom is a card that never gets a due date. */
export async function recordConsent(db: SupabaseClient, item: ItemRow, token: string) {
  try {
    const res = await plaid<ItemGet>("/item/get", { access_token: token });
    const consented = res.item?.consented_products ?? res.item?.billed_products ?? [];
    await db.from("items").update({ consented_products: consented }).eq("id", item.id);
  } catch { /* diagnostic only: never fail a refresh over it */ }
}
