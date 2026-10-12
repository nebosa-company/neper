// Code editor model and engine (D3201, L065 P7-01/03/04/07/09/10 core): the part of the editor that needs no widget.
// One `Editor` owns a UTF-8 document in a gap buffer with an incremental line index, a normalised multi-range
// selection, undo/redo stacks of inverse edit batches, a line-state cache for tokenizer-driven highlighting, an
// indentation policy and literal search. Every content change goes through `commit`: a batch of sorted,
// non-overlapping edits against one revision, validated (bounds, UTF-8 boundaries, well-formed text, capacities)
// and its history reserved BEFORE anything is mutated, so a refused edit leaves content, selections, history and
// saved state exactly as they were. Positions are UTF-8 byte offsets; columns are counted in code points and
// caret motion steps over combining marks and ZWJ sequences. Storage is one arena allocation made by `open`.
// Not here yet: the widget, IME/accessibility, bidi, wrapping/virtual rows, decorations, folding, regex search,
// completion, diagnostics, LSP and the remaining language packs (see docs/code-editor-plan.md).

use e.mem

type Range = struct { anchor: usize, head: usize, goal: usize }
type Edit = struct { at: usize, remove: usize, text_off: usize, text_len: usize }
type Batch = struct { edit_first: usize, edit_n: usize, text_first: usize, text_len: usize }
type Entry = struct { batch_first: usize, batch_n: usize, sel_first: usize, sel_n: usize, id_before: u64, kind: u32 }
type Stack = struct { entries: []Entry, nent: usize, batches: []Batch, nbat: usize, edits: []Edit, ned: usize, text: []u8, ntext: usize, sels: []Range, nsel: usize }
type Token = struct { start: usize, end: usize, kind: u32 }
type Language = struct { keywords: str, types: str, line_comment: str, block_open: str, block_close: str, quotes: str, multiline_quotes: str }
type SearchOpts = struct { case_sensitive: bool, whole_word: bool }
type Editor = struct {
    buf: []u8, gap_start: usize, gap_end: usize,
    lines: []usize, nlines: usize, line_state: []u8, first_dirty: usize,
    sels: []Range, nsel: usize, primary: usize,
    undo: Stack, redo: Stack,
    content_id: u64, next_id: u64, saved_id: u64, revision: u64, can_merge: bool, merge_kind: u32,
    lang: Language, use_tabs: bool, tab_width: usize, indent_unit: usize,
    scratch_edits: []Edit, scratch_text: []u8, scratch_sels: []Range
}
error Invalid
error TooLarge
error TooManyLines
error TooManySelections
error NotBoundary
error BadEdits

const NO_GOAL: usize = 18446744073709551615usize
const NO_DIRTY: usize = 18446744073709551615usize
const KIND_OTHER: u32 = 0u32
const KIND_TYPING: u32 = 1u32
const KIND_DELETE_BACK: u32 = 2u32
const KIND_DELETE_FORWARD: u32 = 3u32
const TOK_KEYWORD: u32 = 1u32
const TOK_TYPE: u32 = 2u32
const TOK_IDENT: u32 = 3u32
const TOK_NUMBER: u32 = 4u32
const TOK_STRING: u32 = 5u32
const TOK_COMMENT: u32 = 6u32
const TOK_OPERATOR: u32 = 7u32
const TOK_PUNCT: u32 = 8u32
const MOVE_LEFT: u32 = 1u32
const MOVE_RIGHT: u32 = 2u32
const MOVE_UP: u32 = 3u32
const MOVE_DOWN: u32 = 4u32
const MOVE_LINE_START: u32 = 5u32
const MOVE_LINE_END: u32 = 6u32
const MOVE_DOC_START: u32 = 7u32
const MOVE_DOC_END: u32 = 8u32
const MOVE_WORD_LEFT: u32 = 9u32
const MOVE_WORD_RIGHT: u32 = 10u32

fn min_of(x: usize, y: usize) -> usize {
    if x < y { ret x }
    ret y
}

fn max_of(x: usize, y: usize) -> usize {
    if x > y { ret x }
    ret y
}

// ---- languages --------------------------------------------------------------------------------------------

fn lang_plain() -> Language {
    ret Language { keywords: "", types: "", line_comment: "", block_open: "", block_close: "", quotes: "", multiline_quotes: "" }
}

// Neper: `//` comments, the keywords of grammar revision 3 and the builtin type names.
fn lang_neper() -> Language {
    ret Language {
        keywords: " as break case const continue default defer else enum error extern false fn for if in let nil nocheck ok own resource ret shared struct switch true try type undef union unreachable use var when while zero ",
        types: " bool u8 u16 u32 u64 i8 i16 i32 i64 usize isize f32 f64 str err ",
        line_comment: "//", block_open: "", block_close: "", quotes: "\"'", multiline_quotes: "" }
}

fn lang_javascript() -> Language {
    ret Language {
        keywords: " async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof var void while with yield ",
        types: "",
        line_comment: "//", block_open: "/*", block_close: "*/", quotes: "\"'`", multiline_quotes: "`" }
}

fn lang_python() -> Language {
    ret Language {
        keywords: " and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield ",
        types: "",
        line_comment: "#", block_open: "", block_close: "", quotes: "\"'", multiline_quotes: "" }
}

