// Canonical compiled-module container. Payload schemas are layered on this format.

use artifact_hash
use binary
use e.mem
use e.os
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
    // `--release --unchecked` (D355): the memory rows left out, so different code
    // under the same directory; its own identity (D369, H15) or a warm build keeps
    // the other policy's artifacts.
    Unchecked,
    // A debug build under `--unchecked` (D929): the debug code with every row but the
    // always-on ones left out, a policy and so a mode of its own.
    DebugUnchecked,
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

// (D1510) Format 15: function and aggregate records carry an attribute tail.
// (D1514) Format 16: the Globals section carries each global's type after its records.
// (D1515) Format 17: the Emission section.
// (D1582) Format 18: the Vars section.
// (D1584) Format 19: a Vars record carries its scope.
// (D1589) Format 20: a kernel's Interface entry carries its capabilities and shared total.
fn format_version() -> usize { ret 20usize }
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
// The unsafe inventory (D457): the manifest's records for the module, rendered.
fn inventory_kind() -> usize { ret 10usize }
// (D1515) Per code function, in the Code section's order: the identity of what
// instruction selection read, zero for none, and a trap stub's operand moves.
fn emission_kind() -> usize { ret 11usize }
fn emission_record_size() -> usize { ret 16usize }
// (D1582) Per code function, in the Code section's order: its named locals for a
// debugger -- a code range within the function, the name, the type as a descriptor,
// the parameter position plus one, and the location.
fn vars_kind() -> usize { ret 12usize }
fn var_record_size() -> usize { ret 36usize }

fn declaration_function_kind() -> usize { ret 1usize }
fn declaration_aggregate_kind() -> usize { ret 2usize }
fn declaration_alias_kind() -> usize { ret 3usize }
fn declaration_constant_kind() -> usize { ret 4usize }
fn declaration_error_kind() -> usize { ret 5usize }
// The checksum the header carries (D473): CRC-32C over the file with the field
// zeroed, as `check_layout` verified it; read raw, for a manifest to record.
fn artifact_checksum(bytes: []const u8) -> (usize, err) {
    let (stored, read_error) = binary.read_u32(bytes, 28usize)
    if read_error != ok { ret (0usize, InvalidArtifact) }
    ret (stored, ok)
}

fn dependency_signature_kind() -> usize { ret 1usize }
fn dependency_value_kind() -> usize { ret 2usize }
fn dependency_body_kind() -> usize { ret 3usize }
fn dependency_lookup_kind() -> usize { ret 4usize }

fn mode_id(mode: BuildMode) -> usize {
    if mode == .Release { ret 1usize }
    if mode == .Unchecked { ret 2usize }
    if mode == .DebugUnchecked { ret 3usize }
    ret 0usize
}

