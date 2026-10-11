// A line editor for REPLs in the manner of readline and reedline, as a state machine with
// no terminal in it: keys go in (decoded from the bytes a raw terminal delivers), the
// buffer, the cursor, the kill and history state change, and `render` answers the bytes
// that redraw the line. A caller owns the terminal (raw mode, reading, writing) and every
// buffer the editor uses; nothing here allocates.
//
// Bindings (emacs): Left/Right/Ctrl-B/Ctrl-F, Home/Ctrl-A, End/Ctrl-E, Alt-B/Alt-F and
// Ctrl-Left/Ctrl-Right by word (alphanumeric runs), Backspace/Ctrl-H, Delete/Ctrl-D (Eof
// on an empty line), Ctrl-K kill to end, Ctrl-U kill to start, Ctrl-W kill the
// whitespace-delimited word before the cursor, Alt-D kill the word after, Alt-Backspace
// kill the word before, Ctrl-Y yank, Ctrl-T transpose, Up/Ctrl-P and Down/Ctrl-N through
// history (the line being edited is kept as a draft), Tab completion through a caller
// callback with cycling on repeated Tab, Enter accepts, Ctrl-C interrupts, Ctrl-L asks
// for a screen clear. Consecutive kills accumulate in the kill buffer, as in readline.
// The cursor moves by UTF-8 code point; a code point is one terminal column (wide and
// combining characters are not measured).
//
// Validators stay caller-side: Enter answers `Accept` and the caller decides whether the
// text is complete (call `insert_newline` to continue a multi-line entry) or ready
// (`submit` records it in the history and clears the line).

use e.str

type KeyKind = enum u8 { Char, Left, Right, Up, Down, Home, End, Backspace, Delete, Enter, Tab, Escape, Unknown }
type Key = struct { kind: KeyKind, ch: u32, ctrl: bool, alt: bool }
type Action = enum u8 { None, Changed, Accept, Interrupt, Eof, Tab, ClearScreen }
type Editor = struct { buf: []u8, len: usize, cursor: usize, draft: []u8, draft_len: usize, kill: []u8, kill_len: usize, last_was_kill: bool, hist_data: []u8, hist_used: usize, hist_starts: []usize, hist_lens: []usize, hist_count: usize, hist_pos: usize, cands: []str, cand_n: usize, cand_i: usize, cand_start: usize, cand_len: usize, cycling: bool }
error TooSmall

// An editor over caller storage: `buf`, `draft` and `kill` hold a line each (the draft and
// kill buffers should be as long as `buf`), `hist_data` the history's bytes with
// `hist_starts`/`hist_lens` its entries, `cands` the completion candidates.
fn editor(buf: []u8, draft: []u8, kill: []u8, hist_data: []u8, hist_starts: []usize, hist_lens: []usize, cands: []str) -> Editor {
    var e: Editor = zero
    e.buf = buf
    e.draft = draft
    e.kill = kill
    e.hist_data = hist_data
    e.hist_starts = hist_starts
    e.hist_lens = hist_lens
    e.cands = cands
    ret e
}

fn text(e: *const Editor) -> str {
    ret e.buf[0..e.len]
}

fn is_continuation(b: u8) -> bool { ret b >= 128u8 && b < 192u8 }

fn is_word_byte(b: u8) -> bool {
    ret (b >= 48u8 && b <= 57u8) || (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8) || b >= 128u8 || b == 95u8
}

fn is_space(b: u8) -> bool { ret b == 32u8 || b == 9u8 || b == 10u8 }

// Offset of the code point boundary before `at` (0 at the start).
fn prev_boundary(e: *const Editor, at: usize) -> usize {
    if at == 0usize { ret 0usize }
    var i = at - 1usize
    while i > 0usize && is_continuation(e.buf[i]) { i -= 1usize }
    ret i
}

fn next_boundary(e: *const Editor, at: usize) -> usize {
    if at >= e.len { ret e.len }
    var i = at + 1usize
    while i < e.len && is_continuation(e.buf[i]) { i += 1usize }
    ret i
}

// Start of the word (alphanumeric run) at or before the cursor, skipping non-word bytes.
fn word_start(e: *const Editor, from: usize) -> usize {
    var i = from
    while i > 0usize && !is_word_byte(e.buf[i - 1usize]) { i -= 1usize }
    while i > 0usize && is_word_byte(e.buf[i - 1usize]) { i -= 1usize }
    ret i
}

