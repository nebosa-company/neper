// e.algo.stat.rpartfull against rpart 4.1.27. tests/oracle/rpartfull_*.json come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rpartfull_a` (and _b, _c, _d); the layout is at the top of scripts/r_oracle/groups/rpartfull_a.R.

use e.algo.stat.rpartfull as rf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn ckf(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn cku(v: []const usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn cki(v: []const i64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// the header of a dataset case, then parms, ncat, cost, wt, y (row-major), x (column-major)
fn build(a: *mem.Arena, x: []const f64, t: *rf.Fit, v: *rf.View) -> err {
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let method = usize(x[3usize])
    let ny = usize(x[4usize])
    let kc = usize(x[5usize])
    let np = usize(x[6usize])
    let (ctl, ec) = rf.rp_control(x[7usize], x[8usize], x[9usize], x[10usize], x[11usize], x[12usize], x[13usize], x[14usize], x[15usize])
    if ec != ok { ret ec }
    var at = 17usize
    let parms = x[at..at + np]
    at += np
    let (ncat, e1) = mem.alloc[usize](a, p + 1usize)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < p {
        ncat[i] = usize(x[at + i])
        i += 1usize
    }
    at += p
    let cost = x[at..at + p]
    at += p
    let wt = x[at..at + n]
    at += n
    let y = x[at..at + n * ny]
    at += n * ny
    let xm = x[at..at + n * p]
    var xg: []usize = zero
    let nx = usize(ctl.xval)
    if nx > 1usize {
        let (g, eg) = rf.rp_xgroups(a, i64(x[16usize]), n, nx)
        if eg != ok { ret eg }
        xg = g
    }
    let (fit, ef) = rf.rp_fit(a, xm, n, p, ncat, y, ny, wt, cost, method, kc, parms, ctl, xg)
    if ef != ok { ret ef }
    *t = fit
    let (view, ev) = rf.rp_view(a, t)
    if ev != ok { ret ev }
    *v = view
    ret ok
}

fn query(a: *mem.Arena, c: *const oracle.Case, t: *rf.Fit, v: *rf.View, what: usize) -> f64 {
    let x = c.args
    let nr = v.nfr
    if what == 1usize { ret f64(v.ncp) }
    if what == 2usize { ret ckf(v.cp_cp, v.ncp) }
    if what == 3usize { ret ckf(v.cp_nsplit, v.ncp) }
    if what == 4usize { ret ckf(v.cp_rel, v.ncp) }
    if what == 5usize { ret ckf(v.cp_x, v.ncp) }
    if what == 6usize { ret ckf(v.cp_xs, v.ncp) }
    if what == 10usize { ret f64(nr) }
    if what == 11usize { ret cki(v.id, nr) }
    if what == 12usize { ret cku(v.fn_, nr) }
    if what == 13usize { ret ckf(v.fwt, nr) }
    if what == 14usize { ret ckf(v.fdev, nr) }
    if what == 15usize { ret ckf(v.fyval, nr) }
    if what == 16usize { ret ckf(v.fcplx, nr) }
    if what == 17usize { ret cku(v.fncomp, nr) }
    if what == 18usize { ret cku(v.fnsur, nr) }
    if what == 19usize { ret cku(v.fvar, nr) }
    if what == 20usize { ret ckf(v.y2, nr * v.y2w) }
    if what == 30usize { ret f64(v.nsp) }
    if what == 31usize { ret ckf(v.sp_count, v.nsp) }
    if what == 32usize { ret cki(v.sp_ncat, v.nsp) }
    if what == 33usize { ret ckf(v.sp_imp, v.nsp) }
    if what == 34usize { ret ckf(v.sp_index, v.nsp) }
    if what == 35usize { ret ckf(v.sp_adj, v.nsp) }
    if what == 36usize { ret cku(v.sp_var, v.nsp) }
    if what == 37usize {
        var s = 0.0f64
        var i = 0usize
        while i < v.ncs * v.maxcat {
            s += f64(v.cs[i] + 2i64) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if what == 40usize { ret cku(v.wh, v.nobs) }
    if what == 50usize { ret f64(v.nimp) }
    if what == 51usize { ret ckf(v.imp_val, v.nimp) }
    if what == 52usize { ret cku(v.imp_var, v.nimp) }
    if what == 70usize { ret v.fdev[0usize] / f64(v.fn_[0usize]) }
    if what == 71usize {
        var seen = 0.0f64
        var s = 0.0f64
        var vv = 1usize
        while vv <= v.p {
            var used = false
            var r = 0usize
            while r < nr {
                if v.fvar[r] == vv { used = true }
                r += 1usize
            }
            if used {
                seen += 1.0f64
                s += f64(vv)
            }
            vv += 1usize
        }
        ret seen * 1000.0f64 + s
    }
    if what == 65usize || what == 66usize || what == 67usize || what == 68usize {
        var s = 0.0f64
        var i = 0usize
        while i < v.nobs {
            let row = v.wh[i] - 1usize
            if what == 65usize { s += v.fyval[row] * f64(i + 1usize) }
            if what == 66usize {
                var cc = 0usize
                while cc < v.k {
                    s += v.y2[row * v.y2w + 1usize + v.k + cc] * f64(i * v.k + cc + 1usize)
                    cc += 1usize
                }
            }
            if what == 67usize {
                var cc = 0usize
                while cc < v.y2w {
                    s += v.y2[row * v.y2w + cc] * f64(i * v.y2w + cc + 1usize)
                    cc += 1usize
                }
            }
            if what == 68usize { s += v.fyval[row] * f64(i + 1usize) }
            i += 1usize
        }
        ret s
    }
    if what >= 60usize && what < 65usize {
        // predict on new data: extras are nn and the matrix
        let nn = usize(x[2usize])
        let xn = x[3usize..3usize + nn * v.p]
        var s = 0.0f64
        var i = 0usize
        while i < nn {
            let row = rf.rp_predict_row(v, xn, nn, i)
            if what == 60usize { s += v.fyval[row] * f64(i + 1usize) }
            if what == 61usize { s += f64(row + 1usize) * f64(i + 1usize) }
            if what == 62usize {
                var cc = 0usize
                while cc < v.k {
                    s += v.y2[row * v.y2w + 1usize + v.k + cc] * f64(i * v.k + cc + 1usize)
                    cc += 1usize
                }
            }
            if what == 63usize { s += v.fyval[row] * f64(i + 1usize) }
            if what == 64usize {
                var cc = 0usize
                while cc < v.y2w {
                    s += v.y2[row * v.y2w + cc] * f64(i * v.y2w + cc + 1usize)
                    cc += 1usize
                }
            }
            i += 1usize
        }
        ret s
    }
    os.exit(9)
    ret 0.0f64
}

fn control_check(c: *const oracle.Case) -> f64 {
    let x = c.args
    let (ctl, ec) = rf.rp_control(x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize], x[9usize])
    if ec != ok { ret 0.0f64 - 1.0f64 }
    ret ctl.minsplit + 10.0f64 * ctl.minbucket + 100.0f64 * ctl.cp + 1000.0f64 * ctl.maxcompete + 10000.0f64 * ctl.maxsurrogate + 100000.0f64 * ctl.usesurrogate + 1000000.0f64 * ctl.surrogatestyle + 10000000.0f64 * ctl.maxdepth + 100000000.0f64 * ctl.xval
}

fn report(a: *mem.Arena, at: usize, what: usize, got: f64, want: f64) {
    let (ib, eb2) = str.builder(a, 160usize)
    if eb2 == ok {
        var b = ib
        let _ = str.push(&b, "case ")
        let _ = str.push_usize(&b, at)
        let _ = str.push(&b, " what ")
        let _ = str.push_usize(&b, what)
        let _ = str.push(&b, ": got ")
        let _ = str.push_f64(&b, got)
        let _ = str.push(&b, " want ")
        let _ = str.push_f64(&b, want)
        let _ = str.push(&b, "\n")
        let _ = io.print(str.done(&b))
    }
}

// one dataset case and the query cases after it; the fit lives until the next dataset case. Returns the index of the next dataset case.
fn run_dataset(a: *mem.Arena, golden: *const oracle.Golden, start: usize, failures: *usize) -> usize {
    var t: rf.Fit = zero
    var v: rf.View = zero
    let base = mem.mark(a)
    let c0 = &golden.cases[start]
    let eb = build(a, c0.args, &t, &v)
    if eb != ok { os.exit(5) }
    if !oracle.agrees(f64(v.nfr), c0) {
        *failures += 1usize
        report(a, start, 0usize, f64(v.nfr), c0.want)
    }
    var at = start + 1usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let what = usize(c.args[0usize])
        if what == 0usize { break }
        let qm = mem.mark(a)
        var got = 0.0f64
        if what == 80usize {
            got = control_check(c)
        } else {
            let cpv = c.args[1usize]
            if cpv > 0.0f64 {
                let (vp, ep) = rf.rp_prune(a, &v, cpv)
                if ep != ok { os.exit(6) }
                var mut_vp = vp
                got = query(a, c, &t, &mut_vp, what)
            } else {
                got = query(a, c, &t, &v, what)
            }
        }
        if !oracle.agrees(got, c) {
            *failures += 1usize
            if *failures <= 12usize { report(a, at, what, got, c.want) }
        }
        mem.reset(a, qm)
        at += 1usize
    }
    mem.reset(a, base)
    ret at
}

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let wh = usize(golden.cases[at].args[0usize])
        if wh == 80usize {
            let c = &golden.cases[at]
            if !oracle.agrees(control_check(c), c) {
                failures += 1usize
                report(a, at, 80usize, control_check(c), c.want)
            }
            at += 1usize
        } else {
            at = run_dataset(a, &golden, at, &failures)
        }
    }
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    var failures = 0usize
    failures += run(a, "tests/oracle/rpartfull_a.json")
    failures += run(a, "tests/oracle/rpartfull_b.json")
    if failures > 0usize { os.exit(1) }
    ret ok
}
