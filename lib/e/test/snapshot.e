// Snapshot testing with a review-and-accept workflow, in the manner of insta and
// pytest-snapshot: a test renders a value to text and `check` compares it with the
// stored snapshot `<dir>/<name>.snap`. What happens on a missing or different snapshot
// is the `Mode`:
//
//   Ci      never writes; a missing snapshot is `Missing`, a different one `Mismatch`.
//   Review  writes the candidate to `<name>.snap.new` and fails (`Unreviewed` for a new
//           snapshot, `Differs` for a changed one); nothing stored is touched until `accept`.
//   Accept  writes `<name>.snap` and passes (`Created`, `Updated`), removing a pending
//           `.snap.new`.
//
// `mode_from_env` reads NEPER_SNAPSHOT (`ci`, `review`, `accept`); unset, a non-empty CI
// variable means `Ci` and otherwise `Review`. A stored file is a three-line header
// (`---`, `snapshot: <name>`, `---`) and the body; a file without a header is all body.
// Comparison ignores CR bytes and trailing whitespace at the end of the whole text, never
// anything inside it. Text snapshots only: binary values stay out.
//
// `check` fails through `e.test` (`test.fail`), so the record's message carries the
// outcome and a line diff; `assert_text` answers the `Outcome` for callers that want it.
// `check_doc` renders an `e.fmt.pretty` document at a width and snapshots the layout.

use e.fmt.pretty as pretty
use e.fs
use e.mem
use e.os
use e.str
use e.test
use e.text.diff as diff

type Mode = enum u8 { Ci, Review, Accept }
type Outcome = enum u8 { Matched, Created, Updated, Unreviewed, Differs, Missing, Mismatch }
error InvalidName
error TooSmall

fn valid_name(name: str) -> bool {
    if name.len == 0usize || name.len > 120usize { ret false }
    var i = 0usize
    while i < name.len {
        let c = name[i]
        let good = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 45u8 || c == 46u8
        if !good { ret false }
        i += 1usize
    }
    ret name[0] != 46u8
}

// `<dir>/<name>.snap`, or `.snap.new` for the pending candidate.
fn path_of(a: *mem.Arena, dir: str, name: str, pending: bool) -> (str, err) {
    if !valid_name(name) { ret ("", InvalidName) }
    let (b0, be) = str.builder(a, dir.len + name.len + 16usize)
    if be != ok { ret ("", be) }
    var b = b0
    if str.push(&b, dir) != ok { ret ("", TooSmall) }
    if dir.len > 0usize && dir[dir.len - 1usize] != 47u8 && dir[dir.len - 1usize] != 92u8 {
        if str.push(&b, "/") != ok { ret ("", TooSmall) }
    }
    if str.push(&b, name) != ok { ret ("", TooSmall) }
    if str.push(&b, ".snap") != ok { ret ("", TooSmall) }
    if pending {
        if str.push(&b, ".new") != ok { ret ("", TooSmall) }
    }
    ret (str.done(&b), ok)
}

// `s` without CR bytes and without trailing whitespace at its very end.
fn normalized(a: *mem.Arena, s: str) -> (str, err) {
    let (b0, be) = str.builder(a, s.len + 1usize)
    if be != ok { ret ("", be) }
    var b = b0
    var i = 0usize
    while i < s.len {
        if s[i] != 13u8 {
            if str.push_byte(&b, s[i]) != ok { ret ("", TooSmall) }
        }
        i += 1usize
    }
    ret (str.trim_end(str.done(&b)), ok)
}

// The body of a stored file: after the closing `---` of a header, or all of it.
fn body_of(stored: str) -> str {
    if !str.starts_with(stored, "---\n") { ret stored }
    let (at_close, found) = str.find_from(stored, "\n---\n", 3usize)
    if !found { ret stored }
    ret stored[at_close + 5usize..]
}

fn same_text(a: *mem.Arena, x: str, y: str) -> (bool, err) {
    let (nx, ex) = normalized(a, x)
    if ex != ok { ret (false, ex) }
    let (ny, ey) = normalized(a, y)
    if ey != ok { ret (false, ey) }
    ret (str.eq(str.trim_end(body_of(nx)), str.trim_end(body_of(ny))), ok)
}

// The candidate's file text: header, then the body with exactly one trailing newline.
fn file_text(a: *mem.Arena, name: str, actual: str) -> (str, err) {
    let (body, be) = normalized(a, actual)
    if be != ok { ret ("", be) }
    let (b0, ce) = str.builder(a, body.len + name.len + 32usize)
    if ce != ok { ret ("", ce) }
    var b = b0
    if str.push(&b, "---\nsnapshot: ") != ok { ret ("", TooSmall) }
    if str.push(&b, name) != ok { ret ("", TooSmall) }
    if str.push(&b, "\n---\n") != ok { ret ("", TooSmall) }
    if str.push(&b, body) != ok { ret ("", TooSmall) }
    if str.push(&b, "\n") != ok { ret ("", TooSmall) }
    ret (str.done(&b), ok)
}

