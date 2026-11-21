// e.algo.stat.bayesmgibbs against bayesm. tests/oracle/bayesm2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesm2`; the layout is at the top of scripts/r_oracle/groups/bayesm2.R.

use e.algo.rand.r as rng
use e.algo.stat.bayesmgibbs as bg
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
    if str.eq(c.name, "nmix") {
        let n = usize(z[1usize])
        let d = usize(z[2usize])
        let nc = usize(z[3usize])
        let nr = usize(z[4usize])
        let (o, oe) = bg.zal(a, nr * (nc + n + nc * (d + d * d)))
        if oe != ok { ret nan }
        let at = 7usize
        let ve = at + d + d * d
        let ae = ve + nc
        if bg.rnmix_gibbs(a, &r, z[ae..ae + n * d], n, d, z[at..at + d], z[5usize], z[6usize], z[at + d..ve], z[ve..ae], nc, nr, o) != ok { ret nan }
        ret pick(o, id)
    }
    if str.eq(c.name, "iv") {
        let n = usize(z[1usize])
        let dd = usize(z[2usize])
        let dg = usize(z[3usize])
        let nr = usize(z[4usize])
        let (o, oe) = bg.zal(a, nr * (dd + 1usize + dg + 4usize))
        if oe != ok { ret nan }
        let md = 6usize
        let ad = md + dd
        let mb = ad + dd * dd
        let ab = mb + 1usize + dg
        let vv = ab + (1usize + dg) * (1usize + dg)
        let yy = vv + 4usize
        let xx = yy + n
        let zz = xx + n
        let ww = zz + n * dd
        if bg.riv_gibbs(a, &r, z[yy..xx], z[xx..zz], z[zz..ww], z[ww..ww + n * dg], z[mb..ab], z[ab..vv], z[md..ad], z[ad..mb], z[vv..yy], z[5usize], n, dd, dg, nr, o) != ok { ret nan }
        ret pick(o, id)
    }
    if str.eq(c.name, "hlin") {
        let nreg = usize(z[1usize])
        let nvar = usize(z[2usize])
        let nz = usize(z[3usize])
        let nr = usize(z[4usize])
        let w = nvar * nvar + nz * nvar + nreg + nreg * nvar
        let (o, oe) = bg.zal(a, nr * w)
        if oe != ok { ret nan }
        let zz = 7usize
        let db = zz + nreg * nz
        let aa = db + nz * nvar
        let vv = aa + nz * nz
        let sq = vv + nvar * nvar
        let t0 = sq + nreg
        let nsx = t0 + nreg
        var tot = 0usize
        var g = 0usize
        while g < nreg {
            tot += usize(z[nsx + g])
            g += 1usize
        }
        let yy = nsx + nreg
        let xx = yy + tot
        if bg.rhier_linear(a, &r, z[nsx..yy], z[yy..xx], z[xx..xx + tot * nvar], z[zz..db], z[db..aa], z[aa..vv], z[5usize], z[vv..sq], z[6usize], z[sq..t0], z[t0..nsx], nreg, nvar, nz, nr, o) != ok { ret nan }
        ret pick(o, id)
    }
    if str.eq(c.name, "mnp") {
        let mvp = z[1usize] != 0.0f64
        let p = usize(z[2usize])
        let n = usize(z[3usize])
        let k = usize(z[4usize])
        let nr = usize(z[5usize])
        let (o, oe) = bg.zal(a, nr * (k + p * p))
        if oe != ok { ret nan }
        let b0 = 7usize
        let s0 = b0 + k
        let vv = s0 + p * p
        let bb = vv + p * p
        let aa = bb + k
        let yy = aa + k * k
        var ny = n
        if mvp { ny = n * p }
        let xx = yy + ny
        if bg.mnp_gibbs(a, &r, mvp, z[yy..xx], z[xx..xx + n * p * k], z[b0..s0], z[s0..vv], z[vv..bb], z[6usize], z[bb..aa], z[aa..yy], p, n, k, nr, o) != ok { ret nan }
        ret pick(o, id)
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesm2.json")
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
