// Flashlight (D2228): the app behind the Flashlight icon -- three tabs: Steady (a big power button and a
// brightness of five steps), Pattern (Strobe, SOS, Beacon and Heartbeat, started and stopped), and Morse
// (a message typed on the on-screen keyboard, sent as flashes: a dot is one beat of light, a dash three,
// with the gaps of Morse code; the dots and dashes are shown, and the one being sent is marked). When the
// light is on, the screen itself turns bright. Dark ground, cream cards and amber, like the other apps
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app.
// ponytail: there is no torch hardware here, so the "light" is the SCREEN turning bright. A beat is one
// 500 ms tick of the input server (so the fastest flash is two a second, and SOS takes about thirteen
// seconds); the strobe cannot go faster until there is a finer timer. The real LED, its brightness levels
// and a faster beat are queued as C133.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui

const NONE: usize = 99usize
const STEADY_TAB: usize = 0usize
const PATTERN_TAB: usize = 1usize
const MORSE_TAB: usize = 2usize
const MAX_BITS: usize = 400usize

type State = struct {
    tab: usize,
    steady_on: bool,
    brightness: usize,
    // A running pattern: its beats (one a tick), where it is, whether it loops, and whether it runs.
    bits: [400]u8,
    bit_total: usize,
    at: usize,
    looping: bool,
    running: bool,
    pattern: usize,
    message: ui.Field,
    lit: bool,
    hits: ui.Hits,
}

fn pattern_name(index: usize) -> str {
    if index == 0usize { ret "Strobe" }
    if index == 1usize { ret "SOS" }
    if index == 2usize { ret "Beacon" }
    ret "Heartbeat"
}

// The Morse code of a letter or digit as dots and dashes, "" for anything else.
fn morse(c: u8) -> str {
    var u = c
    if u >= 97u8 && u <= 122u8 { u = u - 32u8 }
    if u == 65u8 { ret ".-" }
    if u == 66u8 { ret "-..." }
    if u == 67u8 { ret "-.-." }
    if u == 68u8 { ret "-.." }
    if u == 69u8 { ret "." }
    if u == 70u8 { ret "..-." }
    if u == 71u8 { ret "--." }
    if u == 72u8 { ret "...." }
    if u == 73u8 { ret ".." }
    if u == 74u8 { ret ".---" }
    if u == 75u8 { ret "-.-" }
    if u == 76u8 { ret ".-.." }
    if u == 77u8 { ret "--" }
    if u == 78u8 { ret "-." }
    if u == 79u8 { ret "---" }
    if u == 80u8 { ret ".--." }
    if u == 81u8 { ret "--.-" }
    if u == 82u8 { ret ".-." }
    if u == 83u8 { ret "..." }
    if u == 84u8 { ret "-" }
    if u == 85u8 { ret "..-" }
    if u == 86u8 { ret "...-" }
    if u == 87u8 { ret ".--" }
    if u == 88u8 { ret "-..-" }
    if u == 89u8 { ret "-.--" }
    if u == 90u8 { ret "--.." }
    if u == 48u8 { ret "-----" }
    if u == 49u8 { ret ".----" }
    if u == 50u8 { ret "..---" }
    if u == 51u8 { ret "...--" }
    if u == 52u8 { ret "....-" }
    if u == 53u8 { ret "....." }
    if u == 54u8 { ret "-...." }
    if u == 55u8 { ret "--..." }
    if u == 56u8 { ret "---.." }
    if u == 57u8 { ret "----." }
    ret ""
}

fn push_bit(s: *State, on: bool) {
    if s.bit_total < MAX_BITS {
        if on { s.bits[s.bit_total] = 1u8 } else { s.bits[s.bit_total] = 0u8 }
        s.bit_total += 1usize
    }
}

// The beats of a message: a dot is 1 on, a dash 3 on, 1 off between signs, 3 off between letters, 7 off
// between words.
fn build_morse(s: *State, message: str) {
    s.bit_total = 0usize
    var i = 0usize
    while i < message.len {
        let c = message[i]
        if c == 32u8 {
            var gap = 0usize
            while gap < 4usize {
                push_bit(s, false)
                gap += 1usize
            }
        } else {
            let code = morse(c)
            var k = 0usize
            while k < code.len {
                push_bit(s, true)
                if code[k] == 45u8 {
                    push_bit(s, true)
                    push_bit(s, true)
                }
                if k + 1usize < code.len { push_bit(s, false) }
                k += 1usize
            }
            if code.len > 0usize && i + 1usize < message.len && message[i + 1usize] != 32u8 {
                push_bit(s, false)
                push_bit(s, false)
                push_bit(s, false)
            }
        }
        i += 1usize
    }
}

