// Online algorithms with their offline optima: ski rental (break-even and the prediction-augmented rule), paging (Belady's offline optimum, the marking algorithm, LRU), move-to-front list access and online facility location on a line. Each returns its cost so a caller can set it beside the offline cost and the competitive ratio.
//
// Not here: randomised ski rental and randomised marking (the deterministic versions are the ones whose ratios the fixtures assert), k-server, online matching and the other problems of the competitive-analysis literature.

use e.math
use e.mem

// ski rental over `days` days with purchase cost buy (renting costs 1 a day): rent until the buy-th day, then buy; the cost is at most twice the offline minimum(days, buy)
fn ski_break_even(days: f64, buy: f64) -> f64 {
    if days < buy { ret days }
    ret (buy - 1.0f64) + buy
}

fn ski_offline(days: f64, buy: f64) -> f64 {
    if days < buy { ret days }
    ret buy
}

// the learning-augmented rule: with a prediction of the number of days, trust parameter lambda in (0, 1]: if the prediction is at least buy, buy early on day ceil(lambda buy), else on day ceil(buy / lambda); the cost is at most (1 + lambda) OPT with a good prediction and (1 + 1/lambda) OPT whatever the error
fn ski_predicted(days: f64, buy: f64, predicted: f64, lambda: f64) -> f64 {
    var day = math.ceil[f64](buy / lambda)
    if predicted >= buy { day = math.ceil[f64](lambda * buy) }
    if days < day { ret days }
    ret (day - 1.0f64) + buy
}

// the number of faults of Belady's furthest-in-future rule for a cache of k pages: requests are page ids below `pages`; cache and next are scratch of k and pages values
fn belady(requests: []const usize, k: usize, cache: []usize) -> usize {
    var held = 0usize
    var faults = 0usize
    var t = 0usize
    while t < requests.len {
        let p = requests[t]
        var hit = false
        var i = 0usize
        while i < held {
            if cache[i] == p { hit = true }
            i += 1usize
        }
        if !hit {
            faults += 1usize
            if held < k {
                cache[held] = p
                held += 1usize
            } else {
                // evict the cached page whose next request is furthest away (or never)
                var worst = 0usize
                var worst_at = 0usize
                i = 0usize
                while i < held {
                    var nxt = requests.len + 1usize
                    var u = t + 1usize
                    while u < requests.len {
                        if requests[u] == cache[i] {
                            nxt = u
                            break
                        }
                        u += 1usize
                    }
                    if nxt > worst_at {
                        worst_at = nxt
                        worst = i
                    }
                    i += 1usize
                }
                cache[worst] = p
            }
        }
        t += 1usize
    }
    ret faults
}

// least-recently-used paging, a marking algorithm; stamp is scratch of k values
fn lru(requests: []const usize, k: usize, cache: []usize, stamp: []usize) -> usize {
    var held = 0usize
    var faults = 0usize
    var t = 0usize
    while t < requests.len {
        let p = requests[t]
        var at = k
        var i = 0usize
        while i < held {
            if cache[i] == p { at = i }
            i += 1usize
        }
        if at < k {
            stamp[at] = t
        } else {
            faults += 1usize
            if held < k {
                cache[held] = p
                stamp[held] = t
                held += 1usize
            } else {
                var oldest = 0usize
                i = 1usize
                while i < held {
                    if stamp[i] < stamp[oldest] { oldest = i }
                    i += 1usize
                }
                cache[oldest] = p
                stamp[oldest] = t
            }
        }
        t += 1usize
    }
    ret faults
}

