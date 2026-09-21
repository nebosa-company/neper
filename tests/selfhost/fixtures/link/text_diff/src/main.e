// `e.text.diff`: Myers finds the five-edit script of the paper's example
// and `patch` replays it (and refuses a different text), patience diff
// anchors on unique lines and yields a valid minimal script, three-way
// merges take one-sided changes, fold identical ones and mark the rest with
// conflict lines that `conflicts` also reports as base ranges, and the
// similarity ratio behaves at its ends. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.diff

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_lines(got: []const str, count: usize, want: []const str) -> bool {
    if count != want.len { ret false }
    var i = 0usize
    while i < count {
        if !same(got[i], want[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn changes(edits: []const diff.Edit, count: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < count {
        if edits[i].op != .Keep { n += 1usize }
        i += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    var edits: [64]diff.Edit = zero
    var scratch: [2048]usize = zero
    var out: [32]str = zero

    // 1: Myers on ABCABBA -> CBABAC.
    var x: [7]str = zero
    x[0usize] = "A"
    x[1usize] = "B"
    x[2usize] = "C"
    x[3usize] = "A"
    x[4usize] = "B"
    x[5usize] = "B"
    x[6usize] = "A"
    var y: [6]str = zero
    y[0usize] = "C"
    y[1usize] = "B"
    y[2usize] = "A"
    y[3usize] = "B"
    y[4usize] = "A"
    y[5usize] = "C"
    let (count, myers_error) = diff.myers(x[..], y[..], edits[..], scratch[..])
    if myers_error != ok || count != 9usize || changes(edits[..], count) != 5usize { os.exit(1i32) }
    let (patched, patch_error) = diff.patch(x[..], edits[..count], out[..])
    if patch_error != ok || !same_lines(out[..], patched, y[..]) { os.exit(1i32) }
    let (_, wrong) = diff.patch(y[..], edits[..count], out[..])
    if wrong != diff.Mismatch { os.exit(1i32) }
    let (_, short) = diff.patch(x[..], edits[..count - 2usize], out[..])
    if short != diff.Mismatch { os.exit(1i32) }
    let (same_count, same_error) = diff.myers(x[..], x[..], edits[..], scratch[..])
    if same_error != ok || same_count != 7usize || changes(edits[..], same_count) != 0usize { os.exit(1i32) }
    let (empty_count, empty_error) = diff.myers(x[..0usize], y[..], edits[..], scratch[..])
    if empty_error != ok || empty_count != 6usize || changes(edits[..], empty_count) != 6usize || edits[0usize].op != .Insert { os.exit(1i32) }
    let (both_empty, both_error) = diff.myers(x[..0usize], y[..0usize], edits[..], scratch[..])
    if both_error != ok || both_empty != 0usize { os.exit(1i32) }
    let (_, room) = diff.myers(x[..], y[..], edits[..], scratch[..20usize])
    if room != diff.TooSmall { os.exit(1i32) }
    let (_, edit_room) = diff.myers(x[..], y[..], edits[..4usize], scratch[..])
    if edit_room != diff.TooSmall { os.exit(1i32) }

    // 2: patience.
    let (p_count, p_error) = diff.patience(x[..], y[..], edits[..], scratch[..])
    if p_error != ok || changes(edits[..], p_count) > 7usize { os.exit(2i32) }
    let (p_patched, p_patch_error) = diff.patch(x[..], edits[..p_count], out[..])
    if p_patch_error != ok || !same_lines(out[..], p_patched, y[..]) { os.exit(2i32) }
    var s: [6]str = zero
    s[0usize] = "one"
    s[1usize] = "two"
    s[2usize] = "three"
    s[3usize] = "four"
    s[4usize] = "five"
    s[5usize] = "six"
    var t: [6]str = zero
    t[0usize] = "six"
    t[1usize] = "one"
    t[2usize] = "two"
    t[3usize] = "three"
    t[4usize] = "four"
    t[5usize] = "five"
    let (q_count, q_error) = diff.patience(s[..], t[..], edits[..], scratch[..])
    if q_error != ok || q_count != 7usize || changes(edits[..], q_count) != 2usize || edits[0usize].op != .Insert || edits[6usize].op != .Delete { os.exit(2i32) }
    let (q_patched, q_patch_error) = diff.patch(s[..], edits[..q_count], out[..])
    if q_patch_error != ok || !same_lines(out[..], q_patched, t[..]) { os.exit(2i32) }
    // Repeated lines with a unique anchor in the middle: the anchor is kept.
    var u: [5]str = zero
    u[0usize] = "x"
    u[1usize] = "x"
    u[2usize] = "mid"
    u[3usize] = "x"
    u[4usize] = "x"
    var v: [4]str = zero
    v[0usize] = "x"
    v[1usize] = "mid"
    v[2usize] = "x"
    v[3usize] = "y"
    let (r_count, r_error) = diff.patience(u[..], v[..], edits[..], scratch[..])
    if r_error != ok || changes(edits[..], r_count) != 3usize { os.exit(2i32) }
    let (r_patched, r_patch_error) = diff.patch(u[..], edits[..r_count], out[..])
    if r_patch_error != ok || !same_lines(out[..], r_patched, v[..]) { os.exit(2i32) }
    let (_, p_room) = diff.patience(x[..], y[..], edits[..], scratch[..300usize])
    if p_room != diff.TooSmall { os.exit(2i32) }

    // 3: three-way merges.
    var base: [7]str = zero
    base[0usize] = "a"
    base[1usize] = "b"
    base[2usize] = "c"
    base[3usize] = "d"
    base[4usize] = "e"
    base[5usize] = "f"
    base[6usize] = "g"
    var ours: [7]str = zero
    var theirs: [7]str = zero
    var i = 0usize
    while i < 7usize {
        ours[i] = base[i]
        theirs[i] = base[i]
        i += 1usize
    }
    ours[1usize] = "B"
    theirs[4usize] = "E"
    var found: [8]diff.Range = zero
    let (m1, c1, m1_error) = diff.merge3(base[..], ours[..], theirs[..], out[..], edits[..], scratch[..])
    var want1: [7]str = zero
    i = 0usize
    while i < 7usize {
        want1[i] = base[i]
        i += 1usize
    }
    want1[1usize] = "B"
    want1[4usize] = "E"
    if m1_error != ok || c1 != 0usize || !same_lines(out[..], m1, want1[..]) { os.exit(3i32) }
    let (k1, k1_error) = diff.conflicts(base[..], ours[..], theirs[..], edits[..], found[..], scratch[..])
    if k1_error != ok || k1 != 0usize { os.exit(3i32) }
    // Both change line 2 differently.
    theirs[4usize] = "e"
    theirs[1usize] = "X"
    let (m2, c2, m2_error) = diff.merge3(base[..], ours[..], theirs[..], out[..], edits[..], scratch[..])
    var want2: [11]str = zero
    want2[0usize] = "a"
    want2[1usize] = "<<<<<<<"
    want2[2usize] = "B"
    want2[3usize] = "======="
    want2[4usize] = "X"
    want2[5usize] = ">>>>>>>"
    want2[6usize] = "c"
    want2[7usize] = "d"
    want2[8usize] = "e"
    want2[9usize] = "f"
    want2[10usize] = "g"
    if m2_error != ok || c2 != 1usize || !same_lines(out[..], m2, want2[..]) { os.exit(3i32) }
    let (k2, k2_error) = diff.conflicts(base[..], ours[..], theirs[..], edits[..], found[..], scratch[..])
    if k2_error != ok || k2 != 1usize || found[0usize].start != 1usize || found[0usize].end != 2usize { os.exit(3i32) }
    // Both make the same change: taken once.
    theirs[1usize] = "B"
    let (m3, c3, m3_error) = diff.merge3(base[..], ours[..], theirs[..], out[..], edits[..], scratch[..])
    want1[4usize] = "e"
    if m3_error != ok || c3 != 0usize || !same_lines(out[..], m3, want1[..]) { os.exit(3i32) }
    // Ours deletes a line theirs keeps; theirs appends a line.
    theirs[1usize] = "b"
    var ours_short: [6]str = zero
    var theirs_long: [8]str = zero
    i = 0usize
    while i < 7usize {
        if i < 3usize { ours_short[i] = base[i] } else if i > 3usize { ours_short[i - 1usize] = base[i] }
        theirs_long[i] = base[i]
        i += 1usize
    }
    theirs_long[7usize] = "h"
    let (m4, c4, m4_error) = diff.merge3(base[..], ours_short[..], theirs_long[..], out[..], edits[..], scratch[..])
    var want4: [7]str = zero
    want4[0usize] = "a"
    want4[1usize] = "b"
    want4[2usize] = "c"
    want4[3usize] = "e"
    want4[4usize] = "f"
    want4[5usize] = "g"
    want4[6usize] = "h"
    if m4_error != ok || c4 != 0usize || !same_lines(out[..], m4, want4[..]) { os.exit(3i32) }
    // Overlapping multi-line hunks: ours rewrites b..c, theirs deletes c.
    ours[1usize] = "B"
    ours[2usize] = "C"
    i = 0usize
    while i < 7usize {
        if i < 2usize { ours_short[i] = base[i] } else if i > 2usize { ours_short[i - 1usize] = base[i] }
        i += 1usize
    }
    let (m5, c5, m5_error) = diff.merge3(base[..], ours[..], ours_short[..], out[..], edits[..], scratch[..])
    if m5_error != ok || c5 != 1usize || !same(out[0usize], "a") || !same(out[1usize], "<<<<<<<") || !same(out[2usize], "B") || !same(out[3usize], "C") || !same(out[4usize], "=======") || !same(out[5usize], "b") || !same(out[6usize], ">>>>>>>") || !same(out[7usize], "d") || m5 != 11usize { os.exit(3i32) }
    let (k5, k5_error) = diff.conflicts(base[..], ours[..], ours_short[..], edits[..], found[..], scratch[..])
    if k5_error != ok || k5 != 1usize || found[0usize].start != 1usize || found[0usize].end != 3usize { os.exit(3i32) }

    // 4: similarity.
    let (s1, s1_error) = diff.similarity(base[..], base[..], scratch[..])
    if s1_error != ok || s1 != 1.0f64 { os.exit(4i32) }
    let (s2, s2_error) = diff.similarity(base[..], x[..], scratch[..])
    if s2_error != ok || s2 != 0.0f64 { os.exit(4i32) }
    let (s3, s3_error) = diff.similarity(base[..], want4[..], scratch[..])
    if s3_error != ok || s3 < 0.857f64 || s3 > 0.858f64 { os.exit(4i32) }
    let (s4, s4_error) = diff.similarity(base[..0usize], base[..0usize], scratch[..])
    if s4_error != ok || s4 != 1.0f64 { os.exit(4i32) }
    let (_, s_room) = diff.similarity(base[..], base[..], scratch[..3usize])
    if s_room != diff.TooSmall { os.exit(4i32) }

    try io.print("text diff ok\n")
    ret ok
}
