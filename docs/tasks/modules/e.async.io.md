# e.async.io — 18 of 18 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/async/io.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `e.task` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/async/io.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended host and application services:** `e.text.io`, `e.task`, `e.time.calendar`, `e.tz`, `e.fs.mmap`, `e.fs.watch`, `e.concurrent.queue`, `e.concurrent.map`, `e.debug`, `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `e.net`, `e.net.tls`, `e.net.http`, `e.net.ws`, `e.db`, `e.test.support`, `e.test.coverage` and `e.test.fuzz`. These build over the M1/M2 platform boundary and must demonstrate cancellation, backpressure, bounded buffers, partial I/O, deterministic shutdown and no hidden allocation or entropy. They unlock the GP-04 service workload.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.async` | partial | `lib/e/async.e` | 6 |
| `e.cancel` | source | `lib/e/cancel.e` | 4 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.task` | planned | missing | 4 |
| `e.time` | partial | `lib/e/time.e` | 4 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Op[T: type] = struct { state: *void }
type AnyOp = struct { state: *void }
type State = enum u8 { Pending, Succeeded, Failed, Cancelled, TimedOut }
error Cancelled
error Timeout
error Closed

fn read(a: *mem.Arena, loop: *async.Loop, source: io.Reader, dst: []u8, control: cancel_api.Control) -> (Op[usize], err)
fn write(a: *mem.Arena, loop: *async.Loop, sink: io.Writer, src: []const u8, control: cancel_api.Control) -> (Op[usize], err)
fn accept(a: *mem.Arena, loop: *async.Loop, listener: os.Socket, control: cancel_api.Control) -> (Op[os.Socket], err)
fn connect(a: *mem.Arena, loop: *async.Loop, socket: os.Socket, address: os.SocketAddress, control: cancel_api.Control) -> (Op[bool], err)
fn state[T: type](op: *const Op[T]) -> State
fn erase[T: type](op: *Op[T]) -> AnyOp
fn take[T: type](op: *Op[T]) -> (T, err)
fn wait[T: type](loop: *async.Loop, op: *Op[T]) -> (T, err)
fn wait_any(loop: *async.Loop, ops: []AnyOp, timeout: time.Duration) -> (usize, bool, err)
fn cancel[T: type](op: *Op[T]) -> (bool, err)
type Progress = struct { bytes: u64, known: bool }
fn progress[T: type](op: *const Op[T]) -> Progress

```

Submission never blocks and every operation completes exactly once. Buffers, handles,
contexts and cancellation tokens must outlive completion. Control uses e.cancel's explicit deadline flag. cancel returns whether it newly
requested cancellation; it does not acknowledge completion. A completed operation
wins a later cancellation request. Otherwise cancellation is cooperative and the
terminal state reports Cancelled/TimedOut with observable partial effects preserved.
No consumed bytes or transmitted bytes are silently reported as rolled back. `wait` drives
the supplied loop; applications may instead poll it directly. `take` consumes a
completed operation and returns its exact I/O error. `erase` is a non-owning typed
conversion used only to build a heterogeneous `wait_any` slice; the original `Op[T]`
must remain live.


Progress is a monotonic observation, not completion acknowledgement. Byte operations
report exact completed bytes at terminal state even on failure/cancellation; operations
without a byte metric report known=false. take remains mandatory to consume a terminal
operation. An uncancellable blocking callback cannot be advertised as promptly
cancellable: reject an incompatible submission or keep resources pinned until it ends.

## Missing declarations

- [ ] `Op`
- [ ] `AnyOp`
- [ ] `State`
- [ ] `Cancelled`
- [ ] `Timeout`
- [ ] `Closed`
- [ ] `read`
- [ ] `write`
- [ ] `accept`
- [ ] `connect`
- [ ] `state`
- [ ] `erase`
- [ ] `take`
- [ ] `wait`
- [ ] `wait_any`
- [ ] `cancel`
- [ ] `Progress`
- [ ] `progress`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/async/io.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/async_io/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 18.

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
