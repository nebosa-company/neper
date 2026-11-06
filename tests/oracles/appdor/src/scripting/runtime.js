/**
 * Sandboxed script runtime (LC38 / scripting-extensibility) — the escape
 * hatch finally runs code.
 *
 * A deterministic interpreter for a small line-oriented script language whose
 * every expression is evaluated by the LC10 formula engine — there is no
 * `eval`, no `Function`, no prototype access, and no ambient authority
 * anywhere in this file. Side effects happen only through `call`, and every
 * call is gated by the existing grants model (capabilityAllowed): a script
 * can touch exactly what its approved grants permit, and a denied call is a
 * structured error naming the capability and target, never a throw.
 *
 * Language:
 *   # comment
 *   let x = <formula expr>          declare (shadowing an input is an error)
 *   set x = <formula expr>          assign to an existing variable
 *   if <expr> … [else …] end        branch (nestable)
 *   foreach item in <expr> … end    iterate a list (capped)
 *   let r = call <capability> <target-expr> [<payload-expr>]
 *   call <capability> <target-expr> [<payload-expr>]
 *   return <expr>
 *
 * Budgets: total step budget (default 10,000) and per-loop iteration cap
 * (default 1,000) — exhaustion halts with a structured error. Determinism:
 * scripts see only their inputs and injected refs; time comes from the host.
 */

import { evaluate, isError } from '../formula/index.js';
import { capabilityAllowed } from './grants.js';
import { prepareSecret, redactLog, redactValue, unwrapSecret } from './secrets.js';

export const DEFAULT_STEP_BUDGET = 10000;
export const DEFAULT_LOOP_CAP = 1000;

// --- parsing --------------------------------------------------------------

// NOTE: identifier validation is inlined into the `let`, `set` and `foreach`
// matchers below rather than hoisted here — the same character class is
// therefore written three times. An extracted `NAME_RE` constant used to sit
// at this line and was never referenced, which the linter caught. Removed
// rather than wired, because interpolating it into three regex literals is a
// change worth making deliberately with the scripting suite in front of you,
// not as a drive-by.

/**
 * Parse source into a block-structured program. Errors carry line numbers.
 */
export function parseScript(source) {
  const lines = String(source || '').split('\n');
  const root = { type: 'block', body: [] };
  const stack = [root];
  const err = (line, message) => ({ ok: false, error: { line: line + 1, message } });

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const top = stack[stack.length - 1];

    let m;
    if ((m = /^let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/.exec(line))) {
      const stmt = { type: 'let', name: m[1], line: i + 1 };
      const call = parseCall(m[2]);
      if (call === false) return err(i, 'malformed call');
      if (call) stmt.call = call;
      else stmt.expr = m[2];
      top.body.push(stmt);
    } else if ((m = /^set\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/.exec(line))) {
      const stmt = { type: 'set', name: m[1], line: i + 1 };
      const call = parseCall(m[2]);
      if (call === false) return err(i, 'malformed call');
      if (call) stmt.call = call;
      else stmt.expr = m[2];
      top.body.push(stmt);
    } else if ((m = /^if\s+(.+)$/.exec(line))) {
      const stmt = { type: 'if', cond: m[1], then: { type: 'block', body: [] }, else: null, line: i + 1 };
      top.body.push(stmt);
      stack.push(stmt.then);
      stmt.then.owner = stmt;
    } else if (line === 'else') {
      const block = stack.pop();
      if (!block || !block.owner || block.owner.type !== 'if' || block.owner.else) return err(i, '"else" without matching "if"');
      block.owner.else = { type: 'block', body: [], owner: block.owner };
      stack.push(block.owner.else);
    } else if ((m = /^foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.+)$/.exec(line))) {
      const stmt = { type: 'foreach', var: m[1], list: m[2], body: { type: 'block', body: [] }, line: i + 1 };
      top.body.push(stmt);
      stmt.body.owner = stmt;
      stack.push(stmt.body);
    } else if (line === 'end') {
      if (stack.length === 1) return err(i, '"end" without an open block');
      stack.pop();
    } else if ((m = /^return\s+(.+)$/.exec(line))) {
      top.body.push({ type: 'return', expr: m[1], line: i + 1 });
    } else if ((m = /^call\s+(.+)$/.exec(line))) {
      const call = parseCall(line);
      if (!call) return err(i, 'malformed call');
      top.body.push({ type: 'call', call, line: i + 1 });
    } else {
      return err(i, `unrecognized statement: "${line.slice(0, 40)}"`);
    }
  }
  if (stack.length !== 1) return { ok: false, error: { line: lines.length, message: 'unclosed block (missing "end")' } };
  return { ok: true, program: root };
}

