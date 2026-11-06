/**
 * The durable workflow interpreter.
 *
 * Executes a normalized definition against a run journal. Every step consults
 * the journal first: an execution that already has a `step-completed` entry
 * returns its recorded result instead of running again, so restarting the
 * process re-derives the entire control-flow position for free and resumes at
 * the first step that never finished.
 *
 * ## The delivery guarantee, stated honestly
 *
 * Effects are **at-least-once**, not exactly-once, and no journal design makes
 * them otherwise: the window between "the HTTP request left" and "the result
 * is committed" cannot be closed from inside this process. What closes it is
 * the receiver. Every effect handler is therefore passed an
 * `idempotencyKey` — stable across replays, derived from run id and execution
 * key — and connectors that forward it (Stripe, and every SDK channel built on
 * `sdk/http.js`) turn the retry into a no-op on their side.
 *
 * The alternative, journaling intent before acting and treating an unfinished
 * intent as failed, converts a duplicated Slack message into a *dropped* one.
 * For automations, sending twice is a nuisance and never sending is an
 * incident, so at-least-once is the correct default and the key is how a user
 * upgrades it.
 *
 * ## Fork concurrency
 *
 * Branches run **concurrently** — `Promise.all` over independent branch
 * executions — which is a real win because these steps are almost all
 * I/O-bound. Journal writes are serialized behind a mutex so two branches
 * committing at the same await point cannot both claim the same sequence
 * number. If several branches suspend in one pass, every wait is recorded and
 * the run parks on the earliest; resuming replays the finished branches
 * instantly and continues the rest.
 */

import { renderDeep, renderValue, render } from '../template/jinja.js';
import { checkOutboundUrlSync } from '../io/ssrf-guard.js';
// The LC15 view engine, evaluating a built condition (LC29.10). Imported for
// its FUNCTION, not read at module level — `step-forms.js` records what a
// top-level read of an imported binding costs when the bundler reorders a
// chunk, and this module is loaded by both the browser and the worker.
import { matchesFilter } from '../views/query.js';
import { STEP_TYPES, stepType, executionKey, loopFrame, forkFrame, normalizeWorkflow } from './ir.js';
import { beginCommit, journalIndex, recordClock } from './journal.js';
import { traceValue } from './trace-value.js'; import { runClock } from './run-clock.js';
// The metric vocabulary, shared with the inline flow engine so an operator
// plane consuming budget exhaustion sees one reason string, not two.
import { BUDGET_EXCEEDED } from './flow-engine.js';
// The run-log sentences below resolve through `t()` AT THE MOMENT they are
// thrown or recorded. In the browser — the dry-run and step-test paths — that
// is the author's language; in the worker it is the source locale, exactly
// the English these strings were before they were keyed, so nothing stored
// changes shape on that path. `language.js` is already in this module's
// import closure (ir.js pulls it in for its keyed validation messages), so no
// environment that can load this module today is widened by the import.
import { t } from '../language.js';

// --- control-flow signals -------------------------------------------------

/** Thrown to park the run. Carries what the scheduler must wait for. */
export class Suspension extends Error {
  constructor(wait) {
    super(`suspended:${wait.kind}`);
    this.name = 'Suspension';
    this.wait = wait;
  }
}

/** Thrown by a `stop` step — an ordinary, successful early exit. */
class StopRun extends Error {
  constructor(reason) { super(reason || 'stopped'); this.name = 'StopRun'; }
}

/** Thrown by a `fail` step, or by an unhandled step failure. */
class FailRun extends Error {
  constructor(message, details) { super(message); this.name = 'FailRun'; this.details = details; }
}

/** Thrown when another writer moved the run out from under us. */
export class StaleWrite extends Error {
  constructor(reason) { super(reason); this.name = 'StaleWrite'; }
}

/** Thrown when a cancel was requested while the run was executing. */
class CancelRun extends Error {
  constructor(reason) { super(reason || 'cancelled'); this.name = 'CancelRun'; }
}

export const DEFAULT_RETRY = { attempts: 3, backoffMs: 1000, multiplier: 2, maxBackoffMs: 60000 };

/**
 * The signal name an `approval` step parks on.
 *
 * Derived from the execution key rather than typed by the author, for the same
 * reason the key itself is derived: two approval steps in one workflow, or two
 * iterations of one inside a `foreach`, must not share a signal. A form field
 * would let an author give both the same name, and the second decision would
 * resume the first iteration.
 */
export function approvalSignal(key) {
  return `approval:${key}`;
}

// --- duration parsing -----------------------------------------------------

const DURATION_RE = /^\s*(\d+(?:\.\d+)?)\s*(ms|s|sec|secs|seconds?|m|min|mins|minutes?|h|hr|hrs|hours?|d|days?|w|weeks?)\s*$/i;

const UNIT_MS = {
  ms: 1, s: 1000, sec: 1000, secs: 1000, second: 1000, seconds: 1000,
  m: 60000, min: 60000, mins: 60000, minute: 60000, minutes: 60000,
  h: 3600000, hr: 3600000, hrs: 3600000, hour: 3600000, hours: 3600000,
  d: 86400000, day: 86400000, days: 86400000,
  w: 604800000, week: 604800000, weeks: 604800000,
};

/**
 * Parse "4h", "30 minutes", "1d" or a raw millisecond number.
 *
 * Returns null rather than guessing on unparseable input, because a delay that
 * silently becomes zero turns an escalation gate into an instant page.
 */
export function parseDuration(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value >= 0 ? value : null;
  if (typeof value !== 'string') return null;
  if (/^\s*\d+(\.\d+)?\s*$/.test(value)) return Number(value);
  const m = value.match(DURATION_RE);
  if (!m) return null;
  return Number(m[1]) * UNIT_MS[m[2].toLowerCase()];
}

// --- mutex ----------------------------------------------------------------

