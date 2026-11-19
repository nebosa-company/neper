// e.algo.stat.mstatepkg: the mstate package's probtrans (forward, no variance): the Aalen-Johansen estimate, the product over the event times after predt of (I + dA), where dA has the
// increments of the cumulative transition hazards off the diagonal and minus their row sums on it.

use e.math
use e.mem

// from[k], to[k]: the states (0-based) of transition k; cum is trans-major (cum[k * nt + t] the cumulative hazard of transition k at times[t]); out receives, for each of the
// returned count + 1 rows, the S by S matrix P(predt, .) row-major: row 0 is the identity at predt, row i the product after the i-th event time greater than predt.
fn probtrans_forward(a: *mem.Arena, s: usize, ntrans: usize, from: []const usize, to: []const usize, nt: usize, times: []const f64, cum: []const f64, predt: f64, out: []f64) -> (usize, err) {
    let (p, e0) = mem.alloc[f64](a, s * s)
    let (q, e1) = mem.alloc[f64](a, s * s)
    let (d, e2) = mem.alloc[f64](a, s * s)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < s * s {
        p[i] = 0.0f64
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < s {
        p[i * s + i] = 1.0f64
        out[i * s + i] = 1.0f64
        i += 1usize
    }
    var rows = 0usize
    var t = 0usize
    while t < nt {
        if times[t] > predt {
            i = 0usize
            while i < s * s {
                d[i] = 0.0f64
                i += 1usize
            }
            i = 0usize
            while i < s {
                d[i * s + i] = 1.0f64
                i += 1usize
            }
            var k = 0usize
            while k < ntrans {
                var prev = 0.0f64
                if t > 0usize { prev = cum[k * nt + t - 1usize] }
                let dh = cum[k * nt + t] - prev
                d[from[k] * s + to[k]] = dh
                d[from[k] * s + from[k]] = d[from[k] * s + from[k]] - dh
                k += 1usize
            }
            var r = 0usize
            while r < s {
                var c = 0usize
                while c < s {
                    var v = 0.0f64
                    var m = 0usize
                    while m < s {
                        v += p[r * s + m] * d[m * s + c]
                        m += 1usize
                    }
                    q[r * s + c] = v
                    c += 1usize
                }
                r += 1usize
            }
            i = 0usize
            while i < s * s {
                p[i] = q[i]
                i += 1usize
            }
            rows += 1usize
            i = 0usize
            while i < s * s {
                out[rows * s * s + i] = p[i]
                i += 1usize
            }
        }
        t += 1usize
    }
    ret (rows, ok)
}

// msprep: the long format of multi-state data. trans is K by K row-major (0 for no transition, else the transition number); time and status are n by K row-major (the
// starting state's column is ignored); every subject starts in state 0 at time 0. out receives rows of 7 values (id from to trans Tstart Tstop status), ids and states
// 1-based as in R, sorted by id, Tstart, from, to; the answer is the row count (out holds at least n * K * K * 7 values).
fn msprep(a: *mem.Arena, k: usize, n: usize, trans: []const usize, time: []const f64, status: []const f64, out: []f64) -> (usize, err) {
    var rows = 0usize
    var sub = 0usize
    while sub < n {
        var state = 0usize
        var tstart = 0.0f64
        var go = true
        while go {
            var reach = 0usize
            var to = 0usize
            while to < k {
                if trans[state * k + to] > 0usize { reach += 1usize }
                to += 1usize
            }
            if reach == 0usize { break }
            var smallest = math.inf64()
            var nexttime = math.inf64()
            var best = k
            to = 0usize
            while to < k {
                if trans[state * k + to] > 0usize {
                    var ts = time[sub * k + to]
                    if ts < tstart { ts = math.inf64() }
                    if ts < smallest { smallest = ts }
                    var h = math.inf64()
                    if status[sub * k + to] != 0.0f64 { h = ts / status[sub * k + to] }
                    if ts == 0.0f64 && status[sub * k + to] == 0.0f64 { h = math.inf64() }
                    if h < nexttime {
                        nexttime = h
                        best = to
                    }
                }
                to += 1usize
            }
            var censored = false
            if nexttime == math.inf64() {
                censored = true
                nexttime = smallest
            }
            to = 0usize
            while to < k {
                if trans[state * k + to] > 0usize {
                    var st = 0.0f64
                    if !censored && to == best { st = 1.0f64 }
                    let r = rows * 7usize
                    out[r] = f64(sub + 1usize)
                    out[r + 1usize] = f64(state + 1usize)
                    out[r + 2usize] = f64(to + 1usize)
                    out[r + 3usize] = f64(trans[state * k + to])
                    out[r + 4usize] = tstart
                    out[r + 5usize] = nexttime
                    out[r + 6usize] = st
                    rows += 1usize
                }
                to += 1usize
            }
            if censored { break }
            state = best
            tstart = nexttime
        }
        sub += 1usize
    }
    ret (rows, ok)
}

// msfit for the model with no covariates (coxph(Surv(Tstart, Tstop, status) ~ strata(trans)), Breslow): the Nelson-Aalen cumulative hazard of each transition at the unique times
// of the status-1 rows (over all transitions) and the largest follow-up time (survfit includes it). rows is the msprep output (7 values a row); times receives the unique event times and cum (trans-major, ntrans by the count) the
// cumulative hazards; the answer is the number of unique times. A transition with nobody at risk at a time adds nothing.
fn msfit_nelson_aalen(a: *mem.Arena, nrows: usize, rows: []const f64, ntrans: usize, times: []f64, cum: []f64) -> usize {
    var mx = 0.0f64
    var r0 = 0usize
    while r0 < nrows {
        if rows[r0 * 7usize + 5usize] > mx { mx = rows[r0 * 7usize + 5usize] }
        r0 += 1usize
    }
    var cnt = 0usize
    var r = 0usize
    while r < nrows {
        var tmax = rows[r * 7usize + 6usize] != 0.0f64
        if rows[r * 7usize + 5usize] == mx { tmax = true }
        if tmax {
            let v = rows[r * 7usize + 5usize]
            var j = cnt
            var dup = false
            var q = 0usize
            while q < cnt {
                if times[q] == v { dup = true }
                q += 1usize
            }
            if !dup {
                while j > 0usize && times[j - 1usize] > v {
                    times[j] = times[j - 1usize]
                    j -= 1usize
                }
                times[j] = v
                cnt += 1usize
            }
        }
        r += 1usize
    }
    var k = 0usize
    while k < ntrans {
        var acc = 0.0f64
        var t = 0usize
        while t < cnt {
            var dd = 0.0f64
            var nr = 0.0f64
            r = 0usize
            while r < nrows {
                if usize(rows[r * 7usize + 3usize]) == k + 1usize {
                    if rows[r * 7usize + 4usize] < times[t] && times[t] <= rows[r * 7usize + 5usize] {
                        nr += 1.0f64
                        if rows[r * 7usize + 5usize] == times[t] && rows[r * 7usize + 6usize] != 0.0f64 { dd += 1.0f64 }
                    }
                }
                r += 1usize
            }
            if nr > 0.0f64 { acc += dd / nr }
            cum[k * cnt + t] = acc
            t += 1usize
        }
        k += 1usize
    }
    ret cnt
}

// probtrans with direction = "fixedhorizon" (no variance): the matrices P(t, predt) for t = 0 and each event time t_k <= predt, row 0 the product of every (I + dA) up to predt (later
// factors on the right), row k the product over the times after t_k, row TT the identity at the last time; when predt is not an event time one more identity row follows (at predt).
// The answer is the number of rows.
fn probtrans_fixed(a: *mem.Arena, s: usize, ntrans: usize, from: []const usize, to: []const usize, nt: usize, times: []const f64, cum: []const f64, predt: f64, out: []f64) -> (usize, err) {
    var tt = 0usize
    var t = 0usize
    while t < nt {
        if times[t] <= predt { tt += 1usize }
        t += 1usize
    }
    let (p, e0) = mem.alloc[f64](a, s * s)
    let (q, e1) = mem.alloc[f64](a, s * s)
    let (d, e2) = mem.alloc[f64](a, s * s)
    if e0 != ok || e1 != ok || e2 != ok { ret (0usize, mem.Full) }
    var i = 0usize
    while i < s * s {
        p[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < s {
        p[i * s + i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < s * s {
        out[tt * s * s + i] = p[i]
        i += 1usize
    }
    var k = tt
    while k > 0usize {
        let ti = k - 1usize
        i = 0usize
        while i < s * s {
            d[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < s {
            d[i * s + i] = 1.0f64
            i += 1usize
        }
        var m = 0usize
        while m < ntrans {
            var prev = 0.0f64
            if ti > 0usize { prev = cum[m * nt + ti - 1usize] }
            let dh = cum[m * nt + ti] - prev
            d[from[m] * s + to[m]] = dh
            d[from[m] * s + from[m]] = d[from[m] * s + from[m]] - dh
            m += 1usize
        }
        var r = 0usize
        while r < s {
            var c = 0usize
            while c < s {
                var v = 0.0f64
                var z = 0usize
                while z < s {
                    v += d[r * s + z] * p[z * s + c]
                    z += 1usize
                }
                q[r * s + c] = v
                c += 1usize
            }
            r += 1usize
        }
        i = 0usize
        while i < s * s {
            p[i] = q[i]
            out[(k - 1usize) * s * s + i] = p[i]
            i += 1usize
        }
        k -= 1usize
    }
    var rows = tt + 1usize
    if tt == 0usize || times[tt - 1usize] != predt {
        i = 0usize
        while i < s * s {
            out[rows * s * s + i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < s {
            out[rows * s * s + i * s + i] = 1.0f64
            i += 1usize
        }
        rows += 1usize
    }
    ret (rows, ok)
}
