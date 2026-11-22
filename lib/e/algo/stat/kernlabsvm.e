// R kernlab ksvm: the SMO solvers of kernlab's svm.cpp (a libsvm 2.8 derivative with second-order working-set selection and
// shrinking) for C-svc, nu-svc, one-svc, eps-svr and nu-svr, written as that C++ does it: the kernel matrix is held as
// 32-bit floats (Qfloat), the diagonal QD as doubles, positions are swapped on shrinking, and every update runs in the
// same order, so alpha, rho and the objective reproduce kernlab's to rounding. Data are row-major, n by p, in the order
// ksvm hands them to the solver.
//
// kernel types (kernlab's ktype): 0 vanilladot, 1 polydot(gamma = scale, degree, coef0 = offset), 2 rbfdot(gamma = sigma),
// 3 tanhdot(gamma = scale, coef0 = offset), 5 laplacedot(gamma = sigma), 6 besseldot(gamma = sigma, degree = order, coef0 = kernlab degree), 7 anovadot(gamma = sigma, degree), 8 splinedot.
// svm types (kernlab's svm_type): 0 C-svc, 1 nu-svc, 2 one-svc, 3 eps-svr, 4 nu-svr.
//
// Not here: the bound-constrained solvers (kernlabbsvm), the sparse-matrix input
// path, whose dropped zeros change the ANOVA kernel, and ksvm's scaling and multi-class voting.

use e.math
use e.mem

type Param = struct { ktype: usize, svm: usize, c: f64, nu: f64, p: f64, gamma: f64, degree: i64, coef0: f64, tol: f64, shrinking: bool, cp: f64, cn: f64 }

type S = struct { l: usize, m: usize, active: usize, y: []f64, g: []f64, gbar: []f64, alpha: []f64, p: []f64, st: []u8, act: []usize, qd: []f64, base: []f32, eps: f64, cp: f64, cn: f64, unshrink: bool, nu: bool, r: f64, wi: usize, wj: usize }

fn inf() -> f64 { ret mem.bitcast[f64](9218868437227405312u64) }

fn powi(base: f64, times: i64) -> f64 {
    var tmp = base
    var r = 1.0f64
    var t = times
    while t > 0i64 {
        if t % 2i64 == 1i64 { r *= tmp }
        tmp = tmp * tmp
        t = t / 2i64
    }
    ret r
}

// J_n(x) for an integer order n >= 0 and a finite x >= 0: (1 / N) sum_k cos(n t_k - x sin t_k) over N equally spaced angles, which is exact up to the aliased
// J_(N +- n)(x) (below 1e-16 for the N used). Stands in for libm's jn, which kernlab's Bessel kernel calls; the fractional orders of R's besselJ are not ported.
fn besj(n: i64, x: f64) -> f64 {
    if x <= 4.0f64 {
        // the power series, accurate in relative terms where J_n(x) / x^n is wanted for small x
        let h = x / 2.0f64
        var t = 1.0f64
        var qq = 0i64
        while qq < n {
            t = t * h / f64(qq + 1i64)
            qq += 1i64
        }
        var s = t
        var k = 0i64
        while k < 40i64 {
            t = 0.0f64 - t * h * h / (f64(k + 1i64) * f64(k + n + 1i64))
            s += t
            k += 1i64
        }
        ret s
    }
    let nn = 64usize + 2usize * usize(n) + 2usize * usize(x)
    var s = 0.0f64
    var k = 0usize
    while k < nn {
        let th = 6.283185307179586476925286766559f64 * f64(k) / f64(nn)
        s += math.cos[f64](f64(n) * th - x * math.sin[f64](th))
        k += 1usize
    }
    ret s / f64(nn)
}

fn factorial(n: i64) -> f64 {
    var r = 1.0f64
    var i = 2i64
    while i <= n {
        r *= f64(i)
        i += 1i64
    }
    ret r
}

