# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.bundle` (T042, H38): parse change bundles and judge their integration.

Usage:  python scripts/bundle_reference.py

Writes tests/selfhost/fixtures/link/x_agent_bundle/src/main.e from scripts/bundle_fixture_template.e. The verdict rules
are the module header's, written independently: stale > conflict > incomplete > clean; overlap is
`x.start < y.end and y.start < x.end` on one path; a shared semantic identity conflicts though the text is disjoint;
missing receipts and differing policy or environment hashes are incomplete; `combined` is SHA-256 of the base and the
bundle hashes joined by newlines; the combined snapshot never claims to be verified.
"""
import hashlib
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7038)


class Lexeme(str):
    pass


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def is_text(v):
    return type(v) is str


def hex64(s):
    return is_text(s) and re.fullmatch(r"[0-9a-f]{64}", s) is not None


def pairs_hook(pairs):
    keys = [k for k, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate")
    return dict(pairs)


def depth(v):
    if isinstance(v, dict):
        return 1 + max([depth(x) for x in v.values()] + [0])
    if isinstance(v, list):
        return 1 + max([depth(x) for x in v] + [0])
    return 0


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


def parse_bundle(text):
    def refuse(c):
        raise ValueError(c)
    try:
        doc = json.loads(text, object_pairs_hook=pairs_hook, parse_int=Lexeme, parse_float=Lexeme, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    if depth(doc) > 6 or not only_integers(doc) or not isinstance(doc, dict) or len(doc) != 10:
        return None
    if doc.get("schema") != "neper-change-bundle" or not (isinstance(doc.get("version"), Lexeme) and doc["version"] == "1"):
        return None
    for k in ("base", "result", "contract", "environment", "policy", "receipt"):
        if not is_text(doc.get(k)):
            return None
    if doc["base"] == "" or doc["result"] == "":
        return None
    if not (hex64(doc["contract"]) and hex64(doc["environment"]) and hex64(doc["policy"])):
        return None
    if doc["receipt"] != "" and not hex64(doc["receipt"]):
        return None
    edits = doc.get("edits")
    if not isinstance(edits, list):
        return None
    out = []
    for e in edits:
        if not isinstance(e, dict) or set(e) != {"path", "start", "end"}:
            return None
        if not is_text(e["path"]) or e["path"] == "":
            return None
        for k in ("start", "end"):
            if not (isinstance(e[k], Lexeme) and re.fullmatch(r"[0-9]{1,18}", e[k])):
                return None
        start, end = int(e["start"]), int(e["end"])
        if start > end:
            return None
        out.append((e["path"], start, end))
    ids = doc.get("identities")
    if not isinstance(ids, list) or not all(is_text(x) and x != "" for x in ids):
        return None
    canonical = json.dumps(unwrap(doc), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    h = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return {"hash": h, "base": doc["base"], "edits": out, "ids": ids, "policy": doc["policy"],
            "environment": doc["environment"], "receipt": doc["receipt"]}


def integrate(bundles, current_base):
    stale, conflict, incomplete = [], [], []
    for i, b in enumerate(bundles):
        if b["base"] != current_base:
            stale.append("stale:%d" % i)
        if b["receipt"] == "":
            incomplete.append("no-receipt:%d" % i)
    for i in range(len(bundles)):
        for j in range(i + 1, len(bundles)):
            x, y = bundles[i], bundles[j]
            for px, sx, ex in x["edits"]:
                for py, sy, ey in y["edits"]:
                    if px == py and sx < ey and sy < ex:
                        conflict.append("overlap:%s:%d:%d" % (px, i, j))
            for nx in x["ids"]:
                for ny in y["ids"]:
                    if nx == ny:
                        conflict.append("identity:%s:%d:%d" % (nx, i, j))
            if x["policy"] != y["policy"]:
                incomplete.append("policy:%d:%d" % (i, j))
            if x["environment"] != y["environment"]:
                incomplete.append("environment:%d:%d" % (i, j))
    combined = hashlib.sha256("\n".join([current_base] + [b["hash"] for b in bundles]).encode("utf-8")).hexdigest()
    for verdict, causes, cap in (("stale", stale, 64), ("conflict", conflict, 128), ("incomplete", incomplete, 64)):
        if causes:
            return verdict, combined, causes[:cap]
    return "clean", combined, []


def hexs():
    return "".join(pick("0123456789abcdef") for _ in range(64))


POLICIES = [hexs(), hexs()]
ENVS = [hexs(), hexs()]
PATHS = ["src/a.e", "src/b.e", "lib/x.e", "ünï.e"]
NAMES = ["m.f", "m.g", "api:m.h", "n.k"]


def good_bundle(base, same_policy=True, same_env=True):
    edits = []
    for _ in range(rng.randrange(0, 4)):
        s = rng.randrange(0, 60)
        edits.append({"path": pick(PATHS), "start": s, "end": s + rng.randrange(0, 20)})
    return {
        "schema": "neper-change-bundle", "version": 1,
        "base": base, "result": "res-" + str(rng.randrange(1000)),
        "edits": edits, "identities": sorted(set(pick(NAMES) for _ in range(rng.randrange(0, 3)))),
        "contract": hexs(),
        "environment": ENVS[0] if same_env else pick(ENVS),
        "policy": POLICIES[0] if same_policy else pick(POLICIES),
        "receipt": pick([hexs(), hexs(), hexs(), ""]),
    }


def damage(b):
    b = json.loads(json.dumps(b))
    r = rng.randrange(9)
    if r == 0:
        b["extra"] = 1
    elif r == 1:
        del b[pick(["base", "result", "edits", "identities", "contract", "environment", "policy", "receipt"])]
    elif r == 2:
        b["contract"] = pick(["abc", "", 7])
    elif r == 3:
        b["receipt"] = pick(["xyz", "A" * 64, 5])
    elif r == 4:
        b["edits"] = pick([{}, "x", [{"path": "p"}], [{"path": "", "start": 0, "end": 1}], [{"path": "p", "start": 5, "end": 2}],
                           [{"path": "p", "start": -1, "end": 2}], [{"path": "p", "start": 1.5, "end": 2}]])
    elif r == 5:
        b["identities"] = pick(["m.f", [1], [""]])
    elif r == 6:
        b["version"] = pick([2, "1"])
    elif r == 7:
        b["base"] = pick(["", 1])
    else:
        b["schema"] = "neper-change-bundle-x"
    return b


def render(doc):
    return json.dumps(doc, ensure_ascii=chance(0.5), indent=pick([None, 2]), separators=pick([None, (",", ":")]))


def main():
    cases = []
    for _ in range(80):
        t = render(good_bundle(pick(["s1", "s2"])))
        r = parse_bundle(t)
        cases.append({"k": "parse", "a": t, "b": "", "e": "error" if r is None else r["hash"]})
    for _ in range(60):
        t = render(damage(good_bundle("s1")))
        r = parse_bundle(t)
        cases.append({"k": "parse", "a": t, "b": "", "e": "error" if r is None else r["hash"]})
    for t in ["", "{", "[]", "{}"]:
        cases.append({"k": "parse", "a": t, "b": "", "e": "error"})
    for _ in range(220):
        n = rng.randrange(1, 5)
        base = pick(["s1", "s2"])
        mode = rng.randrange(6)
        docs = []
        for _ in range(n):
            b = good_bundle(base if mode != 1 or chance(0.6) else "s9", same_policy=mode != 2, same_env=mode != 3)
            if mode != 4:
                b["receipt"] = hexs()
            if mode == 5:
                b["edits"] = [{"path": "src/a.e", "start": rng.randrange(0, 30), "end": 0}]
                b["edits"][0]["end"] = b["edits"][0]["start"] + rng.randrange(1, 15)
            docs.append(b)
        texts = [render(d) for d in docs]
        if chance(0.05):
            texts[rng.randrange(len(texts))] = "{"
        parsed = [parse_bundle(t) for t in texts]
        if any(p is None for p in parsed):
            e = "error"
        else:
            verdict, combined, causes = integrate(parsed, base)
            e = "\n".join([verdict + " " + combined] + causes)
        cases.append({"k": "integrate", "a": "\x01".join(texts), "b": base, "e": e})
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    for i in range(0, len(lines), 10):
        text = "\n".join(lines[i:i + 10]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "bundle_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_bundle", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    verdicts = {}
    for c in cases:
        if c["k"] == "integrate":
            v = c["e"].split(" ")[0]
            verdicts[v] = verdicts.get(v, 0) + 1
    print("%d cases %s in %d chunks -> x_agent_bundle" % (len(cases), verdicts, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
