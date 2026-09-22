// The D882 additions to `e.algo.sort` and `e.algo.rand` against a Python
// reference: every named sorter reproduces `stable_in_place` on forty LCG records
// with sixteen distinct keys (the stable ones down to the sequence numbers), cycle
// sort's write count, patience sort's pile count, a byte-row radix, a three-run
// external merge, three-way string quicksort, then the LCG, xorshift64*, and LFSR
// streams, the alias table, stratified and Latin hypercube draws, A-Res and its
// time-decayed form, priority sampling and VarOpt over bit-exact PCG64 replicas.
// Each check exits with its own code.

use e.algo.rand
use e.algo.sort
use e.io
use e.mem
use e.os

type Rec = struct { key: i64, seq: i64 }
type Gen = struct { state: u64 }
type Unit = struct { calls: usize }

fn rec_cmp(a: Rec, b: Rec) -> i32 {
    if a.key < b.key { ret 0i32 - 1i32 }
    if a.key > b.key { ret 1i32 }
    ret 0i32
}

fn draw(g: *Gen) -> u64 {
    g.state = g.state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret g.state >> 33u32
}

fn fill(recs: []Rec) {
    var g = Gen { state: 7u64 }
    var i = 0usize
    while i < recs.len {
        recs[i] = Rec { key: i64(draw(&g) % 16u64), seq: i64(i) }
        i += 1usize
    }
}

// Same keys in order; with `with_seq` the same records outright.
fn same(a: []const Rec, b: []const Rec, with_seq: bool) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i].key != b[i].key { ret false }
        if with_seq && a[i].seq != b[i].seq { ret false }
        i += 1usize
    }
    ret true
}

fn key_u32(c: *Unit, r: Rec) -> u32 {
    c.calls += 1usize
    ret u32(r.key)
}

