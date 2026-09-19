import importlib.util
import copy
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("widget_plan", ROOT / "scripts/check_widget_plan.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class WidgetPlanTests(unittest.TestCase):
    def test_repository_widget_plan(self):
        plan, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        self.assertEqual(CHECKER.next_work(plan, modules)["state"], "blocked")

    def test_next_component_after_module_blockers(self):
        plan, _ = CHECKER.validate(ROOT)
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        modules = copy.deepcopy(modules)
        blockers = set(plan["phases"][0]["blocked_by"])
        for module in modules["modules"]:
            if module["name"] in blockers:
                module["surface"] = "source"
        work = CHECKER.next_work(plan, modules)
        self.assertEqual((work["state"], work["item"], work["component"]),
                         ("ready", "P0-01", "ThemeTokens"))

    def test_host_phase_requires_explicit_native_blockers(self):
        plan, _ = CHECKER.validate(ROOT)
        plan = copy.deepcopy(plan)
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        modules = copy.deepcopy(modules)
        for module in modules["modules"]:
            if module["name"] in plan["phases"][0]["blocked_by"]:
                module["surface"] = "source"
        for phase in plan["phases"][:-1]:
            for item in phase["items"]:
                item["delivered"] = list(item["components"])

        work = CHECKER.next_work(plan, modules)
        self.assertEqual((work["item"], work["blocked_by"]),
                         ("P4-01", ["native-shell-api"]))

        plan["resolved_blockers"] = ["native-data-exchange-api"]
        work = CHECKER.next_work(plan, modules)
        self.assertEqual((work["state"], work["item"], work["component"]),
                         ("ready", "P4-04", "ContentType"))

        plan["resolved_blockers"] = sorted({blocker
                                             for item in plan["phases"][-1]["items"]
                                             for blocker in item.get("blocked_by", [])})
        work = CHECKER.next_work(plan, modules)
        self.assertEqual((work["state"], work["item"], work["component"]),
                         ("ready", "P4-01", "SystemTray"))


if __name__ == "__main__":
    unittest.main()