fn word_end(e: *const Editor, from: usize) -> usize {
    var i = from
    while i < e.len && !is_word_byte(e.buf[i]) { i += 1usize }
    while i < e.len && is_word_byte(e.buf[i]) { i += 1usize }
    ret i
}

// Insert `bytes` at `at`; false (and nothing changed) when the buffer cannot hold them.
fn insert_at(e: *Editor, at: usize, bytes: str) -> bool {
    if e.len + bytes.len > e.buf.len { ret false }
    var i = e.len
    while i > at {
        i -= 1usize
        e.buf[i + bytes.len] = e.buf[i]
    }
    var j = 0usize
    while j < bytes.len {
        e.buf[at + j] = bytes[j]
        j += 1usize
    }
    e.len += bytes.len
    if e.cursor >= at { e.cursor += bytes.len }
    ret true
}

fn delete_range(e: *Editor, start: usize, end: usize) {
    if end <= start { ret }
    let n = end - start
    var i = start
    while i + n < e.len {
        e.buf[i] = e.buf[i + n]
        i += 1usize
    }
    e.len -= n
    if e.cursor > end {
        e.cursor -= n
    } else if e.cursor > start {
        e.cursor = start
    }
}

// Replace the whole line and put the cursor at the end.
fn set_text(e: *Editor, s: str) -> bool {
    if s.len > e.buf.len { ret false }
    var i = 0usize
    while i < s.len {
        e.buf[i] = s[i]
        i += 1usize
    }
    e.len = s.len
    e.cursor = s.len
    ret true
}

fn clear(e: *Editor) {
    e.len = 0usize
    e.cursor = 0usize
    e.hist_pos = e.hist_count
    e.cycling = false
}

// Move [start, end) into the kill buffer, appending (forward kills) or prepending
// (backward kills) to the previous kill when the last command was a kill too.
fn kill_range(e: *Editor, start: usize, end: usize, forward: bool) {
    if end <= start { ret }
    let n = end - start
    if e.last_was_kill {
        if e.kill_len + n > e.kill.len { ret }
        if forward {
            var i = 0usize
            while i < n {
                e.kill[e.kill_len + i] = e.buf[start + i]
                i += 1usize
            }
        } else {
            var k = e.kill_len
            while k > 0usize {
                k -= 1usize
                e.kill[k + n] = e.kill[k]
            }
            var j = 0usize
            while j < n {
                e.kill[j] = e.buf[start + j]
                j += 1usize
            }
        }
        e.kill_len += n
    } else {
        if n > e.kill.len { ret }
        var m = 0usize
        while m < n {
            e.kill[m] = e.buf[start + m]
            m += 1usize
        }
        e.kill_len = n
    }
    delete_range(e, start, end)
}

fn history_add(e: *Editor, line: str) {
    if line.len == 0usize || line.len > e.hist_data.len || e.hist_starts.len == 0usize { ret }
    if e.hist_count > 0usize {
        let last = e.hist_count - 1usize
        let prev = e.hist_data[e.hist_starts[last]..e.hist_starts[last] + e.hist_lens[last]]
        if prev.len == line.len {
            var same = true
            var i = 0usize
            while i < line.len {
                if prev[i] != line[i] { same = false }
                i += 1usize
            }
            if same { ret }
        }
    }
    // Evict the oldest entries until the new one fits by count and bytes.
    while e.hist_count >= e.hist_starts.len || e.hist_used + line.len > e.hist_data.len {
        var k = 0usize
        let drop = e.hist_lens[0]
        var i = 0usize
        while i + drop < e.hist_used {
            e.hist_data[i] = e.hist_data[i + drop]
            i += 1usize
        }
        e.hist_used -= drop
        while k + 1usize < e.hist_count {
            e.hist_starts[k] = e.hist_starts[k + 1usize] - drop
            e.hist_lens[k] = e.hist_lens[k + 1usize]
            k += 1usize
        }
        e.hist_count -= 1usize
    }
    var j = 0usize
    while j < line.len {
        e.hist_data[e.hist_used + j] = line[j]
        j += 1usize
    }
    e.hist_starts[e.hist_count] = e.hist_used
    e.hist_lens[e.hist_count] = line.len
    e.hist_used += line.len
    e.hist_count += 1usize
    e.hist_pos = e.hist_count
}

