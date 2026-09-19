// The caller retains the parameter named by the summary, not the first argument.
@borrows("right")
fn choose(left: []u8, right: []u8) -> []u8 {
    ret right
}

fn touch(bytes: *[2]u8) {}

fn main() {
    var left: [2]u8 = zero
    var right: [2]u8 = zero
    let selected = choose(left[..], right[..])
    touch(&right)
    let first = selected[0usize]
}
