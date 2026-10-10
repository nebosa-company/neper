// Vectors for `x.cloud.rest` (L047): Petcow's own declarative REST helpers and registry (the reference is
// provider/declarative.rs lines 22-1150 and provider/mod.rs compiled with thin shims, `restref.exe`) over random
// resource definitions, templates, bodies, operations and registry sequences, written as the link fixture
// tests/selfhost/fixtures/link/x_cloud_rest. Usage: node scripts/rest_vectors.mjs REFERENCE_EXE
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x6e41;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const TYPES = ['gcp.dns_managed_zone', 'azure.vnet', 'ibm.cos_bucket', 'oci.bucket', 'ali.vpc', 'aws.s3', 'tf.aws_s3_bucket', 'gcp.dataplex_zone', 'k8s.deployment'];
const FIELDS = ['name', 'id', 'datasetReference.datasetId', 'VpcId', 'selfLink', 'resourceId'];
const ITEM_URLS = ['https://x.googleapis.com/v1/projects/{project}/zones/{name}', 'https://m.azure.com/subscriptions/{subscription}/vnets/{name}', 'https://vpc.aliyuncs.com/{region}/vpcs/{name}',
  'https://x/v1/projects/{project}/locations/{location}/lakes/{lake}/zones/{name}', 'https://x/{name}', 'https://x/{unknown}/{name}', 'https://x/{name', 'https://x/a{b}c{d}e'];

function def() {
  const d = {
    type_name: pick(TYPES),
    create_method: pick(['PUT', 'POST']),
    item_url: pick(ITEM_URLS),
    create_url: pick(ITEM_URLS),
    list_url: pick(ITEM_URLS),
    list_items_field: pick(['', 'items', 'data.items', 'managedZones']),
    real_id_field: pick(FIELDS),
    copy_attrs: Array.from({ length: int(4) }, () => [pick(['dns_name', 'description', 'cidr', 'labels2']), pick(['dnsName', 'description', 'cidrBlock', 'nested.field'])]),
    output_attrs: Array.from({ length: int(3) }, () => pick(['creationTime', 'state', 'etag'])),
  };
  const m = int(4);
  if (m === 0) d.marker = { field: pick(['labels', 'tags', 'freeformTags']), managed_key: 'petcow_managed', name_key: 'petcow_name' };
  if (m === 1) d.marker = { field: 'Tags.Tag', managed_key: 'petcow_managed', name_key: 'petcow_name', pair: { key_field: 'TagKey', value_field: 'TagValue' } };
  if (chance(0.5)) d.name_field = pick(['name', 'displayName', 'datasetReference.datasetId']);
  if (chance(0.25)) d.name_value_template = pick(['projects/{project}/zones/{name}', '{name}-x', 'projects/{unknown}/{name}']);
  if (chance(0.3)) d.update_mask = pick(['description', 'description,labels', 'dnsName, versionTemplate.algorithm', 'a,b,c']);
  if (chance(0.4)) d.operation_url = pick(['https://x/v1/{operation}', 'https://x/ops/{operation}/get']);
  d.operation_style = pick(['lro', 'lro', 'compute', 'work_request']);
  if (chance(0.2)) d.create_wrapper = { key: pick(['instance', 'serviceAccount']), id_field: chance(0.6) ? pick(['instanceId', 'accountId']) : undefined };
  if (chance(0.2)) d.name_suffix = pick(['/', '.json']);
  if (chance(0.2)) d.observed_name_field = pick(['Name', 'displayName', 'metadata.name']);
  if (chance(0.2)) d.create_body_vars = Array.from({ length: 1 + int(2) }, () => [pick(['compartmentId', 'metadata.compartmentId', 'a.b.c']), pick(['{compartment}', '{region}/{name}', '{project}', '{missing}'])]);
  return d;
}

const WORDS = ['alpha', 'beta-1', 'petcow-demo-vpc', 'x/y/z', '', 'with space', '日本'];
function attrsFor(d) {
  const a = {};
  for (const [attr] of d.copy_attrs) if (chance(0.7)) a[attr] = pick([pick(WORDS), int(100), chance(0.5), { automatic: {} }, [1, 'two', { three: 3 }], 1.5]);
  if (chance(0.5)) a.project = pick(['p1', 'p2', 7, true]);
  if (chance(0.3)) a.region = pick(['us-east1', 'eu']);
  if (d.marker && !d.marker.pair && chance(0.6)) a[d.marker.field] = { team: 'x', petcow_name: 'hijack', k2: 'v2', num: 5 };
  if (chance(0.15)) a.nested = { field: 1 };
  return a;
}
function bodyFor(d) {
  const b = {};
  if (chance(0.8)) b[d.real_id_field.split('.')[0]] = d.real_id_field.includes('.') ? { datasetId: pick(WORDS) } : pick(['petcow-demo-zone', 'projects/p/zones/petcow-z1', 'folder/petcow-f/', 'plain', 5, null]);
  for (const [, f] of d.copy_attrs) if (chance(0.6)) b[f.split('.')[0]] = pick([pick(WORDS), 3, null, { a: 1 }, [1]]);
  for (const o of d.output_attrs) if (chance(0.5)) b[o] = pick(['v', 12, null]);
  if (d.marker) {
    if (d.marker.pair) {
      b.Tags = { Tag: [{ TagKey: 'petcow_managed', TagValue: pick(['true', 'false']) }, { TagKey: 'petcow_name', TagValue: 'petcow-x' }, { TagKey: 'owner', TagValue: 'me' }] };
      if (chance(0.2)) b.Tags = { Tag: 'not-a-list' };
    } else if (chance(0.8)) {
      b[d.marker.field] = { petcow_managed: pick(['true', 'false']), petcow_name: pick(['petcow-demo-z', '']), team: 'a', n: 1 };
    }
  }
  if (d.observed_name_field && chance(0.7)) { const [h, ...t] = d.observed_name_field.split('.'); b[h] = t.length ? { name: 'obs-name' } : 'obs-name'; }
  if (d.list_items_field && chance(0.5)) { /* listing bodies are separate */ }
  return b;
}

