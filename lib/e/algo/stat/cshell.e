// R e1071::cshell, fuzzy c-shell clustering with the centres given: the package's C routine (`cshell`,
// `subcshell`) line for line, R's driver loop that polishes each centre and radius with `optim(method = "CG")`
// on a numerical gradient (`cgmin` of R's optim.c, step 1e-3), and the random row permutation that reorders the
// data first, so every sum is added in the order R adds it. R's `sum` is a long-double sum; `lsum` rounds a
// compensated sum once, which is what a 64-bit mantissa gives to the last place nearly always.
//
// Not here: random starting centres (`runif` ranks), the Manhattan distance inside the optimiser (the package uses the
// Euclidean one there too), predict.

use e.algo.rand.r as rng
use e.math
use e.mem

type State = struct {
    n: usize, d: usize, nc: usize, x: []const f64, centers: []f64, u: []f64, uant: []f64, radius: []f64,
    m: f64, dist: i64, ermin: f64, itermax: i64, iter: i64, flag: i64
}

fn xd(s: *const State, k: usize, col: usize) -> f64 { ret s.x[k + s.n * col] }

// the membership update both the start and each pass share: out receives 1 / sum_j (|dist_i - r_i| / |dist_j - r_j|)^e
fn memberships(s: *State, out: []f64) {
    let e = 2.0f64 / (s.m - 1.0f64)
    var i = 0usize
    while i < s.nc {
        var k = 0usize
        while k < s.n {
            var suma = 0.0f64
            var j = 0usize
            while j < s.nc {
                var t1 = 0.0f64
                var t2 = 0.0f64
                var col = 0usize
                while col < s.d {
                    let a = xd(s, k, col) - s.centers[i + s.nc * col]
                    let b = xd(s, k, col) - s.centers[j + s.nc * col]
                    if s.dist == 0i64 {
                        t1 += a * a
                        t2 += b * b
                    } else {
                        t1 += math.abs[f64](a)
                        t2 += math.abs[f64](b)
                    }
                    col += 1usize
                }
                var tu = 0.0f64
                if s.dist == 0i64 { tu = math.abs[f64](math.sqrt[f64](t1) - s.radius[i]) / math.abs[f64](math.sqrt[f64](t2) - s.radius[j]) } else { tu = math.abs[f64]((t1 - s.radius[i]) / (t2 - s.radius[j])) }
                suma += math.pow[f64](tu, e)
                j += 1usize
            }
            out[k + s.n * i] = 1.0f64 / suma
            k += 1usize
        }
        i += 1usize
    }
}

