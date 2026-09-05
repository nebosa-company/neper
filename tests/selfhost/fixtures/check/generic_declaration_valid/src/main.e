type Buffer[T: type, N: usize] = struct {
    values: [N]T,
}

type Choice = enum u8 {
    First,
    Second,
}

fn identity[T: type](value: T) -> T {
    ret value
}

fn forward[T: type](value: T) -> T {
    ret identity[T](value)
}

fn greater[T: type](left: T, right: T) -> bool {
    ret left > right
}

fn first[T: type, N: usize](values: [N]T) -> T {
    ret values[0usize]
}

fn nested_first[T: type, N: usize](buffer: Buffer[T, N]) -> T {
    ret buffer.values[0usize]
}

fn add[T: type](left: T, right: T) -> T {
    ret left + right
}

fn add_i32[T: type](value: T) -> T {
    ret value + 1i32
}

fn negate[T: type](value: T) -> T {
    ret -value
}

fn invert[T: type](value: T) -> T {
    ret ~value
}

fn shift[T: type](value: T) -> T {
    ret value << 1u8
}

fn length[T: type](value: T) -> usize {
    ret value.len
}

fn unknown_index[T: type](value: T) -> u8 {
    ret value[0usize]
}

fn unknown_deref[T: type](value: T) -> i32 {
    ret *value
}

fn compare_forward[T: type](left: T, right: T) -> bool {
    ret greater[T](left, right)
}

fn inferred_forward[T: type](value: T) -> T {
    ret identity(value)
}

fn array_count[T: type, N: usize](values: [N]T) -> usize {
    ret values.len
}

fn inferred_count[T: type, N: usize](values: [N]T) -> usize {
    ret array_count(values)
}

fn make_buffer[T: type](value: T) -> Buffer[T, 1usize] {
    ret Buffer[T, 1usize]{ values: [1usize]T{ value } }
}

fn dependent_array_literal[T: type, N: usize](value: T) -> [N]T {
    ret [N]T{ value }
}

fn assign_unknown_deref[T: type](pointer: T, value: i32) {
    *pointer = value
}

fn assign_unknown_index[T: type](values: T, value: u8) {
    values[0usize] = value
}

fn compound_unknown[T: type](value: T) {
    var copy = value
    copy += value
}

fn iterate_unknown[T: type](values: T) -> usize {
    var count = 0usize
    for value in values {
        count += 1usize
    }
    ret count
}

fn switch_unknown[T: type](value: T) -> i32 {
    switch value {
    case .First:
        ret 1i32
    default:
        ret 0i32
    }
}

fn exercise(pointer: *i32, values: []u8, fixed: [4usize]u8, choice: Choice) -> bool {
    assign_unknown_deref[*i32](pointer, 1i32)
    assign_unknown_index[[]u8](values, 2u8)
    compound_unknown[i32](3i32)
    let sum = add[i32](4i32, 5i32)
    let adjusted = add_i32[i32](sum)
    let negative = negate[i32](adjusted)
    let inverted = invert[u8](2u8)
    let shifted = shift[u8](inverted)
    let count = length[[]u8](values)
    let first_byte = unknown_index[[]u8](values)
    let pointed = unknown_deref[*i32](pointer)
    let iterated = iterate_unknown[[]u8](values)
    let selected = switch_unknown[Choice](choice)
    let forwarded = inferred_forward(negative)
    let fixed_count = inferred_count(fixed)
    let buffer = make_buffer[i32](forwarded)
    let singleton = dependent_array_literal[i32, 1usize](forwarded)
    ret greater[i32](pointed, selected)
}
