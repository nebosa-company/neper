# Neper charting engine plan

Status: scatter, line, bar, histogram, step, area, lollipop, error bars, ECDF,
box, density, normal Q-Q, violin, heatmap and correlation matrix are delivered,
with linear/log10/symmetric-log and reverse Cartesian scales, caller-owned tick
metadata, grid/axis passes, facet panel geometry, explicit Cartesian limits
for shared/free facet scales and nineteen PNG plus nineteen SVG previews from Neper. L061 remains partial
until the remaining families, production export API and widget integration are
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
data frame. A future adapter can render the same `Layout` to `e.gfx.scene`, PNG,
SVG, PDF, a widget, or a GPU buffer.

The stable sequence is:

1. **Data** — typed columns/views; missingness and categorical levels are explicit.
2. **Mapping** — x/y plus colour, fill, size, shape, group, weight and facet keys.
3. **Statistics** — binning, summaries, smoothing and model overlays, each pure and
   independently testable.
4. **Scales** — linear, log10, symmetric-log and reverse Cartesian mapping are
   delivered, with equal transformed-space tick metadata. Discrete, date/time,
   nice breaks, labels, limits and out-of-bounds policy remain.
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
Area plots close ordered x/y points against an explicit baseline; lollipops
reuse the same baseline and point mapping. Error bars borrow center/lower/upper
columns, validate containment and emit a stem, two caps and a point per row.
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
data (and any baseline); clipping/out-of-bounds policy remains planned. Text
labels and layout-aware margins remain planned.
`e.gfx.chart.svg` streams the same mark and matrix layouts as SVG with escaped
title/description metadata, current CPU-renderer channel packing for solid colours, and axis/grid
strokes from the same tick positions. The gallery exports a vector companion
for every PNG; gradient brushes, text labels, production PNG/PDF/widget APIs
and backend-parity measurements remain planned.

## Chart and diagram catalogue

This is the planned registry, grouped by the calculation or geometry they share.
Scatter, line, bar, histogram, step/stairs, area, lollipop, error bars, ECDF,
box, density, Q-Q, violin, heatmap and correlation matrix are delivered; every other entry
remains planned.

### General-purpose statistical and business charts

| Family | Charts |
|---|---|
| Cartesian series | scatter, line, points+line, step/stairs, lollipop, dot/dumbbell, rug, stem-and-leaf, area, range/interval, error bars, confidence bands |
| Bars and composition | bar, column, grouped, dodged, stacked, 100% stacked, diverging, waterfall/bridge, bullet, Pareto, funnel, population pyramid |
| Distributions | histogram, frequency polygon, density/KDE, ridgeline, box-and-whisker, violin, boxen, beeswarm, strip/jitter, ECDF, QQ, PP, probability plot |
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
   scatter/line/bar/step/area/lollipop/error-bar marks, constant-domain handling,
   executable fixtures.
2. **Core distributions (delivered):** histogram, box, violin, density, ECDF and
   normal Q-Q have executable fixtures and PNG previews. Other distribution
   variants in the catalogue remain planned.
3. **Matrix and facets (partial):** heatmap and Pearson correlation matrix have
   executable fixtures and PNG previews; `facet_grid` places panels and a
   four-panel heatmap preview exercises it. Optional x/y limits let each panel
   share or free its scale independently, exercised by a second four-panel
   preview. Strips, legend metadata and categorical facet mapping remain.
4. **Rendering adapters (partial):** scene display-list marks, tick/grid/axis
   strokes, a Neper-rendered PNG gallery and a streaming solid-colour SVG
   adapter with nineteen vector previews are delivered; text labels and
   margins, a production PNG API, PDF serialization and a widget embed remain. Pixel fixtures follow
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
