# Neper charting engine plan

Status: scatter, line, points+line, bubble, OLS fitted line, OLS mean-confidence and prediction bands, covariance data ellipse, bar, grouped bar, signed stacked bar, 100% stacked bar, categorical bar+line combo with a secondary axis, candlestick, OHLC, price-volume, returns/volatility, waterfall, bullet, target gauge, KPI/target-status card, Pareto, population pyramid, pie, donut, radar, rose/wind, ternary, waffle, mekko, two-set Euler, three-set Venn, basic word cloud, treemap, sunburst, icicle, circle packing, Sankey, alluvial, chord, streamgraph, horizon, seasonal subseries, forecast fan, additive decomposition, ACF/PACF correlogram, empirical variogram, vector/quiver, streamlines, phase-space, recurrence, drawdown, cohort retention, contour, filled contour, rank-over-time ribbon, stage funnel, state timeline, status history, event timeline, in-cell sparklines, in-cell data bars, calendar heatmap, forest plot, Bland–Altman agreement, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve,
histogram, frequency polygon, rug, strip/jitter, beeswarm, binned dot plot, stem-and-leaf, range/interval bars, step, area, lollipop, error bars,
confidence bands, dumbbells, ECDF, box, boxen, density, hexbin, 2D rectangular bins, 2D KDE contours, ridgeline, normal Q-Q and P-P, probability paper, violin, half violin, raincloud, slopegraph, connected scatter, marginal histogram, dose response, interval hazard, influence plot, capability sixpack, heatmap,
correlation matrix, mosaic, spine plot, association plot, single-stratum fourfold display, parallel coordinates and scatterplot matrix are delivered, with linear/log10/symmetric-log and
reverse Cartesian scales, caller-owned ticks and text labels, linear/log nice
breaks, grid/axis passes,
basic category-center labels and per-series legend metadata, facet panel
geometry, explicit limits for shared/free facet scales, and
two hundred and seventeen PNG plus two hundred and seventeen SVG previews from Neper. Basic Gantt scheduling, milestone roadmaps, burndown, burnup, earned-value curves, a likelihood-impact risk matrix, a resource histogram, a basic swimlane workflow, a Kanban board layout, a PERT/CPM activity network, a single-stream value-stream map, a future-state value-stream comparison, a cap-table issuance waterfall, a tornado sensitivity chart, a valuation football field, a yield-curve comparison, a Monte Carlo histogram and empirical CDF, a SIPOC overview, an expected-value decision tree, a rooted org chart, a layered dependency graph, an explicitly placed flowchart, an event-labeled state machine, an ordered sequence diagram, an entity-relationship diagram, a branching process map, a fishbone/Ishikawa diagram, a cause-effect tree, a Weibull probability plot, a binomial OC curve, a crossed Gage R&R component chart, a two-factor multi-vari chart, a raw-data main-effects chart, a two-factor interaction plot, a three-factor cube plot, a one-sided spectrogram, a waterfall spectrum, a Bode plot, a Nyquist plot, a 3-D scatter plot, a 3-D histogram, a 3-D density surface, a 3-D wireframe, a one-way ANOM chart, an individual Hotelling T-squared chart, a generalized-variance chart, a MEWMA chart, a focused normal-capability chart, a fitted lognormal-capability chart, a binomial attribute-capability chart, a balanced batch-capability chart, a gage bias/linearity chart, an attribute-agreement chart, a crossed gage-run chart, a choropleth, a proportional-symbol map, a cross-tab report and a grouped matrix report are also delivered. Individuals, moving-range,
X-bar, subgroup-range, X-bar/S, p/np/c/u, Laney P-prime/U-prime, geometric G, exponential T, CUSUM and EWMA control charts are delivered. Kaplan–Meier
survival and Nelson–Aalen cumulative-hazard curves are delivered. OLS residual/fitted,
leverage/standardized-residual and Cook's-distance diagnostics are delivered.
L061 remains partial
until the remaining families, full export coverage and widget integration are
evidenced.

`hexbin` now maps bounded x/y observations to a pointy-top hexagonal lattice,
assigning every point (including panel-edge values) to its nearest valid cell.
It returns caller-owned counts and six-vertex polygons for the existing scene
and SVG adapters. The Windows/Linux fixture checks count conservation, corner
assignment, geometry, adapters and refusal paths; the gallery adds one PNG/SVG
pair. Adaptive bin sizing, weighted counts and contour/density smoothing remain
planned.

`bin2d` maps bounded x/y observations to caller-sized rectangular cells in
row-major screen order. Inclusive domain maxima go into the final column or
row; exact `u64` counts accompany heatmap-compatible cells and share the
existing scene/SVG matrix adapters. A Windows/Linux fixture checks exact
counts, corners and midpoints, geometry, adapters and refusal paths; the
gallery adds one PNG/SVG pair. Automatic bin sizing, weights and density
smoothing remain planned.

`density2d` evaluates a normalized product-Gaussian KDE on caller-owned
coordinate axes and grids, then reuses marching squares for contours at
increasing fractions of the sampled peak. `e.algo.stat.kde2d` exposes the
numeric kernel independently. The Windows/Linux fixture checks Gaussian
reference values, contour geometry, scene/SVG adapters and refusals; the
gallery adds one PNG/SVG pair. Automatic bandwidth selection and probability-
mass contour labels remain planned.

`half_violin` exposes a caller-selected side of the existing Gaussian KDE as a
single caller-owned polygon. `raincloud` composes that polygon with every raw
observation in deterministic jitter lanes and a Tukey R7 box/whisker summary,
all on the same KDE-extended value axis. Separate Windows/Linux fixtures check
left/right symmetry, quartiles, outlier visibility, adapters and refusals; the
gallery adds two PNG/SVG pairs. Collision-free raw-point packing remains
planned.

`slopegraph` maps paired before/after values to fixed left/right positions under
one shared vertical domain. It preserves caller series order through crossing
segments and emits both endpoints for direct labels. A Windows/Linux fixture
checks crossings, constant-domain expansion, scene/SVG adapters and refusals;
the gallery adds a labeled PNG/SVG pair. Automatic endpoint-label collision
avoidance remains planned.

`connected_scatter` reuses ordered PointLine geometry without sorting x,
retaining reversals and observation identity. `marginal_histogram` aligns a
scatter panel with exact equal-width x frequencies above and rotated y
frequencies beside it, including constant-data domain expansion. Separate
Windows/Linux fixtures check path order, exact counts, alignment, adapters and
refusals; the gallery adds two PNG/SVG pairs. Automatic sequence-label and
multi-panel placement remain planned.

`e.algo.stat.log_logistic4` evaluates a caller-parameterized four-parameter
log-logistic mean; `chart.dose_response` aligns observed responses and that
curve on log-dose coordinates. No parameter fitting or uncertainty estimate is
implied. `e.algo.stat.interval_hazard` divides events by observed person-time
for explicit right-closed intervals, retaining censored exposure; the chart
renders these estimates as a step curve. Windows/Linux fixtures check numeric
references, boundary assignment, layout, adapters and refusals, and two PNG/SVG
pairs join the gallery. Fitting, confidence bands, smoothing and delayed entry
remain planned.

`influence_plot` maps one-predictor OLS leverage and internally standardized
residuals to position, and Cook's distance to bubble area. Its point layer
retains zero-Cook observations; independent guide strokes mark +/-2 residuals
and two/three times mean leverage when in range. A Windows/Linux fixture checks
known diagnostics, geometry, adapters and refusal paths; one PNG/SVG pair joins
the gallery. Externally studentized residuals and automatic noteworthy labels
remain planned.

`normal_capability_individuals` estimates short-term spread from MR-bar/d2 and
long-term spread from sample standard deviation, then reports Cp/Cpk/Pp/Ppk
against two specifications. `capability_sixpack` composes six caller-owned
panels: I chart, MR chart, last 25 observations, histogram with both fitted
normal curves and specification rules, normal Q-Q, and within/overall/spec
intervals. A Windows/Linux fixture checks numeric references, panel geometry,
scene/SVG output and refusals; one PNG/SVG pair joins the gallery. This is the
individuals/normal variant; subgroup, other nonnormal families and probability confidence
bands remain planned.

`lognormal_capability` fits a two-parameter lognormal model by MLE on positive
individual measurements. Its overall Z-score Pp/Ppk, observed/fitted tail PPM,
histogram, fitted count curve and LSL/median/USL guides are separate from the
normal within/overall analysis. A Windows/Linux fixture checks log-scale MLE,
tail references, geometry, adapters and refusals; a PNG/SVG pair joins the
gallery. Weibull and other family selection, goodness-of-fit diagnostics,
subgroup handling and uncertainty intervals remain planned.

`binomial_capability` analyzes time-ordered defective-unit counts with unequal
inspected subgroup sizes. It reports the pooled defective fraction and PPM, a
Wilson confidence interval, target comparisons, cumulative weighted rate, a P
chart with subgroup-specific three-sigma limits, and points beyond those
limits. Caller-owned layouts share scene/PNG and SVG rendering; a Windows/Linux
fixture checks numeric references, target decisions, varying limits, adapters
and refusals. The gallery adds one PNG/SVG pair. Poisson defects per unit,
between/within capability, exact binomial intervals and wider stability rules
remain planned.

