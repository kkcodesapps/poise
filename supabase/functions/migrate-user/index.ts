import { createClient } from "npm:@supabase/supabase-js@2";
import { env, json } from "../_shared/env.ts";
import { admin, userFrom } from "../_shared/db.ts";

// An anonymous user just signed in with Apple. The caller holds BOTH sessions (new one in the header, old one in the body),
// which is the proof of ownership: move every row to the permanent user and retire the anonymous one.
//
// The move itself is `migrate_user` in SQL: one transaction, and every table with a user_id, so nothing is left on the
// anonymous user to be cascade-deleted with it (Amazon order items were, by the table list this used to keep).

Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const { previous_token } = await req.json().catch(() => ({})) as { previous_token?: string };
  if (!previous_token) return json({ error: "previous_token required" }, 400);

  const verifier = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false } });
  const { data: prev } = await verifier.auth.getUser(previous_token);
  if (!prev.user || prev.user.id === user.id) return json({ ok: true, moved: 0 });
  if (!prev.user.is_anonymous) return json({ error: "previous session is not anonymous" }, 403);

  const db = admin();
  const { data: moved, error } = await db.rpc("migrate_user", { old_id: prev.user.id, new_id: user.id });
  if (error) return json({ error: error.message }, 500);   // nothing moved, and the anonymous user is kept
  await db.auth.admin.deleteUser(prev.user.id);
  return json({ ok: true, moved });
});
