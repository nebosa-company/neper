// The aarch64 Linux static image (D2123): the x64 writer's layout, with the code on a page
// so the ADRP pairs patched against the machine buffer hold, the runtime and its entry stub
// after the code, and every patch made by its instruction word. A program with an
// `@import` needs a loader, which this target does not have yet; nor does it carry the
// DWARF sections yet.
use check
use codegen_x64
use emit_x64
use emit_a64
use link_elf
use nir
use runtime_elf_a64

error InvalidImage
// The program reaches an `@import`, which needs a loader this target does not have yet.
error NeedsLoader
// A call to a runtime function the aarch64 runtime does not define.
error MissingRuntime

const A64_IMAGE_BASE: usize = 4194304usize
const A64_IMAGE_PAGE: usize = 4096usize

fn runtime_limit(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) -> (usize, err) {
    let (limit, has_start) = runtime_elf_a64.symbol_end("neper_start_arena")
    if !has_start { ret (0usize, InvalidImage) }
    var most = limit
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && !relocations[at].resolved {
            let reference_index = relocations[at].function_ref
            if reference_index >= builder.function_ref_count { ret (0usize, InvalidImage) }
            let (end, found) = runtime_elf_a64.symbol_end(builder.function_refs[reference_index].name)
            if found && end > most { most = end }
        }
        at += 1usize
    }
    ret (most, ok)
}

// The code, the runtime and the symbol table from `code_offset` (a page), the entry and
// main's call patched, and every relocation but a global's pointed at its function, the
// runtime, the table or -- for an import -- its slot at `got_address`. `table_file` gets
// where the table went.
fn place_code(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, table_at: usize, code_offset: usize, got_address: usize, output: *emit_x64.Buffer, table_file: *usize) -> err {
    let (main_index, main_error) = link_elf.find_main(builder)
    if main_error != ok { ret main_error }
    try link_elf.pad_to(output, code_offset)
    let machine_start = output.count
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    try link_elf.pad_to(output, link_elf.align_up_to(output.count, 4usize))
    let runtime_start = output.count
    let (limit, limit_error) = runtime_limit(builder, relocations, relocation_count)
    if limit_error != ok { ret limit_error }
    try runtime_elf_a64.append(output, limit)
    *table_file = output.count
    if table_at < machine.count {
        try link_elf.pad_to(output, link_elf.align_up_to(output.count, 8usize))
        *table_file = output.count
        try emit_x64.append_bytes(output, machine.bytes[table_at..machine.count])
        try codegen_x64.rebase_symbol_table(output, *table_file, A64_IMAGE_BASE + machine_start)
    }
    let (entry, has_entry) = runtime_elf_a64.symbol_offset("neper_start")
    let (main_call, has_main_call) = runtime_elf_a64.symbol_offset("neper_start_main")
    let (arena_literal, has_arena_literal) = runtime_elf_a64.symbol_offset("neper_start_arena")
    if !has_entry || !has_main_call || !has_arena_literal { ret InvalidImage }
    try link_elf.patch_little_u64(output, 24usize, A64_IMAGE_BASE + runtime_start + entry)
    try emit_a64.patch_relative(output, runtime_start + main_call, machine_start + function_offsets[main_index])
    if builder.arena_bytes != 0usize { try link_elf.patch_little_u64(output, runtime_start + arena_literal, builder.arena_bytes) }
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.global {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidImage }
            let site = machine_start + relocation.displacement_at
            if codegen_x64.is_symbols_reference(builder, relocation) {
                try emit_a64.patch_relative(output, site, *table_file)
                relocations[relocation_at].resolved = true
            } else {
                if !relocation.resolved {
                    let (library, slot_entry, is_import) = nir.import_slot_of(builder, relocation.function_ref)
                    if is_import {
                        let flat = nir.import_flat_index(builder, library, slot_entry)
                        try emit_a64.patch_page(output, site, A64_IMAGE_BASE + site, got_address + flat * 8usize)
                    } else {
                        let (runtime_offset, found_runtime) = runtime_elf_a64.symbol_offset(builder.function_refs[relocation.function_ref].name)
                        if !found_runtime { ret MissingRuntime }
                        try emit_a64.patch_relative(output, site, runtime_start + runtime_offset)
                    }
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
            try emit_a64.patch_page(output, site, A64_IMAGE_BASE + site, area_address + nir.global_area_offset(builder, reference_index))
            relocations[global_at].resolved = true
        }
        global_at += 1usize
    }
    ret ok
}

