// Reference vectors for `e.algo.project` (L035): run appdor's own scheduling core (src/scheduling/{index,
// dependencies,working-calendar}.js) over random dependency graphs, calendars, assignments and reschedules and write
// the link fixture tests/selfhost/fixtures/link/algo_project. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const sched = await load('src/scheduling/index.js');
const calMod = await load('src/scheduling/working-calendar.js');

const hex = (s) => (s === '' || s === undefined || s === null ? '_' : Buffer.from(String(s), 'utf8').toString('hex'));
const flag = (b) => (b ? '1' : '0');
const opt = (v) => (v === null || v === undefined ? '_' : String(v));

let seed = 0x5eed;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const DAY = 86400000;
const BASE = Date.UTC(2026, 0, 1);

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));

// --- random inputs --------------------------------------------------------------------------------------------------

function mkDeps(i, ids, cyclic) {
  const deps = [];
  const n = pick([0, 0, 1, 1, 2, 3]);
  for (let k = 0; k < n; k += 1) {
    let target;
    if (cyclic && rnd() < 0.15) target = pick(ids);
    else if (i > 0) target = ids[int(i)];
    else continue;
    if (rnd() < 0.05) target = 'missing';
    const form = int(10);
    if (form < 3) { deps.push(target); continue; }
    const type = pick([undefined, 'FS', 'SS', 'FF', 'SF', 'ss', 'ff', 'sf', 'XX', null]);
    const lag = pick([undefined, 0, 1, 2, 3, -1, -2, 1.7, -1.7, null, 'x', 5]);
    const idKey = pick(['id', 'id', 'id', 'predecessor', 'from']);
    const d = { [idKey]: target };
    if (type !== undefined) d.type = type;
    if (lag !== undefined) d.lag = lag;
    deps.push(d);
  }
  return deps;
}

function mkTasks(count, cyclic = false) {
  const ids = Array.from({ length: count }, (_, i) => `t${i}`);
  return ids.map((id, i) => {
    const t = { id, name: `Task ${i}`, deps: mkDeps(i, ids, cyclic) };
    const dur = pick([0, 1, 2, 3, 4, 5, 8, null, -2]);
    if (dur !== null) t.duration = dur;
    if (rnd() < 0.15) t.milestone = true;
    const prog = pick([undefined, 0, 0.25, 0.5, 1, 40, 100, 150, -0.5, 'x', null]);
    if (prog !== undefined) t.progress = prog;
    return t;
  });
}

function mkOptions() {
  const o = {};
  if (rnd() < 0.7) o.projectStart = BASE + int(40) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
  const cal = int(4);
  if (cal === 1) o.workingDays = [1, 2, 3, 4, 5];
  else if (cal === 2) { o.workingDays = pick([[1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 5, 6], [2, 4], [6, 0], []]); o.holidays = Array.from({ length: int(5) }, () => BASE + int(60) * DAY + (rnd() < 0.3 ? int(DAY) : 0)); }
  else if (cal === 3) o.holidays = Array.from({ length: 1 + int(4) }, () => BASE + int(40) * DAY);
  return o;
}

// --- rendering -----------------------------------------------------------------------------------------------------

function renderCpm(tasks) {
  try {
    const r = sched.criticalPath(tasks);
    let out = `D${r.projectDuration};`;
    for (const [id, s] of Object.entries(r.tasks)) out += `${hex(id)}:${s.es},${s.ef},${s.ls},${s.lf},${s.slack},${flag(s.critical)};`;
    return `${out}P:${r.criticalPath.map(hex).join(',')}`;
  } catch (e) {
    return `!${e.message}`;
  }
}

function renderGantt(tasks, options) {
  try {
    const r = sched.ganttLayout(tasks, options);
    let out = `D${r.projectDuration};S${r.projectStart.getTime()};E${r.projectEnd.getTime()};`;
    for (const b of r.bars) {
      out += `${hex(b.id)}|${hex(b.name)}|${b.startOffset}|${b.duration}|${b.startDate.getTime()}|${b.endDate.getTime()}|${b.slack}|${flag(b.critical)}|${flag(b.milestone)}|${b.progress}|`;
      out += `${b.baselineStart === undefined ? '-' : b.baselineStart === null ? '_' : b.baselineStart.getTime()}|`;
      out += `${b.baselineEnd === undefined ? '-' : b.baselineEnd === null ? '_' : b.baselineEnd.getTime()}|`;
      out += `${b.variance === undefined ? '-' : b.variance === null ? '_' : b.variance};`;
    }
    return `${out}P:${r.criticalPath.map(hex).join(',')}`;
  } catch (e) {
    return `!${e.message}`;
  }
}

