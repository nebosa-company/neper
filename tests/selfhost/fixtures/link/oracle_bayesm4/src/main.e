// e.algo.stat.bayesmscale (rscaleUsage) against bayesm. tests/oracle/bayesm4.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesm4`; the layout is at the top of scripts/r_oracle/groups/bayesm4.R.

use e.algo.rand.r as rng
use e.algo.stat.bayesmgibbs as bg
use e.algo.stat.bayesmscale as bs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the id-th value of the flattened draws, or the weighted checksum for id -1
fn pick(out: []const f64, id: f64) -> f64 {
    if id >= 0.0f64 { ret out[usize(id)] }
    var s = 0.0f64
    var i = 0usize
    while i < out.len {
        s += out[i] * f64(1usize + i % 5usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var r: rng.Rng = zero
    rng.seed(&r, i64(z[0usize]))
    let id = z[z.len - 1usize]
    let k = usize(z[1usize])
    let p = usize(z[2usize])
    let n = usize(z[3usize])
    let nr = usize(z[4usize])
    let xx = 9usize
    let yy = xx + n * p
    let mm = yy + n * p
    let ss = mm + p
    let tt = ss + p * p
    let sg = tt + n
    let lm = sg + n
    let vv = lm + 4usize
    let mb = vv + p * p
    let am = mb + p
    let vl = am + p * p
    let gs = usize(z[vl + 4usize])
    let g1 = vl + 5usize
    let g2 = g1 + gs
    let g3 = g2 + gs
    let g4 = g3 + gs
    let ge = g4 + gs
    let (o, oe) = bg.zal(a, nr * (p * p + p + 2usize * n + 5usize))
    if oe != ok { ret nan }
    if bs.rscale_usage(a, &r, k, z[xx..yy], p, n, nr, usize(z[5usize]), z[yy..mm], z[mm..ss], z[ss..tt], z[tt..sg], z[sg..lm], z[lm..vv], z[7usize], z[6usize], z[vv..mb], z[mb..am], z[am..vl], z[g1..g2], z[g2..g3], z[g3..g4], z[g4..ge], z[8usize], z[vl..vl + 4usize], z[ge..ge + gs + 1usize], o) != ok { ret nan }
    ret pick(o, id)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesm4.json")
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
            if failures <= 40usize {
                let (sb, be) = str.builder(a, 120usize)
                if be == ok {
                    var b = sb
                    let _ = str.push(&b, c.name)
                    let _ = str.push_f64(&b, c.args[1usize])
                    let _ = str.push(&b, " id ")
                    let _ = str.push_f64(&b, c.args[c.args.len - 1usize])
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
