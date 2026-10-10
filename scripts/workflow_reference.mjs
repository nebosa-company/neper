// Reference vectors for `e.algo.workflow` (L036, the runtime half): run appdor's own durable interpreter
// (src/workflow/runtime.js, with the real Jinja engine and trace redaction) over random workflows, triggers, effect
// plans and operator actions between executions (a signal delivered, the clock moved, a pause or cancel requested), and
// write the link fixture tests/selfhost/fixtures/link/algo_workflow. The Neper side stands in for what is injected --
// templates are literals and `{{ dotted.path }}` references -- and the reference's answers decide whether it is right.
// APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const rt = await load('src/workflow/runtime.js');
const j = await load('src/workflow/journal.js');

let seed = 0x5e36;
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

const UUID = '0b4f6c1e-7a52-4c1e-9d3a-1f2e3d4c5b6a';
const EFFECTS = ['webhook', 'email', 'notify', 'create-record', 'update-record', 'delete-record', 'connector', 'python', 'mcpTool', 'run-workflow', 'transform', 'query', 'emit-event'];
const HANDLED = [...EFFECTS, 'approval', 'checkApprovalGate'];

let nextId = 0;
const sid = () => `s${++nextId}`;

const TEXT = ['plain', 'hello {{ trigger.name }}', '{{ trigger.name }}', '{{ trigger.n }}', '{{ trigger.ok }}', '{{ vars.x }}', '{{ steps.s1.x }}', '{{ trigger.missing }}', '{{ trigger.nested.deep }}', 'n={{ trigger.n }}!'];
const COND = ['trigger.ok', '{{ trigger.ok }}', 'trigger.n', 'trigger.missing', 'vars.flag', 'false', 'true', 'trigger.items', 'trigger.empty', 'trigger.name', 'trigger.zero'];

function effectConfig(type) {
  switch (type) {
    case 'webhook': return { url: pick(['https://example.com/{{ trigger.name }}', 'https://hooks.example.org/x', 'http://localhost:8080/x', 'https://svc.internal/y', 'https://thing.test/z', '']), method: pick(['POST', 'get', undefined]), body: pick([{ n: '{{ trigger.n }}' }, undefined]) };
    case 'email': return { to: pick(['a@x.com', '{{ trigger.name }}']), subject: pick(['Hi', '{{ trigger.name }}']) };
    case 'notify': return pick([{ to: 'owner' }, { to: '' }, {}]);
    case 'create-record': return { table: 'tbl', values: { A: '{{ trigger.n }}' } };
    case 'update-record': return { table: 'tbl', id: '{{ trigger.name }}', values: { A: 1 } };
    case 'delete-record': return { table: 'tbl', target: 'r1' };
    case 'connector': return { channel: 'slack', action: 'post', text: '{{ trigger.name }}' };
    case 'python': return { source: 'print(1)' };
    case 'mcpTool': return { connectionId: 'c1', tool: 't1', arguments: { q: '{{ trigger.name }}' } };
    case 'run-workflow': return { workflowId: 'wf-sub', mode: 'async' };
    default: return { note: '{{ trigger.name }}' };
  }
}

