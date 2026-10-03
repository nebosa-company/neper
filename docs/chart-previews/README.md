# Chart previews

The scatter, line, points+line, bar, grouped bar, signed stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip, beeswarm, binned dot plot, stem-and-leaf, step, area, lollipop, error-bar, band,
dumbbell, ECDF, box, boxen,
density, ridgeline, Q-Q, P-P, violin, heatmap, correlation matrix, parallel coordinates, scatterplot matrix, faceted heatmap, shared/free
facet scales, log scatter, symmetric-log line, labeled line, labeled log scatter
and labeled symmetric-log line PNGs, plus the bubble, OLS fit, covariance data
ellipse, mean-confidence and prediction overlays, and categorical bar+line
combo, candlestick, OHLC bars, a price-volume chart, a returns/rolling-volatility chart, a hierarchical treemap, a sunburst, an icicle, circle packing, a population pyramid, a Sankey, an alluvial diagram, a chord diagram, a streamgraph, a horizon plot, seasonal subseries, a forecast fan chart, an additive decomposition plot, an ACF/PACF correlogram, an empirical variogram, a radar comparison, an area-scaled wind rose, a ternary composition plot, a quiver vector field, a streamline plot, a phase-space portrait, a recurrence plot, a drawdown chart, a cohort retention triangle, contour isolines and filled contour bands, rank-over-time ribbons, a target gauge, a KPI/target-status card, a mekko chart, a Pearson-residual mosaic, an association plot, a fourfold display with confidence arcs, a two-set area-proportional Euler diagram, a nominal three-set Venn diagram, a measured weighted word cloud, a Gantt schedule, a milestone roadmap, a burndown chart, a burnup chart, an earned-value curve, a resource histogram, a risk matrix, a swimlane workflow, a Kanban board, a PERT/CPM network, a value-stream map, a SIPOC overview, a decision tree, an org chart, a dependency graph, a flowchart, a state machine, a sequence diagram, an entity-relationship diagram, a branching process map, a state timeline, a status history, an event timeline, in-cell sparklines, in-cell data bars, a calendar heatmap, a forest plot, a Bland–Altman agreement plot, ROC, precision–recall, cumulative gain, cumulative lift, calibration, confusion matrix, partial ROC area, Youden index and decision curve, plus residual-versus-fitted, leverage-versus-standardized-residual and Cook's-distance diagnostics, Kaplan–Meier survival, Nelson–Aalen cumulative hazard, Individuals and moving-range control charts, X-bar and subgroup-range control charts, and p, np, c and u attribute control charts, X-bar/S, two-sided CUSUM, EWMA, Laney P-prime/U-prime, geometric G and exponential T charts, plus an eight-test SPC run-signal chart, a phased Individuals chart, phased P/Np/C/U charts and phased Laney P-prime/U-prime charts and phased X-bar/R and X-bar/S chart pairs, are rendered by Neper's CPU scene and PNG encoder. All 163 have an SVG
companion streamed from the same layout with title and
description metadata. Grouped and stacked bars include category labels and a
two-series legend in both formats. The labeled preview uses the repository's Montserrat
TrueType font for scene rendering; SVG viewers use their sans-serif fallback.
Both formats come from `examples/chart_gallery.e`. From the repository
root on Windows, refresh them with:

```powershell
build/windows/tests/selfhost/neper-self.exe emit-executable examples/chart_gallery.e . x64 windows build/windows/tests/selfhost/chart-gallery.exe
build/windows/tests/selfhost/chart-gallery.exe
```
