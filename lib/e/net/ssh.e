// An SSH-2 client (C120), sans-IO: the caller moves bytes between a socket and the session. What it speaks:
// the version exchange, curve25519-sha256 key exchange with an ssh-ed25519 host key, the
// chacha20-poly1305@openssh.com cipher or, when the server has not that one, aes256-gcm@openssh.com or
// aes128-gcm@openssh.com (C155), password and ssh-ed25519 public-key authentication, one "session"
// channel with a pty and a shell (or an exec command), flow-control windows, exit status, and the server's
// request to exchange keys again in the middle of a session (a rekey: the host key must be the same, the session
// id stays, the keys and the cipher's counters are new; what the app writes waits until it is done).
// What it does not: other algorithms, a rekey of its own asking, port forwarding, SFTP, compression.
//
// Driving it: `open`, then loop: send `outgoing` bytes and call `sent`, `feed` what the socket received, read
// `status`. When the status is `HOST_KEY_PENDING` read `host_key` and `host_fingerprint`, then `trust` (or
// close). At `READY` `write` sends keystrokes and `read` gives the program's output. A remote closing or an
// error leaves `status` at `CLOSED` or `FAILED` with `failure` naming it.
//
// Memory: the buffers of a session (64 KB in, 64 KB out, 32 KB of channel data) are allocated in the arena.
use e.mem
use e.crypto.kx
use e.crypto.sign
use e.crypto.hash
use e.crypto.cipher
use e.crypto.mac
use e.crypto.aead

error Protocol
error HostKey
error AuthFailed
error TooLong
error Closed
error Unsupported

// The session's status.
const VERSION: u32 = 0u32
const KEX: u32 = 1u32
const HOST_KEY_PENDING: u32 = 2u32
const AUTH: u32 = 3u32
const CHANNEL: u32 = 4u32
const READY: u32 = 5u32
const CLOSED: u32 = 6u32
const FAILED: u32 = 7u32

// Failure codes (see `failure`).
const FAIL_NONE: u32 = 0u32
const FAIL_PROTOCOL: u32 = 1u32
const FAIL_UNSUPPORTED: u32 = 2u32
const FAIL_HOST_KEY: u32 = 3u32
const FAIL_AUTH: u32 = 4u32
const FAIL_MAC: u32 = 5u32
const FAIL_DISCONNECT: u32 = 6u32
const FAIL_CHANNEL: u32 = 7u32

const BUFFER: usize = 65536usize
const DATA: usize = 32768usize

// Authentication methods.
const METHOD_PASSWORD: u32 = 0u32
const METHOD_KEY: u32 = 1u32

// The packet ciphers (`cipher` of the session once the keys are in use).
const CIPHER_CHACHA: u32 = 0u32
const CIPHER_AES256_GCM: u32 = 1u32
const CIPHER_AES128_GCM: u32 = 2u32

// The fields after `got_newkeys` (C155): the cipher chosen by the key exchange in progress and the one in use for each
// direction; AES-GCM's keys and nonces (a fixed part and an invocation counter that each packet moves on); the keys of
// the exchange in progress for what the server sends, held until its NEWKEYS arrives; `scratch` for sealing and
// opening; and `rekeying` (a key exchange the server began after the session was up), `rekeys` (how many have
// finished) and the window credit given back while an exchange held packets.
type Session = struct {
    status: u32,
    failure: u32,
    inbuf: []u8,
    in_len: usize,
    outbuf: []u8,
    out_len: usize,
    chan_in: []u8,
    chan_len: usize,
    seq_in: u32,
    seq_out: u32,
    encrypted_in: bool,
    encrypted_out: bool,
    key_in_main: [32]u8,
    key_in_len: [32]u8,
    key_out_main: [32]u8,
    key_out_len: [32]u8,
    rng: [64]u8,
    server_version: [256]u8,
    server_version_len: usize,
    client_kexinit: [512]u8,
    client_kexinit_len: usize,
    server_kexinit: [2048]u8,
    server_kexinit_len: usize,
    ephemeral: [32]u8,
    ephemeral_public: [32]u8,
    server_public: [32]u8,
    kex_k: [32]u8,
    host_key: [32]u8,
    host_blob: [64]u8,
    host_blob_len: usize,
    host_sig: [64]u8,
    host_sig_ok: bool,
    exchange_hash: [32]u8,
    session_id: [32]u8,
    have_session_id: bool,
    user: [64]u8,
    user_len: usize,
    password: [128]u8,
    password_len: usize,
    key_seed: [32]u8,
    method: u32,
    term: [32]u8,
    term_len: usize,
    cols: u32,
    rows: u32,
    command: [128]u8,
    command_len: usize,
    channel_remote: u32,
    channel_open: bool,
    window_out: u32,
    window_in: u32,
    max_packet: u32,
    pty_done: bool,
    eof_seen: bool,
    exit_status: u32,
    has_exit_status: bool,
    banner: [256]u8,
    banner_len: usize,
    sent_newkeys: bool,
    got_newkeys: bool,
    cipher_next: u32,
    cipher_out: u32,
    cipher_in: u32,
    gcm_out_key: [32]u8,
    gcm_in_key: [32]u8,
    gcm_out_iv: [12]u8,
    gcm_in_iv: [12]u8,
    next_in_main: [32]u8,
    next_in_len: [32]u8,
    next_gcm_key: [32]u8,
    next_gcm_iv: [12]u8,
    scratch: []u8,
    rekeying: bool,
    rekeys: u32,
    deferred_window: u32,
}

// ---- byte helpers ---------------------------------------------------------------------------------

fn put_u32(buf: []u8, at: usize, value: u32) {
    buf[at] = u8(value >> 24u32)
    buf[at + 1usize] = u8((value >> 16u32) & 255u32)
    buf[at + 2usize] = u8((value >> 8u32) & 255u32)
    buf[at + 3usize] = u8(value & 255u32)
}

fn get_u32(buf: []const u8, at: usize) -> u32 {
    ret (u32(buf[at]) << 24u32) | (u32(buf[at + 1usize]) << 16u32) | (u32(buf[at + 2usize]) << 8u32) | u32(buf[at + 3usize])
}

// A writer over `buf`: the length so far and whether something did not fit.
type Writer = struct { buf: []u8, len: usize, over: bool }

fn w_byte(w: *Writer, b: u8) {
    if w.len >= w.buf.len {
        w.over = true
        ret
    }
    w.buf[w.len] = b
    w.len += 1usize
}

fn w_u32(w: *Writer, v: u32) {
    if w.len + 4usize > w.buf.len {
        w.over = true
        ret
    }
    put_u32(w.buf, w.len, v)
    w.len += 4usize
}

