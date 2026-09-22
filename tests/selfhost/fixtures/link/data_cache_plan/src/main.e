// `e.data.cache` whole-policy access: ARC on hand-traced sequences (ghost hits
// move `p`, a scan does not flush the reused set that LRU loses), then all seven
// policies driven by the same LCG traces (a Zipf-ish key space and a hot set
// mixed with a rolling scan) at capacity 64, comparing hit and eviction counts
// and a fold of the resident set with a Python replica of each policy; ARC beats
// LRU on the hot-set-plus-scan trace. Each check exits with its own code.

use e.data.cache
use e.io
use e.mem
use e.os

fn fold(keys: []const u64) -> u64 {
    var f = 0u64
    var i = 0usize
    while i < keys.len {
        f = f ^ (keys[i] *% 11400714819323198485u64)
        i += 1usize
    }
    ret f
}

// Runs every policy over 5000 LCG accesses; `expected` holds hits, evictions
// and the resident fold per policy in the order LRU, FIFO, Clock, LFU, SLRU,
// 2Q, ARC.
fn run(seed: u64, hot: bool, expected: []const u64, code: i32) {
    var lkeys: [64]u64 = zero
    var lvalues: [64]u64 = zero
    var lprev: [64]u32 = zero
    var lnext: [64]u32 = zero
    var lindex: [128]u32 = zero
    var order: [64]u32 = zero
    var fkeys: [64]u64 = zero
    var referenced: [64]u8 = zero
    var cfilled: [64]u8 = zero
    var ckeys: [64]u64 = zero
    var hits: [64]u64 = zero
    var lfilled: [64]u8 = zero
    var fukeys: [64]u64 = zero
    var sprev: [64]u32 = zero
    var snext: [64]u32 = zero
    var protected: [64]u8 = zero
    var skeys: [64]u64 = zero
    var qprev: [64]u32 = zero
    var qnext: [64]u32 = zero
    var main_flags: [64]u8 = zero
    var ghosts: [64]u64 = zero
    var qkeys: [64]u64 = zero
    var akeys: [128]u64 = zero
    var alist: [128]u8 = zero
    var aprev: [132]u32 = zero
    var anext: [132]u32 = zero
    let (lru0, e1) = cache.lru_init(lkeys[..], lvalues[..], lprev[..], lnext[..], lindex[..], 64usize)
    let (fifo0, e2) = cache.fifo_init(order[..], 64usize)
    let (clock0, e3) = cache.clock_init(referenced[..], cfilled[..], 64usize)
    let (lfu0, e4) = cache.lfu_init(hits[..], lfilled[..], 64usize)
    let (slru0, e5) = cache.slru_init(sprev[..], snext[..], protected[..], 64usize, 32usize)
    let (two0, e6) = cache.two_queue_init(qprev[..], qnext[..], main_flags[..], ghosts[..], 64usize, 16usize)
    let (arc0, e7) = cache.arc_init(akeys[..], aprev[..], anext[..], alist[..], 64usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { os.exit(code) }
    var l = lru0
    var f = fifo0
    var ck = clock0
    var lf = lfu0
    var sl = slru0
    var q = two0
    var ac = arc0
    var got: [21]u64 = zero
    var state = seed
    var scan = 1000u64
    var n = 0usize
    while n < 5000usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = state >> 33u32
        var key = 0u64
        if hot {
            if r % 5u64 != 0u64 {
                key = 1u64 + (r >> 8u32) % 40u64
            } else {
                key = scan
                scan += 1u64
            }
        } else {
            let u = r % 1024u64
            key = 1u64 + (u * u) / 1024u64
        }
        let (h1, _, d1) = cache.lru(&l, key)
        let (h2, _, d2) = cache.fifo(&f, fkeys[..], key)
        let (h3, _, d3) = cache.clock(&ck, ckeys[..], key)
        let (h4, _, d4) = cache.lfu(&lf, fukeys[..], key)
        let (h5, _, d5) = cache.slru(&sl, skeys[..], key)
        let (h6, _, d6) = cache.two_queue(&q, qkeys[..], key)
        let (h7, _, d7) = cache.arc(&ac, key)
        if h1 { got[0usize] += 1u64 }
        if d1 { got[1usize] += 1u64 }
        if h2 { got[3usize] += 1u64 }
        if d2 { got[4usize] += 1u64 }
        if h3 { got[6usize] += 1u64 }
        if d3 { got[7usize] += 1u64 }
        if h4 { got[9usize] += 1u64 }
        if d4 { got[10usize] += 1u64 }
        if h5 { got[12usize] += 1u64 }
        if d5 { got[13usize] += 1u64 }
        if h6 { got[15usize] += 1u64 }
        if d6 { got[16usize] += 1u64 }
        if h7 { got[18usize] += 1u64 }
        if d7 { got[19usize] += 1u64 }
        n += 1usize
    }
    // Every policy is full after 5000 accesses, so the slot key slices are the resident sets.
    got[2usize] = fold(lkeys[..])
    got[5usize] = fold(fkeys[..])
    got[8usize] = fold(ckeys[..])
    got[11usize] = fold(fukeys[..])
    got[14usize] = fold(skeys[..])
    got[17usize] = fold(qkeys[..])
    var resident: [64]u64 = zero
    var count = 0usize
    var candidate = 1u64
    while candidate < 2200u64 {
        if cache.arc_contains(&ac, candidate) {
            if count >= 64usize { os.exit(code) }
            resident[count] = candidate
            count += 1usize
        }
        candidate += 1u64
    }
    if count != 64usize || cache.arc_len(&ac) != 64usize || cache.lru_len(&l) != 64usize { os.exit(code) }
    got[20usize] = fold(resident[..])
    var i = 0usize
    while i < 21usize {
        if got[i] != expected[i] { os.exit(code) }
        i += 1usize
    }
    // ARC beats LRU on the hot set mixed with a scan.
    if hot && got[18usize] <= got[0usize] { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: ARC at capacity 4, hand-traced against the paper's routine: ghost hits
    // on B1 raise `p`, the REPLACE victim follows it.
    var akeys: [8]u64 = zero
    var alist: [8]u8 = zero
    var aprev: [12]u32 = zero
    var anext: [12]u32 = zero
    let (arc0, arc_error) = cache.arc_init(akeys[..], aprev[..], anext[..], alist[..], 4usize)
    if arc_error != ok { os.exit(1i32) }
    var ac = arc0
    let seq = [11]u64{ 1u64, 2u64, 3u64, 4u64, 1u64, 2u64, 5u64, 6u64, 3u64, 4u64, 7u64 }
    let want_hit = [11]u8{ 0u8, 0u8, 0u8, 0u8, 1u8, 1u8, 0u8, 0u8, 0u8, 0u8, 0u8 }
    let want_evicted = [11]u64{ 0u64, 0u64, 0u64, 0u64, 0u64, 0u64, 3u64, 4u64, 5u64, 1u64, 2u64 }
    let want_p = [11]usize{ 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 1usize, 2usize, 2usize }
    var i = 0usize
    while i < 11usize {
        let (hit, evicted, did_evict) = cache.arc(&ac, seq[i])
        if hit != (want_hit[i] == 1u8) { os.exit(1i32) }
        if did_evict != (want_evicted[i] != 0u64) { os.exit(1i32) }
        if did_evict && evicted != want_evicted[i] { os.exit(1i32) }
        if cache.arc_p(&ac) != want_p[i] { os.exit(1i32) }
        i += 1usize
    }
    if cache.arc_len(&ac) != 4usize { os.exit(1i32) }
    if !cache.arc_contains(&ac, 3u64) || !cache.arc_contains(&ac, 4u64) || !cache.arc_contains(&ac, 6u64) || !cache.arc_contains(&ac, 7u64) { os.exit(1i32) }
    if cache.arc_contains(&ac, 1u64) || cache.arc_contains(&ac, 2u64) || cache.arc_contains(&ac, 5u64) { os.exit(1i32) }
    let (_, small_error) = cache.arc_init(akeys[..], aprev[..], anext[..], alist[..7usize], 4usize)
    if small_error != cache.TooSmall { os.exit(1i32) }
    let (_, zero_error) = cache.arc_init(akeys[..], aprev[..], anext[..], alist[..], 0usize)
    if zero_error != cache.Invalid { os.exit(1i32) }

    // 2: a scan of 40 fresh keys does not flush the four keys seen three more
    // times; LRU over the same accesses keeps only the scan's tail.
    var bkeys: [16]u64 = zero
    var blist: [16]u8 = zero
    var bprev: [20]u32 = zero
    var bnext: [20]u32 = zero
    let (arc8, arc8_error) = cache.arc_init(bkeys[..], bprev[..], bnext[..], blist[..], 8usize)
    if arc8_error != ok { os.exit(2i32) }
    var big = arc8
    var lkeys: [8]u64 = zero
    var lvalues: [8]u64 = zero
    var lprev: [8]u32 = zero
    var lnext: [8]u32 = zero
    var lindex: [16]u32 = zero
    let (lru8, lru8_error) = cache.lru_init(lkeys[..], lvalues[..], lprev[..], lnext[..], lindex[..], 8usize)
    if lru8_error != ok { os.exit(2i32) }
    var l = lru8
    var k = 1u64
    while k <= 8u64 {
        let (_, _, _) = cache.arc(&big, k)
        let (_, _, _) = cache.lru(&l, k)
        k += 1u64
    }
    var round = 0usize
    while round < 3usize {
        k = 1u64
        while k <= 4u64 {
            let (h, _, _) = cache.arc(&big, k)
            let (lh, _, _) = cache.lru(&l, k)
            if !h || !lh { os.exit(2i32) }
            k += 1u64
        }
        round += 1usize
    }
    var scan_hits = 0usize
    k = 100u64
    while k < 140u64 {
        let (h, _, _) = cache.arc(&big, k)
        let (_, _, _) = cache.lru(&l, k)
        if h { scan_hits += 1usize }
        k += 1u64
    }
    if scan_hits != 0usize || cache.arc_len(&big) != 8usize { os.exit(2i32) }
    k = 1u64
    while k <= 4u64 {
        if !cache.arc_contains(&big, k) || cache.lru_contains(&l, k) { os.exit(2i32) }
        k += 1u64
    }
    k = 136u64
    while k < 140u64 {
        if !cache.arc_contains(&big, k) || !cache.lru_contains(&l, k) { os.exit(2i32) }
        k += 1u64
    }
    if cache.arc_contains(&big, 135u64) || !cache.lru_contains(&l, 132u64) { os.exit(2i32) }

    // 3: hit_rate.
    if cache.hit_rate(0u64, 0u64) != 0.0f64 || cache.hit_rate(1u64, 4u64) != 0.25f64 { os.exit(3i32) }

    // 4: all seven policies over the Zipf-ish trace.
    let zipf = [21]u64{ 675u64, 4261u64, 16480146699040414128u64, 620u64, 4316u64, 18346626426852481176u64, 704u64, 4232u64, 12213867520483403494u64, 831u64, 4105u64, 10045865492747505351u64, 893u64, 4043u64, 6662617248368721928u64, 892u64, 4044u64, 12196622478250769288u64, 919u64, 4017u64, 13456566431768590349u64 }
    run(12345u64, false, zipf[..], 4i32)

    // 5: the hot set mixed with a rolling scan; ARC beats LRU.
    let hotscan = [21]u64{ 3746u64, 1190u64, 10809974419979947076u64, 3141u64, 1795u64, 15639730155369619773u64, 3876u64, 1060u64, 11137820809414297413u64, 3938u64, 998u64, 12046127039905927167u64, 3921u64, 1015u64, 1538500072320652676u64, 3947u64, 989u64, 5694124927875087976u64, 3985u64, 951u64, 5694124927875087976u64 }
    run(777u64, true, hotscan[..], 5i32)

    try io.print("data cache plan ok\n")
    ret ok
}
