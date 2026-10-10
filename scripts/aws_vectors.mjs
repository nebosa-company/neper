// Vectors for `x.cloud.aws` and `x.ssh.args` (L048): the pure helpers of Petcow's provider/aws/cloudcontrol.rs and the
// argument builder of transport/ssh.rs (extracted unchanged into `awsref.exe` behind thin shims) over random inputs,
// written as the link fixture tests/selfhost/fixtures/link/x_cloud_aws.
// Usage: node scripts/aws_vectors.mjs REFERENCE_EXE
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x1f55;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const cases = [];
const add = (c) => cases.push(c);

for (const msg of ['ThrottlingException: Rate exceeded', 'Rate exceeded', 'TooManyRequests', 'AccessDenied', '', 'x ThrottlingException y', 'rate exceeded']) add({ op: 'throttle', msg });

function def() {
  const d = { type: `aws.cc.${pick(['s3_bucket', 'logs_stream', 'ec2_vpc', 'ecs_cluster', 'sqs_queue'])}`, cfn_type: pick(['AWS::S3::Bucket', 'AWS::Logs::LogStream', 'AWS::EC2::VPC']) };
  if (chance(0.5)) d.name_property = pick(['BucketName', 'LogStreamName', 'ClusterName']);
  if (chance(0.3)) d.tag_shape = pick(['kv_list', 'map']);
  if (chance(0.2)) d.tag_property = pick(['Tags', 'UserPoolTags']);
  if (chance(0.25)) d.identity_properties = pick([['LogGroupName', 'LogStreamName'], ['FilterName', 'LogGroupName']]);
  if (chance(0.15)) d.derived_attrs = ['Policy'];
  if (chance(0.2)) d.parent = { type: 'aws.cc.logs_log_group', property: 'LogGroupName' };
  return d;
}
const asYaml = (list) => JSON.stringify(list);
for (let i = 0; i < 24; i++) add({ op: 'parseDefs', yaml: asYaml(Array.from({ length: int(4) }, def)) });
for (const y of ['- type: a\n', '[{"type":"a","cfn_type":"X","bogus":1}]', '{"a":1}', '[{"type":"a","cfn_type":"X","tag_shape":"weird"}]', '[{"type":"a"}]', '[]', '[{"type":"a","cfn_type":"X","parent":{"type":"p"}}]']) add({ op: 'parseDefs', yaml: y });
for (let i = 0; i < 20; i++) {
  const mk = () => Array.from({ length: 1 + int(4) }, () => def());
  add({ op: 'merge', defaults: asYaml(mk()), extra: asYaml(mk()) });
}

for (let i = 0; i < 24; i++) {
  const identity = pick([['LogGroupName', 'LogStreamName'], ['FilterName', 'LogGroupName'], ['A', 'B', 'C']]);
  const attrs = {};
  for (const p of identity) if (chance(0.8)) attrs[p] = pick(['grp', 7, true, 'with|pipe', { x: 1 }, [1], null]);
  add({ op: 'compose', identity, nameProperty: pick(identity), name: pick(['petcow-n', 'a/b']), attrs, type: 'aws.cc.logs_stream' });
}
for (const [identity, nameProperty, identifier] of [[['A', 'B'], 'B', 'x|y'], [['A', 'B'], 'A', 'x|y'], [['A', 'B'], 'B', 'x'], [['A', 'B'], 'B', 'x|y|z'], [['A', 'B'], 'C', 'x|y'], [['A'], 'A', 'single'], [['A', 'B'], 'B', '|']]) {
  add({ op: 'nameFrom', identity, nameProperty, identifier });
}

