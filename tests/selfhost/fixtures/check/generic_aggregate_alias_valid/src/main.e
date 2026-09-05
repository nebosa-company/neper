type Box[T: type] = struct {
    value: T,
}

type IntBox = Box[i32]

fn read(box: IntBox) -> i32 {
    ret box.value
}

fn run() -> IntBox {
    let box: IntBox = Box[i32]{ value: 7i32 }
    let value = read(box)
    ret Box[i32]{ value: value }
}
