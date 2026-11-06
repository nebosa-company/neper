/**
 * Time-based trigger math (LC28.18-LC28.21) — schedules that are actually
 * honored.
 *
 * Three authoring forms compile to one runtime representation: simple
 * interval, human recurrence (daily/weekly/monthly), and full 5-field cron
 * expressions (fixing the decorative-cron heritage). Next-fire previews,
 * catch-up policy (at most one catch-up fire per missed window, never a
 * burst), write-once occurrence stamps for date-approaching triggers
 * (re-armed when the underlying date changes), duration-in-state tracking,
 * and cursor-continued scheduled scans. Pure and clock-injected; all times
 * crossing this module's boundary are epoch ms UTC.
 *
 * Timezones are APPLIED, not stored. This module used to say "timezone
 * shifting is the host presentation layer's job" and `normalizeSchedule` kept
 * the field with a comment marking it *informational* — while `nextCronFire`
 * matched cron fields against `getUTCHours`. A rule reading
 * `0 9 * * 1-5, Europe/Sofia` therefore fired at 09:00Z, which is 12:00 in
 * Sofia. Three hours out in summer and two in winter, so no fixed offset
 * repairs it: the conversion has to know about DST, which is why it goes
 * through `Intl.DateTimeFormat` rather than through arithmetic.
 *
 * Two DST edges have a stated policy rather than an accident:
 *   - a wall-clock time that does not exist (the spring-forward gap) does not
 *     fire that day. `02:30` on a day whose clock jumps 02:00 → 03:00 is not a
 *     time, and inventing one means firing at 01:30 or 03:30 — both of which
 *     are a different instruction from the one the author wrote.
 *   - a wall-clock time that happens twice (the autumn fall-back) fires ONCE,
 *     at the first occurrence. Firing twice would double a daily job's effects
 *     once a year, which is the failure mode nobody tests for.
 */

// Zone arithmetic goes through the module that owns Intl construction and
// caches it. This file grew its own formatter Map, which is a second cache of
// the same objects; tests/i18n/no-ad-hoc-locale.test.js caught it.
import { isUsableTimeZone, zonedParts } from '../localization/index.js';
import { filterRecords } from '../views/query.js';
// The schedule form shows these errors to the author; resolved at call time.
import { t } from '../language.js';

/**
 * @typedef {{error?: string, timezone?: string, onMissed?: string,
 *   kind?: 'cron'|'interval', cron?: string, everyMs?: number}} NormalizedSchedule
 */

// --- cron (LC28.18) ------------------------------------------------------

/**
 * The three-letter day and month names standard cron accepts.
 *
 * Indexed so that `indexOf(name) + min` is the field's numeric value in both
 * cases: the day field's `min` is 0 and SUN is 0, the month field's `min` is 1
 * and JAN is 1. That is why `parseField` takes the name table rather than a
 * separate base — one fewer number to get wrong.
 *
 * Exported because `replatform/nebosa-migrate.js` needs the same translation
 * for the cron spelling it reads out of a Nebosa export, and two tables that
 * must agree are one table that has not been shared yet.
 */
export const CRON_DAY_NAMES = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
export const CRON_MONTH_NAMES = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/**
 * One endpoint of a cron range: a number, or a name from `names`.
 *
 * Anything that is neither returns NaN and `parseField` refuses the whole
 * expression. Refusing is the point — a cron that silently means something
 * other than what its author wrote is worse than one that will not run, and a
 * schedule is a thing people stop watching once it works.
 */
function cronEndpoint(token, names, min) {
  const raw = String(token).trim();
  if (names) {
    const i = names.indexOf(raw.toUpperCase());
    if (i !== -1) return i + min;
  }
  return /^\d+$/.test(raw) && Number.isSafeInteger(Number(raw)) ? Number(raw) : NaN;
}