fn same_bytes(x: []const u8, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// Language for a file name suffix without the dot (ASCII case-insensitive); unknown suffixes are plain text.
fn lang_for_suffix(suffix: str) -> Language {
    var lower: [16]u8 = zero
    if suffix.len > 16usize { ret lang_plain() }
    var i = 0usize
    while i < suffix.len {
        var c = suffix[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        lower[i] = c
        i += 1usize
    }
    let s = lower[0usize..suffix.len]
    if same_bytes(s, "e") { ret lang_neper() }
    if same_bytes(s, "js") || same_bytes(s, "mjs") || same_bytes(s, "cjs") { ret lang_javascript() }
    if same_bytes(s, "py") || same_bytes(s, "pyw") { ret lang_python() }
    ret lang_plain()
}

// ---- document ---------------------------------------------------------------------------------------------

fn len(e: *const Editor) -> usize { ret e.buf.len - (e.gap_end - e.gap_start) }

fn byte_at(e: *const Editor, i: usize) -> u8 {
    if i < e.gap_start { ret e.buf[i] }
    ret e.buf[i + (e.gap_end - e.gap_start)]
}

fn move_gap(e: *Editor, pos: usize) {
    if pos < e.gap_start {
        let n = e.gap_start - pos
        var i = n
        while i > 0usize {
            i -= 1usize
            e.buf[e.gap_end - n + i] = e.buf[pos + i]
        }
        e.gap_start = pos
        e.gap_end -= n
    } else if pos > e.gap_start {
        let n = pos - e.gap_start
        var i = 0usize
        while i < n {
            e.buf[e.gap_start + i] = e.buf[e.gap_end + i]
            i += 1usize
        }
        e.gap_start += n
        e.gap_end += n
    }
}

fn is_boundary(e: *const Editor, pos: usize) -> bool {
    if pos == 0usize || pos == len(e) { ret true }
    if pos > len(e) { ret false }
    ret (byte_at(e, pos) & 192u8) != 128u8
}

// Copy [from, to) into dst; returns the bytes copied (clipped to dst).
fn copy_text(e: *const Editor, from: usize, to: usize, dst: []u8) -> usize {
    let hi = min_of(to, len(e))
    var n = 0usize
    var i = from
    while i < hi && n < dst.len {
        dst[n] = byte_at(e, i)
        n += 1usize
        i += 1usize
    }
    ret n
}

// Structural UTF-8 check of text[off .. off+n): lead/continuation shapes, scalar range, no overlongs or surrogates.
fn valid_utf8(text: []const u8, off: usize, n: usize) -> bool {
    var i = off
    let end = off + n
    while i < end {
        let b = u32(text[i])
        if b < 128u32 {
            i += 1usize
        } else {
            var need = 0usize
            var floor = 0u32
            var cp = 0u32
            if b >= 194u32 && b <= 223u32 {
                need = 1usize
                cp = b & 31u32
                floor = 128u32
            } else if b >= 224u32 && b <= 239u32 {
                need = 2usize
                cp = b & 15u32
                floor = 2048u32
            } else if b >= 240u32 && b <= 244u32 {
                need = 3usize
                cp = b & 7u32
                floor = 65536u32
            } else {
                ret false
            }
            if i + need >= end { ret false }
            var k = 1usize
            while k <= need {
                let c = u32(text[i + k])
                if (c & 192u32) != 128u32 { ret false }
                cp = (cp << 6u32) | (c & 63u32)
                k += 1usize
            }
            if cp < floor || cp > 1114111u32 || (cp >= 55296u32 && cp <= 57343u32) { ret false }
            i += need + 1usize
        }
    }
    ret true
}

// The scalar at pos and its byte length (length 0 past the end).
fn decode_at(e: *const Editor, pos: usize) -> (u32, usize) {
    if pos >= len(e) { ret (0u32, 0usize) }
    let b = u32(byte_at(e, pos))
    var need = 0usize
    var cp = b
    if b >= 192u32 && b <= 223u32 {
        need = 1usize
        cp = b & 31u32
    } else if b >= 224u32 && b <= 239u32 {
        need = 2usize
        cp = b & 15u32
    } else if b >= 240u32 && b <= 247u32 {
        need = 3usize
        cp = b & 7u32
    }
    if need == 0usize || pos + need >= len(e) { ret (b, 1usize) }
    var k = 1usize
    while k <= need {
        cp = (cp << 6u32) | (u32(byte_at(e, pos + k)) & 63u32)
        k += 1usize
    }
    ret (cp, need + 1usize)
}

fn is_extender(cp: u32) -> bool {
    if cp >= 768u32 && cp <= 879u32 { ret true }
    if cp >= 8400u32 && cp <= 8447u32 { ret true }
    if cp >= 65024u32 && cp <= 65039u32 { ret true }
    if cp >= 127995u32 && cp <= 127999u32 { ret true }
    ret cp == 8205u32
}

// The caret stop after pos: one scalar plus following combining marks, variation selectors and ZWJ-joined scalars.
fn next_boundary(e: *const Editor, pos: usize) -> usize {
    let (c0, n0) = decode_at(e, pos)
    if n0 == 0usize { ret pos }
    var p = pos + n0
    var prev = c0
    var going = true
    while going && p < len(e) {
        let (c, n) = decode_at(e, p)
        if prev == 8205u32 || is_extender(c) {
            p += n
            prev = c
        } else {
            going = false
        }
    }
    ret p
}

fn prev_cp_start(e: *const Editor, pos: usize) -> usize {
    if pos == 0usize { ret 0usize }
    var p = pos - 1usize
    var guard = 0usize
    while p > 0usize && (byte_at(e, p) & 192u8) == 128u8 && guard < 3usize {
        p -= 1usize
        guard += 1usize
    }
    ret p
}

fn prev_boundary(e: *const Editor, pos: usize) -> usize {
    var p = prev_cp_start(e, pos)
    var going = true
    while going && p > 0usize {
        let (c, _) = decode_at(e, p)
        let before = prev_cp_start(e, p)
        let (bc, _) = decode_at(e, before)
        if is_extender(c) || bc == 8205u32 {
            p = before
        } else {
            going = false
        }
    }
    ret p
}

// ---- line index and highlight-state cache ---------------------------------------------------------------

fn line_count(e: *const Editor) -> usize { ret e.nlines }
fn line_start(e: *const Editor, i: usize) -> usize { ret e.lines[i] }

fn line_end(e: *const Editor, i: usize) -> usize {
    if i + 1usize < e.nlines { ret e.lines[i + 1usize] - 1usize }
    ret len(e)
}

// The line holding byte offset pos (the last line for pos == len).
fn line_of(e: *const Editor, pos: usize) -> usize {
    var lo = 0usize
    var hi = e.nlines
    while hi - lo > 1usize {
        let mid = (lo + hi) / 2usize
        if e.lines[mid] <= pos { lo = mid } else { hi = mid }
    }
    ret lo
}

// Code points between the line's start and pos.
fn column_of(e: *const Editor, pos: usize) -> usize {
    var p = line_start(e, line_of(e, pos))
    var c = 0usize
    while p < pos {
        let (_, n) = decode_at(e, p)
        if n == 0usize { ret c }
        p += n
        c += 1usize
    }
    ret c
}

// Byte offset of column `col` (code points) on line `ln`, clamped to the line's end.
fn pos_at_column(e: *const Editor, ln: usize, col: usize) -> usize {
    var p = line_start(e, ln)
    let end = line_end(e, ln)
    var c = 0usize
    while c < col && p < end {
        let (_, n) = decode_at(e, p)
        if n == 0usize { ret p }
        p += n
        c += 1usize
    }
    ret min_of(p, end)
}

// Line index and highlight state after replacing [at, at+rem) by n bytes of src from `off`. Lines created or
// touched are marked dirty; later lines keep their cached start state until `ensure_states` proves them stale.
fn lines_splice(e: *Editor, at: usize, rem: usize, src: []const u8, off: usize, n: usize) {
    let ln = line_of(e, at)
    let first = ln + 1usize
    var k = 0usize
    while first + k < e.nlines && e.lines[first + k] <= at + rem { k += 1usize }
    var nl = 0usize
    var i = 0usize
    while i < n {
        if src[off + i] == 10u8 { nl += 1usize }
        i += 1usize
    }
    let tail = e.nlines - (first + k)
    if nl > k {
        let d = nl - k
        var j = tail
        while j > 0usize {
            j -= 1usize
            e.lines[first + k + j + d] = e.lines[first + k + j] + n - rem
            e.line_state[first + k + j + d] = e.line_state[first + k + j]
        }
    } else {
        let d = k - nl
        var j = 0usize
        while j < tail {
            e.lines[first + k + j - d] = e.lines[first + k + j] + n - rem
            e.line_state[first + k + j - d] = e.line_state[first + k + j]
            j += 1usize
        }
    }
    var m = 0usize
    var q = 0usize
    while q < n {
        if src[off + q] == 10u8 {
            e.lines[first + m] = at + q + 1usize
            e.line_state[first + m] = 128u8
            m += 1usize
        }
        q += 1usize
    }
    e.nlines = e.nlines - k + nl
    e.line_state[ln] = e.line_state[ln] | 128u8
    if ln < e.first_dirty { e.first_dirty = ln }
}

// ---- tokenizer --------------------------------------------------------------------------------------------

fn is_word_byte(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c >= 128u8
}

fn has_word(set: str, e: *const Editor, from: usize, to: usize) -> bool {
    let n = to - from
    if n == 0usize || set.len < n + 2usize { ret false }
    var i = 0usize
    while i + n + 2usize <= set.len {
        if set[i] == 32u8 && set[i + n + 1usize] == 32u8 {
            var k = 0usize
            var good = true
            while k < n && good {
                if set[i + 1usize + k] != byte_at(e, from + k) { good = false }
                k += 1usize
            }
            if good { ret true }
        }
        i += 1usize
    }
    ret false
}

fn at_prefix(e: *const Editor, p: usize, end: usize, s: str) -> bool {
    if s.len == 0usize || p + s.len > end { ret false }
    var i = 0usize
    while i < s.len {
        if byte_at(e, p + i) != s[i] { ret false }
        i += 1usize
    }
    ret true
}

fn quote_index(set: str, c: u8) -> usize {
    var i = 0usize
    while i < set.len {
        if set[i] == c { ret i }
        i += 1usize
    }
    ret NO_GOAL
}

// Scan line `ln` from `state_in` (0 normal, 1 inside a block comment, 2+i inside the i-th multiline quote).
// Tokens go to `out` while there is room; returns (tokens written, state at the end of the line).
fn scan_line(e: *const Editor, ln: usize, state_in: u8, out: []Token) -> (usize, u8) {
    let end = line_end(e, ln)
    var p = line_start(e, ln)
    var nt = 0usize
    var st = state_in
    let lg = e.lang
    while p < end {
        let t0 = p
        if st == 1u8 {
            var closed = false
            while p < end && !closed {
                if at_prefix(e, p, end, lg.block_close) {
                    p += lg.block_close.len
                    closed = true
                } else {
                    p += 1usize
                }
            }
            if closed { st = 0u8 }
            if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_COMMENT } }
            nt += 1usize
        } else if st >= 2u8 {
            let q = lg.multiline_quotes[usize(st) - 2usize]
            var closed = false
            while p < end && !closed {
                let c = byte_at(e, p)
                if c == 92u8 && p + 1usize < end {
                    p += 2usize
                } else if c == q {
                    p += 1usize
                    closed = true
                } else {
                    p += 1usize
                }
            }
            if closed { st = 0u8 }
            if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_STRING } }
            nt += 1usize
        } else {
            let c = byte_at(e, p)
            if c == 32u8 || c == 9u8 || c == 13u8 {
                p += 1usize
            } else if at_prefix(e, p, end, lg.line_comment) {
                p = end
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_COMMENT } }
                nt += 1usize
            } else if at_prefix(e, p, end, lg.block_open) {
                p += lg.block_open.len
                var closed = false
                while p < end && !closed {
                    if at_prefix(e, p, end, lg.block_close) {
                        p += lg.block_close.len
                        closed = true
                    } else {
                        p += 1usize
                    }
                }
                if !closed { st = 1u8 }
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_COMMENT } }
                nt += 1usize
            } else if quote_index(lg.quotes, c) != NO_GOAL {
                p += 1usize
                var closed = false
                while p < end && !closed {
                    let d = byte_at(e, p)
                    if d == 92u8 && p + 1usize < end {
                        p += 2usize
                    } else if d == c {
                        p += 1usize
                        closed = true
                    } else {
                        p += 1usize
                    }
                }
                if !closed {
                    let mi = quote_index(lg.multiline_quotes, c)
                    if mi != NO_GOAL { st = u8(2usize + mi) }
                }
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_STRING } }
                nt += 1usize
            } else if is_word_byte(c) && !(c >= 48u8 && c <= 57u8) {
                while p < end && is_word_byte(byte_at(e, p)) { p += 1usize }
                var kind = TOK_IDENT
                if has_word(lg.keywords, e, t0, p) { kind = TOK_KEYWORD } else if has_word(lg.types, e, t0, p) { kind = TOK_TYPE }
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: kind } }
                nt += 1usize
            } else if c >= 48u8 && c <= 57u8 {
                while p < end && (is_word_byte(byte_at(e, p)) || byte_at(e, p) == 46u8) { p += 1usize }
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: TOK_NUMBER } }
                nt += 1usize
            } else {
                p += 1usize
                var kind = TOK_OPERATOR
                if c == 40u8 || c == 41u8 || c == 91u8 || c == 93u8 || c == 123u8 || c == 125u8 || c == 44u8 || c == 59u8 { kind = TOK_PUNCT }
                if nt < out.len { out[nt] = Token { start: t0, end: p, kind: kind } }
                nt += 1usize
            }
        }
    }
    ret (nt, st)
}

