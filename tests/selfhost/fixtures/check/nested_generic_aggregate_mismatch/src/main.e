type Box[T: type] = struct { value: T }
type Pair[T: type] = struct { left: Box[T], right: Box[T] }

fn run() -> Pair[i32] {
    ret Pair[i32]{
        left: Box[u32]{ value: 1u32 },
        right: Box[i32]{ value: 2i32 },
    }
}
