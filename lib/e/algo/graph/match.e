// Matchings: Hopcroft-Karp for maximum bipartite matching over
// `e.data.graph` edges from a left set to a right set, the Hungarian algorithm
// for the minimum-cost assignment over a square cost matrix, Gale-Shapley
// stable marriage over preference lists, and Edmonds' blossom algorithm for
// maximum matching in a general graph. Results are written to caller slices
// (`NONE` marks an unmatched node); scratch comes from the arena.

use e.mem
use e.data.graph as graph

error Invalid
error TooSmall

const NONE: u32 = 4294967295u32

// Maximum bipartite matching: left nodes are `0..left`, every edge goes from a
// left node to a right node in `left..node_count`. `match_left[l]` receives the
// right node matched to `l` (or `NONE`), `match_right[r - left]` the converse;
// answers the matching size.
fn hopcroft_karp[E: type](a: *mem.Arena, g: *const graph.Graph[E], left: usize, match_left: []u32, match_right: []u32) -> (usize, err) {
    let n = graph.node_count[E](g)
    if left > n { ret (0usize, Invalid) }
    let right = n - left
    if match_left.len < left || match_right.len < right { ret (0usize, TooSmall) }
    let (dist, dist_error) = mem.alloc[u32](a, left)
    if dist_error != ok { ret (0usize, dist_error) }
    let (queue, queue_error) = mem.alloc[u32](a, left)
    if queue_error != ok { ret (0usize, queue_error) }
    // An explicit DFS stack of (left node, position in its adjacency).
    let (stack, stack_error) = mem.alloc[u32](a, left + 1usize)
    if stack_error != ok { ret (0usize, stack_error) }
    let (position, position_error) = mem.alloc[usize](a, left)
    if position_error != ok { ret (0usize, position_error) }
    var i = 0usize
    while i < left {
        match_left[i] = NONE
        i += 1usize
    }
    i = 0usize
    while i < right {
        match_right[i] = NONE
        i += 1usize
    }
    var size = 0usize
    while true {
        // BFS from free left nodes, layering by alternating paths.
        var head = 0usize
        var tail = 0usize
        i = 0usize
        while i < left {
            if match_left[i] == NONE {
                dist[i] = 0u32
                queue[tail] = u32(i)
                tail += 1usize
            } else {
                dist[i] = NONE
            }
            i += 1usize
        }
        var found = false
        while head < tail {
            let u = queue[head]
            head += 1usize
            var k = g.offsets[usize(u)]
            while k < g.offsets[usize(u) + 1usize] {
                let v = g.edges[k].to
                if usize(v) < left { ret (0usize, Invalid) }
                let mate = match_right[usize(v) - left]
                if mate == NONE {
                    found = true
                } else if dist[usize(mate)] == NONE {
                    dist[usize(mate)] = dist[usize(u)] + 1u32
                    queue[tail] = mate
                    tail += 1usize
                }
                k += 1usize
            }
        }
        if !found { break }
        // DFS from every free left node along the layering.
        i = 0usize
        while i < left {
            position[i] = g.offsets[i]
            i += 1usize
        }
        i = 0usize
        while i < left {
            if match_left[i] != NONE {
                i += 1usize
                continue
            }
            var depth = 0usize
            stack[0usize] = u32(i)
            var augmented = false
            while true {
                let u = stack[depth]
                var advanced = false
                while position[usize(u)] < g.offsets[usize(u) + 1usize] {
                    let v = g.edges[position[usize(u)]].to
                    let mate = match_right[usize(v) - left]
                    if mate == NONE {
                        // Augment along the stack.
                        var d = depth
                        var last = v
                        while true {
                            let at = stack[d]
                            let next_right = g.edges[position[usize(at)]].to
                            let previous_right = match_left[usize(at)]
                            match_left[usize(at)] = next_right
                            match_right[usize(next_right) - left] = at
                            last = previous_right
                            if d == 0usize { break }
                            d -= 1usize
                        }
                        augmented = true
                        break
                    }
                    if dist[usize(mate)] == dist[usize(u)] + 1u32 {
                        depth += 1usize
                        stack[depth] = mate
                        advanced = true
                        break
                    }
                    position[usize(u)] += 1usize
                }
                if augmented { break }
                if !advanced {
                    dist[usize(u)] = NONE
                    if depth == 0usize { break }
                    depth -= 1usize
                    position[usize(stack[depth])] += 1usize
                }
            }
            if augmented { size += 1usize }
            i += 1usize
        }
    }
    ret (size, ok)
}

