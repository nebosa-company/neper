// `os.env` on every host: the process's environment as NAME=VALUE records, asked for one name
// at a time. `PATH` is set for every process on every host, so it is the one name that can be
// asked for without arranging anything first.

use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    let (search_path, search_path_error) = os.env(a, "PATH")
    if search_path_error != ok { os.exit(10i32) }
    if search_path.len == 0usize { os.exit(11i32) }

    // The value is the text after the `=` and nothing else: no name, no separator.
    if search_path[0usize] == 61u8 { os.exit(12i32) }

    // A name nothing set is `NotFound` and not an empty answer.
    let (unset, unset_error) = os.env(a, "NP_OS_ENVIRONMENT_NOT_SET_ANYWHERE")
    if unset_error != os.NotFound { os.exit(20i32) }

    // A longer name that begins with a real one is not that one, and neither is a shorter one that
    // ends it: a lookup that compared only as far as the stored name reaches would answer `PATHH`
    // with `PATH`'s value, and one that compared the other way round would answer `PAT`.
    let (overrun, overrun_error) = os.env(a, "PATHH")
    if overrun_error != os.NotFound { os.exit(21i32) }
    let (prefix, prefix_error) = os.env(a, "PAT")
    if prefix_error != os.NotFound { os.exit(22i32) }

    // The empty name matches nothing, where a record split at the first `=` with no length check
    // would match the first entry.
    let (empty_name, empty_name_error) = os.env(a, "")
    if empty_name_error != os.NotFound { os.exit(23i32) }

    // Asking twice gives the same answer: the lookup leaves nothing behind that changes the next.
    let (again, again_error) = os.env(a, "PATH")
    if again_error != ok { os.exit(30i32) }
    if again.len != search_path.len { os.exit(31i32) }
    ret ok
}
