// Vectors for `e.net.policy` (L046): Vaper's own HTTP cache, cookie jar, CORS/CORP/COEP/COOP, CSP, private-network and
// filter-list code (scripts/policy_reference.dart) over random inputs, written as the link fixture
// tests/selfhost/fixtures/link/net_policy. Usage: DART=D:/flutter/bin/dart.bat node scripts/policy_vectors.mjs
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x3c71;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const NOW = 1_800_000_000_000;
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const DAYS_FULL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = (n) => String(n).padStart(2, '0');
function dateText(ms, style) {
  const d = new Date(ms);
  const wd = (d.getUTCDay() + 6) % 7;
  const hms = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
  if (style === 0) return `${DAYS[wd]}, ${pad(d.getUTCDate())} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()} ${hms} GMT`;
  if (style === 1) return `${DAYS_FULL[wd]}, ${pad(d.getUTCDate())}-${MONTHS[d.getUTCMonth()]}-${d.getUTCFullYear()} ${hms} GMT`;
  if (style === 2) return `${DAYS[wd]} ${MONTHS[d.getUTCMonth()]} ${String(d.getUTCDate()).padStart(2, ' ')} ${hms} ${d.getUTCFullYear()}`;
  if (style === 3) return `${DAYS[wd].toLowerCase()}, ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()].toUpperCase()} ${d.getUTCFullYear()} ${hms} gmt`;
  return pick(['not a date', 'Sun, 06 Nov 1994 08:49:37 UTC', ' Sun, 06 Nov 1994 08:49:37 GMT', 'Sun Nov 6 1994', '2026-01-01T00:00:00Z', '']);
}

const cases = [];
const add = (c) => cases.push(c);

const CC = [undefined, 'max-age=60', 'max-age=0', 'max-age=-5', 'max-age=abc', 'no-cache', 'no-store', 'must-revalidate', 'max-age=60, must-revalidate', 'public, max-age=3600',
  's-maxage=120, max-age=10', 'S-MAXAGE=30', 'no-cache, max-age=5', 'max-age="45"', 'max-age=0x10', ' max-age = 30 ', 'stale-if-error=600', 'max-age=10, stale-if-error=100', 'must-revalidate, stale-if-error=5', 'private', 'max-age=1e3', 'immutable, max-age=99999999999999999999'];
function headers(base) {
  const h = {};
  const cc = pick(CC);
  if (cc !== undefined) h['cache-control'] = cc;
  if (chance(0.35)) h.expires = dateText(base + (int(10) - 3) * 100000, int(5));
  if (chance(0.5)) h.date = dateText(base - int(5) * 1000, int(4));
  if (chance(0.4)) h['last-modified'] = dateText(base - (1 + int(300)) * 86400000, int(4));
  if (chance(0.25)) h.etag = pick(['"abc"', 'W/"x"', '']);
  if (chance(0.2)) h.age = pick(['0', '30', '5', 'x', '-4', '99999999999999999999']);
  if (chance(0.15)) h.vary = pick(['Accept-Encoding', 'Cookie', '*', 'Accept, Authorization', '']);
  return h;
}

for (let i = 0; i < 30; i++) add({ op: 'cc', value: chance(0.1) ? null : pick(CC) ?? '' });
for (let i = 0; i < 60; i++) add({ op: 'cacheable', status: pick([200, 203, 301, 308, 410, 404, 500, 204]), headers: headers(NOW) });
for (let i = 0; i < 80; i++) {
  const created = NOW - int(5000) * 1000;
  const now = NOW + int(8) * 100000 - 200000;
  const h = headers(created);
  add({ op: 'freshness', headers: h, created, now });
  if (i % 2 === 0) add({ op: 'age', headers: h, created, now });
  if (i % 2 === 0) add({ op: 'lifetime', headers: h, now });
  if (i % 2 === 1) add({ op: 'heuristic', headers: h, now });
  if (i % 2 === 1) add({ op: 'stale', headers: h, created, now });
}
for (let i = 0; i < 10; i++) add({ op: 'conditional', headers: headers(NOW) });

