// A constant whose value would be a pointer (D1570, C066): section 9 requires a
// constant's value to be pointer-free, and an address into the interpreter's memory
// means nothing once the evaluation ends, so it is refused naming the constant.
fn address() -> *u32 {
    var x = 1u32
    ret &x
}

const WHERE = address()

fn main() {}
