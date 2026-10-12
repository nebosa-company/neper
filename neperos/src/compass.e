// Compass (D2226): the app behind the Compass icon -- a dial that turns under a fixed pointer (ticks every 5 degrees,
// the degrees every 30, N E S W in amber), the heading in degrees with its direction in large type, the position,
// altitude and accuracy, and the buttons: Lock (freezes the heading), True north (adds the declination), Calibrate (the
// figure eight) and Replay (a recorded turn through the four cardinal points). Dark ground, cream cards and amber, like
// the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app.
//
// (C161, D4011) The readings come from the sensor server (sensorclient.e): the magnetometer and the accelerometer as
// two 10 Hz streams, read at each tick, the heading tilt-compensated from them with the calibration's offset taken
// off. Calibrate runs the figure eight on the live stream of the server (the field seen along every axis and corner),
// finds the hard-iron offset as the centre of what was seen and shows how round the field is after it (the spread of the
// radius over its mean: the accuracy). The position is the location service's fix (the satellite one, with the
// permission and the Location switch of Settings; off, the card says so), and the declination is the World Magnetic
// Model's at that fix. Without a sensor server everything falls back to the settings server's half-second samples.
use e.mem
use e.os
use e.math
use e.algo.magnetic as magnetic
use sensor_sim
use sensorclient
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
const CAL_MAX: usize = 300usize
const FIX_EVERY: usize = 20usize

type State = struct {
    // The hard-iron offset found by calibration (zero until then) and whether it has been found, and how round the
    // field is with it taken off (the spread of the radius, nT, and as a fraction of the mean in hundredths of a per cent).
    offset_x: f64,
    offset_y: f64,
    offset_z: f64,
    calibrated: bool,
    spread_nt: usize,
    spread_pct100: usize,
    ticks: usize,
    locked: bool,
    locked_heading: f32,
    true_north: bool,
    calibrating: bool,
    shown_heading: usize,
    // The sensor server's streams (live), the latest reading of each (nT, m/s^2), and the position fix.
    streamed: bool,
    rate: usize,
    mx: f64,
    my: f64,
    mz: f64,
    ax: f64,
    ay: f64,
    az: f64,
    have_reading: bool,
    fix_ok: bool,
    fix_denied: bool,
    lat_micro: i64,
    lon_micro: i64,
    accuracy: usize,
    fix_source: usize,
    // The figure eight's samples while it runs.
    cal_n: usize,
    cal_x: [300]f64,
    cal_y: [300]f64,
    cal_z: [300]f64,
    // The replay: running, the stream index of the last sample taken and the next checkpoint of four.
    replay: bool,
    replay_marks: usize,
    dirty: bool,
    hits: ui.Hits,
}

fn pi() -> f32 {
    ret 3.14159265
}

fn abs_f64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// The settings server's samples (or this app's own copy of the trace) at a tick, as the fallback of a machine without
// the sensor server.
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
    if s.streamed && s.have_reading {
        ret f32(magnetic.heading(s.mx - s.offset_x, s.my - s.offset_y, s.mz - s.offset_z, s.ax, s.ay, s.az))
    }
    let (mx, my, mz, ax, ay, az) = readings(s.ticks)
    ret f32(magnetic.heading(mx - s.offset_x, my - s.offset_y, mz - s.offset_z, ax, ay, az))
}

// The latitude and longitude of the position, in degrees (the fix, or the place the trace is recorded at).
fn latitude(s: *State) -> f64 {
    if s.fix_ok { ret f64(s.lat_micro) / 1000000.0f64 }
    ret sensor_sim.place_latitude()
}

fn longitude(s: *State) -> f64 {
    if s.fix_ok { ret f64(s.lon_micro) / 1000000.0f64 }
    ret sensor_sim.place_longitude()
}

fn declination_of(s: *State) -> f32 {
    let f = magnetic.field(latitude(s), longitude(s), 0.056f64, sensor_sim.model_year())
    ret f32(f.declination)
}

