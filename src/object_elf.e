// Deterministic x86-64 ELF relocatable object serialization.

use check
use codegen_x64
use emit_x64
use nir

error Capacity
error InvalidObject

// What `em_link.host_runtime_symbol` answers: the reserved prefix of the host runtime.
fn host_runtime_symbol(name: str) -> bool {
    let prefix = "neper_"
    if name.len < prefix.len { ret false }
    var at = 0usize
    while at < prefix.len {
        if name[at] != prefix[at] { ret false }
        at += 1usize
    }
    ret true
}

type Symbol = struct {
    name: str,
    module: str,
    value: usize,
    size: usize,
    section: usize,
    string_offset: usize,
}

type Section = struct {
    name: usize,
    kind: usize,
    flags: usize,
    offset: usize,
    size: usize,
    link: usize,
    info: usize,
    alignment: usize,
    entry_size: usize,
}

fn widen_byte(value: u8) -> usize {
    var current = 0u8
    var result = 0usize
    while current < value {
        current += 1u8
        result += 1usize
    }
    ret result
}

fn little_u16(output: *emit_x64.Buffer, value: usize) -> err {
    try emit_x64.byte(output, value % 256usize)
    ret emit_x64.byte(output, value / 256usize % 256usize)
}

fn align(value: usize, amount: usize) -> usize {
    let rounded = value + amount - 1usize
    ret rounded / amount * amount
}

fn pad_to(output: *emit_x64.Buffer, offset: usize) -> err {
    if output.count > offset { ret InvalidObject }
    while output.count < offset { try emit_x64.byte(output, 0usize) }
    ret ok
}

fn append_text(output: *emit_x64.Buffer, text: str) -> err {
    var at = 0usize
    while at < text.len {
        try emit_x64.byte(output, widen_byte(text[at]))
        at += 1usize
    }
    ret ok
}

