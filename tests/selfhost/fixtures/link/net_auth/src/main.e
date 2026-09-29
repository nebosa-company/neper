// `e.net.auth`: integrated authentication through the host's own provider. Everywhere: the
// `Negotiate <base64>` header value round-trips (the expected text from Python's base64), a bare
// `Negotiate` is an empty token, another scheme and a token that is not base64 are `Invalid`,
// and a short buffer is `TooSmall`. Windows (SSPI): an in-process client/server handshake with
// the current user's logon credentials, for Negotiate and for NTLM, completes on both sides, and
// both sides name USERDOMAIN\USERNAME (as `whoami` does, even for an account linked to a
// Microsoft account); a garbled first token, an NTLM CHALLENGE with its signature altered and a
// NEGOTIATE sent where the AUTHENTICATE is due are `Refused`; an output buffer too small for a
// token is `TooSmall`. (In-process NTLM is a "local call" whose AUTHENTICATE carries no
// response, so altering or replaying one proves nothing and is not checked.) Linux (GSSAPI):
// with no libgssapi_krb5.so.2 every context is `NotFound`; with it, NTLM without gss-ntlmssp is
// `NotFound`, and with no KDC a client with no credential cache fails its first step and a
// server with no keytab is `Failed`. When NEPER_KRB5_SERVICE names a principal in the keytab
// (`tests/selfhost/kerberos.sh run <fixture>` sets up a KDC, the keytab and the credential cache)
// a garbled token is `Refused` and the same loopback runs over Kerberos and over Negotiate, both
// sides naming NEPER_KRB5_USER, and the fixture also prints `net auth kerberos ok`. Each check
// exits with its own code.
use e.mem
use e.os
use e.io
use e.net.auth

fn same_folded(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        var p = x[i]
        var q = y[i]
        if p >= 65u8 && p <= 90u8 { p = p + 32u8 }
        if q >= 65u8 && q <= 90u8 { q = q + 32u8 }
        if p != q { ret false }
        i += 1usize
    }
    ret true
}

