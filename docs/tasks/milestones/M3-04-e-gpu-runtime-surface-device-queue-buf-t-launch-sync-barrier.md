# M3-04 — e.gpu runtime surface: Device, Queue, Buf[T], launch, sync, barriers, atomics, subgroups

| field | value |
|---|---|
| roadmap section | M3 — GPU |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> `e.gpu`: `Device`, `Queue`, `Buf[T]`, synchronous staging `upload`/`write`, asynchronous `launch[K]` with the compile-time pack check, in-order `release`, syncing `download`, `gpu.sync`, `grid1/2/3` as invocation counts, `gpu.barrier`, `gpu.memory_barrier`, `gpu.atomic_*` with scopes, the subgroup set, capability inference into the `.em` and the launch check — the implementation and documentation must match the exact `e.gpu` API fence in `module-apis.md`

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

## Module fences this bullet delivers

- `e.gpu` — `docs/tasks/modules/e.gpu.md`

## Code anchors

- `e.gpu`: `src/check.e`×6‡, `src/lower.e`×5‡, `lib/e/gfx/scene.e`×2†, `lib/e/gpu.e`×2†, `scripts/algos/decisions-pending.md`×2†, `src/resolve.e`×2†, `lib/e/gpu/tensor.e`×1, `lib/e/ui/app.e`×1†
- `Device`: `lib/e/gpu.e`×38†, `lib/e/gfx/scene.e`×2†, `lib/e/os.windows.e`×2‡, `lib/e/ui/input.e`×2, `lib/e/os/shell.windows.e`×1‡, `lib/e/ui/app.e`×1†, `lib/e/ui/window.e`×1
- `Queue`: `lib/e/gpu.e`×38†, `lib/e/concurrent/queue.e`×13, `lib/e/data/cache.e`×12, `lib/e/data/queue.e`×11, `lib/e/ui/input.e`×9, `lib/e/data/window.e`×7, `lib/e/db/pool.e`×5, `lib/e/gpu/tensor.e`×5
- `upload`: `lib/e/ui/asset.e`×8, `lib/e/gpu/tensor.e`×7, `lib/e/gpu.e`×2†, `lib/e/fmt/brotli.e`×1‡, `lib/e/gfx/image.e`×1, `lib/e/gfx/scene.e`×1†
- `download`: `lib/e/gpu.e`×4†, `lib/e/gpu/tensor.e`×3, `lib/e/fmt/brotli.e`×1‡
- `gpu.barrier`: `src/check.e`×5‡, `lib/e/gpu.e`×1†, `src/lower.e`×1‡
- `module-apis.md`: `scripts/check_module_surfaces.py`×5, `scripts/algos/add_batch.py`×3, `scripts/render_module_apis.py`×3, `scripts/render_progress.py`×2, `scripts/algos/reapply.sh`×1, `scripts/audit_repo_coverage.py`×1, `scripts/build-docs-pdf.py`×1, `scripts/check_gpu_contracts.py`×1
- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡, `src/codegen_x64.e`‡, `lib/e/simd.e`, `lib/e/thread.e`, `docs/m25-gpu-contracts.md`, `scripts/check_gpu_contracts.py` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