function genStep(depth = 0) {
  const nest = depth < 2 && chance(0.35);
  const type = nest ? pick(['if', 'case', 'foreach', 'try']) : pick(['set', 'set', 'log', 'log', ...EFFECTS, 'stop', 'fail', 'delay', 'wait-signal', 'approval']);
  const s = { id: sid(), type, config: {} };
  const kids = () => Array.from({ length: int(3) }, () => genStep(depth + 1));
  switch (type) {
    case 'set': s.config = pick([{ name: 'x', value: pick(['v', 7, true, '{{ trigger.n }}']) }, { name: 'flag', value: chance(0.5) }, { name: 'x', expression: pick(['trigger.name', '{{ trigger.nested }}']) }]); break;
    case 'log': s.config = { message: pick(TEXT) }; break;
    case 'if': s.config = { condition: pick(COND) }; if (chance(0.8)) s.then = kids(); if (chance(0.6)) s.else = kids(); break;
    case 'case':
      s.cases = [{ when: pick(COND), name: pick(['a', 'b']), steps: kids() }, { when: pick(COND), steps: kids() }];
      if (chance(0.5)) s.default = kids();
      break;
    case 'foreach': s.config = { items: pick(['{{ trigger.items }}', '{{ trigger.nested }}', '{{ trigger.name }}', '{{ trigger.missing }}', '{{ trigger.empty }}']), as: pick(['it', undefined]), cap: pick([undefined, 2, 100]) }; s.steps = kids(); break;
    case 'try': s.steps = [...kids(), chance(0.7) ? { id: sid(), type: 'fail', config: { message: 'boom {{ trigger.n }}' } } : { id: sid(), type: 'log', config: { message: 'ok' } }]; if (chance(0.8)) s.catch = kids(); break;
    case 'stop': s.config = pick([{}, { reason: 'enough' }]); break;
    case 'fail': s.config = pick([{}, { message: 'nope {{ trigger.name }}' }]); break;
    case 'delay': s.config = pick([{ ms: 100 }, { duration: '2s' }, { duration: 'soon' }, { until: '2026-01-01T00:00:00Z' }, { until: 'not a date' }, { ms: 0 }, {}]); break;
    case 'wait-signal': s.config = { signal: 'go', ...(chance(0.5) ? { timeout: pick(['1h', '30 minutes', 5000]) } : {}), ...(chance(0.4) ? { timeoutAction: pick(['continue', 'fail']) } : {}), ...(chance(0.3) ? { label: 'Go on' } : {}) }; break;
    case 'approval': s.config = { approvers: [UUID], table: 't', record: '{{ trigger.name }}', ...(chance(0.4) ? { timeout: pick(['1h', '10m']) } : {}), ...(chance(0.3) ? { timeoutAction: pick(['continue', 'fail']) } : {}), ...(chance(0.15) ? { evidenceFields: [UUID] } : {}) }; break;
    default: s.config = effectConfig(type);
  }
  if (chance(0.12)) s.retries = pick([1, 2, 5]);
  if (chance(0.1)) s.continueOnError = true;
  if (chance(0.12)) s.if = pick(COND);
  return s;
}

function genPlan() {
  const plan = {};
  for (const type of HANDLED) {
    if (chance(0.15)) continue; // no handler
    const p = {};
    if (chance(0.3)) p.fail = pick([1, 2, 3, 9]);
    if (chance(0.2)) p.permanent = true;
    if (type === 'approval' && chance(0.9)) p.result = { approvalId: pick(['apr-1', 'apr-2']) };
    else if (chance(0.6)) p.result = pick([{ ok: true }, { id: 'rec-1', n: 3 }, 'done', 42, null, []]);
    plan[type] = p;
  }
  return plan;
}

function genTrigger() {
  const payload = { n: pick([0, 1, 5]), ok: chance(0.5), name: pick(['ann', 'bob', '']), items: pick([[], [1, 2], ['a', 'b', 'c']]), empty: pick([[], {}, '', 0]), zero: pick([0, '0', false]), nested: { deep: pick(['d', 4]) } };
  return { payload, meta: chance(0.3) ? { userId: 'u1' } : {}, input: chance(0.3) ? { k: 1 } : {} };
}

function scenario() {
  nextId = 0;
  const steps = Array.from({ length: int(5) + 1 }, () => genStep(0));
  const settings = chance(0.3) ? { maxSteps: pick([3, 5, 50]) } : (chance(0.2) ? { retryPolicy: { attempts: 2, backoffMs: 10, multiplier: 3, maxBackoffMs: 50 } } : undefined);
  const def = { id: 'wf-1', name: 'W', version: pick([1, 2]), trigger: { type: 'manual' }, steps, ...(settings ? { settings } : {}) };
  const create = { workflow: { id: def.id, version: def.version, trigger: def.trigger }, trigger: genTrigger(), options: { mode: chance(0.2) ? 'dry-run' : 'live', runId: 'run-1', now: pick([100, 1000]) } };
  const plan = genPlan();
  const env = { REGION: 'eu' };
  const start = pick([1000, 5000]);
  const tick = pick([1, 5, 25]);
  return { def, create, plan, env, start, tick };
}

