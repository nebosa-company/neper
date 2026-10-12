// Terminal emulator engine (D3200, L136): a headless VT100/xterm-class state machine over a cell grid.
// Bytes in (`feed`), cells out (`line_cell`, `snapshot`); no PTY, no window and no clock. The parser follows the
// DEC ANSI model (ground, escape, CSI, OSC, string-ignore) with a streaming UTF-8 decoder in ground state, so a
// sequence or a character split across `feed` calls resumes where it stopped. Supported: C0 controls, cursor
// motion and save/restore, erase and insert/delete of characters and lines, scroll regions (DECSTBM), SU/SD,
// tab stops, SGR (16/256/true colour, bold, dim, italic, underline, blink, reverse, hidden, strike), autowrap
// with the deferred-wrap quirk, origin and insert modes, DEC line drawing (ESC ( 0), the alternate screen
// (47/1047/1049), bracketed-paste and cursor-key mode flags, OSC 0/2 titles, DSR/DA replies, and a scrollback
// ring of whole lines. Wide characters take two cells (WIDE then CONT); combining marks are dropped.
// `resize` keeps rows and clips columns (no reflow). Storage is one arena allocation sized by the maximum
// dimensions given to `new`; the live size may be anything up to those maxima.

use e.mem
use e.text.encoding

type Cell = struct { ch: u32, fg: u32, bg: u32, attr: u32 }
type Term = struct {
    cols: usize, rows: usize, max_cols: usize, max_rows: usize, sb_cap: usize, sb_head: usize, sb_len: usize,
    cells: []Cell, flags: []u32, tabs: []bool, alt: bool,
    cx: usize, cy: usize, wrap_pending: bool, top: usize, bottom: usize,
    pen_fg: u32, pen_bg: u32, pen_attr: u32, graphics: bool,
    saved_x: usize, saved_y: usize, saved_fg: u32, saved_bg: u32, saved_attr: u32, saved_pending: bool, saved_origin: bool, saved_graphics: bool,
    autowrap: bool, origin: bool, insert: bool, newline_mode: bool, cursor_visible: bool, app_cursor: bool, bracketed_paste: bool, mouse_mode: u32, mouse_sgr: bool,
    state: u32, params: [16]u32, np: usize, pseen: bool, private: u32, inter: u32,
    utf_cp: u32, utf_need: u32, last_ch: u32,
    osc: [256]u8, osc_len: usize, title: [128]u8, title_len: usize,
    out: [256]u8, out_len: usize, bells: u32
}
error Invalid

const BOLD: u32 = 1u32
const DIM: u32 = 2u32
const ITALIC: u32 = 4u32
const UNDERLINE: u32 = 8u32
const BLINK: u32 = 16u32
const REVERSE: u32 = 32u32
const HIDDEN: u32 = 64u32
const STRIKE: u32 = 128u32
const WIDE: u32 = 256u32
const CONT: u32 = 512u32
const COLOR_INDEXED: u32 = 16777216u32
const COLOR_RGB: u32 = 33554432u32
const LINE_WRAPPED: u32 = 1u32

const S_GROUND: u32 = 0u32
const S_ESC: u32 = 1u32
const S_ESC_INT: u32 = 2u32
const S_CSI: u32 = 3u32
const S_CSI_INT: u32 = 4u32
const S_CSI_IGN: u32 = 5u32
const S_OSC: u32 = 6u32
const S_STR: u32 = 7u32

fn min_usize(x: usize, y: usize) -> usize {
    if x < y { ret x }
    ret y
}

fn max_usize(x: usize, y: usize) -> usize {
    if x > y { ret x }
    ret y
}

// An indexed palette colour (0..255) in a Cell's fg/bg.
fn indexed(i: u32) -> u32 { ret COLOR_INDEXED | i }
// A true colour 0xRRGGBB in a Cell's fg/bg.
fn rgb(v: u32) -> u32 { ret COLOR_RGB | (v & 16777215u32) }

// xterm's 256-colour palette as 0xRRGGBB.
fn palette_rgb(i: u32) -> u32 {
    if i < 16u32 {
        if i == 0u32 { ret 0x000000u32 }
        if i == 1u32 { ret 0xCD0000u32 }
        if i == 2u32 { ret 0x00CD00u32 }
        if i == 3u32 { ret 0xCDCD00u32 }
        if i == 4u32 { ret 0x0000EEu32 }
        if i == 5u32 { ret 0xCD00CDu32 }
        if i == 6u32 { ret 0x00CDCDu32 }
        if i == 7u32 { ret 0xE5E5E5u32 }
        if i == 8u32 { ret 0x7F7F7Fu32 }
        if i == 9u32 { ret 0xFF0000u32 }
        if i == 10u32 { ret 0x00FF00u32 }
        if i == 11u32 { ret 0xFFFF00u32 }
        if i == 12u32 { ret 0x5C5CFFu32 }
        if i == 13u32 { ret 0xFF00FFu32 }
        if i == 14u32 { ret 0x00FFFFu32 }
        ret 0xFFFFFFu32
    }
    if i < 232u32 {
        let n = i - 16u32
        let rr = n / 36u32
        let gg = (n / 6u32) % 6u32
        let bb = n % 6u32
        var r2 = 0u32
        var g2 = 0u32
        var b2 = 0u32
        if rr > 0u32 { r2 = 55u32 + 40u32 * rr }
        if gg > 0u32 { g2 = 55u32 + 40u32 * gg }
        if bb > 0u32 { b2 = 55u32 + 40u32 * bb }
        ret (r2 << 16u32) | (g2 << 8u32) | b2
    }
    let v = 8u32 + 10u32 * (i - 232u32)
    ret (v << 16u32) | (v << 8u32) | v
}

