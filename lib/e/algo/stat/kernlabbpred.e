// R kernlab ksvm: the one-against-one C-bsvc driver and the predictions of C-bsvc (voting), spoc-svc and kbb-svc, on the solvers of kernlabbsvm. The rows of x
// are grouped by class in order, cls the 0-based class of each row.

use e.algo.stat.kernlabbsvm as bs
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabsvm as ks
use e.mem

error Fail

// pairs (1,2), (1,3), ...; coef (npair by n, 0 off the support vectors, alpha * y), bout = -sum(coef), obj per pair
fn bsvc_pairs(a: *mem.Arena, x: []const f64, n: usize, nf: usize, cls: []const usize, kc: usize, par: *const ks.Param, lam: *f64, coef: []f64, bout: []f64, obj: []f64) -> err {
    var p = 0usize
    var i = 0usize
    while i < kc * (kc - 1usize) / 2usize * n {
        coef[i] = 0.0f64
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
            let (out, e4) = mem.alloc[f64](a, m)
            if e2 != ok || e3 != ok || e4 != ok { ret Fail }
            var q = 0usize
            while q < m {
                var k = 0usize
                while k < nf {
                    xs[q * nf + k] = x[idx[q] * nf + k]
                    k += 1usize
                }
                yd[q] = 1.0f64
                if q < li { yd[q] = 0.0f64 - 1.0f64 }
                q += 1usize
            }
            let (ob, e5) = bs.bsvc(a, xs, m, nf, yd, par, lam, out)
            if e5 != ok { ret e5 }
            var sum = 0.0f64
            q = 0usize
            while q < m {
                let v = out[q] * yd[q]
                coef[p * n + idx[q]] = v
                if out[q] > 0.0f64 { sum += v }
                q += 1usize
            }
            bout[p] = 0.0f64 - sum
            obj[p] = ob
            mem.reset(a, start)
            p += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// voting prediction of the pairwise problems; resp gets the 1-based classes
fn predict_pairs(a: *mem.Arena, par: *const ks.Param, x: []const f64, n: usize, nf: usize, coef: []const f64, b: []const f64, kc: usize, xt: []const f64, nt: usize, resp: []usize) -> err {
    let np = kc * (kc - 1usize) / 2usize
    let (dec, e1) = mem.alloc[f64](a, np * nt)
    let (one, e2) = mem.alloc[f64](a, nt)
    let (row, e3) = mem.alloc[f64](a, np)
    let (votes, e4) = mem.alloc[f64](a, kc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Fail }
    var p = 0usize
    while p < np {
        let e = cl.decide(a, par, x, n, nf, coef[p * n..(p + 1usize) * n], b[p], xt, nt, one)
        if e != ok { ret e }
        var t = 0usize
        while t < nt {
            dec[p * nt + t] = one[t]
            t += 1usize
        }
        p += 1usize
    }
    var t = 0usize
    while t < nt {
        p = 0usize
        while p < np {
            row[p] = dec[p * nt + t]
            p += 1usize
        }
        resp[t] = cl.vote_row(row, kc, votes) + 1usize
        t += 1usize
    }
    ret ok
}

fn argmax(v: []const f64, k: usize) -> usize {
    var best = 0usize
    var i = 1usize
    while i < k {
        if v[i] > v[best] { best = i }
        i += 1usize
    }
    ret best
}

// spoc-svc: alpha is n by kc row-major; the class of a test row is the first maximum of sum_j alpha[j, c] k(new, x_j)
fn predict_spoc(a: *mem.Arena, par: *const ks.Param, x: []const f64, n: usize, nf: usize, alpha: []const f64, kc: usize, xt: []const f64, nt: usize, resp: []usize) -> err {
    let (col, e1) = mem.alloc[f64](a, n)
    let (one, e2) = mem.alloc[f64](a, nt)
    let (vm, e3) = mem.alloc[f64](a, kc * nt)
    let (row, e4) = mem.alloc[f64](a, kc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Fail }
    var c = 0usize
    while c < kc {
        var j = 0usize
        while j < n {
            col[j] = alpha[j * kc + c]
            j += 1usize
        }
        let e = cl.decide(a, par, x, n, nf, col, 0.0f64, xt, nt, one)
        if e != ok { ret e }
        var t = 0usize
        while t < nt {
            vm[c * nt + t] = one[t]
            t += 1usize
        }
        c += 1usize
    }
    var t = 0usize
    while t < nt {
        c = 0usize
        while c < kc {
            row[c] = vm[c * nt + t]
            c += 1usize
        }
        resp[t] = argmax(row, kc) + 1usize
        t += 1usize
    }
    ret ok
}

// votes[tg] += sign * (sum_j w[j] k(new, x_j) + sum_j w[j])
fn kbb_acc(a: *mem.Arena, par: *const ks.Param, x: []const f64, n: usize, nf: usize, w: []const f64, xt: []const f64, nt: usize, one: []f64, vm: []f64, tg: usize, sign: f64) -> err {
    let e = cl.decide(a, par, x, n, nf, w, 0.0f64, xt, nt, one)
    if e != ok { ret e }
    var sw = 0.0f64
    var j = 0usize
    while j < n {
        sw += w[j]
        j += 1usize
    }
    var t = 0usize
    while t < nt {
        vm[tg * nt + t] = vm[tg * nt + t] + sign * (one[t] + sw)
        t += 1usize
    }
    ret ok
}

// the weight vector of class i's rows from alpha column q (zero on the other rows)
fn kbb_col(alpha: []const f64, n: usize, k1: usize, q: usize, cls: []const usize, i: usize, col: []f64) {
    var j = 0usize
    while j < n {
        col[j] = 0.0f64
        if cls[j] == i { col[j] = alpha[j * k1 + q] }
        j += 1usize
    }
}

// kbb-svc: alpha is n by (kc - 1) row-major
fn predict_kbb(a: *mem.Arena, par: *const ks.Param, x: []const f64, n: usize, nf: usize, alpha: []const f64, cls: []const usize, kc: usize, xt: []const f64, nt: usize, resp: []usize) -> err {
    let k1 = kc - 1usize
    let (col, e1) = mem.alloc[f64](a, n)
    let (one, e2) = mem.alloc[f64](a, nt)
    let (vm, e3) = mem.alloc[f64](a, kc * nt)
    let (row, e4) = mem.alloc[f64](a, kc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Fail }
    var i = 0usize
    while i < kc * nt {
        vm[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < kc {
        var k = 0usize
        while k < i {
            kbb_col(alpha, n, k1, k, cls, i, col)
            let e = kbb_acc(a, par, x, n, nf, col, xt, nt, one, vm, k, 0.0f64 - 1.0f64)
            if e != ok { ret e }
            k += 1usize
        }
        var j = 0usize
        while j < n {
            col[j] = 0.0f64
            if cls[j] == i {
                var s = 0.0f64
                var q = 0usize
                while q < k1 {
                    s += alpha[j * k1 + q]
                    q += 1usize
                }
                col[j] = s
            }
            j += 1usize
        }
        let e1b = kbb_acc(a, par, x, n, nf, col, xt, nt, one, vm, i, 1.0f64)
        if e1b != ok { ret e1b }
        var kk = i
        while kk < k1 {
            kbb_col(alpha, n, k1, kk, cls, i, col)
            let e = kbb_acc(a, par, x, n, nf, col, xt, nt, one, vm, kk + 1usize, 0.0f64 - 1.0f64)
            if e != ok { ret e }
            kk += 1usize
        }
        i += 1usize
    }
    var t = 0usize
    while t < nt {
        var c = 0usize
        while c < kc {
            row[c] = vm[c * nt + t]
            c += 1usize
        }
        resp[t] = argmax(row, kc) + 1usize
        t += 1usize
    }
    ret ok
}
