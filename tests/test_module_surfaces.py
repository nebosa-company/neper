import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "module_surfaces", ROOT / "scripts/check_module_surfaces.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


class ModuleSurfaceTests(unittest.TestCase):
    def test_repository_surfaces_match(self):
        # Every module the plan calls implemented declares exactly its surface.
        self.assertEqual(checker.main([]), 0)

    def test_checked_signature_drift_is_reported(self):
        problems = checker.compare_compiler_declarations(
            "e.demo", {("fn", "read"): "fn read(dst: []u8) -> err"},
            {("fn", "read"): "fn read(dst: []u8) -> (usize, err)"})
        self.assertEqual(len(problems), 1)
        self.assertIn("differs from checked source", problems[0])

    def test_trailing_aggregate_comma_is_not_surface_drift(self):
        self.assertEqual(
            checker.normalize_declaration("type Pair = struct { a: u8, b: u8, }"),
            "type Pair = struct { a: u8, b: u8 }")

    def test_source_matching_fence_is_clean(self):
        self.assertEqual(
            checker.compare("e.demo", {"a", "b"}, {"a", "b"}, set()), [])

    def test_partial_surface_allows_an_extra_helper(self):
        self.assertEqual(
            checker.compare_delivered(
                "e.demo", {"public"}, {"public", "helper"}, set()), [])

    def test_partial_surface_requires_every_catalogue_name(self):
        problems = checker.compare_delivered(
            "e.demo", {"public", "missing"}, {"public"}, set())
        self.assertEqual(len(problems), 1)
        self.assertIn("delivered M1/M2 surface", problems[0])

    def test_partial_compiler_allows_an_unindexed_seed(self):
        self.assertEqual(
            checker.compare_delivered_compiler_declarations(
                "e.demo", {("fn", "seeded"): "fn seeded()"}, {}, {"seeded"}),
            [])

    def test_partial_compiler_requires_an_indexed_source_declaration(self):
        problems = checker.compare_delivered_compiler_declarations(
            "e.demo", {("fn", "written"): "fn written()"}, {}, set())
        self.assertEqual(len(problems), 1)
        self.assertIn("compiler index has no fn declaration", problems[0])

    def test_dependent_intrinsic_can_skip_spelling_comparison(self):
        self.assertEqual(
            checker.compare_delivered_compiler_declarations(
                "e.demo", {("fn", "splat"): "fn splat[V: type](x: T) -> V"},
                {("fn", "splat"): "fn splat[V: type](x: meta.element_type[V]()) -> V"},
                set(), False),
            [])

    def test_seeded_intrinsic_satisfies_a_declaration(self):
        # `e.mem` and `e.os` are almost entirely compiler-provided, so a fenced name
        # with no source is satisfied by a seed.
        self.assertEqual(
            checker.compare("e.demo", {"a", "b"}, {"a"}, {"b"}), [])

    def test_undeclared_public_symbol_is_reported(self):
        # The language has no visibility mechanism, so a helper is a public symbol.
        problems = checker.compare("e.demo", {"a"}, {"a", "helper"}, set())
        self.assertEqual(len(problems), 1)
        self.assertIn("`helper` is declared in source but not in its surface",
                      problems[0])

    def test_missing_declaration_is_reported(self):
        problems = checker.compare("e.demo", {"a", "b"}, {"a"}, set())
        self.assertEqual(len(problems), 1)
        self.assertIn("`b` is in its surface but neither written in source",
                      problems[0])

    def test_a_rename_is_reported_from_both_sides(self):
        # Renaming one declaration is an extra and an absence at once, which is what
        # makes the two directions worth reporting separately.
        problems = checker.compare("e.demo", {"a"}, {"a_renamed"}, set())
        self.assertEqual(len(problems), 2)

    def test_a_seed_does_not_excuse_an_extra(self):
        # Seeding covers a missing declaration, never an unlisted one.
        problems = checker.compare("e.demo", {"a"}, {"a", "extra"}, {"extra"})
        self.assertEqual(len(problems), 1)
        self.assertIn("`extra` is declared in source", problems[0])

    def test_an_unlisted_seeded_intrinsic_is_reported(self):
        problems = checker.compare("e.demo", {"a"}, {"a"}, {"hidden"})
        self.assertEqual(len(problems), 1)
        self.assertIn("`hidden` is seeded as an intrinsic", problems[0])

    def test_every_fenced_module_name_is_in_the_plan(self):
        # A fence for a module the plan does not list would never be checked.
        import json
        plan = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        modules = plan["modules"] if isinstance(plan, dict) else plan
        planned = {entry["name"] for entry in modules}
        for module in checker.fenced_surfaces():
            self.assertIn(module, planned, "%s has a fence but no plan entry" % module)


if __name__ == "__main__":
    unittest.main()
