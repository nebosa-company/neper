// A terminal emulator (C120): bytes in, a grid of cells out. It reads what a shell session writes -- UTF-8 text, the
// C0 controls (BS, HT, LF, CR), CSI sequences (cursor movement and position, erase in display and line, insert and
// delete of characters and lines, scroll up and down, scroll region, SGR with the 8, 16, 256 and true colours,
// save and restore cursor, cursor visibility, alternate screen), ESC 7 8 D E M c and OSC strings (read and dropped).
// What it does not do: double-width characters, charsets, mouse reporting, device status replies.
//
// A cell holds a code point, a foreground and a background colour and attribute bits. A colour is 0 for the
// default, 1 to 8 for ANSI 30-37, 9 to 16 for 90-97, 0x100 | n for palette entry n (38;5;n), 0x1000000 | rgb for
// true colour. Wrapping is deferred: a character written in the last column leaves the cursor past it and wraps
// when the next one is drawn. Scrolling and the insert and delete commands fill with the default blank, erase
// commands with the current rendition (checked against pyte).
//
// Memory: the screens and the scrollback live in the arena passed to `open`.
use e.mem

type Cell = struct { ch: u32, fg: u32, bg: u32, attrs: u32 }

type Terminal = struct {
    cols: usize,
    rows: usize,
    main_cells: []Cell,
    alt_cells: []Cell,
    alt: bool,
    cx: usize,
    cy: usize,
    pen: Cell,
    saved_x: usize,
    saved_y: usize,
    saved_pen: Cell,
    top: usize,
    bottom: usize,
    cursor_visible: bool,
    autowrap: bool,
    state: u32,
    params: [16]i32,
    param_count: usize,
    private: bool,
    utf8_left: usize,
    utf8_value: u32,
    scrollback: []Cell,
    scroll_cap: usize,
    scroll_count: usize,
    scroll_start: usize,
}

const BOLD: u32 = 1u32
const UNDERLINE: u32 = 2u32
const REVERSE: u32 = 4u32
const ITALIC: u32 = 8u32
const BLINK: u32 = 16u32
const STRIKE: u32 = 32u32

const GROUND: u32 = 0u32
const ESCAPE: u32 = 1u32
const CSI: u32 = 2u32
const OSC: u32 = 3u32
const OSC_ESC: u32 = 4u32
const CHARSET: u32 = 5u32
const IGNORE_CSI: u32 = 6u32

const BLANK: u32 = 32u32

fn blank_cell() -> Cell { ret Cell { ch: 32u32, fg: 0u32, bg: 0u32, attrs: 0u32 } }

// A terminal of `cols` x `rows` with room for `scrollback` lines of history.
fn open(a: *mem.Arena, cols: usize, rows: usize, scrollback: usize) -> (Terminal, err) {
    var none: Terminal = zero
    let (main_cells, main_error) = mem.alloc[Cell](a, cols * rows)
    if main_error != ok { ret (none, main_error) }
    let (alt_cells, alt_error) = mem.alloc[Cell](a, cols * rows)
    if alt_error != ok { ret (none, alt_error) }
    let (history, history_error) = mem.alloc[Cell](a, cols * scrollback + 1usize)
    if history_error != ok { ret (none, history_error) }
    var i = 0usize
    while i < cols * rows {
        main_cells[i] = blank_cell()
        alt_cells[i] = blank_cell()
        i += 1usize
    }
    var t = Terminal { cols: cols, rows: rows, main_cells: main_cells, alt_cells: alt_cells, alt: false, cx: 0usize, cy: 0usize, pen: blank_cell(), saved_x: 0usize, saved_y: 0usize, saved_pen: blank_cell(), top: 0usize, bottom: rows - 1usize, cursor_visible: true, autowrap: true, state: GROUND, params: zero, param_count: 0usize, private: false, utf8_left: 0usize, utf8_value: 0u32, scrollback: history, scroll_cap: scrollback, scroll_count: 0usize, scroll_start: 0usize }
    ret (t, ok)
}

fn cells_of(t: *Terminal) -> []Cell {
    if t.alt { ret t.alt_cells }
    ret t.main_cells
}

// The cell at column `x`, row `y` of the visible screen.
fn cell(t: *Terminal, x: usize, y: usize) -> Cell {
    let cells = cells_of(t)
    ret cells[y * t.cols + x]
}

