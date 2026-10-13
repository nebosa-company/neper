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
    autowrap: bool, origin: bool, insert: bool, newline_mode: bool, cursor_visible: bool, app_cursor: bool, bracketed_paste: bool, mouse_mode: u32, mouse_sgr: bool, focus_events: bool,
    state: u32, params: [16]u32, np: usize, pseen: bool, private: u32, inter: u32,
    utf_cp: u32, utf_need: u32, last_ch: u32,
    osc: [256]u8, osc_len: usize, title: [128]u8, title_len: usize,
    out: [256]u8, out_len: usize, bells: u32,
    app_keypad: bool, mouse_utf8: bool, mouse_urxvt: bool, modify_other: u32, kitty: [32]u32, kitty_n: [2]usize, sb_dropped: usize
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
        t.sb_dropped += 1usize
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
    t.sb_dropped += t.sb_len + t.rows
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
    t.focus_events = false
    t.app_keypad = false
    t.mouse_utf8 = false
    t.mouse_urxvt = false
    t.modify_other = 0u32
    t.kitty_n[0usize] = 0usize
    t.kitty_n[1usize] = 0usize
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
    t.sb_dropped = 0usize
    ret (t, ok)
}

fn set_alt(t: *Term, on: bool, save: bool) {
    if on == t.alt { ret }
    if on {
        if save { save_cursor(t) }
        t.alt = true
        t.kitty_n[1usize] = 0usize
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
    } else if mode == 7u32 { t.autowrap = on } else if mode == 25u32 { t.cursor_visible = on } else if mode == 47u32 || mode == 1047u32 { set_alt(t, on, false) } else if mode == 1049u32 { set_alt(t, on, true) } else if mode == 2004u32 { t.bracketed_paste = on } else if mode == 66u32 { t.app_keypad = on } else if mode == 1005u32 {
        t.mouse_utf8 = on
        t.mouse_sgr = false
        t.mouse_urxvt = false
    } else if mode == 1006u32 {
        t.mouse_sgr = on
        t.mouse_utf8 = false
        t.mouse_urxvt = false
    } else if mode == 1015u32 {
        t.mouse_urxvt = on
        t.mouse_utf8 = false
        t.mouse_sgr = false
    } else if mode == 1004u32 { t.focus_events = on } else if mode == 9u32 || mode == 1000u32 || mode == 1002u32 || mode == 1003u32 {
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

// Kitty keyboard protocol flags (one stack per screen, 16 deep; the oldest entry is evicted by a push on a full
// stack) and xterm's modifyOtherKeys level, set by CSI > ... u / CSI < ... u / CSI = ... u / CSI > 4 ; n m and
// answered by CSI ? u / CSI ? 4 m.
fn kitty_flags(t: *const Term) -> u32 {
    var s = 0usize
    if t.alt { s = 1usize }
    if t.kitty_n[s] == 0usize { ret 0u32 }
    ret t.kitty[s * 16usize + t.kitty_n[s] - 1usize]
}

fn kitty_push(t: *Term, flags: u32) {
    var s = 0usize
    if t.alt { s = 1usize }
    let base = s * 16usize
    if t.kitty_n[s] == 16usize {
        var i = 1usize
        while i < 16usize {
            t.kitty[base + i - 1usize] = t.kitty[base + i]
            i += 1usize
        }
        t.kitty_n[s] = 15usize
    }
    t.kitty[base + t.kitty_n[s]] = flags & 31u32
    t.kitty_n[s] += 1usize
}

fn kitty_set(t: *Term, flags: u32, mode: u32) {
    var s = 0usize
    if t.alt { s = 1usize }
    if t.kitty_n[s] == 0usize { kitty_push(t, 0u32) }
    let at = s * 16usize + t.kitty_n[s] - 1usize
    let f = flags & 31u32
    if mode == 1u32 { t.kitty[at] = f } else if mode == 2u32 { t.kitty[at] = t.kitty[at] | f } else if mode == 3u32 { t.kitty[at] = t.kitty[at] & (31u32 - f) }
}

fn dispatch_csi_keys(t: *Term, f: u32) {
    if f == 117u32 {
        if t.private == 63u32 {
            queue_str(t, "\x1b[?")
            queue_num(t, usize(kitty_flags(t)))
            queue_byte(t, 117u8)
        } else if t.private == 62u32 {
            kitty_push(t, param(t, 0usize, 0u32))
        } else if t.private == 60u32 {
            var s = 0usize
            if t.alt { s = 1usize }
            let n = usize(param(t, 0usize, 1u32))
            if n >= t.kitty_n[s] { t.kitty_n[s] = 0usize } else { t.kitty_n[s] -= n }
        } else if t.private == 61u32 {
            kitty_set(t, param(t, 0usize, 0u32), param(t, 1usize, 1u32))
        }
    } else if t.private == 62u32 {
        if param(t, 0usize, 0u32) == 4u32 {
            var lv = param(t, 1usize, 0u32)
            if lv > 2u32 { lv = 0u32 }
            t.modify_other = lv
        }
    } else if t.private == 63u32 {
        if param(t, 0usize, 0u32) == 4u32 {
            queue_str(t, "\x1b[>4;")
            queue_num(t, usize(t.modify_other))
            queue_byte(t, 109u8)
        }
    }
}

fn dispatch_csi(t: *Term, f: u32) {
    let priv = t.private == 63u32
    if t.private != 0u32 && (f == 109u32 || f == 117u32) {
        dispatch_csi_keys(t, f)
        ret
    }
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
            t.wrap_pending = false } else if f == 72u32 { t.tabs[t.cx] = true } else if f == 99u32 { reset(t) } else if f == 61u32 { t.app_keypad = true } else if f == 62u32 { t.app_keypad = false }
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

// ---- reflow on resize (D3501) -----------------------------------------------------------------------------
// `resize` keeps rows and clips columns. `resize_reflow` re-wraps instead: consecutive buffer lines joined by
// LINE_WRAPPED form one logical line, which is laid out again at the new width. A logical line's trailing plain
// blanks (blank character, default background, no attribute) are dropped; a wide character never straddles the
// right margin (a blank pads the row, which is then wrapped); a blank that only pads a wide character moved to
// the next row is dropped when joining. The cursor keeps its place in its logical line (a pending wrap counts as
// one cell past the margin). The live screen is the last `rows` lines of the result, moved up only as far as
// keeps the cursor on it (lines below are then dropped); the lines above it become scrollback, the oldest lost
// past `scrollback`. The alternate screen has no reflow.

const NO_CURSOR: usize = 18446744073709551615usize

fn plain_blank(c: Cell) -> bool {
    ret (c.ch == 32u32 || c.ch == 0u32) && c.bg == 0u32 && c.attr == 0u32
}

// Cells of row j kept when the logical line ends at row `last`: the final cell is dropped when it is a blank
// that only pads a wide character which starts the next row.
fn row_kept(t: *const Term, j: usize, last: usize) -> usize {
    if j < last {
        let tail = line_cell(t, j, t.cols - 1usize)
        let head = line_cell(t, j + 1usize, 0usize)
        if (tail.ch == 32u32 || tail.ch == 0u32) && tail.attr == 0u32 && (head.attr & WIDE) != 0u32 { ret t.cols - 1usize }
    }
    ret t.cols
}

// (cells kept, one past the last cell that is not a plain blank) over rows a..=b.
fn seq_scan(t: *const Term, a: usize, b: usize) -> (usize, usize) {
    var n = 0usize
    var last_nb = 0usize
    var j = a
    while j <= b {
        let kept = row_kept(t, j, b)
        var c = 0usize
        while c < kept {
            n += 1usize
            if !plain_blank(line_cell(t, j, c)) { last_nb = n }
            c += 1usize
        }
        j += 1usize
    }
    ret (n, last_nb)
}

// Lay the logical line made of rows a..=b out at `ncols`: (rows used, row and column of cell index `cur_idx`).
// With `write` the cells go to dst rows from row0 and every row but the last is flagged LINE_WRAPPED.
fn layout_line(t: *const Term, a: usize, b: usize, ncols: usize, cur_idx: usize, dst: []Cell, dstf: []u32, row0: usize, write: bool) -> (usize, usize, usize) {
    let (_, last_nb) = seq_scan(t, a, b)
    var len_eff = last_nb
    if cur_idx != NO_CURSOR && cur_idx + 1usize > len_eff { len_eff = cur_idx + 1usize }
    var row = 0usize
    var col = 0usize
    var i = 0usize
    var cur_row = 0usize
    var cur_col = 0usize
    var j = a
    while j <= b && i < len_eff {
        let kept = row_kept(t, j, b)
        var c = 0usize
        while c < kept && i < len_eff {
            let cl = line_cell(t, j, c)
            var w = 1usize
            var unit = 1usize
            if (cl.attr & WIDE) != 0u32 && c + 1usize < kept && (line_cell(t, j, c + 1usize).attr & CONT) != 0u32 {
                w = 2usize
                unit = 2usize
            }
            var placed = cl
            if w == 2usize && ncols == 1usize {
                placed = blank_cell(cl.bg)
                w = 1usize
            }
            if col + w > ncols {
                if col < ncols && write { dst[(row0 + row) * ncols + col] = blank_cell(cl.bg) }
                if write { dstf[row0 + row] = LINE_WRAPPED }
                row += 1usize
                col = 0usize
            }
            if cur_idx != NO_CURSOR && (i == cur_idx || (unit == 2usize && i + 1usize == cur_idx)) {
                cur_row = row
                cur_col = col
            }
            if write {
                let at = (row0 + row) * ncols + col
                dst[at] = placed
                if unit == 2usize && w == 2usize { dst[at + 1usize] = line_cell(t, j, c + 1usize) }
            }
            col += w
            i += unit
            c += unit
        }
        j += 1usize
    }
    while i < len_eff {
        if col + 1usize > ncols {
            if write { dstf[row0 + row] = LINE_WRAPPED }
            row += 1usize
            col = 0usize
        }
        if i == cur_idx {
            cur_row = row
            cur_col = col
        }
        col += 1usize
        i += 1usize
    }
    ret (row + 1usize, cur_row, cur_col)
}

// Resize to `cols` x `rows` with reflow. `a` supplies a scratch of `max_lines` lines at the new width (restored
// on return); lines older than the scratch holds are dropped, newest kept. Refused with no change when the
// cursor's logical line does not fit (`mem.Exhausted`) or the size is out of range (`Invalid`). The alternate
// screen and an unchanged width fall through to `resize`.
fn resize_reflow(a: *mem.Arena, t: *Term, cols: usize, rows: usize, max_lines: usize) -> err {
    if cols == 0usize || rows == 0usize || cols > t.max_cols || rows > t.max_rows { ret Invalid }
    if t.alt || cols == t.cols { ret resize(t, cols, rows) }
    if max_lines < rows { ret Invalid }
    let mark = a.off
    let (cells, e1) = mem.alloc[Cell](a, max_lines * cols)
    if e1 != ok {
        a.off = mark
        ret e1
    }
    let (fl, e2) = mem.alloc[u32](a, max_lines)
    if e2 != ok {
        a.off = mark
        ret e2
    }
    var z = 0usize
    while z < cells.len {
        cells[z] = blank_cell(0u32)
        z += 1usize
    }
    z = 0usize
    while z < fl.len {
        fl[z] = 0u32
        z += 1usize
    }
    let total = line_count(t)
    let cursor_abs = t.sb_len + t.cy
    var pend = 0usize
    if t.wrap_pending { pend = 1usize }
    var end = total
    var filled = 0usize
    var got_cursor = false
    var cur_scr_row = 0usize
    var cur_col_out = 0usize
    var go = true
    while go && end > 0usize {
        var start = end - 1usize
        while start > 0usize && line_wrapped(t, start - 1usize) { start -= 1usize }
        var cidx = NO_CURSOR
        if start <= cursor_abs && cursor_abs < end {
            var before = 0usize
            var j = start
            while j < cursor_abs {
                before += row_kept(t, j, end - 1usize)
                j += 1usize
            }
            cidx = before + t.cx + pend
        }
        let (n_rows, _, _) = layout_line(t, start, end - 1usize, cols, cidx, cells, fl, 0usize, false)
        if filled + n_rows > max_lines {
            go = false
        } else {
            let row0 = max_lines - filled - n_rows
            let (_, cr, cc) = layout_line(t, start, end - 1usize, cols, cidx, cells, fl, row0, true)
            if cidx != NO_CURSOR {
                got_cursor = true
                cur_scr_row = row0 + cr
                cur_col_out = cc
            }
            filled += n_rows
            end = start
        }
    }
    if !got_cursor {
        a.off = mark
        ret mem.Exhausted
    }
    let base = max_lines - filled
    let cur_rel = cur_scr_row - base
    var top = 0usize
    if filled > rows { top = min_usize(filled - rows, cur_rel) }
    var sb_n = top
    if sb_n > t.sb_cap { sb_n = t.sb_cap }
    t.sb_dropped += total
    t.sb_head = 0usize
    t.sb_len = sb_n
    var i = 0usize
    while i < sb_n {
        let src = base + top - sb_n + i
        let dbase = (2usize * t.max_rows + i) * t.max_cols
        var x = 0usize
        while x < t.max_cols {
            if x < cols { t.cells[dbase + x] = cells[src * cols + x] } else { t.cells[dbase + x] = blank_cell(0u32) }
            x += 1usize
        }
        t.flags[2usize * t.max_rows + i] = fl[src]
        i += 1usize
    }
    var avail = filled - top
    if avail > rows { avail = rows }
    var r = 0usize
    while r < t.max_rows {
        let dbase = r * t.max_cols
        var x = 0usize
        while x < t.max_cols {
            if r < avail && x < cols { t.cells[dbase + x] = cells[(base + top + r) * cols + x] } else { t.cells[dbase + x] = blank_cell(0u32) }
            x += 1usize
        }
        if r < avail { t.flags[r] = fl[base + top + r] } else { t.flags[r] = 0u32 }
        r += 1usize
    }
    if cols < t.cols {
        t.alt = true
        var ar = 0usize
        while ar < t.max_rows {
            blank_range(t, ar, cols, t.cols)
            ar += 1usize
        }
        t.alt = false
    }
    t.cols = cols
    t.rows = rows
    t.top = 0usize
    t.bottom = rows - 1usize
    t.cx = cur_col_out
    t.cy = cur_rel - top
    t.wrap_pending = false
    t.saved_x = min_usize(t.saved_x, cols - 1usize)
    t.saved_y = min_usize(t.saved_y, rows - 1usize)
    reset_tabs(t)
    a.off = mark
    ret ok
}

// ---- key, mouse, focus and paste encoding (D3501) ---------------------------------------------------------
// Bytes a host sends to the program for an input event, after xterm's defaults (no modifyOtherKeys, 7-bit
// controls). `key` is a Unicode scalar or one of the KEY_ constants; `mods` is MOD_SHIFT | MOD_ALT | MOD_CTRL |
// MOD_META. Every encoder returns the byte count, or 0 when it has nothing to send or `dst` is too small.

const KEY_UP: u32 = 2097153u32
const KEY_DOWN: u32 = 2097154u32
const KEY_RIGHT: u32 = 2097155u32
const KEY_LEFT: u32 = 2097156u32
const KEY_HOME: u32 = 2097157u32
const KEY_END: u32 = 2097158u32
const KEY_INSERT: u32 = 2097159u32
const KEY_DELETE: u32 = 2097160u32
const KEY_PAGE_UP: u32 = 2097161u32
const KEY_PAGE_DOWN: u32 = 2097162u32
const KEY_ENTER: u32 = 2097163u32
const KEY_TAB: u32 = 2097164u32
const KEY_BACKSPACE: u32 = 2097165u32
const KEY_ESCAPE: u32 = 2097166u32
const KEY_F1: u32 = 2097167u32
const KEY_F12: u32 = 2097178u32
const MOD_SHIFT: u32 = 1u32
const MOD_ALT: u32 = 2u32
const MOD_CTRL: u32 = 4u32
const MOD_META: u32 = 8u32
const MOD_HYPER: u32 = 16u32
const MOD_CAPS_LOCK: u32 = 64u32
const MOD_NUM_LOCK: u32 = 128u32
// Keypad keys carry kitty's code points (functional-key private use area 57344..57454); the rest of that area is
// modifier and media keys, reported only by the kitty protocol with "report all keys" set.
const KEY_KP_0: u32 = 57399u32
const KEY_KP_9: u32 = 57408u32
const KEY_KP_DECIMAL: u32 = 57409u32
const KEY_KP_DIVIDE: u32 = 57410u32
const KEY_KP_MULTIPLY: u32 = 57411u32
const KEY_KP_SUBTRACT: u32 = 57412u32
const KEY_KP_ADD: u32 = 57413u32
const KEY_KP_ENTER: u32 = 57414u32
const KEY_KP_EQUAL: u32 = 57415u32
const KEY_KP_SEPARATOR: u32 = 57416u32
const KEY_LEFT_SHIFT: u32 = 57441u32
const KEY_LEFT_CONTROL: u32 = 57442u32
const KEY_LEFT_ALT: u32 = 57443u32
const KEY_LEFT_SUPER: u32 = 57444u32
const EVENT_PRESS: u32 = 1u32
const EVENT_REPEAT: u32 = 2u32
const EVENT_RELEASE: u32 = 3u32
const KITTY_DISAMBIGUATE: u32 = 1u32
const KITTY_EVENT_TYPES: u32 = 2u32
const KITTY_ALTERNATE_KEYS: u32 = 4u32
const KITTY_ALL_KEYS: u32 = 8u32
const KITTY_TEXT: u32 = 16u32
const MOUSE_PRESS: u32 = 0u32
const MOUSE_RELEASE: u32 = 1u32
const MOUSE_MOVE: u32 = 2u32
const BUTTON_LEFT: u32 = 0u32
const BUTTON_MIDDLE: u32 = 1u32
const BUTTON_RIGHT: u32 = 2u32
const BUTTON_NONE: u32 = 3u32
const WHEEL_UP: u32 = 4u32
const WHEEL_DOWN: u32 = 5u32
const WHEEL_LEFT: u32 = 6u32
const WHEEL_RIGHT: u32 = 7u32

// Decimal digits of v appended at buf[n]; returns the new length.
fn put_dec(buf: []u8, n_in: usize, v: usize) -> usize {
    var n = n_in
    var digits: [20]u8 = zero
    var k = 0usize
    var x = v
    if x == 0usize {
        digits[0usize] = 48u8
        k = 1usize
    }
    while x > 0usize {
        digits[k] = 48u8 + u8(x % 10usize)
        k += 1usize
        x = x / 10usize
    }
    while k > 0usize {
        k -= 1usize
        buf[n] = digits[k]
        n += 1usize
    }
    ret n
}

fn emit_bytes(tmp: []const u8, n: usize, dst: []u8) -> usize {
    if n > dst.len { ret 0usize }
    var i = 0usize
    while i < n {
        dst[i] = tmp[i]
        i += 1usize
    }
    ret n
}

// xterm's modifyOtherKeys form of a key: ESC [ 27 ; mods ; code ~
fn other_keys(code: u32, m: usize, dst: []u8) -> usize {
    var b: [24]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    b[2usize] = 50u8
    b[3usize] = 55u8
    b[4usize] = 59u8
    var n = put_dec(b[..], 5usize, m)
    b[n] = 59u8
    n = put_dec(b[..], n + 1usize, usize(code))
    b[n] = 126u8
    ret emit_bytes(b[..], n + 1usize, dst)
}

// The keypad (kitty's code points). Numeric mode sends what the key types; application mode (DECKPAM, ?66) sends
// SS3 and a final letter, `ESC O <mods> <final>` with modifiers.
fn encode_keypad(t: *const Term, key: u32, mods: u32, dst: []u8) -> usize {
    let idx = key - KEY_KP_0
    if !t.app_keypad {
        var ch = 44u32
        if idx <= 9u32 { ch = 48u32 + idx } else if idx == 10u32 { ch = 46u32 } else if idx == 11u32 { ch = 47u32 } else if idx == 12u32 { ch = 42u32 } else if idx == 13u32 { ch = 45u32 } else if idx == 14u32 { ch = 43u32 } else if idx == 16u32 { ch = 61u32 }
        if idx == 15u32 { ret encode_legacy(t, KEY_ENTER, mods, dst) }
        ret encode_legacy(t, ch, mods, dst)
    }
    var f = 108u8
    if idx <= 9u32 { f = 112u8 + u8(idx) } else if idx == 10u32 { f = 110u8 } else if idx == 11u32 { f = 111u8 } else if idx == 12u32 { f = 106u8 } else if idx == 13u32 { f = 109u8 } else if idx == 14u32 { f = 107u8 } else if idx == 15u32 { f = 77u8 } else if idx == 16u32 { f = 88u8 }
    var b: [8]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 79u8
    var n = 2usize
    if (mods & 15u32) != 0u32 { n = put_dec(b[..], n, 1usize + usize(mods & 15u32)) }
    b[n] = f
    ret emit_bytes(b[..], n + 1usize, dst)
}

fn encode_legacy(t: *const Term, key: u32, mods: u32, dst: []u8) -> usize {
    var b: [40]u8 = zero
    var n = 0usize
    let m = 1usize + usize(mods & 15u32)
    let alt = (mods & (MOD_ALT | MOD_META)) != 0u32
    let ctrl = (mods & MOD_CTRL) != 0u32
    let shift = (mods & MOD_SHIFT) != 0u32
    if key >= KEY_KP_0 && key <= KEY_KP_SEPARATOR { ret encode_keypad(t, key, mods, dst) }
    if key >= 57344u32 && key <= 57454u32 { ret 0usize }
    if key < 1114112u32 {
        var c = key
        var as_control = false
        if ctrl {
            if c >= 97u32 && c <= 122u32 {
                c = c - 96u32
                as_control = true
            } else if c >= 65u32 && c <= 90u32 {
                c = c - 64u32
                as_control = true
            } else if c == 64u32 || c == 32u32 || c == 50u32 {
                c = 0u32
                as_control = true
            } else if c == 91u32 || c == 51u32 {
                c = 27u32
                as_control = true
            } else if c == 92u32 || c == 52u32 {
                c = 28u32
                as_control = true
            } else if c == 93u32 || c == 53u32 {
                c = 29u32
                as_control = true
            } else if c == 94u32 || c == 54u32 {
                c = 30u32
                as_control = true
            } else if c == 95u32 || c == 47u32 || c == 55u32 {
                c = 31u32
                as_control = true
            } else if c == 63u32 || c == 56u32 {
                c = 127u32
                as_control = true
            }
        }
        if t.modify_other != 0u32 {
            var other = false
            if t.modify_other >= 2u32 {
                if (mods & (MOD_ALT | MOD_CTRL | MOD_META)) != 0u32 { other = true }
            } else if ctrl && (!as_control || (shift && ((key >= 97u32 && key <= 122u32) || (key >= 65u32 && key <= 90u32)))) {
                other = true
            }
            if other { ret other_keys(key, m, dst) }
        }
        if alt {
            b[n] = 27u8
            n += 1usize
        }
        if as_control || c < 128u32 {
            b[n] = u8(c)
            n += 1usize
        } else {
            n += encoding.write_utf8(c, b[..], n)
        }
        ret emit_bytes(b[..], n, dst)
    }
    if key == KEY_ENTER || key == KEY_TAB || key == KEY_BACKSPACE || key == KEY_ESCAPE {
        if t.modify_other != 0u32 {
            var other = false
            if t.modify_other >= 2u32 {
                if (mods & 15u32) != 0u32 { other = true }
            } else if key == KEY_ENTER {
                if (mods & (MOD_SHIFT | MOD_CTRL)) != 0u32 { other = true }
            } else if key == KEY_TAB {
                if ctrl { other = true }
            }
            if other {
                var code = 27u32
                if key == KEY_ENTER { code = 13u32 } else if key == KEY_TAB { code = 9u32 } else if key == KEY_BACKSPACE { code = 127u32 }
                ret other_keys(code, m, dst)
            }
        }
        if alt {
            b[n] = 27u8
            n += 1usize
        }
        if key == KEY_ENTER {
            b[n] = 13u8
            n += 1usize
            if t.newline_mode {
                b[n] = 10u8
                n += 1usize
            }
        } else if key == KEY_TAB {
            if shift {
                b[n] = 27u8
                b[n + 1usize] = 91u8
                b[n + 2usize] = 90u8
                n += 3usize
            } else {
                b[n] = 9u8
                n += 1usize
            }
        } else if key == KEY_BACKSPACE {
            if ctrl { b[n] = 8u8 } else { b[n] = 127u8 }
            n += 1usize
        } else {
            b[n] = 27u8
            n += 1usize
        }
        ret emit_bytes(b[..], n, dst)
    }
    if key >= KEY_UP && key <= KEY_END {
        var letter = 65u8
        if key == KEY_DOWN { letter = 66u8 }
        if key == KEY_RIGHT { letter = 67u8 }
        if key == KEY_LEFT { letter = 68u8 }
        if key == KEY_HOME { letter = 72u8 }
        if key == KEY_END { letter = 70u8 }
        b[0usize] = 27u8
        if m == 1usize {
            if t.app_cursor { b[1usize] = 79u8 } else { b[1usize] = 91u8 }
            b[2usize] = letter
            n = 3usize
        } else {
            b[1usize] = 91u8
            b[2usize] = 49u8
            b[3usize] = 59u8
            n = put_dec(b[..], 4usize, m)
            b[n] = letter
            n += 1usize
        }
        ret emit_bytes(b[..], n, dst)
    }
    var tilde = 0usize
    if key == KEY_INSERT { tilde = 2usize }
    if key == KEY_DELETE { tilde = 3usize }
    if key == KEY_PAGE_UP { tilde = 5usize }
    if key == KEY_PAGE_DOWN { tilde = 6usize }
    if key >= KEY_F1 && key <= KEY_F12 {
        let f = usize(key - KEY_F1) + 1usize
        if f <= 4usize {
            b[0usize] = 27u8
            if m == 1usize {
                b[1usize] = 79u8
                b[2usize] = 79u8 + u8(f)
                n = 3usize
            } else {
                b[1usize] = 91u8
                b[2usize] = 49u8
                b[3usize] = 59u8
                n = put_dec(b[..], 4usize, m)
                b[n] = 79u8 + u8(f)
                n += 1usize
            }
            ret emit_bytes(b[..], n, dst)
        }
        if f == 5usize { tilde = 15usize }
        if f == 6usize { tilde = 17usize }
        if f == 7usize { tilde = 18usize }
        if f == 8usize { tilde = 19usize }
        if f == 9usize { tilde = 20usize }
        if f == 10usize { tilde = 21usize }
        if f == 11usize { tilde = 23usize }
        if f == 12usize { tilde = 24usize }
    }
    if tilde == 0usize { ret 0usize }
    b[0usize] = 27u8
    b[1usize] = 91u8
    n = put_dec(b[..], 2usize, tilde)
    if m != 1usize {
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, m)
    }
    b[n] = 126u8
    n += 1usize
    ret emit_bytes(b[..], n, dst)
}

// ---- kitty keyboard protocol (D4500) ----------------------------------------------------------------------
// With any flag pushed (CSI > flags u) a key goes through the progressive-enhancement encoding of
// https://sw.kovidgoyal.net/kitty/keyboard-protocol/: flag 1 sends everything legacy bytes cannot say as
// ESC [ code ; mods u (Esc, and any key with alt, ctrl, super or hyper; Enter, Tab and Backspace keep their bytes
// until they carry a modifier), flag 2 adds `:event` (1 press, 2 repeat, 3 release; a release of a key that is
// still sent as text or a control byte is not reported), flag 4 the shifted and base-layout alternates
// (`code:shifted:base`), flag 8 sends every key as an escape code (modifier keys included), flag 16 the text a key
// produced as the third field. Modifier field = 1 + bits (shift 1, alt 2, ctrl 4, super 8, hyper 16, caps 64,
// num 128). The key code of a letter is its lower case; an upper-case letter given with MOD_SHIFT is the shifted
// alternate.

fn kitty_u(code: u32, shifted: u32, base: u32, mods: u32, event: u32, text: u32, dst: []u8) -> usize {
    var b: [48]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    var n = put_dec(b[..], 2usize, usize(code))
    if shifted != 0u32 || base != 0u32 {
        b[n] = 58u8
        n += 1usize
        if shifted != 0u32 { n = put_dec(b[..], n, usize(shifted)) }
        if base != 0u32 {
            b[n] = 58u8
            n = put_dec(b[..], n + 1usize, usize(base))
        }
    }
    if mods != 0u32 || event != 1u32 || text != 0u32 {
        b[n] = 59u8
        n += 1usize
        if mods != 0u32 || event != 1u32 {
            n = put_dec(b[..], n, 1usize + usize(mods))
            if event != 1u32 {
                b[n] = 58u8
                n = put_dec(b[..], n + 1usize, usize(event))
            }
        }
        if text != 0u32 {
            b[n] = 59u8
            n = put_dec(b[..], n + 1usize, usize(text))
        }
    }
    b[n] = 117u8
    ret emit_bytes(b[..], n + 1usize, dst)
}

// Cursor, editing and function keys in kitty's CSI form (F3 is CSI 13 ~ because CSI R is a cursor report).
fn kitty_func(key: u32, mods: u32, event: u32, dst: []u8) -> usize {
    var letter = 0u8
    var tilde = 0usize
    if key == KEY_UP { letter = 65u8 } else if key == KEY_DOWN { letter = 66u8 } else if key == KEY_RIGHT { letter = 67u8 } else if key == KEY_LEFT { letter = 68u8 } else if key == KEY_HOME { letter = 72u8 } else if key == KEY_END { letter = 70u8 } else if key == KEY_INSERT { tilde = 2usize } else if key == KEY_DELETE { tilde = 3usize } else if key == KEY_PAGE_UP { tilde = 5usize } else if key == KEY_PAGE_DOWN { tilde = 6usize } else if key >= KEY_F1 && key <= KEY_F12 {
        let f = usize(key - KEY_F1) + 1usize
        if f == 1usize { letter = 80u8 } else if f == 2usize { letter = 81u8 } else if f == 4usize { letter = 83u8 } else if f == 3usize { tilde = 13usize } else if f == 5usize { tilde = 15usize } else if f == 6usize { tilde = 17usize } else if f == 7usize { tilde = 18usize } else if f == 8usize { tilde = 19usize } else if f == 9usize { tilde = 20usize } else if f == 10usize { tilde = 21usize } else if f == 11usize { tilde = 23usize } else { tilde = 24usize }
    }
    if letter == 0u8 && tilde == 0usize { ret 0usize }
    var b: [32]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    var n = 2usize
    let has = mods != 0u32 || event != 1u32
    if tilde > 0usize {
        n = put_dec(b[..], n, tilde)
    } else if has {
        b[n] = 49u8
        n += 1usize
    }
    if has {
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, 1usize + usize(mods))
        if event != 1u32 {
            b[n] = 58u8
            n = put_dec(b[..], n + 1usize, usize(event))
        }
    }
    if tilde > 0usize { b[n] = 126u8 } else { b[n] = letter }
    ret emit_bytes(b[..], n + 1usize, dst)
}

