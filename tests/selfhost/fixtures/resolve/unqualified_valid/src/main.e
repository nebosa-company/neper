type Box[T: type, N: usize] = struct {
    values: [N]T,
}

type Choice = union enum u8 {
    First: i32,
    Second: i32,
}

const FORWARD_COUNT: usize = COUNT
const COUNT: usize = 2usize

fn identity[T: type](value: T) -> T {
    ret value
}

fn forward(value: i32) -> i32 {
    ret later(value)
}

fn later(value: i32) -> i32 {
    ret value
}

fn architecture(value: target.Arch) -> target.Arch {
    ret value
}

fn run(flag: bool, choice: Choice) -> i32 {
    let first = forward(1i32)
    let second = first
    if flag {
        let scoped = second
    }
    for index in 0usize..COUNT {
        let copy = index
    }
    switch choice {
    case .First as payload:
        ret identity[i32](payload)
    case .Second as payload:
        ret payload
    }
}
