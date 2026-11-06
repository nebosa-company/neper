/**
 * Flow-IR interpreter — the synchronous half of the workflow engine.
 *
 * Executes a flat flow = one trigger + an ordered graph of steps (condition,
 * branch, loop, find, record CRUD, email/notification/http, set) against a
 * trigger context, producing a step-level run log. Deterministic and pure: all
 * side effects go through an injected `effects` handler map (individually
 * dry-runnable), so the same definition is fully testable without a queue,
 * database, or network.
 *
 * ## Why this still exists beside `runtime.js`
 *
 * `runtime.js` is the DURABLE engine: it replays a journal, survives a restart,
 * and can express waits, approvals and parallel branches — the things this
 * interpreter's header used to say it deliberately refused to fake. That engine
 * is the one every user-authored workflow runs on.
 *
 * This one is what remains useful when a caller needs a graph of steps executed
 * *inline, now, inside a transaction it already holds*: transition
 * post-functions (`workflows/guard.js`). A post-function that set a field by
 * starting a durable run would leave the field unset until a worker picked the
 * run up — the record would be committed to its new state with the assignment
 * still pending. Post-functions need the step budget, the cascade guard and the
 * step-level trace, and need them synchronously, which is exactly this.
 *
 * There is deliberately no `delay` step here for the original reason: durable
 * waits are `runtime.js`'s job, and a step reporting success for a wait that
 * never happened is worse than an `unknown-step` verdict.
 *
 * Metering: one triggered run is one metered unit regardless of step/branch/loop
 * count (REQ-20). Trigger-filtered events create no run and consume no quota.
 */

import { evaluate, isError } from '../formula/index.js';
import { matchesFilter } from '../views/query.js'; import { applyRecordQuery } from './record-query.js';
import { runScript } from '../scripting/runtime.js';
import { BUDGET_EXCEEDED } from './governance.js';
// For the one sentence beside UNKNOWN_STEP — the run-log line a person reads.
import { t } from '../language.js';
// LC47.12 — the `ai` step type. These four are the whole AI step runtime; this
// file supplies the flow (bindings, dry-run switch, trace, branch predicates)
// and injects the model through `effects.aiModel`, so no provider is reachable
// from here. The chain step-execution → registry → types is deliberately
// `t()`-free: this module is loaded by services/workflow-worker in plain Node,
// where importing `language.js` is fatal at boot. See registry.js's header.
import { dryRunAiStep, executeAiStep, buildAiStepTrace, resolveTypedOutput } from '../ai/blocks/step-execution.js';

const DEFAULT_ITERATION_CAP = 1000;
const DEFAULT_CASCADE_DEPTH = 3;
const MAX_RETRIES = 3;

/**
 * How many logged steps one run may execute before the budget stops it.
 *
 * Deliberately generous: this is a runaway guard, not a quota. The quota lives
 * in billing/run-guard.js and counts runs; this counts work inside one run, so
 * a loop of 1,000 iterations over a 5-step body cannot turn a single trigger
 * into 5,000 effects that nobody authorised.
 */
export const DEFAULT_STEP_BUDGET = 10000;

/**
 * The contract LC27's §7 names for a run stopped by a budget:
 * status `terminated`, reason `budget_exceeded`.
 *
 * This used to report `status: 'capped'` with no reason at all. The behaviour
 * was right — an inner cap ended the outer run rather than being swallowed —
 * but something written against the criterion would look for these two strings
 * and find neither, and a contract nobody can match is not a contract. The
 * status is the one an operator sees; `reason` is the machine-readable half,
 * so "stopped by a budget" is distinguishable from "stopped by a condition"
 * without parsing prose.
 */
export const TERMINATED = 'terminated';
export { BUDGET_EXCEEDED } from './governance.js';

/**
 * The machine-readable reason a run stopped on a step type this engine does not
 * implement. Beside the prose for the same reason `BUDGET_EXCEEDED` is: a
 * consumer that has to match an error message to tell "unknown step" from "the
 * step failed" does not have a contract.
 */
export const UNKNOWN_STEP = 'unknown_step';

