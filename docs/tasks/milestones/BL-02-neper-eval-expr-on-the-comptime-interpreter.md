# BL-02 — `neper eval EXPR` on the comptime interpreter

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **`neper eval EXPR` on the comptime interpreter (D470).** Once the M1 interpreter bullet reaches spec §9 -- structs, slices, strings and the arena -- `eval` is a `const` initialiser folded and printed: no codegen, no link, the comptime ceiling by design. No runtime interpreter, no REPL past this.

## Spec sections

- `docs/spec.md:2174` 9. Compile-time parameters
  - `docs/spec.md:2266` Compile-time evaluation
  - `docs/spec.md:2338` Protocols
  - `docs/spec.md:2468` Compile-time introspection
  - `docs/spec.md:2590` Argument packs

## Decisions to read first

- `D470` — No runtime interpreter; `eval` rides the comptime one (`docs/decisions.md:10201`)

## Code anchors

- nearest existing implementation: `src/check.e`‡, `src/main.e`‡ († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
