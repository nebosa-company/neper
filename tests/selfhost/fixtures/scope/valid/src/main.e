fn valid(flag: bool) {
    if flag {
        let item = 1i32
    }
    if flag {
        let item = 2i32
    }
    for index in 0i32..1i32 {
        let inside = index
    }
    for index in 0i32..1i32 {
        let inside = index
    }
}

fn separate(flag: bool) {
    let item = flag
}

type Choice = union enum u8 {
    First: i32,
    Second: i32,
}

fn arms(choice: Choice) {
    switch choice {
    case .First as payload:
        ret
    case .Second as payload:
        ret
    }
}
