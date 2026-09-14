// A module with a type error in a body: reported once, when it is the module checked.
error Odd

fn twice(x: i32) -> i32 {
    let wrong: i64 = x
    ret x + x
}