fn encode_kitty(t: *const Term, key: u32, mods_in: u32, event_in: u32, shifted: u32, base: u32, text: u32, flags: u32, dst: []u8) -> usize {
    let disamb = (flags & KITTY_DISAMBIGUATE) != 0u32
    let evt_on = (flags & KITTY_EVENT_TYPES) != 0u32
    let alt_on = (flags & KITTY_ALTERNATE_KEYS) != 0u32
    let all = (flags & KITTY_ALL_KEYS) != 0u32
    let txt_on = (flags & KITTY_TEXT) != 0u32
    var event = event_in
    if event == 0u32 || event > 3u32 { event = 1u32 }
    if event == 3u32 && !evt_on { ret 0usize }
    if event == 2u32 && !evt_on { event = 1u32 }
    let mods = mods_in & 255u32
    let plain = (mods & 31u32) == 0u32
    let mod_eff = mods & 30u32
    if key == KEY_ESCAPE {
        if all || disamb { ret kitty_u(27u32, 0u32, 0u32, mods, event, 0u32, dst) }
        if event == 3u32 { ret 0usize }
        ret encode_legacy(t, key, mods_in, dst)
    }
    if key == KEY_ENTER || key == KEY_TAB || key == KEY_BACKSPACE {
        var code = 127u32
        if key == KEY_ENTER { code = 13u32 } else if key == KEY_TAB { code = 9u32 }
        if all { ret kitty_u(code, 0u32, 0u32, mods, event, 0u32, dst) }
        if event == 3u32 { ret 0usize }
        if disamb && !plain { ret kitty_u(code, 0u32, 0u32, mods, event, 0u32, dst) }
        ret encode_legacy(t, key, mods_in, dst)
    }
    if key >= KEY_UP && key <= KEY_F12 {
        if !all && event == 1u32 && plain { ret encode_legacy(t, key, mods_in, dst) }
        ret kitty_func(key, mods, event, dst)
    }
    if key >= KEY_KP_0 && key <= KEY_KP_SEPARATOR {
        if !all && mod_eff == 0u32 {
            if event == 3u32 { ret 0usize }
            ret encode_legacy(t, key, mods_in, dst)
        }
        var kp_text = 0u32
        let idx = key - KEY_KP_0
        if txt_on && all && event != 3u32 && mod_eff == 0u32 {
            if idx <= 9u32 { kp_text = 48u32 + idx } else if idx == 10u32 { kp_text = 46u32 } else if idx == 11u32 { kp_text = 47u32 } else if idx == 12u32 { kp_text = 42u32 } else if idx == 13u32 { kp_text = 45u32 } else if idx == 14u32 { kp_text = 43u32 } else if idx == 16u32 { kp_text = 61u32 } else if idx == 17u32 { kp_text = 44u32 }
        }
        ret kitty_u(key, 0u32, 0u32, mods, event, kp_text, dst)
    }
    if key >= 57344u32 && key <= 57454u32 {
        if !all { ret 0usize }
        ret kitty_u(key, 0u32, 0u32, mods, event, 0u32, dst)
    }
    if key >= 1114112u32 { ret 0usize }
    var code = key
    var shf = shifted
    if key >= 65u32 && key <= 90u32 {
        code = key + 32u32
        if shf == 0u32 { shf = key }
    }
    var sh = 0u32
    if alt_on && (mods & MOD_SHIFT) != 0u32 && shf != 0u32 && shf != code { sh = shf }
    var bs = 0u32
    if alt_on && base != 0u32 && base != code { bs = base }
    if all {
        var txt = 0u32
        if txt_on && event != 3u32 && mod_eff == 0u32 {
            txt = text
            if txt == 0u32 && key >= 32u32 && key != 127u32 { txt = key }
        }
        ret kitty_u(code, sh, bs, mods, event, txt, dst)
    }
    if event == 3u32 { ret 0usize }
    if disamb && mod_eff != 0u32 { ret kitty_u(code, sh, bs, mods, event, 0u32, dst) }
    if text != 0u32 && mod_eff == 0u32 { ret encode_legacy(t, text, mods_in, dst) }
    ret encode_legacy(t, key, mods_in, dst)
}

