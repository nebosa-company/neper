use e.gpu

fn passthrough[T: type](value: T) -> T {
    gpu.barrier()
    ret value
}

fn host() -> u32 {
    ret passthrough(1u32)
}
