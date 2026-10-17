#!/usr/bin/env python3
"""List WPT CSS reftests for tests/browser/wpt/run.sh (browser tracker 9.2).

  python scripts/gen_wpt_manifest.py WPT_DIR OUT.txt subdir [subdir ...]

Writes `test | reference | match|mismatch` lines with paths relative to OUT's directory (put OUT in WPT_DIR). Skips tests that
use scripts, reftest-wait, fuzzy matching or more than one reference, and references that do not exist.
"""
import os, re, sys

def main():
    wpt, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    base = os.path.dirname(out)
    lines = []
    for sub in sys.argv[3:]:
        for dp, dn, fn in os.walk(os.path.join(wpt, sub)):
            dn.sort()
            if os.path.basename(dp) in ("reference", "support", "resources", "reftest"):
                pass
            for f in sorted(fn):
                if not re.search(r"\.(html|htm|xht|xhtml)$", f) or "-ref" in f or "-notref" in f:
                    continue
                path = os.path.join(dp, f)
                try:
                    text = open(path, encoding="utf8", errors="replace").read()
                except OSError:
                    continue
                links = re.findall(r"<link[^>]+rel=[\"'](match|mismatch)[\"'][^>]*>", text, re.I)
                if len(links) != 1:
                    continue
                if re.search(r"<script|reftest-wait|rel=[\"']?fuzzy|name=[\"']fuzzy|<meta[^>]+name=[\"']timeout|<object|<iframe|<video|<canvas", text, re.I):
                    continue
                m = re.search(r"<link[^>]+rel=[\"'](match|mismatch)[\"'][^>]*href=[\"']([^\"']+)[\"']", text, re.I) or re.search(r"<link[^>]+href=[\"']([^\"']+)[\"'][^>]*rel=[\"'](match|mismatch)[\"']", text, re.I)
                if not m:
                    continue
                if m.group(1) in ("match", "mismatch"):
                    kind, href = m.group(1), m.group(2)
                else:
                    href, kind = m.group(1), m.group(2)
                if href.startswith("http") or href.startswith("/"):
                    ref = os.path.normpath(os.path.join(wpt, href.lstrip("/")))
                else:
                    ref = os.path.normpath(os.path.join(dp, href.split("#")[0]))
                if not os.path.exists(ref):
                    continue
                lines.append(f"{os.path.relpath(path, base).replace(os.sep, '/')} | {os.path.relpath(ref, base).replace(os.sep, '/')} | {kind}")
    open(out, "w", encoding="utf8", newline="\n").write("\n".join(lines) + "\n")
    print(len(lines), "reftests")

main()
