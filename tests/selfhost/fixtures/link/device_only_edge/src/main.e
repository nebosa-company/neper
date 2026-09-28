// A warm build after a helper becomes device-only checks its callers again (D1677):
// `host` calls `lane.helper` from plain CPU code, and `dev`'s device-only `tap` calls
// it too. `main` reaches `host` alone, and names `dev` so its artifact is built.
use dev
use host

error Failed

fn main() -> err {
    if host.run() != 1u32 { ret Failed }
    ret ok
}