fn key_f64(c: *Unit, r: Rec) -> f64 {
    c.calls += 1usize
    ret f64(r.key) / 16.0f64
}

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 0.000000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var reference: [40]Rec = zero
    fill(reference[..])
    try sort.stable_in_place[Rec](a, reference[..])
    var h = 0u64
    var i = 0usize
    while i < 40usize {
        h = h *% 31u64 +% u64(reference[i].seq)
        i += 1usize
    }
    if h != 12760092286460015662u64 { os.exit(1i32) }
    var recs: [40]Rec = zero
    var scratch: [40]Rec = zero
    var unit = Unit { calls: 0usize }

    // 2: insertion, stable.
    fill(recs[..])
    sort.insertion[Rec](recs[..])
    if !same(recs[..], reference[..], true) { os.exit(2i32) }

    // 3: shell.
    fill(recs[..])
    sort.shell[Rec](recs[..])
    if !same(recs[..], reference[..], false) { os.exit(3i32) }

    // 4: heap.
    fill(recs[..])
    sort.heap[Rec](recs[..])
    if !same(recs[..], reference[..], false) { os.exit(4i32) }

    // 5: merge, stable, through a caller scratch that must be long enough.
    fill(recs[..])
    if sort.merge[Rec](recs[..], scratch[..39usize]) != sort.TooSmall { os.exit(5i32) }
    if sort.merge[Rec](recs[..], scratch[..]) != ok { os.exit(5i32) }
    if !same(recs[..], reference[..], true) { os.exit(5i32) }

    // 6: quick.
    fill(recs[..])
    sort.quick[Rec](recs[..])
    if !same(recs[..], reference[..], false) { os.exit(6i32) }

    // 7: cycle, and the number of writes it took.
    fill(recs[..])
    if sort.cycle[Rec](recs[..]) != 35usize { os.exit(7i32) }
    if !same(recs[..], reference[..], false) { os.exit(7i32) }
    if sort.cycle[Rec](recs[..]) != 0usize { os.exit(7i32) }

    // 8: patience, stable, and the pile count is the longest non-decreasing run.
    var below: [40]usize = zero
    var tops: [40]usize = zero
    fill(recs[..])
    let (piles, piles_error) = sort.patience[Rec](recs[..], scratch[..], below[..], tops[..])
    if piles_error != ok || piles != 11usize { os.exit(8i32) }
    if !same(recs[..], reference[..], true) { os.exit(8i32) }
    let (_, tight) = sort.patience[Rec](recs[..], scratch[..], below[..39usize], tops[..])
    if tight != sort.TooSmall { os.exit(8i32) }

    // 9: counting by a u32 key below a bound, stable.
    var counts: [16]usize = zero
    fill(recs[..])
    if sort.counting[Rec, Unit](recs[..], scratch[..], &unit, key_u32, 8u32, counts[..]) != sort.Invalid { os.exit(9i32) }
    if sort.counting[Rec, Unit](recs[..], scratch[..], &unit, key_u32, 16u32, counts[..]) != ok { os.exit(9i32) }
    if !same(recs[..], reference[..], true) || unit.calls == 0usize { os.exit(9i32) }
    if sort.counting[Rec, Unit](recs[..], scratch[..], &unit, key_u32, 16u32, counts[..15usize]) != sort.TooSmall { os.exit(9i32) }

    // 10: bucket by an f64 key in [0, 1), stable, and the boundaries it leaves.
    var starts: [5]usize = zero
    fill(recs[..])
    if sort.bucket[Rec, Unit](recs[..], scratch[..], &unit, key_f64, starts[..]) != ok { os.exit(10i32) }
    if !same(recs[..], reference[..], true) { os.exit(10i32) }
    if starts[0usize] != 0usize || starts[4usize] != 40usize { os.exit(10i32) }
    if recs[starts[1usize]].key < 4i64 || recs[starts[1usize] - 1usize].key >= 4i64 { os.exit(10i32) }

    // 11: radix over byte rows keyed on their first two bytes; the third is the
    // row number and shows the stability.
    var rows: [72]u8 = zero
    var row_scratch: [72]u8 = zero
    var g = Gen { state: 11u64 }
    i = 0usize
    while i < 24usize {
        let d = draw(&g)
        rows[i * 3usize] = u8(d & 3u64)
        rows[i * 3usize + 1usize] = u8((d >> 8u32) & 255u64)
        rows[i * 3usize + 2usize] = u8(i)
        i += 1usize
    }
    if sort.radix_bytes(rows[..], 3usize, 2usize, row_scratch[..71usize]) != sort.TooSmall { os.exit(11i32) }
    if sort.radix_bytes(rows[..], 3usize, 4usize, row_scratch[..]) != sort.Invalid { os.exit(11i32) }
    if sort.radix_bytes(rows[..], 3usize, 2usize, row_scratch[..]) != ok { os.exit(11i32) }
    h = 0u64
    i = 0usize
    while i < 72usize {
        h = h *% 31u64 +% u64(rows[i])
        i += 1usize
    }
    if h != 17859605699903277614u64 || rows[0usize] != 0u8 || rows[1usize] != 98u8 || rows[2usize] != 22u8 { os.exit(11i32) }

    // 12: three sorted runs merged through a heap of run indices, ties to the
    // earlier run, which is the stable sort of the whole.
    var bounds: [4]usize = zero
    bounds[1usize] = 13usize
    bounds[2usize] = 27usize
    bounds[3usize] = 40usize
    var cursor: [3]usize = zero
    var run_heap: [3]usize = zero
    fill(recs[..])
    if sort.merge[Rec](recs[..13usize], scratch[..]) != ok { os.exit(12i32) }
    if sort.merge[Rec](recs[13usize..27usize], scratch[..]) != ok { os.exit(12i32) }
    if sort.merge[Rec](recs[27usize..40usize], scratch[..]) != ok { os.exit(12i32) }
    if sort.external_merge[Rec](recs[..], bounds[..], cursor[..], run_heap[..], scratch[..]) != ok { os.exit(12i32) }
    if !same(scratch[..], reference[..], true) { os.exit(12i32) }
    if sort.external_merge[Rec](recs[..], bounds[..], cursor[..2usize], run_heap[..], scratch[..]) != sort.TooSmall { os.exit(12i32) }
    bounds[2usize] = 12usize
    if sort.external_merge[Rec](recs[..], bounds[..], cursor[..], run_heap[..], scratch[..]) != sort.Invalid { os.exit(12i32) }

    // 13: strings in byte order.
    var words: [12]str = zero
    words[0usize] = "pear"
    words[1usize] = "apple"
    words[2usize] = ""
    words[3usize] = "app"
    words[4usize] = "banana"
    words[5usize] = "apples"
    words[6usize] = "Zed"
    words[7usize] = "zed"
    words[8usize] = "ba"
    words[9usize] = "bananas"
    words[10usize] = "apple"
    words[11usize] = "b"
    sort.strings(words[..])
    h = 0u64
    i = 0usize
    while i < 12usize {
        var c = 0usize
        while c < words[i].len {
            h = h *% 31u64 +% u64(words[i][c])
            c += 1usize
        }
        h = h *% 31u64
        i += 1usize
    }
    if h != 4189876448528273602u64 || words[0usize].len != 0usize || words[1usize].len != 3usize || words[11usize].len != 3usize { os.exit(13i32) }

    // 14: the MMIX LCG.
    var l = rand.lcg(1u64)
    if rand.lcg_next(&l) != 7806831264735756412u64 || rand.lcg_next(&l) != 9396908728118811419u64 || rand.lcg_next(&l) != 11960119808228829710u64 { os.exit(14i32) }

    // 15: xorshift64*, and a zero seed is replaced.
    var x = rand.xorshift(1u64)
    if rand.xorshift_next(&x) != 5180492295206395165u64 || rand.xorshift_next(&x) != 12380297144915551517u64 || rand.xorshift_next(&x) != 13389498078930870103u64 { os.exit(15i32) }
    var xz = rand.xorshift(0u64)
    if rand.xorshift_next(&xz) != 973819730272012410u64 { os.exit(15i32) }

    // 16: the Galois LFSR bit stream, and its state far along (no early return to
    // the seed on the way).
    var f = rand.lfsr(44257u32)
    var packed = 0u32
    i = 0usize
    while i < 32usize {
        packed = (packed << 1u32) | rand.lfsr_next(&f)
        i += 1usize
    }
    if packed != 3746000679u32 || f.state != 3838828353u32 { os.exit(16i32) }
    var returned = false
    while i < 100000usize {
        let _ = rand.lfsr_next(&f)
        if f.state == 44257u32 { returned = true }
        i += 1usize
    }
    if returned || f.state != 2524426344u32 { os.exit(16i32) }
    var fz = rand.lfsr(0u32)
    if fz.state != 1u32 { os.exit(16i32) }

    // 17: the alias table and a thousand picks.
    var weights5: [5]f64 = zero
    weights5[0usize] = 1.0f64
    weights5[1usize] = 2.0f64
    weights5[2usize] = 3.0f64
    weights5[3usize] = 4.0f64
    weights5[4usize] = 10.0f64
    var probability: [5]f64 = zero
    var alias: [5]usize = zero
    var alias_scratch: [5]usize = zero
    if rand.alias_table(weights5[..], probability[..], alias[..], alias_scratch[..4usize]) != rand.TooSmall { os.exit(17i32) }
    if rand.alias_table(weights5[..0usize], probability[..], alias[..], alias_scratch[..]) != rand.Invalid { os.exit(17i32) }
    if rand.alias_table(weights5[..], probability[..], alias[..], alias_scratch[..]) != ok { os.exit(17i32) }
    if probability[0usize] != 0.25f64 || probability[1usize] != 0.5f64 || probability[2usize] != 0.75f64 || probability[3usize] != 1.0f64 || probability[4usize] != 1.0f64 { os.exit(17i32) }
    if alias[0usize] != 4usize || alias[1usize] != 4usize || alias[2usize] != 4usize || alias[3usize] != 3usize || alias[4usize] != 4usize { os.exit(17i32) }
    var p = rand.pcg64(1u64, 2u64)
    var picks: [5]usize = zero
    i = 0usize
    while i < 1000usize {
        let pick = rand.alias_pick(&p, probability[..], alias[..])
        picks[pick] += 1usize
        i += 1usize
    }
    if picks[0usize] != 56usize || picks[1usize] != 96usize || picks[2usize] != 144usize || picks[3usize] != 227usize || picks[4usize] != 477usize { os.exit(17i32) }

    // 18: stratified uniforms, one per stratum.
    var strata: [8]f64 = zero
    var ps = rand.pcg64(3u64, 4u64)
    rand.stratified(&ps, strata[..])
    if strata[0usize] != 0.028052375614510655f64 || strata[3usize] != 0.42668455915311937f64 || strata[7usize] != 0.9300482520958381f64 { os.exit(18i32) }
    i = 0usize
    while i < 8usize {
        if usize(strata[i] * 8.0f64) != i { os.exit(18i32) }
        i += 1usize
    }

    // 19: a Latin hypercube of four points in two dimensions.
    var cube: [8]f64 = zero
    var perm: [4]usize = zero
    var pl = rand.pcg64(5u64, 6u64)
    if rand.latin_hypercube(&pl, cube[..7usize], 4usize, 2usize, perm[..]) != rand.TooSmall { os.exit(19i32) }
    if rand.latin_hypercube(&pl, cube[..], 4usize, 2usize, perm[..]) != ok { os.exit(19i32) }
    if cube[0usize] != 0.9399012616047395f64 || cube[1usize] != 0.6511745828286994f64 || cube[6usize] != 0.7281186222991374f64 || cube[7usize] != 0.163348921112552f64 { os.exit(19i32) }
    var seen = 0u32
    i = 0usize
    while i < 4usize {
        seen = seen | (1u32 << u32(usize(cube[i * 2usize] * 4.0f64)))
        seen = seen | (16u32 << u32(usize(cube[i * 2usize + 1usize] * 4.0f64)))
        i += 1usize
    }
    if seen != 255u32 { os.exit(19i32) }

    // 20: A-Res over thirty weighted items, five kept, in heap order.
    var weights: [30]f64 = zero
    var gw = Gen { state: 13u64 }
    i = 0usize
    while i < 30usize {
        weights[i] = 1.0f64 + f64(draw(&gw) % 10u64)
        i += 1usize
    }
    var kept: [5]u64 = zero
    var keys: [5]f64 = zero
    var res = rand.reservoir_weighted[u64](kept[..], keys[..])
    var pw = rand.pcg64(7u64, 8u64)
    i = 0usize
    while i < 30usize {
        rand.reservoir_weighted_offer[u64](&res, &pw, u64(i), weights[i])
        i += 1usize
    }
    let sample = rand.reservoir_weighted_sample[u64](&res)
    if sample.len != 5usize || sample[0usize] != 20u64 || sample[1usize] != 16u64 || sample[2usize] != 18u64 || sample[3usize] != 29u64 || sample[4usize] != 26u64 { os.exit(20i32) }
    if !near(keys[0usize], 0.9566783731433077f64) || keys[0usize] > keys[1usize] || keys[0usize] > keys[2usize] { os.exit(20i32) }

    // 21: the time-decayed form favours the late items.
    var res2 = rand.reservoir_weighted[u64](kept[..], keys[..])
    var pd = rand.pcg64(9u64, 10u64)
    i = 0usize
    while i < 30usize {
        rand.reservoir_decayed_offer[u64](&res2, &pd, u64(i), weights[i], f64(i), 0.1f64)
        i += 1usize
    }
    let decayed = rand.reservoir_weighted_sample[u64](&res2)
    if decayed[0usize] != 18u64 || decayed[1usize] != 19u64 || decayed[2usize] != 20u64 || decayed[3usize] != 23u64 || decayed[4usize] != 15u64 { os.exit(21i32) }

    // 22: priority sampling: the threshold and the adjusted weights.
    var chosen: [6]usize = zero
    var adjusted: [6]f64 = zero
    var pp = rand.pcg64(11u64, 12u64)
    let (_, short) = rand.priority_sample(&pp, weights[..], chosen[..5usize], adjusted[..4usize])
    if short != rand.TooSmall { os.exit(22i32) }
    let (threshold, priority_error) = rand.priority_sample(&pp, weights[..], chosen[..5usize], adjusted[..5usize])
    if priority_error != ok || threshold != 22.547595490964934f64 { os.exit(22i32) }
    h = 0u64
    var total = 0.0f64
    i = 0usize
    while i < 5usize {
        h = h *% 31u64 +% u64(chosen[i])
        total += adjusted[i]
        if adjusted[i] < weights[chosen[i]] || adjusted[i] < threshold { os.exit(22i32) }
        i += 1usize
    }
    if h != 6729826u64 || !near(total, 112.73797745482467f64) { os.exit(22i32) }

    // 23: VarOpt: the adjusted weights of the sample sum to the total exactly.
    var pv = rand.pcg64(13u64, 14u64)
    let (_, tight_varopt) = rand.varopt_sample(&pv, weights[..], 5usize, chosen[..5usize], adjusted[..])
    if tight_varopt != rand.TooSmall { os.exit(23i32) }
    let (tau, varopt_error) = rand.varopt_sample(&pv, weights[..], 5usize, chosen[..], adjusted[..])
    if varopt_error != ok || tau != 29.8f64 { os.exit(23i32) }
    h = 0u64
    total = 0.0f64
    i = 0usize
    while i < 5usize {
        h = h *% 31u64 +% u64(chosen[i])
        total += adjusted[i]
        if adjusted[i] < weights[chosen[i]] { os.exit(23i32) }
        i += 1usize
    }
    if h != 26429493u64 || !near(total, 149.0f64) { os.exit(23i32) }

    try io.print("algo sort rand plan ok\n")
    ret ok
}
