// `e.test`'s four assertions. Each is checked in both directions -- the case that passes and
// the case that fails -- because an assertion that always passes is the one kind of test
// helper that is worse than none. `eq` is checked across the kinds section 9 rule 4 supplies
// equality for, since that is the whole of what makes it generic.

use e.mem
use e.os
use e.test

// A struct has no supplied `eq` (rule 4): it says what equal means, or it cannot be compared.
type Point = struct { x: i64, y: i64 }
type Level = enum u8 { Low, High }

fn point_eq(a: Point, b: Point) -> bool {
    ret a.x == b.x && a.y == b.y
}

fn main(a: *mem.Arena) -> err {
    // --- assert and fail.
    if test.assert(true, "holds") != ok { os.exit(10i32) }
    if test.assert(false, "does not") != test.Failed { os.exit(11i32) }
    if test.fail("always") != test.Failed { os.exit(12i32) }

    // --- eq, over every kind the language compares.
    if test.eq[i64](7i64, 7i64, "integers") != ok { os.exit(20i32) }
    if test.eq[i64](7i64, 8i64, "integers") != test.Failed { os.exit(21i32) }
    if test.eq[bool](true, true, "bools") != ok { os.exit(22i32) }
    if test.eq[bool](true, false, "bools") != test.Failed { os.exit(23i32) }
    if test.eq[str]("same", "same", "strings") != ok { os.exit(24i32) }
    if test.eq[str]("same", "other", "strings") != test.Failed { os.exit(25i32) }
    if test.eq[str]("same", "sam", "strings of different length") != test.Failed { os.exit(26i32) }
    if test.eq[f64](1.5f64, 1.5f64, "floats") != ok { os.exit(27i32) }
    if test.eq[f64](1.5f64, 1.25f64, "floats") != test.Failed { os.exit(28i32) }
    // Rule 4's float equality is the container rule rather than IEEE's: every NaN equals every
    // other, and the two zeros are one. `near` below is where IEEE's answer shows.
    let quiet = 0.0f64 / 0.0f64
    if test.eq[f64](quiet, quiet, "nan equals nan") != ok { os.exit(50i32) }
    if test.eq[f64](quiet, 1.0f64, "nan against a number") != test.Failed { os.exit(51i32) }
    if test.eq[f64](0.0f64, -0.0f64, "the two zeros") != ok { os.exit(52i32) }
    var p = Point { x: 1i64, y: 2i64 }
    var q = Point { x: 1i64, y: 2i64 }
    var r = Point { x: 1i64, y: 3i64 }
    if test.eq[Point](p, q, "structs") != ok { os.exit(29i32) }
    if test.eq[Point](p, r, "structs") != test.Failed { os.exit(30i32) }
    var low: Level = .Low
    var high: Level = .High
    if test.eq[Level](low, low, "enums") != ok { os.exit(31i32) }
    if test.eq[Level](low, high, "enums") != test.Failed { os.exit(32i32) }
    if test.eq[err](ok, ok, "errors") != ok { os.exit(33i32) }
    if test.eq[err](ok, test.Failed, "errors") != test.Failed { os.exit(34i32) }

    // --- near: by absolute tolerance, by relative tolerance, and by neither.
    if test.near(1.0f64, 1.05f64, 0.1f64, 0.0f64, "within abs") != ok { os.exit(40i32) }
    if test.near(1.0f64, 1.2f64, 0.1f64, 0.0f64, "outside abs") != test.Failed { os.exit(41i32) }
    if test.near(1000.0f64, 1001.0f64, 0.0f64, 0.01f64, "within rel") != ok { os.exit(42i32) }
    if test.near(1000.0f64, 1100.0f64, 0.0f64, 0.01f64, "outside rel") != test.Failed { os.exit(43i32) }
    // The relative tolerance is against the larger magnitude, so the order of the two does
    // not change the answer.
    if test.near(1001.0f64, 1000.0f64, 0.0f64, 0.01f64, "within rel, reversed") != ok { os.exit(44i32) }
    // Exactly equal is near under any tolerance, including none.
    if test.near(2.0f64, 2.0f64, 0.0f64, 0.0f64, "equal") != ok { os.exit(45i32) }
    // Negative values: the gap is a magnitude.
    if test.near(-1.0f64, -1.05f64, 0.1f64, 0.0f64, "negative within abs") != ok { os.exit(46i32) }
    // A NaN is near nothing, itself included.
    let nan = 0.0f64 / 0.0f64
    if test.near(nan, nan, 1.0f64, 1.0f64, "nan") != test.Failed { os.exit(47i32) }
    if test.near(nan, 1.0f64, 1.0f64, 1.0f64, "nan against a number") != test.Failed { os.exit(48i32) }
    ret ok
}
