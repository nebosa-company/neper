# Chart previews

The scatter, line, bar, histogram, step, area, lollipop, error-bar, band,
dumbbell, ECDF, box,
density, Q-Q, violin, heatmap, correlation matrix, faceted heatmap, shared/free
facet scales, log scatter, symmetric-log line and labeled line PNGs are rendered by Neper's CPU scene and PNG encoder.
Each has an SVG companion streamed from the same chart layout with title and
description metadata. The labeled preview uses the repository's Montserrat
TrueType font for scene rendering; SVG viewers use their sans-serif fallback.
Both formats come from `examples/chart_gallery.e`. From the repository
root on Windows, refresh them with:

```powershell
build/windows/tests/selfhost/neper-self.exe emit-executable examples/chart_gallery.e . x64 windows build/windows/tests/selfhost/chart-gallery.exe
build/windows/tests/selfhost/chart-gallery.exe
```
