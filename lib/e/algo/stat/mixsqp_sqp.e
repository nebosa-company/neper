// R mixsqp's own algorithm: the sequential quadratic programming of Kim, Carbonetto, Stephens and Anitescu over the
// full likelihood matrix (no truncated SVD, as with `tol.svd = 0`): rows scaled by their maximum, ten EM updates,
// then per iteration an EM update, a quadratic subproblem solved by the active-set method of Nocedal and Wright
// (p. 472, with the Cholesky-plus-identity of Algorithm 3.3) and a backtracking line search. The solution, the
// objective, the status, the number of iterations and the quadratic-programming and line-search counts are the
// package's.
//
// L is n by m column-major; the weights are normalised to sum to 1 and the start to sum to 1 here.

use e.math
use e.mem

error NotPositive

type SqpControl = struct {
    convtol_sqp: f64, convtol_activeset: f64, zero_solution: f64, zero_searchdir: f64, suffdecr: f64,
    stepreduce: f64, minstep: f64, identity_increase: f64, eps: f64, maxiter_sqp: i64, maxiter_activeset: i64, numiter_em: i64
}

type SqpResult = struct { status: i64, iterations: i64, nnz: i64, nqp: i64, nls: i64, value: f64 }

fn sqp_default() -> SqpControl {
    var c: SqpControl = zero
    c.convtol_sqp = 1.0e-8f64
    c.convtol_activeset = 1.0e-10f64
    c.zero_solution = 1.0e-8f64
    c.zero_searchdir = 1.0e-14f64
    c.suffdecr = 0.01f64
    c.stepreduce = 0.75f64
    c.minstep = 1.0e-8f64
    c.identity_increase = 10.0f64
    c.eps = 1.0e-8f64
    c.maxiter_sqp = 1000i64
    c.maxiter_activeset = 0i64
    c.numiter_em = 10i64
    ret c
}

// -sum w (z + log(L x + eps))
fn sqp_obj(l: []const f64, w: []const f64, z: []const f64, n: usize, m: usize, eps: f64, x: []const f64) -> (f64, err) {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var u = eps
        var j = 0usize
        while j < m {
            u += l[j * n + i] * x[j]
            j += 1usize
        }
        if u <= 0.0f64 { ret (0.0f64, NotPositive) }
        s += w[i] * (z[i] + math.log[f64](u))
        i += 1usize
    }
    ret (0.0f64 - s, ok)
}

