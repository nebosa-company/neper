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
// (C151) With a network the prompt goes to the build server instead (httpstream.e, over TLS): its stages are the
// server's own, shown as it sends them (server-sent events); the signed package is streamed into memory, checked
// against the server's key (package.e), kept in /apps, and the shell puts its icon on the home screen when this app
// is left. The revocation list is fetched from the server and its signature checked before it is kept (C173). A
// machine without a network makes the three templates as before.
use e.mem
use e.os
use e.fmt.sse as sse
use httpstream
use httpc
use netproto
use package
use server_key
use vaultfs
use jsonlite
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

const NONE: usize = 99usize
const MAX_APPS: usize = 6usize
const HOME_SCREEN: usize = 0usize
const PROMPT_SCREEN: usize = 1usize
const PROGRESS_SCREEN: usize = 2usize
const READY_SCREEN: usize = 3usize
const RUN_SCREEN: usize = 4usize
const DETAILS_SCREEN: usize = 5usize
// (C151) An app the server made: its page, and its manifest.
const SERVED_SCREEN: usize = 6usize
const SERVED_DETAILS_SCREEN: usize = 7usize
const BODY_CAP: usize = 16384usize
const PACKAGE_CAP: usize = 1048576usize
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
    // (C151) The build server: the incremental reader, the buffers outside the frames (the event stream's body and the
    // package), and where the make is: 0 not at the server, 1 stages arriving, 2 the package arriving, 3 done.
    net: httpstream.Stream,
    body: []u8,
    pkg: []u8,
    pkg_len: usize,
    srv: usize,
    sse_at: usize,
    silent: usize,
    srv_stage: usize,
    srv_note: [64]u8,
    srv_note_len: usize,
    srv_fail: [80]u8,
    srv_fail_len: usize,
    srv_id: [24]u8,
    srv_id_len: usize,
    srv_name: [24]u8,
    srv_name_len: usize,
    srv_size: usize,
    srv_attempts: usize,
    srv_kept: bool,
    // (C173) The revocation list last fetched: its entries, and whether the signature held.
    revoked_count: usize,
    revoked_state: usize,
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

// (C126) The apps made are kept by the settings server, so they survive leaving the app and a restart, and
// Settings lists them: entry i of the registry is apps[i + 1] (apps[0] is the sample the app starts with).
fn persist(s: *State) {
    var i = 0usize
    while i < 5usize {
        var w0 = 0usize
        var w1 = 0usize
        var w2 = 0usize
        var w3 = 0usize
        if i + 1usize < s.app_total {
            let m = s.apps[i + 1usize]
            var j = 0usize
            while j < m.name_len && j < 24usize {
                let byte = usize(m.name[j]) << ((j % 8usize) * 8usize)
                if j < 8usize { w0 = w0 | byte } else if j < 16usize { w1 = w1 | byte } else { w2 = w2 | byte }
                j += 1usize
            }
            w3 = m.name_len | (m.template << 8usize) | (m.version << 16usize) | (m.extras << 24usize)
        }
        let stored = sysettings.dyn_set(i, w0, w1, w2, w3)
        i += 1usize
    }
}

