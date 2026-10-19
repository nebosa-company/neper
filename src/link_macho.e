// The macOS image, aarch64 and x86-64: a Mach-O executable dyld loads, with libSystem linked and no
// imports used, the runtime (runtime_macos_a64.s) reaching the kernel by BSD system call.
// The kernel kills an arm64 executable with no dyld (D5166). The header page holds the
// load commands -- __PAGEZERO, __TEXT, __DATA when there are globals, __LINKEDIT, LC_MAIN
// naming the runtime's entry, the dylinker and libSystem, empty symbol tables and chained
// fixups, LC_BUILD_VERSION and LC_CODE_SIGNATURE -- the
// code follows on the next 16 KB page, then the globals on one of their own, then the ad-hoc
// signature (a SHA-256 CodeDirectory over every page before it) Apple Silicon refuses to run
// an executable without. Nothing needs the SDK or Apple's linker, so any host writes it.
// A program with an `@import` needs libSystem and dyld's bind opcodes, which this writer
// does not emit yet; nor does it carry DWARF.
use check
use codegen_x64
use emit_x64
use emit_a64
use link_elf
use link_elf_a64
use nir
use runtime_macos_a64
use runtime_macos_x64
use e.crypto.hash as crypto_hash

error InvalidImage
// The program reaches an `@import`, which needs dyld and libSystem.
error NeedsLoader
// A call to a runtime function the macOS runtime does not define.
error MissingRuntime

const MACHO_BASE: usize = 4294967296usize
const MACHO_PAGE: usize = 16384usize
const MACHO_HASH_PAGE: usize = 4096usize

fn big_u32(output: *emit_x64.Buffer, value: usize) -> err {
    try emit_x64.byte(output, (value >> 24usize) & 255usize)
    try emit_x64.byte(output, (value >> 16usize) & 255usize)
    try emit_x64.byte(output, (value >> 8usize) & 255usize)
    ret emit_x64.byte(output, value & 255usize)
}

fn name16(output: *emit_x64.Buffer, name: str) -> err {
    ret padded_name(output, name, 16usize)
}

fn padded_name(output: *emit_x64.Buffer, name: str, size: usize) -> err {
    var at = 0usize
    while at < size {
        if at < name.len { try emit_x64.byte(output, usize(name[at])) } else { try emit_x64.byte(output, 0usize) }
        at += 1usize
    }
    ret ok
}

fn segment(output: *emit_x64.Buffer, name: str, address: usize, size: usize, file_offset: usize, file_size: usize, protection: usize) -> err {
    try emit_x64.little_u32(output, 25usize)
    try emit_x64.little_u32(output, 72usize)
    try name16(output, name)
    try emit_x64.little_u64(output, address)
    try emit_x64.little_u64(output, size)
    try emit_x64.little_u64(output, file_offset)
    try emit_x64.little_u64(output, file_size)
    try emit_x64.little_u32(output, protection)
    try emit_x64.little_u32(output, protection)
    try emit_x64.little_u32(output, 0usize)
    ret emit_x64.little_u32(output, 0usize)
}

// The two runtimes' generated tables and the two instruction sets' patches, by the image's
// architecture.
fn runtime_symbol(x64: bool, name: str) -> (usize, bool) {
    if x64 {
        let (offset, found) = runtime_macos_x64.symbol_offset(name)
        ret (offset, found)
    }
    let (arm_offset, arm_found) = runtime_macos_a64.symbol_offset(name)
    ret (arm_offset, arm_found)
}

fn runtime_end(x64: bool, name: str) -> (usize, bool) {
    if x64 {
        let (end, found) = runtime_macos_x64.symbol_end(name)
        ret (end, found)
    }
    let (arm_end, arm_found) = runtime_macos_a64.symbol_end(name)
    ret (arm_end, arm_found)
}

fn runtime_append(x64: bool, output: *emit_x64.Buffer, limit: usize) -> err {
    if x64 { ret runtime_macos_x64.append(output, limit) }
    ret runtime_macos_a64.append(output, limit)
}

