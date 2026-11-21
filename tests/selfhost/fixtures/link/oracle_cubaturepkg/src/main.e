// e.algo.stat.cubaturepkg against cubature. tests/oracle/cubaturepkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cubaturepkg`; the layout is at the top of scripts/r_oracle/groups/cubaturepkg.R.

use e.algo.stat.cubaturepkg as cb
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

// the user integrands of the R generator (ids 1000 to 1003): s the sum and q the sum of squares, added in order in double
fn user_sums(x: []const f64, w: []f64) {
    var s = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < x.len {
        s = s + x[i]
        q = q + x[i] * x[i]
        i += 1usize
    }
    w[0usize] = s
    w[1usize] = q
}

fn user0(x: []const f64, out: []f64) {
    var w: [2]f64 = zero
    user_sums(x, w[0usize..2usize])
    out[0usize] = (1.0f64 + w[0usize]) * math.sin[f64](3.0f64 * w[1usize]) * math.exp[f64](0.0f64 - 0.3f64 * w[0usize])
}

fn user1(x: []const f64, out: []f64) {
    var w: [2]f64 = zero
    user_sums(x, w[0usize..2usize])
    out[0usize] = w[0usize] * w[0usize] * math.cos[f64](w[1usize])
    out[1usize] = math.exp[f64](0.0f64 - w[0usize]) / (1.0f64 + w[1usize])
}

fn user2(x: []const f64, out: []f64) {
    var w: [2]f64 = zero
    user_sums(x, w[0usize..2usize])
    out[0usize] = math.exp[f64](0.0f64 - w[1usize]) * (2.0f64 + math.sin[f64](w[0usize]))
}

fn user3(x: []const f64, out: []f64) {
    var w: [2]f64 = zero
    user_sums(x, w[0usize..2usize])
    out[0usize] = math.exp[f64](0.0f64 - w[1usize]) * (2.0f64 + math.sin[f64](w[0usize]))
    out[1usize] = math.exp[f64](0.0f64 - w[1usize]) * math.cos[f64](w[0usize])
}

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
        // the cuhre/vegas/suave/divonne cases carry (id, vec, d, ...) and the others (id, d, ...); a user id is registered before the call
        let uid = usize(x[0usize])
        if uid >= 1000usize && uid < 1200usize {
            let uk = uid % 100usize
            if uk == 0usize { cb.set_user(user0, 1usize) }
            if uk == 1usize { cb.set_user(user1, 2usize) }
            if uk == 2usize { cb.set_user(user2, 1usize) }
            if uk == 3usize { cb.set_user(user3, 2usize) }
        }
        if c.name.len == 2usize && c.name[0usize] == 112u8 && c.name[1usize] == 118u8 {
            // "pv": (id, d, lo[d], hi[d], tol, maxEval, which) answered by the vector pcubature
            var pvo: [16]f64 = zero
            cb.pcubature_nd_v(usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), pvo[0usize..16usize])
            let g10 = pvo[usize(x[4usize + 2usize * d])]
            if !oracle.agrees(g10, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g10))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 100u8 && c.name[1usize] == 118u8 {
            // "dv": (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, key1, key2, key3, maxPass, border, maxChisq, minDeviation, which) answered by divonne
            let dd = usize(x[2usize])
            var dvo: [16]f64 = zero
            let dve = cb.divonne(a, usize(x[0usize]), usize(x[1usize]), dd, x[3usize..3usize + dd], x[3usize + dd..3usize + 2usize * dd], x[3usize + 2usize * dd], x[4usize + 2usize * dd], usize(x[5usize + 2usize * dd]), usize(x[6usize + 2usize * dd]), i64(x[7usize + 2usize * dd]), i64(x[8usize + 2usize * dd]), i64(x[9usize + 2usize * dd]), usize(x[10usize + 2usize * dd]), x[11usize + 2usize * dd], x[12usize + 2usize * dd], x[13usize + 2usize * dd], dvo[0usize..16usize])
            if dve != ok { os.exit(14) }
            let g9 = dvo[usize(x[14usize + 2usize * dd])]
            if !oracle.agrees(g9, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g9))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 99u8 && c.name[1usize] == 104u8 {
            // "ch": (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, key, which) answered by cuhre
            let cd = usize(x[2usize])
            var co: [16]f64 = zero
            let ce = cb.cuhre(a, usize(x[0usize]), usize(x[1usize]), cd, x[3usize..3usize + cd], x[3usize + cd..3usize + 2usize * cd], x[3usize + 2usize * cd], x[4usize + 2usize * cd], usize(x[5usize + 2usize * cd]), usize(x[6usize + 2usize * cd]), usize(x[7usize + 2usize * cd]), co[0usize..16usize])
            if ce != ok { os.exit(11) }
            let g6 = co[usize(x[8usize + 2usize * cd])]
            if !oracle.agrees(g6, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g6))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 115u8 && c.name[1usize] == 118u8 {
            // "sv": (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, nNew, nMin, flatness, seed, which) answered by suave
            let sd = usize(x[2usize])
            var svo: [16]f64 = zero
            let sve = cb.suave(a, usize(x[0usize]), usize(x[1usize]), sd, x[3usize..3usize + sd], x[3usize + sd..3usize + 2usize * sd], x[3usize + 2usize * sd], x[4usize + 2usize * sd], usize(x[5usize + 2usize * sd]), usize(x[6usize + 2usize * sd]), usize(x[7usize + 2usize * sd]), usize(x[8usize + 2usize * sd]), x[9usize + 2usize * sd], usize(x[10usize + 2usize * sd]), svo[0usize..16usize])
            if sve != ok { os.exit(13) }
            let g8 = svo[usize(x[11usize + 2usize * sd])]
            if !oracle.agrees(g8, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g8))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
        if c.name.len == 2usize && c.name[0usize] == 118u8 && c.name[1usize] == 103u8 {
            // "vg": (id, vec, d, lo[d], hi[d], relTol, absTol, minEval, maxEval, nStart, nIncrease, seed, which) answered by vegas
            let vd = usize(x[2usize])
            var vgo: [16]f64 = zero
            let vge = cb.vegas(a, usize(x[0usize]), usize(x[1usize]), vd, x[3usize..3usize + vd], x[3usize + vd..3usize + 2usize * vd], x[3usize + 2usize * vd], x[4usize + 2usize * vd], usize(x[5usize + 2usize * vd]), usize(x[6usize + 2usize * vd]), usize(x[7usize + 2usize * vd]), usize(x[8usize + 2usize * vd]), usize(x[9usize + 2usize * vd]), vgo[0usize..16usize])
            if vge != ok { os.exit(12) }
            let g7 = vgo[usize(x[10usize + 2usize * vd])]
            if !oracle.agrees(g7, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, g7))
                    let _ = io.print("\n")
                }
            }
            mem.reset(a, start)
            at += 1usize
            continue
        }
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
            var pno: [4]f64 = zero
            cb.pcubature_nd(usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), pno[0usize..4usize])
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
            var po: [4]f64 = zero
            cb.pcubature_1d(usize(x[0usize]), x[2usize], x[3usize], x[4usize], usize(x[5usize]), po[0usize..4usize])
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
            var o: [4]f64 = zero
            let he = cb.hcubature_gm(a, usize(x[0usize]), d, x[2usize..2usize + d], x[2usize + d..2usize + 2usize * d], x[2usize + 2usize * d], usize(x[3usize + 2usize * d]), o[0usize..4usize])
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
