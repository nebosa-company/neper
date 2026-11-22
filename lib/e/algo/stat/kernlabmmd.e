// R kernlab kmmd on matrix input: the kernel maximum mean discrepancy statistics (mmd1, the unbiased third-order mmd3 and the
// Rademacher bound D1) and the bootstrap bound of the asymptotic test, on R's random stream. Sums and column sums are R's
// long-double sums (armld.sum_ld); the logarithm is R's (armx87.log_r), as R on Windows computes it. Data are row-major.
//
// Not here: the string-kernel (list) and precomputed kernel-matrix methods, and the automatic sigma (sigest) for the default
// kernel; the kernel is chosen by kernlabpkg's kind and parameters.

use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.armx87 as x87
use e.algo.stat.kernlabpkg as kl
use e.algo.stat.kernlabsvm as ks
use e.math
use e.mem

// R 4's round(x, 9) (fround.c): the candidate below and the candidate above, the nearer wins, ties to the even one
fn round9(v: f64) -> f64 {
    if v == 0.0f64 || v != v { ret v }
    var x = v
    var sgn = 1.0f64
    if x < 0.0f64 {
        sgn = 0.0f64 - 1.0f64
        x = 0.0f64 - x
    }
    let ex = i64((mem.bitcast[u64](x) >> 52u64) & 2047u64) - 1023i64
    let l10x = 0.30102999566398119521f64 * (0.5f64 + f64(ex))
    if l10x + 9.0f64 > 15.0f64 { ret v }
    let x10 = 1000000000.0f64 * x
    let i10 = math.floor[f64](x10)
    let xd = i10 / 1000000000.0f64
    let xu = math.ceil[f64](x10) / 1000000000.0f64
    let du = xu - x
    let dd = x - xd
    var even = false
    if i10 - 2.0f64 * math.floor[f64](i10 / 2.0f64) == 0.0f64 { even = true }
    if dd < du || (dd == du && even) { ret sgn * xd }
    ret sgn * xu
}

// kernelMatrix(kernel, x, y) as kernlab builds it: the rbf and Laplace kernels from dot products and half squared norms (x-only calls fill row i with (dot - dota[j]) - dota[i]), the others from kernlabpkg
fn cross(xonly: bool, kind: usize, px: []const f64, py: []const f64, nx: usize, ny: usize, p: usize, par1: f64, par2: f64, par3: f64, out: []f64) {
    var i = 0usize
    while i < nx {
        var j = 0usize
        while j < ny {
            if kind == 7usize {
                // besselkernel (par1 = sigma, par2 = order, par3 = degree): sigma * sqrt(round(-2 w, 9)), besselJ(xx, nu) * xx^-nu, the entries below 10e-5 set to lim, then (. / lim)^degree
                var dxy = 0.0f64
                var k = 0usize
                while k < p {
                    dxy += px[i * p + k] * py[j * p + k]
                    k += 1usize
                }
                let sx = half_sq(px, i, p)
                let sy = half_sq(py, j, p)
                var w = (dxy - sy) - sx
                if !xonly { w = (dxy - sx) - sy }
                let xx = par1 * math.sqrt[f64](round9(0.0f64 - 2.0f64 * w))
                let lim = 1.0f64 / (ks.factorial(i64(par2)) * math.pow[f64](2.0f64, par2))
                var v = lim
                if xx != xx {
                    v = xx
                } else {
                    if !(xx < 0.0001f64) { v = ks.besj(i64(par2), xx) * math.pow[f64](xx, 0.0f64 - par2) }
                }
                var r = math.pow[f64](v / lim, par3)
                if par3 == 2.0f64 { r = (v / lim) * (v / lim) }
                out[i * ny + j] = r
            } else {
            if kind == 0usize || kind == 4usize {
                var dxy = 0.0f64
                var k = 0usize
                while k < p {
                    dxy += px[i * p + k] * py[j * p + k]
                    k += 1usize
                }
                let sx = half_sq(px, i, p)
                let sy = half_sq(py, j, p)
                // x-only: res[i, ] - dota - rep(dota[i]); with y: res[, j] - dota - rep(dotb[j]); both (dot - dota[row index of the vector]) - the fixed one
                var w = (dxy - sy) - sx
                if !xonly { w = (dxy - sx) - sy }
                if kind == 0usize {
                    out[i * ny + j] = x87.exp_r(2.0f64 * par1 * w)
                } else {
                    out[i * ny + j] = x87.exp_r((0.0f64 - par1) * math.sqrt[f64](round9(0.0f64 - 2.0f64 * w)))
                }
            } else {
                out[i * ny + j] = kl.kernel(kind, px[i * p..(i + 1usize) * p], py[j * p..(j + 1usize) * p], par1, par2, par3)
            }
            }
            j += 1usize
        }
        i += 1usize
    }
}

