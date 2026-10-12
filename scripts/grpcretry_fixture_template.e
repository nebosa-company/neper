// `e.net.grpcretry` against an independent model of gRFC A6: scripts/grpcretry_vectors.py validates random retry
// policies and throttles, parses durations and pushback values, computes backoff ranges for supplied jitter and runs
// scripted sequences of failed attempts through the token bucket; each line is `kind TAB input TAB expected` and the
// fixture computes the same with the module. Generated; do not edit.
use e.fmt.json as json
use e.io
use e.mem
use e.net.grpcretry as retry
use e.os
use e.str

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(81) }
    ret out
}

fn dec(a: *mem.Arena, n: u64) -> str {
    let (b, e) = str.builder(a, 24usize)
    if e != ok { os.exit(82) }
    var out = b
    let p = str.push_u64(&out, n)
    ret str.done(&out)
}

fn number(s: str) -> u64 {
    var v = 0u64
    var at = 0usize
    while at < s.len {
        if s[at] >= 48u8 && s[at] <= 57u8 { v = v * 10u64 + u64(s[at] - 48u8) }
        at += 1usize
    }
    ret v
}

// The fields of a line split at `separator`.
fn split_fields(a: *mem.Arena, line: str, separator: u8) -> []str {
    let (out, e) = mem.alloc[str](a, line.len + 2usize)
    if e != ok { os.exit(83) }
    var count = 0usize
    var from = 0usize
    var at = 0usize
    while at <= line.len {
        if at == line.len || line[at] == separator {
            out[count] = line[from..at]
            count += 1usize
            from = at + 1usize
        }
        at += 1usize
    }
    ret out[0usize..count]
}

fn parse_config(a: *mem.Arena, text: str) -> json.Value {
    let (v, e) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 20u16 })
    if e != ok { os.exit(84) }
    ret v
}

fn policy_text(a: *mem.Arena, p: retry.Policy) -> str {
    var s = cat(a, "ok ", dec(a, u64(p.max_attempts)))
    s = cat(a, cat(a, s, " "), dec(a, p.initial_ns))
    s = cat(a, cat(a, s, " "), dec(a, p.max_ns))
    s = cat(a, cat(a, s, " "), dec(a, u64(p.multiplier * 1000.0f64 + 0.5f64)))
    ret cat(a, cat(a, s, " "), dec(a, u64(p.codes)))
}

fn good_policy(a: *mem.Arena, text: str) -> retry.Policy {
    let (p, e) = retry.policy_parse(parse_config(a, text))
    if e != ok { os.exit(85) }
    ret p
}

fn good_throttle(a: *mem.Arena, text: str) -> retry.Throttle {
    let (t, e) = retry.throttle_parse(parse_config(a, text))
    if e != ok { os.exit(86) }
    ret t
}

fn run_line(a: *mem.Arena, line: str) -> str {
    let f = split_fields(a, line, 9u8)
    let kind = f[0]
    if str.eq(kind, "P") {
        let (p, e) = retry.policy_parse(parse_config(a, f[1]))
        if e != ok { ret "invalid" }
        ret policy_text(a, p)
    }
    if str.eq(kind, "T") {
        let (t, e) = retry.throttle_parse(parse_config(a, f[1]))
        if e != ok { ret "invalid" }
        ret cat(a, cat(a, cat(a, "ok ", dec(a, u64(t.max_tokens * 1000.0f64))), " "), dec(a, u64(t.ratio * 1000.0f64 + 0.5f64)))
    }
    if str.eq(kind, "D") {
        let (v, e) = retry.parse_duration(f[1])
        if e != ok { ret "invalid" }
        ret dec(a, v)
    }
    if str.eq(kind, "H") {
        let (v, e) = retry.pushback_parse(f[1])
        if e != ok { ret "invalid" }
        ret dec(a, v)
    }
    if str.eq(kind, "B") {
        let p = good_policy(a, f[1])
        let n = u32(number(f[2]))
        let jitter = f64(number(f[3])) / 1000.0f64
        ret dec(a, retry.backoff_ns(&p, n, jitter))
    }
    if str.eq(kind, "S") {
        let p = good_policy(a, f[1])
        var t = good_throttle(a, f[2])
        let events = split_fields(a, f[3], 59u8)
        var out = ""
        var at = 0usize
        while at < events.len {
            let e = split_fields(a, events[at], 44u8)
            var push = ""
            var has_push = false
            if !str.eq(e[3], "-") {
                push = e[3]
                has_push = true
            }
            let d = retry.decide(&p, &t, u32(number(e[0])), u32(number(e[1])), number(e[2]) == 1u64, push, has_push, f64(number(e[4])) / 1000.0f64, number(e[5]), number(e[6]))
            var piece = cat(a, cat(a, d.reason, ":"), dec(a, d.delay_ns))
            piece = cat(a, cat(a, piece, ":"), dec(a, u64(t.tokens * 1000.0f64 + 0.5f64)))
            if at > 0usize { out = cat(a, out, ";") }
            out = cat(a, out, piece)
            at += 1usize
        }
        ret out
    }
    os.exit(89)
    ret ""
}

fn main(a: *mem.Arena, args: []str) -> err {
    let table = "@@VECTORS@@"
    var start = 0usize
    var at = 0usize
    var count = 0usize
    while at < table.len {
        if table[at] == 10u8 {
            let mark = mem.mark(a)
            let line = table[start..at]
            // the expected answer is the last field
            var last = line.len
            while last > 0usize && line[last - 1usize] != 9u8 { last -= 1usize }
            let want = line[last..line.len]
            let got = run_line(a, line[0usize..last - 1usize])
            if !str.eq(got, want) {
                let shown = io.print(cat(a, cat(a, cat(a, line, "\ngot  "), got), "\n"))
                os.exit(1)
            }
            mem.reset(a, mark)
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    if count != @@COUNT@@usize { os.exit(2) }
    try io.print("net grpcretry ok")
    ret ok
}
