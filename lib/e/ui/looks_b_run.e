// Round 62 lane b (the runner; the drawing is looks_b.e): runs one sheet under all ten looks (Neper, Neper dark, Windows, Windows dark, Linux and dark,
// Cupertino and dark, Material and dark), so a sheet app is one `build` and one call.

use e.mem
use e.ui.looks

fn run_ten(a: *mem.Arena, s: *const looks.Sheet) -> err {
    try looks.run_all(a, s)
    try looks.run_linux(a, s)
    try looks.run_cupertino(a, s)
    ret looks.run_material(a, s)
}
