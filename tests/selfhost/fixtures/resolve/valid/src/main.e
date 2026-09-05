use dep as d

type Local = struct {
    item: d.Item,
}

fn read(item: d.Item) -> i32 {
    ret d.answer(item)
}

fn fail() -> err {
    ret d.Failure
}

fn state() -> i32 {
    ret d.state
}

fn invoke() -> i32 {
    ret d.foreign(d.ANSWER)
}
