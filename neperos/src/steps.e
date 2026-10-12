// Steps (D2233): the app behind the Steps icon, a step counter after Google Fit -- a ring that fills as
// the day's steps approach the goal (6,000, 8,000 or 10,000), the steps in large type, three tiles
// (calories, distance, active minutes), a bar for each of the last seven days with the goal drawn across,
// a Walk button that starts counting and a Goal button that cycles the goal. Dark ground, cream cards and
// amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on
// the bar at the bottom leaves the app.
// ponytail: there is no step sensor, so the steps are SAMPLE data: today starts at 3,412, the six days
// before are made up, and Walk adds about two steps for each of the input server's 500 ms ticks. The
// calories, distance and active minutes are worked out from the steps (0.04 kcal, 0.75 m and 100 steps a
// minute). The accelerometer's step detector, the history in storage and sharing with Level's sensor
// server are queued as C138.
use e.mem
use e.os
use e.time
use e.math
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.algo.pedometer as ped
use appkit
use text
use ui
use sysettings
use sensor_sim
use vaultfs

const NONE: usize = 99usize

type State = struct {
    days: [7]usize,
    today: usize,
    goal: usize,
    walking: bool,
    ticks: usize,
    reached: bool,
    // (C138) The step detector over the accelerometer stream (25 Hz, twelve samples a tick), the next sample's
    // index, and today's count when walking began (the detector's steps are added to it).
    pedometer: ped.Pedometer,
    sample: usize,
    base: usize,
    hits: ui.Hits,
}

fn pi() -> f32 {
    ret 3.14159265
}

fn thousands(a: *mem.Arena, value: usize) -> str {
    if value < 1000usize { ret ui.number(a, value) }
    ret ui.join(a, ui.number(a, value / 1000usize), ",", ui.join(a, ui.number(a, (value / 100usize) % 10usize), ui.number(a, (value / 10usize) % 10usize), ui.number(a, value % 10usize)))
}

fn goal_of(index: usize) -> usize {
    if index == 0usize { ret 6000usize }
    if index == 1usize { ret 8000usize }
    ret 10000usize
}

fn weekday_label(offset: usize) -> str {
    // The days counted back from today: 6 is the oldest.
    if offset == 0usize { ret "Mon" }
    if offset == 1usize { ret "Tue" }
    if offset == 2usize { ret "Wed" }
    if offset == 3usize { ret "Thu" }
    if offset == 4usize { ret "Fri" }
    if offset == 5usize { ret "Sat" }
    ret "Sun"
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn draw_ring(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let cx: f32 = 206.0
    let cy: f32 = 210.0
    let radius: f32 = 118.0
    // The track, then the part done: a polyline round the circle from the top.
    var fraction = f32(s.today) / f32(s.goal)
    if fraction > 1.0 { fraction = 1.0 }
    let points = 72usize
    var all_x: [73]f32 = zero
    var all_y: [73]f32 = zero
    var i = 0usize
    while i <= points {
        let angle = f32(i) / f32(points) * 2.0 * pi()
        all_x[i] = cx + radius * math.sin(angle)
        all_y[i] = cy - radius * math.cos(angle)
        i += 1usize
    }
    try ui.polyline(a, builder, all_x[0usize..73usize], all_y[0usize..73usize], 73usize, 16.0, paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 })
    let done = usize(fraction * f32(points))
    if done >= 1usize { try ui.polyline(a, builder, all_x[0usize..73usize], all_y[0usize..73usize], done + 1usize, 16.0, ui.amber()) }
    try ui.centred(a, builder, faces.jost_bold, 56.0, thousands(a, s.today), cx, cy - 46.0, ui.light())
    try ui.centred(a, builder, faces.jost, 16.0, ui.join(a, "of ", thousands(a, s.goal), " steps"), cx, cy + 22.0, ui.light_muted())
    var note = ui.join(a, ui.number(a, usize(fraction * 100.0)), "% of your goal", "")
    if s.today >= s.goal { note = "Goal reached" }
    try ui.centred(a, builder, faces.jost, 15.0, note, cx, cy + 52.0, ui.amber())
    ret ok
}

