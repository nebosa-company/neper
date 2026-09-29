// `e.algo.csp`: AC-3 prunes a chain of strict inequalities, MAC solves
// 4-queens, limited discrepancy search finds it too, all-different applies
// a Hall pruning, element, table and cumulative filter as expected, and the
// unsatisfiable cases answer. AC-2001 reaches AC-3's domains and answers
// with no more constraint checks (checks 5..10). Both accept a queue exactly
// as long as the arc count and wrap in it when an arc is re-queued (check 11).
// Each check exits with its own code.

use e.algo.csp as csp
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn less(ctx: *Nothing, x: usize, y: usize, a: usize, b: usize) -> bool {
    if x < y { ret a < b }
    ret a > b
}

// The lower-numbered variable at least two values below the other.
fn gap(ctx: *Nothing, x: usize, y: usize, a: usize, b: usize) -> bool {
    if x < y { ret a + 2usize <= b }
    ret b + 2usize <= a
}

fn queens(ctx: *Nothing, x: usize, y: usize, a: usize, b: usize) -> bool {
    if a == b { ret false }
    var dx = x
    var dy = y
    if dx < dy {
        let t = dx
        dx = dy
        dy = t
    }
    var da = a
    var db = b
    if da < db {
        let t = da
        da = db
        db = t
    }
    ret dx - dy != da - db
}

fn set_all(domains: []u8, n: usize, k: usize) {
    var i = 0usize
    while i < n * k {
        domains[i] = 1u8
        i += 1usize
    }
}

// AC-2001 checks (5..10): constraints as a relation table `rel[x][y][a][b]`
// whose `allowed` counts its calls. Expected domains, answers and call counts
// come from vectors_ac2001.py: instances 0..2 are the chain over 4 and 2
// values and 4-queens, 3..22 random binary CSPs from the LCG.
type Table = struct { calls: usize, fewer: usize, n: usize, k: usize, rel: [900]u8 }
type Lcg = struct { s: u64 }

fn table_allowed(t: *Table, x: usize, y: usize, a: usize, b: usize) -> bool {
    t.calls = t.calls + 1usize
    ret t.rel[((x * t.n + y) * t.k + a) * t.k + b] != 0u8
}

fn rnd(g: *Lcg) -> u64 {
    g.s = g.s *% 6364136223846793005u64 +% 1442695040888963407u64
    ret g.s >> 33u32
}

fn clear_rel(t: *Table, n: usize, k: usize) {
    t.n = n
    t.k = k
    var i = 0usize
    while i < 900usize {
        t.rel[i] = 0u8
        i += 1usize
    }
}

fn set_rel(t: *Table, x: usize, y: usize, a: usize, b: usize, v: u8) {
    t.rel[((x * t.n + y) * t.k + a) * t.k + b] = v
    t.rel[((y * t.n + x) * t.k + b) * t.k + a] = v
}

fn fill(t: *Table, n: usize, k: usize, pairs: []const usize, pred: fn(*Nothing, usize, usize, usize, usize) -> bool) {
    var nothing = Nothing { unused: 0u8 }
    clear_rel(t, n, k)
    var p = 0usize
    while p < pairs.len {
        var a = 0usize
        while a < k {
            var b = 0usize
            while b < k {
                var v = 0u8
                if pred(&nothing, pairs[p], pairs[p + 1usize], a, b) { v = 1u8 }
                set_rel(t, pairs[p], pairs[p + 1usize], a, b, v)
                b += 1usize
            }
            a += 1usize
        }
        p += 2usize
    }
}

fn expected_domains() -> str {
    ret "11000110001110001111111111111111111111111011111111111100011011011010111111110011010111110111011111111111101111111111110011011101011111111111111111111011111100111111100111010101111100111111101000101010000100001110001110011111011011110000111101110110001111110010101101001010010101111101111111011011101111110101110111001010011010011101101111111100111110111111101"
}

fn expected_results() -> str {
    ret "oUooUUoooooooooUoUooooo"
}

