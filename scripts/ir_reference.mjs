// Reference vectors for `e.algo.ir` (L036, the runtime half): run appdor's own workflow IR (src/workflow/ir.js) --
// normalization, traversal, the validator over every step and trigger type, the plugin step registry and the execution
// keys -- over random definitions and write the link fixture tests/selfhost/fixtures/link/algo_ir. The approval routing
// matcher is a real module of appdor's that the validator calls; the fixture's stand-in covers the rule shapes this script
// generates and the reference's own answers decide whether it is right. APPDOR_DIR defaults to D:/repos/appdor. TZ=UTC.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const ir = await import(pathToFileURL(resolve(appdor, 'src/workflow/ir.js')).href);

let seed = 0x1e36;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;

function canon(v) {
  if (v === undefined) return 'undefined';
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

const UUIDS = ['0b4f6c1e-7a52-4c1e-9d3a-1f2e3d4c5b6a', '11111111-2222-3333-4444-555555555555', 'ABCDEF01-2345-6789-ABCD-EF0123456789'];
const ZONES = ['UTC', 'Europe/Sofia', 'America/New_York', 'Mars/Phobos', ''];
const CRONS = ['*/5 * * * *', '0 9 * * 1-5', '61 * * * *', 'not a cron', '0 0 1 1 *'];
const POLICIES = [undefined, 'any', 'all', 'first-response', 'all-must-approve', 'weird', 'quorum(2 of 3)', { quorum: 2 }, 'Any'];
const EVENT_TYPES = ['order.created', 'billing:invoice.paid', 'Bad Type', '9x', 'a.b.c', 'a:b:c', '', 'a..b', 'x-y_z'];

const idPool = ['s1', 's2', 's3', 's4', 'alpha', 'beta', 'gamma', 'x-1', 'y_2'];
function stepId() {
  const r = rnd();
  if (r < 0.03) return undefined;
  if (r < 0.06) return 'bad id!';
  if (r < 0.14) return pick(idPool);
  return `st${int(10000)}`;
}

function approvalConfig() {
  const c = {};
  if (chance(0.8)) c.approvers = Array.from({ length: int(3) + (chance(0.8) ? 1 : 0) }, () => chance(0.8) ? pick(UUIDS) : pick(['', 'nobody', 'undefined', null, 7]));
  if (chance(0.8)) c.table = 'tbl';
  if (chance(0.8)) c.record = '{{ trigger.id }}';
  if (chance(0.3)) c.rule = pick(['any', 'all', 'some', 7]);
  if (chance(0.25)) c.evidenceFields = pick([[], [UUIDS[0]], [UUIDS[0], UUIDS[0]], 'x', [UUIDS[1], 'nope'], Array.from({ length: 33 }, (_, i) => `00000000-0000-0000-0000-${String(i).padStart(12, '0')}`), null]);
  if (chance(0.4)) {
    c.routing = pick([[], 'x', '', null, [{ approvers: [pick(UUIDS)], policy: pick(POLICIES) }],
      [{ approvers: [], policy: pick(POLICIES) }], [{ approvers: [pick(UUIDS)], definition: { steps: [] }, policy: pick(POLICIES) }],
      [{ approvers: [pick(UUIDS)] }, { approvers: [], policy: 'all' }], [7, null]]);
  }
  return c;
}

function configFor(type) {
  const good = chance(0.7);
  switch (type) {
    case 'if': return good ? { condition: '{{ x }}' } : {};
    case 'foreach': return good ? { items: '{{ list }}', as: 'item' } : {};
    case 'fork': return good ? pick([{}, { join: 'all' }, { join: 'race' }]) : { join: pick(['both', 'ANY']) };
    case 'delay': return good ? pick([{ ms: 100 }, { until: '2026-01-01' }, { duration: 'PT5M' }, { ms: 0 }]) : {};
    case 'wait-signal': return good ? { signal: 'go' } : {};
    case 'approval': return good ? { approvers: [UUIDS[0]], table: 't', record: 'r' } : approvalConfig();
    case 'webhook': return good ? { url: 'https://example.com' } : {};
    case 'emit-event': {
      const c = { eventType: pick(EVENT_TYPES), schemaVersion: pick([1, 2, '3', 0, -1, '1.5', 'x', null, true]), payload: pick([{ a: 1 }, [], 'x', null]) };
      if (chance(0.3)) c.retainDays = pick([1, 365, 3650, 3651, 0, 'x', '2.5']);
      if (chance(0.15)) delete c[pick(['eventType', 'schemaVersion', 'payload'])];
      return c;
    }
    case 'connector': return good ? { channel: 'slack', action: 'post' } : pick([{ channel: 'slack' }, { action: 'post' }, {}]);
    case 'python': return good ? { source: 'print(1)' } : {};
    case 'create-record': case 'update-record': case 'delete-record': {
      const c = {};
      if (chance(0.8)) c.table = 'tbl';
      if (chance(0.7)) c.values = pick([{ A: '{{ x }}' }, {}, [], [{ key: 'A', value: 'b' }], [{ key: '', value: '' }], null, 'x']);
      return c;
    }
    case 'run-workflow': return good ? { workflowId: 'wf-9' } : {};
    default: return chance(0.2) ? { note: 'x' } : {};
  }
}

const LEAF = ['set', 'transform', 'parse', 'serialize', 'query', 'webhook', 'emit-event', 'connector', 'create-record', 'update-record',
  'delete-record', 'email', 'notify', 'python', 'run-workflow', 'log', 'delay', 'wait-signal', 'approval', 'stop', 'fail'];

function makeStep(depth = 0) {
  const nest = depth < 2 && chance(0.35);
  let type = pick(nest ? ['if', 'case', 'foreach', 'fork', 'try'] : LEAF);
  if (chance(0.03)) type = pick(['teleport', '', 'Webhook']);
  const s = {};
  const id = stepId();
  if (id !== undefined) s.id = id;
  s.type = type;
  if (chance(0.5)) s.name = pick(['Do thing', 'Another', '']);
  if (chance(0.7)) s.config = configFor(type);
  if (chance(0.1)) s.retries = pick([1, 3, 0]);
  if (chance(0.1)) s.continueOnError = chance(0.5);
  if (chance(0.1)) s.if = '{{ ok }}';
  const kids = () => Array.from({ length: int(3) }, () => makeStep(depth + 1));
  if (type === 'if') { if (chance(0.8)) s.then = kids(); if (chance(0.5)) s.else = kids(); }
  if (type === 'foreach' || type === 'try') { if (chance(0.9)) s.steps = kids(); if (type === 'try' && chance(0.6)) s.catch = kids(); }
  if (type === 'case') {
    if (chance(0.85)) s.cases = Array.from({ length: int(3) + (chance(0.8) ? 1 : 0) }, () => ({ when: chance(0.8) ? '{{ a == 1 }}' : '', name: chance(0.5) ? 'c' : undefined, steps: chance(0.9) ? kids() : undefined }));
    if (chance(0.4)) s.default = kids();
  }
  if (type === 'fork') {
    if (chance(0.85)) s.branches = Array.from({ length: int(3) + (chance(0.8) ? 1 : 0) }, (_, i) => ({ name: `b${i}`, steps: chance(0.9) ? kids() : undefined }));
  }
  return s;
}

function makeTrigger() {
  if (chance(0.05)) return undefined;
  const type = chance(0.05) ? pick(['teleport', 7, '']) : pick(['manual', 'webhook', 'table-change', 'schedule', 'metadata-change', 'platform-event', 'button', 'workflow-call', 'form-submitted']);
  const t = {};
  if (type !== '') t.type = type;
  if (type === 'schedule') {
    const config = {};
    if (chance(0.85)) config.cron = pick(CRONS);
    if (chance(0.5)) config.timezone = pick(ZONES);
    if (chance(0.4)) config.catchUp = pick(['one', 'skip', 'all', 'sometimes']);
    t.config = config;
  } else if (type === 'metadata-change') {
    const config = {};
    if (chance(0.8)) config.objects = pick([['page'], [], 'page', ['page', 'form'], ['table']]);
    if (chance(0.5)) config.events = pick([['insert'], ['bogus'], [], ['update', 'delete', 'restore']]);
    t.config = config;
  } else if (type === 'platform-event') {
    const config = {};
    if (chance(0.8)) config.eventType = pick(EVENT_TYPES);
    if (chance(0.8)) config.schemaVersion = pick([1, 2, '3', 0, 'x', '1.5']);
    t.config = config;
  } else if (chance(0.5)) t.config = { a: 1 };
  if (chance(0.15)) t.filter = { field: 'x' };
  return t;
}

function makeDefinition() {
  const d = {};
  if (chance(0.85)) d.id = pick(['wf-1', 'wf-2']);
  if (chance(0.9)) d.name = pick(['Onboarding', 'Sync', 'Ünï']);
  if (chance(0.5)) d.version = pick([1, 2, 5, 0, null]);
  if (chance(0.2)) d.enabled = pick([true, false, 0, 'no']);
  const t = makeTrigger();
  if (t !== undefined) d.trigger = t;
  if (chance(0.95)) d.steps = Array.from({ length: int(4) + (chance(0.9) ? 1 : 0) }, () => makeStep(0));
  if (chance(0.3)) d.inputs = pick([{ n: 'number' }, {}, null]);
  if (chance(0.3)) d.settings = pick([{ maxSteps: 5 }, { onFailure: 'continue', retryPolicy: { attempts: 1 } }, {}, null]);
  return d;
}

function scenario() {
  const ops = [];
  const out = [];
  const note = (op, text) => { ops.push(op); out.push(text); };
  // The plugin registry is module-level state in the reference: clean it between scenarios.
  for (const p of ir.listPluginStepTypes()) ir.unregisterPluginStepType(p.type);
  const steps = int(5) + 3;
  for (let i = 0; i < steps; i++) {
    const r = rnd();
    const def = makeDefinition();
    if (r < 0.2) note({ op: 'normalize', def }, canon(ir.normalizeWorkflow(def)));
    else if (r < 0.32) {
      const visits = [];
      ir.walkSteps(def.steps, (s, path) => visits.push({ id: s.id ?? null, path: path.map((x) => x ?? '') }));
      note({ op: 'walk', def }, canon(visits));
    } else if (r < 0.4) note({ op: 'ids', def }, canon(ir.collectStepIds(def).map((x) => x ?? '')));
    else if (r < 0.75) note({ op: 'validate', def }, canon(ir.validateWorkflow(def)));
    else if (r < 0.82) {
      const spec = { ns: pick(['acme', 'vendor', '']), id: pick(['tool', 'webhook', 'ping', '']), label: pick(['Tool', '', undefined]) };
      const res = ir.registerPluginStepType(spec.ns, spec.id, spec.label === undefined ? {} : { label: spec.label });
      note({ op: 'register', ...spec }, canon(res));
    } else if (r < 0.88) {
      const list = ir.listPluginStepTypes();
      const key = list.length && chance(0.7) ? pick(list).type : 'none.none';
      note({ op: 'unregister', key }, canon(ir.unregisterPluginStepType(key)));
    } else if (r < 0.94) {
      const name = pick([...Object.keys(ir.STEP_TYPES), 'nope', ...ir.listPluginStepTypes().map((p) => p.type)]);
      note({ op: 'step', name }, canon(ir.stepType(name)));
    } else {
      const frames = Array.from({ length: int(3) }, () => pick([ir.loopFrame('s1', int(5)), ir.forkFrame('s2', 'left'), ir.loopFrame('s3', 0)]));
      const id = pick(['s1', 'alpha']);
      note({ op: 'key', id, frames }, canon(ir.executionKey(id, frames)));
    }
  }
  return { ops, e: out.join('\n') };
}

// A few fixed cases first so the catalogue and the helpers are exercised whatever the generator draws.
const cases = [];
for (let i = 0; i < 180; i++) cases.push(JSON.stringify(scenario()));

const chunks = [];
const size = 3;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}(), &clock) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'ir_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_ir/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_ir`);
