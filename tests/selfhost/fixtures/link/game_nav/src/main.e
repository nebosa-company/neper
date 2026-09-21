// `e.game.nav`: the rectangle navmesh covers every walkable cell exactly once with
// the region and portal counts of a Python replica, the funnel pulls the corners of
// three hand-built corridors, the flow field's integrated costs match Dijkstra and
// every direction descends, and HPA* answers a valid path within 5% of exact BFS on
// twenty maps and exactly when one cluster is the whole map. Each check exits with
// its own code.

use e.game.nav
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn fill_map(seed: u64, walk: []u8, cells: usize) {
    var state = seed
    var i = 0usize
    while i < cells {
        walk[i] = 1u8
        if draw(&state) % 100u64 < 25u64 { walk[i] = 0u8 }
        i += 1usize
    }
}

fn pt(x: f64, y: f64) -> nav.Pt { ret nav.Pt { x: x, y: y } }

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: navmesh on three 12x8 maps.
    var walk: [96]u8 = zero
    var regions: [96]nav.Rect = zero
    var portals: [256]nav.Portal = zero
    var region_of: [96]u32 = zero
    var want_regions: [3]usize = zero
    var want_portals: [3]usize = zero
    want_regions[0usize] = 22usize
    want_regions[1usize] = 18usize
    want_regions[2usize] = 22usize
    want_portals[0usize] = 26usize
    want_portals[1usize] = 18usize
    want_portals[2usize] = 24usize
    var k = 0usize
    while k < 3usize {
        fill_map(1000u64 + u64(k), walk[..], 96usize)
        let (rc, pc, e) = nav.build_navmesh(walk[..], 12usize, 8usize, regions[..], portals[..], region_of[..])
        if e != ok || rc != want_regions[k] || pc != want_portals[k] { os.exit(1i32) }
        var area = 0usize
        var walkable = 0usize
        var i = 0usize
        while i < 96usize {
            if walk[i] == 0u8 {
                if region_of[i] != nav.NONE { os.exit(1i32) }
            } else {
                walkable += 1usize
                let r = regions[usize(region_of[i])]
                let x = u32(i % 12usize)
                let y = u32(i / 12usize)
                if x < r.x || x >= r.x + r.w || y < r.y || y >= r.y + r.h { os.exit(1i32) }
            }
            i += 1usize
        }
        i = 0usize
        while i < rc {
            area += usize(regions[i].w) * usize(regions[i].h)
            i += 1usize
        }
        if area != walkable { os.exit(1i32) }
        i = 0usize
        while i < pc {
            if portals[i].a >= portals[i].b || portals[i].b >= u32(rc) { os.exit(1i32) }
            if portals[i].x0 == portals[i].x1 && portals[i].y0 >= portals[i].y1 { os.exit(1i32) }
            i += 1usize
        }
        k += 1usize
    }

    // 2: funnel over an L corridor, a straight one and a zigzag.
    var left: [11]nav.Pt = zero
    var right: [11]nav.Pt = zero
    var corners: [16]nav.Pt = zero
    left[0usize] = pt(1.0f64, 1.0f64)
    left[1usize] = pt(2.0f64, 1.0f64)
    left[2usize] = pt(3.0f64, 1.0f64)
    left[3usize] = pt(4.0f64, 1.0f64)
    left[4usize] = pt(4.0f64, 1.0f64)
    left[5usize] = pt(4.0f64, 2.0f64)
    left[6usize] = pt(4.0f64, 3.0f64)
    right[0usize] = pt(1.0f64, 0.0f64)
    right[1usize] = pt(2.0f64, 0.0f64)
    right[2usize] = pt(3.0f64, 0.0f64)
    right[3usize] = pt(4.0f64, 0.0f64)
    right[4usize] = pt(5.0f64, 1.0f64)
    right[5usize] = pt(5.0f64, 2.0f64)
    right[6usize] = pt(5.0f64, 3.0f64)
    let (na, ea) = nav.funnel(pt(0.5f64, 0.5f64), pt(4.5f64, 3.5f64), left[..7usize], right[..7usize], corners[..])
    if ea != ok || na != 3usize { os.exit(2i32) }
    if corners[1usize].x != 4.0f64 || corners[1usize].y != 1.0f64 || corners[2usize].x != 4.5f64 || corners[2usize].y != 3.5f64 { os.exit(2i32) }
    let (nb, eb) = nav.funnel(pt(0.5f64, 0.5f64), pt(3.5f64, 0.5f64), right[..3usize], left[..3usize], corners[..])
    if eb != ok || nb != 2usize || corners[1usize].x != 3.5f64 { os.exit(2i32) }
    left[7usize] = pt(4.0f64, 3.0f64)
    left[8usize] = pt(3.0f64, 3.0f64)
    left[9usize] = pt(2.0f64, 3.0f64)
    left[10usize] = pt(1.0f64, 3.0f64)
    right[7usize] = pt(4.0f64, 4.0f64)
    right[8usize] = pt(3.0f64, 4.0f64)
    right[9usize] = pt(2.0f64, 4.0f64)
    right[10usize] = pt(1.0f64, 4.0f64)
    let (nc, ec) = nav.funnel(pt(0.5f64, 0.5f64), pt(0.5f64, 3.5f64), left[..], right[..], corners[..])
    if ec != ok || nc != 4usize { os.exit(2i32) }
    if corners[1usize].x != 4.0f64 || corners[1usize].y != 1.0f64 || corners[2usize].x != 4.0f64 || corners[2usize].y != 3.0f64 { os.exit(2i32) }
    let (_, tiny) = nav.funnel(pt(0.5f64, 0.5f64), pt(0.5f64, 3.5f64), left[..], right[..], corners[..2usize])
    if tiny != nav.TooSmall { os.exit(2i32) }

    // 3: flow field on three 16x12 cost maps.
    var cost: [192]u8 = zero
    var dist: [192]u32 = zero
    var dir: [192]u8 = zero
    var heap: [768]u64 = zero
    var want_reach: [3]usize = zero
    var want_total: [3]u64 = zero
    var want_hash: [3]u64 = zero
    want_reach[0usize] = 139usize
    want_reach[1usize] = 151usize
    want_reach[2usize] = 132usize
    want_total[0usize] = 6229u64
    want_total[1usize] = 3517u64
    want_total[2usize] = 3471u64
    want_hash[0usize] = 8066131120112436338u64
    want_hash[1usize] = 4099819149166266578u64
    want_hash[2usize] = 11272298439240431923u64
    k = 0usize
    while k < 3usize {
        var state = 2000u64 + u64(k) * 7u64
        var i = 0usize
        while i < 192usize {
            let v = draw(&state)
            cost[i] = 1u8 + u8(v % 3u64)
            if v % 100u64 < 25u64 { cost[i] = 0u8 }
            i += 1usize
        }
        cost[191usize] = 1u8
        if nav.flow_field(cost[..], 16usize, 12usize, 191usize, dist[..], dir[..], heap[..]) != ok { os.exit(3i32) }
        var reach = 0usize
        var total = 0u64
        var hash = 0u64
        i = 0usize
        while i < 192usize {
            hash = hash *% 31u64 +% u64(dist[i])
            if dist[i] != nav.NONE {
                reach += 1usize
                total += u64(dist[i])
                if i != 191usize {
                    if dir[i] == 0u8 { os.exit(3i32) }
                    var n = i
                    if dir[i] == 1u8 { n = i + 1usize }
                    if dir[i] == 2u8 { n = i + 16usize }
                    if dir[i] == 3u8 { n = i - 1usize }
                    if dir[i] == 4u8 { n = i - 16usize }
                    if dist[n] >= dist[i] { os.exit(3i32) }
                }
            } else {
                if dir[i] != 0u8 { os.exit(3i32) }
            }
            i += 1usize
        }
        if reach != want_reach[k] || total != want_total[k] || hash != want_hash[k] { os.exit(3i32) }
        k += 1usize
    }
    if nav.flow_field(cost[..], 16usize, 12usize, 192usize, dist[..], dir[..], heap[..]) != nav.Invalid { os.exit(3i32) }

    // 4: HPA* on twenty 24x16 maps with 8x8 clusters, then one cluster over the whole map.
    var grid: [384]u8 = zero
    var node_cell: [128]u32 = zero
    var node_of: [384]u32 = zero
    var edge_from: [2048]u32 = zero
    var edge_to: [2048]u32 = zero
    var edge_cost: [2048]u32 = zero
    var hdist: [384]u32 = zero
    var came: [384]u32 = zero
    var queue: [384]u32 = zero
    var adist: [128]u32 = zero
    var acame: [128]u32 = zero
    var aheap: [2048]u64 = zero
    var path: [384]u32 = zero
    var exact: [20]u32 = zero
    exact[0usize] = 38u32
    exact[1usize] = 38u32
    exact[2usize] = 38u32
    exact[3usize] = 38u32
    exact[4usize] = 38u32
    exact[5usize] = 38u32
    exact[6usize] = 38u32
    exact[7usize] = 40u32
    exact[8usize] = 38u32
    exact[9usize] = nav.NONE
    exact[10usize] = 38u32
    exact[11usize] = 38u32
    exact[12usize] = 38u32
    exact[13usize] = 44u32
    exact[14usize] = 38u32
    exact[15usize] = 38u32
    exact[16usize] = nav.NONE
    exact[17usize] = nav.NONE
    exact[18usize] = 38u32
    exact[19usize] = 38u32
    var g = nav.Hpa { walk: grid[..], w: 24usize, h: 16usize, c: 8usize, node_cell: node_cell[..], node_of: node_of[..], node_count: 0usize, edge_from: edge_from[..], edge_to: edge_to[..], edge_cost: edge_cost[..], edge_count: 0usize, dist: hdist[..], came: came[..], queue: queue[..], adist: adist[..], acame: acame[..], heap: aheap[..] }
    k = 0usize
    while k < 21usize {
        var seed = 3000u64 + u64(k)
        if k == 20usize {
            seed = 3013u64
            g.c = 64usize
        }
        fill_map(seed, grid[..], 384usize)
        grid[0usize] = 1u8
        grid[383usize] = 1u8
        if nav.build_hpa(&g) != ok { os.exit(4i32) }
        let (cost_found, length, e) = nav.hierarchical_astar(&g, 0usize, 383usize, path[..])
        var want = 44u32
        if k < 20usize { want = exact[k] }
        if want == nav.NONE {
            if e != nav.Unreachable { os.exit(4i32) }
            k += 1usize
            continue
        }
        if e != ok { os.exit(5i32) }
        if cost_found < want || cost_found * 100u32 > want * 105u32 { os.exit(6i32) }
        if k == 20usize && cost_found != want { os.exit(6i32) }
        if length != usize(cost_found) + 1usize || path[0usize] != 0u32 || path[length - 1usize] != 383u32 { os.exit(7i32) }
        var i = 1usize
        while i < length {
            let p = usize(path[i - 1usize])
            let q = usize(path[i])
            if grid[q] == 0u8 { os.exit(7i32) }
            var step = true
            if p / 24usize == q / 24usize {
                if p + 1usize != q && q + 1usize != p { step = false }
            } else {
                if p + 24usize != q && q + 24usize != p { step = false }
            }
            if !step { os.exit(7i32) }
            i += 1usize
        }
        k += 1usize
    }
    let (_, one, e_same) = nav.hierarchical_astar(&g, 5usize, 5usize, path[..])
    if e_same != ok || one != 1usize || path[0usize] != 5u32 { os.exit(8i32) }

    try io.print("game nav ok\n")
    ret ok
}
