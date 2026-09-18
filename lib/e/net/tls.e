// TLS 1.3 stream state. Constructors retain the caller's I/O and configuration
// slices in arena-owned state; the handshake and record paths are delivered in
// later slices rather than reporting plaintext transport as TLS.

use e.io
use e.mem
use e.time
use e.crypto.hash as hash
use e.crypto.kdf as kdf
use e.crypto.aead as aead
use e.crypto.kx as kx

type Version = enum u8 { Tls13 }
type ClientConfig = struct { server_name: str, trust_roots: []const u8, alpn: []const str, entropy: []const u8, now: time.Timestamp }
type ServerConfig = struct { certificate_chain: []const u8, private_key: []const u8, alpn: []const str, entropy: []const u8 }
type Stream = struct { state: *void }
type TrafficKeys = struct { key: [16]u8, iv: [12]u8, sequence: u64 }
type Cursor = struct { data: []const u8, off: usize }
type ClientHelloInfo = struct { peer_key: kx.X25519PublicKey, selected_alpn: str }

error InvalidCertificate
error Handshake
error Protocol
error Closed
error Unsupported

type State = struct {
    source: io.Reader,
    sink: io.Writer,
    client_side: bool,
    client_config: ClientConfig,
    server_config: ServerConfig,
    selected_alpn: str,
}

// RFC 8446 section 7.1's HKDF-Expand-Label over the one supported hash. The
// fixed buffer is larger than every TLS 1.3 label; the explicit one-byte
// vector limits prevent accidental truncation.
fn hkdf_expand_label(secret: [32]u8, label: str, context: []const u8, out: []u8) -> err {
    if label.len > 249usize || context.len > 255usize || out.len > 65535usize { ret Protocol }
    var info: [512]u8 = zero
    let full_label_len = 6usize + label.len
    let info_len = 2usize + 1usize + full_label_len + 1usize + context.len
    info[0] = u8(out.len >> 8usize)
    info[1] = u8(out.len & 255usize)
    info[2] = u8(full_label_len)
    let prefix = "tls13 "
    var at = 0usize
    while at < prefix.len {
        info[3usize + at] = prefix[at]
        at += 1usize
    }
    at = 0usize
    while at < label.len {
        info[9usize + at] = label[at]
        at += 1usize
    }
    let context_len_at = 3usize + full_label_len
    info[context_len_at] = u8(context.len)
    at = 0usize
    while at < context.len {
        info[context_len_at + 1usize + at] = context[at]
        at += 1usize
    }
    ret kdf.hkdf_sha256_expand(out, secret, info[..info_len])
}

fn derive_secret(secret: [32]u8, label: str, transcript_hash: [32]u8) -> ([32]u8, err) {
    var out: [32]u8 = zero
    let expand_error = hkdf_expand_label(secret, label, transcript_hash[0..], out[0..])
    ret (out, expand_error)
}

fn empty_hash() -> [32]u8 { ret hash.sha256("") }

fn traffic_keys(secret: [32]u8) -> (TrafficKeys, err) {
    var out: TrafficKeys = zero
    let key_error = hkdf_expand_label(secret, "key", "", out.key[0..])
    if key_error != ok { ret (out, key_error) }
    let iv_error = hkdf_expand_label(secret, "iv", "", out.iv[0..])
    ret (out, iv_error)
}

fn record_nonce(keys: *const TrafficKeys) -> [12]u8 {
    var nonce = keys.iv
    var at = 0usize
    while at < 8usize {
        let shift = u32((7usize - at) * 8usize)
        nonce[4usize + at] = nonce[4usize + at] ^ u8((keys.sequence >> shift) & 255u64)
        at += 1usize
    }
    ret nonce
}

// One unpadded TLSCiphertext. The header is authenticated, and the sequence
// advances only after a successful seal/open.
fn seal_record(keys: *TrafficKeys, content_type: u8, content: []const u8, out: []u8) -> (usize, err) {
    if content.len > 16384usize { ret (0usize, Protocol) }
    if content_type != 21u8 && content_type != 22u8 && content_type != 23u8 { ret (0usize, Protocol) }
    if content.len == 0usize && content_type != 23u8 { ret (0usize, Protocol) }
    let sealed_len = content.len + 17usize
    if out.len < sealed_len + 5usize || keys.sequence == 18446744073709551615u64 { ret (0usize, Protocol) }
    out[0] = 23u8
    out[1] = 3u8
    out[2] = 3u8
    out[3] = u8(sealed_len >> 8usize)
    out[4] = u8(sealed_len & 255usize)
    var inner: [16385]u8 = zero
    mem.copy[u8](inner[..content.len], content)
    inner[content.len] = content_type
    let nonce = record_nonce(keys)
    let (written, seal_error) = aead.aes128_gcm_seal(out[5usize..], keys.key, nonce, out[..5usize], inner[..content.len + 1usize])
    if seal_error != ok { ret (0usize, seal_error) }
    keys.sequence += 1u64
    ret (5usize + written, ok)
}

