# M4-06 — Debug engine: process control, breakpoints, stepping, stack walking

| field | value |
|---|---|
| roadmap section | M4 — Breadth and depth |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Debug engine: process control, breakpoints, single-step, stack walking, location rendering

**Done when:** every promised M4 target passes the applicable language/tooling corpus
and bidirectional C ABI fixtures; clean and incremental outputs remain deterministic;
the native debug path agrees with standard debugger locations on shared fixtures; and
GP-09/GP-10 have been rerun for every new applicable backend.

Predecessor: queue item C084 (`docs/tasks/compiler/`) delivers the M1 debug subset this builds on.

## Code anchors

- nearest existing implementation: `lib/e/proc.e`, `lib/e/os.windows.e`‡, `lib/e/os.linux.e`‡, `src/disasm_x64.e`† († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
