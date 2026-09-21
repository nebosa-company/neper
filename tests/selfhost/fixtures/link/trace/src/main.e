// `e.trace`: the W3C spec example parses to the right bytes and formats
// back byte for byte, seven invalid variants are refused, a child header
// under a PCG-drawn span id and a fresh trace id match a Python replica,
// and tracestate get / set (move to front, replace, the 32-member cap,
// whitespace and empty members) agree with the replica. Each check exits
// with its own code.

use e.algo.rand
use e.io
use e.mem
use e.os
use e.str
use e.trace

fn main(a: *mem.Arena, args: []str) -> err {
    let example = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
    var out: [64]u8 = zero

    // 1: the spec example round trips.
    let (c, e1) = trace.parse_traceparent(example)
    if e1 != ok || c.trace_id[0usize] != 10u8 || c.trace_id[15usize] != 156u8 || c.span_id[0usize] != 183u8 || c.span_id[7usize] != 49u8 || c.flags != 1u8 { os.exit(1i32) }
    if !trace.sampled(&c) { os.exit(1i32) }
    let (n1, f1) = trace.format_traceparent(&c, out[..])
    if f1 != ok || n1 != 55usize || !str.eq(out[..n1], example) { os.exit(1i32) }
    let (_, small) = trace.format_traceparent(&c, out[..54usize])
    if small != trace.TooSmall { os.exit(1i32) }

    // 2: invalid variants.
    let (_, b1) = trace.parse_traceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-0")
    let (_, b2) = trace.parse_traceparent("00-0AF7651916CD43DD8448EB211C80319C-B7AD6B7169203331-01")
    let (_, b3) = trace.parse_traceparent("00-00000000000000000000000000000000-b7ad6b7169203331-01")
    let (_, b4) = trace.parse_traceparent("ff-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    let (_, b5) = trace.parse_traceparent("00-0af7651916cd43dd8448eb211c80319c-0000000000000000-01")
    let (_, b6) = trace.parse_traceparent("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01-")
    let (_, b7) = trace.parse_traceparent("00_0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
    if b1 != trace.Invalid || b2 != trace.Invalid || b3 != trace.Invalid || b4 != trace.Invalid || b5 != trace.Invalid || b6 != trace.Invalid || b7 != trace.Invalid { os.exit(2i32) }

    // 3: a child under a drawn span id, then a fresh trace.
    var r = rand.pcg64(11u64, 3u64)
    let sid = trace.span_id_from(&r)
    let (n3, e3) = trace.propagate(&c, sid[0..], out[..])
    if e3 != ok || !str.eq(out[..n3], "00-0af7651916cd43dd8448eb211c80319c-0c29e55c19dc60b7-01") { os.exit(3i32) }
    var fresh: trace.TraceContext = zero
    fresh.trace_id = trace.trace_id_from(&r)
    fresh.span_id = trace.span_id_from(&r)
    let (n3b, e3b) = trace.format_traceparent(&fresh, out[..])
    if e3b != ok || !str.eq(out[..n3b], "00-34a65a43128b1cce4c0ae402fa26e159-10aeb72f8c2d3406-00") { os.exit(3i32) }
    var zero_id: [8]u8 = zero
    let (_, e3c) = trace.propagate(&c, zero_id[0..], out[..])
    if e3c != trace.Invalid { os.exit(3i32) }

    // 4: tracestate get.
    let state = "rojo=00f067aa0ba902b7,congo=t61rcWkgMzE"
    let (v1, g1) = trace.tracestate_get(state, "congo")
    let (v2, g2) = trace.tracestate_get(state, "rojo")
    let (_, g3) = trace.tracestate_get(state, "nope")
    if !g1 || !str.eq(v1, "t61rcWkgMzE") || !g2 || !str.eq(v2, "00f067aa0ba902b7") || g3 { os.exit(4i32) }

    // 5: tracestate set moves to the front or replaces.
    var big: [512]u8 = zero
    let (n5, e5) = trace.tracestate_set(state, "congo", "ucfJifl5GOE", big[..])
    if e5 != ok || !str.eq(big[..n5], "congo=ucfJifl5GOE,rojo=00f067aa0ba902b7") { os.exit(5i32) }
    let (n5b, e5b) = trace.tracestate_set(state, "new", "v", big[..])
    if e5b != ok || !str.eq(big[..n5b], "new=v,rojo=00f067aa0ba902b7,congo=t61rcWkgMzE") { os.exit(5i32) }
    let (_, e5c) = trace.tracestate_set(state, "a,b", "v", big[..])
    let (_, e5d) = trace.tracestate_set(state, "new", "v", big[..10usize])
    if e5c != trace.Invalid || e5d != trace.TooSmall { os.exit(5i32) }

    // 6: thirty-two members k0=v0,...,k31=v31; setting x drops the last.
    var list: [512]u8 = zero
    var len = 0usize
    var i = 0usize
    while i < 32usize {
        if i > 0usize {
            list[len] = 44u8
            len += 1usize
        }
        list[len] = 107u8
        len += 1usize
        if i >= 10usize {
            list[len] = 48u8 + u8(i / 10usize)
            len += 1usize
        }
        list[len] = 48u8 + u8(i % 10usize)
        len += 1usize
        list[len] = 61u8
        len += 1usize
        list[len] = 118u8
        len += 1usize
        if i >= 10usize {
            list[len] = 48u8 + u8(i / 10usize)
            len += 1usize
        }
        list[len] = 48u8 + u8(i % 10usize)
        len += 1usize
        i += 1usize
    }
    let (n6, e6) = trace.tracestate_set(list[..len], "x", "y", big[..])
    if e6 != ok || n6 != 231usize { os.exit(6i32) }
    var commas = 0usize
    i = 0usize
    while i < n6 {
        if big[i] == 44u8 { commas += 1usize }
        i += 1usize
    }
    if commas != 31usize || !str.starts_with(big[..n6], "x=y,k0=v0,") || !str.eq(big[n6 - 7usize..n6], "k30=v30") { os.exit(6i32) }
    let (v6, g6) = trace.tracestate_get(list[..len], "k31")
    if !g6 || !str.eq(v6, "v31") { os.exit(6i32) }

    // 7: whitespace and empty members.
    let messy = " a=1 , b=2 ,,c=3"
    let (v7, g7) = trace.tracestate_get(messy, "b")
    if !g7 || !str.eq(v7, "2") { os.exit(7i32) }
    let (n7, e7) = trace.tracestate_set(messy, "c", "9", big[..])
    if e7 != ok || !str.eq(big[..n7], "c=9,a=1,b=2") { os.exit(7i32) }

    try io.print("trace ok\n")
    ret ok
}
