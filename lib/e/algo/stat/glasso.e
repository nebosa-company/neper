// R glasso 1.11 (Friedman, Hastie, Tibshirani): a port of glasso.f. The connected-component split of the penalty graph,
// the coordinate descent of lasinv1 (exact, and the one-pass approximate form), the lasso inner loop, the inverse
// recovery, and glassopath (a warm-started path over a rho list). All matrices are column-major n by n, as Fortran holds
// them; the rho matrix is the full penalty (R builds it from a scalar, a vector or a matrix, and sets BIG on `zero` pairs).
//
// Not here: the trace output, the memory-allocation error code.

use e.math
use e.mem

fn zalloc(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

// lasso(rho, n, vv, s, thr, x): s is the residual, updated in place along with x
fn lasso(ro: []const f64, n: usize, vv: []const f64, s: []f64, thr: f64, x: []f64) {
    var j = 0usize
    while j < n {
        var acc = 0.0f64
        var i = 0usize
        while i < n {
            if x[i] != 0.0f64 { acc += x[i] * vv[j * n + i] }
            i += 1usize
        }
        s[j] = s[j] - acc
        j += 1usize
    }
    var go = true
    while go {
        var dlx = 0.0f64
        j = 0usize
        while j < n {
            let xj = x[j]
            x[j] = 0.0f64
            let t = s[j] + vv[j * n + j] * xj
            let at = math.abs[f64](t)
            if at - ro[j] > 0.0f64 {
                if t < 0.0f64 {
                    x[j] = 0.0f64 - (at - ro[j]) / vv[j * n + j]
                } else {
                    x[j] = (at - ro[j]) / vv[j * n + j]
                }
            }
            if x[j] != xj {
                let del = x[j] - xj
                if math.abs[f64](del) > dlx { dlx = math.abs[f64](del) }
                var i = 0usize
                while i < n {
                    s[i] = s[i] - del * vv[j * n + i]
                    i += 1usize
                }
            }
            j += 1usize
        }
        if dlx < thr { go = false }
    }
}

// setup(m, n, ss, rho, ww, vv, s, r), m 0-based
fn setup(m: usize, n: usize, ss: []const f64, rho: []const f64, ww: []const f64, vv: []f64, s: []f64, r: []f64) {
    let nm1 = n - 1usize
    var l = 0usize
    var j = 0usize
    while j < n {
        if j != m {
            r[l] = rho[m * n + j]
            s[l] = ss[m * n + j]
            var i = 0usize
            var k = 0usize
            while k < n {
                if k != m {
                    vv[l * nm1 + i] = ww[j * n + k]
                    i += 1usize
                }
                k += 1usize
            }
            l += 1usize
        }
        j += 1usize
    }
}

// lasinv1: info[0] = niter, info[1] = del
fn lasinv(a: *mem.Arena, n: usize, ss: []const f64, rho: []const f64, ia: bool, is: bool, ipen: bool, thr: f64, maxit: usize, ww: []f64, wwi: []f64, info: []f64) -> err {
    let nm1 = n - 1usize
    let mk = mem.mark(a)
    let (vv, e1) = zalloc(a, nm1 * nm1)
    let (xs, e2) = zalloc(a, nm1 * n)
    let (s, e3) = zalloc(a, nm1)
    let (so, e4) = zalloc(a, nm1)
    let (x, e5) = zalloc(a, nm1)
    let (ro, e6) = zalloc(a, nm1)
    let (ws, e7) = zalloc(a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    info[0] = 0.0f64
    info[1] = 0.0f64
    var shr = 0.0f64
    var j = 0usize
    while j < n {
        var k = 0usize
        while k < n {
            if j != k { shr += math.abs[f64](ss[k * n + j]) }
            k += 1usize
        }
        j += 1usize
    }
    if shr == 0.0f64 {
        var i = 0usize
        while i < n * n {
            ww[i] = 0.0f64
            wwi[i] = 0.0f64
            i += 1usize
        }
        j = 0usize
        while j < n {
            ww[j * n + j] = ss[j * n + j]
            if ipen { ww[j * n + j] = ss[j * n + j] + rho[j * n + j] }
            var d = ww[j * n + j]
            let eps = f64(1.0e-7f32)
            if d < eps { d = eps }
            wwi[j * n + j] = 1.0f64 / d
            j += 1usize
        }
        mem.reset(a, mk)
        ret ok
    }
    shr = thr * shr / f64(nm1)
    if ia {
        if !is {
            var i = 0usize
            while i < n * n {
                wwi[i] = 0.0f64
                i += 1usize
            }
        }
        var m = 0usize
        while m < n {
            setup(m, n, ss, rho, ss, vv, s, ro)
            var l = 0usize
            j = 0usize
            while j < n {
                if j != m {
                    x[l] = wwi[m * n + j]
                    l += 1usize
                }
                j += 1usize
            }
            lasso(ro, nm1, vv, s, shr / f64(n), x)
            l = 0usize
            j = 0usize
            while j < n {
                if j != m {
                    wwi[m * n + j] = x[l]
                    l += 1usize
                }
                j += 1usize
            }
            m += 1usize
        }
        info[0] = 1.0f64
        mem.reset(a, mk)
        ret ok
    }
    if !is {
        var i = 0usize
        while i < n * n {
            ww[i] = ss[i]
            i += 1usize
        }
    } else {
        j = 0usize
        while j < n {
            let xjj = 0.0f64 - wwi[j * n + j]
            var l = 0usize
            var k = 0usize
            while k < n {
                if k != j {
                    xs[j * nm1 + l] = wwi[j * n + k] / xjj
                    l += 1usize
                }
                k += 1usize
            }
            j += 1usize
        }
    }
    j = 0usize
    while j < n {
        ww[j * n + j] = ss[j * n + j]
        if ipen { ww[j * n + j] = ss[j * n + j] + rho[j * n + j] }
        j += 1usize
    }
    var niter = 0usize
    var dlx = 0.0f64
    var go = true
    while go {
        dlx = 0.0f64
        var m = 0usize
        while m < n {
            var i = 0usize
            while i < nm1 {
                x[i] = xs[m * nm1 + i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                ws[i] = ww[m * n + i]
                i += 1usize
            }
            setup(m, n, ss, rho, ww, vv, s, ro)
            i = 0usize
            while i < nm1 {
                so[i] = s[i]
                i += 1usize
            }
            var sv = 0.0f64
            i = 0usize
            while i < nm1 * nm1 {
                sv += math.abs[f64](vv[i])
                i += 1usize
            }
            lasso(ro, nm1, vv, s, shr / sv, x)
            var l = 0usize
            j = 0usize
            while j < n {
                if j != m {
                    ww[m * n + j] = so[l] - s[l]
                    ww[j * n + m] = ww[m * n + j]
                    l += 1usize
                }
                j += 1usize
            }
            var sd = 0.0f64
            i = 0usize
            while i < n {
                sd += math.abs[f64](ww[m * n + i] - ws[i])
                i += 1usize
            }
            if sd > dlx { dlx = sd }
            i = 0usize
            while i < nm1 {
                xs[m * nm1 + i] = x[i]
                i += 1usize
            }
            m += 1usize
        }
        niter += 1usize
        if niter >= maxit { go = false }
        if dlx < shr { go = false }
    }
    info[0] = f64(niter)
    info[1] = dlx / f64(nm1)
    // inv(n, ww, xs, wwi)
    var q = 0usize
    while q < nm1 * n {
        xs[q] = 0.0f64 - xs[q]
        q += 1usize
    }
    j = 0usize
    while j < n {
        var k = 0usize
        var part = 0.0f64
        while k < j {
            part += xs[j * nm1 + k] * ww[j * n + k]
            k += 1usize
        }
        var part2 = 0.0f64
        k = j + 1usize
        while k < n {
            part2 += xs[j * nm1 + (k - 1usize)] * ww[j * n + k]
            k += 1usize
        }
        var acc = ww[j * n + j] + part + part2
        if j == 0usize { acc = ww[j * n + j] + part2 }
        if j == n - 1usize { acc = ww[j * n + j] + part }
        let d = 1.0f64 / acc
        wwi[j * n + j] = d
        k = 0usize
        while k < j {
            wwi[j * n + k] = d * xs[j * nm1 + k]
            k += 1usize
        }
        k = j + 1usize
        while k < n {
            wwi[j * n + k] = d * xs[j * nm1 + (k - 1usize)]
            k += 1usize
        }
        j += 1usize
    }
    mem.reset(a, mk)
    ret ok
}

// row: from the nr nodes at ir[jstart..], mark and append (at ir[kstart..]) the unmarked neighbours; returns their count
fn row(nc: usize, jstart: usize, nr: usize, kstart: usize, n: usize, ss: []const f64, rho: []const f64, ie: []usize, ir: []usize) -> usize {
    var na = 0usize
    var l = 0usize
    while l < nr {
        let k = ir[jstart + l]
        var j = 0usize
        while j < n {
            if ie[j] == 0usize && j != k {
                if math.abs[f64](ss[k * n + j]) > rho[k * n + j] {
                    ir[kstart + na] = j
                    na += 1usize
                    ie[j] = nc
                }
            }
            j += 1usize
        }
        l += 1usize
    }
    ret na
}

// connect: the components of the graph |ss(j,k)| > rho(j,k). ir holds the nodes (0-based) in component order, ic1 / ic2 the
// first and last position (0-based, inclusive) of each component; returns the component count.
fn connect(n: usize, ss: []const f64, rho: []const f64, ir: []usize, ic1: []usize, ic2: []usize, ie: []usize) -> usize {
    var i = 0usize
    while i < n {
        ie[i] = 0usize
        i += 1usize
    }
    var nc = 0usize
    var is = 1usize
    var k = 0usize
    while k < n {
        if ie[k] == 0usize {
            ir[is - 1usize] = k
            nc += 1usize
            ie[k] = nc
            ic1[nc - 1usize] = is - 1usize
            is += 1usize
            var na = row(nc, is - 2usize, 1usize, is - 1usize, n, ss, rho, ie, ir)
            if na == 0usize {
                ic2[nc - 1usize] = is - 2usize
            } else {
                var il = 0usize
                var go = true
                while go {
                    let nas = na
                    let iss = is
                    il = iss + nas - 1usize
                    if il >= n {
                        go = false
                    } else {
                        is = is + na
                        na = row(nc, iss - 1usize, nas, is - 1usize, n, ss, rho, ie, ir)
                        if na == 0usize { go = false }
                    }
                }
                ic2[nc - 1usize] = il - 1usize
            }
        }
        k += 1usize
    }
    ret nc
}

// glasso(s, rho, ...): www and wwwi are read when is (a warm start) and always written; info[0] = niter, info[1] = del
fn fit(a: *mem.Arena, n: usize, sss: []const f64, rrho: []const f64, ia: bool, is: bool, ipen: bool, thr: f64, maxit: usize, www: []f64, wwwi: []f64, info: []f64) -> err {
    if ia {
        ret lasinv(a, n, sss, rrho, ia, is, ipen, thr, maxit, www, wwwi, info)
    }
    let mk = mem.mark(a)
    let (ir, e1) = mem.alloc[usize](a, n)
    let (ic1, e2) = mem.alloc[usize](a, n)
    let (ic2, e3) = mem.alloc[usize](a, n)
    let (ie, e4) = mem.alloc[usize](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    let nc = connect(n, sss, rrho, ir, ic1, ic2, ie)
    var nnq = 0usize
    var kc = 0usize
    while kc < nc {
        let sz = ic2[kc] - ic1[kc] + 1usize
        if sz > nnq { nnq = sz }
        kc += 1usize
    }
    nnq = nnq * nnq
    let (ss, e5) = zalloc(a, nnq)
    let (rho, e6) = zalloc(a, nnq)
    let (ww, e7) = zalloc(a, nnq)
    let (wwi, e8) = zalloc(a, nnq)
    let (inf, e9) = zalloc(a, 2usize)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    var nniter = 0.0f64
    var ddel = 0.0f64
    kc = 0usize
    while kc < nc {
        let kb = ic1[kc]
        let ke = ic2[kc]
        let sz = ke - kb + 1usize
        if sz == 1usize {
            let k = ir[kb]
            var q = 0usize
            while q < n {
                www[k * n + q] = 0.0f64
                www[q * n + k] = 0.0f64
                wwwi[k * n + q] = 0.0f64
                wwwi[q * n + k] = 0.0f64
                q += 1usize
            }
        } else {
            var l = 0usize
            var k = kb
            while k <= ke {
                let ik = ir[k]
                var j = kb
                while j <= ke {
                    let ij = ir[j]
                    ss[l] = sss[ik * n + ij]
                    rho[l] = rrho[ik * n + ij]
                    ww[l] = www[ik * n + ij]
                    wwi[l] = wwwi[ik * n + ij]
                    l += 1usize
                    j += 1usize
                }
                k += 1usize
            }
            let sq = sz * sz
            let le = lasinv(a, sz, ss[0usize..sq], rho[0usize..sq], ia, is, ipen, thr, maxit, ww[0usize..sq], wwi[0usize..sq], inf)
            if le != ok { ret le }
            nniter += inf[0]
            ddel += inf[1]
            var jj = kb
            while jj <= ke {
                let kk = ir[jj]
                var q = 0usize
                while q < n {
                    www[kk * n + q] = 0.0f64
                    www[q * n + kk] = 0.0f64
                    wwwi[kk * n + q] = 0.0f64
                    wwwi[q * n + kk] = 0.0f64
                    q += 1usize
                }
                jj += 1usize
            }
            l = 0usize
            k = kb
            while k <= ke {
                let ik = ir[k]
                var j = kb
                while j <= ke {
                    wwwi[ik * n + ir[j]] = wwi[l]
                    www[ik * n + ir[j]] = ww[l]
                    l += 1usize
                    j += 1usize
                }
                k += 1usize
            }
        }
        kc += 1usize
    }
    ddel = ddel / f64(nc)
    var j = 0usize
    while j < n {
        if www[j * n + j] == 0.0f64 {
            www[j * n + j] = sss[j * n + j]
            if ipen { www[j * n + j] = sss[j * n + j] + rrho[j * n + j] }
            wwwi[j * n + j] = 1.0f64 / www[j * n + j]
        }
        j += 1usize
    }
    info[0] = nniter
    info[1] = ddel
    mem.reset(a, mk)
    ret ok
}

// glassopath: rholist ascending (R sorts it), a scalar penalty at each value. beta and what hold the nrho inverse and
// covariance estimates, n * n each, in rholist order. The first fit at the largest rho is cold, then every rho from the
// largest down is warm-started from the previous one.
fn path(a: *mem.Arena, n: usize, s: []const f64, rholist: []const f64, ia: bool, ipen: bool, thr: f64, maxit: usize, beta: []f64, what: []f64) -> err {
    let nrho = rholist.len
    let nn = n * n
    let (rho, e1) = zalloc(a, nn)
    let (ww, e2) = zalloc(a, nn)
    let (wwi, e3) = zalloc(a, nn)
    let (info, e4) = zalloc(a, 2usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var q = 0usize
    while q < nn {
        rho[q] = rholist[nrho - 1usize]
        q += 1usize
    }
    let f0 = fit(a, n, s, rho, ia, false, ipen, thr, maxit, ww, wwi, info)
    if f0 != ok { ret f0 }
    q = 0usize
    while q < nn {
        beta[(nrho - 1usize) * nn + q] = wwi[q]
        what[(nrho - 1usize) * nn + q] = ww[q]
        q += 1usize
    }
    var i = nrho
    while i > 0usize {
        i -= 1usize
        q = 0usize
        while q < nn {
            rho[q] = rholist[i]
            q += 1usize
        }
        let f1 = fit(a, n, s, rho, ia, true, ipen, thr, maxit, ww, wwi, info)
        if f1 != ok { ret f1 }
        q = 0usize
        while q < nn {
            beta[i * nn + q] = wwi[q]
            what[i * nn + q] = ww[q]
            q += 1usize
        }
    }
    ret ok
}
