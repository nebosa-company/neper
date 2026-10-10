# -*- coding: utf-8 -*-
"""Reference vectors for `x.agent.task` (T042, H44): the durable operation lifecycle as a state machine.

Usage:  python scripts/task_reference.py

Writes tests/selfhost/fixtures/link/x_agent_task/src/main.e from scripts/task_fixture_template.e. The model is the
module header's, written independently: transitions queued->running|cancelled, running->input_required|succeeded|
failed|cancelling, input_required->running|cancelling|failed, cancelling->cancelled|succeeded|failed, terminal states
final; handle = HMAC-SHA256(key, id + "\\n" + nonce); authorize checks handle, then owner, then expiry; input tokens
are HMAC-bound to task, operation, policy and scope with expiry and a single-use nonce.
"""
import hashlib
import hmac
import json
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7044)

TERMINAL = {"succeeded", "failed", "cancelled"}
ALLOWED = {
    "queued": {"running", "cancelled"},
    "running": {"input_required", "succeeded", "failed", "cancelling"},
    "input_required": {"running", "cancelling", "failed"},
    "cancelling": {"cancelled", "succeeded", "failed"},
}


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def canonical(doc):
    return json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def mac_hex(key, text):
    return hmac.new(key.encode("utf-8"), text.encode("utf-8"), hashlib.sha256).hexdigest()


class Task:
    def __init__(self, tid, operation, policy, scope, owner, created, expires, nonce):
        self.id, self.operation, self.policy, self.scope, self.owner = tid, operation, policy, scope, owner
        self.status, self.created, self.expires, self.nonce = "queued", created, expires, nonce
        self.outcome, self.result_hash, self.seen, self.version = "", "", [], 0

    def handle(self, key):
        return mac_hex(key, self.id + "\n" + self.nonce)

    def authorize(self, key, handle, caller, now):
        if self.handle(key) != handle:
            return "unknown-handle"
        if caller != self.owner:
            return "denied"
        if now > self.expires:
            return "expired"
        return "ok"

    def advance(self, to):
        if self.status in TERMINAL:
            return "terminal"
        if to not in ALLOWED[self.status]:
            return "illegal"
        self.status = to
        self.version += 1
        return "ok"

    def cancel(self):
        if self.status in TERMINAL:
            return "already-terminal"
        if self.status == "queued":
            self.status = "cancelled"
            self.version += 1
            return "cancelled"
        if self.status == "cancelling":
            return "cancelling"
        self.status = "cancelling"
        self.version += 1
        return "cancelling"

    def complete(self, outcome, result):
        digest = hashlib.sha256(result.encode("utf-8")).hexdigest()
        if self.status in TERMINAL:
            return "duplicate" if (self.outcome == outcome and self.result_hash == digest) else "rejected"
        if outcome not in ("succeeded", "failed", "cancelled"):
            return "rejected"
        if outcome not in ALLOWED[self.status]:
            return "rejected"
        self.status, self.outcome, self.result_hash = outcome, outcome, digest
        self.version += 1
        return "ok"

    def supply(self, key, token_text, now):
        try:
            tok = json.loads(token_text)
        except ValueError:
            return "malformed"
        if not isinstance(tok, dict) or set(tok) != {"task", "operation", "policy", "scope", "expires", "nonce", "mac"}:
            return "malformed"
        if not all(type(tok[k]) is str for k in ("task", "operation", "policy", "scope", "nonce", "mac")):
            return "malformed"
        ex = tok["expires"]
        if type(ex) is not int or ex < 0 or len(str(ex)) > 18:
            return "malformed"
        body = {k: v for k, v in tok.items() if k != "mac"}
        if mac_hex(key, canonical(body)) != tok["mac"]:
            return "bad-mac"
        if tok["task"] != self.id:
            return "wrong-task"
        if tok["operation"] != self.operation:
            return "wrong-operation"
        if tok["policy"] != self.policy:
            return "wrong-policy"
        if tok["scope"] != self.scope:
            return "wrong-scope"
        if now > ex:
            return "expired"
        if tok["nonce"] in self.seen:
            return "replayed"
        if self.status != "input_required":
            return "not-waiting"
        self.seen.append(tok["nonce"])
        self.status = "running"
        self.version += 1
        return "valid"

    def snapshot(self):
        return canonical({"id": self.id, "operation": self.operation, "policy": self.policy, "scope": self.scope,
                          "owner": self.owner, "status": self.status, "created": self.created, "expires": self.expires,
                          "outcome": self.outcome, "result": self.result_hash, "seen": self.seen, "version": self.version})


def token(key, subject, now_hint=0, **over):
    body = {"task": subject.id, "operation": subject.operation, "policy": subject.policy, "scope": subject.scope,
            "expires": now_hint + rng.randrange(1, 40), "nonce": pick(["n1", "n2", "n3"])}
    body.update(over)
    out = dict(body)
    out["mac"] = mac_hex(key, canonical(body))
    return out