fn w_raw(w: *Writer, data: []const u8) {
    if w.len + data.len > w.buf.len {
        w.over = true
        ret
    }
    var i = 0usize
    while i < data.len {
        w.buf[w.len + i] = data[i]
        i += 1usize
    }
    w.len += data.len
}

fn w_string(w: *Writer, data: []const u8) {
    w_u32(w, u32(data.len))
    w_raw(w, data)
}

// A big-endian number as an SSH mpint: leading zeros dropped, a zero byte in front when the top bit is set.
fn w_mpint(w: *Writer, data: []const u8) {
    var skip = 0usize
    while skip < data.len && data[skip] == 0u8 { skip += 1usize }
    let rest = data.len - skip
    if rest == 0usize {
        w_u32(w, 0u32)
        ret
    }
    if data[skip] >= 128u8 {
        w_u32(w, u32(rest + 1usize))
        w_byte(w, 0u8)
    } else {
        w_u32(w, u32(rest))
    }
    var i = skip
    while i < data.len {
        w_byte(w, data[i])
        i += 1usize
    }
}

// A reader over `buf` from `pos`; `bad` once something ran past the end.
type Reader = struct { buf: []const u8, pos: usize, bad: bool }

fn r_byte(r: *Reader) -> u8 {
    if r.pos >= r.buf.len {
        r.bad = true
        ret 0u8
    }
    let b = r.buf[r.pos]
    r.pos += 1usize
    ret b
}

fn r_u32(r: *Reader) -> u32 {
    if r.pos + 4usize > r.buf.len {
        r.bad = true
        ret 0u32
    }
    let v = get_u32(r.buf, r.pos)
    r.pos += 4usize
    ret v
}

// A string's bytes (a view into the buffer).
fn r_string(r: *Reader) -> []const u8 {
    let n = r_u32(r)
    if r.bad || r.pos + usize(n) > r.buf.len {
        r.bad = true
        ret r.buf[0usize..0usize]
    }
    let out = r.buf[r.pos..r.pos + usize(n)]
    r.pos += usize(n)
    ret out
}

