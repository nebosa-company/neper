// TLS 1.3 stream state. Constructors retain the caller's I/O and configuration
// slices in arena-owned state; the handshake and record paths are delivered in
// later slices rather than reporting plaintext transport as TLS.

use e.io
use e.mem
use e.time
use e.crypto.hash as hash
use e.crypto.kdf as kdf
use e.crypto.mac as mac
use e.crypto.aead as aead
use e.crypto.kx as kx
use e.crypto.sign as sign
use e.crypto.x509 as x509
use e.fmt.asn1 as asn1

type Version = enum u8 { Tls13 }
type ClientConfig = struct { server_name: str, trust_roots: []const u8, alpn: []const str, entropy: []const u8, now: time.Timestamp }
type ServerConfig = struct { certificate_chain: []const u8, private_key: []const u8, alpn: []const str, entropy: []const u8 }
type Stream = struct { state: *void }
type TrafficKeys = struct { key: [16]u8, iv: [12]u8, sequence: u64 }
type Cursor = struct { data: []const u8, off: usize }
type ClientHelloInfo = struct { peer_key: kx.X25519PublicKey, selected_alpn: str }
type CertificateSet = struct { leaf: x509.Certificate, intermediates: []const x509.Certificate }
type HandshakeSecrets = struct { client: [32]u8, server: [32]u8, master: [32]u8 }

error InvalidCertificate
error Handshake
error Protocol
error Closed
error Unsupported

