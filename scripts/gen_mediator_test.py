"""Generates tests/selfhost/fixtures/link/mediator/src/main.e (L138).

There is no reference implementation to run, so the oracle is an independent Python model of
MediatR's documented semantics -- one handler per request kind, behaviors wrapping it in
registration order (first registered outermost), notification fan-out in registration order
-- evaluated on random scenarios. Each scenario is rendered as Neper code that registers the
same handlers, listeners and behaviors, performs the same operations, and compares the call
trace the module produced with the model's.

    python scripts/gen_mediator_test.py
"""
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "mediator", "src", "main.e")


class Model:
    def __init__(self, sc):
        self.sc = sc
        self.trace = []
        self.handlers = {}      # kind -> dict
        self.listeners = []
        self.behaviors = []
        for h in sc["handlers"]:
            if h["kind"] in self.handlers:
                self.trace.append("#")
            else:
                self.handlers[h["kind"]] = dict(h, calls=0)
        for l in sc["listeners"]:
            self.listeners.append(l)
        for b in sc["behaviors"]:
            self.behaviors.append(b)

    def call_handler(self, h, kind):
        h["calls"] += 1
        if h["mode"] == 1 or h["calls"] <= h["fail_first"]:
            self.trace.append("x%d" % h["id"])
            return None, "F"
        self.trace.append("H%d" % h["id"])
        return h["id"] + 100, None

    def proceed(self, kind, pos, h):
        for i in range(pos, len(self.behaviors)):
            b = self.behaviors[i]
            if b["kind"] == 0 or b["kind"] == kind:
                return self.run_behavior(b, kind, i + 1, h)
        return self.call_handler(h, kind)

    def run_behavior(self, b, kind, nxt, h):
        i = b["id"]
        if b["mode"] == 0:
            self.trace.append("a%d" % i)
            r, e = self.proceed(kind, nxt, h)
            self.trace.append("A%d" % i)
            return r, e
        if b["mode"] == 1:
            self.trace.append("s%d" % i)
            return b["arg"], None
        if b["mode"] == 2:
            self.trace.append("f%d" % i)
            return None, "F"
        if b["mode"] == 3:
            last = (None, "F")
            for _ in range(max(b["arg"], 1)):
                self.trace.append("r%d" % i)
                r, e = self.proceed(kind, nxt, h)
                if e is None:
                    return r, e
                last = (r, e)
            return last
        # mode 4: recover
        self.trace.append("c%d" % i)
        r, e = self.proceed(kind, nxt, h)
        if e is not None:
            self.trace.append("C%d" % i)
            return b["arg"], None
        return r, e

    def run(self):
        for op in self.sc["ops"]:
            kind = op[1]
            if op[0] == "send":
                h = self.handlers.get(kind)
                if h is None:
                    self.trace.append("!N")
                    continue
                r, e = self.proceed(kind, 0, h)
                self.trace.append("=%03d" % r if e is None else "!F")
            elif op[0] == "publish":
                failed = None
                for l in self.listeners:
                    if l["kind"] == kind:
                        self.trace.append("L%d" % l["id"])
                        if l["mode"] == 1:
                            failed = True
                            break
                self.trace.append("!F" if failed else "=ok")
            else:
                n = 0
                for l in self.listeners:
                    if l["kind"] == kind:
                        self.trace.append("L%d" % l["id"])
                        if l["mode"] == 1:
                            n += 1
                self.trace.append("=%d" % n)
        return "".join(self.trace)