`batch_capability` provides a balanced, equal-size batch analysis using a
one-way random-effects ANOVA variance split. It reports within, between,
between/within and overall standard deviations, corresponding Cp/Cpk and
Pp/Ppk, observed and normal-model tail PPM, and a two-panel batch-means /
within-batch-SD chart with specification and pooled-spread guides. The
Windows/Linux fixture checks exact variance components, zero-between clamping,
scene/SVG adapters and refusal paths; one PNG/SVG pair joins the gallery.
Unequal subgroup sizes, alternative variance estimators, confidence bounds
and stability diagnostics remain planned.

`gage_linearity` fits ordinary least squares to replicate measurement-minus-
reference biases across at least five ordered reference standards. It reports
overall and per-reference bias, signed span drift, residual spread, slope
standard error and two-sided t p-value. A caller-supplied t critical draws
mean-bias confidence intervals alongside replicate points, per-reference means,
the fitted line and zero-bias guide. A Windows/Linux fixture checks an exact
synthetic bias slope and confidence limits, scene/SVG output and refusals; one
PNG/SVG pair joins the gallery. Automated critical quantiles, %bias versus
process variation, stability over time and broader gage diagnostics remain
planned.

`attribute_agreement` counts an appraiser's item as repeatable only when every
trial agrees, and as correct versus a known standard only when that consistent
rating equals the reference. The two-panel chart shows each appraiser's
within-appraiser and versus-standard fractions with exact Clopper–Pearson
confidence intervals. The summary separately counts items on which every
appraiser agrees, items on which all agree with the standard, and pooled
individual-rating agreement/kappa against the repeated standard; that pooled
kappa is not a per-trial average. A Windows/Linux fixture checks counts,
intervals, kappa, scene/SVG adapters and refusals, and the gallery adds one
PNG/SVG pair. Missing-standard analysis, more than 256 categories and
per-trial kappa remain follow-ons.

`gage_run` lays out every measurement from a crossed part/operator/repeat study
as an individual point, with a separate mark layer per operator, vertical part
dividers and an overall-mean reference. `gage_run_summary` reports the grand
mean, observed extrema and largest within-cell repeat range from part-major,
operator-major, repeat-major data. Caller-owned buffers hold every mark; no
observations are collapsed into averages. A Windows/Linux fixture checks exact
summary statistics, part positions, mean guide, scene/SVG output and refusal
paths. The gallery adds a PNG/SVG pair. Nested-operator and time-ordered
stability studies remain follow-ons.

`choropleth` joins keyed metric values to caller-supplied region rings and
projects WGS84-degree vertices through a shared equirectangular or Mercator
window. It produces one fill-ready compound polygon per region, normalizing
outer and hole winding for matching scene/SVG fills and retaining missing
regions separately from numeric zero. `proportional_symbol_map` projects keyed
sites through the same window and scales circle area with nonnegative values.
The Windows/Linux fixture checks projection references, dateline-centered
continuity, keyed values, missing data, hole winding, area ratios, adapters and
refusals; two PNG/SVG pairs join the gallery. This first map slice requires
caller-supplied boundaries entirely within the window; it rejects geometry
that crosses the opposite seam. Automatic clipping, map-file import, geographic
legends and accessible per-region metadata remain planned.

`cross_tab_report` uses exact `u64` category intersections, row and column
totals, and a grand total, then lays out a header-and-total grid in caller-owned
cells. `matrix_report` aggregates finite values while retaining observed zero
separately from missing, inserts a subtotal after each contiguous row group,
and adds marginal and grand totals. Positive in-cell bars have explicit
per-row or global normalization; negative sums are rejected when bars are
requested. Shared scene/SVG adapters paint matching cells and bars. The
Windows/Linux fixture checks counts, sums, nulls, group geometry, scaling and
refusals; two PNG/SVG pairs join the gallery. Pagination and print drivers
remain host-service work.

`fishbone` lays out a right-facing effect, alternating category ribs and
parent-linked causes, including deeper subcauses, as caller-owned segment,
rectangle and text-label layers. Its Windows/Linux fixture checks exact rib
placement, a three-level chain, SVG escaping, adapters and refusals; one
PNG/SVG pair joins the gallery. Measured text collision avoidance and an
interactive brainstorming editor remain planned.

`cause_effect_tree` keeps one effect at the right and places its causes in
leftward columns, reserving one vertical slot per terminal cause. Parent indices
must precede children; the caller owns the placement work, box, connector and
label storage. This is a hierarchy of candidate causes, not an AND/OR fault
tree or proof of causation. Its Windows/Linux fixture checks unbalanced
subtrees, exact geometry, escaping, adapters and refusals; one PNG/SVG pair
joins the gallery. Automatic text fitting and interaction remain planned.

## What the references say

- **ggplot2** supplies the best semantic spine: data, aesthetic mappings, layers,
  scales, facets, coordinates, themes, and guides. Its defaults are valuable;
  its grammar is the part Neper should keep. See the official introduction:
  https://ggplot2.tidyverse.org/articles/ggplot2.html
- **Base R graphics** supplies the broad primitive vocabulary and method dispatch:
  points, lines, segments, rectangles, polygons, axes, annotations, layout,
  histograms, box plots, contours, images, pairs, symbols, and perspective.
  `plot.default(type=...)` also documents points, lines, both, stairs, and
  histogram-like marks. See:
  https://stat.ethz.ch/R-manual/R-devel/library/graphics/html/00Index.html
- **lattice/Trellis** supplies the panel model: a plot object is computed first,
  then printed into conditioned panels with shared or independent scales. This
  maps directly to a facet stage over one common mark/layout contract. See:
  https://stat.ethz.ch/R-manual/R-devel/library/lattice/help/Lattice.html
- **celvyx** shows the product-scale breadth worth borrowing: its pack plans cover
  statistical diagnostics, SPC, finance, operations, quality, science and
  engineering charts. The useful lesson is to keep the chart type registry thin
  and put calculations in domain modules; do not copy its UI-specific painter
  architecture into Neper.
- **sixsg** contributes a practical shortlist (histogram, box, scatter, SPC,
  probability/ECDF, KDE, ROC, Bland–Altman, fan, bee-swarm and rug plots) and
  a no-third-party-library/offline principle. Its current browser path delegates
  general plots to webR/plotly; Neper should own deterministic geometry instead.

## Design contract

`e.gfx.chart` is the grammar boundary. It borrows numeric columns, maps them into
caller-owned screen-space marks, and never owns a device, window, global theme or
data frame. The same `Layout` can be appended to `e.gfx.scene` or SVG, with
scene output rasterized and PNG-encoded; PDF, widget and GPU-buffer adapters
remain future work.

The stable sequence is:

1. **Data** — typed columns/views; missingness and categorical levels are explicit.
2. **Mapping** — x/y plus colour, fill, size, shape, group, weight and facet keys.
3. **Statistics** — binning, summaries, smoothing and model overlays, each pure and
   independently testable.
4. **Scales** — linear, log10, symmetric-log and reverse Cartesian mapping are
   delivered, with equal transformed-space tick metadata. `nice_ticks` adds
   1/2/5 linear steps and sampled 1/2/5 log decades; symmetric-log retains
   equal transformed-space positions. `category_ticks` places ordinal category
   centers for bar labels, without a full discrete scale. `date_axis_line`
   maps civil dates by elapsed days; `date_ticks` and `format_date_ticks`
   provide month starts and ISO year-month labels. Broader date/time scales,
   locale formatting and out-of-bounds policy remain.
5. **Coordinates** — Cartesian first; polar, flipped, fixed-aspect, map and 3-D
   projections later.
6. **Geometries** — marks only; no data analysis hidden in a painter.
7. **Facets/layout** — trellis panels, shared/free scales, strips and guides.
8. **Theme/guides** — typography, grid, axes, legends, colour-blind palettes,
   alt text and export metadata.
9. **Backend** — scene display list first, then PNG/SVG/PDF and interactive hit data.