fn open_record(keys: *TrafficKeys, record: []const u8, out: []u8) -> (usize, u8, err) {
    if record.len < 22usize || record[0] != 23u8 || record[1] != 3u8 || record[2] != 3u8 { ret (0usize, 0u8, Protocol) }
    let sealed_len = (usize(record[3]) << 8usize) | usize(record[4])
    if sealed_len > 16640usize || sealed_len + 5usize != record.len || keys.sequence == 18446744073709551615u64 { ret (0usize, 0u8, Protocol) }
    var inner: [16385]u8 = zero
    let nonce = record_nonce(keys)
    let (plain_len, open_error) = aead.aes128_gcm_open(inner[0..], keys.key, nonce, record[..5usize], record[5usize..])
    if open_error != ok { ret (0usize, 0u8, Protocol) }
    var end = plain_len
    while end > 0usize && inner[end - 1usize] == 0u8 { end -= 1usize }
    if end == 0usize { ret (0usize, 0u8, Protocol) }
    let content_type = inner[end - 1usize]
    if content_type != 21u8 && content_type != 22u8 && content_type != 23u8 { ret (0usize, 0u8, Protocol) }
    let content_len = end - 1usize
    if content_len == 0usize && content_type != 23u8 { ret (0usize, 0u8, Protocol) }
    if out.len < content_len { ret (0usize, 0u8, Protocol) }
    mem.copy[u8](out[..content_len], inner[..content_len])
    keys.sequence += 1u64
    ret (content_len, content_type, ok)
}

fn put_u8(out: []u8, at: *usize, value: u8) -> err {
    if *at >= out.len { ret Protocol }
    out[*at] = value
    *at += 1usize
    ret ok
}

fn put_u16(out: []u8, at: *usize, value: usize) -> err {
    if value > 65535usize || *at + 2usize > out.len { ret Protocol }
    out[*at] = u8(value >> 8usize)
    out[*at + 1usize] = u8(value & 255usize)
    *at += 2usize
    ret ok
}

fn put_u24(out: []u8, at: *usize, value: usize) -> err {
    if value > 16777215usize || *at + 3usize > out.len { ret Protocol }
    out[*at] = u8(value >> 16usize)
    out[*at + 1usize] = u8((value >> 8usize) & 255usize)
    out[*at + 2usize] = u8(value & 255usize)
    *at += 3usize
    ret ok
}

fn put_bytes(out: []u8, at: *usize, value: []const u8) -> err {
    if value.len > out.len - *at { ret Protocol }
    mem.copy[u8](out[*at..*at + value.len], value)
    *at += value.len
    ret ok
}

fn take_u8(c: *Cursor) -> (u8, err) {
    if c.off >= c.data.len { ret (0u8, Protocol) }
    let value = c.data[c.off]
    c.off += 1usize
    ret (value, ok)
}

fn take_u16(c: *Cursor) -> (usize, err) {
    if c.off + 2usize > c.data.len { ret (0usize, Protocol) }
    let value = (usize(c.data[c.off]) << 8usize) | usize(c.data[c.off + 1usize])
    c.off += 2usize
    ret (value, ok)
}

fn take_u24(c: *Cursor) -> (usize, err) {
    if c.off + 3usize > c.data.len { ret (0usize, Protocol) }
    let value = (usize(c.data[c.off]) << 16usize) | (usize(c.data[c.off + 1usize]) << 8usize) | usize(c.data[c.off + 2usize])
    c.off += 3usize
    ret (value, ok)
}

fn take_bytes(c: *Cursor, count: usize) -> ([]const u8, err) {
    if count > c.data.len - c.off { ret (zero, Protocol) }
    let value = c.data[c.off..c.off + count]
    c.off += count
    ret (value, ok)
}

fn bytes_same(left: []const u8, right: []const u8) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn put_extension(out: []u8, at: *usize, kind: usize, value: []const u8) -> err {
    try put_u16(out, at, kind)
    try put_u16(out, at, value.len)
    ret put_bytes(out, at, value)
}

