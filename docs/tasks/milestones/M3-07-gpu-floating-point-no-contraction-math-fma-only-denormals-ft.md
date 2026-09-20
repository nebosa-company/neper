# M3-07 — GPU floating point: no contraction, math.fma only, denormals, ftz opt-in

| field | value |
|---|---|
| roadmap section | M3 — GPU |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Floating point (spec §11, D39): no contraction anywhere, `math.fma` the only FMA, denormals preserved, `@gpu(..., ftz)` as the opt-in

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

- `docs/spec.md:3464` 11. Build modes and safety
  - `docs/spec.md:3519` Trap protocol
  - `docs/spec.md:3577` Resources: static rules
  - `docs/spec.md:3836` Debug fills
  - `docs/spec.md:3849` Floating point

## Decisions to read first

- `D39` — Floating point (`docs/decisions.md:61`)

## Module fences this bullet delivers

- `e.gpu` — `docs/tasks/modules/e.gpu.md`

## Code anchors

- `math.fma`: `lib/e/simd.e`×1
- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡, `src/codegen_x64.e`‡, `lib/e/simd.e`, `lib/e/thread.e`, `docs/m25-gpu-contracts.md`, `scripts/check_gpu_contracts.py` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
