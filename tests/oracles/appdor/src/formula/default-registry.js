/**
 * The shared function registry — built once, owned by a leaf.
 *
 * This lived in `index.js`, which is also the package's public façade, so the
 * moment a second module inside `src/formula/` needed the registry the graph
 * closed on itself: `index.js` re-exports `validate.js`, and `validate.js`
 * needed `getRegistry` from `index.js`. ES modules do not fail loudly on that —
 * one participant simply sees a half-initialised namespace — and
 * `tests/import-cycles.test.js` exists because the symptom is a feature that
 * silently does nothing rather than a crash.
 *
 * So the registry moved down here instead: this module imports the `Registry`
 * class and the category modules and nothing that imports it. `index.js`
 * re-exports `buildRegistry`/`getRegistry` unchanged, so every existing import
 * site keeps working.
 */

import array from './array.js';
import convertion from './convertion.js';
import datetime from './datetime.js';
import { isError, valueError } from './errors.js';
import extraction from './extraction.js';
import finance from './finance.js';
import information from './information.js';
// Category modules (each default-exports an array/map of FnEntry).
import logical from './logical.js';
import lookup from './lookup.js';
import math from './math.js';
import randomHashEncode from './random-hash-encode.js';
import reference from './reference.js';
import { Registry } from './registry.js';
import text from './text.js';

/** Copy a scope's own enumerable props into a fresh object. */
function childScope(scope) {
  const s = {};
  if (scope) for (const k of Object.keys(scope)) s[k] = scope[k];
  return s;
}

function varNameOf(node) {
  if (!node) return null;
  if (node.type === 'name') return node.name;
  if (node.type === 'field') return node.name;
  if (node.type === 'string') return node.value;
  return null;
}

/**
 * Core language forms: `let`/`lets` named intermediate variables
 * (REQ-FORMULAENGINE-04). These are lazy — the body is evaluated under an
 * extended scope.
 */
function registerCoreForms(registry) {
  registry.register({
    name: 'LET',
    category: 'core',
    lazy: true,
    minArgs: 3,
    maxArgs: 3,
    fn: (argNodes, ctx, ev, scope) => {
      const varName = varNameOf(argNodes[0]);
      if (!varName) return valueError('LET expects a variable name as its first argument');
      const val = ev.eval(argNodes[1], scope);
      if (isError(val)) return val;
      const inner = childScope(scope);
      inner[varName] = val;
      return ev.eval(argNodes[2], inner);
    },
  });

  registry.register({
    name: 'LETS',
    category: 'core',
    lazy: true,
    minArgs: 3,
    fn: (argNodes, ctx, ev, scope) => {
      if (argNodes.length % 2 === 0) {
        return valueError('LETS expects name/value pairs followed by a body expression');
      }
      let cur = childScope(scope);
      for (let i = 0; i < argNodes.length - 1; i += 2) {
        const varName = varNameOf(argNodes[i]);
        if (!varName) return valueError('LETS variable names must be identifiers');
        const val = ev.eval(argNodes[i + 1], cur);
        if (isError(val)) return val;
        cur = childScope(cur);
        cur[varName] = val;
      }
      return ev.eval(argNodes[argNodes.length - 1], cur);
    },
  });
}

/** Build a fresh registry with every category registered. */
export function buildRegistry() {
  const r = new Registry();
  registerCoreForms(r);
  r.registerAll(logical);
  r.registerAll(information);
  r.registerAll(math);
  r.registerAll(text);
  r.registerAll(datetime);
  r.registerAll(convertion);
  r.registerAll(randomHashEncode);
  r.registerAll(array);
  r.registerAll(lookup);
  r.registerAll(reference);
  r.registerAll(extraction);
  r.registerAll(finance);
  return r;
}

let defaultRegistry = null;

/** The shared default registry (built once). */
export function getRegistry() {
  if (!defaultRegistry) defaultRegistry = buildRegistry();
  return defaultRegistry;
}
