use e.io

type Kind = enum u8 {
    None,
    Int = 3,
    Float,
}

type Value = union {
    i: i64,
    byte: u8,
}

type Node = union enum u8 {
    Lit: i64,
    Nil,
}

fn classify(k: Kind) -> i64 {
    switch k {
    case .None:
        ret 0i64
    case .Int:
        ret 1i64
    case .Float:
        ret 2i64
    }
}

fn payload(n: Node) -> i64 {
    switch n {
    case .Lit as value:
        ret value
    case .Nil:
        ret 0i64
    }
}

fn scalar(value: i64) -> i64 {
    var result = 0i64
    switch value {
    case 1i64, 2i64:
        result = 7i64
        break
    default:
        result = 9i64
    }
    ret result
}

fn main(a: *mem.Arena, args: []str) -> err {
    let kind: Kind = .Int
    if classify(kind) != 1i64 { ret ok }

    let raw = Value{ i: 9i64 }
    if raw.i != 9i64 { ret ok }

    let node = Node{ Lit: 41i64 }
    if node.tag != Node.Tag.Lit { ret ok }
    if node.Lit != 41i64 { ret ok }
    if payload(node) != 41i64 { ret ok }
    if scalar(2i64) != 7i64 { ret ok }
    if scalar(3i64) != 9i64 { ret ok }

    let empty: Node = .Nil
    if empty.tag != .Nil { ret ok }

    try io.print("enum union switch ok")
    ret ok
}
