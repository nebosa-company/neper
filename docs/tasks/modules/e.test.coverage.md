# e.test.coverage — 8 of 8 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/test/coverage.e` |
| plan row | layer 5, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/test/coverage.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended host and application services:** `e.text.io`, `e.task`, `e.time.calendar`, `e.tz`, `e.fs.mmap`, `e.fs.watch`, `e.concurrent.queue`, `e.concurrent.map`, `e.debug`, `e.metrics`, `e.log`, `e.cli`, `e.async`, `e.async.io`, `e.net`, `e.net.tls`, `e.net.http`, `e.net.ws`, `e.db`, `e.test.support`, `e.test.coverage` and `e.test.fuzz`. These build over the M1/M2 platform boundary and must demonstrate cancellation, backpressure, bounded buffers, partial I/O, deterministic shutdown and no hidden allocation or entropy. They unlock the GP-04 service workload.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.test` | source | `lib/e/test.e` | 5 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 5 may depend on layers [0, 1, 2, 3, 4, 5].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Counter = struct { file_id: u32, region_id: u32, hits: u64 }
type Report = struct { counters: []const Counter }
error InvalidProfile
error TooLarge

fn snapshot(dst: []Counter) -> ([]Counter, err)
fn reset()
fn merge(a: *mem.Arena, profiles: []const Report) -> (Report, err)
fn write_json(writer: *io.Writer, report: *const Report) -> err
```

The compiler assigns stable file and region identifiers and owns instrumentation.
This runtime only snapshots, resets, merges and serializes bounded counters.

## Missing declarations

- [ ] `Counter`
- [ ] `Report`
- [ ] `InvalidProfile`
- [ ] `TooLarge`
- [ ] `snapshot`
- [ ] `reset`
- [ ] `merge`
- [ ] `write_json`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/test/support.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/test/coverage.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/test_coverage/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 8.

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