// A scrollback line, 0 the newest: its cell at column `x`.
fn history_cell(t: *Terminal, line: usize, x: usize) -> Cell {
    if line >= t.scroll_count || x >= t.cols { ret blank_cell() }
    let slot = (t.scroll_start + t.scroll_count - 1usize - line) % t.scroll_cap
    ret t.scrollback[slot * t.cols + x]
}

fn history_lines(t: *Terminal) -> usize { ret t.scroll_count }

fn clear_cells(cells: []Cell, from: usize, to: usize, fill: Cell) {
    var i = from
    while i < to {
        cells[i] = fill
        i += 1usize
    }
}

fn erase_fill(t: *Terminal) -> Cell {
    ret Cell { ch: 32u32, fg: t.pen.fg, bg: t.pen.bg, attrs: t.pen.attrs }
}

fn push_history(t: *Terminal, row: usize) {
    if t.scroll_cap == 0usize { ret }
    var slot = 0usize
    if t.scroll_count < t.scroll_cap {
        slot = (t.scroll_start + t.scroll_count) % t.scroll_cap
        t.scroll_count += 1usize
    } else {
        slot = t.scroll_start
        t.scroll_start = (t.scroll_start + 1usize) % t.scroll_cap
    }
    var x = 0usize
    while x < t.cols {
        t.scrollback[slot * t.cols + x] = t.main_cells[row * t.cols + x]
        x += 1usize
    }
}

// Scroll the region up by `n` lines: the top ones go (to the history when the region is the whole main screen).
fn scroll_up(t: *Terminal, n: usize) {
    let cells = cells_of(t)
    let height = t.bottom - t.top + 1usize
    var count = n
    if count > height { count = height }
    var i = 0usize
    while i < count {
        if !t.alt && t.top == 0usize && t.bottom + 1usize == t.rows { push_history(t, 0usize) }
        i += 1usize
    }
    var y = t.top
    while y + count <= t.bottom {
        var x = 0usize
        while x < t.cols {
            cells[y * t.cols + x] = cells[(y + count) * t.cols + x]
            x += 1usize
        }
        y += 1usize
    }
    clear_cells(cells, (t.bottom + 1usize - count) * t.cols, (t.bottom + 1usize) * t.cols, blank_cell())
}

fn scroll_down(t: *Terminal, n: usize) {
    let cells = cells_of(t)
    let height = t.bottom - t.top + 1usize
    var count = n
    if count > height { count = height }
    var y = t.bottom
    while y >= t.top + count {
        var x = 0usize
        while x < t.cols {
            cells[y * t.cols + x] = cells[(y - count) * t.cols + x]
            x += 1usize
        }
        if y == 0usize { ret }
        y -= 1usize
    }
    clear_cells(cells, t.top * t.cols, (t.top + count) * t.cols, blank_cell())
}

fn linefeed(t: *Terminal) {
    if t.cy == t.bottom {
        scroll_up(t, 1usize)
    } else if t.cy + 1usize < t.rows {
        t.cy += 1usize
    }
}

fn reverse_index(t: *Terminal) {
    if t.cy == t.top {
        scroll_down(t, 1usize)
    } else if t.cy > 0usize {
        t.cy -= 1usize
    }
}

fn put_char(t: *Terminal, cp: u32) {
    if t.cx >= t.cols {
        if t.autowrap {
            t.cx = 0usize
            linefeed(t)
        } else {
            t.cx = t.cols - 1usize
        }
    }
    let cells = cells_of(t)
    cells[t.cy * t.cols + t.cx] = Cell { ch: cp, fg: t.pen.fg, bg: t.pen.bg, attrs: t.pen.attrs }
    t.cx += 1usize
}

fn cursor_back(t: *Terminal, count: usize) {
    if t.cx == t.cols { t.cx -= 1usize }
    if count > t.cx { t.cx = 0usize } else { t.cx -= count }
}

fn clamp_x(t: *Terminal) {
    if t.cx >= t.cols { t.cx = t.cols - 1usize }
}

fn clamp_y(t: *Terminal) {
    if t.cy >= t.rows { t.cy = t.rows - 1usize }
}

fn param(t: *Terminal, i: usize, fallback: i32) -> i32 {
    if i >= t.param_count { ret fallback }
    let v = t.params[i]
    if v < 0i32 { ret fallback }
    ret v
}

