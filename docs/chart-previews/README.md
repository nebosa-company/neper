# Chart previews

The scatter, line, bar, histogram, step, area, lollipop, error-bar, ECDF, box,
density, Q-Q, violin, heatmap, correlation matrix and faceted heatmap PNGs are rendered by Neper's
CPU scene and PNG encoder from `examples/chart_gallery.e`. From the repository
root on Windows, refresh them with:

```powershell
build/windows/tests/selfhost/neper-self.exe emit-executable examples/chart_gallery.e . x64 windows build/windows/tests/selfhost/chart-gallery.exe
build/windows/tests/selfhost/chart-gallery.exe
```