fn kval(par: *const Param, x: []const f64, nf: usize, xsq: []const f64, i: usize, j: usize) -> f64 {
    let xi = x[i * nf..(i + 1usize) * nf]
    let xj = x[j * nf..(j + 1usize) * nf]
    let kind = par.ktype
    var dot = 0.0f64
    var k = 0usize
    if kind != 7usize && kind != 8usize {
        while k < nf {
            dot += xi[k] * xj[k]
            k += 1usize
        }
    }
    if kind == 0usize { ret dot }
    if kind == 1usize { ret powi(par.gamma * dot + par.coef0, par.degree) }
    if kind == 2usize { ret math.exp[f64](0.0f64 - par.gamma * (xsq[i] + xsq[j] - 2.0f64 * dot)) }
    if kind == 3usize {
        let z = par.gamma * dot + par.coef0
        if z > 20.0f64 { ret 1.0f64 }
        if z < 0.0f64 - 20.0f64 { ret 0.0f64 - 1.0f64 }
        let e2 = math.exp[f64](2.0f64 * z)
        ret (e2 - 1.0f64) / (e2 + 1.0f64)
    }
    if kind == 5usize { ret math.exp[f64](0.0f64 - par.gamma * math.sqrt[f64](math.abs[f64](xsq[i] + xsq[j] - 2.0f64 * dot))) }
    if kind == 6usize {
        // kernel_bessel of svm.cpp: degree is the order, coef0 the exponent
        let bkt = par.gamma * math.sqrt[f64](math.abs[f64](xsq[i] + xsq[j] - 2.0f64 * dot))
        if bkt < 0.000001f64 { ret 1.0f64 }
        let lim = 1.0f64 / (factorial(par.degree) * powi(2.0f64, par.degree))
        ret powi((besj(par.degree, bkt) / powi(bkt, par.degree)) / lim, i64(par.coef0))
    }
    if kind == 7usize {
        var sum = 0.0f64
        while k < nf {
            let tv = (xi[k] - xj[k]) * (xi[k] - xj[k])
            sum += math.exp[f64](0.0f64 - par.gamma * tv)
            k += 1usize
        }
        ret powi(sum, par.degree)
    }
    var result = 1.0f64
    while k < nf {
        var mn = xj[k]
        if xi[k] < xj[k] { mn = xi[k] }
        let t1 = xi[k] * xj[k]
        let t4 = mn * mn
        result *= (1.0f64 + t1 + t1 * mn) - ((xi[k] + xj[k]) / 2.0f64) * t4 + (t4 * mn) / 3.0f64
        k += 1usize
    }
    ret result
}

fn q(s: *const S, i: usize, j: usize) -> f64 {
    ret s.y[i] * s.y[j] * f64(s.base[(s.act[i] % s.m) * s.m + s.act[j] % s.m])
}

fn swapf(v: []f64, i: usize, j: usize) {
    let t = v[i]
    v[i] = v[j]
    v[j] = t
}

fn swap_index(s: *S, i: usize, j: usize) {
    swapf(s.y, i, j)
    swapf(s.g, i, j)
    swapf(s.alpha, i, j)
    swapf(s.p, i, j)
    swapf(s.gbar, i, j)
    swapf(s.qd, i, j)
    let ts = s.st[i]
    s.st[i] = s.st[j]
    s.st[j] = ts
    let ta = s.act[i]
    s.act[i] = s.act[j]
    s.act[j] = ta
}

fn get_c(s: *const S, i: usize) -> f64 {
    if s.y[i] > 0.0f64 { ret s.cp }
    ret s.cn
}

// 0 lower bound, 1 upper bound, 2 free
fn update_status(s: *S, i: usize) {
    if s.alpha[i] >= get_c(s, i) {
        s.st[i] = 1u8
    } else {
        if s.alpha[i] <= 0.0f64 {
            s.st[i] = 0u8
        } else {
            s.st[i] = 2u8
        }
    }
}

