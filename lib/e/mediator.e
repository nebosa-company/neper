// An in-process mediator in the shape of MediatR: a `send` of a request goes to the one
// handler registered for its kind, wrapped by the pipeline behaviors in registration order
// (the first registered is outermost); a `publish` of a notification goes to every listener
// of its kind in registration order. No broker and no reflection: a request type is a
// `u32` kind, its payload bytes, and a handler a context pointer plus a function, so a
// caller's typed layer is a cast in each. Distributed messaging stays with the queue and
// bus modules; this is the single-process seam.
//
// A behavior receives the request and a `Next`; it may call `proceed` zero times (a short
// circuit, validation failing), once (logging, timing) or several (retry). A behavior with
// `kind` 0 sees every request, otherwise only that kind. `publish` stops at the first
// listener that fails; `publish_all` runs them all and answers how many failed and the
// first error. `send_job` is the task-pool entry: `task.future[Message, SendJob]` turns one
// `send` into a future (give each job its own arena).
use e.mem
use e.str
use e.task

type Message = struct { kind: u32, data: []const u8 }
type Handler = struct { kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message) -> (Message, err) }
type Listener = struct { kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message) -> err }
type Behavior = struct { kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message, *const Next) -> (Message, err) }
type Mediator = struct { handlers: []Handler, listeners: []Listener, behaviors: []Behavior, handler_count: usize, listener_count: usize, behavior_count: usize }
type Next = struct { mediator: *const Mediator, position: usize, handler: *const Handler }
type SendJob = struct { mediator: *Mediator, arena: *mem.Arena, request: Message }
type Retry = struct { attempts: u32 }
type Validation = struct { ctx: *void, check: fn(*void, *const Message) -> err }
type Logging = struct { ctx: *void, sink: fn(*void, str) }
error NoHandler
error Duplicate
error Full

fn mediator(a: *mem.Arena, handlers: usize, listeners: usize, behaviors: usize) -> (Mediator, err) {
    var m: Mediator = zero
    let (h, he) = mem.alloc[Handler](a, handlers + 1usize)
    if he != ok { ret (m, he) }
    let (l, le) = mem.alloc[Listener](a, listeners + 1usize)
    if le != ok { ret (m, le) }
    let (b, be) = mem.alloc[Behavior](a, behaviors + 1usize)
    if be != ok { ret (m, be) }
    m.handlers = h[0usize..handlers]
    m.listeners = l[0usize..listeners]
    m.behaviors = b[0usize..behaviors]
    ret (m, ok)
}

// The handler of `kind`; a second one for the same kind is `Duplicate`.
fn register(m: *Mediator, kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message) -> (Message, err)) -> err {
    var i = 0usize
    while i < m.handler_count {
        if m.handlers[i].kind == kind { ret Duplicate }
        i += 1usize
    }
    if m.handler_count == m.handlers.len { ret Full }
    m.handlers[m.handler_count] = Handler{ kind: kind, ctx: ctx, run: run }
    m.handler_count += 1usize
    ret ok
}

fn subscribe(m: *Mediator, kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message) -> err) -> err {
    if m.listener_count == m.listeners.len { ret Full }
    m.listeners[m.listener_count] = Listener{ kind: kind, ctx: ctx, run: run }
    m.listener_count += 1usize
    ret ok
}

// A pipeline behavior for `kind`, or for every request with kind 0.
fn behave(m: *Mediator, kind: u32, ctx: *void, run: fn(*void, *mem.Arena, *const Message, *const Next) -> (Message, err)) -> err {
    if m.behavior_count == m.behaviors.len { ret Full }
    m.behaviors[m.behavior_count] = Behavior{ kind: kind, ctx: ctx, run: run }
    m.behavior_count += 1usize
    ret ok
}

// Continues the pipeline: the next behavior that applies, else the handler.
fn proceed(n: *const Next, a: *mem.Arena, req: *const Message) -> (Message, err) {
    var i = n.position
    while i < n.mediator.behavior_count {
        let b = n.mediator.behaviors[i]
        if b.kind == 0u32 || b.kind == req.kind {
            let next = Next{ mediator: n.mediator, position: i + 1usize, handler: n.handler }
            let (r, e) = b.run(b.ctx, a, req, &next)
            ret (r, e)
        }
        i += 1usize
    }
    let (r, e) = n.handler.run(n.handler.ctx, a, req)
    ret (r, e)
}

