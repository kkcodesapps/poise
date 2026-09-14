import { json } from "../_shared/env.ts";
import { plaid, PlaidError } from "../_shared/plaid.ts";
import { userFrom } from "../_shared/db.ts";

// Creates a Link token for the signed-in user. The app hands it to Plaid Link; the public token comes back to plaid-exchange.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const webhook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/plaid-webhook`;
  try {
    const res = await plaid<{ link_token: string; expiration: string }>("/link/token/create", {
      user: { client_user_id: user.id },
      client_name: "Poise",
      products: ["transactions"],
      country_codes: ["US"],
      language: "en",
      webhook,
      transactions: { days_requested: 90 },
    });
    return json({ link_token: res.link_token, expiration: res.expiration });
  } catch (e) {
    if (e instanceof PlaidError) return json({ error: e.code, message: e.message }, 502);
    throw e;
  }
});