for (const host of ['localhost', 'LOCALHOST', 'a.localhost', 'example.com', '127.0.0.1', '10.0.0.1', '172.16.0.1', '172.31.255.255', '172.32.0.1', '192.168.1.1', '192.169.1.1', '169.254.1.1', '0.0.0.0', '8.8.8.8',
  '[::1]', '::1', '[fc00::1]', 'fd12::1', '[fe80::1]', 'febf::1', 'fec0::1', '2001:db8::1', '', '1.2.3', '1.2.3.4.5', '256.1.1.1', '01.2.3.4', '0x7f.0.0.1', '+1.2.3.4', 'a.b.c.d', '1..2.3', '127.1', 'LOCALHOST.', 'fe80', 'fcx']) {
  add({ op: 'private', host });
}

const FILTER_LINES = ['! comment', '[Adblock Plus 2.0]', '||ads.example.com^', '||tracker.net^$third-party', '||Example.ORG', '||bad.com/path^', '||wild*.com^', '||[x]^', '@@||allowed.com^', '##.banner', '###ad-slot', 'example.com##.site', '##+js(abort)', '##  .spaced  ', '  ||trim.me^  ', '', '||', '||^', '||dup.com^', '||dup.com^', '##.banner', '/regex/', '##.a, .b'];
for (let i = 0; i < 12; i++) {
  const n = 1 + int(12);
  const text = Array.from({ length: n }, () => pick(FILTER_LINES)).join(pick(['\n', '\r\n']));
  add({ op: 'filters', text });
}

const ORIGINS = ['https://a.example.com', 'http://a.example.com', 'https://b.example.com', 'https://example.com', 'http://localhost:3000', 'https://sub.a.example.com:8443', 'https://other.org', 'https://x.co.uk', 'https://y.co.uk', 'null'];
const URLS = ['https://a.example.com/x', 'https://a.example.com:443/x', 'https://a.example.com:8443/x', 'http://a.example.com/x', 'https://b.example.com/y.js', 'https://cdn.example.com/lib.js',
  'https://cdn.other.org/i.png', 'data:image/png;base64,AAAA', 'https://example.com', 'HTTPS://A.EXAMPLE.COM/z', 'https://sub.a.example.com:8443/q', 'http://localhost:3000/api', 'https://x.co.uk/a', 'not a url', '/relative', 'https://a.example.com:abc/'];
const SRC_TOKENS = ["'self'", "'none'", '*', 'https:', 'http:', 'https://cdn.example.com', 'https://*.example.com', 'https://a.example.com:8443', 'http://localhost:3000', 'https://other.org/path/', 'HTTPS://CDN.OTHER.ORG', "'unsafe-inline'", 'data:', 'example.com', 'https://*.co.uk', ''];
for (let i = 0; i < 50; i++) {
  const parts = [];
  for (const d of ['default-src', 'script-src', 'connect-src', 'img-src', 'style-src', 'font-src', 'frame-src']) {
    if (chance(d === 'default-src' ? 0.6 : 0.35)) parts.push(`${chance(0.1) ? d.toUpperCase() : d} ${Array.from({ length: int(4) }, () => pick(SRC_TOKENS)).join(' ')}`);
  }
  const header = chance(0.05) ? null : parts.join(pick(['; ', ';', ' ; ']));
  add({ op: 'csp', header, doc: pick(['https://a.example.com/page', 'http://localhost:3000/', 'https://sub.a.example.com:8443/p', 'about:blank']), urls: URLS });
}

