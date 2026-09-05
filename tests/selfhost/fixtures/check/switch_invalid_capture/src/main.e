type Node = union enum u8 {
    Empty,
    Value: i32,
}

fn run(node: Node) {
    switch node {
    case .Empty as value:
        let copy = value
    case .Value:
        let copy = node
    }
}
