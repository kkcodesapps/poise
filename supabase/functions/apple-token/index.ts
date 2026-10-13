import { json } from "../_shared/env.ts";
import { encrypt } from "../_shared/crypto.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { exchangeAppleCode } from "../_shared/apple.ts";

// Right after Sign in with Apple: swap the one-time authorization code for a refresh token and keep it for revocation.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const { code } = await req.json().catch(() => ({})) as { code?: string };
  if (!code) return json({ error: "code required" }, 400);
  const db = admin();
  try {
    const { refreshToken, sub } = await exchangeAppleCode(code);
    // The code must belong to the Apple identity on this account — a stray code can't be parked on someone else's user.
    const { data: full } = await db.auth.admin.getUserById(user.id);
    const apple = full.user?.identities?.find((i) => i.provider === "apple");
    if (apple && sub && apple.id !== sub) return json({ error: "code belongs to another Apple ID" }, 403);
    const { error } = await db.from("apple_tokens").upsert({ user_id: user.id, refresh_token_enc: await encrypt(refreshToken), created_at: new Date().toISOString() });
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true });
  } catch (e) {
    return json({ error: (e as Error).message }, 502);
  }
});
