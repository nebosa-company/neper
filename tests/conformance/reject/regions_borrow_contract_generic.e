// A specialization carries the template's exact result-borrow parameter.
@borrows("right")
fn choose[T: type](left: []T, right: []T) -> []T {
    ret right
}

fn touch(bytes: *[2]u8) {}

fn main() {
    var left: [2]u8 = zero
    var right: [2]u8 = zero
    let selected = choose[u8](left[..], right[..])
    touch(&right)
    let first = selected[0usize]
}
