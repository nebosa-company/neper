// `e.net.grpccall` over a real HTTP/2 wire: the client `e.net.grpc` connection and the `e.net.grpcserver` connection are
// joined in memory on a virtual clock, the server answers each request (by arrival order) as its case scripts -- headers
// at `hlat`, the status at `lat`, a pushback or none -- and the call is carried out by the loop of the module: its START
// opens a stream, its CANCEL resets one, its WAIT advances the clock to the earlier of its instant and the next server
// answer. scripts/grpccall_vectors.py writes one JSON line per case: retry policy or hedging policy, throttle, per-attempt
// timeout, deadline and the server script, with the expected `{code, attempts, starts, cancelled, end}`. The retry cases
// without timing carry the counts grpcio itself produced against the same server script; the rest come from the model
// in the script (see its header).
use e.algo.chain as chain
use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.net.grpc as grpc
use e.net.grpccall as gc
use e.net.grpcretry as retry
use e.net.grpcserver as gs
use e.net.http2 as h2
use e.os
use e.str

type Behavior = struct { lat: u64, hlat: u64, headers: bool, code: u32, has_pushback: bool, pushback: str }

// One server answer to come: `kind` 0 is the response headers, 1 the message and status.
type Due = struct { at: u64, ordinal: u32, kind: u8, live: bool }

type Sim = struct {
    a: *mem.Arena,
    conn: grpc.Conn,
    srv: gs.Server,
    call: gc.Call,
    script: []Behavior,
    due: []Due,
    due_count: usize,
    streams: [8]u32,
    seen: u32,
    now: u64,
    jitter: f64,
    buf: []u8,
    events: []grpc.Event,
    hdr: []h2.Header,
    scratch: []u8,
    sevents: []gs.Event,
    shdr: []h2.Header,
    sscratch: []u8
}

fn num(v: json.Value, key: str) -> u64 {
    let (x, found) = ir.get(v, key)
    if !found { ret 0u64 }
    switch x {
    case .Number as n:
        let (value, e) = json.number_u64(n)
        if e != ok { ret 0u64 }
        ret value
    default:
        ret 0u64
    }
}

fn flag(v: json.Value, key: str) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret false }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret false
    }
}

fn new_client(a: *mem.Arena) -> grpc.Conn {
    let (streams, se) = mem.alloc[grpc.Stream](a, 8usize)
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    if se != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(97i32) }
    ret grpc.conn_new(streams, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
}

fn new_server(a: *mem.Arena) -> gs.Server {
    let (calls, ce) = mem.alloc[gs.Call](a, 8usize)
    if ce != ok { os.exit(98i32) }
    var c = 0usize
    while c < calls.len {
        let (buf, be) = mem.alloc[u8](a, 4096usize)
        if be != ok { os.exit(99i32) }
        calls[c].buf = buf
        c += 1usize
    }
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(100i32) }
    ret gs.server_new(calls, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
}

// The server's bytes arrive at the client: events go to the call.
fn to_client(sim: *Sim, data: []const u8) {
    var start = 0usize
    var reply: [512]u8 = zero
    while start < data.len {
        let (used, out_n, count, e) = grpc.conn_receive(&sim.conn, data[start..], reply[0usize..], sim.events, sim.hdr, sim.scratch)
        if e != ok { os.exit(101i32) }
        var k = 0usize
        while k < count {
            gc.call_event(&sim.call, &sim.events[k], sim.now, sim.jitter)
            k += 1usize
        }
        start += used
        if used == 0usize { break }
    }
}

fn schedule(sim: *Sim, ordinal: u32) {
    var b = sim.script[sim.script.len - 1usize]
    if usize(ordinal) < sim.script.len { b = sim.script[usize(ordinal)] }
    if b.headers && sim.due_count < sim.due.len {
        sim.due[sim.due_count] = Due { at: sim.now + b.hlat, ordinal: ordinal, kind: 0u8, live: true }
        sim.due_count += 1usize
    }
    if sim.due_count < sim.due.len {
        sim.due[sim.due_count] = Due { at: sim.now + b.lat, ordinal: ordinal, kind: 1u8, live: true }
        sim.due_count += 1usize
    }
}

// The client's bytes arrive at the server: a request schedules its answers, a reset drops them.
fn to_server(sim: *Sim, data: []const u8) {
    var start = 0usize
    var out: [1024]u8 = zero
    while start < data.len {
        let (used, out_n, count, e) = gs.server_receive(&sim.srv, data[start..], out[0usize..], sim.sevents, sim.shdr, sim.sscratch)
        if e != ok { os.exit(102i32) }
        var k = 0usize
        while k < count {
            let ev = sim.sevents[k]
            if ev.kind == gs.EVENT_REQUEST {
                if sim.seen < 8u32 { sim.streams[usize(sim.seen)] = ev.stream }
                schedule(sim, sim.seen)
                sim.seen += 1u32
            } else if ev.kind == gs.EVENT_RESET {
                var o = 0usize
                while o < usize(sim.seen) && o < 8usize {
                    if sim.streams[o] == ev.stream {
                        var d = 0usize
                        while d < sim.due_count {
                            if usize(sim.due[d].ordinal) == o { sim.due[d].live = false }
                            d += 1usize
                        }
                    }
                    o += 1usize
                }
            }
            k += 1usize
        }
        if out_n > 0usize { to_client(sim, out[0usize..out_n]) }
        start += used
        if used == 0usize && count == 0usize { break }
    }
}