fn subcshell(s: *State) {
    let n = s.n
    let nc = s.nc
    let d = s.d
    if s.flag == 0i64 || s.flag == 5i64 {
        var i = 0usize
        while i < nc {
            var sum2 = 0.0f64
            var col = 0usize
            while col < d { s.centers[i + nc * col] = 0.0f64
                col += 1usize }
            var k = 0usize
            while k < n {
                let temp = math.pow[f64](s.u[k + n * i], s.m)
                sum2 += temp
                col = 0usize
                while col < d {
                    s.centers[i + nc * col] += temp * xd(s, k, col)
                    col += 1usize
                }
                k += 1usize
            }
            col = 0usize
            while col < d { s.centers[i + nc * col] /= sum2
                col += 1usize }
            i += 1usize
        }
        i = 0usize
        while i < nc {
            var sum2 = 0.0f64
            s.radius[i] = 0.0f64
            var k = 0usize
            while k < n {
                var distance = 0.0f64
                let temp = math.pow[f64](s.u[k + n * i], s.m)
                sum2 += temp
                var col = 0usize
                while col < d {
                    let dv = xd(s, k, col) - s.centers[i + nc * col]
                    if s.dist == 0i64 { distance += dv * dv } else { distance += math.abs[f64](dv) }
                    col += 1usize
                }
                if s.dist == 0i64 { s.radius[i] += temp * math.sqrt[f64](distance) } else { s.radius[i] += temp * distance }
                k += 1usize
            }
            s.radius[i] /= sum2
            i += 1usize
        }
    }
    var q = 0usize
    while q < nc * n { s.uant[q] = s.u[q]
        q += 1usize }
    memberships(s, s.u)
    let epsi1 = 0.002f64
    let epsi2 = 0.2f64
    var conv = 0.0f64
    var m = 0usize
    while m < nc {
        var k = 0usize
        while k < n {
            var serror = 0.0f64
            var nn = 0usize
            while nn < d {
                let dv = xd(s, k, nn) - s.centers[m + nc * nn]
                if s.dist == 0i64 { serror += dv * dv } else { serror += math.abs[f64](dv) }
                nn += 1usize
            }
            if s.dist == 0i64 { serror = math.abs[f64](math.sqrt[f64](serror) - s.radius[m]) } else { serror = math.abs[f64](serror - s.radius[m]) }
            s.ermin += math.pow[f64](s.u[k + n * m], s.m) * math.pow[f64](serror, 2.0f64)
            conv += math.abs[f64](s.u[k + n * m] - s.uant[k + n * m])
            k += 1usize
        }
        m += 1usize
    }
    let scale = f64(n) * f64(d)
    if conv <= scale * epsi1 {
        s.flag = 2i64
    } else if conv <= scale * epsi2 {
        if s.flag == 3i64 { s.flag = 4i64 } else { s.flag = 1i64 }
    } else if s.flag == 3i64 {
        s.flag = 5i64
    }
}

fn cshell_c(s: *State) {
    if s.flag == 0i64 {
        s.iter = 0i64
        memberships(s, s.uant)
        var q = 0usize
        while q < s.nc * s.n { s.u[q] = s.uant[q]
            q += 1usize }
    }
    while true {
        let go = s.iter < s.itermax
        s.iter += 1i64
        if !(go && s.flag != 1i64 && s.flag != 2i64 && s.flag != 4i64) { break }
        s.ermin = 0.0f64
        subcshell(s)
    }
}

// a sum rounded once from a compensated accumulation, standing in for R's long double sum
fn lsum(v: []const f64) -> f64 {
    var hi = 0.0f64
    var lo = 0.0f64
    var i = 0usize
    while i < v.len {
        let x = v[i]
        let t = hi + x
        var e = 0.0f64
        if math.abs[f64](hi) >= math.abs[f64](x) { e = (hi - t) + x } else { e = (x - t) + hi }
        hi = t
        lo += e
        i += 1usize
    }
    ret hi + lo
}

type Obj = struct { x: []const f64, n: usize, d: usize, u: []const f64, m: f64, w: []f64, a: []f64, b: []f64 }

// R's `^`: a square is x * x
fn pw(x: f64, y: f64) -> f64 {
    if y == 2.0f64 { ret x * x }
    ret math.pow[f64](x, y)
}

// the `system` function of e1071::cshell for centre i (u is that centre's membership column)
fn objective(o: *Obj, spar: []const f64) -> f64 {
    let n = o.n
    let d = o.d
    let r = spar[d]
    var k = 0usize
    while k < n {
        var nd = 0.0f64
        var j = 0usize
        while j < d {
            let dv = o.x[k + n * j] - spar[j]
            if j == 0usize { nd = dv * dv } else { nd = nd + dv * dv }
            j += 1usize
        }
        o.w[k] = math.sqrt[f64](nd)
        k += 1usize
    }
    k = 0usize
    while k < n {
        o.a[k] = pw(o.u[k], o.m) * (o.w[k] - r)
        k += 1usize
    }
    let s1 = lsum(o.a[0usize..n])
    var op = s1 * s1
    var cs = 0.0f64
    var j = 0usize
    while j < d {
        k = 0usize
        while k < n {
            o.b[k] = (pw(o.u[k], o.m) * (1.0f64 - r / o.w[k])) * (o.x[k + n * j] - spar[j])
            k += 1usize
        }
        let cj = lsum(o.b[0usize..n])
        o.a[j] = cj * cj
        j += 1usize
    }
    cs = lsum(o.a[0usize..d])
    op = op + cs
    ret op
}

