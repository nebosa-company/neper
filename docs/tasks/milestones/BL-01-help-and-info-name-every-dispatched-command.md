# BL-01 — `--help` and `info` name every dispatched command

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **`--help` and `info` name every dispatched command (D469, spec §1 NFR 1).** There is no `--help`; the two `E-CLI-9999` usage texts disagree with each other and omit some twenty commands the dispatcher accepts. One usage text shared by `--help`, `-h`, `help` and both error sites, `info.commands` widened to the same set, and a conformance check that the three agree with the dispatcher.

## Spec sections

- `docs/spec.md:18` 1. What neper is
  - `docs/spec.md:25` Who writes neper
  - `docs/spec.md:39` Goals
  - `docs/spec.md:55` Non-goals
  - `docs/spec.md:66` Non-functional requirements
  - `docs/spec.md:77` The name

## Decisions to read first

- `D469` — Every dispatched command is in `--help` and `info` (`docs/decisions.md:10185`)

## Code anchors

- `E-CLI-9999`: `src/main.e`×24‡, `src/tool.e`×10‡, `tests/conformance/tools/batch.x64-linux.expected.jsonl`×2, `tests/conformance/tools/batch.x64-windows.expected.jsonl`×2, `tests/conformance/tools/catalog_unavailable.expected.jsonl`×1, `tests/conformance/tools/info_version.expected.jsonl`×1, `tests/conformance/tools/plan_parameter_refused.expected.jsonl`×1, `tests/conformance/tools/plan_rename_protocol_refused.expected.jsonl`×1
- nearest existing implementation: `src/main.e`‡, `tests/conformance/tools/info_version` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