// A cell colour as 0xRRGGBB; `fallback` stands for the default colour.
fn resolve_color(c: u32, fallback: u32) -> u32 {
    if (c & COLOR_RGB) != 0u32 { ret c & 16777215u32 }
    if (c & COLOR_INDEXED) != 0u32 { ret palette_rgb(c & 255u32) }
    ret fallback
}

// Display columns of a scalar: 0 (control, combining, joiner), 1 or 2.
fn char_width(cp: u32) -> u32 {
    if cp < 32u32 || (cp >= 127u32 && cp < 160u32) { ret 0u32 }
    if cp < 768u32 { ret 1u32 }
    if cp <= 879u32 { ret 0u32 }
    if cp >= 8203u32 && cp <= 8207u32 { ret 0u32 }
    if cp >= 8400u32 && cp <= 8447u32 { ret 0u32 }
    if cp >= 65024u32 && cp <= 65039u32 { ret 0u32 }
    if cp >= 4352u32 && cp <= 4447u32 { ret 2u32 }
    if cp >= 11904u32 && cp <= 42191u32 { ret 2u32 }
    if cp >= 44032u32 && cp <= 55203u32 { ret 2u32 }
    if cp >= 63744u32 && cp <= 64255u32 { ret 2u32 }
    if cp >= 65040u32 && cp <= 65049u32 { ret 2u32 }
    if cp >= 65072u32 && cp <= 65135u32 { ret 2u32 }
    if cp >= 65280u32 && cp <= 65376u32 { ret 2u32 }
    if cp >= 65504u32 && cp <= 65510u32 { ret 2u32 }
    if cp >= 127744u32 && cp <= 128591u32 { ret 2u32 }
    if cp >= 129280u32 && cp <= 129791u32 { ret 2u32 }
    if cp >= 131072u32 && cp <= 262141u32 { ret 2u32 }
    ret 1u32
}

fn dec_graphics(cp: u32) -> u32 {
    if cp == 96u32 { ret 9670u32 }
    if cp == 97u32 { ret 9618u32 }
    if cp == 126u32 { ret 183u32 }
    if cp < 106u32 || cp > 120u32 { ret cp }
    if cp == 106u32 { ret 9496u32 }
    if cp == 107u32 { ret 9488u32 }
    if cp == 108u32 { ret 9484u32 }
    if cp == 109u32 { ret 9492u32 }
    if cp == 110u32 { ret 9532u32 }
    if cp == 111u32 { ret 9146u32 }
    if cp == 112u32 { ret 9147u32 }
    if cp == 113u32 { ret 9472u32 }
    if cp == 114u32 { ret 9148u32 }
    if cp == 115u32 { ret 9149u32 }
    if cp == 116u32 { ret 9500u32 }
    if cp == 117u32 { ret 9508u32 }
    if cp == 118u32 { ret 9524u32 }
    if cp == 119u32 { ret 9516u32 }
    ret 9474u32
}

fn blank_cell(bg: u32) -> Cell { ret Cell { ch: 32u32, fg: 0u32, bg: bg, attr: 0u32 } }

fn live_base(t: *const Term, r: usize) -> usize {
    var rr = r
    if t.alt { rr += t.max_rows }
    ret rr * t.max_cols
}

fn sb_slot(t: *const Term, i: usize) -> usize { ret (t.sb_head + i) % t.sb_cap }

// Index (into cells / flags) of a line of the whole buffer: 0..sb_len are scrollback, then the live rows.
fn line_row(t: *const Term, i: usize) -> usize {
    if i < t.sb_len { ret 2usize * t.max_rows + sb_slot(t, i) }
    var r = i - t.sb_len
    if t.alt { r += t.max_rows }
    ret r
}

fn clear_row(t: *Term, r: usize, bg: u32) {
    let base = live_base(t, r)
    var x = 0usize
    while x < t.max_cols {
        t.cells[base + x] = blank_cell(bg)
        x += 1usize
    }
    var fr = r
    if t.alt { fr += t.max_rows }
    t.flags[fr] = 0u32
}

fn copy_row(t: *Term, src_row: usize, dst_row: usize) {
    let sb = live_base(t, src_row)
    let db = live_base(t, dst_row)
    var x = 0usize
    while x < t.max_cols {
        t.cells[db + x] = t.cells[sb + x]
        x += 1usize
    }
    var sf = src_row
    var df = dst_row
    if t.alt {
        sf += t.max_rows
        df += t.max_rows
    }
    t.flags[df] = t.flags[sf]
}

fn push_scrollback(t: *Term, r: usize) {
    if t.sb_cap == 0usize || t.alt { ret }
    var slot = 0usize
    if t.sb_len < t.sb_cap {
        slot = (t.sb_head + t.sb_len) % t.sb_cap
        t.sb_len += 1usize
    } else {
        slot = t.sb_head
        t.sb_head = (t.sb_head + 1usize) % t.sb_cap
    }
    let db = (2usize * t.max_rows + slot) * t.max_cols
    let sb = live_base(t, r)
    var x = 0usize
    while x < t.max_cols {
        t.cells[db + x] = t.cells[sb + x]
        x += 1usize
    }
    t.flags[2usize * t.max_rows + slot] = t.flags[r]
}

// Scroll rows top..=bot up by n; `keep` sends the lines leaving the top of the screen to scrollback.
fn scroll_up(t: *Term, top_row: usize, bot_row: usize, n: usize, keep: bool) {
    let height = bot_row - top_row + 1usize
    let k = min_usize(n, height)
    if k == 0usize { ret }
    if keep && top_row == 0usize {
        var i = 0usize
        while i < k {
            push_scrollback(t, i)
            i += 1usize
        }
    }
    var r = top_row
    while r + k <= bot_row {
        copy_row(t, r + k, r)
        r += 1usize
    }
    while r <= bot_row {
        clear_row(t, r, t.pen_bg)
        r += 1usize
    }
}