/** `call <capability> <targetExpr> [<payloadExpr>]` — capability is a bare word. */
function parseCall(text) {
  const m = /^call\s+([a-z][a-z.]*)\s*(.*)$/.exec(text.trim());
  if (!m) return null;
  const rest = m[2].trim();
  if (!rest) return { capability: m[1], target: null, payload: null };
  // Target is the first expression token: a quoted string or a bare token;
  // everything after is the payload expression.
  let target = null;
  let payload = null;
  if (rest.startsWith('"')) {
    const close = rest.indexOf('"', 1);
    if (close === -1) return false;
    target = JSON.stringify(rest.slice(1, close)); // keep as a formula literal
    payload = rest.slice(close + 1).trim() || null;
  } else {
    const sp = rest.indexOf(' ');
    target = sp === -1 ? rest : rest.slice(0, sp);
    payload = sp === -1 ? null : rest.slice(sp + 1).trim() || null;
  }
  return { capability: m[1], target, payload };
}

// --- execution ------------------------------------------------------------

function evalExpr(expr, scope, env) {
  // Flatten one level of object variables so `{deal.Amount}` resolves —
  // formula field refs are flat names, not paths.
  const fields = { ...scope };
  for (const [k, v] of Object.entries(scope)) {
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      for (const [sub, sv] of Object.entries(v)) fields[`${k}.${sub}`] = sv;
    }
  }
  return evaluate(expr, { fields, ...(env.refs || {}) });
}

class Halt {
  constructor(kind, payload) {
    this.kind = kind;
    this.payload = payload;
  }
}

/**
 * Run a script.
 *
 * @param {string|object} sourceOrProgram
 * @param {ScriptOptions} [opts]
 * @returns {Promise<ScriptResult>} { ok, result, log, steps } | { ok: false,
 *   error, log }
 *
 * @typedef {Object} ScriptOptions
 * @property {Object.<string, *>} [inputs] name → value
 * @property {*[]} [grants] approved grants, for capabilityAllowed
 * @property {Object.<string, Function>} [host] capability → (target, payload) => value
 * @property {Object.<string, *>} [refs]
 * @property {number} [stepBudget]
 * @property {number} [loopCap]
 * @property {Object|Function} [secretSource] resolves named secrets
 * @property {string[]} [secretNames] secret names to inject into script scope
 * @property {Object.<string, string>} [secrets] pre-resolved secret name → raw
 *   value; seeds the redaction table so a value the host already holds is
 *   masked in the log without being re-resolved
 *
 * @typedef {Object} ScriptResult
 * @property {boolean} ok
 * @property {*} [result]
 * @property {*[]} [log]
 * @property {number} [steps]
 * @property {{type: string, message?: string, line?: number}} [error]
 * @property {Object<string, string>} [secrets] resolved secrets map for redaction
 */
export async function runScript(sourceOrProgram, opts = {}) {
  let program = sourceOrProgram;
  if (typeof sourceOrProgram === 'string') {
    const parsed = parseScript(sourceOrProgram);
    if (!parsed.ok) return { ok: false, error: { type: 'parse', ...parsed.error }, log: [] };
    program = parsed.program;
  }

  const env = {
    grants: opts.grants || [],
    host: opts.host || {},
    refs: opts.refs || {},
    stepBudget: opts.stepBudget ?? DEFAULT_STEP_BUDGET,
    loopCap: opts.loopCap ?? DEFAULT_LOOP_CAP,
    steps: 0,
    log: [],
    secrets: opts.secrets || {}, // resolved secret name → raw value, for redaction
  };
  const scope = { ...(opts.inputs || {}) };
  const declared = new Set(Object.keys(scope));

  // Inject resolved secrets into scope so scripts can use them. Each is a
  // RedactableSecret — works as a string in expressions, redacted in logs.
  if (opts.secretSource) {
    for (const name of opts.secretNames || []) {
      const secret = prepareSecret(name, opts.secretSource);
      if (secret !== null) {
        scope[name] = secret;
        declared.add(name);
        env.secrets[name] = secret._value;
      }
    }
  }

  try {
    await execBlock(program, scope, declared, env);
    const log = redactLog(env.log, env.secrets);
    return { ok: true, result: scope._result !== undefined ? redactValue(scope._result, env.secrets) : null, log, steps: env.steps };
  } catch (e) {
    const log = redactLog(env.log, env.secrets);
    if (e instanceof Halt) {
      // A returned secret must not reach a toast or a run record as its raw value.
      if (e.kind === 'return') return { ok: true, result: redactValue(e.payload, env.secrets), log, steps: env.steps };
      return { ok: false, error: e.payload, log, steps: env.steps };
    }
    return { ok: false, error: { type: 'internal', message: String(e && e.message ? e.message : e) }, log };
  }
}

