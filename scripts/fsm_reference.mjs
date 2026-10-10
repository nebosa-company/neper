// Reference vectors for `e.algo.fsm` (L036, the state-machine half): run appdor's own workflow definition
// validator and differ (src/workflows/definition.js), rule registries (registry.js) and guard (guard.js) over
// random workflows, records, principals and environments and write the link fixture
// tests/selfhost/fixtures/link/algo_fsm. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const def = await load('src/workflows/definition.js');
const guard = await load('src/workflows/guard.js');

const hex = (s) => (s === '' || s === undefined || s === null ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const flag = (b) => (b ? '1' : '0');
function rv(v) {
  if (v === null || v === undefined) return '_';
  if (typeof v === 'number') return `N${String(v)}`;
  if (typeof v === 'string') return `T${hex(v)}`;
  if (typeof v === 'boolean') return v ? 'B1' : 'B0';
  if (Array.isArray(v)) return `[${v.map(rv).join(',')}]`;
  return 'O';
}
const rf = (r) => Object.entries(r).map(([k, x]) => `${hex(k)}=${rv(x)};`).join('');
const opt = (v) => (v === null || v === undefined || v === '' ? '_' : hex(v));

let seed = 0xf5a1;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const chance = (p) => rnd() < p;
const clone = (x) => JSON.parse(JSON.stringify(x));

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));

// --- random pieces --------------------------------------------------------------------------------------------

const STATES = ['s0', 's1', 's2', 's3', 's4', 's5'];
const USERS = ['u1', 'u2', 'u3'];
const ROLES = ['admin', 'dev', 'ops'];
const GROUPS = ['g1', 'g2'];

const mkFilter = () => {
  const r = int(5);
  if (r === 0) return { operator: 'and', children: [{ field: 'Amount', op: '>', type: 'number', value: pick([3, 5, 8]) }] };
  if (r === 1) return { operator: 'or', children: [{ field: 'Status', op: 'is', type: 'select', value: pick(STATES) }, { field: 'Amount', op: '<=', type: 'number', value: 4 }] };
  if (r === 2) return { operator: 'and', children: [{ field: 'Owner', op: 'is', type: 'select', value: pick(USERS) }] };
  if (r === 3) return { operator: 'and', children: [{ field: 'Title', op: 'contains', type: 'text', value: pick(['a', 'x']) }] };
  return { operator: 'and', children: [{ field: 'Amount', op: 'isNotEmpty', type: 'number' }] };
};

const mkCondition = (depth = 0) => {
  const r = int(depth > 0 ? 8 : 11);
  if (r === 0) return { type: 'role', roles: Array.from({ length: 1 + int(2) }, () => pick(ROLES)) };
  if (r === 1) return { type: 'group', groups: pick([[pick(GROUPS)], pick(GROUPS)]) };
  if (r === 2) return { type: 'people-field', field: pick(['Owner', 'Assignee', 'Watchers']) };
  if (r === 3) return { type: 'field-predicate', filter: mkFilter() };
  if (r === 4) return { type: 'formula', expr: pick(['Amount > 5', '{Amount} >= 3', 'AND({Amount} > 2, {Status} = "s1")', '{Missing}', 'Amount']) };
  if (r === 5) return { type: 'decision-table', table: pick(['dt', 'nope']) };
  if (r === 6) return { type: 'weird' };
  if (r === 7) return { type: 'role' };
  if (r === 8) return { all: [mkCondition(1), mkCondition(1)] };
  if (r === 9) return { any: [mkCondition(1), mkCondition(1), mkCondition(1)] };
  return { all: [{ any: [mkCondition(1), mkCondition(1)] }, mkCondition(1)] };
};

