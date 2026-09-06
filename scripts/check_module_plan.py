"""Read-only structural checks for the planned library; not a Neper type checker."""
import argparse
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
ALIASES = {
    "e.gpu.tensor": {"e.algo.linalg.tensor": "linalg_tensor"},
    "e.ui.widget": {"e.text.layout": "layout", "e.ui.layout": "ui_layout"},
    "e.async.io": {"e.cancel": "cancel_api"},
}
RESERVED = {
    "target", "void", "err", "bool", "type", "usize", "isize", "f16", "bf16",
    "f32", "f64", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64",
    "Vec", "Mask", "Atomic",
}


def catalogue_sections(text):
    headings = list(re.finditer(r"^### `([^`]+)`\s*$", text, re.M))
    sections, errors = {}, []
    for index, heading in enumerate(headings):
        name = heading[1]
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        section = text[heading.end():end]
        fences = re.findall(r"^```neper\s*\n(.*?)^```\s*$", section, re.M | re.S)
        if name in sections:
            errors.append(f"duplicate catalogue module: {name}")
        if len(fences) != 1:
            errors.append(f"{name}: expected exactly one neper API fence")
        sections[name] = fences[0] if fences else ""
    return sections, errors


def validate(plan, catalogue):
    errors = []
    modules = {}
    for module in plan["modules"]:
        name = module["name"]
        if name in modules:
            errors.append(f"duplicate module: {name}")
        modules[name] = module
    tiers = {}
    for tier in plan["tiers"]:
        for name in tier["modules"]:
            if name in tiers:
                errors.append(f"duplicate tier member: {name}")
            tiers[name] = tier["id"]
    if set(tiers) != set(modules):
        errors.append("tier membership differs from module names")
    layers = {layer["id"]: set(layer["may_depend_on"]) for layer in plan["layers"]}
    sections, section_errors = catalogue_sections(catalogue)
    errors.extend(section_errors)
    if set(sections) != set(modules):
        errors.append("catalogue coverage differs from module names")
    packages = plan.get("packages", [])
    package_names = [package["name"] for package in packages]
    if len(package_names) != len(set(package_names)):
        errors.append("duplicate package reservation")
    for owner in [*modules.values(), *packages]:
        for blocker in owner.get("blocked_by", []):
            if blocker not in modules and not re.fullmatch(r"[a-z][a-z0-9-]*", blocker):
                errors.append(f"{owner['name']}: unknown module blocker {blocker}")
    colors = {}

    def visit(name):
        if colors.get(name) == 1:
            errors.append(f"dependency cycle at {name}")
            return
        if colors.get(name) == 2:
            return
        colors[name] = 1
        for dependency in modules[name]["direct_dependencies"]:
            if dependency in modules:
                visit(dependency)
        colors[name] = 2

    for name, module in modules.items():
        scheduled = module["schedule"] == "scheduled"
        if scheduled != (module["milestone"] is not None):
            errors.append(f"{name}: schedule/milestone mismatch")
        if module["layer"] not in layers:
            errors.append(f"{name}: unknown layer")
        dependencies = module["direct_dependencies"]
        if len(dependencies) != len(set(dependencies)):
            errors.append(f"{name}: duplicate dependency")
        for dependency in dependencies:
            if dependency not in modules:
                errors.append(f"{name}: unknown dependency {dependency}")
                continue
            if modules[dependency]["layer"] not in layers.get(module["layer"], set()):
                errors.append(f"{name}: disallowed layer edge to {dependency}")
            if tiers.get(name) != "experimental" and tiers.get(dependency) == "experimental":
                errors.append(f"{name}: stable-tier dependency on experimental {dependency}")
        visit(name)
        aliases = {}
        for dependency in dependencies:
            qualifier = ALIASES.get(name, {}).get(dependency, dependency.rsplit(".", 1)[-1])
            if qualifier in aliases:
                errors.append(f"{name}: duplicate import qualifier {qualifier}")
            aliases[qualifier] = dependency
        body = sections.get(name, "")
        declarations = re.findall(r"^(fn|type|error|const|var) (\w+)", body, re.M)
        value_names = [symbol for kind, symbol in declarations if kind != "type"]
        type_names = [symbol for kind, symbol in declarations if kind == "type"]
        for namespace in (value_names, type_names):
            if len(namespace) != len(set(namespace)):
                errors.append(f"{name}: duplicate declaration in one namespace")
        for qualifier in aliases:
            if qualifier in value_names:
                errors.append(f"{name}: import qualifier collides with declaration {qualifier}")
        blocked = set(value_names) | set(type_names) | set(aliases) | RESERVED
        for declaration in re.findall(r"^fn [^\n]+", body, re.M):
            function = re.match(r"fn (\w+)", declaration)[1]
            # Catalogue signatures are single-line; nested callback types are
            # unnamed. This intentionally does not implement full language parsing.
            parameters = re.findall(r"(?:\(|,\s*)([a-z_]\w*)\s*:", declaration)
            for parameter in parameters:
                if parameter in blocked:
                    errors.append(f"{name}.{function}: parameter shadows {parameter}")
            if len(parameters) != len(set(parameters)):
                errors.append(f"{name}.{function}: duplicate parameter")
        for qualifier in set(re.findall(r"\b([a-z_]\w*)\.[A-Z]\w*", body)):
            if qualifier not in aliases:
                errors.append(f"{name}: undeclared signature qualifier {qualifier}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    plan = json.loads((args.root / "docs/modules.json").read_text(encoding="utf-8"))
    catalogue = (args.root / "docs" / plan["api_catalog"]).read_text(encoding="utf-8")
    errors = validate(plan, catalogue)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PASS: {len(plan['modules'])} modules; graph, tiers, API fences and signature names")
    print("Static validation only; real resolver and executable conformance remain required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
