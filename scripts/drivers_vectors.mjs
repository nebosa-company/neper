// Vectors for `x.cloud.k8s`, `x.cloud.awssdk` and `x.ssh.transport` (L048): the pure helpers of Petcow's k8s provider, its
// S3, IAM, EC2 and Lightsail providers and its per-host transport selection (extracted unchanged into `l048ref.exe`
// behind thin shims for the SDK builders, see the Rust source beside this script's fixture notes in D2922) over random
// inputs, written as the link fixture tests/selfhost/fixtures/link/x_cloud_drivers.
// Usage: node scripts/drivers_vectors.mjs REFERENCE_EXE   (default D:/temp/l048ref/target/debug/l048ref.exe)
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x48d1;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

// the reference sorts every object it parses (serde_json without preserve_order); keep ours sorted too so that member
// order, where a result keeps it, agrees
const sorted = (v) => {
  if (Array.isArray(v)) return v.map(sorted);
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])]));
  return v;
};

const cases = [];
const add = (c) => cases.push(sorted(c));

// ---- k8s --------------------------------------------------------------------------------------------------------------
add({ op: 'k8sDefs' });
const KINDS = ['Gateway', 'Widget', 'Deployment', 'ConfigMap', 'Certificate'];
const GROUPS = ['v1', 'apps/v1', 'gateway.networking.k8s.io/v1', 'cert-manager.io/v1', 'batch/v1', 'example.org/v1beta1'];
const defObj = () => ({
  type: pick(['k8s.gateway', 'k8s.widget', 'k8s.deployment', 'k8s.config_map', 'k8s.certificate', 'k8s.job']),
  api_version: pick(GROUPS),
  kind: pick(KINDS),
  ...(chance(0.5) ? { namespaced: chance(0.5) } : {}),
});
for (let i = 0; i < 18; i++) add({ op: 'parseDefs', text: JSON.stringify(Array.from({ length: int(4) }, defObj)) });
for (const t of ['[{"type":"a","api_version":"v1","kind":"K","bogus":1}]', '{"type":"a"}', '[{"type":"a","api_version":"v1"}]', '[{"type":"a","kind":"K"}]', '[{"api_version":"v1","kind":"K"}]',
  '[{"type":"a","api_version":"v1","kind":"K","namespaced":"yes"}]', '[{"type":5,"api_version":"v1","kind":"K"}]', '[{"type":"a","api_version":"v1","kind":null}]', '[]', '[1]', '"x"',
  '[{"type":"a","api_version":"v1","kind":"K","kind":"L"}]', '[{"type":"a","api_version":"v1","kind":"K","namespaced":null}]', '- type: k8s.gateway\n  api_version: gateway.networking.k8s.io/v1\n  kind: Gateway\n',
  '- type: k8s.g\n  api_version: v1\n  kind: G\n  namespaced: false\n']) add({ op: 'parseDefs', text: t });
