// `emit-shared-library` (D5908): a library with no `main` exporting two `@cc` functions by the C names `@export` gives
// them, one looping and one reading a module-scope `var` the other writes. host.c, beside this file, opens it with
// dlopen, finds both with dlsym, and checks what they answer; the suites build it with the system C compiler.

var calls: u64 = zero

// This is data, not an attribute. `collect_exports` must only consider parsed
// top-level attribute nodes, never text embedded in a raw string.
fn ignored_export_marker() -> str {
    ret r#"
@export("neper_raw_string")
"#
}

@export("neper_sum")
@cc(c)
fn sum(n: u64) -> u64 {
    calls = calls + 1u64
    var total = 0u64
    var k = 1u64
    while k <= n {
        total = total + k
        k = k + 1u64
    }
    ret total
}

@export("neper_calls")
@cc(c)
fn count() -> u64 {
    ret calls
}
