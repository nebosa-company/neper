"""matplotlib side of the chart benchmark; mirrors chart_bench.e.

Each chart: a 1,000-point line, 200 square scatter markers, a y grid with tick
labels and a title, 360x240 pixels, saved as SVG and as PNG into memory. A new
figure per chart, as a reporting script would do. Prints the same lines as the
Neper program: name, charts, milliseconds, output bytes.
"""
import io
import math
import sys
import time

started = time.perf_counter()
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

IMPORT_MS = (time.perf_counter() - started) * 1000.0
CHARTS = 200
POINTS = 1000
matplotlib.rcParams["svg.fonttype"] = "none"  # text as text, as Neper writes it


def data(chart_index):
    """The same LCG noise and sine as chart_bench.e."""
    state = 1 + chart_index
    frequency = 1.0 + (chart_index % 5) * 0.2
    x, y = [], []
    for i in range(POINTS):
        state = (state * 1103515245 + 12345) % 2147483648
        noise = (state / 2147483648.0 - 0.5) * 0.3
        xi = 10.0 * i / 999.0
        x.append(xi)
        y.append(math.sin(xi * frequency) + noise)
    return x, y, x[::5], [v + 0.5 for v in y[::5]]


def draw(chart_index):
    x, y, sx, sy = data(chart_index)
    fig = plt.figure(figsize=(3.6, 2.4), dpi=100)
    # The plot rectangle Neper uses: x 40..346, y 28..218 of 360x240 pixels.
    ax = fig.add_axes((40 / 360, 22 / 240, 306 / 360, 190 / 240))
    ax.plot(x, y, color=(0, 114 / 255, 178 / 255), linewidth=1.44)
    ax.scatter(sx, sy, marker="s", s=18.7, color=(195 / 255, 86 / 255, 0), linewidths=0)
    ax.set_xlim(0, 10)
    ax.set_ylim(-2, 2.5)
    ax.set_xticks([])
    ax.set_yticks([-2, 0, 2])  # the ticks Neper's nice_ticks chooses for -2..2.5
    ax.grid(axis="y", color=(0.84, 0.87, 0.92))
    ax.tick_params(labelsize=5.76)
    fig.suptitle("Signal with samples", fontsize=5.76, y=0.95)
    return fig


def run(fmt):
    total = 0
    start = time.perf_counter()
    for j in range(CHARTS):
        fig = draw(j)
        buffer = io.BytesIO()
        fig.savefig(buffer, format=fmt)
        plt.close(fig)
        total += buffer.tell()
        if j == 0 and fmt == "png" and len(sys.argv) > 1:
            with open(sys.argv[1], "wb") as out:
                out.write(buffer.getvalue())
    return (time.perf_counter() - start) * 1000.0, total


print(f"import 0 {IMPORT_MS} 0")
svg_ms, svg_bytes = run("svg")
print(f"svg {CHARTS} {svg_ms} {svg_bytes}")
png_ms, png_bytes = run("png")
print(f"png {CHARTS} {png_ms} {png_bytes}")
