// Core dumps and minidumps (#1645): parse a Linux ELF64 x86-64 core file or a Windows
// minidump from its bytes into one `Dump` -- the threads with their registers, the
// modules or mapped files, the crashing thread with its signal or exception code, and
// the memory regions `read_memory` resolves an address through -- and write a dump of a
// live process through the host (`write_minidump` over dbghelp on Windows, `write_core`
// over gdb's `gcore` on Linux; each answers `Unsupported` on the other host).
//
// The parsers only read `bytes`; the tables they answer are allocated in the arena and
// the names and memory are views into `bytes` (a minidump's UTF-16 names are converted
// into the arena), so a `Dump` lives as long as both. Every offset and count stored in
// the dump is checked before it is followed: `BadMagic` is neither format, `Truncated`
// a file that ends inside its header, program headers or stream directory,
// `OutOfBounds` a stored location or count that reaches past the file or its container,
// `Unsupported` a well-formed dump of another architecture or class.
//
// Core: PT_NOTE notes named CORE -- NT_PRSTATUS (one per thread: tid, current signal,
// the general registers), NT_PRPSINFO (pid, process name), NT_SIGINFO (signal, code,
// fault address), NT_FILE (mapped files) -- and PT_LOAD segments with file bytes as the
// memory. The first thread with a signal is the crashing one (the kernel writes it
// first). Minidump: ThreadListStream, ModuleListStream, MemoryListStream,
// Memory64ListStream, ExceptionStream (its thread, code, address and context),
// SystemInfoStream and MiscInfoStream (the pid); other streams are skipped.
//
// ponytail: x86-64 only -- other machines, 32-bit ELF and x86 minidumps are
// `Unsupported`; add a register layout per machine when one is needed.
// ponytail: no stack unwinding -- a thread answers its registers, not its frames; walking
// the dumped stack needs the modules' CFI (.eh_frame / .pdata), which nothing reads yet.

use e.mem
use e.text.utf8 as utf8
use e.debug.dump.host as host

type Kind = enum u8 { Core, Minidump }
type Registers = struct { rax: u64, rbx: u64, rcx: u64, rdx: u64, rsi: u64, rdi: u64, rbp: u64, rsp: u64, r8: u64, r9: u64, r10: u64, r11: u64, r12: u64, r13: u64, r14: u64, r15: u64, rip: u64, flags: u64 }
type Thread = struct { id: u64, signal: u32, registers: Registers }
// A loaded module (minidump) or a mapped file (core): `offset` is where in the file the
// mapping starts, zero for a module.
type Module = struct { base: u64, size: u64, offset: u64, name: str }
// `size` bytes of memory at `address`, stored at `offset` in the dump.
type Region = struct { address: u64, size: u64, offset: usize }
// `code` is the signal number (core) or the exception code (minidump); `signal_code` is
// the core's si_code. The system fields are the minidump's and zero for a core.
type Dump = struct { kind: Kind, bytes: []const u8, pid: u64, process_name: str, threads: []Thread, modules: []Module, regions: []Region, has_crash: bool, crash_thread: u64, code: u32, signal_code: i32, fault_address: u64, crash_registers: Registers, processors: u32, os_major: u32, os_minor: u32, os_build: u32 }
type Note = struct { kind: u32, core: bool, desc: []const u8 }

error BadMagic
error Truncated
error OutOfBounds
error Unsupported
error Unmapped

const NT_PRSTATUS: u32 = 1u32
const NT_PRPSINFO: u32 = 3u32
const NT_SIGINFO: u32 = 1397311305u32
const NT_FILE: u32 = 1179208773u32
const MDMP: u32 = 1347241037u32
const CONTEXT_MIN: usize = 256usize

// `n` little-endian bytes at `at`; the caller has checked they are there.
fn le(b: []const u8, at: usize, n: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < n {
        v = v | (u64(b[at + i]) << u32(8usize * i))
        i += 1usize
    }
    ret v
}

