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
use e.fmt.html as html
use e.fmt.png
use e.fmt.jpeg
use e.gfx.image
use e.str
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
use bgclient

const NONE: usize = 99usize
const MAX_MAILS: usize = 20usize
const LIST_SCREEN: usize = 0usize
const VIEW_SCREEN: usize = 1usize
const COMPOSE_SCREEN: usize = 2usize
const INBOX: usize = 0usize
const STARRED: usize = 1usize
const SENT: usize = 2usize
const TRASH: usize = 3usize
// (C158) More screens: a thread's messages, the mailboxes and accounts, the add-account form, the file picker.
const THREAD_SCREEN: usize = 3usize
const BOXES_SCREEN: usize = 4usize
const ACCOUNT_SCREEN: usize = 5usize
const PICK_SCREEN: usize = 6usize
const SEARCH_SCREEN: usize = 7usize
// The kinds of a line of a rich (HTML) message.
const R_BODY: usize = 0usize
const R_H1: usize = 1usize
const R_H2: usize = 2usize
const R_BULLET: usize = 3usize
const R_LINK: usize = 4usize
const R_IMAGE: usize = 5usize
const RICH_LINES: usize = 14usize
const MAX_BOXES: usize = 6usize
const MAX_ACCOUNTS: usize = 3usize
const ATTACH_MAX: usize = 4096usize

// (C158) One line of an HTML message after layout: its text (wrapped to what a line of its kind holds) and its kind.
type Rich = struct { text: [44]u8, len: usize, kind: usize }

// (C158) A mail account other than the built-in test account: the user and password typed when it was added.
type Account = struct { user: [16]u8, user_len: usize, pass: [16]u8, pass_len: usize }

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
    // (C158) An HTML message laid out as lines, and its inline image (the part named by Content-ID) as a texture.
    rich: [14]Rich,
    rich_total: usize,
    has_img: bool,
    img_tex: scene.TextureId,
    img_w: f32,
    img_h: f32,
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
    // (C158) The mailboxes the server listed for the account and which one is shown, the accounts (the built-in one
    // is account 0), the thread being read and the screen it was opened from.
    boxes: [6][16]u8,
    box_lens: [6]usize,
    box_total: usize,
    box: usize,
    accounts: [3]Account,
    account_total: usize,
    account: usize,
    thread_head: usize,
    thread_list: [8]usize,
    thread_total: usize,
    from_thread: bool,
    // The account form: the user and the password being typed (the focus field is `focus`, 0 or 1).
    form_user: ui.Field,
    form_pass: ui.Field,
    // The file attached to the message being composed (from /Downloads), and the files the picker lists.
    attach_name: [24]u8,
    attach_name_len: usize,
    attach_data: [4096]u8,
    attach_len: usize,
    pick_names: [6][24]u8,
    pick_lens: [6]usize,
    pick_total: usize,
    // (C158) A server-side search: the words typed, and the UIDs the server answered (the list shows only those while
    // `filtering`); and the polling of the inbox (when it last ran, the highest UID seen).
    search: ui.Field,
    filtering: bool,
    filter_uids: [20]usize,
    filter_total: usize,
    filter_words: [24]u8,
    filter_words_len: usize,
    last_poll_ms: usize,
    max_uid: usize,
    // (C158) The program a file was handed over to (Document is 40): the app leaves and exits with 20000 + it, and the
    // shell starts that program; the file's path is in /handover.
    handover: usize,
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
// transfer encoding (base64 or none) undone (up to 24 KB of its encoded form): its file name and its bytes.
fn find_attachment(a: *mem.Arena, headers: []const mime.Header, body: io.Reader) -> (str, str, bool) {
    let (content_type, has_type) = mime.header(headers, "Content-Type")
    if !has_type { ret ("", "", false) }
    let (media, media_error) = mime.parse_media_type(a, content_type, 256usize)
    if media_error != ok || !extract.starts_fold(media.major, 0usize, "multipart") { ret ("", "", false) }
    var boundary = ""
    var k = 0usize
    while k < media.parameters.len {
        if media.parameters[k].name.len == 8usize && extract.starts_fold(media.parameters[k].name, 0usize, "boundary") { boundary = media.parameters[k].value }
        k += 1usize
    }
    if boundary.len == 0usize { ret ("", "", false) }
    let (storage, storage_error) = mem.alloc[u8](a, multipart.storage_required())
    if storage_error != ok { ret ("", "", false) }
    let (opened, open_error) = multipart.reader(storage, body, boundary, 8u32, 65536u64)
    if open_error != ok { ret ("", "", false) }
    var parts = opened
    var seen = 0usize
    while seen < 8usize {
        seen += 1usize
        let (part, has_part, part_error) = multipart.reader_next_err(&parts)
        if part_error != ok || !has_part { ret ("", "", false) }
        let (disposition, has_disposition) = mime.header(part.headers, "Content-Disposition")
        if has_disposition && extract.starts_fold(disposition, 0usize, "attachment") {
            let file_name = disposition_name(disposition)
            let (raw_room, raw_error) = mem.alloc[u8](a, 24576usize)
            if raw_error != ok { ret ("", "", false) }
            var part_body = part.body
            var got = 0usize
            var more = true
            while more && got < 24576usize {
                let (count, read_error) = io.read(&part_body, raw_room[got..24576usize])
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
                if room_error != ok { ret ("", "", false) }
                let (decoded, decode_error) = bytes.base64_decode(room, clean, .Standard)
                if decode_error != ok { ret ("", "", false) }
                data = decoded
            }
            ret (file_name, data, true)
        }
    }
    ret ("", "", false)
}

// (C158) The first attachment of a message, its name, its size and the start of its bytes kept in message `made`; the
// whole file is fetched again from the server when it is saved.
fn read_attachment(a: *mem.Arena, s: *State, made: usize, headers: []const mime.Header, body: io.Reader) {
    let (file_name, data, found) = find_attachment(a, headers, body)
    if !found { ret }
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
}

// ----------------------------------------------------------------------------------------------
// (C158) HTML messages: the MIME tree walked for its HTML part and an inline image, the HTML laid out as lines of the
// kinds the screen draws, and the image decoded (PNG or JPEG) into a texture.

type Flow = struct { cur: [44]u8, cur_len: usize, pending: bool }

// What the MIME walk found: the HTML and plain parts (decoded) and the first image part with its Content-ID.
type Found = struct { html_text: str, has_html: bool, plain: str, has_plain: bool, image: str, has_image: bool, cid: str }

fn rich_limit(kind: usize) -> usize {
    if kind == R_H1 { ret 20usize }
    if kind == R_H2 { ret 26usize }
    if kind == R_BULLET { ret 34usize }
    ret 38usize
}

// End the line being gathered: it becomes a line of the message.
fn rich_flush(m: *Mail, f: *Flow, kind: usize) {
    if f.cur_len == 0usize { ret }
    if m.rich_total < RICH_LINES {
        var line: Rich = zero
        var i = 0usize
        while i < f.cur_len && i < 44usize {
            line.text[i] = f.cur[i]
            i += 1usize
        }
        line.len = i
        line.kind = kind
        m.rich[m.rich_total] = line
        m.rich_total += 1usize
    }
    f.cur_len = 0usize
    f.pending = false
}

