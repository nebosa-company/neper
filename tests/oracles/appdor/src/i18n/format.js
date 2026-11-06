/**
 * Region and format preferences (gap-vs-monday §8.1, "Language & region").
 *
 * The app already lets someone choose English or Bulgarian, but every number
 * and date was formatted either with a hardcoded `en-US` or with a bare
 * `toLocaleString()`. The bare form follows the *browser*, not the app — so a
 * Bulgarian-language user on a US browser reads "1,234.56" while the interface
 * around it is in Bulgarian, and two users looking at the same record see
 * different numbers. Neither is the user's stated preference, because until now
 * there was nowhere to state one.
 *
 * This module is the single place that decides. Everything is pure: it takes a
 * preferences object and a value, and never reads the clock, the browser, or
 * storage.
 *
 * Robustness matters more than usual here. `Intl.NumberFormat` and
 * `Intl.DateTimeFormat` throw a RangeError on a malformed locale or an unknown
 * time zone, and these preferences come from stored JSON that a user (or an
 * older version) wrote. A settings screen that throws while rendering a date is
 * worse than one that falls back, so every entry point degrades.
 *
 * The Intl objects themselves live in src/localization, which caches them —
 * constructing a formatter per grid cell is the expensive way to do this. This
 * module owns what that one has no concept of: whose preferences are in
 * effect, which order dates go in, and where the week starts.
 */
import { formatNumber as intlNumber, formatMoney as intlMoney, formatPercent as intlPercent, formatDate as intlDate, formatRelativeTime as intlRelative, formatPlural as intlPlural, formatDuration as intlDuration, localeFirstDayOfWeek, // Imported, not just re-exported: `export { x } from '...'` forwards the
  // binding without creating a local one, so the calls below would not see it.
  isUsableLocale,
  isUsableTimeZone,
  localeUses24Hour,
  toMachineDate,
  toMachineDateTime,
  toMachineStamp,
  isMachineDateString,
  activeLocaleCode,
} from '../localization/index.js';
import { SOURCE_LOCALE, localeByCode, orderedLocales, intlTag } from '../localization/locales.js';

/**
 * Sensible defaults for the two languages the product ships strings in — the
 * starting point, not a cage. Every other supported language is derived; see
 * {@link regionDefaultsFor}.
 */
export const REGION_DEFAULTS = {
  en: { locale: 'en-US', dateFormat: 'MDY', firstDayOfWeek: 0, timeZone: 'UTC', currency: 'USD' },
  bg: { locale: 'bg-BG', dateFormat: 'DMY', firstDayOfWeek: 1, timeZone: 'Europe/Sofia', currency: 'EUR' },
};

/**
 * `LOCALE` is the one that does not hand-build anything: it asks Intl for the
 * locale's own numeric pattern, separators included. It is the default for the
 * 34 languages with no row in REGION_DEFAULTS, so the ordered forms below run
 * only when a user has explicitly overridden the order — which is the setting
 * they came to that screen to make (an American in a European team wants DMY
 * without switching their whole interface to another language). FMT-2 forbids
 * *inventing* a date layout; honouring one somebody typed into a settings form
 * is the opposite of that, and it is the only place a separator is named.
 */
export const DATE_FORMATS = {
  // The only entry here whose label is prose rather than a pattern, so the only
  // one carrying a key: `MM/DD/YYYY` is the same string in every language.
  LOCALE: { id: 'LOCALE', label: "This locale's own format", labelKey: 'settings.region.localeOwnFormat', order: null, separator: null },
  MDY: { id: 'MDY', label: 'MM/DD/YYYY', order: ['month', 'day', 'year'], separator: '/' },
  DMY: { id: 'DMY', label: 'DD.MM.YYYY', order: ['day', 'month', 'year'], separator: '.' },
  YMD: { id: 'YMD', label: 'YYYY-MM-DD', order: ['year', 'month', 'day'], separator: '-' },
};

export const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export { isUsableLocale, isUsableTimeZone };

