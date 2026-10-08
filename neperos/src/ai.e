// AI (D2236): the app behind the AI icon, a chat with an AI model you bring the key for (bring your own key)
// -- a setup screen (the provider: Anthropic, OpenAI, Google or a local model; the model; the API key typed
// on the on-screen keyboard and shown as stars; Save), and the chat: your messages and the assistant's in
// bubbles, a message box on the keyboard, the reply arriving a little at a time, a button to change the
// provider or the key and one to start a new chat. Dark ground, cream bubbles for the assistant and amber
// for you, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on
// the bar at the bottom leaves the app.
// ponytail: there is no network, so nothing is sent to a provider: the replies are CANNED (a few keywords
// get a fixed answer, anything else is echoed with a note), the key stays in this process, in memory, and
// is not checked. A real client (HTTPS to the provider's API with the key, streaming the reply, the key
// kept in Secure, conversations kept in storage, tools and files) is queued as C141.
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
const MAX_MSGS: usize = 12usize
const SETUP_SCREEN: usize = 0usize
const CHAT_SCREEN: usize = 1usize

type Msg = struct { mine: bool, body: [220]u8, body_len: usize }

type State = struct {
    msgs: [12]Msg,
    msg_total: usize,
    screen: usize,
    provider: usize,
    model: usize,
    key: ui.Field,
    key_saved: bool,
    draft: ui.Field,
    typing: bool,
    // The reply being written: the whole text, how much of it shows.
    reply: [220]u8,
    reply_len: usize,
    reply_shown: usize,
    replying: bool,
    hits: ui.Hits,
}

fn provider_name(p: usize) -> str {
    if p == 0usize { ret "Anthropic" }
    if p == 1usize { ret "OpenAI" }
    if p == 2usize { ret "Google" }
    ret "Local model"
}

fn model_name(p: usize, m: usize) -> str {
    if p == 0usize {
        if m == 0usize { ret "opus" }
        if m == 1usize { ret "sonnet" }
        ret "haiku"
    }
    if p == 1usize {
        if m == 0usize { ret "large" }
        if m == 1usize { ret "small" }
        ret "mini"
    }
    if p == 2usize {
        if m == 0usize { ret "pro" }
        if m == 1usize { ret "flash" }
        ret "nano"
    }
    if m == 0usize { ret "7b" }
    if m == 1usize { ret "3b" }
    ret "1b"
}

fn add_msg(s: *State, mine: bool, body: str) {
    if s.msg_total == MAX_MSGS {
        var k = 1usize
        while k < MAX_MSGS {
            s.msgs[k - 1usize] = s.msgs[k]
            k += 1usize
        }
        s.msg_total -= 1usize
    }
    var m: Msg = zero
    var i = 0usize
    while i < body.len && i < 220usize {
        m.body[i] = body[i]
        i += 1usize
    }
    m.body_len = i
    m.mine = mine
    s.msgs[s.msg_total] = m
    s.msg_total += 1usize
}