// A count parameter: missing or zero is one.
fn count_param(t: *Terminal, i: usize) -> usize {
    let v = param(t, i, 1i32)
    if v <= 0i32 { ret 1usize }
    ret usize(v)
}

fn erase_in_line(t: *Terminal, how: i32) {
    let cells = cells_of(t)
    let fill = erase_fill(t)
    let row = t.cy * t.cols
    var from = 0usize
    var to = t.cols
    if how == 0i32 {
        from = t.cx
        if from > t.cols { from = t.cols }
    } else if how == 1i32 {
        to = t.cx + 1usize
        if to > t.cols { to = t.cols }
    }
    clear_cells(cells, row + from, row + to, fill)
}

fn erase_in_display(t: *Terminal, how: i32) {
    let cells = cells_of(t)
    let fill = erase_fill(t)
    if how == 0i32 {
        erase_in_line(t, 0i32)
        clear_cells(cells, (t.cy + 1usize) * t.cols, t.rows * t.cols, fill)
    } else if how == 1i32 {
        clear_cells(cells, 0usize, t.cy * t.cols, fill)
        erase_in_line(t, 1i32)
    } else {
        clear_cells(cells, 0usize, t.rows * t.cols, fill)
    }
}

fn insert_chars(t: *Terminal, n: usize) {
    let cells = cells_of(t)
    let row = t.cy * t.cols
    var count = n
    if t.cx >= t.cols { ret }
    if count > t.cols - t.cx { count = t.cols - t.cx }
    var x = t.cols
    while x > t.cx + count {
        x -= 1usize
        cells[row + x] = cells[row + x - count]
    }
    clear_cells(cells, row + t.cx, row + t.cx + count, blank_cell())
}

fn delete_chars(t: *Terminal, n: usize) {
    let cells = cells_of(t)
    let row = t.cy * t.cols
    var count = n
    if t.cx >= t.cols { ret }
    if count > t.cols - t.cx { count = t.cols - t.cx }
    var x = t.cx
    while x + count < t.cols {
        cells[row + x] = cells[row + x + count]
        x += 1usize
    }
    clear_cells(cells, row + t.cols - count, row + t.cols, blank_cell())
}

fn erase_chars(t: *Terminal, n: usize) {
    let cells = cells_of(t)
    let row = t.cy * t.cols
    var to = t.cx + n
    if to > t.cols { to = t.cols }
    if t.cx < t.cols { clear_cells(cells, row + t.cx, row + to, erase_fill(t)) }
}

fn insert_lines(t: *Terminal, n: usize) {
    if t.cy < t.top || t.cy > t.bottom { ret }
    let cells = cells_of(t)
    var count = n
    if count > t.bottom - t.cy + 1usize { count = t.bottom - t.cy + 1usize }
    var y = t.bottom
    while y >= t.cy + count {
        var x = 0usize
        while x < t.cols {
            cells[y * t.cols + x] = cells[(y - count) * t.cols + x]
            x += 1usize
        }
        if y == 0usize { break }
        y -= 1usize
    }
    clear_cells(cells, t.cy * t.cols, (t.cy + count) * t.cols, blank_cell())
    t.cx = 0usize
}

fn delete_lines(t: *Terminal, n: usize) {
    if t.cy < t.top || t.cy > t.bottom { ret }
    let cells = cells_of(t)
    var count = n
    if count > t.bottom - t.cy + 1usize { count = t.bottom - t.cy + 1usize }
    var y = t.cy
    while y + count <= t.bottom {
        var x = 0usize
        while x < t.cols {
            cells[y * t.cols + x] = cells[(y + count) * t.cols + x]
            x += 1usize
        }
        y += 1usize
    }
    clear_cells(cells, (t.bottom + 1usize - count) * t.cols, (t.bottom + 1usize) * t.cols, blank_cell())
    t.cx = 0usize
}

