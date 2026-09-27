// D1607: arguments move straight from the registers their values live in to the registers
// the convention names, and a value live across a call prefers a register the call keeps.
// The cases a wrong move order would get wrong: arguments passed in an order that makes one
// argument's value sit where another is going (swaps and rotations of rcx, rdx, r8, r9 on
// Windows and rdx, rcx, r8, r9 on System V), a value passed twice, integers and floats
// interleaved, arguments past the registers, an indirect call, and more values live across
// a call than there are registers a call keeps. Every value derives from the argument count,
// so none of it folds. Each check exits with its own code.

use e.io
use e.mem
use e.os

fn digits4(a: i64, b: i64, c: i64, d: i64) -> i64 { ret a * 1000i64 + b * 100i64 + c * 10i64 + d }

fn digits7(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64) -> i64 {
    ret a * 1000000i64 + b * 100000i64 + c * 10000i64 + d * 1000i64 + e * 100i64 + f * 10i64 + g
}

fn mixed(x: f64, n: i64, y: f64, m: i64, z: f64) -> f64 { ret x * 10000.0f64 + f64(n) * 1000.0f64 + y * 100.0f64 + f64(m) * 10.0f64 + z }

fn twice(n: i64) -> i64 { ret n * 2i64 }

// `os.args` with every register a call keeps holding a value across it. The runtime once read
// its copy of the command line from two of them (r12 and r15 on Windows, r13 on Linux), so a
// function that allocated those read its own values back as the argument table (D1607). The
// runner passes no arguments, so the table is the image's path alone.
fn args_under_pressure(a: *mem.Arena, s: i64) -> i64 {
    let b1 = twice(s)
    let b2 = twice(s + 1i64)
    let b3 = twice(s + 2i64)
    let b4 = twice(s + 3i64)
    let b5 = twice(s + 4i64)
    let b6 = twice(s + 5i64)
    let (arguments, arguments_error) = os.args(a)
    if arguments_error != ok || arguments.len != 1usize || arguments[0usize].len == 0usize { ret -1i64 }
    ret b1 + b2 + b3 + b4 + b5 + b6
}

fn main(a: *mem.Arena, args: []str) -> err {
    let s = i64(args.len)
    let one = s
    let two = s + 1i64
    let three = s + 2i64
    let four = s + 3i64
    // In order, swapped in pairs, rotated each way, reversed, and one value twice.
    if digits4(one, two, three, four) != 1234i64 { os.exit(1i32) }
    if digits4(two, one, four, three) != 2143i64 { os.exit(2i32) }
    if digits4(two, three, four, one) != 2341i64 { os.exit(3i32) }
    if digits4(four, one, two, three) != 4123i64 { os.exit(4i32) }
    if digits4(four, three, two, one) != 4321i64 { os.exit(5i32) }
    if digits4(three, three, one, one) != 3311i64 { os.exit(6i32) }
    // Seven: past Win64's four registers and System V's six, rotated.
    let five = s + 4i64
    let six = s + 5i64
    let seven = s + 6i64
    if digits7(seven, one, two, three, four, five, six) != 7123456i64 { os.exit(7i32) }
    if digits7(two, one, four, three, six, five, seven) != 2143657i64 { os.exit(8i32) }
    // Integers and floats interleaved, the floats from the same values.
    let x = f64(one)
    let y = f64(two)
    let z = f64(three)
    if mixed(z, four, y, one, x) != 34211.0f64 { os.exit(9i32) }
    if mixed(x, two, z, three, y) != 12332.0f64 { os.exit(10i32) }
    // Indirect, with the arguments reversed.
    var through: fn(a: i64, b: i64, c: i64, d: i64) -> i64 = digits4
    if args.len > 100usize { through = digits4 }
    if through(four, three, two, one) != 4321i64 { os.exit(11i32) }
    // Eight values live across calls -- more than the five registers a call keeps -- each
    // checked after them, in a loop so the back edge keeps them live through every call.
    var round = 0i64
    var total = 0i64
    while round < 3i64 {
        let a1 = twice(one + round)
        let a2 = twice(two + round)
        let a3 = twice(three + round)
        let a4 = twice(four + round)
        let a5 = twice(five + round)
        let a6 = twice(six + round)
        let a7 = twice(seven + round)
        let a8 = twice(s + 7i64 + round)
        total += digits4(a1, a2, a3, a4) + digits4(a5, a6, a7, a8)
        if a1 != 2i64 * (1i64 + round) || a8 != 2i64 * (8i64 + round) { os.exit(12i32) }
        round += 1i64
    }
    // Computed by Python from the same definition: a_k = 2 * (k + r), r = 0, 1, 2.
    if total != 54804i64 { os.exit(13i32) }
    // 2 * (1 + 2 + 3 + 4 + 5 + 6).
    if args_under_pressure(a, s) != 42i64 { os.exit(14i32) }
    try io.print("call moves ok\n")
    ret ok
}
