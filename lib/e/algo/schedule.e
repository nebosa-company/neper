// Greedy scheduling over intervals and jobs in caller storage. Intervals
// are `(start, end)` pairs of `i64` with `end` exclusive; `order` arrays
// are caller scratch that the sorts permute.
//
// `activity_selection` picks the most non-overlapping intervals (earliest
// end first), `interval_cover` the fewest points touching every interval,
// `jobs_with_deadlines` the most profitable unit jobs meeting their
// deadlines (a disjoint-set over slots), and `cooldown` the length of the
// shortest schedule of tasks with a cooling gap between repeats.

use e.mem

error TooSmall
error Invalid

// Sort `order[..n]` (indices) by the key `key(i)` given as a parallel array.
fn sort_by(order: []usize, keys: []const i64) {
    var i = 1usize
    while i < order.len {
        let v = order[i]
        var k = i
        while k > 0usize && keys[order[k - 1usize]] > keys[v] {
            order[k] = order[k - 1usize]
            k -= 1usize
        }
        order[k] = v
        i += 1usize
    }
}

// The chosen interval indices, earliest end first; `chosen.len` and
// `order.len` at least the interval count. Answers the count.
fn activity_selection(starts: []const i64, ends: []const i64, chosen: []usize, order: []usize) -> (usize, err) {
    let n = starts.len
    if ends.len < n || chosen.len < n || order.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        if ends[i] < starts[i] { ret (0usize, Invalid) }
        order[i] = i
        i += 1usize
    }
    sort_by(order[..n], ends)
    var count = 0usize
    var free_from = 0i64
    i = 0usize
    while i < n {
        let k = order[i]
        if count == 0usize || starts[k] >= free_from {
            chosen[count] = k
            count += 1usize
            free_from = ends[k]
        }
        i += 1usize
    }
    ret (count, ok)
}

// The fewest points such that every interval `[start, end)` contains one:
// the last point of each interval in end order, skipping intervals already
// touched. Answers the count into `points`.
fn interval_cover(starts: []const i64, ends: []const i64, points: []i64, order: []usize) -> (usize, err) {
    let n = starts.len
    if ends.len < n || points.len < n || order.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        if ends[i] <= starts[i] { ret (0usize, Invalid) }
        order[i] = i
        i += 1usize
    }
    sort_by(order[..n], ends)
    var count = 0usize
    i = 0usize
    while i < n {
        let k = order[i]
        if count == 0usize || points[count - 1usize] < starts[k] {
            points[count] = ends[k] - 1i64
            count += 1usize
        }
        i += 1usize
    }
    ret (count, ok)
}

fn find_slot(parent: []usize, slot: usize) -> usize {
    var s = slot
    while parent[s] != s { s = parent[s] }
    // Path compression.
    var t = slot
    while parent[t] != s {
        let next_t = parent[t]
        parent[t] = s
        t = next_t
    }
    ret s
}

// Unit jobs with `deadlines` (slots `1..=deadline`) and `profits`: most
// profitable first, each into the latest free slot at or before its
// deadline (disjoint sets over slots). `slots` receives the job per slot
// (`NONE` for an idle one); `parent.len` and `order.len` at least
// `max deadline + 1` and the job count. Answers the total profit and the jobs placed.
fn jobs_with_deadlines(deadlines: []const usize, profits: []const i64, slots: []usize, parent: []usize, order: []usize) -> (i64, usize, err) {
    let n = deadlines.len
    if profits.len < n || order.len < n { ret (0i64, 0usize, TooSmall) }
    var latest = 0usize
    var i = 0usize
    while i < n {
        if deadlines[i] > latest { latest = deadlines[i] }
        order[i] = i
        i += 1usize
    }
    if slots.len < latest || parent.len < latest + 1usize { ret (0i64, 0usize, TooSmall) }
    i = 0usize
    while i <= latest {
        parent[i] = i
        i += 1usize
    }
    i = 0usize
    while i < latest {
        slots[i] = NONE
        i += 1usize
    }
    // Sort by falling profit: negate through a scratch of keys? Use the order
    // sort on profits and read it backwards.
    sort_by(order[..n], profits)
    var total = 0i64
    var placed = 0usize
    i = n
    while i > 0usize {
        i -= 1usize
        let job = order[i]
        let slot = find_slot(parent, deadlines[job])
        if slot > 0usize {
            slots[slot - 1usize] = job
            parent[slot] = slot - 1usize
            total += profits[job]
            placed += 1usize
        }
    }
    ret (total, placed, ok)
}