/**
 * The machine half of FMT-3, re-exported here on purpose.
 *
 * This module is what a feature imports when it needs to render something, and
 * the moment it needs to *store* the same value the two helpers should be one
 * import away from each other. Splitting them across modules is how a display
 * string ends up in a CSV.
 */
export { toMachineDate, toMachineDateTime, toMachineStamp, isMachineDateString };

/**
 * Region defaults for any of the 36 supported languages.
 *
 * The two rows above are hand-written because they carry a real currency and a
 * real time zone; the rest are derived, because a 36-row table of date orders
 * and week starts is 36 chances to be wrong about somebody's country and CLDR
 * already knows the answers.
 *
 * The currency does NOT vary by language, and that is deliberate rather than
 * lazy: FMT-7 says the currency belongs to the money, not to the reader. A
 * German-language workspace billing in Swiss francs is ordinary, so guessing
 * EUR from `de` would be a confident wrong label on somebody's revenue. This is
 * only the default a workspace starts from and can change.
 *
 * Memoized: the bound helpers in prefs.js resolve preferences on every call, so
 * this runs once per rendered cell, and `getWeekInfo()` is not free.
 */
const derivedDefaults = new Map();

export function regionDefaultsFor(language) {
  // Naming NO language means "whoever is reading" — the same rule the pure
  // layer applies to an omitted locale, and the reason `formatNumber(n, {})`
  // is now correct at the ~90 call sites that write exactly that. Naming an
  // UNKNOWN one is different: it is a caller asserting something the registry
  // does not recognise, and it falls to the source locale rather than quietly
  // picking up the reader's.
  const entry = localeByCode(language)
    || ((language == null || language === '') ? localeByCode(activeLocaleCode()) : null);
  const code = entry ? entry.code : SOURCE_LOCALE;
  let derived = derivedDefaults.get(code);
  if (!derived) {
    // The hand-written rows carry no `language` of their own — it is the key
    // they are stored under — so it is stamped on here, once, rather than at
    // every read.
    if (REGION_DEFAULTS[code]) {
      derived = { ...REGION_DEFAULTS[code], language: code };
      derivedDefaults.set(code, derived);
      return derived;
    }
    const locale = intlTag(code);
    derived = {
      language: code,
      locale,
      // LOCALE rather than the computed order: the order is what Intl will do
      // anyway, and storing it as an explicit override would freeze today's
      // CLDR answer into the user's preferences.
      dateFormat: 'LOCALE',
      firstDayOfWeek: localeFirstDayOfWeek(locale),
      timeZone: 'UTC',
      currency: REGION_DEFAULTS.en.currency,
    };
    derivedDefaults.set(code, derived);
  }
  return derived;
}

/**
 * Does this locale clock run 0-23? Asked of Intl rather than guessed from the
 * tag: en-AU, en-IN, hi-IN, ko-KR, ar-EG and es-MX all use a 12-hour clock, and
 * "anything but en-US is 24-hour" got every one of them wrong.
 */
function hoursAre24(locale) {
  const answer = localeUses24Hour(locale);
  return answer === null ? locale !== 'en-US' : answer;
}

/**
 * Merge stored preferences over the language defaults, discarding anything
 * unusable.
 *
 * @param {{locale?: string, timeZone?: string, dateFormat?: string,
 *   firstDayOfWeek?: number, currency?: string, use24Hour?: boolean,
 *   numberFormat?: string}} [saved] what the user chose, as stored. Every
 *   property is optional and every one is validated below — this describes the
 *   shape that may arrive, not a shape anything guarantees.
 * @param {string} [language] the app language — any of the 36 supported codes.
 *   This used to be 'en' | 'bg' and anything else fell to the English row, so a
 *   German user read US-grouped numbers under a German interface: FMT-1's
 *   defect, arriving through the defaults rather than through a call site.
 */
