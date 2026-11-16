import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("algos_names", ROOT / "scripts/check_algos_names.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class AlgosNameTests(unittest.TestCase):
    def test_every_mapped_name_resolves(self):
        total, missing = checker.check((ROOT / "docs/algos.md").read_text(encoding="utf-8"))
        self.assertGreater(total, 1000)
        self.assertEqual(missing, [])

    def test_a_missing_name_is_reported(self):
        total, missing = checker.check("1. **Nothing** - none. \u2192 `e.algo.sort.no_such_sort`\n")
        self.assertEqual((total, missing), (1, [(1, "e.algo.sort.no_such_sort")]))

    def test_a_missing_module_is_reported(self):
        total, missing = checker.check("1. **Nothing** - none. \u2192 `e.algo.timeseries.arima`, `e.no.such.module`\n")
        self.assertEqual([name for _, name in missing], ["e.algo.timeseries.arima", "e.no.such.module"])

    def test_intrinsic_spellings_are_skipped(self):
        total, missing = checker.check("1. **CAS** - swap. \u2192 `e.atomic.cas` (the intrinsic's spelling)\n")
        self.assertEqual((total, missing), (0, []))

    def test_existing_names_resolve(self):
        total, missing = checker.check("1. **Sort** - sort. \u2192 `e.algo.sort.in_place`, `e.algo.bignum.int_mul`\n")
        self.assertEqual((total, missing), (2, []))


if __name__ == "__main__":
    unittest.main()
