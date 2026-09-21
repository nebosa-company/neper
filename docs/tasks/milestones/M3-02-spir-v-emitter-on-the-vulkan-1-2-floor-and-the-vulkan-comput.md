# M3-02 — SPIR-V emitter on the Vulkan 1.2 floor and the Vulkan compute runtime

| field | value |
|---|---|
| roadmap section | M3 — GPU |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> SPIR-V emitter on the Vulkan 1.2 floor — `PhysicalStorageBuffer64`, scalar block layout, `NoContraction` on every result, correctly rounded division and square root sequences; Vulkan compute runtime written over `extern` (spec §5, D32). Its `libvulkan` import needs the M4 dynamic-import linking stage, so a program that opens a `.Vulkan` (or, once the PTX emitter exists, a `.Cuda`) device links under `--linker=system` until that stage lands (spec §13)

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

- `docs/spec.md:971` 5. Declarations
  - `docs/spec.md:987` Attributes
  - `docs/spec.md:1050` Local initialisers
  - `docs/spec.md:1073` Functions
  - `docs/spec.md:1109` Multiple return values
  - `docs/spec.md:1174` External functions
  - `docs/spec.md:1272` `e.os`
- `docs/spec.md:4185` 13. Toolchain
  - `docs/spec.md:4300` Diagnostics
  - `docs/spec.md:4319` Program entry
  - `docs/spec.md:4359` Testing
  - `docs/spec.md:4523` Linking
  - `docs/spec.md:4591` Target CPU levels
  - `docs/spec.md:4648` Debug information
  - `docs/spec.md:4742` Editor integration
  - `docs/spec.md:4768` Standard library

## Decisions to read first

- `D32` — Foreign functions (`docs/decisions.md:54`)

## Module fences this bullet delivers

- `e.gpu` — `docs/tasks/modules/e.gpu.md`

## Code anchors

- `.Vulkan`: `lib/e/gpu.e`×1
- `.Cuda`: `lib/e/gpu.e`×1
- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡, `src/codegen_x64.e`‡, `lib/e/simd.e`, `lib/e/thread.e`, `docs/m25-gpu-contracts.md`, `scripts/check_gpu_contracts.py` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