const NAMES = ['accept', 'Accept-Language', 'content-type', 'Content-Language', 'authorization', 'x-custom', 'Range', 'X-Req', 'content-length'];
const VALUES = ['text/plain', 'application/json', 'multipart/form-data; boundary=x', 'APPLICATION/X-WWW-FORM-URLENCODED', 'en', 'Bearer t', 'v', 'a'.repeat(129), 'a'.repeat(128), '*/*'];
for (let i = 0; i < 24; i++) add({ op: 'safelisted', name: pick(NAMES), value: pick(VALUES) });
for (let i = 0; i < 24; i++) {
  const h = {};
  for (let k = 0; k < int(5); k++) h[pick(NAMES)] = pick(VALUES);
  add({ op: 'unsafe', headers: h });
  add({ op: 'simple', method: pick(['GET', 'post', 'HEAD', 'PUT', 'delete', 'OPTIONS']), headers: h });
}
const ACAO = [undefined, '*', 'https://a.example.com', 'https://a.example.com/', 'HTTPS://A.EXAMPLE.COM', 'https://b.example.com', 'null', ' https://a.example.com ', 'a.example.com', ''];
function corsHeaders() {
  const h = {};
  const o = pick(ACAO);
  if (o !== undefined) h['access-control-allow-origin'] = o;
  if (chance(0.5)) h['access-control-allow-credentials'] = pick(['true', 'false', ' true ', 'TRUE']);
  if (chance(0.6)) h['access-control-allow-methods'] = pick(['GET, POST', 'PUT,DELETE', '*', 'put', '', ' , ']);
  if (chance(0.6)) h['access-control-allow-headers'] = pick(['content-type', 'X-Custom, Authorization', '*', 'AUTHORIZATION', '', 'x-req,x-custom']);
  if (chance(0.4)) h['access-control-max-age'] = pick(['600', '0', '-1', 'abc', '99999', ' 30 ']);
  return h;
}
for (let i = 0; i < 40; i++) add({ op: 'response', origin: pick(ORIGINS), headers: corsHeaders(), credentialed: chance(0.4) });
for (let i = 0; i < 50; i++) {
  add({
    op: 'preflight', origin: 'https://a.example.com', method: pick(['PUT', 'delete', 'GET', 'patch', 'POST']),
    unsafe: Array.from({ length: int(4) }, () => pick(['content-type', 'x-custom', 'authorization', 'x-req'])).filter((v, k, a) => a.indexOf(v) === k).sort(),
    status: pick([200, 204, 200, 403, 500, 301]), headers: corsHeaders(), credentialed: chance(0.35),
  });
}
for (const url of URLS.concat(['ftp://h/x', 'https://[::1]:9000/', 'http://user:pw@h.com:8080/p', 'https://h.com:443', 'https://h.com:444'])) add({ op: 'serialize', url });
const CORP = [null, 'same-origin', 'same-site', 'cross-origin', 'SAME-SITE', 'bogus', ' cross-origin '];
for (let i = 0; i < 50; i++) {
  const docs = [null, 'https://a.example.com', 'http://a.example.com', 'https://b.example.com', 'https://x.co.uk', 'https://other.org'];
  add({ op: 'corp', doc: pick(docs), url: pick(URLS.filter((u) => !u.startsWith('not') && !u.startsWith('/') && !u.includes(':abc'))), corp: pick(CORP), requires: chance(0.4) });
}
for (let i = 0; i < 40; i++) {
  const h = corsHeaders();
  const corp = pick(CORP);
  if (corp !== null) h['cross-origin-resource-policy'] = corp;
  add({ op: 'nocors', doc: pick([null, 'https://a.example.com', 'https://other.org']), url: pick(URLS.filter((u) => u.startsWith('http'))).replace(':abc', ''), headers: h, requires: chance(0.5) });
}
for (const value of [null, 'same-origin', 'require-corp', 'credentialless', 'same-origin-allow-popups', 'cross-origin', 'same-site', ' REQUIRE-CORP ', 'x', '']) add({ op: 'parse', value });

for (let i = 0; i < 10; i++) {
  const steps = [];
  let t = 1_000_000;
  for (let k = 0; k < 10; k++) {
    t += pick([0, 1000, 4000, 10000, 700000, 8000000]);
    const origin = pick(ORIGINS.slice(0, 4));
    const url = pick(['https://api.example.com/v1', 'https://api.example.com/v2?x=1', 'HTTPS://API.EXAMPLE.COM/v1', 'https://other.org/z']);
    const credentialed = chance(0.3);
    const r = int(4);
    if (r === 0) steps.push({ k: 'store', t, origin, url, headers: corsHeaders(), credentialed });
    else if (r === 3) steps.push({ k: 'size', t });
    else steps.push({ k: 'allowed', t, origin, url, method: pick(['PUT', 'GET', 'delete']), unsafe: pick([[], ['x-custom'], ['authorization'], ['content-type', 'x-custom']]), credentialed });
  }
  add({ op: 'pcache', steps });
}

