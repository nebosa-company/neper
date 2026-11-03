# e.gpu.cuda — 1 of 6 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/gpu/cuda.e` |
| plan row | layer 5, surface `partial`, milestone M3, schedule `scheduled` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/gpu/cuda.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 5 may depend on layers [0, 1, 2, 3, 4, 5].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error NoLoader
error NoDevice
error Failed

type Physical = struct { name: str, uuid: [16]u8, uuid_valid: bool, memory_bytes: u64, integrated: bool }

fn load(a: *mem.Arena) -> err
fn devices(a: *mem.Arena, limit: usize) -> ([]Physical, err)
```

CUDA device enumeration under `e.gpu` (C093, D4705): the driver library (`nvcuda.dll`,
`libcuda.so.1`) opened at run time through `os.dlopen` and `cuInit`, `cuDeviceGetCount`,
`cuDeviceGet`, `cuDeviceGetName`, `cuDeviceGetUuid`, `cuDeviceTotalMem_v2` and
`cuDeviceGetAttribute` through `os.dlsym`, so a program that never asks for a `.Cuda` device
needs no NVIDIA driver. `devices` is `NoLoader` without the library or `cuInit`, `NoDevice` with a
driver and no device, and otherwise the first `limit` devices with the name the driver gives,
the sixteen-byte `cuDeviceGetUuid` (valid when not all zero; on a GPU that also has a Vulkan
driver these are the bytes of its Vulkan `deviceUUID`), total memory and whether the device
is integrated. There is no CUDA compute backend (M4): `e.gpu.devices(.Cuda, ...)` reports these
with `supported` false, `open_id` of a present key is `Unsupported`, of an absent one `NoDevice`.

## Missing declarations

- [ ] `load`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/gpu/cuda.e`
- `lib/e/gpu/metal.e`
- `lib/e/gpu/metal.macos.e`
- `lib/e/gpu/tensor.e`
- `lib/e/gpu/vulkan.e`†

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/gpu/cuda.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/gpu_cuda/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

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