fn same_text(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Is `name` one of the comma-separated names in `list`?
fn in_list(list: []const u8, name: str) -> bool {
    var start = 0usize
    var i = 0usize
    while i <= list.len {
        if i == list.len || list[i] == 44u8 {
            if same_text(list[start..i], name) { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// ---- opening and the buffers ----------------------------------------------------------------------

// A client session for `user`. `random` is at least 64 bytes of entropy (the key exchange's secret, the cookie,
// padding). Authentication is by `password` (or, with `use_key`, by the ed25519 `key_seed`).
fn open(a: *mem.Arena, random: []const u8, user: str, password: str, cols: u32, rows: u32) -> (Session, err) {
    var none: Session = zero
    if random.len < 64usize || user.len > 64usize || password.len > 128usize { ret (none, TooLong) }
    let (inbuf, in_error) = mem.alloc[u8](a, BUFFER)
    if in_error != ok { ret (none, in_error) }
    let (outbuf, out_error) = mem.alloc[u8](a, BUFFER)
    if out_error != ok { ret (none, out_error) }
    let (chan_in, chan_error) = mem.alloc[u8](a, DATA)
    if chan_error != ok { ret (none, chan_error) }
    let (scratch, scratch_error) = mem.alloc[u8](a, 35200usize)
    if scratch_error != ok { ret (none, scratch_error) }
    var s = Session { status: VERSION, failure: FAIL_NONE, inbuf: inbuf, in_len: 0usize, outbuf: outbuf, out_len: 0usize, chan_in: chan_in, chan_len: 0usize, seq_in: 0u32, seq_out: 0u32, encrypted_in: false, encrypted_out: false, key_in_main: zero, key_in_len: zero, key_out_main: zero, key_out_len: zero, rng: zero, server_version: zero, server_version_len: 0usize, client_kexinit: zero, client_kexinit_len: 0usize, server_kexinit: zero, server_kexinit_len: 0usize, ephemeral: zero, ephemeral_public: zero, server_public: zero, kex_k: zero, host_key: zero, host_blob: zero, host_blob_len: 0usize, host_sig: zero, host_sig_ok: false, exchange_hash: zero, session_id: zero, have_session_id: false, user: zero, user_len: user.len, password: zero, password_len: password.len, key_seed: zero, method: METHOD_PASSWORD, term: zero, term_len: 0usize, cols: cols, rows: rows, command: zero, command_len: 0usize, channel_remote: 0u32, channel_open: false, window_out: 0u32, window_in: 2097152u32, max_packet: 0u32, pty_done: false, eof_seen: false, exit_status: 0u32, has_exit_status: false, banner: zero, banner_len: 0usize, sent_newkeys: false, got_newkeys: false, cipher_next: CIPHER_CHACHA, cipher_out: CIPHER_CHACHA, cipher_in: CIPHER_CHACHA, gcm_out_key: zero, gcm_in_key: zero, gcm_out_iv: zero, gcm_in_iv: zero, next_in_main: zero, next_in_len: zero, next_gcm_key: zero, next_gcm_iv: zero, scratch: scratch, rekeying: false, rekeys: 0u32, deferred_window: 0u32 }
    var i = 0usize
    while i < 64usize {
        s.rng[i] = random[i]
        i += 1usize
    }
    i = 0usize
    while i < user.len {
        s.user[i] = user[i]
        i += 1usize
    }
    i = 0usize
    while i < password.len {
        s.password[i] = password[i]
        i += 1usize
    }
    let name = "xterm-256color"
    i = 0usize
    while i < name.len {
        s.term[i] = name[i]
        i += 1usize
    }
    s.term_len = name.len
    // The first thing sent is the identification string.
    let ident = "SSH-2.0-NeperOS_1.0\r\n"
    i = 0usize
    while i < ident.len {
        s.outbuf[i] = ident[i]
        i += 1usize
    }
    s.out_len = ident.len
    ret (s, ok)
}

// Authenticate with an ed25519 key (its 32-byte seed) instead of the password.
fn use_key(s: *Session, seed: [32]u8) {
    s.key_seed = seed
    s.method = METHOD_KEY
}

// Run `command` instead of a login shell (empty: the shell).
fn set_command(s: *Session, command: str) {
    var n = command.len
    if n > 128usize { n = 128usize }
    var i = 0usize
    while i < n {
        s.command[i] = command[i]
        i += 1usize
    }
    s.command_len = n
}

fn fail(s: *Session, code: u32) {
    s.status = FAILED
    s.failure = code
}

// ---- packets --------------------------------------------------------------------------------------

fn chacha_nonce(seq: u32) -> [12]u8 {
    var n: [12]u8 = zero
    n[8usize] = u8(seq >> 24u32)
    n[9usize] = u8((seq >> 16u32) & 255u32)
    n[10usize] = u8((seq >> 8u32) & 255u32)
    n[11usize] = u8(seq & 255u32)
    ret n
}

// Queue one packet carrying `payload`.
fn send_packet(s: *Session, payload: []const u8) {
    var pad = 8usize - ((payload.len + 1usize) % 8usize)
    if !s.encrypted_out { pad = 8usize - ((payload.len + 5usize) % 8usize) }
    var pad_block = 8usize
    // AES-GCM's blocks are 16 bytes and the length stays out of the padding, as chacha's does.
    if s.encrypted_out && s.cipher_out != CIPHER_CHACHA {
        pad = 16usize - ((payload.len + 1usize) % 16usize)
        pad_block = 16usize
    }
    if pad < 4usize { pad += pad_block }
    let body = 1usize + payload.len + pad
    let total = 4usize + body + 16usize
    if s.out_len + total > s.outbuf.len {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    let at = s.out_len
    put_u32(s.outbuf, at, u32(body))
    s.outbuf[at + 4usize] = u8(pad)
    var i = 0usize
    while i < payload.len {
        s.outbuf[at + 5usize + i] = payload[i]
        i += 1usize
    }
    i = 0usize
    while i < pad {
        // The padding is random bytes; the spare entropy is plenty and cheap.
        s.outbuf[at + 5usize + payload.len + i] = s.rng[(i + usize(s.seq_out)) % 64usize] ^ u8((i * 37usize) % 256usize)
        i += 1usize
    }
    if s.encrypted_out && s.cipher_out != CIPHER_CHACHA {
        // AES-GCM (RFC 5647): the length in the clear is the additional data, the rest is sealed, the nonce is the
        // fixed four bytes and an invocation counter of eight that moves on with every packet.
        var nonce_out: [12]u8 = zero
        i = 0usize
        while i < 12usize {
            nonce_out[i] = s.gcm_out_iv[i]
            i += 1usize
        }
        var sealed_len = 0usize
        var seal_error: err = ok
        if s.cipher_out == CIPHER_AES256_GCM {
            let (n_sealed, e_sealed) = aead.aes256_gcm_seal(s.scratch[0usize..body + 16usize], s.gcm_out_key, nonce_out, s.outbuf[at..at + 4usize], s.outbuf[at + 4usize..at + 4usize + body])
            sealed_len = n_sealed
            seal_error = e_sealed
        } else {
            var key16: [16]u8 = zero
            i = 0usize
            while i < 16usize {
                key16[i] = s.gcm_out_key[i]
                i += 1usize
            }
            let (n_sealed, e_sealed) = aead.aes128_gcm_seal(s.scratch[0usize..body + 16usize], key16, nonce_out, s.outbuf[at..at + 4usize], s.outbuf[at + 4usize..at + 4usize + body])
            sealed_len = n_sealed
            seal_error = e_sealed
        }
        if seal_error != ok || sealed_len != body + 16usize {
            fail(s, FAIL_PROTOCOL)
            ret
        }
        i = 0usize
        while i < body + 16usize {
            s.outbuf[at + 4usize + i] = s.scratch[i]
            i += 1usize
        }
        // The invocation counter, big endian, bytes 4..12.
        var carry = true
        var c = 11usize
        while carry && c >= 4usize {
            s.gcm_out_iv[c] = s.gcm_out_iv[c] + 1u8
            carry = s.gcm_out_iv[c] == 0u8
            if c == 4usize { carry = false }
            c -= 1usize
        }
        s.out_len = at + total
    } else if s.encrypted_out {
        let nonce = chacha_nonce(s.seq_out)
        // The payload under the main key from block 1, the length under the length key from block 0, the tag
        // over both with the main key's block 0.
        cipher.chacha20(s.key_out_main, 1u32, nonce, s.outbuf[at + 4usize..at + 4usize + body])
        cipher.chacha20(s.key_out_len, 0u32, nonce, s.outbuf[at..at + 4usize])
        var poly_key: [32]u8 = zero
        var block: [64]u8 = zero
        let block_error = cipher.chacha20_block(s.key_out_main, 0u32, nonce, block[0usize..64usize])
        i = 0usize
        while i < 32usize {
            poly_key[i] = block[i]
            i += 1usize
        }
        let tag = mac.poly1305(poly_key, s.outbuf[at..at + 4usize + body])
        i = 0usize
        while i < 16usize {
            s.outbuf[at + 4usize + body + i] = tag[i]
            i += 1usize
        }
        s.out_len = at + total
    } else {
        s.out_len = at + 4usize + body
    }
    s.seq_out += 1u32
}

// ---- the key exchange -----------------------------------------------------------------------------

fn name_list(w: *Writer, names: str) {
    w_string(w, names)
}

fn send_kexinit(s: *Session) {
    var payload: [512]u8 = zero
    var w = Writer { buf: payload[0usize..512usize], len: 0usize, over: false }
    w_byte(&w, 20u8)
    var i = 0usize
    while i < 16usize {
        w_byte(&w, s.rng[32usize + i])
        i += 1usize
    }
    name_list(&w, "curve25519-sha256,curve25519-sha256@libssh.org")
    name_list(&w, "ssh-ed25519")
    name_list(&w, "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com")
    name_list(&w, "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com")
    name_list(&w, "hmac-sha2-256")
    name_list(&w, "hmac-sha2-256")
    name_list(&w, "none")
    name_list(&w, "none")
    name_list(&w, "")
    name_list(&w, "")
    w_byte(&w, 0u8)
    w_u32(&w, 0u32)
    i = 0usize
    while i < w.len {
        s.client_kexinit[i] = payload[i]
        i += 1usize
    }
    s.client_kexinit_len = w.len
    send_packet(s, payload[0usize..w.len])
}

// The exchange hash: SHA-256 over V_C, V_S, I_C, I_S, K_S, Q_C, Q_S and K, each as an SSH string (K as an mpint).
fn compute_exchange_hash(s: *Session) {
    var h = hash.sha256_init()
    var lenbuf: [4]u8 = zero
    let v_c = "SSH-2.0-NeperOS_1.0"
    put_u32(lenbuf[0usize..4usize], 0usize, u32(v_c.len))
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, v_c)
    put_u32(lenbuf[0usize..4usize], 0usize, u32(s.server_version_len))
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.server_version[0usize..s.server_version_len])
    put_u32(lenbuf[0usize..4usize], 0usize, u32(s.client_kexinit_len))
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.client_kexinit[0usize..s.client_kexinit_len])
    put_u32(lenbuf[0usize..4usize], 0usize, u32(s.server_kexinit_len))
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.server_kexinit[0usize..s.server_kexinit_len])
    put_u32(lenbuf[0usize..4usize], 0usize, u32(s.host_blob_len))
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.host_blob[0usize..s.host_blob_len])
    put_u32(lenbuf[0usize..4usize], 0usize, 32u32)
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.ephemeral_public[0usize..32usize])
    hash.sha256_update(&h, lenbuf[0usize..4usize])
    hash.sha256_update(&h, s.server_public[0usize..32usize])
    var mp: [40]u8 = zero
    var w = Writer { buf: mp[0usize..40usize], len: 0usize, over: false }
    w_mpint(&w, s.kex_k[0usize..32usize])
    hash.sha256_update(&h, mp[0usize..w.len])
    s.exchange_hash = hash.sha256_done(&h)
}

