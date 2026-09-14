import { json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { encrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { syncItem, upsertAccounts, type ItemRow } from "../_shared/sync.ts";

// Sandbox only: links Plaid's test bank to the signed-in user without the Link UI. Refuses to run outside sandbox.
Deno.serve(async (req) => {
  if ((Deno.env.get("PLAID_ENV") ?? "sandbox") === "production") return json({ error: "sandbox only" }, 403);
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const { institution_id = "ins_109508" } = await req.json().catch(() => ({})) as { institution_id?: string };
  const db = admin();
  try {
    const webhook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/plaid-webhook`;
    const pt = await plaid<{ public_token: string }>("/sandbox/public_token/create", {
      institution_id, initial_products: ["transactions"], options: { webhook },
    });
    const ex = await plaid<{ access_token: string; item_id: string }>("/item/public_token/exchange", { public_token: pt.public_token });
    const { data: item, error } = await db.from("items").upsert({
      user_id: user.id, provider: "plaid", provider_item_id: ex.item_id, access_token_enc: await encrypt(ex.access_token),
      institution_id, institution_name: "First Platypus Bank (sandbox)", status: "ok",
    }, { onConflict: "provider,provider_item_id" }).select("id, user_id, provider_item_id, access_token_enc, sync_cursor").single();
    if (error) throw error;
    const accounts = await plaid<{ accounts: PlaidAccount[] }>("/accounts/get", { access_token: ex.access_token });
    await upsertAccounts(db, item as ItemRow, accounts.accounts);
    const totals = await syncItem(db, item as ItemRow);
    return json({ item_id: item.id, accounts: accounts.accounts.length, ...totals });
  } catch (e) {
    if (e instanceof PlaidError) return json({ error: e.code, message: e.message }, 502);
    throw e;
  }
});
