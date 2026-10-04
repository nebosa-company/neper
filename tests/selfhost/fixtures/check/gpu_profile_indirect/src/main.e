use e.gpu

type Choice = struct { run: fn(u32) -> u32 }

fn through_field(choice: Choice, value: u32) -> u32 {
    ret choice.run(value)
}

@gpu(8)
fn fill(out: []u32) {
    let choice: Choice = zero
    out[usize(gpu.lid.x)] = through_field(choice, gpu.lid.x)
}