The delivered foundation implements the first geometry contract for scatter, line
and bar marks, including empty/mismatched/non-finite input refusal, constant-domain
padding, inverted screen Y, bar baseline inclusion and caller-storage bounds.
The first distribution slice adds equal-width histograms with caller-owned counts
and contiguous rectangles. Its final bin includes the maximum, and a constant
sample is centered in a padded domain. Step/stairs maps ordered x/y columns
into horizontal then vertical segments. `e.gfx.chart.scene` appends the same
marks to a scene display list; `examples/chart_gallery.e` renders the delivered
kinds through the CPU renderer and PNG encoder. ECDF accepts an ascending sample
and emits exact 1/n rises, including tied observations. Box plots reuse R7
quartiles for Tukey whiskers; density reuses Gaussian KDE with an explicit or
Scott bandwidth; Q-Q plots reuse normal quantiles and an R7 quartile reference.
Boxen plots reuse R7 quantiles for nested letter-value ranges with explicit
depth, median rule and tail observations beyond the outer box.
Normal P-P plots compare empirical midpoint ranks with a caller-specified normal CDF and the identity line.
Violin plots mirror that same Gaussian estimate into a filled outline.
Ridgeline plots evaluate per-group Gaussian KDE on one shared x grid and draw
filled Area layers on spaced baselines. A global density peak preserves height
comparability; the caller controls bandwidth, overlap, group membership and
storage. `gfx_chart_ridgeline` checks numeric values, refusal paths and both
adapters on Windows and Linux. Group-wise weights and transformed x scales remain.
Frequency polygons reuse histogram counts and join bin centers to zero at the
outer edges. Rugs map every observation to an independent short x-axis stroke,
preserving ties rather than binning them. Both reuse the existing line/stroke
adapters and keep output storage with the caller.
Points+line combines the existing Cartesian scatter and line layouts with one
domain and paints the line before its points. Strip plots map observations to
numeric x positions and add repeatable vertical jitter, preserving ties; both
use caller-owned coordinates and the existing scene/SVG mark paths.
`bubble` reuses the scatter mapping and independent x/y scales, then maps a
nonnegative size column to circle area via square-root radius. Circle bounds
remain caller-owned; scene paints cubic-circle paths and SVG emits circle marks.
Zero-sized observations stay in the data but are invisible. A quantitative
size legend, overlap policy and alternate area transforms remain guide work.
`regression_line` uses the existing streaming bivariate accumulator for an
ordinary-least-squares fit, then returns a Line layer and a domain covering both
observations and fitted endpoints. `covariance_ellipse` uses its sample covariance
and a caller-selected Mahalanobis radius to trace a data ellipse; it refuses
singular covariance. These are linear-coordinate overlays that share explicit
limits with scatter marks and reuse Line scene/SVG adapters. A data ellipse is
not a confidence region for the mean. `regression_interval` uses the same OLS
accumulator, residual variance with n-2 degrees of freedom and leverage to
produce either a two-sided mean-confidence or new-observation prediction
ribbon. The caller supplies the appropriate Student-t critical value and
polygon resolution; the filled Band and fitted Line share a domain including
observations. `gfx_chart_overlays` checks numeric values and both adapters on
Windows and Linux. Simultaneous confidence bands, nonlinear smoothers,
automatic quantiles and transformed-axis overlays remain planned.
`e.algo.stat.regression_diagnostics` emits fitted values, raw and internally
standardized residuals, leverage and Cook's distance from one streaming OLS
fit into caller storage. It refuses singular x, exact fits and undefined
influence statistics. Scatter and Lollipop layouts produce three diagnostics
without a new painter. `gfx_chart_regression_diagnostics` checks reference
numbers and scene/SVG output on Windows and Linux. Leave-one-out residuals and
robust regression remain planned.
`e.algo.stat.survival_curve` groups sorted nonnegative follow-up times,
applying tied events before censoring at each time. It emits a time-zero
baseline, Kaplan–Meier survival, Nelson–Aalen cumulative hazard and counts
at risk/events/censored into caller storage. Existing Step and Scatter marks
render the two curves and censor marks. `gfx_chart_survival` checks reference
fractions, ties, all-censored data, malformed input and scene/SVG adapters on
Windows and Linux. Greenwood intervals, log-rank comparisons and competing
risks remain planned.
`e.algo.stat.imr_limits` derives consecutive moving ranges and the standard
three-sigma Individuals/MR limits. `xbar_r_limits` derives subgroup means,
ranges and A2/D3/D4 limits for equal subgroups of size 2–10. Both reuse
PointLine and Rug marks for observations and upper/center/lower rules.
`gfx_chart_control` checks NIST numeric references, invalid/capacity paths and
scene/SVG output on Windows and Linux. `xbar_s_limits` uses subgroup sample
standard deviations with the c4 bias correction for three-sigma mean and S
limits. `cusum_control` computes upper/lower tabular sums and decision signals;
`ewma_control` computes recursive weighted means with startup-adjusted limits.
`gfx_chart_weighted_control` checks numeric references and refusal paths on
Windows and Linux. `subgroup_control_phased` reuses the X-bar/R or X-bar/S
calculator within each phase of at least two equal-size subgroups and returns
per-subgroup mean and spread limits. `gfx_chart_subgroup_phases` compares both
modes with independent phase calculations and checks refusal paths on Windows
and Linux; four phase-split PNG/SVG previews show X-bar/R, R, X-bar/S and S.
`imr_phase_control` estimates separate Individuals limits
for each phase of at least two observations, excludes cross-boundary moving
ranges, and emits per-point limits. The gallery shows a visible phase split;
unequal subgroup sizes and historical parameter overrides remain planned.
`e.algo.stat.attribute_control` computes pooled binomial p/np and Poisson c/u
three-sigma values and limits in caller storage. Variable subgroup sizes
change p/u limits per observation; np requires equal size and c equal unit
area. P limits clamp to [0,1], np to [0,n], and all lower limits to zero.
PointLine and Rug marks draw observed values and three control-limit traces.
`gfx_chart_attribute_control` checks reference values, malformed sizes, bounds
and scene/SVG output on Windows and Linux. `attribute_control_phased` reuses
the P/Np/C/U estimator within each phase, requiring at least two subgroups
and allowing Np subgroup size to change only at a boundary. Four phase-split
PNG/SVG previews disconnect the limit traces; `gfx_chart_attribute_phases`
checks numeric equivalence to independent phases and refusals on both hosts.
`laney_control` reuses p/u values,
standardizes each by its subgroup-specific binomial or Poisson sigma, and
multiplies the ordinary three-sigma limits by the adjacent z-score moving-range
estimate divided by 1.128. `gfx_chart_laney` checks overdispersion, variable
subgroup sizes and refusals on Windows and Linux. `laney_control_phased`
estimates center and Sigma Z independently per phase, excluding boundary
moving ranges; two phase-split PNG/SVG previews reuse the attribute renderer.
`gfx_chart_laney_phases` compares both P-prime/U-prime to independent stage
calculations and checks refusals on Windows and Linux.
`g_control_limits` fits the geometric event probability from whole-number
opportunities between events and interpolates the 0.135%, 50% and 99.865%
CDF percentiles. `t_exponential_control_limits` fits positive elapsed times
with an exponential mean and uses the same tail probabilities. Both reuse
PointLine/Rug rules; `gfx_chart_rare_event` checks numeric references,
degenerate/invalid inputs and a large-gap case on Windows and Linux. Date
conversion, Weibull T limits, simultaneous events and rare-event run tests
remain planned.
`control_run_rules` checks the eight standard special-cause tests with
per-observation centers and sigmas, marking the point that completes each
pattern. `gfx_chart_run_rules` checks every test, strict boundary behavior,
varying sigma and refusal paths on Windows and Linux. The PNG/SVG preview
uses PointLine, Rug and highlighted Scatter marks. `control_run_rules_phased`
resets all eight test windows at each boundary; `gfx_chart_phases` checks
reset and malformed-boundary behavior on Windows and Linux. Automatic
chart-specific test selection and false-alarm calibration remain planned.
Binary classification diagnostics share `e.algo.stat.binary_curve`: a caller-owned
descending score order, with tied scores advanced as one threshold. The same
cumulative true/false-positive counts yield ROC, precision–recall, cumulative
gain and lift geometry. `roc_auc` uses trapezoids and `average_precision` uses
recall-weighted precision steps; neither invents a threshold inside a tied
score. `gfx_chart_binary_curves` checks reference values, all-one-class and
storage refusals, and scene/SVG output on Windows and Linux. Equal-width
calibration bins aggregate mean predicted and observed probabilities; a
caller-selected threshold produces four confusion counts. Existing PointLine
and Heatmap layouts draw both, without new mark types. `gfx_chart_diagnostic_tables`
checks numeric references, refusals and both adapters on Windows and Linux.
ROC extensions integrate the tie-grouped sweep to a caller-selected false-positive
cutoff, fill that raw partial-AUC region with an Area mark and identify the first
threshold attaining maximal Youden J. Decision curves evaluate probability
thresholds for model and treat-all net benefit against treat-none zero, using
the existing confusion counter and Line/Rug marks. `gfx_chart_binary_curves`
checks numeric references, bounds, capacity and scene/SVG output on both hosts.
Beeswarm starts from strip's exact numeric x mapping and packs overlapping
six-pixel square marks into free vertical lanes. The current candidate scan is
cubic in the worst case and refuses a panel too short to fit every observation.
Binned dot plots reuse histogram counts and place one caller-owned point per
observation at its bin center, refusing vertical overflow. Both use the same
scatter mark adapters, with lane height kept separate from a numeric y scale.
Area plots close ordered x/y points against an explicit baseline; lollipops
reuse the same baseline and point mapping. Error bars borrow center/lower/upper
columns, validate containment and emit a stem, two caps and a point per row.
Confidence bands close ordered lower/upper series into a filled caller-owned
polygon. Dumbbells use numeric vertical positions and horizontal lower/upper
endpoints, emitting one segment and two points per row. Both reject inverted
intervals and render through the existing scene and SVG mark branches.
Grouped bars borrow category-major values and return per-series `Bar` layouts
over caller-owned rectangles, so the scene/SVG adapters can colour each series
without a new mark type. Stacked bars accumulate positives and negatives away
from zero; the normalized variant requires a positive, nonnegative total in
every category. `category_ticks` drives the existing label pass at each bar
center; `legend_items` borrows series names and emits swatch/label positions.
The caller supplies colours and decides where the legend fits. Automatic
legend placement, wrapping and collision handling remain planned.
`bullet` returns widest-to-narrowest qualitative ranges, a slimmer actual bar
and a target rule as separate caller-owned layers sharing one zero-to-maximum
scale. Existing Bar and Rug adapters paint them; category labels and automatic
palette selection remain caller/guide work.
`gauge` returns a background half-ring, measured-value half-ring and target
rule as Area/Rug layers over an explicit positive maximum. `target_status`
computes signed actual-minus-target delta and threshold attainment for either
higher- or lower-is-better metrics. The gallery composes it with the existing
bullet layers into a KPI card. `gfx_chart_gauge` checks boundary geometry,
range/storage refusals, target direction and both adapters on Windows and
Linux. Dynamic labels and warning/critical thresholds remain caller work.
`pareto` stably orders nonnegative category counts, exposes that order for labels,
and returns frequency Bar and cumulative-fraction PointLine layers with independent
left count and right percentage domains. It refuses zero totals; the gallery
labels both axes. The insertion sort is quadratic until category counts warrant
a caller-scratch mergesort.
`population_pyramid` maps two nonnegative age columns to left/right Bar layers
with one shared maximum, a caller-sized central label gutter and row gaps.
Input runs youngest to oldest, displayed bottom to top. The fixture checks
mirrored geometry, invalid counts, gaps and storage plus scene/SVG adapters on
Windows and Linux. Age labels and series names remain caller-owned guide text.
`combo_bar_line` composes existing Bar and PointLine layouts at identical
category centers. The bar domain includes zero; the line keeps its independent
vertical domain, and the caller renders the corresponding left/right guides.
It rejects mismatched/non-finite columns and short storage. The gallery's
secondary-axis preview reuses the Pareto guide renderer, with numeric right
labels instead of percentage labels. Arbitrary x positions, more than two
vertical scales and aligned axis tables remain planned.
`candlestick` and `ohlc` borrow open/high/low/close columns at strictly increasing
numeric x positions. The shared domain validates the price envelope and pads
the first and last marks by half the smallest x interval. Candlestick emits
wick strokes, rising bodies and falling bodies as separate caller-coloured
Rug/Bar layers; doji bodies become horizontal strokes. OHLC emits high-low
stems plus left-open and right-close ticks. Both use the existing scene/SVG
adapters and have numeric/refusal fixtures on Windows and Linux. Date labels,
corporate-action adjustment remains separate work. A price-volume companion
shares a padded numeric x domain across a closing-price Line and volume Bars;
`gfx_chart_price_volume` checks irregular positions, alignment, invalid prices
and volumes, capacity refusals and scene/SVG output on both hosts. Simple
per-observation returns and trailing sample-SD volatility share x across two
panels; `gfx_chart_returns_volatility` checks numeric references, flat series,
invalid windows, alignment and both adapters on Windows and Linux. Neither
calculation annualizes or adjusts for dividends and corporate actions.
`pie` turns nonnegative category weights into caller-owned slice polygons. A zero
inner-radius ratio yields pie slices; a ratio between zero and one yields a donut.
Each slice is an Area layer shared by scene and SVG; callers supply colours and
labels. Zero totals, invalid bounds/ratios and short storage are refused. A fixed
96-segment full-circle budget is the current tessellation ceiling; adaptive
segment selection belongs with zoom-aware rendering.
`waffle` partitions a fixed rectangular grid among nonnegative category weights,
rounding cumulative boundaries while preserving the exact cell count. Each
category receives a caller-owned Bar layer; callers choose grid dimensions,
cell gap, colours and labels. The ordered rounding can differ from ideal share
by one cell per category; largest-remainder assignment remains an upgrade path.
`treemap` accepts a parent-before-child hierarchy with leaf weights and returns
one rectangle per node, partitioning each parent along its longer side in
sibling order. Leaves reuse Bar layers and caller-owned colours; callers may
outline group rectangles and label them. The slice-and-dice scan is quadratic
and can create long strips; a caller-scratch squarified layout is future work.
The fixture checks proportions, hierarchy/refusal cases and scene/SVG output
on Windows and Linux.
`sunburst` shares treemap's validated leaf-weight hierarchy. It assigns each
node an angular span proportional to its subtree, one ring per depth, with
shallow leaves extending to the outer rim. Caller-owned arcs, points and Area
layers pass through the existing scene/SVG adapters; zero-total nodes emit
empty layers. A caller-selected center-hole ratio leaves room for a root label.
The fixture checks shares, depths, zero leaves, refusal paths and both adapters
on Windows and Linux. Label collision and adaptive curved tessellation remain.
`icicle` reuses the same hierarchy totals and Bar adapter, placing each depth
in a horizontal band and dividing parent widths by subtree share. Positive
leaves extend to the panel bottom; zero-total nodes retain empty layers.
Caller-owned rectangles and depths make the layout deterministic. The fixture
checks proportions, depth, zero leaves, storage refusals and scene/SVG output
on Windows and Linux. Preceding-sibling scans are quadratic until larger trees
justify caller-owned cursors.
`circle_pack` shares the validated hierarchy, placing ordered siblings as
non-overlapping circles inside their parent. Each group uses one ring; sibling
circle areas are proportional to subtree totals, with caller-selected padding.
Caller-owned circle bounds reuse Bubble scene and SVG adapters, and zero-total
nodes emit empty layers. The fixture checks area ratios, containment, separation,
invalid input and storage refusals on Windows and Linux. Ring placement is
deterministic but not density-optimal; tangent packing remains an upgrade path.
`sankey` takes ordered nodes in zero-based columns and nonnegative weighted
forward links. A common pixel-per-unit scale keeps each ribbon's thickness
constant through every column; nodes use the larger of incoming and outgoing
flow, leaving slack for imbalance. Caller-owned node rectangles and smoothstep
Area polygons reuse Bar and Area scene/SVG adapters, with links painted first.
The fixture checks two- and three-column numeric geometry, zero links, refusals
and both adapters on Windows and Linux. The current input order is stable but
can produce crossings; automatic barycentric reordering and interactive
highlighting remain planned.
`alluvial` reuses Sankey geometry but requires each link to join adjacent
columns and each interior node to conserve its incoming and outgoing flow.
The caller assigns stable cohort colours across stages; the gallery shows
four stages and twelve separately colourable ribbons. Input-order stacking
can still produce crossings, and cohort identity is supplied by the caller.
`streamgraph` stacks nonnegative sample-major series around a centered
silhouette baseline, using one scale across all times and caller-owned Area
polygons. It reuses the existing scene/SVG fill adapters; the focused fixture
checks geometry, malformed values, storage and both adapters on Windows and
Linux. Wiggle offsets and automatic layer ordering remain planned.
`ribbon_rank` maps sample-major values to equal-height ordinal bands, with
larger values ranked first and stable input-order ties. Caller-owned Area
polygons reuse both renderers; `gfx_chart_ribbon_rank` checks reference ranks,
ties, malformed inputs, capacity and scene/SVG output on Windows and Linux.
Missing categories and curved crossover interpolation remain planned.
`chord` lays out a square row-major directed matrix as group arcs and
one ribbon per unordered pair. Opposite cell weights control the two ribbon
ends independently, retaining asymmetry; diagonal values form self loops.
Zero pairs emit empty layers. Caller-owned Area polygons paint through the
existing scene/SVG adapters, with fixed-step quadratic curves and group rings
drawn on top. The fixture checks reference geometry, refusal paths and both
adapters on Windows and Linux. Adaptive tessellation and interactive
highlighting remain planned.
`mekko` maps nonnegative category-major values into variable-width columns
with within-column stacks. Each rectangle's area equals its value's share
of the grand total; zero-total categories are retained as zero-width columns.
It returns series-major Bar layers through the existing scene/SVG adapters.
`gfx_chart_mekko` checks proportions, empty and invalid inputs, storage and
both adapters on Windows and Linux. Gaps are omitted to preserve area.
`mosaic` maps a nonnegative contingency table to area-proportional cells and
computes signed Pearson residuals from independence for diverging colour.
Optional gutters separate positive cells; zero-count cells emit no tile.
`gfx_chart_mekko` checks numeric residuals, area, refusals and both matrix
adapters on Windows and Linux.
`association` uses square-root expected counts for rectangle widths and signed
Pearson residuals for heights around a separate baseline per row; the common
horizontal and vertical scales preserve area proportional to observed-minus-
expected counts. It reuses matrix colour adapters and Rug baseline strokes.
`gfx_chart_mekko` checks reference residuals, width ratios, independence,
refusals and scene/SVG output on Windows and Linux.
`fourfold` accepts one column-major 2x2 table, equalizes both margins while
retaining the odds ratio, and draws four caller-owned quarter-circle polygons
whose areas follow standardized frequencies. Optional Wald confidence arcs
use the existing Rug stroke adapter and apply a 0.5 continuity correction if
any observed cell is zero. `gfx_chart_mekko` checks odds ratio, interval,
radii, independence, refusals and scene/SVG on Windows and Linux. Multi-stratum
auto layout, alternate standardizations and multiplicity adjustment remain.
`horizon` folds signed deviations from an explicit origin into positive and
negative colour bands of caller-selected width. It splits linear segments at
each band threshold before creating caller-owned Area quadrilaterals, so
crossings and irregular x spacing retain their correct geometry. Values beyond
the selected band range are refused rather than silently clipped.
`gfx_chart_horizon` checks threshold geometry, band identity, irregular spacing,
refusals and scene/SVG output on Windows and Linux. Automatic origin and band
selection, missing-data gaps and more compact paths remain planned.
`seasonal_subseries` groups successive cycles by caller-selected period, draws
each phase as its own Line and marks its arithmetic mean with a Rug rule.
Partial final cycles retain the available observations, while one-cycle input
is refused. `gfx_chart_seasonal` checks geometry, means, partial cycles, flat
data, invalid/storage refusals and scene/SVG output on Windows and Linux.
Explicit timestamps/phases, missing-data gaps and alternative base functions
remain planned.
`fan` accepts band-major outer-to-inner forecast intervals plus a median
curve, validates quantile nesting and maps all bands to one shared domain.
Band polygons and the median Line reuse the existing scene/SVG adapters;
`gfx_chart_fan` checks irregular x positions, flat distributions, crossing
refusals, capacity and both adapters on Windows and Linux. Precomputing
quantiles from simulations, coverage labels and observed-history anchors
remain planned.
`decomposition` computes classical additive trend, seasonal and remainder
components from evenly spaced observations. A centered moving average uses
half-weighted endpoints for even periods; phase means are centered to zero.
Four Line panels share the time axis while scaling their y values separately,
and trend/remainder omit the endpoint samples without full windows.
`gfx_chart_decomposition` checks exact odd/even references, flat data,
invalid/capacity refusals and scene/SVG output on Windows and Linux.
Multiplicative/STL decomposition, missing data and date labels remain planned.
`euler2` sizes two circles from set totals and solves their separation for the
specified intersection area. Disjoint and containment cases have explicit
layouts. `venn3` makes a nominal three-circle diagram with anchors in all seven
membership regions; it does not encode seven arbitrary region areas.
`gfx_chart_venn_euler` checks overlap references, membership anchors, invalid
inputs, capacity and both scene/SVG adapters on Windows and Linux.
`word_cloud` takes pre-tokenized, unique words with weights and normalized font
metrics, filters an exact-match exclusion list, maps weight to type size and
packs non-overlapping caller-owned text boxes by a deterministic spiral.
`gfx_chart_word_cloud` checks weight order, exclusions, overlap/bounds,
refusals and text output through scene/SVG on Windows and Linux. Tokenization,
case normalization, font embedding and large-cloud packing remain planned.
`state_timeline` maps ordered half-open intervals with f64 time endpoints into
row-aligned Bar layers, coalescing exact abutting equal states and leaving
missing spans blank. It refuses overlaps, out-of-order rows, out-of-domain
times and short storage. The same layout supports an operational state timeline
and a status-history preview with separate caller-owned legends; the focused
fixture checks geometry and scene/SVG adapters on Windows and Linux. Date/time
tick formatting, timezone semantics and event annotations remain planned.
`gantt` maps task start/end times and completion fractions into two caller-owned
Bar layers over one explicit time domain and categorical rows. Tasks may arrive
in any order; invalid intervals, out-of-domain times, invalid completion and
short storage are refused. `gfx_chart_gantt` checks geometry, progress values,
refusals and scene/SVG output on Windows and Linux. Dependencies, critical-path
calculation and calendar scheduling remain planned.
`sparkline` assigns evenly spaced x positions to dense numeric samples and
reuses Line layout without guides; the gallery composes four in-cell rows.
`calendar_heatmap` accepts sorted day offsets, a Monday-first weekday and a
bounded 366-day domain, leaving missing offsets unpainted. It returns sparse
Heatmap cells with caller-selected gaps; scene and SVG matrix adapters accept
those sparse cells. `gfx_chart_calendar_sparkline` checks geometry, refusals
and both adapters on Windows and Linux. Calendar/date labels, locale rules,
missing-value policy for sparklines and shared cell scales remain planned.
`event_timeline` maps ordered f64 timestamps to lane-centered Lollipop marks
with caller-owned points and stems. `in_cell_bars` maps nonnegative values to
horizontal Bar marks inside caller-supplied cells against one explicit maximum;
zero values leave the track blank. `gfx_chart_events_cellbars` checks large
timestamps, geometry, ordering, bounds/capacity refusals and scene/SVG output
on Windows and Linux. Event labels and row names remain caller-owned; collision
avoidance and nullable/reporting data remain planned.
`milestone_roadmap` reuses the ordered event positions and maps each event to a
filled diamond Area layer. It preserves the explicit f64 time domain, rejects
out-of-order times, invalid rows, oversize markers and short caller storage,
and leaves lane labels with the caller. `gfx_chart_milestone_roadmap` checks
geometry, refusals and scene/SVG output on Windows and Linux. Dependency
connectors and calendar/time-zone semantics remain planned.
`burndown` computes a linear ideal remaining-work trace from the starting
total to zero over the observed time domain. `burnup` pairs completed work
with a changing scope trace and refuses completion above scope. Both reuse
Line marks with ordered x positions and shared nonnegative y limits; actual
burndown work may rise after scope changes. `gfx_chart_burn` checks irregular
times, numeric references, flat data, refusals and scene/SVG output on Windows
and Linux. Missing observations, sprint-calendar dates and forecast confidence
intervals remain planned.
`earned_value` aligns planned value (PV), earned value (EV) and actual cost
(AC) on one numeric time/value domain. The PV curve may continue beyond the
observed EV/AC prefix, keeping the reporting point distinct from the plan
horizon. It validates nonnegative finite values, ordered time and caller
capacity, then reuses three Line layouts and existing adapters.
`gfx_chart_earned_value` checks partial-horizon alignment, numeric references,
flat data, refusals and scene/SVG output on Windows and Linux. Forecasts,
variance indices and earned-value estimation stay with project analytics.
`risk_matrix` lays caller-supplied nonnegative rating values into a square
likelihood-by-impact heatmap, with high impact at the top, and separately counts
risks in each cell. The caller defines the rating policy and colour scale; the
layout does not infer severity thresholds. `gfx_chart_risk_matrix` checks the
orientation, duplicate counts, invalid input, caller capacity and scene/SVG
output on Windows and Linux. The gallery includes a labeled PNG/SVG pair.
`resource_histogram` splits an explicit time domain at every assignment start
and end. For each resulting period it sums concurrent resource units, then
returns normal and excess Bar layers split at caller-supplied capacity plus a
capacity Rug rule. It preserves short overloads instead of averaging into
fixed bins. `gfx_chart_resource_histogram` checks exact period loads, gaps,
overload geometry, invalid inputs, capacity refusals and scene/SVG output on
Windows and Linux. The gallery includes a labeled PNG/SVG pair.
`swimlane` places role-partitioned process steps in caller-sized stage columns
and lane rows. Forward links may cross lanes; each reuses Rug strokes for an
orthogonal elbow and directional arrowhead. The caller owns step labels and
lane colours. `gfx_chart_swimlane` checks handoff geometry, same-lane links,
duplicate/out-of-range nodes, backward links, storage refusals and scene/SVG
output on Windows and Linux. The gallery includes a labeled PNG/SVG pair.
This is a basic diagram layout, not a BPMN 2.0 execution model or interchange
format; gateways, events and automatic collision routing remain planned.
`kanban` lays variable-height cards in caller-specified workflow columns,
preserving their input order within each column. It returns column and card
rectangles plus counts and WIP-limit status; a breached limit remains visible
instead of deleting or refusing cards. A zero limit means unrestricted.
`gfx_chart_kanban` checks stable placement, over-limit status, empty boards,
invalid geometry, storage/panel overflow and scene/SVG output on Windows and
Linux. The gallery includes a labeled PNG/SVG pair. Pull policies, grouped
WIP limits and live drag/drop are separate application or L062 work.
`forest_plot` validates study estimates inside intervals and maps them to
horizontal segments plus center markers on linear, log10 or symlog x scales;
the reference line is a separate caller-colourable Rug layer. Study weights,
pooled estimates and interval computation remain statistical inputs, not
implicit chart operations. `e.algo.stat.agreement_limits` computes paired
difference bias and sample-SD limits with a caller-selected critical multiplier.
`bland_altman` maps paired means/differences to Scatter marks and three Rug
guides at the lower limit, bias and upper limit. The focused fixture checks
numeric references, invalid inputs, capacities and scene/SVG adapters on
Windows and Linux. Confidence intervals for limits, proportional-bias analysis
and nonlinear method comparison remain planned.
`funnel` maps nonincreasing stage counts to centered trapezoid Area layers with
an explicit inter-stage gap. This is the business conversion funnel, not the
statistical funnel plot. Both charts refuse invalid totals/stages and short
caller storage and reuse the scene/SVG adapters.
Matrix layouts map row-major values into caller-owned cells; Pearson correlation
reuses `e.algo.stat`. The scene adapter applies caller-selected sequential or
diverging colours. `facet_grid` supplies equal row-major panel rectangles; scale
sharing/freeing each numeric axis is available through explicit limits;
`category_facet_scatter` now maps explicit factor levels to Scatter panels,
retains empty panels and emits strip labels on shared numeric domains. Broader
geometry mapping, free-scale policy and strip collision handling remain.
`scatterplot_matrix` maps row-major observations into off-diagonal scatter
panels with one range per variable and caller-owned coordinates; diagonal
panels are reserved for caller labels. `gfx_chart_parallel_coordinates` checks
constant columns, invalid input, storage and scene/SVG output on both hosts.
`Spec` now carries independent x/y scale configurations for Cartesian marks.
Log10 refuses non-positive domains, symmetric-log has an explicit linear
threshold, and reverse maps fractions without copying columns. `ticks` returns
caller-owned data values and normalized positions; the scene guide pass draws
grid and axis strokes. `layout_with_limits` borrows optional two-value x/y
domains: an empty pair keeps a panel free, while explicit limits let facets
share either or both scales without copying columns. Limits must contain the
data (and any baseline); clipping/out-of-bounds policy remains planned.
`nice_ticks` chooses human-readable linear/log breaks and `format_ticks` uses
Neper's shortest-round-trip float formatter into caller-owned text storage;
`guide_labels` positions those or caller-supplied x/y tick strings in caller-owned
metadata. The scene adapter shapes them with `e.text.layout` and a registered
TrueType font; SVG streams escaped `<text>` elements. Titles and annotations
use the same label contract. Automatic numeric/date formatting, collision
avoidance and layout-aware margins remain planned. Symmetric-log currently
uses the prior transformed-space breaks, with automatic text but no separate
nice-break policy.
`e.gfx.chart.svg` streams the same mark and matrix layouts as SVG with escaped
title/description metadata, current CPU-renderer channel packing for solid colours, and axis/grid
strokes from the same tick positions. The gallery exports a vector companion
for every PNG. `e.gfx.chart.scene.rasterize` now exposes a caller-owned straight-RGBA
image from a chart scene; callers compose it with `e.fmt.png.encode` after
rendering, so arena-backed writers are not interleaved with render allocations.
The gallery uses this path, and a PNG decode fixture checks transparency on both
hosts. Gradients, PDF/widget APIs, SVG font embedding
and backend-parity measurements remain planned.
The scene renderer keeps equal-prefix/suffix guide paint stationary when a
changed mark appears to move: the pixel-shift shortcut is refused in that case,
preventing stale ticks in subsequent chart PNGs. The distribution fixture
checks this frame transition on both hosts.

