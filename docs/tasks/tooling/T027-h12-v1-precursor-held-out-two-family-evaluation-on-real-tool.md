# T027 — H12 v1 precursor: held-out two-family evaluation on real tools

| field | value |
|---|---|
| category | tooling / Tooling |
| score | 0.05 of 1 |
| queue position | 49 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H12 — E2 evaluation and claim evidence** (track: E2 (Measured LLM-experience claim, open)):

Extend [the verification plan](general-purpose-verification.md#4-llm-generation-evaluation)
and [the editing benchmark](../benchmarks/llm_edit/README.md). Existing synthetic
search/edit corpora measure navigation and edit precision. Regex/oracle success
and a synthetic index do not establish compilation, lifetime safety or behavioral
correctness. Million-line filler does not replace a real dependency graph.

Required task strata:

| Stratum | Cases and oracle |
|---|---|
| Local generation/editing | Parse, check, formatter and independent behavioral tests |
| Nonlocal change | Cross-module signature, resource ownership and borrow-result migration; resolved references and tests |
| Temporal defects | Reset/growth, consume/close, alias mutation and error-path cleanup; negative/positive pairs |
| Concurrency | Scoped/detached lifetime, lock contracts, shared aliases and shutdown; static outcomes plus schedules |
| Semantic context | Protocol fallback, generic phase, build policy, unsafe boundary and indirect-call unknowns |
| Broken/adversarial input | Truncation, stale patches, incomplete index, huge diagnostics, deceptive comments and malformed tool data |
| Long-running behavior | Repeated requests/builds, bounded memory and handles, cancellation and partial failure |
| Compiler correctness | Differential execution, IR verification and clean/incremental/parallel artifact equality |

Before altering the compiler, archive the M2 executable, source revision, schema,
cards, prompts, fixtures, environment and baseline results. Pre-register the held-out
task set and decision criteria before inspecting candidate results. Use at least
two independently trained model families with fixed model versions/settings and
three runs per task. Model names/versions and tokenizer identities belong in reports,
not permanent language rules. Do not pool families to hide one failing family.

For statistical thresholds use at least 200 distinct local-edit tasks and 200
compiler-error repair tasks per family, distributed across applicable strata;
seeds and repetitions of one template are not independent tasks. Report task-level
confidence intervals and raw counts. These sample sizes are a minimum evidence
floor, not proof of universal performance or absence of rare failures.

Run three controlled arms: M2 baseline, revised compiler with equivalent minimal
guidance, and revised compiler with context/repair tools. Where feasible isolate
individual H changes. Compare equivalent C, C++, Rust, Go, Python, Java and C#
tasks only where the language supports the workload; report exclusions. Give each
language its real compiler, native semantic tools and equivalent access budgets.
Do not invent a Neper feature such as re-exports to make a comparison symmetrical.
This is the **broad-generation cohort** and characterizes transfer; it does not support
a leadership claim. The separate **registered agent-tooling cohort** is Go, Rust,
TypeScript and Python and alone supports the five-category E2 claim.

Required E2 claim gate:

1. On supported CPU tasks, each model family meets the existing thresholds: 95%
   first-pass local-edit parsing, 90% first-pass type checking, median unrelated
   formatted diff zero, and 95% repair within one additional turn. No accepted task
   needs human-output scraping or undocumented compiler behavior.
2. Every applicable fixed CPU/tooling conformance fixture passes; design-only GPU
   cases satisfy their explicit M2.5-core design obligations instead
   of being reported as runtime passes. All planted violations inside
   a promised checked guarantee are rejected or trapped as specified; valid paired
   fixtures pass. No known miscompilation or missed guaranteed violation remains.
   Unknown/unsafe cases are reported separately and never counted as proved safe.
3. Every model-produced patch counted as accepted passes independent behavioral
   tests and the applicable safety/resource checks. Report overall completion rate,
   first-pass test rate, false rejection, defect escape and unsafe/error-suppression
   introduction by stratum. Aborted tasks, retries, timeouts and failures retain
   their token/time costs in the totals.
4. Demonstrate a reduction in total tokens per verified success or repair turns on
   the held-out context-sensitive CPU tasks in both families, without an unexplained
   loss of verified completion. Publish paired effects and uncertainty; if evidence
   is inconclusive, expand the held-out evaluation rather than assert superiority.
5. Report p50/p95 cold/warm compiler and query latency, peak memory, code size and
   runtime, including an ablation for retained checks. Freeze workload-specific
   performance budgets from the M2 baseline before tuning. Any exceeded budget
   requires a documented tradeoff decision; safety obligations cannot be waived
   to meet the speed budget.

Use GP-01 plus the applicable M2 CPU workloads and minimal direct-FFI fixtures.
Do not require unfinished M3 GPU, M4 dynamic-linker, M6 package or later networking
implementations to close this gate. The broader general-purpose gate still waits
for its own prerequisites and reruns these tests as new capabilities arrive.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> post-m2-llm-hardening.md section 15 specifies the only evidence that can support a superiority claim -- correctness first, then total interaction tokens per verified success, repair turns and source-token pressure, 20 seeds per case, Neper's own tools against each baseline's native ones, rank first or statistically tied or expand rather than assert -- and nothing in this queue schedules it. benchmarks/llm_edit/neper_advantage_matrix.md and benchmarks/llm_gen are smoke runs by their own READMEs. Follow-on (D1898): include an OpenCode-harness arm in the held-out design, or LLMx fixes are measured everywhere except where agents actually run. Done when ten held-out tasks in two model families run under the acceptance rule with the harness, prompts, cards and baseline results frozen and the report versioned. Follow-on (D1954): full E2 comparative gate after this pilot â€” broad plus registered cohorts with frozen weights, oracles and statistical rules; the ten pilot tasks above are the rehearsal, not the claim. FIRST STEP (D2330): scripts/freeze_llm_protocol.py writes docs/llm-protocol-freeze.json -- hashes of the card, schema, capabilities golden, budgets, benchmark tasks and runner, the compiler/library/conformance trees, the acceptance rule as data, arms and strata -- and --check names drift. NOT DONE: register the model families and versions, the held-out task ids and the OpenCode arm, archive baseline results, and run (needs provider access and budget).

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- Every emitted record must validate: `python scripts/validate_stream.py`.
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
