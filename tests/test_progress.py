"""Check the generated unfinished-work lists against their inventories."""
import contextlib
import html
import io
import json
import os
from pathlib import Path
import re
import runpy
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProgressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        previous = Path.cwd()
        sys.path.insert(0, str(ROOT / "scripts"))
        try:
            os.chdir(ROOT)
            with contextlib.redirect_stdout(io.StringIO()):
                cls.render = runpy.run_path(str(ROOT / "scripts/render_progress.py"))
        finally:
            os.chdir(previous)
            sys.path.pop(0)
        cls.page = (ROOT / "docs/progress.html").read_text(encoding="utf-8")
        cls.sections = dict(re.findall(
            r'<details id="unfinished-([a-z]+)">(.*?)</details>', cls.page, re.S))

    def test_numbered_queue_follows_pickup_order_across_categories(self):
        self.assertEqual(list(self.sections), ["queue", "modules"])
        queue = json.loads((ROOT / "docs/work-queue.json").read_text(encoding="utf-8"))
        expected = [item["id"] for item in queue["items"] if float(item["score"]) < 1]
        section = self.sections["queue"]
        actual = re.findall(r'<tr><td>(\d+)</td><td><code>(.*?)</code>', section)
        self.assertEqual(actual, [(str(i), task) for i, task in enumerate(expected, 1)])
        # The NeperOS stage is picked up first (D2119), then chart work (D1955) while any remains.
        self.assertTrue(re.fullmatch(r"C099|L0(6[1-2]|6[8-9]|7[0-5]|9[2-7])", expected[0]), expected[0])
        self.assertIn(f"{len(expected)} unfinished</summary>", section)
        self.assertNotIn("<details open", section)

    def test_chart_work_stays_a_prefix_of_the_pickup_queue(self):
        queue = json.loads((ROOT / "docs/work-queue.json").read_text(encoding="utf-8"))
        chart_ids = {"L061", "L062"} | {f"L{i:03}" for i in range(68, 76)} | {
            f"L{i:03}" for i in range(92, 98)
        }
        actual = [item["id"] for item in queue["items"]]
        if actual[:1] == ["C099"]:  # ahead of chart work by the user's priority (D2119)
            actual = actual[1:]
        active_chart_ids = chart_ids & set(actual)
        self.assertEqual(set(actual[:len(active_chart_ids)]), active_chart_ids)
        self.assertIn("then chart work", self.page)

    def test_release_labels_match_the_cpu_release_gate(self):
        queue = json.loads((ROOT / "docs/work-queue.json").read_text(encoding="utf-8"))
        expected_ids = self.render["RELEASE_REQUIRED_IDS"]
        self.assertEqual(expected_ids,
                         {"C082", "C088", "T004", "T012", "T016", "T023"})
        section = self.sections["queue"]
        actual = re.findall(
            r'<code>([CTL]\d{3})</code></td><td>.*?</td>'
            r'<td><span class="release-status (required|enhancement)">',
            section)
        self.assertEqual(actual, [
            (item["id"], "required" if item["id"] in expected_ids else "enhancement")
            for item in queue["items"] if float(item["score"]) < 1
        ])
        active_required = len(expected_ids & {item["id"] for item in queue["items"]})
        self.assertIn(
            f"{active_required} release-required and "
            f"{len(queue['items']) - active_required} enhancements", self.page)

    def test_module_release_labels_follow_module_tiers(self):
        section = self.sections["modules"]
        actual = re.findall(
            r'<code>(e\.[^<]+)</code></td><td>.*?</td>'
            r'<td><span class="release-status (required|enhancement)">',
            section)
        core = self.render["core_modules"]
        self.assertEqual(actual, [
            (module, "required" if module in core else "enhancement")
            for module in sorted(self.render["module_missing"])
        ])
        self.assertIn("0 are core release requirements", self.page)

    def test_module_rows_account_for_every_missing_symbol(self):
        section = self.sections["modules"]
        missing = self.render["module_missing"]
        actual = re.findall(r'<tr><td>(\d+)</td><td><code>(.*?)</code>', section)
        self.assertEqual(actual, [(str(i), name)
                                 for i, name in enumerate(sorted(missing), 1)])
        self.assertEqual(sum(map(len, missing.values())),
                         self.render["dtot"] - self.render["dgot"])
        for names in missing.values():
            self.assertIn(html.escape(", ".join(sorted(names))), section)

    def test_empty_section_and_untrusted_text(self):
        render = self.render["unfinished_details"]
        self.assertIn("No unfinished items.", render("Library", []))
        result = render("Library", [("L001", '<script>alert("x")</script>', "a & b", False)])
        self.assertNotIn("<script>", result)
        self.assertIn("&lt;script&gt;", result)
        self.assertIn("a &amp; b", result)
        self.assertIn('<tr><td>1</td><td><code>L001</code>', result)


if __name__ == "__main__":
    unittest.main()