fn history_entry(e: *const Editor, index: usize) -> str {
    if index >= e.hist_count { ret "" }
    ret e.hist_data[e.hist_starts[index]..e.hist_starts[index] + e.hist_lens[index]]
}

// Record the line in the history and clear the editor; the returned text stays valid
// until the next edit.
fn submit(e: *Editor) -> str {
    let line = text(e)
    history_add(e, line)
    let kept = e.buf[0..e.len]
    e.len = 0usize
    e.cursor = 0usize
    e.hist_pos = e.hist_count
    e.cycling = false
    ret kept
}

fn insert_newline(e: *Editor) -> bool {
    ret insert_at(e, e.cursor, "\n")
}

fn history_prev(e: *Editor) -> bool {
    if e.hist_count == 0usize || e.hist_pos == 0usize { ret false }
    if e.hist_pos == e.hist_count {
        var i = 0usize
        while i < e.len {
            e.draft[i] = e.buf[i]
            i += 1usize
        }
        e.draft_len = e.len
    }
    e.hist_pos -= 1usize
    ret set_text(e, history_entry(e, e.hist_pos))
}

fn history_next(e: *Editor) -> bool {
    if e.hist_pos >= e.hist_count { ret false }
    e.hist_pos += 1usize
    if e.hist_pos == e.hist_count { ret set_text(e, e.draft[0..e.draft_len]) }
    ret set_text(e, history_entry(e, e.hist_pos))
}

// The suffix of the newest history entry that starts with the line and is longer than it
// (fish-style autosuggestion); empty when there is none or the line is empty.
fn history_hint(e: *const Editor) -> str {
    if e.len == 0usize { ret "" }
    var i = e.hist_count
    while i > 0usize {
        i -= 1usize
        let entry = history_entry(e, i)
        if entry.len > e.len {
            var matches = true
            var k = 0usize
            while k < e.len {
                if entry[k] != e.buf[k] { matches = false }
                k += 1usize
            }
            if matches { ret entry[e.len..] }
        }
    }
    ret ""
}

fn accept_hint(e: *Editor, hint: str) -> bool {
    if e.cursor != e.len { ret false }
    ret insert_at(e, e.len, hint)
}

// Start of the whitespace-delimited word that ends at the cursor.
fn token_start(e: *const Editor) -> usize {
    var i = e.cursor
    while i > 0usize && !is_space(e.buf[i - 1usize]) { i -= 1usize }
    ret i
}

fn replace_range(e: *Editor, start: usize, end: usize, replacement: str) -> bool {
    if e.len - (end - start) + replacement.len > e.buf.len { ret false }
    delete_range(e, start, end)
    e.cursor = start
    ret insert_at(e, start, replacement)
}

// Complete the token before the cursor. `complete` fills `e.cands` with candidates for
// the token and answers how many (borrowed text, valid while the editor cycles).
fn tab[Ctx: type](e: *Editor, ctx: *Ctx, complete: fn(*Ctx, str, []str) -> usize) -> Action {
    if e.cycling && e.cand_n > 0usize {
        e.cand_i = (e.cand_i + 1usize) % e.cand_n
        let c = e.cands[e.cand_i]
        if !replace_range(e, e.cand_start, e.cand_start + e.cand_len, c) { ret .None }
        e.cand_len = c.len
        ret .Changed
    }
    let start = token_start(e)
    let word = e.buf[start..e.cursor]
    var n = complete(ctx, word, e.cands)
    if n > e.cands.len { n = e.cands.len }
    if n == 0usize { ret .None }
    // The longest common prefix of the candidates (on a code point boundary).
    var common = e.cands[0].len
    var i = 1usize
    while i < n {
        var k = 0usize
        let other = e.cands[i]
        while k < common && k < other.len && other[k] == e.cands[0][k] { k += 1usize }
        common = k
        i += 1usize
    }
    while common > 0usize && common < e.cands[0].len && is_continuation(e.cands[0][common]) { common -= 1usize }
    e.cand_start = start
    e.cand_n = n
    if common > word.len {
        let prefix = e.cands[0][0..common]
        if !replace_range(e, start, e.cursor, prefix) { ret .None }
        if n > 1usize {
            e.cycling = true
            e.cand_i = n - 1usize
            e.cand_len = common
        }
        ret .Changed
    }
    if n == 1usize {
        // Nothing to add unless the candidate differs from what is typed.
        if e.cands[0].len == word.len { ret .None }
    }
    e.cycling = true
    e.cand_i = 0usize
    let first = e.cands[0]
    if !replace_range(e, start, e.cursor, first) { ret .None }
    e.cand_len = first.len
    ret .Changed
}

