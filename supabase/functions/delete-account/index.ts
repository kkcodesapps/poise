import { json } from "../_shared/env.ts";
import { plaid } from "../_shared/plaid.ts";
import { decrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { revokeAppleToken } from "../_shared/apple.ts";

// Delete everything: revoke every bank connection at the provider and the Apple sign-in, then remove the auth user
// (rows cascade).
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
  let appleRevoked = false;
  const { data: apple } = await db.from("apple_tokens").select("refresh_token_enc").eq("user_id", user.id).maybeSingle();
  if (apple?.refresh_token_enc) {
    try { appleRevoked = await revokeAppleToken(await decrypt(apple.refresh_token_enc)); } catch { /* Apple unreachable: the account still goes */ }
  }
  const { error } = await db.auth.admin.deleteUser(user.id);
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true, revoked, appleRevoked });
});