// Add words to the line being gathered: whitespace collapses to one space and a line breaks at its limit.
fn rich_add(m: *Mail, f: *Flow, words: str, kind: usize) {
    let limit = rich_limit(kind)
    var i = 0usize
    while i < words.len {
        let c = words[i]
        if c == 32u8 || c == 10u8 || c == 13u8 || c == 9u8 {
            if f.cur_len > 0usize { f.pending = true }
            i += 1usize
        } else {
            var end = i
            while end < words.len && words[end] != 32u8 && words[end] != 10u8 && words[end] != 13u8 && words[end] != 9u8 { end += 1usize }
            var left = end - i
            while left > 0usize {
                var take = left
                if take > limit { take = limit }
                var need = take
                if f.pending && f.cur_len > 0usize { need += 1usize }
                if f.cur_len + need > limit && f.cur_len > 0usize { rich_flush(m, f, kind) }
                if f.pending && f.cur_len > 0usize && f.cur_len < 43usize {
                    f.cur[f.cur_len] = 32u8
                    f.cur_len += 1usize
                }
                f.pending = false
                var k = 0usize
                while k < take && f.cur_len < 44usize {
                    f.cur[f.cur_len] = words[i + k]
                    f.cur_len += 1usize
                    k += 1usize
                }
                i += take
                left -= take
                if left > 0usize { rich_flush(m, f, kind) }
            }
        }
    }
}

fn rich_block(name: str) -> bool {
    ret ui.same(name, "p") || ui.same(name, "div") || ui.same(name, "ul") || ui.same(name, "ol") || ui.same(name, "li") || ui.same(name, "br") || ui.same(name, "table") || ui.same(name, "tr") || ui.same(name, "hr") || ui.same(name, "blockquote") || ui.same(name, "h1") || ui.same(name, "h2") || ui.same(name, "h3") || ui.same(name, "h4") || ui.same(name, "section")
}

// Walk the HTML below `id`, gathering lines. An `<img src="cid:...">` naming the image part found is a line of its own.
fn rich_walk(a: *mem.Arena, m: *Mail, f: *Flow, doc: *const html.Document, id: html.NodeId, kind: usize, cid: str) {
    let n = html.node(doc, id)
    if n.kind == .Text {
        rich_add(m, f, n.value, kind)
        ret
    }
    if n.kind != .Element && n.kind != .Document { ret }
    var child_kind = kind
    if n.kind == .Element {
        let name = n.name
        if ui.same(name, "script") || ui.same(name, "style") || ui.same(name, "head") || ui.same(name, "title") { ret }
        if rich_block(name) { rich_flush(m, f, kind) }
        if ui.same(name, "h1") { child_kind = R_H1 }
        if ui.same(name, "h2") || ui.same(name, "h3") || ui.same(name, "h4") { child_kind = R_H2 }
        if ui.same(name, "li") {
            child_kind = R_BULLET
            rich_add(m, f, "-", R_BULLET)
            f.pending = true
        }
        if ui.same(name, "a") { child_kind = R_LINK }
        if ui.same(name, "img") {
            let (source, has_source) = html.attribute(n, "src")
            let (alt, has_alt) = html.attribute(n, "alt")
            rich_flush(m, f, kind)
            if has_source && source.len > 4usize && ui.same(source[0usize..4usize], "cid:") && m.has_img && ui.same(source[4usize..source.len], cid) {
                if m.rich_total < RICH_LINES {
                    var line: Rich = zero
                    line.kind = R_IMAGE
                    m.rich[m.rich_total] = line
                    m.rich_total += 1usize
                }
            } else if has_alt && alt.len > 0usize {
                rich_add(m, f, ui.join(a, "[", alt, "]"), R_BODY)
                rich_flush(m, f, R_BODY)
            }
        }
    }
    var it = html.children(doc, id)
    var more = true
    while more {
        let (child, has_child) = html.children_next(&it)
        if !has_child { more = false } else { rich_walk(a, m, f, doc, child, child_kind, cid) }
    }
    if n.kind == .Element && rich_block(n.name) { rich_flush(m, f, child_kind) }
}

// The value of a Content-ID header without its angle brackets.
fn bare_id(value: str) -> str {
    var from = 0usize
    var to = value.len
    while from < to && (value[from] == 32u8 || value[from] == 60u8) { from += 1usize }
    while to > from && (value[to - 1usize] == 32u8 || value[to - 1usize] == 62u8) { to -= 1usize }
    ret value[from..to]
}

// Walk a MIME entity (headers, blank line, body): multipart bodies part by part, the first HTML and plain text parts
// decoded (transfer encoding and charset), and the first PNG or JPEG part with its Content-ID.
fn mime_walk(a: *mem.Arena, f: *Found, entity: str, depth: usize) {
    let (block, entity_body) = extract.split_message(entity)
    let (content_type, has_type, type_error) = extract.header_value(a, block, "content-type")
    if type_error != ok { ret }
    let (encoding, has_encoding, encoding_error) = extract.header_value(a, block, "content-transfer-encoding")
    if encoding_error != ok { ret }
    var kind = "text/plain"
    if has_type { kind = content_type }
    if extract.starts_fold(kind, 0usize, "multipart/") {
        if depth >= 4usize { ret }
        let boundary = extract.parameter_of(kind, "boundary")
        if boundary.len == 0usize { ret }
        let marker = ui.join(a, "--", boundary, "")
        let (first, has_first) = str.find_from(entity_body, marker, 0usize)
        if !has_first { ret }
        var at = first + marker.len
        var guard = 0usize
        while at < entity_body.len && guard < 8usize {
            guard += 1usize
            var line_end = at
            while line_end < entity_body.len && entity_body[line_end] != 10u8 { line_end += 1usize }
            if line_end >= entity_body.len { ret }
            let part_start = line_end + 1usize
            let (next, has_next) = str.find_from(entity_body, marker, part_start)
            var part_end = entity_body.len
            if has_next { part_end = next }
            mime_walk(a, f, entity_body[part_start..part_end], depth + 1usize)
            if !has_next { ret }
            at = next + marker.len
            if at + 1usize < entity_body.len && entity_body[at] == 45u8 && entity_body[at + 1usize] == 45u8 { ret }
        }
        ret
    }
    if extract.starts_fold(kind, 0usize, "text/html") {
        let (decoded, decode_error) = extract.decode_body(a, entity_body, kind, encoding)
        if decode_error == ok && !f.has_html {
            f.html_text = decoded
            f.has_html = true
        }
        ret
    }
    if extract.starts_fold(kind, 0usize, "text/plain") || !has_type {
        let (decoded, decode_error) = extract.decode_body(a, entity_body, kind, encoding)
        if decode_error == ok && !f.has_plain {
            f.plain = decoded
            f.has_plain = true
        }
        ret
    }
    if extract.starts_fold(kind, 0usize, "image/png") || extract.starts_fold(kind, 0usize, "image/jpeg") {
        if f.has_image { ret }
        let (cid_value, has_cid, cid_error) = extract.header_value(a, block, "content-id")
        if cid_error != ok || !has_cid { ret }
        let (clean, clean_error) = extract.strip_spaces(a, entity_body)
        if clean_error != ok { ret }
        let (room, room_error) = mem.alloc[u8](a, clean.len / 4usize * 3usize + 3usize)
        if room_error != ok { ret }
        let (raw, raw_error) = bytes.base64_decode(room, clean, .Standard)
        if raw_error != ok { ret }
        f.image = raw
        f.has_image = true
        f.cid = bare_id(cid_value)
    }
}

// Decode a PNG or JPEG and keep it as the message's texture: true when it is there.
fn keep_image(a: *mem.Arena, kit: *appkit.Kit, m: *Mail, data: str) -> bool {
    if data.len < 8usize || data.len > 65536usize { ret false }
    var reader_state: io.SliceReader = zero
    reader_state.data = data
    reader_state.off = 0usize
    var decoded: image.Image = zero
    var decode_error = ok
    if data[0usize] == 255u8 && data[1usize] == 216u8 {
        let (jpeg_image, jpeg_error) = jpeg.decode(a, io.slice_reader(&reader_state), jpeg.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64 })
        decoded = jpeg_image
        decode_error = jpeg_error
    } else {
        let (png_image, png_error) = png.decode(a, io.slice_reader(&reader_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64, verify_crc: true })
        decoded = png_image
        decode_error = png_error
    }
    if decode_error != ok { ret false }
    let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if view_error != ok { ret false }
    let (texture, upload_error) = scene.upload_image(&kit.renderer, view)
    if upload_error != ok { ret false }
    m.img_tex = texture
    m.img_w = f32(decoded.width)
    m.img_h = f32(decoded.height)
    m.has_img = true
    ret true
}

