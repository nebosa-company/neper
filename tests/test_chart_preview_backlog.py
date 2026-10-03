"""Keep the gallery counter in the same unit on both sides of the ratio."""

from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET


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
        for name in rendered:
            self.assertEqual((PREVIEWS / f"{name}.png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(ET.parse(PREVIEWS / f"{name}.svg").getroot().tag,
                             "{http://www.w3.org/2000/svg}svg")
        self.assertIn("decision_tree", rendered)
        self.assertNotIn("decision_tree", planned)
        self.assertIn("org_chart", rendered)
        self.assertNotIn("org_chart", planned)
        self.assertIn("dependency_graph", rendered)
        self.assertNotIn("dependency_graph", planned)
        self.assertIn("flowchart", rendered)
        self.assertNotIn("flowchart", planned)
        self.assertIn("state_machine", rendered)
        self.assertNotIn("state_machine", planned)
        self.assertIn("sequence_diagram", rendered)
        self.assertNotIn("sequence_diagram", planned)
        self.assertIn("entity_relationship", rendered)
        self.assertNotIn("entity_relationship", planned)
        self.assertIn("branching_process_map", rendered)
        self.assertNotIn("branching_process_map", planned)
        self.assertIn("stem_and_leaf", rendered)
        self.assertNotIn("stem_and_leaf", planned)
        self.assertIn("range_interval", rendered)
        self.assertNotIn("range_interval", planned)
        self.assertIn("probability_plot", rendered)
        self.assertNotIn("probability_plot", planned)
        self.assertIn("spine_plot", rendered)
        self.assertNotIn("spine_plot", planned)
        self.assertIn("hexbin", rendered)
        self.assertNotIn("hexbin", planned)
        self.assertIn("bin2d", rendered)
        self.assertNotIn("bin2d", planned)
        self.assertIn("density2d", rendered)
        self.assertNotIn("density2d", planned)
        self.assertIn("half_violin", rendered)
        self.assertNotIn("half_violin", planned)
        self.assertIn("raincloud", rendered)
        self.assertNotIn("raincloud", planned)
        self.assertIn("slopegraph", rendered)
        self.assertNotIn("slopegraph", planned)
        self.assertIn("connected_scatter", rendered)
        self.assertNotIn("connected_scatter", planned)
        self.assertIn("marginal_histogram", rendered)
        self.assertNotIn("marginal_histogram", planned)
        self.assertIn("dose_response", rendered)
        self.assertNotIn("dose_response", planned)
        self.assertIn("hazard_rate", rendered)
        self.assertNotIn("hazard_rate", planned)
        self.assertIn("influence_plot", rendered)
        self.assertNotIn("influence_plot", planned)
        self.assertIn("capability_sixpack", rendered)
        self.assertNotIn("capability_sixpack", planned)

        page = PAGE.read_text(encoding="utf-8")
        match = re.search(r"Rendered previews \((\d+)/(\d+)\)", page)
        self.assertIsNotNone(match)
        self.assertEqual((int(match.group(1)), int(match.group(2))),
                         (len(rendered), len(rendered) + len(planned)))


if __name__ == "__main__":
    unittest.main()
