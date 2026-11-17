// e.algo.stat.gbmr (over gbmfit) against gbm. tests/oracle/gbm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gbm`; the case layout is at the top of
// scripts/r_oracle/groups/gbm.R. Every data set is rebuilt here from its seed with the same R generator draws, fitted once, and then every case of that configuration reads one number off the fit.

use e.algo.rand.r as rng
use e.algo.stat.gbmfit as gb
use e.algo.stat.gbmr as gr
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn r3(x: f64, d: f64) -> f64 { ret math.floor[f64](x * d + 0.5f64) / d }

type Data = struct { x: []f64, y: []f64, st: []f64, w: []f64 }

fn make(a: *mem.Arena, seed: i64, dist: usize, n: usize, p: usize, wflag: bool, na: bool) -> (Data, err) {
    var rg: rng.Rng = zero
    rng.seed(&rg, seed)
    var bad = 0usize
    var d = Data{ x: gb.af(a, n * p, &bad), y: gb.af(a, n, &bad), st: gb.af(a, n, &bad), w: gb.af(a, n, &bad) }
    if bad != 0usize { ret (d, gb.NoMemory) }
    var i = 0usize
    while i < n * p {
        d.x[i] = r3(rng.norm(&rg), 1000.0f64)
        i += 1usize
    }
    i = 0usize
    if dist == 0usize {
        while i < n {
            d.y[i] = r3(math.sin[f64](2.0f64 * d.x[i]) + d.x[n + i] * d.x[n + i] * 0.5f64 + rng.rnorm(&rg, 0.0f64, 0.3f64), 1000.0f64)
            i += 1usize
        }
    } else if dist == 1usize || dist == 3usize || dist == 6usize {
        while i < n {
            let lin = 1.5f64 * d.x[i] - d.x[n + i]
            let u = rng.unif(&rg)
            if u < 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - lin)) {
                d.y[i] = 1.0f64
            } else {
                d.y[i] = 0.0f64
            }
            i += 1usize
        }
    } else if dist == 2usize {
        while i < n {
            d.y[i] = math.floor[f64](rng.unif(&rg) * 3.0f64 * math.exp[f64](0.6f64 * d.x[i]))
            i += 1usize
        }
    } else if dist == 4usize || dist == 5usize {
        while i < n {
            d.y[i] = r3(2.0f64 * d.x[i] + rng.rexp(&rg, 1.0f64), 10000.0f64)
            i += 1usize
        }
    } else if dist == 7usize {
        while i < n {
            d.y[i] = r3(math.sin[f64](2.0f64 * d.x[i]) + d.x[n + i] * d.x[n + i] * 0.5f64 + rng.rnorm(&rg, 0.0f64, 0.3f64), 1000.0f64)
            i += 1usize
        }
        i = 0usize
        while i < n {
            if rng.unif(&rg) < 0.1f64 { d.y[i] += 4.0f64 }
            i += 1usize
        }
    } else if dist == 8usize {
        while i < n {
            d.y[i] = r3(rng.rexp(&rg, 1.0f64) / math.exp[f64](0.7f64 * d.x[i]), 1000.0f64) + 0.001f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            if rng.unif(&rg) < 0.8f64 {
                d.st[i] = 1.0f64
            } else {
                d.st[i] = 0.0f64
            }
            i += 1usize
        }
    } else if dist == 9usize {
        while i < n {
            let u = d.x[i] + rng.norm(&rg) * 0.7f64
            if u < 0.0f64 - 0.5f64 {
                d.y[i] = 0.0f64
            } else if u < 0.5f64 {
                d.y[i] = 1.0f64
            } else {
                d.y[i] = 2.0f64
            }
            i += 1usize
        }
    }
    if wflag {
        i = 0usize
        while i < n {
            d.w[i] = 0.5f64 * (1.0f64 + math.floor[f64](4.0f64 * rng.unif(&rg)))
            i += 1usize
        }
    }
    if na {
        i = 0usize
        while i < n * p {
            if rng.unif(&rg) < 0.08f64 { d.x[i] = 0.0f64 / 0.0f64 }
            i += 1usize
        }
    }
    ret (d, ok)
}

