import { createClient } from "npm:@supabase/supabase-js@2";
import { env, json } from "../_shared/env.ts";
import { admin, userFrom } from "../_shared/db.ts";

// An anonymous user just signed in with Apple. The caller holds BOTH sessions (new one in the header, old one in the body),
// which is the proof of ownership: move every row to the permanent user and retire the anonymous one.
const TABLES = ["items", "accounts", "transactions", "merchant_rules", "streams", "insights", "devices"];

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
  let moved = 0;
  for (const table of TABLES) {
    const { count, error } = await db.from(table).update({ user_id: user.id }, { count: "exact" }).eq("user_id", prev.user.id);
    if (error) return json({ error: error.message, table }, 500);
    moved += count ?? 0;
  }
  // Settings: keep the anonymous user's choices if the new user has none yet.
  const { data: existing } = await db.from("settings").select("user_id").eq("user_id", user.id).maybeSingle();
  if (!existing) await db.from("settings").update({ user_id: user.id }).eq("user_id", prev.user.id);
  await db.auth.admin.deleteUser(prev.user.id);
  return json({ ok: true, moved });
});