function attrs() {
  const a = {};
  if (chance(0.7)) a.Region = pick(['us', 'eu']);
  if (chance(0.5)) a.Count = int(10);
  if (chance(0.4)) a.Enabled = chance(0.5);
  if (chance(0.3)) a.Nested = { x: 1, y: [1, 2] };
  if (chance(0.3)) a.BucketName = 'user-supplied';
  return a;
}
for (let i = 0; i < 16; i++) add({ op: 'desired', nameProperty: 'BucketName', name: 'petcow-b', attrs: attrs() });
const kvTags = () => Array.from({ length: int(4) }, () => ({ Key: pick(['env', 'team', 'petcow:name', 'petcow:managed']), Value: pick(['prod', 'x', 'hijack', 'true']) }));
const mapTags = () => Object.fromEntries(Array.from({ length: int(4) }, () => [pick(['env', 'team', 'petcow:name', 'petcow:managed']), pick(['prod', 'x', 'hijack', 'true'])]));
for (let i = 0; i < 30; i++) {
  const shape = pick(['kv_list', 'map']);
  const tagProp = pick(['Tags', 'UserPoolTags']);
  const a = attrs();
  if (chance(0.7)) a[tagProp] = shape === 'map' ? (chance(0.9) ? mapTags() : kvTags()) : (chance(0.9) ? kvTags() : mapTags());
  add({ op: 'tagged', name: 'petcow-x', attrs: a, shape, tagProp });
  add({ op: 'patchTagged', name: 'petcow-x', attrs: a, shape, tagProp });
  const stripped = { ...a };
  if (chance(0.5)) {
    stripped[tagProp] = shape === 'map'
      ? { ...mapTags(), 'petcow:managed': 'true', 'petcow:name': 'n' }
      : [...kvTags(), { Key: 'petcow:managed', Value: 'true' }, { Key: 'petcow:name', Value: 'n' }];
  }
  add({ op: 'strip', attrs: stripped, shape, tagProp });
  add({ op: 'managedName', attrs: a, shape, tagProp });
}
for (let i = 0; i < 12; i++) {
  add({ op: 'managedName', attrs: { Tags: [{ Key: 'petcow:managed', Value: pick(['true', 'false']) }, { Key: 'petcow:name', Value: 'petcow-v' }] }, shape: 'kv_list', tagProp: 'Tags' });
}
for (let i = 0; i < 14; i++) {
  const a = attrs();
  add({ op: 'patch', nameProperty: chance(0.7) ? 'BucketName' : undefined, attrs: a });
  add({ op: 'patchSkipping', identity: pick([['Region', 'Count'], ['LogGroupName'], []]), attrs: a });
}
for (const props of [undefined, '{"A":1}', '{"A":null}', '"scalar"', '[1]', '{bad', '{"Tags":[{"Key":"k"}]}']) {
  add({ op: 'hasKey', props, key: pick(['A', 'Tags', 'B']) });
  add({ op: 'parseProps', props });
}

const HOSTVARS = [{}, { ssh_user: 'deploy' }, { ansible_user: 'ec2-user', ssh_port: 2222 }, { ssh_private_key_file: '/keys/id', user: 'u' }, { ansible_ssh_private_key_file: '/k/a', ssh_key: '/k/b' },
  { ssh_strict_host_key_checking: false }, { ssh_strict_host_key_checking: 'No' }, { ssh_strict_host_key_checking: ' YES ' }, { ssh_strict_host_key_checking: 'maybe' }, { ssh_known_hosts: '/etc/kh' },
  { known_hosts: '/kh2', ssh_known_hosts: '  ' }, { ssh_port: '  ', ansible_port: 22 }, { port: 8022 }, { ssh_user: '', ansible_user: 'fallback' }, { ssh_user: 7 }, { ssh_port: 1.5 }];
for (const vars of HOSTVARS) {
  for (const shell of ['posix', 'powershell']) add({ op: 'ssh', host: { name: 'h', address: pick(['10.0.0.5', 'host.example', 'fe80::1']), vars }, command: pick(['uptime', 'echo "a b"', 'Get-Process']), shell });
}

const exe = process.argv[2] || 'D:/temp/awsref/awsref.exe';
const answers = JSON.parse(execFileSync(exe, [], { input: JSON.stringify(cases), maxBuffer: 1 << 28 }).toString());
const bs = String.fromCharCode(92);
const lines = cases.map((c, i) => JSON.stringify({ ...c, e: answers[i] }));
const chunks = [];
for (let i = 0; i < lines.length; i += 10) {
  chunks.push('"' + lines.slice(i, i + 10).map((l) => l.split(bs).join(bs + bs).split('"').join(bs + '"')).join(bs + 'n') + bs + 'n"');
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'aws_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_cloud_aws/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> x_cloud_aws`);
