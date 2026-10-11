// Compass (D2226): the app behind the Compass icon -- a dial that turns under a fixed pointer (ticks
// every 5 degrees, the degrees every 30, N E S W in amber), the heading in degrees with its direction in
// large type, the position, altitude and accuracy, and three buttons: Lock (freezes the heading), True
// north (adds the declination) and Calibrate (a figure-eight hint). Dark ground, cream cards and amber,
// like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar
// at the bottom leaves the app.
// ponytail: there is no magnetometer, so the heading is SAMPLE data: it swings gently around 40 degrees,
// advanced by the input server's 500 ms ticks, and the position and altitude are fixed. Real sensors
// (magnetometer, GPS) and the declination from a model are queued as C131.
use e.mem
use e.os
use e.math
use e.algo.magnetic as magnetic
use sensor_sim
use sysettings
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

// (C131) The simulated sensor source: where the device is (Seattle, the position the app shows), the field there
// from the World Magnetic Model, and a hard-iron offset the phone's own magnets add to every reading (nT).

type State = struct {
    // The hard-iron offset found by calibration (zero until then) and whether it has been found.
    offset_x: f64,
    offset_y: f64,
    offset_z: f64,
    calibrated: bool,
    ticks: usize,
    locked: bool,
    locked_heading: f32,
    true_north: bool,
    calibrating: bool,
    shown_heading: usize,
    hits: ui.Hits,
}

fn pi() -> f32 {
    ret 3.14159265
}

// The sample heading, in degrees: a slow swing around 40.
fn raw_heading(ticks: usize) -> f32 {
    let t = f32(ticks) * 0.35
    ret 40.0 + 28.0 * math.sin(t) + 9.0 * math.sin(t * 2.7)
}

// The readings at the app's tick: from the settings server's sensor service when there is one (it answers in
// milli-units), else the same scripted trace computed here.
fn readings(ticks: usize) -> (f64, f64, f64, f64, f64, f64) {
    let (mx, my, mz, has_mag) = sysettings.sensor(sysettings.SENSOR_MAGNETOMETER, ticks)
    if has_mag {
        let (ax, ay, az, has_acc) = sysettings.sensor(sysettings.SENSOR_ACCELEROMETER, ticks)
        if has_acc {
            ret (f64(mx) / 1000.0f64, f64(my) / 1000.0f64, f64(mz) / 1000.0f64, f64(ax) / 1000.0f64, f64(ay) / 1000.0f64, f64(az) / 1000.0f64)
        }
    }
    let (sx, sy, sz, tx, ty, tz) = sensor_sim.sensors(ticks)
    ret (sx, sy, sz, tx, ty, tz)
}

// The heading from the sensors, with the calibration subtracted.
fn magnetic_heading(s: *State) -> f32 {
    let (mx, my, mz, ax, ay, az) = readings(s.ticks)
    ret f32(magnetic.heading(mx - s.offset_x, my - s.offset_y, mz - s.offset_z, ax, ay, az))
}

// The calibration routine: the phone is swung through a figure eight, so the field is read in every direction
// (here fourteen of them, each axis both ways and the corners) and the offset is the centre of what was read.
fn calibrate(s: *State) {
    let f = magnetic.field(sensor_sim.place_latitude(), sensor_sim.place_longitude(), 0.056f64, sensor_sim.model_year())
    let r = f.total
    var xs: [14]f64 = zero
    var ys: [14]f64 = zero
    var zs: [14]f64 = zero
    var k = 0usize
    let corner = 0.57735f64
    while k < 14usize {
        var dx = 0.0f64
        var dy = 0.0f64
        var dz = 0.0f64
        if k == 0usize { dx = 1.0f64 }
        if k == 1usize { dx = 0.0f64 - 1.0f64 }
        if k == 2usize { dy = 1.0f64 }
        if k == 3usize { dy = 0.0f64 - 1.0f64 }
        if k == 4usize { dz = 1.0f64 }
        if k == 5usize { dz = 0.0f64 - 1.0f64 }
        if k >= 6usize {
            dx = corner
            dy = corner
            dz = corner
            if (k - 6usize) % 2usize == 1usize { dx = 0.0f64 - corner }
            if ((k - 6usize) / 2usize) % 2usize == 1usize { dy = 0.0f64 - corner }
            if (k - 6usize) / 4usize == 1usize { dz = 0.0f64 - corner }
        }
        xs[k] = r * dx + sensor_sim.iron_x()
        ys[k] = r * dy + sensor_sim.iron_y()
        zs[k] = r * dz + sensor_sim.iron_z()
        k += 1usize
    }
    let (ox, oy, oz) = magnetic.calibrate_hard_iron(xs[0usize..14usize], ys[0usize..14usize], zs[0usize..14usize], 14usize)
    s.offset_x = ox
    s.offset_y = oy
    s.offset_z = oz
    s.calibrated = true
}

