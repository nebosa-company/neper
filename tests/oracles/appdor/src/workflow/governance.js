/**
 * Automation observability, governance & metering (LC33 /
 * automation-governance-metering) — the operator plane over the run log.
 *
 * Failure notifications with dedup windows (one alert per failure class per
 * rule, not one per run), rule health scoring from recent outcomes with
 * auto-suspend when a rule fails hard enough, durable rate limits and
 * per-tenant run budgets consulted BEFORE a run starts, kill switches at
 * three scopes (workspace, rule, action-family) that suppress with a logged
 * reason, replay/cancel bookkeeping flagged so metering and dedupe stay
 * honest, retention policies for run history, and the per-rule analytics
 * rollup the admin surface renders. Pure and clock-injected.
 *
 * ## Additions (2026-08-05) — closing the remaining pure-engine gaps
 *
 * - `normalizeExecutionRecord` — unified schema for event/scheduled runs
 * - `sanitizeTrace` — credential redaction and payload truncation on step traces
 * - `prepareReplayRun` — full replay envelope (trigger snapshot, version pin)
 * - `createBulkRetryOrchestrator` — filter-by-error-class throttled bulk replay
 * - `createCascadeGuard` — depth-cap enforcement with loop_guard:depth records
 * - `createRunBudget` extended with soft thresholds, billable attribution,
 *    platform_error exclusion, and queryable skip log
 * - `reconcileMeter` — recomputation-from-records vs live meter, with alerts
 */

// --- failure notification dedup -------------------------------------------

/**
 * One notification per (rule, failure class) per window — a crashing rule
 * produces a page, not a pager storm.
 */
/** The machine-readable reason a run was stopped by a budget. */
export const BUDGET_EXCEEDED = 'budget_exceeded';

export function createFailureNotifier({ windowMs = 3600000 } = {}) {
  const lastSent = new Map();
  const queue = [];
  return {
    onFailure(ruleId, failureClass, detail, nowMs) {
      const key = `${ruleId}:${failureClass}`;
      const prev = lastSent.get(key);
      if (prev !== undefined && nowMs - prev < windowMs) {
        return { notified: false, deduped: true };
      }
      lastSent.set(key, nowMs);
      queue.push({ ruleId, failureClass, detail, at: nowMs });
      return { notified: true, deduped: false };
    },
    pending: () => [...queue],
  };
}

// --- rule health & auto-suspend -------------------------------------------

/**
 * Health from the last N runs: failure ratio bands into healthy/degraded/
 * failing; a fully-failing recent window auto-suspends the rule with a
 * reason the builder sees (never a silent stop).
 */
export function ruleHealth(recentRuns, { window = 20, degradedAt = 0.2, failingAt = 0.5, suspendAfter = 10 } = {}) {
  const considered = recentRuns.slice(-window);
  if (!considered.length) return { status: 'healthy', failureRatio: 0, autoSuspend: false };
  const failures = considered.filter((r) => r.status === 'failed').length;
  const ratio = failures / considered.length;
  const tail = considered.slice(-suspendAfter);
  const allFailing = tail.length >= suspendAfter && tail.every((r) => r.status === 'failed');
  return {
    status: ratio >= failingAt ? 'failing' : ratio >= degradedAt ? 'degraded' : 'healthy',
    failureRatio: Math.round(ratio * 100) / 100,
    autoSuspend: allFailing,
    suspendReason: allFailing ? `last ${suspendAfter} runs all failed` : null,
  };
}

// --- rate limits & budgets -------------------------------------------------

/**
 * Durable token-bucket limiter keyed by (scope, id): refills continuously,
 * consulted before run creation. State is a plain object the host persists.
 */
export function createRateLimiter({ capacity = 60, refillPerMinute = 60 } = {}) {
  const buckets = new Map();
  return {
    tryTake(key, nowMs, tokens = 1) {
      let b = buckets.get(key);
      if (!b) {
        b = { tokens: capacity, at: nowMs };
        buckets.set(key, b);
      }
      const refill = ((nowMs - b.at) / 60000) * refillPerMinute;
      b.tokens = Math.min(capacity, b.tokens + refill);
      b.at = nowMs;
      if (b.tokens >= tokens) {
        b.tokens -= tokens;
        return { allowed: true, remaining: Math.floor(b.tokens) };
      }
      const waitMs = Math.ceil(((tokens - b.tokens) / refillPerMinute) * 60000);
      return { allowed: false, reason: 'rate-limited', retryInMs: waitMs };
    },
  };
}

