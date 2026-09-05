use e.mem

type Loaded = struct {
    count: usize,
}

fn value(input: Loaded) -> usize {
    ret input.count
}
