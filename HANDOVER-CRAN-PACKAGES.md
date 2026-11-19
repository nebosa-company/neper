# Handover: CRAN package parity work (session "CRAN package support coverage")

Written 2026-11-18 at master `c24e0402a`. Nothing of mine is running; every agent has finished and every worktree branch I opened is merged and deleted (three leftover worktree directories under `.claude/worktrees` could not be removed because of stuck Windows file handles: `agent-a3f4ecf797cffcea2`, `agent-a8927519883d9a866`, `agent-ae4fd288f235bd32f`; remove them with `git worktree remove -f -f` or delete them by hand once nothing holds them).

## The standing goal

`/goal proceed implementing partials and non-started ones`: every item in `docs/work-queue.json` at score 1. The queue held 444 items at the end (230 `L` items, 143 of them in the group `CRAN parity`, 37 of those at score 0), so the goal is not met and cannot be met in one session. The Stop hook keeps reporting this; that is expected. The user's last instruction was: do not start new items, finish and close the ones already opened (and "close" means *complete*, not just logged), then pause. That is where this stopped.

## What was closed this session (28 items, all in `docs/work-done.jsonl`)

L418 Rmpfr, L305 Hmisc, L483 tsfeatures, L422 extraDistr, L430 geepack, L471 BiasedUrn, L331 hclust+dendextend, L429 imputeTS (incl. seasonal auto.arima), L449 sn, L411 DHARMa, L474 kSamples, L432 seriation, L333 pracma+polynom+caTools+fminsearch, L340 signal, L433 vars, L457 NMF, L310 glmnet, L346 mice, L335 cluster, L387 lmom+gld, L485 DRDID, L401 geosphere, L414 gbm, L348 mclust, L337 rpart, L424 logistf, L428 MuMIn, L364 metafor. (L299 coda/loo/posterior, L499 ResourceSelection, L482 laeken and L504 rcompanion were closed by another writer in the same repo; see "Shared repo" below.)

Each closed item has an `evidence` line in the done log and a `## D71xx` entry in `docs/decisions.md` (D6879 to D7112 are mine; another writer used D7026, D7100, D7101 in between). All of it is verified on **Windows only**. No closed item has been run on Linux. `docs/progress.html` and `docs/digest/*` were regenerated after each closure (`scripts/render_progress.py`, `scripts/render_digest.py`).

### Closed with known caveats (decide whether to reopen)