// Where a call's displacement sits in its instruction: x86-64's `call rel32` has the opcode
// byte first.
fn call_field(x64: bool) -> usize {
    if x64 { ret 1usize }
    ret 0usize
}

// A branch, call or address form at file offset `site` pointed at the file offset `destination`.
fn patch_branch(x64: bool, output: *emit_x64.Buffer, site: usize, destination: usize) -> err {
    if x64 { ret emit_x64.patch_relative32(output, site, destination) }
    ret emit_a64.patch_relative(output, site, destination)
}

// A reference at `site` to the virtual address `destination`: an ADRP pair or a rip-relative
// displacement from the end of the field.
fn patch_data(x64: bool, output: *emit_x64.Buffer, site: usize, destination: usize) -> err {
    if x64 {
        let next_address = MACHO_BASE + site + 4usize
        if destination < next_address { ret InvalidImage }
        ret emit_x64.patch_little_u32(output, site, destination - next_address)
    }
    ret emit_a64.patch_page(output, site, MACHO_BASE + site, destination)
}

fn runtime_limit(x64: bool, builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) -> (usize, err) {
    let (limit, has_start) = runtime_end(x64, "neper_start_arena")
    if !has_start { ret (0usize, InvalidImage) }
    var most = limit
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && !relocations[at].resolved {
            let reference_index = relocations[at].function_ref
            if reference_index >= builder.function_ref_count { ret (0usize, InvalidImage) }
            let (end, found) = runtime_end(x64, builder.function_refs[reference_index].name)
            if found && end > most { most = end }
        }
        at += 1usize
    }
    ret (most, ok)
}

// The code, the runtime and the symbol table from `code_offset` (a page), the main call and
// every relocation but a global's patched. `entry_address` gets the runtime's entry.
fn place_code(x64: bool, builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, table_at: usize, code_offset: usize, data_address: usize, output: *emit_x64.Buffer, entry_address: *usize) -> err {
    let (main_index, main_error) = link_elf.find_main(builder)
    if main_error != ok { ret main_error }
    try link_elf.pad_to(output, code_offset)
    let machine_start = output.count
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    try link_elf.pad_to(output, link_elf.align_up_to(output.count, 4usize))
    let runtime_start = output.count
    let (limit, limit_error) = runtime_limit(x64, builder, relocations, relocation_count)
    if limit_error != ok { ret limit_error }
    try runtime_append(x64, output, limit)
    var table_file = output.count
    if table_at < machine.count {
        try link_elf.pad_to(output, link_elf.align_up_to(output.count, 8usize))
        table_file = output.count
        try emit_x64.append_bytes(output, machine.bytes[table_at..machine.count])
        try codegen_x64.rebase_symbol_table(output, table_file, MACHO_BASE + machine_start)
    }
    let (entry, has_entry) = runtime_symbol(x64, "neper_start")
    let (main_call, has_main_call) = runtime_symbol(x64, "neper_start_main")
    let (arena_literal, has_arena_literal) = runtime_symbol(x64, "neper_start_arena")
    if !has_entry || !has_main_call || !has_arena_literal { ret InvalidImage }
    *entry_address = MACHO_BASE + runtime_start + entry
    try patch_branch(x64, output, runtime_start + main_call + call_field(x64), machine_start + function_offsets[main_index])
    if builder.arena_bytes != 0usize { try link_elf.patch_little_u64(output, runtime_start + arena_literal, builder.arena_bytes) }
    // The argument slot's distance from its own literal, both as file offsets.
    let (args_literal, has_args_literal) = runtime_symbol(x64, "neper_start_args")
    if !has_args_literal { ret InvalidImage }
    try link_elf.patch_little_u64(output, runtime_start + args_literal, (data_address -% MACHO_BASE) -% (runtime_start + args_literal))
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.global {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidImage }
            let site = machine_start + relocation.displacement_at
            if codegen_x64.is_symbols_reference(builder, relocation) {
                try patch_branch(x64, output, site, table_file)
                relocations[relocation_at].resolved = true
            } else {
                if !relocation.resolved {
                    let (library, slot_entry, is_import) = nir.import_slot_of(builder, relocation.function_ref)
                    if is_import {
                        let flat = nir.import_flat_index(builder, library, slot_entry)
                        try patch_data(x64, output, site, data_address + 16usize + flat * 8usize)
                        relocations[relocation_at].resolved = true
                        relocation_at += 1usize
                        continue
                    }
                    let (runtime_offset, found_runtime) = runtime_symbol(x64, builder.function_refs[relocation.function_ref].name)
                    if !found_runtime { ret MissingRuntime }
                    try patch_branch(x64, output, site, runtime_start + runtime_offset)
                    relocations[relocation_at].resolved = true
                }
            }
        }
        relocation_at += 1usize
    }
    ret ok
}

