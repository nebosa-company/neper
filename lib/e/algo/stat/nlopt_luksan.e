// The Luksan-Vlcek limited-memory methods of NLopt 2.10.0 (algs/luksan): NLOPT_LD_LBFGS (plis), ported statement for
// statement so iterates, evaluation counts and return codes match nloptr. Variable metric and truncated Newton are
// in nlopt_luksan_vm.e.
//
// Vectors are 0-based here; the Fortran-style 1-based index of the C is index - 1. A bound type ix: 0 free, 1 lower,
// 2 upper, 3 both, 5 fixed; a negative value marks the variable active at that bound.

use e.math
use e.mem
use e.algo.stat.nlopt as nl

type Lk = struct {
    nf: usize, n: usize, kbf: i64,
    x: []f64, ix: []i64, xl: []f64, xu: []f64, gf: []f64, s: []f64, xo: []f64, go: []f64, uo: []f64, vo: []f64,
    xm: []f64, xr: []f64, gr: []f64, so: []f64, gn: []f64, xs: []f64, gs: []f64, gm: []f64, par: f64, nn: usize, iterh: i64,
    r: f64, rp: f64, f: f64, fo: f64, fp: f64, p: f64, po: f64, pp: f64, minf_est: f64, maxf: f64, rmin: f64, rmax: f64,
    tols: f64, tolp: f64, par1: f64, par2: f64, ro: f64, dmax: f64, umax: f64, gmax: f64, tolg: f64,
    kd: i64, ld: i64, nit: i64, kit: i64, nred: i64, mred: i64, maxst: i64, iest: i64, inits: i64, iters: i64, kters: i64,
    mes: i64, isys: i64, iterm: i64, iold: i64, irest: i64, ites: i64, ires1: i64, ires2: i64,
    ntesx: i64, mtesx: i64, ntesf: i64, mtesf: i64, nfg: i64, mfg: i64, mit: i64,
    fl: f64, fu: f64, pl: f64, rl: f64, pu: f64, ru: f64, mes1: i64, mes2: i64, mes3: i64, mode: i64, mtyp: i64
}

fn imax(a: i64, b: i64) -> i64 {
    if a > b { ret a }
    ret b
}

fn imin(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}

fn iabs(a: i64) -> i64 {
    if a < 0i64 { ret 0i64 - a }
    ret a
}

fn mxvmax(n: usize, x: []const f64) -> f64 {
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m = nl.fmax(m, math.abs[f64](x[i]))
        i += 1usize
    }
    ret m
}

fn mxvine(n: usize, ix: []i64) {
    var i = 0usize
    while i < n {
        ix[i] = iabs(ix[i])
        i += 1usize
    }
}

fn mxvsav(n: usize, x: []f64, y: []f64) {
    var i = 0usize
    while i < n {
        let t = y[i]
        y[i] = x[i] - y[i]
        x[i] = t
        i += 1usize
    }
}

fn mxvlin(n: usize, a: f64, x: []const f64, b: f64, y: []const f64, z: []f64) {
    var i = 0usize
    while i < n {
        z[i] = a * x[i] + b * y[i]
        i += 1usize
    }
}

fn mxdcmu(n: usize, m: usize, a: []f64, alf: f64, x: []const f64, y: []const f64) {
    var k = 0usize
    var j = 0usize
    while j < m {
        let t = alf * y[j]
        var i = 0usize
        while i < n {
            a[k + i] += t * x[i]
            i += 1usize
        }
        k += n
        j += 1usize
    }
}

fn mxdcmv(n: usize, m: usize, a: []f64, alf: f64, x: []const f64, u: []const f64, bet: f64, y: []const f64, v: []const f64) {
    var k = 0usize
    var j = 0usize
    while j < m {
        let ta = alf * u[j]
        let tb = bet * v[j]
        var i = 0usize
        while i < n {
            a[k + i] = a[k + i] + ta * x[i] + tb * y[i]
            i += 1usize
        }
        k += n
        j += 1usize
    }
}

fn mxvdir(n: usize, a: f64, x: []const f64, y: []const f64, z: []f64) {
    var i = 0usize
    while i < n {
        z[i] = y[i] + a * x[i]
        i += 1usize
    }
}

fn mxvscl(n: usize, a: f64, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = a * x[i]
        i += 1usize
    }
}

fn mxvcop(n: usize, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = x[i]
        i += 1usize
    }
}

fn mxvdif(n: usize, x: []const f64, y: []const f64, z: []f64) {
    var i = 0usize
    while i < n {
        z[i] = x[i] - y[i]
        i += 1usize
    }
}

fn mxvneg(n: usize, x: []const f64, y: []f64) {
    var i = 0usize
    while i < n {
        y[i] = 0.0f64 - x[i]
        i += 1usize
    }
}

fn mxvset(n: usize, a: f64, x: []f64) {
    var i = 0usize
    while i < n {
        x[i] = a
        i += 1usize
    }
}

fn mxvdot(n: usize, x: []const f64, y: []const f64) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        t += x[i] * y[i]
        i += 1usize
    }
    ret t
}

fn mxudot(n: usize, x: []const f64, y: []const f64, ix: []const i64, job: i64) -> f64 {
    var t = 0.0f64
    var i = 0usize
    while i < n {
        if job == 0i64 {
            t += x[i] * y[i]
        } else if job > 0i64 {
            if ix[i] >= 0i64 { t += x[i] * y[i] }
        } else {
            if ix[i] != 0i64 - 5i64 { t += x[i] * y[i] }
        }
        i += 1usize
    }
    ret t
}

fn mxudir(n: usize, a: f64, x: []const f64, y: []const f64, z: []f64, ix: []const i64, job: i64) {
    var i = 0usize
    while i < n {
        if job == 0i64 {
            z[i] = y[i] + a * x[i]
        } else if job > 0i64 {
            if ix[i] >= 0i64 { z[i] = y[i] + a * x[i] }
        } else {
            if ix[i] != 0i64 - 5i64 { z[i] = y[i] + a * x[i] }
        }
        i += 1usize
    }
}

fn mxuneg(n: usize, x: []const f64, y: []f64, ix: []const i64, job: i64) {
    var i = 0usize
    while i < n {
        if job == 0i64 {
            y[i] = 0.0f64 - x[i]
        } else if job > 0i64 {
            if ix[i] >= 0i64 {
                y[i] = 0.0f64 - x[i]
            } else {
                y[i] = 0.0f64
            }
        } else {
            if ix[i] != 0i64 - 5i64 {
                y[i] = 0.0f64 - x[i]
            } else {
                y[i] = 0.0f64
            }
        }
        i += 1usize
    }
}

fn mxucop(n: usize, x: []const f64, y: []f64, ix: []const i64, job: i64) {
    var i = 0usize
    while i < n {
        if job == 0i64 {
            y[i] = x[i]
        } else if job > 0i64 {
            if ix[i] >= 0i64 {
                y[i] = x[i]
            } else {
                y[i] = 0.0f64
            }
        } else {
            if ix[i] != 0i64 - 5i64 {
                y[i] = x[i]
            } else {
                y[i] = 0.0f64
            }
        }
        i += 1usize
    }
}

fn mxuzer(n: usize, x: []f64, ix: []const i64, job: i64) {
    if job == 0i64 { ret }
    var i = 0usize
    while i < n {
        if ix[i] < 0i64 { x[i] = 0.0f64 }
        i += 1usize
    }
}