## Chart and diagram catalogue

This is the planned registry, grouped by the calculation or geometry they share.
`docs/chart-preview-backlog.txt` separately tracks individual gallery deliverables,
including grouped-catalogue variants and acceptance previews. The progress-page
preview denominator counts those targets plus rendered PNG/SVG pairs; it is not
the grouped-catalogue count or a claim of full chart-engine parity.
Scatter, line, points+line, bar, grouped/dodged bar, stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip/jitter, beeswarm, binned dot plot, step/stairs, area, lollipop, error bars,
confidence bands, dumbbells, ECDF,
box, boxen, density, hexbin, 2D rectangular bins, 2D KDE contours, ridgeline, Q-Q, P-P, violin, half violin, raincloud, slopegraph, connected scatter, marginal histogram, dose response, interval hazard, influence plot, capability sixpack, heatmap, correlation matrix, mosaic, association, fourfold, parallel coordinates, scatterplot matrix, bubble, OLS fitted line, OLS mean-confidence and prediction bands, covariance data ellipse, categorical bar+line combo, candlestick, OHLC, basic price-volume, returns/rolling volatility, basic waterfall, bullet, target gauge, KPI/target-status card, Pareto, population pyramid, pie, donut, radar, area-scaled rose/wind, ternary composition, waffle, mekko/marimekko, two-set area-proportional Euler, nominal three-set Venn, basic word cloud, treemap, sunburst, icicle, basic circle packing, basic Sankey, basic alluvial, basic chord, centered streamgraph, basic horizon plot, seasonal subseries, forecast fan chart, additive decomposition plot, ACF/PACF correlogram, empirical variogram, vector/quiver plot, streamlines, phase-space portrait, recurrence plot, basic drawdown chart, cohort retention triangle, contour isolines, filled contour bands, basic rank-over-time ribbons, basic stage funnel, state timeline, status history, event timeline, in-cell sparklines, in-cell data bars, calendar heatmap, basic forest plot, Bland–Altman agreement, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve are delivered; every other entry
remains planned.

