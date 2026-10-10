// Vectors for `x.cloud.manifest` (L047): Petcow's own `provider/manifest.rs` (compiled with the thin shims of
// `restref.exe`) over random and deliberately broken resource manifests, written as the link fixture
// tests/selfhost/fixtures/link/x_cloud_manifest. The manifests are emitted as JSON, which is YAML's flow style, so
// the two YAML readers see the same structure. Usage: node scripts/manifest_vectors.mjs REFERENCE_EXE
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
let seed = 0x2b9c;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

const CLOUDS = [['gcp', 'gcp'], ['azure', 'azure'], ['ibm', 'ibm'], ['oci', 'oci'], ['ali', 'aliyun']];
const LEAF = ['dns_zone', 'vnet', 'bucket', 'vpc', 'topic', 'queue', 'ecs_instance'];

function rest(prefix, cloud) {
  const r = { type: `${prefix}.${pick(LEAF)}`, cloud };
  if (chance(0.7)) r.create_method = pick(['PUT', 'POST', 'PATCH']);
  r.item_url = pick(['https://x/v1/projects/{project}/zones/{name}', 'https://x/{name}', 'https://m/{subscription}/vnets/{name}']);
  r.list_url = pick(['https://x/v1/projects/{project}/zones', 'https://x/', 'https://m/{subscription}/vnets']);
  if (chance(0.4)) r.create_url = 'https://x/v1/projects/{project}/zones';
  if (chance(0.4)) r.list_items_field = pick(['items', 'data.items', '', 'Vpcs.Vpc']);
  if (chance(0.3)) r.real_id_field = pick(['id', 'selfLink', 'datasetReference.datasetId']);
  if (chance(0.5)) r.marker = { field: pick(['labels', 'tags']), managed_key: 'petcow_managed', name_key: 'petcow_name' };
  if (chance(0.6)) r.copy_attrs = Object.fromEntries(Array.from({ length: 1 + int(3) }, () => [pick(['zeta', 'alpha', 'dns_name', 'cidr', 'beta']), pick(['dnsName', 'cidrBlock', 'description', 'meta.x'])]));
  if (chance(0.3)) r.output_attrs = Array.from({ length: 1 + int(2) }, () => pick(['selfLink', 'state']));
  if (chance(0.4)) r.name_field = pick(['name', 'displayName', 'meta.x']);
  if (chance(0.3)) r.update_method = 'PATCH';
  if (chance(0.2)) r.update_mask = 'description,labels';
  if (chance(0.3)) r.operation_url = 'https://x/v1/{operation}';
  if (chance(0.2)) r.operation_timeout_minutes = pick([5, 30, 120]);
  if (chance(0.2)) r.operation_style = pick(['lro', 'compute_self_link', 'work_request']);
  if (chance(0.15)) r.create_wrapper = chance(0.5) ? { key: 'cluster' } : { key: 'instance', id_field: 'instanceId' };
  if (chance(0.15)) r.name_value_template = 'projects/{project}/queues/{name}';
  if (chance(0.1)) r.server_named = true;
  if (chance(0.1)) r.name_suffix = '/';
  if (chance(0.15)) r.read_method = 'POST';
  if (chance(0.15)) r.list_method = 'POST';
  if (chance(0.15)) r.delete_method = 'POST';
  if (chance(0.15)) r.delete_url = 'https://x/del/{name}';
  if (chance(0.2)) r.parent = chance(0.5) ? { type: 'gcp.dataplex_zone', url_var: 'zone' } : { type: 'ali.vpc', url_var: 'vpcId', parent_by_id: true };
  if (chance(0.2)) r.create_body_vars = { compartmentId: '{compartment}', 'metadata.region': '{region}' };
  if (chance(0.1) && !r.marker) r.observed_name_field = 'name';
  return r;
}

function rpc(prefix, cloud, pair) {
  const create = { action: 'CreateVpc', params: { RegionId: '{region}', VpcName: '{name}' } };
  if (pair) { create.params['Tag.1.Key'] = 'petcow_managed'; create.params['Tag.1.Value'] = 'true'; create.params['Tag.2.Key'] = 'petcow_name'; create.params['Tag.2.Value'] = '{name}'; }
  const r = {
    type: `${prefix}.${pick(LEAF)}`, cloud,
    rpc: { endpoint: pick(['https://vpc.{region}.aliyuncs.com/', 'https://ecs.aliyuncs.com/?x=1']), version: pick(['2016-04-28', '2014-05-26']), create,
      read: { action: 'DescribeVpcAttribute', params: { VpcId: '{real_id}' } }, list: { action: 'DescribeVpcs' }, delete: { action: 'DeleteVpc', params: { VpcId: '{real_id}' } } },
  };
  if (chance(0.4)) r.rpc.method = pick(['GET', 'POST']);
  if (chance(0.4)) r.rpc.update = { action: 'ModifyVpcAttribute', params: { VpcId: '{real_id}' } };
  if (pair) r.marker = { field: 'Tags.Tag', managed_key: 'petcow_managed', name_key: 'petcow_name', shape: 'pair_list', key_field: 'TagKey', value_field: 'TagValue' };
  else if (chance(0.4)) r.marker = { field: 'labels', managed_key: 'petcow_managed', name_key: 'petcow_name' };
  if (chance(0.3)) r.copy_attrs = { cidr: 'CidrBlock' };
  if (chance(0.3)) r.update_method = 'PATCH';
  return r;
}

