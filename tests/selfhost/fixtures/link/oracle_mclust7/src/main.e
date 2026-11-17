// e.algo.stat.mclustboot against mclust. tests/oracle/mclust7.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust7`; the layout is at the top of scripts/r_oracle/groups/mclust7.R.
// Consecutive cases share the data and the seed, so the bootstrap is computed once per group of cases.

use e.algo.stat.mclustboot as mb
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust7.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (res, re) = mem.alloc[f64](a, 20000usize)
    let (key, ke) = mem.alloc[f64](a, 4000usize)
    if re != ok || ke != ok { os.exit(4) }
    var have = false
    var key_len = 0usize
    var gcount = 0usize
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        let id = usize(z[0usize])
        let model = usize(z[1usize])
        let n = usize(z[2usize])
        let p = usize(z[3usize])
        let nboot = usize(z[4usize])
        let maxg = usize(z[5usize])
        var gtop = 9usize
        if maxg > 0usize { gtop = maxg + 1usize }
        let gm1 = gtop - 1usize
        var got = 0.0f64 / 0.0f64
        if !(have && key_len == z.len && same_key(key[0usize..key_len], z)) {
            have = false
            let be = mb.boot_lrt(a, z[7usize..7usize + n * p], n, p, model, nboot, 0.05f64, maxg, i64(z[6usize]), res, &gcount)
            if be == ok {
                have = true
                key_len = z.len
                var q = 0usize
                while q < z.len {
                    key[q] = z[q]
                    q += 1usize
                }
            }
        }
        if have {
            if id == 1usize {
                got = f64(gcount)
            } else if id >= 300usize {
                let g = id - 300usize
                var s = 0.0f64
                var b = 0usize
                while b < nboot {
                    s += f64(b + 1usize) * res[2usize * gm1 + (g - 1usize) * nboot + b]
                    b += 1usize
                }
                got = s
            } else if id >= 200usize {
                got = res[gm1 + id - 200usize - 1usize]
            } else {
                got = res[id - 100usize - 1usize]
            }
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let (initial, be) = str.builder(a, 120usize)
                var b = initial
                let _ = str.push(&b, "boot id ")
                let _ = str.push_f64(&b, z[0usize])
                let _ = str.push(&b, " model ")
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
