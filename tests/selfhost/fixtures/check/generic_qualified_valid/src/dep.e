type Item = struct {
    value: usize,
}

fn identity[T: type](value: T) -> T {
    ret value
}

fn length[N: usize](values: [N]u8) -> usize {
    ret N
}
