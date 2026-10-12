// Flashlight (D2228): the app behind the Flashlight icon -- three tabs: Steady (a big power button, a brightness of
// five steps and a timer), Pattern (Strobe, SOS, Beacon, Heartbeat and the patterns the user saved, started and
// stopped, at a speed of four), and Morse (a message typed on the on-screen keyboard, sent as flashes: a dot is one
// beat of light, a dash three, with the gaps of Morse code; the dots and dashes are shown, and the one being sent is
// marked; Save keeps the message as a pattern). When the light is on, the screen itself turns bright. Dark ground,
// cream cards and amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A
// tap on the bar at the bottom leaves the app.
//
// (C163, D4006) The beat is the kernel's receive deadline (appkit.next_touch): a unit of 500, 200, 100 or 50 ms
// (the strobe reaches ten flashes a second), scheduled from the monotonic clock so a late beat does not push the
// next one, and the device follows each beat at once (the settings server's torch); at the slow speeds the screen
// follows too, at the fast ones it is drawn when the run ends, because a frame takes longer than the beat. The run
// measures each beat against its schedule and reports the unit and the lateness at the end. The settings server owns
// the torch's policy: it turns it off after the timer (or five minutes, whatever was asked), so an app that dies
// does not leave it on.
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui
use sysettings
use vaultfs

var tick_debug: usize = 0usize
const NONE: usize = 99usize
const STEADY_TAB: usize = 0usize
const PATTERN_TAB: usize = 1usize
const MORSE_TAB: usize = 2usize
const MAX_BITS: usize = 400usize
const MAX_CUSTOM: usize = 6usize
const NAME_BYTES: usize = 24usize
// The file of the saved patterns and the settings: unit index, timer index, count, then six names (length + 24 bytes).
const FILE_BYTES: usize = 153usize

type State = struct {
    tab: usize,
    steady_on: bool,
    brightness: usize,
    // A running pattern: its beats (one a unit), where it is, whether it loops, and whether it runs.
    bits: [400]u8,
    bit_total: usize,
    at: usize,
    looping: bool,
    running: bool,
    // The pattern chosen: 0 to 3 the built-in ones, 4 and on the saved ones.
    pattern: usize,
    message: ui.Field,
    lit: bool,
    // The torch level last sent to the device (99 before the first), so a change is sent once.
    torch_sent: usize,
    // The beat: the unit in ms, the speed's index, and the steady timer's index (0 the policy's limit).
    unit_ms: usize,
    speed: usize,
    timer: usize,
    // The run's schedule: its start and the next beat (ms of the monotonic clock) and what was measured.
    t0: usize,
    next_at: usize,
    late_max: usize,
    late_sum: usize,
    late_over: usize,
    measured: usize,
    // The saved patterns: how many, their name lengths and bytes.
    ccount: usize,
    clens: [6]usize,
    cnames: [144]u8,
    // Whether the screen has fallen behind (a beat passed): it is redrawn on the next tick, the only moment the
    // compositor takes a frame that is not the answer to an event it forwarded.
    dirty: bool,
    hits: ui.Hits,
}

fn pattern_name(index: usize) -> str {
    if index == 0usize { ret "Strobe" }
    if index == 1usize { ret "SOS" }
    if index == 2usize { ret "Beacon" }
    ret "Heartbeat"
}

fn unit_of(speed: usize) -> usize {
    if speed == 0usize { ret 500usize }
    if speed == 1usize { ret 200usize }
    if speed == 2usize { ret 100usize }
    ret 50usize
}

fn speed_label(speed: usize) -> str {
    if speed == 0usize { ret "500 ms" }
    if speed == 1usize { ret "200 ms" }
    if speed == 2usize { ret "100 ms" }
    ret "50 ms"
}

fn timer_seconds(timer: usize) -> usize {
    if timer == 1usize { ret 5usize }
    if timer == 2usize { ret 30usize }
    if timer == 3usize { ret 120usize }
    ret 0usize
}

fn timer_label(timer: usize) -> str {
    if timer == 1usize { ret "5 s" }
    if timer == 2usize { ret "30 s" }
    if timer == 3usize { ret "2 min" }
    ret "Max"
}

fn now_ms() -> usize {
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret 0usize }
    ret usize(now.nanos / 1000000i64)
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