// K1 = HASH(K || H || letter || session_id), K2 = HASH(K || H || K1): 64 key bytes for the chacha cipher.
fn derive_key(s: *Session, letter: u8, out: []u8) {
    var mp: [40]u8 = zero
    var w = Writer { buf: mp[0usize..40usize], len: 0usize, over: false }
    w_mpint(&w, s.kex_k[0usize..32usize])
    var h1 = hash.sha256_init()
    hash.sha256_update(&h1, mp[0usize..w.len])
    hash.sha256_update(&h1, s.exchange_hash[0usize..32usize])
    var one: [1]u8 = zero
    one[0usize] = letter
    hash.sha256_update(&h1, one[0usize..1usize])
    hash.sha256_update(&h1, s.session_id[0usize..32usize])
    let k1 = hash.sha256_done(&h1)
    var h2 = hash.sha256_init()
    hash.sha256_update(&h2, mp[0usize..w.len])
    hash.sha256_update(&h2, s.exchange_hash[0usize..32usize])
    hash.sha256_update(&h2, k1[0usize..32usize])
    let k2 = hash.sha256_done(&h2)
    var i = 0usize
    while i < 32usize {
        out[i] = k1[i]
        out[32usize + i] = k2[i]
        i += 1usize
    }
}

// The keys of the exchange just made: for what we send, in use at once (this is called right after our NEWKEYS went
// out under the old ones); for what the server sends, held until its NEWKEYS says it has changed (`apply_in_keys`).
fn install_keys(s: *Session) {
    var c2s: [64]u8 = zero
    var s2c: [64]u8 = zero
    derive_key(s, 67u8, c2s[0usize..64usize])
    derive_key(s, 68u8, s2c[0usize..64usize])
    var i = 0usize
    if s.cipher_next == CIPHER_CHACHA {
        // The first 32 bytes are the main key (K_2), the last 32 the length key (K_1).
        while i < 32usize {
            s.key_out_main[i] = c2s[i]
            s.key_out_len[i] = c2s[32usize + i]
            s.next_in_main[i] = s2c[i]
            s.next_in_len[i] = s2c[32usize + i]
            i += 1usize
        }
    } else {
        // AES-GCM: the key (32 or 16 bytes) from letters C and D, the fixed part of the nonce (12 bytes, the counter
        // continues from its last eight) from A and B.
        var iv_c2s: [64]u8 = zero
        var iv_s2c: [64]u8 = zero
        derive_key(s, 65u8, iv_c2s[0usize..64usize])
        derive_key(s, 66u8, iv_s2c[0usize..64usize])
        var width = 32usize
        if s.cipher_next == CIPHER_AES128_GCM { width = 16usize }
        i = 0usize
        while i < 32usize {
            s.gcm_out_key[i] = 0u8
            s.next_gcm_key[i] = 0u8
            if i < width {
                s.gcm_out_key[i] = c2s[i]
                s.next_gcm_key[i] = s2c[i]
            }
            i += 1usize
        }
        i = 0usize
        while i < 12usize {
            s.gcm_out_iv[i] = iv_c2s[i]
            s.next_gcm_iv[i] = iv_s2c[i]
            i += 1usize
        }
    }
    s.cipher_out = s.cipher_next
}

// The server's NEWKEYS arrived: what it sends from here on is under the keys held for it.
fn apply_in_keys(s: *Session) {
    var i = 0usize
    while i < 32usize {
        s.key_in_main[i] = s.next_in_main[i]
        s.key_in_len[i] = s.next_in_len[i]
        s.gcm_in_key[i] = s.next_gcm_key[i]
        i += 1usize
    }
    i = 0usize
    while i < 12usize {
        s.gcm_in_iv[i] = s.next_gcm_iv[i]
        i += 1usize
    }
    s.cipher_in = s.cipher_next
    s.encrypted_in = true
}

