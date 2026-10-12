// Level (D2227): the app behind the Level icon, a bubble level and a protractor -- Level mode: a circular
// vial with a bubble that moves with the tilt, a vial for each axis, the tilt of both in degrees, the slope in
// per cent and as a ratio, green when it is level within a degree; Angle mode: a protractor dial with a needle at
// the angle of the phone; Test mode: the self-test of the sensor. Hold freezes the reading, Calibrate takes the
// present tilt as zero, and the phone's real orientation (flat on a table, standing on its edge) switches
// between Level and Angle. Dark ground, cream cards and amber, like the other apps (appkit.e, taps from the
// compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
//
// (C162, D4005) The readings come from the sensor server (sensorclient.e) as two 50 Hz streams, the
// accelerometer's and the gyroscope's, read every 20 ms (the kernel's receive deadline, appkit.next_touch) and
// run through a complementary filter and a Kalman filter side by side (e.control; Filter picks which one the
// screen shows). A phone that lies still on a table (Self-test) gives its sensor's bias and noise; Replay plays a
// recorded session of lifting and standing the phone, whose angles are the ground truth the serial lines carry.
// When the machine has no sensor server the readings are the settings server's half-second samples, as before.
use e.mem
use e.os
use e.math
use e.control as control
use sysettings
use sensor_sim
use sensorclient
use vaultfs
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
const TEST_MODE: usize = 2usize
// The stream rate asked of the sensor server, and the complementary filter's weight of the gyroscope.
const STREAM_HZ: usize = 50usize
const SAMPLES: usize = 100usize
const VIBRATE_SETTING: usize = 13usize

type State = struct {
    // The tilt in degrees from the complementary filter (cx, cy) and from the Kalman filter (kx, ky); `filtering`
    // is whether they have a first reading.
    cx: f64,
    cy: f64,
    kx: control.Kalman,
    ky: control.Kalman,
    filtering: bool,
    kalman: bool,
    // The sensor server's streams: whether they are open, the rate granted and the index of the last sample taken.
    streamed: bool,
    rate: usize,
    last_index: usize,
    have_index: bool,
    // The gyroscope's last rates (degrees per second) and the accelerometer's last reading (m/s^2).
    gp: f64,
    gq: f64,
    ax: f64,
    ay: f64,
    az: f64,
    // Replay: whether the recorded session plays, and the next of its four checkpoints to report.
    replay: bool,
    marks: usize,
    // The self-test: collecting, how many samples, and the readings (mm/s^2) of each axis.
    testing: bool,
    test_n: usize,
    test_done: bool,
    tx: [100]f64,
    ty: [100]f64,
    tz: [100]f64,
    sum_x: i64,
    sum_y: i64,
    sum_z: i64,
    noise_x: i64,
    noise_y: i64,
    noise_z: i64,
    // Whether the phone was level before (so the beep comes when it becomes level, not at the start).
    armed: bool,
    was_level: bool,
    // The half-second ticks, when there is no stream.
    ticks: usize,
    mode: usize,
    held: bool,
    held_x: f32,
    held_y: f32,
    zero_x: f32,
    zero_y: f32,
    on_edge: bool,
    shown: usize,
    dirty: bool,
    since_draw: usize,
    hits: ui.Hits,
}

fn pi() -> f32 {
    ret 3.14159265
}

// The accelerometer's and the gyroscope's readings at a tick: from the settings server's sensor service when
// there is one (milli-units), else the same scripted trace computed here.
fn accel_at(ticks: usize) -> (f64, f64, f64) {
    let (x, y, z, served) = sysettings.sensor(sysettings.SENSOR_ACCELEROMETER, ticks)
    if served { ret (f64(x) / 1000.0f64, f64(y) / 1000.0f64, f64(z) / 1000.0f64) }
    let (mx, my, mz, ax, ay, az) = sensor_sim.sensors(ticks)
    ret (ax, ay, az)
}