for (let i = 0; i < 10; i++) add({ op: 'allDefs', text: JSON.stringify(Array.from({ length: 1 + int(3) }, defObj)) });
for (const d of [{ type: 'k8s.deployment', api_version: 'apps/v1', kind: 'Deployment', namespaced: true }, { type: 'k8s.config_map', api_version: 'v1', kind: 'ConfigMap', namespaced: true },
  { type: 'k8s.namespace', api_version: 'v1', kind: 'Namespace', namespaced: false }, { type: 'k8s.ingress', api_version: 'networking.k8s.io/v1', kind: 'Ingress', namespaced: true }]) {
  for (const ns of [undefined, 'prod', '']) add({ op: 'selector', def: d, ...(ns !== undefined ? { ns } : {}) });
}
const sampleDefs = [{ type: 'k8s.config_map', api_version: 'v1', kind: 'ConfigMap', namespaced: true }, { type: 'k8s.deployment', api_version: 'apps/v1', kind: 'Deployment', namespaced: true }, { type: 'k8s.namespace', api_version: 'v1', kind: 'Namespace', namespaced: false }];
const genSpec = (depth = 0) => {
  const r = int(8);
  if (depth > 2 || r < 3) return pick([1, 3, 2.5, true, false, null, 'x', 'a b', '']);
  if (r < 5) return Array.from({ length: int(3) }, () => genSpec(depth + 1));
  return Object.fromEntries(Array.from({ length: int(4) }, () => [pick(['replicas', 'image', 'ports', 'env', 'a', 'b']), genSpec(depth + 1)]));
};
for (let i = 0; i < 40; i++) {
  const attrs = {};
  if (chance(0.7)) attrs.spec = genSpec();
  if (chance(0.4)) attrs.data = { k: pick(['v', 'w']), n: int(5) };
  if (chance(0.2)) attrs.apiVersion = 'bogus/v9';
  if (chance(0.2)) attrs.kind = 'Bogus';
  if (chance(0.15)) attrs.status = { ready: 1 };
  if (chance(0.7)) {
    attrs.metadata = pick([
      { labels: { app: 'web' } }, { labels: { app: 'web', 'petcow.io/managed': 'false' } }, { annotations: { a: 'b' }, name: 'user-name' }, { labels: 'not-a-map' },
      'a string', null, { namespace: 'ns1', labels: { 'petcow.io/name': 'forged', z: 'y' }, finalizers: ['f'] }, [1, 2], {},
    ]);
  }
  add({ op: 'applyManifest', def: pick(sampleDefs), name: pick(['petcow-demo-cfg', 'petcow-demo-web', 'weird "name"', 'ünï']), attrs });
}
const annotate = (applied) => ({ 'kubectl.kubernetes.io/last-applied-configuration': applied });
for (let i = 0; i < 40; i++) {
  const live = { apiVersion: 'apps/v1', kind: 'Deployment', metadata: {}, spec: { replicas: 3, revisionHistoryLimit: 10, strategy: { type: 'RollingUpdate' } }, status: { readyReplicas: 3 } };
  if (chance(0.9)) live.metadata.name = pick(['petcow-demo-web', 'foreign', '']);
  if (chance(0.7)) live.metadata.uid = pick(['abc-123', 'u1', '']);
  if (chance(0.3)) live.data = { a: '1' };
  const r = int(8);
  if (r === 0) live.metadata.annotations = annotate(JSON.stringify({ apiVersion: 'apps/v1', kind: 'Deployment', metadata: { name: 'petcow-demo-web' }, spec: { replicas: 3 } }));
  else if (r === 1) live.metadata.annotations = annotate('{not json');
  else if (r === 2) live.metadata.annotations = annotate(JSON.stringify([1, 2]));
  else if (r === 3) live.metadata.annotations = annotate(JSON.stringify('text'));
  else if (r === 4) live.metadata.annotations = annotate(JSON.stringify({ data: { a: '1' }, status: 1, kind: 'x', extra: [1, { b: 2 }] }));
  else if (r === 5) live.metadata.annotations = { other: 'x' };
  else if (r === 6) live.metadata.annotations = annotate(123);
  if (chance(0.1)) live.metadata = pick([null, 'x', []]);
  add({ op: 'observed', type: pick(['k8s.deployment', 'k8s.config_map']), obj: live });
}
add({ op: 'observed', type: 'k8s.config_map', obj: { metadata: { name: 'dup', annotations: annotate('{"data":{"a":"1"},"data":{"a":"2"}}') } } });
add({ op: 'observed', type: 'k8s.config_map', obj: 'scalar' });
for (const item of [{ metadata: { name: 'x', labels: { 'petcow.io/managed': 'true' } } }, { metadata: { name: 'x', labels: { app: 'web' } } }, { metadata: { name: 'bare' } }, { metadata: { labels: { 'petcow.io/managed': 'True' } } },
  { metadata: { labels: { 'petcow.io/managed': true } } }, {}, 'x', { metadata: 'm' }, { metadata: { labels: null } }]) add({ op: 'managedItem', item });