fn find_symbol(symbols: []Symbol, count: usize, module: str, name: str) -> (usize, bool) {
    var at = 1usize
    while at < count {
        if check.same(symbols[at].module, module) && check.same(symbols[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn write_section(output: *emit_x64.Buffer, section: Section) -> err {
    try emit_x64.little_u32(output, section.name)
    try emit_x64.little_u32(output, section.kind)
    try emit_x64.little_u64(output, section.flags)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, section.offset)
    try emit_x64.little_u64(output, section.size)
    try emit_x64.little_u32(output, section.link)
    try emit_x64.little_u32(output, section.info)
    try emit_x64.little_u64(output, section.alignment)
    ret emit_x64.little_u64(output, section.entry_size)
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, symbols: []Symbol, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || builder.function_count + 1usize > symbols.len || relocation_count > relocations.len { ret Capacity }
    var null_symbol: Symbol = zero
    symbols[0usize] = null_symbol
    var symbol_count = 1usize
    var function_at = 0usize
    var placed_max = 0usize
    while function_at < builder.function_count {
        // A folded function shares an earlier function's offset and gets size 0; a placed
        // one runs to the next higher offset (#24).
        var size = 0usize
        let start = function_offsets[function_at]
        if function_at == 0usize || start > placed_max {
            let (end, end_error) = codegen_x64.placed_end_after(builder, function_offsets, function_at, machine.count)
            if end_error != ok { ret end_error }
            size = end - start
            placed_max = start
        }
        symbols[symbol_count] = Symbol { name: builder.functions[function_at].name, module: builder.functions[function_at].module_name, value: start, size: size, section: 1usize, string_offset: 0usize }
        symbol_count += 1usize
        function_at += 1usize
    }
    var unresolved_count = 0usize
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if relocation.global { ret InvalidObject }
        if !relocation.resolved {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidObject }
            unresolved_count += 1usize
            let reference = builder.function_refs[relocation.function_ref]
            var name = reference.name
            var reference_module = ""
            if reference.has_target { reference_module = builder.functions[reference.target].module_name }
            if reference.library.len != 0usize {
                name = reference.symbol
                reference_module = ""
            } else {
                if !reference.has_target && !host_runtime_symbol(name) {
                    // A non-library reference with no target has no module to qualify with;
                    // silently matching the empty module could bind the wrong symbol. The
                    // host runtime's own symbols are in no module and stay unqualified.
                    ret InvalidObject
                }
            }
            let (existing, found) = find_symbol(symbols, symbol_count, reference_module, name)
            if !found {
                if symbol_count == symbols.len { ret Capacity }
                symbols[symbol_count] = Symbol { name: name, module: reference_module, value: 0usize, size: 0usize, section: 0usize, string_offset: 0usize }
                symbol_count += 1usize
            }
        }
        relocation_at += 1usize
    }
    var string_size = 1usize
    var symbol_at = 1usize
    while symbol_at < symbol_count {
        symbols[symbol_at].string_offset = string_size
        string_size += symbols[symbol_at].name.len + 1usize
        if symbols[symbol_at].module.len != 0usize { string_size += symbols[symbol_at].module.len + 1usize }
        symbol_at += 1usize
    }
    let text_offset = 64usize
    let relocation_offset = align(text_offset + machine.count, 8usize)
    let relocation_size = unresolved_count * 24usize
    let symbol_offset = align(relocation_offset + relocation_size, 8usize)
    let symbol_size = symbol_count * 24usize
    let string_offset = symbol_offset + symbol_size
    let section_names_offset = string_offset + string_size
    let section_names_size = 60usize
    let section_header_offset = align(section_names_offset + section_names_size, 8usize)
    try emit_x64.byte(output, 127usize)
    try append_text(output, "ELF")
    try emit_x64.byte(output, 2usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 1usize)
    try emit_x64.byte(output, 0usize)
    try emit_x64.byte(output, 0usize)
    try pad_to(output, 16usize)
    try little_u16(output, 1usize)
    try little_u16(output, 62usize)
    try emit_x64.little_u32(output, 1usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, 0usize)
    try emit_x64.little_u64(output, section_header_offset)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, 64usize)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try little_u16(output, 64usize)
    try little_u16(output, 7usize)
    try little_u16(output, 5usize)
    try pad_to(output, text_offset)
    var byte_at = 0usize
    while byte_at < machine.count {
        try emit_x64.byte(output, usize(machine.bytes[byte_at]))
        byte_at += 1usize
    }
    try pad_to(output, relocation_offset)
    relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if relocation.global { ret InvalidObject }
        if !relocation.resolved {
            let reference = builder.function_refs[relocation.function_ref]
            var name = reference.name
            var reference_module = ""
            if reference.has_target { reference_module = builder.functions[reference.target].module_name }
            var kind = 2usize
            if reference.library.len != 0usize {
                name = reference.symbol
                reference_module = ""
                kind = 9usize
            }
            let (index, found) = find_symbol(symbols, symbol_count, reference_module, name)
            if !found { ret InvalidObject }
            try emit_x64.little_u64(output, relocation.displacement_at)
            try emit_x64.little_u64(output, index * 4294967296usize + kind)
            try emit_x64.byte(output, 252usize)
            var addend_at = 1usize
            while addend_at < 8usize {
                try emit_x64.byte(output, 255usize)
                addend_at += 1usize
            }
        }
        relocation_at += 1usize
    }
    try pad_to(output, symbol_offset)
    try pad_to(output, symbol_offset + 24usize)
    symbol_at = 1usize
    while symbol_at < symbol_count {
        let symbol = symbols[symbol_at]
        try emit_x64.little_u32(output, symbol.string_offset)
        try emit_x64.byte(output, 18usize)
        try emit_x64.byte(output, 0usize)
        try little_u16(output, symbol.section)
        try emit_x64.little_u64(output, symbol.value)
        try emit_x64.little_u64(output, symbol.size)
        symbol_at += 1usize
    }
    try pad_to(output, string_offset)
    try emit_x64.byte(output, 0usize)
    symbol_at = 1usize
    while symbol_at < symbol_count {
        if symbols[symbol_at].module.len != 0usize {
            try append_text(output, symbols[symbol_at].module)
            try emit_x64.byte(output, 46usize)
        }
        try append_text(output, symbols[symbol_at].name)
        try emit_x64.byte(output, 0usize)
        symbol_at += 1usize
    }
    try pad_to(output, section_names_offset)
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".text")
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".rela.text")
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".symtab")
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".strtab")
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".shstrtab")
    try emit_x64.byte(output, 0usize)
    try append_text(output, ".note.GNU-stack")
    try emit_x64.byte(output, 0usize)
    try pad_to(output, section_header_offset)
    var null_section: Section = zero
    try write_section(output, null_section)
    var text_section = Section { name: 1usize, kind: 1usize, flags: 6usize, offset: text_offset, size: machine.count, link: 0usize, info: 0usize, alignment: 16usize, entry_size: 0usize }
    try write_section(output, text_section)
    var relocation_section = Section { name: 7usize, kind: 4usize, flags: 0usize, offset: relocation_offset, size: relocation_size, link: 3usize, info: 1usize, alignment: 8usize, entry_size: 24usize }
    try write_section(output, relocation_section)
    var symbol_section = Section { name: 18usize, kind: 2usize, flags: 0usize, offset: symbol_offset, size: symbol_size, link: 4usize, info: 1usize, alignment: 8usize, entry_size: 24usize }
    try write_section(output, symbol_section)
    var string_section = Section { name: 26usize, kind: 3usize, flags: 0usize, offset: string_offset, size: string_size, link: 0usize, info: 0usize, alignment: 1usize, entry_size: 0usize }
    try write_section(output, string_section)
    var section_name_section = Section { name: 34usize, kind: 3usize, flags: 0usize, offset: section_names_offset, size: section_names_size, link: 0usize, info: 0usize, alignment: 1usize, entry_size: 0usize }
    ret write_section(output, section_name_section)
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
    var constant_function: nir.Function = zero
    constant_function.name = "constant"
    functions[0usize] = constant_function
    var machine_storage: [5]u8 = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var symbols: [3]Symbol = zero
    var object_storage: [640]u8 = zero
    var object: emit_x64.Buffer = zero
    try emit_x64.init(&object, object_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, symbols[..], &object)
    // Structural checks, not fixed offsets: the object grew a .note.GNU-stack section
    // and module-qualified symbol names, so per-byte row assertions encoded one layout.
    if object.count < 400usize || object.count > 640usize { ret InvalidObject }
    if object.bytes[0usize] != 127u8 || object.bytes[1usize] != 69u8 || object.bytes[2usize] != 76u8 || object.bytes[3usize] != 70u8 { ret InvalidObject }
    if object.bytes[16usize] != 1u8 || object.bytes[18usize] != 62u8 { ret InvalidObject }
    if object.bytes[60usize] != 7u8 || object.bytes[62usize] != 5u8 { ret InvalidObject }
    if object.bytes[64usize] != 195u8 { ret InvalidObject }
    builder.function_ref_count = 1usize
    var external_reference: nir.FunctionRef = zero
    // A library import: the object binds it through the import table. A reference with
    // neither a target nor a library is refused (the qualified-symbol rule), so the
    // self-test models the real extern form.
    external_reference.library = "libc.so.6"
    external_reference.symbol = "external_long"
    external_reference.name = "external_long"
    references[0usize] = external_reference
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 232usize)
    try emit_x64.little_u32(&machine, 0usize)
    var external_relocation: codegen_x64.Relocation = zero
    external_relocation.displacement_at = 1usize
    external_relocation.function_ref = 0usize
    relocations[0usize] = external_relocation
    try emit_x64.init(&object, object_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 1usize, symbols[..], &object)
    // Structural checks only: the object grew a .note.GNU-stack section, so fixed
    // offsets into the symbol and relocation rows no longer describe one layout.
    if object.count < 600usize || object.count > 640usize { ret InvalidObject }
    if object.bytes[64usize] != 232u8 { ret InvalidObject }
    ret ok
}