// Each module-scope `var`'s ADRP pair pointed into the area at `area_address`.
fn place_globals(x64: bool, builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize, machine_start: usize, area_address: usize, output: *emit_x64.Buffer) -> err {
    var global_at = 0usize
    while global_at < relocation_count {
        if relocations[global_at].global {
            let reference_index = relocations[global_at].function_ref
            if reference_index >= builder.global_count { ret InvalidImage }
            let site = machine_start + relocations[global_at].displacement_at
            try patch_data(x64, output, site, area_address + nir.global_area_offset(builder, reference_index))
            relocations[global_at].resolved = true
        }
        global_at += 1usize
    }
    ret ok
}

fn identifier() -> str { ret "a.out" }

// The CodeDirectory's size for a file of `limit` bytes before the signature.
fn directory_size(limit: usize) -> usize {
    let pages = (limit + MACHO_HASH_PAGE - 1usize) / MACHO_HASH_PAGE
    ret 88usize + identifier().len + 1usize + pages * 32usize
}

// The ad-hoc signature for the `limit` bytes already in `output` (big-endian throughout):
// a SuperBlob of one CodeDirectory, SHA-256 per 4 KB page, flagged as the main binary
// over the text segment `text_size` long.
fn append_signature(output: *emit_x64.Buffer, limit: usize, text_size: usize) -> err {
    let directory = directory_size(limit)
    let pages = (limit + MACHO_HASH_PAGE - 1usize) / MACHO_HASH_PAGE
    let identifier_offset = 88usize
    let hash_offset = identifier_offset + identifier().len + 1usize
    try big_u32(output, 4208856256usize)
    try big_u32(output, 20usize + directory)
    try big_u32(output, 1usize)
    try big_u32(output, 0usize)
    try big_u32(output, 20usize)
    try big_u32(output, 4208856066usize)
    try big_u32(output, directory)
    // Version 2.4 (the exec-segment fields), flags: ad hoc.
    try big_u32(output, 132096usize)
    try big_u32(output, 2usize)
    try big_u32(output, hash_offset)
    try big_u32(output, identifier_offset)
    try big_u32(output, 0usize)
    try big_u32(output, pages)
    try big_u32(output, limit)
    // Hash size 32, SHA-256, no platform, 4 KB pages; then spare, scatter, team, spare, the
    // unused 64-bit limit, and the executable segment: its base, its size, the main-binary flag.
    try emit_x64.byte(output, 32usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 12usize)
    var zero_words = 0usize
    while zero_words < 8usize {
        try big_u32(output, 0usize)
        zero_words += 1usize
    }
    try big_u32(output, 0usize)
    try big_u32(output, text_size)
    try big_u32(output, 0usize)
    try big_u32(output, 1usize)
    var name_at = 0usize
    while name_at < identifier().len {
        try emit_x64.byte(output, usize(identifier()[name_at]))
        name_at += 1usize
    }
    try emit_x64.byte(output, 0usize)
    var page = 0usize
    while page < pages {
        let start = page * MACHO_HASH_PAGE
        var end = start + MACHO_HASH_PAGE
        if end > limit { end = limit }
        let digest = crypto_hash.sha256(output.bytes[start..end])
        var at = 0usize
        while at < 32usize {
            try emit_x64.byte(output, usize(digest[at]))
            at += 1usize
        }
        page += 1usize
    }
    ret ok
}

