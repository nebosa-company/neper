// Line diffs in caller storage. A text is a slice of lines (`[]const str`)
// and an edit script is a sequence of `Edit`s, each keeping, deleting or
// inserting one line and carrying that line's text. `myers` finds a shortest
// script (the O(ND) greedy algorithm with its furthest-reaching frontiers
// kept for the trace back), `patience` anchors on lines unique to both
// sides and recurses, falling back to `myers` between anchors; `patch`
// replays a script on a text, checking every kept and deleted line;
// `merge3` merges two revisions of a base, `conflicts` names the base
// ranges both sides changed, and `similarity` is the line-overlap ratio
// rename detection uses.

type Op = enum u8 { Keep, Delete, Insert }
type Edit = struct { op: Op, line: str }
type Range = struct { start: usize, end: usize }
error TooSmall
error Mismatch

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The frontier storage Myers needs: `(n + m + 1) * (2 * (n + m) + 3)`.
fn myers_scratch(n: usize, m: usize) -> usize { ret (n + m + 1usize) * (2usize * (n + m) + 3usize) }

// ponytail: every frontier is kept, O((n + m)^2) storage; the linear-space
// middle-snake refinement is the upgrade if long texts matter.
fn myers(a: []const str, b: []const str, edits: []Edit, scratch: []usize) -> (usize, err) {
    let n = a.len
    let m = b.len
    let max = n + m
    let width = 2usize * max + 3usize
    if scratch.len < myers_scratch(n, m) { ret (0usize, TooSmall) }
    if edits.len < max { ret (0usize, TooSmall) }
    // v[d][k + max + 1] is the furthest x on diagonal k after d edits.
    var found = false
    var d = 0usize
    var v = scratch[..width]
    v[max + 2usize] = 0usize
    while d <= max && !found {
        var row = scratch[d * width..(d + 1usize) * width]
        if d > 0usize {
            let previous = scratch[(d - 1usize) * width..d * width]
            var i = 0usize
            while i < width {
                row[i] = previous[i]
                i += 1usize
            }
        }
        var k = 0usize
        // k runs over -d, -d + 2, ..., d as offsets from max + 1.
        var offset = max + 1usize - d
        while k <= 2usize * d && !found {
            let slot = offset + k
            var x = 0usize
            if k == 0usize || (k != 2usize * d && row[slot - 1usize] < row[slot + 1usize]) {
                if d > 0usize { x = row[slot + 1usize] }
            } else {
                x = row[slot - 1usize] + 1usize
            }
            // y = x - kd where kd = k - d (may be negative).
            var y = x + d
            y -= k
            while x < n && y < m && same(a[x], b[y]) {
                x += 1usize
                y += 1usize
            }
            row[slot] = x
            if x >= n && y >= m { found = true }
            k += 2usize
        }
        if !found { d += 1usize }
    }
    // Trace back from (n, m) through the frontiers, writing edits from the end.
    var total = d
    // The script has d non-keeps plus every kept line; count the keeps first by walking.
    var x = n
    var y = m
    var written = 0usize
    // First pass: count edits so they can be written back to front.
    var dd = d
    var xx = x
    var yy = y
    while dd > 0usize {
        let row = scratch[dd * width..(dd + 1usize) * width]
        let kd = xx + dd - yy
        let slot = max + 1usize - dd + kd
        let previous = scratch[(dd - 1usize) * width..dd * width]
        var down = false
        if kd == 0usize || (kd != 2usize * dd && previous[slot - 1usize] < previous[slot + 1usize]) { down = true }
        var px = 0usize
        var py = 0usize
        if down {
            px = previous[slot + 1usize]
        } else {
            px = previous[slot - 1usize]
        }
        py = px + dd - 1usize
        // The previous diagonal in the previous row's numbering: kd for k + 1, kd - 2 for k - 1.
        var kp = kd
        if !down { kp -= 2usize }
        py -= kp
        // The snake from (px, py) plus one edit lands at (xx, yy).
        var snake = xx - px
        if !down { snake -= 1usize }
        total += snake
        xx = px
        yy = py
        dd -= 1usize
    }
    total += xx
    if edits.len < total { ret (0usize, TooSmall) }
    // Second pass: write.
    var at = total
    xx = x
    yy = y
    dd = d
    while dd > 0usize {
        let kd = xx + dd - yy
        let slot = max + 1usize - dd + kd
        let previous = scratch[(dd - 1usize) * width..dd * width]
        var down = false
        if kd == 0usize || (kd != 2usize * dd && previous[slot - 1usize] < previous[slot + 1usize]) { down = true }
        var px = 0usize
        if down { px = previous[slot + 1usize] } else { px = previous[slot - 1usize] }
        var kp = kd
        if !down { kp -= 2usize }
        var py = px + dd - 1usize
        py -= kp
        var mx = px
        var my = py
        if down { my += 1usize } else { mx += 1usize }
        while xx > mx {
            at -= 1usize
            xx -= 1usize
            yy -= 1usize
            edits[at] = Edit { op: .Keep, line: a[xx] }
        }
        at -= 1usize
        if down {
            edits[at] = Edit { op: .Insert, line: b[py] }
        } else {
            edits[at] = Edit { op: .Delete, line: a[px] }
        }
        xx = px
        yy = py
        dd -= 1usize
    }
    while xx > 0usize {
        at -= 1usize
        xx -= 1usize
        edits[at] = Edit { op: .Keep, line: a[xx] }
    }
    ret (total, ok)
}

