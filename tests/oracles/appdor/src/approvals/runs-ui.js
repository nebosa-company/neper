/**
 * Requesting and giving approvals (LC31 / approvals-human-workflow).
 *
 * The chain engine and its advanced mechanics have been sitting in
 * `approvals/index.js` and `approvals/advanced.js` since they were written,
 * called by nothing. There was nowhere to put a run, so the product had no
 * approvals at all.
 *
 * This is the bridge between the engine's run object and a stored row. The
 * one thing it must never get wrong is `current_approvers`: it is the RLS
 * predicate that decides who may record a decision, and it is derived from the
 * run on every single transition. A stale value would let an approver from a
 * finished step keep deciding on a step they were never asked about.
 */

import { canBreakGlass } from './break-glass.js';
import { evidenceAllowsDecision, renderApprovalEvidence } from './evidence.js';
// Only what this module CALLS. `newRunRow` and `simpleDefinition` are
// re-exported below, and `export … from` needs no local binding — importing
// them as well is what `npm run lint` flags, and the note under the re-export
// explains the opposite trap that produced the over-wide list.
import { approverInbox, currentApprovers, decide, isSettled } from './index.js';
/**
 * Re-exported, not redefined.
 *
 * These three moved DOWN into `index.js` to cut an import cycle: `break-glass.js`
 * is pure engine and needed them, and reaching up into this UI-facing module to
 * get them made `runs-ui → break-glass → runs-ui`. `tests/import-cycles.test.js`
 * caught it the moment eight parallel branches were merged, which is the only
 * point at which the cycle existed. Re-exported so every caller is untouched.
 *
 * IMPORTED as well as re-exported, deliberately: `export … from` creates no
 * LOCAL binding, and this module calls `currentApprovers` itself. The first
 * attempt re-exported only, and every call in here became a ReferenceError —
 * the same trap `services/thumbnail-service` records in docs/unwired-modules.md.
 *
 * `newRunRow` and `simpleDefinition` are re-exported and NOT imported, because
 * nothing in this file calls them: the rule is "import the ones you call", and
 * importing the others made the lint gate red the moment the eight branches
 * were merged. `startApproval` was neither called nor re-exported and is gone.
 */
export { currentApprovers, newRunRow, simpleDefinition } from './index.js';

/**
 * A stored `approval_runs` row, in the shape 28-approvals.sql holds.
 *
 * Named here because this is the module that BUILDS one, and referenced from
 * `break-glass.js`, `timers.js` and `external-gate.js` rather than restated —
 * the run document is stored whole, so a second description of it is a second
 * thing to keep in step with the column list.
 *
 * @typedef {import('./index.js').ApprovalRun} ApprovalRun
 *
 * @typedef {import('./index.js').ApprovalRow} ApprovalRow
 * @typedef {import('./index.js').ApprovalDefinition} ApprovalDefinition
 */

/**
 * Apply a decision to a stored row.
 *
 * Returns `{ changed: false }` when the engine refused — it returns the SAME
 * run object for a decision by someone not assigned, an unknown outcome, or a
 * settled run. Writing that back would be a no-op UPDATE that still looks like
 * success to the caller, so the refusal is surfaced instead.
 */
export function applyDecision(row, { approver, decision, comment = null, at = null }) {
  const before = row.run;
  const after = decide(before, { approver, decision, comment, at });
  if (after === before) {
    // The engine refuses by returning the run unchanged, which collapses three
    // different refusals into one. Self-approval is separated out because it is
    // the one a person can act on: "you asked for this" tells them to find
    // another approver, where "you are not being asked to decide" sends them
    // looking for a permission problem that is not there.
    if (before && before.requestedBy && approver === before.requestedBy) {
      return { changed: false, reason: 'self-approval' };
    }
    return { changed: false, reason: 'not-permitted-or-settled' };
  }
  return {
    changed: true,
    patch: {
      run: after,
      status: after.status,
      // Recomputed, never carried forward.
      current_approvers: currentApprovers(after),
      updated_at: at || null,
    },
    settled: isSettled(after),
  };
}

/** The rows awaiting this user, from rows already loaded. */
export function inboxFor(rows, userId) {
  const byId = new Map((rows || []).map((r) => [String(r.id), r]));
  return approverInbox((rows || []).map((r) => ({ ...r.run, id: String(r.id) })), userId)
    .map((entry) => ({ ...entry, row: byId.get(String(entry.runId)) }))
    .filter((e) => e.row);
}

/** A one-line summary of where a run has got to. */
export function describeRun(run) {
  if (!run || !run.steps || !run.steps.length) return 'No approval steps';
  if (run.status === 'approved') return 'Approved';
  if (run.status === 'rejected') return 'Rejected';
  if (run.status === 'cancelled') return 'Cancelled';
  const step = run.steps[run.currentIndex];
  const n = run.currentIndex + 1;
  const total = run.steps.length;
  const decided = Object.keys(step.decisions || {}).length;
  const needed = step.rule === 'all' ? step.assignedTo.length : 1;
  return `Step ${n} of ${total} — ${decided} of ${needed} decision${needed === 1 ? '' : 's'}`;
}

