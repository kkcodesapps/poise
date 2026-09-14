import { env } from "./env.ts";

// Provider access tokens never leave the server and sit encrypted in Postgres (AES-256-GCM, key in ITEM_KEY).

async function key(): Promise<CryptoKey> {
  const raw = Uint8Array.from(atob(env("ITEM_KEY")), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
const unhex = (s: string) => Uint8Array.from(s.match(/.{2}/g) ?? [], (h) => parseInt(h, 16));

/** Returns a Postgres bytea literal (`\x…`) holding iv || ciphertext. */
export async function encrypt(plain: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(), new TextEncoder().encode(plain)));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv); out.set(ct, iv.length);
  return "\\x" + hex(out);
}

export async function decrypt(bytea: string): Promise<string> {
  const bytes = unhex(bytea.replace(/^\\x/, ""));
  const iv = bytes.slice(0, 12), ct = bytes.slice(12);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, await key(), ct);
  return new TextDecoder().decode(plain);
}
