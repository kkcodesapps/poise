import * as jose from "npm:jose@5";
import { json } from "../_shared/env.ts";
import { plaid } from "../_shared/plaid.ts";
import { admin } from "../_shared/db.ts";
import { syncItem, type ItemRow } from "../_shared/sync.ts";

// Plaid calls this. Every request is verified against Plaid's signing key before anything is touched.

const keys = new Map<string, jose.KeyLike>();

async function verify(req: Request, rawBody: string): Promise<boolean> {
  const token = req.headers.get("plaid-verification");
  if (!token) return false;
  const { kid, alg } = jose.decodeProtectedHeader(token);
  if (alg !== "ES256" || !kid) return false;
  let key = keys.get(kid);
  if (!key) {
    const res = await plaid<{ key: jose.JWK }>("/webhook_verification_key/get", { key_id: kid });
    key = await jose.importJWK(res.key, "ES256") as jose.KeyLike;
    keys.set(kid, key);
  }
  try {
    const { payload } = await jose.jwtVerify(token, key, { maxTokenAge: "5 minutes" });
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rawBody));
    const hex = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
    return payload.request_body_sha256 === hex;
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  const raw = await req.text();
  if (!(await verify(req, raw))) return json({ error: "invalid signature" }, 401);
  const hook = JSON.parse(raw) as { webhook_type: string; webhook_code: string; item_id: string; error?: { error_code?: string } };
  const db = admin();
  const { data: item } = await db.from("items")
    .select("id, user_id, provider_item_id, access_token_enc, sync_cursor")
    .eq("provider", "plaid").eq("provider_item_id", hook.item_id).maybeSingle();
  if (!item) return json({ ok: true, ignored: "unknown item" });

  if (hook.webhook_type === "TRANSACTIONS" && hook.webhook_code === "SYNC_UPDATES_AVAILABLE") {
    const totals = await syncItem(db, item as ItemRow);
    await db.from("refresh_log").insert({ item_id: item.id, trigger: "webhook", cost_units: 0 });
    return json({ ok: true, ...totals });
  }
  if (hook.webhook_type === "ITEM") {
    if (hook.webhook_code === "ERROR" && hook.error?.error_code === "ITEM_LOGIN_REQUIRED") {
      await db.from("items").update({ status: "relink" }).eq("id", item.id);
    } else if (hook.webhook_code === "PENDING_EXPIRATION" || hook.webhook_code === "PENDING_DISCONNECT") {
      await db.from("items").update({ status: "relink" }).eq("id", item.id);
    } else if (hook.webhook_code === "USER_PERMISSION_REVOKED") {
      await db.from("items").update({ status: "error" }).eq("id", item.id);
    }
  }
  return json({ ok: true });
});
