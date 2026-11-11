type Box[T: type] = struct { value: T, count: usize }

fn make[T: type](value: T) -> Box[T] {
    ret Box[T] { value: value, count: 7usize }
}

fn count[T: type](b: *Box[T]) -> usize {
    ret b.count
}
