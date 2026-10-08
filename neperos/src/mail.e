// Mail (D2223): the app behind the Mail icon, after Gmail -- folder chips (Inbox, Starred, Sent, Trash),
// messages as rows (a round initial, the sender, the subject in bold while unread, the first words, how
// long ago, a star), a message screen (subject, sender, the body, Reply, star, delete), and a compose
// screen (To, Subject and the message on the on-screen keyboard; Send puts it in Sent). Dark ground, cream
// rows and amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]).
// A tap on the bar at the bottom leaves the app.
// ponytail: the mailbox is SAMPLE data in this process (eight messages, made-up senders), a sent message
// goes only to the Sent folder, and nothing leaves the device -- there is no network yet. A real mail
// client (IMAP and SMTP over TLS, accounts, attachments, search, notifications) is queued as C128.
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
const MAX_MAILS: usize = 20usize
const LIST_SCREEN: usize = 0usize
const VIEW_SCREEN: usize = 1usize
const COMPOSE_SCREEN: usize = 2usize
const INBOX: usize = 0usize
const STARRED: usize = 1usize
const SENT: usize = 2usize
const TRASH: usize = 3usize

type Mail = struct {
    from: [20]u8,
    from_len: usize,
    subject: [40]u8,
    subject_len: usize,
    body: [160]u8,
    body_len: usize,
    folder: usize,
    unread: bool,
    starred: bool,
    ago: usize,
    used: bool,
}

type State = struct {
    mails: [20]Mail,
    folder: usize,
    screen: usize,
    open: usize,
    list: [20]usize,
    list_total: usize,
    // The compose screen: To, Subject, the message, and the field in focus.
    to: ui.Field,
    subject: ui.Field,
    message: ui.Field,
    focus: usize,
    hits: ui.Hits,
}

fn add_mail(s: *State, from: str, subject: str, body: str, folder: usize, unread: bool, ago: usize) -> usize {
    var i = 0usize
    while i < MAX_MAILS {
        if !s.mails[i].used {
            var m: Mail = zero
            var k = 0usize
            while k < from.len && k < 20usize {
                m.from[k] = from[k]
                k += 1usize
            }
            m.from_len = k
            k = 0usize
            while k < subject.len && k < 40usize {
                m.subject[k] = subject[k]
                k += 1usize
            }
            m.subject_len = k
            k = 0usize
            while k < body.len && k < 160usize {
                m.body[k] = body[k]
                k += 1usize
            }
            m.body_len = k
            m.folder = folder
            m.unread = unread
            m.ago = ago
            m.used = true
            s.mails[i] = m
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn from_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.mails[i].from[0usize..], s.mails[i].from_len)
}

fn subject_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.mails[i].subject[0usize..], s.mails[i].subject_len)
}

fn body_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.mails[i].body[0usize..], s.mails[i].body_len)
}

fn folder_name(folder: usize) -> str {
    if folder == INBOX { ret "Inbox" }
    if folder == STARRED { ret "Starred" }
    if folder == SENT { ret "Sent" }
    ret "Trash"
}

// The messages of the folder shown, newest first.
fn build_list(s: *State) {
    s.list_total = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        let m = s.mails[i]
        if m.used {
            var keep = false
            if s.folder == STARRED { keep = m.starred && m.folder != TRASH } else { keep = m.folder == s.folder }
            if keep {
                var at = s.list_total
                s.list_total += 1usize
                while at > 0usize && s.mails[s.list[at - 1usize]].ago > m.ago {
                    s.list[at] = s.list[at - 1usize]
                    at -= 1usize
                }
                s.list[at] = i
            }
        }
        i += 1usize
    }
}