type State = struct {
    arena: *mem.Arena,
    source: io.Reader,
    sink: io.Writer,
    client_side: bool,
    client_config: ClientConfig,
    server_config: ServerConfig,
    selected_alpn: str,
    read_keys: TrafficKeys,
    write_keys: TrafficKeys,
    complete: bool,
    failed: bool,
    closed: bool,
    peer_closed: bool,
    read_buffer: [16384]u8,
    read_at: usize,
    read_len: usize,
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

fn parse_der_certificates(a: *mem.Arena, bundle: []const u8) -> ([]const x509.Certificate, err) {
    var count = 0usize
    var probe = asn1.reader(bundle, 16u16)
    while probe.off < probe.data.len {
        let (value, present, value_error) = asn1.reader_next_err(&probe)
        if value_error != ok || !present || !asn1.is_universal(value, 16u32, true) { ret (zero, InvalidCertificate) }
        count += 1usize
    }
    let (certificates, allocation_error) = mem.alloc[x509.Certificate](a, count)
    if allocation_error != ok { ret (zero, allocation_error) }
    var walk = asn1.reader(bundle, 16u16)
    var index = 0usize
    while index < count {
        let (value, present, value_error) = asn1.reader_next_err(&walk)
        if value_error != ok || !present { ret (zero, InvalidCertificate) }
        let (certificate, parse_error) = x509.parse(a, value.encoded)
        if parse_error != ok { ret (zero, InvalidCertificate) }
        certificates[index] = certificate
        index += 1usize
    }
    ret (certificates[0..], ok)
}

// RFC 8410 PKCS#8: version zero, Ed25519 AlgorithmIdentifier without
// parameters, and the 32-byte seed wrapped in the privateKey OCTET STRING.
fn parse_private_key(der: []const u8) -> (sign.Ed25519SecretKey, err) {
    var out: sign.Ed25519SecretKey = zero
    var top = asn1.reader(der, 8u16)
    let (outer, has_outer, outer_error) = asn1.reader_next_err(&top)
    if outer_error != ok || !has_outer || top.off != der.len || !asn1.is_universal(outer, 16u32, true) { ret (out, InvalidCertificate) }
    let (parts0, parts_error) = asn1.children(outer, 8u16)
    if parts_error != ok { ret (out, InvalidCertificate) }
    var parts = parts0
    let (version, has_version, version_error) = asn1.reader_next_err(&parts)
    if version_error != ok || !has_version || !asn1.is_universal(version, 2u32, false) { ret (out, InvalidCertificate) }
    let (version_number, integer_error) = asn1.integer_of(version)
    if integer_error != ok || version_number != 0i64 { ret (out, InvalidCertificate) }
    let (algorithm, has_algorithm, algorithm_error) = asn1.reader_next_err(&parts)
    if algorithm_error != ok || !has_algorithm || !asn1.is_universal(algorithm, 16u32, true) { ret (out, InvalidCertificate) }
    let (algorithm_parts0, algorithm_parts_error) = asn1.children(algorithm, 8u16)
    if algorithm_parts_error != ok { ret (out, InvalidCertificate) }
    var algorithm_parts = algorithm_parts0
    let (oid, has_oid, oid_error) = asn1.reader_next_err(&algorithm_parts)
    if oid_error != ok || !has_oid || !asn1.is_universal(oid, 6u32, false) || oid.content.len != 3usize || oid.content[0] != 43u8 || oid.content[1] != 101u8 || oid.content[2] != 112u8 || algorithm_parts.off != algorithm_parts.data.len { ret (out, InvalidCertificate) }
    let (private_wrapper, has_private, private_error) = asn1.reader_next_err(&parts)
    if private_error != ok || !has_private || !asn1.is_universal(private_wrapper, 4u32, false) || parts.off != parts.data.len { ret (out, InvalidCertificate) }
    var inner = asn1.reader(private_wrapper.content, 2u16)
    let (seed, has_seed, seed_error) = asn1.reader_next_err(&inner)
    if seed_error != ok || !has_seed || inner.off != inner.data.len || !asn1.is_universal(seed, 4u32, false) || seed.content.len != 32usize { ret (out, InvalidCertificate) }
    mem.copy[u8](out.bytes[0..], seed.content)
    ret (out, ok)
}

fn fill_certificate_message(bundle: []const u8, out: []u8, written: *usize) -> err {
    var body_bytes = 4usize
    var scan = asn1.reader(bundle, 16u16)
    var count = 0usize
    while scan.off < scan.data.len {
        let (value, present, value_error) = asn1.reader_next_err(&scan)
        if value_error != ok || !present || !asn1.is_universal(value, 16u32, true) || value.encoded.len > 16777215usize { ret InvalidCertificate }
        if body_bytes > 16777215usize - value.encoded.len - 5usize { ret Protocol }
        body_bytes += value.encoded.len + 5usize
        count += 1usize
    }
    if count == 0usize { ret InvalidCertificate }
    var at = 0usize
    try put_u8(out, &at, 11u8)
    try put_u24(out, &at, body_bytes)
    try put_u8(out, &at, 0u8)
    try put_u24(out, &at, body_bytes - 4usize)
    var walk = asn1.reader(bundle, 16u16)
    while walk.off < walk.data.len {
        let (value, present, value_error) = asn1.reader_next_err(&walk)
        if value_error != ok || !present { ret InvalidCertificate }
        try put_u24(out, &at, value.encoded.len)
        try put_bytes(out, &at, value.encoded)
        try put_u16(out, &at, 0usize)
    }
    *written = at
    ret ok
}

fn build_certificate_message(bundle: []const u8, out: []u8) -> (usize, err) {
    var written = 0usize
    let build_error = fill_certificate_message(bundle, out, &written)
    ret (written, build_error)
}

fn parse_certificate_message(a: *mem.Arena, message: []const u8) -> (CertificateSet, err) {
    var out: CertificateSet = zero
    var c = Cursor { data: message, off: 0usize }
    let (kind, kind_error) = take_u8(&c)
    let (body_len, body_error) = take_u24(&c)
    let (context_len, context_error) = take_u8(&c)
    if kind_error != ok || body_error != ok || context_error != ok || kind != 11u8 || body_len != message.len - 4usize || context_len != 0u8 { ret (out, Protocol) }
    let (list_len, list_error) = take_u24(&c)
    let (list, list_bytes_error) = take_bytes(&c, list_len)
    if list_error != ok || list_bytes_error != ok || c.off != c.data.len || list.len == 0usize { ret (out, Protocol) }
    var probe = Cursor { data: list, off: 0usize }
    var count = 0usize
    while probe.off < probe.data.len {
        let (certificate_len, certificate_len_error) = take_u24(&probe)
        let (_, certificate_error) = take_bytes(&probe, certificate_len)
        let (extensions_len, extensions_error) = take_u16(&probe)
        let (_, extension_bytes_error) = take_bytes(&probe, extensions_len)
        if certificate_len_error != ok || certificate_error != ok || extensions_error != ok || extension_bytes_error != ok || extensions_len != 0usize { ret (out, Protocol) }
        count += 1usize
    }
    let (certificates, allocation_error) = mem.alloc[x509.Certificate](a, count)
    if allocation_error != ok { ret (out, allocation_error) }
    var walk = Cursor { data: list, off: 0usize }
    var index = 0usize
    while index < count {
        let (certificate_len, certificate_len_error) = take_u24(&walk)
        let certificate_start = walk.off
        let (_, certificate_error) = take_bytes(&walk, certificate_len)
        let (extensions_len, extensions_error) = take_u16(&walk)
        let (_, extension_bytes_error) = take_bytes(&walk, extensions_len)
        if certificate_len_error != ok || certificate_error != ok || extensions_error != ok || extension_bytes_error != ok { ret (out, Protocol) }
        let (certificate, parse_error) = x509.parse(a, list[certificate_start..certificate_start + certificate_len])
        if parse_error != ok { ret (out, InvalidCertificate) }
        certificates[index] = certificate
        index += 1usize
    }
    out.leaf = certificates[0]
    out.intermediates = certificates[1usize..]
    ret (out, ok)
}

fn verify_certificate_set(a: *mem.Arena, set: CertificateSet, config: ClientConfig) -> err {
    let (roots, roots_error) = parse_der_certificates(a, config.trust_roots)
    if roots_error != ok || roots.len == 0usize { ret InvalidCertificate }
    var options: x509.VerifyOptions = zero
    options.roots = x509.Pool { certificates: roots }
    options.intermediates = x509.Pool { certificates: set.intermediates }
    options.dns_name = config.server_name
    options.now = time.Instant { nanos: config.now.nanos }
    options.usage = .ServerAuth
    options.max_depth = 8u16
    let (_, verify_error) = x509.verify(a, set.leaf, options)
    if verify_error != ok { ret InvalidCertificate }
    ret ok
}

fn certificate_verify_input(server_side: bool, transcript_hash: [32]u8) -> [130]u8 {
    var out: [130]u8 = zero
    var at = 0usize
    while at < 64usize {
        out[at] = 32u8
        at += 1usize
    }
    let server_context = "TLS 1.3, server CertificateVerify"
    let client_context = "TLS 1.3, client CertificateVerify"
    var context = client_context
    if server_side { context = server_context }
    mem.copy[u8](out[64usize..64usize + context.len], context)
    out[64usize + context.len] = 0u8
    mem.copy[u8](out[65usize + context.len..], transcript_hash[0..])
    ret out
}

fn build_certificate_verify(secret: sign.Ed25519SecretKey, transcript_hash: [32]u8, out: []u8) -> (usize, err) {
    let input = certificate_verify_input(true, transcript_hash)
    let (signature, signature_error) = sign.ed25519_sign(secret, input[0..])
    if signature_error != ok { ret (0usize, InvalidCertificate) }
    if out.len < 72usize { ret (0usize, Protocol) }
    out[0] = 15u8
    out[1] = 0u8
    out[2] = 0u8
    out[3] = 68u8
    out[4] = 8u8
    out[5] = 7u8
    out[6] = 0u8
    out[7] = 64u8
    mem.copy[u8](out[8..72], signature.bytes[0..])
    ret (72usize, ok)
}

fn verify_certificate_verify(leaf: x509.Certificate, transcript_hash: [32]u8, message: []const u8) -> err {
    if message.len != 72usize || message[0] != 15u8 || message[1] != 0u8 || message[2] != 0u8 || message[3] != 68u8 || message[4] != 8u8 || message[5] != 7u8 || message[6] != 0u8 || message[7] != 64u8 { ret Protocol }
    var signature: sign.Ed25519Signature = zero
    mem.copy[u8](signature.bytes[0..], message[8..])
    let input = certificate_verify_input(true, transcript_hash)
    switch leaf.public_key {
    case .Ed25519 as public:
        if sign.ed25519_verify(public, input[0..], signature) { ret ok }
        ret InvalidCertificate
    default:
        ret Unsupported
    }
}

fn validate_server_credentials(a: *mem.Arena, config: ServerConfig) -> (sign.Ed25519SecretKey, err) {
    let (secret, secret_error) = parse_private_key(config.private_key)
    if secret_error != ok { ret (zero, secret_error) }
    let (certificates, certificates_error) = parse_der_certificates(a, config.certificate_chain)
    if certificates_error != ok || certificates.len == 0usize { ret (zero, InvalidCertificate) }
    let (public, public_error) = sign.ed25519_public_from_secret(secret)
    if public_error != ok { ret (zero, InvalidCertificate) }
    switch certificates[0].public_key {
    case .Ed25519 as leaf_public:
        if !bytes_same(public.bytes[0..], leaf_public.bytes[0..]) { ret (zero, InvalidCertificate) }
    default:
        ret (zero, Unsupported)
    }
    ret (secret, ok)
}

fn transcript_digest(transcript: hash.Sha256) -> [32]u8 {
    var copy = transcript
    ret hash.sha256_done(&copy)
}

fn handshake_secrets(shared_key: kx.X25519SharedKey, transcript_hash: [32]u8) -> (HandshakeSecrets, err) {
    var out: HandshakeSecrets = zero
    let zeros: [32]u8 = zero
    let early = kdf.hkdf_sha256_extract("", zeros[0..])
    let (early_derived, early_derived_error) = derive_secret(early, "derived", empty_hash())
    if early_derived_error != ok { ret (out, early_derived_error) }
    let handshake_secret = kdf.hkdf_sha256_extract(early_derived[0..], shared_key.bytes[0..])
    let (client_secret, client_error) = derive_secret(handshake_secret, "c hs traffic", transcript_hash)
    if client_error != ok { ret (out, client_error) }
    let (server_secret, server_error) = derive_secret(handshake_secret, "s hs traffic", transcript_hash)
    if server_error != ok { ret (out, server_error) }
    let (handshake_derived, handshake_derived_error) = derive_secret(handshake_secret, "derived", empty_hash())
    if handshake_derived_error != ok { ret (out, handshake_derived_error) }
    out.client = client_secret
    out.server = server_secret
    out.master = kdf.hkdf_sha256_extract(handshake_derived[0..], zeros[0..])
    ret (out, ok)
}

fn application_keys(secrets: HandshakeSecrets, transcript_hash: [32]u8) -> (TrafficKeys, TrafficKeys, err) {
    var client_keys: TrafficKeys = zero
    var server_keys: TrafficKeys = zero
    let (client_secret, client_secret_error) = derive_secret(secrets.master, "c ap traffic", transcript_hash)
    if client_secret_error != ok { ret (client_keys, server_keys, client_secret_error) }
    let (server_secret, server_secret_error) = derive_secret(secrets.master, "s ap traffic", transcript_hash)
    if server_secret_error != ok { ret (client_keys, server_keys, server_secret_error) }
    let (client_result, client_error) = traffic_keys(client_secret)
    if client_error != ok { ret (client_keys, server_keys, client_error) }
    let (server_result, server_error) = traffic_keys(server_secret)
    ret (client_result, server_result, server_error)
}

fn finished_verify_data(secret: [32]u8, transcript_hash: [32]u8) -> ([32]u8, err) {
    var finished_key: [32]u8 = zero
    let key_error = hkdf_expand_label(secret, "finished", "", finished_key[0..])
    if key_error != ok { ret (zero, key_error) }
    ret (mac.hmac_sha256(finished_key[0..], transcript_hash[0..]), ok)
}

fn build_finished(secret: [32]u8, transcript_hash: [32]u8) -> ([36]u8, err) {
    var out: [36]u8 = zero
    let (verify_data, verify_error) = finished_verify_data(secret, transcript_hash)
    if verify_error != ok { ret (out, verify_error) }
    out[0] = 20u8
    out[3] = 32u8
    mem.copy[u8](out[4..], verify_data[0..])
    ret (out, ok)
}

fn verify_finished(secret: [32]u8, transcript_hash: [32]u8, message: []const u8) -> err {
    if message.len != 36usize || message[0] != 20u8 || message[1] != 0u8 || message[2] != 0u8 || message[3] != 32u8 { ret Protocol }
    let (expected, expected_error) = finished_verify_data(secret, transcript_hash)
    if expected_error != ok { ret expected_error }
    if !hash.equal_constant_time(expected[0..], message[4..]) { ret Handshake }
    ret ok
}

fn build_encrypted_extensions(selected_alpn: str, out: []u8) -> (usize, err) {
    if selected_alpn.len > 255usize { ret (0usize, Protocol) }
    var at = 0usize
    var body_len = 2usize
    if selected_alpn.len != 0usize { body_len += 7usize + selected_alpn.len }
    let first_error = put_u8(out, &at, 8u8)
    if first_error != ok { ret (0usize, first_error) }
    let body_error = put_u24(out, &at, body_len)
    if body_error != ok { ret (0usize, body_error) }
    let extensions_error = put_u16(out, &at, body_len - 2usize)
    if extensions_error != ok { ret (0usize, extensions_error) }
    if selected_alpn.len != 0usize {
        var alpn: [260]u8 = zero
        var alpn_at = 0usize
        let list_error = put_u16(alpn[0..], &alpn_at, selected_alpn.len + 1usize)
        if list_error != ok { ret (0usize, list_error) }
        let length_error = put_u8(alpn[0..], &alpn_at, u8(selected_alpn.len))
        if length_error != ok { ret (0usize, length_error) }
        let protocol_error = put_bytes(alpn[0..], &alpn_at, selected_alpn)
        if protocol_error != ok { ret (0usize, protocol_error) }
        let extension_error = put_extension(out, &at, 16usize, alpn[..alpn_at])
        if extension_error != ok { ret (0usize, extension_error) }
    }
    ret (at, ok)
}

fn parse_encrypted_extensions(message: []const u8, offered: []const str) -> (str, err) {
    var c = Cursor { data: message, off: 0usize }
    let (kind, kind_error) = take_u8(&c)
    let (body_len, body_error) = take_u24(&c)
    let (extensions_len, extensions_error) = take_u16(&c)
    let (extensions, extensions_bytes_error) = take_bytes(&c, extensions_len)
    if kind_error != ok || body_error != ok || extensions_error != ok || extensions_bytes_error != ok || kind != 8u8 || body_len != message.len - 4usize || c.off != c.data.len { ret ("", Protocol) }
    var selected = ""
    var e = Cursor { data: extensions, off: 0usize }
    while e.off < e.data.len {
        let (extension_kind, extension_kind_error) = take_u16(&e)
        let (extension_len, extension_len_error) = take_u16(&e)
        let (value, value_error) = take_bytes(&e, extension_len)
        if extension_kind_error != ok || extension_len_error != ok || value_error != ok { ret ("", Protocol) }
        if extension_kind == 16usize {
            if selected.len != 0usize || value.len < 3usize { ret ("", Protocol) }
            let list_len = (usize(value[0]) << 8usize) | usize(value[1])
            let protocol_len = usize(value[2])
            if list_len != value.len - 2usize || protocol_len != value.len - 3usize || protocol_len == 0usize { ret ("", Protocol) }
            var at = 0usize
            while at < offered.len {
                if bytes_same(value[3..], offered[at]) { selected = offered[at] }
                at += 1usize
            }
            if selected.len == 0usize { ret ("", Unsupported) }
        }
    }
    ret (selected, ok)
}

fn send_plain(state: *State, content_type: u8, content: []const u8) -> err {
    if content.len > 16384usize { ret Protocol }
    var header: [5]u8 = zero
    header[0] = content_type
    header[1] = 3u8
    header[2] = 3u8
    header[3] = u8(content.len >> 8usize)
    header[4] = u8(content.len & 255usize)
    let header_error = io.write_all(&state.sink, header[0..])
    if header_error != ok { ret Handshake }
    let content_error = io.write_all(&state.sink, content)
    if content_error != ok { ret Handshake }
    ret ok
}

fn read_plain(state: *State, expected_type: u8, out: []u8) -> (usize, err) {
    var header: [5]u8 = zero
    let header_error = io.read_exact(&state.source, header[0..])
    if header_error != ok { ret (0usize, Handshake) }
    let length = (usize(header[3]) << 8usize) | usize(header[4])
    if header[0] != expected_type || header[1] != 3u8 || header[2] != 3u8 || length > 16384usize || length > out.len { ret (0usize, Protocol) }
    let content_error = io.read_exact(&state.source, out[..length])
    if content_error != ok { ret (0usize, Handshake) }
    ret (length, ok)
}

fn send_protected(state: *State, keys: *TrafficKeys, content_type: u8, content: []const u8) -> err {
    var record: [16406]u8 = zero
    let (length, seal_error) = seal_record(keys, content_type, content, record[0..])
    if seal_error != ok { ret seal_error }
    let write_error = io.write_all(&state.sink, record[..length])
    if write_error != ok { ret Handshake }
    ret ok
}

fn read_protected_content(state: *State, keys: *TrafficKeys, out: []u8) -> (usize, u8, err) {
    var header: [5]u8 = zero
    let header_error = io.read_exact(&state.source, header[0..])
    if header_error != ok { ret (0usize, 0u8, Handshake) }
    let sealed_len = (usize(header[3]) << 8usize) | usize(header[4])
    if sealed_len > 16640usize { ret (0usize, 0u8, Protocol) }
    var record: [16645]u8 = zero
    mem.copy[u8](record[..5usize], header[0..])
    let record_error = io.read_exact(&state.source, record[5usize..5usize + sealed_len])
    if record_error != ok { ret (0usize, 0u8, Handshake) }
    let (length, content_type, open_error) = open_record(keys, record[..5usize + sealed_len], out)
    ret (length, content_type, open_error)
}

fn read_protected(state: *State, keys: *TrafficKeys, expected_type: u8, out: []u8) -> (usize, err) {
    let (length, content_type, open_error) = read_protected_content(state, keys, out)
    if open_error != ok { ret (0usize, open_error) }
    if content_type != expected_type { ret (0usize, Protocol) }
    ret (length, ok)
}

fn client_handshake(state: *State) -> err {
    var transcript = hash.sha256_init()
    var hello: [4096]u8 = zero
    let (client_hello_len, client_secret, client_hello_error) = build_client_hello(state.client_config, hello[0..])
    if client_hello_error != ok { ret client_hello_error }
    let send_client_error = send_plain(state, 22u8, hello[..client_hello_len])
    if send_client_error != ok { ret send_client_error }
    hash.sha256_update(&transcript, hello[..client_hello_len])
    let (server_hello_len, server_hello_error) = read_plain(state, 22u8, hello[0..])
    if server_hello_error != ok { ret server_hello_error }
    let (server_key, parse_server_error) = parse_server_hello(hello[..server_hello_len])
    if parse_server_error != ok { ret parse_server_error }
    hash.sha256_update(&transcript, hello[..server_hello_len])
    let (shared_key, shared_error) = kx.x25519_exchange(client_secret, server_key)
    if shared_error != ok { ret Handshake }
    let (secrets, secrets_error) = handshake_secrets(shared_key, transcript_digest(transcript))
    if secrets_error != ok { ret secrets_error }
    let (client_handshake_keys0, client_keys_error) = traffic_keys(secrets.client)
    let (server_handshake_keys0, server_keys_error) = traffic_keys(secrets.server)
    if client_keys_error != ok || server_keys_error != ok { ret Handshake }
    var client_handshake_keys = client_handshake_keys0
    var server_handshake_keys = server_handshake_keys0
    var message: [16384]u8 = zero
    let (extensions_len, extensions_error) = read_protected(state, &server_handshake_keys, 22u8, message[0..])
    if extensions_error != ok { ret extensions_error }
    let (selected, selection_error) = parse_encrypted_extensions(message[..extensions_len], state.client_config.alpn)
    if selection_error != ok { ret selection_error }
    state.selected_alpn = selected
    hash.sha256_update(&transcript, message[..extensions_len])
    let (certificate_len, certificate_error) = read_protected(state, &server_handshake_keys, 22u8, message[0..])
    if certificate_error != ok { ret certificate_error }
    let (certificates, parse_certificate_error) = parse_certificate_message(state.arena, message[..certificate_len])
    if parse_certificate_error != ok { ret parse_certificate_error }
    let verify_chain_error = verify_certificate_set(state.arena, certificates, state.client_config)
    if verify_chain_error != ok { ret verify_chain_error }
    hash.sha256_update(&transcript, message[..certificate_len])
    let (certificate_verify_len, certificate_verify_error) = read_protected(state, &server_handshake_keys, 22u8, message[0..])
    if certificate_verify_error != ok { ret certificate_verify_error }
    let verify_signature_error = verify_certificate_verify(certificates.leaf, transcript_digest(transcript), message[..certificate_verify_len])
    if verify_signature_error != ok { ret verify_signature_error }
    hash.sha256_update(&transcript, message[..certificate_verify_len])
    let (server_finished_len, server_finished_error) = read_protected(state, &server_handshake_keys, 22u8, message[0..])
    if server_finished_error != ok { ret server_finished_error }
    let verify_server_finished_error = verify_finished(secrets.server, transcript_digest(transcript), message[..server_finished_len])
    if verify_server_finished_error != ok { ret verify_server_finished_error }
    hash.sha256_update(&transcript, message[..server_finished_len])
    let application_hash = transcript_digest(transcript)
    let (client_application_keys, server_application_keys, application_error) = application_keys(secrets, application_hash)
    if application_error != ok { ret application_error }
    let (client_finished, client_finished_error) = build_finished(secrets.client, application_hash)
    if client_finished_error != ok { ret client_finished_error }
    let send_finished_error = send_protected(state, &client_handshake_keys, 22u8, client_finished[0..])
    if send_finished_error != ok { ret send_finished_error }
    state.write_keys = client_application_keys
    state.read_keys = server_application_keys
    ret ok
}

fn server_handshake(state: *State) -> err {
    var transcript = hash.sha256_init()
    var hello: [4096]u8 = zero
    let (client_hello_len, client_hello_error) = read_plain(state, 22u8, hello[0..])
    if client_hello_error != ok { ret client_hello_error }
    let (client_info, parse_client_error) = parse_client_hello(hello[..client_hello_len], state.server_config.alpn)
    if parse_client_error != ok { ret parse_client_error }
    state.selected_alpn = client_info.selected_alpn
    hash.sha256_update(&transcript, hello[..client_hello_len])
    let (signing_key, credential_error) = validate_server_credentials(state.arena, state.server_config)
    if credential_error != ok { ret credential_error }
    let (server_hello_len, server_secret, server_hello_error) = build_server_hello(state.server_config, hello[0..])
    if server_hello_error != ok { ret server_hello_error }
    let send_server_error = send_plain(state, 22u8, hello[..server_hello_len])
    if send_server_error != ok { ret send_server_error }
    hash.sha256_update(&transcript, hello[..server_hello_len])
    let (shared_key, shared_error) = kx.x25519_exchange(server_secret, client_info.peer_key)
    if shared_error != ok { ret Handshake }
    let (secrets, secrets_error) = handshake_secrets(shared_key, transcript_digest(transcript))
    if secrets_error != ok { ret secrets_error }
    let (client_handshake_keys0, client_keys_error) = traffic_keys(secrets.client)
    let (server_handshake_keys0, server_keys_error) = traffic_keys(secrets.server)
    if client_keys_error != ok || server_keys_error != ok { ret Handshake }
    var client_handshake_keys = client_handshake_keys0
    var server_handshake_keys = server_handshake_keys0
    var message: [16384]u8 = zero
    let (extensions_len, extensions_error) = build_encrypted_extensions(state.selected_alpn, message[0..])
    if extensions_error != ok { ret extensions_error }
    let send_extensions_error = send_protected(state, &server_handshake_keys, 22u8, message[..extensions_len])
    if send_extensions_error != ok { ret send_extensions_error }
    hash.sha256_update(&transcript, message[..extensions_len])
    let (certificate_len, certificate_error) = build_certificate_message(state.server_config.certificate_chain, message[0..])
    if certificate_error != ok { ret certificate_error }
    let send_certificate_error = send_protected(state, &server_handshake_keys, 22u8, message[..certificate_len])
    if send_certificate_error != ok { ret send_certificate_error }
    hash.sha256_update(&transcript, message[..certificate_len])
    let (certificate_verify_len, certificate_verify_error) = build_certificate_verify(signing_key, transcript_digest(transcript), message[0..])
    if certificate_verify_error != ok { ret certificate_verify_error }
    let send_certificate_verify_error = send_protected(state, &server_handshake_keys, 22u8, message[..certificate_verify_len])
    if send_certificate_verify_error != ok { ret send_certificate_verify_error }
    hash.sha256_update(&transcript, message[..certificate_verify_len])
    let (server_finished, server_finished_error) = build_finished(secrets.server, transcript_digest(transcript))
    if server_finished_error != ok { ret server_finished_error }
    let send_finished_error = send_protected(state, &server_handshake_keys, 22u8, server_finished[0..])
    if send_finished_error != ok { ret send_finished_error }
    hash.sha256_update(&transcript, server_finished[0..])
    let application_hash = transcript_digest(transcript)
    let (client_application_keys, server_application_keys, application_error) = application_keys(secrets, application_hash)
    if application_error != ok { ret application_error }
    let (client_finished_len, client_finished_error) = read_protected(state, &client_handshake_keys, 22u8, message[0..])
    if client_finished_error != ok { ret client_finished_error }
    let verify_client_finished_error = verify_finished(secrets.client, application_hash, message[..client_finished_len])
    if verify_client_finished_error != ok { ret verify_client_finished_error }
    state.read_keys = client_application_keys
    state.write_keys = server_application_keys
    ret ok
}

fn client(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ClientConfig) -> (Stream, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let state = &storage[0usize]
    state.arena = a
    state.source = source
    state.sink = sink
    state.client_side = true
    state.client_config = config
    state.server_config = ServerConfig { certificate_chain: "", private_key: "", alpn: config.alpn[0usize..0usize], entropy: config.entropy[0usize..0usize] }
    state.selected_alpn = ""
    state.complete = false
    state.failed = false
    state.closed = false
    state.peer_closed = false
    state.read_at = 0usize
    state.read_len = 0usize
    ret (Stream { state: mem.cast[*void](state) }, ok)
}

fn server(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ServerConfig) -> (Stream, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let state = &storage[0usize]
    state.arena = a
    state.source = source
    state.sink = sink
    state.client_side = false
    state.client_config = ClientConfig { server_name: "", trust_roots: "", alpn: config.alpn[0usize..0usize], entropy: config.entropy[0usize..0usize], now: time.Timestamp { nanos: 0i64 } }
    state.server_config = config
    state.selected_alpn = ""
    state.complete = false
    state.failed = false
    state.closed = false
    state.peer_closed = false
    state.read_at = 0usize
    state.read_len = 0usize
    ret (Stream { state: mem.cast[*void](state) }, ok)
}

fn protocol(stream: *const Stream) -> Version { ret .Tls13 }

fn negotiated_alpn(stream: *const Stream) -> str {
    let state = mem.cast[*const State](stream.state)
    ret state.selected_alpn
}

fn handshake(stream: *Stream) -> err {
    if stream.state == nil { ret Closed }
    let state = mem.cast[*State](stream.state)
    if state.closed || state.failed { ret Closed }
    if state.complete { ret ok }
    var handshake_error: err = ok
    if state.client_side {
        handshake_error = client_handshake(state)
    } else {
        handshake_error = server_handshake(state)
    }
    if handshake_error != ok {
        state.failed = true
        ret handshake_error
    }
    state.complete = true
    ret ok
}

fn stream_read(ctx: *void, dst: []u8) -> (usize, err) {
    let state = mem.cast[*State](ctx)
    if state.closed || state.failed || !state.complete { ret (0usize, Closed) }
    if state.peer_closed { ret (0usize, io.End) }
    while state.read_at == state.read_len {
        let (length, content_type, read_error) = read_protected_content(state, &state.read_keys, state.read_buffer[0..])
        if read_error != ok {
            state.failed = true
            ret (0usize, read_error)
        }
        if content_type == 21u8 {
            if length != 2usize || state.read_buffer[1] != 0u8 {
                state.failed = true
                ret (0usize, Protocol)
            }
            state.peer_closed = true
            ret (0usize, io.End)
        }
        if content_type != 23u8 {
            state.failed = true
            ret (0usize, Protocol)
        }
        state.read_at = 0usize
        state.read_len = length
        // Empty application records are cover traffic, not end-of-stream.
    }
    var count = dst.len
    let available = state.read_len - state.read_at
    if count > available { count = available }
    mem.copy[u8](dst[..count], state.read_buffer[state.read_at..state.read_at + count])
    state.read_at += count
    ret (count, ok)
}

fn stream_write(ctx: *void, src: []const u8) -> (usize, err) {
    let state = mem.cast[*State](ctx)
    if state.closed || state.peer_closed || state.failed || !state.complete { ret (0usize, Closed) }
    var count = src.len
    if count > 16384usize { count = 16384usize }
    let write_error = send_protected(state, &state.write_keys, 23u8, src[..count])
    if write_error != ok {
        state.failed = true
        ret (0usize, write_error)
    }
    ret (count, ok)
}

fn stream_flush(ctx: *void) -> err {
    let state = mem.cast[*State](ctx)
    if state.closed || state.failed || !state.complete { ret Closed }
    ret io.flush(&state.sink)
}

fn reader(stream: *Stream) -> io.Reader {
    ret io.Reader { ctx: stream.state, read: stream_read }
}

fn writer(stream: *Stream) -> io.Writer {
    ret io.Writer { ctx: stream.state, write: stream_write, flush: stream_flush }
}
