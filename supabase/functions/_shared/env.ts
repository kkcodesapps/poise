export function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing environment variable ${name}`);
  return v;
}

export const plaidBase = () => {
  const e = Deno.env.get("PLAID_ENV") ?? "sandbox";
  return e === "production" ? "https://production.plaid.com" : "https://sandbox.plaid.com";
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
