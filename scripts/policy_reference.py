# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.policy` (T042, H36): decisions, path classification, audit verdicts, approvals, redaction.

Usage:  python scripts/policy_reference.py

Writes tests/selfhost/fixtures/link/x_agent_policy/src/main.e from scripts/policy_fixture_template.e. The semantics are
the module header's, written independently: the most specific matching rule decides (an exact scope over `prefix/*` over
`*`; a longer prefix over a shorter), the most restrictive on a tie, the default allow for workspace reads and writes
and deny for anything that reaches out; approvals are HMAC-SHA256 tokens bound to policy, effect and scope.
"""
import hashlib
import hmac
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7036)

EFFECTS = ["network", "credentials", "dependency_change", "project_exec", "vcs_mutation", "external_service",
           "write_outside_workspace", "write_workspace", "read_workspace"]
DECISIONS = ["allow", "deny", "approval_required"]
RESTRICTION = {"allow": 0, "approval_required": 1, "deny": 2}


class Lexeme(str):
    pass


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def is_text(v):
    return type(v) is str


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


def load(text, max_depth):
    def refuse(c):
        raise ValueError(c)
    try:
        doc = json.loads(text, object_pairs_hook=pairs_hook, parse_int=Lexeme, parse_float=Lexeme, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    if depth(doc) > max_depth or not only_integers(doc):
        return None
    return doc


def canonical(doc):
    return json.dumps(unwrap(doc), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def parse_policy(text):
    doc = load(text, 6)
    if not isinstance(doc, dict) or len(doc) != 4:
        return None
    if doc.get("schema") != "neper-action-policy" or not (isinstance(doc.get("version"), Lexeme) and doc["version"] == "1"):
        return None
    ws = doc.get("workspace")
    if not is_text(ws) or ws == "":
        return None
    rules = doc.get("rules")
    if not isinstance(rules, list) or len(rules) > 64:
        return None
    for r in rules:
        if not isinstance(r, dict) or set(r) != {"effect", "scope", "decision"}:
            return None
        if not all(is_text(r[k]) for k in r) or r["effect"] not in EFFECTS or r["scope"] == "" or r["decision"] not in DECISIONS:
            return None
    return doc, hashlib.sha256(canonical(doc).encode("utf-8")).hexdigest()


def specificity(pattern, scope):
    if pattern == "*":
        return 1
    if len(pattern) >= 2 and pattern.endswith("/*"):
        prefix = pattern[:-1]
        return len(prefix) + 1 if scope.startswith(prefix) else 0
    return 1000000 if pattern == scope else 0


def decide(doc, effect, scope):
    if effect not in EFFECTS:
        return "deny"
    best, chosen = 0, ""
    for r in doc["rules"]:
        if r["effect"] != effect:
            continue
        s = specificity(r["scope"], scope)
        if s > best or (s == best and s > 0 and RESTRICTION[r["decision"]] > RESTRICTION[chosen]):
            best, chosen = s, r["decision"]
    if best == 0:
        return "allow" if effect in ("read_workspace", "write_workspace") else "deny"
    return chosen


def normalize(path):
    segments, escaped = [], False
    for seg in re.split(r"[/\\]", path):
        if seg in ("", "."):
            continue
        if seg == "..":
            if segments:
                segments.pop()
            else:
                escaped = True
        else:
            segments.append(seg)
    return "/" + "/".join(segments), escaped


def classify(doc, path):
    ws, ws_escaped = normalize(doc["workspace"])
    absolute = len(path) > 0 and (path[0] in "/\\" or (len(path) > 1 and path[1] == ":"))
    full = path if absolute else doc["workspace"] + "/" + path
    resolved, escaped = normalize(full)
    if escaped or ws_escaped:
        return "write_outside_workspace"
    prefix = ws if ws == "/" else ws + "/"
    if resolved == ws or resolved.startswith(prefix):
        return "write_workspace"
    return "write_outside_workspace"


def split_entry(e):
    i = e.find(":")
    return (e, "") if i < 0 else (e[:i], e[i + 1:])


def audit(doc, declared, observed, approved, enforceable):
    violation = unapproved = undeclared = False
    for o in observed:
        effect, scope = split_entry(o)
        d = decide(doc, effect, scope)
        if d == "deny" and o not in approved:
            violation = True
        elif d == "approval_required" and o not in approved:
            unapproved = True
        if o not in declared:
            undeclared = True
    if violation:
        return "violation"
    if unapproved:
        return "unapproved"
    if undeclared:
        return "undeclared"
    return "verified" if enforceable else "unenforced"


def approval_status(key, token, policy_hash, effect, scope, now, seen):
    doc = load(token, 4)
    if not isinstance(doc, dict) or len(doc) != 6:
        return "malformed"
    if set(doc) != {"effect", "scope", "policy", "nonce", "mac", "expires"}:
        return "malformed"
    if not all(is_text(doc[k]) for k in ("effect", "scope", "policy", "nonce", "mac")):
        return "malformed"
    ex = doc["expires"]
    if not (isinstance(ex, Lexeme) and re.fullmatch(r"[0-9]{1,18}", ex)):
        return "malformed"
    body = {k: v for k, v in doc.items() if k != "mac"}
    mac = hmac.new(key.encode("utf-8"), canonical(body).encode("utf-8"), hashlib.sha256).hexdigest()
    if mac != doc["mac"]:
        return "bad-mac"
    if doc["policy"] != policy_hash:
        return "wrong-policy"
    if doc["effect"] != effect or doc["scope"] != scope:
        return "wrong-scope"
    if now > int(ex):
        return "expired"
    if doc["nonce"] in seen:
        return "replayed"
    return "valid"


def redact(text, secrets):
    for s in secrets:
        if s:
            text = text.replace(s, "[redacted]")
    return text


SCOPES = ["*", "/src/*", "/src/lib/*", "/src/a.e", "example.com", "*.example.com", "/etc/*", "git push", "npm install", "x"]


def good_policy():
    return {
        "schema": "neper-action-policy",
        "version": 1,
        "workspace": pick(["/w", "/work/space", "C:/proj", "/", "rel/ws"]),
        "rules": [{"effect": pick(EFFECTS), "scope": pick(SCOPES), "decision": pick(DECISIONS)} for _ in range(rng.randrange(0, 7))],
    }


def damage(p):
    p = json.loads(json.dumps(p))
    r = rng.randrange(8)
    if r == 0:
        p["extra"] = 1
    elif r == 1:
        p["version"] = 2
    elif r == 2:
        p["rules"] = pick([{}, "x", [1], [{"effect": "network"}]])
    elif r == 3 and p["rules"]:
        p["rules"][0]["effect"] = pick(["teleport", ""])
    elif r == 4 and p["rules"]:
        p["rules"][0]["decision"] = pick(["maybe", "ALLOW"])
    elif r == 5:
        p["workspace"] = pick(["", 1])
    elif r == 6 and p["rules"]:
        p["rules"][0]["scope"] = ""
    else:
        p["rules"] = [{"effect": "network", "scope": "*", "decision": "allow"}] * 70
    return p


def j(doc):
    return json.dumps(doc, ensure_ascii=chance(0.5), separators=pick([None, (",", ":")]))


def sign(key, body):
    return hmac.new(key.encode("utf-8"), canonical(body).encode("utf-8"), hashlib.sha256).hexdigest()


def case(k, p, a="", b="", c="", d="", e=""):
    return {"k": k, "p": p, "a": a, "b": b, "c": c, "d": d, "e": e}


def main():
    cases = []
    policies = [good_policy() for _ in range(40)]
    texts = [j(p) for p in policies]
    for p, t in zip(policies, texts):
        r = parse_policy(t)
        cases.append(case("parse", t, e="error" if r is None else r[1]))
    for p in policies[:30]:
        t = j(damage(p))
        r = parse_policy(t)
        cases.append(case("parse", t, e="error" if r is None else r[1]))
    for t in ["", "{", "[]", "null"]:
        r = parse_policy(t)
        cases.append(case("parse", t, e="error" if r is None else r[1]))
    for p, t in zip(policies, texts):
        doc, h = parse_policy(t)
        for _ in range(8):
            effect = pick(EFFECTS + ["teleport"])
            scope = pick(SCOPES + ["/src/lib/deep/x.e", "/srcx", "sub.example.com", ""])
            cases.append(case("decide", t, a=effect, b=scope, e=decide(doc, effect, scope)))
        for path in [pick(["a.e", "../x", "./a/../b", "/w/a", "/w", "/work/space/x/../y", "C:/proj/src", "C:\\proj\\a", "/etc/passwd", "..", "a/../../b", "\\w\\q"])
                     for _ in range(5)]:
            cases.append(case("classify", t, a=path, e=classify(doc, path)))
        for _ in range(8):
            entries = [pick(EFFECTS) + ":" + pick(SCOPES + ["/w/a", "/src/lib/x"]) for _ in range(rng.randrange(0, 4))]
            observed = entries[:]
            declared = [x for x in entries if chance(0.7)] + [pick(EFFECTS) + ":x" for _ in range(rng.randrange(0, 2))]
            approved = [x for x in entries if chance(0.3)]
            enforceable = chance(0.8)
            cases.append(case("audit", t, a="\n".join(declared), b="\n".join(observed), c="\n".join(approved),
                              d="1" if enforceable else "0", e=audit(doc, declared, observed, approved, enforceable)))
        # approvals: valid, then each defect
        key = pick(["k1", "secret-key", "ü"])
        for _ in range(8):
            effect = pick(EFFECTS)
            scope = pick(SCOPES)
            body = {"effect": effect, "scope": scope, "policy": h, "nonce": pick(["n1", "n2", "n3"]), "expires": rng.randrange(100, 200)}
            mode = rng.randrange(8)
            token = dict(body)
            token["mac"] = sign(key, body)
            offered_effect, offered_scope = effect, scope
            offered_key, now, seen = key, rng.randrange(0, 99), []
            if mode == 1:
                token["mac"] = "0" * 64
            elif mode == 2:
                token["policy"] = "f" * 64
                token["mac"] = sign(key, {k: v for k, v in token.items() if k != "mac"})
            elif mode == 3:
                offered_scope = scope + "/other"
            elif mode == 4:
                now = body["expires"] + 1
            elif mode == 5:
                seen = [body["nonce"]]
            elif mode == 6:
                offered_key = "other-key"
            elif mode == 7:
                token = {k: v for k, v in token.items() if k != "nonce"}
            cases.append(case("approval", t, a=j(token), b=offered_key, c=offered_effect + "\n" + offered_scope,
                              d=str(now) + "\n" + "\n".join(seen),
                              e=approval_status(offered_key, j(token), h, offered_effect, offered_scope, now, seen)))
    for _ in range(25):
        secrets = [pick(["hunter2", "tok_abc", "ünï", "a", ""]) for _ in range(rng.randrange(0, 3))]
        text = " ".join(pick(["hello", "hunter2", "tok_abc", "key=ünï", "aaa", "end"]) for _ in range(rng.randrange(1, 6)))
        t = texts[0]
        cases.append(case("redact", t, a=text, b="\n".join(secrets), e=redact(text, secrets)))
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    for i in range(0, len(lines), 10):
        text = "\n".join(lines[i:i + 10]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "policy_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_policy", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    kinds = {}
    for c in cases:
        kinds[c["k"]] = kinds.get(c["k"], 0) + 1
    print("%d cases %s in %d chunks -> x_agent_policy" % (len(cases), kinds, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
