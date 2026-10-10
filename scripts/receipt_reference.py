# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.receipt` (T042): parse verification receipts and judge them against their contract.

Usage:  python scripts/receipt_reference.py

Writes tests/selfhost/fixtures/link/x_agent_receipt/src/main.e from scripts/receipt_fixture_template.e. Contracts are
validated and hashed by scripts/contract_reference.py's independent reference; the receipt rules are the module
header's, written independently. Precedence: unbound > unsafe > unhermetic > failed > incomplete > verified.
"""
import hashlib
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import contract_reference as cr  # noqa: E402

rng = random.Random(0x7035)
KINDS = {"test", "check", "build", "diff"}
RANK = {"hermetic": 0, "observed": 1, "uncontrolled": 2}


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def hexs():
    return "".join(pick("0123456789abcdef") for _ in range(64))


def parse_receipt(text):
    def refuse(c):
        raise ValueError(c)
    try:
        doc = json.loads(text, object_pairs_hook=cr.pairs_hook, parse_int=cr.Lexeme, parse_float=cr.Lexeme, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    if cr.depth(doc) > 6 or not cr.only_integers(doc) or not isinstance(doc, dict) or len(doc) != 8:
        return None
    if doc.get("schema") != "neper-receipt" or not (isinstance(doc.get("version"), cr.Lexeme) and doc["version"] == "1"):
        return None
    for k in ("contract", "environment", "policy", "bundle"):
        if not cr.hex_ok(doc.get(k)):
            return None
    if not cr.is_text(doc.get("snapshot")) or doc["snapshot"] == "":
        return None
    results = doc.get("results")
    if not isinstance(results, list):
        return None
    seen = {}
    for r in results:
        if not isinstance(r, dict) or set(r) != {"id", "outcome", "evidence"}:
            return None
        if not all(cr.is_text(r[k]) for k in r) or r["id"] == "" or r["id"] in seen:
            return None
        if r["outcome"] not in ("pass", "fail", "not-run") or r["evidence"] not in ("executed", "cached", "none"):
            return None
        if (r["outcome"] == "not-run") != (r["evidence"] == "none"):
            return None
        seen[r["id"]] = r
    canonical = json.dumps(cr.unwrap(doc), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest(), doc["contract"], seen


def verify(contract_text, receipt_text, env_level, required, audit):
    ref = cr.reference(contract_text)
    rec = parse_receipt(receipt_text)
    if ref is None or rec is None:
        return "error"
    chash, verdict, _required_count, _canonical, _pred = ref
    _rhash, receipt_contract, results = rec
    cdoc = json.loads(contract_text)
    obligations = cdoc["obligations"]
    fresh = sum(1 for o in obligations if o["disposition"] == "required"
                and o["id"] in results and results[o["id"]]["evidence"] == "executed")
    if chash != receipt_contract:
        return "unbound %d" % fresh
    if audit != "verified":
        return "unsafe %d" % fresh
    if RANK.get(env_level, 2) > RANK.get(required, 2):
        return "unhermetic %d" % fresh
    incomplete = verdict == "incomplete"
    for o in obligations:
        if o["disposition"] != "required":
            continue
        r = results.get(o["id"])
        if r is None:
            incomplete = True
        elif r["outcome"] == "fail":
            return "failed %d" % fresh
        elif r["outcome"] == "not-run":
            incomplete = True
    return ("incomplete %d" if incomplete else "verified %d") % fresh


def good_receipt(contract_doc, chash):
    results = []
    for o in contract_doc["obligations"]:
        if chance(0.12):
            continue
        outcome = pick(["pass", "pass", "pass", "fail", "not-run"])
        evidence = "none" if outcome == "not-run" else pick(["executed", "executed", "cached"])
        results.append({"id": o["id"], "outcome": outcome, "evidence": evidence})
    if chance(0.2):
        results.append({"id": "stray-" + str(rng.randrange(9)), "outcome": "pass", "evidence": "executed"})
    return {"schema": "neper-receipt", "version": 1, "contract": chash, "environment": hexs(), "policy": hexs(),
            "bundle": hexs(), "snapshot": "snap-" + str(rng.randrange(50)), "results": results}


def damage(rc):
    rc = json.loads(json.dumps(rc))
    r = rng.randrange(8)
    if r == 0:
        rc["extra"] = 1
    elif r == 1:
        del rc[pick(["contract", "environment", "policy", "bundle", "snapshot", "results"])]
    elif r == 2:
        rc["contract"] = pick(["abc", "", 3])
    elif r == 3 and rc["results"]:
        rc["results"][0]["outcome"] = pick(["maybe", "PASS", ""])
    elif r == 4 and rc["results"]:
        rc["results"][0]["evidence"] = pick(["executed", "none"]) if rc["results"][0]["outcome"] == "not-run" else "none"
    elif r == 5 and rc["results"]:
        rc["results"].append(dict(rc["results"][0]))
    elif r == 6:
        rc["version"] = 2
    else:
        rc["schema"] = "neper-receipt-x"
    return rc


def render(doc):
    return json.dumps(doc, ensure_ascii=chance(0.5), indent=pick([None, 2]), separators=pick([None, (",", ":")]))


def main():
    cases = []
    rdocs = []
    base = []
    for _ in range(90):
        c = cr.good_contract()
        if chance(0.6):
            # most contracts should be complete: keep required obligations supported
            for o in c["obligations"]:
                if o["disposition"] == "required":
                    o["kind"] = pick(["test", "check", "build", "diff"])
                    o["expect"] = pick(["pass", "exit 0"])
        ctext = cr.render(c)
        ref = cr.reference(ctext)
        if ref is None:
            continue
        base.append((c, ctext, ref[0]))
    for c, ctext, chash in base:
        rdoc = good_receipt(c, chash)
        rtext = render(rdoc)
        r = parse_receipt(rtext)
        cases.append({"k": "parse", "a": rtext, "b": "", "c": "", "d": "", "e": "error" if r is None else r[0]})
        for _ in range(3):
            level = pick(["hermetic", "observed", "uncontrolled"])
            required = pick(["hermetic", "observed", "uncontrolled"])
            audit = pick(["verified", "verified", "verified", "violation", "undeclared", "unapproved", "unenforced"])
            use = rdoc
            mode = rng.randrange(6)
            if mode == 0:
                use = json.loads(json.dumps(rdoc))
                use["contract"] = hexs()
            elif mode == 1:
                use = damage(rdoc)
            if mode >= 2 and chance(0.5):
                # a clean pass: every required obligation executed and passed
                use = json.loads(json.dumps(rdoc))
                use["results"] = [{"id": o["id"], "outcome": "pass", "evidence": pick(["executed", "cached"])}
                                  for o in c["obligations"]]
                level, required, audit = "hermetic", "hermetic", "verified"
            rt = render(use)
            cases.append({"k": "verify", "a": ctext, "b": rt, "c": level, "d": required + "\n" + audit,
                          "e": verify(ctext, rt, level, required, audit)})
    for t in ["", "{", "[]", "{}"]:
        cases.append({"k": "parse", "a": t, "b": "", "c": "", "d": "", "e": "error"})
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    for i in range(0, len(lines), 6):
        text = "\n".join(lines[i:i + 6]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "receipt_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_receipt", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    verdicts = {}
    for c in cases:
        if c["k"] == "verify":
            v = c["e"].split(" ")[0]
            verdicts[v] = verdicts.get(v, 0) + 1
    print("%d cases %s in %d chunks -> x_agent_receipt" % (len(cases), verdicts, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
