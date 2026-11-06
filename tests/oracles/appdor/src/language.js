/**
 * The UI-chrome translation runtime.
 *
 * Owns which language is active, where that choice is stored, the URL segment
 * (`/en`, `/bg`), the `lang`/`dir` attributes on `<html>`, and the DOM sweep
 * that paints translated text. It is the only module in the app that touches the
 * document for translation, and the only one that owns `localStorage.language`.
 *
 * It does NOT own the catalogue any more. The strings used to be a 690-line
 * object literal here with two languages in it; they now live in
 * `locales/<code>.json` and reach this module through
 * `src/localization/bundle-loader.js`. It does not own `Intl` either — plural
 * category selection is delegated to `src/localization/index.js`, and the
 * product code -> BCP-47 tag mapping to `src/localization/locales.js`, because
 * `zht` is a well-formed tag that silently resolves to US English.
 */

// The map, not the renderer. `grid/chart-svg.js` re-exports this and would be
// the obvious import, but it reaches back here through `cell-render.js` and
// `tests/import-cycles.test.js` rejects the cycle. `grid/chart-types.js`
// imports nothing; see its header.
import { RENDERABLE_CHART_TYPES } from './grid/chart-types.js';
import { LOCALES, SOURCE_LOCALE, localeByCode, isRtlLocale, intlTag, resolveLocale } from './localization/locales.js';
import { pluralCategory, humanizeKey } from './localization/index.js';
import { UI, PROSE, MARKET, ADMIN, getBundle, isBundleResident, loadBundle, hasBundleFor, onBundleLoaded } from './localization/bundle-loader.js';

const LANG_KEY = 'language';

/**
 * The language codes, keyed by uppercase code.
 *
 * Kept as an object rather than replaced by the registry because callers read
 * `LANGUAGES.EN` / `LANGUAGES.BG` by name (`src/settings.js` does, in five
 * places) and those two must keep resolving. It is DERIVED from the registry
 * instead of restated, so the two can never disagree about what is supported —
 * the previous copy of this list was duplicated into `src/i18n/prefs.js` and
 * `src/i18n/format.js` and all three drifted.
 */
export const LANGUAGES = Object.freeze(
  Object.fromEntries(LOCALES.map((l) => [l.code.toUpperCase(), l.code])),
);

/**
 * The same codes as a LIST, for every caller that wants to iterate them.
 *
 * {@link LANGUAGES} is a keyed object and reads like a list — it is plural, it
 * holds nothing but codes, and the name gives no hint that it is not one. A
 * caller mapping over it does not get an empty answer; it gets a TypeError,
 * because a frozen object has no `map`. That is exactly what happened to the
 * dashboard surface's embed-parameter call: the throw landed in the prelude of
 * `setupDashboardSurface`, ahead of the first paint, and every dashboard page in
 * the build rendered the load-failure panel.
 *
 * So the list is exported beside the object rather than reconstructed at each
 * call site. Both are derived from the one registry, so neither can drift from
 * it or from the other, and a caller that wants to iterate now has something to
 * iterate that is not a trap.
 *
 * @type {readonly string[]}
 */
export const LANGUAGE_CODES = Object.freeze(LOCALES.map((l) => l.code));

/**
 * The language the URL asks for: the first path segment, `/en` or `/bg`.
 * Null when the path names neither.
 */
function languageFromPath() {
  if (typeof window === 'undefined' || !window.location) return null;
  const segment = String(window.location.pathname || '').split('/')[1];
  const entry = localeByCode(segment);
  return entry ? entry.code : null;
}

/**
 * Read the stored language without letting storage take the app down (L10N-5).
 *
 * `localStorage` is not merely empty in a private window or with site data
 * blocked — reading it THROWS a SecurityError. This module runs during boot, so
 * an uncaught throw here is a blank page, in the one configuration where the
 * user has told the browser to be careful.
 */
function readStoredLanguage() {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage.getItem(LANG_KEY);
  } catch {
    return null;
  }
}

/** Persist the choice; a storage failure costs persistence, not the session. */
function writeStoredLanguage(lang) {
  try {
    if (typeof localStorage !== 'undefined') localStorage.setItem(LANG_KEY, lang);
  } catch {
    // Nothing to tell the user: the language still changed, it just will not be
    // remembered on the next visit.
  }
}

/**
 * Get the current language: the URL first, then localStorage, then the browser.
 *
 * **The URL wins, and that ordering is the fix for a real defect.**
 * `initLanguage()` has always treated `/bg` as authoritative — but it runs at
 * the END of the boot sequence, and `t()` is called before it: `src/main.js`
 * builds the analytics consent banner and attaches the PWA install affordance
 * first (the install listener has to be early, because `beforeinstallprompt`
 * fires once). On a first visit to `/bg` from a browser reporting US English,
 * storage was empty and this function answered "en" — so the consent notice
 * appeared in English on a page that was otherwise entirely in Bulgarian.
 *
 * The `applyTranslations()` that follows could not repair it: those two are
 * built once, from `t()`, and carried no `data-i18n` for it to find. Reading
 * the URL here fixes every such caller at once rather than reordering boot and
 * hoping the next early caller remembers.
 */
