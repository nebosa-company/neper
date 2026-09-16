# The M2 baseline

M2.5 stage A ([`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 29, H25):
the compiler as it stands at the end of M2, preserved and measured before any of the
M2.5 semantic changes, so that every later revision is compared against fixed
numbers and a budget breach is a recorded decision rather than a drift. What this
document freezes is the compiler and its build-time budgets; the H12 model-family
evaluation is a separate obligation that this baseline does not claim (below).

## The revision

The baseline compiler is the source at tag `m2-baseline` (the commit that added this
document; D338). It builds itself to a fixed point on both hosts -- the suites'
stage 2 and stage 3 are byte for byte the same -- and the stage-3 image is:

| host | SHA-256 of `neper-own-stable` | size |
|---|---|---|
| Windows x64 | `74c36198a849240c42db8d8fbd084704df4fc101597305385f2b00923d2b29c2` | 7,112,192 B |
| Linux x64 | `3ff2cc9ea3dc8705b55325aaf05e787de04022c1fc80c673014254c1d75ea918` | 7,069,288 B |

A checkout of the tag with no `neper` binary rebuilds it through the C bootstrap
(`scripts/build-bootstrap.ps1` / `.sh`, then `tests/selfhost/run.ps1` / `run.sh`);
the hashes above are what those runs must reproduce. The recovery path of D95
remains the older tagged revision; this tag is the M2 semantic baseline, not a
replacement bootstrap anchor.

## The measurement

`benchmarks/baseline/measure.py` builds each workload with a self-hosted release
compiler, cold (the workload's `.neper` removed) and warm (nothing changed) in debug
and release, and records the wall-clock distribution over the runs, the phase split
from `--time`, the peak resident set and the image size from `--stats`, and the
arena's high-water mark. The first run of every cell is discarded so the OS file
cache is warm throughout; the commands are recorded in the JSON. The results under
`benchmarks/baseline/results/` are the raw observations; the tables below are
rendered from them by `benchmarks/baseline/render.py`.

Workloads:

| name | what | source |
|---|---|---|
| `compiler` | the compiler compiling itself, 35 modules | `src/main.e` |
| `sc500k` | 500 modules, 460k lines | `benchmarks/scale/generate.py --modules 500 --lines 500000 --seed 1` |
| `sc1m` | 1000 modules, 920k lines | `--modules 1000 --lines 1000000 --seed 1` |
| `sc2m` | 2000 modules, 1.84M lines | `--modules 2000 --lines 2000000 --seed 1` |

The generated programs are the same bytes on every host and every run (the seed is
fixed); they stand for the shape of a large program -- thousands of files of unequal
size, an import DAG, calls across it -- and say nothing about any real one.

Environment: one machine, an Intel i5-12500H (4 performance and 8 efficiency cores,
16 threads), 16 GB, Windows 11 Home 10.0.26200 and WSL2 Ubuntu 24.04 on the same
hardware. On Windows the sources are on an NTFS volume scanned by Defender; on Linux
the scale fixtures are on the Linux filesystem and the compiler's own sources are on
the Windows volume through 9P, which is the whole of the Linux `compiler` warm
figure (D330). Another build was running on the machine during parts of the Windows
measurement; the p95 columns carry that. Nothing was pinned, isolated or repeated
beyond the runs stated.

<!-- baseline tables -->

### `baseline-linux.json` -- linux, 8 workers, 5 runs per cell, revision `d43267c0aaaa`

Compiler `neper-prof`, `--arena 14g`, platform `Linux-6.18.33.2-microsoft-standard-WSL2-x86_64-with-glibc2.39`.

| workload | lines | mode | cold p50 | cold p95 | warm p50 | warm p95 | peak RSS | arena high-water | image |
|---|---|---|---|---|---|---|---|---|---|
| compiler | 48,391 | debug | 595 ms | 622 ms | 264 ms | 280 ms | 249 MB | 1636 MB | 7,069,288 B |
| compiler | 48,391 | release | 564 ms | 580 ms | 201 ms | 213 ms | 237 MB | 2075 MB | 5,441,624 B |
| sc500k | 460,243 | debug | 1.62 s | 1.77 s | 192 ms | 195 ms | 712 MB | 3313 MB | 2,979,360 B |
| sc500k | 460,243 | release | 1.64 s | 1.69 s | 154 ms | 156 ms | 676 MB | 3835 MB | 2,073,640 B |
| sc1m | 920,554 | debug | 3.11 s | 3.21 s | 298 ms | 330 ms | 1251 MB | 5609 MB | 5,882,552 B |
| sc1m | 920,554 | release | 3.26 s | 3.49 s | 281 ms | 372 ms | 1183 MB | 6356 MB | 4,094,376 B |
| sc2m | 1,840,967 | debug | 6.48 s | 6.60 s | 675 ms | 720 ms | 2358 MB | 10187 MB | 11,853,432 B |
| sc2m | 1,840,967 | release | 6.87 s | 7.28 s | 575 ms | 627 ms | 2226 MB | 11380 MB | 8,254,384 B |

Cold phase split, p50 over the runs (ms):

| workload | mode | load and parse | resolve | check declarations | settle | check bodies | lower and codegen | link from artifacts | link | write executable | manifest | inline oracles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compiler | debug | 123 | 12 | 18 | 5 | 47 | 245 | 33 | 29 | 50 | 7 | 0 |
| compiler | release | 120 | 12 | 19 | 6 | 42 | 263 | 13 | 17 | 38 | 6 | 7 |
| sc500k | debug | 232 | 64 | 114 | 1 | 183 | 928 | 46 | 17 | 7 | 4 | 0 |
| sc500k | release | 219 | 60 | 106 | 1 | 359 | 805 | 35 | 11 | 4 | 3 | 6 |
| sc1m | debug | 429 | 132 | 208 | 1 | 341 | 1804 | 97 | 32 | 11 | 6 | 0 |
| sc1m | release | 428 | 127 | 210 | 1 | 717 | 1629 | 76 | 21 | 9 | 5 | 7 |
| sc2m | debug | 934 | 279 | 444 | 2 | 727 | 3612 | 239 | 65 | 25 | 12 | 0 |
| sc2m | release | 932 | 282 | 456 | 2 | 1511 | 3376 | 198 | 41 | 17 | 11 | 11 |

### `baseline-windows-sc2m-j4.json` -- windows, 4 workers, 3 runs per cell, revision `d43267c0aaaa`

Compiler `neper-big.exe`, `--arena 14g`, platform `Windows-11-10.0.26200-SP0`.

| workload | lines | mode | cold p50 | cold p95 | warm p50 | warm p95 | peak RSS | arena high-water | image |
|---|---|---|---|---|---|---|---|---|---|
| sc2m | 1,840,967 | debug | 7.38 s | 7.40 s | 658 ms | 667 ms | 2077 MB | 8282 MB | 11,855,360 B |
| sc2m | 1,840,967 | release | 7.90 s | 15.70 s | 567 ms | 574 ms | 1947 MB | 9328 MB | 8,256,512 B |

Cold phase split, p50 over the runs (ms):

| workload | mode | load and parse | resolve | check declarations | settle | check bodies | lower and codegen | link from artifacts | link | write executable | manifest | inline oracles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sc2m | debug | 1022 | 286 | 373 | 0 | 711 | 4393 | 324 | 55 | 19 | 10 | 0 |
| sc2m | release | 1036 | 272 | 383 | 0 | 1757 | 4114 | 218 | 33 | 13 | 7 | 12 |

### `baseline-windows.json` -- windows, 8 workers, 5 runs per cell, revision `d43267c0aaaa`

Compiler `neper-big.exe`, `--arena 14g`, platform `Windows-11-10.0.26200-SP0`.

| workload | lines | mode | cold p50 | cold p95 | warm p50 | warm p95 | peak RSS | arena high-water | image |
|---|---|---|---|---|---|---|---|---|---|
| compiler | 48,391 | debug | 385 ms | 400 ms | 82 ms | 86 ms | 260 MB | 1638 MB | 7,112,192 B |
| compiler | 48,391 | release | 416 ms | 432 ms | 53 ms | 56 ms | 248 MB | 2077 MB | 5,481,472 B |
| sc500k | 460,243 | debug | 1.37 s | 1.40 s | 134 ms | 146 ms | 731 MB | 3316 MB | 2,981,376 B |
| sc500k | 460,243 | release | 1.49 s | 1.50 s | 111 ms | 113 ms | 695 MB | 3838 MB | 2,075,648 B |
| sc1m | 920,554 | debug | 2.78 s | 2.83 s | 269 ms | 274 ms | 1279 MB | 5611 MB | 5,884,928 B |
| sc1m | 920,554 | release | 2.99 s | 3.08 s | 231 ms | 236 ms | 1211 MB | 6359 MB | 4,096,512 B |
| sc2m | 1,840,967 | debug | 6.01 s | 6.50 s | 610 ms | 625 ms | 2403 MB | 10189 MB | 11,855,360 B |
| sc2m | 1,840,967 | release | failed | | | | | | (`error: e.mem.Exhausted` after 3 retries) |

Cold phase split, p50 over the runs (ms):

| workload | mode | load and parse | resolve | check declarations | settle | check bodies | lower and codegen | link from artifacts | link | write executable | manifest | inline oracles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compiler | debug | 42 | 7 | 11 | 0 | 28 | 206 | 27 | 23 | 11 | 3 | 0 |
| compiler | release | 41 | 7 | 10 | 0 | 30 | 261 | 12 | 14 | 9 | 2 | 4 |
| sc500k | debug | 200 | 55 | 89 | 0 | 141 | 777 | 38 | 12 | 4 | 2 | 0 |
| sc500k | release | 204 | 54 | 89 | 0 | 326 | 716 | 30 | 7 | 3 | 2 | 3 |
| sc1m | debug | 420 | 115 | 181 | 0 | 294 | 1568 | 83 | 25 | 9 | 4 | 0 |
| sc1m | release | 409 | 117 | 182 | 0 | 668 | 1441 | 66 | 15 | 6 | 3 | 4 |
| sc2m | debug | 843 | 243 | 378 | 0 | 758 | 3214 | 307 | 53 | 19 | 9 | 0 |

<!-- end baseline tables -->

### What the tables say

- Cold builds are within 10% of each other in debug and release on both hosts; the
  release build's oracles cost what the debug build's checks cost.
- Warm builds are a quarter of a second at a million lines and 80 ms for the
  compiler on Windows (D336); the Linux `compiler` warm figure is 9P.
- The arena's high-water mark is five to eight times the peak resident set: pools
  are sized from the program (D306) and the Windows runtime commits up to the
  allocation offset, so a two-million-line release build asks for more than a 16 GB
  machine's commit charge holds. That is why the Windows `sc2m` release cell failed
  after three retries, and why a separate run at four workers is recorded beside it
  (`baseline-windows-sc2m-j4.json`: 7.9 s cold at four workers, 9.3 GB high-water,
  with one 15.7 s outlier in three runs). Linux maps with
  `MAP_NORESERVE` (D330) and completes the same cell at 11.4 GB high-water.
  Closed by D339: worker arenas are reservations committed as they are touched, and
  the cell builds at eight workers with a 4.8 GB peak commit; from D339 on, `arena
  high-water` in the tables is the root arena alone and `worker arenas reached` is
  reported beside it.

## The budgets

Set from the baseline with the noise margin the p95 columns show, per workload and
host, for the M2.5 compiler at every stage until the H25 report replaces them with
its own. A revision that exceeds a budget on either host is not merged without a
recorded decision (`docs/decisions.md`) naming the number, the cause and the
trade; a budget is never met by weakening a check, and rebaselining is itself such
a decision.

| measure | budget | rationale |
|---|---|---|
| cold build p50, any workload and mode | baseline p50 + 10% | the cold p95 sits within 5% of p50 on the quiet cells; 10% leaves the noise a margin and a regression none |
| warm build p50, any workload and mode | baseline p50 + 15% | warm cells are small numbers where 10 ms is 10%; a warm build must stay under 0.1 s for the compiler and 0.3 s for a million lines |
| peak resident set | baseline + 10% | memory is the cost the M2.5 checks are most likely to add to; a checked ownership model that needs more than a tenth more must say why |
| arena high-water mark | baseline, not above | the one figure to bring down, not up: the Windows `sc2m` release cell is the budget already exceeded, recorded here as the first H25 debt |
| image size, debug and release | baseline + 5% | code the retained checks add is the ablation H25 asks for, reported, not hidden in a wider budget |
| self-build fixed point | stage 2 == stage 3, both hosts | not a budget: a gate, as in M2 |

The `compile threads` row of `--stats` reads 1 while eight workers run (it predates
D321); the worker count is the `-j` value or eight.

`benchmarks/baseline/gate.py NEW.json` (D366) judges a measurement against these
budgets, cell by cell and measure by measure -- `ok`, `BREACH` with both numbers
and the delta, or `missing` -- and exits 1 on any breach, which is what a merge
reads. Run against `h01-windows-d351.json` it names twelve: the cold and warm
compiler cells (+27%, +17-27%), the peak resident set everywhere (+24% to +269%),
and the release cold cells of `sc500k` and `sc1m` (+12-14%) -- the D340 and D355
breaches the decision rows carry, now in a form nothing drifts past.

## What this baseline is not

- Not the H12 evaluation: no held-out task set, no model family, no repair run has
  been frozen or measured. Those are pre-registered separately before candidate
  results are inspected, as H12 requires; this document gives them a compiler to
  run against and the numbers a compiler regression is measured by.
- Not the H25 table in full: cold build and no-op build (the warm cell) are here;
  local edit/revert, rename/move/delete, context/repair, persistent session and CPU
  program runtime are pending, each to be frozen with its workload and budget
  before the candidate that changes it is tuned.
- Not a claim about performance in general: one machine, one operating-system pair,
  generated workloads and the compiler itself.
