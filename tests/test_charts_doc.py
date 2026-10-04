"""Keep the chart guide and readiness page in their separate roles."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


class ChartGuideTests(unittest.TestCase):
    def test_gallery_matches_rendered_pairs_and_backlog(self):
        guide = (DOCS / "charts.md").read_text(encoding="utf-8")
        pngs = sorted((DOCS / "chart-previews").glob("*.png"))
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
        rendered = len(list((DOCS / "chart-previews").glob("*.png")))
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


if __name__ == "__main__":
    unittest.main()
