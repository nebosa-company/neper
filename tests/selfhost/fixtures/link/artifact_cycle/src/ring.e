// `ring` imports `e.os`, a module whose name is as long as `main`'s: the runner
// rewrites the artifact's `e.os` strings to `main`, so the artifact claims an
// edge to the module that imports it -- a cycle no source can spell.
use e.os

fn code() -> i32 {
    if os.page_size() == 0usize { ret 0i32 }
    ret 7i32
}