/**
 * Serializes journal writes across concurrent fork branches.
 *
 * JS is single-threaded, but `await` is an interleaving point: two branches
 * that both call `flush()` would each read `run.seq`, each build a commit from
 * it, and the second would be rejected as a stale write — losing a branch's
 * work for no reason other than scheduling luck.
 */
function createMutex() {
  let tail = Promise.resolve();
  return (fn) => {
    const result = tail.then(fn, fn);
    tail = result.then(() => undefined, () => undefined);
    return result;
  };
}

// --- executor -------------------------------------------------------------

/**
 * Render one step's config against a context, honouring the raw-field list.
 *
 * Lifted out of `Executor#renderConfig` — which now calls it — so that the
 * per-step test (LC30.23, `workflow/step-test.js`) can show an author the
 * configuration a step WOULD run with, without standing up a run. That surface
 * has to agree with the engine exactly: a preview that resolves `{{ … }}`
 * slightly differently from the executor is worse than no preview, because it
 * is a preview somebody believes.
 *
 * The raw list is the reason this cannot be "just call renderDeep". Fields like
 * `mcpTool.tool` and `approval.callbackSecret` are deliberately NOT templated,
 * and a preview that rendered them would show the author a value the run will
 * never use.
 *
 * @param {object} step
 * @param {object} context the scope `{{ … }}` is resolved against
 * @returns {Object.<string, *>}
 */
export function renderStepConfig(step, context) {
  const meta = stepType(step && step.type) || { raw: [] };
  const config = (step && step.config) || {};
  /** @type {Object.<string, *>} */
  const out = {};
  for (const [key, value] of Object.entries(config)) {
    out[key] = (meta.raw || []).includes(key) ? value : renderDeep(value, context);
  }
  return out;
}

class Executor {
  constructor(workflow, run, deps) {
    this.workflow = workflow;
    this.run = run;
    this.deps = deps;
    this.index = journalIndex(run);
    this.commit = beginCommit(run);
    this.lock = createMutex();
    this.vars = {};
    this.outputs = {};
    this.suspensions = [];
    this.changes = [];
    this.stepBudget = workflow.settings.maxSteps ?? 10000;
    this.stepsRun = 0;
  }

  now() { return this.deps.now ? this.deps.now() : Date.now(); }

  /** Commit the pending entries, refresh the run header and the replay index. */
  flush() {
    return this.lock(async () => {
      if (this.commit.isEmpty) return;
      const built = this.commit.build();
      // A sibling can finish during the store's await. Give it a separate
      // buffer now; resetting the original builder afterwards loses its work.
      this.commit = beginCommit(this.run);
      let result;
      try { result = await this.deps.store.commit(this.run.runId, built); }
      catch (error) {
        const pending = this.commit;
        this.commit = beginCommit(this.run);
        this.commit.entries.push(...built.entries, ...pending.entries);
        this.commit.setHeader({ ...built.patch, ...pending.patch });
        this.commit.rebase(this.run);
        throw error;
      }
      if (!result.ok) throw new StaleWrite(result.reason);
      this.run = result.run;
      this.index = journalIndex(this.run);
      this.commit.rebase(this.run);
    });
  }

  /**
   * The object every template in this run is rendered against.
   *
   * `extra` carries the lexical scope — the `foreach` alias and its `loop`
   * metadata — and is threaded down the call chain as an argument rather than
   * kept on a stack here. A stack would be correct for sequential execution
   * and quietly wrong the moment two fork branches each entered a loop: they
   * interleave at every `await`, so one branch would render the other's item.
   */
  context(extra = {}) {
    return {
      trigger: this.run.trigger.payload || {},
      triggerMeta: this.run.trigger.meta || {},
      input: this.run.input || {},
      vars: this.vars,
      steps: this.outputs,
      run: {
        id: this.run.runId,
        workflowId: this.run.workflowId,
        mode: this.run.mode,
        startedAt: this.run.startedAt,
        attempt: extra.attempt ?? 1,
      },
      env: this.deps.env || {}, ...runClock(this.run.startedAt), // {{ now }} / {{ today }}: the run start, so a replay renders the same date
      ...extra,
    };
  }

  /** Render a step's config, honouring the per-type raw-field list. */
  renderConfig(step, scope) {
    return renderStepConfig(step, this.context(scope));
  }

  record(type, fields) { return this.commit.add(type, fields); }

  /**
   * Honour a pause or cancel requested while this run was executing.
   *
   * Checked at every step boundary rather than mid-step, because a step is the
   * unit that either happened or did not. Interrupting between "the HTTP
   * request left" and "the result was journaled" would produce a paused run
   * whose journal denies an effect that already landed.
   */
  assertControl() {
    if (this.run.cancelRequested) throw new CancelRun(this.run.cancelReason);
    if (this.run.pauseRequested) throw new Suspension({ kind: 'paused' });
  }

  /** Note a mutation for the dry-run summary. */
  noteChange(change) { this.changes.push(change); }

  /**
   * Note an outbound host the preview could not judge.
   *
   * `checkOutboundUrlSync` returns `{ok: true, resolved: false}` for a
   * public-*looking* name, and its own doc is explicit that this "is a
   * deliberate non-answer, not an approval — a caller that treats the two as
   * the same thing has a hole, and one that reports the caveat is telling the
   * truth". The dry run was the caller treating them as the same thing: it
   * read only `ok === false`, so a preview of a webhook at `localtest.me` — a
   * real public name whose A record is 127.0.0.1 — printed "Dry run completed"
   * while the live run refuses it with `resolves to 127.0.0.1, which is
   * loopback`.
   *
   * Nothing is reached either way; a dry run opens no socket. What was wrong is
   * that the preview whose entire job is to tell you what a run would do said
   * it would be fine about the one thing it had not checked. Recording the host
   * lets the report say which names are still pending a verdict, in the same
   * voice it already uses for template fields it could not resolve.
   */
  noteUncheckedHost(host) {
    if (!this.uncheckedHosts) this.uncheckedHosts = [];
    if (!this.uncheckedHosts.includes(host)) this.uncheckedHosts.push(host);
  }
}

