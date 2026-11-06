/**
 * Translation-bundle loading, in two tiers (L10N-12, L10N-13, L10N-17).
 *
 * The strings used to live inline in `src/language.js` as a 690-line object
 * literal holding two languages. Thirty-six does not fit that shape: every
 * visitor would download all of them, and adding one English string would mean
 * editing the same file thirty-five more people are editing (L10N-Q9). So the
 * catalogue is data — `locales/<code>.json` — and this module is the only thing
 * that knows how to get it.
 *
 * ## The two tiers
 *
 * `ui` is chrome: labels, buttons, menu items, error messages. It is needed
 * SYNCHRONOUSLY — `t()` is called during boot, before `initLanguage()` runs
 * (`src/analytics/consent-ui.js` builds the consent banner, and the PWA install
 * listener has to attach before `beforeinstallprompt` fires). A tier that could
 * only be awaited would paint English on a Bulgarian page, which is the exact
 * defect `getCurrentLanguage()` reads the URL to avoid.
 *
 * `prose` is long-form: help, onboarding, legal. It is an order of magnitude
 * larger per language, it is read by a fraction of visitors, and none of it is
 * needed to paint a screen — so it is never in the always-loaded set (L10N-13).
 * It is fetched on demand and the view is corrected when it lands.
 *
 * It holds the LEGAL documents today — `<slug>.lastUpdated`, `<slug>.intro` and
 * `<slug>.body` for privacy, terms and the DPA. That is 77,469 B of `hi`, the
 * worst of the 36, and `session` in `scripts/bundle-budget.mjs` charges the
 * worst one because a session fetches exactly one. Every signed-in visitor was
 * downloading a legal document nobody reads, in whichever language they use.
 *
 * `<slug>.title` deliberately did NOT move, and the reason generalises to
 * anything else that lands here: a tier is only free to be lazy if nothing that
 * paints early needs a key from it. The marketing footer links each document
 * and LABELS the link with its title, so that one key has to be in `ui` — and
 * the gate the footer asks (`offersLegalDocument`) had to be split from the
 * renderer's (`hasLegalDocument`) to match. The help centre is the obvious next
 * candidate and does not pass that test as a prefix: `help.title` is swept out
 * of `index.html` on every load. `help.article.*` and `help.video.*` would.
 *
 * ## No bundle is eager. A FLOOR is.
 *
 * The source locale used to be eager, on the reasoning that it is the universal
 * fallback and a fallback that is not there yet is not a fallback. The reasoning
 * was right about the requirement and wrong about its size: it inlined all 3,390
 * English strings into the arrival chunk — 213,817 bytes, 64.5% of the 331,632
 * byte `shell` chunk, measured by brace-matching the compiled object literal in
 * the built asset rather than by sourcemap attribution, which charges a JSON
 * import's whole output to whatever module happens to precede it. Every visitor
 * downloaded it; 35 out of 36 then fetched their own catalogue on top and
 * rendered none of the English.
 *
 * What is actually needed before a fetch can resolve is much smaller than the
 * catalogue, and it is measurable rather than arguable: it is the keys `t()` can
 * be asked for from the static import closure of `src/boot.js`, because
 * everything else is behind an `import()` and cannot run first. That is five
 * keys in one module today. `scripts/i18n-boot-floor.mjs` derives them into
 * `boot-floor.en.json` (473 bytes) and `tests/localization/boot-floor.test.js`
 * fails when the derivation and the file disagree, so adding a `t()` call to a
 * pre-hydration module is caught rather than discovered by a reader of a
 * language nobody on the team speaks.
 *
 * The floor is NOT in `cache`, and that separation is load-bearing twice:
 * `loadBundle` short-circuits on a cache hit, so seeding the cache with the
 * floor would mean the real English bundle never loaded at all; and
 * `hasBundleFor` must keep answering for what we can SERVE rather than for what
 * is currently in memory. `getBundle` reads the floor only when the real bundle
 * is absent, so it disappears the moment the catalogue lands.
 *
 * `bg` used to be eager as well. That was defensible when it was the ONLY other
 * authored locale — the marketing page was written against it, and two tests
 * read `t('home.s6', 'bg')` with no await. It stopped being defensible the day
 * all 36 shipped: an eager `bg` is 119 KB of Bulgarian inlined into the main
 * chunk and downloaded by every visitor on earth, including the 35 out of 36
 * who did not ask for Bulgarian. The catalogue grew; the exception did not
 * survive the growth. The tests that needed it now install it explicitly
 * through `registerBundle`, which is what that seam is for.
 *
 * Adding a language is: write `locales/<code>.json` and `locales/prose/<code>.json`,
 * then run `node scripts/i18n-register-bundles.mjs --write`, which regenerates
 * BOTH tiers from what is on disk and refuses anything below 100%. (One line
 * per bundle, by hand, is the same thing done less reliably: `prose` shipped
 * loaders for 2 of 36 locales for as long as it was empty, and nothing said so.)
 * Adding an English string is: edit `locales/en.json`. Neither touches 35 files.
 *
 * ## Failure (L10N-17)
 *
 * A bundle that cannot be fetched is logged, and the loader answers `null`. It
 * never throws and never surfaces the failure to a viewer: the caller falls back
 * to the source locale and the app stays fully usable in English rather than
 * half-painted in nothing.
 *
 * **That fallback is now a fetch, and the caller has to make it.** While the
 * English catalogue was inlined it was free — a `ja` bundle that never arrived
 * cost nothing, because `resolveValue` read English out of memory. It is not in
 * memory any more, so `ensureBundle` in `src/language.js` requests the source
 * locale when the active one is exhausted, and retries it on the same budget it
 * gives the active locale. Without that, a failed `ui/ja` — which the build log
 * records as a real event, alongside a `ui/ko` that spent all three attempts —
 * would leave the page on the five-key floor and humanized key paths.
 *
 * **Two failures, and they are not the same failure.** A locale with no entry in
 * `LAZY` is permanently unavailable — asking again cannot change the answer, so
 * that is remembered forever. A loader that THREW is a different thing: a
 * dynamic import is a network fetch, and a fetch fails for reasons that pass. A
 * flaky connection, or a deploy rotating the hashed chunk names out from under a
 * page that is already open, would otherwise pin the whole session to English —
 * same URL, same key, same markup, translated on one load and English on the
 * next. That is indistinguishable from a missing translation to everyone
 * including us, which is why it is worth the retry budget below rather than one
 * strike.
 */

