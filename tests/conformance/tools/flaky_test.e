// A test that fails the first time it runs and passes after (T041, H39): the marker file is the
// state between two runs, written to the working directory the suite clears before it starts.
use e.mem
use e.fs

error Flaked

@test
fn settles(a: *mem.Arena) -> err {
    let (seen, exists_error) = fs.exists(a, "flaky-marker.txt")
    if exists_error != ok { ret exists_error }
    if seen { ret ok }
    let wrote = fs.write_file(a, "flaky-marker.txt", "x")
    if wrote != ok { ret wrote }
    ret Flaked
}

@test
fn steady(a: *mem.Arena) -> err {
    ret ok
}