for (const stderr of ['Error from server (NotFound): deployments.apps "x" not found', 'Error from server (Forbidden): denied', 'not FOUND', 'NOTFOUND', '', 'resource was not  found', 'Not Found']) add({ op: 'notFound', stderr });

// ---- S3 ----------------------------------------------------------------------------------------------------------------
for (const name of ['petcow-demo-assets', 'ab', 'a'.repeat(63), 'a'.repeat(64), 'Petcow_demo', 'petcow_demo', '-petcow', 'petcow-', '.petcow', 'petcow.', 'a.b-c', 'abc', 'ñandú', 'é'.repeat(20), 'UPPER', 'has space', '3d.s']) add({ op: 'bucketName', name });
const attrBag = () => {
  const a = {};
  if (chance(0.6)) a.versioning = pick([true, false, 'true', 1, null]);
  if (chance(0.6)) a.public = pick([true, false, 'yes']);
  if (chance(0.6)) a.region = pick(['eu-west-1', 'us-east-1', 5, null, '']);
  if (chance(0.6)) a.tags = pick([{ Env: 'prod', Team: 'infra' }, { Env: 5, ok: 'y' }, ['a'], 'x', {}, { 'petcow:managed': 'false', a: null }, null]);
  if (chance(0.5)) a.managed_policy_arns = pick([['arn:b', 'arn:a', 'arn:C'], ['x', 5, 'y'], 'one', [], null, ['z', 'Z', 'a', 'é']]);
  if (chance(0.4)) a.count = pick([1, 2.5, -7, 3000000000, 9223372036854775807, 1e3, 0]);
  if (chance(0.5)) a.sgs = pick([['sg-1', 'sg-2'], ['sg-1', 7], 'sg-1', []]);
  return a;
};
for (let i = 0; i < 14; i++) {
  const attrs = attrBag();
  for (const key of ['versioning', 'public', 'region']) { add({ op: 'attrBool', attrs, key }); add({ op: 'attrStr', attrs, key }); }
  add({ op: 'userTags', attrs });
  add({ op: 'desiredArns', attrs });
  add({ op: 'attrI64', attrs, key: 'count' });
  add({ op: 'attrStrList', attrs, key: 'sgs' });
  add({ op: 'optAttr', attrs, key: pick(['region', 'bundle']) });
  add({ op: 'reqAttr', attrs, key: pick(['region', 'blueprint']), kind: 'aws.lightsail_instance' });
}

// ---- IAM ---------------------------------------------------------------------------------------------------------------
const enc = (s) => Array.from(Buffer.from(s, 'utf8')).map((b) => (chance(0.5) && b > 32 && b < 127 && !'%'.includes(String.fromCharCode(b)) ? String.fromCharCode(b) : '%' + b.toString(16).toUpperCase().padStart(2, '0'))).join('');
for (const s of ['%7B%22Version%22%3A%222012-10-17%22%7D', 'plain-text_123', '%', '%4', '%41', '%4G', '%zz%41', 'a%2', 'a%20b%', '%E2%82', '%E2%82%AC', '%FF', '%C3%A9', '%C3', '%ED%A0%80', '%F0%9F%98%80', '%F0%9F%98', '%80%81', '%E2%82%41', '%C0%80', '%F4%90%80%80', 'x%E2%82%ACy%FFz', '%25', '%2525', '%e2%82%ac', 'ünï%41']) add({ op: 'percentDecode', s });
for (let i = 0; i < 20; i++) add({ op: 'percentDecode', s: enc(pick(['{"Version":"2012-10-17"}', 'héllo wörld €', '😀 ok', 'a/b?c=d&e', '日本語']) ) });
const policy = { Statement: [{ Action: 'sts:AssumeRole', Effect: 'Allow', Principal: { Service: 'ec2.amazonaws.com' } }], Version: '2012-10-17' };
for (const p of [policy, '{"Version":"2012-10-17"}', 5, true, ['a', 1], null, undefined, { a: 1.5, b: [null, true] }]) add({ op: 'assumeRole', name: 'petcow-r', attrs: p === undefined ? {} : { assume_role_policy: p } });
for (const user of [{}, { Env: 'prod' }, { b: '2', a: '1', Team: 'x' }, { 'petcow:managed': 'hijack' }]) add({ op: 'iamTags', name: pick(['petcow-role', 'r']), user });

