# BL-07 — A TextMate grammar

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **A TextMate grammar.** The one editor-side item that earns its keep: a `neper.tmLanguage.json` generated from `grammar.ebnf` by a script beside `render_progress.py`, so the keyword list, the literal suffixes and the `//` trivia rule cannot drift from the parser. Lands in VS Code, Helix, Zed and GitHub as-is; no extension code, no runtime, no LSP (which stays deliberately not scheduled). Checked by tokenising the conformance corpus and comparing scope spans against `tokens --json`.

## Code anchors

- `grammar.ebnf`: `scripts/render_card.py`×5, `scripts/build-docs-pdf.py`×1, `src/tool.e`×1‡
- `render_progress.py`: `scripts/render_progress.py`×2, `scripts/algos/reapply.sh`×1
- nearest existing implementation: `docs/grammar.ebnf`, `scripts/render_card.py`, `tests/conformance/tokens` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