/**
 * Codes an `ai` step answers with. Codes, not sentences, for the reason
 * registry.js's header gives: this file is imported by the workflow worker,
 * which cannot load the locale bundle. A screen maps these to copy.
 *
 * `NO_AI_MODEL` — the host injected no `effects.aiModel`, so nothing ran. The
 * step is recorded `skipped`, never `success`: a run log that reads green for a
 * model call nobody made is the failure mode this engine's `unknown-step`
 * handling exists to refuse.
 *
 * `AI_STEP_FAILED` — the model was called and the step did not produce a usable
 * typed value (provider error, or output the block's `coerce` rejected).
 */
export const NO_AI_MODEL = 'no_ai_model';
export const AI_STEP_FAILED = 'ai_step_failed';

// --- binding & value resolution ------------------------------------------

function getPath(obj, path) {
  const parts = String(path).split('.');
  let cur = obj;
  for (const p of parts) {
    if (cur == null) return undefined;
    cur = cur[p];
  }
  return cur;
}

/** Fields object a formula/condition sees: trigger + loop item + variables. */
function bindingFields(context) {
  return { ...(context.trigger || {}), ...(context.current || {}), ...(context.vars || {}) };
}

function engineCtx(context, env) {
  return { fields: bindingFields(context), ...(env.refs || {}) };
}

/**
 * Resolve a value spec: { literal } | { binding: 'path' } | { formula: 'expr' }
 * | a raw primitive.
 */
export function resolveValue(spec, context, env) {
  if (spec === null || typeof spec !== 'object' || Array.isArray(spec)) return spec;
  if ('literal' in spec) return spec.literal;
  if ('binding' in spec) return getPath(context, spec.binding);
  if ('formula' in spec) {
    const v = evaluate(spec.formula, engineCtx(context, env));
    return isError(v) ? null : v;
  }
  return spec;
}

function resolveValues(map, context, env) {
  const out = {};
  for (const [k, spec] of Object.entries(map || {})) out[k] = resolveValue(spec, context, env);
  return out;
}

/** Evaluate a condition: string expr, {expr}, {filter}, or a raw filter tree. */
export function evalCondition(cond, context, env) {
  if (cond == null) return true;
  const subject = context.current || context.trigger || {};
  if (typeof cond === 'string') return truthy(evaluate(cond, engineCtx(context, env)));
  if (cond.expr) return truthy(evaluate(cond.expr, engineCtx(context, env)));
  const tree = cond.filter || cond;
  return matchesFilter(tree, subject, env.fields || [], env.refs || {});
}

function truthy(v) {
  if (isError(v)) return false;
  if (v === true) return true;
  if (v === false || v == null || v === '') return false;
  if (typeof v === 'number') return v !== 0;
  if (Array.isArray(v)) return v.length > 0;
  return true;
}

function toList(v) {
  if (Array.isArray(v)) return v;
  if (v == null || v === '') return [];
  return [v];
}

/**
 * Publish an AI step's typed output where the rest of the flow can read it.
 *
 * Three surfaces, because the flow has three ways of asking:
 *
 *   `vars[name]`         — the whole value, for `{ binding: 'vars.triage' }`
 *                          and for `getPath`, which walks dots, so
 *                          `{ binding: 'vars.triage.priority' }` also works.
 *   `vars['name.key']`   — each key of a structured output, flattened, because
 *                          a branch predicate is a FORMULA and the formula
 *                          evaluator resolves `{triage.priority}` against a flat
 *                          `fields` map (bindingFields). Without this the parsed
 *                          object is reachable from templates and invisible to
 *                          the if/else that was the point of parsing it.
 *   `steps[stepId]`      — the step-keyed convention `find`/`create`/`script`
 *                          already use.
 *
 * The flattening is one level deep on purpose. Deeper nesting is reachable
 * through `binding`, and a recursive flatten would let a model-authored key
 * collide with a variable a person named.
 */
function bindTypedOutput(vars, name, typed) {
  vars[name] = typed;
  if (typed && typeof typed === 'object' && !Array.isArray(typed)) {
    for (const [k, v] of Object.entries(typed)) vars[`${name}.${k}`] = v;
  }
}

// --- step execution ------------------------------------------------------

function logStep(run, entry) {
  run.steps.push(entry);
  return entry;
}