Basic Gantt task spans and completion layers and diamond milestone roadmaps
are delivered, as are burndown and burnup traces; dependency links remain planned.
The planned/earned/actual-cost earned-value curve is delivered.
The likelihood-impact risk matrix with caller-supplied ratings is delivered.
The variable-width resource histogram with explicit capacity is delivered.
The basic role-lane workflow with directional cross-lane links is delivered.
The variable-height Kanban board with visible per-column WIP status is delivered.
The activity-on-node PERT/CPM network computes three-point expected durations and
per-activity variance, forward/backward elapsed-time passes, slack and the
unconstrained critical path. It rejects cycles and invalid estimates, and lays
out staged nodes and directional links. Working calendars, leads/lags, resource
levelling and project-duration uncertainty remain planned.
The single-stream value-stream map reports processing, value-added and queue
times, lead time, process-cycle efficiency and rolled yield. Its stage boxes
are equally spaced for legibility, while the lower time ladder has proportional
wait and processing intervals.
`future_value_stream_map` pairs independent current and target time ladders,
derives takt from available time and customer demand, and marks the target
pacemaker, FIFO/pull links and stages whose processing time exceeds takt.
It reports lead-time reduction, process-cycle-efficiency gain and rolled-yield
gain without requiring every target to improve. The Windows/Linux fixture
checks numeric deltas, control cues, over-takt geometry, scene/SVG output and
refusals; the gallery adds a paired PNG/SVG preview. This is a planning
comparison, not a production-control simulator; inventory, transport and
branching, and automated capacity balancing remain planned.
The SIPOC overview fixes supplier, input, process, output and customer column
order while accepting caller-owned entries and labels. It lays out variable
column counts with header flow arrows and refuses invalid or overcrowded
geometry. Entity relationships, swimlane handoffs and process execution stay
with their separate diagram families.
The decision tree accepts a rooted choice/chance/outcome tree, evaluates chance
nodes from branch probabilities, selects maximum expected value at choices and
lays out leaf intervals with a highlighted chosen branch. Influence diagrams,
utility functions and DAG decision networks remain planned.

