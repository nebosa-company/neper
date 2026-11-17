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

// the number of option values before the model
fn nopts(name: str) -> usize {
    if str.eq(name, "confint") { ret 1usize }
    if str.eq(name, "predict") { ret 3usize }
    ret 0usize
}

fn run(a: *mem.Arena, ws: *mr.Ws, name: str, args: []const f64, out: []f64, tmp: []f64) -> bool {
    let off = nopts(name)
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
    ret true
}
