use e.os

// `file_handle` is the checked representation view, so File.raw is private to
// e.os just like the fields of a declared resource are private to its module.
fn main() -> err {
    let _ = os.stdin().raw
    ret ok
}
