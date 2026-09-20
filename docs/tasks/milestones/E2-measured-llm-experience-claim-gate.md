# E2 — Measured LLM-experience claim gate

| field | value |
|---|---|
| roadmap section | E2 — measured LLM-experience claim gate |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **Scheduled after the relevant T2 slices; never blocks M3 or later compiler/backend implementation.** The M2 baseline and some performance instrumentation already exist. They are inputs to E2, not a completed comparative claim. E2 owns H12, measured H20, H25, H33 and H43 plus the comparative acceptance clauses of H30–H34. It freezes workloads, models, tokenizers, environments, baselines, weights, oracles and statistical rules before candidate tuning; then reports correctness, escaped defects, latency, tokens, repair turns, runtime/resource distributions and performance obligations from complete trajectories. Two cohorts have different purposes. The **broad-generation cohort** is C, C++, Rust, Go, Python, Java and C# and measures general transfer without a leadership claim. The **registered agent-tooling cohort** is Go, Rust, TypeScript and Python and is the only cohort used by the five-category E2 comparison. Therefore every leadership statement is qualified as "among the registered agent-tooling cohort" and names its frozen manifest. “First or statistically tied for first” and “strictly better composite” govern only a versioned public claim tied to that benchmark manifest. A competitor, model or hardware change may expire or require rerunning the claim; it never reopens M2.5, T2, M3 or another completed implementation milestone. E2 evidence may propose a syntax or API spelling change but cannot authorize one. Adoption requires a separate versioned language/API milestone with normative edits, compatibility analysis and migration evidence; it is neither a T2 nor E2 closure condition and cannot move the language contract underneath concurrent M3 work.

**Done when:** H12/H20/H25/H33/H43 evidence and all comparative H30–H34 results are
reproducible, every failed/incomplete trajectory remains in the report, and the exact
claim is supported. If the thresholds miss, publish the result and keep the
superiority claim open without blocking implementation.

Requirements: `H12` — E2 evaluation and claim evidence, `H20` — compilation policy and generated-code performance, `H25` — reproducible performance and harness acceptance

## Code anchors

- nearest existing implementation: `benchmarks`, `tests/test_llm_edit_benchmark.py`, `docs/m2-baseline.md`, `docs/general-purpose-verification.md` († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