// The Hungarian algorithm over a row-major `n x n` cost matrix: `assignment[i]`
// is the column given to row `i`, and the answer is the minimum total cost.
// `scratch.len >= 4 * (n + 1)` floats and `used.len >= 2 * (n + 1)` indices.
fn hungarian(costs: []const f64, n: usize, assignment: []usize, scratch: []f64, used: []usize) -> (f64, err) {
    if n == 0usize { ret (0.0f64, Invalid) }
    if costs.len < n * n || assignment.len < n || scratch.len < 4usize * (n + 1usize) || used.len < 2usize * (n + 1usize) { ret (0.0f64, TooSmall) }
    let m = n + 1usize
    var u = scratch[..m]
    var v = scratch[m..2usize * m]
    var minv = scratch[2usize * m..3usize * m]
    var p = used[..m]
    var way = used[m..2usize * m]
    var i = 0usize
    while i < m {
        u[i] = 0.0f64
        v[i] = 0.0f64
        p[i] = 0usize
        way[i] = 0usize
        i += 1usize
    }
    // `visited` rides in the fourth scratch row as 0/1 floats.
    var visited = scratch[3usize * m..4usize * m]
    i = 1usize
    while i <= n {
        p[0usize] = i
        var j0 = 0usize
        var j = 0usize
        while j < m {
            minv[j] = 1.0e300f64
            visited[j] = 0.0f64
            j += 1usize
        }
        while true {
            visited[j0] = 1.0f64
            let i0 = p[j0]
            var delta = 1.0e300f64
            var j1 = 0usize
            j = 1usize
            while j <= n {
                if visited[j] == 0.0f64 {
                    let current = costs[(i0 - 1usize) * n + (j - 1usize)] - u[i0] - v[j]
                    if current < minv[j] {
                        minv[j] = current
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                j += 1usize
            }
            j = 0usize
            while j < m {
                if visited[j] == 1.0f64 {
                    u[p[j]] += delta
                    v[j] -= delta
                } else {
                    minv[j] -= delta
                }
                j += 1usize
            }
            j0 = j1
            if p[j0] == 0usize { break }
        }
        while j0 != 0usize {
            let j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        }
        i += 1usize
    }
    var total = 0.0f64
    var j = 1usize
    while j <= n {
        assignment[p[j] - 1usize] = j - 1usize
        total += costs[(p[j] - 1usize) * n + (j - 1usize)]
        j += 1usize
    }
    ret (total, ok)
}

// Gale-Shapley: `proposer_prefs` and `receiver_prefs` are `n x n` row-major
// preference lists (each row the partners in descending preference);
// `match_proposer[p]` receives the receiver engaged to `p`. `scratch.len >= 3 * n`
// indices. Proposer-optimal.
fn stable_marriage(proposer_prefs: []const usize, receiver_prefs: []const usize, n: usize, match_proposer: []usize, scratch: []usize) -> err {
    if n == 0usize { ret Invalid }
    if proposer_prefs.len < n * n || receiver_prefs.len < n * n || match_proposer.len < n || scratch.len < 3usize * n { ret TooSmall }
    var next_choice = scratch[..n]
    var engaged_to = scratch[n..2usize * n]
    var free_stack = scratch[2usize * n..3usize * n]
    var i = 0usize
    while i < n {
        next_choice[i] = 0usize
        engaged_to[i] = NONE_USIZE
        match_proposer[i] = NONE_USIZE
        free_stack[i] = i
        i += 1usize
    }
    var free_count = n
    while free_count > 0usize {
        let p = free_stack[free_count - 1usize]
        if next_choice[p] >= n { ret Invalid }
        let r = proposer_prefs[p * n + next_choice[p]]
        next_choice[p] += 1usize
        if r >= n { ret Invalid }
        let current = engaged_to[r]
        if current == NONE_USIZE {
            engaged_to[r] = p
            match_proposer[p] = r
            free_count -= 1usize
        } else {
            // Does r prefer p to current?
            var rank_p = n
            var rank_current = n
            var k = 0usize
            while k < n {
                let candidate = receiver_prefs[r * n + k]
                if candidate == p && rank_p == n { rank_p = k }
                if candidate == current && rank_current == n { rank_current = k }
                k += 1usize
            }
            if rank_p < rank_current {
                engaged_to[r] = p
                match_proposer[p] = r
                match_proposer[current] = NONE_USIZE
                free_stack[free_count - 1usize] = current
            }
        }
    }
    ret ok
}

const NONE_USIZE: usize = 18446744073709551615usize

// Edmonds' blossom algorithm: a maximum matching in a general graph,
// `mate[v]` the partner of `v` or `NONE`; answers the matching size.
fn blossom[E: type](a: *mem.Arena, g: *const graph.Graph[E], mate: []u32) -> (usize, err) {
    let n = graph.node_count[E](g)
    if mate.len < n { ret (0usize, TooSmall) }
    let (parent, parent_error) = mem.alloc[u32](a, n)
    if parent_error != ok { ret (0usize, parent_error) }
    let (base, base_error) = mem.alloc[u32](a, n)
    if base_error != ok { ret (0usize, base_error) }
    let (queue, queue_error) = mem.alloc[u32](a, n)
    if queue_error != ok { ret (0usize, queue_error) }
    let (used, used_error) = mem.alloc[u8](a, n)
    if used_error != ok { ret (0usize, used_error) }
    let (in_blossom, in_blossom_error) = mem.alloc[u8](a, n)
    if in_blossom_error != ok { ret (0usize, in_blossom_error) }
    let (path_mark, path_mark_error) = mem.alloc[u8](a, n)
    if path_mark_error != ok { ret (0usize, path_mark_error) }
    var i = 0usize
    while i < n {
        mate[i] = NONE
        i += 1usize
    }
    var size = 0usize
    var root = 0usize
    while root < n {
        if mate[root] != NONE {
            root += 1usize
            continue
        }
        // Find an augmenting path from `root`.
        i = 0usize
        while i < n {
            used[i] = 0u8
            parent[i] = NONE
            base[i] = u32(i)
            i += 1usize
        }
        used[root] = 1u8
        var head = 0usize
        var tail = 1usize
        queue[0usize] = u32(root)
        var found = NONE
        while head < tail && found == NONE {
            let v = queue[head]
            head += 1usize
            var k = g.offsets[usize(v)]
            while k < g.offsets[usize(v) + 1usize] && found == NONE {
                let to = g.edges[k].to
                k += 1usize
                if base[usize(v)] == base[usize(to)] || mate[usize(v)] == to { continue }
                if to == u32(root) || (mate[usize(to)] != NONE && parent[usize(mate[usize(to)])] != NONE) {
                    // An odd cycle: contract the blossom.
                    let common = lowest_common_base(base, parent, mate, v, to, u32(root), path_mark, n)
                    i = 0usize
                    while i < n {
                        in_blossom[i] = 0u8
                        i += 1usize
                    }
                    mark_path(base, parent, mate, in_blossom, v, common, to)
                    mark_path(base, parent, mate, in_blossom, to, common, v)
                    i = 0usize
                    while i < n {
                        if in_blossom[usize(base[i])] == 1u8 {
                            base[i] = common
                            if used[i] == 0u8 {
                                used[i] = 1u8
                                queue[tail] = u32(i)
                                tail += 1usize
                            }
                        }
                        i += 1usize
                    }
                } else if parent[usize(to)] == NONE {
                    parent[usize(to)] = v
                    if mate[usize(to)] == NONE {
                        found = to
                    } else {
                        let m = mate[usize(to)]
                        if used[usize(m)] == 0u8 {
                            used[usize(m)] = 1u8
                            queue[tail] = m
                            tail += 1usize
                        }
                    }
                }
            }
        }
        if found != NONE {
            // Augment: flip along parent pointers.
            var v = found
            while v != NONE {
                let pv = parent[usize(v)]
                let ppv = mate[usize(pv)]
                mate[usize(v)] = pv
                mate[usize(pv)] = v
                v = ppv
            }
            size += 1usize
        }
        root += 1usize
    }
    ret (size, ok)
}

// The base common to the alternating paths of `a` and `b` back to the root.
fn lowest_common_base(base: []u32, parent: []u32, mate: []u32, a: u32, b: u32, root: u32, mark: []u8, n: usize) -> u32 {
    var i = 0usize
    while i < n {
        mark[i] = 0u8
        i += 1usize
    }
    var x = a
    while true {
        x = base[usize(x)]
        mark[usize(x)] = 1u8
        if x == root || mate[usize(x)] == NONE { break }
        x = parent[usize(mate[usize(x)])]
    }
    var y = b
    while true {
        y = base[usize(y)]
        if mark[usize(y)] == 1u8 { ret y }
        y = parent[usize(mate[usize(y)])]
    }
    ret root
}

// Marks the blossom's nodes from `v` up to `common`, rewiring parents so the
// contracted blossom can still be walked for augmentation.
fn mark_path(base: []u32, parent: []u32, mate: []u32, in_blossom: []u8, from: u32, common: u32, child: u32) {
    var v = from
    var c = child
    while base[usize(v)] != common {
        in_blossom[usize(base[usize(v)])] = 1u8
        in_blossom[usize(base[usize(mate[usize(v)])])] = 1u8
        parent[usize(v)] = c
        c = mate[usize(v)]
        v = parent[usize(mate[usize(v)])]
    }
}
