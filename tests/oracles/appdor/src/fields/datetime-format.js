/**
 * How a date and a time are written out.
 *
 * Three field types read from this — Date, Created time and Last modified time —
 * and their specs list the same two dropdowns: ten date formats and nine time
 * formats, composed independently. Ten times nine is ninety spellings, which is
 * exactly why they are two tables and one composition rather than ninety cases.
 *
 * Everything is deterministic except the two entries that are explicitly not:
 * `local`, which asks the runtime, and `relative`, which needs a `now`. Both
 * take that dependency as an argument so a test can pin it — a formatter that
 * reads the wall clock cannot be tested, and one that reads the machine locale
 * makes the same record read differently to two people on the same call.
 *
 * Pure. Values are read as UTC and rendered in local time, which is the
 * assumption the Created time spec states outright. Those are two separate
 * halves and only the first is shared with the rest of the app: `toDate` below
 * fixes what instant a stored string names, and the tables fix how that instant
 * is spelled for a reader. The first has one right answer and the formula and
 * view engines already hold it; the second is a display choice this module owns.
 */

import { formatDate } from '../localization/index.js';

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];
const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const pad = (n, width = 2) => String(Math.abs(n)).padStart(width, '0');

/**
 * A date-time string that names no zone. Kept in step with `NAIVE_DATETIME` in
 * `src/formula/values.js`, where the reasoning lives, and with the copy in
 * `src/views/query.js`.
 *
 * Duplicated rather than imported for the same reason the other two are: this
 * module is the display layer and it holds its own coercions. What it must not
 * do is hold a DIFFERENT rule. It did, and this is what that cost: the formula
 * engine and the view engine read `2026-01-15T23:30:00` as 23:30 UTC, while a
 * bare `new Date()` here read it as the VIEWER's 23:30. One cell, two instants,
 * and which two depended on who had the tab open — so a column holding both
 * `2026-01-15T23:30:00` and `2026-01-15T23:30:00Z` sorted them as equal and
 * displayed them an hour apart, and `epoch` and `iso8601-tz`, the two formats
 * that render the instant rather than the wall clock, printed a different
 * moment than the one the view had just filtered on.
 */
