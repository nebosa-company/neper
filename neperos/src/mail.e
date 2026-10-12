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
use e.io
use e.time
use e.fmt.mail as mailfmt
use e.fmt.mime as mime
use e.fmt.extract as extract
use e.fmt.multipart as multipart
use e.bytes as bytes
use vaultfs
use e.net.imap as imap
use e.net.smtp as smtp
use appkit
use text
use ui
use netclient
use sysettings
use netproto

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
    // (C128) The message's UID on the server, when it came from there.
    uid: usize,
    remote: bool,
    // (C158) The first attachment of a multipart/mixed message: its file name and what of its bytes were kept (128).
    att_name: [24]u8,
    att_name_len: usize,
    att_size: usize,
    att_len: usize,
    att_data: [128]u8,
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

// ----------------------------------------------------------------------------------------------
// The network (C128): IMAP and SMTP over the network server's connection.

fn net_read(ctx: *void, dst: []u8) -> (usize, err) {
    var want = dst.len
    if want > netproto.CHUNK { want = netproto.CHUNK }
    if want == 0usize { ret (0usize, ok) }
    let (n, r) = netclient.recv(mem.address_of(&dst[0usize]), want)
    if r != netproto.R_OK { ret (0usize, io.NoProgress) }
    if n == 0usize { ret (0usize, io.End) }
    ret (n, ok)
}

fn net_write(ctx: *void, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let r = netclient.send(mem.address_of(&src[0usize]), src.len)
    if r != netproto.R_OK { ret (0usize, io.NoProgress) }
    ret (src.len, ok)
}

fn net_flush(ctx: *void) -> err { ret ok }

fn net_reader() -> io.Reader { ret io.Reader { ctx: nil, read: net_read } }

fn net_writer() -> io.Writer { ret io.Writer { ctx: nil, write: net_write, flush: net_flush } }

// Connect to the test mail host: TLS first (the chain is checked against the roots and the test CA), plain text
// when that port is not answered. The result is the network result and whether the link is TLS.
fn mail_connect(tls_port: u16, plain_port: u16) -> (usize, bool) {
    let secure_result = netclient.connect("neper.test", tls_port, true)
    if secure_result == netproto.R_OK { ret (secure_result, true) }
    let plain_result = netclient.connect("neper.test", plain_port, false)
    ret (plain_result, false)
}

// Fetch the INBOX over IMAP and make it the app's inbox: the number of messages, or 0 when there is no server or
// the login fails (the sample inbox stays).
// (C158) The `filename` of a Content-Disposition value: `attachment; filename="menu.txt"`, quoted or bare.
fn disposition_name(disposition: str) -> str {
    var at = 0usize
    while at + 9usize <= disposition.len {
        if extract.starts_fold(disposition, at, "filename=") {
            var from = at + 9usize
            var quoted = false
            if from < disposition.len && disposition[from] == 34u8 {
                quoted = true
                from += 1usize
            }
            var to = from
            while to < disposition.len && disposition[to] != 34u8 && disposition[to] != 59u8 && disposition[to] != 32u8 { to += 1usize }
            ret disposition[from..to]
        }
        at += 1usize
    }
    ret ""
}

