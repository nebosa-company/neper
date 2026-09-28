// The e.db benchmark over x.microsoft.tds:  sqlserver <server> <rows> <lookups>
// where <server> is `host;port;certificate.der;certificate.pem;user;password` (run.py builds it
// from the ports file tests/selfhost/sqlserver.* writes), database neper, TDS 8.0 strict.
use e.mem
use e.str
use e.fs
use e.db
use x.microsoft.tds
use workload

// The `index`th `;`-separated field of `s`.
fn field(s: str, index: usize) -> str {
    var start = 0usize
    var seen = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 59u8 {
            if seen == index { ret s[start..i] }
            seen += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 4usize { ret workload.Failed }
    let server = args[1]
    let (port, port_error) = str.parse_u64(field(server, 1usize))
    if port_error != ok || port > 65535u64 { ret workload.Failed }
    let (roots, roots_error) = fs.read_file(a, field(server, 2usize), 65536usize)
    if roots_error != ok { ret roots_error }
    let options = tds.Options { host: field(server, 0usize), port: u16(port), user: field(server, 4usize), password: field(server, 5usize), database: "neper", trust_roots: roots }
    let (conn0, open_error) = tds.open(a, options)
    if open_error != ok { ret open_error }
    var c = conn0
    ret workload.run(a, &c, "sqlserver", args, false)
}
