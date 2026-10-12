// AI (D2236): the app behind the AI icon, a chat with an AI model you bring the key for (bring your own key)
// -- a setup screen (the provider: Anthropic, OpenAI, Google or a local model; the model; the API key typed
// on the on-screen keyboard and shown as stars; Save), and the chat: your messages and the assistant's in
// bubbles, a message box on the keyboard, the reply arriving a little at a time, a button to change the
// provider or the key and one to start a new chat. Dark ground, cream bubbles for the assistant and amber
// for you, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on
// the bar at the bottom leaves the app.
// (C141) The replies are real: each message sends the conversation to the provider's API over HTTPS (httpc, the
// shape of Anthropic's, OpenAI's, Google's and the OpenAI-compatible local server's) with the key typed in setup,
// and the answer's text is read from the reply; a refused key, a rate limit, no network and the rest are said in
// plain words. The key stays in this process's memory, is never logged and is not kept. Left (C171): streaming,
// the key in Secure, conversations in storage, files, images and tools.
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
use httpc
use sysettings
use e.time

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
    // (C148) How much text the clipboard holds (0 when none): the Paste button shows when there is some.
    clip_len: usize,
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

// ----------------------------------------------------------------------------------------------
// The provider client (C141): one HTTPS request per message over httpc, the whole conversation as the body.

fn model_id(p: usize, m: usize) -> str {
    if p == 0usize {
        if m == 0usize { ret "claude-opus-5-5" }
        if m == 1usize { ret "claude-sonnet-5-5" }
        ret "claude-haiku-5-5"
    }
    if p == 1usize {
        if m == 0usize { ret "gpt-5" }
        if m == 1usize { ret "gpt-5-mini" }
        ret "gpt-5-nano"
    }
    if p == 2usize {
        if m == 0usize { ret "gemini-2.5-pro" }
        if m == 1usize { ret "gemini-2.5-flash" }
        ret "gemini-2.5-flash-lite"
    }
    if m == 0usize { ret "llama-7b" }
    if m == 1usize { ret "llama-3b" }
    ret "llama-1b"
}

