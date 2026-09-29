use e.io
use e.mem
use e.fs
use e.db
use x.microsoft.tds

// Windows authentication to SQL Server: no user name and no password in the program.
// The driver logs in as whoever runs it. Arguments: the server's certificate (DER).
fn main(a: *mem.Arena, args: []str) -> err {
    let roots = try fs.read_file(a, args[1], 65536usize)
    let options = tds.Options { host: "localhost", port: 14330u16, user: "", password: "", database: "", trust_roots: roots }
    var c = try tds.open(a, options)
    var rows = try db.query(&c, "SELECT SUSER_SNAME()", zero)
    var row: [1]db.Value = zero
    let more = try db.reader_next_err(&rows, row[..])
    if more {
        switch row[0] {
        case .Text as name:
            try io.printf["logged in as {}\n"](name)
        default:
            try io.printf["unexpected column type\n"]()
        }
    }
    try db.close_rows(&rows)
    try db.close(&c)
    ret ok
}