function spend(env, line) {
  env.steps += 1;
  if (env.steps > env.stepBudget) {
    throw new Halt('error', { type: 'budget-exhausted', line, message: `step budget ${env.stepBudget} exhausted` });
  }
}

/**
 * Run a nested block with its own declarations: a `let` inside a foreach body
 * or an `if` branch is gone when the block ends, so iteration two can declare
 * it again and a later sibling cannot see it.
 */
async function execScoped(block, scope, declared, env) {
  const before = new Set(declared);
  try {
    await execBlock(block, scope, declared, env);
  } finally {
    for (const name of [...declared]) {
      if (!before.has(name)) {
        declared.delete(name);
        delete scope[name];
      }
    }
  }
}

async function execBlock(block, scope, declared, env) {
  for (const stmt of block.body) {
    spend(env, stmt.line);
    switch (stmt.type) {
      case 'let': {
        if (declared.has(stmt.name)) {
          throw new Halt('error', { type: 'redeclaration', line: stmt.line, message: `"${stmt.name}" is already declared — use set` });
        }
        scope[stmt.name] = stmt.call ? await execCall(stmt.call, scope, env, stmt.line) : evalChecked(stmt.expr, scope, env, stmt.line);
        declared.add(stmt.name);
        break;
      }
      case 'set': {
        if (!declared.has(stmt.name)) {
          throw new Halt('error', { type: 'undeclared', line: stmt.line, message: `"${stmt.name}" is not declared — use let` });
        }
        scope[stmt.name] = stmt.call ? await execCall(stmt.call, scope, env, stmt.line) : evalChecked(stmt.expr, scope, env, stmt.line);
        break;
      }
      case 'if': {
        const cond = evalChecked(stmt.cond, scope, env, stmt.line);
        if (truthy(cond)) await execScoped(stmt.then, scope, declared, env);
        else if (stmt.else) await execScoped(stmt.else, scope, declared, env);
        break;
      }
      case 'foreach': {
        const list = evalChecked(stmt.list, scope, env, stmt.line);
        const arr = Array.isArray(list) ? list : list == null ? [] : [list];
        if (arr.length > env.loopCap) {
          throw new Halt('error', { type: 'loop-cap', line: stmt.line, message: `foreach over ${arr.length} items exceeds cap ${env.loopCap}` });
        }
        const shadow = declared.has(stmt.var);
        const saved = scope[stmt.var];
        declared.add(stmt.var);
        for (const item of arr) {
          scope[stmt.var] = item;
          await execScoped(stmt.body, scope, declared, env);
        }
        if (shadow) scope[stmt.var] = saved;
        else {
          delete scope[stmt.var];
          declared.delete(stmt.var);
        }
        break;
      }
      case 'call': {
        await execCall(stmt.call, scope, env, stmt.line);
        break;
      }
      case 'return': {
        throw new Halt('return', evalChecked(stmt.expr, scope, env, stmt.line));
      }
      default:
        throw new Halt('error', { type: 'unknown-statement', line: stmt.line });
    }
  }
}

function evalChecked(expr, scope, env, line) {
  const v = evalExpr(expr, scope, env);
  if (isError(v)) {
    throw new Halt('error', { type: 'expression-error', line, message: `formula error ${v.error || v} in "${expr}"` });
  }
  return v;
}

/** Every side effect passes the grant gate — the sandbox's only door. */
async function execCall(call, scope, env, line) {
  const target = call.target ? evalChecked(call.target, scope, env, line) : null;
  const payload = call.payload ? evalChecked(call.payload, scope, env, line) : null;

  if (!capabilityAllowed(env.grants, call.capability, target)) {
    throw new Halt('error', {
      type: 'capability-denied',
      line,
      capability: call.capability,
      target,
      message: `script has no grant for ${call.capability}${target ? ` on ${target}` : ''}`,
    });
  }
  const handler = env.host[call.capability];
  if (typeof handler !== 'function') {
    throw new Halt('error', { type: 'capability-unavailable', line, capability: call.capability, message: `no host handler for ${call.capability}` });
  }
  env.log.push({ line, capability: call.capability, target });
  return await handler(unwrapSecret(target), unwrapSecret(payload));
}

function truthy(v) {
  if (v === true) return true;
  if (v === false || v == null || v === '') return false;
  if (typeof v === 'number') return v !== 0;
  if (Array.isArray(v)) return v.length > 0;
  return true;
}
