# -*- coding: utf-8 -*-
"""Fixtures for scripts/source_metrics.py (T033): string/comment handling, ignore, binary,
encoding, symlink and bound policies, deterministic order, snapshot comparison and the
report not counting itself. Run: python scripts/source_metrics_test.py"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "source_metrics.py"
failures = []


def check(name, condition, detail=""):
    if not condition:
        failures.append("%s %s" % (name, detail))


def run(*args):
    done = subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True)
    return done.returncode, done.stdout, done.stderr


def write(root, rel, data):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "proj"
    # Neper: a comment marker inside a string is code; a trailing comment keeps the line code.
    write(root, "src/a.e", 'fn main() -> err {\n    let s = "// not a comment"\n    // a comment\n\n    ret ok // trailing\n}\n')
    # C: block comments across lines, a code line opening a block.
    write(root, "src/b.c", "/* one\n two */\nint x; /* open\nstill */\n\nint y;\n")
    # Python: # in a string is code; CRLF endings count the same.
    write(root, "tools/c.py", 'x = "# not a comment"\r\n# comment\r\n\r\ny = 1\r\n')
    # Markdown is heuristic: every non-blank line is code.
    write(root, "README.md", "# title\n\ntext\n")
    # Binary and unknown files are skipped, latin-1 is decoded and listed.
    write(root, "bin/data.e", b"fn\x00\x00")
    write(root, "src/latin.e", b"// caf\xe9\nfn main() -> err { ret ok }\n")
    write(root, "notes.xyz", "ignored\n")
    # Skipped directories and ignore globs.
    write(root, "node_modules/x.js", "var a;\n")
    write(root, "docs/tasks/t.md", "nope\n")
    write(root, "gen/out.e", "fn g() -> err { ret ok }\n")
    # A symlink is not followed (skipped where the host cannot make one).
    try:
        os.symlink(root / "src" / "a.e", root / "src" / "link.e")
    except (OSError, NotImplementedError):
        pass

    code, out, err = run(str(root), "--json", "--ignore", "gen/*")
    check("exit", code == 0, err)
    report = json.loads(out)
    langs = report["languages"]
    check("languages sorted", list(langs) == sorted(langs), list(langs))
    check("neper string vs comment", langs["Neper"]["code"] == 5 and langs["Neper"]["comment"] == 2 and langs["Neper"]["blank"] == 1, langs["Neper"])
    check("neper files", langs["Neper"]["files"] == 2, langs["Neper"])
    check("c block comments", (langs["C"]["code"], langs["C"]["comment"], langs["C"]["blank"]) == (2, 3, 1), langs["C"])
    check("python crlf", (langs["Python"]["code"], langs["Python"]["comment"], langs["Python"]["blank"]) == (2, 1, 1), langs["Python"])
    check("markdown heuristic", langs["Markdown"]["heuristic"] and langs["Markdown"]["code"] == 2, langs["Markdown"])
    check("binary skipped", report["notes"]["binary"] == 1, report["notes"])
    check("latin1 listed", report["notes"]["decoded_as_latin1"] == ["src/latin.e"], report["notes"])
    check("unknown counted", report["notes"]["unknown_language"] == 1, report["notes"])
    check("ignore counted", report["skipped"]["ignored"] == 1, report["skipped"])
    check("node_modules and docs/tasks skipped", "JavaScript" not in langs, list(langs))

    # Bounds are reported, not silent.
    code, out, err = run(str(root), "--json", "--max-files", "2")
    bounded = json.loads(out)
    check("max-files reported", bounded["skipped"]["max_files"] > 0, bounded["skipped"])
    code, out, err = run(str(root), "--json", "--max-bytes", "10")
    check("max-bytes reported", json.loads(out)["notes"]["too_large"] > 0)

    # Snapshot, then a change, then the delta; the snapshot inside ROOT is not counted.
    snap = root / "source-metrics.json"
    code, out, err = run(str(root), "--snapshot", str(snap))
    check("snapshot written", snap.exists(), err)
    before = json.loads(snap.read_text(encoding="utf-8"))
    write(root, "src/new.e", "fn a() -> err { ret ok }\nfn b() -> err { ret ok }\n")
    code, out, err = run(str(root), "--compare", str(snap), "--json")
    after = json.loads(out)
    check("delta code", after["delta"]["code"] == 2 and after["delta"]["files"] == 1, after.get("delta"))
    check("report does not count itself", "JSON" not in after["languages"], list(after["languages"]))
    code, out, err = run(str(root), "--compare", str(snap))
    check("human delta", "+2 code" in out and "heuristic" in out, out)
    # Same tree twice is byte-identical.
    check("deterministic", run(str(root), "--json")[1] == run(str(root), "--json")[1])
    # A missing snapshot is a clear error, not a traceback.
    code, out, err = run(str(root), "--compare", str(root / "missing.json"))
    check("missing snapshot", code == 2 and "cannot read snapshot" in err, err)

if failures:
    print("source_metrics_test: %d failure(s)" % len(failures), file=sys.stderr)
    for f in failures:
        print("  " + f, file=sys.stderr)
    sys.exit(1)
print("source metrics ok")
