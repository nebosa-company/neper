import importlib.util
import unittest
from pathlib import Path

REPORT = Path(__file__).parents[1] / "benchmarks" / "llm_gen" / "report.py"
SPEC = importlib.util.spec_from_file_location("llm_gen_report", REPORT)
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


def row(task, parse=True, check=True, fmt=True, correct=True):
    return {"task": task, "parse": parse, "check": check, "format": fmt, "correct": correct}


class SummarizeTests(unittest.TestCase):
    def test_clean_corpus_meets_every_threshold_and_has_nothing_to_repair(self):
        rows = [row(f"t{i}") for i in range(10)]
        got = report.summarize(rows, {}, "reference")
        self.assertTrue(got["pass"])
        self.assertIsNone(got["rates"]["repair"])
        self.assertEqual(got["source"], "reference")

    def test_one_failed_parse_in_ten_is_below_the_95_percent_threshold(self):
        rows = [row(f"t{i}") for i in range(9)] + [row("bad", parse=False, check=False)]
        got = report.summarize(rows, {}, "candidates")
        self.assertFalse(got["verdict"]["parse"])
        self.assertFalse(got["pass"])
        self.assertEqual(got["failed_first_pass"], ["bad"])

    def test_check_threshold_is_90_percent_so_one_in_ten_passes_it(self):
        rows = [row(f"t{i}") for i in range(9)] + [row("x", check=False)]
        got = report.summarize(rows, {"x": True}, "candidates")
        self.assertTrue(got["verdict"]["check"])
        self.assertEqual(got["rates"]["repair"], 1.0)
        self.assertTrue(got["pass"])

    def test_an_unrepaired_failure_fails_the_repair_threshold(self):
        rows = [row(f"t{i}") for i in range(9)] + [row("x", check=False)]
        got = report.summarize(rows, {}, "candidates")
        self.assertFalse(got["verdict"]["repair"])
        self.assertEqual(got["rates"]["repair"], 0.0)

    def test_any_formatting_diff_fails_zero_unrelated_diff(self):
        rows = [row(f"t{i}") for i in range(9)] + [row("x", fmt=False)]
        got = report.summarize(rows, {}, "candidates")
        self.assertFalse(got["verdict"]["format"])

    def test_an_empty_corpus_never_passes(self):
        self.assertFalse(report.summarize([], {}, "reference")["pass"])


if __name__ == "__main__":
    unittest.main()
