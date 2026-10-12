// App Store Connect API, the small part the tools need: a signed token from the key in ~/.appstoreconnect/private_keys
// and a `call(method, path, body)` that returns { status, json }. Shared by profiles.js and whatsnew.js.
const crypto = require('crypto'), fs = require('fs'), os = require('os'), path = require('path');

const ISSUER = process.env.ASC_ISSUER_ID || 'f7b84198-2497-4bd0-9756-251815113d7a';
const keyDir = path.join(os.homedir(), '.appstoreconnect', 'private_keys');
const keyFile = fs.readdirSync(keyDir).find((f) => /^AuthKey_.*\.p8$/.test(f));
if (!keyFile) { console.error('no AuthKey_*.p8 in ~/.appstoreconnect/private_keys'); process.exit(1); }
const KID = keyFile.replace(/^AuthKey_|\.p8$/g, '');
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${b64({ alg: 'ES256', kid: KID, typ: 'JWT' })}.${b64({ iss: ISSUER, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })}`;
const sig = crypto.sign('sha256', Buffer.from(unsigned), { key: fs.readFileSync(path.join(keyDir, keyFile)), dsaEncoding: 'ieee-p1363' });
const JWT = `${unsigned}.${sig.toString('base64url')}`;
const API = 'https://api.appstoreconnect.apple.com/v1';

async function call(method, p, body) {
  const res = await fetch(API + p, { method, headers: { Authorization: `Bearer ${JWT}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, json: res.status === 204 ? {} : await res.json() };
}
module.exports = { call, KID, ISSUER };
