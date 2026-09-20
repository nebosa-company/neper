# C047 — Bounded tooling lifetimes and responsiveness (v1 precursor for T2 H16)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.80 of 1 |
| queue position | 9 of 54 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H16 — bounded tooling lifetimes and responsiveness** (track: T2.0 (Tooling foundations, open)):

**T2 tooling-v2 delivery: explicit lifetimes, accounting and verified reclamation.** Spec
§15's process-exit reclamation remains appropriate for one-shot work, not a blanket
policy for reusable query sessions. This extends H10 without mandating a daemon.

- Separate request arenas, snapshot storage and evictable reusable caches. Define
  who pins a snapshot, when a pin expires/releases, and what a stale handle returns.
  Never evict storage still referenced by an active query or edit plan.
- Implement bounded multi-request/batch reuse. Add a persistent transport only if
  H25 startup/reparse measurements justify it; record the decision either way.
  A selected persistent implementation must satisfy the same reclamation tests.
- Account for total source/IR storage, workers, outstanding requests, generic and
  comptime work, diagnostic bytes and artifact buffers. Per-evaluation limits do
  not bound thousands of simultaneous individually legal evaluations.
- Define cancellation checkpoints, outstanding work disposal and cache publication
  boundaries. Deadlines are distinct from deterministic work budgets. An aborted
  check cannot leave a successful snapshot or an inferred empty dependency set.
- Prefer a scheduler with explicit memory/backpressure limits over automatically
  launching one memory-heavy task per logical core. Measure dependency critical
  paths, queue wait and peak aggregate allocation before changing worker defaults.

Acceptance: at least 10,000 edit/query/revert cycles under a fixed cache budget;
eviction with pinned/unpinned snapshots; cancelled generics/checks; worker failures;
queued-request saturation and repeated allocation failure. Report retained memory
after warmup and reclamation, not just process-exit memory. H25 sets named latency
and memory limits before tuning; allocator reservation and live allocations are
reported separately.

The batch transport now exposes the first reusable accounting slice (D558): live
and reserved arena bytes, the checked snapshot, the session baseline after loading
the batch, and peak temporary request bytes. The before/after fixture proves that a
nonzero peak is reclaimed to the same retained baseline. Eviction, pinning and the
full edit/query/revert fixed-budget acceptance remain open.

The fixed-budget batch soak now runs ten thousand context queries against one checked
snapshot on both hosts (D559). Its final memory report counts all ten thousand,
records a nonzero temporary peak, and has returned exactly to the original session
baseline. Edit/revert cycling, eviction and pinning remain open.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> One process per query over one snapshot, reclaimed at exit -- measured and kept (D372); `--stats` accounts arena high-water, peak resident set, per-phase time and worker bytes (D311, D338); limits are named codes, not crashes (D344); the baseline's memory budgets and the gate (D366); `--deadline MS` cancels a build with one diagnostic, exit 3 and no published image or manifest (D399), with checkpoints between modules (D422), functions (D441, D442), interpreter steps (D496) and statements during checking/lowering (D540). `query-batch` reuses one check while reclaiming each request arena (D409, D410). Its memory report now separates live and reserved bytes, checked snapshot, session baseline and peak temporary request allocation (D558); both suites run ten thousand context queries against one snapshot, count every completion and prove the nonzero request peak is reclaimed exactly to the fixed session baseline (D559)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] pinned snapshots and eviction
- [ ] edit/revert cycling
- [ ] a backpressure scheduler (the worker default is eight, measured at four on the largest workload)

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D311` — `os.peak_memory` and `os.wait_usage`: the two `--stats` rows that read n/a (`docs/decisions.md:6348`)
- `D338` — The M2 baseline: the compiler preserved before post-M2 tracks touch it (`docs/decisions.md:7195`)
- `D344` — A failure that reaches the top is a diagnostic, and the stream still ends (`docs/decisions.md:7393`)
- `D366` — The performance gate: a measurement judged against the budgets (`docs/decisions.md:8050`)
- `D372` — No persistent server before the measurement says so: H10 and H16 dispositions (`docs/decisions.md:8217`)
- `D399` — `--deadline MS`: a build is cancelled at the next checkpoint between phases (`docs/decisions.md:8878`)
- `D409` — `query-batch`: many queries, one check (`docs/decisions.md:9114`)
- `D410` — A batch line is a request of its own, and the arena says so (`docs/decisions.md:9138`)
- `D422` — A worker checks the deadline between its modules (`docs/decisions.md:9372`)
- `D441` — The deadline is read between functions (`docs/decisions.md:9717`)
- `D442` — The lowering reads the deadline between functions too (`docs/decisions.md:9732`)
- `D496` — The deadline inside an evaluation (`docs/decisions.md:10636`)
- `D540` — The deadline inside a function (`docs/decisions.md:11241`)
- `D558` — Retained memory after warmup (`docs/decisions.md:11532`)
- `D559` — Ten thousand reclaimed queries (`docs/decisions.md:11549`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `query-batch`: `src/main.e`×6‡, `benchmarks/metamorphic/reorder_parameters.py`×1, `scripts/render_card.py`×1, `tests/conformance/tools/batch_broken.expected.jsonl`×1

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