fn is_system(name: str) -> bool {
    ret check.same(name, "c") || check.same(name, "System") || check.same(name, "libSystem") || check.same(name, "libSystem.B.dylib")
}

// The install name dyld is told to load: libSystem for its aliases, an absolute path as
// written, and any other `LIB` as /usr/lib/lib<LIB>.dylib.
fn dylib_prefix(name: str) -> str {
    if is_system(name) { ret "/usr/lib/libSystem.B.dylib" }
    if name.len != 0usize && name[0usize] == 47u8 { ret "" }
    ret "/usr/lib/lib"
}

fn dylib_suffix(name: str) -> str {
    if is_system(name) || (name.len != 0usize && name[0usize] == 47u8) { ret "" }
    ret ".dylib"
}

fn dylib_name(name: str) -> str {
    if is_system(name) { ret "" }
    ret name
}

fn dylib_command_size(name: str) -> usize {
    ret link_elf.align_up_to(24usize + dylib_prefix(name).len + dylib_name(name).len + dylib_suffix(name).len + 1usize, 8usize)
}

fn dylib_command(output: *emit_x64.Buffer, name: str) -> err {
    let size = dylib_command_size(name)
    try emit_x64.little_u32(output, 12usize)
    try emit_x64.little_u32(output, size)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, 65536usize)
    try emit_x64.little_u32(output, 65536usize)
    try link_elf.append_text(output, dylib_prefix(name))
    try link_elf.append_text(output, dylib_name(name))
    try link_elf.append_text(output, dylib_suffix(name))
    var at = 24usize + dylib_prefix(name).len + dylib_name(name).len + dylib_suffix(name).len
    while at < size {
        try emit_x64.byte(output, 0usize)
        at += 1usize
    }
    ret ok
}

// libSystem is dylib 1 whether or not anything imports from it; each other library
// follows in the order the imports name them.
fn library_ordinal(builder: *nir.Builder, library: usize) -> usize {
    if is_system(nir.import_library_name(builder, library)) { ret 1usize }
    var ordinal = 2usize
    var at = 0usize
    while at < library {
        if !is_system(nir.import_library_name(builder, at)) { ordinal += 1usize }
        at += 1usize
    }
    ret ordinal
}

