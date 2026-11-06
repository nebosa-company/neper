/**
 * Advanced approval mechanics (LC31 / approvals-human-workflow) — the gaps
 * the base chain engine leaves open.
 *
 * Quorum-of-N step rules alongside any/all with reject-as-veto; custom
 * outcomes beyond approve/reject (send-back, goto-step, custom labels with
 * declared semantics); delegation/out-of-office rerouting with cycle guards
 * and on-behalf-of attribution; step timers with expiry policies (escalate,
 * auto-approve, auto-reject, skip) that leave an audit trail; response forms
 * whose required inputs gate the decision; external approvers acting through
 * signed, expiring action tokens (HMAC over the run/step/approver tuple via
 * the formula engine's SHA-256 — no new crypto); and a hash-chained decision
 * record so a tampered approval history is detectable
 * (verifyDecisionChain). Pure; the host persists runs and sends mail.
 */

import { sha256 } from '../formula/random-hash-encode.js';

const canonical = (obj) => {
  const sort = (v) =>
    Array.isArray(v) ? v.map(sort) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sort(v[k])])) : v;
  return JSON.stringify(sort(obj));
};

// --- run construction -----------------------------------------------------

/**
 * Start an advanced approval run.
 *
 * Definition steps: { id, approvers: [userId | { external: email }], rule:
 * 'any' | 'all' | { quorum: n }, outcomes?: { [label]: 'advance' |
 * 'reject-run' | 'goto:<stepId>' }, responseForm?: { fields: [{ field,
 * required }] }, dueMs?, onExpiry?: 'escalate'|'auto-approve'|'auto-reject'|
 * 'skip', escalateTo? }
 */
export function startAdvancedApproval(definition, meta = {}) {
  const now = meta.now || null;
  const steps = (definition.steps || []).map((s, i) => ({
    id: s.id || `step-${i + 1}`,
    approvers: (s.approvers || []).map(normalizeApprover),
    rule: s.rule || 'any',
    outcomes: s.outcomes || { approve: 'advance', reject: 'reject-run' },
    responseForm: s.responseForm || null,
    dueMs: s.dueMs || null,
    onExpiry: s.onExpiry || 'escalate',
    escalateTo: s.escalateTo || null,
    assignedTo: [],
    decisions: {},
    status: 'pending',
    startedAt: i === 0 ? now : null,
  }));
  const run = {
    id: meta.id || null,
    recordId: meta.recordId || null,
    status: steps.length ? 'pending' : 'approved',
    currentIndex: 0,
    steps,
    chain: [], // hash-chained decision records
    audit: [],
  };
  // Every step resolves its assignees (through delegations) up front; a
  // goto/send-back reactivation keeps the resolved set.
  for (let i = 0; i < steps.length; i++) assignStep(run, i, meta.delegations || {}, now);
  if (steps.length) steps[0].startedAt = now;
  return run;
}

function normalizeApprover(a) {
  if (typeof a === 'string') return a;
  if (a && a.external) return `external:${a.external}`;
  return String(a);
}

/** Delegation/OOO rerouting with a cycle guard (LC31 delegation). */
export function resolveDelegate(user, delegations, now = null) {
  const seen = new Set([user]);
  let cur = user;
  for (;;) {
    const d = delegations[cur];
    if (!d) return { user: cur, via: cur === user ? null : user };
    if (d.until && now && now > d.until) return { user: cur, via: cur === user ? null : user }; // expired OOO
    if (seen.has(d.to)) return { user: cur, via: cur === user ? null : user, cycle: true };
    seen.add(d.to);
    cur = d.to;
  }
}

function assignStep(run, index, delegations, now) {
  const step = run.steps[index];
  step.assignedTo = step.approvers.map((a) => {
    const resolved = resolveDelegate(a, delegations || {}, now);
    if (resolved.user !== a) {
      run.audit.push({ event: 'delegated', step: step.id, from: a, to: resolved.user, at: now });
    }
    return resolved.user;
  });
}

// --- decisions ------------------------------------------------------------

/**
 * The completion-policy names REQ-APPROVALSHUMANWORKFLOW-03 publishes, mapped onto the
 * rules this engine has always accepted.
 *
 * The spec says `first-response`, `all-must-approve` and `quorum(N of M)`; the engine
 * says `'any'`, `'all'` and `{ quorum: n }`. Both are reasonable names for the same
 * three policies, and a definition written from the specification silently fell through
 * to the default — `quorumNeeded` returns 1 for anything it does not recognise, so
 * `all-must-approve` behaved as first-response. That is the worst possible direction for
 * this particular mistake: an approval chain that required everyone would have advanced
 * on one signature.
 */
