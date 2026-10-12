// Chat (D2229): the app behind the Chat icon, a team chat after Slack and Google Chat -- a list of
// channels and direct messages with unread badges, a channel screen with messages from several people
// (an avatar, the name, the time, the text, reactions you can add with a tap), a message box that sends on
// the on-screen keyboard, and a members line. Dark ground, cream bubbles and amber, like the other apps
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves
// the app.
// ponytail: the rooms are SAMPLE data in this process (four channels and two direct messages, made-up
// people), and nobody else is on the other end: a message you send stays on this device. A real chat
// service (accounts, a server, presence, threads, files, calls) is queued as C134.
// (C134) The server is real: a WebSocket to the test chat server. (C164) It is reached over TLS (wss: the network
// server's poll now reads a TLS stream), the server says who is online and who is typing, a message you send is
// marked delivered when the server echoes it, and every room's messages are kept in /chat on the disk and come
// back at the next start. Left: accounts, threads, files, notifications and encryption.
use e.mem
use e.os
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
use netclient
use netproto
use netio
use wsc

const NONE: usize = 99usize
const MAX_ROOMS: usize = 6usize
const MAX_POSTS: usize = 12usize
const LIST_SCREEN: usize = 0usize
const ROOM_SCREEN: usize = 1usize

type Post = struct { who: usize, body: [100]u8, body_len: usize, minute: usize, thumbs: usize, mine_thumbs: bool, used: bool, delivered: bool }

type Room = struct { name: [20]u8, name_len: usize, direct: bool, posts: [12]Post, post_total: usize, unread: usize }

type State = struct {
    // (C134) The live connection: a WebSocket to the chat server, its buffered network reader, the memory it keeps
    // its state in (outside the per-frame arena), and the name of the last person who was not one of the sample ones.
    live: bool,
    nb: netio.NetBuf,
    other_name: [12]u8,
    other_len: usize,
    // (C164) Whether the link is TLS, who the server says is online (a bit per person: Maya 1, Alex 2, Priya 4) and
    // who is typing in which room (typer 0 when no one).
    tls: bool,
    online: usize,
    typer: usize,
    typer_room: usize,
    rooms: [6]Room,
    room_total: usize,
    screen: usize,
    open: usize,
    draft: ui.Field,
    typing: bool,
    now_minute: usize,
    hits: ui.Hits,
}

fn person_name(who: usize) -> str {
    if who == 0usize { ret "You" }
    if who == 1usize { ret "Maya" }
    if who == 2usize { ret "Alex" }
    if who == 3usize { ret "Priya" }
    ret "Sam"
}


fn add_room(s: *State, name: str, direct: bool, unread: usize) -> usize {
    if s.room_total >= MAX_ROOMS { ret NONE }
    var r: Room = zero
    var i = 0usize
    while i < name.len && i < 20usize {
        r.name[i] = name[i]
        i += 1usize
    }
    r.name_len = i
    r.direct = direct
    r.unread = unread
    s.rooms[s.room_total] = r
    s.room_total += 1usize
    ret s.room_total - 1usize
}

fn add_post(s: *State, room: usize, who: usize, body: str, minute: usize, thumbs: usize) {
    var r = &s.rooms[room]
    if r.post_total == MAX_POSTS {
        var k = 1usize
        while k < MAX_POSTS {
            r.posts[k - 1usize] = r.posts[k]
            k += 1usize
        }
        r.post_total -= 1usize
    }
    var p: Post = zero
    var i = 0usize
    while i < body.len && i < 100usize {
        p.body[i] = body[i]
        i += 1usize
    }
    p.body_len = i
    p.who = who
    p.minute = minute
    p.thumbs = thumbs
    p.used = true
    r.posts[r.post_total] = p
    r.post_total += 1usize
}

// ----------------------------------------------------------------------------------------------
// (C164) A room's messages on the disk, /chat/r<index>: the count, then each post as who, the minute (two bytes), the
// thumbs, the flags (1 mine-thumbs, 2 delivered), the length and the bytes. Only a room that has changed is written.

