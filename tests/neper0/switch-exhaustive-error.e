type Kind = enum u8 {
    One,
    Two,
}

fn main(a: *mem.Arena, args: []str) -> err {
    let kind: Kind = .One
    switch kind {
    case .One:
        ret ok
    }
    ret ok
}
