/**
 * Internationalization & localization (i18n-localization).
 *
 * Pure locale-aware formatting for published-app output: numbers, currency,
 * percent, and dates via cached Intl formatters (never constructed per cell),
 * plus dictionary translation with interpolation and fallback. Formula *source*
 * stays locale-invariant; only formatted *output* honours the viewer's locale.
 *
 * Two rules the rest of the file exists to hold up:
 *
 * - **§4 FMT-1** — formatting follows the language the user picked IN THE APP,
 *   never the browser or the OS. Every entry point below resolves its `locale`
 *   argument through {@link formattingTag}, and an omitted argument means "the
 *   active app locale" rather than the source locale.
 * - **§4 FMT-3** — a display string and a machine string are different kinds.
 *   The `format*` half is locale-dependent and for eyes only; the `toMachine*`
 *   half is ISO-8601, locale-independent, and the only half that may be
 *   persisted, exported or sorted. They sit side by side so a call site picks
 *   one on purpose.
 */
import { SOURCE_LOCALE, intlTag, isSupported, localeByCode, // Their `resolveLocale` answers "which of our 36 codes is this tag?" — a
  // different question from this module's "which tag do I hand Intl?", so it is
  // renamed at the border rather than shadowing the local one.
  resolveLocale as codeFromTag } from './locales.js';

const numberCache = new Map();
const dateCache = new Map();
const relativeCache = new Map();

function key(locale, opts) {
  return `${locale}|${JSON.stringify(opts || {})}`;
}

function numberFormatter(locale, opts) {
  const k = key(locale, opts);
  let f = numberCache.get(k);
  if (!f) {
    f = new Intl.NumberFormat(locale, opts);
    numberCache.set(k, f);
  }
  return f;
}

function dateFormatter(locale, opts) {
  const k = key(locale, opts);
  let f = dateCache.get(k);
  if (!f) {
    f = new Intl.DateTimeFormat(locale, opts);
    dateCache.set(k, f);
  }
  return f;
}

// --- whose locale is in effect (FMT-1) -----------------------------------

/**
 * Where the active app locale comes from, as a getter rather than a value.
 *
 * **This is the headline fix.** Every formatter here used to default its
 * `locale` parameter to `'en'`, so the hundreds of call sites that pass nothing
 * — because they have no locale to hand and no reason to think they need one —
 * silently rendered source-locale output to a German user. The other half of
 * the same bug is `toLocaleString()`, which follows the BROWSER; a German user
 * on an English-locale OS gets English there. The app's own choice must beat
 * both, and the only way to make "pass nothing" correct is for "nothing" to
 * mean the active locale.
 *
 * A getter, not a stored tag, because the language changes at runtime and a
 * value captured at module load would be stale for the rest of the session.
 * Injected rather than imported so this layer keeps knowing nothing about
 * storage or the DOM — src/i18n/prefs.js owns that and registers itself.
 */
let activeLocaleGetter = () => SOURCE_LOCALE;

/** Point {@link activeLocale} at the app's language. Called once, by src/i18n/prefs.js. */
export function setActiveLocaleSource(getter) {
  activeLocaleGetter = typeof getter === 'function' ? getter : () => SOURCE_LOCALE;
}

/**
 * The active app locale as one of the 36 product codes.
 *
 * Tolerant and total: the getter reads storage and the DOM, either of which can
 * hold a stale tag from an older build, and a formatter is the wrong place to
 * discover that. Anything unrecognised degrades to the source locale.
 */
export function activeLocaleCode() {
  let raw;
  try {
    raw = activeLocaleGetter();
  } catch {
    return SOURCE_LOCALE;
  }
  const entry = localeByCode(raw) || localeByCode(codeFromTag(raw));
  return entry ? entry.code : SOURCE_LOCALE;
}

/** The active app locale as a tag `Intl.*` actually understands. */
export function activeLocale() {
  return intlTag(activeLocaleCode());
}

