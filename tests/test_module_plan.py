import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("module_plan", ROOT / "scripts/check_module_plan.py")
checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checker)


def fixture():
    return {
        "tiers": [{"id": "core", "modules": ["e.sample"]},
                  {"id": "experimental", "modules": []}],
        "layers": [{"id": 0, "may_depend_on": [0]}],
        "modules": [{"name": "e.sample", "layer": 0, "surface": "planned",
                     "schedule": "later", "milestone": None,
                     "direct_dependencies": [], "blocked_by": []}],
    }


def api(body):
    return "### `e.sample`\n\n```neper\n" + body + "\n```\n"


class ModulePlanTests(unittest.TestCase):
    def test_repository_catalogue(self):
        plan = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        text = (ROOT / "docs/module-apis.md").read_text(encoding="utf-8")
        self.assertEqual(checker.validate(plan, text), [])

    def test_parameter_shadow(self):
        errors = checker.validate(fixture(), api("fn count() -> usize\nfn repeat(count: usize)"))
        self.assertTrue(any("parameter shadows count" in e for e in errors))

    def test_reserved_target(self):
        self.assertTrue(any("shadows target" in e for e in
                            checker.validate(fixture(), api("fn run(target: str)"))))

    def test_case_sensitive_names(self):
        self.assertEqual(checker.validate(fixture(), api("type Count = u32\nfn run(count: Count)")), [])

    def test_import_parameter_shadow(self):
        plan = fixture()
        dependency = copy.deepcopy(plan["modules"][0])
        dependency["name"] = "e.dep"
        plan["modules"].append(dependency)
        plan["tiers"][0]["modules"].append("e.dep")
        plan["modules"][0]["direct_dependencies"] = ["e.dep"]
        text = api("fn run(dep: u32)") + "### `e.dep`\n\n```neper\nfn read()\n```\n"
        self.assertTrue(any("shadows dep" in e for e in checker.validate(plan, text)))

    def test_cycle(self):
        plan = fixture()
        plan["modules"][0]["direct_dependencies"] = ["e.sample"]
        self.assertTrue(any("cycle" in e for e in checker.validate(plan, api("fn run()"))))

    def test_unknown_dependency(self):
        plan = fixture()
        plan["modules"][0]["direct_dependencies"] = ["e.missing"]
        self.assertTrue(any("unknown dependency" in e for e in checker.validate(plan, api("fn run()"))))

    def test_stability_edge(self):
        plan = fixture()
        dependency = copy.deepcopy(plan["modules"][0])
        dependency["name"] = "e.unstable"
        plan["modules"].append(dependency)
        plan["tiers"][1]["modules"].append("e.unstable")
        plan["modules"][0]["direct_dependencies"] = ["e.unstable"]
        text = api("fn run()") + "### `e.unstable`\n\n```neper\nfn read()\n```\n"
        self.assertTrue(any("stable-tier dependency" in e for e in checker.validate(plan, text)))

    def test_duplicate_fence(self):
        text = api("fn run()") + "\n```neper\nfn more()\n```\n"
        self.assertTrue(any("exactly one" in e for e in checker.validate(fixture(), text)))

    def test_missing_module(self):
        self.assertTrue(any("coverage" in e for e in checker.validate(fixture(), "")))

    def test_unknown_qualifier(self):
        self.assertTrue(any("undeclared signature qualifier" in e for e in
                            checker.validate(fixture(), api("fn run(x: other.Type)"))))

    def test_package_module_blocker(self):
        plan = fixture()
        plan["packages"] = [{"name": "x.owner.package", "blocked_by": ["e.sample"]}]
        self.assertEqual(checker.validate(plan, api("fn run()")), [])
        plan["packages"][0]["blocked_by"] = ["e.missing"]
        self.assertTrue(any("unknown module blocker" in e for e in checker.validate(plan, api("fn run()"))))

    def test_package_blocker_schema_matches_policy(self):
        schema = json.loads((ROOT / "docs/schemas/neper-v1.schema.json").read_text(encoding="utf-8"))
        pattern = schema["$defs"]["modulePlan"]["properties"]["packages"]["items"]["properties"]["blocked_by"]["items"]["pattern"]
        self.assertIsNotNone(re.fullmatch(pattern, "e.db"))
        self.assertIsNotNone(re.fullmatch(pattern, "gpu-presentation-api"))
        self.assertIsNone(re.fullmatch(pattern, "../untrusted"))


if __name__ == "__main__":
    unittest.main()