const mkValidator = () => {
  const r = int(9);
  if (r === 0) return { type: 'required-fields', fields: pick([['Assignee'], ['Owner', 'Amount'], ['Missing'], 'Title']) };
  if (r === 1) return { type: 'field-predicate', filter: mkFilter(), ...(chance(0.5) ? { message: 'must hold' } : {}) };
  if (r === 2) return { type: 'screen-required', fields: pick([['Reason'], ['Reason', 'Note']]) };
  if (r === 3) return { type: 'formula', expr: pick(['Amount > 5', '{Amount} >= 3', '{Missing}']), ...(chance(0.5) ? { message: 'formula says no' } : {}) };
  if (r === 4) return { type: 'linked-records', relation: 'Children', table: 'Tasks', filter: { operator: 'and', children: [{ field: 'Status', op: 'is', type: 'select', value: 'done' }] }, ...(chance(0.5) ? { quantifier: pick(['all', 'any', 'none', 'weird']) } : {}) };
  if (r === 5) return { type: 'approval', approval: pick(['review', 'cab']) };
  if (r === 6) return { type: 'bogus' };
  if (r === 7) return { type: 'approval' };
  return { type: 'required-fields', fields: ['Title'], message: 'ignored' };
};

const mkPost = () => {
  const r = int(11);
  if (r === 0) return { type: 'set-field', field: 'Flag', value: pick([true, 3, 'x', null, [1, 2]]) };
  if (r === 1) return { type: 'set-field', field: 'Flag', valueSpec: { expr: 'Amount + 1' } };
  if (r === 2) return { type: 'assign', field: 'Assignee', user: pick(USERS) };
  if (r === 3) return { type: 'clear-field', field: 'Note' };
  if (r === 4) return { type: 'add-follower', user: pick(USERS), ...(chance(0.5) ? { field: 'Watchers' } : {}) };
  if (r === 5) return { type: 'remove-follower', user: pick(USERS) };
  if (r === 6) return { type: 'create-record', table: 'Audit', values: { Note: 'moved', N: 2 } };
  if (r === 7) return { type: 'update-record', table: 'Tasks', target: { literal: 'c1' }, values: { Status: { literal: 'done' } } };
  if (r === 8) return { type: 'notify', config: { to: 'owner', text: 'hi "there"' } };
  if (r === 9) return { type: 'webhook', config: { url: 'https://example.com' } };
  return { type: pick(['run-workflow', 'mystery']), workflowId: 'wf9', ...(chance(0.5) ? { params: { a: 1 } } : {}) };
};

function mkWorkflow({ posts = true, clean = false } = {}) {
  const count = 2 + int(5);
  const states = STATES.slice(0, count).map((id, i) => ({ id, label: `State ${i}`, category: pick(['todo', 'in-progress', 'done']) }));
  const transitions = [];
  const n = 2 + int(8);
  for (let i = 0; i < n; i += 1) {
    const t = { id: `t${i}`, name: `Move ${i}`, from: chance(0.2) ? '*' : pick(states).id, to: pick(states).id };
    if (!clean) {
      if (chance(0.04)) t.from = 'ghost';
      if (chance(0.04)) t.to = 'ghost';
    }
    if (chance(0.5)) t.conditions = Array.from({ length: 1 + int(2) }, () => mkCondition());
    if (chance(0.5)) t.validators = Array.from({ length: 1 + int(2) }, () => mkValidator());
    if (posts && chance(0.25)) t.postFunctions = Array.from({ length: 1 + int(2) }, () => mkPost());
    if (chance(0.35)) {
      t.permissions = pick([
        { roles: [pick(ROLES)] }, { users: [pick(USERS)] }, { groups: [pick(GROUPS)] }, { peopleFields: [pick(['Owner', 'Assignee'])] },
        { roles: [], users: [] }, { roles: ROLES.slice(0, 2), users: [pick(USERS)] },
      ]);
    }
    if (chance(0.3)) t.screen = { fields: pick([[{ field: 'Reason', required: true }], [{ field: 'Reason', required: true }, { field: 'Note' }], [{ field: 'Note', required: false }]]) };
    transitions.push(t);
  }
  const wf = def.createWorkflow({
    id: `wf${int(1000)}`, tableId: 'tbl', statusField: 'Status', name: `Flow ${int(100)}`, states, transitions,
    initialState: chance(0.9) ? states[0].id : pick([null, 'ghost']),
  });
  if (chance(0.7)) { wf.status = 'published'; wf.version = 1 + int(4); }
  if (!clean && chance(0.1)) for (let d = 0; d < 1 + int(3); d += 1) wf.states.push({ ...pick(wf.states) });
  return wf;
}

