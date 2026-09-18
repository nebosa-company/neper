// TLS 1.3 stream state. Constructors retain the caller's I/O and configuration
// slices in arena-owned state; the handshake and record paths are delivered in
// later slices rather than reporting plaintext transport as TLS.

use e.io
use e.mem
use e.time
use e.crypto.hash as hash
use e.crypto.kdf as kdf
use e.crypto.aead as aead

type Version = enum u8 { Tls13 }
type ClientConfig = struct { server_name: str, trust_roots: []const u8, alpn: []const str, entropy: []const u8, now: time.Timestamp }
type ServerConfig = struct { certificate_chain: []const u8, private_key: []const u8, alpn: []const str, entropy: []const u8 }
type Stream = struct { state: *void }
type TrafficKeys = struct { key: [16]u8, iv: [12]u8, sequence: u64 }

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