// --- truthiness -----------------------------------------------------------

function truthy(value) {
  if (Array.isArray(value)) return value.length > 0;
  if (value && typeof value === 'object') return Object.keys(value).length > 0;
  if (typeof value === 'string') return value !== '' && value !== 'false';
  return !!value;
}

/**
 * Evaluate a condition — a built filter tree, a Jinja expression, or a boolean.
 *
 * A TREE is what the condition builder writes (LC29.10), and it is evaluated by
 * `matchesFilter`: the LC15 view engine, unchanged. That is the point of
 * storing a tree at all. An operator means one thing in this product — `is` on
 * text is case-insensitive, `within` resolves a day range, an empty
 * multi-select is empty rather than absent — and a second implementation of
 * those rules for automations would drift from the filter builder that taught
 * the author what the operator does.
 *
 * The record is the trigger payload, which for a record trigger is the row's
 * fields flattened; `fields` is empty because every leaf the builder writes
 * carries its own `type`, and a run has no column list to consult.
 *
 * A STRING is still a template, so every condition written before the builder
 * existed evaluates exactly as it did.
 */
export function evaluateCondition(expression, context) {
  if (expression === undefined || expression === null) return true;
  if (typeof expression === 'boolean') return expression;
  if (typeof expression === 'object') {
    const ctx = context || {};
    return matchesFilter(expression, ctx.trigger || {}, new Map(), {
      // `isCurrentUser` on a rule means the identity the run executes as. A
      // rule with no acting principal — a schedule, a webhook — leaves it
      // null, and the operator then matches nothing rather than matching
      // whichever user the worker process happens to belong to.
      userId: (ctx.triggerMeta && (ctx.triggerMeta.userId || ctx.triggerMeta.actorId)) || null,
      now: new Date(),
    });
  }
  const source = String(expression);
  const wrapped = source.includes('{{') || source.includes('{%') ? source : `{{ ${source} }}`;
  return truthy(renderValue(wrapped, context));
}

// --- step execution -------------------------------------------------------

async function checkApprovalEvidence(step, ex, key, result) {
  if (!step.config.evidenceFields?.length || result?.dryRun || result?.timedOut) return;
  if (!result?.approvalId || !ex.deps.effects?.checkApprovalGate) {
    throw new FailRun('approval-evidence-check-unavailable', { stepId: step.id });
  }
  try {
    await ex.deps.effects.checkApprovalGate({ approvalId: result.approvalId, runId: ex.run.runId, key });
  } catch (error) {
    // A stale authorization is not an optional failed effect. continueOnError
    // must never turn an evidence refusal into permission for the next step.
    throw new FailRun(error.message || 'approval-evidence-check-failed', { stepId: step.id });
  }
}

async function execSteps(steps, ex, frames, scope = {}) {
  for (const step of steps || []) {
    await execStep(step, ex, frames, scope);
  }
}

async function execStep(step, ex, frames, scope = {}) {
  const key = executionKey(step.id, frames);
  const meta = STEP_TYPES[step.type];

  if (!meta) throw new FailRun(t('workflow.validate.unknownStepType', null, { type: step.type }), { stepId: step.id });

  ex.assertControl();

  if (ex.stepsRun++ > ex.stepBudget) {
    // `reason` is the machine-readable half. The budget-exhaustion metric is
    // consumed by an operator plane that must not have to regex an error
    // message to find out why a run stopped — a contract nobody can match
    // without string-matching prose is not a contract.
    throw new FailRun(t('workflow.run.error.stepBudget', null, { budget: ex.stepBudget }), { stepId: step.id, reason: BUDGET_EXCEEDED, budget: ex.stepBudget });
  }

  // Replay: a completed execution returns its recorded result and runs nothing.
  if (ex.index.isComplete(key)) {
    const result = ex.index.result(key);
    if (step.type === 'approval') await checkApprovalEvidence(step, ex, key, result);
    if (result !== undefined) ex.outputs[step.id] = result;
    if (step.type === 'set' && result && typeof result === 'object') Object.assign(ex.vars, result);
    return replayControl(step, ex, frames, result, scope);
  }

  // A guard that was false on an earlier pass stays false. Evaluating it
  // against later variables can admit an effect the original run skipped.
  if (ex.index.skipped(key)?.reason === 'guard-false') return undefined;

  // Per-step guard, evaluated fresh — it reads context, not the journal.
  if (!ex.index.started(key) && step.if !== undefined && !evaluateCondition(step.if, ex.context(scope))) {
    ex.record('step-skipped', { key, stepId: step.id, reason: 'guard-false' });
    await ex.flush();
    return undefined;
  }

  const startedAt = ex.now();
  const started = ex.record('step-started', { key, stepId: step.id, stepType: step.type, at: startedAt });

  try {
    const config = ex.renderConfig(step, scope);
    started.input = traceValue(config);
    const result = await dispatch(step, ex, frames, key, scope, config);
    if (result !== undefined) ex.outputs[step.id] = result;
    const finishedAt = ex.now();
    ex.record('step-completed', { key, stepId: step.id, stepType: step.type, at: finishedAt, durationMs: Math.max(0, finishedAt - startedAt), ...(result !== undefined ? { result } : {}) });
    await ex.flush();
    return result;
  } catch (error) {
    if (error instanceof Suspension || error instanceof StopRun || error instanceof StaleWrite || error instanceof CancelRun) throw error;
    const failedAt = ex.now();
    ex.record('step-failed', { key, stepId: step.id, at: failedAt, durationMs: Math.max(0, failedAt - startedAt), error: String(error && error.message ? error.message : error) });
    await ex.flush();
    if (error instanceof FailRun) throw error;
    if (step.continueOnError) return undefined;
    throw new FailRun(t('workflow.run.error.stepFailed', null, { step: step.id, error: error && error.message ? error.message : error }), { stepId: step.id });
  }
}

