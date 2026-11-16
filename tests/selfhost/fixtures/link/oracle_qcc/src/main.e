// e.algo.stat.qcc against qcc: charts, rules, cusum, ewma and process capability. tests/oracle/qcc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qcc`; the layout of every case is at the top of scripts/r_oracle/groups/qcc.R.

use e.algo.stat.qcc as qc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn data_of(a: *mem.Arena, v: []const f64) -> []f64 {
    let (o, e) = mem.alloc[f64](a, v.len)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < v.len {
        o[i] = v[i]
        if v[i] == 0.0f64 - 999.0f64 { o[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    ret o
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.eq(nm, "chart") {
        let kind = usize(x[0usize])
        let ng = usize(x[1usize])
        let m = usize(x[2usize])
        let conf = x[3usize]
        let method = u8(x[4usize])
        var sdg = x[5usize]
        if sdg < 0.0f64 { sdg = 0.0f64 / 0.0f64 }
        var ch: qc.Chart = zero
        var e = ok
        var last = 6usize
        if kind < 4usize {
            last = 6usize + ng * m
            if kind == 3usize { last = 6usize + ng }
            let d = data_of(a, x[6usize..last])
            let (r, re) = qc.qcc_var(a, d, ng, m, u8(kind), method, sdg, conf)
            ch = r
            e = re
        } else {
            last = 6usize + 2usize * ng
            let (r, re) = qc.qcc_attr(a, x[6usize..6usize + ng], x[6usize + ng..last], u8(kind - 10usize), conf)
            ch = r
            e = re
        }
        if e != ok { os.exit(6) }
        let j = usize(x[last])
        let n = ch.ng
        if j == 0usize { ret ch.center }
        if j == 1usize { ret ch.sd }
        if j == 2usize || j == 3usize {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                if j == 2usize { s += ch.stat[i] } else { s += f64(i + 1usize) * ch.stat[i] }
                i += 1usize
            }
            ret s
        }
        if j == 4usize { ret ch.lcl[0usize] }
        if j == 5usize { ret ch.ucl[0usize] }
        if j == 6usize || j == 7usize {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                if j == 6usize { s += ch.lcl[i] } else { s += ch.ucl[i] }
                i += 1usize
            }
            ret s
        }
        let (idx, ie) = mem.alloc[usize](a, 2usize * n)
        if ie != ok { os.exit(5) }
        var cnt = 0usize
        if j == 8usize || j == 9usize { cnt = qc.beyond_limits(ch, idx) } else { cnt = qc.violating_runs(ch, 7usize, idx) }
        if j == 8usize || j == 10usize { ret f64(cnt) }
        var s = 0.0f64
        var i = 0usize
        while i < cnt {
            s += f64(idx[i])
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "pareto") {
        let n = usize(x[0usize])
        let (tb, pe) = qc.pareto(a, x[1usize..1usize + n])
        if pe != ok { os.exit(6) }
        let col = usize(x[1usize + n])
        let wh = usize(x[2usize + n])
        var s = 0.0f64
        var i = 0usize
        while i < n {
            if wh == 0usize { s += tb[i * 4usize + col] } else { s += f64(i + 1usize) * tb[i * 4usize + col] }
            i += 1usize
        }
        ret s
    }
    let ng = usize(x[0usize])
    let m = usize(x[1usize])
    if str.eq(nm, "cusum") || str.eq(nm, "ewma") || str.eq(nm, "capability") {
        var off = 5usize
        if str.eq(nm, "capability") { off = 6usize }
        if str.eq(nm, "ewma") { off = 4usize }
        let d = data_of(a, x[off..off + ng * m])
        let (ch, e) = qc.qcc_var(a, d, ng, m, 0u8, 9u8, 0.0f64 / 0.0f64, 3.0f64)
        if e != ok { os.exit(6) }
        let j = usize(x[off + ng * m])
        if str.eq(nm, "cusum") {
            let (cu, ce) = qc.cusum(a, ch.stat, ch.sizes, ch.center, ch.sd, x[2usize], x[3usize], x[4usize])
            if ce != ok { os.exit(7) }
            if j == 2usize { ret f64(cu.nupper) }
            if j == 3usize { ret f64(cu.nlower) }
            var s = 0.0f64
            var i = 0usize
            while i < ng {
                if j == 0usize { s += cu.pos[i] } else { s += cu.neg[i] }
                i += 1usize
            }
            ret s
        }
        if str.eq(nm, "ewma") {
            let (y, lo, hi, ee) = qc.ewma(a, ch.stat, ch.sizes, ch.center, ch.sd, x[2usize], x[3usize])
            if ee != ok { os.exit(7) }
            var s = 0.0f64
            var nv = 0usize
            var i = 0usize
            while i < ng {
                if j == 0usize { s += y[i] }
                if j == 1usize { s += lo[i] }
                if j == 2usize { s += hi[i] }
                if y[i] < lo[i] || y[i] > hi[i] { nv += 1usize }
                i += 1usize
            }
            if j == 3usize { ret f64(nv) }
            ret s
        }
        let cp = qc.process_capability(f64(ng * m), ch.center, ch.sd, 3.0f64, x[2usize], x[3usize], x[4usize], x[5usize])
        if j == 0usize { ret cp.cp }
        if j == 1usize { ret cp.cp_lo }
        if j == 2usize { ret cp.cp_hi }
        if j == 3usize { ret cp.cpl }
        if j == 4usize { ret cp.cpl_lo }
        if j == 5usize { ret cp.cpl_hi }
        if j == 6usize { ret cp.cpu }
        if j == 7usize { ret cp.cpu_lo }
        if j == 8usize { ret cp.cpu_hi }
        if j == 9usize { ret cp.cpk }
        if j == 10usize { ret cp.cpk_lo }
        if j == 11usize { ret cp.cpk_hi }
        if j == 12usize { ret cp.cpm }
        if j == 13usize { ret cp.cpm_lo }
        ret cp.cpm_hi
    }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qcc.json")
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