export function getCurrentLanguage() {
  const fromPath = languageFromPath();
  if (fromPath) return fromPath;

  const savedEntry = localeByCode(readStoredLanguage());
  if (savedEntry) return savedEntry.code;

  // Detect from the browser — but only into a language we can actually serve.
  //
  // `resolveLocale` maps a real browser tag onto one of our codes (`zh-TW` ->
  // `zht`, `nb` -> `no`, `ar-EG` -> `ar`). The `hasBundleFor` gate is the part
  // that matters: 34 of the 36 supported codes have no bundle authored yet, and
  // auto-selecting one would mark the document `lang="de"` while every string on
  // it is English. Guessing wrong about the language of the text is worse for a
  // screen reader than not guessing. An EXPLICIT choice — the URL or a stored
  // preference, both above — is honoured either way; the user asked for it.
  if (typeof navigator !== 'undefined' && navigator.language) {
    const detected = resolveLocale(navigator.language);
    if (detected && hasBundleFor(UI, detected)) return detected;
  }

  return SOURCE_LOCALE;
}

/**
 * Numbers the product states about itself, counted from the product.
 *
 * The trust bar on the homepage is a list of claims, and a claim typed into a
 * sentence rots the moment the code moves: it said "48 field types, 13 with
 * format & checksum validation" against a registry that had grown to 62 and 27
 * — understating the product by a quarter and by half. Counting them here means
 * the sentence cannot disagree with the registry again, in either language.
 *
 * The two field-type counts are counted by a TEST rather than by an import;
 * they live in `CATALOGUE_SIZES` below with the other six for the reason spelled
 * out there. The guarantee is unchanged — the sentence still cannot disagree
 * with the registry — only the place the comparison happens moved.
 *
 * Computed per call rather than cached at module load: cheap (a lookup, only
 * for strings that contain a `{`), and never stale.
 */
function productNumbers(key) {
  // Counted by what a user can PICK and get the chart they asked for, not by
  // renderer functions: the dispatch draws pie and donut with one function but
  // they are two choices, so counting functions understates by three.
  //
  // This one had the same rot the field counts were fixed for and worse: the
  // sentence said 8 against 25, and `tests/homepage-claims.test.js` — a guard
  // written to stop the copy OVERSTATING — had the eight of the day hardcoded
  // into it, so it enforced the understatement. The mechanism was already here;
  // the count was simply never wired into it.
  if (key === 'chartTypes') return Object.keys(RENDERABLE_CHART_TYPES).length;
  // How many languages the product can actually SERVE, which is not
  // `LOCALES.length`: the registry declares 36 codes and `hasBundleFor` is the
  // only thing that knows whether a bundle exists behind one. They agree at 36
  // today, and the day a bundle is pulled for being 12% translated they stop
  // agreeing — at which point the homepage should say 35 by itself rather than
  // wait for somebody to notice. Free: both are already imported above, for the
  // language switcher.
  if (key === 'locales') return LOCALES.filter((l) => hasBundleFor(UI, l.code)).length;
  // Counts this module cannot import for itself, PUSHED in by whoever owns
  // them. `{integrations}` is the connections catalog, and the dependency runs
  // this way round for two separate reasons that both point the same direction:
  // the catalog is a 130 kB chunk deliberately kept out of the main bundle (see
  // `ensureCatalog` in `connections/index.js`), and importing it here drags
  // `sdk` -> `auth-schemes`/`etl` into the tsconfig include graph, which that
  // file's own notes single out as the expensive one.
  //
  // Unregistered returns null, so `{integrations}` is left standing rather than
  // resolving to "Search 0 integrations" — the caller registers it before the
  // only screen that reads it renders.
  if (registered.has(key)) return registered.get(key);
  if (Object.hasOwn(CATALOGUE_SIZES, key)) return CATALOGUE_SIZES[key];
  return null;
}

