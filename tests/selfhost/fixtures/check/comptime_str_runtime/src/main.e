use e.mem

fn width[LABEL: str]() -> usize {
    ret LABEL.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    // A comptime argument has to have a value where the instance is chosen, and a
    // local does not.
    let name = "abc"
    if width[name]() != 3usize { ret ok }
    ret ok
}
