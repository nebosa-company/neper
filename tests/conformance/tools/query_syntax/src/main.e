// A dependency that does not parse (D521, H18): every query over the program is a
// stream under the query's header, the syntax diagnostic its one record, exit 1,
// where the loader had written it as text and the stream had no header.
use dep
use e.os

fn main() -> err {
    os.exit(i32(dep.f()))
    ret ok
}
