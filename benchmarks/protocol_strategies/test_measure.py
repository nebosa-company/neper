import importlib.util
import unittest
from pathlib import Path


path = Path(__file__).with_name("measure.py")
spec = importlib.util.spec_from_file_location("protocol_strategy_measure", path)
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class MeasureTest(unittest.TestCase):
    def test_source_and_distribution(self):
        implicit = measure.make_source("implicit", 2)
        explicit = measure.make_source("explicit", 2)
        self.assertEqual(implicit.count("type Item"), 2)
        self.assertIn("T.cmp(a, b)", implicit)
        self.assertIn("compare[Item0001, item0001_cmp]", explicit)
        self.assertEqual(measure.distribution([3, 1, 2]), {
            "p50": 2,
            "p95": 2.9,
            "min": 1,
            "max": 3,
            "runs": 3,
        })


if __name__ == "__main__":
    unittest.main()
