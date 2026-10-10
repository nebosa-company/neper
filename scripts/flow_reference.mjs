// Reference vectors for `e.algo.flow` (L036, the runtime half): run appdor's own inline flow interpreter
// (src/workflow/flow-engine.js, with the real formula engine) over random flows, triggers, effect plans and options, and
// write the link fixture tests/selfhost/fixtures/link/algo_flow. The Neper side stands in for the effect handlers, the
// dataset and the host's filter engine; the reference's run log decides whether the port is right.
// Not generated: filter trees, `script` and `ai` steps (injected by design), `refs`.
// APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const { runFlow } = await import(pathToFileURL(resolve(appdor, 'src/workflow/flow-engine.js')).href);

let seed = 0x1f10;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

function canon(v) {
  const walk = (x) => {
    if (Array.isArray(x)) return x.map(walk);
    if (x && typeof x === 'object') {
      const out = {};
      for (const k of Object.keys(x).sort()) if (x[k] !== undefined) out[k] = walk(x[k]);
      return out;
    }
    return x;
  };
  return JSON.stringify(walk(v));
}

let nextId = 0;
let varsSet = [];
let findIds = [];
const newId = (p) => `${p}${nextId++}`;

const FORMULAS = ['{n} + 1', '{n} * 2', '{s} & "x"', 'IF({flag}, "y", "n")', '{n} - {x}', 'LEN({s})', '{n} > 2', 'NOT({flag})', '{missing}', 'MAX({n}, 3)'];
const CONDITIONS = ['{n} > 2', '{n} = 0', '{flag}', '{s} = "a"', 'AND({n} > 0, {flag})', 'NOT({flag})', '{x} > 1', '{missing}', '{n} >= 1', 'OR({flag}, {n} > 4)', '1', '0', '""', '{s}'];

function genBinding(inLoop) {
  const paths = ['trigger.n', 'trigger.s', 'trigger.flag', 'trigger.items', 'trigger.rows', 'trigger.rows.0.x', 'triggerMeta.correlationId', 'depth', 'nothing.here', 'trigger.nested.deep'];
  for (const v of varsSet) paths.push(`vars.${v}`);
  for (const f of findIds) { paths.push(`steps.${f}.count`); paths.push(`steps.${f}.records`); paths.push(`steps.${f}.records.0.id`); }
  if (inLoop) paths.push('current', 'current.x', 'current.y', 'index');
  return pick(paths);
}

function genSpec(inLoop) {
  const r = rnd();
  if (r < 0.3) return { literal: pick([1, 0, 7, 'a', 'text', true, false, null, [1, 2], ['a', 'b'], { k: 'v' }, '']) };
  if (r < 0.65) return { binding: genBinding(inLoop) };
  if (r < 0.9) return { formula: pick(FORMULAS) };
  return pick([5, 'raw', true]);
}

function genCond() {
  const r = rnd();
  if (r < 0.7) return pick(CONDITIONS);
  return { expr: pick(CONDITIONS) };
}

function genValues() {
  const out = {};
  const n = int(3);
  for (let i = 0; i < n; i++) out[pick(['Name', 'Title', 'status', 'apiKey', 'token', 'Count'])] = genSpec(true);
  return out;
}