// Does `hay` contain `needle`, ignoring case?
fn contains(a: *mem.Arena, hay: str, needle: str) -> bool {
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

// The canned answer to `message`.
fn answer(a: *mem.Arena, s: *State, message: str) -> str {
    if contains(a, message, "haiku") { ret "Craters in the dusk / amber light on quiet screens / small apps, one by one." }
    if contains(a, message, "neper") { ret "Neper is a compiled systems language with its own toolchain, libraries and operating system. This phone runs on it." }
    if contains(a, message, "weather") { ret "I cannot see the weather without a network, but the Weather app has a sample forecast." }
    if contains(a, message, "help") { ret "Try asking about Neper, or ask me for a haiku. I am a demo until the network exists." }
    if contains(a, message, "hello") || contains(a, message, "hi") { ret "Hello! I am a demo assistant. There is no network yet, so my answers are canned." }
    ret ui.join(a, ui.join(a, "I heard: \"", message, "\". With a real key and a network I would send this to "), provider_name(s.provider), " and answer for real.")
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn star_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M12 2c1 6 4 9 10 10-6 1-9 4-10 10-1-6-4-9-10-10 6-1 9-4 10-10z' fill='currentColor'/></svg>"
}

fn masked(a: *mem.Arena, count: usize) -> str {
    var out = ""
    var i = 0usize
    while i < count && i < 30usize {
        out = ui.join(a, out, "*", "")
        i += 1usize
    }
    ret out
}

fn draw_setup(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Set up AI", 24.0, 10.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "Bring your own key: it stays on this device", 24.0, 48.0, ui.light_muted())
    var p = 0usize
    while p < 4usize {
        var fill = ui.soft()
        if p == s.provider { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + p, 16.0 + f32(p % 2usize) * 196.0, 76.0 + f32(p / 2usize) * 48.0, 184.0, 40.0, provider_name(p), fill, 16.0)
        p += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Model", 24.0, 184.0, ui.light_muted())
    var m = 0usize
    while m < 3usize {
        var fill = ui.soft()
        if m == s.model { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 110usize + m, 16.0 + f32(m) * 130.0, 204.0, 120.0, 36.0, model_name(s.provider, m), fill, 15.0)
        m += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "API key", 24.0, 260.0, ui.light_muted())
    try ui.card(a, builder, 14.0, 278.0, 384.0, 48.0, 16.0, ui.amber())
    try ui.card(a, builder, 16.0, 280.0, 380.0, 44.0, 14.0, ui.cream())
    if s.key.len == 0usize { try ui.put(a, builder, faces.jost, 17.0, "Paste or type your key", 30.0, 291.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 18.0, masked(a, s.key.len), 30.0, 290.0, 340.0, ui.ink()) }
    try ui.pill(a, builder, &s.hits, faces, 120usize, 16.0, 346.0, 186.0, 46.0, "Save key", ui.amber(), 17.0)
    var other = "Skip for now"
    if s.key_saved { other = "Back to chat" }
    try ui.pill(a, builder, &s.hits, faces, 121usize, 210.0, 346.0, 186.0, 46.0, other, ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Save")
    ret ok
}

fn draw_chat(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, star_icon(), geometry.rect(20.0, 22.0, 26.0, 26.0), ui.amber())
    try ui.put(a, builder, faces.jost_bold, 24.0, "AI", 56.0, 18.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 200usize, 160.0, 18.0, 160.0, 34.0, ui.join(a, ui.join(a, provider_name(s.provider), " ", ""), model_name(s.provider, s.model), ""), ui.soft(), 13.0)
    try ui.pill(a, builder, &s.hits, faces, 201usize, 328.0, 18.0, 68.0, 34.0, "New", ui.soft(), 13.0)
    try ui.put(a, builder, faces.grotesk, 11.0, "Demo: no network, replies are canned", 24.0, 60.0, ui.light_muted())
    // The messages from the bottom up.
    var bottom: f32 = 780.0
    if s.typing { bottom = 440.0 }
    var y = bottom
    var shown = 0usize
    var k = s.msg_total
    var room = true
    // The reply being written is the last bubble.
    if s.replying {
        let part = ui.text_of(a, s.reply[0usize..], s.reply_shown)
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, part, 270.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        if placed_error == ok { h = placed.bounds.height }
        y -= h + 24.0
        try ui.card(a, builder, 16.0, y, 300.0, h + 18.0, 16.0, ui.cream())
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, part, 30.0, y + 9.0, 270.0, 0u32, ui.ink())
        if box_error != ok { ret box_error }
        y -= 8.0
    }
    while room && k > 0usize {
        k -= 1usize
        let m = s.msgs[k]
        let body = ui.text_of(a, m.body[0usize..], m.body_len)
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, body, 270.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        var w: f32 = 270.0
        if placed_error == ok {
            h = placed.bounds.height
            w = placed.bounds.width
        }
        y -= h + 24.0
        if y < 84.0 {
            room = false
        } else {
            if m.mine {
                try ui.card(a, builder, 396.0 - w - 28.0, y, w + 28.0, h + 18.0, 16.0, ui.amber())
                let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, body, 396.0 - w - 14.0, y + 9.0, 270.0, 0u32, ui.ink())
                if box_error != ok { ret box_error }
            } else {
                try ui.card(a, builder, 16.0, y, 300.0, h + 18.0, 16.0, ui.cream())
                let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, body, 30.0, y + 9.0, 270.0, 0u32, ui.ink())
                if box_error != ok { ret box_error }
            }
            y -= 8.0
            shown += 1usize
        }
    }
    if s.msg_total == 0usize && !s.replying { try ui.centred(a, builder, faces.jost, 18.0, "Ask me anything", 206.0, 260.0, ui.light_muted()) }
    var box_y: f32 = 800.0
    if s.typing { box_y = 446.0 }
    try ui.card(a, builder, 16.0, box_y, 322.0, 46.0, 23.0, ui.cream())
    if s.draft.len == 0usize { try ui.put(a, builder, faces.jost, 16.0, "Message", 34.0, box_y + 13.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 16.0, ui.field_text(a, &s.draft), 34.0, box_y + 13.0, 290.0, ui.ink()) }
    ui.hit(&s.hits, 210usize, 16.0, box_y, 322.0, 46.0)
    var send_fill = ui.soft()
    if s.draft.len > 0usize { send_fill = ui.amber() }
    try ui.disc(a, builder, 368.0, box_y + 23.0, 24.0, send_fill)
    try ui.centred(a, builder, faces.jost_bold, 16.0, ">", 368.0, box_y + 13.0, ui.ink())
    ui.hit(&s.hits, 211usize, 340.0, box_y, 56.0, 46.0)
    if s.typing { try ui.keyboard(a, builder, &s.hits, faces, "Send") }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == SETUP_SCREEN { try draw_setup(a, builder, s, faces) } else { try draw_chat(a, builder, s, faces) }
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