fn reconstruct_gradient(s: *S) {
    if s.active == s.l { ret }
    var nr_free = 0usize
    var j = s.active
    while j < s.l {
        s.g[j] = s.gbar[j] + s.p[j]
        j += 1usize
    }
    j = 0usize
    while j < s.active {
        if s.st[j] == 2u8 { nr_free += 1usize }
        j += 1usize
    }
    if nr_free * s.l > 2usize * s.active * (s.l - s.active) {
        var i = s.active
        while i < s.l {
            j = 0usize
            while j < s.active {
                if s.st[j] == 2u8 { s.g[i] += s.alpha[j] * q(s, i, j) }
                j += 1usize
            }
            i += 1usize
        }
    } else {
        var i = 0usize
        while i < s.active {
            if s.st[i] == 2u8 {
                let alpha_i = s.alpha[i]
                j = s.active
                while j < s.l {
                    s.g[j] += alpha_i * q(s, i, j)
                    j += 1usize
                }
            }
            i += 1usize
        }
    }
}

// true when already optimal; otherwise the pair is left in wi, wj
fn select_plain(s: *S) -> bool {
    var gmax = 0.0f64 - inf()
    var gmax2 = 0.0f64 - inf()
    var gmax_idx = s.l
    var gmin_idx = s.l
    var obj_diff_min = inf()
    let tau = 1.0e-12f64
    var t = 0usize
    while t < s.active {
        if s.y[t] > 0.0f64 {
            if s.st[t] != 1u8 {
                if 0.0f64 - s.g[t] >= gmax {
                    gmax = 0.0f64 - s.g[t]
                    gmax_idx = t
                }
            }
        } else {
            if s.st[t] != 0u8 {
                if s.g[t] >= gmax {
                    gmax = s.g[t]
                    gmax_idx = t
                }
            }
        }
        t += 1usize
    }
    let i = gmax_idx
    var j = 0usize
    while j < s.active {
        if s.y[j] > 0.0f64 {
            if s.st[j] != 0u8 {
                let grad_diff = gmax + s.g[j]
                if s.g[j] >= gmax2 { gmax2 = s.g[j] }
                if grad_diff > 0.0f64 {
                    var obj_diff = 0.0f64
                    let quad = s.qd[i] + s.qd[j] - 2.0f64 * s.y[i] * q(s, i, j)
                    if quad > 0.0f64 {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / quad
                    } else {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / tau
                    }
                    if obj_diff <= obj_diff_min {
                        gmin_idx = j
                        obj_diff_min = obj_diff
                    }
                }
            }
        } else {
            if s.st[j] != 1u8 {
                let grad_diff = gmax - s.g[j]
                if 0.0f64 - s.g[j] >= gmax2 { gmax2 = 0.0f64 - s.g[j] }
                if grad_diff > 0.0f64 {
                    var obj_diff = 0.0f64
                    let quad = s.qd[i] + s.qd[j] + 2.0f64 * s.y[i] * q(s, i, j)
                    if quad > 0.0f64 {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / quad
                    } else {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / tau
                    }
                    if obj_diff <= obj_diff_min {
                        gmin_idx = j
                        obj_diff_min = obj_diff
                    }
                }
            }
        }
        j += 1usize
    }
    if gmax + gmax2 < s.eps { ret true }
    s.wi = gmax_idx
    s.wj = gmin_idx
    ret false
}

