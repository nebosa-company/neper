// Section 4's `@packed` and `@align(N)` (D925): a packed struct's fields sit at
// alignment one with no padding, `@align(N)` raises an aggregate's alignment and tail
// rounding, and with `@packed` it keeps the packed offsets. The bytes of a packed
// value are read back to show where each field landed. Exit 0 when every layout is
// section 4's.
use e.mem

type Seven = [7]u8

@packed
type Header = struct { kind: u8, length: u32, flags: u16 }

@align(16)
type Line = struct { first: u8 }

@packed
@align(8)
type Framed = struct { kind: u8, length: u32 }

@align(8)
type Either = union { small: u8, wide: u32 }

fn main() -> i32 {
    if mem.size_of[Header]() != 7usize || mem.align_of[Header]() != 1usize { ret 1i32 }
    if mem.size_of[Line]() != 16usize || mem.align_of[Line]() != 16usize { ret 2i32 }
    if mem.size_of[Framed]() != 8usize || mem.align_of[Framed]() != 8usize { ret 3i32 }
    if mem.size_of[Either]() != 8usize || mem.align_of[Either]() != 8usize { ret 4i32 }
    var header = Header { kind: 1u8, length: 0x01020304u32, flags: 7u16 }
    let raw = *mem.cast[*Seven](&header)
    if raw[0usize] != 1u8 || raw[1usize] != 4u8 || raw[4usize] != 1u8 || raw[5usize] != 7u8 || raw[6usize] != 0u8 { ret 5i32 }
    header.length = 9u32
    if header.length != 9u32 || header.flags != 7u16 || header.kind != 1u8 { ret 6i32 }
    ret 0i32
}