fn gyro_at(ticks: usize) -> (f64, f64, f64) {
    let (x, y, z, served) = sysettings.sensor(sysettings.SENSOR_GYROSCOPE, ticks)
    if served { ret (f64(x) / 1000.0f64, f64(y) / 1000.0f64, f64(z) / 1000.0f64) }
    let (gx, gy, gz) = sensor_sim.gyro(ticks)
    ret (gx, gy, gz)
}

fn to_degrees() -> f64 {
    ret 180.0f64 / 3.141592653589793f64
}

// One sample into both filters: the accelerometer (m/s^2) gives the angles at rest, the gyroscope's rates
// (degrees per second) carry them across `dt` seconds.
fn feed(s: *State, ax: f64, ay: f64, az: f64, p: f64, q: f64, dt: f64) {
    let roll = control.roll_from_accel(ay, az)
    let pitch = control.pitch_from_accel(ax, ay, az)
    s.ax = ax
    s.ay = ay
    s.az = az
    if !s.filtering {
        s.cx = roll
        s.cy = pitch
        control.kalman_start(&s.kx, roll)
        control.kalman_start(&s.ky, pitch)
        s.filtering = true
        ret
    }
    s.cx = control.complementary(s.cx, p, roll, dt, 0.98f64)
    s.cy = control.complementary(s.cy, q, pitch, dt, 0.98f64)
    let ka = control.kalman_step(&s.kx, roll, p, dt)
    let kb = control.kalman_step(&s.ky, pitch, q, dt)
}

// The tilt of the phone (degrees) along x (roll) and y (pitch): from the filter on show.
fn raw_x(s: *State) -> f32 {
    if s.kalman { ret f32(s.kx.angle) }
    ret f32(s.cx)
}

fn raw_y(s: *State) -> f32 {
    if s.kalman { ret f32(s.ky.angle) }
    ret f32(s.cy)
}

fn tilt_x(s: *State) -> f32 {
    if s.held { ret s.held_x - s.zero_x }
    ret raw_x(s) - s.zero_x
}

fn tilt_y(s: *State) -> f32 {
    if s.held { ret s.held_y - s.zero_y }
    ret raw_y(s) - s.zero_y
}

// The calibration (the angles taken as zero) is kept in /level: eight bytes, each angle in thousandths of a
// degree plus 2^31, little end.
fn save_zero(s: *State) {
    var buf: [8]u8 = zero
    let bx = u32(i64(s.zero_x * 1000.0) + 2147483648i64)
    let by = u32(i64(s.zero_y * 1000.0) + 2147483648i64)
    var i = 0usize
    while i < 4usize {
        buf[i] = u8((bx >> u32(8usize * i)) & 255u32)
        buf[4usize + i] = u8((by >> u32(8usize * i)) & 255u32)
        i += 1usize
    }
    let kept = vaultfs.write("/level", mem.address_of(&buf[0usize]), 8usize)
}

fn load_zero(s: *State) -> bool {
    var buf: [8]u8 = zero
    let (n, found) = vaultfs.read("/level", mem.address_of(&buf[0usize]), 8usize)
    if !found || n < 8usize { ret false }
    var bx = 0u32
    var by = 0u32
    var i = 0usize
    while i < 4usize {
        bx = bx | (u32(buf[i]) << u32(8usize * i))
        by = by | (u32(buf[4usize + i]) << u32(8usize * i))
        i += 1usize
    }
    s.zero_x = f32(i64(bx) - 2147483648i64) / 1000.0
    s.zero_y = f32(i64(by) - 2147483648i64) / 1000.0
    ret true
}

fn abs(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 - v }
    ret v
}

fn abs_f64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// A signed number of tenths on the serial line (a negative one with its sign).
fn say_signed(v: i64) {
    if v < 0i64 {
        ui.say("-")
        ui.say_num(usize(0i64 - v))
    } else {
        ui.say_num(usize(v))
    }
}

