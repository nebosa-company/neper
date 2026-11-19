// R fpc: discrproj, the projection behind plotcluster, with its method choices dc, mvdc, adc, awc, nc, wnc and anc and the ignorepoints option. Matrices are
// row-major.

use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.mem

error Malformed

// discrproj(x, clvecd, method, clnum, ignorepoints, ignorenum = 0): method 1 dc, 2 mvdc, 3 adc, 4 awc (classical), 5 nc, 6 wnc, 7 anc. clv holds the labels 1..kn;
// with ignorepoints a 0 marks a point left out of the fit, which is projected afterwards by the units. sphere is mvdc's and nc's covariance ("none" when empty)
fn discrproj(a: *mem.Arena, x: []const f64, n: usize, p: usize, clv: []const usize, kn: usize, method: usize, clnum: usize, ignorepoints: bool, nn: usize, md: bool, clweight: bool, alpha: f64, sphere: []const f64, ev: []f64, units: []f64, proj: []f64) -> err {
    var m = n
    if ignorepoints {
        m = 0usize
        var i0 = 0usize
        while i0 < n {
            if clv[i0] != 0usize { m += 1usize }
            i0 += 1usize
        }
    }
    let (xx, e1) = mem.alloc[f64](a, m * p)
    let (lab, e2) = mem.alloc[usize](a, m)
    let (ci, e3) = mem.alloc[usize](a, m)
    let (cz, e4) = mem.alloc[usize](a, m)
    let (px, e5) = mem.alloc[f64](a, m * p)
    let (wg, e6) = mem.alloc[f64](a, m)
    let (wout, e7) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret Malformed }
    var r = 0usize
    var i = 0usize
    while i < n {
        if !ignorepoints || clv[i] != 0usize {
            var j = 0usize
            while j < p {
                xx[r * p + j] = x[i * p + j]
                j += 1usize
            }
            lab[r] = clv[i]
            ci[r] = 0usize
            if clv[i] == clnum { ci[r] = 1usize }
            cz[r] = clv[i] - 1usize
            r += 1usize
        }
        i += 1usize
    }
    var e = ok
    if method == 1usize { e = fp.discrcoord(a, xx, m, p, lab, kn, 0usize, ev, units, px, wout) }
    if method == 2usize { e = fc.mvdcoord(a, xx, m, p, lab, kn, sphere, ev, units, px) }
    if method == 3usize { e = fc.adcoord(a, xx, m, p, ci, ev, units, px) }
    if method == 4usize { e = fc.awcoord(a, xx, m, p, ci, md, clweight, alpha, ev, units, px, wg) }
    if method == 5usize { e = fp.ncoord(a, xx, m, p, cz, kn, nn, false, sphere, ev, units, px) }
    if method == 6usize { e = fp.ncoord(a, xx, m, p, cz, kn, nn, true, sphere, ev, units, px) }
    if method == 7usize { e = fc.ancoord(a, xx, m, p, ci, nn, ev, units, px) }
    if e != ok { ret e }
    r = 0usize
    i = 0usize
    while i < n {
        var j = 0usize
        if !ignorepoints || clv[i] != 0usize {
            while j < p {
                proj[i * p + j] = px[r * p + j]
                j += 1usize
            }
            r += 1usize
        } else {
            fc.mm(x[i * p..i * p + p], 1usize, p, units, p, proj[i * p..i * p + p])
        }
        i += 1usize
    }
    ret ok
}
