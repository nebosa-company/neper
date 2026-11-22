// R osqp (OSQP 1.0.0, the QDLDL direct solver): the convex quadratic program minimise 1/2 x'Px + q'x subject to
// l <= Ax <= u by the OSQP ADMM iteration, ported step for step from the C sources: Ruiz equilibration and cost
// scaling (10 passes), the rho vector (1e-6 for loose rows, 1e3 times rho for equalities), the sigma/alpha updates,
// termination every `check_termination` iterations on the unscaled residuals, the duality gap and the infeasibility
// certificates, the iteration-count adaptive rho, the inaccurate statuses at the iteration limit, solution polishing
// with iterative refinement, warm starts and updates of q, l, u, P and A that keep the iterates.
// Matrices are dense and row-major, P is the full symmetric matrix. An infinite bound is +-1e30 (osqp clamps to it).
//
// Not here: sparse storage, the time limit, the time-based and KKT-error rho rules, the indirect (CG) solver,
// non-vector rho, code generation and derivatives. The QDLDL fill-reducing order is not reproduced: the KKT matrix
// is factorised densely in natural order, so values agree with osqp to rounding, not bit for bit.

use e.math
use e.mem

// osqp status values: 1 solved, 2 solved inaccurate, 3 primal infeasible, 4 primal infeasible inaccurate,
// 5 dual infeasible, 6 dual infeasible inaccurate, 7 maximum iterations, 9 non convex, 11 unsolved
type Settings = struct {
    rho: f64,
    sigma: f64,
    alpha: f64,
    eps_abs: f64,
    eps_rel: f64,
    eps_prim_inf: f64,
    eps_dual_inf: f64,
    delta: f64,
    adaptive_rho_tolerance: f64,
    max_iter: usize,
    check_termination: usize,
    adaptive_rho: usize,
    adaptive_rho_interval: usize,
    polishing: usize,
    polish_refine_iter: usize,
    scaling: usize,
    scaled_termination: usize,
    check_dualgap: usize,
    warm_starting: usize
}

// status_polish: 1 success, -1 failed, 0 not performed, 2 no active set
type Info = struct {
    iter: usize,
    status: usize,
    status_polish: f64,
    obj_val: f64,
    dual_obj_val: f64,
    prim_res: f64,
    dual_res: f64,
    duality_gap: f64,
    rho_estimate: f64,
    rho_updates: usize
}

type Osqp = struct {
    n: usize,
    m: usize,
    st: Settings,
    info: Info,
    pinfo: Info,
    p0: []f64,
    a0: []f64,
    q0: []f64,
    l0: []f64,
    u0: []f64,
    p: []f64,
    a: []f64,
    q: []f64,
    l: []f64,
    u: []f64,
    d: []f64,
    dinv: []f64,
    e: []f64,
    einv: []f64,
    c: f64,
    cinv: f64,
    rho_vec: []f64,
    rho_inv: []f64,
    ctype: []f64,
    kkt: []f64,
    x: []f64,
    z: []f64,
    y: []f64,
    xp: []f64,
    zp: []f64,
    dx: []f64,
    dy: []f64,
    xt: []f64,
    zt: []f64,
    sol: []f64,
    rhs: []f64,
    px: []f64,
    ax: []f64,
    aty: []f64,
    tn: []f64,
    tm: []f64,
    polx: []f64,
    polz: []f64,
    poly: []f64,
    ared: []f64,
    pb: []f64,
    ps: []f64,
    pr: []f64,
    spr: f64,
    sdr: f64,
    sdg: f64,
    xtpx: f64,
    qtx: f64,
    sc: f64,
    sol_x: []f64,
    sol_y: []f64,
    pcert: []f64,
    dcert: []f64
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

fn copyv(src: []const f64, dst: []f64) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
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

fn scaled_norm_inf(w: []const f64, v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        let t = math.abs[f64](w[i] * v[i])
        if t > s { s = t }
        i += 1usize
    }
    ret s
}

