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
        actual = re.findall(r'<tr><td><code class="id-\w+">(.*?)</code>', self.backlog)
        self.assertEqual(actual, expected)
        # A NeperOS item is picked up first (D2119, D2125, D2148: C100-C114 so far), then chart work.
        self.assertTrue(re.fullmatch(r"C1(0[0-9]|1[0-4])|L0(6[1-2]|6[8-9]|7[0-5]|9[2-7])", expected[0]), expected[0])
        self.assertIn("Backlog — %d pending" % len(expected), self.backlog)

    def test_backlog_ids_carry_their_group_colour(self):
        key = self.render["group_key"]
        actual = re.findall(r'<code class="id-(\w+)">([CTL]\d{3})</code>', self.backlog)
        self.assertEqual(actual, [(key(item), item["id"])
                                  for item in self.queue["items"] if float(item["score"]) < 1])
        for name in ("compiler", "lib", "tooling", "neperos"):
            self.assertIn("code.id-%s{color:var(--c-%s)}" % (name, name), self.page)
        # The release-status column is gone.
        self.assertNotIn("release-status", self.page)

    def test_chart_work_stays_a_prefix_of_the_pickup_queue(self):
        chart_ids = {"L061", "L062"} | {f"L{i:03}" for i in range(68, 76)} | {
            f"L{i:03}" for i in range(92, 98)
        }
        actual = [item["id"] for item in self.queue["items"] if item["group"] != "NeperOS"]  # NeperOS first (D2125, D2148)
        active_chart_ids = chart_ids & set(actual)
        self.assertEqual(set(actual[:len(active_chart_ids)]), active_chart_ids)
        self.assertIn("then chart work", self.page)

    def test_release_required_items_stay_in_the_inventory(self):
        # The release gate is still validated against the work inventories, but the
        # backlog intro no longer prints a release-required count.
        expected_ids = self.render["RELEASE_REQUIRED_IDS"]
        self.assertEqual(expected_ids,
                         {"C082", "C088", "T004", "T012", "T016", "T023"})
        self.assertNotIn("release-required", self.page)

    def test_empty_section_and_untrusted_text(self):
        render = self.render["unfinished_details"]
        self.assertIn("No unfinished items.", render("Library", []))
        result = render("Library", [("L001", '<script>alert("x")</script>', "a & b", "lib")])
        self.assertNotIn("<script>", result)
        self.assertIn("&lt;script&gt;", result)
        self.assertIn("a &amp; b", result)
        self.assertIn('<tr><td><code class="id-lib">L001</code>', result)


if __name__ == "__main__":
    unittest.main()
