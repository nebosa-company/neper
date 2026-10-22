use e.mem
use e.os

// `os.spawn_with_options` with two environment entries, run by the bootstrap itself: the self-hosted `run
// --gpu-inventory` hands its child two, and the bootstrap's runtime used to refuse more than one. The child
// is this program with `child`; the parent's own environment is put back afterwards.
fn main(a: *mem.Arena, startup_args: []str) -> err {
    if startup_args.len > 1usize && same(startup_args[1], "child") {
        let (first, first_error) = os.env(a, "NEPER_SPAWN_ENV_A")
        let (second, second_error) = os.env(a, "NEPER_SPAWN_ENV_B")
        if first_error != ok || second_error != ok { os.exit(3i32) }
        if !same(first, "one") || !same(second, "two") { os.exit(4i32) }
        os.exit(0i32)
    }
    var argv: [2]str = zero
    argv[0] = startup_args[0]
    argv[1] = "child"
    var env: [2]str = zero
    env[0] = "NEPER_SPAWN_ENV_A=one"
    env[1] = "NEPER_SPAWN_ENV_B=two"
    var options: os.SpawnOptions = zero
    options.argv = argv[0usize..2usize]
    options.env = env[0usize..2usize]
    options.inherit_env = true
    options.stdio.stdin = os.stdin()
    options.stdio.stdout = os.stdout()
    options.stdio.stderr = os.stderr()
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret spawn_error }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok { ret wait_error }
    if usage.exit_code != 0i32 { ret os.Failed }
    let (left_a, left_a_error) = os.env(a, "NEPER_SPAWN_ENV_A")
    let (left_b, left_b_error) = os.env(a, "NEPER_SPAWN_ENV_B")
    if left_a_error == ok || left_b_error == ok { ret os.Failed }
    let (written, write_error) = os.write(os.stdout(), "spawn env ok\n")
    ret write_error
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}
