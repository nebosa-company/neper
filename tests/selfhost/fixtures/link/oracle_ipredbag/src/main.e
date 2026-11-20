// e.algo.stat.ipredbag against ipred 0.9-16 under set.seed. tests/oracle/ipredbag.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ipredbag`; the case layout is at the top of scripts/r_oracle/groups/ipredbag.R.

use e.algo.rand.r as rng
use e.algo.stat.ipredbag as ib
use e.algo.stat.rpartfull as rf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

error Bad

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn put(outs: [][]f64, i: usize, v: []f64) {
    outs[i] = v
}

// bagging: the order of the calls is the order of the R script (each predict that breaks a tie draws)
fn scn_bag(a: *mem.Arena, x: []const f64, outs: [][]f64) -> err {
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let k = usize(x[3usize])
    let nbagg = usize(x[4usize])
    let ns = usize(x[5usize])
    let coob = x[6usize] != 0.0f64
    let (ctl, ec) = rf.rp_control(x[7usize], x[8usize], x[9usize], nan(), nan(), nan(), nan(), x[10usize], 0.0f64)
    if ec != ok { ret ec }
    let seed = i64(x[11usize])
    let nn = usize(x[12usize])
    var at = 13usize
    let (ncat, e1) = mem.alloc[usize](a, p + 1usize)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p {
        ncat[i] = usize(x[at + i])
        i += 1usize
    }
    at += p
    var d: ib.Data = zero
    d.n = n
    d.p = p
    d.k = k
    d.ncat = ncat
    d.y = x[at..at + n]
    at += n
    d.x = x[at..at + n * p]
    at += n * p
    let newx = x[at..at + nn * p]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (dc, en) = ib.na_omit(a, &d)
    if en != ok { ret en }
    var nsz = ns
    if ns == 0usize { nsz = dc.n }
    let (b, eb) = ib.bag_fit(a, &g, &dc, nbagg, nsz, ctl, coob)
    if eb != ok { ret eb }
    let (bi, e2) = mem.alloc[f64](a, nbagg * b.ns)
    if e2 != ok { ret e2 }
    let (sz, e3) = mem.alloc[f64](a, nbagg)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < nbagg * b.ns {
        bi[i] = f64(b.bindx[i] + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < nbagg {
        sz[i] = f64(b.trees[i].nfr)
        i += 1usize
    }
    put(outs, 1usize, bi)
    put(outs, 2usize, sz)
    if coob {
        let (o, e4) = mem.alloc[f64](a, 1usize)
        if e4 != ok { ret e4 }
        o[0usize] = b.oob
        put(outs, 3usize, o)
    }
    var slot = 4usize
    var pass = 0usize
    while pass < 2usize {
        let oob = pass == 1usize
        if oob && nbagg < 10usize { break }
        let xs = newx
        var nrow = nn
        if oob { nrow = dc.n }
        var agg = 0usize
        while agg < 3usize {
            if k > 0usize {
                let (cl, e5) = ib.bag_predict(a, &g, &b, select(oob, dc.x, xs), nrow, oob, agg, false)
                if e5 != ok { ret e5 }
                let (pr, e6) = ib.bag_predict(a, &g, &b, select(oob, dc.x, xs), nrow, oob, agg, true)
                if e6 != ok { ret e6 }
                put(outs, slot, cl)
                put(outs, slot + 1usize, pr)
                slot += 2usize
            } else if agg != 0usize {
                let (rv, e7) = ib.bag_predict(a, &g, &b, select(oob, dc.x, xs), nrow, oob, agg, false)
                if e7 != ok { ret e7 }
                put(outs, slot, rv)
                slot += 1usize
            }
            agg += 1usize
        }
        pass += 1usize
    }
    ret ok
}

fn select(c: bool, a: []const f64, b: []const f64) -> []const f64 {
    if c { ret a }
    ret b
}

fn one(a: *mem.Arena, v: f64) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, 1usize)
    if e != ok { ret (o, e) }
    o[0usize] = v
    ret (o, ok)
}

