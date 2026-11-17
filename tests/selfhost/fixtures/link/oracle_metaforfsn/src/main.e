// e.algo.stat.metaformore3 (fsn Fisher and General) against metafor. tests/oracle/metaforfsn.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R metaforfsn`; the layout is at the top of scripts/r_oracle/groups/metaforfsn.R.

use e.algo.stat.metaforrma as mr
use e.algo.stat.metaforrun as run
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/metaforfsn.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (ws0, we) = mr.new_ws(a)
    if we != ok { os.exit(4) }
    var ws = ws0
    let (out, oe) = mem.alloc[f64](a, mr.OUTLEN)
    if oe != ok { os.exit(5) }
    let (tmp, te) = mem.alloc[f64](a, mr.OUTLEN)
    if te != ok { os.exit(6) }
    var failures = 0usize
    var data = 0usize
    var lastfail = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var idx = 0usize
        var got = 0.0f64
        if str.eq(c.name, "o") {
            idx = usize(c.args[0usize])
            got = out[idx]
        } else {
            data += 1usize
            let _ = run.run(a, &ws, c.name, c.args, out, tmp)
            got = out[0usize]
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 400usize && data != lastfail {
                lastfail = data
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, "case ")
                    let _ = str.push_i64(&b, i64(data))
                    let _ = str.push(&b, " idx ")
                    let _ = str.push_i64(&b, i64(idx))
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = str.push(&b, "\n")
                    let _ = io.print(str.done(&b))
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
