// Minimal deterministic x86-64 ELF executable linker for closed modules.

use e.mem
use e.os
use check
use codegen_x64
use emit_x64
use nir
use runtime_elf_x64

error InvalidExecutable

fn little_u16(output: *emit_x64.Buffer, value: usize) -> err {
    try emit_x64.byte(output, value % 256usize)
    ret emit_x64.byte(output, value / 256usize % 256usize)
}

fn pad_to(output: *emit_x64.Buffer, offset: usize) -> err {
    if output.count > offset { ret InvalidExecutable }
    while output.count < offset { try emit_x64.byte(output, 0usize) }
    ret ok
}

fn append_blob(output: *emit_x64.Buffer, bytes: str) -> err {
    var at = 0usize
    while at < bytes.len {
        try emit_x64.byte(output, usize(bytes[at]))
        at += 1usize
    }
    ret ok
}

// `--arena` (D225): the startup stub carries the root arena's size as four 64-bit
// immediates (D330; they were 32-bit, and so was the largest arena) -- the mapping's
// length, two bounds and the arena's capacity -- at these offsets from its start.
fn patch_arena(output: *emit_x64.Buffer, startup: usize, arena_bytes: usize) -> err {
    if arena_bytes == 0usize { ret ok }
    try patch_little_u64(output, startup + 7usize, arena_bytes)
    try patch_little_u64(output, startup + 68usize, arena_bytes)
    try patch_little_u64(output, startup + 126usize, arena_bytes)
    ret patch_little_u64(output, startup + 194usize, arena_bytes)
}

fn append_startup(output: *emit_x64.Buffer) -> err {
    try append_blob(output, "\x49\x89\xe4\x31\xff\x48\xbe\x00\x00\x00\x40\x00\x00\x00\x00\xba\x03\x00\x00\x00\x41\xba\x22\x40\x00\x00\x49\xc7\xc0\xff\xff\xff\xff\x45\x31\xc9\xb8\x09\x00\x00\x00\x0f\x05\x48\x85\xc0\x0f\x88\xc9\x00\x00\x00\x49\x89\xc5\x4d\x8b\x34\x24\x4c\x89\xf3\x48\xc1\xe3\x04\x48\xb8\x00\x00\x00\x40\x00\x00\x00\x00\x48\x39\xc3\x0f\x87\xa8\x00\x00\x00\x45\x31\xff")
    try append_blob(output, "\x4d\x39\xf7\x73\x5b\x4f\x8b\x44\xfc\x08\x31\xc9\x41\x80\x3c\x08\x00\x74\x05\x48\xff\xc1\xeb\xf4\x48\x89\xd8\x48\x01\xc8\x0f\x82\x81\x00\x00\x00\x49\xbb\x00\x00\x00\x40\x00\x00\x00\x00\x4c\x39\xd8\x0f\x87\x6e\x00\x00\x00\x4d\x8d\x4c\x1d\x00\x4d\x89\xfa\x49\xc1\xe2\x04\x4f\x89\x4c\x15\x00\x4b\x89\x4c\x15\x08\x48\x89\xca\x4c\x89\xc6\x4c\x89\xcf\xf3\xa4\x48")
    ret append_blob(output, "\x01\xd3\x49\xff\xc7\xeb\xa0\x48\x83\xec\x30\x4c\x89\x2c\x24\x48\xb8\x00\x00\x00\x40\x00\x00\x00\x00\x48\x89\x44\x24\x08\x48\x89\x5c\x24\x10\x4c\x89\x6c\x24\x18\x4c\x89\x74\x24\x20\x48\x8d\x3c\x24\x48\x8d\x74\x24\x18\xe8\x00\x00\x00\x00\x85\xc0\x40\x0f\x95\xc7\x40\x0f\xb6\xff\xb8\x3c\x00\x00\x00\x0f\x05\xbf\x6f\x00\x00\x00\xb8\x3c\x00\x00\x00\x0f\x05\x0f\x0b")
}

// How much of the runtime a program needs: up to the end of the last function it reaches.
// The runtime's source is ordered so that a function calls only what precedes it, which is
// what lets a prefix stand in for the set -- one cut instead of a relocation table. A program
// that reaches nothing in it gets none of it.
// ponytail: prefix, not per-function; a program that reaches `wait` carries `spawn` too.
fn runtime_prefix(builder: *nir.Builder, relocations: []codegen_x64.Relocation, relocation_count: usize) -> (usize, err) {
    var limit = 0usize
    var at = 0usize
    while at < relocation_count {
        if !relocations[at].global && !relocations[at].resolved {
            let reference_index = relocations[at].function_ref
            if reference_index >= builder.function_ref_count { ret (0usize, InvalidExecutable) }
            let (end, found) = runtime_elf_x64.symbol_end(builder.function_refs[reference_index].name)
            if found && end > limit { limit = end }
        }
        at += 1usize
    }
    ret (limit, ok)
}

fn patch_little_u64(output: *emit_x64.Buffer, offset: usize, value: usize) -> err {
    if offset + 8usize > output.count { ret InvalidExecutable }
    var at = 0usize
    var remaining = value
    while at < 8usize {
        output.bytes[offset + at] = u8(remaining % 256usize)
        remaining = remaining / 256usize
        at += 1usize
    }
    ret ok
}

fn find_main(builder: *nir.Builder) -> (usize, err) {
    var at = 0usize
    while at < builder.function_count {
        if builder.functions[at].module_index == 0usize && check.same(builder.functions[at].name, "main") { ret (at, ok) }
        at += 1usize
    }
    ret (0usize, InvalidExecutable)
}

// A program with no `extern` is a freestanding static image and stays exactly that:
// one read-execute segment, no interpreter, no dynamic array. Only an `@import` makes
// this image need a loader, and then it needs all of the below.
//
// There are no PLT stubs. Every imported call goes straight through a slot the loader
// fills before the entry point runs -- `R_X86_64_GLOB_DAT` is resolved eagerly -- which
// is the same `call qword ptr [rip + disp32]` the PE side emits and leaves nothing to
// bind lazily. Lazy binding would buy a shorter start-up and cost a PLT, a second GOT
// convention and `DT_PLTGOT`; none of that is worth having here.
fn interpreter_path() -> str {
    ret "/lib64/ld-linux-x86-64.so.2"
}

fn align_up_to(value: usize, alignment: usize) -> usize {
    let remainder = value % alignment
    if remainder == 0usize { ret value }
    ret value + alignment - remainder
}

// `.dynstr` holds one terminated name per library and per symbol, after a leading
// empty string that index 0 has to be.
fn dynamic_string_size(builder: *nir.Builder) -> usize {
    var size = 1usize
    var library = 0usize
    while library < nir.import_library_count(builder) {
        size += nir.import_library_name(builder, library).len + 1usize
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            size += nir.import_symbol_name(builder, library, entry).len + 1usize
            entry += 1usize
        }
        library += 1usize
    }
    ret size
}

fn library_string_offset(builder: *nir.Builder, library: usize) -> usize {
    var offset = 1usize
    var at = 0usize
    while at < library {
        let library_text = nir.import_library_name(builder, at)
        offset += library_text.len + 1usize
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, at) {
            let symbol_text = nir.import_symbol_name(builder, at, entry)
            offset += symbol_text.len + 1usize
            entry += 1usize
        }
        at += 1usize
    }
    ret offset
}

fn symbol_string_offset(builder: *nir.Builder, library: usize, entry: usize) -> usize {
    let library_text = nir.import_library_name(builder, library)
    var offset = library_string_offset(builder, library) + library_text.len + 1usize
    var at = 0usize
    while at < entry {
        let symbol_text = nir.import_symbol_name(builder, library, at)
        offset += symbol_text.len + 1usize
        at += 1usize
    }
    ret offset
}

fn append_dynamic_strings(builder: *nir.Builder, output: *emit_x64.Buffer) -> err {
    try emit_x64.byte(output, 0usize)
    var library = 0usize
    while library < nir.import_library_count(builder) {
        try append_text(output, nir.import_library_name(builder, library))
        try emit_x64.byte(output, 0usize)
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            try append_text(output, nir.import_symbol_name(builder, library, entry))
            try emit_x64.byte(output, 0usize)
            entry += 1usize
        }
        library += 1usize
    }
    ret ok
}

fn append_text(output: *emit_x64.Buffer, text: str) -> err {
    var at = 0usize
    while at < text.len {
        try emit_x64.byte(output, usize(text[at]))
        at += 1usize
    }
    ret ok
}

// One `Elf64_Sym` per imported symbol, after the null entry index 0 has to be. Every
// one is an undefined global function, which is what makes the loader look for it in
// the libraries `DT_NEEDED` names.
fn append_dynamic_symbols(builder: *nir.Builder, output: *emit_x64.Buffer) -> err {
    var at = 0usize
    while at < 24usize {
        try emit_x64.byte(output, 0usize)
        at += 1usize
    }
    var library = 0usize
    while library < nir.import_library_count(builder) {
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            try emit_x64.little_u32(output, symbol_string_offset(builder, library, entry))
            // STB_GLOBAL | STT_FUNC, no visibility bits, SHN_UNDEF.
            try emit_x64.byte(output, 18usize)
            try emit_x64.byte(output, 0usize)
            try little_u16(output, 0usize)
            try emit_x64.little_u64(output, 0usize)
            try emit_x64.little_u64(output, 0usize)
            entry += 1usize
        }
        library += 1usize
    }
    ret ok
}

