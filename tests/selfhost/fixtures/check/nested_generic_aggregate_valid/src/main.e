type Box[T: type] = struct {
    value: T,
}

type Pair[T: type] = struct {
    left: Box[T],
    right: Box[T],
}

fn unwrap[T: type](pair: Pair[T]) -> T {
    ret pair.left.value
}

fn run() -> i64 {
    let pair = Pair[i64]{
        left: Box[i64]{ value: 3i64 },
        right: Box[i64]{ value: 5i64 },
    }
    ret unwrap[i64](pair)
}