/**
 * Control steps still need their children walked on replay.
 *
 * A completed `if` returns which branch it took; the branch's own steps carry
 * their own keys and may be half-finished. Returning early here would skip the
 * unfinished half of a branch that had already chosen — the single most likely
 * way to get a resumed run to quietly do nothing.
 */
async function replayControl(step, ex, frames, result, scope) {
  switch (step.type) {
    case 'if':
      await execSteps(result && result.branch === 'then' ? step.then : step.else, ex, [...frames, step.id], scope);
      return result;
    case 'case': {
      const chosen = (step.cases || []).find((c) => c.name === (result && result.branch));
      await execSteps(chosen ? chosen.steps : step.default, ex, [...frames, step.id], scope);
      return result;
    }
    case 'foreach': {
      const items = ex.index.loop(executionKey(step.id, frames))?.items ?? resolveItems(step, ex, scope);
      const alias = step.config.as || 'item';
      for (let i = 0; i < items.length; i++) {
        await execSteps(step.steps, ex, [...frames, loopFrame(step.id, i)], loopScope(scope, alias, items, i));
      }
      return result;
    }
    case 'fork': {
      const join = result?.join || step.config.join || 'all';
      if (join === 'any' || join === 'race') {
        // A completed race abandoned its unfinished siblings. Replaying those
        // would revive them after an unrelated later delay.
        const names = result?.branches || ex.index.forkBranches(executionKey(step.id, frames));
        for (const branch of step.branches || []) {
          if (names.includes(branch.name)) await execSteps(branch.steps, ex, [...frames, forkFrame(step.id, branch.name)], scope);
        }
      } else await runBranches(step, ex, frames, scope);
      return result;
    }
    case 'try':
      if (result?.caught) ex.vars.error = ex.index.branch(executionKey(step.id, frames))?.error || { message: result.error };
      await execSteps(result?.caught ? step.catch : step.steps, ex, [...frames, result?.caught ? `${step.id}:catch` : step.id], scope);
      return result;
    default:
      return result;
  }
}

/** The scope one `foreach` iteration adds: the alias plus Jinja's `loop`. */
function loopScope(scope, alias, items, i) {
  return {
    ...scope,
    [alias]: items[i],
    loop: {
      index: i + 1, index0: i, first: i === 0, last: i === items.length - 1, length: items.length,
      previtem: i > 0 ? items[i - 1] : undefined,
      nextitem: i < items.length - 1 ? items[i + 1] : undefined,
    },
  };
}

function resolveItems(step, ex, scope) {
  const raw = renderValue(String(step.config.items ?? ''), ex.context(scope));
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === 'object') return Object.entries(raw).map(([k, v]) => ({ key: k, value: v }));
  if (raw == null || raw === '') return [];
  return [raw];
}