fn restore(s: *State) {
    var i = 0usize
    while i < 5usize {
        let (w0, w1, w2, w3, answered) = sysettings.dyn_get(i)
        let length = w3 & 255usize
        if answered && length > 0usize && length <= 24usize && s.app_total < MAX_APPS {
            var m: Made = zero
            var j = 0usize
            while j < length {
                var word = w2
                if j < 8usize { word = w0 } else if j < 16usize { word = w1 }
                m.name[j] = u8((word >> ((j % 8usize) * 8usize)) & 255usize)
                j += 1usize
            }
            m.name_len = length
            m.template = (w3 >> 8usize) & 255usize
            m.version = (w3 >> 16usize) & 255usize
            m.extras = (w3 >> 24usize) & 255usize
            m.used = true
            s.apps[s.app_total] = m
            s.app_total += 1usize
        }
        i += 1usize
    }
    if s.app_total > 1usize {
        ui.say("dynamic restored ")
        ui.say_num(s.app_total - 1usize)
        ui.say("\n")
    }
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
    // (C173) The revocation list from the server, its signature checked.
    try ui.pill(a, builder, &s.hits, faces, 111usize, 216.0, 164.0, 160.0, 36.0, "Revocations", ui.soft(), 15.0)
    var revoked_line = ""
    if s.revoked_state == 1usize { revoked_line = ui.join(a, ui.join(a, "Revocation list: ", ui.number(a, s.revoked_count), " listed, signed by the server"), "", "") }
    if s.revoked_state == 2usize { revoked_line = "Revocation list: the server did not answer" }
    if s.revoked_state == 3usize { revoked_line = "Revocation list refused: not signed by the server" }
    if revoked_line.len > 0usize { try ui.put(a, builder, faces.grotesk, 11.0, revoked_line, 24.0, 214.0, ui.light_muted()) }
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
        // (C151) At the server the stages are the ones it has sent: those before its stage are done, its own is
        // running, and a failure stops them where they were.
        var note = stage_note(stage)
        if s.srv != 0usize {
            done = stage < s.srv_stage || s.srv >= 2usize && stage < 3usize || s.srv == 4usize
            active = stage == s.srv_stage && !done && s.srv != 3usize
            if stage == s.srv_stage && s.srv_note_len > 0usize { note = ui.text_of(a, s.srv_note[0usize..], s.srv_note_len) }
        }
        try ui.card(a, builder, 16.0, y, 380.0, 78.0, 18.0, ui.cream())
        var fill = ui.soft()
        if done { fill = ui.amber() }
        try ui.disc(a, builder, 52.0, y + 39.0, 18.0, fill)
        if done { try svg.draw(a, builder, check_icon(), geometry.rect(40.0, y + 27.0, 24.0, 24.0), ui.ink()) }
        if active && !done { try ui.centred(a, builder, faces.jost_bold, 16.0, "...", 52.0, y + 28.0, ui.ink()) }
        try ui.put(a, builder, faces.jost, 18.0, stage_name(stage), 84.0, y + 14.0, ui.ink())
        if done || active { try ui.put(a, builder, faces.grotesk, 12.0, note, 84.0, y + 44.0, ui.muted()) }
        stage += 1usize
    }
    // (C151) What went wrong, in plain words, and the way back.
    if s.srv == 3usize {
        try ui.card(a, builder, 16.0, 520.0, 380.0, 120.0, 18.0, ui.cream())
        try ui.put(a, builder, faces.jost_bold, 17.0, "It could not be made", 32.0, 534.0, ui.loss())
        let (reason_box, reason_error) = ui.wrapped(a, builder, faces.grotesk, 14.0, ui.text_of(a, s.srv_fail[0usize..], s.srv_fail_len), 32.0, 562.0, 348.0, 3u32, ui.ink())
        if reason_error != ok { ret reason_error }
        try ui.pill(a, builder, &s.hits, faces, 460usize, 16.0, 660.0, 186.0, 46.0, "Back", ui.amber(), 17.0)
    }
    ret ok
}

// (C151) An app the server made and signed: installed in /apps, its icon on the home screen once Dynamic is left.
fn draw_served(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let name = ui.text_of(a, s.srv_name[0usize..], s.srv_name_len)
    try ui.card(a, builder, 148.0, 90.0, 116.0, 116.0, 28.0, ui.tint(s.srv_name_len))
    try ui.centred(a, builder, faces.jost_bold, 56.0, name[0usize..1usize], 206.0, 118.0, ui.ink())
    try ui.centred(a, builder, faces.jost_bold, 26.0, name, 206.0, 226.0, ui.light())
    var line = "Signed by the server and installed"
    if !s.srv_kept { line = "Signed by the server (the disk would not keep it)" }
    try ui.centred(a, builder, faces.grotesk, 14.0, line, 206.0, 266.0, ui.amber())
    try ui.centred(a, builder, faces.grotesk, 12.0, "Its icon appears on the home screen when you leave Dynamic.", 206.0, 296.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 470usize, 16.0, 360.0, 186.0, 52.0, "Details", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 471usize, 210.0, 360.0, 186.0, 52.0, "Done", ui.amber(), 18.0)
    ret ok
}

