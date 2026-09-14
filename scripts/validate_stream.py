# -*- coding: utf-8 -*-
"""Validate emitted v1 records against docs/schemas/neper-v1.schema.json.

Usage:  python scripts/validate_stream.py [PATH ...]

With no argument every committed golden is checked: the `.jsonl` streams under
tests/conformance (one record per line) and docs/modules.json (a whole document).
Each value is validated against the schema's top-level `oneOf`, so a stream
record, a source map, a build manifest, a module plan and a package manifest are
all accepted where they are what was emitted.  Exit 0 when every value validates,
1 otherwise, with the offending file, line and path named.
"""
import json, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import best_match
except ImportError:
    # The suites call this; a machine without the package should still run them.
    print("skipped: python package `jsonschema` is not installed")
    sys.exit(0)

VALIDATOR = Draft202012Validator(json.loads((ROOT / "docs/schemas/neper-v1.schema.json").read_text(encoding="utf-8")))

# A validator that accepts everything would pass every golden and prove nothing,
# so one record that must be rejected runs before the corpus does.
def self_check():
    bad = {"schema": "neper-stream", "version": 1, "record": "header", "command": "polish",
           "tool_version": "0", "language_version": "0", "grammar_revision": 1}
    if best_match(VALIDATOR.iter_errors(bad)) is None:
        print("invalid  self-check: the schema accepted a header with an unregistered command")
        sys.exit(1)


def check(value, where, failures):
    error = best_match(VALIDATOR.iter_errors(value))
    if error is not None:
        at = "/".join(str(p) for p in error.absolute_path) or "(root)"
        failures.append("%s: %s: %s" % (where, at, error.message))


def main(argv):
    self_check()
    targets = [pathlib.Path(a) for a in argv[1:]]
    if not targets:
        targets = sorted((ROOT / "tests/conformance").rglob("*.jsonl")) + [ROOT / "docs/modules.json"]
    failures, values = [], 0
    for target in targets:
        text = target.read_text(encoding="utf-8")
        try:
            where = target.relative_to(ROOT)
        except ValueError:
            where = target
        if target.suffix == ".jsonl":
            for number, line in enumerate(text.splitlines(), 1):
                if not line.strip():
                    continue
                values += 1
                try:
                    value = json.loads(line)
                except ValueError as bad:
                    failures.append("%s:%d: not JSON: %s" % (where, number, bad))
                    continue
                check(value, "%s:%d" % (where, number), failures)
        else:
            values += 1
            check(json.loads(text), str(where), failures)
    for failure in failures:
        print("invalid  " + failure)
    print("%d records checked in %d files, %d invalid" % (values, len(targets), len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
