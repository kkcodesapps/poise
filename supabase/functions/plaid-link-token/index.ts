import { json } from "../_shared/env.ts";
import { plaid, PlaidError } from "../_shared/plaid.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { decrypt } from "../_shared/crypto.ts";

// Creates a Link token for the signed-in user. The app hands it to Plaid Link; the public token comes back to plaid-exchange.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const webhook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/plaid-webhook`;
  const { item_id } = await req.json().catch(() => ({})) as { item_id?: string };
  try {
    const base: Record<string, unknown> = { user: { client_user_id: user.id }, client_name: "Poise", country_codes: ["US"], language: "en", webhook };
    // OAuth banks (Chase, Discover, …) bounce back through a Universal Link. Only sent once the URI is registered with Plaid.
    const redirect = Deno.env.get("PLAID_REDIRECT_URI"); if (redirect) base.redirect_uri = redirect;
    if (item_id) {
      // Update mode: repair an existing login. The token is bound to the item's access token, so no products list.
      const { data: item } = await admin().from("items").select("access_token_enc").eq("id", item_id).eq("user_id", user.id).single();
      if (!item) return json({ error: "item not found" }, 404);
      base.access_token = await decrypt(item.access_token_enc);
    } else {
      base.products = ["transactions"];
      base.transactions = { days_requested: 90 };
    }
    const res = await plaid<{ link_token: string; expiration: string }>("/link/token/create", base);
    return json({ link_token: res.link_token, expiration: res.expiration });
  } catch (e) {
    if (e instanceof PlaidError) return json({ error: e.code, message: e.message }, 502);
    throw e;
  }
});
