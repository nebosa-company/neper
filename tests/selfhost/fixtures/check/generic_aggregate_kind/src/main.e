type Box[T: type] = struct { value: T }

fn run() -> Box[3] {
    ret Box[3]{ value: 1i32 }
}