fn send(a: *mem.Arena, s: *State) {
    if s.draft.len == 0usize || s.replying { ret }
    let message = ui.field_text(a, &s.draft)
    add_msg(s, true, message)
    s.draft.len = 0usize
    let text_out = answer(a, s, message)
    var i = 0usize
    while i < text_out.len && i < 220usize {
        s.reply[i] = text_out[i]
        i += 1usize
    }
    s.reply_len = i
    s.reply_shown = 0usize
    s.replying = true
    ui.say("ai sent\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == SETUP_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                s.key_saved = s.key.len > 0usize
                if s.key_saved {
                    s.screen = CHAT_SCREEN
                    ui.say("ai key saved\n")
                }
                ret true
            }
            ret ui.field_key(&s.key, id, false)
        }
        if id >= 100usize && id < 104usize {
            s.provider = id - 100usize
            s.model = 0usize
            ui.say("ai provider ")
            ui.say(provider_name(s.provider))
            ui.say("\n")
            ret true
        }
        if id >= 110usize && id < 113usize {
            s.model = id - 110usize
            ret true
        }
        if id == 120usize {
            s.key_saved = s.key.len > 0usize
            if s.key_saved {
                s.screen = CHAT_SCREEN
                ui.say("ai key saved\n")
            }
            ret true
        }
        if id == 121usize {
            s.screen = CHAT_SCREEN
            ret true
        }
        ret false
    }
    if id == 200usize {
        s.screen = SETUP_SCREEN
        ret true
    }
    if id == 201usize {
        s.msg_total = 0usize
        s.replying = false
        ui.say("ai new chat\n")
        ret true
    }
    if id == 210usize {
        s.typing = true
        ret true
    }
    if id == 211usize {
        send(a, s)
        ret true
    }
    if ui.is_key(id) {
        if id == 1205usize {
            send(a, s)
            ret true
        }
        ret ui.field_key(&s.draft, id, true)
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "ai")
    if kit_error != ok {
        ui.say("ai open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("ai fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.screen = SETUP_SCREEN
    if !show(a, &kit, &s) {
        ui.say("ai present failed\n")
        ret ok
    }
    ui.say("ai shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The reply arrives a few letters at a time.
            if s.replying {
                s.reply_shown += 14usize
                if s.reply_shown >= s.reply_len {
                    s.reply_shown = s.reply_len
                    add_msg(&s, false, ui.text_of(a, s.reply[0usize..], s.reply_len))
                    s.replying = false
                    ui.say("ai reply\n")
                }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("ai home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("ai present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