// An angle in degrees as tenths, rounded half away from zero.
fn tenths_of(v: f64) -> i64 {
    if v < 0.0f64 { ret 0i64 - i64(0.0f64 - v * 10.0f64 + 0.5f64) }
    ret i64(v * 10.0f64 + 0.5f64)
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

// The combined slope of the tilt: the angle of the steepest line, as per cent (rise over run) and as the run per
// unit of rise.
fn slope_percent(tx: f32, ty: f32) -> f32 {
    let rx = tx * pi() / 180.0
    let ry = ty * pi() / 180.0
    let tan_x = math.sin(rx) / math.cos(rx + 0.0001)
    let tan_y = math.sin(ry) / math.cos(ry + 0.0001)
    let sum = tan_x * tan_x + tan_y * tan_y
    if sum <= 0.0 { ret 0.0 }
    ret sum * math.rsqrt(sum) * 100.0
}

fn slope_text(a: *mem.Arena, tx: f32, ty: f32) -> str {
    let percent = slope_percent(tx, ty)
    if percent > 999.0 { ret "Steeper than 999 %" }
    var text_ratio = "level"
    if percent >= 1.0 {
        let run = 1000.0 / percent
        let t = usize(run + 0.5)
        text_ratio = ui.join(a, "1 : ", ui.number(a, t / 10usize), ui.join(a, ".", ui.number(a, t % 10usize), ""))
    }
    ret ui.join(a, ui.number(a, usize(percent + 0.5)), " % slope, ", text_ratio)
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
    try ui.card(a, builder, 56.0, 450.0, 300.0, 44.0, 22.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
    try ui.stroke_line(a, builder, 206.0, 454.0, 206.0, 490.0, 1.5, paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 })
    var hx = tx * 12.0
    if hx > 120.0 { hx = 120.0 }
    if hx < -120.0 { hx = -120.0 }
    try ui.disc(a, builder, 206.0 + hx, 472.0, 16.0, level_color(tx))
    try ui.put(a, builder, faces.grotesk, 12.0, "X", 36.0, 464.0, ui.light_muted())
    try ui.card(a, builder, 360.0, 150.0, 30.0, 300.0, 15.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
    var vy = ty * 12.0
    if vy > 125.0 { vy = 125.0 }
    if vy < -125.0 { vy = -125.0 }
    try ui.disc(a, builder, 375.0, 300.0 + vy, 12.0, level_color(ty))
    try ui.put(a, builder, faces.grotesk, 12.0, "Y", 370.0, 126.0, ui.light_muted())
    // The readings: degrees of each axis, then the slope in per cent and as a ratio, then the verdict.
    try ui.card(a, builder, 16.0, 510.0, 380.0, 190.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "X tilt", 40.0, 524.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 36.0, tenths_text(a, tx), 40.0, 544.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Y tilt", 230.0, 524.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 36.0, tenths_text(a, ty), 230.0, 544.0, ui.ink())
    try ui.centred(a, builder, faces.jost, 16.0, slope_text(a, tx, ty), 206.0, 606.0, ui.ink())
    var verdict = "Not level"
    if abs(tx) < 1.0 && abs(ty) < 1.0 { verdict = "Level" }
    try ui.centred(a, builder, faces.jost, 18.0, verdict, 206.0, 640.0, ui.amber_dark())
    var source_line = "Complementary filter, 50 Hz"
    if s.kalman { source_line = "Kalman filter, 50 Hz" }
    if !s.streamed { source_line = "Half-second samples" }
    if s.replay { source_line = "Replaying a recorded session" }
    try ui.centred(a, builder, faces.grotesk, 12.0, source_line, 206.0, 674.0, ui.muted())
    ret ok
}

fn draw_angle(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    // The angle of the steepest line: the larger of the two tilts on a phone that stands on its edge.
    var angle = tilt_x(s)
    if s.on_edge { angle = tilt_y(s) }
    if abs(tilt_y(s)) > abs(angle) && !s.on_edge { angle = tilt_y(s) }
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
    // The slope in per cent, and as a ratio.
    try ui.centred(a, builder, faces.jost, 20.0, slope_text(a, angle, 0.0), cx, 520.0, ui.amber())
    try ui.card(a, builder, 16.0, 580.0, 380.0, 120.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, "Surface", 40.0, 594.0, ui.muted())
    var surface = "Flat on a table"
    if s.on_edge { surface = "Standing on its edge" }
    try ui.put(a, builder, faces.jost, 18.0, surface, 40.0, 614.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 12.0, "Reading", 40.0, 646.0, ui.muted())
    var state = "Live"
    if s.held { state = "Held" }
    try ui.put(a, builder, faces.jost, 16.0, state, 110.0, 642.0, ui.ink())
    var filter = "Complementary"
    if s.kalman { filter = "Kalman" }
    try ui.put(a, builder, faces.grotesk, 12.0, "Filter", 40.0, 672.0, ui.muted())
    try ui.put(a, builder, faces.jost, 16.0, filter, 110.0, 668.0, ui.ink())
    ret ok
}

// The self-test's page: the bias and the noise of each axis of the accelerometer, in mm/s^2, from a flat, still phone.
fn draw_test(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 130.0, 380.0, 400.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost_bold, 22.0, "Self-test", 40.0, 150.0, ui.ink())
    let (box, box_error) = ui.wrapped(a, builder, faces.grotesk, 14.0, "Lay the phone flat and still, then run the test: it takes two seconds and reports each axis's bias and noise.", 40.0, 190.0, 330.0, 3u32, ui.muted())
    if box_error != ok { ret box_error }
    if s.testing {
        try ui.put(a, builder, faces.jost, 18.0, "Measuring...", 40.0, 280.0, ui.amber_dark())
    } else if s.test_done {
        try ui.put(a, builder, faces.grotesk, 12.0, "Bias (mm/s2)", 40.0, 280.0, ui.muted())
        try ui.put(a, builder, faces.jost, 18.0, ui.join(a, ui.join(a, signed_text(a, s.sum_x / 100i64), "   ", signed_text(a, s.sum_y / 100i64)), "   ", signed_text(a, s.sum_z / 100i64 - 9810i64)), 40.0, 300.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, "Noise (mm/s2)", 40.0, 350.0, ui.muted())
        try ui.put(a, builder, faces.jost, 18.0, ui.join(a, ui.join(a, ui.number(a, usize(s.noise_x / 10i64)), "   ", ui.number(a, usize(s.noise_y / 10i64))), "   ", ui.number(a, usize(s.noise_z / 10i64))), 40.0, 370.0, ui.ink())
    } else {
        try ui.put(a, builder, faces.jost, 18.0, "Not run yet", 40.0, 280.0, ui.ink())
    }
    ret ok
}

fn signed_text(a: *mem.Arena, v: i64) -> str {
    if v < 0i64 { ret ui.join(a, "-", ui.number(a, usize(0i64 - v)), "") }
    ret ui.number(a, usize(v))
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    var mode = 0usize
    while mode < 3usize {
        var label = "Level"
        if mode == 1usize { label = "Angle" }
        if mode == 2usize { label = "Test" }
        var fill = ui.soft()
        if mode == s.mode { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + mode, 16.0 + f32(mode) * 130.0, 70.0, 120.0, 40.0, label, fill, 16.0)
        mode += 1usize
    }
    // The picture sits under the tabs.
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Transform: geometry.transform_translate(0.0, 0.0) })
    if s.mode == LEVEL_MODE {
        try draw_level(a, builder, s, faces)
    } else if s.mode == ANGLE_MODE {
        try draw_angle(a, builder, s, faces)
    } else {
        try draw_test(a, builder, s, faces)
    }
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    var replay_fill = ui.soft()
    if s.replay { replay_fill = ui.amber() }
    try ui.pill(a, builder, &s.hits, faces, 113usize, 16.0, 722.0, 120.0, 46.0, "Replay", replay_fill, 16.0)
    var filter_fill = ui.soft()
    if s.kalman { filter_fill = ui.amber() }
    try ui.pill(a, builder, &s.hits, faces, 114usize, 146.0, 722.0, 120.0, 46.0, "Filter", filter_fill, 16.0)
    try ui.pill(a, builder, &s.hits, faces, 115usize, 276.0, 722.0, 120.0, 46.0, "Self-test", ui.soft(), 16.0)
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
    s.dirty = false
    s.since_draw = 0usize
    ret appkit.present(kit, &builder)
}

