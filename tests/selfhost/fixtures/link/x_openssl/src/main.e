// `x.openssl.crypto`: the host's OpenSSL AES-128-GCM as `e.net.tls`'s record cipher (D1646).
// Run with `required` as the first argument where libcrypto must be found (the suites put it
// there); without it, a host with no libcrypto passes after checking that `load` says so.
//
// Covered: seal and open agree byte for byte with `e.crypto.aead` over every length to 300
// and records up to 16 KB, with random keys, nonces and additional data; a flipped bit is
// `aead.Authentication` and leaves nothing in the output; a short buffer is `aead.TooSmall`; and
// a live TLS 1.3 exchange over pipes, the client sealing with OpenSSL and the server with the
// portable cipher, moves 100 KB each way. Every check has its own exit code.
use e.io
use e.mem
use e.os
use e.str
use e.time
use e.net.tls
use e.crypto.aead as aead
use x.openssl.crypto

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn next(state: *u64) -> u64 {
    var x = *state
    x = x ^ (x << 13u32)
    x = x ^ (x >> 7u32)
    x = x ^ (x << 17u32)
    *state = x
    ret x
}

fn fill(state: *u64, b: []u8) {
    var i = 0usize
    while i < b.len {
        b[i] = u8(next(state) & 255u64)
        i += 1usize
    }
}

fn agreement(a: *mem.Arena, cipher: tls.Aead) -> i32 {
    let (plain, plain_error) = mem.alloc[u8](a, 16385usize)
    let (mine, mine_error) = mem.alloc[u8](a, 16401usize)
    let (theirs, theirs_error) = mem.alloc[u8](a, 16401usize)
    let (back, back_error) = mem.alloc[u8](a, 16401usize)
    if plain_error != ok || mine_error != ok || theirs_error != ok || back_error != ok { ret 10i32 }
    var state = 88172645463325252u64
    var length = 0usize
    while length <= 306usize {
        var n = length
        if length == 301usize { n = 1000usize }
        if length == 302usize { n = 4095usize }
        if length == 303usize { n = 16383usize }
        if length == 304usize { n = 16384usize }
        if length == 305usize { n = 16385usize }
        if length == 306usize { n = 7777usize }
        var key: [16]u8 = zero
        var nonce: [12]u8 = zero
        var aad: [40]u8 = zero
        fill(&state, key[0..])
        fill(&state, nonce[0..])
        fill(&state, aad[0..])
        fill(&state, plain[0..n])
        let aad_len = usize(next(&state) % 41u64)
        let (m, m_error) = aead.aes128_gcm_seal(mine, key, nonce, aad[0..aad_len], plain[0..n])
        let (t, t_error) = cipher.seal(cipher.ctx, theirs, key, nonce, aad[0..aad_len], plain[0..n])
        if m_error != ok || t_error != ok || m != t || !same(mine[0..m], theirs[0..t]) { ret 11i32 }
        let (b, b_error) = cipher.open(cipher.ctx, back, key, nonce, aad[0..aad_len], mine[0..m])
        if b_error != ok || b != n || !same(back[0..b], plain[0..n]) { ret 12i32 }
        // One flipped bit anywhere in the ciphertext or tag.
        let spot = usize(next(&state) % u64(m))
        theirs[spot] = theirs[spot] ^ 1u8
        let (x, x_error) = cipher.open(cipher.ctx, back, key, nonce, aad[0..aad_len], theirs[0..t])
        if x_error != aead.Authentication { ret 13i32 }
        var i = 0usize
        while i < n {
            if back[i] != 0u8 { ret 14i32 }
            i += 1usize
        }
        length += 1usize
    }
    var key: [16]u8 = zero
    var nonce: [12]u8 = zero
    let (short, short_error) = cipher.seal(cipher.ctx, mine[0usize..20usize], key, nonce, plain[0usize..0usize], plain[0usize..5usize])
    if short_error != aead.TooSmall { ret 15i32 }
    ret 0i32
}

type ServerJob = struct { reading: *os.File, writing: *os.File, config: tls.ServerConfig, received: usize, failure: err }

