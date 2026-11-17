// e.algo.stat.sn against sn. tests/oracle/sn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sn`; the layout is at the top of scripts/r_oracle/groups/sn.R.

use e.algo.stat.sn as sn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "dsc") { ret sn.dsc(x[4usize], x[0usize], x[1usize], x[2usize]) }
    if str.eq(k, "rsc") {
        let rn = usize(x[4usize])
        let (ro, roe) = mem.alloc[f64](a, rn)
        if roe != ok { ret 0.0f64 / 0.0f64 }
        if sn.rsc(a, rn, x[0usize], x[1usize], x[2usize], i64(x[5usize]), ro) != ok { ret 0.0f64 / 0.0f64 }
        ret ro[usize(x[6usize])]
    }
    if str.eq(k, "rsn") || str.eq(k, "rst") {
        // args (xi, omega, alpha, tau or nu, n, seed, index)
        let rn = usize(x[4usize])
        let (ro, roe) = mem.alloc[f64](a, rn)
        if roe != ok { ret 0.0f64 / 0.0f64 }
        var re = ok
        if str.eq(k, "rsn") { re = sn.rsn(a, rn, x[0usize], x[1usize], x[2usize], x[3usize], i64(x[5usize]), ro) } else { re = sn.rst(a, rn, x[0usize], x[1usize], x[2usize], x[3usize], i64(x[5usize]), ro) }
        if re != ok { ret 0.0f64 / 0.0f64 }
        ret ro[usize(x[6usize])]
    }
    if str.eq(k, "mvcp") {
        let kind = usize(x[0usize])
        let d = usize(x[1usize])
        let (v1, e1) = mem.alloc[f64](a, d)
        let (mt, e2) = mem.alloc[f64](a, d * d)
        let (v2, e3) = mem.alloc[f64](a, d)
        let (o, e4) = mem.alloc[f64](a, d + d * d + d + 1usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
        var i = 0usize
        while i < d {
            v1[i] = x[4usize + i]
            v2[i] = x[4usize + d + d * d + i]
            i += 1usize
        }
        i = 0usize
        while i < d * d {
            mt[i] = x[4usize + d + i]
            i += 1usize
        }
        if kind == 3usize {
            if !sn.mv_cp2dp_st(a, v1, mt, v2, x[2usize], o) { ret 0.0f64 / 0.0f64 }
        } else if kind == 2usize {
            if !sn.mv_cp2dp_sn(a, v1, mt, v2, o) { ret 0.0f64 / 0.0f64 }
        } else {
            let e = sn.mv_dp2cp(a, kind == 1usize, v1, mt, v2, x[2usize], o)
            if e != ok { ret 0.0f64 / 0.0f64 }
        }
        ret o[usize(x[3usize])]
    }
    if str.eq(k, "cumk") { ret sn.sn_cumulant_k(a, x[0usize], x[1usize], x[2usize], usize(x[4usize])) }
    if str.eq(k, "mardia") { ret sn.mst_mardia(x[0usize], x[1usize], x[2usize], usize(x[3usize])) }
    if str.eq(k, "zeta") { ret sn.zeta(usize(x[0usize]), x[1usize]) }
    if str.eq(k, "cumn") { ret sn.sn_cumulant(x[0usize], x[1usize], x[2usize], x[3usize], usize(x[4usize])) }
    if str.eq(k, "dmsn") || str.eq(k, "dmst") || str.eq(k, "rmsn") || str.eq(k, "rmst") || str.eq(k, "dmsc") || str.eq(k, "rmsc") || str.eq(k, "pmsn") || str.eq(k, "pmst") {
        let d = usize(x[0usize])
        let (xi, e1) = mem.alloc[f64](a, d)
        let (om, e2) = mem.alloc[f64](a, d * d)
        let (al, e3) = mem.alloc[f64](a, d)
        let (pt, e4) = mem.alloc[f64](a, d)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
        var i = 0usize
        while i < d {
            xi[i] = x[5usize + i]
            al[i] = x[5usize + d + d * d + i]
            pt[i] = x[5usize + 2usize * d + d * d + i]
            i += 1usize
        }
        i = 0usize
        while i < d * d {
            om[i] = x[5usize + d + i]
            i += 1usize
        }
        if str.eq(k, "dmsn") { ret sn.dmsn(a, pt, xi, om, al, x[1usize], false) }
        if str.eq(k, "dmst") { ret sn.dmst(a, pt, xi, om, al, x[1usize], false) }
        if str.eq(k, "pmsn") { ret sn.pmsn_mv(a, pt, xi, om, al, x[1usize]) }
        if str.eq(k, "pmst") { ret sn.pmst_mv(a, pt, xi, om, al, x[1usize]) }
        if str.eq(k, "dmsc") { ret sn.dmsc(a, pt, xi, om, al, false) }
        let n = usize(x[2usize])
        let (out, e5) = mem.alloc[f64](a, n * d)
        if e5 != ok { ret 0.0f64 / 0.0f64 }
        var re = ok
        if str.eq(k, "rmsc") { re = sn.rmsc(a, n, xi, om, al, i64(x[3usize]), out) } else if str.eq(k, "rmsn") { re = sn.rmsn(a, n, xi, om, al, x[1usize], i64(x[3usize]), out) } else { re = sn.rmst(a, n, xi, om, al, x[1usize], i64(x[3usize]), out) }
        if re != ok { ret 0.0f64 / 0.0f64 }
        ret out[usize(x[4usize])]
    }
    if str.eq(k, "cum") { ret sn.st_cumulant(x[0usize], x[1usize], x[2usize], x[3usize], usize(x[4usize])) }
    if str.eq(k, "cp2st") { ret sn.cp2dp_st(x[0usize], x[1usize], x[2usize], x[3usize], usize(x[4usize])) }
    if str.eq(k, "cp2") { ret sn.cp2dp_sn(x[0usize], x[1usize], x[2usize], usize(x[3usize])) }
    if str.eq(k, "cp") { ret sn.dp2cp(x[0usize], x[1usize], x[2usize], x[3usize], usize(x[4usize])) }
    let xi = x[0usize]
    let om = x[1usize]
    let al = x[2usize]
    let t = x[3usize]
    let v = x[4usize]
    if str.eq(k, "psnb") { ret sn.psn_biv(v, xi, om, al, t) }
    if str.eq(k, "qst") { ret sn.qst(a, v, xi, om, al, t) }
    if str.eq(k, "pstm1") { ret sn.pst_method(a, v, xi, om, al, t, 1usize) }
    if str.eq(k, "pstm2") { ret sn.pst_method(a, v, xi, om, al, t, 2usize) }
    if str.eq(k, "pstm3") { ret sn.pst_method(a, v, xi, om, al, t, 3usize) }
    if str.eq(k, "pstm4") { ret sn.pst_method(a, v, xi, om, al, t, 4usize) }
    if str.eq(k, "pstm5") { ret sn.pst_method(a, v, xi, om, al, t, 5usize) }
    if str.eq(k, "pst") { ret sn.pst(a, v, xi, om, al, t) }
    if str.eq(k, "dsn") { ret sn.dsn(v, xi, om, al, t) }
    if str.eq(k, "psn") { ret sn.psn_owen(v, xi, om, al) }
    if str.eq(k, "qsn") { ret sn.qsn(v, xi, om, al) }
    ret sn.dst(v, xi, om, al, t)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sn.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let mk = mem.mark(a)
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, mk)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