// The name of saved pattern `j` as a string over the state's bytes.
fn custom_name(s: *State, j: usize) -> str {
    ret s.cnames[j * NAME_BYTES..j * NAME_BYTES + s.clens[j]]
}

fn build_pattern(s: *State, pattern: usize) {
    s.bit_total = 0usize
    if pattern >= 4usize {
        let j = pattern - 4usize
        if j < s.ccount {
            build_morse(s, custom_name(s, j))
            var gap = 0usize
            while gap < 6usize {
                push_bit(s, false)
                gap += 1usize
            }
        }
    } else if pattern == 0usize {
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
// The saved patterns and settings: /flashlight, 153 bytes.

fn load_file(s: *State) {
    var raw: [153]u8 = zero
    let (n, found) = vaultfs.read("/flashlight", mem.address_of(&raw[0usize]), FILE_BYTES)
    if !found || n < FILE_BYTES { ret }
    if usize(raw[0usize]) < 4usize { s.speed = usize(raw[0usize]) }
    if usize(raw[1usize]) < 4usize { s.timer = usize(raw[1usize]) }
    s.unit_ms = unit_of(s.speed)
    var count = usize(raw[2usize])
    if count > MAX_CUSTOM { count = MAX_CUSTOM }
    var j = 0usize
    while j < count {
        let at = 3usize + j * 25usize
        var len = usize(raw[at])
        if len > NAME_BYTES { len = NAME_BYTES }
        s.clens[j] = len
        var k = 0usize
        while k < len {
            s.cnames[j * NAME_BYTES + k] = raw[at + 1usize + k]
            k += 1usize
        }
        j += 1usize
    }
    s.ccount = count
    if count > 0usize {
        ui.say("flashlight loaded ")
        ui.say_num(count)
        ui.say(" patterns\n")
    }
}

fn save_file(s: *State) {
    var raw: [153]u8 = zero
    raw[0usize] = u8(s.speed)
    raw[1usize] = u8(s.timer)
    raw[2usize] = u8(s.ccount)
    var j = 0usize
    while j < s.ccount {
        let at = 3usize + j * 25usize
        raw[at] = u8(s.clens[j])
        var k = 0usize
        while k < s.clens[j] {
            raw[at + 1usize + k] = s.cnames[j * NAME_BYTES + k]
            k += 1usize
        }
        j += 1usize
    }
    let kept = vaultfs.write("/flashlight", mem.address_of(&raw[0usize]), FILE_BYTES)
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

// The four speeds as chips at `y`: ids 260 to 263.
fn draw_speed(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, y: f32) -> err {
    try ui.put(a, builder, faces.grotesk, 12.0, "Unit of a beat", 16.0, y - 18.0, ui.light_muted())
    var sp = 0usize
    while sp < 4usize {
        var fill = ui.soft()
        if sp == s.speed { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 260usize + sp, 16.0 + f32(sp) * 96.0, y, 90.0, 40.0, speed_label(sp), fill, 14.0)
        sp += 1usize
    }
    ret ok
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
    // The timer: the torch turns itself off after it.
    try ui.card(a, builder, 16.0, 610.0, 380.0, 96.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost, 17.0, "Turn off after", 32.0, 624.0, ui.ink())
    var tm = 0usize
    while tm < 4usize {
        var fill = ui.soft()
        if tm == s.timer { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 250usize + tm, 32.0 + f32(tm) * 88.0, 654.0, 80.0, 36.0, timer_label(tm), fill, 14.0)
        tm += 1usize
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
    try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Beats (one every ", speed_label(s.speed), ")"), 32.0, 362.0, ui.muted())
    var i = 0usize
    while i < s.bit_total && i < 24usize {
        var fill = ui.soft()
        if s.bits[i] != 0u8 { fill = ui.amber_dark() }
        if s.running && i == s.at % s.bit_total { fill = ui.ink() }
        try ui.card(a, builder, 32.0 + f32(i) * 15.0, 390.0, 12.0, 30.0, 3.0, fill)
        i += 1usize
    }
    try draw_speed(a, builder, s, faces, 470.0)
    // The saved patterns, after the built-in ones.
    var j = 0usize
    while j < s.ccount {
        var fill = ui.soft()
        if 4usize + j == s.pattern { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 270usize + j, 16.0 + f32(j % 2usize) * 196.0, 540.0 + f32(j / 2usize) * 56.0, 184.0, 48.0, custom_name(s, j), fill, 16.0)
        j += 1usize
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
    try ui.pill(a, builder, &s.hits, faces, 242usize, 16.0, 330.0, 186.0, 36.0, "Save as pattern", ui.soft(), 14.0)
    try draw_speed(a, builder, s, faces, 410.0)
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
    s.dirty = false
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

// (C133, C163) The device follows the light: off, or the brightness step. A steady light under a timer goes to the
// server with its seconds; the server turns it off by itself.
fn apply_torch(s: *State) {
    var lit = s.lit
    if s.tab == STEADY_TAB && s.steady_on { lit = true }
    var level = 0usize
    if lit { level = s.brightness }
    if level == s.torch_sent { ret }
    s.torch_sent = level
    if s.tab == STEADY_TAB && s.steady_on && s.timer != 0usize {
        let (applied, served) = sysettings.torch_for(level, timer_seconds(s.timer))
    } else {
        let (applied, served) = sysettings.torch(level)
    }
}

fn stop(s: *State) {
    if s.running {
        s.running = false
        if s.measured > 0usize { report_run(s) }
        s.lit = false
        apply_torch(s)
        ui.say("flashlight stopped\n")
    }
}

fn start(s: *State, looping: bool) {
    s.at = 0usize
    s.running = true
    s.looping = looping
    s.lit = s.bits[0usize] != 0u8
    s.t0 = now_ms()
    s.next_at = s.t0 + s.unit_ms
    s.late_max = 0usize
    s.late_sum = 0usize
    s.late_over = 0usize
    s.measured = 0usize
}

// The run's report: the unit, the beats measured and how late they were against the schedule.
fn report_run(s: *State) {
    var mean = 0usize
    if s.measured > 0usize { mean = s.late_sum / s.measured }
    ui.say("flashlight beats ")
    ui.say_num(s.measured)
    ui.say(" unit ")
    ui.say_num(s.unit_ms)
    ui.say(" late max ")
    ui.say_num(s.late_max)
    ui.say(" mean ")
    ui.say_num(mean)
    ui.say("\n")
    // The beats came when they were due: the average under half a unit and at most one in ten a whole unit late (a
    // host that stalls the guest for a moment makes a late beat, not a wrong schedule).
    if mean * 2usize <= s.unit_ms && s.late_over * 10usize <= s.measured { ui.say("flashlight timing ok\n") } else { ui.say("flashlight timing slow\n") }
}

// Take the beats that are due: each measured against its schedule, the light and the device following. True when a
// beat passed.
fn advance(s: *State) -> bool {
    var any = false
    let now = now_ms()
    while s.running && now >= s.next_at {
        let late = now - s.next_at
        if late > s.late_max { s.late_max = late }
        if late > s.unit_ms { s.late_over += 1usize }
        s.late_sum += late
        s.measured += 1usize
        s.next_at += s.unit_ms
        s.at += 1usize
        if s.at >= s.bit_total {
            if s.looping {
                s.at = 0usize
            } else {
                s.running = false
                s.lit = false
                apply_torch(s)
                report_run(s)
                ui.say("flashlight morse done\n")
            }
        }
        if s.running {
            s.lit = s.bits[s.at] != 0u8
            apply_torch(s)
        }
        any = true
    }
    ret any
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if id >= 100usize && id < 103usize {
        stop(s)
        s.tab = id - 100usize
        s.steady_on = false
        apply_torch(s)
        if s.tab == PATTERN_TAB { build_pattern(s, s.pattern) }
        ret true
    }
    if id >= 260usize && id < 264usize {
        s.speed = id - 260usize
        s.unit_ms = unit_of(s.speed)
        save_file(s)
        ui.say("flashlight unit ")
        ui.say_num(s.unit_ms)
        ui.say("\n")
        ret true
    }
    if s.tab == STEADY_TAB {
        if id == 200usize {
            s.steady_on = !s.steady_on
            apply_torch(s)
            if s.steady_on { ui.say("flashlight on\n") } else { ui.say("flashlight off\n") }
            ret true
        }
        if id >= 210usize && id < 215usize {
            s.brightness = id - 210usize + 1usize
            s.torch_sent = 99usize
            apply_torch(s)
            ret true
        }
        if id >= 250usize && id < 254usize {
            s.timer = id - 250usize
            s.torch_sent = 99usize
            save_file(s)
            apply_torch(s)
            ui.say("flashlight timer ")
            ui.say_num(timer_seconds(s.timer))
            ui.say("\n")
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
        if id >= 270usize && id < 270usize + MAX_CUSTOM && id - 270usize < s.ccount {
            stop(s)
            s.pattern = 4usize + (id - 270usize)
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
                if s.pattern >= 4usize { ui.say_text(custom_name(s, s.pattern - 4usize)) } else { ui.say(pattern_name(s.pattern)) }
                ui.say("\n")
                apply_torch(s)
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
    if id == 242usize {
        save_pattern(a, s)
        ret true
    }
    ret false
}

// Keep the typed message as a pattern of the Pattern tab (the six newest are kept).
fn save_pattern(a: *mem.Arena, s: *State) {
    let message = ui.field_text(a, &s.message)
    if message.len == 0usize { ret }
    var j = s.ccount
    if j >= MAX_CUSTOM {
        // The oldest goes: the others move up one.
        var m = 1usize
        while m < MAX_CUSTOM {
            s.clens[m - 1usize] = s.clens[m]
            var k = 0usize
            while k < NAME_BYTES {
                s.cnames[(m - 1usize) * NAME_BYTES + k] = s.cnames[m * NAME_BYTES + k]
                k += 1usize
            }
            m += 1usize
        }
        j = MAX_CUSTOM - 1usize
    } else {
        s.ccount += 1usize
    }
    var len = message.len
    if len > NAME_BYTES { len = NAME_BYTES }
    s.clens[j] = len
    var k = 0usize
    while k < len {
        s.cnames[j * NAME_BYTES + k] = message[k]
        k += 1usize
    }
    save_file(s)
    ui.say("flashlight pattern saved ")
    ui.say_text(message)
    ui.say(" ")
    ui.say_num(s.ccount)
    ui.say("\n")
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
    apply_torch(s)
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
    s.torch_sent = 99usize
    s.unit_ms = 500usize
    load_file(&s)
    if !show(a, &kit, &s) {
        ui.say("flashlight present failed\n")
        ret ok
    }
    ui.say("flashlight shown\n")
    var running = true
    while running {
        // While a pattern runs the app wakes at its next beat; otherwise it waits for events.
        var wait = 0usize
        if s.running {
            let now = now_ms()
            wait = 1usize
            if s.next_at > now { wait = s.next_at - now }
        }
        let touch = appkit.next_touch(&kit, wait)
        if touch.kind == appkit.TOUCH_TIMEOUT {
            // The compositor takes a frame only as the answer to an event it forwarded, so the screen follows a beat
            // at the next tick (and at the fast speeds only once the run has ended: a frame takes longer than a beat).
            if advance(&s) { s.dirty = true }
        } else if touch.kind == appkit.TOUCH_END {
            running = false
        } else if touch.kind == appkit.TOUCH_TICK {
            // The half-second tick: a steady light the server turned off (the timer, the policy) is off here too.
            var changed = false
            tick_debug += 1usize
            if tick_debug % 6usize == 0usize {
                ui.say("flashlight tick ")
                ui.say_num(tick_debug)
                ui.say("\n")
            }
            if s.steady_on && s.tab == STEADY_TAB {
                let (now_level, served) = sysettings.torch(99usize)
                if served && now_level == 0usize {
                    s.steady_on = false
                    s.torch_sent = 0usize
                    changed = true
                    ui.say("flashlight off timer\n")
                }
            }
            var hold_back = s.running && s.unit_ms < 400usize
            if (changed || s.dirty) && !hold_back {
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if touch.kind == appkit.TOUCH_DOWN {
            if touch.y >= 896.0 {
                stop(&s)
                s.steady_on = false
                apply_torch(&s)
                ui.say("flashlight home\n")
                appkit.leave()
                running = false
            } else {
                let id = ui.hit_at(&s.hits, touch.x, touch.y)
                if id != ui.NONE && act(a, &s, id) {
                    if !show(a, &kit, &s) {
                        ui.say("flashlight present failed\n")
                        appkit.answer(appkit.ANSWER_NONE)
                    }
                    // A run that was just started waited for the frame: its schedule begins now, not before it.
                    if s.running && s.measured == 0usize && s.at == 0usize {
                        s.t0 = now_ms()
                        s.next_at = s.t0 + s.unit_ms
                    }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            }
        } else {
            appkit.answer(appkit.ANSWER_NONE)
        }
    }
    ret ok
}