fn transpose(e: *Editor) -> bool {
    if e.len < 2usize || e.cursor == 0usize { ret false }
    var at = e.cursor
    if at == e.len { at = prev_boundary(e, at) }
    let left_start = prev_boundary(e, at)
    let right_end = next_boundary(e, at)
    if right_end <= at || at <= left_start { ret false }
    // Rotate [left_start, right_end) so the two code points swap.
    let left_len = at - left_start
    let right_len = right_end - at
    var tmp: [8]u8 = zero
    if left_len > 8usize || right_len > 8usize { ret false }
    var i = 0usize
    while i < left_len {
        tmp[i] = e.buf[left_start + i]
        i += 1usize
    }
    var j = 0usize
    while j < right_len {
        e.buf[left_start + j] = e.buf[at + j]
        j += 1usize
    }
    var k = 0usize
    while k < left_len {
        e.buf[left_start + right_len + k] = tmp[k]
        k += 1usize
    }
    e.cursor = right_end
    ret true
}

fn utf8_encode(cp: u32, out: []u8) -> usize {
    if cp < 128u32 {
        out[0] = u8(cp)
        ret 1usize
    }
    if cp < 2048u32 {
        out[0] = 192u8 | u8(cp >> 6u32)
        out[1] = 128u8 | u8(cp & 63u32)
        ret 2usize
    }
    if cp < 65536u32 {
        out[0] = 224u8 | u8(cp >> 12u32)
        out[1] = 128u8 | u8((cp >> 6u32) & 63u32)
        out[2] = 128u8 | u8(cp & 63u32)
        ret 3usize
    }
    out[0] = 240u8 | u8(cp >> 18u32)
    out[1] = 128u8 | u8((cp >> 12u32) & 63u32)
    out[2] = 128u8 | u8((cp >> 6u32) & 63u32)
    out[3] = 128u8 | u8(cp & 63u32)
    ret 4usize
}

