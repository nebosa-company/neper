// Calls `plat.ident` by name: this module's artifact names the library and the symbol.
use plat

fn run() -> bool {
    ret plat.ident() != 0u32
}
