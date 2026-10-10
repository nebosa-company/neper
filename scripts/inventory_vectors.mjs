// Vectors for `x.ops.inventory` (L050): Petcow's own facts.rs, inventory.rs and naming.rs::sanitize (extracted unchanged
// into `factsref.exe` behind a thin `ObservedResource` shim) over random fact output, inventory documents and observed
// resources, written as the link fixture tests/selfhost/fixtures/link/x_ops_inventory.
// Usage: node scripts/inventory_vectors.mjs REFERENCE_EXE
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x4c19;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const cases = [];
const add = (c) => cases.push(c);

const FACT_LINES = ['os=Linux', 'arch=x86_64', 'cpus=4', 'cpus=0', 'hostname=web-01', 'kernel=6.1.0', 'k=a=b=c', ' spaced = value ', 'nonsense line', '', '   ', '=novalue', 'empty=', 'n=-5', 'n=+7', 'big=9223372036854775807', 'over=9223372036854775808',
  'neg=-9223372036854775808', 'f=1.5', 'hex=0x10', 'e=1e3', 'dup=1', 'dup=two', 'distro=ubuntu', 'distro_version=22.04', 'ünï=värde', 'tab\tkey=v', 'z=007'];
for (let i = 0; i < 40; i++) {
  const n = 1 + int(10);
  const eol = pick(['\n', '\r\n']);
  add({ op: 'parseFacts', stdout: Array.from({ length: n }, () => pick(FACT_LINES)).join(eol) + pick(['', eol]) });
}
for (let i = 0; i < 8; i++) {
  const facts = {};
  for (let k = 0; k < int(4); k++) facts[pick(['datacenter', 'owner', 'zone', 'a', 'B'])] = pick(['cat /etc/dc', 'uname -r', 'echo "x y"']);
  add({ op: 'customScript', facts });
}
for (const token of ['MyVPC', 'a__b!!c', 'subnet[0]', 'foo.bar/baz', '[0]', '!!hi!!', '---', '', 'café', 'UPPER-lower-123', 'a b  c', 'x', '-', 'ünï']) add({ op: 'sanitize', token });

function inventory() {
  const groupNames = ['web', 'prod', 'staging', 'db'];
  const doc = { hosts: {}, groups: {} };
  for (let i = 0; i < 1 + int(5); i++) {
    const h = { address: pick(['10.0.0.5', 'web.example', '2001:db8::1']) };
    if (chance(0.7)) h.groups = Array.from({ length: int(3) }, () => pick(groupNames));
    if (chance(0.6)) h.vars = Object.fromEntries(Array.from({ length: int(3) }, () => [pick(['role', 'http_port', 'env', 'ssh_user']), pick(['frontend', 443, 'production', true, 'u', 8080, null])]));
    doc.hosts[pick(['web1', 'web2', 'db1', 'cache', 'Zed', 'alpha', 'b'])] = h;
  }
  for (const g of groupNames) if (chance(0.5)) doc.groups[g] = chance(0.8) ? { vars: Object.fromEntries(Array.from({ length: int(3) }, () => [pick(['http_port', 'env', 'tier', 'ssh_user']), pick([80, 443, 'production', 'x', false]) ])) } : {};
  if (chance(0.3)) doc.dynamic = [{ cloud: 'aws', type: 'aws.ec2_instance', address_from: 'private_ip', group: 'cloud', group_from_tag: 'role' }];
  if (chance(0.1)) doc.extra = 1;
  if (chance(0.05)) doc.hosts = { bad: { groups: ['x'] } };
  return doc;
}
for (let i = 0; i < 24; i++) {
  const yaml = JSON.stringify(inventory());
  add({ op: 'resolve', yaml });
  const c = { op: 'select', yaml };
  if (chance(0.7)) c.group = pick(['web', 'prod', 'db', 'none']);
  if (chance(0.5)) { c.varKey = pick(['http_port', 'env', 'role']); c.varValue = pick(['443', 'production', 'frontend', 'true', '80', '']); }
  add(c);
}
for (const y of ['hosts: 5', '[1]', '{"hosts": {"a": {"address": "x", "bogus": 1}}}', '{"groups": {"g": {"vars": {}, "x": 1}}}', '{"dynamic": [{"cloud": "aws"}]}', '{"hosts": {"a": {"address": "x"}}}']) add({ op: 'resolve', yaml: y });

const TYPES = ['aws.ec2_instance', 'gcp.compute_instance', 'Azure VM!', 'x'];
for (let i = 0; i < 24; i++) {
  const source = { cloud: 'aws', type: pick(TYPES) };
  if (chance(0.5)) source.address_from = pick(['private_ip', 'public_ip', 'missing']);
  if (chance(0.5)) source.group = pick(['cloud', 'Linux Hosts']);
  if (chance(0.5)) source.group_from_tag = pick(['role', 'env', 'absent']);
  const observed = Array.from({ length: 1 + int(5) }, () => {
    const attributes = {};
    if (chance(0.8)) attributes.private_ip = pick(['10.0.0.1', '10.0.0.2', 7]);
    if (chance(0.5)) attributes.public_ip = '1.2.3.4';
    if (chance(0.6)) attributes.tags = pick([{ role: 'Web Tier', env: 'prod', n: 5 }, { role: 'db' }, 'str', []]);
    if (chance(0.4)) attributes.size = pick(['t3.micro', 3, true, { nested: 1 }, [1]]);
    if (chance(0.2)) attributes.role = 'attr-role';
    const o = { name: pick(['petcow-a', 'petcow-b', 'petcow-c', 'host-d']), type: source.type, attributes };
    if (chance(0.6)) o.realId = pick(['i-0123', 'arn:aws:x']);
    return o;
  });
  add({ op: 'synthesize', source, observed });
}

const exe = process.argv[2] || 'D:/temp/factsref/factsref.exe';
const answers = JSON.parse(execFileSync(exe, [], { input: JSON.stringify(cases), maxBuffer: 1 << 28 }).toString());
const bs = String.fromCharCode(92);
const lines = cases.map((c, i) => JSON.stringify({ ...c, e: answers[i] }));
const chunks = [];
for (let i = 0; i < lines.length; i += 8) {
  chunks.push('"' + lines.slice(i, i + 8).map((l) => l.split(bs).join(bs + bs).split('"').join(bs + '"')).join(bs + 'n') + bs + 'n"');
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'inventory_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_ops_inventory/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_ops_inventory`);
