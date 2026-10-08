// Meet (D2230): the app behind the Meet icon, video meetings after Google Meet -- a start screen (New
// meeting, Join with a code typed on the on-screen keyboard, and the meetings coming up), a join screen
// with your camera preview and the microphone and camera switches, and the meeting itself: a tile for each
// person (the one who is speaking has an amber outline), a timer, and Mic, Camera, Hand and a red End.
// Dark ground, cream cards and amber, like the other apps (appkit.e, taps from the compositor, the five
// fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: there is no network, camera or microphone, so a meeting is a DEMO: three made-up people join
// after a moment, "speak" in turn with the input server's 500 ms ticks, and your own tile shows the sample
// portrait of the Camera app. Real calls (signalling, media transport, camera and microphone capture,
// screen sharing, chat) are queued as C135.
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
use scenes

const NONE: usize = 99usize
const HOME_SCREEN: usize = 0usize
const CODE_SCREEN: usize = 1usize
const JOIN_SCREEN: usize = 2usize
const CALL_SCREEN: usize = 3usize

type State = struct {
    screen: usize,
    title: [24]u8,
    title_len: usize,
    code: ui.Field,
    mic: bool,
    camera: bool,
    hand: bool,
    ticks: usize,
    hits: ui.Hits,
}

fn person(who: usize) -> str {
    if who == 0usize { ret "Maya" }
    if who == 1usize { ret "Alex" }
    if who == 2usize { ret "Priya" }
    ret "You"
}

fn meeting_title(index: usize) -> str {
    if index == 0usize { ret "Design review" }
    if index == 1usize { ret "Weekly sync" }
    ret "Lunch and learn"
}

fn meeting_time(index: usize) -> str {
    if index == 0usize { ret "Today, 11:00 AM" }
    if index == 1usize { ret "Today, 2:30 PM" }
    ret "Tomorrow, 12:00 PM"
}

fn set_title(s: *State, title: str) {
    var i = 0usize
    while i < title.len && i < 24usize {
        s.title[i] = title[i]
        i += 1usize
    }
    s.title_len = i
}

fn title_of(a: *mem.Arena, s: *State) -> str {
    ret ui.text_of(a, s.title[0usize..], s.title_len)
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn picture(a: *mem.Arena, builder: *scene.Builder, doc: str, r: geometry.Rect, c: paint.Color) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: r } })
    try svg.draw(a, builder, doc, r, c)
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    ret ok
}

fn mic_icon(on: bool) -> str {
    if on { ret "<svg viewBox='0 0 24 24'><rect x='9' y='3' width='6' height='12' rx='3' fill='currentColor'/><path d='M5 11a7 7 0 0 0 14 0M12 18v3' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><rect x='9' y='3' width='6' height='12' rx='3' fill='currentColor'/><path d='M5 11a7 7 0 0 0 14 0M12 18v3M3 3l18 18' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>"
}

fn camera_icon(on: bool) -> str {
    if on { ret "<svg viewBox='0 0 24 24'><rect x='3' y='6' width='12' height='12' rx='2' fill='currentColor'/><path d='M15 10l6-3v10l-6-3z' fill='currentColor'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><rect x='3' y='6' width='12' height='12' rx='2' fill='currentColor'/><path d='M15 10l6-3v10l-6-3zM3 3l18 18' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>"
}

fn phone_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z' fill='currentColor'/></svg>"
}

fn hand_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M8 12V5a1.5 1.5 0 0 1 3 0v6M11 11V3.5a1.5 1.5 0 0 1 3 0V11M14 11V5a1.5 1.5 0 0 1 3 0v8c0 4-2 7-6 7s-6-3-6-6l-1-4a1.5 1.5 0 0 1 3-.5l1 2' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linejoin='round'/></svg>"
}

fn round_button(a: *mem.Arena, builder: *scene.Builder, s: *State, id: usize, cx: f32, cy: f32, icon: str, on: bool, red: bool) -> err {
    var fill = paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 }
    var tone = ui.light()
    if !on {
        fill = ui.cream()
        tone = ui.ink()
    }
    if red {
        fill = paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 }
        tone = ui.cream()
    }
    try ui.disc(a, builder, cx, cy, 30.0, fill)
    try svg.draw(a, builder, icon, geometry.rect(cx - 14.0, cy - 14.0, 28.0, 28.0), tone)
    ui.hit(&s.hits, id, cx - 32.0, cy - 32.0, 64.0, 64.0)
    ret ok
}

