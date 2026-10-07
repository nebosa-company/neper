// Lunar Calc (D2205), the first full app screen of the lunar UI (ux/calculator.jpg): cream cards on a
// dark ground, a display with the running expression and the result, a four-by-five keypad, a status
// card. It is a real calculator -- digits, a decimal point, + - x / on the usual immediate-execution
// model, =, C, +/-, sqrt and DEL -- driven by taps the compositor routes to it (appkit.e). A tap on
// the bar at the bottom of the screen leaves the app and the shell redraws Home.
// Started by the shell with the lunar fonts as args[1..5].
use e.mem
use e.os
use e.math
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use appkit
use text

const COLS: usize = 4usize
const ROWS: usize = 5usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

// Print a string that lives in the arena: the console call reads the program's own window only, so
// the bytes go through a buffer on the stack.
fn say_text(value: str) {
    var buffer: [32]u8 = zero
    var n = 0usize
    while n < value.len && n < 32usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

// What a key is: its character code, as the engine takes it.
fn key_at(row: usize, col: usize) -> u8 {
    if row == 0usize {
        if col == 0usize { ret 67u8 }
        if col == 1usize { ret 78u8 }
        if col == 2usize { ret 82u8 }
        ret 47u8
    }
    if row == 1usize {
        if col == 0usize { ret 55u8 }
        if col == 1usize { ret 56u8 }
        if col == 2usize { ret 57u8 }
        ret 42u8
    }
    if row == 2usize {
        if col == 0usize { ret 52u8 }
        if col == 1usize { ret 53u8 }
        if col == 2usize { ret 54u8 }
        ret 45u8
    }
    if row == 3usize {
        if col == 0usize { ret 49u8 }
        if col == 1usize { ret 50u8 }
        if col == 2usize { ret 51u8 }
        ret 43u8
    }
    if col == 0usize { ret 48u8 }
    if col == 1usize { ret 46u8 }
    if col == 2usize { ret 68u8 }
    ret 61u8
}

// The text on a key.
fn key_label(key: u8) -> str {
    if key == 67u8 { ret "C" }
    if key == 78u8 { ret "\xC2\xB1" }
    if key == 82u8 { ret "sqrt" }
    if key == 47u8 { ret "\xC3\xB7" }
    if key == 42u8 { ret "\xC3\x97" }
    if key == 45u8 { ret "\xE2\x88\x92" }
    if key == 43u8 { ret "+" }
    if key == 61u8 { ret "=" }
    if key == 68u8 { ret "DEL" }
    if key == 46u8 { ret "." }
    var digit: [1]u8 = zero
    digit[0usize] = key
    ret ""
}

fn is_digit(key: u8) -> bool {
    ret key >= 48u8 && key <= 57u8
}

fn is_operator(key: u8) -> bool {
    ret key == 43u8 || key == 45u8 || key == 42u8 || key == 47u8
}

// The calculator's state: the accumulated value, the number being typed, the operator waiting, and
// the expression shown above the result.
type Calc = struct { acc: f64, entry: [16]u8, entry_len: usize, op: u8, pending: bool, fresh: bool, failed: bool, expr: [64]u8, expr_len: usize }

fn expr_add(c: *Calc, byte: u8) {
    if c.expr_len < 64usize {
        c.expr[c.expr_len] = byte
        c.expr_len += 1usize
    }
}

// The UTF-8 of an operator, for the expression line.
fn expr_operator(c: *Calc, op: u8) {
    expr_add(c, 32u8)
    if op == 42u8 {
        expr_add(c, 195u8)
        expr_add(c, 151u8)
    } else if op == 47u8 {
        expr_add(c, 195u8)
        expr_add(c, 183u8)
    } else if op == 45u8 {
        expr_add(c, 226u8)
        expr_add(c, 136u8)
        expr_add(c, 146u8)
    } else {
        expr_add(c, op)
    }
    expr_add(c, 32u8)
}

fn expr_entry(c: *Calc) {
    var i = 0usize
    while i < c.entry_len {
        expr_add(c, c.entry[i])
        i += 1usize
    }
}

// The typed number as a value.
fn entry_value(c: *Calc) -> f64 {
    var value = 0.0f64
    var scale = 1.0f64
    var after_point = false
    var i = 0usize
    while i < c.entry_len {
        let ch = c.entry[i]
        if ch == 46u8 {
            after_point = true
        } else if after_point {
            scale = scale / 10.0f64
            value = value + f64(ch - 48u8) * scale
        } else {
            value = value * 10.0f64 + f64(ch - 48u8)
        }
        i += 1usize
    }
    ret value
}

fn clear(c: *Calc) {
    c.acc = 0.0f64
    c.entry_len = 0usize
    c.op = 0u8
    c.pending = false
    c.fresh = false
    c.failed = false
    c.expr_len = 0usize
}

fn apply(c: *Calc, left: f64, op: u8, right: f64) -> f64 {
    if op == 43u8 { ret left + right }
    if op == 45u8 { ret left - right }
    if op == 42u8 { ret left * right }
    if right == 0.0f64 {
        c.failed = true
        ret 0.0f64
    }
    ret left / right
}

// The value on the display: the typed number, else the accumulator.
fn shown_value(c: *Calc) -> f64 {
    if c.entry_len > 0usize { ret entry_value(c) }
    ret c.acc
}

// Put a value into the typed-number buffer, as text (up to eight decimals, trailing zeros trimmed).
fn set_entry(c: *Calc, value: f64) {
    c.entry_len = 0usize
    var v = value
    if v < 0.0f64 {
        c.entry[0usize] = 45u8
        c.entry_len = 1usize
        v = 0.0f64 - v
    }
    if v >= 1000000000000.0f64 {
        c.failed = true
        c.entry_len = 0usize
        ret
    }
    let whole = i64(v)
    var fraction = v - f64(whole)
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = whole
    var open = true
    while open {
        digits[count] = u8(rest % 10i64) + 48u8
        count += 1usize
        rest = rest / 10i64
        if rest == 0i64 { open = false }
    }
    while count > 0usize {
        count -= 1usize
        c.entry[c.entry_len] = digits[count]
        c.entry_len += 1usize
    }
    // Up to eight decimals, at most 15 characters in all.
    var decimals = 0usize
    var point_at = c.entry_len
    var scaled = i64(fraction * 100000000.0f64 + 0.5f64)
    if scaled > 0i64 {
        c.entry[c.entry_len] = 46u8
        c.entry_len += 1usize
        var fraction_digits: [8]u8 = zero
        var d = 8usize
        while d > 0usize {
            d -= 1usize
            fraction_digits[d] = u8(scaled % 10i64) + 48u8
            scaled = scaled / 10i64
        }
        var last = 8usize
        while last > 0usize && fraction_digits[last - 1usize] == 48u8 { last -= 1usize }
        var f = 0usize
        while f < last && c.entry_len < 15usize {
            c.entry[c.entry_len] = fraction_digits[f]
            c.entry_len += 1usize
            f += 1usize
        }
        if last == 0usize { c.entry_len = point_at }
    }
}

// One key press.
fn press(c: *Calc, key: u8) {
    if key == 67u8 {
        clear(c)
        ret
    }
    if c.failed {
        clear(c)
    }
    if is_digit(key) || key == 46u8 {
        if c.fresh {
            clear(c)
        }
        if key == 46u8 {
            var has_point = false
            var i = 0usize
            while i < c.entry_len {
                if c.entry[i] == 46u8 { has_point = true }
                i += 1usize
            }
            if has_point { ret }
            if c.entry_len == 0usize {
                c.entry[0usize] = 48u8
                c.entry_len = 1usize
            }
        }
        if c.entry_len < 12usize {
            c.entry[c.entry_len] = key
            c.entry_len += 1usize
        }
        ret
    }
    if key == 68u8 {
        if c.entry_len > 0usize { c.entry_len -= 1usize }
        ret
    }
    if key == 78u8 {
        if c.entry_len > 0usize {
            if c.entry[0usize] == 45u8 {
                var i = 1usize
                while i < c.entry_len {
                    c.entry[i - 1usize] = c.entry[i]
                    i += 1usize
                }
                c.entry_len -= 1usize
            } else if c.entry_len < 15usize {
                var i = c.entry_len
                while i > 0usize {
                    c.entry[i] = c.entry[i - 1usize]
                    i -= 1usize
                }
                c.entry[0usize] = 45u8
                c.entry_len += 1usize
            }
        } else {
            c.acc = 0.0f64 - c.acc
        }
        ret
    }
    if key == 82u8 {
        let v = shown_value(c)
        if v < 0.0f64 {
            c.failed = true
            ret
        }
        c.fresh = false
        set_entry(c, math.sqrt[f64](v))
        ret
    }
    if is_operator(key) {
        if c.entry_len > 0usize {
            let typed = entry_value(c)
            if c.pending {
                c.acc = apply(c, c.acc, c.op, typed)
            } else {
                c.acc = typed
            }
            expr_entry(c)
        } else if !c.pending && c.expr_len == 0usize {
            expr_add(c, 48u8)
        }
        if c.fresh {
            c.expr_len = 0usize
            expr_entry(c)
        }
        c.entry_len = 0usize
        c.fresh = false
        c.op = key
        c.pending = true
        expr_operator(c, key)
        ret
    }
    if key == 61u8 {
        if c.pending && c.entry_len > 0usize {
            let typed = entry_value(c)
            expr_entry(c)
            expr_add(c, 32u8)
            expr_add(c, 61u8)
            let result = apply(c, c.acc, c.op, typed)
            c.pending = false
            c.acc = result
            set_entry(c, result)
            c.fresh = true
        }
        ret
    }
}

// The display's main line: "Error" after a failure, the typed number, else the accumulator.
fn display_text(a: *mem.Arena, c: *Calc) -> str {
    if c.failed { ret "Error" }
    if c.entry_len > 0usize {
        let (buffer, buffer_error) = mem.alloc[u8](a, c.entry_len)
        if buffer_error != ok { ret "0" }
        var i = 0usize
        while i < c.entry_len {
            buffer[i] = c.entry[i]
            i += 1usize
        }
        ret buffer[0usize..c.entry_len]
    }
    var shown = Calc { acc: c.acc, entry: c.entry, entry_len: 0usize, op: 0u8, pending: false, fresh: false, failed: false, expr: c.expr, expr_len: 0usize }
    set_entry(&shown, c.acc)
    let (buffer, buffer_error) = mem.alloc[u8](a, shown.entry_len + 1usize)
    if buffer_error != ok { ret "0" }
    var i = 0usize
    while i < shown.entry_len {
        buffer[i] = shown.entry[i]
        i += 1usize
    }
    ret buffer[0usize..shown.entry_len]
}

fn cream(alpha: f32) -> paint.Color {
    ret paint.Color { red: 0.92, green: 0.90, blue: 0.86, alpha: alpha }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

// The whole screen for the current state.
fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, c: *Calc) -> err {
    let faces = kit.faces
    // The backdrop's alpha alternates by 0.2% each frame (invisible): the renderer redraws only the
    // box of what changed, and left a changed text box without the cards under it, so a frame that
    // always differs in its first command is drawn whole.
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    // The title card and the main card.
    try card(a, builder, 20.0, 40.0, 372.0, 56.0, 14.0, cream(0.96))
    let (t0, e0) = text.draw(a, builder, faces.sora, 22.0, "LUNAR CALC", 36.0, 53.0, 0.0, 0u32, layout.Align.Start, ink())
    if e0 != ok { ret e0 }
    try card(a, builder, 20.0, 108.0, 372.0, 730.0, 16.0, cream(0.92))
    let (t1, e1) = text.draw(a, builder, faces.jost, 18.0, "Precision Computing", 36.0, 120.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 })
    if e1 != ok { ret e1 }
    // The display: the expression above the result.
    try card(a, builder, 36.0, 152.0, 340.0, 128.0, 10.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    if c.expr_len > 0usize {
        let (expr, expr_error) = mem.alloc[u8](a, c.expr_len)
        if expr_error != ok { ret expr_error }
        var i = 0usize
        while i < c.expr_len {
            expr[i] = c.expr[i]
            i += 1usize
        }
        let (t2, e2) = text.draw(a, builder, faces.grotesk, 16.0, expr[0usize..c.expr_len], 364.0 - text.measure(a, faces.grotesk, 16.0, expr[0usize..c.expr_len]), 162.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
        if e2 != ok { ret e2 }
    }
    let result_text = display_text(a, c)
    let (t3, e3) = text.draw(a, builder, faces.jost, 54.0, result_text, 364.0 - text.measure(a, faces.jost, 54.0, result_text), 200.0, 0.0, 0u32, layout.Align.Start, ink())
    if e3 != ok { ret e3 }
    // The keypad.
    var row = 0usize
    while row < ROWS {
        var col = 0usize
        while col < COLS {
            let key = key_at(row, col)
            let x = 36.0 + f32(col) * 88.0
            let y = 296.0 + f32(row) * 80.0
            var fill = paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
            if is_operator(key) { fill = paint.Color { red: 0.66, green: 0.66, blue: 0.67, alpha: 1.0 } }
            if key == 61u8 { fill = paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
            if key == 67u8 || key == 78u8 || key == 82u8 || key == 68u8 { fill = paint.Color { red: 0.80, green: 0.79, blue: 0.78, alpha: 1.0 } }
            try card(a, builder, x, y + 3.0, 76.0, 70.0, 12.0, paint.Color { red: 0.25, green: 0.24, blue: 0.22, alpha: 0.28 })
            try card(a, builder, x, y, 76.0, 70.0, 12.0, fill)
            var label = key_label(key)
            if is_digit(key) {
                let (digit, digit_error) = mem.alloc[u8](a, 1usize)
                if digit_error != ok { ret digit_error }
                digit[0usize] = key
                label = digit[0usize..1usize]
            }
            let width = text.measure(a, faces.grotesk, 26.0, label)
            let (kt, ke) = text.draw(a, builder, faces.grotesk, 26.0, label, x + 38.0 - width / 2.0, y + 19.0, 0.0, 0u32, layout.Align.Start, ink())
            if ke != ok { ret ke }
            col += 1usize
        }
        row += 1usize
    }
    // The status card.
    try card(a, builder, 36.0, 710.0, 340.0, 108.0, 12.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    let (s1, se1) = text.draw(a, builder, faces.exo, 15.0, "STATUS", 52.0, 722.0, 0.0, 0u32, layout.Align.Start, ink())
    if se1 != ok { ret se1 }
    let (s2, se2) = text.draw(a, builder, faces.exo, 15.0, "MODE: BASIC", 52.0, 748.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
    if se2 != ok { ret se2 }
    let (s3, se3) = text.draw(a, builder, faces.exo, 15.0, "PRECISION: 8 DECIMALS", 52.0, 772.0, 0.0, 0u32, layout.Align.Start, paint.Color { red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0 })
    if se3 != ok { ret se3 }
    // The home bar.
    try card(a, builder, 156.0, 876.0, 100.0, 6.0, 3.0, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "calc")
    if kit_error != ok {
        say("calc open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("calc fonts absent\n")
        ret ok
    }
    var calc: Calc = zero
    let (first, first_error) = appkit.begin(a, &kit)
    if first_error != ok { ret first_error }
    var builder = first
    try draw(a, &builder, &kit, &calc)
    if !appkit.present(&kit, &builder) {
        say("calc present failed\n")
        ret ok
    }
    say("calc shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.y >= 850.0 {
            say("calc home\n")
            appkit.leave()
            running = false
        } else {
            let row_f = (tap.y - 296.0) / 80.0
            let col_f = (tap.x - 36.0) / 88.0
            var hit = false
            if tap.y >= 296.0 && tap.x >= 36.0 && row_f < 5.0 && col_f < 4.0 {
                let row = usize(row_f)
                let col = usize(col_f)
                let in_key_x = tap.x - 36.0 - f32(col) * 88.0 < 76.0
                let in_key_y = tap.y - 296.0 - f32(row) * 80.0 < 70.0
                if in_key_x && in_key_y {
                    hit = true
                    press(&calc, key_at(row, col))
                }
            }
            if hit {
                let (next, next_error) = appkit.begin(a, &kit)
                if next_error != ok { ret next_error }
                var next_builder = next
                try draw(a, &next_builder, &kit, &calc)
                if !appkit.present(&kit, &next_builder) {
                    say("calc present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
                say("calc shows ")
                say_text(display_text(a, &calc))
                say("\n")
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
