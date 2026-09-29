use e.io
use e.mem
use e.math.opt.milp

// Move 43 pallets today at the least cost. A truck (70) takes 12 pallets and there
// are 3; a van (35) takes 5; overtime (9 an hour, at most 6) moves 1 pallet an hour.
// Trucks and vans come in whole numbers; overtime hours do not.
fn main(a: *mem.Arena, args: []str) -> err {
    let inf = milp.infinity()
    //                 trucks   vans     overtime
    var c = [3]f64{ 70.0f64, 35.0f64, 9.0f64 }
    var row = [3]f64{ 12.0f64, 5.0f64, 1.0f64 }
    var need_lo = [1]f64{ 43.0f64 }
    var need_hi = [1]f64{ inf }
    var lo = [3]f64{ 0.0f64, 0.0f64, 0.0f64 }
    var hi = [3]f64{ 3.0f64, inf, 6.0f64 }
    var whole = [3]bool{ true, true, false }
    let p = milp.Problem { n: 3usize, m: 1usize, c: c[..], a: row[..], row_lower: need_lo[..], row_upper: need_hi[..], lower: lo[..], upper: hi[..], integer: whole[..] }

    // All storage is the caller's: size it for the problem, the cuts and the open nodes.
    let o = milp.defaults()
    let scratch = try mem.alloc[f64](a, milp.scratch_len(3usize, 1usize, o.max_cuts, 256usize))
    let slots = try mem.alloc[usize](a, milp.slot_len(3usize, 1usize, o.max_cuts))
    var x: [3]f64 = zero
    let (r, failure) = milp.solve(&p, o, x[..], scratch, slots)
    if failure != ok { ret failure }
    if r.status == .Optimal {
        try io.printf["cost {.2} with {.0} trucks, {.0} vans, {.1} overtime hours\n"](r.objective, x[0], x[1], x[2])
        try io.printf["{} nodes, {} Gomory cuts\n"](r.nodes, r.cuts)
    }
    ret ok
}
