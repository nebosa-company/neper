// R stats::StructTS(x, type)$model0: the basic structural model (level, local linear trend or BSM with period nf) with
// its variances fitted by optim's L-BFGS-B on the Kalman likelihood, returned as the state-space model na_kalman uses.
//
// The first value of x must be present. type: 0 level, 1 trend, 2 BSM (nf >= 2). The variances start at 1 (times
// var(x) / 100) and are bounded below by 0, as in R.

use e.math
use e.mem
use e.algo.stat.kalman as kal
use e.algo.stat.lbfgsb as lbf

type StsCtx = struct { ar: *mem.Arena, y: []const f64, base: kal.SsModel, np: usize, vx: f64, scratch: []f64, lo: []f64, up: []f64 }

fn sts_f(c: *StsCtx, par: []const f64) -> f64 {
    var allz = true
    var i = 0usize
    while i <= c.np {
        if par[i] != 0.0f64 { allz = false }
        i += 1usize
    }
    if allz { ret 1000.0f64 }
    let st = mem.mark(c.ar)
    let (mc, e1) = kal.ss_copy(c.ar, &c.base)
    if e1 != ok {
        mem.reset(c.ar, st)
        ret 0.0f64 / 0.0f64
    }
    var m = mc
    let p = m.p
    i = 0usize
    while i < c.np {
        m.vm[i * p + i] = par[i] * c.vx
        i += 1usize
    }
    m.h = par[c.np] * c.vx
    let (ssq, sumlog, nu, e2) = kal.kalman_filter(c.ar, &m, c.y, 0i64 - 1i64, zero, zero)
    mem.reset(c.ar, st)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret 0.5f64 * (ssq / f64(nu) + sumlog / f64(nu))
}

fn sts_g(c: *StsCtx, par: []const f64, g: []f64) {
    var i = 0usize
    while i <= c.np {
        c.scratch[i] = par[i]
        i += 1usize
    }
    let okd = lbf.lbfgsb_fd_gradient[StsCtx](c, sts_f, c.scratch, c.lo, c.up, 0.001f64, g)
}

fn sts_var(y: []const f64) -> f64 {
    var m = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < y.len {
        if y[i] == y[i] {
            m += y[i]
            cnt += 1usize
        }
        i += 1usize
    }
    m = m / f64(cnt)
    var s = 0.0f64
    i = 0usize
    while i < y.len {
        if y[i] == y[i] { s += (y[i] - m) * (y[i] - m) }
        i += 1usize
    }
    ret s / f64(cnt - 1usize)
}

// the fitted model0
fn struct_ts_model(ar: *mem.Arena, y: []const f64, kind: usize, nf: usize) -> (kal.SsModel, err) {
    var p = 1usize
    var np = 1usize
    if kind == 1usize {
        p = 2usize
        np = 2usize
    }
    if kind == 2usize {
        p = nf + 1usize
        np = 3usize
    }
    let (tm, e1) = mem.alloc[f64](ar, p * p)
    let (zv, e2) = mem.alloc[f64](ar, p)
    let (vm, e3) = mem.alloc[f64](ar, p * p)
    let (av, e4) = mem.alloc[f64](ar, p)
    let (pm, e5) = mem.alloc[f64](ar, p * p)
    let (pn, e6) = mem.alloc[f64](ar, p * p)
    var out: kal.SsModel = zero
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Exhausted) }
    var i = 0usize
    while i < p * p {
        tm[i] = 0.0f64
        vm[i] = 0.0f64
        pm[i] = 0.0f64
        pn[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        zv[i] = 0.0f64
        av[i] = 0.0f64
        i += 1usize
    }
    zv[0usize] = 1.0f64
    av[0usize] = y[0usize]
    if kind == 0usize {
        tm[0usize] = 1.0f64
        vm[0usize] = 1.0f64
    } else {
        tm[0usize] = 1.0f64
        tm[1usize] = 1.0f64
        tm[p + 1usize] = 1.0f64
        vm[0usize] = 1.0f64
        vm[p + 1usize] = 1.0f64
        if kind == 2usize {
            zv[2usize] = 1.0f64
            vm[2usize * p + 2usize] = 1.0f64
            var j = 2usize
            while j < p {
                tm[2usize * p + j] = 0.0f64 - 1.0f64
                j += 1usize
            }
            // T[ind + 1, ind] = 1 for ind = 3..nf (1-based): rows 3.. , columns 2..
            j = 3usize
            while j <= nf {
                tm[j * p + (j - 1usize)] = 1.0f64
                j += 1usize
            }
        }
    }
    let vx = sts_var(y) / 100.0f64
    i = 0usize
    while i < p * p {
        pm[i] = 1.0e6f64 * vx
        i += 1usize
    }
    let base = kal.SsModel{ p: p, tm: tm, zv: zv, h: 1.0f64, vm: vm, av: av, pm: pm, pn: pn }
    let (scratch, e7) = mem.alloc[f64](ar, np + 1usize)
    let (lo, e8) = mem.alloc[f64](ar, np + 1usize)
    let (up, e9) = mem.alloc[f64](ar, np + 1usize)
    let (par, e10) = mem.alloc[f64](ar, np + 1usize)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret (out, mem.Exhausted) }
    i = 0usize
    while i <= np {
        lo[i] = 0.0f64
        up[i] = 1.0e308f64
        par[i] = 1.0f64
        i += 1usize
    }
    var ctx = StsCtx{ ar: ar, y: y, base: base, np: np, vx: vx, scratch: scratch, lo: lo, up: up }
    let (fmin, fail) = lbf.lbfgsb[StsCtx](ar, &ctx, sts_f, sts_g, par, lo, up, 1.0e7f64, 0.0f64, 5usize, 100usize)
    i = 0usize
    while i < np {
        vm[i * p + i] = par[i] * vx
        i += 1usize
    }
    let model = kal.SsModel{ p: p, tm: tm, zv: zv, h: par[np] * vx, vm: vm, av: av, pm: pm, pn: pn }
    ret (model, ok)
}