// A key event with its type (EVENT_PRESS / REPEAT / RELEASE) and, for the kitty protocol, the shifted and
// base-layout alternates and the text the key produced (0 for none). Without kitty flags a release sends
// nothing and a repeat is a press.
fn encode_key_event(t: *const Term, key: u32, mods: u32, event: u32, shifted: u32, base: u32, text: u32, dst: []u8) -> usize {
    let kf = kitty_flags(t)
    if kf != 0u32 { ret encode_kitty(t, key, mods, event, shifted, base, text, kf, dst) }
    if event == EVENT_RELEASE { ret 0usize }
    ret encode_legacy(t, key, mods, dst)
}

fn encode_key(t: *const Term, key: u32, mods: u32, dst: []u8) -> usize {
    ret encode_key_event(t, key, mods, EVENT_PRESS, 0u32, 0u32, 0u32, dst)
}

// A mouse report for the mode the program set: 9 (X10, press only, no modifiers), 1000 (press and release,
// wheel), 1002 (plus motion with a button held, `button` naming it) and 1003 (all motion, BUTTON_NONE when no
// button is held); SGR (1006) encoding when set, else urxvt's decimal one (1015: ESC [ Cb ; Cx ; Cy M, Cb the
// legacy byte value, a release Cb 3), else the UTF-8 extension (1005: the legacy bytes, each value above 127 as a
// two-byte UTF-8 character; nothing past column or row 2014), else the legacy single-byte one, which cannot name a
// cell past column or row 222 and then sends nothing. Setting one of 1005/1006/1015 replaces the other two and
// resetting any returns to legacy. `x` and `y` are 0-based cells; wheel events are presses.
fn encode_mouse(t: *const Term, button: u32, action: u32, mods: u32, x: usize, y: usize, dst: []u8) -> usize {
    let mode = t.mouse_mode
    if mode == 0u32 || button > 7u32 || action > 2u32 { ret 0usize }
    let wheel = button >= 4u32
    if wheel && action != MOUSE_PRESS { ret 0usize }
    if action == MOUSE_MOVE {
        if wheel || mode == 9u32 || mode == 1000u32 { ret 0usize }
        if mode == 1002u32 && button == BUTTON_NONE { ret 0usize }
    }
    if mode == 9u32 && (action != MOUSE_PRESS || wheel) { ret 0usize }
    var cb = usize(button)
    if wheel { cb = 60usize + usize(button) }
    var release = false
    if action == MOUSE_RELEASE { release = true }
    if release && !t.mouse_sgr { cb = 3usize }
    if mode != 9u32 {
        if (mods & MOD_SHIFT) != 0u32 { cb += 4usize }
        if (mods & (MOD_ALT | MOD_META)) != 0u32 { cb += 8usize }
        if (mods & MOD_CTRL) != 0u32 { cb += 16usize }
    }
    if action == MOUSE_MOVE { cb += 32usize }
    var b: [40]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    var n = 0usize
    if t.mouse_sgr && mode != 9u32 {
        b[2usize] = 60u8
        n = put_dec(b[..], 3usize, cb)
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, x + 1usize)
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, y + 1usize)
        if release { b[n] = 109u8 } else { b[n] = 77u8 }
        n += 1usize
    } else if t.mouse_urxvt && mode != 9u32 {
        n = put_dec(b[..], 2usize, cb + 32usize)
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, x + 1usize)
        b[n] = 59u8
        n = put_dec(b[..], n + 1usize, y + 1usize)
        b[n] = 77u8
        n += 1usize
    } else if t.mouse_utf8 && mode != 9u32 {
        if x > 2014usize || y > 2014usize { ret 0usize }
        b[2usize] = 77u8
        n = 3usize
        n += encoding.write_utf8(u32(cb + 32usize), b[..], n)
        n += encoding.write_utf8(u32(x + 33usize), b[..], n)
        n += encoding.write_utf8(u32(y + 33usize), b[..], n)
    } else {
        if x > 222usize || y > 222usize { ret 0usize }
        b[2usize] = 77u8
        b[3usize] = u8(cb + 32usize)
        b[4usize] = u8(x + 33usize)
        b[5usize] = u8(y + 33usize)
        n = 6usize
    }
    ret emit_bytes(b[..], n, dst)
}