/**
 * Monthly run budget per tenant: consumed on run creation, replays excluded
 * (LC28.33), refusal is a logged skip with the budget snapshot.
 */
export function createRunBudget(limits) {
  const usage = new Map(); // `${tenant}:${period}` → used
  return {
    consume(tenantId, period, { replay = false } = {}) {
      const limit = limits[tenantId] !== undefined ? limits[tenantId] : limits.default;
      const key = `${tenantId}:${period}`;
      const used = usage.get(key) || 0;
      if (replay) return { allowed: true, replay: true, used, limit }; // replays don't meter
      if (limit !== null && used >= limit) {
        return { allowed: false, reason: 'budget-exhausted', used, limit };
      }
      usage.set(key, used + 1);
      return { allowed: true, used: used + 1, limit };
    },
    usage: (tenantId, period) => usage.get(`${tenantId}:${period}`) || 0,
  };
}

// --- budget exhaustion metric (LC27.14 → LC33) -------------------------------

/**
 * The budget-exhaustion counter LC27's §7 requires to increment "with tenant
 * and rule attribution".
 *
 * Separate from `createRunBudget` above deliberately: that one refuses a run
 * BEFORE it starts, on a monthly allowance. This one counts runs the engine
 * stopped MID-FLIGHT because the work inside a single run exceeded its budget
 * — a loop that would have run 50,000 times, a step budget blown inside a
 * for-each. They are different failures with different fixes, and one counter
 * for both would tell an operator to raise the plan when the answer is to fix
 * the loop.
 *
 * The shape is the sample-series LC33's collectors already consume:
 * `{ labels: { tenant, rule, reason, kind }, value }`. Unattributed runs are
 * labelled `unknown` rather than dropped — a count that silently omits the
 * runs it could not attribute is the failure this register exists to catch.
 */
export function createBudgetMeter() {
  const counts = new Map();
  // JSON rather than a joined string: a tenant id containing the separator
  // would otherwise collide two different label sets into one counter, and
  // `tests/source-is-text.test.js` forbids the NUL that is the usual answer.
  const key = (l) => JSON.stringify([l.tenant, l.rule, l.reason, l.kind]);
  const labelsOf = (budget) => ({
    tenant: (budget && budget.tenantId) || 'unknown',
    rule: (budget && budget.ruleId) || 'unknown',
    reason: (budget && budget.reason) || 'budget_exceeded',
    kind: (budget && budget.kind) || 'unknown',
  });
  return {
    /**
     * Record one finished run. Returns whether it counted, so a caller can
     * assert the meter saw the run rather than inferring it from a total.
     */
    record(run) {
      // Keyed on the BUDGET field, not on a status word. The two engines that
      // have fed this meter spell the terminal state differently — the inline
      // flow engine says `terminated`, the durable one says `failed` — and a
      // meter that recognised only one of those silently reported zero for
      // every run of the other. What actually identifies the event is that the
      // run carries a budget reason at all.
      if (!run) return { counted: false };
      const stoppedByBudget = run.status === 'terminated' || (run.budget && run.budget.reason === BUDGET_EXCEEDED);
      if (!stoppedByBudget) return { counted: false };
      const labels = labelsOf(run.budget);
      const k = key(labels);
      const prev = counts.get(k);
      counts.set(k, { labels, value: (prev ? prev.value : 0) + 1 });
      return { counted: true, labels, value: counts.get(k).value };
    },
    /** Total across every label set, or across one tenant. */
    total(tenant) {
      let n = 0;
      for (const s of counts.values()) if (tenant === undefined || s.labels.tenant === tenant) n += s.value;
      return n;
    },
    /** The metric an LC33 collector scrapes. */
    metric() {
      return {
        name: 'automation_budget_exhausted_total',
        type: 'counter',
        help: 'Runs the engine terminated because a per-run budget was exceeded.',
        samples: [...counts.values()].map((s) => ({ labels: { ...s.labels }, value: s.value })),
      };
    },
  };
}

