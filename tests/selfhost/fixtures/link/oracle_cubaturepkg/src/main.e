// e.algo.stat.cubaturepkg against cubature. tests/oracle/cubaturepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cubaturepkg`; the layout is at the top of scripts/r_oracle/groups/cubaturepkg.R.

use e.algo.stat.cubaturepkg as cb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cubaturepkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let d = usize(x[1usize])
        if c.name.len == 2usize && c.name[0usize] == 104u8 && c.name[1usize] == 118u8 {
            var vo: [8]f64 = zero
            let ve = cb.hcubature_gm_v(a, usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), vo[0usize..8usize])
            if ve != ok { os.exit(10) }
            let g4 = vo[usize(x[4usize + 2usize * d])]
            if !oracle.agrees(g4, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g4))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 112u8 && c.name[1usize] == 110u8 {
            var pno: [3]f64 = zero
            cb.pcubature_nd(usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), pno[0usize..3usize])
            let g5 = pno[usize(x[4usize + 2usize * d])]
            if !oracle.agrees(g5, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g5))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 112u8 && c.name[1usize] == 99u8 {
            var po: [3]f64 = zero
            cb.pcubature_1d(usize(x[0usize]), x[2usize], x[3usize], x[4usize], usize(x[5usize]), po[0usize..3usize])
            let g3 = po[usize(x[6usize])]
            if !oracle.agrees(g3, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g3))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 104u8 && c.name[1usize] == 103u8 {
            var o: [3]f64 = zero
            let he = cb.hcubature_gm(a, usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), o[0usize..3usize])
            if he != ok { os.exit(9) }
            let g2 = o[usize(x[4usize + 2usize * d])]
            if !oracle.agrees(g2, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g2))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        var got = cb.integral_box(a, usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], 4usize)
        if c.name.len == 3usize && c.name[0usize] == 105u8 { got = cb.integral_inf(a, usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], 8usize) }
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