fn mxdrmm(n: usize, m: usize, a: []const f64, x: []const f64, y: []f64) {
    var k = 0usize
    var j = 0usize
    while j < m {
        var t = 0.0f64
        var i = 0usize
        while i < n {
            t += a[k + i] * x[i]
            i += 1usize
        }
        y[j] = t
        k += n
        j += 1usize
    }
}

fn mxdcmd(n: usize, m: usize, a: []const f64, x: []const f64, alf: f64, y: []const f64, z: []f64) {
    mxvscl(n, alf, y, z)
    var k = 0usize
    var j = 0usize
    while j < m {
        mxvdir(n, x[j], a[k..a.len], z, z)
        k += n
        j += 1usize
    }
}

fn mxdrcb(n: usize, m: usize, a: []const f64, b: []const f64, u: []const f64, v: []f64, x: []f64, ix: []const i64, job: i64) {
    var k = 0usize
    var i = 0usize
    while i < m {
        v[i] = u[i] * mxudot(n, x, a[k..a.len], ix, job)
        mxudir(n, 0.0f64 - v[i], b[k..b.len], x, x, ix, job)
        k += n
        i += 1usize
    }
}

fn mxdrcf(n: usize, m: usize, a: []const f64, b: []const f64, u: []const f64, v: []const f64, x: []f64, ix: []const i64, job: i64) {
    var k = (m - 1usize) * n
    var i = m
    while i >= 1usize {
        let t = u[i - 1usize] * mxudot(n, x, b[k..b.len], ix, job)
        mxudir(n, v[i - 1usize] - t, a[k..a.len], x, x, ix, job)
        if i > 1usize { k -= n }
        i -= 1usize
    }
}

fn mxdrsu(n: usize, m: usize, a: []f64, b: []f64, u: []f64) {
    var k = (m - 1usize) * n
    var i = m - 1usize
    while i >= 1usize {
        let l = k - n
        mxvcop(n, a[l..l + n], a[k..k + n])
        mxvcop(n, b[l..l + n], b[k..k + n])
        u[i] = u[i - 1usize]
        k = l
        i -= 1usize
    }
}

fn pcbs04(w: *Lk, eps9: f64) {
    if w.kbf > 0i64 {
        var i = 0usize
        while i < w.nf {
            let ixi = iabs(w.ix[i])
            if (ixi == 1i64 || ixi == 3i64 || ixi == 4i64) && w.x[i] <= w.xl[i] + eps9 * nl.fmax(math.abs[f64](w.xl[i]), 1.0f64) {
                w.x[i] = w.xl[i]
            }
            if (ixi == 2i64 || ixi == 3i64 || ixi == 4i64) && w.x[i] >= w.xu[i] - eps9 * nl.fmax(math.abs[f64](w.xu[i]), 1.0f64) {
                w.x[i] = w.xu[i]
            }
            i += 1usize
        }
    }
}

// interpolation step of the line search; leaves w.r unchanged when no type applies
fn pnint1(w: *Lk, merr: *i64) {
    *merr = 0i64
    if w.mode <= 0i64 { ret }
    if w.pl >= 0.0f64 {
        *merr = 2i64
        ret
    } else if w.ru <= w.rl {
        *merr = 3i64
        ret
    }
    var a = 0.0f64
    var b = 0.0f64
    var den = 0.0f64
    var ntyp = w.mtyp
    while ntyp >= 1i64 {
        if ntyp == 1i64 {
            if w.mode == 1i64 {
                w.r = w.ru * 4.0f64
            } else {
                w.r = (w.rl + w.ru) * 0.5f64
            }
            ret
        } else if ntyp == w.mtyp {
            a = (w.fu - w.fl) / (w.pl * (w.ru - w.rl))
            b = w.pu / w.pl
        }
        var skip = false
        if ntyp == 2i64 {
            den = (1.0f64 - a) * 2.0f64
        } else if ntyp == 3i64 {
            den = 1.0f64 - b
        } else if ntyp == 4i64 {
            let c = b - a * 2.0f64 + 1.0f64
            let d = b - a * 3.0f64 + 2.0f64
            let dis = d * d - c * 3.0f64
            if dis < 0.0f64 {
                skip = true
            } else {
                den = d + math.sqrt[f64](dis)
            }
        } else if ntyp == 5i64 {
            let dis = a * a - b
            if dis < 0.0f64 {
                skip = true
            } else {
                den = a + math.sqrt[f64](dis)
                if den <= 0.0f64 {
                    skip = true
                } else {
                    let d1 = 1.0f64 / den
                    den = 1.0f64 - b * (d1 * (d1 * d1))
                }
            }
        }
        if !skip {
            if w.mode == 1i64 && den > 0.0f64 && den < 1.0f64 {
                w.r = w.rl + (w.ru - w.rl) / den
                w.r = nl.fmax(w.r, w.ru * 1.1f64)
                w.r = nl.fmin(w.r, w.ru * 1.0e3f64)
                ret
            } else if w.mode == 2i64 && den > 1.0f64 {
                w.r = w.rl + (w.ru - w.rl) / den
                if w.rl == 0.0f64 {
                    w.r = nl.fmax(w.r, w.rl + (w.ru - w.rl) * 0.01f64)
                } else {
                    w.r = nl.fmax(w.r, w.rl + (w.ru - w.rl) * 0.1f64)
                }
                w.r = nl.fmin(w.r, w.rl + (w.ru - w.rl) * 0.9f64)
                ret
            }
        }
        ntyp -= 1i64
    }
}