// numerical gradient of optim (ndeps 1e-3, central differences)
fn numgrad(o: *Obj, p: []const f64, tmp: []f64, g: []f64) {
    let eps = 0.001f64
    var i = 0usize
    while i < p.len {
        var q = 0usize
        while q < p.len { tmp[q] = p[q]
            q += 1usize }
        tmp[i] = p[i] + eps
        let v1 = objective(o, tmp)
        tmp[i] = p[i] - eps
        let v2 = objective(o, tmp)
        g[i] = (v1 - v2) / (2.0f64 * eps)
        i += 1usize
    }
}

// optim(method = "CG", type 1 Fletcher-Reeves, maxit 100, abstol -Inf, reltol sqrt(eps)): the answer is `X`, the point where the last
// gradient was taken, as R reports it
fn cgmin(a: *mem.Arena, o: *Obj, b: []f64, xout: []f64) -> err {
    let n = b.len
    let (c, e1) = mem.alloc[f64](a, n)
    let (g, e2) = mem.alloc[f64](a, n)
    let (t, e3) = mem.alloc[f64](a, n)
    let (tmp, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    let abstol = 0.0f64 - 1.0f64 / 0.0f64
    let intol = 1.4901161193847656e-8f64
    let stepredn = 0.2f64
    let acctol = 0.0001f64
    let reltest = 10.0f64
    let maxit = 100i64
    let setstep = 1.7f64
    let cyclimit = i64(n)
    let tol = intol * f64(n) * math.sqrt[f64](intol)
    var f = objective(o, b)
    var fmin = f
    var gradcount = 0i64
    var steplength = 1.0f64
    var cycle = 0i64
    var count = 0usize
    var g1 = 0.0f64
    var g2 = 0.0f64
    var g3 = 0.0f64
    var oldstep = 1.0f64
    while true {
        var i = 0usize
        while i < n {
            t[i] = 0.0f64
            c[i] = 0.0f64
            i += 1usize
        }
        cycle = 0i64
        oldstep = 1.0f64
        count = 0usize
        while true {
            cycle += 1i64
            gradcount += 1i64
            if gradcount > maxit { ret ok }
            numgrad(o, b, tmp, g)
            g1 = 0.0f64
            g2 = 0.0f64
            i = 0usize
            while i < n {
                xout[i] = b[i]
                g1 += g[i] * g[i]
                g2 += c[i] * c[i]
                c[i] = g[i]
                i += 1usize
            }
            if g1 > tol {
                if g2 > 0.0f64 { g3 = g1 / g2 } else { g3 = 1.0f64 }
                var gradproj = 0.0f64
                i = 0usize
                while i < n {
                    t[i] = t[i] * g3 - g[i]
                    gradproj += t[i] * g[i]
                    i += 1usize
                }
                steplength = oldstep
                var accpoint = false
                while true {
                    count = 0usize
                    i = 0usize
                    while i < n {
                        b[i] = xout[i] + steplength * t[i]
                        if reltest + xout[i] == reltest + b[i] { count += 1usize }
                        i += 1usize
                    }
                    if count < n {
                        f = objective(o, b)
                        accpoint = f == f && f - f == 0.0f64 && f <= fmin + gradproj * steplength * acctol
                        if !accpoint { steplength = steplength * stepredn } else { fmin = f }
                    }
                    if count == n || accpoint { break }
                }
                if count < n {
                    var newstep = 2.0f64 * (f - fmin - gradproj * steplength)
                    if newstep > 0.0f64 {
                        newstep = 0.0f64 - gradproj * steplength * steplength / newstep
                        i = 0usize
                        while i < n {
                            b[i] = xout[i] + newstep * t[i]
                            i += 1usize
                        }
                        fmin = f
                        f = objective(o, b)
                        if f < fmin {
                            fmin = f
                        } else {
                            i = 0usize
                            while i < n {
                                b[i] = xout[i] + steplength * t[i]
                                i += 1usize
                            }
                        }
                    }
                }
            }
            oldstep = setstep * steplength
            if oldstep > 1.0f64 { oldstep = 1.0f64 }
            if !(count != n && g1 > tol && cycle != cyclimit) { break }
        }
        if !(cycle != 1i64 || (count != n && g1 > tol && fmin > abstol)) { break }
    }
    ret ok
}

type Fit = struct { iter: i64, ermin: f64 }

// the driver of e1071::cshell for given centres (nc by d, column-major in centers, updated), radius (nc, updated) and membership u (n by nc,
// column-major, in the ORIGINAL row order on answer); m the fuzzifier; the stream gives the row permutation `sample(n)` first
fn cshell(a: *mem.Arena, g: *rng.Rng, x0: []const f64, n: usize, d: usize, nc: usize, centers: []f64, radius: []f64, m: f64, dist: i64, itermax: i64, u_out: []f64) -> (Fit, err) {
    var fit: Fit = zero
    let (perm, pe) = rng.sample_int(a, g, i64(n), i64(n), false)
    if pe != ok { ret (fit, pe) }
    let (x, e1) = mem.alloc[f64](a, n * d)
    let (u, e2) = mem.alloc[f64](a, n * nc)
    let (uant, e3) = mem.alloc[f64](a, n * nc)
    let (w, e4) = mem.alloc[f64](a, n)
    let (aa, e5) = mem.alloc[f64](a, n + d)
    let (bb, e6) = mem.alloc[f64](a, n)
    let (spar, e7) = mem.alloc[f64](a, d + 1usize)
    let (xo, e8) = mem.alloc[f64](a, d + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (fit, e1) }
    var k = 0usize
    while k < n {
        var col = 0usize
        while col < d {
            x[k + n * col] = x0[usize(perm[k] - 1i64) + n * col]
            col += 1usize
        }
        k += 1usize
    }
    var q = 0usize
    while q < n * nc { u[q] = 0.0f64
        uant[q] = 0.0f64
        q += 1usize }
    var st = State { n: n, d: d, nc: nc, x: x, centers: centers, u: u, uant: uant, radius: radius, m: m, dist: dist, ermin: 0.0f64, itermax: itermax, iter: 0i64, flag: 0i64 }
    cshell_c(&st)
    while (st.flag == 1i64 || st.flag == 4i64) && st.iter <= itermax {
        st.flag = 3i64
        var i = 0usize
        while i < nc {
            var col = 0usize
            while col < d {
                spar[col] = centers[i + nc * col]
                col += 1usize
            }
            spar[d] = radius[i]
            var ob = Obj { x: x, n: n, d: d, u: u[n * i..n * i + n], m: m, w: w, a: aa, b: bb }
            let ce = cgmin(a, &ob, spar[0usize..d + 1usize], xo[0usize..d + 1usize])
            if ce != ok { ret (fit, ce) }
            col = 0usize
            while col < d {
                centers[i + nc * col] = xo[col]
                col += 1usize
            }
            radius[i] = xo[d]
            i += 1usize
        }
        st.iter = st.iter - 1i64
        cshell_c(&st)
        if st.flag != 2i64 { st.flag = 1i64 }
    }
    fit.iter = st.iter - 1i64
    fit.ermin = st.ermin
    // membership back in the caller's row order: U[order(perm), ]
    k = 0usize
    while k < n {
        var i = 0usize
        while i < nc {
            u_out[usize(perm[k] - 1i64) + n * i] = u[k + n * i]
            i += 1usize
        }
        k += 1usize
    }
    ret (fit, ok)
}
