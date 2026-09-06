use dep

error Failed

fn last[T: type](values: []T) -> T {
    ret values[values.len - 1usize]
}

fn main() -> err {
    let wide = dep.make[i64](1i64, 2i64)
    let narrow = dep.make[i32](11i32, 22i32)
    if dep.tail[i64](wide) != 2i64 { ret Failed }
    if dep.tail[i32](narrow) != 22i32 { ret Failed }
    var longs: [3]i64 = zero
    longs[2usize] = 9i64
    var shorts: [3]i32 = zero
    shorts[2usize] = 5i32
    if last[i64](longs[..]) != 9i64 { ret Failed }
    if last[i32](shorts[..]) != 5i32 { ret Failed }
    ret ok
}
