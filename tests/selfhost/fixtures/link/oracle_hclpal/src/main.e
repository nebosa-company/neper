// e.gfx.hclpal against colorspace: sequential_hcl, diverging_hcl and qualitative_hcl over every palette
// of hcl_palettes(). tests/oracle/hclpal.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R hclpal`; the layout is at the top of scripts/r_oracle/groups/hclpal.R.

use e.gfx.hclpal as pal
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "contrast") { ret pal.contrast_ratio(i64(x[0usize]), i64(x[1usize])) }
    if str.eq(c.name, "cvd") { ret f64(pal.cvd(u8(x[0usize]), x[1usize], i64(x[2usize]))) }
    let ty = u8(x[0usize])
    let fixup = x[10usize] != 0.0f64
    let n = usize(x[11usize])
    let k = usize(x[12usize])
    if ty == 0u8 { ret f64(pal.sequential(n, k, x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize], x[8usize], x[9usize], fixup)) }
    if ty == 1u8 { ret f64(pal.diverging(n, k, x[1usize], x[2usize], x[3usize], x[5usize], x[6usize], x[7usize], x[8usize], x[9usize], fixup)) }
    ret f64(pal.qualitative(n, k, x[1usize], x[2usize], x[3usize], x[5usize], fixup))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hclpal.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 15usize {
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
