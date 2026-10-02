# L056 — Elementary inferential completions in e.algo.stat

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.00 of 1 |
| queue position | appended at the end (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md`, `docs/stats-coverage.md` §1 and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `lib/e/algo/stat/test.e` covers one-sample, pooled two-sample and Welch t-tests, chi-squared goodness of fit, Mann-Whitney U, Wilcoxon signed-rank, one-way ANOVA and Kruskal-Wallis, plus Fisher exact, two-sample and one-sample KS, Anderson-Darling, Shapiro-Wilk, a permutation test of the mean difference, and Bonferroni/Benjamini-Hochberg corrections; `lib/e/algo/stat.e` covers compensated means, Hyndman-Fan quantiles, G1/G2 skewness/kurtosis, entropy, Ledoit-Wolf covariance, Pearson/Spearman/Kendall correlations, KDE, bootstrap/jackknife, Wilson/Clopper-Pearson intervals and Normal/Exponential/Gamma/Beta fits. Missing: an explicit z-test, a chi-square independence/contingency wrapper, homogeneity-of-variance tests, post-hoc pairwise tests, power/sample-size analysis, a mode and weighted descriptives. Full evaluation: `docs/stats-coverage.md` §1–§2.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

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
