fn identity(value: i32) -> i32 {
    ret value
}

fn readonly(values: []i32) -> []const i32 {
    ret values
}

fn consume(value: i32) {
    ret
}

const VALUE: i32 = 42i32