The org chart accepts a rooted single-parent hierarchy, preserves report order,
allocates horizontal space by descendant leaves and emits caller-owned boxes and
orthogonal connectors. Multiple roots, dotted-line relationships and interactive
collapse remain planned.

The dependency graph accepts a general DAG with multiple sources, joins and
disconnected components. It assigns longest-path ranks through a topological
pass, spaces peers within ranks and emits caller-owned boxes and directional
orthogonal connectors. Crossing reduction, port selection and graph editing
remain planned.

The flowchart accepts explicitly placed terminal, process and decision nodes
plus opposing entry/exit ports. It emits chamfered terminal and diamond
polygons, process rectangles and orthogonal arrows; cycles are allowed so
feedback paths can be shown. Automatic placement, crossing avoidance and
mixed-axis port routing remain planned.

The state-machine diagram accepts explicitly placed states, exactly one initial
state, any number of final states and deterministic event transitions. It emits
state polygons, transition arrows and event labels, an initial arrow, final
rings and a self-loop; `state_machine_step` advances on a matching event and
otherwise leaves state unchanged. Hierarchical and concurrent states,
automatic placement and event-label collision handling remain planned.

The sequence diagram accepts participants, ordered call/return/async messages
and explicit activation intervals. It emits participant headers, dashed
lifelines, activation bars, self-call loops, dashed returns, arrows and message
labels as caller-owned layouts. Automatic call-stack activation inference,
fragments, destruction markers and long-label collision handling remain planned.

The entity-relationship diagram accepts caller-placed tables, ordered fields,
PK/FK tags and horizontal relationships. It emits table and header rectangles,
field labels and crow's-foot one/optional/many endpoint geometry. Automatic
schema-derived placement, vertical routing and collision-safe labels remain
planned.

The branching process map accepts a rooted DAG, per-step good fractions and
durations, and branch fractions that sum to one at every split. It propagates
surviving flow through joins, calculates expected processing time and terminal
good output, and emits staged caller-owned boxes and directional links.
Working calendars, repeat/rework loops, stochastic distributions and
collision-minimizing layout remain planned.

The stem-and-leaf transform rounds sorted numeric observations to a caller-
selected leaf unit, groups them into ordered signed stems and preserves every
leaf digit, including repeats, in caller-owned arrays. Negative stems use
floor division, so the displayed key reconstructs rounded values. The
renderer-neutral divider and row baselines support text placement in PNG and
SVG; automatic leaf-unit selection and split stems remain planned.

The range/interval layout maps nonzero low-to-high spans onto explicit numeric
limits and categorical rows. Floating Bar rectangles and separate Rug end
caps share caller-owned geometry, so the adapters can style the interval and
its bounds independently. Open/closed endpoints, overlapping-range dodging
and automatic numeric limits remain planned.

The probability plot maps sorted observations to (i + 1/2)/n positions on
normal or exponential probability paper. Its caller-owned ticks retain
probability values but use nonlinear transformed fractions; fitted location
and scale generate a reference line clipped to the numeric domain and the
fixed 1%-99% paper. Automatic distribution fitting, confidence envelopes
and additional probability families remain planned.

The count-based spine plot maps contingency-table column marginals to column
width and within-column category fractions to stacked height. It returns
category-major Bar layers and caller-owned totals for color/legend mapping;
without a gutter each cell area equals count divided by grand total. The
existing mosaic differs by coloring Pearson residuals. Empty columns are
refused, while zero-count individual cells retain empty slots.

### General-purpose statistical and business charts

