// e.algo.stat.earthfit (earth.fit: forward pass, pruning, final fit) against earth. tests/oracle/earth.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R earth`; the layout of args is at the top of scripts/r_oracle/groups/earth.R.
// The data are regenerated from the seed with the R generator port: x = runif(n p), z = rnorm(n), y from x and z with only + - * (so the bits agree).

use e.algo.rand.r as rr
use e.algo.stat.earthcv as ec
use e.algo.stat.earthfit as ef
use e.algo.stat.earthfmt as efm
use e.algo.stat.earthmore as em
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

type Data = struct { x: []f64, y: []f64 }

fn gen(a: *mem.Arena, rng: *rr.Rng, seed: i64, n: usize, p: usize, nr: usize, fam: usize) -> (Data, err) {
    var d: Data = zero
    rr.seed(rng, seed)
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (y, e2) = mem.alloc[f64](a, n * nr)
    let (z, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (d, mem.Exhausted) }
    var i = 0usize
    while i < n * p {
        x[i] = rr.runif(rng, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        z[i] = rr.rnorm(rng, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        let t = x[i] - 0.5f64
        let x2 = x[n + i]
        let x3 = x[2usize * n + i]
        y[i] = 4.0f64 * t * t + 3.0f64 * x2 - 2.0f64 * x2 * x3 + 0.3f64 * z[i]
        i += 1usize
    }
    if nr == 2usize {
        i = 0usize
        while i < n {
            z[i] = rr.rnorm(rng, 0.0f64, 1.0f64)
            i += 1usize
        }
        i = 0usize
        while i < n {
            y[n + i] = 2.0f64 * x[i] * x[n + i] - x[2usize * n + i] + 0.2f64 * z[i]
            i += 1usize
        }
    }
    if fam == 1usize {
        i = 0usize
        while i < n * nr {
            var yv = 0.0f64
            if y[i] > 1.3f64 { yv = 1.0f64 }
            y[i] = yv
            i += 1usize
        }
    }
    if fam == 2usize {
        i = 0usize
        while i < n * nr {
            y[i] = math.floor[f64](2.5f64 * math.abs[f64](y[i]))
            i += 1usize
        }
    }
    d.x = x
    d.y = y
    ret (d, ok)
}

fn same_setup(x: []const f64, y: []const f64) -> bool {
    var i = 0usize
    while i < 24usize {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

type Built = struct { f: ef.EFit, md: ec.Model, xn: []f64, x: []f64, m: usize, p: usize, n: usize, nr: usize, fam: usize }

fn build(a: *mem.Arena, rng: *rr.Rng, z: []const f64, with_new: bool) -> (Built, err) {
    var none: Built = zero
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let nr = usize(z[3usize])
    let (d, e0) = gen(a, rng, i64(z[0usize]), n, p, nr, usize(z[19usize]))
    if e0 != ok { ret (none, e0) }
    let (o0, e1) = ef.opts_default(a, p, i64(z[4usize]))
    var o = o0
    if e1 != ok { ret (none, e1) }
    if z[5usize] != 0.0f64 - 99.0f64 { o.penalty = z[5usize] }
    if z[6usize] != 0.0f64 { o.nk = usize(z[6usize]) }
    o.thresh = z[7usize]
    o.minspan = i64(z[8usize])
    o.endspan = i64(z[9usize])
    o.pmethod = usize(z[10usize])
    o.nprune = usize(z[11usize])
    o.newvar = z[12usize]
    o.fastk = i64(z[13usize])
    o.fastbeta = z[14usize]
    let mask = usize(z[15usize])
    var j = 0usize
    while j < p {
        o.linp[j] = ((mask >> j) & 1usize) == 1usize
        j += 1usize
    }
    o.adjend = z[16usize]
    o.autolin = z[17usize] == 1.0f64
    o.scale_y = i64(z[18usize])
    let fam = usize(z[19usize])
    let (md, e2) = ec.earth_model(a, d.x, d.y, n, p, nr, &o, fam, usize(z[20usize]), usize(z[21usize]), z[22usize] == 1.0f64, z[23usize] == 1.0f64, rng)
    var b: Built = zero
    b.md = md
    b.x = d.x
    b.f = md.f
    b.p = p
    b.n = n
    b.nr = nr
    b.fam = fam
    if with_new {
        b.m = 15usize
        let (xn, e3) = mem.alloc[f64](a, 15usize * p)
        if e3 != ok { ret (none, e3) }
        var q = 0usize
        while q < 15usize * p {
            xn[q] = rr.runif(rng, 0.0f64, 1.0f64)
            q += 1usize
        }
        b.xn = xn
    }
    ret (b, e2)
}

fn answer_more(a: *mem.Arena, b: *const Built, q: usize, i: usize, j: usize) -> f64 {    var v = 0.0f64 / 0.0f64
    let f = &b.f
    if q == 22usize {
        let (out, e) = mem.alloc[f64](a, b.m * f.nr)
        if e == ok {
            let e2 = ef.predict_rows(a, f, b.xn, b.m, out)
            if e2 == ok { v = out[i + j * b.m] }
        }
    }
    if q == 23usize {
        let (bx, e) = ef.get_bx(a, b.xn, b.m, f.p, f.dirs, f.cuts, f.nt, f.sel, f.nsel)
        if e == ok { v = bx[j * b.m + i] }
    }
    if q == 24usize || q == 25usize {
        let (pred_of, e) = mem.alloc[usize](a, f.p + 1usize)
        if e == ok {
            let (tm, nc, e2) = em.predict_terms(a, f, b.xn, b.m, pred_of)
            if e2 == ok {
                if q == 24usize { v = f64(nc) }
                if q == 25usize { v = tm[j * b.m + i] }
            }
        }
    }
    if q == 30usize || q == 31usize {
        let (ev, e) = em.evimp(a, f, true, true)
        if e == ok {
            if q == 30usize { v = f64(ev.nrow) }
            if q == 31usize { v = ev.tab[i + j * ev.p] }
        }
    }
    if q == 32usize {
        let (ev, e) = em.evimp(a, f, false, false)
        if e == ok { v = ev.tab[i + j * ev.p] }
    }
    if q >= 80usize && q <= 82usize {
        let p = f.p
        let (nmb, e1) = mem.alloc[u8](a, 2usize * p)
        let (noff, e2) = mem.alloc[usize](a, p + 1usize)
        if e1 == ok && e2 == ok {
            var c = 0usize
            while c < p {
                nmb[2usize * c] = 120u8
                nmb[2usize * c + 1usize] = u8(49usize + c)
                noff[c] = 2usize * c
                c += 1usize
            }
            noff[p] = 2usize * p
            var gc: []f64 = f.coef[0usize..0usize]
            var resp = j
            if j >= f.nr {
                resp = j - f.nr
                gc = b.md.g.coef[resp * f.nsel..resp * f.nsel + f.nsel]
            }
            let (txt, e3) = efm.format_earth(a, f, nmb, noff, i / 100usize, i % 100usize, resp, gc)
            if e3 == ok {
                var h1 = 0.0f64
                var h2 = 0usize
                var t = 0usize
                while t < txt.len {
                    h1 += f64(usize(txt[t]) * (t + 1usize))
                    h2 = (h2 * 257usize + usize(txt[t])) % 1000003usize
                    t += 1usize
                }
                if q == 80usize { v = f64(txt.len) }
                if q == 81usize { v = h1 }
                if q == 82usize { v = f64(h2) }
            }
        }
    }
    let g = &b.md.g
    if q == 40usize { v = g.coef[i + j * f.nsel] }
    if q == 41usize { v = g.stats[i * 8usize + j] }
    if q >= 49usize && q <= 52usize {
        var xs = b.xn
        var m = b.m
        if q == 52usize {
            xs = b.x
            m = b.n
        }
        var kind = 1usize
        if q == 50usize { kind = 0usize }
        let (out, e) = mem.alloc[f64](a, m * f.nr)
        if e == ok {
            let e2 = ec.glm_predict(a, f, g, xs, m, kind, out)
            if e2 == ok { v = out[i + j * m] }
            if q == 51usize && e2 == ok {
                v = 0.0f64
                if out[i] > 0.5f64 { v = 1.0f64 }
            }
        }
    }
    if q >= 60usize {
        let cv = &b.md.cv
        let t = i + j * cv.ntab
        if q == 60usize { v = f64(cv.ntab) }
        if q == 61usize { v = cv.rsq[t] }
        if q == 62usize { v = cv.maxerr[t] }
        if q == 63usize { v = cv.nterms[i] }
        if q == 64usize { v = cv.nvars[i] }
        if q == 65usize {
            if j == 0usize { v = f64(i / cv.n + 1usize) } else { v = f64(cv.groups[i]) }
        }
        if q == 66usize { v = cv.oof[t] }
        if q == 67usize { v = cv.infold[t] }
        if q == 68usize { v = cv.dev[t] }
        if q == 69usize { v = cv.cint[t] }
        if q == 70usize { v = cv.cslope[t] }
        if q == 71usize { v = cv.test[t] }
    }
    ret v
}

fn answer(f: *const ef.EFit, q: usize, i: usize, j: usize) -> f64 {
    var v = 0.0f64 / 0.0f64
    if q == 1usize { v = f64(f.nt) }
    if q == 2usize { v = f64(f.termcond) }
    if q == 3usize { v = f64(f.nsel) }
    if q == 4usize { v = f64(f.sel[i] + 1usize) }
    if q == 5usize { v = f64(f.dirs[i + j * f.nt]) }
    if q == 6usize { v = f.cuts[i + j * f.nt] }
    if q == 7usize { v = f.rss }
    if q == 8usize { v = f.gcv }
    if q == 9usize { v = f.rsq }
    if q == 10usize { v = f.grsq }
    if q == 11usize { v = f.coef[i + j * f.nsel] }
    if q == 12usize { v = f.fitted[i + j * f.n] }
    if q == 13usize { v = f.resid[i + j * f.n] }
    if q == 14usize { v = f.rss_sub[i] }
    if q == 15usize { v = f.gcv_sub[i] }
    if q == 16usize { v = f64(f.prune[i + j * f.nall]) }
    if q == 17usize { v = f.bx[j * f.n + i] }
    if q == 18usize { v = f.rss_resp[j] }
    if q == 19usize { v = f.gcv_resp[j] }
    if q == 20usize { v = f.rsq_resp[j] }
    if q == 21usize { v = f.grsq_resp[j] }
    ret v
}

fn run_file(a: *mem.Arena, path: str, with_new: bool) -> usize {
    let (golden, load_error) = oracle.load(a, path)
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var rng: rr.Rng = zero
    var failures = 0usize
    var at = 0usize
    var have = false
    var prev = golden.cases[0usize].args
    var good = false
    var built: Built = zero
    var shown = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        if !have || !same_setup(prev, c.args) {
            let (bt, e) = build(a, &rng, c.args, with_new)
            good = e == ok
            built = bt
            prev = c.args
            have = true
            if !good {
                let _ = io.print("setup failed\n")
            }
        }
        var got = 0.0f64 / 0.0f64
        if good {
            let q = usize(c.args[24usize])
            if q >= 22usize {
                got = answer_more(a, &built, q, usize(c.args[25usize]), usize(c.args[26usize]))
            } else {
                got = answer(&built.f, q, usize(c.args[25usize]), usize(c.args[26usize]))
            }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            shown += 1usize
            if shown <= 6usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    let _ = io.print(path)
    let _ = io.print("\n")
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    var failures = run_file(a, "tests/oracle/earth.json", false)
    failures += run_file(a, "tests/oracle/earth_opts.json", false)
    failures += run_file(a, "tests/oracle/earth_prune.json", false)
    failures += run_file(a, "tests/oracle/earth_pred.json", true)
    failures += run_file(a, "tests/oracle/earth_glm.json", true)
    failures += run_file(a, "tests/oracle/earth_cv.json", true)
    failures += run_file(a, "tests/oracle/earth_fmt.json", true)
    if failures > 0usize { os.exit(1) }
    ret ok
}