const mkRecord = (wf) => {
  const known = wf.states.map((s) => s.id);
  const r = { id: `r${int(100)}`, Status: chance(0.9) ? pick(known) : pick(['old1', 'old2']) };
  r.Title = pick(['alpha', 'beta', 'xray', '']);
  if (chance(0.8)) r.Owner = pick(USERS);
  if (chance(0.7)) r.Assignee = pick([...USERS, '', null]);
  if (chance(0.8)) r.Amount = int(10);
  if (chance(0.6)) r.Watchers = Array.from({ length: int(3) }, () => pick(USERS));
  if (chance(0.5)) r.Children = pick([['c1', 'c2'], ['c1'], ['c3'], []]);
  if (chance(0.7)) r._version = int(5);
  if (chance(0.3)) r._resolvedAt = '2026-01-01T00:00:00.000Z';
  if (chance(0.2)) r.Note = 'n';
  return r;
};
const mkPrincipal = () => {
  if (chance(0.1)) return null;
  const p = {};
  if (chance(0.9)) p.id = pick(USERS);
  if (chance(0.6)) p.roles = pick([[pick(ROLES)], pick(ROLES), [pick(ROLES), pick(ROLES)]]);
  if (chance(0.5)) p.groups = pick([[pick(GROUPS)], []]);
  if (chance(0.3)) p.permissions = pick([['workflow.force-transition'], ['other'], 'workflow.force-transition']);
  return p;
};
const mkEnv = () => {
  const env = {};
  if (chance(0.4)) env.legacyMap = { old1: pick(STATES.slice(0, 3)), old2: pick(STATES.slice(0, 3)) };
  env.fields = [{ name: 'Amount', type: 'number' }, { name: 'Status', type: 'select', options: STATES }, { name: 'Owner', type: 'select', options: USERS }, { name: 'Title', type: 'text' }];
  env.dataset = { Tasks: [{ id: 'c1', Status: 'done' }, { id: 'c2', Status: pick(['done', 'todo']) }, { id: 'c3', Status: 'todo' }] };
  if (chance(0.7)) env.approvals = { review: pick(['approved', 'pending']), cab: pick(['approved', 'rejected']) };
  env.decisionTables = { dt: { ...(chance(0.5) ? { inputs: ['Owner'] } : {}), rows: [{ when: { Owner: 'u1' }, result: true }, { when: { Owner: 'u2', Amount: 3 }, result: true }, { when: { Owner: '*' }, result: false }] } };
  return env;
};
const mkOpts = () => {
  const o = { now: new Date(Date.UTC(2026, 1, 1) + int(100) * 3600000).toISOString() };
  if (chance(0.8)) o.principal = mkPrincipal();
  if (chance(0.3)) o.onBehalfOf = pick(['auto1', '']);
  if (chance(0.5)) o.inputs = pick([{ Reason: 'because' }, { Reason: '' }, { Note: 'x', Reason: 'y' }, {}, { Amount: 9 }]);
  if (chance(0.3)) o.channel = pick(['api', 'bulk', 'import']);
  if (chance(0.3)) o.expectedVersion = pick([0, 1, 2, 3]);
  if (chance(0.15)) o.override = true;
  if (chance(0.15)) o.reason = 'emergency';
  if (chance(0.2)) o.cascadeDepth = int(3);
  return o;
};

// --- cases ----------------------------------------------------------------------------------------------------

for (let k = 0; k < 120; k += 1) {
  const wf = mkWorkflow();
  const r = def.validateWorkflow(wf);
  const fnd = (x) => `${x.code}@${opt(x.transition)}@${opt(x.state)}@${hex(x.message)};`;
  add({ op: 'validate', workflow: wf, e: `${flag(r.valid)}|E:${r.errors.map(fnd).join('')}|W:${r.warnings.map(fnd).join('')}` });
}