async function dispatch(step, ex, frames, key, scope = {}, config = ex.renderConfig(step, scope)) {

  switch (step.type) {
    // --- control flow
    case 'if': {
      const recorded = ex.index.branch(key);
      const taken = recorded?.branch ?? (evaluateCondition(step.config.condition, ex.context(scope)) ? 'then' : 'else');
      if (!recorded) { ex.record('branch-taken', { key, stepId: step.id, branch: taken }); await ex.flush(); }
      await execSteps(taken === 'then' ? step.then : step.else, ex, [...frames, step.id], scope);
      return { branch: taken };
    }

    case 'case': {
      const recorded = ex.index.branch(key);
      const context = ex.context(scope);
      const match = (step.cases || []).find((c) => recorded ? c.name === recorded.branch : evaluateCondition(c.when, context));
      const branch = recorded?.branch ?? (match ? (match.name || 'case') : 'default');
      if (!recorded) { ex.record('branch-taken', { key, stepId: step.id, branch }); await ex.flush(); }
      await execSteps(match ? match.steps : step.default, ex, [...frames, step.id], scope);
      return { branch };
    }

    case 'foreach': {
      const recorded = ex.index.loop(key);
      const items = recorded?.items ?? resolveItems(step, ex, scope);
      const cap = Number(config.cap ?? 10000);
      if (items.length > cap) throw new FailRun(t('workflow.run.error.foreachCap', null, { step: step.id, count: items.length, cap }));
      if (!Array.isArray(recorded?.items)) { ex.record('loop-started', { key, stepId: step.id, count: items.length, items }); await ex.flush(); }
      const alias = step.config.as || 'item';
      for (let i = 0; i < items.length; i++) {
        await execSteps(step.steps, ex, [...frames, loopFrame(step.id, i)], loopScope(scope, alias, items, i));
      }
      return { count: items.length };
    }

    case 'fork': {
      ex.record('fork-started', { key, stepId: step.id, branches: (step.branches || []).map((b) => b.name) });
      const outcome = await runBranches(step, ex, frames, scope);
      return { joined: outcome.completed, join: step.config.join || 'all', branches: outcome.branches };
    }

    case 'try': {
      const caught = ex.index.branch(key);
      if (caught?.branch === 'catch') {
        ex.vars.error = caught.error;
        await execSteps(step.catch, ex, [...frames, `${step.id}:catch`], scope);
        return { caught: true, error: caught.error.message };
      }
      try {
        await execSteps(step.steps, ex, [...frames, step.id], scope);
        return { caught: false };
      } catch (error) {
        if (error instanceof Suspension || error instanceof StaleWrite || error instanceof StopRun || error instanceof CancelRun) throw error;
        ex.vars.error = { message: error.message, stepId: error.details && error.details.stepId };
        ex.record('branch-taken', { key, stepId: step.id, branch: 'catch', error: ex.vars.error });
        await ex.flush();
        await execSteps(step.catch, ex, [...frames, `${step.id}:catch`], scope);
        return { caught: true, error: error.message };
      }
    }

    case 'stop':
      throw new StopRun(config.reason || t('workflow.run.error.stoppedByStop'));

    case 'fail':
      throw new FailRun(config.message || t('workflow.run.error.failedByStep', null, { step: step.id }), { stepId: step.id });

    // --- waiting
    case 'delay': {
      const ms = parseDuration(config.duration ?? config.ms);
      const wakeAt = config.until
        ? Date.parse(String(config.until))
        : recordClock(`${key}:wake`, ex.index, ex.commit, () => ex.now() + (ms ?? 0));
      if (ms === null && !config.until) throw new FailRun(t('workflow.run.error.delayBadDuration', null, { step: step.id }));
      if (Number.isNaN(wakeAt)) throw new FailRun(t('workflow.run.error.delayBadUntil', null, { step: step.id }));
      if (ex.now() >= wakeAt) return { wokeAt: ex.now(), wakeAt };
      ex.record('timer-set', { key, stepId: step.id, wakeAt });
      throw new Suspension({ kind: 'timer', key, stepId: step.id, wakeAt });
    }

    case 'wait-signal': {
      const signal = step.config.signal;
      const received = ex.index.signal(key);
      if (received) return { signal, payload: received.payload, receivedAt: received.at };

      const timeoutMs = parseDuration(config.timeout);
      const timeoutAt = timeoutMs
        ? recordClock(`${key}:timeout`, ex.index, ex.commit, () => ex.now() + timeoutMs)
        : null;

      if (timeoutAt && ex.now() >= timeoutAt) {
        if ((step.config.timeoutAction || 'fail') === 'continue') return { signal, timedOut: true };
        throw new FailRun(t('workflow.run.error.waitTimedOut', null, { step: step.id, signal }), { stepId: step.id });
      }

      ex.record('signal-awaited', { key, stepId: step.id, signal, timeoutAt });
      throw new Suspension({
        kind: 'signal', key, stepId: step.id, signal, timeoutAt,
        // What a dashboard button needs to render itself and call back.
        resume: { label: config.label || step.name || signal, inputs: config.inputs || {} },
      });
    }

    /**
     * Park the run until named people decide.
     *
     * Everything durable here is already built — the journal, `Suspension`,
     * the signal path, the sweeper — so this case is mostly about the two ways
     * an approval gate goes wrong and neither is about waiting:
     *
     *  1. **Creating the approval twice.** A resumed run replays this step, so
     *     the created row's id is journaled as a `clock` entry and the commit
     *     happens BEFORE the throw. `journal.js` already declares that id
     *     generation goes through the recorded-value door, so this is reuse of
     *     that door rather than a new journal concept. It narrows the window;
     *     it does not close it — see the at-least-once note at the top of this
     *     file, which applies to this effect exactly as it does to a webhook.
     *
     *  2. **Parking without a decision to read.** A gate that only resumes is
     *     a `delay` with extra steps. The signal payload is returned as the
     *     step result, so a later step reads `{{ steps.gate.decision }}` and
     *     can branch on `{{ steps.gate.approved }}`.
     */
    case 'approval': {
      const signal = approvalSignal(key);
      const received = ex.index.signal(key);
      if (received) {
        const payload = received.payload || {};
        // The signal may have waited in the journal while the record changed.
        // Bound gates require a fresh server check before any next step runs.
        await checkApprovalEvidence(step, ex, key, payload);
        return { ...payload, signal, receivedAt: received.at, approved: payload.decision === 'approved' };
      }

      const timeoutMs = parseDuration(config.timeout);
      const timeoutAt = timeoutMs
        ? recordClock(`${key}:timeout`, ex.index, ex.commit, () => ex.now() + timeoutMs)
        : null;

      if (timeoutAt && ex.now() >= timeoutAt) {
        // The same wake_at path `wait-signal` uses — no new timer machinery.
        if ((step.config.timeoutAction || 'fail') === 'continue') {
          return { signal, timedOut: true, decision: null, approved: false };
        }
        throw new FailRun(t('workflow.run.error.approvalTimedOut', null, { step: step.id }), { stepId: step.id });
      }

      if (ex.run.mode === 'dry-run') {
        // A preview must not file a real approval or page real people, and it
        // equally must not invent a decision: `decision` stays null so a
        // downstream `{{ steps.gate.approved }}` reads false in the preview
        // rather than showing the approved path as if it had been chosen.
        const preview = describeChange(step, config);
        ex.noteChange(preview);
        ex.record('effect-recorded', { key, stepId: step.id, stepType: step.type, preview });
        return { dryRun: true, asked: config.approvers || [], decision: null, approved: false };
      }

      let approvalId = ex.index.recorded(`${key}:approval`);
      if (approvalId === undefined) {
        const created = await callEffect(step, ex, key, {
          ...config,
          // The handler needs to know where the answer goes; it is the only
          // thing that writes the row, so it is the only thing that can stamp
          // the origin the sweeper reads back.
          signal, stepId: step.id, executionKey: key,
        }, scope);
        approvalId = created && (created.approvalId ?? created.id);
        if (!approvalId) {
          throw new FailRun(
            t('workflow.run.error.approvalNotCreated', null, { step: step.id }),
            { stepId: step.id }
          );
        }
        ex.record('clock', { key: `${key}:approval`, value: approvalId });
        // Committed before the throw. Suspending first and journaling after
        // would mean a crash in between leaves a parked run whose journal
        // denies the approval that is sitting in the approver's queue — and
        // the resume would raise a second one.
        await ex.flush();
      }

      ex.record('signal-awaited', { key, stepId: step.id, signal, timeoutAt });
      throw new Suspension({
        kind: 'signal', key, stepId: step.id, signal, timeoutAt, approvalId,
        // No `resume` block, deliberately. That block is what a dashboard
        // renders an unconditional button from, and this wait must not get
        // one: only `current_approvers` may action it, and `approvalId` is how
        // a screen knows to ask `gateActionsFor` instead.
      });
    }

    // --- data
    case 'set': {
      const value = config.value !== undefined ? config.value : renderValue(String(step.config.expression ?? ''), ex.context(scope));
      ex.vars[step.config.name] = value;
      ex.record('var-set', { key, name: step.config.name });
      return { [step.config.name]: value };
    }

    case 'log':
      return { message: typeof config.message === 'string' ? config.message : render(String(step.config.message ?? ''), ex.context(scope)) };

    // Data steps and effect steps take the same path; what separates them is
    // the `mutates` flag the dry-run gate reads, not the dispatch.
    default:
      return callEffect(step, ex, key, config, scope);
  }
}

