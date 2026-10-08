// Dynamic (D2238): the app behind the Dynamic icon -- make an app by describing it. You write a prompt
// ("a tip calculator", "a counter", "a dice roller"), and the app goes through the stages a real one would:
// written, compiled in Neper, security scanned, ready; it joins your list with a version, you can open it,
// look at its manifest (name, version, capabilities, the scan result, a signature), and extend it with
// another prompt, which makes the next version. Dark ground, cream cards and amber, like the other apps
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app.
// ponytail: there is no server, no model and no network, so the apps are made from THREE TEMPLATES inside
// this app (a counter, a tip calculator and a dice roller, picked by a word in the prompt), the stages are
// timed by the input server's 500 ms ticks, the "signature" is a made-up string, and "extend" adds a
// feature name to the manifest. The real thing -- a prompt sent to a server where a model writes Neper, the
// Neper compiler builds it, a scanner checks the code against the capabilities it asks for, and the signed
// image is installed with its icon on the home screen -- is queued as C124.
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
const MAX_APPS: usize = 6usize
const HOME_SCREEN: usize = 0usize
const PROMPT_SCREEN: usize = 1usize
const PROGRESS_SCREEN: usize = 2usize
const READY_SCREEN: usize = 3usize
const RUN_SCREEN: usize = 4usize
const DETAILS_SCREEN: usize = 5usize
const COUNTER: usize = 0usize
const TIP: usize = 1usize
const DICE: usize = 2usize

type Made = struct { name: [24]u8, name_len: usize, template: usize, version: usize, extras: usize, used: bool }

type State = struct {
    apps: [6]Made,
    app_total: usize,
    screen: usize,
    current: usize,
    prompt: ui.Field,
    extending: bool,
    ticks: usize,
    // The running apps' state: the counter, the bill and tip of the calculator, the die.
    counter: usize,
    bill: usize,
    tip: usize,
    die: usize,
    seed: usize,
    hits: ui.Hits,
}

fn template_name(t: usize) -> str {
    if t == COUNTER { ret "Counter" }
    if t == TIP { ret "Tip calculator" }
    ret "Dice roller"
}

// Which template a prompt asks for, by a word in it.
fn pick_template(a: *mem.Arena, text_in: str) -> usize {
    if contains(text_in, "tip") || contains(text_in, "bill") { ret TIP }
    if contains(text_in, "dice") || contains(text_in, "die") || contains(text_in, "roll") { ret DICE }
    ret COUNTER
}

fn contains(hay: str, needle: str) -> bool {
    if needle.len > hay.len { ret false }
    var at = 0usize
    while at + needle.len <= hay.len {
        var k = 0usize
        var match_all = true
        while k < needle.len {
            var c = hay[at + k]
            if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
            if c != needle[k] { match_all = false }
            k += 1usize
        }
        if match_all { ret true }
        at += 1usize
    }
    ret false
}

fn app_name(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.apps[i].name[0usize..], s.apps[i].name_len)
}

fn add_app(s: *State, name: str, template: usize) -> usize {
    if s.app_total >= MAX_APPS { ret NONE }
    var m: Made = zero
    var i = 0usize
    while i < name.len && i < 24usize {
        m.name[i] = name[i]
        i += 1usize
    }
    m.name_len = i
    m.template = template
    m.version = 1usize
    m.used = true
    s.apps[s.app_total] = m
    s.app_total += 1usize
    ret s.app_total - 1usize
}

fn stage_name(stage: usize) -> str {
    if stage == 0usize { ret "Writing the app" }
    if stage == 1usize { ret "Compiling with the Neper compiler" }
    if stage == 2usize { ret "Scanning for security" }
    ret "Ready"
}

fn stage_note(stage: usize) -> str {
    if stage == 0usize { ret "42 lines of Neper written" }
    if stage == 1usize { ret "neper build: ok, 0 errors" }
    if stage == 2usize { ret "no network, no storage, no raw syscalls" }
    ret "signed and installed"
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn spark_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M12 2c1 6 4 9 10 10-6 1-9 4-10 10-1-6-4-9-10-10 6-1 9-4 10-10z' fill='currentColor'/></svg>"
}