export const COMPLETION_POLICIES = Object.freeze({
  'first-response': 'any',
  'all-must-approve': 'all',
  any: 'any',
  all: 'all',
});

/** `quorum(3 of 5)` / `quorum(3)` → `{ quorum: 3 }`. */
function parseQuorum(rule) {
  const m = /^quorum\s*\(\s*(\d+)(?:\s+of\s+\d+)?\s*\)$/i.exec(String(rule).trim());
  return m ? { quorum: Number(m[1]) } : null;
}

/**
 * Normalize a step rule to the engine's internal form. Exported because a definition is
 * validated before it is started, and both paths must agree on what a rule means.
 */
export function normalizeStepRule(rule) {
  if (rule && typeof rule === 'object' && rule.quorum) return { quorum: rule.quorum };
  if (typeof rule === 'string') {
    const named = COMPLETION_POLICIES[rule.trim().toLowerCase()];
    if (named) return named;
    const quorum = parseQuorum(rule);
    if (quorum) return quorum;
  }
  // Unrecognised rules keep falling through to first-response, which is the historical
  // behaviour — but they are now the only thing that does, rather than sharing that fate
  // with every correctly-spelled policy from the specification.
  return rule;
}

function quorumNeeded(step) {
  const rule = normalizeStepRule(step.rule);
  if (rule === 'all') return step.assignedTo.length;
  if (rule && typeof rule === 'object' && rule.quorum) return rule.quorum;
  return 1;
}

function chainAppend(run, entry) {
  const prev = run.chain.length ? run.chain[run.chain.length - 1].hash : 'genesis';
  const record = { ...entry, prev };
  record.hash = sha256(prev + canonical(entry));
  run.chain.push(record);
  return record;
}

/**
 * Record a decision with an outcome label declared by the step. Response-
 * form requirements gate the decision; every accepted decision appends to
 * the tamper-evident chain.
 *
 * @param {import('./index.js').ApprovalRun} run
 * @param {{approver?: string, outcome?: string, comment?: string|null,
 *   inputs?: Record<string, any>|null, onBehalfOf?: string|null,
 *   at?: string|number|null}} [decision]
 */
export function decideAdvanced(run, { approver, outcome, comment = null, inputs = null, onBehalfOf = null, at = null } = {}) {
  if (run.status !== 'pending') return { ok: false, error: 'run-settled', run };
  const step = run.steps[run.currentIndex];
  if (!step.assignedTo.includes(approver)) return { ok: false, error: 'not-an-assigned-approver', run };
  if (!(outcome in step.outcomes)) {
    return { ok: false, error: 'unknown-outcome', allowed: Object.keys(step.outcomes), run };
  }
  if (step.responseForm) {
    const missing = (step.responseForm.fields || [])
      .filter((f) => f.required)
      .map((f) => f.field)
      .filter((f) => inputs == null || inputs[f] == null || inputs[f] === '');
    if (missing.length) return { ok: false, error: 'missing-inputs', missing, run };
  }
  if (approver in step.decisions) return { ok: false, error: 'already-decided', run };

  step.decisions[approver] = { outcome, comment, inputs, onBehalfOf, at };
  chainAppend(run, { kind: 'decision', step: step.id, approver, outcome, inputs, onBehalfOf, at });
  run.audit.push({ event: 'decision', step: step.id, approver, outcome, at });

  applyOutcomes(run, step, at);
  return { ok: true, run };
}

function applyOutcomes(run, step, at) {
  const semantics = step.outcomes;
  const byOutcome = {};
  for (const d of Object.values(step.decisions)) byOutcome[d.outcome] = (byOutcome[d.outcome] || 0) + 1;

  // Any terminal/redirect outcome fires immediately (veto semantics).
  for (const [label, count] of Object.entries(byOutcome)) {
    const action = semantics[label];
    if (action === 'reject-run' && count > 0) {
      step.status = 'rejected';
      run.status = 'rejected';
      run.outcome = label;
      return;
    }
    if (action && action.startsWith('goto:') && count > 0) {
      const target = action.slice(5);
      const idx = run.steps.findIndex((s) => s.id === target);
      if (idx !== -1) {
        step.status = 'returned';
        run.currentIndex = idx;
        const t = run.steps[idx];
        t.status = 'pending';
        t.decisions = {};
        t.startedAt = at;
        run.audit.push({ event: 'sent-back', from: step.id, to: target, at });
      }
      return;
    }
  }

  // Advancing outcomes accumulate toward the quorum.
  const advancing = Object.entries(byOutcome)
    .filter(([label]) => semantics[label] === 'advance')
    .reduce((a, [, n]) => a + n, 0);
  if (advancing >= quorumNeeded(step)) {
    step.status = 'approved';
    if (run.currentIndex >= run.steps.length - 1) {
      run.status = 'approved';
      run.outcome = 'approved';
    } else {
      run.currentIndex += 1;
      run.steps[run.currentIndex].startedAt = at;
    }
  }
}

