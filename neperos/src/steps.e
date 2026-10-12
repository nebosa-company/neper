// Steps (D2233): the app behind the Steps icon, a step counter after Google Fit -- a ring that fills as the day's steps
// approach the goal (6,000, 8,000 or 10,000), the steps in large type with what the phone feels (still, walking,
// running), three tiles (calories, distance, active minutes), a bar for each of the last seven days (or thirty) with
// the goal drawn across and the streak and the week's report, a Walk button that starts counting a simulated walk, a
// Goal button that cycles the goal, a Week/Month switch and a Replay of a recorded walk. Dark ground, cream cards and
// amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at
// the bottom leaves the app.
//
// (C168, D4010) The count comes from the sensor hub's step counter (sensorclient.steps): the hub counts whether or
// not this app runs, so what was walked while it was closed is added when it opens (the counter's value at the last
// save is kept in /steps, and a counter that restarted is not read as steps). The history is thirty days in storage
// (/steps, 136 bytes), rolled forward over the days that passed; the streak is the days in a row at or over the goal; the
// calories and the distance follow the profile in Settings (height and weight, e.algo.pedometer) and whether the
// cadence is a run. The goal reached posts a notification through the background services process. Replay feeds a
// recorded accelerometer walk of two minutes (served by the sensor server, played as fast as it is read) through the
// step detector and reports its count against the recording's 228 steps.
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
use sensorclient
use bgclient
use vaultfs

const NONE: usize = 99usize
// The history: thirty days, today last; the file is 36 bytes of what the week held, the hub counter's value, the best
// streak and the 23 days before the week.
const DAYS: usize = 30usize
const FILE_BYTES: usize = 136usize
// The recorded walk: two minutes at 25 Hz, 1.9 steps a second.
const REPLAY_SAMPLES: usize = 3000usize
const REPLAY_STEPS: usize = 228usize

