// Recorder (D2231): the app behind the Recorder icon, a voice recorder after the Pixel's -- a list of
// recordings (name, how long ago, length) with a red record button; the recording screen (the time and a
// sound wave that scrolls while it records, Stop to keep it); the playback screen (the whole wave with a
// playhead, Play and Pause, five seconds back and forward, the transcript, Delete). Dark ground, cream
// cards and amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]).
// A tap on the bar at the bottom leaves the app.
// ponytail: there is no microphone, speaker or speech engine, so the wave is SAMPLE data drawn from a
// seed, a recording is kept only in this process (its length is the seconds counted from the input
// server's 500 ms ticks), and the transcripts are made up (a new recording says none is available).
// Real capture and playback through e.audio, files in storage and a speech-to-text model are queued as
// C136.
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
const MAX_RECS: usize = 10usize
const WAVE: usize = 48usize
const LIST_SCREEN: usize = 0usize
const RECORD_SCREEN: usize = 1usize
const PLAY_SCREEN: usize = 2usize

type Rec = struct { name: [24]u8, name_len: usize, seconds: usize, ago: usize, seed: usize, sample: bool, used: bool }

type State = struct {
    recs: [10]Rec,
    rec_total: usize,
    screen: usize,
    open: usize,
    ticks: usize,
    live: [48]u8,
    playing: bool,
    head: usize,
    hits: ui.Hits,
}

fn add_rec(s: *State, name: str, seconds: usize, ago: usize, seed: usize, sample: bool) {
    // The newest first.
    var k = MAX_RECS - 1usize
    while k > 0usize {
        s.recs[k] = s.recs[k - 1usize]
        k -= 1usize
    }
    var r: Rec = zero
    var i = 0usize
    while i < name.len && i < 24usize {
        r.name[i] = name[i]
        i += 1usize
    }
    r.name_len = i
    r.seconds = seconds
    r.ago = ago
    r.seed = seed
    r.sample = sample
    r.used = true
    s.recs[0usize] = r
    if s.rec_total < MAX_RECS { s.rec_total += 1usize }
}

fn rec_name(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.recs[i].name[0usize..], s.recs[i].name_len)
}

fn mmss(a: *mem.Arena, seconds: usize) -> str {
    ret ui.join(a, ui.number(a, seconds / 60usize), ":", ui.two(a, seconds % 60usize))
}

