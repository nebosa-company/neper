"""Keep the chart guide and readiness page in their separate roles."""

from pathlib import Path
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def tracked_pngs():
    names = subprocess.check_output(
        ["git", "ls-files", "docs/chart-previews/*.png"], cwd=ROOT, text=True
    ).splitlines()
    return [ROOT / name for name in sorted(names)]


class ChartGuideTests(unittest.TestCase):
    def test_gallery_matches_rendered_pairs_and_backlog(self):
        guide = (DOCS / "charts.md").read_text(encoding="utf-8")
        pngs = tracked_pngs()
        planned = [line for line in (DOCS / "chart-preview-backlog.txt").read_text(
            encoding="utf-8").splitlines() if line and not line.startswith("#")]
        self.assertIn(f"## Rendered previews ({len(pngs)}/{len(pngs) + len(planned)})", guide)
        rows = re.findall(
            r"^\| ([^|]+) \| !\[[^]]+\]\(chart-previews/([^)]*\.png)\) "
            r"\| \[SVG\]\(chart-previews/([^)]*\.svg)\) \|$", guide, re.M)
        self.assertEqual([png for _, png, _ in rows], [path.name for path in pngs])
        self.assertEqual([svg for _, _, svg in rows], [path.with_suffix(".svg").name for path in pngs])

    def test_progress_links_to_guide_without_embedding_gallery_or_plan(self):
        progress = (DOCS / "progress.html").read_text(encoding="utf-8")
        guide = (DOCS / "charts.md").read_text(encoding="utf-8")
        rendered = len(tracked_pngs())
        planned = sum(bool(line and not line.startswith("#")) for line in
                      (DOCS / "chart-preview-backlog.txt").read_text(
                          encoding="utf-8").splitlines())
        self.assertIn('href="charts.md"', progress)
        self.assertIn(f"Rendered previews ({rendered}/{rendered + planned})", progress)
        self.assertNotIn('<div class="previews">', progress)
        self.assertNotIn('<pre class="plan">', progress)
        self.assertIn("## Preview descriptions", guide)
        self.assertIn("## Neper charting engine plan", guide)
        self.assertIn("[progress.html](progress.html)", guide)

    def test_browser_gallery_resolves_every_preview(self):
        page = (DOCS / "charts.html").read_text(encoding="utf-8")
        pngs = tracked_pngs()
        cards = re.findall(
            r'<a href="chart-previews/([^"/]+\.png)">'
            r'<img src="chart-previews/([^"/]+\.png)"[^>]*></a>', page)
        self.assertEqual(cards, [(path.name, path.name) for path in pngs])
        for path in pngs:
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertIn(f'href="chart-previews/{path.stem}.svg"', page)
            self.assertTrue(path.with_suffix(".svg").is_file())
            svg = ET.parse(path.with_suffix(".svg"))
            self.assertEqual(svg.getroot().tag, "{http://www.w3.org/2000/svg}svg")
        self.assertNotIn("data:image/png;base64,", page)
        if any(path.stem == "interactive_selection" for path in pngs):
            self.assertIn('href="chart-previews/interactive_selection.svg">Select in SVG</a>', page)
        self.assertLess(len(page), 100_000)
        self.assertIn('href="charts.html"', (DOCS / "progress.html").read_text(encoding="utf-8"))

    def test_interactive_selection_has_focusable_source_row_targets(self):
        svg = ET.parse(DOCS / "chart-previews" / "interactive_selection.svg").getroot()
        ns = "{http://www.w3.org/2000/svg}"
        links = svg.findall(f".//{ns}a")
        self.assertEqual([link.get("data-row-id") for link in links],
                         ["0", "1", "3", "4", "6", "7", "8"])
        for index, link in enumerate(links):
            self.assertEqual(link.get("id"), f"point-{index}")
            self.assertEqual(link.get("href"), f"#point-{index}")
            self.assertEqual(link.get("tabindex"), "0")
            self.assertTrue(link.find(f"{ns}title").text)
            self.assertIsNotNone(link.find(f"{ns}rect[@class='np-selection-halo']"))
        style = svg.find(f"{ns}style")
        self.assertIn("a:target .np-selection-halo", style.text)
        self.assertIn("a:focus .np-selection-halo", style.text)

    def test_accessible_palette_labels_clear_wcag_contrast(self):
        # An independent WCAG 2 computation over the bytes Neper wrote.
        def luminance(rgb):
            def linear(byte):
                c = byte / 255
                return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
            r, g, b = (linear(int(part)) for part in rgb.split(","))
            return 0.2126 * r + 0.7152 * g + 0.0722 * b

        def contrast(first, second):
            hi, lo = sorted((luminance(first), luminance(second)), reverse=True)
            return (hi + 0.05) / (lo + 0.05)

        svg = (DOCS / "chart-previews" / "accessible_palette.svg").read_text(encoding="utf-8")
        labels = re.findall(r'fill="rgb\(([0-9,]+)\)" fill-opacity="1">S[1-6]<', svg)
        self.assertEqual(len(labels), 12)
        self.assertEqual(len(set(labels[:6])), 6)
        self.assertEqual(len(set(labels[6:])), 6)
        for color in labels[:6]:
            self.assertGreaterEqual(contrast(color, "255,255,255"), 4.5)
        for color in labels[6:]:
            self.assertGreaterEqual(contrast(color, "28,33,43"), 4.5)

    def test_gradient_font_embeds_the_raster_face(self):
        import base64
        svg = (DOCS / "chart-previews" / "gradient_font.svg").read_text(encoding="utf-8")
        payload = re.search(r'font-family:"Montserrat";src:url\(data:font/ttf;base64,([A-Za-z0-9+/=]+)\)', svg)
        face = DOCS / "video" / "neper-capabilities" / "fonts" / "Montserrat-ExtraBold.ttf"
        self.assertEqual(base64.b64decode(payload.group(1), validate=True), face.read_bytes())
        root = ET.fromstring(svg)
        ns = "{http://www.w3.org/2000/svg}"
        ids = {g.get("id") for g in root.iter(f"{ns}linearGradient")}
        self.assertEqual(ids, {"columns", "trend"})
        self.assertEqual(svg.count('fill="url(#columns)"'), 6)
        self.assertIn('stroke="url(#trend)"', svg)
        self.assertNotIn("font-family=\"sans-serif\"", svg)

    def test_color_vision_rows_match_an_independent_simulation(self):
        # Vienot-Brettel-Mollon from the LMS matrix and anchor planes, solved here
        # rather than copied from Neper's folded matrices.
        lms = [[17.8824, 43.5161, 4.11935], [3.45565, 27.1554, 3.86714], [0.0299566, 0.184309, 1.46709]]

        def mul(m, v):
            return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]

        def inverse(m):
            (a, b, c), (d, e, f), (g, h, i) = m
            det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
            return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
                    [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
                    [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]

        def plane(target, anchors):
            o = [k for k in range(3) if k != target]
            (p, q), (r, s) = [[mul(lms, x)[k] for k in o] for x in anchors]
            y1, y2 = [mul(lms, x)[target] for x in anchors]
            det = p * s - q * r
            return target, o, ((y1 * s - q * y2) / det, (p * y2 - y1 * r) / det)

        planes = [plane(0, ([1, 1, 1], [0, 0, 1])), plane(1, ([1, 1, 1], [0, 0, 1])), plane(2, ([1, 1, 1], [1, 0, 0]))]
        back = inverse(lms)

        def simulate(rgb, kind):
            lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
            cone = mul(lms, lin)
            target, others, (u, v) = planes[kind]
            cone[target] = u * cone[others[0]] + v * cone[others[1]]
            out = [min(max(c, 0.0), 1.0) for c in mul(back, cone)]
            return [round(255 * (c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)) for c in out]

        svg = (DOCS / "chart-previews" / "color_vision.svg").read_text(encoding="utf-8")
        swatches = [list(map(int, m)) for m in re.findall(
            r'width="26" height="26" fill="rgb\((\d+),(\d+),(\d+)\)"', svg)]
        self.assertEqual(len(swatches), 24)
        for row in range(3):
            for i in range(6):
                expected = simulate([c / 255 for c in swatches[i]], row)
                got = swatches[6 * (row + 1) + i]
                self.assertTrue(all(abs(e - g) <= 1 for e, g in zip(expected, got)), (row, i, expected, got))


if __name__ == "__main__":
    unittest.main()