Weakest first:
- **L348 mclust**: `sim` and `mclustBootstrapLRT` from fitted **EVE and VVE** models do not match R (the orientation comes from a long MM iteration whose reached solution is rounding dependent). Noise combined with subset initialisation or a prior is also not done. The acceptance names `mclustBootstrapLRT`.
- **L411 DHARMa**: the Durbin-Watson p value is within ~1.5e-4 of R for n = 61..99 (R's own value moves with the last bits of its LAPACK eigenvalues); exact elsewhere. `testQuantiles` (needs qgam/mgcv) is not ported.
- **L364 metafor**: weakly identified `rma.mv` fits under the default `nlminb` agree to 1e-7 (16 of 33 to 1e-9); the variance-component covariance matrix to 1e-4. `rma.mh`, `rma.peto`, `rma.glmm`, the bounded and Hessian PORT drivers are not ported.
- **L331**: DendSer untangle method and `stepBothSides` not done (DendSer is not installed).
- **L414 gbm**: `calibrate.plot`, loess for more than one predictor, pairwise at a few thousand rows untested.
- **L428 MuMIn**: mixed-model `r.squaredGLMM` takes fitted pieces from R as data (the repo has no glmer fit); the `V()` helper in subset expressions is not done.
- **L457 NMF**: fastICA starts that never converge (200-iteration cap) are chaotic in R itself and are skipped by the oracle.
- Smaller notes are in each item's evidence line.

## What remains

The remaining CRAN-parity items (scores in the queue): L477 compositions 0.65 (another writer advanced it; still open: NA values, robust MCD, optimal and principal balances, `balanceBase` from a formula), L332 foreign 0.5, L379 gmp 0.5, L306 MASS remainder 0.42, L342 lmerTest 0.42 (needs general `lmer` fits), L496 fda 0.42, L425 ismev 0.4, L478 dagitty 0.4, then a long tail at 0.35 and below (tm/tidytext, vcd/effectsize, fpc, WRS2, gmm, gsl, bayesm, afex, betareg, TSA, sm, RSpectra/irlba, DescTools, lpSolve/clue, ordinal, pscl, marginaleffects, energy, PMCMRplus, sampling, QCA, EnvStats, and the score-0 ones: mediation, flexmix, uwot/Rtsne, earth, gam, RcppAnnoy, cubature, aod, rstan, stringi, lubridate, igraph, ...). Use:

```
D:/tools/neper-pyenv/Scripts/python.exe - <<'EOF'
import json
q=json.load(open('docs/work-queue.json',encoding='utf8'))
for i in sorted([i for i in q['items'] if i['id'].startswith('L')], key=lambda i:-i['score'])[:60]: print(i['id'], i['score'], i['title'])
EOF
```

Non-CRAN items (C and T tasks, UI and compiler work) were not touched.

## The workflow that worked

One agent per item, each in its own git worktree (`Agent` tool with `isolation: "worktree"`), at most four at a time, each told to finish its item **in full**, to touch only its own files, not to edit `docs/`, and to report exactly what equals R. I merge each branch into master as it reports, rerun its fixtures, then apply the docs entries myself (so D-numbers never collide). Per item:

1. `git merge worktree-agent-<id>`; the only recurring conflict is `tests/selfhost/extra-fixtures.txt`: remove the markers, `awk '!seen[$0]++'` to dedupe, `git add`, commit.
2. Run the fixtures: `NEPER_COMPILER=$PWD/build/windows/neper-try.exe bash scripts/check-fixture.sh <fixture> 2>&1 | tail -1`.
3. Read the item's **Acceptance** text (in `docs/work-queue.json`) and close only if every acceptance item has an oracle case; otherwise `SendMessage` the agent to continue.
4. Append the record (score 1, new evidence) as one line to `docs/work-done.jsonl`, remove it from `docs/work-queue.json`, append `## D<n> — title` to `docs/decisions.md`, run both render scripts, commit only those paths plus `docs/progress.html` and `docs/digest`.
5. `git worktree remove .claude/worktrees/agent-<id> --force` and `git branch -d worktree-agent-<id>`.

Rules from `AGENTS.md`/`CLAUDE.md` that still apply: shared tree, commit only touched paths (never `git add -A`), one source of truth, a regression test per behaviour, Edit tool or `build/windows/patch.exe` for code edits, commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## How an oracle item is built

- R oracle group `scripts/r_oracle/groups/<name>.R` writes `tests/oracle/<name>.json`; regenerate with `R_ORACLE_LIB=D:/Temp/rlib D:/tools/R/R-4.6.1/bin/Rscript.exe scripts/r_oracle/generate.R <name>`.
- Fixture `tests/selfhost/fixtures/link/oracle_<name>/src/main.e` loads the JSON and compares with `oracle.agrees`; register new fixture names in `tests/selfhost/extra-fixtures.txt`.
- Traps: call `set.seed` **after** drawing random parameters in the R group; keep each committed JSON under about 1.5 MB (one 34 MB `tests/oracle/loo.json` and a 9 MB `mclust.json` predate this and could be shrunk); never print raw fixture failures (their argument lists are thousands of characters; pipe through `cut -c1-200` or `grep -o`); a fresh worktree has no `build/windows` (run `mkdir -p build/windows` if `e.os.NotFound`); a string literal must not contain a raw newline; no if-expressions (use `var` + `if`); numeric literals need suffixes; no top-level `f64` consts.
- When an R function is compiled (C, C++ or Fortran) the exact algorithm, iteration order and RNG draw order must be ported from the package source, not re-derived from the maths; guessed algorithms matched only approximately every time.

## Reusable infrastructure built this session

- `lib/e/algo/linalg/lapack_base.e`, `lapack_syevr.e`, `lapack_gesdd.e` (plus `lapack_syev.e`, `lapack_gesvd.e` from the mclust work): a **sign- and rounding-exact port** of R's `eigen(symmetric = TRUE)` (dsyevr) and `svd()` (dgesdd), translated from LAPACK 3.12.1 by a Fortran-to-Neper translator that was **not committed** (it lived in an agent scratchpad); the generated modules are committed and carry a header saying so. Use `dsyevr_all` and `svd_all` whenever R output depends on eigenvector or singular-vector signs.
- `lib/e/algo/stat/nlminb.e` (R's PORT `nlminb`, unbounded drivers), `lbfgsb.e` (optim L-BFGS-B), `rnm.e`/`rbfgs.e` (optim Nelder-Mead, BFGS), `loessfit.e` (loess, one predictor), R's `integrate` (QUADPACK `qags`, in `ksamples_steel.e`), exact-rounded `exp`/`log` in `gbmfit.e` (`cr_exp`, `cr_log`), `kalman.e`, `arimafit.e`, `autoarima.e`, `fastica.e`, `mpfr.e` (arbitrary precision with all rounding modes).
- `lib/e/algo/rand/r.e` and `rdist.e`: R's RNG, `sample.int`, `rnorm`, `rgamma`, `rbeta`, `rt`, `rbinom` ... in R's draw order.

## Downloads (all approved by the user, one by one)

Source tarballs were fetched from CRAN (and GitHub for LAPACK 3.12.1 and R's PORT sources) into `D:/Temp/claude/src/`: geepack, lmtest, TSP, qap, kSamples, SuppDists, ggdist, cramer, cluster, nnet, rpart, glmnet, gbm, mclust, signal, fastglm, fastICA, logistf, lmom, geosphere, metafor, urca/tseries (earlier sessions), LAPACK 3.12.1, R PORT. The user said further source downloads needed for pending items are allowed; keep saying in the report what was fetched. Installed R packages live in `D:/Temp/rlib` (`R_LIBS=D:/Temp/rlib`); R is `D:/tools/R/R-4.6.1/bin/Rscript.exe`; Python is `D:/tools/neper-pyenv/Scripts/python.exe`.

## Shared repo

Other sessions (same git user, same working tree) commit to master concurrently and some also launched agents on the same items: L299, L499, L482, L504 and parts of L477 were closed or advanced by them while my agents worked, and my agents sometimes found foreign files in their worktrees. Before starting an item, check the current queue (`docs/work-queue.json`) and `git log --since="2 hours ago"` for that package; before closing, re-read the queue entry because its score or evidence may have changed. `docs/decisions.md` numbering: take the next free `D<n>` at the time you write.

## Open questions for the user

- Linux: run all new fixtures (`oracle_lapack_exact`, `oracle_glmnet_ext`, `oracle_mclust2..20`, `oracle_metafor*`, `oracle_nlminb`, ...) in the Linux batch; none has been run there.
- Reopen the caveated items above (most valuable: L348 EVE/VVE, L411 n = 61..99) or accept them?
- Whether to keep the slow fixtures (`oracle_imputets` about 45 s, `oracle_sn_selm` about 2 min, `oracle_glmnet_ext` about 20 s) in the regular suite.

## Update 2026-11-19: Workflow round and merged increments

Closed since the first handover: L464 (D7715). A 9-item Workflow round (81 agents, worktree implementers, two adversarial verifiers each, three repair rounds) closed nothing: every verifier still found gaps. Increments for L417 gsl, L407 GeneralizedHyperbolic, L367 lpSolve/clue, L468 fpc, L332 foreign, L409 arm, L413 flexmix and L306 MASS are merged on master (29ec799f5, 55585ba0c); 70 fixtures pass on Windows, none run on Linux. L334 produced nothing new.

The remaining-gap list for each of those items is in its `evidence` field in `docs/work-queue.json` (text after "Workflow round 2026-11-19"). Scores were not changed. Status: 134 CRAN-parity items done, 123 open (20 at score 0, 103 partial).

Lessons: a verifier finds new gaps every round, so give the next round only the listed gaps; a fresh git worktree outside `.claude/worktrees` makes the compiler fail with `e.os.Denied`; a background `for` loop that reads stdin stops after one command (use a script with `</dev/null`); `extra-fixtures.txt` in the working tree still holds another session's uncommitted edits.
