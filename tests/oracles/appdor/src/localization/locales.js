/**
 * The supported-locale registry (§1, L10N-6).
 *
 * One table, read by everything: what the picker lists, which endonym it prints,
 * which direction the document is laid out in, which flag is drawn, and — the
 * part that matters most — which tag an `Intl.*` constructor is actually given.
 *
 * **Why this module exists at all.** The product's codes are short and partly
 * legacy: `zht` for Traditional Chinese, `no` for Norwegian. `zht` is not a
 * BCP-47 language tag. It is worse than an invalid one — it is *well-formed*
 * (2–3 alpha characters is all the grammar requires), so `new Intl.NumberFormat('zht')`
 * does not throw. It resolves to English, and a Traditional Chinese viewer reads
 * English month names with no error raised anywhere in the stack. Measured:
 *
 *     new Intl.DateTimeFormat('zht', {...}).format(d)      -> "August 3, 2026"
 *     new Intl.DateTimeFormat('zh-Hant', {...}).format(d)  -> "2026年8月3日"
 *
 * So: every `Intl.*` call in the product goes through {@link intlTag}, never
 * through the raw code. That is the single rule this file is here to enforce.
 *
 * **Flag naming.** The spec says a product should pick one convention and map it
 * via metadata; the convention here is COUNTRY CODE (ISO 3166-1 alpha-2), always,
 * never the language code. `en` -> `us`, `cs` -> `cz`, `ja` -> `jp`. The two
 * families collide in both directions — `ms` (Malay) draws `my` (Malaysia), while
 * `my` is itself the language code for Burmese — which is exactly why the mapping
 * is data here rather than a rule applied at the call site.
 */

/** English is source and universal fallback. Nothing falls back past it. */
export const SOURCE_LOCALE = 'en';

/**
 * The 36 supported locales.
 *
 * `english` is the sort key and the name used in builder-facing UI; `endonym` is
 * what a picker DISPLAYS to a viewer. They are separate fields because the two
 * jobs disagree — sorting by endonym would reshuffle the list per language, which
 * DLG-6 forbids.
 *
 * Declared in final display order for readability, but nothing depends on that:
 * {@link orderedLocales} computes the order from `english`.
 */
/**
 * @typedef {Object} LocaleRow
 * @property {string} code
 * @property {string} english
 * @property {string} endonym
 * @property {'ltr'|'rtl'} dir
 * @property {string} intl BCP-47 tag for Intl — a column, not a derivation
 * @property {string} flag
 */
