// `e.debug.dump`: a synthetic ELF core and a synthetic minidump built by ../vectors.py
// parse into every field the generator wrote -- threads and their registers, the crash
// (signal / exception, fault address, context), mapped files and modules (a UTF-16
// name converted to UTF-8), system info -- and `read_memory` returns the dumped bytes,
// across adjacent regions, and refuses a read past a region or outside all of them.
// Malformed input is refused: bad magic, truncated program headers and directory, a
// segment or stream pointing past the end, a count that overruns its stream. Then a
// real dump of this very process: a minidump through dbghelp on Windows, a core
// through gcore on Linux (skipped when gcore is not installed), read back for this
// thread, this executable and a module-scope pattern. Each check exits with its own code.

use e.debug.dump as dump
use e.debug.dump.host as host
use e.fs
use e.fs.mmap as mmap
use e.io
use e.mem
use e.os
use e.str
use vectors

var marker: [64]u8 = zero

fn pattern(address: u64) -> u8 {
    ret u8((address *% 31u64 +% 7u64) & 255u64)
}

fn pattern_ok(buf: []const u8, address: u64) -> bool {
    var i = 0usize
    while i < buf.len {
        if buf[i] != pattern(address + u64(i)) { ret false }
        i += 1usize
    }
    ret true
}

