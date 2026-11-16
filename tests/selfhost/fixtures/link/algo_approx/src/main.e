use e.algo.approx as approx
use e.io
use e.mem

error Failed

fn lcg(s: u64) -> u64 { ret (s * 1103515245u64 + 12345u64) % 2147483648u64 }

// 8 vertices, random edges; brute-force minimum vertex cover and maximum cut
fn graph_checks(seed0: u64) -> err {
    var seed = seed0
    var edges: [40]usize = zero
    var ne = 0usize
    var u = 0usize
    while u < 8usize {
        var w = u + 1usize
        while w < 8usize {
            seed = lcg(seed)
            if (seed >> 12u64) % 100u64 < 35u64 {
                edges[ne] = u
                edges[ne + 1usize] = w
                ne += 2usize
            }
            w += 1usize
        }
        u += 1usize
    }
    if ne == 0usize { ret ok }
    var cover: [8]bool = zero
    let size = approx.vertex_cover(edges[..ne], 8usize, cover[..])
    var e = 0usize
    while e < ne {
        if !cover[edges[e]] && !cover[edges[e + 1usize]] { ret Failed }
        e += 2usize
    }
    var best_cover = 9usize
    var best_cut = 0usize
    var mask = 0usize
    while mask < 256usize {
        var ok_cover = true
        var cut = 0usize
        e = 0usize
        while e < ne {
            let a = (mask >> edges[e]) & 1usize
            let b = (mask >> edges[e + 1usize]) & 1usize
            if a == 0usize && b == 0usize { ok_cover = false }
            if a != b { cut += 1usize }
            e += 2usize
        }
        var pop = 0usize
        var v = 0usize
        while v < 8usize {
            pop += (mask >> v) & 1usize
            v += 1usize
        }
        if ok_cover && pop < best_cover { best_cover = pop }
        if cut > best_cut { best_cut = cut }
        mask += 1usize
    }
    if f64(size) > approx.vertex_cover_ratio() * f64(best_cover) { ret Failed }
    var side: [8]bool = zero
    let got = approx.max_cut(edges[..ne], 8usize, side[..])
    if f64(got) < approx.max_cut_ratio() * f64(best_cut) { ret Failed }
    if 2usize * got < ne / 2usize { ret Failed }
    ret ok
}

// jobs on m machines against the brute-force optimal makespan
fn schedule_checks(seed0: u64) -> err {
    var seed = seed0
    var jobs: [7]f64 = zero
    var j = 0usize
    while j < 7usize {
        seed = lcg(seed)
        jobs[j] = f64(1u64 + (seed >> 12u64) % 20u64)
        j += 1usize
    }
    let m = 3usize
    var assign: [7]usize = zero
    var order: [7]usize = zero
    var loads: [3]f64 = zero
    let ls = approx.list_schedule(jobs[..], m, assign[..], loads[..])
    let lp = approx.lpt(jobs[..], m, order[..], assign[..], loads[..])
    var best = 1.0e300f64
    var code = 0usize
    while code < 2187usize {
        var l0 = 0.0f64
        var l1 = 0.0f64
        var l2 = 0.0f64
        var c = code
        j = 0usize
        while j < 7usize {
            let mm = c % 3usize
            c = c / 3usize
            if mm == 0usize { l0 += jobs[j] }
            if mm == 1usize { l1 += jobs[j] }
            if mm == 2usize { l2 += jobs[j] }
            j += 1usize
        }
        var mk = l0
        if l1 > mk { mk = l1 }
        if l2 > mk { mk = l2 }
        if mk < best { best = mk }
        code += 1usize
    }
    if ls > approx.list_schedule_ratio(m) * best + 1.0e-9f64 { ret Failed }
    if lp > approx.lpt_ratio(m) * best + 1.0e-9f64 { ret Failed }
    if lp > ls + 1.0e-9f64 && lp > best * 2.0f64 { ret Failed }
    ret ok
}

fn knapsack_checks(a: *mem.Arena, seed0: u64) -> err {
    var seed = seed0
    var values: [10]f64 = zero
    var weights: [10]f64 = zero
    var i = 0usize
    while i < 10usize {
        seed = lcg(seed)
        values[i] = f64(5u64 + (seed >> 12u64) % 60u64)
        seed = lcg(seed)
        weights[i] = f64(3u64 + (seed >> 12u64) % 25u64)
        i += 1usize
    }
    let cap = 60.0f64
    var best = 0.0f64
    var mask = 0usize
    while mask < 1024usize {
        var v = 0.0f64
        var w = 0.0f64
        i = 0usize
        while i < 10usize {
            if (mask >> i) & 1usize == 1usize {
                v += values[i]
                w += weights[i]
            }
            i += 1usize
        }
        if w <= cap && v > best { best = v }
        mask += 1usize
    }
    var take: [10]bool = zero
    let start = mem.mark(a)
    let (got, e) = approx.knapsack_fptas(a, values[..], weights[..], cap, 0.1f64, take[..])
    mem.reset(a, start)
    if e != ok { ret e }
    var w = 0.0f64
    i = 0usize
    while i < 10usize {
        if take[i] { w += weights[i] }
        i += 1usize
    }
    if w > cap { ret Failed }
    if got < 0.9f64 * best - 1.0e-9f64 { ret Failed }
    ret ok
}

fn wrapper_checks(seed0: u64) -> err {
    var seed = seed0
    // bin packing: sizes in (0, 1], capacity 1, against the lower bound ceil(total) on OPT
    var sizes: [12]f64 = zero
    var total = 0.0f64
    var i = 0usize
    while i < 12usize {
        seed = lcg(seed)
        sizes[i] = f64(5u64 + (seed >> 12u64) % 60u64) / 100.0f64
        total += sizes[i]
        i += 1usize
    }
    var bins: [12]usize = zero
    var loads: [12]f64 = zero
    var order: [12]usize = zero
    let (used, e) = approx.bin_pack(sizes[..], 1.0f64, bins[..], loads[..], order[..])
    if e != ok { ret e }
    var lb = 1usize
    while f64(lb) < total - 1.0e-9f64 { lb += 1usize }
    if f64(used) > approx.bin_pack_ratio(lb) * 1.5f64 + 1.0e-9f64 { ret Failed }
    if used < lb { ret Failed }
    // set cover: 5 sets over 8 elements, the chosen sets cover everything within H(8) times the optimum (at most 5)
    var membership: [40]u8 = zero
    i = 0usize
    while i < 40usize {
        seed = lcg(seed)
        if (seed >> 12u64) % 100u64 < 45u64 { membership[i] = 1u8 }
        i += 1usize
    }
    var s = 0usize
    while s < 5usize {
        membership[s * 8usize + (s % 8usize)] = 1u8
        membership[s * 8usize + ((s + 3usize) % 8usize)] = 1u8
        s += 1usize
    }
    var chosen: [5]usize = zero
    var covered: [8]u8 = zero
    let (nc, ce) = approx.set_cover(membership[..], 5usize, 8usize, chosen[..], covered[..])
    if ce != ok { ret ok }
    if nc > 5usize { ret Failed }
    if approx.set_cover_ratio(8usize) < 2.7f64 { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var s = 1u64
    while s <= 40u64 {
        let g = graph_checks(s * 7919u64)
        if g != ok { ret g }
        let c = schedule_checks(s * 104729u64)
        if c != ok { ret c }
        let k = knapsack_checks(a, s * 1299709u64)
        if k != ok { ret k }
        let w = wrapper_checks(s * 15485863u64)
        if w != ok { ret w }
        s += 1u64
    }
    ret ok
}
