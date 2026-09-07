use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let (s, e) = str.format["{}"](a, 1i64, 2i64)
    if e != ok { ret e }
    ret ok
}
