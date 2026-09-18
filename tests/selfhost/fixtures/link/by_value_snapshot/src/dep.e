type Value = struct { a: usize, b: usize, c: usize }

fn overwrite(v: Value, p: *Value) -> usize {
    p.a = 0usize
    p.b = 0usize
    p.c = 0usize
    ret read(v)
}

fn read(v: Value) -> usize {
    ret v.a * 100usize + v.b * 10usize + v.c
}
