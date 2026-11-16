import importlib.util
import os
from pathlib import Path
import re
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ceilings", ROOT / "scripts/ceilings.py")
ceilings = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ceilings)


class CeilingTests(unittest.TestCase):
    def test_every_marker_in_the_library_is_listed(self):
        os.chdir(ROOT)
        listed = sum(len(v) for v in ceilings.declared_ceilings().values())
        counted = 0
        for path in (ROOT / "lib/e").rglob("*.e"):
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                at = line.find("ponytail:")
                if at >= 0 and "//" in line[:at]:
                    counted += 1
        self.assertEqual(listed, counted)
        self.assertGreater(listed, 300)

    def test_two_runs_agree(self):
        os.chdir(ROOT)
        self.assertEqual(ceilings.declared_ceilings(), ceilings.declared_ceilings())

    def test_the_progress_page_carries_the_table(self):
        os.chdir(ROOT)
        page = (ROOT / "docs/progress.html").read_text(encoding="utf-8")
        total = sum(len(v) for v in ceilings.declared_ceilings().values())
        self.assertIn("%d declared ceilings" % total, page)
        self.assertIsNotNone(re.search(r'id="ceilings"', page))

    def test_a_marker_with_a_continuation_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            module = Path(tmp) / "sample.e"
            module.write_text("// ponytail: a global lock,\n// per-account locks if throughput matters\nfn f() {}\n// no marker here\n", encoding="utf-8")
            found = ceilings.declared_ceilings(tmp)
            self.assertEqual(found, {"e.sample": ["a global lock, per-account locks if throughput matters"]})


if __name__ == "__main__":
    unittest.main()
