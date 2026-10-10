// Vectors for `e.net.ssrf` (L046): Appdor's own src/io/ssrf-guard.js over URL forms (WHATWG host normalisation: integer,
// hex and octal IPv4, mapped IPv6), literal addresses and injected resolver answers, written as the link fixture
// tests/selfhost/fixtures/link/net_ssrf. Usage: node scripts/ssrf_vectors.mjs   (APPDOR_DIR defaults to D:/repos/appdor)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const g = await import(pathToFileURL(resolve(appdor, 'src/io/ssrf-guard.js')).href);

const URLS = ['http://127.0.0.1/', 'http://2130706433/', 'http://0x7f.1/', 'http://0177.0.0.1', 'http://[::1]:8080/', 'http://[::ffff:127.0.0.1]/', 'http://[::ffff:7f00:1]/', 'http://[fe80::1]', 'http://[fd00::1]/',
  'http://[2001:db8::1]/', 'http://10.0.0.5', 'http://100.64.0.1', 'http://100.128.0.1', 'http://172.15.0.1', 'http://172.16.5.5', 'http://172.32.0.1', 'http://192.0.0.9', 'http://198.18.1.1', 'http://198.19.255.255', 'http://198.20.1.1',
  'http://224.0.0.1', 'http://240.0.0.1', 'http://8.8.8.8', 'https://example.com', 'http://meta:8080/query', 'http://db', 'http://metadata.google.internal/', 'http://a.metadata.google.internal', 'http://localhost',
  'http://x.localhost', 'http://LOCALHOST:80', 'ftp://example.com', 'file:///etc/passwd', 'javascript:alert(1)', 'not a url', '', 'http://', 'http://user:pw@example.com:8080/p', 'http://example.com:99999',
  'http://exa mple.com', 'HTTP://EXAMPLE.COM', 'http://1.2.3', 'http://1.2.3.4.5', 'http://999.1.1.1', 'http://[::]', 'http://0.0.0.0', 'http://[0:0:0:0:0:ffff:7f00:1]', 'http://example.com./', 'http://1.2.3.4.',
  'http://0x10', 'http://%31%32%37.0.0.1', 'http://[2001:0db8:0000:0000:0000:0000:0000:0001]', 'http://[1:0:0:2:0:0:0:3]', 'http://[::ffff:10.1.2.3]', 'http://[::ffff:8.8.8.8]', 'http://[fe80::1%25eth0]',
  'http://169.254.169.254/latest/meta-data', 'http://[fec0::1]', 'https://api.example.org/v1?x=1#f', 'http://0', 'http://4294967295', 'http://4294967296', 'http://1.1.1.256', 'http://[::ffff:1:2]', 'http://[1::]', 'http://[::1.2.3.4]'];
const LOOKUPS = [null, ['93.184.216.34'], ['10.0.0.1'], ['8.8.8.8', '127.0.0.1'], [], 'throw', ['::ffff:10.0.0.1'], ['2606:4700::1111'], ['fe80::1'], ['100.64.0.9']];

const cases = [];
const add = (c) => cases.push(c);
const shape = (r) => (r.ok ? { ok: true, hostname: r.url ? r.url.hostname : r.host, addresses: r.addresses ?? null, resolved: r.resolved === false ? false : true } : { ok: false, error: r.error });

for (const url of URLS) {
  add({ op: 'sync', url, e: shape(g.checkOutboundUrlSync(url)) });
}
for (const url of URLS) {
  for (const lookup of [pick(LOOKUPS), pick(LOOKUPS)]) {
    const fn = lookup === null ? undefined : lookup === 'throw' ? async () => { throw new Error('x'); } : async () => lookup;
    const r = await g.checkOutboundUrl(url, { lookup: fn });
    add({ op: 'full', url, lookup: lookup === null ? { present: false } : lookup === 'throw' ? { present: true, failed: true, answers: [] } : { present: true, failed: false, answers: lookup }, e: shape(r) });
  }
}
const ADDRS = ['127.0.0.1', '10.1.2.3', '8.8.8.8', '1.1.1.1', '::1', '::', 'fe80::1', 'FD00::1', '[::1]', ' 8.8.8.8 ', '::ffff:127.0.0.1', '::ffff:7f00:1', '::ffff:808:808', '2001:db8::1', '', '1.2.3', 'abc', '256.1.1.1', '100.100.100.100', '198.51.100.7', '203.0.113.9', '239.255.255.255', '255.255.255.255', 'fc00::', 'fe00::1', 'febf::1', 'fec0::1', '::ffff:1:2:3'];
for (const ip of ADDRS) add({ op: 'addr', ip, e: { blocked: g.isBlockedAddress(ip), reason: g.blockReason(ip) } });

function pick(a) { return a[Math.floor(Math.random() * 0 + (cases.length * 7 + a.length * 3) % a.length)]; }

const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
for (let i = 0; i < lines.length; i += 10) {
  chunks.push(`"${lines.slice(i, i + 10).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'ssrf_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/net_ssrf/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> net_ssrf`);