// ---- EC2 / Lightsail ----------------------------------------------------------------------------------------------------
for (const user of [{}, { Env: 'prod' }, { z: '1', a: '2' }, { Name: 'override', 'petcow:name': 'x' }]) { add({ op: 'managedTags', name: 'petcow-vm', user }); add({ op: 'iamTags', name: 'petcow-vm', user }); }
add({ op: 'lsTags', name: 'petcow-proj-web' });
const genTags = () => Array.from({ length: int(6) }, () => [pick(['Name', 'petcow:name', 'petcow:managed', 'Env', 'Team', null, 'k']), pick(['web', '', 'true', 'prod', null, 'x'])]);
for (let i = 0; i < 30; i++) {
  const tags = genTags();
  add({ op: 'observedUserTags', tags });
  add({ op: 'petcowName', tags });
  add({ op: 'nameOrId', tags, realId: pick(['i-123', 'vpc-9']) });
  add({ op: 'unmanaged', type: pick(['aws.instance', 'aws.vpc']), tags, realId: pick(['i-123', 'vpc-9']) });
}
for (const tags of [[['Name', '']], [['Name', ''], ['Name', 'x']], [['Name', null]], [['x', 'y'], ['Name', 'web']], []]) { add({ op: 'nameOrId', tags, realId: 'i-9' }); add({ op: 'unmanaged', type: 'aws.instance', tags, realId: 'i-9' }); }
const rule = () => ({
  ...(chance(0.92) ? { protocol: pick(['tcp', 'udp', '-1', 5]) } : {}),
  ...(chance(0.7) ? { from_port: pick([22, 443, 0, 8080, 4294967296 + 80, -1, 2147483648, 2.5, '80', null]) } : {}),
  ...(chance(0.5) ? { to_port: pick([22, 65535, 100, 4294967297]) } : {}),
  ...(chance(0.92) ? { cidr: pick(['0.0.0.0/0', '10.0.0.0/8', 5]) } : {}),
});
for (let i = 0; i < 24; i++) add({ op: 'ingress', name: 'petcow-sg', attrs: pick([{}, { ingress: Array.from({ length: int(4) }, rule) }, { ingress: 'x' }, { ingress: [rule(), 'str', rule()] }, { ingress: [] }]) });

// ---- transport ----------------------------------------------------------------------------------------------------------
const KNOWN = ['ssm', 'ssh', 'winrm'];
const tvals = ['ssm', 'ssh', 'winrm', 'winrmm', '  ssh  ', '', '   ', '\tssm\n', '\u00a0ssh\u00a0', 'SSH', 5, null, true, ['ssh'], 'ssm ', '\u3000winrm\u2003'];
for (let i = 0; i < 40; i++) {
  const hosts = Array.from({ length: 1 + int(7) }, (_, k) => ({ name: `h${k}`, ...(chance(0.75) ? { transport: pick(tvals) } : {}) }));
  add({ op: 'transport', default: pick(['ssm', 'ssh', 'winrm', 'bogus', '']), known: chance(0.85) ? KNOWN : ['ssh'], hosts });
}

const exe = process.argv[2] || 'D:/temp/l048ref/target/debug/l048ref.exe';
const answers = JSON.parse(execFileSync(exe, [], { input: JSON.stringify(cases), maxBuffer: 1 << 28 }).toString());
const bs = String.fromCharCode(92);
const lines = cases.map((c, i) => JSON.stringify({ ...c, e: answers[i] }));
const chunks = [];
for (let i = 0; i < lines.length; i += 10) {
  chunks.push('"' + lines.slice(i, i + 10).map((l) => l.split(bs).join(bs + bs).split('"').join(bs + '"')).join(bs + 'n') + bs + 'n"');
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'drivers_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_cloud_drivers/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_cloud_drivers`);