fn scroll_down(t: *Term, top_row: usize, bot_row: usize, n: usize) {
    let height = bot_row - top_row + 1usize
    let k = min_usize(n, height)
    if k == 0usize { ret }
    var r = bot_row
    while r >= top_row + k {
        copy_row(t, r - k, r)
        r -= 1usize
    }
    var j = 0usize
    while j < k {
        clear_row(t, top_row + j, t.pen_bg)
        j += 1usize
    }
}

fn index_down(t: *Term) {
    if t.cy == t.bottom {
        scroll_up(t, t.top, t.bottom, 1usize, true)
    } else if t.cy + 1usize < t.rows {
        t.cy += 1usize
    }
}

fn reverse_index(t: *Term) {
    if t.cy == t.top {
        scroll_down(t, t.top, t.bottom, 1usize)
    } else if t.cy > 0usize {
        t.cy -= 1usize
    }
}

fn set_row_flag(t: *Term, r: usize, f: u32) {
    var fr = r
    if t.alt { fr += t.max_rows }
    t.flags[fr] = t.flags[fr] | f
}

// Break a wide character that a write at column x would cut in half.
fn unwide(t: *Term, r: usize, x: usize) {
    let base = live_base(t, r)
    let c = t.cells[base + x]
    if (c.attr & CONT) != 0u32 && x > 0usize {
        t.cells[base + x - 1usize] = blank_cell(c.bg)
    }
    if (c.attr & WIDE) != 0u32 && x + 1usize < t.max_cols {
        t.cells[base + x + 1usize] = blank_cell(c.bg)
    }
}

fn fix_row(t: *Term, r: usize) {
    let base = live_base(t, r)
    var x = 0usize
    while x < t.cols {
        let c = t.cells[base + x]
        if (c.attr & CONT) != 0u32 {
            if x == 0usize || (t.cells[base + x - 1usize].attr & WIDE) == 0u32 { t.cells[base + x] = blank_cell(c.bg) }
        } else if (c.attr & WIDE) != 0u32 {
            if x + 1usize >= t.cols || (t.cells[base + x + 1usize].attr & CONT) == 0u32 { t.cells[base + x] = blank_cell(c.bg) }
        }
        x += 1usize
    }
}

// Erase columns x0..x1 (exclusive) of a live row with the current background.
fn erase_span(t: *Term, r: usize, x0: usize, x1: usize) {
    if x0 >= x1 { ret }
    unwide(t, r, x0)
    if x1 < t.max_cols { unwide(t, r, x1 - 1usize) }
    let base = live_base(t, r)
    var x = x0
    while x < x1 {
        t.cells[base + x] = blank_cell(t.pen_bg)
        x += 1usize
    }
}

fn put_cell(t: *Term, ch: u32, w: u32) {
    let base = live_base(t, t.cy)
    unwide(t, t.cy, t.cx)
    var a = t.pen_attr
    if w == 2u32 {
        unwide(t, t.cy, t.cx + 1usize)
        a = a | WIDE
    }
    t.cells[base + t.cx] = Cell { ch: ch, fg: t.pen_fg, bg: t.pen_bg, attr: a }
    if w == 2u32 {
        t.cells[base + t.cx + 1usize] = Cell { ch: 0u32, fg: t.pen_fg, bg: t.pen_bg, attr: t.pen_attr | CONT }
    }
}

fn insert_blank(t: *Term, n: usize) {
    let base = live_base(t, t.cy)
    let k = min_usize(n, t.cols - t.cx)
    var x = t.cols
    while x > t.cx + k {
        x -= 1usize
        t.cells[base + x] = t.cells[base + x - k]
    }
    var i = 0usize
    while i < k {
        t.cells[base + t.cx + i] = blank_cell(t.pen_bg)
        i += 1usize
    }
    fix_row(t, t.cy)
}

fn delete_chars(t: *Term, n: usize) {
    let base = live_base(t, t.cy)
    let k = min_usize(n, t.cols - t.cx)
    var x = t.cx
    while x + k < t.cols {
        t.cells[base + x] = t.cells[base + x + k]
        x += 1usize
    }
    while x < t.cols {
        t.cells[base + x] = blank_cell(t.pen_bg)
        x += 1usize
    }
    fix_row(t, t.cy)
}

fn put_char(t: *Term, cp_in: u32) {
    var cp = cp_in
    if t.graphics { cp = dec_graphics(cp) }
    let w = char_width(cp)
    if w == 0u32 { ret }
    t.last_ch = cp
    if t.wrap_pending {
        t.wrap_pending = false
        if t.autowrap {
            set_row_flag(t, t.cy, LINE_WRAPPED)
            t.cx = 0usize
            index_down(t)
        }
    }
    if w == 2u32 && t.cx + 1usize >= t.cols {
        if !t.autowrap { ret }
        erase_span(t, t.cy, t.cx, t.cols)
        set_row_flag(t, t.cy, LINE_WRAPPED)
        t.cx = 0usize
        index_down(t)
    }
    if t.insert { insert_blank(t, usize(w)) }
    put_cell(t, cp, w)
    t.cx += usize(w)
    if t.cx >= t.cols {
        t.cx = t.cols - 1usize
        t.wrap_pending = true
    }
}

fn queue_byte(t: *Term, b: u8) {
    if t.out_len < 256usize {
        t.out[t.out_len] = b
        t.out_len += 1usize
    }
}

fn queue_str(t: *Term, s: str) {
    var i = 0usize
    while i < s.len {
        queue_byte(t, s[i])
        i += 1usize
    }
}

