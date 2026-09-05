type Maybe = union enum u8 { None, Some: i32 }

fn run() -> Maybe {
    ret Maybe{ Some }
}