// the line search as a coroutine: isys 0 on entry starts, 1 resumes after the caller evaluated f and p at w.r
fn ps1l01(w: *Lk) {
    var pc = 2i64
    if w.isys != 1i64 {
        pc = 0i64
    } else {
        pc = 3i64
    }
    var l1 = false
    var l2 = false
    var l3 = false
    var l5 = false
    var l7 = false
    var m1 = false
    var m2 = false
    var m3 = false
    while true {
        if pc == 0i64 {
            w.mes1 = 2i64
            w.mes2 = 2i64
            w.mes3 = 2i64
            w.iters = 0i64
            if w.po >= 0.0f64 {
                w.r = 0.0f64
                w.iters = 0i64 - 2i64
                w.isys = 0i64
                ret
            }
            if w.rmax <= 0.0f64 {
                w.iters = 0i64
                w.isys = 0i64
                ret
            }
            var rtemp = 0.0f64
            if w.inits > 0i64 {
                rtemp = w.minf_est - w.f
            } else if w.iest == 0i64 {
                rtemp = w.f - w.fp
            } else {
                rtemp = nl.fmax(w.f - w.fp, w.minf_est - w.f)
            }
            let init1 = iabs(w.inits)
            w.rp = 0.0f64
            w.fp = w.fo
            w.pp = w.po
            if init1 == 0i64 {
            } else if init1 == 1i64 || (w.inits >= 1i64 && w.iest == 0i64) {
                w.r = 1.0f64
            } else if init1 == 2i64 {
                w.r = nl.fmin(1.0f64, rtemp * 4.0f64 / w.po)
            } else if init1 == 3i64 {
                w.r = nl.fmin(1.0f64, rtemp * 2.0f64 / w.po)
            } else if init1 == 4i64 {
                w.r = rtemp * 2.0f64 / w.po
            }
            w.r = nl.fmax(w.r, w.rmin)
            w.r = nl.fmin(w.r, w.rmax)
            w.mode = 0i64
            w.ru = 0.0f64
            w.fu = w.fo
            w.pu = w.po
            pc = 2i64
        }
        if pc == 2i64 {
            var merr = 0i64
            pnint1(w, &merr)
            if merr > 0i64 {
                w.iters = 0i64 - merr
                w.isys = 0i64
                ret
            } else if w.mode == 1i64 {
                w.nred -= 1i64
                w.r = nl.fmin(w.r, w.rmax)
            } else if w.mode == 2i64 {
                w.nred += 1i64
            }
            w.kd = 1i64
            w.ld = 0i64 - 1i64
            w.isys = 1i64
            ret
        }
        // pc == 3
        if w.mode == 0i64 {
            w.par1 = w.p / w.po
            w.par2 = w.f - w.fo
        }
        if w.iters != 0i64 {
            w.isys = 0i64
            ret
        }
        if w.f <= w.minf_est {
            w.iters = 7i64
            w.isys = 0i64
            ret
        } else {
            l1 = w.r <= w.rmin && w.nit != w.kit
            l2 = w.r >= w.rmax
            l3 = w.f - w.fo <= w.tols * w.r * w.po
            l5 = w.p >= w.tolp * w.po || (w.mes2 == 2i64 && w.mode == 2i64)
            l7 = w.mes2 <= 2i64 || w.mode != 0i64
            m1 = false
            m2 = false
            m3 = l3
            if w.mes3 >= 1i64 {
                m1 = math.abs[f64](w.p) <= math.abs[f64](w.po) * 0.01f64 && w.fo - w.f >= math.abs[f64](w.fo) * 9.9999999999999994e-12f64
                l3 = l3 || m1
            }
            if w.mes3 >= 2i64 {
                m2 = math.abs[f64](w.p) <= math.abs[f64](w.po) * 0.5f64 && math.abs[f64](w.fo - w.f) <= math.abs[f64](w.fo) * 2.0000000000000001e-13f64
                l3 = l3 || m2
            }
            w.maxst = 0i64
            if l2 { w.maxst = 1i64 }
        }
        if l1 && !l3 {
            w.iters = 0i64
            w.isys = 0i64
            ret
        } else if l2 && l3 && !l5 {
            w.iters = 7i64
            w.isys = 0i64
            ret
        } else if m3 && w.mes1 == 3i64 {
            w.iters = 5i64
            w.isys = 0i64
            ret
        } else if l3 && l5 && l7 {
            w.iters = 4i64
            w.isys = 0i64
            ret
        } else if w.kters < 0i64 || (w.kters == 6i64 && l7) {
            w.iters = 6i64
            w.isys = 0i64
            ret
        } else if iabs(w.nred) >= w.mred {
            w.iters = 0i64 - 1i64
            w.isys = 0i64
            ret
        } else {
            w.rp = w.r
            w.fp = w.f
            w.pp = w.p
            w.mode = imax(w.mode, 1i64)
            w.mtyp = iabs(w.mes)
            if w.f >= w.maxf { w.mtyp = 1i64 }
        }
        if w.mode == 1i64 {
            w.rl = w.ru
            w.fl = w.fu
            w.pl = w.pu
            w.ru = w.r
            w.fu = w.f
            w.pu = w.p
            if !l3 {
                w.nred = 0i64
                w.mode = 2i64
            } else if w.mes1 == 1i64 {
                w.mtyp = 1i64
            }
        } else {
            if !l3 {
                w.ru = w.r
                w.fu = w.f
                w.pu = w.p
            } else {
                w.rl = w.r
                w.fl = w.f
                w.pl = w.p
            }
        }
        pc = 2i64
    }
}

// elimination of bound violations after the active set changes; counts the free variables in w.n
fn pyadc0(w: *Lk) -> i64 {
    w.n = w.nf
    var inew = 0i64
    var i = 0usize
    while i < w.nf {
        let ii = w.ix[i]
        let ixi = iabs(ii)
        if ixi >= 5i64 {
            w.ix[i] = 0i64 - ixi
        } else if (ixi == 1i64 || ixi == 3i64 || ixi == 4i64) && w.x[i] <= w.xl[i] {
            w.x[i] = w.xl[i]
            if ixi == 4i64 {
                w.ix[i] = 0i64 - 3i64
            } else {
                w.ix[i] = 0i64 - ixi
            }
            w.n -= 1usize
            if ii > 0i64 { inew += 1i64 }
        } else if (ixi == 2i64 || ixi == 3i64 || ixi == 4i64) && w.x[i] >= w.xu[i] {
            w.x[i] = w.xu[i]
            if ixi == 3i64 {
                w.ix[i] = 0i64 - 4i64
            } else {
                w.ix[i] = 0i64 - ixi
            }
            w.n -= 1usize
            if ii > 0i64 { inew += 1i64 }
        }
        i += 1usize
    }
    ret inew
}

fn pyfut1(w: *Lk, stop: *nl.Stop, xstop: bool, n: usize) {
    if w.iterm < 0i64 { ret }
    var skip = false
    if w.ites <= 0i64 { skip = true }
    if !skip && w.iters == 0i64 { skip = true }
    if !skip {
        if w.nit <= 0i64 {
            w.fo = w.f + nl.fmin(math.sqrt[f64](math.abs[f64](w.f)), math.abs[f64](w.f) / 10.0f64)
        }
        if w.f <= stop.minf_max {
            w.iterm = 3i64
            ret
        }
        if w.kd > 0i64 {
            if w.gmax <= w.tolg && w.umax <= w.tolg {
                w.iterm = 4i64
                ret
            }
        }
        if w.nit <= 0i64 {
            w.ntesx = 0i64
            w.ntesf = 0i64
        }
        if xstop {
            w.iterm = 1i64
            w.ntesx += 1i64
            if w.ntesx >= w.mtesx { ret }
        } else {
            w.ntesx = 0i64
        }
        if nl.stop_ftol(stop, w.f, w.fo) {
            w.iterm = 2i64
            w.ntesf += 1i64
            if w.ntesf >= w.mtesf { ret }
        } else {
            w.ntesf = 0i64
        }
    }
    if w.nit >= w.mit {
        w.iterm = 11i64
        ret
    }
    if nl.stop_evals(stop) {
        w.iterm = 12i64
        ret
    }
    if w.nfg >= w.mfg {
        w.iterm = 13i64
        ret
    }
    w.iterm = 0i64
    if n > 0usize && w.nit - w.kit >= w.ires1 * i64(n) + w.ires2 { w.irest = imax(w.irest, 1i64) }
    w.nit += 1i64
}

fn pyrmc0(w: *Lk, g: []const f64, eps8: f64) {
    if w.n == 0usize || w.rmax > 0.0f64 {
        if w.umax > eps8 * w.gmax {
            w.iold = 0i64
            var i = 0usize
            var stopped = false
            while i < w.nf && !stopped {
                let ixi = w.ix[i]
                if ixi >= 0i64 {
                } else if ixi <= 0i64 - 5i64 {
                } else if (ixi == 0i64 - 1i64 || ixi == 0i64 - 3i64) && 0.0f64 - g[i] <= 0.0f64 {
                } else if (ixi == 0i64 - 2i64 || ixi == 0i64 - 4i64) && g[i] <= 0.0f64 {
                } else {
                    w.iold += 1i64
                    w.ix[i] = imin(iabs(w.ix[i]), 3i64)
                    if w.rmax == 0.0f64 { stopped = true }
                }
                i += 1usize
            }
            if w.iold > 1i64 { w.irest = imax(w.irest, 1i64) }
        }
    }
}

