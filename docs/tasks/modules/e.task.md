# e.task — 20 of 20 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/task.e` |
| plan row | layer 4, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/task.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended host and application services:** `e.text.io`, `e.task`, `e.time.calendar`, `e.tz`, `e.fs.mmap`, `e.fs.watch`, `e.concurrent.queue`, `e.concurrent.map`, `e.debug`, `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `e.net`, `e.net.tls`, `e.net.http`, `e.net.ws`, `e.db`, `e.test.support`, `e.test.coverage` and `e.test.fuzz`. These build over the M1/M2 platform boundary and must demonstrate cancellation, backpressure, bounded buffers, partial I/O, deterministic shutdown and no hidden allocation or entropy. They unlock the GP-04 service workload.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.atomic` | source | `lib/e/atomic.e` | 0 |
| `e.cancel` | source | `lib/e/cancel.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.sync` | partial | `lib/e/sync.e` | 4 |
| `e.thread` | source | `lib/e/thread.e` | 4 |
| `e.time` | partial | `lib/e/time.e` | 4 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 4 may depend on layers [0, 1, 2, 3, 4].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Pool = struct { state: *void }
type Task = struct { state: *void }
type Future[T: type] = struct { state: *void }
type Cancel = cancel.Token
type Status = enum u8 { Pending, Running, Succeeded, Failed, Cancelled }
type Options = struct { workers: u32, queue_capacity: usize, stack_size: usize }
error Cancelled
error Closed
error Invalid

fn pool(a: *mem.Arena, options: Options) -> (Pool, err)
fn submit[Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> err) -> (Task, err)
fn future[T: type, Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> (T, err)) -> (Future[T], err)
fn status(t: *const Task) -> Status
fn wait(t: *Task) -> err
fn wait_for(t: *Task, timeout: time.Duration) -> (bool, err)
fn future_get[T: type](f: *Future[T]) -> (T, err)
fn wait_any(tasks: []*Task, timeout: time.Duration) -> (usize, bool, err)
fn wait_all(tasks: []*Task) -> err
fn parallel_for[Ctx: type](p: *Pool, cancel_token: *Cancel, begin: usize, end: usize, grain: usize, ctx: *Ctx, body: fn(*Ctx, usize, usize, *const Cancel) -> err) -> err
fn close(p: *Pool) -> err
```

The pool and all task records borrow their arena for the pool lifetime. Submission is
bounded and never allocates secretly. Cancellation is cooperative: queued work may
become `Cancelled`, while running work observes the shared e.cancel token; construct/request it through that module.
The Cancel alias preserves a named task parameter type, not a second token system. `close` rejects new work,
cancels queued work and joins every worker. `wait_all` returns the first error in
input order, not completion order. `parallel_for` partitions `[begin..end)` into
deterministic ranges no smaller than `grain` except the last; scheduling order is not
observable and callers synchronize shared state explicitly.

## Missing declarations

- [ ] `Pool`
- [ ] `Task`
- [ ] `Future`
- [ ] `Cancel`
- [ ] `Status`
- [ ] `Options`
- [ ] `Cancelled`
- [ ] `Closed`
- [ ] `Invalid`
- [ ] `pool`
- [ ] `submit`
- [ ] `future`
- [ ] `status`
- [ ] `wait`
- [ ] `wait_for`
- [ ] `future_get`
- [ ] `wait_any`
- [ ] `wait_all`
- [ ] `parallel_for`
- [ ] `close`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/async.e`
- `lib/e/atomic.e`
- `lib/e/audio.e`
- `lib/e/bytes.e`
- `lib/e/cancel.e`
- `lib/e/channel.e`
- `lib/e/cli.e`
- `lib/e/db.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/task.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/task/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 20.

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
