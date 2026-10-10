# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.environment` (T042, H37): validate, classify and hash execution-environment manifests.

Usage:  python scripts/environment_reference.py

Writes tests/selfhost/fixtures/link/x_agent_environment/src/main.e from scripts/environment_fixture_template.e. The
rules are the spec's (H37) written independently of the Neper module. A case is `{"k": "parse"|"same", "src", "src2", "e"}`:
`parse` gives `error` or `identity level omissions\\ncanonical`, `same` says whether two manifests have one identity
(`true`/`false`/`error`) -- the perturbation acceptance: every core field changes identity, the observation never does.
"""
import hashlib
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7037)


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


def nonneg_int(v):
    return isinstance(v, Lexeme) and re.fullmatch(r"[0-9]+", v) is not None


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


def text_items(v):
    return isinstance(v, list) and all(is_text(x) for x in v)


CORE = ["tools", "platform", "lock", "roots", "env", "locale", "timezone", "clock", "random", "network", "limits"]
TOP = set(["schema", "version", "services", "observed", "uncontrolled", "observation"] + CORE)
LEVELS = ["hermetic", "observed", "uncontrolled"]


def reference(text):
    def refuse(c):
        raise ValueError(c)
    try:
        doc = json.loads(text, object_pairs_hook=pairs_hook, parse_int=Lexeme, parse_float=Lexeme, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    if depth(doc) > 8 or not isinstance(doc, dict) or not set(doc) <= TOP:
        return None
    if doc.get("schema") != "neper-environment" or not (isinstance(doc.get("version"), Lexeme) and doc["version"] == "1"):
        return None
    omissions = [k for k in CORE + ["services"] if k not in doc]
    rank = 2 if omissions else 0
    if "tools" in doc:
        t = doc["tools"]
        if not isinstance(t, list) or not t:
            return None
        for x in t:
            if not isinstance(x, dict) or set(x) != {"name", "sha256"} or not is_text(x["name"]) or x["name"] == "" or not hex64(x["sha256"]):
                return None
    if "platform" in doc:
        p = doc["platform"]
        if not isinstance(p, dict) or set(p) != {"os", "arch"} or not all(is_text(p[k]) and p[k] != "" for k in p):
            return None
    if "lock" in doc and not (hex64(doc["lock"]) or doc["lock"] == "none" and is_text(doc["lock"])):
        return None
    if "roots" in doc:
        r = doc["roots"]
        if not isinstance(r, dict) or set(r) != {"read", "write"} or not text_items(r["read"]) or not text_items(r["write"]):
            return None
    if "env" in doc:
        e = doc["env"]
        if not isinstance(e, dict):
            return None
        for v in e.values():
            if not is_text(v) or re.fullmatch(r"sha256:[0-9a-f]{64}", v) is None:
                return None
    for k in ("locale", "timezone"):
        if k in doc and (not is_text(doc[k]) or doc[k] == ""):
            return None
    if "limits" in doc:
        l = doc["limits"]
        if not isinstance(l, dict) or not all(nonneg_int(v) for v in l.values()):
            return None
    if "services" in doc and not text_items(doc["services"]):
        return None
    if "observed" in doc:
        if not text_items(doc["observed"]):
            return None
        if doc["observed"]:
            rank = max(rank, 1)
    if "uncontrolled" in doc:
        if not text_items(doc["uncontrolled"]):
            return None
        if doc["uncontrolled"]:
            rank = 2
    for key, spellings in (("clock", ("fixed", "monotonic", "real")), ("random", ("seeded", None, "os")), ("network", ("none", "allowlist", "open"))):
        if key in doc:
            v = doc[key]
            if not is_text(v) or v not in [s for s in spellings if s]:
                return None
            rank = max(rank, spellings.index(v))
    core = {k: v for k, v in doc.items() if k != "observation"}
    if not only_integers(core):
        return None
    canonical = json.dumps(unwrap(core), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    identity = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return identity, LEVELS[rank], omissions, canonical


def good_env():
    d = {
        "schema": "neper-environment",
        "version": 1,
        "tools": [{"name": pick(["neper", "neper-self"]), "sha256": "".join(pick("0123456789abcdef") for _ in range(64))}
                  for _ in range(rng.randrange(1, 3))],
        "platform": {"os": pick(["windows", "linux"]), "arch": pick(["x64", "arm64"])},
        "lock": pick(["none", "".join(pick("0123456789abcdef") for _ in range(64))]),
        "roots": {"read": [pick(["/src", "C:/work", "ünï"]) for _ in range(rng.randrange(0, 3))],
                  "write": [pick(["/out", "build"]) for _ in range(rng.randrange(0, 2))]},
        "env": {k: "sha256:" + "".join(pick("0123456789abcdef") for _ in range(64)) for k in rng.sample(["PATH", "HOME", "LANG", "TOKEN"], rng.randrange(0, 4))},
        "locale": pick(["C", "en_US.UTF-8"]),
        "timezone": pick(["UTC", "Europe/Sofia"]),
        "clock": pick(["fixed", "fixed", "monotonic", "real"]),
        "random": pick(["seeded", "seeded", "os"]),
        "network": pick(["none", "none", "allowlist", "open"]),
        "limits": {k: pick([0, 512, 60000]) for k in rng.sample(["memory_mb", "time_ms", "files"], rng.randrange(0, 3))},
        "services": [pick(["db", "cache"]) for _ in range(rng.randrange(0, 2))],
    }
    if chance(0.25):
        d["observed"] = [pick(["locale", "timezone"])]
    if chance(0.1):
        d["uncontrolled"] = [pick(["gpu", "wall-clock"])]
    if chance(0.4):
        d["observation"] = {"host": pick(["ci-1", "laptop"]), "at": pick([1, 2, 3]), "pid": rng.randrange(1000)}
    if chance(0.2):
        del d[pick(CORE + ["services"])]
    return d


def damage(d):
    d = json.loads(json.dumps(d))
    r = rng.randrange(12)
    if r == 0:
        d["surprise"] = 1
    elif r == 1:
        d["env"] = {"TOKEN": "hunter2"}
    elif r == 2:
        d["clock"] = pick(["wall", "", 3])
    elif r == 3:
        d["network"] = pick(["maybe", ""])
    elif r == 4:
        d["tools"] = pick([[], "x", [{"name": "n"}], [{"name": "n", "sha256": "xyz"}]])
    elif r == 5:
        d["lock"] = pick(["", "latest", "A" * 64])
    elif r == 6:
        d["limits"] = {"memory_mb": pick([-1, 1.5, "big"])}
    elif r == 7:
        d["platform"] = pick([{"os": "linux"}, [], {"os": "", "arch": "x64"}])
    elif r == 8:
        d["version"] = pick([2, "1", 1.0])
    elif r == 9:
        d["observed"] = pick(["locale", [1]])
    elif r == 10:
        d["schema"] = pick(["neper-env", ""])
    elif r == 11:
        return [d]
    return d


def render(doc):
    def shuffled(v):
        if isinstance(v, dict):
            items = list(v.items())
            rng.shuffle(items)
            return {k: shuffled(x) for k, x in items}
        if isinstance(v, list):
            return [shuffled(x) for x in v]
        return v
    return json.dumps(shuffled(doc), indent=pick([None, 0, 2]), ensure_ascii=chance(0.5), separators=pick([None, (",", ":")]))


def outcome(text):
    ref = reference(text)
    if ref is None:
        return "error"
    return "%s %s %s\n%s" % (ref[0], ref[1], ",".join(ref[2]), ref[3])


def perturb(d):
    """One change to the core, or to the observation only; returns (doc, should_be_same)."""
    d = json.loads(json.dumps(d))
    if rng.random() < 0.3:
        d["observation"] = {"host": pick(["a", "b", "c"]), "n": rng.randrange(100)}
        return d, True
    key = pick([k for k in CORE + ["services"] if k in d])
    v = d[key]
    if key == "tools":
        v[0]["sha256"] = "".join(pick("0123456789abcdef") for _ in range(64))
    elif key == "platform":
        v["arch"] = v["arch"] + "x"
    elif key == "lock":
        d[key] = "".join(pick("0123456789abcdef") for _ in range(64)) if v == "none" else "none"
    elif key == "roots":
        v["read"] = v["read"] + ["/extra"]
    elif key == "env":
        v["NEWVAR"] = "sha256:" + "0" * 64
    elif key in ("locale", "timezone"):
        d[key] = v + "-x"
    elif key == "clock":
        d[key] = "fixed" if v != "fixed" else "real"
    elif key == "random":
        d[key] = "seeded" if v != "seeded" else "os"
    elif key == "network":
        d[key] = "none" if v != "none" else "open"
    elif key == "limits":
        v["extra_limit"] = 1
    elif key == "services":
        v.append("extra-service")
    return d, False


def main():
    cases = []
    docs = [good_env() for _ in range(110)]
    for d in docs:
        t = render(d)
        cases.append({"k": "parse", "src": t, "src2": "", "e": outcome(t)})
    for d in docs[:90]:
        t = render(damage(d))
        cases.append({"k": "parse", "src": t, "src2": "", "e": outcome(t)})
    for t in ["", "{", "[]", '{"schema":"neper-environment","version":1,"version":1}', "{}"]:
        cases.append({"k": "parse", "src": t, "src2": "", "e": outcome(t)})
    for d in docs[:60]:
        other, same = perturb(d)
        ta, tb = render(d), render(other)
        ra, rb = reference(ta), reference(tb)
        e = "error" if ra is None or rb is None else ("true" if ra[0] == rb[0] else "false")
        cases.append({"k": "same", "src": ta, "src2": tb, "e": e})
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    for i in range(0, len(lines), 8):
        text = "\n".join(lines[i:i + 8]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "environment_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_environment", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    errors = sum(1 for c in cases if c["e"] == "error")
    changed = sum(1 for c in cases if c["k"] == "same" and c["e"] == "false")
    print("%d cases (%d errors, %d identity changes) in %d chunks -> x_agent_environment" % (len(cases), errors, changed, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
