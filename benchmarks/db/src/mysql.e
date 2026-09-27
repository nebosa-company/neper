// The e.db benchmark over x.oracle.mysql:  mysql <port> <rows> <lookups>
// (127.0.0.1, user root with no password, database neper -- the suites' throwaway server)
use e.mem
use e.str
use e.db
use x.oracle.mysql
use workload

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 4usize { ret workload.Failed }
    let (port, port_error) = str.parse_u64(args[1])
    if port_error != ok || port > 65535u64 { ret workload.Failed }
    let options = mysql.Options { host: "127.0.0.1", port: u16(port), user: "root", password: "", database: "neper" }
    let (conn0, open_error) = mysql.open(a, options)
    if open_error != ok { ret open_error }
    var c = conn0
    ret workload.run(a, &c, "mysql", args, false)
}
