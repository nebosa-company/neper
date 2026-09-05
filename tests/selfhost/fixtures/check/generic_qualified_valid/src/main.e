use dep as d

fn run(values: [3]u8, item: d.Item) -> usize {
    let explicit = d.identity[u32](1)
    let inferred = d.identity(explicit)
    let qualified_type = d.identity[d.Item](item)
    ret d.length(values)
}