const HOSTS = ['https://www.example.com', 'https://api.example.com', 'http://example.com', 'https://example.com', 'https://shop.example.co.uk', 'https://other.org', 'https://192.168.1.5', 'https://[::1]:8443', 'https://localhost'];
const COOKIES = ['sid=abc123', 'sid=abc; Path=/', 'a=1; Secure', 'b=2; HttpOnly; SameSite=None', 'c=3; SameSite=None; Secure', 'd=4; SameSite=Strict', 'e=5; Domain=example.com', 'f=6; Domain=.example.com; Path=/app',
  'g=7; Domain=other.org', 'h=8; Max-Age=3600', 'i=9; Max-Age=0', 'j=10; Max-Age=-1', 'k=11; Expires=Wed, 21 Oct 2099 07:28:00 GMT', 'l=12; Expires=Wed, 21 Oct 2001 07:28:00 GMT', 'm=13; Expires=Wed, 21 Oct 2099 07:28:00 GMT; Max-Age=0',
  '__Host-n=14; Secure; Path=/', '__Host-o=15; Secure', '__Host-p=16; Secure; Path=/; Domain=example.com', '__Secure-q=17; Secure', '__Secure-r=18', 's=19; Partitioned; Secure', 't=20; Partitioned', 'u=21; Domain=com', '=novalue', 'noequals',
  'v=22; Path=nope', 'w=23; Path=/a/b', 'x=24; max-age=abc', 'y=25; Expires=garbage', 'z=26; Expires=Sun, 06 Nov 2099 08:49:37 GMT; Max-Age=3600', 'A=27;  Secure ;  HttpOnly', 'B=28; SameSite=Lax', 'C=29; SameSite=bogus'];
for (let i = 0; i < 40; i++) {
  const steps = [];
  const block = chance(0.7);
  const site = pick(['https://www.example.com', 'https://api.example.com', 'https://example.com', 'https://shop.example.co.uk', 'https://other.org']);
  const sitePk = pick(['https://example.com', 'https://other.org', 'https://example.co.uk']);
  const n = 6 + int(8);
  for (let k = 0; k < n; k++) {
    const url = (chance(0.75) ? site : pick(HOSTS)) + pick(['', '/', '/', '/app', '/app/x', '/a/b/c', '/other']);
    const pk = chance(0.5) ? (chance(0.6) ? sitePk : pick(['https://example.com', 'https://other.org', 'http://example.com', 'https://example.co.uk'])) : null;
    const r = int(10);
    if (r < 5 || (k < 3 && r < 8)) {
      const joined = chance(0.2) ? `${pick(COOKIES)}, ${pick(COOKIES)}` : pick(COOKIES);
      steps.push({ k: 'set', url, header: joined, pk });
    } else if (r < 9) steps.push({ k: 'get', url, top: chance(0.5), pk });
    else if (r === 9 && chance(0.5)) steps.push({ k: 'key', url });
    else steps.push({ k: chance(0.5) ? 'clearOrigin' : 'clear', host: pick(['example.com', 'www.example.com', 'other.org']) });
  }
  add({ op: 'jar', block, steps });
}
{
  // per-domain cap and eviction order
  const steps = [];
  for (let k = 0; k < 60; k++) steps.push({ k: 'set', url: 'https://www.example.com/', header: `n${k}=v${k}${k % 7 === 0 ? '; Secure' : ''}`, pk: null });
  steps.push({ k: 'get', url: 'https://www.example.com/', top: true, pk: null });
  add({ op: 'jar', block: true, steps });
}

const tmp = join(tmpdir(), 'policy_vectors');
mkdirSync(tmp, { recursive: true });
writeFileSync(join(tmp, 'in.json'), JSON.stringify(cases));
execFileSync(process.env.DART || 'dart', ['run', resolve(here, 'policy_reference.dart'), join(tmp, 'in.json'), join(tmp, 'out.json')], { stdio: 'inherit', shell: true });
const answers = JSON.parse(readFileSync(join(tmp, 'out.json'), 'utf8'));
const lines = [];
let dropped = 0;
cases.forEach((c, i) => {
  if (answers[i].x !== undefined) { dropped++; return; }
  lines.push(JSON.stringify({ ...c, e: answers[i].v }));
});
const chunks = [];
const size = 10;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'policy_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/net_policy/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${lines.length} cases (${dropped} dropped: the reference threw) in ${chunks.length} chunks -> net_policy`);