fn select_nu(s: *S) -> bool {
    var gmaxp = 0.0f64 - inf()
    var gmaxp2 = 0.0f64 - inf()
    var gmaxp_idx = s.l
    var gmaxn = 0.0f64 - inf()
    var gmaxn2 = 0.0f64 - inf()
    var gmaxn_idx = s.l
    var gmin_idx = s.l
    var obj_diff_min = inf()
    let tau = 1.0e-12f64
    var t = 0usize
    while t < s.active {
        if s.y[t] > 0.0f64 {
            if s.st[t] != 1u8 {
                if 0.0f64 - s.g[t] >= gmaxp {
                    gmaxp = 0.0f64 - s.g[t]
                    gmaxp_idx = t
                }
            }
        } else {
            if s.st[t] != 0u8 {
                if s.g[t] >= gmaxn {
                    gmaxn = s.g[t]
                    gmaxn_idx = t
                }
            }
        }
        t += 1usize
    }
    let ip = gmaxp_idx
    let inn = gmaxn_idx
    var j = 0usize
    while j < s.active {
        if s.y[j] > 0.0f64 {
            if s.st[j] != 0u8 {
                let grad_diff = gmaxp + s.g[j]
                if s.g[j] >= gmaxp2 { gmaxp2 = s.g[j] }
                if grad_diff > 0.0f64 {
                    var obj_diff = 0.0f64
                    let quad = s.qd[ip] + s.qd[j] - 2.0f64 * q(s, ip, j)
                    if quad > 0.0f64 {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / quad
                    } else {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / tau
                    }
                    if obj_diff <= obj_diff_min {
                        gmin_idx = j
                        obj_diff_min = obj_diff
                    }
                }
            }
        } else {
            if s.st[j] != 1u8 {
                let grad_diff = gmaxn - s.g[j]
                if 0.0f64 - s.g[j] >= gmaxn2 { gmaxn2 = 0.0f64 - s.g[j] }
                if grad_diff > 0.0f64 {
                    var obj_diff = 0.0f64
                    let quad = s.qd[inn] + s.qd[j] - 2.0f64 * q(s, inn, j)
                    if quad > 0.0f64 {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / quad
                    } else {
                        obj_diff = 0.0f64 - (grad_diff * grad_diff) / tau
                    }
                    if obj_diff <= obj_diff_min {
                        gmin_idx = j
                        obj_diff_min = obj_diff
                    }
                }
            }
        }
        j += 1usize
    }
    var m1 = gmaxp + gmaxp2
    if gmaxn + gmaxn2 > m1 { m1 = gmaxn + gmaxn2 }
    if m1 < s.eps { ret true }
    if s.y[gmin_idx] > 0.0f64 {
        s.wi = gmaxp_idx
    } else {
        s.wi = gmaxn_idx
    }
    s.wj = gmin_idx
    ret false
}

fn shrunk_plain(s: *const S, i: usize, gmax1: f64, gmax2: f64) -> bool {
    if s.st[i] == 1u8 {
        if s.y[i] > 0.0f64 { ret 0.0f64 - s.g[i] > gmax1 }
        ret 0.0f64 - s.g[i] > gmax2
    }
    if s.st[i] == 0u8 {
        if s.y[i] > 0.0f64 { ret s.g[i] > gmax2 }
        ret s.g[i] > gmax1
    }
    ret false
}

fn shrunk_nu(s: *const S, i: usize, gmax1: f64, gmax2: f64, gmax3: f64, gmax4: f64) -> bool {
    if s.st[i] == 1u8 {
        if s.y[i] > 0.0f64 { ret 0.0f64 - s.g[i] > gmax1 }
        ret 0.0f64 - s.g[i] > gmax4
    }
    if s.st[i] == 0u8 {
        if s.y[i] > 0.0f64 { ret s.g[i] > gmax2 }
        ret s.g[i] > gmax3
    }
    ret false
}

