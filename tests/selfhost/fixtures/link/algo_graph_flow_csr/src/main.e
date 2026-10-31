// Invalid CSR offsets must be rejected before max_min_fair reads links or
// overwrites the caller's rates.
use e.algo.graph.flow
use e.mem
use e.os

fn unchanged(rate: []const f64, first: f64, second: f64) -> bool {
    if rate.len > 0usize && rate[0usize] != first { ret false }
    if rate.len > 1usize && rate[1usize] != second { ret false }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var capacity: [1]f64 = zero
    capacity[0usize] = 4.0f64
    var links: [1]u32 = zero

    // The terminal offset points one past the link slice.
    var past: [2]usize = zero
    past[1usize] = 2usize
    var one_rate: [1]f64 = zero
    one_rate[0usize] = 17.0f64
    let (_, past_error) = flow.max_min_fair(a, capacity[..], past[..], links[..], one_rate[..])
    if past_error != flow.InvalidFlow || !unchanged(one_rate[..], 17.0f64, 0.0f64) { os.exit(1) }

    // A decreasing row boundary is not an empty flow.
    var decreasing: [3]usize = zero
    decreasing[1usize] = 1usize
    var two_rates: [2]f64 = zero
    two_rates[0usize] = 19.0f64
    two_rates[1usize] = 23.0f64
    let (_, decreasing_error) = flow.max_min_fair(a, capacity[..], decreasing[..], links[..], two_rates[..])
    if decreasing_error != flow.InvalidFlow || !unchanged(two_rates[..], 19.0f64, 23.0f64) { os.exit(2) }

    // The first CSR boundary must be zero, and the final one must cover every link.
    var nonzero_start: [2]usize = zero
    nonzero_start[0usize] = 1usize
    nonzero_start[1usize] = 1usize
    let (_, start_error) = flow.max_min_fair(a, capacity[..], nonzero_start[..], links[..], one_rate[..])
    if start_error != flow.InvalidFlow || !unchanged(one_rate[..], 17.0f64, 0.0f64) { os.exit(3) }
    var trailing: [2]usize = zero
    let (_, trailing_error) = flow.max_min_fair(a, capacity[..], trailing[..], links[..], one_rate[..])
    if trailing_error != flow.InvalidFlow || !unchanged(one_rate[..], 17.0f64, 0.0f64) { os.exit(4) }

    // Link IDs are checked only after the CSR partition is known sound.
    var valid: [2]usize = zero
    valid[1usize] = 1usize
    links[0usize] = 1u32
    let (_, link_error) = flow.max_min_fair(a, capacity[..], valid[..], links[..], one_rate[..])
    if link_error != flow.InvalidNode || !unchanged(one_rate[..], 17.0f64, 0.0f64) { os.exit(5) }
    ret ok
}
