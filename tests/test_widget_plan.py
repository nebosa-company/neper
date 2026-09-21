import importlib.util
import copy
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("widget_plan", ROOT / "scripts/check_widget_plan.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


def first_undelivered(plan):
    """The first component the plan still owes, in phase and item order."""
    for phase in plan["phases"]:
        for item in phase["items"]:
            missing = [c for c in item["components"] if c not in item["delivered"]]
            if missing:
                return item["id"], missing[0]
    return None


def fresh_last_phase(plan):
    """The plan with every earlier phase delivered and the last one not started, so
    the host-phase tests do not move as the repository delivers."""
    plan = copy.deepcopy(plan)
    for phase in plan["phases"][:-1]:
        for item in phase["items"]:
            item["delivered"] = list(item["components"])
    for item in plan["phases"][-1]["items"]:
        item["delivered"] = []
    plan["resolved_blockers"] = []
    return plan


class WidgetPlanTests(unittest.TestCase):
    def test_repository_widget_plan(self):
        plan, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        work = CHECKER.next_work(plan, modules)
        self.assertIn(work["state"], ("ready", "blocked", "complete"))
        if work["state"] == "ready":
            item = next(it for ph in plan["phases"] for it in ph["items"] if it["id"] == work["item"])
            self.assertIn(work["component"], item["components"])
            self.assertNotIn(work["component"], item["delivered"])

    def test_next_component_after_module_blockers(self):
        plan, _ = CHECKER.validate(ROOT)
        plan = copy.deepcopy(plan)
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        modules = copy.deepcopy(modules)
        blockers = set(plan["phases"][0]["blocked_by"])
        for module in modules["modules"]:
            if module["name"] in blockers:
                module["surface"] = "source"
        plan["resolved_blockers"] = sorted({blocker
                                             for phase in plan["phases"]
                                             for item in phase["items"]
                                             for blocker in item.get("blocked_by", [])
                                             if not blocker.startswith(("P", "e."))})
        work = CHECKER.next_work(plan, modules)
        expected = first_undelivered(plan)
        if expected is None:
            self.assertEqual(work["state"], "complete")
        else:
            self.assertEqual((work["state"], work["item"], work["component"]), ("ready",) + expected)

    def test_host_phase_requires_explicit_native_blockers(self):
        plan, _ = CHECKER.validate(ROOT)
        plan = fresh_last_phase(plan)
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        modules = copy.deepcopy(modules)
        for module in modules["modules"]:
            if module["name"] in plan["phases"][0]["blocked_by"]:
                module["surface"] = "source"

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
