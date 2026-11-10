import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { env } from "./env.ts";

// Logos for merchants Plaid has none for. Each one is looked up once — Logo.dev's search turns the name into a domain,
// its image CDN gives the logo — and the image is copied into our own `logos` bucket, so phones load it from us and
// Logo.dev only ever hears about a merchant the first time anyone is charged by it. A miss is remembered too.
//
// The free plan stops hard at its limits and never bills, so the worst a runaway could do is go quiet until next month.
// The caps keep it nowhere near: a few dozen merchants an hour, a couple of thousand a month.

const PER_RUN = 25;
const PER_MONTH = 2000;

/** Brands the name search gets wrong or can't find from how banks spell them. A merchant key matches when it is the
 *  key or starts with it ("starbucks coffee company", "apple store", "tesla supercharger"). */
const DOMAINS: Record<string, string> = {
  "apple": "apple.com", "icloud": "apple.com", "amazon": "amazon.com", "whole foods": "wholefoodsmarket.com",
  "starbucks": "starbucks.com", "chipotle": "chipotle.com", "shell": "shell.com", "tesla": "tesla.com",
  "victoria s secret": "victoriassecret.com", "h m": "hm.com", "jewel osco": "jewelosco.com", "aldi": "aldi.us",
  "meijer": "meijer.com", "the home depot": "homedepot.com", "home depot": "homedepot.com", "peloton": "onepeloton.com",
  "td auto finance": "td.com", "chick fil a": "chick-fil-a.com", "mod pizza": "modpizza.com", "walgreens": "walgreens.com",
  "nintendo": "nintendo.com", "us post office": "usps.com", "usps": "usps.com", "crate barrel": "crateandbarrel.com",
  "dunkin": "dunkindonuts.com", "jersey mike s": "jerseymikes.com", "advocate": "advocatehealth.com", "aerie": "ae.com",
  "five guys": "fiveguys.com", "markel": "markel.com", "marble slab": "marbleslab.com", "amorino": "amorino.com",
  "transportation security administration": "tsa.gov", "tsa": "tsa.gov",
};
const known = (k: string) => Object.entries(DOMAINS).find(([d]) => k === d || k.startsWith(d + " "))?.[1] ?? null;

/** Names that are a payment processor or a bank's own line, not the place you bought from. */
const SKIP = /^(toast|tst|sq|square|adjustment|payment|transfer|interest|fee|zelle|venmo|cash app|paypal)( |$)/;

const key = (s: string) => s.toLowerCase().replace(/[^\p{L} ]/gu, " ").replace(/ +/g, " ").trim();
/** Words that don't tell one business from another: legal suffixes, the bank's own billing words, stray letters. */
const NOISE = new Set(["the", "and", "of", "store", "stores", "online", "com", "inc", "llc", "ltd", "co", "corp", "company",
  "usa", "payment", "pymt", "pmt", "bill", "web", "id", "loan", "purchase", "restaurant", "restaurants"]);
const core = (s: string) => key(s).split(" ").filter((w) => w.length > 1 && !NOISE.has(w));
/** US merchants live on these; a country domain (.de, .co.uk, .com.au) is somebody else with the same name. */
const HOME_TLD = /\.(com|us|org|net|co|io|app|shop|store)$/;

/** A result counts only when it names the same business: the bank's name starts with the brand, has every word of it,
 *  and adds nothing but a store or location code (three letters at most, two of them at most). Among results that
 *  count, a .com wins. Strict on purpose — a wrong logo is worse than the category glyph. */
function accept(merchant: string, results: { name: string; domain: string }[]): string | null {
  const m = core(merchant);
  const ok = results.filter((r) => {
    if (!HOME_TLD.test(r.domain)) return false;
    const b = core(r.name);
    if (!b.length || !b.every((w) => m.includes(w)) || !b.includes(m[0])) return false;
    const extra = m.filter((w) => !b.includes(w));
    return extra.length <= 2 && extra.every((w) => w.length <= 3);
  });
  return (ok.find((r) => r.domain.endsWith(".com")) ?? ok[0])?.domain ?? null;
}

async function search(name: string): Promise<{ name: string; domain: string }[] | "stop"> {
  const res = await fetch(`https://api.logo.dev/v2/search?q=${encodeURIComponent(name)}&limit=5`, {
    headers: { Authorization: `Bearer ${env("LOGO_DEV_SECRET_KEY")}` },
  });
  if (res.status === 402 || res.status === 429) return "stop";
  if (!res.ok) return [];
  const body = await res.json() as { data?: { name: string; domain: string }[] };
  return body.data ?? [];
}

/** The logo as a 256px PNG, or null when Logo.dev has none (no generated monogram — the phone has its own glyph). */
async function image(domain: string): Promise<Uint8Array | null | "stop"> {
  const res = await fetch(`https://img.logo.dev/${domain}?token=${env("LOGO_DEV_PUBLISHABLE_KEY")}&size=128&retina=true&format=png&fallback=404`);
  if (res.status === 402 || res.status === 429) return "stop";
  if (!res.ok || !(res.headers.get("content-type") ?? "").startsWith("image/")) return null;
  return new Uint8Array(await res.arrayBuffer());
}

export async function resolveLogos(db: SupabaseClient, limit = PER_RUN): Promise<Record<string, string>> {
  const monthStart = new Date(); monthStart.setUTCDate(1); monthStart.setUTCHours(0, 0, 0, 0);
  const { count } = await db.from("merchant_logos").select("*", { count: "exact", head: true })
    .eq("source", "logo.dev").gte("checked_at", monthStart.toISOString());
  const room = Math.min(limit, PER_MONTH - (count ?? 0));
  if (room <= 0) return { skipped: "monthly cap" };

  const { data: todo, error } = await db.rpc("logo_candidates", { n: room });
  if (error) return { error: error.message };

  // Domains already in the bucket ("Apple" and "Apple Store" share one file).
  const { data: have } = await db.from("merchant_logos").select("domain, logo_url").not("logo_url", "is", null);
  const stored = new Map((have ?? []).map((r: { domain: string; logo_url: string }) => [r.domain, r.logo_url]));

  const out: Record<string, string> = {};
  for (const c of (todo ?? []) as { merchant_key: string; merchant: string }[]) {
    const remember = (domain: string | null, logo_url: string | null) =>
      db.from("merchant_logos").upsert({ merchant_key: c.merchant_key, domain, logo_url, source: "logo.dev", checked_at: new Date().toISOString() });
    if (SKIP.test(c.merchant_key)) { await remember(null, null); out[c.merchant_key] = "skipped"; continue; }

    let domain = known(c.merchant_key);
    if (!domain) {
      const found = await search(c.merchant);
      if (found === "stop") { out._stopped = "logo.dev limit"; break; }
      domain = accept(c.merchant, found);
    }
    if (!domain) { await remember(null, null); out[c.merchant_key] = "no match"; continue; }

    let url = stored.get(domain) ?? null;
    if (!url) {
      const png = await image(domain);
      if (png === "stop") { out._stopped = "logo.dev limit"; break; }
      if (png) {
        const path = `${domain}.png`;
        const up = await db.storage.from("logos").upload(path, png, { contentType: "image/png", upsert: true, cacheControl: "31536000" });
        if (!up.error) { url = `${env("SUPABASE_URL")}/storage/v1/object/public/logos/${path}`; stored.set(domain, url); }
      }
    }
    await remember(domain, url);
    out[c.merchant_key] = url ? domain : `${domain} (no image)`;
  }
  return out;
}