// `piece` into `buf` at `at` as the inside of a JSON string; the new end.
fn put_escaped(buf: []u8, at: usize, piece: []const u8, length: usize) -> usize {
    var n = at
    var i = 0usize
    while i < length && n + 6usize < buf.len {
        let c = piece[i]
        if c == 34u8 || c == 92u8 {
            buf[n] = 92u8
            buf[n + 1usize] = c
            n += 2usize
        } else if c == 10u8 {
            buf[n] = 92u8
            buf[n + 1usize] = 110u8
            n += 2usize
        } else if c >= 32u8 {
            buf[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// The request body for the conversation so far, in the shape of the provider; the length.
fn build_body(s: *State, buf: []u8) -> usize {
    var n = 0usize
    let google = s.provider == 2usize
    if google {
        n = httpc.put(buf, n, "{\"contents\":[")
    } else {
        n = httpc.put(buf, n, "{\"model\":\"")
        n = httpc.put(buf, n, model_id(s.provider, s.model))
        if s.provider == 0usize { n = httpc.put(buf, n, "\",\"max_tokens\":1024,\"messages\":[") } else { n = httpc.put(buf, n, "\",\"messages\":[") }
    }
    var k = 0usize
    while k < s.msg_total {
        if k > 0usize { n = httpc.put(buf, n, ",") }
        var role = "assistant"
        if s.msgs[k].mine { role = "user" }
        if google {
            if !s.msgs[k].mine { role = "model" }
            n = httpc.put(buf, n, "{\"role\":\"")
            n = httpc.put(buf, n, role)
            n = httpc.put(buf, n, "\",\"parts\":[{\"text\":\"")
        } else {
            n = httpc.put(buf, n, "{\"role\":\"")
            n = httpc.put(buf, n, role)
            n = httpc.put(buf, n, "\",\"content\":\"")
        }
        n = put_escaped(buf, n, s.msgs[k].body[0usize..], s.msgs[k].body_len)
        if google { n = httpc.put(buf, n, "\"}]}") } else { n = httpc.put(buf, n, "\"}") }
        k += 1usize
    }
    n = httpc.put(buf, n, "]}")
    ret n
}

fn hex4(body: str, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize && at + i < body.len {
        let d = httpc.hex_digit(body[at + i])
        if d == 99usize { ret 0usize }
        v = v * 16usize + d
        i += 1usize
    }
    ret v
}

// Whether `body` holds `"key":` at `at`.
fn key_at(body: str, at: usize, key: str) -> bool {
    if at + key.len + 3usize > body.len { ret false }
    if body[at] != 34u8 || body[at + 1usize + key.len] != 34u8 || body[at + 2usize + key.len] != 58u8 { ret false }
    var i = 0usize
    while i < key.len {
        if body[at + 1usize + i] != key[i] { ret false }
        i += 1usize
    }
    ret true
}

// The first JSON string value of `key` in `body` into `out`; its length (0 when the key is absent).
fn extract_text(body: str, key: str, out: []u8) -> usize {
    var at = 0usize
    var found = false
    while at + key.len + 3usize < body.len && !found {
        var next = at + 1usize
        if key_at(body, at, key) {
            var v = at + 3usize + key.len
            while v < body.len && body[v] == 32u8 { v += 1usize }
            if v < body.len && body[v] == 34u8 {
                next = v + 1usize
                found = true
            }
        }
        at = next
    }
    if !found { ret 0usize }
    var n = 0usize
    var done = false
    while at < body.len && !done && n + 4usize < out.len {
        let c = body[at]
        if c == 34u8 {
            done = true
        } else if c == 92u8 && at + 1usize < body.len {
            let e = body[at + 1usize]
            at += 2usize
            if e == 110u8 {
                out[n] = 10u8
                n += 1usize
            } else if e == 116u8 {
                out[n] = 32u8
                n += 1usize
            } else if e == 117u8 && at + 4usize <= body.len {
                let cp = hex4(body, at)
                at += 4usize
                if cp < 128usize {
                    out[n] = u8(cp)
                    n += 1usize
                } else if cp < 2048usize {
                    out[n] = u8(192usize | (cp >> 6usize))
                    out[n + 1usize] = u8(128usize | (cp & 63usize))
                    n += 2usize
                } else {
                    out[n] = u8(224usize | (cp >> 12usize))
                    out[n + 1usize] = u8(128usize | ((cp >> 6usize) & 63usize))
                    out[n + 2usize] = u8(128usize | (cp & 63usize))
                    n += 3usize
                }
            } else {
                out[n] = e
                n += 1usize
            }
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret n
}

fn set_reply(s: *State, message: str) {
    var i = 0usize
    while i < message.len && i < 220usize {
        s.reply[i] = message[i]
        i += 1usize
    }
    s.reply_len = i
}

// Ask the provider for the next reply: its text into s.reply and true; or, when there is none, the plain-words
// reason there and false.
fn ask(a: *mem.Arena, s: *State) -> bool {
    let (buf, buf_error) = mem.alloc[u8](a, 8192usize)
    if buf_error != ok {
        set_reply(s, "I ran out of memory.")
        ret false
    }
    let body_len = build_body(s, buf)
    let body: str = buf[0usize..body_len]
    let key = ui.field_text(a, &s.key)
    var host = "neper.test"
    var path = "/v1/chat/completions"
    var extra = ""
    var reply_key = "content"
    if s.provider == 0usize {
        host = "api.anthropic.com"
        path = "/v1/messages"
        extra = ui.join(a, ui.join(a, "x-api-key: ", key, "\r\n"), "anthropic-version: 2023-06-01\r\n", "")
        reply_key = "text"
    } else if s.provider == 1usize {
        host = "api.openai.com"
        extra = ui.join(a, "Authorization: Bearer ", key, "\r\n")
    } else if s.provider == 2usize {
        host = "generativelanguage.googleapis.com"
        path = ui.join(a, ui.join(a, "/v1beta/models/", model_id(s.provider, s.model), ":generateContent?key="), key, "")
        reply_key = "text"
    } else if key.len > 0usize {
        extra = ui.join(a, "Authorization: Bearer ", key, "\r\n")
    }
    let (reply, request_error) = httpc.post(a, host, path, extra, body)
    if request_error == httpc.NoNetwork {
        set_reply(s, "There is no network, so I cannot reach the model.")
        ret false
    }
    if request_error == httpc.Unreachable {
        set_reply(s, ui.join(a, "I could not reach ", provider_name(s.provider), "."))
        ret false
    }
    if request_error == httpc.TlsFailed {
        set_reply(s, ui.join(a, "The secure connection to ", provider_name(s.provider), " failed."))
        ret false
    }
    if request_error != ok {
        set_reply(s, "The reply did not arrive whole.")
        ret false
    }
    if reply.status == 401usize || reply.status == 403usize {
        set_reply(s, "The provider refused the key. Check it in setup.")
        ret false
    }
    if reply.status == 429usize {
        set_reply(s, "The rate limit was reached. Try again in a moment.")
        ret false
    }
    if reply.status == 404usize {
        set_reply(s, "The provider does not know this model.")
        ret false
    }
    if reply.status != 200usize {
        set_reply(s, ui.join(a, "The provider answered with status ", ui.number(a, reply.status), "."))
        ret false
    }
    let n = extract_text(reply.body, reply_key, s.reply[0usize..])
    if n == 0usize {
        set_reply(s, "The reply held no text.")
        ret false
    }
    s.reply_len = n
    ret true
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
    try ui.put(a, builder, faces.grotesk, 11.0, "Your messages go to the provider you chose", 24.0, 60.0, ui.light_muted())
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
    if s.clip_len > 0usize { try ui.pill(a, builder, &s.hits, faces, 212usize, 16.0, box_y - 44.0, 96.0, 36.0, "Paste", ui.soft(), 14.0) }
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

// The wall-clock second now, 0 when there is no clock.
fn wall_seconds() -> usize {
    let (wall, wall_error) = time.now()
    if wall_error != ok || wall.nanos < 0i64 { ret 0usize }
    ret usize(wall.nanos / 1000000000i64)
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    var clip_bytes: [32]u8 = zero
    let (clip_length, clip_owner) = sysettings.clip_get(wall_seconds(), clip_bytes[0usize..])
    s.clip_len = clip_length
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
    let answered = ask(a, s)
    if answered {
        ui.say("ai text ")
        ui.say_text(ui.text_of(a, s.reply[0usize..], s.reply_len))
        ui.say("\n")
    } else {
        ui.say("ai failed ")
        ui.say_text(ui.text_of(a, s.reply[0usize..], s.reply_len))
        ui.say("\n")
    }
    // The answer is whole when the request returns, so it goes straight in as a bubble.
    add_msg(s, false, ui.text_of(a, s.reply[0usize..], s.reply_len))
    ui.say("ai sent\n")
    ui.say("ai reply\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == SETUP_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                s.key_saved = s.key.len > 0usize || s.provider == 3usize
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
            s.key_saved = s.key.len > 0usize || s.provider == 3usize
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
    if id == 212usize {
        var clip_bytes: [32]u8 = zero
        let (clip_length, clip_owner) = sysettings.clip_get(wall_seconds(), clip_bytes[0usize..])
        if clip_length == 0usize { ret true }
        let pasted = ui.field_paste(&s.draft, clip_bytes[0usize..], clip_length)
        s.typing = true
        ui.say("ai pasted ")
        ui.say_num(pasted)
        ui.say(" bytes\n")
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
        if id == 1206usize {
            // The keyboard's Paste key (C175).
            let before = s.draft.len
            let did = ui.field_key(&s.draft, id, true)
            ui.say("ai keyboard pasted ")
            ui.say_num(s.draft.len - before)
            ui.say(" bytes\n")
            ret did
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
