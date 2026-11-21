// e.algo.stat.tsa against TSA. tests/oracle/tsa.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsa`; the layout is at the top of scripts/r_oracle/groups/tsa.R.

use e.algo.stat.tsa as ts
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn mcl_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let gl = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, gl)
    if e != ok { os.exit(5) }
    if ts.mcleod_li(a, x[2usize..2usize + n], gl, o) != ok { os.exit(6) }
    var s = 0.0f64
    var i = 0usize
    while i < gl {
        s += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "mcl") { ret mcl_case(a, c) }
    if str.eq(c.name, "aro") {
        let ax = c.args
        let an = usize(ax[0usize])
        let (ao, ae) = mem.alloc[f64](a, 40usize)
        let (ar_, ae2) = mem.alloc[f64](a, an)
        if ae != ok || ae2 != ok { os.exit(11) }
        let bs = 1usize + an
        if ts.ar_ols(a, ax[1usize..1usize + an], ax[bs] != 0.0f64, usize(ax[bs + 1usize]), ax[bs + 2usize] != 0.0f64, ax[bs + 3usize] != 0.0f64, ao, ar_) != ok { os.exit(12) }
        let wh = usize(ax[bs + 4usize])
        let ix = usize(ax[bs + 5usize])
        if wh == 4usize { ret ao[4usize + ix] }
        if wh == 5usize { ret ar_[ix] }
        ret ao[wh]
    }
    if str.eq(c.name, "asub") {
        let sx = c.args
        let sn = usize(sx[0usize])
        let (so, se) = mem.alloc[f64](a, 6usize * 8usize)
        if se != ok { os.exit(13) }
        let (nv, ser) = ts.armasubsets(a, sx[3usize..3usize + sn], usize(sx[1usize]), usize(sx[2usize]), so)
        if ser != ok || nv == 0usize { os.exit(14) }
        let sk = usize(sx[3usize + sn])
        let sq = usize(sx[4usize + sn])
        ret so[(sk - 1usize) * 6usize + sq]
    }
    if str.eq(c.name, "bl") {
        let bx = c.args
        let bn = usize(bx[0usize])
        let bg = usize(bx[1usize])
        let bf = usize(bx[2usize])
        let (bo, be) = mem.alloc[f64](a, bg)
        if be != ok { os.exit(7) }
        if ts.box_ljung(a, bx[3usize..3usize + bn], bg, bf, bo) != ok { os.exit(8) }
        var bs = 0.0f64
        var bi = bf
        while bi < bg {
            bs += bo[bi] * f64(bi + 1usize)
            bi += 1usize
        }
        ret bs
    }
    if str.eq(c.name, "eacf") {
        let ex = c.args
        let en = usize(ex[0usize])
        let ar = usize(ex[1usize])
        let ma = usize(ex[2usize])
        let (eo, ee) = mem.alloc[f64](a, (ar + 1usize) * (ma + 1usize))
        if ee != ok { ret 0.0f64 / 0.0f64 }
        if ts.eacf(a, ex[4usize..4usize + en], ar, ma, eo) != ok { ret 0.0f64 / 0.0f64 }
        ret eo[usize(ex[3usize])]
    }
    let x = c.args
    let n = usize(x[0usize])
    let (o, e) = mem.alloc[f64](a, ts.nextn(n) / 2usize + 1usize)
    if e != ok { os.exit(5) }
    let cnt = ts.periodogram(x[1usize..1usize + n], o)
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsa.json")
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