fn build_pattern(s: *State, pattern: usize) {
    s.bit_total = 0usize
    if pattern == 0usize {
        push_bit(s, true)
        push_bit(s, false)
    } else if pattern == 1usize {
        build_morse(s, "sos")
        var gap = 0usize
        while gap < 6usize {
            push_bit(s, false)
            gap += 1usize
        }
    } else if pattern == 2usize {
        var on = 0usize
        while on < 3usize {
            push_bit(s, true)
            on += 1usize
        }
        var off = 0usize
        while off < 7usize {
            push_bit(s, false)
            off += 1usize
        }
    } else {
        push_bit(s, true)
        push_bit(s, false)
        push_bit(s, true)
        var off = 0usize
        while off < 5usize {
            push_bit(s, false)
            off += 1usize
        }
    }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn power_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M12 3v9M6.3 6.5a8 8 0 1 0 11.4 0' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round'/></svg>"
}

// The morse of the message as one line of signs, with the sign being sent marked by its position.
fn morse_line(a: *mem.Arena, message: str) -> str {
    var line = ""
    var i = 0usize
    while i < message.len {
        if message[i] == 32u8 {
            line = ui.join(a, line, "   ", "")
        } else {
            line = ui.join(a, line, morse(message[i]), " ")
        }
        i += 1usize
    }
    ret line
}

fn draw_steady(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var ring = paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 }
    var core = paint.Color { red: 0.14, green: 0.15, blue: 0.18, alpha: 1.0 }
    var glyph = ui.light_muted()
    if s.steady_on {
        ring = paint.Color { red: 0.99, green: 0.88, blue: 0.62, alpha: 1.0 }
        core = ui.amber()
        glyph = ui.ink()
    }
    try ui.disc(a, builder, 206.0, 300.0, 108.0, ring)
    try ui.disc(a, builder, 206.0, 300.0, 92.0, core)
    try svg.draw(a, builder, power_icon(), geometry.rect(166.0, 260.0, 80.0, 80.0), glyph)
    ui.hit(&s.hits, 200usize, 98.0, 192.0, 216.0, 216.0)
    var label = "Tap to turn on"
    if s.steady_on { label = "On" }
    try ui.centred(a, builder, faces.jost, 22.0, label, 206.0, 430.0, ui.ink())
    try ui.card(a, builder, 16.0, 500.0, 380.0, 96.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost, 17.0, "Brightness", 32.0, 514.0, ui.ink())
    var step = 0usize
    while step < 5usize {
        var fill = ui.soft()
        if step < s.brightness { fill = ui.amber() }
        try ui.card(a, builder, 32.0 + f32(step) * 70.0, 548.0, 62.0, 32.0, 10.0, fill)
        ui.hit(&s.hits, 210usize + step, 32.0 + f32(step) * 70.0, 540.0, 62.0, 48.0)
        step += 1usize
    }
    ret ok
}

fn draw_pattern(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var pat = 0usize
    while pat < 4usize {
        var fill = ui.soft()
        if pat == s.pattern { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 220usize + pat, 16.0 + f32(pat % 2usize) * 196.0, 100.0 + f32(pat / 2usize) * 64.0, 184.0, 48.0, pattern_name(pat), fill, 18.0)
        pat += 1usize
    }
    var label = "Start"
    if s.running { label = "Stop" }
    try ui.pill(a, builder, &s.hits, faces, 230usize, 106.0, 260.0, 200.0, 56.0, label, ui.amber(), 20.0)
    // The beats of the pattern, the present one marked.
    try ui.card(a, builder, 16.0, 350.0, 380.0, 90.0, 18.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "Beats (one every half second)", 32.0, 362.0, ui.muted())
    var i = 0usize
    while i < s.bit_total && i < 24usize {
        var fill = ui.soft()
        if s.bits[i] != 0u8 { fill = ui.amber_dark() }
        if s.running && i == s.at % s.bit_total { fill = ui.ink() }
        try ui.card(a, builder, 32.0 + f32(i) * 15.0, 390.0, 12.0, 30.0, 3.0, fill)
        i += 1usize
    }
    ret ok
}

