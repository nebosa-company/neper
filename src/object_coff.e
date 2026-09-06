// Deterministic AMD64 COFF object serialization.

use check
use codegen_x64
use emit_x64
use nir

error Capacity
error InvalidObject

type Symbol = struct {
    name: str,
    value: usize,
    section: usize,
    string_offset: usize,
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

fn append_zeroes(output: *emit_x64.Buffer, count: usize) -> err {
    var at = 0usize
    while at < count {
        try emit_x64.byte(output, 0usize)
        at += 1usize
    }
    ret ok
}

fn append_short_name(output: *emit_x64.Buffer, name: str) -> err {
    var at = 0usize
    while at < 8usize {
        if at < name.len {
            try emit_x64.byte(output, widen_byte(name[at]))
        } else {
            try emit_x64.byte(output, 0usize)
        }
        at += 1usize
    }
    ret ok
}

fn find_symbol(symbols: []Symbol, count: usize, name: str) -> (usize, bool) {
    var at = 0usize
    while at < count {
        if check.same(symbols[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn write(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, symbols: []Symbol, output: *emit_x64.Buffer) -> err {
    if builder.function_count > function_offsets.len || builder.function_count > symbols.len || relocation_count > relocations.len { ret Capacity }
    var symbol_count = 0usize
    var function_at = 0usize
    while function_at < builder.function_count {
        symbols[symbol_count] = Symbol { name: builder.functions[function_at].name, value: function_offsets[function_at], section: 1usize, string_offset: 0usize }
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
                symbols[symbol_count] = Symbol { name: name, value: 0usize, section: 0usize, string_offset: 0usize }
                symbol_count += 1usize
            }
        }
        relocation_at += 1usize
    }
    var string_size = 4usize
    var symbol_at = 0usize
    while symbol_at < symbol_count {
        if symbols[symbol_at].name.len > 8usize {
            symbols[symbol_at].string_offset = string_size
            string_size += symbols[symbol_at].name.len + 1usize
        }
        symbol_at += 1usize
    }
    let raw_offset = 60usize
    let relocation_offset = raw_offset + machine.count
    let symbol_offset = relocation_offset + unresolved_count * 10usize
    try little_u16(output, 34404usize)
    try little_u16(output, 1usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, symbol_offset)
    try emit_x64.little_u32(output, symbol_count)
    try little_u16(output, 0usize)
    try little_u16(output, 0usize)
    try append_short_name(output, ".text")
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, 0usize)
    try emit_x64.little_u32(output, machine.count)
    try emit_x64.little_u32(output, raw_offset)
    try emit_x64.little_u32(output, relocation_offset)
    try emit_x64.little_u32(output, 0usize)
    try little_u16(output, unresolved_count)
    try little_u16(output, 0usize)
    try emit_x64.little_u32(output, 1610612768usize)
    var byte_at = 0usize
    while byte_at < machine.count {
        try emit_x64.byte(output, machine.bytes[byte_at])
        byte_at += 1usize
    }
    relocation_at = 0usize
    while relocation_at < relocation_count {
        let relocation = relocations[relocation_at]
        if !relocation.resolved {
            let name = builder.function_refs[relocation.function_ref].name
            let (index, found) = find_symbol(symbols, symbol_count, name)
            if !found { ret InvalidObject }
            try emit_x64.little_u32(output, relocation.displacement_at)
            try emit_x64.little_u32(output, index)
            try little_u16(output, 4usize)
        }
        relocation_at += 1usize
    }
    symbol_at = 0usize
    while symbol_at < symbol_count {
        let symbol = symbols[symbol_at]
        if symbol.string_offset == 0usize {
            try append_short_name(output, symbol.name)
        } else {
            try emit_x64.little_u32(output, 0usize)
            try emit_x64.little_u32(output, symbol.string_offset)
        }
        try emit_x64.little_u32(output, symbol.value)
        try little_u16(output, symbol.section)
        try little_u16(output, 32usize)
        try emit_x64.byte(output, 2usize)
        try emit_x64.byte(output, 0usize)
        symbol_at += 1usize
    }
    try emit_x64.little_u32(output, string_size)
    symbol_at = 0usize
    while symbol_at < symbol_count {
        let symbol = symbols[symbol_at]
        if symbol.string_offset != 0usize {
            byte_at = 0usize
            while byte_at < symbol.name.len {
                try emit_x64.byte(output, widen_byte(symbol.name[byte_at]))
                byte_at += 1usize
            }
            try emit_x64.byte(output, 0usize)
        }
        symbol_at += 1usize
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
    builder.functions[0usize] = zero
    builder.functions[0usize].name = "constant"
    var machine_storage: [5]usize = zero
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 195usize)
    var offsets: [1]usize = zero
    var relocations: [1]codegen_x64.Relocation = zero
    var symbols: [2]Symbol = zero
    var object_storage: [160]usize = zero
    var object: emit_x64.Buffer = zero
    try emit_x64.init(&object, object_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 0usize, symbols[..], &object)
    if object.count != 83usize { ret InvalidObject }
    if object.bytes[0usize] != 100usize || object.bytes[1usize] != 134usize || object.bytes[2usize] != 1usize { ret InvalidObject }
    if object.bytes[8usize] != 61usize || object.bytes[12usize] != 1usize || object.bytes[20usize] != 46usize || object.bytes[21usize] != 116usize { ret InvalidObject }
    if object.bytes[36usize] != 1usize || object.bytes[40usize] != 60usize || object.bytes[56usize] != 32usize || object.bytes[59usize] != 96usize { ret InvalidObject }
    if object.bytes[60usize] != 195usize || object.bytes[61usize] != 99usize || object.bytes[68usize] != 116usize || object.bytes[73usize] != 1usize || object.bytes[75usize] != 32usize || object.bytes[77usize] != 2usize || object.bytes[79usize] != 4usize { ret InvalidObject }
    builder.function_ref_count = 1usize
    builder.function_refs[0usize] = zero
    builder.function_refs[0usize].module_index = 1usize
    builder.function_refs[0usize].name = "external_long"
    try emit_x64.init(&machine, machine_storage[..])
    try emit_x64.byte(&machine, 232usize)
    try emit_x64.little_u32(&machine, 0usize)
    relocations[0usize] = zero
    relocations[0usize].displacement_at = 1usize
    relocations[0usize].function_ref = 0usize
    try emit_x64.init(&object, object_storage[..])
    try write(&builder, &machine, offsets[..], relocations[..], 1usize, symbols[..], &object)
    if object.count != 129usize || object.bytes[8usize] != 75usize || object.bytes[12usize] != 2usize || object.bytes[36usize] != 5usize || object.bytes[44usize] != 65usize || object.bytes[52usize] != 1usize { ret InvalidObject }
    if object.bytes[65usize] != 1usize || object.bytes[69usize] != 1usize || object.bytes[73usize] != 4usize || object.bytes[97usize] != 4usize || object.bytes[111usize] != 18usize || object.bytes[115usize] != 101usize { ret InvalidObject }
    ret ok
}
