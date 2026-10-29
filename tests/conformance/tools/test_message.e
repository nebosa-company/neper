// `test --json` (T005): a failed assertion's message is its record's `message`, and a
// passing test's is null.
use e.mem
use e.test

error Terminal

@test
fn says_why(a: *mem.Arena) -> err {
    try test.assert(1i32 + 1i32 == 3i32, "one and one make two")
    ret ok
}

@test
fn passes(a: *mem.Arena) -> err {
    try test.eq(2i32, 2i32, "never shown")
    ret ok
}

// A caught assertion records its text, but a later unrelated failure must not inherit it.
@test
fn returns_after_caught_failure(a: *mem.Arena) -> err {
    let caught = test.assert(false, "stale assertion")
    if caught != test.Failed { ret Terminal }
    ret Terminal
}
