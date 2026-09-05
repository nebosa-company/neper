type Buffer[T: type, N: usize] = struct { values: [N]T }

fn run() -> Buffer[i32, 2] {
    ret Buffer[i32, 2]{ values: [2]u32{ 1u32, 2u32 } }
}