/**
 * Run fork branches concurrently, collecting every suspension.
 *
 * `Promise.all` would reject on the first suspension and abandon the other
 * branches mid-flight — their in-flight effects would still land, but
 * unjournaled, so the resume would run them again. `allSettled` lets every
 * branch reach a committed resting point first.
 */
async function runBranches(step, ex, frames, scope = {}) {
  const branches = step.branches || [];
  const join = step.config.join || 'all';

  const settled = await Promise.allSettled(
    branches.map((branch) => execSteps(branch.steps, ex, [...frames, forkFrame(step.id, branch.name)], scope))
  );

  const suspensions = [];
  const failures = [];
  let completed = 0;
  const completedBranches = [];

  settled.forEach((outcome, i) => {
    if (outcome.status === 'fulfilled') {
      completed++; completedBranches.push(branches[i].name);
      ex.record('fork-branch-completed', { key: executionKey(step.id, frames), stepId: step.id, branch: branches[i].name }); return;
    }
    const error = outcome.reason;
    if (error instanceof Suspension) suspensions.push(error);
    else failures.push(error);
  });

  await ex.flush();

  if (failures.length) {
    const stale = failures.find((e) => e instanceof StaleWrite);
    if (stale) throw stale;
    const cancelled = failures.find((e) => e instanceof CancelRun);
    if (cancelled) throw cancelled;
    const stop = failures.find((e) => e instanceof StopRun);
    if (stop && join !== 'all') throw stop;
    if (join === 'all' || (!completed && !suspensions.length)) throw failures[0];
  }

  // `any`/`race` are satisfied by one finished branch; a still-waiting sibling
  // is abandoned rather than kept alive, which is what racing means.
  if (completed > 0 && (join === 'any' || join === 'race')) return { completed, branches: completedBranches };

  if (suspensions.length) {
    suspensions.sort((a, b) => (a.wait.wakeAt ?? a.wait.timeoutAt ?? Infinity)
      - (b.wait.wakeAt ?? b.wait.timeoutAt ?? Infinity));
    throw new Suspension({ ...suspensions[0].wait, siblings: suspensions.slice(1).map((s) => s.wait) });
  }

  return { completed, branches: completedBranches };
}

/**
 * Hand a step to its effect handler, with retries and a dry-run gate.
 *
 * The dry run stops at exactly this line: control flow, templating,
 * conditions, loops and data steps all execute for real, so the preview
 * reflects the decisions the live run would make. Only handlers whose step
 * type is declared `mutates` are withheld.
 */
/**
 * Refuse a webhook aimed at the inside of our own network.
 *
 * A `webhook` step is an outbound request builder pointed at whatever string
 * the author typed, executed from inside the compose network — so this is the
 * one control that stands between "any user who can create a workflow" and
 * `http://meta:8080/query`, which is arbitrary SQL as a database superuser.
 *
 * ## Why it lives here and not only in the handler
 *
 * `effects.js` already refuses a bad URL, and the worker refuses it a second
 * time at the socket. Both of those are on the LIVE path. The dry run never
 * reaches either: `callEffect` withholds every `mutates` handler below, so a
 * preview of a webhook at 169.254.169.254 used to render a tidy
 * "Call 169.254.169.254" and report the workflow as fine. Nothing was fetched
 * — but the author was told the definition was good, and the refusal only
 * arrived once it was live. Deciding it at the dispatcher, ahead of the gate,
 * means the preview and the run give the same verdict for the same reason.
 *
 * ## What this check can and cannot see
 *
 * `checkOutboundUrlSync` judges literals — v4, v6, the `::ffff:` mapped forms
 * — plus dotless container names, `*.localhost` and the metadata endpoint. It
 * cannot resolve DNS, because the dry run executes in a browser where no
 * resolver exists. A public-looking name whose A record points at
 * 169.254.169.254 therefore passes HERE and is refused by the resolving guard
 * in the worker before a socket is opened. A host that can resolve says so by
 * passing `deps.checkUrl`; the worker does, so its runs are judged on the
 * resolved address at this point too.
 */
async function outboundRefusal(step, config, ex) {
  if (step.type !== 'webhook') return null;
  const url = config && config.url;
  // An absent URL is the validator's complaint to make, not the guard's — and
  // "a webhook step requires a url" is the more useful of the two messages.
  if (url === undefined || url === null || url === '') return null;
  const check = ex.deps.checkUrl || checkOutboundUrlSync;
  const verdict = await check(String(url));
  if (verdict && verdict.ok === false) return verdict.error;
  // Approved, but only as far as this caller could see. `resolved: false` means
  // the host is a public-looking name and nothing resolved it — true in the
  // browser preview, never true on the worker, which passes a DNS-resolving
  // `checkUrl`. Carry the caveat instead of discarding it.
  if (verdict && verdict.ok && verdict.resolved === false && verdict.host) {
    ex.noteUncheckedHost(verdict.host);
  }
  return null;
}