/**
 * Stop the run on a budget, recording WHICH budget and where.
 *
 * The trace is deliberately left intact up to this point rather than truncated:
 * the steps that did run are the only evidence of what the partial run already
 * did to the world, and an operator asked to clean up after a terminated run
 * needs exactly that list.
 *
 * `budget` carries the attribution LC33 meters on — the rule is the run's own
 * `flowId`, and the tenant is stamped by the host, which is the only layer that
 * knows it.
 */
function terminate(run, detail) {
  run.reason = BUDGET_EXCEEDED;
  run.budget = { reason: BUDGET_EXCEEDED, ...detail };
  return { status: TERMINATED, reason: BUDGET_EXCEEDED };
}

/**
 * Run `fn`, retrying transient failures.
 *
 * An error carrying `permanent === true` stops immediately. Retrying a verdict
 * is not the same as retrying a request: an SSRF refusal ("ai-proxy is an
 * internal hostname") was attempted three times, and the hostname was not going
 * to become public between attempts. Observed on a real run — three attempts,
 * three DNS resolutions, one inevitable answer.
 *
 * It also misreports. `attempts: 3` in the run log says the worker tried hard
 * and the network was flaky; the truth was that the URL is not allowed, which
 * is a thing the customer must fix rather than wait out.
 *
 * The `http` effect already made this distinction for status codes — only 5xx
 * throws, 4xx returns — so this closes the same gap for the guard.
 */
async function withRetries(fn, retries) {
  let lastErr;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return { ok: true, value: await fn(attempt), attempts: attempt };
    } catch (e) {
      lastErr = e;
      if (e && e.permanent) return { ok: false, error: e, attempts: attempt };
    }
  }
  return { ok: false, error: lastErr, attempts: retries };
}

/**
 * The step loop, at every nesting level.
 *
 * There used to be a second, top-level-only variant of this that took a
 * checkpoint after each node so a worker dying mid-run could resume from the
 * cursor. That was the *legacy* durability story. Durability now belongs to
 * `runtime.js`, which replays a journal and resumes at the exact step rather
 * than at the nearest top-level node — and the only caller left here runs
 * inline inside a transition it already holds, where there is no worker to die
 * and nothing to resume. Two mechanisms for one property is how they come to
 * disagree, so this keeps the one that is still true.
 */
async function execSteps(steps, context, run, env) {
  for (const step of steps || []) {
    // Checked here rather than in logStep so it applies at every nesting level
    // — the criterion is written about a budget exceeded INSIDE a for-each, and
    // a guard that only sees the top level would never see that.
    if (run.steps.length >= env.stepBudget) {
      return terminate(run, { kind: 'step-budget', budget: env.stepBudget, used: run.steps.length, stepId: step.id || null, stepType: step.type || null });
    }
    const control = await execStep(step, context, run, env);
    if (control.status && control.status !== 'continue') return control;
  }
  return { status: 'continue' };
}