// the common data block after the header: ncat[p], y[n], x[n * p]; returns the position after it
fn load(a: *mem.Arena, x: []const f64, at0: usize, n: usize, p: usize, k: usize, d: *ib.Data) -> (usize, err) {
    var at = at0
    let (ncat, e1) = mem.alloc[usize](a, p + 1usize)
    if e1 != ok { ret (at, e1) }
    var i = 0usize
    while i < p {
        ncat[i] = usize(x[at + i])
        i += 1usize
    }
    at += p
    d.n = n
    d.p = p
    d.k = k
    d.ncat = ncat
    d.y = x[at..at + n]
    at += n
    d.x = x[at..at + n * p]
    at += n * p
    ret (at, ok)
}

// errorest
fn scn_err(a: *mem.Arena, x: []const f64, outs: [][]f64) -> err {
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let k = usize(x[3usize])
    let est = usize(x[4usize])
    var m: ib.Model = zero
    m.kind = usize(x[5usize])
    let nk = usize(x[6usize])
    let strat = x[7usize] != 0.0f64
    let random = x[8usize] != 0.0f64
    m.nbagg = usize(x[9usize])
    let (ctl, ec) = rf.rp_control(x[10usize], x[11usize], x[12usize], nan(), nan(), nan(), nan(), x[13usize], x[14usize])
    if ec != ok { ret ec }
    m.ctl = ctl
    m.knnk = usize(x[15usize])
    let seed = i64(x[16usize])
    var d: ib.Data = zero
    let (_at, el) = load(a, x, 17usize, n, p, k, &d)
    if el != ok { ret el }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    var r: ib.Est = zero
    if est == 1usize {
        let (rr, e) = ib.est_cv(a, &g, &d, &m, nk, strat, random)
        if e != ok { ret e }
        r = rr
    } else {
        let (rr, e) = ib.est_boot(a, &g, &d, &m, nk, est - 1usize)
        if e != ok { ret e }
        r = rr
    }
    let (s1, e1) = one(a, r.est)
    if e1 != ok { ret e1 }
    put(outs, 1usize, s1)
    let (s2, e2) = one(a, f64(r.nk))
    if e2 != ok { ret e2 }
    put(outs, 2usize, s2)
    var sdv = r.sd
    if est == 1usize || est == 3usize { sdv = nan() }
    let (s3, e3) = one(a, sdv)
    if e3 != ok { ret e3 }
    put(outs, 3usize, s3)
    if est == 1usize {
        put(outs, 4usize, r.pred)
    } else {
        var cs = 0.0f64
        var na = 0.0f64
        var i = 0usize
        while i < r.npred {
            if r.pred[i] == r.pred[i] { cs += r.pred[i] * f64(i + 1usize) } else { na += 1.0f64 }
            i += 1usize
        }
        let (s4, e4) = one(a, cs)
        if e4 != ok { ret e4 }
        put(outs, 4usize, s4)
        let (s6, e6) = one(a, na)
        if e6 != ok { ret e6 }
        put(outs, 6usize, s6)
    }
    var e632 = r.err632
    if est != 4usize { e632 = nan() }
    let (s5, e5) = one(a, e632)
    if e5 != ok { ret e5 }
    put(outs, 5usize, s5)
    ret ok
}

fn scn_knn(a: *mem.Arena, x: []const f64, outs: [][]f64) -> err {
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let k = usize(x[3usize])
    let kk = usize(x[4usize])
    let nn = usize(x[5usize])
    let seed = i64(x[6usize])
    var d: ib.Data = zero
    let (at, el) = load(a, x, 7usize, n, p, k, &d)
    if el != ok { ret el }
    let newx = x[at..at + nn * p]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (cl, e1) = ib.knn_predict(a, &g, &d, kk, newx, nn, false)
    if e1 != ok { ret e1 }
    let (pr, e2) = ib.knn_predict(a, &g, &d, kk, newx, nn, true)
    if e2 != ok { ret e2 }
    put(outs, 1usize, cl)
    put(outs, 2usize, pr)
    ret ok
}

