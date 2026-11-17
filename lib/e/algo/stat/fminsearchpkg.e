// R pracma::fminsearch with method "Nelder-Mead": the package's nelder_mead (Algorithm AS 47 with the adaptive coefficients), step by step, on a fixed set of test functions,
// with the restart that checks the answer is a local minimum along each coordinate.
//
// Not here: user functions, the non-adaptive coefficients, Hooke-Jeeves and bounds.

use e.math
use e.mem
use e.algo.rand.r as rng

// the test functions: 0 Rosenbrock, 1 sum (x_i - i)^2 (three variables), 2 Beale, 3 Himmelblau, 4 a quartic bowl x1^4 + x2^4 + x1 x2 + (x1 - 1)^2
fn tf(id: usize, x: []const f64) -> f64 {
    if id == 0usize {
        let a = x[1usize] - x[0usize] * x[0usize]
        let b = 1.0f64 - x[0usize]
        ret 100.0f64 * a * a + b * b
    }
    if id == 1usize {
        var s = 0.0f64
        var i = 0usize
        while i < 3usize {
            let d = x[i] - f64(i + 1usize)
            s += d * d
            i += 1usize
        }
        ret s
    }
    if id == 2usize {
        let a = 1.5f64 - x[0usize] + x[0usize] * x[1usize]
        let b = 2.25f64 - x[0usize] + x[0usize] * x[1usize] * x[1usize]
        let c = 2.625f64 - x[0usize] + x[0usize] * x[1usize] * x[1usize] * x[1usize]
        ret a * a + b * b + c * c
    }
    if id == 3usize {
        let a = x[0usize] * x[0usize] + x[1usize] - 11.0f64
        let b = x[0usize] + x[1usize] * x[1usize] - 7.0f64
        ret a * a + b * b
    }
    let d = x[0usize] - 1.0f64
    ret x[0usize] * x[0usize] * x[0usize] * x[0usize] + x[1usize] * x[1usize] * x[1usize] * x[1usize] + x[0usize] * x[1usize] + d * d
}

fn dim_of(id: usize) -> usize {
    if id == 1usize { ret 3usize }
    ret 2usize
}

fn which_min(y: []const f64, n: usize) -> usize {
    var k = 0usize
    var i = 1usize
    while i < n {
        if y[i] < y[k] { k = i }
        i += 1usize
    }
    ret k
}

fn which_max(y: []const f64, n: usize) -> usize {
    var k = 0usize
    var i = 1usize
    while i < n {
        if y[i] > y[k] { k = i }
        i += 1usize
    }
    ret k
}

