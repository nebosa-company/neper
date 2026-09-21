# T2-2 — Tooling v2 edit and test evidence (T2.2)

| field | value |
|---|---|
| roadmap section | T2 — agent tooling v2 |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> transactional semantic plans, structured tests, change contracts, flaky-test semantics, runtime failures and compatibility diffs (H09/H17/H29/H32/H35/H39/H41/H42). It may produce a receipt-shaped evidence package, but without T2.3 trust evidence its terminal state is `incomplete`, never `verified`.

**Done when:** the frozen tooling-v2 schema and conformance corpus pass; all required
T2 capabilities are discoverable; compiler, runner and host ownership boundaries are
executable; restart/retrieval and security fixtures pass; and the canonical workflow
can produce and independently validate a scoped receipt. Comparative leadership is
not a T2 completion condition.

Requirements: `H09` — diagnosis, recovery and transactional repair (`docs/post-m2-llm-hardening.md`), `H17` — semantic search and safe change planning (`docs/post-m2-llm-hardening.md`)

The v1 precursors already in the queue (`docs/tasks/compiler/`, titles ending 'precursor for T2 Hxx') are inputs to this slice, not its closure. `docs/tooling-v2-draft.md` is the protocol draft; `docs/hardening-tracks.json` carries the track status.

## Code anchors

- `incomplete`: `scripts/check_gpu_contracts.py`×11, `lib/e/math/special.e`×6, `benchmarks/llm_edit/jev_router.py`×1, `scripts/algos/decisions-pending.md`×1, `scripts/check_module_surfaces.py`×1, `src/main.e`×1‡
- `verified`: `src/tool.e`×13‡, `src/main.e`×9‡, `scripts/render_card.py`×8, `src/nir.e`×5†, `src/em.e`×4‡, `scripts/algos/decisions-pending.md`×2, `tests/conformance/tools/catalog_verified.x64-linux.expected.jsonl`×2, `tests/conformance/tools/catalog_verified.x64-windows.expected.jsonl`×2
- nearest existing implementation: `src/tool.e`‡, `src/main.e`‡, `docs/tooling.md`, `docs/tooling-v2-draft.md`, `docs/schemas/neper-v1.schema.json`†, `tests/conformance/tools` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
