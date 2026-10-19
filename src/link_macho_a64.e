// The aarch64 macOS image: a Mach-O executable dyld loads, with libSystem linked and no
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
use nir
use runtime_macos_a64
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

fn runtime_limit(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) -> (usize, err) {
    let (limit, has_start) = runtime_macos_a64.symbol_end("neper_start_arena")
    if !has_start { ret (0usize, InvalidImage) }
    var most = limit
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && !relocations[at].resolved {
            let reference_index = relocations[at].function_ref
            if reference_index >= builder.function_ref_count { ret (0usize, InvalidImage) }
            let (end, found) = runtime_macos_a64.symbol_end(builder.function_refs[reference_index].name)
            if found && end > most { most = end }
        }
        at += 1usize
    }
    ret (most, ok)
}

// The code, the runtime and the symbol table from `code_offset` (a page), the main call and
// every relocation but a global's patched. `entry_address` gets the runtime's entry.
fn place_code(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, table_at: usize, code_offset: usize, output: *emit_x64.Buffer, entry_address: *usize) -> err {
    let (main_index, main_error) = link_elf.find_main(builder)
    if main_error != ok { ret main_error }
    try link_elf.pad_to(output, code_offset)
    let machine_start = output.count
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    try link_elf.pad_to(output, link_elf.align_up_to(output.count, 4usize))
    let runtime_start = output.count
    let (limit, limit_error) = runtime_limit(builder, relocations, relocation_count)
    if limit_error != ok { ret limit_error }
    try runtime_macos_a64.append(output, limit)
    var table_file = output.count
    if table_at < machine.count {
        try link_elf.pad_to(output, link_elf.align_up_to(output.count, 8usize))
        table_file = output.count
        try emit_x64.append_bytes(output, machine.bytes[table_at..machine.count])
        try codegen_x64.rebase_symbol_table(output, table_file, MACHO_BASE + machine_start)
    }
    let (entry, has_entry) = runtime_macos_a64.symbol_offset("neper_start")
    let (main_call, has_main_call) = runtime_macos_a64.symbol_offset("neper_start_main")
    let (arena_literal, has_arena_literal) = runtime_macos_a64.symbol_offset("neper_start_arena")
    if !has_entry || !has_main_call || !has_arena_literal { ret InvalidImage }
    *entry_address = MACHO_BASE + runtime_start + entry
    try emit_a64.patch_relative(output, runtime_start + main_call, machine_start + function_offsets[main_index])
    if builder.arena_bytes != 0usize { try link_elf.patch_little_u64(output, runtime_start + arena_literal, builder.arena_bytes) }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.global {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidImage }
            let site = machine_start + relocation.displacement_at
            if codegen_x64.is_symbols_reference(builder, relocation) {
                try emit_a64.patch_relative(output, site, table_file)
                relocations[relocation_at].resolved = true
            } else {
                if !relocation.resolved {
                    let (library, slot_entry, is_import) = nir.import_slot_of(builder, relocation.function_ref)
                    if is_import { ret NeedsLoader }
                    let (runtime_offset, found_runtime) = runtime_macos_a64.symbol_offset(builder.function_refs[relocation.function_ref].name)
                    if !found_runtime { ret MissingRuntime }
                    try emit_a64.patch_relative(output, site, runtime_start + runtime_offset)
                    relocations[relocation_at].resolved = true
                }
            }
        }
        relocation_at += 1usize
    }
    ret ok
}