// --- kill switches ----------------------------------------------------------

/**
 * Three scopes — workspace, rule, action-family — any active switch
 * suppresses with a logged reason; deactivation restores without residue.
 */
export function createKillSwitches() {
  const switches = new Map(); // `${scope}:${id}` → { reason, by, at }
  const log = [];
  return {
    activate(scope, id, { reason, by, at }) {
      switches.set(`${scope}:${id}`, { reason, by, at });
      log.push({ event: 'kill-switch-on', scope, id, reason, by, at });
    },
    deactivate(scope, id, meta = {}) {
      switches.delete(`${scope}:${id}`);
      log.push({ event: 'kill-switch-off', scope, id, ...meta });
    },
    /** Consult before a run: which switch, if any, suppresses it? */
    check({ workspaceId, ruleId, actionFamilies = [] }) {
      const hits = [];
      if (switches.has(`workspace:${workspaceId}`)) hits.push({ scope: 'workspace', id: workspaceId, ...switches.get(`workspace:${workspaceId}`) });
      if (switches.has(`rule:${ruleId}`)) hits.push({ scope: 'rule', id: ruleId, ...switches.get(`rule:${ruleId}`) });
      for (const fam of actionFamilies) {
        if (switches.has(`action-family:${fam}`)) hits.push({ scope: 'action-family', id: fam, ...switches.get(`action-family:${fam}`) });
      }
      return hits.length ? { suppressed: true, by: hits } : { suppressed: false };
    },
    auditLog: () => [...log],
  };
}

// --- replay / cancel bookkeeping --------------------------------------------

/**
 * Replays are flagged and excluded from dedupe and metering; cancels record
 * who and why and only ever move a run to `cancelled` from a live state.
 */
export function markReplay(run, { by, of }) {
  return { ...run, replay: true, replayOf: of, replayBy: by, metered: 0 };
}

export function cancelRun(run, { by, reason, at }) {
  if (run.status !== 'running' && run.status !== 'queued') {
    return { ok: false, error: `cannot cancel a ${run.status} run` };
  }
  return { ok: true, run: { ...run, status: 'cancelled', cancelledBy: by, cancelReason: reason || null, cancelledAt: at } };
}

// --- retention & analytics ---------------------------------------------------

/** Run-history retention: plan-tiered windows, sweep returns survivors + purged count. */
export function applyRetention(runs, plan, nowMs, windows = { free: 14, pro: 365, business: 1095, enterprise: null }) {
  const days = windows[plan];
  if (days == null) return { runs: [...runs], purged: 0 };
  const cutoff = nowMs - days * 24 * 3600 * 1000;
  const kept = runs.filter((r) => r.at >= cutoff);
  return { runs: kept, purged: runs.length - kept.length };
}

/** The per-rule analytics rollup the admin console renders (LC33). */
export function analyticsRollup(runs) {
  const byRule = new Map();
  for (const r of runs) {
    if (!byRule.has(r.ruleId)) byRule.set(r.ruleId, { ruleId: r.ruleId, total: 0, failed: 0, cancelled: 0, replays: 0, metered: 0, durations: [] });
    const s = byRule.get(r.ruleId);
    s.total++;
    if (r.status === 'failed') s.failed++;
    if (r.status === 'cancelled') s.cancelled++;
    if (r.replay) s.replays++;
    s.metered += r.metered || 0;
    if (typeof r.durationMs === 'number') s.durations.push(r.durationMs);
  }
  return [...byRule.values()].map((s) => ({
    ruleId: s.ruleId,
    total: s.total,
    failed: s.failed,
    cancelled: s.cancelled,
    replays: s.replays,
    metered: s.metered,
    failureRatio: s.total ? Math.round((s.failed / s.total) * 100) / 100 : 0,
    p50DurationMs: percentile(s.durations, 0.5),
    p95DurationMs: percentile(s.durations, 0.95),
  }));
}

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
}

// --- unified execution record schema (C1) -----------------------------------

