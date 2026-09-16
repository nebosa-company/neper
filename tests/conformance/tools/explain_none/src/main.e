use e.mem
use shapes
use helper

// Dispatches that find nothing (D430, H06): a struct, which no rule supplies, and
// whose `cmp` is declared in `helper` where rule 4 does not look; a tagged union
// with an arm the rule refuses; a float, which `cmp` does not cover.
fn least[T: type](a: T, b: T) -> T {
    if T.cmp(a, b) < 0i32 { ret a }
    ret b
}

fn main(a: *mem.Arena, args: []str) -> err {
    let p = least[shapes.Point](shapes.Point { x: 1i64, y: 2i64 }, shapes.Point { x: 3i64, y: 4i64 })
    let s = least[shapes.Shape](shapes.Shape{ Empty }, shapes.Shape{ Empty })
    let f = least[f64](1.0f64, 2.0f64)
    let d = helper.point_cmp(p, p)
    ret ok
}