// Replay `edits` on `target`, checking every kept and deleted line against
// it; `out` receives the result. `Mismatch` when the text differs.
fn patch(text: []const str, edits: []const Edit, out: []str) -> (usize, err) {
    var i = 0usize
    var n = 0usize
    var e = 0usize
    while e < edits.len {
        let edit = edits[e]
        if edit.op == .Insert {
            if n >= out.len { ret (n, TooSmall) }
            out[n] = edit.line
            n += 1usize
        } else {
            if i >= text.len || !same(text[i], edit.line) { ret (n, Mismatch) }
            if edit.op == .Keep {
                if n >= out.len { ret (n, TooSmall) }
                out[n] = text[i]
                n += 1usize
            }
            i += 1usize
        }
        e += 1usize
    }
    if i != text.len { ret (n, Mismatch) }
    ret (n, ok)
}

// Patience diff: lines occurring exactly once in each side are matched by
// the longest increasing subsequence of their positions, and the gaps
// between matches are diffed the same way, `myers` when no unique line
// remains. `scratch.len >= myers_scratch(n, m) + 6 * (n + m) + 8`.
fn patience(a: []const str, b: []const str, edits: []Edit, scratch: []usize) -> (usize, err) {
    let n = a.len
    let m = b.len
    let need = myers_scratch(n, m)
    if scratch.len < need + 18usize * (n + m) + 16usize { ret (0usize, TooSmall) }
    var work = scratch[..need]
    var at = need
    // A stack of ranges (a_lo, a_hi, b_lo, b_hi), processed left to right.
    var stack = scratch[at..at + 4usize * (3usize * (n + m) + 4usize)]
    at += 4usize * (3usize * (n + m) + 4usize)
    var pairs = scratch[at..at + 2usize * (n + m)]
    at += 2usize * (n + m)
    var top = 0usize
    stack[0usize] = 0usize
    stack[1usize] = n
    stack[2usize] = 0usize
    stack[3usize] = m
    top = 1usize
    var count = 0usize
    while top > 0usize {
        top -= 1usize
        let a_lo = stack[4usize * top]
        let a_hi = stack[4usize * top + 1usize]
        let b_lo = stack[4usize * top + 2usize]
        let b_hi = stack[4usize * top + 3usize]
        if a_hi == a_lo + 1usize && b_hi == b_lo + 1usize && same(a[a_lo], b[b_lo]) {
            // An anchor: one kept line.
            if count >= edits.len { ret (count, TooSmall) }
            edits[count] = Edit { op: .Keep, line: a[a_lo] }
            count += 1usize
        } else {
            // Unique lines of a[a_lo..a_hi] that are unique in b[b_lo..b_hi] too.
            var unique = 0usize
            var i = a_lo
            while i < a_hi {
                var in_a = 0usize
                var j = a_lo
                while j < a_hi && in_a < 2usize {
                    if same(a[j], a[i]) { in_a += 1usize }
                    j += 1usize
                }
                if in_a == 1usize {
                    var in_b = 0usize
                    var where = b_lo
                    j = b_lo
                    while j < b_hi && in_b < 2usize {
                        if same(b[j], a[i]) {
                            in_b += 1usize
                            where = j
                        }
                        j += 1usize
                    }
                    if in_b == 1usize {
                        pairs[2usize * unique] = i
                        pairs[2usize * unique + 1usize] = where
                        unique += 1usize
                    }
                }
                i += 1usize
            }
            if unique == 0usize {
                let (produced, myers_error) = myers(a[a_lo..a_hi], b[b_lo..b_hi], edits[count..], work)
                if myers_error != ok { ret (count, myers_error) }
                count += produced
            } else {
                // Patience sorting: the longest chain of pairs increasing in b, by
                // the O(u^2) chain DP (the pairs are already increasing in a).
                var length = scratch[at..at + unique]
                var previous = scratch[at + unique..at + 2usize * unique]
                var best = 0usize
                i = 0usize
                while i < unique {
                    length[i] = 1usize
                    previous[i] = unique
                    var j = 0usize
                    while j < i {
                        if pairs[2usize * j + 1usize] < pairs[2usize * i + 1usize] && length[j] + 1usize > length[i] {
                            length[i] = length[j] + 1usize
                            previous[i] = j
                        }
                        j += 1usize
                    }
                    if length[i] > length[best] { best = i }
                    i += 1usize
                }
                // Collect the chain in order into pairs[..chain] (it only shrinks).
                var chain = length[best]
                var k = chain
                var node = best
                while node != unique {
                    k -= 1usize
                    pairs[2usize * k] = pairs[2usize * node]
                    pairs[2usize * k + 1usize] = pairs[2usize * node + 1usize]
                    node = previous[node]
                }
                // Push the gaps and the anchors in reverse so the first is on top:
                // gap before anchor 0, anchor 0, gap, anchor 1, ..., last gap.
                var pa = a_hi
                var pb = b_hi
                k = chain
                while k > 0usize {
                    k -= 1usize
                    let ai = pairs[2usize * k]
                    let bi = pairs[2usize * k + 1usize]
                    stack[4usize * top] = ai + 1usize
                    stack[4usize * top + 1usize] = pa
                    stack[4usize * top + 2usize] = bi + 1usize
                    stack[4usize * top + 3usize] = pb
                    top += 1usize
                    // The anchor itself: a range of one kept line, marked by a_hi == a_lo + 1 and equal lines.
                    stack[4usize * top] = ai
                    stack[4usize * top + 1usize] = ai + 1usize
                    stack[4usize * top + 2usize] = bi
                    stack[4usize * top + 3usize] = bi + 1usize
                    top += 1usize
                    pa = ai
                    pb = bi
                }
                stack[4usize * top] = a_lo
                stack[4usize * top + 1usize] = pa
                stack[4usize * top + 2usize] = b_lo
                stack[4usize * top + 3usize] = pb
                top += 1usize
            }
        }
        }
    ret (count, ok)
}

