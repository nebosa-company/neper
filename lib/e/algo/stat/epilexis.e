// R Epi: Lexis objects on two time scales as flat tables, splitLexis on one time scale (splitLexis.1D), cutLexis with numeric states (precursor states, the progressive
// rule, the time since the cut as a new time scale), the Poisson person-years cells of a split object and ci.lin's linear combinations with their Wald intervals.
//
// A row of a Lexis table is 6 numbers: lex.id, the entry on the first time scale, the entry on the second, lex.dur, lex.Cst and lex.Xst (states are numbers).
//
// Not here: factor states, split.states, count = TRUE, the data frame form of `cut`, more than two time scales, apc.fit, and ci.lin's diffs, subset and sample options.

use e.math
use e.math.dist as dist
use e.mem
use e.algo.stat.armglm as ag

// splitLexis(lex, breaks, time.scale = scale + 1) for scale 0 or 1; breaks sorted ascending. The output row cap is nrows * (nbrk + 1).
fn split1(a: *mem.Arena, tab: []const f64, nrows: usize, scale: usize, brk: []const f64) -> (usize, []f64, err) {
    let (out, ee) = mem.alloc[f64](a, nrows * (brk.len + 1usize) * 6usize + 1usize)
    if ee != ok { ret (0usize, out, ee) }
    let tol = 1.4901161193847656e-8f64
    var nout = 0usize
    var r = 0usize
    while r < nrows {
        let t1 = tab[r * 6usize + 1usize + scale]
        let t2 = t1 + tab[r * 6usize + 3usize]
        // the valid intervals first, then each one's entry shift is the sum of the durations before it
        var shift = 0.0f64
        var last = 0usize
        var j = 0usize
        while j <= brk.len {
            var en = t1
            var ex = t2
            if j > 0usize && brk[j - 1usize] > en { en = brk[j - 1usize] }
            if j < brk.len && brk[j] < ex { ex = brk[j] }
            if en < ex - tol { last = j }
            j += 1usize
        }
        j = 0usize
        while j <= brk.len {
            var en = t1
            var ex = t2
            if j > 0usize && brk[j - 1usize] > en { en = brk[j - 1usize] }
            if j < brk.len && brk[j] < ex { ex = brk[j] }
            if en < ex - tol {
                let d = ex - en
                let o = nout * 6usize
                out[o] = tab[r * 6usize]
                out[o + 1usize] = tab[r * 6usize + 1usize] + shift
                out[o + 2usize] = tab[r * 6usize + 2usize] + shift
                out[o + 3usize] = d
                out[o + 4usize] = tab[r * 6usize + 4usize]
                out[o + 5usize] = tab[r * 6usize + 4usize]
                if j == last { out[o + 5usize] = tab[r * 6usize + 5usize] }
                nout += 1usize
                shift += d
            }
            j += 1usize
        }
        r += 1usize
    }
    ret (nout, out, ok)
}

