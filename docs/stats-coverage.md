# R/Python statistics coverage in Neper

Evaluation of the `stats.md` catalogue (statistical algorithms, charts, top-50 R
and Python packages) against the Neper standard library, conducted 2026-10-02.
Every "already delivered" claim names the implementing module and function; gaps
became backlog items L056–L064 (D1785). Items already queued (L005, L007, L017,
L032) are referenced, not duplicated.

## 1. Statistical algorithms

### Descriptive — supported

`lib/e/algo/stat.e`: streaming `Moments` (Welford) with `moments_merge`
(Chan), compensated `mean_compensated` (Neumaier), Hyndman-Fan quantiles R1–R9
(`quantile`, bit-for-bit numpy), sample-adjusted skewness G1 / excess kurtosis
G2 (`skewness`, `kurtosis`, matching `scipy.stats`), Shannon entropy (nats and
counts), covariance matrices with Ledoit-Wolf shrinkage (`covariance_shrink`,
as `sklearn.covariance.ledoit_wolf`), Pearson/Spearman/Kendall correlations,
Gaussian KDE with Silverman/Scott bandwidths, bootstrap/jackknife resampling,
Wilson and Clopper-Pearson binomial intervals, historical VaR / expected
shortfall, moment and MLE fits of Normal/Exponential/Gamma/Beta.

Gap (small, → L056): no `mode`, no weighted-descriptives helper; median is
covered via `quantile` R7.

### Inferential — mostly supported

`lib/e/algo/stat/test.e`: one-sample / pooled two-sample / Welch t-tests
(`t_test`, `t_test_two`, `welch`), chi-squared goodness of fit
(`chi_squared`), Mann-Whitney U (`mann_whitney`), Wilcoxon signed-rank
(`wilcoxon`), one-way ANOVA (`anova`), Kruskal-Wallis (`kruskal_wallis`), plus
Fisher exact, two-sample and one-sample KS, Anderson-Darling, Shapiro-Wilk
(Royston AS R94), permutation test of the mean difference, Bonferroni and
Benjamini-Hochberg corrections — all with two-sided p-values via
`lib/e/math/special.e` distribution functions.

Gap (→ L056): no explicit `z_test` (composable today via
`special.normal_cdf`), chi-square is goodness-of-fit only with no
independence/contingency-table wrapper, no homogeneity-of-variance test
(Levene/Bartlett), no post-hoc pairwise test (Tukey HSD), no power /
sample-size analysis.

### Regression — partial

`lib/e/ml/linear.e`: OLS (`ols`), ridge (`ridge`), lasso (`lasso`), binary
logistic (`logistic`), PLS (`pls`).

Gap (→ L057): no polynomial-feature helper, no elastic net, no quantile
regression, no robust (Huber) regression. Poisson / negative-binomial /
matched-conditional / ordinal GLM is already queued as L007 — not repeated.

### Time series — partial

`lib/e/algo/timeseries.e`: additive Holt-Winters (`holt_winters`, i.e. triple
exponential smoothing), STL/LOESS decomposition (`stl`, `loess`), CUSUM,
Page-Hinkley and ADWIN change detection, GARCH(1,1) likelihood/fit/forecast,
Hawkes self-exciting process (intensity, likelihood, thinning simulation).
State-space coverage via Kalman/EKF/UKF in `lib/e/math/filter.e`.

Gap: ARIMA is already queued as L017 — not repeated. VAR and structural
time-series remain (→ L059). Prophet has no equivalent; it is a non-goal
(D1785): an additive STL + regression composition covers the pattern.

### Multivariate — partial

`lib/e/ml/reduce.e`: PCA (`pca`), streaming PCA (Oja, `pca_online`), t-SNE,
UMAP. `lib/e/ml/cluster.e`: k-means, k-means++, streaming k-means, k-medoids,
agglomerative, DBSCAN, OPTICS, BIRCH, GMM.

Gap (→ L058): no factor analysis, no CCA, no MANOVA, no LDA/QDA discriminant
analysis (`lib/e/ml/bayes.e` covers Gaussian/multinomial naive Bayes only).

### Bayesian — supported, one gap

