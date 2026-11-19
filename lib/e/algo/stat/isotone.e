// R isotone::gpava for a vector y: the generalised pool-adjacent-violators algorithm with the solvers weighted mean,
// weighted median and weighted fractile, and the three ties treatments ("primary": ties ordered by y, "secondary":
// ties averaged before and the group fit assigned to all, "tertiary": the group fit added to each deviation).
//
// Not here: matrix or list responses, user solvers, the Lp and quantile helpers beyond the fractile, activeSet and
// pava for general partial orders.

use e.algo.sort
use e.math
use e.mem

type Item = struct { x: f64, y: f64, w: f64, pos: usize }

fn cmp_item(ctx: *u8, a: Item, b: Item) -> i32 {
    if a.x < b.x { ret 0i32 - 1i32 }
    if a.x > b.x { ret 1i32 }
    if a.y < b.y { ret 0i32 - 1i32 }
    if a.y > b.y { ret 1i32 }
    ret 0i32
}

fn cmp_f(ctx: *u8, a: f64, b: f64) -> i32 {
    if a < b { ret 0i32 - 1i32 }
    if a > b { ret 1i32 }
    ret 0i32
}

// the solver on y with weights w: kind 0 weighted mean, 1 weighted median, 2 weighted fractile p
fn solve(a: *mem.Arena, y: []const f64, w: []const f64, kind: u8, p: f64) -> f64 {
    ret solve_ab(a, y, w, kind, p, 1.0f64, 1.0f64)
}

// kind 3 is the asymmetric weighted fractile with weights aw below and bw above (R weightedFractile)
fn solve_ab(a: *mem.Arena, y: []const f64, w: []const f64, kind: u8, p: f64, aw: f64, bw: f64) -> f64 {
    let n = y.len
    if kind == 0u8 {
        var sw = 0.0f64
        var swy = 0.0f64
        var i = 0usize
        while i < n {
            swy += y[i] * w[i]
            sw += w[i]
            i += 1usize
        }
        ret swy / sw
    }
    let (ys, e1) = mem.alloc[f64](a, n)
    let (ws, e2) = mem.alloc[f64](a, n)
    let (idx, e3) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = idx[i]
        var j = i
        while j > 0usize && y[idx[j - 1usize]] > y[v] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    i = 0usize
    while i < n {
        ys[i] = y[idx[i]]
        ws[i] = w[idx[i]]
        i += 1usize
    }
    var aa = 0.5f64
    var bb = 0.5f64
    if kind == 2u8 {
        aa = 1.0f64 - p
        bb = p
    }
    if kind == 3u8 {
        aa = aw
        bb = bw
    }
    // R sums in long double and rounds once; a compensated sum gives the same double
    var total = 0.0f64
    var comp = 0.0f64
    i = 0usize
    while i < n {
        let t = total + ws[i]
        if math.abs[f64](total) >= math.abs[f64](ws[i]) { comp += (total - t) + ws[i] } else { comp += (ws[i] - t) + total }
        total = t
        i += 1usize
    }
    total = total + comp
    var low = 0.0f64
    var lsum = 0.0f64
    var lcomp = 0.0f64
    var k = 1usize
    while true {
        let up = total - low
        let df = aa * low - bb * up
        if df < 0.0f64 {
            let lt = lsum + ws[k - 1usize]
            if math.abs[f64](lsum) >= math.abs[f64](ws[k - 1usize]) { lcomp += (lsum - lt) + ws[k - 1usize] } else { lcomp += (ws[k - 1usize] - lt) + lsum }
            lsum = lt
            low = lsum + lcomp
            k += 1usize
        } else if df == 0.0f64 {
            ret (ws[k - 1usize] * ys[k - 1usize] + ws[k - 2usize] * ys[k - 2usize]) / (ws[k - 1usize] + ws[k - 2usize])
        } else {
            ret ys[k - 2usize]
        }
    }
    ret 0.0f64
}