def scenario(rnd):
    kinds = [1, 2, 3]
    sc = {"handlers": [], "listeners": [], "behaviors": [], "ops": []}
    used = 0
    for k in rnd.sample(kinds, rnd.randint(1, 3)):
        sc["handlers"].append({"kind": k, "id": used % 10, "mode": rnd.choice([0, 0, 0, 1]), "fail_first": rnd.choice([0, 0, 1, 2])})
        used += 1
    if rnd.random() < 0.25:
        sc["handlers"].append({"kind": sc["handlers"][0]["kind"], "id": used % 10, "mode": 0, "fail_first": 0})
        used += 1
    for _ in range(rnd.randint(0, 3)):
        sc["listeners"].append({"kind": rnd.choice([1, 2, 4]), "id": used % 10, "mode": rnd.choice([0, 0, 1])})
        used += 1
    for _ in range(rnd.randint(0, 4)):
        mode = rnd.choice([0, 0, 0, 1, 2, 3, 4])
        arg = rnd.randint(1, 4) if mode == 3 else rnd.randint(0, 99)
        sc["behaviors"].append({"kind": rnd.choice([0, 0, 1, 2]), "id": used % 10, "mode": mode, "arg": arg})
        used += 1
    for _ in range(rnd.randint(2, 6)):
        op = rnd.choice(["send", "send", "publish", "publish_all"])
        sc["ops"].append((op, rnd.choice([1, 2, 3, 4, 9])))
    return sc


def render(sc, k, expected):
    L = ["fn case_%d(a: *mem.Arena) -> bool {" % k]
    L.append("    var trace = Trace{ buf: zero, n: 0usize }")
    L.append("    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)")
    L.append("    if me != ok { ret false }")
    L.append("    var m = m0")
    nh, nl, nb = len(sc["handlers"]), len(sc["listeners"]), len(sc["behaviors"])
    L.append("    var hc: [%d]Ctx = zero" % max(1, nh))
    L.append("    var lc: [%d]Ctx = zero" % max(1, nl))
    L.append("    var bc: [%d]Ctx = zero" % max(1, nb))
    for i, h in enumerate(sc["handlers"]):
        L.append("    hc[%d] = Ctx{ trace: &trace, id: %du8, mode: %du8, arg: 0u8, calls: 0u32, fail_first: %du32 }" % (i, h["id"], h["mode"], h["fail_first"]))
        L.append("    if med.register(&m, %du32, mem.cast[*void](&hc[%d]), handler_run) != ok { mark(&trace, 35u8) }" % (h["kind"], i))
    for i, l in enumerate(sc["listeners"]):
        L.append("    lc[%d] = Ctx{ trace: &trace, id: %du8, mode: %du8, arg: 0u8, calls: 0u32, fail_first: 0u32 }" % (i, l["id"], l["mode"]))
        L.append("    if med.subscribe(&m, %du32, mem.cast[*void](&lc[%d]), listener_run) != ok { ret false }" % (l["kind"], i))
    for i, b in enumerate(sc["behaviors"]):
        L.append("    bc[%d] = Ctx{ trace: &trace, id: %du8, mode: %du8, arg: %du8, calls: 0u32, fail_first: 0u32 }" % (i, b["id"], b["mode"], b["arg"]))
        L.append("    if med.behave(&m, %du32, mem.cast[*void](&bc[%d]), behavior_run) != ok { ret false }" % (b["kind"], i))
    L.append("    let none: [1]u8 = [1]u8{ 0 }")
    for op, kind in sc["ops"]:
        msg = "med.Message{ kind: %du32, data: none[0usize..0usize] }" % kind
        if op == "send":
            L.append("    let (rs%d, er%d) = med.send(&m, a, %s)" % (len(L), len(L), msg))
            L.append("    result(&trace, rs%d, er%d)" % (len(L) - 1, len(L) - 1))
        elif op == "publish":
            L.append("    note_result(&trace, med.publish(&m, a, %s))" % msg)
        else:
            L.append("    let (cn%d, fl%d) = med.publish_all(&m, a, %s)" % (len(L), len(L), msg))
            L.append("    count(&trace, cn%d)" % (len(L) - 1))
    L.append("    let want = %s" % lit(expected))
    L.append("    if !str.eq(trace.buf[0usize..trace.n], want) {\n        show(trace.buf[0usize..trace.n], want)\n        ret false\n    }")
    L.append("    ret true\n}\n")
    return "\n".join(L)