fn unread_count(s: *State) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        if s.mails[i].used && s.mails[i].folder == INBOX && s.mails[i].unread { n += 1usize }
        i += 1usize
    }
    ret n
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn star_icon(filled: bool) -> str {
    if filled { ret "<svg viewBox='0 0 24 24'><path d='M12 2.8l2.8 6 6.5.8-4.8 4.5 1.3 6.5L12 17.4l-5.8 3.2 1.3-6.5L2.7 9.6l6.5-.8z' fill='currentColor' stroke='currentColor' stroke-width='1.6' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M12 2.8l2.8 6 6.5.8-4.8 4.5 1.3 6.5L12 17.4l-5.8 3.2 1.3-6.5L2.7 9.6l6.5-.8z' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linejoin='round'/></svg>"
}

fn trash_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13M10 11v6M14 11v6' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn pencil_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M4 20l1-5L16 4l4 4L9 19zM14 6l4 4' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

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
    build_list(s)
    try ui.put(a, builder, faces.jost_bold, 30.0, "Mail", 20.0, 20.0, ui.light())
    if unread_count(s) > 0usize { try ui.put_right(a, builder, faces.grotesk, 13.0, ui.join(a, ui.number(a, unread_count(s)), " unread", ""), 392.0, 34.0, ui.light_muted()) }
    var chip = 0usize
    while chip < 4usize {
        var fill = ui.soft()
        if chip == s.folder { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + chip, 16.0 + f32(chip) * 96.0, 70.0, 88.0, 34.0, folder_name(chip), fill, 14.0)
        chip += 1usize
    }
    var pos = 0usize
    while pos < s.list_total && pos < 9usize {
        let i = s.list[pos]
        let m = s.mails[i]
        let y: f32 = 116.0 + f32(pos) * 74.0
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 68.0, 18.0, ui.cream())
        try avatar(a, builder, faces, 48.0, y + 36.0, 20.0, from_of(a, s, i), i)
        var face = faces.jost
        if m.unread { face = faces.jost_bold }
        try ui.clipped(a, builder, face, 16.0, from_of(a, s, i), 80.0, y + 8.0, 200.0, ui.ink())
        try ui.clipped(a, builder, face, 15.0, subject_of(a, s, i), 80.0, y + 28.0, 270.0, ui.ink())
        try ui.clipped(a, builder, faces.grotesk, 12.0, body_of(a, s, i), 80.0, y + 49.0, 270.0, ui.muted())
        try ui.put_right(a, builder, faces.grotesk, 11.0, ui.ago_text(a, m.ago), 380.0, y + 12.0, ui.muted())
        var star_tone = ui.soft()
        if m.starred { star_tone = ui.amber_dark() }
        try svg.draw(a, builder, star_icon(m.starred), geometry.rect(356.0, y + 34.0, 22.0, 22.0), star_tone)
        ui.hit(&s.hits, 200usize + i, 16.0, y + 2.0, 336.0, 68.0)
        ui.hit(&s.hits, 300usize + i, 352.0, y + 2.0, 44.0, 68.0)
        pos += 1usize
    }
    if s.list_total == 0usize { try ui.centred(a, builder, faces.jost, 19.0, "No messages here", 206.0, 300.0, ui.light_muted()) }
    // Compose.
    try ui.card(a, builder, 252.0, 820.0, 144.0, 56.0, 28.0, ui.amber())
    try svg.draw(a, builder, pencil_icon(), geometry.rect(268.0, 836.0, 24.0, 24.0), ui.ink())
    try ui.put(a, builder, faces.jost, 17.0, "Compose", 300.0, 837.0, ui.ink())
    ui.hit(&s.hits, 150usize, 252.0, 820.0, 144.0, 56.0)
    ret ok
}

