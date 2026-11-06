/**
 * The emergency override, and the review it owes (LC31.15).
 *
 * Break-glass is the one approval mechanic that is dangerous to build badly,
 * because its whole purpose is to bypass the control everything else in this
 * directory exists to enforce. Three properties make it safe enough to ship:
 *
 *   1. **It is off unless the definition turns it on.** A run started without
 *      `definition.breakGlass` cannot be overridden by anybody, at any role.
 *      The person asking for the approval decides whether an emergency exit
 *      exists — not the person who later wants to use it.
 *   2. **It is never silent.** The override is stamped on the run
 *      (`run.override`), written into the audit trail, and rendered as an
 *      override rather than as an approval. A bypass that reads like a normal
 *      approval in the history is worse than no bypass at all, because it
 *      removes the control AND the evidence.
 *   3. **It files its own review.** `applyBreakGlass` returns a second row —
 *      an approval over the same record, addressed to exactly the people who
 *      were bypassed, asking them to review after the fact. The retro-review
 *      is a real approval run rather than a new kind of object, so it appears
 *      in the same panel, notifies through the same path, and cannot be
 *      quietly dropped by a queue nobody built.
 *
 * A reason is REQUIRED. An override with no reason is an audit entry that says
 * a rule was broken and nothing about why, which is the entry that makes the
 * whole trail worthless six months later.
 *
 * Pure. The caller checks the role it holds, writes the patch, and inserts the
 * retro-review row.
 */

// `runs-ui.js` imports `canBreakGlass` back, which is a cycle — and a safe one:
// neither module evaluates anything from the other at module scope, and both
// sides are hoisted function declarations resolved at call time. The
// alternative was a third module holding two predicates, which is a file whose
// only purpose is to be somewhere else.
import { newRunRow, currentApprovers, simpleDefinition } from './index.js';

/**
 * @typedef {import('./runs-ui.js').ApprovalRow} ApprovalRow
 * @typedef {import('./runs-ui.js').ApprovalDefinition} ApprovalDefinition
 */

/**
 * Who may break the glass when a definition does not say.
 *
 * App-level roles, matching `custom-roles.js`. Deliberately the two roles that
 * already hold every capability there is: naming a WEAKER role here as a
 * default would be this module inventing a privilege escalation.
 */
export const DEFAULT_EMERGENCY_ROLES = Object.freeze(['owner', 'admin']);

/**
 * The break-glass policy on a definition. Disabled unless it says otherwise.
 * @param {ApprovalDefinition|null|undefined} definition
 * @returns {{enabled: boolean, roles: string[]}}
 */
export function breakGlassPolicy(definition) {
  const policy = definition && definition.breakGlass;
  if (!policy) return { enabled: false, roles: [] };
  const roles = Array.isArray(policy.roles) && policy.roles.length
    ? policy.roles.map((r) => String(r).toLowerCase())
    : [...DEFAULT_EMERGENCY_ROLES];
  return { enabled: policy.enabled !== false, roles };
}

/**
 * May this person override this run right now?
 *
 * @param {ApprovalRow|null|undefined} row a stored `approval_runs` row
 * @param {{role?: string|null}} [who] the caller's app role
 */
export function canBreakGlass(row, { role } = {}) {
  if (!row || !row.run || row.run.status !== 'pending') return false;
  const policy = breakGlassPolicy(row.definition);
  if (!policy.enabled) return false;
  return policy.roles.includes(String(role || '').toLowerCase());
}

/**
 * Apply an override.
 *
 * @param {ApprovalRow} row
 * @param {{by?: string, role?: string|null, reason?: string, at?: string|null,
 *   retroReviewTitle?: string|null}} [args]
 *   `by` is the overriding user's id, `role` their app role, `reason` why this
 *   could not wait (required), and `retroReviewTitle` the title of the review
 *   row — which the caller supplies already translated, because this module
 *   renders nothing.
 * @returns {{ok: false, error: string}
 *   |{ok: true, bypassed: string[], retroReview: ApprovalRow|null,
 *     patch: {run: import('./index.js').ApprovalRun, status: string,
 *       current_approvers: string[], updated_at: string|null}}}
 */
export function applyBreakGlass(row, { by, role, reason, at = null, retroReviewTitle = null } = {}) {
  if (!row || !row.run) return { ok: false, error: 'no-run' };
  if (row.run.status !== 'pending') return { ok: false, error: 'run-settled' };
  if (!canBreakGlass(row, { role })) return { ok: false, error: 'not-permitted' };
  if (!by) return { ok: false, error: 'no-actor' };
  // The requester may not break the glass on their own request.
  //
  // Without this line break-glass would be a way around the self-approval
  // refusal in `decide` (src/approvals/index.js): an admin asks for something,
  // ticks the emergency box while asking, and approves it themselves an hour
  // later. That is not an emergency exit, it is a self-approval with an extra
  // click — and it would have made LC31.13's unconditional block conditional on
  // the requester not being an admin.
  if (row.run.requestedBy && String(row.run.requestedBy) === String(by)) {
    return { ok: false, error: 'self-override' };
  }
  const why = String(reason || '').trim();
  if (!why) return { ok: false, error: 'reason-required' };

  const bypassed = currentApprovers(row.run).filter((u) => String(u) !== String(by));
  const run = JSON.parse(JSON.stringify(row.run));
  const step = run.steps[run.currentIndex];

  // Recorded as a decision so the trail shows WHO settled it, and flagged as
  // an override on the same entry so no reader can mistake it for a normal
  // approval. Both halves are needed: the id alone reads as an approver who
  // was never asked, and the flag alone leaves the settling decision unowned.
  step.decisions[by] = { decision: 'approve', comment: why, at, override: true };
  step.status = 'approved';
  // Every step the override skipped is marked as skipped rather than left
  // pending, so a two-stage chain does not read as still waiting on stage 2.
  for (let i = run.currentIndex + 1; i < run.steps.length; i++) run.steps[i].status = 'skipped';
  run.currentIndex = run.steps.length - 1;
  run.status = 'approved';
  run.outcome = 'break-glass';
  run.override = { by, role: String(role || '').toLowerCase(), reason: why, at, bypassed };
  run.audit = [...(run.audit || []), { event: 'break-glass', by, role: String(role || '').toLowerCase(), reason: why, bypassed, at }];

  // The people who were bypassed are the people who review it. Asked as `all`:
  // an override is reviewed by everyone it went around, not by whichever one of
  // them opens the record first.
  const retroReview = bypassed.length && retroReviewTitle
    ? newRunRow({
      tableId: row.table_id,
      rowId: row.row_id,
      title: retroReviewTitle,
      definition: {
        ...simpleDefinition(bypassed, 'all'),
        retroReviewOf: row.id != null ? String(row.id) : null,
        // The review is itself un-overridable. A break-glass that can be
        // closed by a second break-glass is not a control.
        breakGlass: { enabled: false, roles: [] },
      },
      requestedBy: by,
    })
    : null;

  return {
    ok: true,
    bypassed,
    retroReview,
    patch: {
      run,
      status: 'approved',
      // Settled: nobody is being asked any more, and the column is the RLS
      // predicate — leaving the bypassed approvers in it would let them decide
      // an approval that is already closed.
      current_approvers: currentApprovers(run),
      updated_at: at,
    },
  };
}
