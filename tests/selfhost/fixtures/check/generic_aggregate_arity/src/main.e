type Box[T: type] = struct { value: T }

fn run() -> Box[i32, u32] {
    ret Box[i32, u32]{ value: 1i32 }
}
