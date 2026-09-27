// A file a full owning list handed back, then dropped (D1568, H01): `own_put`'s
// `(v, true)` is the caller's again, so the exit that forgets it is E-SAFETY-0002.
use e.mem
use e.os
use e.data.list

// Every element closed, the first failure kept and the rest still closed, then the
// list ended empty.
fn close_all(files: own list.Owning[os.File]) -> err {
    var held = files
    var first_error = ok
    while list.owned_count[os.File](&held) != 0usize {
        let (f, got) = list.own_take[os.File](&held)
        if got {
            let closed = os.close(f)
            if closed != ok && first_error == ok { first_error = closed }
        }
    }
    list.owning_finish[os.File](held)
    ret first_error
}

fn main(a: *mem.Arena) -> err {
    var (files, made) = list.owning[os.File](a, 1usize)
    if made != ok {
        list.owning_finish[os.File](files)
        ret made
    }
    defer let _ = close_all(files)
    let first = try os.dup(os.stdout())
    let (back, full) = list.own_put[os.File](&files, first)
    if full { }
    let second = try os.dup(os.stdout())
    let (again, still_full) = list.own_put[os.File](&files, second)
    if still_full { try os.close(again) }
    ret ok
}