for (let k = 0; k < 50; k += 1) {
  const a = mkWorkflow({ clean: true });
  const b = clone(a);
  b.version = a.version + 1;
  for (let m = 0; m < 1 + int(4); m += 1) {
    const r = int(7);
    if (r === 0 && b.states.length > 1) { const s = b.states.pop(); b.transitions = b.transitions.filter((t) => t.from !== s.id && t.to !== s.id); }
    else if (r === 1) b.states.push({ id: `n${m}`, label: `New ${m}`, category: 'todo' });
    else if (r === 2) b.states[int(b.states.length)].label = 'Renamed';
    else if (r === 3) b.states[int(b.states.length)].category = pick(['todo', 'done']);
    else if (r === 4 && b.transitions.length) b.transitions.splice(int(b.transitions.length), 1);
    else if (r === 5 && b.transitions.length) { const t = b.transitions[int(b.transitions.length)]; t.name = 'Changed'; }
    else if (b.transitions.length) { const t = b.transitions[int(b.transitions.length)]; t.validators = [...t.validators, mkValidator()]; }
  }
  const out = def.diffWorkflows(a, b);
  const lab = (c) => (c.label !== undefined ? c.label : c.name);
  add({ op: 'diff', a, b, e: out.map((c) => `${c.kind}:${hex(c.id)}:${hex(lab(c))};`).join('') });
}

for (let k = 0; k < 130; k += 1) {
  const wf = mkWorkflow();
  const record = mkRecord(wf);
  const principal = mkPrincipal();
  const env = mkEnv();
  const offered = guard.allowedTransitions(wf, record, principal, env);
  const expl = wf.transitions.map((t) => {
    const x = guard.explainTransition(wf, record, t, principal, env);
    return `${hex(t.id)}=${x.available ? 'yes' : `${x.reason}:${(x.conditions || []).map(hex).join(',')}`};`;
  }).join('');
  add({ op: 'allowed', workflow: wf, record, principal, env, e: `${offered.map((t) => hex(t.id)).join(',')}#${expl}` });
}

const renderOutcome = (res) => {
  if (!res.ok) {
    return `ERR|${res.error}|${opt(res.transitionId)}|${rv(res.expected)}|${rv(res.actual)}|${rv(res.from)}|${flag(res.override)}|${opt(res.condition)}|${(res.missing || []).map(hex).join(',')}|${opt(res.validator)}|${opt(res.detail)}|${opt(res.field)}`;
  }
  const h = res.history;
  const ev = res.event;
  const hs = [rv(h.recordId), hex(h.workflowId), String(h.workflowVersion), hex(h.transitionId), hex(h.transitionName), rv(h.from), hex(h.to), opt(h.actor), opt(h.onBehalfOf), hex(h.channel), h.inputs ? rf(h.inputs) : '_', flag(h.override), opt(h.reason), hex(h.at)].join(',');
  const es = [hex(ev.tableId), rv(ev.from), hex(ev.to), hex(ev.transitionId), opt(ev.actor), String(ev.cascadeDepth), hex(ev.dedupKey)].join(',');
  return `OK|${rf(res.record)}|${hs}|${es}||${flag(res.selfTransition)}`;
};
const noPosts = (wf) => { const c = clone(wf); for (const t of c.transitions) t.postFunctions = []; return c; };

for (let k = 0; k < 220; k += 1) {
  const wf = noPosts(mkWorkflow());
  const record = mkRecord(wf);
  const env = mkEnv();
  const opts = mkOpts();
  const tid = chance(0.04) ? 'nope' : pick(wf.transitions).id;
  // A record sitting in the transition's own from-state is the interesting case.
  const t = wf.transitions.find((x) => x.id === tid);
  if (t && t.from !== '*' && chance(0.7) && wf.states.some((s) => s.id === t.from)) record.Status = t.from;
  const res = await guard.executeTransition(wf, record, tid, { ...opts, env });
  add({ op: 'exec', workflow: wf, record, transitionId: tid, opts, env, e: renderOutcome({ ...res, transitionId: res.transitionId }) });
}