function parseField(spec, min, max, names = null) {
  // Supports: * , - / lists, e.g. "*/15", "1-5", "1,3,5", "10-20/2", and — for
  // the day and month fields — the standard names, e.g. "MON", "MON-FRI",
  // "JAN,JUL".
  const out = new Set();
  for (const part of String(spec).split(',')) {
    const pieces = part.split('/');
    if (!part || pieces.length > 2) return null;
    const [range, stepStr] = pieces;
    const step = pieces.length === 2 ? cronEndpoint(stepStr, null, 0) : 1;
    if (!Number.isSafeInteger(step) || step < 1) return null;
    let lo;
    let hi;
    if (range === '*') {
      lo = min;
      hi = max;
    } else if (range.includes('-')) {
      const endpoints = range.split('-');
      if (endpoints.length !== 2) return null;
      const [a, b] = endpoints;
      lo = cronEndpoint(a, names, min);
      hi = cronEndpoint(b, names, min);
    } else {
      lo = hi = cronEndpoint(range, names, min);
    }
    if (Number.isNaN(lo) || Number.isNaN(hi) || lo < min || hi > max || lo > hi) return null;
    for (let v = lo; v <= hi; v += step) out.add(v);
  }
  return out;
}

/**
 * Parse a 5-field cron expression (min hour dom mon dow). Returns null on
 * invalid input.
 *
 * The day and month fields accept the standard three-letter names as well as
 * numbers. They are not an extension: `MON` and `JAN` are Vixie cron syntax and
 * every scheduler a user is likely to have copied an expression from emits
 * them. This parser read `parseInt` over every field, so `0 7 * * MON` — the
 * expression LC20.12 quotes, and the one BOTH Nebosa fixtures carry — returned
 * null, and a schedule the product could not run was stored with nothing said.
 * `replatform/nebosa-migrate.js` worked around it at the migration boundary,
 * which fixed the imports and left every hand-typed expression still broken.
 */
export function parseCron(expr) {
  const parts = String(expr || '').trim().split(/\s+/);
  if (parts.length !== 5) return null;
  const fields = [
    parseField(parts[0], 0, 59),
    parseField(parts[1], 0, 23),
    parseField(parts[2], 1, 31),
    parseField(parts[3], 1, 12, CRON_MONTH_NAMES),
    parseField(parts[4], 0, 6, CRON_DAY_NAMES),
  ];
  if (fields.some((f) => f === null)) return null;
  const [minute, hour, dom, month, dow] = fields;
  const domWild = parts[2].startsWith('*');
  const dowWild = parts[4].startsWith('*');
  return { minute, hour, dom, month, dow, domWild, dowWild };
}

// --- timezone conversion (LC27.10) ---------------------------------------

/**
 * Is this an IANA zone this runtime can actually convert? An unknown zone must
 * not silently degrade to UTC — that is precisely the failure being fixed.
 */
export function isKnownTimeZone(tz) {
  if (!tz || tz === 'UTC') return true;
  return isUsableTimeZone(tz);
}

/** The wall-clock fields an observer in `tz` reads at instant `ms`. */
export function wallClock(ms, tz = 'UTC') {
  const d = new Date(ms);
  if (!tz || tz === 'UTC') {
    return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(), hour: d.getUTCHours(), minute: d.getUTCMinutes(), second: d.getUTCSeconds(), weekday: d.getUTCDay() };
  }
  const out = zonedParts(d, tz);
  // `weekday` from the formatter would be a localized string; deriving it from
  // the wall date keeps it a number and keeps the cron matcher arithmetic.
  out.weekday = new Date(Date.UTC(out.year, out.month - 1, out.day)).getUTCDay();
  return out;
}

/** How far ahead of UTC the zone's wall clock is at instant `ms`, in ms. */
export function zoneOffsetMs(ms, tz = 'UTC') {
  if (!tz || tz === 'UTC') return 0;
  const w = wallClock(ms, tz);
  return Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second) - Math.floor(ms / 1000) * 1000;
}

/**
 * The instant(s) at which `tz`'s wall clock reads the given date and time.
 *
 * Returns [] for a time inside a spring-forward gap and two entries for one
 * inside an autumn fall-back overlap — the caller decides, rather than being
 * handed one arbitrary answer. Offsets are probed a day either side because a
 * transition can sit between the naive guess and the true instant, and one
 * probe at the guess cannot see across it.
 */