fn half_sq(x: []const f64, i: usize, p: usize) -> f64 {
    var sq: [16]f64 = zero
    var k = 0usize
    while k < p {
        sq[k] = x[i * p + k] * x[i * p + k]
        k += 1usize
    }
    ret ld.sum_ld(sq[0usize..p]) / 2.0f64
}

// K over the pooled labels 0..m + n: x rows first, then y rows
fn kc(kxx: []const f64, kyy: []const f64, kxy: []const f64, m: usize, n: usize, u: usize, v: usize) -> f64 {
    if u < m && v < m { ret kxx[u * m + v] }
    if u < m { ret kxy[u * n + (v - m)] }
    if v < m { ret kxy[v * n + (u - m)] }
    ret kyy[(u - m) * n + (v - m)]
}

// hu (length mm) of the three blocks: row labels rl and column labels cl index the pooled kernel
fn hu_block(kxx: []const f64, kyy: []const f64, kxy: []const f64, m: usize, n: usize, lx: []const usize, ly: []const usize, mm: usize, col: []f64, hu: []f64) {
    var j = 0usize
    while j < mm {
        var i = 0usize
        while i < mm {
            col[i] = kc(kxx, kyy, kxy, m, n, lx[i], lx[j])
            i += 1usize
        }
        let csx = ld.sum_ld(col[0usize..mm])
        let dgx = kc(kxx, kyy, kxy, m, n, lx[j], lx[j])
        i = 0usize
        while i < mm {
            col[i] = kc(kxx, kyy, kxy, m, n, ly[i], ly[j])
            i += 1usize
        }
        let csy = ld.sum_ld(col[0usize..mm])
        let dgy = kc(kxx, kyy, kxy, m, n, ly[j], ly[j])
        // nKxy[i, j] = K(ly[i], lx[j]): column j then row j
        i = 0usize
        while i < mm {
            col[i] = kc(kxx, kyy, kxy, m, n, ly[i], lx[j])
            i += 1usize
        }
        let csxy = ld.sum_ld(col[0usize..mm])
        i = 0usize
        while i < mm {
            col[i] = kc(kxx, kyy, kxy, m, n, ly[j], lx[i])
            i += 1usize
        }
        let csyx = ld.sum_ld(col[0usize..mm])
        let dgxy = kc(kxx, kyy, kxy, m, n, ly[j], lx[j])
        hu[j] = ((csx - dgx) + csy - dgy) - csxy - csyx + 2.0f64 * dgxy
        j += 1usize
    }
}

