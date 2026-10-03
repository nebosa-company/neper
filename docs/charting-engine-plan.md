# Neper charting engine plan

Status: scatter, line, points+line, bubble, OLS fitted line, OLS mean-confidence and prediction bands, covariance data ellipse, bar, grouped bar, signed stacked bar, 100% stacked bar, categorical bar+line combo with a secondary axis, candlestick, OHLC, waterfall, bullet, target gauge, KPI/target-status card, Pareto, population pyramid, pie, donut, waffle, mekko, two-set Euler, three-set Venn, basic word cloud, treemap, sunburst, icicle, circle packing, Sankey, alluvial, chord, streamgraph, rank-over-time ribbon, stage funnel, state timeline, status history, event timeline, in-cell sparklines, in-cell data bars, calendar heatmap, forest plot, Bland–Altman agreement, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve,
histogram, frequency polygon, rug, strip/jitter, beeswarm, binned dot plot, step, area, lollipop, error bars,
confidence bands, dumbbells, ECDF, box, density, ridgeline, normal Q-Q, violin, heatmap
and correlation matrix are delivered, with linear/log10/symmetric-log and
reverse Cartesian scales, caller-owned ticks and text labels, linear/log nice
breaks, grid/axis passes,
basic category-center labels and per-series legend metadata, facet panel
geometry, explicit limits for shared/free facet scales, and
eighty-seven PNG plus eighty-seven SVG previews from Neper. Kaplan–Meier
survival and Nelson–Aalen cumulative-hazard curves are delivered. OLS residual/fitted,
leverage/standardized-residual and Cook's-distance diagnostics are delivered.
L061 remains partial
until the remaining families, full export coverage and widget integration are
evidenced.

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
   centers for bar labels, without a full discrete scale. Date scales, locale/date label
   formatting and out-of-bounds policy remain.
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
corporate-action adjustment and volume companions remain separate work.
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
categorical facet mapping and strips remain future work.
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
Scatter, line, points+line, bar, grouped/dodged bar, stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip/jitter, beeswarm, binned dot plot, step/stairs, area, lollipop, error bars,
confidence bands, dumbbells, ECDF,
box, density, ridgeline, Q-Q, violin, heatmap, correlation matrix, bubble, OLS fitted line, OLS mean-confidence and prediction bands, covariance data ellipse, categorical bar+line combo, candlestick, OHLC, basic waterfall, bullet, target gauge, KPI/target-status card, Pareto, population pyramid, pie, donut, waffle, mekko/marimekko, two-set area-proportional Euler, nominal three-set Venn, basic word cloud, treemap, sunburst, icicle, basic circle packing, basic Sankey, basic alluvial, basic chord, centered streamgraph, basic rank-over-time ribbons, basic stage funnel, state timeline, status history, event timeline, in-cell sparklines, in-cell data bars, calendar heatmap, basic forest plot, Bland–Altman agreement, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve are delivered; every other entry
remains planned.

### General-purpose statistical and business charts

| Family | Charts |
|---|---|
| Cartesian series | scatter, line, points+line, step/stairs, lollipop, dot/dumbbell, rug, stem-and-leaf, area, range/interval, error bars, confidence bands |
| Bars and composition | bar, column, grouped, dodged, stacked, 100% stacked, diverging, waterfall/bridge (basic), bullet (basic), Pareto (basic), funnel, population pyramid |
| Distributions | histogram, frequency polygon, binned dot plot, density/KDE, ridgeline, box-and-whisker, violin, boxen, beeswarm, strip/jitter, ECDF, QQ, PP, probability plot |
| Matrix and categorical | heatmap, tile, correlation matrix, mosaic, spine, fourfold, association, parallel coordinates, scatterplot matrix/pairs |
| Composition and hierarchy | pie, donut, ring, waffle, treemap, sunburst/icicle, circle packing, Sankey, alluvial, chord, streamgraph |
| Time and calendars | sparkline, calendar heatmap, horizon, seasonal, fan/forecast, decomposition, control/run chart, event timeline, state timeline, status history |

### Statistical, quality, medical and scientific diagrams

ROC/PR, calibration/reliability, lift/gain, confusion matrix, Bland–Altman,
forest, funnel, Kaplan–Meier/survival, dose-response, hazard, residual/fitted,
leverage/Cook’s distance, influence, control I-MR/Xbar-R/Xbar-S/p/np/c/u/CUSUM/
EWMA, capability sixpack, Pareto, fishbone/Ishikawa, cause-and-effect tree,
Weibull, OC curve, Gage R&R, multi-vari, main-effects, interaction, cube,
contour, filled contour, 3-D surface, wireframe, vector/quiver, streamlines,
polar/radar, rose/wind, ternary, spectrogram, waterfall spectra, Bode/Nyquist,
phase-space, recurrence, correlogram/ACF/PACF and empirical variogram.

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
   beeswarm, binned dot plot, box,
   violin, density, ridgeline, ECDF and normal Q-Q have executable fixtures and PNG previews. Other distribution
   variants in the catalogue remain planned.
3. **Matrix and facets (partial):** heatmap and Pearson correlation matrix have
   executable fixtures and PNG previews; `facet_grid` places panels and a
   four-panel heatmap preview exercises it. Optional x/y limits let each panel
   share or free its scale independently, exercised by a second four-panel
   preview. Basic category-center labels and per-series legend geometry are
   delivered for bar compositions; strips, automated legend layout and
   categorical facet mapping remain.
   A basic waterfall/bridge layout now accepts an opening total and signed
   changes, adds the closing total and level connectors, and reuses the bar
   scene/SVG paths. Per-step semantic colouring and category labels remain.
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
   adapter with eighty-seven vector previews, automatic numeric tick text and
   caller-supplied title labels are delivered. The reusable rasterization path
   composes with `e.fmt.png.encode` for PNG export; collision-safe margins,
   PDF serialization and a widget embed remain. Pixel fixtures follow
   existing gfx renderer practice.
5. **Specialized calculators (partial):** tied-score binary threshold sweeps,
   ROC AUC, average precision, calibration bins and confusion counts, plus
   Bland–Altman limits and censor-aware survival/hazard steps are delivered in
   `e.algo.stat`; survival intervals/comparisons, SPC, capability, pooled forest/funnel estimators,
   contour/surface and other domain diagrams remain in their owning modules.
6. **Interaction and acceleration:** hit regions, selection, zoom/pan, animation,
   GPU batching and progressive downsampling. This is L062, not a reason to block
   the deterministic static core.

## How Neper can beat the reference tools

The target is not “more enum values.” It is a smaller, deterministic core with
zero-copy inputs, explicit caller storage, stable scene replay, backend parity,
accessible metadata, and one mark grammar shared by every chart. Benchmark gates
should compare layout throughput, peak allocations, rendered pixels, export size,
and semantic accessibility against representative ggplot2/base/lattice/matplot
fixtures before claiming superiority. Until those measurements exist, “beat” is a
goal, not evidence.
