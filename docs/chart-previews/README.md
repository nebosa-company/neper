# Chart previews

The scatter, line, points+line, bar, grouped bar, signed stacked bar, 100% stacked bar,
histogram, frequency polygon, rug, strip, beeswarm, binned dot plot, step, area, lollipop, error-bar, band,
dumbbell, ECDF, box,
density, ridgeline, Q-Q, violin, heatmap, correlation matrix, faceted heatmap, shared/free
facet scales, log scatter, symmetric-log line, labeled line, labeled log scatter
and labeled symmetric-log line PNGs, plus the bubble, OLS fit, covariance data
ellipse, mean-confidence and prediction overlays, and categorical bar+line
combo, candlestick, OHLC bars, a hierarchical treemap, a sunburst, an icicle, circle packing, a population pyramid, a Sankey, an alluvial diagram, a chord diagram, a streamgraph, rank-over-time ribbons, a target gauge, a KPI/target-status card, a mekko chart, a two-set area-proportional Euler diagram, a nominal three-set Venn diagram, a measured weighted word cloud, a state timeline, a status history, an event timeline, in-cell sparklines, in-cell data bars, a calendar heatmap, a forest plot and a Bland–Altman agreement plot are rendered by Neper's CPU scene and PNG encoder. All 73 have an SVG
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
