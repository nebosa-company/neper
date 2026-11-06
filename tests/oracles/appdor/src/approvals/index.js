/**
 * Approvals & human-in-the-loop workflow (LC31 / approvals-human-workflow).
 *
 * Pure sequential approval state machine: multi-step chains, per-step any/all
 * rules, reassignment and escalation, an approver inbox, and terminal status.
 * The host persists runs, sends notifications, and enforces due dates.
 *
 * Definition: { steps:[{ id, approvers:[userId], rule:'any'|'all', escalateTo?,
 *   dueInHours? }] }
 *
 * ## The shapes, named once
 *
 * `src/workflow/ir.js` validates an approval step's routing rules, which pulls
 * this directory into the type-check program through `flow-engine.js` — so the
 * run and the step are now written down rather than left as `@param {object}`,
 * which the checker reads as "an object with no properties at all". Every
 * module in this directory references these rather than restating them: a
 * second copy of the run shape is a second thing to keep true, and the whole
 * point of the engine is that there is one.
 *
 * @typedef {Object} ApprovalStep
 * @property {string} id
 * @property {string[]} approvers
 * @property {string|{quorum: number}} rule
 * @property {string|null} [escalateTo]
 * @property {string[]} assignedTo
 * @property {Record<string, any>} decisions
 * @property {string} status
 * @property {number|string|null} [startedAt]  set by the timer sweep (LC31.5)
 * @property {number|null} [dueMs]             the calendar-adjusted span
 * @property {string} [onExpiry]
 * @property {boolean} [expired]
 * @property {Record<string, string>} [outcomes]
 * @property {{fields?: Array<{field: string, required?: boolean}>}|null} [responseForm]
 *
 * @typedef {Object} ApprovalRun
 * @property {string} [id]
 * @property {string} [recordId]
 * @property {string|null} [requestedBy]
 * @property {string} status
 * @property {number} currentIndex
 * @property {ApprovalStep[]} steps
 * @property {Array<Record<string, any>>} [audit]
 * @property {Array<Record<string, any>>} [chain]
 * @property {string} [outcome]
 * @property {{by: string, role: string, reason: string, at: string|null, bypassed: string[]}} [override]
 *
 * @typedef {Object} ApprovalDecision
 * @property {string} approver
 * @property {string} decision  'approve' | 'reject'
 * @property {string|null} [comment]
 * @property {string|null} [at]
 *
 * `newRunRow` and `simpleDefinition` moved DOWN here to cut an import cycle,
 * and they carry `ApprovalRow`/`ApprovalDefinition` in their JSDoc — two shapes
 * `runs-ui.js` names, because it is the module that builds a stored row. A
 * JSDoc typedef is FILE-scoped, so the bare names resolved to nothing here and
 * the type-check went red the moment the eight branches were merged. Imported
 * the same way `break-glass.js` and `routing.js` already import them.
 */

import { addEscalationTarget } from './advanced.js';

function cloneRun(run) {
  return {
    ...run,
    steps: run.steps.map((s) => ({
      ...s,
      decisions: { ...s.decisions },
      assignedTo: [...s.assignedTo],
      ...(s.escalatedTo ? { escalatedTo: [...s.escalatedTo] } : {}),
    })),
  };
}

/**
 * Initialize an approval run from a definition.
 *
 * `meta.requestedBy` is carried ONTO THE RUN, not just onto the row around it.
 * `newRunRow` has always taken a requester and stored it as `requested_by` on
 * the database row, and the run it built never learned who that was — so
 * `decide` below, which is the only thing that can refuse a decision, had no
 * way to tell an approver from the person asking. A requester who was also an
 * assigned approver could approve their own request, and nothing anywhere
 * said no.
 */
export function startApproval(definition, meta = {}) {
  const steps = (definition.steps || []).map((s, i) => ({
    id: s.id || `step-${i + 1}`,
    approvers: s.approvers || [],
    rule: s.rule || 'any',
    escalateTo: s.escalateTo || null,
    assignedTo: [...(s.approvers || [])],
    decisions: {},
    status: 'pending',
  }));
  return {
    id: meta.id,
    recordId: meta.recordId,
    // Null when the caller does not say. A run with no known requester is not
    // treated as one nobody may decide — that would refuse every legacy run in
    // the table, which is a worse failure than the one being fixed.
    requestedBy: meta.requestedBy || null,
    status: steps.length ? 'pending' : 'approved',
    currentIndex: 0,
    steps,
  };
}