const NAIVE_DATETIME = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/;

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Parse whatever the cell holds into a Date, or null. */
export function toDate(value) {
  if (value === null || value === undefined || value === '') return null;
  const date = value instanceof Date
    ? value
    : new Date(NAIVE_DATETIME.test(value) ? `${String(value).replace(' ', 'T')}Z` : value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/**
 * The ISO 8601 week number, and the year that week belongs to.
 *
 * Weeks belong to the year containing their Thursday, so the 1st of January can
 * be week 52 of the previous year — the reason this is not `Math.ceil(day/7)`,
 * which is wrong for about a fifth of all years.
 */
export function isoWeekOf(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = d.getUTCDay() || 7;               // Sunday is 7, not 0
  d.setUTCDate(d.getUTCDate() + 4 - day);       // move to this week's Thursday
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return { week, year: d.getUTCFullYear() };
}

/** Date formats, keyed as the settings dropdown lists them. */
export const DATE_FORMATS = {
  // Through `localization/index.js` — see the note in number-format.js. The
  // explicit `timeZone: undefined` overrides that module's UTC default: every
  // other format here reads local wall-clock parts, and one entry rendering the
  // day in UTC would put the same instant on two different dates depending on
  // which format the column happened to choose.
  local: (d, o) => formatDate(d, o.locale, {
    timeZone: undefined, year: 'numeric', month: 'numeric', day: 'numeric',
  }),
  'short-no-year': (d) => `${MONTHS[d.getMonth()].slice(0, 3)} ${d.getDate()}`,
  'short-friendly': (d) => `${MONTHS[d.getMonth()].slice(0, 3)} ${d.getDate()}, ${d.getFullYear()}`,
  friendly: (d) => `${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`,
  // Middle-endian is the US order; European is the same three numbers reversed.
  // They are listed separately because a column shared across offices needs to
  // say which it means — 7/1 is two different days.
  'middle-endian': (d) => `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`,
  european: (d) => `${d.getDate()}/${d.getMonth() + 1}/${d.getFullYear()}`,
  'big-endian': (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
  'little-endian': (d) => `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}`,
  rfc2822: (d) => `${DAYS[d.getDay()].slice(0, 3)}, ${d.getDate()} ${MONTHS[d.getMonth()].slice(0, 3)} ${d.getFullYear()}`,
  relative: (d, o) => relativeFrom(d, o.now),
};

/** Time formats, keyed as the settings dropdown lists them. */
export const TIME_FORMATS = {
  // "Chicago style" is the manual's lowercase a.m./p.m.; "modern" is the
  // uppercase one. They differ by four characters and both are asked for.
  'chicago-12': (d) => `${hour12(d)}:${pad(d.getMinutes())} ${d.getHours() < 12 ? 'a.m.' : 'p.m.'}`,
  'modern-12': (d) => `${hour12(d)}:${pad(d.getMinutes())} ${d.getHours() < 12 ? 'AM' : 'PM'}`,
  '24h': (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`,
  military: (d) => `${pad(d.getHours())}${pad(d.getMinutes())}`,
  iso8601: (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`,
  // The only entry rendered in UTC rather than local time: a trailing Z that
  // carried a local wall-clock reading would be a lie about the instant.
  'iso8601-tz': (d) => `T${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}Z`,
  british: (d) => `${pad(d.getHours())}.${pad(d.getMinutes())}`,
  french: (d) => `${pad(d.getHours())} h ${pad(d.getMinutes())}`,
  epoch: (d) => String(Math.floor(d.getTime() / 1000)),
  relative: (d, o) => relativeFrom(d, o.now),
};

function hour12(d) {
  const h = d.getHours() % 12;
  return h === 0 ? 12 : h;
}

/** Unit names and their length in seconds, largest first. @type {Array<[string, number]>} */
const UNITS = [
  ['year', 31536000],
  ['month', 2592000],
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
  ['second', 1],
];

/**
 * "3 years, 4 months, 2 days ago" — the spec's own example, and its shape.
 *
 * Three units at most: past that it stops being readable and starts being a
 * duration. A difference under a second is "just now" rather than "0 seconds
 * ago", which reads like a stopped clock.
 *
 * @param {Date} date
 * @param {Date|number} [now] injected so this is testable; defaults to the clock
 */
export function relativeFrom(date, now) {
  const nowMs = now instanceof Date ? now.getTime() : (typeof now === 'number' ? now : Date.now());
  const deltaSeconds = Math.round((nowMs - date.getTime()) / 1000);
  const future = deltaSeconds < 0;
  let remaining = Math.abs(deltaSeconds);
  if (remaining < 1) return 'just now';

  const parts = [];
  for (const [name, seconds] of UNITS) {
    if (parts.length === 3) break;
    const count = Math.floor(remaining / seconds);
    if (!count) continue;
    parts.push(`${count} ${name}${count === 1 ? '' : 's'}`);
    remaining -= count * seconds;
  }
  return future ? `in ${parts.join(', ')}` : `${parts.join(', ')} ago`;
}

/**
 * @typedef {object} DateTimeConfig
 * @property {string} [dateFormat='local']
 * @property {boolean} [includeTime=false]
 * @property {string} [timeFormat='24h']
 * @property {boolean} [showDayOfWeek=false] prefix "Wed, "
 * @property {boolean} [showWeekNumber=false] suffix "(W02)"
 * @property {boolean} [showSeconds=false]  seconds on the formats that omit them
 * @property {string} [locale]              for `local`
 * @property {Date|number} [now]            for `relative`
 */

/**
 * Write a date/time value out.
 *
 * @param {string|number|Date|null|undefined} value
 * @param {DateTimeConfig} [config]
 * @returns {string} '' for empty; the original string for an unparseable value
 */
export function formatDateTime(value, config = {}) {
  if (value === null || value === undefined || value === '') return '';
  // A date-only value is a calendar day, not an instant: build it at LOCAL
  // midnight so the local getters below read the day that was stored, rather
  // than the previous day for a viewer west of UTC.
  const dayOnly = typeof value === 'string' ? DATE_ONLY.exec(value.trim()) : null;
  const date = dayOnly ? new Date(+dayOnly[1], +dayOnly[2] - 1, +dayOnly[3]) : toDate(value);
  // An unparseable value is shown as it was rather than as "Invalid Date":
  // the cell may be mid-import, and the original is more use than the word.
  if (!date) return String(value);

  const {
    dateFormat = 'local',
    includeTime = false,
    timeFormat = '24h',
    showDayOfWeek = false,
    showWeekNumber = false,
    showSeconds = false,
    locale,
    now,
  } = config;

  const dateFn = DATE_FORMATS[dateFormat] || DATE_FORMATS.local;
  let out = dateFn(date, { locale, now });

  // "Relative" already reads as a sentence; a weekday prefix or a week-number
  // suffix on "2 days ago" is noise, and the time half would repeat it.
  if (dateFormat === 'relative') return out;

  if (showDayOfWeek) out = `${DAYS[date.getDay()].slice(0, 3)}, ${out}`;

  if (includeTime) {
    const timeFn = TIME_FORMATS[timeFormat] || TIME_FORMATS['24h'];
    let time = timeFn(date, { locale, now });
    // Seconds are asked for separately, and only the formats that do not
    // already carry them can gain them. Appending to `military` (1622) or
    // `epoch` would corrupt the format rather than extend it.
    if (showSeconds && ['chicago-12', 'modern-12', '24h', 'british', 'french'].includes(timeFormat)) {
      const seconds = pad(date.getSeconds());
      time = timeFormat === '24h' || timeFormat === 'british' || timeFormat === 'french'
        ? `${time}${timeFormat === '24h' ? ':' : timeFormat === 'british' ? '.' : ' '}${seconds}`
        : time.replace(/(\d+:\d+)/, `$1:${seconds}`);
    }
    out = `${out} ${time}`;
  }

  if (showWeekNumber) out = `${out} (W${pad(isoWeekOf(date).week)})`;
  return out;
}

/** The keys a settings dropdown offers. */
export function dateFormatIds() { return Object.keys(DATE_FORMATS); }
export function timeFormatIds() { return Object.keys(TIME_FORMATS); }
