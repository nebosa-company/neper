# C033 — Reproducible performance gate (evidence for E2 H25)

| field | value |
|---|---|
| category | compiler / Front end and language |
| score | 0.72 of 1 |
| queue position | 2 of 49 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

From `docs/post-m2-llm-hardening.md`, **H25 — reproducible performance and harness acceptance** (track: E2 (Measured LLM-experience claim, open)):

**E2 claim-gate delivery: executable CPU/tooling measurements and registered GPU workload
designs.** Extend H12; do not replace its semantic/LLM thresholds with throughput.

| Workflow | Required measurements and correctness guard |
|---|---|
| Cold build | Wall/CPU time, peak memory, phase/critical-path timing; clean output oracle |
| No-op check | p50/p95 latency, reads and actual semantic/emission work; current snapshot |
| Local edit/revert | Rechecked declarations, emitted functions, invalidation edges, bytes; H14 reuse oracle |
| Rename/move/delete | Query/plan/apply/check latency, changed references, unrelated diff; H17 completeness |
| Context/repair | Serialized bytes, tokenizer-specific tokens, calls/retries, total time; verified success |
| Persistent/batch session | Warm memory slope, cache eviction and cancellation latency; no stale results |
| CPU program | Throughput/tail latency, allocations/copies, executable size; same defined behavior |
| GPU cold/warm, M3 | End-to-end and phase times, transfer bytes/synchronization; H21/H23 output oracle |

- Freeze hardware/OS/toolchain, compiler revision, workload/data hashes, options,
  cache states, worker counts, repetitions and numeric budgets before candidate
  tuning. Archive raw observations and reproducible commands. Distinguish empty
  compiler caches from cold OS caches; record thermal/power/background-work controls.
- Use small interactive projects and real larger dependency graphs, generic-heavy
  code, generated files, high fan-out, malformed intermediate edits and repeated
  refactors. Include CPU/GPU transfer-bound as well as compute-bound future cases.
- Report per-workload distributions and paired changes; averages cannot hide tail
  regressions. Record measurement noise, instrumentation overhead and exclusions.
  A cache hit without a timing win is not itself a performance success.
- Attribute compiler stages, dependency wait, filesystem/link work and driver work
  separately. Compare runtime only for equivalent semantics and safety contracts;
  report intentional differences rather than rewarding unchecked behavior.
- Evaluate full harness cost per verified success, including unsuccessful runs,
  retries, timeouts and output retrieval. Measure tokenizer identities empirically;
  source characters, lexer tokens and model tokens are different quantities.
- Set numeric latency/memory/code-size/runtime regression thresholds from the M2
  shared M2 baseline, with rationale and noise margins. For features absent in M2,
  freeze workload and absolute budget before implementing/tuning the candidate.
  Exceeded budgets require an explicit recorded decision before closure; no silent
  rebaselining or removal of safety obligations.

Acceptance: reproducible Windows/Linux CPU reports, H12 two-family evidence, H14–H24
and H30–H44 applicable conformance/fault/comparative tests and a budget decision for
every regression.
GPU reports are marked pending with named M3 owners/workloads, never filled with
emulator timings and labeled device performance. No claim to be fastest overall is
made from this suite; claims name the workload, configuration and measured evidence.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Registered workloads, budgets and rendered reports (D338, `m2-baseline.md`); `benchmarks/baseline/gate.py` judges a measurement cell by cell against the budgets and exits 1 on a breach (D366) -- twelve named on the D351 measurement, twenty on the D382 one and the causes found in the phase split (D383: two scans fixed, D355's retained checks named as what stands; D386: a profile of the compiler building itself found a quadratic slot walk, cold -14%; D387/D388: the warm build's byte sinks copy whole through the intrinsic memcpy and the hash reads inline under a proof, cold 603 ms, warm 115; D402: the crew's workers set up in parallel, the body phase halved; D403: two quadratic walks of the register allocator found on a synthetic function of four thousand loops, 2082 -> 74 ms, the compiler's own build unchanged; D411: the warm build profiled, the compiler's own xxHash64 identity a sixth of its CPU, replaced by the CRC32 instruction, warm 130 -> 117 ms by a stopwatch around the process; D428: the runtime no longer touches every small allocation, `os.touch` at the kernel-facing `e.os` sites keeps the property, peak RSS of the compiler's own build 1018 -> 322 MB release, eight-worker check bodies 70 -> 50 ms; D457: the unsafe inventory rides in the artifact, the warm manifest phase 20 -> 4 ms; D459: the link recomputes a function's content hash only where the image folds by it, warm `link from artifacts` 34 -> 27 ms; D460: the reach walk's answer per relocation is the reference's target, no second lookup in the copy and no third by name, `link from artifacts` 27 -> 22 ms, `link` 18 -> 15 ms; D461: a callee's module found once per artifact string, 22 -> 18 ms; the warm build of the compiler is now load 8, link from artifacts 18, symbol table 7, image 7, manifest 4 ms). The deterministic half of the gate is in both suites (D506): `benchmarks/baseline/static.py` builds the fixed sc500k workload in both modes with the stable stage on eight workers and `gate.py` holds the workers' arena high-water (not above) and the image bytes (within five percent) to `results/static-<host>.json`, since neither varies with the machine's load; a breach fails the suite and re-pinning is the decision row

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] the timed half of the gate (a distribution, not a suite step), Linux measurements after the baseline
- [ ] the H25 report

