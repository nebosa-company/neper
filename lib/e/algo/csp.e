// Finite-domain constraint satisfaction in caller storage: `n` variables
// over the values `0..k`, domains as `n × k` bytes (1 = allowed), binary
// constraints given by the caller as `allowed(ctx, x, y, a, b)` over
// constrained pairs listed in `pairs`. `ac3` prunes to arc consistency,
// `solve` searches with maintained arc consistency (smallest domain
// first) and `limited_discrepancy` searches by rising discrepancy count
// against value order. The global filters `all_different` (Hall-style
// pruning through a maximum matching), `element` (index-value linking),
// `table` (support in an explicit tuple list) and `cumulative` (a
// time-table capacity check) work on domains directly.

error TooSmall
error Invalid
error Unsatisfiable

fn count(domains: []const u8, k: usize, x: usize) -> usize {
    var c = 0usize
    var v = 0usize
    while v < k {
        if domains[x * k + v] != 0u8 { c += 1usize }
        v += 1usize
    }
    ret c
}

// Revise x against y: drop values of x with no support in y. Answers
// whether anything was dropped.
fn revise[Ctx: type](domains: []u8, k: usize, x: usize, y: usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool) -> bool {
    var changed = false
    var a = 0usize
    while a < k {
        if domains[x * k + a] != 0u8 {
            var supported = false
            var b = 0usize
            while b < k && !supported {
                if domains[y * k + b] != 0u8 && allowed(ctx, x, y, a, b) { supported = true }
                b += 1usize
            }
            if !supported {
                domains[x * k + a] = 0u8
                changed = true
            }
        }
        a += 1usize
    }
    ret changed
}

// AC-3 over the arcs of `pairs` (each `(x, y)` in both directions);
// `queue.len >= 2 * pairs.len / 2 * ...`: at least `2 * pair count`
// entries of arc indices. Answers `Unsatisfiable` when a domain empties.
fn ac3[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, queue: []usize, queued: []u8) -> err {
    let arcs = pairs.len
    if domains.len < n * k || pairs.len % 2usize != 0usize || queue.len < arcs || queued.len < arcs { ret TooSmall }
    // Arc index i covers pair i / 2 in direction i % 2.
    var i = 0usize
    while i < arcs {
        queue[i] = i
        queued[i] = 1u8
        i += 1usize
    }
    var head = 0usize
    var tail = arcs
    var live = arcs
    while live > 0usize {
        let arc = queue[head]
        head = (head + 1usize) % queue.len
        live -= 1usize
        queued[arc] = 0u8
        var x = pairs[(arc / 2usize) * 2usize]
        var y = pairs[(arc / 2usize) * 2usize + 1usize]
        if arc % 2usize == 1usize {
            let t = x
            x = y
            y = t
        }
        if revise[Ctx](domains, k, x, y, ctx, allowed) {
            if count(domains, k, x) == 0usize { ret Unsatisfiable }
            // Every arc (z, x) with z != y goes back on the queue.
            var j = 0usize
            while j < arcs {
                let zx = pairs[(j / 2usize) * 2usize]
                let zy = pairs[(j / 2usize) * 2usize + 1usize]
                var from = zx
                var to = zy
                if j % 2usize == 1usize {
                    from = zy
                    to = zx
                }
                if to == x && from != y && queued[j] == 0u8 {
                    if live >= queue.len { ret TooSmall }
                    queue[tail] = j
                    tail = (tail + 1usize) % queue.len
                    queued[j] = 1u8
                    live += 1usize
                }
                j += 1usize
            }
        }
    }
    ret ok
}

// Backtracking search with maintained arc consistency: `assignment`
// receives a value per variable; `saved` (`depth × n × k`, `n * n * k` bytes)
// keeps domain copies per level. Answers whether a solution exists.
fn solve[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, saved: []u8, queue: []usize, queued: []u8) -> (bool, err) {
    if domains.len < n * k || assignment.len < n || saved.len < n * n * k { ret (false, TooSmall) }
    let first = ac3[Ctx](domains, n, k, pairs, ctx, allowed, queue, queued)
    if first == Unsatisfiable { ret (false, ok) }
    if first != ok { ret (false, first) }
    ret (mac[Ctx](domains, n, k, pairs, ctx, allowed, assignment, saved, queue, queued, 0usize), ok)
}

fn mac[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, saved: []u8, queue: []usize, queued: []u8, depth: usize) -> bool {
    // The unassigned variable with the smallest domain (size > 1); all singletons means solved.
    var pick = n
    var x = 0usize
    while x < n {
        let c = count(domains, k, x)
        if c > 1usize && (pick == n || c < count(domains, k, pick)) { pick = x }
        x += 1usize
    }
    if pick == n {
        x = 0usize
        while x < n {
            var v = 0usize
            while v < k && domains[x * k + v] == 0u8 { v += 1usize }
            assignment[x] = v
            x += 1usize
        }
        ret true
    }
    var copy = saved[depth * n * k..(depth + 1usize) * n * k]
    var i = 0usize
    while i < n * k {
        copy[i] = domains[i]
        i += 1usize
    }
    var v = 0usize
    while v < k {
        if copy[pick * k + v] != 0u8 {
            i = 0usize
            while i < n * k {
                domains[i] = copy[i]
                i += 1usize
            }
            var w = 0usize
            while w < k {
                if w != v { domains[pick * k + w] = 0u8 }
                w += 1usize
            }
            let e = ac3[Ctx](domains, n, k, pairs, ctx, allowed, queue, queued)
            if e == ok && mac[Ctx](domains, n, k, pairs, ctx, allowed, assignment, saved, queue, queued, depth + 1usize) { ret true }
        }
        v += 1usize
    }
    i = 0usize
    while i < n * k {
        domains[i] = copy[i]
        i += 1usize
    }
    ret false
}