// (C158) The first attachment of a multipart/mixed message: a part whose Content-Disposition is `attachment`, its
// transfer encoding (base64 or none) undone, kept in message `made` for saving to Files.
fn read_attachment(a: *mem.Arena, s: *State, made: usize, headers: []const mime.Header, body: io.Reader) {
    let (content_type, has_type) = mime.header(headers, "Content-Type")
    if !has_type { ret }
    let (media, media_error) = mime.parse_media_type(a, content_type, 256usize)
    if media_error != ok || !extract.starts_fold(media.major, 0usize, "multipart") { ret }
    var boundary = ""
    var k = 0usize
    while k < media.parameters.len {
        if media.parameters[k].name.len == 8usize && extract.starts_fold(media.parameters[k].name, 0usize, "boundary") { boundary = media.parameters[k].value }
        k += 1usize
    }
    if boundary.len == 0usize { ret }
    let (storage, storage_error) = mem.alloc[u8](a, multipart.storage_required())
    if storage_error != ok { ret }
    let (opened, open_error) = multipart.reader(storage, body, boundary, 8u32, 65536u64)
    if open_error != ok { ret }
    var parts = opened
    var seen = 0usize
    while seen < 8usize {
        seen += 1usize
        let (part, has_part, part_error) = multipart.reader_next_err(&parts)
        if part_error != ok || !has_part { ret }
        let (disposition, has_disposition) = mime.header(part.headers, "Content-Disposition")
        if has_disposition && extract.starts_fold(disposition, 0usize, "attachment") {
            let file_name = disposition_name(disposition)
            let (raw_room, raw_error) = mem.alloc[u8](a, 1024usize)
            if raw_error != ok { ret }
            var part_body = part.body
            var got = 0usize
            var more = true
            while more && got < 1024usize {
                let (count, read_error) = io.read(&part_body, raw_room[got..1024usize])
                if read_error != ok || count == 0usize { more = false } else { got += count }
            }
            var data = raw_room[0usize..got]
            let (encoding, has_encoding) = mime.header(part.headers, "Content-Transfer-Encoding")
            if has_encoding && extract.starts_fold(encoding, 0usize, "base64") {
                // Whitespace out, then decoded.
                var clean = raw_room[0usize..0usize]
                var w = 0usize
                var r = 0usize
                while r < got {
                    let c = raw_room[r]
                    if c != 10u8 && c != 13u8 && c != 32u8 {
                        raw_room[w] = c
                        w += 1usize
                    }
                    r += 1usize
                }
                clean = raw_room[0usize..w]
                let (room, room_error) = mem.alloc[u8](a, w / 4usize * 3usize + 3usize)
                if room_error != ok { ret }
                let (decoded, decode_error) = bytes.base64_decode(room, clean, .Standard)
                if decode_error != ok { ret }
                data = decoded
            }
            var n = 0usize
            while n < file_name.len && n < 24usize {
                s.mails[made].att_name[n] = file_name[n]
                n += 1usize
            }
            s.mails[made].att_name_len = n
            s.mails[made].att_size = data.len
            var d = 0usize
            while d < data.len && d < 128usize {
                s.mails[made].att_data[d] = data[d]
                d += 1usize
            }
            s.mails[made].att_len = d
            ui.say("mail attachment ")
            ui.say_text(file_name)
            ui.say(" ")
            ui.say_num(data.len)
            ui.say("\n")
            ret
        }
    }
}

