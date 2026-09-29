// `x.microsoft.tds` integrated login (`e.net.auth`): with no user name the driver logs in as the
// Windows user the program runs as -- LOGIN7 with fIntSecurity and the first SSPI token, then the
// server's SSPI tokens answered with SSPI messages -- and `SELECT SUSER_SNAME()` names that user,
// USERDOMAIN\USERNAME. The arguments are the host, the port and the server's certificate (DER),
// as for x_tds, from the ports file tests/selfhost/sqlserver.ps1 writes. Exit codes: 1 missing
// arguments, 2 unreadable certificate or port, 3 the login refused (`CannotConnect`), 4 no
// provider (`auth.NotFound`), 5 a token refused (`auth.Refused`), 6 another open failure, 7 the
// query failed, 8 the name differs, 9 close failed.
use e.os
use e.mem
use e.str
use e.fs
use e.io
use e.db
use e.net.auth
use x.microsoft.tds

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

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 4usize { os.exit(1i32) }
    let (roots, roots_error) = fs.read_file(a, args[3], 65536usize)
    if roots_error != ok { os.exit(2i32) }
    let (port, port_error) = str.parse_u64(args[2])
    if port_error != ok { os.exit(2i32) }
    let options = tds.Options { host: args[1], port: u16(port), user: "", password: "", database: "", trust_roots: roots }
    let (conn0, open_error) = tds.open(a, options)
    if open_error == tds.CannotConnect { os.exit(3i32) }
    if open_error == auth.NotFound { os.exit(4i32) }
    if open_error == auth.Refused { os.exit(5i32) }
    if open_error != ok { os.exit(6i32) }
    var c = conn0
    let (rows0, query_error) = db.query(&c, "SELECT SUSER_SNAME()", zero)
    if query_error != ok { os.exit(7i32) }
    var rows = rows0
    var row: [1]db.Value = zero
    let (more, next_error) = db.reader_next_err(&rows, row[0..])
    let close_rows_error = db.close_rows(&rows)
    if next_error != ok || !more || close_rows_error != ok { os.exit(7i32) }
    var name = ""
    switch row[0] {
    case .Text as s:
        name = s
    default:
        os.exit(7i32)
    }
    let (domain, domain_error) = os.env(a, "USERDOMAIN")
    let (user, user_error) = os.env(a, "USERNAME")
    if domain_error != ok || user_error != ok { os.exit(8i32) }
    let (expected, expected_error) = mem.alloc[u8](a, domain.len + 1usize + user.len)
    if expected_error != ok { os.exit(8i32) }
    mem.copy[u8](expected[0usize..domain.len], domain)
    expected[domain.len] = 92u8
    mem.copy[u8](expected[domain.len + 1usize..], user)
    if !same_folded(name, expected) { os.exit(8i32) }
    if db.close(&c) != ok { os.exit(9i32) }
    try io.print("x tds integrated ok\n")
    ret ok
}
