# The H25 report

H25 ([`post-m2-llm-hardening.md`](post-m2-llm-hardening.md)) asks for reproducible
performance and harness measurements on Windows and Linux, a frozen workload and budget
for every workflow, and a recorded decision for every regression. This report gathers
them. The numbers come from the decision rows named in each section and the raw
observations in `benchmarks/baseline/results/`. Every figure can be reproduced with the
command given.

## What is frozen

| item | value |
|---|---|
| host | Intel Core i5-12500H, 16 GB; Windows 11 26200 and, on it, WSL2 Ubuntu 24.04 (kernel 6.18.33.2) |
| baseline compiler | tag `m2-baseline` (D338), rebuilt from its tag to its recorded image |
| candidate compiler | the revision each row names; the D946 compiler for the rows from D947 on |
| workloads | `benchmarks/scale/generate.py --seed 1`: sc500k (500 modules), sc1m (1,000), sc2m (2,000); the compiler's own source; `benchmarks/cpu` (four programs) |
| options | `--arena 14g`, eight workers unless a row says `-j 1`, debug and release |
| cache states | cold = the workload's `.neper` removed first; warm = the same build again; the OS file cache is warm in both (the first run of every cell is discarded) |
| repetitions | seven pairs (timed gate, edit, CPU), five sessions, seven renames, three context and repair runs |
| Linux files | the workloads on the VM's own file system: the Windows drive's 9P mount takes 11 ms a rename and times the mount (D935) |

Nothing here was tuned against its own workload after that workload was frozen. Each
workflow new since M2 has its budget pinned from its first measurement (D941, D947,
D948). The rows M2 had are judged against the baseline compiler run alongside.

## Instruments

- **Paired runs** (D930): the baseline and the candidate run in alternation and the
  gate judges the median of the per-run ratio, so load on the host lands on both. The
  stored baseline times drift with the host (the baseline compiler itself runs up to
  14% slower than its stored numbers, D936), so they are the record of M2, not the bar.
- **Exact instruction counts** (D933): `valgrind --tool=cachegrind --cache-sim=no`
  on a single-worker build, repeatable to 0.06%. Under valgrind the runtime finds no
  SHA extensions and hashes in software, so SHA-256 is left out of every comparison.
- **Deterministic measures** (D506): arena high-water and image bytes, held exactly
  in both suites by `benchmarks/baseline/static.py`.
- **Profiles**: `perf` with frame-pointer call graphs on Linux; on Windows, a sampling
  profiler that needs no elevation (`build/examples/winprof.py`, D934).

## The workflows

### Cold build and no-op (warm) build: M2 had them

`python benchmarks/baseline/paired.py --baseline-compiler M2 --baseline-root M2ROOT --candidate-compiler NEW --candidate-root ROOT --host HOST --jobs 8`
(D935; `results/paired-{windows,linux}-d934.json`). Median ratio, candidate over
baseline; budgets 1.10 cold, 1.15 warm:

| cell | Windows cold | Windows warm | Linux cold | Linux warm |
|---|---|---|---|---|
| sc500k debug | 1.059 | 0.899 | 1.004 | 0.869 |
| sc500k release | 1.097 | 1.037 | 1.012 | 0.827 |
| sc1m debug | 1.062 | 0.922 | 1.022 | 0.935 |
| sc1m release | 1.054 | 0.963 | 1.060 | 1.043 |

No breach. D930 had found seven at 1.35-1.54 cold. What closed the gap, largest first:
aggregate copies and clears of a known size laid out move by move (D933, -15.8% of the
instructions a build executes), the profile cuts with identical outputs (D930-D932),
and a warm build that trusts its own hash of unchanged bytes (D934). Each phase's
share is printed by `--time`; the paired runs split cold and warm per workload and
mode.

Peak memory, arena and image, both hosts, all four workloads (D936;
`results/h25-{windows,linux}-d936.json`): peak resident set -2.8% to +2.8%, arena
high-water 73-81% below the baseline, images 28-45% smaller. The Windows sc2m release
cell, which the baseline could not build at eight workers, builds. The `compiler`
cell's workload is the revision's own source, 40% larger than M2's, so it is read per
line: cold -1% to -14%, peak RSS -9% to +1%, release image +2% with its checks kept
(D355).

### Local edit/revert: M2 had it

`python benchmarks/baseline/edit.py ...` (D939; `results/edit-{windows,linux}-d939.json`).
It freezes three edits to the middle module (a body statement, the header comment, an
added function) and pairs them against the baseline over seven cycles. The H14 reuse
oracle is checked every cycle: after the edit the image equals a cold build's of the
edited source, and after the revert a cold build's of the original.

| edit | Windows edit / revert | Linux edit / revert | rebuilt | artifact bytes (baseline) |
|---|---|---|---|---|
| body, sc500k | 0.978 / 0.943 | 0.927 / 0.823 | 1 module, 1 body, 18 functions | 22,420 (38,628) |
| comment, sc500k | 0.779 / 0.789 | 0.558 / 0.650 | nothing | 0 (38,476) |
| interface, sc500k | 0.994 / 0.970 | 0.892 / 0.936 | 1 module, 19 functions | 22,516 (38,620) |
| body, sc1m | 0.940 / 0.963 | 0.857 / 0.867 | 1 module, 28 functions | 33,796 (59,516) |
| comment, sc1m | 0.813 / 0.834 | 0.608 / 0.648 | nothing | 0 (59,364) |
| interface, sc1m | 0.983 / 0.980 | 0.930 / 0.823 | 1 module, 29 functions | 33,884 (59,500) |

The oracle held every cycle. The importing modules are kept by their edges
(`edges-hold`).