fn draw_view(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let m = s.mails[s.open]
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 500usize, 0.0, 10.0, 66.0, 56.0)
    var star_tone = ui.light_muted()
    if m.starred { star_tone = ui.amber() }
    try svg.draw(a, builder, star_icon(m.starred), geometry.rect(322.0, 24.0, 28.0, 28.0), star_tone)
    ui.hit(&s.hits, 510usize, 308.0, 10.0, 52.0, 56.0)
    try svg.draw(a, builder, trash_icon(), geometry.rect(364.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 520usize, 356.0, 10.0, 52.0, 56.0)
    let (subject_box, subject_error) = ui.wrapped(a, builder, faces.jost_bold, 24.0, subject_of(a, s, s.open), 24.0, 80.0, 364.0, 2u32, ui.light())
    if subject_error != ok { ret subject_error }
    var y: f32 = 80.0 + subject_box.height + 20.0
    try avatar(a, builder, faces, 48.0, y + 24.0, 22.0, from_of(a, s, s.open), s.open)
    try ui.put(a, builder, faces.jost, 18.0, from_of(a, s, s.open), 84.0, y + 6.0, ui.light())
    var line = "to me"
    if m.folder == SENT { line = "to " }
    try ui.put(a, builder, faces.grotesk, 13.0, ui.join(a, line, ", ", ui.ago_text(a, m.ago)), 84.0, y + 32.0, ui.light_muted())
    y += 64.0
    try ui.card(a, builder, 16.0, y, 380.0, 280.0, 18.0, ui.cream())
    let (body_box, body_error) = ui.wrapped(a, builder, faces.jost, 17.0, body_of(a, s, s.open), 32.0, y + 18.0, 348.0, 9u32, ui.ink())
    if body_error != ok { ret body_error }
    try ui.pill(a, builder, &s.hits, faces, 530usize, 16.0, 830.0, 140.0, 48.0, "Reply", ui.amber(), 17.0)
    ret ok
}

fn compose_field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, which: usize, label: str, value: str, y: f32, height: f32) -> err {
    try ui.put(a, builder, faces.grotesk, 12.0, label, 20.0, y - 15.0, ui.light_muted())
    if s.focus == which { try ui.card(a, builder, 14.0, y - 2.0, 384.0, height + 4.0, 16.0, ui.amber()) }
    try ui.card(a, builder, 16.0, y, 380.0, height, 14.0, ui.cream())
    let (box, draw_error) = ui.wrapped(a, builder, faces.jost, 17.0, value, 30.0, y + 9.0, 350.0, 3u32, ui.ink())
    if draw_error != ok { ret draw_error }
    if s.focus == which {
        var caret_x: f32 = 30.0 + box.width + 2.0
        var caret_y: f32 = y + 8.0
        if value.len == 0usize { caret_x = 30.0 }
        if caret_x > 380.0 { caret_x = 380.0 }
        try ui.card(a, builder, caret_x, caret_y, 2.0, 22.0, 1.0, ui.amber())
    }
    ui.hit(&s.hits, 1500usize + which, 16.0, y, 380.0, height)
    ret ok
}

