// Generated aarch64 macOS syscall runtime. Source: runtime_macos_a64.s.

use check
use emit_x64

// The first `limit` bytes of a chunk that starts `from` bytes into the runtime.
fn append_blob(output: *emit_x64.Buffer, bytes: str, from: usize, limit: usize) -> err {
    var at = 0usize
    while at < bytes.len && from + at < limit {
        try emit_x64.byte(output, usize(bytes[at]))
        at += 1usize
    }
    ret ok
}

// The runtime up to `limit` bytes: a prefix, because the source is ordered so that a
// function calls only what precedes it, and the linker cuts after the last one reached.
fn append(output: *emit_x64.Buffer, limit: usize) -> err {
    try append_blob(output, "\xcf\xfa\xed\xfe\x0c\x00\x00\x01\x00\x00\x00\x00\x01\x00\x00\x00\x04\x00\x00\x00\xc8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x19\x00\x00\x00\x48\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0usize, limit)
    try append_blob(output, "\x00\x00\x00\x00\x00\x00\x00\x00\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x32\x00\x00\x00\x18\x00\x00\x00\x01\x00\x00\x00\x00\x00\x0d\x00\x00\x00\x00\x00\x00\x00\x00\x00", 64usize, limit)
    try append_blob(output, "\x02\x00\x00\x00\x18\x00\x00\x00\xe8\x00\x00\x00\x00\x00\x00\x00\xe8\x00\x00\x00\x08\x00\x00\x00\x0b\x00\x00\x00\x50\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 128usize, limit)
    ret append_blob(output, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 192usize, limit)
}

fn size() -> usize { ret 240usize }

fn symbol_offset(name: str) -> (usize, bool) {
    if check.same(name, "neper_start") { ret (0usize, true) }
    if check.same(name, "neper_start_main") { ret (260usize, true) }
    if check.same(name, "neper_start_args") { ret (312usize, true) }
    if check.same(name, "neper_start_arena") { ret (320usize, true) }
    if check.same(name, "neper_mem_alloc") { ret (548usize, true) }
    if check.same(name, "neper_mem_alloc_fill") { ret (640usize, true) }
    if check.same(name, "neper_mem_mark") { ret (708usize, true) }
    if check.same(name, "neper_mem_reset") { ret (716usize, true) }
    if check.same(name, "neper_mem_reset_fill") { ret (824usize, true) }
    if check.same(name, "neper_mem_stats") { ret (868usize, true) }
    if check.same(name, "neper_os_stdout") { ret (888usize, true) }
    if check.same(name, "neper_os_stderr") { ret (900usize, true) }
    if check.same(name, "neper_os_exit") { ret (912usize, true) }
    if check.same(name, "neper_os_write") { ret (932usize, true) }
    if check.same(name, "neper_os_copy_bytes") { ret (1000usize, true) }
    if check.same(name, "neper_os_sha256_blocks") { ret (1072usize, true) }
    if check.same(name, "neper_os_crc32c_bytes") { ret (1080usize, true) }
    if check.same(name, "neper_trap") { ret (1320usize, true) }
    if check.same(name, "neper_os_read") { ret (1924usize, true) }
    if check.same(name, "neper_os_close") { ret (1992usize, true) }
    if check.same(name, "neper_os_open") { ret (2044usize, true) }
    if check.same(name, "neper_os_seek") { ret (2312usize, true) }
    if check.same(name, "neper_os_args") { ret (2368usize, true) }
    if check.same(name, "neper_os_clock") { ret (2396usize, true) }
    if check.same(name, "neper_os_syscall") { ret (2564usize, true) }
    if check.same(name, "neper_os_env_block") { ret (2656usize, true) }
    if check.same(name, "neper_os_spawn") { ret (2844usize, true) }
    if check.same(name, "neper_os_wait") { ret (3272usize, true) }
    if check.same(name, "neper_runtime_imports") { ret (3380usize, true) }
    if check.same(name, "neper_os_thread_create") { ret (3460usize, true) }
    if check.same(name, "neper_os_thread_join") { ret (3660usize, true) }
    if check.same(name, "neper_os_thread_detach") { ret (3720usize, true) }
    if check.same(name, "neper_os_wait_u32") { ret (3776usize, true) }
    if check.same(name, "neper_os_wake_one_u32") { ret (3920usize, true) }
    if check.same(name, "neper_os_wake_all_u32") { ret (3952usize, true) }
    if check.same(name, "neper_os_reserve") { ret (3984usize, true) }
    if check.same(name, "neper_os_commit") { ret (4052usize, true) }
    if check.same(name, "neper_hash_bytes") { ret (4096usize, true) }
    if check.same(name, "neper_os_aes_ctr") { ret (4568usize, true) }
    if check.same(name, "neper_os_ghash_blocks") { ret (4576usize, true) }
    if check.same(name, "neper_os_cpu_features") { ret (4584usize, true) }
    if check.same(name, "neper_os_aes_expand_key") { ret (4592usize, true) }
    ret (0usize, false)
}

// Where a function ends: the start of the next, or the end of the runtime for the last.
fn symbol_end(name: str) -> (usize, bool) {
    if check.same(name, "neper_start") { ret (260usize, true) }
    if check.same(name, "neper_start_main") { ret (312usize, true) }
    if check.same(name, "neper_start_args") { ret (320usize, true) }
    if check.same(name, "neper_start_arena") { ret (548usize, true) }
    if check.same(name, "neper_mem_alloc") { ret (640usize, true) }
    if check.same(name, "neper_mem_alloc_fill") { ret (708usize, true) }
    if check.same(name, "neper_mem_mark") { ret (716usize, true) }
    if check.same(name, "neper_mem_reset") { ret (824usize, true) }
    if check.same(name, "neper_mem_reset_fill") { ret (868usize, true) }
    if check.same(name, "neper_mem_stats") { ret (888usize, true) }
    if check.same(name, "neper_os_stdout") { ret (900usize, true) }
    if check.same(name, "neper_os_stderr") { ret (912usize, true) }
    if check.same(name, "neper_os_exit") { ret (932usize, true) }
    if check.same(name, "neper_os_write") { ret (1000usize, true) }
    if check.same(name, "neper_os_copy_bytes") { ret (1072usize, true) }
    if check.same(name, "neper_os_sha256_blocks") { ret (1080usize, true) }
    if check.same(name, "neper_os_crc32c_bytes") { ret (1320usize, true) }
    if check.same(name, "neper_trap") { ret (1924usize, true) }
    if check.same(name, "neper_os_read") { ret (1992usize, true) }
    if check.same(name, "neper_os_close") { ret (2044usize, true) }
    if check.same(name, "neper_os_open") { ret (2312usize, true) }
    if check.same(name, "neper_os_seek") { ret (2368usize, true) }
    if check.same(name, "neper_os_args") { ret (2396usize, true) }
    if check.same(name, "neper_os_clock") { ret (2564usize, true) }
    if check.same(name, "neper_os_syscall") { ret (2656usize, true) }
    if check.same(name, "neper_os_env_block") { ret (2844usize, true) }
    if check.same(name, "neper_os_spawn") { ret (3272usize, true) }
    if check.same(name, "neper_os_wait") { ret (3380usize, true) }
    if check.same(name, "neper_runtime_imports") { ret (3460usize, true) }
    if check.same(name, "neper_os_thread_create") { ret (3660usize, true) }
    if check.same(name, "neper_os_thread_join") { ret (3720usize, true) }
    if check.same(name, "neper_os_thread_detach") { ret (3776usize, true) }
    if check.same(name, "neper_os_wait_u32") { ret (3920usize, true) }
    if check.same(name, "neper_os_wake_one_u32") { ret (3952usize, true) }
    if check.same(name, "neper_os_wake_all_u32") { ret (3984usize, true) }
    if check.same(name, "neper_os_reserve") { ret (4052usize, true) }
    if check.same(name, "neper_os_commit") { ret (4096usize, true) }
    if check.same(name, "neper_hash_bytes") { ret (4568usize, true) }
    if check.same(name, "neper_os_aes_ctr") { ret (4576usize, true) }
    if check.same(name, "neper_os_ghash_blocks") { ret (4584usize, true) }
    if check.same(name, "neper_os_cpu_features") { ret (4592usize, true) }
    if check.same(name, "neper_os_aes_expand_key") { ret (240usize, true) }
    ret (0usize, false)
}