// Focus-in / focus-out report (CSI I / CSI O) when the program asked for them (mode 1004).
fn encode_focus(t: *const Term, focused: bool, dst: []u8) -> usize {
    if !t.focus_events { ret 0usize }
    var b: [3]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    if focused { b[2usize] = 73u8 } else { b[2usize] = 79u8 }
    ret emit_bytes(b[..], 3usize, dst)
}

// ESC [ 2 0 0 ~ when bracketed paste is on, else nothing.
fn paste_begin(t: *const Term, dst: []u8) -> usize {
    if !t.bracketed_paste { ret 0usize }
    var b: [6]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    b[2usize] = 50u8
    b[3usize] = 48u8
    b[4usize] = 48u8
    b[5usize] = 126u8
    ret emit_bytes(b[..], 6usize, dst)
}

// ESC [ 2 0 1 ~ when bracketed paste is on, else nothing.
fn paste_end(t: *const Term, dst: []u8) -> usize {
    if !t.bracketed_paste { ret 0usize }
    var b: [6]u8 = zero
    b[0usize] = 27u8
    b[1usize] = 91u8
    b[2usize] = 50u8
    b[3usize] = 48u8
    b[4usize] = 49u8
    b[5usize] = 126u8
    ret emit_bytes(b[..], 6usize, dst)
}

