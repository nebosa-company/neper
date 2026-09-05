fn pair(seed: i32) -> (i32, bool) {
    ret (seed, true)
}

fn run() -> bool {
    let (value, present) = pair(7i32)
    let (_, discarded_position) = pair(8i32)
    var assigned_value = 0i32
    var assigned_present = false
    (assigned_value, assigned_present) = pair(9i32)
    ret value == 7i32 && present && discarded_position && assigned_value == 9i32 && assigned_present
}
