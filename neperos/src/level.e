// Level (D2227): the app behind the Level icon, a bubble level and a protractor -- Level mode: a circular
// vial with a bubble that moves with the tilt, a vial for each axis, the tilt of both in degrees, green when
// it is level within a degree; Angle mode: a protractor dial with a needle at the angle of the phone, the
// angle in large type with the slope in per cent. Hold freezes the reading, Calibrate takes the present
// tilt as zero, and a switch says whether the phone lies flat or stands on its edge. Dark ground, cream
// cards and amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]).
// A tap on the bar at the bottom leaves the app.
// ponytail: there is no accelerometer, so the tilt is SAMPLE data: two slow swings of a few degrees
// advanced by the input server's 500 ms ticks. The accelerometer and the gyroscope, and filtering the
// reading, are queued as C132 (with the sensor server of C131).
use e.mem
use e.os
use e.math
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
const LEVEL_MODE: usize = 0usize
const ANGLE_MODE: usize = 1usize

type State = struct {
    ticks: usize,
    mode: usize,
    held: bool,
    held_x: f32,
    held_y: f32,
    zero_x: f32,
    zero_y: f32,
    on_edge: bool,
    shown: usize,
    hits: ui.Hits,
}

fn pi() -> f32 {
    ret 3.14159265
}

// The sample tilt (degrees) of the phone along x and y.
fn raw_x(ticks: usize) -> f32 {
    ret 7.0 * math.sin(f32(ticks) * 0.31) + 1.2 * math.sin(f32(ticks) * 1.7)
}

fn raw_y(ticks: usize) -> f32 {
    ret 4.5 * math.sin(f32(ticks) * 0.23 + 1.0)
}

fn tilt_x(s: *State) -> f32 {
    if s.held { ret s.held_x - s.zero_x }
    ret raw_x(s.ticks) - s.zero_x
}

fn tilt_y(s: *State) -> f32 {
    if s.held { ret s.held_y - s.zero_y }
    ret raw_y(s.ticks) - s.zero_y
}

fn abs(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 - v }
    ret v
}

fn tenths_text(a: *mem.Arena, v: f32) -> str {
    var sign = ""
    var m = v
    if v < 0.0 {
        sign = "-"
        m = 0.0 - v
    }
    let t = usize(m * 10.0 + 0.5)
    ret ui.join(a, ui.join(a, sign, ui.number(a, t / 10usize), "."), ui.number(a, t % 10usize), "\xC2\xB0")
}

fn level_color(v: f32) -> paint.Color {
    if abs(v) < 1.0 { ret paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 } }
    ret ui.amber()
}

