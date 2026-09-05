fn choose(flag: bool) -> i32 {
    if flag {
        ret 1i32
    } else {
        ret 2i32
    }
}

fn select(flag: bool) -> i32 {
    var result: i32 = 1i32
    if flag {
        result = 2i32
    }
    ret result
}