fn sgr(t: *Terminal) {
    if t.param_count == 0usize {
        t.pen = blank_cell()
        ret
    }
    var i = 0usize
    while i < t.param_count {
        let p = t.params[i]
        if p <= 0i32 {
            t.pen = blank_cell()
        } else if p == 1i32 {
            t.pen.attrs = t.pen.attrs | BOLD
        } else if p == 3i32 {
            t.pen.attrs = t.pen.attrs | ITALIC
        } else if p == 4i32 {
            t.pen.attrs = t.pen.attrs | UNDERLINE
        } else if p == 5i32 {
            t.pen.attrs = t.pen.attrs | BLINK
        } else if p == 7i32 {
            t.pen.attrs = t.pen.attrs | REVERSE
        } else if p == 9i32 {
            t.pen.attrs = t.pen.attrs | STRIKE
        } else if p == 22i32 {
            t.pen.attrs = t.pen.attrs & ~BOLD
        } else if p == 23i32 {
            t.pen.attrs = t.pen.attrs & ~ITALIC
        } else if p == 24i32 {
            t.pen.attrs = t.pen.attrs & ~UNDERLINE
        } else if p == 25i32 {
            t.pen.attrs = t.pen.attrs & ~BLINK
        } else if p == 27i32 {
            t.pen.attrs = t.pen.attrs & ~REVERSE
        } else if p == 29i32 {
            t.pen.attrs = t.pen.attrs & ~STRIKE
        } else if p >= 30i32 && p <= 37i32 {
            t.pen.fg = u32(p - 29i32)
        } else if p == 39i32 {
            t.pen.fg = 0u32
        } else if p >= 40i32 && p <= 47i32 {
            t.pen.bg = u32(p - 39i32)
        } else if p == 49i32 {
            t.pen.bg = 0u32
        } else if p >= 90i32 && p <= 97i32 {
            t.pen.fg = u32(p - 81i32)
        } else if p >= 100i32 && p <= 107i32 {
            t.pen.bg = u32(p - 91i32)
        } else if p == 38i32 || p == 48i32 {
            var colour = 0u32
            var used = 0usize
            if i + 2usize < t.param_count && t.params[i + 1usize] == 5i32 {
                var n = t.params[i + 2usize]
                if n < 0i32 { n = 0i32 }
                if n > 255i32 { n = 255i32 }
                colour = 256u32 | u32(n)
                used = 2usize
            } else if i + 4usize < t.param_count && t.params[i + 1usize] == 2i32 {
                var r = t.params[i + 2usize]
                var g = t.params[i + 3usize]
                var b = t.params[i + 4usize]
                if r < 0i32 { r = 0i32 }
                if g < 0i32 { g = 0i32 }
                if b < 0i32 { b = 0i32 }
                if r > 255i32 { r = 255i32 }
                if g > 255i32 { g = 255i32 }
                if b > 255i32 { b = 255i32 }
                colour = 16777216u32 | (u32(r) << 16u32) | (u32(g) << 8u32) | u32(b)
                used = 4usize
            }
            if used != 0usize {
                if p == 38i32 { t.pen.fg = colour } else { t.pen.bg = colour }
                i += used
            }
        }
        i += 1usize
    }
}

fn switch_screen(t: *Terminal, alt: bool) {
    if t.alt == alt { ret }
    t.alt = alt
    if alt {
        clear_cells(t.alt_cells, 0usize, t.cols * t.rows, blank_cell())
        t.saved_x = t.cx
        t.saved_y = t.cy
    } else {
        t.cx = t.saved_x
        t.cy = t.saved_y
        clamp_x(t)
        clamp_y(t)
    }
}

fn set_mode(t: *Terminal, on: bool) {
    var i = 0usize
    while i < t.param_count {
        let p = t.params[i]
        if t.private {
            if p == 25i32 { t.cursor_visible = on }
            if p == 7i32 { t.autowrap = on }
            if p == 1049i32 || p == 47i32 || p == 1047i32 { switch_screen(t, on) }
        }
        i += 1usize
    }
}

fn reset(t: *Terminal) {
    clear_cells(t.main_cells, 0usize, t.cols * t.rows, blank_cell())
    clear_cells(t.alt_cells, 0usize, t.cols * t.rows, blank_cell())
    t.alt = false
    t.cx = 0usize
    t.cy = 0usize
    t.pen = blank_cell()
    t.top = 0usize
    t.bottom = t.rows - 1usize
    t.cursor_visible = true
    t.autowrap = true
}