// the PAVA on already ordered y and w; fit receives the block value of every position
fn pava(a: *mem.Arena, y: []const f64, w: []const f64, kind: u8, p: f64, fit: []f64) -> err {
    let n = y.len
    let (lo, e1) = mem.alloc[usize](a, n)
    let (hi, e2) = mem.alloc[usize](a, n)
    let (vals, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var i = 0usize
    while i < n {
        lo[i] = i
        hi[i] = i + 1usize
        vals[i] = solve(a, y[i..i + 1usize], w[i..i + 1usize], kind, p)
        i += 1usize
    }
    var nb = n
    i = 0usize
    while i + 1usize < nb {
        if vals[i] > vals[i + 1usize] {
            var cur = i
            while true {
                hi[cur] = hi[cur + 1usize]
                vals[cur] = solve(a, y[lo[cur]..hi[cur]], w[lo[cur]..hi[cur]], kind, p)
                var j = cur + 1usize
                while j + 1usize < nb {
                    lo[j] = lo[j + 1usize]
                    hi[j] = hi[j + 1usize]
                    vals[j] = vals[j + 1usize]
                    j += 1usize
                }
                nb -= 1usize
                if cur > 0usize && vals[cur - 1usize] > vals[cur] {
                    cur -= 1usize
                } else {
                    i = cur
                    break
                }
            }
        } else {
            i += 1usize
        }
    }
    var b = 0usize
    while b < nb {
        var t = lo[b]
        while t < hi[b] {
            fit[t] = vals[b]
            t += 1usize
        }
        b += 1usize
    }
    ret ok
}

// gpava(z = x, y, weights, solver, ties): ties 0 primary, 1 secondary, 2 tertiary; out receives the fit in the input order
fn gpava(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, kind: u8, p: f64, ties: u8, out: []f64) -> err {
    let n = x.len
    if ties == 0u8 {
        let (items, e1) = mem.alloc[Item](a, n)
        let (ys, e2) = mem.alloc[f64](a, n)
        let (ws, e3) = mem.alloc[f64](a, n)
        let (fit, e4) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
        var i = 0usize
        while i < n {
            items[i] = Item { x: x[i], y: y[i], w: w[i], pos: i }
            i += 1usize
        }
        var ctx = 0u8
        sort.in_place_by[Item, u8](items, &ctx, cmp_item)
        i = 0usize
        while i < n {
            ys[i] = items[i].y
            ws[i] = items[i].w
            i += 1usize
        }
        let pe = pava(a, ys, ws, kind, p, fit)
        if pe != ok { ret pe }
        i = 0usize
        while i < n {
            out[items[i].pos] = fit[i]
            i += 1usize
        }
        ret ok
    }
    let (ux, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret e5 }
    var i = 0usize
    while i < n {
        ux[i] = x[i]
        i += 1usize
    }
    var ctx2 = 0u8
    sort.in_place_by[f64, u8](ux, &ctx2, cmp_f)
    var g = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || ux[i] != ux[i - 1usize] {
            ux[g] = ux[i]
            g += 1usize
        }
        i += 1usize
    }
    let (yag, e6) = mem.alloc[f64](a, g)
    let (wag, e7) = mem.alloc[f64](a, g)
    let (fit2, e8) = mem.alloc[f64](a, g)
    if e6 != ok || e7 != ok || e8 != ok { ret e6 }
    var gi = 0usize
    while gi < g {
        var sy = 0.0f64
        var sw = 0.0f64
        var c = 0.0f64
        i = 0usize
        while i < n {
            if x[i] == ux[gi] {
                sy += y[i]
                sw += w[i]
                c += 1.0f64
            }
            i += 1usize
        }
        yag[gi] = sy / c
        wag[gi] = sw
        gi += 1usize
    }
    let pe2 = pava(a, yag, wag, kind, p, fit2)
    if pe2 != ok { ret pe2 }
    i = 0usize
    while i < n {
        var gk = 0usize
        while ux[gk] != x[i] { gk += 1usize }
        if ties == 1u8 { out[i] = fit2[gk] } else { out[i] = y[i] + (fit2[gk] - yag[gk]) }
        i += 1usize
    }
    ret ok
}

