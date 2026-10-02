# Neper charting engine plan

Status: foundation slice delivered; L061 remains partial until the standard
families, scene/PNG output, and widget integration are evidenced.

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
4. **Scales** — continuous, discrete, date/time, log, symlog, reverse and
   transformed domains; breaks, labels, limits and out-of-bounds policy.
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

## Chart and diagram catalogue

This is the planned registry, grouped by the calculation or geometry they share.
“Foundation” means the current `e.gfx.chart` slice; “planned” is not a claim of
implementation.

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
   scatter/line/bar marks, constant-domain handling, executable fixture.
2. **Core distributions:** histogram/bin policy, box/violin, density, ECDF and QQ;
   fixtures compare exact bins/quantiles against small hand oracles.
3. **Matrix and facets:** heatmap, correlation matrix, panel layout, shared/free
   scales, strips and legend metadata.
4. **Rendering adapters:** scene display-list marks, axes/text/guides, PNG output,
   SVG/PDF serialization and a widget embed; pixel fixtures follow existing gfx
   renderer practice.
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