for (let k = 0; k < 60; k += 1) {
  const wf = mkWorkflow();
  const record = mkRecord(wf);
  const principal = mkPrincipal();
  const env = mkEnv();
  const status = chance(0.1) ? record.Status : pick(wf.states).id;
  const r = guard.resolveStatusWrite(wf, record, status, principal, env);
  const e = r.noop ? 'noop' : r.transition ? `t:${hex(r.transition.id)}` : `e:${r.error}${r.candidates ? `:${r.candidates.map((c) => hex(c.id)).join(',')}` : ''}`;
  add({ op: 'resolve', workflow: wf, record, status, principal, env, e });
}

const renderReport = (r) => {
  if (r.error) return 'ok=0,error=unknown-transition';
  const rules = (list, withErr) => list.map((x) => `${hex(x.type)}=${flag(x.passed)}${withErr && x.error !== undefined ? `=${hex(x.error)}` : ''};`).join('');
  return [flag(r.ok), hex(r.transition.id), hex(r.transition.name), hex(r.transition.from), hex(r.transition.to), flag(r.fromStateOk), flag(r.permissionOk), rules(r.conditions, false), rules(r.validators, true), r.missingInputs.map(hex).join(','), r.postFunctionPreview.map((s) => `${hex(JSON.stringify(s))};`).join('')].join('|');
};
for (let k = 0; k < 130; k += 1) {
  const wf = mkWorkflow();
  const record = mkRecord(wf);
  const principal = mkPrincipal();
  const env = mkEnv();
  const inputs = pick([{}, { Reason: 'because' }, { Reason: '' }, { Note: 'x' }]);
  const tid = chance(0.04) ? 'nope' : pick(wf.transitions).id;
  const r = await guard.simulateTransition(wf, record, tid, principal, { ...env, inputs });
  // Conditions report `type || 'group'`, which the renderer reads as `type`.
  if (r.conditions) for (const c of r.conditions) if (c.type === undefined) c.type = 'group';
  add({ op: 'simulate', workflow: wf, record, transitionId: tid, principal, env, inputs, e: renderReport(r) });
}

for (let k = 0; k < 40; k += 1) {
  const wf = noPosts(mkWorkflow());
  const tid = pick(wf.transitions).id;
  const records = Array.from({ length: 1 + int(5) }, () => mkRecord(wf));
  const t = wf.transitions.find((x) => x.id === tid);
  if (t && t.from !== '*') for (const r of records) if (chance(0.7) && wf.states.some((s) => s.id === t.from)) r.Status = t.from;
  records.forEach((r, i) => { r.id = `r${i}`; });
  const env = mkEnv();
  const opts = mkOpts();
  delete opts.expectedVersion;
  const policy = pick(['partial', 'atomic']);
  const res = await guard.bulkTransition(wf, records, tid, { ...opts, env, policy, inputs: opts.inputs });
  const rep = (x) => renderReport(x);
  const text = res.outcomes.map((o) => {
    const head = `|${rv(o.recordId)}:${o.status}`;
    if (o.status === 'transitioned') return `${head}:${rf(o.record)}`;
    if (o.blockedBy) return o.blockedBy.error === 'atomic-abort' ? `${head}:abort` : `${head}:probe:${rep(o.blockedBy.conditions ? { ...o.blockedBy, conditions: o.blockedBy.conditions.map((c) => ({ ...c, type: c.type ?? 'group' })) } : o.blockedBy)}`;
    return `${head}:${o.error}:${opt(o.detail)}`;
  }).join('');
  add({ op: 'bulk', workflow: wf, records, transitionId: tid, opts, env, policy, e: `${res.policy}|${res.committed}${text}` });
}

for (let k = 0; k < 40; k += 1) {
  const states = ['a', 'b', 'c'];
  const entries = [];
  let at = Date.UTC(2026, 0, 1);
  let cur = 'a';
  for (let i = 0; i < 1 + int(6); i += 1) {
    at += (1 + int(50)) * 3600000;
    const to = chance(0.2) ? cur : pick(states);
    entries.push({ from: cur, to, at: new Date(at).toISOString() });
    cur = to;
  }
  const shuffled = entries.map((e) => ({ e, k: rnd() })).sort((x, y) => x.k - y.k).map((x) => x.e);
  const now = new Date(at + 40 * 3600000).toISOString();
  const r = guard.timeInState(shuffled, { now });
  add({
    op: 'time', entries: shuffled, now,
    e: `${r.visits.map((v) => `${hex(v.state)}|${hex(v.enteredAt)}|${opt(v.leftAt)}|${v.ms};`).join('')}#${Object.entries(r.totals).map(([s, ms]) => `${hex(s)}=${ms};`).join('')}`,
  });
}

