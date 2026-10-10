// Vectors for `x.identity.scim` (L045): Appdor's own src/identity/scim-protocol.js over random SCIM resources, filters,
// PATCH operations, projections, list parameters and sorts, written as the link fixture
// tests/selfhost/fixtures/link/x_identity_scim. Usage: node scripts/scim_vectors.mjs   (APPDOR_DIR defaults to D:/repos/appdor)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const scim = await import(pathToFileURL(resolve(appdor, 'src/identity/scim-protocol.js')).href);

let seed = 0x5c1d;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const norm = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

const NAMES = ['alice@acme.com', 'Bob@Example.org', 'carol', 'dave smith', 'érin', 'frank@acme.com'];
function resource(i) {
  const r = { id: `id-${i}`, userName: pick(NAMES), active: chance(0.8) };
  if (chance(0.7)) r.name = { givenName: pick(['Ann', 'bob', 'Cy']), familyName: pick(['Lee', 'Roe', 'lee']) };
  if (chance(0.7)) r.emails = Array.from({ length: 1 + int(3) }, () => ({ value: pick(NAMES), type: pick(['work', 'home', 'Work']), primary: chance(0.3) }));
  if (chance(0.4)) r.groups = Array.from({ length: int(3) }, () => ({ value: pick(['g1', 'g2', 'g3']), display: pick(['Admins', 'Staff', 'x']) }));
  if (chance(0.5)) r.age = int(60);
  if (chance(0.3)) r.title = pick(['Engineer', '', 'engineer manager']);
  if (chance(0.15)) r.nick = null;
  if (chance(0.2)) r.meta = { lastModified: pick(['2026-01-01T00:00:00Z', '2026-05-05T10:00:00Z']) };
  if (chance(0.1)) { r.UserName = r.userName; delete r.userName; }
  return r;
}
const resources = () => Array.from({ length: int(6) }, (_, i) => resource(i));

const ATTRS = ['userName', 'UserName', 'emails.value', 'emails.type', 'name.givenName', 'name.familyName', 'active', 'title', 'age', 'id', 'meta.lastModified', 'groups.display', 'nick', 'missing', 'name'];
const VALUES = ['"alice@acme.com"', '"ALICE@ACME.COM"', '"work"', '"Ann"', 'true', 'false', 'null', '30', '"30"', '12.5', '"Admins"', '"a\\"b"', '"x y"', 'word', '"2026-03-01T00:00:00Z"', '""'];
const OPS = ['eq', 'ne', 'co', 'sw', 'ew', 'gt', 'ge', 'lt', 'le', 'EQ', 'Co'];

function leaf() {
  const r = int(10);
  const attr = pick(ATTRS);
  if (r === 0) return `${attr} pr`;
  if (r === 1) return `emails[${pick(['type eq "work"', 'type eq "home" and primary eq true', 'value co "acme"', 'primary pr'])}]${pick(['', '', '.value'])}`;
  return `${attr} ${pick(OPS)} ${pick(VALUES)}`;
}
function filter(depth) {
  if (depth > 2 || chance(0.4)) return leaf();
  const r = int(5);
  if (r === 0) return `${filter(depth + 1)} and ${filter(depth + 1)}`;
  if (r === 1) return `${filter(depth + 1)} or ${filter(depth + 1)}`;
  if (r === 2) return `not (${filter(depth + 1)})`;
  if (r === 3) return `(${filter(depth + 1)})`;
  return `${filter(depth + 1)} AND ${filter(depth + 1)}`;
}
const BROKEN = ['', '   ', 'userName', 'userName eq', 'userName foo "x"', '(userName eq "a"', 'userName eq "a" )', 'emails[type eq "work"', 'and', 'not', '"quoted" eq 1', 'a eq 1 b', '[x]', 'userName pr extra', 'x eq "unterminated', '(', ')', 'a[b eq 1].c.d pr', 'a eq "\\\\"'];

const cases = [];
const add = (c) => cases.push(c);

function astOf(text) {
  const r = scim.parseScimFilter(text);
  return r.ok ? { ok: true, ast: r.ast } : { ok: false, error: r.error };
}

for (let i = 0; i < 90; i++) {
  const text = chance(0.15) ? pick(BROKEN) : filter(0);
  add({ op: 'parse', text, e: norm(astOf(text)) });
}
for (const text of BROKEN) add({ op: 'parse', text, e: norm(astOf(text)) });