fn do_shrinking(s: *S) {
    var gmax1 = 0.0f64 - inf()
    var gmax2 = 0.0f64 - inf()
    var gmax3 = 0.0f64 - inf()
    var gmax4 = 0.0f64 - inf()
    var i = 0usize
    if s.nu {
        while i < s.active {
            if s.st[i] != 1u8 {
                if s.y[i] > 0.0f64 {
                    if 0.0f64 - s.g[i] > gmax1 { gmax1 = 0.0f64 - s.g[i] }
                } else {
                    if 0.0f64 - s.g[i] > gmax4 { gmax4 = 0.0f64 - s.g[i] }
                }
            }
            if s.st[i] != 0u8 {
                if s.y[i] > 0.0f64 {
                    if s.g[i] > gmax2 { gmax2 = s.g[i] }
                } else {
                    if s.g[i] > gmax3 { gmax3 = s.g[i] }
                }
            }
            i += 1usize
        }
        var mm = gmax1 + gmax2
        if gmax3 + gmax4 > mm { mm = gmax3 + gmax4 }
        if !s.unshrink && mm <= s.eps * 10.0f64 {
            s.unshrink = true
            reconstruct_gradient(s)
            s.active = s.l
        }
    } else {
        while i < s.active {
            if s.y[i] > 0.0f64 {
                if s.st[i] != 1u8 {
                    if 0.0f64 - s.g[i] >= gmax1 { gmax1 = 0.0f64 - s.g[i] }
                }
                if s.st[i] != 0u8 {
                    if s.g[i] >= gmax2 { gmax2 = s.g[i] }
                }
            } else {
                if s.st[i] != 1u8 {
                    if 0.0f64 - s.g[i] >= gmax2 { gmax2 = 0.0f64 - s.g[i] }
                }
                if s.st[i] != 0u8 {
                    if s.g[i] >= gmax1 { gmax1 = s.g[i] }
                }
            }
            i += 1usize
        }
        if !s.unshrink && gmax1 + gmax2 <= s.eps * 10.0f64 {
            s.unshrink = true
            reconstruct_gradient(s)
            s.active = s.l
        }
    }
    i = 0usize
    while i < s.active {
        var sh = false
        if s.nu {
            sh = shrunk_nu(s, i, gmax1, gmax2, gmax3, gmax4)
        } else {
            sh = shrunk_plain(s, i, gmax1, gmax2)
        }
        if sh {
            s.active -= 1usize
            while s.active > i {
                var sh2 = false
                if s.nu {
                    sh2 = shrunk_nu(s, s.active, gmax1, gmax2, gmax3, gmax4)
                } else {
                    sh2 = shrunk_plain(s, s.active, gmax1, gmax2)
                }
                if !sh2 {
                    swap_index(s, i, s.active)
                    break
                }
                s.active -= 1usize
            }
        }
        i += 1usize
    }
}

fn calc_rho(s: *S) -> f64 {
    if s.nu {
        var nr1 = 0usize
        var nr2 = 0usize
        var ub1 = inf()
        var ub2 = inf()
        var lb1 = 0.0f64 - inf()
        var lb2 = 0.0f64 - inf()
        var sum1 = 0.0f64
        var sum2 = 0.0f64
        var i = 0usize
        while i < s.active {
            if s.y[i] > 0.0f64 {
                if s.st[i] == 1u8 {
                    if s.g[i] > lb1 { lb1 = s.g[i] }
                } else {
                    if s.st[i] == 0u8 {
                        if s.g[i] < ub1 { ub1 = s.g[i] }
                    } else {
                        nr1 += 1usize
                        sum1 += s.g[i]
                    }
                }
            } else {
                if s.st[i] == 1u8 {
                    if s.g[i] > lb2 { lb2 = s.g[i] }
                } else {
                    if s.st[i] == 0u8 {
                        if s.g[i] < ub2 { ub2 = s.g[i] }
                    } else {
                        nr2 += 1usize
                        sum2 += s.g[i]
                    }
                }
            }
            i += 1usize
        }
        var r1 = (ub1 + lb1) / 2.0f64
        if nr1 > 0usize { r1 = sum1 / f64(nr1) }
        var r2 = (ub2 + lb2) / 2.0f64
        if nr2 > 0usize { r2 = sum2 / f64(nr2) }
        s.r = (r1 + r2) / 2.0f64
        ret (r1 - r2) / 2.0f64
    }
    var nr_free = 0usize
    var ub = inf()
    var lb = 0.0f64 - inf()
    var sum_free = 0.0f64
    var i = 0usize
    while i < s.active {
        let yg = s.y[i] * s.g[i]
        if s.st[i] == 1u8 {
            if s.y[i] < 0.0f64 {
                if yg < ub { ub = yg }
            } else {
                if yg > lb { lb = yg }
            }
        } else {
            if s.st[i] == 0u8 {
                if s.y[i] > 0.0f64 {
                    if yg < ub { ub = yg }
                } else {
                    if yg > lb { lb = yg }
                }
            } else {
                nr_free += 1usize
                sum_free += yg
            }
        }
        i += 1usize
    }
    if nr_free > 0usize { ret sum_free / f64(nr_free) }
    ret (ub + lb) / 2.0f64
}