fn valid_protocols(protocols: []const str) -> (usize, err) {
    var total = 0usize
    var at = 0usize
    while at < protocols.len {
        let length = protocols[at].len
        if length == 0usize || length > 255usize || total > 65535usize - length - 1usize { ret (0usize, Protocol) }
        total += length + 1usize
        at += 1usize
    }
    ret (total, ok)
}

fn fill_client_hello(config: ClientConfig, out: []u8, secret: *kx.X25519SecretKey, written: *usize) -> err {
    if config.entropy.len < 64usize || config.server_name.len > 253usize { ret Unsupported }
    mem.copy[u8](secret.bytes[0..], config.entropy[32usize..64usize])
    let public = kx.x25519_public_from_secret(*secret)
    let (protocol_bytes, protocols_error) = valid_protocols(config.alpn)
    if protocols_error != ok { ret protocols_error }
    var at = 0usize
    try put_u8(out, &at, 1u8)
    let body_length_at = at
    try put_u24(out, &at, 0usize)
    try put_u16(out, &at, 771usize)
    try put_bytes(out, &at, config.entropy[..32usize])
    try put_u8(out, &at, 0u8)
    try put_u16(out, &at, 2usize)
    try put_u16(out, &at, 4865usize)
    try put_u8(out, &at, 1u8)
    try put_u8(out, &at, 0u8)
    let extensions_length_at = at
    try put_u16(out, &at, 0usize)
    let extensions_start = at
    if config.server_name.len != 0usize {
        var name: [260]u8 = zero
        var name_at = 0usize
        try put_u16(name[0..], &name_at, config.server_name.len + 3usize)
        try put_u8(name[0..], &name_at, 0u8)
        try put_u16(name[0..], &name_at, config.server_name.len)
        try put_bytes(name[0..], &name_at, config.server_name)
        try put_extension(out, &at, 0usize, name[..name_at])
    }
    let versions: [3]u8 = [3]u8{ 2, 3, 4 }
    try put_extension(out, &at, 43usize, versions[0..])
    let groups: [4]u8 = [4]u8{ 0, 2, 0, 29 }
    try put_extension(out, &at, 10usize, groups[0..])
    let signatures: [4]u8 = [4]u8{ 0, 2, 8, 7 }
    try put_extension(out, &at, 13usize, signatures[0..])
    var share: [38]u8 = zero
    share[1] = 36u8
    share[3] = 29u8
    share[5] = 32u8
    mem.copy[u8](share[6..], public.bytes[0..])
    try put_extension(out, &at, 51usize, share[0..])
    if protocol_bytes != 0usize {
        var protocols: [65535]u8 = zero
        var protocols_at = 0usize
        try put_u16(protocols[0..], &protocols_at, protocol_bytes)
        var index = 0usize
        while index < config.alpn.len {
            try put_u8(protocols[0..], &protocols_at, u8(config.alpn[index].len))
            try put_bytes(protocols[0..], &protocols_at, config.alpn[index])
            index += 1usize
        }
        try put_extension(out, &at, 16usize, protocols[..protocols_at])
    }
    let extensions_length = at - extensions_start
    out[extensions_length_at] = u8(extensions_length >> 8usize)
    out[extensions_length_at + 1usize] = u8(extensions_length & 255usize)
    let body_length = at - 4usize
    out[body_length_at] = u8(body_length >> 16usize)
    out[body_length_at + 1usize] = u8((body_length >> 8usize) & 255usize)
    out[body_length_at + 2usize] = u8(body_length & 255usize)
    *written = at
    ret ok
}

fn build_client_hello(config: ClientConfig, out: []u8) -> (usize, kx.X25519SecretKey, err) {
    var secret: kx.X25519SecretKey = zero
    var written = 0usize
    let build_error = fill_client_hello(config, out, &secret, &written)
    ret (written, secret, build_error)
}

fn select_alpn(encoded: []const u8, supported: []const str) -> (str, err) {
    var choice = ""
    var wanted = 0usize
    while wanted < supported.len {
        var list = Cursor { data: encoded, off: 0usize }
        while list.off < list.data.len {
            let (length, length_error) = take_u8(&list)
            if length_error != ok || length == 0u8 { ret ("", Protocol) }
            let (candidate, candidate_error) = take_bytes(&list, usize(length))
            if candidate_error != ok { ret ("", candidate_error) }
            if bytes_same(candidate, supported[wanted]) { choice = supported[wanted] }
        }
        if choice.len != 0usize { ret (choice, ok) }
        wanted += 1usize
    }
    ret ("", Unsupported)
}

