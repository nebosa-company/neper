// R FactoMineR::PCA (standardised, unit weights) and CA: eigenvalues, variable and individual coordinates, cosines and contributions; row and column coordinates, contributions and cosines of a correspondence analysis. Signs of axes are free, so callers compare absolute values.
//
// Not here: supplementary individuals and variables, weights, MCA, MFA, HCPC, quantitative scale.unit = FALSE, descriptions of dimensions.

use e.algo.linalg.matrix as mx
use e.math
use e.mem

// PCA of x (n by p, row-major). out layout: eig (p), var coord (p by p, column k = axis k), var contrib (p by p), ind coord (n by p), ind cos2 (n by p), ind contrib (n by p), ind dist (n)
fn pca(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> err {
    let nf = f64(n)
    let (z, e1) = mem.alloc[f64](a, n * p)
    let (cr, e2) = mem.alloc[f64](a, p * p)
    let (vv, e3) = mem.alloc[f64](a, p * p)
    let (ev, e4) = mem.alloc[f64](a, p)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += x[i * p + j] / nf
            i += 1usize
        }
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            s2 += (x[i * p + j] - m) * (x[i * p + j] - m) / nf
            i += 1usize
        }
        i = 0usize
        while i < n {
            z[i * p + j] = (x[i * p + j] - m) / math.sqrt[f64](s2)
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            var s = 0.0f64
            var t = 0usize
            while t < n {
                s += z[t * p + i] * z[t * p + j] / nf
                t += 1usize
            }
            cr[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let (vm, e5) = mx.view[f64](vv, p, p, p)
    let (src, e6) = mx.view_const[f64](cr, p, p, p)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let r = mx.eigen(a, ev, vm, src, 1.0e-30f64, 200u32)
    if r != ok { ret r }
    let o_vc = p
    let o_vk = p + p * p
    let o_ic = p + 2usize * p * p
    let o_cs = o_ic + n * p
    let o_ik = o_cs + n * p
    let o_dd = o_ik + n * p
    var k = 0usize
    while k < p {
        out[k] = ev[k]
        j = 0usize
        while j < p {
            let c = vv[j * p + k] * math.sqrt[f64](ev[k])
            out[o_vc + j * p + k] = c
            out[o_vk + j * p + k] = c * c / ev[k] * 100.0f64
            j += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        var d2 = 0.0f64
        j = 0usize
        while j < p {
            d2 += z[i * p + j] * z[i * p + j]
            j += 1usize
        }
        out[o_dd + i] = math.sqrt[f64](d2)
        k = 0usize
        while k < p {
            var c = 0.0f64
            j = 0usize
            while j < p {
                c += z[i * p + j] * vv[j * p + k]
                j += 1usize
            }
            out[o_ic + i * p + k] = c
            out[o_cs + i * p + k] = c * c / d2
            out[o_ik + i * p + k] = c * c / (nf * ev[k]) * 100.0f64
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// CA of a table (nr by nc, row-major, positive total) with the nd = min(nr, nc) - 1 axes. out layout: eig (nd), row coord (nr by nd), row contrib (nr by nd), col coord (nc by nd), col cos2 (nc by nd)
fn ca(a: *mem.Arena, t: []const f64, nr: usize, nc: usize, out: []f64) -> err {
    var nd = nr
    if nc < nd { nd = nc }
    nd -= 1usize
    var tot = 0.0f64
    var i = 0usize
    while i < nr * nc {
        tot += t[i]
        i += 1usize
    }
    let (rm, e1) = mem.alloc[f64](a, nr)
    let (cm, e2) = mem.alloc[f64](a, nc)
    let (s, e3) = mem.alloc[f64](a, nr * nc)
    let kk = nc
    var kmin = nr
    if nc < kmin { kmin = nc }
    let (u, e4) = mem.alloc[f64](a, nr * kmin)
    let (v, e5) = mem.alloc[f64](a, nc * kmin)
    let (sg, e6) = mem.alloc[f64](a, kmin)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    i = 0usize
    while i < nr {
        rm[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < nc {
        cm[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < nr {
        j = 0usize
        while j < nc {
            rm[i] += t[i * nc + j] / tot
            cm[j] += t[i * nc + j] / tot
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nr {
        j = 0usize
        while j < nc {
            s[i * nc + j] = (t[i * nc + j] / tot - rm[i] * cm[j]) / math.sqrt[f64](rm[i] * cm[j])
            j += 1usize
        }
        i += 1usize
    }
    let (um, e7) = mx.view[f64](u, nr, kmin, kmin)
    let (vm, e8) = mx.view[f64](v, nc, kmin, kmin)
    let (src, e9) = mx.view_const[f64](s, nr, nc, nc)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    let r = mx.svd(a, um, sg, vm, src, 1.0e-14f64, 200u32)
    if r != ok { ret r }
    let o_rc = nd
    let o_rk = nd + nr * nd
    let o_cc = nd + 2usize * nr * nd
    let o_cs = o_cc + nc * nd
    var k = 0usize
    while k < nd {
        let lam = sg[k] * sg[k]
        out[k] = lam
        i = 0usize
        while i < nr {
            let c = u[i * kmin + k] * sg[k] / math.sqrt[f64](rm[i])
            out[o_rc + i * nd + k] = c
            out[o_rk + i * nd + k] = rm[i] * c * c / lam * 100.0f64
            i += 1usize
        }
        j = 0usize
        while j < nc {
            let c = v[j * kmin + k] * sg[k] / math.sqrt[f64](cm[j])
            out[o_cc + j * nd + k] = c
            var d2 = 0.0f64
            i = 0usize
            while i < nr {
                let q = t[i * nc + j] / tot / cm[j] - rm[i]
                d2 += q * q / rm[i]
                i += 1usize
            }
            out[o_cs + j * nd + k] = c * c / d2
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}
