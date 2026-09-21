// Greedy scheduling over intervals and jobs in caller storage. Intervals
// are `(start, end)` pairs of `i64` with `end` exclusive; `order` arrays
// are caller scratch that the sorts permute.
//
// `activity_selection` picks the most non-overlapping intervals (earliest
// end first), `interval_cover` the fewest points touching every interval,
// `jobs_with_deadlines` the most profitable unit jobs meeting their
// deadlines (a disjoint-set over slots), and `cooldown` the length of the
// shortest schedule of tasks with a cooling gap between repeats.

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