fn handle_kexinit(s: *Session, payload: []const u8) {
    if payload.len > 2048usize {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    var i = 0usize
    while i < payload.len {
        s.server_kexinit[i] = payload[i]
        i += 1usize
    }
    s.server_kexinit_len = payload.len
    var r = Reader { buf: payload, pos: 17usize, bad: false }
    let kex_list = r_string(&r)
    let host_list = r_string(&r)
    let enc_c2s = r_string(&r)
    let enc_s2c = r_string(&r)
    if r.bad {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    if !in_list(kex_list, "curve25519-sha256") && !in_list(kex_list, "curve25519-sha256@libssh.org") {
        fail(s, FAIL_UNSUPPORTED)
        ret
    }
    if !in_list(host_list, "ssh-ed25519") {
        fail(s, FAIL_UNSUPPORTED)
        ret
    }
    // The first of our ciphers, in our order, that the server has in both directions.
    var chosen = 99u32
    if in_list(enc_c2s, "chacha20-poly1305@openssh.com") && in_list(enc_s2c, "chacha20-poly1305@openssh.com") {
        chosen = CIPHER_CHACHA
    } else if in_list(enc_c2s, "aes256-gcm@openssh.com") && in_list(enc_s2c, "aes256-gcm@openssh.com") {
        chosen = CIPHER_AES256_GCM
    } else if in_list(enc_c2s, "aes128-gcm@openssh.com") && in_list(enc_s2c, "aes128-gcm@openssh.com") {
        chosen = CIPHER_AES128_GCM
    }
    if chosen == 99u32 {
        fail(s, FAIL_UNSUPPORTED)
        ret
    }
    s.cipher_next = chosen
    // Our ephemeral key: the caller's random bytes; a key exchange begun later in the session takes a new one made
    // from the old secret and the last exchange hash, so it is never the same twice.
    if s.rekeying {
        var seed_input: [68]u8 = zero
        i = 0usize
        while i < 32usize {
            seed_input[i] = s.ephemeral[i]
            seed_input[32usize + i] = s.exchange_hash[i]
            i += 1usize
        }
        put_u32(seed_input[0usize..68usize], 64usize, s.rekeys + 1u32)
        let fresh = hash.sha256(seed_input[0usize..68usize])
        i = 0usize
        while i < 32usize {
            s.ephemeral[i] = fresh[i]
            i += 1usize
        }
    } else {
        i = 0usize
        while i < 32usize {
            s.ephemeral[i] = s.rng[i]
            i += 1usize
        }
    }
    let public = kx.x25519_public_from_secret(kx.X25519SecretKey { bytes: s.ephemeral })
    s.ephemeral_public = public.bytes
    var msg: [64]u8 = zero
    var w = Writer { buf: msg[0usize..64usize], len: 0usize, over: false }
    w_byte(&w, 30u8)
    w_string(&w, s.ephemeral_public[0usize..32usize])
    send_packet(s, msg[0usize..w.len])
}

fn handle_kex_reply(s: *Session, payload: []const u8) {
    // A key exchange begun mid-session must show the host key already trusted.
    let old_host_key = s.host_key
    var r = Reader { buf: payload, pos: 1usize, bad: false }
    let blob = r_string(&r)
    let q_s = r_string(&r)
    let sig = r_string(&r)
    if r.bad || q_s.len != 32usize || blob.len > 64usize {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    // The host key blob: string "ssh-ed25519", string key(32).
    var br = Reader { buf: blob, pos: 0usize, bad: false }
    let key_type = r_string(&br)
    let key = r_string(&br)
    if br.bad || !same_text(key_type, "ssh-ed25519") || key.len != 32usize {
        fail(s, FAIL_UNSUPPORTED)
        ret
    }
    var i = 0usize
    while i < blob.len {
        s.host_blob[i] = blob[i]
        i += 1usize
    }
    s.host_blob_len = blob.len
    i = 0usize
    while i < 32usize {
        s.host_key[i] = key[i]
        s.server_public[i] = q_s[i]
        i += 1usize
    }
    // The signature blob: string "ssh-ed25519", string sig(64).
    var sr = Reader { buf: sig, pos: 0usize, bad: false }
    let sig_type = r_string(&sr)
    let sig_bytes = r_string(&sr)
    if sr.bad || !same_text(sig_type, "ssh-ed25519") || sig_bytes.len != 64usize {
        fail(s, FAIL_HOST_KEY)
        ret
    }
    i = 0usize
    while i < 64usize {
        s.host_sig[i] = sig_bytes[i]
        i += 1usize
    }
    // K and H.
    let (shared_key, shared_error) = kx.x25519_exchange(kx.X25519SecretKey { bytes: s.ephemeral }, kx.X25519PublicKey { bytes: s.server_public })
    if shared_error != ok {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    s.kex_k = shared_key.bytes
    compute_exchange_hash(s)
    var sig_value: sign.Ed25519Signature = zero
    i = 0usize
    while i < 64usize {
        sig_value.bytes[i] = s.host_sig[i]
        i += 1usize
    }
    if !sign.ed25519_verify(sign.Ed25519PublicKey { bytes: s.host_key }, s.exchange_hash[0usize..32usize], sig_value) {
        fail(s, FAIL_HOST_KEY)
        ret
    }
    s.host_sig_ok = true
    if !s.have_session_id {
        s.session_id = s.exchange_hash
        s.have_session_id = true
    }
    if s.rekeying {
        // Same key as before, or the session ends; then our NEWKEYS goes out and the keys of this exchange take over
        // for what we send.
        var changed = false
        i = 0usize
        while i < 32usize {
            if old_host_key[i] != s.host_key[i] { changed = true }
            i += 1usize
        }
        if changed {
            fail(s, FAIL_HOST_KEY)
            ret
        }
        var nk: [1]u8 = zero
        nk[0usize] = 21u8
        send_packet(s, nk[0usize..1usize])
        install_keys(s)
        ret
    }
    // The caller is asked about the key before anything secret is sent.
    s.status = HOST_KEY_PENDING
}

// Carry on after the caller accepted the host key: NEWKEYS out, then the keys in use for what we send.
fn trust(s: *Session) {
    if s.status != HOST_KEY_PENDING { ret }
    var nk: [1]u8 = zero
    nk[0usize] = 21u8
    send_packet(s, nk[0usize..1usize])
    install_keys(s)
    s.encrypted_out = true
    s.sent_newkeys = true
    s.status = KEX
    if s.got_newkeys { start_auth(s) }
}

// The server's host key (the 32 ed25519 bytes) and its SHA-256 fingerprint as OpenSSH shows it, SHA256:base64.
fn host_key(s: *Session) -> [32]u8 { ret s.host_key }

fn b64_char(v: usize) -> u8 {
    let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    ret table[v]
}

// "SHA256:" and the unpadded base64 of the SHA-256 of the key blob, into `out` (at least 50 bytes): the length.
fn host_fingerprint(s: *Session, out: []u8) -> usize {
    let digest = hash.sha256(s.host_blob[0usize..s.host_blob_len])
    let prefix = "SHA256:"
    var n = 0usize
    var i = 0usize
    while i < prefix.len {
        out[n] = prefix[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i + 3usize <= 32usize {
        let v = (usize(digest[i]) << 16usize) | (usize(digest[i + 1usize]) << 8usize) | usize(digest[i + 2usize])
        out[n] = b64_char((v >> 18usize) & 63usize)
        out[n + 1usize] = b64_char((v >> 12usize) & 63usize)
        out[n + 2usize] = b64_char((v >> 6usize) & 63usize)
        out[n + 3usize] = b64_char(v & 63usize)
        n += 4usize
        i += 3usize
    }
    // 32 bytes leave two: three base64 characters, the padding left off.
    let v2 = (usize(digest[30usize]) << 16usize) | (usize(digest[31usize]) << 8usize)
    out[n] = b64_char((v2 >> 18usize) & 63usize)
    out[n + 1usize] = b64_char((v2 >> 12usize) & 63usize)
    out[n + 2usize] = b64_char((v2 >> 6usize) & 63usize)
    n += 3usize
    ret n
}

// ---- authentication and the channel -------------------------------------------------------------------

fn start_auth(s: *Session) {
    var msg: [32]u8 = zero
    var w = Writer { buf: msg[0usize..32usize], len: 0usize, over: false }
    w_byte(&w, 5u8)
    w_string(&w, "ssh-userauth")
    send_packet(s, msg[0usize..w.len])
    s.status = AUTH
}

fn send_userauth(s: *Session) {
    var msg: [512]u8 = zero
    var w = Writer { buf: msg[0usize..512usize], len: 0usize, over: false }
    w_byte(&w, 50u8)
    w_string(&w, s.user[0usize..s.user_len])
    w_string(&w, "ssh-connection")
    if s.method == METHOD_PASSWORD {
        w_string(&w, "password")
        w_byte(&w, 0u8)
        w_string(&w, s.password[0usize..s.password_len])
        send_packet(s, msg[0usize..w.len])
        ret
    }
    // Public key: the signature covers the session id and the request up to the signature flag.
    let (public, public_error) = sign.ed25519_public_from_secret(sign.Ed25519SecretKey { bytes: s.key_seed })
    if public_error != ok {
        fail(s, FAIL_AUTH)
        ret
    }
    var blob: [64]u8 = zero
    var bw = Writer { buf: blob[0usize..64usize], len: 0usize, over: false }
    w_string(&bw, "ssh-ed25519")
    w_string(&bw, public.bytes[0usize..32usize])
    w_string(&w, "publickey")
    w_byte(&w, 1u8)
    w_string(&w, "ssh-ed25519")
    w_string(&w, blob[0usize..bw.len])
    var signed: [640]u8 = zero
    var sw = Writer { buf: signed[0usize..640usize], len: 0usize, over: false }
    w_string(&sw, s.session_id[0usize..32usize])
    w_raw(&sw, msg[0usize..w.len])
    let (signature, sign_error) = sign.ed25519_sign(sign.Ed25519SecretKey { bytes: s.key_seed }, signed[0usize..sw.len])
    if sign_error != ok {
        fail(s, FAIL_AUTH)
        ret
    }
    var sigblob: [96]u8 = zero
    var gw = Writer { buf: sigblob[0usize..96usize], len: 0usize, over: false }
    w_string(&gw, "ssh-ed25519")
    w_string(&gw, signature.bytes[0usize..64usize])
    w_string(&w, sigblob[0usize..gw.len])
    send_packet(s, msg[0usize..w.len])
}

fn open_channel(s: *Session) {
    var msg: [64]u8 = zero
    var w = Writer { buf: msg[0usize..64usize], len: 0usize, over: false }
    w_byte(&w, 90u8)
    w_string(&w, "session")
    w_u32(&w, 0u32)
    w_u32(&w, s.window_in)
    w_u32(&w, 32768u32)
    send_packet(s, msg[0usize..w.len])
    s.status = CHANNEL
}

fn channel_request(s: *Session, kind: str, want_reply: bool, extra: []const u8) {
    var msg: [256]u8 = zero
    var w = Writer { buf: msg[0usize..256usize], len: 0usize, over: false }
    w_byte(&w, 98u8)
    w_u32(&w, s.channel_remote)
    w_string(&w, kind)
    if want_reply { w_byte(&w, 1u8) } else { w_byte(&w, 0u8) }
    w_raw(&w, extra)
    send_packet(s, msg[0usize..w.len])
}

fn request_pty(s: *Session) {
    var extra: [96]u8 = zero
    var w = Writer { buf: extra[0usize..96usize], len: 0usize, over: false }
    w_string(&w, s.term[0usize..s.term_len])
    w_u32(&w, s.cols)
    w_u32(&w, s.rows)
    w_u32(&w, 0u32)
    w_u32(&w, 0u32)
    // The terminal modes: just the end marker.
    var modes: [1]u8 = zero
    w_string(&w, modes[0usize..1usize])
    channel_request(s, "pty-req", true, extra[0usize..w.len])
}

fn request_shell(s: *Session) {
    if s.command_len > 0usize {
        var extra: [140]u8 = zero
        var w = Writer { buf: extra[0usize..140usize], len: 0usize, over: false }
        w_string(&w, s.command[0usize..s.command_len])
        channel_request(s, "exec", true, extra[0usize..w.len])
    } else {
        var none: [1]u8 = zero
        channel_request(s, "shell", true, none[0usize..0usize])
    }
}

// Tell the server the terminal changed size.
fn resize(s: *Session, cols: u32, rows: u32) {
    s.cols = cols
    s.rows = rows
    if s.status != READY { ret }
    var extra: [16]u8 = zero
    var w = Writer { buf: extra[0usize..16usize], len: 0usize, over: false }
    w_u32(&w, cols)
    w_u32(&w, rows)
    w_u32(&w, 0u32)
    w_u32(&w, 0u32)
    channel_request(s, "window-change", false, extra[0usize..w.len])
}

// Send keystrokes to the remote program (as much as the server's window and packet size allow; the count taken).
fn write(s: *Session, data: []const u8) -> usize {
    // While keys are being exchanged nothing but the exchange may be sent: the caller tries again.
    if s.status != READY || s.rekeying || data.len == 0usize { ret 0usize }
    var n = data.len
    if n > usize(s.window_out) { n = usize(s.window_out) }
    if n > 4096usize { n = 4096usize }
    if n == 0usize { ret 0usize }
    var msg: [4128]u8 = zero
    var w = Writer { buf: msg[0usize..4128usize], len: 0usize, over: false }
    w_byte(&w, 94u8)
    w_u32(&w, s.channel_remote)
    w_string(&w, data[0usize..n])
    send_packet(s, msg[0usize..w.len])
    s.window_out -= u32(n)
    ret n
}

// What the remote program wrote, up to `out.len` bytes; the window is given back so it keeps sending.
fn read(s: *Session, out: []u8) -> usize {
    var n = s.chan_len
    if n > out.len { n = out.len }
    var i = 0usize
    while i < n {
        out[i] = s.chan_in[i]
        i += 1usize
    }
    i = n
    while i < s.chan_len {
        s.chan_in[i - n] = s.chan_in[i]
        i += 1usize
    }
    s.chan_len -= n
    if n > 0usize && s.status == READY {
        s.window_in += u32(n)
        if s.rekeying {
            // Held with the rest until the exchange is done (dispatch's NEWKEYS gives it back).
            s.deferred_window += u32(n)
        } else {
            // Give back what was consumed once it adds up to something worth a packet.
            var msg: [16]u8 = zero
            var w = Writer { buf: msg[0usize..16usize], len: 0usize, over: false }
            w_byte(&w, 93u8)
            w_u32(&w, s.channel_remote)
            w_u32(&w, u32(n))
            send_packet(s, msg[0usize..w.len])
        }
    }
    ret n
}

fn handle_channel_data(s: *Session, data: []const u8) {
    if s.chan_len + data.len > s.chan_in.len {
        fail(s, FAIL_CHANNEL)
        ret
    }
    var i = 0usize
    while i < data.len {
        s.chan_in[s.chan_len + i] = data[i]
        i += 1usize
    }
    s.chan_len += data.len
    if usize(s.window_in) >= data.len { s.window_in -= u32(data.len) } else { s.window_in = 0u32 }
}

// Close the session: the channel first, then the connection.
fn close(s: *Session) {
    if s.status == READY || s.status == CHANNEL {
        var msg: [8]u8 = zero
        var w = Writer { buf: msg[0usize..8usize], len: 0usize, over: false }
        w_byte(&w, 97u8)
        w_u32(&w, s.channel_remote)
        send_packet(s, msg[0usize..w.len])
    }
    s.status = CLOSED
}

fn dispatch(s: *Session, payload: []const u8) {
    if payload.len == 0usize {
        fail(s, FAIL_PROTOCOL)
        ret
    }
    let kind = payload[0usize]
    // The messages that mean the same everywhere: IGNORE, DEBUG, UNIMPLEMENTED, DISCONNECT, EXT_INFO.
    if kind == 2u8 || kind == 4u8 || kind == 7u8 || kind == 3u8 { ret }
    if kind == 1u8 {
        fail(s, FAIL_DISCONNECT)
        ret
    }
    if kind == 20u8 {
        // After the session is up this is the server asking to exchange keys again: our KEXINIT goes out, and the
        // exchange runs as the first did, except that the host key is not asked about again.
        if s.have_session_id && s.status != KEX && s.status != VERSION && s.status != HOST_KEY_PENDING {
            if s.rekeying {
                fail(s, FAIL_PROTOCOL)
                ret
            }
            s.rekeying = true
            send_kexinit(s)
        }
        handle_kexinit(s, payload)
        ret
    }
    if kind == 31u8 {
        handle_kex_reply(s, payload)
        ret
    }
    if kind == 21u8 {
        apply_in_keys(s)
        if s.rekeying {
            // The exchange is done: what was held goes out.
            s.rekeying = false
            s.rekeys += 1u32
            if s.deferred_window > 0u32 {
                var msg: [16]u8 = zero
                var w = Writer { buf: msg[0usize..16usize], len: 0usize, over: false }
                w_byte(&w, 93u8)
                w_u32(&w, s.channel_remote)
                w_u32(&w, s.deferred_window)
                send_packet(s, msg[0usize..w.len])
                s.deferred_window = 0u32
            }
            ret
        }
        s.got_newkeys = true
        if s.sent_newkeys { start_auth(s) }
        ret
    }
    if kind == 6u8 {
        // Service accepted: authenticate.
        send_userauth(s)
        ret
    }
    if kind == 53u8 {
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let text_bytes = r_string(&r)
        var n = text_bytes.len
        if n > 256usize { n = 256usize }
        var i = 0usize
        while i < n {
            s.banner[i] = text_bytes[i]
            i += 1usize
        }
        s.banner_len = n
        ret
    }
    if kind == 51u8 {
        fail(s, FAIL_AUTH)
        ret
    }
    if kind == 52u8 {
        open_channel(s)
        ret
    }
    if kind == 60u8 {
        // PK_OK (a key the server would take) is answered by sending the signed request; the server only asks
        // for a changed password otherwise, which is a failure here.
        if s.method == METHOD_KEY { ret }
        fail(s, FAIL_AUTH)
        ret
    }
    if kind == 91u8 {
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let local = r_u32(&r)
        let remote = r_u32(&r)
        let window = r_u32(&r)
        let max = r_u32(&r)
        if r.bad {
            fail(s, FAIL_PROTOCOL)
            ret
        }
        s.channel_remote = remote
        s.window_out = window
        s.max_packet = max
        s.channel_open = true
        request_pty(s)
        ret
    }
    if kind == 92u8 {
        fail(s, FAIL_CHANNEL)
        ret
    }
    if kind == 99u8 {
        if !s.pty_done {
            s.pty_done = true
            request_shell(s)
        } else {
            s.status = READY
        }
        ret
    }
    if kind == 100u8 {
        fail(s, FAIL_CHANNEL)
        ret
    }
    if kind == 93u8 {
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let local = r_u32(&r)
        let add = r_u32(&r)
        if r.bad {
            fail(s, FAIL_PROTOCOL)
            ret
        }
        s.window_out += add
        ret
    }
    if kind == 94u8 {
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let local = r_u32(&r)
        let data = r_string(&r)
        if r.bad {
            fail(s, FAIL_PROTOCOL)
            ret
        }
        handle_channel_data(s, data)
        ret
    }
    if kind == 95u8 {
        // Extended data (stderr): shown with the rest.
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let local = r_u32(&r)
        let code = r_u32(&r)
        let data = r_string(&r)
        if r.bad {
            fail(s, FAIL_PROTOCOL)
            ret
        }
        handle_channel_data(s, data)
        ret
    }
    if kind == 96u8 {
        s.eof_seen = true
        ret
    }
    if kind == 97u8 {
        s.status = CLOSED
        ret
    }
    if kind == 98u8 {
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let local = r_u32(&r)
        let request = r_string(&r)
        let is_exit = same_text(request, "exit-status")
        let want_reply = r_byte(&r)
        if is_exit {
            s.exit_status = r_u32(&r)
            s.has_exit_status = true
        }
        if want_reply != 0u8 {
            var msg: [8]u8 = zero
            var w = Writer { buf: msg[0usize..8usize], len: 0usize, over: false }
            w_byte(&w, 100u8)
            w_u32(&w, s.channel_remote)
            send_packet(s, msg[0usize..w.len])
        }
        ret
    }
    if kind == 80u8 {
        // A global request (host keys, keepalive): refused, as it asks to be answered.
        var r = Reader { buf: payload, pos: 1usize, bad: false }
        let request = r_string(&r)
        let want_reply = r_byte(&r)
        if want_reply != 0u8 {
            var msg: [1]u8 = zero
            msg[0usize] = 82u8
            send_packet(s, msg[0usize..1usize])
        }
        ret
    }
    // Anything else is answered as unimplemented, with its sequence number.
    var msg: [8]u8 = zero
    var w = Writer { buf: msg[0usize..8usize], len: 0usize, over: false }
    w_byte(&w, 3u8)
    w_u32(&w, s.seq_in)
    send_packet(s, msg[0usize..w.len])
}

// ---- input ------------------------------------------------------------------------------------------

// Take one whole packet from the input, if there is one; false when more bytes are needed.
fn take_packet(s: *Session) -> bool {
    if s.status == FAILED || s.status == CLOSED { ret false }
    if s.status == VERSION {
        // The identification line ends at a newline; other lines before it are banner text.
        var i = 0usize
        while i < s.in_len {
            if s.inbuf[i] == 10u8 {
                var end = i
                if end > 0usize && s.inbuf[end - 1usize] == 13u8 { end -= 1usize }
                var is_ident = end >= 4usize && s.inbuf[0usize] == 83u8 && s.inbuf[1usize] == 83u8 && s.inbuf[2usize] == 72u8 && s.inbuf[3usize] == 45u8
                if is_ident {
                    if end > 255usize {
                        fail(s, FAIL_PROTOCOL)
                        ret false
                    }
                    var k = 0usize
                    while k < end {
                        s.server_version[k] = s.inbuf[k]
                        k += 1usize
                    }
                    s.server_version_len = end
                    // Must be SSH-2.0 or SSH-1.99.
                    let v2 = end >= 8usize && s.inbuf[4usize] == 50u8 && s.inbuf[5usize] == 46u8 && s.inbuf[6usize] == 48u8
                    let v199 = end >= 9usize && s.inbuf[4usize] == 49u8 && s.inbuf[5usize] == 46u8 && s.inbuf[6usize] == 57u8 && s.inbuf[7usize] == 57u8
                    if !v2 && !v199 {
                        fail(s, FAIL_UNSUPPORTED)
                        ret false
                    }
                    s.status = KEX
                    send_kexinit(s)
                }
                // Drop the line.
                var rest = s.in_len - (i + 1usize)
                var m = 0usize
                while m < rest {
                    s.inbuf[m] = s.inbuf[i + 1usize + m]
                    m += 1usize
                }
                s.in_len = rest
                ret true
            }
            i += 1usize
        }
        ret false
    }
    // A binary packet.
    if s.in_len < 4usize { ret false }
    var length = 0u32
    var total = 0usize
    var plain_len: [4]u8 = zero
    if s.encrypted_in {
        var i = 0usize
        while i < 4usize {
            plain_len[i] = s.inbuf[i]
            i += 1usize
        }
        // AES-GCM sends the length in the clear (it is the additional data); chacha has its own key for it.
        if s.cipher_in == CIPHER_CHACHA { cipher.chacha20(s.key_in_len, 0u32, chacha_nonce(s.seq_in), plain_len[0usize..4usize]) }
        length = get_u32(plain_len[0usize..4usize], 0usize)
        if length > 35000u32 || length < 5u32 {
            fail(s, FAIL_PROTOCOL)
            ret false
        }
        total = 4usize + usize(length) + 16usize
    } else {
        length = get_u32(s.inbuf, 0usize)
        if length > 35000u32 || length < 5u32 {
            fail(s, FAIL_PROTOCOL)
            ret false
        }
        total = 4usize + usize(length)
    }
    if total > s.inbuf.len {
        fail(s, FAIL_PROTOCOL)
        ret false
    }
    if s.in_len < total { ret false }
    let body = usize(length)
    if s.encrypted_in && s.cipher_in != CIPHER_CHACHA {
        var nonce_in: [12]u8 = zero
        var g = 0usize
        while g < 12usize {
            nonce_in[g] = s.gcm_in_iv[g]
            g += 1usize
        }
        var opened_len = 0usize
        var open_error: err = ok
        if s.cipher_in == CIPHER_AES256_GCM {
            let (n_opened, e_opened) = aead.aes256_gcm_open(s.scratch[0usize..body], s.gcm_in_key, nonce_in, s.inbuf[0usize..4usize], s.inbuf[4usize..4usize + body + 16usize])
            opened_len = n_opened
            open_error = e_opened
        } else {
            var key16: [16]u8 = zero
            g = 0usize
            while g < 16usize {
                key16[g] = s.gcm_in_key[g]
                g += 1usize
            }
            let (n_opened, e_opened) = aead.aes128_gcm_open(s.scratch[0usize..body], key16, nonce_in, s.inbuf[0usize..4usize], s.inbuf[4usize..4usize + body + 16usize])
            opened_len = n_opened
            open_error = e_opened
        }
        if open_error != ok || opened_len != body {
            fail(s, FAIL_MAC)
            ret false
        }
        g = 0usize
        while g < body {
            s.inbuf[4usize + g] = s.scratch[g]
            g += 1usize
        }
        var carry_in = true
        var c_in = 11usize
        while carry_in && c_in >= 4usize {
            s.gcm_in_iv[c_in] = s.gcm_in_iv[c_in] + 1u8
            carry_in = s.gcm_in_iv[c_in] == 0u8
            if c_in == 4usize { carry_in = false }
            c_in -= 1usize
        }
    } else if s.encrypted_in {
        let nonce = chacha_nonce(s.seq_in)
        var poly_key: [32]u8 = zero
        var block: [64]u8 = zero
        let block_error = cipher.chacha20_block(s.key_in_main, 0u32, nonce, block[0usize..64usize])
        var i = 0usize
        while i < 32usize {
            poly_key[i] = block[i]
            i += 1usize
        }
        var tag: [16]u8 = zero
        i = 0usize
        while i < 16usize {
            tag[i] = s.inbuf[4usize + body + i]
            i += 1usize
        }
        if !mac.poly1305_verify(poly_key, s.inbuf[0usize..4usize + body], tag) {
            fail(s, FAIL_MAC)
            ret false
        }
        cipher.chacha20(s.key_in_main, 1u32, nonce, s.inbuf[4usize..4usize + body])
    }
    let pad = usize(s.inbuf[4usize])
    if pad + 1usize > body {
        fail(s, FAIL_PROTOCOL)
        ret false
    }
    let payload_len = body - 1usize - pad
    // Copy the payload out before the buffer is compacted; dispatch may queue replies.
    var payload_copy: [35000]u8 = zero
    var i = 0usize
    while i < payload_len {
        payload_copy[i] = s.inbuf[5usize + i]
        i += 1usize
    }
    var rest = s.in_len - total
    var m = 0usize
    while m < rest {
        s.inbuf[m] = s.inbuf[total + m]
        m += 1usize
    }
    s.in_len = rest
    dispatch(s, payload_copy[0usize..payload_len])
    s.seq_in += 1u32
    ret true
}

// Bytes received from the server.
fn feed(s: *Session, data: []const u8) -> err {
    if s.in_len + data.len > s.inbuf.len {
        fail(s, FAIL_PROTOCOL)
        ret TooLong
    }
    var i = 0usize
    while i < data.len {
        s.inbuf[s.in_len + i] = data[i]
        i += 1usize
    }
    s.in_len += data.len
    var more = true
    while more { more = take_packet(s) }
    if s.status == FAILED { ret Protocol }
    ret ok
}

// The bytes waiting to be sent, and `sent` to take the first `n` of them off.
fn outgoing(s: *Session) -> []const u8 { ret s.outbuf[0usize..s.out_len] }

fn sent(s: *Session, n: usize) {
    var i = n
    while i < s.out_len {
        s.outbuf[i - n] = s.outbuf[i]
        i += 1usize
    }
    if n > s.out_len { s.out_len = 0usize } else { s.out_len -= n }
}

fn status(s: *Session) -> u32 { ret s.status }