fn sync_inbox(a: *mem.Arena, s: *State) -> usize {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret 0usize }
    var loaded = 0usize
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, "neper", "secret") == ok {
            let (box, select_error) = imap.select(&sess, "INBOX")
            if select_error == ok && box.exists > 0u32 {
                let (items, fetch_error) = imap.fetch(&sess, "1:*", "(FLAGS BODY.PEEK[])", false)
                if fetch_error == ok {
                    // What the server holds replaces the sample inbox.
                    var k = 0usize
                    while k < MAX_MAILS {
                        if s.mails[k].used && s.mails[k].folder == INBOX { s.mails[k].used = false }
                        k += 1usize
                    }
                    var now_seconds = 0i64
                    let (wall, wall_error) = time.now()
                    if wall_error == ok { now_seconds = wall.nanos / 1000000000i64 }
                    var i = 0usize
                    while i < items.len {
                        let (raw, has_raw) = imap.section(items[i], "BODY[]")
                        if has_raw {
                            var state = io.SliceReader { data: raw, off: 0usize }
                            let (message, message_error) = mailfmt.read_message(a, io.slice_reader(&state), 4096usize)
                            if message_error == ok {
                                let (from_header, has_from) = mime.header(message.headers, "From")
                                let (subject, has_subject) = mime.header(message.headers, "Subject")
                                let (date, has_date) = mime.header(message.headers, "Date")
                                var from_name = "Unknown"
                                if has_from {
                                    let (addr, addr_error) = mailfmt.parse_address(a, from_header)
                                    if addr_error == ok {
                                        from_name = addr.name
                                        if from_name.len == 0usize { from_name = addr.address }
                                    }
                                }
                                var ago = 0usize
                                if has_date {
                                    let (stamp, date_error) = mailfmt.parse_date(date)
                                    if date_error == ok && now_seconds > stamp.instant { ago = usize((now_seconds - stamp.instant) / 60i64) }
                                }
                                // (C158) The text of the message through the extraction facade: a multipart/alternative
                                // gives its plain part, an HTML-only message its text, quoted-printable and base64
                                // undone; when it will not read, the raw bytes as before.
                                var body_buf: [160]u8 = zero
                                var body_len = 0usize
                                let (doc, doc_error) = extract.extract_as(a, raw, extract.Format.Mail)
                                if doc_error == ok && doc.text.len > 0usize {
                                    var j = 0usize
                                    while j < doc.text.len && j < 160usize {
                                        body_buf[j] = doc.text[j]
                                        j += 1usize
                                    }
                                    body_len = j
                                } else {
                                    var body = message.body
                                    let (got, body_error) = io.read(&body, body_buf[0usize..160usize])
                                    if body_error == ok { body_len = got }
                                }
                                let unread = !imap.has_flag(items[i], "\\Seen")
                                let body_text = ui.text_of(a, body_buf[0usize..], body_len)
                                ui.say("mail body ")
                                ui.say_text(subject)
                                ui.say(": ")
                                ui.say_text(body_text)
                                ui.say("\n")
                                let made = add_mail(s, from_name, subject, body_text, INBOX, unread, ago)
                                if made != NONE {
                                    s.mails[made].uid = usize(items[i].uid)
                                    s.mails[made].remote = true
                                    read_attachment(a, s, made, message.headers, message.body)
                                    loaded += 1usize
                                }
                            }
                        }
                        i += 1usize
                    }
                }
            }
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    if loaded > 0usize && secure { ui.say("mail imap tls\n") }
    ret loaded
}

// Set a flag on the server's copy of a message (and expunge when it is deleted): true when the server took it.
fn remote_flag(a: *mem.Arena, uid: usize, action: str, expunge_after: bool) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var done = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, "neper", "secret") == ok {
            let (box, select_error) = imap.select(&sess, "INBOX")
            if select_error == ok {
                if imap.store(&sess, ui.number(a, uid), action, true) == ok {
                    done = true
                    if expunge_after {
                        let (removed, expunge_error) = imap.expunge(&sess)
                        if expunge_error != ok { done = false }
                    }
                }
            }
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret done
}

