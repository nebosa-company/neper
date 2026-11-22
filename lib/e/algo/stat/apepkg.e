// R ape::nj: Saitou and Nei neighbour joining of a distance matrix; the 2n - 3 edge lengths are returned sorted ascending (the tree topology is not exposed), which fixes the total length, the unrooted tree up to leaf labelling and every order-free summary.
//
// ape::dist.dna over an alignment with global deletion (pairwise.deletion = FALSE, ape's default): sites
// where any sequence holds a non-ACGT code are dropped first, the base frequencies are counted over what
// remains, and each model turns the pairwise counts into a distance (raw, JC69, K80, F81).
//
// Not here: the topology and labels, bionj, upgma, rooting, cophenetic distances, tree comparison, the
// other dist.dna models (K81, F84, T92, TN93, GG95, LogDet, the indel models), the rest of ape.

use e.math
use e.mem

// a dist.dna model this module does not port (ape's K81, F84, T92, TN93, GG95, LogDet and indel models)
error Unsupported

// The DNA codes this module reads: 0..3 are A, C, G and T and anything else is an unknown base or a gap.
// A site is kept only when every sequence has 0..3 there (ape's global deletion), and the distance of a
// pair counts the differing kept sites. model: 0 raw, 1 JC69, 2 K80 (transitions/transversions), 3 F81
// (with the base frequencies of the kept matrix). out is n by n row-major with a zero diagonal.
fn dist_dna(a: *mem.Arena, x: []const u8, n: usize, l: usize, model: u8, out: []f64) -> err {
    if model > 3u8 { ret Unsupported }
    let (keep, e1) = mem.alloc[bool](a, l)
    if e1 != ok { ret e1 }
    var s = 0usize
    while s < l {
        var all_known = true
        var i = 0usize
        while i < n {
            if x[i * l + s] > 3u8 { all_known = false }
            i += 1usize
        }
        keep[s] = all_known
        s += 1usize
    }
    var kept = 0usize
    s = 0usize
    while s < l {
        if keep[s] { kept += 1usize }
        s += 1usize
    }
    // the base frequencies of the whole matrix, for F81: ape computes base.freq(x) before the deletion, so a
    // site that is later dropped still counts towards the frequencies (only its distance is lost)
    var freq: [4]f64 = zero
    var b = 0usize
    while b < 4usize {
        var count = 0.0f64
        var i = 0usize
        while i < n {
            s = 0usize
            while s < l {
                let code = x[i * l + s]
                if code <= 3u8 && usize(code) == b { count += 1.0f64 }
                s += 1usize
            }
            i += 1usize
        }
        freq[b] = count
        b += 1usize
    }
    var total = 0.0f64
    b = 0usize
    while b < 4usize {
        total += freq[b]
        b += 1usize
    }
    var e81 = 1.0f64
    b = 0usize
    while b < 4usize {
        let pi = freq[b] / total
        e81 -= pi * pi
        b += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var diffs = 0usize
            var transitions = 0usize
            s = 0usize
            while s < l {
                if keep[s] {
                    let ai = x[i * l + s]
                    let bj = x[j * l + s]
                    if ai != bj {
                        diffs += 1usize
                        // a transition is A<->G or C<->T: both purines (0, 2) or both pyrimidines (1, 3)
                        let purine_a = ai == 0u8 || ai == 2u8
                        let purine_b = bj == 0u8 || bj == 2u8
                        if purine_a == purine_b { transitions += 1usize }
                    }
                }
                s += 1usize
            }
            let len = f64(kept)
            let nd = f64(diffs)
            var d = 0.0f64
            if model == 0u8 {
                d = nd / len
            } else if model == 1u8 {
                d = 0.0f64 - 0.75f64 * math.log[f64](1.0f64 - 4.0f64 * (nd / len) / 3.0f64)
            } else if model == 2u8 {
                let p = f64(transitions) / len
                let q = (nd - f64(transitions)) / len
                d = 0.0f64 - 0.5f64 * math.log[f64]((1.0f64 - 2.0f64 * p - q) * math.sqrt[f64](1.0f64 - 2.0f64 * q))
            } else {
                d = 0.0f64 - e81 * math.log[f64](1.0f64 - (nd / len) / e81)
            }
            out[i * n + j] = d
            out[j * n + i] = d
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// d is n by n row-major (n >= 3); the edge lengths go into out (2n - 3 values)
fn nj(a: *mem.Arena, d: []const f64, n: usize, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, n * n)
    let (alive, e2) = mem.alloc[bool](a, n)
    let (r, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n * n {
        w[i] = d[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        alive[i] = true
        i += 1usize
    }
    var left = n
    var ne = 0usize
    while left > 3usize {
        i = 0usize
        while i < n {
            r[i] = 0.0f64
            if alive[i] {
                var j = 0usize
                while j < n {
                    if alive[j] { r[i] += w[i * n + j] }
                    j += 1usize
                }
            }
            i += 1usize
        }
        var bi = 0usize
        var bj = 0usize
        var best = 1.0e300f64
        i = 0usize
        while i < n {
            if alive[i] {
                var j = i + 1usize
                while j < n {
                    if alive[j] {
                        let q = f64(left - 2usize) * w[i * n + j] - r[i] - r[j]
                        if q < best {
                            best = q
                            bi = i
                            bj = j
                        }
                    }
                    j += 1usize
                }
            }
            i += 1usize
        }
        let lf = f64(left - 2usize)
        let di = w[bi * n + bj] / 2.0f64 + (r[bi] - r[bj]) / (2.0f64 * lf)
        let dj = w[bi * n + bj] - di
        out[ne] = di
        out[ne + 1usize] = dj
        ne += 2usize
        // the new node replaces bi
        var k = 0usize
        while k < n {
            if alive[k] && k != bi && k != bj {
                let nd = (w[bi * n + k] + w[bj * n + k] - w[bi * n + bj]) / 2.0f64
                w[bi * n + k] = nd
                w[k * n + bi] = nd
            }
            k += 1usize
        }
        alive[bj] = false
        left -= 1usize
    }
    var p = 0usize
    var q = 0usize
    var s = 0usize
    i = 0usize
    while i < n {
        if alive[i] {
            if p == 0usize && q == 0usize && s == 0usize { p = i + 1usize } else if q == 0usize { q = i + 1usize } else { s = i + 1usize }
        }
        i += 1usize
    }
    let ip = p - 1usize
    let iq = q - 1usize
    let is = s - 1usize
    out[ne] = (w[ip * n + iq] + w[ip * n + is] - w[iq * n + is]) / 2.0f64
    out[ne + 1usize] = (w[ip * n + iq] + w[iq * n + is] - w[ip * n + is]) / 2.0f64
    out[ne + 2usize] = (w[ip * n + is] + w[iq * n + is] - w[ip * n + iq]) / 2.0f64
    // ascending
    i = 1usize
    while i < 2usize * n - 3usize {
        let v = out[i]
        var j = i
        while j > 0usize && out[j - 1usize] > v {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = v
        i += 1usize
    }
    ret ok
}