import { SOURCE_LOCALE, localeByCode } from './locales.js';

// The only catalogue bytes in the arrival chunk. Generated — see the header and
// `scripts/i18n-boot-floor.mjs`; do not hand-edit, and do not add keys to it
// that no pre-hydration module asks for.
// The import ATTRIBUTE is load-bearing outside the bundler. Vite does not need
// it; Node 22 does, and without it this line throws ERR_IMPORT_ATTRIBUTE_MISSING
// — which made `language.js`, and therefore `dashboards/widgets.js` and
// `resolveDashboard`, unimportable by any of the worker processes. The
// scheduled dashboard snapshot (LC20.12) resolves the SAME widget engine the
// screen resolves because of this one word; the alternative was a second
// resolver written for the server, which is how two surfaces come to disagree
// about the same numbers. Measured: `vite build` is unaffected.
import enBootUi from './boot-floor.en.json' with { type: 'json' };

/** Tier names. Exported so callers never spell them as bare strings. */
export const UI = 'ui';
export const PROSE = 'prose';
/**
 * The marketplace's own copy — ~360 strings that only the marketplace route
 * paints, so it is fetched when that route mounts (`loadMarket` in
 * `src/language.js`) rather than shipped in every session's `ui` bundle. The
 * one marketplace key the chrome needs early, `market.title` (the nav link),
 * stays in `ui` for the reason `<slug>.title` stayed out of `prose`.
 *
 * Its 36 loader stubs are NOT in `LAZY` below: this module is in the arrival
 * chunk, and ~2.5 kB of `import()` stubs for a page most visitors never open
 * took `arrival` over its budget. They live in `market-loaders.js`, which
 * `loadMarket` fetches and installs with `registerLoaders` before the bundle.
 */
export const MARKET = 'market';

/**
 * The administration screens' own copy — SSO, SCIM, the embed allowlist,
 * growth insights, portal operations and the ticket-portal setup dialog. Each
 * of those screens is already its own chunk behind an `import()`; its strings
 * were not, and every signed-in session downloaded them in its `ui` bundle to
 * open none of them. On the same terms as MARKET: fetched beside the screen
 * (`loadAdminCopy` in `src/admin/load-admin-copy.js`), awaited before it
 * mounts, loaders in `admin-loaders.js` rather than here. What the console
 * paints before a screen's chunk lands — the rail, each card's title and its
 * (i) help — stays in `ui`, for the reason `market.title` did.
 */
