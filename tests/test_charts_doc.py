"""Keep the chart guide and readiness page in their separate roles."""

from pathlib import Path
import base64
import re
import struct
import subprocess
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def tracked_pngs():
    names = subprocess.check_output(
        ["git", "ls-files", "docs/chart-previews/*.png"], cwd=ROOT, text=True
    ).splitlines()
    return [ROOT / name for name in sorted(names)]


def png_image_data(blob):
    assert blob.startswith(b"\x89PNG\r\n\x1a\n")
    offset = 8
    compressed = []
    while offset < len(blob):
        size = struct.unpack_from(">I", blob, offset)[0]
        kind = blob[offset + 4:offset + 8]
        payload = blob[offset + 8:offset + 8 + size]
        if kind == b"IDAT":
            compressed.append(payload)
        offset += size + 12
    return blob[16:29], zlib.decompress(b"".join(compressed))


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
            r'<img src="data:image/png;base64,([^"]+)"[^>]*></a>', page)
        self.assertEqual([name for name, _ in cards], [path.name for path in pngs])
        for path, (_, thumbnail) in zip(pngs, cards):
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertIn(f'href="chart-previews/{path.stem}.svg"', page)
            self.assertTrue(path.with_suffix(".svg").is_file())
            self.assertEqual(png_image_data(base64.b64decode(thumbnail)),
                             png_image_data(path.read_bytes()))
        self.assertLess(len(page), 10_000_000)
        self.assertIn('href="charts.html"', (DOCS / "progress.html").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
