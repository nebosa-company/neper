# -*- coding: utf-8 -*-
"""Malformed-manifest fixtures for scripts/ui_audit.py (T035): one case per check must fail
with that check's code and an actionable location; a clean manifest passes.
Run: python scripts/ui_audit_test.py"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "ui_audit.py"
failures = []

GOOD = {
    "resources": ["icons/save", "icons/open"],
    "references": [{"resource": "icons/save", "at": "app.e:10"}],
    "locales": {"en": {"save": "Save {name}", "count": "%d items"}, "de": {"save": "{name} speichern", "count": "%d Elemente"}},
    "commands": [
        {"id": "file.save", "label": "Save", "callback": "on_save", "menu": "file", "mnemonic": "S", "at": "cmds.e:3"},
        {"id": "file.open", "label": "Open", "callback": "on_open", "menu": "file", "mnemonic": "O", "at": "cmds.e:4"},
    ],
    "callbacks": ["on_save", "on_open"],
}


def run(manifest, raw=None):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "m.json"
        path.write_text(raw if raw is not None else json.dumps(manifest), encoding="utf-8")
        done = subprocess.run([sys.executable, str(TOOL), str(path)], capture_output=True, text=True)
        return done.returncode, done.stdout


def mutated(change):
    m = json.loads(json.dumps(GOOD))
    change(m)
    return m


def expect(name, code, manifest, raw=None, fragment=""):
    status, out = run(manifest, raw)
    if status != 1 or "[%s]" % code not in out or fragment not in out:
        failures.append("%s: wanted [%s] %s, got %d %r" % (name, code, fragment, status, out))


status, out = run(GOOD)
if status != 0 or "ui audit ok" not in out:
    failures.append("clean manifest: %d %r" % (status, out))
expect("unknown resource", "unknown-resource", mutated(lambda m: m["references"].append({"resource": "icons/nope", "at": "view.e:77"})), fragment="view.e:77")
expect("missing translation", "missing-translation", mutated(lambda m: m["locales"]["de"].pop("count")), fragment="'count'")
expect("extra translation", "extra-translation", mutated(lambda m: m["locales"]["de"].update({"stale": "x"})), fragment="'stale'")
expect("placeholder", "placeholder-mismatch", mutated(lambda m: m["locales"]["de"].update({"save": "speichern"})), fragment="'save'")
expect("duplicate command", "duplicate-command", mutated(lambda m: m["commands"].append(dict(m["commands"][0], at="cmds.e:9"))), fragment="cmds.e:9")
expect("missing callback", "missing-callback", mutated(lambda m: m["commands"][0].update({"callback": "on_missing"})), fragment="on_missing")
expect("mnemonic missing", "mnemonic-missing", mutated(lambda m: m["commands"][0].update({"mnemonic": "Z"})), fragment="'Z'")
expect("mnemonic conflict", "mnemonic-conflict", mutated(lambda m: m["commands"][1].update({"label": "Save as", "mnemonic": "s"})), fragment="file.open")
dup = '{"locales": {"en": {"a": "1", "a": "2"}}}'
expect("duplicate key", "duplicate-key", None, raw=dup, fragment="'a'")

if failures:
    print("ui_audit_test: %d failure(s)" % len(failures), file=sys.stderr)
    for f in failures:
        print("  " + f, file=sys.stderr)
    sys.exit(1)
print("ui audit fixtures ok")
