type Choice = union enum u8 {
    Some: i32,
    None,
}

fn run(choice: Choice) {
    switch choice {
    case .Some as choice:
        ret
    default:
        ret
    }
}
