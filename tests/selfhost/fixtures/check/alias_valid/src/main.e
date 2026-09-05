use dep as d

type Count = d.Count
type MutableBytes = []u8
type ReadonlyBytes = []const u8
type MutablePointer = *i32
type ReadonlyPointer = *const i32
type Matrix = [2][3]i32
type Record = struct {
    value: i32,
}
type RecordAlias = Record

fn count(value: Count) -> usize {
    ret value
}

fn text(value: d.Text) -> str {
    ret value
}

fn weaken(value: MutableBytes) -> ReadonlyBytes {
    ret value
}

fn weaken_pointer(value: MutablePointer) -> ReadonlyPointer {
    ret value
}

fn matrix(value: Matrix) -> [2][3]i32 {
    ret value
}

fn nominal(value: RecordAlias) -> Record {
    ret value
}