fn draw_home(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Meet", 20.0, 20.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 100usize, 16.0, 84.0, 186.0, 52.0, "New meeting", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 101usize, 210.0, 84.0, 186.0, 52.0, "Join with a code", ui.soft(), 17.0)
    try ui.put(a, builder, faces.jost, 15.0, "Coming up", 24.0, 160.0, ui.light_muted())
    var i = 0usize
    while i < 3usize {
        let y: f32 = 190.0 + f32(i) * 78.0
        try ui.card(a, builder, 16.0, y, 380.0, 70.0, 18.0, ui.cream())
        try ui.disc(a, builder, 50.0, y + 35.0, 20.0, ui.tint(i))
        try picture(a, builder, camera_icon(true), geometry.rect(38.0, y + 23.0, 24.0, 24.0), ui.ink())
        try ui.put(a, builder, faces.jost, 18.0, meeting_title(i), 84.0, y + 12.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, meeting_time(i), 84.0, y + 40.0, ui.muted())
        try ui.pill(a, builder, &s.hits, faces, 200usize + i, 312.0, y + 20.0, 72.0, 32.0, "Join", ui.amber(), 14.0)
        ui.hit(&s.hits, 200usize + i, 16.0, y, 380.0, 70.0)
        i += 1usize
    }
    ret ok
}

fn draw_code(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Join with a code", 24.0, 20.0, ui.light())
    let value = ui.field_text(a, &s.code)
    try ui.card(a, builder, 14.0, 90.0, 384.0, 56.0, 18.0, ui.amber())
    try ui.card(a, builder, 16.0, 92.0, 380.0, 52.0, 16.0, ui.cream())
    if value.len == 0usize { try ui.put(a, builder, faces.jost, 18.0, "abc-defg-hij", 32.0, 106.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 20.0, value, 32.0, 104.0, 340.0, ui.ink()) }
    try ui.pill(a, builder, &s.hits, faces, 300usize, 16.0, 170.0, 186.0, 46.0, "Join", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 301usize, 210.0, 170.0, 186.0, 46.0, "Cancel", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Join")
    ret ok
}

fn draw_join(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 301usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, title_of(a, s), 62.0, 20.0, ui.light())
    // Your preview.
    if s.camera {
        try picture(a, builder, scenes.scene_svg(a, 1usize, 2usize, 5usize, false, 380usize, 400usize), geometry.rect(16.0, 84.0, 380.0, 400.0), ui.light())
    } else {
        try ui.card(a, builder, 16.0, 84.0, 380.0, 400.0, 20.0, paint.Color { red: 0.14, green: 0.15, blue: 0.18, alpha: 1.0 })
        try ui.disc(a, builder, 206.0, 284.0, 56.0, ui.tint(3usize))
        try ui.centred(a, builder, faces.jost_bold, 52.0, "Y", 206.0, 252.0, ui.ink())
    }
    try round_button(a, builder, s, 700usize, 130.0, 540.0, mic_icon(s.mic), s.mic, false)
    try round_button(a, builder, s, 701usize, 282.0, 540.0, camera_icon(s.camera), s.camera, false)
    try ui.centred(a, builder, faces.jost, 16.0, "Ready to join?", 206.0, 610.0, ui.light())
    try ui.centred(a, builder, faces.grotesk, 12.0, "Maya and 2 others are in the meeting (demo)", 206.0, 640.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 710usize, 106.0, 700.0, 200.0, 52.0, "Join now", ui.amber(), 18.0)
    ret ok
}

