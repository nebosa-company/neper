// e.algo.stat.logistf_r against the logistf R package. tests/oracle/logistf_full.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R logistf_full`; the case layout is at the top of scripts/r_oracle/groups/logistf_full.R.
// A case is one R call: the fixture runs the same call and the case passes when every number of R's answer is reproduced (1e-9 relative or
// 1e-10 absolute).

use e.algo.stat.logistf_r as lf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Prob = struct {
    n: usize, k: usize, m: usize, mask: usize, o: lf.Opt, y: []const f64, x: []const f64, w: []const f64, off: []const f64,
    plconf: []usize, terms: []usize, extra: []const f64, want: []const f64
}

fn flag(v: f64) -> bool { ret v != 0.0f64 }

fn parse(a: *mem.Arena, args: []const f64) -> (Prob, err) {
    let n = usize(args[0usize])
    let k = usize(args[1usize])
    let m = usize(args[2usize])
    var o = lf.opt_default()
    o.firth = flag(args[4usize])
    o.pl = flag(args[5usize])
    o.has_int = flag(args[6usize])
    o.flic = flag(args[7usize])
    o.c.maxit = usize(args[8usize])
    o.c.maxstep = args[9usize]
    o.c.maxhs = usize(args[10usize])
    o.c.lconv = args[11usize]
    o.c.gconv = args[12usize]
    o.c.xconv = args[13usize]
    o.c.irls = flag(args[14usize])
    o.c.tau = args[15usize]
    o.c.plmaxit = usize(args[16usize])
    o.c.plmaxstep = args[17usize]
    o.c.plmaxhs = usize(args[18usize])
    o.c.pllconv = args[19usize]
    o.c.plxconv = args[20usize]
    o.alpha = args[21usize]
    let npl = usize(args[22usize])
    let nt = usize(args[23usize])
    let has_w = flag(args[24usize])
    let has_o = flag(args[25usize])
    let ne = usize(args[26usize])
    var at = 27usize
    let (plconf, e1) = mem.alloc[usize](a, npl + 1usize)
    if e1 != ok { ret (zero, e1) }
    var i = 0usize
    while i < npl {
        plconf[i] = usize(args[at + i])
        i += 1usize
    }
    at += npl
    let (terms, e2) = mem.alloc[usize](a, nt + 1usize)
    if e2 != ok { ret (zero, e2) }
    i = 0usize
    while i < nt {
        terms[i] = usize(args[at + i])
        i += 1usize
    }
    at += nt
    o.has_plconf = npl > 0usize
    o.has_terms = nt > 0usize
    o.plconf = plconf[0usize..npl]
    o.terms_fit = terms[0usize..nt]
    let y = args[at..at + n]
    at += n
    let x = args[at..at + n * k]
    at += n * k
    var w = args[at..at]
    if has_w {
        w = args[at..at + n]
        at += n
    }
    var off = args[at..at]
    if has_o {
        off = args[at..at + n]
        at += n
    }
    let extra = args[at..at + ne]
    at += ne
    let want = args[at..at + m]
    ret (Prob { n: n, k: k, m: m, mask: usize(args[3usize]), o: o, y: y, x: x, w: w, off: off, plconf: plconf, terms: terms, extra: extra, want: want }, ok)
}

fn bit(mask: usize, b: usize) -> bool { ret (mask >> b) & 1usize == 1usize }

type Out = struct { v: []f64, at: usize }

fn put(o: *Out, v: f64) {
    o.v[o.at] = v
    o.at += 1usize
}