fn extra_library_count(builder: *nir.Builder) -> usize {
    var count = 0usize
    var at = 0usize
    while at < nir.import_library_count(builder) {
        if !is_system(nir.import_library_name(builder, at)) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn extra_libraries_size(builder: *nir.Builder) -> usize {
    var size = 0usize
    var at = 0usize
    while at < nir.import_library_count(builder) {
        let name = nir.import_library_name(builder, at)
        if !is_system(name) { size += dylib_command_size(name) }
        at += 1usize
    }
    ret size
}

// The symbols' names, a NUL first so offset 0 is the empty name, each with the underscore
// Mach-O gives a C symbol.
fn symbols_size(builder: *nir.Builder) -> usize {
    var size = 1usize
    var library = 0usize
    while library < nir.import_library_count(builder) {
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            size += nir.import_symbol_name(builder, library, entry).len + 2usize
            entry += 1usize
        }
        library += 1usize
    }
    ret size
}

fn symbol_name_offset(builder: *nir.Builder, library: usize, entry: usize) -> usize {
    var offset = 1usize
    var at_library = 0usize
    while at_library <= library {
        var limit = nir.import_symbol_count(builder, at_library)
        if at_library == library { limit = entry }
        var at = 0usize
        while at < limit {
            offset += nir.import_symbol_name(builder, at_library, at).len + 2usize
            at += 1usize
        }
        at_library += 1usize
    }
    ret offset
}

fn fixups_size(builder: *nir.Builder, segment_count: usize, data_size: usize, imports: usize) -> usize {
    let pages = (data_size + MACHO_PAGE - 1usize) / MACHO_PAGE
    let segment_starts = link_elf.align_up_to(32usize + 4usize + 4usize * segment_count, 8usize)
    var segment_size = 0usize
    if imports != 0usize { segment_size = 22usize + 2usize * pages }
    let imports_offset = link_elf.align_up_to(segment_starts + segment_size, 8usize)
    var strings = 0usize
    if imports != 0usize { strings = symbols_size(builder) }
    ret link_elf.align_up_to(imports_offset + 4usize * imports + strings, 8usize)
}

// The chained-fixups blob (dyld_chained_fixups_header) at file offset `base`: one chain
// over the import slots at the start of __DATA, each a DYLD_CHAINED_PTR_64 bind to its
// import, the imports naming their dylib by ordinal and their symbol by offset into the
// string table.
fn append_fixups(builder: *nir.Builder, output: *emit_x64.Buffer, base: usize, segment_count: usize, data_index: usize, data_offset: usize, data_size: usize, imports: usize) -> err {
    let pages = (data_size + MACHO_PAGE - 1usize) / MACHO_PAGE
    let starts_offset = 32usize
    let segment_starts = link_elf.align_up_to(starts_offset + 4usize + 4usize * segment_count, 8usize)
    var segment_size = 0usize
    if imports != 0usize { segment_size = 22usize + 2usize * pages }
    let imports_offset = link_elf.align_up_to(segment_starts + segment_size, 8usize)
    let symbols_offset = imports_offset + 4usize * imports
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, starts_offset)
    try emit_x64.little_u32(output, imports_offset)
    try emit_x64.little_u32(output, symbols_offset)
    try emit_x64.little_u32(output, imports)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 0usize)
    try link_elf.pad_to(output, base + starts_offset)
    try emit_x64.little_u32(output, segment_count)
    var segment_at = 0usize
    while segment_at < segment_count {
        if imports != 0usize && segment_at == data_index { try emit_x64.little_u32(output, segment_starts - starts_offset) } else { try emit_x64.little_u32(output, 0usize) }
        segment_at += 1usize
    }
    if imports != 0usize {
        try link_elf.pad_to(output, base + segment_starts)
        try emit_x64.little_u32(output, segment_size)
        try link_elf.little_u16(output, MACHO_PAGE)
        // DYLD_CHAINED_PTR_64.
        try link_elf.little_u16(output, 2usize)
        try emit_x64.little_u64(output, data_offset)
        try emit_x64.little_u32(output, 0usize)
        try link_elf.little_u16(output, pages)
        var page = 0usize
        while page < pages {
            if page == 0usize { try link_elf.little_u16(output, 16usize) } else { try link_elf.little_u16(output, 65535usize) }
            page += 1usize
        }
        try link_elf.pad_to(output, base + imports_offset)
        var library = 0usize
        while library < nir.import_library_count(builder) {
            var entry = 0usize
            while entry < nir.import_symbol_count(builder, library) {
                try emit_x64.little_u32(output, library_ordinal(builder, library) | (symbol_name_offset(builder, library, entry) << 9usize))
                entry += 1usize
            }
            library += 1usize
        }
        try emit_x64.byte(output, 0usize)
        library = 0usize
        while library < nir.import_library_count(builder) {
            var entry = 0usize
            while entry < nir.import_symbol_count(builder, library) {
                try emit_x64.byte(output, 95usize)
                try link_elf.append_text(output, nir.import_symbol_name(builder, library, entry))
                try emit_x64.byte(output, 0usize)
                entry += 1usize
            }
            library += 1usize
        }
    }
    ret ok
}