// out = [mmd1, mmd3, D1, bound] (bound only when asymptotic)
fn kmmd(a: *mem.Arena, g: *rr.Rng, x: []const f64, y: []const f64, m: usize, n: usize, p: usize, kind: usize, par1: f64, par2: f64, par3: f64, alpha: f64, asymptotic: bool, frac: f64, ntimes: usize, replace: bool, out: []f64) -> err {
    let (kxx, e1) = mem.alloc[f64](a, m * m)
    let (kyy, e2) = mem.alloc[f64](a, n * n)
    let (kxy, e3) = mem.alloc[f64](a, m * n)
    var big = m
    if n > big { big = n }
    let (col, e4) = mem.alloc[f64](a, m * m + n * n + m * n + 4usize * big)
    let (hu, e5) = mem.alloc[f64](a, 2usize * big)
    let (lx, e6) = mem.alloc[usize](a, 2usize * big)
    let (ly, e7) = mem.alloc[usize](a, 2usize * big)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    cross(true, kind, x, x, m, m, p, par1, par2, par3, kxx)
    cross(true, kind, y, y, n, n, p, par1, par2, par3, kyy)
    cross(false, kind, x, y, m, n, p, par1, par2, par3, kxy)
    var mm = m
    if n < mm { mm = n }
    // statistics: the sums run in column-major order, as R's do
    let sxx = ld.sum_ld(kxx[0usize..m * m])
    let syy = ld.sum_ld(kyy[0usize..n * n])
    var i = 0usize
    var j = 0usize
    while j < n {
        i = 0usize
        while i < m {
            col[j * m + i] = kxy[i * n + j]
            i += 1usize
        }
        j += 1usize
    }
    let sxy = ld.sum_ld(col[0usize..m * n])
    var rm = kxx[0usize]
    j = 0usize
    while j < mm {
        if kxx[j * m + j] > rm { rm = kxx[j * m + j] }
        if kyy[j * n + j] > rm { rm = kyy[j * n + j] }
        j += 1usize
    }
    let ws = col[m * n..]
    j = 0usize
    while j < mm {
        i = 0usize
        while i < mm {
            ws[i] = kxx[i * m + j]
            i += 1usize
        }
        var h = ld.sum_ld(ws[0usize..mm]) - kxx[j * m + j]
        i = 0usize
        while i < mm {
            ws[i] = kyy[i * n + j]
            i += 1usize
        }
        h = h + ld.sum_ld(ws[0usize..mm]) - kyy[j * n + j]
        i = 0usize
        while i < mm {
            ws[i] = kxy[i * n + j]
            i += 1usize
        }
        let c1 = ld.sum_ld(ws[0usize..mm])
        i = 0usize
        while i < mm {
            ws[i] = kxy[j * n + i]
            i += 1usize
        }
        let c2 = ld.sum_ld(ws[0usize..mm])
        hu[j] = h - c1 - c2 + 2.0f64 * kxy[j * n + j]
        j += 1usize
    }
    let mf = f64(m)
    let nf = f64(n)
    let mn2 = f64(m * m)
    let nn2 = f64(n * n)
    var inner = sxx / mn2 + syy / nn2 - 2.0f64 / mf / nf * sxy
    if inner < 0.0f64 { inner = 0.0f64 }
    let mmf = f64(mm)
    out[0usize] = math.sqrt[f64](inner)
    out[1usize] = ld.sum_ld(hu[0usize..mm]) / mmf / (mmf - 1.0f64)
    out[2usize] = 2.0f64 * math.sqrt[f64](rm / mmf) + math.sqrt[f64](x87.log_r(1.0f64 / alpha) * 4.0f64 * rm / mmf)
    out[3usize] = 0.0f64
    if !asymptotic { ret ok }
    // bootstrap bound
    let (boot, e8) = mem.alloc[f64](a, ntimes)
    if e8 != ok { ret e8 }
    var ns = usize(math.ceil[f64](frac * mmf))
    if ns < 1usize { ns = 1usize }
    var it = 0usize
    while it < ntimes {
        let mark = mem.mark(a)
        let (xs, f1) = rr.sample_int(a, g, i64(m), i64(ns), replace)
        if f1 != ok { ret f1 }
        let (ys, f2) = rr.sample_int(a, g, i64(n), i64(ns), replace)
        if f2 != ok { ret f2 }
        let (perm, f3) = rr.sample_int(a, g, i64(2usize * ns), i64(2usize * ns), false)
        if f3 != ok { ret f3 }
        // newlab[k] (1-based label): x draws then m + y draws; samplenew = newlab[perm]
        var kx = 0usize
        var ky = 0usize
        var k = 0usize
        while k < 2usize * ns {
            let pk = usize(perm[k]) - 1usize
            var lab = 0usize
            if pk < ns {
                lab = usize(xs[pk]) - 1usize
            } else {
                lab = m + usize(ys[pk - ns]) - 1usize
            }
            if k < ns {
                lx[kx] = lab
                kx += 1usize
            } else {
                ly[ky] = lab
                ky += 1usize
            }
            k += 1usize
        }
        // group the x labels (those below m, then the rest), keeping order inside each group
        regroup(lx, ns, m, col)
        regroup(ly, ns, m, col)
        hu_block(kxx, kyy, kxy, m, n, lx, ly, ns, col, hu)
        let nsf = f64(ns)
        boot[it] = ld.sum_ld(hu[0usize..ns]) / nsf / (nsf - 1.0f64)
        mem.reset(a, mark)
        it += 1usize
    }
    // sort decreasing, then the mean of the aind-th and next
    var s = 1usize
    while s < ntimes {
        let v = boot[s]
        var t = s
        while t > 0usize && boot[t - 1usize] < v {
            boot[t] = boot[t - 1usize]
            t -= 1usize
        }
        boot[t] = v
        s += 1usize
    }
    let aind = usize(math.floor[f64](alpha * f64(ntimes)))
    col[0usize] = boot[aind - 1usize]
    col[1usize] = boot[aind]
    out[3usize] = ld.sum_ld(col[0usize..2usize]) / 2.0f64
    ret ok
}

// stable partition of lab[0..k]: labels below m first, the rest after
fn regroup(lab: []usize, k: usize, m: usize, tmp: []f64) {
    var w = 0usize
    var i = 0usize
    while i < k {
        if lab[i] < m {
            tmp[w] = f64(lab[i])
            w += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        if lab[i] >= m {
            tmp[w] = f64(lab[i])
            w += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < k {
        lab[i] = usize(tmp[i])
        i += 1usize
    }
}
