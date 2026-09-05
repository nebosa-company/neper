type Value = union enum u8 {
    Empty,
    Item: i32,
}

fn run(value: Value) -> bool {
    ret value.tag == Value.Tag.Missing
}
