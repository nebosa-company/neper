# M6-05 — pacman portable CLI with the toolchain's JSON conventions

| field | value |
|---|---|
| roadmap section | M6 — pacman package manager |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> Portable CLI: `init`, `add`, `remove`, `resolve`, `sync`, `upgrade`, `build`, `run`, `task`, `vendor`, `publish`, `cache`, and `info`, all with the toolchain's versioned JSON output conventions, shared diagnostic registry, deterministic record ordering and schema validation

**Done when:** GP-12 passes; the same manifest and signed registry snapshot resolve to
a byte-identical lockfile on Windows, Linux, macOS, and in a container; a clean cache
can be populated from the lock and then build byte-identically under
`sync --frozen --offline`; mutable Git refs cannot alter a locked sync; concurrent
syncs expose no partial entry; and neither transitive packages nor denied tasks can
execute code.

The normative design is `docs/pacman.md`; the `packageManifest` shape is already in `docs/schemas/neper-v1.schema.json`.

## Code anchors

- `task`: `benchmarks/llm_edit/jev_router.py`×22, `benchmarks/llm_edit/run.py`×17, `benchmarks/llm_edit/mega.py`×13, `benchmarks/llm_edit/semantic.py`×13, `benchmarks/llm_gen/run.py`×11, `benchmarks/llm_edit/README.md`×9, `benchmarks/llm_gen/README.md`×2
- `vendor`: `scripts/audit_repo_coverage.py`×2
- `publish`: `src/main.e`×3‡, `lib/e/math.e`×2†, `lib/e/algo/rand.e`×1, `lib/e/crypto/hash.e`×1, `lib/e/proc.e`×1, `lib/e/sync.e`×1
- nearest existing implementation: `docs/pacman.md`, `src/project.e`, `src/source.e`, `docs/schemas/neper-v1.schema.json`†, `lib/e/fmt/yaml.e`, `lib/e/crypto` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