// cutLexis(lex, cut, timescale = scale + 1, new.state, new.scale, progressive, precursor.states): cut and new_state have one entry per row; nprec < 0 asks for
// the default transient(data), the distinct lex.Cst. The output has 7 columns, the last the time since the cut (0 where R has NA), sorted by lex.id then the first time scale.
fn cut1(a: *mem.Arena, tab: []const f64, nrows: usize, scale: usize, prog: bool, prec: []const f64, defprec: bool, cut: []const f64, ns: []const f64) -> (usize, []f64, err) {
    let (out, ee) = mem.alloc[f64](a, nrows * 14usize + 7usize)
    if ee != ok { ret (0usize, out, ee) }
    var nout = 0usize
    var r = 0usize
    while r < nrows {
        let b = r * 6usize
        let e = tab[b + 1usize + scale]
        let ex = e + tab[b + 3usize]
        var ex1 = ex
        if cut[r] < ex1 { ex1 = cut[r] }
        let d1 = ex1 - e
        if d1 > 0.0f64 {
            let o = nout * 7usize
            out[o] = tab[b]
            out[o + 1usize] = tab[b + 1usize]
            out[o + 2usize] = tab[b + 2usize]
            out[o + 3usize] = d1
            out[o + 4usize] = tab[b + 4usize]
            out[o + 5usize] = tab[b + 5usize]
            if cut[r] < ex { out[o + 5usize] = ns[r] }
            out[o + 6usize] = 0.0f64
            nout += 1usize
        }
        var in2 = e
        if cut[r] > in2 { in2 = cut[r] }
        let d2 = ex - in2
        if d2 > 0.0f64 {
            let o = nout * 7usize
            out[o] = tab[b]
            out[o + 1usize] = (tab[b + 1usize] + tab[b + 3usize]) - d2
            out[o + 2usize] = (tab[b + 2usize] + tab[b + 3usize]) - d2
            out[o + 3usize] = d2
            out[o + 4usize] = ns[r]
            let xs = tab[b + 5usize]
            var isp = false
            if defprec {
                var q = 0usize
                while q < nrows {
                    if tab[q * 6usize + 4usize] == xs { isp = true }
                    q += 1usize
                }
            }
            var q2 = 0usize
            while q2 < prec.len {
                if prec[q2] == xs { isp = true }
                q2 += 1usize
            }
            if prog && xs < ns[r] { isp = true }
            out[o + 5usize] = xs
            if isp { out[o + 5usize] = ns[r] }
            out[o + 6usize] = in2 - cut[r]
            nout += 1usize
        }
        r += 1usize
    }
    // a stable insertion sort of the rows by (lex.id, first time scale)
    var i = 1usize
    while i < nout {
        var j = i
        while j > 0usize {
            let p = (j - 1usize) * 7usize
            let c = j * 7usize
            var swap = false
            if out[c] < out[p] { swap = true }
            if out[c] == out[p] && out[c + 1usize] < out[p + 1usize] { swap = true }
            if !swap { break }
            var k = 0usize
            while k < 7usize {
                let t = out[p + k]
                out[p + k] = out[c + k]
                out[c + k] = t
                k += 1usize
            }
            j -= 1usize
        }
        i += 1usize
    }
    ret (nout, out, ok)
}

// findInterval(x, breaks): the number of breaks at or below x
fn band(x: f64, brk: []const f64) -> usize {
    var n = 0usize
    while n < brk.len && brk[n] <= x { n += 1usize }
    ret n
}

type Cells = struct { n: usize, p: usize, y: []const f64, d: []const f64, coef: []const f64, cov: []const f64 }

