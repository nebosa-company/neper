// Clock agreement over caller storage: `marzullo` finds the interval covered
// by the most sources (a sweep over the sorted endpoints) and
// `marzullo_estimate` its midpoint; `berkeley` is the master's step, an
// average of the reported offsets with outliers beyond a tolerance from the
// median dropped, answering every node's adjustment; `cristian` is the
// client's step, the server time plus half the round trip with the bound the
// other half leaves after the minimum one-way delay.

error TooSmall
error Invalid

// The interval [lo, hi] intersected by the most of the `n` source intervals
// `[lows[i], highs[i]]`; `scratch` needs `4 * n` slots. Touching intervals
// count as overlapping. Answers the interval and how many sources cover it.
fn marzullo(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, i64, usize, err) {
    if n == 0usize || n > lows.len || n > highs.len { ret (0i64, 0i64, 0usize, Invalid) }
    if scratch.len < 4usize * n { ret (0i64, 0i64, 0usize, TooSmall) }
    let m = 2usize * n
    let offsets = scratch[..m]
    let kinds = scratch[m..2usize * m]
    var i = 0usize
    while i < n {
        if lows[i] > highs[i] { ret (0i64, 0i64, 0usize, Invalid) }
        offsets[2usize * i] = lows[i]
        kinds[2usize * i] = -1i64
        offsets[2usize * i + 1usize] = highs[i]
        kinds[2usize * i + 1usize] = 1i64
        i += 1usize
    }
    // ponytail: insertion sort, O(n^2) over 2n endpoints; sources are few.
    i = 1usize
    while i < m {
        let o = offsets[i]
        let k = kinds[i]
        var j = i
        while j > 0usize && (offsets[j - 1usize] > o || (offsets[j - 1usize] == o && kinds[j - 1usize] > k)) {
            offsets[j] = offsets[j - 1usize]
            kinds[j] = kinds[j - 1usize]
            j -= 1usize
        }
        offsets[j] = o
        kinds[j] = k
        i += 1usize
    }
    var count = 0i64
    var best = 0i64
    var lo = 0i64
    var hi = 0i64
    i = 0usize
    while i < m {
        count -= kinds[i]
        if count > best {
            best = count
            lo = offsets[i]
            hi = offsets[i + 1usize]
        }
        i += 1usize
    }
    ret (lo, hi, usize(best), ok)
}

// The midpoint of the `marzullo` interval.
fn marzullo_estimate(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, err) {
    let (lo, hi, _, e) = marzullo(lows, highs, n, scratch)
    if e != ok { ret (0i64, e) }
    ret (lo + (hi - lo) / 2i64, ok)
}

// The master's step: `offsets[i]` is node i's clock minus the master's (the
// master itself reports 0 if it takes part). Offsets more than `tolerance`
// from the median are left out of the average; `out[i]` is what node i adds
// to its clock. Division truncates toward zero.
fn berkeley(offsets: []const i64, n: usize, tolerance: i64, out: []i64) -> err {
    if n == 0usize || n > offsets.len || tolerance < 0i64 { ret Invalid }
    if out.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        out[i] = offsets[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let o = out[i]
        var j = i
        while j > 0usize && out[j - 1usize] > o {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = o
        i += 1usize
    }
    let median = out[n / 2usize]
    var sum = 0i64
    var kept = 0i64
    i = 0usize
    while i < n {
        var gap = offsets[i] - median
        if gap < 0i64 { gap = 0i64 - gap }
        if gap <= tolerance {
            sum += offsets[i]
            kept += 1i64
        }
        i += 1usize
    }
    let average = sum / kept
    i = 0usize
    while i < n {
        out[i] = average - offsets[i]
        i += 1usize
    }
    ret ok
}

// The client's step: `t_server` was read while the request was in flight
// between `t0_send` and `t1_receive` on the client's clock. Answers the
// client's estimate of the server's clock at `t1_receive` and the error
// bound, half the round trip less `min_one_way`, the least the network takes.
fn cristian(t0_send: i64, t_server: i64, t1_receive: i64, min_one_way: i64) -> (i64, i64) {
    let rtt = t1_receive - t0_send
    let half = rtt / 2i64
    var bound = half - min_one_way
    if bound < 0i64 { bound = 0i64 }
    ret (t_server + half, bound)
}
