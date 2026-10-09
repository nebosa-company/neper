// e.net.imap (L083, D2276): a scripted IMAP server compared byte for byte (CAPABILITY, LOGIN with quoting,
// AUTHENTICATE PLAIN, SELECT, LIST with a literal name, SEARCH and UID SEARCH, FETCH with literals, NIL and
// nested lists, STORE, EXPUNGE, NO/BAD, PREAUTH, LOGINDISABLED, injection guard, size limit) and a live
// STARTTLS session against a server thread over pipes that checks the decrypted commands it receives.
use e.io
use e.mem
use e.net.imap as imap
use e.net.tls as tls
use e.os
use e.time

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fail(code: i32) -> err {
    let _ = io.print("net imap failed at ")
    var digits: [4]u8 = zero
    digits[0] = u8(48i32 + code / 100i32)
    digits[1] = u8(48i32 + (code / 10i32) % 10i32)
    digits[2] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..3])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

type Scene = struct { sent: [4096]u8, writer: io.SliceWriter, reader: io.SliceReader }

type Job = struct { reading: *os.File, writing: *os.File, config: tls.ServerConfig, failure: i32, received: [2048]u8, received_len: usize }

fn line_from(source: *io.Reader, buf: []u8) -> (usize, err) {
    var n = 0usize
    var one: [1]u8 = zero
    while true {
        let (got, read_error) = io.read(source, one[0..])
        if read_error != ok { ret (0usize, read_error) }
        if got == 0usize { continue }
        if one[0] == 10u8 { break }
        if n < buf.len {
            buf[n] = one[0]
            n += 1usize
        }
    }
    ret (n, ok)
}

// Answer a command line: the untagged part, then the line's own tag with the completion.
fn answer(sink: *io.Writer, line: []const u8, untagged: str, completion: str) -> err {
    var tag_end = 0usize
    while tag_end < line.len && line[tag_end] != 32u8 { tag_end += 1usize }
    try io.write_all(sink, untagged)
    try io.write_all(sink, line[..tag_end])
    try io.write_all(sink, " ")
    ret io.write_all(sink, completion)
}

fn serve(job: *Job) {
    var storage: [262144]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var source = io.file_reader(job.reading)
    var sink = io.file_writer(job.writing)
    var line: [256]u8 = zero
    if io.write_all(&sink, "* OK [CAPABILITY IMAP4rev1 STARTTLS] live ready\r\n") != ok { job.failure = 101i32 }
    let (n, line_error) = line_from(&source, line[0..])
    if line_error != ok || !same(line[..n], "A1 CAPABILITY\r") { job.failure = 102i32 }
    if answer(&sink, line[..n], "* CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED\r\n", "OK done\r\n") != ok { job.failure = 103i32 }
    let (n2, line2_error) = line_from(&source, line[0..])
    if line2_error != ok || !same(line[..n2], "A2 STARTTLS\r") { job.failure = 104i32 }
    if answer(&sink, line[..n2], "", "OK Begin TLS negotiation now\r\n") != ok { job.failure = 105i32 }
    let (secure0, create_error) = tls.server(&arena, source, sink, job.config)
    if create_error != ok { job.failure = 106i32 }
    if job.failure != 0i32 { ret }
    var secure = secure0
    if tls.handshake(&secure) != ok {
        job.failure = 107i32
        ret
    }
    var secure_source = tls.reader(&secure)
    var secure_sink = tls.writer(&secure)
    var step = 0i32
    var at = 0usize
    while step < 5i32 {
        let (m, m_error) = line_from(&secure_source, line[0..])
        if m_error != ok {
            job.failure = 110i32 + step
            ret
        }
        if at + m + 1usize <= job.received.len {
            mem.copy[u8](job.received[at..], line[..m])
            job.received[at + m] = 10u8
            at += m + 1usize
        }
        var untagged = ""
        var completion = "OK done\r\n"
        if step == 0i32 { untagged = "* CAPABILITY IMAP4rev1 AUTH=PLAIN\r\n" }
        if step == 1i32 { completion = "OK LOGIN completed\r\n" }
        if step == 2i32 {
            untagged = "* 1 EXISTS\r\n* OK [UIDVALIDITY 9] v\r\n"
            completion = "OK [READ-WRITE] SELECT completed\r\n"
        }
        if step == 3i32 { untagged = "* 1 FETCH (UID 41 BODY[] {18}\r\nSubject: a\r\n\r\nhi\r\n)\r\n" }
        if step == 4i32 { untagged = "* BYE bye\r\n" }
        if answer(&secure_sink, line[..m], untagged, completion) != ok {
            job.failure = 130i32 + step
            ret
        }
        step += 1i32
    }
    job.received_len = at
    let _ = tls.close(&secure)
}

