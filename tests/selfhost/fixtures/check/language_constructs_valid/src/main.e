use dep as d

error LocalFailure

type State = enum u8 {
    Idle,
    Busy,
    Done,
}

type Option = union enum u8 {
    None,
    Some: i32,
}

fn local_error() -> err {
    ret LocalFailure
}

fn remote_error() -> err {
    ret d.RemoteFailure
}

fn exercise(values: []i32, text: str, pointer: *i32, shift: u8) -> u32 {
    let idle: State = .Idle
    let busy = State.Busy
    let remote = d.Mode.Ready
    let none: Option = .None
    var result = 1u32
    result <<= shift
    result >>= 1
    let shifted = result << 2u16
    if idle < busy && remote == d.Mode.Ready && pointer != nil {
        result += shifted
    }
    for i in 0usize..values.len {
        if i == 0usize { continue }
        break
    }
    for index, value in values {
        if index == 0usize && value == 0i32 { continue }
    }
    for byte in text {
        if byte == 0u8 { break }
    }
    ret result
}