### Rename, move, delete: new since M2

`python benchmarks/baseline/rename.py --compiler NEW --root ROOT --host HOST [--judge results/rename-HOST.json]`
(D941). The most used function of the middle module is renamed from inside the project,
and the query, plan, apply and check steps are timed on a fresh copy each run:

| workload | query | plan | apply | check (build) |
|---|---|---|---|---|
| sc500k, Windows / Linux | 2,780 / 2,758 ms | 2,766 / 2,740 | 11 / 1 | 1,576 / 1,624 |
| sc1m, Windows / Linux | 8,919 / 8,996 | 8,632 / 8,630 | 12 / 2 | 2,995 / 3,562 |

H17 completeness held every run: the new name has the old name's uses, the old name
has none left, and the program prints the same value. The unrelated diff was empty:
only planned files changed, and putting the old name back gives the original bytes.
**Move and delete have no planning tool yet**, so they are listed here and not
measured.

### Context and repair: new since M2

`python benchmarks/baseline/context.py --compiler NEW --root ROOT --host HOST [--judge results/context-HOST.json]`
(D948). Context answers are measured in serialized bytes and in tiktoken `cl100k_base` /
`o200k_base` tokens, counted rather than estimated: 582-5,107 tokens at record budgets
of 16 and 64. An answer cut short by its budget says so. Five frozen defects in the CPU
programs are repaired by a model-free loop that applies the compiler's own fixes. Every
one was verified (it builds and prints the original's output) on both hosts: one defect
takes 2 calls and about 360 tokens of diagnostics, and two defects take 3 calls and
658 tokens. Model calls, retries and harness cost per verified success with a model in
the loop belong to H12's evaluation (below).

### Persistent session: new since M2

`python benchmarks/baseline/session.py --compiler NEW --root ROOT --host HOST [--judge results/session-HOST.json]`
(D947), over `query-batch`: 100 context and uses queries with a memory sample every ten.
A query takes 47-49 ms on sc500k and 96 ms on sc1m, against a load of 2.7-9.4 s. The
warm memory slope is zero bytes per query, and each request's peak (105-209 MB) is
released before the next. Five answers match a fresh process byte for byte, so no
answer is stale. Cache eviction and cancellation are not applicable: a session holds
one snapshot and answers in order.

### CPU programs: the compiler's output

`python benchmarks/baseline/cpu.py ...` (D943, D946; `results/cpu-{windows,linux}-d943.json`).
Four core-language programs (sieve, sort, hash, records), with the same output from
every build. Run time is compared only under the same contract: the candidate's
`--release --unchecked` build against M2's release, which had no checks, with a +10%
budget. That ratio is 0.98-1.02, and 0.63-0.71 for the program that copies records.
The shipped release keeps its checks, and its cost is reported as the intentional
difference: 0% on `hash`, whose loop is proven, +10-12% on `sort`, +29-42% on `sieve`,
whose stride no proof covers. Since D946 the images are within a few hundred bytes of
M2's (18-25 KB), because an image lays out only the globals its code reaches.

### GPU: pending

No GPU number is reported. None is filled in from an emulator and labelled device
performance. Each workload is owned by the M3 item that makes it measurable:

| measurement | owner |
|---|---|
| device selection and runtime surface timings | C092 (M3-04), C093 (M3-05) |
| end-to-end and phase times, transfer bytes, synchronization | C090 (M3-02, the SPIR-V emitter and Vulkan runtime) |
| CPU-backend launch cost, the workgroup loop | C091 (M3-03) |
| the device-reached edit case, determinism | C094 (M3-06), C096 (M3-08) |
| floating-point contract | C095 (M3-07) |

## The budgets in force

| workflow | judged by | budget |
|---|---|---|
| cold / warm build | `paired.py` against the baseline compiler | median ratio 1.10 / 1.15 |
| peak RSS, arena, image | `measure.py` + `gate.py`; `static.py` in both suites | +10%, not above, +5% (the compiler cell per line, D936) |
| edit / revert | `edit.py` against the baseline compiler | median ratio 1.15, reuse oracle every cycle |
| rename | `rename.py --judge results/rename-<host>.json` | each step's median +25% frozen at D941; completeness and unrelated-diff guards |
| context / repair | `context.py --judge results/context-<host>.json` | tokens not above; latency and repair time median +25%; calls not above |
| session | `session.py --judge results/session-<host>.json` | per query median +25%; zero retention |
| CPU programs | `cpu.py` against the baseline compiler | unchecked ratio 1.10; same output |

A regression beyond any of these needs a decision row naming the number, the cause and
the trade (docs/m2-baseline.md, "The budgets").

## Noise and exclusions

- Host load moves any single time by up to 5% (the baseline compiler's own runs,
  D932). That is why times are compared paired or against pinned medians with a
  quarter's margin.
- Valgrind's software SHA-256 is excluded from instruction counts (D933).
- WSL's 9P mount is excluded by keeping the Linux workloads on the VM's own file system
  (D935). The measurement of the compiler cell builds from the Windows drive in both
  the baseline and the candidate, as the baseline was measured.
- `--stats` computes source statistics over every module and is never on a timed
  build (D939).

## What this report is not

- Not H12's evaluation. Model families, held-out tasks, first-pass rates and harness
  cost per verified success with a model are E2's claim gate
  ([`tasks/milestones/E2-measured-llm-experience-claim-gate.md`](tasks/milestones/E2-measured-llm-experience-claim-gate.md)).
  The context and repair measurements here are what that evaluation hands a model and
  what the compiler repairs without one.
- Not a claim to be fast in general. One machine, generated workloads, four small
  programs and the compiler itself; every claim here names its workload and command.