// The message `made` of the raw bytes `raw`, when it carries HTML: its lines and its inline image.
fn rich_message(a: *mem.Arena, kit: *appkit.Kit, s: *State, made: usize, raw: str) {
    var found: Found = zero
    mime_walk(a, &found, raw, 0usize)
    if !found.has_html { ret }
    var m = &s.mails[made]
    if found.has_image {
        let kept = keep_image(a, kit, m, found.image)
    }
    let (doc, parse_error) = html.parse(a, found.html_text, html.Options { max_bytes: 16384usize, max_nodes: 512usize, max_attributes: 8usize, max_depth: 24u16, preserve_comments: false })
    if parse_error != ok { ret }
    var flow: Flow = zero
    rich_walk(a, m, &flow, &doc, doc.root, R_BODY, found.cid)
    rich_flush(m, &flow, R_BODY)
    if m.rich_total > 0usize {
        ui.say("mail rich ")
        ui.say_num(m.rich_total)
        if m.has_img {
            ui.say(" image ")
            ui.say_num(usize(m.img_w))
            ui.say("x")
            ui.say_num(usize(m.img_h))
        }
        ui.say("\n")
    }
}

// The user and password of the account in use.
fn account_user(a: *mem.Arena, s: *State) -> str {
    let c = s.accounts[s.account]
    ret ui.text_of(a, c.user[0usize..], c.user_len)
}

fn account_pass(a: *mem.Arena, s: *State) -> str {
    let c = s.accounts[s.account]
    ret ui.text_of(a, c.pass[0usize..], c.pass_len)
}

// The name of the mailbox shown.
fn box_name(a: *mem.Arena, s: *State) -> str {
    ret ui.text_of(a, s.boxes[s.box][0usize..], s.box_lens[s.box])
}

// Fetch the shown mailbox of the account in use over IMAP and make it the app's inbox: the number of messages, or 0
// when there is no server or the login fails (the messages already there stay). The first login of an account also
// lists the account's mailboxes.
fn sync_inbox(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> usize {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret 0usize }
    var loaded = 0usize
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            // The mailboxes of the account.
            let (names, list_error) = imap.list(&sess, "", "*")
            if list_error == ok && names.len > 0usize {
                s.box_total = 0usize
                var q = 0usize
                while q < names.len && s.box_total < MAX_BOXES {
                    let nm = names[q].name
                    var w = 0usize
                    while w < nm.len && w < 16usize {
                        s.boxes[s.box_total][w] = nm[w]
                        w += 1usize
                    }
                    s.box_lens[s.box_total] = w
                    s.box_total += 1usize
                    q += 1usize
                }
                if s.box >= s.box_total { s.box = 0usize }
                ui.say("mail folders ")
                ui.say_num(s.box_total)
                ui.say("\n")
            }
            let (box, select_error) = imap.select(&sess, box_name(a, s))
            if select_error == ok && box.exists == 0u32 {
                // An empty mailbox shows nothing.
                var cleared = 0usize
                while cleared < MAX_MAILS {
                    if s.mails[cleared].used && s.mails[cleared].folder == INBOX {
                        if s.mails[cleared].has_img {
                            let released = scene.release_image(&kit.renderer, s.mails[cleared].img_tex)
                        }
                        s.mails[cleared].used = false
                    }
                    cleared += 1usize
                }
            }
            if select_error == ok && box.exists > 0u32 {
                let (items, fetch_error) = imap.fetch(&sess, "1:*", "(FLAGS BODY.PEEK[])", false)
                if fetch_error == ok {
                    // What the server holds replaces the sample inbox.
                    var k = 0usize
                    while k < MAX_MAILS {
                        if s.mails[k].used && s.mails[k].folder == INBOX {
                            // The picture a message held is given back to the renderer, which has a few slots.
                            if s.mails[k].has_img {
                                let released = scene.release_image(&kit.renderer, s.mails[k].img_tex)
                            }
                            s.mails[k].used = false
                        }
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
                                    rich_message(a, kit, s, made, raw)
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
fn remote_flag(a: *mem.Arena, s: *State, uid: usize, action: str, expunge_after: bool) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var done = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            let (box, select_error) = imap.select(&sess, box_name(a, s))
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

// (C158) `data` as base64 in lines of 76 characters separated by CRLF.
fn wrap_base64(a: *mem.Arena, data: []const u8) -> str {
    let (needed, needed_error) = bytes.base64_encoded_len(data.len, true)
    if needed_error != ok { ret "" }
    let (room, room_error) = mem.alloc[u8](a, needed)
    if room_error != ok { ret "" }
    let (encoded, encode_error) = bytes.base64_encode(room, data, .Standard, true)
    if encode_error != ok { ret "" }
    let (out, out_error) = mem.alloc[u8](a, encoded.len + encoded.len / 76usize * 2usize + 2usize)
    if out_error != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < encoded.len {
        if i > 0usize && i % 76usize == 0usize {
            out[n] = 13u8
            out[n + 1usize] = 10u8
            n += 2usize
        }
        out[n] = encoded[i]
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
            let sender = ui.join(a, account_user(a, s), "@neper.test", "")
            var message_text = ui.join(a, ui.join(a, "From: ", sender, ""), ui.join(a, "\r\nTo: ", to, ""), "")
            message_text = ui.join(a, message_text, ui.join(a, "\r\nSubject: ", ui.field_text(a, &s.subject), ""), "")
            if s.attach_len > 0usize {
                // (C158) With an attachment: multipart/mixed, the text first, the file after as base64 in 76-byte lines.
                message_text = ui.join(a, message_text, "\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"=_neper_out\"\r\n\r\n--=_neper_out\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n", "")
                message_text = ui.join(a, message_text, ui.join(a, ui.field_text(a, &s.message), "\r\n--=_neper_out\r\nContent-Type: application/octet-stream; name=\"", ""), "")
                let file_name = ui.text_of(a, s.attach_name[0usize..], s.attach_name_len)
                message_text = ui.join(a, message_text, ui.join(a, file_name, "\"\r\nContent-Disposition: attachment; filename=\"", ""), "")
                message_text = ui.join(a, message_text, ui.join(a, file_name, "\"\r\nContent-Transfer-Encoding: base64\r\n\r\n", ""), "")
                message_text = ui.join(a, message_text, ui.join(a, wrap_base64(a, s.attach_data[0usize..s.attach_len]), "\r\n--=_neper_out--\r\n", ""), "")
            } else {
                message_text = ui.join(a, message_text, ui.join(a, "\r\n\r\n", ui.field_text(a, &s.message), "\r\n"), "")
            }
            var state = io.SliceReader { data: message_text, off: 0usize }
            let recipients: [1]str = [1]str{ to }
            let (sent, send_error) = smtp.send(&sess, sender, recipients[0usize..1usize], io.slice_reader(&state), u64(message_text.len))
            if send_error == ok { code = usize(sent.reply.code) }
            let bye = smtp.quit(&sess)
        }
    }
    let closed = netclient.close()
    if code != 0usize && secure { ui.say("mail smtp tls\n") }
    ret code
}

// (C158) What the server holds in Sent after a send: the last message is fetched back and its attachment read, so the
// check is on what arrived, not on what was sent. Says `mail sent verified <name> <size>` when the attachment is there.
fn verify_sent(a: *mem.Arena, s: *State) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var verified = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            let (sent_box, select_error) = imap.select(&sess, "Sent")
            ui.say("mail verify select ")
            ui.say_num(usize(sent_box.exists))
            ui.say(" fetch\n")
            if select_error == ok && sent_box.exists > 0u32 {
                let (items, fetch_error) = imap.fetch(&sess, "1:*", "(FLAGS BODY.PEEK[])", false)
                ui.say("mail verify items ")
                ui.say_num(items.len)
                ui.say("\n")
                if fetch_error == ok && items.len > 0usize {
                    let (raw, has_raw) = imap.section(items[items.len - 1usize], "BODY[]")
                    ui.say("mail verify raw ")
                    ui.say_num(raw.len)
                    ui.say("\n")
                    if has_raw {
                        var state = io.SliceReader { data: raw, off: 0usize }
                        let (message, message_error) = mailfmt.read_message(a, io.slice_reader(&state), 4096usize)
                        ui.say("mail verify message\n")
                        if message_error == ok {
                            let (file_name, data, found) = find_attachment(a, message.headers, message.body)
                            if found {
                                ui.say("mail sent verified ")
                                ui.say_text(file_name)
                                ui.say(" ")
                                ui.say_num(data.len)
                                ui.say("\n")
                                verified = true
                            }
                        }
                    }
                }
            }
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret verified
}

// (C158) The whole raw message `i` came from, fetched again from the server by its UID.
fn fetch_raw(a: *mem.Arena, s: *State, i: usize) -> (str, bool) {
    let m = s.mails[i]
    if !m.remote { ret ("", false) }
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret ("", false) }
    var out = ""
    var got_it = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            let (picked, select_error) = imap.select(&sess, box_name(a, s))
            if select_error == ok {
                let (items, fetch_error) = imap.fetch(&sess, ui.number(a, m.uid), "(BODY.PEEK[])", true)
                if fetch_error == ok && items.len > 0usize {
                    let (raw, has_raw) = imap.section(items[0usize], "BODY[]")
                    if has_raw {
                        out = raw
                        got_it = true
                    }
                }
            }
            let bye = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret (out, got_it)
}

// Whether `whole` ends with `suffix`.
fn ends_with(whole: str, suffix: str) -> bool {
    if whole.len < suffix.len { ret false }
    var i = 0usize
    while i < suffix.len {
        if whole[whole.len - suffix.len + i] != suffix[i] { ret false }
        i += 1usize
    }
    ret true
}

// (C158) Open in Document: the message's HTML (or plain text), or with `attachment` its attachment, is written into
// /Downloads and its path put in /handover; the app then leaves with 20000 + Document's program number and the shell
// starts Document, which reads the path (how Files opens a file).
fn open_in_document(a: *mem.Arena, s: *State, i: usize, attachment: bool) -> bool {
    let (raw, fetched) = fetch_raw(a, s, i)
    if !fetched { ret false }
    let made_dir = vaultfs.mkdir("/Downloads")
    var path = ""
    var data_text = ""
    if attachment {
        var state = io.SliceReader { data: raw, off: 0usize }
        let (message, message_error) = mailfmt.read_message(a, io.slice_reader(&state), 4096usize)
        if message_error != ok { ret false }
        let (file_name, data, found) = find_attachment(a, message.headers, message.body)
        if !found || data.len == 0usize { ret false }
        path = ui.join(a, "/Downloads/", file_name, "")
        data_text = data
    } else {
        var found: Found = zero
        mime_walk(a, &found, raw, 0usize)
        if found.has_html {
            path = ui.join(a, ui.join(a, "/Downloads/mail-", ui.number(a, s.mails[i].uid), ""), ".html", "")
            data_text = found.html_text
        } else if found.has_plain {
            path = ui.join(a, ui.join(a, "/Downloads/mail-", ui.number(a, s.mails[i].uid), ""), ".txt", "")
            data_text = found.plain
        } else {
            ret false
        }
    }
    if data_text.len == 0usize || path.len > 63usize { ret false }
    if !vaultfs.write_big(path, mem.address_of(&data_text[0usize]), data_text.len) { ret false }
    var buffer: [64]u8 = zero
    var n = 0usize
    while n < path.len {
        buffer[n] = path[n]
        n += 1usize
    }
    if !vaultfs.write("/handover", mem.address_of(&buffer[0usize]), n) { ret false }
    s.handover = 40usize
    // A picture goes to Photos (22), anything else to Document.
    if ends_with(path, ".png") || ends_with(path, ".jpg") || ends_with(path, ".jpeg") { s.handover = 22usize }
    ui.say("mail handover ")
    ui.say_text(path)
    ui.say("\n")
    ret true
}

// (C158) A search done on the server (IMAP SEARCH TEXT "words" over the shown mailbox): the UIDs it answered are kept
// in the state; false when there is no server, no login or the answer is bad.
fn search_remote(a: *mem.Arena, s: *State, words: str) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var done = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            let (picked, select_error) = imap.select(&sess, box_name(a, s))
            if select_error == ok {
                let (found, search_error) = imap.search(&sess, ui.join(a, "TEXT \"", words, "\""), true)
                if search_error == ok {
                    s.filter_total = 0usize
                    var i = 0usize
                    while i < found.len && s.filter_total < 20usize {
                        s.filter_uids[s.filter_total] = usize(found[i])
                        s.filter_total += 1usize
                        i += 1usize
                    }
                    done = true
                }
            }
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret done
}

