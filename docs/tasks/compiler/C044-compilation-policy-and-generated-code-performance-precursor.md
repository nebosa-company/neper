# C044 — Compilation policy and generated-code performance (precursor for T2/E2 H20)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.55 of 1 |
| queue position | 7 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H20 — compilation policy and generated-code performance** (track: T2.1 (Understand and check, open); E2 (Measured LLM-experience claim, open)):

**T2 implementation and E2 measured closure: versioned CPU policy and explanation
records.** This is not a requirement to build every advanced optimizer before M3.

- Separate semantic check, development emission and bounded release optimization
  objectives. Decide supported modes and expose them in build/query identities.
  H03 safety guarantees cannot silently disappear in the faster mode.
- Reevaluate the permanent cross-module 40-NIR-instruction cap and fixed pipeline
  against representative workloads. Retain them if justified; otherwise record a
  versioned replacement with compile-work/code-size budgets. No cap is universally
  optimal and faster emission alone does not establish faster programs.
- Measure copies, redundant checks, allocations, loop code, specialization growth,
  register pressure and inlining effects. Serialize enough checked type/effect/alias
  information to support valid optimization without unsafe assumptions or repeatedly
  importing entire bodies. Define lazy access to `.em` sections where useful.
- Emit structured reasons for performed/missed transformations supported by the
  implementation: origin, decision, relevant precondition and cost/budget. Features
  not implemented, such as a proposed vectorizer, must be reported as unavailable.
- Require semantic/IR verification across transformations and independent execution
  tests. Removing a check requires an actual proof under the selected contract.

Acceptance: same valid CPU workloads across supported policies; retained/eliminated
checks; observable aggregate copies; generic growth; inline-sensitive workloads;
phase timings and executable size/runtime reports. Replace unconditional speed
claims with measured targets. H25 freezes regression budgets and decisions.

**Later delivery:** advanced loop/vector optimizers, profile-guided optimization
and additional optimization tiers require separate workload-backed decisions and
named milestones. T2 closes their architectural constraints and disposition,
not nonexistent implementation/performance evidence.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Three policies, each a build identity and named in the manifest: debug, release with the memory checks retained, release `--unchecked` (D355, D369); the forty-instruction cap re-evaluated on the 500k-line workload and retained, `--inline-cap N` and `--explain` giving every inlining decision its reason (D346), and under `--json` as `inline` records of the build stream, gathered per worker and written in worker order, pinned per host (D408); the bounds proof and the `--stats` rows for elided checks and by-value copies (D356); measured budgets and the gate (D338, D366). `--stats` reports the register pressure of a build -- values allocated, values spilled, functions spilling -- summed over the crew (D450)

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] allocation counts
- [ ] lazy `.em` section access
- [ ] serialized alias facts
- [ ] the cap against the GP workloads
- [ ] any vectorizer (reported unavailable)
- [ ] the vector register class whose ABI is section 5's xmm convention for `Vec`/`Mask` (D786)

Notes:

- `any vectorizer` is reported unavailable on purpose: auto-vectorisation is under roadmap 'Deliberately not scheduled'. Do not build one; the remaining lines are the measurements.

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D338` — The M2 baseline: the compiler preserved before post-M2 tracks touch it (`docs/decisions.md:7195`)
- `D346` — The inlining cap re-evaluated and retained, and every decision explained (`docs/decisions.md:7471`)
- `D355` — A release build is a checked build, and every unsafe boundary is listed (`docs/decisions.md:7776`)
- `D356` — The first bounds proof, and the inlined bodies that had lost their checks (`docs/decisions.md:7803`)
- `D366` — The performance gate: a measurement judged against the budgets (`docs/decisions.md:8050`)
- `D369` — A check policy is a build identity: `--unchecked` artifacts carry their own mode (`docs/decisions.md:8128`)
- `D408` — Inlining decisions are records of the build stream (`docs/decisions.md:9093`)
- `D450` — Register pressure is a `--stats` row (`docs/decisions.md:9855`)
- `D786` — `Vec`/`Mask` cross a call by copied storage until there is a vector register class (`docs/decisions.md:14930`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `unchecked`: `src/em.e`×36‡, `src/main.e`×27‡, `src/check.e`×23‡, `src/tool.e`×11‡, `src/codegen_x64.e`×1‡, `src/lower.e`×1‡, `tests/conformance/reject/safety_unchecked.expected.jsonl`×1
- `inline-cap`: `src/main.e`×6‡, `src/lower.e`×2‡, `src/nir.e`×1†
- `Mask`: `lib/e/simd.e`×22, `src/check.e`×15‡, `src/layout.e`×2, `src/main.e`×2‡, `benchmarks/metamorphic/rename_symbols.py`×1, `lib/e/algo/combin.e`×1, `scripts/check_module_plan.py`×1, `src/resolve.e`×1†

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
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