## Decisions to read first

Read each row in full (`sed -n 'START,+60p' docs/decisions.md`). They record why the delivered shape is what it is; a change that contradicts one needs a new row that supersedes it.

- `D338` — The M2 baseline: the compiler preserved before post-M2 tracks touch it (`docs/decisions.md:7195`)
- `D351` — Nothing moves out from under a pointer, and an arena is affine (`docs/decisions.md:7648`)
- `D355` — A release build is a checked build, and every unsafe boundary is listed (`docs/decisions.md:7776`)
- `D366` — The performance gate: a measurement judged against the budgets (`docs/decisions.md:8050`)
- `D382` — The second fix: an untested acquisition offers its test (`docs/decisions.md:8490`)
- `D383` — The stage measured: two scans that had gone quadratic and per-byte, and the cost that stands (`docs/decisions.md:8509`)
- `D386` — The stack object's slot was a rewalk of the function: fifteen per cent of the build (`docs/decisions.md:8576`)
- `D387` — The warm build profiled: the byte sinks copy whole, and the hash's loads are proven (`docs/decisions.md:8599`)
- `D388` — The hash reads its words inline, and a reader's guard is its proof (`docs/decisions.md:8625`)
- `D402` — A worker sets itself up on its own thread (`docs/decisions.md:8949`)
- `D403` — Two quadratic walks in the register allocator (`docs/decisions.md:8973`)
- `D411` — The compiler's identity is a CRC-32C, not an xxHash64 (`docs/decisions.md:9157`)
- `D428` — The runtime touches what the kernel writes, not every allocation (`docs/decisions.md:9477`)
- `D457` — The unsafe inventory rides in the artifact (`docs/decisions.md:9965`)
- `D459` — The content hash verified where the image folds by it (`docs/decisions.md:9982`)
- `D460` — A callee resolved once (`docs/decisions.md:9998`)
- `D461` — A callee's module found once per string (`docs/decisions.md:10017`)
- `D506` — The deterministic half of the gate, in the suites (`docs/decisions.md:10779`)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `m2-baseline.md`: `benchmarks/baseline/render.py`×2, `benchmarks/baseline/gate.py`×1, `benchmarks/baseline/measure.py`×1
- `benchmarks/baseline/gate.py`: `benchmarks/baseline/gate.py`×1
- `os.touch`: `lib/e/os/shell.windows.e`×8†, `src/runtime_pe_x64.asm`×2†, `src/check.e`×1‡
- `e.os`: `tests/conformance/tools/explain_inline.x64-linux.expected.jsonl`×150, `tests/conformance/tools/explain_inline.x64-windows.expected.jsonl`×133, `src/resolve.e`×36†, `lib/e/ui/app.e`×10, `lib/e/os.linux.e`×9‡, `src/check.e`×8‡, `lib/e/fs.e`×7, `lib/e/os.windows.e`×6‡
- `benchmarks/baseline/static.py`: `benchmarks/baseline/static.py`×1
- `gate.py`: `benchmarks/baseline/gate.py`×1, `benchmarks/baseline/static.py`×1

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
