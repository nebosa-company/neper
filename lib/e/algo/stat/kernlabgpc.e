// R kernlab gausspr classification: the Laplace approximation of gausspr.R, one-against-one over the class pairs (1,2), (1,3), ..., each solved by Newton steps whose linear system
// (I + diag(hess) K) solut = grad + alpha goes through solveiter, the preconditioned biconjugate gradient method of gausspr.R, started from the previous step's solution. Voting
// (which.max, the first class on ties) and the coupled probabilities as predict.gausspr gives them. K is kernelMatrix (kernlabmmd.cross, kind 0 rbfdot or 4 laplacedot),
// predictions use kernelMult as kernlabclass.decide does. Data are row-major, n by nf, in the order gausspr hands them to the solver.

use e.algo.stat.armld as ld
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabmmd as km
use e.algo.stat.kernlabsvm as ks
use e.math
use e.mem

error Fail

// out = B d (n by n row-major)
fn matvec(b: []const f64, d: []const f64, n: usize, out: []f64) {
    var i = 0usize
    while i < n {
        out[i] = 0.0f64
        i += 1usize
    }
    var l = 0usize
    while l < n {
        let t = d[l]
        i = 0usize
        while i < n {
            out[i] = out[i] + t * b[i * n + l]
            i += 1usize
        }
        l += 1usize
    }
}

fn dotv(x: []const f64, y: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

// .Amul2: d + noise * (B d)
fn amul2(a: *mem.Arena, b: []const f64, noise: []const f64, d: []const f64, n: usize, ee: []f64, out: []f64) {
    matvec(b, d, n, ee)
    var i = 0usize
    while i < n {
        out[i] = d[i] + noise[i] * ee[i]
        i += 1usize
    }
}

// solveiter(B, noiseproc, b, x): updates x in place
fn solveiter(a: *mem.Arena, bm: []const f64, noise: []const f64, b: []const f64, x: []f64, n: usize) -> err {
    let (pool, e1) = mem.alloc[f64](a, 11usize * n)
    if e1 != ok { ret Fail }
    let diag = pool[0usize..n]
    let r = pool[n..2usize * n]
    let rr = pool[2usize * n..3usize * n]
    let z = pool[3usize * n..4usize * n]
    let zz = pool[4usize * n..5usize * n]
    let p = pool[5usize * n..6usize * n]
    let pp = pool[6usize * n..7usize * n]
    let ee = pool[7usize * n..8usize * n]
    let tmp = pool[8usize * n..9usize * n]
    let col = pool[9usize * n..10usize * n]
    let t2 = pool[10usize * n..11usize * n]
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            col[k] = bm[k * n + i]
            k += 1usize
        }
        diag[i] = (1.0f64 + ld.sum_ld(col[0usize..n])) + bm[i * n + i] * (noise[i] - 1.0f64)
        i += 1usize
    }
    amul2(a, bm, noise, x, n, ee, tmp)
    i = 0usize
    while i < n {
        r[i] = b[i] - tmp[i]
        rr[i] = r[i]
        z[i] = r[i] / diag[i]
        i += 1usize
    }
    var iter = 0usize
    var bkden = 0.0f64
    while iter <= 50usize {
        iter += 1usize
        i = 0usize
        while i < n {
            zz[i] = rr[i] / diag[i]
            i += 1usize
        }
        let bknum = dotv(z, rr, n)
        if iter == 1usize {
            i = 0usize
            while i < n {
                p[i] = z[i]
                pp[i] = zz[i]
                i += 1usize
            }
        } else {
            let bk = bknum / bkden
            i = 0usize
            while i < n {
                p[i] = bk * p[i] + z[i]
                pp[i] = bk * pp[i] + zz[i]
                i += 1usize
            }
        }
        bkden = bknum
        amul2(a, bm, noise, p, n, ee, z)
        let akden = dotv(z, pp, n)
        let ak = bknum / akden
        // .Amul2T: pp + B (noise * pp)
        i = 0usize
        while i < n {
            t2[i] = noise[i] * pp[i]
            i += 1usize
        }
        matvec(bm, t2, n, ee)
        i = 0usize
        while i < n {
            zz[i] = pp[i] + ee[i]
            i += 1usize
        }
        i = 0usize
        while i < n {
            x[i] = x[i] + ak * p[i]
            r[i] = r[i] - ak * z[i]
            rr[i] = rr[i] - ak * zz[i]
            z[i] = r[i] / diag[i]
            tmp[i] = math.abs[f64](r[i])
            i += 1usize
        }
        let er = ld.sum_ld(tmp[0usize..n]) / f64(n)
        if er < 0.001f64 { break }
    }
    ret ok
}

// the Newton iteration for one pair: yd = +1 / -1, answers alphag (n values)
fn fit_pair(a: *mem.Arena, kk: []const f64, yd: []const f64, n: usize, tol: f64, alphag: []f64) -> err {
    let (pool, e1) = mem.alloc[f64](a, 6usize * n)
    if e1 != ok { ret Fail }
    let f = pool[0usize..n]
    let grad = pool[n..2usize * n]
    let hess = pool[2usize * n..3usize * n]
    let solut = pool[3usize * n..4usize * n]
    let rhs = pool[4usize * n..5usize * n]
    let sq = pool[5usize * n..6usize * n]
    var i = 0usize
    while i < n {
        alphag[i] = 0.0f64
        solut[i] = 0.0f64
        i += 1usize
    }
    var gradnorm = 1.0f64
    var guard = 0usize
    while gradnorm > tol && guard < 200usize {
        guard += 1usize
        // crossprod(K, alphag): column i of K against alphag
        i = 0usize
        while i < n {
            var s = 0.0f64
            var l = 0usize
            while l < n {
                s += kk[l * n + i] * alphag[l]
                l += 1usize
            }
            f[i] = s
            i += 1usize
        }
        i = 0usize
        while i < n {
            let ex = math.exp[f64](yd[i] * f[i])
            grad[i] = 0.0f64 - yd[i] / (1.0f64 + ex)
            hess[i] = ex / ((1.0f64 + ex) * (1.0f64 + ex))
            rhs[i] = grad[i] + alphag[i]
            i += 1usize
        }
        let e = solveiter(a, kk, hess, rhs, solut, n)
        if e != ok { ret e }
        i = 0usize
        while i < n {
            alphag[i] = alphag[i] - solut[i]
            sq[i] = (grad[i] + alphag[i]) * (grad[i] + alphag[i])
            i += 1usize
        }
        gradnorm = math.sqrt[f64](ld.sum_ld(sq[0usize..n]))
    }
    ret ok
}