// `DT_HASH` is not used to find anything here -- this image defines no symbol anyone
// looks up -- but glibc expects a hash table to exist, so it gets the smallest valid
// one: a single bucket holding every symbol in a chain.
fn append_dynamic_hash(builder: *nir.Builder, output: *emit_x64.Buffer) -> err {
    let symbols = nir.import_symbol_total(builder) + 1usize
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, symbols)
    var first = 0usize
    if symbols > 1usize { first = 1usize }
    try emit_x64.little_u32(output, first)
    try emit_x64.little_u32(output, 0usize)
    var at = 1usize
    while at < symbols {
        var next = at + 1usize
        if next == symbols { next = 0usize }
        try emit_x64.little_u32(output, next)
        at += 1usize
    }
    ret ok
}

fn dynamic_hash_size(builder: *nir.Builder) -> usize {
    let symbols = nir.import_symbol_total(builder) + 1usize
    let words = 3usize + symbols
    ret words * 4usize
}

// One `R_X86_64_GLOB_DAT` per symbol, each naming the slot that symbol's calls read.
// Patched rather than appended: the area was reserved with the rest of what the loader
// reads, which is ahead of the code, while the slots it names are behind it.
fn patch_dynamic_relocations(builder: *nir.Builder, output: *emit_x64.Buffer, rela_offset: usize, got_address: usize) -> err {
    var library = 0usize
    while library < nir.import_library_count(builder) {
        var entry = 0usize
        while entry < nir.import_symbol_count(builder, library) {
            let flat = nir.import_flat_index(builder, library, entry)
            let at = rela_offset + flat * 24usize
            try patch_little_u64(output, at, got_address + flat * 8usize)
            // r_info: the symbol index in the high word, R_X86_64_GLOB_DAT (6) in the low.
            try emit_x64.patch_little_u32(output, at + 8usize, 6usize)
            try emit_x64.patch_little_u32(output, at + 12usize, flat + 1usize)
            entry += 1usize
        }
        library += 1usize
    }
    ret ok
}

fn append_dynamic_entry(output: *emit_x64.Buffer, tag: usize, value: usize) -> err {
    try emit_x64.little_u64(output, tag)
    ret emit_x64.little_u64(output, value)
}

fn dynamic_entry_count(builder: *nir.Builder) -> usize {
    ret nir.import_library_count(builder) + 10usize
}

fn append_dynamic(builder: *nir.Builder, output: *emit_x64.Buffer, dynstr_address: usize, dynsym_address: usize, hash_address: usize, rela_address: usize) -> err {
    var library = 0usize
    while library < nir.import_library_count(builder) {
        try append_dynamic_entry(output, 1usize, library_string_offset(builder, library))
        library += 1usize
    }
    try append_dynamic_entry(output, 5usize, dynstr_address)
    try append_dynamic_entry(output, 10usize, dynamic_string_size(builder))
    try append_dynamic_entry(output, 6usize, dynsym_address)
    try append_dynamic_entry(output, 11usize, 24usize)
    try append_dynamic_entry(output, 4usize, hash_address)
    try append_dynamic_entry(output, 7usize, rela_address)
    try append_dynamic_entry(output, 8usize, nir.import_symbol_total(builder) * 24usize)
    try append_dynamic_entry(output, 9usize, 24usize)
    // DF_BIND_NOW, and the flag that says so again for loaders that read only one.
    try append_dynamic_entry(output, 30usize, 8usize)
    ret append_dynamic_entry(output, 0usize, 0usize)
}

