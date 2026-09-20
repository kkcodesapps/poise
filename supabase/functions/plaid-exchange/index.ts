import { json } from "../_shared/env.ts";
import { plaid, PlaidError, type PlaidAccount } from "../_shared/plaid.ts";
import { encrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { syncItem, upsertAccounts, type ItemRow } from "../_shared/sync.ts";

// Exchanges a Link public token, stores the item (token encrypted), pulls accounts, runs the first sync.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => ({})) as { public_token?: string; institution?: { id?: string; name?: string }; item_id?: string };
  const db = admin();
  if (body.item_id && !body.public_token) {
    // Repair after Link update mode: the stored token works again — mark healthy and resync.
    const { data: item } = await db.from("items").select("id, user_id, provider_item_id, access_token_enc, sync_cursor").eq("id", body.item_id).eq("user_id", user.id).single();
    if (!item) return json({ error: "item not found" }, 404);
    await db.from("items").update({ status: "ok" }).eq("id", item.id);
    const totals = await syncItem(db, item as ItemRow).catch(() => ({ added: 0, modified: 0, removed: 0 }));
    return json({ item_id: item.id, repaired: true, ...totals });
  }
  if (!body.public_token) return json({ error: "public_token required" }, 400);
  try {
    const ex = await plaid<{ access_token: string; item_id: string }>("/item/public_token/exchange", { public_token: body.public_token });
    const { data: item, error } = await db.from("items").upsert({
      user_id: user.id,
      provider: "plaid",
      provider_item_id: ex.item_id,
      access_token_enc: await encrypt(ex.access_token),
      institution_id: body.institution?.id ?? null,
      institution_name: body.institution?.name ?? null,
      status: "ok",
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
