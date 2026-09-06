// Generic templates instantiated by another module at more than one type.

type Pair[T: type] = struct { first: T, second: T }

fn make[T: type](a: T, b: T) -> Pair[T] {
    ret Pair[T] { first: a, second: b }
}

fn tail[T: type](pair: Pair[T]) -> T {
    ret pair.second
}
