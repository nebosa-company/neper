// `test --json` (D240): @test discovery, a per-process run of each, and section 7's stream.
use e.mem

error Mismatch

@test
fn arithmetic_holds(a: *mem.Arena) -> err {
    if 2i32 + 2i32 == 4i32 { ret ok }
    ret Mismatch
}

@test
fn reports_a_failure(a: *mem.Arena) -> err {
    ret Mismatch
}

fn pick(values: []const i32, index: usize) -> i32 {
    ret values[index]
}

@test
fn crashes(a: *mem.Arena) -> err {
    var values: [5]i32 = zero
    let chosen = pick(values[..], usize(values[0usize]) + 7usize)
    if chosen == 0i32 { ret ok }
    ret Mismatch
}