fn ac3_calls(i: usize) -> usize {
    let xs = [23]usize { 41usize, 8usize, 90usize, 81usize, 12usize, 17usize, 14usize, 57usize, 8usize, 66usize, 53usize, 8usize, 94usize, 50usize, 22usize, 2usize, 22usize, 37usize, 79usize, 41usize, 35usize, 38usize, 81usize }
    ret xs[i]
}

fn ac2001_calls(i: usize) -> usize {
    let xs = [23]usize { 36usize, 8usize, 90usize, 81usize, 12usize, 17usize, 14usize, 57usize, 8usize, 66usize, 53usize, 8usize, 70usize, 48usize, 22usize, 2usize, 17usize, 37usize, 79usize, 36usize, 29usize, 35usize, 66usize }
    ret xs[i]
}

// Runs ac3 and ac2001 on one instance and compares them with each other and
// with the reference: 6 domains, 7 answer, 8 call counts.
fn run_instance(t: *Table, n: usize, k: usize, pairs: []const usize, start: []const u8, index: usize, offset: usize) -> i32 {
    var d3: [64]u8 = zero
    var d2: [64]u8 = zero
    var queue: [64]usize = zero
    var queued: [64]u8 = zero
    var last: [256]usize = zero
    var i = 0usize
    while i < n * k {
        d3[i] = start[i]
        d2[i] = start[i]
        i += 1usize
    }
    t.calls = 0usize
    let e3 = csp.ac3[Table](d3[..], n, k, pairs, t, table_allowed, queue[..], queued[..])
    let c3 = t.calls
    t.calls = 0usize
    let e2 = csp.ac2001[Table](d2[..], n, k, pairs, t, table_allowed, queue[..], queued[..], last[..])
    let c2 = t.calls
    let want = expected_domains()
    i = 0usize
    while i < n * k {
        // 48 is '0'.
        if d2[i] != d3[i] || d3[i] + 48u8 != want[offset + i] { ret 6i32 }
        i += 1usize
    }
    // 111 is 'o' (ok), anything else 'U' (Unsatisfiable).
    let consistent = expected_results()[index] == 111u8
    if e2 != e3 || (e3 == ok) != consistent || (e3 != ok && e3 != csp.Unsatisfiable) { ret 7i32 }
    if c3 != ac3_calls(index) || c2 != ac2001_calls(index) || c2 > c3 { ret 8i32 }
    if c2 < c3 { t.fewer = t.fewer + 1usize }
    ret 0i32
}