// (C158) Archive message `uid` on the server: copied to the Archive mailbox, then flagged deleted and expunged from the
// mailbox shown.
fn remote_archive(a: *mem.Arena, s: *State, uid: usize) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var done = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
            let (picked, select_error) = imap.select(&sess, box_name(a, s))
            if select_error == ok {
                let (copied, copy_error) = imap.run(&sess, ui.join(a, "UID COPY ", ui.number(a, uid), " Archive"), "", false)
                if copy_error == ok {
                    if imap.store(&sess, ui.number(a, uid), "+FLAGS.SILENT (\\Deleted)", true) == ok {
                        let (removed, expunge_error) = imap.expunge(&sess)
                        done = expunge_error == ok
                    }
                }
            }
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret done
}

// (C158) Save the whole attachment of message `i` into /Downloads: the message is fetched again by its UID, the part
// decoded and written, and the size read back. The size saved, or 0 when it was not.
fn save_attachment(a: *mem.Arena, s: *State, i: usize) -> usize {
    let m = s.mails[i]
    let name = ui.text_of(a, m.att_name[0usize..], m.att_name_len)
    let dest = ui.join(a, "/Downloads/", name, "")
    let made_dir = vaultfs.mkdir("/Downloads")
    var written = false
    if m.remote {
        let (link, secure) = mail_connect(8993u16, 8143u16)
        if link == netproto.R_OK {
            let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
            if connect_error == ok {
                var sess = session
                if imap.login(&sess, account_user(a, s), account_pass(a, s)) == ok {
                    let (picked, select_error) = imap.select(&sess, box_name(a, s))
                    if select_error == ok {
                        let (items, fetch_error) = imap.fetch(&sess, ui.number(a, m.uid), "(BODY.PEEK[])", true)
                        if fetch_error == ok && items.len > 0usize {
                            let (raw, has_raw) = imap.section(items[0usize], "BODY[]")
                            if has_raw {
                                var state = io.SliceReader { data: raw, off: 0usize }
                                let (message, message_error) = mailfmt.read_message(a, io.slice_reader(&state), 4096usize)
                                if message_error == ok {
                                    let (file_name, data, found) = find_attachment(a, message.headers, message.body)
                                    if found && data.len > 0usize { written = vaultfs.write_big(dest, mem.address_of(&data[0usize]), data.len) }
                                }
                            }
                        }
                    }
                    let out = imap.logout(&sess)
                }
            }
            let closed = netclient.close()
        }
    }
    if !written && m.att_len > 0usize && m.att_len == m.att_size { written = vaultfs.write_big(dest, mem.address_of(&s.mails[i].att_data[0usize]), m.att_len) }
    if !written { ret 0usize }
    let (size, kind_of, extra, found_after) = vaultfs.stat(dest)
    if !found_after || size != m.att_size { ret 0usize }
    ret size
}

