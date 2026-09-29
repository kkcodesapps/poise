import { json } from "../_shared/env.ts";
import { admin, userFrom } from "../_shared/db.ts";
import { applyWallet, ensureWalletItem, type WalletPayload } from "../_shared/wallet.ts";

// Receives what the app read from Wallet (Apple Card, Apple Cash, Savings) and stores it like any other bank's rows.
// The phone walks FinanceKit's change history and sends batches: accounts + balances first, then transaction changes.
Deno.serve(async (req) => {
  const user = await userFrom(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => null) as WalletPayload | null;
  if (!body || typeof body !== "object") return json({ error: "payload required" }, 400);
  const db = admin();
  const item = await ensureWalletItem(db, user.id);
  const totals = await applyWallet(db, item, body);
  return json({ item_id: item.id, ...totals });
});