const cases = [];
const add = (resources, raw) => cases.push({ op: 'manifest', yaml: raw !== undefined ? raw : JSON.stringify({ resources }) });

for (let i = 0; i < 40; i++) {
  const [p, c] = pick(CLOUDS);
  add([rest(p, c)]);
}
for (let i = 0; i < 20; i++) add(Array.from({ length: 1 + int(3) }, () => { const [p, c] = pick(CLOUDS); return rest(p, c); }));
for (let i = 0; i < 20; i++) add([rpc('ali', 'aliyun', chance(0.6))]);

// deliberately broken
const broken = [];
const brk = (f) => { const [p, c] = pick(CLOUDS); const r = rest(p, c); f(r, p, c); broken.push([r]); };
brk((r) => { r.cloud = 'aws'; });
brk((r) => { r.cloud = pick(['gcp', 'ibm']); r.type = 'ali.vpc'; });
brk((r) => { delete r.item_url; });
brk((r) => { delete r.list_url; });
brk((r) => { r.marker = { field: 'labels', managed_key: 'a', name_key: 'b' }; r.observed_name_field = 'name'; });
brk((r) => { r.copy_attrs = { x: 'target' }; r.create_body_vars = { target: '{region}' }; });
brk((r) => { r.name_field = 'nf'; r.create_body_vars = { nf: '{region}' }; });
brk((r) => { r.marker = { field: 'labels', managed_key: 'a', name_key: 'b', key_field: 'K' }; });
brk((r) => { r.marker = { field: 'Tags.Tag', managed_key: 'a', name_key: 'b', shape: 'pair_list', value_field: 'V' }; });
brk((r) => { r.marker = { field: 'Tags.Tag', managed_key: 'a', name_key: 'b', shape: 'pair_list', key_field: 'K' }; });
brk((r) => { r.marker = { field: 'Tags.Tag', managed_key: 'a', name_key: 'b', shape: 'pair_list', key_field: 'K', value_field: 'V' }; });
brk((r) => { r.rpc = rpc('ali', 'aliyun', false).rpc; });
brk((r) => { r.bogus = 1; });
brk((r) => { r.operation_style = 'weird'; });
brk((r) => { r.server_named = 'yes'; });
brk((r) => { r.operation_timeout_minutes = 'x'; });
for (const b of broken) add(b);
function rpcBreak(f) { const r = rpc('ali', 'aliyun', true); f(r); add([r]); }
rpcBreak((r) => { r.rpc.create.params = { RegionId: 'x' }; });
rpcBreak((r) => { delete r.rpc.create.params['Tag.1.Value']; });
rpcBreak((r) => { r.rpc.create.params['Tag.1.Value'] = 'false'; });
rpcBreak((r) => { r.rpc.create.params['Tag.2.Value'] = 'fixed'; });
rpcBreak((r) => { r.rpc.create.params['Tag.1.Extra'] = 'e'; });
rpcBreak((r) => { delete r.rpc.create.params['Tag.1.Key']; r.rpc.create.params.NoDot = 'petcow_managed'; });
rpcBreak((r) => { r.rpc.create.action = 'Create&Evil=1'; });
rpcBreak((r) => { r.rpc.version = '2016 04'; });
rpcBreak((r) => { r.rpc.create.params['bad key'] = 'v'; });
rpcBreak((r) => { r.rpc.create.params.Name = 'a=b'; });
rpcBreak((r) => { r.rpc.create.params.Name = 'caf\u00e9'; });
rpcBreak((r) => { r.item_url = 'https://x/{name}'; });
rpcBreak((r) => { r.read_method = 'GET'; });
rpcBreak((r) => { delete r.marker; r.rpc.create.params.Name = '{ok}{x}'; });
add(null, 'resources: 5');
add(null, '[1, 2]');
add(null, '{"resources": [], "extra": 1}');
add(null, '{"resources": []}');
add(null, '{"resources": [{"type": "gcp.x"}]}');
add(null, '{"resources": [{"type": "gcp.x", "cloud": "gcp", "item_url": "u", "list_url": "l"}, {"type": "ali.x", "cloud": "gcp", "item_url": "u", "list_url": "l"}]}');
add(null, '{"resources": [{"type": 5, "cloud": "gcp"}]}');

const exe = process.argv[2] || 'D:/temp/restref/restref.exe';
const out = execFileSync(exe, [], { input: JSON.stringify(cases), maxBuffer: 1 << 28 }).toString();
const answers = JSON.parse(out);
let ok = 0;
const lines = cases.map((c, i) => { if (answers[i].ok) ok++; return JSON.stringify({ ...c, e: answers[i] }); });
const chunks = [];
for (let i = 0; i < lines.length; i += 6) {
  chunks.push(`"${lines.slice(i, i + 6).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'manifest_fixture_template.e'), 'utf8');
const outText = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/x_cloud_manifest/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, outText, 'utf8');
console.log(`${cases.length} cases (${ok} accepted) in ${chunks.length} chunks -> x_cloud_manifest`);
