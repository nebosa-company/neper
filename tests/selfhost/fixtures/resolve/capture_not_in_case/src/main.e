type Choice = union enum u8 {
    Some: i32,
}

fn run(choice: Choice) {
    switch choice {
    case payload as payload:
        ret payload
    default:
        ret
    }
}