// The dynamic image. Everything the loader reads sits in the first segment ahead of
// the code, and the one writable segment holds the dynamic array and the slots the
// loader fills. The layout is derived in one pass so that every address below is the
// arithmetic that produced it and none of it is written down twice.
// The globals area's contents. A zero-initialised one needs nothing written, since padding is
// already zero -- which is what section 5's "zero-initialised unless given an initialiser" costs.
fn append_globals(builder: *nir.Builder, output: *emit_x64.Buffer, area_offset: usize) -> err {
    var at = 0usize
    while at < builder.global_count {
        let item = builder.globals[at]
        if item.live && item.has_initial && item.initial != 0usize {
            try pad_to(output, area_offset + nir.global_area_offset(builder, at))
            var byte_at = 0usize
            var remaining = item.initial
            while byte_at < item.size {
                try emit_x64.byte(output, remaining % 256usize)
                remaining = remaining / 256usize
                byte_at += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

fn write_dynamic(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    let base = 4194304usize
    let startup_size = 267usize
    let symbols = nir.import_symbol_total(builder)

    let phdr_offset = 64usize
    let phdr_count = 5usize
    let interp_offset = phdr_offset + phdr_count * 56usize
    let interpreter = interpreter_path()
    let interp_size = interpreter.len + 1usize
    let dynstr_offset = interp_offset + interp_size
    let dynstr_size = dynamic_string_size(builder)
    let dynsym_offset = align_up_to(dynstr_offset + dynstr_size, 8usize)
    let dynsym_size = (symbols + 1usize) * 24usize
    let hash_offset = align_up_to(dynsym_offset + dynsym_size, 8usize)
    let hash_size = dynamic_hash_size(builder)
    let rela_offset = align_up_to(hash_offset + hash_size, 8usize)
    let rela_size = symbols * 24usize
    // The code starts on the first page past the loader's metadata (D1594). Up to about 48
    // imports that is the page at 4096, where it always was, so a small program lays out
    // byte for byte as before; past that the metadata takes more pages. Every address below
    // is derived from this offset, and the first loaded segment starts at 0 and runs to the
    // end of the code, so it covers the metadata however many pages it takes.
    var code_offset = align_up_to(rela_offset + rela_size, 4096usize)
    if code_offset < 4096usize { code_offset = 4096usize }

    try emit_x64.byte(output, 127usize)
    try emit_x64.byte(output, 69usize)
    try emit_x64.byte(output, 76usize)
    try emit_x64.byte(output, 70usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try pad_to(output, 16usize)
    try little_u16(output, 2usize)
    try little_u16(output, 62usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u64(output, base + code_offset)
    try emit_x64.little_u64(output, phdr_offset)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 64usize)
    try little_u16(output, 56usize)
    try little_u16(output, phdr_count)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)

    // The sizes of the two loaded segments are not known until the code and the
    // writable data have been written, so the headers are emitted with placeholders
    // and patched at the end -- as the static path already does for its one segment.
    try emit_x64.little_u32(output, 6usize)
    try emit_x64.little_u32(output, 4usize)
    try emit_x64.little_u64(output, phdr_offset)
    try emit_x64.little_u64(output, base + phdr_offset)
    try emit_x64.little_u64(output, base + phdr_offset)
    try emit_x64.little_u64(output, phdr_count * 56usize)
    try emit_x64.little_u64(output, phdr_count * 56usize)
    try emit_x64.little_u64(output, 8usize)

    try emit_x64.little_u32(output, 3usize)
    try emit_x64.little_u32(output, 4usize)
    try emit_x64.little_u64(output, interp_offset)
    try emit_x64.little_u64(output, base + interp_offset)
    try emit_x64.little_u64(output, base + interp_offset)
    try emit_x64.little_u64(output, interp_size)
    try emit_x64.little_u64(output, interp_size)
    try emit_x64.little_u64(output, 1usize)

    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 5usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, base)
    try emit_x64.little_u64(output, base)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 4096usize)

    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 6usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 4096usize)

    try emit_x64.little_u32(output, 2usize)
    try emit_x64.little_u32(output, 6usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 8usize)

    try pad_to(output, interp_offset)
    try append_text(output, interpreter_path())
    try emit_x64.byte(output, 0usize)
    try pad_to(output, dynstr_offset)
    try append_dynamic_strings(builder, output)
    try pad_to(output, dynsym_offset)
    try append_dynamic_symbols(builder, output)
    try pad_to(output, hash_offset)
    try append_dynamic_hash(builder, output)
    // The relocations name slots that do not exist yet, so the area is reserved here
    // and filled once the writable segment has been laid out.
    try pad_to(output, rela_offset)
    var reserved = 0usize
    while reserved < rela_size {
        try emit_x64.byte(output, 0usize)
        reserved += 1usize
    }

    try pad_to(output, code_offset)
    try append_startup(output)
    try patch_arena(output, code_offset, builder.arena_bytes)
    let machine_start = output.count
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    let runtime_start = output.count
    let (runtime_limit, runtime_limit_error) = runtime_prefix(builder, relocations, relocation_count)
    if runtime_limit_error != ok { ret runtime_limit_error }
    try runtime_elf_x64.append(output, runtime_limit)
    var table_file = 0usize
    try place_symbol_table(builder, output, machine, table_at, machine_start, relocations, relocation_count, &table_file)
    let text_end = output.count

    // The writable segment starts on the next page, at the same offset within it as
    // its address: a segment whose file offset and address disagree modulo the page
    // size cannot be mapped.
    let data_offset = align_up_to(text_end, 4096usize)
    try pad_to(output, data_offset)
    let dynamic_address = base + data_offset
    let dynamic_size = dynamic_entry_count(builder) * 16usize
    let got_offset = data_offset + dynamic_size
    let got_address = base + got_offset
    try append_dynamic(builder, output, base + dynstr_offset, base + dynsym_offset, base + hash_offset, base + rela_offset)
    var slot = 0usize
    while slot < symbols {
        try emit_x64.little_u64(output, 0usize)
        slot += 1usize
    }
    // Module-scope `var`s follow the loader's own slots in the same writable segment: this path
    // already has one, so there is nothing to add to the headers -- only more of it.
    let globals_offset = align_up_to(output.count, 8usize)
    try pad_to(output, globals_offset)
    let globals_size = nir.global_area_size(builder)
    try append_globals(builder, output, globals_offset)
    try pad_to(output, globals_offset + globals_size)
    let data_end = output.count

    try patch_dynamic_relocations(builder, output, rela_offset, got_address)

    let main_offset = machine_start + function_offsets[main_index]
    try emit_x64.patch_relative32(output, code_offset + 232usize, main_offset)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        // A module-scope `var`, whose address is known once the writable segment is placed.
        if relocations[relocation_at].global {
            let global_index = relocations[relocation_at].function_ref
            if global_index >= builder.global_count { ret InvalidExecutable }
            let destination = base + globals_offset + nir.global_area_offset(builder, global_index)
            let site = machine_start + relocations[relocation_at].displacement_at
            // A file offset is its own distance from the image base here as on the static path:
            // both segments are mapped at `base` plus their own offset.
            let next_address = base + site + 4usize
            if destination < next_address { ret InvalidExecutable }
            try emit_x64.patch_little_u32(output, site, destination - next_address)
            relocations[relocation_at].resolved = true
            relocation_at += 1usize
            continue
        }
        if !relocations[relocation_at].resolved {
            let reference_index = relocations[relocation_at].function_ref
            if reference_index >= builder.function_ref_count { ret InvalidExecutable }
            let (library, entry, is_import) = nir.import_slot_of(builder, reference_index)
            if is_import {
                let flat = nir.import_flat_index(builder, library, entry)
                let site = machine_start + relocations[relocation_at].displacement_at
                let next_address = base + site + 4usize
                let slot_address = got_address + flat * 8usize
                if slot_address < next_address { ret InvalidExecutable }
                try emit_x64.patch_little_u32(output, site, slot_address - next_address)
            } else {
                let (runtime_offset, found_runtime) = runtime_elf_x64.symbol_offset(builder.function_refs[reference_index].name)
                if !found_runtime { ret InvalidExecutable }
                try emit_x64.patch_relative32(output, site_of(machine_start, relocations[relocation_at].displacement_at), runtime_start + runtime_offset)
            }
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }

    // The two loaded segments and the dynamic array, now that their sizes are known.
    try patch_little_u64(output, 96usize + 56usize * 2usize, text_end)
    try patch_little_u64(output, 104usize + 56usize * 2usize, text_end)
    try patch_little_u64(output, 72usize + 56usize * 3usize, data_offset)
    try patch_little_u64(output, 80usize + 56usize * 3usize, base + data_offset)
    try patch_little_u64(output, 88usize + 56usize * 3usize, base + data_offset)
    try patch_little_u64(output, 96usize + 56usize * 3usize, data_end - data_offset)
    try patch_little_u64(output, 104usize + 56usize * 3usize, data_end - data_offset)
    try patch_little_u64(output, 72usize + 56usize * 4usize, data_offset)
    try patch_little_u64(output, 80usize + 56usize * 4usize, dynamic_address)
    try patch_little_u64(output, 88usize + 56usize * 4usize, dynamic_address)
    try patch_little_u64(output, 96usize + 56usize * 4usize, dynamic_size)
    try patch_little_u64(output, 104usize + 56usize * 4usize, dynamic_size)
    try append_debug(builder, output, machine, machine_start, function_offsets, lines, table_at, code_offset, table_file)
    ret ok
}

// (D1586) The `.nepersym` table after the runtime rather than between the code and it,
// so a section can name it alone: aligned for its 64-bit fields, its entries made
// addresses, and every trap site's reference to it pointed at where it now is. The
// loaded segment still covers it -- the trap walk reads it -- and `table_file` is where
// it starts, or where it would, for a machine buffer with none (a test's).
fn place_symbol_table(builder: *nir.Builder, output: *emit_x64.Buffer, machine: *emit_x64.Buffer, table_at: usize, machine_start: usize, relocations: []codegen_x64.Relocation, relocation_count: usize, table_file: *usize) -> err {
    *table_file = output.count
    if table_at >= machine.count { ret ok }
    try pad_to(output, align_up_to(output.count, 8usize))
    *table_file = output.count
    try emit_x64.append_bytes(output, machine.bytes[table_at..machine.count])
    try codegen_x64.rebase_symbol_table(output, *table_file, 4194304usize + machine_start)
    var at = 0usize
    while at < relocation_count {
        if codegen_x64.is_symbols_reference(builder, relocations[at]) { try emit_x64.patch_relative32(output, machine_start + relocations[at].displacement_at, *table_file) }
        at += 1usize
    }
    ret ok
}

fn site_of(machine_start: usize, displacement_at: usize) -> usize {
    ret machine_start + displacement_at
}

// `lines` and `table_at`, where the D206 table starts in `machine`, are what a debug image's
// DWARF is built from (D1581).
fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, table_at: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len { ret InvalidExecutable }
    if relocation_count > relocations.len { ret InvalidExecutable }
    codegen_x64.mark_live_globals(builder, relocations, relocation_count)
    // Only an `@import` makes this image need a loader. Without one it stays the
    // freestanding static executable it has always been, byte for byte.
    if nir.import_library_count(builder) != 0usize {
        ret write_dynamic(builder, machine, function_offsets, relocations, relocation_count, lines, table_at, output)
    }
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    // A second segment only when there is something to put in it. An image with no module-scope
    // `var` keeps the single read-execute segment it has always had, byte for byte -- which the
    // determinism harness compares, so the absence of the feature has to cost nothing.
    var segments = 1usize
    if nir.live_global_count(builder) != 0usize { segments = 2usize }
    // The code starts where the program headers end. The loader asks only that a segment's file
    // offset and address agree modulo the page, not that either be a page boundary; padding the
    // code out to 4096 cost an empty program half its size for nothing (D149). The address is
    // still the base plus the file offset, so every relocation below stays a file offset.
    let code_offset = 64usize + 56usize * segments
    let startup_size = 267usize
    try emit_x64.byte(output, 127usize)
    try emit_x64.byte(output, 69usize)
    try emit_x64.byte(output, 76usize)
    try emit_x64.byte(output, 70usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try pad_to(output, 16usize)
    try little_u16(output, 2usize)
    try little_u16(output, 62usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u64(output, 4194304usize + code_offset)
    try emit_x64.little_u64(output, 64usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 64usize)
    try little_u16(output, 56usize)
    try little_u16(output, segments)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u32(output, 5usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 4194304usize)
    try emit_x64.little_u64(output, 4194304usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 4096usize)
    if segments == 2usize {
        // Writable, and placed so its file offset and address agree modulo the page -- which is
        // what the loader requires of a mapping. The offset and size are not known until the
        // code has been written, so they are patched like the first segment's.
        try emit_x64.little_u32(output, 1usize)
        try emit_x64.little_u32(output, 6usize)
        try emit_x64.little_u64(output, 0usize)
        try emit_x64.little_u64(output, 0usize)
        try emit_x64.little_u64(output, 0usize)
        try emit_x64.little_u64(output, 0usize)
        try emit_x64.little_u64(output, 0usize)
        try emit_x64.little_u64(output, 4096usize)
    }
    try pad_to(output, code_offset)
    try append_startup(output)
    try patch_arena(output, code_offset, builder.arena_bytes)
    let machine_start = output.count
    try emit_x64.append_bytes(output, machine.bytes[0usize..table_at])
    let runtime_start = output.count
    let (runtime_limit, runtime_limit_error) = runtime_prefix(builder, relocations, relocation_count)
    if runtime_limit_error != ok { ret runtime_limit_error }
    try runtime_elf_x64.append(output, runtime_limit)
    var table_file = 0usize
    try place_symbol_table(builder, output, machine, table_at, machine_start, relocations, relocation_count, &table_file)
    let main_offset = machine_start + function_offsets[main_index]
    try emit_x64.patch_relative32(output, code_offset + 232usize, main_offset)
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        // A module-scope `var`'s address depends on where the data segment lands, which is
        // decided after the code is written -- so these are left to the pass that does it.
        if relocations[relocation_at].global {
            relocation_at += 1usize
            continue
        }
        if !relocations[relocation_at].resolved {
            let reference_index = relocations[relocation_at].function_ref
            if reference_index >= builder.function_ref_count { ret InvalidExecutable }
            let (runtime_offset, found_runtime) = runtime_elf_x64.symbol_offset(builder.function_refs[reference_index].name)
            if !found_runtime { ret InvalidExecutable }
            try emit_x64.patch_relative32(output, machine_start + relocations[relocation_at].displacement_at, runtime_start + runtime_offset)
            relocations[relocation_at].resolved = true
        }
        relocation_at += 1usize
    }
    // The code segment covers everything written so far. The data follows it in the file, rounded
    // up only to the strictest alignment a global asks for, and is mapped one page further along
    // than its offset would say, so that it lands on a page of its own -- one mapping never has to
    // be both writable and executable -- while the offset and the address still agree modulo the
    // page. The globals' own offsets are relative to the area, so the area must carry the
    // alignment they assume.
    let code_end = output.count
    try patch_little_u64(output, 96usize, code_end)
    try patch_little_u64(output, 104usize, code_end)
    if nir.live_global_count(builder) != 0usize {
        var area_alignment = 1usize
        var alignment_at = 0usize
        while alignment_at < builder.global_count {
            if builder.globals[alignment_at].live && builder.globals[alignment_at].alignment > area_alignment { area_alignment = builder.globals[alignment_at].alignment }
            alignment_at += 1usize
        }
        let area_offset = align_up_to(code_end, area_alignment)
        let area_address = 4194304usize + area_offset + 4096usize
        let area_size = nir.global_area_size(builder)
        try pad_to(output, area_offset)
        try append_globals(builder, output, area_offset)
        try pad_to(output, area_offset + area_size)
        // The second header: offset, virtual and physical address, then both sizes.
        try patch_little_u64(output, 128usize, area_offset)
        try patch_little_u64(output, 136usize, area_address)
        try patch_little_u64(output, 144usize, area_address)
        try patch_little_u64(output, 152usize, area_size)
        try patch_little_u64(output, 160usize, area_size)
        var global_at = 0usize
        while global_at < relocation_count {
            if relocations[global_at].global {
                let reference_index = relocations[global_at].function_ref
                if reference_index >= builder.global_count { ret InvalidExecutable }
                let destination = area_address + nir.global_area_offset(builder, reference_index)
                let site = machine_start + relocations[global_at].displacement_at
                // The displacement is from the end of the instruction, and a code address on
                // this path is the image base plus the file offset.
                let next_address = 4194304usize + site + 4usize
                if destination < next_address { ret InvalidExecutable }
                try emit_x64.patch_little_u32(output, site, destination - next_address)
                relocations[global_at].resolved = true
            }
            global_at += 1usize
        }
    }
    try append_debug(builder, output, machine, machine_start, function_offsets, lines, table_at, code_offset, table_file)
    ret ok
}

// (D1581) What a foreign debugger or profiler reads from an image, appended after
// everything the loader maps and mapped by none of it: section headers naming the code, a
// symbol per placed function, the D206 table as `.nepersym`, and DWARF 4 -- a compile
// unit, a subprogram per placed function and a line program built from the rows the trap
// walk reads. Section 13 asks for the line and symbol tables in every build mode, so a
// release image carries them too. `debug_bound` is what the caller adds to the image's
// buffer for them.
fn debug_bound(builder: *nir.Builder, lines: []codegen_x64.LineEntry) -> usize {
    // The type entries, at most the memo's, and per var its entry and location list.
    // The PE path pads each of its five sections to 512 as well.
    var total = 16384usize + lines.len * 24usize + 2048usize * 96usize
    var var_at = 0usize
    while var_at < builder.debug.var_count {
        total += builder.debug.vars[var_at].name.len + builder.debug.vars[var_at].descriptor.len + 96usize
        var_at += 1usize
    }
    var definition_at = 0usize
    while definition_at < builder.debug.definition_count {
        total += builder.debug.definitions[definition_at].len * 2usize + 64usize
        definition_at += 1usize
    }
    var at = 0usize
    while at < builder.function_count {
        total += 2usize * (builder.functions[at].module_name.len + builder.functions[at].name.len) + 64usize
        at += 1usize
    }
    var row = 0usize
    while row < lines.len {
        if row == 0usize || !check.same(lines[row].path, lines[row - 1usize].path) { total += lines[row].path.len + 4usize }
        row += 1usize
    }
    ret total
}

fn uleb(output: *emit_x64.Buffer, value: usize) -> err {
    var rest = value
    while true {
        var part = rest % 128usize
        rest = rest / 128usize
        if rest != 0usize { part += 128usize }
        try emit_x64.byte(output, part)
        if rest == 0usize { break }
    }
    ret ok
}

// A signed LEB128 from a magnitude and a sign: a negative value's groups are the
// complement of those of its magnitude less one.
fn sleb(output: *emit_x64.Buffer, magnitude: usize, negative: bool) -> err {
    var rest = magnitude
    if negative { rest = magnitude - 1usize }
    while true {
        let part = rest % 128usize
        rest = rest / 128usize
        let last = rest == 0usize && part < 64usize
        var encoded = part
        if negative { encoded = 127usize - part }
        if !last { encoded += 128usize }
        try emit_x64.byte(output, encoded)
        if last { break }
    }
    ret ok
}

fn section_header(output: *emit_x64.Buffer, name: usize, kind: usize, flags: usize, address: usize, offset: usize, size: usize, link: usize, info: usize, alignment: usize, entry_size: usize) -> err {
    try emit_x64.little_u32(output, name)
    try emit_x64.little_u32(output, kind)
    try emit_x64.little_u64(output, flags)
    try emit_x64.little_u64(output, address)
    try emit_x64.little_u64(output, offset)
    try emit_x64.little_u64(output, size)
    try emit_x64.little_u32(output, link)
    try emit_x64.little_u32(output, info)
    try emit_x64.little_u64(output, alignment)
    try emit_x64.little_u64(output, entry_size)
    ret ok
}

// The line program's registers as the rows have left them.
type LineState = struct {
    file: usize,
    line: usize,
    offset: usize,
    open: bool,
}

// One row: a sequence opened at its address, the file when it changes, the address and
// the line advanced, a copy. A row behind the last starts a sequence of its own.
fn line_row(output: *emit_x64.Buffer, state: *LineState, code_address: usize, offset: usize, file: usize, line: usize) -> err {
    if state.open && offset < state.offset {
        try append_blob(output, "\x00\x01\x01")
        state.open = false
    }
    if !state.open {
        try append_blob(output, "\x00\x09\x02")
        try emit_x64.little_u64(output, code_address + offset)
        state.file = 1usize
        state.line = 1usize
        state.offset = offset
        state.open = true
    }
    if file != state.file {
        state.file = file
        try emit_x64.byte(output, 4usize)
        try uleb(output, file)
    }
    if offset > state.offset {
        try emit_x64.byte(output, 2usize)
        try uleb(output, offset - state.offset)
        state.offset = offset
    }
    if line != state.line {
        try emit_x64.byte(output, 3usize)
        if line > state.line { try sleb(output, line - state.line, false) }
        if line < state.line { try sleb(output, state.line - line, true) }
        state.line = line
    }
    ret emit_x64.byte(output, 1usize)
}

// (D1582) The vars of the function whose code starts at `start` in the machine buffer:
// they arrive in code order.
fn debug_vars_of(builder: *nir.Builder, start: usize) -> (usize, usize) {
    var low = 0usize
    var high = builder.debug.var_count
    while low < high {
        let middle = low + (high - low) / 2usize
        if builder.debug.vars[middle].function_start < start { low = middle + 1usize } else { high = middle }
    }
    var count = 0usize
    while low + count < builder.debug.var_count && builder.debug.vars[low + count].function_start == start { count += 1usize }
    ret (low, count)
}

// A named local's first record, which later pieces (`kind` plus 16) continue; a saved
// register's record (`kind` 4) is the frame description's.
fn local_head(placed: nir.DebugVar) -> bool {
    ret placed.kind >= 1usize && placed.kind <= 5usize && placed.kind != 4usize
}

fn var_pieces_end(builder: *nir.Builder, at: usize, limit: usize) -> usize {
    var end = at + 1usize
    while end < limit && builder.debug.vars[end].kind > 16usize { end += 1usize }
    ret end
}

fn whole_function(placed: nir.DebugVar, start: usize, end: usize) -> bool {
    ret placed.start <= start && placed.end >= end
}

fn sleb_size(magnitude: usize) -> usize {
    var size = 1usize
    var rest = magnitude / 64usize
    while rest != 0usize {
        size += 1usize
        rest = rest / 128usize
    }
    ret size
}

// A var's DWARF location: its register (DW_OP_reg), memory at a register and a
// displacement (DW_OP_breg), or the address held there (and DW_OP_deref).
fn location_size(placed: nir.DebugVar) -> usize {
    if placed.kind % 16usize == 1usize { ret 1usize }
    var magnitude = placed.displacement
    if placed.displacement >= 9223372036854775808usize { magnitude = (0usize -% placed.displacement) - 1usize }
    var size = 1usize + sleb_size(magnitude)
    if placed.kind % 16usize == 3usize || placed.kind % 16usize == 5usize { size += 1usize }
    ret size
}

fn location_expression(output: *emit_x64.Buffer, placed: nir.DebugVar) -> err {
    if placed.kind % 16usize == 1usize { ret emit_x64.byte(output, 80usize + placed.register) }
    try emit_x64.byte(output, 112usize + placed.register)
    if placed.displacement >= 9223372036854775808usize { try sleb(output, 0usize -% placed.displacement, true) } else { try sleb(output, placed.displacement, false) }
    if placed.kind % 16usize == 3usize { try emit_x64.byte(output, 6usize) }
    // The address itself as the value (DW_OP_stack_value).
    if placed.kind % 16usize == 5usize { try emit_x64.byte(output, 159usize) }
    ret ok
}

// The type entries a link has written, by descriptor (D1582), and where each is from
// the unit's start. Open-addressed; a full table leaves the rest untyped.
type TypeMemo = struct {
    names: [2048]str,
    offsets: [2048]usize,
    info_offset: usize,
}

// The DWARF writer's tables in a region reserved for this link, cleared here: what
// `reserve` hands back is not promised to be zero.
// ponytail: the region (about 300 KB) is not released -- `e.os` has no release the
// bootstrap knows -- which a process that links once does not feel; a cached region
// when something links many times in one process.
type DwarfScratch = struct { memo: *TypeMemo, paths: []str, path_heads: []usize, path_next: []usize }

fn dwarf_scratch() -> (DwarfScratch, err) {
    var none: DwarfScratch = zero
    let capacity = 524288usize
    let (base, reserve_error) = os.reserve(capacity)
    if reserve_error != ok { ret (none, reserve_error) }
    let commit_error = os.commit(base, capacity)
    if commit_error != ok { ret (none, commit_error) }
    var region: mem.Arena = zero
    region.base = base
    region.cap = capacity
    let (memos, memos_error) = mem.alloc[TypeMemo](&region, 1usize)
    if memos_error != ok { ret (none, memos_error) }
    let (paths, paths_error) = mem.alloc[str](&region, 8192usize)
    if paths_error != ok { ret (none, paths_error) }
    let (heads, heads_error) = mem.alloc[usize](&region, 4096usize)
    if heads_error != ok { ret (none, heads_error) }
    let (links, links_error) = mem.alloc[usize](&region, 8192usize)
    if links_error != ok { ret (none, links_error) }
    let memo = &memos[0usize]
    memo.info_offset = 0usize
    var at = 0usize
    while at < 8192usize {
        if at < 2048usize {
            memo.names[at] = ""
            memo.offsets[at] = 0usize
        }
        if at < 4096usize { heads[at] = 0usize }
        paths[at] = ""
        links[at] = 0usize
        at += 1usize
    }
    var tables: DwarfScratch = zero
    tables.memo = memo
    tables.paths = paths
    tables.path_heads = heads
    tables.path_next = links
    ret (tables, ok)
}

fn memo_slot(memo: *TypeMemo, descriptor: str) -> (usize, bool) {
    var slot = codegen_x64.path_bucket(descriptor) % 2048usize
    var probes = 0usize
    while probes < 2048usize {
        if memo.names[slot].len == 0usize { ret (slot, false) }
        if check.same(memo.names[slot], descriptor) { ret (slot, true) }
        slot = (slot + 1usize) % 2048usize
        probes += 1usize
    }
    ret (2048usize, false)
}

fn digits_until(text: str, from: usize, stop: u8) -> (usize, usize, bool) {
    var value = 0usize
    var at = from
    while at < text.len && text[at] != stop {
        if text[at] < 48u8 || text[at] > 57u8 { ret (0usize, 0usize, false) }
        value = value * 10usize + usize(text[at] - 48u8)
        at += 1usize
    }
    if at >= text.len || at == from { ret (0usize, 0usize, false) }
    ret (value, at + 1usize, true)
}

fn pointer_die(output: *emit_x64.Buffer, memo: *TypeMemo, element: str) -> (usize, bool) {
    let (element_offset, has_element) = type_die(output, memo, element)
    if !has_element { ret (0usize, false) }
    let offset = output.count - memo.info_offset
    if uleb(output, 5usize) != ok || emit_x64.byte(output, 8usize) != ok || emit_x64.little_u32(output, element_offset) != ok { ret (0usize, false) }
    ret (offset, true)
}

fn member_die(output: *emit_x64.Buffer, name: str, type_offset: usize, offset: usize) -> bool {
    ret uleb(output, 8usize) == ok && append_text(output, name) == ok && emit_x64.byte(output, 0usize) == ok && emit_x64.little_u32(output, type_offset) == ok && emit_x64.little_u32(output, offset) == ok
}

// The end of the descriptor that starts at `at` within `text` -- a struct's field types
// are written one after another -- by the grammar `em.spell_type` writes.
fn descriptor_end(text: str, at: usize) -> (usize, bool) {
    if at >= text.len { ret (0usize, false) }
    // A union (`|`, `%`) reads as a struct (`{`, `#`) does (D1585).
    var head = text[at]
    if head == 124u8 { head = 123u8 }
    if head == 37u8 { head = 35u8 }
    // A pointer's or a slice's or an array's element follows its prefix.
    var element_at = 0usize
    if head == 42u8 {
        if at + 1usize < text.len && text[at + 1usize] == 63u8 { ret (at + 2usize, true) }
        element_at = at + 1usize
    }
    if head == 91u8 {
        if at + 1usize < text.len && text[at + 1usize] == 93u8 {
            element_at = at + 2usize
        } else {
            let (count, after, counted) = digits_until(text, at + 1usize, 93u8)
            if !counted { ret (0usize, false) }
            element_at = after
        }
    }
    if element_at != 0usize {
        let (element_end, element_ok) = descriptor_end(text, element_at)
        ret (element_end, element_ok)
    }
    if head == 35u8 || head == 123u8 || head == 61u8 {
        let (size, after_size, sized) = digits_until(text, at + 1usize, 58u8)
        let (length, after_length, measured) = digits_until(text, after_size, 58u8)
        if !sized || !measured || after_length + length > text.len { ret (0usize, false) }
        var cursor = after_length + length
        if head == 35u8 { ret (cursor, true) }
        let (count, after_count, has_count) = digits_until(text, cursor, 58u8)
        if !has_count { ret (0usize, false) }
        cursor = after_count
        var item = 0usize
        while item < count {
            let (item_length, after_item, has_item) = digits_until(text, cursor, 58u8)
            if !has_item || after_item + item_length > text.len { ret (0usize, false) }
            cursor = after_item + item_length
            if head == 61u8 && cursor < text.len && text[cursor] == 45u8 { cursor += 1usize }
            let (number, after_number, has_number) = digits_until(text, cursor, 58u8)
            if !has_number { ret (0usize, false) }
            cursor = after_number
            if head == 123u8 {
                let (field_end, field_ok) = descriptor_end(text, cursor)
                if !field_ok || field_end >= text.len || text[field_end] != 59u8 { ret (0usize, false) }
                cursor = field_end + 1usize
            }
            item += 1usize
        }
        ret (cursor, true)
    }
    var end = at
    while end < text.len && ((text[end] >= 97u8 && text[end] <= 122u8) || (text[end] >= 48u8 && text[end] <= 57u8)) { end += 1usize }
    ret (end, end > at)
}

// A struct's entry (`{`) and its members, or an enum's (`=`) and its enumerators: the
// field types written first, so the members refer back to them.
fn aggregate_die(output: *emit_x64.Buffer, memo: *TypeMemo, descriptor: str) -> (usize, bool) {
    let is_union = descriptor[0usize] == 124u8
    var head = descriptor[0usize]
    if is_union { head = 123u8 }
    let (size, after_size, sized) = digits_until(descriptor, 1usize, 58u8)
    let (length, after_length, measured) = digits_until(descriptor, after_size, 58u8)
    if !sized || !measured || after_length + length > descriptor.len { ret (0usize, false) }
    let name = descriptor[after_length..after_length + length]
    let (count, first_item, has_count) = digits_until(descriptor, after_length + length, 58u8)
    if !has_count { ret (0usize, false) }
    var cursor = first_item
    var item = 0usize
    if head == 123u8 {
        while item < count {
            let (item_length, after_item, has_item) = digits_until(descriptor, cursor, 58u8)
            if !has_item { ret (0usize, false) }
            let (field_offset, field_type_at, has_offset) = digits_until(descriptor, after_item + item_length, 58u8)
            let (field_end, field_ok) = descriptor_end(descriptor, field_type_at)
            if !has_offset || !field_ok { ret (0usize, false) }
            let (field_type, has_type) = type_die(output, memo, descriptor[field_type_at..field_end])
            let (field_slot, field_known) = memo_slot(memo, descriptor[field_type_at..field_end])
            if !has_type || !field_known { ret (0usize, false) }
            cursor = field_end + 1usize
            item += 1usize
        }
    }
    let offset = output.count - memo.info_offset
    if head == 123u8 {
        var entry = 7usize
        if is_union { entry = 22usize }
        if uleb(output, entry) != ok || append_text(output, name) != ok || emit_x64.byte(output, 0usize) != ok || emit_x64.little_u32(output, size) != ok { ret (0usize, false) }
    } else {
        if uleb(output, 18usize) != ok || append_text(output, name) != ok || emit_x64.byte(output, 0usize) != ok || emit_x64.byte(output, size) != ok { ret (0usize, false) }
    }
    cursor = first_item
    item = 0usize
    while item < count {
        let (item_length, after_item, has_item) = digits_until(descriptor, cursor, 58u8)
        if !has_item { ret (0usize, false) }
        let item_name = descriptor[after_item..after_item + item_length]
        cursor = after_item + item_length
        if head == 123u8 {
            let (field_offset, field_type_at, has_offset) = digits_until(descriptor, cursor, 58u8)
            let (field_end, field_ok) = descriptor_end(descriptor, field_type_at)
            let (field_slot, field_known) = memo_slot(memo, descriptor[field_type_at..field_end])
            if !has_offset || !field_ok || !field_known { ret (0usize, false) }
            if !member_die(output, item_name, memo.offsets[field_slot], field_offset) { ret (0usize, false) }
            cursor = field_end + 1usize
        } else {
            var negative = false
            if cursor < descriptor.len && descriptor[cursor] == 45u8 {
                negative = true
                cursor += 1usize
            }
            let (value, after_value, has_value) = digits_until(descriptor, cursor, 58u8)
            if !has_value { ret (0usize, false) }
            if uleb(output, 19usize) != ok || append_text(output, item_name) != ok || emit_x64.byte(output, 0usize) != ok || sleb(output, value, negative && value != 0usize) != ok { ret (0usize, false) }
            cursor = after_value
        }
        item += 1usize
    }
    if emit_x64.byte(output, 0usize) != ok { ret (0usize, false) }
    ret (offset, true)
}

// A descriptor's entry, written once (its elements first) and then found: the base
// types by name, `u8` as characters behind a `str`, pointers, the two words of a
// slice, arrays with their count, and a structure of a size for anything else.
fn type_die(output: *emit_x64.Buffer, memo: *TypeMemo, descriptor: str) -> (usize, bool) {
    let (known_slot, known) = memo_slot(memo, descriptor)
    if known { ret (memo.offsets[known_slot], true) }
    if known_slot >= 2048usize || descriptor.len == 0usize { ret (0usize, false) }
    var offset = 0usize
    if descriptor[0usize] == 42u8 {
        if check.same(descriptor, "*?") {
            offset = output.count - memo.info_offset
            if uleb(output, 6usize) != ok || emit_x64.byte(output, 8usize) != ok { ret (0usize, false) }
        } else {
            let (pointer, has_pointer) = pointer_die(output, memo, descriptor[1usize..descriptor.len])
            if !has_pointer { ret (0usize, false) }
            offset = pointer
        }
    } else {
    if check.same(descriptor, "str") || (descriptor.len > 2usize && descriptor[0usize] == 91u8 && descriptor[1usize] == 93u8) {
        var element = "c8"
        if !check.same(descriptor, "str") { element = descriptor[2usize..descriptor.len] }
        let (pointer, has_pointer) = pointer_die(output, memo, element)
        let (length, has_length) = type_die(output, memo, "usize")
        if !has_pointer || !has_length { ret (0usize, false) }
        offset = output.count - memo.info_offset
        if uleb(output, 7usize) != ok || append_text(output, descriptor) != ok || emit_x64.byte(output, 0usize) != ok || emit_x64.little_u32(output, 16usize) != ok { ret (0usize, false) }
        if !member_die(output, "ptr", pointer, 0usize) || !member_die(output, "len", length, 8usize) || emit_x64.byte(output, 0usize) != ok { ret (0usize, false) }
    } else {
    if descriptor[0usize] == 91u8 {
        let (count, rest, counted) = digits_until(descriptor, 1usize, 93u8)
        if !counted { ret (0usize, false) }
        let (element, has_element) = type_die(output, memo, descriptor[rest..descriptor.len])
        if !has_element { ret (0usize, false) }
        offset = output.count - memo.info_offset
        if uleb(output, 9usize) != ok || emit_x64.little_u32(output, element) != ok || uleb(output, 10usize) != ok || emit_x64.little_u32(output, count) != ok || emit_x64.byte(output, 0usize) != ok { ret (0usize, false) }
    } else {
    if descriptor[0usize] == 123u8 || descriptor[0usize] == 61u8 || descriptor[0usize] == 124u8 {
        let (aggregate, has_aggregate) = aggregate_die(output, memo, descriptor)
        if !has_aggregate { ret (0usize, false) }
        offset = aggregate
    } else {
    if descriptor[0usize] == 35u8 || descriptor[0usize] == 37u8 {
        let (size, after_size, sized) = digits_until(descriptor, 1usize, 58u8)
        let (length, after_length, measured) = digits_until(descriptor, after_size, 58u8)
        if !sized || !measured || after_length + length != descriptor.len { ret (0usize, false) }
        offset = output.count - memo.info_offset
        var declaration = 11usize
        if descriptor[0usize] == 37u8 { declaration = 21usize }
        if uleb(output, declaration) != ok || append_text(output, descriptor[after_length..descriptor.len]) != ok || emit_x64.byte(output, 0usize) != ok || emit_x64.little_u32(output, size) != ok { ret (0usize, false) }
    } else {
        var name = descriptor
        var encoding = 0usize
        var size = 0usize
        if check.same(descriptor, "bool") {
            encoding = 2usize
            size = 1usize
        }
        if check.same(descriptor, "err") {
            encoding = 7usize
            size = 4usize
        }
        if check.same(descriptor, "c8") {
            name = "u8"
            encoding = 8usize
            size = 1usize
        }
        if encoding == 0usize && descriptor.len >= 2usize {
            if descriptor[0usize] == 117u8 { encoding = 7usize }
            if descriptor[0usize] == 105u8 { encoding = 5usize }
            if descriptor[0usize] == 102u8 { encoding = 4usize }
            if check.same(descriptor, "usize") || check.same(descriptor, "isize") {
                size = 8usize
            } else {
                var bits = 0usize
                var at = 1usize
                while at < descriptor.len && descriptor[at] >= 48u8 && descriptor[at] <= 57u8 {
                    bits = bits * 10usize + usize(descriptor[at] - 48u8)
                    at += 1usize
                }
                if at == descriptor.len { size = bits / 8usize }
            }
        }
        if encoding == 0usize || size == 0usize { ret (0usize, false) }
        offset = output.count - memo.info_offset
        if uleb(output, 4usize) != ok || append_text(output, name) != ok || emit_x64.byte(output, 0usize) != ok || emit_x64.byte(output, encoding) != ok || emit_x64.byte(output, size) != ok { ret (0usize, false) }
    }
    }
    }
    }
    }
    // The slot again: the elements written meanwhile may have taken it.
    let (slot, found) = memo_slot(memo, descriptor)
    if !found && slot < 2048usize {
        memo.names[slot] = descriptor
        memo.offsets[slot] = offset
    }
    ret (offset, true)
}

fn function_name(output: *emit_x64.Buffer, placed: nir.Function) -> err {
    try append_text(output, placed.module_name)
    try emit_x64.byte(output, 46usize)
    try append_text(output, placed.name)
    try emit_x64.byte(output, 0usize)
    ret ok
}

// `text_end` is where the code and the runtime end, and the `.nepersym` table starts
// (D1586).
fn append_debug(builder: *nir.Builder, output: *emit_x64.Buffer, machine: *emit_x64.Buffer, machine_start: usize, function_offsets: []usize, lines: []codegen_x64.LineEntry, table_at: usize, text_start: usize, text_end: usize) -> err {
    let base = 4194304usize
    let code_address = base + machine_start
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    // The symbols: a null one, the startup as `_start`, then one local function per
    // placed function.
    let symtab_offset = align_up_to(output.count, 8usize)
    try pad_to(output, symtab_offset)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 0usize)
    try little_u16(output, 1usize)
    try emit_x64.little_u64(output, base + text_start)
    try emit_x64.little_u64(output, machine_start - text_start)
    var symbols = 2usize
    var name_at = 8usize
    var at = 0usize
    var placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) {
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, at, table_at)
            if end_error != ok { ret end_error }
            try emit_x64.little_u32(output, name_at)
            try emit_x64.byte(output, 2usize)
            try emit_x64.byte(output, 0usize)
            try little_u16(output, 1usize)
            try emit_x64.little_u64(output, code_address + function_offsets[at])
            try emit_x64.little_u64(output, end - function_offsets[at])
            name_at += builder.functions[at].module_name.len + builder.functions[at].name.len + 2usize
            symbols += 1usize
        }
        at += 1usize
    }
    let strtab_offset = output.count
    try append_blob(output, "\x00_start\x00")
    at = 0usize
    placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) { try function_name(output, builder.functions[at]) }
        at += 1usize
    }
    var dwarf: DwarfSections = zero
    try write_dwarf(builder, output, function_offsets, lines, table_at, code_address, main_index, 1usize, &dwarf)
    let names_offset = output.count
    try append_blob(output, "\x00.text\x00.nepersym\x00.symtab\x00.strtab\x00.debug_abbrev\x00.debug_info\x00.debug_line\x00.shstrtab\x00.debug_loc\x00.debug_frame\x00")
    let names_end = output.count
    let headers_offset = align_up_to(output.count, 8usize)
    try pad_to(output, headers_offset)
    try section_header(output, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    try section_header(output, 1usize, 1usize, 6usize, base + text_start, text_start, text_end - text_start, 0usize, 0usize, 16usize, 0usize)
    try section_header(output, 7usize, 1usize, 2usize, base + text_end, text_end, machine.count - table_at, 0usize, 0usize, 8usize, 0usize)
    try section_header(output, 17usize, 2usize, 0usize, 0usize, symtab_offset, strtab_offset - symtab_offset, 4usize, symbols, 8usize, 24usize)
    try section_header(output, 25usize, 3usize, 0usize, 0usize, strtab_offset, dwarf.abbrev - strtab_offset, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 33usize, 1usize, 0usize, 0usize, dwarf.abbrev, dwarf.abbrev_end - dwarf.abbrev, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 47usize, 1usize, 0usize, 0usize, dwarf.info, dwarf.info_end - dwarf.info, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 59usize, 1usize, 0usize, 0usize, dwarf.line, dwarf.line_end - dwarf.line, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 71usize, 3usize, 0usize, 0usize, names_offset, names_end - names_offset, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 81usize, 1usize, 0usize, 0usize, dwarf.loc, dwarf.loc_end - dwarf.loc, 0usize, 0usize, 1usize, 0usize)
    try section_header(output, 92usize, 1usize, 0usize, 0usize, dwarf.frame, dwarf.frame_end - dwarf.frame, 0usize, 0usize, 8usize, 0usize)
    // The ELF header's section fields: the table's offset, its entry size, its count
    // and the index of the section names.
    try patch_little_u64(output, 40usize, headers_offset)
    output.bytes[58usize] = 64u8
    output.bytes[60usize] = 11u8
    output.bytes[62usize] = 8u8
    ret ok
}

