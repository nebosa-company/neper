/**
 * Guard for USER-SUPPLIED regular expressions (a field's `pattern`, a formula's
 * REGEXMATCH/REGEXEXTRACT/REGEXREPLACE pattern).
 *
 * V8's matcher backtracks, so `^(a+)+$` against `aaaa...!` is exponential: 28
 * characters pin a thread for half a minute. Neither a try/catch (syntax errors
 * only) nor an input-length cap bounds that. This module refuses the shapes that
 * cause it BEFORE the pattern is compiled:
 *
 *   - a quantified group that itself contains a quantifier: `(a+)+`, `(a*)*`,
 *     `(a+){2,}`, `(.*a){5,}` -- the nested-quantifier family;
 *   - back-references (`\1`, `\k<n>`), which are not regular at all;
 *   - patterns longer than MAX_PATTERN_LENGTH.
 *
 * It is a conservative static check, not a proof: overlapping alternation such as
 * `(a|aa)+` is not caught. It removes the classes people write by accident and
 * the textbook attack; a linear-time engine (RE2) would be the complete answer.
 *
 * Pure and dependency-free, and compiled patterns are memoised per string, so a
 * bulk validation of 100k rows compiles once.
 */

export const MAX_PATTERN_LENGTH = 1000;
const CACHE_LIMIT = 500;

/** Does a `{...}` at `i` form a repeat quantifier? Returns [endIndex, unbounded-or-many]. */
function braceQuantifier(p, i) {
  const m = /^\{(\d+)(?:(,)(\d*))?\}/.exec(p.slice(i, i + 24));
  if (!m) return null;
  const many = m[2] ? (m[3] === '' || Number(m[3]) > 1) : Number(m[1]) > 1;
  return { len: m[0].length, many };
}

/**
 * True when the pattern is free of the shapes this module refuses.
 *
 * A quantified group is refused when its body is ONE quantified thing
 * (`(a+)+`, `(\d*)*`, `((a+))+`), starts with a wildcard run (`(.*a){5,}`), or
 * mixes alternation with an inner quantifier (`(a|a?)+`). A group whose body
 * has a fixed delimiter before its quantified part -- `(?:\.[a-z]+)*`,
 * `(\d+-)*` -- is unambiguous and stays allowed, because rejecting those would
 * refuse the patterns people actually write.
 *
 * @param {string} pattern
 */
export function isSafePattern(pattern) {
  const p = String(pattern);
  if (p.length > MAX_PATTERN_LENGTH) return false;
  const fresh = () => ({ atoms: 0, hasQuant: false, hasAlt: false, wildStart: false });
  /** @type {ReturnType<typeof fresh>[]} */
  const stack = [fresh()];
  const top = () => stack[stack.length - 1];
  let inClass = false;
  for (let i = 0; i < p.length; i += 1) {
    const c = p[i];
    if (c === '\\') {
      const next = p[i + 1];
      // Back-references: \1-\9 and \k<name>.
      if (!inClass && next !== undefined && ((next >= '1' && next <= '9') || next === 'k')) return false;
      if (!inClass) top().atoms += 1;
      i += 1;
      continue;
    }
    if (inClass) {
      if (c === ']') inClass = false;
      continue;
    }
    if (c === '[') { inClass = true; top().atoms += 1; continue; }
    if (c === '(') {
      stack.push(fresh());
      // Skip the group-type prefix (?: (?= (?! (?<= (?<! (?<name> so its `?` is not a quantifier.
      if (p[i + 1] === '?') {
        const m = /^\?(?::|=|!|<=|<!|<[A-Za-z_]\w*>)/.exec(p.slice(i + 1, i + 40));
        if (m) i += m[0].length;
      }
      continue;
    }
    if (c === '|') { top().hasAlt = true; continue; }
    if (c === ')') {
      if (stack.length === 1) continue; // unbalanced: the compiler will say so
      const g = stack.pop();
      const parent = top();
      const next = p[i + 1];
      let quantified = false;
      let many = false;
      if (next === '*' || next === '+') { quantified = true; many = true; } else if (next === '{') {
        const bq = braceQuantifier(p, i + 1);
        if (bq) { quantified = true; many = bq.many; }
      }
      if (quantified && many && g.hasQuant && (g.atoms === 1 || g.hasAlt || g.wildStart)) return false;
      parent.atoms += 1;
      if (g.hasQuant || (quantified && many)) parent.hasQuant = true;
      if (parent.atoms === 1 && g.wildStart) parent.wildStart = true;
      continue;
    }
    if (c === '*' || c === '+') {
      const t = top();
      t.hasQuant = true;
      if (t.atoms === 1 && p[i - 1] === '.') t.wildStart = true;
      continue;
    }
    if (c === '{') {
      const bq = braceQuantifier(p, i);
      if (bq) {
        if (bq.many) top().hasQuant = true;
        i += bq.len - 1;
        continue;
      }
    }
    if (c === '?') continue; // optional / lazy: not a repeat
    top().atoms += 1;
  }
  return true;
}

const cache = new Map();

/**
 * Compile a user pattern, or explain why not.
 * @param {string} pattern
 * @param {string} [flags]
 * @returns {{ re: RegExp } | { error: 'unsafe' | 'invalid' }}
 */
export function compileSafePattern(pattern, flags = '') {
  const key = `${flags}/${pattern}`;
  const hit = cache.get(key);
  if (hit) {
    // A global/sticky RegExp carries lastIndex; hand out a clean one each time.
    return 're' in hit ? { re: new RegExp(hit.re.source, hit.re.flags) } : hit;
  }
  let result;
  if (!isSafePattern(pattern)) {
    result = { error: 'unsafe' };
  } else {
    try {
      result = { re: new RegExp(pattern, flags) };
    } catch {
      result = { error: 'invalid' };
    }
  }
  if (cache.size >= CACHE_LIMIT) cache.clear();
  cache.set(key, result);
  return 're' in result ? { re: new RegExp(result.re.source, result.re.flags) } : result;
}
