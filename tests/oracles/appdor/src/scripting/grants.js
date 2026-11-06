/**
 * Capability-grant matching (LC38 / scripting-extensibility).
 *
 * A leaf of the scripting governance model: decides whether a capability+target
 * is permitted by a set of approved grants. Split out of `index.js` so the
 * sandboxed runtime can import it without closing an import cycle back through
 * the scripting barrel.
 */

/**
 * The grant shape both functions read. It is the same `ScriptGrant` the
 * governance barrel documents, restated here rather than imported from
 * `index.js` because this leaf exists precisely so that `runtime.js` can reach
 * it WITHOUT closing an import cycle back through the barrel — and a JSDoc
 * `import('./index.js')` would reopen exactly that cycle for the type checker.
 *
 * @typedef {Object} ApprovedGrant
 * @property {string} [capability] one of the scripting CAPABILITIES
 * @property {string} [target] `*`, an exact target, a `*.host` suffix, or a
 *   base URL that permits any path beneath it
 */

/**
 * Does one grant's target cover the target being asked for?
 *
 * @param {string|null|undefined} grantTarget
 * @param {string|null|undefined} target
 * @returns {boolean}
 */
function targetMatches(grantTarget, target) {
  if (grantTarget == null || grantTarget === '*') return true;
  if (target == null) return false;
  if (grantTarget === target) return true;
  // Host-suffix match for http grants (e.g. "*.example.com").
  if (grantTarget.startsWith('*.')) {
    try {
      const host = new URL(target).hostname;
      return host === grantTarget.slice(2) || host.endsWith(grantTarget.slice(1));
    } catch {
      return false;
    }
  }
  // A base-URL grant permits any path under it, on a path-segment boundary and
  // for the same origin. A raw string prefix also admitted
  // `https://api.example.com.evil.net/x` and `https://api.example.com@evil.net`.
  if (typeof target === 'string' && isHttpUrl(grantTarget)) return urlWithin(grantTarget, target);
  // Anything else (a table or field name) is an exact match or a wildcard.
  return false;
}

const isHttpUrl = (value) => typeof value === 'string' && /^https?:\/\//i.test(value);

function urlWithin(base, candidate) {
  let b;
  let c;
  try {
    b = new URL(base);
    c = new URL(candidate);
  } catch {
    return false;
  }
  if (c.username || c.password) return false;
  if (b.origin !== c.origin) return false;
  const basePath = b.pathname.replace(/\/+$/, '');
  return c.pathname === b.pathname || c.pathname === basePath || c.pathname.startsWith(`${basePath}/`);
}

/**
 * Is a capability+target permitted by a set of approved grants?
 *
 * @param {ApprovedGrant[]} approvedGrants
 * @param {string} capability
 * @param {string|null} [target]
 * @returns {boolean}
 */
export function capabilityAllowed(approvedGrants, capability, target) {
  return (approvedGrants || []).some((g) => g.capability === capability && targetMatches(g.target, target));
}