export function wallToInstants(year, month, day, hour, minute, tz = 'UTC') {
  const target = Date.UTC(year, month - 1, day, hour, minute);
  if (!tz || tz === 'UTC') return [target];
  const out = [];
  for (const probe of [target - 86400000, target, target + 86400000]) {
    const ts = target - zoneOffsetMs(probe, tz);
    if (out.includes(ts)) continue;
    const w = wallClock(ts, tz);
    if (w.year === year && w.month === month && w.day === day && w.hour === hour && w.minute === minute) out.push(ts);
  }
  return out.sort((a, b) => a - b);
}

function dayMatches(c, dom, dow) {
  // Wildcard steps still restrict their field. When either field starts with
  // '*', cron intersects the two sets; otherwise its day restrictions use OR.
  const dateMatches = c.dom.has(dom);
  const weekdayMatches = c.dow.has(dow);
  return c.domWild || c.dowWild ? dateMatches && weekdayMatches : dateMatches || weekdayMatches;
}

/**
 * Next fire time strictly after `fromMs` for a parsed cron.
 *
 * Cron fields are matched against the wall clock in `opts.timezone` (default
 * UTC), which is the whole point: `0 9 * * 1-5` in Europe/Sofia means 09:00 as
 * the author's clock reads it, on every weekday of the year, and not a fixed
 * instant that drifts an hour twice a year.
 *
 * Standard cron day semantics: when both dom and dow are restricted, either
 * matches. Search at most one Gregorian calendar cycle, including leap days
 * beyond next year and the eight-year gap across a non-leap century.
 */
export function nextCronFire(cron, fromMs, opts = {}) {
  const c = typeof cron === 'string' ? parseCron(cron) : cron;
  if (!c || !Number.isFinite(new Date(fromMs).getTime())) return null;
  const tz = opts.timezone || 'UTC';
  if (!isKnownTimeZone(tz)) return null;

  const hours = [...c.hour].sort((a, b) => a - b);
  const minutes = [...c.minute].sort((a, b) => a - b);
  const months = [...c.month].sort((a, b) => a - b);
  // Skip unselected months and impossible month dates without Intl work. A
  // full 400-year cycle bounds an impossible date without losing leap days.
  const start = wallClock(fromMs, tz);
  for (let y = start.year; y <= start.year + 400; y++) {
    for (const mo of months) {
      if (y === start.year && mo < start.month) continue;
      const lastDay = new Date(Date.UTC(y, mo, 0)).getUTCDate();
      const firstDay = y === start.year && mo === start.month ? start.day : 1;
      for (let d = firstDay; d <= lastDay; d++) {
        if (!dayMatches(c, d, new Date(Date.UTC(y, mo - 1, d)).getUTCDay())) continue;
        const sameDay = y === start.year && mo === start.month && d === start.day;
        for (const h of hours) {
          if (sameDay && h < start.hour) continue;
          for (const mi of minutes) {
            if (sameDay && h === start.hour && mi < start.minute) continue;
            // First occurrences follow wall-clock order. Repeated readings
            // use their earlier instant; spring-forward gaps have none.
            // Resolve lazily, so an every-minute preview never expands a day.
            const inst = wallToInstants(y, mo, d, h, mi, tz);
            if (inst.length && inst[0] > fromMs) return inst[0];
          }
        }
      }
    }
  }
  return null;
}

/** Latest recorded occurrence at or before now, with the same DST policy. */
function previousCronFire(cron, nowMs, timezone) {
  const c = parseCron(cron);
  if (!c || !Number.isFinite(new Date(nowMs).getTime()) || !isKnownTimeZone(timezone)) return null;
  const start = wallClock(nowMs, timezone);
  const hours = [...c.hour].sort((a, b) => b - a);
  const minutes = [...c.minute].sort((a, b) => b - a);
  const months = [...c.month].sort((a, b) => b - a);
  // During the second pass of a repeated hour, a larger wall minute's FIRST
  // occurrence can already be in the past. Bound by the day's largest offset
  // rather than skipping all wall readings larger than the current reading.
  const upperWall = nowMs + Math.max(...[-86400000, 0, 86400000].map((delta) => zoneOffsetMs(nowMs + delta, timezone)));
  for (let y = start.year; y >= start.year - 400; y--) {
    for (const mo of months) {
      if (y === start.year && mo > start.month) continue;
      const lastDay = y === start.year && mo === start.month ? start.day : new Date(Date.UTC(y, mo, 0)).getUTCDate();
      for (let d = lastDay; d >= 1; d--) {
        if (!dayMatches(c, d, new Date(Date.UTC(y, mo - 1, d)).getUTCDay())) continue;
        for (const h of hours) {
          for (const mi of minutes) {
            if (Date.UTC(y, mo - 1, d, h, mi) > upperWall) continue;
            const inst = wallToInstants(y, mo, d, h, mi, timezone);
            if (inst.length && inst[0] <= nowMs) return inst[0];
          }
        }
      }
    }
  }
  return null;
}

