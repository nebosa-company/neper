// M0 bootstrap surface. The bootstrap recognizes arena_from as a fixed intrinsic;
// this source fixes the names and shapes used by program entry.
type Arena = struct {
    base: *u8,
    cap: usize,
    off: usize,
}

fn arena_from(buf: []u8) -> Arena {
    ret Arena { base: &buf[0], cap: buf.len, off: 0usize }
}