async function callEffect(step, ex, key, config, scope = {}) {
  // `stepType`, not `STEP_TYPES[...]`: a step contributed by an installed app
  // is a real step type (LC39.2), and reading only the built-in map made `meta`
  // undefined for one — which skipped the dry-run gate below on the step most
  // in need of it, since an extension step runs vendor code.
  const meta = stepType(step.type) || { mutates: true };
  // An extension step dispatches through ONE handler rather than a handler per
  // installed app: the app is an argument, not a different kind of effect. The
  // namespaced key is what tells them apart, and it is the same key the
  // registry, the palette and the package store all use.
  const handler = ex.deps.effects
    && (ex.deps.effects[step.type] || (step.type.includes('.') ? ex.deps.effects.extension : undefined));

  const refusal = await outboundRefusal(step, config, ex);
  if (refusal) {
    // `permanent` so the retry loop does not turn one refusal into three. The
    // URL is not going to become public between attempts, and `attempts: 3`
    // in a run log tells the reader the network was flaky when the truth is
    // that the address is not allowed and they must change it.
    const error = new Error(`${step.type} step ${refusal}`);
    error.permanent = true;
    throw error;
  }

  if (ex.run.mode === 'dry-run' && meta.mutates) {
    const preview = describeChange(step, config);
    ex.noteChange(preview);
    ex.record('effect-recorded', { key, stepId: step.id, stepType: step.type, preview });
    return { dryRun: true, ...preview.summary };
  }

  if (typeof handler !== 'function') {
    ex.record('step-skipped', { key, stepId: step.id, reason: `no-handler:${step.type}` });
    return { skipped: true, reason: `no-handler:${step.type}` };
  }

  const policy = { ...DEFAULT_RETRY, ...(ex.workflow.settings.retryPolicy || {}) };
  const maxAttempts = step.retries ?? policy.attempts;
  const already = ex.index.failureCount(key);

  let lastError;
  for (let attempt = already + 1; attempt <= maxAttempts; attempt++) {
    try {
      return await handler({
        config,
        step,
        context: ex.context({ ...scope, attempt }),
        // Stable across replays, which is what lets a receiver dedupe.
        idempotencyKey: `${ex.run.runId}:${key}`,
        runId: ex.run.runId,
        attempt,
        signal: ex.deps.abortSignal,
      });
    } catch (error) {
      lastError = error;
      // A permanent error is not a flaky network. Retrying an SSRF refusal
      // three times produced three identical refusals and a run log that
      // implied the network was at fault.
      if (error && error.permanent) break;
      // Only the RETRIED attempts are journaled here. The final one throws to
      // `execStep`, which journals the terminal failure — recording it in both
      // places put the last attempt in the run log twice, so a step with three
      // attempts showed four failures and any "attempts" metric read high.
      if (attempt < maxAttempts) {
        ex.record('step-failed', { key, stepId: step.id, attempt, at: ex.now(), error: String(error && error.message ? error.message : error) });
        await ex.flush();
        const backoff = Math.min(policy.backoffMs * policy.multiplier ** (attempt - 1), policy.maxBackoffMs);
        // A receiver that said how long to wait (Retry-After on a 429) is obeyed, up
        // to the policy ceiling; burning every attempt inside its rate-limit window
        // helps nobody.
        const stated = Number(error && error.retryAfterMs);
        const wait = Number.isFinite(stated) && stated > 0 ? Math.max(backoff, Math.min(stated, policy.maxBackoffMs)) : backoff;
        await sleep(wait, ex.deps);
      }
    }
  }
  throw lastError || new Error(t('workflow.run.error.attemptsExhausted', null, { step: step.id, attempts: maxAttempts }));
}