fn pytrcd(w: *Lk) {
    let nf = w.nf
    if w.iters > 0i64 {
        mxvdif(nf, w.x, w.xo, w.xo)
        mxvdif(nf, w.gf, w.go, w.go)
        w.po = w.r * w.po
        w.p = w.r * w.p
    } else {
        w.f = w.fo
        w.p = w.po
        mxvsav(nf, w.x, w.xo)
        mxvsav(nf, w.gf, w.go)
        w.ld = w.kd
    }
    w.dmax = 0.0f64
    var i = 0usize
    while i < nf {
        var fixed = false
        if w.kbf > 0i64 {
            if w.ix[i] < 0i64 {
                w.xo[i] = 0.0f64
                w.go[i] = 0.0f64
                fixed = true
            }
        }
        if !fixed {
            w.dmax = nl.fmax(w.dmax, math.abs[f64](w.xo[i]) / nl.fmax(math.abs[f64](w.x[i]), 1.0f64))
        }
        i += 1usize
    }
}

fn pytrcg(w: *Lk) {
    if w.kbf > 0i64 {
        w.gmax = 0.0f64
        w.umax = 0.0f64
        w.iold = 0i64
        var i = 0usize
        while i < w.nf {
            let temp = w.gf[i]
            if w.ix[i] >= 0i64 {
                w.gmax = nl.fmax(w.gmax, math.abs[f64](temp))
            } else if w.ix[i] <= 0i64 - 5i64 {
            } else if (w.ix[i] == 0i64 - 1i64 || w.ix[i] == 0i64 - 3i64) && w.umax + temp >= 0.0f64 {
            } else if (w.ix[i] == 0i64 - 2i64 || w.ix[i] == 0i64 - 4i64) && w.umax - temp >= 0.0f64 {
            } else {
                w.iold = i64(i) + 1i64
                w.umax = math.abs[f64](temp)
            }
            i += 1usize
        }
    } else {
        w.umax = 0.0f64
        w.gmax = mxvmax(w.nf, w.gf)
    }
}

fn pytrcs(w: *Lk, eta9: f64) {
    let nf = w.nf
    w.fp = w.fo
    w.ro = 0.0f64
    w.fo = w.f
    w.po = w.p
    mxvcop(nf, w.x, w.xo)
    mxvcop(nf, w.gf, w.go)
    if w.kbf > 0i64 {
        var i = 0usize
        while i < nf {
            if w.ix[i] < 0i64 {
                w.s[i] = 0.0f64
            } else {
                if w.ix[i] == 1i64 || w.ix[i] >= 3i64 {
                    if w.s[i] < 0.0f64 - 1.0f64 / eta9 { w.rmax = nl.fmin(w.rmax, (w.xl[i] - w.x[i]) / w.s[i]) }
                }
                if w.ix[i] == 2i64 || w.ix[i] >= 3i64 {
                    if w.s[i] > 1.0f64 / eta9 { w.rmax = nl.fmin(w.rmax, (w.xu[i] - w.x[i]) / w.s[i]) }
                }
            }
            i += 1usize
        }
    }
}

// the common set-up of plis, plip and pnet; the three differ in tolerances' use only through stop
fn lk_new(ar: *mem.Arena, n: usize, lb: []const f64, ub: []const f64, x: []f64, mf: usize, tolg: f64, nvec: usize) -> (Lk, bool) {
    let (xl, e1) = mem.alloc[f64](ar, n + 1usize)
    let (xu, e2) = mem.alloc[f64](ar, n + 1usize)
    let (gf, e3) = mem.alloc[f64](ar, n + 1usize)
    let (s, e4) = mem.alloc[f64](ar, n + 1usize)
    let (xo, e5) = mem.alloc[f64](ar, n * nvec + n + 1usize)
    let (go, e6) = mem.alloc[f64](ar, n * nvec + n + 1usize)
    let (uo, e7) = mem.alloc[f64](ar, nvec + n + 1usize)
    let (vo, e8) = mem.alloc[f64](ar, nvec + n + 1usize)
    let (ix, e9) = mem.alloc[i64](ar, n + 1usize)
    let (xm, e10) = mem.alloc[f64](ar, n * nvec + n + 1usize)
    let (xr, e11) = mem.alloc[f64](ar, nvec + n + 1usize)
    let (gr, e12) = mem.alloc[f64](ar, nvec + n + 1usize)
    let (so, e13) = mem.alloc[f64](ar, n + 1usize)
    let (gn, e14) = mem.alloc[f64](ar, n + 1usize)
    let (xs, e15) = mem.alloc[f64](ar, n + 1usize)
    let (gs, e16) = mem.alloc[f64](ar, n + 1usize)
    let (gm, e17) = mem.alloc[f64](ar, n * nvec + n + 1usize)
    var w = Lk {
        nf: n, n: n, kbf: 0i64, x: x, ix: ix, xl: xl, xu: xu, gf: gf, s: s, xo: xo, go: go, uo: uo, vo: vo, xm: xm, xr: xr, gr: gr, so: so, gn: gn, xs: xs, gs: gs, gm: gm, par: 1.0f64, nn: 0usize, iterh: 0i64,
        r: 0.0f64, rp: 0.0f64, f: 0.0f64, fo: 0.0f64, fp: 0.0f64, p: 0.0f64, po: 0.0f64, pp: 0.0f64, minf_est: 0.0f64, maxf: 0.0f64, rmin: 0.0f64, rmax: 0.0f64,
        tols: 0.0f64, tolp: 0.0f64, par1: 0.0f64, par2: 0.0f64, ro: 0.0f64, dmax: 0.0f64, umax: 0.0f64, gmax: 0.0f64, tolg: tolg,
        kd: 0i64, ld: 0i64, nit: 0i64, kit: 0i64, nred: 0i64, mred: 0i64, maxst: 0i64, iest: 0i64, inits: 0i64, iters: 0i64, kters: 0i64,
        mes: 0i64, isys: 0i64, iterm: 0i64, iold: 0i64, irest: 0i64, ites: 0i64, ires1: 0i64, ires2: 0i64,
        ntesx: 0i64, mtesx: 0i64, ntesf: 0i64, mtesf: 0i64, nfg: 0i64, mfg: 0i64, mit: 0i64,
        fl: 0.0f64, fu: 0.0f64, pl: 0.0f64, rl: 0.0f64, pu: 0.0f64, ru: 0.0f64, mes1: 0i64, mes2: 0i64, mes3: 0i64, mode: 0i64, mtyp: 0i64
    }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret (w, false) }
    var i = 0usize
    while i < n {
        let lbu = lb[i] <= 0.0f64 - 1.7976931348623157e308f64 * 0.99f64
        let ubu = ub[i] >= 1.7976931348623157e308f64 * 0.99f64
        if lbu {
            if ubu {
                ix[i] = 0i64
            } else {
                ix[i] = 2i64
            }
        } else if ubu {
            ix[i] = 1i64
        } else if lb[i] == ub[i] {
            ix[i] = 5i64
        } else {
            ix[i] = 3i64
        }
        xl[i] = lb[i]
        xu[i] = ub[i]
        i += 1usize
    }
    i = 0usize
    while i < n * nvec + n {
        xo[i] = 0.0f64
        i += 1usize
    }
    ret (w, true)
}