// The manifest of the package that arrived: what the server wrote and the device checked.
fn draw_served_details(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "Manifest", 62.0, 20.0, ui.light())
    let (pkg, pkg_error) = package.parse(s.pkg[0usize..s.pkg_len])
    var row = 0usize
    while row < 7usize {
        var label = "Name"
        var key = "name"
        if row == 1usize {
            label = "Version"
            key = "version"
        }
        if row == 2usize {
            label = "Kit level"
            key = "api"
        }
        if row == 3usize {
            label = "Capabilities"
            key = "capabilities"
        }
        if row == 4usize {
            label = "Scan"
            key = "scan"
        }
        if row == 5usize {
            label = "Build"
            key = "build"
        }
        if row == 6usize {
            label = "Reproducible"
            key = "reproducible"
        }
        var value = "-"
        if pkg_error == ok {
            let (found_value, has_value) = package.value(pkg, key)
            if has_value && found_value.len > 0usize { value = ui.text_of(a, found_value, found_value.len) }
            if has_value && found_value.len == 0usize { value = "none" }
        }
        let y: f32 = 84.0 + f32(row) * 56.0
        try ui.card(a, builder, 16.0, y, 380.0, 50.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.grotesk, 12.0, label, 32.0, y + 17.0, ui.muted())
        try ui.put_right(a, builder, faces.jost, 17.0, value, 380.0, y + 14.0, ui.ink())
        row += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "The signature was checked against the server's key", 24.0, 484.0, ui.light_muted())
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
    if s.screen == SERVED_SCREEN { try draw_served(a, builder, s, faces) }
    if s.screen == SERVED_DETAILS_SCREEN { try draw_served_details(a, builder, s, faces) }
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

// ----------------------------------------------------------------------------------------------
// The build server (C151): the protocol of httpstream.e over TLS, the stages it sends, the package it streams.

fn copy_into(dst: []u8, source: str) -> usize {
    var n = 0usize
    while n < source.len && n < dst.len {
        dst[n] = source[n]
        n += 1usize
    }
    ret n
}

// The request: the prompt and the kit's level, as JSON. True when the request is out and stages will come.
fn server_start(a: *mem.Arena, s: *State) -> bool {
    var buf: [400]u8 = zero
    var n = httpstream.put(buf[0usize..], 0usize, "{\"prompt\":\"")
    var i = 0usize
    while i < s.prompt.len && n + 4usize < buf.len - 24usize {
        let c = s.prompt.bytes[i]
        if c == 34u8 || c == 92u8 {
            buf[n] = 92u8
            buf[n + 1usize] = c
            n += 2usize
        } else if c >= 32u8 {
            buf[n] = c
            n += 1usize
        }
        i += 1usize
    }
    n = httpstream.put(buf[0usize..], n, "\",\"api\":1}")
    httpstream.begin(&s.net, mem.address_of(&s.body[0usize]), s.body.len)
    let result = httpstream.start(a, &s.net, "POST", "neper.test", "/dynamic/make", "", ui.text_of(a, buf[0usize..], n), 443u16, true)
    if result != netproto.R_OK { ret false }
    s.sse_at = 0usize
    s.silent = 0usize
    s.srv_stage = 0usize
    s.srv_note_len = 0usize
    s.srv_fail_len = 0usize
    s.srv_kept = false
    s.srv = 1usize
    ret true
}

fn server_fail(s: *State, reason: str) {
    httpstream.abort(&s.net)
    s.srv_fail_len = copy_into(s.srv_fail[0usize..], reason)
    s.srv = 3usize
    ui.say("dynamic server failed ")
    ui.say_text(reason)
    ui.say("\n")
}

// The path /apps/<name's letters and digits, lower case>.npkg the shell reads (shell.e's adopt keeps the same rule).
fn package_path(a: *mem.Arena, name: str) -> str {
    var file: [24]u8 = zero
    var f = 0usize
    var k = 0usize
    while k < name.len && f < 14usize {
        var c = name[k]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) {
            file[f] = c
            f += 1usize
        }
        k += 1usize
    }
    let suffix = ".npkg"
    var q = 0usize
    while q < suffix.len {
        file[f + q] = suffix[q]
        q += 1usize
    }
    ret ui.join(a, "/apps/", ui.text_of(a, file[0usize..], f + suffix.len), "")
}

