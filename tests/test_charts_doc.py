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


if __name__ == "__main__":
    unittest.main()