// the shared initiation of the three drivers: constants, the simple-bounds set-up and the first evaluation
fn lk_init(w: *Lk, stop: *nl.Stop) {
    w.kbf = 2i64
    w.ites = 1i64
    w.mtesx = 2i64
    w.mtesf = 2i64
    w.inits = 2i64
    w.iterm = 0i64
    w.iters = 2i64
    w.kters = 3i64
    w.irest = 0i64
    w.ires1 = 999i64
    w.ires2 = 0i64
    w.mred = 10i64
    w.mes = 4i64
    w.iest = 0i64
    w.rmax = 1.0e120f64
    w.maxf = 1.0e20f64
    w.minf_est = 0.0f64 - nl.inf()
    if w.tolg <= 0.0f64 { w.tolg = 1.0e-8f64 }
    w.tols = 1.0e-4f64
    w.tolp = 0.8f64
    w.mit = 2147483647i64
    w.mfg = stop.maxeval
    if w.mfg <= 0i64 { w.mfg = 2147483647i64 }
    w.kd = 1i64
    w.ld = 0i64 - 1i64
    w.kit = 0i64 - (w.ires1 * i64(w.nf) + w.ires2)
    w.fo = w.minf_est
    var i = 0usize
    while i < w.nf {
        if (w.ix[i] == 3i64 || w.ix[i] == 4i64) && w.xu[i] <= w.xl[i] {
            w.xu[i] = w.xl[i]
            w.ix[i] = 5i64
        } else if w.ix[i] == 5i64 || w.ix[i] == 6i64 {
            w.xl[i] = w.x[i]
            w.xu[i] = w.x[i]
            w.ix[i] = 5i64
        }
        i += 1usize
    }
    pcbs04(w, 1.0e-8f64)
    let _inew = pyadc0(w)
}

fn lk_code(iterm: i64) -> i64 {
    if iterm == 1i64 { ret nl.XTOL_REACHED }
    if iterm == 2i64 { ret nl.FTOL_REACHED }
    if iterm == 3i64 { ret nl.STOPVAL_REACHED }
    if iterm == 4i64 || iterm == 6i64 { ret nl.SUCCESS }
    if iterm == 12i64 || iterm == 13i64 { ret nl.MAXEVAL_REACHED }
    if iterm == 0i64 - 999i64 { ret 0i64 - 5i64 }
    ret nl.FAILURE
}

// NLOPT_LD_LBFGS. mf is the number of stored correction pairs (nloptr's vector_storage); x is the start and the answer.
fn lbfgs[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ctx: *C, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop, mf0: usize, tolg: f64) -> (f64, i64) {
    let n = x.len
    var mf = mf0
    if mf == 0usize {
        mf = 1310720usize / n
        if mf < 10usize { mf = 10usize }
        if stop.maxeval > 0i64 && stop.maxeval <= i64(mf) {
            mf = usize(stop.maxeval)
            if mf < 1usize { mf = 1usize }
        }
    }
    let nvec = mf
    var mfn = nvec
    if mfn < 1usize { mfn = 1usize }
    let (w, okk) = lk_new(ar, n, lb, ub, x, mf, tolg, mfn)
    if !okk { ret (0.0f64, nl.OUT_OF_MEMORY) }
    var lw = w
    let wp = &lw
    lk_init(wp, stop)
    let eta9 = 1.0e120f64
    let eps8 = 1.0f64
    let eps9 = 1.0e-8f64
    let alf1 = 1.0e-10f64
    let alf2 = 1.0e10f64
    let told = 1.0e-4f64
    var xstop = false
    var gnorm = 0.0f64
    var snorm = 0.0f64
    var kk = 0i64
    var a = 0.0f64
    var b = 0.0f64
    wp.f = f(ctx, wp.x, wp.gf)
    stop.nevals += 1i64
    wp.nfg += 1i64
    // L11120 .. L11175 as one loop
    var stage = 0i64
    while wp.iterm == 0i64 {
        if stage == 0i64 {
            pytrcg(wp)
            pyfut1(wp, stop, xstop, wp.nf)
            if wp.iterm != 0i64 { break }
            if wp.kbf > 0i64 && wp.rmax > 0.0f64 { pyrmc0(wp, wp.gf, eps8) }
            stage = 1i64
        }
        // L11130: direction determination
        gnorm = math.sqrt[f64](mxudot(wp.nf, wp.gf, wp.gf, wp.ix, wp.kbf))
        if wp.irest == 0i64 {
            kk = imin(wp.nit - wp.kit, i64(mf))
            if kk <= 0i64 {
                wp.irest = imax(wp.irest, 1i64)
            } else {
                b = mxudot(wp.nf, wp.xo, wp.go, wp.ix, wp.kbf)
                if b <= 0.0f64 {
                    wp.irest = imax(wp.irest, 1i64)
                } else {
                    wp.uo[0usize] = 1.0f64 / b
                    mxuneg(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf)
                    mxdrcb(wp.nf, usize(kk), wp.xo, wp.go, wp.uo, wp.vo, wp.s, wp.ix, wp.kbf)
                    a = mxudot(wp.nf, wp.go, wp.go, wp.ix, wp.kbf)
                    if a > 0.0f64 { mxvscl(wp.nf, b / a, wp.s, wp.s) }
                    mxdrcf(wp.nf, usize(kk), wp.xo, wp.go, wp.uo, wp.vo, wp.s, wp.ix, wp.kbf)
                    snorm = math.sqrt[f64](mxudot(wp.nf, wp.s, wp.s, wp.ix, wp.kbf))
                    kk = imin(kk + 1i64, i64(mf))
                    mxdrsu(wp.nf, usize(kk), wp.xo, wp.go, wp.uo)
                }
            }
        }
        if wp.irest != 0i64 {
            mxuneg(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf)
            snorm = gnorm
            if wp.kit < wp.nit {
                wp.kit = wp.nit
            } else {
                wp.iterm = 0i64 - 10i64
                if wp.iters < 0i64 { wp.iterm = wp.iters - 5i64 }
            }
        }
        if wp.kd > 0i64 { wp.p = mxudot(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf) }
        if snorm <= 0.0f64 {
            wp.irest = imax(wp.irest, 1i64)
        } else if wp.p + told * gnorm * snorm <= 0.0f64 {
            wp.irest = 0i64
        } else {
            wp.irest = imax(wp.irest, 1i64)
        }
        if wp.irest == 0i64 {
            wp.nred = 0i64
            wp.rmin = alf1 * gnorm / snorm
            wp.rmax = nl.fmin(alf2 * gnorm / snorm, 1.0e16f64 / snorm)
        }
        if wp.iterm != 0i64 { break }
        if wp.irest != 0i64 {
            stage = 1i64
        } else {
            pytrcs(wp, eta9)
            if wp.rmax != 0.0f64 {
                var searching = true
                while searching {
                    ps1l01(wp)
                    if wp.isys == 0i64 {
                        searching = false
                    } else {
                        mxudir(wp.nf, wp.r, wp.s, wp.xo, wp.x, wp.ix, wp.kbf)
                        pcbs04(wp, eps9)
                        wp.f = f(ctx, wp.x, wp.gf)
                        stop.nevals += 1i64
                        wp.nfg += 1i64
                        wp.p = mxudot(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf)
                    }
                }
                if wp.iters <= 0i64 {
                    wp.r = 0.0f64
                    wp.f = wp.fo
                    wp.p = wp.po
                    mxvcop(wp.nf, wp.xo, wp.x)
                    mxvcop(wp.nf, wp.go, wp.gf)
                    wp.irest = imax(wp.irest, 1i64)
                    wp.ld = wp.kd
                    stage = 1i64
                } else {
                    pytrcd(wp)
                    xstop = nl.stop_dx(stop, wp.x, wp.xo)
                    stage = 0i64
                }
            } else {
                stage = 0i64
            }
            if stage == 0i64 {
                if wp.kbf > 0i64 {
                    mxvine(wp.nf, wp.ix)
                    let _i2 = pyadc0(wp)
                }
            }
        }
    }
    ret (wp.f, lk_code(wp.iterm))
}

