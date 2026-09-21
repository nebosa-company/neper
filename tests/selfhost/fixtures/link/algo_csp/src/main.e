// `e.algo.csp`: AC-3 prunes a chain of strict inequalities, MAC solves
// 4-queens, limited discrepancy search finds it too, all-different applies
// a Hall pruning, element, table and cumulative filter as expected, and the
// unsatisfiable cases answer. Each check exits with its own code.

use e.algo.csp as csp
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

fn less(ctx: *Nothing, x: usize, y: usize, a: usize, b: usize) -> bool {
    if x < y { ret a < b }
    ret a > b
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

    try io.print("algo csp ok\n")
    ret ok
}