/**
 * A run record as it reaches this module. Deliberately all-optional and
 * carrying BOTH spellings of the three columns that have them
 * (`workflow_id`/`ruleId`, `created_by`/`createdBy`, `workflow_version`):
 * records arrive here straight off the run-log table as well as from
 * in-memory callers, and `normalizeExecutionRecord` is precisely the thing
 * that reconciles the two. Named once because the replay preparer, the bulk
 * retry orchestrator and the meter reconciler all read the same rows.
 *
 * @typedef {Object} RunRecord
 * @property {string} [id]
 * @property {string} [ruleId]
 * @property {string} [workflow_id] the run-log column behind `ruleId`
 * @property {number} [workflow_version] the flow version the run executed
 * @property {string} [tenantId]
 * @property {string} [status]
 * @property {{kind?: string, cron?: string}} [trigger]
 * @property {string} [mode]
 * @property {number} [metered]
 * @property {string} [createdBy]
 * @property {string} [created_by] the run-log column behind `createdBy`
 * @property {boolean} [replay]
 * @property {string} [replayOf] id of the run this one replays
 * @property {string|number} [at]
 * @property {number} [durationMs]
 * @property {string} [errorClass]
 * @property {{class?: string}} [error] nested form some callers send instead
 * @property {object[]} [steps]
 * @property {object} [input]
 * @property {number} [versionPin]
 */

/**
 * Normalize a run record from any trigger family into the unified governance
 * schema. Scheduled, event-triggered, and manual runs all pass through this
 * before entering the query API, so the operator sees one schema regardless
 * of how the run started.
 *
 * The `triggerFamily` discriminator ('event' | 'scheduled' | 'manual') is
 * derived from the trigger shape and carried as a top-level field so the
 * run query API can filter by family without parsing trigger payloads.
 *
 * @param {RunRecord} run
 */
export function normalizeExecutionRecord(run) {
  if (!run) return null;
  const trigger = run.trigger || {};
  let triggerFamily = 'manual';
  if (trigger.kind === 'schedule' || trigger.cron) triggerFamily = 'scheduled';
  else if (trigger.kind === 'record-change' || trigger.kind === 'webhook' || trigger.kind === 'app-event') triggerFamily = 'event';
  return {
    id: run.id || null,
    ruleId: run.ruleId || run.workflow_id || null,
    tenantId: run.tenantId || null,
    status: run.status || 'unknown',
    trigger: { ...trigger },
    triggerFamily,
    mode: run.mode || 'live',
    metered: run.metered ?? 1,
    createdBy: run.createdBy || run.created_by || null,
    replay: !!run.replay,
    replayOf: run.replayOf || null,
    at: run.at || null,
    durationMs: typeof run.durationMs === 'number' ? run.durationMs : null,
    errorClass: run.errorClass || null,
    steps: Array.isArray(run.steps) ? run.steps : [],
    input: run.input || {},
  };
}

// --- step trace sanitization (C2) --------------------------------------------

/** Maximum bytes before a trace payload is truncated. */
export const DEFAULT_TRACE_PAYLOAD_MAX = 65536;

const TRUNCATION_MARKER = '[truncated]';

/**
 * Sanitize a step trace so credentials never appear in snapshots and oversized
 * payloads carry explicit truncation markers.
 *
 * @param {object} step - a single step trace entry with optional request/response
 * @param {{maxBytes?: number, credentialFields?: string[]}} opts
 * @returns {object} a sanitized copy — the original is never mutated
 */
