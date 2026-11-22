// R clarabel: the conic quadratic program minimise 1/2 x'Px + q'x subject to Ax + s = b, s in K, with K a product of
// zero cones, nonnegative cones, second-order cones, exponential cones {y e^(x/y) <= z, y > 0} and power cones
// {x^a y^(1-a) >= |z|}. Dense matrices, row-major; P is the full symmetric matrix.
//
// This is a primal barrier path-following method (an infeasible-start Newton iteration on the central path
// z = -mu grad f(s), mu cut by a factor after each centred step), not Clarabel's homogeneous embedding: it reaches the
// unique optimum of a strictly feasible problem to about 1e-9, so x, s, the objective and the status of solved,
// primal infeasible and dual infeasible problems agree with clarabel run to a tight tolerance; the iteration count
// does not. Infeasibility is read off the diverging iterates (a certificate by normalisation), not by a homogeneous
// embedding.
//
// The cone spec is a flat array: nz, nl, nsoc, the soc sizes, nexp, npow, the power exponents (zero rows first,
// then the nonnegative rows, the second-order cones, the exponential cones, the power cones, as in R).
//
// Not here: the semidefinite and generalised power cones, sparse storage, the iteration count of clarabel.

use e.math
use e.mem

// status as clarabel returns it: 2 solved, 3 primal infeasible, 4 dual infeasible, 8 iteration limit
type Result = struct { status: usize, iters: usize, obj: f64 }

type Ctx = struct {
    n: usize,
    m: usize,
    nz: usize,
    mk: usize,
    nb: usize,
    maxd: usize,
    p: []const f64,
    q: []const f64,
    am: []const f64,
    b: []const f64,
    kind: []usize,
    off: []usize,
    dim: []usize,
    par: []f64,
    x: []f64,
    sk: []f64,
    zk: []f64,
    yz: []f64,
    dx: []f64,
    dsk: []f64,
    dzk: []f64,
    dyz: []f64,
    xt: []f64,
    st: []f64,
    zt: []f64,
    yt: []f64,
    rd: []f64,
    rpk: []f64,
    rpz: []f64,
    rc: []f64,
    gk: []f64,
    hd: []f64,
    tt: []f64,
    kkt: []f64,
    rhs: []f64,
    wb: []f64,
    vb: []f64,
    vc: []f64,
    bw: []f64,
    tk: []f64,
    tn: []f64,
    s0: []f64
}

fn vec(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n)
    var i = 0usize
    while i < v.len {
        v[i] = 0.0f64
        i += 1usize
    }
    ret v
}

fn uvec(a: *mem.Arena, n: usize) -> []usize {
    let (v, e) = mem.alloc[usize](a, n)
    var i = 0usize
    while i < v.len {
        v[i] = 0usize
        i += 1usize
    }
    ret v
}

fn norm_inf(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        let t = math.abs[f64](v[i])
        if t > s { s = t }
        i += 1usize
    }
    ret s
}

fn sumsq(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * v[i]
        i += 1usize
    }
    ret s
}

