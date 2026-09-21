// `e.data.stream`: over 200 LCG-jittered out-of-order events the emitted
// watermark sequence, the late count and the order and contents of the
// fired tumbling and sliding windows fold to the hashes a Python replica
// computed; a three-source merge with an idle source agrees likewise;
// sliding assignment lists the right starts. Each check exits with its
// own code.

use e.data.stream
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: tumbling windows of 100, lateness 30.
    var state = 11u64
    var w = stream.watermark(30u64)
    var slots: [16]stream.Window = zero
    let (wb, wb_error) = stream.window_buffer(100u64, 100u64, slots[..])
    if wb_error != ok { os.exit(1i32) }
    var b = wb
    var fired: [8]stream.Window = zero
    var hm = 0u64
    var hf = 0u64
    var fired_total = 0usize
    var late_flags = 0u64
    var i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let t = u64(i) * 10u64 + (state >> 33u32) % 60u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let v = (state >> 33u32) % 100u64
        if stream.watermark_is_late(&w, t) { late_flags += 1u64 }
        let mark = stream.watermark_observe(&w, t)
        hm = hm *% 1000003u64 +% mark
        if stream.window_add(&b, t, v, mark) != ok { os.exit(1i32) }
        let (n, fire_error) = stream.window_fire(&b, mark, fired[..])
        if fire_error != ok { os.exit(1i32) }
        var k = 0usize
        while k < n {
            hf = hf *% 1000003u64 +% fired[k].start
            hf = hf *% 1000003u64 +% fired[k].count
            hf = hf *% 1000003u64 +% fired[k].sum
            k += 1usize
        }
        fired_total += n
        i += 1usize
    }
    if hm != 3697081791380630709u64 || hf != 17716309852602219927u64 { os.exit(1i32) }
    if fired_total != 19usize || w.late != 15u64 || late_flags != 15u64 || b.late != 0u64 { os.exit(1i32) }
    if b.used != 2usize || stream.watermark_current(&w) != 1996u64 { os.exit(1i32) }

    // 2: sliding windows of 100 every 50.
    state = 12u64
    w = stream.watermark(30u64)
    let (sb, sb_error) = stream.window_buffer(100u64, 50u64, slots[..])
    if sb_error != ok { os.exit(2i32) }
    b = sb
    hm = 0u64
    hf = 0u64
    fired_total = 0usize
    late_flags = 0u64
    i = 0usize
    while i < 200usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let t = u64(i) * 10u64 + (state >> 33u32) % 60u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let v = (state >> 33u32) % 100u64
        if stream.watermark_is_late(&w, t) { late_flags += 1u64 }
        let mark = stream.watermark_observe(&w, t)
        hm = hm *% 1000003u64 +% mark
        if stream.window_add(&b, t, v, mark) != ok { os.exit(2i32) }
        let (n, fire_error) = stream.window_fire(&b, mark, fired[..])
        if fire_error != ok { os.exit(2i32) }
        var k = 0usize
        while k < n {
            hf = hf *% 1000003u64 +% fired[k].start
            hf = hf *% 1000003u64 +% fired[k].count
            hf = hf *% 1000003u64 +% fired[k].sum
            k += 1usize
        }
        fired_total += n
        i += 1usize
    }
    if hm != 12346241119193593260u64 || hf != 15153602589201518259u64 { os.exit(2i32) }
    if fired_total != 39usize || w.late != 12u64 || late_flags != 12u64 || b.late != 1u64 { os.exit(2i32) }
    if b.used != 2usize || stream.watermark_current(&w) != 2010u64 { os.exit(2i32) }
    // The watermark never decreases and an early event is not late before anything is seen.
    var fresh = stream.watermark(10u64)
    if stream.watermark_is_late(&fresh, 0u64) { os.exit(2i32) }
    if stream.watermark_observe(&fresh, 5u64) != 0u64 { os.exit(2i32) }
    if stream.watermark_observe(&fresh, 100u64) != 90u64 { os.exit(2i32) }
    if stream.watermark_observe(&fresh, 50u64) != 90u64 || fresh.late != 1u64 { os.exit(2i32) }

    // 3: merging three sources, the third going silent after 300.
    state = 13u64
    var marks: [3]u64 = zero
    var last: [3]u64 = zero
    let (mg, mg_error) = stream.merge(marks[..], last[..], 40u64)
    if mg_error != ok { os.exit(3i32) }
    var m = mg
    var now = 0u64
    var h = 0u64
    i = 0usize
    while i < 60usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        now += (state >> 33u32) % 15u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let src = usize((state >> 33u32) % 3u64)
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let lag = (state >> 33u32) % 5u64
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        var mk = now + (state >> 33u32) % 20u64
        if lag == 0u64 { mk = now / 4u64 }
        var merged = 0u64
        if src == 2usize && now > 300u64 {
            merged = stream.merge_at(&m, now)
        } else {
            let (value, update_error) = stream.merge_update(&m, src, mk, now)
            if update_error != ok { os.exit(3i32) }
            merged = value
        }
        h = h *% 1000003u64 +% merged
        i += 1usize
    }
    if h != 2800799856422157844u64 || m.mark != 371u64 || now != 389u64 { os.exit(3i32) }
    let (_, bad_source) = stream.merge_update(&m, 3usize, 0u64, now)
    if bad_source != stream.Invalid { os.exit(3i32) }

    // 4: sliding assignment and the argument checks.
    var starts: [4]u64 = zero
    let (n, starts_error) = stream.sliding_windows(175u64, 100u64, 30u64, starts[..])
    if starts_error != ok || n != 3usize || starts[0usize] != 150u64 || starts[1usize] != 120u64 || starts[2usize] != 90u64 { os.exit(4i32) }
    let (_, cramped) = stream.sliding_windows(175u64, 100u64, 30u64, starts[..2usize])
    if cramped != stream.TooSmall { os.exit(4i32) }
    if stream.window_start(175u64, 100u64) != 100u64 { os.exit(4i32) }
    let (_, bad_buffer) = stream.window_buffer(50u64, 100u64, slots[..])
    if bad_buffer != stream.Invalid { os.exit(4i32) }
    var one: [1]stream.Window = zero
    let (tiny, _) = stream.window_buffer(10u64, 10u64, one[..])
    var t1 = tiny
    if stream.window_add(&t1, 5u64, 1u64, 0u64) != ok { os.exit(4i32) }
    if stream.window_add(&t1, 15u64, 1u64, 0u64) != stream.TooSmall { os.exit(4i32) }

    try io.print("data stream ok\n")
    ret ok
}