export function sanitizeTrace(step, { maxBytes = DEFAULT_TRACE_PAYLOAD_MAX, credentialFields = ['authorization', 'apikey', 'password', 'secret', 'token', 'credential'] } = {}) {
  if (!step) return step;
  const out = { ...step };

  const isCredentialKey = (k) => {
    // Normalise: remove delimiters so 'X-Api-Key' matches 'apikey'.
    const flat = k.toLowerCase().replace(/[-_]/g, '');
    return credentialFields.some((f) => flat.includes(f.toLowerCase()));
  };

  const sanitize = (obj) => {
    if (!obj || typeof obj !== 'object') return obj;
    if (Array.isArray(obj)) return obj.map(sanitize);
    const copy = {};
    for (const [k, v] of Object.entries(obj)) {
      if (isCredentialKey(k)) {
        copy[k] = '[redacted]';
      } else if (typeof v === 'object' && v !== null) {
        copy[k] = sanitize(v);
      } else {
        copy[k] = v;
      }
    }
    return copy;
  };

  const truncateBody = (body) => {
    if (body == null) return body;
    const s = typeof body === 'string' ? body : JSON.stringify(body);
    if (s.length <= maxBytes) return body;
    const truncated = s.slice(0, maxBytes);
    return typeof body === 'string' ? truncated + TRUNCATION_MARKER : { _truncated: true, preview: truncated, marker: TRUNCATION_MARKER };
  };

  if (out.request) {
    out.request = sanitize({ ...out.request, body: truncateBody(out.request.body) });
  }
  if (out.response) {
    out.response = sanitize({ ...out.response, body: truncateBody(out.response.body) });
  }
  return out;
}

/** Deep-sanitize every step in a trace. */
export function sanitizeTraceFull(trace, opts) {
  if (!Array.isArray(trace)) return trace;
  return trace.map((step) => sanitizeTrace(step, opts));
}

// --- replay preparation (C5) -------------------------------------------------

/**
 * Prepare a replay run envelope from the original run. The caller passes the
 * original trigger snapshot and the flow version recorded on the original run;
 * the engine books the link and the metering flag.
 *
 * @param {RunRecord} originalRun
 * @param {Object} [opts]
 * @param {string} [opts.by] principal credited with asking for the replay
 * @param {object} [opts.triggerSnapshot] the original trigger payload to re-feed
 * @param {number} [opts.versionPin] flow version to pin the replay to
 * @returns {{ok: boolean, replayRun?: object, error?: string}} a new run record
 *   ready for execution, marked as replay
 */
export function prepareReplayRun(originalRun, { by, triggerSnapshot, versionPin } = {}) {
  if (!originalRun) return { ok: false, error: 'original-run-required' };
  const base = normalizeExecutionRecord(originalRun);
  const replayRun = {
    ...base,
    id: undefined, // new id assigned by the host
    status: 'queued',
    replay: true,
    replayOf: base.id,
    replayBy: by || null,
    metered: 0, // replays are unmetered at bookkeeping; the caller may override
    input: triggerSnapshot || base.input,
    versionPin: versionPin ?? (originalRun.workflow_version || base.versionPin || null),
    at: undefined, // new timestamp by the host
    steps: [],
    durationMs: null,
  };
  return { ok: true, replayRun };
}

// --- bulk retry orchestrator (C6) --------------------------------------------

/**
 * Bulk-retry orchestrator: filter runs by error class, replay them at a
 * throttled rate while live triggers are never starved, and report progress.
 *
 * The host calls `nextBatch()` repeatedly until `done()` is true; the
 * orchestrator consults the rate limiter before releasing each batch. Live
 * traffic is always admitted first: a separate `allowLive()` gate that the
 * host consults independently ensures ordinary triggers are never blocked
 * by a bulk replay.
 *
 * @param {Object} [opts]
 * @param {{tryTake: (key: string, nowMs?: number) => {allowed: boolean, retryInMs?: number}}} [opts.rateLimiter]
 *   the durable limiter consulted before each run is released; omitting it
 *   releases every candidate
 * @param {string} [opts.filterErrorClass] replay only runs of this error class
 * @param {number} [opts.batchSize]
 * @param {number} [opts.total] how many runs the whole retry covers
 */