/**
 * The tag to hand `Intl.*` for a caller-supplied locale.
 *
 * Three inputs, three answers, and the middle one is the whole reason this
 * exists:
 *
 * - **nothing** -> the active app locale (FMT-1);
 * - **one of our codes** -> `intlTag()` of it. `zht` is well-formed BCP-47, so
 *   `new Intl.DateTimeFormat('zht')` does not throw — it resolves to English
 *   and a Traditional Chinese reader gets English month names with no error
 *   anywhere. Only the registry knows it means `zh-Hant`;
 * - **a concrete tag** (en-GB, bg-BG, pt-BR) -> itself, untouched. These are
 *   region preferences and are strictly more specific than any product code;
 *   routing them through `intlTag()` would collapse en-GB to en and quietly
 *   discard the setting the user came to the settings screen to make.
 */
export function formattingTag(locale) {
  if (locale == null) return activeLocale();
  const tag = String(locale).trim();
  if (!tag) return activeLocale();
  if (isSupported(tag)) return intlTag(tag);
  return isUsableLocale(tag) ? tag : activeLocale();
}

/**
 * The wall-clock fields an observer in `timeZone` reads at an instant.
 *
 * **Not a formatting call — nothing this returns is shown to anyone.** Cron
 * matching has to answer "what hour is it *there* right now", and the only
 * portable way to make a runtime do zone arithmetic (including DST) is to let
 * `Intl` do it and read the fields back as numbers.
 *
 * It lives here because this module owns `Intl` construction and caches it.
 * `src/automations/trigger-schedule.js` had grown its own `formatterFor(tz)`
 * with its own `Map`, which is a second cache of the same objects and was
 * caught by `tests/i18n/no-ad-hoc-locale.test.js` — correctly. A scheduler
 * polling every few seconds must not build a `DateTimeFormat` per evaluation,
 * and it should not have to know that to be correct.
 *
 * It names **no locale tag**. The first version pinned one, which bought the
 * numeric safety by side effect — a tag that happens to imply a Gregorian
 * calendar and Latin digits — and tripped this repo's own rule that concrete
 * tags belong in the preferences layer. Naming the two properties that actually
 * matter states the requirement instead of encoding it in a region code: the
 * parts are consumed as NUMBERS, so a non-Gregorian calendar or non-Latin
 * digits would silently change what `Number(part)` means. `hourCycle: 'h23'`
 * is the third, for the same reason — `hour12` yields a 12 at midnight.
 */
