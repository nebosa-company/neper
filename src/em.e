// Canonical compiled-module container. Payload schemas are layered on this format.

use artifact_hash
use binary
use e.mem
use check
use codegen_x64
use emit_x64
use graph
use lex
use lookup
use nir
use resolve

error Capacity
error InvalidArtifact
error UnsupportedVersion

type BuildMode = enum u8 {
    Debug,
    Release,
}

type Section = struct {
    kind: usize,
    flags: usize,
    offset: usize,
    length: usize,
}

type Writer = struct {
    output: *binary.Buffer,
    sections: []Section,
    count: usize,
    active: bool,
    active_start: usize,
}

type StringTable = struct {
    values: []str,
    count: usize,
    // An open-addressed index over the values, each slot the value's index plus one
    // (D213): a module of the compiler's size interns tens of thousands of strings, and
    // a linear scan per intern made the writer quadratic.
    index: []usize,
}

type Declaration = struct {
    kind: usize,
    flags: usize,
    name_index: usize,
    signature_hash: usize,
    body_hash: usize,
}

type Dependency = struct {
    kind: usize,
    module_index: usize,
    name_index: usize,
    hash: usize,
}

type ErrorValue = struct {
    value: usize,
    module_index: usize,
    name_index: usize,
}

type InterfaceErrors = struct {
    entries: usize,
    count: usize,
    module_index: usize,
}

type CodeFunction = struct {
    name_index: usize,
    instance: usize,
    content_hash: usize,
    code_start: usize,
    code_length: usize,
    relocations: usize,
    relocation_count: usize,
}

// A module-scope `var` of the artifact's module, in the order the checker declared them:
// what the linker needs to lay it out and fill it, and nothing about its type.
type GlobalRecord = struct {
    name_index: usize,
    size: usize,
    alignment: usize,
    has_initial: bool,
    initial: usize,
}

type CodeRelocation = struct {
    displacement_at: usize,
    module_index: usize,
    name_index: usize,
    // A module-scope `var` rather than a function: `module_index` and `name_index` name the
    // variable, and `instance` is 0.
    global: bool,
    instance: usize,
    // An `extern fn` bound by `@import` (D319): the library and the symbol it binds, as
    // string indexes, so the linker that consumes the artifact can import it.
    imported: bool,
    library_index: usize,
    symbol_index: usize,
}

fn format_version() -> usize { ret 6usize }
fn header_size() -> usize { ret 32usize }
fn directory_entry_size() -> usize { ret 24usize }
fn required_flag() -> usize { ret 1usize }
fn strings_kind() -> usize { ret 1usize }
fn interface_kind() -> usize { ret 2usize }
fn deps_kind() -> usize { ret 3usize }
fn nir_kind() -> usize { ret 4usize }
fn code_kind() -> usize { ret 5usize }
fn debug_kind() -> usize { ret 6usize }
fn globals_kind() -> usize { ret 7usize }
// Section 13's line table per code function (D209): rows of a code offset within the
// function, a line, and the path as a string index.
fn lines_kind() -> usize { ret 8usize }
// The module's `use` declarations in order, name and qualifier (D322, format 6): a hot
// build discovers the graph from an unchanged module's artifact without parsing it.
fn imports_kind() -> usize { ret 9usize }

fn declaration_function_kind() -> usize { ret 1usize }
fn declaration_aggregate_kind() -> usize { ret 2usize }
fn declaration_alias_kind() -> usize { ret 3usize }
fn declaration_constant_kind() -> usize { ret 4usize }
fn declaration_error_kind() -> usize { ret 5usize }
fn dependency_signature_kind() -> usize { ret 1usize }
fn dependency_value_kind() -> usize { ret 2usize }
fn dependency_body_kind() -> usize { ret 3usize }
fn dependency_lookup_kind() -> usize { ret 4usize }

fn mode_id(mode: BuildMode) -> usize {
    if mode == .Release { ret 1usize }
    ret 0usize
}

fn known_kind(kind: usize) -> bool {
    ret kind >= strings_kind() && kind <= imports_kind()
}

// One row of a code function's line table as an artifact carries it.
type LineRow = struct {
    offset: usize,
    line: usize,
    path_index: usize,
}

fn canonical_text(output: *binary.Buffer, value: str) -> err {
    try binary.little_u32(output, value.len)
    ret binary.text(output, value)
}

fn type_kind_id(kind: check.Kind) -> usize {
    if kind == .Void { ret 1usize }
    if kind == .Bool { ret 2usize }
    if kind == .Err { ret 3usize }
    if kind == .Integer { ret 4usize }
    if kind == .Float { ret 5usize }
    if kind == .String { ret 6usize }
    if kind == .Named { ret 7usize }
    if kind == .Tag { ret 8usize }
    if kind == .Pointer { ret 9usize }
    if kind == .Slice { ret 10usize }
    if kind == .Array { ret 11usize }
    if kind == .TypeParameter { ret 12usize }
    if kind == .UntypedInteger { ret 13usize }
    if kind == .UntypedFloat { ret 14usize }
    if kind == .Other { ret 15usize }
    if kind == .Function { ret 16usize }
    ret 0usize
}

fn aggregate_type(kind: check.Kind) -> bool {
    ret kind == .Pointer || kind == .Slice || kind == .Array
}

fn type_flags(ty: check.Type) -> usize {
    var flags = 0usize
    if ty.is_const { flags += 1usize }
    if ty.has_element { flags += 2usize }
    if ty.has_length { flags += 4usize }
    ret flags
}

fn collect_type_strings(c: *check.Checker, g: *graph.Graph, table: *StringTable, ty: check.Type) -> err {
    if ty.name.len != 0usize {
        let (name_index, name_error) = intern(table, ty.name)
        if name_error != ok { ret name_error }
    }
    if (ty.kind == .Named || ty.kind == .Tag) && ty.module_index < g.count {
        let (module_index, module_error) = intern(table, g.modules[ty.module_index].name)
        if module_error != ok { ret module_error }
    }
    if aggregate_type(ty.kind) && ty.has_element {
        if ty.element >= c.type_count { ret InvalidArtifact }
        ret collect_type_strings(c, g, table, c.types[ty.element])
    }
    if ty.kind == .Function {
        let (signature, has_signature) = check.function_signature_of(c, ty)
        if !has_signature { ret InvalidArtifact }
        var at = 0usize
        while at < signature.parameter_count {
            let (parameter, has_parameter) = check.function_signature_parameter(c, signature, at)
            if !has_parameter { ret InvalidArtifact }
            try collect_type_strings(c, g, table, parameter)
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (result, has_result) = check.function_signature_return(c, signature, at)
            if !has_result { ret InvalidArtifact }
            try collect_type_strings(c, g, table, result)
            at += 1usize
        }
    }
    ret ok
}

fn write_type_canonical(c: *check.Checker, g: *graph.Graph, ty: check.Type, output: *binary.Buffer) -> err {
    let kind = type_kind_id(ty.kind)
    if kind == 0usize { ret InvalidArtifact }
    try binary.byte(output, kind)
    try binary.byte(output, type_flags(ty))
    try binary.little_u16(output, 0usize)
    if (ty.kind == .Named || ty.kind == .Tag) && ty.module_index < g.count {
        try canonical_text(output, g.modules[ty.module_index].name)
    } else {
        try canonical_text(output, "")
    }
    try canonical_text(output, ty.name)
    if ty.has_length { try binary.little_u64(output, ty.array_length) } else { try binary.little_u64(output, 0usize) }
    if aggregate_type(ty.kind) && ty.has_element {
        if ty.element >= c.type_count { ret InvalidArtifact }
        ret write_type_canonical(c, g, c.types[ty.element], output)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = check.function_signature_of(c, ty)
        if !has_signature { ret InvalidArtifact }
        try binary.little_u32(output, signature.parameter_count)
        try binary.little_u32(output, signature.return_count)
        var at = 0usize
        while at < signature.parameter_count {
            let (parameter, has_parameter) = check.function_signature_parameter(c, signature, at)
            if !has_parameter { ret InvalidArtifact }
            try write_type_canonical(c, g, parameter, output)
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (result, has_result) = check.function_signature_return(c, signature, at)
            if !has_result { ret InvalidArtifact }
            try write_type_canonical(c, g, result, output)
            at += 1usize
        }
    }
    ret ok
}

fn write_type_indexed(c: *check.Checker, g: *graph.Graph, table: *StringTable, ty: check.Type, output: *binary.Buffer) -> err {
    let kind = type_kind_id(ty.kind)
    if kind == 0usize { ret InvalidArtifact }
    try binary.byte(output, kind)
    try binary.byte(output, type_flags(ty))
    try binary.little_u16(output, 0usize)
    var module_index = 0usize
    if (ty.kind == .Named || ty.kind == .Tag) && ty.module_index < g.count {
        let (stored_module, module_error) = string_index(table, g.modules[ty.module_index].name)
        if module_error != ok { ret module_error }
        module_index = stored_module
    }
    let (name_index, name_error) = string_index(table, ty.name)
    if name_error != ok { ret name_error }
    try binary.little_u32(output, module_index)
    try binary.little_u32(output, name_index)
    if ty.has_length { try binary.little_u64(output, ty.array_length) } else { try binary.little_u64(output, 0usize) }
    if aggregate_type(ty.kind) && ty.has_element {
        if ty.element >= c.type_count { ret InvalidArtifact }
        ret write_type_indexed(c, g, table, c.types[ty.element], output)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = check.function_signature_of(c, ty)
        if !has_signature { ret InvalidArtifact }
        try binary.little_u32(output, signature.parameter_count)
        try binary.little_u32(output, signature.return_count)
        var at = 0usize
        while at < signature.parameter_count {
            let (parameter, has_parameter) = check.function_signature_parameter(c, signature, at)
            if !has_parameter { ret InvalidArtifact }
            try write_type_indexed(c, g, table, parameter, output)
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (result, has_result) = check.function_signature_return(c, signature, at)
            if !has_result { ret InvalidArtifact }
            try write_type_indexed(c, g, table, result, output)
            at += 1usize
        }
    }
    ret ok
}

fn opcode_id(opcode: nir.Opcode) -> usize {
    if opcode == .Parameter { ret 1usize }
    if opcode == .ConstInteger { ret 2usize }
    if opcode == .ConstBool { ret 3usize }
    if opcode == .ConstError { ret 4usize }
    if opcode == .ConstString { ret 5usize }
    if opcode == .Stack { ret 6usize }
    if opcode == .Load { ret 7usize }
    if opcode == .Store { ret 8usize }
    if opcode == .Copy { ret 9usize }
    if opcode == .Zero { ret 10usize }
    if opcode == .FieldAddress { ret 11usize }
    if opcode == .IndexAddress { ret 12usize }
    if opcode == .Slice { ret 13usize }
    if opcode == .Cast { ret 14usize }
    if opcode == .Add { ret 15usize }
    if opcode == .Subtract { ret 16usize }
    if opcode == .Multiply { ret 17usize }
    if opcode == .Divide { ret 18usize }
    if opcode == .Remainder { ret 19usize }
    if opcode == .AddWrap { ret 20usize }
    if opcode == .SubtractWrap { ret 21usize }
    if opcode == .MultiplyWrap { ret 22usize }
    if opcode == .ShiftLeft { ret 23usize }
    if opcode == .ShiftRight { ret 24usize }
    if opcode == .BitAnd { ret 25usize }
    if opcode == .BitXor { ret 26usize }
    if opcode == .BitOr { ret 27usize }
    if opcode == .Negate { ret 28usize }
    if opcode == .BitNot { ret 29usize }
    if opcode == .Equal { ret 30usize }
    if opcode == .NotEqual { ret 31usize }
    if opcode == .Less { ret 32usize }
    if opcode == .LessEqual { ret 33usize }
    if opcode == .Greater { ret 34usize }
    if opcode == .GreaterEqual { ret 35usize }
    if opcode == .Call { ret 36usize }
    if opcode == .Extract { ret 37usize }
    if opcode == .Phi { ret 38usize }
    if opcode == .Trap { ret 39usize }
    if opcode == .Branch { ret 40usize }
    if opcode == .BranchIf { ret 41usize }
    if opcode == .Switch { ret 42usize }
    if opcode == .Return { ret 43usize }
    if opcode == .Unreachable { ret 44usize }
    if opcode == .FunctionAddress { ret 45usize }
    if opcode == .IndirectCall { ret 46usize }
    if opcode == .ConstFloat { ret 47usize }
    if opcode == .Bitcast { ret 48usize }
    if opcode == .AtomicLoad { ret 49usize }
    if opcode == .AtomicStore { ret 50usize }
    if opcode == .AtomicRmw { ret 51usize }
    if opcode == .AtomicCas { ret 52usize }
    if opcode == .AtomicFence { ret 53usize }
    if opcode == .GlobalAddress { ret 54usize }
    if opcode == .Sqrt { ret 55usize }
    ret 0usize
}

fn init_strings(table: *StringTable, values: []str, index: []usize) -> err {
    if values.len == 0usize || index.len < values.len * 2usize || index.len & (index.len - 1usize) != 0usize { ret Capacity }
    table.values = values
    table.index = index
    ret reset_strings(table)
}

// Back to the empty string alone, for the next module.
fn reset_strings(table: *StringTable) -> err {
    let index = table.index
    var at = 0usize
    while at < index.len {
        index[at] = 0usize
        at += 1usize
    }
    table.count = 0usize
    let (empty, empty_error) = intern(table, "")
    ret empty_error
}

fn string_hash(value: str) -> usize {
    var hash = 14695981039346656037usize
    var at = 0usize
    while at < value.len {
        hash = (hash ^ usize(value[at])) *% 1099511628211usize
        at += 1usize
    }
    ret hash
}

