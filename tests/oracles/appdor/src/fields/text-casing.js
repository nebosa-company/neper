/**
 * The Text field's casing option — the eleven spellings its spec lists.
 *
 * Every mode is the same two steps: cut the value into words, then join them
 * back a particular way. Writing them as one segmentation plus eleven joins is
 * what keeps `camelCase` and `PascalCase` from disagreeing about where a word
 * starts, which is the usual way these drift: one splits on the acronym and the
 * other does not, and `parseHTTPResponse` comes out two different shapes.
 *
 * Pure, and deliberately unaware of the field: `applyCasing` takes a string and
 * a mode. The column decides when to call it (on write, not on render — a
 * casing that only exists on screen is a lie the export does not tell).
 */

/** The modes, in the order the settings dropdown offers them. */
export const CASING_MODES = [
  'none',
  'lower',
  'upper',
  'camel',
  'dot',
  'kebab',
  'pascal',
  'screaming-snake',
  'sentence',
  'snake',
  'word',
];

/** Human labels, for the dropdown. */
export const CASING_LABELS = {
  none: 'None',
  lower: 'all lower',
  upper: 'ALL UPPER',
  camel: 'camelCase',
  dot: 'dot.case',
  kebab: 'kebab-case',
  pascal: 'PascalCase',
  'screaming-snake': 'SCREAMING_SNAKE',
  sentence: 'Sentence case',
  snake: 'snake_case',
  word: 'Word Case',
};

/**
 * Cut a string into words.
 *
 * Three boundaries, and the third is the one that is usually missed:
 *   1. anything that is not a letter or a digit  — `a-b`, `a_b`, `a.b`, `a b`
 *   2. lower-to-upper                            — `fooBar`
 *   3. acronym-to-word                           — `HTTPResponse` is HTTP + Response,
 *      not HTTPR + esponse. Without it every acronym loses its last letter.
 *
 * Digits stay attached to the word they follow (`utf8` is one word, not two):
 * splitting them out turns `sha256` into `sha 256` and then `Sha 256`, which is
 * not what anyone means by title-casing a column of hash names.
 */
export function words(value) {
  const text = value === null || value === undefined ? '' : String(value);
  if (!text) return [];
  return text
    .replace(/([\p{Ll}\p{N}])(\p{Lu})/gu, '$1 $2')      // fooBar   -> foo|Bar
    .replace(/(\p{Lu}+)(\p{Lu}\p{Ll})/gu, '$1 $2')      // HTTPResp -> HTTP|Resp
    .split(/[^\p{L}\p{N}]+| /u)
    .filter(Boolean);
}

const lower = (w) => w.toLocaleLowerCase();
const upperFirst = (w) => w.charAt(0).toLocaleUpperCase() + w.slice(1).toLocaleLowerCase();

const JOINERS = {
  lower: (parts) => parts.map(lower).join(' '),
  upper: (parts) => parts.map((w) => w.toLocaleUpperCase()).join(' '),
  camel: (parts) => parts.map((w, i) => (i === 0 ? lower(w) : upperFirst(w))).join(''),
  pascal: (parts) => parts.map(upperFirst).join(''),
  dot: (parts) => parts.map(lower).join('.'),
  kebab: (parts) => parts.map(lower).join('-'),
  snake: (parts) => parts.map(lower).join('_'),
  'screaming-snake': (parts) => parts.map((w) => w.toLocaleUpperCase()).join('_'),
  word: (parts) => parts.map(upperFirst).join(' '),
  // Sentence case capitalises the FIRST word only — and rejoins with spaces, so
  // `user_first_name` becomes "User first name" rather than staying underscored.
  sentence: (parts) => parts.map((w, i) => (i === 0 ? upperFirst(w) : lower(w))).join(' '),
};

/**
 * Recase `value`.
 *
 * `none` — and any mode this does not know — returns the value untouched. That
 * matters more than it looks: an unknown mode arriving from a column configured
 * by a newer build must not silently rewrite the person's data into a shape
 * neither build intended.
 *
 * @param {string|null|undefined} value
 * @param {string} [mode='none']
 * @returns {string} the recased value; '' only when the input was empty
 */
export function applyCasing(value, mode = 'none') {
  if (value === null || value === undefined) return '';
  const text = String(value);
  const join = JOINERS[mode];
  if (!join) return text;
  const parts = words(text);
  // A value with no letters or digits at all (`---`, `   `) has no words to
  // recase. Returning the original keeps a separator-only cell as it was rather
  // than emptying it.
  if (!parts.length) return text;
  return join(parts);
}

/**
 * Truncate to `maxCharacters`, counting the way a person counts.
 *
 * `String.length` counts UTF-16 code units, so it cuts an emoji or an
 * astral-plane character in half and leaves an unpaired surrogate — a string
 * that renders as a replacement glyph and no longer round-trips through JSON.
 * The spread counts code points instead.
 *
 * `0` means no limit, which is what the spec's `[ 0 ]` default is for.
 *
 * @param {string|null|undefined} value
 * @param {number} maxCharacters
 * @returns {string}
 */
export function truncateToMax(value, maxCharacters) {
  if (value === null || value === undefined) return '';
  const text = String(value);
  const limit = Math.trunc(Number(maxCharacters) || 0);
  if (limit <= 0) return text;
  const points = [...text];
  return points.length <= limit ? text : points.slice(0, limit).join('');
}

/**
 * Everything the Text column does to a value on the way in, in one call.
 *
 * Casing first, then the length limit: recasing can change the length
 * (`kebab-case` of "Hello World" is shorter, `SCREAMING_SNAKE` is not), and a
 * limit applied first would be re-broken by the casing that followed it.
 *
 * @param {string|null|undefined} value
 * @param {{casing?: string, maxCharacters?: number}} [config]
 * @returns {string}
 */
export function normalizeTextValue(value, config = {}) {
  return truncateToMax(applyCasing(value, config.casing || 'none'), config.maxCharacters || 0);
}