fn queue_num(t: *Term, v: usize) {
    var digits: [20]u8 = zero
    var n = 0usize
    var x = v
    if x == 0usize {
        digits[0] = 48u8
        n = 1usize
    }
    while x > 0usize {
        digits[n] = u8(48usize + x % 10usize)
        n += 1usize
        x = x / 10usize
    }
    while n > 0usize {
        n -= 1usize
        queue_byte(t, digits[n])
    }
}

fn param(t: *const Term, i: usize, fallback: u32) -> u32 {
    if i > t.np || !t.pseen { ret fallback }
    let v = t.params[i]
    if v == 0u32 { ret fallback }
    ret v
}

fn param_count(t: *const Term) -> usize {
    if !t.pseen { ret 0usize }
    ret t.np + 1usize
}

fn clear_params(t: *Term) {
    var i = 0usize
    while i < 16usize {
        t.params[i] = 0u32
        i += 1usize
    }
    t.np = 0usize
    t.pseen = false
    t.private = 0u32
    t.inter = 0u32
}

fn row_min(t: *const Term) -> usize {
    if t.origin { ret t.top }
    ret 0usize
}

fn row_max(t: *const Term) -> usize {
    if t.origin { ret t.bottom }
    ret t.rows - 1usize
}

fn move_to(t: *Term, r: usize, c: usize) {
    t.cy = min_usize(row_min(t) + r, row_max(t))
    t.cx = min_usize(c, t.cols - 1usize)
    t.wrap_pending = false
}

fn save_cursor(t: *Term) {
    t.saved_x = t.cx
    t.saved_y = t.cy
    t.saved_fg = t.pen_fg
    t.saved_bg = t.pen_bg
    t.saved_attr = t.pen_attr
    t.saved_pending = t.wrap_pending
    t.saved_origin = t.origin
    t.saved_graphics = t.graphics
}

fn restore_cursor(t: *Term) {
    t.cx = min_usize(t.saved_x, t.cols - 1usize)
    t.cy = min_usize(t.saved_y, t.rows - 1usize)
    t.pen_fg = t.saved_fg
    t.pen_bg = t.saved_bg
    t.pen_attr = t.saved_attr
    t.wrap_pending = t.saved_pending
    t.origin = t.saved_origin
    t.graphics = t.saved_graphics
}

fn reset_tabs(t: *Term) {
    var x = 0usize
    while x < t.max_cols {
        t.tabs[x] = x % 8usize == 0usize
        x += 1usize
    }
}

fn clear_screen_rows(t: *Term, bg: u32) {
    var r = 0usize
    while r < t.max_rows {
        clear_row(t, r, bg)
        r += 1usize
    }
}

// Back to power-on state: blank screens, no scrollback, default modes and pen, size kept.
fn reset(t: *Term) {
    t.alt = true
    clear_screen_rows(t, 0u32)
    t.alt = false
    clear_screen_rows(t, 0u32)
    t.sb_head = 0usize
    t.sb_len = 0usize
    t.cx = 0usize
    t.cy = 0usize
    t.wrap_pending = false
    t.top = 0usize
    t.bottom = t.rows - 1usize
    t.pen_fg = 0u32
    t.pen_bg = 0u32
    t.pen_attr = 0u32
    t.graphics = false
    t.autowrap = true
    t.origin = false
    t.insert = false
    t.newline_mode = false
    t.cursor_visible = true
    t.app_cursor = false
    t.bracketed_paste = false
    t.mouse_mode = 0u32
    t.mouse_sgr = false
    t.state = S_GROUND
    t.utf_need = 0u32
    t.saved_x = 0usize
    t.saved_y = 0usize
    t.saved_fg = 0u32
    t.saved_bg = 0u32
    t.saved_attr = 0u32
    t.saved_pending = false
    t.saved_origin = false
    t.saved_graphics = false
    t.last_ch = 32u32
    t.osc_len = 0usize
    t.title_len = 0usize
    clear_params(t)
    reset_tabs(t)
}

// A terminal of `cols` x `rows` that can later be resized up to `max_cols` x `max_rows`, keeping `scrollback` lines.
fn new(a: *mem.Arena, cols: usize, rows: usize, max_cols: usize, max_rows: usize, scrollback: usize) -> (Term, err) {
    if cols == 0usize || rows == 0usize || cols > max_cols || rows > max_rows { ret (zero, Invalid) }
    let (cells, e1) = mem.alloc[Cell](a, (2usize * max_rows + scrollback) * max_cols)
    if e1 != ok { ret (zero, e1) }
    let (flags, e2) = mem.alloc[u32](a, 2usize * max_rows + scrollback)
    if e2 != ok { ret (zero, e2) }
    let (tabs, e3) = mem.alloc[bool](a, max_cols)
    if e3 != ok { ret (zero, e3) }
    var t: Term = zero
    t.cols = cols
    t.rows = rows
    t.max_cols = max_cols
    t.max_rows = max_rows
    t.sb_cap = scrollback
    t.cells = cells
    t.flags = flags
    t.tabs = tabs
    var i = 0usize
    while i < flags.len {
        flags[i] = 0u32
        i += 1usize
    }
    var j = 0usize
    while j < cells.len {
        cells[j] = blank_cell(0u32)
        j += 1usize
    }
    reset(&t)
    ret (t, ok)
}

fn set_alt(t: *Term, on: bool, save: bool) {
    if on == t.alt { ret }
    if on {
        if save { save_cursor(t) }
        t.alt = true
        var r = 0usize
        while r < t.max_rows {
            clear_row(t, r, 0u32)
            r += 1usize
        }
    } else {
        t.alt = false
        if save { restore_cursor(t) }
    }
    t.wrap_pending = false
}

