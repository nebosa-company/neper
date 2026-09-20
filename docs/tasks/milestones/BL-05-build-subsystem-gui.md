# BL-05 — `build --subsystem gui`

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **`build --subsystem gui`.** The PE emitter hard-codes subsystem 3 (console); the first windowed app wants 2 so no console window opens. One constant behind one flag, recorded in the build manifest.

## Code anchors

- nearest existing implementation: `src/link_pe.e`, `src/main.e`‡ († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
