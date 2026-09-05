fn answer(item: Item) -> i32 {
    ret item.value
}

type Item = struct {
    value: i32,
}

error Failure

const ANSWER: i32 = 42i32
var state: i32
extern fn foreign(value: i32) -> i32
