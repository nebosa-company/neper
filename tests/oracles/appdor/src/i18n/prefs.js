/**
 * The stored side of region preferences.
 *
 * src/i18n/format.js is pure and knows nothing about where preferences live;
 * this is the thin adapter that reads and writes them, plus bound helpers so
 * call sites read as `num(x)` rather than threading a prefs object through
 * every render function.
 *
 * Kept separate so the formatting logic stays testable without a storage stub,
 * and so there is exactly one place that decides what "the current user's
 * preferences" means.
 */
import { resolvePreferences, formatNumber, formatCurrency, formatMoney, formatPercent, formatDate, formatTime, formatDateTime, formatRelative, formatBytes, formatMonth, formatCount, formatDuration, weekdayOrder, startOfWeek, toMachineDate, toMachineDateTime, toMachineStamp, isMachineDateString } from './format.js';
import { SOURCE_LOCALE, localeByCode, resolveLocale as codeFromTag, intlTag } from '../localization/locales.js';
import { setActiveLocaleSource } from '../localization/index.js';

export const PREFS_KEY = 'appdor.region';

/**
 * The key src/language.js writes. It was `appdor_language` here and `language`
 * there, so the storage branch below never matched and this fell through to the
 * `<html lang>` attribute — which happens to be set, so nothing looked broken,
 * but anything running before the first `applyTranslations()` (or off-DOM, in a
 * worker or a test) formatted in English regardless of the choice. FMT-1's
 * defect, reached through a typo rather than through a call site.
 */
const LANG_KEY = 'language';

/** The key an older build used. Read, never written; a stored choice is a choice. */
const LEGACY_LANG_KEY = 'appdor_language';

/** Storage that works in a browser, a test, and a worker. */
function store() {
  try {
    return typeof localStorage !== 'undefined' ? localStorage : null;
  } catch {
    return null;   // Safari private mode throws on access, not on use
  }
}

/**
 * The app language, without importing language.js (which imports this).
 *
 * Any of the 36 supported codes, not the two the product ships strings in: a
 * viewer whose interface is untranslated still gets their own number grouping
 * and date order, and a language whose translations land later needs no change
 * here. Tolerant of tags too, since `<html lang>` may hold a region-qualified
 * one.
 */
function currentLanguage() {
  const s = store();
  for (const key of [LANG_KEY, LEGACY_LANG_KEY]) {
    try {
      const entry = localeByCode(s && s.getItem(key));
      if (entry) return entry.code;
    } catch { /* fall through to the next source */ }
  }
  if (typeof document !== 'undefined' && document.documentElement) {
    const attr = document.documentElement.getAttribute('lang');
    const entry = localeByCode(attr) || localeByCode(codeFromTag(attr));
    if (entry) return entry.code;
  }
  return SOURCE_LOCALE;
}

/**
 * **FMT-1, wired up.** This is the one call that makes "pass no locale" mean
 * "the language the user picked" everywhere in the product.
 *
 * Registered at module load, and this module is imported by every surface that
 * formats anything, so the localization layer stops defaulting to the source
 * locale as soon as the first of them loads. It is a getter rather than a tag
 * because the language changes mid-session.
 */
setActiveLocaleSource(currentLanguage);

/** The active app language, as one of the 36 codes. */
export function activeLanguage() {
  return currentLanguage();
}

/**
 * The active app language as a tag `Intl.*` understands — `zh-Hant`, not `zht`.
 *
 * The accessor for code that has to reach Intl-adjacent APIs this layer does
 * not wrap (a chart library's locale option, an `Intl`-backed third party).
 * Passing the raw product code there is the failure this exists to prevent:
 * `zht` is well-formed BCP-47, so nothing throws and the output is English.
 */
export function activeLocaleTag() {
  return intlTag(currentLanguage());
}

/**
 * The machine half of FMT-3, reachable from the same import as the display
 * half — so the choice between "show this" and "store this" is made by picking
 * a name, not by remembering a rule.
 */
export { toMachineDate, toMachineDateTime, toMachineStamp, isMachineDateString };

/**
 * The resolved preferences, memoised for the rest of the current task.
 *
 * Every bound helper (`num`, `date`, `money` ...) calls loadPrefs(), and a grid
 * formatting 10k cells did a getItem + JSON.parse + resolvePreferences + the
 * language lookup (two more reads and a DOM attribute) for each of them. Within
 * one synchronous pass nothing can have changed the answer, so it is computed
 * once and dropped at the next microtask; a save, a cross-tab `storage` event
 * and `invalidatePrefsCache()` drop it at once; a change of the stored language
 * is noticed by comparing it on every call (one getItem).
 */
let memo = null;
let memoTag = null;

export function invalidatePrefsCache() {
  memo = null;
}

if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
  window.addEventListener('storage', invalidatePrefsCache);
}

/** The resolved preferences in effect right now. */
export function loadPrefs() {
  // The stored language is part of the memo's identity: nothing calls
  // invalidatePrefsCache() on a language switch, and the resolved locale,
  // currency and date order all follow the language.
  let tag = null;
  try { const s = store(); tag = s && s.getItem(LANG_KEY); } catch { /* unreadable storage: no tag */ }
  if (memo && memoTag === tag) return memo;
  const fresh = readPrefs();
  memo = fresh;
  memoTag = tag;
  if (typeof queueMicrotask === 'function') queueMicrotask(invalidatePrefsCache);
  else memo = null;
  return fresh;
}

function readPrefs() {
  const s = store();
  let saved = {};
  try {
    const raw = s && s.getItem(PREFS_KEY);
    if (raw) saved = JSON.parse(raw) || {};
  } catch {
    saved = {};   // a corrupt blob must not break every date on the page
  }
  return resolvePreferences(saved, currentLanguage());
}

/** Merge a patch into the stored preferences and return the new resolved set. */
export function savePrefs(patch = {}) {
  const s = store();
  let saved = {};
  try {
    const raw = s && s.getItem(PREFS_KEY);
    if (raw) saved = JSON.parse(raw) || {};
  } catch { saved = {}; }
  const next = { ...saved, ...patch };
  try {
    if (s) s.setItem(PREFS_KEY, JSON.stringify(next));
  } catch { /* storage full or blocked; the session still works */ }
  invalidatePrefsCache();
  return resolvePreferences(next, currentLanguage());
}

/** Forget the stored choices and fall back to the language defaults. */

// Bound helpers. Each reads the current preferences, so a call site never has
// to know they exist — which is what stops the next hardcoded 'en-US'.
export const num = (value, options) => formatNumber(value, loadPrefs(), options);
export const money = (value, currency) => formatCurrency(value, loadPrefs(), currency);
/** Money that carries its own currency (FMT-7); the two arguments travel together. */
export const amount = (value, currency) => formatMoney(value, currency, loadPrefs());
export const pct = (fraction, digits) => formatPercent(fraction, loadPrefs(), digits);
export const date = (value) => formatDate(value, loadPrefs());
export const time = (value) => formatTime(value, loadPrefs());
export const dateTime = (value) => formatDateTime(value, loadPrefs());
export const relative = (value, now) => formatRelative(value, loadPrefs(), now);
export const bytes = (value) => formatBytes(value, loadPrefs());
export const monthLabel = (value) => formatMonth(value, loadPrefs());
/** `count(3, { one: '{n} record', other: '{n} records' })` (FMT-8). */
export const count = (value, forms) => formatCount(value, forms, loadPrefs());
export const duration = (ms) => formatDuration(ms, loadPrefs());
export const weekdays = () => weekdayOrder(loadPrefs());
export const weekStartOf = (value) => startOfWeek(value, loadPrefs());