// solves w * x = b in place (w dim x dim row-major, partial pivoting); false when singular
fn lu_solve(w: []f64, dim: usize, b: []f64) -> bool {
    var c = 0usize
    while c < dim {
        var pv = c
        var best = math.abs[f64](w[c * dim + c])
        var r = c + 1usize
        while r < dim {
            let t = math.abs[f64](w[r * dim + c])
            if t > best {
                best = t
                pv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if pv != c {
            var j = 0usize
            while j < dim {
                let t = w[c * dim + j]
                w[c * dim + j] = w[pv * dim + j]
                w[pv * dim + j] = t
                j += 1usize
            }
            let tb = b[c]
            b[c] = b[pv]
            b[pv] = tb
        }
        r = c + 1usize
        while r < dim {
            let f = w[r * dim + c] / w[c * dim + c]
            if f != 0.0f64 {
                var j = c
                while j < dim {
                    w[r * dim + j] -= f * w[c * dim + j]
                    j += 1usize
                }
                b[r] -= f * b[c]
            }
            r += 1usize
        }
        c += 1usize
    }
    var i = dim
    while i > 0usize {
        i = i - 1usize
        var s = b[i]
        var j = i + 1usize
        while j < dim {
            s -= w[i * dim + j] * b[j]
            j += 1usize
        }
        b[i] = s / w[i * dim + i]
    }
    ret true
}

// is v (cone block at off) in the interior of the cone
fn interior(kind: usize, dim: usize, par: f64, v: []const f64, off: usize) -> bool {
    if kind == 1usize { ret v[off] > 0.0f64 }
    if kind == 2usize {
        var u2 = 0.0f64
        var i = 1usize
        while i < dim {
            u2 += v[off + i] * v[off + i]
            i += 1usize
        }
        ret v[off] > 0.0f64 && v[off] * v[off] > u2
    }
    let x = v[off]
    let y = v[off + 1usize]
    let z = v[off + 2usize]
    if kind == 3usize {
        if y <= 0.0f64 || z <= 0.0f64 { ret false }
        ret y * math.log[f64](z / y) - x > 0.0f64
    }
    if x <= 0.0f64 || y <= 0.0f64 { ret false }
    ret math.pow[f64](x, 2.0f64 * par) * math.pow[f64](y, 2.0f64 * (1.0f64 - par)) - z * z > 0.0f64
}

// the barrier gradient of the block into g (indexed like v) and, when want_h, its Hessian into hd (mk x mk) at (kb, kb)
fn block_barrier(kind: usize, dim: usize, par: f64, v: []const f64, off: usize, g: []f64, hd: []f64, mk: usize, want_h: bool, w: []f64) {
    if kind == 1usize {
        let s = v[off]
        g[off] = 0.0f64 - 1.0f64 / s
        if want_h { hd[off * mk + off] = 1.0f64 / (s * s) }
        ret
    }
    if kind == 2usize {
        let t = v[off]
        var u2 = 0.0f64
        var i = 1usize
        while i < dim {
            u2 += v[off + i] * v[off + i]
            i += 1usize
        }
        let d = t * t - u2
        g[off] = 0.0f64 - 2.0f64 * t / d
        i = 1usize
        while i < dim {
            g[off + i] = 2.0f64 * v[off + i] / d
            i += 1usize
        }
        if want_h {
            i = 0usize
            while i < dim {
                var wi = 0.0f64 - 2.0f64 * v[off + i]
                if i == 0usize { wi = 2.0f64 * t }
                var j = 0usize
                while j < dim {
                    var wj = 0.0f64 - 2.0f64 * v[off + j]
                    if j == 0usize { wj = 2.0f64 * t }
                    var h = wi * wj / (d * d)
                    if i == j {
                        if i == 0usize { h -= 2.0f64 / d } else { h += 2.0f64 / d }
                    }
                    hd[(off + i) * mk + off + j] = h
                    j += 1usize
                }
                i += 1usize
            }
        }
        ret
    }
    let x = v[off]
    let y = v[off + 1usize]
    let z = v[off + 2usize]
    // gv: the gradient and hv: the Hessian of the argument of the log, hl: its barrier tail
    var wi = 0usize
    while wi < 18usize {
        w[wi] = 0.0f64
        wi += 1usize
    }
    let gv = w[0usize..3usize]
    let hv = w[3usize..12usize]
    let tg = w[12usize..15usize]
    let th = w[15usize..18usize]
    var gg = 0.0f64
    if kind == 3usize {
        // g = y log(z/y) - x
        gg = y * math.log[f64](z / y) - x
        gv[0usize] = 0.0f64 - 1.0f64
        gv[1usize] = math.log[f64](z / y) - 1.0f64
        gv[2usize] = y / z
        hv[4usize] = 0.0f64 - 1.0f64 / y
        hv[5usize] = 1.0f64 / z
        hv[7usize] = 1.0f64 / z
        hv[8usize] = 0.0f64 - y / (z * z)
        tg[1usize] = 1.0f64 / y
        tg[2usize] = 1.0f64 / z
        th[1usize] = 1.0f64 / (y * y)
        th[2usize] = 1.0f64 / (z * z)
    } else {
        let be = 1.0f64 - par
        let px = math.pow[f64](x, 2.0f64 * par)
        let py = math.pow[f64](y, 2.0f64 * be)
        gg = px * py - z * z
        gv[0usize] = 2.0f64 * par * px * py / x
        gv[1usize] = 2.0f64 * be * px * py / y
        gv[2usize] = 0.0f64 - 2.0f64 * z
        hv[0usize] = 2.0f64 * par * (2.0f64 * par - 1.0f64) * px * py / (x * x)
        hv[1usize] = 4.0f64 * par * be * px * py / (x * y)
        hv[3usize] = hv[1usize]
        hv[4usize] = 2.0f64 * be * (2.0f64 * be - 1.0f64) * px * py / (y * y)
        hv[8usize] = 0.0f64 - 2.0f64
        tg[0usize] = be / x
        tg[1usize] = par / y
        th[0usize] = be / (x * x)
        th[1usize] = par / (y * y)
    }
    var i = 0usize
    while i < 3usize {
        g[off + i] = 0.0f64 - gv[i] / gg - tg[i]
        i += 1usize
    }
    if want_h {
        i = 0usize
        while i < 3usize {
            var j = 0usize
            while j < 3usize {
                var h = gv[i] * gv[j] / (gg * gg) - hv[i * 3usize + j] / gg
                if i == j { h += th[i] }
                hd[(off + i) * mk + off + j] = h
                j += 1usize
            }
            i += 1usize
        }
    }
}

// a canonical interior point of the block
fn canonical(kind: usize, par: f64, s: []f64, off: usize) {
    if kind == 1usize || kind == 2usize {
        s[off] = 1.0f64
        ret
    }
    if kind == 3usize {
        s[off] = 0.0f64 - 1.051383f64
        s[off + 1usize] = 0.556409f64
        s[off + 2usize] = 1.258967f64
        ret
    }
    s[off] = math.sqrt[f64](1.0f64 + par)
    s[off + 1usize] = math.sqrt[f64](2.0f64 - par)
}

fn all_interior(c: *Ctx, v: []const f64) -> bool {
    var k = 0usize
    while k < c.nb {
        if !interior(c.kind[k], c.dim[k], c.par[k], v, c.off[k]) { ret false }
        k += 1usize
    }
    ret true
}

fn grads(c: *Ctx, s: []const f64, want_h: bool) {
    var i = 0usize
    if want_h {
        while i < c.mk * c.mk {
            c.hd[i] = 0.0f64
            i += 1usize
        }
    }
    var k = 0usize
    while k < c.nb {
        block_barrier(c.kind[k], c.dim[k], c.par[k], s, c.off[k], c.gk, c.hd, c.mk, want_h, c.bw)
        k += 1usize
    }
}

// the residual vectors at (x, s, z, y) for barrier parameter mu; returns their joint 2-norm
fn residuals(c: *Ctx, x: []const f64, s: []const f64, z: []const f64, y: []const f64, mu: f64) -> f64 {
    let n = c.n
    var j = 0usize
    while j < n {
        var t = c.q[j]
        var k = 0usize
        while k < n {
            t += c.p[j * n + k] * x[k]
            k += 1usize
        }
        var i = 0usize
        while i < c.mk {
            t += c.am[(c.nz + i) * n + j] * z[i]
            i += 1usize
        }
        i = 0usize
        while i < c.nz {
            t += c.am[i * n + j] * y[i]
            i += 1usize
        }
        c.rd[j] = t
        j += 1usize
    }
    var i = 0usize
    while i < c.mk {
        var t = s[i] - c.b[c.nz + i]
        j = 0usize
        while j < n {
            t += c.am[(c.nz + i) * n + j] * x[j]
            j += 1usize
        }
        c.rpk[i] = t
        i += 1usize
    }
    i = 0usize
    while i < c.nz {
        var t = 0.0f64 - c.b[i]
        j = 0usize
        while j < n {
            t += c.am[i * n + j] * x[j]
            j += 1usize
        }
        c.rpz[i] = t
        i += 1usize
    }
    grads(c, s, false)
    i = 0usize
    while i < c.mk {
        c.rc[i] = z[i] + mu * c.gk[i]
        i += 1usize
    }
    ret math.sqrt[f64](sumsq(c.rd) + sumsq(c.rpk) + sumsq(c.rpz) + sumsq(c.rc))
}

fn objective(c: *Ctx, x: []const f64) -> f64 {
    var t = 0.0f64
    var j = 0usize
    while j < c.n {
        var r = 0.0f64
        var k = 0usize
        while k < c.n {
            r += c.p[j * c.n + k] * x[k]
            k += 1usize
        }
        t += x[j] * (0.5f64 * r + c.q[j])
        j += 1usize
    }
    ret t
}

// the Newton direction at the current point for parameter mu into dx, dsk, dzk, dyz; false when the system is singular
fn newton(c: *Ctx, mu: f64) -> bool {
    let n = c.n
    let mk = c.mk
    let nz = c.nz
    let dim = n + nz
    grads(c, c.sk, true)
    // tt = H * A_K (mk x n)
    var i = 0usize
    while i < mk {
        var j = 0usize
        while j < n {
            var t = 0.0f64
            var k = 0usize
            while k < mk {
                t += c.hd[i * mk + k] * c.am[(nz + k) * n + j]
                k += 1usize
            }
            c.tt[i * n + j] = t
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < dim * dim {
        c.kkt[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < n {
        var l = 0usize
        while l < n {
            var t = c.p[j * n + l]
            var k = 0usize
            while k < mk {
                t += mu * c.am[(nz + k) * n + j] * c.tt[k * n + l]
                k += 1usize
            }
            c.kkt[j * dim + l] = t
            l += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < nz {
        j = 0usize
        while j < n {
            c.kkt[(n + i) * dim + j] = c.am[i * n + j]
            c.kkt[j * dim + n + i] = c.am[i * n + j]
            j += 1usize
        }
        c.kkt[(n + i) * dim + n + i] = 0.0f64 - 1.0e-12f64
        i += 1usize
    }
    // vector rc - mu H rpk in tk
    i = 0usize
    while i < mk {
        var t = 0.0f64
        var k = 0usize
        while k < mk {
            t += c.hd[i * mk + k] * c.rpk[k]
            k += 1usize
        }
        c.tk[i] = c.rc[i] - mu * t
        i += 1usize
    }
    j = 0usize
    while j < n {
        var t = 0.0f64 - c.rd[j]
        i = 0usize
        while i < mk {
            t += c.am[(nz + i) * n + j] * c.tk[i]
            i += 1usize
        }
        c.rhs[j] = t
        j += 1usize
    }
    i = 0usize
    while i < nz {
        c.rhs[n + i] = 0.0f64 - c.rpz[i]
        i += 1usize
    }
    if !lu_solve(c.kkt, dim, c.rhs) { ret false }
    j = 0usize
    while j < n {
        c.dx[j] = c.rhs[j]
        j += 1usize
    }
    i = 0usize
    while i < nz {
        c.dyz[i] = c.rhs[n + i]
        i += 1usize
    }
    i = 0usize
    while i < mk {
        var t = 0.0f64 - c.rpk[i]
        j = 0usize
        while j < n {
            t -= c.am[(nz + i) * n + j] * c.dx[j]
            j += 1usize
        }
        c.dsk[i] = t
        i += 1usize
    }
    i = 0usize
    while i < mk {
        var t = 0.0f64 - c.rc[i]
        var k = 0usize
        while k < mk {
            t -= mu * c.hd[i * mk + k] * c.dsk[k]
            k += 1usize
        }
        c.dzk[i] = t
        i += 1usize
    }
    ret true
}

// the largest proximity of z to the central path z = -mu grad f(s) over the cone blocks (the dual local norm)
fn proximity(c: *Ctx, mu: f64) -> f64 {
    grads(c, c.sk, true)
    var worst = 0.0f64
    var k = 0usize
    while k < c.nb {
        let d = c.dim[k]
        let o = c.off[k]
        var i = 0usize
        while i < d {
            c.vb[i] = c.zk[o + i] + mu * c.gk[o + i]
            var j = 0usize
            while j < d {
                c.wb[i * d + j] = c.hd[(o + i) * c.mk + o + j]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < d {
            c.vc[i] = c.vb[i]
            i += 1usize
        }
        if !lu_solve(c.wb, d, c.vb) { ret 1.0e30f64 }
        var q2 = 0.0f64
        i = 0usize
        while i < d {
            q2 += c.vc[i] * c.vb[i]
            i += 1usize
        }
        let eta = math.sqrt[f64](math.abs[f64](q2)) / mu
        if eta > worst { worst = eta }
        k += 1usize
    }
    ret worst
}

fn copyv(src: []const f64, dst: []f64) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

// out = A' * (nz_part for the zero rows, y for the cone rows)
fn matvec_t_all(c: *Ctx, y: []const f64, nz_part: []const f64, out: []f64) {
    var j = 0usize
    while j < c.n {
        var t = 0.0f64
        var i = 0usize
        while i < c.nz {
            t += c.am[i * c.n + j] * nz_part[i]
            i += 1usize
        }
        i = 0usize
        while i < c.mk {
            t += c.am[(c.nz + i) * c.n + j] * y[i]
            i += 1usize
        }
        out[j] = t
        j += 1usize
    }
}

// 3 primal infeasible, 4 dual infeasible, 0 neither, read off the iterates by normalisation
fn certificate(c: *Ctx) -> usize {
    let n = c.n
    var zmax = norm_inf(c.zk)
    let ym = norm_inf(c.yz)
    if ym > zmax { zmax = ym }
    if zmax > 0.0f64 {
        matvec_t_all(c, c.zk, c.yz, c.tn)
        var bz = 0.0f64
        var i = 0usize
        while i < c.nz {
            bz += c.b[i] * c.yz[i]
            i += 1usize
        }
        i = 0usize
        while i < c.mk {
            bz += c.b[c.nz + i] * c.zk[i]
            i += 1usize
        }
        if norm_inf(c.tn) <= 1.0e-6f64 * zmax && bz <= 0.0f64 - 1.0e-6f64 * zmax { ret 3usize }
    }
    let xm = norm_inf(c.x)
    if xm > 0.0f64 {
        var j = 0usize
        while j < n {
            c.tn[j] = c.x[j] / xm
            j += 1usize
        }
        var pd = 0.0f64
        var qd = 0.0f64
        j = 0usize
        while j < n {
            var t = 0.0f64
            var k = 0usize
            while k < n {
                t += c.p[j * n + k] * c.tn[k]
                k += 1usize
            }
            if math.abs[f64](t) > pd { pd = math.abs[f64](t) }
            qd += c.q[j] * c.tn[j]
            j += 1usize
        }
        var az = 0.0f64
        var i = 0usize
        while i < c.nz {
            var t = 0.0f64
            j = 0usize
            while j < n {
                t += c.am[i * n + j] * c.tn[j]
                j += 1usize
            }
            if math.abs[f64](t) > az { az = math.abs[f64](t) }
            i += 1usize
        }
        i = 0usize
        while i < c.mk {
            var t = 0.0f64
            j = 0usize
            while j < n {
                t -= c.am[(c.nz + i) * n + j] * c.tn[j]
                j += 1usize
            }
            c.tk[i] = t + 1.0e-5f64 * c.s0[i]
            i += 1usize
        }
        if pd <= 1.0e-6f64 && az <= 1.0e-6f64 && qd <= 0.0f64 - 1.0e-6f64 && all_interior(c, c.tk) { ret 4usize }
    }
    ret 0usize
}

fn gap_of(c: *Ctx) -> f64 {
    var gap = 0.0f64
    var i = 0usize
    while i < c.mk {
        gap += c.sk[i] * c.zk[i]
        i += 1usize
    }
    ret gap
}

// 1 when the residuals and the gap are within tol (relative to the data), else 0
fn converged(c: *Ctx, tol: f64) -> bool {
    let rdn = norm_inf(c.rd)
    var rpn = norm_inf(c.rpk)
    let rzn = norm_inf(c.rpz)
    if rzn > rpn { rpn = rzn }
    let obj = objective(c, c.x)
    ret rdn <= tol * (1.0f64 + norm_inf(c.q)) && rpn <= tol * (1.0f64 + norm_inf(c.b)) && math.abs[f64](gap_of(c)) <= tol * (1.0f64 + math.abs[f64](obj))
}

// x, s and z (the multipliers: free for the zero rows, in the dual cone for the others) receive the solution
fn solve_core(a: *mem.Arena, n: usize, m: usize, p: []const f64, q: []const f64, am: []const f64, b: []const f64, spec: []const f64, x_out: []f64, s_out: []f64, z_out: []f64) -> Result {
    let bad = Result { status: 10usize, iters: 0usize, obj: 0.0f64 / 0.0f64 }
    let nz = usize(spec[0usize])
    let nl = usize(spec[1usize])
    let nsoc = usize(spec[2usize])
    let nexp = usize(spec[3usize + nsoc])
    let npow = usize(spec[4usize + nsoc])
    let nb = nl + nsoc + nexp + npow
    let kind = uvec(a, nb)
    let off = uvec(a, nb)
    let dim = uvec(a, nb)
    let par = vec(a, nb)
    var k = 0usize
    var at = 0usize
    var maxd = 3usize
    while k < nl {
        kind[k] = 1usize
        dim[k] = 1usize
        off[k] = at
        at += 1usize
        k += 1usize
    }
    var s_i = 0usize
    while s_i < nsoc {
        let d = usize(spec[3usize + s_i])
        kind[k] = 2usize
        dim[k] = d
        off[k] = at
        at += d
        if d > maxd { maxd = d }
        k += 1usize
        s_i += 1usize
    }
    var e_i = 0usize
    while e_i < nexp {
        kind[k] = 3usize
        dim[k] = 3usize
        off[k] = at
        at += 3usize
        k += 1usize
        e_i += 1usize
    }
    var p_i = 0usize
    while p_i < npow {
        kind[k] = 4usize
        dim[k] = 3usize
        par[k] = spec[5usize + nsoc + p_i]
        off[k] = at
        at += 3usize
        k += 1usize
        p_i += 1usize
    }
    let mk = at
    if nz + mk != m { ret bad }
    let kd = n + nz
    var c = Ctx {
        n: n, m: m, nz: nz, mk: mk, nb: nb, maxd: maxd,
        p: p, q: q, am: am, b: b,
        kind: kind, off: off, dim: dim, par: par,
        x: vec(a, n), sk: vec(a, mk), zk: vec(a, mk), yz: vec(a, nz),
        dx: vec(a, n), dsk: vec(a, mk), dzk: vec(a, mk), dyz: vec(a, nz),
        xt: vec(a, n), st: vec(a, mk), zt: vec(a, mk), yt: vec(a, nz),
        rd: vec(a, n), rpk: vec(a, mk), rpz: vec(a, nz), rc: vec(a, mk),
        gk: vec(a, mk), hd: vec(a, mk * mk), tt: vec(a, mk * n),
        kkt: vec(a, kd * kd), rhs: vec(a, kd), wb: vec(a, maxd * maxd), vb: vec(a, maxd), vc: vec(a, maxd), bw: vec(a, 18usize),
        tk: vec(a, mk), tn: vec(a, n), s0: vec(a, mk)
    }
    let cp = &c
    k = 0usize
    while k < nb {
        canonical(kind[k], par[k], cp.s0, off[k])
        k += 1usize
    }
    var mu = 1.0f64
    var i = 0usize
    while i < mk {
        cp.sk[i] = cp.s0[i]
        i += 1usize
    }
    grads(cp, cp.sk, false)
    i = 0usize
    while i < mk {
        cp.zk[i] = 0.0f64 - mu * cp.gk[i]
        i += 1usize
    }
    let mu0 = mu
    let r0 = 1.0e-300f64 + residuals_feas0(cp)
    var status = 8usize
    var it = 0usize
    var stall = 0usize
    var done = false
    while it < 300usize && !done {
        let phi = residuals(cp, cp.x, cp.sk, cp.zk, cp.yz, mu)
        if converged(cp, 1.0e-12f64) {
            status = 2usize
            done = true
        } else if !newton(cp, mu) {
            done = true
        } else {
            var al = 1.0f64
            var okstep = false
            while al > 1.0e-14f64 && !okstep {
                i = 0usize
                while i < mk {
                    cp.st[i] = cp.sk[i] + al * cp.dsk[i]
                    cp.zt[i] = cp.zk[i] + al * cp.dzk[i]
                    i += 1usize
                }
                if all_interior(cp, cp.st) {
                    var j = 0usize
                    while j < n {
                        cp.xt[j] = cp.x[j] + al * cp.dx[j]
                        j += 1usize
                    }
                    i = 0usize
                    while i < nz {
                        cp.yt[i] = cp.yz[i] + al * cp.dyz[i]
                        i += 1usize
                    }
                    let pt = residuals(cp, cp.xt, cp.st, cp.zt, cp.yt, mu)
                    if pt <= (1.0f64 - 1.0e-4f64 * al) * phi { okstep = true }
                }
                if !okstep { al = al * 0.5f64 }
            }
            if !okstep {
                stall += 1usize
                if stall >= 6usize {
                    done = true
                } else {
                    mu = mu * 5.0f64
                }
            } else {
                stall = 0usize
                copyv(cp.xt, cp.x)
                copyv(cp.st, cp.sk)
                copyv(cp.zt, cp.zk)
                copyv(cp.yt, cp.yz)
                let eta = proximity(cp, mu)
                if eta <= 0.5f64 && mu > 1.0e-15f64 {
                    let rf = residuals(cp, cp.x, cp.sk, cp.zk, cp.yz, mu)
                    var rfeas = math.sqrt[f64](sumsq(cp.rd) + sumsq(cp.rpk) + sumsq(cp.rpz))
                    var floor_mu = 0.1f64 * mu0 * rfeas / r0
                    mu = mu * 0.2f64
                    if mu < floor_mu { mu = floor_mu }
                }
            }
        }
        it += 1usize
        if norm_inf(cp.x) > 1.0e13f64 || norm_inf(cp.zk) > 1.0e13f64 { done = true }
    }
    if status != 2usize {
        let phi = residuals(cp, cp.x, cp.sk, cp.zk, cp.yz, mu)
        if converged(cp, 1.0e-8f64) {
            status = 2usize
        } else {
            status = certificate(cp)
            if status == 0usize { status = 8usize }
        }
    }
    let _ = residuals(cp, cp.x, cp.sk, cp.zk, cp.yz, mu)
    copyv(cp.x, x_out)
    i = 0usize
    while i < nz {
        s_out[i] = 0.0f64
        z_out[i] = cp.yz[i]
        i += 1usize
    }
    i = 0usize
    while i < mk {
        s_out[nz + i] = cp.sk[i]
        z_out[nz + i] = cp.zk[i]
        i += 1usize
    }
    ret Result { status: status, iters: it, obj: objective(cp, cp.x) }
}

// the feasibility residual norm at the starting point
fn residuals_feas0(c: *Ctx) -> f64 {
    let _ = residuals(c, c.x, c.sk, c.zk, c.yz, 1.0f64)
    ret math.sqrt[f64](sumsq(c.rd) + sumsq(c.rpk) + sumsq(c.rpz))
}

// the number of cone rows (nonnegative, second-order, exponential and power) and the rows' dimension total
fn cone_rows(spec: []const f64) -> usize {
    let nl = usize(spec[1usize])
    let nsoc = usize(spec[2usize])
    var t = nl
    var i = 0usize
    while i < nsoc {
        t += usize(spec[3usize + i])
        i += 1usize
    }
    t += 3usize * usize(spec[3usize + nsoc])
    t += 3usize * usize(spec[4usize + nsoc])
    ret t
}

// 1 when the certificate of primal infeasibility (a dual cone point z with A'z = 0 and b'z = -1) exists, found by solving
// the strictly convex feasibility problem for the smallest such z; 0 otherwise
fn primal_certificate(a: *mem.Arena, n: usize, m: usize, p: []const f64, q: []const f64, am: []const f64, b: []const f64, spec: []const f64) -> bool {
    let nz = usize(spec[0usize])
    let mk = cone_rows(spec)
    let nsoc = usize(spec[2usize])
    let nexp = usize(spec[3usize + nsoc])
    let npow = usize(spec[4usize + nsoc])
    let ma = n + 1usize + mk
    let pa = vec(a, m * m)
    var i = 0usize
    while i < m {
        pa[i * m + i] = 1.0e-6f64
        i += 1usize
    }
    let qa = vec(a, m)
    let aa = vec(a, ma * m)
    let ba = vec(a, ma)
    var j = 0usize
    while j < n {
        i = 0usize
        while i < m {
            aa[j * m + i] = am[i * n + j]
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < m {
        aa[n * m + i] = b[i]
        i += 1usize
    }
    ba[n] = 0.0f64 - 1.0f64
    // the cone rows of z (the zero-cone rows are free): z in the dual cone, written s + A z = 0
    let ne = 2.718281828459045f64
    var r = n + 1usize
    var k = 0usize
    let nl = usize(spec[1usize])
    while k < nl {
        aa[r * m + nz + k] = 0.0f64 - 1.0f64
        r += 1usize
        k += 1usize
    }
    var at = nz + nl
    var si = 0usize
    while si < nsoc {
        let d = usize(spec[3usize + si])
        k = 0usize
        while k < d {
            aa[r * m + at + k] = 0.0f64 - 1.0f64
            r += 1usize
            k += 1usize
        }
        at += d
        si += 1usize
    }
    var ei = 0usize
    while ei < nexp {
        aa[r * m + at + 1usize] = 1.0f64
        aa[(r + 1usize) * m + at] = 1.0f64
        aa[(r + 2usize) * m + at + 2usize] = 0.0f64 - ne
        r += 3usize
        at += 3usize
        ei += 1usize
    }
    var pi = 0usize
    while pi < npow {
        let al = spec[5usize + nsoc + pi]
        aa[r * m + at] = 0.0f64 - 1.0f64 / al
        aa[(r + 1usize) * m + at + 1usize] = 0.0f64 - 1.0f64 / (1.0f64 - al)
        aa[(r + 2usize) * m + at + 2usize] = 0.0f64 - 1.0f64
        r += 3usize
        at += 3usize
        pi += 1usize
    }
    let sa = vec(a, 6usize + nsoc + npow)
    sa[0usize] = f64(n + 1usize)
    var t = 1usize
    while t < 5usize + nsoc + npow {
        sa[t] = spec[t]
        t += 1usize
    }
    let xo = vec(a, m)
    let so = vec(a, ma)
    let zo = vec(a, ma)
    let res = solve_core(a, m, ma, pa, qa, aa, ba, sa, xo, so, zo)
    ret res.status == 2usize
}

// 1 when the certificate of dual infeasibility (x with Px = 0, q'x = -1, A_Z x = 0 and -A_K x in K) exists
fn dual_certificate(a: *mem.Arena, n: usize, m: usize, p: []const f64, q: []const f64, am: []const f64, b: []const f64, spec: []const f64) -> bool {
    let nz = usize(spec[0usize])
    let nsoc = usize(spec[2usize])
    let nexp = usize(spec[3usize + nsoc])
    let npow = usize(spec[4usize + nsoc])
    let mk = m - nz
    let nza = n + 1usize + nz
    let ma = nza + mk
    let pa = vec(a, n * n)
    var i = 0usize
    while i < n {
        pa[i * n + i] = 1.0e-6f64
        i += 1usize
    }
    let qa = vec(a, n)
    let aa = vec(a, ma * n)
    let ba = vec(a, ma)
    var j = 0usize
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            aa[i * n + j] = p[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < n {
        aa[n * n + j] = q[j]
        j += 1usize
    }
    ba[n] = 0.0f64 - 1.0f64
    i = 0usize
    while i < nz {
        j = 0usize
        while j < n {
            aa[(n + 1usize + i) * n + j] = am[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < mk {
        j = 0usize
        while j < n {
            aa[(nza + i) * n + j] = am[(nz + i) * n + j]
            j += 1usize
        }
        i += 1usize
    }
    let sa = vec(a, 5usize + nsoc + npow)
    sa[0usize] = f64(nza)
    var t = 1usize
    while t < 5usize + nsoc + npow {
        sa[t] = spec[t]
        t += 1usize
    }
    let xo = vec(a, n)
    let so = vec(a, ma)
    let zo = vec(a, ma)
    let res = solve_core(a, n, ma, pa, qa, aa, ba, sa, xo, so, zo)
    ret res.status == 2usize
}

// x, s and z (the multipliers: free for the zero rows, in the dual cone for the others) receive the solution; the status is
// 2 solved, 3 primal infeasible, 4 dual infeasible, 8 neither (not converged)
fn solve(a: *mem.Arena, n: usize, m: usize, p: []const f64, q: []const f64, am: []const f64, b: []const f64, spec: []const f64, x_out: []f64, s_out: []f64, z_out: []f64) -> Result {
    var r = solve_core(a, n, m, p, q, am, b, spec, x_out, s_out, z_out)
    if r.status != 8usize { ret r }
    if primal_certificate(a, n, m, p, q, am, b, spec) {
        r.status = 3usize
        ret r
    }
    if dual_certificate(a, n, m, p, q, am, b, spec) { r.status = 4usize }
    ret r
}