// The hunks of an edit script: maximal runs of non-keeps, each as (start,
// end, first edit, edit limit) where `start..end` are the base lines it
// deletes and its insertions sit at `end`; written to `hunks` as four
// numbers each, the count answered.
fn hunks_of(edits: []const Edit, produced: usize, hunks: []usize) -> (usize, err) {
    var count = 0usize
    var base = 0usize
    var e = 0usize
    while e < produced {
        if edits[e].op == .Keep {
            base += 1usize
            e += 1usize
        } else {
            let start = base
            let from = e
            while e < produced && edits[e].op != .Keep {
                if edits[e].op == .Delete { base += 1usize }
                e += 1usize
            }
            if 4usize * count + 3usize >= hunks.len { ret (count, TooSmall) }
            hunks[4usize * count] = start
            hunks[4usize * count + 1usize] = base
            hunks[4usize * count + 2usize] = from
            hunks[4usize * count + 3usize] = e
            count += 1usize
        }
    }
    ret (count, ok)
}

// The lines one side produces over base lines `s..e` (its kept lines there
// and its insertions at points `s..=e`), written from `n`; `write` false only
// counts. Answers the count and the new `n`.
fn side_lines(edits: []const Edit, produced: usize, s: usize, e: usize, out: []str, n: usize, write: bool) -> (usize, usize, err) {
    var base = 0usize
    var at = n
    var lines = 0usize
    var i = 0usize
    while i < produced && base <= e {
        let edit = edits[i]
        if edit.op == .Insert {
            if base >= s {
                if write {
                    if at >= out.len { ret (lines, at, TooSmall) }
                    out[at] = edit.line
                    at += 1usize
                }
                lines += 1usize
            }
        } else {
            if edit.op == .Keep && base >= s && base < e {
                if write {
                    if at >= out.len { ret (lines, at, TooSmall) }
                    out[at] = edit.line
                    at += 1usize
                }
                lines += 1usize
            }
            base += 1usize
        }
        i += 1usize
    }
    ret (lines, at, ok)
}