const cases = [];
const add = (c) => cases.push(c);

for (const t of [...TYPES, 'gcp', '', 'ali.x.y', 'GCP.x']) add({ op: 'cloud', type: t, cloud: pick(['gcp', 'azure', 'ibm', 'oci', 'aliyun', 'ali', 'aws', '']) });

for (let i = 0; i < 24; i++) {
  const steps = [];
  const used = new Set();
  const n = 6 + int(10);
  for (let k = 0; k < n; k++) {
    const t = pick(['aws.s3', 'aws.vpc', 'tf.aws_s3_bucket', 'tf.vpc', 'gcp.x', 'aws.ec2']);
    const kind = pick(['register', 'aliased', 'bridged', 'prefer', 'isBridged', 'source', 'resolve', 'get', 'getAliased', 'supports', 'supportsAliased', 'types', 'source', 'resolve']);
    const st = { k: kind, type: t };
    if (kind === 'aliased' || kind === 'getAliased' || kind === 'supportsAliased') { st.alias = pick(['east', 'west']); if (kind !== 'aliased' && chance(0.3)) delete st.alias; }
    if (kind === 'bridged' && chance(0.7)) st.native = pick(['aws.s3', 'aws.vpc', 'aws.ec2']);
    if (kind === 'register' || kind === 'bridged') {
      const key = `${kind === 'register' ? 'r' : 'b'}:${t}`;
      if (kind === 'register' && used.has(`b:${t}`)) continue;
      if (used.has(key)) continue;
      used.add(key);
      used.add(`r:${t}`);
    }
    if (kind === 'aliased') { const key = `a:${st.alias}:${t}`; if (used.has(key)) continue; used.add(key); }
    steps.push(st);
  }
  // one deliberate duplicate in a few sequences
  if (i % 6 === 0) steps.push({ k: 'register', type: 'aws.s3' }, { k: 'register', type: 'aws.s3' });
  add({ op: 'registry', steps });
}

const TEMPLATES = ['https://x/{project}/{name}', '{name}', 'plain', '{project}{region}', 'a{name', '{}', '{name}/{count}', 'https://{region}.x/{project}/{enabled}', '{ok}'];
for (let i = 0; i < 50; i++) {
  const attrs = {};
  if (chance(0.6)) attrs.project = pick(['p1', 7, true, 1.5, { a: 1 }, [1], null]);
  if (chance(0.4)) attrs.region = pick(['us', 'eu']);
  if (chance(0.3)) attrs.count = pick([3, 0, -1]);
  if (chance(0.3)) attrs.enabled = chance(0.5);
  const vars = {};
  if (chance(0.5)) vars.project = 'ctx-project';
  if (chance(0.4)) vars.region = 'ctx-region';
  if (chance(0.2)) vars.ok = 'fine';
  add({ op: 'render', template: pick(TEMPLATES), name: pick(['n1', 'petcow-x']), attrs, vars });
}

const PATHS = ['name', 'a.b', 'a.b.c', 'datasetReference.datasetId', '', 'x', 'items', 'a.', '.a'];
for (let i = 0; i < 40; i++) {
  const body = pick([{ name: 'n', a: { b: { c: 1 } }, datasetReference: { datasetId: 'd' }, items: [1, 2], x: null }, { a: 5 }, [1, 2], 'str', {}, { a: [1] }]);
  add({ op: 'getPath', body, path: pick(PATHS) });
}
for (let i = 0; i < 30; i++) {
  const obj = pick([{}, { a: { z: 1 } }, { a: 5 }, { a: { b: 'x' } }, { name: 1 }, { a: null }]);
  add({ op: 'setPath', obj, path: pick(['name', 'a.b', 'a.b.c', 'x.y', 'datasetReference.datasetId']), value: pick(['v', 3, { k: 1 }, null]) });
}