// Open the accelerometer's and the gyroscope's streams from `source`; false when there is no server or no permission.
fn start_streams(s: *State, source: usize) -> bool {
    let (status_a, rate_a) = sensorclient.open(sensorclient.KIND_ACCELEROMETER, STREAM_HZ, source)
    let (status_g, rate_g) = sensorclient.open(sensorclient.KIND_GYROSCOPE, STREAM_HZ, source)
    s.have_index = false
    if status_a != sensorclient.STATUS_OK || status_g != sensorclient.STATUS_OK {
        s.streamed = false
        ret false
    }
    s.streamed = true
    s.rate = rate_a
    ui.say("level stream accelerometer ")
    ui.say_num(rate_a)
    ui.say(" gyroscope ")
    ui.say_num(rate_g)
    ui.say(" hz\n")
    ret true
}

// The replay's checkpoints, in milliseconds of the recording: flat and still, the roll held, the pitch held, the phone on
// its edge.
fn mark_ms(k: usize) -> usize {
    if k == 0usize { ret 3000usize }
    if k == 1usize { ret 11000usize }
    if k == 2usize { ret 21000usize }
    ret 29000usize
}

fn report_mark(s: *State, k: usize) {
    ui.say("level replay t")
    ui.say_num(mark_ms(k) / 1000usize)
    ui.say(" x")
    say_signed(tenths_of(s.cx))
    ui.say(" y")
    say_signed(tenths_of(s.cy))
    ui.say(" kx")
    say_signed(tenths_of(s.kx.angle))
    ui.say(" ky")
    say_signed(tenths_of(s.ky.angle))
    ui.say("\n")
}