fn flat(a: *mem.Arena, r: lf.Lf, mask: usize, pl: bool) -> ([]f64, err) {
    let (buf, e) = mem.alloc[f64](a, 64usize + 8usize * r.k * r.k + 12usize * r.n + 12usize * r.k)
    if e != ok { ret (buf, e) }
    var out = Out { v: buf, at: 0usize }
    let po = &out
    var i = 0usize
    if bit(mask, 0usize) {
        i = 0usize
        while i < r.k {
            put(po, r.coef[i])
            i += 1usize
        }
    }
    if bit(mask, 1usize) {
        i = 0usize
        while i < r.k * r.k {
            put(po, r.var_m[i])
            i += 1usize
        }
    }
    if bit(mask, 2usize) {
        i = 0usize
        while i < r.k {
            put(po, r.prob[i])
            i += 1usize
        }
        i = 0usize
        while i < r.k {
            put(po, r.ci_lo[i])
            i += 1usize
        }
        i = 0usize
        while i < r.k {
            put(po, r.ci_up[i])
            i += 1usize
        }
    }
    if bit(mask, 3usize) {
        put(po, r.ll_full)
        put(po, r.ll_null)
    }
    if bit(mask, 4usize) {
        put(po, f64(r.iter_full))
        put(po, f64(r.iter_null))
    }
    if bit(mask, 5usize) {
        put(po, f64(r.df))
        put(po, r.sumw)
    }
    if bit(mask, 6usize) {
        i = 0usize
        while i < r.n {
            put(po, r.lp[i])
            i += 1usize
        }
    }
    if bit(mask, 7usize) {
        i = 0usize
        while i < r.n {
            put(po, r.pred[i])
            i += 1usize
        }
    }
    if bit(mask, 8usize) {
        i = 0usize
        while i < r.n {
            put(po, r.hat[i])
            i += 1usize
        }
    }
    if bit(mask, 9usize) && pl {
        i = 0usize
        while i < 3usize * r.k {
            put(po, f64(r.pl_iter[i]))
            i += 1usize
        }
    }
    if bit(mask, 10usize) && pl {
        i = 0usize
        while i < 4usize * r.np {
            put(po, r.pl_conv[i])
            i += 1usize
        }
    }
    ret (buf[0usize..out.at], ok)
}

fn close(got: f64, want: f64) -> bool {
    if got != got && want != want { ret true }
    if got != got || want != want { ret false }
    let d = math_abs(got - want)
    if d <= 1.0e-10f64 { ret true }
    ret d <= 1.0e-9f64 * math_abs(want)
}

fn math_abs(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// the numbers that differ from R's, the first one described
fn compare(a: *mem.Arena, name: str, at: usize, got: []const f64, want: []const f64) -> usize {
    var bad = 0usize
    if got.len != want.len {
        let (initial, be) = str.builder(a, 96usize)
        if be == ok {
            var b = initial
            let _ = str.push(&b, name)
            let _ = str.push(&b, " case ")
            let _ = str.push_f64(&b, f64(at))
            let _ = str.push(&b, ": length ")
            let _ = str.push_f64(&b, f64(got.len))
            let _ = str.push(&b, " against R ")
            let _ = str.push_f64(&b, f64(want.len))
            let _ = str.push(&b, "\n")
            let _ = io.print(str.done(&b))
        }
        ret 1usize
    }
    var i = 0usize
    while i < got.len {
        if !close(got[i], want[i]) {
            bad += 1usize
            if bad <= 2usize {
                let (initial, be) = str.builder(a, 96usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, name)
                    let _ = str.push(&b, " case ")
                    let _ = str.push_f64(&b, f64(at))
                    let _ = str.push(&b, " item ")
                    let _ = str.push_f64(&b, f64(i))
                    let _ = str.push(&b, ": got ")
                    let _ = str.push_f64(&b, got[i])
                    let _ = str.push(&b, ", R says ")
                    let _ = str.push_f64(&b, want[i])
                    let _ = str.push(&b, "\n")
                    let _ = io.print(str.done(&b))
                }
            }
        }
        i += 1usize
    }
    ret bad
}

fn run(a: *mem.Arena, c: *const oracle.Case, at: usize) -> usize {
    let (p, pe) = parse(a, c.args)
    if pe != ok { ret 1usize }
    if str.eq(c.name, "fit") {
        let (r, e) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, p.o)
        if e != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "flic") {
        var o = p.o
        o.flic = false
        let (r0, e) = lf.logistf(a, p.x, p.y, p.n, p.k, p.w, p.off, o)
        if e != ok { ret 1usize }
        let (r, e1) = lf.flic_fit(a, p.x, p.y, p.n, p.k, p.w, p.off, p.terms[0usize..p.o.terms_fit.len], r0)
        if e1 != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    if str.eq(c.name, "flac") {
        let (r, e) = lf.flac(a, p.x, p.y, p.n, p.k, p.w, p.off, p.o)
        if e != ok { ret 1usize }
        let (g, e2) = flat(a, r, p.mask, p.o.pl)
        if e2 != ok { ret 1usize }
        ret compare(a, c.name, at, g, p.want)
    }
    ret 1usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/logistf_full.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let bad = run(a, c, at)
        if bad > 0usize { failures += 1usize }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