fn check_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M5.5 12.5l4.2 4.2L18.5 7.6' fill='none' stroke='currentColor' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn draw_home(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, spark_icon(), geometry.rect(20.0, 22.0, 28.0, 28.0), ui.amber())
    try ui.put(a, builder, faces.jost_bold, 30.0, "Dynamic", 56.0, 16.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "Describe an app, and it is made for you", 24.0, 62.0, ui.light_muted())
    try ui.card(a, builder, 16.0, 90.0, 380.0, 120.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost, 18.0, "What app do you need?", 32.0, 106.0, ui.muted())
    try ui.put(a, builder, faces.grotesk, 12.0, "For example: a tip calculator, a counter, a dice roller", 32.0, 140.0, ui.muted())
    try ui.pill(a, builder, &s.hits, faces, 110usize, 32.0, 164.0, 180.0, 36.0, "Describe an app", ui.amber(), 15.0)
    ui.hit(&s.hits, 110usize, 16.0, 90.0, 380.0, 120.0)
    try ui.put(a, builder, faces.jost, 15.0, "Your apps", 24.0, 232.0, ui.light_muted())
    var i = 0usize
    while i < s.app_total {
        let y: f32 = 262.0 + f32(i) * 68.0
        try ui.card(a, builder, 16.0, y, 380.0, 60.0, 18.0, ui.cream())
        try ui.card(a, builder, 28.0, y + 10.0, 40.0, 40.0, 12.0, ui.tint(s.apps[i].template))
        try ui.centred(a, builder, faces.jost_bold, 20.0, app_name(a, s, i)[0usize..1usize], 48.0, y + 18.0, ui.ink())
        try ui.put(a, builder, faces.jost, 18.0, app_name(a, s, i), 84.0, y + 8.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.join(a, "Version ", ui.number(a, s.apps[i].version), ""), ", made by Dynamic", ""), 84.0, y + 34.0, ui.muted())
        ui.hit(&s.hits, 200usize + i, 16.0, y, 380.0, 60.0)
        i += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Demo: three templates, no server yet", 24.0, 800.0, ui.light_muted())
    ret ok
}

fn draw_prompt(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "Describe your app"
    if s.extending { heading = ui.join(a, "Extend ", app_name(a, s, s.current), "") }
    try ui.put(a, builder, faces.jost_bold, 26.0, heading, 24.0, 14.0, ui.light())
    try ui.card(a, builder, 14.0, 70.0, 384.0, 130.0, 18.0, ui.amber())
    try ui.card(a, builder, 16.0, 72.0, 380.0, 126.0, 16.0, ui.cream())
    let value = ui.field_text(a, &s.prompt)
    if value.len == 0usize { try ui.put(a, builder, faces.jost, 18.0, "A tip calculator for two people", 30.0, 86.0, ui.muted()) } else {
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 19.0, value, 30.0, 86.0, 350.0, 4u32, ui.ink())
        if box_error != ok { ret box_error }
    }
    try ui.pill(a, builder, &s.hits, faces, 300usize, 16.0, 216.0, 186.0, 46.0, "Make it", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 301usize, 210.0, 216.0, 186.0, 46.0, "Cancel", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Make")
    ret ok
}