// Bring the cached start states of lines 0..=upto up to date: process dirty lines in order and stop propagating
// as soon as a line's end state equals the cached start state of the next clean line.
fn ensure_states(e: *Editor, upto: usize) {
    var l = e.first_dirty
    var none: [1]Token = zero
    while l <= upto && l < e.nlines {
        if (e.line_state[l] & 128u8) == 0u8 {
            l += 1usize
        } else {
            let (_, out_state) = scan_line(e, l, e.line_state[l] & 127u8, none[..0usize])
            e.line_state[l] = e.line_state[l] & 127u8
            if l + 1usize < e.nlines {
                let nx = e.line_state[l + 1usize]
                if (nx & 128u8) != 0u8 {
                    e.line_state[l + 1usize] = 128u8 | out_state
                } else if nx != out_state {
                    e.line_state[l + 1usize] = 128u8 | out_state
                }
            }
            l += 1usize
        }
    }
    var f = l
    while f < e.nlines && (e.line_state[f] & 128u8) == 0u8 { f += 1usize }
    if f >= e.nlines { e.first_dirty = NO_DIRTY } else { e.first_dirty = f }
}

// Tokens of one line (non-blank, absolute offsets) into out; returns how many were produced (may exceed out.len).
fn tokens(e: *Editor, ln: usize, out: []Token) -> usize {
    if ln >= e.nlines { ret 0usize }
    ensure_states(e, ln)
    let (n, _) = scan_line(e, ln, e.line_state[ln] & 127u8, out)
    ret n
}

// Replace the language; every line's state is recomputed on demand.
fn set_language(e: *Editor, lg: Language) {
    e.lang = lg
    var i = 0usize
    while i < e.nlines {
        e.line_state[i] = 128u8
        i += 1usize
    }
    e.line_state[0usize] = 128u8
    e.first_dirty = 0usize
}

// ---- history stacks ---------------------------------------------------------------------------------------

fn stack_room(s: *const Stack, nent: usize, nbat: usize, ned: usize, ntext: usize, nsel: usize) -> bool {
    ret s.nent + nent <= s.entries.len && s.nbat + nbat <= s.batches.len && s.ned + ned <= s.edits.len && s.ntext + ntext <= s.text.len && s.nsel + nsel <= s.sels.len
}

fn stack_clear(s: *Stack) {
    s.nent = 0usize
    s.nbat = 0usize
    s.ned = 0usize
    s.ntext = 0usize
    s.nsel = 0usize
}