// (D1583) Where `write_dwarf` put each section, as offsets into the output.
type DwarfSections = struct {
    abbrev: usize,
    abbrev_end: usize,
    loc: usize,
    loc_end: usize,
    info: usize,
    info_end: usize,
    line: usize,
    line_end: usize,
    frame: usize,
    frame_end: usize,
}

fn pad_aligned(output: *emit_x64.Buffer, alignment: usize) -> err {
    ret pad_to(output, align_up_to(output.count, alignment))
}

// (D1583) The DWARF both linkers write -- abbreviations, location lists, the unit and
// its entries, the line program and the frame description -- each section starting on
// a multiple of `alignment` (a PE image's file alignment; one for ELF). `code_address`
// is where the machine buffer's first byte is loaded.
fn write_dwarf(builder: *nir.Builder, output: *emit_x64.Buffer, function_offsets: []usize, lines: []codegen_x64.LineEntry, table_at: usize, code_address: usize, main_index: usize, alignment: usize, sections: *DwarfSections) -> err {
    var at = 0usize
    var placed_max = 0usize
    try pad_aligned(output, alignment)
    let abbrev_offset = output.count
    sections.abbrev = abbrev_offset
    // 1: the compile unit -- producer, language, name, low_pc, high_pc, stmt_list.
    try append_blob(output, "\x01\x11\x01\x25\x08\x13\x05\x03\x08\x11\x01\x12\x07\x10\x17\x00\x00")
    // 2: a subprogram -- name, low_pc, high_pc, external; 3: the same, and the program's
    // main (DW_AT_main_subprogram), where a debugger's backtrace stops.
    try append_blob(output, "\x02\x2e\x00\x03\x08\x11\x01\x12\x07\x3f\x19\x00\x00")
    try append_blob(output, "\x03\x2e\x00\x03\x08\x11\x01\x12\x07\x3f\x19\x6a\x19\x00\x00")
    // (D1582) The locals: 4 a base type, 5 a pointer, 6 a pointer to anything, 7 a
    // structure and 8 its member, 9 an array and 10 its count, 11 a structure known by
    // its size alone, 12 and 13 subprograms 2 and 3 with children, 14 and 15 a parameter
    // placed for the whole function or by a location list, 16 and 17 a variable so.
    try append_blob(output, "\x04\x24\x00\x03\x08\x3e\x0b\x0b\x0b\x00\x00")
    try append_blob(output, "\x05\x0f\x00\x0b\x0b\x49\x13\x00\x00")
    try append_blob(output, "\x06\x0f\x00\x0b\x0b\x00\x00")
    try append_blob(output, "\x07\x13\x01\x03\x08\x0b\x06\x00\x00")
    try append_blob(output, "\x08\x0d\x00\x03\x08\x49\x13\x38\x06\x00\x00")
    try append_blob(output, "\x09\x01\x01\x49\x13\x00\x00")
    try append_blob(output, "\x0a\x21\x00\x37\x06\x00\x00")
    // 11 is a declaration: a debugger finds the full structure of that name if there is one.
    try append_blob(output, "\x0b\x13\x00\x03\x08\x0b\x06\x3c\x19\x00\x00")
    try append_blob(output, "\x0c\x2e\x01\x03\x08\x11\x01\x12\x07\x3f\x19\x00\x00")
    try append_blob(output, "\x0d\x2e\x01\x03\x08\x11\x01\x12\x07\x3f\x19\x6a\x19\x00\x00")
    try append_blob(output, "\x0e\x05\x00\x03\x08\x49\x13\x02\x18\x00\x00")
    try append_blob(output, "\x0f\x05\x00\x03\x08\x49\x13\x02\x17\x00\x00")
    try append_blob(output, "\x10\x34\x00\x03\x08\x49\x13\x02\x18\x00\x00")
    try append_blob(output, "\x11\x34\x00\x03\x08\x49\x13\x02\x17\x00\x00")
    // 18 an enumeration and 19 its enumerator.
    try append_blob(output, "\x12\x04\x01\x03\x08\x0b\x0b\x00\x00")
    try append_blob(output, "\x13\x28\x00\x03\x08\x1c\x0d\x00\x00")
    // (D1584) 20 a lexical block: its range, and the locals its block declares.
    try append_blob(output, "\x14\x0b\x01\x11\x01\x12\x07\x00\x00")
    // (D1585) 21 a union known by its name and size, 22 a union and its members.
    try append_blob(output, "\x15\x17\x00\x03\x08\x0b\x06\x3c\x19\x00\x00")
    try append_blob(output, "\x16\x17\x01\x03\x08\x0b\x06\x00\x00\x00")
    // The location lists, before the entries that name them: a var placed for part of its
    // function has one, in the order the entries are written below.
    sections.abbrev_end = output.count
    try pad_aligned(output, alignment)
    let loc_offset = output.count
    sections.loc = loc_offset
    at = 0usize
    placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) {
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, at, table_at)
            if end_error != ok { ret end_error }
            let (vars_first, vars_count) = debug_vars_of(builder, function_offsets[at])
            var var_at = vars_first
            while var_at < vars_first + vars_count {
                let placed = builder.debug.vars[var_at]
                let pieces_end = var_pieces_end(builder, var_at, vars_first + vars_count)
                if local_head(placed) && !(pieces_end == var_at + 1usize && whole_function(placed, function_offsets[at], end)) {
                    var piece_at = var_at
                    while piece_at < pieces_end {
                        let piece = builder.debug.vars[piece_at]
                        try emit_x64.little_u64(output, piece.start)
                        try emit_x64.little_u64(output, piece.end)
                        try little_u16(output, location_size(piece))
                        try location_expression(output, piece)
                        piece_at += 1usize
                    }
                    try emit_x64.little_u64(output, 0usize)
                    try emit_x64.little_u64(output, 0usize)
                }
                var_at = pieces_end
            }
        }
        at += 1usize
    }
    sections.loc_end = output.count
    try pad_aligned(output, alignment)
    let info_offset = output.count
    sections.info = info_offset
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 4usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.byte(output, 8usize)
    try uleb(output, 1usize)
    try append_text(output, "neper")
    try emit_x64.byte(output, 0usize)
    // DW_LANG_C99: the nearest a foreign debugger knows, and what it prints types as.
    try little_u16(output, 12usize)
    if lines.len != 0usize { try append_text(output, lines[0usize].path) }
    try emit_x64.byte(output, 0usize)
    try emit_x64.little_u64(output, code_address)
    try emit_x64.little_u64(output, table_at)
    try emit_x64.little_u32(output, 0usize)
    // Every type a var names, written before the subprograms so each entry refers back
    // to its type's.
    // (D1605) The memo and the path tables live in a region of their own: as locals
    // they were 270 KB of a main-thread stack the `build` spelling, which nests
    // `dispatch`, had already half used, and Windows overflowed it.
    let (scratch, scratch_error) = dwarf_scratch()
    if scratch_error != ok { ret scratch_error }
    let memo = scratch.memo
    memo.info_offset = info_offset
    // The struct definitions first: the vars and fields name them.
    var definition_at = 0usize
    while definition_at < builder.debug.definition_count {
        let (definition_offset, has_definition) = type_die(output, memo, builder.debug.definitions[definition_at])
        definition_at += 1usize
    }
    var type_at = 0usize
    while type_at < builder.debug.var_count {
        let (type_offset, has_type) = type_die(output, memo, builder.debug.vars[type_at].descriptor)
        builder.debug.vars[type_at].type_entry = 0usize
        if has_type { builder.debug.vars[type_at].type_entry = type_offset + 1usize }
        type_at += 1usize
    }
    var loc_cursor = 0usize
    at = 0usize
    placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) {
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, at, table_at)
            if end_error != ok { ret end_error }
            let (vars_first, vars_count) = debug_vars_of(builder, function_offsets[at])
            var locals = 0usize
            var local_at = vars_first
            while local_at < vars_first + vars_count {
                if local_head(builder.debug.vars[local_at]) { locals += 1usize }
                local_at += 1usize
            }
            var code = 2usize
            if at == main_index { code = 3usize }
            if locals != 0usize { code += 10usize }
            try uleb(output, code)
            try function_name(output, builder.functions[at])
            try emit_x64.little_u64(output, code_address + function_offsets[at])
            try emit_x64.little_u64(output, end - function_offsets[at])
            if locals != 0usize {
                // (D1584) The open lexical blocks' ends, innermost last. The locals come
                // in binding order, so a block's scopes nest: one that ends where the
                // innermost does is that block's; one that ends sooner opens a block inside.
                var scope_ends: [64]usize = zero
                var depth = 0usize
                var var_at = vars_first
                while var_at < vars_first + vars_count {
                    let placed = builder.debug.vars[var_at]
                    let pieces_end = var_pieces_end(builder, var_at, vars_first + vars_count)
                    if !local_head(placed) {
                        var_at = pieces_end
                        continue
                    }
                    if placed.parameter == 0usize {
                        while depth != 0usize && scope_ends[depth - 1usize] <= placed.scope_start {
                            try emit_x64.byte(output, 0usize)
                            depth = depth - 1usize
                        }
                        let nested = depth == 0usize || placed.scope_end < scope_ends[depth - 1usize]
                        if nested && depth < scope_ends.len && placed.scope_end > placed.scope_start {
                            try uleb(output, 20usize)
                            try emit_x64.little_u64(output, code_address + placed.scope_start)
                            try emit_x64.little_u64(output, placed.scope_end - placed.scope_start)
                            scope_ends[depth] = placed.scope_end
                            depth += 1usize
                        }
                    }
                    let whole = pieces_end == var_at + 1usize && whole_function(placed, function_offsets[at], end)
                    let has_type = placed.type_entry != 0usize
                    var type_offset = 0usize
                    if has_type { type_offset = placed.type_entry - 1usize }
                    if has_type {
                        var entry = 16usize
                        if placed.parameter != 0usize { entry = 14usize }
                        if !whole { entry += 1usize }
                        try uleb(output, entry)
                        try append_text(output, placed.name)
                        try emit_x64.byte(output, 0usize)
                        try emit_x64.little_u32(output, type_offset)
                        if whole {
                            try uleb(output, location_size(placed))
                            try location_expression(output, placed)
                        } else {
                            try emit_x64.little_u32(output, loc_cursor)
                        }
                    }
                    // The list was written for it whether or not its type has an entry.
                    if !whole {
                        var piece_at = var_at
                        while piece_at < pieces_end {
                            loc_cursor += 18usize + location_size(builder.debug.vars[piece_at])
                            piece_at += 1usize
                        }
                        loc_cursor += 16usize
                    }
                    var_at = pieces_end
                }
                while depth != 0usize {
                    try emit_x64.byte(output, 0usize)
                    depth = depth - 1usize
                }
                try emit_x64.byte(output, 0usize)
            }
        }
        at += 1usize
    }
    try emit_x64.byte(output, 0usize)
    try emit_x64.patch_little_u32(output, info_offset, output.count - info_offset - 4usize)
    // The line program: the files in the order the rows first name them, then a row
    // per entry -- the file when it changes, the address and line advanced, a copy.
    sections.info_end = output.count
    try pad_aligned(output, alignment)
    let line_offset = output.count
    sections.line = line_offset
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 4usize)
    let header_length_at = output.count
    try emit_x64.little_u32(output, 0usize)
    try append_blob(output, "\x01\x01\x01\xfb\x0e\x0d\x00\x01\x01\x01\x01\x00\x00\x00\x01\x00\x00\x01\x00")
    let paths = scratch.paths
    let path_heads = scratch.path_heads
    let path_next = scratch.path_next
    var path_count = 0usize
    var last_path = 0usize
    var row = 0usize
    while row < lines.len {
        let (path_index, found) = codegen_x64.path_position(paths[..path_count], lines[row].path, &last_path, path_heads[..], path_next[..])
        if !found {
            if path_count == paths.len { ret InvalidExecutable }
            paths[path_count] = lines[row].path
            let bucket = codegen_x64.path_bucket(lines[row].path)
            path_next[path_count] = path_heads[bucket]
            path_heads[bucket] = path_count + 1usize
            path_count += 1usize
            try append_text(output, lines[row].path)
            try append_blob(output, "\x00\x00\x00\x00")
        }
        row += 1usize
    }
    try emit_x64.byte(output, 0usize)
    try emit_x64.patch_little_u32(output, header_length_at, output.count - header_length_at - 4usize)
    // Function by function in code order, so every row belongs to a placed function and
    // each function's first row is at its entry: a debugger skips a prologue to the
    // function's second row, and without one at the entry it finds none to skip.
    var state: LineState = zero
    var cursor = 0usize
    at = 0usize
    placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) {
            let start = function_offsets[at]
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, at, table_at)
            if end_error != ok { ret end_error }
            let (first, count) = codegen_x64.line_rows_from(lines, lines.len, start, end, &cursor)
            var row_at = first
            while row_at < first + count {
                let entry = lines[row_at]
                let (path_index, found) = codegen_x64.path_position(paths[..path_count], entry.path, &last_path, path_heads[..], path_next[..])
                if !found { ret InvalidExecutable }
                if row_at == first && start < entry.offset { try line_row(output, &state, code_address, start, path_index + 1usize, usize(entry.line)) }
                try line_row(output, &state, code_address, entry.offset, path_index + 1usize, usize(entry.line))
                row_at += 1usize
            }
        }
        at += 1usize
    }
    if state.open {
        if table_at > state.offset {
            try emit_x64.byte(output, 2usize)
            try uleb(output, table_at - state.offset)
        }
        try append_blob(output, "\x00\x01\x01")
    }
    try emit_x64.patch_little_u32(output, line_offset, output.count - line_offset - 4usize)
    // The frame description (section 13's unwind info): one CIE -- the return address at
    // the CFA less 8, the CFA the stack pointer plus 8 at entry -- and per placed function
    // an FDE: after `push rbp` the CFA is 16 above the stack pointer and rbp is saved
    // below it, after `mov rbp, rsp` the CFA is rbp plus 16, and each callee-saved
    // register the function uses is in its slot.
    sections.line_end = output.count
    try pad_aligned(output, alignment)
    let frame_offset = output.count
    sections.frame = frame_offset
    try append_blob(output, "\x14\x00\x00\x00\xff\xff\xff\xff\x01\x00\x01\x78\x10\x0c\x07\x08\x90\x01\x00\x00\x00\x00\x00\x00")
    at = 0usize
    placed_max = 0usize
    while at < builder.function_count {
        if codegen_x64.is_placed_after(builder, function_offsets, at, &placed_max) {
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, at, table_at)
            if end_error != ok { ret end_error }
            let fde_offset = output.count
            try emit_x64.little_u32(output, 0usize)
            try emit_x64.little_u32(output, 0usize)
            try emit_x64.little_u64(output, code_address + function_offsets[at])
            try emit_x64.little_u64(output, end - function_offsets[at])
            try append_blob(output, "\x41\x0e\x10\x86\x02\x43\x0d\x06")
            let (vars_first, vars_count) = debug_vars_of(builder, function_offsets[at])
            var saved_at = vars_first
            while saved_at < vars_first + vars_count {
                let saved = builder.debug.vars[saved_at]
                if saved.kind == 4usize && saved.register < 64usize {
                    try emit_x64.byte(output, 128usize + saved.register)
                    try uleb(output, (16usize + (0usize -% saved.displacement)) / 8usize)
                }
                saved_at += 1usize
            }
            while (output.count - fde_offset) % 8usize != 0usize { try emit_x64.byte(output, 0usize) }
            try emit_x64.patch_little_u32(output, fde_offset, output.count - fde_offset - 4usize)
        }
        at += 1usize
    }
    sections.frame_end = output.count
    ret ok
}