// The next line a side produces over `s..e` from cursor (`i`, `base`):
// answers whether there is one, the line, and the advanced cursor.
fn next_line(edits: []const Edit, produced: usize, s: usize, e: usize, i: usize, base: usize) -> (bool, str, usize, usize) {
    var at = i
    var b = base
    while at < produced && b <= e {
        let edit = edits[at]
        at += 1usize
        if edit.op == .Insert {
            if b >= s { ret (true, edit.line, at, b) }
        } else {
            let keep = edit.op == .Keep && b >= s && b < e
            b += 1usize
            if keep { ret (true, edit.line, at, b) }
        }
    }
    ret (false, "", at, b)
}

// Whether two sides produce the same lines over `s..e`.
fn sides_agree(ours: []const Edit, our_count: usize, theirs: []const Edit, their_count: usize, s: usize, e: usize) -> bool {
    var oi = 0usize
    var ob = 0usize
    var ti = 0usize
    var tb = 0usize
    var going = true
    while going {
        let (our_has, our_line, oi2, ob2) = next_line(ours, our_count, s, e, oi, ob)
        let (their_has, their_line, ti2, tb2) = next_line(theirs, their_count, s, e, ti, tb)
        if our_has != their_has { ret false }
        if !our_has { going = false } else if !same(our_line, their_line) { ret false }
        oi = oi2
        ob = ob2
        ti = ti2
        tb = tb2
    }
    ret true
}

// The shared walk of `merge3` and `conflicts`: base lines both sides keep
// pass through; where hunks of either side meet, the region is one side
// alone, identical on both, or a conflict. `write` controls `out`; `found`
// (when `record`) receives the conflict regions.
fn walk(base: []const str, ours: []const Edit, our_count: usize, theirs: []const Edit, their_count: usize, out: []str, write: bool, found: []Range, record: bool, scratch: []usize) -> (usize, usize, err) {
    let cap = base.len + 1usize
    if scratch.len < 8usize * cap { ret (0usize, 0usize, TooSmall) }
    var our_hunks = scratch[..4usize * cap]
    var their_hunks = scratch[4usize * cap..8usize * cap]
    let (oh, oh_error) = hunks_of(ours, our_count, our_hunks)
    if oh_error != ok { ret (0usize, 0usize, oh_error) }
    let (th, th_error) = hunks_of(theirs, their_count, their_hunks)
    if th_error != ok { ret (0usize, 0usize, th_error) }
    var n = 0usize
    var conflict_count = 0usize
    var p = 0usize
    var hi = 0usize
    var hj = 0usize
    while p < base.len || hi < oh || hj < th {
        // The next hunk start on either side, or the end of the base.
        var start = base.len
        if hi < oh && our_hunks[4usize * hi] < start { start = our_hunks[4usize * hi] }
        if hj < th && their_hunks[4usize * hj] < start { start = their_hunks[4usize * hj] }
        while p < start {
            if write {
                if n >= out.len { ret (n, conflict_count, TooSmall) }
                out[n] = base[p]
            }
            n += 1usize
            p += 1usize
        }
        if hi >= oh && hj >= th { ret (n, conflict_count, ok) }
        // Grow the region until no hunk on either side starts within it.
        let s = start
        var e = start
        var ours_in = 0usize
        var theirs_in = 0usize
        var growing = true
        while growing {
            growing = false
            if hi < oh && our_hunks[4usize * hi] <= e {
                if our_hunks[4usize * hi + 1usize] > e { e = our_hunks[4usize * hi + 1usize] }
                hi += 1usize
                ours_in += 1usize
                growing = true
            }
            if hj < th && their_hunks[4usize * hj] <= e {
                if their_hunks[4usize * hj + 1usize] > e { e = their_hunks[4usize * hj + 1usize] }
                hj += 1usize
                theirs_in += 1usize
                growing = true
            }
        }
        var identical = false
        if ours_in > 0usize && theirs_in > 0usize { identical = sides_agree(ours, our_count, theirs, their_count, s, e) }
        if theirs_in == 0usize || identical {
            let (_, n2, e1) = side_lines(ours, our_count, s, e, out, n, write)
            if e1 != ok { ret (n2, conflict_count, e1) }
            n = n2
        } else if ours_in == 0usize {
            let (_, n2, e2) = side_lines(theirs, their_count, s, e, out, n, write)
            if e2 != ok { ret (n2, conflict_count, e2) }
            n = n2
        } else {
            if record {
                if conflict_count >= found.len { ret (n, conflict_count, TooSmall) }
                found[conflict_count] = Range { start: s, end: e }
            }
            conflict_count += 1usize
            if write {
                if n >= out.len { ret (n, conflict_count, TooSmall) }
                out[n] = "<<<<<<<"
            }
            n += 1usize
            let (_, n2, e3) = side_lines(ours, our_count, s, e, out, n, write)
            if e3 != ok { ret (n2, conflict_count, e3) }
            n = n2
            if write {
                if n >= out.len { ret (n, conflict_count, TooSmall) }
                out[n] = "======="
            }
            n += 1usize
            let (_, n3, e4) = side_lines(theirs, their_count, s, e, out, n, write)
            if e4 != ok { ret (n3, conflict_count, e4) }
            n = n3
            if write {
                if n >= out.len { ret (n, conflict_count, TooSmall) }
                out[n] = ">>>>>>>"
            }
            n += 1usize
        }
        p = e
    }
    ret (n, conflict_count, ok)
}

