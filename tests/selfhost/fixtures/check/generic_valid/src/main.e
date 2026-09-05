type Local = struct {
    value: usize,
}

fn identity[T: type](value: T) -> T {
    ret value
}

fn forward[T: type](value: T) -> T {
    ret identity[T](value)
}

fn array_length[N: usize](values: [N]u8) -> usize {
    ret N
}

fn doubled_length[N: usize](values: [N * 2]u8) -> usize {
    ret N * 2usize
}

fn choose[T: type, N: usize](value: T, values: [N]u8) -> T {
    ret value
}

fn from_slice[T: type](values: []T, fallback: T) -> T {
    ret fallback
}

fn from_pointer[T: type](pointer: *const T, fallback: T) -> T {
    ret fallback
}

fn run(values: [4]u8, doubled: [8]u8, words: []u16, bytes: []u8, pointer: *u8, local: Local) -> usize {
    let explicit = identity[i32](1)
    let inferred = identity(explicit)
    let forwarded = forward[u16](2u16)
    let explicit_length = array_length[4](values)
    let inferred_length = array_length(values)
    let expression_length = doubled_length[4](doubled)
    let partially_inferred = choose[i32](3, values)
    let cached = identity[i32](partially_inferred)
    let slice_inferred = from_slice(words, 4)
    let pointer_inferred = from_pointer(&explicit, 5)
    let array_type = identity[[4]u8](values)
    let slice_type = identity[[]u8](bytes)
    let pointer_type = identity[*u8](pointer)
    let named_type = identity[Local](local)
    ret explicit_length + inferred_length + expression_length
}