// The highest UID among the messages that came from the server's mailbox shown.
fn highest_uid(s: *State) -> usize {
    var top = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        if s.mails[i].used && s.mails[i].remote && s.mails[i].folder == INBOX && s.mails[i].uid > top { top = s.mails[i].uid }
        i += 1usize
    }
    ret top
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

// (C158) Where a subject starts once `Re:`, `Fwd:` and `Fw:` (any case) and the spaces after them are skipped.
fn subject_start(a: *mem.Arena, s: *State, i: usize) -> usize {
    let subject = subject_of(a, s, i)
    var at = 0usize
    var again = true
    while again {
        again = false
        while at < subject.len && subject[at] == 32u8 { at += 1usize }
        if extract.starts_fold(subject, at, "re:") {
            at += 3usize
            again = true
        } else if extract.starts_fold(subject, at, "fwd:") {
            at += 4usize
            again = true
        } else if extract.starts_fold(subject, at, "fw:") {
            at += 3usize
            again = true
        }
    }
    ret at
}

// (C158) Two messages of one mailbox folder are one thread when their subjects match once the reply prefixes are off.
fn same_thread(a: *mem.Arena, s: *State, x: usize, y: usize) -> bool {
    if s.mails[x].folder != s.mails[y].folder { ret false }
    let sx = subject_of(a, s, x)
    let sy = subject_of(a, s, y)
    var px = subject_start(a, s, x)
    var py = subject_start(a, s, y)
    if sx.len - px != sy.len - py { ret false }
    while px < sx.len {
        if extract.fold(sx[px]) != extract.fold(sy[py]) { ret false }
        px += 1usize
        py += 1usize
    }
    ret true
}

fn thread_count(a: *mem.Arena, s: *State, head: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        if s.mails[i].used && same_thread(a, s, head, i) { n += 1usize }
        i += 1usize
    }
    ret n
}

// The messages of the folder shown, newest first; a thread shows as its newest message.
fn build_list(a: *mem.Arena, s: *State) {
    s.list_total = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        let m = s.mails[i]
        if m.used {
            var keep = false
            if s.folder == STARRED { keep = m.starred && m.folder != TRASH } else { keep = m.folder == s.folder }
            if keep && s.filtering {
                // (C158) A search is on: only what the server answered.
                var listed = false
                var f = 0usize
                while f < s.filter_total {
                    if m.remote && s.filter_uids[f] == m.uid { listed = true }
                    f += 1usize
                }
                keep = listed
            }
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
    // (C158) Threads: of the messages that share a thread only the newest stays in the list.
    var kept = 0usize
    var pos = 0usize
    while pos < s.list_total {
        let candidate = s.list[pos]
        var dup = false
        var k = 0usize
        while k < kept {
            if same_thread(a, s, s.list[k], candidate) { dup = true }
            k += 1usize
        }
        if !dup {
            s.list[kept] = candidate
            kept += 1usize
        }
        pos += 1usize
    }
    s.list_total = kept
}

// (C158) The messages of the thread of `head`, oldest first.
fn build_thread(a: *mem.Arena, s: *State, head: usize) {
    s.thread_total = 0usize
    var i = 0usize
    while i < MAX_MAILS {
        if s.mails[i].used && same_thread(a, s, head, i) && s.thread_total < 8usize {
            var at = s.thread_total
            s.thread_total += 1usize
            while at > 0usize && s.mails[s.thread_list[at - 1usize]].ago < s.mails[i].ago {
                s.thread_list[at] = s.thread_list[at - 1usize]
                at -= 1usize
            }
            s.thread_list[at] = i
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
    build_list(a, s)
    var heading = "Mail"
    if s.box != 0usize { heading = box_name(a, s) }
    try ui.put(a, builder, faces.jost_bold, 30.0, heading, 20.0, 20.0, ui.light())
    if s.filtering {
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, "Search: ", ui.text_of(a, s.filter_words[0usize..], s.filter_words_len), ""), 22.0, 54.0, ui.amber())
    } else if unread_count(s) > 0usize {
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.number(a, unread_count(s)), " unread", ""), 22.0, 54.0, ui.light_muted())
    }
    // (C158) The mailboxes and accounts, and the search of the mailbox on the server.
    try ui.pill(a, builder, &s.hits, faces, 160usize, 308.0, 20.0, 88.0, 34.0, "Boxes", ui.soft(), 14.0)
    var find_label = "Find"
    if s.filtering { find_label = "Clear" }
    try ui.pill(a, builder, &s.hits, faces, 170usize, 212.0, 20.0, 88.0, 34.0, find_label, ui.soft(), 14.0)
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
        var shown_subject = subject_of(a, s, i)
        let in_thread = thread_count(a, s, i)
        if in_thread > 1usize { shown_subject = ui.join(a, ui.join(a, "(", ui.number(a, in_thread), ") "), shown_subject, "") }
        try ui.clipped(a, builder, face, 15.0, shown_subject, 80.0, y + 28.0, 270.0, ui.ink())
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
    if m.rich_total > 0usize {
        // (C158) An HTML message: its lines by kind (headings, bullets, links, the inline picture).
        try ui.card(a, builder, 16.0, y, 380.0, 460.0, 18.0, ui.cream())
        var ry: f32 = y + 16.0
        var line_at = 0usize
        while line_at < m.rich_total {
            let rl = m.rich[line_at]
            let words = ui.text_of(a, rl.text[0usize..], rl.len)
            if rl.kind == R_H1 {
                try ui.put(a, builder, faces.jost_bold, 26.0, words, 32.0, ry, ui.ink())
                ry += 36.0
            } else if rl.kind == R_H2 {
                try ui.put(a, builder, faces.jost_bold, 20.0, words, 32.0, ry, ui.ink())
                ry += 30.0
            } else if rl.kind == R_LINK {
                try ui.put(a, builder, faces.jost, 17.0, words, 32.0, ry, ui.amber_dark())
                ry += 26.0
            } else if rl.kind == R_IMAGE {
                var picture_w: f32 = m.img_w * 3.0
                var picture_h: f32 = m.img_h * 3.0
                if picture_w > 180.0 {
                    picture_h = picture_h * 180.0 / picture_w
                    picture_w = 180.0
                }
                try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: m.img_tex, source: geometry.rect(0.0, 0.0, m.img_w, m.img_h), destination: geometry.rect(32.0, ry, picture_w, picture_h), opacity: 1.0 } })
                ry += picture_h + 12.0
                ui.say("mail image drawn\n")
            } else {
                try ui.put(a, builder, faces.jost, 17.0, words, 32.0, ry, ui.ink())
                ry += 26.0
            }
            line_at += 1usize
        }
    } else {
        try ui.card(a, builder, 16.0, y, 380.0, 280.0, 18.0, ui.cream())
        let (body_box, body_error) = ui.wrapped(a, builder, faces.jost, 17.0, body_of(a, s, s.open), 32.0, y + 18.0, 348.0, 9u32, ui.ink())
        if body_error != ok { ret body_error }
    }
    // (C158) An attachment is a chip below the message; a tap saves it into /Downloads.
    if m.att_name_len > 0usize {
        try ui.card(a, builder, 16.0, 700.0, 288.0, 48.0, 14.0, ui.cream())
        try ui.clipped(a, builder, faces.jost, 16.0, ui.join(a, ui.text_of(a, m.att_name[0usize..], m.att_name_len), ui.join(a, " (", ui.number(a, m.att_size), " bytes)"), ""), 28.0, 714.0, 264.0, ui.ink())
        ui.hit(&s.hits, 540usize, 16.0, 700.0, 288.0, 48.0)
        // (C158) Open: the attachment is saved and handed over to Document.
        try ui.pill(a, builder, &s.hits, faces, 541usize, 316.0, 700.0, 80.0, 48.0, "Open", ui.amber(), 16.0)
    }
    try ui.pill(a, builder, &s.hits, faces, 530usize, 16.0, 830.0, 140.0, 48.0, "Reply", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 550usize, 172.0, 830.0, 140.0, 48.0, "Copy", ui.amber(), 17.0)
    // (C158) Done on the server: mark the message unread again, or move it to the Archive mailbox.
    if m.remote {
        try ui.pill(a, builder, &s.hits, faces, 560usize, 16.0, 770.0, 140.0, 48.0, "Unread", ui.soft(), 17.0)
        try ui.pill(a, builder, &s.hits, faces, 570usize, 172.0, 770.0, 140.0, 48.0, "Archive", ui.soft(), 17.0)
        try ui.pill(a, builder, &s.hits, faces, 580usize, 328.0, 770.0, 68.0, 48.0, "Doc", ui.soft(), 17.0)
    }
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
    // (C158) An attachment from Files: the picker, and what is attached (a tap on it takes it off).
    try ui.pill(a, builder, &s.hits, faces, 1303usize, 16.0, 404.0, 186.0, 40.0, "Attach", ui.soft(), 16.0)
    if s.attach_len > 0usize {
        try ui.card(a, builder, 16.0, 452.0, 380.0, 40.0, 14.0, ui.cream())
        try ui.clipped(a, builder, faces.jost, 16.0, ui.join(a, ui.text_of(a, s.attach_name[0usize..], s.attach_name_len), ui.join(a, " (", ui.number(a, s.attach_len), " bytes)"), ""), 30.0, 462.0, 340.0, ui.ink())
        ui.hit(&s.hits, 1304usize, 16.0, 452.0, 380.0, 40.0)
    }
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

