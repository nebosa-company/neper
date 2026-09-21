// `e.dist.clock`: Lamport and vector clocks over an LCG-driven exchange of
// ticks and sends between four nodes agree with a Python replay, vector
// comparison answers Before/After/Equal/Concurrent, and hybrid logical clocks
// follow the Kulkarni rules for local events and receipts. Each check exits
// with its own code.

use e.dist.clock
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var lam: [4]clock.Lamport = zero
    var vec: [16]u64 = zero
    var snap: [4]u64 = zero
    var first: [4]u64 = zero
    var first_to = 0usize
    var sent = 0usize
    var state = 7u64
    var step = 0usize
    while step < 60usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let from = usize((state >> 33u32) % 4u64)
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let kind = (state >> 33u32) % 3u64
        if kind == 1u64 {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            var to = usize((state >> 33u32) % 3u64)
            if to >= from { to += 1usize }
            let stamp = clock.lamport_send(&lam[from])
            let _ = clock.lamport_receive(&lam[to], stamp)
            let _ = clock.vector_tick(vec[from * 4usize..from * 4usize + 4usize], from)
            var i = 0usize
            while i < 4usize {
                snap[i] = vec[from * 4usize + i]
                i += 1usize
            }
            let _ = clock.vector_receive(vec[to * 4usize..to * 4usize + 4usize], snap[..], to)
            if sent == 0usize {
                i = 0usize
                while i < 4usize {
                    first[i] = snap[i]
                    i += 1usize
                }
                first_to = to
            }
            sent += 1usize
        } else {
            let _ = clock.lamport_tick(&lam[from])
            let _ = clock.vector_tick(vec[from * 4usize..from * 4usize + 4usize], from)
        }
        step += 1usize
    }

    // 1: Lamport times.
    if lam[0usize].time != 22u64 || lam[1usize].time != 23u64 || lam[2usize].time != 26u64 || lam[3usize].time != 24u64 { os.exit(1i32) }

    // 2: vector clocks.
    let want = [16]u64 { 18u64, 17u64, 7u64, 8u64, 17u64, 19u64, 7u64, 8u64, 15u64, 16u64, 18u64, 8u64, 13u64, 6u64, 9u64, 19u64 }
    var i = 0usize
    while i < 16usize {
        if vec[i] != want[i] { os.exit(2i32) }
        i += 1usize
    }

    // 3: comparison: every pair of final clocks is concurrent, a clock equals itself,
    // and the first send's stamp precedes its receiver's final clock.
    var p = 0usize
    while p < 4usize {
        var q = 0usize
        while q < 4usize {
            let o = clock.vector_cmp(vec[p * 4usize..p * 4usize + 4usize], vec[q * 4usize..q * 4usize + 4usize])
            if p == q && o != .Equal { os.exit(3i32) }
            if p != q && o != .Concurrent { os.exit(3i32) }
            q += 1usize
        }
        p += 1usize
    }
    if first_to != 1usize || first[3usize] != 1u64 { os.exit(3i32) }
    if clock.vector_cmp(first[..], vec[4usize..8usize]) != .Before { os.exit(3i32) }
    if clock.vector_cmp(vec[4usize..8usize], first[..]) != .After { os.exit(3i32) }
    let short = [2]u64 { 18u64, 17u64 }
    if clock.vector_cmp(short[..], vec[0usize..4usize]) != .Before { os.exit(3i32) }
    if clock.vector_cmp(vec[0usize..4usize], short[..]) != .After { os.exit(3i32) }

    // 4: hybrid logical clocks.
    var ha = clock.hlc()
    var hb = clock.hlc()
    let s1 = clock.hlc_now(&ha, 10u64)
    let s2 = clock.hlc_now(&ha, 10u64)
    let s3 = clock.hlc_now(&ha, 12u64)
    if s1.physical != 10u64 || s1.logical != 0u64 || s2.physical != 10u64 || s2.logical != 1u64 || s3.physical != 12u64 || s3.logical != 0u64 { os.exit(4i32) }
    let r1 = clock.hlc_receive(&hb, 5u64, clock.Hlc { physical: 12u64, logical: 2u64 })
    let r2 = clock.hlc_receive(&hb, 12u64, clock.Hlc { physical: 12u64, logical: 2u64 })
    let r3 = clock.hlc_receive(&hb, 20u64, clock.Hlc { physical: 12u64, logical: 9u64 })
    let r4 = clock.hlc_now(&hb, 20u64)
    let r5 = clock.hlc_receive(&hb, 20u64, clock.Hlc { physical: 30u64, logical: 0u64 })
    if r1.physical != 12u64 || r1.logical != 3u64 || r2.physical != 12u64 || r2.logical != 4u64 { os.exit(4i32) }
    if r3.physical != 20u64 || r3.logical != 0u64 || r4.physical != 20u64 || r4.logical != 1u64 || r5.physical != 30u64 || r5.logical != 1u64 { os.exit(4i32) }
    if clock.hlc_cmp(s1, s2) >= 0i32 || clock.hlc_cmp(s3, s2) <= 0i32 || clock.hlc_cmp(r4, r4) != 0i32 || clock.hlc_cmp(r3, r4) >= 0i32 { os.exit(4i32) }

    try io.print("dist clock ok\n")
    ret ok
}