type State = struct {
    // Seven days of the week (the sixth day before today first, today at [6], which is kept in `today`) and the 23
    // days before them, oldest first.
    days: [7]usize,
    older: [23]usize,
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
    // (C168) The hub's counter: its value at the last save or read, what the app has read of it (and whether it is
    // served), the cadence now in hundredths of a step a second, and the best streak.
    hub_base: usize,
    hub_served: bool,
    cadence: usize,
    best_streak: usize,
    // 0 the week, 1 the month.
    view: usize,
    // The replay of a recorded walk: running, its own detector and how many samples it has had.
    replaying: bool,
    replay_ped: ped.Pedometer,
    replay_n: usize,
    replay_result: usize,
    // The screen is behind the counts: drawn at the next tick (a frame is only the answer to an event).
    dirty: bool,
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

fn weekday_name(day: usize) -> str {
    if day == 0usize { ret "Mon" }
    if day == 1usize { ret "Tue" }
    if day == 2usize { ret "Wed" }
    if day == 3usize { ret "Thu" }
    if day == 4usize { ret "Fri" }
    if day == 5usize { ret "Sat" }
    ret "Sun"
}

// The weekday label of the bar `back` days before today: the wall clock's weekday (Monday 0), or fixed labels with no clock.
fn weekday_label(back: usize) -> str {
    let day = wall_day()
    if day == 0usize { ret weekday_name((7usize - back % 7usize) % 7usize) }
    ret weekday_name((day + 3usize + 7usize * 5usize - back) % 7usize)
}

// ----------------------------------------------------------------------------------------------
// The profile and what the steps are worth.

fn height_cm(index: usize) -> f64 {
    ret 155.0f64 + 10.0f64 * f64(index)
}

fn weight_kg(index: usize) -> f64 {
    if index == 0usize { ret 55.0f64 }
    if index == 1usize { ret 70.0f64 }
    if index == 2usize { ret 85.0f64 }
    ret 100.0f64
}

// The profile of Settings (36 height, 37 weight; a machine without the server keeps the defaults, 165 cm and 70 kg).
fn profile() -> (usize, usize) {
    let (h, h_served) = sysettings.get(36usize)
    let (w, w_served) = sysettings.get(37usize)
    var height = 1usize
    var weight = 1usize
    if h_served && h < 4usize { height = h }
    if w_served && w < 4usize { weight = w }
    ret (height, weight)
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
    try ui.centred(a, builder, faces.jost, 15.0, note, cx, cy + 50.0, ui.amber())
    try ui.centred(a, builder, faces.grotesk, 12.0, motion_label(s), cx, cy + 76.0, ui.light_muted())
    ret ok
}

// What the phone feels: running over 2.5 steps a second, walking over half a step, else still.
fn motion_label(s: *State) -> str {
    if !s.hub_served { ret "" }
    if s.cadence >= 250usize { ret "Running" }
    if s.cadence >= 50usize { ret "Walking" }
    ret "Still"
}

fn tile(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, x: f32, label: str, value: str) -> err {
    try ui.card(a, builder, x, 360.0, 120.0, 84.0, 18.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 12.0, label, x + 14.0, 374.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 24.0, value, x + 14.0, 398.0, ui.ink())
    ret ok
}

// The value of day `d` of the thirty (0 the oldest, 29 today).
fn day_value(s: *State, d: usize) -> usize {
    if d < 23usize { ret s.older[d] }
    if d < 29usize { ret s.days[d - 23usize] }
    ret s.today
}

// The days in a row at or over the goal, counting back from today (yesterday when today is not there yet).
fn streak_of(s: *State) -> usize {
    var count = 0usize
    var d = DAYS - 1usize
    if s.today < s.goal { d = DAYS - 2usize }
    var going = true
    while going {
        if day_value(s, d) >= s.goal {
            count += 1usize
            if d == 0usize { going = false } else { d -= 1usize }
        } else {
            going = false
        }
    }
    ret count
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    try ui.put(a, builder, faces.jost_bold, 30.0, "Steps", 20.0, 20.0, ui.light())
    let streak = streak_of(s)
    if streak > 0usize {
        try ui.put_right(a, builder, faces.jost, 16.0, ui.join(a, ui.number(a, streak), " day streak", ""), 396.0, 30.0, ui.amber())
    }
    try draw_ring(a, builder, s, faces)
    // The calories and the distance follow the profile and the cadence (a run covers more ground a step).
    let (height_index, weight_index) = profile()
    let running = s.hub_served && s.cadence >= 250usize
    let metres_f = ped.distance_m(s.today, height_cm(height_index), running)
    let calories_f = ped.calories_kcal(metres_f, weight_kg(weight_index), running)
    let calories = usize(calories_f + 0.5f64)
    let metres = usize(metres_f + 0.5f64)
    try tile(a, builder, faces, 16.0, "Calories", ui.join(a, ui.number(a, calories), " kcal", ""))
    var distance = ui.join(a, ui.number(a, metres), " m", "")
    if metres >= 1000usize { distance = ui.join(a, ui.join(a, ui.number(a, metres / 1000usize), ".", ui.number(a, (metres % 1000usize) / 100usize)), " km", "") }
    try tile(a, builder, faces, 146.0, "Distance", distance)
    try tile(a, builder, faces, 276.0, "Active", ui.join(a, ui.number(a, s.today / 100usize), " min", ""))
    // The week (or the month): a bar each, the goal across, and the report.
    try ui.card(a, builder, 16.0, 462.0, 380.0, 236.0, 20.0, ui.cream())
    var count = 7usize
    var title = "This week"
    if s.view == 1usize {
        count = DAYS
        title = "This month"
    }
    try ui.put(a, builder, faces.jost, 15.0, title, 32.0, 474.0, ui.ink())
    var best = s.goal
    var d = 0usize
    while d < count {
        let value = day_value(s, DAYS - count + d)
        if value > best { best = value }
        d += 1usize
    }
    let chart_top: f32 = 504.0
    let chart_height: f32 = 120.0
    let goal_y = chart_top + chart_height - f32(s.goal) / f32(best) * chart_height
    try ui.card(a, builder, 28.0, goal_y, 356.0, 1.5, 0.75, ui.amber_dark())
    d = 0usize
    while d < count {
        let value = day_value(s, DAYS - count + d)
        let height = f32(value) / f32(best) * chart_height
        var fill = ui.soft()
        if value >= s.goal { fill = ui.amber() }
        if d == count - 1usize { fill = ui.amber_dark() }
        if count == 7usize {
            let x: f32 = 38.0 + f32(d) * 48.0
            try ui.card(a, builder, x, chart_top + chart_height - height, 30.0, height, 6.0, fill)
            try ui.centred(a, builder, faces.grotesk, 11.0, weekday_label(6usize - d), x + 15.0, chart_top + chart_height + 6.0, ui.muted())
        } else {
            let x: f32 = 30.0 + f32(d) * 11.7
            try ui.card(a, builder, x, chart_top + chart_height - height, 8.0, height, 2.0, fill)
        }
        d += 1usize
    }
    // The week's report: the steps, the days the goal was met and the best day.
    var total = 0usize
    var met = 0usize
    var best_day = 0usize
    var best_back = 0usize
    d = 0usize
    while d < 7usize {
        let value = day_value(s, DAYS - 7usize + d)
        total += value
        if value >= s.goal { met += 1usize }
        if value > best_day {
            best_day = value
            best_back = 6usize - d
        }
        d += 1usize
    }
    let report = ui.join(a, ui.join(a, thousands(a, total), " steps, goal met ", ui.number(a, met)), " of 7, best ", ui.join(a, weekday_label(best_back), " ", thousands(a, best_day)))
    try ui.clipped(a, builder, faces.grotesk, 13.0, report, 32.0, 660.0, 348.0, ui.muted())
    var walk = "Walk"
    var fill = ui.amber()
    if s.walking {
        walk = "Stop"
        fill = ui.soft()
    }
    try ui.pill(a, builder, &s.hits, faces, 100usize, 16.0, 710.0, 186.0, 52.0, walk, fill, 18.0)
    try ui.pill(a, builder, &s.hits, faces, 101usize, 210.0, 710.0, 186.0, 52.0, ui.join(a, "Goal ", thousands(a, s.goal), ""), ui.soft(), 18.0)
    var view_label = "Month"
    if s.view == 1usize { view_label = "Week" }
    try ui.pill(a, builder, &s.hits, faces, 102usize, 16.0, 774.0, 186.0, 46.0, view_label, ui.soft(), 16.0)
    var replay_label = "Replay a walk"
    var replay_fill = ui.soft()
    if s.replaying {
        replay_label = "Replaying..."
        replay_fill = ui.amber()
    }
    try ui.pill(a, builder, &s.hits, faces, 103usize, 210.0, 774.0, 186.0, 46.0, replay_label, replay_fill, 16.0)
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

// /steps is 136 bytes: today's count, the goal, the day (since the epoch) the count is for, the six days before it
// (oldest first), the hub counter's value when it was kept, the best streak, and the 23 days before those; four bytes
// each, little end. A file of 36 bytes (before the counter) is the first part only, one of 8 the first two.
fn save_today(s: *State) {
    var buf: [136]u8 = zero
    put_word(buf[0usize..136usize], 0usize, s.today)
    put_word(buf[0usize..136usize], 4usize, s.goal)
    put_word(buf[0usize..136usize], 8usize, wall_day())
    var d = 0usize
    while d < 6usize {
        put_word(buf[0usize..136usize], 12usize + 4usize * d, s.days[d])
        d += 1usize
    }
    put_word(buf[0usize..136usize], 36usize, s.hub_base)
    put_word(buf[0usize..136usize], 40usize, s.best_streak)
    d = 0usize
    while d < 23usize {
        put_word(buf[0usize..136usize], 44usize + 4usize * d, s.older[d])
        d += 1usize
    }
    let kept = vaultfs.write("/steps", mem.address_of(&buf[0usize]), FILE_BYTES)
}

// Slide the thirty days forward over the days that have passed since `stored_day`: yesterday's count moves into the
// week, the oldest day drops off, and today starts again at zero.
fn roll_days(s: *State, stored_day: usize, now_day: usize) {
    if stored_day == 0usize || now_day <= stored_day { ret }
    var passed = now_day - stored_day
    if passed > DAYS { passed = DAYS }
    var old: [30]usize = zero
    var d = 0usize
    while d < DAYS {
        old[d] = day_value(s, d)
        d += 1usize
    }
    d = 0usize
    while d < DAYS {
        var value = 0usize
        if d + passed < DAYS { value = old[d + passed] }
        if d < 23usize { s.older[d] = value } else if d < 29usize { s.days[d - 23usize] = value } else { s.today = value }
        d += 1usize
    }
}

fn load_today(s: *State) -> bool {
    var buf: [136]u8 = zero
    let (n, found) = vaultfs.read("/steps", mem.address_of(&buf[0usize]), FILE_BYTES)
    if !found || n < 8usize { ret false }
    s.today = get_word(buf[0usize..136usize], 0usize)
    let goal = get_word(buf[0usize..136usize], 4usize)
    if goal >= 1000usize && goal <= 100000usize { s.goal = goal }
    if n >= 36usize {
        var d = 0usize
        while d < 6usize {
            s.days[d] = get_word(buf[0usize..136usize], 12usize + 4usize * d)
            d += 1usize
        }
        if n >= FILE_BYTES {
            s.hub_base = get_word(buf[0usize..136usize], 36usize)
            s.best_streak = get_word(buf[0usize..136usize], 40usize)
            d = 0usize
            while d < 23usize {
                s.older[d] = get_word(buf[0usize..136usize], 44usize + 4usize * d)
                d += 1usize
            }
        }
        roll_days(s, get_word(buf[0usize..136usize], 8usize), wall_day())
    }
    ret true
}

// Take what the hub has counted since the last read into today: the steps walked while the app was closed on opening,
// and the live ones on every tick. A counter lower than the last one read restarted (a reboot): it is read from its
// new start, not as a loss.
fn read_hub(s: *State, opening: bool) {
    let (count, cadence, status) = sensorclient.steps()
    if status != sensorclient.STATUS_OK {
        s.hub_served = false
        ret
    }
    s.hub_served = true
    s.cadence = cadence
    if count < s.hub_base {
        s.hub_base = 0usize
    }
    if count > s.hub_base {
        let gained = count - s.hub_base
        s.today += gained
        s.hub_base = count
        if opening {
            ui.say("steps background ")
            ui.say_num(gained)
            ui.say("\n")
        }
    }
}

fn judge_goal(s: *State) {
    if s.today >= s.goal && !s.reached {
        s.reached = true
        ui.say("steps reached goal\n")
        bgclient.notify_goal()
        let (peak, served) = bgclient.play(bgclient.STREAM_MEDIA, bgclient.TONE_CHIME, 200usize)
    }
    var streak = streak_of(s)
    if streak > s.best_streak { s.best_streak = streak }
}

// The recorded walk: the samples the server has, a few hundred at a call, through the replay's own detector.
fn poll_replay(s: *State) {
    var rounds = 0usize
    while s.replaying && rounds < 16usize {
        var batch: [32]sensorclient.Reading = zero
        let (count, first, denied) = sensorclient.read(sensorclient.KIND_ACCELEROMETER, batch[0usize..32usize])
        if denied {
            s.replaying = false
            ui.say("steps replay denied\n")
            ret
        }
        var i = 0usize
        while i < count && s.replay_n < REPLAY_SAMPLES {
            let magnitude = f64(batch[i].z) / 1000.0f64
            let counted = ped.feed(&s.replay_ped, magnitude)
            s.replay_n += 1usize
            i += 1usize
        }
        if s.replay_n >= REPLAY_SAMPLES {
            finish_replay(s)
            ret
        }
        rounds += 1usize
    }
}

fn finish_replay(s: *State) {
    if s.replay_n >= REPLAY_SAMPLES {
        let found = ped.steps(&s.replay_ped)
        s.replay_result = found
        s.replaying = false
        s.dirty = true
        sensorclient.close(sensorclient.KIND_ACCELEROMETER)
        var off = 0usize
        if found > REPLAY_STEPS { off = found - REPLAY_STEPS } else { off = REPLAY_STEPS - found }
        ui.say("steps replay ")
        ui.say_num(found)
        ui.say(" of ")
        ui.say_num(REPLAY_STEPS)
        // Within two per cent of the recording's steps.
        if off * 50usize <= REPLAY_STEPS { ui.say(" within 2 percent\n") } else { ui.say(" off\n") }
    }
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
    if id == 102usize {
        if s.view == 0usize { s.view = 1usize } else { s.view = 0usize }
        if s.view == 1usize { ui.say("steps view month\n") } else { ui.say("steps view week\n") }
        ret true
    }
    if id == 103usize {
        if s.replaying { ret false }
        let (status, rate) = sensorclient.open(sensorclient.KIND_ACCELEROMETER, 25usize, sensorclient.SOURCE_WALK)
        if status != sensorclient.STATUS_OK {
            ui.say("steps replay unavailable\n")
            ret false
        }
        s.replay_ped = ped.new(25usize)
        s.replay_n = 0usize
        s.replaying = true
        ui.say("steps replay started\n")
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
    // The weeks before the sample week: made-up numbers around the goal, until real ones are kept.
    var o = 0usize
    while o < 23usize {
        s.older[o] = 4000usize + (o * 977usize) % 7000usize
        o += 1usize
    }
    if load_today(&s) {
        ui.say("steps loaded ")
        ui.say_num(s.today)
        ui.say("\n")
    }
    // What the hub counted while the app was closed.
    read_hub(&s, true)
    s.reached = s.today >= s.goal
    if s.hub_served {
        ui.say("steps hub ")
        ui.say_num(s.hub_base)
        ui.say("\n")
    }
    if !show(a, &kit, &s) {
        ui.say("steps present failed\n")
        ret ok
    }
    ui.say("steps shown\n")
    var running = true
    while running {
        // The replay reads as fast as the server serves, so the app wakes every 20 ms for it; otherwise on events.
        var wait = 0usize
        if s.replaying { wait = 20usize }
        let touch = appkit.next_touch(&kit, wait)
        if touch.kind == appkit.TOUCH_TIMEOUT {
            poll_replay(&s)
        } else if touch.kind == appkit.TOUCH_END {
            running = false
        } else if touch.kind == appkit.TOUCH_TICK {
            // Walking: twelve samples of the accelerometer a tick go to the detector, and what it counts is added
            // to today; the hub's steps join them; the goal is announced once.
            var moved = false
            if s.walking {
                var k = 0usize
                while k < 12usize {
                    let counted = ped.feed(&s.pedometer, walk_sample(s.sample))
                    s.sample += 1usize
                    k += 1usize
                }
                s.today = s.base + ped.steps(&s.pedometer)
                moved = true
            }
            let before = s.today
            read_hub(&s, false)
            if s.today != before { moved = true }
            judge_goal(&s)
            if s.replaying { poll_replay(&s) }
            // (A replay in progress is not drawn: a frame takes longer than the samples it would hold up.)
            if (moved || s.dirty) && !s.replaying {
                s.dirty = false
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if touch.kind == appkit.TOUCH_DOWN {
            if touch.y >= 896.0 {
                ui.say("steps home\n")
                // What the hub counted is kept, so the next opening adds only what comes after it.
                save_today(&s)
                appkit.leave()
                running = false
            } else {
                let id = ui.hit_at(&s.hits, touch.x, touch.y)
                if id != ui.NONE && act(&s, id) {
                    if !show(a, &kit, &s) {
                        ui.say("steps present failed\n")
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
