// Structs, slices and strings in the comptime interpreter (D1569, C066): each
// constant below is settled at compile time by a function that builds, copies,
// nests and returns structs, hands slices of an array to another function, and
// reads a string field. The program only compares the folded answers.
error Wrong

type Point = struct { x: i32, y: i32 }
type Box = struct { low: Point, high: Point, name: str }

fn make(x: i32, y: i32) -> Point {
    ret Point { x: x, y: y }
}

fn area(b: Box) -> i32 {
    ret (b.high.x - b.low.x) * (b.high.y - b.low.y)
}

fn box_area() -> i32 {
    let b = Box { low: make(1i32, 1i32), high: make(4i32, 6i32), name: "unit" }
    ret area(b)
}

fn sum(values: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at < values.len {
        total += values[at]
        at += 1usize
    }
    ret total
}

fn table_sum() -> u32 {
    var t: [6]u32 = zero
    for i in 0usize..6usize {
        t[i] = u32(i) * 3u32
    }
    let middle = t[1usize..5usize]
    ret sum(middle) + sum(t[..])
}

fn name_length() -> usize {
    let b = Box { low: make(0i32, 0i32), high: make(4i32, 5i32), name: "window" }
    ret b.name.len + usize(b.name[0usize])
}

fn moved() -> i32 {
    var p = make(1i32, 2i32)
    p.x = 10i32
    var q = p
    q.y += 5i32
    var points: [2]Point = zero
    points[1usize] = q
    ret points[1usize].x + points[1usize].y + p.y + points[0usize].x
}

const AREA = box_area()
const TABLE = table_sum()
const NAME = name_length()
const MOVED = moved()

fn main() -> err {
    if AREA != 15i32 { ret Wrong }
    if TABLE != 75u32 { ret Wrong }
    if NAME != 125usize { ret Wrong }
    if MOVED != 19i32 { ret Wrong }
    // A length is settled before the program runs: the fold is not a run-time call.
    var sized: [NAME]u8 = zero
    if sized.len != 125usize { ret Wrong }
    ret ok
}
