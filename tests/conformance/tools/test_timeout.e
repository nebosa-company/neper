// `test --json` with a deadline (D245): the second test never returns, so its own process
// is ended by the runner's watchdog thread and it is reported `timeout`, not `crashed`.
use e.mem

@test
fn returns_at_once(a: *mem.Arena) -> err {
    ret ok
}

@test
fn never_returns(a: *mem.Arena) -> err {
    var spin = 0usize
    while true { spin += 1usize }
    ret ok
}
