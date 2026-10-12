// `e.mediator` against an independent model of MediatR's documented semantics (scripts/gen_mediator_test.py):
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
    let p = io.print("\nGOT  ")
    let q = io.print(got)
    let r = io.print("\nWANT ")
    let s = io.print(want)
    let u = io.print("\n")
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

fn case_0(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 95u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let want = "#=0a4x0A4!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_1(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 2u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 82u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "=0a6x0A6!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_2(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let (cn22, fl22) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn22)
    let want = "=okL3L4=ok=ok=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_3(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 39u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let want = "!N=0=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_4(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 1u8, arg: 51u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 2u8, arg: 27u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 2u8, arg: 53u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 8u8, mode: 2u8, arg: 15u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let (cn29, fl29) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn29)
    let (rs31, er31) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs31, er31)
    let (cn33, fl33) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn33)
    let want = "#=0=0!NL4=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_5(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 85u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 4u8, arg: 51u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (cn20, fl20) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn20)
    let (rs22, er22) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs22, er22)
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let want = "=ok=0a3c4x0C4A3=051!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_6(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 3u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 2u8, arg: 80u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let (cn26, fl26) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn26)
    let (rs28, er28) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs28, er28)
    let want = "!N=0=okH1=101=0H1=101"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_7(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let want = "=0=0x2!F=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_8(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 88u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 18u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 75u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 5u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let want = "a4a6x0A6A4!F=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_9(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let want = "L5=ok=ok=okx2!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_10(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 4u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 1u8, arg: 74u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 2u8, arg: 41u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let want = "=0=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_11(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 12u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs15, er15) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs15, er15)
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let want = "#a2x0A2!F=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_12(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 37u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 10u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 2u8, arg: 65u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let want = "L3=0L3=0a4a5f6A5A4!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_13(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 1u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 66u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn15, fl15) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn15)
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    let want = "=0!Nr1a2x0A2r1a2x0A2r1a2x0A2!F=ok=ok=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_14(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 6u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let want = "L2=1!Ns3=006s3=006"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_15(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 42u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 0u8, arg: 88u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let want = "!N=0!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_16(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs13, er13) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs13, er13)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (cn16, fl16) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn16)
    let want = "#!N=ok=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_17(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let (cn26, fl26) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn26)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] }))
    let want = "x0!F=okH0=100=0=okL3L5=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_18(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 13u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 4u8, arg: 24u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 2u8, arg: 32u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let (rs31, er31) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs31, er31)
    let (rs33, er33) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs33, er33)
    let want = "a4c5H1A4=101!N!Nf6!Ff6!Ff6!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_19(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 32u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 51u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let (rs22, er22) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs22, er22)
    let want = "=0!N=ok!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_20(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs22, er22) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs22, er22)
    let want = "=ok!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_21(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [4]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    hc[3] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[3]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 4u8, arg: 33u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let want = "#=0=0!Nx1!F!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_22(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 9u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let want = "=ok!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_23(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 99u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let (rs18, er18) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs18, er18)
    let (cn20, fl20) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn20)
    let want = "#L2=ok!NL2=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_24(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 1u8, arg: 68u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let (rs26, er26) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs26, er26)
    let want = "#=0=ok!N!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_25(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 29u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] }))
    let (rs20, er20) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs20, er20)
    let (rs22, er22) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs22, er22)
    let want = "L2!F!N!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_26(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 2u8, arg: 14u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 2u8, arg: 99u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 0u8, arg: 53u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 8u8, mode: 0u8, arg: 44u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let want = "#f5!Ff5!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_27(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs15, er15) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs15, er15)
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] }))
    let (rs20, er20) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs20, er20)
    let (rs22, er22) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs22, er22)
    let want = "#H0=100!NL2=okH0=100!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_28(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 2u8, arg: 9u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 3u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let want = "=0!N=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_29(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "#=0!N!N!Nx1!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_30(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 81u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 3u8, mode: 4u8, arg: 67u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let want = "=0=okL1!F=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_31(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 95u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 81u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let want = "=0!N!N!N=0!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_32(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 63u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 2u8, mode: 4u8, arg: 47u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 91u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let (rs20, er20) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs20, er20)
    let (cn22, fl22) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn22)
    let (rs24, er24) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs24, er24)
    let (cn26, fl26) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn26)
    let want = "a1c2x0C2A1=047=ok!N=0!N=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_33(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 92u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 4u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 1u8, arg: 52u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 8u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs28, er28) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs28, er28)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs32, er32) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs32, er32)
    let want = "=oka5c6r8x2r8H2A5=102=ok=oka5c6r8H2A5=102"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_34(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 4u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 24u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "L3!F=okr5x0r5x0r5x0r5x0!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_35(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "!N=0=0!NH0=100"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_36(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 81u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let (rs14, er14) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs14, er14)
    let (rs16, er16) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs16, er16)
    let (rs18, er18) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs18, er18)
    let want = "=oks1=081s1=081!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_37(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 32u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 71u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let want = "=0x1!F=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_38(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 4u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 4u8, arg: 14u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 1u8, arg: 93u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let want = "#!NL3!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_39(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 2u8, arg: 52u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 1u8, arg: 81u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let want = "L2L3=0!NL2L3=0L2L3=okL1=ok!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_40(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 1u8, arg: 96u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 36u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "!Ns5=096"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_41(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 74u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let want = "!N=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_42(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 56u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 42u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 5u8, mode: 2u8, arg: 4u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 6u8, mode: 1u8, arg: 14u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let want = "#=0!N=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_43(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 4u8, arg: 71u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 16u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let want = "L3=1=ok=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_44(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 49u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 85u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 0u8, arg: 83u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 8u8, mode: 0u8, arg: 68u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let (rs32, er32) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs32, er32)
    let (cn34, fl34) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn34)
    let want = "=0a5a6a7a8x1A8A7A6A5!FL3!Fa5a6a7a8x0A8A7A6A5!F=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_45(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [4]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    hc[3] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[3]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 93u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 0u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "#a5x2A5!F!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_46(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 13u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 95u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 2u8, arg: 11u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let (rs31, er31) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs31, er31)
    let want = "H1=101H1=101!N!NH1=101"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_47(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 1u8, arg: 12u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 0u8, arg: 24u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] }))
    let (rs26, er26) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs26, er26)
    let (cn28, fl28) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn28)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (cn31, fl31) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn31)
    let want = "=ok!NL3L4=1=ok=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_48(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 46u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 54u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let want = "a4a5x2A5A4!Fa4a5x2A5A4!F"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_49(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 73u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 2u8, arg: 44u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] }))
    let want = "a3f4A3!F=ok=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_50(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 3u8, mode: 2u8, arg: 22u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn17, fl17) = med.publish_all(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    count(&trace, cn17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let want = "=0x0!F!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_51(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let want = "!N!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_52(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 7u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 1u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    let (rs29, er29) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs29, er29)
    let want = "!N!N=0L2L3=1!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_53(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [1]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 2u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 2u8, arg: 31u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (cn21, fl21) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn21)
    let want = "!N=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_54(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [3]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    lc[2] = Ctx{ trace: &trace, id: 4u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[2]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 5u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 6u8, mode: 4u8, arg: 20u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 7u8, mode: 2u8, arg: 24u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let (cn26, fl26) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn26)
    let want = "=ok=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_55(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [4]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 1u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 2u8, arg: 47u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 5u8, mode: 1u8, arg: 52u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 6u8, mode: 3u8, arg: 3u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    bc[3] = Ctx{ trace: &trace, id: 7u8, mode: 1u8, arg: 98u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[3]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let (cn27, fl27) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn27)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] }))
    let want = "f4!F=0=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_56(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [3]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 2u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    hc[2] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[2]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 4u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 1u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (rs25, er25) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs25, er25)
    let want = "=0x1!Fx1!FH0=100"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_57(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [2]Ctx = zero
    var bc: [1]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    lc[1] = Ctx{ trace: &trace, id: 3u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 2u32, mem.cast[*void](&lc[1]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 4u8, mode: 4u8, arg: 75u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs19, er19) = med.send(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    result(&trace, rs19, er19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let want = "!N!N"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_58(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [2]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 1u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.register(&m, 3u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    bc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 74u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 64u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 2u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs17, er17) = med.send(&m, a, med.Message{ kind: 2u32, data: none[0usize..0usize] })
    result(&trace, rs17, er17)
    let (cn19, fl19) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn19)
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (cn23, fl23) = med.publish_all(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    count(&trace, cn23)
    let want = "a2a3x0A3A2!F=0!N=0"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

fn case_59(a: *mem.Arena) -> bool {
    var trace = Trace{ buf: zero, n: 0usize }
    let (m0, me) = med.mediator(a, 8usize, 8usize, 8usize)
    if me != ok { ret false }
    var m = m0
    var hc: [2]Ctx = zero
    var lc: [1]Ctx = zero
    var bc: [3]Ctx = zero
    hc[0] = Ctx{ trace: &trace, id: 0u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 1u32, mem.cast[*void](&hc[0]), handler_run) != ok { mark(&trace, 35u8) }
    hc[1] = Ctx{ trace: &trace, id: 1u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 1u32 }
    if med.register(&m, 2u32, mem.cast[*void](&hc[1]), handler_run) != ok { mark(&trace, 35u8) }
    lc[0] = Ctx{ trace: &trace, id: 2u8, mode: 0u8, arg: 0u8, calls: 0u32, fail_first: 0u32 }
    if med.subscribe(&m, 4u32, mem.cast[*void](&lc[0]), listener_run) != ok { ret false }
    bc[0] = Ctx{ trace: &trace, id: 3u8, mode: 0u8, arg: 7u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 1u32, mem.cast[*void](&bc[0]), behavior_run) != ok { ret false }
    bc[1] = Ctx{ trace: &trace, id: 4u8, mode: 3u8, arg: 2u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[1]), behavior_run) != ok { ret false }
    bc[2] = Ctx{ trace: &trace, id: 5u8, mode: 0u8, arg: 77u8, calls: 0u32, fail_first: 0u32 }
    if med.behave(&m, 0u32, mem.cast[*void](&bc[2]), behavior_run) != ok { ret false }
    let none: [1]u8 = [1]u8{ 0 }
    let (rs21, er21) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs21, er21)
    let (rs23, er23) = med.send(&m, a, med.Message{ kind: 4u32, data: none[0usize..0usize] })
    result(&trace, rs23, er23)
    let (cn25, fl25) = med.publish_all(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] })
    count(&trace, cn25)
    let (rs27, er27) = med.send(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    result(&trace, rs27, er27)
    let (cn29, fl29) = med.publish_all(&m, a, med.Message{ kind: 3u32, data: none[0usize..0usize] })
    count(&trace, cn29)
    note_result(&trace, med.publish(&m, a, med.Message{ kind: 9u32, data: none[0usize..0usize] }))
    let want = "!N!N=0!N=0=ok"
    if !str.eq(trace.buf[0usize..trace.n], want) {
        show(trace.buf[0usize..trace.n], want)
        ret false
    }
    ret true
}

// ---- stock behaviors, the pool entry and registration errors ----
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
    if !case_0(a) { os.exit(1i32) }
    if !case_1(a) { os.exit(2i32) }
    if !case_2(a) { os.exit(3i32) }
    if !case_3(a) { os.exit(4i32) }
    if !case_4(a) { os.exit(5i32) }
    if !case_5(a) { os.exit(6i32) }
    if !case_6(a) { os.exit(7i32) }
    if !case_7(a) { os.exit(8i32) }
    if !case_8(a) { os.exit(9i32) }
    if !case_9(a) { os.exit(10i32) }
    if !case_10(a) { os.exit(11i32) }
    if !case_11(a) { os.exit(12i32) }
    if !case_12(a) { os.exit(13i32) }
    if !case_13(a) { os.exit(14i32) }
    if !case_14(a) { os.exit(15i32) }
    if !case_15(a) { os.exit(16i32) }
    if !case_16(a) { os.exit(17i32) }
    if !case_17(a) { os.exit(18i32) }
    if !case_18(a) { os.exit(19i32) }
    if !case_19(a) { os.exit(20i32) }
    if !case_20(a) { os.exit(21i32) }
    if !case_21(a) { os.exit(22i32) }
    if !case_22(a) { os.exit(23i32) }
    if !case_23(a) { os.exit(24i32) }
    if !case_24(a) { os.exit(25i32) }
    if !case_25(a) { os.exit(26i32) }
    if !case_26(a) { os.exit(27i32) }
    if !case_27(a) { os.exit(28i32) }
    if !case_28(a) { os.exit(29i32) }
    if !case_29(a) { os.exit(30i32) }
    if !case_30(a) { os.exit(31i32) }
    if !case_31(a) { os.exit(32i32) }
    if !case_32(a) { os.exit(33i32) }
    if !case_33(a) { os.exit(34i32) }
    if !case_34(a) { os.exit(35i32) }
    if !case_35(a) { os.exit(36i32) }
    if !case_36(a) { os.exit(37i32) }
    if !case_37(a) { os.exit(38i32) }
    if !case_38(a) { os.exit(39i32) }
    if !case_39(a) { os.exit(40i32) }
    if !case_40(a) { os.exit(41i32) }
    if !case_41(a) { os.exit(42i32) }
    if !case_42(a) { os.exit(43i32) }
    if !case_43(a) { os.exit(44i32) }
    if !case_44(a) { os.exit(45i32) }
    if !case_45(a) { os.exit(46i32) }
    if !case_46(a) { os.exit(47i32) }
    if !case_47(a) { os.exit(48i32) }
    if !case_48(a) { os.exit(49i32) }
    if !case_49(a) { os.exit(50i32) }
    if !case_50(a) { os.exit(51i32) }
    if !case_51(a) { os.exit(52i32) }
    if !case_52(a) { os.exit(53i32) }
    if !case_53(a) { os.exit(54i32) }
    if !case_54(a) { os.exit(55i32) }
    if !case_55(a) { os.exit(56i32) }
    if !case_56(a) { os.exit(57i32) }
    if !case_57(a) { os.exit(58i32) }
    if !case_58(a) { os.exit(59i32) }
    if !case_59(a) { os.exit(60i32) }
    let s = stock(a)
    if s != 0u32 { os.exit(i32(100u32 + s)) }
    let pl = pool_entry(a)
    if pl != 0u32 { os.exit(i32(120u32 + pl)) }
    try io.print("mediator ok")
    ret ok
}
