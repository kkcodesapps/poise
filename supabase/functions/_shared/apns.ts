import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { env } from "./env.ts";

// Pushes, token-authenticated (ES256 JWT signed with the APNs key). One JWT per invocation is plenty.

export interface Push {
  title: string;
  body: string;
  /** "spend" | "heads" | "review" — the app decides how to show it; also the iOS thread. */
  kind: string;
  /** Deep-link hints the app understands: transaction, stream, insight, tab. */
  data?: Record<string, string>;
  /** Collapses repeats of the same thing (e.g. one merchant's watch). */
  collapseID?: string;
}

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const utf8 = (s: string) => new TextEncoder().encode(s);

let cached: { jwt: string; at: number } | null = null;

async function providerToken(): Promise<string> {
  if (cached && Date.now() - cached.at < 40 * 60 * 1000) return cached.jwt;   // Apple accepts a token for an hour
  const pem = env("APNS_KEY").replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") })));
  const claims = b64url(utf8(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) })));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(`${header}.${claims}`)));
  cached = { jwt: `${header}.${claims}.${b64url(sig)}`, at: Date.now() };
  return cached.jwt;
}

/** Sends one push to every device the user registered. Dead tokens are dropped as Apple reports them. */
export async function sendPush(db: SupabaseClient, userID: string, push: Push): Promise<number> {
  const { data: devices } = await db.from("devices").select("id, apns_token, env").eq("user_id", userID);
  if (!devices?.length) return 0;
  const jwt = await providerToken();
  const payload = JSON.stringify({
    aps: { alert: { title: push.title, body: push.body }, sound: "default", "thread-id": push.kind, "interruption-level": push.kind === "spend" ? "active" : "time-sensitive" },
    kind: push.kind,
    ...(push.data ?? {}),
  });
  let sent = 0;
  for (const d of devices) {
    const host = d.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": "com.koliokolev.poise",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 6 * 3600),
    };
    if (push.collapseID) headers["apns-collapse-id"] = push.collapseID.slice(0, 64);
    try {
      const res = await fetch(`https://${host}/3/device/${d.apns_token}`, { method: "POST", headers, body: payload });
      if (res.ok) { sent++; continue; }
      const reason = (await res.json().catch(() => ({})) as { reason?: string }).reason;
      if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic") {
        await db.from("devices").delete().eq("id", d.id);
      }
    } catch { /* network: try again next event */ }
  }
  return sent;
}

interface Prefs { spend: boolean; heads_up: boolean; weekly_review: boolean }
export async function pushPrefs(db: SupabaseClient, userID: string): Promise<Prefs> {
  const { data } = await db.from("settings").select("notif_prefs").eq("user_id", userID).maybeSingle();
  const p = (data?.notif_prefs ?? {}) as Partial<Prefs>;
  return { spend: p.spend ?? true, heads_up: p.heads_up ?? true, weekly_review: p.weekly_review ?? true };
}