fn client_side(a: *mem.Arena, client_read: *os.File, client_write: *os.File, client_config: tls.ClientConfig) -> i32 {
    let (live0, live_error) = imap.connect(a, io.file_reader(client_read), io.file_writer(client_write), 65536usize)
    if live_error != ok { ret 30i32 }
    var live = live0
    if imap.capability(&live) != ok || !live.caps.starttls || !live.caps.login_disabled { ret 31i32 }
    if imap.login(&live, "alice", "secret") != imap.Unsupported { ret 41i32 }
    if imap.starttls(&live, client_config) != ok { ret 32i32 }
    if !live.secured || live.caps.starttls || !live.caps.auth_plain { ret 33i32 }
    if imap.starttls(&live, client_config) != imap.Unsupported { ret 34i32 }
    if imap.login(&live, "alice", "secret") != ok || !live.authenticated { ret 35i32 }
    let (box, select_error) = imap.select(&live, "INBOX")
    if select_error != ok || box.exists != 1u32 || box.uid_validity != 9u32 || box.read_only { ret 36i32 }
    let (rows, fetch_error) = imap.fetch(&live, "1", "(UID BODY.PEEK[])", false)
    if fetch_error != ok || rows.len != 1usize || rows[0].uid != 41u32 { ret 37i32 }
    let (text, has_text) = imap.section(rows[0], "BODY[]")
    if !has_text || !same(text, "Subject: a\r\n\r\nhi\r\n") { ret 42i32 }
    if imap.logout(&live) != ok { ret 38i32 }
    ret 0i32
}