function genStep(depth, inLoop) {
  const type = pick(['condition', 'condition', 'branch', 'loop', 'find', 'set', 'set', 'create', 'update', 'delete', 'email', 'notification', 'http', 'run-workflow', 'webhook']);
  const id = chance(0.8) ? newId('s') : undefined;
  const s = { type };
  if (id) s.id = id;
  const sub = (n) => Array.from({ length: n }, () => genStep(depth + 1, inLoop));
  switch (type) {
    case 'condition':
      s[pick(['filter', 'expr', 'condition'])] = genCond();
      if (chance(0.4)) s.onFalse = pick(['stop', 'continue']);
      break;
    case 'branch':
      s.branches = Array.from({ length: int(3) + 1 }, () => ({ ...(chance(0.8) ? { name: newId('b') } : {}), ...(chance(0.9) ? { [pick(['filter', 'expr'])]: genCond() } : {}), steps: depth < 2 ? sub(int(3)) : [] }));
      if (chance(0.5)) s.default = depth < 2 ? sub(int(2)) : [];
      break;
    case 'loop':
      s.list = chance(0.9) ? genSpec(inLoop) : undefined;
      if (chance(0.4)) s.cap = pick([1, 2, 3]);
      s.steps = depth < 2 ? Array.from({ length: int(3) + 1 }, () => genStep(depth + 1, true)) : [];
      break;
    case 'find':
      s.table = pick(['tasks', 'users', 'none']);
      if (chance(0.3)) s.limit = pick([1, 2]);
      if (id) findIds.push(id);
      break;
    case 'set':
      s.name = pick(['v0', 'v1', 'v2', 'n']);
      s.value = genSpec(inLoop);
      varsSet.push(s.name);
      break;
    case 'create':
    case 'update':
    case 'delete':
      s.table = 'tasks';
      s.values = genValues();
      if (chance(0.3)) s.target = genSpec(inLoop);
      break;
    case 'email':
    case 'notification':
    case 'http':
      s[chance(0.7) ? 'config' : 'payload'] = { to: genSpec(inLoop), ...(chance(0.5) ? { body: genSpec(inLoop) } : {}), ...(chance(0.4) ? { 'API-Key': pick([{ literal: 'k1' }, { formula: '{n} + 1' }]) } : {}) };
      if (chance(0.3)) s.retries = pick([1, 2, 3, 5]);
      break;
    case 'run-workflow':
      s.workflowId = pick(['wf-a', 'wf-b']);
      s.params = { p: genSpec(inLoop) };
      break;
    default:
      break;
  }
  return s;
}

function genPlan() {
  const plan = {};
  const handler = (name, extra) => { if (chance(0.8)) plan[name] = { ...extra, ...(chance(0.25) ? { failFirst: pick([1, 2, 5]) } : {}), ...(chance(0.2) ? { permanent: true } : {}), ...(chance(0.2) ? { code: 'permission_denied' } : {}) }; };
  handler('findRecords', { records: pick([[], [{ id: 'r1', x: 1 }], [{ id: 'r1', x: 1 }, { id: 'r2', x: 3, y: 'b' }]]) });
  handler('createRecord', chance(0.3) ? { noId: true } : {});
  handler('updateRecord', chance(0.3) ? { noId: true } : {});
  handler('deleteRecord', chance(0.3) ? { noId: true } : {});
  handler('email', { ...(chance(0.3) ? { delivered: false } : {}), ...(chance(0.3) ? { withId: true } : {}) });
  handler('notify', {});
  handler('http', {});
  handler('runWorkflow', { status: pick(['success', 'failed', 'filtered']), ...(chance(0.2) ? { nullResult: true } : {}) });
  return plan;
}

