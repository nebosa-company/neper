// W3C Trace Context over caller storage: `parse_traceparent` reads a version
// 00 header into a `TraceContext` (exact lengths, lowercase hex, an all-zero
// id is invalid), `format_traceparent` writes one, `propagate` writes the
// child header a new span id gets under the same trace id and flags,
// `span_id_from` and `trace_id_from` draw non-zero ids from a generator, and
// `tracestate_get` / `tracestate_set` read and move-to-front a member of the
// tracestate list (at most 32 members, the last dropped when full).

use e.algo.rand
use e.str

type TraceContext = struct { trace_id: [16]u8, span_id: [8]u8, flags: u8 }
error Invalid
error TooSmall

const HEADER_LEN: usize = 55usize
const MAX_MEMBERS: usize = 32usize
const FLAG_SAMPLED: u8 = 1u8

fn nibble(c: u8) -> (u8, bool) {
    if c >= 48u8 && c <= 57u8 { ret (c - 48u8, true) }
    if c >= 97u8 && c <= 102u8 { ret (c - 87u8, true) }
    ret (0u8, false)
}

// Lowercase hex of `s[at..at + 2 * out.len]` into `out`; false unless every
// byte is a lowercase hex digit and at least one is non-zero.
fn unhex(s: str, at: usize, out: []u8) -> bool {
    var any = false
    var i = 0usize
    while i < out.len {
        let (high, high_ok) = nibble(s[at + 2usize * i])
        let (low, low_ok) = nibble(s[at + 2usize * i + 1usize])
        if !high_ok || !low_ok { ret false }
        out[i] = (high << 4u32) | low
        if out[i] != 0u8 { any = true }
        i += 1usize
    }
    ret any
}

fn hex(bytes: []const u8, out: []u8) {
    let digits = "0123456789abcdef"
    var i = 0usize
    while i < bytes.len {
        out[2usize * i] = digits[usize(bytes[i] >> 4u32)]
        out[2usize * i + 1usize] = digits[usize(bytes[i] & 15u8)]
        i += 1usize
    }
}

// `00-<32 hex>-<16 hex>-<2 hex>`, 55 bytes; version 00 only.
fn parse_traceparent(s: str) -> (TraceContext, err) {
    if s.len != HEADER_LEN || s[0usize] != 48u8 || s[1usize] != 48u8 || s[2usize] != 45u8 || s[35usize] != 45u8 || s[52usize] != 45u8 { ret (zero, Invalid) }
    var c: TraceContext = zero
    if !unhex(s, 3usize, c.trace_id[0..]) { ret (zero, Invalid) }
    if !unhex(s, 36usize, c.span_id[0..]) { ret (zero, Invalid) }
    var flags: [1]u8 = zero
    let (high, high_ok) = nibble(s[53usize])
    let (low, low_ok) = nibble(s[54usize])
    if !high_ok || !low_ok { ret (zero, Invalid) }
    flags[0usize] = (high << 4u32) | low
    c.flags = flags[0usize]
    ret (c, ok)
}

// The header of `c` into `out`; answers 55.
fn format_traceparent(c: *const TraceContext, out: []u8) -> (usize, err) {
    if out.len < HEADER_LEN { ret (0usize, TooSmall) }
    if all_zero(c.trace_id[0..]) || all_zero(c.span_id[0..]) { ret (0usize, Invalid) }
    out[0usize] = 48u8
    out[1usize] = 48u8
    out[2usize] = 45u8
    hex(c.trace_id[0..], out[3..35])
    out[35usize] = 45u8
    hex(c.span_id[0..], out[36..52])
    out[52usize] = 45u8
    var flag: [1]u8 = zero
    flag[0usize] = c.flags
    hex(flag[0..], out[53..55])
    ret (HEADER_LEN, ok)
}

fn all_zero(bytes: []const u8) -> bool {
    var i = 0usize
    while i < bytes.len {
        if bytes[i] != 0u8 { ret false }
        i += 1usize
    }
    ret true
}

// The child of `parent`: the same trace id and flags under `new_span_id` (8
// non-zero bytes); answers the child context and writes its header.
fn child(parent: *const TraceContext, new_span_id: []const u8) -> (TraceContext, err) {
    if new_span_id.len != 8usize || all_zero(new_span_id) { ret (zero, Invalid) }
    var c: TraceContext = zero
    var i = 0usize
    while i < 16usize {
        c.trace_id[i] = parent.trace_id[i]
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        c.span_id[i] = new_span_id[i]
        i += 1usize
    }
    c.flags = parent.flags
    ret (c, ok)
}