fn heading_of(s: *State) -> f32 {
    var h = magnetic_heading(s)
    if s.locked { h = s.locked_heading }
    if s.true_north { h += declination_of(s) }
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

// ----------------------------------------------------------------------------------------------
// The streams.

fn start_streams(s: *State, source: usize, rate: usize) -> bool {
    let (status_m, rate_m) = sensorclient.open(sensorclient.KIND_MAGNETOMETER, rate, source)
    let (status_a, rate_a) = sensorclient.open(sensorclient.KIND_ACCELEROMETER, rate, source)
    if status_m != sensorclient.STATUS_OK || status_a != sensorclient.STATUS_OK {
        s.streamed = false
        ret false
    }
    s.streamed = true
    s.rate = rate_m
    s.have_reading = false
    ret true
}

// A signed number on the serial line.
fn say_signed(v: i64) {
    if v < 0i64 {
        ui.say("-")
        ui.say_num(usize(0i64 - v))
    } else {
        ui.say_num(usize(v))
    }
}

fn rounded(v: f64) -> i64 {
    if v < 0.0f64 { ret 0i64 - i64(0.0f64 - v + 0.5f64) }
    ret i64(v + 0.5f64)
}

// The figure eight finished: the offset is the centre of the box round the samples, and the accuracy how much the radius
// still varies with it taken off.
fn finish_calibration(s: *State) {
    let n = s.cal_n
    if n < 14usize { ret }
    let (ox, oy, oz) = magnetic.calibrate_hard_iron(s.cal_x[0usize..n], s.cal_y[0usize..n], s.cal_z[0usize..n], n)
    s.offset_x = ox
    s.offset_y = oy
    s.offset_z = oz
    s.calibrated = true
    var sum = 0.0f64
    var k = 0usize
    while k < n {
        let dx = s.cal_x[k] - ox
        let dy = s.cal_y[k] - oy
        let dz = s.cal_z[k] - oz
        sum = sum + math.sqrt[f64](dx * dx + dy * dy + dz * dz)
        k += 1usize
    }
    let mean = sum / f64(n)
    var var_sum = 0.0f64
    k = 0usize
    while k < n {
        let dx = s.cal_x[k] - ox
        let dy = s.cal_y[k] - oy
        let dz = s.cal_z[k] - oz
        let r = math.sqrt[f64](dx * dx + dy * dy + dz * dz)
        var_sum = var_sum + (r - mean) * (r - mean)
        k += 1usize
    }
    let spread = math.sqrt[f64](var_sum / f64(n))
    s.spread_nt = usize(spread + 0.5f64)
    s.spread_pct100 = usize(spread / mean * 10000.0f64 + 0.5f64)
    ui.say("compass calibrated ")
    ui.say_num(usize(rounded(ox)))
    ui.say(" ")
    say_signed(rounded(oy))
    ui.say(" ")
    ui.say_num(usize(rounded(oz)))
    ui.say(" spread ")
    ui.say_num(s.spread_nt)
    ui.say(" nT of ")
    ui.say_num(usize(mean + 0.5f64))
    ui.say("\n")
}

// What the streams have: the latest reading of each into the state; during the figure eight every magnetometer sample
// is kept for the fit, and a replay reports its checkpoints (the heading at 1.5, 3.5, 5.5 and 7.5 s of the recording).
fn poll(s: *State) {
    if !s.streamed { ret }
    var mag: [32]sensorclient.Reading = zero
    var acc: [32]sensorclient.Reading = zero
    let (count, first, denied) = sensorclient.read(sensorclient.KIND_MAGNETOMETER, mag[0usize..32usize])
    let (acount, afirst, adenied) = sensorclient.read(sensorclient.KIND_ACCELEROMETER, acc[0usize..32usize])
    if denied || adenied {
        s.streamed = false
        ui.say("compass sensors denied\n")
        ret
    }
    var i = 0usize
    while i < count {
        let index = first + i
        s.mx = f64(mag[i].x)
        s.my = f64(mag[i].y)
        s.mz = f64(mag[i].z)
        if index >= afirst && index - afirst < acount {
            let j = index - afirst
            s.ax = f64(acc[j].x) / 1000.0f64
            s.ay = f64(acc[j].y) / 1000.0f64
            s.az = f64(acc[j].z) / 1000.0f64
        }
        s.have_reading = true
        if s.calibrating && s.cal_n < CAL_MAX {
            s.cal_x[s.cal_n] = s.mx
            s.cal_y[s.cal_n] = s.my
            s.cal_z[s.cal_n] = s.mz
            s.cal_n += 1usize
        }
        if s.replay && s.replay_marks < 4usize && index == 15usize + 20usize * s.replay_marks {
            let h = magnetic.heading(s.mx - s.offset_x, s.my - s.offset_y, s.mz - s.offset_z, s.ax, s.ay, s.az)
            ui.say("compass replay t")
            ui.say_num(s.replay_marks * 2usize)
            ui.say(" heading ")
            ui.say_num(usize(rounded(h)) % 360usize)
            ui.say("\n")
            s.replay_marks += 1usize
        }
        i += 1usize
    }
    if count > 0usize { s.dirty = true }
}

fn take_fix(s: *State) {
    let (status, lat, lon, accuracy, source) = sensorclient.fix(true)
    if status == sensorclient.STATUS_OK {
        let first = !s.fix_ok
        s.fix_ok = true
        s.fix_denied = false
        s.lat_micro = lat
        s.lon_micro = lon
        s.accuracy = accuracy
        s.fix_source = source
        if first {
            ui.say("compass fix ")
            if source == sensorclient.SOURCE_GPS { ui.say("gps ") } else { ui.say("network ") }
            say_signed(lat / 1000i64)
            ui.say(" ")
            say_signed(lon / 1000i64)
            ui.say(" accuracy ")
            ui.say_num(accuracy)
            ui.say("\n")
        }
    } else if status == sensorclient.STATUS_DENIED {
        if !s.fix_denied { ui.say("compass location off\n") }
        s.fix_ok = false
        s.fix_denied = true
    }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

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

fn button(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, on: bool) -> err {
    var fill = ui.soft()
    if on { fill = ui.amber() }
    ret ui.pill(a, builder, &s.hits, faces, id, x, y, w, 46.0, label, fill, 16.0)
}

// A latitude or longitude in degrees to four places with its hemisphere.
fn degrees_text(a: *mem.Arena, value: f64, plus: str, minus: str) -> str {
    var v = value
    var side = plus
    if v < 0.0f64 {
        v = 0.0f64 - v
        side = minus
    }
    let ten_thousandths = usize(v * 10000.0f64 + 0.5f64)
    let frac = ten_thousandths % 10000usize
    var pad = ""
    if frac < 1000usize { pad = "0" }
    if frac < 100usize { pad = "00" }
    if frac < 10usize { pad = "000" }
    ret ui.join(a, ui.join(a, ui.number(a, ten_thousandths / 10000usize), ".", ui.join(a, pad, ui.number(a, frac), "")), "\xC2\xB0 ", side)
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
    if s.fix_ok {
        try ui.put(a, builder, faces.jost, 17.0, ui.join(a, degrees_text(a, latitude(s), "N", "S"), ", ", degrees_text(a, longitude(s), "E", "W")), 32.0, 668.0, ui.ink())
    } else if s.fix_denied {
        try ui.put(a, builder, faces.jost, 17.0, "Location is off (Settings)", 32.0, 668.0, ui.ink())
    } else {
        try ui.put(a, builder, faces.jost, 17.0, ui.join(a, degrees_text(a, latitude(s), "N", "S"), ", ", degrees_text(a, longitude(s), "E", "W")), 32.0, 668.0, ui.ink())
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Altitude", 32.0, 700.0, ui.muted())
    try ui.put(a, builder, faces.jost, 16.0, "56 m", 32.0, 716.0, ui.ink())
    // The accuracy of the compass after calibration (how round the field is), or of the position.
    try ui.put(a, builder, faces.grotesk, 12.0, "Accuracy", 120.0, 700.0, ui.muted())
    var accuracy_text = "Not calibrated"
    if s.calibrated {
        if s.spread_pct100 < 200usize { accuracy_text = "High" } else if s.spread_pct100 < 500usize { accuracy_text = "Medium" } else { accuracy_text = "Low" }
        accuracy_text = ui.join(a, accuracy_text, ui.join(a, " (", ui.number(a, s.spread_pct100 / 100usize), ""), ui.join(a, ".", ui.number(a, s.spread_pct100 % 100usize / 10usize), " %)"))
    } else if s.fix_ok {
        accuracy_text = ui.join(a, ui.number(a, s.accuracy), " m", "")
    }
    try ui.put(a, builder, faces.jost, 16.0, accuracy_text, 120.0, 716.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Declination", 290.0, 700.0, ui.muted())
    // The declination from the World Magnetic Model at this place and date.
    var declination_value = declination_of(s)
    var declination_side = " E"
    if declination_value < 0.0 {
        declination_value = 0.0 - declination_value
        declination_side = " W"
    }
    let declination_text = ui.join(a, ui.number(a, usize(declination_value + 0.5)), "\xC2\xB0", declination_side)
    try ui.put(a, builder, faces.jost, 16.0, declination_text, 290.0, 716.0, ui.ink())
    try button(a, builder, s, faces, 100usize, 16.0, 760.0, 120.0, "Lock", s.locked)
    try button(a, builder, s, faces, 101usize, 146.0, 760.0, 120.0, "Calibrate", s.calibrating)
    try button(a, builder, s, faces, 102usize, 276.0, 760.0, 120.0, "True north", s.true_north)
    try button(a, builder, s, faces, 104usize, 16.0, 814.0, 120.0, "Replay", s.replay)
    if s.calibrating {
        try ui.card(a, builder, 16.0, 120.0, 380.0, 200.0, 20.0, ui.cream())
        try ui.centred(a, builder, faces.jost_bold, 20.0, "Calibrate the compass", 206.0, 138.0, ui.ink())
        try ui.centred(a, builder, faces.jost, 16.0, "Move your phone in a figure eight", 206.0, 176.0, ui.muted())
        try ui.centred(a, builder, faces.jost, 16.0, ui.join(a, ui.number(a, s.cal_n), " samples", ""), 206.0, 204.0, ui.muted())
        try ui.pill(a, builder, &s.hits, faces, 103usize, 126.0, 250.0, 160.0, 44.0, "Done", ui.amber(), 16.0)
    }
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
        if s.calibrating {
            s.cal_n = 0usize
            // The figure eight of the server, at 25 Hz; without a server the first figure eight of the app's own.
            let started = start_streams(s, sensorclient.SOURCE_FIGURE_EIGHT, 25usize)
        } else {
            let resumed = start_streams(s, sensorclient.SOURCE_LIVE, 10usize)
        }
        ret true
    }
    if id == 102usize {
        s.true_north = !s.true_north
        if s.true_north { ui.say("compass true on\n") } else { ui.say("compass true off\n") }
        ret true
    }
    if id == 103usize {
        s.calibrating = false
        if s.streamed && s.cal_n >= 14usize {
            finish_calibration(s)
        } else {
            // No stream (a machine without the server): the same fourteen directions computed here.
            var k = 0usize
            let f = magnetic.field(sensor_sim.place_latitude(), sensor_sim.place_longitude(), 0.056f64, sensor_sim.model_year())
            while k < 112usize {
                let (cx, cy, cz) = sensor_sim.calibration_pose(k, f.total)
                if s.cal_n < CAL_MAX {
                    s.cal_x[s.cal_n] = cx
                    s.cal_y[s.cal_n] = cy
                    s.cal_z[s.cal_n] = cz
                    s.cal_n += 1usize
                }
                k += 8usize
            }
            finish_calibration(s)
        }
        let resumed = start_streams(s, sensorclient.SOURCE_LIVE, 10usize)
        ret true
    }
    if id == 104usize {
        s.replay = true
        s.replay_marks = 0usize
        s.locked = false
        if start_streams(s, sensorclient.SOURCE_COMPASS, 10usize) {
            ui.say("compass replay started\n")
        } else {
            s.replay = false
        }
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
    // Where the readings come from: the sensor server's streams, the settings server's sensor service, or this app's
    // own copy of the trace.
    if start_streams(&s, sensorclient.SOURCE_LIVE, 10usize) {
        ui.say("compass sensors from the sensor server\n")
    } else {
        let (probe_x, probe_y, probe_z, served) = sysettings.sensor(sysettings.SENSOR_MAGNETOMETER, 0usize)
        if served { ui.say("compass sensors from the server\n") }
    }
    take_fix(&s)
    if !show(a, &kit, &s) {
        ui.say("compass present failed\n")
        ret ok
    }
    ui.say("compass shown\n")
    var running = true
    while running {
        // The figure eight and the replay read as fast as the server serves, so the app wakes every 20 ms for them.
        var wait = 0usize
        if s.calibrating || s.replay { wait = 20usize }
        let touch = appkit.next_touch(&kit, wait)
        if touch.kind == appkit.TOUCH_TIMEOUT {
            poll(&s)
            // The recording ends after eight seconds: back to the live heading.
            if s.replay && s.replay_marks >= 4usize {
                s.replay = false
                let resumed = start_streams(&s, sensorclient.SOURCE_LIVE, 10usize)
                s.dirty = true
            }
        } else if touch.kind == appkit.TOUCH_END {
            running = false
        } else if touch.kind == appkit.TOUCH_TICK {
            // The heading follows the ticks; the screen follows when the whole degrees change.
            s.ticks += 1usize
            if !s.calibrating && !s.replay { poll(&s) }
            if s.ticks % FIX_EVERY == 1usize { take_fix(&s) }
            let now = usize(heading_of(&s) + 0.5)
            if (!s.locked && now != s.shown_heading) || s.dirty {
                s.shown_heading = now
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if touch.kind == appkit.TOUCH_DOWN {
            if touch.y >= 896.0 {
                ui.say("compass home\n")
                appkit.leave()
                running = false
            } else {
                let id = ui.hit_at(&s.hits, touch.x, touch.y)
                if id != ui.NONE && act(&s, id) {
                    if !show(a, &kit, &s) {
                        ui.say("compass present failed\n")
                        appkit.answer(appkit.ANSWER_NONE)
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