export function resolvePreferences(saved = {}, language) {
  const base = regionDefaultsFor(language);
  const s = saved && typeof saved === 'object' ? saved : {};

  const locale = isUsableLocale(s.locale) ? s.locale : base.locale;
  const timeZone = isUsableTimeZone(s.timeZone) ? s.timeZone : base.timeZone;
  const dateFormat = DATE_FORMATS[s.dateFormat] ? s.dateFormat : base.dateFormat;
  const firstDayOfWeek = Number.isInteger(s.firstDayOfWeek) && s.firstDayOfWeek >= 0 && s.firstDayOfWeek <= 6
    ? s.firstDayOfWeek : base.firstDayOfWeek;
  const currency = typeof s.currency === 'string' && /^[A-Z]{3}$/.test(s.currency) ? s.currency : base.currency;
  const use24Hour = typeof s.use24Hour === 'boolean' ? s.use24Hour : hoursAre24(locale);

  // The RESOLVED language, not the argument. A resolved set is routinely fed
  // back in — `formatNumber(v, prefs)` re-resolves through `prefs?.language` —
  // and echoing an omitted or unrecognised value would make the second pass
  // disagree with the first.
  return { locale, timeZone, dateFormat, firstDayOfWeek, currency, use24Hour, language: base.language };
}

/**
 * A finite number, or null.
 *
 * `Number(null)` and `Number('')` are both 0, so an empty numeric cell would
 * otherwise render as "0" — and a blank field reading zero is not a cosmetic
 * problem, it is a different fact.
 */
function toNumber(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'boolean') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Format a number, falling back to a plain string if Intl refuses. */
export function formatNumber(value, prefs = {}, options = {}) {
  const n = toNumber(value);
  if (n === null) return '';
  const { locale } = resolvePreferences(prefs, prefs?.language);
  try {
    return intlNumber(n, locale, options);
  } catch {
    return String(n);
  }
}

/**
 * Money in the workspace's default currency unless one is named (FMT-7).
 *
 * The named currency is the amount's OWN — separators and placement come from
 * the reader's locale, the code does not. `formatCurrency(1234.56, french,
 * 'USD')` is `1 234,56 $US`: French typography, dollars, same number. Nothing
 * here converts. Prefer {@link formatMoney} where the amount already carries a
 * currency, which is most places once a record has a currency column.
 */
export function formatCurrency(value, prefs = {}, currencyCode = null) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const currency = currencyCode || resolved.currency;
  const n = toNumber(value);
  if (n === null) return '';
  try {
    return intlMoney(n, currency, resolved.locale);
  } catch {
    return `${currency} ${formatNumber(n, prefs)}`;
  }
}

/**
 * Money whose currency is known, in the reader's locale (FMT-7).
 *
 * Argument order is the point: the amount and its currency are one fact and sit
 * together, and the reader is the trailing, optional concern. There is no rate
 * parameter and never will be — this renders money, it does not convert it.
 */
export function formatMoney(amount, currency, prefs = {}) {
  const n = toNumber(amount);
  if (n === null) return '';
  const { locale } = resolvePreferences(prefs, prefs?.language);
  try {
    return intlMoney(n, currency, locale);
  } catch {
    return `${currency} ${formatNumber(n, prefs)}`;
  }
}

/** Percentage from a 0–1 fraction. */
export function formatPercent(fraction, prefs = {}, digits = 0) {
  const n = toNumber(fraction);
  if (n === null) return '';
  const { locale } = resolvePreferences(prefs, prefs?.language);
  try {
    return intlPercent(n, locale, { minimumFractionDigits: digits, maximumFractionDigits: digits });
  } catch {
    return String(n);
  }
}

/**
 * A usable Date, or null.
 *
 * `new Date(null)` is epoch 0 — a perfectly valid date — so passing an empty
 * cell straight to the Date constructor renders 01/01/1970 in every blank date
 * field rather than nothing at all.
 */
function toDate(value) {
  if (value == null || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * A bare calendar day ('2026-09-01') names no instant and no zone. It parses as
 * UTC midnight, so rendering it in the viewer's zone shows the day BEFORE for
 * anyone west of Greenwich: it is formatted in UTC instead.
 */
function zoneFor(value, timeZone) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value.trim()) ? 'UTC' : timeZone;
}