async function execute(spec) {
  const store = j.createMemoryStore();
  const fresh = j.createRun(spec.create.workflow, spec.create.trigger, spec.create.options);
  await store.create(fresh);
  const runId = 'run-1';
  let t = spec.start;
  const now = () => { const v = t; t += spec.tick; return v; };
  const effects = {};
  for (const type of Object.keys(spec.plan)) {
    effects[type] = async ({ attempt }) => {
      const p = spec.plan[type];
      if (attempt <= (p.fail || 0)) { const e = new Error(`${type} failed ${attempt}`); if (p.permanent) e.permanent = true; throw e; }
      return p.result;
    };
  }
  const checkUrl = async (url) => {
    const m = /^[a-z]+:\/\/([^/]*)/i.exec(url);
    const host = m ? m[1] : url;
    if (host.startsWith('localhost') || host.endsWith('.internal')) return { ok: false, error: 'is not allowed' };
    if (host.endsWith('.test')) return { ok: true, resolved: false, host };
    return { ok: true };
  };
  const deps = { store, now, sleep: async () => {}, effects, checkUrl, env: spec.env };
  const rounds = [];
  const out = [];
  const roundCount = int(4) + 1;
  for (let r = 0; r < roundCount; r++) {
    const round = { pre: [] };
    if (r > 0) {
      const loaded = await store.load(runId);
      if (['succeeded', 'failed', 'cancelled', 'conflict'].includes(loaded.status)) break;
      // Operator actions between executions.
      if (loaded.waiting && loaded.waiting.kind === 'signal' && chance(0.75)) {
        round.pre.push({ entries: [{ type: 'signal-received', fields: { key: loaded.waiting.key, payload: { decision: pick(['approved', 'rejected']), note: 'ok' }, at: t } }], patch: {} });
      }
      if (loaded.waiting && loaded.waiting.kind === 'timer' && chance(0.8)) round.clock = loaded.waiting.wakeAt + int(50);
      else if (chance(0.5)) round.clock = t + int(100000);
      if (chance(0.1)) round.pre.push({ entries: [], patch: { cancelRequested: true, cancelReason: 'operator' } });
      else if (chance(0.1)) round.pre.push({ entries: [], patch: { pauseRequested: true } });
      for (const pre of round.pre) {
        const base = await store.load(runId);
        const c = j.beginCommit(base);
        for (const e of pre.entries) c.add(e.type, e.fields);
        c.setHeader(pre.patch);
        await store.commit(runId, c.build());
      }
      if (round.clock !== undefined) t = round.clock;
    }
    const loaded = await store.load(runId);
    const res = await rt.executeRun(spec.def, loaded, deps);
    rounds.push(round);
    out.push(canon(res));
  }
  return { rounds, e: out.join('\n') };
}

const cases = [];
for (let i = 0; i < 150; i++) {
  const spec = scenario();
  const { rounds, e } = await execute(spec);
  cases.push(JSON.stringify({ def: spec.def, create: spec.create, plan: spec.plan, env: spec.env, start: spec.start, tick: spec.tick, rounds, e }));
}

const chunks = [];
const size = 3;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run_chunk(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'workflow_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_workflow/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
const statuses = {};
for (const c of cases) for (const line of JSON.parse(c).e.split('\n')) { const m = /"status":"([a-z-]+)"/.exec(line.slice(-300)) || /"status":"([a-z-]+)"/.exec(line); if (m) statuses[m[1]] = (statuses[m[1]] || 0) + 1; }
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_workflow`, statuses);
