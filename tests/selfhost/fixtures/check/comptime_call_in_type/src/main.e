// A constant that calls a function is settled once the signatures exist; a struct
// field length asks for it before them and is refused naming the reason (D222).
fn size() -> usize { ret 4usize }
const N = size()
type Box = struct { data: [N]u8 }
fn main() {}