// The dynamic image: the x64 one's layout (link_elf.write_dynamic) with aarch64's loader,
// machine and relocation. Everything the loader reads is in the first segment ahead of the
// code; the writable segment holds the dynamic array, the slots the loader fills -- every
// `R_AARCH64_GLOB_DAT` (1025) resolved at once under DF_BIND_NOW, no PLT -- and the globals.
fn write_dynamic(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    let base = A64_IMAGE_BASE
    let symbols = nir.import_symbol_total(builder)
    let interpreter = "/lib/ld-linux-aarch64.so.1"
    let phdr_offset = 64usize
    let phdr_count = 5usize
    let interp_offset = phdr_offset + phdr_count * 56usize
    let interp_size = interpreter.len + 1usize
    let dynstr_offset = interp_offset + interp_size
    let dynstr_size = link_elf.dynamic_string_size(builder)
    let dynsym_offset = link_elf.align_up_to(dynstr_offset + dynstr_size, 8usize)
    let dynsym_size = (symbols + 1usize) * 24usize
    let hash_offset = link_elf.align_up_to(dynsym_offset + dynsym_size, 8usize)
    let hash_size = link_elf.dynamic_hash_size(builder)
    let rela_offset = link_elf.align_up_to(hash_offset + hash_size, 8usize)
    let rela_size = symbols * 24usize
    let page = A64_IMAGE_PAGE
    var code_offset = link_elf.align_up_to(rela_offset + rela_size, page)
    if code_offset < page { code_offset = page }
    try elf_header(output, phdr_count)
    // PT_PHDR, PT_INTERP, the read-execute load, the writable load and PT_DYNAMIC; the
    // sizes are patched once known.
    try program_header(output, 6usize, 4usize, phdr_offset, base + phdr_offset, phdr_count * 56usize, 8usize)
    try program_header(output, 3usize, 4usize, interp_offset, base + interp_offset, interp_size, 1usize)
    try program_header(output, 1usize, 5usize, 0usize, base, 0usize, A64_IMAGE_PAGE)
    try program_header(output, 1usize, 6usize, 0usize, 0usize, 0usize, A64_IMAGE_PAGE)
    try program_header(output, 2usize, 6usize, 0usize, 0usize, 0usize, 8usize)
    try link_elf.pad_to(output, interp_offset)
    try link_elf.append_text(output, interpreter)
    try emit_x64.byte(output, 0usize)
    try link_elf.pad_to(output, dynstr_offset)
    try link_elf.append_dynamic_strings(builder, output)
    try link_elf.pad_to(output, dynsym_offset)
    try link_elf.append_dynamic_symbols(builder, output)
    try link_elf.pad_to(output, hash_offset)
    try link_elf.append_dynamic_hash(builder, output)
    try link_elf.pad_to(output, rela_offset + rela_size)
    let machine_start = code_offset
    // The slots' addresses are needed to patch the calls, and depend only on where the code
    // ends: the code is placed, then its end measured, then the calls patched -- so the
    // first placement is undone and repeated with the answer.
    let text_start = output.count
    var table_file = 0usize
    try place_code(builder, machine, function_offsets, relocations, relocation_count, table_at, code_offset, base, output, &table_file)
    let text_end = output.count
    let data_offset = link_elf.align_up_to(text_end, A64_IMAGE_PAGE)
    let dynamic_address = base + data_offset
    let dynamic_size = link_elf.dynamic_entry_count(builder) * 16usize
    let got_address = dynamic_address + dynamic_size
    output.count = text_start
    clear_resolved_imports(builder, relocations, relocation_count)
    try place_code(builder, machine, function_offsets, relocations, relocation_count, table_at, code_offset, got_address, output, &table_file)
    if output.count != text_end { ret InvalidImage }
    try link_elf.pad_to(output, data_offset)
    try link_elf.append_dynamic(builder, output, base + dynstr_offset, base + dynsym_offset, base + hash_offset, base + rela_offset)
    var slot = 0usize
    while slot < symbols {
        try emit_x64.little_u64(output, 0usize)
        slot += 1usize
    }
    let globals_offset = link_elf.align_up_to(output.count, 8usize)
    try link_elf.pad_to(output, globals_offset)
    let globals_size = nir.global_area_size(builder)
    try link_elf.append_globals(builder, output, globals_offset)
    try link_elf.pad_to(output, globals_offset + globals_size)
    let data_end = output.count
    try place_globals(builder, relocations, relocation_count, machine_start, base + globals_offset, output)
    try patch_dynamic_relocations(builder, output, rela_offset, got_address)
    try link_elf.patch_little_u64(output, 96usize + 56usize * 2usize, text_end)
    try link_elf.patch_little_u64(output, 104usize + 56usize * 2usize, text_end)
    try link_elf.patch_little_u64(output, 72usize + 56usize * 3usize, data_offset)
    try link_elf.patch_little_u64(output, 80usize + 56usize * 3usize, base + data_offset)
    try link_elf.patch_little_u64(output, 88usize + 56usize * 3usize, base + data_offset)
    try link_elf.patch_little_u64(output, 96usize + 56usize * 3usize, data_end - data_offset)
    try link_elf.patch_little_u64(output, 104usize + 56usize * 3usize, data_end - data_offset)
    try link_elf.patch_little_u64(output, 72usize + 56usize * 4usize, data_offset)
    try link_elf.patch_little_u64(output, 80usize + 56usize * 4usize, dynamic_address)
    try link_elf.patch_little_u64(output, 88usize + 56usize * 4usize, dynamic_address)
    try link_elf.patch_little_u64(output, 96usize + 56usize * 4usize, dynamic_size)
    try link_elf.patch_little_u64(output, 104usize + 56usize * 4usize, dynamic_size)
    ret link_elf.append_debug(builder, output, machine, machine_start, function_offsets, lines, table_at, code_offset, table_file, true)
}