// (C158) The messages of one thread, oldest first.
fn draw_thread(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 1400usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 26.0, ui.join(a, "Thread of ", ui.number(a, s.thread_total), ""), 62.0, 20.0, ui.light())
    var pos = 0usize
    while pos < s.thread_total {
        let i = s.thread_list[pos]
        let m = s.mails[i]
        let y: f32 = 96.0 + f32(pos) * 74.0
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 68.0, 18.0, ui.cream())
        try avatar(a, builder, faces, 48.0, y + 36.0, 20.0, from_of(a, s, i), i)
        try ui.clipped(a, builder, faces.jost_bold, 16.0, from_of(a, s, i), 80.0, y + 8.0, 200.0, ui.ink())
        try ui.clipped(a, builder, faces.jost, 15.0, subject_of(a, s, i), 80.0, y + 28.0, 270.0, ui.ink())
        try ui.clipped(a, builder, faces.grotesk, 12.0, body_of(a, s, i), 80.0, y + 49.0, 290.0, ui.muted())
        try ui.put_right(a, builder, faces.grotesk, 11.0, ui.ago_text(a, m.ago), 380.0, y + 12.0, ui.muted())
        ui.hit(&s.hits, 1410usize + pos, 16.0, y + 2.0, 380.0, 68.0)
        pos += 1usize
    }
    ret ok
}

// (C158) The accounts and the mailboxes of the account in use.
fn draw_boxes(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 1600usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 26.0, "Mailboxes", 62.0, 20.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "Accounts", 24.0, 76.0, ui.light_muted())
    var at = 0usize
    while at < s.account_total {
        let y: f32 = 96.0 + f32(at) * 52.0
        if at == s.account { try ui.card(a, builder, 14.0, y - 2.0, 384.0, 48.0, 16.0, ui.amber()) }
        try ui.card(a, builder, 16.0, y, 380.0, 44.0, 14.0, ui.cream())
        let c = s.accounts[at]
        try ui.put(a, builder, faces.jost, 17.0, ui.join(a, ui.text_of(a, c.user[0usize..], c.user_len), "@neper.test", ""), 32.0, y + 11.0, ui.ink())
        ui.hit(&s.hits, 1700usize + at, 16.0, y, 380.0, 44.0)
        at += 1usize
    }
    if s.account_total < MAX_ACCOUNTS {
        try ui.pill(a, builder, &s.hits, faces, 1750usize, 16.0, 96.0 + f32(s.account_total) * 52.0, 170.0, 40.0, "Add account", ui.amber(), 16.0)
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Folders", 24.0, 290.0, ui.light_muted())
    var b = 0usize
    while b < s.box_total {
        let y: f32 = 312.0 + f32(b) * 52.0
        if b == s.box { try ui.card(a, builder, 14.0, y - 2.0, 384.0, 48.0, 16.0, ui.amber()) }
        try ui.card(a, builder, 16.0, y, 380.0, 44.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, ui.text_of(a, s.boxes[b][0usize..], s.box_lens[b]), 32.0, y + 11.0, ui.ink())
        ui.hit(&s.hits, 1800usize + b, 16.0, y, 380.0, 44.0)
        b += 1usize
    }
    ret ok
}

