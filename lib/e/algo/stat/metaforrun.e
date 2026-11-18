// The dispatcher the metafor oracle fixtures share: `run` takes a case's name and its argument vector and fills the result vector `out`; the first value of the case is out[0].
//
// Every case is a fitted rma.uni model plus what to do with it. The arguments: the options of the feature (their count depends on the name, see nopts), then
//   [method, test, weighted, level (95), tau2 fixed or NA, intercept, k, p, nw, yi (k), vi (k), X (k * p, row-major), weights (nw)] and the extra data of the feature (the rows of predict).
// The result is the layout of metaforrma (the fit, 0 .. 135) and metaformore (the feature, 136 and after).

use e.str
use e.mem
use e.algo.stat.metaforrma as mr
use e.algo.stat.metaforfit as mf
use e.algo.stat.metaformore as mm
use e.algo.stat.metaformore2 as m2
use e.algo.stat.metaformore3 as m3
use e.algo.stat.metaforbias as mb
use e.algo.stat.escalcmore as em
use e.algo.stat.metaformv as mv
use e.algo.stat.metaformv2 as mv2

// the number of option values before the model
fn nopts(name: str, args: []const f64) -> usize {
    if str.eq(name, "confint") { ret 1usize }
    if str.eq(name, "predict") { ret 3usize }
    if str.eq(name, "permutest") { ret 3usize }
    if str.eq(name, "regtest") { ret 2usize }
    if str.eq(name, "trimfill") { ret 2usize }
    if str.eq(name, "fsn") { ret 3usize }
    if str.eq(name, "fsn2") { ret 8usize }
    if str.eq(name, "profile") { ret 1usize + usize(args[0usize]) }
    ret 0usize
}

fn run(a: *mem.Arena, ws: *mr.Ws, name: str, args: []const f64, out: []f64, tmp: []f64) -> bool {
    if str.eq(name, "rmamv") { ret mv.mv_run(a, args, out) }
    if str.eq(name, "rmamv2") { ret mv2.mv2_run(a, args, out) }
    if str.eq(name, "escalc") {
        // args = [measure, vtype, add, to, drop00, correct, k, ncol, data (k * ncol, row-major)]; out[2 i] = yi, out[2 i + 1] = vi
        let ek = usize(args[6usize])
        let ncol = usize(args[7usize])
        let (yi, e1) = mem.alloc[f64](a, ek)
        let (vi, e2) = mem.alloc[f64](a, ek)
        let (sc, e3) = mem.alloc[f64](a, 6usize * ek)
        if e1 != ok || e2 != ok || e3 != ok { ret false }
        em.escalc(usize(args[0usize]), usize(args[1usize]), args[2usize], usize(args[3usize]), args[4usize] != 0.0f64, args[5usize] != 0.0f64, ek, ncol, args[8usize..8usize + ek * ncol], yi, vi, sc)
        var q = 0usize
        while q < ek {
            out[2usize * q] = yi[q]
            out[2usize * q + 1usize] = vi[q]
            q += 1usize
        }
        ret true
    }
    let off = nopts(name, args)
    var c = mf.default_ctl()
    c.method = usize(args[off])
    c.test = usize(args[off + 1usize])
    c.weighted = args[off + 2usize] != 0.0f64
    c.level = args[off + 3usize] / 100.0f64
    c.tau2fix = args[off + 4usize]
    c.intercept = args[off + 5usize] != 0.0f64
    let k = usize(args[off + 6usize])
    let p = usize(args[off + 7usize])
    let nw = usize(args[off + 8usize])
    let at = off + 9usize
    let y = args[at..at + k]
    let v = args[at + k..at + 2usize * k]
    let x = args[at + 2usize * k..at + 2usize * k + k * p]
    let wstart = at + 2usize * k + k * p
    c.aw = args[wstart..wstart + nw]
    let extra = wstart + nw
    mf.fit(ws, y, v, x, k, p, &c, out)
    var m: mm.Mod = zero
    m.ws = ws
    m.y = y
    m.v = v
    m.x = x
    m.k = k
    m.p = p
    m.c = c
    m.out = out
    m.tmp = tmp
    m.a = a
    if str.eq(name, "confint") { mm.confint_tau2(&m, usize(args[0usize])) }
    if str.eq(name, "predict") {
        let nnew = usize(args[0usize])
        mm.predict(&m, args[extra..extra + nnew * p], nnew, usize(args[1usize]), args[2usize] != 0.0f64)
    }
    if str.eq(name, "blup") { mm.blup(&m) }
    var needs_h = str.eq(name, "rstandard") || str.eq(name, "influence")
    if needs_h {
        let (h, he) = mem.alloc[f64](a, k * k)
        if he != ok { ret false }
        if str.eq(name, "rstandard") { mm.residuals(&m, h) } else { mm.influence(&m, h) }
    }
    if str.eq(name, "leave1out") { mm.leave1out(&m) }
    if str.eq(name, "cumul") { mm.cumul(&m) }
    if str.eq(name, "permutest") { m2.permutest(&m, args[0usize] != 0.0f64, args[1usize], i64(args[2usize])) }
    if str.eq(name, "regtest") { m2.regtest(&m, usize(args[0usize]), usize(args[1usize]), args[extra..extra + k]) }
    if str.eq(name, "trimfill") { m2.trimfill(&m, usize(args[0usize]), i64(args[1usize])) }
    if str.eq(name, "fsn") { m2.fsn(y, v, k, usize(args[0usize]), args[1usize], args[2usize], out) }
    if str.eq(name, "fsn2") { m3.fsn2(&m, usize(args[0usize]), args[1usize], args[2usize], usize(args[3usize]), args[4usize] != 0.0f64, args[5usize], args[6usize], args[7usize]) }
    if str.eq(name, "profile") { m2.profile(&m, args[1usize..1usize + usize(args[0usize])]) }
    if str.eq(name, "ranktest") {
        let mm2 = k * (k - 1usize) / 2usize + 1usize
        let (counts, ce) = mem.alloc[f64](a, mm2)
        let (next, ne) = mem.alloc[f64](a, mm2)
        if ce == ok && ne == ok {
            out[mm.X0] = mb.ranktest(y, v, 0usize, counts, next)
            out[mm.X0 + 1usize] = mb.ranktest(y, v, 1usize, counts, next)
        }
    }
    ret true
}
