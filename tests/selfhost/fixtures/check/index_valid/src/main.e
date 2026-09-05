fn run(array: [4]u16, slice: []u16, readonly: []const u16, text: str) -> u16 {
    let first = array[0]
    let second = slice[1usize]
    let third = readonly[2]
    let byte = text[0]
    var local: [4]u16 = zero
    local[0] = first
    slice[1] = second
    let middle: []u16 = local[1..3]
    let tail: []u16 = slice[1..]
    let prefix: []const u16 = readonly[..2]
    let array_view: []const u16 = array[..]
    let text_view: str = text[1..]
    let lengths: usize = array.len + slice.len + text.len
    let pointer: *u16 = &slice[0]
    let const_pointer: *const u16 = &readonly[0]
    *pointer = third
    ret middle[0]
}