function evaluateStep(step) {
  const decisions = Object.values(step.decisions);
  if (decisions.some((d) => d.decision === 'reject')) return 'rejected';
  const approvals = decisions.filter((d) => d.decision === 'approve').length;
  if (step.rule === 'all') {
    // An escalated approver stands in for the people who did not answer: their
    // approval settles the step, and they are not a further signature to wait for.
    const escalated = step.escalatedTo || [];
    if (escalated.some((user) => step.decisions[user] && step.decisions[user].decision === 'approve')) return 'approved';
    const required = step.assignedTo.filter((user) => !escalated.includes(user));
    const done = required.filter((user) => step.decisions[user] && step.decisions[user].decision === 'approve').length;
    return required.length > 0 && done >= required.length ? 'approved' : 'pending';
  }
  return approvals >= 1 ? 'approved' : 'pending';
}

/**
 * Record a decision on the current step and advance the run.
 * @param {ApprovalRun} run
 * @param {Partial<ApprovalDecision>} [decision]
 * @returns {ApprovalRun} the updated run (a copy)
 */
export function decide(run, { approver, decision, comment, at } = {}) {
  if (run.status !== 'pending') return run;
  // Self-approval, refused here rather than by leaving the requester out of the
  // pool. A definition may legitimately name a group the requester belongs to —
  // "any team lead" when the requester IS a team lead — and resolving them out
  // of `assignedTo` would silently shrink an `all` rule's denominator and let
  // the step approve on fewer decisions than it asks for. Refusing the DECISION
  // keeps the pool honest and the arithmetic right.
  //
  // Only when the run knows who asked: `requestedBy` is null on runs written
  // before it was recorded, and those keep their old behaviour rather than
  // becoming undecidable.
  if (run.requestedBy && approver === run.requestedBy) return run;
  const next = cloneRun(run);
  const step = next.steps[next.currentIndex];
  if (!step || !step.assignedTo.includes(approver)) return run; // not an assigned approver
  if (decision !== 'approve' && decision !== 'reject') return run;
  // One decision per approver. Without this an approver on an 'all' step could
  // approve and then flip to reject (or the reverse) through the API.
  if (Object.prototype.hasOwnProperty.call(step.decisions, approver)) return run;

  step.decisions[approver] = { decision, comment: comment || null, at: at || null };
  const outcome = evaluateStep(step);
  step.status = outcome;

  if (outcome === 'rejected') {
    next.status = 'rejected';
    return next;
  }
  if (outcome === 'approved') {
    if (next.currentIndex >= next.steps.length - 1) {
      next.status = 'approved';
    } else {
      next.currentIndex += 1;
    }
  }
  return next;
}

/** Reassign the current step from one approver to another (a copy is returned). */
export function reassign(run, fromUser, toUser) {
  const next = cloneRun(run);
  const step = next.steps[next.currentIndex];
  if (!step) return run;
  step.assignedTo = step.assignedTo.map((u) => (u === fromUser ? toUser : u));
  if (!step.assignedTo.includes(toUser)) step.assignedTo.push(toUser);
  return next;
}

/** Escalate the current step to its escalation approver (adds them as assignee). */
export function escalate(run, escalateTo) {
  const next = cloneRun(run);
  const step = next.steps[next.currentIndex];
  if (!step) return run;
  addEscalationTarget(step, escalateTo || step.escalateTo);
  return next;
}

/** Steps across runs currently awaiting a given user's decision. */
export function approverInbox(runs, userId) {
  const out = [];
  for (const run of runs) {
    if (run.status !== 'pending') continue;
    const step = run.steps[run.currentIndex];
    if (step && step.assignedTo.includes(userId) && !(userId in step.decisions)) {
      out.push({ runId: run.id, recordId: run.recordId, stepId: step.id });
    }
  }
  return out;
}

export function isSettled(run) {
  return run.status === 'approved' || run.status === 'rejected';
}

/**
 * Who the run is asking right now. Empty once the run is settled.
 * @param {ApprovalRun} run
 * @returns {string[]}
 */
/**
 * The two shapes the hosts store, moved here with `newRunRow` and
 * `simpleDefinition` when those were pulled DOWN out of `runs-ui.js` to cut an
 * import cycle. The JSDoc came with them and the typedefs did not, so tsc lost
 * both names — caught by an agent running typecheck on a branch built from
 * this one, not by me, because I re-ran the test SUITE after the cycle fix and
 * not lint or typecheck. `runs-ui.js` now imports them back.
 *
 * @typedef {Object} ApprovalRow
 * @property {string} [id]
 * @property {string} table_id
 * @property {string} row_id
 * @property {string|null} title
 * @property {ApprovalDefinition} definition
 * @property {ApprovalRun} run
 * @property {string} status
 * @property {string[]} current_approvers
 * @property {string|null} requested_by
 * @property {string} [created_at]
 * @property {string|null} [updated_at]
 * @property {Record<string, any>} [evidence] Caller-visible evidence returned by the database.
 *
 * The definition a run was started from, plus the four things the hosts stamp
 * onto it: where a workflow's answer goes, which routing rule chose these
 * people, whether an emergency override exists, and the timers.
 *
 * @typedef {Object} ApprovalDefinition
 * @property {Array<Record<string, any>>} [steps]
 * @property {{runId: string, stepId: string|null, key: string|null, signal: string}} [origin]
 * @property {{id: string, index: number, name: string|null}} [matchedRule]
 * @property {{url: string, secret?: string|null, correlation?: string|null}} [externalGate]
 * @property {{enabled?: boolean, roles?: string[]}} [breakGlass]
 * @property {{remindAfterHours?: number, escalateAfterHours?: number, calendar?: any}} [timers]
 * @property {string|null} [escalateTo]
 * @property {Record<string, {to: string, until?: string|number}>} [delegations]
 * @property {string|null} [retroReviewOf]
 * @property {string[]} [evidenceFields] Immutable scalar column ids selected when requesting.
 */