/**
 * The eight catalogue sizes the marketing page states that neither an import
 * nor a push can deliver here.
 *
 * The push above is the right mechanism when the owning module is CERTAIN to
 * have run before the sentence renders — `connections/index.js` registers
 * `{integrations}` on its way to drawing the only picker that reads it. The
 * homepage numbers band is the opposite case on both halves:
 *
 *  - it renders on first paint of a logged-out route, before anything has been
 *    interacted with, so there is no moment at which a pushing module could
 *    have run; an unregistered key leaves a literal `{templates}` on screen;
 *  - and every module that owns one of these counts is precisely a module the
 *    marketing entry is built to stay out of. `templates/index.js` statically
 *    imports 42 definition modules and emits a 1,038 kB chunk; the two element
 *    registries reach `element-engines.js`, `pagebuilder/index.js` and
 *    `views/query.js`; `grid/page-elements.js` and `grid/view-types.js` both
 *    import `t` from THIS file, so an import back would be a cycle
 *    `tests/import-cycles.test.js` rejects outright.
 *
 * So they are literals — which docs/work-os-redesign.md §13.4 names as the
 * alternative for exactly this reason — and the thing that makes a literal
 * safe is that it is not maintained by hand. `tests/homepage-sections.test.js`
 * asserts each one EQUAL to the registry that owns it, so a template added or
 * a widget retired fails the build here rather than rotting on the page. That
 * is the same guarantee `{chartTypes}` has, bought at zero bytes on a route
 * that has 6 kB of JS headroom left.
 *
 * A `registerProductNumber` push still WINS over these, so a signed-in surface
 * that has legitimately loaded a registry can upgrade the figure to a live one
 * without this table having to be removed first.
 *
 * The two field-type counts joined the table on 2026-09-03, and they are the
 * clearest case of the rule above rather than an exception to it. They were
 * `Object.values(FIELD_TYPES)` counted in `productNumbers`, which meant this
 * module statically imported `src/fields/registry.js` — and because
 * `vite.config.js:637` tests `isShellModule(id)` BEFORE every subsystem rule,
 * any module in `boot.js`'s static closure lands in `shell` whatever its own
 * rule says. Measured with the config's own `staticClosure` over the tree:
 * that one edge dragged 9 modules / 114,785 B of source into the chunk every
 * cold load of `/` fetches before first paint — `fields/nace.js` (a 22,774 B
 * NACE industry-code table), `fields/barcode.js`, `validation/validators.js`
 * and four formatters — none of which the logged-out page renders anything
 * with. `scripts/bundle-budget.mjs` had 4,046 B of arrival headroom at the
 * time. Two integers do not cost a field engine.
 */
const CATALOGUE_SIZES = Object.freeze({
  fieldTypes: 90,           // FIELD_TYPES                — src/fields/registry.js
  validatingFieldTypes: 66, // FIELD_TYPES with .validates — src/fields/registry.js
  pageElements: 48,      // LAUNCH_ELEMENTS               — src/grid/page-elements.js
  dashboardWidgets: 24,  // WIDGET_TYPES                  — src/dashboards/widgets.js
  // Twelve, and it was twelve before — but it was pinned to the WRONG registry,
  // which is the failure mode this whole table exists to prevent and the one
  // shape of it a count alone cannot catch. `registerBuiltinViewTypes` in
  // `src/grid/view-types.js` also registers twelve, so every gate agreed on the
  // number while the page named `list` (unreachable) and omitted `gantt`
  // (shipping). `docs/unwired-modules.md` files that module as superseded and
  // nothing under `src/` imports it; `applications.js:90` reads `nav/toolbar.js`.
  // tests/homepage-sections.test.js now holds this EQUAL to `VIEW_TYPES`.
  viewTypes: 12,         // VIEW_TYPES                    — src/nav/toolbar.js
  templates: 64,         // TEMPLATE_CATALOG              — templates/index.js
  formulaFunctions: 279, // functionCatalog().length      — src/formula/index.js
  // The homepage's proof band states this one too, and until 2026-08-27 it was
  // a literal `7` inside `home.s6` and the hero badge — 72 hand-maintained
  // digits bounded only by a "not overstated" ceiling in
  // tests/homepage-claims.test.js. `src/formula/compat/index.js` is the owner
  // and is no more importable from here than `src/formula/index.js` is, for the
  // same cycle reason, so it joins the pinned table and
  // tests/homepage-sections.test.js holds it EQUAL to `DIALECTS`.
  dialects: 7,           // Object.keys(DIALECTS).length  — src/formula/compat/index.js
});

/** Counts pushed in by the module that owns them; see `productNumbers`. */
const registered = new Map();

/**
 * Publish a live count for `{key}` substitution in translated copy.
 *
 * The point is that a sentence cannot disagree with the thing it counts. The
 * connections picker read "Search 100 integrations" in 35 languages against a
 * catalog that was no longer 100, which is the same failure the field-type
 * claim above was fixed for.
 */
export function registerProductNumber(key, value) {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) registered.set(key, value);
}

/**
 * Substitute every `{count}` the product states about itself; leave every
 * other brace alone.
 *
 * The alternation is written out rather than made `\w+` on purpose. An
 * open-ended pattern would swallow `{name}` and `{count}` — the placeholders
 * `interpolateNamed` fills from a CALLER's params — and turn them into the
 * literal text they were standing in for, because an unknown key here returns
 * null and is left standing only by accident of ordering. Naming the eleven
 * keeps the two mechanisms from reaching into each other.
 */
function fillProductNumbers(value) {
  if (typeof value !== 'string' || !value.includes('{')) return value;
  return value.replace(/\{(fieldTypes|validatingFieldTypes|chartTypes|integrations|locales|pageElements|dashboardWidgets|viewTypes|templates|formulaFunctions|dialects)\}/g, (whole, key) => {
    const n = productNumbers(key);
    return n === null ? whole : String(n);
  });
}

/**
 * Substitute named placeholders (L10N-8).
 *
 * Named, never positional, so a translator may REORDER them freely: German puts
 * the object before the verb, and a `%s`-style string cannot express that
 * without the translation being wrong. An UNKNOWN placeholder is left standing
 * as `{whatever}` rather than replaced with nothing — a visible `{count}` in the
 * UI is a bug report, whereas "Deleted  records" reads as finished copy and
 * ships. `src/localization/index.js`'s private `interpolate` empties them; this
 * one does not, and that difference is deliberate.
 *
 * Called only when params are supplied, so the pre-existing strings that carry
 * literal braces for the caller to replace itself (`apps.deleteConfirmNamed`
 * substitutes `{name}` with escaped, emphasised markup) are untouched.
 */