/** The date parts of a value in the preferred time zone. */
function partsOf(value, prefs) {
  const date = toDate(value);
  if (!date) return null;
  const timeZone = zoneFor(value, prefs.timeZone);
  try {
    // en-CA renders YYYY-MM-DD, which is trivially splittable — the locale is
    // an implementation detail here, not the user's.
    const [year, month, day] = intlDate(date, 'en-CA', {
      timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    }).split('-');
    return { year, month, day, date };
  } catch {
    const s = date.toISOString();
    return { year: s.slice(0, 4), month: s.slice(5, 7), day: s.slice(8, 10), date };
  }
}

/**
 * A DATE ONLY, in the user's chosen order (FMT-4 — the granularity is in the
 * name, so a value that carries a time is visibly being narrowed rather than
 * silently truncated).
 *
 * `LOCALE` — the default for every language without a hand-written row — asks
 * Intl for the locale's own numeric pattern and touches neither the order nor
 * the separators. The three ordered forms below run only when someone has
 * explicitly chosen one, which is the setting they came to that screen to make.
 */
export function formatDate(value, prefs = {}) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const spec = DATE_FORMATS[resolved.dateFormat] || DATE_FORMATS.LOCALE;
  if (!spec.order) {
    return dateOnlyInLocale(value, resolved);
  }
  const parts = partsOf(value, resolved);
  if (!parts) return '';
  return spec.order.map((k) => parts[k]).join(spec.separator);
}

/** The locale's own numeric date. Nothing is assembled; Intl emits the string. */
function dateOnlyInLocale(value, resolved) {
  const date = toDate(value);
  if (!date) return '';
  try {
    return intlDate(date, resolved.locale, {
      timeZone: zoneFor(value, resolved.timeZone), year: 'numeric', month: '2-digit', day: '2-digit',
    });
  } catch {
    return toMachineDate(date);
  }
}

/** TIME ONLY, in the preferred zone and hour cycle (FMT-4). */
export function formatTime(value, prefs = {}) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const date = toDate(value);
  if (!date) return '';
  try {
    return intlDate(date, resolved.locale, {
      timeZone: resolved.timeZone, hour: '2-digit', minute: '2-digit', hour12: !resolved.use24Hour,
    });
  } catch {
    return toMachineDateTime(date).slice(11, 16);
  }
}

/** A DATE AND TIME together, honouring the 12/24-hour preference (FMT-4). */
export function formatDateTime(value, prefs = {}) {
  const date = toDate(value);
  if (!date) return '';
  return `${formatDate(value, prefs)} ${formatTime(value, prefs)}`;
}

/**
 * Weekday names starting on the user's first day of the week.
 * @returns {{index:number, name:string, short:string}[]}
 */
export function weekdayOrder(prefs = {}) {
  const { firstDayOfWeek, locale } = resolvePreferences(prefs, prefs?.language);
  const out = [];
  for (let i = 0; i < 7; i++) {
    const index = (firstDayOfWeek + i) % 7;
    // 2026-08-02 is a Sunday, so adding `index` days lands on weekday `index`.
    const day = new Date(Date.UTC(2026, 7, 2 + index));
    let name = WEEKDAYS[index];
    let short = name.slice(0, 3);
    try {
      name = intlDate(day, locale, { weekday: 'long', timeZone: 'UTC' });
      short = intlDate(day, locale, { weekday: 'short', timeZone: 'UTC' });
    } catch { /* keep the English fallback */ }
    out.push({ index, name, short });
  }
  return out;
}

/**
 * The start of the week containing `value`, honouring firstDayOfWeek.
 *
 * A calendar that always starts on Monday is wrong for half the world and a
 * calendar that always starts on Sunday is wrong for the other half.
 * @returns {string} an ISO date
 */
export function startOfWeek(value, prefs = {}) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const { firstDayOfWeek } = resolved;
  // The calendar day in the preferred zone (the one formatDate shows), not the
  // UTC day: at UTC+3, 01:00 on Monday is still Sunday in UTC.
  const parts = partsOf(value, resolved);
  if (!parts) return '';
  const t = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
  const dow = new Date(t).getUTCDay();
  const back = (dow - firstDayOfWeek + 7) % 7;
  return new Date(t - back * 86400000).toISOString().slice(0, 10);
}