/**
 * Render the approvals panel for one record.
 *
 * The controls come from the component layer (`.panel`, `.btn`, `.input`) so
 * this screen stops carrying its own copy of eight utilities per element.
 *
 * Two deliberate exceptions:
 *   - Approve keeps its green. There is no `.btn-success`, and inventing one in
 *     a stylesheet this module does not own would be worse than a named local.
 *   - Reject uses `.btn-danger` plain. It used to carry an explicit
 *     `text-white`, and that override has been REMOVED because it had outlived
 *     the defect it was written for and become one.
 *
 *     The note it replaced said `.btn-danger` lands at 3.6:1 in dark mode and
 *     that white is 4.8:1. Both figures were true when the dark theme mapped
 *     `--danger` to `--red-500` (#d92d20). It no longer does: the dark block in
 *     `src/styles/tokens.css` remaps it to `--red-400` (#f97066), and says in
 *     its own comment that this was done to fix exactly this pairing.
 *
 *     Re-measured against the values that ship today, dark theme:
 *
 *         .btn-danger default ink   gray-900 on #f97066  = 6.27:1   passes
 *         the `text-white` override white    on #f97066  = 2.79:1   fails
 *
 *     So the override was producing a worse result than doing nothing — below
 *     even the 3:1 floor for a non-text indicator, where the token it was
 *     overriding clears AA text with room to spare. No `--danger-contrast`
 *     token is needed; the handoff that asked for one is answered by deleting a
 *     class.
 *
 *     The general rule this earned: a contrast figure is only meaningful beside
 *     the token values it was measured against. Re-measure before acting on an
 *     inherited number.
 *
 * ## The override is rendered as an override
 *
 * A break-glass approval (LC31.15) settles the run through the same
 * `step.decisions` map every other decision uses, so without the `override`
 * flag it would read in this trail as "Ada approved" — a bypass of the control
 * this panel exists to show, displayed as the control working. The banner and
 * the flagged trail line are the criterion's "prominently flagged in audit and
 * inbox history", and they are the reason `applyBreakGlass` stamps the flag on
 * the decision rather than only on the run.
 *
 * @param {{escapeHtml: (s: any) => string, rows: ApprovalRow[], userId: string,
 *   nameOf?: (id: string) => string, t?: (key: string) => string,
 *   role?: string|null}} deps
 *   `t` defaults to returning the key, so a caller that renders no override
 *   controls needs no translator; `role` is the viewer's app role, and without
 *   one the emergency control is never offered.
 */
export function renderRecordApprovals({
  escapeHtml, rows, userId, nameOf = (id) => id, t = (key) => key, role = null,
}) {
  if (!rows || !rows.length) {
    return '<p class="text-xs text-muted">No approval has been requested for this record.</p>';
  }
  return rows.map((row) => {
    const run = row.run;
    const mine = evidenceAllowsDecision(row) && currentApprovers(run).includes(userId) && !((run.steps[run.currentIndex] || {}).decisions || {})[userId];
    const stale = row.evidence?.state === 'changed';
    const badge = stale ? 'text-danger' : run.status === 'approved' ? 'text-success'
      : run.status === 'rejected' ? 'text-danger'
        : 'text-warn';

    const trail = (run.steps || []).flatMap((s) =>
      Object.entries(s.decisions || {}).map(([who, d]) =>
        `<div class="text-2xs ${d.override ? 'text-danger font-medium' : 'text-muted'}">${escapeHtml(nameOf(who))} ${escapeHtml(d.override ? t('apps.overrodeApproval') : d.decision === 'approve' ? 'approved' : 'rejected')}${d.comment ? `: ${escapeHtml(d.comment)}` : ''}</div>`)
    ).join('');

    // The chases this run has already made, from the audit trail the worker
    // writes (LC31.5). Shown because "nobody has answered" and "nobody has
    // answered and two people have been chased about it" are different states
    // and the panel could only ever say the first.
    const chases = (run.audit || []).filter((e) => e && (e.event === 'reminded' || e.event === 'escalated'))
      .map((e) => `<div class="text-2xs text-muted">${escapeHtml(e.event === 'reminded' ? t('apps.approvalReminderSent') : t('apps.approvalEscalated'))}${e.to && e.to.length ? `: ${[].concat(e.to).map((u) => escapeHtml(nameOf(u))).join(', ')}` : ''}</div>`)
      .join('');

    const override = run.override
      ? `<div class="text-2xs text-danger font-medium mt-1">${escapeHtml(t('apps.emergencyOverride'))} — ${escapeHtml(nameOf(run.override.by))}: ${escapeHtml(run.override.reason || '')}</div>`
      : '';

    return `
      <div class="panel p-2 mb-2">
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-secondary truncate">${escapeHtml(row.title || 'Approval')}</span>
          <span class="text-xs ${badge} whitespace-nowrap">${escapeHtml(stale ? t('approvals.evidence.staleStatus') : describeRun(run))}</span>
        </div>
        <div class="text-2xs text-muted mt-0.5">Waiting on ${currentApprovers(run).map((u) => escapeHtml(nameOf(u))).join(', ') || '—'}</div>
        ${trail}
        ${chases}
        ${override}
        ${renderApprovalEvidence(row, { escapeHtml, t })}
        ${mine ? `
        <div class="flex gap-2 mt-2">
          <button data-approve="${escapeHtml(String(row.id))}" class="btn bg-success text-inverse hover:opacity-90">Approve</button>
          <button data-reject="${escapeHtml(String(row.id))}" class="btn btn-danger">Reject</button>
          <input data-comment="${escapeHtml(String(row.id))}" placeholder="Comment (optional)" class="input flex-1 min-w-0">
        </div>` : ''}
        ${evidenceAllowsDecision(row) && canBreakGlass(row, { role }) ? `
        <div class="mt-2">
          <button data-break-glass="${escapeHtml(String(row.id))}" class="text-xs text-danger hover:underline"><i class="fas fa-triangle-exclamation mr-1"></i>${escapeHtml(t('apps.emergencyOverride'))}</button>
        </div>` : ''}
      </div>`;
  }).join('');
}