function interpolateNamed(value, params) {
  if (typeof value !== 'string' || !params || !value.includes('{')) return value;
  return value.replace(/\{(\w+)\}/g, (whole, name) => (
    params[name] === undefined || params[name] === null ? whole : String(params[name])
  ));
}

/**
 * Pick the CLDR category for a count-bearing value (L10N-16).
 *
 * A bundle value may be an object of categories instead of a string. Six exist
 * — zero/one/two/few/many/other — and how many a language USES is not ours to
 * decide: Arabic needs all six, Russian and Polish four, Japanese one. So the
 * category comes from `Intl.PluralRules` via `pluralCategory`, resolved through
 * `intlTag` (a raw `zht` would answer with English's rules and nothing would
 * throw), and never from a table written here.
 *
 * `other` is the last resort because CLDR guarantees every language has it.
 */
function selectPluralForm(categories, count, code) {
  if (count !== undefined && count !== null && Number.isFinite(Number(count))) {
    let category = 'other';
    try {
      category = pluralCategory(count, intlTag(code));
    } catch {
      category = 'other';
    }
    if (typeof categories[category] === 'string') return categories[category];
  }
  if (typeof categories.other === 'string') return categories.other;
  // A bundle with categories but no `other` is malformed; show something rather
  // than nothing, and let the parity test be the thing that complains.
  const first = Object.values(categories).find((v) => typeof v === 'string');
  return first === undefined ? undefined : first;
}

/** Raw value for a key in one locale, across every tier. `undefined` if absent. */
function rawFromLocale(key, code) {
  for (const tier of [UI, PROSE, MARKET, ADMIN]) {
    const bundle = getBundle(tier, code);
    if (bundle && Object.prototype.hasOwnProperty.call(bundle, key)) return bundle[key];
  }
  return undefined;
}

/**
 * The fallback chain (L10N-3): active locale -> source -> nothing.
 *
 * Returns `undefined` rather than a placeholder, so the two callers can differ:
 * `t()` needs something printable, the DOM sweep needs to know to leave the
 * element alone. Collapsing them is what would put "Title" over an input that
 * already said "Company name" in the markup.
 */
function resolveValue(key, code, params) {
  let raw = rawFromLocale(key, code);
  if (raw === undefined && code !== SOURCE_LOCALE) raw = rawFromLocale(key, SOURCE_LOCALE);
  if (raw === undefined) return undefined;

  const count = params ? params.count : undefined;
  const value = (raw && typeof raw === 'object' && !Array.isArray(raw))
    ? selectPluralForm(raw, count, code)
    : raw;
  if (typeof value !== 'string') return undefined;

  return interpolateNamed(fillProductNumbers(value), params);
}

/** Keys already reported, so a re-render does not repeat itself forever. */
const reportedMissing = new Set();

/**
 * What a viewer sees when NOTHING translates a key (L10N-3's third step).
 *
 * Never the dotted path. `settings.import.title` on screen tells a user nothing
 * and tells them the product is broken; "Title" is wrong-ish but reads as a
 * label. The key still reaches whoever can fix it — once per key, on the
 * console, where it is loud in development and invisible to a customer.
 */
function missingKeyPlaceholder(key) {
  /**
   * Silent until there is a catalogue to be missing FROM.
   *
   * Modules whose labels are getters — the chart registry, the AI block
   * descriptors, the PWA capability table — are read as their module is
   * evaluated, which is before the source bundle has been fetched. At that
   * moment `rawFromLocale` cannot resolve ANY key, so every one of them warned,
   * and a clean boot printed forty-one "no translation" lines for keys that all
   * exist and all render correctly a moment later.
   *
   * That is worse than untidy: it is a warning that cannot be acted on, sitting
   * in the same channel as the one that can, and it trained everybody to scroll
   * past both. A sweep of the whole product reported 41 missing keys and zero
   * of them were missing.
   *
   * `isBundleResident`, not `getBundle`, for the reason the retry loop below
   * gives: `getBundle` answers with the pre-hydration floor, which would make
   * this read as "loaded" from the first tick and restore the noise. The
   * placeholder is still returned either way — only the console line waits.
   */
  if (!reportedMissing.has(key) && isBundleResident(UI, SOURCE_LOCALE)) {
    reportedMissing.add(key);
    console.warn(`[i18n] no translation for "${key}" in any locale`);
  }
  return humanizeKey(key) || String(key);
}

/** Keys that reached `missingKeyPlaceholder` this session. For tooling/tests. */
export function missingTranslationKeys() {
  return [...reportedMissing];
}

/**
 * Set the current language
 *
 * @param {string} lang
 * @param {{replace?: boolean}} [opts] `replace`: put the language in the address
 *   bar WITHOUT adding a history entry. Only an explicit user switch should push
 *   one; the initial language, and a language read back from history, must not
 *   (the first visit to `/` otherwise needed Back pressed twice).
 */