const NONE: usize = 18446744073709551615usize

// The shortest schedule of `tasks` (kinds in `0..kinds`) with at least `gap`
// slots between two of a kind: the classic bound from the most frequent
// kind, `max(n, (f_max - 1) (gap + 1) + count of kinds at f_max)`;
// `counts.len >= kinds`.
fn cooldown(tasks: []const usize, kinds: usize, gap: usize, counts: []usize) -> (usize, err) {
    if counts.len < kinds { ret (0usize, TooSmall) }
    var k = 0usize
    while k < kinds {
        counts[k] = 0usize
        k += 1usize
    }
    var i = 0usize
    while i < tasks.len {
        if tasks[i] >= kinds { ret (0usize, Invalid) }
        counts[tasks[i]] += 1usize
        i += 1usize
    }
    var most = 0usize
    var at_most = 0usize
    k = 0usize
    while k < kinds {
        if counts[k] > most {
            most = counts[k]
            at_most = 1usize
        } else if counts[k] == most && most > 0usize {
            at_most += 1usize
        }
        k += 1usize
    }
    if most == 0usize { ret (0usize, ok) }
    let bound = (most - 1usize) * (gap + 1usize) + at_most
    if bound > tasks.len { ret (bound, ok) }
    ret (tasks.len, ok)
}

// ---------------------------------------------------------------------------
// Dependency order (Kahn), after petcow's `topo_order`: dependencies first, the same input always giving the
// same order, and a graph that cannot be ordered refused, never guessed.
//
// A node has an `id` and the targets it `depends_on`. A target names a node whose id is exactly the target OR
// the target followed by `[`, so depending on `subnet` means all of `subnet[0]`, `subnet[1]` ... (the expanded
// members of a `for_each` set). Ties are broken by id (bytewise, stable): the initial ready set is sorted by id
// and so is each batch of nodes a processed node frees. Three refusals: `UnknownDependency` (a target no node
// matches; `node` and `dep` say which), `SelfDependency` (a target that matches the node itself; `node`) and
// `Cycle` (`stuck` lists the nodes left over, ascending, which are on or behind a cycle).


error UnknownDependency
error SelfDependency
error Cycle

type DependencyNode = struct { id: str, depends_on: []const str }

type DependencyOrder = struct { order: []const usize, stuck: []const usize, node: usize, dep: usize }

// Whether node id `id` is the dependency target `wanted` or one of its `wanted[...]` members.
fn target_matches(id: str, wanted: str) -> bool {
    if id.len == wanted.len {
        var i = 0usize
        while i < id.len {
            if id[i] != wanted[i] { ret false }
            i += 1usize
        }
        ret true
    }
    if id.len <= wanted.len { ret false }
    var i = 0usize
    while i < wanted.len {
        if id[i] != wanted[i] { ret false }
        i += 1usize
    }
    ret id[wanted.len] == 91u8
}

// Bytewise `left < right`.
fn id_less(left: str, right: str) -> bool {
    var i = 0usize
    while i < left.len && i < right.len {
        if left[i] != right[i] { ret left[i] < right[i] }
        i += 1usize
    }
    ret left.len < right.len
}

// Stable insertion sort of `items` (node indices) by node id.
fn sort_ids(nodes: []const DependencyNode, items: []usize) {
    var i = 1usize
    while i < items.len {
        let v = items[i]
        var k = i
        while k > 0usize && id_less(nodes[v].id, nodes[items[k - 1usize]].id) {
            items[k] = items[k - 1usize]
            k -= 1usize
        }
        items[k] = v
        i += 1usize
    }
}