// The package has arrived whole: check it against the server's key, keep it in /apps.
fn server_package_done(a: *mem.Arena, s: *State) {
    // The server closes the stream when the package is out, with or without a close_notify (the stream's `failed` is
    // set then): what counts is that all the bytes the `done` event promised are here, and the signature says the rest.
    if s.net.status != 200usize || s.net.body_len == 0usize || s.net.overflow {
        server_fail(s, "The package did not arrive")
        ret
    }
    if s.srv_size != 0usize && s.net.body_len != s.srv_size {
        server_fail(s, "The package arrived short")
        ret
    }
    s.pkg_len = s.net.body_len
    ui.say("dynamic package ")
    ui.say_num(s.pkg_len)
    ui.say(" bytes\n")
    let (pkg, pkg_error) = package.check(s.pkg[0usize..s.pkg_len], server_key.public())
    if pkg_error != ok {
        server_fail(s, "The package's signature is not the server's")
        ret
    }
    let (pkg_name, has_name) = package.value(pkg, "name")
    s.srv_name_len = copy_into(s.srv_name[0usize..], ui.text_of(a, pkg_name, pkg_name.len))
    ui.say("dynamic package verified ")
    ui.say_text(ui.text_of(a, s.srv_name[0usize..], s.srv_name_len))
    ui.say("\n")
    let made = vaultfs.mkdir("/apps")
    let path = package_path(a, ui.text_of(a, s.srv_name[0usize..], s.srv_name_len))
    if vaultfs.write_big(path, mem.address_of(&s.pkg[0usize]), s.pkg_len) {
        s.srv_kept = true
        ui.say("dynamic installed ")
        ui.say_text(path)
        ui.say("\n")
    } else {
        ui.say("dynamic install failed\n")
    }
    s.srv = 4usize
    s.screen = SERVED_SCREEN
}

// One tick of a make at the server: take what has arrived, act on the events it completes.
fn server_step(a: *mem.Arena, s: *State) -> bool {
    var changed = false
    var polls = 0usize
    var got_any = false
    // A package of hundreds of kilobytes comes in 2 KB polls: a tick takes many of them.
    var poll_limit = 8usize
    if s.srv == 2usize { poll_limit = 160usize }
    while polls < poll_limit && s.net.phase != httpstream.PH_DONE {
        let before = s.net.body_len
        let before_head = s.net.head_len
        let got = httpstream.pump(&s.net)
        if got == netproto.R_EMPTY {
            polls = poll_limit
        } else {
            polls += 1usize
            if s.net.body_len != before || s.net.head_len != before_head { got_any = true }
        }
    }
    if got_any { s.silent = 0usize } else { s.silent += 1usize }
    if s.srv == 2usize {
        // The package: the bytes land in s.pkg as they come; the stream's end is the package's.
        if s.net.phase != httpstream.PH_HEAD && s.net.status != 200usize && s.net.status != 0usize {
            server_fail(s, "The server has no such package")
            ret true
        }
        if s.net.phase == httpstream.PH_DONE {
            server_package_done(a, s)
            ret true
        }
        if s.silent > 120usize {
            server_fail(s, "The package took too long")
            ret true
        }
        ret got_any
    }
    // The stages: events until `done` or `failed`.
    if s.net.phase != httpstream.PH_HEAD && s.net.status != 200usize && s.net.status != 0usize {
        server_fail(s, "The server did not take the request")
        ret true
    }
    var more = s.net.body_len > s.sse_at
    var finished = false
    while more && !finished {
        let (event, next_at, whole, sse_error) = sse.next(a, s.body[0usize..s.net.body_len], s.sse_at)
        if sse_error != ok || !whole {
            more = false
        } else {
            s.sse_at = next_at
            if ui.same(event.kind, "stage") {
                s.srv_stage = jsonlite.number_of(event.data, "stage")
                s.srv_note_len = jsonlite.string_of(event.data, "note", s.srv_note[0usize..])
                changed = true
                ui.say("dynamic server stage ")
                ui.say_num(s.srv_stage)
                ui.say("\n")
            } else if ui.same(event.kind, "done") {
                s.srv_id_len = jsonlite.string_of(event.data, "id", s.srv_id[0usize..])
                s.srv_size = jsonlite.number_of(event.data, "size")
                s.srv_attempts = jsonlite.number_of(event.data, "attempts")
                s.srv_name_len = jsonlite.string_of(event.data, "name", s.srv_name[0usize..])
                ui.say("dynamic server done ")
                ui.say_text(ui.text_of(a, s.srv_name[0usize..], s.srv_name_len))
                ui.say(" ")
                ui.say_num(s.srv_size)
                ui.say("\n")
                finished = true
            } else if ui.same(event.kind, "failed") {
                var reason: [80]u8 = zero
                let n = jsonlite.string_of(event.data, "reason", reason[0usize..])
                server_fail(s, ui.text_of(a, reason[0usize..], n))
                ret true
            }
        }
    }
    if finished {
        // The package next, over a new request of its own, into the package buffer.
        httpstream.abort(&s.net)
        httpstream.begin(&s.net, mem.address_of(&s.pkg[0usize]), s.pkg.len)
        let path = ui.join(a, "/dynamic/package/", ui.text_of(a, s.srv_id[0usize..], s.srv_id_len), "")
        let result = httpstream.start(a, &s.net, "GET", "neper.test", path, "", "", 443u16, true)
        if result != netproto.R_OK {
            server_fail(s, "The package could not be fetched")
            ret true
        }
        s.srv = 2usize
        s.silent = 0usize
        ret true
    }
    if s.net.phase == httpstream.PH_DONE {
        server_fail(s, "The server stopped before the app was made")
        ret true
    }
    if s.silent > 240usize {
        server_fail(s, "The server took too long")
        ret true
    }
    ret changed
}

