type Value = union { number: i32, flag: bool }

fn run() -> Value {
    ret Value{ number: 1i32, flag: true }
}