// --- unified schedule representation -------------------------------------

/**
 * How a schedule behaves when the host was down across one or more of its
 * fire times (LC27.10's third clause, LC28.33). Documented here because
 * "the rule's documented missed-fire policy" is only a contract if the
 * document and the code are the same object.
 *
 *   one-catch-up  (default) — fire ONCE, at the most recent missed instant,
 *                  whatever the outage's length. A nightly report that missed
 *                  four nights sends one report, not four.
 *   skip          — fire nothing for the outage; wait for the next scheduled
 *                  instant. Correct for "is anything stale right now" scans,
 *                  where the missed runs have no separate answer to give.
 *   all           — fire every missed instant in order. Correct only for
 *                  schedules whose runs are not interchangeable, and capped so
 *                  a long outage cannot become an unbounded burst.
 */
export const MISSED_FIRE_POLICIES = ['one-catch-up', 'skip', 'all'];
export const DEFAULT_MISSED_FIRE_POLICY = 'one-catch-up';
const MAX_CATCH_UP_FIRES = 1000;

/**
 * Normalize the three authoring forms into one runtime schedule:
 *   { interval: { everyMs } } | { daily: { hour, minute } } |
 *   { weekly: { day 0-6, hour, minute } } | { monthly: { dayOfMonth, hour,
 *   minute } } | { cron: 'expr' }  (+ a timezone that is applied, and a
 *   missed-fire policy).
 *
 * An unrecognized timezone is an ERROR rather than a fall back to UTC. Falling
 * back is how `timezone` came to be decorative in the first place: the field
 * was accepted, stored, and never applied, and nothing anywhere said so.
 * @returns {NormalizedSchedule}
 */
export function normalizeSchedule(spec = {}) {
  const timezone = spec.timezone || 'UTC';
  if (!isKnownTimeZone(timezone)) return { error: t('workflow.schedule.unknownTimezone', null, { timezone }) };
  const onMissed = spec.onMissed || DEFAULT_MISSED_FIRE_POLICY;
  if (!MISSED_FIRE_POLICIES.includes(onMissed)) return { error: t('workflow.schedule.unknownMissedPolicy', null, { policy: onMissed }) };
  const base = { timezone, onMissed };

  const cronResult = /** @returns {NormalizedSchedule} */ (cron) => parseCron(cron) ? { kind: 'cron', cron, ...base }
    : { error: t('workflow.schedule.invalidCron', null, { cron }) };
  if (spec.cron != null) return cronResult(spec.cron);
  if (spec.everyMs != null || spec.intervalMinutes != null) {
    const everyMs = Number(spec.everyMs ?? Number(spec.intervalMinutes) * 60000);
    if (!Number.isFinite(everyMs)) return { error: t('workflow.schedule.unrecognized') };
    if (everyMs < 5 * 60000) return { error: t('workflow.schedule.minimumInterval') };
    return { kind: 'interval', everyMs, ...base };
  }
  const simple = spec.daily || spec.weekly || spec.monthly;
  if (simple) {
    const values = [simple.minute ?? 0, simple.hour ?? 0];
    if (spec.weekly) values.push(simple.day ?? 0);
    if (spec.monthly) values.push(simple.dayOfMonth ?? 1);
    // Friendly forms take scalar numbers, never embedded cron expressions.
    if (values.some((value) => !/^\d+$/.test(String(value)))) return { error: t('workflow.schedule.unrecognized') };
    const [minute, hour, day] = values;
    return cronResult(`${minute} ${hour} ${spec.monthly ? day : '*'} * ${spec.weekly ? day : '*'}`);
  }
  return { error: t('workflow.schedule.unrecognized') };
}

