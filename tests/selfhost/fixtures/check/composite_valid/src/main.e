fn view(values: []i32) -> []const i32 {
    ret values
}

fn widen_pointer(value: *i32) -> *const i32 {
    ret value
}

fn array(values: [4]i32) -> [4]i32 {
    ret values
}

fn normalized(values: [4]i32) -> [4usize]i32 {
    ret values
}

fn empty(values: [0]u8) -> [0usize]u8 {
    ret values
}

fn based(values: [0x10]u8, binary: [0b1_0000]u8, octal: [0o20]u8) -> [16]u8 {
    let first: [16]u8 = values
    let second: [16]u8 = binary
    ret octal
}

fn calculated(values: [2usize * (3usize - 1usize)]u8, divided: [8usize / 2usize]u8, remainder: [9usize % 5usize]u8) -> [4]u8 {
    let first: [4]u8 = values
    let second: [4]u8 = divided
    ret remainder
}

fn maximum_length(values: [0xffff_ffff_ffff_ffff]u8) -> [~0usize]u8 {
    ret values
}

fn nested(values: []const []const u8) -> []const []const u8 {
    ret values
}

fn matrix(values: [2][3]u8) -> [2][3]u8 {
    ret values
}

fn opaque(value: *void) -> *void {
    ret value
}

fn maybe() -> *const i32 {
    ret nil
}

fn empty_slice() -> []i32 {
    ret nil
}

fn strings(text: str, bytes: []const u8) -> str {
    let first: []const u8 = text
    let second: str = bytes
    ret second
}

fn mutable_string(bytes: []u8) -> str {
    ret bytes
}

fn local() -> i32 {
    var value = 1i32
    let pointer = &value
    let readonly: *const i32 = pointer
    let immutable = 2i32
    let immutable_pointer: *const i32 = &immutable
    ret *readonly
}