for (let i = 0; i < 90; i++) {
  const rs = resources();
  const text = chance(0.1) ? pick(['', ...BROKEN.slice(2, 6)]) : filter(0);
  add({ op: 'filter', resources: rs, text, e: norm(scim.filterResources(rs, text)) });
}

for (let i = 0; i < 40; i++) {
  const r = resource(i);
  const path = pick([...ATTRS, 'emails.value', 'name.givenname', 'groups.value', 'meta', 'name.x.y', '']);
  const v = scim.getAttribute(r, path);
  add({ op: 'attr', resource: r, path, found: v !== undefined, e: v === undefined ? null : norm(v) });
}

const PATHS = [undefined, undefined, 'userName', 'active', 'emails', 'emails[type eq "work"].value', 'emails[type eq "work"]', 'name.givenName', 'name.deep.leaf', 'emails[type eq "home"].primary',
  'bogus[', 'groups[value eq "g1"]', 'title', 'NAME.givenName', 'emails[type eq "work"].value.x', 'emails[type eq]', 'age', 'nick', 'groups'];
for (let i = 0; i < 40; i++) {
  const path = pick(PATHS);
  const r = scim.parsePatchPath(path);
  add({ op: 'patchpath', path: path === undefined ? '' : path, e: norm({ attribute: r.attribute, hasFilter: r.filter !== null, subAttribute: r.subAttribute, error: r.error }) });
}

function operation() {
  const op = pick(['add', 'replace', 'remove', 'replace', 'Replace', 'ADD', 'move', '']);
  const path = pick(PATHS);
  const o = { op };
  if (path !== undefined) o.path = path;
  if (op !== 'remove') {
    if (path === undefined) o.value = pick([{ active: false }, { title: 'Boss', name: { givenName: 'Z' } }, 'str', null]);
    else if (path.includes('[') && !path.includes('].')) o.value = pick([{ primary: true }, { value: 'x@y.z', type: 'work' }]);
    else if (path === 'emails' || path === 'groups') o.value = pick([{ value: 'n@o.p', type: 'other' }, [{ value: 'a@b.c' }, { value: 'd@e.f' }]]);
    else o.value = pick(['s', 7, true, { k: 'v' }, ['x']]);
  }
  return o;
}
for (let i = 0; i < 90; i++) {
  const r = resource(i);
  const o = operation();
  const out = scim.applyScimPatchOp(r, o);
  add({ op: 'patchop', resource: r, operation: o, e: norm(out) });
}
for (let i = 0; i < 30; i++) {
  const r = resource(i);
  const body = pick([{ Operations: Array.from({ length: 1 + int(3) }, operation) }, { operations: [operation()] }, { Operations: [] }, {}, { Operations: 'x' }]);
  add({ op: 'patch', resource: r, body, e: norm(scim.applyScimPatch(r, body)) });
}

for (let i = 0; i < 20; i++) {
  const r = resource(i);
  add({ op: 'version', resource: r, e: scim.resourceVersion(r) });
}
add({ op: 'version', resource: { id: 'é\u2028"q"\n', userName: '日本\u0001' }, e: scim.resourceVersion({ id: 'é\u2028"q"\n', userName: '日本\u0001' }) });

for (let i = 0; i < 30; i++) {
  const u = {};
  if (chance(0.9)) u.id = `u${i}`;
  if (chance(0.6)) u.email = pick(NAMES);
  if (chance(0.5)) u.userName = pick(NAMES);
  if (chance(0.5)) u.name = pick(['Ann Lee', '']);
  if (chance(0.4)) u.givenName = 'Ann';
  if (chance(0.4)) u.familyName = 'Lee';
  if (chance(0.3)) u.externalId = 'ext-1';
  if (chance(0.3)) u.active = chance(0.5);
  if (chance(0.4)) u.groups = [pick(['g1', { id: 'g2', name: 'Staff' }, { id: 'g3' }]), pick(['g4', { id: 'g5', name: 'Ops' }])];
  if (chance(0.3)) u.createdAt = '2026-01-01T00:00:00Z';
  if (chance(0.3)) u.updatedAt = '2026-02-02T00:00:00Z';
  const base = chance(0.5) ? undefined : '/api/scim';
  add({ op: 'user', user: u, base: base === undefined ? '' : base, e: norm(scim.toScimUser(u, base === undefined ? {} : { baseUrl: base })) });
}
for (let i = 0; i < 20; i++) {
  const g = {};
  if (chance(0.9)) g.id = `g${i}`;
  if (chance(0.6)) g.displayName = 'Admins';
  if (chance(0.6)) g.name = 'Team';
  if (chance(0.3)) g.externalId = 'x';
  if (chance(0.7)) g.members = Array.from({ length: int(3) }, () => pick(['u1', { id: 'u2', name: 'Bob' }, { id: 'u3' }]));
  if (chance(0.3)) g.createdAt = '2026-01-01T00:00:00Z';
  const base = chance(0.5) ? undefined : '/scim';
  add({ op: 'group', group: g, base: base === undefined ? '' : base, e: norm(scim.toScimGroup(g, base === undefined ? {} : { baseUrl: base })) });
}