fn tile(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, x: f32, label: str, value: str) -> err {
    try ui.card(a, builder, x, 360.0, 120.0, 84.0, 18.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, label, x + 14.0, 374.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 24.0, value, x + 14.0, 398.0, ui.ink())
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    try ui.put(a, builder, faces.jost_bold, 30.0, "Steps", 20.0, 20.0, ui.light())
    try draw_ring(a, builder, s, faces)
    let calories = s.today * 4usize / 100usize
    let metres = s.today * 3usize / 4usize
    try tile(a, builder, faces, 16.0, "Calories", ui.join(a, ui.number(a, calories), " kcal", ""))
    var distance = ui.join(a, ui.number(a, metres), " m", "")
    if metres >= 1000usize { distance = ui.join(a, ui.join(a, ui.number(a, metres / 1000usize), ".", ui.number(a, (metres % 1000usize) / 100usize)), " km", "") }
    try tile(a, builder, faces, 146.0, "Distance", distance)
    try tile(a, builder, faces, 276.0, "Active", ui.join(a, ui.number(a, s.today / 100usize), " min", ""))
    // The week: six days and today, a bar each, the goal across.
    try ui.card(a, builder, 16.0, 462.0, 380.0, 220.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost, 15.0, "This week", 32.0, 474.0, ui.ink())
    var best = s.goal
    var d = 0usize
    while d < 7usize {
        var value = s.days[d]
        if d == 6usize { value = s.today }
        if value > best { best = value }
        d += 1usize
    }
    let chart_top: f32 = 508.0
    let chart_height: f32 = 130.0
    let goal_y = chart_top + chart_height - f32(s.goal) / f32(best) * chart_height
    try ui.card(a, builder, 28.0, goal_y, 356.0, 1.5, 0.75, ui.amber_dark())
    d = 0usize
    while d < 7usize {
        var value = s.days[d]
        if d == 6usize { value = s.today }
        let height = f32(value) / f32(best) * chart_height
        var fill = ui.soft()
        if value >= s.goal { fill = ui.amber() }
        if d == 6usize { fill = ui.amber_dark() }
        let x: f32 = 38.0 + f32(d) * 48.0
        try ui.card(a, builder, x, chart_top + chart_height - height, 30.0, height, 6.0, fill)
        try ui.centred(a, builder, faces.grotesk, 11.0, weekday_label(d), x + 15.0, chart_top + chart_height + 8.0, ui.muted())
        d += 1usize
    }
    var walk = "Walk"
    var fill = ui.amber()
    if s.walking {
        walk = "Stop"
        fill = ui.soft()
    }
    try ui.pill(a, builder, &s.hits, faces, 100usize, 16.0, 710.0, 186.0, 52.0, walk, fill, 18.0)
    try ui.pill(a, builder, &s.hits, faces, 101usize, 210.0, 710.0, 186.0, 52.0, ui.join(a, "Goal ", thousands(a, s.goal), ""), ui.soft(), 18.0)
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

// One sample of the walking accelerometer: from the settings server's sensor service, else the same function here.
fn walk_sample(index: usize) -> f64 {
    let (x, y, z, served) = sysettings.sensor(sysettings.SENSOR_WALK, index)
    if served { ret f64(x) / 1000.0f64 }
    ret sensor_sim.walk_magnitude(index)
}

// The wall clock's day (days since the epoch), 0 with no clock.
fn wall_day() -> usize {
    let (wall, wall_error) = time.now()
    if wall_error != ok || wall.nanos <= 0i64 { ret 0usize }
    ret usize(wall.nanos / 86400000000000i64)
}

fn put_word(buf: []u8, at: usize, value: usize) {
    var i = 0usize
    while i < 4usize {
        buf[at + i] = u8((value >> (8usize * i)) & 255usize)
        i += 1usize
    }
}

fn get_word(buf: []const u8, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize {
        v = v | (usize(buf[at + i]) << (8usize * i))
        i += 1usize
    }
    ret v
}

// /steps is 36 bytes: today's count, the goal, the day (since the epoch) the count is for, and the six days before
// it, oldest first, four bytes each, little end. A file of eight bytes (before the history) is the first two only.
fn save_today(s: *State) {
    var buf: [36]u8 = zero
    put_word(buf[0usize..36usize], 0usize, s.today)
    put_word(buf[0usize..36usize], 4usize, s.goal)
    put_word(buf[0usize..36usize], 8usize, wall_day())
    var d = 0usize
    while d < 6usize {
        put_word(buf[0usize..36usize], 12usize + 4usize * d, s.days[d])
        d += 1usize
    }
    let kept = vaultfs.write("/steps", mem.address_of(&buf[0usize]), 36usize)
}

fn load_today(s: *State) -> bool {
    var buf: [36]u8 = zero
    let (n, found) = vaultfs.read("/steps", mem.address_of(&buf[0usize]), 36usize)
    if !found || n < 8usize { ret false }
    s.today = get_word(buf[0usize..36usize], 0usize)
    let goal = get_word(buf[0usize..36usize], 4usize)
    if goal >= 1000usize && goal <= 100000usize { s.goal = goal }
    if n >= 36usize {
        // The week as it was kept, slid forward over the days that have passed since.
        var week: [7]usize = zero
        var d = 0usize
        while d < 6usize {
            week[d] = get_word(buf[0usize..36usize], 12usize + 4usize * d)
            d += 1usize
        }
        week[6] = s.today
        let stored_day = get_word(buf[0usize..36usize], 8usize)
        ped.roll_week(week[0..], stored_day, wall_day())
        d = 0usize
        while d < 6usize {
            s.days[d] = week[d]
            d += 1usize
        }
        s.today = week[6]
    }
    ret true
}

fn act(s: *State, id: usize) -> bool {
    if id == 100usize {
        s.walking = !s.walking
        if s.walking {
            s.pedometer = ped.new(25usize)
            s.base = s.today
            ui.say("steps walking on\n")
        } else {
            ui.say("steps walking off\n")
            ui.say("steps total ")
            ui.say_num(s.today)
            ui.say("\n")
            save_today(s)
        }
        ret true
    }
    if id == 101usize {
        var which = 0usize
        if s.goal == 6000usize { which = 1usize }
        if s.goal == 8000usize { which = 2usize }
        s.goal = goal_of(which)
        ui.say("steps goal ")
        ui.say_num(s.goal)
        ui.say("\n")
        save_today(s)
        s.reached = s.today >= s.goal
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "steps")
    if kit_error != ok {
        ui.say("steps open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("steps fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.days[0usize] = 7240usize
    s.days[1usize] = 9100usize
    s.days[2usize] = 5380usize
    s.days[3usize] = 10420usize
    s.days[4usize] = 6870usize
    s.days[5usize] = 8210usize
    s.today = 3412usize
    s.goal = 8000usize
    if load_today(&s) {
        ui.say("steps loaded ")
        ui.say_num(s.today)
        ui.say("\n")
    }
    if !show(a, &kit, &s) {
        ui.say("steps present failed\n")
        ret ok
    }
    ui.say("steps shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // Walking: twelve samples of the accelerometer a tick go to the detector, and what it counts is added
            // to today; the goal is announced once.
            if s.walking {
                var k = 0usize
                while k < 12usize {
                    let counted = ped.feed(&s.pedometer, walk_sample(s.sample))
                    s.sample += 1usize
                    k += 1usize
                }
                s.today = s.base + ped.steps(&s.pedometer)
                if s.today >= s.goal && !s.reached {
                    s.reached = true
                    ui.say("steps reached goal\n")
                }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("steps home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    ui.say("steps present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
