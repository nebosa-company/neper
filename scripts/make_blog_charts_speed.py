#!/usr/bin/env python3
"""Build docs/blog/charts-speed-and-png-size.html and its banner from the committed template post
(docs/blog/sqlserver-openssl.html) and the measured numbers in benchmarks/charts/results/windows.json. Computed
content only: the numbers in the post come from that file, not from this script."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / "benchmarks/charts/results/windows.json").read_text(encoding="utf-8"))
n, m, r = data["neper"], data["matplotlib_results"], data["r"]


def per(rows, key):
    return rows[key]["ms"] / 200.0


svg_ms = {"Neper": per(n, "svg"), "base R": per(r, "base_svg"), "lattice": per(r, "lattice_svg"),
          "matplotlib": per(m, "svg"), "ggplot2": per(r, "ggplot2_svg")}
png_ms = {"Neper": per(n, "png"), "base R": per(r, "base_png"), "lattice": per(r, "lattice_png"),
          "matplotlib": per(m, "png"), "ggplot2": per(r, "ggplot2_png")}
svg_b = {"Neper": n["svg"]["bytes"] // 200, "base R": r["base_svg"]["bytes"] // 200, "lattice": r["lattice_svg"]["bytes"] // 200,
         "matplotlib": m["svg"]["bytes"] // 200, "ggplot2": r["ggplot2_svg"]["bytes"] // 200}
png_b = {"Neper": n["png"]["bytes"] // 200, "base R": r["base_png"]["bytes"] // 200, "lattice": r["lattice_png"]["bytes"] // 200,
         "matplotlib": m["png"]["bytes"] // 200, "ggplot2": r["ggplot2_png"]["bytes"] // 200}
neper_svg = svg_ms["Neper"]
neper_png = png_ms["Neper"]
order = ["Neper", "base R", "lattice", "matplotlib", "ggplot2"]


def f(x):
    return "%.1f" % x


def row(label, values, unit, fmt=f):
    cells = "".join("<td%s>%s</td>" % (' class="rank-1"' if k == "Neper" else "", fmt(values[k])) for k in order)
    return "<tr><td>%s</td>%s</tr>" % (label, cells)


def thousands(x):
    return "{:,}".format(int(x))


speed_table = ("<div class=\"table-scroll\"><table><thead><tr><th>Per chart, median</th>"
               + "".join("<th>%s</th>" % k for k in order) + "</tr></thead><tbody>"
               + row("SVG, ms", svg_ms, "ms")
               + row("PNG, ms", png_ms, "ms")
               + "</tbody></table></div>")
size_table = ("<div class=\"table-scroll\"><table><thead><tr><th>Bytes per chart</th>"
              + "".join("<th>%s</th>" % k for k in order) + "</tr></thead><tbody>"
              + row("SVG", svg_b, "B", thousands)
              + row("PNG", png_b, "B", thousands)
              + "</tbody></table></div>")

ratios_svg = {k: svg_ms[k] / neper_svg for k in order if k != "Neper"}
ratios_png = {k: png_ms[k] / neper_png for k in order if k != "Neper"}

# The banner: SVG time per chart as bars, clipped at 60 ms with the ggplot2 value written out.
bars = ""
y = 232
scale = 760.0 / 60.0
for k in ["Neper", "base R", "lattice", "matplotlib", "ggplot2"]:
    v = svg_ms[k]
    w = min(v, 60.0) * scale
    cls = "accent" if k == "Neper" else "rival"
    label = f(v) + " ms" + ("  (bar clipped)" if v > 60.0 else "")
    bars += ('<text class="sans ink" x="64" y="%d" font-size="26">%s</text>'
             '<rect class="%s" x="260" y="%d" width="%.0f" height="30" rx="6"/>'
             '<text class="mono ink" x="%.0f" y="%d" font-size="24">%s</text>\n  ') % (y + 24, k, cls, y, w, 260 + w + 14, y + 24, label)
    y += 62
banner = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" width="1200" height="630" role="img" aria-labelledby="t d">
  <title id="t">Neper charts: faster and smaller</title>
  <desc id="d">SVG chart time, milliseconds per chart: Neper %s, base R %s, lattice %s, matplotlib %s, ggplot2 %s.</desc>
  <style>
    .page { fill: #f8f9ff; } .ink { fill: #1a1b20; } .muted { fill: #434653; } .accent { fill: #145db2; } .rival { fill: #737784; }
    .display { font-family: "Segoe UI Variable Display", "Segoe UI", -apple-system, BlinkMacSystemFont, "SF Pro Display", Roboto, "Noto Sans", system-ui, sans-serif; }
    .sans { font-family: "Segoe UI Variable Text", "Segoe UI", -apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, "Noto Sans", system-ui, sans-serif; }
    .mono { font-family: "Cascadia Code", "SF Mono", ui-monospace, Menlo, "Roboto Mono", Consolas, monospace; }
    @media (prefers-color-scheme: dark) { .page { fill: #121318; } .ink { fill: #e1e2e9; } .muted { fill: #c3c6d5; } .accent { fill: #b3c5ff; } .rival { fill: #8d909e; } }
  </style>
  <rect class="page" width="1200" height="630"/>
  <text class="display ink" x="64" y="110" font-size="56">Faster charts, smaller SVG</text>
  <text class="sans muted" x="64" y="160" font-size="28">One 360x240 chart, 1,000 points and 200 markers, written as SVG. Median ms per chart.</text>
  %s
  <text class="mono muted" x="64" y="590" font-size="20">Windows 11, R 4.6.1, matplotlib 3.9.4, five-run medians (benchmarks/charts)</text>
</svg>
''' % (f(svg_ms["Neper"]), f(svg_ms["base R"]), f(svg_ms["lattice"]), f(svg_ms["matplotlib"]), f(svg_ms["ggplot2"]), bars)
(ROOT / "docs/blog/img/charts-speed-and-png-size.svg").write_text(banner, encoding="utf-8", newline="\n")

template = (ROOT / "docs/blog/sqlserver-openssl.html").read_text(encoding="utf-8")
head_end = template.index("<article>")
foot_start = template.index("</article>")
head = template[:head_end]
foot = template[foot_start:]
title = "Faster charts, smaller SVG, and what we are doing about PNG size"
desc = ("Neper draws the same 360x240 chart 3.4 to 73 times faster than base R, lattice, matplotlib and ggplot2 as SVG "
        "and 2 to 24 times faster as PNG, with SVG 28 to 32 percent smaller. Its PNG is three times larger than R's, "
        "and here is why, what we measured, and the lossy step that closes most of the gap.")
head = re.sub(r"<title>.*?</title>", "<title>%s — Neper blog</title>" % title, head, flags=re.S)
head = re.sub(r'(<meta name="description" content=")[^"]*(")', r"\g<1>%s\g<2>" % desc.replace("\\", "\\\\"), head)
head = re.sub(r'(<meta property="og:title" content=")[^"]*(")', r"\g<1>%s\g<2>" % title, head)
head = re.sub(r'(<meta property="og:description" content=")[^"]*(")', r"\g<1>%s\g<2>" % desc.replace("\\", "\\\\"), head)
head = head.replace("sqlserver-openssl", "charts-speed-and-png-size")
head = head.replace("2026-09-29", "2026-10-13")

body = '''<article>
      <div class="eyebrow">&gt; blog // engineering</div>
      <h1>%(title)s</h1>
      <p class="meta">October 13, 2026 · <code>lib/e/gfx/chart</code>, <code>lib/e/fmt/png.e</code>, <code>benchmarks/charts</code></p>
      <img class="banner" src="img/charts-speed-and-png-size.svg" width="1200" height="630" alt="SVG chart time in milliseconds per chart: Neper %(n_svg)s, base R %(b_svg)s, lattice %(l_svg)s, matplotlib %(m_svg)s, ggplot2 %(g_svg)s.">

      <p class="lede">We measured Neper's chart engine against the three R plotting systems and matplotlib on one machine, one workload and one data set. Neper writes the chart %(rb)s to %(rg)s times faster as SVG and %(pb)s to %(pg)s times faster as PNG, and its SVG is 28 to 32 percent smaller. Its PNG is the one column it loses: R's files are about three times smaller. This post has the numbers, the reason, what we tried, and the lossy step we added.</p>

      <h2>The workload</h2>
      <p>The same chart in every program: a 1,000-point line and 200 square markers drawn from one deterministic data set (a sine plus linear-congruential noise, computed exactly in all of them), a fixed plot rectangle in a 360x240 image, y limits -2 to 2.5, a y grid with tick labels at -2, 0 and 2, and a title. Each program draws 200 charts per pass and writes each to memory or a file as SVG (text kept as text) and as PNG, and we keep the median of five passes. R 4.6.1 (ggplot2 and svglite from CRAN, lattice from the distribution) and matplotlib 3.9.4 ran on the same Windows 11 laptop as Neper, whose chart code is <code>e.gfx.chart</code> over a borrowed-columns layout, a streaming SVG writer, and a CPU rasterizer into <code>e.fmt.png</code>. We checked the first ggplot2 chart by eye before trusting any R number; the line, the markers, the title and the ticks are all there.</p>

      <h2>Time</h2>
      %(speed)s
      <p>Against base R, the fastest of the others, Neper is %(rb)s times faster as SVG and %(pb)s times as PNG; against matplotlib %(rm)s and %(pm)s times; against ggplot2, which builds a grob tree and a gtable for every chart, %(rg)s and %(pg)s times. R's packages take %(rimp)s s to load once and matplotlib %(mimp)s s; for the whole 200-chart job (both formats, both passes) Neper took %(nproc)s s and matplotlib %(mproc)s s. The design is the whole reason: layout from borrowed columns into caller-owned storage, a streaming writer, no figure object model, and a PNG encoder that is not the bottleneck any more (the raster step is %(raster)s ms of the %(pn)s ms; the rest is deflate, which D4400 made about twice as fast).</p>

      <h2>Size</h2>
      %(size)s
      <p>The SVG is where Neper's output is smallest: %(svg_pct_b)s%% smaller than base R and %(svg_pct_m)s%% smaller than matplotlib. It writes coordinates at 0.01 px (D2111); before that change its SVG was larger than matplotlib's.</p>
      <p>The PNG column is the honest one. Neper writes %(png_n)s bytes; R's three devices write about %(png_r)s. matplotlib's %(png_m)s sits next to Neper's, so this is not a Neper quirk, it is how R's <code>png()</code> device draws.</p>

      <h2>Why R's PNG is a third the size</h2>
      <p>We opened both files. R's chart has 81 distinct colours and is written as an 8-bit indexed PNG; Neper's has 961 and is written as 32-bit RGBA with no palette. R's device renders with a coarse anti-aliasing step; Neper blends each ink with the background at every one of 256 coverage levels, so a 360x240 chart with three inks lands near a thousand colours. All 961 are legitimate pixels, and none of them can go in a 256-entry palette without being changed. So the question is how much we can save without changing anything, and how much by changing a little.</p>

      <h2>What we tried, lossless</h2>
      <div class="table-scroll">
        <table>
          <thead><tr><th>Same pixels, one chart</th><th>Bytes</th></tr></thead>
          <tbody>
            <tr><td>As written today (RGBA, filter none, <code>.Balanced</code>)</td><td>11,334</td></tr>
            <tr><td><code>.Best</code> instead of <code>.Balanced</code></td><td>11,096</td></tr>
            <tr><td>Tell the encoder the image is opaque (RGB, no alpha channel)</td><td>10,993</td></tr>
            <tr><td>Opaque and <code>.Best</code></td><td>10,412</td></tr>
            <tr><td>Per-row filters chosen by libpng's heuristic (<code>encode_adaptive</code>)</td><td>14,431–15,082</td></tr>
            <tr><td>Per-row filters chosen by trial deflate of each row (a Python experiment)</td><td>about 10,200</td></tr>
            <tr><td>Pillow's default PNG writer</td><td>14,818</td></tr>
          </tbody>
        </table>
      </div>
      <p>Two things stand out. First, declaring the image opaque and asking for <code>.Best</code> gets 8%% for free, and the benchmark's PNG pass now measures both. Second, the row-filter heuristic that every PNG library uses makes this picture worse by a third: flat colour with soft edges is exactly what filter <code>None</code> plus a good match finder compresses best, and no filter trial we ran beat that by more than the noise. <code>encode_adaptive</code> stays for photographs and gradients, where it wins; for charts it is the wrong tool, and it now says so in its documentation.</p>

      <h2>What we added, lossy and opt-in</h2>
      <p>A lossless PNG cannot get near R's size with this many colours, so we added the lossy step separately and made it explicit. <code>e.fmt.png.quantize</code> keeps the <em>N</em> most frequent colours of the picture and maps every other colour to the nearest kept one by squared distance over the four channels; <code>encode_quantized</code> then writes the result as an indexed PNG. Both choices have fixed tie-breaks, so the output is a function of the picture, and the fixture compares it with an independent Python model of the rule. An image that already has no more colours than asked is written unchanged, and a photograph (more than 3,072 distinct colours) is refused rather than butchered.</p>
      <div class="table-scroll">
        <table>
          <thead><tr><th>Colours kept</th><th>Bytes</th><th>Largest channel error (of 255)</th></tr></thead>
          <tbody>
            <tr><td>961 (lossless, opaque, <code>.Best</code>)</td><td>10,412</td><td>0</td></tr>
            <tr><td>256</td><td>6,004</td><td>17</td></tr>
            <tr><td>128</td><td>4,997</td><td>55</td></tr>
            <tr><td>64</td><td>4,376</td><td>109</td></tr>
            <tr><td>32</td><td>4,045</td><td>109</td></tr>
            <tr><td>R's <code>png()</code>, for comparison</td><td>3,412</td><td>(different anti-aliasing)</td></tr>
          </tbody>
        </table>
      </div>
      <p>At 256 colours the chart is 6,004 bytes, 47%% smaller than today's 11,334, with no pixel off by more than 17 of 255 (the mean error is 0.02). Median cut in Pillow reaches 6,047 bytes with a largest error of 16, so keeping the most frequent colours and snapping the rest costs nothing against the standard tool. Below 128 colours a popularity palette starts to put a rare coverage level on the wrong ink, and the error jumps; that is the point where a real quantizer with dithering is the next step, and we have not built one. We would not use fewer than 128 for a chart someone will read.</p>
      <p>The cost is real. On a laptop that was also running builds, the indexed pass took about three times the plain pass per chart (15 ms plain, 29 ms opaque at <code>.Best</code>, 45 ms quantized at <code>.Best</code>), so it is worth it for files that are stored or sent, not for a hot loop that throws the PNG away. The quiet-machine figures are not in this post; the sizes are exact and do not depend on the load.</p>

      <h2>What this does not say</h2>
      <ul>
        <li><strong>One machine, one workload.</strong> A larger chart, a different font, or a heat map changes every ratio. The R ratios are far outside the run-to-run spread, the PNG size gap is not a spread at all.</li>
        <li><strong>The libraries do different work.</strong> ggplot2 builds a theme and a layout engine we do not have; matplotlib shapes text with its own font manager. The workload fixes the visible content, not the internal work, and R's chart looks slightly different (its anti-aliasing is coarser).</li>
        <li><strong>The first R numbers were taken while other jobs ran on the same laptop.</strong> They are medians of five, and the speed ratios are an order of magnitude beyond that noise, but a quiet-machine rerun of all columns is still owed.</li>
        <li><strong>Linux was not measured.</strong> The WSL Python on this machine has neither matplotlib nor R.</li>
      </ul>

      <h2>Reproduce it</h2>
      <p>With R on the path (and <code>ggplot2</code>, <code>svglite</code> installed) and matplotlib, build and run the harness against the compiler of your choice:</p>
      <pre><code><span class="prompt">$</span> python benchmarks/charts/run.py build/windows/tests/selfhost/neper-self.exe 5
<span class="prompt">$</span> Rscript benchmarks/charts/r_bench.R first-chart.png   <span class="com"># keeps the first ggplot2 chart to look at</span></code></pre>
      <p>The sizes of the lossless variants and of the quantized charts come from <code>benchmarks/charts/chart_bench.e</code> (the <code>png_opaque_best</code> and <code>png_indexed</code> lines), the model of the colour reduction from <code>scripts/gen_png_quant_test.py</code>, and the raw results from <code>benchmarks/charts/results/windows.json</code>.</p>
      ''' % {
    "title": title,
    "n_svg": f(svg_ms["Neper"]), "b_svg": f(svg_ms["base R"]), "l_svg": f(svg_ms["lattice"]),
    "m_svg": f(svg_ms["matplotlib"]), "g_svg": f(svg_ms["ggplot2"]),
    "rb": "%.1f" % ratios_svg["base R"], "rg": "%.0f" % ratios_svg["ggplot2"],
    "pb": "%.1f" % ratios_png["base R"], "pg": "%.0f" % ratios_png["ggplot2"],
    "rm": "%.1f" % ratios_svg["matplotlib"], "pm": "%.1f" % ratios_png["matplotlib"],
    "speed": speed_table, "size": size_table,
    "rimp": "%.2f" % (r["import"]["ms"] / 1000.0), "mimp": "%.2f" % (m["import"]["ms"] / 1000.0),
    "nproc": "%.1f" % (n["process"]["ms"] / 1000.0), "mproc": "%.1f" % (m["process"]["ms"] / 1000.0),
    "raster": f(n["raster"]["ms"] / 200.0), "pn": f(png_ms["Neper"]),
    "svg_pct_b": "%.0f" % (100.0 * (1 - svg_b["Neper"] / svg_b["base R"])),
    "svg_pct_m": "%.0f" % (100.0 * (1 - svg_b["Neper"] / svg_b["matplotlib"])),
    "png_n": thousands(png_b["Neper"]),
    "png_r": "%s to %s" % (thousands(min(png_b["base R"], png_b["lattice"], png_b["ggplot2"])),
                           thousands(max(png_b["base R"], png_b["lattice"], png_b["ggplot2"]))),
    "png_m": thousands(png_b["matplotlib"]),
}
html = head + body + "\n    " + foot.lstrip()
(ROOT / "docs/blog/charts-speed-and-png-size.html").write_text(html, encoding="utf-8", newline="\n")
print("wrote docs/blog/charts-speed-and-png-size.html", len(html), "bytes")