fn stack_drop_oldest(s: *Stack) {
    let first = s.entries[0usize]
    let last_batch = s.batches[first.batch_first + first.batch_n - 1usize]
    let nb = first.batch_n
    let ne = last_batch.edit_first + last_batch.edit_n
    let nt = last_batch.text_first + last_batch.text_len
    let ns = first.sel_n
    var i = 1usize
    while i < s.nent {
        var en = s.entries[i]
        en.batch_first -= nb
        en.sel_first -= ns
        s.entries[i - 1usize] = en
        i += 1usize
    }
    var j = nb
    while j < s.nbat {
        var b = s.batches[j]
        b.edit_first -= ne
        b.text_first -= nt
        s.batches[j - nb] = b
        j += 1usize
    }
    var k = ne
    while k < s.ned {
        var ed = s.edits[k]
        ed.text_off -= nt
        s.edits[k - ne] = ed
        k += 1usize
    }
    var t = nt
    while t < s.ntext {
        s.text[t - nt] = s.text[t]
        t += 1usize
    }
    var q = ns
    while q < s.nsel {
        s.sels[q - ns] = s.sels[q]
        q += 1usize
    }
    s.nent -= 1usize
    s.nbat -= nb
    s.ned -= ne
    s.ntext -= nt
    s.nsel -= ns
}

// Evict oldest entries until the requested room exists. `keep` entries at the top are never evicted.
fn stack_make_room(s: *Stack, nent: usize, nbat: usize, ned: usize, ntext: usize, nsel: usize, keep: usize) -> bool {
    while !stack_room(s, nent, nbat, ned, ntext, nsel) {
        if s.nent <= keep { ret false }
        stack_drop_oldest(s)
    }
    ret true
}

// ---- selections -------------------------------------------------------------------------------------------

fn range_from(r: Range) -> usize { ret min_of(r.anchor, r.head) }
fn range_to(r: Range) -> usize { ret max_of(r.anchor, r.head) }
fn caret(pos: usize) -> Range { ret Range { anchor: pos, head: pos, goal: NO_GOAL } }

// Sort by start and merge overlapping ranges (touching empty carets merge too); returns (count, new primary).
fn normalize(rs: []Range, n: usize, primary: usize) -> (usize, usize) {
    if n == 0usize { ret (0usize, 0usize) }
    let mark = rs[min_of(primary, n - 1usize)].head
    var i = 1usize
    while i < n {
        let cur = rs[i]
        var j = i
        while j > 0usize && (range_from(rs[j - 1usize]) > range_from(cur) || (range_from(rs[j - 1usize]) == range_from(cur) && range_to(rs[j - 1usize]) > range_to(cur))) {
            rs[j] = rs[j - 1usize]
            j -= 1usize
        }
        rs[j] = cur
        i += 1usize
    }
    var w = 0usize
    var r = 1usize
    while r < n {
        let prev = rs[w]
        let cur = rs[r]
        var merge = false
        if range_from(cur) < range_to(prev) { merge = true }
        if range_from(cur) == range_to(prev) && (cur.anchor == cur.head || prev.anchor == prev.head) { merge = true }
        if merge {
            let lo = range_from(prev)
            let hi = max_of(range_to(prev), range_to(cur))
            if prev.head >= prev.anchor && cur.head >= cur.anchor || prev.anchor == prev.head {
                rs[w] = Range { anchor: lo, head: hi, goal: NO_GOAL }
            } else {
                rs[w] = Range { anchor: hi, head: lo, goal: NO_GOAL }
            }
        } else {
            w += 1usize
            rs[w] = cur
        }
        r += 1usize
    }
    var pi = 0usize
    var s = 0usize
    while s <= w {
        if range_from(rs[s]) <= mark && mark <= range_to(rs[s]) { pi = s }
        s += 1usize
    }
    ret (w + 1usize, pi)
}

// Replace the selection with `ranges` (validated against the document, then normalised).
fn set_selection(e: *Editor, ranges: []const Range, primary: usize) -> err {
    if ranges.len == 0usize { ret Invalid }
    if ranges.len > e.sels.len { ret TooManySelections }
    var i = 0usize
    while i < ranges.len {
        if ranges[i].anchor > len(e) || ranges[i].head > len(e) { ret Invalid }
        if !is_boundary(e, ranges[i].anchor) || !is_boundary(e, ranges[i].head) { ret NotBoundary }
        i += 1usize
    }
    var j = 0usize
    while j < ranges.len {
        e.sels[j] = ranges[j]
        j += 1usize
    }
    let (n, pi) = normalize(e.sels, ranges.len, primary)
    e.nsel = n
    e.primary = pi
    e.can_merge = false
    ret ok
}

fn selection_count(e: *const Editor) -> usize { ret e.nsel }
fn selection_at(e: *const Editor, i: usize) -> Range { ret e.sels[i] }

// ---- commit -----------------------------------------------------------------------------------------------

// Map pos through a sorted batch: `assoc` > 0 lands after text inserted at pos, otherwise before it.
fn map_pos(edits: []const Edit, pos: usize, assoc: i32) -> usize {
    var shift_add = 0usize
    var shift_sub = 0usize
    var i = 0usize
    while i < edits.len {
        let ed = edits[i]
        if pos < ed.at { break }
        if pos <= ed.at + ed.remove {
            var r = ed.at + shift_add - shift_sub
            if assoc > 0i32 { r += ed.text_len }
            ret r
        }
        shift_add += ed.text_len
        shift_sub += ed.remove
        i += 1usize
    }
    ret pos + shift_add - shift_sub
}

// Check a batch against the document without touching it.
fn validate(e: *const Editor, edits: []const Edit, text: []const u8) -> err {
    var prev_end = 0usize
    var total_rem = 0usize
    var total_ins = 0usize
    var nl_ins = 0usize
    var nl_rem = 0usize
    var i = 0usize
    while i < edits.len {
        let ed = edits[i]
        if ed.at < prev_end { ret BadEdits }
        if ed.at > len(e) || ed.remove > len(e) - ed.at { ret BadEdits }
        if !is_boundary(e, ed.at) || !is_boundary(e, ed.at + ed.remove) { ret NotBoundary }
        if ed.text_off > text.len || ed.text_len > text.len - ed.text_off { ret BadEdits }
        if !valid_utf8(text, ed.text_off, ed.text_len) { ret Invalid }
        var k = 0usize
        while k < ed.text_len {
            if text[ed.text_off + k] == 10u8 { nl_ins += 1usize }
            k += 1usize
        }
        var m = ed.at
        while m < ed.at + ed.remove {
            if byte_at(e, m) == 10u8 { nl_rem += 1usize }
            m += 1usize
        }
        total_rem += ed.remove
        total_ins += ed.text_len
        prev_end = ed.at + ed.remove
        i += 1usize
    }
    if len(e) - total_rem + total_ins > e.buf.len { ret TooLarge }
    if e.nlines - nl_rem + nl_ins > e.lines.len { ret TooManyLines }
    ret ok
}