fn dot(x: []const f64, y: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

// out = am (rows x cols) * x
fn matvec(am: []const f64, rows: usize, cols: usize, x: []const f64, out: []f64) {
    var i = 0usize
    while i < rows {
        var s = 0.0f64
        var j = 0usize
        while j < cols {
            s += am[i * cols + j] * x[j]
            j += 1usize
        }
        out[i] = s
        i += 1usize
    }
}

// out = am' * x
fn matvec_t(am: []const f64, rows: usize, cols: usize, x: []const f64, out: []f64) {
    var j = 0usize
    while j < cols {
        var s = 0.0f64
        var i = 0usize
        while i < rows {
            s += am[i * cols + j] * x[i]
            i += 1usize
        }
        out[j] = s
        j += 1usize
    }
}

fn infval() -> f64 { ret 1.0e30f64 * 1.0e-4f64 }

fn division_tol() -> f64 { ret 1.0f64 / 1.0e30f64 }

fn limit_scaling(v: f64) -> f64 {
    var r = v
    if r < 1.0e-4f64 { r = 1.0f64 }
    if r > 1.0e4f64 { r = 1.0e4f64 }
    ret r
}

fn default_settings() -> Settings {
    ret Settings {
        rho: 0.1f64,
        sigma: 1.0e-6f64,
        alpha: 1.6f64,
        eps_abs: 1.0e-3f64,
        eps_rel: 1.0e-3f64,
        eps_prim_inf: 1.0e-4f64,
        eps_dual_inf: 1.0e-4f64,
        delta: 1.0e-6f64,
        adaptive_rho_tolerance: 5.0f64,
        max_iter: 4000usize,
        check_termination: 25usize,
        adaptive_rho: 1usize,
        adaptive_rho_interval: 50usize,
        polishing: 0usize,
        polish_refine_iter: 3usize,
        scaling: 10usize,
        scaled_termination: 0usize,
        check_dualgap: 1usize,
        warm_starting: 1usize
    }
}

fn blank_info() -> Info {
    ret Info {
        iter: 0usize,
        status: 11usize,
        status_polish: 0.0f64,
        obj_val: 0.0f64,
        dual_obj_val: 0.0f64,
        prim_res: 0.0f64,
        dual_res: 0.0f64,
        duality_gap: 0.0f64,
        rho_estimate: 0.0f64,
        rho_updates: 0usize
    }
}

fn info_ptr(o: *Osqp, pol: bool) -> *Info {
    if pol { ret &o.pinfo }
    ret &o.info
}

// in-place LDL' of the symmetric matrix whose lower triangle is in k (dim x dim), natural order, no pivoting;
// false on a zero pivot
fn ldl_factor(k: []f64, dim: usize) -> bool {
    var j = 0usize
    while j < dim {
        var dj = k[j * dim + j]
        var t = 0usize
        while t < j {
            let l = k[j * dim + t]
            dj -= l * l * k[t * dim + t]
            t += 1usize
        }
        k[j * dim + j] = dj
        if dj == 0.0f64 { ret false }
        var i = j + 1usize
        while i < dim {
            var v = k[i * dim + j]
            t = 0usize
            while t < j {
                v -= k[i * dim + t] * k[j * dim + t] * k[t * dim + t]
                t += 1usize
            }
            k[i * dim + j] = v / dj
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

fn ldl_solve(k: []const f64, dim: usize, b: []f64) {
    var i = 0usize
    while i < dim {
        var s = b[i]
        var t = 0usize
        while t < i {
            s -= k[i * dim + t] * b[t]
            t += 1usize
        }
        b[i] = s
        i += 1usize
    }
    i = 0usize
    while i < dim {
        b[i] = b[i] / k[i * dim + i]
        i += 1usize
    }
    i = dim
    while i > 0usize {
        i = i - 1usize
        var s = b[i]
        var t = i + 1usize
        while t < dim {
            s -= k[t * dim + i] * b[t]
            t += 1usize
        }
        b[i] = s
    }
}

// [P + sigma I, A'; A, -diag(1/rho)] factorised into o.kkt
fn factor(o: *Osqp) -> bool {
    let n = o.n
    let m = o.m
    let dim = n + m
    var i = 0usize
    while i < dim * dim {
        o.kkt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            o.kkt[i * dim + j] = o.p[i * n + j]
            j += 1usize
        }
        o.kkt[i * dim + i] += o.st.sigma
        i += 1usize
    }
    i = 0usize
    while i < m {
        var j = 0usize
        while j < n {
            o.kkt[(n + i) * dim + j] = o.a[i * n + j]
            j += 1usize
        }
        o.kkt[(n + i) * dim + n + i] = 0.0f64 - o.rho_inv[i]
        i += 1usize
    }
    ret ldl_factor(o.kkt, dim)
}

// Ruiz equilibration and cost scaling of the original data
fn rescale(o: *Osqp) {
    let n = o.n
    let m = o.m
    copyv(o.p0, o.p)
    copyv(o.a0, o.a)
    copyv(o.q0, o.q)
    var i = 0usize
    while i < n {
        o.d[i] = 1.0f64
        o.dinv[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < m {
        o.e[i] = 1.0f64
        o.einv[i] = 1.0f64
        i += 1usize
    }
    o.c = 1.0f64
    o.cinv = 1.0f64
    var pass = 0usize
    while pass < o.st.scaling {
        // inf norms of the columns of the KKT matrix [P A'; A 0]
        var j = 0usize
        while j < n {
            var s = 0.0f64
            i = 0usize
            while i < n {
                let t = math.abs[f64](o.p[i * n + j])
                if t > s { s = t }
                i += 1usize
            }
            var s2 = 0.0f64
            i = 0usize
            while i < m {
                let t = math.abs[f64](o.a[i * n + j])
                if t > s2 { s2 = t }
                i += 1usize
            }
            if s2 > s { s = s2 }
            o.tn[j] = 1.0f64 / math.sqrt[f64](limit_scaling(s))
            j += 1usize
        }
        i = 0usize
        while i < m {
            var s = 0.0f64
            j = 0usize
            while j < n {
                let t = math.abs[f64](o.a[i * n + j])
                if t > s { s = t }
                j += 1usize
            }
            o.tm[i] = 1.0f64 / math.sqrt[f64](limit_scaling(s))
            i += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                o.p[i * n + j] = o.p[i * n + j] * o.tn[i]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            j = 0usize
            while j < n {
                o.p[i * n + j] = o.p[i * n + j] * o.tn[j]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < m {
            j = 0usize
            while j < n {
                o.a[i * n + j] = o.a[i * n + j] * o.tm[i]
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < m {
            j = 0usize
            while j < n {
                o.a[i * n + j] = o.a[i * n + j] * o.tn[j]
                j += 1usize
            }
            i += 1usize
        }
        j = 0usize
        while j < n {
            o.q[j] = o.q[j] * o.tn[j]
            o.d[j] = o.d[j] * o.tn[j]
            j += 1usize
        }
        i = 0usize
        while i < m {
            o.e[i] = o.e[i] * o.tm[i]
            i += 1usize
        }
        // cost normalisation
        var total = 0.0f64
        j = 0usize
        while j < n {
            var s = 0.0f64
            i = 0usize
            while i < n {
                let t = math.abs[f64](o.p[i * n + j])
                if t > s { s = t }
                i += 1usize
            }
            total += s
            j += 1usize
        }
        var c_temp = total / f64(n)
        let qn = limit_scaling(norm_inf(o.q))
        if qn > c_temp { c_temp = qn }
        c_temp = 1.0f64 / limit_scaling(c_temp)
        i = 0usize
        while i < n * n {
            o.p[i] = o.p[i] * c_temp
            i += 1usize
        }
        j = 0usize
        while j < n {
            o.q[j] = o.q[j] * c_temp
            j += 1usize
        }
        o.c = o.c * c_temp
        pass += 1usize
    }
    o.cinv = 1.0f64 / o.c
    i = 0usize
    while i < n {
        o.dinv[i] = 1.0f64 / o.d[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        o.einv[i] = 1.0f64 / o.e[i]
        o.l[i] = o.l0[i] * o.e[i]
        o.u[i] = o.u0[i] * o.e[i]
        i += 1usize
    }
}

fn clamp_bound(v: f64) -> f64 {
    var r = v
    if r > 1.0e30f64 { r = 1.0e30f64 }
    if r < 0.0f64 - 1.0e30f64 { r = 0.0f64 - 1.0e30f64 }
    ret r
}

// refreshes the constraint types and the rho vector; true when a type changed
fn set_rho_vec(o: *Osqp) -> bool {
    if o.st.rho < 1.0e-6f64 { o.st.rho = 1.0e-6f64 }
    if o.st.rho > 1.0e6f64 { o.st.rho = 1.0e6f64 }
    var changed = false
    let big = infval()
    var i = 0usize
    while i < o.m {
        var t = 0.0f64
        if o.l[i] < 0.0f64 - big && o.u[i] > big {
            t = 0.0f64 - 1.0f64
        } else if o.u[i] - o.l[i] < 1.0e-4f64 {
            t = 1.0f64
        }
        if t != o.ctype[i] { changed = true }
        o.ctype[i] = t
        i += 1usize
    }
    fill_rho(o)
    ret changed
}

fn fill_rho(o: *Osqp) {
    var i = 0usize
    while i < o.m {
        var r = o.st.rho
        if o.ctype[i] < 0.0f64 { r = 1.0e-6f64 }
        if o.ctype[i] > 0.0f64 { r = 1.0e3f64 * o.st.rho }
        o.rho_vec[i] = r
        o.rho_inv[i] = 1.0f64 / r
        i += 1usize
    }
}

fn cold_start(o: *Osqp) {
    var i = 0usize
    while i < o.n {
        o.x[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < o.m {
        o.z[i] = 0.0f64
        o.y[i] = 0.0f64
        i += 1usize
    }
}

// the problem data are copied (an infinite bound is clamped to +-1e30); the factorisation is built
fn setup(a: *mem.Arena, n: usize, m: usize, p: []const f64, q: []const f64, am: []const f64, l: []const f64, u: []const f64, st: Settings) -> (*Osqp, err) {
    let (bx, eb) = mem.alloc[Osqp](a, 1usize)
    if eb != ok { ret (&bx[0], eb) }
    bx[0] = Osqp {
        n: n,
        m: m,
        st: st,
        info: blank_info(),
        pinfo: blank_info(),
        p0: vec(a, n * n),
        a0: vec(a, m * n),
        q0: vec(a, n),
        l0: vec(a, m),
        u0: vec(a, m),
        p: vec(a, n * n),
        a: vec(a, m * n),
        q: vec(a, n),
        l: vec(a, m),
        u: vec(a, m),
        d: vec(a, n),
        dinv: vec(a, n),
        e: vec(a, m),
        einv: vec(a, m),
        c: 1.0f64,
        cinv: 1.0f64,
        rho_vec: vec(a, m),
        rho_inv: vec(a, m),
        ctype: vec(a, m),
        kkt: vec(a, (n + m) * (n + m)),
        x: vec(a, n),
        z: vec(a, m),
        y: vec(a, m),
        xp: vec(a, n),
        zp: vec(a, m),
        dx: vec(a, n),
        dy: vec(a, m),
        xt: vec(a, n),
        zt: vec(a, m),
        sol: vec(a, n + m),
        rhs: vec(a, n + m),
        px: vec(a, n),
        ax: vec(a, m),
        aty: vec(a, n),
        tn: vec(a, n),
        tm: vec(a, m),
        polx: vec(a, n),
        polz: vec(a, m),
        poly: vec(a, m),
        ared: vec(a, m * n),
        pb: vec(a, n + m),
        ps: vec(a, n + m),
        pr: vec(a, n + m),
        spr: 0.0f64,
        sdr: 0.0f64,
        sdg: 0.0f64,
        xtpx: 0.0f64,
        qtx: 0.0f64,
        sc: 0.0f64,
        sol_x: vec(a, n),
        sol_y: vec(a, m),
        pcert: vec(a, m),
        dcert: vec(a, n)
    }
    let o = &bx[0]
    copyv(p, o.p0)
    copyv(am, o.a0)
    copyv(q, o.q0)
    var i = 0usize
    while i < m {
        o.l0[i] = clamp_bound(l[i])
        o.u0[i] = clamp_bound(u[i])
        i += 1usize
    }
    if o.st.adaptive_rho_interval == 0usize {
        if o.st.check_termination > 0usize {
            o.st.adaptive_rho_interval = 4usize * o.st.check_termination
        } else {
            o.st.adaptive_rho_interval = 100usize
        }
    }
    rescale(o)
    let _ = set_rho_vec(o)
    if !factor(o) { ret (o, mem.Exhausted) }
    cold_start(o)
    o.info.rho_estimate = o.st.rho
    ret (o, ok)
}

fn prim_res(o: *Osqp, x: []const f64, z: []const f64) -> f64 {
    matvec(o.a, o.m, o.n, x, o.ax)
    var s = 0.0f64
    var sc = 0.0f64
    var i = 0usize
    while i < o.m {
        let r = o.ax[i] - z[i]
        let t = math.abs[f64](r)
        if t > s { s = t }
        let w = math.abs[f64](o.einv[i] * r)
        if w > sc { sc = w }
        i += 1usize
    }
    o.spr = s
    if o.st.scaling > 0usize && o.st.scaled_termination == 0usize { ret sc }
    ret s
}

fn dual_res(o: *Osqp, x: []const f64, y: []const f64) -> f64 {
    let n = o.n
    matvec(o.p, n, n, x, o.px)
    if o.m > 0usize { matvec_t(o.a, o.m, n, y, o.aty) }
    var s = 0.0f64
    var sc = 0.0f64
    var j = 0usize
    while j < n {
        var r = o.q[j]
        r += o.px[j]
        if o.m > 0usize { r += o.aty[j] }
        let t = math.abs[f64](r)
        if t > s { s = t }
        let w = math.abs[f64](o.dinv[j] * r)
        if w > sc { sc = w }
        j += 1usize
    }
    o.sdr = s
    if o.st.scaling > 0usize && o.st.scaled_termination == 0usize { ret o.cinv * sc }
    ret s
}

// y projected onto the polar of the recession cone of [l, u]
fn project_polar(o: *Osqp, v: []f64) {
    let big = infval()
    var i = 0usize
    while i < o.m {
        if o.u[i] > big {
            if o.l[i] < 0.0f64 - big {
                v[i] = 0.0f64
            } else if v[i] > 0.0f64 {
                v[i] = 0.0f64
            }
        } else if o.l[i] < 0.0f64 - big {
            if v[i] < 0.0f64 { v[i] = 0.0f64 }
        }
        i += 1usize
    }
}

fn update_info(o: *Osqp, x: []const f64, z: []const f64, y: []const f64, pol: bool) {
    let inf = info_ptr(o, pol)
    if o.m == 0usize {
        inf.prim_res = 0.0f64
    } else {
        inf.prim_res = prim_res(o, x, z)
    }
    inf.dual_res = dual_res(o, x, y)
    obj_gap(o, x, y, inf)
}

// objective, dual objective and duality gap at (x, y); needs o.px from dual_res
fn obj_gap(o: *Osqp, x: []const f64, y: []const f64, inf: *Info) {
    let quad = dot(o.px, x)
    let lin = dot(o.q, x)
    var i = 0usize
    while i < o.m {
        o.tm[i] = y[i]
        i += 1usize
    }
    project_polar(o, o.tm)
    var sup = 0.0f64
    i = 0usize
    while i < o.m {
        if math.abs[f64](o.tm[i]) < 1.0e-15f64 { o.tm[i] = 0.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < o.m {
        var pos = o.tm[i]
        if pos < 0.0f64 { pos = 0.0f64 }
        sup += o.u[i] * pos
        i += 1usize
    }
    i = 0usize
    while i < o.m {
        var neg = o.tm[i]
        if neg > 0.0f64 { neg = 0.0f64 }
        sup += o.l[i] * neg
        i += 1usize
    }
    inf.obj_val = 0.5f64 * quad + lin
    inf.dual_obj_val = 0.0f64 - 0.5f64 * quad - sup
    o.sdg = quad + lin + sup
    if o.st.scaling > 0usize {
        inf.obj_val = inf.obj_val * o.cinv
        inf.dual_obj_val = inf.dual_obj_val * o.cinv
        inf.duality_gap = o.cinv * o.sdg
    } else {
        inf.duality_gap = o.sdg
    }
    o.xtpx = quad
    o.qtx = lin
    o.sc = sup
}

fn is_primal_infeasible(o: *Osqp, eps: f64) -> bool {
    project_polar(o, o.dy)
    var nd = 0.0f64
    if o.st.scaling > 0usize && o.st.scaled_termination == 0usize {
        nd = scaled_norm_inf(o.e, o.dy)
    } else {
        nd = norm_inf(o.dy)
    }
    if nd > division_tol() {
        var lhs = 0.0f64
        var i = 0usize
        while i < o.m {
            var pos = o.dy[i]
            if pos < 0.0f64 { pos = 0.0f64 }
            lhs += o.u[i] * pos
            i += 1usize
        }
        i = 0usize
        while i < o.m {
            var neg = o.dy[i]
            if neg > 0.0f64 { neg = 0.0f64 }
            lhs += o.l[i] * neg
            i += 1usize
        }
        if lhs < 0.0f64 {
            matvec_t(o.a, o.m, o.n, o.dy, o.tn)
            if o.st.scaling > 0usize && o.st.scaled_termination == 0usize {
                var j = 0usize
                while j < o.n {
                    o.tn[j] = o.tn[j] * o.dinv[j]
                    j += 1usize
                }
            }
            ret norm_inf(o.tn) < eps * nd
        }
    }
    ret false
}

fn is_dual_infeasible(o: *Osqp, eps: f64) -> bool {
    let scaled = o.st.scaling > 0usize && o.st.scaled_termination == 0usize
    var nd = 0.0f64
    var cost_scaling = 1.0f64
    if scaled {
        nd = scaled_norm_inf(o.d, o.dx)
        cost_scaling = o.c
    } else {
        nd = norm_inf(o.dx)
    }
    if nd > division_tol() {
        if dot(o.q, o.dx) < 0.0f64 {
            matvec(o.p, o.n, o.n, o.dx, o.tn)
            if scaled {
                var j = 0usize
                while j < o.n {
                    o.tn[j] = o.tn[j] * o.dinv[j]
                    j += 1usize
                }
            }
            if norm_inf(o.tn) < cost_scaling * eps * nd {
                matvec(o.a, o.m, o.n, o.dx, o.tm)
                if scaled {
                    var i = 0usize
                    while i < o.m {
                        o.tm[i] = o.tm[i] * o.einv[i]
                        i += 1usize
                    }
                }
                let big = infval()
                let tol = eps * nd
                var i = 0usize
                while i < o.m {
                    if (o.u[i] < big && o.tm[i] > tol) || (o.l[i] > 0.0f64 - big && o.tm[i] < 0.0f64 - tol) { ret false }
                    i += 1usize
                }
                ret true
            }
        }
    }
    ret false
}

fn set_status(o: *Osqp, s: usize) {
    o.info.status = s
}

fn check_termination(o: *Osqp, approximate: bool) -> bool {
    var eps_abs = o.st.eps_abs
    var eps_rel = o.st.eps_rel
    var eps_prim_inf = o.st.eps_prim_inf
    var eps_dual_inf = o.st.eps_dual_inf
    if o.info.prim_res > 1.0e30f64 || o.info.dual_res > 1.0e30f64 {
        set_status(o, 9usize)
        o.info.obj_val = 0.0f64 / 0.0f64
        ret true
    }
    if approximate {
        eps_abs = eps_abs * 10.0f64
        eps_rel = eps_rel * 10.0f64
        eps_prim_inf = eps_prim_inf * 10.0f64
        eps_dual_inf = eps_dual_inf * 10.0f64
    }
    let scaled = o.st.scaling > 0usize && o.st.scaled_termination == 0usize
    var prim_ok = false
    var dual_ok = false
    var gap_ok = false
    var prim_inf = false
    var dual_inf = false
    if o.m == 0usize {
        prim_ok = true
    } else {
        var mx = 0.0f64
        if scaled {
            mx = scaled_norm_inf(o.einv, o.z)
            let t = scaled_norm_inf(o.einv, o.ax)
            if t > mx { mx = t }
        } else {
            mx = norm_inf(o.z)
            let t = norm_inf(o.ax)
            if t > mx { mx = t }
        }
        let eps_prim = eps_abs + eps_rel * mx
        if o.info.prim_res < eps_prim {
            prim_ok = true
        } else {
            prim_inf = is_primal_infeasible(o, eps_prim_inf)
        }
    }
    var md = 0.0f64
    if scaled {
        md = scaled_norm_inf(o.dinv, o.q)
        var t = scaled_norm_inf(o.dinv, o.aty)
        if t > md { md = t }
        t = scaled_norm_inf(o.dinv, o.px)
        if t > md { md = t }
        md = md * o.cinv
    } else {
        md = norm_inf(o.q)
        var t = norm_inf(o.aty)
        if t > md { md = t }
        t = norm_inf(o.px)
        if t > md { md = t }
    }
    let eps_dual = eps_abs + eps_rel * md
    if o.info.dual_res < eps_dual {
        dual_ok = true
    } else {
        dual_inf = is_dual_infeasible(o, eps_dual_inf)
    }
    if o.st.check_dualgap != 0usize {
        var mg = math.abs[f64](o.xtpx)
        if math.abs[f64](o.qtx) > mg { mg = math.abs[f64](o.qtx) }
        if math.abs[f64](o.sc) > mg { mg = math.abs[f64](o.sc) }
        if scaled { mg = o.cinv * mg }
        let eps_gap = eps_abs + eps_rel * mg
        if scaled {
            if math.abs[f64](o.info.duality_gap) < eps_gap { gap_ok = true }
        } else {
            if math.abs[f64](o.sdg) < eps_gap { gap_ok = true }
        }
    } else {
        gap_ok = true
    }
    if prim_ok && dual_ok && gap_ok {
        if approximate { set_status(o, 2usize) } else { set_status(o, 1usize) }
        ret true
    }
    if prim_inf {
        if approximate { set_status(o, 4usize) } else { set_status(o, 3usize) }
        if scaled {
            var i = 0usize
            while i < o.m {
                o.dy[i] = o.dy[i] * o.e[i]
                i += 1usize
            }
        }
        o.info.obj_val = 1.0e30f64
        ret true
    }
    if dual_inf {
        if approximate { set_status(o, 6usize) } else { set_status(o, 5usize) }
        if scaled {
            var j = 0usize
            while j < o.n {
                o.dx[j] = o.dx[j] * o.d[j]
                j += 1usize
            }
        }
        o.info.obj_val = 0.0f64 - 1.0e30f64
        ret true
    }
    ret false
}

fn rho_estimate(o: *Osqp) -> f64 {
    var pn = norm_inf(o.z)
    let t1 = norm_inf(o.ax)
    if t1 > pn { pn = t1 }
    let pr = o.spr / (pn + division_tol())
    var dn = norm_inf(o.q)
    let t2 = norm_inf(o.aty)
    if t2 > dn { dn = t2 }
    let t3 = norm_inf(o.px)
    if t3 > dn { dn = t3 }
    let dr = o.sdr / (dn + division_tol())
    var r = o.st.rho * math.sqrt[f64](pr / dr)
    if r < 1.0e-6f64 { r = 1.0e-6f64 }
    if r > 1.0e6f64 { r = 1.0e6f64 }
    ret r
}

fn update_rho(o: *Osqp, rho_new: f64) -> bool {
    o.st.rho = rho_new
    if o.st.rho < 1.0e-6f64 { o.st.rho = 1.0e-6f64 }
    if o.st.rho > 1.0e6f64 { o.st.rho = 1.0e6f64 }
    fill_rho(o)
    ret factor(o)
}

fn adapt_rho(o: *Osqp) {
    let est = rho_estimate(o)
    o.info.rho_estimate = est
    if est > o.st.rho * o.st.adaptive_rho_tolerance || est < o.st.rho / o.st.adaptive_rho_tolerance {
        let _ = update_rho(o, est)
        o.info.rho_updates += 1usize
    }
}

fn has_solution(o: *Osqp) -> bool {
    let s = o.info.status
    ret s != 3usize && s != 4usize && s != 5usize && s != 6usize && s != 9usize
}

// the active-set solve of the reduced KKT system [P+delta I, Ared'; Ared, -delta I] with iterative refinement;
// it replaces the iterate when the residuals shrink
fn polish(o: *Osqp) {
    let n = o.n
    let m = o.m
    var na = 0usize
    var i = 0usize
    // flags in o.tm: -1 lower or equality, 1 upper, 0 inactive
    while i < m {
        var f = 0.0f64
        if o.z[i] - o.l[i] < 0.0f64 - o.y[i] || o.l[i] == o.u[i] {
            f = 0.0f64 - 1.0f64
            na += 1usize
        } else if o.u[i] - o.z[i] < o.y[i] {
            f = 1.0f64
            na += 1usize
        }
        o.tm[i] = f
        i += 1usize
    }
    if na == 0usize {
        o.info.status_polish = 2.0f64
        ret
    }
    let dim = n + na
    i = 0usize
    while i < dim * dim {
        o.kkt[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            o.kkt[i * dim + j] = o.p[i * n + j]
            j += 1usize
        }
        o.kkt[i * dim + i] += o.st.delta
        o.pb[i] = 0.0f64 - o.q[i]
        i += 1usize
    }
    var r = 0usize
    i = 0usize
    while i < m {
        if o.tm[i] != 0.0f64 {
            j = 0usize
            while j < n {
                o.ared[r * n + j] = o.a[i * n + j]
                o.kkt[(n + r) * dim + j] = o.a[i * n + j]
                j += 1usize
            }
            o.kkt[(n + r) * dim + n + r] = 0.0f64 - o.st.delta
            if o.tm[i] < 0.0f64 { o.pb[n + r] = o.l[i] } else { o.pb[n + r] = o.u[i] }
            r += 1usize
        }
        i += 1usize
    }
    if !ldl_factor(o.kkt, dim) {
        o.info.status_polish = 0.0f64 - 1.0f64
        let _ = factor(o)
        ret
    }
    i = 0usize
    while i < dim {
        o.ps[i] = o.pb[i]
        i += 1usize
    }
    ldl_solve(o.kkt, dim, o.ps)
    var it = 0usize
    while it < o.st.polish_refine_iter {
        // pr = pb - [P Ared'; Ared 0] ps
        j = 0usize
        while j < n {
            var s = o.pb[j]
            var t = 0usize
            while t < n {
                s -= o.p[j * n + t] * o.ps[t]
                t += 1usize
            }
            o.pr[j] = s
            j += 1usize
        }
        r = 0usize
        while r < na {
            j = 0usize
            while j < n {
                o.pr[j] -= o.ared[r * n + j] * o.ps[n + r]
                j += 1usize
            }
            var s = o.pb[n + r]
            j = 0usize
            while j < n {
                s -= o.ared[r * n + j] * o.ps[j]
                j += 1usize
            }
            o.pr[n + r] = s
            r += 1usize
        }
        ldl_solve(o.kkt, dim, o.pr)
        i = 0usize
        while i < dim {
            o.ps[i] += o.pr[i]
            i += 1usize
        }
        it += 1usize
    }
    j = 0usize
    while j < n {
        o.polx[j] = o.ps[j]
        j += 1usize
    }
    matvec(o.a, m, n, o.polx, o.polz)
    r = 0usize
    i = 0usize
    while i < m {
        if o.tm[i] != 0.0f64 {
            o.poly[i] = o.ps[n + r]
            r += 1usize
        } else {
            o.poly[i] = 0.0f64
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        let yy = o.poly[i] + o.polz[i]
        var zc = yy
        if zc < o.l[i] { zc = o.l[i] }
        if zc > o.u[i] { zc = o.u[i] }
        o.polz[i] = zc
        o.poly[i] = yy - zc
        i += 1usize
    }
    update_info(o, o.polx, o.polz, o.poly, true)
    let pi = o.pinfo
    let ci = o.info
    var good = false
    if pi.prim_res < ci.prim_res && pi.dual_res < ci.dual_res { good = true }
    if pi.prim_res < ci.prim_res && ci.dual_res < 1.0e-10f64 { good = true }
    if pi.dual_res < ci.dual_res && ci.prim_res < 1.0e-10f64 { good = true }
    if good {
        o.info.obj_val = pi.obj_val
        o.info.dual_obj_val = pi.dual_obj_val
        o.info.duality_gap = pi.duality_gap
        o.info.prim_res = pi.prim_res
        o.info.dual_res = pi.dual_res
        o.info.status_polish = 1.0f64
        copyv(o.polx, o.x)
        copyv(o.polz, o.z)
        copyv(o.poly, o.y)
    } else {
        o.info.status_polish = 0.0f64 - 1.0f64
    }
    let _ = factor(o)
}

fn store_solution(o: *Osqp) {
    let nan = 0.0f64 / 0.0f64
    var i = 0usize
    if has_solution(o) {
        i = 0usize
        while i < o.n {
            if o.st.scaling > 0usize { o.sol_x[i] = o.x[i] * o.d[i] } else { o.sol_x[i] = o.x[i] }
            o.dcert[i] = nan
            i += 1usize
        }
        i = 0usize
        while i < o.m {
            if o.st.scaling > 0usize { o.sol_y[i] = o.y[i] * o.e[i] * o.cinv } else { o.sol_y[i] = o.y[i] }
            o.pcert[i] = nan
            i += 1usize
        }
        ret
    }
    i = 0usize
    while i < o.n {
        o.sol_x[i] = nan
        o.dcert[i] = nan
        i += 1usize
    }
    i = 0usize
    while i < o.m {
        o.sol_y[i] = nan
        o.pcert[i] = nan
        i += 1usize
    }
    cold_start(o)
    let s = o.info.status
    if s == 3usize || s == 4usize {
        let nv = norm_inf(o.dy)
        i = 0usize
        while i < o.m {
            o.pcert[i] = o.dy[i] * (1.0f64 / nv)
            i += 1usize
        }
    }
    if s == 5usize || s == 6usize {
        let nv = norm_inf(o.dx)
        i = 0usize
        while i < o.n {
            o.dcert[i] = o.dx[i] * (1.0f64 / nv)
            i += 1usize
        }
    }
}

// the ADMM loop; the answer is in o.info, o.sol_x, o.sol_y and the certificates
fn solve_problem(o: *Osqp) {
    let n = o.n
    let m = o.m
    if o.st.warm_starting == 0usize { cold_start(o) }
    var can_check = false
    var iter = 1usize
    var done = false
    while iter <= o.st.max_iter && !done {
        copyv(o.x, o.xp)
        copyv(o.z, o.zp)
        var j = 0usize
        while j < n {
            o.rhs[j] = o.st.sigma * o.xp[j] - o.q[j]
            j += 1usize
        }
        var i = 0usize
        while i < m {
            o.rhs[n + i] = o.zp[i] - o.rho_inv[i] * o.y[i]
            i += 1usize
        }
        copyv(o.rhs, o.sol)
        ldl_solve(o.kkt, n + m, o.sol)
        j = 0usize
        while j < n {
            o.xt[j] = o.sol[j]
            j += 1usize
        }
        i = 0usize
        while i < m {
            o.zt[i] = o.rhs[n + i] + o.rho_inv[i] * o.sol[n + i]
            i += 1usize
        }
        let al = o.st.alpha
        j = 0usize
        while j < n {
            o.x[j] = al * o.xt[j] + (1.0f64 - al) * o.xp[j]
            o.dx[j] = o.x[j] - o.xp[j]
            j += 1usize
        }
        i = 0usize
        while i < m {
            var v = o.rho_inv[i] * o.y[i] + al * o.zt[i] + (1.0f64 - al) * o.zp[i]
            if v < o.l[i] { v = o.l[i] }
            if v > o.u[i] { v = o.u[i] }
            o.z[i] = v
            let d = (al * o.zt[i] + (1.0f64 - al) * o.zp[i] - v) * o.rho_vec[i]
            o.dy[i] = d
            o.y[i] = o.y[i] + d
            i += 1usize
        }
        can_check = o.st.check_termination > 0usize && iter % o.st.check_termination == 0usize
        var can_adapt = o.st.adaptive_rho == 1usize && o.st.adaptive_rho_interval > 0usize && iter % o.st.adaptive_rho_interval == 0usize
        if can_check || can_adapt || iter == 1usize {
            update_info(o, o.x, o.z, o.y, false)
            o.info.iter = iter
        }
        if can_check {
            if check_termination(o, false) { done = true }
        }
        if !done {
            if can_adapt { adapt_rho(o) }
            iter += 1usize
        }
    }
    if !can_check {
        update_info(o, o.x, o.z, o.y, false)
        o.info.iter = iter - 1usize
        let _ = check_termination(o, false)
    }
    if has_solution(o) { obj_gap(o, o.x, o.y, &o.info) }
    if o.info.status == 11usize {
        if !check_termination(o, true) { set_status(o, 7usize) }
    }
    o.info.rho_estimate = rho_estimate(o)
    if o.st.polishing != 0usize && o.info.status == 1usize { polish(o) }
    store_solution(o)
}

fn reset_info(o: *Osqp) {
    o.info.status = 11usize
    o.info.rho_updates = 0usize
}

fn warm_start(o: *Osqp, x: []const f64, y: []const f64) {
    o.st.warm_starting = 1usize
    var j = 0usize
    while j < o.n {
        o.x[j] = x[j] * o.dinv[j]
        j += 1usize
    }
    var i = 0usize
    while i < o.m {
        o.y[i] = y[i] * o.einv[i] * o.c
        i += 1usize
    }
    matvec(o.a, o.m, o.n, o.x, o.z)
}

// replaces q, l and u (the scaling is kept); false when l > u somewhere
fn update_vec(o: *Osqp, q: []const f64, l: []const f64, u: []const f64) -> bool {
    var i = 0usize
    while i < o.m {
        if l[i] * o.e[i] > u[i] * o.e[i] { ret false }
        i += 1usize
    }
    i = 0usize
    while i < o.m {
        o.l0[i] = clamp_bound(l[i])
        o.u0[i] = clamp_bound(u[i])
        o.l[i] = o.l0[i] * o.e[i]
        o.u[i] = o.u0[i] * o.e[i]
        i += 1usize
    }
    if set_rho_vec(o) { let _ = factor(o) }
    i = 0usize
    while i < o.n {
        o.q0[i] = q[i]
        o.q[i] = q[i] * o.d[i] * o.c
        i += 1usize
    }
    reset_info(o)
    ret true
}

// replaces the values of P and A (same shape); the scaling is recomputed and the iterates are kept
fn update_mat(o: *Osqp, p: []const f64, am: []const f64) {
    copyv(p, o.p0)
    copyv(am, o.a0)
    rescale(o)
    let _ = factor(o)
    reset_info(o)
}