export const ADMIN = 'admin';

/**
 * Code-split entry points, one per (tier, locale).
 *
 * Written as literal `import()` calls rather than a computed path, because a
 * computed specifier is invisible to the bundler: it would either inline every
 * locale into the main chunk (defeating L10N-13) or emit nothing at all and
 * fail at runtime. One line per bundle is the price of a real chunk per bundle.
 */
const LAZY = {
  [UI]: {
    en: () => import('../../locales/en.json'),
    ar: () => import('../../locales/ar.json'),
    bg: () => import('../../locales/bg.json'),
    zh: () => import('../../locales/zh.json'),
    zht: () => import('../../locales/zht.json'),
    hr: () => import('../../locales/hr.json'),
    cs: () => import('../../locales/cs.json'),
    da: () => import('../../locales/da.json'),
    nl: () => import('../../locales/nl.json'),
    fi: () => import('../../locales/fi.json'),
    fr: () => import('../../locales/fr.json'),
    de: () => import('../../locales/de.json'),
    el: () => import('../../locales/el.json'),
    he: () => import('../../locales/he.json'),
    hi: () => import('../../locales/hi.json'),
    hu: () => import('../../locales/hu.json'),
    id: () => import('../../locales/id.json'),
    it: () => import('../../locales/it.json'),
    ja: () => import('../../locales/ja.json'),
    ko: () => import('../../locales/ko.json'),
    ms: () => import('../../locales/ms.json'),
    no: () => import('../../locales/no.json'),
    fa: () => import('../../locales/fa.json'),
    pl: () => import('../../locales/pl.json'),
    pt: () => import('../../locales/pt.json'),
    ro: () => import('../../locales/ro.json'),
    ru: () => import('../../locales/ru.json'),
    sr: () => import('../../locales/sr.json'),
    sk: () => import('../../locales/sk.json'),
    es: () => import('../../locales/es.json'),
    sv: () => import('../../locales/sv.json'),
    th: () => import('../../locales/th.json'),
    tr: () => import('../../locales/tr.json'),
    uk: () => import('../../locales/uk.json'),
    ur: () => import('../../locales/ur.json'),
    vi: () => import('../../locales/vi.json'),
  },
  [PROSE]: {
    en: () => import('../../locales/prose/en.json'),
    ar: () => import('../../locales/prose/ar.json'),
    bg: () => import('../../locales/prose/bg.json'),
    zh: () => import('../../locales/prose/zh.json'),
    zht: () => import('../../locales/prose/zht.json'),
    hr: () => import('../../locales/prose/hr.json'),
    cs: () => import('../../locales/prose/cs.json'),
    da: () => import('../../locales/prose/da.json'),
    nl: () => import('../../locales/prose/nl.json'),
    fi: () => import('../../locales/prose/fi.json'),
    fr: () => import('../../locales/prose/fr.json'),
    de: () => import('../../locales/prose/de.json'),
    el: () => import('../../locales/prose/el.json'),
    he: () => import('../../locales/prose/he.json'),
    hi: () => import('../../locales/prose/hi.json'),
    hu: () => import('../../locales/prose/hu.json'),
    id: () => import('../../locales/prose/id.json'),
    it: () => import('../../locales/prose/it.json'),
    ja: () => import('../../locales/prose/ja.json'),
    ko: () => import('../../locales/prose/ko.json'),
    ms: () => import('../../locales/prose/ms.json'),
    no: () => import('../../locales/prose/no.json'),
    fa: () => import('../../locales/prose/fa.json'),
    pl: () => import('../../locales/prose/pl.json'),
    pt: () => import('../../locales/prose/pt.json'),
    ro: () => import('../../locales/prose/ro.json'),
    ru: () => import('../../locales/prose/ru.json'),
    sr: () => import('../../locales/prose/sr.json'),
    sk: () => import('../../locales/prose/sk.json'),
    es: () => import('../../locales/prose/es.json'),
    sv: () => import('../../locales/prose/sv.json'),
    th: () => import('../../locales/prose/th.json'),
    tr: () => import('../../locales/prose/tr.json'),
    uk: () => import('../../locales/prose/uk.json'),
    ur: () => import('../../locales/prose/ur.json'),
    vi: () => import('../../locales/prose/vi.json'),
  },
  // Loaders live in `market-loaders.js`, fetched by `loadMarket` — see MARKET.
  [MARKET]: {},
  // Loaders live in `admin-loaders.js`, fetched by `loadAdminCopy` — see ADMIN.
  [ADMIN]: {},
};