// The orientation from gravity and the filtered angles: on its edge past 60 degrees either way, flat again below 45.
fn judge_orientation(s: *State) {
    let steep = abs_f64(s.cy) > 60.0f64 || abs_f64(s.cx) > 60.0f64
    let flat = abs_f64(s.cy) < 45.0f64 && abs_f64(s.cx) < 45.0f64
    if steep && !s.on_edge {
        s.on_edge = true
        s.mode = ANGLE_MODE
        s.dirty = true
        ui.say("level orientation edge\n")
    } else if flat && s.on_edge {
        s.on_edge = false
        s.mode = LEVEL_MODE
        s.dirty = true
        ui.say("level orientation flat\n")
    }
}

// The feedback when the phone becomes level: a beep and, when Vibrate is on in Settings, a vibration.
fn judge_feedback(s: *State) {
    if s.mode != LEVEL_MODE || s.held {
        s.was_level = false
        ret
    }
    let now_level = abs(tilt_x(s)) < 0.5 && abs(tilt_y(s)) < 0.5
    if now_level && !s.was_level && s.armed {
        ui.say("level beep\n")
        let (vibrate, served) = sysettings.get(VIBRATE_SETTING)
        if served && vibrate != 0usize { ui.say("level vibrate\n") }
    }
    if !now_level { s.armed = true }
    s.was_level = now_level
}

