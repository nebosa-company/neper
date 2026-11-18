// e.algo.stat.fpc's discrcoord against fpc::discrcoord. tests/oracle/fpc_discr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_discr`; the layout of every case is at the top of scripts/r_oracle/groups/fpc_discr.R.

use e.algo.stat.fpc as fp
use e.math
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kn = usize(z[2usize])
    let pool = usize(z[3usize])
    let (cl, e0) = mem.alloc[usize](a, n)
    if e0 != ok { os.exit(10) }
    var i = 0usize
    while i < n {
        cl[i] = usize(z[4usize + i])
        i += 1usize
    }
    let x = z[4usize + n..4usize + n + n * p]
    let which = usize(z[z.len - 1usize])
    let (ev, e1) = mem.alloc[f64](a, p)
    let (units, e2) = mem.alloc[f64](a, p * p)
    let (proj, e3) = mem.alloc[f64](a, n * p)
    let (wout, e4) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(11) }
    if fp.discrcoord(a, x, n, p, cl, kn, pool, ev, units, proj, wout) != ok { os.exit(12) }
    var s = 0.0f64
    var k = 0usize
    if which == 0usize {
        while k < p {
            s += ev[k]
            k += 1usize
        }
        ret s
    }
    if which == 5usize || which == 6usize {
        // the first or the last discriminant axis
        var axis = p - 1usize
        if which == 5usize { axis = 0usize }
        var r = 0usize
        while r < n {
            s += proj[r * p + axis] * proj[r * p + axis]
            r += 1usize
        }
        ret s
    }
    if which == 7usize {
        while k < p * p {
            s += math.abs[f64](units[k])
            k += 1usize
        }
        ret s
    }
    if which == 1usize || which == 2usize {
        while k < n * p {
            if which == 1usize { s += proj[k] * proj[k] } else { s += math.abs[f64](proj[k]) }
            k += 1usize
        }
        ret s
    }
    while k < p * p {
        if which == 3usize { s += wout[k] } else { s += f64(k + 1usize) * wout[k] }
        k += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_discr.json")
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
            if failures <= 12usize {
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