// The earliest answer still due, or none.
fn next_due(sim: *Sim) -> (usize, bool) {
    var best = sim.due_count
    var d = 0usize
    while d < sim.due_count {
        if sim.due[d].live {
            var better = best == sim.due_count
            if !better && sim.due[d].at < sim.due[best].at { better = true }
            if !better && sim.due[d].at == sim.due[best].at && sim.due[d].ordinal < sim.due[best].ordinal { better = true }
            if !better && sim.due[d].at == sim.due[best].at && sim.due[d].ordinal == sim.due[best].ordinal && sim.due[d].kind < sim.due[best].kind { better = true }
            if better { best = d }
        }
        d += 1usize
    }
    ret (best, best < sim.due_count)
}

// Answer everything due at or before `now`.
fn serve_due(sim: *Sim) {
    while true {
        let (d, found) = next_due(sim)
        if !found { break }
        if sim.due[d].at > sim.now { break }
        sim.due[d].live = false
        let ordinal = sim.due[d].ordinal
        var b = sim.script[sim.script.len - 1usize]
        if usize(ordinal) < sim.script.len { b = sim.script[usize(ordinal)] }
        if usize(ordinal) >= 8usize { break }
        let id = sim.streams[usize(ordinal)]
        var out: [512]u8 = zero
        let none: []const h2.Header = zero
        if sim.due[d].kind == 0u8 {
            let (n, e) = gs.response_headers(&sim.srv, out[0usize..], id, none)
            if e != ok { os.exit(103i32) }
            to_client(sim, out[0usize..n])
        } else {
            var at = 0usize
            if b.code == 0u32 {
                let (n, e) = gs.response_message(&sim.srv, out[0usize..], id, "ok", false)
                if e != ok { os.exit(104i32) }
                at = n
            }
            var meta: [1]h2.Header = zero
            var count = 0usize
            if b.has_pushback {
                meta[0usize] = h2.Header { name: "grpc-retry-pushback-ms", value: b.pushback }
                count = 1usize
            }
            let (n2, e2) = gs.response_finish(&sim.srv, out[at..], id, b.code, "", meta[0usize..count])
            if e2 != ok { os.exit(105i32) }
            to_client(sim, out[0usize..at + n2])
        }
    }
}

fn code_mask(a: *mem.Arena, v: json.Value) -> u32 {
    let (xs, is_array) = ir.items_of(v)
    var mask = 0u32
    var i = 0usize
    while i < xs.len {
        switch xs[i] {
        case .Number as n:
            let (value, e) = json.number_u64(n)
            if e == ok && value <= 16u64 { mask = mask | (1u32 << u32(value)) }
        default:
            let nothing = 0u8
        }
        i += 1usize
    }
    ret mask
}

fn put_number(a: *mem.Arena, o: *ir.Obj, key: str, v: u64) {
    let (n, e) = json.number_from_u64(a, v)
    let p = ir.put(o, key, json.Value{ Number: n })
}

fn numbers(a: *mem.Arena, xs: []const u64) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, xs.len + 1usize)
    var i = 0usize
    while i < xs.len {
        let (n, ne) = json.number_from_u64(a, xs[i])
        out[i] = json.Value{ Number: n }
        i += 1usize
    }
    ret json.Value{ Array: out[0usize..xs.len] }
}

