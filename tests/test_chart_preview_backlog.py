"""Keep the gallery counter in the same unit on both sides of the ratio."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PREVIEWS = ROOT / "docs" / "chart-previews"
BACKLOG = ROOT / "docs" / "chart-preview-backlog.txt"
PAGE = ROOT / "docs" / "progress.html"


class ChartPreviewBacklogTests(unittest.TestCase):
    def test_rendered_and_planned_targets_are_disjoint(self):
        planned = [line.strip() for line in BACKLOG.read_text(encoding="utf-8").splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        rendered = {path.stem for path in PREVIEWS.glob("*.png")}
        self.assertEqual(len(planned), len(set(planned)))
        self.assertTrue(all(re.fullmatch(r"[a-z][a-z0-9_]*", name) for name in planned))
        self.assertFalse(rendered.intersection(planned))
        self.assertTrue(all((PREVIEWS / f"{name}.svg").is_file() for name in rendered))
        self.assertIn("decision_tree", rendered)
        self.assertNotIn("decision_tree", planned)
        self.assertIn("org_chart", rendered)
        self.assertNotIn("org_chart", planned)
        self.assertIn("dependency_graph", rendered)
        self.assertNotIn("dependency_graph", planned)

        page = PAGE.read_text(encoding="utf-8")
        match = re.search(r"Rendered previews \((\d+)/(\d+)\)", page)
        self.assertIsNotNone(match)
        self.assertEqual((int(match.group(1)), int(match.group(2))),
                         (len(rendered), len(rendered) + len(planned)))


if __name__ == "__main__":
    unittest.main()