const brief = (wf) => `${hex(wf.name)}|${opt(wf.initialState)}|${wf.status}|${wf.version}|${wf.states.map((s) => `${hex(s.id)}:${hex(s.label)}:${s.category};`).join('')}|${wf.transitions.map((t) => `${hex(t.id)}:${hex(t.name)}:${hex(t.from)}:${hex(t.to)}:${t.validators.length}:${t.postFunctions.length}:${flag(t.screen)};`).join('')}`;
for (let k = 0; k < 6; k += 1) {
  const options = Array.from({ length: k }, (_, i) => `opt${i}`);
  add({ op: 'open', tableId: 't1', statusField: 'S', options, e: brief(def.openWorkflow('t1', 'S', options)) });
}
for (const key of Object.keys(def.WORKFLOW_TEMPLATES)) {
  add({ op: 'template', key, tableId: 'tbl', statusField: 'Status', e: brief(def.WORKFLOW_TEMPLATES[key]('tbl', 'Status')).replace(/^[^|]*\|/, (m) => m) });
}
add({ op: 'template', key: 'nonesuch', tableId: 'tbl', statusField: 'Status', e: 'unknown' });

for (let k = 0; k < 20; k += 1) {
  const states = [pick(['x', { id: 'y' }, { id: 'z', label: 'Zed', category: 'done' }, { id: 'w', category: 'bogus' }]), { id: 'q', label: '', category: 'in-progress' }];
  const transitions = [{ id: 't1', to: 'x' }, { name: 'Named', from: 'x', to: 'y', primary: true }, { id: 't3', name: '', from: '*', to: 'q' }];
  const wf = def.createWorkflow({ tableId: 'a', statusField: 'b', states, transitions });
  const norm = (s) => `${hex(s.id)}:${hex(s.label)}:${s.category};`;
  const nt = wf.transitions.map((t, i) => `${hex(transitions[i].id ? t.id : 'GEN')}:${hex(t.name)}:${hex(t.from)}:${hex(t.to)}:${flag(t.primary)};`).join('');
  add({ op: 'normalize', states, transitions, e: `${wf.states.map(norm).join('')}#${nt}` });
}

for (let k = 0; k < 40; k += 1) {
  const draft = def.createWorkflow({ id: 'wf', tableId: 'a', statusField: 'b', states: ['x', 'y'], transitions: [{ id: 'xy', from: 'x', to: 'y' }] });
  if (chance(0.15)) draft.status = 'published';
  const script = [];
  const wf = clone(draft);
  const out = [];
  for (let s = 0; s < 1 + int(5); s += 1) {
    const r = int(3);
    let step;
    if (r === 0) step = ['addState', { id: pick(['x', 'n1', 'n2', 'n3']), ...(chance(0.5) ? { label: 'L' } : {}) }];
    else if (r === 1) step = ['addTransition', { id: `e${s}`, from: pick(['x', 'y', '*']), to: pick(['x', 'y', 'n1']), name: 'Edge' }];
    else step = ['removeState', pick(['x', 'y', 'n1'])];
    script.push(step);
    try {
      if (step[0] === 'addState') def.addState(wf, step[1]);
      else if (step[0] === 'addTransition') def.addTransition(wf, step[1]);
      else def.removeState(wf, step[1]);
      out.push('ok;');
    } catch (e) { out.push(`!${hex(e.message)};`); }
  }
  add({ op: 'edit', workflow: draft, script, e: `${out.join('')}#${brief(wf)}` });
}

const chunks = [];
const size = 8;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'fsm_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_fsm/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_fsm`);
