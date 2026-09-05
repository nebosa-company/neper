fn add(a: i32, b: i32) -> i32 {
    ret a + b
}

fn forward(flag: bool) -> i32 {
    ret choose(flag)
}

fn no_value() -> void {
    ret
}

fn branch(flag: bool) -> i32 {
    if flag {
        ret 1i32
    } else {
        ret 2i32
    }
}

fn scalars(flag: bool) -> bool {
    let text: str = "ok"
    let byte: u8 = 'x'
    let status: err = ok
    let succeeded = status == ok
    while false {}
    ret flag != false
}

fn choose(flag: bool) -> i32 {
    let value: i32 = add(1, 2i32)
    let narrowed = i32(3i64)
    let total: i32 = 1 + 2
    let ratio = 1.0f32 + 2.0
    let equal = flag == true
    no_value()
    if flag {
        let copy = value
    }
    var result = value
    result = result + 1i32
    ret result
}