def lit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


PRE = '''// `e.mediator` against an independent model of MediatR's documented semantics (scripts/gen_mediator_test.py):
// random scenarios of handlers, listeners and pipeline behaviors (pass-through, short circuit, failure, retry,
// recover), each rendered as source; the module's call trace must equal the model's. Then the stock behaviors,
// the task-pool entry, and the registration errors. Every check has its own exit code.
use e.io
use e.mediator as med
use e.mem
use e.os
use e.str
use e.task
use e.time

error Failed

type Trace = struct { buf: [512]u8, n: usize }
type Ctx = struct { trace: *Trace, id: u8, mode: u8, arg: u8, calls: u32, fail_first: u32 }

fn mark(t: *Trace, c: u8) {
    if t.n < 512usize {
        t.buf[t.n] = c
        t.n += 1usize
    }
}

fn mark2(t: *Trace, c: u8, id: u8) {
    mark(t, c)
    mark(t, 48u8 + id)
}

fn show(got: str, want: str) {
    let p = io.print("\\nGOT  ")
    let q = io.print(got)
    let r = io.print("\\nWANT ")
    let s = io.print(want)
    let u = io.print("\\n")
}

fn handler_run(ctx: *void, a: *mem.Arena, req: *const med.Message) -> (med.Message, err) {
    var c = mem.cast[*Ctx](ctx)
    c.calls += 1u32
    var none: med.Message = zero
    if c.mode == 1u8 || c.calls <= c.fail_first {
        mark2(c.trace, 120u8, c.id)
        ret (none, Failed)
    }
    mark2(c.trace, 72u8, c.id)
    let (b, e) = mem.alloc[u8](a, 1usize)
    if e != ok { ret (none, e) }
    b[0] = c.id + 100u8
    ret (med.Message{ kind: req.kind, data: b[0usize..1usize] }, ok)
}

fn listener_run(ctx: *void, a: *mem.Arena, note: *const med.Message) -> err {
    var c = mem.cast[*Ctx](ctx)
    mark2(c.trace, 76u8, c.id)
    if c.mode == 1u8 { ret Failed }
    ret ok
}

fn reply(a: *mem.Arena, kind: u32, value: u8) -> (med.Message, err) {
    var none: med.Message = zero
    let (b, e) = mem.alloc[u8](a, 1usize)
    if e != ok { ret (none, e) }
    b[0] = value
    ret (med.Message{ kind: kind, data: b[0usize..1usize] }, ok)
}

fn behavior_run(ctx: *void, a: *mem.Arena, req: *const med.Message, n: *const med.Next) -> (med.Message, err) {
    var c = mem.cast[*Ctx](ctx)
    var none: med.Message = zero
    if c.mode == 0u8 {
        mark2(c.trace, 97u8, c.id)
        let (r, e) = med.proceed(n, a, req)
        mark2(c.trace, 65u8, c.id)
        ret (r, e)
    }
    if c.mode == 1u8 {
        mark2(c.trace, 115u8, c.id)
        let (r, e) = reply(a, req.kind, c.arg)
        ret (r, e)
    }
    if c.mode == 2u8 {
        mark2(c.trace, 102u8, c.id)
        ret (none, Failed)
    }
    if c.mode == 3u8 {
        var last = none
        var failure = ok
        var i = 0u8
        var limit = c.arg
        if limit == 0u8 { limit = 1u8 }
        while i < limit {
            mark2(c.trace, 114u8, c.id)
            let (r, e) = med.proceed(n, a, req)
            if e == ok { ret (r, ok) }
            last = r
            failure = e
            i += 1u8
        }
        ret (last, failure)
    }
    mark2(c.trace, 99u8, c.id)
    let (r, e) = med.proceed(n, a, req)
    if e != ok {
        mark2(c.trace, 67u8, c.id)
        let (r2, e2) = reply(a, req.kind, c.arg)
        ret (r2, e2)
    }
    ret (r, e)
}

fn put3(t: *Trace, v: u8) {
    mark(t, 48u8 + v / 100u8)
    mark(t, 48u8 + (v / 10u8) % 10u8)
    mark(t, 48u8 + v % 10u8)
}

fn result(t: *Trace, r: med.Message, e: err) {
    if e == ok {
        mark(t, 61u8)
        put3(t, r.data[0])
        ret
    }
    mark(t, 33u8)
    if e == med.NoHandler { mark(t, 78u8) } else { mark(t, 70u8) }
}

fn note_result(t: *Trace, e: err) {
    if e == ok {
        mark(t, 61u8)
        mark(t, 111u8)
        mark(t, 107u8)
    } else {
        mark(t, 33u8)
        mark(t, 70u8)
    }
}

fn count(t: *Trace, n: usize) {
    mark(t, 61u8)
    mark(t, 48u8 + u8(n))
}

'''