fn draw_call(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let seconds = s.ticks / 2usize
    try ui.put(a, builder, faces.jost, 18.0, title_of(a, s), 20.0, 18.0, ui.light())
    try ui.put_right(a, builder, faces.grotesk, 14.0, ui.join(a, ui.number(a, seconds / 60usize), ":", ui.two(a, seconds % 60usize)), 392.0, 22.0, ui.light_muted())
    // Who is in the meeting: Maya at once, Alex after two seconds, Priya after four; you.
    var joined: usize = 1usize
    if s.ticks >= 4usize { joined = 2usize }
    if s.ticks >= 8usize { joined = 3usize }
    let speaker = (s.ticks / 6usize) % joined
    var tile = 0usize
    while tile < 4usize {
        let x: f32 = 12.0 + f32(tile % 2usize) * 196.0
        let y: f32 = 60.0 + f32(tile / 2usize) * 304.0
        var who = tile
        if tile == 3usize { who = 3usize }
        let present = tile == 3usize || tile < joined
        var rim = paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 }
        if present && tile != 3usize && tile == speaker { rim = ui.amber() }
        try ui.card(a, builder, x - 2.0, y - 2.0, 192.0, 296.0, 20.0, rim)
        try ui.card(a, builder, x, y, 188.0, 292.0, 18.0, paint.Color { red: 0.14, green: 0.15, blue: 0.18, alpha: 1.0 })
        if !present {
            try ui.centred(a, builder, faces.jost, 15.0, "Joining...", x + 94.0, y + 134.0, ui.light_muted())
        } else if tile == 3usize && s.camera {
            try picture(a, builder, scenes.scene_svg(a, 1usize, 2usize, 5usize, false, 188usize, 292usize), geometry.rect(x, y, 188.0, 292.0), ui.light())
        } else {
            try ui.disc(a, builder, x + 94.0, y + 130.0, 42.0, ui.tint(tile))
            let name = person(who)
            try ui.centred(a, builder, faces.jost_bold, 40.0, name[0usize..1usize], x + 94.0, y + 106.0, ui.ink())
        }
        if present {
            try ui.card(a, builder, x + 8.0, y + 262.0, 100.0, 22.0, 11.0, ui.shade(0.55))
            try ui.put(a, builder, faces.jost, 13.0, person(who), x + 16.0, y + 265.0, ui.light())
            if tile == 3usize && !s.mic { try ui.disc(a, builder, x + 170.0, y + 273.0, 9.0, ui.loss()) }
        }
        tile += 1usize
    }
    try round_button(a, builder, s, 700usize, 70.0, 790.0, mic_icon(s.mic), s.mic, false)
    try round_button(a, builder, s, 701usize, 150.0, 790.0, camera_icon(s.camera), s.camera, false)
    try round_button(a, builder, s, 702usize, 230.0, 790.0, hand_icon(), !s.hand, false)
    try round_button(a, builder, s, 711usize, 332.0, 790.0, phone_icon(), true, true)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.07, 0.08, 0.10)
    if s.screen == HOME_SCREEN { try draw_home(a, builder, s, faces) }
    if s.screen == CODE_SCREEN { try draw_code(a, builder, s, faces) }
    if s.screen == JOIN_SCREEN { try draw_join(a, builder, s, faces) }
    if s.screen == CALL_SCREEN { try draw_call(a, builder, s, faces) }
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

fn to_join(a: *mem.Arena, s: *State, title: str) {
    set_title(s, title)
    s.screen = JOIN_SCREEN
    s.mic = true
    s.camera = true
    ui.say("meet joining ")
    ui.say_text(title)
    ui.say("\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == CALL_SCREEN {
        if id == 700usize {
            s.mic = !s.mic
            if s.mic { ui.say("meet mic on\n") } else { ui.say("meet mic off\n") }
            ret true
        }
        if id == 701usize {
            s.camera = !s.camera
            if s.camera { ui.say("meet camera on\n") } else { ui.say("meet camera off\n") }
            ret true
        }
        if id == 702usize {
            s.hand = !s.hand
            ret true
        }
        if id == 711usize {
            ui.say("meet ended ")
            ui.say_num(s.ticks / 2usize)
            ui.say("s\n")
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == JOIN_SCREEN {
        if id == 700usize {
            s.mic = !s.mic
            ret true
        }
        if id == 701usize {
            s.camera = !s.camera
            ret true
        }
        if id == 710usize {
            s.screen = CALL_SCREEN
            s.ticks = 0usize
            ui.say("meet joined\n")
            ret true
        }
        if id == 301usize {
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == CODE_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.code.len > 0usize { to_join(a, s, ui.field_text(a, &s.code)) }
                ret true
            }
            ret ui.field_key(&s.code, id, false)
        }
        if id == 300usize {
            if s.code.len > 0usize { to_join(a, s, ui.field_text(a, &s.code)) }
            ret true
        }
        if id == 301usize {
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if id == 100usize {
        to_join(a, s, "New meeting")
        ret true
    }
    if id == 101usize {
        s.screen = CODE_SCREEN
        s.code.len = 0usize
        ret true
    }
    if id >= 200usize && id < 203usize {
        to_join(a, s, meeting_title(id - 200usize))
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "meet")
    if kit_error != ok {
        ui.say("meet open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("meet fonts absent\n")
        ret ok
    }
    var s: State = zero
    if !show(a, &kit, &s) {
        ui.say("meet present failed\n")
        ret ok
    }
    ui.say("meet shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // In a meeting the timer, the people joining and the speaker follow the ticks.
            if s.screen == CALL_SCREEN {
                s.ticks += 1usize
                if s.ticks % 2usize == 0usize {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("meet home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("meet present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
