// A list that owns what it holds (D1568, H01/H02). `list.Owning` reserves its slots
// up front, so a full list hands an element back instead of taking it, and nothing
// is lost; every element taken is closed, the first failure kept and the rest still
// closed. Run as `unfinished`, the list is ended while it still holds a file, which
// traps rather than lose the file.
use e.mem
use e.os
use e.data.list

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

fn unfinished(a: *mem.Arena) -> err {
    var (files, made) = list.owning[os.File](a, 1usize)
    if made != ok {
        list.owning_finish[os.File](files)
        ret made
    }
    let (f, dup_error) = os.dup(os.stdout())
    if dup_error != ok {
        list.owning_finish[os.File](files)
        ret dup_error
    }
    let (back, full) = list.own_put[os.File](&files, f)
    if full { let _ = os.close(back) }
    list.owning_finish[os.File](files)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize { ret unfinished(a) }
    var (files, made) = list.owning[os.File](a, 1usize)
    if made != ok {
        list.owning_finish[os.File](files)
        ret made
    }
    defer let _ = close_all(files)
    let first = try os.dup(os.stdout())
    let (back, full) = list.own_put[os.File](&files, first)
    if full { try os.close(back) }
    // The one slot is taken: the second file comes back, and is closed here.
    let second = try os.dup(os.stdout())
    let (again, still_full) = list.own_put[os.File](&files, second)
    if !still_full { ret mem.Exhausted }
    try os.close(again)
    if list.owned_count[os.File](&files) != 1usize { ret mem.Exhausted }
    ret ok
}