// Apply a validated batch (last edit first, so earlier coordinates stay valid) and record its inverse as a new
// batch on the top entry of `to`, whose room the caller reserved.
fn apply_raw(e: *Editor, edits: []const Edit, text: []const u8, to: *Stack) {
    let top = to.nent - 1usize
    var total_rem = 0usize
    var i = 0usize
    while i < edits.len {
        total_rem += edits[i].remove
        i += 1usize
    }
    let bi = to.nbat
    to.batches[bi] = Batch { edit_first: to.ned, edit_n: edits.len, text_first: to.ntext, text_len: total_rem }
    to.nbat += 1usize
    to.entries[top].batch_n += 1usize
    var delta_add = 0usize
    var delta_sub = 0usize
    var j = 0usize
    while j < edits.len {
        let ed = edits[j]
        let at_new = ed.at + delta_add - delta_sub
        to.edits[to.ned] = Edit { at: at_new, remove: ed.text_len, text_off: to.ntext, text_len: ed.remove }
        to.ned += 1usize
        var k = 0usize
        while k < ed.remove {
            to.text[to.ntext + k] = byte_at(e, ed.at + k)
            k += 1usize
        }
        to.ntext += ed.remove
        delta_add += ed.text_len
        delta_sub += ed.remove
        j += 1usize
    }
    var n = edits.len
    while n > 0usize {
        n -= 1usize
        let ed = edits[n]
        move_gap(e, ed.at)
        e.gap_end += ed.remove
        lines_splice(e, ed.at, ed.remove, text, ed.text_off, ed.text_len)
        var c = 0usize
        while c < ed.text_len {
            e.buf[e.gap_start + c] = text[ed.text_off + c]
            c += 1usize
        }
        e.gap_start += ed.text_len
    }
    e.revision += 1u64
}

fn push_entry(to: *Stack, id_before: u64, kind: u32, sels: []const Range, n: usize) {
    var i = 0usize
    while i < n {
        to.sels[to.nsel + i] = sels[i]
        i += 1usize
    }
    to.entries[to.nent] = Entry { batch_first: to.nbat, batch_n: 0usize, sel_first: to.nsel, sel_n: n, id_before: id_before, kind: kind }
    to.nent += 1usize
    to.nsel += n
}

// Apply a batch as one undoable transaction. `new_sels` becomes the selection (it is validated and normalised
// like set_selection). `kind` and `e.can_merge` decide whether the history entry joins the previous one: typing
// joins typing, backspace joins backspace, anything else starts a new entry.
fn commit(e: *Editor, edits: []const Edit, text: []const u8, new_sels: []const Range, kind: u32) -> err {
    try validate(e, edits, text)
    if new_sels.len > e.sels.len { ret TooManySelections }
    var new_len = len(e)
    var q = 0usize
    while q < edits.len {
        new_len = new_len - edits[q].remove + edits[q].text_len
        q += 1usize
    }
    var v = 0usize
    while v < new_sels.len {
        if new_sels[v].anchor > new_len || new_sels[v].head > new_len { ret Invalid }
        v += 1usize
    }
    if edits.len == 0usize {
        if new_sels.len > 0usize {
            var w = 0usize
            while w < new_sels.len {
                e.sels[w] = new_sels[w]
                w += 1usize
            }
            let (n0, p0) = normalize(e.sels, new_sels.len, 0usize)
            e.nsel = n0
            e.primary = p0
        }
        ret ok
    }
    var total_rem = 0usize
    var i = 0usize
    while i < edits.len {
        total_rem += edits[i].remove
        i += 1usize
    }
    let merge = kind != KIND_OTHER && e.can_merge && e.merge_kind == kind && e.undo.nent > 0usize
    if merge {
        if !stack_make_room(&e.undo, 0usize, 1usize, edits.len, total_rem, 0usize, 1usize) { ret TooLarge }
    } else {
        if !stack_make_room(&e.undo, 1usize, 1usize, edits.len, total_rem, e.nsel, 0usize) { ret TooLarge }
    }
    // Nothing below can fail: history room exists, the batch validated.
    let before_id = e.content_id
    if !merge { push_entry(&e.undo, before_id, kind, e.sels, e.nsel) }
    stack_clear(&e.redo)
    if edits.len > 0usize {
        apply_raw(e, edits, text, &e.undo)
        e.content_id = e.next_id
        e.next_id += 1u64
    }
    var j = 0usize
    while j < new_sels.len {
        e.sels[j] = new_sels[j]
        j += 1usize
    }
    if new_sels.len > 0usize {
        let (n, pi) = normalize(e.sels, new_sels.len, 0usize)
        e.nsel = n
        e.primary = pi
    }
    e.can_merge = kind != KIND_OTHER
    e.merge_kind = kind
    ret ok
}

// Programmatic edit: selections follow the batch (non-empty ranges exclude text inserted at their boundaries).
fn apply_edits(e: *Editor, edits: []const Edit, text: []const u8) -> err {
    ret apply_edits_as(e, edits, text, KIND_OTHER, -1i32)
}

// apply_edits with an explicit history kind and the association of empty ranges at an insertion point.
fn apply_edits_as(e: *Editor, edits: []const Edit, text: []const u8, kind: u32, caret_assoc: i32) -> err {
    var mapped: [64]Range = zero
    if e.nsel > 64usize { ret TooManySelections }
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        let lo = range_from(r)
        let hi = range_to(r)
        var a = 0usize
        var h = 0usize
        if lo == hi {
            a = map_pos(edits, lo, caret_assoc)
            h = a
        } else {
            let mlo = map_pos(edits, lo, 1i32)
            let mhi = map_pos(edits, hi, -1i32)
            if r.anchor <= r.head {
                a = mlo
                h = max_of(mlo, mhi)
            } else {
                h = mlo
                a = max_of(mlo, mhi)
            }
        }
        mapped[i] = Range { anchor: a, head: h, goal: NO_GOAL }
        i += 1usize
    }
    ret commit(e, edits, text, mapped[0usize..e.nsel], kind)
}

// ---- undo and redo ------------------------------------------------------------------------------------------

fn can_undo(e: *const Editor) -> bool { ret e.undo.nent > 0usize }
fn can_redo(e: *const Editor) -> bool { ret e.redo.nent > 0usize }
fn is_dirty(e: *const Editor) -> bool { ret e.content_id != e.saved_id }
fn mark_saved(e: *Editor) { e.saved_id = e.content_id }

// Stop the next typing/delete from joining the previous history entry.
fn break_group(e: *Editor) { e.can_merge = false }

fn history_step(e: *Editor, from: *Stack, to: *Stack) -> err {
    if from.nent == 0usize { ret ok }
    let ent = from.entries[from.nent - 1usize]
    var ned = 0usize
    var nrem = 0usize
    var b = 0usize
    while b < ent.batch_n {
        let bt = from.batches[ent.batch_first + b]
        ned += bt.edit_n
        var k = 0usize
        while k < bt.edit_n {
            nrem += from.edits[bt.edit_first + k].remove
            k += 1usize
        }
        b += 1usize
    }
    if !stack_make_room(to, 1usize, ent.batch_n, ned, nrem, e.nsel, 0usize) { ret TooLarge }
    let id_now = e.content_id
    push_entry(to, id_now, KIND_OTHER, e.sels, e.nsel)
    var c = ent.batch_n
    while c > 0usize {
        c -= 1usize
        let bt = from.batches[ent.batch_first + c]
        apply_raw(e, from.edits[bt.edit_first..bt.edit_first + bt.edit_n], from.text[0usize..from.ntext], to)
    }
    // restore the selection the entry captured
    var s = 0usize
    while s < ent.sel_n {
        e.sels[s] = from.sels[ent.sel_first + s]
        s += 1usize
    }
    e.nsel = ent.sel_n
    e.primary = min_of(e.primary, ent.sel_n - 1usize)
    e.content_id = ent.id_before
    // pop
    from.nent -= 1usize
    from.nbat = ent.batch_first
    from.nsel = ent.sel_first
    if ent.batch_n > 0usize {
        let first_b = from.batches[ent.batch_first]
        from.ned = first_b.edit_first
        from.ntext = first_b.text_first
    }
    e.can_merge = false
    ret ok
}

