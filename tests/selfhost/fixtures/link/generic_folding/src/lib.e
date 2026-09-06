// One template, instantiated at the same type by two different modules. Each
// module owns its own copy, so the own linker has two identical bodies to fold.

fn pick[T: type](a: T, b: T, first: bool) -> T {
    if first { ret a }
    ret b
}
