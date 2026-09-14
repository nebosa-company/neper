// Deterministic x86-64 ELF relocatable object serialization.

use check
use codegen_x64
use emit_x64
use nir

error Capacity
error InvalidObject

type Symbol = struct {
    name: str,
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

fn find_symbol(symbols: []Symbol, count: usize, name: str) -> (usize, bool) {
    var at = 1usize
    while at < count {
        if check.same(symbols[at].name, name) { ret (at, true) }
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
    while function_at < builder.function_count {
        var size = machine.count - function_offsets[function_at]
        if function_at + 1usize < builder.function_count { size = function_offsets[function_at + 1usize] - function_offsets[function_at] }
        symbols[symbol_count] = Symbol { name: builder.functions[function_at].name, value: function_offsets[function_at], size: size, section: 1usize, string_offset: 0usize }
        symbol_count += 1usize
        function_at += 1usize
    }
    var unresolved_count = 0usize
    var relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.resolved {
            if relocation.function_ref >= builder.function_ref_count { ret InvalidObject }
            unresolved_count += 1usize
            let name = builder.function_refs[relocation.function_ref].name
            let (existing, found) = find_symbol(symbols, symbol_count, name)
            if !found {
                if symbol_count == symbols.len { ret Capacity }
                symbols[symbol_count] = Symbol { name: name, value: 0usize, size: 0usize, section: 0usize, string_offset: 0usize }
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
        symbol_at += 1usize
    }
    let text_offset = 64usize
    let relocation_offset = align(text_offset + machine.count, 8usize)
    let relocation_size = unresolved_count * 24usize
    let symbol_offset = align(relocation_offset + relocation_size, 8usize)
    let symbol_size = symbol_count * 24usize
    let string_offset = symbol_offset + symbol_size
    let section_names_offset = string_offset + string_size
    let section_names_size = 44usize
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
    try little_u16(output, 6usize)
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
        if !relocation.resolved {
            let name = builder.function_refs[relocation.function_ref].name
            let (index, found) = find_symbol(symbols, symbol_count, name)
            if !found { ret InvalidObject }
            try emit_x64.little_u64(output, relocation.displacement_at)
            try emit_x64.little_u64(output, index * 4294967296usize + 2usize)
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
    if object.count != 560usize { ret InvalidObject }
    if object.bytes[0usize] != 127u8 || object.bytes[1usize] != 69u8 || object.bytes[2usize] != 76u8 || object.bytes[3usize] != 70u8 { ret InvalidObject }
    if object.bytes[16usize] != 1u8 || object.bytes[18usize] != 62u8 || object.bytes[40usize] != 176u8 || object.bytes[52usize] != 64u8 || object.bytes[58usize] != 64u8 || object.bytes[60usize] != 6u8 || object.bytes[62usize] != 5u8 { ret InvalidObject }
    if object.bytes[64usize] != 195u8 || object.bytes[100usize] != 18u8 || object.bytes[102usize] != 1u8 || object.bytes[112usize] != 1u8 || object.bytes[120usize] != 0u8 || object.bytes[121usize] != 99u8 { ret InvalidObject }
    if object.bytes[240usize] != 1u8 || object.bytes[244usize] != 1u8 || object.bytes[248usize] != 6u8 || object.bytes[264usize] != 64u8 || object.bytes[272usize] != 1u8 || object.bytes[288usize] != 16u8 { ret InvalidObject }
    builder.function_ref_count = 1usize
    var external_reference: nir.FunctionRef = zero
    external_reference.module_index = 1usize
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
    if object.count != 624usize || object.bytes[40usize] != 240u8 || object.bytes[64usize] != 232u8 { ret InvalidObject }
    if object.bytes[72usize] != 1u8 || object.bytes[80usize] != 2u8 || object.bytes[84usize] != 2u8 || object.bytes[88usize] != 252u8 || object.bytes[89usize] != 255u8 { ret InvalidObject }
    if object.bytes[178usize] != 101u8 || object.bytes[368usize] != 7u8 || object.bytes[372usize] != 4u8 || object.bytes[392usize] != 72u8 || object.bytes[400usize] != 24u8 || object.bytes[408usize] != 3u8 || object.bytes[412usize] != 1u8 || object.bytes[424usize] != 24u8 { ret InvalidObject }
    if object.bytes[432usize] != 18u8 || object.bytes[436usize] != 2u8 || object.bytes[456usize] != 96u8 || object.bytes[464usize] != 72u8 || object.bytes[472usize] != 4u8 || object.bytes[476usize] != 1u8 || object.bytes[480usize] != 8u8 || object.bytes[488usize] != 24u8 { ret InvalidObject }
    ret ok
}