`lib/e/math/mcmc.e`: Metropolis-Hastings, Gibbs, HMC, NUTS.
`lib/e/math/mc.e`: plain, antithetic and control-variate estimators.
`lib/e/algo/rand/dist.e`: Normal, Exponential, Poisson, Binomial, Gamma, Beta,
Dirichlet, multivariate Normal (Cholesky), importance/rejection sampling,
stratified / Latin-hypercube / Halton / Sobol sequences, Gaussian copula.

Gap (→ L060): no variational inference (ELBO / SVI / ADVI-lite) over the
existing `e.ml.nn` autodiff.

### Non-parametric — supported

Bootstrap percentile intervals and jackknife (`stat.bootstrap`,
`stat.jackknife`), permutation test (`test.permutation`), Gaussian KDE, rank
tests, LOESS. No gap worth a backlog item (spline/GAM smoothing noted but
deferred).

### Survival analysis — supported, extensions queued

`lib/e/algo/stat/survival_trial.e`: Kaplan-Meier, Mantel-Cox log-rank, Cox PH
(Breslow ties, Newton-Raphson, model covariance), O'Brien-Fleming / Pocock
alpha spending, Simon optimal/minimax two-stage designs, CRM dose finding,
Farrington-Manning non-inferiority. Longitudinal/mixed core (GEE, MMRM, LMM)
landed as L012; causal/MICE landed as L014.

Gap already queued as L005 (Nelson-Aalen, competing risks, RMST, weighted
log-rank) — not repeated.

### Machine learning — partial

`lib/e/ml/tree.e`: CART, random forest, generic gradient boosting.
`lib/e/ml/svm.e` (SMO + kernels), `knn.e`, `bayes.e`, `nn.e` (perceptron,
autodiff tape, attention, multi-head attention, RoPE), `recurrent.e`
(LSTM/GRU), `gnn.e`, `hmm.e`, `rl.e` (Q-learning, SARSA), `optim.e`
(SGD/momentum/RMSprop/Adam/AdamW + schedules), `loss.e`
(InfoNCE/triplet/CTC/KL/JS), `sample.e` (softmax/top-k/top-p/beam),
`ann.e` (HNSW, IVF-PQ, MinHash-LSH).

Gap (→ L063): no histogram/leafwise gradient boosting (XGBoost/LightGBM
class — only the generic `gradient_boost` exists), no k-fold CV + grid search
+ pipeline abstraction (caret/sklearn-lite), no probability calibration.

## 2. Charts & visualizations — partial, queued

`e.gfx.chart` now has a deterministic caller-owned geometry API for scatter,
line, bar, grouped/dodged bar, signed stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, step, area, lollipop, error bars, confidence bands,
dumbbells, ECDF, box, density, normal Q-Q, violin, heatmap and correlation
matrix, with numeric scales and facet-panel geometry. Its scene and SVG
adapters produce twenty-nine paired previews in `docs/chart-previews/`, including
automatic linear/log tick text, caller-supplied titles, and bar category/series
legends. The
complete registry, remaining grammar stages and export/widget/benchmark gates
are tracked in `docs/charting-engine-plan.md` and L061; the original R/Python
gap remains open rather than being inferred closed from these first charts.

- Standard plots (scatter, line, bar, histogram, box, violin, density,
  heatmap, correlation matrix, facet/trellis, paired, joint, ridge) → L061.
- Specialized: interactive hover/select/zoom via `e.ui` (no plotly/bokeh
  equivalent), geographic rendering atop `e.algo.geo` (S2/haversine exist, no
  renderer), network layout atop `e.algo.graph` (algorithms exist, no
  layout/draw), 3D surfaces atop `e.gfx.mesh/scene` (low-level only) → L062.
- Dashboards (shiny/streamlit/dash): non-goal (D1785) — hand-build on
  `e.ui.app` + `e.net.http`; no framework port.

## 3. Top-50 R packages

