// R stats state-space routines: KalmanLike / KalmanRun (the filter) and KalmanSmooth (the fixed-interval smoother).
//
// A model is the list stats uses: T (transition), Z (observation), h, V, a (state), P (state covariance) and Pn (the
// predicted covariance used while l <= nit). Matrices are row-major p x p. The filter works in place on a, P and Pn,
// like R's C code does; the smoother and a caller who wants the model kept pass a copy.

use e.math
use e.mem

type SsModel = struct { p: usize, tm: []f64, zv: []f64, h: f64, vm: []f64, av: []f64, pm: []f64, pn: []f64 }

fn k_is_nan(x: f64) -> bool { ret x != x }

fn k_nan() -> f64 { ret mem.bitcast[f64](9221120237041090560u64) }

// a deep copy of the model
fn ss_copy(ar: *mem.Arena, m: *const SsModel) -> (SsModel, err) {
    let p = m.p
    let (tm, e1) = mem.alloc[f64](ar, p * p)
    let (zv, e2) = mem.alloc[f64](ar, p)
    let (vm, e3) = mem.alloc[f64](ar, p * p)
    let (av, e4) = mem.alloc[f64](ar, p)
    let (pm, e5) = mem.alloc[f64](ar, p * p)
    let (pn, e6) = mem.alloc[f64](ar, p * p)
    var out: SsModel = zero
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (out, mem.Exhausted) }
    var i = 0usize
    while i < p * p {
        tm[i] = m.tm[i]
        vm[i] = m.vm[i]
        pm[i] = m.pm[i]
        pn[i] = m.pn[i]
        i += 1usize
    }
    i = 0usize
    while i < p {
        zv[i] = m.zv[i]
        av[i] = m.av[i]
        i += 1usize
    }
    out = SsModel{ p: p, tm: tm, zv: zv, h: m.h, vm: vm, av: av, pm: pm, pn: pn }
    ret (out, ok)
}

// anew = T a; when l > nit also pn = T P T' + V (mm is scratch p x p)
fn ss_predict(m: *SsModel, anew: []f64, mm: []f64, l: usize, nit: i64) {
    let p = m.p
    var i = 0usize
    while i < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += m.tm[i * p + k] * m.av[k]
            k += 1usize
        }
        anew[i] = s
        i += 1usize
    }
    if i64(l) > nit {
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += m.tm[i * p + k] * m.pm[k * p + j]
                    k += 1usize
                }
                mm[i * p + j] = s
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < p {
            var j = 0usize
            while j < p {
                var s = m.vm[i * p + j]
                var k = 0usize
                while k < p {
                    s += mm[i * p + k] * m.tm[j * p + k]
                    k += 1usize
                }
                m.pn[i * p + j] = s
                j += 1usize
            }
            i += 1usize
        }
    }
}

// KalmanLike (cut = 1e300) or ARIMA_Like (cut = 1e4: a gain at or above it, a diffuse start, is left out of the sums): returns (sum of squared standardised innovations, sum of log gains, count of observations). `states`
// (n x p, filtered) and `resid` (n, standardised) are filled when not empty. The model is changed in place.
fn kalman_filter(ar: *mem.Arena, m: *SsModel, y: []const f64, nit: i64, states: []f64, resid: []f64, cut: f64) -> (f64, f64, usize, err) {
    let p = m.p
    let n = y.len
    let (anew, e1) = mem.alloc[f64](ar, p)
    let (mv, e2) = mem.alloc[f64](ar, p)
    let (mm, e3) = mem.alloc[f64](ar, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret (0.0f64, 0.0f64, 0usize, mem.Exhausted) }
    var ssq = 0.0f64
    var sumlog = 0.0f64
    var nu = 0usize
    var l = 0usize
    while l < n {
        ss_predict(m, anew, mm, l, nit)
        if !k_is_nan(y[l]) {
            var r0 = y[l]
            var i = 0usize
            while i < p {
                r0 -= m.zv[i] * anew[i]
                i += 1usize
            }
            var gain = m.h
            i = 0usize
            while i < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += m.pn[i * p + k] * m.zv[k]
                    k += 1usize
                }
                mv[i] = s
                gain += m.zv[i] * s
                i += 1usize
            }
            if gain < cut {
                nu += 1usize
                ssq += r0 * r0 / gain
                sumlog += math.log[f64](gain)
                if resid.len > 0usize { resid[l] = r0 / math.sqrt[f64](gain) }
            } else {
                if resid.len > 0usize { resid[l] = k_nan() }
            }
            i = 0usize
            while i < p {
                m.av[i] = anew[i] + mv[i] * r0 / gain
                i += 1usize
            }
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    m.pm[i * p + j] = m.pn[i * p + j] - mv[i] * mv[j] / gain
                    j += 1usize
                }
                i += 1usize
            }
        } else {
            var i = 0usize
            while i < p {
                m.av[i] = anew[i]
                i += 1usize
            }
            i = 0usize
            while i < p * p {
                m.pm[i] = m.pn[i]
                i += 1usize
            }
            if resid.len > 0usize { resid[l] = k_nan() }
        }
        if states.len > 0usize {
            var i = 0usize
            while i < p {
                states[l * p + i] = m.av[i]
                i += 1usize
            }
        }
        l += 1usize
    }
    ret (ssq, sumlog, nu, ok)
}

