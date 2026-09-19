"""Inventory application APIs/UI names under D:\\repos and compare to Neper."""
from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter, defaultdict
from pathlib import Path


CODE_EXTENSIONS = {
    ".c", ".cc", ".cpp", ".cs", ".dart", ".e", ".go", ".h", ".hpp",
    ".java", ".js", ".jsx", ".kt", ".m", ".mm", ".mjs", ".pas", ".py",
    ".rs", ".swift", ".ts", ".tsx", ".vue", ".xaml", ".xml", ".html",
}
UI_EXTENSIONS = CODE_EXTENSIONS | {".dfm", ".fmx", ".lfm", ".ui"}
SKIP_DIRS = {
    ".git", ".dart_tool", ".pub-cache", ".tgrep", ".claude", ".gradle", ".idea", ".venv", "__pycache__",
    "build", "dist", "node_modules", "target", "vendor", "generated",
}
SKIP_ROOTS = {"assets", "art-refresh", "mtg.studio.art"}
SKIP_ROOT_PREFIXES = ("neper-",)

PY_DEF = re.compile(r"^\s*(?:async\s+)?def\s+(\w+)\s*\(([^)]*)\)")
RUST_DEF = re.compile(r"^\s*(?:pub\s+)?(?:async\s+)?fn\s+(\w+)\s*\(([^)]*)\)")
GO_DEF = re.compile(r"^\s*func\s+(?:\([^)]*\)\s*)?(\w+)\s*\(([^)]*)\)")
PASCAL_DEF = re.compile(
    r"^\s*(?:(?:class\s+)?(?:procedure|function|constructor|destructor))\s+([\w.]+)\s*(?:\(([^)]*)\))?",
    re.I,
)
JS_DEF = re.compile(
    r"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)|"
    r"^\s*(?:export\s+)?(?:const|let)\s+(\w+)\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>"
)
TYPED_DEF = re.compile(
    r"^\s*(?:(?:public|private|protected|internal|static|final|override|async|virtual|abstract)\s+)*"
    r"[\w<>,.?\[\]| ]+\s+(\w+)\s*\(([^;{}]*)\)\s*(?:\{|=>|;)")
