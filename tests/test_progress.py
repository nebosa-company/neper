"""Check the generated readiness cards and the backlog list against their inventories."""
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
        # The one pending list lives in the Backlog section's open details.
        cls.backlog = re.search(
            r'<details id="unfinished-backlog" open>(.*?)</details>', cls.page, re.S).group(1)
        cls.queue = json.loads((ROOT / "docs/work-queue.json").read_text(encoding="utf-8"))

    def test_four_group_cards_show_their_scores(self):
        cards = re.findall(
            r'<section class="card (\w+)"><div class="lab">(.*?)</div>'
            r'<div class="val">([0-9]+\.[0-9]+)<span', self.page)
        expected = [
            ("compiler", "Compiler", self.render["COMPILER_PCT"]),
            ("lib", "Library – e.lib", self.render["ELIB_PCT"]),
            ("tooling", "Tooling", self.render["T"]),
            ("neperos", "NeperOS", self.render["NEPEROS_PCT"]),
        ]
        self.assertEqual([(key, label) for key, label, _ in cards],
                         [(key, label) for key, label, _ in expected])
        for (_, _, shown), (_, _, pct) in zip(cards, expected):
            self.assertEqual(shown, "%.2f" % pct)
        # The four group colours are the data-series tokens of the UX theme.
        for token in ("--c-compiler:#007dbc", "--c-lib:#00885b",
                      "--c-tooling:#93731f", "--c-neperos:#8269ba", "--c-backlog:#b36137"):
            self.assertIn(token, self.page)

    def test_backlog_follows_pickup_order_across_categories(self):
        expected = [item["id"] for item in self.queue["items"] if float(item["score"]) < 1]
        actual = re.findall(r'<tr><td>(\d+)</td><td><code>(.*?)</code>', self.backlog)
        self.assertEqual(actual, [(str(i), task) for i, task in enumerate(expected, 1)])
        # NeperOS stage 1 is picked up first (D2119, D2125), then chart work (D1955).
        self.assertTrue(re.fullmatch(r"C10[0-3]|L0(6[1-2]|6[8-9]|7[0-5]|9[2-7])", expected[0]), expected[0])
        self.assertIn("Backlog — %d pending" % len(expected), self.backlog)

    def test_chart_work_stays_a_prefix_of_the_pickup_queue(self):
        chart_ids = {"L061", "L062"} | {f"L{i:03}" for i in range(68, 76)} | {
            f"L{i:03}" for i in range(92, 98)
        }
        actual = [item["id"] for item in self.queue["items"]]
        while actual[:1] and actual[0] in {"C100", "C101", "C102", "C103"}:  # NeperOS first (D2125)
            actual = actual[1:]
        active_chart_ids = chart_ids & set(actual)
        self.assertEqual(set(actual[:len(active_chart_ids)]), active_chart_ids)
        self.assertIn("then chart work", self.page)

    def test_release_labels_match_the_cpu_release_gate(self):
        expected_ids = self.render["RELEASE_REQUIRED_IDS"]
        self.assertEqual(expected_ids,
                         {"C082", "C088", "T004", "T012", "T016", "T023"})
        actual = re.findall(
            r'<code>([CTL]\d{3})</code></td><td>.*?</td>'
            r'<td><span class="release-status (required|enhancement)">',
            self.backlog)
        self.assertEqual(actual, [
            (item["id"], "required" if item["id"] in expected_ids else "enhancement")
            for item in self.queue["items"] if float(item["score"]) < 1
        ])
        active_required = len(expected_ids & {item["id"] for item in self.queue["items"]})
        self.assertIn("%d are release-required" % active_required, self.page)

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