fn undo(e: *Editor) -> err { ret history_step(e, &e.undo, &e.redo) }
fn redo(e: *Editor) -> err { ret history_step(e, &e.redo, &e.undo) }

// ---- construction -----------------------------------------------------------------------------------------

fn make_stack(a: *mem.Arena, entries: usize, edits: usize, text: usize, sels: usize) -> (Stack, err) {
    let (en, e1) = mem.alloc[Entry](a, entries)
    if e1 != ok { ret (zero, e1) }
    let (bt, e2) = mem.alloc[Batch](a, entries * 4usize)
    if e2 != ok { ret (zero, e2) }
    let (ed, e3) = mem.alloc[Edit](a, edits)
    if e3 != ok { ret (zero, e3) }
    let (tx, e4) = mem.alloc[u8](a, text)
    if e4 != ok { ret (zero, e4) }
    let (sl, e5) = mem.alloc[Range](a, sels)
    if e5 != ok { ret (zero, e5) }
    ret (Stack { entries: en, nent: 0usize, batches: bt, nbat: 0usize, edits: ed, ned: 0usize, text: tx, ntext: 0usize, sels: sl, nsel: 0usize }, ok)
}

// An empty editor: `capacity` bytes of text, `max_lines` lines, `max_sels` simultaneous ranges, and history for
// `history_entries` transactions holding at most `history_edits` edits and `history_bytes` of removed text per stack.
fn open(a: *mem.Arena, capacity: usize, max_lines: usize, max_sels: usize, history_entries: usize, history_edits: usize, history_bytes: usize) -> (Editor, err) {
    if capacity == 0usize || max_lines == 0usize || max_sels == 0usize || history_entries == 0usize || history_edits == 0usize { ret (zero, Invalid) }
    let (buf, e1) = mem.alloc[u8](a, capacity)
    if e1 != ok { ret (zero, e1) }
    let (lines, e2) = mem.alloc[usize](a, max_lines)
    if e2 != ok { ret (zero, e2) }
    let (states, e3) = mem.alloc[u8](a, max_lines)
    if e3 != ok { ret (zero, e3) }
    let (sels, e4) = mem.alloc[Range](a, max_sels)
    if e4 != ok { ret (zero, e4) }
    let (undo_stack, e5) = make_stack(a, history_entries, history_edits, history_bytes, history_entries * max_sels)
    if e5 != ok { ret (zero, e5) }
    let (redo_stack, e6) = make_stack(a, history_entries, history_edits, history_bytes, history_entries * max_sels)
    if e6 != ok { ret (zero, e6) }
    let (sedits, e7) = mem.alloc[Edit](a, history_edits)
    if e7 != ok { ret (zero, e7) }
    let (stext, e8) = mem.alloc[u8](a, history_bytes + capacity)
    if e8 != ok { ret (zero, e8) }
    let (ssels, e9) = mem.alloc[Range](a, max_sels)
    if e9 != ok { ret (zero, e9) }
    var e: Editor = zero
    e.buf = buf
    e.gap_start = 0usize
    e.gap_end = capacity
    e.lines = lines
    e.line_state = states
    e.lines[0usize] = 0usize
    e.line_state[0usize] = 0u8
    e.nlines = 1usize
    e.first_dirty = NO_DIRTY
    e.sels = sels
    e.sels[0usize] = caret(0usize)
    e.nsel = 1usize
    e.primary = 0usize
    e.undo = undo_stack
    e.redo = redo_stack
    e.content_id = 1u64
    e.next_id = 2u64
    e.saved_id = 1u64
    e.lang = lang_plain()
    e.use_tabs = false
    e.tab_width = 4usize
    e.indent_unit = 4usize
    e.scratch_edits = sedits
    e.scratch_text = stext
    e.scratch_sels = ssels
    ret (e, ok)
}

// Replace the whole document with `text` without history (opening a file): clears both stacks and marks it saved.
fn load(e: *Editor, text: []const u8) -> err {
    if text.len > e.buf.len { ret TooLarge }
    if !valid_utf8(text, 0usize, text.len) { ret Invalid }
    var nl = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 { nl += 1usize }
        i += 1usize
    }
    if nl > e.lines.len { ret TooManyLines }
    e.gap_start = 0usize
    e.gap_end = e.buf.len
    var k = 0usize
    while k < text.len {
        e.buf[k] = text[k]
        k += 1usize
    }
    e.gap_start = text.len
    e.nlines = 1usize
    e.lines[0usize] = 0usize
    var p = 0usize
    while p < text.len {
        if text[p] == 10u8 {
            e.lines[e.nlines] = p + 1usize
            e.nlines += 1usize
        }
        p += 1usize
    }
    var s = 0usize
    while s < e.nlines {
        e.line_state[s] = 128u8
        s += 1usize
    }
    e.first_dirty = 0usize
    stack_clear(&e.undo)
    stack_clear(&e.redo)
    e.sels[0usize] = caret(0usize)
    e.nsel = 1usize
    e.primary = 0usize
    e.content_id = e.next_id
    e.next_id += 1u64
    e.saved_id = e.content_id
    e.revision += 1u64
    e.can_merge = false
    ret ok
}

// ---- editing commands -------------------------------------------------------------------------------------

// Insert `s` at every selection (replacing a non-empty one), carets after the text; typing joins one undo entry.
fn type_text(e: *Editor, s: str) -> err {
    if e.nsel > e.scratch_edits.len { ret TooLarge }
    var gain = 0usize
    var loss = 0usize
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        let lo = range_from(r)
        let hi = range_to(r)
        e.scratch_edits[i] = Edit { at: lo, remove: hi - lo, text_off: 0usize, text_len: s.len }
        e.scratch_sels[i] = caret(lo + gain + s.len - loss)
        gain += s.len
        loss += hi - lo
        i += 1usize
    }
    ret commit(e, e.scratch_edits[0usize..e.nsel], s, e.scratch_sels[0usize..e.nsel], KIND_TYPING)
}

