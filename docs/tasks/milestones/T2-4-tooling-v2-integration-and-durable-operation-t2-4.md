# T2-4 — Tooling v2 integration and durable operation (T2.4)

| field | value |
|---|---|
| roadmap section | T2 — agent tooling v2 |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> implement H38/H44 in the same host: isolated parallel change bundles, integrated-snapshot revalidation and durable authorized tasks across reconnect, approval and cancellation. The compiler declares semantic facts and requested effects; the host owns authority, credentials, isolation, worktrees and durable lifecycle.

**Done when:** the frozen tooling-v2 schema and conformance corpus pass; all required
T2 capabilities are discoverable; compiler, runner and host ownership boundaries are
executable; restart/retrieval and security fixtures pass; and the canonical workflow
can produce and independently validate a scoped receipt. Comparative leadership is
not a T2 completion condition.

Requirements: 

The v1 precursors already in the queue (`docs/tasks/compiler/`, titles ending 'precursor for T2 Hxx') are inputs to this slice, not its closure. `docs/tooling-v2-draft.md` is the protocol draft; `docs/hardening-tracks.json` carries the track status.

## Code anchors

- nearest existing implementation: `src/tool.e`‡, `src/main.e`‡, `docs/tooling.md`, `docs/tooling-v2-draft.md`, `docs/schemas/neper-v1.schema.json`†, `tests/conformance/tools` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
