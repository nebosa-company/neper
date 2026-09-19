"""Validate the machine-readable UI and host-integration inventory."""
import argparse
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r"[A-Z][A-Za-z0-9]*$")
MODULE = re.compile(r"e(?:\.[a-z][a-z0-9_]*)+$")
BLOCKER = re.compile(r"[a-z][a-z0-9-]*$")


def validate_blockers(blockers, phase_ids, known_modules, owner, errors):
    if len(blockers) != len(set(blockers)):
        errors.append(f"{owner}: duplicate blocker")
    for blocker in blockers:
        if blocker.startswith("P") and blocker not in phase_ids:
            errors.append(f"{owner}: phase blocker must be earlier: {blocker}")
        elif blocker.startswith("e.") and blocker not in known_modules:
            errors.append(f"{owner}: unknown module blocker: {blocker}")
        elif not blocker.startswith(("P", "e.")) and not BLOCKER.fullmatch(blocker):
            errors.append(f"{owner}: invalid external blocker: {blocker}")


def unresolved_blockers(blockers, complete_phases, surfaces, resolved_blockers):
    return [blocker for blocker in blockers
            if (blocker.startswith("P") and blocker not in complete_phases)
            or (blocker.startswith("e.") and surfaces.get(blocker) != "source")
            or (not blocker.startswith(("P", "e."))
                and blocker not in resolved_blockers)]


def validate(root=ROOT):
    errors = []
    plan = json.loads((root / "docs/widget-plan.json").read_text(encoding="utf-8"))
    modules = json.loads((root / "docs/modules.json").read_text(encoding="utf-8"))
    known_modules = {item["name"] for item in modules["modules"]}
    candidates = plan.get("candidate_modules", [])
    resolved_blockers = plan.get("resolved_blockers", [])
    if plan.get("schema") != "neper-widget-plan-v1" or plan.get("version") != 1:
        errors.append("unsupported widget plan schema/version")
    if not (root / plan.get("proposal", "")).is_file():
        errors.append("widget proposal is missing")
    if len(candidates) != len(set(candidates)) or any(not MODULE.fullmatch(x) for x in candidates):
        errors.append("invalid or duplicate candidate module")
    if (len(resolved_blockers) != len(set(resolved_blockers))
            or any(not BLOCKER.fullmatch(x) for x in resolved_blockers)):
        errors.append("invalid or duplicate resolved blocker")
    allowed_modules = known_modules | set(candidates)
    phase_ids, item_ids, components = set(), set(), set()
    phases = plan.get("phases", [])
    for index, phase in enumerate(phases):
        phase_id = phase.get("id")
        if phase_id != f"P{index}":
            errors.append(f"phase {phase_id}: expected P{index}")
        if phase_id in phase_ids:
            errors.append(f"duplicate phase: {phase_id}")
        validate_blockers(phase.get("blocked_by", []), phase_ids,
                          known_modules, phase_id, errors)
        phase_ids.add(phase_id)
        for item in phase.get("items", []):
            item_id = item.get("id")
            if item_id in item_ids or not re.fullmatch(rf"{phase_id}-[0-9]{{2}}", item_id or ""):
                errors.append(f"invalid or duplicate item id: {item_id}")
            item_ids.add(item_id)
            validate_blockers(item.get("blocked_by", []), phase_ids - {phase_id},
                              known_modules, item_id, errors)
            if item.get("module") not in allowed_modules:
                errors.append(f"{item_id}: unknown owning module {item.get('module')}")
            names = item.get("components", [])
            delivered = item.get("delivered", [])
            if not names:
                errors.append(f"{item_id}: empty component list")
            for name in names:
                if not NAME.fullmatch(name):
                    errors.append(f"{item_id}: invalid component name {name}")
                if name in components:
                    errors.append(f"duplicate component: {name}")
                components.add(name)
            if len(delivered) != len(set(delivered)) or not set(delivered) <= set(names):
                errors.append(f"{item_id}: delivered must be a unique component subset")
            if delivered and not item.get("evidence"):
                errors.append(f"{item_id}: delivered components require evidence")
    if not phases or not components:
        errors.append("widget plan is empty")
    return plan, errors


def next_work(plan, module_plan):
    surfaces = {item["name"]: item["surface"] for item in module_plan["modules"]}
    resolved_blockers = set(plan.get("resolved_blockers", []))
    complete_phases = set()
    for phase in plan["phases"]:
        blocked = unresolved_blockers(phase["blocked_by"], complete_phases, surfaces,
                                      resolved_blockers)
        if blocked:
            return {"state": "blocked", "phase": phase["id"], "blocked_by": blocked}
        first_blocked = None
        for item in phase["items"]:
            missing = [name for name in item["components"] if name not in item["delivered"]]
            if missing:
                blocked = unresolved_blockers(item.get("blocked_by", []), complete_phases,
                                              surfaces, resolved_blockers)
                if blocked:
                    if first_blocked is None:
                        first_blocked = {"state": "blocked", "phase": phase["id"],
                                         "item": item["id"], "blocked_by": blocked}
                    continue
                return {"state": "ready", "phase": phase["id"], "item": item["id"],
                        "component": missing[0], "module": item["module"]}
        if first_blocked is not None:
            return first_blocked
        complete_phases.add(phase["id"])
    return {"state": "complete"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--next", action="store_true", help="print the next eligible component")
    args = parser.parse_args()
    plan, errors = validate()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    count = sum(len(item["components"]) for phase in plan["phases"] for item in phase["items"])
    print(f"PASS: {len(plan['phases'])} phases; {count} UI and host capabilities")
    if args.next:
        modules = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
        work = next_work(plan, modules)
        if work["state"] == "ready":
            print(f"NEXT: {work['phase']} {work['item']} {work['component']} ({work['module']})")
        elif work["state"] == "blocked":
            location = f"{work['phase']} {work['item']}" if "item" in work else work["phase"]
            print(f"BLOCKED: {location} by {', '.join(work['blocked_by'])}")
        else:
            print("COMPLETE: all widget capabilities delivered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
