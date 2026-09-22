// `e.ui.state`: the diamond a -> b, a -> c, d = b + c runs d once per set
// with no mixed state, a memo that keeps its value leaves its effect
// asleep, a batch runs an effect once, a dynamic dependency stops
// re-running when no longer read, dispose stops runs, per-node run counts
// match the Python replica, and exhausted node storage answers TooSmall.
// Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.ui.state

type Ctx = struct { a: u32, b: u32, c: u32, d: u32, above: u32, flag: u32, s1: u32, log_node: [128]u32, log_value: [128]i64, log_len: usize }

fn log(c: *Ctx, node: u32, value: i64) {
    if c.log_len < 128usize {
        c.log_node[c.log_len] = node
        c.log_value[c.log_len] = value
        c.log_len += 1usize
    }
}

fn compute_b(c: *Ctx, g: *state.Graph[Ctx]) -> i64 { ret state.get[Ctx](g, c.a) * 2i64 }
fn compute_c(c: *Ctx, g: *state.Graph[Ctx]) -> i64 { ret state.get[Ctx](g, c.a) + 100i64 }
fn compute_d(c: *Ctx, g: *state.Graph[Ctx]) -> i64 { ret state.get[Ctx](g, c.b) + state.get[Ctx](g, c.c) }
fn watch_d(c: *Ctx, g: *state.Graph[Ctx]) { log(c, c.d, state.get[Ctx](g, c.d)) }
fn compute_above(c: *Ctx, g: *state.Graph[Ctx]) -> i64 {
    if state.get[Ctx](g, c.a) > 5i64 { ret 1i64 }
    ret 0i64
}
fn watch_above(c: *Ctx, g: *state.Graph[Ctx]) { log(c, c.above, state.get[Ctx](g, c.above)) }
fn watch_dyn(c: *Ctx, g: *state.Graph[Ctx]) {
    if state.get[Ctx](g, c.flag) != 0i64 {
        log(c, 99u32, state.get[Ctx](g, c.s1))
    } else {
        log(c, 99u32, 0i64 - 1i64)
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var value: [16]i64 = zero
    var kind: [16]u8 = zero
    var height: [16]u32 = zero
    var dirty: [16]u8 = zero
    var runs: [16]u32 = zero
    var compute: [16]fn(*Ctx, *state.Graph[Ctx]) -> i64 = zero
    var run: [16]fn(*Ctx, *state.Graph[Ctx]) = zero
    var from: [64]u32 = zero
    var to: [64]u32 = zero
    var c: Ctx = zero
    let (made, graph_error) = state.graph[Ctx](&c, value[..], kind[..], height[..], dirty[..], runs[..], compute[..], run[..], from[..], to[..])
    if graph_error != ok { os.exit(1i32) }
    var g = made

    // 1: the diamond; d runs once per set and sees b and c from the same a.
    let (sa, ea) = state.signal[Ctx](&g, 1i64)
    if ea != ok { os.exit(1i32) }
    c.a = sa
    let (mb, eb) = state.memo[Ctx](&g, compute_b)
    let (mc, ec) = state.memo[Ctx](&g, compute_c)
    if eb != ok || ec != ok { os.exit(1i32) }
    c.b = mb
    c.c = mc
    let (md, ed) = state.memo[Ctx](&g, compute_d)
    if ed != ok { os.exit(1i32) }
    c.d = md
    let (e_d, eed) = state.effect[Ctx](&g, watch_d)
    if eed != ok { os.exit(1i32) }
    if state.get[Ctx](&g, md) != 103i64 || c.log_len != 1usize || c.log_value[0] != 103i64 { os.exit(1i32) }
    c.log_len = 0usize
    if state.set[Ctx](&g, sa, 5i64) != ok { os.exit(1i32) }
    if state.set[Ctx](&g, sa, 7i64) != ok { os.exit(1i32) }
    if c.log_len != 2usize || c.log_node[0] != md || c.log_value[0] != 115i64 || c.log_node[1] != md || c.log_value[1] != 121i64 { os.exit(1i32) }
    if state.run_count[Ctx](&g, md) != 3u32 || state.run_count[Ctx](&g, e_d) != 3u32 || state.get[Ctx](&g, md) != 121i64 { os.exit(1i32) }
    if state.height_of[Ctx](&g, md) != 2u32 || state.height_of[Ctx](&g, e_d) != 3u32 { os.exit(1i32) }

    // 2: memo equality: `a > 5` wakes its effect only when crossing 5.
    let (mabove, eabove) = state.memo[Ctx](&g, compute_above)
    if eabove != ok { os.exit(2i32) }
    c.above = mabove
    let (e_above, eeabove) = state.effect[Ctx](&g, watch_above)
    if eeabove != ok { os.exit(2i32) }
    var seed = 12345u64
    var step = 0usize
    while step < 20usize {
        seed = seed *% 6364136223846793005u64 +% 1442695040888963407u64
        let x = i64((seed >> 33u32) % 12u64)
        if state.set[Ctx](&g, sa, x) != ok { os.exit(2i32) }
        step += 1usize
    }
    if state.run_count[Ctx](&g, mabove) != 19u32 || state.run_count[Ctx](&g, e_above) != 12u32 || state.get[Ctx](&g, mabove) != 0i64 { os.exit(2i32) }

    // 3: three sets inside a batch run the effect once.
    let before = state.run_count[Ctx](&g, e_d)
    if before != 21u32 { os.exit(3i32) }
    state.batch_begin[Ctx](&g)
    if state.set[Ctx](&g, sa, 20i64) != ok || state.set[Ctx](&g, sa, 30i64) != ok || state.set[Ctx](&g, sa, 40i64) != ok { os.exit(3i32) }
    if state.run_count[Ctx](&g, e_d) != 21u32 { os.exit(3i32) }
    if state.batch_end[Ctx](&g) != ok { os.exit(3i32) }
    if state.run_count[Ctx](&g, e_d) != 22u32 || state.get[Ctx](&g, md) != 220i64 || state.run_count[Ctx](&g, mb) != 22u32 { os.exit(3i32) }

    // 4: a dynamic dependency: s1 is read only while flag is set.
    let (sflag, eflag) = state.signal[Ctx](&g, 1i64)
    let (ss1, es1) = state.signal[Ctx](&g, 10i64)
    if eflag != ok || es1 != ok { os.exit(4i32) }
    c.flag = sflag
    c.s1 = ss1
    let (e_dyn, edyn) = state.effect[Ctx](&g, watch_dyn)
    if edyn != ok { os.exit(4i32) }
    if state.set[Ctx](&g, ss1, 11i64) != ok || state.run_count[Ctx](&g, e_dyn) != 2u32 { os.exit(4i32) }
    if state.set[Ctx](&g, sflag, 0i64) != ok || state.run_count[Ctx](&g, e_dyn) != 3u32 { os.exit(4i32) }
    if state.set[Ctx](&g, ss1, 12i64) != ok || state.set[Ctx](&g, ss1, 13i64) != ok { os.exit(4i32) }
    if state.run_count[Ctx](&g, e_dyn) != 3u32 { os.exit(4i32) }
    if state.set[Ctx](&g, sflag, 1i64) != ok || state.run_count[Ctx](&g, e_dyn) != 4u32 { os.exit(4i32) }
    if c.log_node[c.log_len - 1usize] != 99u32 || c.log_value[c.log_len - 1usize] != 13i64 { os.exit(4i32) }

    // 5: dispose stops runs.
    if state.dispose[Ctx](&g, e_dyn) != ok { os.exit(5i32) }
    if state.set[Ctx](&g, ss1, 50i64) != ok || state.set[Ctx](&g, sflag, 0i64) != ok { os.exit(5i32) }
    if state.run_count[Ctx](&g, e_dyn) != 4u32 { os.exit(5i32) }

    // 6: per-node run counts, edge count and heights equal the replica.
    let expected_runs = [10]u32{ 0u32, 22u32, 22u32, 22u32, 22u32, 20u32, 13u32, 0u32, 0u32, 4u32 }
    let expected_heights = [10]u32{ 0u32, 1u32, 1u32, 2u32, 3u32, 1u32, 2u32, 0u32, 0u32, 1u32 }
    var i = 0usize
    while i < 10usize {
        if state.run_count[Ctx](&g, u32(i)) != expected_runs[i] || state.height_of[Ctx](&g, u32(i)) != expected_heights[i] { os.exit(6i32) }
        i += 1usize
    }
    if state.edge_count[Ctx](&g) != 7usize { os.exit(6i32) }

    // 7: node storage exhausted answers TooSmall; misuse answers Invalid.
    var extra = 0usize
    while extra < 6usize {
        let (_, e) = state.signal[Ctx](&g, 0i64)
        if e != ok { os.exit(7i32) }
        extra += 1usize
    }
    let (_, full) = state.signal[Ctx](&g, 0i64)
    if full != state.TooSmall { os.exit(7i32) }
    let (_, full_memo) = state.memo[Ctx](&g, compute_b)
    if full_memo != state.TooSmall { os.exit(7i32) }
    if state.set[Ctx](&g, md, 1i64) != state.Invalid || state.set[Ctx](&g, 200u32, 1i64) != state.Invalid { os.exit(7i32) }
    if state.dispose[Ctx](&g, 200u32) != state.Invalid { os.exit(7i32) }

    try io.print("ui state ok\n")
    ret ok
}
