// `fmt --check --json` (D243): a deliberately non-canonical source -- extra spaces and
// missing operator spacing -- so the check reports E-FORMAT-0001 at the first differing byte.
fn  add(x: i32, y: i32) -> i32 {
    ret x+%y
}
