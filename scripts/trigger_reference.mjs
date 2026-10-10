// Reference vectors for `e.algo.trigger` (L035): run appdor's own time-trigger math (src/workflow/schedule.js) over
// random cron expressions, zones (DST edges included), authoring forms, outages, stored schedules, running rules,
// date stamps, continuous-state tracking and scheduled scans, and write the link fixture
// tests/selfhost/fixtures/link/algo_trigger. Run with TZ=UTC. APPDOR_DIR defaults to D:/repos/appdor.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appdor = process.env.APPDOR_DIR || 'D:/repos/appdor';
const load = (p) => import(pathToFileURL(resolve(appdor, p)).href);
const s = await load('src/workflow/schedule.js');

const hex = (v) => (v === '' || v === undefined || v === null ? '_' : Buffer.from(String(v), 'utf8').toString('hex'));
const flag = (b) => (b ? '1' : '0');
const opt = (v) => (v === null || v === undefined ? '_' : String(v));

let seed = 0xc20c;
const rnd = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];
const MIN = 60000;
const HOUR = 3600000;
const DAY = 86400000;
const ZONES = ['UTC', 'Europe/London', 'Europe/Sofia', 'Europe/Berlin', 'America/New_York', 'America/Los_Angeles', 'America/Sao_Paulo', 'Asia/Tokyo', 'Asia/Kolkata', 'Asia/Kathmandu', 'Australia/Sydney', 'Australia/Lord_Howe', 'Pacific/Auckland'];
const BAD_ZONES = ['Mars/Phobos', 'Nowhere'];
const T0 = Date.UTC(2026, 0, 1);

const cases = [];
const add = (o) => cases.push(JSON.stringify(o));

// Instants where a zone's offset changes, found by an hourly scan of a year.
const edgeCache = new Map();
function edges(tz, year) {
  const key = `${tz}/${year}`;
  if (edgeCache.has(key)) return edgeCache.get(key);
  const out = [];
  let prev = s.zoneOffsetMs(Date.UTC(year, 0, 1), tz);
  for (let t = Date.UTC(year, 0, 1); t < Date.UTC(year + 1, 0, 1); t += HOUR) {
    const off = s.zoneOffsetMs(t, tz);
    if (off !== prev) out.push(t);
    prev = off;
  }
  edgeCache.set(key, out);
  return out;
}

const zone = () => (rnd() < 0.05 ? pick(BAD_ZONES) : pick(ZONES));
const instant = () => {
  const r = rnd();
  if (r < 0.4) return T0 + int(5 * 365) * DAY + int(DAY);
  const tz = pick(ZONES);
  const year = 2026 + int(4);
  const list = edges(tz, year);
  if (!list.length) return T0 + int(365) * DAY + int(DAY);
  return pick(list) + (int(7) - 3) * 30 * MIN + (rnd() < 0.5 ? 0 : int(MIN));
};

const CRON_PARTS = [
  ['0', '30', '*/15', '5,35', '*', '0-10/5', '59', '15'],
  ['*', '9', '0', '2', '3', '1-5', '*/6', '23', '2,3'],
  ['*', '1', '15', '31', '28-31', '*/10', '29', '30', '*/3'],
  ['*', '1-3', '2', 'JAN', '*/6', 'DEC', 'mar', '6,9'],
  ['*', 'MON-FRI', '0', '6', 'SUN', '1,3', '*/2', 'sat', '7'],
];
const randomCron = () => CRON_PARTS.map((p) => pick(p)).join(' ');

// --- parse -----------------------------------------------------------------------------------------------------

