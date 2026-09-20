# e.gpu.tensor — 7 of 7 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gpu/tensor.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gpu/tensor.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental collection conveniences:** `e.data.stack`, `e.data.queue` and `e.data.linked` remain available for workload evaluation but have no compatibility promise. `e.gpu.tensor` is likewise experimental, follows both M3 `e.gpu` and extended `e.algo.linalg.tensor`, and keeps every operation as an explicit queue submission. Promotion requires an applicable general-purpose workload and a recorded compatibility decision.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.linalg.tensor` | partial | `lib/e/algo/linalg/tensor.e` | 2 |
| `e.gpu` | partial | `lib/e/gpu.e` | 5 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Tensor[T: type] = struct { data: gpu.Buf[T], shape: []const usize, stride: []const usize }
error Shape

fn upload[T: type](a: *mem.Arena, queue: *gpu.Queue, src: linalg_tensor.ConstTensor[T]) -> (Tensor[T], err)
fn download[T: type](queue: *gpu.Queue, src: Tensor[T], dst: linalg_tensor.Tensor[T]) -> err
fn add[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err
fn matmul[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err
fn release[T: type](queue: *gpu.Queue, tensor_view: Tensor[T]) -> err
```

The import of `e.algo.linalg.tensor` uses the deterministic alias `linalg_tensor`.
Every operation is an explicit queue submission; this module never opens a device or
allocates a host arena implicitly.

## Missing declarations

- [ ] `Tensor`
- [ ] `Shape`
- [ ] `upload`
- [ ] `download`
- [ ] `add`
- [ ] `matmul`
- [ ] `release`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gpu/tensor.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gpu_tensor/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 7.

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