/** tier -> locale -> bundle. Empty until a load lands or a caller registers one. */
const cache = {
  [UI]: new Map(),
  [PROSE]: new Map(),
  [MARKET]: new Map(),
  [ADMIN]: new Map(),
};

/**
 * The pre-hydration floor: what `t()` can answer before ANY bundle exists.
 *
 * Deliberately a second map rather than a seeded `cache`. See the header — a
 * seeded cache would make `loadBundle` answer "already have it" and the real
 * English catalogue would never be fetched, which is the failure this whole
 * change would otherwise introduce and which nothing in English would reveal.
 */
const FLOOR = {
  [UI]: new Map([[SOURCE_LOCALE, enBootUi]]),
  [PROSE]: new Map(),
  [MARKET]: new Map(),
  [ADMIN]: new Map(),
};

/** In-flight loads, so N callers during one paint produce ONE fetch. */
const inFlight = { [UI]: new Map(), [PROSE]: new Map(), [MARKET]: new Map(), [ADMIN]: new Map() };

/** (tier, locale) pairs we do not ship a loader for. Permanent — see L10N-17. */
const unavailable = new Set();

/**
 * How many times a THROWING loader is retried before it joins `unavailable`.
 *
 * Bounded rather than unlimited: a locale whose JSON is genuinely malformed
 * would otherwise re-parse on every `t()`-driven paint for the life of the tab.
 * Three is enough to ride out a chunk rotation or a dropped request, and small
 * enough that a real breakage settles into the English fallback quickly.
 */
const LOAD_ATTEMPTS = 3;

/** (tier, locale) -> failed attempts so far. Cleared on success. */
const attempts = new Map();

/** Subscribers notified after a bundle lands and is readable (L10N-12). */
const listeners = new Set();

function normalizeCode(locale) {
  const entry = localeByCode(locale);
  return entry ? entry.code : null;
}

/**
 * A JSON module's payload, whichever interop produced it.
 *
 * Vite gives `{ default }`; Babel's CommonJS interop gives the keys spread onto
 * the namespace AND a `default`. Reading `default` first is correct under both,
 * and the `||` is what keeps a hand-registered plain object working.
 */
function payload(mod) {
  return (mod && typeof mod === 'object' && mod.default) ? mod.default : mod;
}

/**
 * The bundle if it is already in memory, else the floor, else `undefined`.
 * **Synchronous.** This is what `t()` reads; it must never wait and never fetch.
 *
 * The floor is consulted LAST, so it answers only in the window before the real
 * catalogue lands and never shadows it afterwards.
 */
export function getBundle(tier, locale) {
  const code = normalizeCode(locale);
  const tierCache = cache[tier];
  if (!code || !tierCache) return undefined;
  const loaded = tierCache.get(code);
  if (loaded) return loaded;
  return FLOOR[tier] ? FLOOR[tier].get(code) : undefined;
}

/**
 * Is the REAL bundle in memory, as opposed to the floor standing in for it?
 *
 * `getBundle` cannot answer this — it is the function whose whole job is to
 * blur the difference for readers of a string. The distinction matters to
 * exactly one caller: `ensureBundle` in `src/language.js` skips the fetch when
 * the bundle is already here, and asking `getBundle` there would make it skip
 * the fetch for the source locale forever, leaving every English visitor on
 * five keys and humanized key paths. That is a page of plausible-looking
 * English, which is the reason this predicate is exported rather than inlined.
 */
export function isBundleResident(tier, locale) {
  const code = normalizeCode(locale);
  return Boolean(code && cache[tier] && cache[tier].has(code));
}

/** Do we ship a bundle for this pair at all — loaded, loadable, or neither? */
export function hasBundleFor(tier, locale) {
  const code = normalizeCode(locale);
  if (!code || !cache[tier]) return false;
  return cache[tier].has(code) || Boolean(LAZY[tier] && LAZY[tier][code]);
}