fn room_path(a: *mem.Arena, i: usize) -> str {
    ret ui.join(a, "/chat/r", ui.number(a, i), "")
}

fn save_room(a: *mem.Arena, s: *State, i: usize) {
    var buf: [1300]u8 = zero
    var n = 1usize
    buf[0] = u8(s.rooms[i].post_total)
    var k = 0usize
    while k < s.rooms[i].post_total {
        let p = s.rooms[i].posts[k]
        buf[n] = u8(p.who)
        buf[n + 1usize] = u8(p.minute & 255usize)
        buf[n + 2usize] = u8(p.minute >> 8usize)
        buf[n + 3usize] = u8(p.thumbs)
        var flags = 0u8
        if p.mine_thumbs { flags = flags | 1u8 }
        if p.delivered { flags = flags | 2u8 }
        buf[n + 4usize] = flags
        buf[n + 5usize] = u8(p.body_len)
        n += 6usize
        var b = 0usize
        while b < p.body_len {
            buf[n] = p.body[b]
            n += 1usize
            b += 1usize
        }
        k += 1usize
    }
    let made = vaultfs.mkdir("/chat")
    if vaultfs.write_big(room_path(a, i), mem.address_of(&buf[0usize]), n) {
        ui.say("chat kept ")
        ui.say_num(i)
        ui.say("\n")
    }
}

// The posts of room `i` from the disk, replacing the room's sample ones; how many came back (0 when none were kept).
fn load_room(a: *mem.Arena, s: *State, i: usize) -> usize {
    var buf: [1300]u8 = zero
    let (n, found) = vaultfs.read_big(room_path(a, i), mem.address_of(&buf[0usize]), 1300usize)
    if !found || n < 1usize { ret 0usize }
    let count = usize(buf[0])
    if count == 0usize || count > MAX_POSTS { ret 0usize }
    s.rooms[i].post_total = 0usize
    var at = 1usize
    var k = 0usize
    while k < count && at + 6usize <= n {
        var p: Post = zero
        p.who = usize(buf[at])
        p.minute = usize(buf[at + 1usize]) | (usize(buf[at + 2usize]) << 8usize)
        p.thumbs = usize(buf[at + 3usize])
        p.mine_thumbs = (buf[at + 4usize] & 1u8) != 0u8
        p.delivered = (buf[at + 4usize] & 2u8) != 0u8
        let length = usize(buf[at + 5usize])
        at += 6usize
        if length > 100usize || at + length > n { ret s.rooms[i].post_total }
        var b = 0usize
        while b < length {
            p.body[b] = buf[at + b]
            b += 1usize
        }
        p.body_len = length
        p.used = true
        at += length
        s.rooms[i].posts[s.rooms[i].post_total] = p
        s.rooms[i].post_total += 1usize
        k += 1usize
    }
    ret s.rooms[i].post_total
}

fn room_name(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.rooms[i].name[0usize..], s.rooms[i].name_len)
}