for (let i = 0; i < 90; i++) {
  const d = def();
  const attrs = attrsFor(d);
  const name = pick(['petcow-demo-z', 'petcow-x']);
  const vars = pick([{}, { project: 'ctx-p', location: 'ctx-l', region: 'ctx-r', compartment: 'ctx-c', subscription: 's', lake: 'lk' }]);
  add({ op: 'body', def: d, name, nameValue: pick([name, `projects/p/zones/${name}`]), attrs });
  if (i % 3 === 0) add({ op: 'nameValue', def: d, name, vars });
  if (i % 3 === 0) add({ op: 'bodyVars', def: d, body: pick([{}, { a: { b: 1 } }, [1], { compartmentId: 'old' }, { a: 5 }]), name, attrs, vars });
  if (i % 3 === 1) add({ op: 'address', def: d, name });
  if (i % 3 === 1) add({ op: 'wrap', def: d, name, body: pick([{ a: 1 }, {}]) });
  const body = bodyFor(d);
  add({ op: 'parse', def: d, body });
  add({ op: 'isManaged', def: d, body });
  add({ op: 'observedName', def: d, body });
  if (i % 2 === 0) add({ op: 'observed', def: d, body });
  if (i % 4 === 0) add({ op: 'items', def: d, body: pick([[1, 2], { items: [1], managedZones: [2], data: { items: [3] } }, {}, 'x']) });
  if (i % 4 === 1) add({ op: 'isAsync', def: d });
}

for (let i = 0; i < 20; i++) {
  const real = pick(['projects/P/locations/L/lakes/LAKE/zones/ZONE', 'zone', 'projects/P', 'a/b/c', 'projects/P/locations/L/lakes/LAKE/zones/Z/extra']);
  add({ op: 'scope', itemUrl: pick(ITEM_URLS), realId: chance(0.9) ? real : undefined });
}
for (let i = 0; i < 12; i++) add({ op: 'updateUrl', url: pick(['https://x/item', 'https://x/item?a=1']), mask: chance(0.7) ? 'a,b' : undefined });
for (let i = 0; i < 16; i++) add({ op: 'mask', curated: chance(0.9) ? pick(['a,b,c', ' a , d.e , z', 'a', 'versionTemplate.algorithm,labels']) : undefined, body: pick([{ a: 1 }, { d: 1, z: null }, {}, { versionTemplate: {} }, { labels: 1, a: 1 }]) });

const OPS = [{ name: 'operations/abc', done: true }, { name: 'projects/p/operations/op1', done: false }, { name: 'projects/p/zones/z' }, { name: 'op-without' }, { done: true, error: { code: 3, message: 'bad' } }, { done: true, error: null },
  { error: { code: 1 }, done: true }, {}, { kind: 'compute#operation', selfLink: 'https://compute/ops/1', status: 'DONE' }, { kind: 'compute#operation', status: 'RUNNING', selfLink: 'u' },
  { kind: 'compute#operation', status: 'DONE', error: { errors: [{ code: 'X' }] }, httpErrorMessage: 'NOT FOUND' }, { kind: 'compute#operation', status: 'DONE', error: { errors: [] } },
  { status: 'SUCCEEDED', id: 'ocid1' }, { status: 'FAILED', id: 'ocid2' }, { status: 'CANCELED' }, { status: 'IN_PROGRESS' }, { status: 'weird' }, { selfLink: 'x' }];
for (let i = 0; i < 70; i++) {
  const d = def();
  d.operation_url = chance(0.8) ? pick(['https://x/v1/{operation}', 'https://x/ops/{operation}']) : undefined;
  const body = pick(OPS);
  add({ op: 'lroName', def: d, body });
  add({ op: 'opStatusFor', def: d, body });
  add({ op: 'pollTarget', def: d, body, headers: pick([[], [['Opc-Work-Request-Id', ' ocid1.wr.abc ']], [['opc-work-request-id', '  ']], [['x', 'y']]]) });
  if (i % 3 === 0) add({ op: 'opStatus', body });
  if (i % 3 === 1) add({ op: 'isCompute', body });
}
add({ op: 'pollUrl', template: 'https://x/{operation}/y', name: 'projects/p/operations/1' });
add({ op: 'pollUrl', template: 'https://x/{operation}/{operation}', name: 'o' });
add({ op: 'workRequestId', headers: [['OPC-WORK-REQUEST-ID', ' id1 ']] });
add({ op: 'workRequestId', headers: [] });
for (const minutes of [undefined, 0, 1, 5, 30, 60]) add({ op: 'polls', minutes });
for (const budgetMs of [0, 200, 500, 700, 1500, 4000, 9000, 30000]) add({ op: 'settle', budgetMs });

const exe = process.argv[2] || 'D:/temp/restref/restref.exe';
const out = execFileSync(exe, [], { input: JSON.stringify(cases), maxBuffer: 1 << 28 }).toString();
const answers = JSON.parse(out);
const lines = cases.map((c, i) => JSON.stringify({ ...c, e: answers[i] }));
const chunks = [];
for (let i = 0; i < lines.length; i += 10) {
  chunks.push(`"${lines.slice(i, i + 10).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'rest_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_cloud_rest/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
const panics = answers.filter((x) => x && x.panic).length;
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_cloud_rest (${panics} reference panics)`);