CALL_NAME = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\s*\(")
REACT_TAG = re.compile(r"<([A-Z][A-Za-z0-9_.]*)\b")
HTML_TAG = re.compile(r"<([a-z][a-z0-9-]*)\b")
VCL_OBJECT = re.compile(r"\b(?:object|inherited)\s+\w+\s*:\s*(T[A-Za-z0-9_]+)", re.I)
XAML_CLASS = re.compile(r"\b(?:x:Class|class|type)\s*=\s*[\"']([^\"']+)", re.I)
QT_MEMBER = re.compile(r"\b(?:Q[A-Z][A-Za-z0-9_]*|Gtk[A-Z][A-Za-z0-9_]*|T[A-Z][A-Za-z0-9_]*)\b")
VCL_MEMBER = re.compile(r"\bT(?:Button|CheckBox|ComboBox|Edit|Form|Label|ListBox|Memo|Menu|PageControl|Panel|RadioButton|Shape|SpeedButton|StatusBar|StringGrid|TabControl|ToolBar|TrackBar|TreeView|UpDown|Image|Timer|ActionList|MainMenu|PopupMenu|DataSource|DBGrid|DBEdit|DBNavigator)\b")

COMMON_CALLS = {
    "BuildContext", "Color", "DateTime", "Duration", "EdgeInsets", "Future", "Key",
    "List", "Map", "Object", "Offset", "Path", "Point", "Rect", "Size", "String",
    "TextStyle", "ThemeData", "Widget", "WidgetState", "ValueNotifier", "ChangeNotifier",
}

ALIASES = {
    "Container": "Box", "SizedBox": "Constrained", "Row": "Row", "Column": "Column",
    "TextButton": "Button", "ElevatedButton": "Button", "OutlinedButton": "Button",
    "IconButton": "IconButton", "Checkbox": "Checkbox", "Radio": "Radio", "Switch": "Switch",
    "Slider": "Slider", "RangeSlider": "RangeSlider", "TextField": "TextField",
    "TextFormField": "FormField", "DropdownButton": "Select", "ListView": "List",
    "GridView": "GridView", "TabBar": "Tabs", "TabBarView": "TabView",
    "Drawer": "NavigationDrawer", "NavigationRail": "NavigationRail",
    "BottomNavigationBar": "BottomNavigation", "AppBar": "AppBar", "SnackBar": "Snackbar",
    "AlertDialog": "AlertDialog", "Dialog": "Dialog", "Tooltip": "Tooltip",
    "CircularProgressIndicator": "ProgressRing", "LinearProgressIndicator": "ProgressBar",
    "ExpansionTile": "Expander", "PageView": "PageView", "DataTable": "Table",
}


def iter_files(root: Path):
    for directory, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for name in filenames:
            path = Path(directory) / name
            if path.suffix.lower() in UI_EXTENSIONS:
                yield path


def read_text(path: Path) -> str:
    try:
        # Minified bundles and generated dumps are not useful API evidence.
        if path.stat().st_size > 16_000:
            return ""
        raw = path.read_bytes()
        if b"\x00" in raw[:8192]:
            return ""
        return raw.decode("utf-8", errors="ignore")
    except OSError:
        return ""


def prototypes(text: str, suffix: str):
    out = []
    for line in text.splitlines():
        if len(line) > 10_000:
            continue
        if re.match(r"^\s*(?:if|for|while|switch|catch|return|throw)\b", line):
            continue
        match = None
        if suffix == ".py":
            match = PY_DEF.match(line)
        elif suffix == ".rs":
            match = RUST_DEF.match(line)
        elif suffix == ".go":
            match = GO_DEF.match(line)
        elif suffix == ".pas":
            match = PASCAL_DEF.match(line)
        elif suffix in {".js", ".jsx", ".mjs", ".ts", ".tsx", ".vue"}:
            match = JS_DEF.match(line)
        else:
            match = TYPED_DEF.match(line)
        if match:
            groups = [g for g in match.groups() if g is not None]
            if len(groups) >= 2:
                out.append(f"{groups[0]}({groups[1].strip()})")
    return out


def ui_names(text: str, suffix: str):
    names = set()
    low = text.lower()
    if suffix in {".tsx", ".jsx", ".vue", ".html", ".xaml", ".xml", ".dfm", ".fmx", ".lfm", ".ui"}:
        names.update(REACT_TAG.findall(text))
        names.update(HTML_TAG.findall(text))
        names.update(VCL_OBJECT.findall(text))
        names.update(XAML_CLASS.findall(text))
    if ((suffix == ".dart" and "package:flutter" in low)
            or (suffix == ".swift" and "import swiftui" in low)
            or (suffix in {".kt", ".java"} and ("androidx.compose" in low or "android.view" in low))):
        names.update(CALL_NAME.findall(text))
    if suffix in {".cpp", ".cc", ".h", ".hpp"} and ("#include <q" in low or "gtk/" in low):
        names.update(QT_MEMBER.findall(text))
    if suffix == ".pas" and "vcl." in low:
        names.update(VCL_MEMBER.findall(text))
    return sorted(name for name in names if name not in COMMON_CALLS and len(name) > 1)


def frameworks(text: str, suffix: str):
    low = text.lower()
    found = set()
    signatures = {
        "Flutter": ("package:flutter", "flutter/"),
        "React": ("from 'react'", 'from "react"', "reactdom"),
        "SwiftUI": ("import swiftui", "some view"),
        "VCL": ("vcl.",),
        "Qt": ("#include <qt", "qwidget", "qapplication"),
        "GTK": ("gtk_", "gtk/gtk.h", "gtk4"),
        "Android": ("androidx.", "android.view", "android.app"),
        "Web": ("<html", "document.", "window.", "vite", "next/"),
    }
    for name, needles in signatures.items():
        if any(needle in low for needle in needles):
            found.add(name)
    if suffix in {".pas", ".dfm", ".fmx", ".lfm"}:
        found.add("Pascal/VCL-like")
    return sorted(found)


def neper_catalogue(neper_root: Path):
    modules = json.loads((neper_root / "docs/modules.json").read_text(encoding="utf-8"))
    surfaces = {item["name"]: item["surface"] for item in modules["modules"]}
    api_text = (neper_root / "docs/module-apis.md").read_text(encoding="utf-8")
    api_names = set(re.findall(r"^\s*(?:fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)", api_text, re.M))
    widget_plan = json.loads((neper_root / "docs/widget-plan.json").read_text(encoding="utf-8"))
    widgets = {}
    for phase in widget_plan["phases"]:
        for item in phase["items"]:
            for name in item["components"]:
                widgets[name] = {"phase": phase["id"], "delivered": name in item["delivered"]}
    return surfaces, api_names, widgets


def coverage(name: str, surfaces, api_names, widgets):
    canonical = ALIASES.get(name, name)
    if canonical in widgets:
        entry = widgets[canonical]
        return "implemented" if entry["delivered"] else f"planned {entry['phase']}"
    if canonical in api_names:
        return f"module API ({surfaces.get(canonical, 'planned')})"
    return "missing/extension"


def audit(root: Path, neper_root: Path):
    surfaces, api_names, widgets = neper_catalogue(neper_root)
    repos = {}
    for repo in sorted(p for p in root.iterdir() if p.is_dir()):
        if repo.name in SKIP_ROOTS or repo.name.startswith(SKIP_ROOT_PREFIXES):
            continue
        files = list(iter_files(repo))
        if not files:
            continue
        print(f"scanning {repo.name} ({len(files)} files)", flush=True)
        function_names = []
        ui = set()
        fw = set()
        ext_counts = Counter()
        prototypes_by_file = defaultdict(list)
        for path in files:
            text = read_text(path)
            if not text:
                continue
            ext = path.suffix.lower()
            ext_counts[ext] += 1
            found = prototypes(text, ext)
            function_names.extend(found)
            if found:
                prototypes_by_file[str(path.relative_to(repo))] = found
            ui.update(ui_names(text, ext))
            fw.update(frameworks(text, ext))
        ui = sorted(ui)
        repos[repo.name] = {
            "files": sum(ext_counts.values()),
            "extensions": dict(sorted(ext_counts.items())),
            "frameworks": sorted(fw),
            "prototype_count": len(function_names),
            "prototype_names": sorted(set(function_names)),
            "prototypes_by_file": dict(prototypes_by_file),
            "ui_names": ui,
            "ui_coverage": Counter(coverage(name, surfaces, api_names, widgets) for name in ui),
        }
    return repos


def write_report(report_path: Path, inventory_path: Path, repos, surfaces, api_names, widgets):
    inventory_path.write_text(json.dumps(repos, indent=2, sort_keys=True), encoding="utf-8")
    total_files = sum(item["files"] for item in repos.values())
    total_protos = sum(item["prototype_count"] for item in repos.values())
    all_ui = sorted({name for item in repos.values() for name in item["ui_names"]})
    covered = Counter()
    for item in repos.values():
        covered.update(item["ui_coverage"])
    lines = [
        "# Repository rewrite coverage verification",
        "",
        "Generated by `scripts/audit_repo_coverage.py` from `D:\\repos`.",
        "This is a capability inventory, not a claim that Neper can currently build these apps.",
        "Generated/vendor trees, assets and duplicate `neper-*` worktrees are excluded.",
        "Individual files larger than 16 KiB are counted but omitted from text extraction as likely generated/minified artifacts.",
        "",
        f"Scope: **{len(repos)} repositories**, **{total_files:,} source/UI files**, "
        f"**{total_protos:,} extracted function/procedure prototypes**, and "
        f"**{len(all_ui):,} unique UI/type names**.",
        "",
        "## Conclusion",
        "",
        "No repository is currently verified as a complete Neper rewrite. The exact-name "
        "comparison finds planned coverage for common controls, but most application UI "
        "names are app-specific or framework-specific, and function prototypes still need "
        "signature-by-signature porting and behavioral tests.",
        "",
        "## Verification checklist",
        "",
        "- [ ] Map every extracted prototype to a Neper module declaration and preserve its error, ownership and async behavior.",
        "- [ ] Map every UI/type name to a delivered Neper widget, an explicit alias, or a reviewed extension package.",
        "- [ ] Verify OS services: file access, clipboard, cross-application drag/drop, sharing, activation, notifications, tray and lifecycle.",
        "- [ ] Re-run application behavior, accessibility, persistence, packaging and platform integration tests after the mapping is complete.",
        "",
        "## Verification status",
        "",
        "`implemented` means an exact widget-plan component is delivered. `planned Pn` "
        "means it exists in the Neper plan but is not delivered. `module API` means a "
        "matching public declaration exists in the module catalogue. `missing/extension` "
        "requires a new API, an adapter, or an application-specific package.",
        "",
        "| Status | UI/type occurrences |",
        "| --- | ---: |",
    ]
    for status, count in sorted(covered.items()):
        lines.append(f"| `{status}` | {count:,} |")
    lines += [
        "",
        "## Repository inventory",
        "",
        "| Repository | Files | Prototypes | UI/type names | Frameworks |",
        "| --- | ---: | ---: | ---: | --- |",
    ]
    for name, item in sorted(repos.items(), key=lambda pair: (-pair[1]["files"], pair[0])):
        lines.append(f"| `{name}` | {item['files']:,} | {item['prototype_count']:,} | "
                     f"{len(item['ui_names']):,} | {', '.join(item['frameworks']) or 'unclassified'} |")
    lines += ["", "## Per-repository verification list", ""]
    for name, item in sorted(repos.items(), key=lambda pair: pair[0].lower()):
        lines += [f"### `{name}`", "", f"Frameworks: {', '.join(item['frameworks']) or 'unclassified'}.",
                  f"Extracted {item['prototype_count']:,} prototypes from {item['files']:,} files.", "",
                  "UI/type names and Neper status:", ""]
        for ui_name in item["ui_names"]:
            lines.append(f"- `{ui_name}` — {coverage(ui_name, surfaces, api_names, widgets)}")
        lines += ["", "The complete file-to-prototype extraction is retained in the JSON inventory "
                  "(`prototypes_by_file`), alongside the unique prototype-name set.", ""]
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(r"D:\repos"))
    parser.add_argument("--neper", type=Path, default=Path(r"D:\repos\neper"))
    parser.add_argument("--report", type=Path, default=Path(r"D:\repos\neper\docs\rewrite-coverage-verification.md"))
    parser.add_argument("--inventory", type=Path, default=Path(r"D:\repos\neper\docs\rewrite-coverage-inventory.json"))
    args = parser.parse_args()
    surfaces, api_names, widgets = neper_catalogue(args.neper)
    repos = audit(args.root, args.neper)
    write_report(args.report, args.inventory, repos, surfaces, api_names, widgets)
    print(f"audited {len(repos)} repositories; wrote {args.report} and {args.inventory}")


if __name__ == "__main__":
    main()
