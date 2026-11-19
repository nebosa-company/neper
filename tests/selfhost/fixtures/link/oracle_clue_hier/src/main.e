// e.algo.stat.clue's hier_dissimilarity against clue cl_dissimilarity on hclust trees. tests/oracle/clue_hier.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clue_hier`; the layout is at the top of scripts/r_oracle/groups/clue_hier.R.

use e.algo.stat.clue as cl
use e.algo.stat.hclust as hc
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn dmat(a: *mem.Arena, x: []const f64, n: usize) -> []f64 {
    let (d, e) = mem.alloc[f64](a, n * n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = x[2usize * i] - x[2usize * j]
            let dy = x[2usize * i + 1usize] - x[2usize * j + 1usize]
            d[i * n + j] = math.sqrt[f64](dx * dx + dy * dy)
            j += 1usize
        }
        i += 1usize
    }
    ret d
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if c.name.len == 4usize && c.name[0usize] == 115u8 {
        let sn = usize(z[0usize])
        let sk = usize(z[1usize])
        let (sv, se) = cl.euclid_soft(a, z[2usize..2usize + sn * sk], z[2usize + sn * sk..2usize + 2usize * sn * sk], sn, sk)
        if se != ok { ret 0.0f64 / 0.0f64 }
        ret sv
    }
    let n = usize(z[1usize])
    let (t1, e1) = hc.hclust(a, dmat(a, z[4usize..4usize + 2usize * n], n), n, usize(z[2usize]))
    let (t2, e2) = hc.hclust(a, dmat(a, z[4usize + 2usize * n..4usize + 4usize * n], n), n, usize(z[3usize]))
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    if usize(z[0usize]) >= 5usize {
        let (va, ea) = cl.hier_agreement(a, &t1, &t2, n, usize(z[0usize]))
        if ea != ok { ret 0.0f64 / 0.0f64 }
        ret va
    }
    let (v, e) = cl.hier_dissimilarity(a, &t1, &t2, n, usize(z[0usize]))
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clue_hier.json")
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