// The first placement resolved the import calls against a stand-in address.
fn clear_resolved_imports(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) {
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && relocations[at].function_ref < builder.function_ref_count {
            let (library, slot_entry, is_import) = nir.import_slot_of(builder, relocations[at].function_ref)
            if is_import { relocations[at].resolved = false }
            if !is_import && !builder.function_refs[relocations[at].function_ref].has_target { relocations[at].resolved = false }
        }
        at += 1usize
    }
}

fn patch_dynamic_relocations(builder: *nir.Builder, output: *emit_x64.Buffer, rela_offset: usize, got_address: usize) -> err {
    var library = 0usize
    while library < nir.import_library_count(builder) {
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            let flat = nir.import_flat_index(builder, library, entry)
            let at = rela_offset + flat * 24usize
            try link_elf.patch_little_u64(output, at, got_address + flat * 8usize)
            // r_info: the symbol index in the high word, R_AARCH64_GLOB_DAT in the low.
            try emit_x64.patch_little_u32(output, at + 8usize, 1025usize)
            try emit_x64.patch_little_u32(output, at + 12usize, flat + 1usize)
            entry += 1usize
        }
        library += 1usize
    }
    ret ok
}

fn elf_header(output: *emit_x64.Buffer, phdr_count: usize) -> err {
    try emit_x64.byte(output, 127usize)
    try emit_x64.byte(output, 69usize)
    try emit_x64.byte(output, 76usize)
    try emit_x64.byte(output, 70usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 1usize)
    try link_elf.pad_to(output, 16usize)
    try link_elf.little_u16(output, 2usize)
    try link_elf.little_u16(output, 183usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 64usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try link_elf.little_u16(output, 64usize)
    try link_elf.little_u16(output, 56usize)
    try link_elf.little_u16(output, phdr_count)
    try link_elf.little_u16(output, 0usize)
    try link_elf.little_u16(output, 0usize)
    ret link_elf.little_u16(output, 0usize)
}

fn program_header(output: *emit_x64.Buffer, kind: usize, flags: usize, offset: usize, address: usize, size: usize, alignment: usize) -> err {
    try emit_x64.little_u32(output, kind)
    try emit_x64.little_u32(output, flags)
    try emit_x64.little_u64(output, offset)
    try emit_x64.little_u64(output, address)
    try emit_x64.little_u64(output, address)
    try emit_x64.little_u64(output, size)
    try emit_x64.little_u64(output, size)
    ret emit_x64.little_u64(output, alignment)
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || relocation_count > relocations.len || table_at > machine.count { ret InvalidImage }
    codegen_x64.mark_live_globals(builder, relocations, relocation_count)
    if nir.import_library_count(builder) != 0usize { ret write_dynamic(builder, machine, function_offsets, relocations, relocation_count, lines, table_at, output) }
    var segments = 1usize
    if nir.live_global_count(builder) != 0usize { segments = 2usize }
    try elf_header(output, segments)
    // The read-execute segment from the file's start and, with globals, the writable one;
    // their sizes are patched at the end.
    try program_header(output, 1usize, 5usize, 0usize, A64_IMAGE_BASE, 0usize, A64_IMAGE_PAGE)
    if segments == 2usize { try program_header(output, 1usize, 6usize, 0usize, 0usize, 0usize, A64_IMAGE_PAGE) }
    // The code on a page of its own (an address is the base plus the file offset, and the
    // base is a page), so a page delta between two offsets is the one between addresses.
    // ponytail: up to a page of padding per image; x64 dropped its own (D149).
    let machine_start = A64_IMAGE_PAGE
    var table_file = 0usize
    try place_code(builder, machine, function_offsets, relocations, relocation_count, table_at, machine_start, 0usize, output, &table_file)
    let code_end = output.count
    try link_elf.patch_little_u64(output, 96usize, code_end)
    try link_elf.patch_little_u64(output, 104usize, code_end)
    if segments == 2usize {
        // The data on a page of its own one page past its offset, as on x64.
        var area_alignment = 1usize
        var alignment_at = 0usize
        while alignment_at < builder.global_count {
            if builder.globals[alignment_at].live && builder.globals[alignment_at].alignment > area_alignment { area_alignment = builder.globals[alignment_at].alignment }
            alignment_at += 1usize
        }
        let area_offset = link_elf.align_up_to(code_end, area_alignment)
        let area_address = A64_IMAGE_BASE + area_offset + A64_IMAGE_PAGE
        let area_size = nir.global_area_size(builder)
        try link_elf.pad_to(output, area_offset)
        try link_elf.append_globals(builder, output, area_offset)
        try link_elf.pad_to(output, area_offset + area_size)
        try link_elf.patch_little_u64(output, 128usize, area_offset)
        try link_elf.patch_little_u64(output, 136usize, area_address)
        try link_elf.patch_little_u64(output, 144usize, area_address)
        try link_elf.patch_little_u64(output, 152usize, area_size)
        try link_elf.patch_little_u64(output, 160usize, area_size)
        try place_globals(builder, relocations, relocation_count, machine_start, area_address, output)
    }
    // (D1581) Section headers, symbols and DWARF after everything the loader maps, with
    // aarch64's frame description.
    ret link_elf.append_debug(builder, output, machine, machine_start, function_offsets, lines, table_at, machine_start, table_file, true)
}
