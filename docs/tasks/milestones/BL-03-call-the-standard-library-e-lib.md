# BL-03 — Call the standard library `e.lib`

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **Call the standard library `e.lib`.** The prose says "the standard library", "stdlib" (`stdlib-hardening.md`), "core library" and "the library" for the one thing, the `e.*` modules under `lib/e`. Adopt `e.lib` as the name everywhere a document names it -- spec §1 and §2, `modules.md`, `module-apis.md`, `tooling.md`, the README, `render_progress.py`'s row text -- and keep file names as they are. A docs-only sweep; a D-row records the term.

## Spec sections

- `docs/spec.md:18` 1. What neper is
  - `docs/spec.md:25` Who writes neper
  - `docs/spec.md:39` Goals
  - `docs/spec.md:55` Non-goals
  - `docs/spec.md:66` Non-functional requirements
  - `docs/spec.md:77` The name

## Code anchors

- `e.lib`: `src/nir.e`×5†, `src/em.e`×2‡, `src/lower.e`×2‡, `src/em_link.e`×1†
- `stdlib-hardening.md`: `benchmarks/llm_edit/README.md`×1, `lib/e/cancel.e`×1
- `lib/e`: `src/assets.e`×6, `scripts/build-bootstrap.sh`×4, `scripts/algos/agent_brief.md`×3, `scripts/render_progress.py`×3, `lib/e/os.linux.e`×2‡, `lib/e/os.windows.e`×2‡, `scripts/check_module_surfaces.py`×2, `src/check.e`×2‡
- `modules.md`: `lib/e/os.linux.e`×1‡, `lib/e/os.windows.e`×1‡, `scripts/build-docs-pdf.py`×1
- `module-apis.md`: `scripts/check_module_surfaces.py`×5, `scripts/algos/add_batch.py`×3, `scripts/render_module_apis.py`×3, `scripts/render_progress.py`×2, `scripts/algos/reapply.sh`×1, `scripts/audit_repo_coverage.py`×1, `scripts/build-docs-pdf.py`×1, `scripts/check_gpu_contracts.py`×1
- `tooling.md`: `src/main.e`×3‡, `src/tool.e`×3‡, `scripts/build-docs-pdf.py`×1
- `render_progress.py`: `scripts/render_progress.py`×2, `scripts/algos/reapply.sh`×1
- nearest existing implementation: `docs/spec.md`, `docs/modules.md`, `docs/module-apis.md`, `docs/tooling.md`, `scripts/render_progress.py` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
