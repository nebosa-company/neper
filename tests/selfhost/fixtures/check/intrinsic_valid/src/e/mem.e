type Arena = struct {
    base: *u8,
    cap: usize,
    off: usize,
}

// The rest of e.mem's fence (D821): a project that replaces e.mem replaces it for
// the toolchain's own modules too, so the stub carries every source-defined
// member a library may call.
fn arena_from(buf: []u8) -> Arena {
    ret Arena { base: &buf[0usize], cap: buf.len, off: 0usize }
}

fn copy[T: type](dst: []T, src: []const T) {
    var i = 0usize
    while i < src.len && i < dst.len {
        dst[i] = src[i]
        i += 1usize
    }
}

fn eq[T: type](x: []const T, y: []const T) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}