export const LOCALES = Object.freeze([
  { code: 'en', english: 'English', endonym: 'English', dir: 'ltr', intl: 'en', flag: 'us' },
  { code: 'ar', english: 'Arabic', endonym: 'العربية', dir: 'rtl', intl: 'ar', flag: 'sa' },
  { code: 'bg', english: 'Bulgarian', endonym: 'Български', dir: 'ltr', intl: 'bg', flag: 'bg' },
  // The two Chinese rows are the reason `intl` is a column and not a derivation.
  { code: 'zh', english: 'Chinese (Simplified)', endonym: '简体中文', dir: 'ltr', intl: 'zh-Hans', flag: 'cn' },
  { code: 'zht', english: 'Chinese (Traditional)', endonym: '繁體中文', dir: 'ltr', intl: 'zh-Hant', flag: 'tw' },
  { code: 'hr', english: 'Croatian', endonym: 'Hrvatski', dir: 'ltr', intl: 'hr', flag: 'hr' },
  { code: 'cs', english: 'Czech', endonym: 'Čeština', dir: 'ltr', intl: 'cs', flag: 'cz' },
  { code: 'da', english: 'Danish', endonym: 'Dansk', dir: 'ltr', intl: 'da', flag: 'dk' },
  { code: 'nl', english: 'Dutch', endonym: 'Nederlands', dir: 'ltr', intl: 'nl', flag: 'nl' },
  { code: 'fi', english: 'Finnish', endonym: 'Suomi', dir: 'ltr', intl: 'fi', flag: 'fi' },
  { code: 'fr', english: 'French', endonym: 'Français', dir: 'ltr', intl: 'fr', flag: 'fr' },
  { code: 'de', english: 'German', endonym: 'Deutsch', dir: 'ltr', intl: 'de', flag: 'de' },
  { code: 'el', english: 'Greek', endonym: 'Ελληνικά', dir: 'ltr', intl: 'el', flag: 'gr' },
  { code: 'he', english: 'Hebrew', endonym: 'עברית', dir: 'rtl', intl: 'he', flag: 'il' },
  { code: 'hi', english: 'Hindi', endonym: 'हिन्दी', dir: 'ltr', intl: 'hi', flag: 'in' },
  { code: 'hu', english: 'Hungarian', endonym: 'Magyar', dir: 'ltr', intl: 'hu', flag: 'hu' },
  // The source spec's table listed this endonym as "Indonesian" — the English
  // name. An Indonesian reader scanning the picker for their own language would
  // not find it written the way they write it.
  { code: 'id', english: 'Indonesian', endonym: 'Bahasa Indonesia', dir: 'ltr', intl: 'id', flag: 'id' },
  { code: 'it', english: 'Italian', endonym: 'Italiano', dir: 'ltr', intl: 'it', flag: 'it' },
  { code: 'ja', english: 'Japanese', endonym: '日本語', dir: 'ltr', intl: 'ja', flag: 'jp' },
  { code: 'ko', english: 'Korean', endonym: '한국어', dir: 'ltr', intl: 'ko', flag: 'kr' },
  { code: 'ms', english: 'Malay', endonym: 'Melayu', dir: 'ltr', intl: 'ms', flag: 'my' },
  // `no` is the macrolanguage and ambiguous between Bokmål and Nynorsk. The
  // endonym above is Bokmål's, so the tag says so too.
  { code: 'no', english: 'Norwegian', endonym: 'Norsk', dir: 'ltr', intl: 'nb', flag: 'no' },
  { code: 'fa', english: 'Persian', endonym: 'فارسی', dir: 'rtl', intl: 'fa', flag: 'ir' },
  { code: 'pl', english: 'Polish', endonym: 'Polski', dir: 'ltr', intl: 'pl', flag: 'pl' },
  { code: 'pt', english: 'Portuguese', endonym: 'Português', dir: 'ltr', intl: 'pt', flag: 'pt' },
  { code: 'ro', english: 'Romanian', endonym: 'Română', dir: 'ltr', intl: 'ro', flag: 'ro' },
  { code: 'ru', english: 'Russian', endonym: 'Русский', dir: 'ltr', intl: 'ru', flag: 'ru' },
  // Bare `sr` is Cyrillic by CLDR default, which matches the endonym. Latin
  // Serbian would need `sr-Latn` and is a different row we do not ship.
  { code: 'sr', english: 'Serbian', endonym: 'Српски', dir: 'ltr', intl: 'sr', flag: 'rs' },
  { code: 'sk', english: 'Slovak', endonym: 'Slovenčina', dir: 'ltr', intl: 'sk', flag: 'sk' },
  { code: 'es', english: 'Spanish', endonym: 'Español', dir: 'ltr', intl: 'es', flag: 'es' },
  { code: 'sv', english: 'Swedish', endonym: 'Svenska', dir: 'ltr', intl: 'sv', flag: 'se' },
  { code: 'th', english: 'Thai', endonym: 'ไทย', dir: 'ltr', intl: 'th', flag: 'th' },
  { code: 'tr', english: 'Turkish', endonym: 'Türkçe', dir: 'ltr', intl: 'tr', flag: 'tr' },
  { code: 'uk', english: 'Ukrainian', endonym: 'Українська', dir: 'ltr', intl: 'uk', flag: 'ua' },
  { code: 'ur', english: 'Urdu', endonym: 'اردو', dir: 'rtl', intl: 'ur', flag: 'pk' },
  { code: 'vi', english: 'Vietnamese', endonym: 'Tiếng Việt', dir: 'ltr', intl: 'vi', flag: 'vn' },
].map((entry) => Object.freeze(entry)));
// `.map(Object.freeze)` — the bare function reference — was how every consumer
// came to see `Readonly<unknown>`: passed as a callback, `Object.freeze`
// resolves to its non-generic overload and the row type is erased. Wrapping it
// keeps `T` and is otherwise the same call. That single character of laziness
// accounted for the type errors in i18n/format.js and i18n/prefs.js too, which
// only ever read this table.

const BY_CODE = new Map(LOCALES.map((l) => [l.code, l]));

/** The source entry, resolved once — every degraded path returns it. */
const SOURCE_ENTRY = BY_CODE.get(SOURCE_LOCALE);

/**
 * Lowercase and canonicalise separators, so `en_US`, `EN-us` and the canonical
 * spelling all agree. Product codes are all lowercase, so a normalized string
 * can be compared to a code directly.
 */
function normalize(tag) {
  return typeof tag === 'string' ? tag.trim().replace(/_/g, '-').toLowerCase() : '';
}

/**
 * Inbound tags that are not our codes but mean one of them.
 *
 * Only entries that are LOAD-BEARING are listed — a tag like `ja-JP` or `ar-EG`
 * needs no row because {@link resolveLocale} already falls back along subtags to
 * `ja` / `ar`. A row earns its place by being one of:
 *
 * - **wrong without it**: every `zh-*` Traditional variant would otherwise strip
 *   down to bare `zh` and be served Simplified — a real reader, silently wrong;
 * - **missing without it**: `nb`/`nn` and the ISO 639 legacy pairs (`iw` for
 *   Hebrew, `in` for Indonesian, `mo` for Romanian, `sh` whose CLDR replacement
 *   is `sr-Latn`) are still emitted by real runtimes and stored in old prefs.
 *
 * The `zh-Hans` family IS redundant with the bare-`zh` fallthrough. It is listed
 * anyway so the Traditional block above cannot be read as a special case and
 * "simplified" is never left as the unstated default of an unlabelled tag.
 *
 * A Map, not an object literal: lookups are keyed by untrusted input, and
 * `ALIASES['constructor']` on a literal is truthy — `resolveLocale('constructor')`
 * would have returned the `Object` function as a locale code.
 */
