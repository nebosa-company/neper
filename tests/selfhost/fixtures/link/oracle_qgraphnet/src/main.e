// e.algo.stat.qgraphpkg general centrality_auto, centralityTable, mat2vec, FDRnetwork and the spring layout against qgraph.
// tests/oracle/qgraphnet.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qgraphnet`; the argument layouts are at
// the top of scripts/r_oracle/groups/qgraphnet.R.

use e.algo.stat.glasso as gl
use e.algo.stat.qgraphpkg as qg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// position-weighted sum with NaN as 0, or the weighted mask of the NaN positions
fn wsum(v: []const f64, mask: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        let nan = v[i] != v[i]
        if mask {
            if nan { s += f64(i + 1usize) }
        } else if !nan {
            s += v[i] * f64(i + 1usize)
        }
        i += 1usize
    }
    ret s
}

fn block(name: str) -> usize {
    if str.ends_with(name, "between") { ret 0usize }
    if str.ends_with(name, "clos") || str.ends_with(name, "clos_na") { ret 1usize }
    if str.ends_with(name, "outstr") || str.ends_with(name, "outstr_na") { ret 2usize }
    if str.ends_with(name, "instr") || str.ends_with(name, "instr_na") { ret 3usize }
    if str.ends_with(name, "outei") || str.ends_with(name, "outei_na") { ret 4usize }
    ret 5usize
}

fn run_cent(a: *mem.Arena, c: *const oracle.Case, table: bool) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let wg = z[1usize] != 0.0f64
    var off = 3usize
    if table { off = 5usize }
    let w = z[off..off + n * n]
    let (out, e1) = gl.zalloc(a, 6usize * n)
    let (spl, e2) = gl.zalloc(a, n * n)
    let (ef, e3) = mem.alloc[usize](a, n * n + 1usize)
    let (et, e4) = mem.alloc[usize](a, n * n + 1usize)
    let (ev, e5) = gl.zalloc(a, n * n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    let (info, e) = qg.centrality_auto(a, w, n, wg, z[2usize] != 0.0f64, out, spl, ef, et, ev)
    if e != ok { ret nan }
    let na = str.ends_with(c.name, "_na")
    if table {
        qg.centrality_table(out, n, 6usize, z[3usize] != 0.0f64, z[4usize] != 0.0f64)
        let b = block(c.name)
        ret wsum(out[b * n..(b + 1usize) * n], na)
    }
    if str.eq(c.name, "cent_ne") { ret f64(info.edges) }
    if str.eq(c.name, "cent_spl") || str.eq(c.name, "cent_spl_inf") {
        var s = 0.0f64
        var i = 0usize
        while i < n * n {
            let inf = spl[i] > 1.0e300f64
            if str.eq(c.name, "cent_spl_inf") {
                if inf { s += f64(i + 1usize) }
            } else if !inf {
                s += spl[i] * f64(i + 1usize)
            }
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cent_eb") {
        var s = 0.0f64
        var i = 0usize
        while i < info.edges {
            s += ev[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "cent_eb_ord") {
        var s = 0.0f64
        var i = 0usize
        while i < info.edges {
            s += f64((ef[i] + 1usize) * 100usize + et[i] + 1usize) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    let b = block(c.name)
    ret wsum(out[b * n..(b + 1usize) * n], na)
}

fn run_m2v(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = gl.zalloc(a, n * n)
    if e1 != ok { ret nan }
    let k = qg.mat2vec(a, z[3usize..3usize + n * n], n, z[1usize] != 0.0f64, z[2usize], out)
    if str.eq(c.name, "m2v_len") { ret f64(k) }
    ret wsum(out[0usize..k], false)
}

fn run_fdr(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[2usize])
    let (out, e1) = gl.zalloc(a, n * n)
    if e1 != ok { ret nan }
    if qg.fdr_network(a, z[3usize..3usize + n * n], n, z[1usize], u8(z[0usize]), out) != ok { ret nan }
    ret wsum(out, false)
}

fn run_sp(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (raw, e1) = gl.zalloc(a, 2usize * n)
    let (sc, e2) = gl.zalloc(a, 2usize * n)
    if e1 != ok || e2 != ok { ret nan }
    var area = nan
    if z[3usize] > 0.0f64 { area = z[3usize] }
    var cool = nan
    if z[4usize] > 0.0f64 { cool = z[4usize] }
    if qg.spring_layout(a, z[5usize..5usize + n * n], n, usize(z[1usize]), z[2usize], area, cool, nan, raw, sc) != ok { ret nan }
    if str.eq(c.name, "sp_raw_x") { ret wsum(raw[0usize..n], false) }
    if str.eq(c.name, "sp_raw_y") { ret wsum(raw[n..2usize * n], false) }
    if str.eq(c.name, "sp_x") { ret wsum(sc[0usize..n], false) }
    ret wsum(sc[n..2usize * n], false)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "cent_") { ret run_cent(a, c, false) }
    if str.starts_with(c.name, "tab_") { ret run_cent(a, c, true) }
    if str.starts_with(c.name, "m2v_") { ret run_m2v(a, c) }
    if str.starts_with(c.name, "fdr_") { ret run_fdr(a, c) }
    ret run_sp(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qgraphnet.json")
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
            if failures <= 60usize {
                let (initial, be) = str.builder(a, 160usize)
                var b = initial
                let _ = str.push(&b, c.name)
                let _ = str.push(&b, " #")
                let _ = str.push_f64(&b, f64(at))
                let _ = str.push(&b, " got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, " R ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