// --- cases ---------------------------------------------------------------------------------------------------------

for (let k = 0; k < 160; k += 1) {
  const tasks = mkTasks(1 + int(12), rnd() < 0.12);
  add({ op: 'cpm', tasks, e: renderCpm(tasks) });
}

for (let k = 0; k < 160; k += 1) {
  const tasks = mkTasks(1 + int(10), false);
  const options = mkOptions();
  const wire = { ...options };
  let baseline;
  if (rnd() < 0.5) {
    baseline = {};
    for (const t of tasks) {
      if (rnd() < 0.7) {
        const entry = {};
        if (rnd() < 0.85) entry.start = BASE + int(60) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
        if (rnd() < 0.85) entry.end = BASE + int(80) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
        baseline[t.id] = entry;
      }
    }
    options.baseline = baseline;
    wire.baseline = baseline;
  }
  add({ op: 'gantt', tasks, options: wire, e: renderGantt(tasks, options) });
}

// A baseline captured from a layout and replayed.
for (let k = 0; k < 20; k += 1) {
  const tasks = mkTasks(1 + int(8), false);
  const options = mkOptions();
  const first = sched.ganttLayout(tasks, options);
  const cap = sched.captureBaseline(first);
  const baseline = {};
  for (const [id, b] of Object.entries(cap)) baseline[id] = { start: b.start.getTime(), end: b.end.getTime() + (rnd() < 0.5 ? 0 : int(5) * DAY) };
  const wire = { ...options, baseline };
  add({ op: 'gantt', tasks, options: wire, e: renderGantt(tasks, { ...options, baseline }) });
}

for (let k = 0; k < 80; k += 1) {
  const count = 2 + int(10);
  const tasks = mkTasks(count, false);
  // A parent forest, with the occasional cycle.
  for (let i = 0; i < count; i += 1) {
    if (i > 0 && rnd() < 0.6) tasks[i].parent = `t${int(i)}`;
    if (rnd() < 0.05) tasks[i].parent = `t${int(count)}`;
  }
  const r = sched.rollUpProgress(tasks);
  add({ op: 'rollup', tasks, e: Object.entries(r).map(([id, v]) => `${hex(id)}=${v};`).join('') });
}

for (let k = 0; k < 80; k += 1) {
  const events = [];
  const n = int(9);
  for (let i = 0; i < n; i += 1) {
    const ev = { id: `e${i}` };
    const day = BASE + int(75) * DAY + (rnd() < 0.4 ? int(DAY) : 0);
    const form = int(5);
    if (form === 0) ev.date = day;
    else if (form === 1) ev.start = day;
    else if (form === 2) { ev.start = day; ev.end = day + int(8) * DAY + int(DAY); }
    else if (form === 3) { ev.date = day; ev.end = day + int(5) * DAY; }
    else if (rnd() < 0.5) { ev.start = day; ev.end = day - int(4) * DAY; }
    events.push(ev);
  }
  const params = { year: 2026, month: 1 + int(3), weekStart: pick([undefined, 0, 1, 6]) };
  const r = sched.calendarLayout(events, params);
  const cells = r.weeks.map((w) => w.map((c) => `${c.day === null ? '_' : c.day}:${c.events.map(hex).join(',')}`).join(';')).join('/');
  add({ op: 'calendar', events, params, e: `${r.year},${r.month},${cells}` });
}

