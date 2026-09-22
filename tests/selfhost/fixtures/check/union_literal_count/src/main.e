type Value = union { number: i32, flag: u8 }

fn run() -> Value {
    ret Value{ number: 1i32, flag: 1u8 }
}