| Family | Charts |
|---|---|
| Cartesian series | scatter, line, points+line, step/stairs, lollipop, dot/dumbbell, rug, stem-and-leaf (basic), area, range/interval (basic), error bars, confidence bands |
| Bars and composition | bar, column, grouped, dodged, stacked, 100% stacked, diverging, waterfall/bridge (basic), bullet (basic), Pareto (basic), funnel, population pyramid |
| Distributions | histogram, frequency polygon, binned dot plot, density/KDE, ridgeline, box-and-whisker, violin, boxen, beeswarm, strip/jitter, ECDF, QQ, PP, probability plot (normal/exponential) |
| Matrix and categorical | heatmap, tile, correlation matrix, mosaic, spine (count-based), fourfold, association, parallel coordinates, scatterplot matrix/pairs |
| Composition and hierarchy | pie, donut, ring, waffle, treemap, sunburst/icicle, circle packing, Sankey, alluvial, chord, streamgraph |
| Time and calendars | sparkline, calendar heatmap, horizon, seasonal, fan/forecast, decomposition, control/run chart, event timeline, state timeline, status history |

### Statistical, quality, medical and scientific diagrams

ROC/PR, calibration/reliability, lift/gain, confusion matrix, Bland–Altman,
forest, funnel, Kaplan–Meier/survival, dose-response, hazard, residual/fitted,
leverage/Cook’s distance, influence, control I-MR/Xbar-R/Xbar-S/p/np/c/u/CUSUM/
EWMA, capability sixpack, Pareto, fishbone/Ishikawa, cause-and-effect tree,
Weibull, OC curve, Gage R&R, multi-vari, main-effects, interaction, cube,
contour, filled contour, 3-D surface, wireframe,
polar/radar, rose/wind, spectrogram, waterfall spectra, Bode/Nyquist,
correlogram/ACF/PACF and empirical variogram.

### Operations, finance and network diagrams

Gantt, milestone roadmap, swimlane, burndown, burnup, earned-value curve,
resource histogram, risk matrix, Kanban, PERT/CPM/network, process map/VSM,
SIPOC, decision tree, org chart, dependency graph, flowchart, state machine,
sequence diagram, entity-relationship diagram, cohort retention triangle,
cap table/waterfall, tornado/sensitivity, football field, yield curve, candlestick,
OHLC, volume, drawdown, returns/volatility and Monte-Carlo histogram/CDF.

## Delivery order and gates

1. **Foundation (delivered now):** typed spec, borrowed data, scale-to-bounds,
   scatter/line/points+line/bubble/bar/step/area/lollipop/error-bar/band/dumbbell marks, constant-domain handling,
   executable fixtures.
2. **Core distributions (delivered):** histogram, frequency polygon, rug, strip,
   beeswarm, binned dot plot, box, boxen,
   violin, density, ridgeline, ECDF, normal Q-Q and P-P have executable fixtures and PNG previews. Other distribution
   variants in the catalogue remain planned.
3. **Matrix and facets (partial):** heatmap, likelihood-impact risk matrix and Pearson correlation matrix have
   executable fixtures and PNG previews. `parallel_coordinates` maps each
   row to independent column axes using caller-owned ranges and segments;
   `gfx_chart_parallel_coordinates` checks constant axes, storage and scene/SVG
   output on Windows and Linux. Its labeled PNG/SVG preview is delivered.
   `scatterplot_matrix` composes off-diagonal scatter panels with independent
   per-variable ranges; its labeled PNG/SVG preview and Windows/Linux fixture
   are delivered. Diagonal density layers and selection remain planned.
   `mosaic` adds contingency-area cells coloured by Pearson residuals; its
   labeled PNG/SVG preview and Windows/Linux fixture are delivered.
   `association` adds signed residual bars about row baselines, width-scaled
   by square-root expected counts; its PNG/SVG preview and fixture are delivered.
   `fourfold` adds an equal-margin 2x2 quarter-circle display with optional
   odds-ratio confidence arcs; its PNG/SVG preview and fixture are delivered.
   `facet_grid` places panels and a
   four-panel heatmap preview exercises it. Optional x/y limits let each panel
   share or free its scale independently, exercised by a second four-panel
   preview. Basic category-center labels and per-series legend geometry are
   delivered for bar compositions; strips, automated legend layout and
   categorical facet mapping remain.
   A basic waterfall/bridge layout now accepts an opening total and signed
   changes, adds the closing total and level connectors, and reuses the bar
   scene/SVG paths. Per-step semantic colouring and category labels remain.
   `cap_table_waterfall` takes exact same-basis existing holder share counts,
   an option-pool top-up and a new-investor issuance. It yields before/after
   ownership segments and a signed retained-ownership bridge, with percentages
   derived only after overflow-checked share totals. The Windows/Linux fixture
   covers fractions, geometry, omitted events, overflow and storage refusals;
   the gallery adds a PNG/SVG pair. SAFE/note conversion, preferences, voting
   classes and valuation are not inferred by this first share-count model.
   `tornado_sensitivity` accepts paired one-at-a-time model outcomes around a
   common baseline, stably orders cases by absolute output swing, and retains
   separate low-input and high-input bar layers even when response direction
   reverses. The Windows/Linux fixture checks sorting ties, geometry,
   scene/SVG adapters and refusal paths; the gallery adds a PNG/SVG pair.
   Input distributions, joint interactions and probabilistic uncertainty are
   outside this deterministic scenario layout.
   `football_field` composes one ordered valuation interval per method through
   the existing capped range bars and adds a common benchmark rule. The caller
   supplies the shared domain, unit basis, colours and labels; no enterprise-
   to-equity or currency conversion is inferred. The Windows/Linux fixture
   checks bar/cap/reference geometry, scene/SVG adapters and refusals, and the
   gallery adds a paired PNG/SVG preview.
   `yield_curve` maps strictly ordered positive maturities in years and finite
   supplied yields to explicit shared tenor/rate domains, preserving uneven
   maturity spacing and allowing negative rates. It connects observations
   without fitting, smoothing or extrapolation. The Windows/Linux fixture
   checks coordinates, inversion, negative yields, adapters and refusals; the
   gallery adds a two-scenario PNG/SVG preview with synthetic values.
   `monte_carlo_distribution` accepts caller-produced model outcomes and
   exposes exact equal-width bin counts, an empirical sample CDF, and the
   observed fraction at or below one threshold on a shared explicit domain.
   It neither chooses uncertainty distributions nor runs the model. The
   Windows/Linux fixture checks endpoint bins, sorted values, CDF steps,
   threshold arithmetic, adapters and refusals. A seeded PCG toy model in
   the gallery renders histogram and CDF PNG/SVG pairs from the same draws.
   `aggregate_decomposition_tree` rolls nonnegative leaf measures up through a
   depth-first-preorder hierarchy, then lays out labeled cards left to right
   with bars proportional to each node's parent total. Root and child totals
   remain caller-visible; no interactive drill or automatic explanatory split
   is implied. The Windows/Linux fixture checks roll-ups, geometry, relative
   bars, scene/SVG adapters and refusals; the gallery adds a PNG/SVG pair.
   `date_axis_line` maps ordered civil dates through elapsed day counts over an
   explicit date and y domain, so unequal months and leap days retain their
   spacing. `date_ticks` emits month-start fractions at an explicit stride;
   `format_date_ticks` writes ISO year-month labels into caller storage. The
   Windows/Linux fixture checks leap-year positions, labels, adapters and
   invalid dates/storage; the gallery adds a paired PNG/SVG preview. Day/week
   and locale-sensitive tick policies remain planned.
   `discrete_axis_bars` uses caller-ordered factor levels rather than source
   encounter order, sums repeated nonnegative keys and retains missing levels
   as zero-height labeled slots. It rejects duplicate levels, unknown keys,
   overflow and sums above the explicit y domain. The Windows/Linux fixture
   checks aggregation, slots, geometry, adapters and refusal paths; the gallery
   adds a paired PNG/SVG preview. A reusable discrete scale for every geometry
   and guide collision policy remain planned.
   `category_facet_scatter` maps a categorical key into row-major panels in
   caller-specified level order and retains empty levels as blank panels with
   strip labels. Each Scatter panel uses the same explicit x/y domain; caller
   storage holds panels, grouped points, marks, labels and counts. The
   Windows/Linux fixture checks grouping, empty panels, coordinates, SVG
   escaping, scene output and refusal paths; the gallery adds a PNG/SVG pair.
   Generalized geom facets and free-scale category panels remain planned.
   `wrapped_legend_items` accepts caller-measured label widths and wraps whole
   swatch/label pairs into bounded rows. It refuses an item wider than the
   legend region or too many rows for its height, avoiding silent text
   collisions. The Windows/Linux fixture checks placement, capacity and
   scene/SVG output; the gallery adds a measured-font PNG/SVG preview.
   Automatic plot-versus-legend placement and layout-aware margins remain.
   `masked_scatter` separates x/y presence bits from numeric payloads: an
   incomplete pair is omitted, while observed non-finite or out-of-domain
   values are errors. It compacts complete marks with their original row IDs
   and reports the omitted count, including an all-missing result. The
   Windows/Linux fixture checks mapping, row identity, empty marks, adapters
   and refusals; the gallery adds a PNG/SVG pair that names omitted rows.
   General missing-data policies for other geoms remain planned.
   Bullet charts now compose qualitative bands, an actual bar and a target
   rule from existing layers; `gfx_chart_composition` checks geometry,
   refusals and both adapters on Windows and Linux.
   Pareto composes stable descending frequency bars with a cumulative-share
   PointLine layer and an explicit percentage axis in the gallery.
   Population pyramid uses mirrored horizontal Bar layers with a shared maximum;
   `gfx_chart_population_pyramid` checks geometry and both adapters on both hosts.
   A target gauge reuses Area arcs and a Rug rule; a KPI card composes bullet
   layers with `target_status`. `gfx_chart_gauge` checks both hosts and adapters.
   Pie and donut reuse Area polygons, explicit colour/legend metadata and the
   common scene/SVG adapters; `gfx_chart_polar` checks both on Windows and Linux.
   Waffle and stage funnel reuse Bar and Area layers respectively;
   `gfx_chart_funnel_grid` checks geometry, refusals and adapters on both hosts.
   A hierarchical slice-and-dice treemap returns caller-owned rectangles and
   leaf Bar layers; `gfx_chart_treemap` checks area and scene/SVG output on both
   hosts. Squarified packing and interaction remain.
   Sunburst reuses the leaf-weight tree for angular sectors and depth rings;
   `gfx_chart_sunburst` checks numeric spans and scene/SVG adapters on both
   hosts. Curved-label placement and adaptive tessellation remain.
   Icicle reuses those totals for proportional horizontal depth bands;
   `gfx_chart_icicle` checks geometry and scene/SVG adapters on both hosts.
   Circle packing reuses hierarchy totals and Bubble marks for non-overlapping
   nested circles; `gfx_chart_circle_pack` checks geometry and both adapters.
   Sankey uses caller-owned Area ribbons and Bar nodes at one flow scale;
   `gfx_chart_sankey` checks numeric geometry and both adapters on both hosts.
   Alluvial keeps adjacent-stage strata balanced over the same ribbon layout;
   `gfx_chart_alluvial` checks conservation and both adapters on both hosts.
   Streamgraph centers sample-major stacks into caller-owned Area polygons;
   `gfx_chart_streamgraph` checks shared scale and both adapters on both hosts.
   Rank ribbons map sample-major values to stable ordinal bands in Area layers;
   `gfx_chart_ribbon_rank` checks ties, geometry and both adapters on both hosts.
   Chord maps asymmetric matrix pairs into ribbons and group rings;
   `gfx_chart_chord` checks geometry and both adapters on both hosts.
   Mekko uses variable-width category columns and series-major Bar layers;
   `gfx_chart_mekko` checks area proportions and both adapters on both hosts.
   Two-set Euler solves exact circle overlap; nominal three-set Venn provides
   seven region anchors. `gfx_chart_venn_euler` checks both adapters on both hosts.
   Weighted word clouds pack measured text boxes with an exact exclusion list;
   `gfx_chart_word_cloud` checks bounds and scene/SVG text on both hosts.
   State timeline and status history share ordered f64 interval geometry,
   coalescing and gap handling; `gfx_chart_state_timeline` checks both adapters.
   In-cell sparklines reuse Line layers and calendar heatmaps reuse sparse
   Heatmap cells; `gfx_chart_calendar_sparkline` checks both adapters and hosts.
   Event timelines reuse Lollipop points/stems and in-cell data bars reuse Bar
   rectangles; `gfx_chart_events_cellbars` checks both adapters and hosts.
   Horizon plots fold signed time-series values into threshold-split Area
   patches; `gfx_chart_horizon` checks geometry and adapters on both hosts.
   Seasonal subseries group cycles by period and mark phase means;
   `gfx_chart_seasonal` checks geometry and adapters on both hosts.
   Forecast fans compose nested Band polygons and a median Line;
   `gfx_chart_fan` checks nesting, geometry and adapters on both hosts.
   Additive decomposition computes centered-MA trend, seasonal and remainder
   lines; `gfx_chart_decomposition` checks numeric references and adapters.
   Correlograms use mean-centered ACF and Durbin-Levinson PACF in paired Rug
   panels; `gfx_chart_correlogram` checks numeric values and both adapters.
   Empirical variograms bin 2D Euclidean pairs by distance and emit classical
   semivariance Scatter marks; `gfx_chart_variogram` checks numeric values and adapters.
   Radar charts normalize per-axis ranges into filled polygons with spoke/ring
   guides; rose diagrams map pre-binned angular weights to equal-angle,
   area-proportional sectors. `gfx_chart_radial` checks both adapters and hosts.
   Ternary compositions close three nonnegative components to unit sum before
   projecting into a fixed-aspect triangle with parallel grid guides;
   `gfx_chart_ternary` checks geometry and both adapters on both hosts.
   Quiver plots map vector tails through Cartesian data coordinates, then add
   explicitly pixel-scaled shafts and heads as Rug segments; `gfx_chart_quiver`
   checks zero vectors, geometry, refusals and both adapters on both hosts.
   Streamlines bilinearly sample regular vector grids and follow midpoint steps
   from caller seeds, clipping at domain edges; independent Rug strokes prevent
   accidental joins across seeds. `gfx_chart_streamlines` checks both adapters.
   Phase-space plots pair scalar observations at an explicit lag on equal axes;
   recurrence matrices threshold Euclidean distances between those same
   two-dimensional states. `gfx_chart_phase_space` and `gfx_chart_recurrence`
   check numeric references, refusals and scene/SVG adapters on both hosts.
   `drawdown` computes fractional losses from the running price high and fills
   them with the existing Area mark. `cohort_retention` normalizes compact
   triangular counts by each cohort's starting size into sparse Heatmap tiles.
   `gfx_chart_drawdown` and `gfx_chart_cohort_retention` check values, invalid
   shapes/capacities and scene/SVG adapters on both hosts.
   `contour` interpolates ordered levels across a row-major scalar grid into
   independent Rug isolines, resolving diagonal saddles by the cell centre.
   `filled_contour` clips each cell's two linear triangles to scalar bands and
   returns Area polygons with caller-owned band IDs. Scene/SVG adapters group
   each colour into one fill path so shared triangle edges leave no seams.
   `gfx_chart_contour` and `gfx_chart_filled_contour` check reference geometry,
   area conservation, invalid/capacity paths and adapters on both hosts.
   Forest intervals reuse Dumbbell/Rug marks with log-ratio support;
   Bland–Altman agreement reuses Scatter/Rug marks and `e.algo.stat` sample SD.
   `gfx_chart_agreement_forest` checks numeric references and adapters on both hosts.
   OLS fit and covariance data-ellipse overlays reuse Line layers and shared
   scatter limits; mean-confidence and prediction ribbons add filled Band
   layers on the same domain. `gfx_chart_overlays` checks references and adapters
   on both hosts.
   Category-centered bar+line overlays share x but expose independent left and
   right y domains; `gfx_chart_composition` checks alignment and adapters on
   both hosts.
   Candlestick and OHLC share a validated numeric x/price domain and reuse
   Rug/Bar strokes and rectangles; `gfx_chart_finance` checks irregular spacing,
   doji marks, invalid envelopes and scene/SVG output on both hosts.