const PARSE_FIXED = [
  '0 9 * * 1-5', '*/15 * * * *', '0 0 1 1 *', '0 7 * * MON', '0 0 * JAN-MAR *', '30 2 * * *', '0 0 31 2 *', '60 * * * *',
  '*/0 * * * *', '5-1 * * * *', '1,,2 * * * *', '  0   9\t* * *  ', '0\u00a09 * * *', '* * * *', '* * * * * *', '', '0 0 * * 7',
  '0 0 32 * *', '0 24 * * *', '0 0 0 * *', '0 0 * 0 *', '0 0 * 13 *', 'a * * * *', '1-2-3 * * * *', '1/2/3 * * * *', '5/2 * * * *',
  '10-20/3 * * * *', '*/5,1-3 * * * *', '0 0 * * sun,MON', '0 0 * jan,Jul *', '0 0 1-5/2 * 3', '0 0 */7 * *', '00 09 * * *',
  '0000000000000000000005 * * * *', '9007199254740993 * * * *', '0 0 * * MON-', '0 0 * * -MON', '*/ * * * *',
];
for (const expr of PARSE_FIXED) {
  const c = s.parseCron(expr);
  const list = (set) => [...set].sort((a, b) => a - b).join(',');
  add({ op: 'parse', expr, e: c === null ? 'null' : `m=${list(c.minute)};h=${list(c.hour)};d=${list(c.dom)};mo=${list(c.month)};w=${list(c.dow)};dw=${flag(c.domWild)};ww=${flag(c.dowWild)}` });
}
for (let k = 0; k < 40; k += 1) {
  const expr = randomCron();
  const c = s.parseCron(expr);
  const list = (set) => [...set].sort((a, b) => a - b).join(',');
  add({ op: 'parse', expr, e: c === null ? 'null' : `m=${list(c.minute)};h=${list(c.hour)};d=${list(c.dom)};mo=${list(c.month)};w=${list(c.dow)};dw=${flag(c.domWild)};ww=${flag(c.dowWild)}` });
}

// --- zone arithmetic --------------------------------------------------------------------------------------------

for (let k = 0; k < 60; k += 1) {
  const tz = rnd() < 0.1 ? undefined : pick(ZONES);
  const ms = instant();
  const w = s.wallClock(ms, tz);
  add({ op: 'wall', ms, tz: tz ?? '', e: `${w.year},${w.month},${w.day},${w.hour},${w.minute},${w.second},${w.weekday}` });
  add({ op: 'offset', ms, tz: tz ?? '', e: String(s.zoneOffsetMs(ms, tz)) });
}
for (let k = 0; k < 60; k += 1) {
  const tz = pick(ZONES);
  const year = 2026 + int(3);
  const list = edges(tz, year);
  let ms = list.length ? pick(list) : T0 + int(300) * DAY;
  ms += (int(5) - 2) * 30 * MIN;
  const w = s.wallClock(ms, tz);
  const probe = pick([w, { ...w, hour: (w.hour + 1) % 24 }, { ...w, minute: pick([0, 30]) }]);
  const r = s.wallToInstants(probe.year, probe.month, probe.day, probe.hour, probe.minute, tz);
  add({ op: 'instants', y: probe.year, mo: probe.month, d: probe.day, h: probe.hour, mi: probe.minute, tz, e: r.join(',') });
}

// --- next fire -------------------------------------------------------------------------------------------------

for (let k = 0; k < 160; k += 1) {
  const expr = rnd() < 0.2 ? pick(['30 2 * * *', '0 9 * * 1-5', '*/15 * * * *', '0 0 29 2 *', '0 3 * * *', '30 1 * * *', '0 0 1 * *']) : randomCron();
  const tz = zone();
  const from = instant();
  const r = s.nextCronFire(expr, from, { timezone: tz });
  add({ op: 'nextcron', expr, from, tz, e: r === null ? 'null' : String(r) });
}
for (let k = 0; k < 6; k += 1) {
  const expr = pick(['0 0 30 2 *', '0 0 31 4 *', '0 0 29 2 *']);
  const from = instant();
  const r = s.nextCronFire(expr, from, { timezone: 'UTC' });
  add({ op: 'nextcron', expr, from, tz: 'UTC', e: r === null ? 'null' : String(r) });
}

// --- authoring forms ------------------------------------------------------------------------------------------