// shifted rank-one (met 1) or rank-two (met 2) variable-metric update, the first mf steps (pulsp3)
fn pulsp3(w: *Lk, mf: usize, met3: i64) {
    let n = w.nf
    let m = w.nn
    if m >= mf { ret }
    var b = mxvdot(n, w.xo, w.go)
    if b <= 0.0f64 {
        w.iterh = 0i64
        ret
    }
    mxdrmm(n, m, w.xm, w.go, w.gr)
    let ah = mxvdot(n, w.go, w.go)
    let aa = mxvdot(m, w.gr, w.gr)
    let a = aa + ah * w.par
    let par = 1.0f64
    var pom = b / ah
    if a > 0.0f64 {
        let den = mxvdot(n, w.xo, w.xo)
        if met3 <= 4i64 {
            w.par = math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - aa / a)) / (math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - b * b / (den * ah))) + 1.0f64) * pom
        } else {
            w.par = math.sqrt[f64](nl.fmax(0.0f64, w.par * ah / a)) / (math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - b * b / (den * ah))) + 1.0f64) * pom
        }
        w.par = nl.fmax(w.par, pom * 0.2f64)
        w.par = nl.fmin(w.par, pom * 0.8f64)
    } else {
        w.par = pom * 0.25f64
    }
    let bb = b - ah * w.par
    mxvdir(n, 0.0f64 - w.par, w.go, w.xo, w.xo)
    pom = 1.0f64
    mxdcmu(n, m, w.xm, 0.0f64 - 1.0f64 / bb, w.xo, w.gr)
    mxvscl(n, math.sqrt[f64](par / bb), w.xo, w.xm[n * m..w.xm.len])
    w.nn += 1usize
    w.iterh = 0i64
}

fn pulvp3(w: *Lk, met2: i64, met3: i64, met5: i64) {
    let n = w.nf
    let m = w.nn
    let zet = w.par
    var b = mxvdot(n, w.xo, w.go)
    if b <= 0.0f64 {
        w.iterh = 0i64
        ret
    }
    mxdrmm(n, m, w.xm, w.go, w.gr)
    mxvscl(n, w.r, w.s, w.s)
    mxdrmm(n, m, w.xm, w.s, w.xr)
    mxvdir(n, 0.0f64 - w.par, w.s, w.xo, w.so)
    let ah = mxvdot(n, w.go, w.go)
    let aa = mxvdot(m, w.gr, w.gr)
    let bb = mxvdot(m, w.gr, w.xr)
    let cc = mxvdot(m, w.xr, w.xr)
    let a = aa + ah * w.par
    var pom = b / ah
    if a > 0.0f64 {
        let den = mxvdot(n, w.xo, w.xo)
        if met3 <= 4i64 {
            w.par = math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - aa / a)) / (math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - b * b / (den * ah))) + 1.0f64) * pom
        } else {
            w.par = math.sqrt[f64](nl.fmax(0.0f64, w.par * ah / a)) / (math.sqrt[f64](nl.fmax(0.0f64, 1.0f64 - b * b / (den * ah))) + 1.0f64) * pom
        }
        w.par = nl.fmax(w.par, pom * 0.2f64)
        w.par = nl.fmin(w.par, pom * 0.8f64)
    } else {
        w.par = pom * 0.25f64
    }
    b -= ah * w.par
    mxvdir(n, 0.0f64 - w.par, w.go, w.xo, w.xo)
    var par = 0.0f64
    if met2 <= 1i64 {
        par = 1.0f64
    } else if met2 == 2i64 {
        par = w.par * ah / b
    } else if met2 == 3i64 {
        par = math.sqrt[f64](1.0f64 - aa / a)
    } else if met2 == 4i64 {
        par = math.sqrt[f64](math.sqrt[f64](1.0f64 - aa / a) * (w.par * ah / b))
    } else {
        par = zet / (zet + w.par)
    }
    pom = math.copysign[f64](math.sqrt[f64](par * b / cc), bb)
    if met5 == 1i64 {
        mxvdir(m, pom, w.xr, w.gr, w.xr)
        mxvlin(n, par, w.xo, pom, w.so, w.s)
        mxdcmu(n, m, w.xm, 0.0f64 - 1.0f64 / (par * b + pom * bb), w.s, w.xr)
    } else {
        mxvdir(n, par / pom - bb / b, w.xo, w.so, w.s)
        mxdcmv(n, m, w.xm, 0.0f64 - 1.0f64 / b, w.xo, w.gr, 0.0f64 - 1.0f64 / cc, w.s, w.xr)
    }
    w.iterh = 0i64
}