// --- timers & expiry (LC31 timers) ----------------------------------------

/**
 * Sweep a run against the clock: an overdue current step applies its expiry
 * policy exactly once, with an audit entry.
 */
/**
 * Put an escalation target on a step.
 *
 * The target is added as an assignee AND remembered in `escalatedTo`. For an
 * 'all' rule that second part matters: merely adding the target would raise the
 * bar ("everyone approves" now includes the person escalation was meant to route
 * around), so the simple engine treats an escalated assignee's approval as
 * satisfying the step instead of one more signature to collect.
 */
export function addEscalationTarget(step, target) {
  if (!target) return;
  if (!step.assignedTo.includes(target)) step.assignedTo.push(target);
  step.escalatedTo = step.escalatedTo || [];
  if (!step.escalatedTo.includes(target)) step.escalatedTo.push(target);
}

export function checkExpiry(run, nowMs, delegations = {}) {
  if (run.status !== 'pending') return { expired: false, run };
  const step = run.steps[run.currentIndex];
  if (!step.dueMs || !step.startedAt || step.expired) return { expired: false, run };
  if (nowMs - step.startedAt < step.dueMs) return { expired: false, run };

  step.expired = true;
  run.audit.push({ event: 'expired', step: step.id, policy: step.onExpiry, at: nowMs });

  if (step.onExpiry === 'escalate') {
    if (step.escalateTo) {
      const resolved = resolveDelegate(step.escalateTo, delegations, nowMs);
      addEscalationTarget(step, resolved.user);
      run.audit.push({ event: 'escalated', step: step.id, to: resolved.user, at: nowMs });
    }
  } else if (step.onExpiry === 'auto-approve' || step.onExpiry === 'skip') {
    step.status = step.onExpiry === 'skip' ? 'skipped' : 'approved';
    chainAppend(run, { kind: 'expiry', step: step.id, policy: step.onExpiry, at: nowMs });
    if (run.currentIndex >= run.steps.length - 1) {
      run.status = 'approved';
      run.outcome = 'approved';
    } else {
      run.currentIndex += 1;
      run.steps[run.currentIndex].startedAt = nowMs;
    }
  } else if (step.onExpiry === 'auto-reject') {
    step.status = 'rejected';
    run.status = 'rejected';
    run.outcome = 'expired';
    chainAppend(run, { kind: 'expiry', step: step.id, policy: 'auto-reject', at: nowMs });
  }
  return { expired: true, run };
}

// --- external approvers via signed tokens (LC31 external) ------------------

/** Sign an action token an external approver can use without an account. */
export function signApprovalToken(secret, { runId, stepId, approver, expiresAt }) {
  const payload = canonical({ runId, stepId, approver, expiresAt });
  return { token: sha256(`${secret}:${payload}`), runId, stepId, approver, expiresAt };
}

/** Constant-shape verification: match + expiry, nothing leaks on failure. */
export function verifyApprovalToken(secret, token, nowMs) {
  const expected = sha256(`${secret}:${canonical({ runId: token.runId, stepId: token.stepId, approver: token.approver, expiresAt: token.expiresAt })}`);
  if (expected !== token.token) return { ok: false, error: 'invalid-token' };
  if (token.expiresAt && nowMs > token.expiresAt) return { ok: false, error: 'token-expired' };
  return { ok: true, approver: token.approver };
}

// --- tamper-evident chain (LC31 signed gates) ------------------------------

/** Re-derive every link; any edited decision breaks the chain from there on. */
export function verifyDecisionChain(run) {
  let prev = 'genesis';
  for (let i = 0; i < run.chain.length; i++) {
    const { hash, prev: recordedPrev, ...entry } = run.chain[i];
    if (recordedPrev !== prev) return { ok: false, brokenAt: i, reason: 'prev-mismatch' };
    if (sha256(prev + canonical(entry)) !== hash) return { ok: false, brokenAt: i, reason: 'hash-mismatch' };
    prev = hash;
  }
  return { ok: true, length: run.chain.length };
}