// Apply one key; `Tab` is answered for the caller to complete (`tab`), the rest is done.
fn handle(e: *Editor, key: Key) -> Action {
    let was_kill = e.last_was_kill
    e.last_was_kill = false
    if key.kind != .Tab { e.cycling = false }
    if key.kind == .Tab { ret .Tab }
    if key.kind == .Enter { ret .Accept }
    if key.kind == .Left {
        if key.ctrl || key.alt { e.cursor = word_start(e, e.cursor) } else { e.cursor = prev_boundary(e, e.cursor) }
        ret .Changed
    }
    if key.kind == .Right {
        if key.ctrl || key.alt { e.cursor = word_end(e, e.cursor) } else { e.cursor = next_boundary(e, e.cursor) }
        ret .Changed
    }
    if key.kind == .Home {
        e.cursor = 0usize
        ret .Changed
    }
    if key.kind == .End {
        e.cursor = e.len
        ret .Changed
    }
    if key.kind == .Up {
        if history_prev(e) { ret .Changed }
        ret .None
    }
    if key.kind == .Down {
        if history_next(e) { ret .Changed }
        ret .None
    }
    if key.kind == .Backspace {
        if key.alt {
            e.last_was_kill = was_kill
            kill_range(e, word_start(e, e.cursor), e.cursor, false)
            e.last_was_kill = true
            ret .Changed
        }
        if e.cursor == 0usize { ret .None }
        delete_range(e, prev_boundary(e, e.cursor), e.cursor)
        ret .Changed
    }
    if key.kind == .Delete {
        if e.cursor >= e.len { ret .None }
        delete_range(e, e.cursor, next_boundary(e, e.cursor))
        ret .Changed
    }
    if key.kind == .Char {
        if key.ctrl {
            let c = key.ch
            if c == 97u32 {
                e.cursor = 0usize
                ret .Changed
            }
            if c == 101u32 {
                e.cursor = e.len
                ret .Changed
            }
            if c == 98u32 {
                e.cursor = prev_boundary(e, e.cursor)
                ret .Changed
            }
            if c == 102u32 {
                e.cursor = next_boundary(e, e.cursor)
                ret .Changed
            }
            if c == 100u32 {
                if e.len == 0usize { ret .Eof }
                if e.cursor < e.len { delete_range(e, e.cursor, next_boundary(e, e.cursor)) }
                ret .Changed
            }
            if c == 104u32 {
                if e.cursor == 0usize { ret .None }
                delete_range(e, prev_boundary(e, e.cursor), e.cursor)
                ret .Changed
            }
            if c == 107u32 {
                e.last_was_kill = was_kill
                kill_range(e, e.cursor, e.len, true)
                e.last_was_kill = true
                ret .Changed
            }
            if c == 117u32 {
                e.last_was_kill = was_kill
                kill_range(e, 0usize, e.cursor, false)
                e.last_was_kill = true
                ret .Changed
            }
            if c == 119u32 {
                var s = e.cursor
                while s > 0usize && is_space(e.buf[s - 1usize]) { s -= 1usize }
                while s > 0usize && !is_space(e.buf[s - 1usize]) { s -= 1usize }
                e.last_was_kill = was_kill
                kill_range(e, s, e.cursor, false)
                e.last_was_kill = true
                ret .Changed
            }
            if c == 121u32 {
                var yanked = true
                if e.kill_len > 0usize { yanked = insert_at(e, e.cursor, e.kill[0..e.kill_len]) }
                if yanked { ret .Changed }
                ret .None
            }
            if c == 116u32 {
                if transpose(e) { ret .Changed }
                ret .None
            }
            if c == 112u32 {
                if history_prev(e) { ret .Changed }
                ret .None
            }
            if c == 110u32 {
                if history_next(e) { ret .Changed }
                ret .None
            }
            if c == 99u32 { ret .Interrupt }
            if c == 108u32 { ret .ClearScreen }
            ret .None
        }
        if key.alt {
            let c = key.ch
            if c == 98u32 {
                e.cursor = word_start(e, e.cursor)
                ret .Changed
            }
            if c == 102u32 {
                e.cursor = word_end(e, e.cursor)
                ret .Changed
            }
            if c == 100u32 {
                e.last_was_kill = was_kill
                kill_range(e, e.cursor, word_end(e, e.cursor), true)
                e.last_was_kill = true
                ret .Changed
            }
            ret .None
        }
        var enc: [4]u8 = zero
        let n = utf8_encode(key.ch, enc[0..])
        if insert_at(e, e.cursor, enc[0..n]) { ret .Changed }
        ret .None
    }
    ret .None
}

fn plain(kind: KeyKind) -> Key {
    ret Key { kind: kind, ch: 0u32, ctrl: false, alt: false }
}

