// Generated x86-64 macOS syscall runtime. Source: runtime_macos_x64.s.

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
    try append_blob(output, "\xcf\xfa\xed\xfe\x07\x00\x00\x01\x03\x00\x00\x00\x01\x00\x00\x00\x04\x00\x00\x00\xc8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x19\x00\x00\x00\x48\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0usize, limit)
    try append_blob(output, "\x00\x00\x00\x00\x00\x00\x00\x00\xe8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x00\x00\x00\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x32\x00\x00\x00\x18\x00\x00\x00\x01\x00\x00\x00\x00\x00\x0d\x00\x00\x00\x00\x00\x00\x00\x00\x00", 64usize, limit)
    try append_blob(output, "\x02\x00\x00\x00\x18\x00\x00\x00\xe8\x00\x00\x00\x00\x00\x00\x00\xe8\x00\x00\x00\x08\x00\x00\x00\x0b\x00\x00\x00\x50\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 128usize, limit)
    ret append_blob(output, "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 192usize, limit)
}

fn size() -> usize { ret 240usize }

fn symbol_offset(name: str) -> (usize, bool) {
    if check.same(name, "neper_start") { ret (0usize, true) }
    if check.same(name, "neper_start_main") { ret (267usize, true) }
    if check.same(name, "neper_start_args") { ret (303usize, true) }
    if check.same(name, "neper_start_arena") { ret (311usize, true) }
    if check.same(name, "neper_mem_alloc") { ret (577usize, true) }
    if check.same(name, "neper_mem_alloc_fill") { ret (686usize, true) }
    if check.same(name, "neper_mem_mark") { ret (739usize, true) }
    if check.same(name, "neper_mem_reset") { ret (744usize, true) }
    if check.same(name, "neper_mem_reset_fill") { ret (840usize, true) }
    if check.same(name, "neper_mem_stats") { ret (880usize, true) }
    if check.same(name, "neper_os_stdout") { ret (896usize, true) }
    if check.same(name, "neper_os_stderr") { ret (904usize, true) }
    if check.same(name, "neper_os_exit") { ret (912usize, true) }
    if check.same(name, "neper_os_write") { ret (926usize, true) }
    if check.same(name, "neper_os_copy_bytes") { ret (977usize, true) }
    if check.same(name, "neper_os_sha256_blocks") { ret (1001usize, true) }
    if check.same(name, "neper_os_crc32c_bytes") { ret (2330usize, true) }
    if check.same(name, "neper_trap") { ret (2532usize, true) }
    if check.same(name, "neper_os_read") { ret (3504usize, true) }
    if check.same(name, "neper_os_close") { ret (3555usize, true) }
    if check.same(name, "neper_os_open") { ret (3595usize, true) }
    if check.same(name, "neper_os_args") { ret (3900usize, true) }
    if check.same(name, "neper_os_syscall") { ret (3936usize, true) }
    if check.same(name, "neper_runtime_imports") { ret (4014usize, true) }
    if check.same(name, "neper_os_clock") { ret (4090usize, true) }
    if check.same(name, "neper_os_seek") { ret (4226usize, true) }
    if check.same(name, "neper_os_env_block") { ret (4270usize, true) }
    if check.same(name, "neper_os_spawn") { ret (4472usize, true) }
    if check.same(name, "neper_os_wait") { ret (4899usize, true) }
    if check.same(name, "neper_os_thread_create") { ret (4993usize, true) }
    if check.same(name, "neper_os_thread_join") { ret (5189usize, true) }
    if check.same(name, "neper_os_thread_detach") { ret (5242usize, true) }
    if check.same(name, "neper_os_wait_u32") { ret (5293usize, true) }
    if check.same(name, "neper_os_wake_one_u32") { ret (5439usize, true) }
    if check.same(name, "neper_os_wake_all_u32") { ret (5462usize, true) }
    if check.same(name, "neper_os_reserve") { ret (5485usize, true) }
    if check.same(name, "neper_os_commit") { ret (5540usize, true) }
    if check.same(name, "neper_hash_bytes") { ret (5575usize, true) }
    if check.same(name, "neper_os_cpu_features") { ret (6154usize, true) }
    if check.same(name, "neper_os_aes_expand_key") { ret (6203usize, true) }
    if check.same(name, "neper_os_aes_ctr") { ret (6578usize, true) }
    if check.same(name, "neper_os_ghash_blocks") { ret (7082usize, true) }
    ret (0usize, false)
}

// Where a function ends: the start of the next, or the end of the runtime for the last.
fn symbol_end(name: str) -> (usize, bool) {
    if check.same(name, "neper_start") { ret (267usize, true) }
    if check.same(name, "neper_start_main") { ret (303usize, true) }
    if check.same(name, "neper_start_args") { ret (311usize, true) }
    if check.same(name, "neper_start_arena") { ret (577usize, true) }
    if check.same(name, "neper_mem_alloc") { ret (686usize, true) }
    if check.same(name, "neper_mem_alloc_fill") { ret (739usize, true) }
    if check.same(name, "neper_mem_mark") { ret (744usize, true) }
    if check.same(name, "neper_mem_reset") { ret (840usize, true) }
    if check.same(name, "neper_mem_reset_fill") { ret (880usize, true) }
    if check.same(name, "neper_mem_stats") { ret (896usize, true) }
    if check.same(name, "neper_os_stdout") { ret (904usize, true) }
    if check.same(name, "neper_os_stderr") { ret (912usize, true) }
    if check.same(name, "neper_os_exit") { ret (926usize, true) }
    if check.same(name, "neper_os_write") { ret (977usize, true) }
    if check.same(name, "neper_os_copy_bytes") { ret (1001usize, true) }
    if check.same(name, "neper_os_sha256_blocks") { ret (2330usize, true) }
    if check.same(name, "neper_os_crc32c_bytes") { ret (2532usize, true) }
    if check.same(name, "neper_trap") { ret (3504usize, true) }
    if check.same(name, "neper_os_read") { ret (3555usize, true) }
    if check.same(name, "neper_os_close") { ret (3595usize, true) }
    if check.same(name, "neper_os_open") { ret (3900usize, true) }
    if check.same(name, "neper_os_args") { ret (3936usize, true) }
    if check.same(name, "neper_os_syscall") { ret (4014usize, true) }
    if check.same(name, "neper_runtime_imports") { ret (4090usize, true) }
    if check.same(name, "neper_os_clock") { ret (4226usize, true) }
    if check.same(name, "neper_os_seek") { ret (4270usize, true) }
    if check.same(name, "neper_os_env_block") { ret (4472usize, true) }
    if check.same(name, "neper_os_spawn") { ret (4899usize, true) }
    if check.same(name, "neper_os_wait") { ret (4993usize, true) }
    if check.same(name, "neper_os_thread_create") { ret (5189usize, true) }
    if check.same(name, "neper_os_thread_join") { ret (5242usize, true) }
    if check.same(name, "neper_os_thread_detach") { ret (5293usize, true) }
    if check.same(name, "neper_os_wait_u32") { ret (5439usize, true) }
    if check.same(name, "neper_os_wake_one_u32") { ret (5462usize, true) }
    if check.same(name, "neper_os_wake_all_u32") { ret (5485usize, true) }
    if check.same(name, "neper_os_reserve") { ret (5540usize, true) }
    if check.same(name, "neper_os_commit") { ret (5575usize, true) }
    if check.same(name, "neper_hash_bytes") { ret (6154usize, true) }
    if check.same(name, "neper_os_cpu_features") { ret (6203usize, true) }
    if check.same(name, "neper_os_aes_expand_key") { ret (6578usize, true) }
    if check.same(name, "neper_os_aes_ctr") { ret (7082usize, true) }
    if check.same(name, "neper_os_ghash_blocks") { ret (240usize, true) }
    ret (0usize, false)
}