/**
 * The runtime shape (`{kind}`) for a schedule stored in the `{type}` shape the
 * worker reads off `automations.schedule`.
 *
 * Two shapes exist because two modules grew them independently — the authoring
 * side normalizes to `kind`, the execution side persists `type`. Converting at
 * the boundary is cheaper than migrating rows, and putting the conversion here
 * means the timezone and the missed-fire policy survive the crossing instead
 * of being dropped by whichever caller forgets them.
 *
 * Returns null for a shape this module does not model, so a caller can fall
 * back rather than act on a silently empty schedule.
 */
export function runtimeSchedule(stored) {
  if (!stored || typeof stored !== 'object') return null;
  const spec = { timezone: stored.timezone, onMissed: stored.onMissed };
  if (stored.type === 'cron') return normalizeSchedule({ ...spec, cron: stored.cron });
  if (stored.type === 'interval') return normalizeSchedule({ ...spec, everyMs: stored.everyMs });
  if (stored.type === 'daily') return normalizeSchedule({ ...spec, daily: { hour: stored.atHour ?? 0, minute: stored.atMinute ?? 0 } });
  return null;
}

/** Next fire strictly after fromMs, in the schedule's own timezone. */
export function nextFire(schedule, fromMs, anchorMs = 0) {
  if (!schedule || !Number.isFinite(fromMs) || !Number.isFinite(anchorMs)) return null;
  if (schedule.kind === 'interval') {
    if (!Number.isFinite(schedule.everyMs) || schedule.everyMs <= 0) return null;
    const n = Math.floor((fromMs - anchorMs) / schedule.everyMs) + 1;
    const at = anchorMs + n * schedule.everyMs;
    return Number.isFinite(at) && at > fromMs ? at : null;
  }
  if (schedule.kind === 'cron') return nextCronFire(schedule.cron, fromMs, { timezone: schedule.timezone });
  return null;
}

/** Preview the next N fire times (LC28.18 builder preview). */
export function nextFires(schedule, fromMs, n = 5, anchorMs = 0) {
  if (!Number.isSafeInteger(n) || n < 1) return [];
  const out = [];
  let at = fromMs;
  while (out.length < n) {
    const next = nextFire(schedule, at, anchorMs);
    if (next == null) break;
    out.push(next);
    at = next;
  }
  return out;
}

/**
 * Catch-up policy after downtime (LC28.33): given the last fired instant and
 * now, report whether the schedule is due and how many windows were missed —
 * at most ONE catch-up fire regardless of missed count, never a burst.
 */
export function catchUp(schedule, lastFiredMs, nowMs, anchorMs = 0) {
  const plan = missedFires({ ...schedule, onMissed: 'one-catch-up' }, lastFiredMs, nowMs, anchorMs);
  if (!plan.due) return { due: false, missed: 0 };
  return { due: true, fireAt: plan.fireAt[0], missed: plan.missed, catchUp: plan.missed > 0, ...(plan.capped ? { capped: true } : {}) };
}

/**
 * Apply the schedule's missed-fire policy across a downtime window.
 *
 * `catchUp` above answers one policy and hard-codes it. This applies whichever
 * one the rule declared, and always reports `missed` — the count is what makes
 * a skipped outage visible instead of silent, and an operator asking "did last
 * night's job run" needs the number even when the answer is "no, by policy".
 *
 * Cron counts stop at the chunk limit; `capped` marks a lower bound. The skip
 * and one-catch-up cursor still advances to the true latest occurrence.
 * @returns {{policy, due, fireAt: number[], missed, skipped, capped?, spentAt?}}
 */
