error Wrong

const expected: i32 = 42i32

type Result = struct {
    value: i32,
}

fn make() -> Result {
    ret Result { value: expected }
}

fn correct(result: Result) -> bool {
    ret result.value == expected
}