fn declination_of() -> f32 {
    let f = magnetic.field(sensor_sim.place_latitude(), sensor_sim.place_longitude(), 0.056f64, sensor_sim.model_year())
    ret f32(f.declination)
}

fn heading_of(s: *State) -> f32 {
    var h = magnetic_heading(s)
    if s.locked { h = s.locked_heading }
    if s.true_north { h += declination_of() }
    while h < 0.0 { h += 360.0 }
    while h >= 360.0 { h -= 360.0 }
    ret h
}

fn direction_name(degrees: usize) -> str {
    let d = (degrees + 23usize) / 45usize % 8usize
    if d == 0usize { ret "N" }
    if d == 1usize { ret "NE" }
    if d == 2usize { ret "E" }
    if d == 3usize { ret "SE" }
    if d == 4usize { ret "S" }
    if d == 5usize { ret "SW" }
    if d == 6usize { ret "W" }
    ret "NW"
}

// The screen point at `degrees` clockwise from the top, `radius` from the centre.
fn px(cx: f32, radius: f32, degrees: f32) -> f32 {
    ret cx + radius * math.sin(degrees * pi() / 180.0)
}

fn py(cy: f32, radius: f32, degrees: f32) -> f32 {
    ret cy - radius * math.cos(degrees * pi() / 180.0)
}

fn draw_dial(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, heading: f32) -> err {
    let cx: f32 = 206.0
    let cy: f32 = 330.0
    try ui.disc(a, builder, cx, cy, 168.0, paint.Color { red: 0.13, green: 0.14, blue: 0.17, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 160.0, paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 })
    // The ticks and the labels: the dial is turned by minus the heading.
    var step = 0usize
    while step < 72usize {
        let degrees = f32(step) * 5.0
        let screen = degrees - heading
        var inner: f32 = 140.0
        var width: f32 = 1.6
        var tone = ui.muted()
        if step % 6usize == 0usize {
            inner = 128.0
            width = 3.0
            tone = ui.ink()
        }
        if step == 0usize {
            tone = paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 }
        }
        try ui.stroke_line(a, builder, px(cx, 152.0, screen), py(cy, 152.0, screen), px(cx, inner, screen), py(cy, inner, screen), width, tone)
        step += 1usize
    }
    var label = 0usize
    while label < 12usize {
        let degrees = f32(label) * 30.0
        let screen = degrees - heading
        var words = ui.number(a, label * 30usize)
        var tone = ui.ink()
        var size: f32 = 15.0
        if label % 3usize == 0usize {
            tone = ui.amber_dark()
            size = 22.0
            if label == 0usize { words = "N" }
            if label == 3usize { words = "E" }
            if label == 6usize { words = "S" }
            if label == 9usize { words = "W" }
        }
        try ui.centred(a, builder, faces.jost_bold, size, words, px(cx, 104.0, screen), py(cy, 104.0, screen) - size * 0.62, tone)
        label += 1usize
    }
    // The fixed pointer at the top, and the hub.
    let pointer_x: [4]f32 = [4]f32{ cx, cx - 11.0, cx + 11.0, cx }
    let pointer_y: [4]f32 = [4]f32{ cy - 150.0, cy - 176.0, cy - 176.0, cy - 150.0 }
    try ui.polyline(a, builder, pointer_x[0usize..4usize], pointer_y[0usize..4usize], 4usize, 5.0, paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 })
    try ui.disc(a, builder, cx, cy, 6.0, ui.amber())
    ret ok
}

