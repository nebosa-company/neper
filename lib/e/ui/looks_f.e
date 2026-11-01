// Round 62, lane f: runs one sheet under all ten looks, so a control that only needs a sheet and a status row has one app.
use e.mem
use e.ui.looks

// Neper, Windows, Windows dark, Neper dark (run_all), then Cupertino, Material and Linux, each Light and Dark, at 100 % and 150 %.
fn run_ten(a: *mem.Arena, s: *const looks.Sheet) -> err {
    try looks.run_all(a, s)
    try looks.run_cupertino(a, s)
    try looks.run_material(a, s)
    ret looks.run_linux(a, s)
}