Covered: `stringr→e.str/e.text.*`, `lubridate→e.time/e.time.calendar`,
`forcats`-basics→`e.text` (factors remain caller-side), `jsonlite/xml2→
e.fmt.json/xml`, `httr/rvest→e.net.http + e.text.regex + e.fmt.html`,
`survival→e.algo.stat.survival_trial`, `lme4→e.algo.stat.mixed` (GEE/MMRM/LMM),
`glmnet→` ridge/lasso only (elastic net → L057), `randomForest→
e.ml.tree.random_forest`, `forecast/fable/tsibble→` partial (HW/STL/GARCH;
ARIMA → L017), `testthat→e.test + prop/fuzz/linearize/sim`,
`devtools/roxygen2/usethis/renv/targets→` compiler + script-free hash-verified
`pacman`, `odbc/RPostgres/RMariaDB→e.db` contract + SQLite/Postgres/MySQL/TDS/
ODBC drivers, `future/furrr→e.task/e.thread.pool`, `readr→e.fmt.csv`.

Missing, now queued: `dplyr/tidyr/data.table` verbs beyond L032's
filter/sort/group/summarize/pivot (mutate/select/relocate, joins,
pivot wider/longer, window functions, missing-value verbs → L064);
`ggplot2/plotly/leaflet/DT` (→ L061/L062); `caret/modelr/broom`
(→ L063 pipeline/tidy-model layer); `MASS`-class GLM/multivariate (→ L057/L058).

Non-goals (D1785, consistent with `docs/algos.md` skip policy):
`quantmod/TTR` (finance), bioinformatics domain tools, `sparklyr` (Spark),
`shiny/flexdashboard/rmarkdown/knitr/bookdown/blogdown` (doc-site pipelines;
`e.fmt.markdown` exists for composition).

## 4. Top-50 Python packages

Covered: `numpy→e.math/e.algo.linalg.matrix/e.simd`,
`scipy→e.math.special/opt/ode/fft/filter + e.algo.stat`,
`statsmodels→` partial (§1; GLM → L007, VAR → L059),
`pandas/polars→` storage via `e.data.*` + `e.db.query/storage` +
`e.fmt.csv/parquet/arrow` (lazy-DataFrame API → L064),
`duckdb/sqlalchemy/drivers→e.db` contract, `requests/httpx/aiohttp→e.net` +
TLS/HTTP/WS/QUIC/MQTT, `fastapi/flask/django→` hand-build on `e.net.http` (no
router framework — non-goal), `pytest/hypothesis→e.test` family,
`black/ruff/mypy→` compiler fmt/tool, `poetry/uv→pacman`,
`networkx`-algorithms→`e.algo.graph` (draw → L062),
`geopandas`-math→`e.algo.geo` (render → L062),
`jupyter`-notebooks: non-goal.

Missing, now queued: `matplotlib/seaborn/plotly/altair/bokeh` (→ L061/L062),
`scikit-learn` pipeline/CV/GBM layer (→ L063),
`xgboost/lightgbm/catboost` (→ L063 histogram GBM).
Non-goals (D1785): `tensorflow/pytorch/keras` at scale, `transformers/nltk/
spacy/gensim` pipelines (no trained-model stacks per `docs/algos.md` model
skip), `streamlit/dash/panel/ipywidgets` (see §2 dashboards).

## 5. Backlog mapping

| Item | Title | Covers |
|---|---|---|
| L056 | Elementary inferential completions in `e.algo.stat` | z-tests, chi-square independence, Levene/Bartlett, Tukey HSD, power/sample-size, mode + weighted descriptives |
| L057 | Regularized and robust regression in `e.ml.linear` | elastic net, quantile + robust regression, polynomial features (L007 GLM excluded) |
| L058 | Multivariate core in `e.ml.reduce` / `e.algo.stat` | factor analysis, CCA, MANOVA, LDA/QDA |
| L059 | VAR and structural time-series in `e.algo.timeseries` | VAR(p), structural/state-space bridge to `e.math.filter` (ARIMA excluded → L017) |
| L060 | Variational inference in `e.math.mcmc` | ELBO / SVI / ADVI-lite over `e.ml.nn` autodiff |
| L061 | Standard statistical charts in `e.gfx.chart` | scatter/line/bar/hist/box/violin/density/heatmap/corr-matrix/facet → `e.gfx.scene` + PNG + `e.ui.widget` |
| L062 | Specialized visualization | interactive selection/zoom, geographic render, network layout, 3D surfaces |
| L063 | ML production core | histogram GBM, k-fold CV + tuning + pipeline, calibration |
| L064 | Tidy-data verbs atop L032 | mutate/select/relocate, joins, pivot wider/longer, window functions, missing-value verbs |
