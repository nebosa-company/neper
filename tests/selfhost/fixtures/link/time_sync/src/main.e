// `e.time.sync`: Marzullo's interval on a hand set and on forty LCG-drawn
// sets (a checksum of the interval and count against a Python replica
// checked against brute force), the midpoint estimate, Berkeley's
// adjustments with an outlier dropped, and Cristian's estimate and bound.
// Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.time.sync

fn main(a: *mem.Arena, args: []str) -> err {
    var scratch: [64]i64 = zero
    var lows: [16]i64 = zero
    var highs: [16]i64 = zero

    // 1: the hand set [8,12] [11,13] [14,15].
    lows[0usize] = 8i64
    highs[0usize] = 12i64
    lows[1usize] = 11i64
    highs[1usize] = 13i64
    lows[2usize] = 14i64
    highs[2usize] = 15i64
    let (lo, hi, best, e1) = sync.marzullo(lows[..], highs[..], 3usize, scratch[..])
    if e1 != ok || lo != 11i64 || hi != 12i64 || best != 2usize { os.exit(1i32) }
    let (_, _, _, small) = sync.marzullo(lows[..], highs[..], 3usize, scratch[..11usize])
    if small != sync.TooSmall { os.exit(1i32) }
    let (_, _, _, none) = sync.marzullo(lows[..], highs[..], 0usize, scratch[..])
    if none != sync.Invalid { os.exit(1i32) }

    // 2: forty LCG sets, checksum of (lo, hi, best).
    var state = 7u64
    var acc = 0u64
    var r = 0usize
    while r < 40usize {
        let n = 1usize + r % 10usize
        var i = 0usize
        while i < n {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            let low = i64((state >> 33u32) % 100u64)
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            lows[i] = low
            highs[i] = low + i64((state >> 33u32) % 30u64)
            i += 1usize
        }
        let (l, h, b, e) = sync.marzullo(lows[..], highs[..], n, scratch[..])
        if e != ok { os.exit(2i32) }
        acc = (acc *% 31u64 +% u64(l) *% 1000003u64 +% u64(h) *% 1009u64 +% u64(b)) & 4294967295u64
        r += 1usize
    }
    if acc != 2581745290u64 { os.exit(2i32) }

    // 3: the midpoint estimate of the hand set.
    lows[0usize] = 8i64
    highs[0usize] = 12i64
    lows[1usize] = 11i64
    highs[1usize] = 13i64
    lows[2usize] = 14i64
    highs[2usize] = 15i64
    let (mid, e3) = sync.marzullo_estimate(lows[..], highs[..], 3usize, scratch[..])
    if e3 != ok || mid != 11i64 { os.exit(3i32) }

    // 4: Berkeley with the 300 outlier dropped, then a negative outlier.
    var offsets: [6]i64 = zero
    offsets[1usize] = 25i64
    offsets[2usize] = -10i64
    offsets[3usize] = 300i64
    offsets[4usize] = 15i64
    offsets[5usize] = -5i64
    var out: [6]i64 = zero
    if sync.berkeley(offsets[..], 6usize, 50i64, out[..]) != ok { os.exit(4i32) }
    if out[0usize] != 5i64 || out[1usize] != -20i64 || out[2usize] != 15i64 || out[3usize] != -295i64 || out[4usize] != -10i64 || out[5usize] != 10i64 { os.exit(4i32) }
    offsets[0usize] = -7i64
    offsets[1usize] = 3i64
    offsets[2usize] = 9i64
    offsets[3usize] = -100i64
    offsets[4usize] = 4i64
    if sync.berkeley(offsets[..], 5usize, 20i64, out[..]) != ok { os.exit(4i32) }
    if out[0usize] != 9i64 || out[1usize] != -1i64 || out[2usize] != -7i64 || out[3usize] != 102i64 || out[4usize] != -2i64 { os.exit(4i32) }
    if sync.berkeley(offsets[..], 5usize, 20i64, out[..4usize]) != sync.TooSmall { os.exit(4i32) }

    // 5: Cristian.
    let (adjusted, bound) = sync.cristian(1000i64, 5000i64, 1080i64, 10i64)
    if adjusted != 5040i64 || bound != 30i64 { os.exit(5i32) }
    let (adjusted2, bound2) = sync.cristian(0i64, 77i64, 21i64, 20i64)
    if adjusted2 != 87i64 || bound2 != 0i64 { os.exit(5i32) }

    try io.print("time sync ok\n")
    ret ok
}
