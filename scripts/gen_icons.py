#!/usr/bin/env python3
# Embeds the SVG icons under neperos/assets/icons into neperos/src/icons.e as string constants, since
# NeperOS programs have no filesystem to read assets from. Each file is minified to one line and its
# double quotes become single quotes (e.gfx.svg reads either), so the result needs no escapes.
# Run after editing an icon:  python scripts/gen_icons.py
import os
import re

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
assets = os.path.join(root, "neperos", "assets", "icons")
out_path = os.path.join(root, "neperos", "src", "icons.e")


# The launcher's grid order (four columns, so five rows of four); files not listed follow, sorted.
APP_ORDER = ["phone", "messages", "mail", "browser", "camera", "gallery", "maps", "compass", "clock", "calculator", "tasks", "files", "chat", "meet", "recorder", "translate", "steps", "lunatris", "mfa", "settings"]


# The name each app shows under its icon (the file name where it is not the right word).
LABELS = {"gallery": "Photos", "mfa": "Secure"}


def load(kind):
    items = []
    folder = os.path.join(assets, kind)
    names = sorted(n for n in os.listdir(folder) if n.endswith(".svg"))
    if kind == "apps":
        names.sort(key=lambda n: (APP_ORDER.index(n[:-4]) if n[:-4] in APP_ORDER else len(APP_ORDER), n))
    for name in names:
        text = open(os.path.join(folder, name), encoding="utf-8").read()
        text = re.sub(r"\s+", " ", text).strip().replace("> <", "><").replace('"', "'")
        assert "\\" not in text
        items.append((name[:-4], text))
    return items


lines = [
    "// The NeperOS icon set, embedded from neperos/assets/icons by scripts/gen_icons.py (D2200).",
    "// Do not edit by hand: change the .svg files and run the script. Each constant is one minified",
    "// SVG document for e.gfx.svg; app icons are 96x96 rounded tiles, top-bar glyphs are 24x24 and",
    "// draw in `currentColor`.",
    "",
]
for kind, prefix in (("apps", "APP"), ("topbar", "BAR")):
    items = load(kind)
    for name, text in items:
        # A module-scope `const X: str` does not type-check here, so each document is a function.
        lines.append('fn %s_%s() -> str { ret "%s" }' % (prefix.lower(), name, text))
    lines.append("")
    lines.append("const %s_COUNT: usize = %dusize" % (prefix, len(items)))
    lines.append("")
    lines.append("fn %s(index: usize) -> str {" % kind[:-1] if kind == "apps" else "fn bar(index: usize) -> str {")
    for i, (name, _) in enumerate(items):
        lines.append("    if index == %dusize { ret %s_%s() }" % (i, prefix.lower(), name))
    lines.append('    ret ""')
    lines.append("}")
    lines.append("")
    lines.append("fn %s_name(index: usize) -> str {" % ("app" if kind == "apps" else "bar"))
    for i, (name, _) in enumerate(items):
        lines.append('    if index == %dusize { ret "%s" }' % (i, name))
    lines.append('    ret ""')
    lines.append("}")
    lines.append("")
    if kind == "apps":
        lines.append("fn app_label(index: usize) -> str {")
        for i, (name, _) in enumerate(items):
            lines.append('    if index == %dusize { ret "%s" }' % (i, LABELS.get(name, name.capitalize())))
        lines.append('    ret ""')
        lines.append("}")
        lines.append("")
open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("wrote", out_path, len(lines), "lines")