/**
 * "3 days ago" / "in 2 hours", in the user's language.
 * `now` is a parameter so this stays pure and testable.
 */
export function formatRelative(value, prefs = {}, now = null) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const date = toDate(value);
  if (!date) return '';
  const reference = now == null ? Date.now() : (now instanceof Date ? now.getTime() : Number(now));
  const diffMs = date.getTime() - reference;

  // Annotated because the inferred type of a mixed array literal is
  // `(string|number)[][]`, which makes `diffMs / ms` arithmetic on a string.
  /** @type {[string, number][]} */
  const units = [
    ['year', 31536000000], ['month', 2592000000], ['week', 604800000],
    ['day', 86400000], ['hour', 3600000], ['minute', 60000], ['second', 1000],
  ];
  for (const [unit, ms] of units) {
    const amount = diffMs / ms;
    if (Math.abs(amount) >= 1 || unit === 'second') {
      try {
        return intlRelative(Math.round(amount), unit, resolved.locale);
      } catch {
        const n = Math.round(Math.abs(amount));
        return diffMs < 0 ? `${n} ${unit}${n === 1 ? '' : 's'} ago` : `in ${n} ${unit}${n === 1 ? '' : 's'}`;
      }
    }
  }
  return '';
}

/** "August 2026" in the user's language, for a calendar heading. */
export function formatMonth(value, prefs = {}) {
  const resolved = resolvePreferences(prefs, prefs?.language);
  const d = toDate(value);
  if (!d) return '';
  try {
    return intlDate(d, resolved.locale, { month: 'long', year: 'numeric', timeZone: zoneFor(value, resolved.timeZone) });
  } catch {
    return d.toISOString().slice(0, 7);
  }
}

/**
 * File-size string; storage quotas are meaningless without one.
 *
 * The NUMBER is locale-formatted (FMT-6); the unit is the SI/IEC symbol, which
 * is the same glyph sequence in every locale we ship and is therefore not a
 * word to pluralise. That is the one place FMT-8's "never `value + ' items'`"
 * does not apply — `1,5 MB` is correct German, `1,5 Megabytes` is not.
 */
export function formatBytes(bytes, prefs = {}) {
  const n = toNumber(bytes);
  if (n === null || n < 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i += 1; }
  const digits = i === 0 || v >= 100 || Number.isInteger(v) ? 0 : 1;
  return `${formatNumber(v, prefs, { minimumFractionDigits: digits, maximumFractionDigits: digits })} ${units[i]}`;
}

/**
 * A counted noun (FMT-8). `formatCount(3, { one: '{n} record', other: '{n} records' })`.
 *
 * `${n} record${n === 1 ? '' : 's'}` is English grammar written into a template
 * literal, and this repo has it in about forty places. It is wrong for Russian
 * at 2, for Polish at 22, and for Arabic at 0, 2 and 11 — all of which are
 * separate categories with separate words. Supplying a category map instead
 * lets the locale pick, and lets a translator add the categories their language
 * needs without the call site changing.
 */
export function formatCount(count, forms, prefs = {}) {
  const n = toNumber(count);
  if (n === null) return '';
  const { locale } = resolvePreferences(prefs, prefs?.language);
  try {
    return intlPlural(n, forms, locale);
  } catch {
    return `${formatNumber(n, prefs)} ${(forms && forms.other) || ''}`.trim();
  }
}

/** A duration in the largest whole unit, in the locale's own words (FMT-8). */
export function formatDuration(ms, prefs = {}, options = {}) {
  const n = toNumber(ms);
  if (n === null) return '';
  const { locale } = resolvePreferences(prefs, prefs?.language);
  try {
    return intlDuration(n, locale, options);
  } catch {
    return formatNumber(n, prefs);
  }
}

