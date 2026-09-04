use e.mem
use e.io

const WIDTH: usize = BASE * 2
const BASE: usize = 2
const OFFSET: i64 = -3i64 + 10i64

type Block = struct {
    values: [WIDTH]u16,
}

fn sum(values: [WIDTH]u16) -> u16 {
    var total = 0u16
    for value in values {
        total += value
    }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [BASE * 2]u16{ 1u16, 2u16, 3u16, 4u16 }
    let block = Block{ values: values }
    let runtime_value = OFFSET + 1i64
    if values.len == 4usize && block.values[3usize] == 4u16 && sum(values) == 10u16 && runtime_value == 8i64 {
        try io.print("constant folding ok\n")
    } else {
        try io.print("constant folding failed\n")
    }
    ret ok
}