// Whether `n` bytes at `at` lie inside `b`, without overflowing.
fn fits(b: []const u8, at: u64, n: u64) -> bool {
    ret at <= u64(b.len) && n <= u64(b.len) - at
}

// The bytes up to the first NUL.
fn c_string(b: []const u8) -> str {
    var n = 0usize
    while n < b.len && b[n] != 0u8 { n += 1usize }
    ret b[..n]
}

// Reads the dump by its magic.
fn parse(a: *mem.Arena, bytes: []const u8) -> (Dump, err) {
    if bytes.len >= 4usize && le(bytes, 0usize, 4usize) == u64(MDMP) {
        let (md, md_error) = parse_minidump(a, bytes)
        ret (md, md_error)
    }
    let (core, core_error) = parse_core(a, bytes)
    ret (core, core_error)
}

// Copies `dst.len` bytes of the dumped process's memory at `address`. A read may span
// adjacent regions; any byte in no region refuses the whole read with `Unmapped` (what
// was copied before it is left in `dst`).
fn read_memory(d: *const Dump, address: u64, dst: []u8) -> err {
    if dst.len != 0usize && u64(dst.len - 1usize) > ~address { ret Unmapped }
    var done = 0usize
    while done < dst.len {
        let at = address + u64(done)
        var found = false
        var i = 0usize
        while i < d.regions.len && !found {
            let r = d.regions[i]
            if r.address <= at && at - r.address < r.size {
                found = true
                var take = usize(r.size - (at - r.address))
                if take > dst.len - done { take = dst.len - done }
                let from = r.offset + usize(at - r.address)
                var k = 0usize
                while k < take {
                    dst[done + k] = d.bytes[from + k]
                    k += 1usize
                }
                done += take
            }
            i += 1usize
        }
        if !found { ret Unmapped }
    }
    ret ok
}

