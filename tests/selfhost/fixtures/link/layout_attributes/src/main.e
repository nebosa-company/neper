// A warm build after a record's layout attribute changes rebuilds the module compiled
// against the old layout (D1677): `p` reads `dep.P` and `q` reads `dep.Q`, and each
// edit changes one attribute of one record, so the other module's edge holds.
use p
use q
use e.os

fn main() -> err {
    os.exit(p.read() + q.read())
    ret ok
}