export function setLanguage(lang, opts = {}) {
  const entry = localeByCode(lang);
  if (!entry) {
    console.warn(`Invalid language: ${lang}`);
    return;
  }
  const code = entry.code;

  writeStoredLanguage(code);
  // URL BEFORE the re-render. `getCurrentLanguage()` now reads the path, and
  // `applyTranslations` re-entrantly triggers renderers that call `t()` with no
  // explicit language — so a stale `/en` in the address bar during the repaint
  // would hand those callers the language we are leaving.
  updateURL(code, opts.replace === true);
  applyTranslations(code);
  notifyLanguageChange(code);

  // No reload, no state loss (L10N-4): the switch has already repainted from
  // whatever is in memory. If this locale's bundle is not in memory yet, the
  // fetch runs behind the paint and the arrival repaints again (L10N-12), so a
  // slow network costs a moment of English rather than a blank or frozen page.
  ensureBundle(code);
}

/**
 * Start (or reuse) the load of a locale's UI bundle. Never awaited by callers.
 *
 * A failed load is retried behind the paint. The loader distinguishes "we ship
 * no bundle for this locale" from "the fetch threw" and stops answering after
 * its own attempt budget, so this loop terminates on both — but without a
 * caller to re-ask, a retryable failure is never retried, and one dropped
 * request pins the session to English. The delay grows so a genuinely offline
 * visitor is not fetching in a tight loop.
 *
 * **`isBundleResident`, not `getBundle`.** `getBundle` answers with the
 * pre-hydration floor when the real catalogue has not arrived, which is correct
 * for a caller that wants a string and wrong for the caller that decides
 * whether to fetch: asking it here would make an English visitor skip the fetch
 * forever and read a page built from five real strings and humanized key paths
 * — which looks like English, so nobody would report it.
 *
 * **The source locale is fetched on exhaustion, and retried like the active
 * one.** English used to be inlined in the arrival chunk, so `resolveValue`'s
 * fallback was free and a bundle that never arrived cost nothing. It is a
 * network fetch now. `[i18n] bundle-load-failed ui/ja` and `ui/ko (3/3)` are in
 * the build log, so this is an observed path and not a hypothetical one: when
 * the active locale is spent, the fallback has to be requested or the viewer is
 * left on the floor.
 */
const RETRY_BACKOFF_MS = 400;

function ensureBundle(code, attempt = 0) {
  if (isBundleResident(UI, code)) return Promise.resolve(true);
  return loadBundle(UI, code).then((b) => {
    if (b) return true;
    // The ACTIVE locale is worth retrying because it is the screen; the SOURCE
    // locale is worth retrying because it is every other screen's last resort.
    // A background preload of some third language failing costs nobody anything.
    const worthRetrying = code === getCurrentLanguage() || code === SOURCE_LOCALE;
    if (attempt >= 2 || !worthRetrying) {
      // Spent. Go and get the fallback, which is no longer already here.
      if (code !== SOURCE_LOCALE && code === getCurrentLanguage()) ensureBundle(SOURCE_LOCALE);
      return false;
    }
    return new Promise((resolve) => {
      setTimeout(() => resolve(ensureBundle(code, attempt + 1)), RETRY_BACKOFF_MS * (attempt + 1));
    });
  });
}

/**
 * Load a locale's UI bundle and resolve when it is readable (L10N-13).
 *
 * The hook for a host that wants NO flash of source-locale text: await this
 * before the first paint. Resolves `false` when the locale has no bundle, which
 * is not an error — the app runs in English (L10N-17).
 */
export function preloadLanguage(lang = null) {
  return ensureBundle(localeByCode(lang)?.code || getCurrentLanguage());
}

/**
 * Load a locale's long-form prose bundle (L10N-13).
 *
 * Separate from the UI tier on purpose: help, onboarding and legal copy is the
 * bulk of a catalogue and none of it is needed to paint a screen. Call it when
 * opening the surface that shows it; `t()` reads the prose tier as soon as it
 * lands, and any view already on screen is repainted by the arrival hook below.
 *
 * **Falls back to the source locale, for the reason `ensureBundle` does.**
 * `resolveValue` walks active -> source, and since no bundle is eager that
 * second step is a FETCH rather than a memory read. Without this, a `prose/hi`
 * that never arrived would leave the legal page with nothing to show even
 * though English was one request away — the exact failure the UI tier already
 * learned, one tier over. Retries are `loadBundle`'s (`LOAD_ATTEMPTS`); this
 * only adds the second locale.
 *
 * @returns {Promise<boolean>} whether ANY prose bundle is now readable. `false`
 *   is a real outage rather than a missing translation, and it is the only
 *   thing a caller can honestly report to a viewer.
 */
export function loadProse(lang = null) {
  const code = localeByCode(lang)?.code || getCurrentLanguage();
  return loadBundle(PROSE, code).then((b) => {
    if (b) return true;
    if (code === SOURCE_LOCALE) return false;
    return loadBundle(PROSE, SOURCE_LOCALE).then(Boolean);
  });
}

/** Subscribers to re-render on a language change or a late bundle (L10N-12). */
const languageListeners = new Set();