// The node indices in dependency order. On an error `order` is empty and the fields named above say why.
fn dependency_order(a: *mem.Arena, nodes: []const DependencyNode) -> (DependencyOrder, err) {
    var result: DependencyOrder = zero
    let n = nodes.len
    if n == 0usize { ret (result, ok) }
    let (indegree, indegree_error) = mem.alloc[usize](a, n)
    if indegree_error != ok { ret (result, indegree_error) }
    let (outdegree, outdegree_error) = mem.alloc[usize](a, n + 1usize)
    if outdegree_error != ok { ret (result, outdegree_error) }
    var i = 0usize
    while i < n {
        indegree[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i <= n {
        outdegree[i] = 0usize
        i += 1usize
    }
    // Pass 1: resolve every target, refuse the unknown and the self-referential, count the edges.
    var edges = 0usize
    i = 0usize
    while i < n {
        var d = 0usize
        while d < nodes[i].depends_on.len {
            var matched = false
            var t = 0usize
            while t < n {
                if target_matches(nodes[t].id, nodes[i].depends_on[d]) {
                    matched = true
                    if t == i {
                        result.node = i
                        result.dep = d
                        ret (result, SelfDependency)
                    }
                    indegree[i] += 1usize
                    outdegree[t + 1usize] += 1usize
                    edges += 1usize
                }
                t += 1usize
            }
            if !matched {
                result.node = i
                result.dep = d
                ret (result, UnknownDependency)
            }
            d += 1usize
        }
        i += 1usize
    }
    // Adjacency (dependency -> dependents) in compressed form: outdegree becomes the start offsets.
    i = 0usize
    while i < n {
        outdegree[i + 1usize] += outdegree[i]
        i += 1usize
    }
    var adjacent: []usize = zero
    if edges > 0usize {
        let (storage, adjacent_error) = mem.alloc[usize](a, edges)
        if adjacent_error != ok { ret (result, adjacent_error) }
        adjacent = storage
    }
    let (cursor, cursor_error) = mem.alloc[usize](a, n)
    if cursor_error != ok { ret (result, cursor_error) }
    i = 0usize
    while i < n {
        cursor[i] = outdegree[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var d = 0usize
        while d < nodes[i].depends_on.len {
            var t = 0usize
            while t < n {
                if target_matches(nodes[t].id, nodes[i].depends_on[d]) {
                    adjacent[cursor[t]] = i
                    cursor[t] += 1usize
                }
                t += 1usize
            }
            d += 1usize
        }
        i += 1usize
    }
    // Kahn: the queue is the order itself. The first ready set and every freed batch are sorted by id.
    let (queue, queue_error) = mem.alloc[usize](a, n)
    if queue_error != ok { ret (result, queue_error) }
    var tail = 0usize
    i = 0usize
    while i < n {
        if indegree[i] == 0usize {
            queue[tail] = i
            tail += 1usize
        }
        i += 1usize
    }
    sort_ids(nodes, queue[0usize..tail])
    var head = 0usize
    while head < tail {
        let node = queue[head]
        head += 1usize
        let batch = tail
        var e = outdegree[node]
        while e < outdegree[node + 1usize] {
            let next = adjacent[e]
            indegree[next] -= 1usize
            if indegree[next] == 0usize {
                queue[tail] = next
                tail += 1usize
            }
            e += 1usize
        }
        sort_ids(nodes, queue[batch..tail])
    }
    if tail == n {
        result.order = queue[0usize..n]
        ret (result, ok)
    }
    // The rest are on a cycle or behind one.
    let (seen, seen_error) = mem.alloc[bool](a, n)
    if seen_error != ok { ret (result, seen_error) }
    i = 0usize
    while i < n {
        seen[i] = false
        i += 1usize
    }
    i = 0usize
    while i < tail {
        seen[queue[i]] = true
        i += 1usize
    }
    let (stuck, stuck_error) = mem.alloc[usize](a, n - tail)
    if stuck_error != ok { ret (result, stuck_error) }
    var count = 0usize
    i = 0usize
    while i < n {
        if !seen[i] {
            stuck[count] = i
            count += 1usize
        }
        i += 1usize
    }
    result.stuck = stuck[0usize..count]
    ret (result, Cycle)
}