fn write_text(a: *mem.Arena, dir: str, path: str, text: str) -> err {
    try fs.make_dirs(a, dir)
    ret fs.write_file(a, path, text)
}

fn remove_if_present(a: *mem.Arena, path: str) -> err {
    let (there, ee) = fs.exists(a, path)
    if ee != ok { ret ee }
    if !there { ret ok }
    ret fs.remove_file(a, path)
}

// NEPER_SNAPSHOT, else CI, else review.
fn mode_from_env(a: *mem.Arena) -> Mode {
    let (v, e) = os.env(a, "NEPER_SNAPSHOT")
    if e == ok {
        if str.eq(v, "accept") { ret Mode.Accept }
        if str.eq(v, "ci") { ret Mode.Ci }
        if str.eq(v, "review") { ret Mode.Review }
    }
    let (ci, ce) = os.env(a, "CI")
    if ce == ok && ci.len > 0usize { ret Mode.Ci }
    ret Mode.Review
}

// Compare `actual` with the stored snapshot and act per `mode`; the answer is what
// happened, an error only for storage failures or a bad name.
fn assert_text(a: *mem.Arena, dir: str, name: str, actual: str, mode: Mode) -> (Outcome, err) {
    let (path, pe) = path_of(a, dir, name, false)
    if pe != ok { ret (Outcome.Missing, pe) }
    let (pending, qe) = path_of(a, dir, name, true)
    if qe != ok { ret (Outcome.Missing, qe) }
    let (there, ee) = fs.exists(a, path)
    if ee != ok { ret (Outcome.Missing, ee) }
    var matched = false
    if there {
        let (bytes, re) = fs.read_file(a, path, 16777216usize)
        if re != ok { ret (Outcome.Missing, re) }
        let (same, se) = same_text(a, bytes, actual)
        if se != ok { ret (Outcome.Missing, se) }
        matched = same
    }
    if matched {
        if mode != Mode.Ci {
            let re = remove_if_present(a, pending)
            if re != ok { ret (Outcome.Matched, re) }
        }
        ret (Outcome.Matched, ok)
    }
    if mode == Mode.Ci {
        if there { ret (Outcome.Mismatch, ok) }
        ret (Outcome.Missing, ok)
    }
    let (text, te) = file_text(a, name, actual)
    if te != ok { ret (Outcome.Missing, te) }
    if mode == Mode.Accept {
        let we = write_text(a, dir, path, text)
        if we != ok { ret (Outcome.Missing, we) }
        let re = remove_if_present(a, pending)
        if re != ok { ret (Outcome.Missing, re) }
        if there { ret (Outcome.Updated, ok) }
        ret (Outcome.Created, ok)
    }
    let we = write_text(a, dir, pending, text)
    if we != ok { ret (Outcome.Missing, we) }
    if there { ret (Outcome.Differs, ok) }
    ret (Outcome.Unreviewed, ok)
}

