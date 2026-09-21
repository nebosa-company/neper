// `e.data.link_cut`: a link-cut tree and an Euler tour tree agree with a
// BFS over an explicit edge set through 260 random link, cut, path-sum and
// set-value operations on 40 vertices; the checksums of the path sums and
// the operation counts match the Python reference. Each check exits with
// its own code.

use e.data.link_cut as lc
use e.io
use e.mem
use e.os

const N: usize = 40usize

fn rng(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

// BFS from `u`: the sum of values along the path to `v`, or false if apart.
fn brute(adj: []const bool, value: []const i64, u: u32, v: u32) -> (i64, bool) {
    var par: [41]u32 = zero
    var seen: [41]bool = zero
    var queue: [41]u32 = zero
    var head = 0usize
    var tail = 1usize
    queue[0usize] = u
    seen[usize(u)] = true
    while head < tail {
        let x = queue[head]
        head += 1usize
        var y = 1usize
        while y <= N {
            if adj[usize(x) * (N + 1usize) + y] && !seen[y] {
                seen[y] = true
                par[y] = x
                queue[tail] = u32(y)
                tail += 1usize
            }
            y += 1usize
        }
    }
    if !seen[usize(v)] { ret (0i64, false) }
    var s = 0i64
    var x = v
    while x != u {
        s += value[usize(x)]
        x = par[usize(x)]
    }
    ret (s + value[usize(u)], true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var left: [41]u32 = zero
    var right: [41]u32 = zero
    var parent: [41]u32 = zero
    var rev: [41]bool = zero
    var value: [41]i64 = zero
    var sum: [41]i64 = zero
    var eleft: [169]u32 = zero
    var eright: [169]u32 = zero
    var eparent: [169]u32 = zero
    var edge_u: [64]u32 = zero
    var edge_v: [64]u32 = zero
    var adj: [1681]bool = zero
    var state = 12345u64
    var i = 1usize
    while i <= N {
        value[i] = i64(rng(&state) % 1000u64) - 500i64
        i += 1usize
    }

    // 1: storage too small.
    let (_, small) = lc.link_cut(N, left[..N], right[..], parent[..], rev[..], value[..], sum[..])
    if small != lc.TooSmall { os.exit(1i32) }
    let (_, esmall) = lc.euler_tour_tree(N, eleft[..168usize], eright[..], eparent[..], edge_u[..], edge_v[..])
    if esmall != lc.TooSmall { os.exit(1i32) }
    var (t, build_error) = lc.link_cut(N, left[..], right[..], parent[..], rev[..], value[..], sum[..])
    if build_error != ok { os.exit(1i32) }
    var (e, ebuild_error) = lc.euler_tour_tree(N, eleft[..], eright[..], eparent[..], edge_u[..], edge_v[..])
    if ebuild_error != ok { os.exit(1i32) }

    // 2: vertices outside 1..=n and self-edges are refused.
    if lc.access(&t, 0u32) != lc.Invalid || lc.link(&t, 41u32, 1u32) != lc.Invalid || lc.link(&t, 3u32, 3u32) != lc.Invalid { os.exit(2i32) }
    let (_, apart) = lc.path_sum(&t, 1u32, 2u32)
    if apart != lc.Invalid || lc.cut(&t, 1u32, 1u32) != lc.Invalid { os.exit(2i32) }
    if lc.ett_link(&e, 0u32, 1u32) != lc.Invalid || lc.ett_link(&e, 5u32, 5u32) != lc.Invalid || lc.ett_connected(&e, 0u32, 1u32) { os.exit(2i32) }
    let (own, _) = lc.path_sum(&t, 7u32, 7u32)
    if own != value[7usize] || !lc.connected(&t, 7u32, 7u32) || !lc.ett_connected(&e, 7u32, 7u32) { os.exit(2i32) }

    // 3..8: random operations against BFS on the edge matrix.
    var acc = 0u64
    var hits = 0usize
    var links = 0usize
    var cuts = 0usize
    var step = 0usize
    while step < 260usize {
        var op = rng(&state) % 8u64
        var u = u32(rng(&state) % u64(N)) + 1u32
        var v = u32(rng(&state) % u64(N)) + 1u32
        let (_, joined) = brute(adj[..], value[..], u, v)
        if lc.connected(&t, u, v) != joined { os.exit(3i32) }
        if lc.ett_connected(&e, u, v) != joined { os.exit(7i32) }
        if op == 4u64 {
            var edges = 0usize
            var x = 1usize
            while x <= N {
                var y = x + 1usize
                while y <= N {
                    if adj[x * (N + 1usize) + y] { edges += 1usize }
                    y += 1usize
                }
                x += 1usize
            }
            if edges > 0usize {
                if !adj[usize(u) * (N + 1usize) + usize(v)] && (lc.cut(&t, u, v) != lc.Invalid || lc.ett_cut(&e, u, v) != lc.Invalid) { os.exit(6i32) }
                var pick = usize(rng(&state) % u64(edges))
                x = 1usize
                var found = false
                while x <= N && !found {
                    var y = x + 1usize
                    while y <= N && !found {
                        if adj[x * (N + 1usize) + y] {
                            if pick == 0usize {
                                found = true
                                u = u32(x)
                                v = u32(y)
                            } else {
                                pick -= 1usize
                            }
                        }
                        y += 1usize
                    }
                    x += 1usize
                }
                if lc.cut(&t, u, v) != ok || lc.ett_cut(&e, u, v) != ok { os.exit(6i32) }
                adj[usize(u) * (N + 1usize) + usize(v)] = false
                adj[usize(v) * (N + 1usize) + usize(u)] = false
                cuts += 1usize
                step += 1usize
                continue
            }
            op = 5u64
        }
        if op <= 3u64 {
            let link_error = lc.link(&t, u, v)
            let ett_error = lc.ett_link(&e, u, v)
            if joined {
                if link_error != lc.Invalid || ett_error != lc.Invalid { os.exit(5i32) }
            } else {
                if link_error != ok || ett_error != ok { os.exit(8i32) }
                adj[usize(u) * (N + 1usize) + usize(v)] = true
                adj[usize(v) * (N + 1usize) + usize(u)] = true
                links += 1usize
            }
        } else if op <= 6u64 {
            let (expected, _) = brute(adj[..], value[..], u, v)
            let (got, sum_error) = lc.path_sum(&t, u, v)
            if joined {
                if sum_error != ok || got != expected { os.exit(4i32) }
                hits += 1usize
                acc = acc *% 31u64 +% u64(got + 1000000i64)
            } else if sum_error != lc.Invalid {
                os.exit(4i32)
            }
        } else {
            let fresh = i64(rng(&state) % 1000u64) - 500i64
            value[usize(u)] = fresh
            if lc.set_value(&t, u, fresh) != ok { os.exit(4i32) }
        }
        step += 1usize
    }

    // 9: the checksums match the Python reference.
    if acc != 17129975330128156343u64 || hits != 38usize || links != 63usize || cuts != 32usize { os.exit(9i32) }

    try io.print("data link_cut ok\n")
    ret ok
}
