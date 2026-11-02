// e.math is Neper code, not libm: the same answers on every target.

use e.io
use e.math
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["floor(2.7) = {}\n"](math.floor[f64](2.7))
    try io.printf["sin(1) = {}\n"](math.sin[f64](1.0))
    try io.printf["pow(2, 0.5) = {}\n"](math.pow64(2.0, 0.5))
    ret ok
}
