type Record = struct {
    tiny: u8,
    value: i64,
    tail: u16,
}

fn main() -> i64 {
    let record = Record{ tiny: 7u8, value: 35i64, tail: 9u16 }
    var blank: Record = zero
    var values: [3]u16 = zero
    let all = values[..]
    if record.tiny != 7u8 { ret 1i64 }
    if record.tail != 9u16 { ret 2i64 }
    if blank.tiny != 0u8 || blank.value != 0i64 || blank.tail != 0u16 { ret 3i64 }
    if all.len != 3usize { ret 4i64 }
    if values[2usize] != 0u16 || all[1usize] != 0u16 { ret 5i64 }
    ret record.value - 35i64
}