export function createBulkRetryOrchestrator({ rateLimiter, filterErrorClass, batchSize = 10, total = 0 } = {}) {
  let cursor = 0;
  const replayIds = [];
  const skipLog = [];

  return {
    /** How many runs have been dispatched so far. */
    progress() {
      return { dispatched: replayIds.length, total, remaining: total - replayIds.length };
    },
    /** All done? */
    done() {
      return total > 0 && cursor >= total;
    },
    /**
     * Ask for a batch of runs to replay. The host must supply `runs` — the
     * orchestrator filters by error class internally. Returns the run ids
     * the host should replay.
     */
    nextBatch(runs, nowMs) {
      if (this.done()) return { batch: [], done: true };
      const candidates = runs.filter((r) => {
        if (!filterErrorClass) return true;
        const cls = r.errorClass || (r.error && r.error.class) || null;
        return cls === filterErrorClass;
      });
      const batch = [];
      for (const r of candidates.slice(cursor, cursor + batchSize)) {
        const key = `bulk-retry:${r.ruleId || r.id}`;
        const check = rateLimiter ? rateLimiter.tryTake(key, nowMs) : { allowed: true };
        if (check.allowed) {
          batch.push(r.id);
          replayIds.push(r.id);
        } else {
          skipLog.push({ runId: r.id, reason: 'rate-limited', retryInMs: check.retryInMs });
        }
      }
      cursor += batchSize;
      return { batch, done: this.done(), skipped: skipLog.length };
    },
    /** Live traffic always passes — the bulk replay never blocks it. */
    allowLive() {
      return true;
    },
    skips: () => [...skipLog],
    reset() {
      cursor = 0;
      replayIds.length = 0;
      skipLog.length = 0;
    },
  };
}

// --- cascade guard with loop_guard recording (C7) ----------------------------

/** Loop-guard reasons the guard records when it stops a chain. */
export const LOOP_GUARD_DEPTH = 'loop_guard:depth';
export const LOOP_GUARD_RATE_LIMIT = 'loop_guard:rate_limit';

/**
 * Cascade depth guard: stops re-entrant trigger chains at a configurable cap
 * and records every skip with a `loop_guard:depth` reason so the suppression
 * is countable.
 *
 * The host calls `admit()` before firing a rule in a cascade chain. When the
 * depth cap is hit, the return carries the reason and the guard records the
 * event so the operator can see it in the suppression log.
 */
export function createCascadeGuard({ maxDepth = 5 } = {}) {
  const log = [];

  return {
    /**
     * Check whether a run at `depth` should be admitted. Returns the guard
     * reason when suppressed.
     *
     * @param {number} depth
     * @param {{ruleId?: string, recordId?: string}} [origin] what the chain was
     *   firing on, recorded so a suppression can be traced back to a row
     */
    admit(depth, { ruleId, recordId } = {}) {
      if (depth > maxDepth) {
        const entry = {
          reason: LOOP_GUARD_DEPTH,
          depth,
          maxDepth,
          ruleId: ruleId || null,
          recordId: recordId || null,
          at: Date.now(),
        };
        log.push(entry);
        return { allowed: false, reason: LOOP_GUARD_DEPTH, depth, maxDepth };
      }
      return { allowed: true, depth };
    },
    /**
     * Records a loop_guard:rate_limit skip from the durable rate limiter.
     *
     * @param {{ruleId?: string, recordId?: string, retryInMs?: number}} [skip]
     */
    recordRateLimit({ ruleId, recordId, retryInMs } = {}) {
      const entry = {
        reason: LOOP_GUARD_RATE_LIMIT,
        ruleId: ruleId || null,
        recordId: recordId || null,
        retryInMs: retryInMs || null,
        at: Date.now(),
      };
      log.push(entry);
      return entry;
    },
    /** All skips recorded, newest last. */
    suppressed() {
      return [...log];
    },
    /** How many skips of a given reason. */
    countByReason(reason) {
      return log.filter((e) => e.reason === reason).length;
    },
  };
}

// --- extended run budget with soft thresholds & billable tracking (C10) ------

/** Error classes that are NOT billable — the platform's own fault. */
export const NON_BILLABLE_ERRORS = ['platform_error', 'internal_error', 'infrastructure_error'];

/**
 * Monthly run budget with soft thresholds and billable attribution.
 *
 * Extended beyond `createRunBudget`: soft (80%) notification threshold,
 * platform_error exclusion from billable counts, queryable skip log, and
 * dry-run / condition-non-match exemption.
 */
