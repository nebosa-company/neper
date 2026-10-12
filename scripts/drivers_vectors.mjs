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

// ---- WinRM, local, SSM, Lightsail list mapping (second part of L048) ----------------------------------------------------
const CMDS = ['whoami', 'Get-Service | Where-Object Status -eq Running', "Write-Output 'it''s $here'; `echo x`\nStop-Service 'w3svc'", 'echo "héllo wörld"', 'dir C:\\Users\\*', '', 'a', 'ab', 'abc', 'abcd', '日本語テキスト', '😀 ok 𝄞', 'x'.repeat(100), 'tab\there\r\nline'];
for (const s of CMDS) add({ op: 'encodeCommand', s });
const winVars = () => {
  const v = {};
  if (chance(0.4)) v.winrm_allow_http = pick([true, false, 'yes', 'No', ' TRUE ', 'maybe', 5, null]);
  if (chance(0.3)) v.winrm_port = pick(['15986', 5986, '', '  ', 7, '5985']);
  if (chance(0.2)) v.ansible_port = pick(['2222', 22, '']);
  if (chance(0.2)) v.port = pick(['9', 10]);
  if (chance(0.4)) v.winrm_user = pick(['svc_deploy', 'DOMAIN\\user', "o'brien", '', '   ', 5, 'ünï']);
  if (chance(0.2)) v.ansible_user = pick(['admin', 'Administrator']);
  if (chance(0.15)) v.user = 'u1';
  if (chance(0.3)) v.winrm_auth = pick(['Kerberos', 'Basic', '', 'Negotiate', 'CredSSP']);
  if (chance(0.1)) v.winrm_authentication = 'Default';
  if (chance(0.3)) v.winrm_skip_ca_check = pick([true, false, 'yes', 'no', 'x']);
  if (chance(0.3)) v.winrm_skip_cn_check = pick([true, false, 'YES', 'false', 1]);
  return v;
};
for (let i = 0; i < 60; i++) add({ op: 'winrmArgs', address: pick(['w.example', '10.0.0.9', 'win-1.corp.local']), vars: winVars(), command: pick(CMDS), shell: pick(['posix', 'powershell']) });
add({ op: 'winrmArgs', address: 'w', vars: {}, command: 'x', shell: 'posix' });
for (const windows of [true, false]) add({ op: 'winrmProgram', windows });
for (const notFound of [true, false]) add({ op: 'winrmError', host: 'win1', exe: pick(['powershell', 'pwsh']), notFound, msg: 'Access is denied. (os error 5)' });
for (const shell of ['posix', 'powershell']) {
  for (const command of CMDS.slice(0, 6)) add({ op: 'localArgv', command, shell });
  add({ op: 'localError', host: 'node-1', shell, msg: 'No such file or directory (os error 2)' });
  add({ op: 'ssmDocument', shell });
}
for (const status of ['Pending', 'InProgress', 'Delayed', 'Success', 'Cancelled', 'Failed', 'TimedOut', 'Cancelling', 'success', 'Weird', '']) add({ op: 'ssmTerminal', status });
const SSMVARS = [{ resource_id: 'i-1' }, { instance_id: 'i-2' }, { resource_id: 'i-1', instance_id: 'i-2' }, { resource_id: 5, instance_id: 'i-3' }, {}, { resource_id: '' }, { resource_id: null, instance_id: 'i-4' }, { instance_id: ['i-5'] }, { transport: 'ssm', other: 'x' }];
for (const vars of SSMVARS) add({ op: 'ssmInstanceId', name: pick(['web-1', 'db']), vars });
const answer = () => {
  const r = rnd();
  if (r < 0.25) return { missing: true };
  if (r < 0.32) return { error: pick(['AccessDenied: not allowed', 'throttled']) };
  return { ...(chance(0.9) ? { status: pick(['Pending', 'InProgress', 'Delayed', 'Success', 'Success', 'Failed', 'Cancelled', 'TimedOut', 'Cancelling', 'Weird']) } : {}), code: pick([0, 0, 1, 127, -1, 255, 2147483647]), ...(chance(0.8) ? { out: pick(['ok\n', '', 'héllo', 'line1\nline2']) } : {}), ...(chance(0.5) ? { err: pick(['', 'warn', 'boom']) } : {}) };
};
for (let i = 0; i < 60; i++) {
  add({
    op: 'ssmRun', name: pick(['web-1', 'db']), vars: pick(SSMVARS), shell: pick(['posix', 'powershell']),
    sent: pick([{ id: 'cmd-1' }, { id: 'cmd-1' }, { id: 'cmd-1' }, { id: null }, { error: 'InvalidInstanceId: not in SSM' }]),
    answers: Array.from({ length: int(7) }, answer), maxPolls: 1 + int(6),
  });
}
// deterministic runs: two waits, one pending, then Success; and none answering within the polls
add({ op: 'ssmRun', name: 'web-1', vars: { resource_id: 'i-1' }, shell: 'powershell', sent: { id: 'c' }, answers: [{ missing: true }, { missing: true }, { status: 'InProgress', code: 0 }, { status: 'Success', code: 0, out: 'done\n', err: '' }], maxPolls: 80 });
add({ op: 'ssmRun', name: 'web-1', vars: { resource_id: 'i-1' }, shell: 'posix', sent: { id: 'c' }, answers: [], maxPolls: 80 });
const lsItem = (kind) => {
  const x = chance(0.92) ? { name: pick(['petcow-web', 'petcow-db', 'hand-made', 'petcow', 'Petcow-x', 'web']) + int(5) } : {};
  if (chance(0.8)) x.arn = `arn:aws:lightsail:eu-west-1:1:${kind}/${int(1e6)}`;
  if (kind === 'instance') {
    if (chance(0.7)) x.state = chance(0.9) ? { name: pick(['running', 'stopped', 'pending']) } : {};
    if (chance(0.7)) x.blueprintId = pick(['ubuntu_22_04', 'wordpress', 'nodejs']);
    if (chance(0.7)) x.bundleId = pick(['nano_2_0', 'micro_3_0']);
    if (chance(0.7)) x.location = chance(0.9) ? { availabilityZone: pick(['eu-west-1a', 'us-east-1b']), regionName: 'x' } : { regionName: 'x' };
    if (chance(0.6)) x.publicIpAddress = pick(['1.2.3.4', '203.0.113.9']);
    if (chance(0.3)) x.tags = [{ key: 'petcow:managed', value: 'true' }];
  } else if (kind === 'database') {
    if (chance(0.8)) x.engine = pick(['mysql', 'postgres']);
    if (chance(0.7)) x.engineVersion = pick(['8.0.35', '15.4']);
    if (chance(0.7)) x.state = pick(['available', 'creating']);
    if (chance(0.6)) x.relationalDatabaseBlueprintId = pick(['mysql_8_0', 'postgres_15']);
    if (chance(0.6)) x.relationalDatabaseBundleId = pick(['micro_2_0']);
    if (chance(0.6)) x.masterDatabaseName = pick(['app', 'db1']);
    if (chance(0.6)) x.masterUsername = pick(['admin', 'dbuser']);
  } else if (chance(0.85)) {
    x.domainEntries = Array.from({ length: int(5) }, () => ({ ...(chance(0.9) ? { type: pick(['A', 'CNAME', 'MX', 'TXT']) } : {}), ...(chance(0.9) ? { name: pick(['www.example.com', 'example.com', 'mail']) } : {}), ...(chance(0.9) ? { target: pick(['1.2.3.4', 'lb.example.com', '10 mx.example.com']) } : {}) }));
  }
  return x;
};
const lsPages = (kind) => {
  const member = { instance: 'instances', database: 'relationalDatabases', domain: 'domains' }[kind];
  const n = 1 + int(4);
  return Array.from({ length: n }, (_, k) => {
    const p = { [member]: Array.from({ length: int(5) }, () => lsItem(kind)) };
    if (k < n - 1 || chance(0.1)) p.nextPageToken = pick(['t1', 'page-2', '', 'a/b+c=']);
    if (chance(0.06)) return { error: pick(['AccessDeniedException: no', 'throttled']) };
    return p;
  });
};
for (let i = 0; i < 60; i++) {
  const kind = pick(['instance', 'database', 'domain']);
  add({ op: 'lsList', kind, pages: lsPages(kind), mode: pick(['all', 'managed', 'unmanaged']) });
}
add({ op: 'lsList', kind: 'instance', pages: [{ instances: [{ name: 'petcow-a', state: { name: 'running' }, arn: 'arn:1' }, { name: 'b' }, {}], nextPageToken: 'T' }, { instances: [{ name: 'petcow-c' }] }], mode: 'managed' });
add({ op: 'lsList', kind: 'domain', pages: [{ domains: [{ name: 'example.com', domainEntries: [] }], nextPageToken: 'ignored' }], mode: 'all' });

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