// Runs ac3 and ac2001 on the same start and answers whether domains and result agree.
fn same_as_ac3(n: usize, k: usize, pairs: []const usize, pred: fn(*Nothing, usize, usize, usize, usize) -> bool) -> bool {
    var nothing = Nothing { unused: 0u8 }
    var d3: [64]u8 = zero
    var d2: [64]u8 = zero
    var queue: [64]usize = zero
    var queued: [64]u8 = zero
    var last: [256]usize = zero
    set_all(d3[..], n, k)
    set_all(d2[..], n, k)
    let e3 = csp.ac3[Nothing](d3[..], n, k, pairs, &nothing, pred, queue[..], queued[..])
    let e2 = csp.ac2001[Nothing](d2[..], n, k, pairs, &nothing, pred, queue[..], queued[..], last[..])
    if e2 != e3 { ret false }
    var i = 0usize
    while i < n * k {
        if d2[i] != d3[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check_ac2001() -> i32 {
    // 5: the existing examples, with the plain predicates.
    var chain: [4]usize = zero
    chain[1usize] = 1usize
    chain[2usize] = 1usize
    chain[3usize] = 2usize
    var qp: [12]usize = zero
    var p = 0usize
    var i = 0usize
    while i < 4usize {
        var j = i + 1usize
        while j < 4usize {
            qp[p] = i
            qp[p + 1usize] = j
            p += 2usize
            j += 1usize
        }
        i += 1usize
    }
    if !same_as_ac3(3usize, 4usize, chain[..], less) || !same_as_ac3(3usize, 2usize, chain[..], less) || !same_as_ac3(4usize, 4usize, qp[..], queens) { ret 5i32 }

    // 6..8: the same three through the counting table, then 20 random CSPs.
    var t = Table { calls: 0usize, fewer: 0usize, n: 0usize, k: 0usize, rel: zero }
    var start: [64]u8 = zero
    var offset = 0usize
    fill(&t, 3usize, 4usize, chain[..], less)
    set_all(start[..], 3usize, 4usize)
    var code = run_instance(&t, 3usize, 4usize, chain[..], start[..], 0usize, offset)
    if code != 0i32 { ret code }
    offset += 12usize
    fill(&t, 3usize, 2usize, chain[..], less)
    set_all(start[..], 3usize, 2usize)
    code = run_instance(&t, 3usize, 2usize, chain[..], start[..], 1usize, offset)
    if code != 0i32 { ret code }
    offset += 6usize
    fill(&t, 4usize, 4usize, qp[..], queens)
    set_all(start[..], 4usize, 4usize)
    code = run_instance(&t, 4usize, 4usize, qp[..], start[..], 2usize, offset)
    if code != 0i32 { ret code }
    offset += 16usize
    var g = Lcg { s: 2001u64 }
    var rp: [30]usize = zero
    var index = 3usize
    while index < 23usize {
        let n = 3usize + usize(rnd(&g) % 4u64)
        let k = 2usize + usize(rnd(&g) % 4u64)
        var m = 0usize
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                if rnd(&g) % 100u64 < 60u64 {
                    rp[m] = i
                    rp[m + 1usize] = j
                    m += 2usize
                }
                j += 1usize
            }
            i += 1usize
        }
        clear_rel(&t, n, k)
        p = 0usize
        while p < m {
            var a = 0usize
            while a < k {
                var b = 0usize
                while b < k {
                    var v = 0u8
                    if rnd(&g) % 100u64 < 55u64 { v = 1u8 }
                    set_rel(&t, rp[p], rp[p + 1usize], a, b, v)
                    b += 1usize
                }
                a += 1usize
            }
            p += 2usize
        }
        i = 0usize
        while i < n * k {
            start[i] = 1u8
            if rnd(&g) % 6u64 == 0u64 { start[i] = 0u8 }
            i += 1usize
        }
        code = run_instance(&t, n, k, rp[..m], start[..], index, offset)
        if code != 0i32 { ret code }
        offset += n * k
        index += 1usize
    }
    // 9: never more checks than AC-3 (checked above), strictly fewer somewhere.
    if t.fewer == 0usize { ret 9i32 }

    // 10: a `last` table one entry short is refused.
    var d: [12]u8 = zero
    var queue: [4]usize = zero
    var queued: [4]u8 = zero
    var last: [15]usize = zero
    set_all(d[..], 3usize, 4usize)
    if csp.ac2001[Table](d[..], 3usize, 4usize, chain[..], &t, table_allowed, queue[..], queued[..], last[..]) != csp.TooSmall { ret 10i32 }

    // 11: four variables over 0..7, two apart along 0-1-2-3 and 0-3, with a queue of
    // exactly the 8 arcs: pruning re-queues arcs, which must wrap to slot 0. Both
    // reach {0,1} {2,3} {4,5} {6,7}.
    var nothing = Nothing { unused: 0u8 }
    var talks = [8]usize{ 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 0usize, 3usize }
    var exact_queue: [8]usize = zero
    var exact_queued: [8]u8 = zero
    var talk_last: [64]usize = zero
    var d3: [32]u8 = zero
    var d2: [32]u8 = zero
    set_all(d3[..], 4usize, 8usize)
    set_all(d2[..], 4usize, 8usize)
    if csp.ac3[Nothing](d3[..], 4usize, 8usize, talks[..], &nothing, gap, exact_queue[..], exact_queued[..]) != ok { ret 11i32 }
    if csp.ac2001[Nothing](d2[..], 4usize, 8usize, talks[..], &nothing, gap, exact_queue[..], exact_queued[..], talk_last[..]) != ok { ret 11i32 }
    var v = 0usize
    while v < 32usize {
        let want = (v % 8usize) / 2usize == v / 8usize
        if (d3[v] == 1u8) != want || (d2[v] == 1u8) != want { ret 11i32 }
        v += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nothing = Nothing { unused: 0u8 }
    var domains: [64]u8 = zero
    var queue: [64]usize = zero
    var queued: [64]u8 = zero

    // 1: AC-3 on x < y < z over 0..3.
    set_all(domains[..], 3usize, 4usize)
    var pairs: [4]usize = zero
    pairs[1usize] = 1usize
    pairs[2usize] = 1usize
    pairs[3usize] = 2usize
    if csp.ac3[Nothing](domains[..], 3usize, 4usize, pairs[..], &nothing, less, queue[..], queued[..]) != ok { os.exit(1i32) }
    // x in {0,1}, y in {1,2}, z in {2,3}.
    if domains[0usize] != 1u8 || domains[1usize] != 1u8 || domains[2usize] != 0u8 || domains[3usize] != 0u8 { os.exit(1i32) }
    if domains[4usize] != 0u8 || domains[5usize] != 1u8 || domains[6usize] != 1u8 || domains[7usize] != 0u8 { os.exit(1i32) }
    if domains[8usize] != 0u8 || domains[9usize] != 0u8 || domains[10usize] != 1u8 || domains[11usize] != 1u8 { os.exit(1i32) }
    // With only two values the chain is impossible.
    set_all(domains[..], 3usize, 2usize)
    if csp.ac3[Nothing](domains[..], 3usize, 2usize, pairs[..], &nothing, less, queue[..], queued[..]) != csp.Unsatisfiable { os.exit(1i32) }

    // 2: 4-queens by MAC and by limited discrepancy.
    set_all(domains[..], 4usize, 4usize)
    var all_pairs: [12]usize = zero
    var p = 0usize
    var i = 0usize
    while i < 4usize {
        var j = i + 1usize
        while j < 4usize {
            all_pairs[p] = i
            all_pairs[p + 1usize] = j
            p += 2usize
            j += 1usize
        }
        i += 1usize
    }
    var assignment: [4]usize = zero
    var saved: [64]u8 = zero
    let (solved, solve_error) = csp.solve[Nothing](domains[..], 4usize, 4usize, all_pairs[..], &nothing, queens, assignment[..], saved[..], queue[..], queued[..])
    if solve_error != ok || !solved { os.exit(2i32) }
    // One of the two solutions: (1,3,0,2) or (2,0,3,1).
    let first = assignment[0usize] == 1usize && assignment[1usize] == 3usize && assignment[2usize] == 0usize && assignment[3usize] == 2usize
    let second = assignment[0usize] == 2usize && assignment[1usize] == 0usize && assignment[2usize] == 3usize && assignment[3usize] == 1usize
    if !first && !second { os.exit(2i32) }
    set_all(domains[..], 3usize, 3usize)
    var three_pairs: [6]usize = zero
    three_pairs[1usize] = 1usize
    three_pairs[3usize] = 2usize
    three_pairs[4usize] = 1usize
    three_pairs[5usize] = 2usize
    let (three, three_error) = csp.solve[Nothing](domains[..], 3usize, 3usize, three_pairs[..], &nothing, queens, assignment[..], saved[..], queue[..], queued[..])
    if three_error != ok || three { os.exit(2i32) }
    set_all(domains[..], 4usize, 4usize)
    let (found, discrepancies, lds_error) = csp.limited_discrepancy[Nothing](domains[..], 4usize, 4usize, all_pairs[..], &nothing, queens, 6usize, assignment[..])
    if lds_error != ok || !found || discrepancies == 0usize { os.exit(2i32) }
    if !(assignment[0usize] == 1usize && assignment[1usize] == 3usize && assignment[2usize] == 0usize && assignment[3usize] == 2usize) { os.exit(2i32) }
    let (none, _, lds3) = csp.limited_discrepancy[Nothing](domains[..], 4usize, 4usize, all_pairs[..], &nothing, queens, 0usize, assignment[..])
    if lds3 != ok || none { os.exit(2i32) }

    // 3: all-different Hall pruning: x, y in {0,1}, z in {0,1,2} -> z = 2.
    set_all(domains[..], 3usize, 3usize)
    domains[2usize] = 0u8
    domains[5usize] = 0u8
    var vars: [3]usize = zero
    vars[1usize] = 1usize
    vars[2usize] = 2usize
    var match_value: [3]usize = zero
    var seen: [3]u8 = zero
    if csp.all_different(domains[..], 3usize, vars[..], match_value[..], seen[..]) != ok { os.exit(3i32) }
    if domains[6usize] != 0u8 || domains[7usize] != 0u8 || domains[8usize] != 1u8 || domains[0usize] != 1u8 || domains[1usize] != 1u8 { os.exit(3i32) }
    domains[8usize] = 0u8
    if csp.all_different(domains[..], 3usize, vars[..], match_value[..], seen[..]) != csp.Unsatisfiable { os.exit(3i32) }

    // 4: element, table, cumulative.
    set_all(domains[..], 2usize, 4usize)
    var array: [4]usize = zero
    array[0usize] = 2usize
    array[1usize] = 3usize
    array[2usize] = 2usize
    array[3usize] = 0usize
    // result (variable 1) in {2, 3} only.
    domains[4usize] = 0u8
    domains[5usize] = 0u8
    if csp.element(domains[..], 4usize, 0usize, 1usize, array[..]) != ok { os.exit(4i32) }
    // index keeps 0, 1, 2 (values 2, 3, 2), loses 3 (value 0).
    if domains[0usize] != 1u8 || domains[1usize] != 1u8 || domains[2usize] != 1u8 || domains[3usize] != 0u8 { os.exit(4i32) }
    set_all(domains[..], 2usize, 3usize)
    var tuples: [6]usize = zero
    tuples[0usize] = 0usize
    tuples[1usize] = 1usize
    tuples[2usize] = 1usize
    tuples[3usize] = 2usize
    tuples[4usize] = 2usize
    tuples[5usize] = 0usize
    var two: [2]usize = zero
    two[1usize] = 1usize
    domains[3usize] = 0u8
    // y cannot be 0: the tuple (2, 0) dies, so x loses 2.
    if csp.table(domains[..], 3usize, two[..], tuples[..], 3usize) != ok { os.exit(4i32) }
    if domains[2usize] != 0u8 || domains[0usize] != 1u8 || domains[1usize] != 1u8 || domains[4usize] != 1u8 || domains[5usize] != 1u8 { os.exit(4i32) }
    // Cumulative: two tasks of duration 3, demand 1, capacity 1, starts in 0..4, horizon 8.
    set_all(domains[..], 2usize, 5usize)
    var starts_vars: [2]usize = zero
    starts_vars[1usize] = 1usize
    var duration: [2]usize = zero
    duration[0usize] = 3usize
    duration[1usize] = 3usize
    var demand: [2]usize = zero
    demand[0usize] = 1usize
    demand[1usize] = 1usize
    var profile: [8]usize = zero
    if csp.cumulative(domains[..], 5usize, starts_vars[..], duration[..], demand[..], 1usize, 8usize, profile[..]) != ok { os.exit(4i32) }
    // Fix task 0 at start 1 (covers 1..4): task 1 may start only at 4.
    domains[0usize] = 0u8
    domains[2usize] = 0u8
    domains[3usize] = 0u8
    domains[4usize] = 0u8
    if csp.cumulative(domains[..], 5usize, starts_vars[..], duration[..], demand[..], 1usize, 8usize, profile[..]) != ok { os.exit(4i32) }
    if domains[5usize] != 0u8 || domains[6usize] != 0u8 || domains[7usize] != 0u8 || domains[8usize] != 0u8 || domains[9usize] != 1u8 { os.exit(4i32) }
    demand[1usize] = 2usize
    domains[9usize] = 1u8
    if csp.cumulative(domains[..], 5usize, starts_vars[..], duration[..], demand[..], 1usize, 8usize, profile[..]) != csp.Unsatisfiable { os.exit(4i32) }

    // 5..10: AC-2001 against AC-3.
    let ac2001_code = check_ac2001()
    if ac2001_code != 0i32 { os.exit(ac2001_code) }

    try io.print("algo csp ok\n")
    ret ok
}
