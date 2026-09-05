type Box[T: type] = struct { value: T }

fn run() -> Box[u32] {
    ret Box[i32]{ value: 1i32 }
}
