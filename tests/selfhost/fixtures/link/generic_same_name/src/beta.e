type Pair[T: type] = struct { first: T, second: T }

fn make[T: type](v: T) -> Pair[T] { ret Pair[T] { first: v, second: v } }