// NLOPT_LD_VAR1 (met 1) and NLOPT_LD_VAR2 (met 2): shifted limited-memory variable metric
fn varmetric[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ctx: *C, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop, mf0: usize, met: i64, tolg: f64) -> (f64, i64) {
    let n = x.len
    var mf = mf0
    if mf == 0usize {
        mf = 1310720usize / n
        if mf < 10usize { mf = 10usize }
        if stop.maxeval > 0i64 && stop.maxeval <= i64(mf) {
            mf = usize(stop.maxeval)
            if mf < 1usize { mf = 1usize }
        }
    }
    let (w, okk) = lk_new(ar, n, lb, ub, x, mf, tolg, mf + 1usize)
    if !okk { ret (0.0f64, nl.OUT_OF_MEMORY) }
    var lw = w
    let wp = &lw
    lk_init(wp, stop)
    wp.tolp = 0.9f64
    let met3 = 4i64
    let mec = 4i64
    let eta9 = 1.0e120f64
    let eps8 = 1.0f64
    let eps9 = 1.0e-8f64
    let alf1 = 1.0e-10f64
    let alf2 = 1.0e10f64
    let told = 1.0e-4f64
    var xstop = false
    var gnorm = 0.0f64
    var snorm = 0.0f64
    wp.f = f(ctx, wp.x, wp.gf)
    stop.nevals += 1i64
    wp.nfg += 1i64
    var stage = 0i64
    while wp.iterm == 0i64 {
        if stage == 0i64 {
            pytrcg(wp)
            pyfut1(wp, stop, xstop, wp.nf)
            if wp.iterm != 0i64 { break }
            if wp.kbf > 0i64 && wp.rmax > 0.0f64 { pyrmc0(wp, wp.gf, eps8) }
            stage = 1i64
        }
        // L11130
        if wp.irest > 0i64 {
            wp.nn = 0usize
            wp.par = 1.0f64
            wp.ld = imin(wp.ld, 1i64)
            if wp.kit < wp.nit {
                wp.kit = wp.nit
            } else {
                wp.iterm = 0i64 - 10i64
                if wp.iters < 0i64 { wp.iterm = wp.iters - 5i64 }
            }
        }
        if wp.iterm != 0i64 { break }
        gnorm = math.sqrt[f64](mxudot(wp.nf, wp.gf, wp.gf, wp.ix, wp.kbf))
        mxuneg(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf)
        mxdrmm(wp.nf, wp.nn, wp.xm, wp.s, wp.gr)
        mxdcmd(wp.nf, wp.nn, wp.xm, wp.gr, wp.par, wp.s, wp.s)
        mxuzer(wp.nf, wp.s, wp.ix, wp.kbf)
        snorm = math.sqrt[f64](mxudot(wp.nf, wp.s, wp.s, wp.ix, wp.kbf))
        if wp.kd > 0i64 { wp.p = mxudot(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf) }
        if snorm <= 0.0f64 {
            wp.irest = imax(wp.irest, 1i64)
        } else if wp.p + told * gnorm * snorm <= 0.0f64 {
            wp.irest = 0i64
        } else {
            wp.irest = imax(wp.irest, 1i64)
        }
        if wp.irest == 0i64 {
            wp.nred = 0i64
            wp.rmin = alf1 * gnorm / snorm
            wp.rmax = nl.fmin(alf2 * gnorm / snorm, 1.0e16f64 / snorm)
        }
        if wp.irest != 0i64 {
            stage = 1i64
        } else {
            pytrcs(wp, eta9)
            if wp.rmax != 0.0f64 {
                var searching = true
                while searching {
                    ps1l01(wp)
                    if wp.isys == 0i64 {
                        searching = false
                    } else {
                        mxudir(wp.nf, wp.r, wp.s, wp.xo, wp.x, wp.ix, wp.kbf)
                        pcbs04(wp, eps9)
                        wp.f = f(ctx, wp.x, wp.gf)
                        stop.nevals += 1i64
                        wp.nfg += 1i64
                        wp.p = mxudot(wp.nf, wp.gf, wp.s, wp.ix, wp.kbf)
                    }
                }
                if wp.iters <= 0i64 {
                    wp.r = 0.0f64
                    wp.f = wp.fo
                    wp.p = wp.po
                    mxvcop(wp.nf, wp.xo, wp.x)
                    mxvcop(wp.nf, wp.go, wp.gf)
                    wp.irest = imax(wp.irest, 1i64)
                    wp.ld = wp.kd
                    stage = 1i64
                } else {
                    mxuneg(wp.nf, wp.go, wp.s, wp.ix, wp.kbf)
                    pytrcd(wp)
                    xstop = nl.stop_dx(stop, wp.x, wp.xo)
                    mxucop(wp.nf, wp.gf, wp.so, wp.ix, wp.kbf)
                    if wp.nn < mf {
                        pulsp3(wp, mf, met3)
                    } else {
                        pulvp3(wp, mec, met3, met)
                    }
                    stage = 0i64
                }
            } else {
                stage = 0i64
            }
            if stage == 0i64 {
                if wp.iterh != 0i64 { wp.irest = imax(wp.irest, 1i64) }
                if wp.kbf > 0i64 {
                    let _i2 = pyadc0(wp)
                }
            }
        }
    }
    ret (wp.f, lk_code(wp.iterm))
}

type Memo[C: type] = struct { f: fn(*C, []const f64, []f64) -> f64, ctx: *C, lb: []const f64, ub: []const f64, minf: f64, bestx: []f64 }

// nlopt_optimize wraps the truncated-Newton and COBYLA objectives so the best feasible point ever evaluated is the answer
fn memo_fn[C: type](m: *Memo[C], x: []const f64, g: []f64) -> f64 {
    let v = m.f(m.ctx, x, g)
    var feasible = true
    var i = 0usize
    while i < x.len {
        if x[i] < m.lb[i] { feasible = false }
        if x[i] > m.ub[i] { feasible = false }
        i += 1usize
    }
    if feasible && v < m.minf {
        m.minf = v
        i = 0usize
        while i < x.len {
            m.bestx[i] = x[i]
            i += 1usize
        }
    }
    ret v
}

