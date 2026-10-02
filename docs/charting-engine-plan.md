# Neper charting engine plan

Status: scatter, line, points+line, bar, grouped bar, signed stacked bar, 100% stacked bar, waterfall, bullet, Pareto,
histogram, frequency polygon, rug, strip/jitter, beeswarm, binned dot plot, step, area, lollipop, error bars,
confidence bands, dumbbells, ECDF, box, density, normal Q-Q, violin, heatmap
and correlation matrix are delivered, with linear/log10/symmetric-log and
reverse Cartesian scales, caller-owned ticks and text labels, linear/log nice
breaks, grid/axis passes,
basic category-center labels and per-series legend metadata, facet panel
geometry, explicit limits for shared/free facet scales, and
thirty-six PNG plus thirty-six SVG previews from Neper. L061 remains partial
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
Frequency polygons reuse histogram counts and join bin centers to zero at the
outer edges. Rugs map every observation to an independent short x-axis stroke,
preserving ties rather than binning them. Both reuse the existing line/stroke
adapters and keep output storage with the caller.
Points+line combines the existing Cartesian scatter and line layouts with one
domain and paints the line before its points. Strip plots map observations to
numeric x positions and add repeatable vertical jitter, preserving ties; both
use caller-owned coordinates and the existing scene/SVG mark paths.
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
`pareto` stably orders nonnegative category counts, exposes that order for labels,
and returns frequency Bar and cumulative-fraction PointLine layers with independent
left count and right percentage domains. It refuses zero totals; the gallery
labels both axes. The insertion sort is quadratic until category counts warrant
a caller-scratch mergesort.
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
box, density, Q-Q, violin, heatmap, correlation matrix, basic waterfall, bullet and Pareto are delivered; every other entry
remains planned.

### General-purpose statistical and business charts

| Family | Charts |
|---|---|
| Cartesian series | scatter, line, points+line, step/stairs, lollipop, dot/dumbbell, rug, stem-and-leaf, area, range/interval, error bars, confidence bands |
| Bars and composition | bar, column, grouped, dodged, stacked, 100% stacked, diverging, waterfall/bridge (basic), bullet (basic), Pareto (basic), funnel, population pyramid |
| Distributions | histogram, frequency polygon, binned dot plot, density/KDE, ridgeline, box-and-whisker, violin, boxen, beeswarm, strip/jitter, ECDF, QQ, PP, probability plot |
| Matrix and categorical | heatmap, tile, correlation matrix, mosaic, spine, fourfold, association, parallel coordinates, scatterplot matrix/pairs |
| Composition and hierarchy | pie, donut, ring, waffle, treemap, sunburst/icicle, circle packing, Sankey, alluvial, chord, streamgraph |
| Time and calendars | sparkline, calendar heatmap, horizon, seasonal, fan/forecast, decomposition, control/run chart, event timeline |

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
   scatter/line/points+line/bar/step/area/lollipop/error-bar/band/dumbbell marks, constant-domain handling,
   executable fixtures.
2. **Core distributions (delivered):** histogram, frequency polygon, rug, strip,
   beeswarm, binned dot plot, box,
   violin, density, ECDF and normal Q-Q have executable fixtures and PNG previews. Other distribution
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
4. **Rendering adapters (partial):** scene display-list marks, tick/grid/axis
   strokes, a Neper-rendered PNG gallery and a streaming solid-colour SVG
   adapter with thirty-six vector previews, automatic numeric tick text and
   caller-supplied title labels are delivered. The reusable rasterization path
   composes with `e.fmt.png.encode` for PNG export; collision-safe margins,
   PDF serialization and a widget embed remain. Pixel fixtures follow
   existing gfx renderer practice.
5. **Specialized calculators:** ROC, survival, SPC, capability, Bland–Altman,
   forest/funnel, contour/surface and domain diagrams, each in the owning stats or
   operations module and consumed by chart marks.
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
