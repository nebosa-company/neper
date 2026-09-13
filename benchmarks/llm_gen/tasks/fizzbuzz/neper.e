use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    for i in 1i32..16 {
        if i % 15 == 0 { try io.print("FizzBuzz\n") } else {
            if i % 3 == 0 { try io.print("Fizz\n") } else {
                if i % 5 == 0 { try io.print("Buzz\n") } else { try io.printf["{}\n"](i) }
            }
        }
    }
    ret ok
}
