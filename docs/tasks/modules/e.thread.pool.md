# e.thread.pool — 4 of 33 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/thread/pool.e` |
| plan row | layer 4, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/thread/pool.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.atomic` | source | `lib/e/atomic.e` | 0 |
| `e.concurrent.queue` | partial | `lib/e/concurrent/queue.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.sync` | partial | `lib/e/sync.e` | 4 |
| `e.thread` | source | `lib/e/thread.e` | 4 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 4 may depend on layers [0, 1, 2, 3, 4].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Pool[Ctx: type] = struct { state: *void }
type State[Ctx: type] = struct { q: queue.Queue[u32], ctx: *Ctx, task: fn(*Ctx, u32), pending: Atomic[u32], lock: sync.Mutex, idle: sync.Condition, threads: []thread.Thread, started: usize, deps: []const u32, dep_starts: []const usize, indegree: []Atomic[u32], dag_nodes: usize }
type Fork[Ctx: type] = struct { ctx: *Ctx, leaf: fn(*Ctx, usize, usize), lo: usize, hi: usize, grain: usize }
type Deque = struct { items: []u32, top: Atomic[i64], bottom: Atomic[i64], mask: usize }
type Steal[Ctx: type] = struct { ctx: *Ctx, task: fn(*Ctx, u32), deques: []Deque, remaining: Atomic[u32], counts: []u32 }
type Thief[Ctx: type] = struct { pool: *Steal[Ctx], index: usize }
error Invalid
error Full
error TooSmall

fn state_of[Ctx: type](p: *Pool[Ctx]) -> *State[Ctx]
fn worker_main[Ctx: type](s: *State[Ctx])
fn finish_one[Ctx: type](s: *State[Ctx])
fn release_dependents[Ctx: type](s: *State[Ctx], id: u32)
fn submit_state[Ctx: type](s: *State[Ctx], id: u32) -> err
fn wait_idle[Ctx: type](s: *State[Ctx])
fn pool[Ctx: type](a: *mem.Arena, workers: usize, queue_capacity: usize, ctx: *Ctx, task: fn(*Ctx, u32)) -> (Pool[Ctx], err)
fn submit[Ctx: type](p: *Pool[Ctx], id: u32) -> err
fn try_submit[Ctx: type](p: *Pool[Ctx], id: u32) -> err
fn run[Ctx: type](p: *Pool[Ctx], ids: []const u32) -> err
fn shutdown[Ctx: type](p: *Pool[Ctx]) -> err
fn fork_task[Ctx: type](f: *Fork[Ctx], id: u32)
fn fork_join[Ctx: type](a: *mem.Arena, workers: usize, ctx: *Ctx, lo: usize, hi: usize, grain: usize, leaf: fn(*Ctx, usize, usize)) -> err
fn deque_push(d: *Deque, v: u32)
fn deque_take(d: *Deque) -> (u32, bool)
fn deque_steal(d: *Deque) -> (u32, bool)
fn steal_run[Ctx: type](s: *Steal[Ctx], index: usize, id: u32)
fn steal_main[Ctx: type](w: *Thief[Ctx])
fn work_stealing[Ctx: type](a: *mem.Arena, workers: usize, ctx: *Ctx, task: fn(*Ctx, u32), ids: []const u32, counts: []u32) -> err
fn run_dag[Ctx: type](p: *Pool[Ctx], deps: []const u32, dep_starts: []const usize, indegree: []Atomic[u32]) -> err
fn later(deadlines: []const u64, x: u32, y: u32) -> bool
fn sift(deadlines: []const u64, out: []u32, root: usize, end: usize)
fn edf_order(deadlines: []const u64, out: []u32) -> err
fn edf[Ctx: type](p: *Pool[Ctx], deadlines: []const u64, ids: []const u32, order: []u32) -> err
```

Task ids over one context type: `pool`, `submit`, `try_submit`, `run` (submit all and
wait), `shutdown`; `fork_join` (one-level range splitting), `work_stealing` (a private
Chase-Lev deque per worker with a remaining-count termination), `run_dag` (in-degrees
released by finishing tasks, cycles reported) and `edf`/`edf_order`.

## Missing declarations

- [ ] `Deque`
- [ ] `deque_push`
- [ ] `deque_take`
- [ ] `deque_steal`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/thread/pool.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/thread/pool.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/thread_pool/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 4.

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
