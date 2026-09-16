// Exits 5; after `extra` is deleted the warm build fails on this line, naming `dep`
// and `extra`, exit 1, no image rewritten (D495).
use dep
use e.os

fn main() -> err {
    os.exit(dep.answer() + dep.extra())
    ret ok
}