// `r` against row `row` of the generated register table.
fn registers_ok(r: dump.Registers, row: usize) -> bool {
    let table = vectors.expected_registers()
    var got: [18]u64 = zero
    got[0usize] = r.rax
    got[1usize] = r.rbx
    got[2usize] = r.rcx
    got[3usize] = r.rdx
    got[4usize] = r.rsi
    got[5usize] = r.rdi
    got[6usize] = r.rbp
    got[7usize] = r.rsp
    got[8usize] = r.r8
    got[9usize] = r.r9
    got[10usize] = r.r10
    got[11usize] = r.r11
    got[12usize] = r.r12
    got[13usize] = r.r13
    got[14usize] = r.r14
    got[15usize] = r.r15
    got[16usize] = r.rip
    got[17usize] = r.flags
    var i = 0usize
    while i < 18usize {
        if got[i] != table[row * 18usize + i] { ret false }
        i += 1usize
    }
    ret true
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn ends_with(s: str, tail: str) -> bool {
    ret s.len >= tail.len && same(s[s.len - tail.len..], tail)
}

// The file name after the last separator.
fn base_name(path: str) -> str {
    var start = 0usize
    var i = 0usize
    while i < path.len {
        if path[i] == 47u8 || path[i] == 92u8 { start = i + 1usize }
        i += 1usize
    }
    ret path[start..]
}

fn put32(b: []u8, at: usize, v: u32) {
    b[at] = u8(v & 255u32)
    b[at + 1usize] = u8((v >> 8u32) & 255u32)
    b[at + 2usize] = u8((v >> 16u32) & 255u32)
    b[at + 3usize] = u8(v >> 24u32)
}

fn get32(b: []const u8, at: usize) -> usize {
    ret usize(b[at]) | (usize(b[at + 1usize]) << 8u32) | (usize(b[at + 2usize]) << 16u32) | (usize(b[at + 3usize]) << 24u32)
}

fn copy(dst: []u8, src: []const u8) -> []u8 {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
    ret dst[..src.len]
}

fn check_core(a: *mem.Arena) -> i32 {
    let (d, parse_error) = dump.parse(a, vectors.core_bytes())
    if parse_error != ok || d.kind != .Core { ret 1i32 }
    if d.pid != vectors.CORE_PID || !same(d.process_name, "crasher") { ret 2i32 }
    if d.threads.len != 2usize || d.threads[0usize].id != vectors.CORE_TID0 || d.threads[1usize].id != vectors.CORE_TID1 { ret 3i32 }
    if d.threads[0usize].signal != vectors.CORE_SIGNAL || d.threads[1usize].signal != 0u32 { ret 3i32 }
    if !registers_ok(d.threads[0usize].registers, 0usize) || !registers_ok(d.threads[1usize].registers, 1usize) { ret 4i32 }
    if !d.has_crash || d.crash_thread != vectors.CORE_TID0 || d.code != vectors.CORE_SIGNAL || d.signal_code != vectors.CORE_SIGNAL_CODE || d.fault_address != vectors.CORE_FAULT { ret 5i32 }
    if !registers_ok(d.crash_registers, 0usize) { ret 5i32 }
    let (t, found) = dump.find_thread(&d, vectors.CORE_TID1)
    if !found || t.id != vectors.CORE_TID1 { ret 5i32 }
    let (_, missing) = dump.find_thread(&d, 1u64)
    if missing { ret 5i32 }
    if d.modules.len != 2usize || !same(d.modules[0usize].name, "/usr/bin/crasher") || !same(d.modules[1usize].name, "/usr/lib/libc.so.6") { ret 6i32 }
    if d.modules[0usize].base != vectors.CORE_FILE0_START || d.modules[0usize].size != vectors.CORE_FILE0_END - vectors.CORE_FILE0_START || d.modules[0usize].offset != 0u64 { ret 6i32 }
    if d.modules[1usize].base != vectors.CORE_FILE1_START || d.modules[1usize].size != vectors.CORE_FILE1_END - vectors.CORE_FILE1_START || d.modules[1usize].offset != vectors.CORE_FILE1_OFFSET { ret 6i32 }
    // Three loads with bytes; the empty one is no region.
    if d.regions.len != 3usize { ret 7i32 }
    var buf: [64]u8 = zero
    // 0x400000 + 0x30 spans the two adjacent loads.
    if dump.read_memory(&d, 4194304u64, buf[..48usize]) != ok || !pattern_ok(buf[..48usize], 4194304u64) { ret 8i32 }
    if dump.read_memory(&d, 2147287056u64, buf[..8usize]) != ok || !pattern_ok(buf[..8usize], 2147287056u64) { ret 8i32 }
    if dump.read_memory(&d, 2147287040u64, buf[..64usize]) != ok || !pattern_ok(buf[..64usize], 2147287040u64) { ret 8i32 }
    if dump.read_memory(&d, 12345u64, buf[..0usize]) != ok { ret 8i32 }
    // Past the file bytes of a load (memsz is larger), in the empty load, nowhere, past the top.
    if dump.read_memory(&d, 4194344u64, buf[..16usize]) != dump.Unmapped { ret 9i32 }
    if dump.read_memory(&d, 5242880u64, buf[..1usize]) != dump.Unmapped { ret 9i32 }
    if dump.read_memory(&d, 2147287104u64, buf[..1usize]) != dump.Unmapped { ret 9i32 }
    if dump.read_memory(&d, ~0u64, buf[..2usize]) != dump.Unmapped { ret 9i32 }
    ret 0i32
}

fn check_core_refusals(a: *mem.Arena) -> i32 {
    let core = vectors.core_bytes()
    var storage: [4096]u8 = zero
    let bad = copy(storage[..], core)
    bad[1usize] = 70u8
    let (_, magic_error) = dump.parse(a, bad)
    if magic_error != dump.BadMagic { ret 10i32 }
    let (_, empty_error) = dump.parse(a, core[..0usize])
    if empty_error != dump.BadMagic { ret 10i32 }
    let (_, header_error) = dump.parse(a, core[..40usize])
    if header_error != dump.Truncated { ret 11i32 }
    let (_, table_error) = dump.parse(a, core[..vectors.PH_OFF + vectors.PH_SIZE])
    if table_error != dump.Truncated { ret 11i32 }
    // A load whose bytes start past the end.
    let far = copy(storage[..], core)
    put32(far, vectors.PH_OFF + vectors.PH_SIZE + 8usize, 2147483647u32)
    let (_, segment_error) = dump.parse(a, far)
    if segment_error != dump.OutOfBounds { ret 12i32 }
    // A note whose descriptor size runs past its segment.
    let note = copy(storage[..], core)
    put32(note, get32(core, vectors.PH_OFF + 8usize) + 4usize, 65536u32)
    let (_, note_error) = dump.parse(a, note)
    if note_error != dump.OutOfBounds { ret 13i32 }
    // An executable, not a core; a 32-bit file.
    let exec = copy(storage[..], core)
    exec[16usize] = 2u8
    let (_, type_error) = dump.parse(a, exec)
    if type_error != dump.Unsupported { ret 14i32 }
    let narrow = copy(storage[..], core)
    narrow[4usize] = 1u8
    let (_, class_error) = dump.parse(a, narrow)
    if class_error != dump.Unsupported { ret 14i32 }
    ret 0i32
}

fn check_minidump(a: *mem.Arena) -> i32 {
    let (d, parse_error) = dump.parse(a, vectors.minidump_bytes())
    if parse_error != ok || d.kind != .Minidump { ret 20i32 }
    if d.pid != vectors.MD_PID { ret 21i32 }
    if d.threads.len != 2usize || d.threads[0usize].id != vectors.MD_TID0 || d.threads[1usize].id != vectors.MD_TID1 { ret 22i32 }
    if !registers_ok(d.threads[0usize].registers, 2usize) || !registers_ok(d.threads[1usize].registers, 3usize) { ret 23i32 }
    if !d.has_crash || d.crash_thread != vectors.MD_TID0 || d.code != vectors.MD_CODE || d.fault_address != vectors.MD_FAULT || !registers_ok(d.crash_registers, 4usize) { ret 24i32 }
    if d.modules.len != 2usize || d.modules[0usize].base != vectors.MD_MODULE0_BASE || d.modules[0usize].size != vectors.MD_MODULE0_SIZE || d.modules[1usize].base != vectors.MD_MODULE1_BASE || d.modules[1usize].size != vectors.MD_MODULE1_SIZE { ret 25i32 }
    if !same(d.modules[0usize].name, vectors.md_module0_name()) || !same(d.modules[1usize].name, vectors.md_module1_name()) || !same(d.process_name, vectors.md_module0_name()) { ret 26i32 }
    if d.processors != vectors.MD_PROCESSORS || d.os_major != vectors.MD_OS_MAJOR || d.os_minor != vectors.MD_OS_MINOR || d.os_build != vectors.MD_OS_BUILD { ret 27i32 }
    if d.regions.len != vectors.MD_REGIONS { ret 28i32 }
    var buf: [64]u8 = zero
    // The memory list's stack, then across the two adjacent memory64 ranges, then the third.
    if dump.read_memory(&d, 65536u64, buf[..64usize]) != ok || !pattern_ok(buf[..64usize], 65536u64) { ret 29i32 }
    if dump.read_memory(&d, 131080u64, buf[..16usize]) != ok || !pattern_ok(buf[..16usize], 131080u64) { ret 29i32 }
    if dump.read_memory(&d, 196608u64, buf[..8usize]) != ok || !pattern_ok(buf[..8usize], 196608u64) { ret 29i32 }
    // Partly past the third range, and outside every region.
    if dump.read_memory(&d, 196612u64, buf[..8usize]) != dump.Unmapped { ret 30i32 }
    if dump.read_memory(&d, 262144u64, buf[..1usize]) != dump.Unmapped { ret 30i32 }
    ret 0i32
}

fn check_minidump_refusals(a: *mem.Arena) -> i32 {
    let md = vectors.minidump_bytes()
    var storage: [8192]u8 = zero
    let bad = copy(storage[..], md)
    bad[0usize] = 78u8
    let (_, magic_error) = dump.parse(a, bad)
    if magic_error != dump.BadMagic { ret 40i32 }
    let (_, direct_error) = dump.parse_minidump(a, bad)
    if direct_error != dump.BadMagic { ret 40i32 }
    let (_, header_error) = dump.parse(a, md[..20usize])
    if header_error != dump.Truncated { ret 41i32 }
    let (_, directory_error) = dump.parse(a, md[..vectors.MD_DIR_RVA + 36usize])
    if directory_error != dump.Truncated { ret 41i32 }
    // The first stream's rva points past the end.
    let far = copy(storage[..], md)
    put32(far, vectors.MD_DIR_RVA + 8usize, 4294967040u32)
    let (_, stream_error) = dump.parse(a, far)
    if stream_error != dump.OutOfBounds { ret 42i32 }
    // The thread list claims more threads than it holds.
    let many = copy(storage[..], md)
    put32(many, get32(md, vectors.MD_DIR_RVA + 8usize), 1000u32)
    let (_, count_error) = dump.parse(a, many)
    if count_error != dump.OutOfBounds { ret 43i32 }
    ret 0i32
}

// A real dump of this process, read back. Windows: a minidump with data segments.
// Linux: a gcore core, skipped when gcore is not installed.
fn check_real(a: *mem.Arena) -> i32 {
    var i = 0usize
    while i < marker.len {
        marker[i] = u8((i * 37usize + 11usize) & 255usize)
        i += 1usize
    }
    let marker_at = u64(mem.address_of(&marker[0usize]))
    let (dir, dir_error) = fs.temp_dir(a)
    if dir_error != ok { ret 50i32 }
    let pid = host.process_id()
    let (b0, builder_error) = str.builder(a, dir.len + 64usize)
    if builder_error != ok { ret 50i32 }
    var b = b0
    if str.push(&b, dir) != ok || str.push(&b, "/neper_debug_dump_") != ok || str.push_u32(&b, pid) != ok || str.push(&b, ".dmp") != ok { ret 50i32 }
    let path = str.done(&b)
    var written = dump.write_minidump(a, 0u32, path, dump.DATA_SEGMENTS)
    if written == dump.Unsupported {
        written = dump.write_core(a, 0u32, path)
        if written == host.NotFound { ret 0i32 }
    }
    if written != ok { ret 51i32 }
    // Mapped, not read: a core holds the whole arena reservation (a gigabyte).
    let (info, stat_error) = os.stat(a, path)
    if stat_error != ok { ret 52i32 }
    let (mapping, map_error) = mmap.open(a, path, false, 0u64, usize(info.size))
    if map_error != ok { ret 52i32 }
    let code = check_real_bytes(a, mmap.bytes(mapping), pid, marker_at)
    if mmap.close(mapping) != ok || fs.remove_file(a, path) != ok { ret 52i32 }
    ret code
}

fn check_real_bytes(a: *mem.Arena, bytes: []const u8, pid: u32, marker_at: u64) -> i32 {
    let (d, parse_error) = dump.parse(a, bytes)
    if parse_error != ok { ret 53i32 }
    if d.pid != u64(pid) { ret 54i32 }
    let (_, found) = dump.find_thread(&d, u64(os.current_thread_id()))
    if !found { ret 55i32 }
    let (exe, exe_error) = os.executable_path(a)
    if exe_error != ok { ret 56i32 }
    var listed = false
    var m = 0usize
    while m < d.modules.len {
        let module = d.modules[m]
        if d.kind == .Minidump && module.base == host.image_base() && ends_with(module.name, base_name(exe)) { listed = true }
        if d.kind == .Core && same(module.name, exe) { listed = true }
        m += 1usize
    }
    if !listed { ret 57i32 }
    var buf: [64]u8 = zero
    if dump.read_memory(&d, marker_at, buf[..]) != ok { ret 58i32 }
    var i = 0usize
    while i < buf.len {
        if buf[i] != marker[i] { ret 59i32 }
        i += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_core(a)
    if code == 0i32 { code = check_core_refusals(a) }
    if code == 0i32 { code = check_minidump(a) }
    if code == 0i32 { code = check_minidump_refusals(a) }
    if code == 0i32 { code = check_real(a) }
    if code != 0i32 { os.exit(code) }
    try io.print("debug dump ok\n")
    ret ok
}
