# M5-02 — Metal-only capabilities on the GPU profile

| field | value |
|---|---|
| roadmap section | M5 — Native Metal |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Metal-only capabilities exposed where they map onto the GPU profile

**Done when:** the Metal backend passes the same capability, ABI, source-map,
determinism and GP-10 correctness/ULP fixtures as the other applicable GPU backends,
and its published performance results satisfy the performance-language gate.

## Code anchors

- nearest existing implementation: `src/nir.e`†, `src/lower.e`‡ († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