fn same_bytes(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn headers() -> i32 {
    var text: [64]u8 = zero
    var back: [32]u8 = zero
    let token: [14]u8 = [14]u8{ 78, 84, 76, 77, 83, 83, 80, 0, 1, 0, 0, 0, 251, 255 }
    let (value, value_error) = auth.negotiate_header(text[0..], token[0..])
    if value_error != ok || !same_bytes(value, "Negotiate TlRMTVNTUAABAAAA+/8=") { ret 1i32 }
    let (decoded, decoded_error) = auth.parse_negotiate(back[0..], "  nEgOtIaTe   TlRMTVNTUAABAAAA+/8= ")
    if decoded_error != ok || !same_bytes(decoded, token[0..]) { ret 2i32 }
    let (bare, bare_error) = auth.parse_negotiate(back[0..], "Negotiate")
    if bare_error != ok || bare.len != 0usize { ret 3i32 }
    let (empty_header, empty_error) = auth.negotiate_header(text[0..], back[0..0])
    if empty_error != ok || !same_bytes(empty_header, "Negotiate") { ret 3i32 }
    let (basic, basic_error) = auth.parse_negotiate(back[0..], "Basic dXNlcjpwYXNz")
    if basic_error != auth.Invalid { ret 4i32 }
    let (joined, joined_error) = auth.parse_negotiate(back[0..], "NegotiateTlRM")
    if joined_error != auth.Invalid { ret 4i32 }
    let (garbage, garbage_error) = auth.parse_negotiate(back[0..], "Negotiate Tl*MTVNT")
    if garbage_error != auth.Invalid { ret 5i32 }
    let (short, short_error) = auth.negotiate_header(text[0..20], token[0..])
    if short_error != auth.TooSmall { ret 6i32 }
    let (cramped, cramped_error) = auth.parse_negotiate(back[0..4], "Negotiate TlRMTVNTUAABAAAA+/8=")
    if cramped_error != auth.TooSmall { ret 6i32 }
    ret 0i32
}

// A client and a server driven to completion over two token buffers; both must name
// `expected`. Answers 0 or `base` plus the failing check.
fn loopback(a: *mem.Arena, mechanism: auth.Mechanism, spn: str, expected: str, base: i32) -> i32 {
    let (cl, client_error) = auth.client(a, mechanism, spn)
    if client_error != ok { ret base }
    let (sv, server_error) = auth.server(a, mechanism)
    if server_error != ok { ret base + 1i32 }
    let (to_server, to_server_error) = mem.alloc[u8](a, auth.MAX_TOKEN)
    let (to_client, to_client_error) = mem.alloc[u8](a, auth.MAX_TOKEN)
    if to_server_error != ok || to_client_error != ok { ret base + 1i32 }
    var back = 0usize
    var client_done = false
    var server_done = false
    var rounds = 0usize
    while rounds < 8usize && !(client_done && server_done) {
        var sent = 0usize
        if !client_done {
            let (written, done, step_error) = auth.step(cl, to_client[0usize..back], to_server)
            if step_error != ok { ret base + 2i32 }
            client_done = done
            sent = written
        }
        back = 0usize
        if sent != 0usize {
            if server_done { ret base + 3i32 }
            let (answered, accepted, accept_error) = auth.step(sv, to_server[0usize..sent], to_client)
            if accept_error != ok { ret base + 3i32 }
            server_done = accepted
            back = answered
        }
        rounds += 1usize
    }
    if !client_done || !server_done { ret base + 4i32 }
    var names: [512]u8 = zero
    let (server_user, server_user_error) = auth.user_name(sv, names[0usize..128usize])
    let (client_user, client_user_error) = auth.user_name(cl, names[128usize..256usize])
    let (server_peer, server_peer_error) = auth.peer_name(sv, names[256usize..384usize])
    let (client_peer, client_peer_error) = auth.peer_name(cl, names[384usize..512usize])
    if server_user_error != ok || client_user_error != ok || server_peer_error != ok || client_peer_error != ok { ret base + 5i32 }
    if !same_folded(server_user, expected) || !same_folded(client_user, expected) || !same_folded(server_peer, expected) || client_peer.len == 0usize { ret base + 5i32 }
    let (after, after_done, after_error) = auth.step(cl, to_client[0usize..0usize], to_server)
    if after_error == ok { ret base + 6i32 }
    if auth.close(cl) != ok || auth.close(sv) != ok { ret base + 7i32 }
    ret 0i32
}

// A server handed bytes that are no token of its mechanism.
fn garbled(a: *mem.Arena, mechanism: auth.Mechanism, base: i32) -> i32 {
    let (sv, server_error) = auth.server(a, mechanism)
    if server_error != ok { ret base }
    var out: [4096]u8 = zero
    let junk: [24]u8 = [24]u8{ 96, 22, 6, 6, 43, 6, 1, 5, 5, 2, 160, 12, 48, 10, 160, 8, 7, 99, 1, 2, 3, 4, 5, 6 }
    let (written, done, step_error) = auth.step(sv, junk[0..], out[0..])
    if step_error != auth.Refused { ret base + 1i32 }
    let closed = auth.close(sv)
    ret 0i32
}

// NTLM with the AUTHENTICATE message's NT proof altered: the server must refuse it. A client
// whose output buffer cannot hold its first token is `TooSmall`.
fn tampered(a: *mem.Arena, spn: str) -> i32 {
    let (cl, client_error) = auth.client(a, .Ntlm, spn)
    let (sv, server_error) = auth.server(a, .Ntlm)
    if client_error != ok || server_error != ok { ret 40i32 }
    let (to_server, to_server_error) = mem.alloc[u8](a, auth.MAX_TOKEN)
    let (to_client, to_client_error) = mem.alloc[u8](a, auth.MAX_TOKEN)
    if to_server_error != ok || to_client_error != ok { ret 40i32 }
    let (negotiate, negotiate_done, negotiate_error) = auth.step(cl, to_client[0usize..0usize], to_server)
    if negotiate_error != ok || negotiate_done { ret 41i32 }
    let (challenge, challenge_done, challenge_error) = auth.step(sv, to_server[0usize..negotiate], to_client)
    if challenge_error != ok || challenge_done { ret 41i32 }
    // The client, handed the CHALLENGE with its signature altered, refuses it; the server,
    // handed the NEGOTIATE again where the AUTHENTICATE is due, refuses that.
    to_client[0usize] = to_client[0usize] ^ 1u8
    var answer: [4096]u8 = zero
    let (altered, altered_done, altered_error) = auth.step(cl, to_client[0usize..challenge], answer[0..])
    if altered_error != auth.Refused { ret 42i32 }
    let (repeated, repeated_done, repeated_error) = auth.step(sv, to_server[0usize..negotiate], answer[0..])
    if repeated_error != auth.Refused { ret 43i32 }
    let closed_client = auth.close(cl)
    let closed_server = auth.close(sv)
    let (small, small_error) = auth.client(a, .Ntlm, spn)
    if small_error != ok { ret 44i32 }
    var cramped: [4]u8 = zero
    let (none, none_done, none_error) = auth.step(small, to_client[0usize..0usize], cramped[0..])
    if none_error != auth.TooSmall { ret 44i32 }
    let closed_small = auth.close(small)
    ret 0i32
}

fn windows(a: *mem.Arena) -> i32 {
    let (domain, domain_error) = os.env(a, "USERDOMAIN")
    let (user, user_error) = os.env(a, "USERNAME")
    if domain_error != ok || user_error != ok { ret 10i32 }
    let (joined, joined_error) = mem.alloc[u8](a, domain.len + 1usize + user.len)
    if joined_error != ok { ret 10i32 }
    mem.copy[u8](joined[0usize..domain.len], domain)
    joined[domain.len] = 92u8
    mem.copy[u8](joined[domain.len + 1usize..], user)
    var code = loopback(a, .Negotiate, "HTTP/localhost", joined, 20i32)
    if code == 0i32 { code = loopback(a, .Ntlm, "HTTP/localhost", joined, 30i32) }
    if code == 0i32 { code = tampered(a, "HTTP/localhost") }
    if code == 0i32 { code = garbled(a, .Negotiate, 50i32) }
    if code == 0i32 { code = garbled(a, .Ntlm, 52i32) }
    ret code
}

fn linux(a: *mem.Arena) -> i32 {
    let (probe, probe_error) = auth.client(a, .Kerberos, "HTTP/localhost@NEPER.TEST")
    if probe_error == auth.NotFound {
        let (sv, server_error) = auth.server(a, .Negotiate)
        if server_error != auth.NotFound { ret 60i32 }
        let (none, none_error) = auth.client(a, .Negotiate, "HTTP/localhost")
        if none_error != auth.NotFound { ret 60i32 }
        ret 0i32
    }
    if probe_error != ok || auth.close(probe) != ok { ret 61i32 }
    let (ntlm, ntlm_error) = auth.client(a, .Ntlm, "HTTP/localhost")
    if ntlm_error != ok { ret 62i32 }
    var out: [4096]u8 = zero
    let (written, done, ntlm_step_error) = auth.step(ntlm, out[0..0], out[0..])
    if ntlm_step_error != auth.NotFound { ret 62i32 }
    let closed_ntlm = auth.close(ntlm)
    let (service, service_error) = os.env(a, "NEPER_KRB5_SERVICE")
    if service_error != ok || service.len == 0usize {
        // No KDC: a client with no credential cache cannot begin, and a server with no keytab
        // cannot be made.
        let (bare, bare_error) = auth.client(a, .Kerberos, "HTTP/localhost@NEPER.TEST")
        if bare_error != ok { ret 63i32 }
        let (none, none_done, none_error) = auth.step(bare, out[0..0], out[0..])
        if none_error != auth.Failed { ret 64i32 }
        let closed_bare = auth.close(bare)
        let (keyless, keyless_error) = auth.server(a, .Kerberos)
        if keyless_error != auth.Failed { ret 64i32 }
        ret 0i32
    }
    let (user, user_error) = os.env(a, "NEPER_KRB5_USER")
    if user_error != ok { ret 65i32 }
    var code = garbled(a, .Kerberos, 66i32)
    if code == 0i32 { code = garbled(a, .Negotiate, 68i32) }
    if code == 0i32 { code = loopback(a, .Kerberos, service, user, 70i32) }
    if code == 0i32 { code = loopback(a, .Negotiate, service, user, 80i32) }
    if code == 0i32 {
        let kerberos_printed = io.print("net auth kerberos ok\n")
    }
    ret code
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = headers()
    if code == 0i32 {
        if os.NATIVE_SEPARATOR == 92u8 { code = windows(a) } else { code = linux(a) }
    }
    if code != 0i32 { os.exit(code) }
    try io.print("net auth ok\n")
    ret ok
}