fn hash_name(a: *mem.Arena, s: *State, i: usize) -> str {
    if s.rooms[i].direct { ret room_name(a, s, i) }
    ret ui.join(a, "# ", room_name(a, s, i), "")
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn avatar(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, cx: f32, cy: f32, radius: f32, name: str, index: usize) -> err {
    try ui.disc(a, builder, cx, cy, radius, ui.tint(index))
    if name.len > 0usize {
        let (one, one_error) = mem.alloc[u8](a, 1usize)
        if one_error != ok { ret one_error }
        one[0usize] = name[0usize]
        try ui.centred(a, builder, faces.jost_bold, radius * 0.95, one[0usize..1usize], cx, cy - radius * 0.62, ui.ink())
    }
    ret ok
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Chat", 20.0, 20.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "Neper team", 20.0, 62.0, ui.light_muted())
    var i = 0usize
    while i < s.room_total {
        let r = s.rooms[i]
        let y: f32 = 92.0 + f32(i) * 74.0
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 68.0, 18.0, ui.cream())
        if r.direct {
            try avatar(a, builder, faces, 48.0, y + 36.0, 20.0, room_name(a, s, i), i)
            // (C164) A green dot on the avatar of a person the server says is online.
            var bit = 0usize
            if r.name_len == 4usize && r.name[0usize] == 77u8 { bit = 1usize }
            if r.name_len == 4usize && r.name[0usize] == 65u8 { bit = 2usize }
            if (s.online & bit) != 0usize && bit != 0usize { try ui.disc(a, builder, 63.0, y + 51.0, 6.0, paint.Color { red: 0.30, green: 0.78, blue: 0.46, alpha: 1.0 }) }
        } else {
            try ui.card(a, builder, 28.0, y + 16.0, 40.0, 40.0, 12.0, ui.tint(i))
            try ui.centred(a, builder, faces.jost_bold, 22.0, "#", 48.0, y + 22.0, ui.ink())
        }
        var face = faces.jost
        if r.unread > 0usize { face = faces.jost_bold }
        try ui.put(a, builder, face, 18.0, hash_name(a, s, i), 84.0, y + 10.0, ui.ink())
        var last = "No messages yet"
        if r.post_total > 0usize {
            let p = r.posts[r.post_total - 1usize]
            last = ui.join(a, ui.join(a, person_name(p.who), ": ", ui.text_of(a, p.body[0usize..], p.body_len)), "", "")
        }
        try ui.clipped(a, builder, faces.grotesk, 12.0, last, 84.0, y + 40.0, 250.0, ui.muted())
        if r.unread > 0usize {
            try ui.disc(a, builder, 372.0, y + 36.0, 12.0, ui.amber_dark())
            try ui.centred(a, builder, faces.jost_bold, 13.0, ui.number(a, r.unread), 372.0, y + 28.0, ui.cream())
        }
        ui.hit(&s.hits, 100usize + i, 16.0, y + 2.0, 380.0, 68.0)
        i += 1usize
    }
    ret ok
}

fn draw_room(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let r = s.rooms[s.open]
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 22.0, hash_name(a, s, s.open), 62.0, 16.0, ui.light())
    var members = "4 members"
    if r.direct { members = "Direct message" }
    // (C164) Who is typing here, when the server said so.
    if s.typer != 0usize && s.typer == 1usize && s.typer_room == s.open { members = "Maya is typing..." }
    if s.typer != 0usize && s.typer != 1usize && s.typer_room == s.open { members = ui.join(a, person_name(s.typer), " is typing...", "") }
    try ui.put(a, builder, faces.grotesk, 12.0, members, 62.0, 48.0, ui.light_muted())
    // The posts, newest at the bottom, as many as fit above the message box.
    var bottom: f32 = 770.0
    if s.typing { bottom = 440.0 }
    var y = bottom - 8.0
    var shown = 0usize
    var k = r.post_total
    var room_left = true
    while room_left && k > 0usize {
        k -= 1usize
        let p = r.posts[k]
        let body = ui.text_of(a, p.body[0usize..], p.body_len)
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, body, 290.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        if placed_error == ok { h = placed.bounds.height }
        let total = h + 44.0
        y -= total
        if y < 84.0 {
            room_left = false
        } else {
            try avatar(a, builder, faces, 36.0, y + 20.0, 16.0, person_name(p.who), p.who)
            try ui.put(a, builder, faces.jost_bold, 15.0, person_name(p.who), 62.0, y + 4.0, ui.light())
            try ui.put(a, builder, faces.grotesk, 11.0, ui.clock_text(a, p.minute), 62.0 + text.measure(a, faces.jost_bold, 15.0, person_name(p.who)) + 10.0, y + 7.0, ui.light_muted())
            let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, body, 62.0, y + 26.0, 290.0, 0u32, ui.light())
            if box_error != ok { ret box_error }
            // The reaction under the post: a thumbs-up with its count, amber when it is yours.
            var fill = paint.Color { red: 0.20, green: 0.21, blue: 0.24, alpha: 1.0 }
            if p.mine_thumbs { fill = ui.amber() }
            let chip_y = y + 26.0 + h + 2.0
            if p.thumbs > 0usize || p.mine_thumbs {
                try ui.card(a, builder, 62.0, chip_y, 52.0, 20.0, 10.0, fill)
                var tone = ui.light()
                if p.mine_thumbs { tone = ui.ink() }
                try ui.put(a, builder, faces.jost, 12.0, ui.join(a, "+1  ", ui.number(a, p.thumbs), ""), 70.0, chip_y + 3.0, tone)
            }
            if p.who == 0usize && p.delivered { try ui.put(a, builder, faces.grotesk, 10.0, "Delivered", 300.0, y + 28.0 + h, ui.light_muted()) }
            ui.hit(&s.hits, 300usize + k, 340.0, y, 60.0, total)
            shown += 1usize
        }
    }
    // The message box.
    var box_y: f32 = 800.0
    if s.typing { box_y = 446.0 }
    try ui.card(a, builder, 16.0, box_y, 322.0, 46.0, 23.0, ui.cream())
    if s.draft.len == 0usize { try ui.put(a, builder, faces.jost, 16.0, "Message", 34.0, box_y + 13.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 16.0, ui.field_text(a, &s.draft), 34.0, box_y + 13.0, 290.0, ui.ink()) }
    if s.typing { try ui.card(a, builder, 34.0 + text.measure(a, faces.jost, 16.0, ui.field_text(a, &s.draft)) + 2.0, box_y + 11.0, 2.0, 24.0, 1.0, ui.amber()) }
    ui.hit(&s.hits, 510usize, 16.0, box_y, 322.0, 46.0)
    var send_fill = ui.soft()
    if s.draft.len > 0usize { send_fill = ui.amber() }
    try ui.disc(a, builder, 368.0, box_y + 23.0, 24.0, send_fill)
    try ui.centred(a, builder, faces.jost_bold, 16.0, ">", 368.0, box_y + 13.0, ui.ink())
    ui.hit(&s.hits, 520usize, 340.0, box_y, 56.0, 46.0)
    if s.typing { try ui.keyboard(a, builder, &s.hits, faces, "Send") }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN { try draw_list(a, builder, s, faces) } else { try draw_room(a, builder, s, faces) }
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
// The server (C134): one WebSocket text frame a message, fields separated by |.

