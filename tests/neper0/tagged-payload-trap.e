type Node = union enum u8 {
    Lit: i64,
    Nil,
}

fn main(a: *mem.Arena, args: []str) -> err {
    let node: Node = .Nil
    if node.Lit == 0i64 { ret ok }
    ret ok
}