// the LS solver of activeSet for the active rows ia (indices into the m constraints, each constraint a1 >= a2 in 0-based positions p1, p2): fills y, the multipliers lbd (one per active row) and returns f
fn ls_solve(a: *mem.Arena, z: []const f64, w: []const f64, xo: []const f64, p1: []const usize, p2: []const usize, ia: []const usize, y: []f64, lbd: []f64, gy: []f64, kind: u8, aw: f64, bw: f64) -> f64 {
    let n = z.len
    let na = ia.len
    var i = 0usize
    if na == 0usize && (kind < 3u8 || kind == 9u8) {
        while i < n {
            y[i] = z[i]
            gy[i] = 0.0f64
            i += 1usize
        }
        ret 0.0f64
    }
    let (lab, e0) = mem.alloc[usize](a, n)
    if e0 != ok { ret 0.0f64 / 0.0f64 }
    while i < n {
        lab[i] = i
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        var r = 0usize
        while r < na {
            let u = lab[p1[ia[r]]]
            let v = lab[p2[ia[r]]]
            if u < v {
                lab[p2[ia[r]]] = u
                changed = true
            } else if v < u {
                lab[p1[ia[r]]] = v
                changed = true
            }
            r += 1usize
        }
        // propagate to every member of the relabelled blocks
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if lab[i] == j && lab[j] < lab[i] {
                    lab[i] = lab[j]
                    changed = true
                }
                j += 1usize
            }
            i += 1usize
        }
    }
    let (sw, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (swz, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < n {
        sw[i] = 0.0f64
        swz[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        sw[lab[i]] += w[i]
        swz[lab[i]] += w[i] * z[i]
        i += 1usize
    }
    var f = 0.0f64
    i = 0usize
    while i < n {
        y[i] = swz[lab[i]] / sw[lab[i]]
        i += 1usize
    }
    if kind >= 1u8 && kind < 3u8 {
        let (ty, e7) = mem.alloc[f64](a, n)
        if e7 != ok { ret 0.0f64 / 0.0f64 }
        let (tw, e8) = mem.alloc[f64](a, n)
        if e8 != ok { ret 0.0f64 / 0.0f64 }
        var root = 0usize
        while root < n {
            var cnt = 0usize
            i = 0usize
            while i < n {
                if lab[i] == root {
                    ty[cnt] = z[i]
                    tw[cnt] = w[i]
                    cnt += 1usize
                }
                i += 1usize
            }
            if cnt > 0usize {
                let med = solve_ab(a, ty[0usize..cnt], tw[0usize..cnt], 1u8 + kind / 2u8 * 2u8, 0.0f64, aw, bw)
                i = 0usize
                while i < n {
                    if lab[i] == root { y[i] = med }
                    i += 1usize
                }
            }
            root += 1usize
        }
    }
    if kind >= 3u8 && kind < 9u8 { f = fsolve(a, z, w, xo, lab, kind, aw, bw, y, gy) }
    if kind == 9u8 {
        // the Chebyshev solver (isotone mSolver): each block takes the weighted mid-range of its values, the objective is the largest weighted deviation, and the gradient puts its weight on the largest and smallest
        var root = 0usize
        while root < n {
            var s = 0.0f64
            var i0 = root
            var j0 = root
            var cnt = 0usize
            i = 0usize
            while i < n {
                if lab[i] == root {
                    cnt += 1usize
                    var j = i + 1usize
                    while j < n {
                        if lab[j] == root {
                            let t = w[i] * w[j] * math.abs[f64](z[i] - z[j]) / (w[i] + w[j])
                            if t > s {
                                s = t
                                i0 = i
                                j0 = j
                            }
                        }
                        j += 1usize
                    }
                }
                i += 1usize
            }
            if cnt > 0usize {
                var mid = z[i0]
                if cnt > 1usize { mid = (w[i0] * z[i0] + w[j0] * z[j0]) / (w[i0] + w[j0]) }
                i = 0usize
                while i < n {
                    if lab[i] == root { y[i] = mid }
                    i += 1usize
                }
            }
            root += 1usize
        }
        var i1 = 0usize
        var i2 = 0usize
        i = 0usize
        while i < n {
            let dv = w[i] * (y[i] - z[i])
            if dv > w[i1] * (y[i1] - z[i1]) { i1 = i }
            if dv < w[i2] * (y[i2] - z[i2]) { i2 = i }
            i += 1usize
        }
        f = math.abs[f64](w[i1] * (y[i1] - z[i1]))
        if math.abs[f64](w[i2] * (y[i2] - z[i2])) > f { f = math.abs[f64](w[i2] * (y[i2] - z[i2])) }
        i = 0usize
        while i < n {
            gy[i] = 0.0f64
            i += 1usize
        }
        gy[i1] = w[i2] * w[i1] / (w[i1] + w[i2])
        gy[i2] = gy[i2] - w[i1] * w[i2] / (w[i1] + w[i2])
    }
    i = 0usize
    while i < n && kind < 3u8 {
        if kind == 1u8 {
            var sg = 0.0f64
            if y[i] > z[i] { sg = 1.0f64 } else if y[i] < z[i] { sg = 0.0f64 - 1.0f64 }
            gy[i] = w[i] * sg
            f += w[i] * math.abs[f64](z[i] - y[i])
        } else if kind == 2u8 {
            if y[i] <= z[i] {
                gy[i] = 0.0f64 - w[i] * aw
                f += w[i] * aw * (z[i] - y[i])
            } else {
                gy[i] = w[i] * bw
                f += w[i] * bw * (y[i] - z[i])
            }
        } else {
            gy[i] = 2.0f64 * w[i] * (y[i] - z[i])
            f += w[i] * (y[i] - z[i]) * (y[i] - z[i])
        }
        i += 1usize
    }
    // t(A) lbd = gy by R's qr.coef (LINPACK dqrdc2, tolerance 1e-7): a column that is dependent on the earlier ones is aliased and its coefficient NA; the others solve the normal equations
    let (sel, e3) = mem.alloc[usize](a, na)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    let (qv, e4) = mem.alloc[f64](a, na * n)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    var ns = 0usize
    var r = 0usize
    while r < na {
        let v = qv[ns * n..ns * n + n]
        i = 0usize
        while i < n {
            v[i] = 0.0f64
            i += 1usize
        }
        v[p1[ia[r]]] += 1.0f64
        v[p2[ia[r]]] -= 1.0f64
        let orig = math.sqrt[f64](2.0f64)
        var k = 0usize
        while k < ns {
            var d = 0.0f64
            i = 0usize
            while i < n {
                d += v[i] * qv[k * n + i]
                i += 1usize
            }
            i = 0usize
            while i < n {
                v[i] -= d * qv[k * n + i]
                i += 1usize
            }
            k += 1usize
        }
        var nrm = 0.0f64
        i = 0usize
        while i < n {
            nrm += v[i] * v[i]
            i += 1usize
        }
        nrm = math.sqrt[f64](nrm)
        lbd[r] = 0.0f64 / 0.0f64
        if nrm > 1.0e-7f64 * orig {
            i = 0usize
            while i < n {
                v[i] = v[i] / nrm
                i += 1usize
            }
            sel[ns] = r
            ns += 1usize
        }
        r += 1usize
    }
    if ns == 0usize { ret f }
    let wd = ns + 1usize
    let (mat, e5) = mem.alloc[f64](a, ns * wd)
    if e5 != ok { ret 0.0f64 / 0.0f64 }
    r = 0usize
    while r < ns {
        var c = 0usize
        while c < ns {
            var s = 0.0f64
            let r1 = p1[ia[sel[r]]]
            let r2 = p2[ia[sel[r]]]
            let c1 = p1[ia[sel[c]]]
            let c2 = p2[ia[sel[c]]]
            if r1 == c1 { s += 1.0f64 }
            if r1 == c2 { s -= 1.0f64 }
            if r2 == c1 { s -= 1.0f64 }
            if r2 == c2 { s += 1.0f64 }
            mat[r * wd + c] = s
            c += 1usize
        }
        mat[r * wd + ns] = gy[p1[ia[sel[r]]]] - gy[p2[ia[sel[r]]]]
        r += 1usize
    }
    var col = 0usize
    while col < ns {
        var piv = col
        var rr = col + 1usize
        while rr < ns {
            if math.abs[f64](mat[rr * wd + col]) > math.abs[f64](mat[piv * wd + col]) { piv = rr }
            rr += 1usize
        }
        var cc = 0usize
        while cc < wd {
            let t = mat[col * wd + cc]
            mat[col * wd + cc] = mat[piv * wd + cc]
            mat[piv * wd + cc] = t
            cc += 1usize
        }
        rr = 0usize
        while rr < ns {
            if rr != col {
                let fct = mat[rr * wd + col] / mat[col * wd + col]
                cc = col
                while cc < wd {
                    mat[rr * wd + cc] -= fct * mat[col * wd + cc]
                    cc += 1usize
                }
            }
            rr += 1usize
        }
        col += 1usize
    }
    r = 0usize
    while r < ns {
        lbd[sel[r]] = mat[r * wd + ns] / mat[r * wd + r]
        r += 1usize
    }
    ret f
}

// activeSet(isomat, "LS", y, weights) from the zero start: out receives x (n), the multipliers per constraint (m, zero for inactive), then fval and niter;
// the constraints are the 0-based pairs (p1[i] >= p2[i]) of R's isomat[i, 2] >= isomat[i, 1]
fn active_set(a: *mem.Arena, y0: []const f64, w: []const f64, p1: []const usize, p2: []const usize, kind: u8, aw: f64, bw: f64, out: []f64) -> err {
    let n = y0.len
    let m = p1.len
    let ups = 1.0e-12f64
    let big = 1.0e300f64
    let (xold, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret e0 }
    let (y, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    let (gy, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret e2 }
    let (ax, e3) = mem.alloc[f64](a, m)
    if e3 != ok { ret e3 }
    let (ay, e4) = mem.alloc[f64](a, m)
    if e4 != ok { ret e4 }
    let (iab, e5) = mem.alloc[usize](a, m + 1usize)
    if e5 != ok { ret e5 }
    let (lb, e6) = mem.alloc[f64](a, m + 1usize)
    if e6 != ok { ret e6 }
    var i = 0usize
    while i < n {
        xold[i] = 0.0f64
        i += 1usize
    }
    var nia = 0usize
    i = 0usize
    while i < m {
        ax[i] = 0.0f64
        iab[nia] = i
        nia += 1usize
        i += 1usize
    }
    var iter = 0usize
    var f = 0.0f64
    while true {
        iter += 1usize
        f = ls_solve(a, y0, w, xold, p1, p2, iab[0usize..nia], y, lb, gy, kind, aw, bw)
        i = 0usize
        var my = big
        while i < m {
            ay[i] = y[p1[i]] - y[p2[i]]
            if ay[i] < my { my = ay[i] }
            i += 1usize
        }
        var ml = big
        var il = 0usize
        i = 0usize
        while i < nia {
            if lb[i] < ml {
                ml = lb[i]
                il = i
            }
            i += 1usize
        }
        var done = false
        if my > 0.0f64 - ups {
            if ml > 0.0f64 - ups {
                done = true
            } else {
                i = 0usize
                while i < n {
                    xold[i] = y[i]
                    i += 1usize
                }
                i = 0usize
                while i < m {
                    ax[i] = ay[i]
                    i += 1usize
                }
                i = il
                while i + 1usize < nia {
                    iab[i] = iab[i + 1usize]
                    i += 1usize
                }
                nia -= 1usize
            }
        } else {
            var best = 0.0f64 - big
            var bk = m
            i = 0usize
            while i < m {
                if ax[i] > 0.0f64 - ups && ay[i] < ups {
                    let rat = 0.0f64 - ay[i] / (ax[i] - ay[i])
                    if rat == rat && rat > best {
                        best = rat
                        bk = i
                    }
                }
                i += 1usize
            }
            i = 0usize
            while i < n {
                xold[i] = y[i] + best * (xold[i] - y[i])
                i += 1usize
            }
            i = 0usize
            while i < m {
                ax[i] = xold[p1[i]] - xold[p2[i]]
                i += 1usize
            }
            if bk < m {
                var at = nia
                while at > 0usize && iab[at - 1usize] > bk {
                    iab[at] = iab[at - 1usize]
                    at -= 1usize
                }
                iab[at] = bk
                nia += 1usize
            }
        }
        if done { break }
        if iter == 100usize { break }
    }
    i = 0usize
    while i < n {
        out[i] = y[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        out[n + i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nia {
        out[n + iab[i]] = lb[i]
        i += 1usize
    }
    out[n + m] = f
    out[n + m + 1usize] = f64(iter)
    ret ok
}

// the pooled-adjacent-violators pass over rows of k replicates each (a gpava matrix or list response): fit[i] is the block value of row i; rows are already in their order, yv and wv hold the rows contiguously
fn pava_rows(a: *mem.Arena, yv: []const f64, wv: []const f64, n: usize, k: usize, kind: u8, p: f64, fit: []f64) -> err {
    let (st, e1) = mem.alloc[usize](a, n)
    let (en, e2) = mem.alloc[usize](a, n)
    let (vals, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        st[i] = i
        en[i] = i + 1usize
        vals[i] = solve(a, yv[i * k..(i + 1usize) * k], wv[i * k..(i + 1usize) * k], kind, p)
        i += 1usize
    }
    var nb = n
    i = 0usize
    while i + 1usize < nb {
        if vals[i] > vals[i + 1usize] {
            // merge block i with i + 1
            en[i] = en[i + 1usize]
            vals[i] = solve(a, yv[st[i] * k..en[i] * k], wv[st[i] * k..en[i] * k], kind, p)
            var j = i + 1usize
            while j + 1usize < nb {
                st[j] = st[j + 1usize]
                en[j] = en[j + 1usize]
                vals[j] = vals[j + 1usize]
                j += 1usize
            }
            nb -= 1usize
            while i > 0usize && vals[i - 1usize] > vals[i] {
                en[i - 1usize] = en[i]
                vals[i - 1usize] = solve(a, yv[st[i - 1usize] * k..en[i - 1usize] * k], wv[st[i - 1usize] * k..en[i - 1usize] * k], kind, p)
                var q = i
                while q + 1usize < nb {
                    st[q] = st[q + 1usize]
                    en[q] = en[q + 1usize]
                    vals[q] = vals[q + 1usize]
                    q += 1usize
                }
                nb -= 1usize
                i -= 1usize
            }
        } else {
            i += 1usize
        }
    }
    var b = 0usize
    while b < nb {
        var r = st[b]
        while r < en[b] {
            fit[r] = vals[b]
            r += 1usize
        }
        b += 1usize
    }
    ret ok
}

// gpava(z = x, y = matrix, weights = matrix) with the weighted mean, median or fractile solver: rows are the repeated measurements at x; ties 0 primary, 1 secondary, 2 tertiary; out receives the fit in the input order
fn gpava_rows(a: *mem.Arena, x: []const f64, y: []const f64, w: []const f64, n: usize, k: usize, kind: u8, p: f64, ties: u8, out: []f64) -> err {
    let (ord, e1) = mem.alloc[usize](a, n)
    let (key, e2) = mem.alloc[f64](a, n)
    let (ys, e3) = mem.alloc[f64](a, n * k)
    let (ws, e4) = mem.alloc[f64](a, n * k)
    let (fit, e5) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    var i = 0usize
    if ties == 0u8 {
        i = 0usize
        while i < n {
            ord[i] = i
            key[i] = solve(a, y[i * k..(i + 1usize) * k], w[i * k..(i + 1usize) * k], kind, p)
            i += 1usize
        }
        // order(x, key): stable insertion sort
        i = 1usize
        while i < n {
            let v = ord[i]
            var j = i
            while j > 0usize && (x[ord[j - 1usize]] > x[v] || (x[ord[j - 1usize]] == x[v] && key[ord[j - 1usize]] > key[v])) {
                ord[j] = ord[j - 1usize]
                j -= 1usize
            }
            ord[j] = v
            i += 1usize
        }
        i = 0usize
        while i < n {
            var c = 0usize
            while c < k {
                ys[i * k + c] = y[ord[i] * k + c]
                ws[i * k + c] = w[ord[i] * k + c]
                c += 1usize
            }
            i += 1usize
        }
        let pe = pava_rows(a, ys, ws, n, k, kind, p, fit)
        if pe != ok { ret pe }
        i = 0usize
        while i < n {
            out[ord[i]] = fit[i]
            i += 1usize
        }
        ret ok
    }
    // secondary and tertiary: aggregate the rows with equal x (means of the values, sums of the weights), order by x
    let (ux, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret e6 }
    var ng = 0usize
    i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < ng {
            if ux[j] == x[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ux[ng] = x[i]
            ng += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < ng {
        let v = ux[i]
        var j = i
        while j > 0usize && ux[j - 1usize] > v {
            ux[j] = ux[j - 1usize]
            j -= 1usize
        }
        ux[j] = v
        i += 1usize
    }
    let (ya, e7) = mem.alloc[f64](a, ng * k)
    let (wa, e8) = mem.alloc[f64](a, ng * k)
    let (fa, e9) = mem.alloc[f64](a, ng)
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    var g = 0usize
    while g < ng {
        var cnt = 0.0f64
        var c = 0usize
        while c < k {
            ya[g * k + c] = 0.0f64
            wa[g * k + c] = 0.0f64
            c += 1usize
        }
        i = 0usize
        while i < n {
            if x[i] == ux[g] {
                cnt += 1.0f64
                c = 0usize
                while c < k {
                    ya[g * k + c] += y[i * k + c]
                    wa[g * k + c] += w[i * k + c]
                    c += 1usize
                }
            }
            i += 1usize
        }
        c = 0usize
        while c < k {
            ya[g * k + c] = ya[g * k + c] / cnt
            c += 1usize
        }
        g += 1usize
    }
    let pe2 = pava_rows(a, ya, wa, ng, k, kind, p, fa)
    if pe2 != ok { ret pe2 }
    i = 0usize
    while i < n {
        g = 0usize
        while ux[g] != x[i] { g += 1usize }
        if ties == 1u8 {
            out[i] = fa[g]
        } else {
            out[i] = solve(a, y[i * k..(i + 1usize) * k], w[i * k..(i + 1usize) * k], kind, p) + (fa[g] - solve(a, ya[g * k..(g + 1usize) * k], wa[g * k..(g + 1usize) * k], kind, p))
        }
        i += 1usize
    }
    ret ok
}

// ---- activeSet solvers that run optim(method = "BFGS") on the block values (isotone fSolver): asymmetric LS (kind 3, aw bw), L1 with eps (4, eps = aw), Huber (5, eps = aw), SILF (6, eps = aw, beta = bw), Lp (7, p = aw) ----

type IsoCtx = struct { kind: u8, z: []const f64, w: []const f64, blk: []const usize, aw: f64, bw: f64 }

fn rpow(x: f64, y: f64) -> f64 {
    if y == 2.0f64 { ret x * x }
    if x == 1.0f64 || y == 0.0f64 { ret 1.0f64 }
    ret math.pow[f64](x, y)
}

fn sgn(v: f64) -> f64 {
    if v > 0.0f64 { ret 1.0f64 }
    if v < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// the objective term of one observation at the fitted value x
fn iso_term(c: *const IsoCtx, i: usize, x: f64) -> f64 {
    let d = x - c.z[i]
    let w = c.w[i]
    if c.kind == 3u8 {
        var s = c.bw
        if x < c.z[i] { s = c.aw }
        ret w * (d * d) * s
    }
    if c.kind == 4u8 { ret w * math.sqrt[f64](d * d + c.aw) }
    if c.kind == 5u8 {
        if math.abs[f64](d) < 2.0f64 * c.aw { ret w * (d * d / (4.0f64 * c.aw)) }
        ret w * (math.abs[f64](d) - c.aw)
    }
    if c.kind == 6u8 {
        let delta = math.abs[f64](d)
        let lo = (1.0f64 - c.bw) * c.aw
        var g = (delta - lo) * (delta - lo) / (4.0f64 * c.bw * c.aw)
        if delta < lo { g = 0.0f64 }
        if delta > (1.0f64 + c.bw) * c.aw { g = delta - c.aw }
        ret w * g
    }
    if c.kind == 8u8 { ret x - c.z[i] * math.log[f64](x) }
    ret w * rpow(math.abs[f64](d), c.aw)
}

fn iso_grad(c: *const IsoCtx, i: usize, x: f64) -> f64 {
    let d = x - c.z[i]
    let w = c.w[i]
    if c.kind == 3u8 {
        var s = c.bw
        if x < c.z[i] { s = c.aw }
        ret 2.0f64 * w * d * s
    }
    if c.kind == 4u8 { ret w * d / math.sqrt[f64](d * d + c.aw) }
    if c.kind == 5u8 {
        if math.abs[f64](d) < 2.0f64 * c.aw { ret w * (d / (2.0f64 * c.aw)) }
        ret w * sgn(d)
    }
    if c.kind == 6u8 {
        let hi = (1.0f64 + c.bw) * c.aw
        let lo = (1.0f64 - c.bw) * c.aw
        var g = 0.0f64
        if d < 0.0f64 - hi {
            g = 0.0f64 - 1.0f64
        } else if d > 0.0f64 - hi && d < 0.0f64 - lo {
            g = (d + lo) / (2.0f64 * c.bw * c.aw)
        } else if d > lo && d < hi {
            g = (d - lo) / (2.0f64 * c.bw * c.aw)
        } else if d > hi {
            g = 1.0f64
        }
        ret w * g
    }
    if c.kind == 8u8 { ret 1.0f64 - c.z[i] / x }
    ret c.aw * w * sgn(d) * rpow(math.abs[f64](d), c.aw - 1.0f64)
}

// sum to double the way R's long-double accumulation rounds it
fn ksum(v: []const f64) -> f64 {
    var total = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let t = total + v[i]
        if math.abs[f64](total) >= math.abs[f64](v[i]) { comp += (total - t) + v[i] } else { comp += (v[i] - t) + total }
        total = t
        i += 1usize
    }
    ret total + comp
}

fn iso_f(c: *const IsoCtx, u: []const f64, tmp: []f64) -> f64 {
    var i = 0usize
    while i < c.z.len {
        tmp[i] = iso_term(c, i, u[c.blk[i]])
        i += 1usize
    }
    ret ksum(tmp[0usize..c.z.len])
}

fn iso_g(c: *const IsoCtx, u: []const f64, g: []f64) {
    var j = 0usize
    while j < u.len {
        g[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < c.z.len {
        g[c.blk[i]] += iso_grad(c, i, u[c.blk[i]])
        i += 1usize
    }
}

// R's vmmin (optim BFGS: maxit 100, abstol -Inf, reltol sqrt(eps)); b is the start and the answer, returns the minimum
fn vmmin(a: *mem.Arena, c: *const IsoCtx, b: []f64, tmp: []f64) -> f64 {
    let n = b.len
    let (g, e1) = mem.alloc[f64](a, n)
    let (t, e2) = mem.alloc[f64](a, n)
    let (xv, e3) = mem.alloc[f64](a, n)
    let (cv, e4) = mem.alloc[f64](a, n)
    let (bm, e5) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    let reltol = 1.490116119384766e-8f64
    var f = iso_f(c, b, tmp)
    var fmin = f
    iso_g(c, b, g)
    var gradcount = 1usize
    var iter = 1usize
    var ilast = gradcount
    var count = 0usize
    var go = true
    while go {
        var i = 0usize
        if ilast == gradcount {
            i = 0usize
            while i < n {
                var j = 0usize
                while j < i {
                    bm[i * n + j] = 0.0f64
                    j += 1usize
                }
                bm[i * n + i] = 1.0f64
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            xv[i] = b[i]
            cv[i] = g[i]
            i += 1usize
        }
        var gradproj = 0.0f64
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j <= i {
                s -= bm[i * n + j] * g[j]
                j += 1usize
            }
            j = i + 1usize
            while j < n {
                s -= bm[j * n + i] * g[j]
                j += 1usize
            }
            t[i] = s
            gradproj += s * g[i]
            i += 1usize
        }
        if gradproj < 0.0f64 {
            var steplength = 1.0f64
            var accpoint = false
            var again = true
            while again {
                count = 0usize
                i = 0usize
                while i < n {
                    b[i] = xv[i] + steplength * t[i]
                    if 10.0f64 + xv[i] == 10.0f64 + b[i] { count += 1usize }
                    i += 1usize
                }
                if count < n {
                    f = iso_f(c, b, tmp)
                    accpoint = f - f == 0.0f64 && f <= fmin + gradproj * steplength * 0.0001f64
                    if !accpoint { steplength *= 0.2f64 }
                }
                again = !(count == n || accpoint)
            }
            let enough = math.abs[f64](f - fmin) > reltol * (math.abs[f64](fmin) + reltol)
            if !enough {
                count = n
                fmin = f
            }
            if count < n {
                fmin = f
                iso_g(c, b, g)
                gradcount += 1usize
                iter += 1usize
                var d1 = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = steplength * t[i]
                    cv[i] = g[i] - cv[i]
                    d1 += t[i] * cv[i]
                    i += 1usize
                }
                if d1 > 0.0f64 {
                    var d2 = 0.0f64
                    i = 0usize
                    while i < n {
                        var s = 0.0f64
                        var j = 0usize
                        while j <= i {
                            s += bm[i * n + j] * cv[j]
                            j += 1usize
                        }
                        j = i + 1usize
                        while j < n {
                            s += bm[j * n + i] * cv[j]
                            j += 1usize
                        }
                        xv[i] = s
                        d2 += s * cv[i]
                        i += 1usize
                    }
                    d2 = 1.0f64 + d2 / d1
                    i = 0usize
                    while i < n {
                        var j = 0usize
                        while j <= i {
                            bm[i * n + j] += (d2 * t[i] * t[j] - xv[i] * t[j] - t[i] * xv[j]) / d1
                            j += 1usize
                        }
                        i += 1usize
                    }
                } else {
                    ilast = gradcount
                }
            } else if ilast < gradcount {
                count = 0usize
                ilast = gradcount
            }
        } else {
            count = 0usize
            if ilast == gradcount { count = n } else { ilast = gradcount }
        }
        if iter >= 100usize { go = false }
        if go {
            if gradcount - ilast > 2usize * n { ilast = gradcount }
            go = count != n || ilast != gradcount
        }
    }
    ret fmin
}

// fSolver on the blocks lab (block root per observation): the start is the sum of the current point xo over each block, the answer expanded to every observation; fills y and gy, returns f
fn fsolve(a: *mem.Arena, z: []const f64, w: []const f64, xo: []const f64, lab: []const usize, kind: u8, aw: f64, bw: f64, y: []f64, gy: []f64) -> f64 {
    let n = z.len
    let (blk, e1) = mem.alloc[usize](a, n)
    let (ord, e2) = mem.alloc[usize](a, n)
    let (tmp, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var nb = 0usize
    var i = 0usize
    while i < n {
        if lab[i] == i {
            ord[i] = nb
            nb += 1usize
        }
        i += 1usize
    }
    let (u, e4) = mem.alloc[f64](a, nb)
    if e4 != ok { ret 0.0f64 / 0.0f64 }
    i = 0usize
    while i < nb {
        u[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        blk[i] = ord[lab[i]]
        u[blk[i]] += xo[i]
        i += 1usize
    }
    let c = IsoCtx{ kind: kind, z: z, w: w, blk: blk, aw: aw, bw: bw }
    let fmin = vmmin(a, &c, u, tmp)
    i = 0usize
    while i < n {
        y[i] = u[blk[i]]
        gy[i] = iso_grad(&c, i, y[i])
        i += 1usize
    }
    ret fmin
}

// gpava with a list response and ties = "primary": row i holds len[i] replicates (flattened in yv / wv, rows in the input order); out receives the block value of each row in the input order
fn gpava_list(a: *mem.Arena, x: []const f64, yv: []const f64, wv: []const f64, len: []const usize, kind: u8, p: f64, out: []f64) -> err {
    let n = len.len
    let (off, e0) = mem.alloc[usize](a, n + 1usize)
    let (ord, e1) = mem.alloc[usize](a, n)
    let (key, e2) = mem.alloc[f64](a, n)
    let (ys, e3) = mem.alloc[f64](a, yv.len)
    let (ws, e4) = mem.alloc[f64](a, yv.len)
    let (os, e5) = mem.alloc[usize](a, n + 1usize)
    let (st, e6) = mem.alloc[usize](a, n)
    let (en, e7) = mem.alloc[usize](a, n)
    let (vals, e8) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    off[0usize] = 0usize
    var i = 0usize
    while i < n {
        off[i + 1usize] = off[i] + len[i]
        ord[i] = i
        key[i] = solve(a, yv[off[i]..off[i + 1usize]], wv[off[i]..off[i + 1usize]], kind, p)
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && (x[ord[j - 1usize]] > x[v] || (x[ord[j - 1usize]] == x[v] && key[ord[j - 1usize]] > key[v])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    os[0usize] = 0usize
    i = 0usize
    while i < n {
        let r = ord[i]
        var c = 0usize
        while c < len[r] {
            ys[os[i] + c] = yv[off[r] + c]
            ws[os[i] + c] = wv[off[r] + c]
            c += 1usize
        }
        os[i + 1usize] = os[i] + len[r]
        st[i] = i
        en[i] = i + 1usize
        vals[i] = key[r]
        i += 1usize
    }
    var nb = n
    i = 0usize
    while i + 1usize < nb {
        if vals[i] > vals[i + 1usize] {
            en[i] = en[i + 1usize]
            vals[i] = solve(a, ys[os[st[i]]..os[en[i]]], ws[os[st[i]]..os[en[i]]], kind, p)
            var j = i + 1usize
            while j + 1usize < nb {
                st[j] = st[j + 1usize]
                en[j] = en[j + 1usize]
                vals[j] = vals[j + 1usize]
                j += 1usize
            }
            nb -= 1usize
            while i > 0usize && vals[i - 1usize] > vals[i] {
                en[i - 1usize] = en[i]
                vals[i - 1usize] = solve(a, ys[os[st[i - 1usize]]..os[en[i - 1usize]]], ws[os[st[i - 1usize]]..os[en[i - 1usize]]], kind, p)
                var q = i
                while q + 1usize < nb {
                    st[q] = st[q + 1usize]
                    en[q] = en[q + 1usize]
                    vals[q] = vals[q + 1usize]
                    q += 1usize
                }
                nb -= 1usize
                i -= 1usize
            }
        } else {
            i += 1usize
        }
    }
    var b = 0usize
    while b < nb {
        var r = st[b]
        while r < en[b] {
            out[ord[r]] = vals[b]
            r += 1usize
        }
        b += 1usize
    }
    ret ok
}
