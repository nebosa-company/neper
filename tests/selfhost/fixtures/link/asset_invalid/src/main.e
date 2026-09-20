// `e.asset` in a project with no `project.yaml`: the empty registry, every lookup
// answering false and `attribute` scanning whatever slice it is handed.

use e.asset
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    if asset.count() != 0usize { os.exit(1i32) }
    let (_, found) = asset.at(0usize)
    if found { os.exit(2i32) }
    let (_, named) = asset.get("anything")
    if named { os.exit(3i32) }
    var pairs: [2]asset.Attribute = [2]asset.Attribute{ asset.Attribute { name: "theme", value: "dark" }, asset.Attribute { name: "scale", value: "2" } }
    let value = asset.Asset { name: "x", media_type: "text/plain", bytes: "x", sha256: zero, attributes: pairs[0..] }
    let (scale, has_scale) = asset.attribute(value, "scale")
    if !has_scale || scale.len != 1usize || scale[0] != 50u8 { os.exit(4i32) }
    let (_, has_locale) = asset.attribute(value, "locale")
    if has_locale { os.exit(5i32) }
    try io.print("asset empty ok\n")
    ret ok
}