async function execStep(step, context, run, env) {
  const entry = { id: step.id, type: step.type, status: 'success' };
  const effects = env.effects;

  try {
    switch (step.type) {
      case 'condition': {
        const ok = evalCondition(step.filter || step.expr || step.condition, context, env);
        entry.output = { matched: ok };
        logStep(run, entry);
        if (!ok && (step.onFalse || 'stop') === 'stop') return { status: 'stopped' };
        return { status: 'continue' };
      }

      case 'branch': {
        for (const branch of step.branches || []) {
          if (evalCondition(branch.filter || branch.expr, context, env)) {
            entry.output = { branch: branch.name || 'matched' };
            logStep(run, entry);
            return execSteps(branch.steps, context, run, env);
          }
        }
        entry.output = { branch: 'default' };
        logStep(run, entry);
        return execSteps(step.default || [], context, run, env);
      }

      case 'loop': {
        const list = toList(resolveValue(step.list, context, env));
        const cap = step.cap || DEFAULT_ITERATION_CAP;
        entry.output = { count: Math.min(list.length, cap) };
        logStep(run, entry);
        for (let i = 0; i < list.length; i++) {
          if (i >= cap) {
            entry.status = TERMINATED;
            return terminate(run, { kind: 'iteration-cap', budget: cap, used: list.length, stepId: step.id || null, stepType: 'loop' });
          }
          const child = { ...context, current: list[i], index: i };
          const res = await execSteps(step.steps, child, run, env);
          if (res.status === 'failed' || res.status === TERMINATED) return res;
        }
        return { status: 'continue' };
      }

      case 'find': {
        const table = step.table;
        const filter = step.filter;
        let records;
        if (effects && typeof effects.findRecords === 'function') {
          records = await effects.findRecords(table, { filter, sort: step.sort, limit: step.limit });
        } else if (env.dataset && env.dataset[table]) {
          // The worker's reader and this fixture path share one meaning of
          // filter/sort/limit (record-query.js): a plain `{"status": "open"}` map
          // used to reach `filterRecords` as an unknown condition and match nothing.
          records = applyRecordQuery(env.dataset[table], { filter, sort: step.sort, limit: typeof step.limit === 'number' ? step.limit : undefined, fields: env.fields || [] });
        } else {
          records = [];
        }
        const output = { records, count: records.length };
        if (step.id) context.steps[step.id] = output;
        entry.output = { count: records.length };
        logStep(run, entry);
        return { status: 'continue' };
      }

      case 'set': {
        const value = resolveValue(step.value, context, env);
        context.vars[step.name] = value;
        entry.output = { [step.name]: value };
        logStep(run, entry);
        return { status: 'continue' };
      }

      case 'create':
      case 'update':
      case 'delete': {
        const values = resolveValues(step.values, context, env);
        const target = step.target ? resolveValue(step.target, context, env) : context.current || context.trigger;
        const handlerName = step.type === 'create' ? 'createRecord' : step.type === 'update' ? 'updateRecord' : 'deleteRecord';
        if (env.dryRun && env.dryRun[step.type]) {
          entry.status = 'dry-run';
          entry.output = { table: step.table, values };
          logStep(run, entry);
          return { status: 'continue' };
        }
        if (!effects || typeof effects[handlerName] !== 'function') {
          entry.status = 'skipped';
          logStep(run, entry);
          return { status: 'continue' };
        }
        const output =
          step.type === 'create'
            ? await effects.createRecord(step.table, values)
            : step.type === 'update'
              ? await effects.updateRecord(step.table, target, values)
              : await effects.deleteRecord(step.table, target);
        if (step.id) context.steps[step.id] = output;
        entry.output = summarizeOutput(output);
        logStep(run, entry);
        return { status: 'continue' };
      }

      case 'email':
      case 'notification':
      case 'http': {
        const payload = resolveValues(step.config || step.payload || {}, context, env);
        const handlerName = step.type === 'notification' ? 'notify' : step.type;
        if (env.dryRun && env.dryRun[step.type]) {
          entry.status = 'dry-run';
          entry.output = redact(payload);
          logStep(run, entry);
          return { status: 'continue' };
        }
        if (!effects || typeof effects[handlerName] !== 'function') {
          entry.status = 'skipped';
          logStep(run, entry);
          return { status: 'continue' };
        }
        const result = await withRetries(() => effects[handlerName](payload), step.retries ?? MAX_RETRIES);
        if (!result.ok) {
          entry.status = 'failed';
          entry.error = String(result.error && result.error.message ? result.error.message : result.error);
          if (result.error && result.error.code) entry.code = result.error.code;
          entry.attempts = result.attempts;
          logStep(run, entry);
          return handleFailure(step, run, context, env);
        }
        if (step.id) context.steps[step.id] = result.value;
        entry.attempts = result.attempts;
        // A handler that ran but delivered nothing (e.g. email with no
        // transport configured) is a no-op, not a success — the distinction
        // is what keeps the run log from green-lighting mail nobody sent.
        if (result.value && result.value.delivered === false) entry.status = 'no-op';
        entry.output = redact(summarizeOutput(result.value));
        logStep(run, entry);
        return { status: 'continue' };
      }

      case 'script': {
        // The escape hatch, executed under the same grants model everything
        // else obeys (LC38): no eval, a step budget, and every side effect
        // gated by an approved capability. A script with no grants can compute
        // and return, and can touch nothing.
        const res = await runScript(step.source, {
          inputs: { ...bindingFields(context), ...resolveValues(step.inputs, context, env) },
          grants: step.grants || [],
          stepBudget: step.stepBudget,
          loopCap: step.loopCap,
          host: {
            'table.read': async (table) => (effects && effects.findRecords ? effects.findRecords(table, {}) : []),
            'table.write': async (table, payload) => (effects && effects.updateRecord ? effects.updateRecord(table, payload && payload.id, payload) : null),
            http: async (url, payload) => (effects && effects.http ? effects.http({ url, payload }) : null),
            notify: async (to, message) => (effects && effects.notify ? effects.notify({ to, message }) : null),
            email: async (to, subject) => (effects && effects.email ? effects.email({ to, subject }) : null),
            'run.workflow': async (id, params) => (effects && effects.runWorkflow ? effects.runWorkflow(id, params, env.depth + 1) : null),
          },
        });
        if (!res.ok) {
          entry.status = 'failed';
          entry.error = `${res.error.type}${res.error.line ? ` (line ${res.error.line})` : ''}: ${res.error.message || ''}`.trim();
          logStep(run, entry);
          return handleFailure(step, run, context, env);
        }
        if (step.id) context.steps[step.id] = res.result;
        if (step.into) context.vars[step.into] = res.result;
        entry.output = { result: summarizeOutput(res.result), calls: res.log.length, steps: res.steps };
        logStep(run, entry);
        return { status: 'continue' };
      }

      /**
       * An AI action (LC47.12).
       *
       * The vocabulary is the block registry's — `step.block` is a registered
       * block key (`custom-prompt`, `categorize`, …), the same definition that
       * backs the AI FIELD of that name, which is the point of the block layer:
       * one registration, two surfaces. `step-bridge.js` already resolves a
       * block into a step-type DESCRIPTOR for a builder's palette; it is a
       * catalogue entry, not a runtime, and nothing here needs it. The runtime
       * is `step-execution.js`, and until this case existed it had no caller.
       *
       *   { id, type: 'ai', block: 'custom-prompt',
       *     config: { prompt, outputType: 'json', outputSchema, model },
       *     sources: { Notes: { binding: 'trigger.Notes' } },   // optional
       *     into: 'triage' }                                    // optional
       *
       * `sources` defaults to the same bindings a formula sees (trigger + loop
       * item + vars) so a prompt can interpolate `{{Field}}` with no wiring;
       * an explicit map overlays it and goes through `resolveValue`, so a
       * source may itself be a literal, a binding or a formula.
       *
       * No provider is reachable from this file. The model arrives as
       * `effects.aiModel`, exactly as `http`/`email`/`notify` do, which is what
       * makes the whole step testable without a network and what makes the
       * dry-run branch below honest rather than merely unexercised.
       */
      case 'ai': {
        const blockKey = step.block || step.blockKey || step.aiBlock;
        const config = { ...(step.config || {}), ...resolveValues(step.configValues, context, env) };
        if (step.model) config.model = step.model;
        // Explicit sources overlay the ambient bindings, never the reverse: a
        // step that names a source means it.
        const sources = { ...bindingFields(context), ...resolveValues(step.sources, context, env) };
        const name = step.into || step.id || blockKey;

        // Dry run: resolve the prompt, pick the model, price it — and stop.
        // `dryRunAiStep` has no model parameter to pass a provider through, so
        // "no provider call" is a property of the code path, not a promise.
        if (env.dryRun && env.dryRun.ai) {
          const preview = dryRunAiStep(blockKey, config, sources, config.model);
          entry.status = 'dry-run';
          // The resolved prompt IS the preview — an author checking their
          // interpolation before spending money has to see it. It still goes
          // through `redact`, so a token that reached the config does not reach
          // the log. This is the one place a full prompt appears; the trace
          // below carries a 100-char prefix and nothing else.
          entry.output = redact({
            blockKey: preview.blockKey,
            model: preview.model,
            prompt: preview.prompt,
            cost: preview.costEstimate,
          });
          if (step.id) context.steps[step.id] = preview;
          logStep(run, entry);
          return { status: 'continue' };
        }

        const modelFn = effects && typeof effects.aiModel === 'function' ? effects.aiModel : null;
        if (!modelFn) {
          entry.status = 'skipped';
          entry.code = NO_AI_MODEL;
          logStep(run, entry);
          return { status: 'continue' };
        }

        const result = await executeAiStep(blockKey, config, sources, modelFn);
        // The trace is metadata only — step identity, model, a redacted prompt
        // prefix, output type, status, correlation, cost class. Neither the
        // full prompt nor the response payload is in it, and `redact` then
        // masks anything sensitively named that a config injected into it.
        entry.output = redact(buildAiStepTrace(result, {
          stepId: step.id,
          outputType: config.outputType,
          correlationId: (context.triggerMeta && context.triggerMeta.correlationId) || undefined,
        }));

        if (!result.ok) {
          entry.status = 'failed';
          entry.code = AI_STEP_FAILED;
          if (result.error) entry.error = String(result.error);
          logStep(run, entry);
          return handleFailure(step, run, context, env);
        }

        // The parsed value, not the raw text: a structured output declared by
        // the block comes back as an object here, and that object is what the
        // downstream branch predicate and templates read.
        const typed = resolveTypedOutput(result);
        if (step.id) context.steps[step.id] = typed;
        bindTypedOutput(context.vars, name, typed);
        logStep(run, entry);
        return { status: 'continue' };
      }

      case 'run-workflow': {
        if (env.depth + 1 > env.maxCascadeDepth) {
          entry.status = 'cascade-exceeded';
          logStep(run, entry);
          return { status: 'cascade-exceeded' };
        }
        if (effects && typeof effects.runWorkflow === 'function') {
          const params = resolveValues(step.params, context, env);
          const child = await effects.runWorkflow(step.workflowId, params, env.depth + 1);
          if (step.id) context.steps[step.id] = child;
          entry.output = { status: child && child.status };
        } else {
          entry.status = 'skipped';
        }
        logStep(run, entry);
        return { status: 'continue' };
      }

      /**
       * A step type this interpreter does not implement.
       *
       * This used to `return { status: 'continue' }`, so the run finished
       * `success` with the offending step recorded `unknown-step` beside it —
       * nothing ran, and the run log said it went fine. A typo (`webhook` for
       * `http`), a step type removed from the catalog, or a definition written
       * against a newer schema than this process all landed there, and all of
       * them read as a completed automation.
       *
       * An unmeasured state must never be readable as a good one, so this ends
       * the run. The verdict on the STEP stays `unknown-step` rather than
       * becoming a generic `failed`, because "we do not know this step type" and
       * "this step tried and failed" are different things for whoever has to fix
       * it — and `reason` is the machine-readable half, so a consumer does not
       * have to regex prose to tell the two apart.
       *
       * It is deliberately NOT routed through `handleFailure`: `onFailure:
       * 'continue'` is an author's decision about steps that can fail, and it
       * would put this straight back to reporting success for a definition this
       * engine cannot execute at all.
       */
      default:
        entry.status = 'unknown-step';
        entry.error = t('workflow.run.error.noHandlerForType', null, { type: step.type });
        logStep(run, entry);
        run.reason = UNKNOWN_STEP;
        return { status: 'failed', reason: UNKNOWN_STEP };
    }
  } catch (e) {
    entry.status = 'failed';
    entry.error = String(e && e.message ? e.message : e);
    // A machine-readable code beside the prose. `permission_denied` is the
    // string LC27's §7 names, and a consumer that has to regex the message to
    // find it does not have a contract.
    if (e && e.code) entry.code = e.code;
    logStep(run, entry);
    return handleFailure(step, run, context, env);
  }
}

