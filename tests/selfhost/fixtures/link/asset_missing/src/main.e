// A project whose `project.yaml` declares an asset with no file: refused at the manifest,
// naming the file (T013), before anything is built.

use e.asset
use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    try io.print("unreachable\n")
    ret ok
}