export function currentApprovers(run) {
  if (!run || run.status !== 'pending') return [];
  const step = run.steps[run.currentIndex];
  // Assignees who have not decided yet: this is what is written to
  // current_approvers (the RLS predicate for deciding) and what reminders chase.
  return step ? step.assignedTo.filter((user) => !(step.decisions && Object.prototype.hasOwnProperty.call(step.decisions, user))) : [];
}


/**
 * The two shapes `newRunRow` and `simpleDefinition` speak, borrowed by TYPE
 * from the module they used to live in.
 *
 * They came down here to cut the `runs-ui → break-glass → runs-ui` cycle and
 * their `@typedef` blocks stayed behind, so `tsc --noEmit` reported three
 * "cannot find name" errors on functions that had not changed. A JSDoc
 * `import()` is erased before anything runs, which is why `break-glass.js`
 * already reaches back into `runs-ui.js` for the same two names without
 * recreating the cycle — this is that pattern, not a new one.
 *
 * Aliased rather than restated: a second declaration of `ApprovalRow` here is a
 * second description of the `approval_runs` column list, and the two would
 * drift the first time a column moved.
 *
 */

/**
 * A stored row from a definition.
 *
 * The two names are reached through a TYPE-ONLY import of `runs-ui.js`, which
 * is where both are declared and where this function used to live. It moved
 * down here to cut the `runs-ui -> break-glass -> runs-ui` cycle and the
 * typedefs did not follow, so `npm run typecheck` has been red on three
 * "cannot find name" errors ever since. `import(...)` inside JSDoc emits no
 * runtime import, so the cycle the move removed stays removed.
 *
 * @param {{tableId: string, rowId: string, title?: string|null,
 *   definition: ApprovalDefinition,
 *   requestedBy?: string|null}} args
 * @returns {ApprovalRow}
 */
export function newRunRow({ tableId, rowId, title, definition, requestedBy }) {
  const run = startApproval(definition, { recordId: rowId, requestedBy });
  return {
    table_id: tableId,
    row_id: rowId,
    title: title || null,
    definition,
    run,
    status: run.status,
    current_approvers: currentApprovers(run),
    requested_by: requestedBy,
  };
}


/**
 * Build a one-step definition from a list of approvers — the common case, and
 * the only one the request dialog offers. Multi-step chains are supported by
 * the engine and have no UI yet; pretending otherwise in this form would be
 * worse than the form being simple.
 *
 * `options` carries the two things the dialog now also asks for, and each is
 * omitted entirely when it was not asked for. That is not tidiness: a
 * `breakGlass: null` on the definition is indistinguishable from a policy
 * somebody configured and then emptied, and `breakGlassPolicy` would have to
 * guess which. Absent means "never offered".
 *
 * @param {string[]} approverIds
 * @param {string} [rule] 'any' | 'all'
 * @param {{escalateTo?: string|null, evidenceFields?: string[],
 *   breakGlass?: {enabled?: boolean, roles?: string[]}|null,
 *   timers?: {remindAfterHours?: number, escalateAfterHours?: number, calendar?: any}|null,
 *   externalGate?: {url: string, secret?: string|null, correlation?: string|null}|null}} [options]
 * @returns {ApprovalDefinition}
 */
export function simpleDefinition(approverIds, rule = 'any', options = {}) {
  const step = { id: 'step-1', approvers: [...(approverIds || [])], rule };
  // Read by `timers.js` when the escalation deadline passes. The chain engine
  // has always had this field (`startApproval` copies it); nothing populated it.
  if (options.escalateTo) step.escalateTo = options.escalateTo;
  const definition = { steps: [step] };
  if (options.breakGlass) definition.breakGlass = options.breakGlass;
  if (options.timers) definition.timers = options.timers;
  if (options.evidenceFields?.length) definition.evidenceFields = [...options.evidenceFields];
  if (options.externalGate && options.externalGate.url) definition.externalGate = options.externalGate;
  return definition;
}