/**
 * Re-render hook for views built from JavaScript rather than markup.
 *
 * `applyTranslations` can only repair elements carrying `data-i18n`. A view
 * rendered from a template literal — most of `src/applications.js` — has no
 * such attribute, so a bundle arriving after it painted would leave it in
 * English forever. Returns its own unsubscribe function.
 */
export function onLanguageChange(fn) {
  if (typeof fn !== 'function') return () => {};
  languageListeners.add(fn);
  return () => languageListeners.delete(fn);
}

function notifyLanguageChange(code) {
  for (const fn of [...languageListeners]) {
    // A throwing subscriber must not abort the rest of the repaint.
    try { fn(code); } catch (err) { console.warn('[i18n] language listener failed', err); }
  }
}

// Late-load correctness (L10N-12). A bundle that arrives after the view was
// painted repaints it: the DOM sweep fixes everything with a `data-i18n`, and
// the subscribers above fix everything without one.
//
// Scoped to the ACTIVE language, so a background preload of some other locale
// does not repaint — and to the SOURCE locale, which is not a background
// preload but the fallback every other locale resolves through. That second
// case only exists because English is no longer inlined in the arrival chunk:
// when `ui/de` fails and `ensureBundle` fetches `ui/en` behind the paint, the
// arriving bundle is `en` while the active language is still `de`, and the
// original condition would have dropped it on the floor. The page would have
// held humanized key paths with the strings that fix them sitting in memory.
//
// The repaint is driven by the ACTIVE language either way: `resolveValue`
// already walks active -> source, so painting `de` is what puts the freshly
// arrived English on screen for the keys `de` cannot answer.
onBundleLoaded(({ locale }) => {
  const active = getCurrentLanguage();
  if (locale !== active && locale !== SOURCE_LOCALE) return;
  if (typeof document !== 'undefined' && document.documentElement) applyTranslations(active);
  notifyLanguageChange(active);
});

/**
 * Point `<link rel="canonical">` at the address this rendering actually has.
 *
 * The same defect as the `<html lang>` write below it, one layer out. `/`,
 * `/en` and `/bg` serve a BYTE-IDENTICAL document — the locale is applied here,
 * in the browser, not by the server — so three URLs were offering a crawler the
 * same page with nothing saying which one is the page. index.html ships
 * `<link rel="canonical" href="/">`, which is right for two of the three and
 * wrong for `/bg`; this is the half that knows better, because it is the code
 * that just decided what language the document is in.
 *
 * The rule, and the reason for each arm:
 *
 *   - Source locale -> `/`. `/en` is not a second page, it is `initLanguage()`
 *     replaceState-ing the root, so the root is the address and `/en` is a
 *     rewrite of it. Folding them is the point of the tag.
 *   - Any other locale WITH a bundle -> `/{lang}`. `/bg` renders Bulgarian, so
 *     it is a genuinely different document and self-canonicalises.
 *   - Any other locale WITHOUT a bundle -> `/`. `LOCALES` declares 36 codes and
 *     two have bundles authored; `/de` therefore renders English at a URL that
 *     claims to be German. That is a duplicate of the root, and pointing it at
 *     the root is the honest answer — the alternative is 34 near-identical URLs
 *     competing with the page they are copies of. `hasBundleFor` is the same
 *     gate `getCurrentLanguage()` uses to refuse to auto-select such a locale.
 *
 * Absolute, from `location.origin`: the browser knows the host the build did not,
 * and docker/seo.mjs already wrote the absolute form this used to overwrite with
 * `/` (Lighthouse: "Is not an absolute URL"). A non-http origin keeps the path.
 *
 * No-ops rather than throws when the tag is absent: a test harness mounting a
 * bare `<div>` is not a page with a canonical URL, and translation must not
 * depend on head markup.
 *
 * @param {string} lang  the locale that has just been applied
 */
function updateCanonicalLink(lang) {
  const link = document.querySelector('link[rel="canonical"]');
  if (!link) return;
  const path = lang !== SOURCE_LOCALE && hasBundleFor(UI, lang) ? `/${lang}` : '/';
  const origin = /^https?:$/.test(globalThis.location?.protocol ?? '') ? location.origin : '';
  const href = origin + path;
  if (link.getAttribute('href') !== href) link.setAttribute('href', href);
}

/**
 * The interpolation values a marked element carries, if it carries any.
 *
 * `data-i18n` marks an element so the sweep can repaint it on a language
 * change, and the sweep resolved every key with NO params. For a plain string
 * that is correct. For a parameterised one — `billing.gate.availableFrom` is
 * "Available from {plan}" — it is not: the element painted correctly on first
 * render, because the render site called `translate(key, null, {...})` itself,
 * and then a language switch repainted it as the raw template with `{plan}`
 * showing. So every parameterised string had to choose between being right on
 * first paint and surviving a language change, and the way that choice got
 * made in practice was to leave the marker off and let the string go stale.
 *
 * `data-i18n-params` is the missing half: the values ride on the element as
 * JSON, so the sweep can resolve exactly what the render site resolved.
 *
 * Malformed JSON is treated as absent rather than thrown. A tooltip that falls
 * back to its un-interpolated template is a blemish; a `JSON.parse` that
 * escapes here aborts the whole sweep and leaves the REST of the page in the
 * previous language.
 */