// The portable end: reads 100 KB, then writes 100 KB back.
fn serve(job: *ServerJob) {
    var storage: [524288]u8 = zero
    var arena = mem.arena_from(storage[0..])
    let (stream0, create_error) = tls.server(&arena, io.file_reader(job.reading), io.file_writer(job.writing), job.config)
    if create_error != ok {
        job.failure = create_error
        ret
    }
    var stream = stream0
    job.failure = tls.handshake(&stream)
    if job.failure != ok { ret }
    var source = tls.reader(&stream)
    var sink = tls.writer(&stream)
    var chunk: [4096]u8 = zero
    while job.received < 102400usize {
        job.failure = io.read_exact(&source, chunk[0..])
        if job.failure != ok { ret }
        var i = 0usize
        while i < chunk.len {
            if chunk[i] != u8((job.received + i) % 251usize) {
                job.failure = tls.Protocol
                ret
            }
            i += 1usize
        }
        job.received += chunk.len
        job.failure = io.write_all(&sink, chunk[0..])
        if job.failure != ok { ret }
    }
    job.failure = tls.close(&stream)
}

fn exchange(a: *mem.Arena, cipher: tls.Aead) -> i32 {
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    let protocols: [1]str = [1]str{ "h2" }
    var server_entropy: [64]u8 = zero
    var client_entropy: [64]u8 = zero
    var i = 0usize
    while i < 64usize {
        server_entropy[i] = u8(i + 1usize)
        client_entropy[i] = u8(200usize - i)
        i += 1usize
    }
    let (server_read, client_write, up_error) = os.pipe()
    if up_error != ok { ret 20i32 }
    let (client_read, server_write, down_error) = os.pipe()
    if down_error != ok {
        let _ = os.close(server_read)
        let _ = os.close(client_write)
        ret 20i32
    }
    var sr = server_read
    var cw = client_write
    var cr = client_read
    var sw = server_write
    defer let _ = os.close(sr)
    defer let _ = os.close(cw)
    defer let _ = os.close(cr)
    defer let _ = os.close(sw)
    var job = ServerJob { reading: &sr, writing: &sw, config: tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: protocols[0..], entropy: server_entropy[0..] }, received: 0usize, failure: ok }
    let (server_thread, thread_error) = os.thread_create[ServerJob](serve, &job, 8388608usize)
    if thread_error != ok { ret 21i32 }
    let config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    // A failing client ends the process here: the server would wait on it forever.
    let client_code = client_side(a, cipher, &cr, &cw, config)
    if client_code != 0i32 { os.exit(client_code) }
    let joined = os.thread_join(server_thread)
    if joined != ok || job.failure != ok || job.received != 102400usize { ret 30i32 }
    ret 0i32
}

// The OpenSSL end: 100 KB out in 4 KB writes, each echoed back.
fn client_side(a: *mem.Arena, cipher: tls.Aead, cr: *os.File, cw: *os.File, config: tls.ClientConfig) -> i32 {
    let (stream0, client_error) = tls.client(a, io.file_reader(cr), io.file_writer(cw), config)
    if client_error != ok { ret 22i32 }
    var stream = stream0
    if tls.use_aead(&stream, cipher) != ok { ret 23i32 }
    if tls.handshake(&stream) != ok { ret 24i32 }
    // Too late once the handshake is done.
    if tls.use_aead(&stream, cipher) != tls.Protocol { ret 25i32 }
    var sink = tls.writer(&stream)
    var source = tls.reader(&stream)
    var chunk: [4096]u8 = zero
    var echo: [4096]u8 = zero
    var sent = 0usize
    while sent < 102400usize {
        var i = 0usize
        while i < chunk.len {
            chunk[i] = u8((sent + i) % 251usize)
            i += 1usize
        }
        if io.write_all(&sink, chunk[0..]) != ok { ret 26i32 }
        if io.read_exact(&source, echo[0..]) != ok || !same(echo[0..], chunk[0..]) { ret 27i32 }
        sent += chunk.len
    }
    var after: [1]u8 = zero
    let (_, end_error) = io.read(&source, after[0..])
    if end_error != io.End { ret 28i32 }
    if tls.close(&stream) != ok { ret 29i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let required = args.len > 1usize && str.eq(args[1], "required")
    let (openssl, load_error) = crypto.load(a)
    if load_error == crypto.NotFound && !required { ret ok }
    if load_error != ok { os.exit(1i32) }
    let cipher = crypto.aead_of(openssl)
    var code = agreement(a, cipher)
    if code == 0i32 { code = exchange(a, cipher) }
    if code == 0i32 && crypto.close(openssl) != ok { code = 2i32 }
    if code != 0i32 { os.exit(code) }
    ret ok
}
