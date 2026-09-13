// Section 11's `null` row: a dereference of `nil` traps. `field` reads a field through
// a nil pointer, `write` writes one, `deref` reads `*p` and `store` writes it, each
// with a record naming the pointer's type; anything else does the same through live
// pointers and exits 0. The nil pointers are conditionally reassigned on the argument
// count so nothing folds.
use e.mem
use e.str

type Point = struct { x: i32, y: i32 }

fn read_x(p: *Point) -> i32 { ret p.x }
fn write_y(p: *Point, v: i32) { p.y = v }
fn load(p: *i32) -> i32 { ret *p }

fn main(a: *mem.Arena, args: []str) -> err {
    let mode = args[args.len - 1usize]
    var point = Point { x: 1i32, y: 2i32 }
    var live: *Point = &point
    var gone: *Point = nil
    var cell = 5i32
    var live_cell: *i32 = &cell
    var gone_cell: *i32 = nil
    if args.len > 100usize { gone = &point }
    if str.eq(mode, "field") {
        if read_x(gone) == 3i32 { ret ok }
    }
    if str.eq(mode, "write") {
        write_y(gone, 9i32)
    }
    if str.eq(mode, "deref") {
        if load(gone_cell) == 3i32 { ret ok }
    }
    if str.eq(mode, "store") {
        *gone_cell = 4i32
    }
    write_y(live, 7i32)
    *live_cell = 6i32
    if read_x(live) + load(live_cell) + point.y != 14i32 { ret ok }
    ret ok
}
