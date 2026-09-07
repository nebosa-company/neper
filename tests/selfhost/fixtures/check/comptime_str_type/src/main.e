use e.mem

fn width[LABEL: str]() -> usize {
    ret LABEL.len
}

fn main(a: *mem.Arena, args: []str) -> err {
    if width[u8]() != 3usize { ret ok }
    ret ok
}
