// A file mapping by path: `e.os`'s `map_file` behind an open of the file, the file
// itself closed once the mapping exists, since the mapping keeps what it needs. The
// slice is exactly the bytes asked for; page alignment is the host's business inside
// `e.os`. `close` consumes the mapping and every slice taken from it.

use e.mem
use e.os

type Mapping = struct { raw: os.Mapping }
error Empty
error Invalid

fn open(a: *mem.Arena, path: str, writable: bool, offset: u64, len: usize) -> (Mapping, err) {
    if len == 0usize { ret (zero, Empty) }
    var flags: os.OpenFlags = zero
    flags.read = true
    flags.write = writable
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret (zero, open_error) }
    let (raw, map_error) = os.map_file(file, offset, len, writable)
    if map_error != ok {
        if os.close(file) != ok { ret (zero, map_error) }
        ret (zero, map_error)
    }
    let close_error = os.close(file)
    if close_error != ok {
        if os.mapping_close(raw) != ok { ret (zero, close_error) }
        ret (zero, close_error)
    }
    var m: Mapping = zero
    m.raw = raw
    ret (m, ok)
}

// The mapped bytes. This view is always read-only: a mapping opened read-only must
// not hand out a writable slice whose first write faults the process.
fn bytes(m: Mapping) -> []const u8 { ret os.mapping_bytes(m.raw) }

// A writable view of a mapping opened for writing. Read-only mappings return the
// host's `Unsupported` error rather than exposing their protected pages.
fn bytes_mut(m: Mapping) -> ([]u8, err) {
    let (view, view_error) = os.mapping_bytes_mut(m.raw)
    ret (view, view_error)
}

fn flush(m: Mapping) -> err { ret os.mapping_flush(m.raw) }

fn close(m: own Mapping) -> err { ret os.mapping_close(m.raw) }

// The planned name (algo 1623) for `open`, and `unmap` for `close`, so a caller
// reading the algorithm list finds the mapping under it.
fn map(a: *mem.Arena, path: str, writable: bool, offset: u64, len: usize) -> (Mapping, err) {
    let (m, open_error) = open(a, path, writable, offset, len)
    ret (m, open_error)
}

fn unmap(m: own Mapping) -> err { ret close(m) }
