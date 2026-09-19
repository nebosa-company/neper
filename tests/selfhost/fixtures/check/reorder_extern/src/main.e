// `@reorder` picks neper's layout over C's (D239), so a value of one cannot cross an
// FFI boundary: the callee reads the fields where its own declaration puts them. The
// crossing is refused here rather than passed silently.
@reorder
type Point = struct {
    tag: u8,
    x: f64,
}

@import("plotting", "plot")
extern fn plot(point: *Point) -> i32

fn main() -> i64 {
    var point = Point{ tag: 1u8, x: 2.0 }
    let plotted = plot(&point)
    ret i64(plotted)
}
