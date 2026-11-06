/**
 * Secrets integration for the scripting runtime (LC38).
 *
 * Named secrets resolved at runtime through the host, with automatic redaction
 * so a secret value never appears in persisted logs, run records, or exports.
 *
 * Pure — the host supplies the secret resolver; this module owns the redaction.
 */

const REDACTED = '***REDACTED***';

/**
 * Resolve a named secret through the host callback.
 *
 * @param {string} name the secret name
 * @param {Object<string, string>|Function} secretSource either a map or a
 *   resolver function `(name) => string|null`
 * @returns {string|null} the secret value, or null if not found
 */
export function resolveSecret(name, secretSource) {
  if (!name) return null;
  if (typeof secretSource === 'function') {
    return secretSource(name);
  }
  if (secretSource && typeof secretSource === 'object') {
    return secretSource[name] ?? null;
  }
  return null;
}

/**
 * Wrap a secret value for use in scripts. The wrapped value behaves like a
 * string in formula expressions but carries a redaction sentinel.
 *
 * Script expressions can use it (e.g. in HTTP calls), but the runtime's log
 * redaction replaces it with a marker.
 */
class RedactableSecret {
  constructor(value, name) {
    this._value = value;
    this._name = name;
    this._isSecret = true;
  }

  valueOf() { return this._value; }
  toString() { return String(this._value); }
  toJSON() { return REDACTED; }
}

/**
 * Resolve and wrap a secret as a redactable value. The runtime uses this before
 * injecting secrets into the script scope.
 *
 * @param {string} name
 * @param {Object|Function} secretSource
 * @returns {RedactableSecret|null}
 */
export function prepareSecret(name, secretSource) {
  const value = resolveSecret(name, secretSource);
  if (value === null || value === undefined) return null;
  return new RedactableSecret(value, name);
}

/**
 * Scan a log entry for secret values and redact them. This is called before
 * persisting logs or run records.
 *
 * @param {*[]} log the raw log array from the runtime
 * @param {Object<string, string>} secrets map of name → value, used to find and
 *   replace occurrences
 * @returns {*[]} a deep copy of log with secrets redacted
 */
export function redactLog(log, secrets = {}) {
  if (!log || !log.length) return [];
  const secretValues = Object.values(secrets).filter((v) => v && typeof v === 'string');
  if (!secretValues.length) return [...log];

  const redact = (val) => {
    if (val === null || val === undefined) return val;
    if (typeof val === 'string') {
      let redacted = val;
      for (const secret of secretValues) {
        // Redact any occurrence of the secret value, case-sensitive.
        if (secret && secret.length > 0) {
          redacted = redacted.split(secret).join(REDACTED);
        }
      }
      return redacted;
    }
    if (Array.isArray(val)) return val.map(redact);
    if (typeof val === 'object') {
      const out = {};
      for (const [k, v] of Object.entries(val)) {
        out[k] = redact(v);
      }
      return out;
    }
    return val;
  };

  return log.map((entry) => {
    if (typeof entry === 'object' && entry !== null) {
      return redact({ ...entry });
    }
    return redact(entry);
  });
}

/**
 * Deep-redact an arbitrary value: a wrapped secret becomes the marker and any
 * string containing a known secret value has it replaced. For the outputs that
 * `redactLog` does not see — a script's returned value and a dry-run's effect
 * previews — which would otherwise hand the raw value to a toast or a report.
 *
 * @param {*} value
 * @param {Object<string, string>} [secrets] name -> raw value
 * @returns {*} a redacted copy (primitives pass through)
 */
export function redactValue(value, secrets = {}, depth = 0) {
  const secretValues = Object.values(secrets).filter((v) => v && typeof v === 'string');
  if (depth > 20) return REDACTED;
  if (isRedactableSecret(value)) return REDACTED;
  if (typeof value === 'string') {
    let out = value;
    for (const secret of secretValues) out = out.split(secret).join(REDACTED);
    return out;
  }
  if (Array.isArray(value)) return value.map((item) => redactValue(item, secrets, depth + 1));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = redactValue(v, secrets, depth + 1);
    return out;
  }
  return value;
}

/**
 * Check whether a value is a redactable secret (needs redaction in outputs).
 *
 * @param {*} value
 * @returns {boolean}
 */
export function isRedactableSecret(value) {
  return value && typeof value === 'object' && value._isSecret === true;
}

/**
 * Extract the underlying raw value from a redactable secret (for actual use in
 * calls/requests), or return the value unchanged.
 *
 * @param {*} value
 * @returns {*}
 */
export function unwrapSecret(value) {
  if (isRedactableSecret(value)) return value._value;
  return value;
}

export { REDACTED };
