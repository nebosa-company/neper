// Passes `plat.ident` one argument past the one it declares, which only a C variadic takes.
use plat

fn run() -> bool {
    ret plat.ident(1i32, 2i32) != 0u32
}
