use e.os

// Seeded resource representations are private; the explicit plain Handle view
// is how checked code reads the platform value.
fn main() -> err {
    let _ = os.file_handle(os.stdin()).raw
    ret ok
}
