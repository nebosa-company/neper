use dep as d

fn run(values: []i32) -> []const i32 {
    let answer = d.identity(42i32)
    d.consume(answer)
    ret d.readonly(values)
}
