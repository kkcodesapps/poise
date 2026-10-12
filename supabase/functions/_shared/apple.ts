import { env } from "./env.ts";

// Sign in with Apple, server side: the client secret is an ES256 JWT signed with the "Poise Sign In" key. Apple's token
// endpoint turns the app's one-time authorization code into a refresh token; the revoke endpoint ends the sign-in.

const CLIENT_ID = "com.koliokolev.poise";
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const utf8 = (s: string) => new TextEncoder().encode(s);

async function clientSecret(): Promise<string> {
  const pem = env("SIWA_KEY").replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: env("SIWA_KEY_ID") })));
  const claims = b64url(utf8(JSON.stringify({ iss: env("SIWA_TEAM_ID"), iat: now, exp: now + 3600, aud: "https://appleid.apple.com", sub: CLIENT_ID })));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(`${header}.${claims}`)));
  return `${header}.${claims}.${b64url(sig)}`;
}

async function post(path: string, fields: Record<string, string>): Promise<Response> {
  const body = new URLSearchParams({ client_id: CLIENT_ID, client_secret: await clientSecret(), ...fields });
  return await fetch(`https://appleid.apple.com/auth/${path}`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body });
}

/** The authorization code is good for five minutes and one use. Returns Apple's refresh token and the subject it belongs to. */
export async function exchangeAppleCode(code: string): Promise<{ refreshToken: string; sub: string | null }> {
  const res = await post("token", { grant_type: "authorization_code", code });
  const data = await res.json().catch(() => ({})) as { refresh_token?: string; id_token?: string; error?: string };
  if (!res.ok || !data.refresh_token) throw new Error(`apple token exchange failed: ${data.error ?? res.status}`);
  let sub: string | null = null;
  try { sub = JSON.parse(atob(data.id_token!.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).sub ?? null; } catch { /* no id token */ }
  return { refreshToken: data.refresh_token, sub };
}

/** Ends the user's Sign in with Apple for Poise. Apple answers 200 for a token it already forgot, so this is safe to repeat. */
export async function revokeAppleToken(refreshToken: string): Promise<boolean> {
  const res = await post("revoke", { token: refreshToken, token_type_hint: "refresh_token" });
  return res.ok;
}