// The slot holding `value`, or the empty slot where it would go.
fn string_slot(table: *StringTable, value: str) -> usize {
    let mask = table.index.len - 1usize
    var slot = string_hash(value) & mask
    while table.index[slot] != 0usize {
        if same(table.values[table.index[slot] - 1usize], value) { ret slot }
        slot = (slot + 1usize) & mask
    }
    ret slot
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

fn intern(table: *StringTable, value: str) -> (usize, err) {
    let slot = string_slot(table, value)
    if table.index[slot] != 0usize { ret (table.index[slot] - 1usize, ok) }
    if table.count == table.values.len { ret (0usize, Capacity) }
    let index = table.count
    table.values[index] = value
    table.count += 1usize
    table.index[slot] = index + 1usize
    ret (index, ok)
}

fn string_index(table: *StringTable, value: str) -> (usize, err) {
    let slot = string_slot(table, value)
    if table.index[slot] != 0usize { ret (table.index[slot] - 1usize, ok) }
    ret (0usize, InvalidArtifact)
}

// The Strings section (format 5, D319): the count, then each string's offset from the
// section's start, then the strings as a length and its bytes. The offsets are what
// make `string_bounds` one read: every reader of the artifact walked the table from
// its first entry, per relocation, per row.
fn write_strings(table: *StringTable, output: *binary.Buffer) -> err {
    try binary.little_u32(output, table.count)
    var offset = 4usize + table.count * 4usize
    var at = 0usize
    while at < table.count {
        try binary.little_u32(output, offset)
        offset += 4usize + table.values[at].len
        at += 1usize
    }
    at = 0usize
    while at < table.count {
        try binary.little_u32(output, table.values[at].len)
        try binary.text(output, table.values[at])
        at += 1usize
    }
    ret ok
}

fn comptime_kind_id(kind: check.ComptimeKind) -> usize {
    if kind == .Type { ret 1usize }
    if kind == .Integer { ret 2usize }
    ret 0usize
}

fn aggregate_kind_id(kind: check.AggregateKind) -> usize {
    if kind == .Struct { ret 1usize }
    if kind == .Union { ret 2usize }
    if kind == .TaggedUnion { ret 3usize }
    if kind == .Enum { ret 4usize }
    ret 0usize
}

fn function_flags(function: check.Function) -> usize {
    var flags = 0usize
    if function.generic { flags += 1usize }
    if function.external { flags += 2usize }
    ret flags
}

fn write_function_signature_canonical(c: *check.Checker, g: *graph.Graph, function_index: usize, output: *binary.Buffer) -> err {
    if function_index >= c.function_count { ret InvalidArtifact }
    let function = c.functions[function_index]
    if function.module_index >= g.count { ret InvalidArtifact }
    try binary.byte(output, declaration_function_kind())
    try binary.byte(output, function_flags(function))
    try binary.little_u16(output, 0usize)
    try canonical_text(output, g.modules[function.module_index].name)
    try canonical_text(output, function.name)
    var comptime_count = 0usize
    var first_comptime = 0usize
    if function_index < c.signature_function_count {
        comptime_count = c.function_generics[function_index].comptime_count
        first_comptime = c.function_generics[function_index].first_comptime
    }
    try binary.little_u32(output, comptime_count)
    var at = 0usize
    while at < comptime_count {
        if first_comptime + at >= c.comptime_parameter_count { ret InvalidArtifact }
        let parameter = c.comptime_parameters[first_comptime + at]
        let kind = comptime_kind_id(parameter.kind)
        if kind == 0usize { ret InvalidArtifact }
        try binary.byte(output, kind)
        try binary.zeroes(output, 3usize)
        try canonical_text(output, parameter.name)
        if parameter.kind == .Integer { try write_type_canonical(c, g, parameter.ty, output) }
        at += 1usize
    }
    try binary.little_u32(output, function.parameter_count)
    at = 0usize
    while at < function.parameter_count {
        if function.first_parameter + at >= c.parameter_count { ret InvalidArtifact }
        let parameter = c.parameters[function.first_parameter + at]
        try canonical_text(output, parameter.name)
        try write_type_canonical(c, g, parameter.ty, output)
        at += 1usize
    }
    try binary.little_u32(output, function.return_count)
    at = 0usize
    while at < function.return_count {
        if function.first_return + at >= c.return_type_count { ret InvalidArtifact }
        try write_type_canonical(c, g, c.return_types[function.first_return + at], output)
        at += 1usize
    }
    ret ok
}

fn signature_hash(c: *check.Checker, g: *graph.Graph, function_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = write_function_signature_canonical(c, g, function_index, scratch)
    if write_error != ok { ret (0usize, write_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn write_aggregate_signature_canonical(c: *check.Checker, g: *graph.Graph, aggregate_index: usize, output: *binary.Buffer) -> err {
    if aggregate_index >= c.aggregate_count { ret InvalidArtifact }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.module_index >= g.count { ret InvalidArtifact }
    let kind = aggregate_kind_id(aggregate.kind)
    if kind == 0usize { ret InvalidArtifact }
    try binary.byte(output, declaration_aggregate_kind())
    if aggregate.generic { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
    try binary.little_u16(output, 0usize)
    try canonical_text(output, g.modules[aggregate.module_index].name)
    try canonical_text(output, aggregate.name)
    try binary.byte(output, kind)
    try binary.zeroes(output, 3usize)
    try binary.little_u32(output, aggregate.comptime_count)
    var at = 0usize
    while at < aggregate.comptime_count {
        if aggregate.first_comptime + at >= c.comptime_parameter_count { ret InvalidArtifact }
        let parameter = c.comptime_parameters[aggregate.first_comptime + at]
        let parameter_kind = comptime_kind_id(parameter.kind)
        if parameter_kind == 0usize { ret InvalidArtifact }
        try binary.byte(output, parameter_kind)
        try binary.zeroes(output, 3usize)
        try canonical_text(output, parameter.name)
        if parameter.kind == .Integer { try write_type_canonical(c, g, parameter.ty, output) }
        at += 1usize
    }
    if aggregate.kind == .Enum || aggregate.kind == .TaggedUnion {
        try binary.byte(output, 1usize)
        try write_type_canonical(c, g, aggregate.backing_type, output)
    } else {
        try binary.byte(output, 0usize)
    }
    try binary.little_u32(output, aggregate.field_count)
    at = 0usize
    while at < aggregate.field_count {
        if aggregate.first_field + at >= c.aggregate_field_count { ret InvalidArtifact }
        let field = c.aggregate_fields[aggregate.first_field + at]
        try canonical_text(output, field.name)
        try write_type_canonical(c, g, field.ty, output)
        if field.has_enum_value { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        if field.enum_negative { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        try binary.little_u16(output, 0usize)
        try binary.little_u64(output, field.enum_value)
        at += 1usize
    }
    ret ok
}

fn aggregate_signature_hash(c: *check.Checker, g: *graph.Graph, aggregate_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = write_aggregate_signature_canonical(c, g, aggregate_index, scratch)
    if write_error != ok { ret (0usize, write_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn write_alias_signature_canonical(c: *check.Checker, g: *graph.Graph, alias_index: usize, output: *binary.Buffer) -> err {
    if alias_index >= c.alias_count { ret InvalidArtifact }
    let alias = c.aliases[alias_index]
    if alias.module_index >= g.count { ret InvalidArtifact }
    try binary.byte(output, declaration_alias_kind())
    if alias.generic { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
    try binary.little_u16(output, 0usize)
    try canonical_text(output, g.modules[alias.module_index].name)
    try canonical_text(output, alias.name)
    if alias.generic {
        try binary.byte(output, 0usize)
    } else {
        try binary.byte(output, 1usize)
        try write_type_canonical(c, g, alias.resolved, output)
    }
    ret ok
}

fn alias_signature_hash(c: *check.Checker, g: *graph.Graph, alias_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = write_alias_signature_canonical(c, g, alias_index, scratch)
    if write_error != ok { ret (0usize, write_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn write_constant_signature_canonical(c: *check.Checker, g: *graph.Graph, constant_index: usize, output: *binary.Buffer) -> err {
    if constant_index >= c.constant_count { ret InvalidArtifact }
    let constant = c.constants[constant_index]
    if constant.module_index >= g.count { ret InvalidArtifact }
    try binary.byte(output, declaration_constant_kind())
    try binary.zeroes(output, 3usize)
    try canonical_text(output, g.modules[constant.module_index].name)
    try canonical_text(output, constant.name)
    ret write_type_canonical(c, g, constant.ty, output)
}

fn constant_signature_hash(c: *check.Checker, g: *graph.Graph, constant_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = write_constant_signature_canonical(c, g, constant_index, scratch)
    if write_error != ok { ret (0usize, write_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn write_error_signature_canonical(g: *graph.Graph, symbol: resolve.Symbol, output: *binary.Buffer) -> err {
    if symbol.module_index >= g.count || symbol.kind != .Error { ret InvalidArtifact }
    try binary.byte(output, declaration_error_kind())
    try binary.zeroes(output, 3usize)
    try canonical_text(output, g.modules[symbol.module_index].name)
    ret canonical_text(output, symbol.name)
}

fn error_signature_hash(g: *graph.Graph, symbol: resolve.Symbol, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = write_error_signature_canonical(g, symbol, scratch)
    if write_error != ok { ret (0usize, write_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn signature_only_body_hash(signature: usize, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let write_error = binary.little_u64(scratch, signature)
    if write_error != ok { ret (0usize, write_error) }
    let marker_error = binary.byte(scratch, 0usize)
    if marker_error != ok { ret (0usize, marker_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn constant_body_hash(c: *check.Checker, g: *graph.Graph, constant_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    let (signature, signature_error) = constant_signature_hash(c, g, constant_index, scratch)
    if signature_error != ok { ret (0usize, signature_error) }
    let constant = c.constants[constant_index]
    scratch.count = 0usize
    let signature_write_error = binary.little_u64(scratch, signature)
    if signature_write_error != ok { ret (0usize, signature_write_error) }
    let marker_error = binary.byte(scratch, 1usize)
    if marker_error != ok { ret (0usize, marker_error) }
    var negative = 0usize
    if constant.value.negative { negative = 1usize }
    let negative_error = binary.byte(scratch, negative)
    if negative_error != ok { ret (0usize, negative_error) }
    let value_error = binary.little_u64(scratch, constant.value.magnitude)
    if value_error != ok { ret (0usize, value_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn find_checked_function(c: *check.Checker, module_index: usize, name: str) -> (usize, bool) {
    // The checker's own index (D303): this walked every function of the program per
    // edge, a fifth of writing a large program's artifacts (D320).
    let (found_at, found) = check.find_function(c, module_index, name)
    ret (found_at, found)
}

fn dependency_reference_name(name: str) -> (str, bool) {
    // Lowering uses linker symbols for host intrinsics, while dependency hashes
    // identify their source declarations. Keep this table aligned with
    // lower.intrinsic_symbol. mem.alloc is compiler-owned and has no declaration.
    if same(name, "neper_mem_alloc") || same(name, "neper_mem_alloc_fill") { ret ("", false) }
    if same(name, "neper_hash_bytes") { ret ("", false) }
    if same(name, "neper_trap") { ret ("", false) }
    if same(name, "neper_report_failure") { ret ("", false) }
    if same(name, "neper_symbols") { ret ("", false) }
    if same(name, "neper_mem_mark") { ret ("mark", true) }
    if same(name, "neper_mem_reset") || same(name, "neper_mem_reset_fill") { ret ("reset", true) }
    if same(name, "neper_mem_stats") { ret ("stats", true) }
    if same(name, "neper_os_open") { ret ("open", true) }
    if same(name, "neper_os_seek") { ret ("seek", true) }
    if same(name, "neper_os_read") { ret ("read", true) }
    if same(name, "neper_os_write") { ret ("write", true) }
    if same(name, "neper_os_close") { ret ("close", true) }
    if same(name, "neper_os_stdout") { ret ("stdout", true) }
    if same(name, "neper_os_stderr") { ret ("stderr", true) }
    if same(name, "neper_os_readdir") { ret ("readdir", true) }
    if same(name, "neper_os_spawn") { ret ("spawn", true) }
    if same(name, "neper_os_wait") { ret ("wait", true) }
    if same(name, "neper_os_exit") { ret ("exit", true) }
    if same(name, "neper_os_args") { ret ("args", true) }
    if same(name, "neper_os_reserve") { ret ("reserve", true) }
    if same(name, "neper_os_commit") { ret ("commit", true) }
    if same(name, "neper_os_clock") { ret ("clock", true) }
    if same(name, "neper_os_syscall") { ret ("syscall", true) }
    if same(name, "neper_os_wait_u32") { ret ("wait_u32", true) }
    if same(name, "neper_os_wake_one_u32") { ret ("wake_one_u32", true) }
    if same(name, "neper_os_wake_all_u32") { ret ("wake_all_u32", true) }
    // `thread_create` is generic and intercepted at the call (D321): no declaration.
    if same(name, "neper_os_thread_create") { ret ("", false) }
    if same(name, "neper_os_thread_join") { ret ("thread_join", true) }
    if same(name, "neper_os_thread_detach") { ret ("thread_detach", true) }
    ret (name, true)
}


fn find_nir_function(builder: *nir.Builder, module_index: usize, name: str, instance: usize) -> (usize, bool) {
    var at = 0usize
    while at < builder.function_count {
        if builder.functions[at].module_index == module_index && builder.functions[at].instance == instance && same(builder.functions[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn write_instruction_immediate_canonical(g: *graph.Graph, builder: *nir.Builder, instruction: nir.Instruction, output: *binary.Buffer) -> err {
    if instruction.opcode == .Call || instruction.opcode == .FunctionAddress {
        if instruction.immediate >= builder.function_ref_count { ret InvalidArtifact }
        let reference = builder.function_refs[instruction.immediate]
        if reference.module_index >= g.count { ret InvalidArtifact }
        try binary.byte(output, 1usize)
        try canonical_text(output, g.modules[reference.module_index].name)
        try canonical_text(output, reference.name)
        ret binary.little_u32(output, reference.instance)
    }
    if instruction.opcode == .ConstString {
        if instruction.immediate >= builder.string_count { ret InvalidArtifact }
        try binary.byte(output, 2usize)
        ret canonical_text(output, builder.strings[instruction.immediate].spelling)
    }
    // `unreachable("why")`: the message by its text, as a string constant is, and a
    // bare `unreachable()` as none -- the index is program-wide (D194).
    if instruction.opcode == .Trap {
        if instruction.immediate > builder.string_count { ret InvalidArtifact }
        try binary.byte(output, 4usize)
        if instruction.immediate == 0usize { ret canonical_text(output, "") }
        ret canonical_text(output, builder.strings[instruction.immediate - 1usize].spelling)
    }
    if instruction.opcode == .GlobalAddress {
        // By name: the index is program-wide and would change with every module added.
        if instruction.immediate >= builder.global_count { ret InvalidArtifact }
        let global = builder.globals[instruction.immediate]
        if global.module_index >= g.count { ret InvalidArtifact }
        try binary.byte(output, 3usize)
        try canonical_text(output, g.modules[global.module_index].name)
        ret canonical_text(output, global.name)
    }
    try binary.byte(output, 0usize)
    ret binary.little_u64(output, instruction.immediate)
}

fn write_nir_canonical(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, function_index: usize, output: *binary.Buffer) -> err {
    if function_index >= builder.function_count { ret InvalidArtifact }
    let function = builder.functions[function_index]
    if function.first_block + function.block_count > builder.block_count || function.first_instruction + function.instruction_count > builder.instruction_count { ret InvalidArtifact }
    try binary.little_u32(output, function.block_count)
    try binary.little_u32(output, function.instruction_count)
    try binary.little_u32(output, function.value_count)
    var block_at = function.first_block
    while block_at < function.first_block + function.block_count {
        let block = builder.blocks[block_at]
        try binary.little_u32(output, block.instruction_count)
        block_at += 1usize
    }
    var instruction_at = function.first_instruction
    while instruction_at < function.first_instruction + function.instruction_count {
        let instruction = builder.instructions[instruction_at]
        let opcode = opcode_id(instruction.opcode)
        if opcode == 0usize { ret InvalidArtifact }
        try binary.byte(output, opcode)
        if instruction.has_result { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        // The `@nocheck` mark is semantics, so it is in the hash (D203).
        var flags = 0usize
        if instruction.nocheck { flags = 1usize }
        try binary.little_u16(output, flags)
        var instruction_type = instruction.ty
        if instruction_type.kind == .Invalid {
            if instruction.has_result { ret InvalidArtifact }
            instruction_type = check.make_type(.Void, "void", function.module_index)
        }
        try write_type_canonical(c, g, instruction_type, output)
        if instruction.has_result { try binary.little_u32(output, instruction.result) } else { try binary.little_u32(output, 0usize) }
        try binary.little_u32(output, instruction.operand_count)
        if instruction.first_operand + instruction.operand_count > builder.operand_count { ret InvalidArtifact }
        var operand_at = instruction.first_operand
        while operand_at < instruction.first_operand + instruction.operand_count {
            try binary.little_u32(output, builder.operands[operand_at])
            operand_at += 1usize
        }
        try write_instruction_immediate_canonical(g, builder, instruction, output)
        var branch_target = 0usize
        var branch_target2 = 0usize
        if instruction.opcode == .Branch || instruction.opcode == .BranchIf || instruction.opcode == .Switch {
            if instruction.target < function.first_block || instruction.target >= function.first_block + function.block_count { ret InvalidArtifact }
            branch_target = instruction.target - function.first_block
        }
        if instruction.opcode == .BranchIf {
            if instruction.target2 < function.first_block || instruction.target2 >= function.first_block + function.block_count { ret InvalidArtifact }
            branch_target2 = instruction.target2 - function.first_block
        }
        try binary.little_u32(output, branch_target)
        try binary.little_u32(output, branch_target2)
        instruction_at += 1usize
    }
    ret ok
}

// A generic template has no NIR of its own, so its body hash is taken over the
// token spellings of its declaration. Trivia and formatting are excluded, and a
// consumer that instantiated the template can hold a body edge that goes stale
// exactly when the template's code changes.
// The declaration's tokens from the module's own stream (D316), found by offset
// (D320): the range was lexed again for every body hash, which lexed the whole
// program a second time in settle and a third in the writer.
fn write_declaration_tokens_canonical(text: str, tokens: []const lex.Token, start: usize, end: usize, output: *binary.Buffer) -> err {
    if start > end || end > text.len { ret InvalidArtifact }
    var low = 0usize
    var high = tokens.len
    while low < high {
        let mid = (low + high) / 2usize
        if tokens[mid].start < start { low = mid + 1usize } else { high = mid }
    }
    var at = low
    while at < tokens.len && tokens[at].end <= end {
        let token = tokens[at]
        if token.kind == .Invalid { ret InvalidArtifact }
        if token.kind != .Eof {
            if token.start > token.end { ret InvalidArtifact }
            try canonical_text(output, text[token.start..token.end])
        }
        at += 1usize
    }
    ret ok
}

fn body_hash(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, checked_function: usize, nir_function: usize, has_nir: bool, scratch: *binary.Buffer) -> (usize, err) {
    let (signature, signature_error) = signature_hash(c, g, checked_function, scratch)
    if signature_error != ok { ret (0usize, signature_error) }
    scratch.count = 0usize
    let signature_write_error = binary.little_u64(scratch, signature)
    if signature_write_error != ok { ret (0usize, signature_write_error) }
    if checked_function >= c.function_count { ret (0usize, InvalidArtifact) }
    let function = c.functions[checked_function]
    // The declaration's tokens whenever it has them (D214): the same hash whether or
    // not the function was lowered, which is what lets a module be kept unlowered;
    // NIR only for a function with no source of its own.
    if function.source_end > function.source_start && function.module_index < g.count {
        let marker_error = binary.byte(scratch, 2usize)
        if marker_error != ok { ret (0usize, marker_error) }
        // The line the declaration starts on is part of the hash (D322): a copy of the
        // body inlined into another module, or an instance made by one, carries this
        // module's line numbers in its line table, so a function that moved down the
        // file has a different body for them even when its tokens are the same.
        let line = lex.line_of(g.modules[function.module_index].text, g.modules[function.module_index].lines, function.source_start)
        let line_error = binary.little_u32(scratch, line)
        if line_error != ok { ret (0usize, line_error) }
        let tokens_error = write_declaration_tokens_canonical(g.modules[function.module_index].text, g.modules[function.module_index].tokens, function.source_start, function.source_end, scratch)
        if tokens_error != ok { ret (0usize, tokens_error) }
    } else {
        if has_nir {
            let marker_error = binary.byte(scratch, 1usize)
            if marker_error != ok { ret (0usize, marker_error) }
            let nir_error = write_nir_canonical(c, g, builder, nir_function, scratch)
            if nir_error != ok { ret (0usize, nir_error) }
        } else {
            let marker_error = binary.byte(scratch, 0usize)
            if marker_error != ok { ret (0usize, marker_error) }
        }
    }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

// Where a module's rows lie in each program-wide table (D320). The writer walked every
// table from its first row for every module it wrote -- the functions, aggregates,
// aliases, constants and symbols of the whole program, the builder's functions, globals
// and inlined entries -- and at two million lines those walks were most of the writer.
// The tables are append-only and one module's rows sit together, so a first and an end
// per module and table, extended over the rows appended since the last call, make each
// walk the module's own rows and little else. The checker carries the spans; a builder
// table that shrank -- a mark reset -- is scanned again from its first row.
fn span_functions() -> usize { ret 0usize }
fn span_instances() -> usize { ret 1usize }
fn span_aggregates() -> usize { ret 2usize }
fn span_aliases() -> usize { ret 3usize }
fn span_constants() -> usize { ret 4usize }
fn span_symbols() -> usize { ret 5usize }
fn span_nir() -> usize { ret 6usize }
fn span_globals() -> usize { ret 7usize }
fn span_inlined() -> usize { ret 8usize }
fn span_tables() -> usize { ret 9usize }

fn span_modules(c: *check.Checker) -> usize {
    ret c.writer_spans.len / (span_tables() * 2usize)
}

fn span_extend(c: *check.Checker, table: usize, module_index: usize, row: usize) {
    let modules = span_modules(c)
    if module_index >= modules { ret }
    let at = (table * modules + module_index) * 2usize
    if c.writer_spans[at + 1usize] == 0usize { c.writer_spans[at] = row }
    c.writer_spans[at + 1usize] = row + 1usize
}

fn span_of(c: *check.Checker, table: usize, module_index: usize) -> (usize, usize) {
    let modules = span_modules(c)
    if module_index >= modules { ret (0usize, 0usize) }
    let at = (table * modules + module_index) * 2usize
    ret (c.writer_spans[at], c.writer_spans[at + 1usize])
}

fn span_clear(c: *check.Checker, table: usize) {
    let modules = span_modules(c)
    var at = table * modules * 2usize
    while at < (table + 1usize) * modules * 2usize {
        c.writer_spans[at] = 0usize
        at += 1usize
    }
    c.writer_scanned[table] = 0usize
}

fn update_spans(c: *check.Checker, builder: *nir.Builder) -> err {
    if c.writer_spans.len == 0usize { ret InvalidArtifact }
    var at = c.writer_scanned[span_functions()]
    while at < c.signature_function_count {
        span_extend(c, span_functions(), c.functions[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_functions()] = c.signature_function_count
    // An instance is owned by the module that instantiated it.
    at = c.writer_scanned[span_instances()]
    if at < c.signature_function_count { at = c.signature_function_count }
    while at < c.function_count {
        span_extend(c, span_instances(), c.functions[at].owner_module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_instances()] = c.function_count
    at = c.writer_scanned[span_aggregates()]
    while at < c.aggregate_count {
        span_extend(c, span_aggregates(), c.aggregates[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_aggregates()] = c.aggregate_count
    at = c.writer_scanned[span_aliases()]
    while at < c.alias_count {
        span_extend(c, span_aliases(), c.aliases[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_aliases()] = c.alias_count
    at = c.writer_scanned[span_constants()]
    while at < c.constant_count {
        span_extend(c, span_constants(), c.constants[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_constants()] = c.constant_count
    at = c.writer_scanned[span_symbols()]
    while at < c.resolver.count {
        span_extend(c, span_symbols(), c.resolver.symbols[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_symbols()] = c.resolver.count
    if builder.function_count < c.writer_scanned[span_nir()] { span_clear(c, span_nir()) }
    at = c.writer_scanned[span_nir()]
    while at < builder.function_count {
        span_extend(c, span_nir(), builder.functions[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_nir()] = builder.function_count
    if builder.global_count < c.writer_scanned[span_globals()] { span_clear(c, span_globals()) }
    at = c.writer_scanned[span_globals()]
    while at < builder.global_count {
        span_extend(c, span_globals(), builder.globals[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_globals()] = builder.global_count
    if builder.inlined_count < c.writer_scanned[span_inlined()] { span_clear(c, span_inlined()) }
    at = c.writer_scanned[span_inlined()]
    while at < builder.inlined_count {
        span_extend(c, span_inlined(), builder.inlined[at].caller_module, at)
        at += 1usize
    }
    c.writer_scanned[span_inlined()] = builder.inlined_count
    ret ok
}

fn collect_module_strings(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable) -> err {
    if module_index >= g.count { ret InvalidArtifact }
    try update_spans(c, builder)
    try mark_module_references(builder, c, module_index)
    let (module_name, module_name_error) = intern(table, g.modules[module_index].name)
    if module_name_error != ok { ret module_name_error }
    let (source_path, source_path_error) = intern(table, g.modules[module_index].path)
    if source_path_error != ok { ret source_path_error }
    var import_at = g.modules[module_index].first_import
    while import_at < g.modules[module_index].first_import + g.modules[module_index].import_count {
        let (import_name, import_name_error) = intern(table, g.imports[import_at].name)
        if import_name_error != ok { ret import_name_error }
        let (import_qualifier, import_qualifier_error) = intern(table, g.imports[import_at].qualifier)
        if import_qualifier_error != ok { ret import_qualifier_error }
        import_at += 1usize
    }
    let (function_first, function_end) = span_of(c, span_functions(), module_index)
    var function_at = function_first
    while function_at < function_end {
        if c.functions[function_at].module_index == module_index {
            let function = c.functions[function_at]
            let (function_name, function_name_error) = intern(table, function.name)
            if function_name_error != ok { ret function_name_error }
            let generic = c.function_generics[function_at]
            var at = 0usize
            while at < generic.comptime_count {
                if generic.first_comptime + at >= c.comptime_parameter_count { ret InvalidArtifact }
                let parameter = c.comptime_parameters[generic.first_comptime + at]
                let (parameter_name, parameter_name_error) = intern(table, parameter.name)
                if parameter_name_error != ok { ret parameter_name_error }
                try collect_type_strings(c, g, table, parameter.ty)
                at += 1usize
            }
            at = 0usize
            while at < function.parameter_count {
                if function.first_parameter + at >= c.parameter_count { ret InvalidArtifact }
                let parameter = c.parameters[function.first_parameter + at]
                let (parameter_name, parameter_name_error) = intern(table, parameter.name)
                if parameter_name_error != ok { ret parameter_name_error }
                try collect_type_strings(c, g, table, parameter.ty)
                at += 1usize
            }
            at = 0usize
            while at < function.return_count {
                if function.first_return + at >= c.return_type_count { ret InvalidArtifact }
                try collect_type_strings(c, g, table, c.return_types[function.first_return + at])
                at += 1usize
            }
        }
        function_at += 1usize
    }
    let (instance_first, instance_end) = span_of(c, span_instances(), module_index)
    var template_at = instance_first
    while template_at < instance_end {
        let (template_index, records_template) = owned_template_dependency(c, module_index, template_at)
        if records_template {
            let template = c.functions[template_index]
            if template.module_index >= g.count { ret InvalidArtifact }
            let (template_module_name, template_module_error) = intern(table, g.modules[template.module_index].name)
            if template_module_error != ok { ret template_module_error }
            let (template_name, template_name_error) = intern(table, template.name)
            if template_name_error != ok { ret template_name_error }
        }
        template_at += 1usize
    }
    let (aggregate_first, aggregate_end) = span_of(c, span_aggregates(), module_index)
    var aggregate_at = aggregate_first
    while aggregate_at < aggregate_end {
        if c.aggregates[aggregate_at].module_index == module_index && !c.aggregates[aggregate_at].instance && !builtin_aggregate(c.aggregates[aggregate_at].name) {
            let aggregate = c.aggregates[aggregate_at]
            let (aggregate_name, aggregate_name_error) = intern(table, aggregate.name)
            if aggregate_name_error != ok { ret aggregate_name_error }
            var at = 0usize
            while at < aggregate.comptime_count {
                let parameter = c.comptime_parameters[aggregate.first_comptime + at]
                let (parameter_name, parameter_name_error) = intern(table, parameter.name)
                if parameter_name_error != ok { ret parameter_name_error }
                try collect_type_strings(c, g, table, parameter.ty)
                at += 1usize
            }
            if aggregate.kind == .Enum || aggregate.kind == .TaggedUnion { try collect_type_strings(c, g, table, aggregate.backing_type) }
            at = 0usize
            while at < aggregate.field_count {
                let field = c.aggregate_fields[aggregate.first_field + at]
                let (field_name, field_name_error) = intern(table, field.name)
                if field_name_error != ok { ret field_name_error }
                try collect_type_strings(c, g, table, field.ty)
                at += 1usize
            }
        }
        aggregate_at += 1usize
    }
    let (alias_first, alias_end) = span_of(c, span_aliases(), module_index)
    var alias_at = alias_first
    while alias_at < alias_end {
        if c.aliases[alias_at].module_index == module_index {
            let alias = c.aliases[alias_at]
            let (alias_name, alias_name_error) = intern(table, alias.name)
            if alias_name_error != ok { ret alias_name_error }
            if !alias.generic { try collect_type_strings(c, g, table, alias.resolved) }
        }
        alias_at += 1usize
    }
    let (constant_first, constant_end) = span_of(c, span_constants(), module_index)
    var constant_at = constant_first
    while constant_at < constant_end {
        if c.constants[constant_at].module_index == module_index {
            let constant = c.constants[constant_at]
            let (constant_name, constant_name_error) = intern(table, constant.name)
            if constant_name_error != ok { ret constant_name_error }
            try collect_type_strings(c, g, table, constant.ty)
        }
        constant_at += 1usize
    }
    constant_at = 0usize
    while constant_at < c.constant_count {
        let constant = c.constants[constant_at]
        if constant.module_index != module_index {
            let (used, used_error) = foreign_constant_used_by_module(c, module_index, constant_at)
            if used_error != ok { ret used_error }
            if used {
                if constant.module_index >= g.count { ret InvalidArtifact }
                let (target_module_name, target_module_name_error) = intern(table, g.modules[constant.module_index].name)
                if target_module_name_error != ok { ret target_module_name_error }
                let (target_constant_name, target_constant_name_error) = intern(table, constant.name)
                if target_constant_name_error != ok { ret target_constant_name_error }
            }
        }
        constant_at += 1usize
    }
    let (symbol_first, symbol_end) = span_of(c, span_symbols(), module_index)
    var symbol_at = symbol_first
    while symbol_at < symbol_end {
        if c.resolver.symbols[symbol_at].module_index == module_index && c.resolver.symbols[symbol_at].kind == .Error {
            let (error_name, error_name_error) = intern(table, c.resolver.symbols[symbol_at].name)
            if error_name_error != ok { ret error_name_error }
        }
        symbol_at += 1usize
    }
    // An inlined callee (D207) is named by a body edge with no instruction of its own.
    let (inlined_first, inlined_end) = span_of(c, span_inlined(), module_index)
    var inlined_at = inlined_first
    while inlined_at < inlined_end {
        let entry = builder.inlined[inlined_at]
        if entry.caller_module == module_index && entry.callee_module != module_index && entry.callee_module < g.count {
            let (callee_module, callee_module_error) = intern(table, g.modules[entry.callee_module].name)
            if callee_module_error != ok { ret callee_module_error }
            let (callee_name, callee_name_error) = intern(table, entry.name)
            if callee_name_error != ok { ret callee_name_error }
        }
        inlined_at += 1usize
    }
    // A trap site (D194) names the runtime's `neper_trap` from a relocation alone -- no
    // instruction carries it -- so its strings are collected from the references.
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        if builder.function_refs[reference_at].module_index == module_index {
            let reference = builder.function_refs[reference_at]
            if same(reference.name, "neper_trap") || same(reference.name, "neper_symbols") {
                let (trap_module, trap_module_error) = intern(table, g.modules[module_index].name)
                if trap_module_error != ok { ret trap_module_error }
                let (trap_name, trap_name_error) = intern(table, reference.name)
                if trap_name_error != ok { ret trap_name_error }
            }
        }
        // An import's library and symbol ride its relocations (D319), which the
        // module's own calls place.
        if builder.used_marks[reference_at] == 1u8 && builder.function_refs[reference_at].library.len != 0usize {
            let (library_index, library_error) = intern(table, builder.function_refs[reference_at].library)
            if library_error != ok { ret library_error }
            let (symbol_index, symbol_error) = intern(table, builder.function_refs[reference_at].symbol)
            if symbol_error != ok { ret symbol_error }
        }
        reference_at += 1usize
    }
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            let function = builder.functions[function_at]
            let (function_name, function_name_error) = intern(table, function.name)
            if function_name_error != ok { ret function_name_error }
            var instruction_at = function.first_instruction
            while instruction_at < function.first_instruction + function.instruction_count {
                let instruction = builder.instructions[instruction_at]
                try collect_type_strings(c, g, table, instruction.ty)
                if instruction.opcode == .Call || instruction.opcode == .FunctionAddress {
                    if instruction.immediate >= builder.function_ref_count { ret InvalidArtifact }
                    let reference = builder.function_refs[instruction.immediate]
                    if reference.module_index >= g.count { ret InvalidArtifact }
                    let (target_module, target_module_error) = intern(table, g.modules[reference.module_index].name)
                    if target_module_error != ok { ret target_module_error }
                    let (target_name, target_name_error) = intern(table, reference.name)
                    if target_name_error != ok { ret target_name_error }
                    let (dependency_name, records_dependency) = dependency_reference_name(reference.name)
                    if records_dependency {
                        let (stored_dependency_name, dependency_name_error) = intern(table, dependency_name)
                        if dependency_name_error != ok { ret dependency_name_error }
                    }
                }
                if instruction.opcode == .GlobalAddress {
                    if instruction.immediate >= builder.global_count { ret InvalidArtifact }
                    let global = builder.globals[instruction.immediate]
                    if global.module_index >= g.count { ret InvalidArtifact }
                    let (global_module, global_module_error) = intern(table, g.modules[global.module_index].name)
                    if global_module_error != ok { ret global_module_error }
                    let (global_name, global_name_error) = intern(table, global.name)
                    if global_name_error != ok { ret global_name_error }
                }
                instruction_at += 1usize
            }
        }
        function_at += 1usize
    }
    let (global_first, global_end) = span_of(c, span_globals(), module_index)
    var global_at = global_first
    while global_at < global_end {
        if builder.globals[global_at].module_index == module_index {
            let (global_name, global_name_error) = intern(table, builder.globals[global_at].name)
            if global_name_error != ok { ret global_name_error }
        }
        global_at += 1usize
    }
    ret ok
}

fn source_function_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_functions(), module_index)
    var at = first
    while at < end {
        if c.functions[at].module_index == module_index { count += 1usize }
        at += 1usize
    }
    ret count
}

// Section 2's `target.Arch` and `target.Os` are seeded into the root module (D223)
// and are the language's, not a declaration of it: no Interface carries them.
fn builtin_aggregate(name: str) -> bool {
    ret same(name, "target.Arch") || same(name, "target.Os")
}

fn module_aggregate_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_aggregates(), module_index)
    var at = first
    while at < end {
        if c.aggregates[at].module_index == module_index && !c.aggregates[at].instance && !builtin_aggregate(c.aggregates[at].name) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn module_alias_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_aliases(), module_index)
    var at = first
    while at < end {
        if c.aliases[at].module_index == module_index { count += 1usize }
        at += 1usize
    }
    ret count
}

fn module_constant_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_constants(), module_index)
    var at = first
    while at < end {
        if c.constants[at].module_index == module_index { count += 1usize }
        at += 1usize
    }
    ret count
}

fn module_error_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_symbols(), module_index)
    var at = first
    while at < end {
        if c.resolver.symbols[at].module_index == module_index && c.resolver.symbols[at].kind == .Error { count += 1usize }
        at += 1usize
    }
    ret count
}

fn interface_declaration_count(c: *check.Checker, module_index: usize) -> usize {
    ret source_function_count(c, module_index) + module_aggregate_count(c, module_index) + module_alias_count(c, module_index) + module_constant_count(c, module_index) + module_error_count(c, module_index)
}

fn module_nir_function_count(builder: *nir.Builder, c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_nir(), module_index)
    var at = first
    while at < end {
        if builder.functions[at].module_index == module_index { count += 1usize }
        at += 1usize
    }
    ret count
}

fn write_function_interface(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, table: *StringTable, function_index: usize, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let function = c.functions[function_index]
    let (name_index, name_error) = string_index(table, function.name)
    if name_error != ok { ret name_error }
    let (signature, signature_error) = signature_hash(c, g, function_index, scratch)
    if signature_error != ok { ret signature_error }
    let (body, body_error) = body_hash(c, g, builder, function_index, 0usize, false, scratch)
    if body_error != ok { ret body_error }
    try binary.byte(output, declaration_function_kind())
    try binary.byte(output, function_flags(function))
    try binary.little_u16(output, 0usize)
    let length_offset = output.count
    try binary.little_u32(output, 0usize)
    let payload_start = output.count
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    let generic = c.function_generics[function_index]
    try binary.little_u32(output, generic.comptime_count)
    var at = 0usize
    while at < generic.comptime_count {
        let parameter = c.comptime_parameters[generic.first_comptime + at]
        let kind = comptime_kind_id(parameter.kind)
        if kind == 0usize { ret InvalidArtifact }
        let (parameter_name, parameter_name_error) = string_index(table, parameter.name)
        if parameter_name_error != ok { ret parameter_name_error }
        try binary.byte(output, kind)
        try binary.zeroes(output, 3usize)
        try binary.little_u32(output, parameter_name)
        if parameter.kind == .Integer { try write_type_indexed(c, g, table, parameter.ty, output) }
        at += 1usize
    }
    try binary.little_u32(output, function.parameter_count)
    at = 0usize
    while at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + at]
        let (parameter_name, parameter_name_error) = string_index(table, parameter.name)
        if parameter_name_error != ok { ret parameter_name_error }
        try binary.little_u32(output, parameter_name)
        try write_type_indexed(c, g, table, parameter.ty, output)
        at += 1usize
    }
    try binary.little_u32(output, function.return_count)
    at = 0usize
    while at < function.return_count {
        try write_type_indexed(c, g, table, c.return_types[function.first_return + at], output)
        at += 1usize
    }
    ret binary.patch_little_u32(output, length_offset, output.count - payload_start)
}

fn write_aggregate_interface(c: *check.Checker, g: *graph.Graph, table: *StringTable, aggregate_index: usize, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let aggregate = c.aggregates[aggregate_index]
    let (name_index, name_error) = string_index(table, aggregate.name)
    if name_error != ok { ret name_error }
    let (signature, signature_error) = aggregate_signature_hash(c, g, aggregate_index, scratch)
    if signature_error != ok { ret signature_error }
    let (body, body_error) = signature_only_body_hash(signature, scratch)
    if body_error != ok { ret body_error }
    try binary.byte(output, declaration_aggregate_kind())
    if aggregate.generic { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
    try binary.little_u16(output, 0usize)
    let length_offset = output.count
    try binary.little_u32(output, 0usize)
    let payload_start = output.count
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    let kind = aggregate_kind_id(aggregate.kind)
    if kind == 0usize { ret InvalidArtifact }
    try binary.byte(output, kind)
    try binary.zeroes(output, 3usize)
    try binary.little_u32(output, aggregate.comptime_count)
    var at = 0usize
    while at < aggregate.comptime_count {
        let parameter = c.comptime_parameters[aggregate.first_comptime + at]
        let parameter_kind = comptime_kind_id(parameter.kind)
        if parameter_kind == 0usize { ret InvalidArtifact }
        let (parameter_name, parameter_name_error) = string_index(table, parameter.name)
        if parameter_name_error != ok { ret parameter_name_error }
        try binary.byte(output, parameter_kind)
        try binary.zeroes(output, 3usize)
        try binary.little_u32(output, parameter_name)
        if parameter.kind == .Integer { try write_type_indexed(c, g, table, parameter.ty, output) }
        at += 1usize
    }
    if aggregate.kind == .Enum || aggregate.kind == .TaggedUnion {
        try binary.byte(output, 1usize)
        try write_type_indexed(c, g, table, aggregate.backing_type, output)
    } else {
        try binary.byte(output, 0usize)
    }
    try binary.little_u32(output, aggregate.field_count)
    at = 0usize
    while at < aggregate.field_count {
        let field = c.aggregate_fields[aggregate.first_field + at]
        let (field_name, field_name_error) = string_index(table, field.name)
        if field_name_error != ok { ret field_name_error }
        try binary.little_u32(output, field_name)
        try write_type_indexed(c, g, table, field.ty, output)
        if field.has_enum_value { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        if field.enum_negative { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        try binary.little_u16(output, 0usize)
        try binary.little_u64(output, field.enum_value)
        at += 1usize
    }
    ret binary.patch_little_u32(output, length_offset, output.count - payload_start)
}

fn write_alias_interface(c: *check.Checker, g: *graph.Graph, table: *StringTable, alias_index: usize, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let alias = c.aliases[alias_index]
    let (name_index, name_error) = string_index(table, alias.name)
    if name_error != ok { ret name_error }
    let (signature, signature_error) = alias_signature_hash(c, g, alias_index, scratch)
    if signature_error != ok { ret signature_error }
    let (body, body_error) = signature_only_body_hash(signature, scratch)
    if body_error != ok { ret body_error }
    try binary.byte(output, declaration_alias_kind())
    if alias.generic { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
    try binary.little_u16(output, 0usize)
    let length_offset = output.count
    try binary.little_u32(output, 0usize)
    let payload_start = output.count
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    if alias.generic {
        try binary.byte(output, 0usize)
    } else {
        try binary.byte(output, 1usize)
        try write_type_indexed(c, g, table, alias.resolved, output)
    }
    ret binary.patch_little_u32(output, length_offset, output.count - payload_start)
}

fn write_constant_interface(c: *check.Checker, g: *graph.Graph, table: *StringTable, constant_index: usize, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let constant = c.constants[constant_index]
    let (name_index, name_error) = string_index(table, constant.name)
    if name_error != ok { ret name_error }
    let (signature, signature_error) = constant_signature_hash(c, g, constant_index, scratch)
    if signature_error != ok { ret signature_error }
    let (body, body_error) = constant_body_hash(c, g, constant_index, scratch)
    if body_error != ok { ret body_error }
    try binary.byte(output, declaration_constant_kind())
    try binary.zeroes(output, 3usize)
    let length_offset = output.count
    try binary.little_u32(output, 0usize)
    let payload_start = output.count
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    try write_type_indexed(c, g, table, constant.ty, output)
    if constant.value.negative { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
    try binary.zeroes(output, 3usize)
    try binary.little_u64(output, constant.value.magnitude)
    ret binary.patch_little_u32(output, length_offset, output.count - payload_start)
}

fn write_error_interface(g: *graph.Graph, table: *StringTable, symbol: resolve.Symbol, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let (name_index, name_error) = string_index(table, symbol.name)
    if name_error != ok { ret name_error }
    let (signature, signature_error) = error_signature_hash(g, symbol, scratch)
    if signature_error != ok { ret signature_error }
    let (body, body_error) = signature_only_body_hash(signature, scratch)
    if body_error != ok { ret body_error }
    let (value, value_error) = artifact_hash.qualified_error_value(g.modules[symbol.module_index].name, symbol.name)
    if value_error != ok || value == 0usize { ret InvalidArtifact }
    try binary.byte(output, declaration_error_kind())
    try binary.zeroes(output, 3usize)
    try binary.little_u32(output, 24usize)
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    ret binary.little_u32(output, value)
}

fn write_interface(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    let section_start = output.count
    try binary.little_u64(output, 0usize)
    try binary.little_u32(output, interface_declaration_count(c, module_index))
    let (stored_module_index, stored_module_error) = string_index(table, g.modules[module_index].name)
    if stored_module_error != ok { ret stored_module_error }
    try binary.little_u32(output, stored_module_index)
    let (function_first, function_end) = span_of(c, span_functions(), module_index)
    var at = function_first
    while at < function_end {
        if c.functions[at].module_index == module_index { try write_function_interface(c, g, builder, table, at, scratch, output) }
        at += 1usize
    }
    let (aggregate_first, aggregate_end) = span_of(c, span_aggregates(), module_index)
    at = aggregate_first
    while at < aggregate_end {
        if c.aggregates[at].module_index == module_index && !c.aggregates[at].instance && !builtin_aggregate(c.aggregates[at].name) { try write_aggregate_interface(c, g, table, at, scratch, output) }
        at += 1usize
    }
    let (alias_first, alias_end) = span_of(c, span_aliases(), module_index)
    at = alias_first
    while at < alias_end {
        if c.aliases[at].module_index == module_index { try write_alias_interface(c, g, table, at, scratch, output) }
        at += 1usize
    }
    let (constant_first, constant_end) = span_of(c, span_constants(), module_index)
    at = constant_first
    while at < constant_end {
        if c.constants[at].module_index == module_index { try write_constant_interface(c, g, table, at, scratch, output) }
        at += 1usize
    }
    let (symbol_first, symbol_end) = span_of(c, span_symbols(), module_index)
    at = symbol_first
    while at < symbol_end {
        if c.resolver.symbols[at].module_index == module_index && c.resolver.symbols[at].kind == .Error { try write_error_interface(g, table, c.resolver.symbols[at], scratch, output) }
        at += 1usize
    }
    try binary.little_u32(output, module_error_count(c, module_index))
    at = symbol_first
    while at < symbol_end {
        let symbol = c.resolver.symbols[at]
        if symbol.module_index == module_index && symbol.kind == .Error {
            let (value, value_error) = artifact_hash.qualified_error_value(g.modules[module_index].name, symbol.name)
            if value_error != ok || value == 0usize { ret InvalidArtifact }
            let (name_index, name_error) = string_index(table, symbol.name)
            if name_error != ok { ret name_error }
            try binary.little_u32(output, value)
            try binary.little_u32(output, name_index)
        }
        at += 1usize
    }
    let (interface_hash, interface_hash_error) = artifact_hash.xxhash64(output.bytes[section_start..output.count])
    if interface_hash_error != ok { ret interface_hash_error }
    ret binary.patch_little_u64(output, section_start, interface_hash)
}

// The module's references marked in one pass (D319), and its edges with them (D320): a
// used reference to another module's declaration records a signature edge unless an
// earlier reference resolves to the same declaration -- distinct generic instances
// intern distinct references -- and an inlined entry stands for its body edge unless an
// earlier entry of the module names the callee. The index dedupes both; the walks it
// replaces compared every used reference against every earlier one, per module.
fn mark_module_references(builder: *nir.Builder, c: *check.Checker, module_index: usize) -> err {
    if builder.used_marks_valid && builder.used_marks_module == module_index { ret ok }
    if builder.function_ref_count == 0usize && builder.inlined_count == 0usize {
        builder.used_count = 0usize
        builder.used_marks_module = module_index
        builder.used_marks_valid = true
        ret ok
    }
    if builder.used_marks.len < builder.function_ref_count || builder.edge_marks.len < builder.function_ref_count || builder.inlined_marks.len < builder.inlined_count { ret InvalidArtifact }
    var clear_at = 0usize
    while clear_at < builder.function_ref_count {
        builder.used_marks[clear_at] = 0u8
        builder.edge_marks[clear_at] = 0u8
        clear_at += 1usize
    }
    builder.used_count = 0usize
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            let function = builder.functions[function_at]
            var instruction_at = function.first_instruction
            while instruction_at < function.first_instruction + function.instruction_count {
                let instruction = builder.instructions[instruction_at]
                if (instruction.opcode == .Call || instruction.opcode == .FunctionAddress) && instruction.immediate < builder.function_ref_count && builder.used_marks[instruction.immediate] == 0u8 {
                    builder.used_marks[instruction.immediate] = 1u8
                    if builder.used_count < builder.used_list.len {
                        builder.used_list[builder.used_count] = instruction.immediate
                        builder.used_count += 1usize
                    }
                }
                instruction_at += 1usize
            }
        }
        function_at += 1usize
    }
    try lookup.attach(&builder.edge_index, builder.edge_index.entries)
    var at = 0usize
    while at < builder.function_ref_count {
        if builder.used_marks[at] == 1u8 && builder.function_refs[at].module_index != module_index {
            let reference = builder.function_refs[at]
            let (dependency_name, records_dependency) = dependency_reference_name(reference.name)
            if records_dependency {
                let (seen_at, seen) = lookup.find(&builder.edge_index, reference.module_index, 1usize, dependency_name)
                if !seen {
                    try lookup.insert(&builder.edge_index, reference.module_index, 1usize, dependency_name, at)
                    builder.edge_marks[at] = 1u8
                }
            }
        }
        at += 1usize
    }
    let (inlined_first, inlined_end) = span_of(c, span_inlined(), module_index)
    at = inlined_first
    while at < inlined_end {
        builder.inlined_marks[at] = 0u8
        let entry = builder.inlined[at]
        if entry.caller_module == module_index && entry.callee_module != module_index {
            let (seen_at, seen) = lookup.find(&builder.edge_index, entry.callee_module, 16usize + entry.instance, entry.name)
            if !seen {
                try lookup.insert(&builder.edge_index, entry.callee_module, 16usize + entry.instance, entry.name, at)
                builder.inlined_marks[at] = 1u8
            }
        }
        at += 1usize
    }
    builder.used_marks_module = module_index
    builder.used_marks_valid = true
    ret ok
}


fn constant_expression_references(c: *check.Checker, expression_index: usize, module_index: usize, name: str) -> (bool, err) {
    if expression_index >= c.constant_expr_count { ret (false, InvalidArtifact) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .Name { ret (expression.module_index == module_index && same(expression.name, name), ok) }
    if expression.kind == .Unary {
        let (references, reference_error) = constant_expression_references(c, expression.left, module_index, name)
        ret (references, reference_error)
    }
    if expression.kind == .Binary {
        let (left, left_error) = constant_expression_references(c, expression.left, module_index, name)
        if left_error != ok || left { ret (left, left_error) }
        if !expression.has_right { ret (false, InvalidArtifact) }
        let (right, right_error) = constant_expression_references(c, expression.right, module_index, name)
        ret (right, right_error)
    }
    ret (false, ok)
}

fn foreign_constant_used_by_module(c: *check.Checker, module_index: usize, target_constant: usize) -> (bool, err) {
    if target_constant >= c.constant_count { ret (false, InvalidArtifact) }
    let target_item = c.constants[target_constant]
    if target_item.module_index == module_index { ret (false, ok) }
    let (first, end) = span_of(c, span_constants(), module_index)
    var at = first
    while at < end {
        if c.constants[at].module_index == module_index {
            let (references, reference_error) = constant_expression_references(c, c.constants[at].expression, target_item.module_index, target_item.name)
            if reference_error != ok { ret (false, reference_error) }
            if references { ret (true, ok) }
        }
        at += 1usize
    }
    ret (false, ok)
}

fn module_dependency_reference(builder: *nir.Builder, module_index: usize, at: usize) -> (str, bool) {
    if at >= builder.function_ref_count || !builder.used_marks_valid || builder.used_marks_module != module_index || builder.edge_marks[at] == 0u8 { ret ("", false) }
    let (dependency_name, records_dependency) = dependency_reference_name(builder.function_refs[at].name)
    ret (dependency_name, records_dependency)
}

fn owned_template_dependency(c: *check.Checker, module_index: usize, at: usize) -> (usize, bool) {
    if at >= c.function_count { ret (0usize, false) }
    let generic = c.function_generics[at]
    if !generic.instance || c.functions[at].generic { ret (0usize, false) }
    if c.functions[at].owner_module_index != module_index { ret (0usize, false) }
    let template_index = generic.template_index
    if template_index >= c.function_count || c.functions[template_index].module_index == module_index { ret (0usize, false) }
    let (first, end) = span_of(c, span_instances(), module_index)
    var prior = first
    if prior < c.signature_function_count { prior = c.signature_function_count }
    while prior < at {
        let earlier = c.function_generics[prior]
        if earlier.instance && !c.functions[prior].generic && c.functions[prior].owner_module_index == module_index && earlier.template_index == template_index { ret (0usize, false) }
        prior += 1usize
    }
    ret (template_index, true)
}

fn template_dependency_count(c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_instances(), module_index)
    var at = first
    while at < end {
        let (template_index, records) = owned_template_dependency(c, module_index, at)
        if records { count += 1usize }
        at += 1usize
    }
    ret count
}

fn dependency_count(builder: *nir.Builder, c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    var at = 0usize
    while at < builder.function_ref_count {
        let (dependency_name, records_dependency) = module_dependency_reference(builder, module_index, at)
        if records_dependency { count += 1usize }
        at += 1usize
    }
    ret count + inlined_dependency_count(builder, c, module_index)
}

// Section 12's body edges: a callee of another module whose NIR was copied into this
// one (D207). The edge carries the body hash the callee's own artifact writes for it.
fn inlined_dependency_count(builder: *nir.Builder, c: *check.Checker, module_index: usize) -> usize {
    var count = 0usize
    let (first, end) = span_of(c, span_inlined(), module_index)
    var at = first
    while at < end {
        if first_inlined(builder, module_index, at) { count += 1usize }
        at += 1usize
    }
    ret count
}

// The refs are recorded per copying function (D212); the edge is per module, so an
// entry stands for its edge only when no earlier entry of the module names the callee,
// as `mark_module_references` marked it.
fn first_inlined(builder: *nir.Builder, module_index: usize, index: usize) -> bool {
    ret builder.used_marks_valid && builder.used_marks_module == module_index && index < builder.inlined_marks.len && builder.inlined_marks[index] == 1u8
}

fn value_dependency_count(c: *check.Checker, module_index: usize) -> (usize, err) {
    var count = 0usize
    var at = 0usize
    while at < c.constant_count {
        let (used, used_error) = foreign_constant_used_by_module(c, module_index, at)
        if used_error != ok { ret (0usize, used_error) }
        if used { count += 1usize }
        at += 1usize
    }
    ret (count, ok)
}

fn write_dependencies(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    try mark_module_references(builder, c, module_index)
    let (value_count, value_count_error) = value_dependency_count(c, module_index)
    if value_count_error != ok { ret value_count_error }
    try binary.little_u32(output, dependency_count(builder, c, module_index) + template_dependency_count(c, module_index) + value_count)
    var at = 0usize
    while at < builder.function_ref_count {
        let reference = builder.function_refs[at]
        let (dependency_name, records_dependency) = module_dependency_reference(builder, module_index, at)
        if records_dependency {
            if reference.module_index >= g.count { ret InvalidArtifact }
            let (checked_function, found_function) = find_checked_function(c, reference.module_index, dependency_name)
            if !found_function { ret InvalidArtifact }
            let (hash, hash_error) = signature_hash(c, g, checked_function, scratch)
            if hash_error != ok { ret hash_error }
            let (target_module, target_module_error) = string_index(table, g.modules[reference.module_index].name)
            if target_module_error != ok { ret target_module_error }
            let (target_name, target_name_error) = string_index(table, dependency_name)
            if target_name_error != ok { ret target_name_error }
            try binary.byte(output, dependency_signature_kind())
            try binary.zeroes(output, 3usize)
            try binary.little_u32(output, target_module)
            try binary.little_u32(output, target_name)
            try binary.little_u64(output, hash)
        }
        at += 1usize
    }
    let (inlined_first, inlined_end) = span_of(c, span_inlined(), module_index)
    at = inlined_first
    while at < inlined_end {
        if first_inlined(builder, module_index, at) {
            let entry = builder.inlined[at]
            if entry.callee_module >= g.count { ret InvalidArtifact }
            let (checked_function, found_checked) = find_checked_function(c, entry.callee_module, entry.name)
            if !found_checked { ret InvalidArtifact }
            // The hash is over the declaration's tokens whenever it has them; the NIR
            // is looked up -- a walk over every function -- only for one that has none.
            var nir_function = 0usize
            var found_nir = false
            if c.functions[checked_function].source_end <= c.functions[checked_function].source_start {
                let (lowered, found_lowered) = find_nir_function(builder, entry.callee_module, entry.name, entry.instance)
                nir_function = lowered
                found_nir = found_lowered
            }
            let (hash, hash_error) = body_hash(c, g, builder, checked_function, nir_function, found_nir, scratch)
            if hash_error != ok { ret hash_error }
            let (target_module, target_module_error) = string_index(table, g.modules[entry.callee_module].name)
            if target_module_error != ok { ret target_module_error }
            let (target_name, target_name_error) = string_index(table, entry.name)
            if target_name_error != ok { ret target_name_error }
            try binary.byte(output, dependency_body_kind())
            try binary.zeroes(output, 3usize)
            try binary.little_u32(output, target_module)
            try binary.little_u32(output, target_name)
            try binary.little_u64(output, hash)
        }
        at += 1usize
    }
    let (instance_first, instance_end) = span_of(c, span_instances(), module_index)
    at = instance_first
    while at < instance_end {
        let (template_index, records_template) = owned_template_dependency(c, module_index, at)
        if records_template {
            let template = c.functions[template_index]
            if template.module_index >= g.count { ret InvalidArtifact }
            let (hash, hash_error) = body_hash(c, g, builder, template_index, 0usize, false, scratch)
            if hash_error != ok { ret hash_error }
            let (target_module, target_module_error) = string_index(table, g.modules[template.module_index].name)
            if target_module_error != ok { ret target_module_error }
            let (target_name, target_name_error) = string_index(table, template.name)
            if target_name_error != ok { ret target_name_error }
            try binary.byte(output, dependency_body_kind())
            try binary.zeroes(output, 3usize)
            try binary.little_u32(output, target_module)
            try binary.little_u32(output, target_name)
            try binary.little_u64(output, hash)
        }
        at += 1usize
    }
    at = 0usize
    while at < c.constant_count {
        let (used, used_error) = foreign_constant_used_by_module(c, module_index, at)
        if used_error != ok { ret used_error }
        if used {
            let constant = c.constants[at]
            if constant.module_index >= g.count { ret InvalidArtifact }
            let (hash, hash_error) = constant_body_hash(c, g, at, scratch)
            if hash_error != ok { ret hash_error }
            let (target_module, target_module_error) = string_index(table, g.modules[constant.module_index].name)
            if target_module_error != ok { ret target_module_error }
            let (target_name, target_name_error) = string_index(table, constant.name)
            if target_name_error != ok { ret target_name_error }
            try binary.byte(output, dependency_value_kind())
            try binary.zeroes(output, 3usize)
            try binary.little_u32(output, target_module)
            try binary.little_u32(output, target_name)
            try binary.little_u64(output, hash)
        }
        at += 1usize
    }
    ret ok
}


fn function_code_end(builder: *nir.Builder, machine: *emit_x64.Buffer, function_offsets: []usize, function_index: usize) -> (usize, err) {
    if function_index >= builder.function_count || function_index >= function_offsets.len { ret (0usize, InvalidArtifact) }
    if function_index + 1usize < builder.function_count {
        if function_index + 1usize >= function_offsets.len { ret (0usize, InvalidArtifact) }
        ret (function_offsets[function_index + 1usize], ok)
    }
    ret (machine.count, ok)
}

// Relocations are appended as code is emitted, so their displacements ascend: the
// first one at or past `start` is a binary search, and a function's relocations are
// the run from there (D305). Every function used to scan all of them, twice.
fn first_relocation_from(relocations: []codegen_x64.Relocation, relocation_count: usize, start: usize) -> usize {
    var low = 0usize
    var high = relocation_count
    while low < high {
        let mid = (low + high) / 2usize
        if relocations[mid].displacement_at < start { low = mid + 1usize } else { high = mid }
    }
    ret low
}

fn relocation_count_for_range(relocations: []codegen_x64.Relocation, relocation_count: usize, start: usize, end: usize) -> (usize, err) {
    if relocation_count > relocations.len { ret (0usize, InvalidArtifact) }
    var count = 0usize
    var at = first_relocation_from(relocations, relocation_count, start)
    while at < relocation_count {
        let offset = relocations[at].displacement_at
        if offset >= end { break }
        if offset >= start {
            if offset + 4usize > end { ret (0usize, InvalidArtifact) }
            count += 1usize
        }
        at += 1usize
    }
    ret (count, ok)
}

fn write_code_hash_input(g: *graph.Graph, builder: *nir.Builder, machine: *emit_x64.Buffer, start: usize, end: usize, relocations: []codegen_x64.Relocation, relocation_count: usize, output: *binary.Buffer) -> err {
    if start > end || end > machine.count { ret InvalidArtifact }
    let (count, count_error) = relocation_count_for_range(relocations, relocation_count, start, end)
    if count_error != ok { ret count_error }
    try binary.little_u32(output, end - start)
    try binary.copy_bytes(output, machine.bytes[start..end])
    try binary.little_u32(output, count)
    var at = first_relocation_from(relocations, relocation_count, start)
    while at < relocation_count {
        let relocation = relocations[at]
        if relocation.displacement_at >= end { break }
        if relocation.displacement_at >= start && relocation.displacement_at < end {
            try binary.little_u32(output, relocation.displacement_at - start)
            if relocation.global {
                if relocation.function_ref >= builder.global_count { ret InvalidArtifact }
                let global = builder.globals[relocation.function_ref]
                if global.module_index >= g.count { ret InvalidArtifact }
                try binary.byte(output, 1usize)
                try canonical_text(output, g.modules[global.module_index].name)
                try canonical_text(output, global.name)
                try binary.little_u32(output, 0usize)
            } else {
                if relocation.function_ref >= builder.function_ref_count { ret InvalidArtifact }
                let reference = builder.function_refs[relocation.function_ref]
                if reference.module_index >= g.count { ret InvalidArtifact }
                try binary.byte(output, 0usize)
                try canonical_text(output, g.modules[reference.module_index].name)
                try canonical_text(output, reference.name)
                try binary.little_u32(output, reference.instance)
            }
        }
        at += 1usize
    }
    ret ok
}

fn write_code(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    try binary.little_u32(output, module_nir_function_count(builder, c, module_index))
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            let function = builder.functions[function_at]
            if function_at >= function_offsets.len { ret InvalidArtifact }
            let start = function_offsets[function_at]
            let (end, end_error) = function_code_end(builder, machine, function_offsets, function_at)
            if end_error != ok || start > end || end > machine.count { ret InvalidArtifact }
            let (count, count_error) = relocation_count_for_range(relocations, relocation_count, start, end)
            if count_error != ok { ret count_error }
            scratch.count = 0usize
            try write_code_hash_input(g, builder, machine, start, end, relocations, relocation_count, scratch)
            let (content_hash, content_hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
            if content_hash_error != ok { ret content_hash_error }
            let (name_index, name_error) = string_index(table, function.name)
            if name_error != ok { ret name_error }
            try binary.little_u32(output, name_index)
            try binary.little_u32(output, function.instance)
            try binary.little_u64(output, content_hash)
            try binary.little_u32(output, end - start)
            try binary.little_u32(output, count)
            try binary.copy_bytes(output, machine.bytes[start..end])
            var relocation_at = first_relocation_from(relocations, relocation_count, start)
            while relocation_at < relocation_count {
                let relocation = relocations[relocation_at]
                if relocation.displacement_at >= end { break }
                if relocation.displacement_at >= start {
                    var target_module_index = 0usize
                    var target_symbol = ""
                    var instance = 0usize
                    var kind = 0usize
                    var library_index = 0usize
                    var symbol_index = 0usize
                    if relocation.global {
                        if relocation.function_ref >= builder.global_count { ret InvalidArtifact }
                        target_module_index = builder.globals[relocation.function_ref].module_index
                        target_symbol = builder.globals[relocation.function_ref].name
                        kind = 1usize
                    } else {
                        if relocation.function_ref >= builder.function_ref_count { ret InvalidArtifact }
                        let reference = builder.function_refs[relocation.function_ref]
                        target_module_index = reference.module_index
                        target_symbol = reference.name
                        instance = reference.instance
                        if reference.library.len != 0usize {
                            kind = 2usize
                            let (stored_library, stored_library_error) = string_index(table, reference.library)
                            if stored_library_error != ok { ret stored_library_error }
                            let (stored_symbol, stored_symbol_error) = string_index(table, reference.symbol)
                            if stored_symbol_error != ok { ret stored_symbol_error }
                            library_index = stored_library
                            symbol_index = stored_symbol
                        }
                    }
                    if target_module_index >= g.count { ret InvalidArtifact }
                    let (target_module, target_module_error) = string_index(table, g.modules[target_module_index].name)
                    if target_module_error != ok { ret target_module_error }
                    let (target_name, target_name_error) = string_index(table, target_symbol)
                    if target_name_error != ok { ret target_name_error }
                    try binary.little_u32(output, relocation.displacement_at - start)
                    try binary.little_u32(output, target_module)
                    try binary.little_u32(output, target_name)
                    try binary.little_u32(output, instance)
                    try binary.little_u32(output, kind)
                    try binary.little_u32(output, library_index)
                    try binary.little_u32(output, symbol_index)
                }
                relocation_at += 1usize
            }
        }
        function_at += 1usize
    }
    ret ok
}

// The module's own `var`s, in declaration order: name, size, alignment, whether an initial
// value was written, and its bits. The linker lays them out from this and nothing else.
// The paths the module's line rows name, interned ahead of the Strings section.
fn collect_line_paths(builder: *nir.Builder, c: *check.Checker, module_index: usize, machine: *emit_x64.Buffer, function_offsets: []usize, lines: []codegen_x64.LineEntry, line_count: usize, table: *StringTable) -> err {
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            if function_at >= function_offsets.len { ret InvalidArtifact }
            let start = function_offsets[function_at]
            let (end, end_error) = function_code_end(builder, machine, function_offsets, function_at)
            if end_error != ok { ret end_error }
            let (first_row, row_total) = codegen_x64.line_rows_of(lines, line_count, start, end)
            var row_at = first_row
            while row_at < first_row + row_total {
                let (path_index, path_error) = intern(table, lines[row_at].path)
                if path_error != ok { ret path_error }
                row_at += 1usize
            }
        }
        function_at += 1usize
    }
    ret ok
}

// The Lines section: per code function, in the Code section's order, a count and then
// the rows -- the offset within the function's code, the line, the path's string index.
fn write_lines(builder: *nir.Builder, c: *check.Checker, module_index: usize, table: *StringTable, machine: *emit_x64.Buffer, function_offsets: []usize, lines: []codegen_x64.LineEntry, line_count: usize, output: *binary.Buffer) -> err {
    try binary.little_u32(output, module_nir_function_count(builder, c, module_index))
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            if function_at >= function_offsets.len { ret InvalidArtifact }
            let start = function_offsets[function_at]
            let (end, end_error) = function_code_end(builder, machine, function_offsets, function_at)
            if end_error != ok { ret end_error }
            let (first_row, row_total) = codegen_x64.line_rows_of(lines, line_count, start, end)
            try binary.little_u32(output, row_total)
            var row_at = first_row
            while row_at < first_row + row_total {
                let entry = lines[row_at]
                let (path_index, path_error) = string_index(table, entry.path)
                if path_error != ok { ret path_error }
                try binary.little_u32(output, entry.offset - start)
                try binary.little_u32(output, entry.line)
                try binary.little_u32(output, path_index)
                row_at += 1usize
            }
        }
        function_at += 1usize
    }
    ret ok
}

// The rows of one code function, by its position in the Code section; an artifact with
// no Lines section, or fewer functions in it, has none.
fn read_code_lines(bytes: []const u8, function_index: usize, out: []LineRow) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (section, found, section_error) = find_section_unchecked(bytes, lines_kind())
    if section_error != ok { ret (0usize, section_error) }
    if !found || section.length < 4usize { ret (0usize, ok) }
    let (function_count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    if function_index >= function_count { ret (0usize, ok) }
    let end = section.offset + section.length
    var cursor = section.offset + 4usize
    var at = 0usize
    while at <= function_index {
        if cursor > end || 4usize > end - cursor { ret (0usize, InvalidArtifact) }
        let (row_count, row_count_error) = binary.read_u32(bytes, cursor)
        if row_count_error != ok { ret (0usize, InvalidArtifact) }
        cursor += 4usize
        if row_count > (end - cursor) / 12usize { ret (0usize, InvalidArtifact) }
        if at == function_index {
            if row_count > out.len { ret (0usize, Capacity) }
            var row_at = 0usize
            while row_at < row_count {
                let (offset, offset_error) = binary.read_u32(bytes, cursor + row_at * 12usize)
                let (line, line_error) = binary.read_u32(bytes, cursor + row_at * 12usize + 4usize)
                let (path_index, path_error) = binary.read_u32(bytes, cursor + row_at * 12usize + 8usize)
                if offset_error != ok || line_error != ok || path_error != ok { ret (0usize, InvalidArtifact) }
                out[row_at] = LineRow { offset: offset, line: line, path_index: path_index }
                row_at += 1usize
            }
            ret (row_count, ok)
        }
        cursor += row_count * 12usize
        at += 1usize
    }
    ret (0usize, ok)
}

// How many rows the artifact holds in all, to size the assembled program's table.
fn artifact_line_row_total(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (section, found, section_error) = find_section_unchecked(bytes, lines_kind())
    if section_error != ok { ret (0usize, section_error) }
    if !found || section.length < 4usize { ret (0usize, ok) }
    let (function_count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    let end = section.offset + section.length
    var cursor = section.offset + 4usize
    var total = 0usize
    var at = 0usize
    while at < function_count {
        if cursor > end || 4usize > end - cursor { ret (0usize, InvalidArtifact) }
        let (row_count, row_count_error) = binary.read_u32(bytes, cursor)
        if row_count_error != ok { ret (0usize, InvalidArtifact) }
        cursor += 4usize + row_count * 12usize
        total += row_count
        at += 1usize
    }
    ret (total, ok)
}

fn write_globals(builder: *nir.Builder, c: *check.Checker, module_index: usize, table: *StringTable, output: *binary.Buffer) -> err {
    var count = 0usize
    let (first, end) = span_of(c, span_globals(), module_index)
    var at = first
    while at < end {
        if builder.globals[at].module_index == module_index { count += 1usize }
        at += 1usize
    }
    try binary.little_u32(output, count)
    at = first
    while at < end {
        let global = builder.globals[at]
        if global.module_index == module_index {
            let (name_index, name_error) = string_index(table, global.name)
            if name_error != ok { ret name_error }
            try binary.little_u32(output, name_index)
            try binary.little_u32(output, global.size)
            try binary.little_u32(output, global.alignment)
            var has_initial = 0usize
            if global.has_initial { has_initial = 1usize }
            try binary.little_u32(output, has_initial)
            try binary.little_u64(output, global.initial)
        }
        at += 1usize
    }
    ret ok
}

fn source_text_hash(text: str, scratch: *binary.Buffer) -> (usize, err) {
    scratch.count = 0usize
    let text_error = binary.text(scratch, text)
    if text_error != ok { ret (0usize, text_error) }
    let (source_hash, source_hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (source_hash, source_hash_error)
}

fn write_debug(g: *graph.Graph, module_index: usize, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    if module_index >= g.count { ret InvalidArtifact }
    let (source_hash, source_hash_error) = source_text_hash(g.modules[module_index].text, scratch)
    if source_hash_error != ok { ret source_hash_error }
    let (path_index, path_error) = string_index(table, g.modules[module_index].path)
    if path_error != ok { ret path_error }
    try binary.little_u32(output, path_index)
    try binary.little_u64(output, source_hash)
    try binary.little_u32(output, 0usize)
    ret binary.little_u32(output, 0usize)
}

// The Interface a module's artifact would carry, as an artifact of its Strings and
// Interface sections alone (D214): every hash in it comes from the checker, so the
// edge rule can be settled against it before anything is lowered.
fn write_interface_artifact(c: *check.Checker, g: *graph.Graph, module_index: usize, target_triple: str, mode: BuildMode, strings: *StringTable, section_values: []Section, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    if module_index >= g.count || target_triple.len == 0usize || section_values.len != 2usize || output.count != 0usize { ret InvalidArtifact }
    var no_builder: nir.Builder = zero
    try reset_strings(strings)
    let (target_index, target_error) = intern(strings, target_triple)
    if target_error != ok { ret target_error }
    try collect_module_strings(c, g, &no_builder, module_index, strings)
    var writer: Writer = zero
    try begin(&writer, output, section_values, target_index, 0usize, mode)
    try begin_section(&writer, strings_kind(), required_flag())
    try write_strings(strings, output)
    try end_section(&writer)
    try begin_section(&writer, interface_kind(), required_flag())
    let interface_error = write_interface(c, g, &no_builder, module_index, strings, scratch, output)
    if interface_error != ok { ret interface_error }
    try end_section(&writer)
    try finish(&writer)
    ret check_layout(output.bytes[0usize..output.count])
}

fn write_module(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, target_triple: str, mode: BuildMode, machine: *emit_x64.Buffer, function_offsets: []usize, relocations: []codegen_x64.Relocation, relocation_count: usize, lines: []codegen_x64.LineEntry, line_count: usize, strings: *StringTable, section_values: []Section, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    if module_index >= g.count || target_triple.len == 0usize || section_values.len != 8usize || output.count != 0usize { ret InvalidArtifact }
    try reset_strings(strings)
    let (target_index, target_error) = intern(strings, target_triple)
    if target_error != ok { ret target_error }
    try collect_module_strings(c, g, builder, module_index, strings)
    try collect_line_paths(builder, c, module_index, machine, function_offsets, lines, line_count, strings)
    var writer: Writer = zero
    try begin(&writer, output, section_values, target_index, 0usize, mode)
    try begin_section(&writer, strings_kind(), required_flag())
    try write_strings(strings, output)
    try end_section(&writer)
    try begin_section(&writer, interface_kind(), required_flag())
    let interface_error = write_interface(c, g, builder, module_index, strings, scratch, output)
    if interface_error != ok { ret interface_error }
    try end_section(&writer)
    try begin_section(&writer, deps_kind(), required_flag())
    try write_dependencies(c, g, builder, module_index, strings, scratch, output)
    try end_section(&writer)
    try begin_section(&writer, code_kind(), required_flag())
    let code_error = write_code(c, g, builder, module_index, strings, machine, function_offsets, relocations, relocation_count, scratch, output)
    if code_error != ok { ret code_error }
    try end_section(&writer)
    try begin_section(&writer, debug_kind(), required_flag())
    try write_debug(g, module_index, strings, scratch, output)
    try end_section(&writer)
    try begin_section(&writer, globals_kind(), required_flag())
    try write_globals(builder, c, module_index, strings, output)
    try end_section(&writer)
    try begin_section(&writer, lines_kind(), required_flag())
    try write_lines(builder, c, module_index, strings, machine, function_offsets, lines, line_count, output)
    try end_section(&writer)
    try begin_section(&writer, imports_kind(), required_flag())
    try write_imports(g, module_index, strings, output)
    try end_section(&writer)
    ret finish(&writer)
}

fn write_imports(g: *graph.Graph, module_index: usize, table: *StringTable, output: *binary.Buffer) -> err {
    let first = g.modules[module_index].first_import
    let count = g.modules[module_index].import_count
    try binary.little_u32(output, count)
    var at = first
    while at < first + count {
        let (name_index, name_error) = string_index(table, g.imports[at].name)
        if name_error != ok { ret name_error }
        let (qualifier_index, qualifier_error) = string_index(table, g.imports[at].qualifier)
        if qualifier_error != ok { ret qualifier_error }
        try binary.little_u32(output, name_index)
        try binary.little_u32(output, qualifier_index)
        at += 1usize
    }
    ret ok
}

// The Imports section read: the count, then each import's name and qualifier string
// indexes. An artifact without the section has no imports.
fn artifact_import_count(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (section, found, section_error) = find_section_unchecked(bytes, imports_kind())
    if section_error != ok { ret (0usize, section_error) }
    if !found { ret (0usize, ok) }
    if section.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || count > (section.length - 4usize) / 8usize { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

fn artifact_import_at(bytes: []const u8, index: usize) -> (usize, usize, err) {
    let (count, count_error) = artifact_import_count(bytes)
    if count_error != ok { ret (0usize, 0usize, count_error) }
    if index >= count { ret (0usize, 0usize, InvalidArtifact) }
    let (section, found, section_error) = find_section_unchecked(bytes, imports_kind())
    if section_error != ok || !found { ret (0usize, 0usize, InvalidArtifact) }
    let (name_index, name_error) = binary.read_u32(bytes, section.offset + 4usize + index * 8usize)
    let (qualifier_index, qualifier_error) = binary.read_u32(bytes, section.offset + 8usize + index * 8usize)
    if name_error != ok || qualifier_error != ok { ret (0usize, 0usize, InvalidArtifact) }
    ret (name_index, qualifier_index, ok)
}

fn begin(writer: *Writer, output: *binary.Buffer, sections: []Section, target_triple_index: usize, flags: usize, mode: BuildMode) -> err {
    if sections.len == 0usize || output.count != 0usize { ret InvalidArtifact }
    writer.output = output
    writer.sections = sections
    writer.count = 0usize
    writer.active = false
    writer.active_start = 0usize
    try binary.byte(output, 78usize)
    try binary.byte(output, 69usize)
    try binary.byte(output, 80usize)
    try binary.byte(output, 77usize)
    try binary.little_u16(output, format_version())
    try binary.little_u16(output, header_size())
    try binary.little_u32(output, target_triple_index)
    try binary.little_u32(output, flags)
    try binary.byte(output, mode_id(mode))
    try binary.zeroes(output, 3usize)
    try binary.little_u32(output, sections.len)
    try binary.little_u32(output, header_size())
    try binary.little_u32(output, 0usize)
    try binary.zeroes(output, sections.len * directory_entry_size())
    ret binary.align(output, 8usize)
}

fn begin_section(writer: *Writer, kind: usize, flags: usize) -> err {
    if writer.active || writer.count == writer.sections.len || kind == 0usize { ret InvalidArtifact }
    if writer.count != 0usize && kind <= writer.sections[writer.count - 1usize].kind { ret InvalidArtifact }
    try binary.align(writer.output, 8usize)
    writer.active = true
    writer.active_start = writer.output.count
    writer.sections[writer.count] = Section { kind: kind, flags: flags, offset: writer.output.count, length: 0usize }
    ret ok
}

fn end_section(writer: *Writer) -> err {
    if !writer.active || writer.count == writer.sections.len { ret InvalidArtifact }
    writer.sections[writer.count].length = writer.output.count - writer.active_start
    writer.count += 1usize
    writer.active = false
    ret ok
}

fn finish(writer: *Writer) -> err {
    if writer.active || writer.count != writer.sections.len { ret InvalidArtifact }
    var at = 0usize
    while at < writer.count {
        let entry = header_size() + at * directory_entry_size()
        try binary.patch_little_u32(writer.output, entry, writer.sections[at].kind)
        try binary.patch_little_u32(writer.output, entry + 4usize, writer.sections[at].flags)
        try binary.patch_little_u64(writer.output, entry + 8usize, writer.sections[at].offset)
        try binary.patch_little_u64(writer.output, entry + 16usize, writer.sections[at].length)
        at += 1usize
    }
    let (checksum, checksum_error) = artifact_hash.crc32c(writer.output.bytes[0usize..writer.output.count], 28usize, 4usize)
    if checksum_error != ok { ret checksum_error }
    ret binary.patch_little_u32(writer.output, 28usize, checksum)
}

fn continuation(value: usize) -> bool {
    ret value >= 128usize && value <= 191usize
}

fn valid_utf8(bytes: []const u8, start: usize, length: usize) -> bool {
    if start > bytes.len || length > bytes.len - start { ret false }
    let end = start + length
    var at = start
    while at < end {
        let first = usize(usize(bytes[at]))
        if first <= 127usize {
            at += 1usize
        } else {
            if first >= 194usize && first <= 223usize {
                if at + 1usize >= end || !continuation(usize(usize(bytes[at + 1usize]))) { ret false }
                at += 2usize
            } else {
                if first >= 224usize && first <= 239usize {
                    if at + 2usize >= end || !continuation(usize(usize(bytes[at + 1usize]))) || !continuation(usize(usize(bytes[at + 2usize]))) { ret false }
                    if first == 224usize && usize(usize(bytes[at + 1usize])) < 160usize { ret false }
                    if first == 237usize && usize(usize(bytes[at + 1usize])) > 159usize { ret false }
                    at += 3usize
                } else {
                    if first < 240usize || first > 244usize || at + 3usize >= end || !continuation(usize(usize(bytes[at + 1usize]))) || !continuation(usize(usize(bytes[at + 2usize]))) || !continuation(usize(usize(bytes[at + 3usize]))) { ret false }
                    if first == 240usize && usize(usize(bytes[at + 1usize])) < 144usize { ret false }
                    if first == 244usize && usize(usize(bytes[at + 1usize])) > 143usize { ret false }
                    at += 4usize
                }
            }
        }
    }
    ret true
}

fn validate_strings(bytes: []const u8, section: Section, target_index: usize) -> err {
    if section.length < 4usize { ret InvalidArtifact }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || count == 0usize || target_index >= count { ret InvalidArtifact }
    if section.length < 4usize + count * 4usize { ret InvalidArtifact }
    var at = section.offset + 4usize + count * 4usize
    var index = 0usize
    while index < count {
        let (offset, offset_error) = binary.read_u32(bytes, section.offset + 4usize + index * 4usize)
        if offset_error != ok || section.offset + offset != at { ret InvalidArtifact }
        let (length, length_error) = binary.read_u32(bytes, at)
        if length_error != ok { ret InvalidArtifact }
        at += 4usize
        let section_end = section.offset + section.length
        if at > section_end || length > section_end - at || !valid_utf8(bytes, at, length) { ret InvalidArtifact }
        if index == 0usize && length != 0usize { ret InvalidArtifact }
        at += length
        index += 1usize
    }
    if at != section.offset + section.length { ret InvalidArtifact }
    ret ok
}

fn find_section_unchecked(bytes: []const u8, kind: usize) -> (Section, bool, err) {
    let empty = Section { kind: 0usize, flags: 0usize, offset: 0usize, length: 0usize }
    let (section_count, count_error) = binary.read_u32(bytes, 20usize)
    let (directory, directory_error) = binary.read_u32(bytes, 24usize)
    if count_error != ok || directory_error != ok || directory > bytes.len || section_count > (bytes.len - directory) / directory_entry_size() { ret (empty, false, InvalidArtifact) }
    var at = 0usize
    while at < section_count {
        let entry = directory + at * directory_entry_size()
        let (entry_kind, kind_error) = binary.read_u32(bytes, entry)
        let (flags, flags_error) = binary.read_u32(bytes, entry + 4usize)
        let (offset, offset_error) = binary.read_u64(bytes, entry + 8usize)
        let (length, length_error) = binary.read_u64(bytes, entry + 16usize)
        if kind_error != ok || flags_error != ok || offset_error != ok || length_error != ok || offset > bytes.len || length > bytes.len - offset { ret (empty, false, InvalidArtifact) }
        if entry_kind == kind { ret (Section { kind: entry_kind, flags: flags, offset: offset, length: length }, true, ok) }
        at += 1usize
    }
    ret (empty, false, ok)
}

// The number of strings, and every string's start once into `starts` (sized to at least the
// count). `string_bounds` walks the table from the front on each call -- O(index) -- so asking
// it per function or per relocation is quadratic over a module; a caller that will touch many
// strings reads their starts once through this and indexes in O(1). `validate` is the caller's.
fn string_count(bytes: []const u8) -> (usize, err) {
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings || strings.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, strings.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

fn read_string_starts(bytes: []const u8, starts: []usize) -> (usize, err) {
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings || strings.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, strings.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    if count > starts.len { ret (0usize, Capacity) }
    var at = 0usize
    while at < count {
        let (start, length, bounds_error) = string_bounds(bytes, at)
        if bounds_error != ok { ret (0usize, bounds_error) }
        starts[at] = start
        at += 1usize
    }
    ret (count, ok)
}

// The byte length of the string at `start`, which `read_string_starts` recorded. The length
// prefix sits four bytes before the start.
fn string_length_at(bytes: []const u8, start: usize) -> (usize, err) {
    if start < 4usize { ret (0usize, InvalidArtifact) }
    let (length, length_error) = binary.read_u32(bytes, start - 4usize)
    ret (length, length_error)
}

fn string_bounds(bytes: []const u8, index: usize) -> (usize, usize, err) {
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings || strings.length < 4usize { ret (0usize, 0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, strings.offset)
    if count_error != ok || index >= count || strings.length < 4usize + count * 4usize { ret (0usize, 0usize, InvalidArtifact) }
    let (offset, offset_error) = binary.read_u32(bytes, strings.offset + 4usize + index * 4usize)
    if offset_error != ok || offset + 4usize > strings.length { ret (0usize, 0usize, InvalidArtifact) }
    let cursor = strings.offset + offset
    let (length, length_error) = binary.read_u32(bytes, cursor)
    if length_error != ok || length > strings.length - offset - 4usize { ret (0usize, 0usize, InvalidArtifact) }
    ret (cursor + 4usize, length, ok)
}

// Every string's start and length, walked once (D319): a link reads strings per
// relocation, and each read walked the table from its first entry.
fn string_table_bounds(a: *mem.Arena, bytes: []const u8) -> ([]usize, []usize, err) {
    var none: [1]usize = zero
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings || strings.length < 4usize { ret (none[0usize..0usize], none[0usize..0usize], InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, strings.offset)
    if count_error != ok { ret (none[0usize..0usize], none[0usize..0usize], InvalidArtifact) }
    let (starts, starts_error) = mem.alloc[usize](a, count + 1usize)
    if starts_error != ok { ret (none[0usize..0usize], none[0usize..0usize], starts_error) }
    let (lengths, lengths_error) = mem.alloc[usize](a, count + 1usize)
    if lengths_error != ok { ret (none[0usize..0usize], none[0usize..0usize], lengths_error) }
    var at = 0usize
    while at < count {
        let (start, length, bounds_error) = string_bounds(bytes, at)
        if bounds_error != ok { ret (none[0usize..0usize], none[0usize..0usize], bounds_error) }
        starts[at] = start
        lengths[at] = length
        at += 1usize
    }
    ret (starts[0usize..count], lengths[0usize..count], ok)
}

fn string_matches(bytes: []const u8, index: usize, expected: str) -> (bool, err) {
    let (start, length, bounds_error) = string_bounds(bytes, index)
    if bounds_error != ok { ret (false, bounds_error) }
    if length != expected.len { ret (false, ok) }
    var at = 0usize
    while at < length {
        if usize(bytes[start + at]) != usize(expected[at]) { ret (false, ok) }
        at += 1usize
    }
    ret (true, ok)
}

fn strings_equal(left: []const u8, left_index: usize, right: []const u8, right_index: usize) -> (bool, err) {
    let (left_start, left_length, left_error) = string_bounds(left, left_index)
    let (right_start, right_length, right_error) = string_bounds(right, right_index)
    if left_error != ok { ret (false, left_error) }
    if right_error != ok { ret (false, right_error) }
    if left_length != right_length { ret (false, ok) }
    var at = 0usize
    while at < left_length {
        if usize(left[left_start + at]) != usize(right[right_start + at]) { ret (false, ok) }
        at += 1usize
    }
    ret (true, ok)
}

fn indexed_error_value(bytes: []const u8, module_index: usize, name_index: usize) -> (usize, err) {
    let (module_start, module_length, module_error) = string_bounds(bytes, module_index)
    if module_error != ok || module_length == 0usize { ret (0usize, InvalidArtifact) }
    let (name_start, name_length, name_error) = string_bounds(bytes, name_index)
    if name_error != ok || name_length == 0usize { ret (0usize, InvalidArtifact) }
    var hash = 2166136261usize
    var at = 0usize
    while at < module_length {
        let (next, step_error) = artifact_hash.fnv1a32_step(hash, usize(bytes[module_start + at]))
        if step_error != ok { ret (0usize, step_error) }
        hash = next
        at += 1usize
    }
    let (with_separator, separator_error) = artifact_hash.fnv1a32_step(hash, 46usize)
    if separator_error != ok { ret (0usize, separator_error) }
    hash = with_separator
    at = 0usize
    while at < name_length {
        let (next, step_error) = artifact_hash.fnv1a32_step(hash, usize(bytes[name_start + at]))
        if step_error != ok { ret (0usize, step_error) }
        hash = next
        at += 1usize
    }
    ret (hash, ok)
}

fn interface_errors_unchecked(bytes: []const u8) -> (InterfaceErrors, err) {
    let empty = InterfaceErrors { entries: 0usize, count: 0usize, module_index: 0usize }
    let (interface, found_interface, section_error) = find_section_unchecked(bytes, interface_kind())
    if section_error != ok || !found_interface || interface.length < 20usize { ret (empty, InvalidArtifact) }
    let (declaration_count, count_error) = binary.read_u32(bytes, interface.offset + 8usize)
    let (module_index, module_error) = binary.read_u32(bytes, interface.offset + 12usize)
    if count_error != ok || module_error != ok { ret (empty, InvalidArtifact) }
    let (module_start, module_length, module_bounds_error) = string_bounds(bytes, module_index)
    if module_bounds_error != ok || module_length == 0usize || module_start >= bytes.len { ret (empty, InvalidArtifact) }
    let end = interface.offset + interface.length
    var cursor = interface.offset + 16usize
    var declared_errors = 0usize
    var declaration_at = 0usize
    while declaration_at < declaration_count {
        if cursor > end || 8usize > end - cursor { ret (empty, InvalidArtifact) }
        let kind = usize(bytes[cursor])
        if kind < declaration_function_kind() || kind > declaration_error_kind() || usize(bytes[cursor + 1usize]) > 255usize || usize(bytes[cursor + 2usize]) != 0usize || usize(bytes[cursor + 3usize]) != 0usize { ret (empty, InvalidArtifact) }
        let (length, length_error) = binary.read_u32(bytes, cursor + 4usize)
        if length_error != ok || length < 20usize { ret (empty, InvalidArtifact) }
        let payload = cursor + 8usize
        if payload > end || length > end - payload { ret (empty, InvalidArtifact) }
        let (name_index, name_error) = binary.read_u32(bytes, payload)
        let (name_start, name_length, name_bounds_error) = string_bounds(bytes, name_index)
        if name_error != ok || name_bounds_error != ok || name_length == 0usize || name_start >= bytes.len { ret (empty, InvalidArtifact) }
        if kind == declaration_error_kind() {
            if length != 24usize { ret (empty, InvalidArtifact) }
            declared_errors += 1usize
        }
        cursor = payload + length
        declaration_at += 1usize
    }
    if cursor > end || 4usize > end - cursor { ret (empty, InvalidArtifact) }
    let (error_count, error_count_error) = binary.read_u32(bytes, cursor)
    if error_count_error != ok || error_count != declared_errors { ret (empty, InvalidArtifact) }
    let entries = cursor + 4usize
    if entries > end || error_count > (end - entries) / 8usize || entries + error_count * 8usize != end { ret (empty, InvalidArtifact) }
    ret (InterfaceErrors { entries: entries, count: error_count, module_index: module_index }, ok)
}

fn interface_errors(bytes: []const u8) -> (InterfaceErrors, err) {
    let empty = InterfaceErrors { entries: 0usize, count: 0usize, module_index: 0usize }
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (empty, validation_error) }
    let (table, table_error) = interface_errors_unchecked(bytes)
    ret (table, table_error)
}

// Every error in one validated pass, into `out` (sized to at least the count). The per-index
// reader validates the whole artifact and re-walks the interface on each call, so reading an
// error table entry by entry is quadratic with a CRC on every step; this is one validate and
// one walk.
fn read_error_table(bytes: []const u8, out: []ErrorValue) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (table, table_error) = interface_errors_unchecked(bytes)
    if table_error != ok { ret (0usize, table_error) }
    if table.count > out.len { ret (0usize, Capacity) }
    var index = 0usize
    while index < table.count {
        let entry = table.entries + index * 8usize
        let (value, value_error) = binary.read_u32(bytes, entry)
        let (name_index, name_error) = binary.read_u32(bytes, entry + 4usize)
        if value_error != ok || name_error != ok || value == 0usize { ret (0usize, InvalidArtifact) }
        let (expected, expected_error) = indexed_error_value(bytes, table.module_index, name_index)
        if expected_error != ok || expected != value { ret (0usize, InvalidArtifact) }
        out[index] = ErrorValue { value: value, module_index: table.module_index, name_index: name_index }
        index += 1usize
    }
    ret (table.count, ok)
}

fn artifact_error_count(bytes: []const u8) -> (usize, err) {
    let (table, table_error) = interface_errors(bytes)
    if table_error != ok { ret (0usize, table_error) }
    ret (table.count, ok)
}

fn artifact_error_at(bytes: []const u8, index: usize) -> (ErrorValue, err) {
    let empty = ErrorValue { value: 0usize, module_index: 0usize, name_index: 0usize }
    let (table, table_error) = interface_errors(bytes)
    if table_error != ok || index >= table.count { ret (empty, InvalidArtifact) }
    let entry = table.entries + index * 8usize
    let (value, value_error) = binary.read_u32(bytes, entry)
    let (name_index, name_error) = binary.read_u32(bytes, entry + 4usize)
    if value_error != ok || name_error != ok || value == 0usize { ret (empty, InvalidArtifact) }
    let (expected, expected_error) = indexed_error_value(bytes, table.module_index, name_index)
    if expected_error != ok || expected != value { ret (empty, InvalidArtifact) }
    ret (ErrorValue { value: value, module_index: table.module_index, name_index: name_index }, ok)
}

// A code relocation: displacement, target module, target name, instance, and the kind --
// 0 a function, 1 a module-scope `var`.
// A relocation record: displacement, target module, name, instance, kind, and since
// format 5 (D319) the library and symbol an `@import` binds -- 0 and 0 for a
// reference to a function or a `var`. A kind of 2 says import.
fn relocation_record_size() -> usize { ret 28usize }

fn code_function_at_unchecked(bytes: []const u8, query: usize) -> (CodeFunction, usize, err) {
    let empty = CodeFunction { name_index: 0usize, instance: 0usize, content_hash: 0usize, code_start: 0usize, code_length: 0usize, relocations: 0usize, relocation_count: 0usize }
    let (code, found_code, section_error) = find_section_unchecked(bytes, code_kind())
    if section_error != ok || !found_code || code.length < 4usize { ret (empty, 0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, code.offset)
    if count_error != ok || query >= count { ret (empty, count, InvalidArtifact) }
    let end = code.offset + code.length
    var cursor = code.offset + 4usize
    var at = 0usize
    while at < count {
        if cursor > end || 24usize > end - cursor { ret (empty, count, InvalidArtifact) }
        let (name_index, name_error) = binary.read_u32(bytes, cursor)
        let (instance, instance_error) = binary.read_u32(bytes, cursor + 4usize)
        let (content_hash, hash_error) = binary.read_u64(bytes, cursor + 8usize)
        let (code_length, length_error) = binary.read_u32(bytes, cursor + 16usize)
        let (relocation_count, relocation_count_error) = binary.read_u32(bytes, cursor + 20usize)
        if name_error != ok || instance_error != ok || hash_error != ok || length_error != ok || relocation_count_error != ok { ret (empty, count, InvalidArtifact) }
        let code_start = cursor + 24usize
        if code_start > end || code_length > end - code_start { ret (empty, count, InvalidArtifact) }
        let relocations = code_start + code_length
        if relocations > end || relocation_count > (end - relocations) / relocation_record_size() { ret (empty, count, InvalidArtifact) }
        var relocation_at = 0usize
        while relocation_at < relocation_count {
            let relocation = relocations + relocation_at * relocation_record_size()
            let (displacement, displacement_error) = binary.read_u32(bytes, relocation)
            let (target_module, target_module_error) = binary.read_u32(bytes, relocation + 4usize)
            let (target_name, target_name_error) = binary.read_u32(bytes, relocation + 8usize)
            let (target_instance, target_instance_error) = binary.read_u32(bytes, relocation + 12usize)
            let (target_kind, target_kind_error) = binary.read_u32(bytes, relocation + 16usize)
            if displacement_error != ok || target_module_error != ok || target_name_error != ok || target_instance_error != ok || target_kind_error != ok || target_kind > 2usize || displacement > code_length || 4usize > code_length - displacement { ret (empty, count, InvalidArtifact) }
            let (module_start, module_length, module_bounds_error) = string_bounds(bytes, target_module)
            let (target_start, target_length, target_bounds_error) = string_bounds(bytes, target_name)
            if module_bounds_error != ok || target_bounds_error != ok || module_length == 0usize || target_length == 0usize || module_start >= bytes.len || target_start >= bytes.len { ret (empty, count, InvalidArtifact) }
            relocation_at += 1usize
        }
        let next = relocations + relocation_count * relocation_record_size()
        if at == query {
            ret (CodeFunction { name_index: name_index, instance: instance, content_hash: content_hash, code_start: code_start, code_length: code_length, relocations: relocations, relocation_count: relocation_count }, count, ok)
        }
        cursor = next
        at += 1usize
    }
    ret (empty, count, InvalidArtifact)
}

// Every code function in one forward pass, into `out` (sized to at least the count). The
// per-index reader re-parses from function 0 each call, which is O(n^2) over a whole module;
// the linker reads every function anyway, so it reads them once through this. `validate` is
// the caller's to have run.
fn read_code_functions(bytes: []const u8, out: []CodeFunction) -> (usize, err) {
    let (code, found_code, section_error) = find_section_unchecked(bytes, code_kind())
    if section_error != ok || !found_code || code.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, code.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    if count > out.len { ret (0usize, Capacity) }
    let end = code.offset + code.length
    var cursor = code.offset + 4usize
    var at = 0usize
    while at < count {
        if cursor > end || 24usize > end - cursor { ret (0usize, InvalidArtifact) }
        let (name_index, name_error) = binary.read_u32(bytes, cursor)
        let (instance, instance_error) = binary.read_u32(bytes, cursor + 4usize)
        let (content_hash, hash_error) = binary.read_u64(bytes, cursor + 8usize)
        let (code_length, length_error) = binary.read_u32(bytes, cursor + 16usize)
        let (relocation_count, relocation_count_error) = binary.read_u32(bytes, cursor + 20usize)
        if name_error != ok || instance_error != ok || hash_error != ok || length_error != ok || relocation_count_error != ok { ret (0usize, InvalidArtifact) }
        // The name's own bytes are validated where the name is read; walking the string table to
        // it here (O(index)) once per function made counting and reading a module quadratic.
        let code_start = cursor + 24usize
        if code_start > end || code_length > end - code_start { ret (0usize, InvalidArtifact) }
        let relocations = code_start + code_length
        if relocations > end || relocation_count > (end - relocations) / relocation_record_size() { ret (0usize, InvalidArtifact) }
        out[at] = CodeFunction { name_index: name_index, instance: instance, content_hash: content_hash, code_start: code_start, code_length: code_length, relocations: relocations, relocation_count: relocation_count }
        cursor = relocations + relocation_count * relocation_record_size()
        at += 1usize
    }
    if cursor != end { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

fn artifact_code_count(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (code, found_code, section_error) = find_section_unchecked(bytes, code_kind())
    if section_error != ok || !found_code || code.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, code.offset)
    if count_error != ok { ret (0usize, InvalidArtifact) }
    if count == 0usize {
        if code.length != 4usize { ret (0usize, InvalidArtifact) }
        ret (0usize, ok)
    }
    let (last, parsed_count, last_error) = code_function_at_unchecked(bytes, count - 1usize)
    if last_error != ok || parsed_count != count { ret (0usize, InvalidArtifact) }
    let end = last.relocations + last.relocation_count * relocation_record_size()
    if end != code.offset + code.length { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

fn artifact_code_function_at(bytes: []const u8, index: usize) -> (CodeFunction, err) {
    let empty = CodeFunction { name_index: 0usize, instance: 0usize, content_hash: 0usize, code_start: 0usize, code_length: 0usize, relocations: 0usize, relocation_count: 0usize }
    let (count, count_error) = artifact_code_count(bytes)
    if count_error != ok || index >= count { ret (empty, InvalidArtifact) }
    let (function, parsed_count, function_error) = code_function_at_unchecked(bytes, index)
    if function_error != ok || parsed_count != count { ret (empty, InvalidArtifact) }
    ret (function, ok)
}

fn artifact_code_relocation_at(bytes: []const u8, function: CodeFunction, index: usize) -> (CodeRelocation, err) {
    var empty: CodeRelocation = zero
    if index >= function.relocation_count { ret (empty, InvalidArtifact) }
    let relocation = function.relocations + index * relocation_record_size()
    if relocation > bytes.len || relocation_record_size() > bytes.len - relocation { ret (empty, InvalidArtifact) }
    let (displacement, displacement_error) = binary.read_u32(bytes, relocation)
    let (module_index, module_error) = binary.read_u32(bytes, relocation + 4usize)
    let (name_index, name_error) = binary.read_u32(bytes, relocation + 8usize)
    let (instance, instance_error) = binary.read_u32(bytes, relocation + 12usize)
    let (kind, kind_error) = binary.read_u32(bytes, relocation + 16usize)
    let (library_index, library_error) = binary.read_u32(bytes, relocation + 20usize)
    let (symbol_index, symbol_error) = binary.read_u32(bytes, relocation + 24usize)
    if displacement_error != ok || module_error != ok || name_error != ok || instance_error != ok || kind_error != ok || library_error != ok || symbol_error != ok || kind > 2usize || displacement > function.code_length || 4usize > function.code_length - displacement { ret (empty, InvalidArtifact) }
    let (module_start, module_length, module_bounds_error) = string_bounds(bytes, module_index)
    let (name_start, name_length, name_bounds_error) = string_bounds(bytes, name_index)
    if module_bounds_error != ok || name_bounds_error != ok || module_length == 0usize || name_length == 0usize || module_start >= bytes.len || name_start >= bytes.len { ret (empty, InvalidArtifact) }
    if kind == 2usize {
        let (library_start, library_length, library_bounds_error) = string_bounds(bytes, library_index)
        let (symbol_start, symbol_length, symbol_bounds_error) = string_bounds(bytes, symbol_index)
        if library_bounds_error != ok || symbol_bounds_error != ok || library_length == 0usize || symbol_length == 0usize { ret (empty, InvalidArtifact) }
    }
    var record: CodeRelocation = zero
    record.displacement_at = displacement
    record.module_index = module_index
    record.name_index = name_index
    record.global = kind == 1usize
    record.instance = instance
    record.imported = kind == 2usize
    record.library_index = library_index
    record.symbol_index = symbol_index
    ret (record, ok)
}

// The module's `var`s, from the globals section: how many, and each by index. An artifact
// written before the section existed has no section and no globals.
fn artifact_global_count(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (section, found, section_error) = find_section_unchecked(bytes, globals_kind())
    if section_error != ok { ret (0usize, section_error) }
    if !found { ret (0usize, ok) }
    if section.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || count > (section.length - 4usize) / global_record_size() { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

fn global_record_size() -> usize { ret 24usize }

fn artifact_global_at(bytes: []const u8, index: usize) -> (GlobalRecord, err) {
    let empty = GlobalRecord { name_index: 0usize, size: 0usize, alignment: 0usize, has_initial: false, initial: 0usize }
    let (count, count_error) = artifact_global_count(bytes)
    if count_error != ok { ret (empty, count_error) }
    if index >= count { ret (empty, InvalidArtifact) }
    let (section, found, section_error) = find_section_unchecked(bytes, globals_kind())
    if section_error != ok || !found { ret (empty, InvalidArtifact) }
    let record = section.offset + 4usize + index * global_record_size()
    let (name_index, name_error) = binary.read_u32(bytes, record)
    let (size, size_error) = binary.read_u32(bytes, record + 4usize)
    let (alignment, alignment_error) = binary.read_u32(bytes, record + 8usize)
    let (has_initial, has_initial_error) = binary.read_u32(bytes, record + 12usize)
    let (initial, initial_error) = binary.read_u64(bytes, record + 16usize)
    if name_error != ok || size_error != ok || alignment_error != ok || has_initial_error != ok || initial_error != ok || has_initial > 1usize { ret (empty, InvalidArtifact) }
    let (name_start, name_length, name_bounds_error) = string_bounds(bytes, name_index)
    if name_bounds_error != ok || name_length == 0usize || name_start >= bytes.len { ret (empty, InvalidArtifact) }
    ret (GlobalRecord { name_index: name_index, size: size, alignment: alignment, has_initial: has_initial == 1usize, initial: initial }, ok)
}

fn artifact_code_hash_input_size(bytes: []const u8, function: CodeFunction) -> (usize, err) {
    if function.code_start > bytes.len || function.code_length > bytes.len - function.code_start { ret (0usize, InvalidArtifact) }
    var size = 8usize + function.code_length
    var relocation_at = 0usize
    while relocation_at < function.relocation_count {
        let (relocation, relocation_error) = artifact_code_relocation_at(bytes, function, relocation_at)
        if relocation_error != ok { ret (0usize, relocation_error) }
        let (module_start, module_length, module_error) = string_bounds(bytes, relocation.module_index)
        let (name_start, name_length, name_error) = string_bounds(bytes, relocation.name_index)
        if module_error != ok || name_error != ok || module_start >= bytes.len || name_start >= bytes.len { ret (0usize, InvalidArtifact) }
        size += 17usize + module_length + name_length
        relocation_at += 1usize
    }
    ret (size, ok)
}

fn write_indexed_canonical_text(bytes: []const u8, index: usize, output: *binary.Buffer) -> err {
    let (start, length, bounds_error) = string_bounds(bytes, index)
    if bounds_error != ok { ret bounds_error }
    try binary.little_u32(output, length)
    ret binary.copy(output, bytes[start..start + length])
}

fn artifact_code_content_hash(bytes: []const u8, function: CodeFunction, scratch: *binary.Buffer) -> (usize, err) {
    let (required, required_error) = artifact_code_hash_input_size(bytes, function)
    if required_error != ok { ret (0usize, required_error) }
    if required > scratch.bytes.len { ret (0usize, Capacity) }
    scratch.count = 0usize
    let length_write_error = binary.little_u32(scratch, function.code_length)
    if length_write_error != ok { ret (0usize, length_write_error) }
    let code_write_error = binary.copy(scratch, bytes[function.code_start..function.code_start + function.code_length])
    if code_write_error != ok { ret (0usize, code_write_error) }
    let count_write_error = binary.little_u32(scratch, function.relocation_count)
    if count_write_error != ok { ret (0usize, count_write_error) }
    var relocation_at = 0usize
    while relocation_at < function.relocation_count {
        let (relocation, relocation_error) = artifact_code_relocation_at(bytes, function, relocation_at)
        if relocation_error != ok { ret (0usize, relocation_error) }
        let displacement_error = binary.little_u32(scratch, relocation.displacement_at)
        if displacement_error != ok { ret (0usize, displacement_error) }
        var kind = 0usize
        if relocation.global { kind = 1usize }
        let kind_error = binary.byte(scratch, kind)
        if kind_error != ok { ret (0usize, kind_error) }
        let module_write_error = write_indexed_canonical_text(bytes, relocation.module_index, scratch)
        if module_write_error != ok { ret (0usize, module_write_error) }
        let name_write_error = write_indexed_canonical_text(bytes, relocation.name_index, scratch)
        if name_write_error != ok { ret (0usize, name_write_error) }
        let instance_write_error = binary.little_u32(scratch, relocation.instance)
        if instance_write_error != ok { ret (0usize, instance_write_error) }
        relocation_at += 1usize
    }
    if scratch.count != required { ret (0usize, InvalidArtifact) }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

fn interface_module_index(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (interface, found_interface, section_error) = find_section_unchecked(bytes, interface_kind())
    if section_error != ok || !found_interface || interface.length < 16usize { ret (0usize, InvalidArtifact) }
    let (module_index, module_error) = binary.read_u32(bytes, interface.offset + 12usize)
    if module_error != ok { ret (0usize, InvalidArtifact) }
    let (module_start, module_length, bounds_error) = string_bounds(bytes, module_index)
    if bounds_error != ok || module_length == 0usize || module_start >= bytes.len { ret (0usize, InvalidArtifact) }
    ret (module_index, ok)
}

fn artifact_target_index(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (target_index, target_error) = binary.read_u32(bytes, 8usize)
    if target_error != ok { ret (0usize, InvalidArtifact) }
    let (target_start, target_length, bounds_error) = string_bounds(bytes, target_index)
    if bounds_error != ok || target_length == 0usize || target_start >= bytes.len { ret (0usize, InvalidArtifact) }
    ret (target_index, ok)
}

fn find_declaration(bytes: []const u8, name: str) -> (Declaration, bool, err) {
    let empty = Declaration { kind: 0usize, flags: 0usize, name_index: 0usize, signature_hash: 0usize, body_hash: 0usize }
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (empty, false, validation_error) }
    let (interface, found_interface, section_error) = find_section_unchecked(bytes, interface_kind())
    if section_error != ok || !found_interface || interface.length < 16usize { ret (empty, false, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, interface.offset + 8usize)
    if count_error != ok { ret (empty, false, InvalidArtifact) }
    let end = interface.offset + interface.length
    var cursor = interface.offset + 16usize
    var at = 0usize
    while at < count {
        if cursor > end || 8usize > end - cursor { ret (empty, false, InvalidArtifact) }
        let kind = usize(bytes[cursor])
        let flags = usize(bytes[cursor + 1usize])
        if kind > 255usize || flags > 255usize || usize(bytes[cursor + 2usize]) != 0usize || usize(bytes[cursor + 3usize]) != 0usize { ret (empty, false, InvalidArtifact) }
        let (length, length_error) = binary.read_u32(bytes, cursor + 4usize)
        if length_error != ok || length < 20usize { ret (empty, false, InvalidArtifact) }
        let payload = cursor + 8usize
        if payload > end || length > end - payload { ret (empty, false, InvalidArtifact) }
        let (name_index, name_error) = binary.read_u32(bytes, payload)
        let (signature, signature_error) = binary.read_u64(bytes, payload + 4usize)
        let (body, body_error) = binary.read_u64(bytes, payload + 12usize)
        if name_error != ok || signature_error != ok || body_error != ok { ret (empty, false, InvalidArtifact) }
        let (matches, match_error) = string_matches(bytes, name_index, name)
        if match_error != ok { ret (empty, false, match_error) }
        if matches { ret (Declaration { kind: kind, flags: flags, name_index: name_index, signature_hash: signature, body_hash: body }, true, ok) }
        cursor = payload + length
        at += 1usize
    }
    ret (empty, false, ok)
}

fn dependency_at(bytes: []const u8, index: usize) -> (Dependency, err) {
    let empty = Dependency { kind: 0usize, module_index: 0usize, name_index: 0usize, hash: 0usize }
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (empty, validation_error) }
    let (deps, found_deps, section_error) = find_section_unchecked(bytes, deps_kind())
    if section_error != ok || !found_deps || deps.length < 4usize { ret (empty, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, deps.offset)
    if count_error != ok || index >= count || count > (deps.length - 4usize) / 20usize { ret (empty, InvalidArtifact) }
    let offset = deps.offset + 4usize + index * 20usize
    if offset + 20usize > deps.offset + deps.length { ret (empty, InvalidArtifact) }
    let kind = usize(bytes[offset])
    if kind > 255usize || usize(bytes[offset + 1usize]) != 0usize || usize(bytes[offset + 2usize]) != 0usize || usize(bytes[offset + 3usize]) != 0usize { ret (empty, InvalidArtifact) }
    let (module_index, module_error) = binary.read_u32(bytes, offset + 4usize)
    let (name_index, name_error) = binary.read_u32(bytes, offset + 8usize)
    let (hash, hash_error) = binary.read_u64(bytes, offset + 12usize)
    if module_error != ok || name_error != ok || hash_error != ok { ret (empty, InvalidArtifact) }
    let (module_start, module_length, module_bounds_error) = string_bounds(bytes, module_index)
    let (name_start, name_length, name_bounds_error) = string_bounds(bytes, name_index)
    if module_bounds_error != ok || name_bounds_error != ok || module_length == 0usize || name_length == 0usize { ret (empty, InvalidArtifact) }
    ret (Dependency { kind: kind, module_index: module_index, name_index: name_index, hash: hash }, ok)
}

// The source hash the Debug section carries: the incremental driver's first test (D205).
// The header's build mode: 0 debug, 1 release (D211).
fn artifact_mode(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    if bytes.len < 17usize { ret (0usize, InvalidArtifact) }
    ret (usize(bytes[16usize]), ok)
}

fn artifact_source_hash(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (debug, found_debug, section_error) = find_section_unchecked(bytes, debug_kind())
    if section_error != ok || !found_debug || debug.length < 20usize { ret (0usize, InvalidArtifact) }
    let (hash, hash_error) = binary.read_u64(bytes, debug.offset + 4usize)
    if hash_error != ok { ret (0usize, InvalidArtifact) }
    ret (hash, ok)
}

fn artifact_dependency_count(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (deps, found_deps, section_error) = find_section_unchecked(bytes, deps_kind())
    if section_error != ok || !found_deps || deps.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, deps.offset)
    if count_error != ok || count > (deps.length - 4usize) / 20usize { ret (0usize, InvalidArtifact) }
    ret (count, ok)
}

// The Interface's declarations in order (D320): the count, the first record's cursor
// and the section's end, then each record from its cursor. Settle indexes a fresh
// interface with them once, where it scanned the declarations once per edge.
fn interface_declarations(bytes: []const u8) -> (usize, usize, usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, 0usize, 0usize, validation_error) }
    let (interface, found_interface, section_error) = find_section_unchecked(bytes, interface_kind())
    if section_error != ok || !found_interface || interface.length < 16usize { ret (0usize, 0usize, 0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, interface.offset + 8usize)
    if count_error != ok { ret (0usize, 0usize, 0usize, InvalidArtifact) }
    ret (count, interface.offset + 16usize, interface.offset + interface.length, ok)
}

fn declaration_from(bytes: []const u8, cursor: usize, end: usize) -> (Declaration, usize, err) {
    let empty = Declaration { kind: 0usize, flags: 0usize, name_index: 0usize, signature_hash: 0usize, body_hash: 0usize }
    if cursor > end || end > bytes.len || 8usize > end - cursor { ret (empty, 0usize, InvalidArtifact) }
    let kind = usize(bytes[cursor])
    let flags = usize(bytes[cursor + 1usize])
    let (length, length_error) = binary.read_u32(bytes, cursor + 4usize)
    if length_error != ok || length < 20usize { ret (empty, 0usize, InvalidArtifact) }
    let payload = cursor + 8usize
    if payload > end || length > end - payload { ret (empty, 0usize, InvalidArtifact) }
    let (name_index, name_error) = binary.read_u32(bytes, payload)
    let (signature, signature_error) = binary.read_u64(bytes, payload + 4usize)
    let (body, body_error) = binary.read_u64(bytes, payload + 12usize)
    if name_error != ok || signature_error != ok || body_error != ok { ret (empty, 0usize, InvalidArtifact) }
    ret (Declaration { kind: kind, flags: flags, name_index: name_index, signature_hash: signature, body_hash: body }, payload + length, ok)
}

fn find_declaration_indexed(bytes: []const u8, query: []const u8, query_name_index: usize) -> (Declaration, bool, err) {
    let empty = Declaration { kind: 0usize, flags: 0usize, name_index: 0usize, signature_hash: 0usize, body_hash: 0usize }
    let (count, first, end, open_error) = interface_declarations(bytes)
    if open_error != ok { ret (empty, false, open_error) }
    var cursor = first
    var at = 0usize
    while at < count {
        let (declaration, next, read_error) = declaration_from(bytes, cursor, end)
        if read_error != ok { ret (empty, false, read_error) }
        let (matches, match_error) = strings_equal(bytes, declaration.name_index, query, query_name_index)
        if match_error != ok { ret (empty, false, match_error) }
        if matches { ret (declaration, true, ok) }
        cursor = next
        at += 1usize
    }
    ret (empty, false, ok)
}

// Whether an edge still holds against the declaration it names, or against its absence.
fn dependency_holds(dependency: Dependency, declaration: Declaration, found_declaration: bool) -> (bool, err) {
    if dependency.kind == dependency_lookup_kind() && dependency.hash == 0usize { ret (!found_declaration, ok) }
    if !found_declaration { ret (false, ok) }
    if dependency.kind == dependency_signature_kind() { ret (declaration.signature_hash == dependency.hash, ok) }
    if dependency.kind == dependency_value_kind() || dependency.kind == dependency_body_kind() { ret (declaration.body_hash == dependency.hash, ok) }
    if dependency.kind == dependency_lookup_kind() { ret (declaration.signature_hash == dependency.hash, ok) }
    ret (false, InvalidArtifact)
}

fn dependency_targets_module(dependent: []const u8, dependency_index: usize, target_artifact: []const u8) -> (bool, err) {
    let (dependency, dependency_error) = dependency_at(dependent, dependency_index)
    if dependency_error != ok { ret (false, dependency_error) }
    let (target_module_index, target_module_error) = interface_module_index(target_artifact)
    if target_module_error != ok { ret (false, target_module_error) }
    let (same_module, module_error) = strings_equal(dependent, dependency.module_index, target_artifact, target_module_index)
    ret (same_module, module_error)
}

fn dependency_matches(dependent: []const u8, dependency_index: usize, target_artifact: []const u8) -> (bool, err) {
    let (dependency, dependency_error) = dependency_at(dependent, dependency_index)
    if dependency_error != ok { ret (false, dependency_error) }
    let (target_module_index, target_module_error) = interface_module_index(target_artifact)
    if target_module_error != ok { ret (false, target_module_error) }
    let (same_module, module_error) = strings_equal(dependent, dependency.module_index, target_artifact, target_module_index)
    if module_error != ok { ret (false, module_error) }
    if !same_module { ret (false, ok) }
    let (declaration, found_declaration, declaration_error) = find_declaration_indexed(target_artifact, dependent, dependency.name_index)
    if declaration_error != ok { ret (false, declaration_error) }
    let (holds, holds_error) = dependency_holds(dependency, declaration, found_declaration)
    ret (holds, holds_error)
}

// The whole check: the layout, and the checksum over every byte. Once per artifact,
// where it is loaded or written; the readers check the layout alone (D213), since a
// checksum per read made an edge walk over the compiler's own artifacts take minutes.
// The whole artifact, once, when it is loaded (D213): the layout, the string table's
// encoding, the error table and the checksum. The readers check the layout alone --
// header and directory, a dozen reads -- since the strings and the checksum were
// checked here (D320): every reader validated every string's UTF-8 again, and the
// link's duplicate-module check made a hundred thousand such reads of a
// five-hundred-module program.
fn validate(bytes: []const u8) -> err {
    try check_layout(bytes)
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings { ret InvalidArtifact }
    let (target_index, target_error) = binary.read_u32(bytes, 8usize)
    if target_error != ok { ret InvalidArtifact }
    let strings_error = validate_strings(bytes, strings, target_index)
    if strings_error != ok { ret strings_error }
    let (errors, interface_error) = interface_errors_unchecked(bytes)
    if interface_error != ok || errors.entries > bytes.len { ret InvalidArtifact }
    let (stored_checksum, checksum_read_error) = binary.read_u32(bytes, 28usize)
    if checksum_read_error != ok { ret InvalidArtifact }
    let (checksum, checksum_error) = artifact_hash.crc32c(bytes, 28usize, 4usize)
    if checksum_error != ok || checksum != stored_checksum { ret InvalidArtifact }
    ret ok
}

fn check_layout(bytes: []const u8) -> err {
    if bytes.len < header_size() || usize(bytes[0usize]) != 78usize || usize(bytes[1usize]) != 69usize || usize(bytes[2usize]) != 80usize || usize(bytes[3usize]) != 77usize { ret InvalidArtifact }
    let (version, version_error) = binary.read_u16(bytes, 4usize)
    if version_error != ok || version != format_version() { ret UnsupportedVersion }
    let (size, size_error) = binary.read_u16(bytes, 6usize)
    if size_error != ok || size != header_size() { ret InvalidArtifact }
    let (target_index, target_error) = binary.read_u32(bytes, 8usize)
    let (section_count, count_error) = binary.read_u32(bytes, 20usize)
    let (directory, directory_error) = binary.read_u32(bytes, 24usize)
    let (stored_checksum, checksum_read_error) = binary.read_u32(bytes, 28usize)
    if target_error != ok || count_error != ok || directory_error != ok || checksum_read_error != ok || section_count == 0usize { ret InvalidArtifact }
    if directory < header_size() || directory > bytes.len || section_count > (bytes.len - directory) / directory_entry_size() { ret InvalidArtifact }
    var prior_kind = 0usize
    var prior_end = directory + section_count * directory_entry_size()
    var strings = Section { kind: 0usize, flags: 0usize, offset: 0usize, length: 0usize }
    var found_strings = false
    var at = 0usize
    while at < section_count {
        let entry = directory + at * directory_entry_size()
        let (kind, kind_error) = binary.read_u32(bytes, entry)
        let (flags, flags_error) = binary.read_u32(bytes, entry + 4usize)
        let (offset, offset_error) = binary.read_u64(bytes, entry + 8usize)
        let (length, length_error) = binary.read_u64(bytes, entry + 16usize)
        if kind_error != ok || flags_error != ok || offset_error != ok || length_error != ok || kind == 0usize || kind <= prior_kind { ret InvalidArtifact }
        if !known_kind(kind) && flags % 2usize == 1usize { ret InvalidArtifact }
        if offset % 8usize != 0usize || offset < prior_end || offset > bytes.len || length > bytes.len - offset { ret InvalidArtifact }
        prior_kind = kind
        prior_end = offset + length
        if kind == strings_kind() {
            strings = Section { kind: kind, flags: flags, offset: offset, length: length }
            found_strings = true
        }
        at += 1usize
    }
    if !found_strings { ret InvalidArtifact }
    // The string table's count is what the readers index by; its bytes were checked
    // by `validate`.
    if strings.length < 4usize { ret InvalidArtifact }
    let (string_total, string_total_error) = binary.read_u32(bytes, strings.offset)
    if string_total_error != ok || string_total == 0usize || target_index >= string_total || strings.length < 4usize + string_total * 4usize { ret InvalidArtifact }
    ret ok
}

fn self_test() -> err {
    var storage: [1024]u8 = zero
    var output: binary.Buffer = zero
    try binary.init(&output, storage[..])
    var section_storage: [5]Section = zero
    var string_storage: [4]str = zero
    var string_slots: [8]usize = zero
    var strings: StringTable = zero
    try init_strings(&strings, string_storage[..], string_slots[..])
    let (target_index, target_error) = intern(&strings, "x64-linux")
    if target_error != ok || target_index != 1usize { ret InvalidArtifact }
    let (module_name, module_error) = intern(&strings, "main")
    if module_error != ok || module_name != 2usize { ret InvalidArtifact }
    var writer: Writer = zero
    try begin(&writer, &output, section_storage[..], target_index, 0usize, .Debug)
    try begin_section(&writer, strings_kind(), required_flag())
    try write_strings(&strings, &output)
    try end_section(&writer)
    try begin_section(&writer, interface_kind(), required_flag())
    let interface_start = output.count
    try binary.little_u64(&output, 0usize)
    try binary.little_u32(&output, 1usize)
    try binary.little_u32(&output, module_name)
    try binary.byte(&output, declaration_function_kind())
    try binary.zeroes(&output, 3usize)
    try binary.little_u32(&output, 20usize)
    try binary.little_u32(&output, module_name)
    try binary.little_u64(&output, 123usize)
    try binary.little_u64(&output, 456usize)
    try binary.little_u32(&output, 0usize)
    let (interface_hash, interface_hash_error) = artifact_hash.xxhash64(output.bytes[interface_start..output.count])
    if interface_hash_error != ok { ret interface_hash_error }
    try binary.patch_little_u64(&output, interface_start, interface_hash)
    try end_section(&writer)
    try begin_section(&writer, deps_kind(), required_flag())
    try binary.little_u32(&output, 1usize)
    try binary.byte(&output, dependency_signature_kind())
    try binary.zeroes(&output, 3usize)
    try binary.little_u32(&output, module_name)
    try binary.little_u32(&output, module_name)
    try binary.little_u64(&output, 123usize)
    try end_section(&writer)
    try begin_section(&writer, code_kind(), required_flag())
    var code_hash_storage: [16]u8 = zero
    var code_hash_input: binary.Buffer = zero
    try binary.init(&code_hash_input, code_hash_storage[..])
    try binary.little_u32(&code_hash_input, 1usize)
    try binary.byte(&code_hash_input, 195usize)
    try binary.little_u32(&code_hash_input, 0usize)
    let (code_hash, code_hash_error) = artifact_hash.xxhash64(code_hash_input.bytes[0usize..code_hash_input.count])
    if code_hash_error != ok { ret code_hash_error }
    try binary.little_u32(&output, 1usize)
    try binary.little_u32(&output, module_name)
    try binary.little_u32(&output, 0usize)
    try binary.little_u64(&output, code_hash)
    try binary.little_u32(&output, 1usize)
    try binary.little_u32(&output, 0usize)
    try binary.byte(&output, 195usize)
    try end_section(&writer)
    try begin_section(&writer, debug_kind(), required_flag())
    try binary.little_u64(&output, 0usize)
    try end_section(&writer)
    try finish(&writer)
    try validate(output.bytes[0usize..output.count])
    let (error_count, error_count_error) = artifact_error_count(output.bytes[0usize..output.count])
    if error_count_error != ok || error_count != 0usize { ret InvalidArtifact }
    let (code_count, code_count_error) = artifact_code_count(output.bytes[0usize..output.count])
    if code_count_error != ok || code_count != 1usize { ret InvalidArtifact }
    let (code_function, code_function_error) = artifact_code_function_at(output.bytes[0usize..output.count], 0usize)
    if code_function_error != ok || code_function.code_length != 1usize || code_function.relocation_count != 0usize { ret InvalidArtifact }
    let (checked_code_hash, checked_code_hash_error) = artifact_code_content_hash(output.bytes[0usize..output.count], code_function, &code_hash_input)
    if checked_code_hash_error != ok || checked_code_hash != code_hash { ret InvalidArtifact }
    let (declaration, found_declaration, declaration_error) = find_declaration(output.bytes[0usize..output.count], "main")
    if declaration_error != ok || !found_declaration || declaration.signature_hash != 123usize || declaration.body_hash != 456usize { ret InvalidArtifact }
    let (dependency, dependency_error) = dependency_at(output.bytes[0usize..output.count], 0usize)
    if dependency_error != ok || dependency.kind != dependency_signature_kind() || dependency.hash != 123usize { ret InvalidArtifact }
    let (matches_dependency, dependency_match_error) = dependency_matches(output.bytes[0usize..output.count], 0usize, output.bytes[0usize..output.count])
    if dependency_match_error != ok || !matches_dependency { ret InvalidArtifact }
    output.bytes[0usize] = 0u8
    if validate(output.bytes[0usize..output.count]) != InvalidArtifact { ret InvalidArtifact }
    output.bytes[0usize] = 78u8
    if validate(output.bytes[0usize..output.count]) != ok { ret InvalidArtifact }
    output.bytes[output.count - 1usize] = 1u8
    if validate(output.bytes[0usize..output.count]) != InvalidArtifact { ret InvalidArtifact }
    ret ok
}