fn draw_progress(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 26.0, "Making your app", 24.0, 14.0, ui.light())
    let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, ui.join(a, "\"", ui.field_text(a, &s.prompt), "\""), 24.0, 56.0, 364.0, 2u32, ui.light_muted())
    if box_error != ok { ret box_error }
    var stage = 0usize
    while stage < 4usize {
        let y: f32 = 150.0 + f32(stage) * 90.0
        var done = s.ticks >= (stage + 1usize) * 2usize
        var active = s.ticks >= stage * 2usize && !done
        if stage == 3usize { done = s.ticks >= 6usize }
        try ui.card(a, builder, 16.0, y, 380.0, 78.0, 18.0, ui.cream())
        var fill = ui.soft()
        if done { fill = ui.amber() }
        try ui.disc(a, builder, 52.0, y + 39.0, 18.0, fill)
        if done { try svg.draw(a, builder, check_icon(), geometry.rect(40.0, y + 27.0, 24.0, 24.0), ui.ink()) }
        if active && !done { try ui.centred(a, builder, faces.jost_bold, 16.0, "...", 52.0, y + 28.0, ui.ink()) }
        try ui.put(a, builder, faces.jost, 18.0, stage_name(stage), 84.0, y + 14.0, ui.ink())
        if done || active { try ui.put(a, builder, faces.grotesk, 12.0, stage_note(stage), 84.0, y + 44.0, ui.muted()) }
        stage += 1usize
    }
    ret ok
}

