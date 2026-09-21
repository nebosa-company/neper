// Pairwise sequence alignment over bytes in caller storage, scores as
// `i64` with a match reward, mismatch and gap penalties given by the
// caller. `global` is Needleman-Wunsch, `local` is Smith-Waterman (the best
// local score and where it ends), `affine_gap` is Gotoh with an opening
// and an extension penalty, and `global_linear_space` is Hirschberg's
// divide and conquer, answering the same score as `global` with two rows
// of storage and writing the alignment as edit operations.

type Scores = struct { match_score: i64, mismatch: i64, gap: i64 }
type Op = enum u8 { Match, Insert, Delete }
error TooSmall

fn score_pair(s: Scores, a: u8, b: u8) -> i64 {
    if a == b { ret s.match_score }
    ret s.mismatch
}

fn max3(a: i64, b: i64, c: i64) -> i64 {
    var m = a
    if b > m { m = b }
    if c > m { m = c }
    ret m
}

// The global alignment score; `scratch.len >= 2 * (b.len + 1)`.
fn global(a: str, b: str, s: Scores, scratch: []i64) -> (i64, err) {
    let width = b.len + 1usize
    if scratch.len < 2usize * width { ret (0i64, TooSmall) }
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = i64(j) * s.gap
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        current[0usize] = i64(i + 1usize) * s.gap
        j = 0usize
        while j < b.len {
            current[j + 1usize] = max3(previous[j] + score_pair(s, a[i], b[j]), previous[j + 1usize] + s.gap, current[j] + s.gap)
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (previous[b.len], ok)
}

// The best local alignment score and the end positions (exclusive) in `a`
// and `b`; `scratch.len >= 2 * (b.len + 1)`.
fn local(a: str, b: str, s: Scores, scratch: []i64) -> (i64, usize, usize, err) {
    let width = b.len + 1usize
    if scratch.len < 2usize * width { ret (0i64, 0usize, 0usize, TooSmall) }
    var previous = scratch[..width]
    var current = scratch[width..2usize * width]
    var j = 0usize
    while j < width {
        previous[j] = 0i64
        j += 1usize
    }
    var best = 0i64
    var best_i = 0usize
    var best_j = 0usize
    var i = 0usize
    while i < a.len {
        current[0usize] = 0i64
        j = 0usize
        while j < b.len {
            var v = max3(previous[j] + score_pair(s, a[i], b[j]), previous[j + 1usize] + s.gap, current[j] + s.gap)
            if v < 0i64 { v = 0i64 }
            current[j + 1usize] = v
            if v > best {
                best = v
                best_i = i + 1usize
                best_j = j + 1usize
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (best, best_i, best_j, ok)
}

// Gotoh: global alignment where a gap of length k costs `open + k * extend`;
// `scratch.len >= 6 * (b.len + 1)` (three rows, two generations).
fn affine_gap(a: str, b: str, s: Scores, open: i64, extend: i64, scratch: []i64) -> (i64, err) {
    let width = b.len + 1usize
    if scratch.len < 6usize * width { ret (0i64, TooSmall) }
    let none = 0i64 - 4611686018427387904i64
    var m_prev = scratch[..width]
    var x_prev = scratch[width..2usize * width]
    var y_prev = scratch[2usize * width..3usize * width]
    var m_cur = scratch[3usize * width..4usize * width]
    var x_cur = scratch[4usize * width..5usize * width]
    var y_cur = scratch[5usize * width..6usize * width]
    // M: ends in a match; X: ends in a gap in b (a consumed); Y: gap in a (b consumed).
    m_prev[0usize] = 0i64
    x_prev[0usize] = none
    y_prev[0usize] = none
    var j = 1usize
    while j < width {
        m_prev[j] = none
        x_prev[j] = none
        y_prev[j] = open + i64(j) * extend
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        m_cur[0usize] = none
        x_cur[0usize] = open + i64(i + 1usize) * extend
        y_cur[0usize] = none
        j = 0usize
        while j < b.len {
            m_cur[j + 1usize] = max3(m_prev[j], x_prev[j], y_prev[j]) + score_pair(s, a[i], b[j])
            x_cur[j + 1usize] = max3(m_prev[j + 1usize] + open + extend, x_prev[j + 1usize] + extend, y_prev[j + 1usize] + open + extend)
            y_cur[j + 1usize] = max3(m_cur[j] + open + extend, x_cur[j] + open + extend, y_cur[j] + extend)
            j += 1usize
        }
        var swap = m_prev
        m_prev = m_cur
        m_cur = swap
        swap = x_prev
        x_prev = x_cur
        x_cur = swap
        swap = y_prev
        y_prev = y_cur
        y_cur = swap
        i += 1usize
    }
    ret (max3(m_prev[b.len], x_prev[b.len], y_prev[b.len]), ok)
}

// The last row of the global score table of `a` against `b`, or of their
// reversals when `reverse`; into `row` (`b.len + 1`) with `work` as the other row.
fn last_row(a: str, b: str, s: Scores, reverse: bool, row: []i64, work: []i64) {
    let width = b.len + 1usize
    var j = 0usize
    while j < width {
        row[j] = i64(j) * s.gap
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        var ai = a[i]
        if reverse { ai = a[a.len - 1usize - i] }
        work[0usize] = i64(i + 1usize) * s.gap
        j = 0usize
        while j < b.len {
            var bj = b[j]
            if reverse { bj = b[b.len - 1usize - j] }
            work[j + 1usize] = max3(row[j] + score_pair(s, ai, bj), row[j + 1usize] + s.gap, work[j] + s.gap)
            j += 1usize
        }
        j = 0usize
        while j < width {
            row[j] = work[j]
            j += 1usize
        }
        i += 1usize
    }
}

// Hirschberg: the global score and the alignment as operations in `ops`
// (`Match` pairs a[i] with b[j], `Delete` consumes a, `Insert` consumes b);
// `scratch.len >= 4 * (b.len + 1)`. Answers the score and the operation count.
fn global_linear_space(a: str, b: str, s: Scores, ops: []Op, scratch: []i64) -> (i64, usize, err) {
    let width = b.len + 1usize
    if scratch.len < 4usize * width || ops.len < a.len + b.len { ret (0i64, 0usize, TooSmall) }
    let (score, score_error) = global(a, b, s, scratch)
    if score_error != ok { ret (0i64, 0usize, score_error) }
    let count = hirschberg(a, b, s, ops, 0usize, scratch)
    ret (score, count, ok)
}

fn hirschberg(a: str, b: str, s: Scores, ops: []Op, at: usize, scratch: []i64) -> usize {
    var n = at
    if a.len == 0usize {
        var j = 0usize
        while j < b.len {
            ops[n] = .Insert
            n += 1usize
            j += 1usize
        }
        ret n - at
    }
    if b.len == 0usize {
        var i = 0usize
        while i < a.len {
            ops[n] = .Delete
            n += 1usize
            i += 1usize
        }
        ret n - at
    }
    if a.len == 1usize {
        // One row: match a[0] against the best b[j], the rest are inserts.
        var best_j = b.len
        var best = i64(b.len) * s.gap + s.gap
        var j = 0usize
        while j < b.len {
            let v = i64(b.len - 1usize) * s.gap + score_pair(s, a[0usize], b[j])
            if v > best {
                best = v
                best_j = j
            }
            j += 1usize
        }
        j = 0usize
        while j < b.len {
            if j == best_j {
                ops[n] = .Match
            } else {
                ops[n] = .Insert
            }
            n += 1usize
            j += 1usize
        }
        if best_j == b.len {
            ops[n] = .Delete
            n += 1usize
        }
        ret n - at
    }
    let width = b.len + 1usize
    let middle = a.len / 2usize
    var forward = scratch[..width]
    var backward = scratch[width..2usize * width]
    var work = scratch[2usize * width..3usize * width]
    last_row(a[..middle], b, s, false, forward, work)
    last_row(a[middle..], b, s, true, backward, work)
    var split = 0usize
    var best = forward[0usize] + backward[b.len]
    var j = 1usize
    while j <= b.len {
        let v = forward[j] + backward[b.len - j]
        if v > best {
            best = v
            split = j
        }
        j += 1usize
    }
    let first = hirschberg(a[..middle], b[..split], s, ops, n, scratch)
    n += first
    let second = hirschberg(a[middle..], b[split..], s, ops, n, scratch)
    n += second
    ret n - at
}