fn set_mode(t: *Term, private: bool, mode: u32, on: bool) {
    if !private {
        if mode == 4u32 { t.insert = on }
        if mode == 20u32 { t.newline_mode = on }
        ret
    }
    if mode == 1u32 { t.app_cursor = on } else if mode == 6u32 {
        t.origin = on
        move_to(t, 0usize, 0usize)
    } else if mode == 7u32 { t.autowrap = on } else if mode == 25u32 { t.cursor_visible = on } else if mode == 47u32 || mode == 1047u32 { set_alt(t, on, false) } else if mode == 1049u32 { set_alt(t, on, true) } else if mode == 2004u32 { t.bracketed_paste = on } else if mode == 1006u32 { t.mouse_sgr = on } else if mode == 9u32 || mode == 1000u32 || mode == 1002u32 || mode == 1003u32 {
        if on { t.mouse_mode = mode } else { t.mouse_mode = 0u32 }
    }
}

fn apply_sgr(t: *Term) {
    let n = param_count(t)
    if n == 0usize {
        t.pen_fg = 0u32
        t.pen_bg = 0u32
        t.pen_attr = 0u32
        ret
    }
    var i = 0usize
    while i < n {
        let p = t.params[i]
        if p == 0u32 {
            t.pen_fg = 0u32
            t.pen_bg = 0u32
            t.pen_attr = 0u32
        } else if p == 1u32 { t.pen_attr = t.pen_attr | BOLD } else if p == 2u32 { t.pen_attr = t.pen_attr | DIM } else if p == 3u32 { t.pen_attr = t.pen_attr | ITALIC } else if p == 4u32 || p == 21u32 { t.pen_attr = t.pen_attr | UNDERLINE } else if p == 5u32 || p == 6u32 { t.pen_attr = t.pen_attr | BLINK } else if p == 7u32 { t.pen_attr = t.pen_attr | REVERSE } else if p == 8u32 { t.pen_attr = t.pen_attr | HIDDEN } else if p == 9u32 { t.pen_attr = t.pen_attr | STRIKE } else if p == 22u32 { t.pen_attr = t.pen_attr & (4294967295u32 - BOLD - DIM) } else if p == 23u32 { t.pen_attr = t.pen_attr & (4294967295u32 - ITALIC) } else if p == 24u32 { t.pen_attr = t.pen_attr & (4294967295u32 - UNDERLINE) } else if p == 25u32 { t.pen_attr = t.pen_attr & (4294967295u32 - BLINK) } else if p == 27u32 { t.pen_attr = t.pen_attr & (4294967295u32 - REVERSE) } else if p == 28u32 { t.pen_attr = t.pen_attr & (4294967295u32 - HIDDEN) } else if p == 29u32 { t.pen_attr = t.pen_attr & (4294967295u32 - STRIKE) } else if p >= 30u32 && p <= 37u32 { t.pen_fg = indexed(p - 30u32) } else if p == 39u32 { t.pen_fg = 0u32 } else if p >= 40u32 && p <= 47u32 { t.pen_bg = indexed(p - 40u32) } else if p == 49u32 { t.pen_bg = 0u32 } else if p >= 90u32 && p <= 97u32 { t.pen_fg = indexed(p - 90u32 + 8u32) } else if p >= 100u32 && p <= 107u32 { t.pen_bg = indexed(p - 100u32 + 8u32) } else if p == 38u32 || p == 48u32 {
            var col = 0u32
            var used = 0usize
            if i + 2usize < n && t.params[i + 1usize] == 5u32 {
                col = indexed(t.params[i + 2usize] & 255u32)
                used = 2usize
            } else if i + 4usize < n && t.params[i + 1usize] == 2u32 {
                let rv = t.params[i + 2usize] & 255u32
                let gv = t.params[i + 3usize] & 255u32
                let bv = t.params[i + 4usize] & 255u32
                col = rgb((rv << 16u32) | (gv << 8u32) | bv)
                used = 4usize
            }
            if used > 0usize {
                if p == 38u32 { t.pen_fg = col } else { t.pen_bg = col }
                i += used
            } else {
                i = n
            }
        }
        i += 1usize
    }
}

fn erase_display(t: *Term, mode: u32) {
    if mode == 0u32 {
        erase_span(t, t.cy, t.cx, t.cols)
        var r = t.cy + 1usize
        while r < t.rows {
            clear_row(t, r, t.pen_bg)
            r += 1usize
        }
    } else if mode == 1u32 {
        var r = 0usize
        while r < t.cy {
            clear_row(t, r, t.pen_bg)
            r += 1usize
        }
        erase_span(t, t.cy, 0usize, t.cx + 1usize)
    } else if mode == 2u32 {
        var r = 0usize
        while r < t.rows {
            clear_row(t, r, t.pen_bg)
            r += 1usize
        }
    } else if mode == 3u32 {
        t.sb_head = 0usize
        t.sb_len = 0usize
    }
}

fn erase_line(t: *Term, mode: u32) {
    if mode == 0u32 { erase_span(t, t.cy, t.cx, t.cols) } else if mode == 1u32 { erase_span(t, t.cy, 0usize, t.cx + 1usize) } else if mode == 2u32 { erase_span(t, t.cy, 0usize, t.cols) }
}

fn next_tab(t: *const Term, x: usize) -> usize {
    var c = x + 1usize
    while c < t.cols - 1usize && !t.tabs[c] { c += 1usize }
    ret min_usize(c, t.cols - 1usize)
}

fn prev_tab(t: *const Term, x: usize) -> usize {
    var c = x
    while c > 0usize {
        c -= 1usize
        if t.tabs[c] { ret c }
    }
    ret 0usize
}