for (let k = 0; k < 120; k += 1) {
  const people = ['Ann', 'Bo', 'Cy', 'Di'];
  const assignments = [];
  const n = 1 + int(10);
  for (let i = 0; i < n; i += 1) {
    const a = { assignee: pick(people) };
    const start = BASE + int(30) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
    if (rnd() < 0.95) a.start = start;
    if (rnd() < 0.7) a.end = start + int(8) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
    const h = pick([undefined, 2, 4, 6, 8, 10, 'x', null, 0.5]);
    if (h !== undefined) a.hoursPerDay = h;
    const eff = pick([undefined, 1, 3, 5, 9]);
    if (eff !== undefined) a.effort = eff;
    assignments.push(a);
  }
  const options = {};
  if (rnd() < 0.4) options.capacityPerDay = pick([6, 8, 10, 4]);
  if (rnd() < 0.4) options.capacityOverrides = { [pick(people)]: pick([4, 6, 12, 0]) };
  if (rnd() < 0.3) options.mode = 'count';
  if (rnd() < 0.3) options.effortField = 'effort';
  const cal = mkOptions();
  if (cal.workingDays) options.workingDays = cal.workingDays;
  if (cal.holidays) options.holidays = cal.holidays;
  const r = sched.workload(assignments, options);
  const per = Object.entries(r.perAssignee).map(([who, days]) => `${hex(who)}{${Object.entries(days).map(([d, h]) => `${Date.parse(d) / DAY}=${h}`).join(',')}}`).join(';');
  const over = r.overallocated.map((o) => `${hex(o.assignee)}|${Date.parse(o.day) / DAY}|${o.hours}|${o.over}|${o.capacity}`).join(';');
  add({ op: 'workload', assignments, options, e: `${per}#${over}` });
}

for (let k = 0; k < 100; k += 1) {
  const tasks = mkTasks(2 + int(9), false);
  for (const t of tasks) if (t.duration === null || t.duration === undefined) t.duration = pick([undefined, 1, 2]);
  let cpm;
  try { cpm = sched.criticalPath(tasks); } catch { continue; }
  const schedule = {};
  for (const [id, s] of Object.entries(cpm.tasks)) if (rnd() < 0.9) schedule[id] = { es: s.es, ef: s.ef };
  const change = { id: pick(tasks).id, start: int(10) };
  if (rnd() < 0.1) change.id = 'ghost';
  const moves = sched.cascadeReschedule(tasks, schedule, change);
  add({ op: 'cascade', tasks, schedule, change, e: moves.map((m) => `${hex(m.id)}:${m.from}>${m.to}(${m.shift});`).join('') });
}

for (let k = 0; k < 120; k += 1) {
  const o = mkOptions();
  const wd = o.workingDays ?? (rnd() < 0.5 ? undefined : [1, 2, 3, 4, 5]);
  const cal = calMod.createWorkingCalendar({ workingDays: wd, holidays: o.holidays });
  const queries = [];
  for (let q = 0; q < 8; q += 1) {
    const a = BASE + int(60) * DAY + (rnd() < 0.3 ? int(DAY) : 0);
    const b = a + int(20) * DAY;
    const n = pick([0, 1, 2, 3, 5, 9, -2, 2.7]);
    const kind = pick(['is', 'next', 'add', 'count', 'span']);
    let r;
    if (kind === 'is') r = flag(cal.isWorkingDay(a));
    else if (kind === 'next') r = cal.nextWorkingDay(a).getTime();
    else if (kind === 'add') r = cal.addWorkingDays(a, n).getTime();
    else if (kind === 'count') r = cal.countWorkingDays(a, b);
    else r = cal.workingSpan(a, b);
    queries.push([kind, a, b, n, String(r)]);
  }
  add({ op: 'calendar-ops', workingDays: wd === undefined ? null : wd, holidays: o.holidays || [], queries, e: `${flag(cal.isContinuous)}${queries.map((q) => `,${q[4]}`).join('')}` });
}

for (let k = 0; k < 40; k += 1) {
  const kind = pick(['FS', 'SS', 'FF', 'SF']);
  const dep = { type: kind, lag: int(7) - 3 };
  const es = int(10);
  const ef = es + int(6);
  const dur = int(6);
  add({
    op: 'depfn',
    kind,
    lag: dep.lag,
    es,
    ef,
    dur,
    e: `${sched.earliestStartUnder(dep, { es, ef }, dur)},${sched.latestFinishUnder(dep, { ls: es, lf: ef }, dur)}`,
  });
}

const chunks = [];
const size = 12;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}()) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'project_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_project/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_project`);
