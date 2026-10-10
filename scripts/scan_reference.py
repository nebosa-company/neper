# -*- coding: utf-8 -*-
"""Reference vectors for `x.lint.scan` and `e.fmt.mermaid` (L042): run petcow's own scan helpers and diagram emitter.

Usage:  python scripts/scan_reference.py REFERENCE_EXE

REFERENCE_EXE is a build of petcow's `scan.rs` (the parsers, `map_external`, `finding_id`, `merge_owned`,
`finding_to_value`, `inject_findings`), `findings.rs` types and `diagram.rs` `to_mermaid` over small shims (see
docs/petcow.md F2/F3); it reads one JSON case on stdin and writes one JSON answer. The script writes
tests/selfhost/fixtures/link/x_lint_scan/src/main.e from scripts/scan_fixture_template.e: one JSON line per case,
`{"op", ..., "e": answer}`.
"""
import json
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x42a7)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


RULES = ["CKV_AWS_18", "CKV_AWS_21", "PETCOW_S3_PUBLIC", "python.lang.security.audit", "R1", "R2", "x"]
DESCS = ["bucket logging", "versioning off", "desc with \"quote\"", "unicode é", "(none)", "a b c"]
SEVS = ["HIGH", "high", "Critical", "LOW", "moderate", "informational", "info", "medium", "bogus", "", " High ", None, 5]
HINTS = ["aws_s3_bucket.logs", "aws_vpc.main", "modules/net/main.tf", "logs", "x", ""]
BASES = ["logs", "main", "net", "web", "vpc"]
TOOLS = ["checkov (3.2.1)", "semgrep (1.0)", "petcow-native (0.1)", "petcow-native", "petcow-spartan (2)", "manual", "x (1) (2)"]
NOWS = ["2026-01-01T00:00:00Z", "2026-06-15T12:30:00Z"]
STATES = ["open", "accepted", "fixed", "false-positive"]


def checkov_check():
    c = {}
    if chance(0.9):
        c["check_id"] = pick(RULES)
    if chance(0.85):
        c["check_name"] = pick(DESCS)
    sev = pick(SEVS)
    if chance(0.8) and sev is not None:
        c["severity"] = sev
    if chance(0.6):
        c["resource"] = pick(HINTS)
    if chance(0.5):
        c["file_path"] = "/" + pick(HINTS)
    return c


def checkov_doc():
    r = rng.randrange(10)
    if r == 0:
        return pick(["", "null", "[]", "{}", "123", '"just a string"', "true", "not json {", "[1, 2, {\"results\": 5}]"])
    report = {"results": {"failed_checks": [checkov_check() for _ in range(rng.randrange(4))]}}
    if chance(0.2):
        report["results"]["passed_checks"] = [checkov_check()]
    if chance(0.15):
        report = {"results": {"failed_checks": "oops"}}
    if chance(0.15):
        report = {"results": [1]}
    if chance(0.3):
        return json.dumps([report, {"results": {"failed_checks": [checkov_check()]}}, 7])
    return json.dumps(report)


def semgrep_doc():
    r = rng.randrange(8)
    if r == 0:
        return pick(["", "null", "{}", "[]", "[1]", "42", "{\"results\": 3}"])
    results = []
    for _ in range(rng.randrange(4)):
        x = {}
        if chance(0.9):
            x["check_id"] = pick(RULES)
        if chance(0.85):
            x["path"] = pick(HINTS)
        if chance(0.9):
            e = {}
            if chance(0.8):
                e["message"] = pick(DESCS)
            if chance(0.8):
                e["severity"] = pick(["ERROR", "WARNING", "INFO", "error", "Warning", "other", 3])
            x["extra"] = e
        results.append(x)
    return json.dumps({"results": results})


def external():
    return {"rule": pick(RULES), "description": pick(DESCS), "severity": pick(["info", "low", "medium", "high", "critical"]), "hint": pick(HINTS)}


def reported(base):
    r = {"resource": base, "tool": pick(TOOLS), "rule": pick(RULES), "severity": pick(["info", "low", "medium", "high", "critical"]), "description": pick(DESCS)}
    if chance(0.4):
        r["solution"] = pick(["fix it", "use encryption"])
    return r


def finding(base, with_id=True):
    tool = pick(TOOLS)
    rule = pick(RULES)
    f = {"tool": tool, "state": pick(STATES), "severity": pick(["info", "low", "medium", "high", "critical"]), "description": pick(DESCS),
         "detection_time": pick(NOWS), "last_update": pick(NOWS)}
    if with_id and chance(0.8):
        f["id"] = pick(["", "abc"]) or "0123456789abcdef"
    if chance(0.8):
        f["rule"] = rule
    if chance(0.4):
        f["solution"] = "s"
    if chance(0.3):
        f["justification"] = "waiver"
    if chance(0.2):
        f["expires"] = "2027-01-01"
    return f


def case_checkov():
    return {"op": "checkov", "json": checkov_doc()}