// (C173) Fetch the revocation list, check that the server signed it, and keep its text as /revoked for the shell.
fn fetch_revocations(a: *mem.Arena, s: *State) {
    let (reply, request_error) = httpc.get(a, "neper.test", "/dynamic/revoked", "")
    if request_error != ok || reply.status != 200usize {
        s.revoked_state = 2usize
        ui.say("dynamic revocations unreachable\n")
        ret
    }
    let (list, list_error) = package.check_list(reply.body, server_key.public())
    if list_error != ok {
        s.revoked_state = 3usize
        ui.say("dynamic revocations refused\n")
        ret
    }
    var entries = 0usize
    var i = 0usize
    while i < list.len {
        if list[i] == 10u8 { entries += 1usize }
        i += 1usize
    }
    if list.len > 0usize && list.len <= 512usize {
        if vaultfs.write("/revoked", mem.address_of(&list[0usize]), list.len) {
            ui.say("dynamic revocations kept\n")
        }
    }
    s.revoked_count = entries
    s.revoked_state = 1usize
    ui.say("dynamic revocations ")
    ui.say_num(entries)
    ui.say(" signed\n")
}

fn start_making(a: *mem.Arena, s: *State) {
    if s.prompt.len == 0usize { ret }
    let words = ui.field_text(a, &s.prompt)
    ui.say("dynamic prompt ")
    ui.say_text(words)
    ui.say("\n")
    // (C151) With a network the server makes it; without one the three templates do.
    if !s.extending && server_start(a, s) {
        s.ticks = 0usize
        s.screen = PROGRESS_SCREEN
        ui.say("dynamic server request\n")
        ret
    }
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
    persist(s)
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
    if s.screen == PROGRESS_SCREEN {
        if id == 460usize && s.srv == 3usize {
            s.srv = 0usize
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == SERVED_SCREEN {
        if id == 470usize {
            s.screen = SERVED_DETAILS_SCREEN
            ret true
        }
        if id == 471usize {
            s.srv = 0usize
            s.screen = HOME_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == SERVED_DETAILS_SCREEN {
        if id == 500usize {
            s.screen = SERVED_SCREEN
            ret true
        }
        ret false
    }
    // Home.
    if id == 111usize {
        fetch_revocations(a, s)
        ret true
    }
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
    // (C151) The stream's body and the package land in buffers that outlive the frames (taken before the kit's mark).
    let (body_store, body_error) = mem.alloc[u8](a, BODY_CAP)
    if body_error != ok {
        ui.say("dynamic open failed\n")
        ret ok
    }
    let (pkg_store, pkg_error) = mem.alloc[u8](a, PACKAGE_CAP)
    if pkg_error != ok {
        ui.say("dynamic open failed\n")
        ret ok
    }
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
    s.body = body_store
    s.pkg = pkg_store
    let first = add_app(&s, "Counter", COUNTER)
    restore(&s)
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
            // (C151) At the server the stages and the package arrive on the ticks.
            if s.screen == PROGRESS_SCREEN && (s.srv == 1usize || s.srv == 2usize) {
                if server_step(a, &s) {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else if s.screen == PROGRESS_SCREEN && s.srv == 0usize {
                // The stages follow the ticks: a stage takes a second.
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