fn draw_morse(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let message = ui.field_text(a, &s.message)
    try ui.card(a, builder, 14.0, 98.0, 384.0, 56.0, 18.0, ui.amber())
    try ui.card(a, builder, 16.0, 100.0, 380.0, 52.0, 16.0, ui.cream())
    if message.len == 0usize { try ui.put(a, builder, faces.jost, 18.0, "Type a message, like SOS or HELP", 32.0, 114.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 20.0, message, 32.0, 112.0, 340.0, ui.ink()) }
    try ui.pill(a, builder, &s.hits, faces, 240usize, 16.0, 170.0, 186.0, 46.0, "Flash", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 241usize, 210.0, 170.0, 186.0, 46.0, "Stop", ui.soft(), 17.0)
    try ui.card(a, builder, 16.0, 232.0, 380.0, 86.0, 16.0, ui.cream())
    try ui.clipped(a, builder, faces.grotesk, 20.0, morse_line(a, message), 32.0, 248.0, 348.0, ui.ink())
    var progress = ui.join(a, ui.number(a, s.bit_total), " beats", "")
    if s.running { progress = ui.join(a, ui.number(a, s.at), " of ", ui.join(a, ui.number(a, s.bit_total), " beats", "")) }
    try ui.put(a, builder, faces.grotesk, 12.0, progress, 32.0, 290.0, ui.muted())
    try ui.keyboard(a, builder, &s.hits, faces, "Flash")
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    var lit = s.lit
    if s.tab == STEADY_TAB && s.steady_on { lit = true }
    if lit {
        // The "light": the whole screen turns bright, by the brightness.
        let level = 0.55 + f32(s.brightness) * 0.09
        try ui.ground(builder, kit.frame, kit.logical_h, level, level * 0.96, level * 0.82)
    } else {
        try ui.ground(builder, kit.frame, kit.logical_h, 0.06, 0.07, 0.09)
    }
    var tab = 0usize
    while tab < 3usize {
        var label = "Steady"
        if tab == 1usize { label = "Pattern" }
        if tab == 2usize { label = "Morse" }
        var fill = ui.soft()
        if tab == s.tab { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + tab, 16.0 + f32(tab) * 130.0, 24.0, 120.0, 40.0, label, fill, 16.0)
        tab += 1usize
    }
    if s.tab == STEADY_TAB { try draw_steady(a, builder, s, faces) }
    if s.tab == PATTERN_TAB { try draw_pattern(a, builder, s, faces) }
    if s.tab == MORSE_TAB { try draw_morse(a, builder, s, faces) }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn stop(s: *State) {
    if s.running {
        s.running = false
        s.lit = false
        ui.say("flashlight stopped\n")
    }
}

fn start(s: *State, looping: bool) {
    s.at = 0usize
    s.running = true
    s.looping = looping
    s.lit = s.bits[0usize] != 0u8
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if id >= 100usize && id < 103usize {
        stop(s)
        s.tab = id - 100usize
        s.steady_on = false
        if s.tab == PATTERN_TAB { build_pattern(s, s.pattern) }
        ret true
    }
    if s.tab == STEADY_TAB {
        if id == 200usize {
            s.steady_on = !s.steady_on
            if s.steady_on { ui.say("flashlight on\n") } else { ui.say("flashlight off\n") }
            ret true
        }
        if id >= 210usize && id < 215usize {
            s.brightness = id - 210usize + 1usize
            ret true
        }
        ret false
    }
    if s.tab == PATTERN_TAB {
        if id >= 220usize && id < 224usize {
            stop(s)
            s.pattern = id - 220usize
            build_pattern(s, s.pattern)
            ret true
        }
        if id == 230usize {
            if s.running {
                stop(s)
            } else {
                build_pattern(s, s.pattern)
                start(s, true)
                ui.say("flashlight pattern ")
                ui.say(pattern_name(s.pattern))
                ui.say("\n")
            }
            ret true
        }
        ret false
    }
    // Morse.
    if ui.is_key(id) {
        if id == 1205usize {
            id_flash(a, s)
            ret true
        }
        ret ui.field_key(&s.message, id, false)
    }
    if id == 240usize {
        id_flash(a, s)
        ret true
    }
    if id == 241usize {
        stop(s)
        ret true
    }
    ret false
}

fn id_flash(a: *mem.Arena, s: *State) {
    let message = ui.field_text(a, &s.message)
    if message.len == 0usize { ret }
    build_morse(s, message)
    start(s, false)
    ui.say("flashlight morse ")
    ui.say_text(message)
    ui.say(" ")
    ui.say_num(s.bit_total)
    ui.say("\n")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "flashlight")
    if kit_error != ok {
        ui.say("flashlight open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("flashlight fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.brightness = 5usize
    if !show(a, &kit, &s) {
        ui.say("flashlight present failed\n")
        ret ok
    }
    ui.say("flashlight shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // A running pattern advances one beat a tick; the light follows the beat.
            if s.running && s.bit_total > 0usize {
                s.at += 1usize
                if s.at >= s.bit_total {
                    if s.looping {
                        s.at = 0usize
                    } else {
                        s.running = false
                        s.lit = false
                        ui.say("flashlight morse done\n")
                    }
                }
                if s.running { s.lit = s.bits[s.at] != 0u8 }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("flashlight home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("flashlight present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
