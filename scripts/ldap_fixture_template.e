// e.net.ldap against ldap3 (scripts/ldap_reference.py writes this file from scripts/ldap_fixture_template.e):
// @@COUNT@@ RFC 4515 filter strings encoded to the same BER as ldap3, malformed filters refused, a scripted
// conversation whose requests equal ldap3's bytes and whose responses are ldap3's, and a live StartTLS session
// against a server thread over pipes that checks the decrypted requests it receives.
use e.io
use e.mem
use e.net.ldap as ldap
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
    let _ = io.print("net ldap failed at ")
    var digits: [5]u8 = zero
    digits[0] = u8(48i32 + code / 1000i32)
    digits[1] = u8(48i32 + (code / 100i32) % 10i32)
    digits[2] = u8(48i32 + (code / 10i32) % 10i32)
    digits[3] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..4])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

@@FILTER_FNS@@

fn bad_filters() -> i32 {
@@BAD@@
    var buf: [1024]u8 = zero
    var i = 0usize
    while i < bad.len {
        let (_, e) = ldap.encode_filter(buf[0..], bad[i])
        if e != ldap.Invalid { ret i32(i) + 1i32 }
        i += 1usize
    }
    ret 0i32
}

type Scene = struct { sent: [16384]u8, writer: io.SliceWriter, reader: io.SliceReader }

// ---- the live StartTLS server ----

type Job = struct { reading: *os.File, writing: *os.File, config: tls.ServerConfig, failure: i32 }

// One whole LDAPMessage (tag, length, content) into `buf`.
fn message_from(source: *io.Reader, buf: []u8) -> (usize, err) {
    var head: [2]u8 = zero
    try io.read_exact(source, head[0..])
    var length = usize(head[1])
    var at = 2usize
    buf[0] = head[0]
    buf[1] = head[1]
    if head[1] >= 128u8 {
        let count = usize(head[1] & 127u8)
        try io.read_exact(source, buf[2..2usize + count])
        length = 0usize
        var i = 0usize
        while i < count {
            length = length * 256usize + usize(buf[2usize + i])
            i += 1usize
        }
        at = 2usize + count
    }
    try io.read_exact(source, buf[at..at + length])
    ret (at + length, ok)
}

fn serve(job: *Job) {
    var storage: [262144]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var source = io.file_reader(job.reading)
    var sink = io.file_writer(job.writing)
    var buf: [2048]u8 = zero
    let (n, read_error) = message_from(&source, buf[0..])
    if read_error != ok || !same(buf[..n], @@LIVE_REQ0@@) {
        job.failure = 101i32
        ret
    }
    if io.write_all(&sink, @@LIVE_RESP0@@) != ok {
        job.failure = 102i32
        ret
    }
    let (secure0, create_error) = tls.server(&arena, source, sink, job.config)
    if create_error != ok {
        job.failure = 103i32
        ret
    }
    var secure = secure0
    if tls.handshake(&secure) != ok {
        job.failure = 104i32
        ret
    }
    var secure_source = tls.reader(&secure)
    var secure_sink = tls.writer(&secure)
    let (n1, error1) = message_from(&secure_source, buf[0..])
    if error1 != ok || !same(buf[..n1], @@LIVE_REQ1@@) {
        job.failure = 105i32
        ret
    }
    if io.write_all(&secure_sink, @@LIVE_RESP1@@) != ok {
        job.failure = 106i32
        ret
    }
    let (n2, error2) = message_from(&secure_source, buf[0..])
    if error2 != ok || !same(buf[..n2], @@LIVE_REQ2@@) {
        job.failure = 107i32
        ret
    }
    if io.write_all(&secure_sink, @@LIVE_RESP2@@) != ok {
        job.failure = 108i32
        ret
    }
    let (n3, error3) = message_from(&secure_source, buf[0..])
    if error3 != ok || !same(buf[..n3], @@LIVE_REQ3@@) {
        job.failure = 109i32
        ret
    }
    let _ = tls.close(&secure)
}