POST = '''// ---- stock behaviors, the pool entry and registration errors ----
type Sink = struct { lines: [8]str, n: usize }

fn sink(ctx: *void, line: str) {
    var s = mem.cast[*Sink](ctx)
    if s.n < 8usize {
        s.lines[s.n] = line
        s.n += 1usize
    }
}

type Flaky = struct { fail: u32, seen: u32 }

fn flaky_handler(ctx: *void, a: *mem.Arena, req: *const med.Message) -> (med.Message, err) {
    var f = mem.cast[*Flaky](ctx)
    f.seen += 1u32
    if f.seen <= f.fail {
        var none: med.Message = zero
        ret (none, Failed)
    }
    let (r, e) = reply(a, req.kind, 7u8)
    ret (r, e)
}

fn deny_odd(ctx: *void, req: *const med.Message) -> err {
    if req.data.len > 0usize && req.data[0] % 2u8 == 1u8 { ret Failed }
    ret ok
}

fn stock(a: *mem.Arena) -> u32 {
    let one: [1]u8 = [1]u8{ 3 }
    let two: [1]u8 = [1]u8{ 4 }
    var flaky = Flaky{ fail: 2u32, seen: 0u32 }
    var retry = med.Retry{ attempts: 3u32 }
    var val = med.Validation{ ctx: mem.cast[*void](&flaky), check: deny_odd }
    var log = Sink{ lines: zero, n: 0usize }
    var logging = med.Logging{ ctx: mem.cast[*void](&log), sink: sink }
    let (m0, me) = med.mediator(a, 4usize, 4usize, 4usize)
    if me != ok { ret 1u32 }
    var m = m0
    if med.register(&m, 5u32, mem.cast[*void](&flaky), flaky_handler) != ok { ret 2u32 }
    // outermost first: logging, validation, retry
    if med.behave(&m, 0u32, mem.cast[*void](&logging), med.logging_run) != ok { ret 3u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&val), med.validation_run) != ok { ret 4u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&retry), med.retry_run) != ok { ret 5u32 }
    // an odd payload is refused before the handler is touched
    let (_, e1) = med.send(&m, a, med.Message{ kind: 5u32, data: one[0usize..1usize] })
    if e1 != Failed || flaky.seen != 0u32 { ret 6u32 }
    if log.n != 2usize || !str.eq(log.lines[0], "kind=5 start") || !str.eq(log.lines[1], "kind=5 failed") { ret 7u32 }
    // an even one fails twice and succeeds on the third try
    let (r2, e2) = med.send(&m, a, med.Message{ kind: 5u32, data: two[0usize..1usize] })
    if e2 != ok || r2.data[0] != 7u8 || flaky.seen != 3u32 { ret 8u32 }
    if log.n != 4usize || !str.eq(log.lines[3], "kind=5 ok") { ret 9u32 }
    // retry gives up after its attempts
    flaky.fail = 10u32
    flaky.seen = 0u32
    let (_, e3) = med.send(&m, a, med.Message{ kind: 5u32, data: two[0usize..1usize] })
    if e3 != Failed || flaky.seen != 3u32 { ret 10u32 }
    // an unregistered kind is NoHandler and runs no behavior
    let before = log.n
    let (_, e4) = med.send(&m, a, med.Message{ kind: 6u32, data: two[0usize..1usize] })
    if e4 != med.NoHandler || log.n != before { ret 11u32 }
    // a second handler for a kind, and a full table
    if med.register(&m, 5u32, mem.cast[*void](&flaky), flaky_handler) != med.Duplicate { ret 12u32 }
    let (e0, ee) = med.mediator(a, 0usize, 0usize, 0usize)
    if ee != ok { ret 13u32 }
    var empty = e0
    if med.register(&empty, 1u32, mem.cast[*void](&flaky), flaky_handler) != med.Full { ret 14u32 }
    if med.subscribe(&empty, 1u32, mem.cast[*void](&flaky), plain_listener) != med.Full { ret 15u32 }
    ret 0u32
}

fn plain_listener(ctx: *void, a: *mem.Arena, note_msg: *const med.Message) -> err { ret ok }

fn pool_entry(a: *mem.Arena) -> u32 {
    let (m0, me) = med.mediator(a, 2usize, 0usize, 0usize)
    if me != ok { ret 1u32 }
    var m = m0
    var flaky = Flaky{ fail: 0u32, seen: 0u32 }
    if med.register(&m, 9u32, mem.cast[*void](&flaky), flaky_handler) != ok { ret 2u32 }
    let (p0, pe) = task.pool(a, task.Options{ workers: 2u32, queue_capacity: 8usize, stack_size: 0usize })
    if pe != ok { ret 3u32 }
    var pool = p0
    var bytes1: [4096]u8 = zero
    var bytes2: [4096]u8 = zero
    var a1 = mem.arena_from(bytes1[0usize..4096usize])
    var a2 = mem.arena_from(bytes2[0usize..4096usize])
    let none: [1]u8 = [1]u8{ 0 }
    var j1 = med.SendJob{ mediator: &m, arena: &a1, request: med.Message{ kind: 9u32, data: none[0usize..0usize] } }
    var j2 = med.SendJob{ mediator: &m, arena: &a2, request: med.Message{ kind: 8u32, data: none[0usize..0usize] } }
    var cancel: task.Cancel = zero
    let (f1, e1) = task.future[med.Message, med.SendJob](&pool, &cancel, &j1, med.send_job)
    let (f2, e2) = task.future[med.Message, med.SendJob](&pool, &cancel, &j2, med.send_job)
    if e1 != ok || e2 != ok { ret 4u32 }
    var fa = f1
    var fb = f2
    let (r1, g1) = task.future_get[med.Message](&fa)
    let (r2, g2) = task.future_get[med.Message](&fb)
    let closed = task.close(&pool)
    if g1 != ok || r1.data[0] != 7u8 { ret 5u32 }
    if g2 != med.NoHandler { ret 6u32 }
    ret 0u32
}

fn main(a: *mem.Arena, args: []str) -> err {
%(calls)s
    let s = stock(a)
    if s != 0u32 { os.exit(i32(100u32 + s)) }
    let pl = pool_entry(a)
    if pl != 0u32 { os.exit(i32(120u32 + pl)) }
    try io.print("mediator ok")
    ret ok
}
'''


def main():
    rnd = random.Random(138)
    funcs, calls = [], []
    for k in range(60):
        sc = scenario(rnd)
        exp = Model(sc).run()
        funcs.append(render(sc, k, exp))
        calls.append("    if !case_%d(a) { os.exit(%di32) }" % (k, k + 1))
    src = PRE + "\n".join(funcs) + "\n" + POST.replace("%(calls)s", "\n".join(calls))
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    print("scenarios:", len(funcs))


main()