// Limited discrepancy search over the same model without propagation
// between choices beyond a consistency check of assigned pairs: paths
// with at most `d` departures from the first allowed value, for `d` from 0
// to `max_discrepancies`. Answers whether a solution was found and the
// discrepancies it needed.
fn limited_discrepancy[Ctx: type](domains: []const u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, max_discrepancies: usize, assignment: []usize) -> (bool, usize, err) {
    if domains.len < n * k || assignment.len < n { ret (false, 0usize, TooSmall) }
    var d = 0usize
    while d <= max_discrepancies {
        if lds[Ctx](domains, n, k, pairs, ctx, allowed, assignment, 0usize, d) { ret (true, d, ok) }
        d += 1usize
    }
    ret (false, 0usize, ok)
}

fn consistent[Ctx: type](pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []const usize, x: usize) -> bool {
    var p = 0usize
    while p + 1usize < pairs.len {
        let a = pairs[p]
        let b = pairs[p + 1usize]
        if a == x && b < x && !allowed(ctx, a, b, assignment[a], assignment[b]) { ret false }
        if b == x && a < x && !allowed(ctx, a, b, assignment[a], assignment[b]) { ret false }
        p += 2usize
    }
    ret true
}

fn lds[Ctx: type](domains: []const u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, x: usize, budget: usize) -> bool {
    if x == n { ret true }
    var rank = 0usize
    var v = 0usize
    while v < k {
        if domains[x * k + v] != 0u8 {
            if rank <= budget {
                assignment[x] = v
                if consistent[Ctx](pairs, ctx, allowed, assignment, x) && lds[Ctx](domains, n, k, pairs, ctx, allowed, assignment, x + 1usize, budget - rank) { ret true }
            }
            rank += 1usize
        }
        v += 1usize
    }
    ret false
}

// Augmenting path for the variable-value matching of `all_different`.
fn augment(domains: []const u8, k: usize, vars: []const usize, x: usize, match_value: []usize, seen: []u8) -> bool {
    var v = 0usize
    while v < k {
        if domains[vars[x] * k + v] != 0u8 && seen[v] == 0u8 {
            seen[v] = 1u8
            if match_value[v] == vars.len || augment(domains, k, vars, match_value[v], match_value, seen) {
                match_value[v] = x
                ret true
            }
        }
        v += 1usize
    }
    ret false
}

// All-different over `vars`: `Unsatisfiable` when no matching covers them;
// otherwise every value that belongs to no maximum matching is pruned
// (tested by rematching with that value forced). `match_value.len >= k`,
// `seen.len >= k`.
fn all_different(domains: []u8, k: usize, vars: []const usize, match_value: []usize, seen: []u8) -> err {
    if match_value.len < k || seen.len < k { ret TooSmall }
    let m = vars.len
    var v = 0usize
    while v < k {
        match_value[v] = m
        v += 1usize
    }
    var x = 0usize
    while x < m {
        v = 0usize
        while v < k {
            seen[v] = 0u8
            v += 1usize
        }
        if !augment(domains, k, vars, x, match_value, seen) { ret Unsatisfiable }
        x += 1usize
    }
    // Prune: a value stays only if some maximum matching uses it for that variable.
    x = 0usize
    while x < m {
        v = 0usize
        while v < k {
            if domains[vars[x] * k + v] != 0u8 && match_value[v] != x {
                // Force x = v and try to complete a matching of the others.
                let keep = domains[vars[x] * k + v]
                var w = 0usize
                while w < k {
                    seen[w] = 0u8
                    w += 1usize
                }
                // Temporarily restrict x's domain to v.
                var restore: [64]u8 = zero
                var ok_restore = k <= 64usize
                if ok_restore {
                    w = 0usize
                    while w < k {
                        restore[w] = domains[vars[x] * k + w]
                        if w != v { domains[vars[x] * k + w] = 0u8 }
                        w += 1usize
                    }
                    var complete = true
                    var y = 0usize
                    // Rematch everything from scratch under the restriction.
                    w = 0usize
                    while w < k {
                        match_value[w] = m
                        w += 1usize
                    }
                    while y < m && complete {
                        w = 0usize
                        while w < k {
                            seen[w] = 0u8
                            w += 1usize
                        }
                        if !augment(domains, k, vars, y, match_value, seen) { complete = false }
                        y += 1usize
                    }
                    w = 0usize
                    while w < k {
                        domains[vars[x] * k + w] = restore[w]
                        w += 1usize
                    }
                    if !complete { domains[vars[x] * k + v] = 0u8 } else { domains[vars[x] * k + v] = keep }
                }
            }
            v += 1usize
        }
        x += 1usize
    }
    // Leave a valid matching behind.
    v = 0usize
    while v < k {
        match_value[v] = m
        v += 1usize
    }
    x = 0usize
    while x < m {
        v = 0usize
        while v < k {
            seen[v] = 0u8
            v += 1usize
        }
        if !augment(domains, k, vars, x, match_value, seen) { ret Unsatisfiable }
        x += 1usize
    }
    ret ok
}