fn dispatch_csi(t: *Term, f: u32) {
    let priv = t.private == 63u32
    if t.private != 0u32 && !priv {
        if f != 99u32 { ret }
    }
    let n1 = usize(param(t, 0usize, 1u32))
    let cnt = param_count(t)
    if f == 65u32 { t.cy = max_usize(row_min(t), t.cy - min_usize(n1, t.cy))
        t.wrap_pending = false } else if f == 66u32 || f == 101u32 { t.cy = min_usize(t.cy + n1, row_max(t))
        t.wrap_pending = false } else if f == 67u32 || f == 97u32 { t.cx = min_usize(t.cx + n1, t.cols - 1usize)
        t.wrap_pending = false } else if f == 68u32 { t.cx = t.cx - min_usize(n1, t.cx)
        t.wrap_pending = false } else if f == 69u32 { t.cy = min_usize(t.cy + n1, row_max(t))
        t.cx = 0usize
        t.wrap_pending = false } else if f == 70u32 { t.cy = max_usize(row_min(t), t.cy - min_usize(n1, t.cy))
        t.cx = 0usize
        t.wrap_pending = false } else if f == 71u32 || f == 96u32 { t.cx = min_usize(n1 - 1usize, t.cols - 1usize)
        t.wrap_pending = false } else if f == 72u32 || f == 102u32 {
        let rr = usize(param(t, 0usize, 1u32)) - 1usize
        let cc = usize(param(t, 1usize, 1u32)) - 1usize
        move_to(t, rr, cc)
    } else if f == 73u32 {
        var k = 0usize
        while k < n1 {
            t.cx = next_tab(t, t.cx)
            k += 1usize
        }
        t.wrap_pending = false
    } else if f == 90u32 {
        var k = 0usize
        while k < n1 {
            t.cx = prev_tab(t, t.cx)
            k += 1usize
        }
        t.wrap_pending = false
    } else if f == 74u32 { erase_display(t, param(t, 0usize, 0u32)) } else if f == 75u32 { erase_line(t, param(t, 0usize, 0u32)) } else if f == 76u32 {
        if t.cy >= t.top && t.cy <= t.bottom {
            scroll_down(t, t.cy, t.bottom, n1)
            t.cx = 0usize
            t.wrap_pending = false
        }
    } else if f == 77u32 {
        if t.cy >= t.top && t.cy <= t.bottom {
            scroll_up(t, t.cy, t.bottom, n1, false)
            t.cx = 0usize
            t.wrap_pending = false
        }
    } else if f == 64u32 { insert_blank(t, n1) } else if f == 80u32 { delete_chars(t, n1) } else if f == 88u32 { erase_span(t, t.cy, t.cx, min_usize(t.cx + n1, t.cols)) } else if f == 83u32 { scroll_up(t, t.top, t.bottom, n1, true) } else if f == 84u32 { scroll_down(t, t.top, t.bottom, n1) } else if f == 100u32 {
        t.cy = min_usize(row_min(t) + n1 - 1usize, row_max(t))
        t.wrap_pending = false
    } else if f == 98u32 {
        var k = 0usize
        while k < n1 && k < 65536usize {
            put_char(t, t.last_ch)
            k += 1usize
        }
    } else if f == 103u32 {
        let m = param(t, 0usize, 0u32)
        if m == 0u32 { t.tabs[t.cx] = false } else if m == 3u32 {
            var x = 0usize
            while x < t.max_cols {
                t.tabs[x] = false
                x += 1usize
            }
        }
    } else if f == 104u32 || f == 108u32 {
        var k = 0usize
        while k < cnt {
            set_mode(t, priv, t.params[k], f == 104u32)
            k += 1usize
        }
    } else if f == 109u32 { apply_sgr(t) } else if f == 110u32 {
        let m = param(t, 0usize, 0u32)
        if m == 5u32 { queue_str(t, "\x1b[0n") } else if m == 6u32 {
            queue_str(t, "\x1b[")
            queue_num(t, t.cy - row_min(t) + 1usize)
            queue_byte(t, 59u8)
            queue_num(t, t.cx + 1usize)
            queue_byte(t, 82u8)
        }
    } else if f == 99u32 {
        if t.private == 0u32 && param(t, 0usize, 0u32) == 0u32 { queue_str(t, "\x1b[?62;22c") } else if t.private == 62u32 { queue_str(t, "\x1b[>0;0;0c") }
    } else if f == 114u32 {
        if t.inter == 0u32 && t.private == 0u32 {
            let tp = usize(param(t, 0usize, 1u32)) - 1usize
            let bt = usize(param(t, 1usize, u32(t.rows))) - 1usize
            if tp < bt && bt < t.rows {
                t.top = tp
                t.bottom = bt
            } else {
                t.top = 0usize
                t.bottom = t.rows - 1usize
            }
            move_to(t, 0usize, 0usize)
        }
    } else if f == 115u32 { save_cursor(t) } else if f == 117u32 { restore_cursor(t) }
}

fn dispatch_esc(t: *Term, f: u32) {
    if t.inter == 0u32 {
        if f == 55u32 { save_cursor(t) } else if f == 56u32 { restore_cursor(t) } else if f == 68u32 { index_down(t)
            t.wrap_pending = false } else if f == 69u32 {
            index_down(t)
            t.cx = 0usize
            t.wrap_pending = false
        } else if f == 77u32 { reverse_index(t)
            t.wrap_pending = false } else if f == 72u32 { t.tabs[t.cx] = true } else if f == 99u32 { reset(t) }
    } else if t.inter == 40u32 {
        t.graphics = f == 48u32
    } else if t.inter == 35u32 {
        if f == 56u32 {
            var r = 0usize
            while r < t.rows {
                var x = 0usize
                let base = live_base(t, r)
                while x < t.cols {
                    t.cells[base + x] = Cell { ch: 69u32, fg: 0u32, bg: 0u32, attr: 0u32 }
                    x += 1usize
                }
                r += 1usize
            }
        }
    }
}