// nelder_mead(fn, x0, tol, maxfeval = 5000, step = 1, adapt = TRUE): the minimiser into xmin, the minimum and the evaluation count and restarts; work holds 6 * (n + 1) * n values
fn nelder_mead(id: usize, x0: []const f64, tol: f64, maxfeval: usize, xmin: []f64, work: []f64) -> (f64, usize, usize) {
    let n = dim_of(id)
    let dn = f64(n)
    let nn = n + 1usize
    let rcoeff = 1.0f64
    let ecoeff = 1.0f64 + 2.0f64 / dn
    let ccoeff = 0.75f64 - 1.0f64 / (2.0f64 * dn)
    let scoeff = 1.0f64 - 1.0f64 / dn
    let eps = 0.001f64
    let kcount = maxfeval
    let konvge = maxfeval / 100usize
    let rq = tol * dn
    let p = work[0usize..nn * n]
    let y = work[nn * n..nn * n + nn]
    let start = work[nn * n + nn..nn * n + nn + n]
    let pbar = work[nn * n + nn + n..nn * n + nn + 2usize * n]
    let pstar = work[nn * n + nn + 2usize * n..nn * n + nn + 3usize * n]
    let p2star = work[nn * n + nn + 3usize * n..nn * n + nn + 4usize * n]
    var i = 0usize
    while i < n {
        start[i] = x0[i]
        i += 1usize
    }
    var icount = 0usize
    var numres = 0usize
    var del = 1.0f64
    var jcount = konvge
    var ynewlo = 0.0f64
    var ilo = 0usize
    var ylo = 0.0f64
    while true {
        // columns of p are stored as p[col * n + row]
        i = 0usize
        while i < n {
            p[n * n + i] = start[i]
            i += 1usize
        }
        y[n] = tf(id, start)
        icount += 1usize
        var j = 0usize
        while j < n {
            let x = start[j]
            start[j] = start[j] + del
            i = 0usize
            while i < n {
                p[j * n + i] = start[i]
                i += 1usize
            }
            y[j] = tf(id, start)
            icount += 1usize
            start[j] = x
            j += 1usize
        }
        ilo = which_min(y, nn)
        ylo = y[ilo]
        var inner = true
        while inner && icount < kcount {
            let ihi = which_max(y, nn)
            ynewlo = y[ihi]
            i = 0usize
            while i < n {
                var s = 0.0f64
                var c = 0usize
                while c < nn {
                    if c != ihi { s += p[c * n + i] }
                    c += 1usize
                }
                pbar[i] = s / dn
                pstar[i] = pbar[i] + rcoeff * (pbar[i] - p[ihi * n + i])
                i += 1usize
            }
            let ystar = tf(id, pstar)
            icount += 1usize
            var skip = false
            if ystar < ylo {
                i = 0usize
                while i < n {
                    p2star[i] = pbar[i] + ecoeff * (pstar[i] - pbar[i])
                    i += 1usize
                }
                let y2star = tf(id, p2star)
                icount += 1usize
                if ystar < y2star {
                    i = 0usize
                    while i < n {
                        p[ihi * n + i] = pstar[i]
                        i += 1usize
                    }
                    y[ihi] = ystar
                } else {
                    i = 0usize
                    while i < n {
                        p[ihi * n + i] = p2star[i]
                        i += 1usize
                    }
                    y[ihi] = y2star
                }
            } else {
                let l = count_less(y, nn, ystar)
                if l > 1usize {
                    i = 0usize
                    while i < n {
                        p[ihi * n + i] = pstar[i]
                        i += 1usize
                    }
                    y[ihi] = ystar
                } else if l == 0usize {
                    i = 0usize
                    while i < n {
                        p2star[i] = pbar[i] + ccoeff * (p[ihi * n + i] - pbar[i])
                        i += 1usize
                    }
                    let y2star = tf(id, p2star)
                    icount += 1usize
                    if y[ihi] < y2star {
                        var jj = 0usize
                        while jj < nn {
                            i = 0usize
                            while i < n {
                                p[jj * n + i] = scoeff * (p[jj * n + i] + p[ilo * n + i])
                                xmin[i] = p[jj * n + i]
                                i += 1usize
                            }
                            y[jj] = tf(id, xmin)
                            icount += 1usize
                            jj += 1usize
                        }
                        ilo = which_min(y, nn)
                        ylo = y[ilo]
                        skip = true
                    } else {
                        i = 0usize
                        while i < n {
                            p[ihi * n + i] = p2star[i]
                            i += 1usize
                        }
                        y[ihi] = y2star
                    }
                } else {
                    i = 0usize
                    while i < n {
                        p2star[i] = pbar[i] + ccoeff * (pstar[i] - pbar[i])
                        i += 1usize
                    }
                    let y2star = tf(id, p2star)
                    icount += 1usize
                    if y2star <= ystar {
                        i = 0usize
                        while i < n {
                            p[ihi * n + i] = p2star[i]
                            i += 1usize
                        }
                        y[ihi] = y2star
                    } else {
                        i = 0usize
                        while i < n {
                            p[ihi * n + i] = pstar[i]
                            i += 1usize
                        }
                        y[ihi] = ystar
                    }
                }
            }
            if !skip {
                if y[ihi] < ylo {
                    ylo = y[ihi]
                    ilo = ihi
                }
                jcount -= 1usize
                if jcount == 0usize {
                    if icount <= kcount {
                        jcount = konvge
                        var xm = 0.0f64
                        i = 0usize
                        while i < nn {
                            xm += y[i]
                            i += 1usize
                        }
                        xm = xm / f64(nn)
                        var z = 0.0f64
                        i = 0usize
                        while i < nn {
                            z += (y[i] - xm) * (y[i] - xm)
                            i += 1usize
                        }
                        if z <= rq { inner = false }
                    }
                }
            }
        }
        i = 0usize
        while i < n {
            xmin[i] = p[ilo * n + i]
            i += 1usize
        }
        ynewlo = y[ilo]
        if kcount < icount { break }
        var fault = false
        i = 0usize
        while i < n && !fault {
            del = eps
            xmin[i] = xmin[i] + del
            var z = tf(id, xmin)
            icount += 1usize
            if z < ynewlo {
                fault = true
            } else {
                xmin[i] = xmin[i] - del - del
                z = tf(id, xmin)
                icount += 1usize
                if z < ynewlo {
                    fault = true
                } else {
                    xmin[i] = xmin[i] + del
                }
            }
            if !fault { i += 1usize }
        }
        if !fault { break }
        j = 0usize
        while j < n {
            start[j] = xmin[j]
            j += 1usize
        }
        del = eps
        numres += 1usize
    }
    ret (ynewlo, icount, numres)
}

// l = sum(ystar < y)
fn count_less(y: []const f64, nn: usize, ystar: f64) -> usize {
    var c = 0usize
    var i = 0usize
    while i < nn {
        if ystar < y[i] { c += 1usize }
        i += 1usize
    }
    ret c
}