fn parse_client_hello(message: []const u8, supported_alpn: []const str) -> (ClientHelloInfo, err) {
    var out: ClientHelloInfo = zero
    var c = Cursor { data: message, off: 0usize }
    let (kind, kind_error) = take_u8(&c)
    let (body_len, body_error) = take_u24(&c)
    if kind_error != ok || body_error != ok || kind != 1u8 || body_len != message.len - 4usize { ret (out, Protocol) }
    let (legacy, legacy_error) = take_u16(&c)
    if legacy_error != ok || legacy != 771usize { ret (out, Protocol) }
    let (_, random_error) = take_bytes(&c, 32usize)
    let (session_len, session_error) = take_u8(&c)
    if random_error != ok || session_error != ok || session_len > 32u8 { ret (out, Protocol) }
    let (_, session_bytes_error) = take_bytes(&c, usize(session_len))
    let (cipher_len, cipher_error) = take_u16(&c)
    if session_bytes_error != ok || cipher_error != ok || cipher_len == 0usize || cipher_len % 2usize != 0usize { ret (out, Protocol) }
    let (ciphers, ciphers_error) = take_bytes(&c, cipher_len)
    if ciphers_error != ok { ret (out, ciphers_error) }
    var has_cipher = false
    var cipher_at = 0usize
    while cipher_at < ciphers.len {
        if ciphers[cipher_at] == 19u8 && ciphers[cipher_at + 1usize] == 1u8 { has_cipher = true }
        cipher_at += 2usize
    }
    let (compression_len, compression_error) = take_u8(&c)
    if compression_error != ok || compression_len == 0u8 { ret (out, Protocol) }
    let (compression, compression_bytes_error) = take_bytes(&c, usize(compression_len))
    if compression_bytes_error != ok || compression[0] != 0u8 || !has_cipher { ret (out, Unsupported) }
    let (extensions_len, extensions_error) = take_u16(&c)
    let (extensions, extension_bytes_error) = take_bytes(&c, extensions_len)
    if extensions_error != ok || extension_bytes_error != ok || c.off != c.data.len { ret (out, Protocol) }
    var e = Cursor { data: extensions, off: 0usize }
    var has_version = false
    var has_group = false
    var has_signature = false
    var has_share = false
    var offered_alpn: []const u8 = zero
    while e.off < e.data.len {
        let (extension_kind, extension_kind_error) = take_u16(&e)
        let (extension_len, extension_len_error) = take_u16(&e)
        let (value, value_error) = take_bytes(&e, extension_len)
        if extension_kind_error != ok || extension_len_error != ok || value_error != ok { ret (out, Protocol) }
        if extension_kind == 43usize { has_version = value.len == 3usize && value[0] == 2u8 && value[1] == 3u8 && value[2] == 4u8 }
        if extension_kind == 10usize { has_group = value.len == 4usize && value[0] == 0u8 && value[1] == 2u8 && value[2] == 0u8 && value[3] == 29u8 }
        if extension_kind == 13usize { has_signature = value.len == 4usize && value[0] == 0u8 && value[1] == 2u8 && value[2] == 8u8 && value[3] == 7u8 }
        if extension_kind == 51usize {
            if value.len == 38usize && value[0] == 0u8 && value[1] == 36u8 && value[2] == 0u8 && value[3] == 29u8 && value[4] == 0u8 && value[5] == 32u8 {
                mem.copy[u8](out.peer_key.bytes[0..], value[6..])
                has_share = true
            }
        }
        if extension_kind == 16usize {
            if value.len < 2usize { ret (out, Protocol) }
            let listed = (usize(value[0]) << 8usize) | usize(value[1])
            if listed != value.len - 2usize { ret (out, Protocol) }
            offered_alpn = value[2usize..]
        }
    }
    if !has_version || !has_group || !has_signature || !has_share { ret (out, Unsupported) }
    if supported_alpn.len != 0usize {
        if offered_alpn.len == 0usize { ret (out, Unsupported) }
        let (selected, selection_error) = select_alpn(offered_alpn, supported_alpn)
        if selection_error != ok { ret (out, selection_error) }
        out.selected_alpn = selected
    }
    ret (out, ok)
}