fn self_test() -> err {
    var functions: [1]nir.Function = zero
    var blocks: [1]nir.Block = zero
    var instructions: [1]nir.Instruction = zero
    var operands: [1]usize = zero
    var references: [1]nir.FunctionRef = zero
    var strings: [1]nir.StringConstant = zero
    var builder: nir.Builder = zero
    try nir.init(&builder, functions[..], blocks[..], instructions[..], operands[..], references[..], strings[..])
    builder.function_count = 1usize
    var main_function: nir.Function = zero
    main_function.name = "main"
    functions[0usize] = main_function
    var machine_storage: [1]u8 = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var executable_storage: [8192]u8 = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    var lines: [1]codegen_x64.LineEntry = zero
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, lines[0usize..0usize], machine.count, &executable)
    // The startup is fixed in this file, and a program with no relocation into the runtime
    // gets none of it (D150, D151): the loaded image is the headers, the startup and the
    // code, and the nine sections of D1581 follow it unloaded. Checking the segment size
    // keeps this test honest, and the machine code is checked where `write` puts it rather
    // than at a literal offset.
    let machine_start = 120usize + 267usize
    let total = machine_start + machine.count
    if executable.count <= total || executable.bytes[60usize] != 11u8 || executable.bytes[62usize] != 8u8 { ret InvalidExecutable }
    if executable.bytes[0usize] != 127u8 || executable.bytes[16usize] != 2u8 || executable.bytes[18usize] != 62u8 || executable.bytes[24usize] != 120u8 || executable.bytes[25usize] != 0u8 || executable.bytes[26usize] != 64u8 { ret InvalidExecutable }
    if executable.bytes[64usize] != 1u8 || executable.bytes[68usize] != 5u8 { ret InvalidExecutable }
    if executable.bytes[96usize] != u8(total % 256usize) || executable.bytes[97usize] != u8((total / 256usize) % 256usize) { ret InvalidExecutable }
    if executable.bytes[120usize] != 73u8 || executable.bytes[351usize] != 232u8 { ret InvalidExecutable }
    if executable.bytes[machine_start] != 195u8 { ret InvalidExecutable }
    ret ok
}