// (C158) The add-account form: a user and a password on the on-screen keyboard.
fn draw_account(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Add account", 24.0, 14.0, ui.light())
    try compose_field(a, builder, s, faces, 0usize, "User", ui.field_text(a, &s.form_user), 76.0, 44.0)
    let typed_pass = ui.field_text(a, &s.form_pass)
    var masked = ""
    var dots = 0usize
    while dots < typed_pass.len && dots < 16usize {
        masked = ui.join(a, masked, "*", "")
        dots += 1usize
    }
    try compose_field(a, builder, s, faces, 1usize, "Password", masked, 144.0, 44.0)
    try ui.pill(a, builder, &s.hits, faces, 1760usize, 16.0, 212.0, 186.0, 46.0, "Sign in", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 1761usize, 210.0, 212.0, 186.0, 46.0, "Cancel", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

// (C158) The search of the shown mailbox on the server: the words and the keyboard.
fn draw_search(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Search mail", 24.0, 14.0, ui.light())
    s.focus = 0usize
    try compose_field(a, builder, s, faces, 0usize, ui.join(a, "In ", box_name(a, s), ""), ui.field_text(a, &s.search), 76.0, 44.0)
    try ui.pill(a, builder, &s.hits, faces, 1770usize, 210.0, 140.0, 186.0, 46.0, "Cancel", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Search")
    ret ok
}

// (C158) The files of /Downloads, to attach one.
fn draw_pick(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Attach a file", 24.0, 20.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "Files in Downloads", 24.0, 66.0, ui.light_muted())
    var at = 0usize
    while at < s.pick_total {
        let y: f32 = 92.0 + f32(at) * 56.0
        try ui.card(a, builder, 16.0, y, 380.0, 48.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, ui.text_of(a, s.pick_names[at][0usize..], s.pick_lens[at]), 32.0, y + 12.0, ui.ink())
        ui.hit(&s.hits, 1900usize + at, 16.0, y, 380.0, 48.0)
        at += 1usize
    }
    if s.pick_total == 0usize { try ui.centred(a, builder, faces.jost, 18.0, "No files in Downloads", 206.0, 200.0, ui.light_muted()) }
    try ui.pill(a, builder, &s.hits, faces, 1950usize, 16.0, 800.0, 150.0, 48.0, "Cancel", ui.soft(), 17.0)
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
    } else if s.screen == THREAD_SCREEN {
        try draw_thread(a, builder, s, faces)
    } else if s.screen == BOXES_SCREEN {
        try draw_boxes(a, builder, s, faces)
    } else if s.screen == ACCOUNT_SCREEN {
        try draw_account(a, builder, s, faces)
    } else if s.screen == PICK_SCREEN {
        try draw_pick(a, builder, s, faces)
    } else if s.screen == SEARCH_SCREEN {
        try draw_search(a, builder, s, faces)
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

// Open message `which`: it is read now, and the server is told when it came from there.
fn open_message(a: *mem.Arena, s: *State, which: usize) {
    s.open = which
    let was_unread = s.mails[s.open].unread
    s.mails[s.open].unread = false
    s.screen = VIEW_SCREEN
    if was_unread && s.mails[s.open].remote {
        if remote_flag(a, s, s.mails[s.open].uid, "+FLAGS.SILENT (\\Seen)", false) {
            ui.say("mail server read ")
            ui.say_text(ui.number(a, s.mails[s.open].uid))
            ui.say("\n")
        }
    }
    ui.say("mail opened ")
    ui.say_text(subject_of(a, s, s.open))
    ui.say("\n")
}

// (C158) Whether the server takes a user and password: connect, log in, log out.
fn try_login(a: *mem.Arena, user: str, word: str) -> bool {
    let (link, secure) = mail_connect(8993u16, 8143u16)
    if link != netproto.R_OK { ret false }
    var accepted = false
    let (session, connect_error) = imap.connect(a, net_reader(), net_writer(), 65536usize)
    if connect_error == ok {
        var sess = session
        if imap.login(&sess, user, word) == ok {
            accepted = true
            let out = imap.logout(&sess)
        }
    }
    let closed = netclient.close()
    ret accepted
}

// (C158) The accounts after the built-in one are kept in /mail_accounts as `user<TAB>password<LF>` lines.
fn save_accounts(s: *State) {
    var buf: [128]u8 = zero
    var n = 0usize
    var i = 1usize
    while i < s.account_total {
        let c = s.accounts[i]
        var k = 0usize
        while k < c.user_len {
            buf[n] = c.user[k]
            n += 1usize
            k += 1usize
        }
        buf[n] = 9u8
        n += 1usize
        k = 0usize
        while k < c.pass_len {
            buf[n] = c.pass[k]
            n += 1usize
            k += 1usize
        }
        buf[n] = 10u8
        n += 1usize
        i += 1usize
    }
    let written = vaultfs.write_big("/mail_accounts", mem.address_of(&buf[0usize]), n)
}

fn load_accounts(s: *State) -> usize {
    var buf: [128]u8 = zero
    let (n, found) = vaultfs.read_big("/mail_accounts", mem.address_of(&buf[0usize]), 128usize)
    if !found || n == 0usize { ret 0usize }
    var loaded = 0usize
    var at = 0usize
    while at < n && s.account_total < MAX_ACCOUNTS {
        var tab = at
        while tab < n && buf[tab] != 9u8 && buf[tab] != 10u8 { tab += 1usize }
        var end = tab
        while end < n && buf[end] != 10u8 { end += 1usize }
        if tab < n && buf[tab] == 9u8 && tab > at && tab - at < 16usize && end - tab - 1usize < 16usize {
            var c: Account = zero
            var k = 0usize
            while at + k < tab {
                c.user[k] = buf[at + k]
                k += 1usize
            }
            c.user_len = k
            k = 0usize
            while tab + 1usize + k < end {
                c.pass[k] = buf[tab + 1usize + k]
                k += 1usize
            }
            c.pass_len = k
            s.accounts[s.account_total] = c
            s.account_total += 1usize
            loaded += 1usize
        }
        at = end + 1usize
    }
    ret loaded
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, kit: *appkit.Kit, s: *State, id: usize) -> bool {
    if s.screen == SEARCH_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                let words = ui.field_text(a, &s.search)
                if words.len > 0usize && words.len <= 24usize && search_remote(a, s, words) {
                    var w = 0usize
                    while w < words.len {
                        s.filter_words[w] = words[w]
                        w += 1usize
                    }
                    s.filter_words_len = w
                    s.filtering = true
                    ui.say("mail search ")
                    ui.say_text(words)
                    ui.say(" ")
                    ui.say_num(s.filter_total)
                    ui.say("\n")
                    s.folder = INBOX
                    s.screen = LIST_SCREEN
                }
                ret true
            }
            ret ui.field_key(&s.search, id, false)
        }
        if id == 1500usize {
            ret false
        }
        if id == 1770usize {
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == THREAD_SCREEN {
        if id == 1400usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id >= 1410usize && id < 1418usize && id - 1410usize < s.thread_total {
            s.from_thread = true
            open_message(a, s, s.thread_list[id - 1410usize])
            ret true
        }
        ret false
    }
    if s.screen == BOXES_SCREEN {
        if id == 1600usize {
            s.screen = LIST_SCREEN
            ret true
        }
        if id >= 1700usize && id < 1700usize + MAX_ACCOUNTS && id - 1700usize < s.account_total {
            s.account = id - 1700usize
            s.box = 0usize
            s.box_total = 0usize
            ui.say("mail account ")
            ui.say_text(account_user(a, s))
            ui.say("\n")
            let synced = sync_inbox(a, kit, s)
            ui.say("mail synced ")
            ui.say_num(synced)
            ui.say("\n")
            s.folder = INBOX
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 1750usize && s.account_total < MAX_ACCOUNTS {
            s.form_user.len = 0usize
            s.form_pass.len = 0usize
            s.focus = 0usize
            s.screen = ACCOUNT_SCREEN
            ret true
        }
        if id >= 1800usize && id < 1800usize + MAX_BOXES && id - 1800usize < s.box_total {
            s.box = id - 1800usize
            ui.say("mail box ")
            ui.say_text(box_name(a, s))
            ui.say("\n")
            let synced = sync_inbox(a, kit, s)
            ui.say("mail synced ")
            ui.say_num(synced)
            ui.say("\n")
            s.folder = INBOX
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == ACCOUNT_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.focus == 0usize { s.focus = 1usize }
                ret true
            }
            var field = &s.form_user
            if s.focus == 1usize { field = &s.form_pass }
            ret ui.field_key(field, id, false)
        }
        if id >= 1500usize && id < 1502usize {
            s.focus = id - 1500usize
            ret true
        }
        if id == 1761usize {
            s.screen = BOXES_SCREEN
            ret true
        }
        if id == 1760usize {
            let typed_user = ui.field_text(a, &s.form_user)
            let typed_pass = ui.field_text(a, &s.form_pass)
            if typed_user.len == 0usize || typed_user.len > 15usize || typed_pass.len > 15usize { ret true }
            if !try_login(a, typed_user, typed_pass) {
                ui.say("mail account refused ")
                ui.say_text(typed_user)
                ui.say("\n")
                ret true
            }
            var slot = s.account_total
            var u = 0usize
            while u < typed_user.len {
                s.accounts[slot].user[u] = typed_user[u]
                u += 1usize
            }
            s.accounts[slot].user_len = u
            var p = 0usize
            while p < typed_pass.len {
                s.accounts[slot].pass[p] = typed_pass[p]
                p += 1usize
            }
            s.accounts[slot].pass_len = p
            s.account_total += 1usize
            save_accounts(s)
            s.account = slot
            s.box = 0usize
            s.box_total = 0usize
            ui.say("mail account added ")
            ui.say_text(typed_user)
            ui.say("\n")
            let synced = sync_inbox(a, kit, s)
            ui.say("mail synced ")
            ui.say_num(synced)
            ui.say("\n")
            s.folder = INBOX
            s.screen = LIST_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == PICK_SCREEN {
        if id == 1950usize {
            s.screen = COMPOSE_SCREEN
            ret true
        }
        if id >= 1900usize && id < 1906usize && id - 1900usize < s.pick_total {
            let which = id - 1900usize
            let file_name = ui.text_of(a, s.pick_names[which][0usize..], s.pick_lens[which])
            let path = ui.join(a, "/Downloads/", file_name, "")
            let (size, kind_of, extra, found) = vaultfs.stat(path)
            if found && size > 0usize && size <= ATTACH_MAX {
                let (got, read_ok) = vaultfs.read_big(path, mem.address_of(&s.attach_data[0usize]), ATTACH_MAX)
                if read_ok && got == size {
                    var n = 0usize
                    while n < file_name.len && n < 24usize {
                        s.attach_name[n] = file_name[n]
                        n += 1usize
                    }
                    s.attach_name_len = n
                    s.attach_len = got
                    ui.say("mail attached ")
                    ui.say_text(file_name)
                    ui.say(" ")
                    ui.say_num(got)
                    ui.say("\n")
                }
            }
            s.screen = COMPOSE_SCREEN
            ret true
        }
        ret false
    }
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
                    if s.attach_len > 0usize {
                        // (C158) What the server holds in Sent is read back: the attachment must be in it.
                        let confirmed = verify_sent(a, s)
                    }
                }
                s.attach_len = 0usize
                s.attach_name_len = 0usize
                s.folder = SENT
                s.screen = LIST_SCREEN
            }
            ret true
        }
        if id == 1303usize {
            // The picker lists /Downloads (names separated by newlines).
            var names: [256]u8 = zero
            let (name_bytes, listed) = vaultfs.list("/Downloads", mem.address_of(&names[0usize]), 256usize)
            s.pick_total = 0usize
            if listed {
                var start = 0usize
                var at = 0usize
                while at < name_bytes && s.pick_total < 6usize {
                    if names[at] == 10u8 {
                        var w = 0usize
                        while start + w < at && w < 24usize {
                            s.pick_names[s.pick_total][w] = names[start + w]
                            w += 1usize
                        }
                        s.pick_lens[s.pick_total] = w
                        s.pick_total += 1usize
                        start = at + 1usize
                    }
                    at += 1usize
                }
            }
            s.screen = PICK_SCREEN
            ui.say("mail picker ")
            ui.say_num(s.pick_total)
            ui.say("\n")
            ret true
        }
        if id == 1304usize {
            s.attach_len = 0usize
            s.attach_name_len = 0usize
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
            if s.from_thread { s.screen = THREAD_SCREEN }
            s.from_thread = false
            ret true
        }
        if id == 540usize && s.mails[s.open].att_name_len > 0usize {
            // (C158) Save the attachment into Files: /Downloads/<name>, checked by reading its size back.
            let m = s.mails[s.open]
            let size = save_attachment(a, s, s.open)
            if size > 0usize {
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
        if id == 541usize && s.mails[s.open].att_name_len > 0usize {
            let handed = open_in_document(a, s, s.open, true)
            ret true
        }
        if id == 580usize && s.mails[s.open].remote {
            let handed = open_in_document(a, s, s.open, false)
            ret true
        }
        if id == 560usize && s.mails[s.open].remote {
            // (C158) Mark unread: the \Seen flag is taken off on the server too.
            s.mails[s.open].unread = true
            if remote_flag(a, s, s.mails[s.open].uid, "-FLAGS.SILENT (\\Seen)", false) {
                ui.say("mail server unread ")
                ui.say_text(ui.number(a, s.mails[s.open].uid))
                ui.say("\n")
            }
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 570usize && s.mails[s.open].remote {
            // (C158) Archive: moved to the Archive mailbox on the server, gone from this one.
            if remote_archive(a, s, s.mails[s.open].uid) {
                s.mails[s.open].used = false
                ui.say("mail server archived ")
                ui.say_text(ui.number(a, s.mails[s.open].uid))
                ui.say("\n")
            }
            s.screen = LIST_SCREEN
            ret true
        }
        if id == 520usize {
            s.mails[s.open].folder = TRASH
            s.screen = LIST_SCREEN
            ui.say("mail deleted\n")
            if s.mails[s.open].remote {
                if remote_flag(a, s, s.mails[s.open].uid, "+FLAGS.SILENT (\\Deleted)", true) {
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
            // (C175) Copy: the start of the message (the clipboard holds 128 bytes) goes to the clipboard.
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
    if id == 160usize {
        s.screen = BOXES_SCREEN
        ui.say("mail boxes\n")
        ret true
    }
    if id == 170usize {
        if s.filtering {
            s.filtering = false
            ui.say("mail search cleared\n")
        } else {
            s.search.len = 0usize
            s.screen = SEARCH_SCREEN
        }
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_MAILS {
        let which = id - 200usize
        s.from_thread = false
        // (C158) A thread of several messages opens as the list of them.
        let members = thread_count(a, s, which)
        if members > 1usize {
            s.thread_head = which
            build_thread(a, s, which)
            s.screen = THREAD_SCREEN
            ui.say("mail thread ")
            ui.say_num(members)
            ui.say(" ")
            ui.say_text(subject_of(a, s, which))
            ui.say("\n")
            ret true
        }
        open_message(a, s, which)
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
    // (C158) The built-in test account and its INBOX; the accounts added in the app come back from /mail_accounts.
    let built_user = "neper"
    let built_pass = "secret"
    var b = 0usize
    while b < built_user.len {
        s.accounts[0usize].user[b] = built_user[b]
        b += 1usize
    }
    s.accounts[0usize].user_len = built_user.len
    b = 0usize
    while b < built_pass.len {
        s.accounts[0usize].pass[b] = built_pass[b]
        b += 1usize
    }
    s.accounts[0usize].pass_len = built_pass.len
    s.account_total = 1usize
    let inbox_name = "INBOX"
    b = 0usize
    while b < inbox_name.len {
        s.boxes[0usize][b] = inbox_name[b]
        b += 1usize
    }
    s.box_lens[0usize] = inbox_name.len
    s.box_total = 1usize
    let restored = load_accounts(&s)
    if restored > 0usize {
        ui.say("mail accounts ")
        ui.say_num(s.account_total)
        ui.say("\n")
    }
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
    let synced = sync_inbox(a, &kit, &s)
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
            // (C158) Push by polling: with the list in front the inbox is fetched again every 30 s; a message with a
            // UID above the highest seen is new, and is counted as a notification (once).
            var fresh = false
            if s.screen == LIST_SCREEN && s.account_total > 0usize {
                let (now_mono, mono_error) = time.monotonic()
                if mono_error == ok {
                    let now_ms = usize(now_mono.nanos / 1000000i64)
                    if s.last_poll_ms == 0usize {
                        s.last_poll_ms = now_ms
                        s.max_uid = highest_uid(&s)
                    }
                    if now_ms - s.last_poll_ms >= 30000usize {
                        s.last_poll_ms = now_ms
                        let before = highest_uid(&s)
                        let polled = sync_inbox(a, &kit, &s)
                        var arrived = 0usize
                        var m_at = 0usize
                        while m_at < MAX_MAILS {
                            if s.mails[m_at].used && s.mails[m_at].remote && s.mails[m_at].uid > before && s.mails[m_at].folder == INBOX { arrived += 1usize }
                            m_at += 1usize
                        }
                        if arrived > 0usize {
                            ui.say("mail new ")
                            ui.say_num(arrived)
                            ui.say("\n")
                            bgclient.notify()
                            ui.say("mail notified ")
                            ui.say_num(arrived)
                            ui.say("\n")
                            fresh = true
                        }
                    }
                }
            }
            if fresh {
                if !show(a, &kit, &s) {
                    ui.say("mail present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("mail home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &kit, &s, id) {
                if s.handover != 0usize {
                    appkit.leave()
                    running = false
                } else if !show(a, &kit, &s) {
                    ui.say("mail present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    if s.handover != 0usize { os.exit(i32(20000usize + s.handover)) }
    ret ok
}
