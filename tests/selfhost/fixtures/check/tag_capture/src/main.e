type Value = union enum u8 {
    Empty,
    Item: i32,
}

fn run(value: Value) {
    switch value.tag {
    case .Empty:
        let copy = value
    case .Item as payload:
        let copy = payload
    }
}
