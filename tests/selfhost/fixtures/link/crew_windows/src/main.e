// A crew of two or more workers shares the program's parameter and return rows and
// gives each worker a window of its own for the rows it appends (D1670); at `-j 1` the
// one worker copies them. Six modules append the same kinds of rows, so at `-j 3`
// the workers' windows each hold some. The image is the same at `-j 1`, `-j 3
// --perturb`, `-j 8` and the default, and linked from `emit-em-all`'s artifacts, and
// the program prints each module's line and the sum it checks.

use e.io
use e.mem
use m1
use m2
use m3
use m4
use m5
use m6

error Failed

fn main(a: *mem.Arena) -> err {
    var sum = 0i64
    let (one, one_error) = m1.run(a)
    if one_error != ok { ret one_error }
    sum += one
    let (two, two_error) = m2.run(a)
    if two_error != ok { ret two_error }
    sum += two
    let (three, three_error) = m3.run(a)
    if three_error != ok { ret three_error }
    sum += three
    let (four, four_error) = m4.run(a)
    if four_error != ok { ret four_error }
    sum += four
    let (five, five_error) = m5.run(a)
    if five_error != ok { ret five_error }
    sum += five
    let (six, six_error) = m6.run(a)
    if six_error != ok { ret six_error }
    sum += six
    try io.printf["sum {}\n"](sum)
    if sum != 2352i64 { ret Failed }
    ret ok
}