// one exploration of pracma's Hooke-Jeeves (.hjexplore, or .hjbexplore with the bounds): the coordinates in the order of sample.int(n, n) from the seeded generator; returns (fx, sf, numf) and x in xout
fn hj_explore(a: *mem.Arena, rg: *rng.Rng, id: usize, xb: []const f64, xc: []const f64, h: f64, have_fb: bool, fbold: f64, bounded: bool, lo: []const f64, up: []const f64, xout: []f64) -> (f64, usize, usize, err) {
    let n = dim_of(id)
    var numf = 0usize
    var fb = fbold
    var i = 0usize
    while i < n {
        xout[i] = xb[i]
        i += 1usize
    }
    if !have_fb {
        fb = tf(id, xb)
        numf = 1usize
    }
    let fx0 = fb
    let (xt, e1) = mem.alloc[f64](a, n)
    let (p1, e2) = mem.alloc[f64](a, n)
    let (p2, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0usize, 0usize, mem.Full) }
    i = 0usize
    while i < n {
        xt[i] = xc[i]
        i += 1usize
    }
    let (perm, ep) = rng.sample_int(a, rg, i64(n), i64(n), false)
    if ep != ok { ret (0.0f64, 0usize, 0usize, ep) }
    var sf = 0usize
    var q = 0usize
    while q < n {
        let k = usize(perm[q]) - 1usize
        i = 0usize
        while i < n {
            p1[i] = xt[i]
            p2[i] = xt[i]
            i += 1usize
        }
        p1[k] = xt[k] + h
        p2[k] = xt[k] - h
        var ft1 = fb
        var ft2 = fb
        if !bounded || p1[k] <= up[k] {
            ft1 = tf(id, p1)
            numf += 1usize
        }
        if !bounded || lo[k] <= p2[k] {
            ft2 = tf(id, p2)
            numf += 1usize
        }
        var mn = ft1
        if ft2 < mn { mn = ft2 }
        if mn < fb {
            sf = 1usize
            if ft1 < ft2 {
                i = 0usize
                while i < n {
                    xt[i] = p1[i]
                    i += 1usize
                }
                fb = ft1
            } else {
                i = 0usize
                while i < n {
                    xt[i] = p2[i]
                    i += 1usize
                }
                fb = ft2
            }
        }
        q += 1usize
    }
    var fx = fx0
    if sf == 1usize {
        i = 0usize
        while i < n {
            xout[i] = xt[i]
            i += 1usize
        }
        fx = fb
    }
    ret (fx, sf, numf, ok)
}

// fminsearch(method = "Hooke-Jeeves", tol, maxiter): pracma's .hj or .hjb (with bounds lo and up when bounded) after the seeded generator; returns (fmin, fcalls, niter, err), xmin filled
fn hooke_jeeves(a: *mem.Arena, rg: *rng.Rng, id: usize, x0: []const f64, tol: f64, maxfeval: usize, bounded: bool, lo: []const f64, up: []const f64, xmin: []f64) -> (f64, usize, usize, err) {
    let n = dim_of(id)
    let nsteps = usize(math.floor[f64]((math.log[f64](1.0f64 / tol) / math.log[f64](2.0f64))))
    let (x, e1) = mem.alloc[f64](a, n)
    let (xb, e2) = mem.alloc[f64](a, n)
    let (xc, e3) = mem.alloc[f64](a, n)
    let (xo, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, 0usize, 0usize, mem.Full) }
    var i = 0usize
    while i < n {
        x[i] = x0[i]
        i += 1usize
    }
    var fx = tf(id, x)
    var fcount = 1usize
    var ns = 0usize
    while ns < nsteps && fcount < maxfeval {
        let h = math.pow[f64](2.0f64, 0.0f64 - f64(ns))
        ns += 1usize
        // .hjsearch
        i = 0usize
        while i < n {
            xb[i] = x[i]
            xc[i] = x[i]
            i += 1usize
        }
        var finc = 0usize
        let (f1, sf1, nf1, ee1) = hj_explore(a, rg, id, xb, xc, h, false, 0.0f64, bounded, lo, up, xo)
        if ee1 != ok { ret (0.0f64, 0usize, 0usize, ee1) }
        i = 0usize
        while i < n {
            x[i] = xo[i]
            i += 1usize
        }
        fx = f1
        var sf = sf1
        finc += nf1
        while sf == 1usize {
            i = 0usize
            while i < n {
                let d = x[i] - xb[i]
                xb[i] = x[i]
                xc[i] = x[i] + d
                if bounded {
                    if xc[i] > up[i] { xc[i] = up[i] }
                    if xc[i] < lo[i] { xc[i] = lo[i] }
                }
                i += 1usize
            }
            let fb = fx
            let (f2, sf2, nf2, ee2) = hj_explore(a, rg, id, xb, xc, h, true, fb, bounded, lo, up, xo)
            if ee2 != ok { ret (0.0f64, 0usize, 0usize, ee2) }
            i = 0usize
            while i < n {
                x[i] = xo[i]
                i += 1usize
            }
            fx = f2
            sf = sf2
            finc += nf2
            if sf == 0usize {
                let (f3, sf3, nf3, ee3) = hj_explore(a, rg, id, xb, xb, h, true, fb, bounded, lo, up, xo)
                if ee3 != ok { ret (0.0f64, 0usize, 0usize, ee3) }
                i = 0usize
                while i < n {
                    x[i] = xo[i]
                    i += 1usize
                }
                fx = f3
                sf = sf3
                finc += nf3
            }
            if fcount + finc > maxfeval { break }
        }
        fcount += finc
    }
    i = 0usize
    while i < n {
        xmin[i] = x[i]
        i += 1usize
    }
    ret (fx, fcount, ns, ok)
}
