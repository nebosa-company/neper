// The dispatcher the metafor oracle fixtures share: `run` takes a case's name and its argument vector and fills the result vector `out`; the first value of the case is out[0].
//
// rma: args = [method, test, weighted, level (95), tau2 fixed or NA, intercept, k, p, nw, yi (k), vi (k), X (k * p, row-major), weights (nw)]; out is the layout of metaforrma.

use e.mem
use e.algo.stat.metaforrma as mr
use e.algo.stat.metaforfit as mf

// the model of an rma case: y, v, x and the control, positions given back through the tuple (k, p)
fn parse_rma(args: []const f64) -> (mr.Ctl, usize, usize, usize) {
    var c = mf.default_ctl()
    c.method = usize(args[0usize])
    c.test = usize(args[1usize])
    c.weighted = args[2usize] != 0.0f64
    c.level = args[3usize] / 100.0f64
    c.tau2fix = args[4usize]
    c.intercept = args[5usize] != 0.0f64
    let k = usize(args[6usize])
    let p = usize(args[7usize])
    let nw = usize(args[8usize])
    c.aw = args[9usize + 2usize * k + k * p..9usize + 2usize * k + k * p + nw]
    ret (c, k, p, 9usize)
}

fn run(a: *mem.Arena, ws: *mr.Ws, name: str, args: []const f64, out: []f64) -> bool {
    let (c, k, p, at) = parse_rma(args)
    let y = args[at..at + k]
    let v = args[at + k..at + 2usize * k]
    let x = args[at + 2usize * k..at + 2usize * k + k * p]
    mf.fit(ws, y, v, x, k, p, &c, out)
    ret true
}
