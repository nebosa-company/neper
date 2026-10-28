// Regression probes for promised-file descriptor capability checks, QueryGetData
// indexing and bounded CF_UNICODETEXT decoding.
use e.mem
use e.os
use e.os.shell

fn read_u32(bytes: []const u8, offset: usize) -> u32 {
    ret u32(bytes[offset]) | (u32(bytes[offset + 1usize]) << 8u32) | (u32(bytes[offset + 2usize]) << 16u32) | (u32(bytes[offset + 3usize]) << 24u32)
}

fn main(a: *mem.Arena) -> err {
    // An unterminated text HGLOBAL must be rejected within its allocation.
    let text_handle = shell.global_from_bytes("text")
    if text_handle == 0usize { os.exit(1i32) }
    let (text, text_error) = shell.content_of(a, .Text, "", text_handle)
    let released_text = shell.raw_global_free(text_handle)
    if text_error != shell.Invalid { os.exit(2i32) }

    // A promised name that cannot fit FILEDESCRIPTORW's 259 UTF-16 units is
    // rejected before drag_start reaches the OLE drag loop.
    var name_bytes: [260]u8 = zero
    var at = 0usize
    while at < name_bytes.len {
        name_bytes[at] = 97u8
        at += 1usize
    }
    let long_name: str = name_bytes[..]
    var items: [1]shell.Content = zero
    items[0usize] = shell.Content { kind: .Promise, mime: "", text: long_name, paths: zero, image: zero, bytes: "x" }
    let (cancelled, long_name_error) = shell.drag_start(a, items[..], false)
    if long_name_error != shell.Invalid { os.exit(3i32) }

    // The descriptor keeps the high 32 bits of a promised size as well as the low.
    var one: [1]u8 = zero
    var fake: mem.Arena = zero
    fake.base = &one[0usize]
    fake.cap = 4294967296usize
    let oversized = mem.view(&fake, 0usize, 4294967296usize)
    items[0usize] = shell.Content { kind: .Promise, mime: "", text: "full.bin", paths: zero, image: zero, bytes: oversized }
    let (descriptor_handle, descriptor_error) = shell.descriptor_block(a, items[..])
    if descriptor_error != ok || descriptor_handle == 0usize { os.exit(4i32) }
    let (descriptor, descriptor_locked) = shell.global_bytes(descriptor_handle)
    if !descriptor_locked || read_u32(descriptor, 68usize) != 1u32 || read_u32(descriptor, 72usize) != 0u32 {
        let unlocked = shell.raw_global_unlock(descriptor_handle)
        let released = shell.raw_global_free(descriptor_handle)
        os.exit(5i32)
    }
    let unlocked_descriptor = shell.raw_global_unlock(descriptor_handle)
    let released_descriptor = shell.raw_global_free(descriptor_handle)

    // The descriptor accepts only lindex -1; file contents require a nonnegative
    // promised-file index.
    if !shell.descriptor_query_valid(items[..], 0i32 - 1i32) { os.exit(6i32) }
    if shell.descriptor_query_valid(items[..], 0i32) { os.exit(7i32) }
    if !shell.contents_query_valid(items[..], 0i32) { os.exit(8i32) }
    if shell.contents_query_valid(items[..], 0i32 - 1i32) { os.exit(9i32) }
    if shell.contents_query_valid(items[..], 1i32) { os.exit(10i32) }
    ret ok
}