fn draw_compose(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "New message", 24.0, 14.0, ui.light())
    try compose_field(a, builder, s, faces, 0usize, "To", ui.field_text(a, &s.to), 76.0, 44.0)
    try compose_field(a, builder, s, faces, 1usize, "Subject", ui.field_text(a, &s.subject), 144.0, 44.0)
    try compose_field(a, builder, s, faces, 2usize, "Message", ui.field_text(a, &s.message), 212.0, 112.0)
    try ui.pill(a, builder, &s.hits, faces, 1300usize, 16.0, 348.0, 186.0, 46.0, "Send", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 1302usize, 210.0, 348.0, 186.0, 46.0, "Discard", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == LIST_SCREEN {
        try draw_list(a, builder, s, faces)
    } else if s.screen == VIEW_SCREEN {
        try draw_view(a, builder, s, faces)
    } else {
        try draw_compose(a, builder, s, faces)
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

fn focused(s: *State) -> *ui.Field {
    if s.focus == 0usize { ret &s.to }
    if s.focus == 1usize { ret &s.subject }
    ret &s.message
}

fn open_compose(s: *State, to: str, subject: str) {
    s.screen = COMPOSE_SCREEN
    s.to.len = 0usize
    s.subject.len = 0usize
    s.message.len = 0usize
    var i = 0usize
    while i < to.len && i < 64usize {
        ui.field_type(&s.to, to[i], false)
        i += 1usize
    }
    i = 0usize
    while i < subject.len && i < 64usize {
        ui.field_type(&s.subject, subject[i], false)
        i += 1usize
    }
    s.focus = 2usize
    if to.len == 0usize { s.focus = 0usize }
    ui.say("mail composing\n")
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == COMPOSE_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.focus < 2usize { s.focus += 1usize }
                ret true
            }
            ret ui.field_key(focused(s), id, s.focus != 0usize)
        }
        if id >= 1500usize && id < 1503usize {
            s.focus = id - 1500usize
            ret true
        }
        if id == 1300usize {
            if s.to.len > 0usize {
                let made = add_mail(s, ui.field_text(a, &s.to), ui.field_text(a, &s.subject), ui.field_text(a, &s.message), SENT, false, 0usize)
                if made != NONE { ui.say("mail sent\n") }
                s.folder = SENT
                s.screen = LIST_SCREEN
            }
            ret true
        }
        if id == 1302usize {
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == VIEW_SCREEN {
        if id == 500usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 510usize {
            s.mails[s.open].starred = !s.mails[s.open].starred
            ui.say("mail starred\n")
            ret true
        }
        if id == 520usize {
            s.mails[s.open].folder = TRASH
            s.screen = LIST_SCREEN
            ui.say("mail deleted\n")
            ret true
        }
        if id == 530usize {
            open_compose(s, from_of(a, s, s.open), ui.join(a, "Re: ", subject_of(a, s, s.open), ""))
            ret true
        }
        ret false
    }
    if id >= 100usize && id < 104usize {
        s.folder = id - 100usize
        ui.say("mail folder ")
        ui.say(folder_name(s.folder))
        ui.say("\n")
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_MAILS {
        s.open = id - 200usize
        s.mails[s.open].unread = false
        s.screen = VIEW_SCREEN
        ui.say("mail opened ")
        ui.say_text(subject_of(a, s, s.open))
        ui.say("\n")
        ret true
    }
    if id >= 300usize && id < 300usize + MAX_MAILS {
        s.mails[id - 300usize].starred = !s.mails[id - 300usize].starred
        ret true
    }
    if id == 150usize {
        open_compose(s, "", "")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "mail")
    if kit_error != ok {
        ui.say("mail open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("mail fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    let m1 = add_mail(&s, "Maya Chen", "Lunch on Friday?", "Hi! Are you free for lunch on Friday at 12:30? There is a new place near the library that I would love to try. Let me know and I will book a table for two.", INBOX, true, 14usize)
    let m2 = add_mail(&s, "City Library", "Your hold is ready", "The book you reserved, Field Notes on Craters, is ready for pickup at the front desk. It will be held for seven days.", INBOX, true, 95usize)
    let m3 = add_mail(&s, "Alex Rivera", "Build is green", "Good news: the nightly build passed all tests, including the new ones for the storage server. I merged the branch this morning.", INBOX, false, 300usize)
    let m4 = add_mail(&s, "Neper Bank", "Your statement is ready", "Your October statement is now available. Sign in to view your balance and recent transactions. This is a sample message.", INBOX, false, 1500usize)
    let m5 = add_mail(&s, "Priya", "Notes from the meeting", "Thanks for joining. My notes are attached in the shared folder. The next meeting is on Thursday at 10.", INBOX, false, 2900usize)
    let m6 = add_mail(&s, "Dad", "Photos from the trip", "Found the old photos from the trip to the coast. I will bring them on Sunday so you can scan them.", INBOX, false, 5000usize)
    let m7 = add_mail(&s, "Sam", "Happy birthday!", "Many happy returns! Dinner is on me this weekend. Pick the place.", INBOX, false, 8000usize)
    s.mails[m3].starred = true
    s.mails[m5].starred = true
    let s1 = add_mail(&s, "Maya Chen", "Re: Lunch on Friday?", "Friday works for me. See you at 12:30.", SENT, false, 5usize)
    if !show(a, &kit, &s) {
        ui.say("mail present failed\n")
        ret ok
    }
    ui.say("mail shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            ui.say("mail home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("mail present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