// inbagg
fn scn_inb(a: *mem.Arena, x: []const f64, outs: [][]f64) -> err {
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let k = usize(x[3usize])
    let q = usize(x[4usize])
    let nbagg = usize(x[5usize])
    let nsfrac = x[6usize]
    let replace = x[7usize] != 0.0f64
    let wkind = usize(x[8usize])
    let (wctl, e1) = rf.rp_control(x[10usize], nan(), nan(), nan(), nan(), nan(), nan(), nan(), x[9usize])
    if e1 != ok { ret e1 }
    let wtrain = usize(x[11usize])
    let (cctl, e2) = rf.rp_control(x[12usize], x[13usize], x[14usize], nan(), nan(), nan(), nan(), x[15usize], 0.0f64)
    if e2 != ok { ret e2 }
    let seed = i64(x[16usize])
    let nn = usize(x[17usize])
    var d: ib.Data = zero
    let (at, el) = load(a, x, 18usize, n, p, k, &d)
    if el != ok { ret el }
    let w = x[at..at + n * q]
    let newx = x[at + n * q..at + n * q + nn * p]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (m, em) = ib.inb_fit(a, &g, &d, w, q, nbagg, nsfrac, replace, wkind, wctl, wtrain, cctl)
    if em != ok { ret em }
    let (bi, e3) = mem.alloc[f64](a, nbagg * m.ns)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < nbagg * m.ns {
        bi[i] = f64(m.bindx[i] + 1usize)
        i += 1usize
    }
    put(outs, 1usize, bi)
    let (sz, e4) = mem.alloc[f64](a, nbagg)
    if e4 != ok { ret e4 }
    let (iv, e5) = mem.alloc[f64](a, nbagg * nn * q)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < nbagg {
        sz[i] = f64(m.trees[i].nfr)
        let (wn, ew) = ib.inb_intermed(a, &m, i, newx, nn)
        if ew != ok { ret ew }
        var j = 0usize
        while j < nn * q {
            iv[i * nn * q + j] = wn[j]
            j += 1usize
        }
        i += 1usize
    }
    put(outs, 2usize, sz)
    put(outs, 3usize, iv)
    let (pr, ep) = ib.inb_predict(a, &g, &m, newx, nn)
    if ep != ok { ret ep }
    put(outs, 4usize, pr)
    ret ok
}

fn report(a: *mem.Arena, at: usize, what: str, got: f64, c: *const oracle.Case) {
    let _ = io.print(oracle.describe(a, c, got))
    let _ = io.print("\n")
}

// one dataset case and the "bl" / "bq" cases after it; returns the index of the next dataset case
fn run_dataset(a: *mem.Arena, golden: *const oracle.Golden, start: usize, failures: *usize) -> usize {
    let base = mem.mark(a)
    let c0 = &golden.cases[start]
    let (outs, eo) = mem.alloc[[]f64](a, 16usize)
    if eo != ok { os.exit(4) }
    var emp: []f64 = zero
    var i = 0usize
    while i < 16usize {
        outs[i] = emp
        i += 1usize
    }
    var ec = ok
    let scn = usize(c0.args[0usize])
    if scn == 1usize { ec = scn_bag(a, c0.args, outs) }
    if scn == 2usize { ec = scn_err(a, c0.args, outs) }
    if scn == 3usize { ec = scn_knn(a, c0.args, outs) }
    if scn == 4usize { ec = scn_inb(a, c0.args, outs) }
    if ec != ok { os.exit(5) }
    var at = start + 1usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        if str.eq(c.name, "ds") { break }
        let sl = usize(c.args[0usize])
        var got = nan()
        if str.eq(c.name, "bl") { got = f64(outs[sl].len) }
        if str.eq(c.name, "bq") {
            let j = usize(c.args[1usize])
            if j < outs[sl].len { got = outs[sl][j] }
        }
        if !oracle.agrees(got, c) {
            *failures += 1usize
            if *failures <= 12usize {
                let (sb, se) = str.builder(a, 64usize)
                if se == ok {
                    var bb = sb
                    let _ = str.push(&bb, "ds@")
                    let _ = str.push_usize(&bb, start)
                    let _ = str.push(&bb, " ")
                    let _ = io.print(str.done(&bb))
                }
                report(a, at, c.name, got, c)
            }
        }
        at += 1usize
    }
    mem.reset(a, base)
    ret at
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ipredbag.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        at = run_dataset(a, &golden, at, &failures)
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