// Solver::Solve over s (already holding y, p, alpha, qd, base); alpha_out receives alpha in the caller's order. Answers rho and the objective.
fn solve(a: *mem.Arena, s: *S, shrinking: bool, alpha_out: []f64) -> (f64, f64, err) {
    let l = s.l
    var i = 0usize
    while i < l {
        s.gbar[i] = 0.0f64
        s.g[i] = s.p[i]
        s.act[i] = i
        update_status(s, i)
        i += 1usize
    }
    s.active = l
    s.unshrink = false
    i = 0usize
    while i < l {
        if s.st[i] != 0u8 {
            let alpha_i = s.alpha[i]
            var j = 0usize
            while j < l {
                s.g[j] += alpha_i * q(s, i, j)
                j += 1usize
            }
            if s.st[i] == 1u8 {
                j = 0usize
                while j < l {
                    s.gbar[j] += get_c(s, i) * q(s, i, j)
                    j += 1usize
                }
            }
        }
        i += 1usize
    }
    var iter = 0usize
    var max_iter = 10000000usize
    if 100usize * l > max_iter { max_iter = 100usize * l }
    var lim = l
    if lim > 1000usize { lim = 1000usize }
    var counter = lim + 1usize
    while iter < max_iter {
        counter -= 1usize
        if counter == 0usize {
            counter = lim
            if shrinking { do_shrinking(s) }
        }
        var opt = false
        if s.nu {
            opt = select_nu(s)
        } else {
            opt = select_plain(s)
        }
        if opt {
            reconstruct_gradient(s)
            s.active = s.l
            if s.nu {
                opt = select_nu(s)
            } else {
                opt = select_plain(s)
            }
            if opt { break }
            counter = 1usize
        }
        iter += 1usize
        let ii = s.wi
        let jj = s.wj
        let c_i = get_c(s, ii)
        let c_j = get_c(s, jj)
        let old_i = s.alpha[ii]
        let old_j = s.alpha[jj]
        let qij = q(s, ii, jj)
        let tau = 1.0e-12f64
        if s.y[ii] != s.y[jj] {
            var quad = s.qd[ii] + s.qd[jj] + 2.0f64 * qij
            if quad <= 0.0f64 { quad = tau }
            let delta = (0.0f64 - s.g[ii] - s.g[jj]) / quad
            let diff = s.alpha[ii] - s.alpha[jj]
            s.alpha[ii] += delta
            s.alpha[jj] += delta
            if diff > 0.0f64 {
                if s.alpha[jj] < 0.0f64 {
                    s.alpha[jj] = 0.0f64
                    s.alpha[ii] = diff
                }
            } else {
                if s.alpha[ii] < 0.0f64 {
                    s.alpha[ii] = 0.0f64
                    s.alpha[jj] = 0.0f64 - diff
                }
            }
            if diff > c_i - c_j {
                if s.alpha[ii] > c_i {
                    s.alpha[ii] = c_i
                    s.alpha[jj] = c_i - diff
                }
            } else {
                if s.alpha[jj] > c_j {
                    s.alpha[jj] = c_j
                    s.alpha[ii] = c_j + diff
                }
            }
        } else {
            var quad = s.qd[ii] + s.qd[jj] - 2.0f64 * qij
            if quad <= 0.0f64 { quad = tau }
            let delta = (s.g[ii] - s.g[jj]) / quad
            let sum = s.alpha[ii] + s.alpha[jj]
            s.alpha[ii] -= delta
            s.alpha[jj] += delta
            if sum > c_i {
                if s.alpha[ii] > c_i {
                    s.alpha[ii] = c_i
                    s.alpha[jj] = sum - c_i
                }
            } else {
                if s.alpha[jj] < 0.0f64 {
                    s.alpha[jj] = 0.0f64
                    s.alpha[ii] = sum
                }
            }
            if sum > c_j {
                if s.alpha[jj] > c_j {
                    s.alpha[jj] = c_j
                    s.alpha[ii] = sum - c_j
                }
            } else {
                if s.alpha[ii] < 0.0f64 {
                    s.alpha[ii] = 0.0f64
                    s.alpha[jj] = sum
                }
            }
        }
        let da_i = s.alpha[ii] - old_i
        let da_j = s.alpha[jj] - old_j
        var k = 0usize
        while k < s.active {
            s.g[k] += q(s, ii, k) * da_i + q(s, jj, k) * da_j
            k += 1usize
        }
        let ui = s.st[ii] == 1u8
        let uj = s.st[jj] == 1u8
        update_status(s, ii)
        update_status(s, jj)
        if ui != (s.st[ii] == 1u8) {
            k = 0usize
            while k < l {
                if ui {
                    s.gbar[k] -= c_i * q(s, ii, k)
                } else {
                    s.gbar[k] += c_i * q(s, ii, k)
                }
                k += 1usize
            }
        }
        if uj != (s.st[jj] == 1u8) {
            k = 0usize
            while k < l {
                if uj {
                    s.gbar[k] -= c_j * q(s, jj, k)
                } else {
                    s.gbar[k] += c_j * q(s, jj, k)
                }
                k += 1usize
            }
        }
    }
    if iter >= max_iter {
        if s.active < l {
            reconstruct_gradient(s)
            s.active = l
        }
    }
    let rho = calc_rho(s)
    var v = 0.0f64
    i = 0usize
    while i < l {
        v += s.alpha[i] * (s.g[i] + s.p[i])
        i += 1usize
    }
    i = 0usize
    while i < l {
        alpha_out[s.act[i]] = s.alpha[i]
        i += 1usize
    }
    ret (rho, v / 2.0f64, ok)
}

