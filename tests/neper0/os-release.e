use e.mem
use e.os

// `os.release` and the bootstrap's registry of reservations (D1665). Its own fixture:
// the bootstrap refuses os-intrinsics.e since D636 (`os.file_handle` is not on its surface).
fn main(a: *mem.Arena, startup_args: []str) -> err {
    // A released page is gone: committing it again fails, on both hosts.
    let (page, reserve_error) = os.reserve(4096usize)
    if reserve_error != ok { ret reserve_error }
    let commit_error = os.commit(page, 4096usize)
    if commit_error != ok { ret commit_error }
    *page = 77u8
    let release_error = os.release(page, 4096usize)
    if release_error != ok { ret release_error }
    if os.commit(page, 4096usize) == ok { ret os.Failed }

    // Released regions and regions committed whole give their registry slots back, so after
    // 300 of each an arena over a fresh reservation still grows by commits under the
    // bootstrap's Windows runtime. A released one is committed only in part, so its release
    // alone frees its slot. They come first, so that the live regions after them, not the
    // arena's reservation, take the addresses they freed. Linux commits the reservation
    // here, as `graph.reserved_arena` does (D348).
    var released = 0usize
    while released < 300usize {
        let (part, part_error) = os.reserve(8192usize)
        if part_error != ok { ret part_error }
        let part_commit = os.commit(part, 4096usize)
        if part_commit != ok { ret part_commit }
        let part_release = os.release(part, 8192usize)
        if part_release != ok { ret part_release }
        released += 1usize
    }
    var filled = 0usize
    while filled < 300usize {
        let (small, small_error) = os.reserve(4096usize)
        if small_error != ok { ret small_error }
        let small_commit = os.commit(small, 4096usize)
        if small_commit != ok { ret small_commit }
        filled += 1usize
    }
    let (big, big_error) = os.reserve(8388608usize)
    if big_error != ok { ret big_error }
    let (cwd, cwd_error) = os.current_dir(a)
    if cwd_error != ok { ret cwd_error }
    if cwd.len != 0usize && cwd[0usize] == 47u8 {
        let big_commit = os.commit(big, 8388608usize)
        if big_commit != ok { ret big_commit }
    }
    var region: mem.Arena = zero
    region.base = big
    region.cap = 8388608usize
    let (bytes, bytes_error) = mem.alloc[u8](&region, 2097152usize)
    if bytes_error != ok { ret bytes_error }
    bytes[2097151usize] = 1u8
    if bytes[2097151usize] != 1u8 { ret os.Failed }

    let (written, write_error) = os.write(os.stdout(), "release ok\n")
    if write_error != ok { ret write_error }
    if written != 11usize { ret os.Failed }
    ret ok
}