fn draw_level(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let tx = tilt_x(s)
    let ty = tilt_y(s)
    let cx: f32 = 206.0
    let cy: f32 = 300.0
    // The circular vial: a bubble 14 dp for each degree, kept inside the ring.
    try ui.disc(a, builder, cx, cy, 130.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 124.0, paint.Color { red: 0.12, green: 0.14, blue: 0.13, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 60.0, paint.Color { red: 0.15, green: 0.17, blue: 0.16, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 52.0, paint.Color { red: 0.12, green: 0.14, blue: 0.13, alpha: 1.0 })
    try ui.stroke_line(a, builder, cx - 124.0, cy, cx + 124.0, cy, 1.5, paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 })
    try ui.stroke_line(a, builder, cx, cy - 124.0, cx, cy + 124.0, 1.5, paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 })
    var bx = tx * 14.0
    var by = ty * 14.0
    let reach = bx * bx + by * by
    if reach > 85.0 * 85.0 {
        let scale = 85.0 * math.rsqrt(reach)
        bx = bx * scale
        by = by * scale
    }
    var tone = level_color(tx)
    if abs(ty) >= 1.0 { tone = ui.amber() }
    try ui.disc(a, builder, cx + bx, cy + by, 34.0, tone)
    try ui.disc(a, builder, cx + bx - 10.0, cy + by - 10.0, 9.0, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35 })
    // A horizontal vial below, and a vertical one at the right.
    try ui.card(a, builder, 56.0, 470.0, 300.0, 44.0, 22.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
    try ui.stroke_line(a, builder, 206.0, 474.0, 206.0, 510.0, 1.5, paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 })
    var hx = tx * 12.0
    if hx > 120.0 { hx = 120.0 }
    if hx < -120.0 { hx = -120.0 }
    try ui.disc(a, builder, 206.0 + hx, 492.0, 16.0, level_color(tx))
    try ui.put(a, builder, faces.grotesk, 12.0, "X", 36.0, 484.0, ui.light_muted())
    try ui.card(a, builder, 360.0, 150.0, 30.0, 300.0, 15.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
    var vy = ty * 12.0
    if vy > 125.0 { vy = 125.0 }
    if vy < -125.0 { vy = -125.0 }
    try ui.disc(a, builder, 375.0, 300.0 + vy, 12.0, level_color(ty))
    try ui.put(a, builder, faces.grotesk, 12.0, "Y", 370.0, 126.0, ui.light_muted())
    // The readings.
    try ui.card(a, builder, 16.0, 560.0, 380.0, 120.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "X tilt", 40.0, 574.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 36.0, tenths_text(a, tx), 40.0, 596.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Y tilt", 230.0, 574.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 36.0, tenths_text(a, ty), 230.0, 596.0, ui.ink())
    var verdict = "Not level"
    if abs(tx) < 1.0 && abs(ty) < 1.0 { verdict = "Level" }
    try ui.centred(a, builder, faces.jost, 18.0, verdict, 206.0, 650.0, ui.amber_dark())
    ret ok
}

fn draw_angle(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var angle = tilt_x(s) * 3.0
    if angle > 90.0 { angle = 90.0 }
    if angle < -90.0 { angle = -90.0 }
    let cx: f32 = 206.0
    let cy: f32 = 420.0
    // The protractor: an upper half-disc, ticks every 5 degrees from -90 to 90 around the vertical.
    try ui.disc(a, builder, cx, cy, 170.0, paint.Color { red: 0.13, green: 0.14, blue: 0.17, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 162.0, paint.Color { red: 0.20, green: 0.35, blue: 0.62, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 112.0, paint.Color { red: 0.62, green: 0.20, blue: 0.22, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 78.0, paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 })
    // Only the upper half is a protractor.
    try ui.card(a, builder, cx - 176.0, cy, 352.0, 176.0, 0.0, paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 })
    var step = 0usize
    while step <= 36usize {
        let degrees: f32 = f32(step) * 5.0 - 90.0
        var inner: f32 = 146.0
        var width: f32 = 1.4
        if step % 6usize == 0usize {
            inner = 134.0
            width = 2.8
        }
        let sx0 = cx + 160.0 * math.sin(degrees * pi() / 180.0)
        let sy0 = cy - 160.0 * math.cos(degrees * pi() / 180.0)
        let sx1 = cx + inner * math.sin(degrees * pi() / 180.0)
        let sy1 = cy - inner * math.cos(degrees * pi() / 180.0)
        try ui.stroke_line(a, builder, sx0, sy0, sx1, sy1, width, ui.cream())
        step += 1usize
    }
    // The needle.
    let nx = cx + 150.0 * math.sin(angle * pi() / 180.0)
    let ny = cy - 150.0 * math.cos(angle * pi() / 180.0)
    try ui.stroke_line(a, builder, cx, cy, nx, ny, 4.0, ui.amber())
    try ui.disc(a, builder, cx, cy, 8.0, ui.amber())
    try ui.centred(a, builder, faces.jost_bold, 52.0, tenths_text(a, abs(angle)), cx, cy - 90.0, ui.light())
    // The slope in per cent.
    var slope = math.sin(abs(angle) * pi() / 180.0) / math.cos(abs(angle) * pi() / 180.0 + 0.0001) * 100.0
    if abs(angle) > 84.0 { slope = 999.0 }
    try ui.centred(a, builder, faces.jost, 20.0, ui.join(a, ui.number(a, usize(slope + 0.5)), " % slope", ""), cx, 520.0, ui.amber())
    try ui.card(a, builder, 16.0, 580.0, 380.0, 96.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "Surface", 40.0, 594.0, ui.muted())
    var surface = "Flat on a table"
    if s.on_edge { surface = "Standing on its edge" }
    try ui.put(a, builder, faces.jost, 18.0, surface, 40.0, 614.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Reading", 40.0, 646.0, ui.muted())
    var state = "Live"
    if s.held { state = "Held" }
    try ui.put(a, builder, faces.jost, 16.0, state, 110.0, 642.0, ui.ink())
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    var mode = 0usize
    while mode < 2usize {
        var label = "Level"
        if mode == 1usize { label = "Angle" }
        var fill = ui.soft()
        if mode == s.mode { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + mode, 16.0 + f32(mode) * 130.0, 70.0, 120.0, 40.0, label, fill, 16.0)
        mode += 1usize
    }
    // The picture sits under the tabs.
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Transform: geometry.transform_translate(0.0, 0.0) })
    if s.mode == LEVEL_MODE { try draw_level(a, builder, s, faces) } else { try draw_angle(a, builder, s, faces) }
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    var hold_fill = ui.soft()
    if s.held { hold_fill = ui.amber() }
    try ui.pill(a, builder, &s.hits, faces, 110usize, 16.0, 780.0, 120.0, 46.0, "Hold", hold_fill, 16.0)
    try ui.pill(a, builder, &s.hits, faces, 111usize, 146.0, 780.0, 120.0, 46.0, "Calibrate", ui.soft(), 16.0)
    var edge_fill = ui.soft()
    if s.on_edge { edge_fill = ui.amber() }
    try ui.pill(a, builder, &s.hits, faces, 112usize, 276.0, 780.0, 120.0, 46.0, "On edge", edge_fill, 16.0)
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

fn act(s: *State, id: usize) -> bool {
    if id == 100usize || id == 101usize {
        s.mode = id - 100usize
        if s.mode == LEVEL_MODE { ui.say("level mode Level\n") } else { ui.say("level mode Angle\n") }
        ret true
    }
    if id == 110usize {
        s.held = !s.held
        if s.held {
            s.held_x = raw_x(s.ticks)
            s.held_y = raw_y(s.ticks)
            ui.say("level hold on\n")
        } else {
            ui.say("level hold off\n")
        }
        ret true
    }
    if id == 111usize {
        s.zero_x = raw_x(s.ticks)
        s.zero_y = raw_y(s.ticks)
        if s.held {
            s.zero_x = s.held_x
            s.zero_y = s.held_y
        }
        ui.say("level calibrate\n")
        ret true
    }
    if id == 112usize {
        s.on_edge = !s.on_edge
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "level")
    if kit_error != ok {
        ui.say("level open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("level fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.shown = 9999usize
    if !show(a, &kit, &s) {
        ui.say("level present failed\n")
        ret ok
    }
    ui.say("level shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The tilt follows the ticks; the screen is redrawn while it is live.
            s.ticks += 1usize
            if !s.held {
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("level home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    ui.say("level present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
