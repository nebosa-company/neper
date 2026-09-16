// A declaration the dependent uses, deleted by `edits/dep_without.e` (D495, H14): the
// warm build after it must report the dependent's lost name as a cold build would.
fn answer() -> i32 {
    ret 4i32
}

fn extra() -> i32 {
    ret 1i32
}
