// Planned names added across the algo modules: Fletcher, LRC, MurmurHash3
// and Zobrist in `e.algo.hash`; `intersect`/`union_into`/`difference` in
// `e.algo.bitset`; `build` in `e.algo.bdd`; `factor_ecm` in `e.algo.bignum`;
// Christofides, 3-opt and Lin-Kernighan in `e.algo.combopt`; `virtual_nodes`
// in `e.algo.consistent_hash`; `global_cardinality` in `e.algo.csp`; the
// rollback union-find in `e.algo.disjoint_set`; `barnes_hut` in
// `e.algo.geom3`; `householder` in `e.algo.linalg.matrix`; `ternary` in
// `e.algo.search`. Expectations come from scratchpad Python (mmh3, sympy,
// brute force). Each check exits with its own code.

use e.algo.bdd as bdd
use e.algo.bignum as big
use e.algo.bitset as bits
use e.algo.combopt as combopt
use e.algo.consistent_hash as ring
use e.algo.csp as csp
use e.algo.disjoint_set as dsu
use e.algo.geom3 as g3
use e.algo.hash as hash
use e.algo.linalg.matrix as matrix
use e.algo.search as search
use e.io
use e.math
use e.mem
use e.os

type Bowl = struct { center: i64 }
type Dish = struct { center: f64 }

fn bowl(ctx: *Bowl, x: i64) -> i64 { ret (x - ctx.center) * (x - ctx.center) + 5i64 }
fn dish(ctx: *Dish, x: f64) -> f64 { ret (x - ctx.center) * (x - ctx.center) + 1.0f64 }

