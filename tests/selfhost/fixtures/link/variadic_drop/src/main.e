// A warm build after an extern loses its `...` refuses the caller that passes more
// arguments than it declares, as a clean build does: `call` passes two to `plat.ident`.
use call

error CallFailed

fn main() -> err {
    if !call.run() { ret CallFailed }
    ret ok
}
