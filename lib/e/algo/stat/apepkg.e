// R ape::nj: Saitou and Nei neighbour joining of a distance matrix; the 2n - 3 edge lengths are returned sorted ascending (the tree topology is not exposed), which fixes the total length, the unrooted tree up to leaf labelling and every order-free summary.
//
// Not here: the topology and labels, bionj, upgma, rooting, cophenetic distances, tree comparison, the rest of ape.

use e.math
use e.mem

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