fn draw_ready(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let m = s.apps[s.current]
    try ui.card(a, builder, 148.0, 90.0, 116.0, 116.0, 28.0, ui.tint(m.template))
    try ui.centred(a, builder, faces.jost_bold, 56.0, app_name(a, s, s.current)[0usize..1usize], 206.0, 118.0, ui.ink())
    try ui.centred(a, builder, faces.jost_bold, 26.0, app_name(a, s, s.current), 206.0, 226.0, ui.light())
    try ui.centred(a, builder, faces.grotesk, 14.0, ui.join(a, "Version ", ui.number(a, m.version), " is ready and installed"), 206.0, 266.0, ui.amber())
    try ui.centred(a, builder, faces.grotesk, 12.0, "Made by Dynamic. Generated code: check what it asks for.", 206.0, 296.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 400usize, 16.0, 360.0, 186.0, 52.0, "Open app", ui.amber(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 401usize, 210.0, 360.0, 186.0, 52.0, "Extend", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 402usize, 16.0, 424.0, 186.0, 46.0, "Details", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 403usize, 210.0, 424.0, 186.0, 46.0, "Done", ui.soft(), 16.0)
    ret ok
}

fn draw_details(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let m = s.apps[s.current]
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "Manifest", 62.0, 20.0, ui.light())
    var row = 0usize
    while row < 7usize {
        var label = "Name"
        var value = app_name(a, s, s.current)
        if row == 1usize {
            label = "Version"
            value = ui.number(a, m.version)
        }
        if row == 2usize {
            label = "Capabilities"
            value = "ui"
        }
        if row == 3usize {
            label = "Features"
            value = ui.join(a, ui.number(a, 1usize + m.extras), " added by prompts", "")
        }
        if row == 4usize {
            label = "Scan"
            value = "passed"
        }
        if row == 5usize {
            label = "Source"
            value = "kept on the server"
        }
        if row == 6usize {
            label = "Signature"
            value = ui.join(a, "demo-", ui.number(a, 7340000usize + m.template * 911usize + m.version * 37usize), "")
        }
        let y: f32 = 84.0 + f32(row) * 56.0
        try ui.card(a, builder, 16.0, y, 380.0, 50.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.grotesk, 12.0, label, 32.0, y + 17.0, ui.muted())
        try ui.put_right(a, builder, faces.jost, 17.0, value, 380.0, y + 14.0, ui.ink())
        row += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Sample manifest: the signature is made up", 24.0, 484.0, ui.light_muted())
    ret ok
}

fn draw_run(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let m = s.apps[s.current]
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 22.0, app_name(a, s, s.current), 62.0, 20.0, ui.light())
    if m.template == COUNTER {
        try ui.centred(a, builder, faces.jost_bold, 120.0, ui.number(a, s.counter), 206.0, 200.0, ui.light())
        try ui.pill(a, builder, &s.hits, faces, 600usize, 40.0, 420.0, 100.0, 64.0, "-", ui.soft(), 28.0)
        try ui.pill(a, builder, &s.hits, faces, 601usize, 156.0, 420.0, 100.0, 64.0, "Reset", ui.soft(), 18.0)
        try ui.pill(a, builder, &s.hits, faces, 602usize, 272.0, 420.0, 100.0, 64.0, "+", ui.amber(), 28.0)
    } else if m.template == TIP {
        try ui.card(a, builder, 16.0, 100.0, 380.0, 140.0, 20.0, ui.cream())
        try ui.put(a, builder, faces.grotesk, 12.0, "Bill", 32.0, 114.0, ui.muted())
        try ui.put(a, builder, faces.jost_bold, 44.0, ui.join(a, "$", ui.number(a, s.bill), ""), 32.0, 134.0, ui.ink())
        try ui.pill(a, builder, &s.hits, faces, 610usize, 246.0, 150.0, 60.0, 56.0, "-", ui.soft(), 26.0)
        try ui.pill(a, builder, &s.hits, faces, 611usize, 322.0, 150.0, 60.0, 56.0, "+", ui.amber(), 26.0)
        var chip = 0usize
        while chip < 4usize {
            let pct = 10usize + chip * 5usize
            var fill = ui.soft()
            if s.tip == pct { fill = ui.amber() }
            try ui.pill(a, builder, &s.hits, faces, 620usize + chip, 16.0 + f32(chip) * 97.0, 262.0, 88.0, 40.0, ui.join(a, ui.number(a, pct), "%", ""), fill, 16.0)
            chip += 1usize
        }
        let tip_amount = s.bill * s.tip / 100usize
        try ui.card(a, builder, 16.0, 330.0, 380.0, 130.0, 20.0, ui.cream())
        try ui.put(a, builder, faces.grotesk, 12.0, "Tip", 32.0, 344.0, ui.muted())
        try ui.put(a, builder, faces.jost_bold, 28.0, ui.join(a, "$", ui.number(a, tip_amount), ""), 32.0, 362.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, "Total", 220.0, 344.0, ui.muted())
        try ui.put(a, builder, faces.jost_bold, 28.0, ui.join(a, "$", ui.number(a, s.bill + tip_amount), ""), 220.0, 362.0, ui.amber_dark())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Each of two: $", ui.number(a, (s.bill + tip_amount + 1usize) / 2usize), ""), 32.0, 418.0, ui.muted())
    } else {
        try ui.card(a, builder, 106.0, 170.0, 200.0, 200.0, 36.0, ui.cream())
        try ui.centred(a, builder, faces.jost_bold, 110.0, ui.number(a, s.die), 206.0, 214.0, ui.ink())
        try ui.pill(a, builder, &s.hits, faces, 630usize, 106.0, 420.0, 200.0, 60.0, "Roll", ui.amber(), 22.0)
    }
    if m.extras > 0usize { try ui.centred(a, builder, faces.grotesk, 12.0, ui.join(a, ui.number(a, m.extras), " feature(s) added by extending", ""), 206.0, 520.0, ui.light_muted()) }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == HOME_SCREEN { try draw_home(a, builder, s, faces) }
    if s.screen == PROMPT_SCREEN { try draw_prompt(a, builder, s, faces) }
    if s.screen == PROGRESS_SCREEN { try draw_progress(a, builder, s, faces) }
    if s.screen == READY_SCREEN { try draw_ready(a, builder, s, faces) }
    if s.screen == DETAILS_SCREEN { try draw_details(a, builder, s, faces) }
    if s.screen == RUN_SCREEN { try draw_run(a, builder, s, faces) }
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

fn start_making(a: *mem.Arena, s: *State) {
    if s.prompt.len == 0usize { ret }
    let words = ui.field_text(a, &s.prompt)
    ui.say("dynamic prompt ")
    ui.say_text(words)
    ui.say("\n")
    if !s.extending {
        let template = pick_template(a, words)
        let made = add_app(s, template_name(template), template)
        if made == NONE { ret }
        s.current = made
    }
    s.ticks = 0usize
    s.screen = PROGRESS_SCREEN
}

fn finish_making(a: *mem.Arena, s: *State) {
    if s.extending {
        s.apps[s.current].version += 1usize
        s.apps[s.current].extras += 1usize
        ui.say("dynamic extended ")
        ui.say_text(app_name(a, s, s.current))
        ui.say(" v")
        ui.say_num(s.apps[s.current].version)
        ui.say("\n")
    } else {
        ui.say("dynamic ready ")
        ui.say_text(app_name(a, s, s.current))
        ui.say(" v1\n")
    }
    s.extending = false
    s.screen = READY_SCREEN
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == PROMPT_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                start_making(a, s)
                ret true
            }
            ret ui.field_key(&s.prompt, id, true)
        }
        if id == 300usize {
            start_making(a, s)
            ret true
        }
        if id == 301usize {
            s.screen = HOME_SCREEN
            s.extending = false
            ret true
        }
        ret false
    }
    if s.screen == READY_SCREEN {
        if id == 400usize {
            s.screen = RUN_SCREEN
            s.counter = 0usize
            s.bill = 40usize
            s.tip = 15usize
            s.die = 1usize
            ui.say("dynamic open ")
            ui.say_text(app_name(a, s, s.current))
            ui.say("\n")
            ret true
        }
        if id == 401usize {
            s.extending = true
            s.prompt.len = 0usize
            s.screen = PROMPT_SCREEN
            ret true
        }
        if id == 402usize {
            s.screen = DETAILS_SCREEN
            ret true
        }
        if id == 403usize {
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == DETAILS_SCREEN {
        if id == 500usize {
            s.screen = READY_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == RUN_SCREEN {
        if id == 500usize {
            s.screen = READY_SCREEN
            ret true
        }
        if id == 600usize {
            if s.counter > 0usize { s.counter -= 1usize }
            ret true
        }
        if id == 601usize {
            s.counter = 0usize
            ret true
        }
        if id == 602usize {
            s.counter += 1usize
            ret true
        }
        if id == 610usize {
            if s.bill > 5usize { s.bill -= 5usize }
            ret true
        }
        if id == 611usize {
            s.bill += 5usize
            ret true
        }
        if id >= 620usize && id < 624usize {
            s.tip = 10usize + (id - 620usize) * 5usize
            ret true
        }
        if id == 630usize {
            s.seed = (s.seed * 1103515245usize + 12345usize) & 2147483647usize
            s.die = 1usize + (s.seed >> 10usize) % 6usize
            ui.say("dynamic rolled ")
            ui.say_num(s.die)
            ui.say("\n")
            ret true
        }
        ret false
    }
    if s.screen == PROGRESS_SCREEN { ret false }
    // Home.
    if id == 110usize {
        s.screen = PROMPT_SCREEN
        s.extending = false
        s.prompt.len = 0usize
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_APPS {
        if id - 200usize < s.app_total {
            s.current = id - 200usize
            s.screen = READY_SCREEN
            ret true
        }
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "dynamic")
    if kit_error != ok {
        ui.say("dynamic open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("dynamic fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.seed = 424242usize
    s.current = NONE
    let first = add_app(&s, "Counter", COUNTER)
    if !show(a, &kit, &s) {
        ui.say("dynamic present failed\n")
        ret ok
    }
    ui.say("dynamic shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The stages follow the ticks: a stage takes a second.
            if s.screen == PROGRESS_SCREEN {
                s.ticks += 1usize
                if s.ticks % 2usize == 0usize && s.ticks <= 6usize {
                    var stage = s.ticks / 2usize
                    if stage > 3usize { stage = 3usize }
                    ui.say("dynamic stage ")
                    ui.say(stage_name(stage))
                    ui.say("\n")
                }
                if s.ticks >= 7usize { finish_making(a, &s) }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("dynamic home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("dynamic present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
