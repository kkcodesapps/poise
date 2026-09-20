import { json } from "../_shared/env.ts";
import { plaid } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";

// Delete everything: revoke every bank connection at the provider, then remove the auth user (rows cascade).
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const db = admin();
  const { data: items } = await db.from("items").select("id, provider, access_token_enc").eq("user_id", user.id);
  let revoked = 0;
  for (const item of items ?? []) {
    if (item.provider !== "plaid" || !item.access_token_enc) continue;
    try { await plaid("/item/remove", { access_token: await decrypt(item.access_token_enc) }); revoked++; } catch { /* already gone */ }
  }
  const { error } = await db.auth.admin.deleteUser(user.id);
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true, revoked });
});