/**
 * Every IANA zone the runtime knows, grouped by region.
 *
 * The list used to be eight entries typed into `src/settings.js` — UTC, four
 * European cities, two American, Tokyo, Sydney — with no data source behind it
 * and no comment explaining the choice, so a user anywhere else simply could
 * not say where they were. `Intl.supportedValuesOf` returns the full ~420-zone
 * set in every browser this product targets, needs no data file, and stays
 * current with the runtime's own tzdata.
 *
 * Grouped because a flat 420-entry `<select>` is not a picker, and labelled by
 * the part after the region with **every** underscore replaced — the old
 * `replace('_', ' ')` handled only the first, which is invisible at eight
 * entries and wrong for `America/Argentina/Buenos_Aires` the moment there are
 * four hundred.
 *
 * Falls back to the previous eight where `supportedValuesOf` is missing, so an
 * older runtime keeps the behaviour it had rather than losing the control.
 */
const FALLBACK_ZONES = [
  'UTC', 'Europe/Sofia', 'Europe/London', 'Europe/Berlin',
  'America/New_York', 'America/Los_Angeles', 'Asia/Tokyo', 'Australia/Sydney',
];

export function timeZoneChoices() {
  let zones = FALLBACK_ZONES;
  try {
    const all = Intl.supportedValuesOf('timeZone');
    if (Array.isArray(all) && all.length) zones = ['UTC', ...all.filter((z) => z !== 'UTC')];
  } catch { /* keep the fallback */ }

  const groups = new Map();
  for (const id of zones) {
    const slash = id.indexOf('/');
    // A zone with no region ("UTC") is its own group of one, at the top.
    const region = slash === -1 ? id : id.slice(0, slash);
    const label = slash === -1 ? id : id.slice(slash + 1).replace(/_/g, ' ').replace(/\//g, ' — ');
    if (!groups.has(region)) groups.set(region, []);
    groups.get(region).push({ id, label });
  }
  return [...groups.entries()].map(([region, options]) => ({
    region: region.replace(/_/g, ' '),
    options: options.sort((a, b) => a.label.localeCompare(b.label)),
  }));
}

/**
 * The choices a settings screen offers, so the UI does not hardcode them.
 *
 * The locale list is the supported-locale registry rather than the five tags
 * that used to be typed in here — a product that claims 36 languages and offers
 * five number formats is claiming something it does not do. Labelled with the
 * endonym, because a picker is read by the person who speaks the language.
 *
 * @param {{locale?: string, language?: string, firstDayOfWeek?: number}} [prefs]
 *   resolved for the weekday names below; see `firstDays`.
 */
export function formatChoices(prefs = {}) {
  // `WEEKDAYS` is a hardcoded English array, so Sunday / Monday / Saturday had
  // no key in any locale and could not get one without changing this line. The
  // correct implementation was already 140 lines above, in `weekdayOrder` — ask
  // Intl in the resolved locale and keep WEEKDAYS as the `catch` fallback.
  const { locale } = resolvePreferences(prefs, prefs?.language);
  const dayName = (index) => {
    try {
      // 2026-08-02 is a Sunday, so adding `index` days lands on weekday `index`.
      return intlDate(new Date(Date.UTC(2026, 7, 2 + index)), locale, { weekday: 'long', timeZone: 'UTC' });
    } catch {
      return WEEKDAYS[index];
    }
  };

  return {
    dateFormats: Object.values(DATE_FORMATS).map((f) => ({ id: f.id, label: f.label, labelKey: f.labelKey || null })),
    firstDays: [0, 1, 6].map((i) => ({ id: i, label: dayName(i) })),
    timeZones: timeZoneChoices(),
    locales: orderedLocales()
      .map((l) => ({ id: l.intl, label: `${l.endonym} (${l.english})` }))
      // Region variants of a shipped language, where the region changes the
      // formatting and the language does not. en-GB writes 03/08/2026 where
      // en-US writes 08/03/2026, and someone in London should not have to pick
      // a different interface language to get it.
      .concat([{ id: 'en-GB', label: 'English (United Kingdom)' }])
      .filter((l) => isUsableLocale(l.id)),
  };
}
