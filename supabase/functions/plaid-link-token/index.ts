import { json } from "../_shared/env.ts";
import { plaid, PlaidError } from "../_shared/plaid.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { decrypt } from "../_shared/crypto.ts";

// Creates a Link token for the signed-in user. The app hands it to Plaid Link; the public token comes back to plaid-exchange.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const webhook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/plaid-webhook`;
  const { item_id, consent } = await req.json().catch(() => ({})) as { item_id?: string; consent?: boolean };
  try {
    const base: Record<string, unknown> = { user: { client_user_id: user.id }, client_name: "Poise", country_codes: ["US"], language: "en", webhook };
    // OAuth banks (Chase, Discover, …) bounce back through a Universal Link. Only sent once the URI is registered with Plaid.
    const redirect = Deno.env.get("PLAID_REDIRECT_URI"); if (redirect) base.redirect_uri = redirect;
    if (item_id) {
      // Update mode: repair an existing login. The token is bound to the item's access token, so no products list.
      const { data: item } = await admin().from("items").select("access_token_enc").eq("id", item_id).eq("user_id", user.id).single();
      if (!item) return json({ error: "item not found" }, 404);
      base.access_token = await decrypt(item.access_token_enc);
      base.transactions = { days_requested: 730 };       // update mode can pull the longer history too
      // Asking for a product the user didn't grant at link time. Plaid answers ADDITIONAL_CONSENT_REQUIRED until they
      // come back through Link and allow it — which is the only way to get a Chase card's due date.
      if (consent) base.additional_consented_products = ["liabilities"];
    } else {
      base.products = ["transactions"];
      // Consented up front rather than merely optional: a card's due date and statement are what Next 14 is built on,
      // and optional_products leaves banks that support it asking for consent separately later.
      base.optional_products = ["liabilities"];
      base.additional_consented_products = ["liabilities"];
      base.transactions = { days_requested: 730 };       // two years: annual renewals seen twice, Where's year view full
    }
    const res = await plaid<{ link_token: string; expiration: string }>("/link/token/create", base);
    return json({ link_token: res.link_token, expiration: res.expiration });
  } catch (e) {
    if (e instanceof PlaidError) return json({ error: e.code, message: e.message }, 502);
    throw e;
  }
});