// An address for what was typed in To: itself when it has an @, else the name without spaces at the test domain.
fn address_of(a: *mem.Arena, typed: str) -> str {
    var has_at = false
    var i = 0usize
    while i < typed.len {
        if typed[i] == 64u8 { has_at = true }
        i += 1usize
    }
    if has_at { ret typed }
    let (out, out_error) = mem.alloc[u8](a, typed.len + 12usize)
    if out_error != ok { ret typed }
    var n = 0usize
    i = 0usize
    while i < typed.len {
        var c = typed[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != 32u8 {
            out[n] = c
            n += 1usize
        }
        i += 1usize
    }
    let domain = "@neper.test"
    i = 0usize
    while i < domain.len {
        out[n] = domain[i]
        n += 1usize
        i += 1usize
    }
    ret out[0usize..n]
}

// Send the composed message over SMTP: the server's three-digit reply, or 0 when it could not be sent.
fn send_message(a: *mem.Arena, s: *State) -> usize {
    let (link, secure) = mail_connect(8465u16, 8025u16)
    if link != netproto.R_OK { ret 0usize }
    var code = 0usize
    let (session, connect_error) = smtp.connect(a, net_reader(), net_writer(), "neper.test")
    if connect_error == ok {
        var sess = session
        if smtp.ehlo(&sess) == ok {
            let to = address_of(a, ui.field_text(a, &s.to))
            var message_text = ui.join(a, "From: neper@neper.test\r\nTo: ", to, "")
            message_text = ui.join(a, message_text, ui.join(a, "\r\nSubject: ", ui.field_text(a, &s.subject), ""), "")
            message_text = ui.join(a, message_text, ui.join(a, "\r\n\r\n", ui.field_text(a, &s.message), "\r\n"), "")
            var state = io.SliceReader { data: message_text, off: 0usize }
            let recipients: [1]str = [1]str{ to }
            let (sent, send_error) = smtp.send(&sess, "neper@neper.test", recipients[0usize..1usize], io.slice_reader(&state), u64(message_text.len))
            if send_error == ok { code = usize(sent.reply.code) }
            let bye = smtp.quit(&sess)
        }
    }
    let closed = netclient.close()
    if code != 0usize && secure { ui.say("mail smtp tls\n") }
    ret code
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
    // (C158) An attachment is a chip below the message; a tap saves it into /Downloads.
    if m.att_name_len > 0usize {
        try ui.card(a, builder, 16.0, 700.0, 380.0, 48.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, ui.join(a, ui.text_of(a, m.att_name[0usize..], m.att_name_len), ui.join(a, " (", ui.number(a, m.att_size), " bytes)"), ""), 32.0, 713.0, ui.ink())
        ui.hit(&s.hits, 540usize, 16.0, 700.0, 380.0, 48.0)
    }
    try ui.pill(a, builder, &s.hits, faces, 530usize, 16.0, 830.0, 140.0, 48.0, "Reply", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 550usize, 172.0, 830.0, 140.0, 48.0, "Copy", ui.amber(), 17.0)
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
                // Over the network when there is a server to take it.
                let code = send_message(a, s)
                if code != 0usize {
                    ui.say("mail smtp ")
                    ui.say_text(ui.number(a, code))
                    ui.say("\n")
                }
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
        if id == 540usize && s.mails[s.open].att_name_len > 0usize {
            // (C158) Save the attachment into Files: /Downloads/<name>, checked by reading its size back.
            let m = s.mails[s.open]
            let made_dir = vaultfs.mkdir("/Downloads")
            let dest = ui.join(a, "/Downloads/", ui.text_of(a, m.att_name[0usize..], m.att_name_len), "")
            var saved = false
            if m.att_len > 0usize { saved = vaultfs.write_big(dest, mem.address_of(&s.mails[s.open].att_data[0usize]), m.att_len) }
            let (size, kind_of, extra, found) = vaultfs.stat(dest)
            if saved && found && size == m.att_len {
                ui.say("mail attachment saved ")
                ui.say_text(ui.text_of(a, m.att_name[0usize..], m.att_name_len))
                ui.say(" ")
                ui.say_num(size)
                ui.say("\n")
            } else {
                ui.say("mail attachment not saved\n")
            }
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
            if s.mails[s.open].remote {
                if remote_flag(a, s.mails[s.open].uid, "+FLAGS.SILENT (\\Deleted)", true) {
                    ui.say("mail server deleted ")
                    ui.say_text(ui.number(a, s.mails[s.open].uid))
                    ui.say("\n")
                }
            }
            ret true
        }
        if id == 530usize {
            open_compose(s, from_of(a, s, s.open), ui.join(a, "Re: ", subject_of(a, s, s.open), ""))
            ret true
        }
        if id == 550usize {
            // (C175) Copy: the start of the message (the clipboard holds 32 bytes) goes to the clipboard.
            let (wall, wall_error) = time.now()
            var now_s = 0usize
            if wall_error == ok { now_s = usize(wall.nanos / 1000000000i64) }
            let text_copied = body_of(a, s, s.open)
            let taken = sysettings.clip_set(3usize, now_s, text_copied)
            ui.say("mail copied ")
            ui.say_num(text_copied.len)
            ui.say("\n")
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
        let was_unread = s.mails[s.open].unread
        s.mails[s.open].unread = false
        s.screen = VIEW_SCREEN
        if was_unread && s.mails[s.open].remote {
            if remote_flag(a, s.mails[s.open].uid, "+FLAGS.SILENT (\\Seen)", false) {
                ui.say("mail server read ")
                ui.say_text(ui.number(a, s.mails[s.open].uid))
                ui.say("\n")
            }
        }
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
    // With a mail server reachable, its inbox replaces the sample one.
    let synced = sync_inbox(a, &s)
    if synced > 0usize {
        ui.say("mail synced ")
        ui.say_text(ui.number(a, synced))
        ui.say("\n")
    }
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