fn fill_server_hello(config: ServerConfig, out: []u8, secret: *kx.X25519SecretKey, written: *usize) -> err {
    if config.entropy.len < 64usize { ret Unsupported }
    mem.copy[u8](secret.bytes[0..], config.entropy[32usize..64usize])
    let public = kx.x25519_public_from_secret(*secret)
    var at = 0usize
    try put_u8(out, &at, 2u8)
    try put_u24(out, &at, 86usize)
    try put_u16(out, &at, 771usize)
    try put_bytes(out, &at, config.entropy[..32usize])
    try put_u8(out, &at, 0u8)
    try put_u16(out, &at, 4865usize)
    try put_u8(out, &at, 0u8)
    try put_u16(out, &at, 46usize)
    var share: [36]u8 = zero
    share[1] = 29u8
    share[3] = 32u8
    mem.copy[u8](share[4..], public.bytes[0..])
    try put_extension(out, &at, 51usize, share[0..])
    let version: [2]u8 = [2]u8{ 3, 4 }
    try put_extension(out, &at, 43usize, version[0..])
    *written = at
    ret ok
}

fn build_server_hello(config: ServerConfig, out: []u8) -> (usize, kx.X25519SecretKey, err) {
    var secret: kx.X25519SecretKey = zero
    var written = 0usize
    let build_error = fill_server_hello(config, out, &secret, &written)
    ret (written, secret, build_error)
}

fn parse_server_hello(message: []const u8) -> (kx.X25519PublicKey, err) {
    var key: kx.X25519PublicKey = zero
    var c = Cursor { data: message, off: 0usize }
    let (kind, kind_error) = take_u8(&c)
    let (body_len, body_error) = take_u24(&c)
    if kind_error != ok || body_error != ok || kind != 2u8 || body_len != message.len - 4usize { ret (key, Protocol) }
    let (legacy, legacy_error) = take_u16(&c)
    let (_, random_error) = take_bytes(&c, 32usize)
    let (session_len, session_error) = take_u8(&c)
    if legacy_error != ok || random_error != ok || session_error != ok || legacy != 771usize || session_len > 32u8 { ret (key, Protocol) }
    let (_, session_bytes_error) = take_bytes(&c, usize(session_len))
    let (cipher, cipher_error) = take_u16(&c)
    let (compression, compression_error) = take_u8(&c)
    let (extensions_len, extensions_error) = take_u16(&c)
    let (extensions, extension_bytes_error) = take_bytes(&c, extensions_len)
    if session_bytes_error != ok || cipher_error != ok || compression_error != ok || extensions_error != ok || extension_bytes_error != ok || c.off != c.data.len { ret (key, Protocol) }
    if cipher != 4865usize || compression != 0u8 { ret (key, Unsupported) }
    var e = Cursor { data: extensions, off: 0usize }
    var has_version = false
    var has_share = false
    while e.off < e.data.len {
        let (extension_kind, extension_kind_error) = take_u16(&e)
        let (extension_len, extension_len_error) = take_u16(&e)
        let (value, value_error) = take_bytes(&e, extension_len)
        if extension_kind_error != ok || extension_len_error != ok || value_error != ok { ret (key, Protocol) }
        if extension_kind == 43usize { has_version = value.len == 2usize && value[0] == 3u8 && value[1] == 4u8 }
        if extension_kind == 51usize && value.len == 36usize && value[0] == 0u8 && value[1] == 29u8 && value[2] == 0u8 && value[3] == 32u8 {
            mem.copy[u8](key.bytes[0..], value[4..])
            has_share = true
        }
    }
    if !has_version || !has_share { ret (key, Unsupported) }
    ret (key, ok)
}

fn client(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ClientConfig) -> (Stream, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let state = &storage[0usize]
    state.source = source
    state.sink = sink
    state.client_side = true
    state.client_config = config
    state.server_config = ServerConfig { certificate_chain: "", private_key: "", alpn: config.alpn[0usize..0usize], entropy: config.entropy[0usize..0usize] }
    state.selected_alpn = ""
    ret (Stream { state: mem.cast[*void](state) }, ok)
}

fn server(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ServerConfig) -> (Stream, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let state = &storage[0usize]
    state.source = source
    state.sink = sink
    state.client_side = false
    state.client_config = ClientConfig { server_name: "", trust_roots: "", alpn: config.alpn[0usize..0usize], entropy: config.entropy[0usize..0usize], now: time.Timestamp { nanos: 0i64 } }
    state.server_config = config
    state.selected_alpn = ""
    ret (Stream { state: mem.cast[*void](state) }, ok)
}

fn protocol(stream: *const Stream) -> Version { ret .Tls13 }

fn negotiated_alpn(stream: *const Stream) -> str {
    let state = mem.cast[*const State](stream.state)
    ret state.selected_alpn
}