fn same_config(x: []const f64, y: []const f64) -> bool {
    var i = 0usize
    while i < 17usize {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// the number a case asks for, read off the fit f and the new rows dn (12 by p)
fn output(a: *mem.Arena, f: *const gr.Fitted, dn: []const f64, z: []const f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let code = usize(z[17usize])
    let ia = usize(z[18usize])
    let ib = usize(z[19usize])
    let ic = usize(z[20usize])
    let p = usize(z[3usize])
    let n = usize(z[2usize])
    let nn = 12usize
    if code == 1usize { ret f.fit[ia + ic * n] }
    if code == 2usize { ret f.m.train_err[ia] }
    if code == 3usize { ret f.m.valid_err[ia] }
    if code == 4usize { ret f.m.oobag[ia] }
    if code == 6usize { ret f.m.initf }
    if code == 9usize { ret gb.rsum(f.m.train_err, f.m.ntrees) }
    if code == 10usize { ret gb.rsum(f.m.valid_err, f.m.ntrees) }
    if code == 11usize { ret gb.rsum(f.m.oobag, f.m.ntrees) }
    if code == 12usize { ret f.cv_error[ia] }
    if code == 13usize { ret f.cv_fitted[ia] }
    if code == 14usize {
        if ia == 1usize { ret f64(gr.best_iter_test(f)) }
        ret f64(gr.best_iter_cv(f))
    }
    if code == 5usize || code == 15usize {
        let (inf, e) = mem.alloc[f64](a, p)
        if e != ok { ret nan }
        var nt = ib
        if code == 15usize { nt = gr.default_trees(f) }
        if gr.relative_influence(a, f, nt, inf) != ok { ret nan }
        ret inf[ia]
    }
    if code == 7usize || code == 8usize || code == 16usize {
        let (po, e) = mem.alloc[f64](a, nn * f.nclass)
        if e != ok { ret nan }
        var nt = ib
        if code == 16usize { nt = gr.default_trees(f) }
        gr.predict(f, dn, nn, nt, po)
        if code == 8usize { gr.to_response(f.dist, f.nclass, nn, po) }
        ret po[ia + ic * nn]
    }
    if code == 30usize || code == 31usize {
        var vars: [3]usize = zero
        var nv = 1usize
        if ic < 10usize {
            vars[0usize] = ic - 1usize
        } else if ic < 100usize {
            nv = 2usize
            vars[0usize] = ic / 10usize - 1usize
            vars[1usize] = ic % 10usize - 1usize
        } else {
            nv = 3usize
            vars[0usize] = ic / 100usize - 1usize
            vars[1usize] = (ic / 10usize) % 10usize - 1usize
            vars[2usize] = ic % 10usize - 1usize
        }
        var res = 20usize
        if nv == 2usize { res = 7usize }
        if nv == 3usize { res = 4usize }
        var rows = res
        if nv == 2usize { rows = 49usize }
        if nv == 3usize { rows = 64usize }
        let (po, e) = mem.alloc[f64](a, rows * f.nclass)
        if e != ok { ret nan }
        if gr.plot_grid(a, f, vars[0usize..nv], nv, res, ib, po) != ok { ret nan }
        if code == 31usize { gr.to_response(f.dist, f.nclass, rows, po) }
        ret po[ia]
    }
    if code >= 20usize && code <= 27usize {
        let at = (ib - 1usize) * f.m.stride + ia
        if code == 20usize { ret f64(f.m.tvar[at]) }
        if code == 21usize { ret f.m.tcode[at] }
        if code == 22usize { ret f64(f.m.tleft[at]) }
        if code == 23usize { ret f64(f.m.tright[at]) }
        if code == 24usize { ret f64(f.m.tmiss[at]) }
        if code == 25usize { ret f.m.terr[at] }
        if code == 26usize { ret f.m.twt[at] }
        ret f.m.tpred[at]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gbm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var shown = 0usize
    var last_bad = 0.0f64 - 1.0f64
    var errors = 0usize
    var at = 0usize
    let (key, key_error) = mem.alloc[f64](a, 17usize)
    if key_error != ok { os.exit(5) }
    let base = mem.mark(a)
    var have = false
    var fd: gr.Fitted = zero
    var dn: []f64 = zero
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let z = c.args
        var fresh = !have
        if have {
            var q = 0usize
            while q < 17usize {
                if key[q] != z[q] { fresh = true }
                q += 1usize
            }
        }
        if fresh {
            have = false
            mem.reset(a, base)
            let n = usize(z[2usize])
            let p = usize(z[3usize])
            let dist = usize(z[1usize])
            let (dat, de) = make(a, i64(z[0usize]), dist, n, p, z[12usize] == 1.0f64, z[15usize] == 1.0f64)
            var mono: []f64 = zero
            var bad = 0usize
            if z[13usize] == 1.0f64 {
                mono = gb.af(a, p, &bad)
                mono[0usize] = 1.0f64
                mono[1usize] = 0.0f64 - 1.0f64
            }
            dn = gb.af(a, 12usize * p, &bad)
            if de != ok || bad != 0usize { os.exit(4) }
            var rg: rng.Rng = zero
            rng.seed(&rg, i64(z[0usize]) + 1000003i64)
            var i = 0usize
            while i < 12usize * p {
                dn[i] = r3(rng.norm(&rg), 1000.0f64)
                i += 1usize
            }
            if z[15usize] == 1.0f64 {
                i = 0usize
                while i < 12usize * p {
                    if rng.unif(&rg) < 0.15f64 { dn[i] = 0.0f64 / 0.0f64 }
                    i += 1usize
                }
            }
            var st: []f64 = zero
            if dist == 8usize { st = dat.st }
            var ww: []f64 = zero
            if z[12usize] == 1.0f64 { ww = dat.w }
            var grp: []f64 = zero
            let inp = gr.Input{ dist: dist, n: n, p: p, ntrees: usize(z[4usize]), shrinkage: z[5usize], depth: usize(z[6usize]), minobs: usize(z[7usize]), bag: z[8usize], trainfrac: z[9usize], par: z[11usize], maxrank: 0usize, cv: usize(z[14usize]), ncores1: true, stratify: false,
                x: dat.x, y: dat.y, status: st, w: ww, group: grp, mono: mono }
            rng.seed(&rg, i64(z[10usize]))
            var (f, fe) = gr.gbm(a, &rg, &inp)
            if fe == ok && z[16usize] > 0.0f64 {
                let (f2, fe2) = gr.more(a, &rg, &f, usize(z[16usize]))
                f = f2
                fe = fe2
            }
            q_copy(key, z)
            if fe != ok {
                errors += 1usize
                if errors <= 3usize {
                    let _ = io.print("gbm fit failed\n")
                }
                at += 1usize
                continue
            }
            fd = f
            have = true
        }
        if !have {
            failures += 1usize
            at += 1usize
            continue
        }
        let start = mem.mark(a)
        let got = output(a, &fd, dn, z)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if z[0usize] != last_bad && shown < 14usize {
                last_bad = z[0usize]
                shown += 1usize
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}

fn q_copy(k: []f64, z: []const f64) {
    var q = 0usize
    while q < 17usize {
        k[q] = z[q]
        q += 1usize
    }
}