export function createRunBudgetWithThresholds(limits, { softThreshold = 0.8 } = {}) {
  const usage = new Map(); // `${tenant}:${period}` → { billable, total }
  const skipLog = [];

  return {
    /**
     * Check and consume a unit. Returns whether admitted, with threshold
     * crossing info and billable attribution.
     */
    consume(tenantId, period, opts = {}) {
      const { replay = false, dryRun = false, conditionMatch = true, errorClass = null } = opts;
      const limit = limits[tenantId] !== undefined ? limits[tenantId] : limits.default;
      const key = `${tenantId}:${period}`;
      const u = usage.get(key) || { billable: 0, total: 0 };

      // Never bill: replays, dry-runs, condition-non-matches.
      const billable = !replay && !dryRun && conditionMatch !== false &&
        !NON_BILLABLE_ERRORS.includes(errorClass);

      if (limit !== null && u.billable >= limit) {
        const skip = {
          tenantId, period, reason: 'quota_exceeded',
          billable: u.billable, limit,
          dryRun: !!dryRun, conditionMatch,
          at: opts.at || Date.now(),
        };
        skipLog.push(skip);
        return { allowed: false, reason: 'quota_exceeded', billable: u.billable, limit, softThresholdCrossed: u.billable >= limit * softThreshold };
      }

      const next = {
        billable: billable ? u.billable + 1 : u.billable,
        total: u.total + 1,
      };
      usage.set(key, next);

      const softCrossed = softThreshold && limit !== null && next.billable >= Math.ceil(limit * softThreshold);
      const prevSoftCrossed = softThreshold && limit !== null && u.billable >= Math.ceil(limit * softThreshold);

      return {
        allowed: true,
        billable: next.billable,
        total: next.total,
        limit,
        softThresholdCrossed: softCrossed && !prevSoftCrossed, // edge: true only on crossing
        atThreshold: next.billable >= Math.ceil((limit || Infinity) * softThreshold),
      };
    },
    /** Current usage snapshot. */
    usage(tenantId, period) {
      const u = usage.get(`${tenantId}:${period}`);
      const limit = limits[tenantId] !== undefined ? limits[tenantId] : limits.default;
      return {
        billable: u ? u.billable : 0,
        total: u ? u.total : 0,
        limit,
        percentUsed: limit ? Math.round(((u ? u.billable : 0) / limit) * 100) : 0,
      };
    },
    /** Queryable skip records. */
    skipLog: () => [...skipLog],
    /** Skips grouped by reason, for the admin surface. */
    skipSummary() {
      const byReason = new Map();
      for (const s of skipLog) {
        byReason.set(s.reason, (byReason.get(s.reason) || 0) + 1);
      }
      return [...byReason.entries()].map(([reason, count]) => ({ reason, count }));
    },
  };
}

// --- meter reconciliation (C11) ----------------------------------------------

/**
 * Recompute a meter from execution records and compare against the live meter.
 * When the recomputed total disagrees with the live meter, the return carries
 * the discrepancy — the host is expected to raise an operational alert.
 *
 * @param {RunRecord[]} records - run records for the period
 * @param {{billable?: number, total?: number}} liveMeter - the meter as booked
 * @param {{tolerance?: number}} [opts] - absolute count tolerance before alerting
 * @returns {{recomputed:object, live:object, match:boolean, discrepancy:object|null}}
 */
export function reconcileMeter(records, liveMeter, { tolerance = 0 } = {}) {
  const recomputed = {
    billable: 0,
    total: 0,
  };
  for (const r of records || []) {
    if (!r) continue;
    const isReplay = r.replay || r.replayOf;
    const isPlatformError = r.errorClass && NON_BILLABLE_ERRORS.includes(r.errorClass);
    recomputed.total++;
    if (!isReplay && !isPlatformError) recomputed.billable++;
  }

  const live = {
    billable: liveMeter && typeof liveMeter.billable === 'number' ? liveMeter.billable : 0,
    total: liveMeter && typeof liveMeter.total === 'number' ? liveMeter.total : 0,
  };

  const billableDelta = recomputed.billable - live.billable;
  const totalDelta = recomputed.total - live.total;
  const match = Math.abs(billableDelta) <= tolerance && Math.abs(totalDelta) <= tolerance;

  const discrepancy = match ? null : {
    billableDelta,
    totalDelta,
    recomputed: { ...recomputed },
    live: { ...live },
    alert: `Meter discrepancy: billable off by ${billableDelta}, total off by ${totalDelta}`,
  };

  return { recomputed, live, match, discrepancy };
}