const ALIASES = new Map([
  ['zh-hant', 'zht'], ['zh-tw', 'zht'], ['zh-hk', 'zht'], ['zh-mo', 'zht'],
  ['zh-hans', 'zh'], ['zh-cn', 'zh'], ['zh-sg', 'zh'],
  ['nb', 'no'], ['nn', 'no'],
  ['iw', 'he'], ['in', 'id'], ['mo', 'ro'], ['sh', 'sr'],
]);

/**
 * The registry entry for one of OUR codes, or `undefined` (L10N-3).
 *
 * Exact — a regional tag like `ja-JP` is not a code and returns `undefined`. That
 * strictness is the point: a picker and a preference validator need to know
 * whether a stored value is a real row. Callers holding a browser tag want
 * {@link resolveLocale} first.
 *
 * Never throws, for any input, including `null` and non-strings. Callers fall
 * back to {@link SOURCE_LOCALE}.
 */
export function localeByCode(code) {
  return BY_CODE.get(normalize(code));
}

/** Is this one of the 36 codes? Exact, same contract as {@link localeByCode}. */
export function isSupported(code) {
  return BY_CODE.has(normalize(code));
}

/** Computed once — the order can never change at runtime. */
const ORDERED = Object.freeze([
  SOURCE_ENTRY,
  // `filter` copies, so the frozen LOCALES is never the thing being sorted.
  ...LOCALES
    .filter((l) => l.code !== SOURCE_LOCALE)
    .sort((a, b) => a.english.localeCompare(b.english, 'en')),
]);

/**
 * Source locale FIRST, then alphabetical by `english` (DLG-6).
 *
 * Sorted on the ENGLISH name and compared with an explicitly pinned `'en'`
 * collator, so the order is identical no matter which language the viewer is in
 * and no matter what the runtime's default locale is. A picker that reshuffled
 * when you switched language would move the row under the cursor mid-click.
 *
 * Returns a fresh array so a caller may sort or splice it without corrupting the
 * registry; the entries themselves are frozen.
 */
export function orderedLocales() {
  return [...ORDERED];
}

/**
 * Resolve any inbound tag — `navigator.language`, an old stored preference, an
 * `Accept-Language` entry — to one of our codes, or `undefined`.
 *
 * Walks the tag from most to least specific, checking aliases before codes at
 * each length, so `zh-Hant-HK` finds Traditional before it can decay to `zh`:
 *
 *     resolveLocale('ja-JP')      -> 'ja'    (region subtag dropped)
 *     resolveLocale('zh-Hant')    -> 'zht'
 *     resolveLocale('zh-TW')      -> 'zht'
 *     resolveLocale('zh-Hant-HK') -> 'zht'
 *     resolveLocale('nb')         -> 'no'
 *     resolveLocale('ar-EG')      -> 'ar'    (no Egyptian row; degrades to ar)
 *     resolveLocale('tlh')        -> undefined
 *
 * `undefined` rather than `'en'` on no match, deliberately: only the caller knows
 * whether an unmatched tag means "use the source locale" or "try the next
 * `Accept-Language` entry", and returning a plausible-looking `'en'` would make
 * the second impossible to write.
 */
export function resolveLocale(tag) {
  const parts = normalize(tag).split('-').filter(Boolean);
  for (let i = parts.length; i > 0; i -= 1) {
    const candidate = parts.slice(0, i).join('-');
    // Alias before code at each length: `zh-tw` must not lose to a later `zh`.
    if (ALIASES.has(candidate)) return ALIASES.get(candidate);
    if (BY_CODE.has(candidate)) return candidate;
  }
  return undefined;
}

/** Shared by the two tolerant helpers: exact code, else alias, else source. */
function entryFor(code) {
  return localeByCode(code) || localeByCode(resolveLocale(code)) || SOURCE_ENTRY;
}

/**
 * A product code -> a real BCP-47 tag. **The only thing an `Intl.*` constructor
 * may ever be handed.**
 *
 * Tolerant on input (accepts codes, aliases and browser tags) and degrades to the
 * source tag rather than throwing, because the alternative — passing the raw code
 * through — is the silent `zht` -> English resolution this module exists to stop.
 * Falling back to English visibly is a bug report; falling back to English while
 * claiming to be Chinese is not.
 */
export function intlTag(code) {
  return entryFor(code).intl;
}

/**
 * Is this locale written right-to-left? Four are: `ar`, `he`, `fa`, `ur`.
 *
 * Tolerant like {@link intlTag} — `ar-EG` is RTL — and unknown input is LTR,
 * since a mirrored layout applied to an LTR language is far more disruptive than
 * the reverse.
 */
export function isRtlLocale(code) {
  return entryFor(code).dir === 'rtl';
}