fn send(m: *const Mediator, a: *mem.Arena, req: Message) -> (Message, err) {
    var i = 0usize
    while i < m.handler_count {
        if m.handlers[i].kind == req.kind {
            let first = Next{ mediator: m, position: 0usize, handler: &m.handlers[i] }
            let (r, e) = proceed(&first, a, &req)
            ret (r, e)
        }
        i += 1usize
    }
    var none: Message = zero
    ret (none, NoHandler)
}

// Every listener of the notification's kind, in order; the first failure stops it.
fn publish(m: *const Mediator, a: *mem.Arena, note: Message) -> err {
    var i = 0usize
    while i < m.listener_count {
        if m.listeners[i].kind == note.kind {
            let e = m.listeners[i].run(m.listeners[i].ctx, a, &note)
            if e != ok { ret e }
        }
        i += 1usize
    }
    ret ok
}

// Every listener runs; the count of failures and the first error.
fn publish_all(m: *const Mediator, a: *mem.Arena, note: Message) -> (usize, err) {
    var failed = 0usize
    var first = ok
    var i = 0usize
    while i < m.listener_count {
        if m.listeners[i].kind == note.kind {
            let e = m.listeners[i].run(m.listeners[i].ctx, a, &note)
            if e != ok {
                if failed == 0usize { first = e }
                failed += 1usize
            }
        }
        i += 1usize
    }
    ret (failed, first)
}

// The body of a task-pool job: one `send`.
fn send_job(job: *SendJob, token: *const task.Cancel) -> (Message, err) {
    let (r, e) = send(job.mediator, job.arena, job.request)
    ret (r, e)
}

// ---- stock behaviors -----------------------------------------------------------------

// Retries a failing request up to `attempts` times in all (at least one), stopping early on
// success; the last error is the answer.
fn retry_run(ctx: *void, a: *mem.Arena, req: *const Message, n: *const Next) -> (Message, err) {
    let r = mem.cast[*Retry](ctx)
    var tries = 0u32
    var last: Message = zero
    var failure = ok
    while tries < r.attempts || tries == 0u32 {
        let (out, e) = proceed(n, a, req)
        tries += 1u32
        if e == ok {
            ret (out, ok)
        }
        last = out
        failure = e
    }
    ret (last, failure)
}

// Runs `check` before the handler and refuses the request with its error.
fn validation_run(ctx: *void, a: *mem.Arena, req: *const Message, n: *const Next) -> (Message, err) {
    let v = mem.cast[*Validation](ctx)
    let e = v.check(v.ctx, req)
    if e != ok {
        var none: Message = zero
        ret (none, e)
    }
    let (out, pe) = proceed(n, a, req)
    ret (out, pe)
}

// One `kind=N start` and one `kind=N ok|failed` line through the sink around the request.
fn logging_run(ctx: *void, a: *mem.Arena, req: *const Message, n: *const Next) -> (Message, err) {
    let l = mem.cast[*Logging](ctx)
    let (b0, be) = str.builder(a, 64usize)
    if be != ok {
        var none: Message = zero
        ret (none, be)
    }
    var b = b0
    let w1 = str.push(&b, "kind=")
    let w2 = str.push_u32(&b, req.kind)
    let w3 = str.push(&b, " start")
    l.sink(l.ctx, str.done(&b))
    let (out, e) = proceed(n, a, req)
    let (b1, be1) = str.builder(a, 64usize)
    if be1 != ok { ret (out, e) }
    var c = b1
    let x1 = str.push(&c, "kind=")
    let x2 = str.push_u32(&c, req.kind)
    if e == ok {
        let x3 = str.push(&c, " ok")
    } else {
        let x3 = str.push(&c, " failed")
    }
    l.sink(l.ctx, str.done(&c))
    ret (out, e)
}
