# M4-08 — Optimiser depth: inlining heuristics, load/store forwarding, scheduling

| field | value |
|---|---|
| roadmap section | M4 — Breadth and depth |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Optimiser depth: better inlining heuristics, load/store forwarding, scheduling; cross-`.em` inlining stays under the M2 cap; a vector register class whose ABI is section 5's `xmm`/`ymm` convention for `Vec`/`Mask` (D786, D1524), measured against GP-09 once that workload exists

**Done when:** every promised M4 target passes the applicable language/tooling corpus
and bidirectional C ABI fixtures; clean and incremental outputs remain deterministic;
the native debug path agrees with standard debugger locations on shared fixtures; and
GP-09/GP-10 have been rerun for every new applicable backend.

## Decisions to read first

- `D786` — `Vec`/`Mask` cross a call by copied storage until there is a vector register class (`docs/decisions.md:14930`)

## Code anchors

- `Mask`: `lib/e/simd.e`×22, `src/check.e`×17‡, `scripts/khronos/glcorearb.h`×12‡, `lib/e/gfx/dwtext.e`×9, `lib/x/khronos/gl.e`×6‡, `scripts/khronos/gl32.h`×6‡, `src/main.e`×5‡, `lib/e/gfx/chart.e`×3‡
- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡, `src/regalloc.e`†, `src/em_link.e`† († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