// The self-test's samples: 100 of the flat phone's accelerometer; then its bias (the mean less nominal gravity) and
// noise (the sample standard deviation) of each axis.
fn finish_test(s: *State) {
    let (mean_x, noise_x) = control.noise_bias(s.tx[0usize..SAMPLES])
    let (mean_y, noise_y) = control.noise_bias(s.ty[0usize..SAMPLES])
    let (mean_z, noise_z) = control.noise_bias(s.tz[0usize..SAMPLES])
    var sx = 0.0f64
    var sy = 0.0f64
    var sz = 0.0f64
    var i = 0usize
    while i < SAMPLES {
        sx = sx + s.tx[i]
        sy = sy + s.ty[i]
        sz = sz + s.tz[i]
        i += 1usize
    }
    s.sum_x = i64(sx)
    s.sum_y = i64(sy)
    s.sum_z = i64(sz)
    s.noise_x = i64(noise_x * 10.0f64)
    s.noise_y = i64(noise_y * 10.0f64)
    s.noise_z = i64(noise_z * 10.0f64)
    s.testing = false
    s.test_done = true
    s.dirty = true
    ui.say("level selftest sum ")
    say_signed(s.sum_x)
    ui.say(" ")
    say_signed(s.sum_y)
    ui.say(" ")
    say_signed(s.sum_z)
    ui.say(" noise ")
    ui.say_num(usize(s.noise_x))
    ui.say(" ")
    ui.say_num(usize(s.noise_y))
    ui.say(" ")
    ui.say_num(usize(s.noise_z))
    ui.say("\n")
    // Back to the live sensor.
    s.replay = false
    s.filtering = false
    let restarted = start_streams(s, sensorclient.SOURCE_LIVE)
}

// Take every sample the server has for the two streams: each through the filters, the replay's checkpoints
// reported as the recording passes them, the orientation and the feedback judged once per batch.
fn poll_once(s: *State) -> usize {
    if !s.streamed { ret 0usize }
    var acc: [32]sensorclient.Reading = zero
    var gyr: [32]sensorclient.Reading = zero
    let (count, first, denied) = sensorclient.read(sensorclient.KIND_ACCELEROMETER, acc[0usize..32usize])
    let (gcount, gfirst, gdenied) = sensorclient.read(sensorclient.KIND_GYROSCOPE, gyr[0usize..32usize])
    if denied || gdenied {
        s.streamed = false
        ui.say("level stream denied\n")
        ret 0usize
    }
    if count == 0usize { ret 0usize }
    let rate = f64(s.rate)
    var i = 0usize
    while i < count {
        let index = first + i
        // The gap since the last sample taken: a sample the server dropped is time the gyroscope still carried.
        var gap = 1usize
        if s.have_index && index > s.last_index { gap = index - s.last_index }
        s.last_index = index
        s.have_index = true
        // The gyroscope's sample of the same index, when the other stream has it; else its last rates carry on.
        if index >= gfirst && index - gfirst < gcount {
            let j = index - gfirst
            s.gp = f64(gyr[j].x) / 1000.0f64 * to_degrees()
            s.gq = f64(gyr[j].y) / 1000.0f64 * to_degrees()
        }
        let ax = f64(acc[i].x) / 1000.0f64
        let ay = f64(acc[i].y) / 1000.0f64
        let az = f64(acc[i].z) / 1000.0f64
        if s.testing {
            if s.test_n < SAMPLES {
                s.tx[s.test_n] = f64(acc[i].x)
                s.ty[s.test_n] = f64(acc[i].y)
                s.tz[s.test_n] = f64(acc[i].z)
                s.test_n += 1usize
            }
            if s.test_n == SAMPLES {
                finish_test(s)
                ret 0usize
            }
        } else {
            feed(s, ax, ay, az, s.gp, s.gq, f64(gap) / rate)
            if s.replay {
                while s.marks < 4usize && index * 1000usize / s.rate >= mark_ms(s.marks) {
                    report_mark(s, s.marks)
                    s.marks += 1usize
                }
            }
        }
        i += 1usize
    }
    if s.testing { ret count }
    judge_orientation(s)
    judge_feedback(s)
    s.dirty = true
    ret count
}

// Everything that has arrived: batches of 32 until the server has no more (at most a second's worth of 50 Hz at a time
// of 60 batches, so a long frame does not keep the app from its events).
fn poll(s: *State) {
    var rounds = 0usize
    var more = true
    while more && rounds < 60usize {
        let got = poll_once(s)
        if got < 32usize { more = false }
        rounds += 1usize
    }
}

// The half-second fallback of a machine without a sensor server: the settings server's samples, one per tick.
fn step_tick(s: *State) {
    let (ax, ay, az) = accel_at(s.ticks)
    let (p, q, r) = gyro_at(s.ticks)
    feed(s, ax, ay, az, p * to_degrees(), q * to_degrees(), 0.5f64)
    judge_orientation(s)
    judge_feedback(s)
    s.dirty = true
}