// all pairs: alpha (npair by n, 0 off the pair's rows); cls the 0-based class of each row. kind 0 rbfdot, 4 laplacedot with sigma par1
fn fit(a: *mem.Arena, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, kind: usize, par1: f64, tol: f64, alpha: []f64) -> err {
    var p = 0usize
    var i = 0usize
    while i < kc * (kc - 1usize) / 2usize * n {
        alpha[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i + 1usize < kc {
        var j = i + 1usize
        while j < kc {
            let start = mem.mark(a)
            let (idx, e1) = mem.alloc[usize](a, n)
            if e1 != ok { ret Fail }
            var m = 0usize
            var li = 0usize
            var r = 0usize
            while r < n {
                if cls[r] == i {
                    idx[m] = r
                    m += 1usize
                    li += 1usize
                }
                r += 1usize
            }
            r = 0usize
            while r < n {
                if cls[r] == j {
                    idx[m] = r
                    m += 1usize
                }
                r += 1usize
            }
            let (xs, e2) = mem.alloc[f64](a, m * nf)
            let (yd, e3) = mem.alloc[f64](a, m)
            let (kk, e4) = mem.alloc[f64](a, m * m)
            let (ag, e5) = mem.alloc[f64](a, m)
            if e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Fail }
            var q = 0usize
            while q < m {
                var k = 0usize
                while k < nf {
                    xs[q * nf + k] = x[idx[q] * nf + k]
                    k += 1usize
                }
                yd[q] = 0.0f64 - 1.0f64
                if q < li { yd[q] = 1.0f64 }
                q += 1usize
            }
            km.cross(true, kind, xs, xs, m, m, nf, par1, 0.0f64, 0.0f64, kk)
            let e = fit_pair(a, kk, yd, m, tol, ag)
            if e != ok { ret e }
            q = 0usize
            while q < m {
                alpha[p * n + idx[q]] = ag[q]
                q += 1usize
            }
            mem.reset(a, start)
            p += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// the pairwise decision values on xt: dec (npair by nt), kernelMult of the fitted rows
fn decisions(a: *mem.Arena, x: []const f64, n: usize, nf: usize, kc: usize, kind: usize, par1: f64, alpha: []const f64, xt: []const f64, nt: usize, dec: []f64) -> err {
    var ktype = 2usize
    if kind == 4usize { ktype = 5usize }
    let par = ks.Param { ktype: ktype, svm: 0usize, c: 1.0f64, nu: 0.1f64, p: 0.1f64, gamma: par1, degree: 1i64, coef0: 0.0f64, tol: 0.001f64, shrinking: true, cp: 1.0f64, cn: 1.0f64 }
    let (one, e1) = mem.alloc[f64](a, nt)
    if e1 != ok { ret Fail }
    let np = kc * (kc - 1usize) / 2usize
    var p = 0usize
    while p < np {
        let e = cl.decide(a, &par, x, n, nf, alpha[p * n..(p + 1usize) * n], 0.0f64, xt, nt, one)
        if e != ok { ret e }
        var t = 0usize
        while t < nt {
            dec[p * nt + t] = one[t]
            t += 1usize
        }
        p += 1usize
    }
    ret ok
}

// type = "response": votes[i] for ret > 0, votes[j] for ret < 0, the first maximum; resp is 1-based
fn respond(dec: []const f64, kc: usize, nt: usize, resp: []usize) {
    var t = 0usize
    while t < nt {
        var best = 0usize
        var bestv = 0.0f64 - 1.0f64
        var c = 0usize
        while c < kc {
            var v = 0.0f64
            var p = 0usize
            var i = 0usize
            while i + 1usize < kc {
                var j = i + 1usize
                while j < kc {
                    let d = dec[p * nt + t]
                    if i == c && d > 0.0f64 { v += 1.0f64 }
                    if j == c && d < 0.0f64 { v += 1.0f64 }
                    p += 1usize
                    j += 1usize
                }
                i += 1usize
            }
            if v > bestv {
                bestv = v
                best = c
            }
            c += 1usize
        }
        resp[t] = best + 1usize
        t += 1usize
    }
}

// type = "probabilities": out is nt by kc row-major, the pairwise 1 / (1 + exp(-ret)) coupled by which (0 minpair, 1 pkpd, 2 vote)
fn probabilities(a: *mem.Arena, dec: []const f64, kc: usize, nt: usize, which: usize, out: []f64) -> err {
    let np = kc * (kc - 1usize) / 2usize
    let (row, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret Fail }
    var t = 0usize
    while t < nt {
        let start = mem.mark(a)
        var p = 0usize
        while p < np {
            row[p] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - dec[p * nt + t]))
            p += 1usize
        }
        let e = cl.couple(a, row, kc, which, out[t * kc..(t + 1usize) * kc])
        if e != ok { ret e }
        mem.reset(a, start)
        t += 1usize
    }
    ret ok
}