export function missedFires(schedule, lastFiredMs, nowMs, anchorMs = 0) {
  const policy = schedule?.onMissed || DEFAULT_MISSED_FIRE_POLICY;
  const empty = { policy, due: false, fireAt: [], missed: 0, skipped: 0, capped: false };
  if (!Number.isFinite(lastFiredMs) || !Number.isFinite(nowMs) || nowMs <= lastFiredMs) return empty;
  // Interval counts and their latest occurrence do not require enumerating a
  // long outage. The all policy still returns a bounded chronological chunk.
  if (schedule?.kind === 'interval') {
    const first = nextFire(schedule, lastFiredMs, anchorMs);
    if (first == null || first > nowMs) return empty;
    const count = Math.floor((nowMs - first) / schedule.everyMs) + 1;
    const latest = first + (count - 1) * schedule.everyMs;
    if (policy === 'skip') return { ...empty, missed: count, skipped: count, spentAt: latest };
    if (policy !== 'all') return { policy, due: true, fireAt: [latest], missed: count - 1, skipped: count - 1, capped: false };
    const length = Math.min(count, MAX_CATCH_UP_FIRES);
    return { policy, due: true, fireAt: Array.from({ length }, (_, i) => first + i * schedule.everyMs), missed: length - 1, skipped: 0, capped: count > length };
  }
  const instants = [];
  let at = lastFiredMs;
  let capped = false;
  for (;;) {
    const next = nextFire(schedule, at, anchorMs);
    if (next == null || next > nowMs) break;
    if (instants.length >= MAX_CATCH_UP_FIRES) { capped = true; break; }
    instants.push(next);
    at = next;
  }
  const missed = Math.max(0, instants.length - 1);
  if (!instants.length) return { policy, due: false, fireAt: [], missed: 0, skipped: 0, capped };

  if (policy === 'skip') {
    // The whole window is dropped, including the most recent instant: "skip"
    // that still fired once would be `one-catch-up` under a different name.
    const spentAt = capped ? previousCronFire(schedule.cron, nowMs, schedule.timezone) : instants[instants.length - 1];
    return { policy, due: false, fireAt: [], missed: instants.length, skipped: instants.length, capped, spentAt };
  }
  if (policy === 'all') {
    return { policy, due: true, fireAt: instants, missed, skipped: 0, capped };
  }
  const last = capped ? previousCronFire(schedule.cron, nowMs, schedule.timezone) : instants[instants.length - 1];
  return { policy, due: true, fireAt: [last], missed, skipped: instants.length - 1, capped };
}

/**
 * Resolve the concrete instants a worker should claim for this poll.
 *
 * A first poll must resolve from shared schedule state, not from that worker's
 * clock: otherwise two workers a millisecond apart create different
 * occurrence keys and both pass the database uniqueness check.
 */
export function scheduleFirePlan(stored, lastFiredMs, nowMs, anchorMs = null) {
  if (!Number.isFinite(new Date(nowMs).getTime())) return null;
  const schedule = runtimeSchedule(stored);
  if (!schedule || schedule.error) return null;
  const anchor = Number.isFinite(anchorMs) ? anchorMs : 0;
  const plannedFrom = (from) => {
    const plan = missedFires(schedule, from, nowMs, anchor);
    if (plan.due || !plan.skipped || Number.isFinite(plan.spentAt)) return plan;
    const spent = missedFires({ ...schedule, onMissed: 'all' }, from, nowMs, anchor);
    return { ...plan, spentAt: spent.fireAt[spent.fireAt.length - 1] ?? null };
  };
  if (Number.isFinite(lastFiredMs)) return plannedFrom(lastFiredMs);

  // An interval is intentionally due immediately before its first run. Its
  // creation instant is the shared, deterministic occurrence for that fire.
  if (stored.type === 'interval') {
    const fireAt = Number.isFinite(anchorMs) ? anchorMs : nowMs;
    return { policy: schedule.onMissed, due: true, fireAt: [fireAt], missed: 0, skipped: 0, capped: false };
  }

  // A never-run daily rule keeps isDue()'s existing contract: after today's
  // wall-clock time it is due even when it was created later that day.
  if (stored.type === 'daily') {
    const w = wallClock(nowMs, schedule.timezone);
    const today = wallToInstants(w.year, w.month, w.day, Number(stored.atHour ?? 0), Number(stored.atMinute ?? 0), schedule.timezone)[0];
    if (today == null || today > nowMs) return missedFires(schedule, nowMs, nowMs, anchor);
    return plannedFrom(today - 1);
  }

  // Cron schedules begin at creation, so every worker derives the same real
  // scheduled instant(s), with the declared missed-fire policy applied.
  if (!Number.isFinite(anchorMs)) return null;
  return plannedFrom(anchorMs);
}

