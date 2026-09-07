use e.mem

fn width[LABEL: str]() -> usize {
    ret LABEL.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    if width[3usize]() != 3usize { ret ok }
    ret ok
}
