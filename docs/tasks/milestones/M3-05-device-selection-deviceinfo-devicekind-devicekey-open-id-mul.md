# M3-05 — Device selection: DeviceInfo/DeviceKind/DeviceKey, open_id, multi-device tests

| field | value |
|---|---|
| roadmap section | M3 — GPU |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Device selection: bounded `devices`, `DeviceInfo`/`DeviceKind`/`DeviceKey`, exact `open_id`, and opening-time `info` (spec §10, D83). Expose names, capacity and capabilities without treating ordinals as persistent IDs. Reject missing or ambiguous keys and cross-device handles; never silently choose a substitute. Test zero/one/many devices, duplicate names/keys, changed ordinals, hotplug, unsupported floors, arena/limit failure and simultaneous devices. CPU/Vulkan run in M3; CUDA/partition-identity cases run when M4 adds that backend. Require a hardware-gated two-device integration job; CPU mocks are supplemental evidence, not reported as multi-GPU hardware passes. GPU tests cannot silently CPU-fallback.

**Done when:** GP-09 and GP-10 pass on every backend available at M3, and every
kernel in the test suite that uses no approximate builtin —
the `e.math` transcendentals `sin cos tan asin acos atan atan2 exp exp2 log log2
log10 pow`, `math.rsqrt`, and the float `gpu.subgroup_add/min/max` reductions (spec
§11) — produces **bit-identical** output on the CPU backend and on a Vulkan device (linked with `--linker=system`,
above),
the `saxpy` kernel of `examples/saxpy.e` among them (the example is a program root
run as `neper run examples/saxpy.e`, spec §2; it runs on `.Cpu`, then on `.Vulkan`
when one is present, and prints both checksums); and every
kernel that uses one agrees within its stated ULP bound.
The performance-language gate is rerun whenever M4 or M5 adds an applicable CPU or
GPU backend; published comparisons use identical algorithms and report distributions,
compile time, runtime and memory rather than isolated best cases.

M2.5 froze the contracts this bullet implements: `docs/m25-gpu-contracts.md` and `docs/m25-gpu-contracts.json` (checked by `python scripts/check_gpu_contracts.py` and `tests/test_gpu_contracts.py`), `docs/m25-gpu-closure.md`. A device runtime test may not be reported as passing on a CPU mock. `libvulkan` needs M4's dynamic-import linking; until then a Vulkan program links with `--linker=system`.

## Spec sections

- `docs/spec.md:2628` 10. The GPU profile
  - `docs/spec.md:2646` Platforms
  - `docs/spec.md:2687` What runs where
  - `docs/spec.md:2709` Restrictions inside `@gpu`
  - `docs/spec.md:2729` Kernels and workgroups
  - `docs/spec.md:2790` Device types and slices
  - `docs/spec.md:2881` Shared memory
  - `docs/spec.md:2916` Barriers, memory ordering and atomics
  - `docs/spec.md:2964` Subgroups
  - `docs/spec.md:2999` Capabilities
  - `docs/spec.md:3048` Host side
  - `docs/spec.md:3147` Device discovery and selection
  - `docs/spec.md:3291` Queues and synchronisation
  - `docs/spec.md:3382` CPU execution model

## Decisions to read first

- `D83` — Explicit multi-GPU discovery and selection (`docs/decisions.md:106`)

## Module fences this bullet delivers

- `e.gpu` — `docs/tasks/modules/e.gpu.md`

## Code anchors

- `devices`: `lib/e/gpu.e`×7, `scripts/check_gpu_contracts.py`×1
- `DeviceInfo`: `lib/e/gpu.e`×6
- `DeviceKind`: `lib/e/gpu.e`×2
- `DeviceKey`: `lib/e/gpu.e`×3
- `open_id`: `lib/e/gpu.e`×1
- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡, `src/codegen_x64.e`‡, `lib/e/simd.e`, `lib/e/thread.e`, `docs/m25-gpu-contracts.md`, `scripts/check_gpu_contracts.py` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