function handleFailure(step, run, context, env) {
  const policy = env.onFailure || 'stop';
  if (policy === 'continue') return { status: 'continue' };
  if (Array.isArray(env.errorBranch)) {
    // Run the designated error branch, then fail the run.
    return execSteps(env.errorBranch, context, run, env).then(() => ({ status: 'failed' }));
  }
  return { status: 'failed' };
}

const SENSITIVE = /(authorization|token|secret|password|api[_-]?key|bearer)/i;

function redact(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  const out = Array.isArray(obj) ? [] : {};
  for (const [k, v] of Object.entries(obj)) {
    out[k] = SENSITIVE.test(k) ? '***redacted***' : v && typeof v === 'object' ? redact(v) : v;
  }
  return out;
}

function summarizeOutput(output) {
  if (output && typeof output === 'object' && !Array.isArray(output)) {
    if (output.id !== undefined) return { id: output.id };
    return output;
  }
  return output;
}

// --- public API ----------------------------------------------------------

/**
 * Execute a flow.
 *
 * @param {Flow} flow
 * @param {FlowTrigger} [trigger] the triggering record + metadata
 * @param {FlowOptions} [options]
 * @returns {Promise<RunLog>} run log { status, steps, metered, ... }
 *
 * @typedef {Object} FlowTriggerSpec
 * @property {string} [type]
 * @property {*} [filter]
 * @property {string[]} [watchedFields]
 *
 * @typedef {Object} Flow
 * @property {string} id
 * @property {string} [name]
 * @property {boolean} [enabled]
 * @property {FlowTriggerSpec} [trigger]
 * @property {*[]} [steps]
 *
 * @typedef {Object} FlowTrigger
 * @property {Object.<string, *>} [record]
 * @property {Object.<string, *>} [fields]
 * @property {Object.<string, *>} [meta]
 * @property {string[]} [changed] update triggers: which fields moved
 *
 * @typedef {Object} FlowOptions
 * @property {Object.<string, Function>} [effects]
 * @property {*} [dataset]
 * @property {*[]} [fields]
 * @property {Object.<string, *>} [refs]
 * @property {Object.<string, *>} [dryRun]
 * @property {string} [now]
 * @property {number} [depth]
 * @property {number} [maxCascadeDepth]
 * @property {number} [stepBudget]
 * @property {string} [onFailure]
 * @property {*} [errorBranch]
 * @property {boolean} [force] run even when the flow is disabled
 * @property {string|null} [tenantId]
 *
 * @typedef {Object} RunLog
 * @property {string} flowId
 * @property {string} [name]
 * @property {string} [triggerType]
 * @property {string} status
 * @property {*[]} steps
 * @property {number} metered
 * @property {Object.<string, *>} outputs
 * @property {Object.<string, *>} [vars]
 * @property {Object.<string, *>} [budget]
 */
