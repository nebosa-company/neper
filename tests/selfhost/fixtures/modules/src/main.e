use e.io
use e.mem
use util.math as calc

fn read(result: calc.Result) -> i32 {
    ret result.value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let result = calc.make()
    if !calc.correct(result) || read(result) != 42i32 { ret calc.Wrong }
    try io.print("module loading ok\n")
    ret ok
}