// --- self-overlap (LC27.10, default concurrency) --------------------------

/**
 * Should this scheduled rule start now, given a previous run that may still be
 * going?
 *
 * Default concurrency for a schedule is ONE: a nightly job that takes 26 hours
 * must not have two copies of itself walking the same table. The worker's
 * existing `last_run_at`-before-running claim stops two ticks starting the same
 * fire, which is a different problem — it says nothing about a run from the
 * PREVIOUS fire that has not finished.
 *
 * `activeRun` is the host's view of a live run: `{ startedAt }`, or null.
 * `staleAfterMs` exists because a worker killed mid-run leaves a row that says
 * `running` forever, and a schedule that never fires again because of a crash
 * six months ago is worse than an overlap.
 *
 * @returns {{fire: boolean, reason: string, skippedFireAt?: number,
 *   staleForMs?: number, activeSinceMs?: number}}
 */
export function overlapDecision({ due, fireAt = null, activeRun = null, concurrency = 'skip', staleAfterMs = 6 * 3600_000, now = 0 }) {
  if (!due) return { fire: false, reason: 'not-due' };
  if (!activeRun) return { fire: true, reason: 'no-active-run' };
  if (concurrency === 'allow') return { fire: true, reason: 'concurrency-allowed' };
  const startedAt = Number(activeRun.startedAt) || 0;
  if (startedAt && now - startedAt >= staleAfterMs) {
    return { fire: true, reason: 'previous-run-stale', staleForMs: now - startedAt };
  }
  return { fire: false, reason: 'previous-run-active', skippedFireAt: fireAt, activeSinceMs: startedAt || null };
}

// --- date approaching (LC28.20) ------------------------------------------

/**
 * Which records' (field + offset) occurrences are due? Write-once occurrence
 * stamps: `stamps` maps `${recordId}` to the target time already fired for;
 * a changed date re-arms the occurrence (stamp no longer matches the new
 * target) and cancels stale future firings by the same comparison.
 *
 * @param {Array} records
 * @param {{field: string, offsetMs?: number}} config — negative offset = before
 * @param {Map} stamps persisted write-once stamps
 * @returns {Array} events [{ record, target, firedFor }]
 */
export function dueDateEvents(records, config, stamps, nowMs) {
  const out = [];
  for (const r of records) {
    const raw = r[config.field];
    if (!raw) continue;
    const target = Date.parse(raw);
    if (Number.isNaN(target)) continue;
    const fireAt = target + (config.offsetMs || 0);
    const stamped = stamps.get(r.id);
    if (stamped === target) continue; // already fired for this occurrence
    if (nowMs >= fireAt) {
      stamps.set(r.id, target); // write-once per occurrence
      out.push({ record: r, target, firedFor: target, fireAt });
    }
  }
  return out;
}

// --- duration in state (LC28.21) -----------------------------------------

/**
 * Fire when a record has continuously matched `filter` for `durationMs`.
 * `state` maps recordId → { since } while matching; entries clear when the
 * record stops matching (which re-arms the trigger), and a `fired` flag
 * keeps each continuous stretch to one firing.
 */
export function durationInStateDue(records, config, state, nowMs, ctx = {}) {
  const matching = new Set(
    filterRecords(records, config.filter, ctx.fields || [], ctx.refs || {}).map((r) => r.id)
  );
  const out = [];
  for (const r of records) {
    if (matching.has(r.id)) {
      const entry = state.get(r.id) || { since: nowMs, fired: false };
      if (!state.has(r.id)) state.set(r.id, entry);
      if (!entry.fired && nowMs - entry.since >= config.durationMs) {
        entry.fired = true;
        out.push({ record: r, since: entry.since, durationMs: nowMs - entry.since });
      }
    } else {
      state.delete(r.id); // stopped matching → clock and firing re-arm
    }
  }
  return out;
}

// --- scheduled record scan (LC28.19) -------------------------------------

/**
 * One tick of a scheduled scan: evaluate the filter, emit per-record events
 * with scan-batch metadata, and continue from a cursor when the match set
 * exceeds the fan-out cap (default 10,000 per LC28.N2).
 */
