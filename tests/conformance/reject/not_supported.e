// E-TYPE-0009 (T013): a statement the checker has no rule for, named by its first
// line. Assigning to a range of an array is one.
fn main() {
    var a: [4]u8 = zero
    let b: [2]u8 = zero
    a[0usize..2usize] = b
}
