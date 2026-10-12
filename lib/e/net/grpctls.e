// The TLS dial helper of gRPC (L164): a TCP connection to an endpoint, a TLS 1.3 handshake that offers only `h2` through
// ALPN and refuses a server that does not select it, and the `io.Reader` and `io.Writer` of the protected stream that
// `e.net.grpc` or `e.net.grpcserver` is driven over (`conn_receive` fed from `reader`, the bytes the state machine
// produces written to `writer`). Verification is `e.net.tls`'s: the chain is checked against `trust_roots` for
// `server_name` at `now`, and the entropy is the caller's.
//
// `Channel` owns the socket and is filled in place by `dial`; `close` sends close_notify and closes it, and may be called more than once.
//
// Memory: the TLS state and the buffers it takes are allocated from the arena, which is retained.

use e.io
use e.mem
use e.net
use e.net.tls as tls
use e.time

error NoH2

type Channel = struct { socket: net.Socket, secure: tls.Stream, open: bool }

// The client configuration the dial uses: ALPN `h2` only.
fn client_config(a: *mem.Arena, server_name: str, trust_roots: []const u8, entropy: []const u8, now: time.Timestamp) -> (tls.ClientConfig, err) {
    let (protocols, e) = mem.alloc[str](a, 1usize)
    if e != ok { ret (zero, e) }
    protocols[0] = "h2"
    ret (tls.ClientConfig { server_name: server_name, trust_roots: trust_roots, alpn: protocols[0usize..1usize], entropy: entropy, now: now }, ok)
}

// The handshake over an open socket, with ALPN `h2` checked.
fn establish(c: *Channel, a: *mem.Arena, config: tls.ClientConfig) -> err {
    let source = net.reader(&c.socket)
    let sink = net.writer(&c.socket)
    let (secure0, create_error) = tls.client(a, source, sink, config)
    if create_error != ok { ret create_error }
    c.secure = secure0
    let handshake_error = tls.handshake(&c.secure)
    if handshake_error != ok {
        let unused = tls.close(&c.secure)
        ret handshake_error
    }
    let selected = tls.negotiated_alpn(&c.secure)
    if selected.len != 2usize || selected[0] != 104u8 || selected[1] != 50u8 {
        let unused = tls.close(&c.secure)
        ret NoH2
    }
    ret ok
}

// Connect `c` to `endpoint`: TCP, then TLS 1.3 with ALPN `h2` only (`NoH2` when the server selects nothing else). `c` is
// the caller's, and the reader and writer of the stream point into it, so it must not move while it is open.
fn dial(c: *Channel, a: *mem.Arena, endpoint: net.Endpoint, server_name: str, trust_roots: []const u8, entropy: []const u8, now: time.Timestamp) -> err {
    c.open = false
    let (config, config_error) = client_config(a, server_name, trust_roots, entropy, now)
    if config_error != ok { ret config_error }
    let (opened, connect_error) = net.tcp_connect(endpoint)
    if connect_error != ok { ret connect_error }
    c.socket = opened
    let established = establish(c, a, config)
    if established != ok {
        let unused = net.close(c.socket)
        ret established
    }
    c.open = true
    ret ok
}

// The protected stream's reader, for `conn_receive`.
fn reader(c: *Channel) -> io.Reader { ret tls.reader(&c.secure) }

// The protected stream's writer, for the bytes the call state machine produces.
fn writer(c: *Channel) -> io.Writer { ret tls.writer(&c.secure) }

// close_notify, then the socket.
fn close(c: *Channel) -> err {
    if !c.open { ret ok }
    c.open = false
    let tls_error = tls.close(&c.secure)
    let net_error = net.close(c.socket)
    if tls_error != ok { ret tls_error }
    ret net_error
}