fn run_live(a: *mem.Arena, server_read: *os.File, server_write: *os.File, client_read: *os.File, client_write: *os.File, leaf_der: str, leaf_pkcs8: str, mid_der: str, server_entropy: []const u8, client_entropy: []const u8) -> i32 {
    let none_protocols: [0]str = zero
    var job: Job = zero
    job.reading = server_read
    job.writing = server_write
    job.config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: none_protocols[0..], entropy: server_entropy }
    let (server_thread, thread_error) = os.thread_create[Job](serve, &job, 8388608usize)
    if thread_error != ok { ret 29i32 }
    let client_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: none_protocols[0..], entropy: client_entropy, now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let client_code = client_side(a, client_read, client_write, client_config)
    if client_code != 0i32 { os.exit(client_code) }
    let join_error = os.thread_join(server_thread)
    if join_error != ok { ret 28i32 }
    if job.failure != 0i32 { ret job.failure }
    let seen = job.received[..job.received_len]
    if !same(seen, "A3 CAPABILITY\r\nA4 LOGIN \"alice\" \"secret\"\r\nA5 SELECT \"INBOX\"\r\nA6 FETCH 1 (UID BODY.PEEK[])\r\nA7 LOGOUT\r\n") { ret 39i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var scene: Scene = zero
    scene.writer = io.SliceWriter { data: scene.sent[0..], off: 0usize }
    let replies = "* OK [CAPABILITY IMAP4rev1] IMAP4rev1 Service Ready\r\n* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN SASL-IR UIDPLUS IDLE\r\nA1 OK CAPABILITY completed\r\nA2 OK LOGIN completed\r\n* 3 EXISTS\r\n* 1 RECENT\r\n* OK [UNSEEN 2] first unseen\r\n* OK [UIDVALIDITY 3857529045] UIDs valid\r\n* OK [UIDNEXT 4392] predicted next UID\r\n* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] limited\r\nA3 OK [READ-WRITE] SELECT completed\r\n* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n* LIST (\\Noselect \\HasChildren) \"/\" {7}\r\nArchive\r\n* LIST () NIL Sent\r\nA4 OK LIST completed\r\n* SEARCH 2 5 9\r\nA5 OK SEARCH completed\r\n* SEARCH 4391\r\nA6 OK SEARCH completed\r\n* 1 FETCH (UID 4388 FLAGS (\\Seen) RFC822.SIZE 26 INTERNALDATE \"17-Jul-1996 02:44:25 -0700\" BODY[] {26}\r\nSubject: hi\r\n\r\nbody line\r\n)\r\n* 2 FETCH (UID 4389 FLAGS () BODY[] NIL)\r\n* 3 FETCH (BODY[HEADER.FIELDS (From To)] {9}\r\nFrom: a\r\n ENVELOPE (\"Mon\" \"Subj \\\"q\\\"\" NIL) UID 77)\r\nA7 OK FETCH completed\r\nA8 OK STORE completed\r\n* 1 EXPUNGE\r\n* 2 EXPUNGE\r\nA9 OK EXPUNGE completed\r\nA10 OK NOOP completed\r\nA11 OK CLOSE completed\r\n* BYE logging out\r\nA12 OK LOGOUT completed\r\n"
    scene.reader = io.SliceReader { data: replies, off: 0usize }
    let (s0, connect_error) = imap.connect(a, io.slice_reader(&scene.reader), io.slice_writer(&scene.writer), 65536usize)
    if connect_error != ok { ret fail(1i32) }
    var s = s0
    if s.authenticated { ret fail(2i32) }
    if imap.capability(&s) != ok || !s.caps.imap4rev1 || !s.caps.starttls || !s.caps.auth_plain || !s.caps.sasl_ir || !s.caps.uidplus || !s.caps.idle || s.caps.login_disabled || s.caps.move { ret fail(3i32) }
    if imap.login(&s, "alice", "se\"cret") != ok || !s.authenticated { ret fail(4i32) }
    let (box, select_error) = imap.select(&s, "INBOX")
    if select_error != ok || box.exists != 3u32 || box.recent != 1u32 || box.unseen != 2u32 || box.uid_validity != 3857529045u32 || box.uid_next != 4392u32 { ret fail(5i32) }
    if !same(box.flags, "\\Answered \\Flagged \\Deleted \\Seen \\Draft") || !same(box.permanent_flags, "\\Deleted \\Seen \\*") || box.read_only { ret fail(6i32) }
    let (names, list_error) = imap.list(&s, "", "*")
    if list_error != ok || names.len != 3usize { ret fail(7i32) }
    if !same(names[0].name, "INBOX") || !same(names[0].delimiter, "/") || !same(names[0].attributes, "\\HasNoChildren") { ret fail(8i32) }
    if !same(names[1].name, "Archive") || !same(names[1].attributes, "\\Noselect \\HasChildren") { ret fail(9i32) }
    if !same(names[2].name, "Sent") || names[2].delimiter.len != 0usize || names[2].attributes.len != 0usize { ret fail(10i32) }
    let (hits, search_error) = imap.search(&s, "UNSEEN", false)
    if search_error != ok || hits.len != 3usize || hits[0] != 2u32 || hits[1] != 5u32 || hits[2] != 9u32 { ret fail(11i32) }
    let (uids, uid_error) = imap.search(&s, "ALL", true)
    if uid_error != ok || uids.len != 1usize || uids[0] != 4391u32 { ret fail(12i32) }
    let (rows, fetch_error) = imap.fetch(&s, "1:3", "(UID FLAGS BODY.PEEK[])", false)
    if fetch_error != ok || rows.len != 3usize { ret fail(13i32) }
    if rows[0].seq != 1u32 || rows[0].uid != 4388u32 || rows[0].size != 26u32 || !same(rows[0].flags, "\\Seen") || !same(rows[0].internal_date, "17-Jul-1996 02:44:25 -0700") || !imap.has_flag(rows[0], "\\SEEN") { ret fail(14i32) }
    let (body, has_body) = imap.section(rows[0], "BODY[]")
    if !has_body || !same(body, "Subject: hi\r\n\r\nbody line\r\n") { ret fail(15i32) }
    let (_, has_nil) = imap.section(rows[1], "BODY[]")
    if has_nil || rows[1].uid != 4389u32 || rows[1].flags.len != 0usize || imap.has_flag(rows[1], "\\Seen") { ret fail(16i32) }
    let (head, has_head) = imap.section(rows[2], "BODY[HEADER.FIELDS (From To)]")
    let (envelope, has_envelope) = imap.section(rows[2], "ENVELOPE")
    if !has_head || !same(head, "From: a\r\n") || !has_envelope || !same(envelope, "(\"Mon\" \"Subj \\\"q\\\"\" NIL)") || rows[2].uid != 77u32 { ret fail(17i32) }
    if imap.store(&s, "1", "+FLAGS.SILENT (\\Deleted)", false) != ok { ret fail(18i32) }
    let (removed, expunge_error) = imap.expunge(&s)
    if expunge_error != ok || removed != 2usize { ret fail(19i32) }
    if imap.noop(&s) != ok || imap.close_mailbox(&s) != ok || imap.logout(&s) != ok { ret fail(20i32) }
    let want = "A1 CAPABILITY\r\nA2 LOGIN \"alice\" \"se\\\"cret\"\r\nA3 SELECT \"INBOX\"\r\nA4 LIST \"\" \"*\"\r\nA5 SEARCH UNSEEN\r\nA6 UID SEARCH ALL\r\nA7 FETCH 1:3 (UID FLAGS BODY.PEEK[])\r\nA8 STORE 1 +FLAGS.SILENT (\\Deleted)\r\nA9 EXPUNGE\r\nA10 NOOP\r\nA11 CLOSE\r\nA12 LOGOUT\r\n"
    if !same(scene.sent[..scene.writer.off], want) { ret fail(21i32) }

    // NO and BAD, PREAUTH, AUTHENTICATE PLAIN through a continuation, LOGINDISABLED, and what never reaches the wire
    var two: Scene = zero
    two.writer = io.SliceWriter { data: two.sent[0..], off: 0usize }
    two.reader = io.SliceReader { data: "* PREAUTH ready\r\nA1 NO [AUTHENTICATIONFAILED] bad credentials\r\nA2 BAD parse error\r\n* CAPABILITY IMAP4rev1 LOGINDISABLED AUTH=PLAIN\r\nA3 OK done\r\n+ \r\nA4 OK PLAIN authentication successful\r\n", off: 0usize }
    let (t0, t_error) = imap.connect(a, io.slice_reader(&two.reader), io.slice_writer(&two.writer), 65536usize)
    if t_error != ok { ret fail(22i32) }
    var t = t0
    if !t.authenticated { ret fail(23i32) }
    if imap.login(&t, "u", "wrong") != imap.No || !same(t.last, "NO [AUTHENTICATIONFAILED] bad credentials") { ret fail(24i32) }
    if imap.noop(&t) != imap.Bad { ret fail(25i32) }
    if imap.authenticate_plain(&t, "alice", "secret") != imap.Unsupported { ret fail(26i32) }
    if imap.capability(&t) != ok || !t.caps.login_disabled { ret fail(27i32) }
    if imap.login(&t, "u", "p") != imap.Unsupported { ret fail(28i32) }
    if imap.authenticate_plain(&t, "alice", "secret") != ok { ret fail(29i32) }
    let wrote = two.writer.off
    let (_, evil_search) = imap.search(&t, "ALL\r\nA9 LOGOUT", false)
    let (_, evil_mailbox) = imap.select(&t, "in\r\nbox")
    let (_, evil_fetch) = imap.fetch(&t, "1", "(UID)\r\n", false)
    let (_, empty_set) = imap.fetch(&t, "", "(UID)", false)
    if evil_search != imap.Invalid || evil_mailbox != imap.Invalid || evil_fetch != imap.Invalid || empty_set != imap.Invalid || imap.store(&t, "1", "\xc3\xa9", false) != imap.Invalid { ret fail(30i32) }
    if two.writer.off != wrote { ret fail(31i32) }
    let want2 = "A1 LOGIN \"u\" \"wrong\"\r\nA2 NOOP\r\nA3 CAPABILITY\r\nA4 AUTHENTICATE PLAIN\r\nAGFsaWNlAHNlY3JldA==\r\n"
    if !same(two.sent[..wrote], want2) { ret fail(32i32) }

    // greeting refusal, an oversized response, a cut connection, an unexpected continuation
    var three: Scene = zero
    three.writer = io.SliceWriter { data: three.sent[0..], off: 0usize }
    three.reader = io.SliceReader { data: "* BYE too many connections\r\n", off: 0usize }
    let (_, bye_error) = imap.connect(a, io.slice_reader(&three.reader), io.slice_writer(&three.writer), 65536usize)
    if bye_error != imap.Rejected { ret fail(33i32) }
    var four: Scene = zero
    four.writer = io.SliceWriter { data: four.sent[0..], off: 0usize }
    four.reader = io.SliceReader { data: "* OK hi\r\n* 1 FETCH (BODY[] {100}\r\n0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789\r\n)\r\nA1 OK done\r\n", off: 0usize }
    let (f0, f_error) = imap.connect(a, io.slice_reader(&four.reader), io.slice_writer(&four.writer), 64usize)
    var f = f0
    let (_, big_error) = imap.fetch(&f, "1", "(BODY[])", false)
    if f_error != ok || big_error != imap.TooLarge { ret fail(34i32) }
    var five: Scene = zero
    five.writer = io.SliceWriter { data: five.sent[0..], off: 0usize }
    five.reader = io.SliceReader { data: "* OK hi\r\n* 1 FETCH (UID 1", off: 0usize }
    let (g0, g_error) = imap.connect(a, io.slice_reader(&five.reader), io.slice_writer(&five.writer), 65536usize)
    var g = g0
    if g_error != ok || imap.noop(&g) != imap.Closed { ret fail(35i32) }
    var six: Scene = zero
    six.writer = io.SliceWriter { data: six.sent[0..], off: 0usize }
    six.reader = io.SliceReader { data: "* OK hi\r\n+ surprise\r\n", off: 0usize }
    let (h0, h_error) = imap.connect(a, io.slice_reader(&six.reader), io.slice_writer(&six.writer), 65536usize)
    var h = h0
    if h_error != ok || imap.noop(&h) != imap.Protocol { ret fail(36i32) }

    // ---- STARTTLS against a live server thread ----
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    var server_entropy: [64]u8 = zero
    var client_entropy: [64]u8 = zero
    var e = 0usize
    while e < 64usize {
        server_entropy[e] = u8((e * 3usize + 1usize) % 256usize)
        client_entropy[e] = u8((e * 7usize + 5usize) % 256usize)
        e += 1usize
    }
    var server_read: os.File = zero
    var client_write: os.File = zero
    let (sr, cw, c2s_error) = os.pipe()
    if c2s_error != ok { os.exit(23i32) }
    server_read = sr
    client_write = cw
    var client_read: os.File = zero
    var server_write: os.File = zero
    let (cr, sw, s2c_error) = os.pipe()
    if s2c_error != ok { os.exit(24i32) }
    client_read = cr
    server_write = sw
    let live_code = run_live(a, &server_read, &server_write, &client_read, &client_write, leaf_der, leaf_pkcs8, mid_der, server_entropy[0..], client_entropy[0..])
    if live_code != 0i32 { os.exit(live_code) }
    let _ = os.close(server_read)
    let _ = os.close(client_write)
    let _ = os.close(client_read)
    let _ = os.close(server_write)
    try io.print("net imap ok\n")
    ret ok
}
