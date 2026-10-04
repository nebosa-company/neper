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
medians, 2026-10-04 (`results/windows.json`):

| per chart | Neper | matplotlib | |
|---|---:|---:|---|
| SVG | 2.62 ms | 16.02 ms | Neper 6.1x faster |
| PNG | 20.28 ms | 17.68 ms | matplotlib 1.15x faster |
| layout only | 0.16 ms | – | |
| rasterize only | 2.00 ms | – | |
| SVG size | 61,962 B | 44,387 B | |
| PNG size | 14,004 B | 11,217 B | |
| whole process, both passes | 5.0 s | 7.6 s | includes 0.55 s matplotlib import |

What the numbers say:

- SVG output is where Neper's design pays: layout from borrowed columns into
  caller-owned storage and a streaming writer, with no figure object model.
- Neper's PNG time is almost all encoding: rasterizing takes 2.0 ms of the
  20.3 ms, so `e.algo.deflate` at `.Balanced`, not the renderer, is the next
  thing to make faster. Neper's PNGs are also 25% larger.
- Neper's SVG is larger because it writes every line point and coordinate
  at full float precision; matplotlib rounds.

## Caveats

- One machine, wall-clock time, on a host shared with other work: single runs
  varied by up to 50%, which is why the table uses nine-run medians.
- Not measured: ggplot2, base R graphics and lattice, which need an R
  installation this machine does not have; and Linux, where the WSL Python has
  no matplotlib. `run.py` works on Linux once matplotlib is installed.
- matplotlib does work Neper does not: it shapes text with its own font
  manager and draws an axes frame. The workload keeps the visible content the
  same, not the internal work.