fn button(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, w: f32, label: str, on: bool) -> err {
    var fill = ui.soft()
    if on { fill = ui.amber() }
    ret ui.pill(a, builder, &s.hits, faces, id, x, 760.0, w, 46.0, label, fill, 16.0)
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    let heading = heading_of(s)
    let degrees = usize(heading + 0.5) % 360usize
    try ui.put(a, builder, faces.jost_bold, 30.0, "Compass", 20.0, 18.0, ui.light())
    try draw_dial(a, builder, s, faces, heading)
    try ui.centred(a, builder, faces.jost_bold, 54.0, ui.join(a, ui.number(a, degrees), "\xC2\xB0", ""), 206.0, 530.0, ui.light())
    try ui.centred(a, builder, faces.jost, 24.0, direction_name(degrees), 206.0, 596.0, ui.amber())
    try ui.card(a, builder, 16.0, 640.0, 380.0, 100.0, 18.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "Position", 32.0, 652.0, ui.muted())
    try ui.put(a, builder, faces.jost, 17.0, "47.6062\xC2\xB0 N, 122.3321\xC2\xB0 W", 32.0, 668.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Altitude", 32.0, 700.0, ui.muted())
    try ui.put(a, builder, faces.jost, 16.0, "56 m", 32.0, 716.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Accuracy", 160.0, 700.0, ui.muted())
    try ui.put(a, builder, faces.jost, 16.0, "High", 160.0, 716.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Declination", 270.0, 700.0, ui.muted())
    // The declination from the World Magnetic Model at this place and date.
    var declination_value = declination_of()
    var declination_side = " E"
    if declination_value < 0.0 {
        declination_value = 0.0 - declination_value
        declination_side = " W"
    }
    let declination_text = ui.join(a, ui.number(a, usize(declination_value + 0.5)), "\xC2\xB0", declination_side)
    try ui.put(a, builder, faces.jost, 16.0, declination_text, 270.0, 716.0, ui.ink())
    try button(a, builder, s, faces, 100usize, 16.0, 120.0, "Lock", s.locked)
    try button(a, builder, s, faces, 101usize, 146.0, 120.0, "Calibrate", s.calibrating)
    try button(a, builder, s, faces, 102usize, 276.0, 120.0, "True north", s.true_north)
    if s.calibrating {
        try ui.card(a, builder, 16.0, 120.0, 380.0, 180.0, 20.0, ui.cream())
        try ui.centred(a, builder, faces.jost_bold, 20.0, "Calibrate the compass", 206.0, 138.0, ui.ink())
        try ui.centred(a, builder, faces.jost, 16.0, "Move your phone in a figure eight", 206.0, 176.0, ui.muted())
        try ui.centred(a, builder, faces.jost, 16.0, "until the heading settles.", 206.0, 200.0, ui.muted())
        try ui.pill(a, builder, &s.hits, faces, 103usize, 126.0, 240.0, 160.0, 44.0, "Done", ui.amber(), 16.0)
    }
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
    if id == 100usize {
        s.locked = !s.locked
        if s.locked { s.locked_heading = magnetic_heading(s) }
        if s.locked { ui.say("compass lock on\n") } else { ui.say("compass lock off\n") }
        ret true
    }
    if id == 101usize {
        s.calibrating = !s.calibrating
        ui.say("compass calibrate\n")
        ret true
    }
    if id == 102usize {
        s.true_north = !s.true_north
        if s.true_north { ui.say("compass true on\n") } else { ui.say("compass true off\n") }
        ret true
    }
    if id == 103usize {
        s.calibrating = false
        calibrate(s)
        ui.say("compass calibrated ")
        ui.say_num(usize(s.offset_x))
        ui.say("\n")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "compass")
    if kit_error != ok {
        ui.say("compass open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("compass fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.shown_heading = 999usize
    // Where the readings come from: the settings server's sensor service, or this app's own copy of the trace.
    let (probe_x, probe_y, probe_z, served) = sysettings.sensor(sysettings.SENSOR_MAGNETOMETER, 0usize)
    if served { ui.say("compass sensors from the server\n") }
    if !show(a, &kit, &s) {
        ui.say("compass present failed\n")
        ret ok
    }
    ui.say("compass shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The heading swings with the ticks; the screen follows when the whole degrees change.
            s.ticks += 1usize
            let now = usize(heading_of(&s) + 0.5)
            if !s.locked && now != s.shown_heading {
                s.shown_heading = now
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("compass home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    ui.say("compass present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