fn dispatch_csi(t: *Terminal, final: u8) {
    if final == 64u8 {
        insert_chars(t, count_param(t, 0usize))
    } else if final == 65u8 {
        let n = count_param(t, 0usize)
        if t.cy < t.top + n { t.cy = t.top } else { t.cy -= n }
    } else if final == 66u8 {
        t.cy += count_param(t, 0usize)
        if t.cy > t.bottom { t.cy = t.bottom }
    } else if final == 67u8 {
        t.cx += count_param(t, 0usize)
        clamp_x(t)
    } else if final == 68u8 {
        cursor_back(t, count_param(t, 0usize))
    } else if final == 69u8 {
        t.cy += count_param(t, 0usize)
        if t.cy > t.bottom { t.cy = t.bottom }
        t.cx = 0usize
    } else if final == 70u8 {
        let n = count_param(t, 0usize)
        if t.cy < t.top + n { t.cy = t.top } else { t.cy -= n }
        t.cx = 0usize
    } else if final == 71u8 {
        t.cx = count_param(t, 0usize) - 1usize
        clamp_x(t)
    } else if final == 72u8 || final == 102u8 {
        t.cy = count_param(t, 0usize) - 1usize
        t.cx = count_param(t, 1usize) - 1usize
        clamp_x(t)
        clamp_y(t)
    } else if final == 74u8 {
        erase_in_display(t, param(t, 0usize, 0i32))
    } else if final == 75u8 {
        erase_in_line(t, param(t, 0usize, 0i32))
    } else if final == 76u8 {
        insert_lines(t, count_param(t, 0usize))
    } else if final == 77u8 {
        delete_lines(t, count_param(t, 0usize))
    } else if final == 80u8 {
        delete_chars(t, count_param(t, 0usize))
    } else if final == 83u8 {
        scroll_up(t, count_param(t, 0usize))
    } else if final == 84u8 {
        scroll_down(t, count_param(t, 0usize))
    } else if final == 88u8 {
        erase_chars(t, count_param(t, 0usize))
    } else if final == 100u8 {
        t.cy = count_param(t, 0usize) - 1usize
        clamp_y(t)
    } else if final == 104u8 {
        set_mode(t, true)
    } else if final == 108u8 {
        set_mode(t, false)
    } else if final == 109u8 {
        sgr(t)
    } else if final == 114u8 {
        if t.param_count == 0usize {
            t.top = 0usize
            t.bottom = t.rows - 1usize
            t.cx = 0usize
            t.cy = 0usize
        } else {
            var top = count_param(t, 0usize) - 1usize
            var bottom = t.rows - 1usize
            if t.param_count > 1usize && t.params[1usize] > 0i32 { bottom = usize(t.params[1usize]) - 1usize }
            if top > t.rows - 1usize { top = t.rows - 1usize }
            if bottom > t.rows - 1usize { bottom = t.rows - 1usize }
            if bottom > top {
                t.top = top
                t.bottom = bottom
                t.cx = 0usize
                t.cy = 0usize
            }
        }
    } else if final == 115u8 {
        t.saved_x = t.cx
        t.saved_y = t.cy
        t.saved_pen = t.pen
    } else if final == 117u8 {
        t.cx = t.saved_x
        t.cy = t.saved_y
        t.pen = t.saved_pen
        clamp_x(t)
        clamp_y(t)
    }
}

fn control(t: *Terminal, byte: u8) {
    if byte == 8u8 {
        cursor_back(t, 1usize)
    } else if byte == 9u8 {
        var next = (t.cx / 8usize + 1usize) * 8usize
        if next >= t.cols { next = t.cols - 1usize }
        t.cx = next
    } else if byte == 10u8 || byte == 11u8 || byte == 12u8 {
        linefeed(t)
    } else if byte == 13u8 {
        t.cx = 0usize
    }
}