// Decode one key from `bytes` at `at`: the key and how many bytes it used (0 when the
// bytes end inside a sequence). Understands UTF-8 text, Ctrl letters, CSI and SS3 arrows
// and editing keys with the xterm modifier parameter, and Alt as an ESC prefix.
fn decode(bytes: []const u8, at: usize) -> (Key, usize) {
    if at >= bytes.len { ret (plain(.Unknown), 0usize) }
    let b = bytes[at]
    if b == 27u8 {
        if at + 1usize >= bytes.len { ret (plain(.Escape), 1usize) }
        let n = bytes[at + 1usize]
        if n == 91u8 || n == 79u8 {
            var i = at + 2usize
            var p0 = 0u32
            var p1 = 0u32
            var field = 0usize
            while i < bytes.len && ((bytes[i] >= 48u8 && bytes[i] <= 57u8) || bytes[i] == 59u8) {
                if bytes[i] == 59u8 {
                    field += 1usize
                } else if field == 0usize {
                    p0 = p0 * 10u32 + u32(bytes[i] - 48u8)
                } else {
                    p1 = p1 * 10u32 + u32(bytes[i] - 48u8)
                }
                i += 1usize
            }
            if i >= bytes.len { ret (plain(.Unknown), 0usize) }
            let last_byte = bytes[i]
            let used = i + 1usize - at
            var k = plain(.Unknown)
            if last_byte == 65u8 { k = plain(.Up) }
            if last_byte == 66u8 { k = plain(.Down) }
            if last_byte == 67u8 { k = plain(.Right) }
            if last_byte == 68u8 { k = plain(.Left) }
            if last_byte == 72u8 { k = plain(.Home) }
            if last_byte == 70u8 { k = plain(.End) }
            if last_byte == 126u8 {
                if p0 == 1u32 || p0 == 7u32 { k = plain(.Home) }
                if p0 == 4u32 || p0 == 8u32 { k = plain(.End) }
                if p0 == 3u32 { k = plain(.Delete) }
            }
            // xterm modifiers: 3 alt, 5 ctrl, 7 ctrl+alt (parameter minus one is a bit set).
            let mods = p1
            if mods >= 2u32 {
                let bits = mods - 1u32
                if (bits & 2u32) != 0u32 { k.alt = true }
                if (bits & 4u32) != 0u32 { k.ctrl = true }
            }
            ret (k, used)
        }
        // ESC then a key: Alt-modified.
        if n == 127u8 || n == 8u8 {
            var k = plain(.Backspace)
            k.alt = true
            ret (k, 2usize)
        }
        let (inner, used) = decode(bytes, at + 1usize)
        if used == 0usize { ret (plain(.Unknown), 0usize) }
        var k = inner
        k.alt = true
        ret (k, used + 1usize)
    }
    if b == 13u8 || b == 10u8 { ret (plain(.Enter), 1usize) }
    if b == 9u8 { ret (plain(.Tab), 1usize) }
    if b == 127u8 { ret (plain(.Backspace), 1usize) }
    if b >= 1u8 && b <= 26u8 {
        var k = plain(.Char)
        k.ch = u32(b) + 96u32
        k.ctrl = true
        ret (k, 1usize)
    }
    var k = plain(.Char)
    if b < 128u8 {
        k.ch = u32(b)
        ret (k, 1usize)
    }
    var need = 0usize
    var cp = 0u32
    if b >= 240u8 {
        need = 3usize
        cp = u32(b & 7u8)
    } else if b >= 224u8 {
        need = 2usize
        cp = u32(b & 15u8)
    } else if b >= 192u8 {
        need = 1usize
        cp = u32(b & 31u8)
    } else {
        ret (plain(.Unknown), 1usize)
    }
    if at + need >= bytes.len { ret (plain(.Unknown), 0usize) }
    var i = 1usize
    while i <= need {
        cp = (cp << 6u32) | u32(bytes[at + i] & 63u8)
        i += 1usize
    }
    k.ch = cp
    ret (k, need + 1usize)
}

// Feed raw terminal bytes: decode and handle each key, completing on Tab with `complete`.
// Stops after the key that answers `Accept`, `Interrupt`, `Eof` or `ClearScreen`; answers
// the bytes consumed and the last non-`None` action (`Changed` when only edits happened).
fn feed[Ctx: type](e: *Editor, bytes: []const u8, ctx: *Ctx, complete: fn(*Ctx, str, []str) -> usize) -> (usize, Action) {
    var at = 0usize
    var last = Action.None
    while at < bytes.len {
        let (key, used) = decode(bytes, at)
        if used == 0usize { break }
        at += used
        var action = handle(e, key)
        if action == .Tab {
            e.last_was_kill = false
            action = tab[Ctx](e, ctx, complete)
        }
        if action == .Accept || action == .Interrupt || action == .Eof || action == .ClearScreen { ret (at, action) }
        if action == .Changed { last = .Changed }
    }
    ret (at, last)
}

fn push_cols(b: *str.Builder, n: usize) -> err {
    try str.push(b, "\x1b[")
    try str.push_usize(b, n)
    ret str.push(b, "C")
}

// The bytes that redraw the line: carriage return, the prompt, the text, the hint dimmed,
// erase to end of line, then back to the cursor column (`prompt_cols` is the prompt's width
// in columns).
fn render(b: *str.Builder, e: *const Editor, prompt: str, prompt_cols: usize, hint: str) -> err {
    try str.push(b, "\r")
    try str.push(b, prompt)
    try str.push(b, text(e))
    if hint.len > 0usize {
        try str.push(b, "\x1b[2m")
        try str.push(b, hint)
        try str.push(b, "\x1b[0m")
    }
    try str.push(b, "\x1b[K")
    var cols = prompt_cols
    var i = 0usize
    while i < e.cursor {
        if !is_continuation(e.buf[i]) { cols += 1usize }
        i += 1usize
    }
    try str.push(b, "\r")
    if cols > 0usize { try push_cols(b, cols) }
    ret ok
}