// Delete the selection, or the grapheme before (`forward` false) or after each caret.
fn delete_char(e: *Editor, forward: bool) -> err {
    if e.nsel > e.scratch_edits.len { ret TooLarge }
    var n = 0usize
    var shift = 0usize
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        var lo = range_from(r)
        var hi = range_to(r)
        if lo == hi {
            if forward { hi = next_boundary(e, lo) } else { lo = prev_boundary(e, hi) }
        }
        var skip = false
        if n > 0usize {
            let pe = e.scratch_edits[n - 1usize]
            if lo < pe.at + pe.remove {
                lo = pe.at + pe.remove
                if hi < lo { skip = true }
            }
        }
        if !skip {
            e.scratch_edits[n] = Edit { at: lo, remove: hi - lo, text_off: 0usize, text_len: 0usize }
            e.scratch_sels[n] = caret(lo - shift)
            shift += hi - lo
            n += 1usize
        }
        i += 1usize
    }
    var kind = KIND_DELETE_BACK
    if forward { kind = KIND_DELETE_FORWARD }
    ret commit(e, e.scratch_edits[0usize..n], "", e.scratch_sels[0usize..n], kind)
}

fn is_blank_byte(c: u8) -> bool { ret c == 32u8 || c == 9u8 }

// Leading white space of line ln in columns (a tab advances to the next multiple of tab_width) and in bytes.
fn indent_of(e: *const Editor, ln: usize) -> (usize, usize) {
    var p = line_start(e, ln)
    let end = line_end(e, ln)
    var col = 0usize
    while p < end && is_blank_byte(byte_at(e, p)) {
        if byte_at(e, p) == 9u8 {
            col = (col / e.tab_width + 1usize) * e.tab_width
        } else {
            col += 1usize
        }
        p += 1usize
    }
    ret (col, p - line_start(e, ln))
}

// The indentation of `width` columns under the editor's tab policy, written to dst; returns its length.
fn write_indent(e: *const Editor, width: usize, dst: []u8, at: usize) -> usize {
    var n = 0usize
    var w = width
    if e.use_tabs {
        while w >= e.tab_width {
            dst[at + n] = 9u8
            n += 1usize
            w -= e.tab_width
        }
    }
    while w > 0usize {
        dst[at + n] = 32u8
        n += 1usize
        w -= 1usize
    }
    ret n
}

fn is_open_bracket(c: u8) -> bool { ret c == 123u8 || c == 40u8 || c == 91u8 }
fn closes(open_c: u8, c: u8) -> bool {
    ret (open_c == 123u8 && c == 125u8) || (open_c == 40u8 && c == 41u8) || (open_c == 91u8 && c == 93u8)
}

// Enter at every selection: a newline carrying the line's indentation, one unit deeper after an opening
// bracket, and between a bracket pair the closer moves to its own line (the caret lands on the middle line).
fn newline_indent(e: *Editor) -> err {
    if e.nsel > e.scratch_edits.len { ret TooLarge }
    var off = 0usize
    var gain = 0usize
    var loss = 0usize
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        let lo = range_from(r)
        let hi = range_to(r)
        let ln = line_of(e, lo)
        let (width, _) = indent_of(e, ln)
        // last non-blank byte before lo on its line, first non-blank byte at hi
        var b = lo
        while b > line_start(e, ln) && is_blank_byte(byte_at(e, b - 1usize)) { b -= 1usize }
        var last = 0u8
        if b > line_start(e, ln) { last = byte_at(e, b - 1usize) }
        var f = hi
        let hend = line_end(e, line_of(e, hi))
        while f < hend && is_blank_byte(byte_at(e, f)) { f += 1usize }
        var first = 0u8
        if f < hend { first = byte_at(e, f) }
        let deeper = is_open_bracket(last)
        var inner = width
        if deeper { inner += e.indent_unit }
        let start = off
        e.scratch_text[off] = 10u8
        off += 1usize
        off += write_indent(e, inner, e.scratch_text, off)
        let caret_off = off - start
        if deeper && closes(last, first) {
            e.scratch_text[off] = 10u8
            off += 1usize
            off += write_indent(e, width, e.scratch_text, off)
        }
        // drop trailing blanks before the caret on the old line: not done; keep the user's text untouched
        e.scratch_edits[i] = Edit { at: lo, remove: hi - lo, text_off: start, text_len: off - start }
        e.scratch_sels[i] = caret(lo + gain + caret_off - loss)
        gain += off - start
        loss += hi - lo
        i += 1usize
    }
    ret commit(e, e.scratch_edits[0usize..e.nsel], e.scratch_text[0usize..off], e.scratch_sels[0usize..e.nsel], KIND_OTHER)
}

// Lines touched by the selection, ascending and unique, into out (a range ending at a line start excludes it
// unless the range is empty); returns the count.
fn selected_lines(e: *const Editor, out: []usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        let lo = range_from(r)
        var hi = range_to(r)
        var l0 = line_of(e, lo)
        var l1 = line_of(e, hi)
        if hi > lo && l1 > l0 && line_start(e, l1) == hi { l1 -= 1usize }
        if n > 0usize && out[n - 1usize] >= l0 { l0 = out[n - 1usize] + 1usize }
        var l = l0
        while l <= l1 && n < out.len {
            out[n] = l
            n += 1usize
            l += 1usize
        }
        i += 1usize
    }
    ret n
}

// Indent (or dedent) every selected line by one unit as one transaction; blank lines are left alone when indenting.
fn indent_lines(e: *Editor, dedent: bool) -> err {
    var lines: [64]usize = zero
    let nl = selected_lines(e, lines[..])
    var off = 0usize
    var ne = 0usize
    var i = 0usize
    while i < nl {
        let ln = lines[i]
        let s = line_start(e, ln)
        if !dedent {
            if line_end(e, ln) > s && ne < e.scratch_edits.len {
                let start = off
                off += write_indent(e, e.indent_unit, e.scratch_text, off)
                e.scratch_edits[ne] = Edit { at: s, remove: 0usize, text_off: start, text_len: off - start }
                ne += 1usize
            }
        } else {
            var rm = 0usize
            if s < line_end(e, ln) && byte_at(e, s) == 9u8 {
                rm = 1usize
            } else {
                while rm < e.indent_unit && s + rm < line_end(e, ln) && byte_at(e, s + rm) == 32u8 { rm += 1usize }
            }
            if rm > 0usize && ne < e.scratch_edits.len {
                e.scratch_edits[ne] = Edit { at: s, remove: rm, text_off: 0usize, text_len: 0usize }
                ne += 1usize
            }
        }
        i += 1usize
    }
    if ne == 0usize { ret ok }
    ret apply_edits_as(e, e.scratch_edits[0usize..ne], e.scratch_text[0usize..off], KIND_OTHER, 1i32)
}

