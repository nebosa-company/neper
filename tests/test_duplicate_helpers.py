import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("duplicate_helpers", ROOT / "scripts/check_duplicate_helpers.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)

HELPER = """// a comment that is not part of the body
fn first_digit(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if text[i] >= 48u8 && text[i] <= 57u8 { ret true }
        i += 1usize
    }
    ret false
}
"""


class DuplicateHelperTests(unittest.TestCase):
    def test_count_only_falls(self):
        base = json.loads((ROOT / "docs/duplicate-helpers.json").read_text(encoding="utf-8"))
        dup = checker.scan()
        self.assertLessEqual(len(dup), base["groups"])
        self.assertLessEqual(sum(len(v) - 1 for v in dup.values()), base["copies"])

    def test_identical_bodies_in_two_files_are_found(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = Path(tmp) / "a.e"
            b = Path(tmp) / "b.e"
            a.write_text(HELPER, encoding="utf-8")
            b.write_text(HELPER.replace("first_digit", "has_digit").replace("// a comment that is not part of the body", "// another comment"), encoding="utf-8")
            ka = [k for _, k in checker.functions(a)]
            kb = [k for _, k in checker.functions(b)]
            self.assertEqual(ka, kb)
            self.assertEqual(len(ka), 1)

    def test_different_bodies_are_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = Path(tmp) / "a.e"
            b = Path(tmp) / "b.e"
            a.write_text(HELPER, encoding="utf-8")
            b.write_text(HELPER.replace("57u8", "58u8"), encoding="utf-8")
            self.assertNotEqual([k for _, k in checker.functions(a)], [k for _, k in checker.functions(b)])

    def test_short_forwarders_are_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = Path(tmp) / "a.e"
            a.write_text("fn same(a: str, b: str) -> bool { ret str.eq(a, b) }\n", encoding="utf-8")
            self.assertEqual(list(checker.functions(a)), [])


if __name__ == "__main__":
    unittest.main()