function sleep(ms, deps) {
  if (deps.sleep) return deps.sleep(ms);
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** A human-readable preview of a mutation, for the dry-run summary. */
function describeChange(step, config) {
  switch (step.type) {
    case 'create-record':
      return { type: 'create-record', table: config.table, values: config.values, summary: { table: config.table }, label: t('workflow.describe.createRecordIn', null, { table: config.table }) };
    case 'update-record':
      return { type: 'update-record', table: config.table, target: config.target ?? config.id, values: config.values, summary: { table: config.table }, label: t('workflow.describe.updateRecord', null, { table: config.table, record: config.target ?? config.id ?? '' }).trim() };
    case 'delete-record':
      return { type: 'delete-record', table: config.table, target: config.target ?? config.id, summary: { table: config.table }, label: t('workflow.describe.deleteRecord', null, { table: config.table, record: config.target ?? config.id ?? '' }).trim() };
    case 'lot-receipt':
    case 'lot-disposition': {
      const table = step.config.tables?.lots?.table;
      return { type: step.type, table, summary: { table }, label: t(`workflow.palette.${step.type}`) };
    }
    case 'webhook':
      return { type: 'webhook', method: config.method || 'POST', url: config.url, body: config.body, summary: { url: config.url }, label: `${(config.method || 'POST').toUpperCase()} ${config.url}` };
    case 'connector':
      return { type: 'connector', channel: step.config.channel, action: step.config.action, params: config, summary: { channel: step.config.channel, action: step.config.action }, label: `${step.config.channel}: ${step.config.action}` };
    case 'mcpTool':
      // The connection and tool come off `step.config`, not off `config`: they
      // are raw by declaration, and reading them from the rendered values would
      // quietly reintroduce the templating the IR refuses.
      return {
        type: 'mcpTool',
        connectionId: step.config.connectionId,
        tool: step.config.tool,
        arguments: config.arguments || {},
        summary: { connectionId: step.config.connectionId, tool: step.config.tool },
        label: t('workflow.describe.callTool', null, { tool: step.config.tool, connection: step.config.connectionId }),
      };
    case 'email':
      return { type: 'email', to: config.to, subject: config.subject, summary: { to: config.to }, label: t('workflow.describe.email', null, { to: config.to }) };
    case 'notify': {
      // A blank recipient is a documented value (see `step-forms.js`: "Blank
      // sends to the workflow owner"), so the label must not interpolate it
      // raw. It read `Notify undefined` — a dry run, whose whole job is to tell
      // a reviewer what a live run would do, reporting a defect that is not
      // there and saying nothing about where the notification actually goes.
      //
      // Only the LABEL changes. `to` and `summary` still carry exactly what was
      // configured, because resolving the owner is the host's job and guessing
      // at it here would be a second implementation of that rule.
      const named = config.to == null || String(config.to).trim() === '' ? null : config.to;
      return {
        type: 'notify',
        to: config.to,
        summary: { to: config.to },
        label: named ? t('workflow.describe.notify', null, { to: named }) : t('workflow.describe.notifyOwner'),
      };
    }
    case 'approval': {
      const asked = (config.approvers || []).length;
      return {
        type: 'approval',
        table: step.config.table,
        record: config.record,
        approvers: config.approvers || [],
        rule: step.config.rule || 'any',
        summary: { approvers: asked, rule: step.config.rule || 'any' },
        label: t('workflow.describe.askApproval', null, { count: asked }),
      };
    }
    case 'python':
      return { type: 'python', summary: {}, label: t('workflow.describe.python', null, { step: step.id }) };
    case 'run-workflow':
      return { type: 'run-workflow', workflowId: step.config.workflowId, summary: { workflowId: step.config.workflowId }, label: t('workflow.describe.startWorkflow', null, { workflow: step.config.workflowId }) };
    default:
      return { type: step.type, summary: {}, label: t('workflow.describe.runStep', null, { type: step.type, step: step.id }) };
  }
}

// --- driver ---------------------------------------------------------------

/**
 * Execute a run until it finishes, fails or parks.
 *
 * Call it to start a run and call it again unchanged to resume one — there is
 * no separate resume path, because "resume" is just "execute with a journal
 * that already has entries in it". That equivalence is the whole point of the
 * design: the code that survives a crash is the code that runs normally, so it
 * cannot rot from disuse.
 *
 * @returns {Promise<{ run, status, changes, suspension? }>}
 */
export async function executeRun(workflowDefinition, run, deps = {}) {
  const workflow = normalizeWorkflow(workflowDefinition);
  // A code, not a sentence — the reader is the developer who forgot the dependency.
  if (!deps.store) throw new Error('executeRun-requires-deps.store');

  const ex = new Executor(workflow, run, deps);

  try {
    // The prologue is INSIDE the try because its flush is the most likely
    // place to discover another worker already owns this run — two sweepers
    // picking up the same due run collide on exactly this write. Outside the
    // try, that surfaced as an unhandled StaleWrite instead of the `conflict`
    // result the caller is documented to get.
    if (run.status === 'pending') {
      ex.record('run-started', { at: ex.now() });
      ex.commit.setHeader({ status: 'running', startedAt: run.startedAt ?? ex.now(), metered: 1 });
      await ex.flush();
    } else if (run.status === 'suspended' || run.status === 'paused') {
      ex.record('run-resumed', { at: ex.now() });
      ex.commit.setHeader({ status: 'running', waiting: null });
      await ex.flush();
    }

    // Rebuild context as completed steps are visited, in program order. A
    // global preload leaks later assignments into an earlier unfinished step.
    await execSteps(workflow.steps, ex, []);
    ex.assertControl();
    ex.record('run-completed', { at: ex.now() });
    ex.commit.setHeader({ status: 'succeeded', finishedAt: ex.now(), waiting: null });
    await ex.flush();
    return { run: ex.run, status: 'succeeded', changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [] };
  } catch (error) {
    if (error instanceof Suspension) {
      // A pause is a suspension with no wakeup condition: nothing schedules it
      // back, a person does. Recording it as `suspended` would let the timer
      // sweeper resume a run an operator deliberately stopped.
      const paused = error.wait.kind === 'paused';
      // Timer and signal waits already journaled themselves in the step that
      // raised them; adding a second entry here would double-count them in
      // the run log and in any metric derived from it.
      if (paused) ex.record('run-paused', { at: ex.now() });
      ex.commit.setHeader(paused
        ? { status: 'paused', pauseRequested: false, waiting: error.wait }
        : { status: 'suspended', waiting: error.wait });
      await ex.flush();
      return { run: ex.run, status: paused ? 'paused' : 'suspended', changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [], suspension: error.wait };
    }

    if (error instanceof CancelRun) {
      ex.record('run-cancelled', { at: ex.now(), reason: error.message });
      ex.commit.setHeader({ status: 'cancelled', finishedAt: ex.now(), waiting: null, cancelRequested: false });
      await ex.flush();
      return { run: ex.run, status: 'cancelled', changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [], reason: error.message };
    }
    if (error instanceof StopRun) {
      ex.record('run-completed', { at: ex.now(), reason: error.message });
      ex.commit.setHeader({ status: 'succeeded', finishedAt: ex.now(), waiting: null });
      await ex.flush();
      return { run: ex.run, status: 'succeeded', changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [], stopped: error.message };
    }
    if (error instanceof StaleWrite) {
      // Another worker owns this run. Do not touch the header: it is theirs.
      return { run: ex.run, status: 'conflict', changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [], reason: error.message };
    }
    const message = error && error.message ? error.message : String(error);
    const details = (error && error.details) || {};
    ex.record('run-failed', { at: ex.now(), error: message, ...(details.stepId ? { stepId: details.stepId } : {}), ...(details.reason ? { reason: details.reason } : {}) });
    ex.commit.setHeader({ status: 'failed', finishedAt: ex.now(), error: message, waiting: null });
    await ex.flush().catch(() => undefined);
    return {
      run: ex.run,
      status: 'failed',
      changes: ex.changes, uncheckedHosts: ex.uncheckedHosts || [],
      error: message,
      ...(details.reason ? { reason: details.reason, budget: { reason: details.reason, kind: 'step-budget', budget: details.budget } } : {}),
    };
  }
}