// Toggle the language's line comment on the selected lines: remove it when every non-blank line has it, else
// insert "<comment> " at the smallest indentation among them.
fn toggle_comment(e: *Editor) -> err {
    let cm = e.lang.line_comment
    if cm.len == 0usize { ret Invalid }
    var lines: [64]usize = zero
    let nl = selected_lines(e, lines[..])
    var all = true
    var any = false
    var min_ind = 1000000usize
    var i = 0usize
    while i < nl {
        let ln = lines[i]
        let (_, nb) = indent_of(e, ln)
        let p = line_start(e, ln) + nb
        if p < line_end(e, ln) {
            any = true
            if nb < min_ind { min_ind = nb }
            if !at_prefix(e, p, line_end(e, ln), cm) { all = false }
        }
        i += 1usize
    }
    if !any { ret ok }
    var off = 0usize
    var ne = 0usize
    var j = 0usize
    while j < nl {
        let ln = lines[j]
        let (_, nb) = indent_of(e, ln)
        let p = line_start(e, ln) + nb
        if p < line_end(e, ln) {
            if all {
                var rm = cm.len
                if p + rm < line_end(e, ln) && byte_at(e, p + rm) == 32u8 { rm += 1usize }
                e.scratch_edits[ne] = Edit { at: p, remove: rm, text_off: 0usize, text_len: 0usize }
            } else {
                let start = off
                var k = 0usize
                while k < cm.len {
                    e.scratch_text[off] = cm[k]
                    off += 1usize
                    k += 1usize
                }
                e.scratch_text[off] = 32u8
                off += 1usize
                e.scratch_edits[ne] = Edit { at: line_start(e, ln) + min_ind, remove: 0usize, text_off: start, text_len: off - start }
            }
            ne += 1usize
        }
        j += 1usize
    }
    ret apply_edits_as(e, e.scratch_edits[0usize..ne], e.scratch_text[0usize..off], KIND_OTHER, 1i32)
}

// ---- motion -----------------------------------------------------------------------------------------------

fn is_word_char_at(e: *const Editor, p: usize) -> bool {
    let (c, n) = decode_at(e, p)
    if n == 0usize { ret false }
    ret c >= 128u32 || is_word_byte(u8(c))
}

fn word_end(e: *const Editor, pos: usize) -> usize {
    var p = pos
    while p < len(e) && !is_word_char_at(e, p) && byte_at(e, p) != 10u8 { p = next_boundary(e, p) }
    while p < len(e) && is_word_char_at(e, p) { p = next_boundary(e, p) }
    ret p
}

fn word_start(e: *const Editor, pos: usize) -> usize {
    var p = pos
    while p > 0usize && !is_word_char_at(e, prev_boundary(e, p)) && byte_at(e, prev_boundary(e, p)) != 10u8 { p = prev_boundary(e, p) }
    while p > 0usize && is_word_char_at(e, prev_boundary(e, p)) { p = prev_boundary(e, p) }
    ret p
}

// Move (or extend, keeping each anchor) every range. Plain left/right collapse a non-empty range to its edge.
fn move_selection(e: *Editor, dir: u32, extend: bool) -> err {
    var i = 0usize
    while i < e.nsel {
        let r = e.sels[i]
        let lo = range_from(r)
        let hi = range_to(r)
        var h = r.head
        var goal = r.goal
        let empty = lo == hi
        if dir == MOVE_LEFT {
            if !extend && !empty { h = lo } else { h = prev_boundary(e, r.head) }
            goal = NO_GOAL
        } else if dir == MOVE_RIGHT {
            if !extend && !empty { h = hi } else { h = next_boundary(e, r.head) }
            goal = NO_GOAL
        } else if dir == MOVE_UP || dir == MOVE_DOWN {
            let ln = line_of(e, r.head)
            if goal == NO_GOAL { goal = column_of(e, r.head) }
            if dir == MOVE_UP {
                if ln == 0usize { h = 0usize } else { h = pos_at_column(e, ln - 1usize, goal) }
            } else {
                if ln + 1usize >= e.nlines { h = len(e) } else { h = pos_at_column(e, ln + 1usize, goal) }
            }
        } else if dir == MOVE_LINE_START {
            h = line_start(e, line_of(e, r.head))
            goal = NO_GOAL
        } else if dir == MOVE_LINE_END {
            h = line_end(e, line_of(e, r.head))
            goal = NO_GOAL
        } else if dir == MOVE_DOC_START {
            h = 0usize
            goal = NO_GOAL
        } else if dir == MOVE_DOC_END {
            h = len(e)
            goal = NO_GOAL
        } else if dir == MOVE_WORD_LEFT {
            h = word_start(e, r.head)
            goal = NO_GOAL
        } else if dir == MOVE_WORD_RIGHT {
            h = word_end(e, r.head)
            goal = NO_GOAL
        } else {
            ret Invalid
        }
        var a = h
        if extend { a = r.anchor }
        e.sels[i] = Range { anchor: a, head: h, goal: goal }
        i += 1usize
    }
    let (n, pi) = normalize(e.sels, e.nsel, e.primary)
    e.nsel = n
    e.primary = pi
    e.can_merge = false
    ret ok
}

// ---- search -----------------------------------------------------------------------------------------------

fn fold_byte(c: u8, sensitive: bool) -> u8 {
    if !sensitive && c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn match_at(e: *const Editor, q: str, p: usize, o: SearchOpts) -> bool {
    if q.len == 0usize || p + q.len > len(e) { ret false }
    var i = 0usize
    while i < q.len {
        if fold_byte(byte_at(e, p + i), o.case_sensitive) != fold_byte(q[i], o.case_sensitive) { ret false }
        i += 1usize
    }
    if o.whole_word {
        if p > 0usize && is_word_char_at(e, prev_cp_start(e, p)) { ret false }
        if p + q.len < len(e) && is_word_char_at(e, p + q.len) { ret false }
    }
    ret true
}

// First match starting at or after `from` (forward) or the last starting before `from` (backward).
fn find(e: *const Editor, q: str, from: usize, forward: bool, o: SearchOpts) -> (usize, bool) {
    if q.len == 0usize { ret (0usize, false) }
    if forward {
        var p = from
        while p + q.len <= len(e) {
            if is_boundary(e, p) && match_at(e, q, p, o) { ret (p, true) }
            p += 1usize
        }
    } else {
        var p = min_of(from, len(e))
        while p > 0usize {
            p -= 1usize
            if is_boundary(e, p) && match_at(e, q, p, o) { ret (p, true) }
        }
    }
    ret (0usize, false)
}

// Non-overlapping matches left to right, counted up to `limit` (the second result is true when capped).
fn count_matches(e: *const Editor, q: str, o: SearchOpts, limit: usize) -> (usize, bool) {
    if q.len == 0usize { ret (0usize, false) }
    var n = 0usize
    var p = 0usize
    while p + q.len <= len(e) {
        if is_boundary(e, p) && match_at(e, q, p, o) {
            n += 1usize
            if n >= limit { ret (n, true) }
            p += q.len
        } else {
            p += 1usize
        }
    }
    ret (n, false)
}

// Replace every match in one transaction; returns how many. Refused whole (no change) when the matches do not
// fit the edit scratch or the document.
fn replace_all(e: *Editor, q: str, repl: str, o: SearchOpts) -> (usize, err) {
    if q.len == 0usize { ret (0usize, ok) }
    var n = 0usize
    var p = 0usize
    while p + q.len <= len(e) {
        if is_boundary(e, p) && match_at(e, q, p, o) {
            if n >= e.scratch_edits.len { ret (0usize, TooLarge) }
            e.scratch_edits[n] = Edit { at: p, remove: q.len, text_off: 0usize, text_len: repl.len }
            n += 1usize
            p += q.len
        } else {
            p += 1usize
        }
    }
    if n == 0usize { ret (0usize, ok) }
    let r = apply_edits_as(e, e.scratch_edits[0usize..n], repl, KIND_OTHER, -1i32)
    if r != ok { ret (0usize, r) }
    ret (n, ok)
}