// The pasted bytes as the program should read them: bracketed, every ESC is dropped so the text cannot end its
// own bracket; unbracketed, a line break (CR LF, LF) becomes one CR. Stops when dst is full; returns the bytes
// written.
fn paste_filter(t: *const Term, src: []const u8, dst: []u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < src.len && n < dst.len {
        let c = src[i]
        if t.bracketed_paste {
            if c != 27u8 {
                dst[n] = c
                n += 1usize
            }
        } else if c == 13u8 && i + 1usize < src.len && src[i + 1usize] == 10u8 {
            dst[n] = 13u8
            n += 1usize
            i += 1usize
        } else if c == 10u8 {
            dst[n] = 13u8
            n += 1usize
        } else {
            dst[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// ---- selection (D3501) ------------------------------------------------------------------------------------
// A selection is in buffer coordinates (line = scrollback index or sb_len + row, column in cells). Character
// mode takes both end cells; word mode widens each end to the run of same-class cells (blank, word, other) on
// its line, continuing over a wrapped row into the next (or back into the previous) when the run reaches the
// margin and the cell across has the same class; line mode takes whole logical lines (rows joined by LINE_WRAPPED); block mode a rectangle. A click
// on the second half of a wide character selects the character.

const SEL_NONE: u32 = 0u32
const SEL_CHAR: u32 = 1u32
const SEL_WORD: u32 = 2u32
const SEL_LINE: u32 = 3u32
const SEL_BLOCK: u32 = 4u32

type Selection = struct { mode: u32, a_line: usize, a_col: usize, h_line: usize, h_col: usize }

fn selection_start(mode: u32, line: usize, col: usize) -> Selection {
    ret Selection { mode: mode, a_line: line, a_col: col, h_line: line, h_col: col }
}

fn selection_extend(sel: *Selection, line: usize, col: usize) {
    sel.h_line = line
    sel.h_col = col
}

// The column of the cell a position belongs to (the head of a wide character).
fn snap_col(t: *const Term, line: usize, col: usize) -> usize {
    var c = min_usize(col, t.cols - 1usize)
    if c > 0usize && (line_cell(t, line, c).attr & CONT) != 0u32 { c -= 1usize }
    ret c
}

fn cell_class(c: Cell) -> u32 {
    if c.ch == 32u32 || c.ch == 0u32 { ret 0u32 }
    if (c.ch >= 48u32 && c.ch <= 57u32) || (c.ch >= 65u32 && c.ch <= 90u32) || (c.ch >= 97u32 && c.ch <= 122u32) || c.ch == 95u32 || c.ch >= 128u32 { ret 1u32 }
    ret 2u32
}

// [first, one past last) columns of the run of same-class cells holding (line, col).
fn word_bounds(t: *const Term, line: usize, col: usize) -> (usize, usize) {
    let c0 = snap_col(t, line, col)
    let cls = cell_class(line_cell(t, line, c0))
    var s = c0
    while s > 0usize {
        var p = s - 1usize
        if p > 0usize && (line_cell(t, line, p).attr & CONT) != 0u32 { p -= 1usize }
        if cell_class(line_cell(t, line, p)) != cls { break }
        s = p
    }
    var f = c0
    while f < t.cols {
        let cl = line_cell(t, line, f)
        if (cl.attr & CONT) == 0u32 && cell_class(cl) != cls { break }
        f += 1usize
    }
    ret (s, f)
}

fn logical_first(t: *const Term, line: usize) -> usize {
    var l = line
    while l > 0usize && line_wrapped(t, l - 1usize) { l -= 1usize }
    ret l
}

fn logical_last(t: *const Term, line: usize) -> usize {
    var l = line
    while l + 1usize < line_count(t) && line_wrapped(t, l) { l += 1usize }
    ret l
}

// The selected span in reading order: (first line, first column, last line, one past its last column). For block
// mode the columns are the rectangle's (min, max + 1) on every line from first to last.
fn selection_range(t: *const Term, sel: *const Selection) -> (usize, usize, usize, usize) {
    if sel.mode == SEL_NONE || line_count(t) == 0usize { ret (0usize, 0usize, 0usize, 0usize) }
    let last_line = line_count(t) - 1usize
    let al = min_usize(sel.a_line, last_line)
    let hl = min_usize(sel.h_line, last_line)
    let ac = snap_col(t, al, sel.a_col)
    let hc = snap_col(t, hl, sel.h_col)
    var a_first = al
    var a_col = ac
    var h_first = hl
    var h_col = hc
    var swap = false
    if hl < al || (hl == al && hc < ac) { swap = true }
    if sel.mode == SEL_BLOCK {
        ret (min_usize(al, hl), min_usize(ac, hc), max_usize(al, hl), max_usize(ac, hc) + 1usize)
    }
    if swap {
        a_first = hl
        a_col = hc
        h_first = al
        h_col = ac
    }
    if sel.mode == SEL_LINE {
        ret (logical_first(t, a_first), 0usize, logical_last(t, h_first), t.cols)
    }
    var end_col = h_col + 1usize
    if sel.mode == SEL_WORD {
        let (ws0, _) = word_bounds(t, a_first, a_col)
        let (_, we0) = word_bounds(t, h_first, h_col)
        var ws = ws0
        var we = we0
        // A word that runs off the end of a wrapped row goes on at the start of the next one.
        let cls_a = cell_class(line_cell(t, a_first, snap_col(t, a_first, a_col)))
        while ws == 0usize && a_first > 0usize && line_wrapped(t, a_first - 1usize) {
            let pc = snap_col(t, a_first - 1usize, t.cols - 1usize)
            if cell_class(line_cell(t, a_first - 1usize, pc)) != cls_a { break }
            a_first -= 1usize
            let (ps, _) = word_bounds(t, a_first, pc)
            ws = ps
        }
        let cls_h = cell_class(line_cell(t, h_first, snap_col(t, h_first, h_col)))
        while we >= t.cols && h_first + 1usize < line_count(t) && line_wrapped(t, h_first) {
            if cell_class(line_cell(t, h_first + 1usize, 0usize)) != cls_h { break }
            h_first += 1usize
            let (_, fe) = word_bounds(t, h_first, 0usize)
            we = fe
        }
        a_col = ws
        end_col = we
    }
    ret (a_first, a_col, h_first, min_usize(end_col, t.cols))
}

fn selection_contains(t: *const Term, sel: *const Selection, line: usize, col: usize) -> bool {
    if sel.mode == SEL_NONE { ret false }
    let (sl, sc, el, ec) = selection_range(t, sel)
    if line < sl || line > el { ret false }
    let c = snap_col(t, line, col)
    if sel.mode == SEL_BLOCK { ret c >= sc && c < ec }
    if line == sl && c < sc { ret false }
    if line == el && c >= ec { ret false }
    ret true
}

// The blank that pads the last column of a wrapped row whose next row starts with a wide character (the same
// cell `resize_reflow` drops when it joins): it is layout, not text, so a selection never copies it.
fn wrap_filler(t: *const Term, line: usize, col: usize) -> bool {
    if col + 1usize != t.cols || !line_wrapped(t, line) || line + 1usize >= line_count(t) { ret false }
    let cl = line_cell(t, line, col)
    if (cl.ch != 32u32 && cl.ch != 0u32) || cl.attr != 0u32 { ret false }
    ret (line_cell(t, line + 1usize, 0usize).attr & WIDE) != 0u32
}

// The selected text as UTF-8 into dst (truncated at dst.len, never inside a character); returns the bytes
// written. Rows joined by LINE_WRAPPED have no break between them (nor does the blank that pads a wide
// character moved to the next row); any other break is one LF. A row that the selection runs to the
// right edge of loses its trailing blanks unless it continues on the next row; block rows always do.
fn selection_text(t: *const Term, sel: *const Selection, dst: []u8) -> usize {
    if sel.mode == SEL_NONE { ret 0usize }
    let (sl, sc, el, ec) = selection_range(t, sel)
    var n = 0usize
    var l = sl
    while l <= el {
        var c0 = 0usize
        var c1 = t.cols
        if sel.mode == SEL_BLOCK {
            c0 = sc
            c1 = ec
        } else if sel.mode != SEL_LINE {
            if l == sl { c0 = sc }
            if l == el { c1 = ec }
        }
        var last = c1
        let continues = line_wrapped(t, l) && l != el
        var trim = false
        if sel.mode == SEL_BLOCK { trim = true } else if c1 == t.cols && !line_wrapped(t, l) { trim = true }
        if trim {
            while last > c0 {
                let cl = line_cell(t, l, last - 1usize)
                if (cl.attr & CONT) != 0u32 || (cl.ch != 32u32 && cl.ch != 0u32) { break }
                last -= 1usize
            }
        }
        var c = c0
        while c < last {
            let cl = line_cell(t, l, c)
            if (cl.attr & CONT) == 0u32 && !wrap_filler(t, l, c) {
                var ch = cl.ch
                if ch == 0u32 { ch = 32u32 }
                if n + encoding.utf8_length(ch) > dst.len { ret n }
                n += encoding.write_utf8(ch, dst, n)
            }
            c += 1usize
        }
        if l != el && !continues {
            if n >= dst.len { ret n }
            dst[n] = 10u8
            n += 1usize
        }
        l += 1usize
    }
    ret n
}

// Lines `dropped` scrolled out of the oldest end of the buffer: move the selection with them. Returns false
// (and clears the selection) when nothing of it is left.
fn selection_adjust(sel: *Selection, dropped: usize) -> bool {
    if sel.mode == SEL_NONE { ret false }
    if sel.a_line < dropped && sel.h_line < dropped {
        sel.mode = SEL_NONE
        ret false
    }
    if sel.a_line < dropped {
        sel.a_line = 0usize
        sel.a_col = 0usize
    } else {
        sel.a_line -= dropped
    }
    if sel.h_line < dropped {
        sel.h_line = 0usize
        sel.h_col = 0usize
    } else {
        sel.h_line -= dropped
    }
    ret true
}