// Element: `result = array[index]` over constant `array`; prunes `index` to
// positions whose value is in `result`'s domain and `result` to values at
// some allowed position.
fn element(domains: []u8, k: usize, index: usize, result: usize, array: []const usize) -> err {
    var i = 0usize
    while i < k {
        if domains[index * k + i] != 0u8 && (i >= array.len || array[i] >= k || domains[result * k + array[i]] == 0u8) { domains[index * k + i] = 0u8 }
        i += 1usize
    }
    var v = 0usize
    while v < k {
        if domains[result * k + v] != 0u8 {
            var supported = false
            i = 0usize
            while i < array.len && i < k && !supported {
                if domains[index * k + i] != 0u8 && array[i] == v { supported = true }
                i += 1usize
            }
            if !supported { domains[result * k + v] = 0u8 }
        }
        v += 1usize
    }
    if count(domains, k, index) == 0usize || count(domains, k, result) == 0usize { ret Unsatisfiable }
    ret ok
}

// Table: `vars` must take one of the `tuples` (`rows × vars.len`); every
// value with no supporting tuple is pruned.
fn table(domains: []u8, k: usize, vars: []const usize, tuples: []const usize, rows: usize) -> err {
    let width = vars.len
    if tuples.len < rows * width { ret TooSmall }
    var x = 0usize
    while x < width {
        var v = 0usize
        while v < k {
            if domains[vars[x] * k + v] != 0u8 {
                var supported = false
                var t = 0usize
                while t < rows && !supported {
                    if tuples[t * width + x] == v {
                        var fits = true
                        var y = 0usize
                        while y < width && fits {
                            if tuples[t * width + y] >= k || domains[vars[y] * k + tuples[t * width + y]] == 0u8 { fits = false }
                            y += 1usize
                        }
                        if fits { supported = true }
                    }
                    t += 1usize
                }
                if !supported { domains[vars[x] * k + v] = 0u8 }
            }
            v += 1usize
        }
        if count(domains, k, vars[x]) == 0usize { ret Unsatisfiable }
        x += 1usize
    }
    ret ok
}

// Cumulative: tasks with a start variable each, `duration` and `demand`,
// over `capacity`. The compulsory parts (times every start in the domain
// covers) are summed per time; a start whose placement overloads some
// time is pruned. `profile.len >= horizon`.
fn cumulative(domains: []u8, k: usize, starts: []const usize, duration: []const usize, demand: []const usize, capacity: usize, horizon: usize, profile: []usize) -> err {
    let tasks = starts.len
    if duration.len < tasks || demand.len < tasks || profile.len < horizon { ret TooSmall }
    var t = 0usize
    while t < horizon {
        profile[t] = 0usize
        t += 1usize
    }
    var i = 0usize
    while i < tasks {
        // Earliest and latest start.
        var earliest = k
        var latest = 0usize
        var v = 0usize
        while v < k {
            if domains[starts[i] * k + v] != 0u8 {
                if earliest == k { earliest = v }
                latest = v
            }
            v += 1usize
        }
        if earliest == k { ret Unsatisfiable }
        // Compulsory part: [latest, earliest + duration).
        t = latest
        while t < earliest + duration[i] && t < horizon {
            profile[t] += demand[i]
            t += 1usize
        }
        i += 1usize
    }
    t = 0usize
    while t < horizon {
        if profile[t] > capacity { ret Unsatisfiable }
        t += 1usize
    }
    // Prune starts that would overload a time, discounting the task's own compulsory part.
    i = 0usize
    while i < tasks {
        var earliest = k
        var latest = 0usize
        var v = 0usize
        while v < k {
            if domains[starts[i] * k + v] != 0u8 {
                if earliest == k { earliest = v }
                latest = v
            }
            v += 1usize
        }
        v = 0usize
        while v < k {
            if domains[starts[i] * k + v] != 0u8 {
                var fits = true
                t = v
                while t < v + duration[i] && fits {
                    if t >= horizon {
                        fits = false
                    } else {
                        var own = 0usize
                        if t >= latest && t < earliest + duration[i] { own = demand[i] }
                        if profile[t] - own + demand[i] > capacity { fits = false }
                    }
                    t += 1usize
                }
                if !fits { domains[starts[i] * k + v] = 0u8 }
            }
            v += 1usize
        }
        if count(domains, k, starts[i]) == 0usize { ret Unsatisfiable }
        i += 1usize
    }
    ret ok
}
