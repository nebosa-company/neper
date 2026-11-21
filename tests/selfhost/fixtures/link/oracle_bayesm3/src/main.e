// e.algo.stat.bayesmgibbs against bayesm. tests/oracle/bayesm3.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesm3`; the layout is at the top of scripts/r_oracle/groups/bayesm3.R.

use e.algo.rand.r as rng
use e.algo.stat.bayesmgibbs as bg
use e.algo.stat.bayesmhier as bh
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
    if str.eq(c.name, "hmnl") {
        let nlgt = usize(z[1usize])
        let nvar = usize(z[2usize])
        let nz = usize(z[3usize])
        let p = usize(z[4usize])
        let nc = usize(z[5usize])
        let nr = usize(z[6usize])
        let w = nlgt * nvar + nc + 1usize + nz * nvar + nc * (nvar + nvar * nvar)
        let (o, oe) = bg.zal(a, nr * w)
        if oe != ok { ret nan }
        let mb = 10usize
        let vv = mb + nvar
        let av = vv + nvar * nvar
        let sr = av + nc
        let db = sr + nvar
        let ad = db + nz * nvar
        let zz = ad + nz * nvar * nz * nvar
        let ob = zz + nlgt * nz
        let nsx = ob + nlgt * nvar
        var tot = 0usize
        var g = 0usize
        while g < nlgt {
            tot += usize(z[nsx + g])
            g += 1usize
        }
        let yy = nsx + nlgt
        let xx = yy + tot
        let hh = xx + tot * p * nvar
        if bh.rhier_mnl(a, &r, z[nsx..yy], z[yy..xx], z[xx..hh], z[hh..hh + nlgt * nvar * nvar], z[zz..ob], z[db..ad], z[ad..zz], z[mb..vv], z[8usize], z[7usize], z[vv..av], z[9usize], z[av..sr], z[sr..db], z[ob..nsx], nlgt, nvar, nz, p, nc, nr, o) != ok { ret nan }
        ret pick(o, id)
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesm3.json")
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
