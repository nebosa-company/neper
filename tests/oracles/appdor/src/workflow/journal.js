/**
 * The run journal — the only thing that has to survive a process dying.
 *
 * A durable run keeps no state in JavaScript memory that matters. Everything
 * an interpreter needs to resume is an append-only list of entries plus a
 * small run header, both plain JSON. Kill the worker mid-run, start a new one,
 * replay the journal, and execution continues from the step after the last
 * committed entry — because the journal *is* the program counter.
 *
 * ## Why replay rather than a saved cursor
 *
 * A cursor ("currently at step 7, inside branch B, loop index 3") has to
 * serialize the interpreter's entire stack, and every new control-flow
 * construct changes that shape. Replay stores results instead of position:
 * re-run the definition from the top, and any step that already has a
 * `step-completed` entry returns its recorded value rather than executing.
 * Control flow re-derives itself, because the same inputs take the same
 * branches. Nested forks and loops need no special serialization at all.
 *
 * The price is determinism, and it is a real price: an interpreter that calls
 * `Date.now()` takes a different branch on replay than it did on the first
 * pass, and the run silently diverges. So every non-deterministic value is
 * *recorded* — `recordClock` writes the timestamp into the journal on the
 * first pass and reads it back on every replay. `Math.random()` and id
 * generation go through the same door.
 *
 * ## ACID, precisely
 *
 * This module produces commits; the host applies them. A commit is one
 * atomic write of (new entries + the patched run header), guarded by
 * `expectedSeq`.
 *
 *   - **Atomic**: entries and header move together, so a run can never have a
 *     `step-completed` entry with a header that says it never started.
 *   - **Consistent**: `applyCommit` refuses an out-of-order or duplicate seq,
 *     so a replayed commit is a no-op rather than a double-append.
 *   - **Isolated**: `expectedSeq` is optimistic concurrency control. Two
 *     workers that both pick up the same suspended run will both build a
 *     commit; exactly one lands, and the loser gets `stale-write` and drops
 *     its work. Effects it already performed are still journaled by the
 *     winner's replay only if they were committed — which is why effects are
 *     journaled immediately, one commit each, rather than batched at the end.
 *   - **Durable**: the host writes to its own storage; this module never
 *     assumes an in-process cache is authoritative.
 */

import { TERMINAL_STATUSES } from './ir.js';

export const ENTRY_TYPES = [
  'run-started',
  'step-started',
  'step-completed',
  'step-failed',
  'step-skipped',
  'branch-taken',
  'loop-started',
  'fork-started',
  'fork-branch-completed',
  'timer-set',
  'timer-fired',
  'signal-awaited',
  'signal-received',
  'clock',
  'random',
  'var-set',
  'effect-recorded',
  'run-paused',
  'run-resumed',
  'run-cancelled',
  'run-completed',
  'run-failed',
  'run-retried',
];

// --- run records ----------------------------------------------------------

/**
 * Create a fresh run header.
 *
 * `seq` is the count of committed entries and doubles as the optimistic lock.
 * `waiting` describes what the run is parked on, and is the *only* thing a
 * scheduler needs to read to decide whether to wake it — a worker never has
 * to load or interpret the definition to know a timer is due.
 */
export function createRun(workflow, trigger = {}, options = {}) {
  return {
    runId: options.runId || null,
    workflowId: workflow.id || null,
    workflowVersion: workflow.version ?? 1,
    // Tenancy anchor and audit actor. The engine never reads either — they
    // exist so a store can enforce row-level security in one hop and a run
    // list can say who started it. Carrying them on the header rather than
    // deriving them per query is what keeps the RLS policy a single join.
    tableId: options.tableId ?? null,
    // The other half of the tenancy anchor, for a rule that is scoped to an
    // application and has no table at all — a page rule. Exactly one of the two
    // is set; `workflows_scope_check` in 85-metadata-changes.sql is what makes
    // that true of the definition, and this carries it onto the run.
    applicationId: options.applicationId ?? null,
    createdBy: options.createdBy ?? null,
    // The event this run answers, when there was one. A store makes
    // (workflow, changeId) unique, so a replayed delivery collides at creation
    // instead of starting a second run — the same shape the legacy path uses,
    // and for the same reason: recognising the duplicate after the run has
    // finished is too late, because the webhook has already been sent.
    changeId: options.changeId ?? null,
    batchId: options.batchId ?? null,
    // Deterministic scheduled occurrence key. A database unique index on
    // (workflow, scheduleOccurrence) makes concurrent workers idempotent.
    scheduleOccurrence: options.scheduleOccurrence ?? null,
    status: 'pending',
    deferred: options.defer === true,
    seq: 0,
    startedAt: options.now ?? null,
    finishedAt: null,
    trigger: { type: (workflow.trigger && workflow.trigger.type) || 'manual', payload: trigger.payload || {}, meta: trigger.meta || {} },
    input: trigger.input || {},
    waiting: null,
    error: null,
    mode: options.mode === 'dry-run' ? 'dry-run' : 'live',
    metered: 0,
    entries: [],
  };
}