const randomSpec = () => {
  const spec = {};
  if (rnd() < 0.5) spec.timezone = pick([...ZONES, 'Mars/Phobos', '']);
  if (rnd() < 0.3) spec.onMissed = pick(['one-catch-up', 'skip', 'all', 'zz']);
  const form = int(7);
  if (form === 0) spec.cron = randomCron();
  else if (form === 1) spec.cron = pick(['bad', '* * *', '0 9 * * MON']);
  else if (form === 2) spec.everyMs = pick([300000, 600000, 3600000, 1000, 301500.5, 'x']);
  else if (form === 3) spec.intervalMinutes = pick([5, 10, 60, 1, 'abc', 0.5]);
  else if (form === 4) spec.daily = { hour: pick([0, 9, 23, 24, 'a', '', 7]), minute: pick([0, 30, 59, 60, undefined, 5]) };
  else if (form === 5) spec.weekly = { day: pick([0, 1, 6, 7, undefined, 'x']), hour: pick([9, 0, undefined]), minute: pick([0, 15, undefined]) };
  else spec.monthly = { dayOfMonth: pick([1, 15, 31, 0, undefined]), hour: pick([9, 12, undefined]), minute: pick([0, 45, undefined]) };
  if (rnd() < 0.05) spec.daily = { hour: 1 };
  return spec;
};
const renderSchedule = (n) => {
  if (n.error) return `ERR:${n.error}`;
  if (n.kind === 'interval') return `interval|${n.everyMs}|${n.timezone}|${n.onMissed}`;
  return `cron|${hex(n.cron)}|${n.timezone}|${n.onMissed}`;
};
for (let k = 0; k < 120; k += 1) {
  const spec = randomSpec();
  add({ op: 'normalize', spec, e: renderSchedule(s.normalizeSchedule(spec)) });
}
add({ op: 'normalize', spec: {}, e: renderSchedule(s.normalizeSchedule({})) });

const randomStored = () => {
  const type = pick(['cron', 'interval', 'daily', 'weekly', 'cron']);
  const o = { type };
  if (rnd() < 0.6) o.timezone = zone();
  if (rnd() < 0.3) o.onMissed = pick(['one-catch-up', 'skip', 'all']);
  if (type === 'cron') o.cron = pick(['0 9 * * 1-5', '*/20 * * * *', '30 2 * * *', '0 0 * * MON', '0 12 1 * *', randomCron(), 'bad']);
  else if (type === 'interval') o.everyMs = pick([300000, 900000, 3600000, 7200000, 10]);
  else if (type === 'daily') { o.atHour = pick([0, 2, 9, 23, undefined]); o.atMinute = pick([0, 30, undefined]); }
  return o;
};
for (let k = 0; k < 60; k += 1) {
  const stored = randomStored();
  const r = s.runtimeSchedule(stored);
  add({ op: 'runtime', stored, e: r === null ? 'null' : renderSchedule(r) });
}

// --- previews and policies ---------------------------------------------------------------------------------

const randomValidSpec = () => {
  for (;;) {
    const spec = randomSpec();
    if (!s.normalizeSchedule(spec).error) return spec;
  }
};
for (let k = 0; k < 60; k += 1) {
  const spec = randomValidSpec();
  const from = instant();
  const n = pick([1, 3, 5, 8, 0, -1]);
  const anchor = pick([0, from - int(100) * MIN, T0]);
  const norm = s.normalizeSchedule(spec);
  add({ op: 'nextfires', spec, from, n, anchor, e: s.nextFires(norm, from, n, anchor).join(',') });
}

const renderPlan = (r) => `${r.policy}|${flag(r.due)}|${r.fireAt.join(',')}|${r.missed}|${r.skipped}|${flag(r.capped)}|${opt(r.spentAt)}`;
for (let k = 0; k < 140; k += 1) {
  const spec = randomValidSpec();
  const norm = s.normalizeSchedule(spec);
  const policy = pick(['one-catch-up', 'skip', 'all']);
  spec.onMissed = policy;
  const schedule = s.normalizeSchedule(spec);
  const last = instant();
  const span = pick([30 * MIN, 3 * HOUR, DAY, 5 * DAY, 40 * DAY, 400 * DAY, 2 * DAY]);
  const now = last + int(span);
  const anchor = pick([0, last - HOUR, T0]);
  add({ op: 'missed', spec, last, now, anchor, e: renderPlan(s.missedFires(schedule, last, now, anchor)) });
  const c = s.catchUp(norm, last, now, anchor);
  add({ op: 'catchup', spec: { ...spec, onMissed: undefined }, last, now, anchor, e: c.due ? `1|${c.fireAt}|${c.missed}|${flag(c.catchUp)}|${flag(c.capped)}` : '0' });
}
// A wide outage on a fast schedule hits the burst cap.
for (const expr of ['* * * * *', '*/5 * * * *', '0 * * * *']) {
  for (const policy of ['one-catch-up', 'skip', 'all']) {
    const spec = { cron: expr, onMissed: policy, timezone: pick(['UTC', 'Europe/Sofia', 'America/New_York']) };
    const schedule = s.normalizeSchedule(spec);
    const last = T0 + int(30) * DAY;
    const now = last + 30 * DAY;
    add({ op: 'missed', spec, last, now, anchor: 0, e: renderPlan(s.missedFires(schedule, last, now, 0)) });
  }
}
for (const policy of ['one-catch-up', 'skip', 'all']) {
  const spec = { everyMs: 300000, onMissed: policy };
  const schedule = s.normalizeSchedule(spec);
  const last = T0;
  const now = last + 30 * DAY;
  add({ op: 'missed', spec, last, now, anchor: 0, e: renderPlan(s.missedFires(schedule, last, now, 0)) });
}