fn known_kind(kind: usize) -> bool {
    ret kind >= strings_kind() && kind <= vars_kind()
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
    // (D1590) The shared address space of a slice or pointer (section 10).
    if ty.in_shared { flags += 8usize }
    // (D1676) A function type called by the C convention.
    if ty.foreign { flags += 16usize }
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
    if opcode == .VectorBinary { ret 56usize }
    if opcode == .Data { ret 57usize }
    if opcode == .TrapStub { ret 58usize }
    if opcode == .Barrier { ret 59usize }
    if opcode == .MemoryBarrier { ret 60usize }
    if opcode == .Subgroup { ret 61usize }
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

// A comptime parameter's kind in the artifact (D325): the section 9 kinds that arrived
// after the writer -- a string, a field, a member -- were refused, so a module
// declaring a `[LABEL: str]` generic had no artifact and, once every executable is
// linked from artifacts, no executable.
fn comptime_kind_id(kind: check.ComptimeKind) -> usize {
    if kind == .Type { ret 1usize }
    if kind == .Integer { ret 2usize }
    if kind == .Str { ret 3usize }
    if kind == .Field { ret 4usize }
    if kind == .Member { ret 5usize }
    if kind == .Array { ret 6usize }
    if kind == .Function { ret 7usize }
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
    // (D1676) `@cc`: a caller passes an aggregate the C way, so it is the signature's.
    // Not 4: the Interface's record adds that for an instance.
    if function.callback { flags += 16usize }
    ret flags
}

fn write_function_signature_canonical(c: *check.Checker, g: *graph.Graph, function_index: usize, output: *binary.Buffer) -> err {
    if function_index >= c.function_count { ret InvalidArtifact }
    let function = c.functions[function_index]
    if function.module_index >= g.count { ret InvalidArtifact }
    try binary.byte(output, declaration_function_kind())
    // An extern's `...` is part of what a caller is checked against (D1677): a call
    // passing arguments past the declared ones is refused once it is gone, so it has to
    // change every caller's edge. Only a C variadic sets the bit -- 8, clear of the
    // Interface's instance 4 -- so every other signature hashes as it did.
    var flags = function_flags(function)
    if function.variadic { flags += 8usize }
    try binary.byte(output, flags)
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
        if parameter.kind == .Integer || parameter.kind == .Array || parameter.kind == .Function { try write_type_canonical(c, g, parameter.ty, output) }
        at += 1usize
    }
    try binary.little_u32(output, function.parameter_count)
    at = 0usize
    while at < function.parameter_count {
        if function.first_parameter + at >= c.parameter_count { ret InvalidArtifact }
        let parameter = c.parameters[function.first_parameter + at]
        // A parameter's name is not its signature (D535, H14): a call is positional,
        // so a caller compiled against `n` is compiled against `count` the same, and
        // a rename no longer rebuilds every importer; the type and `own` remain.
        // `own` is part of the signature (D345): a caller compiled against a borrowing
        // parameter has to be checked again when it starts taking ownership.
        if parameter.own { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
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
    try binary.little_u32(output, check.function_borrow_from(c, function))
    let noescape_count = check.function_noescape_count(c, function)
    try binary.little_u32(output, noescape_count)
    at = 0usize
    while at < noescape_count {
        try binary.little_u32(output, check.function_noescape_position_at(c, function, at))
        at += 1usize
    }
    // An extern's `@import` is part of what a caller is compiled against (D1672): the
    // call's relocation names the library and the symbol, so a changed binding has to
    // change every caller's edge, or a warm build keeps the old one. Only an extern
    // with a binding writes them: a function that is not extern keeps its `@borrows`
    // and `@noescape` spellings in the same fields, whose positions are written above,
    // and every other signature hashes as it did.
    if function.external && function.import_library.len != 0usize {
        try canonical_text(output, function.import_library)
        try canonical_text(output, function.import_symbol)
    }
    // A kernel's `@gpu` and its workgroup size (D1677): a caller's `gpu.launch`
    // launcher bakes the size in and calls the kernel with its frame and shared
    // blocks first, and a direct call to a kernel is refused. Only a kernel writes
    // it, so every other signature hashes as it did; an extern is never a kernel.
    if function.gpu { try binary.little_u32(output, usize(function.gpu_size)) }
    // (D1677) Device-only (D1589) decides who may call a function: a caller checked
    // against a helper that became device-only has to be checked again. Read from the
    // body, it is written only when set, so every other signature hashes as it did;
    // an extern or a kernel is never device-only, so this follows neither tail above.
    if check.device_only(c, g, function_index) { try binary.byte(output, 1usize) }
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
        if parameter.kind == .Integer || parameter.kind == .Array || parameter.kind == .Function { try write_type_canonical(c, g, parameter.ty, output) }
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
    // An aggregate's layout attributes are part of what a dependent is compiled against
    // (D1677): `@packed` and `@align(N)` move its fields' offsets and its size, and
    // `@reorder` both and the FFI crossings it is refused at (D239). So is `resource`
    // and its cleanup (D348): a dependent may not read a resource's fields (E-SAFETY-0010)
    // and owes the value it acquires (E-SAFETY-0002). Written only when one is present,
    // in D1510's tail bits (resource 1, reorder 2, packed 4), so every other aggregate
    // hashes as it did.
    if aggregate.resource || aggregate.reorder || aggregate.packed || aggregate.align != 0usize {
        var attributes = 0usize
        if aggregate.resource { attributes += 1usize }
        if aggregate.reorder { attributes += 2usize }
        if aggregate.packed { attributes += 4usize }
        try binary.byte(output, attributes)
        try binary.zeroes(output, 3usize)
        try binary.little_u32(output, aggregate.align)
        if aggregate.resource { try canonical_text(output, aggregate.cleanup) }
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
    if same(name, "neper_os_copy_bytes") { ret ("copy_bytes", true) }
    if same(name, "neper_os_touch") { ret ("touch", true) }
    if same(name, "neper_os_sha256_blocks") { ret ("sha256_blocks", true) }
    if same(name, "neper_os_crc32c_bytes") { ret ("crc32c_bytes", true) }
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
    // (D2126) aarch64-none's machine.
    if same(name, "neper_os_set_console") { ret ("set_console", true) }
    if same(name, "neper_os_set_exit") { ret ("set_exit", true) }
    if same(name, "neper_os_set_exception") { ret ("set_exception", true) }
    if same(name, "neper_os_load8") { ret ("load8", true) }
    if same(name, "neper_os_load16") { ret ("load16", true) }
    if same(name, "neper_os_load32") { ret ("load32", true) }
    if same(name, "neper_os_load64") { ret ("load64", true) }
    if same(name, "neper_os_store8") { ret ("store8", true) }
    if same(name, "neper_os_store16") { ret ("store16", true) }
    if same(name, "neper_os_store32") { ret ("store32", true) }
    if same(name, "neper_os_store64") { ret ("store64", true) }
    if same(name, "neper_os_barrier") { ret ("barrier", true) }
    if same(name, "neper_os_tlb_flush") { ret ("tlb_flush", true) }
    if same(name, "neper_os_wait_for_interrupt") { ret ("wait_for_interrupt", true) }
    if same(name, "neper_os_memory_barrier") { ret ("memory_barrier", true) }
    if same(name, "neper_os_wait_for_event") { ret ("wait_for_event", true) }
    if same(name, "neper_os_send_event") { ret ("send_event", true) }
    if same(name, "neper_os_yield") { ret ("yield", true) }
    if same(name, "neper_os_send") { ret ("send", true) }
    if same(name, "neper_os_recv") { ret ("recv", true) }
    if same(name, "neper_os_cap_derive") { ret ("cap_derive", true) }
    if same(name, "neper_os_cap_revoke") { ret ("cap_revoke", true) }
    if same(name, "neper_os_frame_protect") { ret ("frame_protect", true) }
    if same(name, "neper_os_notify_wait") { ret ("notify_wait", true) }
    if same(name, "neper_os_device_write") { ret ("device_write", true) }
    if same(name, "neper_os_retype") { ret ("retype", true) }
    if same(name, "neper_os_hvc") { ret ("hvc", true) }
    if same(name, "neper_os_smc") { ret ("smc", true) }
    if same(name, "neper_os_mrs") { ret ("mrs", true) }
    if same(name, "neper_os_msr") { ret ("msr", true) }
    // A kernel's `K$frame` and `K$shared` (D780, D781) are generated beside the
    // kernel and have no declaration of their own: the dependency they stand for
    // is the kernel's.
    let suffix = "$frame"
    if name.len > suffix.len {
        let tail = name[name.len - suffix.len..name.len]
        if same(tail, suffix) { ret (name[0usize..name.len - suffix.len], true) }
    }
    let shared_suffix = "$shared"
    if name.len > shared_suffix.len {
        let shared_tail = name[name.len - shared_suffix.len..name.len]
        if same(shared_tail, shared_suffix) { ret (name[0usize..name.len - shared_suffix.len], true) }
    }
    // The kernel's SPIR-V (D1611), a companion as its sizes are.
    let spirv_suffix = "$spirv"
    if name.len > spirv_suffix.len {
        let spirv_tail = name[name.len - spirv_suffix.len..name.len]
        if same(spirv_tail, spirv_suffix) { ret (name[0usize..name.len - spirv_suffix.len], true) }
    }
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
        if usize(tokens[mid].start) < start { low = mid + 1usize } else { high = mid }
    }
    var at = low
    while at < tokens.len && usize(tokens[at].end) <= end {
        let token = tokens[at]
        if token.kind == .Invalid { ret InvalidArtifact }
        if token.kind != .Eof {
            if token.start > token.end { ret InvalidArtifact }
            try canonical_text(output, lex.token_text(text, token))
        }
        at += 1usize
    }
    ret ok
}

fn body_hash(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, checked_function: usize, nir_function: usize, has_nir: bool, scratch: *binary.Buffer) -> (usize, err) {
    // Memoized for a function with source (D326): its tokens and line are fixed for
    // the build. One without source is hashed from NIR, which differs by builder.
    if checked_function >= c.function_count { ret (0usize, InvalidArtifact) }
    let memoized = checked_function < c.body_hashes.len && c.functions[checked_function].source_end > c.functions[checked_function].source_start
    if memoized && c.body_hashes[checked_function] != 0usize { ret (c.body_hashes[checked_function] - 1usize, ok) }
    let (hash, hash_error) = body_hash_uncached(c, g, builder, checked_function, nir_function, has_nir, scratch)
    if hash_error == ok && memoized { c.body_hashes[checked_function] = hash + 1usize }
    ret (hash, hash_error)
}

// (D1668) An inlined callee's body hash memoized on the program's checker before the
// lowering, when its declaration is in a module a worker may give back before a module
// that inlined it is written (`write_dependencies`). The inputs are the ones a worker
// reads -- the declaration rows, the text, the lines and the tokens -- so it is the hash
// the worker would take. Answers the function's index and whether it was hashed.
fn prefill_body_hash(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, name: str, scratch: *binary.Buffer) -> (usize, bool, err) {
    if module_index >= g.count { ret (0usize, false, ok) }
    let (checked_function, found) = find_checked_function(c, module_index, name)
    if !found || checked_function >= c.body_hashes.len { ret (0usize, false, ok) }
    let function = c.functions[checked_function]
    if function.source_end <= function.source_start || function.module_index >= g.count || !g.modules[function.module_index].droppable { ret (0usize, false, ok) }
    let (_, hash_error) = body_hash(c, g, builder, checked_function, 0usize, false, scratch)
    if hash_error != ok { ret (0usize, false, hash_error) }
    ret (checked_function, true, ok)
}

fn body_hash_uncached(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, checked_function: usize, nir_function: usize, has_nir: bool, scratch: *binary.Buffer) -> (usize, err) {
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
        // (D1667) A released module's declaration has no tokens to hash, and hashing
        // none would be a wrong body edge, not a failure. (D1668) Nor has one another
        // worker may give back: an inlined callee's hash was taken before the lowering
        // (`prefill_body_hash`), and any other is a miss, refused whenever the module is
        // another worker's or its owner has given it back already (`front_readable`).
        if !graph.front_readable(g, function.module_index, c.fork.id) { ret (0usize, graph.ModuleDropped) }
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

// The spans a lowering worker's module set over the builder's functions and inlined
// entries, cleared before its rows are discarded (D1664), and both tables scanned from
// their first row again. `span_clear` over the two was four words for every module of
// the program, for each module a worker lowered: quadratic in the modules, as the used
// marks were until D930. A fork's spans start zero and only `update_spans` sets a
// pair, for a row below the count, so the rows name every pair set since the last
// clear.
fn span_clear_rows(c: *check.Checker, builder: *nir.Builder) {
    var at = 0usize
    while at < builder.function_count {
        span_zero(c, span_nir(), builder.functions[at].module_index)
        at += 1usize
    }
    at = 0usize
    while at < builder.inlined_count {
        span_zero(c, span_inlined(), builder.inlined[at].caller_module)
        at += 1usize
    }
    c.writer_scanned[span_nir()] = 0usize
    c.writer_scanned[span_inlined()] = 0usize
}

fn span_zero(c: *check.Checker, table: usize, module_index: usize) {
    let modules = span_modules(c)
    if module_index >= modules { ret }
    let at = (table * modules + module_index) * 2usize
    c.writer_spans[at] = 0usize
    c.writer_spans[at + 1usize] = 0usize
}

fn update_spans(c: *check.Checker, builder: *nir.Builder) -> err {
    if c.writer_spans.len == 0usize { ret InvalidArtifact }
    var at = c.writer_scanned[span_functions()]
    while at < c.signature_function_count {
        span_extend(c, span_functions(), c.functions[at].module_index, at)
        at += 1usize
    }
    c.writer_scanned[span_functions()] = c.signature_function_count
    // An instance is owned by the module that instantiated it. A worker's own rows
    // start past the other workers' windows (D1671), and its scan with them.
    at = c.writer_scanned[span_instances()]
    if at < check.own_rows(c) { at = check.own_rows(c) }
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

// The strings the aggregate edges need (D493, D494), interned; its own function for
// the bootstrap's 256 locals a body may hold.
fn intern_aggregate_strings(c: *check.Checker, g: *graph.Graph, table: *StringTable, aggregate_marks: []u8) -> err {
    var aggregate_string_at = 0usize
    while aggregate_string_at < c.aggregate_count && aggregate_string_at < aggregate_marks.len {
        if aggregate_marks[aggregate_string_at] != 0u8 {
            let marked = c.aggregates[aggregate_string_at]
            if marked.module_index >= g.count { ret InvalidArtifact }
            let (marked_module_name, marked_module_name_error) = intern(table, g.modules[marked.module_index].name)
            if marked_module_name_error != ok { ret marked_module_name_error }
            let (marked_name, marked_name_error) = intern(table, marked.name)
            if marked_name_error != ok { ret marked_name_error }
        }
        aggregate_string_at += 1usize
    }
    ret ok
}

// The marks it leaves in `aggregate_marks` and `string_marks` are the module's
// aggregate and body constant uses, which the dependency writer reads (D931): each was
// made again there, three token walks of the module where one serves.
fn collect_module_strings(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable, aggregate_marks: []u8, string_marks: []u8) -> err {
    if module_index >= g.count { ret InvalidArtifact }
    try update_spans(c, builder)
    try mark_module_references(builder, c, module_index)
    let (module_name, module_name_error) = intern(table, g.modules[module_index].name)
    if module_name_error != ok { ret module_name_error }
    let (source_path, source_path_error) = intern(table, g.modules[module_index].spelling)
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
            // (D1510) The attribute tail's strings.
            if function.import_library.len > 0usize {
                let (library_name, library_name_error) = intern(table, function.import_library)
                if library_name_error != ok { ret library_name_error }
            }
            if function.import_symbol.len > 0usize {
                let (symbol_name, symbol_name_error) = intern(table, function.import_symbol)
                if symbol_name_error != ok { ret symbol_name_error }
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
            // (D1510) The attribute tail's cleanup name.
            if aggregate.cleanup.len > 0usize {
                let (cleanup_name, cleanup_name_error) = intern(table, aggregate.cleanup)
                if cleanup_name_error != ok { ret cleanup_name_error }
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
    mark_aggregate_uses(c, g, builder, module_index, aggregate_marks)
    try intern_aggregate_strings(c, g, table, aggregate_marks)
    mark_body_constant_uses(c, g, module_index, string_marks)
    constant_at = 0usize
    while constant_at < c.constant_count {
        let constant = c.constants[constant_at]
        if constant.module_index != module_index {
            let (used_by_constant, used_error) = foreign_constant_used_by_module(c, module_index, constant_at)
            if used_error != ok { ret used_error }
            let used = used_by_constant || (constant_at < string_marks.len && string_marks[constant_at] != 0u8)
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
                try collect_type_strings(c, g, table, builder.instructions[instruction_at].ty)
                let opcode = builder.instructions[instruction_at].opcode
                let immediate = builder.instructions[instruction_at].immediate
                if opcode == .Call || opcode == .FunctionAddress {
                    if immediate >= builder.function_ref_count { ret InvalidArtifact }
                    let reference = builder.function_refs[immediate]
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
                if opcode == .GlobalAddress {
                    if immediate >= builder.global_count { ret InvalidArtifact }
                    let global = builder.globals[immediate]
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
    // (D1514) The strings of the globals' types.
    global_at = 0usize
    while global_at < c.global_count {
        if c.globals[global_at].module_index == module_index { try collect_type_strings(c, g, table, c.globals[global_at].ty) }
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
    // (D1511) The Interface flags an instance 4, apart from the signature's flags,
    // so a decode can tell a generic's instance from a declared function.
    var interface_flags = function_flags(function)
    if c.function_generics[function_index].instance { interface_flags += 4usize }
    try binary.byte(output, interface_flags)
    try binary.little_u16(output, 0usize)
    let length_offset = output.count
    try binary.little_u32(output, 0usize)
    let payload_start = output.count
    try binary.little_u32(output, name_index)
    try binary.little_u64(output, signature)
    try binary.little_u64(output, body)
    try binary.little_u32(output, check.function_borrow_from(c, function))
    let noescape_count = check.function_noescape_count(c, function)
    try binary.little_u32(output, noescape_count)
    var noescape_at = 0usize
    while noescape_at < noescape_count {
        try binary.little_u32(output, check.function_noescape_position_at(c, function, noescape_at))
        noescape_at += 1usize
    }
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
        if parameter.kind == .Integer || parameter.kind == .Array || parameter.kind == .Function { try write_type_indexed(c, g, table, parameter.ty, output) }
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
    // (D1510) The attribute tail: what the checker keeps of a function beyond its
    // signature, so a kept module's declarations can come from here -- intrinsic 1,
    // variadic 2, gpu 4, device-only 8 (D1677), `@cc` 16 (D1676); the packed workgroup
    // size; the import library and symbol (for a non-extern function the `@borrows` name
    // and `@noescape` spelling) as string indexes plus one, zero for none; and each
    // parameter's `own`.
    var attributes = 0usize
    if function.intrinsic { attributes += 1usize }
    if function.variadic { attributes += 2usize }
    if function.gpu { attributes += 4usize }
    // (D1677) A declaration from the Interface has no body to read device-only from, and
    // its callers' checks and signature edges need it.
    if check.device_only(c, g, function_index) { attributes += 8usize }
    if function.callback { attributes += 16usize }
    try binary.byte(output, attributes)
    // (D1589) A kernel's inferred capabilities (`gpu.Cap`'s members as bits) and the
    // bytes of its `shared var`s, which `gpu.launch` checks against a device (spec
    // section 10); zero for any other function.
    var facts = 0usize
    if function.gpu { facts = check.kernel_fact(c, function_index) }
    try binary.byte(output, facts % 256usize)
    try binary.byte(output, (facts / 256usize) % 256usize)
    try binary.byte(output, 0usize)
    try binary.little_u32(output, usize(function.gpu_size))
    try binary.little_u32(output, (facts / 65536usize) % 4294967296usize)
    try write_optional_string(table, function.import_library, output)
    try write_optional_string(table, function.import_symbol, output)
    at = 0usize
    while at < function.parameter_count {
        if c.parameters[function.first_parameter + at].own { try binary.byte(output, 1usize) } else { try binary.byte(output, 0usize) }
        at += 1usize
    }
    ret binary.patch_little_u32(output, length_offset, output.count - payload_start)
}

// (D1510) A string that may be empty: its index plus one, or zero.
fn write_optional_string(table: *StringTable, value: str, output: *binary.Buffer) -> err {
    if value.len == 0usize { ret binary.little_u32(output, 0usize) }
    let (index, index_error) = string_index(table, value)
    if index_error != ok { ret index_error }
    ret binary.little_u32(output, index + 1usize)
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
        if parameter.kind == .Integer || parameter.kind == .Array || parameter.kind == .Function { try write_type_indexed(c, g, table, parameter.ty, output) }
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
    // (D1510) The attribute tail: resource 1, reorder 2, packed 4; `@align`; and
    // the cleanup function's name as a string index plus one, zero for none.
    var attributes = 0usize
    if aggregate.resource { attributes += 1usize }
    if aggregate.reorder { attributes += 2usize }
    if aggregate.packed { attributes += 4usize }
    try binary.byte(output, attributes)
    try binary.zeroes(output, 3usize)
    try binary.little_u32(output, aggregate.align)
    try write_optional_string(table, aggregate.cleanup, output)
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

// The last module's marks are the only ones set when its list was whole (D930): a
// worker's builder held every reference of every module it lowered, and clearing all
// of them for each module was quadratic in its modules. None left, the empty list is
// whole.
fn clear_used_marks(builder: *nir.Builder) {
    var clear_at = 0usize
    if builder.used_complete {
        while clear_at < builder.used_count {
            builder.used_marks[builder.used_list[clear_at]] = 0u8
            builder.edge_marks[builder.used_list[clear_at]] = 0u8
            clear_at += 1usize
        }
    } else {
        // Every mark, past the count too: a compaction renumbers the references, and a
        // mark left beyond the new count would belong to whichever reference lands there.
        while clear_at < builder.used_marks.len {
            builder.used_marks[clear_at] = 0u8
            clear_at += 1usize
        }
        clear_at = 0usize
        while clear_at < builder.edge_marks.len {
            builder.edge_marks[clear_at] = 0u8
            clear_at += 1usize
        }
    }
    builder.used_count = 0usize
    builder.used_complete = true
}

// The module's references marked in one pass (D319), and its edges with them (D320): a
// used reference to another module's declaration records a signature edge unless an
// earlier reference resolves to the same declaration -- distinct generic instances
// intern distinct references -- and an inlined entry stands for its body edge unless an
// earlier entry of the module names the callee. The index dedupes both; the walks it
// replaces compared every used reference against every earlier one, per module.
fn mark_module_references(builder: *nir.Builder, c: *check.Checker, module_index: usize) -> err {
    if builder.used_marks_valid && builder.used_marks_module == module_index { ret ok }
    // The last module's marks go first, whatever this one holds (D1664): a lowering
    // worker's references start again at its mark for every module, so a module with
    // none left the marks of the one before it set, and the next module's walk passed
    // over every reference landing on a marked index -- an edge its artifact never had.
    clear_used_marks(builder)
    if builder.function_ref_count == 0usize && builder.inlined_count == 0usize {
        builder.used_marks_module = module_index
        builder.used_marks_valid = true
        ret ok
    }
    if builder.used_marks.len < builder.function_ref_count || builder.edge_marks.len < builder.function_ref_count || builder.inlined_marks.len < builder.inlined_count { ret InvalidArtifact }
    builder.used_complete = false
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            let function = builder.functions[function_at]
            var instruction_at = function.first_instruction
            while instruction_at < function.first_instruction + function.instruction_count {
                // The two fields read, not the instruction copied (D932).
                let opcode = builder.instructions[instruction_at].opcode
                let immediate = builder.instructions[instruction_at].immediate
                if (opcode == .Call || opcode == .FunctionAddress) && immediate < builder.function_ref_count && builder.used_marks[immediate] == 0u8 {
                    builder.used_marks[immediate] = 1u8
                    if builder.used_count < builder.used_list.len {
                        builder.used_list[builder.used_count] = immediate
                        builder.used_count += 1usize
                    }
                }
                instruction_at += 1usize
            }
        }
        function_at += 1usize
    }
    // The used references in index order, the order every walk below made (D930).
    if builder.used_count < builder.used_list.len {
        sort_indexes(builder.used_list[0usize..builder.used_count])
        builder.used_complete = true
    }
    try lookup.attach(&builder.edge_index, builder.edge_index.entries)
    var walk = 0usize
    while walk < reference_walk_count(builder) {
        let at = reference_walk_at(builder, walk)
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
        walk += 1usize
    }
    let (inlined_first, inlined_end) = span_of(c, span_inlined(), module_index)
    var at = inlined_first
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

// A body's uses of foreign constants (D492, H14): every `q.NAME` in the module's
// tokens where `q` is a qualifier of an imported module and `NAME` one of its
// constants marks that constant used -- its value is baked into the body, so the
// edge is a value edge and a change to it rebuilds this module. One pass over the
// tokens; a program past `marks.len` constants records the rest as before.
// ponytail: a struct literal field or a member spelled `q.NAME` marks a constant of
// the same name too, an edge held to a value that did not change -- harmless.
fn mark_body_constant_uses(c: *check.Checker, g: *graph.Graph, module_index: usize, marks: []u8) {
    if module_index >= g.count { ret }
    let module = g.modules[module_index]
    let tokens = module.tokens
    var token_at = 0usize
    while token_at + 2usize < tokens.len {
        if tokens[token_at].kind == .Identifier && tokens[token_at + 1usize].kind == .PunctDot && tokens[token_at + 2usize].kind == .Identifier {
            let qualifier = lex.token_text(module.text, tokens[token_at])
            let name = lex.token_text(module.text, tokens[token_at + 2usize])
            var import_at = module.first_import
            let import_end = module.first_import + module.import_count
            while import_at < import_end {
                if same(g.imports[import_at].qualifier, qualifier) {
                    let imported = g.imports[import_at].target
                    let (first, end) = span_of(c, span_constants(), imported)
                    var constant_at = first
                    while constant_at < end {
                        if constant_at < marks.len && c.constants[constant_at].module_index == imported && same(c.constants[constant_at].name, name) { marks[constant_at] = 1u8 }
                        constant_at += 1usize
                    }
                }
                import_at += 1usize
            }
        }
        token_at += 1usize
    }
}

// The foreign aggregates a module's bodies can touch (D493, H14): every named type
// in the signature of a function the module references, every aggregate spelled
// `q.Name` in its tokens, and the aggregates of their fields, to a fixed point.
// Each is a signature edge -- the aggregate's signature hash covers its fields in
// order -- so a change to a layout the body reads rebuilds the module. Before, a
// module kept as `edges-hold` read the old layout: a wrong program from a warm build.
fn mark_type_aggregates(c: *check.Checker, ty: check.Type, module_index: usize, marks: []u8, changed: *bool) {
    var subject = ty
    if subject.kind == .Pointer || subject.kind == .Slice || subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret }
        mark_type_aggregates(c, c.types[subject.element], module_index, marks, changed)
        ret
    }
    let (canonical, canonical_error) = check.canonical_type(c, subject)
    if canonical_error != ok { ret }
    let (aggregate_index, found) = check.aggregate_for_type(c, canonical)
    if !found || aggregate_index >= marks.len { ret }
    if c.aggregates[aggregate_index].module_index == module_index || marks[aggregate_index] != 0u8 { ret }
    marks[aggregate_index] = 1u8
    *changed = true
}

fn mark_aggregate_uses(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, marks: []u8) {
    if module_index >= g.count { ret }
    var changed = false
    // The signatures the module references.
    var walk = 0usize
    while walk < reference_walk_count(builder) {
        let at = reference_walk_at(builder, walk)
        let (dependency_name, records_dependency) = module_dependency_reference(builder, module_index, at)
        if records_dependency && builder.function_refs[at].module_index < g.count {
            let (checked_function, found_function) = find_checked_function(c, builder.function_refs[at].module_index, dependency_name)
            if found_function {
                let function = c.functions[checked_function]
                var parameter_at = 0usize
                while parameter_at < function.parameter_count {
                    if function.first_parameter + parameter_at < c.parameter_count { mark_type_aggregates(c, c.parameters[function.first_parameter + parameter_at].ty, module_index, marks, &changed) }
                    parameter_at += 1usize
                }
                var return_at = 0usize
                while return_at < function.return_count {
                    if function.first_return + return_at < c.return_type_count { mark_type_aggregates(c, c.return_types[function.first_return + return_at], module_index, marks, &changed) }
                    return_at += 1usize
                }
            }
        }
        walk += 1usize
    }
    // The aggregates the module spells as `q.Name`.
    let module = g.modules[module_index]
    let tokens = module.tokens
    var token_at = 0usize
    while token_at + 2usize < tokens.len {
        if tokens[token_at].kind == .Identifier && tokens[token_at + 1usize].kind == .PunctDot && tokens[token_at + 2usize].kind == .Identifier {
            let qualifier = lex.token_text(module.text, tokens[token_at])
            let name = lex.token_text(module.text, tokens[token_at + 2usize])
            var import_at = module.first_import
            let import_end = module.first_import + module.import_count
            while import_at < import_end {
                // The index says whether the module declares an aggregate of the name at
                // all (D930): most `q.x` are calls and fields, and the walk of every
                // aggregate below was a sixth of the artifact writer's time.
                let (declared_at, declared) = check.find_aggregate(c, g.imports[import_at].target, name)
                if declared && same(g.imports[import_at].qualifier, qualifier) {
                    let imported = g.imports[import_at].target
                    var aggregate_at = 0usize
                    while aggregate_at < c.aggregate_count && aggregate_at < marks.len {
                        if c.aggregates[aggregate_at].module_index == imported && same(c.aggregates[aggregate_at].name, name) {
                            if marks[aggregate_at] == 0u8 { changed = true }
                            marks[aggregate_at] = 1u8
                        }
                        aggregate_at += 1usize
                    }
                }
                import_at += 1usize
            }
        }
        token_at += 1usize
    }
    // The fields' aggregates, to a fixed point.
    while changed {
        changed = false
        var aggregate_at = 0usize
        while aggregate_at < c.aggregate_count && aggregate_at < marks.len {
            if marks[aggregate_at] == 1u8 {
                marks[aggregate_at] = 2u8
                let aggregate = c.aggregates[aggregate_at]
                var field_at = 0usize
                while field_at < aggregate.field_count {
                    if aggregate.first_field + field_at < c.aggregate_field_count { mark_type_aggregates(c, c.aggregate_fields[aggregate.first_field + field_at].ty, module_index, marks, &changed) }
                    field_at += 1usize
                }
            }
            aggregate_at += 1usize
        }
    }
}

// The protocol functions a marked aggregate's module does not declare (D494, H14):
// `T.eq`, `T.cmp` and `T.hash` over such a type take the supplied rule, and the day
// the module declares `<snake>_eq`, the declared one is selected instead -- so the
// absence is an edge, a lookup with no hash that holds while the name is absent
// (section 12's negative edge, which nothing wrote before). A declared one that is
// called is a signature edge already, and its removal fails that.
fn snake_protocol_name(type_name: str, protocol: str, out: []u8) -> usize {
    var n = 0usize
    var at = 0usize
    while at < type_name.len {
        let byte = type_name[at]
        let upper = byte >= 65u8 && byte <= 90u8
        var previous_lower = false
        if at > 0usize {
            let previous = type_name[at - 1usize]
            previous_lower = (previous >= 97u8 && previous <= 122u8) || (previous >= 48u8 && previous <= 57u8)
        }
        var next_lower = false
        if at + 1usize < type_name.len {
            let next = type_name[at + 1usize]
            next_lower = next >= 97u8 && next <= 122u8
        }
        if n + 3usize >= out.len { ret 0usize }
        if upper && at > 0usize && (previous_lower || next_lower) {
            out[n] = 95u8
            n += 1usize
        }
        if upper { out[n] = byte + 32u8 } else { out[n] = byte }
        n += 1usize
        at += 1usize
    }
    if n + 1usize + protocol.len >= out.len { ret 0usize }
    out[n] = 95u8
    n += 1usize
    var suffix_at = 0usize
    while suffix_at < protocol.len {
        out[n] = protocol[suffix_at]
        n += 1usize
        suffix_at += 1usize
    }
    ret n
}

fn protocol_name_of(which: usize) -> str {
    if which == 0usize { ret "eq" }
    if which == 1usize { ret "cmp" }
    ret "hash"
}

// Whether the aggregate's module declares the protocol function.
fn protocol_declared(c: *check.Checker, aggregate_index: usize, protocol: str) -> bool {
    let aggregate = c.aggregates[aggregate_index]
    // The name spelled and asked of the index (D931): absent is the common answer, and
    // was a walk of every function in the program per aggregate and protocol. A found
    // one that is generic or an instance leaves it to the walk.
    var spelled: [256]u8 = zero
    let spelled_count = snake_protocol_name(aggregate.name, protocol, spelled[..])
    if spelled_count != 0usize {
        let (found_at, found) = check.find_function(c, aggregate.module_index, spelled[0usize..spelled_count])
        if !found { ret false }
        if found_at < c.signature_function_count && !c.functions[found_at].generic { ret true }
    }
    var at = 0usize
    while at < c.signature_function_count {
        let function = c.functions[at]
        if function.module_index == aggregate.module_index && !function.generic && check.protocol_name_matches(aggregate.name, function.name, protocol) { ret true }
        at += 1usize
    }
    ret false
}

fn lookup_dependency_count(c: *check.Checker, marks: []u8) -> usize {
    var count = 0usize
    var at = 0usize
    while at < c.aggregate_count && at < marks.len {
        if marks[at] != 0u8 {
            var which = 0usize
            while which < 3usize {
                if !protocol_declared(c, at, protocol_name_of(which)) { count += 1usize }
                which += 1usize
            }
        }
        at += 1usize
    }
    ret count
}

fn aggregate_dependency_count(c: *check.Checker, marks: []u8) -> usize {
    var count = 0usize
    var at = 0usize
    while at < c.aggregate_count && at < marks.len {
        if marks[at] != 0u8 { count += 1usize }
        at += 1usize
    }
    ret count
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

// The references a module's walks visit (D930): its used ones in index order when the
// list of them was whole, else every reference the builder holds.
fn reference_walk_count(builder: *nir.Builder) -> usize {
    if builder.used_complete { ret builder.used_count }
    ret builder.function_ref_count
}

fn reference_walk_at(builder: *nir.Builder, walk: usize) -> usize {
    if builder.used_complete { ret builder.used_list[walk] }
    ret walk
}

// Indexes in ascending order, in place: a Shell sort, since a module uses a few
// hundred references and the list arrives in the order its instructions name them.
fn sort_indexes(values: []usize) {
    var gap = values.len / 2usize
    while gap > 0usize {
        var at = gap
        while at < values.len {
            let held = values[at]
            var slot = at
            while slot >= gap && values[slot - gap] > held {
                values[slot] = values[slot - gap]
                slot = slot - gap
            }
            values[slot] = held
            at += 1usize
        }
        gap = gap / 2usize
    }
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
    // A generated body (a formatter's, a launcher's) has no template to depend on
    // (D778): a launcher's `template_index` names its kernel, which is ordinary code.
    if generic.formatter || generic.launcher { ret (0usize, false) }
    let template_index = generic.template_index
    if template_index >= c.function_count || c.functions[template_index].module_index == module_index { ret (0usize, false) }
    let (first, end) = span_of(c, span_instances(), module_index)
    var prior = first
    if prior < check.own_rows(c) { prior = check.own_rows(c) }
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
    var walk = 0usize
    while walk < reference_walk_count(builder) {
        let (dependency_name, records_dependency) = module_dependency_reference(builder, module_index, reference_walk_at(builder, walk))
        if records_dependency { count += 1usize }
        walk += 1usize
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

fn value_dependency_count(c: *check.Checker, module_index: usize, marks: []u8) -> (usize, err) {
    var count = 0usize
    var at = 0usize
    while at < c.constant_count {
        let (used_by_constant, used_error) = foreign_constant_used_by_module(c, module_index, at)
        if used_error != ok { ret (0usize, used_error) }
        if used_by_constant || (at < marks.len && marks[at] != 0u8) { count += 1usize }
        at += 1usize
    }
    ret (count, ok)
}

// The aggregate edges (D493): a signature edge each, held by its fields; and the
// protocol functions the module does not declare (D494): negative edges. Its own
// function, since the bootstrap holds a body to 256 locals and `write_dependencies`
// was near it.
fn write_aggregate_dependencies(c: *check.Checker, g: *graph.Graph, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer, aggregate_marks: []u8) -> err {
    var at = 0usize
    while at < c.aggregate_count && at < aggregate_marks.len {
        if aggregate_marks[at] != 0u8 {
            let aggregate = c.aggregates[at]
            if aggregate.module_index >= g.count { ret InvalidArtifact }
            let (hash, hash_error) = aggregate_signature_hash(c, g, at, scratch)
            if hash_error != ok { ret hash_error }
            let (target_module, target_module_error) = string_index(table, g.modules[aggregate.module_index].name)
            if target_module_error != ok { ret target_module_error }
            let (target_name, target_name_error) = string_index(table, aggregate.name)
            if target_name_error != ok { ret target_name_error }
            try binary.byte(output, dependency_signature_kind())
            try binary.zeroes(output, 3usize)
            try binary.little_u32(output, target_module)
            try binary.little_u32(output, target_name)
            try binary.little_u64(output, hash)
            // The protocol functions the module does not declare (D494): negative edges.
            var which = 0usize
            while which < 3usize {
                if !protocol_declared(c, at, protocol_name_of(which)) {
                    // Named by the aggregate, the protocol in the hash field (1 eq, 2
                    // cmp, 3 hash): the string table holds slices, not copies, so a
                    // spelling made here could not be interned; the settle side spells it.
                    try binary.byte(output, dependency_lookup_kind())
                    try binary.zeroes(output, 3usize)
                    try binary.little_u32(output, target_module)
                    try binary.little_u32(output, target_name)
                    try binary.little_u64(output, which + 1usize)
                }
                which += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

fn write_dependencies(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, module_index: usize, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer, aggregate_marks: []u8, body_marks: []u8) -> err {
    try mark_module_references(builder, c, module_index)
    let (value_count, value_count_error) = value_dependency_count(c, module_index, body_marks)
    if value_count_error != ok { ret value_count_error }
    try binary.little_u32(output, dependency_count(builder, c, module_index) + template_dependency_count(c, module_index) + value_count + aggregate_dependency_count(c, aggregate_marks) + lookup_dependency_count(c, aggregate_marks))
    var walk = 0usize
    while walk < reference_walk_count(builder) {
        let at = reference_walk_at(builder, walk)
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
        walk += 1usize
    }
    let (inlined_first, inlined_end) = span_of(c, span_inlined(), module_index)
    var at = inlined_first
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
    try write_aggregate_dependencies(c, g, table, scratch, output, aggregate_marks)
    at = 0usize
    while at < c.constant_count {
        let (used_by_constant, used_error) = foreign_constant_used_by_module(c, module_index, at)
        if used_error != ok { ret used_error }
        if used_by_constant || (at < body_marks.len && body_marks[at] != 0u8) {
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
                try binary.little_u32(output, usize(entry.line))
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
            // Too many rows for the caller's buffer (D541): the count, so it can grow.
            if row_count > out.len { ret (row_count, Capacity) }
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

fn write_globals(builder: *nir.Builder, c: *check.Checker, g: *graph.Graph, module_index: usize, table: *StringTable, output: *binary.Buffer) -> err {
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
    // (D1514) Each global's type, in the records' order -- the checker's, which
    // `lower.declare_globals` adds them in -- so an importer declares from them.
    var typed = 0usize
    at = 0usize
    while at < c.global_count {
        if c.globals[at].module_index == module_index {
            try write_type_indexed(c, g, table, c.globals[at].ty, output)
            typed += 1usize
        }
        at += 1usize
    }
    if typed != count { ret InvalidArtifact }
    ret ok
}

// The text's hash, straight over its bytes (D324): it was copied into a scratch
// buffer first, which a worker thread has none of.
// The identity of a module's text (D504, D534, H14): the canonical text -- every
// comment's body left out, `//` to the end of its line, and every line's trailing
// spaces and tabs with it, the line breaks kept -- hashed as one, so an edit
// inside a comment, a comment added at a line's end or blanked to spaces, keeps the
// artifact, and one that adds or removes a line does not, since the line tables the
// artifact carries would be wrong; nor does one that moves a token's column, which
// the trap records carry. A `//` inside a string, a raw string or a character
// literal is text, not a comment. The bytes' own hash stays the manifest's. The
// key is a candidate (D507, H15): the artifact also carries the canonical text's
// SHA-256, which a hit is verified by when the bytes are not the artifact's.
fn source_text_hash(a: *mem.Arena, text: str) -> (usize, err) {
    let checkpoint = mem.mark(a)
    let (canonical, canonical_error) = comment_blind_text(a, text)
    if canonical_error != ok { ret (0usize, canonical_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(canonical)
    mem.reset(a, checkpoint)
    ret (hash, hash_error)
}

// The next comment at or after `from`: where it starts and where its body ends --
// the line break, or the text's end -- or the text's end twice when there is none.
fn next_comment(text: str, from: usize) -> (usize, usize) {
    let classes = comment_scan_bytes()
    var at = from
    while at < text.len {
        // The bytes that open nothing, in one tight loop by table (D933): a quote, an
        // apostrophe, a slash and an `r` are the only ones the scan below looks at.
        while at < text.len && classes[usize(text[at])] == 0u8 { at += 1usize }
        if at >= text.len { break }
        let byte_here = text[at]
        if byte_here == 34u8 {
            at += 1usize
            while at < text.len && text[at] != 34u8 && text[at] != 10u8 {
                if text[at] == 92u8 { at += 1usize }
                at += 1usize
            }
            at += 1usize
            continue
        }
        if byte_here == 39u8 {
            at += 1usize
            while at < text.len && text[at] != 39u8 && text[at] != 10u8 {
                if text[at] == 92u8 { at += 1usize }
                at += 1usize
            }
            at += 1usize
            continue
        }
        if byte_here == 114u8 && at + 1usize < text.len && (text[at + 1usize] == 34u8 || text[at + 1usize] == 35u8) && (at == 0usize || !identifier_byte(text[at - 1usize])) {
            // A raw string: `r"..."` or `r#..."..."#...` with as many hashes as opened.
            var hashes = 0usize
            var open_at = at + 1usize
            while open_at < text.len && text[open_at] == 35u8 {
                hashes += 1usize
                open_at += 1usize
            }
            if open_at < text.len && text[open_at] == 34u8 {
                at = open_at + 1usize
                var closed = false
                while at < text.len && !closed {
                    if text[at] == 34u8 {
                        var closes = at + 1usize + hashes <= text.len
                        var hash_at = 0usize
                        while closes && hash_at < hashes {
                            if text[at + 1usize + hash_at] != 35u8 { closes = false }
                            hash_at += 1usize
                        }
                        if closes {
                            at += 1usize + hashes
                            closed = true
                        }
                    }
                    if !closed { at += 1usize }
                }
                continue
            }
        }
        if byte_here == 47u8 && at + 1usize < text.len && text[at + 1usize] == 47u8 {
            var comment_end = at
            while comment_end < text.len && text[comment_end] != 10u8 { comment_end += 1usize }
            ret (at, comment_end)
        }
        at += 1usize
    }
    ret (text.len, text.len)
}

// The bytes `next_comment` stops at, as a table: `"`, `'`, `/` and `r`.
fn comment_scan_bytes() -> str {
    ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
}

// The canonical text (D507, H15): the bytes the key is over, every comment's body
// left out, and its SHA-256 as hex -- what an artifact carries and a key hit is
// verified by when the bytes changed.
fn comment_blind_text(a: *mem.Arena, text: str) -> (str, err) {
    let (storage, storage_error) = mem.alloc[u8](a, text.len)
    if storage_error != ok { ret ("", storage_error) }
    // One copy up to each comment (D931): a line's trailing spaces, tabs and carriage
    // return (D534) are taken back off the copy at its break, where the text was found
    // line by line and walked three times.
    var count = 0usize
    var line_mark = 0usize
    var at = 0usize
    while at < text.len {
        let (comment_at, comment_end) = next_comment(text, at)
        // Line by line up to the comment, each line's bytes copied whole (D933).
        let run = text[at..comment_at]
        var piece_start = 0usize
        while piece_start <= run.len {
            var piece_end = piece_start
            while piece_end < run.len && run[piece_end] != 10u8 { piece_end += 1usize }
            let piece = run[piece_start..piece_end]
            os.copy_bytes(storage[count..count + piece.len], piece)
            count += piece.len
            if piece_end == run.len { break }
            while count > line_mark && (storage[count - 1usize] == 32u8 || storage[count - 1usize] == 9u8 || storage[count - 1usize] == 13u8) { count = count - 1usize }
            storage[count] = 10u8
            count += 1usize
            line_mark = count
            piece_start = piece_end + 1usize
        }
        // The comment's body goes; its line break, if any, is the next copy's first byte.
        at = comment_end
    }
    while count > line_mark && (storage[count - 1usize] == 32u8 || storage[count - 1usize] == 9u8 || storage[count - 1usize] == 13u8) { count = count - 1usize }
    ret (storage[0usize..count], ok)
}

fn canonical_sha256_hex(a: *mem.Arena, text: str) -> (str, err) {
    let checkpoint = mem.mark(a)
    let (stripped, strip_error) = comment_blind_text(a, text)
    if strip_error != ok { ret ("", strip_error) }
    var hex: [64]u8 = zero
    artifact_hash.sha256_hex_into(stripped, hex[..])
    mem.reset(a, checkpoint)
    let (kept, kept_error) = mem.alloc[u8](a, 64usize)
    if kept_error != ok { ret ("", kept_error) }
    var at = 0usize
    while at < 64usize {
        kept[at] = hex[at]
        at += 1usize
    }
    ret (kept[0usize..64usize], ok)
}

// The canonical text's 64-bit key and its SHA-256 as hex, from one stripping of the
// comments (D930): the writer asked for each apart, and stripped every module twice.
fn canonical_digests(a: *mem.Arena, text: str) -> (usize, str, err) {
    let checkpoint = mem.mark(a)
    let (stripped, strip_error) = comment_blind_text(a, text)
    if strip_error != ok { ret (0usize, "", strip_error) }
    let (hash, hash_error) = artifact_hash.xxhash64(stripped)
    if hash_error != ok { ret (0usize, "", hash_error) }
    var hex: [64]u8 = zero
    artifact_hash.sha256_hex_into(stripped, hex[..])
    mem.reset(a, checkpoint)
    let (kept, kept_error) = mem.alloc[u8](a, 64usize)
    if kept_error != ok { ret (0usize, "", kept_error) }
    var at = 0usize
    while at < 64usize {
        kept[at] = hex[at]
        at += 1usize
    }
    ret (hash, kept[0usize..64usize], ok)
}

fn identifier_byte(byte_here: u8) -> bool {
    let named = (byte_here >= 97u8 && byte_here <= 122u8) || (byte_here >= 65u8 && byte_here <= 90u8) || (byte_here >= 48u8 && byte_here <= 57u8) || byte_here == 95u8
    ret named
}

fn write_debug(c: *check.Checker, g: *graph.Graph, module_index: usize, table: *StringTable, scratch: *binary.Buffer, output: *binary.Buffer) -> err {
    if module_index >= g.count { ret InvalidArtifact }
    // Both digests of the canonical text from one stripping of it (D930).
    let (source_hash, canonical, source_hash_error) = canonical_digests(c.arena, g.modules[module_index].text)
    if source_hash_error != ok { ret source_hash_error }
    let (path_index, path_error) = string_index(table, g.modules[module_index].spelling)
    if path_error != ok { ret path_error }
    try binary.little_u32(output, path_index)
    try binary.little_u64(output, source_hash)
    // The compiler's own hash (D398, H15), in what were two reserved words: the
    // driver learned it from its executable, or left zero.
    try binary.little_u64(output, g.compiler_identity)
    // The manifest's digests (D323, format 7): the source's SHA-256 and its
    // interface's, as hex, so a build that does not parse this module still writes
    // its manifest line. Computed here when the module does not carry them yet.
    var sha = g.modules[module_index].sha256
    if sha.len != 64usize {
        let (computed, computed_error) = artifact_hash.sha256_hex(c.arena, g.modules[module_index].text)
        if computed_error != ok { ret computed_error }
        sha = computed
        g.modules[module_index].sha256 = sha
    }
    var interface_sha = g.modules[module_index].interface_sha256
    if interface_sha.len != 64usize {
        let (computed, computed_error) = artifact_hash.interface_sha256_hex(c.arena, g.modules[module_index].text, g.modules[module_index].tokens)
        if computed_error != ok { ret computed_error }
        interface_sha = computed
        g.modules[module_index].interface_sha256 = interface_sha
    }
    try binary.text(output, sha)
    try binary.text(output, interface_sha)
    // The canonical text's digest (D507, H15), after them: a hit on the 64-bit key
    // whose bytes are not the artifact's is verified by it.
    ret binary.text(output, canonical)
}

// The canonical text's digest an artifact carries (D507): empty for one written
// before it, which a key hit over changed bytes cannot verify.
fn artifact_canonical_sha256(bytes: []const u8) -> (str, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret ("", validation_error) }
    let (debug, found_debug, section_error) = find_section_unchecked(bytes, debug_kind())
    if section_error != ok || !found_debug { ret ("", InvalidArtifact) }
    if debug.length < 212usize { ret ("", ok) }
    let start = debug.offset + 148usize
    ret (bytes[start..start + 64usize], ok)
}

// The manifest's digests an artifact carries (D323), as views; empty when it has none.
fn artifact_manifest_digests(bytes: []const u8) -> (str, str, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret ("", "", validation_error) }
    let (debug, found_debug, section_error) = find_section_unchecked(bytes, debug_kind())
    if section_error != ok || !found_debug { ret ("", "", InvalidArtifact) }
    if debug.length < 148usize { ret ("", "", ok) }
    let start = debug.offset + 20usize
    ret (bytes[start..start + 64usize], bytes[start + 64usize..start + 128usize], ok)
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
    var aggregate_marks: [8192]u8 = zero
    var constant_marks: [8192]u8 = zero
    try collect_module_strings(c, g, &no_builder, module_index, strings, aggregate_marks[..], constant_marks[..])
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
    if module_index >= g.count || target_triple.len == 0usize || section_values.len != 11usize || output.count != 0usize { ret InvalidArtifact }
    try reset_strings(strings)
    let (target_index, target_error) = intern(strings, target_triple)
    if target_error != ok { ret target_error }
    var aggregate_marks: [8192]u8 = zero
    var constant_marks: [8192]u8 = zero
    try collect_module_strings(c, g, builder, module_index, strings, aggregate_marks[..], constant_marks[..])
    try collect_line_paths(builder, c, module_index, machine, function_offsets, lines, line_count, strings)
    try collect_vars(builder, c, g, module_index, machine, function_offsets, strings)
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
    try write_dependencies(c, g, builder, module_index, strings, scratch, output, aggregate_marks[..], constant_marks[..])
    try end_section(&writer)
    try begin_section(&writer, code_kind(), required_flag())
    let code_error = write_code(c, g, builder, module_index, strings, machine, function_offsets, relocations, relocation_count, scratch, output)
    if code_error != ok { ret code_error }
    try end_section(&writer)
    try begin_section(&writer, debug_kind(), required_flag())
    try write_debug(c, g, module_index, strings, scratch, output)
    try end_section(&writer)
    try begin_section(&writer, globals_kind(), required_flag())
    try write_globals(builder, c, g, module_index, strings, output)
    try end_section(&writer)
    try begin_section(&writer, lines_kind(), required_flag())
    try write_lines(builder, c, module_index, strings, machine, function_offsets, lines, line_count, output)
    try end_section(&writer)
    try begin_section(&writer, imports_kind(), required_flag())
    try write_imports(g, module_index, strings, output)
    try end_section(&writer)
    // The inventory (D457): its record count, then the manifest's bytes for it.
    try begin_section(&writer, inventory_kind(), required_flag())
    try binary.little_u32(output, g.modules[module_index].inventory_count)
    try binary.copy_bytes(output, g.modules[module_index].inventory)
    try end_section(&writer)
    try begin_section(&writer, emission_kind(), required_flag())
    try write_emission(builder, c, module_index, output)
    try end_section(&writer)
    try begin_section(&writer, vars_kind(), 0usize)
    try write_vars(builder, c, module_index, strings, machine, function_offsets, output)
    try end_section(&writer)
    ret finish(&writer)
}

// (D1582) A type as the Vars section spells it, appended to the builder's descriptor
// text: a primitive by its name (`u32`, `f64`, `bool`, `err`), `str`, `*T` (`*?` for a
// pointer to anything else), `[]T`, `[N]T`; a struct as `{size:n:name` and its field
// count `k:`, then per field `n:name`, its offset, `:` and its type; an enum as
// `=size:n:name` and its member count `k:`, then per member `n:name`, its value (`-`
// before a negative one) and `:`; and any other type -- or a struct or enum nested
// past `depth` 2, which keeps a type that points at itself finite -- as
// `#size:n:name`, a structure of that size. Names carry their length, since a generic
// instance's has brackets and commas. False for a type with no spelling.
//
// A struct is named, not spelled, where a var or a field has it -- `#size:n:module.name`
// -- and its definition is spelled once for the artifact's type table (`definition`
// true). A debugger finds the definition by the name; a name spelled once keeps a
// descriptor short and a type that points at itself finite.
fn spell_type(c: *check.Checker, g: *graph.Graph, ty: check.Type, info: *nir.DebugInfo) -> bool {
    ret spell_type_at(c, g, ty, info, false)
}

fn spell_name(info: *nir.DebugInfo, name: str) -> bool {
    ret spell_number(info, name.len) && spell_text(info, ":") && spell_text(info, name)
}

// `module.name`, its length first: two modules may each have a `Node`.
fn spell_qualified(g: *graph.Graph, info: *nir.DebugInfo, ty: check.Type) -> bool {
    ret spell_qualified_as(g, info, ty, "")
}

// `module.name` with `suffix` after it: a tagged union's `.Tag` and `.Payload`.
fn spell_qualified_as(g: *graph.Graph, info: *nir.DebugInfo, ty: check.Type, suffix: str) -> bool {
    if ty.module_index >= g.count { ret spell_number(info, ty.name.len + suffix.len) && spell_text(info, ":") && spell_text(info, ty.name) && spell_text(info, suffix) }
    let module_name = g.modules[ty.module_index].name
    ret spell_number(info, module_name.len + 1usize + ty.name.len + suffix.len) && spell_text(info, ":") && spell_text(info, module_name) && spell_text(info, ".") && spell_text(info, ty.name) && spell_text(info, suffix)
}

// (D1585) A union's definition, `|size:n:name` and its member count, then per member
// its name, `0:`, its type and `;`; and a tagged union's, a struct of its `tag` -- an
// enum of every member -- and its `payload`, a union of the members that carry one.
fn spell_union(c: *check.Checker, g: *graph.Graph, ty: check.Type, info: *nir.DebugInfo, aggregate: check.Aggregate, size: usize) -> bool {
    var carried = 0usize
    var member_at = 0usize
    while member_at < aggregate.field_count {
        if c.aggregate_fields[aggregate.first_field + member_at].ty.kind != .Void { carried += 1usize }
        member_at += 1usize
    }
    var payload_offset = 0usize
    var payload_size = size
    if aggregate.kind == .TaggedUnion {
        let (tag, tag_error) = check.layout_type_info(c, aggregate.backing_type)
        if tag_error != ok { ret false }
        payload_offset = tag.size
        member_at = 0usize
        while member_at < aggregate.field_count {
            let member = c.aggregate_fields[aggregate.first_field + member_at]
            if member.ty.kind != .Void {
                let (placed, placed_error) = check.layout_field(c, ty, member.name)
                if placed_error != ok { ret false }
                payload_offset = placed.offset
            }
            member_at += 1usize
        }
        if payload_offset > size { ret false }
        payload_size = size - payload_offset
        var fields = 1usize
        if carried != 0usize { fields = 2usize }
        if !(spell_text(info, "{") && spell_number(info, size) && spell_text(info, ":") && spell_qualified(g, info, ty) && spell_number(info, fields) && spell_text(info, ":3:tag0:=") && spell_number(info, tag.size) && spell_text(info, ":") && spell_qualified_as(g, info, ty, ".Tag") && spell_number(info, aggregate.field_count) && spell_text(info, ":")) { ret false }
        member_at = 0usize
        while member_at < aggregate.field_count {
            let member = c.aggregate_fields[aggregate.first_field + member_at]
            if !(spell_name(info, member.name) && (!member.enum_negative || spell_text(info, "-")) && spell_number(info, member.enum_value) && spell_text(info, ":")) { ret false }
            member_at += 1usize
        }
        if !spell_text(info, ";") { ret false }
        if carried == 0usize { ret true }
        if !(spell_text(info, "0:") && spell_number(info, payload_offset) && spell_text(info, ":|") && spell_number(info, payload_size) && spell_text(info, ":") && spell_qualified_as(g, info, ty, ".Payload")) { ret false }
    } else {
        if !(spell_text(info, "|") && spell_number(info, size) && spell_text(info, ":") && spell_qualified(g, info, ty)) { ret false }
    }
    if !(spell_number(info, carried) && spell_text(info, ":")) { ret false }
    member_at = 0usize
    while member_at < aggregate.field_count {
        let member = c.aggregate_fields[aggregate.first_field + member_at]
        if member.ty.kind != .Void {
            if !(spell_name(info, member.name) && spell_text(info, "0:") && spell_type_at(c, g, member.ty, info, false) && spell_text(info, ";")) { ret false }
        }
        member_at += 1usize
    }
    if aggregate.kind == .TaggedUnion { ret spell_text(info, ";") }
    ret true
}

// A struct a descriptor names, to be defined: each once.
fn want_definition(info: *nir.DebugInfo, ty: check.Type) {
    var at = 0usize
    while at < info.wanted_count {
        if info.wanted[at].module_index == ty.module_index && check.same(info.wanted[at].name, ty.name) { ret }
        at += 1usize
    }
    if info.wanted_count < info.wanted.len {
        info.wanted[info.wanted_count] = ty
        info.wanted_count += 1usize
    }
}

fn spell_type_at(c: *check.Checker, g: *graph.Graph, ty: check.Type, info: *nir.DebugInfo, definition: bool) -> bool {
    if ty.kind == .Bool { ret spell_text(info, "bool") }
    if ty.kind == .Err { ret spell_text(info, "err") }
    if ty.kind == .Integer || ty.kind == .Float { ret spell_text(info, ty.name) }
    if ty.kind == .String { ret spell_text(info, "str") }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if ty.kind == .Pointer && !spell_text(info, "*") { ret false }
        if ty.kind == .Slice && !spell_text(info, "[]") { ret false }
        if ty.kind == .Array {
            if !ty.has_length || !spell_text(info, "[") || !spell_number(info, ty.array_length) || !spell_text(info, "]") { ret false }
        }
        if !ty.has_element || ty.element >= c.types.len { ret ty.kind == .Pointer && spell_text(info, "?") }
        let mark = info.text_count
        if spell_type_at(c, g, c.types[ty.element], info, false) { ret true }
        info.text_count = mark
        ret ty.kind == .Pointer && spell_text(info, "?")
    }
    if ty.kind == .Named || ty.kind == .Tag {
        let (layout, layout_error) = check.layout_type_info(c, ty)
        if layout_error != ok { ret false }
        let (aggregate_index, is_aggregate) = check.layout_aggregate_index(c, ty)
        if is_aggregate && aggregate_index < c.aggregate_count {
            let aggregate = c.aggregates[aggregate_index]
            let mark = info.text_count
            if aggregate.kind == .Struct && definition {
                if spell_text(info, "{") && spell_number(info, layout.size) && spell_text(info, ":") && spell_qualified(g, info, ty) && spell_number(info, aggregate.field_count) && spell_text(info, ":") {
                    var field_at = 0usize
                    var spelled = true
                    while field_at < aggregate.field_count && spelled {
                        let field = c.aggregate_fields[aggregate.first_field + field_at]
                        let (placed, placed_error) = check.layout_field(c, ty, field.name)
                        spelled = placed_error == ok && spell_name(info, field.name) && spell_number(info, placed.offset) && spell_text(info, ":") && spell_type_at(c, g, placed.ty, info, false) && spell_text(info, ";")
                        field_at += 1usize
                    }
                    if spelled { ret true }
                }
                info.text_count = mark
                ret false
            }
            if (aggregate.kind == .Union || aggregate.kind == .TaggedUnion) && definition {
                if spell_union(c, g, ty, info, aggregate, layout.size) { ret true }
                info.text_count = mark
                ret false
            }
            if aggregate.kind == .Struct || aggregate.kind == .Union || aggregate.kind == .TaggedUnion { want_definition(info, ty) }
            // A union is named as one: a debugger finds a union's definition by a union's name.
            if aggregate.kind == .Union { ret spell_text(info, "%") && spell_number(info, layout.size) && spell_text(info, ":") && spell_qualified(g, info, ty) }
            if aggregate.kind == .Enum {
                if spell_text(info, "=") && spell_number(info, layout.size) && spell_text(info, ":") && spell_qualified(g, info, ty) && spell_number(info, aggregate.field_count) && spell_text(info, ":") {
                    var member_at = 0usize
                    var spelled = true
                    while member_at < aggregate.field_count && spelled {
                        let member = c.aggregate_fields[aggregate.first_field + member_at]
                        spelled = spell_name(info, member.name) && (!member.enum_negative || spell_text(info, "-")) && spell_number(info, member.enum_value) && spell_text(info, ":")
                        member_at += 1usize
                    }
                    if spelled { ret true }
                }
                info.text_count = mark
            }
        }
        ret spell_text(info, "#") && spell_number(info, layout.size) && spell_text(info, ":") && spell_qualified(g, info, ty)
    }
    ret false
}

// (D1582) The type table a reused function's vars refer into: the previous artifact's
// definitions, taken whole ahead of this one's.
fn inherit_definitions(bytes: []const u8, strings: Section, info: *nir.DebugInfo) -> bool {
    let (first, count, found) = vars_definitions(bytes)
    if !found { ret true }
    var at = 0usize
    while at < count && info.definition_count < info.definitions.len {
        let (start, length, bounds_error) = string_bounds_in(bytes, strings, binary.read_u32_at(bytes, first + at * 4usize))
        if bounds_error != ok { ret false }
        info.definitions[info.definition_count] = bytes[start..start + length]
        info.definition_count += 1usize
        at += 1usize
    }
    info.inherited = info.definition_count
    ret true
}

// Where the Vars section's type table is: after the functions' records, a count and a
// string index per definition.
fn vars_definitions(bytes: []const u8) -> (usize, usize, bool) {
    let (section, found, section_error) = find_section_unchecked(bytes, vars_kind())
    if section_error != ok || !found || section.length < 4usize { ret (0usize, 0usize, false) }
    let end = section.offset + section.length
    let function_count = binary.read_u32_at(bytes, section.offset)
    var cursor = section.offset + 4usize
    var at = 0usize
    while at < function_count {
        if cursor > end || 4usize > end - cursor { ret (0usize, 0usize, false) }
        let var_count = binary.read_u32_at(bytes, cursor)
        cursor += 4usize
        if var_count > (end - cursor) / var_record_size() { ret (0usize, 0usize, false) }
        cursor += var_count * var_record_size()
        at += 1usize
    }
    if cursor > end || 4usize > end - cursor { ret (0usize, 0usize, false) }
    let count = binary.read_u32_at(bytes, cursor)
    if count > (end - cursor - 4usize) / 4usize { ret (0usize, 0usize, false) }
    ret (cursor + 4usize, count, true)
}

fn spell_text(info: *nir.DebugInfo, text: str) -> bool {
    if info.text_count + text.len > info.text.len { ret false }
    os.copy_bytes(info.text[info.text_count..info.text_count + text.len], text)
    info.text_count += text.len
    ret true
}

fn spell_number(info: *nir.DebugInfo, value: usize) -> bool {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = value
    while count == 0usize || rest != 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        count += 1usize
    }
    if info.text_count + count > info.text.len { ret false }
    var at = 0usize
    while at < count {
        info.text[info.text_count + at] = digits[count - 1usize - at]
        at += 1usize
    }
    info.text_count += count
    ret true
}

// The first placed var of the function starting at `start` in the machine buffer, and
// how many: selection placed them in code order.
fn vars_of(builder: *nir.Builder, start: usize) -> (usize, usize) {
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

// Each var's name and descriptor interned, a fresh one's type spelled first; a var
// whose type has no spelling is left out (`kind` zero).
fn collect_vars(builder: *nir.Builder, c: *check.Checker, g: *graph.Graph, module_index: usize, machine: *emit_x64.Buffer, function_offsets: []usize, table: *StringTable) -> err {
    builder.debug.text_count = 0usize
    builder.debug.wanted_count = 0usize
    builder.debug.definition_count = builder.debug.inherited
    var inherited_at = 0usize
    while inherited_at < builder.debug.inherited {
        let (inherited_index, inherited_error) = intern(table, builder.debug.definitions[inherited_at])
        if inherited_error != ok { ret inherited_error }
        inherited_at += 1usize
    }
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index && function_at < function_offsets.len {
            let (first, count) = vars_of(builder, function_offsets[function_at])
            var at = first
            while at < first + count {
                // A saved register's record (`kind` 4) names no local and has no type.
                if builder.debug.vars[at].descriptor.len == 0usize && builder.debug.vars[at].kind != 4usize {
                    let mark = builder.debug.text_count
                    if spell_type(c, g, builder.debug.vars[at].ty, &builder.debug) {
                        let spelled = builder.debug.text[mark..builder.debug.text_count]
                        let known = table.count
                        let (spelled_index, spelled_error) = intern(table, spelled)
                        if spelled_error != ok { ret spelled_error }
                        // Spelled before: the table keeps the first copy, and the text goes back.
                        if table.count == known {
                            builder.debug.text_count = mark
                            builder.debug.vars[at].descriptor = table.values[spelled_index]
                        } else {
                            builder.debug.vars[at].descriptor = spelled
                        }
                    } else {
                        builder.debug.text_count = mark
                        builder.debug.vars[at].kind = 0usize
                    }
                }
                if builder.debug.vars[at].kind != 0usize {
                    let (descriptor_index, descriptor_error) = intern(table, builder.debug.vars[at].descriptor)
                    if descriptor_error != ok { ret descriptor_error }
                    let (name_index, name_error) = intern(table, builder.debug.vars[at].name)
                    if name_error != ok { ret name_error }
                }
                at += 1usize
            }
        }
        function_at += 1usize
    }
    // The structs the descriptors named, each defined once; a definition names more,
    // which join the list behind it. One the reused functions' table already has is not
    // spelled again.
    var wanted_at = 0usize
    while wanted_at < builder.debug.wanted_count && builder.debug.definition_count < builder.debug.definitions.len {
        let mark = builder.debug.text_count
        if spell_type_at(c, g, builder.debug.wanted[wanted_at], &builder.debug, true) {
            let spelled = builder.debug.text[mark..builder.debug.text_count]
            let known = table.count
            let (spelled_index, spelled_error) = intern(table, spelled)
            if spelled_error != ok { ret spelled_error }
            if table.count == known {
                builder.debug.text_count = mark
                var defined = false
                var defined_at = 0usize
                while defined_at < builder.debug.definition_count && !defined {
                    defined = check.same(builder.debug.definitions[defined_at], table.values[spelled_index])
                    defined_at += 1usize
                }
                if !defined {
                    builder.debug.definitions[builder.debug.definition_count] = table.values[spelled_index]
                    builder.debug.definition_count += 1usize
                }
            } else {
                builder.debug.definitions[builder.debug.definition_count] = spelled
                builder.debug.definition_count += 1usize
            }
        } else {
            builder.debug.text_count = mark
        }
        wanted_at += 1usize
    }
    ret ok
}

fn write_vars(builder: *nir.Builder, c: *check.Checker, module_index: usize, table: *StringTable, machine: *emit_x64.Buffer, function_offsets: []usize, output: *binary.Buffer) -> err {
    try binary.little_u32(output, module_nir_function_count(builder, c, module_index))
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            if function_at >= function_offsets.len { ret InvalidArtifact }
            let start = function_offsets[function_at]
            let (first, count) = vars_of(builder, start)
            var written = 0usize
            var at = first
            while at < first + count {
                if builder.debug.vars[at].kind != 0usize { written += 1usize }
                at += 1usize
            }
            try binary.little_u32(output, written)
            at = first
            while at < first + count {
                let placed = builder.debug.vars[at]
                if placed.kind != 0usize {
                    let (name_index, name_error) = string_index(table, placed.name)
                    if name_error != ok { ret name_error }
                    let (descriptor_index, descriptor_error) = string_index(table, placed.descriptor)
                    if descriptor_error != ok { ret descriptor_error }
                    try binary.little_u32(output, placed.start - start)
                    try binary.little_u32(output, placed.end - start)
                    try binary.little_u32(output, name_index)
                    try binary.little_u32(output, descriptor_index)
                    try binary.little_u32(output, placed.parameter)
                    try binary.little_u32(output, placed.kind + placed.register * 256usize)
                    try binary.little_u32(output, placed.displacement % 4294967296usize)
                    try binary.little_u32(output, placed.scope_start - start)
                    try binary.little_u32(output, placed.scope_end - start)
                }
                at += 1usize
            }
        }
        function_at += 1usize
    }
    // The type table.
    try binary.little_u32(output, builder.debug.definition_count)
    var definition_at = 0usize
    while definition_at < builder.debug.definition_count {
        let (definition_index, definition_error) = string_index(table, builder.debug.definitions[definition_at])
        if definition_error != ok { ret definition_error }
        try binary.little_u32(output, definition_index)
        definition_at += 1usize
    }
    ret ok
}

// The Vars records of every code function, located once like the lines (D1582): an
// artifact without the section has none, which is not an error.
fn code_vars_index(bytes: []const u8, count: usize, starts: []usize, counts: []usize) -> err {
    let (section, found, section_error) = find_section_unchecked(bytes, vars_kind())
    if section_error != ok || starts.len < count || counts.len < count { ret InvalidArtifact }
    var at = 0usize
    if !found {
        while at < count {
            starts[at] = 0usize
            counts[at] = 0usize
            at += 1usize
        }
        ret ok
    }
    if section.length < 4usize { ret InvalidArtifact }
    let (function_count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || function_count != count { ret InvalidArtifact }
    let end = section.offset + section.length
    var cursor = section.offset + 4usize
    while at < count {
        if cursor > end || 4usize > end - cursor { ret InvalidArtifact }
        let var_count = binary.read_u32_at(bytes, cursor)
        cursor += 4usize
        if var_count > (end - cursor) / var_record_size() { ret InvalidArtifact }
        starts[at] = cursor
        counts[at] = var_count
        cursor += var_count * var_record_size()
        at += 1usize
    }
    ret ok
}

// One Vars record at `record`, placed in a function starting at `start`: the name and
// descriptor read from the artifact's own strings.
fn read_var(bytes: []const u8, strings: Section, record: usize, start: usize) -> (nir.DebugVar, err) {
    var placed: nir.DebugVar = zero
    let (name_start, name_length, name_error) = string_bounds_in(bytes, strings, binary.read_u32_at(bytes, record + 8usize))
    if name_error != ok { ret (placed, name_error) }
    let (descriptor_start, descriptor_length, descriptor_error) = string_bounds_in(bytes, strings, binary.read_u32_at(bytes, record + 12usize))
    if descriptor_error != ok { ret (placed, descriptor_error) }
    let name = bytes[name_start..name_start + name_length]
    let descriptor = bytes[descriptor_start..descriptor_start + descriptor_length]
    let location = binary.read_u32_at(bytes, record + 20usize)
    var displacement = binary.read_u32_at(bytes, record + 24usize)
    if displacement >= 2147483648usize { displacement = displacement -% 4294967296usize }
    placed.function_start = start
    placed.start = start + binary.read_u32_at(bytes, record)
    placed.end = start + binary.read_u32_at(bytes, record + 4usize)
    placed.name = name
    placed.descriptor = descriptor
    placed.parameter = binary.read_u32_at(bytes, record + 16usize)
    placed.kind = location % 256usize
    placed.register = location / 256usize
    placed.displacement = displacement
    placed.scope_start = start + binary.read_u32_at(bytes, record + 28usize)
    placed.scope_end = start + binary.read_u32_at(bytes, record + 32usize)
    ret (placed, ok)
}

// (D1515) The Emission section: the count, then per code function its emission
// identity -- zero when it has none -- and, for a trap stub, its operand moves.
fn write_emission(builder: *nir.Builder, c: *check.Checker, module_index: usize, output: *binary.Buffer) -> err {
    try binary.little_u32(output, module_nir_function_count(builder, c, module_index))
    try binary.little_u32(output, 0usize)
    let (nir_first, nir_end) = span_of(c, span_nir(), module_index)
    var function_at = nir_first
    while function_at < nir_end {
        if builder.functions[function_at].module_index == module_index {
            var identity = 0usize
            if function_at >= builder.emission_first && function_at < builder.emission_end && function_at < builder.emission.len { identity = builder.emission[function_at] }
            var moves = 0usize
            let function = builder.functions[function_at]
            if function.instruction_count == 1usize && builder.instructions[function.first_instruction].opcode == .TrapStub { moves = builder.instructions[function.first_instruction].immediate }
            try binary.little_u64(output, identity)
            try binary.little_u64(output, moves)
        }
        function_at += 1usize
    }
    ret ok
}

// (D1515) What instruction selection reads of one function, hashed: its canonical
// NIR (D203), and what that leaves out -- each instruction's line, column, path and
// inline origin, a callee's import binding -- with the function's own names, path
// and the build's selection settings. Two functions with one identity select to
// the same bytes, relocations and line rows.
fn emission_hash(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, function_index: usize, scratch: *binary.Buffer) -> (usize, err) {
    if function_index >= builder.function_count { ret (0usize, InvalidArtifact) }
    let function = builder.functions[function_index]
    scratch.count = 0usize
    let prefix_error = emission_prefix(builder, function, scratch)
    if prefix_error != ok { ret (0usize, prefix_error) }
    let nir_error = write_nir_canonical(c, g, builder, function_index, scratch)
    if nir_error != ok { ret (0usize, nir_error) }
    // An inline origin indexes the module's table of inlined bodies, which an edit to
    // an earlier function shifts; selection only compares two origins, so each is
    // taken from the function's least (D1516).
    var origin_base = 0usize
    var at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        let origin = usize(builder.instructions[at].inline_origin)
        if origin != 0usize && (origin_base == 0usize || origin < origin_base) { origin_base = origin }
        at += 1usize
    }
    at = function.first_instruction
    while at < function.first_instruction + function.instruction_count {
        let instruction = builder.instructions[at]
        let site_error = emission_site(builder, instruction, origin_base, scratch)
        if site_error != ok { ret (0usize, site_error) }
        at += 1usize
    }
    // (D1582) The named locals selection places: a renamed local selects the same
    // code, and its record must not carry the old name.
    let (debug_first, debug_count) = nir.debug_locals_of(builder, function.first_instruction)
    var debug_at = debug_first
    while debug_at < debug_first + debug_count {
        let local = builder.debug.locals[debug_at]
        var flags = local.parameter * 2usize
        if local.address { flags += 1usize }
        // The scope from the function's start: selection places it.
        var scope_start = 0usize
        var scope_end = 0usize
        if local.scope_start >= function.first_instruction { scope_start = local.scope_start - function.first_instruction }
        if local.scope_end >= function.first_instruction { scope_end = local.scope_end - function.first_instruction }
        if canonical_text(scratch, local.name) != ok || binary.little_u32(scratch, local.value) != ok || binary.little_u32(scratch, flags) != ok || binary.little_u32(scratch, scope_start) != ok || binary.little_u32(scratch, scope_end) != ok { ret (0usize, binary.Capacity) }
        debug_at += 1usize
    }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    // Zero stands for none.
    if hash == 0usize { ret (1usize, hash_error) }
    ret (hash, hash_error)
}

fn emission_prefix(builder: *nir.Builder, function: nir.Function, scratch: *binary.Buffer) -> err {
    try canonical_text(scratch, function.module_name)
    try canonical_text(scratch, function.name)
    try binary.little_u32(scratch, function.instance)
    try canonical_text(scratch, function.path)
    var release = 0usize
    if builder.release { release = 1usize }
    try binary.byte(scratch, release)
    ret binary.little_u32(scratch, builder.cpu_level)
}

fn emission_site(builder: *nir.Builder, instruction: nir.Instruction, origin_base: usize, scratch: *binary.Buffer) -> err {
    try binary.little_u32(scratch, instruction.site.line)
    try binary.little_u32(scratch, instruction.site.column)
    var origin = usize(instruction.inline_origin)
    if origin != 0usize { origin = origin - origin_base + 1usize }
    try binary.little_u32(scratch, origin)
    try canonical_text(scratch, instruction.path)
    if (instruction.opcode == .Call || instruction.opcode == .FunctionAddress) && instruction.immediate < builder.function_ref_count {
        let reference = builder.function_refs[instruction.immediate]
        try canonical_text(scratch, reference.library)
        try canonical_text(scratch, reference.symbol)
    }
    ret ok
}

// (D1515) A validated artifact's Emission section: how many records, and where the
// first starts; none when the section is absent or its count is not the Code's.
fn emission_records(bytes: []const u8, code_count: usize) -> (usize, bool) {
    let (section, found, section_error) = find_section_unchecked(bytes, emission_kind())
    if section_error != ok || !found || section.length < 8usize { ret (0usize, false) }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || count != code_count || section.length != 8usize + count * emission_record_size() { ret (0usize, false) }
    ret (section.offset + 8usize, true)
}

// (D1515) Where each code function's line rows start in a validated artifact, and
// how many, in one pass over the Lines section: rows of three words each.
fn code_lines_index(bytes: []const u8, count: usize, starts: []usize, counts: []usize) -> err {
    let (section, found, section_error) = find_section_unchecked(bytes, lines_kind())
    if section_error != ok || !found || section.length < 4usize || starts.len < count || counts.len < count { ret InvalidArtifact }
    let (function_count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || function_count != count { ret InvalidArtifact }
    let end = section.offset + section.length
    var cursor = section.offset + 4usize
    var at = 0usize
    while at < count {
        if cursor > end || 4usize > end - cursor { ret InvalidArtifact }
        let row_count = binary.read_u32_at(bytes, cursor)
        cursor += 4usize
        if row_count > (end - cursor) / 12usize { ret InvalidArtifact }
        starts[at] = cursor
        counts[at] = row_count
        cursor += row_count * 12usize
        at += 1usize
    }
    ret ok
}

// One record of the Emission section at `first`: the identity and the moves.
fn emission_at(bytes: []const u8, first: usize, index: usize) -> (usize, usize) {
    let record = first + index * emission_record_size()
    let identity = binary.read_u32_at(bytes, record) | (binary.read_u32_at(bytes, record + 4usize) << 32usize)
    ret (identity, binary.read_u32_at(bytes, record + 8usize))
}

// The Inventory section read (D457): the count and the bytes, or nothing for an
// artifact without one.
fn artifact_inventory(bytes: []const u8) -> ([]const u8, usize, bool, err) {
    var none: []const u8 = zero
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (none, 0usize, false, validation_error) }
    let (section, found, section_error) = find_section_unchecked(bytes, inventory_kind())
    if section_error != ok { ret (none, 0usize, false, section_error) }
    if !found { ret (none, 0usize, false, ok) }
    if section.length < 4usize { ret (none, 0usize, false, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok { ret (none, 0usize, false, InvalidArtifact) }
    ret (bytes[section.offset + 4usize..section.offset + section.length], count, true, ok)
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
        let (start, length, bounds_error) = string_bounds_in(bytes, strings, at)
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
    let (start, length, bounds_error) = string_bounds_in(bytes, strings, index)
    ret (start, length, bounds_error)
}

// The string section, for a reader that asks for many strings of one artifact (D332):
// `string_bounds` found it again per string.
fn strings_section(bytes: []const u8) -> (Section, err) {
    let (strings, found_strings, section_error) = find_section_unchecked(bytes, strings_kind())
    if section_error != ok || !found_strings || strings.length < 4usize { ret (strings, InvalidArtifact) }
    ret (strings, ok)
}

fn string_bounds_in(bytes: []const u8, strings: Section, index: usize) -> (usize, usize, err) {
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
        let (start, length, bounds_error) = string_bounds_in(bytes, strings, at)
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

// The relocation's words alone (D324): the linker holds every artifact's string bounds
// and checks the indexes against them, so the two table walks per relocation this
// reader's checked form makes are not made twice.
fn code_relocation_raw(bytes: []const u8, function: CodeFunction, index: usize) -> (CodeRelocation, err) {
    var empty: CodeRelocation = zero
    if index >= function.relocation_count { ret (empty, InvalidArtifact) }
    let relocation = function.relocations + index * relocation_record_size()
    if relocation > bytes.len || relocation_record_size() > bytes.len - relocation { ret (empty, InvalidArtifact) }
    var record: CodeRelocation = zero
    record.displacement_at = binary.read_u32_at(bytes, relocation)
    record.module_index = binary.read_u32_at(bytes, relocation + 4usize)
    record.name_index = binary.read_u32_at(bytes, relocation + 8usize)
    record.instance = binary.read_u32_at(bytes, relocation + 12usize)
    let kind = binary.read_u32_at(bytes, relocation + 16usize)
    record.global = kind == 1usize
    record.imported = kind == 2usize
    record.library_index = binary.read_u32_at(bytes, relocation + 20usize)
    record.symbol_index = binary.read_u32_at(bytes, relocation + 24usize)
    ret (record, ok)
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
    let (record, record_error) = global_record_from(bytes, section.offset + 4usize + index * global_record_size())
    ret (record, record_error)
}

// One Globals record at its offset, unvalidated beyond itself (the D1514 decode
// reads every record of an artifact already validated once).
fn global_record_from(bytes: []const u8, record: usize) -> (GlobalRecord, err) {
    let empty = GlobalRecord { name_index: 0usize, size: 0usize, alignment: 0usize, has_initial: false, initial: 0usize }
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

// The content hash over the function's code and relocations, with the string table's
// bounds in hand (D324): the checked form below read every relocation twice, each
// through two walks of the string table, and the link verifies every function it emits.
fn code_content_hash_bounded(bytes: []const u8, function: CodeFunction, starts: []const usize, lengths: []const usize, scratch: *binary.Buffer) -> (usize, err) {
    if function.code_start > bytes.len || function.code_length > bytes.len - function.code_start { ret (0usize, InvalidArtifact) }
    scratch.count = 0usize
    let e1 = binary.little_u32(scratch, function.code_length)
    if e1 != ok { ret (0usize, e1) }
    let e2 = binary.copy(scratch, bytes[function.code_start..function.code_start + function.code_length])
    if e2 != ok { ret (0usize, e2) }
    let e3 = binary.little_u32(scratch, function.relocation_count)
    if e3 != ok { ret (0usize, e3) }
    var relocation_at = 0usize
    while relocation_at < function.relocation_count {
        let (relocation, relocation_error) = code_relocation_raw(bytes, function, relocation_at)
        if relocation_error != ok { ret (0usize, relocation_error) }
        if relocation.module_index >= starts.len || relocation.name_index >= starts.len { ret (0usize, InvalidArtifact) }
        let r1 = binary.little_u32(scratch, relocation.displacement_at)
        if r1 != ok { ret (0usize, r1) }
        var kind = 0usize
        if relocation.global { kind = 1usize }
        let r2 = binary.byte(scratch, kind)
        if r2 != ok { ret (0usize, r2) }
        let module_start = starts[relocation.module_index]
        let module_length = lengths[relocation.module_index]
        let name_start = starts[relocation.name_index]
        let name_length = lengths[relocation.name_index]
        if module_length == 0usize || name_length == 0usize || module_start + module_length > bytes.len || name_start + name_length > bytes.len { ret (0usize, InvalidArtifact) }
        let r3 = binary.little_u32(scratch, module_length)
        if r3 != ok { ret (0usize, r3) }
        let r4 = binary.copy(scratch, bytes[module_start..module_start + module_length])
        if r4 != ok { ret (0usize, r4) }
        let r5 = binary.little_u32(scratch, name_length)
        if r5 != ok { ret (0usize, r5) }
        let r6 = binary.copy(scratch, bytes[name_start..name_start + name_length])
        if r6 != ok { ret (0usize, r6) }
        let r7 = binary.little_u32(scratch, relocation.instance)
        if r7 != ok { ret (0usize, r7) }
        relocation_at += 1usize
    }
    let (hash, hash_error) = artifact_hash.xxhash64(scratch.bytes[0usize..scratch.count])
    ret (hash, hash_error)
}

// The Code section's count in one read (D324), for a caller that reads every record
// after and checks what it uses; `artifact_code_count` walks and checks them all.
fn artifact_code_count_light(bytes: []const u8) -> (usize, err) {
    let (code, found_code, section_error) = find_section_unchecked(bytes, code_kind())
    if section_error != ok || !found_code || code.length < 4usize { ret (0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, code.offset)
    if count_error != ok || count > (code.length - 4usize) / 24usize { ret (0usize, InvalidArtifact) }
    ret (count, ok)
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
    let (deps, strings, open_error) = dependencies_open(bytes)
    if open_error != ok { ret (empty, open_error) }
    let (dependency, read_error) = dependency_in(bytes, deps, strings, index)
    ret (dependency, read_error)
}

// The Deps and string sections of a validated artifact, found once for a walk over
// its edges (D332): `dependency_at` validated the layout and found both per edge, and
// the hot build walks every edge of every kept module to a fixed point.
fn dependencies_open(bytes: []const u8) -> (Section, Section, err) {
    let empty = Section { kind: 0usize, flags: 0usize, offset: 0usize, length: 0usize }
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (empty, empty, validation_error) }
    let (deps, found_deps, section_error) = find_section_unchecked(bytes, deps_kind())
    if section_error != ok || !found_deps || deps.length < 4usize { ret (empty, empty, InvalidArtifact) }
    let (strings, strings_error) = strings_section(bytes)
    if strings_error != ok { ret (empty, empty, strings_error) }
    ret (deps, strings, ok)
}

fn dependency_in(bytes: []const u8, deps: Section, strings: Section, index: usize) -> (Dependency, err) {
    let empty = Dependency { kind: 0usize, module_index: 0usize, name_index: 0usize, hash: 0usize }
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
    let (module_start, module_length, module_bounds_error) = string_bounds_in(bytes, strings, module_index)
    let (name_start, name_length, name_bounds_error) = string_bounds_in(bytes, strings, name_index)
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

// The compiler hash the Debug section carries (D398): zero in an artifact written
// before the field or by a compiler that could not read itself.
fn artifact_compiler_hash(bytes: []const u8) -> (usize, err) {
    let validation_error = check_layout(bytes)
    if validation_error != ok { ret (0usize, validation_error) }
    let (debug, found_debug, section_error) = find_section_unchecked(bytes, debug_kind())
    if section_error != ok || !found_debug || debug.length < 20usize { ret (0usize, InvalidArtifact) }
    let (hash, hash_error) = binary.read_u64(bytes, debug.offset + 12usize)
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

// (D1325, C036) The Interface's typed payload read back. Where one type the writer
// encoded (`write_type_indexed`) ends: its 20-byte head, then a pointer's, slice's
// or array's element when its flags say it has one, or a function type's
// parameters and returns; a kind or flag the writer never uses, a record cut short
// or a nesting deeper than 64 is refused.
fn interface_type_end(bytes: []const u8, cursor: usize, end: usize, depth: usize) -> (usize, err) {
    if depth > 64usize || cursor > end || end > bytes.len || end - cursor < 20usize { ret (0usize, InvalidArtifact) }
    let kind = usize(bytes[cursor])
    let flags = usize(bytes[cursor + 1usize])
    if kind == 0usize || kind > 16usize || flags > 31usize { ret (0usize, InvalidArtifact) }
    var next = cursor + 20usize
    if (kind == 9usize || kind == 10usize || kind == 11usize) && (flags & 2usize) != 0usize {
        let (element_end, element_error) = interface_type_end(bytes, next, end, depth + 1usize)
        ret (element_end, element_error)
    }
    if kind == 16usize {
        if end - next < 8usize { ret (0usize, InvalidArtifact) }
        let (parameters, parameters_error) = binary.read_u32(bytes, next)
        let (results, results_error) = binary.read_u32(bytes, next + 4usize)
        if parameters_error != ok || results_error != ok { ret (0usize, InvalidArtifact) }
        next += 8usize
        var at = 0usize
        while at < parameters + results {
            let (after, after_error) = interface_type_end(bytes, next, end, depth + 1usize)
            if after_error != ok { ret (0usize, after_error) }
            next = after
            at += 1usize
        }
    }
    ret (next, ok)
}

// (D1325) Past `count` bytes from `cursor`, or refused when the record is shorter.
fn interface_skip(cursor: usize, end: usize, count: usize) -> (usize, err) {
    if cursor > end || end - cursor < count { ret (0usize, InvalidArtifact) }
    ret (cursor + count, ok)
}

// (D1325) A u32 count at `cursor`, and the cursor past it.
fn interface_count(bytes: []const u8, cursor: usize, end: usize) -> (usize, usize, err) {
    if cursor > end || end - cursor < 4usize { ret (0usize, 0usize, InvalidArtifact) }
    let (value, value_error) = binary.read_u32(bytes, cursor)
    if value_error != ok { ret (0usize, 0usize, InvalidArtifact) }
    ret (value, cursor + 4usize, ok)
}

// (D1325) Past a function's or aggregate's comptime parameters: the count, then
// each a kind byte, three zeroes and a name, an integer's, array's or function's
// parameter with its type.
fn interface_comptime_end(bytes: []const u8, cursor: usize, end: usize) -> (usize, err) {
    let (count, first, count_error) = interface_count(bytes, cursor, end)
    if count_error != ok { ret (0usize, count_error) }
    var next = first
    var at = 0usize
    while at < count {
        if next > end || end - next < 8usize { ret (0usize, InvalidArtifact) }
        let kind = usize(bytes[next])
        if kind == 0usize || kind > 7usize { ret (0usize, InvalidArtifact) }
        next += 8usize
        if kind == 2usize || kind == 6usize || kind == 7usize {
            let (typed, typed_error) = interface_type_end(bytes, next, end, 0usize)
            if typed_error != ok { ret (0usize, typed_error) }
            next = typed
        }
        at += 1usize
    }
    ret (next, ok)
}

// (D1325) Where a declaration's typed payload ends, read from its kind: past the
// name and the two hashes, a function's borrow source, no-escape positions,
// comptime parameters, parameters and returns; an aggregate's kind, comptime
// parameters, backing type and fields; an alias's resolved type; a constant's type
// and value; an error's qualified value.
fn interface_payload_end(bytes: []const u8, kind: usize, payload: usize, end: usize) -> (usize, err) {
    let (named, named_error) = interface_skip(payload, end, 20usize)
    if named_error != ok { ret (0usize, named_error) }
    var next = named
    if kind == declaration_function_kind() {
        let (borrowed, borrowed_error) = interface_skip(next, end, 4usize)
        if borrowed_error != ok { ret (0usize, borrowed_error) }
        let (noescapes, positions, noescape_error) = interface_count(bytes, borrowed, end)
        if noescape_error != ok || noescapes > (end - positions) / 4usize { ret (0usize, InvalidArtifact) }
        let (comptimes_end, comptime_error) = interface_comptime_end(bytes, positions + 4usize * noescapes, end)
        if comptime_error != ok { ret (0usize, comptime_error) }
        let (parameters, parameter_first, parameters_error) = interface_count(bytes, comptimes_end, end)
        if parameters_error != ok { ret (0usize, parameters_error) }
        next = parameter_first
        var at = 0usize
        while at < parameters {
            let (after_name, name_error) = interface_skip(next, end, 4usize)
            if name_error != ok { ret (0usize, name_error) }
            let (after, after_error) = interface_type_end(bytes, after_name, end, 0usize)
            if after_error != ok { ret (0usize, after_error) }
            next = after
            at += 1usize
        }
        let (results, result_first, results_error) = interface_count(bytes, next, end)
        if results_error != ok { ret (0usize, results_error) }
        next = result_first
        at = 0usize
        while at < results {
            let (after, after_error) = interface_type_end(bytes, next, end, 0usize)
            if after_error != ok { ret (0usize, after_error) }
            next = after
            at += 1usize
        }
        // (D1510) The attribute tail: 20 bytes (D1589) and one `own` byte a parameter.
        // Its first byte's known bits are intrinsic 1, variadic 2, gpu 4, device-only 8
        // (D1677) and `@cc` 16 (D1676).
        if next > end || end - next < 20usize || (usize(bytes[next]) & 224usize) != 0usize { ret (0usize, InvalidArtifact) }
        next += 20usize
        if parameters > end - next { ret (0usize, InvalidArtifact) }
        at = 0usize
        while at < parameters {
            if usize(bytes[next + at]) > 1usize { ret (0usize, InvalidArtifact) }
            at += 1usize
        }
        ret (next + parameters, ok)
    }
    if kind == declaration_aggregate_kind() {
        if next > end || end - next < 4usize || usize(bytes[next]) == 0usize || usize(bytes[next]) > 4usize { ret (0usize, InvalidArtifact) }
        let (comptimes_end, comptime_error) = interface_comptime_end(bytes, next + 4usize, end)
        if comptime_error != ok { ret (0usize, comptime_error) }
        next = comptimes_end
        if next >= end { ret (0usize, InvalidArtifact) }
        let backed = usize(bytes[next])
        next += 1usize
        if backed > 1usize { ret (0usize, InvalidArtifact) }
        if backed == 1usize {
            let (after, after_error) = interface_type_end(bytes, next, end, 0usize)
            if after_error != ok { ret (0usize, after_error) }
            next = after
        }
        let (fields, field_first, fields_error) = interface_count(bytes, next, end)
        if fields_error != ok { ret (0usize, fields_error) }
        next = field_first
        var at = 0usize
        while at < fields {
            let (after_name, name_error) = interface_skip(next, end, 4usize)
            if name_error != ok { ret (0usize, name_error) }
            let (typed, typed_error) = interface_type_end(bytes, after_name, end, 0usize)
            if typed_error != ok { ret (0usize, typed_error) }
            let (after, after_error) = interface_skip(typed, end, 12usize)
            if after_error != ok { ret (0usize, after_error) }
            next = after
            at += 1usize
        }
        // (D1510) The attribute tail: 12 bytes.
        if next > end || end - next < 12usize || usize(bytes[next]) > 7usize { ret (0usize, InvalidArtifact) }
        ret (next + 12usize, ok)
    }
    if kind == declaration_alias_kind() {
        if next >= end { ret (0usize, InvalidArtifact) }
        let resolved = usize(bytes[next])
        if resolved > 1usize { ret (0usize, InvalidArtifact) }
        if resolved == 0usize { ret (next + 1usize, ok) }
        let (after, after_error) = interface_type_end(bytes, next + 1usize, end, 0usize)
        ret (after, after_error)
    }
    if kind == declaration_constant_kind() {
        let (typed, typed_error) = interface_type_end(bytes, next, end, 0usize)
        if typed_error != ok { ret (0usize, typed_error) }
        let (after, after_error) = interface_skip(typed, end, 12usize)
        ret (after, after_error)
    }
    if kind == declaration_error_kind() {
        let (after, after_error) = interface_skip(next, end, 4usize)
        ret (after, after_error)
    }
    ret (0usize, InvalidArtifact)
}

// (D1325) Whether every declaration of the artifact's Interface reads back whole:
// each record's typed payload ends exactly where its length says. A kept artifact
// that does not is rebuilt as invalid.
fn interface_payloads_read(bytes: []const u8) -> err {
    let (count, first, end, open_error) = interface_declarations(bytes)
    if open_error != ok { ret open_error }
    var cursor = first
    var at = 0usize
    while at < count {
        let (declaration, next, read_error) = declaration_from(bytes, cursor, end)
        if read_error != ok { ret read_error }
        let (payload_end, payload_error) = interface_payload_end(bytes, declaration.kind, cursor + 8usize, next)
        if payload_error != ok { ret payload_error }
        if payload_end != next { ret InvalidArtifact }
        cursor = next
        at += 1usize
    }
    ret ok
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
    // A protocol function's absence (D494): the edge names the aggregate, the
    // protocol is in the hash field, and it holds while the target declares no
    // `<snake>_<protocol>`.
    if dependency.kind == dependency_lookup_kind() && dependency.hash >= 1usize && dependency.hash <= 3usize {
        let (name_start, name_length, bounds_error) = string_bounds(dependent, dependency.name_index)
        if bounds_error != ok { ret (false, bounds_error) }
        var absent_storage: [256]u8 = zero
        let absent_len = snake_protocol_name(dependent[name_start..name_start + name_length], protocol_name_of(dependency.hash - 1usize), absent_storage[..])
        if absent_len == 0usize { ret (false, ok) }
        let (absent, declared, absent_error) = find_declaration(target_artifact, absent_storage[0usize..absent_len])
        if absent_error != ok { ret (false, absent_error) }
        ret (!declared, ok)
    }
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

// ---------------------------------------------------------------- Interface decode (D1511, C036)

// The checker kind an Interface type id names (the inverse of `type_kind_id`).
fn type_kind_of_id(id: usize) -> (check.Kind, bool) {
    if id == 1usize { ret (.Void, true) }
    if id == 2usize { ret (.Bool, true) }
    if id == 3usize { ret (.Err, true) }
    if id == 4usize { ret (.Integer, true) }
    if id == 5usize { ret (.Float, true) }
    if id == 6usize { ret (.String, true) }
    if id == 7usize { ret (.Named, true) }
    if id == 8usize { ret (.Tag, true) }
    if id == 9usize { ret (.Pointer, true) }
    if id == 10usize { ret (.Slice, true) }
    if id == 11usize { ret (.Array, true) }
    if id == 12usize { ret (.TypeParameter, true) }
    if id == 13usize { ret (.UntypedInteger, true) }
    if id == 14usize { ret (.UntypedFloat, true) }
    if id == 15usize { ret (.Other, true) }
    if id == 16usize { ret (.Function, true) }
    ret (.Invalid, false)
}

// A string of the artifact by index, as a slice of its bytes.
fn artifact_string(bytes: []const u8, index: usize) -> (str, err) {
    let (start, length, bounds_error) = string_bounds(bytes, index)
    if bounds_error != ok { ret ("", bounds_error) }
    ret (bytes[start..start + length], ok)
}

// One encoded type read back into the checker (an element and a function type's
// signature stored as the checker stores its own); where it ends.
fn decode_type(c: *check.Checker, g: *graph.Graph, bytes: []const u8, cursor: usize, end: usize, module_index: usize, depth: usize) -> (check.Type, usize, err) {
    let invalid = check.invalid_type()
    if depth > 64usize || cursor > end || end - cursor < 20usize { ret (invalid, 0usize, InvalidArtifact) }
    let (kind, known) = type_kind_of_id(usize(bytes[cursor]))
    if !known { ret (invalid, 0usize, InvalidArtifact) }
    let flags = usize(bytes[cursor + 1usize])
    let (module_name_index, module_error) = binary.read_u32(bytes, cursor + 4usize)
    let (name_index, name_error) = binary.read_u32(bytes, cursor + 8usize)
    let (length, length_error) = binary.read_u64(bytes, cursor + 12usize)
    if module_error != ok || name_error != ok || length_error != ok { ret (invalid, 0usize, InvalidArtifact) }
    let (name, name_read_error) = artifact_string(bytes, name_index)
    if name_read_error != ok { ret (invalid, 0usize, name_read_error) }
    var owner = module_index
    if kind == .Named || kind == .Tag {
        let (module_name, module_name_error) = artifact_string(bytes, module_name_index)
        if module_name_error != ok { ret (invalid, 0usize, module_name_error) }
        let (found_module, has_module) = graph.find_module(g, module_name)
        if !has_module { ret (invalid, 0usize, InvalidArtifact) }
        owner = found_module
    }
    var ty = check.make_type(kind, name, owner)
    ty.is_const = (flags & 1usize) != 0usize
    ty.has_length = (flags & 4usize) != 0usize
    ty.in_shared = (flags & 8usize) != 0usize
    ty.foreign = (flags & 16usize) != 0usize
    if ty.has_length { ty.array_length = length }
    var next = cursor + 20usize
    if (flags & 2usize) != 0usize && aggregate_type(kind) {
        let (element, element_end, element_error) = decode_type(c, g, bytes, next, end, module_index, depth + 1usize)
        if element_error != ok { ret (invalid, 0usize, element_error) }
        let (element_index, store_error) = check.store_type(c, element)
        if store_error != ok { ret (invalid, 0usize, store_error) }
        ty.element = element_index
        ty.has_element = true
        next = element_end
    }
    if kind == .Function {
        let (parameters, parameters_error) = binary.read_u32(bytes, next)
        let (results, results_error) = binary.read_u32(bytes, next + 4usize)
        if parameters_error != ok || results_error != ok || parameters + results > 64usize { ret (invalid, 0usize, InvalidArtifact) }
        next += 8usize
        // Decoded first (their own elements stored as they come), then stored side
        // by side, as a signature's parameters and returns must stand.
        var held: [64]check.Type = zero
        var at = 0usize
        while at < parameters + results {
            let (part, part_end, part_error) = decode_type(c, g, bytes, next, end, module_index, depth + 1usize)
            if part_error != ok { ret (invalid, 0usize, part_error) }
            held[at] = part
            next = part_end
            at += 1usize
        }
        let (built, built_error) = check.build_function_type(c, held[0usize..parameters], held[parameters..parameters + results], module_index)
        if built_error != ok { ret (invalid, 0usize, built_error) }
        ty.element = built.element
        ty.has_element = true
    }
    ret (ty, next, ok)
}

// Whether a kept module's declarations can come from its Interface alone: no
// generic function, aggregate or alias, no instance, and no global.
fn interface_decodable(bytes: []const u8) -> bool {
    let (count, first, end, open_error) = interface_declarations(bytes)
    if open_error != ok { ret false }
    var cursor = first
    var at = 0usize
    while at < count {
        let (declaration, next, read_error) = declaration_from(bytes, cursor, end)
        if read_error != ok { ret false }
        if declaration.kind == declaration_function_kind() && (declaration.flags & 5usize) != 0usize { ret false }
        if (declaration.kind == declaration_aggregate_kind() || declaration.kind == declaration_alias_kind()) && (declaration.flags & 1usize) != 0usize { ret false }
        // A constant record carries an integer value only: a string, float or
        // composite constant needs its expression, so its module keeps its tree.
        if declaration.kind == declaration_constant_kind() {
            let type_at = cursor + 8usize + 20usize
            if type_at >= end { ret false }
            let type_id = usize(bytes[type_at])
            if type_id != 2usize && type_id != 4usize && type_id != 13usize { ret false }
        }
        cursor = next
        at += 1usize
    }
    // (D1514) Globals declare from the Globals section's types.
    let (globals, found_globals, globals_error) = find_section_unchecked(bytes, globals_kind())
    ret globals_error == ok && found_globals && globals.length >= 4usize
}

// (D1514) The Globals section of an artifact validated once: how many records,
// where the first starts and where the section ends.
fn interface_globals(bytes: []const u8) -> (usize, usize, usize, err) {
    let (section, found, section_error) = find_section_unchecked(bytes, globals_kind())
    if section_error != ok || !found || section.length < 4usize { ret (0usize, 0usize, 0usize, InvalidArtifact) }
    let (count, count_error) = binary.read_u32(bytes, section.offset)
    if count_error != ok || count > (section.length - 4usize) / global_record_size() { ret (0usize, 0usize, 0usize, InvalidArtifact) }
    ret (count, section.offset + 4usize, section.offset + section.length, ok)
}

// (D1514) A kept module's globals from its Globals section: each record's name and
// the type the section carries after the records, in the checker's order. Their
// initial values stay in the artifact the link reads; the checker needs the types.
fn decode_globals(c: *check.Checker, g: *graph.Graph, module_index: usize, bytes: []const u8) -> err {
    let (count, first, end, open_error) = interface_globals(bytes)
    if open_error != ok { ret open_error }
    var next = first + count * global_record_size()
    var at = 0usize
    while at < count {
        if c.global_count == c.globals.len { ret check.Capacity }
        let (record, record_error) = global_record_from(bytes, first + at * global_record_size())
        if record_error != ok { ret record_error }
        let (name, name_error) = artifact_string(bytes, record.name_index)
        if name_error != ok { ret name_error }
        let (ty, typed_end, type_error) = decode_type(c, g, bytes, next, end, module_index, 0usize)
        if type_error != ok { ret type_error }
        var item: check.Global = zero
        item.name = name
        item.module_index = module_index
        item.ty = ty
        c.globals[c.global_count] = item
        c.global_count += 1usize
        next = typed_end
        at += 1usize
    }
    ret ok
}

// A resolver symbol with no token span (the bootstrap takes no qualified literal).
fn interface_symbol(name: str, kind: resolve.Kind, space: resolve.Namespace, module_index: usize, target_module: usize) -> resolve.Symbol {
    var symbol: resolve.Symbol = zero
    symbol.name = name
    symbol.kind = kind
    symbol.space = space
    symbol.module_index = module_index
    symbol.target_module = target_module
    ret symbol
}

// A kept module's resolver symbols from its Interface: its imports' qualifiers
// and one symbol a declaration, as `resolve.collect_module` adds from a tree,
// without token spans.
fn declare_interface_symbols(r: *resolve.Resolver, g: *graph.Graph, module_index: usize, bytes: []const u8) -> err {
    let import_end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var import_at = g.modules[module_index].first_import
    while import_at < import_end {
        let item = g.imports[import_at]
        try resolve.add(r, interface_symbol(item.qualifier, .Qualifier, .Value, module_index, item.target))
        import_at += 1usize
    }
    let (count, first, end, open_error) = interface_declarations(bytes)
    if open_error != ok { ret open_error }
    var cursor = first
    var at = 0usize
    while at < count {
        let (declaration, next, read_error) = declaration_from(bytes, cursor, end)
        if read_error != ok { ret read_error }
        let (name, name_error) = artifact_string(bytes, declaration.name_index)
        if name_error != ok { ret name_error }
        var kind: resolve.Kind = .Function
        var space: resolve.Namespace = .Value
        if declaration.kind < declaration_function_kind() || declaration.kind > declaration_error_kind() { ret InvalidArtifact }
        if declaration.kind == declaration_function_kind() && (declaration.flags & 2usize) != 0usize { kind = .Extern }
        if declaration.kind == declaration_aggregate_kind() || declaration.kind == declaration_alias_kind() {
            kind = .Type
            space = .Type
        }
        if declaration.kind == declaration_constant_kind() { kind = .Const }
        if declaration.kind == declaration_error_kind() { kind = .Error }
        // A seeded intrinsic (`e.mem.alloc`, `e.str.format`) or error (`e.os.NotFound`)
        // is in the Interface as the checker keeps it, and in the resolver already.
        let (prior, seeded) = resolve.find(r, module_index, name, space)
        if !seeded { try resolve.add(r, interface_symbol(name, kind, space, module_index, module_index)) }
        cursor = next
        at += 1usize
    }
    // (D1514) Its globals, by the Globals section's names.
    let (global_count, global_first, global_end, globals_error) = interface_globals(bytes)
    if globals_error != ok { ret globals_error }
    at = 0usize
    while at < global_count {
        let (record, record_error) = global_record_from(bytes, global_first + at * global_record_size())
        if record_error != ok { ret record_error }
        let (global_name, global_name_error) = artifact_string(bytes, record.name_index)
        if global_name_error != ok { ret global_name_error }
        try resolve.add(r, interface_symbol(global_name, .Var, .Value, module_index, module_index))
        at += 1usize
    }
    ret ok
}

// Whether the checker seeded the function itself (an intrinsic of `e.mem`,
// `e.str` or `e.meta`), which its module's Interface lists as the checker keeps it.
fn seeded_function(c: *check.Checker, module_index: usize, name: str) -> bool {
    var at = check.function_row(c, 0usize)
    while at < c.function_count {
        if c.functions[at].intrinsic && c.functions[at].module_index == module_index && same(c.functions[at].name, name) { ret true }
        at = check.function_row(c, at + 1usize)
    }
    ret false
}

// A kept module's checker records from its Interface: its aggregates and aliases,
// constants and functions, in the order `check.declarations_module` makes them
// from a tree, with no source spans. Errors are the resolver's symbols alone.
fn declare_interface_records(c: *check.Checker, g: *graph.Graph, module_index: usize, bytes: []const u8) -> err {
    let (count, first, end, open_error) = interface_declarations(bytes)
    if open_error != ok { ret open_error }
    var pass = 0usize
    while pass < 4usize {
        var cursor = first
        var at = 0usize
        while at < count {
            let (declaration, next, read_error) = declaration_from(bytes, cursor, end)
            if read_error != ok { ret read_error }
            let (name, name_error) = artifact_string(bytes, declaration.name_index)
            if name_error != ok { ret name_error }
            let payload = cursor + 8usize + 20usize
            if pass == 0usize && declaration.kind == declaration_alias_kind() { try decode_alias(c, g, bytes, payload, next, module_index, name) }
            if pass == 1usize && declaration.kind == declaration_constant_kind() { try decode_constant(c, g, bytes, payload, next, module_index, name) }
            if pass == 2usize && declaration.kind == declaration_aggregate_kind() { try decode_aggregate(c, g, bytes, payload, next, module_index, name) }
            if pass == 3usize && declaration.kind == declaration_function_kind() && !seeded_function(c, module_index, name) { try decode_function(c, g, bytes, payload, next, module_index, name, (declaration.flags & 2usize) != 0usize) }
            cursor = next
            at += 1usize
        }
        // Globals follow the constants, as `check.declarations_module` collects them.
        if pass == 1usize { try decode_globals(c, g, module_index, bytes) }
        pass += 1usize
    }
    ret ok
}

// (D1511) A non-generic function record: its borrow and no-escape lists (read
// past; the attribute tail's strings carry their spelling), parameters, returns
// and attributes.
fn decode_function(c: *check.Checker, g: *graph.Graph, bytes: []const u8, payload: usize, end: usize, module_index: usize, name: str, external: bool) -> err {
    if c.function_count == c.functions.len { ret check.Capacity }
    var next = payload + 4usize
    let (noescapes, noescape_error) = binary.read_u32(bytes, next)
    if noescape_error != ok { ret InvalidArtifact }
    next += 4usize + 4usize * noescapes
    let (comptimes, comptime_error) = binary.read_u32(bytes, next)
    if comptime_error != ok || comptimes != 0usize { ret InvalidArtifact }
    next += 4usize
    let (parameters, parameters_error) = binary.read_u32(bytes, next)
    if parameters_error != ok { ret InvalidArtifact }
    next += 4usize
    var item: check.Function = zero
    item.name = name
    item.module_index = module_index
    item.owner_module_index = module_index
    item.external = external
    item.first_parameter = c.parameter_count
    item.parameter_count = parameters
    var at = 0usize
    while at < parameters {
        if c.parameter_count == c.parameters.len { ret check.Capacity }
        let (parameter_name_index, parameter_name_error) = binary.read_u32(bytes, next)
        if parameter_name_error != ok { ret InvalidArtifact }
        let (parameter_name, parameter_string_error) = artifact_string(bytes, parameter_name_index)
        if parameter_string_error != ok { ret parameter_string_error }
        let (parameter_type, typed_end, type_error) = decode_type(c, g, bytes, next + 4usize, end, module_index, 0usize)
        if type_error != ok { ret type_error }
        var parameter: check.Parameter = zero
        parameter.name = parameter_name
        parameter.ty = parameter_type
        c.parameters[c.parameter_count] = parameter
        c.parameter_count += 1usize
        next = typed_end
        at += 1usize
    }
    let (results, results_error) = binary.read_u32(bytes, next)
    if results_error != ok { ret InvalidArtifact }
    next += 4usize
    item.first_return = c.return_type_count
    item.return_count = results
    at = 0usize
    while at < results {
        if c.return_type_count == c.return_types.len { ret check.Capacity }
        let (result_type, typed_end, type_error) = decode_type(c, g, bytes, next, end, module_index, 0usize)
        if type_error != ok { ret type_error }
        c.return_types[c.return_type_count] = result_type
        c.return_type_count += 1usize
        next = typed_end
        at += 1usize
    }
    // The attribute tail (D1510).
    if next > end || end - next < 20usize + parameters { ret InvalidArtifact }
    let attributes = usize(bytes[next])
    item.intrinsic = (attributes & 1usize) != 0usize
    item.variadic = (attributes & 2usize) != 0usize
    item.gpu = (attributes & 4usize) != 0usize
    item.device_only = (attributes & 8usize) != 0usize
    item.callback = (attributes & 16usize) != 0usize
    let (gpu_size, gpu_error) = binary.read_u32(bytes, next + 4usize)
    let (library, library_error) = binary.read_u32(bytes, next + 12usize)
    let (symbol, symbol_error) = binary.read_u32(bytes, next + 16usize)
    if gpu_error != ok || library_error != ok || symbol_error != ok { ret InvalidArtifact }
    item.gpu_size = u32(gpu_size)
    if library != 0usize {
        let (library_text, library_text_error) = artifact_string(bytes, library - 1usize)
        if library_text_error != ok { ret library_text_error }
        item.import_library = library_text
    }
    if symbol != 0usize {
        let (symbol_text, symbol_text_error) = artifact_string(bytes, symbol - 1usize)
        if symbol_text_error != ok { ret symbol_text_error }
        item.import_symbol = symbol_text
    }
    next += 20usize
    at = 0usize
    while at < parameters {
        c.parameters[item.first_parameter + at].own = usize(bytes[next + at]) == 1usize
        at += 1usize
    }
    var generic: check.FunctionGeneric = zero
    generic.first_comptime = c.comptime_parameter_count
    c.functions[c.function_count] = item
    c.function_generics[c.function_count] = generic
    c.function_count += 1usize
    ret ok
}

// (D1511) A non-generic aggregate record: kind, backing, fields and attributes.
fn decode_aggregate(c: *check.Checker, g: *graph.Graph, bytes: []const u8, payload: usize, end: usize, module_index: usize, name: str) -> err {
    if c.aggregate_count == c.aggregates.len { ret check.Capacity }
    var item: check.Aggregate = zero
    item.name = name
    item.module_index = module_index
    let kind_id = usize(bytes[payload])
    if kind_id < 1usize || kind_id > 4usize { ret InvalidArtifact }
    item.kind = .Struct
    if kind_id == 2usize { item.kind = .Union }
    if kind_id == 3usize { item.kind = .TaggedUnion }
    if kind_id == 4usize { item.kind = .Enum }
    let (comptimes, comptime_error) = binary.read_u32(bytes, payload + 4usize)
    if comptime_error != ok || comptimes != 0usize { ret InvalidArtifact }
    var next = payload + 8usize
    let backed = usize(bytes[next])
    next += 1usize
    if backed == 1usize {
        let (backing, backing_end, backing_error) = decode_type(c, g, bytes, next, end, module_index, 0usize)
        if backing_error != ok { ret backing_error }
        item.backing_type = backing
        next = backing_end
    }
    let (fields, fields_error) = binary.read_u32(bytes, next)
    if fields_error != ok { ret InvalidArtifact }
    next += 4usize
    item.first_field = c.aggregate_field_count
    item.field_count = fields
    var at = 0usize
    while at < fields {
        if c.aggregate_field_count == c.aggregate_fields.len { ret check.Capacity }
        let (field_name_index, field_name_error) = binary.read_u32(bytes, next)
        if field_name_error != ok { ret InvalidArtifact }
        let (field_name, field_string_error) = artifact_string(bytes, field_name_index)
        if field_string_error != ok { ret field_string_error }
        let (field_type, typed_end, type_error) = decode_type(c, g, bytes, next + 4usize, end, module_index, 0usize)
        if type_error != ok { ret type_error }
        if typed_end > end || end - typed_end < 12usize { ret InvalidArtifact }
        let (enum_value, enum_error) = binary.read_u64(bytes, typed_end + 4usize)
        if enum_error != ok { ret InvalidArtifact }
        var field: check.AggregateField = zero
        field.name = field_name
        field.ty = field_type
        field.has_enum_value = usize(bytes[typed_end]) == 1usize
        field.enum_negative = usize(bytes[typed_end + 1usize]) == 1usize
        field.enum_value = enum_value
        c.aggregate_fields[c.aggregate_field_count] = field
        c.aggregate_field_count += 1usize
        next = typed_end + 12usize
        at += 1usize
    }
    // The attribute tail (D1510).
    if next > end || end - next < 12usize { ret InvalidArtifact }
    let attributes = usize(bytes[next])
    item.resource = (attributes & 1usize) != 0usize
    item.reorder = (attributes & 2usize) != 0usize
    item.packed = (attributes & 4usize) != 0usize
    // As `register_aggregate_declaration` does (D239): a decoded `@reorder` aggregate is
    // refused at a rebuilt dependent's FFI crossing too (D1677).
    if item.reorder { c.has_reorder = true }
    let (align, align_error) = binary.read_u32(bytes, next + 4usize)
    let (cleanup, cleanup_error) = binary.read_u32(bytes, next + 8usize)
    if align_error != ok || cleanup_error != ok { ret InvalidArtifact }
    item.align = align
    if cleanup != 0usize {
        let (cleanup_text, cleanup_text_error) = artifact_string(bytes, cleanup - 1usize)
        if cleanup_text_error != ok { ret cleanup_text_error }
        item.cleanup = cleanup_text
    }
    c.aggregates[c.aggregate_count] = item
    c.aggregate_count += 1usize
    ret ok
}

// (D1511) A non-generic alias: its resolved type.
fn decode_alias(c: *check.Checker, g: *graph.Graph, bytes: []const u8, payload: usize, end: usize, module_index: usize, name: str) -> err {
    if c.alias_count == c.aliases.len { ret check.Capacity }
    if usize(bytes[payload]) != 1usize { ret InvalidArtifact }
    let (resolved, resolved_end, resolved_error) = decode_type(c, g, bytes, payload + 1usize, end, module_index, 0usize)
    if resolved_error != ok { ret resolved_error }
    var alias: check.Alias = zero
    alias.name = name
    alias.module_index = module_index
    alias.rhs = resolved
    alias.resolved = resolved
    alias.state = 2u8
    c.aliases[c.alias_count] = alias
    c.alias_count += 1usize
    ret ok
}

// (D1511) A constant: its type and its value, already evaluated.
fn decode_constant(c: *check.Checker, g: *graph.Graph, bytes: []const u8, payload: usize, end: usize, module_index: usize, name: str) -> err {
    if c.constant_count == c.constants.len { ret check.Capacity }
    let (ty, typed_end, type_error) = decode_type(c, g, bytes, payload, end, module_index, 0usize)
    if type_error != ok { ret type_error }
    if typed_end > end || end - typed_end < 12usize { ret InvalidArtifact }
    let (magnitude, magnitude_error) = binary.read_u64(bytes, typed_end + 4usize)
    if magnitude_error != ok { ret InvalidArtifact }
    var item: check.Constant = zero
    item.name = name
    item.module_index = module_index
    item.ty = ty
    item.value.magnitude = magnitude
    item.value.negative = usize(bytes[typed_end]) == 1usize
    item.state = 2u8
    c.constants[c.constant_count] = item
    c.constant_count += 1usize
    ret ok
}
