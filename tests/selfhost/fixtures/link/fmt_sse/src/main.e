// `e.fmt.sse` against the HTML Living Standard's event-stream algorithm as an independent Python parser
// (scripts/gen_sse_test.py): whole streams field by field, then every prefix of every stream, counting the events
// the incremental reader dispatches. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.sse as sse

fn count_events(a: *mem.Arena, data: []const u8) -> usize {
    var at = 0usize
    var n = 0usize
    var more = true
    while more {
        let (ev, after, whole, e) = sse.next(a, data, at)
        if e != ok || !whole {
            more = false
        } else {
            at = after
            n += 1usize
        }
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let plain: [69]u8 = [69]u8{ 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 104u8, 101u8, 108u8, 108u8, 111u8, 10u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 97u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 98u8, 10u8, 10u8, 101u8, 118u8, 101u8, 110u8, 116u8, 58u8, 32u8, 112u8, 105u8, 110u8, 103u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 120u8, 10u8, 105u8, 100u8, 58u8, 32u8, 55u8, 10u8, 114u8, 101u8, 116u8, 114u8, 121u8, 58u8, 32u8, 51u8, 48u8, 48u8, 48u8, 10u8, 10u8 }
    var at_plain = 0usize
    let (ev_plain_0, after_plain_0, whole_plain_0, err_plain_0) = sse.next(a, plain[0..], at_plain)
    if err_plain_0 != ok || !whole_plain_0 { os.exit(1) }
    if !str.eq(ev_plain_0.kind, "") || !str.eq(ev_plain_0.data, "hello") { os.exit(2) }
    if ev_plain_0.has_id { os.exit(3) }
    if ev_plain_0.has_retry { os.exit(4) }
    at_plain = after_plain_0
    let (ev_plain_1, after_plain_1, whole_plain_1, err_plain_1) = sse.next(a, plain[0..], at_plain)
    if err_plain_1 != ok || !whole_plain_1 { os.exit(5) }
    if !str.eq(ev_plain_1.kind, "") || !str.eq(ev_plain_1.data, "a\nb") { os.exit(6) }
    if ev_plain_1.has_id { os.exit(7) }
    if ev_plain_1.has_retry { os.exit(8) }
    at_plain = after_plain_1
    let (ev_plain_2, after_plain_2, whole_plain_2, err_plain_2) = sse.next(a, plain[0..], at_plain)
    if err_plain_2 != ok || !whole_plain_2 { os.exit(9) }
    if !str.eq(ev_plain_2.kind, "ping") || !str.eq(ev_plain_2.data, "x") { os.exit(10) }
    if !ev_plain_2.has_id || !str.eq(ev_plain_2.id, "7") { os.exit(11) }
    if !ev_plain_2.has_retry || ev_plain_2.retry != 3000i64 { os.exit(12) }
    at_plain = after_plain_2
    let (ev_plain_end, after_plain_end, whole_plain_end, err_plain_end) = sse.next(a, plain[0..], at_plain)
    if whole_plain_end { os.exit(13) }
    let counts_plain: [70]u8 = [70]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 3u8 }
    var p_plain = 0usize
    while p_plain <= 69usize {
        if count_events(a, plain[0..p_plain]) != usize(counts_plain[p_plain]) { os.exit(14) }
        p_plain += 1usize
    }
    let mixed: [66]u8 = [66]u8{ 58u8, 32u8, 99u8, 111u8, 109u8, 109u8, 101u8, 110u8, 116u8, 13u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 110u8, 111u8, 32u8, 115u8, 112u8, 97u8, 99u8, 101u8, 13u8, 10u8, 13u8, 10u8, 101u8, 118u8, 101u8, 110u8, 116u8, 58u8, 101u8, 13u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 121u8, 13u8, 13u8, 58u8, 116u8, 97u8, 105u8, 108u8, 10u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 108u8, 97u8, 115u8, 116u8, 13u8, 10u8, 13u8, 10u8 }
    var at_mixed = 0usize
    let (ev_mixed_0, after_mixed_0, whole_mixed_0, err_mixed_0) = sse.next(a, mixed[0..], at_mixed)
    if err_mixed_0 != ok || !whole_mixed_0 { os.exit(15) }
    if !str.eq(ev_mixed_0.kind, "") || !str.eq(ev_mixed_0.data, "no space") { os.exit(16) }
    if ev_mixed_0.has_id { os.exit(17) }
    if ev_mixed_0.has_retry { os.exit(18) }
    at_mixed = after_mixed_0
    let (ev_mixed_1, after_mixed_1, whole_mixed_1, err_mixed_1) = sse.next(a, mixed[0..], at_mixed)
    if err_mixed_1 != ok || !whole_mixed_1 { os.exit(19) }
    if !str.eq(ev_mixed_1.kind, "e") || !str.eq(ev_mixed_1.data, "y") { os.exit(20) }
    if ev_mixed_1.has_id { os.exit(21) }
    if ev_mixed_1.has_retry { os.exit(22) }
    at_mixed = after_mixed_1
    let (ev_mixed_2, after_mixed_2, whole_mixed_2, err_mixed_2) = sse.next(a, mixed[0..], at_mixed)
    if err_mixed_2 != ok || !whole_mixed_2 { os.exit(23) }
    if !str.eq(ev_mixed_2.kind, "") || !str.eq(ev_mixed_2.data, "last") { os.exit(24) }
    if ev_mixed_2.has_id { os.exit(25) }
    if ev_mixed_2.has_retry { os.exit(26) }
    at_mixed = after_mixed_2
    let (ev_mixed_end, after_mixed_end, whole_mixed_end, err_mixed_end) = sse.next(a, mixed[0..], at_mixed)
    if whole_mixed_end { os.exit(27) }
    let counts_mixed: [67]u8 = [67]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 3u8 }
    var p_mixed = 0usize
    while p_mixed <= 66usize {
        if count_events(a, mixed[0..p_mixed]) != usize(counts_mixed[p_mixed]) { os.exit(28) }
        p_mixed += 1usize
    }
    let odd: [90]u8 = [90]u8{ 105u8, 100u8, 58u8, 32u8, 97u8, 0u8, 98u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 122u8, 10u8, 10u8, 114u8, 101u8, 116u8, 114u8, 121u8, 58u8, 32u8, 97u8, 98u8, 99u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 113u8, 10u8, 10u8, 102u8, 111u8, 111u8, 58u8, 32u8, 98u8, 97u8, 114u8, 10u8, 10u8, 100u8, 97u8, 116u8, 97u8, 10u8, 10u8, 114u8, 101u8, 116u8, 114u8, 121u8, 58u8, 32u8, 49u8, 53u8, 10u8, 101u8, 118u8, 101u8, 110u8, 116u8, 58u8, 32u8, 101u8, 50u8, 10u8, 10u8, 100u8, 97u8, 116u8, 97u8, 58u8, 32u8, 107u8, 101u8, 112u8, 116u8, 10u8, 105u8, 100u8, 58u8, 10u8, 10u8 }
    var at_odd = 0usize
    let (ev_odd_0, after_odd_0, whole_odd_0, err_odd_0) = sse.next(a, odd[0..], at_odd)
    if err_odd_0 != ok || !whole_odd_0 { os.exit(29) }
    if !str.eq(ev_odd_0.kind, "") || !str.eq(ev_odd_0.data, "z") { os.exit(30) }
    if ev_odd_0.has_id { os.exit(31) }
    if ev_odd_0.has_retry { os.exit(32) }
    at_odd = after_odd_0
    let (ev_odd_1, after_odd_1, whole_odd_1, err_odd_1) = sse.next(a, odd[0..], at_odd)
    if err_odd_1 != ok || !whole_odd_1 { os.exit(33) }
    if !str.eq(ev_odd_1.kind, "") || !str.eq(ev_odd_1.data, "q") { os.exit(34) }
    if ev_odd_1.has_id { os.exit(35) }
    if ev_odd_1.has_retry { os.exit(36) }
    at_odd = after_odd_1
    let (ev_odd_2, after_odd_2, whole_odd_2, err_odd_2) = sse.next(a, odd[0..], at_odd)
    if err_odd_2 != ok || !whole_odd_2 { os.exit(37) }
    if !str.eq(ev_odd_2.kind, "") || !str.eq(ev_odd_2.data, "") { os.exit(38) }
    if ev_odd_2.has_id { os.exit(39) }
    if ev_odd_2.has_retry { os.exit(40) }
    at_odd = after_odd_2
    let (ev_odd_3, after_odd_3, whole_odd_3, err_odd_3) = sse.next(a, odd[0..], at_odd)
    if err_odd_3 != ok || !whole_odd_3 { os.exit(41) }
    if !str.eq(ev_odd_3.kind, "") || !str.eq(ev_odd_3.data, "kept") { os.exit(42) }
    if !ev_odd_3.has_id || !str.eq(ev_odd_3.id, "") { os.exit(43) }
    if ev_odd_3.has_retry { os.exit(44) }
    at_odd = after_odd_3
    let (ev_odd_end, after_odd_end, whole_odd_end, err_odd_end) = sse.next(a, odd[0..], at_odd)
    if whole_odd_end { os.exit(45) }
    let counts_odd: [91]u8 = [91]u8{ 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 3u8, 4u8 }
    var p_odd = 0usize
    while p_odd <= 90usize {
        if count_events(a, odd[0..p_odd]) != usize(counts_odd[p_odd]) { os.exit(46) }
        p_odd += 1usize
    }
    ret ok
}
