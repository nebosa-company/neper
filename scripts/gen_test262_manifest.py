#!/usr/bin/env python3
"""List test262 scripts for the Neper JavaScript runners (browser tracker 5.14).

  python scripts/gen_test262_manifest.py TEST262_DIR OUT.txt [subdir ...]

Each line is `path | expect | strict | includes`: expect is `ok` or `parse` (a negative test with phase parse), `runtime:Type`
for a negative runtime test, strict is 1 for onlyStrict, 0 otherwise; module, async and raw-flagged tests are skipped. Paths are
relative to TEST262_DIR; includes are the harness files the test needs, comma separated.
"""
import os, re, sys

def main():
    root, out = sys.argv[1], sys.argv[2]
    subs = sys.argv[3:] or ["test"]
    lines = []
    for sub in subs:
        for dp, dn, fn in os.walk(os.path.join(root, sub)):
            dn.sort()
            for f in sorted(fn):
                if not f.endswith(".js") or "_FIXTURE" in f:
                    continue
                path = os.path.join(dp, f)
                text = open(path, encoding="utf8", errors="replace").read()
                m = re.search(r"/\*---(.*?)---\*/", text, re.S)
                meta = m.group(1) if m else ""
                flags = re.search(r"flags:\s*\[(.*?)\]", meta)
                flagset = [x.strip() for x in flags.group(1).split(",")] if flags else []
                if "module" in flagset or "async" in flagset or "raw" in flagset:
                    continue
                expect = "ok"
                neg = re.search(r"negative:\s*\n\s*phase:\s*(\w+)\s*\n\s*type:\s*(\w+)", meta)
                if neg:
                    expect = "parse" if neg.group(1) == "parse" else "runtime:" + neg.group(2)
                inc = re.search(r"includes:\s*\[(.*?)\]", meta, re.S)
                includes = [x.strip() for x in inc.group(1).split(",")] if inc else []
                rel = os.path.relpath(path, root).replace("\\", "/")
                strict = 1 if "onlyStrict" in flagset else 0
                lines.append(f"{rel} | {expect} | {strict} | {','.join(includes)}")
    open(out, "w", encoding="utf8", newline="\n").write("\n".join(lines) + "\n")
    print(len(lines), "tests")

main()