// NLOPT_LD_TNEWTON (mos1 1, mos2 1), _RESTART (2, 1), _PRECOND (1, 2), _PRECOND_RESTART (2, 2)
fn pnet[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ctx: *C, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop, mf0: usize, mos1: i64, mos2: i64, tolg: f64) -> (f64, i64) {
    let n = x.len
    var mf = mf0
    if mf == 0usize {
        mf = 1310720usize / n
        if mf < 10usize { mf = 10usize }
        if stop.maxeval > 0i64 && stop.maxeval <= i64(mf) {
            mf = usize(stop.maxeval)
            if mf < 1usize { mf = 1usize }
        }
    }
    let (w, okk) = lk_new(ar, n, lb, ub, x, mf, tolg, mf + 1usize)
    if !okk { ret (0.0f64, nl.OUT_OF_MEMORY) }
    var lw = w
    let wp = &lw
    lk_init(wp, stop)
    wp.tolp = 0.9f64
    wp.mfg = 2147483647i64
    let eps = 0.8f64
    let eta0 = 1.0e-15f64
    let eta9 = 1.0e120f64
    let eps8 = 1.0f64
    let eps9 = 1.0e-8f64
    let alf1 = 1.0e-10f64
    let alf2 = 1.0e10f64
    let told = 1.0e-4f64
    var xstop = false
    var gnorm = 0.0f64
    var snorm = 0.0f64
    var mx = 0usize
    var a = 0.0f64
    var b = 0.0f64
    var rho = 0.0f64
    var rho1 = 0.0f64
    var rho2 = 0.0f64
    var par = 0.0f64
    var alf = 0.0f64
    var pp = 0.0f64
    var iterd = 0i64
    var nredc = 0i64
    let mmx = i64(n) + 3i64
    wp.f = f(ctx, wp.x, wp.gf)
    stop.nevals += 1i64
    wp.nfg += 1i64
    wp.ld = wp.kd
    var stage = 0i64
    while wp.iterm == 0i64 {
        if stage == 0i64 {
            pytrcg(wp)
            mxvcop(n, wp.gf, wp.gn)
            pyfut1(wp, stop, xstop, n)
            if wp.iterm != 0i64 { break }
            if wp.kbf > 0i64 {
                pyrmc0(wp, wp.gn, eps8)
                if wp.umax > eps8 * wp.gmax { wp.irest = imax(wp.irest, 1i64) }
            }
            mxvcop(n, wp.x, wp.xo)
        }
        stage = 0i64
        // L11040
        var tosd = false
        if wp.irest != 0i64 {
            if wp.kit < wp.nit {
                mx = 0usize
                wp.kit = wp.nit
            } else {
                wp.iterm = 0i64 - 10i64
                if wp.iters < 0i64 { wp.iterm = wp.iters - 5i64 }
                break
            }
            if mos1 > 1i64 {
                mxvneg(n, wp.gn, wp.s)
                gnorm = math.sqrt[f64](mxudot(n, wp.gn, wp.gn, wp.ix, wp.kbf))
                snorm = gnorm
                tosd = true
            }
        }
        if !tosd {
            rho1 = mxudot(n, wp.gn, wp.gn, wp.ix, wp.kbf)
            gnorm = math.sqrt[f64](rho1)
            par = nl.fmin(eps, math.sqrt[f64](gnorm))
            if par > 0.01f64 { par = nl.fmin(par, 1.0f64 / f64(wp.nit)) }
            par *= par
            rho = rho1
            snorm = 0.0f64
            mxvset(n, 0.0f64, wp.s)
            mxvneg(n, wp.gn, wp.gs)
            mxvcop(n, wp.gs, wp.xs)
            if mos2 > 1i64 {
                if mx == 0usize {
                    b = 0.0f64
                } else {
                    b = mxudot(n, wp.xm, wp.gm, wp.ix, wp.kbf)
                }
                if b > 0.0f64 {
                    wp.uo[0usize] = 1.0f64 / b
                    mxdrcb(n, mx, wp.xm, wp.gm, wp.uo, wp.vo, wp.xs, wp.ix, wp.kbf)
                    a = mxudot(n, wp.gm, wp.gm, wp.ix, wp.kbf)
                    if a > 0.0f64 { mxvscl(n, b / a, wp.xs, wp.xs) }
                    mxdrcf(n, mx, wp.xm, wp.gm, wp.uo, wp.vo, wp.xs, wp.ix, wp.kbf)
                }
            }
            rho = mxudot(n, wp.gs, wp.xs, wp.ix, wp.kbf)
            nredc = 0i64
            var cg = true
            while cg {
                nredc += 1i64
                if nredc > mmx {
                    cg = false
                } else {
                    wp.fo = wp.f
                    pp = math.sqrt[f64](eta0 / mxudot(n, wp.xs, wp.xs, wp.ix, wp.kbf))
                    wp.ld = 0i64
                    mxudir(n, pp, wp.xs, wp.xo, wp.x, wp.ix, wp.kbf)
                    let _v = f(ctx, wp.x, wp.gf)
                    stop.nevals += 1i64
                    wp.nfg += 1i64
                    wp.ld = wp.kd
                    mxvdif(n, wp.gf, wp.gn, wp.go)
                    wp.f = wp.fo
                    mxvscl(n, 1.0f64 / pp, wp.go, wp.go)
                    alf = mxudot(n, wp.xs, wp.go, wp.ix, wp.kbf)
                    if alf <= 1.0f64 / eta9 {
                        if nredc == 1i64 {
                            mxvneg(n, wp.gn, wp.s)
                            snorm = gnorm
                        }
                        iterd = 0i64
                        cg = false
                    } else {
                        iterd = 2i64
                        alf = rho / alf
                        mxudir(n, alf, wp.xs, wp.s, wp.s, wp.ix, wp.kbf)
                        mxudir(n, 0.0f64 - alf, wp.go, wp.gs, wp.gs, wp.ix, wp.kbf)
                        rho2 = mxudot(n, wp.gs, wp.gs, wp.ix, wp.kbf)
                        snorm = math.sqrt[f64](mxudot(n, wp.s, wp.s, wp.ix, wp.kbf))
                        if rho2 <= par * rho1 {
                            cg = false
                        } else if nredc >= mmx {
                            cg = false
                        } else {
                            if mos2 > 1i64 {
                                if b > 0.0f64 {
                                    mxvcop(n, wp.gs, wp.go)
                                    mxdrcb(n, mx, wp.xm, wp.gm, wp.uo, wp.vo, wp.go, wp.ix, wp.kbf)
                                    if a > 0.0f64 { mxvscl(n, b / a, wp.go, wp.go) }
                                    mxdrcf(n, mx, wp.xm, wp.gm, wp.uo, wp.vo, wp.go, wp.ix, wp.kbf)
                                    rho2 = mxudot(n, wp.gs, wp.go, wp.ix, wp.kbf)
                                    alf = rho2 / rho
                                    mxudir(n, alf, wp.xs, wp.go, wp.xs, wp.ix, wp.kbf)
                                } else {
                                    alf = rho2 / rho
                                    mxudir(n, alf, wp.xs, wp.gs, wp.xs, wp.ix, wp.kbf)
                                }
                            } else {
                                alf = rho2 / rho
                                mxudir(n, alf, wp.xs, wp.gs, wp.xs, wp.ix, wp.kbf)
                            }
                            rho = rho2
                        }
                    }
                }
            }
        }
        // L12560
        mxvcop(n, wp.xo, wp.x)
        mxvcop(n, wp.gn, wp.gf)
        if wp.kd > 0i64 { wp.p = mxudot(n, wp.gn, wp.s, wp.ix, wp.kbf) }
        if iterd < 0i64 {
            wp.iterm = iterd
        } else {
            if snorm <= 0.0f64 {
                wp.irest = imax(wp.irest, 1i64)
            } else if wp.p + told * gnorm * snorm <= 0.0f64 {
                wp.irest = 0i64
            } else {
                wp.irest = imax(wp.irest, 1i64)
            }
            if wp.irest == 0i64 {
                wp.nred = 0i64
                wp.rmin = alf1 * gnorm / snorm
                wp.rmax = nl.fmin(alf2 * gnorm / snorm, 1.0e16f64 / snorm)
            }
        }
        wp.ld = wp.kd
        if wp.iterm != 0i64 { break }
        if wp.irest != 0i64 {
            stage = 1i64
        } else {
            pytrcs(wp, eta9)
            if wp.rmax != 0.0f64 {
                var searching = true
                while searching {
                    ps1l01(wp)
                    if wp.isys == 0i64 {
                        searching = false
                    } else {
                        mxudir(n, wp.r, wp.s, wp.xo, wp.x, wp.ix, wp.kbf)
                        pcbs04(wp, eps9)
                        wp.f = f(ctx, wp.x, wp.gf)
                        stop.nevals += 1i64
                        wp.nfg += 1i64
                        wp.ld = wp.kd
                        wp.p = mxudot(n, wp.gf, wp.s, wp.ix, wp.kbf)
                    }
                }
                if wp.iters <= 0i64 {
                    wp.r = 0.0f64
                    wp.f = wp.fo
                    wp.p = wp.po
                    mxvcop(n, wp.xo, wp.x)
                    mxvcop(n, wp.go, wp.gf)
                    wp.irest = imax(wp.irest, 1i64)
                    wp.ld = wp.kd
                    stage = 1i64
                } else {
                    pytrcd(wp)
                    xstop = nl.stop_dx(stop, wp.x, wp.xo)
                    if mos2 > 1i64 {
                        mx = usize(imin(i64(mx) + 1i64, i64(mf)))
                        mxdrsu(n, mx, wp.xm, wp.gm, wp.uo)
                        mxvcop(n, wp.xo, wp.xm)
                        mxvcop(n, wp.go, wp.gm)
                    }
                }
            }
            if stage == 0i64 {
                if wp.kbf > 0i64 {
                    let inew = pyadc0(wp)
                    if inew > 0i64 { wp.irest = imax(wp.irest, 1i64) }
                }
            }
        }
    }
    ret (wp.f, lk_code(wp.iterm))
}

// NLOPT_LD_TNEWTON*: pnet under nlopt's memoizing wrapper, so the answer is the best feasible point evaluated
fn tnewton[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ctx: *C, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop, mf: usize, mos1: i64, mos2: i64, tolg: f64) -> (f64, i64) {
    let (bx, e) = mem.alloc[f64](ar, x.len + 1usize)
    if e != ok { ret (0.0f64, nl.OUT_OF_MEMORY) }
    var m = Memo[C] { f: f, ctx: ctx, lb: lb, ub: ub, minf: 1.7976931348623157e308f64, bestx: bx }
    let (_v, code) = pnet[Memo[C]](ar, memo_fn[C], &m, lb, ub, x, stop, mf, mos1, mos2, tolg)
    var i = 0usize
    while i < x.len {
        x[i] = bx[i]
        i += 1usize
    }
    ret (m.minf, code)
}
