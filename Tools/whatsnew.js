#!/usr/bin/env node
// After an upload: waits for App Store Connect to process the build, then sets its TestFlight "What to Test" text from
// the matching CHANGELOG.md section. Run by Tools/testflight.sh; by hand: node Tools/whatsnew.js <version> <build>.
const fs = require('fs');
const { call } = require('./asc.js');

const [version, build] = process.argv.slice(2);
if (!version || !build) { console.error('usage: whatsnew.js <version> <build>'); process.exit(1); }
const APP = '6813939754';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The bullet list under "## <version>" in CHANGELOG.md, as plain text (TestFlight has no markdown). */
function notes() {
  const lines = fs.readFileSync('CHANGELOG.md', 'utf8').split('\n');
  const start = lines.findIndex((l) => l.startsWith(`## ${version}`));
  if (start < 0) return `Poise ${version} (${build})`;
  const section = [];
  for (const l of lines.slice(start + 1)) { if (l.startsWith('## ')) break; section.push(l); }
  const body = section.map((l) => l.replace(/^\s*[-*]\s+/, '• ').replace(/\*\*/g, '').trim()).filter(Boolean).join('\n');
  return body || `Poise ${version} (${build})`;
}

(async () => {
  let found = null;
  for (let i = 0; i < 60 && !found; i++) {   // up to 30 minutes
    const r = await call('GET', `/builds?filter%5Bapp%5D=${APP}&filter%5Bversion%5D=${build}&limit=1`);
    const b = r.json.data?.[0];
    if (b && b.attributes.processingState !== 'PROCESSING') found = b;
    else { if (i === 0) process.stdout.write('waiting for App Store Connect to process the build'); process.stdout.write('.'); await sleep(30_000); }
  }
  if (!found) { console.log('\nstill processing — set What to Test later with: node Tools/whatsnew.js', version, build); process.exit(0); }
  if (found.attributes.processingState !== 'VALID') { console.log(`\nbuild ${build} is ${found.attributes.processingState}`); process.exit(1); }
  const text = notes();
  const existing = (await call('GET', `/builds/${found.id}/betaBuildLocalizations`)).json.data?.find((l) => l.attributes.locale === 'en-US');
  const r = existing
    ? await call('PATCH', `/betaBuildLocalizations/${existing.id}`, { data: { type: 'betaBuildLocalizations', id: existing.id, attributes: { whatsNew: text } } })
    : await call('POST', '/betaBuildLocalizations', { data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: text }, relationships: { build: { data: { type: 'builds', id: found.id } } } } });
  if (r.status >= 300) { console.error('\nWhat to Test not set:', JSON.stringify(r.json.errors)); process.exit(1); }
  console.log(`\nBuild ${build} processed — What to Test set for ${version}:\n${text}`);
})();