export function zonedParts(value, timeZone) {
  const parts = dateFormatter(undefined, {
    timeZone,
    calendar: 'gregory',
    numberingSystem: 'latn',
    hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).formatToParts(value instanceof Date ? value : new Date(value));
  const out = {};
  for (const p of parts) {
    if (p.type !== 'literal') out[p.type] = Number(p.value);
  }
  return out;
}

export function formatNumber(value, locale, options = {}) {
  if (value == null || value === '') return '';
  return numberFormatter(formattingTag(locale), options).format(Number(value));
}

/**
 * Money (FMT-7). **The currency comes before the language, and it is required.**
 *
 * The argument order states the rule: an amount and its currency are one fact
 * and travel together, while the locale is a separate, optional question about
 * who is reading. A French interface showing a USD price renders `1 234,56 $US`
 * — French separators and French placement around an amount that is still, and
 * only, dollars. Nothing here converts, rounds to another currency's minor
 * units, or relabels; there is deliberately no rate parameter to pass.
 *
 * Omitting the currency throws rather than defaulting. A default would be a
 * guess about somebody's money that renders as a confident `$` — the one
 * failure mode nobody catches by looking at the screen.
 */
export function formatMoney(amount, currency, locale, options = {}) {
  const code = typeof currency === 'string' ? currency.trim().toUpperCase() : '';
  if (!/^[A-Z]{3}$/.test(code)) {
    throw new TypeError(`formatMoney needs an ISO 4217 currency code; got ${JSON.stringify(currency)}`);
  }
  if (amount == null || amount === '') return '';
  return numberFormatter(formattingTag(locale), { style: 'currency', currency: code, ...options })
    .format(Number(amount));
}

/**
 * Money, in the argument order this module shipped with.
 *
 * Kept because call sites and tests use it; {@link formatMoney} is the shape
 * FMT-7 asks for and this delegates to it, so the currency is required here too.
 */
export function formatCurrency(value, locale, currency, options = {}) {
  return formatMoney(value, currency, locale, options);
}

/** Format a 0..1 (or 0..100 with `whole:true`) ratio as a percent. */
export function formatPercent(value, locale, options = {}) {
  if (value == null || value === '') return '';
  const n = options.whole ? Number(value) / 100 : Number(value);
  const { whole, ...rest } = options;
  return numberFormatter(formattingTag(locale), { style: 'percent', ...rest }).format(n);
}

/**
 * The default is a starting point, not the shape callers must supply — a
 * time-only or weekday-only format is an ordinary call. Saying so here is what
 * lets `i18n/format.js` ask for `{ hour, minute }` without inheriting a
 * year/month/day requirement it never wanted.
 *
 * The zone defaults to UTC, which makes this the PRIMITIVE rather than the
 * display helper: a value rendered here reads the same for everyone, which is
 * right for a stored instant and wrong for a due date. {@link formatDisplayDate}
 * is the FMT-5 half — it defaults to the viewer's own zone and can name it.
 *
 * @param {Date|string|number|null} value
 * @param {string} [locale]
 * @param {Intl.DateTimeFormatOptions} [options]
 */
export function formatDate(value, locale, options = { year: 'numeric', month: 'short', day: 'numeric' }) {
  if (value == null || value === '') return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return dateFormatter(formattingTag(locale), { timeZone: 'UTC', ...options }).format(d);
}

/** Plural category for a count in a locale ('one'|'other'|…). */
export function pluralCategory(count, locale) {
  return new Intl.PluralRules(formattingTag(locale)).select(Number(count));
}

// --- dictionary translation ----------------------------------------------

function interpolate(template, params) {
  return String(template).replace(/\{(\w+)\}/g, (_m, k) => (params && params[k] != null ? String(params[k]) : ''));
}

/**
 * Translate a key from a nested/flat dictionary set.
 * @param {Object<string, object>} dictionaries { en:{...}, bg:{...} }
 * @param {string} keyPath
 * @param {{ locale?: string, fallbackLocale?: string, params?: object,
 *           onMissing?: 'key'|((keyPath: string) => string),
 *           missing?: string[], pseudo?: boolean }} [opts]
 *   `onMissing` — what a caller gets when nothing translates the key. Default
 *   is humanized prose; `'key'` returns the path, which is what a builder
 *   listing gaps wants and what a viewer must never see (LC6.12).
 *   `missing` — an array the misses are appended to, deduped, so a builder can
 *   flag the untranslated remainder without a second pass over the catalogue.
 *   `pseudo` — render through {@link pseudoLocalize} (LC6.14).
 */
export function translate(dictionaries, keyPath, opts = {}) {
  const locale = opts.locale || 'en';
  const fallback = opts.fallbackLocale || 'en';
  const lookup = (dict) => keyPath.split('.').reduce((o, k) => (o == null ? undefined : o[k]), dict);
  let value = dictionaries[locale] ? lookup(dictionaries[locale]) : undefined;
  if (value == null && dictionaries[fallback]) value = lookup(dictionaries[fallback]);

  if (value == null) {
    // LC6.12 requires untranslated strings fall back to English and **never**
    // render as raw keys. This returned `keyPath`, so a viewer of a partly
    // translated app saw `welcome.title` on the page — the one output the
    // criterion names. The key is still available, but only by asking for it:
    // `onMissing: 'key'` is what a builder or a test wants, and a viewer is
    // never the one asking.
    if (Array.isArray(opts.missing) && !opts.missing.includes(keyPath)) opts.missing.push(keyPath);
    if (typeof opts.onMissing === 'function') return opts.onMissing(keyPath);
    if (opts.onMissing === 'key') return keyPath;
    return humanizeKey(keyPath);
  }

  if (opts.pseudo) return pseudoLocalize(interpolate(value, opts.params));
  return interpolate(value, opts.params);
}

/**
 * Last resort text for a key nothing translates: the final segment, spaced and
 * sentence-cased. `checkout.payment.cardNumber` -> "Card number".
 *
 * Not the whole path. A viewer seeing "Checkout payment card number" above a
 * single input is worse than seeing "Card number", and the leading segments are
 * routing information that only means something to whoever wrote the catalogue.
 */
export function humanizeKey(keyPath) {
  const last = String(keyPath).split('.').pop() || '';
  const spaced = last
    .replace(/[_-]+/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .trim()
    .toLowerCase();
  return spaced ? spaced.charAt(0).toUpperCase() + spaced.slice(1) : '';
}

/**
 * Languages written right-to-left, by ISO 639 subtag.
 *
 * Matched on the LANGUAGE subtag only, so `ar-EG`, `ar_EG` and `ar` all agree.
 * Deliberately a list rather than a guess from the script subtag: `az-Arab` is
 * RTL and `az` is not, and a heuristic that reads the region would get both
 * wrong. Unknown tags are LTR, which is the safe default — a mirrored layout on
 * an LTR language is far more disruptive than the reverse.
 */
export const RTL_LANGUAGES = Object.freeze([
  'ar', 'arc', 'ckb', 'dv', 'fa', 'ha', 'he', 'khw', 'ks', 'ps', 'sd', 'ur', 'uz-AF', 'yi',
]);

/** 'rtl' or 'ltr' for a locale tag. LC6.13 — no per-app configuration. */
export function direction(locale = 'en') {
  const tag = String(locale).replace(/_/g, '-');
  const lang = tag.split('-')[0].toLowerCase();
  if (RTL_LANGUAGES.includes(tag)) return 'rtl';
  return RTL_LANGUAGES.includes(lang) ? 'rtl' : 'ltr';
}

/** Convenience predicate over {@link direction}. */
export function isRtl(locale = 'en') {
  return direction(locale) === 'rtl';
}

/**
 * The document attributes a viewer's locale implies.
 *
 * Returned as data rather than applied, so the same decision is testable
 * without a DOM and there is exactly one place that decides it.
 *
 * @param {string} [locale]
 * @returns {{lang: string, dir: 'ltr'|'rtl'}} `dir` is the literal union
 *   because `rtl.js` writes it straight onto `<html>` and its own signature
 *   promises the same two values.
 */
export function documentLocaleAttrs(locale) {
  // Omitting the locale means the active one here too — the document attributes
  // are the one place where following the browser instead of the app is visible
  // to a screen reader rather than just to a reader.
  const tag = locale == null || locale === '' ? activeLocaleCode() : String(locale);
  return { lang: tag.replace(/_/g, '-'), dir: direction(tag) };
}

const PSEUDO_MAP = {
  a: 'ä', b: 'ƀ', c: 'ç', d: 'ð', e: 'é', f: 'ƒ', g: 'ĝ', h: 'ĥ', i: 'į', j: 'ĵ', k: 'ķ',
  l: 'ł', m: 'ɱ', n: 'ń', o: 'ö', p: 'þ', q: 'ə', r: 'ŕ', s: 'ş', t: 'ţ', u: 'ü', v: 'ṽ',
  w: 'ŵ', x: 'ẋ', y: 'ý', z: 'ž',
  A: 'Ä', B: 'Ɓ', C: 'Ç', D: 'Ð', E: 'É', F: 'Ƒ', G: 'Ĝ', H: 'Ĥ', I: 'Į', J: 'Ĵ', K: 'Ķ',
  L: 'Ł', M: 'Ṁ', N: 'Ń', O: 'Ö', P: 'Þ', Q: 'Ǫ', R: 'Ŕ', S: 'Ş', T: 'Ţ', U: 'Ü', V: 'Ṽ',
  W: 'Ŵ', X: 'Ẋ', Y: 'Ý', Z: 'Ž',
};

/**
 * Pseudo-localization for the workbench (LC6.14).
 *
 * Three jobs at once, which is why it is not just an accent map:
 *
 * - **accents** make an untranslated string obvious at a glance;
 * - **padding** (~30%) exposes layout that only fits English, since most target
 *   languages run longer;
 * - **brackets** mark the boundaries, so a string built by concatenation shows
 *   up as `[[…]][[…]]` — the defect that is invisible until it is translated.
 *
 * Interpolation placeholders are left ALONE. Accenting `{name}` to `{ńäɱé}`
 * would break the very substitution the string exists to perform, and the
 * resulting bug would look like a translation problem rather than a tooling one.
 */
export function pseudoLocalize(text, opts = {}) {
  const src = String(text ?? '');
  if (!src) return src;
  const pad = opts.pad === undefined ? 0.3 : opts.pad;
  const brackets = opts.brackets !== false;

  // Split on {placeholders} so they can be passed through untouched.
  const parts = src.split(/(\{[^{}]*\})/g);
  const accented = parts
    .map((part) => (/^\{[^{}]*\}$/.test(part)
      ? part
      : part.replace(/[a-zA-Z]/g, (c) => PSEUDO_MAP[c] || c)))
    .join('');

  // Padding is measured on the TRANSLATABLE text only — padding proportional to
  // placeholder names would vary with the variable's spelling, which is noise.
  const translatableLength = parts
    .filter((p) => !/^\{[^{}]*\}$/.test(p))
    .join('').length;
  const tail = '·'.repeat(Math.max(0, Math.round(translatableLength * pad)));
  const body = tail ? `${accented}${tail}` : accented;
  return brackets ? `[[${body}]]` : body;
}

/**
 * Which keys a locale has not translated yet (LC6.12's "flags the untranslated
 * remainder").
 *
 * A key counts as translated only when the locale supplies its OWN value.
 * Falling back to English is what makes the app usable and is exactly what
 * makes the gap invisible, so a coverage report that counted fallbacks would
 * report 100% for a catalogue with nothing in it.
 *
 * Values identical to the base string are reported separately rather than as
 * missing: for `OK`, `Email` or a product name that is often correct, and
 * calling it untranslated would cry wolf until nobody reads the report.
 */
export function translationCoverage(dictionaries, opts = {}) {
  const base = opts.baseLocale || 'en';
  const flatten = (obj, prefix = '', out = {}) => {
    for (const [k, v] of Object.entries(obj || {})) {
      const path = prefix ? `${prefix}.${k}` : k;
      if (v && typeof v === 'object' && !Array.isArray(v)) flatten(v, path, out);
      else out[path] = v;
    }
    return out;
  };

  const baseFlat = flatten(dictionaries[base]);
  const keys = Object.keys(baseFlat);
  const locales = opts.locales || Object.keys(dictionaries).filter((l) => l !== base);

  const report = {};
  for (const locale of locales) {
    const flat = flatten(dictionaries[locale]);
    const missing = keys.filter((k) => flat[k] == null || flat[k] === '');
    const identical = keys.filter((k) => flat[k] != null && flat[k] === baseFlat[k]);
    const translated = keys.length - missing.length;
    report[locale] = {
      total: keys.length,
      translated,
      missing,
      identical,
      // Reported as a whole number beside its counts, never alone — the same
      // rule the progress board applies to every other percentage here.
      percent: keys.length ? Math.round((translated / keys.length) * 100) : 100,
      complete: missing.length === 0,
    };
  }
  return report;
}

/**
 * Is this a locale tag this runtime accepts?
 *
 * Intl throws a RangeError on a malformed tag, and locales reach us from
 * stored user preferences, so callers need to ask before they format.
 */
export function isUsableLocale(tag) {
  if (typeof tag !== 'string' || !tag) return false;
  try {
    new Intl.NumberFormat(tag);
    return true;
  } catch {
    return false;
  }
}

/** Is this an IANA zone this runtime accepts? Same reason as above. */
export function isUsableTimeZone(tz) {
  if (typeof tz !== 'string' || !tz) return false;
  try {
    new Intl.DateTimeFormat('en', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/**
 * Does this locale's clock run 0-23? Asked of Intl, not guessed from the tag:
 * en-AU, en-IN, hi-IN, ko-KR, ar-EG and es-MX are all 12-hour. Null when the
 * runtime cannot say, so the caller picks its own fallback.
 */
export function localeUses24Hour(locale) {
  try {
    const cycle = new Intl.DateTimeFormat(locale, { hour: 'numeric' }).resolvedOptions().hourCycle;
    return cycle === 'h23' || cycle === 'h24';
  } catch {
    return null;
  }
}

/**
 * "3 days ago" / "in 2 hours" in the given locale.
 *
 * `unit` and a signed `amount`, so the caller decides the granularity — this
 * layer only owns the Intl object and its cache.
 */
export function formatRelativeTime(amount, unit, locale, options = { numeric: /** @type {const} */ ('auto') }) {
  const tag = formattingTag(locale);
  const k = key(tag, { unit, ...options });
  let f = relativeCache.get(k);
  if (!f) {
    f = new Intl.RelativeTimeFormat(tag, options);
    relativeCache.set(k, f);
  }
  return f.format(amount, unit);
}

// --- the machine half (FMT-3) ---------------------------------------------

/**
 * **Nothing below this line is for a person to read.**
 *
 * ISO-8601, UTC, Latin digits, Gregorian — identical for every viewer in every
 * language, which is the entire requirement. These are the strings that go into
 * filenames, CSV cells, API payloads, sort keys and localStorage, and the reason
 * they are named apart from `format*` is that the two halves are impossible to
 * tell apart once they are both just strings:
 *
 * - a display string that gets PERSISTED is a time bomb — `03.08.2026` written
 *   by a German user is read back as March by an American one, or by the same
 *   user after they change one setting;
 * - an ISO string that reaches the UI is merely ugly, and therefore survives
 *   review — `until 2026-08-03T12:00:00.000Z` in a sentence is a leak, not a
 *   design.
 *
 * Both directions are checked in tests/localization/format-compliance.test.js.
 */

/** A usable Date from a Date/ISO string/epoch number, or null. */
function toDate(value) {
  if (value == null || value === '') return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** `2026-08-03` — a calendar date for storage, sorting or a CSV cell. */
export function toMachineDate(value) {
  const d = toDate(value);
  return d ? d.toISOString().slice(0, 10) : '';
}

/** `2026-08-03T12:00:00.000Z` — a full instant for an API payload or a record. */
export function toMachineDateTime(value) {
  const d = toDate(value);
  return d ? d.toISOString() : '';
}

/**
 * `2026-08-03T12-00-00Z` — the same instant, safe in a filename.
 *
 * Colons are legal on POSIX and forbidden on Windows, and an export named with
 * one downloads as a truncated or mangled file rather than failing loudly.
 */
export function toMachineStamp(value) {
  const iso = toMachineDateTime(value);
  return iso ? iso.replace(/\.\d{3}Z$/, 'Z').replace(/:/g, '-') : '';
}

/**
 * Does this string look like a machine timestamp?
 *
 * The guard for the direction that is easy to miss: a display surface asserting
 * that what it is about to render is NOT one of the strings above.
 */
export function isMachineDateString(value) {
  return typeof value === 'string'
    && /^\d{4}-\d{2}-\d{2}([T ]\d{2}[:-]\d{2}([:-]\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/.test(value.trim());
}

// --- the display half (FMT-4, FMT-5, FMT-8) -------------------------------

/**
 * The three granularities, named so a caller states which one it meant.
 *
 * FMT-4's point is that granularity is never silently chosen: a row that shows
 * a bare date for a value that carries a time has not formatted it, it has
 * discarded part of it, and the reader has no way to know which.
 */
export const GRANULARITY = Object.freeze({
  date: Object.freeze({ year: 'numeric', month: 'short', day: 'numeric' }),
  dateTime: Object.freeze({ year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }),
  time: Object.freeze({ hour: '2-digit', minute: '2-digit' }),
});

/**
 * A date for a person to read, at a stated granularity, in a stated zone.
 *
 * `timeZone` defaults to the viewer's own (FMT-5) — `undefined` is what tells
 * Intl to use the runtime zone, which is what someone reading a due date wants.
 * The stored value stays UTC; only this rendering moves.
 *
 * `withZone` appends the short zone name, and exists because "14:00" is a
 * different fact in two places. Audit entries, scheduled jobs and price
 * snapshots are the cases where the reader has to be told which clock they are
 * looking at; a due date is not, and would only be made noisier by it.
 *
 * @param {Date|string|number|null} value
 * @param {{ granularity?: 'date'|'dateTime'|'time', locale?: string,
 *           timeZone?: string, withZone?: boolean,
 *           options?: Intl.DateTimeFormatOptions }} [opts]
 */
export function formatDisplayDate(value, opts = {}) {
  const d = toDate(value);
  if (!d) return '';
  const base = GRANULARITY[opts.granularity || 'date'] || GRANULARITY.date;
  const zone = opts.withZone ? { timeZoneName: /** @type {const} */ ('short') } : {};
  return dateFormatter(formattingTag(opts.locale), {
    ...base, ...zone, ...(opts.timeZone ? { timeZone: opts.timeZone } : {}), ...(opts.options || {}),
  }).format(d);
}

/**
 * One of `forms` chosen by the locale's plural rules, with `{n}` filled in
 * (FMT-8).
 *
 * `${n} items` is wrong in most of the world and wrong for n=1 in all of it.
 * Slavic locales need three forms and Arabic six, so the caller supplies a map
 * keyed by CLDR category rather than a singular/plural pair; `other` is
 * required and is what any missing category falls back to.
 *
 * The count itself is formatted, not interpolated raw — a locale that groups
 * with spaces or writes Arabic-Indic digits must do so here too (FMT-6).
 */
export function formatPlural(count, forms, locale) {
  const n = Number(count);
  const tag = formattingTag(locale);
  const category = pluralCategory(n, tag);
  const template = forms && (forms[category] != null ? forms[category] : forms.other);
  return String(template ?? '').replace(/\{n\}/g, formatNumber(n, tag));
}

/**
 * A duration for a person to read (FMT-8).
 *
 * `Intl.NumberFormat`'s `unit` style knows the locale's own word for "hour" and
 * pluralises it; hand-built `${h}h ${m}m` is English typography that reads as
 * noise elsewhere. Only the largest whole unit is shown, which is what a
 * duration in a table cell is for.
 */
export function formatDuration(ms, locale, options = {}) {
  const n = Number(ms);
  if (!Number.isFinite(n)) return '';
  /** @type {[Intl.NumberFormatOptions['unit'], number][]} */
  const units = [['day', 86400000], ['hour', 3600000], ['minute', 60000], ['second', 1000]];
  const [unit, size] = units.find(([, s]) => Math.abs(n) >= s) || ['millisecond', 1];
  const amount = size === 1 ? n : n / size;
  return formatNumber(amount, locale, {
    style: 'unit', unit, unitDisplay: 'long', maximumFractionDigits: size === 1 ? 0 : 1, ...options,
  });
}

// --- what a locale itself says about dates and weeks ----------------------

/**
 * Which order this locale writes a numeric date in: MDY, DMY or YMD.
 *
 * Asked of `Intl` rather than kept in a table. A 36-row table of date orders is
 * a 36-row table of things to get wrong, and CLDR already knows — reading the
 * answer back out of `formatToParts` is the same data with nobody maintaining a
 * copy of it.
 */
export function localeDateOrder(locale) {
  const parts = dateFormatter(formattingTag(locale), {
    timeZone: 'UTC', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date(Date.UTC(2026, 7, 3)));
  const order = parts.filter((p) => p.type !== 'literal').map((p) => p.type[0].toUpperCase()).join('');
  return ['MDY', 'DMY', 'YMD'].includes(order) ? order : 'YMD';
}

/**
 * The day this locale's week starts on, 0=Sunday, matching `Date#getDay`.
 *
 * `getWeekInfo()` numbers days 1=Monday..7=Sunday, so Sunday has to come back
 * to 0. Older runtimes do not implement it at all, hence the guard — a calendar
 * that starts on the wrong day is a nuisance, one that throws is a blank page.
 */
export function localeFirstDayOfWeek(locale) {
  try {
    // TWO spellings, because this API changed shape after it shipped: V8 gave
    // it as a `weekInfo` GETTER first and only later as a `getWeekInfo()`
    // method, and Safari did the same. Asking for the method alone silently
    // takes the fallback on every runtime carrying the older one — Node 22
    // among them, which is what CI runs. The symptom is not a crash: it is
    // this function quietly answering Monday for the Sunday-start locales, so
    // their calendars start on the wrong day and nothing says why.
    //
    // The cast is still needed: `getWeekInfo` postdates the configured TS lib.
    const loc = /** @type {*} */ (new Intl.Locale(formattingTag(locale)));
    const info = typeof loc.getWeekInfo === 'function' ? loc.getWeekInfo() : loc.weekInfo;
    const first = info && info.firstDay;
    return typeof first === 'number' ? first % 7 : 1;
  } catch {
    return 1;
  }
}

