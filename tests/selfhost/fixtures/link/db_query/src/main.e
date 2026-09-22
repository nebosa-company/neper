// `e.db.query`: LCG-generated orders (200 x 4), customers (60 x 3) and regions
// (5 x 2); the row iterator and the vectorized executor agree with a Python
// brute force over scan -> filter -> project, every join variant yields the
// brute-force multiset (order-free fold of per-row FNV hashes), semi/anti
// counts, the join-size estimate, Selinger's order and cost for a 4-chain,
// predicate and projection pushdown against expected plan arrays, partition
// pruning and the covering index, a CTE scanned twice, TooSmall, and
// `optimize` on a three-table plan. Each check exits with its own code.

use e.db.query
use e.io
use e.mem
use e.os

fn lcg(s: *u64) -> u64 {
    *s = *s *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *s >> 33u32
}

fn row_hash(row: []const i64) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < row.len {
        h = (h ^ u64(row[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn fold(cells: []const i64, w: usize, n: usize) -> u64 {
    var h = 0u64
    var r = 0usize
    while r < n {
        h = h +% row_hash(cells[r * w..(r + 1usize) * w])
        r += 1usize
    }
    ret h
}

fn plan_fold(plan: []const query.Op, n: usize) -> u64 {
    var h = 0u64
    var i = 0usize
    while i < n {
        let op = plan[i]
        h = (h *% 31u64) +% u64(op.kind)
        h = (h *% 31u64) +% u64(op.input_a)
        h = (h *% 31u64) +% u64(op.input_b)
        h = (h *% 31u64) +% u64(op.column)
        h = (h *% 31u64) +% u64(op.column_b)
        h = (h *% 31u64) +% u64(op.value)
        h = (h *% 31u64) +% u64(op.cmp)
        h = (h *% 31u64) +% u64(op.cols.len)
        var k = 0usize
        while k < op.cols.len {
            h = (h *% 31u64) +% u64(op.cols[k])
            k += 1usize
        }
        i += 1usize
    }
    ret h
}

fn main(a: *mem.Arena, args: []str) -> err {
    var s = 12345u64
    var orders: [800]i64 = zero
    var i = 0usize
    while i < 200usize {
        orders[i * 4usize] = i64(i)
        orders[i * 4usize + 1usize] = i64(lcg(&s) % 40u64)
        orders[i * 4usize + 2usize] = i64(lcg(&s) % 1000u64)
        orders[i * 4usize + 3usize] = i64(lcg(&s) % 10u64)
        i += 1usize
    }
    var customers: [180]i64 = zero
    i = 0usize
    while i < 60usize {
        customers[i * 3usize] = i64(lcg(&s) % 40u64)
        customers[i * 3usize + 1usize] = i64(lcg(&s) % 5u64)
        customers[i * 3usize + 2usize] = i64(lcg(&s) % 100u64)
        i += 1usize
    }
    var regions: [10]i64 = zero
    i = 0usize
    while i < 5usize {
        regions[i * 2usize] = i64(i)
        regions[i * 2usize + 1usize] = i64(lcg(&s) % 30u64)
        i += 1usize
    }
    var tables: [4]query.Table = zero
    tables[0usize] = query.table(orders[..], 4usize)
    tables[1usize] = query.table(customers[..], 3usize)
    tables[2usize] = query.table(regions[..], 2usize)

    // 1: the row iterator over scan -> filter(amount > 500) -> project [id, amount].
    var plan: [12]query.Op = zero
    var cols_a: [2]u32 = [2]u32{ 0u32, 2u32 }
    plan[0usize] = query.scan(0u32)
    plan[1usize] = query.filter(0u32, 2u32, query.GT, 500i64)
    plan[2usize] = query.project(1u32, cols_a[..])
    var state: [64]usize = zero
    var buf: [4096]i64 = zero
    var out: [3000]i64 = zero
    let (c0, ce) = query.iterator(plan[..3usize], 2u32, tables[..3usize], state[..], buf[..])
    if ce != ok { os.exit(1i32) }
    var c = c0
    var n = 0usize
    var more = true
    while more {
        let (got, e) = query.next(&c, out[n * 2usize..])
        if e != ok { os.exit(1i32) }
        more = got
        if got { n += 1usize }
    }
    if n != 104usize || fold(out[..], 2usize, n) != 11938013614307805207u64 { os.exit(1i32) }

    // 2: the vectorized executor answers the same, with full and ragged batches.
    let (vn, ve) = query.vectorized(plan[..3usize], 2u32, tables[..3usize], 16usize, state[..], buf[..], out[..])
    if ve != ok || vn != 104usize || fold(out[..], 2usize, vn) != 11938013614307805207u64 { os.exit(2i32) }
    let (vn5, ve5) = query.vectorized(plan[..3usize], 2u32, tables[..3usize], 5usize, state[..], buf[..], out[..])
    if ve5 != ok || vn5 != 104usize || fold(out[..], 2usize, vn5) != 11938013614307805207u64 { os.exit(2i32) }

    // 3: every join variant gives the brute-force multiset.
    let (n3, e3) = query.join_nested_loop(tables[0usize], 1usize, tables[1usize], 0usize, out[..])
    if e3 != ok || n3 != 291usize || fold(out[..], 7usize, n3) != 10131815322498323383u64 { os.exit(3i32) }
    var buckets: [64]u32 = zero
    var chain: [256]u32 = zero
    let (n3h, e3h) = query.join_hash(tables[0usize], 1usize, tables[1usize], 0usize, out[..], buckets[..], chain[..])
    if e3h != ok || n3h != 291usize || fold(out[..], 7usize, n3h) != 10131815322498323383u64 { os.exit(3i32) }
    var index_a: [256]u32 = zero
    var index_b: [256]u32 = zero
    let (n3p, e3p) = query.join_hash_parallel(tables[0usize], 1usize, tables[1usize], 0usize, out[..], 4usize, index_a[..], index_b[..], buckets[..], chain[..])
    if e3p != ok || n3p != 291usize || fold(out[..], 7usize, n3p) != 10131815322498323383u64 { os.exit(3i32) }
    let (n3s, e3s) = query.join_sort_merge(tables[0usize], 1usize, tables[1usize], 0usize, out[..], index_a[..], index_b[..])
    if e3s != ok || n3s != 291usize || fold(out[..], 7usize, n3s) != 10131815322498323383u64 { os.exit(3i32) }
    plan[3usize] = query.scan(1u32)
    plan[4usize] = query.join(0u32, 3u32, 1u32, 0u32)
    let (n3v, e3v) = query.vectorized(plan[..5usize], 4u32, tables[..3usize], 16usize, state[..], buf[..], out[..])
    if e3v != ok || n3v != 291usize || fold(out[..], 7usize, n3v) != 10131815322498323383u64 { os.exit(3i32) }

    // 4: semi and anti joins.
    let (n4s, e4s) = query.join_semi(tables[0usize], 1usize, tables[1usize], 0usize, out[..], buckets[..], chain[..])
    if e4s != ok || n4s != 149usize || fold(out[..], 4usize, n4s) != 15870442478438615314u64 { os.exit(4i32) }
    let (n4a, e4a) = query.join_anti(tables[0usize], 1usize, tables[1usize], 0usize, out[..], buckets[..], chain[..])
    if e4a != ok || n4a != 51usize || fold(out[..], 4usize, n4a) != 4420149721523227797u64 { os.exit(4i32) }

    // 5: |A| * |B| / max(V(A), V(B)).
    if query.estimate_join_size(200u64, 60u64, 40u64, 30u64) != 300.0f64 { os.exit(5i32) }

    // 6: Selinger's order and cost for a four-relation chain.
    var cards: [4]u64 = [4]u64{ 1000u64, 100u64, 10000u64, 50u64 }
    var sel: [16]f64 = zero
    i = 0usize
    while i < 16usize {
        sel[i] = 1.0f64
        i += 1usize
    }
    sel[1usize] = 0.01f64
    sel[4usize] = 0.01f64
    sel[6usize] = 0.001f64
    sel[9usize] = 0.001f64
    sel[11usize] = 0.02f64
    sel[14usize] = 0.02f64
    var order: [8]u32 = zero
    var cost: [256]f64 = zero
    var best: [256]u32 = zero
    let (c6, e6) = query.join_order(cards[..], sel[..], order[..4usize], cost[..], best[..])
    if e6 != ok || c6 != 12000.0f64 { os.exit(6i32) }
    if order[0usize] != 2u32 || order[1usize] != 1u32 || order[2usize] != 3u32 || order[3usize] != 0u32 { os.exit(6i32) }

    // 7: predicate and projection pushdown against the expected plan arrays.
    var cols7: [2]u32 = [2]u32{ 0u32, 5u32 }
    plan[0usize] = query.scan(0u32)
    plan[1usize] = query.scan(1u32)
    plan[2usize] = query.join(0u32, 1u32, 1u32, 0u32)
    plan[3usize] = query.filter(2u32, 2u32, query.GT, 500i64)
    plan[4usize] = query.project(3u32, cols7[..])
    if plan_fold(plan[..], 5usize) != 5436467428139913305u64 { os.exit(7i32) }
    let r7 = query.push_predicates(plan[..5usize], 4u32, tables[..3usize])
    if r7 != 4u32 || plan_fold(plan[..], 5usize) != 1711360582025448537u64 { os.exit(7i32) }
    var cols_scratch: [32]u32 = zero
    var p7 = query.planner(plan[..], 5usize, tables[..3usize], cols_scratch[..])
    let e7 = query.push_projections(&p7, 4u32)
    if e7 != ok || p7.count != 7usize || plan_fold(plan[..], 7usize) != 6330020011051940154u64 { os.exit(7i32) }
    let (n7, e7v) = query.vectorized(plan[..7usize], 4u32, tables[..3usize], 16usize, state[..], buf[..], out[..])
    if e7v != ok || n7 != 170usize || fold(out[..], 2usize, n7) != 17426002689746338647u64 { os.exit(7i32) }

    // 8: partition pruning and the covering index.
    var pmin: [8]i64 = zero
    var pmax: [8]i64 = zero
    i = 0usize
    while i < 8usize {
        pmin[i] = i64(i) * 100i64
        pmax[i] = i64(i) * 100i64 + 99i64
        i += 1usize
    }
    var kept: [8]u32 = zero
    let (n8, e8) = query.prune_partitions(pmin[..], pmax[..], 300i64, 600i64, kept[..])
    if e8 != ok || n8 != 4usize || kept[0usize] != 3u32 || kept[3usize] != 6u32 { os.exit(8i32) }
    var keys: [200]i64 = zero
    var key_rows: [200]u32 = zero
    let (ni, ei) = query.build_index(tables[0usize], 2usize, keys[..], key_rows[..])
    if ei != ok || ni != 200usize { os.exit(8i32) }
    var hits: [200]u32 = zero
    let (nh, eh) = query.index_only_scan(keys[..ni], key_rows[..ni], 300i64, 600i64, hits[..])
    if eh != ok || nh != 56usize { os.exit(8i32) }
    var row_sum = 0u64
    i = 0usize
    while i < nh {
        row_sum += u64(hits[i])
        i += 1usize
    }
    if row_sum != 5849u64 { os.exit(8i32) }

    // 9: a CTE materialised once and scanned twice (self join on the customer key).
    var cols9: [3]u32 = [3]u32{ 0u32, 1u32, 2u32 }
    plan[0usize] = query.scan(0u32)
    plan[1usize] = query.filter(0u32, 2u32, query.GT, 500i64)
    plan[2usize] = query.project(1u32, cols9[..])
    var cte_cells: [400]i64 = zero
    let (cte, e9) = query.materialize_cte(plan[..3usize], 2u32, tables[..3usize], state[..], buf[..], cte_cells[..])
    if e9 != ok || query.rows(cte) != 104usize || cte.columns != 3usize { os.exit(9i32) }
    tables[3usize] = cte
    plan[3usize] = query.scan(3u32)
    plan[4usize] = query.scan(3u32)
    plan[5usize] = query.join(3u32, 4u32, 1u32, 1u32)
    let (n9, e9v) = query.vectorized(plan[..6usize], 5u32, tables[..], 16usize, state[..], buf[..], out[..])
    if e9v != ok || n9 != 372usize || fold(out[..], 6usize, n9) != 4669635235118204824u64 { os.exit(9i32) }

    // 10: TooSmall from the joins, the cursor and the DP tables.
    let (_, e10a) = query.join_nested_loop(tables[0usize], 1usize, tables[1usize], 0usize, out[..10usize])
    if e10a != query.TooSmall { os.exit(10i32) }
    let (_, e10b) = query.iterator(plan[..3usize], 2u32, tables[..3usize], state[..2usize], buf[..])
    if e10b != query.TooSmall { os.exit(10i32) }
    let (_, e10c) = query.join_order(cards[..], sel[..], order[..4usize], cost[..8usize], best[..])
    if e10c != query.TooSmall { os.exit(10i32) }
    let (_, e10d) = query.join_semi(tables[0usize], 1usize, tables[1usize], 0usize, out[..], buckets[..], chain[..8usize])
    if e10d != query.TooSmall { os.exit(10i32) }

    // 11: optimize a three-table plan: filters sink, the join chain is reordered
    // (regions, customers, orders) and projections narrow; the answer is unchanged.
    var cols11: [3]u32 = [3]u32{ 0u32, 5u32, 8u32 }
    plan[0usize] = query.scan(0u32)
    plan[1usize] = query.scan(1u32)
    plan[2usize] = query.scan(2u32)
    plan[3usize] = query.join(0u32, 1u32, 1u32, 0u32)
    plan[4usize] = query.join(3u32, 2u32, 5u32, 0u32)
    plan[5usize] = query.filter(4u32, 2u32, query.GT, 500i64)
    plan[6usize] = query.project(5u32, cols11[..])
    var sel3: [9]f64 = [9]f64{ 1.0, 0.025, 1.0, 0.025, 1.0, 0.2, 1.0, 0.2, 1.0 }
    var p11 = query.planner(plan[..], 7usize, tables[..3usize], cols_scratch[..])
    let (r11, e11) = query.optimize(&p11, 6u32, sel3[..], cost[..], best[..])
    if e11 != ok || r11 != 6u32 || p11.count <= 7usize { os.exit(11i32) }
    if plan[4usize].input_b == 2u32 || plan[3usize].input_a != 2u32 { os.exit(11i32) }
    let (n11, e11v) = query.vectorized(plan[..p11.count], 6u32, tables[..3usize], 16usize, state[..], buf[..], out[..])
    if e11v != ok || n11 != 170usize || fold(out[..], 3usize, n11) != 4825550860999645306u64 { os.exit(11i32) }

    try io.print("db query ok\n")
    ret ok
}