fn both_scripts(base: []const str, ours: []const str, theirs: []const str, edits: []Edit, scratch: []usize) -> (usize, usize, err) {
    let half = edits.len / 2usize
    let (our_count, our_error) = myers(base, ours, edits[..half], scratch)
    if our_error != ok { ret (0usize, 0usize, our_error) }
    let (their_count, their_error) = myers(base, theirs, edits[half..], scratch)
    if their_error != ok { ret (0usize, 0usize, their_error) }
    ret (our_count, their_count, ok)
}

// Three-way merge: where only one side changed a region the change is
// taken, where both changed it identically it is taken once, and where they
// differ the region is written as `<<<<<<<`, our lines, `=======`, their
// lines, `>>>>>>>`. Answers the line count and the number of conflicts;
// `edits.len >= 2 * (base.len + max(ours.len, theirs.len))` and
// `scratch.len >= max(myers_scratch(base.len, max(ours.len, theirs.len)), 8 * (base.len + 1))`.
fn merge3(base: []const str, ours: []const str, theirs: []const str, out: []str, edits: []Edit, scratch: []usize) -> (usize, usize, err) {
    let (our_count, their_count, script_error) = both_scripts(base, ours, theirs, edits, scratch)
    if script_error != ok { ret (0usize, 0usize, script_error) }
    let half = edits.len / 2usize
    var none: [1]Range = zero
    let (lines, conflict_count, walk_error) = walk(base, edits[..half], our_count, edits[half..], their_count, out, true, none[..], false, scratch)
    ret (lines, conflict_count, walk_error)
}

// The base ranges both sides changed differently, as `merge3` would mark
// them; the same storage as `merge3`.
fn conflicts(base: []const str, ours: []const str, theirs: []const str, edits: []Edit, found: []Range, scratch: []usize) -> (usize, err) {
    let (our_count, their_count, script_error) = both_scripts(base, ours, theirs, edits, scratch)
    if script_error != ok { ret (0usize, script_error) }
    let half = edits.len / 2usize
    var none: [1]str = zero
    let (_, count, walk_error) = walk(base, edits[..half], our_count, edits[half..], their_count, none[..], false, found, true, scratch)
    ret (count, walk_error)
}

// The similarity of two texts as lines: twice the longest common
// subsequence over the total line count, in [0, 1] (1 for two empty texts);
// `scratch.len >= 2 * (b.len + 1)`.
fn similarity(a: []const str, b: []const str, scratch: []usize) -> (f64, err) {
    let m = b.len
    if scratch.len < 2usize * (m + 1usize) { ret (0.0f64, TooSmall) }
    if a.len + m == 0usize { ret (1.0f64, ok) }
    var previous = scratch[..m + 1usize]
    var current = scratch[m + 1usize..2usize * (m + 1usize)]
    var j = 0usize
    while j <= m {
        previous[j] = 0usize
        j += 1usize
    }
    var i = 0usize
    while i < a.len {
        current[0usize] = 0usize
        j = 0usize
        while j < m {
            if same(a[i], b[j]) {
                current[j + 1usize] = previous[j] + 1usize
            } else if previous[j + 1usize] > current[j] {
                current[j + 1usize] = previous[j + 1usize]
            } else {
                current[j + 1usize] = current[j]
            }
            j += 1usize
        }
        let swap = previous
        previous = current
        current = swap
        i += 1usize
    }
    ret (2.0f64 * f64(previous[m]) / f64(a.len + m), ok)
}