for (let i = 0; i < 30; i++) {
  const r = scim.toScimUser({ id: `p${i}`, email: pick(NAMES), name: 'Ann Lee', givenName: 'Ann', active: true, groups: ['g1'] });
  const o = {};
  const kind = int(5);
  if (kind === 0) o.attributes = pick(['userName', 'userName,emails', 'name.givenName, active', ['displayName', 'meta.version'], '', ' , ', 'nope']);
  if (kind === 1) o.excludedAttributes = pick(['groups', 'groups,meta', 'id', 'schemas,emails', ['active'], '']);
  if (kind === 2) { o.attributes = 'userName'; o.excludedAttributes = 'userName'; }
  add({ op: 'project', resource: r, opts: o, e: norm(scim.projectAttributes(r, o)) });
}

for (let i = 0; i < 40; i++) {
  const rs = Array.from({ length: int(7) }, (_, k) => ({ id: k }));
  const o = {};
  if (chance(0.7)) o.startIndex = pick([1, 2, 3, 5, 0, -2, 99, null, '2']);
  if (chance(0.6)) o.count = pick([0, 1, 2, 3, 100, null, '2']);
  if (chance(0.25)) o.totalResults = pick([17, 0, null]);
  add({ op: 'list', resources: rs, opts: o, e: norm(scim.listResponse(rs, o)) });
}
for (let i = 0; i < 8; i++) {
  const status = pick([400, 404, '409', 500]);
  const type = pick([null, 'invalidFilter', undefined, '']);
  const detail = pick(['bad', 'not found', 'x "y"']);
  add({ op: 'error', status: String(status), detail, scimType: type || '', e: norm(scim.scimError(status, detail, type)) });
}
for (const [status, detail, type] of [[400, 'bad', 'invalidFilter'], [404, 'nope', null]]) add({ op: 'error', status: String(status), detail, scimType: type || '', e: norm(scim.scimError(status, detail, type)) });
add({ op: 'config', base: '', doc: '', e: norm(scim.serviceProviderConfig()) });
add({ op: 'config', base: '/api/scim', doc: 'https://docs/x', e: norm(scim.serviceProviderConfig({ baseUrl: '/api/scim', documentationUri: 'https://docs/x' })) });
add({ op: 'types', base: '', e: norm(scim.resourceTypes()) });
add({ op: 'types', base: '/api', e: norm(scim.resourceTypes({ baseUrl: '/api' })) });

for (let i = 0; i < 40; i++) {
  const rs = Array.from({ length: int(7) }, (_, k) => {
    const r = { id: k };
    if (chance(0.85)) r.userName = pick(['bob', 'alice', 'carol', 'bob', 'dave']);
    if (chance(0.7)) r.age = int(5);
    if (chance(0.5)) r.name = { givenName: pick(['x', 'y']) };
    return r;
  });
  const by = pick(['userName', 'age', 'name.givenName', '', 'missing']);
  const order = pick(['ascending', 'descending', 'DESCENDING', undefined, 'bogus']);
  add({ op: 'sort', resources: rs, by, order: order || '', e: norm(scim.sortResources(rs, by, order)) });
}

const lines = cases.map((c) => JSON.stringify(c));
const chunks = [];
const size = 10;
for (let i = 0; i < lines.length; i += size) {
  chunks.push(`"${lines.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'scim_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_identity_scim/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_identity_scim`);