fn count_newlines(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn split_into(s: str, out: []str) -> usize {
    var it = str.lines(s)
    var n = 0usize
    while n < out.len {
        let (line, more) = str.split_next(&it)
        if !more { break }
        out[n] = line
        n += 1usize
    }
    ret n
}

// A line diff of two texts: `- expected`, `+ actual`, two spaces for a line they share.
fn diff_text(a: *mem.Arena, expected: str, actual: str) -> (str, err) {
    let (ex, ee) = normalized(a, expected)
    if ee != ok { ret ("", ee) }
    let (ac, ae) = normalized(a, actual)
    if ae != ok { ret ("", ae) }
    let cap_x = count_newlines(ex) + 1usize
    let cap_y = count_newlines(ac) + 1usize
    let (xs, xe) = mem.alloc[str](a, cap_x)
    if xe != ok { ret ("", xe) }
    let (ys, ye) = mem.alloc[str](a, cap_y)
    if ye != ok { ret ("", ye) }
    let nx = split_into(ex, xs)
    let ny = split_into(ac, ys)
    let (edits, de) = mem.alloc[diff.Edit](a, nx + ny + 1usize)
    if de != ok { ret ("", de) }
    let (scratch, se) = mem.alloc[usize](a, diff.myers_scratch(nx, ny) + 1usize)
    if se != ok { ret ("", se) }
    let (produced, me) = diff.myers(xs[0..nx], ys[0..ny], edits, scratch)
    if me != ok { ret ("", me) }
    let (b0, be) = str.builder(a, ex.len + ac.len + (nx + ny) * 3usize + 16usize)
    if be != ok { ret ("", be) }
    var b = b0
    var i = 0usize
    while i < produced {
        let edit = edits[i]
        var mark = "  "
        if edit.op == diff.Op.Delete { mark = "- " }
        if edit.op == diff.Op.Insert { mark = "+ " }
        if str.push(&b, mark) != ok || str.push(&b, edit.line) != ok || str.push(&b, "\n") != ok { ret ("", TooSmall) }
        i += 1usize
    }
    ret (str.done(&b), ok)
}

fn describe(a: *mem.Arena, dir: str, name: str, outcome: Outcome, actual: str) -> (str, err) {
    let (path, pe) = path_of(a, dir, name, false)
    if pe != ok { ret ("", pe) }
    // The diff is computed before the builder opens: a builder must be the arena's top allocation.
    var text = ""
    if outcome == Outcome.Differs || outcome == Outcome.Mismatch {
        let (bytes, re) = fs.read_file(a, path, 16777216usize)
        if re != ok { ret ("", re) }
        let (diffed, de) = diff_text(a, body_of(bytes), actual)
        if de != ok { ret ("", de) }
        text = diffed
    }
    let (b0, be) = str.builder(a, text.len + path.len * 2usize + 512usize)
    if be != ok { ret ("", be) }
    var b = b0
    if str.push(&b, "snapshot `") != ok || str.push(&b, name) != ok { ret ("", TooSmall) }
    if outcome == Outcome.Unreviewed {
        if str.push(&b, "` is new: wrote ") != ok || str.push(&b, path) != ok || str.push(&b, ".new for review; accept it or run with NEPER_SNAPSHOT=accept") != ok { ret ("", TooSmall) }
    } else if outcome == Outcome.Missing {
        if str.push(&b, "` has no stored value and the mode is ci: ") != ok || str.push(&b, path) != ok || str.push(&b, " must be committed") != ok { ret ("", TooSmall) }
    } else {
        if outcome == Outcome.Differs {
            if str.push(&b, "` changed: wrote ") != ok || str.push(&b, path) != ok || str.push(&b, ".new for review; accept it or run with NEPER_SNAPSHOT=accept") != ok { ret ("", TooSmall) }
        } else {
            if str.push(&b, "` differs from ") != ok || str.push(&b, path) != ok { ret ("", TooSmall) }
        }
        if str.push(&b, "\n") != ok || str.push(&b, text) != ok { ret ("", TooSmall) }
    }
    ret (str.done(&b), ok)
}

// The test assertion: `ok` for a match or an accepted write, `test.Failed` (with the
// message and diff in the running record) otherwise; storage errors come through as is.
fn check(a: *mem.Arena, dir: str, name: str, actual: str, mode: Mode) -> err {
    let (outcome, ae) = assert_text(a, dir, name, actual, mode)
    if ae != ok { ret ae }
    if outcome == Outcome.Matched || outcome == Outcome.Created || outcome == Outcome.Updated { ret ok }
    let (message, me) = describe(a, dir, name, outcome, actual)
    if me != ok { ret me }
    ret test.fail(message)
}

// Snapshot the layout of an `e.fmt.pretty` document at `width`; `capacity` bounds the
// laid-out text and `stack` its frame stack.
fn check_doc(a: *mem.Arena, dir: str, name: str, p: *const pretty.Pool, root: u32, width: usize, capacity: usize, mode: Mode) -> err {
    let (out, oe) = mem.alloc[u8](a, capacity)
    if oe != ok { ret oe }
    let (stack, se) = mem.alloc[pretty.Frame](a, p.used * 2usize + 8usize)
    if se != ok { ret se }
    let (n, le) = pretty.layout(p, root, width, out, stack)
    if le != ok { ret le }
    ret check(a, dir, name, out[0..n], mode)
}

// Promote a pending candidate: `<name>.snap.new` replaces `<name>.snap`.
fn accept(a: *mem.Arena, dir: str, name: str) -> err {
    let (path, pe) = path_of(a, dir, name, false)
    if pe != ok { ret pe }
    let (pending, qe) = path_of(a, dir, name, true)
    if qe != ok { ret qe }
    ret fs.replace(a, pending, path, fs.ReplaceOptions { overwrite: true, durable: false })
}

// Discard a pending candidate; a missing one is not an error.
fn reject(a: *mem.Arena, dir: str, name: str) -> err {
    let (pending, qe) = path_of(a, dir, name, true)
    if qe != ok { ret qe }
    ret remove_if_present(a, pending)
}

// Whether a candidate is waiting for review.
fn has_pending(a: *mem.Arena, dir: str, name: str) -> (bool, err) {
    let (pending, qe) = path_of(a, dir, name, true)
    if qe != ok { ret (false, qe) }
    let (there, ee) = fs.exists(a, pending)
    ret (there, ee)
}