function paramsFor(element) {
  const raw = element.getAttribute('data-i18n-params');
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Apply translations to all elements with data-i18n attribute
 */
export function applyTranslations(lang = null) {
  // Use the resolved currentLang (not the possibly-null `lang` arg), otherwise a
  // no-arg call re-renders dynamic content in English even when BG is active.
  const currentLang = lang || getCurrentLanguage();

  // Keep <html lang> honest. It stayed "en" while the page rendered Bulgarian,
  // so screen readers applied English pronunciation to Cyrillic text and search
  // engines mis-identified the page. Every language change flows through here.
  //
  // `dir` beside it is what actually turns RTL on for the four right-to-left
  // languages: the direction logic has existed and been tested for months with
  // no caller, because nothing in the app ever wrote the attribute it produces.
  //
  // The BCP-47 tag, not the product code: `zht` is not a language tag, so a
  // Traditional Chinese page announced itself as an unknown language — a
  // screen reader picked no Chinese voice and the browser chose Han glyphs by
  // guesswork. `intlTag` gives `zh-Hant`, `zh-Hans` and `nb`; every reader of
  // this attribute maps a tag back to a code (`resolveLocale`).
  if (typeof document !== 'undefined' && document.documentElement) {
    document.documentElement.setAttribute('lang', intlTag(currentLang));
    document.documentElement.setAttribute('dir', isRtlLocale(currentLang) ? 'rtl' : 'ltr');
    updateCanonicalLink(currentLang);
  }

  if (typeof document === 'undefined' || !document.querySelectorAll) return;

  document.querySelectorAll('[data-i18n]').forEach((element) => {
    const key = element.getAttribute('data-i18n');
    const translation = resolveValue(key, currentLang, paramsFor(element));

    // Falsy is skipped, and that is load-bearing twice over: `auth.title` is
    // deliberately empty in every locale, and a key no bundle defines leaves the
    // element's own markup text in place — which is real English copy, and a
    // better last resort than a humanized key path.
    if (translation) {
      if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA') {
        // The tagName check above is the narrowing; the cast writes it down for
        // the checker without an `instanceof`, which would need the constructor
        // globals to exist in every host that stubs `document`.
        /** @type {HTMLInputElement | HTMLTextAreaElement} */ (element).placeholder = translation;
      } else {
        element.textContent = translation;
      }
    }
  });

  // Attributes a user reads but cannot see in the text: tooltips, the
  // accessible name of an icon-only button, and the placeholder of an input
  // whose visible label lives elsewhere. `data-i18n` above can only reach
  // ONE of these per element (text, or placeholder), so a button with both a
  // label and a title had no way to translate the title — which is how every
  // sidebar toggle and every icon-only control stayed English on /bg.
  for (const [attribute, marker] of ATTRIBUTE_KEYS) {
    document.querySelectorAll(`[${marker}]`).forEach((element) => {
      const translation = resolveValue(element.getAttribute(marker), currentLang, paramsFor(element));
      if (translation) element.setAttribute(attribute, translation);
    });
  }
}

/**
 * Translate markup the moment it enters the document (L10N-4).
 *
 * `applyTranslations()` is a one-shot sweep: it runs at boot and on a language
 * change, and it can only reach what is in the DOM at that instant. The product
 * renders almost everything AFTER boot — `src/applications.js` alone has 105
 * `innerHTML = \`…\`` assignments and called the sweep exactly once — so a
 * `data-i18n` in any of those templates was inert. The key was right, the
 * catalogue had the translation, and the panel still painted English, which is
 * indistinguishable from "not translated yet" to everyone including us.
 *
 * Fixing that at 105 call sites is 105 chances to forget the 106th. Observing
 * the document fixes it once, for every template that exists now and every one
 * written later.
 *
 * Scoped tightly on purpose: only ADDED subtrees, only when they actually
 * contain a key, and the sweep is confined to that subtree rather than
 * re-running over the whole page. A render that adds no translatable markup
 * costs one `querySelector` that finds nothing.
 */
const KEY_SELECTOR = '[data-i18n],[data-i18n-title],[data-i18n-aria-label],[data-i18n-placeholder],[data-i18n-alt]';

function translateSubtree(root, code) {
  if (!root || root.nodeType !== 1) return;
  const nodes = root.matches?.(KEY_SELECTOR) ? [root, ...root.querySelectorAll(KEY_SELECTOR)]
    : [...root.querySelectorAll(KEY_SELECTOR)];
  for (const element of nodes) {
    // Read once per element and shared by the text and the attribute passes,
    // the same way `applyTranslations` does — the two sweeps must agree, or a
    // string would interpolate on a language change and not on first insert.
    const params = paramsFor(element);
    const key = element.getAttribute('data-i18n');
    if (key) {
      const translation = resolveValue(key, code, params);
      if (translation) {
        if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA') {
          /** @type {HTMLInputElement | HTMLTextAreaElement} */ (element).placeholder = translation;
        } else {
          element.textContent = translation;
        }
      }
    }
    for (const [attribute, marker] of ATTRIBUTE_KEYS) {
      const attrKey = element.getAttribute(marker);
      if (!attrKey) continue;
      const translation = resolveValue(attrKey, code, params);
      if (translation) element.setAttribute(attribute, translation);
    }
  }
}