// The thread with `id`, and whether there is one.
fn find_thread(d: *const Dump, id: u64) -> (Thread, bool) {
    var i = 0usize
    while i < d.threads.len {
        if d.threads[i].id == id { ret (d.threads[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

// ---- ELF core -------------------------------------------------------------------

// The note at `at` in `notes` and where the next one starts.
fn note_at(notes: []const u8, at: usize) -> (Note, usize, err) {
    if notes.len - at < 12usize { ret (zero, at, OutOfBounds) }
    let name_size = le(notes, at, 4usize)
    let desc_size = le(notes, at + 4usize, 4usize)
    let name_at = u64(at + 12usize)
    let desc_at = name_at + ((name_size + 3u64) & ~3u64)
    if !fits(notes, name_at, name_size) || !fits(notes, desc_at, desc_size) { ret (zero, at, OutOfBounds) }
    let name = notes[usize(name_at)..usize(name_at + name_size)]
    let is_core = name_size == 5u64 && name[0usize] == 67u8 && name[1usize] == 79u8 && name[2usize] == 82u8 && name[3usize] == 69u8
    let desc = notes[usize(desc_at)..usize(desc_at + desc_size)]
    var after = desc_at + ((desc_size + 3u64) & ~3u64)
    if after > u64(notes.len) { after = u64(notes.len) }
    ret (Note { kind: u32(le(notes, at + 8usize, 4usize)), core: is_core, desc: desc }, usize(after), ok)
}

// user_regs_struct at `at`: r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi
// orig_rax rip cs eflags rsp ...
fn core_registers(b: []const u8, at: usize) -> Registers {
    ret Registers { rax: le(b, at + 80usize, 8usize), rbx: le(b, at + 40usize, 8usize), rcx: le(b, at + 88usize, 8usize), rdx: le(b, at + 96usize, 8usize), rsi: le(b, at + 104usize, 8usize), rdi: le(b, at + 112usize, 8usize), rbp: le(b, at + 32usize, 8usize), rsp: le(b, at + 152usize, 8usize), r8: le(b, at + 72usize, 8usize), r9: le(b, at + 64usize, 8usize), r10: le(b, at + 56usize, 8usize), r11: le(b, at + 48usize, 8usize), r12: le(b, at + 24usize, 8usize), r13: le(b, at + 16usize, 8usize), r14: le(b, at + 8usize, 8usize), r15: le(b, at, 8usize), rip: le(b, at + 128usize, 8usize), flags: le(b, at + 144usize, 8usize) }
}

// One CORE note into `d`. Without `fill` it only counts the threads into `count`; with
// it, it fills `d.threads[count]` and everything else.
fn core_note(a: *mem.Arena, d: *Dump, n: Note, fill: bool, count: *usize) -> err {
    if n.kind == NT_PRSTATUS {
        if n.desc.len < 336usize { ret OutOfBounds }
        if fill {
            let signal = u32(le(n.desc, 12usize, 2usize))
            let id = le(n.desc, 32usize, 4usize)
            let registers = core_registers(n.desc, 112usize)
            d.threads[*count] = Thread { id: id, signal: signal, registers: registers }
            if signal != 0u32 && !d.has_crash {
                d.has_crash = true
                d.crash_thread = id
                d.code = signal
                d.crash_registers = registers
            }
        }
        *count = *count + 1usize
        ret ok
    }
    if !fill { ret ok }
    if n.kind == NT_PRPSINFO {
        if n.desc.len < 136usize { ret OutOfBounds }
        d.pid = le(n.desc, 24usize, 4usize)
        d.process_name = c_string(n.desc[40usize..56usize])
        ret ok
    }
    if n.kind == NT_SIGINFO {
        if n.desc.len < 24usize { ret OutOfBounds }
        d.code = u32(le(n.desc, 0usize, 4usize))
        d.signal_code = i32.trunc(le(n.desc, 8usize, 4usize))
        d.fault_address = le(n.desc, 16usize, 8usize)
        ret ok
    }
    if n.kind == NT_FILE {
        if n.desc.len < 16usize { ret OutOfBounds }
        let files = le(n.desc, 0usize, 8usize)
        let page = le(n.desc, 8usize, 8usize)
        if files > u64(n.desc.len - 16usize) / 24u64 { ret OutOfBounds }
        let (modules, modules_error) = mem.alloc[Module](a, usize(files))
        if modules_error != ok { ret modules_error }
        var name_at = 16usize + usize(files) * 24usize
        var i = 0usize
        while i < modules.len {
            let row = 16usize + i * 24usize
            let start = le(n.desc, row, 8usize)
            let end = le(n.desc, row + 8usize, 8usize)
            if end < start || name_at >= n.desc.len { ret OutOfBounds }
            let name = c_string(n.desc[name_at..])
            if name_at + name.len >= n.desc.len { ret OutOfBounds }
            modules[i] = Module { base: start, size: end - start, offset: le(n.desc, row + 16usize, 8usize) *% page, name: name }
            name_at += name.len + 1usize
            i += 1usize
        }
        d.modules = modules
    }
    ret ok
}

fn parse_core(a: *mem.Arena, bytes: []const u8) -> (Dump, err) {
    var d: Dump = zero
    d.kind = .Core
    d.bytes = bytes
    if bytes.len < 4usize || le(bytes, 0usize, 4usize) != 1179403647u64 { ret (d, BadMagic) }
    if bytes.len < 64usize { ret (d, Truncated) }
    if bytes[4usize] != 2u8 || bytes[5usize] != 1u8 || le(bytes, 16usize, 2usize) != 4u64 || le(bytes, 18usize, 2usize) != 62u64 { ret (d, Unsupported) }
    let ph_off = le(bytes, 32usize, 8usize)
    let ph_size = le(bytes, 54usize, 2usize)
    let ph_count = le(bytes, 56usize, 2usize)
    if ph_size < 56u64 { ret (d, OutOfBounds) }
    if !fits(bytes, ph_off, ph_size * ph_count) { ret (d, Truncated) }
    let (regions, regions_error) = mem.alloc[Region](a, usize(ph_count))
    if regions_error != ok { ret (d, regions_error) }
    var used = 0usize
    // Pass 0 validates every segment and counts the threads; pass 1 fills.
    var pass = 0usize
    while pass < 2usize {
        var count = 0usize
        var i = 0usize
        while i < usize(ph_count) {
            let ph = usize(ph_off) + i * usize(ph_size)
            let kind = le(bytes, ph, 4usize)
            let offset = le(bytes, ph + 8usize, 8usize)
            let size = le(bytes, ph + 32usize, 8usize)
            if (kind == 1u64 || kind == 4u64) && !fits(bytes, offset, size) { ret (d, OutOfBounds) }
            if kind == 1u64 && size != 0u64 && pass == 1usize {
                regions[used] = Region { address: le(bytes, ph + 16usize, 8usize), size: size, offset: usize(offset) }
                used += 1usize
            }
            if kind == 4u64 {
                let notes = bytes[usize(offset)..usize(offset + size)]
                var at = 0usize
                while at < notes.len {
                    let (n, after, note_error) = note_at(notes, at)
                    if note_error != ok { ret (d, note_error) }
                    if n.core {
                        let fill_error = core_note(a, &d, n, pass == 1usize, &count)
                        if fill_error != ok { ret (d, fill_error) }
                    }
                    at = after
                }
            }
            i += 1usize
        }
        if pass == 0usize {
            let (threads, threads_error) = mem.alloc[Thread](a, count)
            if threads_error != ok { ret (d, threads_error) }
            d.threads = threads
        }
        pass += 1usize
    }
    d.regions = regions[..used]
    ret (d, ok)
}

// ---- Minidump -------------------------------------------------------------------

// An x64 CONTEXT at `at` (checked to hold CONTEXT_MIN bytes).
fn context_registers(b: []const u8, at: usize) -> Registers {
    ret Registers { rax: le(b, at + 120usize, 8usize), rbx: le(b, at + 144usize, 8usize), rcx: le(b, at + 128usize, 8usize), rdx: le(b, at + 136usize, 8usize), rsi: le(b, at + 168usize, 8usize), rdi: le(b, at + 176usize, 8usize), rbp: le(b, at + 160usize, 8usize), rsp: le(b, at + 152usize, 8usize), r8: le(b, at + 184usize, 8usize), r9: le(b, at + 192usize, 8usize), r10: le(b, at + 200usize, 8usize), r11: le(b, at + 208usize, 8usize), r12: le(b, at + 216usize, 8usize), r13: le(b, at + 224usize, 8usize), r14: le(b, at + 232usize, 8usize), r15: le(b, at + 240usize, 8usize), rip: le(b, at + 248usize, 8usize), flags: le(b, at + 68usize, 4usize) }
}

// A MINIDUMP_STRING at `rva`, UTF-16 converted to UTF-8 in the arena.
fn minidump_string(a: *mem.Arena, b: []const u8, rva: u64) -> (str, err) {
    if !fits(b, rva, 4u64) { ret ("", OutOfBounds) }
    let length = le(b, usize(rva), 4usize)
    if !fits(b, rva + 4u64, length) { ret ("", OutOfBounds) }
    let (out, out_error) = mem.alloc[u8](a, usize(length / 2u64) * 3usize)
    if out_error != ok { ret ("", out_error) }
    let (n, decode_error) = utf8.decode_utf16(b[usize(rva) + 4usize..usize(rva + 4u64 + length)], false, out)
    if decode_error != ok { ret ("", decode_error) }
    ret (out[..n], ok)
}

fn parse_minidump(a: *mem.Arena, bytes: []const u8) -> (Dump, err) {
    var d: Dump = zero
    d.kind = .Minidump
    d.bytes = bytes
    if bytes.len < 4usize || le(bytes, 0usize, 4usize) != u64(MDMP) { ret (d, BadMagic) }
    if bytes.len < 32usize { ret (d, Truncated) }
    let streams = le(bytes, 8usize, 4usize)
    let directory = le(bytes, 12usize, 4usize)
    if !fits(bytes, directory, streams * 12u64) { ret (d, Truncated) }
    // First the bounds of every stream and the number of memory regions.
    var region_count = 0u64
    var s = 0usize
    while s < usize(streams) {
        let entry = usize(directory) + s * 12usize
        let kind = le(bytes, entry, 4usize)
        let size = le(bytes, entry + 4usize, 4usize)
        let rva = le(bytes, entry + 8usize, 4usize)
        if !fits(bytes, rva, size) { ret (d, OutOfBounds) }
        if kind == 5u64 && size >= 4u64 { region_count += le(bytes, usize(rva), 4usize) }
        if kind == 9u64 && size >= 16u64 { region_count += le(bytes, usize(rva), 8usize) }
        s += 1usize
    }
    if region_count > u64(bytes.len) / 16u64 { ret (d, OutOfBounds) }
    let (regions, regions_error) = mem.alloc[Region](a, usize(region_count))
    if regions_error != ok { ret (d, regions_error) }
    var used = 0usize
    s = 0usize
    while s < usize(streams) {
        let entry = usize(directory) + s * 12usize
        let kind = le(bytes, entry, 4usize)
        let size = usize(le(bytes, entry + 4usize, 4usize))
        let rva = usize(le(bytes, entry + 8usize, 4usize))
        let stream = bytes[rva..rva + size]
        let stream_error = minidump_stream(a, &d, kind, stream, regions, &used)
        if stream_error != ok { ret (d, stream_error) }
        s += 1usize
    }
    d.regions = regions[..used]
    if d.modules.len != 0usize { d.process_name = d.modules[0usize].name }
    ret (d, ok)
}

// One stream (`stream` is its bytes, checked inside the file) into `d`.
fn minidump_stream(a: *mem.Arena, d: *Dump, kind: u64, stream: []const u8, regions: []Region, used: *usize) -> err {
    let b = d.bytes
    if kind == 3u64 {
        if stream.len < 4usize { ret OutOfBounds }
        let count = le(stream, 0usize, 4usize)
        if count > u64(stream.len - 4usize) / 48u64 { ret OutOfBounds }
        let (threads, threads_error) = mem.alloc[Thread](a, usize(count))
        if threads_error != ok { ret threads_error }
        var i = 0usize
        while i < threads.len {
            let row = 4usize + i * 48usize
            let (registers, context_error) = context_at(b, stream, row + 40usize)
            if context_error != ok { ret context_error }
            threads[i] = Thread { id: le(stream, row, 4usize), signal: 0u32, registers: registers }
            i += 1usize
        }
        d.threads = threads
        ret ok
    }
    if kind == 4u64 {
        if stream.len < 4usize { ret OutOfBounds }
        let count = le(stream, 0usize, 4usize)
        if count > u64(stream.len - 4usize) / 108u64 { ret OutOfBounds }
        let (modules, modules_error) = mem.alloc[Module](a, usize(count))
        if modules_error != ok { ret modules_error }
        var i = 0usize
        while i < modules.len {
            let row = 4usize + i * 108usize
            let (name, name_error) = minidump_string(a, b, le(stream, row + 20usize, 4usize))
            if name_error != ok { ret name_error }
            modules[i] = Module { base: le(stream, row, 8usize), size: le(stream, row + 8usize, 4usize), offset: 0u64, name: name }
            i += 1usize
        }
        d.modules = modules
        ret ok
    }
    if kind == 5u64 {
        if stream.len < 4usize { ret OutOfBounds }
        let count = le(stream, 0usize, 4usize)
        if count > u64(stream.len - 4usize) / 16u64 { ret OutOfBounds }
        var i = 0usize
        while i < usize(count) {
            let row = 4usize + i * 16usize
            let size = le(stream, row + 8usize, 4usize)
            let rva = le(stream, row + 12usize, 4usize)
            if !fits(b, rva, size) { ret OutOfBounds }
            regions[*used] = Region { address: le(stream, row, 8usize), size: size, offset: usize(rva) }
            *used = *used + 1usize
            i += 1usize
        }
        ret ok
    }
    if kind == 9u64 {
        if stream.len < 16usize { ret OutOfBounds }
        let count = le(stream, 0usize, 8usize)
        if count > u64(stream.len - 16usize) / 16u64 { ret OutOfBounds }
        var at = le(stream, 8usize, 8usize)
        var i = 0usize
        while i < usize(count) {
            let row = 16usize + i * 16usize
            let size = le(stream, row + 8usize, 8usize)
            if !fits(b, at, size) { ret OutOfBounds }
            regions[*used] = Region { address: le(stream, row, 8usize), size: size, offset: usize(at) }
            *used = *used + 1usize
            at += size
            i += 1usize
        }
        ret ok
    }
    if kind == 6u64 {
        if stream.len < 168usize { ret OutOfBounds }
        let (registers, context_error) = context_at(b, stream, 160usize)
        if context_error != ok { ret context_error }
        d.has_crash = true
        d.crash_thread = le(stream, 0usize, 4usize)
        d.code = u32(le(stream, 8usize, 4usize))
        d.fault_address = le(stream, 24usize, 8usize)
        d.crash_registers = registers
        ret ok
    }
    if kind == 7u64 {
        if stream.len < 24usize { ret OutOfBounds }
        if le(stream, 0usize, 2usize) != 9u64 { ret Unsupported }
        d.processors = u32(le(stream, 6usize, 1usize))
        d.os_major = u32(le(stream, 8usize, 4usize))
        d.os_minor = u32(le(stream, 12usize, 4usize))
        d.os_build = u32(le(stream, 16usize, 4usize))
        ret ok
    }
    if kind == 15u64 && stream.len >= 12usize && (le(stream, 4usize, 4usize) & 1u64) == 1u64 {
        d.pid = le(stream, 8usize, 4usize)
    }
    ret ok
}

// A LOCATION_DESCRIPTOR (size, rva) at `at` in `stream` naming a context in the file `b`.
fn context_at(b: []const u8, stream: []const u8, at: usize) -> (Registers, err) {
    let size = le(stream, at, 4usize)
    let rva = le(stream, at + 4usize, 4usize)
    if size < u64(CONTEXT_MIN) || !fits(b, rva, size) { ret (zero, OutOfBounds) }
    ret (context_registers(b, usize(rva)), ok)
}

// ---- Writing ----------------------------------------------------------------------

// MINIDUMP_TYPE flags for `write_minidump`: zero is MiniDumpNormal (threads, modules,
// stacks); DATA_SEGMENTS adds every module's writable data, FULL_MEMORY all of it.
const DATA_SEGMENTS: u32 = 1u32
const FULL_MEMORY: u32 = 2u32

// Writes a minidump of process `pid` (zero: this process) to `path` through dbghelp's
// MiniDumpWriteDump. `Unsupported` off Windows.
fn write_minidump(a: *mem.Arena, pid: u32, path: str, flags: u32) -> err {
    let e = host.write_minidump(a, pid, path, flags)
    if e == host.Unsupported { ret Unsupported }
    ret e
}

// Writes an ELF core of process `pid` (zero: this process) to `path` with gdb's
// `gcore`. `Unsupported` off Linux, `host.NotFound` when gcore is not installed.
fn write_core(a: *mem.Arena, pid: u32, path: str) -> err {
    let e = host.write_core(a, pid, path)
    if e == host.Unsupported { ret Unsupported }
    ret e
}
