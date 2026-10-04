"""Keep the chart guide and readiness page in their separate roles."""

from pathlib import Path
import base64
import re
import subprocess
import unittest


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
            r'<a href="chart-previews/([^"/]+\.png)"><img '
            r'src="data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)" '
            r'alt="[^"]+" width="360" height="240"', page)
        self.assertEqual([name for name, _ in cards], [path.name for path in pngs])
        for path, (_, thumbnail) in zip(pngs, cards):
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertIn(f'href="chart-previews/{path.stem}.svg"', page)
            self.assertTrue(path.with_suffix(".svg").is_file())
            self.assertEqual(base64.b64decode(thumbnail), path.with_suffix(".svg").read_bytes())
        self.assertIn('href="charts.html"', (DOCS / "progress.html").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
