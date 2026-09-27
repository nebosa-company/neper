// The e.db benchmark over x.postgresql.libpq:  postgresql <conninfo> <rows> <lookups>
use e.mem
use e.db
use x.postgresql.libpq
use workload

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 4usize { ret workload.Failed }
    let (conn0, open_error) = libpq.open(a, args[1])
    if open_error != ok { ret open_error }
    var c = conn0
    ret workload.run(a, &c, "postgresql", args, true)
}