export function scanBatch(records, config, ctx = {}, opts = {}) {
  const cap = opts.cap || 10000;
  const cursor = opts.cursor || 0;
  const matched = filterRecords(records, config.filter, ctx.fields || [], ctx.refs || {});
  const slice = matched.slice(cursor, cursor + cap);
  const batchId = opts.batchId || `scan_${cursor}`;
  return {
    events: slice.map((record, i) => ({
      record,
      scanBatch: { id: batchId, size: matched.length, position: cursor + i },
    })),
    total: matched.length,
    nextCursor: cursor + slice.length < matched.length ? cursor + slice.length : null,
  };
}

// --- due evaluation -------------------------------------------------------
//
// This used to live in `src/automation-runtime/index.js`, next to a run-state
// machine that drove the legacy engine's retry/checkpoint cursor. That state
// machine died with the Automations feature — durable runs journal their own
// progress now — but "is this schedule due?" is not about either engine, and it
// was already delegating its cron arm to this file to avoid a second parser
// that could disagree with the preview the author was shown. It belongs here.

/**
 * Is a schedule due to fire?
 *  - { type:'interval', everyMs }  — due when now-lastRunAt ≥ everyMs (or never run)
 *  - { type:'daily', atHour, atMinute }  — due once per day at/after the time,
 *    on the schedule's own clock (`timezone`, default UTC)
 *  - { type:'cron', cron }  — due when a cron instant has passed since the last run
 *
 * `schedule.timezone` is honoured by both the daily and cron arms. It used to
 * be carried and ignored, which made `0 9 * * 1-5` in Europe/Sofia fire at
 * noon local.
 *
 * `anchorMs` is the workflow's creation time and matters only for cron that has
 * never run: without it, "every Monday at 09:00" saved on a Wednesday would
 * have no reference point. It must NOT fire immediately on save the way an
 * interval does — nobody authoring a weekly job expects it to run at once.
 */
export function isDue(schedule, now, lastRunAt, anchorMs = null) {
  if (!schedule) return false;
  if (schedule.type === 'interval') {
    if (lastRunAt == null) return true;
    return now - lastRunAt >= schedule.everyMs;
  }
  if (schedule.type === 'daily') {
    const normalized = runtimeSchedule(schedule);
    if (normalized.error || !Number.isFinite(now)) return false;
    const w = wallClock(now, normalized.timezone);
    const scheduled = wallToInstants(w.year, w.month, w.day, Number(schedule.atHour ?? 0), Number(schedule.atMinute ?? 0), normalized.timezone)[0];
    if (scheduled == null) return false;
    return now >= scheduled && (lastRunAt == null || lastRunAt < scheduled);
  }
  if (schedule.type === 'cron') {
    // An unparseable expression never fires. It is also refused at authoring,
    // so this is the second of two gates rather than the only one.
    if (!parseCron(schedule.cron)) return false;
    const from = lastRunAt != null ? lastRunAt : (anchorMs != null ? anchorMs : now);
    const next = nextCronFire(schedule.cron, from, { timezone: schedule.timezone });
    return next != null && next <= now;
  }
  return false;
}

/**
 * From a set of scheduled workflows, return the ids that are due at `now`.
 * The scheduler enqueues these.
 *
 * A workflow carrying `activeRun: { startedAt }` is a rule whose PREVIOUS fire
 * has not finished. Under default concurrency it does not start a second copy
 * of itself — see `overlapDecision`. Passing `{ detailed: true }` returns the
 * decisions instead of the ids, so a caller can log which rule it held back and
 * why rather than watching a schedule quietly not fire.
 */
export function dueWorkflows(workflows, now, opts = {}) {
  const decisions = (workflows || [])
    .filter((w) => w.schedule)
    .map((w) => ({
      id: w.id,
      ...overlapDecision({
        due: isDue(w.schedule, now, w.lastRunAt, w.anchorMs ?? null),
        fireAt: now,
        activeRun: w.activeRun || null,
        concurrency: w.concurrency || (w.schedule && w.schedule.concurrency) || 'skip',
        now,
      }),
    }));
  return opts.detailed ? decisions : decisions.filter((d) => d.fire).map((d) => d.id);
}