fn client_side(a: *mem.Arena, client_read: *os.File, client_write: *os.File, client_config: tls.ClientConfig) -> i32 {
    let (live0, live_error) = ldap.connect(a, io.file_reader(client_read), io.file_writer(client_write), 65536usize)
    if live_error != ok { ret 30i32 }
    var live = live0
    if ldap.starttls(&live, client_config) != ok || !live.secured { ret 31i32 }
    if ldap.starttls(&live, client_config) != ldap.Unsupported { ret 32i32 }
    if ldap.bind_simple(&live, "cn=live", "pw") != ok { ret 33i32 }
    let attrs = [1]str{ "cn" }
    let (found, search_error) = ldap.search(&live, "dc=live", ldap.SCOPE_SUBTREE, "(cn=*)", attrs[0..], 0u32, 0u32, false)
    if search_error != ok || found.len != 1usize || !same(found[0].dn, "cn=L,dc=live") { ret 34i32 }
    if ldap.unbind(&live) != ok { ret 35i32 }
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
    ret job.failure
}

fn main(a: *mem.Arena) -> err {
@@FILTER_CALLS@@
    let bad_code = bad_filters()
    if bad_code != 0i32 { ret fail(2000i32 + bad_code) }

    // ---- the scripted conversation ----
    var scene: Scene = zero
    scene.writer = io.SliceWriter { data: scene.sent[0..], off: 0usize }
    scene.reader = io.SliceReader { data: @@REPLIES@@, off: 0usize }
    let (s0, connect_error) = ldap.connect(a, io.slice_reader(&scene.reader), io.slice_writer(&scene.writer), 65536usize)
    if connect_error != ok { ret fail(1i32) }
    var s = s0
@@STEPS@@
    if ldap.unbind(&s) != ok { ret fail(40i32) }
    let want = @@SENT@@
    let unbind_tail = @@UNBIND@@
    if !same(scene.sent[..scene.writer.off - unbind_tail.len], want) { ret fail(41i32) }
    if !same(scene.sent[scene.writer.off - unbind_tail.len..scene.writer.off], unbind_tail) { ret fail(42i32) }
    if scene.reader.off != scene.reader.data.len { ret fail(43i32) }

    // refusals that write nothing, a message over the limit, a cut connection
    let wrote = scene.writer.off
    let empty_values: [0]str = zero
    let (_, scope_search) = ldap.search(&s, "dc=x", 7u8, "(a=b)", empty_values[0..], 0u32, 0u32, false)
    let (_, filter_search) = ldap.search(&s, "dc=x", 0u8, "(a=", empty_values[0..], 0u32, 0u32, false)
    if ldap.bind_simple(&s, "cn=x", "") != ldap.Invalid || scope_search != ldap.Invalid || filter_search != ldap.Invalid || ldap.delete(&s, "") != ldap.Invalid || ldap.bind_plain(&s, "", "", "p") != ldap.Invalid { ret fail(44i32) }
    if scene.writer.off != wrote { ret fail(45i32) }
    var small: Scene = zero
    small.writer = io.SliceWriter { data: small.sent[0..], off: 0usize }
    small.reader = io.SliceReader { data: "\x30\x82\x04\x00", off: 0usize }
    let (t0, t_error) = ldap.connect(a, io.slice_reader(&small.reader), io.slice_writer(&small.writer), 512usize)
    var t = t0
    if t_error != ok || ldap.bind_anonymous(&t) != ldap.TooLarge { ret fail(46i32) }
    var cut: Scene = zero
    cut.writer = io.SliceWriter { data: cut.sent[0..], off: 0usize }
    cut.reader = io.SliceReader { data: "\x30\x0c\x02\x01\x01\x61", off: 0usize }
    let (u0, u_error) = ldap.connect(a, io.slice_reader(&cut.reader), io.slice_writer(&cut.writer), 512usize)
    var u = u0
    if u_error != ok || ldap.bind_anonymous(&u) != ldap.Closed { ret fail(47i32) }
    var junk: Scene = zero
    junk.writer = io.SliceWriter { data: junk.sent[0..], off: 0usize }
    junk.reader = io.SliceReader { data: "\x04\x01\x00", off: 0usize }
    let (v0, v_error) = ldap.connect(a, io.slice_reader(&junk.reader), io.slice_writer(&junk.writer), 512usize)
    var v = v0
    if v_error != ok || ldap.bind_anonymous(&v) != ldap.Protocol { ret fail(48i32) }

    // ---- StartTLS against a live server thread ----
    let mid_der = @@MID@@
    let leaf_der = @@LEAF@@
    let leaf_pkcs8 = @@KEY@@
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
    try io.print("net ldap ok\n")
    ret ok
}