fn act(s: *State, id: usize) -> bool {
    if id == 100usize || id == 101usize || id == 102usize {
        s.mode = id - 100usize
        if s.mode == LEVEL_MODE { ui.say("level mode Level\n") }
        if s.mode == ANGLE_MODE { ui.say("level mode Angle\n") }
        if s.mode == TEST_MODE { ui.say("level mode Test\n") }
        ret true
    }
    if id == 110usize {
        s.held = !s.held
        if s.held {
            s.held_x = raw_x(s)
            s.held_y = raw_y(s)
            ui.say("level hold on\n")
        } else {
            ui.say("level hold off\n")
        }
        ret true
    }
    if id == 111usize {
        s.zero_x = raw_x(s)
        s.zero_y = raw_y(s)
        if s.held {
            s.zero_x = s.held_x
            s.zero_y = s.held_y
        }
        save_zero(s)
        ui.say("level calibrate\n")
        ret true
    }
    if id == 112usize {
        s.on_edge = !s.on_edge
        ret true
    }
    if id == 113usize {
        // Replay the recorded session from its start, from a clean filter and no calibration in the way.
        s.replay = true
        s.marks = 0usize
        s.filtering = false
        s.testing = false
        s.zero_x = 0.0
        s.zero_y = 0.0
        s.held = false
        s.armed = false
        s.was_level = false
        if start_streams(s, sensorclient.SOURCE_REPLAY) {
            ui.say("level replay started\n")
        } else {
            s.replay = false
        }
        ret true
    }
    if id == 114usize {
        s.kalman = !s.kalman
        if s.kalman { ui.say("level filter Kalman\n") } else { ui.say("level filter Complementary\n") }
        ret true
    }
    if id == 115usize {
        s.mode = TEST_MODE
        s.replay = false
        s.testing = true
        s.test_n = 0usize
        s.test_done = false
        if start_streams(s, sensorclient.SOURCE_FLAT) {
            ui.say("level selftest started\n")
        } else {
            s.testing = false
        }
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
    s.kx = control.kalman_new(0.001f64, 0.003f64, 0.03f64)
    s.ky = control.kalman_new(0.001f64, 0.003f64, 0.03f64)
    s.shown = 9999usize
    if !start_streams(&s, sensorclient.SOURCE_LIVE) {
        step_tick(&s)
    } else {
        poll(&s)
    }
    if load_zero(&s) {
        ui.say("level kept ")
        ui.say_num(usize(s.zero_x * 10.0 + 1000.0))
        ui.say("\n")
    }
    if !show(a, &kit, &s) {
        ui.say("level present failed\n")
        ret ok
    }
    ui.say("level shown\n")
    var running = true
    while running {
        // With a stream the app wakes every 20 ms (50 Hz); without, it waits for the input server's half-second ticks.
        var wait = 0usize
        if s.streamed { wait = 20usize }
        let touch = appkit.next_touch(&kit, wait)
        if touch.kind == appkit.TOUCH_TIMEOUT {
            // Samples only: a frame goes to the compositor as the answer to an event it forwarded (the half-second
            // tick draws what changed), never on its own.
            poll(&s)
        } else if touch.kind == appkit.TOUCH_END {
            running = false
        } else if touch.kind == appkit.TOUCH_TICK {
            // The tick is the fallback's sample; with a stream it only draws what has changed.
            if !s.streamed {
                s.ticks += 1usize
                step_tick(&s)
            }
            if s.dirty && !s.held {
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if touch.kind == appkit.TOUCH_DOWN {
            if touch.y >= 896.0 {
                ui.say("level home\n")
                appkit.leave()
                running = false
            } else {
                let id = ui.hit_at(&s.hits, touch.x, touch.y)
                if id != ui.NONE && act(&s, id) {
                    if !show(a, &kit, &s) {
                        ui.say("level present failed\n")
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
