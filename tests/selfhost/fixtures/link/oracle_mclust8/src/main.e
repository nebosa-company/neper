// e.algo.stat.mclustfit against mclust. tests/oracle/mclust8.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust8`; the layout is at the top of scripts/r_oracle/groups/mclust8.R.
// Consecutive cases share the data and the grid, so the fit is computed once per group of cases.

use e.algo.stat.mclustfit as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 1usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// the answer for one case from the stored fit res
fn pick(res: []const f64, z: []const f64) -> f64 {
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let gmin = usize(z[3usize])
    let gmax = usize(z[4usize])
    let nm = usize(z[5usize])
    let ng = gmax - gmin + 1usize
    let g = usize(res[1usize])
    let off_cl = 6usize + ng * nm
    let off_un = off_cl + n
    let off_z = off_un + n
    let off_pro = off_z + n * gmax
    let off_mu = off_pro + gmax
    let off_sg = off_mu + p * gmax
    if id < 6usize { ret res[id] }
    var s = 0.0f64
    var q = 0usize
    if id >= 10usize && id < 40usize {
        let j = id - 10usize
        q = 0usize
        while q < ng {
            let b = res[6usize + j * ng + q]
            if b == b { s += f64(q + 1usize) * b }
            q += 1usize
        }
        ret s
    }
    if id >= 200usize && id < 230usize {
        let j = id - 200usize
        let off_icl = off_sg + gmax * p * p
        q = 0usize
        while q < ng {
            let b = res[off_icl + j * ng + q]
            if b == b { s += f64(q + 1usize) * b }
            q += 1usize
        }
        ret s
    }
    if id >= 40usize && id < 70usize {
        let j = id - 40usize
        q = 0usize
        while q < ng {
            let b = res[6usize + j * ng + q]
            if b != b { s += f64(q + 1usize) }
            q += 1usize
        }
        ret s
    }
    var base = off_cl
    var cnt = n
    if id == 101usize { base = off_un }
    if id == 102usize {
        base = off_z
        cnt = n * g
    }
    if id == 103usize {
        base = off_pro
        cnt = g
    }
    if id == 104usize {
        base = off_mu
        cnt = p * g
    }
    if id == 105usize {
        base = off_sg
        cnt = g * p * p
    }
    q = 0usize
    while q < cnt {
        s += f64(q + 1usize) * res[base + q]
        q += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust8.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (res, re) = mem.alloc[f64](a, 40000usize)
    let (key, ke) = mem.alloc[f64](a, 40000usize)
    if re != ok || ke != ok { os.exit(4) }
    var have = false
    var key_len = 0usize
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        var got = 0.0f64 / 0.0f64
        if !(have && key_len == z.len && same_key(key[0usize..key_len], z)) {
            have = false
            let n = usize(z[1usize])
            let p = usize(z[2usize])
            let nm = usize(z[5usize])
            let (mods, me) = mem.alloc[usize](a, nm)
            if me == ok {
                var q = 0usize
                while q < nm {
                    mods[q] = usize(z[6usize + q])
                    q += 1usize
                }
                let fe = mf.mclust_run(a, z[6usize + nm..6usize + nm + n * p], n, p, usize(z[3usize]), usize(z[4usize]), mods, res)
                if fe == ok {
                    have = true
                    key_len = z.len
                    q = 0usize
                    while q < z.len {
                        key[q] = z[q]
                        q += 1usize
                    }
                }
            }
        }
        if have { got = pick(res, z) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let (initial, be) = str.builder(a, 120usize)
                var b = initial
                let _ = str.push(&b, "mfit id ")
                let _ = str.push_f64(&b, z[0usize])
                let _ = str.push(&b, " n ")
                let _ = str.push_f64(&b, z[1usize])
                let _ = str.push(&b, ": got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, ", R says ")
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
