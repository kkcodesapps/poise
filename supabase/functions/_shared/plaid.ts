import { env, plaidBase } from "./env.ts";

/** Minimal Plaid client: every call is a POST with client_id + secret merged in. */
export async function plaid<T = Record<string, unknown>>(path: string, body: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${plaidBase()}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_id: env("PLAID_CLIENT_ID"), secret: env("PLAID_SECRET"), ...body }),
  });
  const data = await res.json();
  if (!res.ok) {
    const err = data as { error_code?: string; error_message?: string };
    throw new PlaidError(err.error_code ?? "UNKNOWN", err.error_message ?? res.statusText, res.status);
  }
  return data as T;
}

export class PlaidError extends Error {
  constructor(public code: string, message: string, public status: number) {
    super(`${code}: ${message}`);
  }
}

export interface PlaidAccount {
  account_id: string;
  name: string;
  official_name?: string | null;
  mask?: string | null;
  type: string;
  subtype?: string | null;
  balances: { available?: number | null; current?: number | null; limit?: number | null; iso_currency_code?: string | null };
}

export interface PlaidTransaction {
  transaction_id: string;
  account_id: string;
  amount: number; // Plaid: positive = money leaving the account
  iso_currency_code?: string | null;
  date: string;
  authorized_date?: string | null;
  name: string;
  merchant_name?: string | null;
  pending: boolean;
  pending_transaction_id?: string | null;
  personal_finance_category?: { primary: string; detailed: string } | null;
}

export interface SyncResponse {
  accounts: PlaidAccount[];
  added: PlaidTransaction[];
  modified: PlaidTransaction[];
  removed: { transaction_id: string; account_id?: string }[];
  next_cursor: string;
  has_more: boolean;
}