4. **Rendering adapters (partial):** scene display-list marks, tick/grid/axis
   strokes, a Neper-rendered PNG gallery and a streaming solid-colour SVG
   adapter with two hundred and five vector previews, automatic numeric tick text and
   caller-supplied title labels are delivered. The reusable rasterization path
   composes with `e.fmt.png.encode` for PNG export; collision-safe margins,
   PDF serialization and a widget embed remain. Pixel fixtures follow
   existing gfx renderer practice.
5. **Specialized calculators (partial):** tied-score binary threshold sweeps,
   ROC AUC, average precision, calibration bins and confusion counts, plus
   Bland–Altman limits and censor-aware survival/hazard steps are delivered in
   `e.algo.stat`; I-MR/Xbar-R/Xbar-S, p/np/c/u, Laney P-prime/U-prime, geometric G, exponential T, CUSUM, EWMA and eight run-rule tests are also delivered. Survival intervals/comparisons,
   further SPC, capability, pooled forest/funnel estimators,
   surface and other domain diagrams remain in their owning modules.
6. **Interaction and acceleration:** hit regions, selection, zoom/pan, animation,
   GPU batching and progressive downsampling. This is L062, not a reason to block
   the deterministic static core.

## How Neper can beat the reference tools

`shared_facet_guide_labels` reuses tick text placement for complete aligned
facet grids, emitting x labels only below the final row and y labels only at
the first column. All panels retain shared domains and their own grid strokes.
The `shared_guide_facets` PNG/SVG pair demonstrates a four-panel composition;
`gfx_chart_shared_guides` checks geometry, deduplication, adapters and refusal
paths on Windows and Linux. Free-scale guide semantics and shared legends
remain separate work.

`plot_grid` arranges independent plot rectangles using caller-owned column and
row weights and explicit horizontal/vertical gaps. Each cell can host a
different chart kind and domain; the gallery composes line, bar, scatter and
area plots into a PNG/SVG pair. `gfx_chart_plot_grid` checks weighted geometry,
backend output, invalid weights/gaps and short storage on Windows and Linux.
Shared guides, spanning cells and automatic title/axis margins remain open.

The `clipped_annotation` preview exercises reusable rectangular clip scopes in
the CPU scene and SVG adapters. Each backend clips marks and text inside a
panel while leaving later labels unaffected. `gfx_chart_clipped_annotation`
checks command ordering, escaped SVG text, invalid clips and IDs, and short
scene-builder refusal on Windows and Linux. Arbitrary path clips and automatic
annotation placement remain open.

The target is not “more enum values.” It is a smaller, deterministic core with
zero-copy inputs, explicit caller storage, stable scene replay, backend parity,
accessible metadata, and one mark grammar shared by every chart. Benchmark gates
should compare layout throughput, peak allocations, rendered pixels, export size,
and semantic accessibility against representative ggplot2/base/lattice/matplot
fixtures before claiming superiority. Until those measurements exist, “beat” is a
goal, not evidence.
