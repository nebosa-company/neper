fn run(mut: *i32, shift: u32) {
    var value = 8i32
    value += 2i32
    value -= 1i32
    value *= 3i32
    value /= 2i32
    value %= 5i32
    value +%= 1i32
    value -%= 1i32
    value *%= 2i32
    value &= 7i32
    value ^= 1i32
    value |= 8i32
    value <<= shift
    value >>= 1
    *mut += value
}