// The import slots, one chained bind each: the import's index, the distance in 4-byte
// strides to the next slot, and the bind bit.
fn append_slots(output: *emit_x64.Buffer, imports: usize) -> err {
    var slot = 0usize
    while slot < imports {
        var next = 2usize
        if slot + 1usize == imports { next = 0usize }
        try emit_x64.little_u32(output, slot)
        try emit_x64.little_u32(output, (next << 19usize) | 2147483648usize)
        slot += 1usize
    }
    ret ok
}

fn write(x64: bool, builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len || table_at > machine.count { ret InvalidImage }
    codegen_x64.mark_live_globals(builder, relocations, relocation_count)
    let imports = nir.import_symbol_total(builder)
    if imports > 2048usize { ret InvalidImage }
    let has_globals = nir.live_global_count(builder) != 0usize
    let has_data = true
    // __PAGEZERO, __TEXT, __DATA when there are slots or globals, __LINKEDIT, then LC_MAIN,
    // LC_LOAD_DYLINKER, LC_LOAD_DYLIB for libSystem and for each other library, LC_SYMTAB,
    // LC_DYSYMTAB, the chained fixups, LC_BUILD_VERSION and LC_CODE_SIGNATURE.
    var segment_count = 3usize
    if has_data { segment_count = 4usize }
    let command_count = segment_count + 8usize + extra_library_count(builder)
    let commands_size = 72usize * segment_count + 272usize + extra_libraries_size(builder)
    // The header and its commands fill the first page; the code starts on the second.
    let code_offset = MACHO_PAGE
    var entry_address = 0usize
    // The code is placed first into the output only to measure it, then again once the
    // slots' addresses are known; the header is written over the page left for it.
    try link_elf.pad_to(output, code_offset)
    try place_code(x64, builder, machine, function_offsets, relocations, relocation_count, table_at, code_offset, MACHO_BASE + 268435456usize, output, &entry_address)
    let text_end = output.count
    let text_size = link_elf.align_up_to(text_end, MACHO_PAGE)
    let data_offset = text_size
    var data_end = text_size
    if has_data {
        // The slots first, the globals after them.
        let globals_offset = link_elf.align_up_to(data_offset + 16usize + imports * 8usize, 16usize)
        var data_bytes = globals_offset - data_offset
        if has_globals { data_bytes += nir.global_area_size(builder) }
        data_end = data_offset + link_elf.align_up_to(data_bytes, MACHO_PAGE)
        output.count = code_offset
        link_elf_a64.clear_resolved_imports(builder, relocations, relocation_count)
        try place_code(x64, builder, machine, function_offsets, relocations, relocation_count, table_at, code_offset, MACHO_BASE + data_offset, output, &entry_address)
        if output.count != text_end { ret InvalidImage }
        try link_elf.pad_to(output, data_offset)
        try link_elf.pad_to(output, data_offset + 16usize)
        try append_slots(output, imports)
        try link_elf.pad_to(output, globals_offset)
        if has_globals {
            try link_elf.append_globals(builder, output, globals_offset)
            try link_elf.pad_to(output, globals_offset + nir.global_area_size(builder))
            try place_globals(x64, builder, relocations, relocation_count, code_offset, MACHO_BASE + globals_offset, output)
        }
        try link_elf.pad_to(output, data_end)
    } else {
        try link_elf.pad_to(output, text_size)
    }
    // __LINKEDIT, on the page after everything else: the chained-fixups blob dyld insists
    // on, an empty symbol table, then the signature, whose hash covers all before it.
    let linkedit_offset = data_end
    let data_index = 2usize
    let fixups_bytes = fixups_size(builder, segment_count, data_end - data_offset, imports)
    let strings_offset = linkedit_offset + fixups_bytes
    let signature_offset = link_elf.align_up_to(strings_offset + 8usize, 16usize)
    let directory = directory_size(signature_offset)
    let signature_size = 20usize + directory
    let linkedit_size = signature_offset - linkedit_offset + signature_size
    try append_fixups(builder, output, linkedit_offset, segment_count, data_index, data_offset, data_end - data_offset, imports)
    try link_elf.pad_to(output, linkedit_offset + fixups_bytes)
    try emit_x64.byte(output, 32usize)
    try link_elf.pad_to(output, signature_offset)
    let end = output.count
    output.count = 0usize
    try emit_x64.little_u32(output, 4277009103usize)
    // CPU_TYPE_X86_64 / CPU_SUBTYPE_X86_64_ALL, or CPU_TYPE_ARM64 / CPU_SUBTYPE_ARM64_ALL.
    if x64 {
        try emit_x64.little_u32(output, 16777223usize)
        try emit_x64.little_u32(output, 3usize)
    } else {
        try emit_x64.little_u32(output, 16777228usize)
        try emit_x64.little_u32(output, 0usize)
    }
    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, command_count)
    try emit_x64.little_u32(output, commands_size)
    // MH_NOUNDEFS | MH_DYLDLINK | MH_TWOLEVEL | MH_PIE.
    try emit_x64.little_u32(output, 2097285usize)
    try emit_x64.little_u32(output, 0usize)
    try segment(output, "__PAGEZERO", 0usize, MACHO_BASE, 0usize, 0usize, 0usize)
    try segment(output, "__TEXT", MACHO_BASE, text_size, 0usize, text_size, 5usize)
    if has_data { try segment(output, "__DATA", MACHO_BASE + data_offset, data_end - data_offset, data_offset, data_end - data_offset, 3usize) }
    try segment(output, "__LINKEDIT", MACHO_BASE + linkedit_offset, link_elf.align_up_to(linkedit_size, MACHO_PAGE), linkedit_offset, linkedit_size, 1usize)
    // LC_MAIN: the runtime's entry, as a file offset into __TEXT, called as main(argc, argv).
    try emit_x64.little_u32(output, 2147483688usize)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u64(output, entry_address - MACHO_BASE)
    try emit_x64.little_u64(output, 0usize)
    // LC_LOAD_DYLINKER, then the dylibs: dyld loads the image, and the kernel refuses an
    // arm64 executable with neither it nor libSystem.
    try emit_x64.little_u32(output, 14usize)
    try emit_x64.little_u32(output, 32usize)
    try emit_x64.little_u32(output, 12usize)
    try padded_name(output, "/usr/lib/dyld", 20usize)
    try dylib_command(output, "c")
    var library_at = 0usize
    while library_at < nir.import_library_count(builder) {
        let library_name = nir.import_library_name(builder, library_at)
        if !is_system(library_name) { try dylib_command(output, library_name) }
        library_at += 1usize
    }
    // LC_SYMTAB with no symbols and a string table of one space, LC_DYSYMTAB all zero.
    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u32(output, strings_offset)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, strings_offset)
    try emit_x64.little_u32(output, 8usize)
    try emit_x64.little_u32(output, 11usize)
    try emit_x64.little_u32(output, 80usize)
    var dysymtab_word = 0usize
    while dysymtab_word < 18usize {
        try emit_x64.little_u32(output, 0usize)
        dysymtab_word += 1usize
    }
    // LC_DYLD_CHAINED_FIXUPS.
    try emit_x64.little_u32(output, 2147483700usize)
    try emit_x64.little_u32(output, 16usize)
    try emit_x64.little_u32(output, linkedit_offset)
    try emit_x64.little_u32(output, fixups_bytes)
    // LC_BUILD_VERSION: macOS, minimum and SDK 11.0, no tools.
    try emit_x64.little_u32(output, 50usize)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 720896usize)
    try emit_x64.little_u32(output, 720896usize)
    try emit_x64.little_u32(output, 0usize)
    // LC_CODE_SIGNATURE.
    try emit_x64.little_u32(output, 29usize)
    try emit_x64.little_u32(output, 16usize)
    try emit_x64.little_u32(output, signature_offset)
    try emit_x64.little_u32(output, signature_size)
    if output.count > code_offset { ret InvalidImage }
    output.count = end
    ret append_signature(output, signature_offset, text_size)
}
