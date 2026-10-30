// The compiler as neper.wasm (C184, D5640); platform.e is the native hosts.

// One thread: `os.thread_create` answers Unsupported, and every worker but the first would
// still take a reservation before running on the main thread.
fn jobs(asked: usize) -> usize { ret 1usize }

// The root and every reservation share 4 GiB of address (lib/e/os.wasi.e), and a one-worker
// build holds three at once (the front end's, the lowering's and the link's): each takes a
// quarter of what the root leaves, so they fit with a quarter to spare for the modules' fronts.
fn reservation(root_capacity: usize) -> usize {
    if root_capacity >= 4294901760usize { ret 0usize }
    let left = 4294901760usize - root_capacity
    ret left / 4usize
}

fn triple() -> str { ret "wasm32-wasi" }