// one EM update of x in place: P = L scaled by x + 1e-15, rows by their maximum, plus 1e-15, rows to sum 1; x = P' w
fn sqp_em(l: []const f64, w: []const f64, n: usize, m: usize, x: []f64, pr: []f64) {
    let e = 1.0e-15f64
    var j = 0usize
    while j < m {
        pr[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var mx = 0.0f64
        j = 0usize
        while j < m {
            let v = l[j * n + i] * (x[j] + e)
            if v > mx { mx = v }
            j += 1usize
        }
        var sum = 0.0f64
        j = 0usize
        while j < m {
            sum += l[j * n + i] * (x[j] + e) / mx + e
            j += 1usize
        }
        j = 0usize
        while j < m {
            pr[j] += w[i] * ((l[j * n + i] * (x[j] + e) / mx + e) / sum)
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < m {
        x[j] = pr[j]
        j += 1usize
    }
}

// gradient g = -L'(w / u) and Hessian H = Z'Z, Z = diag(sqrt(w) / u) L, with u = L x + eps; H is m by m row-major
fn sqp_grad(l: []const f64, w: []const f64, n: usize, m: usize, eps: f64, x: []const f64, g: []f64, h: []f64, zz: []f64) {
    var j = 0usize
    while j < m {
        g[j] = 0.0f64
        var k = 0usize
        while k < m {
            h[j * m + k] = 0.0f64
            k += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        var u = eps
        j = 0usize
        while j < m {
            u += l[j * n + i] * x[j]
            j += 1usize
        }
        let sc = math.sqrt[f64](w[i]) / u
        j = 0usize
        while j < m {
            g[j] -= l[j * n + i] * (w[i] / u)
            zz[j] = l[j * n + i] * sc
            j += 1usize
        }
        j = 0usize
        while j < m {
            var k = j
            while k < m {
                h[j * m + k] += zz[j] * zz[k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < m {
        var k = 0usize
        while k < j {
            h[j * m + k] = h[k * m + j]
            k += 1usize
        }
        j += 1usize
    }
}

// the smallest feasible step along p from x (x + a p >= 0), at most 1, and the blocking coordinate (or -1)
fn sqp_feasible(x: []const f64, p: []const f64, m: usize) -> (i64, f64) {
    var a = 1.0f64
    var k = 0i64 - 1i64
    var best = 0.0f64
    var first = true
    var i = 0usize
    while i < m {
        if p[i] < 0.0f64 {
            let t = 0.0f64 - x[i] / p[i]
            if first || t < best {
                best = t
                k = i64(i)
                first = false
            }
        }
        i += 1usize
    }
    if !first && best < 1.0f64 { a = best }
    ret (k, a)
}

// Cholesky of the symmetric s by s matrix b (row-major), in place in lower form; false when a pivot is not positive
fn sqp_chol(b: []f64, s: usize) -> bool {
    var i = 0usize
    while i < s {
        var j = 0usize
        while j <= i {
            var v = b[i * s + j]
            var k = 0usize
            while k < j {
                v -= b[i * s + k] * b[j * s + k]
                k += 1usize
            }
            if i == j {
                if !(v > 0.0f64) { ret false }
                b[i * s + i] = math.sqrt[f64](v)
            } else {
                b[i * s + j] = v / b[j * s + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// solve B p = r by Gaussian elimination with partial pivoting (B overwritten)
fn sqp_solve(b: []f64, r: []f64, s: usize) {
    var col = 0usize
    while col < s {
        var piv = col
        var best = math.abs[f64](b[col * s + col])
        var q = col + 1usize
        while q < s {
            let v = math.abs[f64](b[q * s + col])
            if v > best {
                best = v
                piv = q
            }
            q += 1usize
        }
        if piv != col {
            var c = 0usize
            while c < s {
                let tv = b[col * s + c]
                b[col * s + c] = b[piv * s + c]
                b[piv * s + c] = tv
                c += 1usize
            }
            let tr = r[col]
            r[col] = r[piv]
            r[piv] = tr
        }
        q = col + 1usize
        while q < s {
            let f = b[q * s + col] / b[col * s + col]
            var c = col
            while c < s {
                b[q * s + c] -= f * b[col * s + c]
                c += 1usize
            }
            r[q] -= f * r[col]
            q += 1usize
        }
        col += 1usize
    }
    var i = s
    while i > 0usize {
        i -= 1usize
        var v = r[i]
        var c = i + 1usize
        while c < s {
            v -= b[i * s + c] * r[c]
            c += 1usize
        }
        r[i] = v / b[i * s + i]
    }
}

// the search direction of the working-set subproblem: p = -(H + a I)^-1 y with a the smallest tried multiple that makes it positive definite
fn sqp_searchdir(a: *mem.Arena, hs: []const f64, y: []const f64, p: []f64, s: usize, ainc: f64) -> err {
    let a0 = 1.0e-15f64
    let amax = 1.0e15f64
    let (bm, e0) = mem.alloc[f64](a, s * s)
    let (cm, e1) = mem.alloc[f64](a, s * s)
    if e0 != ok || e1 != ok { ret mem.Full }
    var d = hs[0usize]
    var i = 1usize
    while i < s {
        if hs[i * s + i] < d { d = hs[i * s + i] }
        i += 1usize
    }
    var mult = 0.0f64
    if !(d > a0) { mult = a0 - d }
    while true {
        i = 0usize
        while i < s * s {
            bm[i] = hs[i]
            cm[i] = hs[i]
            i += 1usize
        }
        i = 0usize
        while i < s {
            bm[i * s + i] += mult
            cm[i * s + i] += mult
            i += 1usize
        }
        if mult * ainc > amax { break }
        if sqp_chol(cm, s) { break }
        if mult <= 0.0f64 { mult = a0 } else { mult = mult * ainc }
    }
    i = 0usize
    while i < s {
        p[i] = 0.0f64 - y[i]
        i += 1usize
    }
    sqp_solve(bm, p, s)
    ret ok
}

// the active-set method for the subproblem: minimise y'Hy/2 + g'y over y >= 0 from y; answers the iterations used
fn sqp_activeset(a: *mem.Arena, h: []const f64, g: []const f64, y: []f64, m: usize, maxiter: i64, zerosd: f64, tol: f64, ainc: f64) -> (i64, err) {
    let (t, e0) = mem.alloc[bool](a, m)
    let (idx, e1) = mem.alloc[usize](a, m)
    let (hs, e2) = mem.alloc[f64](a, m * m)
    let (bv, e3) = mem.alloc[f64](a, m)
    let (bs, e4) = mem.alloc[f64](a, m)
    let (ps, e5) = mem.alloc[f64](a, m)
    let (p, e6) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (0i64, mem.Full) }
    var q = 0usize
    while q < m {
        t[q] = y[q] > 0.0f64
        q += 1usize
    }
    var iter = 0i64
    while iter < maxiter {
        var ni = 0usize
        q = 0usize
        while q < m {
            if t[q] {
                idx[ni] = q
                ni += 1usize
            } else {
                y[q] = 0.0f64
            }
            q += 1usize
        }
        var r = 0usize
        while r < ni {
            var c = 0usize
            while c < ni {
                hs[r * ni + c] = h[idx[r] * m + idx[c]]
                c += 1usize
            }
            r += 1usize
        }
        r = 0usize
        while r < ni {
            var v = g[idx[r]]
            var c = 0usize
            while c < ni {
                v += hs[r * ni + c] * y[idx[c]]
                c += 1usize
            }
            bs[r] = v
            r += 1usize
        }
        q = 0usize
        while q < m {
            p[q] = 0.0f64
            q += 1usize
        }
        if ni > 0usize {
            let es = sqp_searchdir(a, hs[0usize..ni * ni], bs[0usize..ni], ps[0usize..ni], ni, ainc)
            if es != ok { ret (0i64, es) }
        }
        r = 0usize
        while r < ni {
            p[idx[r]] = ps[r]
            r += 1usize
        }
        var pmax = 0.0f64
        q = 0usize
        while q < m {
            if math.abs[f64](p[q]) > pmax { pmax = math.abs[f64](p[q]) }
            q += 1usize
        }
        if pmax <= zerosd {
            var bmin = 0.0f64
            var kmin = 0usize
            var nz = 0usize
            q = 0usize
            while q < m {
                var v = g[q]
                var c = 0usize
                while c < m {
                    v += h[q * m + c] * y[c]
                    c += 1usize
                }
                bv[q] = v
                if !t[q] {
                    if nz == 0usize || v < bmin {
                        bmin = v
                        kmin = q
                    }
                    nz += 1usize
                }
                q += 1usize
            }
            if nz == 0usize {
                iter += 1i64
                break
            } else if bmin >= 0.0f64 - tol {
                iter += 1i64
                break
            } else {
                t[kmin] = true
            }
        } else {
            let (k, st) = sqp_feasible(y, p, m)
            var add = false
            if k >= 0i64 && st < 1.0f64 {
                if ni > 1usize { add = true }
            }
            q = 0usize
            while q < m {
                y[q] += st * p[q]
                if y[q] < 0.0f64 { y[q] = 0.0f64 }
                q += 1usize
            }
            if add {
                t[usize(k)] = false
                y[usize(k)] = 0.0f64
            }
        }
        iter += 1i64
    }
    ret (iter, ok)
}

// Solve the problem; x0 (positive, summing to anything) is replaced by the solution (summing to 1); l is n by m column-major with at least one positive entry in every row and column
fn mixsqp_sqp(a: *mem.Arena, l0: []const f64, w0: []const f64, n: usize, m: usize, x: []f64, c: SqpControl, gout: []f64, hout: []f64) -> (SqpResult, err) {
    var res: SqpResult = zero
    let (l, e0) = mem.alloc[f64](a, n * m)
    let (w, e1) = mem.alloc[f64](a, n)
    let (z, e2) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (res, mem.Full) }
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = w0[i] / sw
        var mx = 0.0f64
        var j = 0usize
        while j < m {
            if l0[j * n + i] > mx { mx = l0[j * n + i] }
            j += 1usize
        }
        z[i] = math.log[f64](mx)
        j = 0usize
        while j < m {
            l[j * n + i] = l0[j * n + i] / mx
            j += 1usize
        }
        i += 1usize
    }
    var sx = 0.0f64
    var j = 0usize
    while j < m {
        sx += x[j]
        j += 1usize
    }
    j = 0usize
    while j < m {
        x[j] = x[j] / sx
        j += 1usize
    }
    let (pr, ep) = mem.alloc[f64](a, m)
    let (g, eg) = mem.alloc[f64](a, m)
    let (h, eh) = mem.alloc[f64](a, m * m)
    let (zz, ez) = mem.alloc[f64](a, m)
    let (ghat, ea) = mem.alloc[f64](a, m)
    let (y, eb) = mem.alloc[f64](a, m)
    let (xnew, ec) = mem.alloc[f64](a, m)
    let (xold, ed) = mem.alloc[f64](a, m)
    let (pd, ee) = mem.alloc[f64](a, m)
    if ep != ok || eg != ok || eh != ok || ez != ok || ea != ok || eb != ok || ec != ok || ed != ok || ee != ok { ret (res, mem.Full) }
    var maxas = c.maxiter_activeset
    if maxas == 0i64 { maxas = i64(m) + 1i64 }
    if maxas > 20i64 { maxas = 20i64 }
    var rows = 0i64
    var k = 0i64
    while k < c.numiter_em {
        sqp_em(l, w, n, m, x, pr)
        rows += 1i64
        k += 1i64
    }
    res.status = 1i64
    var it = 0i64
    var nqp_sum = 0i64
    var nls_sum = 0i64
    while it < c.maxiter_sqp {
        j = 0usize
        while j < m {
            xold[j] = x[j]
            j += 1usize
        }
        sqp_em(l, w, n, m, x, pr)
        j = 0usize
        while j < m {
            if x[j] <= c.zero_solution { x[j] = 0.0f64 }
            j += 1usize
        }
        let (f, ef) = sqp_obj(l, w, z, n, m, c.eps, x)
        if ef != ok { ret (res, ef) }
        sqp_grad(l, w, n, m, c.eps, x, g, h, zz)
        var gmin = 0.0f64
        var any = false
        var nnz = 0i64
        j = 0usize
        while j < m {
            if x[j] > c.zero_solution {
                if !any || g[j] < gmin {
                    gmin = g[j]
                    any = true
                }
            }
            if x[j] > 0.0f64 { nnz += 1i64 }
            j += 1usize
        }
        gmin = 1.0f64 + gmin
        res.nnz = nnz
        it += 1i64
        if gmin >= 0.0f64 - c.convtol_sqp {
            res.status = 0i64
            break
        }
        // ghat = g - H x + 1 and the quadratic subproblem from y = x
        j = 0usize
        while j < m {
            var hx = 0.0f64
            var q = 0usize
            while q < m {
                hx += h[j * m + q] * x[q]
                q += 1usize
            }
            ghat[j] = g[j] - hx + 1.0f64
            y[j] = x[j]
            j += 1usize
        }
        let (nq, eq) = sqp_activeset(a, h, ghat, y, m, maxas, c.zero_searchdir, c.convtol_activeset, c.identity_increase)
        if eq != ok { ret (res, eq) }
        nqp_sum += nq
        // backtracking line search along p = y - x
        j = 0usize
        while j < m {
            pd[j] = y[j] - x[j]
            j += 1usize
        }
        let (_kf, afeas) = sqp_feasible(x, pd, m)
        var step = 0.0f64
        if afeas <= c.minstep {
            step = afeas
            j = 0usize
            while j < m {
                xnew[j] = afeas * y[j] + (1.0f64 - afeas) * x[j]
                j += 1usize
            }
        } else {
            step = 1.0f64
            if afeas < step { step = afeas }
            var sumx = 0.0f64
            var dg = 0.0f64
            j = 0usize
            while j < m {
                sumx += x[j]
                dg += pd[j] * (g[j] + 1.0f64)
                j += 1usize
            }
            var going = true
            while going {
                var sumn = 0.0f64
                var minn = 0.0f64
                j = 0usize
                while j < m {
                    xnew[j] = step * y[j] + (1.0f64 - step) * x[j]
                    sumn += xnew[j]
                    if j == 0usize || xnew[j] < minn { minn = xnew[j] }
                    j += 1usize
                }
                let (fnew, efn) = sqp_obj(l, w, z, n, m, c.eps, xnew)
                if efn != ok { ret (res, efn) }
                nls_sum += 1i64
                if minn >= 0.0f64 && (fnew + sumn <= f + sumx + c.suffdecr * step * dg) {
                    going = false
                } else if step * c.stepreduce < c.minstep {
                    step = c.minstep
                    var minq = 0.0f64
                    j = 0usize
                    while j < m {
                        xnew[j] = step * y[j] + (1.0f64 - step) * x[j]
                        if j == 0usize || xnew[j] < minq { minq = xnew[j] }
                        j += 1usize
                    }
                    if minq < 0.0f64 {
                        step = 0.0f64
                        j = 0usize
                        while j < m {
                            xnew[j] = x[j]
                            j += 1usize
                        }
                    }
                    going = false
                } else {
                    step = step * c.stepreduce
                }
            }
        }
        j = 0usize
        while j < m {
            x[j] = xnew[j]
            j += 1usize
        }
    }
    res.iterations = rows + it
    res.nqp = nqp_sum
    res.nls = nls_sum
    var s = 0.0f64
    j = 0usize
    while j < m {
        s += x[j]
        j += 1usize
    }
    j = 0usize
    while j < m {
        x[j] = x[j] / s
        j += 1usize
    }
    let (v, ev) = sqp_obj(l, w, z, n, m, 0.0f64, x)
    if ev != ok { ret (res, ev) }
    res.value = v
    if gout.len >= m && hout.len >= m * m { sqp_grad(l, w, n, m, c.eps, x, gout, hout, zz) }
    ret (res, ok)
}

// The package's front end: `logl` reads l0 as log-likelihoods (row maximum subtracted, then exponentiated); columns that are all zero get a zero weight; one nonzero column is the trivial solution (status 2, nothing run). gout and hout (at least m and m by m long, or empty; filled over the nonzero columns, the Hessian with the stride of the nonzero count) receive the gradient and Hessian at the solution
fn mixsqp_run(a: *mem.Arena, l0: []const f64, w0: []const f64, n: usize, m: usize, x: []f64, c: SqpControl, logl: bool, gout: []f64, hout: []f64) -> (SqpResult, err) {
    var res: SqpResult = zero
    let (l, e0) = mem.alloc[f64](a, n * m)
    let (flag, e1) = mem.alloc[bool](a, m)
    if e0 != ok || e1 != ok { ret (res, mem.Full) }
    var i = 0usize
    while i < n * m {
        l[i] = l0[i]
        i += 1usize
    }
    if logl {
        i = 0usize
        while i < n {
            var mx = l0[i]
            var j = 1usize
            while j < m {
                if l0[j * n + i] > mx { mx = l0[j * n + i] }
                j += 1usize
            }
            j = 0usize
            while j < m {
                l[j * n + i] = math.exp[f64](l0[j * n + i] - mx)
                j += 1usize
            }
            i += 1usize
        }
    }
    var nz = 0usize
    var first = 0usize
    var j = 0usize
    while j < m {
        var mx = 0.0f64
        i = 0usize
        while i < n {
            if l[j * n + i] > mx { mx = l[j * n + i] }
            i += 1usize
        }
        flag[j] = mx > 0.0f64
        if flag[j] {
            if nz == 0usize { first = j }
            nz += 1usize
        }
        j += 1usize
    }
    if m == 1usize || nz == 1usize {
        j = 0usize
        while j < m {
            x[j] = 0.0f64
            j += 1usize
        }
        x[first] = 1.0f64
        var sw = 0.0f64
        var s = 0.0f64
        i = 0usize
        while i < n {
            sw += w0[i]
            s += w0[i] * math.log[f64](l[first * n + i])
            i += 1usize
        }
        res.status = 2i64
        res.value = 0.0f64 - s / sw
        ret (res, ok)
    }
    if nz == m {
        let (r1, e5) = mixsqp_sqp(a, l, w0, n, m, x, c, gout, hout)
        ret (r1, e5)
    }
    let (lc, e2) = mem.alloc[f64](a, n * nz)
    let (xc, e3) = mem.alloc[f64](a, nz)
    if e2 != ok || e3 != ok { ret (res, mem.Full) }
    var k = 0usize
    j = 0usize
    while j < m {
        if flag[j] {
            i = 0usize
            while i < n {
                lc[k * n + i] = l[j * n + i]
                i += 1usize
            }
            xc[k] = x[j]
            k += 1usize
        }
        j += 1usize
    }
    let (r2, e4) = mixsqp_sqp(a, lc, w0, n, nz, xc, c, gout, hout)
    if e4 != ok { ret (r2, e4) }
    k = 0usize
    j = 0usize
    while j < m {
        if flag[j] {
            x[j] = xc[k]
            k += 1usize
        } else {
            x[j] = 0.0f64
        }
        j += 1usize
    }
    ret (r2, ok)
}
