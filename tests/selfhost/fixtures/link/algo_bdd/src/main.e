// `e.algo.bdd`: diagrams of (x0 and x1) or x2 and of x0 xor x1 xor x2
// evaluate like the formulas on every assignment and count their models,
// two constructions of one function share a node (canonicity), negation
// complements the count, and a full pool is reported. Each check exits
// with its own code.

use e.algo.bdd as bdd
use e.io
use e.mem
use e.os
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    var variable: [2048]u32 = zero
    var low: [2048]u32 = zero
    var high: [2048]u32 = zero
    var keys: [256]u64 = zero
    var values: [256]u32 = zero
    var counts: [2048]u64 = zero
    var memo = 0usize
    let (b0, make_error) = bdd.bdd(variable[..], low[..], high[..], 3usize)
    if make_error != ok { os.exit(1i32) }
    var b = b0
    let (x0, _) = bdd.var_node(&b, 0usize)
    let (x1, _) = bdd.var_node(&b, 1usize)
    let (x2, e2) = bdd.var_node(&b, 2usize)
    if e2 != ok || x0 != x0 || x1 == x2 { os.exit(1i32) }

    // 1: (x0 and x1) or x2.
    let (both, and_error) = bdd.apply(&b, .And, x0, x1, keys[..], values[..], &memo)
    memo = 0usize
    let (f, or_error) = bdd.apply(&b, .Or, both, x2, keys[..], values[..], &memo)
    if and_error != ok || or_error != ok { os.exit(1i32) }
    var assignment: [3]bool = zero
    var mask = 0usize
    while mask < 8usize {
        assignment[0usize] = (mask & 1usize) == 1usize
        assignment[1usize] = (mask & 2usize) == 2usize
        assignment[2usize] = (mask & 4usize) == 4usize
        let want = (assignment[0usize] && assignment[1usize]) || assignment[2usize]
        if bdd.evaluate(&b, f, assignment[..]) != want { os.exit(1i32) }
        mask += 1usize
    }
    let (count_f, cf_error) = bdd.count(&b, f, counts[..])
    let (count_x2, cx2_error) = bdd.count(&b, x2, counts[..])
    let (count_both, cb_error) = bdd.count(&b, both, counts[..])
    if cf_error != ok || cx2_error != ok || cb_error != ok || count_f != 5u64 || count_x2 != 4u64 || count_both != 2u64 { os.exit(1i32) }

    // 2: x0 xor x1 xor x2 has four models; canonicity.
    memo = 0usize
    let (x01, xa) = bdd.apply(&b, .Xor, x0, x1, keys[..], values[..], &memo)
    memo = 0usize
    let (parity, xb) = bdd.apply(&b, .Xor, x01, x2, keys[..], values[..], &memo)
    let (count_parity, cp_error) = bdd.count(&b, parity, counts[..])
    if xa != ok || xb != ok || cp_error != ok || count_parity != 4u64 { os.exit(2i32) }
    memo = 0usize
    let (x12, xc) = bdd.apply(&b, .Xor, x1, x2, keys[..], values[..], &memo)
    memo = 0usize
    let (parity2, xd) = bdd.apply(&b, .Xor, x0, x12, keys[..], values[..], &memo)
    if xc != ok || xd != ok || parity2 != parity { os.exit(2i32) }
    // Or of the two forms is the same node; and with its negation is false.
    memo = 0usize
    let (again, xe) = bdd.apply(&b, .Or, parity, parity2, keys[..], values[..], &memo)
    if xe != ok || again != parity { os.exit(2i32) }
    memo = 0usize
    let (not_parity, ne) = bdd.negate(&b, parity, keys[..], values[..], &memo)
    let (count_not, cn_error) = bdd.count(&b, not_parity, counts[..])
    if ne != ok || cn_error != ok || count_not != 4u64 { os.exit(2i32) }
    memo = 0usize
    let (contradiction, ce) = bdd.apply(&b, .And, parity, not_parity, keys[..], values[..], &memo)
    if ce != ok || contradiction != 0u32 { os.exit(2i32) }
    memo = 0usize
    let (tautology, te) = bdd.apply(&b, .Or, parity, not_parity, keys[..], values[..], &memo)
    let (count_taut, ct_error) = bdd.count(&b, tautology, counts[..])
    if te != ok || tautology != 1u32 || ct_error != ok || count_taut != 8u64 { os.exit(2i32) }
    let (_, bad_var) = bdd.var_node(&b, 3usize)
    if bad_var != bdd.Invalid { os.exit(2i32) }

    // 3: a full pool.
    let (t0, t_error) = bdd.bdd(variable[..3usize], low[..3usize], high[..3usize], 2usize)
    if t_error != ok { os.exit(3i32) }
    var t = t0
    let (y0, y0_error) = bdd.var_node(&t, 0usize)
    let (_, y1_error) = bdd.var_node(&t, 1usize)
    if y0_error != ok || y0 != 2u32 || y1_error != bdd.TooSmall { os.exit(3i32) }

    // 4-6: #277. A diagram cannot have 64 variables (its count would be 2^64); a
    // cyclic expression answers Invalid; and a chain parity diagram is counted once
    // per node, not once per assignment prefix. `vars`/`cycle`/`count` select one
    // check for pre-fix evidence.
    var mode: str = ""
    if args.len > 1usize { mode = args[1usize] }
    if mode.len == 0usize || str.eq(mode, "vars") {
        let (_, too_many) = bdd.bdd(variable[..], low[..], high[..], 64usize)
        if too_many != bdd.Invalid { os.exit(4i32) }
    }
    if mode.len == 0usize || str.eq(mode, "cycle") {
        var cycle_kind: [2]bdd.Expr = zero
        cycle_kind[0usize] = .Not
        cycle_kind[1usize] = .Not
        var cycle_left: [2]u32 = zero
        cycle_left[0usize] = 1u32
        cycle_left[1usize] = 0u32
        var cycle_right: [2]u32 = zero
        let (_, cycle_error) = bdd.build(&b, cycle_kind[..], cycle_left[..], cycle_right[..], 1u32, keys[..], values[..])
        if cycle_error != bdd.Invalid { os.exit(5i32) }
    }
    if mode.len == 0usize || str.eq(mode, "count") {
        let (p0, p_error) = bdd.bdd(variable[..], low[..], high[..], 30usize)
        if p_error != ok { os.exit(6i32) }
        var p = p0
        let (x0p, x0e) = bdd.var_node(&p, 0usize)
        if x0e != ok { os.exit(6i32) }
        var chain = x0p
        var vi = 1usize
        while vi < 30usize {
            memo = 0usize
            let (xv, xve) = bdd.var_node(&p, vi)
            let (next_chain, pe) = bdd.apply(&p, .Xor, chain, xv, keys[..], values[..], &memo)
            if xve != ok || pe != ok { os.exit(6i32) }
            chain = next_chain
            vi += 1usize
        }
        let (chain_count, cc_error) = bdd.count(&p, chain, counts[..])
        if cc_error != ok || chain_count != 536870912u64 { os.exit(6i32) }
    }

    try io.print("algo bdd ok\n")
    ret ok
}