// the marking algorithm: pages are marked when requested; a fault evicts the lowest-indexed unmarked cached page, and when every cached page is marked a new phase starts and all marks are cleared; at most k times the optimum; mark is scratch of k values
fn marking(requests: []const usize, k: usize, cache: []usize, mark: []bool) -> usize {
    var held = 0usize
    var faults = 0usize
    var t = 0usize
    while t < requests.len {
        let p = requests[t]
        var at = k
        var i = 0usize
        while i < held {
            if cache[i] == p { at = i }
            i += 1usize
        }
        if at < k {
            mark[at] = true
        } else {
            faults += 1usize
            if held < k {
                cache[held] = p
                mark[held] = true
                held += 1usize
            } else {
                var victim = k
                i = 0usize
                while i < held {
                    if !mark[i] {
                        victim = i
                        break
                    }
                    i += 1usize
                }
                if victim == k {
                    i = 0usize
                    while i < held {
                        mark[i] = false
                        i += 1usize
                    }
                    victim = 0usize
                }
                cache[victim] = p
                mark[victim] = true
            }
        }
        t += 1usize
    }
    ret faults
}

// move-to-front list access: the list starts as items 0 .. n - 1 in order (scratch list of n values); the cost of a request is the position of the item, counted from 1, and the item then moves to the front; at most twice the cost of the best static order
fn move_to_front(requests: []const usize, n: usize, list: []usize) -> usize {
    var i = 0usize
    while i < n {
        list[i] = i
        i += 1usize
    }
    var cost = 0usize
    var t = 0usize
    while t < requests.len {
        let p = requests[t]
        var at = 0usize
        while list[at] != p { at += 1usize }
        cost += at + 1usize
        while at > 0usize {
            list[at] = list[at - 1usize]
            at -= 1usize
        }
        list[0usize] = p
        t += 1usize
    }
    ret cost
}

// the cost of the best static order: items sorted by decreasing request count, each request paying its position; counts is scratch of n values
fn static_optimal(requests: []const usize, n: usize, counts: []usize) -> usize {
    var i = 0usize
    while i < n {
        counts[i] = 0usize
        i += 1usize
    }
    var t = 0usize
    while t < requests.len {
        counts[requests[t]] += 1usize
        t += 1usize
    }
    i = 1usize
    while i < n {
        let v = counts[i]
        var j = i
        while j > 0usize && counts[j - 1usize] < v {
            counts[j] = counts[j - 1usize]
            j -= 1usize
        }
        counts[j] = v
        i += 1usize
    }
    var cost = 0usize
    i = 0usize
    while i < n {
        cost += counts[i] * (i + 1usize)
        i += 1usize
    }
    ret cost
}

// deterministic online facility location on a line (a Fotakis-style rule): a client at x opens a facility there when the savings it would have given the earlier clients, the sum of max(0, their distance to the nearest facility so far - their distance to x), reach the opening cost f, plus its own distance; otherwise it connects to the nearest facility. open receives the facility positions; the total cost is returned. clients are processed in the given order
fn facility_location(clients: []const f64, f: f64, open: []f64, count: *usize) -> f64 {
    var m = 0usize
    var cost = 0.0f64
    var i = 0usize
    while i < clients.len {
        let x = clients[i]
        var nearest = 1.0e300f64
        var j = 0usize
        while j < m {
            let d = math.abs[f64](open[j] - x)
            if d < nearest { nearest = d }
            j += 1usize
        }
        var open_here = m == 0usize
        if !open_here {
            // the savings the earlier clients would have had at x (they are served by the facilities open now, approximated by the facilities at the time they arrived through their current nearest distance)
            var saving = nearest
            var c = 0usize
            while c < i {
                var dn = 1.0e300f64
                var q = 0usize
                while q < m {
                    let dq = math.abs[f64](open[q] - clients[c])
                    if dq < dn { dn = dq }
                    q += 1usize
                }
                let dx = math.abs[f64](clients[c] - x)
                if dn > dx { saving += dn - dx }
                c += 1usize
            }
            if saving >= f { open_here = true }
        }
        if open_here {
            open[m] = x
            m += 1usize
            cost += f
        } else {
            cost += nearest
        }
        i += 1usize
    }
    *count = m
    ret cost
}