// KalmanSmooth(y, mod, nit)$smooth: the smoothed states, n x p row-major. The model is not changed.
fn kalman_smooth(ar: *mem.Arena, m0: *const SsModel, y: []const f64, nit: i64) -> ([]f64, err) {
    let p = m0.p
    let n = y.len
    let (mc, ec) = ss_copy(ar, m0)
    if ec != ok { ret (zero, ec) }
    var m = mc
    let (anew, e1) = mem.alloc[f64](ar, p)
    let (mv, e2) = mem.alloc[f64](ar, p)
    let (mm, e3) = mem.alloc[f64](ar, p * p)
    let (at, e4) = mem.alloc[f64](ar, n * p)
    let (pt, e5) = mem.alloc[f64](ar, n * p * p)
    let (mt, e6) = mem.alloc[f64](ar, n * p)
    let (gains, e7) = mem.alloc[f64](ar, n)
    let (resids, e8) = mem.alloc[f64](ar, n)
    let (sm, e9) = mem.alloc[f64](ar, n * p)
    let (rnext, e10) = mem.alloc[f64](ar, p)
    let (rcur, e11) = mem.alloc[f64](ar, p)
    let (lm, e12) = mem.alloc[f64](ar, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok { ret (zero, mem.Exhausted) }
    var l = 0usize
    while l < n {
        ss_predict(&m, anew, mm, l, nit)
        var i = 0usize
        while i < p {
            at[l * p + i] = anew[i]
            i += 1usize
        }
        i = 0usize
        while i < p * p {
            pt[l * p * p + i] = m.pn[i]
            i += 1usize
        }
        if !k_is_nan(y[l]) {
            var r0 = y[l]
            i = 0usize
            while i < p {
                r0 -= m.zv[i] * anew[i]
                i += 1usize
            }
            var gain = m.h
            i = 0usize
            while i < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += m.pn[i * p + k] * m.zv[k]
                    k += 1usize
                }
                mv[i] = s
                mt[l * p + i] = s
                gain += m.zv[i] * s
                i += 1usize
            }
            gains[l] = gain
            resids[l] = r0
            i = 0usize
            while i < p {
                m.av[i] = anew[i] + mv[i] * r0 / gain
                i += 1usize
            }
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    m.pm[i * p + j] = m.pn[i * p + j] - mv[i] * mv[j] / gain
                    j += 1usize
                }
                i += 1usize
            }
        } else {
            i = 0usize
            while i < p {
                m.av[i] = anew[i]
                mt[l * p + i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < p * p {
                m.pm[i] = m.pn[i]
                i += 1usize
            }
            gains[l] = k_nan()
            resids[l] = k_nan()
        }
        l += 1usize
    }
    var i = 0usize
    while i < p {
        rnext[i] = 0.0f64
        i += 1usize
    }
    var ll = n
    while ll > 0usize {
        let q = ll - 1usize
        var gn = 0.0f64
        i = 0usize
        while i < p {
            rcur[i] = 0.0f64
            i += 1usize
        }
        if !k_is_nan(gains[q]) {
            gn = 1.0f64 / gains[q]
            i = 0usize
            while i < p {
                rcur[i] = m.zv[i] * resids[q] * gn
                i += 1usize
            }
        }
        if q < n - 1usize {
            // mm = I - M Z' / F, lm = T mm, r_{q} += lm' r_{q+1}
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    var d0 = 0.0f64
                    if i == j { d0 = 1.0f64 }
                    mm[i * p + j] = d0 - mt[q * p + i] * m.zv[j] * gn
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    var s = 0.0f64
                    var k = 0usize
                    while k < p {
                        s += m.tm[i * p + k] * mm[k * p + j]
                        k += 1usize
                    }
                    lm[i * p + j] = s
                    j += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < p {
                var s = 0.0f64
                var j = 0usize
                while j < p {
                    s += lm[j * p + i] * rnext[j]
                    j += 1usize
                }
                rcur[i] += s
                i += 1usize
            }
        }
        i = 0usize
        while i < p {
            var s = 0.0f64
            var j = 0usize
            while j < p {
                s += pt[q * p * p + i * p + j] * rcur[j]
                j += 1usize
            }
            sm[q * p + i] = at[q * p + i] + s
            i += 1usize
        }
        i = 0usize
        while i < p {
            rnext[i] = rcur[i]
            i += 1usize
        }
        ll -= 1usize
    }
    ret (sm, ok)
}