// --- fire plans and due evaluation -----------------------------------------------------------------------

for (let k = 0; k < 120; k += 1) {
  const stored = randomStored();
  const now = instant();
  const last = rnd() < 0.5 ? undefined : now - int(3 * DAY);
  const anchor = rnd() < 0.5 ? undefined : now - int(10 * DAY);
  const r = s.scheduleFirePlan(stored, last === undefined ? null : last, now, anchor === undefined ? null : anchor);
  add({ op: 'plan', stored, last: last ?? null, now, anchor: anchor ?? null, e: r === null ? 'null' : renderPlan(r) });
  const due = s.isDue(stored, now, last === undefined ? null : last, anchor === undefined ? null : anchor);
  add({ op: 'due', stored, last: last ?? null, now, anchor: anchor ?? null, e: flag(due) });
}

const renderDecision = (d) => `${flag(d.fire)}|${d.reason}|${d.skippedFireAt === undefined ? '-' : opt(d.skippedFireAt)}|${d.staleForMs === undefined ? '-' : d.staleForMs}|${d.activeSinceMs === undefined ? '-' : opt(d.activeSinceMs)}`;
for (let k = 0; k < 60; k += 1) {
  const input = {
    due: rnd() < 0.7,
    fireAt: pick([null, 1000, 5000]),
    now: 10 * HOUR,
  };
  if (rnd() < 0.7) input.activeRun = { startedAt: pick([HOUR, 2 * HOUR, 9 * HOUR, 0, 10 * HOUR - 1000]) };
  if (rnd() < 0.3) input.concurrency = pick(['allow', 'skip']);
  if (rnd() < 0.3) input.staleAfterMs = pick([HOUR, 1000]);
  add({ op: 'overlap', ...input, e: renderDecision(s.overlapDecision(input)) });
}
for (let k = 0; k < 30; k += 1) {
  const now = instant();
  const workflows = Array.from({ length: 1 + int(5) }, (_, i) => {
    const w = { id: `w${i}` };
    if (rnd() < 0.85) w.schedule = randomStored();
    if (rnd() < 0.5) w.lastRunAt = now - int(2 * DAY);
    if (rnd() < 0.3) w.anchorMs = now - int(5 * DAY);
    if (rnd() < 0.4) w.activeRun = { startedAt: now - int(10 * HOUR) };
    if (rnd() < 0.2) w.concurrency = pick(['allow', 'skip']);
    return w;
  });
  const out = s.dueWorkflows(workflows, now, { detailed: true });
  add({ op: 'workflows', workflows, now, e: out.map((d) => `${hex(d.id)}=${renderDecision(d)};`).join('') });
}

// --- date approaching -----------------------------------------------------------------------------------------

for (let k = 0; k < 30; k += 1) {
  const now = T0 + int(30) * DAY;
  const records = Array.from({ length: 1 + int(6) }, (_, i) => {
    const r = { id: `r${i}` };
    const form = int(5);
    if (form === 0) r.due = new Date(now + (int(10) - 5) * DAY).toISOString();
    else if (form === 1) r.due = new Date(now + (int(10) - 5) * DAY).toISOString().slice(0, 10);
    else if (form === 2) r.due = 'not a date';
    else if (form === 3) r.due = '';
    else r.due = new Date(now + (int(6) - 3) * HOUR).toISOString();
    return r;
  });
  const stampList = [];
  for (const r of records) if (r.due && rnd() < 0.4) stampList.push([r.id, rnd() < 0.5 ? Date.parse(r.due) : now - DAY]);
  const config = { field: 'due', offsetMs: pick([0, -DAY, HOUR, -HOUR]) };
  const stamps = new Map(stampList.map(([id, t]) => [id, Number.isNaN(t) ? 0 : t]));
  const out = s.dueDateEvents(records, config, stamps, now);
  add({
    op: 'dueevents',
    records,
    config,
    stamps: stampList.map(([id, t]) => [id, Number.isNaN(t) ? 0 : t]),
    now,
    e: `${out.map((x) => `${hex(x.record.id)}:${x.target}:${x.fireAt};`).join('')}#${[...stamps].map(([id, t]) => `${hex(id)}=${t};`).join('')}`,
  });
}

