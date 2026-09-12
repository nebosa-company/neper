// Minimal deterministic x86-64 ELF executable linker for closed modules.

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

fn append_startup(output: *emit_x64.Buffer) -> err {
    try append_blob(output, "\x49\x89\xe4\x31\xff\xbe\x00\x00\x00\x20\xba\x03\x00\x00\x00\x41\xba\x22\x00\x00\x00\x49\xc7\xc0\xff\xff\xff\xff\x45\x31\xc9\xb8\x09\x00\x00\x00\x0f\x05\x48\x85\xc0\x0f\x88\xae\x00\x00\x00\x49\x89\xc5\x4d\x8b\x34\x24\x4c\x89\xf3\x48\xc1\xe3\x04\x48\x81\xfb\x00\x00\x00\x20\x0f\x87\x93\x00\x00\x00\x45\x31\xff\x4d\x39\xf7\x73\x4c\x4f\x8b\x44\xfc\x08\x31\xc9\x41\x80\x3c\x08\x00\x74\x05")
    try append_blob(output, "\x48\xff\xc1\xeb\xf4\x48\x89\xd8\x48\x01\xc8\x72\x70\x48\x3d\x00\x00\x00\x20\x77\x68\x4d\x8d\x4c\x1d\x00\x4d\x89\xfa\x49\xc1\xe2\x04\x4f\x89\x4c\x15\x00\x4b\x89\x4c\x15\x08\x48\x89\xca\x4c\x89\xc6\x4c\x89\xcf\xf3\xa4\x48\x01\xd3\x49\xff\xc7\xeb\xaf\x48\x83\xec\x30\x4c\x89\x2c\x24\x48\xc7\x44\x24\x08\x00\x00\x00\x20\x48\x89\x5c\x24\x10\x4c\x89\x6c\x24\x18\x4c\x89\x74\x24\x20\x48\x8d")
    ret append_blob(output, "\x3c\x24\x48\x8d\x74\x24\x18\xe8\x00\x00\x00\x00\x85\xc0\x40\x0f\x95\xc7\x40\x0f\xb6\xff\xb8\x3c\x00\x00\x00\x0f\x05\xbf\x6f\x00\x00\x00\xb8\x3c\x00\x00\x00\x0f\x05\x0f\x0b")
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
        output.bytes[offset + at] = remaining % 256usize
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
        if item.has_initial && item.initial != 0usize {
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

fn write_dynamic(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    let base = 4194304usize
    let code_offset = 4096usize
    let startup_size = 235usize
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
    if rela_offset + rela_size > code_offset { ret InvalidExecutable }

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
    let machine_start = output.count
    var at = 0usize
    while at < machine.count {
        try emit_x64.byte(output, machine.bytes[at])
        at += 1usize
    }
    let runtime_start = output.count
    let (runtime_limit, runtime_limit_error) = runtime_prefix(builder, relocations, relocation_count)
    if runtime_limit_error != ok { ret runtime_limit_error }
    try runtime_elf_x64.append(output, runtime_limit)
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
    try emit_x64.patch_relative32(output, code_offset + 200usize, main_offset)
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
    ret ok
}

fn site_of(machine_start: usize, displacement_at: usize) -> usize {
    ret machine_start + displacement_at
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len { ret InvalidExecutable }
    if relocation_count > relocations.len { ret InvalidExecutable }
    // Only an `@import` makes this image need a loader. Without one it stays the
    // freestanding static executable it has always been, byte for byte.
    if nir.import_library_count(builder) != 0usize {
        ret write_dynamic(builder, machine, function_offsets, relocations, relocation_count, output)
    }
    let (main_index, main_error) = find_main(builder)
    if main_error != ok { ret main_error }
    // A second segment only when there is something to put in it. An image with no module-scope
    // `var` keeps the single read-execute segment it has always had, byte for byte -- which the
    // determinism harness compares, so the absence of the feature has to cost nothing.
    var segments = 1usize
    if builder.global_count != 0usize { segments = 2usize }
    // The code starts where the program headers end. The loader asks only that a segment's file
    // offset and address agree modulo the page, not that either be a page boundary; padding the
    // code out to 4096 cost an empty program half its size for nothing (D149). The address is
    // still the base plus the file offset, so every relocation below stays a file offset.
    let code_offset = 64usize + 56usize * segments
    let startup_size = 235usize
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
    let machine_start = output.count
    var at = 0usize
    while at < machine.count {
        try emit_x64.byte(output, machine.bytes[at])
        at += 1usize
    }
    let runtime_start = output.count
    let (runtime_limit, runtime_limit_error) = runtime_prefix(builder, relocations, relocation_count)
    if runtime_limit_error != ok { ret runtime_limit_error }
    try runtime_elf_x64.append(output, runtime_limit)
    let main_offset = machine_start + function_offsets[main_index]
    try emit_x64.patch_relative32(output, code_offset + 200usize, main_offset)
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
    if builder.global_count != 0usize {
        var area_alignment = 1usize
        var alignment_at = 0usize
        while alignment_at < builder.global_count {
            if builder.globals[alignment_at].alignment > area_alignment { area_alignment = builder.globals[alignment_at].alignment }
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
    var machine_storage: [1]usize = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var executable_storage: [8192]usize = zero
    var executable: emit_x64.Buffer = zero
    try emit_x64.init(&executable, executable_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, &executable)
    // The startup is fixed in this file, and a program with no relocation into the runtime
    // gets none of it (D150, D151): the image is the headers, the startup and the code.
    // Checking the total and the segment size keeps this test honest, and the machine code
    // is checked where `write` puts it rather than at a literal offset.
    let machine_start = 120usize + 235usize
    let total = machine_start + machine.count
    if executable.count != total { ret InvalidExecutable }
    if executable.bytes[0usize] != 127usize || executable.bytes[16usize] != 2usize || executable.bytes[18usize] != 62usize || executable.bytes[24usize] != 120usize || executable.bytes[25usize] != 0usize || executable.bytes[26usize] != 64usize { ret InvalidExecutable }
    if executable.bytes[64usize] != 1usize || executable.bytes[68usize] != 5usize { ret InvalidExecutable }
    if executable.bytes[96usize] != total % 256usize || executable.bytes[97usize] != (total / 256usize) % 256usize { ret InvalidExecutable }
    if executable.bytes[120usize] != 73usize || executable.bytes[319usize] != 232usize { ret InvalidExecutable }
    if executable.bytes[machine_start] != 195usize { ret InvalidExecutable }
    ret ok
}
