// Exits 7, the `b` of the record, before and after `edits/dep_layout.e` reorders
// the fields -- a kept `main` would read the old offset and exit 1 (D493).
use dep
use e.os

fn main() -> err {
    let r = dep.make()
    os.exit(r.b)
    ret ok
}