// kernlab's smo_optim: x is n by nf row-major, y the labels (any sign for classification, targets for regression); out receives n values (alpha for C-svc and one-svc, alpha * y for nu-svc, alpha - alpha* for the regressions). Answers rho (ksvm's b) and the objective.
fn smo_optim(a: *mem.Arena, x: []const f64, n: usize, nf: usize, y: []const f64, par: *const Param, out: []f64) -> (f64, f64, err) {
    var l = n
    if par.svm >= 3usize { l = 2usize * n }
    let (xsq, e1) = mem.alloc[f64](a, n)
    let (base, e2) = mem.alloc[f32](a, n * n)
    let (yy, e3) = mem.alloc[f64](a, l)
    let (g, e4) = mem.alloc[f64](a, l)
    let (gbar, e5) = mem.alloc[f64](a, l)
    let (alpha, e6) = mem.alloc[f64](a, l)
    let (pp, e7) = mem.alloc[f64](a, l)
    let (st, e8) = mem.alloc[u8](a, l)
    let (act, e9) = mem.alloc[usize](a, l)
    let (qd, e10) = mem.alloc[f64](a, l)
    let (res, e11) = mem.alloc[f64](a, l)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    if e4 != ok { ret (0.0f64, 0.0f64, e4) }
    if e5 != ok { ret (0.0f64, 0.0f64, e5) }
    if e6 != ok { ret (0.0f64, 0.0f64, e6) }
    if e7 != ok { ret (0.0f64, 0.0f64, e7) }
    if e8 != ok { ret (0.0f64, 0.0f64, e8) }
    if e9 != ok { ret (0.0f64, 0.0f64, e9) }
    if e10 != ok { ret (0.0f64, 0.0f64, e10) }
    if e11 != ok { ret (0.0f64, 0.0f64, e11) }
    var i = 0usize
    while i < n {
        var d = 0.0f64
        var k = 0usize
        while k < nf {
            d += x[i * nf + k] * x[i * nf + k]
            k += 1usize
        }
        xsq[i] = d
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            base[i * n + j] = f32(kval(par, x, nf, xsq, i, j))
            j += 1usize
        }
        qd[i] = kval(par, x, nf, xsq, i, i)
        if l > n { qd[i + n] = qd[i] }
        i += 1usize
    }
    var s = S { l: l, m: n, active: l, y: yy, g: g, gbar: gbar, alpha: alpha, p: pp, st: st, act: act, qd: qd, base: base, eps: par.tol, cp: par.c, cn: par.c, unshrink: false, nu: false, r: 0.0f64, wi: 0usize, wj: 0usize }
    let nf64 = f64(n)
    if par.svm == 0usize {
        i = 0usize
        while i < n {
            alpha[i] = 0.0f64
            pp[i] = 0.0f64 - 1.0f64
            yy[i] = 0.0f64 - 1.0f64
            if y[i] > 0.0f64 { yy[i] = 1.0f64 }
            i += 1usize
        }
        s.cp = par.cp
        s.cn = par.cn
        let (rho, obj, e) = solve(a, &s, par.shrinking, out)
        ret (rho, obj, e)
    }
    if par.svm == 1usize {
        var sum_pos = par.nu * nf64 / 2.0f64
        var sum_neg = par.nu * nf64 / 2.0f64
        i = 0usize
        while i < n {
            pp[i] = 0.0f64
            if y[i] > 0.0f64 {
                yy[i] = 1.0f64
                alpha[i] = 1.0f64
                if sum_pos < 1.0f64 { alpha[i] = sum_pos }
                sum_pos -= alpha[i]
            } else {
                yy[i] = 0.0f64 - 1.0f64
                alpha[i] = 1.0f64
                if sum_neg < 1.0f64 { alpha[i] = sum_neg }
                sum_neg -= alpha[i]
            }
            i += 1usize
        }
        s.cp = 1.0f64
        s.cn = 1.0f64
        s.nu = true
        let (rho, obj, e) = solve(a, &s, par.shrinking, out)
        let r = s.r
        i = 0usize
        while i < n {
            var sg = 0.0f64 - 1.0f64
            if y[i] > 0.0f64 { sg = 1.0f64 }
            out[i] = out[i] * (sg / r)
            i += 1usize
        }
        ret (rho / r, obj / (r * r), e)
    }
    if par.svm == 2usize {
        let cnt = usize(par.nu * nf64)
        i = 0usize
        while i < n {
            alpha[i] = 0.0f64
            if i < cnt { alpha[i] = 1.0f64 }
            pp[i] = 0.0f64
            yy[i] = 1.0f64
            i += 1usize
        }
        if cnt < n { alpha[cnt] = par.nu * nf64 - f64(cnt) }
        s.cp = 1.0f64
        s.cn = 1.0f64
        let (rho, obj, e) = solve(a, &s, par.shrinking, out)
        ret (rho, obj, e)
    }
    // regression: 2n variables
    if par.svm == 3usize {
        i = 0usize
        while i < n {
            alpha[i] = 0.0f64
            alpha[i + n] = 0.0f64
            pp[i] = par.p - y[i]
            yy[i] = 1.0f64
            pp[i + n] = par.p + y[i]
            yy[i + n] = 0.0f64 - 1.0f64
            i += 1usize
        }
    } else {
        var sum = par.c * par.nu * nf64 / 2.0f64
        i = 0usize
        while i < n {
            var v = par.c
            if sum < v { v = sum }
            alpha[i] = v
            alpha[i + n] = v
            sum -= v
            pp[i] = 0.0f64 - y[i]
            yy[i] = 1.0f64
            pp[i + n] = y[i]
            yy[i + n] = 0.0f64 - 1.0f64
            i += 1usize
        }
        s.nu = true
    }
    let (rho, obj, e) = solve(a, &s, par.shrinking, res)
    i = 0usize
    while i < n {
        out[i] = res[i] - res[i + n]
        i += 1usize
    }
    ret (rho, obj, e)
}
