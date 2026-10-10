# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.contract` (T042, H35): validate, canonicalize and hash random change contracts.

Usage:  python scripts/contract_reference.py

Writes tests/selfhost/fixtures/link/x_agent_contract/src/main.e from scripts/contract_fixture_template.e. The
validation is the spec's (H35) written independently of the Neper module; the canonical form is
`json.dumps(sort_keys=True, separators=(",", ":"), ensure_ascii=False)` and the hash its UTF-8 SHA-256.
"""
import hashlib
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7042)


class Lexeme(str):
    pass


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


TOP = {"schema", "version", "base", "objective", "provenance", "scope", "obligations", "tier", "predecessor"}
KINDS = {"test", "check", "build", "diff"}


def only_integers(v):
    if isinstance(v, Lexeme):
        return re.fullmatch(r"-?[0-9]+", v) is not None and v != "-0"
    if isinstance(v, dict):
        return all(only_integers(x) for x in v.values())
    if isinstance(v, list):
        return all(only_integers(x) for x in v)
    return True


def unwrap(v):
    if isinstance(v, Lexeme):
        return int(v)
    if isinstance(v, dict):
        return {k: unwrap(x) for k, x in v.items()}
    if isinstance(v, list):
        return [unwrap(x) for x in v]
    return v


def depth(v):
    if isinstance(v, dict):
        return 1 + max([depth(x) for x in v.values()] + [0])
    if isinstance(v, list):
        return 1 + max([depth(x) for x in v] + [0])
    return 0


def is_text(v):
    return type(v) is str


def hex_ok(v):
    return is_text(v) and re.fullmatch(r"[0-9a-f]{64}", v) is not None


def pairs_hook(pairs):
    keys = [k for k, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate")
    return dict(pairs)


def reference(text):
    """None, or (hash, verdict, required, canonical, predecessor-or-None)."""
    def refuse(c):
        raise ValueError(c)
    try:
        doc = json.loads(text, object_pairs_hook=pairs_hook, parse_int=Lexeme, parse_float=Lexeme, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    if depth(doc) > 16:
        return None
    if not isinstance(doc, dict) or not set(doc) <= TOP:
        return None
    if doc.get("schema") != "neper-change-contract":
        return None
    if not (isinstance(doc.get("version"), Lexeme) and doc["version"] == "1"):
        return None
    base = doc.get("base")
    if not is_text(base) or base == "":
        return None
    if not is_text(doc.get("objective")) or not isinstance(doc.get("provenance"), dict):
        return None
    if doc.get("tier") not in ("fast", "affected", "full"):
        return None
    scope = doc.get("scope")
    if not isinstance(scope, dict) or set(scope) != {"permit", "forbid"}:
        return None
    for k in ("permit", "forbid"):
        if not isinstance(scope[k], list) or not all(is_text(x) for x in scope[k]):
            return None
    obligations = doc.get("obligations")
    if not isinstance(obligations, list):
        return None
    seen = set()
    required = 0
    complete = True
    for o in obligations:
        if not isinstance(o, dict) or set(o) != {"id", "kind", "expect", "disposition"}:
            return None
        if not all(is_text(o[k]) for k in o) or o["id"] == "" or o["id"] in seen:
            return None
        if o["disposition"] not in ("required", "advisory"):
            return None
        seen.add(o["id"])
        if o["disposition"] == "required":
            required += 1
            if o["kind"] not in KINDS or o["expect"] == "":
                complete = False
    predecessor = None
    if "predecessor" in doc:
        p = doc["predecessor"]
        if not is_text(p) or re.fullmatch(r"[0-9a-f]{64}", p) is None:
            return None
        predecessor = p
    if not only_integers(doc):
        return None
    canonical = json.dumps(unwrap(doc), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return digest, "complete" if complete else "incomplete", required, canonical, predecessor


WORDS = ["fix the flaky retry", "ünïcode — tést", "tab\there", 'quote "x" and \\ slash', "line\nbreak", "ctl\x01\x1f", "δ", ""]
IDS = ["t1", "t2", "build", "compat", "scope-ok", "a b"]


def good_contract():
    c = {
        "schema": "neper-change-contract",
        "version": 1,
        "base": pick(["snap-1", "sha256:" + "a" * 64, "ünï"]),
        "objective": pick(WORDS),
        "provenance": pick([{}, {"author": "agent", "turn": 4}, {"nested": {"a": [1, 2, {"b": None}], "z": True}}]),
        "scope": {"permit": [pick(["src", "lib/e/x", "tests/**"]) for _ in range(rng.randrange(0, 3))],
                  "forbid": [pick(["docs", "build"]) for _ in range(rng.randrange(0, 2))]},
        "obligations": [],
        "tier": pick(["fast", "affected", "full"]),
    }
    ids = IDS[:]
    rng.shuffle(ids)
    for i in range(rng.randrange(0, 4)):
        c["obligations"].append({
            "id": ids[i],
            "kind": pick(["test", "check", "build", "diff", "test", "review", "prose"]),
            "expect": pick(["pass", "exit 0", "no change", "", "fail:E-TYPE"]),
            "disposition": pick(["required", "required", "advisory"]),
        })
    if chance(0.3):
        c["predecessor"] = "".join(pick("0123456789abcdef") for _ in range(64))
    return c


def damage(c):
    c = json.loads(json.dumps(c))
    r = rng.randrange(16)
    if r == 0:
        c["surprise"] = 1
    elif r == 1:
        del c[pick(["schema", "base", "objective", "provenance", "scope", "obligations", "tier", "version"])]
    elif r == 2:
        c["version"] = pick([2, "1", 1.0, 0])
    elif r == 3:
        c["tier"] = pick(["slow", "", 3])
    elif r == 4:
        c["scope"] = pick([{"permit": []}, {"permit": [], "forbid": [], "x": 1}, [], "src"])
    elif r == 5 and c["obligations"]:
        c["obligations"].append(dict(c["obligations"][0]))
    elif r == 6:
        c["obligations"] = pick([{}, "x", [1], [{"id": "z"}]])
    elif r == 7:
        c["predecessor"] = pick(["abc", "G" * 64, 7, "A" * 64])
    elif r == 8:
        c["provenance"] = pick([[], "x", None])
    elif r == 9:
        c["base"] = pick(["", 1, None])
    elif r == 10:
        c["provenance"] = {"ratio": pick([0.5, 1e3, -0.0])}
    elif r == 11 and c["obligations"]:
        c["obligations"][0]["disposition"] = pick(["maybe", "REQUIRED", ""])
    elif r == 12:
        c["schema"] = pick(["neper-change-contract-2", "x", ""])
    elif r == 13:
        return [c]
    elif r == 14 and c["obligations"]:
        c["obligations"][0]["extra"] = 1
    elif r == 15:
        c["objective"] = pick([1, None, ["x"]])
    return c


def render(doc):
    """Random JSON text of a document: key order and whitespace vary, non-ASCII escaped half the time."""
    def shuffled(v):
        if isinstance(v, dict):
            items = list(v.items())
            rng.shuffle(items)
            return {k: shuffled(x) for k, x in items}
        if isinstance(v, list):
            return [shuffled(x) for x in v]
        return v
    return json.dumps(shuffled(doc), indent=pick([None, 0, 1, 2, 4]), ensure_ascii=chance(0.5),
                      separators=pick([None, (",", ":"), (", ", ": ")]))


def outcome(text):
    ref = reference(text)
    return "error" if ref is None else "%s %s %d\n%s" % ref[:4]


def main():
    cases = []
    base_docs = [good_contract() for _ in range(120)]
    for doc in base_docs:
        text = render(doc)
        cases.append({"k": "parse", "src": text, "src2": "", "e": outcome(text)})
    for doc in base_docs[:100]:
        text = render(damage(doc))
        cases.append({"k": "parse", "src": text, "src2": "", "e": outcome(text)})
    for text in ["", "{", "[]", "null", '{"schema":"neper-change-contract","schema":"x"}', "{}",
                 '{"a":' * 20 + "1" + "}" * 20]:
        cases.append({"k": "parse", "src": text, "src2": "", "e": outcome(text)})
    for _ in range(40):
        a = good_contract()
        a.pop("predecessor", None)
        ta = render(a)
        ra = reference(ta)
        b = good_contract()
        mode = rng.randrange(4)
        if mode == 0:
            b["predecessor"] = ra[0]
        elif mode == 1:
            b["predecessor"] = "0" * 64
        elif mode == 2:
            b.pop("predecessor", None)
        else:
            b = damage(b)
            if isinstance(b, dict):
                b["predecessor"] = ra[0]
        tb = render(b)
        rb = reference(tb)
        if ra is None or rb is None:
            e = "error"
        else:
            e = "true" if rb[4] == ra[0] else "false"
        cases.append({"k": "amend", "src": ta, "src2": tb, "e": e})
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    size = 8
    for i in range(0, len(lines), size):
        text = "\n".join(lines[i:i + size]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "contract_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_contract", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    errors = sum(1 for c in cases if c["e"] == "error")
    print("%d cases (%d errors) in %d chunks -> x_agent_contract" % (len(cases), errors, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