fn live_say(s: *State, line: str) {
    if !s.live { ret }
    if !wsc.send_text(line) { s.live = false }
}

// The index of room `name`, or NONE.
fn find_room(s: *State, name: []const u8) -> usize {
    var i = 0usize
    while i < s.room_total {
        let r = s.rooms[i]
        if r.name_len == name.len {
            var same = true
            var k = 0usize
            while k < name.len {
                if r.name[k] != name[k] { same = false }
                k += 1usize
            }
            if same { ret i }
        }
        i += 1usize
    }
    ret NONE
}

fn text_is(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// One message from the server: MSG|room|who|text puts a post in the room (our own echo is skipped).
fn live_message(a: *mem.Arena, s: *State, payload: []const u8) -> bool {
    // Split at the first three bars.
    var bars: [3]usize = zero
    var n = 0usize
    var i = 0usize
    while i < payload.len && n < 3usize {
        if payload[i] == 124u8 {
            bars[n] = i
            n += 1usize
        }
        i += 1usize
    }
    // (C164) PRESENCE|who|online (or offline) and TYPING|room|who.
    if n >= 2usize && text_is(payload[0usize..bars[0usize]], "PRESENCE") {
        let who_bytes = payload[bars[0usize] + 1usize..bars[1usize]]
        let state_bytes = payload[bars[1usize] + 1usize..payload.len]
        var bit = 0usize
        if text_is(who_bytes, "Maya") { bit = 1usize }
        if text_is(who_bytes, "Alex") { bit = 2usize }
        if text_is(who_bytes, "Priya") { bit = 4usize }
        if text_is(state_bytes, "online") { s.online = s.online | bit } else { s.online = s.online & (7usize - bit) }
        ui.say("chat presence ")
        ui.say_text(ui.text_of(a, who_bytes, who_bytes.len))
        ui.say(" ")
        ui.say_text(ui.text_of(a, state_bytes, state_bytes.len))
        ui.say("\n")
        ret true
    }
    if n >= 2usize && text_is(payload[0usize..bars[0usize]], "TYPING") {
        let room_bytes = payload[bars[0usize] + 1usize..bars[1usize]]
        let who_bytes = payload[bars[1usize] + 1usize..payload.len]
        var typer = 4usize
        if text_is(who_bytes, "Maya") { typer = 1usize }
        if text_is(who_bytes, "Alex") { typer = 2usize }
        if text_is(who_bytes, "Priya") { typer = 3usize }
        s.typer = typer
        s.typer_room = find_room(s, room_bytes)
        ui.say("chat typing ")
        ui.say_text(ui.text_of(a, who_bytes, who_bytes.len))
        ui.say("\n")
        ret true
    }
    if n < 3usize || !text_is(payload[0usize..bars[0usize]], "MSG") { ret false }
    let room_name_bytes = payload[bars[0usize] + 1usize..bars[1usize]]
    let who_bytes = payload[bars[1usize] + 1usize..bars[2usize]]
    let body_bytes = payload[bars[2usize] + 1usize..payload.len]
    let room = find_room(s, room_name_bytes)
    if room == NONE { ret false }
    if text_is(who_bytes, "neper") {
        // (C164) The server's echo of our own message: the newest one not yet marked is delivered.
        var k = s.rooms[room].post_total
        var marked = false
        while k > 0usize && !marked {
            k -= 1usize
            if s.rooms[room].posts[k].who == 0usize && !s.rooms[room].posts[k].delivered {
                s.rooms[room].posts[k].delivered = true
                marked = true
            }
        }
        if marked {
            save_room(a, s, room)
            ui.say("chat delivered\n")
        }
        ret marked
    }
    var who = 4usize
    if text_is(who_bytes, "Maya") { who = 1usize }
    if text_is(who_bytes, "Alex") { who = 2usize }
    if text_is(who_bytes, "Priya") { who = 3usize }
    if s.typer == who { s.typer = 0usize }
    add_post(s, room, who, ui.text_of(a, body_bytes, body_bytes.len), s.now_minute, 0usize)
    save_room(a, s, room)
    if !(s.screen == ROOM_SCREEN && s.open == room) { s.rooms[room].unread += 1usize }
    ui.say("chat received ")
    ui.say_text(ui.text_of(a, who_bytes, who_bytes.len))
    ui.say(" ")
    ui.say_text(ui.text_of(a, body_bytes, body_bytes.len))
    ui.say("\n")
    ret true
}

// What the server has sent since last time: true when a post was added.
fn live_poll(a: *mem.Arena, s: *State) -> bool {
    if !s.live { ret false }
    var changed = false
    let have = netio.poll(&s.nb)
    if have == 0usize {
        if s.nb.closed {
            s.live = false
            ui.say("chat live closed\n")
        }
        ret false
    }
    var guard = 0usize
    var payload: [256]u8 = zero
    while s.nb.pos < s.nb.len && guard < 16usize {
        let (opcode, n, received) = wsc.receive(&s.nb, payload[0usize..256usize])
        if !received {
            s.live = false
            ret changed
        }
        if opcode == 1u8 {
            if live_message(a, s, payload[0usize..n]) { changed = true }
        }
        guard += 1usize
    }
    ret changed
}

// Connect to the chat server and join as `neper`. Plain text only: the network server polls plain connections for
// what has arrived, and a TLS stream it can only read by waiting (a poll over TLS is a later step).
fn live_open(s: *State) -> bool {
    // (C164) TLS first (wss, the test server's 8453, which the poll over TLS makes usable); the plain port is the
    // way back when the secure link cannot be made.
    var link = netclient.connect("neper.test", 8453u16, true)
    s.tls = link == netproto.R_OK
    if link != netproto.R_OK { link = netclient.connect("neper.test", 8090u16, false) }
    if link != netproto.R_OK { ret false }
    s.nb.pos = 0usize
    s.nb.len = 0usize
    s.nb.closed = false
    if !wsc.upgrade(&s.nb, "neper.test", "/chat") {
        let closed = netclient.close()
        ret false
    }
    s.live = true
    live_say(s, "JOIN|neper")
    if s.tls { ui.say("chat live wss\n") } else { ui.say("chat live ws\n") }
    ret s.live
}

fn send(a: *mem.Arena, s: *State) {
    if s.draft.len == 0usize { ret }
    let body = ui.field_text(a, &s.draft)
    add_post(s, s.open, 0usize, body, s.now_minute, 0usize)
    save_room(a, s, s.open)
    // A room the server knows (not a direct message) is said there too.
    if s.live && !s.rooms[s.open].direct {
        live_say(s, ui.join(a, ui.join(a, "SAY|", room_name(a, s, s.open), ""), "|", body))
    }
    s.draft.len = 0usize
    ui.say("chat sent\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == ROOM_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            s.typing = false
            ui.say("chat back\n")
            ret true
        }
        if id == 510usize {
            s.typing = true
            ret true
        }
        if id == 520usize {
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
        if id >= 300usize && id < 300usize + MAX_POSTS {
            let at = id - 300usize
            if at < s.rooms[s.open].post_total {
                var p = &s.rooms[s.open].posts[at]
                if p.mine_thumbs {
                    p.mine_thumbs = false
                    if p.thumbs > 0usize { p.thumbs -= 1usize }
                } else {
                    p.mine_thumbs = true
                    p.thumbs += 1usize
                }
                ui.say("chat reaction\n")
                ret true
            }
        }
        ret false
    }
    if id >= 100usize && id < 100usize + MAX_ROOMS {
        if id - 100usize < s.room_total {
            s.open = id - 100usize
            s.screen = ROOM_SCREEN
            s.rooms[s.open].unread = 0usize
            s.typing = false
            ui.say("chat opened ")
            ui.say_text(room_name(a, s, s.open))
            ui.say("\n")
            ret true
        }
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "chat")
    if kit_error != ok {
        ui.say("chat open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("chat fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    s.now_minute = 10usize * 60usize + 45usize
    let general = add_room(&s, "general", false, 3usize)
    add_post(&s, general, 1usize, "Morning everyone! The build is green again.", 9usize * 60usize + 12usize, 3usize)
    add_post(&s, general, 2usize, "Nice. I merged the storage server branch.", 9usize * 60usize + 20usize, 1usize)
    add_post(&s, general, 3usize, "Lunch at 12:30? The new place near the library.", 10usize * 60usize + 30usize, 0usize)
    let design = add_room(&s, "design", false, 0usize)
    add_post(&s, design, 3usize, "New icons are in. The brain one finally has a stem.", 8usize * 60usize + 50usize, 4usize)
    add_post(&s, design, 1usize, "Love the footprints for Steps.", 8usize * 60usize + 55usize, 2usize)
    let build = add_room(&s, "builds", false, 1usize)
    add_post(&s, build, 2usize, "Nightly passed all 42 fixtures.", 7usize * 60usize + 5usize, 5usize)
    let ideas = add_room(&s, "ideas", false, 0usize)
    add_post(&s, ideas, 4usize, "What about an app that writes apps from a prompt?", 6usize * 60usize + 40usize, 9usize)
    let maya = add_room(&s, "Maya", true, 1usize)
    add_post(&s, maya, 1usize, "Are you coming on Friday?", 10usize * 60usize + 41usize, 0usize)
    let alex = add_room(&s, "Alex", true, 0usize)
    add_post(&s, alex, 0usize, "Thanks for the review!", 9usize * 60usize + 2usize, 0usize)
    add_post(&s, alex, 2usize, "Anytime.", 9usize * 60usize + 3usize, 0usize)
    // (C164) What was kept on the disk replaces the sample messages of each room.
    var restored = 0usize
    var room_at = 0usize
    while room_at < s.room_total {
        restored += load_room(a, &s, room_at)
        room_at += 1usize
    }
    if restored > 0usize {
        ui.say("chat history restored ")
        ui.say_num(restored)
        ui.say("\n")
    }
    let joined = live_open(&s)
    if !show(a, &kit, &s) {
        ui.say("chat present failed\n")
        ret ok
    }
    ui.say("chat shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // Messages that arrived since the last tick.
            if live_poll(a, &s) {
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("chat home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("chat present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