// The person-years and event (lex.Xst == 2) cells of a table split on age (scale 1) at brk_a and on per (scale 0) at brk_p, ordered by period band then age band as
// aggregate(~ A + P) does, and glm(D ~ factor(A) + factor(P) + offset(log(Y)), poisson) over them: p coefficients and their covariance (the dispersion is 1).
fn rate_cells(a: *mem.Arena, tab: []const f64, nrows: usize, brk_a: []const f64, brk_p: []const f64) -> (Cells, err) {
    var c = Cells { n: 0usize, p: 0usize, y: tab[0usize..0usize], d: tab[0usize..0usize], coef: tab[0usize..0usize], cov: tab[0usize..0usize] }
    let (n1, t1, e1) = split1(a, tab, nrows, 1usize, brk_a)
    if e1 != ok { ret (c, e1) }
    let (n2, t2, e2) = split1(a, t1[0usize..n1 * 6usize], n1, 0usize, brk_p)
    if e2 != ok { ret (c, e2) }
    let nb = brk_a.len + 1usize
    let np = brk_p.len + 1usize
    let (cy, e3) = mem.alloc[f64](a, nb * np)
    let (cd, e4) = mem.alloc[f64](a, nb * np)
    if e3 != ok || e4 != ok { ret (c, mem.Exhausted) }
    var i = 0usize
    while i < nb * np {
        cy[i] = 0.0f64
        cd[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n2 {
        let ba = band(t2[i * 6usize + 2usize], brk_a)
        let bp = band(t2[i * 6usize + 1usize], brk_p)
        cy[bp * nb + ba] += t2[i * 6usize + 3usize]
        if t2[i * 6usize + 5usize] == 2.0f64 { cd[bp * nb + ba] += 1.0f64 }
        i += 1usize
    }
    // the levels present, and the cells that exist (positive person-years)
    var la = 0usize
    var lp = 0usize
    var ncell = 0usize
    let (ia, e5) = mem.alloc[usize](a, nb)
    let (ip, e6) = mem.alloc[usize](a, np)
    if e5 != ok || e6 != ok { ret (c, mem.Exhausted) }
    i = 0usize
    while i < nb {
        ia[i] = nb
        i += 1usize
    }
    i = 0usize
    while i < np {
        ip[i] = np
        i += 1usize
    }
    var q = 0usize
    while q < np {
        var w = 0usize
        while w < nb {
            if cy[q * nb + w] > 0.0f64 {
                ia[w] = 0usize
                ip[q] = 0usize
                ncell += 1usize
            }
            w += 1usize
        }
        q += 1usize
    }
    i = 0usize
    while i < nb {
        if ia[i] == 0usize {
            ia[i] = la
            la += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < np {
        if ip[i] == 0usize {
            ip[i] = lp
            lp += 1usize
        }
        i += 1usize
    }
    let k = la + lp - 1usize
    let (x, e7) = mem.alloc[f64](a, ncell * k)
    let (y, e8) = mem.alloc[f64](a, ncell)
    let (off, e9) = mem.alloc[f64](a, ncell)
    let (yy, e10) = mem.alloc[f64](a, ncell)
    let (cf, e11) = mem.alloc[f64](a, k)
    let (cv, e12) = mem.alloc[f64](a, k * k)
    let (info, e13) = mem.alloc[f64](a, 8usize)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (c, mem.Exhausted) }
    var r = 0usize
    i = 0usize
    while i < ncell * k {
        x[i] = 0.0f64
        i += 1usize
    }
    q = 0usize
    while q < np {
        var w = 0usize
        while w < nb {
            if cy[q * nb + w] > 0.0f64 {
                x[r * k] = 1.0f64
                if ia[w] > 0usize { x[r * k + ia[w]] = 1.0f64 }
                if ip[q] > 0usize { x[r * k + la - 1usize + ip[q]] = 1.0f64 }
                y[r] = cd[q * nb + w]
                yy[r] = cy[q * nb + w]
                off[r] = math.log[f64](cy[q * nb + w])
                r += 1usize
            }
            w += 1usize
        }
        q += 1usize
    }
    let none = y[0usize..0usize]
    let it = ag.glm_fit_gen(a, x, y, ncell, k, 2usize, 1usize, none, off, true, cf, cv, info)
    if it == 0usize { ret (c, mem.Exhausted) }
    c.n = ncell
    c.p = k
    c.y = yy
    c.d = y
    c.coef = cf
    c.cov = cv
    ret (c, ok)
}

// ci.lin(fit, ctr.mat = row, Exp = TRUE, alpha) for one row: estimate, standard error, z, P, exp(estimate), exp of the lower and upper limits.
fn ci_lin(cf: []const f64, cov: []const f64, p: usize, ctr: []const f64, alpha: f64, out: []f64) {
    var ct = 0.0f64
    var i = 0usize
    while i < p {
        ct += ctr[i] * cf[i]
        i += 1usize
    }
    var vc = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        var s = 0.0f64
        while j < p {
            s += cov[i * p + j] * ctr[j]
            j += 1usize
        }
        vc += ctr[i] * s
        i += 1usize
    }
    let se = math.sqrt[f64](vc)
    let z = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let zz = ct / se
    var az = zz
    if az < 0.0f64 { az = 0.0f64 - az }
    out[0usize] = ct
    out[1usize] = se
    out[2usize] = zz
    out[3usize] = 2.0f64 * dist.pnorm(0.0f64 - az, 0.0f64, 1.0f64, true, false)
    out[4usize] = math.exp[f64](ct)
    out[5usize] = math.exp[f64](ct - z * se)
    out[6usize] = math.exp[f64](ct + z * se)
}
