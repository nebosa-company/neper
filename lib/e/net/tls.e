// TLS 1.3 stream state. Constructors retain the caller's I/O and configuration
// slices in arena-owned state; the handshake and record paths are delivered in
// later slices rather than reporting plaintext transport as TLS.

use e.io
use e.mem
use e.time
use e.crypto.hash as hash
use e.crypto.kdf as kdf

type Version = enum u8 { Tls13 }
type ClientConfig = struct { server_name: str, trust_roots: []const u8, alpn: []const str, entropy: []const u8, now: time.Timestamp }
type ServerConfig = struct { certificate_chain: []const u8, private_key: []const u8, alpn: []const str, entropy: []const u8 }
type Stream = struct { state: *void }

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