// The header an outgoing request carries for the child span `new_span_id`.
fn propagate(parent: *const TraceContext, new_span_id: []const u8, out: []u8) -> (usize, err) {
    let (c, child_error) = child(parent, new_span_id)
    if child_error != ok { ret (0usize, child_error) }
    let (n, e) = format_traceparent(&c, out)
    ret (n, e)
}

fn sampled(c: *const TraceContext) -> bool { ret (c.flags & FLAG_SAMPLED) != 0u8 }

// A non-zero span id from `r`.
fn span_id_from(r: *rand.Pcg64) -> [8]u8 {
    var id: [8]u8 = zero
    while true {
        fill(r, id[0..])
        if !all_zero(id[0..]) { break }
    }
    ret id
}

// A non-zero trace id from `r`.
fn trace_id_from(r: *rand.Pcg64) -> [16]u8 {
    var id: [16]u8 = zero
    while true {
        fill(r, id[0..])
        if !all_zero(id[0..]) { break }
    }
    ret id
}

fn fill(r: *rand.Pcg64, out: []u8) {
    var i = 0usize
    while i < out.len {
        let word = rand.pcg64_next(r)
        var k = 0usize
        while k < 8usize && i < out.len {
            out[i] = u8((word >> u32(8usize * k)) & 255u64)
            i += 1usize
            k += 1usize
        }
    }
}

// The next member of `state` from `at`: (key, value, end, found); empty
// members are skipped and OWS around the comma dropped.
fn member(state: str, at: usize) -> (str, str, usize, bool) {
    var start = at
    while start < state.len {
        var end = start
        while end < state.len && state[end] != 44u8 { end += 1usize }
        var lo = start
        var hi = end
        while lo < hi && (state[lo] == 32u8 || state[lo] == 9u8) { lo += 1usize }
        while hi > lo && (state[hi - 1usize] == 32u8 || state[hi - 1usize] == 9u8) { hi -= 1usize }
        var next_at = end
        if next_at < state.len { next_at += 1usize }
        if lo < hi {
            var eq = lo
            while eq < hi && state[eq] != 61u8 { eq += 1usize }
            if eq == hi { ret ("", "", next_at, false) }
            ret (state[lo..eq], state[eq + 1usize..hi], next_at, true)
        }
        start = next_at
    }
    ret ("", "", state.len, false)
}

// The value of `key` in `state`.
fn tracestate_get(state: str, key: str) -> (str, bool) {
    var at = 0usize
    while at < state.len {
        let (k, v, next_at, found) = member(state, at)
        if !found { ret ("", false) }
        if str.eq(k, key) { ret (v, true) }
        at = next_at
    }
    ret ("", false)
}

// `state` with `key=value` first and any earlier `key` removed, at most 32
// members (the last dropped when full); answers the length written.
fn tracestate_set(state: str, key: str, value: str, out: []u8) -> (usize, err) {
    if key.len == 0usize || key.len > 256usize || value.len == 0usize || value.len > 256usize { ret (0usize, Invalid) }
    var i = 0usize
    while i < key.len {
        if key[i] == 44u8 || key[i] == 61u8 || key[i] == 32u8 { ret (0usize, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < value.len {
        if value[i] == 44u8 || value[i] == 61u8 { ret (0usize, Invalid) }
        i += 1usize
    }
    var n = 0usize
    let (n1, e1) = append(out, n, key)
    if e1 != ok { ret (0usize, e1) }
    let (n2, e2) = append(out, n1, "=")
    if e2 != ok { ret (0usize, e2) }
    let (n3, e3) = append(out, n2, value)
    if e3 != ok { ret (0usize, e3) }
    n = n3
    var count = 1usize
    var at = 0usize
    while at < state.len && count < MAX_MEMBERS {
        let (k, v, next_at, found) = member(state, at)
        if !found { break }
        at = next_at
        if str.eq(k, key) { continue }
        let (m1, f1) = append(out, n, ",")
        if f1 != ok { ret (0usize, f1) }
        let (m2, f2) = append(out, m1, k)
        if f2 != ok { ret (0usize, f2) }
        let (m3, f3) = append(out, m2, "=")
        if f3 != ok { ret (0usize, f3) }
        let (m4, f4) = append(out, m3, v)
        if f4 != ok { ret (0usize, f4) }
        n = m4
        count += 1usize
    }
    ret (n, ok)
}

fn append(out: []u8, n: usize, s: str) -> (usize, err) {
    if out.len - n < s.len { ret (n, TooSmall) }
    var i = 0usize
    while i < s.len {
        out[n + i] = s[i]
        i += 1usize
    }
    ret (n + s.len, ok)
}
