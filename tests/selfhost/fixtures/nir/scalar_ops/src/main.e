fn ignore() -> void {}

fn scalar(input: i64, flag: bool) -> i32 {
    ignore()
    let narrowed: i32 = i32(input)
    let negative: i32 = -narrowed
    let inverted: i32 = ~negative
    if !flag {
        ret inverted
    }
    ret narrowed
}
