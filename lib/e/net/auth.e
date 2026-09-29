// Integrated authentication through the host's own security provider (algorithm #1403,
// Kerberos V5): a program logs in as the user it runs as, with no password, by driving SSPI on
// Windows (`auth.windows.e`, secur32.dll) and GSSAPI on Linux (`auth.linux.e`, MIT
// `libgssapi_krb5.so.2`, looked up at run time so a host without it answers `NotFound`).
// Nothing here implements Kerberos; the provider does, with the credentials the user already
// holds (the Windows logon session, a Linux credential cache from `kinit`).
//
// Both sides of a handshake are here: `client` for the initiator, naming the service it logs
// in to, and `server` for the acceptor. Each call to `step` takes the peer's last token (empty
// for the client's first call) and writes the next token to send into `out`; when it answers
// `complete` the context is established and `user_name` names the authenticated client. A
// token longer than `out` is `TooSmall`; `MAX_TOKEN` bytes always hold one. A token the
// provider rejects is `Refused`. `negotiate_header` and `parse_negotiate` carry a token in an
// HTTP `Authorization`/`WWW-Authenticate` value, `Negotiate <base64>` (RFC 4559).
//
// This file is the module for a target with no provider: every context answers `NotFound`.
// The Windows and Linux variants are the whole module on their hosts.
use e.mem
use e.bytes

type Mechanism = enum u8 { Negotiate, Kerberos, Ntlm }
type Context = struct { mechanism: Mechanism, complete: bool }

error NotFound
error Refused
error TooSmall
error Failed
error Invalid

const MAX_TOKEN: usize = 65536usize

// The initiator's context for `service_principal`, such as `HTTP/host@REALM` or
// `MSSQLSvc/host:1433`.
fn client(a: *mem.Arena, mechanism: Mechanism, service_principal: str) -> (*Context, err) { ret (nil, NotFound) }

// The acceptor's context, with the host's own service credentials.
fn server(a: *mem.Arena, mechanism: Mechanism) -> (*Context, err) { ret (nil, NotFound) }

// Consumes the peer's token and writes the next one into `out`: the bytes written, and whether
// the context is now established. A written token must still be sent when `complete` is true.
fn step(c: *Context, input: []const u8, out: []u8) -> (usize, bool, err) { ret (0usize, false, NotFound) }

// The authenticated client, `DOMAIN\user` or `user@REALM`, as UTF-8 in `dst`.
fn user_name(c: *Context, dst: []u8) -> (str, err) { ret ("", NotFound) }

// The other side: the client for a server, the service for a client.
fn peer_name(c: *Context, dst: []u8) -> (str, err) { ret ("", NotFound) }

fn close(c: *Context) -> err { ret NotFound }

// `Negotiate <base64 of token>`, the value of an HTTP authentication header; a bare
// `Negotiate` for an empty token.
fn negotiate_header(dst: []u8, token: []const u8) -> (str, err) {
    let scheme = "Negotiate"
    if dst.len < scheme.len + 1usize { ret ("", TooSmall) }
    mem.copy[u8](dst[0usize..scheme.len], scheme)
    if token.len == 0usize { ret (dst[0usize..scheme.len], ok) }
    dst[scheme.len] = 32u8
    let (encoded, encode_error) = bytes.base64_encode(dst[scheme.len + 1usize..], token, .Standard, true)
    if encode_error != ok { ret ("", TooSmall) }
    ret (dst[0usize..scheme.len + 1usize + encoded.len], ok)
}

// The token in a `Negotiate` header value, decoded into `dst`; empty for a bare `Negotiate`.
// The scheme's case does not matter. Another scheme, or a token that is not base64, is
// `Invalid`.
fn parse_negotiate(dst: []u8, value: str) -> ([]u8, err) {
    let scheme = "negotiate"
    var start = 0usize
    var stop = value.len
    while start < stop && value[start] == 32u8 { start += 1usize }
    while stop > start && value[stop - 1usize] == 32u8 { stop -= 1usize }
    if stop - start < scheme.len { ret (zero, Invalid) }
    var i = 0usize
    while i < scheme.len {
        if (value[start + i] | 32u8) != scheme[i] { ret (zero, Invalid) }
        i += 1usize
    }
    var at = start + scheme.len
    if at == stop { ret (dst[0usize..0usize], ok) }
    if value[at] != 32u8 { ret (zero, Invalid) }
    while value[at] == 32u8 { at += 1usize }
    let (token, decode_error) = bytes.base64_decode(dst, value[at..stop], .Standard)
    if decode_error == bytes.TooLarge { ret (zero, TooSmall) }
    if decode_error != ok { ret (zero, Invalid) }
    ret (token, ok)
}