fn run_case(a: *mem.Arena, c: json.Value) -> bool {
    let (mode_value, has_mode) = ir.get(c, "mode")
    let (mode_text, is_text) = ir.string_of(mode_value)
    let hedged = str.eq(mode_text, "hedge")
    let (throttle_config, has_throttle) = ir.get(c, "throttle")
    let (throttle, throttle_error) = retry.throttle_parse(throttle_config)
    if throttle_error != ok { os.exit(110i32) }
    var bucket = throttle
    let per_attempt = num(c, "per_attempt_ns")
    let deadline = num(c, "deadline_ns")
    // the script
    let (items, is_array) = ir.items_of(ir.value_of(c, "server"))
    let (script, se) = mem.alloc[Behavior](a, items.len + 1usize)
    if se != ok { os.exit(111i32) }
    var i = 0usize
    while i < items.len {
        let (pb, has_pb) = ir.get(items[i], "pushback")
        let (pb_text, pb_is_text) = ir.string_of(pb)
        script[i] = Behavior { lat: num(items[i], "lat"), hlat: num(items[i], "hlat"), headers: flag(items[i], "headers"), code: u32(num(items[i], "code")), has_pushback: has_pb && pb_is_text, pushback: pb_text }
        i += 1usize
    }
    var call: gc.Call = zero
    if hedged {
        let hv = ir.value_of(c, "hedge")
        let h = gc.Hedging { max_attempts: u32(num(hv, "maxAttempts")), delay_ns: num(hv, "hedgingDelay_ns"), nonfatal: code_mask(a, ir.value_of(hv, "nonFatal")) }
        call = gc.call_hedge(h, &bucket, per_attempt, deadline, 0u64)
    } else {
        let (policy, policy_error) = retry.policy_parse(ir.value_of(c, "policy"))
        if policy_error != ok { os.exit(112i32) }
        call = gc.call_retry(policy, &bucket, per_attempt, deadline, 0u64)
    }
    let (buf, be) = mem.alloc[u8](a, 8192usize)
    let (events, ee) = mem.alloc[grpc.Event](a, 16usize)
    let (hdr, he) = mem.alloc[h2.Header](a, 64usize)
    let (scratch, sc) = mem.alloc[u8](a, 8192usize)
    let (sevents, see) = mem.alloc[gs.Event](a, 16usize)
    let (shdr, she) = mem.alloc[h2.Header](a, 64usize)
    let (sscratch, ssc) = mem.alloc[u8](a, 8192usize)
    let (due, de) = mem.alloc[Due](a, 32usize)
    if be != ok || ee != ok || he != ok || sc != ok || see != ok || she != ok || ssc != ok || de != ok { os.exit(113i32) }
    var sim = Sim { a: a, conn: new_client(a), srv: new_server(a), call: call, script: script[0usize..items.len], due: due, due_count: 0usize, streams: zero, seen: 0u32, now: 0u64, jitter: 0.5f64, buf: buf, events: events, hdr: hdr, scratch: scratch, sevents: sevents, shdr: shdr, sscratch: sscratch }
    // handshake: the client's preface and settings, the server's settings
    var open: [256]u8 = zero
    let (opened, open_error) = grpc.conn_start(&sim.conn, open[0usize..])
    if open_error != ok { os.exit(114i32) }
    to_server(&sim, open[0usize..opened])
    var sopen: [256]u8 = zero
    let (sopened, sopen_error) = gs.server_start(&sim.srv, sopen[0usize..])
    if sopen_error != ok { os.exit(115i32) }
    to_client(&sim, sopen[0usize..sopened])

    var starts: [8]u64 = zero
    var cancelled: [8]u64 = zero
    var started = 0usize
    var cancels = 0usize
    var code = 99u32
    var steps = 0usize
    while steps < 400usize {
        steps += 1usize
        serve_due(&sim)
        let act = gc.call_poll(&sim.call, sim.now, sim.jitter)
        if act.kind == gc.ACTION_START {
            if started < 8usize {
                starts[started] = sim.now
                started += 1usize
            }
            var wire: [1024]u8 = zero
            var none: [1]h2.Header = zero
            var rbuf: [1]u8 = zero
            let (rb, rbe) = mem.alloc[u8](a, 1024usize)
            if rbe != ok { os.exit(116i32) }
            let (id, n1, e1) = grpc.call_start(&sim.conn, wire[0usize..], "h", "/t.S/M", 0u64, none[0usize..0usize], rb)
            if e1 != ok { os.exit(117i32) }
            let (n2, e2) = grpc.call_send(&sim.conn, wire[n1..], id, "ping", false, true)
            if e2 != ok { os.exit(118i32) }
            gc.call_opened(&sim.call, act.attempt, id, sim.now)
            to_server(&sim, wire[0usize..n1 + n2])
        } else if act.kind == gc.ACTION_CANCEL {
            if cancels < 8usize {
                cancelled[cancels] = u64(act.attempt)
                cancels += 1usize
            }
            var wire: [64]u8 = zero
            let (n, e) = grpc.call_cancel(&sim.conn, wire[0usize..], act.stream)
            if e != ok { os.exit(119i32) }
            to_server(&sim, wire[0usize..n])
        } else if act.kind == gc.ACTION_WAIT {
            var wake = act.at_ns
            let (d, found) = next_due(&sim)
            if found {
                if wake == 0u64 || sim.due[d].at < wake { wake = sim.due[d].at }
            }
            if wake == 0u64 || wake < sim.now {
                code = 98u32
                break
            }
            sim.now = wake
        } else if act.kind == gc.ACTION_DONE {
            code = act.code
            break
        }
    }
    let want = ir.value_of(c, "e")
    let (made, me) = ir.new_obj(a)
    var got = made
    put_number(a, &got, "code", u64(code))
    put_number(a, &got, "attempts", u64(started))
    let p1 = ir.put(&got, "starts", numbers(a, starts[0usize..started]))
    let p2 = ir.put(&got, "cancelled", numbers(a, cancelled[0usize..cancels]))
    put_number(a, &got, "end", sim.now)
    let (got_text, ge) = chain.canonical_json(a, ir.obj_value(&got))
    let (want_text, we) = chain.canonical_json(a, want)
    if ge != ok || we != ok { ret false }
    if !str.eq(got_text, want_text) {
        let shown = io.print(f.join(a, f.join(a, "\nGOT  ", got_text), f.join(a, "\nWANT ", want_text)))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_case(a, root) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net grpccall ok")
    ret ok
}