export async function runFlow(flow, trigger = {}, options = {}) {
  const run = {
    flowId: flow.id,
    name: flow.name,
    triggerType: flow.trigger && flow.trigger.type,
    status: 'success',
    steps: [],
    metered: 0,
    outputs: {},
  };

  const depth = options.depth ?? 0;
  const maxCascadeDepth = options.maxCascadeDepth ?? DEFAULT_CASCADE_DEPTH;

  if (flow.enabled === false && !options.force) {
    run.status = 'disabled';
    return run;
  }
  if (depth > maxCascadeDepth) {
    run.status = 'cascade-exceeded';
    return run;
  }

  const context = {
    trigger: trigger.record || trigger.fields || {},
    triggerMeta: trigger.meta || {},
    steps: {},
    vars: {},
    depth,
  };

  const env = {
    effects: options.effects || {},
    dataset: options.dataset,
    fields: options.fields || [],
    refs: options.refs || {},
    dryRun: options.dryRun || {},
    depth,
    maxCascadeDepth,
    stepBudget: Number.isFinite(options.stepBudget) ? options.stepBudget : DEFAULT_STEP_BUDGET,
    onFailure: options.onFailure,
    errorBranch: options.errorBranch,
  };

  // Trigger filter: suppressed events create no run and consume no quota.
  if (flow.trigger && flow.trigger.filter) {
    if (!evalCondition(flow.trigger.filter, context, env)) {
      run.status = 'filtered';
      run.metered = 0;
      return run;
    }
  }
  // Watched-field scoping for update triggers.
  if (flow.trigger && flow.trigger.watchedFields && trigger.changed) {
    const watched = flow.trigger.watchedFields;
    if (!watched.some((f) => trigger.changed.includes(f))) {
      run.status = 'filtered';
      run.metered = 0;
      return run;
    }
  }

  // One triggered run is one metered unit (REQ-20), regardless of how many
  // steps, branches or loop iterations it turns into.
  run.metered = 1;
  const outcome = await execSteps(flow.steps, context, run, env);
  run.status = outcome.status === 'continue' ? 'success' : outcome.status;
  run.vars = context.vars;
  // Attribution the LC33 meter needs and the engine cannot know: the rule is
  // ours, the tenant is the host's.
  if (run.budget) {
    run.budget.ruleId = flow.id;
    run.budget.tenantId = options.tenantId ?? null;
  }
  return run;
}
