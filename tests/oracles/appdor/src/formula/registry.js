/**
 * Function registry with case- and underscore-insensitive name resolution and
 * an alias registry (REQ-FORMULAENGINE-02).
 *
 *   `is_blank` ≡ `is__blank` ≡ `ISBLANK`   (underscore- and case-insensitive)
 *   `EncodeUrl` ≡ `UrlEncode` ≡ `URLENCODE` (alias registry)
 *
 * Every registered function declares a canonical name; docs and error messages
 * always show that canonical name. Each entry also carries volatility metadata
 * (REQ-FORMULAENGINE-15): `volatile` recomputes on every render (NOW, TODAY);
 * `generateOnce` computes on first evaluation and is expected to persist
 * (UUID, RANDOM, GENERATEPASSWORD).
 *
 * Dependency-free.
 */

/** Normalise a function name for lookup: uppercase, underscores removed. */
export function normalizeName(name) {
  return String(name).toUpperCase().replace(/_/g, '');
}

/**
 * A registered function.
 * @typedef {Object} FnEntry
 * @property {string} name canonical name (upper-case)
 * @property {string[]} [aliases]
 * @property {string} category
 * @property {boolean} [lazy] receives AST arg nodes + evaluator instead of values
 * @property {boolean} [volatile] recompute on each render (NOW/TODAY)
 * @property {boolean} [generateOnce] compute once then persist (UUID/RANDOM)
 * @property {number} [minArgs]
 * @property {number} [maxArgs]  (-1 or omitted = unbounded)
 * @property {Function} fn implementation
 */

export class Registry {
  constructor() {
    this.byName = new Map();
    this.entries = [];
  }

  /** Register one entry under its canonical name and all aliases. */
  register(entry) {
    if (!entry || !entry.name || typeof entry.fn !== 'function') {
      throw new Error('Invalid function entry');
    }
    entry.name = entry.name.toUpperCase();
    const names = [entry.name, ...(entry.aliases || [])];
    for (const n of names) {
      const key = normalizeName(n);
      if (this.byName.has(key) && this.byName.get(key) !== entry) {
        throw new Error(
          `Function name collision: "${n}" already maps to ${this.byName.get(key).name}`
        );
      }
      this.byName.set(key, entry);
    }
    this.entries.push(entry);
    return this;
  }

  /** Register a map of { CANONICAL: entry } or an array of entries. */
  registerAll(defs) {
    if (Array.isArray(defs)) {
      defs.forEach((e) => this.register(e));
    } else {
      for (const [name, e] of Object.entries(defs)) {
        this.register({ name, ...e });
      }
    }
    return this;
  }

  /** Resolve a (possibly aliased/mixed-case) name to its entry, or null. */
  resolve(name) {
    return this.byName.get(normalizeName(name)) || null;
  }

  has(name) {
    return this.byName.has(normalizeName(name));
  }

  /** All canonical entries (deduplicated), for docs / function reference. */
  list() {
    return [...this.entries];
  }
}

/**
 * Validate an argument count against an entry's min/max, returning a
 * FormulaError builder result via the provided error factory, or null if ok.
 */
export function checkArity(entry, count) {
  const min = entry.minArgs ?? 0;
  const max = entry.maxArgs ?? Infinity;
  if (count < min) {
    return `${entry.name} expects at least ${min} argument(s), got ${count}`;
  }
  if (max !== -1 && count > max) {
    return `${entry.name} expects at most ${max === Infinity ? '∞' : max} argument(s), got ${count}`;
  }
  return null;
}
