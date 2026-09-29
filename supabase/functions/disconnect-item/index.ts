import { json } from "../_shared/env.ts";
import { plaid } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";

// Disconnect one institution: revoke it at the provider, then delete the item (its accounts and rows cascade).
// Watches that pointed at its transactions keep their status; the transaction links are nulled by the schema.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => ({})) as { item_id?: string };
  if (!body.item_id) return json({ error: "item_id required" }, 400);
  const db = admin();
  const { data: item } = await db.from("items").select("id, provider, access_token_enc").eq("id", body.item_id).eq("user_id", user.id).single();
  if (!item) return json({ error: "item not found" }, 404);
  let revoked = false;
  if (item.provider === "plaid" && item.access_token_enc) {
    try { await plaid("/item/remove", { access_token: await decrypt(item.access_token_enc) }); revoked = true; } catch { /* already gone at Plaid */ }
  }
  const { error } = await db.from("items").delete().eq("id", item.id);
  if (error) throw error;
  return json({ ok: true, revoked });
});
