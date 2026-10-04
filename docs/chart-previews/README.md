# Chart previews

The scatter, line, points+line, bar, grouped bar, signed stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip, beeswarm, binned dot plot, stem-and-leaf, range/interval, step, area, lollipop, error-bar, band,
dumbbell, slopegraph, connected scatter, marginal histogram, dose response, interval hazard, influence plot, capability sixpack, ECDF, box, boxen,
density, ridgeline, Q-Q, P-P, probability plot, violin, heatmap, correlation matrix, parallel coordinates, scatterplot matrix, faceted heatmap, shared/free
facet scales, log scatter, symmetric-log line, labeled line, labeled log scatter
and labeled symmetric-log line PNGs, plus the bubble, OLS fit, covariance data
ellipse, mean-confidence and prediction overlays, and categorical bar+line
combo, candlestick, OHLC bars, a price-volume chart, a returns/rolling-volatility chart, a hierarchical treemap, a sunburst, an icicle, circle packing, a population pyramid, a Sankey, an alluvial diagram, a chord diagram, a streamgraph, a horizon plot, seasonal subseries, a forecast fan chart, an additive decomposition plot, an ACF/PACF correlogram, an empirical variogram, a radar comparison, an area-scaled wind rose, a ternary composition plot, a quiver vector field, a streamline plot, a phase-space portrait, a recurrence plot, a drawdown chart, a cohort retention triangle, contour isolines and filled contour bands, rank-over-time ribbons, a target gauge, a KPI/target-status card, a mekko chart, a Pearson-residual mosaic, a count-based spine plot, an association plot, a fourfold display with confidence arcs, a two-set area-proportional Euler diagram, a nominal three-set Venn diagram, a measured weighted word cloud, a Gantt schedule, a milestone roadmap, a burndown chart, a burnup chart, an earned-value curve, a resource histogram, a risk matrix, a swimlane workflow, a Kanban board, a PERT/CPM network, a value-stream map, a SIPOC overview, a decision tree, an org chart, a dependency graph, a flowchart, a state machine, a sequence diagram, an entity-relationship diagram, a branching process map, a state timeline, a status history, an event timeline, in-cell sparklines, in-cell data bars, a calendar heatmap, a forest plot, a Bland–Altman agreement plot, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve, plus residual-versus-fitted, leverage-versus-standardized-residual and Cook's-distance diagnostics, Kaplan–Meier survival, Nelson–Aalen cumulative hazard, Individuals and moving-range control charts, X-bar and subgroup-range control charts, and p, np, c and u attribute control charts, X-bar/S, two-sided CUSUM, EWMA, Laney P-prime/U-prime, geometric G and exponential T charts, plus an eight-test SPC run-signal chart, a phased Individuals chart, phased P/Np/C/U charts and phased Laney P-prime/U-prime charts and phased X-bar/R and X-bar/S chart pairs, are rendered by Neper's CPU scene and PNG encoder. All 190 have an SVG
companion streamed from the same layout with title and
description metadata. Grouped and stacked bars include category labels and a
two-series legend in both formats. The labeled preview uses the repository's Montserrat
TrueType font for scene rendering; SVG viewers use their sans-serif fallback.
The hexbin preview assigns two synthetic clusters to a pointy-top hexagonal
lattice; colour intensity represents the observation count in each cell.
The 2D-bin preview uses the same two clusters on a rectangular grid, with
each tile coloured by its observation count.
The 2D-density preview evaluates a normalized Gaussian KDE on the same sample
and draws contours at fractions of its sampled peak density.
The half-violin preview keeps one KDE side; raincloud adds every observation
and a Tukey IQR/whisker summary on the same value axis.
Connected scatter follows observation order even when x reverses; marginal
histograms align exact x/y bin counts with their joint scatter panel.
Dose response shows observed values against a caller-parameterized LL.4 mean
on log dose; interval hazard divides event counts by observed person-time in
explicit right-closed intervals, including censored follow-up.
The influence preview uses leverage and internally standardized residuals;
Cook's distance controls bubble area and points with zero Cook's distance
remain visible under the bubble layer.
The individuals-only normal capability sixpack composes I/MR, recent samples,
histogram with within/overall normal fits, Q-Q and tolerance intervals; its
footer reports Cp, Cpk, Pp and Ppk from the same summary.
The fishbone preview groups candidate causes under six categories on alternating
ribs; the layout API also accepts deeper parent-linked subcauses.
The cause-effect tree instead places one effect at the right and recursively
branches possible causes to the left, reserving vertical space per leaf.
The Weibull probability plot uses NIST's 20-unit reliability example: ten
observed failures and ten units right-censored at 500 hours. Its straight
reference shows a caller-supplied shape of 1.5 and scale of 500 hours; this
gallery example does not estimate those parameters from the sample.
The OC curve plots the binomial probability of lot acceptance for NIST's
single-sample attributes plan (n=52, c=3) against incoming percent defective.
It assumes a large lot; finite-lot hypergeometric acceptance is not shown.
The Gage R&R component chart follows Minitab's published balanced crossed
ANOVA example, comparing variance contribution with study variation for
total gage, repeatability, reproducibility and part-to-part variation.
The two-factor multi-vari chart retains all readings while connecting setting
means only within each machine and connecting the machine means separately.
The main-effects chart shows raw level means and a grand-mean reference in
separate factor panels, retaining uneven per-level sample counts in its layout.
The two-factor interaction plot draws raw cell means as independently styled
series over a shared x axis; unequal cell counts remain available to callers.
The three-factor cube plot puts raw cell means at the eight two-level design
vertices, with A/B/C mapped to horizontal, vertical and depth directions.
The spectrogram maps one-sided STFT power to time/frequency cells in decibels
relative to unit power; the gallery's rising and steady tones use `e.dsp.stft`.
The waterfall spectrum reuses those STFT cells as separately colored,
perspective-offset frequency traces with retained source-frame indices.
The Bode preview plots a sampled low-pass complex response as magnitude dB and
unwrapped phase degrees in two panels with a shared log-frequency axis.
These previews come from `examples/chart_gallery.e`. From the repository
root on Windows, refresh them with:

```powershell
build/windows/tests/selfhost/neper-self.exe emit-executable examples/chart_gallery.e . x64 windows build/windows/tests/selfhost/chart-gallery.exe
build/windows/tests/selfhost/chart-gallery.exe
```
