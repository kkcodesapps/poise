#!/usr/bin/env node
// Mints the iOS profiles through the App Store Connect API and installs them in ~/Library/MobileDevice/Provisioning
// Profiles: development ("Poise Dev", "Poise Widgets Dev", "Poise Finance Dev" — every enabled device) and App Store
// ("Poise Dist", "Poise Widgets Dist", "Poise Finance Dist"). Needs the ASC key at ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
// and node 18+. Re-run after adding a device or a capability; each run replaces the same-named profiles.
const crypto = require('crypto'), fs = require('fs'), os = require('os'), path = require('path');
const { call } = require('./asc.js');
const IDS = [['Poise', 'com.koliokolev.poise'], ['Poise Widgets', 'com.koliokolev.poise.widgets'], ['Poise Finance', 'com.koliokolev.poise.finance']];
const PROFILES = IDS.flatMap(([n, id]) => [[`${n} Dev`, id, 'IOS_APP_DEVELOPMENT', 'DEVELOPMENT'], [`${n} Dist`, id, 'IOS_APP_STORE', 'DISTRIBUTION']]);
// App IDs registered on demand. Capabilities that the API can't switch on (FinanceKit) are enabled by hand in the portal.
const NAMES = { 'com.koliokolev.poise.finance': 'Poise Finance' };

(async () => {
  const certs = (await call('GET', '/certificates?limit=50')).json.data;
  const local = require('child_process').execSync('security find-identity -v -p codesigning', { encoding: 'utf8' });
  // The certificate for each profile type is the one whose private key lives in this Mac's keychain.
  const certFor = (type) => certs.find((c) => c.attributes.certificateType === type && local.includes(crypto.createHash('sha1').update(Buffer.from(c.attributes.certificateContent, 'base64')).digest('hex').toUpperCase()));
  const devices = (await call('GET', '/devices?filter%5Bplatform%5D=IOS&filter%5Bstatus%5D=ENABLED&limit=50')).json.data.map((d) => d.id);
  const bundleIds = (await call('GET', '/bundleIds?limit=100')).json.data;
  for (const [, identifier] of PROFILES) {
    if (bundleIds.some((b) => b.attributes.identifier === identifier)) continue;
    const { status, json } = await call('POST', '/bundleIds', { data: { type: 'bundleIds', attributes: { identifier, name: NAMES[identifier] ?? identifier, platform: 'IOS' } } });
    if (status === 201) { bundleIds.push(json.data); console.log(`registered App ID ${identifier}`); } else console.error(identifier, 'not registered', JSON.stringify(json.errors));
  }
  const existing = (await call('GET', '/profiles?limit=100')).json.data;
  const dir = path.join(os.homedir(), 'Library', 'MobileDevice', 'Provisioning Profiles');
  fs.mkdirSync(dir, { recursive: true });
  // Drop stale local copies with the same names, or Xcode may pick an older one.
  for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.mobileprovision'))) {
    const plist = require('child_process').execSync(`security cms -D -i "${path.join(dir, f)}"`, { encoding: 'utf8' });
    if (PROFILES.some(([name]) => plist.includes(`<string>${name}</string>`))) fs.unlinkSync(path.join(dir, f));
  }
  for (const [name, identifier, profileType, certType] of PROFILES) {
    const bid = bundleIds.find((b) => b.attributes.identifier === identifier);
    if (!bid) { console.error(`bundle id ${identifier} not registered`); continue; }
    const cert = certFor(certType);
    if (!cert) { console.error(`${name}: no ${certType.toLowerCase()} certificate on this Mac matches App Store Connect`); continue; }
    for (const p of existing.filter((p) => p.attributes.name === name)) await call('DELETE', `/profiles/${p.id}`);
    const relationships = { bundleId: { data: { type: 'bundleIds', id: bid.id } }, certificates: { data: [{ type: 'certificates', id: cert.id }] } };
    if (profileType === 'IOS_APP_DEVELOPMENT') relationships.devices = { data: devices.map((id) => ({ type: 'devices', id })) };
    const { status, json } = await call('POST', '/profiles', { data: { type: 'profiles', attributes: { name, profileType }, relationships } });
    if (status !== 201) { console.error(name, 'failed', JSON.stringify(json.errors)); continue; }
    const a = json.data.attributes;
    fs.writeFileSync(path.join(dir, `${a.uuid}.mobileprovision`), Buffer.from(a.profileContent, 'base64'));
    console.log(`${name}: ${a.uuid} (expires ${a.expirationDate.slice(0, 10)}${profileType === 'IOS_APP_DEVELOPMENT' ? `, ${devices.length} devices` : ''})`);
  }
})();
