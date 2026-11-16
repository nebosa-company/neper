// e.algo.stat.fdrtool against fdrtool::fdrtool for p values. tests/oracle/fdrtool.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fdrtool`; the layout is at the top of
// scripts/r_oracle/groups/fdrtool.R.

use e.algo.stat.fdrtool as fd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "mono") || str.eq(c.name, "gcm") || str.eq(c.name, "gren") {
        let nan = 0.0f64 / 0.0f64
        let nn = usize(x[0usize])
        let fl = x[1usize] != 0.0f64
        if str.eq(c.name, "mono") {
            let (m, me) = fd.monoreg(a, x[2usize..2usize + nn], x[2usize + nn..2usize + 2usize * nn], x[2usize + 2usize * nn..2usize + 3usize * nn], fl)
            if me != ok { ret nan }
            let what = usize(x[2usize + 3usize * nn])
            let ix = usize(x[3usize + 3usize * nn])
            if what == 0usize { ret f64(m.x.len) }
            if what == 1usize { ret m.x[ix - 1usize] }
            ret m.yf[ix - 1usize]
        }
        if str.eq(c.name, "gcm") {
            let (g, ge) = fd.gcmlcm(a, x[2usize..2usize + nn], x[2usize + nn..2usize + 2usize * nn], fl)
            if ge != ok { ret nan }
            let what = usize(x[2usize + 2usize * nn])
            let ix = usize(x[3usize + 2usize * nn])
            if what == 0usize { ret f64(g.xk.len) }
            if what == 1usize { ret g.xk[ix - 1usize] }
            if what == 2usize { ret g.yk[ix - 1usize] }
            ret g.sk[ix - 1usize]
        }
        let (gr, gre) = fd.grenander(a, x[2usize..2usize + nn], fl)
        if gre != ok { ret nan }
        let what = usize(x[2usize + nn])
        let ix = usize(x[3usize + nn])
        if what == 0usize { ret f64(gr.xk.len) }
        if what == 1usize { ret gr.xk[ix - 1usize] }
        if what == 2usize { ret gr.fk_cdf[ix - 1usize] }
        ret gr.fk[ix - 1usize]
    }
    let n = usize(x[0usize])
    let (q, e1) = mem.alloc[f64](a, n)
    let (l, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    if str.starts_with(c.name, "c_") {
        let st = x[1usize] == 1.0f64
        let meth = u8(x[2usize])
        var eta = 0.0f64
        var cut = 0.0f64
        var nc = 0usize
        if st {
            let (r1, ec1) = fd.fdrtool_normal_cut(a, x[4usize..4usize + n], q, l, meth, x[3usize])
            if ec1 != ok { ret 0.0f64 / 0.0f64 }
            eta = r1.eta0
            cut = r1.cutoff
            nc = r1.ncens
        } else {
            let (r2, ec2) = fd.fdrtool_pvalue_cut(a, x[4usize..4usize + n], q, l, meth, x[3usize])
            if ec2 != ok { ret 0.0f64 / 0.0f64 }
            eta = r2.eta0
            cut = r2.cutoff
            nc = r2.ncens
        }
        let cn = c.name
        if str.eq(cn, "c_eta0") { ret eta }
        if str.eq(cn, "c_cutoff") { ret cut }
        if str.eq(cn, "c_ncens") { ret f64(nc) }
        var cs = 0.0f64
        var ci = 0usize
        while ci < n {
            var v = q[ci]
            if str.starts_with(cn, "c_l_") { v = l[ci] }
            if str.ends_with(cn, "_sum") { cs += v } else { cs += f64(ci + 1usize) * v }
            ci += 1usize
        }
        ret cs
    }
    if str.starts_with(c.name, "t_") {
        let (tr, te) = fd.fdrtool_t(a, x[1usize..1usize + n], q, l)
        if te != ok { ret 0.0f64 / 0.0f64 }
        let tn = c.name
        if str.eq(tn, "t_eta0") { ret tr.eta0 }
        if str.eq(tn, "t_cutoff") { ret tr.cutoff }
        if str.eq(tn, "t_ncens") { ret f64(tr.ncens) }
        if str.eq(tn, "t_df") { ret tr.sd }
        if str.eq(tn, "t_dfse") { ret tr.sd_se }
        ret tr.eta0_se
    }
    if str.starts_with(c.name, "r_") {
        let (rr, re) = fd.fdrtool_corr(a, x[1usize..1usize + n], q, l)
        if re != ok { ret 0.0f64 / 0.0f64 }
        let rn = c.name
        if str.eq(rn, "r_eta0") { ret rr.eta0 }
        if str.eq(rn, "r_cutoff") { ret rr.cutoff }
        if str.eq(rn, "r_ncens") { ret f64(rr.ncens) }
        if str.eq(rn, "r_kappa") { ret rr.sd }
        if str.eq(rn, "r_kappase") { ret rr.sd_se }
        if str.eq(rn, "r_eta0se") { ret rr.eta0_se }
        var rs = 0.0f64
        var ri = 0usize
        while ri < n {
            var v = q[ri]
            if str.starts_with(rn, "r_l_") { v = l[ri] }
            if str.ends_with(rn, "_sum") { rs += v } else { rs += f64(ri + 1usize) * v }
            ri += 1usize
        }
        ret rs
    }
    if str.starts_with(c.name, "z_") {
        let (zr, ze) = fd.fdrtool_normal(a, x[1usize..1usize + n], q, l)
        if ze != ok { ret 0.0f64 / 0.0f64 }
        let zn = c.name
        if str.eq(zn, "z_eta0") { ret zr.eta0 }
        if str.eq(zn, "z_cutoff") { ret zr.cutoff }
        if str.eq(zn, "z_ncens") { ret f64(zr.ncens) }
        if str.eq(zn, "z_sd") { ret zr.sd }
        if str.eq(zn, "z_sdse") { ret zr.sd_se }
        if str.eq(zn, "z_eta0se") { ret zr.eta0_se }
        var zs = 0.0f64
        var zi = 0usize
        while zi < n {
            var v = q[zi]
            if str.starts_with(zn, "z_l_") { v = l[zi] }
            if str.ends_with(zn, "_sum") { zs += v } else { zs += f64(zi + 1usize) * v }
            zi += 1usize
        }
        ret zs
    }
    let (r, e) = fd.fdrtool_pvalue(a, x[1usize..1usize + n], q, l)
    if e != ok { ret 0.0f64 / 0.0f64 }
    let nm = c.name
    if str.eq(nm, "eta0") { ret r.eta0 }
    if str.eq(nm, "cutoff") { ret r.cutoff }
    if str.eq(nm, "ncens") { ret f64(r.ncens) }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var v = q[i]
        if str.starts_with(nm, "l_") { v = l[i] }
        if str.ends_with(nm, "_sum") { s += v } else { s += f64(i + 1usize) * v }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fdrtool.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
