use e.algo.discrepancy as disc
use e.io
use e.math
use e.mem

error Failed

fn lcg(s: u64) -> u64 { ret (s * 1103515245u64 + 12345u64) % 2147483648u64 }

// a random system of 14 sets over 12 elements where every element lies in at most 3 sets
fn beck_fiala_checks(a: *mem.Arena, seed0: u64) -> err {
    var seed = seed0
    var sets: [168]u8 = zero
    var j = 0usize
    while j < 12usize {
        var placed = 0usize
        var tries = 0usize
        while placed < 3usize && tries < 40usize {
            seed = lcg(seed)
            let s = usize((seed >> 12u64) % 14u64)
            if sets[s * 12usize + j] == 0u8 {
                sets[s * 12usize + j] = 1u8
                placed += 1usize
            }
            tries += 1usize
        }
        j += 1usize
    }
    var colour: [12]f64 = zero
    let start = mem.mark(a)
    let (worst, e) = disc.beck_fiala(a, sets[..], 14usize, 12usize, 3usize, colour[..])
    mem.reset(a, start)
    if e != ok { ret e }
    j = 0usize
    while j < 12usize {
        if colour[j] != 1.0f64 && colour[j] != 0.0f64 - 1.0f64 { ret Failed }
        j += 1usize
    }
    // the Beck-Fiala bound: below 2 t = 6
    if worst >= 6.0f64 { ret Failed }
    // brute force: the heuristic cannot beat the true optimum
    var best = 1.0e300f64
    var mask = 0usize
    while mask < 4096usize {
        var w = 0.0f64
        var s = 0usize
        while s < 14usize {
            var sum = 0.0f64
            j = 0usize
            while j < 12usize {
                if sets[s * 12usize + j] != 0u8 {
                    if (mask >> j) & 1usize == 1usize { sum += 1.0f64 } else { sum -= 1.0f64 }
                }
                j += 1usize
            }
            if math.abs[f64](sum) > w { w = math.abs[f64](sum) }
            s += 1usize
        }
        if w < best { best = w }
        mask += 1usize
    }
    if worst < best - 1.0e-9f64 { ret Failed }
    ret ok
}

fn balance_checks(seed0: u64) -> err {
    var seed = seed0
    var vecs: [60]f64 = zero
    var total = 0.0f64
    var i = 0usize
    while i < 20usize {
        var nrm = 0.0f64
        var k = 0usize
        while k < 3usize {
            seed = lcg(seed)
            let v = f64((seed >> 12u64) % 2001u64) / 1000.0f64 - 1.0f64
            vecs[i * 3usize + k] = v
            nrm += v * v
            k += 1usize
        }
        total += nrm
        i += 1usize
    }
    var signs: [20]f64 = zero
    var sum: [3]f64 = zero
    let sq = disc.balance(vecs[..], 20usize, 3usize, signs[..], sum[..])
    if sq > total + 1.0e-9f64 { ret Failed }
    ret ok
}

fn cut_checks(seed0: u64) -> err {
    var seed = seed0
    var edges: [80]usize = zero
    var ne = 0usize
    var u = 0usize
    while u < 9usize {
        var w = u + 1usize
        while w < 9usize {
            seed = lcg(seed)
            if (seed >> 12u64) % 100u64 < 40u64 {
                edges[ne] = u
                edges[ne + 1usize] = w
                ne += 2usize
            }
            w += 1usize
        }
        u += 1usize
    }
    if ne == 0usize { ret ok }
    var side: [9]u8 = zero
    let got = disc.max_cut(edges[..ne], 9usize, side[..])
    if 2usize * got < ne / 2usize { ret Failed }
    var best = 0usize
    var mask = 0usize
    while mask < 512usize {
        var cut = 0usize
        var e = 0usize
        while e < ne {
            if (mask >> edges[e]) & 1usize != (mask >> edges[e + 1usize]) & 1usize { cut += 1usize }
            e += 2usize
        }
        if cut > best { best = cut }
        mask += 1usize
    }
    if got > best { ret Failed }
    if 2usize * got < best { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var s = 1u64
    while s <= 50u64 {
        let b = beck_fiala_checks(a, s * 7919u64)
        if b != ok { ret b }
        let v = balance_checks(s * 104729u64)
        if v != ok { ret v }
        let c = cut_checks(s * 1299709u64)
        if c != ok { ret c }
        s += 1u64
    }
    ret ok
}
