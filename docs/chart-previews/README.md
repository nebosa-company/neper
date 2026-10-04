# Chart previews

The scatter, line, points+line, bar, grouped bar, signed stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip, beeswarm, binned dot plot, stem-and-leaf, range/interval, step, area, lollipop, error-bar, band,
dumbbell, slopegraph, connected scatter, marginal histogram, dose response, interval hazard, influence plot, capability sixpack, ECDF, box, boxen,
density, ridgeline, Q-Q, P-P, probability plot, violin, heatmap, correlation matrix, parallel coordinates, scatterplot matrix, faceted heatmap, shared/free
facet scales, log scatter, symmetric-log line, labeled line, labeled log scatter
and labeled symmetric-log line PNGs, plus the bubble, OLS fit, covariance data
ellipse, mean-confidence and prediction overlays, and categorical bar+line
combo, candlestick, OHLC bars, a price-volume chart, a returns/rolling-volatility chart, a hierarchical treemap, a sunburst, an icicle, circle packing, a population pyramid, a Sankey, an alluvial diagram, a chord diagram, a streamgraph, a horizon plot, seasonal subseries, a forecast fan chart, an additive decomposition plot, an ACF/PACF correlogram, an empirical variogram, a radar comparison, an area-scaled wind rose, a ternary composition plot, a quiver vector field, a streamline plot, a phase-space portrait, a recurrence plot, a drawdown chart, a cohort retention triangle, contour isolines and filled contour bands, rank-over-time ribbons, a target gauge, a KPI/target-status card, a mekko chart, a Pearson-residual mosaic, a count-based spine plot, an association plot, a fourfold display with confidence arcs, a two-set area-proportional Euler diagram, a nominal three-set Venn diagram, a measured weighted word cloud, a Gantt schedule, a milestone roadmap, a burndown chart, a burnup chart, an earned-value curve, a resource histogram, a risk matrix, a swimlane workflow, a Kanban board, a PERT/CPM network, a value-stream map, a future-state value-stream comparison, a cap-table issuance waterfall, a tornado sensitivity chart, a valuation football field, a yield-curve comparison, a Monte Carlo histogram and empirical CDF, a SIPOC overview, a decision tree, an org chart, a dependency graph, a flowchart, a state machine, a sequence diagram, an entity-relationship diagram, a branching process map, a state timeline, a status history, an event timeline, in-cell sparklines, in-cell data bars, a calendar heatmap, a forest plot, a Bland–Altman agreement plot, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve, plus residual-versus-fitted, leverage-versus-standardized-residual and Cook's-distance diagnostics, Kaplan–Meier survival, Nelson–Aalen cumulative hazard, Individuals and moving-range control charts, X-bar and subgroup-range control charts, and p, np, c and u attribute control charts, X-bar/S, two-sided CUSUM, EWMA, Laney P-prime/U-prime, geometric G and exponential T charts, plus an eight-test SPC run-signal chart, a phased Individuals chart, phased P/Np/C/U charts and phased Laney P-prime/U-prime charts and phased X-bar/R and X-bar/S chart pairs, are rendered by Neper's CPU scene and PNG encoder. All 217 have an SVG
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
The Nyquist preview maps a sampled second-order complex response to equal-scale
real/imaginary axes, reflects the conjugate negative-frequency branch, and marks
the critical point (-1, 0); it does not infer closed-loop stability.
The 3-D scatter preview projects a helix through an explicit perspective camera,
depth-sorts its circular marks and draws a twelve-edge reference cube.
The 3-D histogram bins x/y observations into a joint 5-by-5 grid, extrudes
nonempty counts into camera-facing prisms and painter-sorts their shaded faces.
The 3-D density surface projects explicit-bandwidth product-Gaussian KDE values
as filled quads; the 3-D wireframe projects an analytic two-peak scalar grid
as independent row and column traces through the same camera.
The one-way ANOM chart plots group means against a grand-mean center line and
pooled-variance decision limits. The critical value is caller-supplied; the
example uses `h = 3` to demonstrate flagged groups without assigning an
unsupported significance level.
The Hotelling T-squared chart computes covariance-adjusted distances from a
historical mean/covariance. It uses the Phase II individual-observation F limit
in the preview; the same API computes the Phase I beta limit when the
historical slice is empty.
The generalized-variance chart plots subgroup covariance determinants and
uses pooled Phase I covariance with a finite-reference correction. Its control
limits use a labeled moment-normal approximation, not exact tail quantiles;
Phase II subgroups do not alter the reference.
The MEWMA chart smooths correlated observations against a historical mean and
uses the finite-time EWMA covariance factor for its statistic. The preview's
upper limit is explicitly caller-selected; run-length calibration is not
claimed by this example.
The focused normal-capability chart compares observed bin counts with within-
and overall-sigma normal fits, marks both specification limits and the mean,
and reports Cp/Cpk/Pp/Ppk plus observed and model-estimated out-of-spec PPM.
The estimates assume normality; process stability must be checked separately.
The nonnormal-capability preview fits a two-parameter lognormal distribution
by maximum likelihood on the log scale and compares its expected bin counts
with the observed histogram. It reports overall Z-score Pp/Ppk and both
observed and fitted out-of-spec PPM; this is not a Weibull or general-family
selection tool, and the fit should be assessed before interpreting capability.
The gage-run preview keeps every crossed part/operator/repeat observation
visible, colors points by operator, separates parts and marks the overall mean.
The summary shows the grand mean and largest within-part/operator repeat range;
it does not estimate variance components or claim measurement-system approval.
The choropleth joins keyed district rates to caller-supplied polygon rings,
preserves a gray missing-data district, and renders holes with opposite winding.
The proportional-symbol map reuses the same map window and district boundaries;
its circle areas, including the size legend, scale with site volume. These
synthetic district outlines avoid implying a real administrative geography.
The initial map window supports equirectangular and Mercator projections and
can center on the antimeridian. It refuses unsplit rings that still cross the
map seam and out-of-window geometry; general polygon clipping and map-data
import remain planned.
The cross-tab report counts events across two categorical dimensions, with
explicit row, column and grand totals. The grouped matrix report sums numeric
values by row and quarter, distinguishes a missing cell from an observed zero,
and inserts group subtotals. Its blue in-cell bars use per-row normalization;
the report API also offers global scaling and no bars. Both previews use the
same report-cell geometry through the CPU scene and SVG adapters. Page breaks,
print layout and export of underlying tabular data remain follow-on work.
The future-state value-stream comparison places current and target process
flows on separate proportional lead-time ladders. The target shows pull and
FIFO control cues, a pacemaker stage, and a red stage marker where processing
time exceeds the demand-derived takt of four hours per unit. Its synthetic
plan reduces lead time from 16 to 10.2 hours and raises PCE from 44% to 69%;
those numbers describe the supplied scenario, not a predicted outcome.
The cap-table issuance waterfall uses one explicit share-count basis: three
existing holders own 10 million shares before a 2 million-share option-pool
top-up and 3 million-share investor issuance. The stacked bars show each
holder's before/after percentage; the lower bridge shows incumbents falling
from 100% to 67% through the two issuance events. It is an illustrative
ownership calculation, not a model of convertible securities, preferences or
valuation.
The tornado sensitivity chart orders one-at-a-time input cases by the absolute
spread between their paired modeled outputs. Blue and orange preserve which
input assumption produced each result, including cases whose direction
reverses. A common numeric output axis and baseline rule make the spans
comparable. The preview illustrates supplied scenarios; it does not estimate
input distributions or interactions between factors.
The valuation football field shows four illustrative method ranges on one
equity-value-per-share scale. Capped horizontal bars keep each low/high range
visible, and the red rule marks an explicit $100 reference. The method ranges
are supplied inputs, not estimates made by this chart; callers must keep
currency, valuation date and equity/enterprise basis consistent themselves.
The yield-curve preview overlays two synthetic rate term structures against
the same years-to-maturity and percent-yield axes. The plotted observations
are borrowed inputs, joined in tenor order; the chart neither downloads
market rates nor fits or extrapolates a financial model.
The Monte Carlo histogram and empirical CDF share 256 outcomes from one
fixed-seed, three-uniform toy model. The histogram shows exact bin counts;
the CDF steps at each sorted outcome. Both mark the same threshold at 70
and display the observed sample fraction at or below it. The pictures are
reproducible examples, not a calibrated forecast or confidence interval.
These previews come from `examples/chart_gallery.e`. From the repository
root on Windows, refresh them with:

```powershell
build/windows/tests/selfhost/neper-self.exe emit-executable examples/chart_gallery.e . x64 windows build/windows/tests/selfhost/chart-gallery.exe
build/windows/tests/selfhost/chart-gallery.exe
```