/** Read-only view helpers over a run's journal. */
export function journalIndex(run) {
  const completed = new Map();
  const failures = new Map();
  const signals = new Map();
  const timers = new Map();
  const clocks = new Map();
  const branches = new Map();
  const loops = new Map();
  const skipped = new Map();
  const started = new Map();
  const forkBranches = new Map();

  for (const entry of run.entries || []) {
    switch (entry.type) {
      // An explicit operator retry renews the attempt budget without deleting
      // committed results, branch choices, approval evidence or effect IDs.
      case 'run-retried': failures.clear(); break;
      case 'step-completed': completed.set(entry.key, entry); break;
      case 'step-started': started.set(entry.key, entry); break;
      case 'step-skipped': skipped.set(entry.key, entry); break;
      case 'branch-taken': branches.set(entry.key, entry); break;
      case 'loop-started': loops.set(entry.key, entry); break;
      case 'fork-branch-completed': {
        const key = entry.key ?? entry.stepId;
        const names = forkBranches.get(key) || new Set();
        names.add(entry.branch); forkBranches.set(key, names); break;
      }
      case 'step-failed': {
        const list = failures.get(entry.key) || [];
        list.push(entry);
        failures.set(entry.key, list);
        break;
      }
      case 'signal-received': signals.set(entry.key, entry); break;
      case 'timer-fired': timers.set(entry.key, entry); break;
      case 'clock':
      case 'random': clocks.set(entry.key, entry); break;
      default: break;
    }
  }

  return {
    /** The recorded result of a completed execution, or undefined. */
    result: (key) => (completed.has(key) ? completed.get(key).result : undefined),
    isComplete: (key) => completed.has(key),
    skipped: (key) => skipped.get(key),
    started: (key) => started.get(key),
    branch: (key) => branches.get(key),
    loop: (key) => loops.get(key),
    forkBranches: (key) => [...(forkBranches.get(key) || [])],
    failureCount: (key) => (failures.get(key) || []).length,
    lastFailure: (key) => { const list = failures.get(key) || []; return list[list.length - 1]; },
    signal: (key) => signals.get(key),
    hasSignal: (key) => signals.has(key),
    timerFired: (key) => timers.has(key),
    recorded: (key) => (clocks.has(key) ? clocks.get(key).value : undefined),
    hasRecorded: (key) => clocks.has(key),
    size: (run.entries || []).length,
  };
}

// --- commits --------------------------------------------------------------

/**
 * A commit builder. Collect entries and header changes, then hand the whole
 * thing to the store in one write.
 */
export function beginCommit(run) {
  const entries = [];
  const patch = {};
  let baseSeq = run.seq;

  return {
    get expectedSeq() { return baseSeq; },
    get entries() { return entries; },
    get patch() { return patch; },
    get isEmpty() { return entries.length === 0 && Object.keys(patch).length === 0; },

    add(type, fields = {}) {
      if (!ENTRY_TYPES.includes(type)) throw new Error(`unknown-journal-entry-type "${type}"`);
      // `rev` LAST, so a caller cannot supply one (LC27.6).
      //
      // The criterion asks that a run suspended on revision N complete on N
      // "and the ledger records revision N for every node". The header has
      // pinned `workflowVersion` since `createRun` was written; nothing carried
      // it down to the entries, so a reader of the journal could see which
      // steps ran and not which definition they ran under — and after a
      // republish those are different questions.
      //
      // Stamped here rather than at each call site because there are a dozen of
      // them and the one that forgets is the one that matters. Spreading
      // `fields` FIRST would let a caller pass `rev` and have it win, which
      // turns an integrity field into a suggestion.
      const entry = { seq: baseSeq + entries.length + 1, type, ...fields, rev: run.workflowVersion ?? null };
      entries.push(entry);
      return entry;
    },

    setHeader(fields) {
      Object.assign(patch, fields);
      return patch;
    },

    // Entries may be buffered by a sibling fork while a prior commit is in
    // flight. Rebase that buffer after the earlier write completes, retaining
    // the entry objects that the active step still uses for trace fields.
    rebase(nextRun) {
      baseSeq = nextRun.seq;
      entries.forEach((entry, i) => { entry.seq = baseSeq + i + 1; });
    },

    build() {
      return { expectedSeq: baseSeq, entries: entries.slice(), patch: { ...patch } };
    },
  };
}

/**
 * Apply a commit to a run record, in memory, with the same checks a database
 * constraint would enforce.
 *
 * Returns a NEW run object — callers that mutate the run they were handed make
 * a failed commit unrecoverable, because the in-memory copy has already moved
 * on from what storage holds.
 *
 * @returns {{ ok: true, run: object } | { ok: false, reason: string }}
 */