fn dispatch_osc(t: *Term) {
    // "<n>;<payload>": 0 and 2 set the title; everything else is dropped.
    var i = 0usize
    var num = 0usize
    while i < t.osc_len && t.osc[i] >= 48u8 && t.osc[i] <= 57u8 {
        num = num * 10usize + usize(t.osc[i]) - 48usize
        i += 1usize
    }
    if i >= t.osc_len || t.osc[i] != 59u8 { ret }
    i += 1usize
    if num == 0usize || num == 2usize {
        var n = 0usize
        while i < t.osc_len && n < 128usize {
            t.title[n] = t.osc[i]
            n += 1usize
            i += 1usize
        }
        t.title_len = n
    }
}

fn execute_c0(t: *Term, b: u32) {
    if b == 7u32 { t.bells += 1u32 } else if b == 8u32 {
        if t.cx > 0usize { t.cx -= 1usize }
        t.wrap_pending = false
    } else if b == 9u32 {
        t.cx = next_tab(t, t.cx)
        t.wrap_pending = false
    } else if b == 10u32 || b == 11u32 || b == 12u32 {
        index_down(t)
        if t.newline_mode { t.cx = 0usize }
        t.wrap_pending = false
    } else if b == 13u32 {
        t.cx = 0usize
        t.wrap_pending = false
    }
}

fn feed_ground(t: *Term, b: u32) {
    if t.utf_need > 0u32 {
        if (b & 192u32) == 128u32 {
            t.utf_cp = (t.utf_cp << 6u32) | (b & 63u32)
            t.utf_need -= 1u32
            if t.utf_need == 0u32 {
                var cp = t.utf_cp
                if cp > 1114111u32 || (cp >= 55296u32 && cp <= 57343u32) { cp = 65533u32 }
                put_char(t, cp)
            }
            ret
        }
        t.utf_need = 0u32
        put_char(t, 65533u32)
    }
    if b < 128u32 {
        put_char(t, b)
    } else if b >= 194u32 && b <= 223u32 {
        t.utf_cp = b & 31u32
        t.utf_need = 1u32
    } else if b >= 224u32 && b <= 239u32 {
        t.utf_cp = b & 15u32
        t.utf_need = 2u32
    } else if b >= 240u32 && b <= 244u32 {
        t.utf_cp = b & 7u32
        t.utf_need = 3u32
    } else {
        put_char(t, 65533u32)
    }
}

fn feed_byte(t: *Term, b: u32) {
    if b == 24u32 || b == 26u32 {
        t.state = S_GROUND
        t.utf_need = 0u32
        ret
    }
    if b == 27u32 {
        if t.state == S_OSC { dispatch_osc(t) }
        t.state = S_ESC
        t.utf_need = 0u32
        clear_params(t)
        ret
    }
    if t.state == S_GROUND {
        if b < 32u32 { execute_c0(t, b) } else if b != 127u32 { feed_ground(t, b) }
        ret
    }
    if t.state == S_OSC {
        if b == 7u32 {
            dispatch_osc(t)
            t.state = S_GROUND
        } else if b >= 32u32 && t.osc_len < 256usize {
            t.osc[t.osc_len] = u8(b)
            t.osc_len += 1usize
        }
        ret
    }
    if t.state == S_STR {
        if b == 7u32 { t.state = S_GROUND }
        ret
    }
    if b < 32u32 {
        execute_c0(t, b)
        ret
    }
    if t.state == S_ESC {
        if b == 91u32 {
            t.state = S_CSI
        } else if b == 93u32 {
            t.state = S_OSC
            t.osc_len = 0usize
        } else if b == 80u32 || b == 88u32 || b == 94u32 || b == 95u32 {
            t.state = S_STR
        } else if b >= 32u32 && b <= 47u32 {
            t.inter = b
            t.state = S_ESC_INT
        } else {
            dispatch_esc(t, b)
            t.state = S_GROUND
        }
        ret
    }
    if t.state == S_ESC_INT {
        if b >= 32u32 && b <= 47u32 {
            if t.inter == 0u32 { t.inter = b }
        } else {
            if b >= 48u32 && b <= 126u32 { dispatch_esc(t, b) }
            t.state = S_GROUND
        }
        ret
    }
    if t.state == S_CSI {
        if b >= 48u32 && b <= 57u32 {
            t.pseen = true
            let cur = t.params[t.np] * 10u32 + (b - 48u32)
            if cur > 65535u32 { t.params[t.np] = 65535u32 } else { t.params[t.np] = cur }
        } else if b == 59u32 || b == 58u32 {
            t.pseen = true
            if t.np < 15usize { t.np += 1usize }
        } else if b >= 60u32 && b <= 63u32 {
            if t.private == 0u32 { t.private = b }
        } else if b >= 32u32 && b <= 47u32 {
            t.inter = b
            t.state = S_CSI_INT
        } else if b >= 64u32 && b <= 126u32 {
            dispatch_csi(t, b)
            t.state = S_GROUND
        } else {
            t.state = S_CSI_IGN
        }
        ret
    }
    if t.state == S_CSI_INT {
        if b >= 64u32 && b <= 126u32 {
            dispatch_csi(t, b)
            t.state = S_GROUND
        } else if b < 32u32 || b > 47u32 {
            t.state = S_CSI_IGN
        }
        ret
    }
    // S_CSI_IGN: swallow to the final byte.
    if b >= 64u32 && b <= 126u32 { t.state = S_GROUND }
}

