use e.io
use e.mem
use e.net.auth

// The first leg of HTTP Negotiate: the header an intranet request carries so the
// server knows who is asking, with no password in the program.
fn main(a: *mem.Arena, args: []str) -> err {
    let (ctx, open_error) = auth.client(a, .Negotiate, "HTTP/intranet.example.com")
    if open_error == auth.NotFound {
        try io.printf["no security provider on this host\n"]()
        ret ok
    }
    if open_error != ok { ret open_error }
    let token = try mem.alloc[u8](a, auth.MAX_TOKEN)
    let (n, complete, step_error) = auth.step(ctx, "", token)
    if step_error == auth.Failed {
        // Linux: no Kerberos ticket for this user yet (kinit gets one).
        try io.printf["no credentials to offer\n"]()
        ret ok
    }
    if step_error != ok { ret step_error }
    let header = try mem.alloc[u8](a, 16usize + n * 2usize)
    let value = try auth.negotiate_header(header, token[..n])
    let start: str = value[..32usize]
    try io.printf["Authorization: {}...\n"](start)
    try io.printf["{} token bytes, complete after one leg: {}\n"](n, complete)
    // Each "WWW-Authenticate: Negotiate <token>" the server answers goes back through
    // auth.parse_negotiate and auth.step until step reports the context complete.
    try auth.close(ctx)
    ret ok
}
