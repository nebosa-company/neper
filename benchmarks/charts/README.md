# Chart benchmark: Neper against matplotlib

`chart_bench.e` and `mpl_bench.py` render the same workload 200 times per pass
and time it inside the process:

- a 1,000-point line and 200 square markers from the same deterministic data
  (a sine plus LCG noise, generated identically in both);
- a fixed plot rectangle in a 360x240 image, y limits -2..2.5, y grid and tick
  labels at -2, 0 and 2, and a title;
- written to memory as SVG (text kept as text in both) and as PNG.

Neper lays the chart out with `e.gfx.chart`, streams SVG with
`e.gfx.chart.svg`, and rasterizes with `e.gfx.chart.scene` on the CPU device
before `e.fmt.png` encodes at `.Balanced`. matplotlib uses the Agg backend,
a new figure per chart (as a reporting script does) and `savefig` into a
`BytesIO`. Each side also reports parts of the work: Neper's layout alone and
rasterization without encoding, and the time to import matplotlib.

```
python benchmarks/charts/run.py build/windows/tests/selfhost/neper-self.exe 9
```

builds the Neper program, runs each side nine times, keeps the median of every
pass and writes `results/<host>.json`.

## Results

Windows 11, Intel Core i5-12500H, Python 3.12.10, matplotlib 3.9.4; nine-run
medians, 2026-10-05 (`results/windows.json`), after the SVG writer moved to
0.01 px precision (D2111):

| per chart | Neper | matplotlib | |
|---|---:|---:|---|
| SVG | 2.50 ms | 15.63 ms | Neper 6.2x faster |
| PNG | 20.02 ms | 16.51 ms | matplotlib 1.21x faster |
| layout only | 0.15 ms | – | |
| rasterize only | 1.99 ms | – | |
| SVG size | 30,224 B | 44,387 B | Neper 32% smaller |
| PNG size | 14,004 B | 11,217 B | matplotlib 20% smaller |
| whole process, both passes | 5.0 s | 7.2 s | includes 0.53 s matplotlib import |

What the numbers say:

- SVG output is where Neper's design pays: layout from borrowed columns into
  caller-owned storage and a streaming writer, with no figure object model.
  Before D2111 Neper wrote full-precision coordinates and its SVG was 61,962 B,
  larger than matplotlib's; at 0.01 px it is 32% smaller.
- Neper's PNG time is almost all encoding: rasterizing takes 2.0 ms of the
  20.0 ms, so `e.algo.deflate` at `.Balanced`, not the renderer, is the thing
  to make faster (queued as L163). On the same raster, zlib level 6 takes
  1.74 ms and writes 11,283 B; Neper's deflate writes fixed Huffman codes
  only, has no lazy matching and computes the PNG CRC bit by bit.

### After L163 (D2840)

`e.algo.deflate` now writes dynamic Huffman blocks with zlib's lazy matcher over a
window that spans blocks, and `e.fmt.png` uses a table CRC, a deferred-modulo
Adler-32 and a whole-row copy. Measured by hand with `chart_bench.exe` on a loaded
host (not the nine-run `run.py` protocol): PNG 14.0 ms a chart against 20.0 ms
above, the chart's zlib stream 11,277 B against zlib level 6's 11,283 B on the
same rows (the file is 11,334 B), matplotlib 33.7 ms on the same host that day.
The deflate encoder alone is 9.6 ms on the 345,840-byte raster, still about 5x C
zlib; run `run.py` for the nine-run table.

## The R side

`r_bench.R` draws the same data (the same LCG, computed exactly in doubles by
splitting the state into 16-bit halves), the same 360x240 image (3.6x2.4 in at
100 dpi) and the same content with ggplot2, base R graphics and lattice, 200
charts per pass, SVG through `svglite` (text kept as text, as in the other two
programs) and PNG through `png()`, and prints the lines `name charts ms bytes`
(`ggplot2_svg`, `ggplot2_png`, `base_svg`, ... and `import`). `run.py` runs it
with the same median protocol when an `Rscript` is found (on PATH, or under
`C:\Program Files\R`, `/usr/lib/R`, `/opt/R`) and `ggplot2`, `lattice` and
`svglite` load, adds an `r` object to `results/<host>.json` and prints
`neper`-relative rows; without them it records `r_unavailable` and says why.

Measured 2026-10-13 on the same Windows 11 host with R 4.6.1 (installed under
`D:	ools\R`; ggplot2, svglite from CRAN, lattice from the R distribution),
five-run medians, 200 charts per pass; the first ggplot2 chart was checked by
eye (`Rscript r_bench.R first-chart.png`): the line, the markers, the title and
the y ticks at -2, 0 and 2 are all there.

| per chart | Neper | base R | lattice | ggplot2 | matplotlib |
|---|---:|---:|---:|---:|---:|
| SVG | 3.93 ms | 13.2 ms | 34.9 ms | 288.6 ms | 44.2 ms |
| PNG | 11.03 ms | 23.6 ms | 51.7 ms | 261.8 ms | 45.9 ms |
| SVG size | 30,224 B | 41,811 B | 42,468 B | 41,883 B | 44,387 B |
| PNG size | 11,334 B | 3,185 B | 2,951 B | 3,449 B | 11,217 B |
| package load | – | 0.76 s (all three) | | | 1.46 s |

Neper is 3.4x faster than base R, 8.9x than lattice and 73x than ggplot2 on SVG,
and 2.1x, 4.7x and 23.7x on PNG; its SVG is 28-29% smaller. R's PNG files are
3.5x *smaller* than Neper's: its `png()` device draws without anti-aliased
text and with few distinct colours, and Neper writes a 32-bit RGBA image;
`e.fmt.png.encode_adaptive` (D4400, palette output for images of at most 256
colours) is the way to close that, and this benchmark does not use it yet. The
times were taken on a host also running the lanes' builds, so single numbers
carry the usual spread; the R ratios are far outside it.

### PNG size (D2482)

R's PNGs are about three times smaller than Neper's because R's `png()` writes an
81-colour indexed file while the chart has 961 distinct colours (three inks at
every anti-aliasing coverage level). What we tried on the first chart:

| variant | bytes |
|---|---:|
| as written (RGBA, filter none, `.Balanced`) | 11,334 |
| `.Best` | 11,096 |
| declared opaque (RGB) | 10,993 |
| opaque and `.Best` | 10,412 |
| `encode_adaptive` (libpng's row-filter heuristic) | 14,431 - 15,082 |
| quantized to 256 colours (`e.fmt.png.quantize`, lossy), indexed, `.Best` | 6,004 |
| quantized to 128 / 64 / 32 colours | 4,997 / 4,376 / 4,045 |

The largest channel error is 17 of 255 at 256 colours (Pillow's median cut: 16,
6,047 bytes), 55 at 128 and 109 at 64 and below. The row-filter heuristic makes
flat-colour pictures worse; filter `None` with a good match finder is best here,
and a trial deflate of every row's five filters does not beat it. `chart_bench`
prints `png_opaque_best` and `png_indexed` passes with the exact byte totals; the
times it prints on a loaded host were 15 / 29 / 45 ms a chart (plain, opaque
`.Best`, quantized `.Best`), so quantizing is for files that are kept or sent.

## Caveats

- One machine, wall-clock time, on a host shared with other work: single runs
  varied by up to 50%, which is why the table uses nine-run medians.
- Linux is not measured: the WSL Python has no matplotlib or R. `run.py`
  works on Linux once matplotlib and R are installed.
- matplotlib does work Neper does not: it shapes text with its own font
  manager and draws an axes frame. The workload keeps the visible content the
  same, not the internal work.