def scenario():
    key = pick(["svc-key", "k2", "ünï"])
    tid = pick(["t-1", "task/7", "ü"])
    op, pol, scope, owner = pick(["opA", "opB"]), pick(["pol1", "pol2"]), pick(["scope1", "s/2"]), pick(["alice", "bob"])
    created = rng.randrange(0, 50)
    expires = created + rng.randrange(5, 100)
    nonce = pick(["x1", "x2"])
    steps, expected = [], []
    t = Task(tid, op, pol, scope, owner, created, expires, nonce)
    steps.append("\t".join(["create", tid, op, pol, scope, owner, str(created), str(expires), nonce]))
    expected.append("handle:" + t.handle(key))
    for _ in range(rng.randrange(3, 14)):
        kind = rng.randrange(7)
        now = rng.randrange(0, expires + 20)
        h = t.handle(key) if chance(0.85) else "0" * 64
        caller = owner if chance(0.85) else "mallory"
        if kind == 0:
            steps.append("\t".join(["read", h, caller, str(now)]))
            a = t.authorize(key, h, caller, now)
            expected.append("ok " + t.status if a == "ok" else a)
        elif kind == 1:
            steps.append("\t".join(["cancel", h, caller, str(now)]))
            a = t.authorize(key, h, caller, now)
            expected.append(t.cancel() if a == "ok" else a)
        elif kind == 2:
            to = pick(["running", "input_required", "succeeded", "failed", "cancelling", "cancelled", "queued", "bogus"])
            steps.append("\t".join(["advance", to]))
            expected.append(t.advance(to))
        elif kind == 3:
            outcome = pick(["succeeded", "failed", "cancelled", "weird"])
            result = pick(["r1", "r2", "", "ünï"])
            steps.append("\t".join(["complete", outcome, result]))
            expected.append(t.complete(outcome, result))
        elif kind == 4 or kind == 5:
            over = {}
            mode = rng.randrange(8)
            if mode == 1:
                over["task"] = "other"
            elif mode == 2:
                over["operation"] = "opX"
            elif mode == 3:
                over["policy"] = "polX"
            elif mode == 4:
                over["scope"] = "scopeX"
            tk = token(key if mode != 5 else "wrong-key", t, now, **over)
            text = json.dumps(tk, ensure_ascii=chance(0.5))
            if mode == 6:
                text = "{not json"
            if mode == 7:
                tk.pop("nonce")
                text = json.dumps(tk)
            steps.append("\t".join(["input", text, str(now)]))
            expected.append(t.supply(key, text, now))
        else:
            steps.append("snapshot")
            expected.append(t.snapshot())
    # always end with the full state so the version/seen bookkeeping is compared
    steps.append("snapshot")
    expected.append(t.snapshot())
    return {"key": key, "steps": steps, "e": "\n".join(expected)}


def guided():
    """A run that mostly goes where it should: queued, running, waiting, resumed (once, then replayed), finished."""
    key = pick(["svc-key", "k2"])
    t = Task("g-%d" % rng.randrange(99), "op", "pol", "sc", "owner", 0, 200, pick(["a", "b"]))
    steps = ["	".join(["create", t.id, "op", "pol", "sc", "owner", "0", "200", t.nonce])]
    exp = ["handle:" + t.handle(key)]

    def do(step, out):
        steps.append(step)
        exp.append(out)

    do("advance	running", t.advance("running"))
    for _ in range(rng.randrange(1, 4)):
        do("advance	input_required", t.advance("input_required"))
        for _ in range(rng.randrange(1, 3)):
            tk = token(key, t, 5, nonce=pick(["u1", "u2", "u3"]), expires=rng.randrange(10, 120))
            text = json.dumps(tk)
            now = rng.randrange(0, 150)
            do("	".join(["input", text, str(now)]), t.supply(key, text, now))
        if t.status != "running":
            break
    if chance(0.3):
        do("	".join(["cancel", t.handle(key), "owner", "10"]), t.cancel())
    outcome = pick(["succeeded", "failed", "cancelled"])
    for _ in range(rng.randrange(1, 4)):
        do("	".join(["complete", outcome if chance(0.7) else pick(["succeeded", "failed"]), pick(["r", "r", "s"])]),
           "")
        steps_last = steps[-1].split("	")
        exp[-1] = t.complete(steps_last[1], steps_last[2])
    do("snapshot", t.snapshot())
    return {"key": key, "steps": steps, "e": "\n".join(exp)}


def main():
    cases = [scenario() for _ in range(260)] + [guided() for _ in range(120)]
    # Guarantee the interesting paths appear: a run that waits for input and is resumed.
    key = "svc-key"
    t = Task("t", "op", "pol", "sc", "owner", 0, 100, "n")
    steps = ["\t".join(["create", "t", "op", "pol", "sc", "owner", "0", "100", "n"])]
    exp = ["handle:" + t.handle(key)]
    for to in ("running", "input_required"):
        steps.append("advance\t" + to)
        exp.append(t.advance(to))
    tk = json.dumps(token(key, t, 5, nonce="once", expires=50))
    for _ in range(2):
        steps.append("\t".join(["input", tk, "10"]))
        exp.append(t.supply(key, tk, 10))
    steps.append("complete\tsucceeded\tdone")
    exp.append(t.complete("succeeded", "done"))
    steps.append("complete\tsucceeded\tdone")
    exp.append(t.complete("succeeded", "done"))
    steps.append("complete\tfailed\tdone")
    exp.append(t.complete("failed", "done"))
    steps.append("snapshot")
    exp.append(t.snapshot())
    cases.append({"key": key, "steps": steps, "e": "\n".join(exp)})
    lines = [json.dumps(c, ensure_ascii=True) for c in cases]
    chunks = []
    for i in range(0, len(lines), 6):
        text = "\n".join(lines[i:i + 6]) + "\n"
        chunks.append('"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "task_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_agent_task", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    seen = {}
    for c in cases:
        for line in c["e"].split("\n"):
            w = line.split(" ")[0]
            if len(w) < 24 and not w.startswith("{"):
                seen[w] = seen.get(w, 0) + 1
    print("%d cases, outputs %s in %d chunks -> x_agent_task" % (len(cases), dict(sorted(seen.items())), len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
