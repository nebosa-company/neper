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
const ACCOUNT_SCREEN: usize = 2usize

// (C164) `sid` is the server's number of the post (0 until it has told us) and `reply` the number of the post it answers
// (0 for none).
type Post = struct { who: usize, body: [100]u8, body_len: usize, minute: usize, thumbs: usize, mine_thumbs: bool, used: bool, delivered: bool, sid: usize, reply: usize }

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
    // (C164) The account: its name once the server accepted it (empty for the guest join), the post being answered
    // (an index in the open room, or NONE), the room's search (the text and whether the bar is open) and the
    // Account screen's two fields with the one in focus.
    account: [16]u8,
    account_len: usize,
    reply_to: usize,
    searching: bool,
    search_focus: bool,
    query: ui.Field,
    user: ui.Field,
    secret: ui.Field,
    account_focus: usize,
    account_note: [40]u8,
    account_note_len: usize,
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
    if who == 5usize { ret "Noor" }
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
    var buf: [1400]u8 = zero
    var n = 1usize
    buf[0] = u8(s.rooms[i].post_total) | 128u8
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
        buf[n + 6usize] = u8(p.sid & 255usize)
        buf[n + 7usize] = u8(p.sid >> 8usize)
        buf[n + 8usize] = u8(p.reply & 255usize)
        buf[n + 9usize] = u8(p.reply >> 8usize)
        n += 10usize
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
    var buf: [1400]u8 = zero
    let (n, found) = vaultfs.read_big(room_path(a, i), mem.address_of(&buf[0usize]), 1400usize)
    if !found || n < 1usize { ret 0usize }
    // (C164) Bit 7 of the count marks the layout with the server's id of the post and the id it replies to.
    let versioned = (buf[0] & 128u8) != 0u8
    let count = usize(buf[0] & 127u8)
    if count == 0usize || count > MAX_POSTS { ret 0usize }
    s.rooms[i].post_total = 0usize
    var at = 1usize
    var k = 0usize
    var header = 6usize
    if versioned { header = 10usize }
    while k < count && at + header <= n {
        var p: Post = zero
        p.who = usize(buf[at])
        p.minute = usize(buf[at + 1usize]) | (usize(buf[at + 2usize]) << 8usize)
        p.thumbs = usize(buf[at + 3usize])
        p.mine_thumbs = (buf[at + 4usize] & 1u8) != 0u8
        p.delivered = (buf[at + 4usize] & 2u8) != 0u8
        let length = usize(buf[at + 5usize])
        if versioned {
            p.sid = usize(buf[at + 6usize]) | (usize(buf[at + 7usize]) << 8usize)
            p.reply = usize(buf[at + 8usize]) | (usize(buf[at + 9usize]) << 8usize)
        }
        at += header
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

// Whether `needle` is in `hay`, ignoring case.
fn has_text(hay: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    var at = 0usize
    while at + needle.len <= hay.len {
        var same = true
        var i = 0usize
        while same && i < needle.len {
            var x = hay[at + i]
            var y = needle[i]
            if x >= 65u8 && x <= 90u8 { x = x + 32u8 }
            if y >= 65u8 && y <= 90u8 { y = y + 32u8 }
            if x != y { same = false }
            i += 1usize
        }
        if same { ret true }
        at += 1usize
    }
    ret false
}

// How many posts of the open room hold the search text.
fn count_matches(a: *mem.Arena, s: *State) -> usize {
    var n = 0usize
    let needle = ui.field_text(a, &s.query)
    var k = 0usize
    while k < s.rooms[s.open].post_total {
        let p = s.rooms[s.open].posts[k]
        if has_text(ui.text_of(a, p.body[0usize..], p.body_len), needle) { n += 1usize }
        k += 1usize
    }
    ret n
}

fn draw_account(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 26.0, "Account", 62.0, 16.0, ui.light())
    var who = "Not signed in: you join as a guest"
    if s.account_len > 0usize { who = ui.join(a, "Signed in as ", ui.text_of(a, s.account[0usize..], s.account_len), "") }
    try ui.put(a, builder, faces.grotesk, 12.0, who, 24.0, 56.0, ui.light_muted())
    try ui.put(a, builder, faces.grotesk, 12.0, "Name", 24.0, 90.0, ui.light_muted())
    var edge = ui.soft()
    if s.account_focus == 0usize { edge = ui.amber() }
    try ui.card(a, builder, 14.0, 108.0, 384.0, 48.0, 16.0, edge)
    try ui.card(a, builder, 16.0, 110.0, 380.0, 44.0, 14.0, ui.cream())
    try ui.put(a, builder, faces.jost, 18.0, ui.field_text(a, &s.user), 30.0, 120.0, ui.ink())
    ui.hit(&s.hits, 560usize, 14.0, 108.0, 384.0, 48.0)
    try ui.put(a, builder, faces.grotesk, 12.0, "Password", 24.0, 168.0, ui.light_muted())
    edge = ui.soft()
    if s.account_focus == 1usize { edge = ui.amber() }
    try ui.card(a, builder, 14.0, 186.0, 384.0, 48.0, 16.0, edge)
    try ui.card(a, builder, 16.0, 188.0, 380.0, 44.0, 14.0, ui.cream())
    var dots: [64]u8 = zero
    var d = 0usize
    while d < s.secret.len && d < 64usize {
        dots[d] = 42u8
        d += 1usize
    }
    try ui.put(a, builder, faces.jost, 18.0, ui.text_of(a, dots[0usize..], s.secret.len), 30.0, 198.0, ui.ink())
    ui.hit(&s.hits, 561usize, 14.0, 186.0, 384.0, 48.0)
    try ui.pill(a, builder, &s.hits, faces, 570usize, 16.0, 250.0, 150.0, 46.0, "Sign in", ui.amber(), 17.0)
    if s.account_note_len > 0usize { try ui.put(a, builder, faces.jost, 14.0, ui.text_of(a, s.account_note[0usize..], s.account_note_len), 24.0, 310.0, ui.light()) }
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Chat", 20.0, 20.0, ui.light())
    var team = "Neper team"
    if s.account_len > 0usize { team = ui.join(a, "Neper team, signed in as ", ui.text_of(a, s.account[0usize..], s.account_len), "") }
    try ui.put(a, builder, faces.grotesk, 12.0, team, 20.0, 62.0, ui.light_muted())
    // (C164) The Account screen: a name and a password the server checks.
    try ui.pill(a, builder, &s.hits, faces, 150usize, 300.0, 20.0, 96.0, 36.0, "Account", ui.soft(), 14.0)
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
    // (C164) Search: a bar under the header with the text and how many posts of this room hold it.
    try ui.pill(a, builder, &s.hits, faces, 530usize, 316.0, 18.0, 80.0, 32.0, "Search", ui.soft(), 13.0)
    var top: f32 = 84.0
    if s.searching {
        top = 124.0
        try ui.card(a, builder, 16.0, 70.0, 380.0, 40.0, 14.0, ui.amber())
        try ui.clipped(a, builder, faces.jost, 17.0, ui.field_text(a, &s.query), 30.0, 80.0, 250.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.number(a, count_matches(a, s)), " found", ""), 320.0, 84.0, ui.ink())
    }
    // The posts, newest at the bottom, as many as fit above the message box.
    var bottom: f32 = 770.0
    if s.typing { bottom = 440.0 }
    if s.reply_to != NONE { bottom = bottom - 26.0 }
    var y = bottom - 8.0
    var shown = 0usize
    var k = r.post_total
    var room_left = true
    while room_left && k > 0usize {
        k -= 1usize
        let p = r.posts[k]
        let body = ui.text_of(a, p.body[0usize..], p.body_len)
        // (C164) With a search open only the posts that hold it are shown.
        var wanted = true
        if s.searching && s.query.len > 0usize { wanted = has_text(body, ui.field_text(a, &s.query)) }
        if wanted {
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, body, 290.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        if placed_error == ok { h = placed.bounds.height }
        let total = h + 44.0
        y -= total
        if y < top {
            room_left = false
        } else {
            // (C164) A reply says which post it answers, beside the name and the time.
            if p.reply != 0usize {
                var label = "in reply"
                var q = 0usize
                while q < r.post_total {
                    if r.posts[q].sid == p.reply { label = ui.join(a, "in reply to ", person_name(r.posts[q].who), "") }
                    q += 1usize
                }
                try ui.put(a, builder, faces.grotesk, 11.0, label, 240.0, y + 7.0, ui.amber())
            }
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
            // (C164) A tap on the text answers that post.
            ui.hit(&s.hits, 400usize + k, 62.0, y, 278.0, total)
            shown += 1usize
        }
        }
    }
    // The message box.
    var box_y: f32 = 800.0
    if s.typing { box_y = 446.0 }
    if s.reply_to != NONE {
        var who_name = "a message"
        if s.reply_to < r.post_total { who_name = person_name(r.posts[s.reply_to].who) }
        try ui.card(a, builder, 16.0, box_y - 30.0, 322.0, 26.0, 13.0, ui.amber())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Replying to ", who_name, ""), 30.0, box_y - 25.0, ui.ink())
        try ui.pill(a, builder, &s.hits, faces, 540usize, 300.0, box_y - 30.0, 38.0, 26.0, "x", ui.soft(), 13.0)
    }
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
    if s.screen == LIST_SCREEN {
        try draw_list(a, builder, s, faces)
    } else if s.screen == ACCOUNT_SCREEN {
        try draw_account(a, builder, s, faces)
    } else {
        try draw_room(a, builder, s, faces)
    }
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