fn feed_byte(t: *Terminal, byte: u8) {
    if t.state == GROUND {
        if byte == 27u8 {
            t.state = ESCAPE
            t.utf8_left = 0usize
        } else if byte < 32u8 || byte == 127u8 {
            control(t, byte)
        } else if byte < 128u8 {
            t.utf8_left = 0usize
            put_char(t, u32(byte))
        } else if t.utf8_left > 0usize && (byte & 192u8) == 128u8 {
            t.utf8_value = (t.utf8_value << 6u32) | u32(byte & 63u8)
            t.utf8_left -= 1usize
            if t.utf8_left == 0usize { put_char(t, t.utf8_value) }
        } else if (byte & 224u8) == 192u8 {
            t.utf8_value = u32(byte & 31u8)
            t.utf8_left = 1usize
        } else if (byte & 240u8) == 224u8 {
            t.utf8_value = u32(byte & 15u8)
            t.utf8_left = 2usize
        } else if (byte & 248u8) == 240u8 {
            t.utf8_value = u32(byte & 7u8)
            t.utf8_left = 3usize
        } else {
            t.utf8_left = 0usize
            put_char(t, 65533u32)
        }
    } else if t.state == ESCAPE {
        t.state = GROUND
        if byte == 91u8 {
            t.state = CSI
            t.param_count = 0usize
            t.private = false
            var k = 0usize
            while k < 16usize {
                t.params[k] = 0i32
                k += 1usize
            }
        } else if byte == 93u8 {
            t.state = OSC
        } else if byte == 40u8 || byte == 41u8 || byte == 42u8 || byte == 43u8 {
            t.state = CHARSET
        } else if byte == 55u8 {
            t.saved_x = t.cx
            t.saved_y = t.cy
            t.saved_pen = t.pen
        } else if byte == 56u8 {
            t.cx = t.saved_x
            t.cy = t.saved_y
            t.pen = t.saved_pen
        } else if byte == 68u8 {
            linefeed(t)
        } else if byte == 69u8 {
            t.cx = 0usize
            linefeed(t)
        } else if byte == 77u8 {
            reverse_index(t)
        } else if byte == 99u8 {
            reset(t)
        }
    } else if t.state == CHARSET {
        t.state = GROUND
    } else if t.state == OSC {
        if byte == 7u8 {
            t.state = GROUND
        } else if byte == 27u8 {
            t.state = OSC_ESC
        }
    } else if t.state == OSC_ESC {
        t.state = GROUND
    } else if t.state == CSI || t.state == IGNORE_CSI {
        if byte >= 48u8 && byte <= 57u8 {
            if t.param_count == 0usize { t.param_count = 1usize }
            let at = t.param_count - 1usize
            if at < 16usize {
                var v = t.params[at]
                if v < 0i32 { v = 0i32 }
                if v < 100000i32 { t.params[at] = v * 10i32 + i32(byte - 48u8) }
            }
        } else if byte == 59u8 || byte == 58u8 {
            if t.param_count == 0usize { t.param_count = 1usize }
            if t.param_count < 16usize { t.param_count += 1usize }
        } else if byte == 63u8 || byte == 62u8 || byte == 33u8 {
            t.private = true
        } else if byte >= 32u8 && byte <= 47u8 {
            t.state = IGNORE_CSI
        } else if byte >= 64u8 && byte <= 126u8 {
            if t.state == CSI { dispatch_csi(t, byte) }
            t.state = GROUND
        } else if byte == 27u8 {
            t.state = ESCAPE
        } else if byte < 32u8 {
            control(t, byte)
        } else {
            t.state = GROUND
        }
    }
}

// Feed output bytes to the terminal.
fn feed(t: *Terminal, data: []const u8) {
    var i = 0usize
    while i < data.len {
        feed_byte(t, data[i])
        i += 1usize
    }
}

// Resize to `cols` x `rows`: the overlapping part of each screen is kept from the top left, the scrollback is
// dropped, the region and the cursor are clamped.
fn resize(a: *mem.Arena, t: *Terminal, cols: usize, rows: usize) -> err {
    let (main_cells, main_error) = mem.alloc[Cell](a, cols * rows)
    if main_error != ok { ret main_error }
    let (alt_cells, alt_error) = mem.alloc[Cell](a, cols * rows)
    if alt_error != ok { ret alt_error }
    var i = 0usize
    while i < cols * rows {
        main_cells[i] = blank_cell()
        alt_cells[i] = blank_cell()
        i += 1usize
    }
    var y = 0usize
    while y < rows && y < t.rows {
        var x = 0usize
        while x < cols && x < t.cols {
            main_cells[y * cols + x] = t.main_cells[y * t.cols + x]
            alt_cells[y * cols + x] = t.alt_cells[y * t.cols + x]
            x += 1usize
        }
        y += 1usize
    }
    t.main_cells = main_cells
    t.alt_cells = alt_cells
    t.cols = cols
    t.rows = rows
    t.top = 0usize
    t.bottom = rows - 1usize
    t.scroll_count = 0usize
    t.scroll_start = 0usize
    t.scroll_cap = 0usize
    if t.cx > cols { t.cx = cols }
    clamp_y(t)
    ret ok
}
