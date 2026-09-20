# M4-05 — neper-format debug side table in .em

| field | value |
|---|---|
| roadmap section | M4 — Breadth and depth |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> neper-format debug side table in `.em` — types, locals, scopes, variable locations over the serialised type table — beside the standard subset, never instead of it (spec §13, D9)

**Done when:** every promised M4 target passes the applicable language/tooling corpus
and bidirectional C ABI fixtures; clean and incremental outputs remain deterministic;
the native debug path agrees with standard debugger locations on shared fixtures; and
GP-09/GP-10 have been rerun for every new applicable backend.

Predecessor: queue item C084 (`docs/tasks/compiler/`) delivers the M1 debug subset this builds on.

## Spec sections

- `docs/spec.md:4090` 13. Toolchain
  - `docs/spec.md:4205` Diagnostics
  - `docs/spec.md:4224` Program entry
  - `docs/spec.md:4264` Testing
  - `docs/spec.md:4428` Linking
  - `docs/spec.md:4496` Target CPU levels
  - `docs/spec.md:4553` Debug information
  - `docs/spec.md:4647` Editor integration
  - `docs/spec.md:4673` Standard library

## Code anchors

- nearest existing implementation: `src/em.e`‡, `src/binary.e`, `src/layout.e` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