// The decimal number in `digits` (0 when it holds anything else).
fn number_of(digits: []const u8) -> usize {
    var v = 0usize
    var i = 0usize
    while i < digits.len && digits[i] >= 48u8 && digits[i] <= 57u8 {
        v = v * 10usize + usize(digits[i] - 48u8)
        i += 1usize
    }
    ret v
}

// The person a name from the server stands for: 0 is this account (or `neper`, the guest), the sample people have
// their own numbers, Noor 5, anyone else 4.
fn who_of(s: *State, name: []const u8) -> usize {
    if s.account_len > 0usize {
        if name.len == s.account_len {
            var same = true
            var k = 0usize
            while k < name.len {
                if name[k] != s.account[k] { same = false }
                k += 1usize
            }
            if same { ret 0usize }
        }
    } else if text_is(name, "neper") {
        ret 0usize
    }
    if text_is(name, "Maya") { ret 1usize }
    if text_is(name, "Alex") { ret 2usize }
    if text_is(name, "Priya") { ret 3usize }
    if text_is(name, "noor") { ret 5usize }
    ret 4usize
}

// One message from the server: MSG|room|who|text puts a post in the room (our own echo is skipped).
fn live_message(a: *mem.Arena, s: *State, payload: []const u8) -> bool {
    // (C164) The frames with more fields than the first three bars hold: AUTH, MID and REACT.
    var field_start: [8]usize = zero
    var field_end: [8]usize = zero
    var fields = 0usize
    var from = 0usize
    var at_byte = 0usize
    while at_byte <= payload.len && fields < 8usize {
        if at_byte == payload.len || payload[at_byte] == 124u8 {
            field_start[fields] = from
            field_end[fields] = at_byte
            fields += 1usize
            from = at_byte + 1usize
        }
        at_byte += 1usize
    }
    if fields >= 2usize && text_is(payload[field_start[0usize]..field_end[0usize]], "AUTH") {
        if text_is(payload[field_start[1usize]..field_end[1usize]], "ok") && fields >= 3usize {
            var n = 0usize
            while n < 16usize && field_start[2usize] + n < field_end[2usize] {
                s.account[n] = payload[field_start[2usize] + n]
                n += 1usize
            }
            s.account_len = n
            ui.say("chat signed in ")
            ui.say_text(ui.text_of(a, s.account[0usize..], s.account_len))
            ui.say("\n")
        } else {
            s.account_len = 0usize
            ui.say("chat sign-in refused\n")
        }
        ret true
    }
    if fields >= 5usize && text_is(payload[field_start[0usize]..field_end[0usize]], "MID") {
        let room = find_room(s, payload[field_start[1usize]..field_end[1usize]])
        if room == NONE { ret false }
        let ident = number_of(payload[field_start[2usize]..field_end[2usize]])
        let who = who_of(s, payload[field_start[3usize]..field_end[3usize]])
        let reply = number_of(payload[field_start[4usize]..field_end[4usize]])
        var k = s.rooms[room].post_total
        var tagged = false
        while k > 0usize && !tagged {
            k -= 1usize
            if s.rooms[room].posts[k].who == who && s.rooms[room].posts[k].sid == 0usize {
                s.rooms[room].posts[k].sid = ident
                s.rooms[room].posts[k].reply = reply
                tagged = true
            }
        }
        if tagged {
            save_room(a, s, room)
            ui.say("chat id ")
            ui.say_num(ident)
            ui.say("\n")
        }
        ret tagged
    }
    if fields >= 6usize && text_is(payload[field_start[0usize]..field_end[0usize]], "REACT") {
        let room = find_room(s, payload[field_start[1usize]..field_end[1usize]])
        if room == NONE { ret false }
        let ident = number_of(payload[field_start[2usize]..field_end[2usize]])
        let count = number_of(payload[field_start[5usize]..field_end[5usize]])
        var k = 0usize
        var found = false
        while k < s.rooms[room].post_total {
            if s.rooms[room].posts[k].sid == ident && ident != 0usize {
                s.rooms[room].posts[k].thumbs = count
                found = true
            }
            k += 1usize
        }
        if found {
            save_room(a, s, room)
            ui.say("chat reaction ")
            ui.say_text(ui.text_of(a, payload[field_start[3usize]..field_end[3usize]], field_end[3usize] - field_start[3usize]))
            ui.say(" ")
            ui.say_num(count)
            ui.say("\n")
        }
        ret found
    }
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
    let author = who_of(s, who_bytes)
    if author == 0usize {
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
    let who = author
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

// The account kept on the disk (/chat/account, "name:secret"): the two Account fields hold it.
fn load_account(s: *State) -> bool {
    var raw: [64]u8 = zero
    let (n, found) = vaultfs.read("/chat/account", mem.address_of(&raw[0usize]), 64usize)
    if !found || n < 3usize { ret false }
    var colon = n
    var i = 0usize
    while i < n {
        if raw[i] == 58u8 && colon == n { colon = i }
        i += 1usize
    }
    if colon == n || colon == 0usize || colon + 1usize >= n { ret false }
    s.user.len = 0usize
    s.secret.len = 0usize
    i = 0usize
    while i < colon && i < 16usize {
        ui.field_type(&s.user, raw[i], false)
        i += 1usize
    }
    i = colon + 1usize
    while i < n && raw[i] != 10u8 {
        ui.field_type(&s.secret, raw[i], false)
        i += 1usize
    }
    ret true
}

fn save_account(a: *mem.Arena, s: *State) -> bool {
    var raw: [64]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < s.user.len && n < 30usize {
        raw[n] = s.user.bytes[i]
        n += 1usize
        i += 1usize
    }
    raw[n] = 58u8
    n += 1usize
    i = 0usize
    while i < s.secret.len && n < 63usize {
        raw[n] = s.secret.bytes[i]
        n += 1usize
        i += 1usize
    }
    let made = vaultfs.mkdir("/chat")
    ret vaultfs.write("/chat/account", mem.address_of(&raw[0usize]), n)
}

// Connect to the chat server and join: as the account in the Account fields when there is one (JOIN|name|secret, which
// the server checks), else as the guest `neper`. wss first, the plain port when the secure link cannot be made.
fn live_open(a: *mem.Arena, s: *State) -> bool {
    var link = netclient.connect("neper.test", 8453u16, true)
    s.tls = link == netproto.R_OK
    if link != netproto.R_OK { link = netclient.connect("neper.test", 8090u16, false) }
    if link != netproto.R_OK { ret false }
    s.nb.pos = 0usize
    s.nb.len = 0usize
    s.nb.closed = false
    s.account_len = 0usize
    if !wsc.upgrade(&s.nb, "neper.test", "/chat") {
        let closed = netclient.close()
        ret false
    }
    s.live = true
    if s.user.len > 0usize && s.secret.len > 0usize {
        live_say(s, ui.join(a, ui.join(a, "JOIN|", ui.field_text(a, &s.user), ""), "|", ui.field_text(a, &s.secret)))
    } else {
        live_say(s, "JOIN|neper")
    }
    if s.tls { ui.say("chat live wss\n") } else { ui.say("chat live ws\n") }
    ret s.live
}

fn send(a: *mem.Arena, s: *State) {
    if s.draft.len == 0usize { ret }
    let body = ui.field_text(a, &s.draft)
    // (C164) An answer to a post the server numbered goes as SAYTO with that number, and says so in the post.
    var reply = 0usize
    if s.reply_to != NONE && s.reply_to < s.rooms[s.open].post_total { reply = s.rooms[s.open].posts[s.reply_to].sid }
    add_post(s, s.open, 0usize, body, s.now_minute, 0usize)
    s.rooms[s.open].posts[s.rooms[s.open].post_total - 1usize].reply = reply
    save_room(a, s, s.open)
    // A room the server knows (not a direct message) is said there too.
    if s.live && !s.rooms[s.open].direct {
        if reply != 0usize {
            live_say(s, ui.join(a, ui.join(a, ui.join(a, "SAYTO|", room_name(a, s, s.open), "|"), ui.number(a, reply), "|"), body, ""))
        } else {
            live_say(s, ui.join(a, ui.join(a, "SAY|", room_name(a, s, s.open), ""), "|", body))
        }
    }
    s.reply_to = NONE
    s.draft.len = 0usize
    ui.say("chat sent\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == ACCOUNT_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ui.say("chat back\n")
            ret true
        }
        if id == 560usize || id == 561usize {
            s.account_focus = id - 560usize
            ret true
        }
        var sign_in = id == 570usize
        if ui.is_key(id) {
            if id == 1205usize {
                if s.account_focus == 0usize {
                    s.account_focus = 1usize
                    ret true
                }
                sign_in = true
            } else {
                if s.account_focus == 0usize { ret ui.field_key(&s.user, id, false) }
                ret ui.field_key(&s.secret, id, false)
            }
        }
        if sign_in {
            if s.user.len == 0usize || s.secret.len == 0usize { ret false }
            if save_account(a, s) {
                ui.say("chat account saved ")
                ui.say_text(ui.field_text(a, &s.user))
                ui.say("\n")
            }
            // A new join: the old link is closed and the account's own is made.
            if s.live {
                let closed = netclient.close()
                s.live = false
            }
            let again = live_open(a, s)
            s.account_note_len = 0usize
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == ROOM_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            s.typing = false
            s.searching = false
            s.reply_to = NONE
            ui.say("chat back\n")
            ret true
        }
        if id == 510usize {
            s.typing = true
            s.search_focus = false
            ret true
        }
        if id == 520usize {
            send(a, s)
            ret true
        }
        // (C164) Search: the bar opens with the keyboard on it; the count of posts that hold the text is said.
        if id == 530usize {
            s.searching = !s.searching
            s.search_focus = s.searching
            s.typing = s.searching
            s.query.len = 0usize
            if s.searching { ui.say("chat search open\n") } else { ui.say("chat search closed\n") }
            ret true
        }
        if id == 540usize {
            s.reply_to = NONE
            ret true
        }
        if ui.is_key(id) {
            if s.searching && s.search_focus {
                if id == 1205usize {
                    ui.say("chat search ")
                    ui.say_num(count_matches(a, s))
                    ui.say("\n")
                    ret true
                }
                ret ui.field_key(&s.query, id, false)
            }
            if id == 1205usize {
                send(a, s)
                ret true
            }
            ret ui.field_key(&s.draft, id, true)
        }
        // (C164) A tap on a post's text answers it.
        if id >= 400usize && id < 400usize + MAX_POSTS {
            let at = id - 400usize
            if at < s.rooms[s.open].post_total {
                s.reply_to = at
                s.typing = true
                s.search_focus = false
                ui.say("chat replying to ")
                ui.say(person_name(s.rooms[s.open].posts[at].who))
                ui.say("\n")
                ret true
            }
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
                // (C164) A post the server numbered has its reactions kept there: the count comes back to everyone.
                if s.live && p.sid != 0usize && !s.rooms[s.open].direct {
                    live_say(s, ui.join(a, ui.join(a, ui.join(a, "REACT|", room_name(a, s, s.open), "|"), ui.number(a, p.sid), "|"), "+1", ""))
                }
                ui.say("chat reaction\n")
                ret true
            }
        }
        ret false
    }
    if id == 150usize {
        s.screen = ACCOUNT_SCREEN
        s.account_focus = 0usize
        s.account_note_len = 0usize
        ui.say("chat account screen\n")
        ret true
    }
    if id >= 100usize && id < 100usize + MAX_ROOMS {
        if id - 100usize < s.room_total {
            s.open = id - 100usize
            s.screen = ROOM_SCREEN
            s.rooms[s.open].unread = 0usize
            s.typing = false
            s.searching = false
            s.reply_to = NONE
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
    // (C164) The account kept on the disk, if there is one, signs in at the start.
    if load_account(&s) { ui.say("chat account loaded\n") }
    s.reply_to = NONE
    let joined = live_open(a, &s)
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