// The height (0..100) of bar `i` of a recording's wave.
fn wave_at(seed: usize, i: usize) -> usize {
    var x = (seed * 7919usize + i * 104729usize + 12345usize) & 2147483647usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    ret 12usize + (x >> 10usize) % 80usize
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn play_icon(playing: bool) -> str {
    if playing { ret "<svg viewBox='0 0 24 24'><path d='M7 4h4v16H7zM13 4h4v16h-4z' fill='currentColor'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M7 4l13 8-13 8z' fill='currentColor'/></svg>"
}

fn skip_icon(back: bool) -> str {
    if back { ret "<svg viewBox='0 0 24 24'><path d='M12 5a8 8 0 1 0 8 8M12 1v8l-4-4' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M12 5a8 8 0 1 1-8 8M12 1v8l4-4' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn trash_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13M10 11v6M14 11v6' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn bars(a: *mem.Arena, builder: *scene.Builder, s: *State, seed: usize, count: usize, x: f32, y: f32, w: f32, h: f32, upto: usize, live: bool) -> err {
    var i = 0usize
    let pitch: f32 = w / f32(count)
    while i < count {
        var height: f32 = 0.0
        if live { height = f32(s.live[i]) } else { height = f32(wave_at(seed, i)) }
        height = height / 100.0 * h
        if height < 4.0 { height = 4.0 }
        var tone = ui.soft()
        if live || i < upto { tone = ui.amber() }
        try ui.card(a, builder, x + f32(i) * pitch + 1.0, y + (h - height) / 2.0, pitch - 3.0, height, 2.0, tone)
        i += 1usize
    }
    ret ok
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Recorder", 20.0, 20.0, ui.light())
    var i = 0usize
    while i < s.rec_total {
        let r = s.recs[i]
        let y: f32 = 80.0 + f32(i) * 70.0
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, ui.cream())
        try ui.put(a, builder, faces.jost, 18.0, rec_name(a, s, i), 32.0, y + 10.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.ago_text(a, r.ago), 32.0, y + 38.0, ui.muted())
        try ui.put_right(a, builder, faces.jost, 16.0, mmss(a, r.seconds), 380.0, y + 22.0, ui.muted())
        ui.hit(&s.hits, 200usize + i, 16.0, y + 2.0, 380.0, 64.0)
        i += 1usize
    }
    try ui.disc(a, builder, 206.0, 830.0, 42.0, ui.cream())
    try ui.disc(a, builder, 206.0, 830.0, 34.0, ui.loss())
    ui.hit(&s.hits, 100usize, 160.0, 784.0, 92.0, 92.0)
    ret ok
}

fn draw_record(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.centred(a, builder, faces.jost, 18.0, "Recording", 206.0, 120.0, ui.loss())
    try ui.centred(a, builder, faces.jost_bold, 72.0, mmss(a, s.ticks / 2usize), 206.0, 170.0, ui.light())
    try ui.card(a, builder, 16.0, 330.0, 380.0, 160.0, 20.0, ui.cream())
    try bars(a, builder, s, 0usize, WAVE, 24.0, 340.0, 364.0, 140.0, WAVE, true)
    try ui.pill(a, builder, &s.hits, faces, 110usize, 106.0, 640.0, 200.0, 60.0, "Stop", ui.amber(), 20.0)
    ret ok
}

fn draw_play(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let r = s.recs[s.open]
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 22.0, rec_name(a, s, s.open), 62.0, 20.0, ui.light())
    try ui.card(a, builder, 16.0, 90.0, 380.0, 150.0, 20.0, ui.cream())
    var upto = WAVE
    if r.seconds > 0usize { upto = s.head * WAVE / r.seconds }
    try bars(a, builder, s, r.seed, WAVE, 24.0, 100.0, 364.0, 130.0, upto, false)
    try ui.put(a, builder, faces.jost, 16.0, mmss(a, s.head), 24.0, 250.0, ui.light())
    try ui.put_right(a, builder, faces.jost, 16.0, mmss(a, r.seconds), 392.0, 250.0, ui.light_muted())
    try ui.disc(a, builder, 206.0, 340.0, 38.0, ui.amber())
    try svg.draw(a, builder, play_icon(s.playing), geometry.rect(190.0, 324.0, 32.0, 32.0), ui.ink())
    ui.hit(&s.hits, 300usize, 164.0, 298.0, 84.0, 84.0)
    try ui.disc(a, builder, 100.0, 340.0, 26.0, paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, skip_icon(true), geometry.rect(86.0, 326.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 301usize, 70.0, 310.0, 60.0, 60.0)
    try ui.disc(a, builder, 312.0, 340.0, 26.0, paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, skip_icon(false), geometry.rect(298.0, 326.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 302usize, 282.0, 310.0, 60.0, 60.0)
    try ui.card(a, builder, 16.0, 410.0, 380.0, 280.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost_bold, 17.0, "Transcript", 32.0, 424.0, ui.ink())
    var words = "No transcript: there is no speech engine yet."
    if r.sample && s.open == 1usize { words = "Okay, so the plan for the week: finish the Settings app, then Photos, and on Friday we review the icons together." }
    if r.sample && s.open == 2usize { words = "Remember to buy milk, call the library about the hold, and send Maya the lunch place." }
    if r.sample && s.open >= 3usize { words = "Idea: an app that writes apps from a prompt, compiles them on a server and installs them." }
    let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, words, 32.0, 456.0, 348.0, 9u32, ui.muted())
    if box_error != ok { ret box_error }
    try svg.draw(a, builder, trash_icon(), geometry.rect(184.0, 724.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 310usize, 150.0, 710.0, 100.0, 56.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN { try draw_list(a, builder, s, faces) }
    if s.screen == RECORD_SCREEN { try draw_record(a, builder, s, faces) }
    if s.screen == PLAY_SCREEN { try draw_play(a, builder, s, faces) }
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

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == RECORD_SCREEN {
        if id == 110usize {
            var seconds = s.ticks / 2usize
            if seconds < 1usize { seconds = 1usize }
            add_rec(s, ui.join(a, "Recording ", ui.number(a, s.rec_total + 1usize), ""), seconds, 0usize, s.rec_total * 7usize + 3usize, false)
            ui.say("recorder saved ")
            ui.say_num(seconds)
            ui.say("s\n")
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == PLAY_SCREEN {
        if id == 500usize {
            s.playing = false
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 300usize {
            s.playing = !s.playing
            if s.playing { ui.say("recorder playing\n") } else { ui.say("recorder paused\n") }
            ret true
        }
        if id == 301usize {
            if s.head >= 5usize { s.head -= 5usize } else { s.head = 0usize }
            ret true
        }
        if id == 302usize {
            s.head += 5usize
            if s.head > s.recs[s.open].seconds { s.head = s.recs[s.open].seconds }
            ret true
        }
        if id == 310usize {
            var k = s.open + 1usize
            while k < s.rec_total {
                s.recs[k - 1usize] = s.recs[k]
                k += 1usize
            }
            s.rec_total -= 1usize
            s.screen = LIST_SCREEN
            s.playing = false
            ui.say("recorder deleted\n")
            ret true
        }
        ret false
    }
    if id == 100usize {
        s.screen = RECORD_SCREEN
        s.ticks = 0usize
        var i = 0usize
        while i < WAVE {
            s.live[i] = 6u8
            i += 1usize
        }
        ui.say("recorder recording\n")
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_RECS {
        if id - 200usize < s.rec_total {
            s.open = id - 200usize
            s.screen = PLAY_SCREEN
            s.head = 0usize
            s.playing = false
            ui.say("recorder open ")
            ui.say_text(rec_name(a, s, s.open))
            ui.say("\n")
            ret true
        }
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "recorder")
    if kit_error != ok {
        ui.say("recorder open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("recorder fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    add_rec(&s, "Ideas", 62usize, 14400usize, 5usize, true)
    add_rec(&s, "Shopping list", 18usize, 2000usize, 6usize, true)
    add_rec(&s, "Weekly plan", 134usize, 300usize, 4usize, true)
    if !show(a, &kit, &s) {
        ui.say("recorder present failed\n")
        ret ok
    }
    ui.say("recorder shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // Recording: the wave scrolls by one bar a tick. Playing: the playhead moves a second per two ticks.
            if s.screen == RECORD_SCREEN {
                s.ticks += 1usize
                var k = 1usize
                while k < WAVE {
                    s.live[k - 1usize] = s.live[k]
                    k += 1usize
                }
                s.live[WAVE - 1usize] = u8(wave_at(s.ticks, 3usize))
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else if s.screen == PLAY_SCREEN && s.playing {
                s.ticks += 1usize
                if s.ticks % 2usize == 0usize { s.head += 1usize }
                if s.head >= s.recs[s.open].seconds {
                    s.head = s.recs[s.open].seconds
                    s.playing = false
                    ui.say("recorder finished\n")
                }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("recorder home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("recorder present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