function scenario() {
  nextId = 0;
  varsSet = [];
  findIds = [];
  const steps = Array.from({ length: int(5) + 1 }, () => genStep(0, false));
  const watched = chance(0.15);
  const trig = { type: pick(['record.created', 'record.updated']) };
  if (chance(0.2)) trig.filter = pick(CONDITIONS.filter((c) => !c.includes('{x}')));
  if (watched) trig.watchedFields = ['n', 'flag'];
  const flow = { id: 'flow-1', ...(chance(0.7) ? { name: 'F' } : {}), ...(chance(0.15) ? { enabled: false } : {}), ...(chance(0.8) ? { trigger: trig } : {}), steps };
  const record = { n: pick([0, 1, 3, 5]), s: pick(['a', 'b', '']), flag: chance(0.5), items: pick([[], [1, 2], [1, 2, 3, 4]]), rows: pick([[], [{ x: 1, y: 'a' }], [{ x: 1, y: 'a' }, { x: 4, y: 'b' }, { x: 0 }]]), nested: { deep: 'd' } };
  const trigger = { [pick(['record', 'record', 'fields'])]: record, ...(chance(0.5) ? { meta: { correlationId: 'c1' } } : {}), ...(watched || chance(0.1) ? { changed: pick([['n'], ['s'], ['flag', 's']]) } : {}) };
  const options = {
    ...(chance(0.3) ? { dryRun: pick([{ create: true }, { email: true, http: true }, { update: true, delete: true, notification: true }]) } : {}),
    ...(chance(0.3) ? { stepBudget: pick([2, 3, 6, 12]) } : {}),
    ...(chance(0.25) ? { onFailure: 'continue' } : {}),
    ...(chance(0.15) ? { errorBranch: [{ id: 'eb', type: 'set', name: 'err', value: { literal: 'handled' } }] } : {}),
    ...(chance(0.2) ? { depth: pick([0, 2, 3, 4]) } : {}),
    ...(chance(0.1) ? { maxCascadeDepth: pick([0, 1]) } : {}),
    ...(chance(0.1) ? { force: true } : {}),
    ...(chance(0.2) ? { tenantId: 't-1' } : {}),
    ...(chance(0.4) ? { dataset: { tasks: [{ id: 'd1', x: 2 }, { id: 'd2', x: 5 }, { id: 'd3', x: 7 }] } } : {}),
  };
  return { flow, trigger, options, plan: genPlan() };
}

async function execute(spec) {
  const counts = {};
  const effects = {};
  const wrap = (name, make) => {
    effects[name] = async (...args) => {
      counts[name] = (counts[name] || 0) + 1;
      const n = counts[name];
      const p = spec.plan[name];
      if (n <= (p.failFirst || 0)) {
        const e = new Error(`${name} failed ${n}`);
        if (p.permanent) e.permanent = true;
        if (p.code) e.code = p.code;
        throw e;
      }
      return make(p, n, ...args);
    };
  };
  const has = (n) => spec.plan[n] !== undefined;
  if (has('findRecords')) wrap('findRecords', (p) => p.records);
  if (has('createRecord')) wrap('createRecord', (p, n, table, values) => ({ ...(p.noId ? {} : { id: `c${n}` }), table, values }));
  if (has('updateRecord')) wrap('updateRecord', (p, n, table, target, values) => ({ ...(p.noId ? {} : { id: `u${n}` }), table, target, values }));
  if (has('deleteRecord')) wrap('deleteRecord', (p, n, table, target) => ({ ...(p.noId ? {} : { id: `d${n}` }), table, target }));
  if (has('email')) wrap('email', (p, n, payload) => ({ ...(p.withId ? { id: `e${n}` } : {}), delivered: p.delivered !== false, to: payload.to, apiKey: 'k', messageId: `m${n}` }));
  if (has('notify')) wrap('notify', (p, n, payload) => ({ delivered: true, payload }));
  if (has('http')) wrap('http', (p, n, payload) => ({ status: 200, body: payload, authorization: 'x' }));
  if (has('runWorkflow')) wrap('runWorkflow', (p, n, id, params, depth) => (p.nullResult ? null : { status: p.status, id, params, depth }));
  const res = await runFlow(spec.flow, spec.trigger, { ...spec.options, effects });
  return canon(res);
}

const cases = [];
const statuses = {};
for (let i = 0; i < 400; i++) {
  const spec = scenario();
  const e = await execute(spec);
  const st = JSON.parse(e).status;
  statuses[st] = (statuses[st] || 0) + 1;
  cases.push(JSON.stringify({ flow: spec.flow, trigger: spec.trigger, options: spec.options, plan: spec.plan, e }));
}

const chunks = [];
const size = 8;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'flow_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_flow/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_flow`, statuses);