fn near(a: f64, b: f64, tolerance: f64) -> bool { ret math.abs[f64](a - b) <= tolerance }

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn is_permutation(tour: []const usize, n: usize, seen: []u8) -> bool {
    var i = 0usize
    while i < n {
        seen[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < n {
        if tour[i] >= n || seen[tour[i]] != 0u8 { ret false }
        seen[tour[i]] = 1u8
        i += 1usize
    }
    ret true
}

fn check_ecm(a: *mem.Arena, n_text: str, b1: u64, curves: usize, seed: u64, want: str) -> bool {
    let (n, n_error) = big.int_parse(a, n_text, 10u8)
    let (expected, want_error) = big.int_parse(a, want, 10u8)
    if n_error != ok || want_error != ok { ret false }
    let (factor, factor_error) = big.factor_ecm(a, n, b1, curves, seed)
    if factor_error != ok { ret false }
    ret big.int_cmp(factor, expected) == 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let fox = "The quick brown fox jumps over the lazy dog"
    // 1: Fletcher and LRC on the Wikipedia vectors.
    if hash.fletcher16("abcde") != 51440u16 || hash.fletcher32("abcde") != 4031760169u32 || hash.fletcher64("abcde") != 14467467625952928454u64 { os.exit(1i32) }
    if hash.fletcher16(fox) != 65256u16 || hash.fletcher32(fox) != 1405967245u32 || hash.fletcher64(fox) != 8909736117919956087u64 { os.exit(1i32) }
    if hash.lrc("abcde") != 97u8 || hash.lrc(fox) != 79u8 || hash.lrc("") != 0u8 || hash.fletcher(fox) != 1405967245u32 { os.exit(1i32) }

    // 2: MurmurHash3 against mmh3.
    if hash.murmur3(fox, 0u32) != 776992547u32 || hash.murmur3_32(fox, 0u32) != 776992547u32 || hash.murmur3_32("abc", 42u32) != 1313807976u32 || hash.murmur3_32("", 0u32) != 0u32 { os.exit(2i32) }
    let (fox_lo, fox_hi) = hash.murmur3_x64_128(fox, 0u64)
    if fox_lo != 16378391709484522348u64 || fox_hi != 8809951995912426311u64 { os.exit(2i32) }
    let (abc_lo, abc_hi) = hash.murmur3_x64_128("abc", 42u64)
    if abc_lo != 974194376405153750u64 || abc_hi != 8435366532673256752u64 { os.exit(2i32) }
    var run: [37]u8 = zero
    var i = 0usize
    while i < 37usize {
        run[i] = u8(i)
        i += 1usize
    }
    let (run_lo, run_hi) = hash.murmur3_x64_128(run[..], 7u64)
    if run_lo != 16114569852788912550u64 || run_hi != 11533222817013231618u64 { os.exit(2i32) }

    // 3: Zobrist table, position hash and toggle.
    var table: [768]u64 = zero
    hash.zobrist(12345u64, table[..])
    if table[0usize] != 2454886589211414944u64 || table[767usize] != 5209268318894398032u64 { os.exit(3i32) }
    let slots = [3]u32{ 196u32, 508u32, 12u32 }
    let position = hash.zobrist_hash(table[..], slots[..])
    if position != 10315143986628295883u64 { os.exit(3i32) }
    let moved = hash.zobrist_toggle(position, table[..], 329u32)
    if moved != 13020843408889548534u64 || hash.zobrist_toggle(moved, table[..], 329u32) != position { os.exit(3i32) }

    // 4: bitset set operations into a third set.
    var wa: [2]u64 = zero
    var wb: [2]u64 = zero
    var wc: [2]u64 = zero
    let (sa0, ea) = bits.init(wa[..], 100usize)
    let (sb0, eb) = bits.init(wb[..], 100usize)
    let (sc0, ec) = bits.init(wc[..], 100usize)
    if ea != ok || eb != ok || ec != ok { os.exit(4i32) }
    var sa = sa0
    var sb = sb0
    var sc = sc0
    i = 0usize
    while i < 100usize {
        if i % 3usize == 0usize { bits.set(&sa, i) }
        if i % 5usize == 0usize { bits.set(&sb, i) }
        i += 1usize
    }
    bits.intersect(&sa, &sb, &sc)
    if bits.count(&sc) != 7usize || !bits.get(&sc, 45usize) || !bits.is_subset(&sc, &sa) || bits.is_subset(&sa, &sb) { os.exit(4i32) }
    bits.union_into(&sa, &sb, &sc)
    if bits.count(&sc) != 47usize || !bits.get(&sc, 10usize) || bits.get(&sc, 11usize) { os.exit(4i32) }
    bits.difference(&sa, &sb, &sc)
    if bits.count(&sc) != 27usize || bits.get(&sc, 15usize) || !bits.get(&sc, 3usize) { os.exit(4i32) }

    // 5: a BDD from the tree ((x0 and x1) or not x2) xor x3.
    var variable: [64]u32 = zero
    var low: [64]u32 = zero
    var high: [64]u32 = zero
    var keys: [256]u64 = zero
    var values: [256]u32 = zero
    let (b0, make_error) = bdd.bdd(variable[..], low[..], high[..], 4usize)
    if make_error != ok { os.exit(5i32) }
    var b = b0
    let kind = [8]bdd.Expr{ .Var, .Var, .And, .Var, .Not, .Or, .Var, .Xor }
    let left = [8]u32{ 0u32, 1u32, 0u32, 2u32, 3u32, 2u32, 3u32, 5u32 }
    let right = [8]u32{ 0u32, 0u32, 1u32, 0u32, 0u32, 4u32, 0u32, 6u32 }
    let (f, build_error) = bdd.build(&b, kind[..], left[..], right[..], 7u32, keys[..], values[..])
    if build_error != ok || bdd.count(&b, f) != 8u64 { os.exit(5i32) }
    let truth = [16]u8{ 1u8, 0u8, 0u8, 1u8, 1u8, 0u8, 0u8, 1u8, 1u8, 0u8, 0u8, 1u8, 1u8, 0u8, 1u8, 0u8 }
    var assignment: [4]bool = zero
    var mask = 0usize
    while mask < 16usize {
        assignment[0usize] = (mask & 8usize) == 8usize
        assignment[1usize] = (mask & 4usize) == 4usize
        assignment[2usize] = (mask & 2usize) == 2usize
        assignment[3usize] = (mask & 1usize) == 1usize
        if bdd.evaluate(&b, f, assignment[..]) != (truth[mask] == 1u8) { os.exit(5i32) }
        mask += 1usize
    }

    // 6: ECM splits a 21x30-bit and a 32x32-bit semiprime; a prime is NotFound; even answers 2.
    if !check_ecm(a, "562953723052109", 2000u64, 200usize, 1u64, "536870923") { os.exit(6i32) }
    if !check_ecm(a, "6521908894648437971", 2000u64, 60usize, 1u64, "3037000493") { os.exit(6i32) }
    if !check_ecm(a, "1000", 100u64, 1usize, 1u64, "2") { os.exit(6i32) }
    let (prime, prime_error) = big.int_parse(a, "1000003", 10u8)
    let (_, none_error) = big.factor_ecm(a, prime, 500u64, 5usize, 1u64)
    if prime_error != ok || none_error != big.NotFound { os.exit(6i32) }

    // 7: TSP on ten LCG cities: Christofides within 3/2 of the brute-force optimum,
    // 3-opt and Lin-Kernighan reach it from the nearest-neighbour tour.
    var xs: [10]f64 = zero
    var ys: [10]f64 = zero
    var state = 99u64
    i = 0usize
    while i < 10usize {
        xs[i] = f64(lcg(&state) % 1000u64)
        ys[i] = f64(lcg(&state) % 1000u64)
        i += 1usize
    }
    var d: [100]f64 = zero
    i = 0usize
    while i < 10usize {
        var j = 0usize
        while j < 10usize {
            d[i * 10usize + j] = math.sqrt[f64]((xs[i] - xs[j]) * (xs[i] - xs[j]) + (ys[i] - ys[j]) * (ys[i] - ys[j]))
            j += 1usize
        }
        i += 1usize
    }
    let optimum = 2331.4856815807743f64
    var tour: [10]usize = zero
    var scratch: [104]usize = zero
    var flags: [30]u8 = zero
    let (christofides_len, christofides_error) = combopt.tsp_christofides(d[..], 10usize, tour[..], scratch[..], flags[..])
    if christofides_error != ok || !is_permutation(tour[..], 10usize, flags[..]) { os.exit(7i32) }
    if !near(christofides_len, 2362.8053897112122f64, 1.0e-9f64) || christofides_len > 1.5f64 * optimum { os.exit(7i32) }
    let (nn_len, nn_error) = combopt.tsp_nearest_neighbor(d[..], 10usize, 0usize, tour[..], flags[..])
    if nn_error != ok || !near(nn_len, 3121.251866282714f64, 1.0e-9f64) { os.exit(7i32) }
    let (three_len, three_moves, three_error) = combopt.tsp_three_opt(d[..], 10usize, tour[..])
    if three_error != ok || three_moves != 6usize || !near(three_len, optimum, 1.0e-9f64) || !is_permutation(tour[..], 10usize, flags[..]) { os.exit(7i32) }
    let (_, nn2_error) = combopt.tsp_nearest_neighbor(d[..], 10usize, 0usize, tour[..], flags[..])
    let (lk_len, lk_rounds, lk_error) = combopt.tsp_lin_kernighan(d[..], 10usize, tour[..], scratch[..], 5usize, 5usize)
    if nn2_error != ok || lk_error != ok || lk_rounds == 0usize || !near(lk_len, optimum, 1.0e-9f64) || !is_permutation(tour[..], 10usize, flags[..]) { os.exit(7i32) }

    // 8: virtual nodes, uniform and weighted, and the load they take.
    var points: [200]ring.Point = zero
    let nodes = [4]u64{ 101u64, 202u64, 303u64, 404u64 }
    var key_list: [1000]u64 = zero
    i = 0usize
    while i < 1000usize {
        key_list[i] = u64(i)
        i += 1usize
    }
    var counts: [4]usize = zero
    let none: [0]u32 = zero
    let (uniform, uniform_error) = ring.virtual_nodes(points[..], nodes[..], 50u32, none[..])
    if uniform_error != ok || uniform.len != 200usize { os.exit(8i32) }
    if ring.virtual_nodes_load(uniform, key_list[..], nodes[..], counts[..]) != ok { os.exit(8i32) }
    if counts[0usize] != 206usize || counts[1usize] != 289usize || counts[2usize] != 220usize || counts[3usize] != 285usize { os.exit(8i32) }
    let weights = [4]u32{ 1u32, 2u32, 3u32, 4u32 }
    let (weighted, weighted_error) = ring.virtual_nodes(points[..], nodes[..], 10u32, weights[..])
    if weighted_error != ok || weighted.len != 100usize { os.exit(8i32) }
    if ring.virtual_nodes_load(weighted, key_list[..], nodes[..], counts[..]) != ok { os.exit(8i32) }
    if counts[0usize] != 88usize || counts[1usize] != 241usize || counts[2usize] != 223usize || counts[3usize] != 448usize { os.exit(8i32) }
    let (_, zero_error) = ring.virtual_nodes(points[..], nodes[..], 0u32, none[..])
    if zero_error != ring.Invalid { os.exit(8i32) }

    // 9: global cardinality prunes by the lower bound, the upper bound, and reports unsat.
    var doms = [9]u8{ 1u8, 1u8, 0u8, 1u8, 1u8, 0u8, 1u8, 1u8, 1u8 }
    let vars = [3]usize{ 0usize, 1usize, 2usize }
    let lo_a = [3]usize{ 0usize, 0usize, 1usize }
    let hi_a = [3]usize{ 3usize, 3usize, 1usize }
    if csp.global_cardinality(doms[..], 3usize, vars[..], lo_a[..], hi_a[..]) != ok { os.exit(9i32) }
    let want_a = [9]u8{ 1u8, 1u8, 0u8, 1u8, 1u8, 0u8, 0u8, 0u8, 1u8 }
    i = 0usize
    while i < 9usize {
        if doms[i] != want_a[i] { os.exit(9i32) }
        i += 1usize
    }
    var doms_b = [9]u8{ 1u8, 0u8, 0u8, 1u8, 1u8, 0u8, 1u8, 1u8, 1u8 }
    let lo_b = [3]usize{ 0usize, 0usize, 0usize }
    let hi_b = [3]usize{ 1usize, 1usize, 3usize }
    if csp.global_cardinality(doms_b[..], 3usize, vars[..], lo_b[..], hi_b[..]) != ok { os.exit(9i32) }
    let want_b = [9]u8{ 1u8, 0u8, 0u8, 0u8, 1u8, 0u8, 0u8, 0u8, 1u8 }
    i = 0usize
    while i < 9usize {
        if doms_b[i] != want_b[i] { os.exit(9i32) }
        i += 1usize
    }
    var doms_c = [9]u8{ 1u8, 1u8, 0u8, 1u8, 0u8, 1u8, 0u8, 1u8, 1u8 }
    let lo_c = [3]usize{ 3usize, 0usize, 0usize }
    let hi_c = [3]usize{ 3usize, 3usize, 3usize }
    if csp.global_cardinality(doms_c[..], 3usize, vars[..], lo_c[..], hi_c[..]) != csp.Unsatisfiable { os.exit(9i32) }

    // 10: the rollback union-find undoes unions in order and keeps ranks honest.
    var parent: [8]u32 = zero
    var rank: [8]u8 = zero
    var log: [16]u32 = zero
    let (rs0, rs_error) = dsu.rollback_init(parent[..], rank[..], log[..], 8usize)
    if rs_error != ok { os.exit(10i32) }
    var rs = rs0
    let (u1, e1) = dsu.rollback_union(&rs, 0u32, 1u32)
    let mark1 = dsu.snapshot(&rs)
    let (u2, e2) = dsu.rollback_union(&rs, 2u32, 3u32)
    let (u3, e3) = dsu.rollback_union(&rs, 1u32, 3u32)
    let (u4, e4) = dsu.rollback_union(&rs, 0u32, 2u32)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || !u1 || !u2 || !u3 || u4 { os.exit(10i32) }
    if mark1 != 1usize || dsu.rollback_set_count(&rs) != 5usize || !dsu.rollback_same(&rs, 0u32, 2u32) { os.exit(10i32) }
    dsu.rollback(&rs, mark1)
    if dsu.rollback_set_count(&rs) != 7usize || dsu.rollback_same(&rs, 0u32, 2u32) || !dsu.rollback_same(&rs, 0u32, 1u32) || dsu.rollback_same(&rs, 2u32, 3u32) { os.exit(10i32) }
    dsu.rollback(&rs, 0usize)
    if dsu.rollback_set_count(&rs) != 8usize || dsu.rollback_same(&rs, 0u32, 1u32) || rank[0usize] != 0u8 { os.exit(10i32) }
    let (u5, e5) = dsu.rollback_union(&rs, 4u32, 5u32)
    if e5 != ok || !u5 || !dsu.rollback_same(&rs, 4u32, 5u32) || dsu.snapshot(&rs) != 1usize { os.exit(10i32) }

    // 11: Barnes-Hut accelerations within 1% of the direct sum on 200 bodies.
    var bx: [200]f64 = zero
    var by: [200]f64 = zero
    var bz: [200]f64 = zero
    var bm: [200]f64 = zero
    state = 7u64
    i = 0usize
    while i < 200usize {
        bx[i] = f64(lcg(&state) % 1000u64) / 10.0f64
        by[i] = f64(lcg(&state) % 1000u64) / 10.0f64
        bz[i] = f64(lcg(&state) % 1000u64) / 10.0f64
        bm[i] = 1.0f64 + f64(lcg(&state) % 10u64)
        i += 1usize
    }
    var child: [32768]u32 = zero
    var body: [4096]u32 = zero
    var node_mass: [4096]f64 = zero
    var cx: [4096]f64 = zero
    var cy: [4096]f64 = zero
    var cz: [4096]f64 = zero
    let (tree, tree_error) = g3.barnes_hut_build(bx[..], by[..], bz[..], bm[..], child[..], body[..], node_mass[..], cx[..], cy[..], cz[..])
    if tree_error != ok { os.exit(11i32) }
    var ax: [200]f64 = zero
    var ay: [200]f64 = zero
    var az: [200]f64 = zero
    if g3.barnes_hut(&tree, 0.5f64, ax[..], ay[..], az[..]) != ok { os.exit(11i32) }
    var direct_sum = 0.0f64
    var error_sum = 0.0f64
    i = 0usize
    while i < 200usize {
        var acc = g3.vec3(0.0f64, 0.0f64, 0.0f64)
        var j = 0usize
        while j < 200usize {
            if j != i {
                let delta = g3.vec3(bx[j] - bx[i], by[j] - by[i], bz[j] - bz[i])
                let r2 = g3.dot(delta, delta)
                acc = g3.add(acc, g3.scale(delta, bm[j] / (r2 * math.sqrt[f64](r2))))
            }
            j += 1usize
        }
        if i == 0usize && !(near(acc.x, 0.04692562920600082f64, 1.0e-9f64) && near(acc.y, 0.1521494576681055f64, 1.0e-9f64) && near(acc.z, 0.0f64 - 0.054548965769218f64, 1.0e-9f64)) { os.exit(11i32) }
        direct_sum += g3.length(acc)
        error_sum += g3.length(g3.sub(g3.vec3(ax[i], ay[i], az[i]), acc))
        i += 1usize
    }
    if !near(direct_sum, 67.97999697128925f64, 1.0e-6f64) || error_sum > 0.01f64 * direct_sum { os.exit(11i32) }

    // 12: the planned `householder` reflects x onto the first axis.
    let x = [3]f64{ 3.0f64, 1.0f64, 2.0f64 }
    var v: [3]f64 = zero
    let (beta, reflect_error) = matrix.householder(x[..], v[..])
    if reflect_error != ok || v[0usize] != 1.0f64 { os.exit(12i32) }
    let vx = v[0usize] * x[0usize] + v[1usize] * x[1usize] + v[2usize] * x[2usize]
    let hx0 = x[0usize] - beta * v[0usize] * vx
    let hx1 = x[1usize] - beta * v[1usize] * vx
    let hx2 = x[2usize] - beta * v[2usize] * vx
    if !near(math.abs[f64](hx0), 3.7416573867739413f64, 1.0e-12f64) || !near(hx1, 0.0f64, 1.0e-12f64) || !near(hx2, 0.0f64, 1.0e-12f64) { os.exit(12i32) }

    // 13: ternary search minimises a parabola on integers and on a real interval.
    var cup = Bowl { center: 37i64 }
    if search.ternary[Bowl](0i64 - 100i64, 100i64, &cup, bowl) != 37i64 || search.ternary_min_i64[Bowl](0i64 - 100i64, 100i64, &cup, bowl) != 37i64 { os.exit(13i32) }
    if search.ternary_min_i64[Bowl](37i64, 37i64, &cup, bowl) != 37i64 || search.ternary_min_i64[Bowl](40i64, 90i64, &cup, bowl) != 40i64 { os.exit(13i32) }
    var plate = Dish { center: 2.5f64 }
    let at_min = search.ternary_min_f64[Dish](0.0f64, 10.0f64, 100usize, &plate, dish)
    if !near(at_min, 2.5f64, 1.0e-6f64) { os.exit(13i32) }

    try io.print("algo gaps a ok\n")
    ret ok
}