let observer = null;

/**
 * Start translating late-rendered markup. Idempotent; safe to call more than
 * once. Returns the observer so a host or a test can disconnect it.
 */
export function observeTranslations() {
  if (observer || typeof MutationObserver === 'undefined' || typeof document === 'undefined') return observer;
  observer = new MutationObserver((records) => {
    const code = getCurrentLanguage();
    for (const record of records) {
      for (const added of record.addedNodes) translateSubtree(added, code);
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  return observer;
}

/** Attribute → the `data-i18n-*` attribute naming its key. */
const ATTRIBUTE_KEYS = [
  ['title', 'data-i18n-title'],
  ['aria-label', 'data-i18n-aria-label'],
  ['placeholder', 'data-i18n-placeholder'],
  // A photo or screenshot's description is read aloud, so it is copy like any other.
  ['alt', 'data-i18n-alt'],
];

/**
 * Update URL to reflect current language
 */
function updateURL(lang, replace = false) {
  // Compared WITHOUT a trailing slash, so `/en/` is already `/en` and is not
  // rewritten (and pushed) on every call.
  const currentPath = window.location.pathname.replace(/\/+$/, '') || '/';
  const newPath = `/${lang}`;

  if (currentPath !== newPath) {
    // The root is not a language page: moving off it is a redirect, not a step
    // the visitor took, so it replaces the entry instead of stacking another.
    const method = replace || currentPath === '/' ? 'replaceState' : 'pushState';
    // Search and hash carried over, for the same reason as the root redirect
    // below: `?share=` and `?form=` are the two public links, and replacing
    // the whole URL with `/en` dropped them. The page still rendered because
    // the token had already been read, so the loss only showed up on refresh.
    window.history[method]({ lang }, '', newPath + window.location.search + window.location.hash);
  }
}

/**
 * Get translation for a key.
 *
 * Synchronous, and it has to stay that way: `src/analytics/consent-ui.js` calls
 * it during boot, before `initLanguage()` runs, and eight render sites in
 * `settings.js` and `applications.js` call `applyTranslations()` straight after
 * an `innerHTML` assignment. An `await` anywhere in here is a blank consent
 * banner and eight untranslated panels.
 *
 * @param {string} key
 * @param {string|null} [lang]    explicit locale, else the active one
 * @param {object|null} [params]  named placeholder values; `count` also selects
 *                                the plural category when the value has one
 */
export function t(key, lang = null, params = null) {
  const currentLang = lang || getCurrentLanguage();
  const value = resolveValue(key, currentLang, params);
  return value === undefined ? missingKeyPlaceholder(key) : value;
}

/**
 * Does the catalogue know this key? (L10N-3's first two steps, asked and not
 * answered.)
 *
 * `t()` cannot be used to ASK this. It always returns something printable, and
 * for a key nobody translates that something is `humanizeKey(key)` plus a
 * console warning plus an entry in `missingTranslationKeys()`. That is right
 * for a render site, which has to put text on screen either way, and wrong for
 * a caller holding a string that may not be a key at all: passing
 * `export-run-failed` through `t()` would print "Export Run Failed" — invented
 * English for a machine code — and permanently poison the missing-key report
 * that tells translators what still needs writing.
 *
 * So this answers the question without rendering anything: true when the key
 * resolves in `lang`, or in the source locale behind it.
 *
 * @param {string} key
 * @param {string|null} [lang]  explicit locale, else the active one
 */
export function hasTranslation(key, lang = null) {
  if (typeof key !== 'string' || key === '') return false;
  return resolveValue(key, lang || getCurrentLanguage(), null) !== undefined;
}

/**
 * Initialize language functionality
 */
export function initLanguage() {
  // Check URL for language
  const pathLang = languageFromPath();
  const initialLang = pathLang || getCurrentLanguage();

  // Apply initial language. (The visible language buttons are the settings
  // page's #lang-en-btn/#lang-bg-btn, which settings.js binds and highlights.)
  setLanguage(initialLang, { replace: true });

  // Then keep translating whatever renders from here on. Almost nothing in this
  // product is in the DOM when the sweep above runs — panels, modals and the
  // grid are all painted later — so without this the sweep translates the shell
  // and nothing else.
  observeTranslations();

  // Handle browser back/forward buttons
  window.addEventListener('popstate', (event) => {
    if (event.state && event.state.lang) {
      setLanguage(event.state.lang, { replace: true });
    } else {
      const poppedLang = languageFromPath();
      if (poppedLang) setLanguage(poppedLang, { replace: true });
    }
  });

  // The root redirect now happens in the setLanguage(initialLang, { replace })
  // call above: `updateURL` replaces (never pushes) when leaving `/`, and it
  // CARRIES OVER the search and hash, so `?share=<token>` and `?form=<token>`
  // survive a refresh. The block that used to live here tested
  // `pathname === '/'` AFTER that call had already moved the path, so it never ran.
}
