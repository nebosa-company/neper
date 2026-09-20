# C057 — Scoped concurrency and shared-state contracts (M2.5-core H04)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.88 of 1 |
| queue position | 15 of 54 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H04 — scoped concurrency and shared-state contracts** (track: M2.5-core (Language safety and GPU contracts, in_progress)):

The closure design for this requirement is `docs/m25-h04-concurrency.md`; read it after the section below.

Prefer scoped workers with a compiler-visible join obligation. A detached worker
must own its inputs or use explicitly valid long-lived shared storage. Borrowing a
stack frame for a detached task is rejected, including through an indirect callback.

Joining alone does not prevent races. A read-only pointer may alias another thread's
writer. Define thread transfer and sharing recursively, including pointer-bearing
containers, arena cursors, globals and callback environments. Checked code shares
either transitively immutable storage, atomics, or storage accessed through a
recognized lock capability. Raw shared access remains an unsafe obligation.

Lock guards must refer to the protected data/lock identity and cannot expose a
borrow that survives release. Specify reentrancy, moving guards, condition-variable
wait/reacquire and cancellation. Static lock checking does not prove deadlock
freedom or correct atomic ordering; expose those limitations and test protocols.

Joining on error paths must precede reset/cleanup of worker-visible state. A timeout
cannot safely release a worker's memory while it still runs. Define join errors,
partial spawn failure, cancellation acknowledgement and unresponsive workers.
Keep scheduling a library concern; no green-thread runtime is implied.

Acceptance: stack escape, shared mutable alias, wrong-lock access, guard escape,
worker arena sharing, early `try` with live workers and partial spawn failure.
Test valid disjoint partitions and synchronized mutation as well as negative cases.
Schedule perturbation is evidence over tested runs, not an exhaustive race proof.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> The design (`m25-h04-concurrency.md`, D365): the join obligation is H01's; a thread over this frame's storage cannot be detached, handed on, returned or stored past it (D357, E-SAFETY-0015); what a thread was given is lent to it until the join, read or written by nobody but through an address (D365, E-SAFETY-0016); a lock held as a value is a `sync.Guard` resource, released on every exit by H01's rule (D379); a pointer local bound from `&x` is followed, so a read or store through it while `x` is lent is refused (D393), and a thread start through that pointer alias lends the underlying frame storage too (D674); a thread context addressed through a local slice lends its known backing storage (D679), and one addressed through a tracked aggregate pointer field lends the pointed-to local rather than the carrier (D686), including the aggregate's second and later independently tracked pointer fields (D695, D700), recursively nested field paths (D705), comptime-indexed fixed-array pointer elements (D710), and every possible owner of a runtime-indexed element (D714); a read or a write lock held as a value is a `sync.ReadGuard` or `sync.WriteGuard`, each owed to its own release (D433); a `thread.Group` starts one thread per context, joins what it started when a start fails, and is one resource owed to `join_all` (D434); the compiler's crews and every fixture pass

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the protected data as a view of the guard
- [ ] aliases through externally sourced slices and globals
- [ ] a perturbation fixture

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D357` — A thread over this frame's storage is joined in this frame (`docs/decisions.md:7826`)
- `D365` — What a thread was given is the thread's until the join, and H04's design (`docs/decisions.md:8025`)
- `D379` — A lock held as a value: `sync.Guard` is a resource, and H01 is the lock discipline (`docs/decisions.md:8419`)
- `D393` — A pointer bound from `&x` is `x` by another name to the lending rule (`docs/decisions.md:8751`)
- `D433` — Read and write locks held as values (`docs/decisions.md:9581`)
- `D434` — A group of threads is one resource (`docs/decisions.md:9601`)
- `D674` — Thread starts follow local context pointer aliases (`docs/decisions.md:13089`)
- `D679` — Thread contexts through slices lend their known backing storage (`docs/decisions.md:13141`)
- `D686` — Thread contexts prefer the storage behind an aggregate pointer field (`docs/decisions.md:13207`)
- `D695` — Thread contexts resolve the second aggregate pointer field (`docs/decisions.md:13295`)
- `D700` — Thread contexts resolve later aggregate pointer fields (`docs/decisions.md:13349`)
- `D705` — Thread contexts resolve recursive aggregate alias paths (`docs/decisions.md:13401`)
- `D710` — Thread contexts resolve fixed-array element aliases (`docs/decisions.md:13449`)
- `D714` — Runtime array thread contexts lend every candidate owner (`docs/decisions.md:13488`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `join_all`: `lib/e/thread.e`×5, `tests/conformance/reject/safety_thread_group_leak.e`×2, `tests/conformance/reject/safety_thread_group_leak.expected.jsonl`×1

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