// Feed output bytes from the child process; sequences and UTF-8 characters may straddle calls.
fn feed(t: *Term, data: []const u8) {
    var i = 0usize
    while i < data.len {
        feed_byte(t, u32(data[i]))
        i += 1usize
    }
}

// Copy pending replies (DSR, DA) the terminal wants written back to the child; returns the byte count.
fn take_output(t: *Term, dst: []u8) -> usize {
    let n = min_usize(t.out_len, dst.len)
    var i = 0usize
    while i < n {
        dst[i] = t.out[i]
        i += 1usize
    }
    var j = n
    while j < t.out_len {
        t.out[j - n] = t.out[j]
        j += 1usize
    }
    t.out_len -= n
    ret n
}

fn blank_range(t: *Term, r: usize, x0: usize, x1: usize) {
    let base = live_base(t, r)
    var x = x0
    while x < x1 {
        t.cells[base + x] = blank_cell(0u32)
        x += 1usize
    }
}

// Change the live size (within the maxima). Rows are kept (no reflow): shrinking pushes lines above the cursor
// into scrollback, growing pulls lines back from it; columns are clipped or padded with blanks.
fn resize(t: *Term, cols: usize, rows: usize) -> err {
    if cols == 0usize || rows == 0usize || cols > t.max_cols || rows > t.max_rows { ret Invalid }
    if rows < t.rows {
        var lose_top = 0usize
        if t.cy + 1usize > rows { lose_top = t.cy + 1usize - rows }
        var k = 0usize
        while k < lose_top {
            push_scrollback(t, 0usize)
            var r = 0usize
            while r + 1usize < t.rows {
                copy_row(t, r + 1usize, r)
                r += 1usize
            }
            clear_row(t, t.rows - 1usize, 0u32)
            t.cy -= 1usize
            k += 1usize
        }
        var r2 = rows
        while r2 < t.rows {
            clear_row(t, r2, 0u32)
            r2 += 1usize
        }
    } else if rows > t.rows {
        var want = rows - t.rows
        if t.alt { want = 0usize }
        let pull = min_usize(want, t.sb_len)
        if pull > 0usize {
            // Shift the screen down by `pull` and refill the top from the newest scrollback lines.
            var r = t.rows
            while r > 0usize {
                r -= 1usize
                copy_row(t, r, r + pull)
            }
            var j = 0usize
            while j < pull {
                let src = t.sb_len - pull + j
                let sbase = (2usize * t.max_rows + sb_slot(t, src)) * t.max_cols
                let dbase = live_base(t, j)
                var x = 0usize
                while x < t.max_cols {
                    t.cells[dbase + x] = t.cells[sbase + x]
                    x += 1usize
                }
                t.flags[j] = t.flags[2usize * t.max_rows + sb_slot(t, src)]
                j += 1usize
            }
            t.sb_len -= pull
            t.cy += pull
        }
    }
    if cols < t.cols {
        var r = 0usize
        while r < t.max_rows {
            blank_range(t, r, cols, t.cols)
            r += 1usize
        }
        t.alt = !t.alt
        r = 0usize
        while r < t.max_rows {
            blank_range(t, r, cols, t.cols)
            r += 1usize
        }
        t.alt = !t.alt
    }
    t.cols = cols
    t.rows = rows
    t.top = 0usize
    t.bottom = rows - 1usize
    t.cx = min_usize(t.cx, cols - 1usize)
    t.cy = min_usize(t.cy, rows - 1usize)
    t.wrap_pending = false
    reset_tabs(t)
    ret ok
}

// Lines in the whole buffer: scrollback then live rows.
fn line_count(t: *const Term) -> usize { ret t.sb_len + t.rows }

fn line_cell(t: *const Term, i: usize, c: usize) -> Cell {
    if i >= line_count(t) || c >= t.cols { ret blank_cell(0u32) }
    var base = 0usize
    if i < t.sb_len {
        base = (2usize * t.max_rows + sb_slot(t, i)) * t.max_cols
    } else {
        base = live_base(t, i - t.sb_len)
    }
    ret t.cells[base + c]
}

fn line_wrapped(t: *const Term, i: usize) -> bool {
    if i >= line_count(t) { ret false }
    ret (t.flags[line_row(t, i)] & LINE_WRAPPED) != 0u32
}

// The line's text as UTF-8 with trailing blanks trimmed; wide characters once. Returns bytes written.
fn line_text(t: *const Term, i: usize, dst: []u8) -> usize {
    var last = 0usize
    var c = 0usize
    while c < t.cols {
        let cl = line_cell(t, i, c)
        if (cl.attr & CONT) == 0u32 && cl.ch != 32u32 && cl.ch != 0u32 { last = c + 1usize }
        c += 1usize
    }
    var n = 0usize
    c = 0usize
    while c < last {
        let cl = line_cell(t, i, c)
        if (cl.attr & CONT) == 0u32 {
            var ch = cl.ch
            if ch == 0u32 { ch = 32u32 }
            if n + encoding.utf8_length(ch) > dst.len { ret n }
            n += encoding.write_utf8(ch, dst, n)
        }
        c += 1usize
    }
    ret n
}

// Copy the visible window (`rows` x `cols`, row-major) scrolled `offset` lines back into history (clamped; the
// alternate screen has none). Returns the cells written, `rows * cols` when `out` is large enough.
fn snapshot(t: *const Term, offset: usize, out: []Cell) -> usize {
    var back = min_usize(offset, t.sb_len)
    if t.alt { back = 0usize }
    var n = 0usize
    var v = 0usize
    while v < t.rows {
        let line = t.sb_len - back + v
        var c = 0usize
        while c < t.cols {
            if n >= out.len { ret n }
            out[n] = line_cell(t, line, c)
            n += 1usize
            c += 1usize
        }
        v += 1usize
    }
    ret n
}