/**
 * Install a lazy tier's loaders from a module that is itself fetched on demand.
 * Must run before the first `loadBundle` for that tier: a locale with no loader
 * is remembered as permanently unavailable.
 */
export function registerLoaders(tier, loaders) {
  if (!LAZY[tier] || !loaders || typeof loaders !== 'object') return;
  Object.assign(LAZY[tier], loaders);
}

/**
 * Install a bundle directly.
 *
 * The seam that makes late-arrival behaviour testable without a network, and
 * the hook a host page uses to inline the active locale into the initial
 * response. Notifies listeners exactly as a fetched bundle does, so nothing
 * downstream can tell the difference — which is the point of testing through it.
 */
export function registerBundle(tier, locale, bundle) {
  const code = normalizeCode(locale);
  if (!code || !cache[tier] || !bundle || typeof bundle !== 'object') return false;
  cache[tier].set(code, bundle);
  unavailable.delete(`${tier}:${code}`);
  attempts.delete(`${tier}:${code}`);
  notify(tier, code);
  return true;
}

function notify(tier, locale) {
  for (const fn of [...listeners]) {
    // One bad subscriber must not stop the others, and must not turn a
    // successful load into a rejected promise upstream.
    //
    // The diagnostics in this file are deliberately token-shaped rather than
    // sentences: they are machine output, they can never carry a translation
    // key, and `scripts/i18n-hardcoded.mjs` correctly reports any English
    // sentence in `src/` that has no key. A log line is not copy.
    try { fn({ tier, locale }); } catch (err) { console.warn('[i18n] listener-failed', err); }
  }
}

/**
 * Subscribe to bundle arrivals. Returns the unsubscribe function.
 *
 * This is L10N-12's whole mechanism: a view that rendered before its bundle
 * existed is not left showing source-locale text, it is repainted here.
 */
export function onBundleLoaded(fn) {
  if (typeof fn !== 'function') return () => {};
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/**
 * Fetch a bundle, or answer `null` (L10N-17).
 *
 * Resolves — never rejects. A locale with no loader, a network failure and a
 * malformed file are all the same answer to a caller: you do not have this, use
 * the source locale. Making that a rejection would put a `.catch()` at every
 * call site, and the one that forgot it would take the page down over a missing
 * translation file.
 *
 * They are the same answer to a CALLER, and a different answer to this module:
 * a thrown loader is retried up to `LOAD_ATTEMPTS` times across the session
 * before it is treated as unavailable. See the header.
 */
export function loadBundle(tier, locale) {
  const code = normalizeCode(locale);
  if (!code || !cache[tier]) return Promise.resolve(null);

  const cached = cache[tier].get(code);
  if (cached) return Promise.resolve(cached);

  const id = `${tier}:${code}`;
  if (unavailable.has(id)) return Promise.resolve(null);

  const pending = inFlight[tier].get(code);
  if (pending) return pending;

  const loader = LAZY[tier] && LAZY[tier][code];
  if (!loader) {
    // Not an error: `LOCALES` may declare a code before anybody has authored a
    // bundle for it, and the product is required to stay usable meanwhile. Both
    // tiers are complete in all 36 today, so this arm is reached only by a
    // locale added to the registry ahead of its copy.
    unavailable.add(id);
    return Promise.resolve(null);
  }

  const promise = Promise.resolve()
    .then(loader)
    .then((mod) => {
      const bundle = payload(mod);
      if (!bundle || typeof bundle !== 'object') throw new Error('malformed-bundle');
      cache[tier].set(code, bundle);
      attempts.delete(id);
      notify(tier, code);
      return bundle;
    })
    .catch((err) => {
      // Logged, not shown. A viewer gets English; whoever runs the deployment
      // gets the reason in the console.
      const spent = (attempts.get(id) || 0) + 1;
      attempts.set(id, spent);
      if (spent >= LOAD_ATTEMPTS) unavailable.add(id);
      console.warn(`[i18n] bundle-load-failed ${tier}/${code} (${spent}/${LOAD_ATTEMPTS})`, err);
      return null;
    })
    .finally(() => inFlight[tier].delete(code));

  inFlight[tier].set(code, promise);
  return promise;
}

/** Which (tier, locale) pairs are in memory right now. For diagnostics/tests. */
export function loadedBundles() {
  return Object.fromEntries(
    Object.keys(cache).map((tier) => [tier, [...cache[tier].keys()].sort()]),
  );
}