// Each module-scope `var`'s ADRP pair pointed into the area at `area_address`.
fn place_globals(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize, machine_start: usize, area_address: usize, output: *emit_x64.Buffer) -> err {
    var global_at = 0usize
    while global_at < relocation_count {
        if relocations[global_at].global {
            let reference_index = relocations[global_at].function_ref
            if reference_index >= builder.global_count { ret InvalidImage }
            let site = machine_start + relocations[global_at].displacement_at
            try emit_a64.patch_page(output, site, MACHO_BASE + site, area_address + nir.global_area_offset(builder, reference_index))
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

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len || table_at > machine.count { ret InvalidImage }
    if nir.import_library_count(builder) != 0usize { ret NeedsLoader }
    codegen_x64.mark_live_globals(builder, relocations, relocation_count)
    let has_globals = nir.live_global_count(builder) != 0usize
    // __PAGEZERO, __TEXT, __LINKEDIT and __DATA's when there are globals, then LC_MAIN,
    // LC_LOAD_DYLINKER, LC_LOAD_DYLIB, LC_SYMTAB, LC_DYSYMTAB, the chained fixups,
    // LC_BUILD_VERSION and LC_CODE_SIGNATURE.
    var segment_count = 3usize
    if has_globals { segment_count = 4usize }
    let command_count = segment_count + 8usize
    let commands_size = 72usize * segment_count + 272usize
    // The header and its commands fill the first page; the code starts on the second.
    let code_offset = MACHO_PAGE
    var entry_address = 0usize
    // The code is placed first into the output only to measure it and to learn the entry;
    // the header is written after, over the page left for it.
    try link_elf.pad_to(output, code_offset)
    try place_code(builder, machine, function_offsets, relocations, relocation_count, table_at, code_offset, output, &entry_address)
    let text_end = output.count
    let text_size = link_elf.align_up_to(text_end, MACHO_PAGE)
    let data_offset = text_size
    var data_end = text_size
    if has_globals {
        try link_elf.pad_to(output, data_offset)
        try link_elf.append_globals(builder, output, data_offset)
        try link_elf.pad_to(output, data_offset + nir.global_area_size(builder))
        data_end = link_elf.align_up_to(output.count, MACHO_PAGE)
        try link_elf.pad_to(output, data_end)
        try place_globals(builder, relocations, relocation_count, code_offset, MACHO_BASE + data_offset, output)
    } else {
        try link_elf.pad_to(output, text_size)
    }
    // __LINKEDIT, on the page after everything else: the chained-fixups blob dyld insists
    // on (no imports, no starts), an empty symbol table, then the signature, whose hash
    // covers all before it.
    let linkedit_offset = data_end
    let starts_size = 4usize + 4usize * segment_count
    let imports_offset = 32usize + starts_size
    let fixups_size = link_elf.align_up_to(imports_offset + 1usize, 8usize)
    let strings_offset = linkedit_offset + fixups_size
    let signature_offset = link_elf.align_up_to(strings_offset + 8usize, 16usize)
    let directory = directory_size(signature_offset)
    let signature_size = 20usize + directory
    let linkedit_size = signature_offset - linkedit_offset + signature_size
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 32usize)
    try emit_x64.little_u32(output, imports_offset)
    try emit_x64.little_u32(output, imports_offset)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 0usize)
    try link_elf.pad_to(output, linkedit_offset + 32usize)
    try emit_x64.little_u32(output, segment_count)
    try link_elf.pad_to(output, linkedit_offset + fixups_size)
    try emit_x64.byte(output, 32usize)
    try link_elf.pad_to(output, signature_offset)
    let end = output.count
    output.count = 0usize
    try emit_x64.little_u32(output, 4277009103usize)
    try emit_x64.little_u32(output, 16777228usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, command_count)
    try emit_x64.little_u32(output, commands_size)
    // MH_NOUNDEFS | MH_DYLDLINK | MH_TWOLEVEL | MH_PIE.
    try emit_x64.little_u32(output, 2097285usize)
    try emit_x64.little_u32(output, 0usize)
    try segment(output, "__PAGEZERO", 0usize, MACHO_BASE, 0usize, 0usize, 0usize)
    try segment(output, "__TEXT", MACHO_BASE, text_size, 0usize, text_size, 5usize)
    if has_globals { try segment(output, "__DATA", MACHO_BASE + data_offset, data_end - data_offset, data_offset, data_end - data_offset, 3usize) }
    try segment(output, "__LINKEDIT", MACHO_BASE + linkedit_offset, link_elf.align_up_to(linkedit_size, MACHO_PAGE), linkedit_offset, linkedit_size, 1usize)
    // LC_MAIN: the runtime's entry, as a file offset into __TEXT, called as main(argc, argv).
    try emit_x64.little_u32(output, 2147483688usize)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u64(output, entry_address - MACHO_BASE)
    try emit_x64.little_u64(output, 0usize)
    // LC_LOAD_DYLINKER and LC_LOAD_DYLIB for libSystem: dyld loads the image, and the kernel
    // refuses an arm64 executable that has neither.
    try emit_x64.little_u32(output, 14usize)
    try emit_x64.little_u32(output, 32usize)
    try emit_x64.little_u32(output, 12usize)
    try padded_name(output, "/usr/lib/dyld", 20usize)
    try emit_x64.little_u32(output, 12usize)
    try emit_x64.little_u32(output, 56usize)
    try emit_x64.little_u32(output, 24usize)
    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, 65536usize)
    try emit_x64.little_u32(output, 65536usize)
    try padded_name(output, "/usr/lib/libSystem.B.dylib", 32usize)
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
    try emit_x64.little_u32(output, fixups_size)
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
