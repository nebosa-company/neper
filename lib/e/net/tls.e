// TLS 1.3 stream state. Constructors retain the caller's I/O and configuration
// slices in arena-owned state; the handshake and record paths are delivered in
// later slices rather than reporting plaintext transport as TLS.

use e.io
use e.mem
use e.time

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
