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
