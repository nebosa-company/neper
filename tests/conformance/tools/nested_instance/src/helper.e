use e.mem

fn fill[T: type](dst: []T, src: []const T) {
    mem.copy[T](dst, src)
}

fn count[T: type](items: []const T) -> usize {
    ret items.len
}
