// e.algo.stat.cubist against Cubist: the rules, their linear models, the committees, the usage table, the evaluation on the training data and
// predict at 0 to 9 neighbors. tests/oracle/cubist.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cubist`;
// the layout of the arguments is at the top of scripts/r_oracle/groups/cubist.R.

use e.algo.stat.cubist as cu
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn alloc_f(a: *mem.Arena, n: usize) -> []f64 {
    let (v, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { os.exit(4) }
    ret v[0usize..n]
}

fn alloc_u(a: *mem.Arena, n: usize) -> []usize {
    let (v, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { os.exit(4) }
    ret v[0usize..n]
}

// a column of numbers is sent as hundredths; a factor as its codes
fn fill(x: []const f64, at: usize, kind: usize, n: usize, dst: []f64, col: usize) {
    var i = 0usize
    while i < n {
        let v = x[at + i]
        if kind == 0usize {
            dst[col * n + i] = v / 100.0f64
        } else {
            dst[col * n + i] = v
        }
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    var cfg: cu.Cfg = zero
    cfg.committees = usize(x[2usize])
    cfg.unbiased = x[3usize] != 0.0f64
    cfg.maxrules = i64(x[4usize])
    cfg.extrap = x[5usize]
    cfg.sample = x[6usize]
    cfg.seed = i64(x[7usize])
    cfg.maxd = x[8usize]
    cfg.nn = 1i64
    let nb = i64(x[9usize])
    let nq = usize(x[10usize])
    var d: cu.Data = zero
    d.n = n
    d.p = p
    d.kind = alloc_u(a, p)
    d.nlev = alloc_u(a, p)
    var j = 0usize
    while j < p {
        d.kind[j] = usize(x[11usize + j])
        d.nlev[j] = usize(x[11usize + p + j])
        j += 1usize
    }
    d.x = alloc_f(a, n * p)
    d.y = alloc_f(a, n)
    var at = 11usize + 2usize * p
    j = 0usize
    while j < p {
        fill(x, at, d.kind[j], n, d.x, j)
        at += n
        j += 1usize
    }
    j = 0usize
    while j < n {
        d.y[j] = x[at + j] / 100.0f64
        j += 1usize
    }
    at += n
    var q: cu.Data = zero
    q.n = nq
    q.p = p
    q.kind = d.kind
    q.nlev = d.nlev
    q.x = alloc_f(a, nq * p)
    q.y = alloc_f(a, nq)
    j = 0usize
    while j < p {
        fill(x, at, d.kind[j], nq, q.x, j)
        at += nq
        j += 1usize
    }
    var kr: cu.Kr = zero
    var fit: cu.Cb = zero
    let e = cu.cb_fit(a, &fit, &d, &cfg, &kr)
    if e != ok { os.exit(5) }
    if str.eq(c.name, "maxd") { ret cu.cb_rt_fix(a, fit.maxd, 1i64) }
    var rd: cu.Cb = zero
    let e2 = cu.cb_read_model(a, &fit, &rd)
    if e2 != ok { os.exit(6) }
    var sums = alloc_f(a, 8usize)
    cu.cb_model_sums(a, &rd, sums)
    if str.eq(c.name, "nrules") { ret sums[0usize] }
    if str.eq(c.name, "cover") { ret sums[1usize] }
    if str.eq(c.name, "mean") { ret sums[2usize] }
    if str.eq(c.name, "lohi") { ret sums[3usize] }
    if str.eq(c.name, "esterr") { ret sums[4usize] }
    if str.eq(c.name, "cond") { ret sums[5usize] }
    if str.eq(c.name, "cut") { ret sums[6usize] }
    if str.eq(c.name, "coef") { ret sums[7usize] }
    if str.eq(c.name, "usage_c") || str.eq(c.name, "usage_m") {
        let w = fit.w
        var u = alloc_f(a, 2usize * w)
        cu.cb_usage(a, &fit, u)
        var s = 0.0f64
        var k = 2usize
        while k <= fit.na {
            if str.eq(c.name, "usage_c") { s += f64(k - 1usize) * u[k] } else { s += f64(k - 1usize) * u[w + k] }
            k += 1usize
        }
        ret s
    }
    if str.starts_with(c.name, "eval") {
        var ev = alloc_f(a, 3usize)
        cu.cb_evaluate(&fit, ev)
        if str.eq(c.name, "eval_err") { ret cu.cb_rt_fix(a, ev[0usize], fit.prec + 1i64) }
        if str.eq(c.name, "eval_rel") { ret cu.cb_rt_fix(a, ev[1usize], 2i64) }
        ret cu.cb_rt_fix(a, ev[2usize], 2i64)
    }
    var pr = alloc_f(a, nq)
    let e3 = cu.cb_predict(a, &rd, &d, &q, nb, &kr, pr)
    if e3 != ok { os.exit(7) }
    var s = 0.0f64
    var k = 0usize
    while k < nq {
        s += pr[k] * f64(k + 1usize)
        k += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cubist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 90usize {
                let (b0, be) = str.builder(a, 200usize)
                var b = b0
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " #")
                let _ = str.push_usize(&b, at)
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " R ")
                let _ = str.push_f64(&b, c.want)
                let _ = str.push(&b, "\n")
                let _ = io.print(str.done(&b))
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
