fn value(seed: i32) -> (i32, err) {
    ret (seed, ok)
}

fn pair(seed: i32) -> (i32, bool, err) {
    ret (seed, true, ok)
}

fn finish() -> err {
    ret ok
}

fn run() -> err {
    let first = try value(1i32)
    let (second, present) = try pair(2i32)
    var third = 0i32
    third = try value(3i32)
    var fourth = 0i32
    var assigned_present = false
    (fourth, assigned_present) = try pair(4i32)
    try finish()
    ret ok
}