// --- duration in state and scans -------------------------------------------------------------------------

const FIELDS = [{ name: 'id', type: 'text' }, { name: 'status', type: 'select', options: ['open', 'closed', 'hold'] }, { name: 'qty', type: 'number' }];
const mkRecords = (n) => Array.from({ length: n }, (_, i) => ({ id: `r${i}`, status: pick(['open', 'closed', 'hold']), qty: int(10) }));
const mkFilter = () => {
  const r = int(4);
  if (r === 0) return { operator: 'and', children: [{ field: 'status', op: 'is', type: 'select', value: 'open' }] };
  if (r === 1) return { operator: 'or', children: [{ field: 'status', op: 'is', type: 'select', value: 'hold' }, { field: 'qty', op: '>', type: 'number', value: 6 }] };
  if (r === 2) return { operator: 'and', children: [{ field: 'qty', op: '<=', type: 'number', value: 4 }, { field: 'status', op: 'isNot', type: 'select', value: 'closed' }] };
  return undefined;
};
for (let k = 0; k < 30; k += 1) {
  const records = mkRecords(2 + int(8));
  const filter = mkFilter();
  const now = 100000 + int(100000);
  const durationMs = pick([0, 1000, 5000, 60000]);
  const stateList = [];
  for (const r of records) if (rnd() < 0.5) stateList.push([r.id, now - int(120000), rnd() < 0.3]);
  if (rnd() < 0.3) stateList.push(['gone', now - 5000, false]);
  const state = new Map(stateList.map(([id, since, fired]) => [id, { since, fired }]));
  const config = { durationMs };
  if (filter) config.filter = filter;
  const ctx = { fields: FIELDS };
  const out = s.durationInStateDue(records, config, state, now, ctx);
  add({
    op: 'duration',
    records,
    fields: FIELDS,
    config,
    state: stateList,
    now,
    e: `${out.map((x) => `${hex(x.record.id)}:${x.since}:${x.durationMs};`).join('')}#${[...state].map(([id, st]) => `${hex(id)}=${st.since},${flag(st.fired)};`).join('')}`,
  });
}
for (let k = 0; k < 30; k += 1) {
  const records = mkRecords(1 + int(12));
  const filter = mkFilter();
  const config = {};
  if (filter) config.filter = filter;
  const opts = {};
  if (rnd() < 0.7) opts.cap = pick([1, 2, 3, 5]);
  if (rnd() < 0.5) opts.cursor = int(records.length + 2);
  if (rnd() < 0.3) opts.batchId = pick(['b1', 'nightly']);
  const out = s.scanBatch(records, config, { fields: FIELDS }, opts);
  add({
    op: 'scan',
    records,
    fields: FIELDS,
    config,
    opts,
    e: `${out.events.map((x) => `${hex(x.record.id)}@${hex(x.scanBatch.id)}@${x.scanBatch.size}@${x.scanBatch.position};`).join('')}n=${out.total},${out.nextCursor === null ? '_' : out.nextCursor}`,
  });
}

const chunks = [];
const size = 12;
for (let i = 0; i < cases.length; i += size) {
  chunks.push(`"${cases.slice(i, i + size).map((l) => l.replace(/\\/g, '\\\\').replace(/"/g, '\\"')).join('\\n')}\\n"`);
}
const funcs = chunks.map((c, i) => `fn vectors_${i}() -> str {\n    ret ${c}\n}\n`).join('\n');
const calls = chunks.map((_, i) => `    if run(a, vectors_${i}(), &registry, &clock) != 0u8 { os.exit(${i + 1}i32) }\n`).join('');
const template = readFileSync(resolve(here, 'trigger_fixture_template.e'), 'utf8');
const out = template.replace('//__VECTOR_FUNCTIONS__\n', () => `${funcs}\n`).replace('    //__VECTOR_CALLS__\n', () => calls);
const target = resolve(here, '..', 'tests/selfhost/fixtures/link/algo_trigger/src/main.e');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, out, 'utf8');
console.log(`${cases.length} cases in ${chunks.length} chunks -> algo_trigger`);