export function applyCommit(run, commit) {
  if (commit.expectedSeq !== run.seq) {
    return { ok: false, reason: 'stale-write', expected: commit.expectedSeq, actual: run.seq };
  }
  if (TERMINAL_STATUSES.includes(run.status) && commit.patch.status && commit.patch.status !== run.status) {
    return { ok: false, reason: 'run-already-finished' };
  }

  let seq = run.seq;
  for (const entry of commit.entries) {
    if (entry.seq !== seq + 1) return { ok: false, reason: 'non-sequential-entry', at: entry.seq };
    seq = entry.seq;
  }

  return {
    ok: true,
    run: {
      ...run,
      ...commit.patch,
      seq,
      entries: [...(run.entries || []), ...commit.entries],
    },
  };
}

// --- store contract -------------------------------------------------------

/**
 * The in-memory reference store.
 *
 * Its purpose is to be the executable definition of the contract a real store
 * must satisfy — and to be what the tests run against, so the runtime's
 * durability claims are proven rather than asserted. A Postgres store
 * implements the same four methods; `commit` becomes
 * `UPDATE runs SET … WHERE id = $1 AND seq = $2` plus an insert of the
 * entries, in one transaction, and returns `stale-write` when it updates zero
 * rows.
 */
export function createMemoryStore(options = {}) {
  const runs = new Map();
  let counter = 0;
  const prefix = options.idPrefix || 'run';

  return {
    async create(run) {
      if (run.changeId != null) {
        for (const existing of runs.values()) {
          if (existing.workflowId === run.workflowId && existing.changeId === run.changeId) return null;
        }
      }
      if (run.batchId != null) {
        for (const existing of runs.values()) {
          if (existing.workflowId === run.workflowId && existing.batchId === run.batchId) return null;
        }
      }
      if (run.scheduleOccurrence != null) {
        for (const existing of runs.values()) {
          if (existing.workflowId === run.workflowId && existing.scheduleOccurrence === run.scheduleOccurrence) return null;
        }
      }
      const runId = run.runId || `${prefix}_${++counter}`;
      const stored = { ...run, runId };
      runs.set(runId, JSON.parse(JSON.stringify(stored)));
      return JSON.parse(JSON.stringify(stored));
    },

    async load(runId) {
      const found = runs.get(runId);
      return found ? JSON.parse(JSON.stringify(found)) : null;
    },

    async commit(runId, commit) {
      const current = runs.get(runId);
      if (!current) return { ok: false, reason: 'no-such-run' };
      const applied = applyCommit(current, commit);
      if (!applied.ok) return applied;
      runs.set(runId, JSON.parse(JSON.stringify(applied.run)));
      return { ok: true, run: JSON.parse(JSON.stringify(applied.run)) };
    },

    /**
     * Runs a scheduler should wake. Reading only the header is the point: a
     * store can index `waiting.wakeAt` and never deserialize a definition.
     */
    async due(now, limit = 100) {
      const out = [];
      for (const run of runs.values()) {
        if (run.status !== 'suspended' || !run.waiting) continue;
        if (run.waiting.kind === 'timer' && run.waiting.wakeAt <= now) out.push(JSON.parse(JSON.stringify(run)));
        else if (run.waiting.kind === 'signal' && run.waiting.timeoutAt && run.waiting.timeoutAt <= now) {
          out.push(JSON.parse(JSON.stringify(run)));
        }
        if (out.length >= limit) break;
      }
      return out;
    },

    async list() {
      return [...runs.values()].map((r) => JSON.parse(JSON.stringify(r)));
    },
  };
}

// --- determinism helpers --------------------------------------------------

/**
 * Read a clock value that stays the same across replays.
 *
 * First pass: calls the host clock and journals the answer. Every replay after
 * that: returns the journaled answer. Without this, a `delay` computed from
 * "now" would move on every restart and a run could postpone itself forever —
 * which is not a hypothetical, it is the standard way naive durable engines
 * fail.
 */
export function recordClock(key, index, commit, hostNow) {
  if (index.hasRecorded(key)) return index.recorded(key);
  const value = hostNow();
  commit.add('clock', { key, value });
  return value;
}

// A `recordRandom` twin of the above was written and removed: no step type
// generates randomness yet, and an export with no caller and no test is dead
// code however plausible its future looks. The `random` entry type stays in
// ENTRY_TYPES so adding one later is a two-line change rather than a journal
// migration.

/**
 * Summarize a run for a list view without shipping the whole journal.
 * A run that ran a 5,000-row foreach has a journal a UI must never load.
 */
export function summarizeRun(run) {
  const steps = (run.entries || []).filter((e) => e.type === 'step-completed').length;
  const failed = (run.entries || []).filter((e) => e.type === 'step-failed').length;
  return {
    runId: run.runId,
    workflowId: run.workflowId,
    status: run.status,
    mode: run.mode,
    startedAt: run.startedAt,
    finishedAt: run.finishedAt,
    durationMs: run.startedAt && run.finishedAt ? run.finishedAt - run.startedAt : null,
    stepsCompleted: steps,
    stepsFailed: failed,
    waiting: run.waiting ? { kind: run.waiting.kind, wakeAt: run.waiting.wakeAt ?? null, signal: run.waiting.signal ?? null } : null,
    error: run.error,
    entryCount: (run.entries || []).length,
  };
}