def case_semgrep():
    return {"op": "semgrep", "json": semgrep_doc()}


def case_map():
    return {"op": "map", "results": [external() for _ in range(rng.randrange(5))], "tool": pick(TOOLS), "bases": [pick(BASES) for _ in range(rng.randrange(4))]}


def case_id():
    return {"op": "id", "resource": pick(BASES + ["a b", "é"]), "tool": pick(TOOLS), "rule": pick(RULES)}


def case_merge():
    base = pick(BASES)
    reps = [reported(base) for _ in range(rng.randrange(4))]
    existing = []
    # make some existing findings match the reported ids by building them from the reference's own ids afterwards
    for _ in range(rng.randrange(4)):
        existing.append(finding(base))
    return {"op": "merge", "base": base, "existing": existing, "reported": reps, "now": pick(NOWS), "owner": pick(["petcow-native", "petcow-spartan", "checkov"]), "_match": chance(0.7)}


def case_inject():
    names = ["logs", "vpc", "web"]
    lines = ["project: demo", "resources:"]
    for n in names:
        lines.append("  %s:" % n)
        lines.append("    type: aws.s3")
        if chance(0.3):
            lines.append("    findings: []")
    if chance(0.5):
        lines.append("unmanaged:")
        for n in ("legacy", "old"):
            lines.append("  - type: aws.s3")
            lines.append("    name: %s" % n)
            lines.append("    public: true")
    doc = "\n".join(lines) + "\n"
    if chance(0.08):
        doc = pick(["project: x\n", "[1, 2]\n", "resources: 5\n", ": : :\n"])
    managed = {}
    for n in rng.sample(names + ["ghost"], rng.randrange(0, 4)):
        managed[n] = [finding(n) for _ in range(rng.randrange(0, 3))]
    unmanaged = {}
    for n in rng.sample(["legacy", "old", "nope"], rng.randrange(0, 3)):
        unmanaged[n] = [finding(n) for _ in range(rng.randrange(0, 3))]
    return {"op": "inject", "doc": doc, "managed": dict(sorted(managed.items())), "unmanaged": dict(sorted(unmanaged.items()))}


def case_mermaid():
    n = rng.randrange(0, 6)
    ids = []
    insts = []
    for i in range(n):
        base = pick(["vpc", "subnet", "app", 'q"uote', "db"])
        lid = base if chance(0.6) else "%s[%d]" % (base, rng.randrange(3))
        ids.append(lid)
        insts.append({"logical_id": lid, "type": pick(["aws.vpc", "aws.subnet", "aws.x"]), "depends_on": [], "blocking": chance(0.3)})
    for inst in insts:
        for _ in range(rng.randrange(3)):
            inst["depends_on"].append(pick(["vpc", "subnet", "app", "db", "missing", 'q"uote']))
    return {"op": "mermaid", "project": pick(["demo", "my\nproject", "", "p\"q"]), "instances": insts}


def run(exe, case):
    payload = {k: v for k, v in case.items() if not k.startswith("_")}
    r = subprocess.run([exe], input=json.dumps(payload), capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        raise SystemExit("reference failed on %r: %s" % (payload, r.stderr[:300]))
    return json.loads(r.stdout)


def fix_matching(exe, case):
    """Give some existing findings the id of a reported one, so the merge's matched branch runs."""
    if not case.get("_match") or not case["reported"] or not case["existing"]:
        return
    for rep, ex in zip(case["reported"], case["existing"]):
        out = run(exe, {"op": "id", "resource": case["base"], "tool": rep["tool"], "rule": rep["rule"]})
        ex["id"] = out["id"]
        if chance(0.5):
            ex["tool"] = rep["tool"]
            ex["rule"] = rep["rule"]


def main(argv):
    exe = argv[1]
    cases = []
    for _ in range(120):
        cases.append(case_checkov())
    for _ in range(90):
        cases.append(case_semgrep())
    for _ in range(60):
        cases.append(case_map())
    for _ in range(30):
        cases.append(case_id())
    for _ in range(150):
        c = case_merge()
        fix_matching(exe, c)
        cases.append(c)
    for _ in range(100):
        cases.append(case_inject())
    for _ in range(60):
        cases.append(case_mermaid())
    lines = []
    for c in cases:
        e = run(exe, c)
        payload = {k: v for k, v in c.items() if not k.startswith("_")}
        payload["e"] = e
        lines.append(json.dumps(payload, ensure_ascii=True, sort_keys=True))
    chunks = []
    size = 10
    for i in range(0, len(lines), size):
        body = "\n".join(lines[i:i + size]) + "\n"
        chunks.append('"%s"' % body.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    with open(os.path.join(ROOT, "scripts", "scan_fixture_template.e"), encoding="utf-8") as f:
        template = f.read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_lint_scan", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    errs = sum(1 for c in cases if False)
    print("%d cases in %d chunks -> x_lint_scan" % (len(cases), len(chunks)))


if __name__ == "__main__":
    main(sys.argv)
