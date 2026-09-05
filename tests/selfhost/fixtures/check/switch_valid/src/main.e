error Failed
error Other

const One: i32 = 1i32

type Kind = enum u8 {
    None,
    Int,
    Float,
}

type Node = union enum u8 {
    Lit: i64,
    Nil,
}

fn enum_switch(kind: Kind) -> i32 {
    switch kind {
    case .None:
        ret 0i32
    case .Int, .Float:
        ret 1i32
    }
}

fn tagged_switch(node: Node) -> i64 {
    switch node {
    case .Lit as value:
        ret value
    case .Nil:
        ret 0i64
    }
}

fn default_switch(value: i32) -> i32 {
    switch value {
    case 1i32:
        ret 1i32
    default:
        ret 0i32
    }
}

fn scalar_switch(value: i32, flag: bool, failure: err) {
    switch value {
    case 0i32, One:
        break
    default:
        let copy = value
    }
    switch flag {
    case true:
        let copy = flag
    case false:
        let copy = flag
    }
    switch failure {
    case ok, Failed:
        let copy = failure
    case Other:
        let copy = failure
    }
}

fn nested(values: []i32) {
    for value in values {
        switch value {
        case 0i32:
            continue
        default:
            break
        }
    }
}
