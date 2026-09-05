type Mutable = []i32
type Readonly = []const i32

fn take(values: Mutable) {
    ret
}

fn run(values: Readonly) {
    take(values)
}
