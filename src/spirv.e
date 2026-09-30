// The SPIR-V emitter (spec section 10, D1610): the program's kernels, lowered by
// `lower.module` without the CPU frame, written as one SPIR-V 1.5 module for a Vulkan
// 1.2 device -- `PhysicalStorageBuffer64` addressing, one entry point per kernel.
//
// A NIR value is one of three things here. A scalar is a SPIR-V value; a device address
// is a pair of 32-bit words, bitcast to a typed pointer at each load and store -- SPIR-V
// 1.5 allows that of a `PhysicalStorageBuffer64` pointer -- so no kernel needs `Int64`
// for its addresses: the Iris Xe meets section 10's floor and has no `shaderInt64`
// (D1610). `Int64` is declared only for a kernel's own `u64` and `i64` values. A private
// address -- a `Stack` slot, or an aggregate parameter's copy -- is a `Function` array
// of 32-bit words and a byte offset, since the spec lets no private address escape.
// The invocation ids are what lowering reads, `e.gpu.gid`, `lid` and `wgid`, and come
// from the built-in inputs.
//
// The launch ABI: one push constant, the device address of the argument block, which
// holds the parameters in order at their natural alignment -- a slice as `{ u64
// address, u32 len }` in sixteen bytes. `usize` is 32 bits on `spv`.
//
// Words are appended without failing: a full table sets `full`, and `assemble` answers
// `mem.Exhausted` for it once, so the helpers return plain ids.
use e.mem
use check
use graph
use nir

type Words = struct { data: []u32, count: usize, full: bool }

// The kinds a NIR value can be (D1610).
const KIND_NONE: u8 = 0u8
const KIND_SCALAR: u8 = 1u8
const KIND_PRIVATE: u8 = 2u8
const KIND_BUILTIN: u8 = 3u8

type Module = struct {
    bound: usize,
    capabilities: Words,
    imports: Words,
    entries: Words,
    modes: Words,
    decorations: Words,
    types: Words,
    code: Words,
    t_void: usize,
    t_bool: usize,
    t_u32: usize,
    // Declared on first use, with the `Int64` capability.
    t_u64: usize,
    t_f32: usize,
    t_v2u32: usize,
    t_pair: usize,
    t_fn_void: usize,
    t_v3u32: usize,
    t_in_v3u32: usize,
    t_in_u32: usize,
    t_pc_struct: usize,
    t_pc_pointer: usize,
    t_pc_address: usize,
    t_psb_u32: usize,
    t_psb_u64: usize,
    t_psb_f32: usize,
    t_psb_address: usize,
    t_fn_u32: usize,
    // `GLSL.std.450`, declared only when an exact float sequence needs an extended
    // instruction (`Fma` or the seed `Sqrt`).
    glsl: usize,
    denorm_preserve: bool,
    v_gid: usize,
    v_lid: usize,
    v_wgid: usize,
    v_pc: usize,
    // Interned constants: (type id, low word, high word) -> id.
    constant_types: []usize,
    constant_low: []usize,
    constant_high: []usize,
    constant_ids: []usize,
    constant_count: usize,
    // Interned word arrays for private memory: length -> `Function` pointer type.
    array_lengths: []usize,
    array_pointers: []usize,
    array_count: usize,
    full: bool,
    // Why emission stopped, for the command's diagnostic.
    failure: str,
}

// The per-function tables, indexed by NIR value.
type Values = struct {
    kind: []u8,
    id: []usize,
    ty: []usize,
    signed: []bool,
    offset: []usize,
    dynamic: []usize,
}

// One kernel's control flow: each NIR block's label, its order and each branch's merge.
type Flow = struct {
    labels: []usize,
    order: []usize,
    order_count: usize,
    merges: []usize,
    loop_merges: []usize,
    loop_continues: []usize,
    loop_counts: []usize,
    // Two edge slots per block; zero is not a back edge, otherwise header + 1.
    back_headers: []usize,
    synthetic: []usize,
    synthetic_count: usize,
    // Merge blocks no path reaches, written at the end with `OpUnreachable`.
    dead: []usize,
    dead_count: usize,
    // A branch names its target absolutely, as a builder block (the x64 back end
    // subtracts this too).
    first_block: usize,
}

error Unsupported

// `message` says why when it fails, for the command's diagnostic.
// Every kernel among the builder's functions from `first` on (D1611: a host build hands
// over the one it has just lowered for the device).
fn emit(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, first: usize, message: *str) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    var m: Module = zero
    let init_error = init_module(a, &m)
    if init_error != ok { ret (no_bytes, init_error) }
    var kernels = 0usize
    var function_at = first
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        let (index, found) = check.find_function(c, function.module_index, function.name)
        if found && c.functions[index].gpu {
            let kernel_error = emit_kernel(a, &m, c, g, builder, function_at, index)
            if kernel_error != ok {
                *message = m.failure
                ret (no_bytes, kernel_error)
            }
            kernels += 1usize
        }
        function_at += 1usize
    }
    if kernels == 0usize {
        *message = "the program has no kernel to write as SPIR-V"
        ret (no_bytes, Unsupported)
    }
    let (bytes, bytes_error) = assemble(a, &m)
    ret (bytes, bytes_error)
}

fn fail(m: *Module, message: str) -> err {
    m.failure = message
    ret Unsupported
}

fn init_module(a: *mem.Arena, m: *Module) -> err {
    try init_words(a, &m.capabilities, 64usize)
    try init_words(a, &m.imports, 16usize)
    try init_words(a, &m.entries, 4096usize)
    try init_words(a, &m.modes, 1024usize)
    try init_words(a, &m.decorations, 16384usize)
    try init_words(a, &m.types, 65536usize)
    try init_words(a, &m.code, 1048576usize)
    let (constant_types, constant_types_error) = mem.alloc[usize](a, 4096usize)
    if constant_types_error != ok { ret constant_types_error }
    let (constant_low, constant_low_error) = mem.alloc[usize](a, 4096usize)
    if constant_low_error != ok { ret constant_low_error }
    let (constant_high, constant_high_error) = mem.alloc[usize](a, 4096usize)
    if constant_high_error != ok { ret constant_high_error }
    let (constant_ids, constant_ids_error) = mem.alloc[usize](a, 4096usize)
    if constant_ids_error != ok { ret constant_ids_error }
    m.constant_types = constant_types
    m.constant_low = constant_low
    m.constant_high = constant_high
    m.constant_ids = constant_ids
    let (array_lengths, array_lengths_error) = mem.alloc[usize](a, 1024usize)
    if array_lengths_error != ok { ret array_lengths_error }
    let (array_pointers, array_pointers_error) = mem.alloc[usize](a, 1024usize)
    if array_pointers_error != ok { ret array_pointers_error }
    m.array_lengths = array_lengths
    m.array_pointers = array_pointers
    m.bound = 1usize
    declare_module(m)
    ret ok
}

// ---- words ---------------------------------------------------------------------

fn init_words(a: *mem.Arena, w: *Words, capacity: usize) -> err {
    let (data, data_error) = mem.alloc[u32](a, capacity)
    if data_error != ok { ret data_error }
    w.data = data
    w.count = 0usize
    w.full = false
    ret ok
}

fn put(w: *Words, value: usize) {
    if w.count >= w.data.len {
        w.full = true
        ret
    }
    w.data[w.count] = u32(value & 4294967295usize)
    w.count += 1usize
}

// An instruction's first word: its length in words and its opcode.
fn head(w: *Words, opcode: usize, length: usize) {
    put(w, length * 65536usize + opcode)
}

fn fresh(m: *Module) -> usize {
    let id = m.bound
    m.bound += 1usize
    ret id
}

// A literal string: its bytes, a NUL, padded to a whole word.
fn string_words(value: str) -> usize { ret value.len / 4usize + 1usize }

fn put_string(w: *Words, value: str) {
    var at = 0usize
    while at < string_words(value) * 4usize {
        var word = 0usize
        var lane = 0usize
        while lane < 4usize {
            if at + lane < value.len { word = word | (usize(value[at + lane]) << (lane * 8usize)) }
            lane += 1usize
        }
        put(w, word)
        at += 4usize
    }
}

// ---- the module's fixed part ---------------------------------------------------

const OP_MEMORY_MODEL: usize = 14usize
const OP_EXT_INST_IMPORT: usize = 11usize
const OP_EXT_INST: usize = 12usize
const OP_ENTRY_POINT: usize = 15usize
const OP_EXECUTION_MODE: usize = 16usize
const OP_CAPABILITY: usize = 17usize
const OP_TYPE_VOID: usize = 19usize
const OP_TYPE_BOOL: usize = 20usize
const OP_TYPE_INT: usize = 21usize
const OP_TYPE_FLOAT: usize = 22usize
const OP_TYPE_VECTOR: usize = 23usize
const OP_TYPE_ARRAY: usize = 28usize
const OP_TYPE_STRUCT: usize = 30usize
const OP_TYPE_POINTER: usize = 32usize
const OP_TYPE_FUNCTION: usize = 33usize
const OP_CONSTANT_TRUE: usize = 41usize
const OP_CONSTANT_FALSE: usize = 42usize
const OP_CONSTANT: usize = 43usize
const OP_FUNCTION: usize = 54usize
const OP_FUNCTION_END: usize = 56usize
const OP_VARIABLE: usize = 59usize
const OP_LOAD: usize = 61usize
const OP_STORE: usize = 62usize
const OP_ACCESS_CHAIN: usize = 65usize
const OP_DECORATE: usize = 71usize
const OP_MEMBER_DECORATE: usize = 72usize
const OP_CONVERT_F_TO_U: usize = 109usize
const OP_CONVERT_F_TO_S: usize = 110usize
const OP_CONVERT_S_TO_F: usize = 111usize
const OP_CONVERT_U_TO_F: usize = 112usize
const OP_U_CONVERT: usize = 113usize
const OP_S_CONVERT: usize = 114usize
const OP_COMPOSITE_CONSTRUCT: usize = 80usize
const OP_COMPOSITE_EXTRACT: usize = 81usize
const OP_BITCAST: usize = 124usize
const OP_I_ADD_CARRY: usize = 149usize
const OP_U_MUL_EXTENDED: usize = 151usize
const OP_S_NEGATE: usize = 126usize
const OP_F_NEGATE: usize = 127usize
const OP_I_ADD: usize = 128usize
const OP_F_ADD: usize = 129usize
const OP_I_SUB: usize = 130usize
const OP_F_SUB: usize = 131usize
const OP_I_MUL: usize = 132usize
const OP_F_MUL: usize = 133usize
const OP_U_DIV: usize = 134usize
const OP_S_DIV: usize = 135usize
const OP_F_DIV: usize = 136usize
const OP_U_MOD: usize = 137usize
const OP_S_REM: usize = 138usize
const OP_LOGICAL_OR: usize = 166usize
const OP_LOGICAL_AND: usize = 167usize
const OP_LOGICAL_NOT: usize = 168usize
const OP_SELECT: usize = 169usize
const OP_I_EQUAL: usize = 170usize
const OP_I_NOT_EQUAL: usize = 171usize
const OP_U_GREATER_THAN: usize = 172usize
const OP_S_GREATER_THAN: usize = 173usize
const OP_U_GREATER_THAN_EQUAL: usize = 174usize
const OP_S_GREATER_THAN_EQUAL: usize = 175usize
const OP_U_LESS_THAN: usize = 176usize
const OP_S_LESS_THAN: usize = 177usize
const OP_U_LESS_THAN_EQUAL: usize = 178usize
const OP_S_LESS_THAN_EQUAL: usize = 179usize
const OP_F_ORD_EQUAL: usize = 180usize
const OP_F_UNORD_NOT_EQUAL: usize = 183usize
const OP_F_ORD_LESS_THAN: usize = 184usize
const OP_F_ORD_GREATER_THAN: usize = 186usize
const OP_F_ORD_LESS_THAN_EQUAL: usize = 188usize
const OP_F_ORD_GREATER_THAN_EQUAL: usize = 190usize
const OP_SHIFT_RIGHT_LOGICAL: usize = 194usize
const OP_SHIFT_RIGHT_ARITHMETIC: usize = 195usize
const OP_SHIFT_LEFT_LOGICAL: usize = 196usize
const OP_BITWISE_OR: usize = 197usize
const OP_BITWISE_XOR: usize = 198usize
const OP_BITWISE_AND: usize = 199usize
const OP_NOT: usize = 200usize
const OP_LOOP_MERGE: usize = 246usize
const OP_SELECTION_MERGE: usize = 247usize
const OP_LABEL: usize = 248usize
const OP_BRANCH: usize = 249usize
const OP_BRANCH_CONDITIONAL: usize = 250usize
const OP_RETURN: usize = 253usize
const OP_UNREACHABLE: usize = 255usize

const STORAGE_INPUT: usize = 1usize
const STORAGE_FUNCTION: usize = 7usize
const STORAGE_PUSH_CONSTANT: usize = 9usize
const STORAGE_PHYSICAL: usize = 5349usize

const DECORATION_BLOCK: usize = 2usize
const DECORATION_BUILTIN: usize = 11usize
const DECORATION_OFFSET: usize = 35usize
const DECORATION_NO_CONTRACTION: usize = 42usize

const BUILTIN_WORKGROUP_ID: usize = 26usize
const BUILTIN_LOCAL_INVOCATION_ID: usize = 27usize
const BUILTIN_GLOBAL_INVOCATION_ID: usize = 28usize

// Memory operand `Aligned`.
const MEMORY_ALIGNED: usize = 2usize

fn declare_module(m: *Module) {
    // Shader and PhysicalStorageBufferAddresses; `Int64` when a kernel needs it.
    capability(m, 1usize)
    capability(m, 5347usize)
    m.t_void = fresh(m)
    head(&m.types, OP_TYPE_VOID, 2usize)
    put(&m.types, m.t_void)
    m.t_bool = fresh(m)
    head(&m.types, OP_TYPE_BOOL, 2usize)
    put(&m.types, m.t_bool)
    m.t_u32 = int_type(m, 32usize)
    m.t_f32 = fresh(m)
    head(&m.types, OP_TYPE_FLOAT, 3usize)
    put(&m.types, m.t_f32)
    put(&m.types, 32usize)
    m.t_fn_void = fresh(m)
    head(&m.types, OP_TYPE_FUNCTION, 3usize)
    put(&m.types, m.t_fn_void)
    put(&m.types, m.t_void)
    m.t_v3u32 = fresh(m)
    head(&m.types, OP_TYPE_VECTOR, 4usize)
    put(&m.types, m.t_v3u32)
    put(&m.types, m.t_u32)
    put(&m.types, 3usize)
    m.t_v2u32 = fresh(m)
    head(&m.types, OP_TYPE_VECTOR, 4usize)
    put(&m.types, m.t_v2u32)
    put(&m.types, m.t_u32)
    put(&m.types, 2usize)
    // What `OpIAddCarry` and `OpUMulExtended` answer: two words.
    m.t_pair = fresh(m)
    head(&m.types, OP_TYPE_STRUCT, 4usize)
    put(&m.types, m.t_pair)
    put(&m.types, m.t_u32)
    put(&m.types, m.t_u32)
    m.t_in_v3u32 = pointer_type(m, STORAGE_INPUT, m.t_v3u32)
    m.t_in_u32 = pointer_type(m, STORAGE_INPUT, m.t_u32)
    m.t_psb_u32 = pointer_type(m, STORAGE_PHYSICAL, m.t_u32)
    m.t_psb_f32 = pointer_type(m, STORAGE_PHYSICAL, m.t_f32)
    m.t_psb_address = pointer_type(m, STORAGE_PHYSICAL, m.t_v2u32)
    m.t_fn_u32 = pointer_type(m, STORAGE_FUNCTION, m.t_u32)
    // The push constant: the argument block's device address, as two words.
    m.t_pc_struct = fresh(m)
    head(&m.types, OP_TYPE_STRUCT, 3usize)
    put(&m.types, m.t_pc_struct)
    put(&m.types, m.t_v2u32)
    head(&m.decorations, OP_DECORATE, 3usize)
    put(&m.decorations, m.t_pc_struct)
    put(&m.decorations, DECORATION_BLOCK)
    head(&m.decorations, OP_MEMBER_DECORATE, 5usize)
    put(&m.decorations, m.t_pc_struct)
    put(&m.decorations, 0usize)
    put(&m.decorations, DECORATION_OFFSET)
    put(&m.decorations, 0usize)
    m.t_pc_pointer = pointer_type(m, STORAGE_PUSH_CONSTANT, m.t_pc_struct)
    m.t_pc_address = pointer_type(m, STORAGE_PUSH_CONSTANT, m.t_v2u32)
    m.v_pc = global_variable(m, m.t_pc_pointer, STORAGE_PUSH_CONSTANT)
    m.v_gid = builtin_variable(m, BUILTIN_GLOBAL_INVOCATION_ID)
    m.v_lid = builtin_variable(m, BUILTIN_LOCAL_INVOCATION_ID)
    m.v_wgid = builtin_variable(m, BUILTIN_WORKGROUP_ID)
}

// `u64` and `i64`, which need the `Int64` capability: declared the first time a kernel
// holds one.
fn u64_type(m: *Module) -> usize {
    if m.t_u64 == 0usize {
        capability(m, 11usize)
        m.t_u64 = int_type(m, 64usize)
        m.t_psb_u64 = pointer_type(m, STORAGE_PHYSICAL, m.t_u64)
    }
    ret m.t_u64
}

fn capability(m: *Module, which: usize) {
    head(&m.capabilities, OP_CAPABILITY, 2usize)
    put(&m.capabilities, which)
}

fn glsl_import(m: *Module) -> usize {
    if m.glsl == 0usize {
        m.glsl = fresh(m)
        head(&m.imports, OP_EXT_INST_IMPORT, 2usize + string_words("GLSL.std.450"))
        put(&m.imports, m.glsl)
        put_string(&m.imports, "GLSL.std.450")
    }
    ret m.glsl
}

fn int_type(m: *Module, width: usize) -> usize {
    let id = fresh(m)
    head(&m.types, OP_TYPE_INT, 4usize)
    put(&m.types, id)
    put(&m.types, width)
    put(&m.types, 0usize)
    ret id
}

fn pointer_type(m: *Module, storage: usize, pointee: usize) -> usize {
    let id = fresh(m)
    head(&m.types, OP_TYPE_POINTER, 4usize)
    put(&m.types, id)
    put(&m.types, storage)
    put(&m.types, pointee)
    ret id
}

fn global_variable(m: *Module, pointer: usize, storage: usize) -> usize {
    let id = fresh(m)
    head(&m.types, OP_VARIABLE, 4usize)
    put(&m.types, pointer)
    put(&m.types, id)
    put(&m.types, storage)
    ret id
}

fn builtin_variable(m: *Module, builtin: usize) -> usize {
    let id = global_variable(m, m.t_in_v3u32, STORAGE_INPUT)
    head(&m.decorations, OP_DECORATE, 4usize)
    put(&m.decorations, id)
    put(&m.decorations, DECORATION_BUILTIN)
    put(&m.decorations, builtin)
    ret id
}

// A constant of a scalar type, interned.
fn constant(m: *Module, ty: usize, value: usize) -> usize {
    var high = 0usize
    let low = value & 4294967295usize
    if ty != 0usize && ty == m.t_u64 { high = value >> 32usize }
    var at = 0usize
    while at < m.constant_count {
        if m.constant_types[at] == ty && m.constant_low[at] == low && m.constant_high[at] == high { ret m.constant_ids[at] }
        at += 1usize
    }
    let id = fresh(m)
    if ty == m.t_bool {
        var opcode = OP_CONSTANT_FALSE
        if value != 0usize { opcode = OP_CONSTANT_TRUE }
        head(&m.types, opcode, 3usize)
        put(&m.types, ty)
        put(&m.types, id)
    } else {
        if ty != 0usize && ty == m.t_u64 {
            head(&m.types, OP_CONSTANT, 5usize)
            put(&m.types, ty)
            put(&m.types, id)
            put(&m.types, low)
            put(&m.types, high)
        } else {
            head(&m.types, OP_CONSTANT, 4usize)
            put(&m.types, ty)
            put(&m.types, id)
            put(&m.types, low)
        }
    }
    if m.constant_count >= m.constant_ids.len {
        m.full = true
        ret id
    }
    m.constant_types[m.constant_count] = ty
    m.constant_low[m.constant_count] = low
    m.constant_high[m.constant_count] = high
    m.constant_ids[m.constant_count] = id
    m.constant_count += 1usize
    ret id
}

// A private slot of `words` 32-bit words: the `Function` pointer to its array type.
fn word_array(m: *Module, words: usize) -> usize {
    var at = 0usize
    while at < m.array_count {
        if m.array_lengths[at] == words { ret m.array_pointers[at] }
        at += 1usize
    }
    let length = constant(m, m.t_u32, words)
    let array = fresh(m)
    head(&m.types, OP_TYPE_ARRAY, 4usize)
    put(&m.types, array)
    put(&m.types, m.t_u32)
    put(&m.types, length)
    let pointer = pointer_type(m, STORAGE_FUNCTION, array)
    if m.array_count >= m.array_lengths.len {
        m.full = true
        ret pointer
    }
    m.array_lengths[m.array_count] = words
    m.array_pointers[m.array_count] = pointer
    m.array_count += 1usize
    ret pointer
}

// ---- types of values ---------------------------------------------------------

// The SPIR-V type a NIR type is held in, and whether it is signed; 0 when this row of
// the emitter cannot hold it (D1610's later rows).
fn value_type(m: *Module, ty: check.Type) -> (usize, bool) {
    if ty.kind == .Bool { ret (m.t_bool, false) }
    if ty.kind == .Err { ret (m.t_u32, false) }
    if ty.kind == .Pointer { ret (m.t_v2u32, false) }
    if ty.kind == .Float {
        if same(ty.name, "f32") { ret (m.t_f32, false) }
        ret (0usize, false)
    }
    if ty.kind == .Integer {
        if same(ty.name, "u32") || same(ty.name, "usize") { ret (m.t_u32, false) }
        if same(ty.name, "i32") || same(ty.name, "isize") { ret (m.t_u32, true) }
        if same(ty.name, "u64") { ret (u64_type(m), false) }
        if same(ty.name, "i64") { ret (u64_type(m), true) }
    }
    ret (0usize, false)
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn aggregate(ty: check.Type) -> bool {
    ret ty.kind == .Slice || ty.kind == .Named || ty.kind == .Array || ty.kind == .String
}

fn uses_f32(builder: *nir.Builder, function: nir.Function) -> bool {
    let end = function.first_instruction + function.instruction_count
    var at = function.first_instruction
    while at < end {
        let ty = builder.instructions[at].ty
        if ty.kind == .Float && same(ty.name, "f32") { ret true }
        at += 1usize
    }
    ret false
}

fn type_bytes(m: *Module, ty: usize) -> usize {
    if ty == m.t_v2u32 || (ty != 0usize && ty == m.t_u64) { ret 8usize }
    ret 4usize
}

// ---- a kernel ------------------------------------------------------------------

fn emit_kernel(a: *mem.Arena, m: *Module, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, function_at: usize, checked: usize) -> err {
    let function = builder.functions[function_at]
    let kernel = c.functions[checked]
    var values: Values = zero
    try init_values(a, &values, function.value_count + 1usize)
    var flow: Flow = zero
    try plan_flow(a, m, builder, function, &flow)
    let entry = fresh(m)
    // The entry point, with every interface variable (SPIR-V 1.4 on lists them all).
    let (name, name_error) = qualified_name(a, g, kernel)
    if name_error != ok { ret name_error }
    head(&m.entries, OP_ENTRY_POINT, 3usize + string_words(name) + 4usize)
    put(&m.entries, 5usize)
    put(&m.entries, entry)
    put_string(&m.entries, name)
    put(&m.entries, m.v_pc)
    put(&m.entries, m.v_gid)
    put(&m.entries, m.v_lid)
    put(&m.entries, m.v_wgid)
    // `LocalSize` from `@gpu(X, Y, Z)`, packed as D778 keeps it.
    let size = usize(kernel.gpu_size)
    head(&m.modes, OP_EXECUTION_MODE, 6usize)
    put(&m.modes, entry)
    put(&m.modes, 17usize)
    put(&m.modes, size % 1024usize + 1usize)
    put(&m.modes, size / 1024usize % 1024usize + 1usize)
    put(&m.modes, size / 1048576usize % 1024usize + 1usize)
    if uses_f32(builder, function) {
        if !m.denorm_preserve {
            capability(m, 4464usize)
            m.denorm_preserve = true
        }
        head(&m.modes, OP_EXECUTION_MODE, 4usize)
        put(&m.modes, entry)
        put(&m.modes, 4459usize)
        put(&m.modes, 32usize)
    }
    // The function, and its first block: every private variable, then the block's address.
    head(&m.code, OP_FUNCTION, 5usize)
    put(&m.code, m.t_void)
    put(&m.code, entry)
    put(&m.code, 0usize)
    put(&m.code, m.t_fn_void)
    head(&m.code, OP_LABEL, 2usize)
    put(&m.code, fresh(m))
    try declare_privates(m, builder, function, &values)
    let chain = fresh(m)
    head(&m.code, OP_ACCESS_CHAIN, 5usize)
    put(&m.code, m.t_pc_address)
    put(&m.code, chain)
    put(&m.code, m.v_pc)
    put(&m.code, constant(m, m.t_u32, 0usize))
    let block_address = fresh(m)
    head(&m.code, OP_LOAD, 4usize)
    put(&m.code, m.t_v2u32)
    put(&m.code, block_address)
    put(&m.code, chain)
    head(&m.code, OP_BRANCH, 2usize)
    put(&m.code, flow.labels[0usize])
    var order_at = 0usize
    while order_at < flow.order_count {
        try emit_block(m, c, builder, function, kernel, flow.order[order_at], &flow, &values, block_address)
        order_at += 1usize
    }
    // Several source `continue`s make several NIR back edges. SPIR-V requires exactly
    // one, so they meet in this otherwise empty continue block.
    var synthetic_at = 0usize
    while synthetic_at < flow.synthetic_count {
        let header = flow.synthetic[synthetic_at]
        head(&m.code, OP_LABEL, 2usize)
        put(&m.code, flow.loop_continues[header])
        head(&m.code, OP_BRANCH, 2usize)
        put(&m.code, flow.labels[header])
        synthetic_at += 1usize
    }
    var dead_at = 0usize
    while dead_at < flow.dead_count {
        head(&m.code, OP_LABEL, 2usize)
        put(&m.code, flow.dead[dead_at])
        head(&m.code, OP_UNREACHABLE, 1usize)
        dead_at += 1usize
    }
    head(&m.code, OP_FUNCTION_END, 1usize)
    ret ok
}

fn init_values(a: *mem.Arena, values: *Values, count: usize) -> err {
    let (kinds, kinds_error) = mem.alloc[u8](a, count)
    if kinds_error != ok { ret kinds_error }
    let (ids, ids_error) = mem.alloc[usize](a, count)
    if ids_error != ok { ret ids_error }
    let (tys, tys_error) = mem.alloc[usize](a, count)
    if tys_error != ok { ret tys_error }
    let (signs, signs_error) = mem.alloc[bool](a, count)
    if signs_error != ok { ret signs_error }
    let (offsets, offsets_error) = mem.alloc[usize](a, count)
    if offsets_error != ok { ret offsets_error }
    let (dynamics, dynamics_error) = mem.alloc[usize](a, count)
    if dynamics_error != ok { ret dynamics_error }
    var at = 0usize
    while at < count {
        kinds[at] = KIND_NONE
        ids[at] = 0usize
        tys[at] = 0usize
        signs[at] = false
        offsets[at] = 0usize
        dynamics[at] = 0usize
        at += 1usize
    }
    values.kind = kinds
    values.id = ids
    values.ty = tys
    values.signed = signs
    values.offset = offsets
    values.dynamic = dynamics
    ret ok
}

fn qualified_name(a: *mem.Arena, g: *graph.Graph, kernel: check.Function) -> (str, err) {
    var module_name = ""
    if kernel.module_index < g.count { module_name = g.modules[kernel.module_index].name }
    let (storage, storage_error) = mem.alloc[u8](a, module_name.len + 1usize + kernel.name.len)
    if storage_error != ok { ret ("", storage_error) }
    var at = 0usize
    while at < module_name.len {
        storage[at] = module_name[at]
        at += 1usize
    }
    storage[at] = 46u8
    at += 1usize
    var name_at = 0usize
    while name_at < kernel.name.len {
        storage[at] = kernel.name[name_at]
        at += 1usize
        name_at += 1usize
    }
    ret (storage[0usize..at], ok)
}

// Every `Stack` slot and aggregate parameter as a `Function` array of words; SPIR-V
// wants all of them in the function's first block.
fn declare_privates(m: *Module, builder: *nir.Builder, function: nir.Function, values: *Values) -> err {
    var at = 0usize
    while at < function.instruction_count {
        let instruction = builder.instructions[function.first_instruction + at]
        var bytes = 0usize
        // A slot is counted in eight-byte words, and none means one scalar's.
        if instruction.opcode == .Stack {
            bytes = instruction.immediate * 8usize
            if bytes == 0usize { bytes = 8usize }
        }
        if instruction.opcode == .Parameter && aggregate(instruction.ty) {
            if instruction.ty.kind != .Slice { ret fail(m, "a kernel parameter of this type is not yet written as SPIR-V") }
            bytes = 16usize
        }
        if bytes != 0usize && instruction.has_result {
            let pointer = word_array(m, (bytes + 3usize) / 4usize)
            let variable = fresh(m)
            head(&m.code, OP_VARIABLE, 4usize)
            put(&m.code, pointer)
            put(&m.code, variable)
            put(&m.code, STORAGE_FUNCTION)
            values.kind[instruction.result] = KIND_PRIVATE
            values.id[instruction.result] = variable
            values.offset[instruction.result] = 0usize
            values.dynamic[instruction.result] = 0usize
        }
        at += 1usize
    }
    ret ok
}

// ---- control flow ----------------------------------------------------------------

// The blocks' labels, their order (reverse postorder, so a block follows its
// dominators), selection merges, and the loop merge/continue declarations (D1612).
fn plan_flow(a: *mem.Arena, m: *Module, builder: *nir.Builder, function: nir.Function, flow: *Flow) -> err {
    let blocks = function.block_count
    let (labels, labels_error) = mem.alloc[usize](a, blocks + 1usize)
    if labels_error != ok { ret labels_error }
    let (order, order_error) = mem.alloc[usize](a, blocks + 1usize)
    if order_error != ok { ret order_error }
    let (merges, merges_error) = mem.alloc[usize](a, blocks + 1usize)
    if merges_error != ok { ret merges_error }
    let (loop_merges, loop_merges_error) = mem.alloc[usize](a, blocks + 1usize)
    if loop_merges_error != ok { ret loop_merges_error }
    let (loop_continues, loop_continues_error) = mem.alloc[usize](a, blocks + 1usize)
    if loop_continues_error != ok { ret loop_continues_error }
    let (loop_counts, loop_counts_error) = mem.alloc[usize](a, blocks + 1usize)
    if loop_counts_error != ok { ret loop_counts_error }
    let (back_headers, back_headers_error) = mem.alloc[usize](a, blocks * 2usize + 2usize)
    if back_headers_error != ok { ret back_headers_error }
    let (synthetic, synthetic_error) = mem.alloc[usize](a, blocks + 1usize)
    if synthetic_error != ok { ret synthetic_error }
    let (dead, dead_error) = mem.alloc[usize](a, blocks + 1usize)
    if dead_error != ok { ret dead_error }
    let (state, state_error) = mem.alloc[u8](a, blocks + 1usize)
    if state_error != ok { ret state_error }
    let (stack, stack_error) = mem.alloc[usize](a, blocks + 1usize)
    if stack_error != ok { ret stack_error }
    let (edge, edge_error) = mem.alloc[usize](a, blocks + 1usize)
    if edge_error != ok { ret edge_error }
    let (post, post_error) = mem.alloc[usize](a, blocks + 1usize)
    if post_error != ok { ret post_error }
    let (ipdom, ipdom_error) = mem.alloc[usize](a, blocks + 1usize)
    if ipdom_error != ok { ret ipdom_error }
    let (rank, rank_error) = mem.alloc[usize](a, blocks + 1usize)
    if rank_error != ok { ret rank_error }
    var at = 0usize
    while at < blocks {
        labels[at] = fresh(m)
        merges[at] = 0usize
        loop_merges[at] = 0usize
        loop_continues[at] = 0usize
        loop_counts[at] = 0usize
        back_headers[at * 2usize] = 0usize
        back_headers[at * 2usize + 1usize] = 0usize
        state[at] = 0u8
        at += 1usize
    }
    flow.labels = labels
    flow.order = order
    flow.merges = merges
    flow.loop_merges = loop_merges
    flow.loop_continues = loop_continues
    flow.loop_counts = loop_counts
    flow.back_headers = back_headers
    flow.synthetic = synthetic
    flow.synthetic_count = 0usize
    flow.dead = dead
    flow.dead_count = 0usize
    flow.first_block = function.first_block
    // Postorder by an explicit walk; a successor still on the walk is a loop.
    var post_count = 0usize
    var depth = 1usize
    stack[0usize] = 0usize
    edge[0usize] = 0usize
    state[0usize] = 1u8
    while depth > 0usize {
        let block = stack[depth - 1usize]
        let edge_index = edge[depth - 1usize]
        let (next, has_next) = successor(builder, function, block, edge_index)
        if has_next {
            edge[depth - 1usize] += 1usize
            if next >= blocks { ret fail(m, "a branch leaves the kernel's blocks") }
            if state[next] == 1u8 {
                back_headers[block * 2usize + edge_index] = next + 1usize
                loop_counts[next] += 1usize
            }
            if state[next] == 0u8 {
                state[next] = 1u8
                stack[depth] = next
                edge[depth] = 0usize
                depth += 1usize
            }
        } else {
            state[block] = 2u8
            post[post_count] = block
            post_count += 1usize
            depth = depth - 1usize
        }
    }
    var order_count = 0usize
    while order_count < post_count {
        order[order_count] = post[post_count - 1usize - order_count]
        order_count += 1usize
    }
    flow.order_count = order_count
    // Lowering writes every source loop as `BranchIf body, exit`; the incoming back
    // edge identifies its header and the second target is its merge. One back-edge
    // block can be the continue target directly. Several get one synthetic join.
    at = 0usize
    while at < blocks {
        if loop_counts[at] != 0usize {
            let terminator = last_instruction(builder, function, at)
            if terminator.opcode != .BranchIf { ret fail(m, "a kernel loop has no conditional header") }
            let merge = terminator.target2 - function.first_block
            if merge >= blocks { ret fail(m, "a kernel loop merge leaves the function") }
            loop_merges[at] = labels[merge]
            let body = terminator.target - function.first_block
            // A range `for` has a dedicated increment block immediately after its
            // header and branches past it to the body. A while-like loop does not;
            // give it a distinct continue block even with one back edge, because the
            // source may itself be a nested construct's merge block.
            if loop_counts[at] == 1usize && body != at + 1usize {
                var source = 0usize
                while source < blocks && back_headers[source * 2usize] != at + 1usize && back_headers[source * 2usize + 1usize] != at + 1usize { source += 1usize }
                if source == blocks { ret fail(m, "a kernel loop has no back-edge block") }
                loop_continues[at] = labels[source]
            } else {
                loop_continues[at] = fresh(m)
                synthetic[flow.synthetic_count] = at
                flow.synthetic_count += 1usize
            }
        }
        at += 1usize
    }
    // Post-dominators over the acyclic graph, the exit a virtual node past the blocks:
    // in postorder every successor is done before its block.
    let exit = blocks
    at = 0usize
    while at < post_count {
        rank[post[at]] = at
        at += 1usize
    }
    rank[exit] = blocks + 1usize
    at = 0usize
    while at < post_count {
        let block = post[at]
        var dominator = exit
        var found = false
        var index = 0usize
        while index < 2usize {
            let (next, has_next) = successor(builder, function, block, index)
            if has_next && back_headers[block * 2usize + index] == 0usize {
                if found {
                    dominator = intersect(ipdom, rank, dominator, next, exit)
                } else {
                    dominator = next
                    found = true
                }
            }
            index += 1usize
        }
        ipdom[block] = dominator
        at += 1usize
    }
    // Each conditional branch's merge; two branches may not share one.
    at = 0usize
    while at < post_count {
        let block = post[at]
        let branch = last_instruction(builder, function, block)
        if branch.opcode == .BranchIf && loop_merges[block] == 0usize {
            var merge = 0usize
            if branch.immediate != 0usize {
                let explicit = branch.immediate - 1usize
                if explicit < function.first_block || explicit >= function.first_block + blocks { ret fail(m, "a selection merge leaves the kernel's blocks") }
                merge = labels[explicit - function.first_block]
            } else {
                if ipdom[block] != exit { merge = labels[ipdom[block]] }
            }
            if merge == 0usize {
                merge = fresh(m)
                flow.dead[flow.dead_count] = merge
                flow.dead_count += 1usize
            } else {
                var loop_at = 0usize
                while loop_at < blocks && loop_merges[loop_at] != merge { loop_at += 1usize }
                if loop_at < blocks {
                    merge = fresh(m)
                    flow.dead[flow.dead_count] = merge
                    flow.dead_count += 1usize
                }
                var other = 0usize
                while other < blocks {
                    if merges[other] == merge { ret fail(m, "two branches in a kernel meet at one block, which this row of the SPIR-V emitter does not structure yet") }
                    other += 1usize
                }
            }
            merges[block] = merge
        }
        at += 1usize
    }
    ret ok
}

// The nearest common post-dominator of two blocks, by postorder rank.
fn intersect(ipdom: []usize, rank: []usize, left: usize, right: usize, exit: usize) -> usize {
    var x = left
    var y = right
    while x != y {
        while x != exit && rank[x] < rank[y] { x = ipdom[x] }
        while y != exit && rank[y] < rank[x] { y = ipdom[y] }
        if x == exit || y == exit { ret exit }
    }
    ret x
}

fn last_instruction(builder: *nir.Builder, function: nir.Function, block: usize) -> nir.Instruction {
    let record = builder.blocks[function.first_block + block]
    if record.instruction_count == 0usize {
        var none: nir.Instruction = zero
        ret none
    }
    ret builder.instructions[record.first_instruction + record.instruction_count - 1usize]
}

// The `index`th successor of a block, from its terminator.
fn successor(builder: *nir.Builder, function: nir.Function, block: usize, index: usize) -> (usize, bool) {
    let terminator = last_instruction(builder, function, block)
    if terminator.opcode == .Branch && index == 0usize { ret (terminator.target - function.first_block, true) }
    if terminator.opcode == .BranchIf {
        if index == 0usize { ret (terminator.target - function.first_block, true) }
        if index == 1usize { ret (terminator.target2 - function.first_block, true) }
    }
    ret (0usize, false)
}

// ---- instructions ----------------------------------------------------------------

fn emit_block(m: *Module, c: *check.Checker, builder: *nir.Builder, function: nir.Function, kernel: check.Function, block_index: usize, flow: *Flow, values: *Values, block_address: usize) -> err {
    head(&m.code, OP_LABEL, 2usize)
    put(&m.code, flow.labels[block_index])
    let record = builder.blocks[function.first_block + block_index]
    var at = 0usize
    while at < record.instruction_count {
        let instruction = builder.instructions[record.first_instruction + at]
        try emit_instruction(m, c, builder, kernel, instruction, block_index, flow, values, block_address)
        at += 1usize
    }
    ret ok
}

fn operand(builder: *nir.Builder, instruction: nir.Instruction, index: usize) -> usize {
    ret builder.operands[instruction.first_operand + index]
}

fn scalar(values: *Values, value: usize, id: usize, ty: usize, signed: bool) {
    values.kind[value] = KIND_SCALAR
    values.id[value] = id
    values.ty[value] = ty
    values.signed[value] = signed
}

fn emit_instruction(m: *Module, c: *check.Checker, builder: *nir.Builder, kernel: check.Function, instruction: nir.Instruction, block_index: usize, flow: *Flow, values: *Values, block_address: usize) -> err {
    let opcode = instruction.opcode
    if opcode == .Parameter { ret emit_parameter(m, c, kernel, instruction, values, block_address) }
    if opcode == .Stack { ret ok }
    if opcode == .ConstInteger || opcode == .ConstFloat || opcode == .ConstBool || opcode == .Zero {
        let (ty, signed) = value_type(m, instruction.ty)
        if ty == 0usize { ret fail(m, "a constant of this type is not yet written as SPIR-V") }
        var bits = instruction.immediate
        if opcode == .Zero { bits = 0usize }
        scalar(values, instruction.result, constant(m, ty, bits), ty, signed)
        ret ok
    }
    if opcode == .GlobalAddress { ret emit_global_address(m, builder, instruction, values) }
    if opcode == .FieldAddress { ret emit_field_address(m, builder, instruction, values) }
    if opcode == .IndexAddress { ret emit_index_address(m, builder, instruction, values) }
    if opcode == .Load { ret emit_load(m, builder, instruction, values) }
    if opcode == .Store { ret emit_store(m, builder, instruction, values) }
    if opcode == .Cast { ret emit_cast(m, builder, instruction, values) }
    if opcode == .Sqrt { ret emit_sqrt(m, builder, instruction, values) }
    if opcode == .Add || opcode == .AddWrap || opcode == .Subtract || opcode == .SubtractWrap || opcode == .Multiply || opcode == .MultiplyWrap || opcode == .Divide || opcode == .Remainder || opcode == .BitAnd || opcode == .BitOr || opcode == .BitXor || opcode == .ShiftLeft || opcode == .ShiftRight { ret emit_binary(m, builder, instruction, values) }
    if opcode == .Equal || opcode == .NotEqual || opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual { ret emit_compare(m, builder, instruction, values) }
    if opcode == .Negate || opcode == .BitNot { ret emit_unary(m, builder, instruction, values) }
    if opcode == .Return {
        head(&m.code, OP_RETURN, 1usize)
        ret ok
    }
    if opcode == .Branch {
        var destination = flow.labels[instruction.target - flow.first_block]
        let back = flow.back_headers[block_index * 2usize]
        if back != 0usize && flow.loop_continues[back - 1usize] != flow.labels[block_index] { destination = flow.loop_continues[back - 1usize] }
        head(&m.code, OP_BRANCH, 2usize)
        put(&m.code, destination)
        ret ok
    }
    if opcode == .BranchIf {
        let condition = operand(builder, instruction, 0usize)
        if flow.loop_merges[block_index] != 0usize {
            head(&m.code, OP_LOOP_MERGE, 4usize)
            put(&m.code, flow.loop_merges[block_index])
            put(&m.code, flow.loop_continues[block_index])
            put(&m.code, 0usize)
        } else {
            head(&m.code, OP_SELECTION_MERGE, 3usize)
            put(&m.code, flow.merges[block_index])
            put(&m.code, 0usize)
        }
        var destination = flow.labels[instruction.target - flow.first_block]
        var destination2 = flow.labels[instruction.target2 - flow.first_block]
        let back = flow.back_headers[block_index * 2usize]
        let back2 = flow.back_headers[block_index * 2usize + 1usize]
        if back != 0usize && flow.loop_continues[back - 1usize] != flow.labels[block_index] { destination = flow.loop_continues[back - 1usize] }
        if back2 != 0usize && flow.loop_continues[back2 - 1usize] != flow.labels[block_index] { destination2 = flow.loop_continues[back2 - 1usize] }
        head(&m.code, OP_BRANCH_CONDITIONAL, 4usize)
        put(&m.code, values.id[condition])
        put(&m.code, destination)
        put(&m.code, destination2)
        ret ok
    }
    ret fail(m, "an operation in this kernel is not yet written as SPIR-V")
}

// A parameter from the argument block: a scalar loaded, a slice's header copied into
// its private words.
fn emit_parameter(m: *Module, c: *check.Checker, kernel: check.Function, instruction: nir.Instruction, values: *Values, block_address: usize) -> err {
    let index = instruction.immediate
    // The parameter's offset: every one before it at its natural alignment.
    var offset = 0usize
    var at = 0usize
    while at <= index {
        let ty = c.parameters[kernel.first_parameter + at].ty
        var size = 16usize
        var align = 8usize
        if aggregate(ty) {
            if ty.kind != .Slice { ret fail(m, "a kernel parameter of this type is not yet written as SPIR-V") }
        } else {
            let (held, held_signed) = value_type(m, ty)
            if held == 0usize || held == m.t_bool { ret fail(m, "a kernel parameter of this type is not yet written as SPIR-V") }
            size = type_bytes(m, held)
            align = size
        }
        offset = (offset + align - 1usize) / align * align
        if at == index { break }
        offset += size
        at += 1usize
    }
    let address = add_address(m, block_address, offset)
    if !aggregate(instruction.ty) {
        let (ty, signed) = value_type(m, instruction.ty)
        scalar(values, instruction.result, device_load(m, address, ty), ty, signed)
        ret ok
    }
    // A slice: the address's two words and the length, into the header's words.
    let base = device_load(m, address, m.t_v2u32)
    let length = device_load(m, add_address(m, block_address, offset + 8usize), m.t_u32)
    let header = values.id[instruction.result]
    private_word_store(m, header, 0usize, extract(m, base, 0usize))
    private_word_store(m, header, 1usize, extract(m, base, 1usize))
    private_word_store(m, header, 2usize, length)
    private_word_store(m, header, 3usize, constant(m, m.t_u32, 0usize))
    ret ok
}

// A device address `offset` bytes on: the low word added with its carry into the high.
fn add_address(m: *Module, base: usize, offset: usize) -> usize {
    if offset == 0usize { ret base }
    ret add_wide(m, base, constant(m, m.t_u32, offset), constant(m, m.t_u32, 0usize))
}

// `base` plus the 64-bit amount `low`, `high`, as two words with the carry between them.
fn add_wide(m: *Module, base: usize, low: usize, high: usize) -> usize {
    let sum = binary(m, OP_I_ADD_CARRY, m.t_pair, extract(m, base, 0usize), low)
    let upper = binary(m, OP_I_ADD, m.t_u32, extract(m, base, 1usize), high)
    ret pair(m, extract(m, sum, 0usize), binary(m, OP_I_ADD, m.t_u32, upper, extract(m, sum, 1usize)))
}

fn extract(m: *Module, composite: usize, index: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_COMPOSITE_EXTRACT, 5usize)
    put(&m.code, m.t_u32)
    put(&m.code, id)
    put(&m.code, composite)
    put(&m.code, index)
    ret id
}

fn pair(m: *Module, low: usize, high: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_COMPOSITE_CONSTRUCT, 5usize)
    put(&m.code, m.t_v2u32)
    put(&m.code, id)
    put(&m.code, low)
    put(&m.code, high)
    ret id
}

fn binary(m: *Module, opcode: usize, ty: usize, left: usize, right: usize) -> usize {
    let id = fresh(m)
    head(&m.code, opcode, 5usize)
    put(&m.code, ty)
    put(&m.code, id)
    put(&m.code, left)
    put(&m.code, right)
    ret id
}

fn convert(m: *Module, opcode: usize, ty: usize, value: usize) -> usize {
    let id = fresh(m)
    head(&m.code, opcode, 4usize)
    put(&m.code, ty)
    put(&m.code, id)
    put(&m.code, value)
    ret id
}

fn device_pointer_type(m: *Module, ty: usize) -> usize {
    if ty != 0usize && ty == m.t_u64 { ret m.t_psb_u64 }
    if ty == m.t_v2u32 { ret m.t_psb_address }
    if ty == m.t_f32 { ret m.t_psb_f32 }
    ret m.t_psb_u32
}

fn device_load(m: *Module, address: usize, ty: usize) -> usize {
    let pointer = convert(m, OP_BITCAST, device_pointer_type(m, ty), address)
    let id = fresh(m)
    head(&m.code, OP_LOAD, 6usize)
    put(&m.code, ty)
    put(&m.code, id)
    put(&m.code, pointer)
    put(&m.code, MEMORY_ALIGNED)
    put(&m.code, type_bytes(m, ty))
    ret id
}

fn device_store(m: *Module, address: usize, value: usize, ty: usize) {
    let pointer = convert(m, OP_BITCAST, device_pointer_type(m, ty), address)
    head(&m.code, OP_STORE, 5usize)
    put(&m.code, pointer)
    put(&m.code, value)
    put(&m.code, MEMORY_ALIGNED)
    put(&m.code, type_bytes(m, ty))
}

// A word of a private variable by a constant index.
fn private_word_store(m: *Module, variable: usize, word: usize, value: usize) {
    let pointer = access_word(m, variable, constant(m, m.t_u32, word))
    store_word(m, pointer, value)
}

fn access_word(m: *Module, variable: usize, index: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_ACCESS_CHAIN, 5usize)
    put(&m.code, m.t_fn_u32)
    put(&m.code, id)
    put(&m.code, variable)
    put(&m.code, index)
    ret id
}

fn load_word(m: *Module, pointer: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_LOAD, 4usize)
    put(&m.code, m.t_u32)
    put(&m.code, id)
    put(&m.code, pointer)
    ret id
}

fn store_word(m: *Module, pointer: usize, value: usize) {
    head(&m.code, OP_STORE, 3usize)
    put(&m.code, pointer)
    put(&m.code, value)
}

// A private address's word, `extra` bytes on: the constant byte offset plus the
// dynamic one, over four.
fn private_word(m: *Module, values: *Values, address: usize, extra: usize) -> usize {
    var bytes = constant(m, m.t_u32, values.offset[address] + extra)
    if values.dynamic[address] != 0usize { bytes = binary(m, OP_I_ADD, m.t_u32, bytes, values.dynamic[address]) }
    let index = binary(m, OP_SHIFT_RIGHT_LOGICAL, m.t_u32, bytes, constant(m, m.t_u32, 2usize))
    ret access_word(m, values.id[address], index)
}

fn emit_global_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let index = instruction.immediate
    if index >= builder.global_count { ret fail(m, "a kernel names a global that is not there") }
    let global = builder.globals[index]
    var variable = 0usize
    if same(global.name, "gid") { variable = m.v_gid }
    if same(global.name, "lid") { variable = m.v_lid }
    if same(global.name, "wgid") { variable = m.v_wgid }
    if variable == 0usize { ret fail(m, "a kernel reads a module-scope variable other than the invocation ids") }
    values.kind[instruction.result] = KIND_BUILTIN
    values.id[instruction.result] = variable
    values.offset[instruction.result] = 0usize
    ret ok
}

fn emit_field_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let base = operand(builder, instruction, 0usize)
    let result = instruction.result
    if values.kind[base] == KIND_PRIVATE || KIND_BUILTIN == values.kind[base] {
        values.kind[result] = values.kind[base]
        values.id[result] = values.id[base]
        values.offset[result] = values.offset[base] + instruction.immediate
        values.dynamic[result] = values.dynamic[base]
        ret ok
    }
    if KIND_SCALAR != values.kind[base] { ret fail(m, "a field address has no base") }
    scalar(values, result, add_address(m, values.id[base], instruction.immediate), m.t_v2u32, false)
    ret ok
}

// `base[index]` with the element size in the immediate, checked against the length
// unless `@nocheck`: a failed check returns from the kernel (the fault record is a
// later row, D1610).
fn emit_index_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let base = operand(builder, instruction, 0usize)
    let index = operand(builder, instruction, 1usize)
    let result = instruction.result
    if KIND_SCALAR != values.kind[index] { ret fail(m, "an index has no value") }
    if instruction.operand_count >= 3usize && !instruction.nocheck {
        let length = operand(builder, instruction, 2usize)
        guard(m, binary(m, OP_U_LESS_THAN, m.t_bool, values.id[index], values.id[length]))
    }
    if KIND_PRIVATE == values.kind[base] {
        var dynamic = binary(m, OP_I_MUL, m.t_u32, values.id[index], constant(m, m.t_u32, instruction.immediate))
        if values.dynamic[base] != 0usize { dynamic = binary(m, OP_I_ADD, m.t_u32, values.dynamic[base], dynamic) }
        values.kind[result] = KIND_PRIVATE
        values.id[result] = values.id[base]
        values.offset[result] = values.offset[base]
        values.dynamic[result] = dynamic
        ret ok
    }
    if KIND_SCALAR != values.kind[base] { ret fail(m, "an indexed address has no base") }
    if values.ty[index] != m.t_u32 { ret fail(m, "an index wider than 32 bits is not yet written as SPIR-V") }
    // The element's offset as 64 bits -- a 32-bit index times the size -- then added.
    let scaled = binary(m, OP_U_MUL_EXTENDED, m.t_pair, values.id[index], constant(m, m.t_u32, instruction.immediate))
    scalar(values, result, add_wide(m, values.id[base], extract(m, scaled, 0usize), extract(m, scaled, 1usize)), m.t_v2u32, false)
    ret ok
}

// A check that returns from the kernel when it fails: a selection whose one arm
// returns, and whose merge is where the block goes on.
fn guard(m: *Module, holds: usize) {
    let failed = fresh(m)
    let rest = fresh(m)
    head(&m.code, OP_SELECTION_MERGE, 3usize)
    put(&m.code, rest)
    put(&m.code, 0usize)
    head(&m.code, OP_BRANCH_CONDITIONAL, 4usize)
    put(&m.code, holds)
    put(&m.code, rest)
    put(&m.code, failed)
    head(&m.code, OP_LABEL, 2usize)
    put(&m.code, failed)
    head(&m.code, OP_RETURN, 1usize)
    head(&m.code, OP_LABEL, 2usize)
    put(&m.code, rest)
}

fn emit_load(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let address = operand(builder, instruction, 0usize)
    let (ty, signed) = value_type(m, instruction.ty)
    if ty == 0usize { ret fail(m, "a load of this type is not yet written as SPIR-V") }
    let result = instruction.result
    if KIND_BUILTIN == values.kind[address] {
        if ty != m.t_u32 || values.offset[address] % 4usize != 0usize || values.offset[address] >= 12usize { ret fail(m, "an invocation id is read in an unexpected shape") }
        let chain = fresh(m)
        head(&m.code, OP_ACCESS_CHAIN, 5usize)
        put(&m.code, m.t_in_u32)
        put(&m.code, chain)
        put(&m.code, values.id[address])
        put(&m.code, constant(m, m.t_u32, values.offset[address] / 4usize))
        let id = fresh(m)
        head(&m.code, OP_LOAD, 4usize)
        put(&m.code, m.t_u32)
        put(&m.code, id)
        put(&m.code, chain)
        scalar(values, result, id, ty, signed)
        ret ok
    }
    if KIND_PRIVATE == values.kind[address] {
        if ty == m.t_bool { ret fail(m, "a private bool is not yet written as SPIR-V") }
        let low = load_word(m, private_word(m, values, address, 0usize))
        var value = low
        if ty == m.t_f32 { value = convert(m, OP_BITCAST, m.t_f32, low) }
        if ty == m.t_v2u32 { value = pair(m, low, load_word(m, private_word(m, values, address, 4usize))) }
        if ty != 0usize && ty == m.t_u64 {
            let high = load_word(m, private_word(m, values, address, 4usize))
            let upper = binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u64, convert(m, OP_U_CONVERT, m.t_u64, high), constant(m, m.t_u64, 32usize))
            value = binary(m, OP_BITWISE_OR, m.t_u64, upper, convert(m, OP_U_CONVERT, m.t_u64, low))
        }
        scalar(values, result, value, ty, signed)
        ret ok
    }
    if KIND_SCALAR != values.kind[address] { ret fail(m, "a load has no address") }
    if ty == m.t_bool { ret fail(m, "a bool in device memory is not a device storage type") }
    scalar(values, result, device_load(m, values.id[address], ty), ty, signed)
    ret ok
}

fn emit_store(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let address = operand(builder, instruction, 0usize)
    let value = operand(builder, instruction, 1usize)
    if KIND_SCALAR != values.kind[value] { ret fail(m, "a store of an aggregate is not yet written as SPIR-V") }
    let ty = values.ty[value]
    if KIND_PRIVATE == values.kind[address] {
        if ty == m.t_bool { ret fail(m, "a private bool is not yet written as SPIR-V") }
        var low = values.id[value]
        if ty == m.t_f32 { low = convert(m, OP_BITCAST, m.t_u32, values.id[value]) }
        if ty == m.t_v2u32 {
            low = extract(m, values.id[value], 0usize)
            store_word(m, private_word(m, values, address, 4usize), extract(m, values.id[value], 1usize))
        }
        if ty != 0usize && ty == m.t_u64 {
            low = convert(m, OP_U_CONVERT, m.t_u32, values.id[value])
            let shifted = binary(m, OP_SHIFT_RIGHT_LOGICAL, m.t_u64, values.id[value], constant(m, m.t_u64, 32usize))
            store_word(m, private_word(m, values, address, 4usize), convert(m, OP_U_CONVERT, m.t_u32, shifted))
        }
        store_word(m, private_word(m, values, address, 0usize), low)
        ret ok
    }
    if KIND_SCALAR != values.kind[address] { ret fail(m, "a store has no address") }
    device_store(m, values.id[address], values.id[value], ty)
    ret ok
}

fn emit_cast(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    let (ty, signed) = value_type(m, instruction.ty)
    if ty == 0usize || KIND_SCALAR != values.kind[source] { ret fail(m, "a conversion of this type is not yet written as SPIR-V") }
    let from = values.ty[source]
    if from == m.t_v2u32 || ty == m.t_v2u32 {
        if from != ty { ret fail(m, "a conversion between an address and an integer is not written as SPIR-V") }
    }
    let integer_from = from == m.t_u32 || (from != 0usize && from == m.t_u64)
    let integer_to = ty == m.t_u32 || (ty != 0usize && ty == m.t_u64)
    var id = values.id[source]
    if from != ty {
        if integer_from && integer_to {
            var opcode = OP_U_CONVERT
            if values.signed[source] && ty == u64_type(m) { opcode = OP_S_CONVERT }
            id = convert(m, opcode, ty, values.id[source])
        } else {
            if ty == m.t_f32 && integer_from {
                var opcode = OP_CONVERT_U_TO_F
                if values.signed[source] { opcode = OP_CONVERT_S_TO_F }
                id = convert(m, opcode, ty, values.id[source])
            } else {
                if from == m.t_f32 && integer_to {
                    var opcode = OP_CONVERT_F_TO_U
                    if signed { opcode = OP_CONVERT_F_TO_S }
                    id = convert(m, opcode, ty, values.id[source])
                } else {
                    ret fail(m, "a conversion of this type is not yet written as SPIR-V")
                }
            }
        }
    }
    scalar(values, instruction.result, id, ty, signed)
    ret ok
}

// Every float result is `NoContraction` (spec section 11, D39).
fn no_contraction(m: *Module, id: usize) {
    head(&m.decorations, OP_DECORATE, 3usize)
    put(&m.decorations, id)
    put(&m.decorations, DECORATION_NO_CONTRACTION)
}

fn float_binary(m: *Module, opcode: usize, left: usize, right: usize) -> usize {
    let id = binary(m, opcode, m.t_f32, left, right)
    no_contraction(m, id)
    ret id
}

fn float_fma(m: *Module, a: usize, b: usize, c: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_EXT_INST, 8usize)
    put(&m.code, m.t_f32)
    put(&m.code, id)
    put(&m.code, glsl_import(m))
    put(&m.code, 50usize)
    put(&m.code, a)
    put(&m.code, b)
    put(&m.code, c)
    no_contraction(m, id)
    ret id
}

fn float_sqrt_seed(m: *Module, value: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_EXT_INST, 6usize)
    put(&m.code, m.t_f32)
    put(&m.code, id)
    put(&m.code, glsl_import(m))
    put(&m.code, 31usize)
    put(&m.code, value)
    ret id
}

fn select_float(m: *Module, condition: usize, yes: usize, no: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_SELECT, 6usize)
    put(&m.code, m.t_f32)
    put(&m.code, id)
    put(&m.code, condition)
    put(&m.code, yes)
    put(&m.code, no)
    ret id
}

fn select_u32(m: *Module, condition: usize, yes: usize, no: usize) -> usize {
    let id = fresh(m)
    head(&m.code, OP_SELECT, 6usize)
    put(&m.code, m.t_u32)
    put(&m.code, id)
    put(&m.code, condition)
    put(&m.code, yes)
    put(&m.code, no)
    ret id
}

fn select_u64(m: *Module, condition: usize, yes: usize, no: usize) -> usize {
    let ty = u64_type(m)
    let id = fresh(m)
    head(&m.code, OP_SELECT, 6usize)
    put(&m.code, ty)
    put(&m.code, id)
    put(&m.code, condition)
    put(&m.code, yes)
    put(&m.code, no)
    ret id
}

fn float_abs_bits(m: *Module, value: usize) -> usize {
    let bits = convert(m, OP_BITCAST, m.t_u32, value)
    ret binary(m, OP_BITWISE_AND, m.t_u32, bits, constant(m, m.t_u32, 2147483647usize))
}

fn finite_nonzero(m: *Module, value: usize) -> usize {
    let bits = float_abs_bits(m, value)
    let finite = binary(m, OP_U_LESS_THAN, m.t_bool, bits, constant(m, m.t_u32, 2139095040usize))
    let nonzero = binary(m, OP_I_NOT_EQUAL, m.t_bool, bits, constant(m, m.t_u32, 0usize))
    ret binary(m, OP_LOGICAL_AND, m.t_bool, finite, nonzero)
}

fn canonical_float(m: *Module, value: usize) -> usize {
    let bits = float_abs_bits(m, value)
    let nan = binary(m, OP_U_GREATER_THAN, m.t_bool, bits, constant(m, m.t_u32, 2139095040usize))
    ret select_float(m, nan, constant(m, m.t_f32, 2143289344usize), value)
}

// Markstein residual correction. The second pass starts from a neighbour of the
// exact quotient even when Vulkan's seed was at its allowed 2.5-ULP limit.
fn divide_core(m: *Module, numerator: usize, denominator: usize) -> usize {
    var quotient = float_binary(m, OP_F_DIV, numerator, denominator)
    let reciprocal = float_binary(m, OP_F_DIV, constant(m, m.t_f32, 1065353216usize), denominator)
    var step = 0usize
    while step < 2usize {
        let negative = convert(m, OP_F_NEGATE, m.t_f32, quotient)
        no_contraction(m, negative)
        let residual = float_fma(m, negative, denominator, numerator)
        quotient = float_fma(m, residual, reciprocal, quotient)
        step += 1usize
    }
    ret quotient
}

fn normalized_significand(m: *Module, bits: usize) -> (usize, usize) {
    let absolute = binary(m, OP_BITWISE_AND, m.t_u32, bits, constant(m, m.t_u32, 2147483647usize))
    let exponent = binary(m, OP_SHIFT_RIGHT_LOGICAL, m.t_u32, absolute, constant(m, m.t_u32, 23usize))
    let fraction = binary(m, OP_BITWISE_AND, m.t_u32, absolute, constant(m, m.t_u32, 8388607usize))
    let normal = binary(m, OP_I_NOT_EQUAL, m.t_bool, exponent, constant(m, m.t_u32, 0usize))
    var significand = select_u32(m, normal, binary(m, OP_BITWISE_OR, m.t_u32, fraction, constant(m, m.t_u32, 8388608usize)), fraction)
    significand = select_u32(m, binary(m, OP_I_EQUAL, m.t_bool, significand, constant(m, m.t_u32, 0usize)), constant(m, m.t_u32, 1usize), significand)
    var effective = select_u32(m, normal, exponent, constant(m, m.t_u32, 1usize))
    var step = 0usize
    while step < 23usize {
        let shift = binary(m, OP_U_LESS_THAN, m.t_bool, significand, constant(m, m.t_u32, 8388608usize))
        significand = select_u32(m, shift, binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u32, significand, constant(m, m.t_u32, 1usize)), significand)
        effective = select_u32(m, shift, binary(m, OP_I_SUB, m.t_u32, effective, constant(m, m.t_u32, 1usize)), effective)
        step += 1usize
    }
    ret (significand, effective)
}

fn rounded_quotient(m: *Module, numerator: usize, denominator: usize) -> usize {
    let ty = u64_type(m)
    let floor = binary(m, OP_U_DIV, ty, numerator, denominator)
    let remainder = binary(m, OP_U_MOD, ty, numerator, denominator)
    let twice_remainder = binary(m, OP_SHIFT_LEFT_LOGICAL, ty, remainder, constant(m, ty, 1usize))
    let greater = binary(m, OP_U_GREATER_THAN, m.t_bool, twice_remainder, denominator)
    let equal = binary(m, OP_I_EQUAL, m.t_bool, twice_remainder, denominator)
    let odd = binary(m, OP_I_NOT_EQUAL, m.t_bool, binary(m, OP_BITWISE_AND, ty, floor, constant(m, ty, 1usize)), constant(m, ty, 0usize))
    let round_up = binary(m, OP_LOGICAL_OR, m.t_bool, greater, binary(m, OP_LOGICAL_AND, m.t_bool, equal, odd))
    ret select_u64(m, round_up, binary(m, OP_I_ADD, ty, floor, constant(m, ty, 1usize)), floor)
}

// Normalize the two 24-bit significands, divide them once in u64, and use the
// remainder for round-to-nearest-even. This fixes the last bit independently of
// the Vulkan implementation's permitted OpFDiv and Fma error.
fn exact_divide(m: *Module, numerator: usize, denominator: usize) -> usize {
    let ty = u64_type(m)
    let numerator_bits = convert(m, OP_BITCAST, m.t_u32, numerator)
    let denominator_bits = convert(m, OP_BITCAST, m.t_u32, denominator)
    let (numerator_significand, numerator_exponent) = normalized_significand(m, numerator_bits)
    let (denominator_significand, denominator_exponent) = normalized_significand(m, denominator_bits)
    let shift = binary(m, OP_U_LESS_THAN, m.t_bool, numerator_significand, denominator_significand)
    let normalized_numerator = select_u32(m, shift, binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u32, numerator_significand, constant(m, m.t_u32, 1usize)), numerator_significand)
    var result_exponent = binary(m, OP_I_ADD, m.t_u32, binary(m, OP_I_SUB, m.t_u32, numerator_exponent, denominator_exponent), constant(m, m.t_u32, 127usize))
    result_exponent = select_u32(m, shift, binary(m, OP_I_SUB, m.t_u32, result_exponent, constant(m, m.t_u32, 1usize)), result_exponent)
    let wide_numerator = binary(m, OP_SHIFT_LEFT_LOGICAL, ty, convert(m, OP_U_CONVERT, ty, normalized_numerator), constant(m, ty, 23usize))
    let wide_denominator = convert(m, OP_U_CONVERT, ty, denominator_significand)
    var rounded = rounded_quotient(m, wide_numerator, wide_denominator)
    let carry = binary(m, OP_U_GREATER_THAN_EQUAL, m.t_bool, rounded, constant(m, ty, 16777216usize))
    rounded = select_u64(m, carry, binary(m, OP_SHIFT_RIGHT_LOGICAL, ty, rounded, constant(m, ty, 1usize)), rounded)
    let carry32 = select_u32(m, carry, constant(m, m.t_u32, 1usize), constant(m, m.t_u32, 0usize))
    let normal_exponent = binary(m, OP_I_ADD, m.t_u32, result_exponent, carry32)
    let overflow = binary(m, OP_S_GREATER_THAN_EQUAL, m.t_bool, normal_exponent, constant(m, m.t_u32, 255usize))
    var normal_bits = binary(m, OP_BITWISE_OR, m.t_u32, binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u32, normal_exponent, constant(m, m.t_u32, 23usize)), binary(m, OP_BITWISE_AND, m.t_u32, convert(m, OP_U_CONVERT, m.t_u32, rounded), constant(m, m.t_u32, 8388607usize)))
    normal_bits = select_u32(m, overflow, constant(m, m.t_u32, 2139095040usize), normal_bits)
    let subnormal = binary(m, OP_S_LESS_THAN_EQUAL, m.t_bool, result_exponent, constant(m, m.t_u32, 0usize))
    let subnormal_shift_raw = binary(m, OP_I_SUB, m.t_u32, constant(m, m.t_u32, 1usize), result_exponent)
    let too_small = binary(m, OP_U_GREATER_THAN, m.t_bool, subnormal_shift_raw, constant(m, m.t_u32, 24usize))
    let subnormal_shift = select_u32(m, binary(m, OP_LOGICAL_OR, m.t_bool, convert(m, OP_LOGICAL_NOT, m.t_bool, subnormal), too_small), constant(m, m.t_u32, 0usize), subnormal_shift_raw)
    let subnormal_denominator = binary(m, OP_SHIFT_LEFT_LOGICAL, ty, wide_denominator, convert(m, OP_U_CONVERT, ty, subnormal_shift))
    var subnormal_bits = convert(m, OP_U_CONVERT, m.t_u32, rounded_quotient(m, wide_numerator, subnormal_denominator))
    subnormal_bits = select_u32(m, too_small, constant(m, m.t_u32, 0usize), subnormal_bits)
    let magnitude = select_u32(m, subnormal, subnormal_bits, normal_bits)
    let sign = binary(m, OP_BITWISE_AND, m.t_u32, binary(m, OP_BITWISE_XOR, m.t_u32, numerator_bits, denominator_bits), constant(m, m.t_u32, 2147483648usize))
    let bits = binary(m, OP_BITWISE_OR, m.t_u32, sign, magnitude)
    ret convert(m, OP_BITCAST, m.t_f32, bits)
}

fn divide_float(m: *Module, numerator: usize, denominator: usize) -> usize {
    let seed = float_binary(m, OP_F_DIV, numerator, denominator)
    let refined = divide_core(m, numerator, denominator)
    let quotient = exact_divide(m, numerator, denominator)
    let valid = binary(m, OP_LOGICAL_AND, m.t_bool, finite_nonzero(m, numerator), finite_nonzero(m, denominator))
    let rounded = select_float(m, valid, quotient, refined)
    ret canonical_float(m, select_float(m, valid, rounded, seed))
}

fn integer_sqrt(m: *Module, radicand: usize) -> usize {
    let ty = u64_type(m)
    var root = constant(m, ty, 0usize)
    var remainder = constant(m, ty, 0usize)
    var digit = 24usize
    while digit > 0usize {
        digit = digit - 1usize
        let shifted = binary(m, OP_SHIFT_RIGHT_LOGICAL, ty, radicand, constant(m, ty, digit * 2usize))
        let next = binary(m, OP_BITWISE_AND, ty, shifted, constant(m, ty, 3usize))
        remainder = binary(m, OP_BITWISE_OR, ty, binary(m, OP_SHIFT_LEFT_LOGICAL, ty, remainder, constant(m, ty, 2usize)), next)
        let trial = binary(m, OP_BITWISE_OR, ty, binary(m, OP_SHIFT_LEFT_LOGICAL, ty, root, constant(m, ty, 2usize)), constant(m, ty, 1usize))
        let take = binary(m, OP_U_GREATER_THAN_EQUAL, m.t_bool, remainder, trial)
        remainder = select_u64(m, take, binary(m, OP_I_SUB, ty, remainder, trial), remainder)
        root = binary(m, OP_SHIFT_LEFT_LOGICAL, ty, root, constant(m, ty, 1usize))
        root = select_u64(m, take, binary(m, OP_BITWISE_OR, ty, root, constant(m, ty, 1usize)), root)
    }
    ret root
}

// `sqrt(M * 2^23)` is rounded as an integer; a remainder greater than the floor
// root lies above the half-way square. The input is normal after scaling below.
fn exact_sqrt_normal(m: *Module, value: usize) -> usize {
    let ty = u64_type(m)
    let bits = convert(m, OP_BITCAST, m.t_u32, value)
    let exponent = binary(m, OP_SHIFT_RIGHT_LOGICAL, m.t_u32, bits, constant(m, m.t_u32, 23usize))
    let fraction = binary(m, OP_BITWISE_AND, m.t_u32, bits, constant(m, m.t_u32, 8388607usize))
    let significand = binary(m, OP_BITWISE_OR, m.t_u32, fraction, constant(m, m.t_u32, 8388608usize))
    let odd = binary(m, OP_I_EQUAL, m.t_bool, binary(m, OP_BITWISE_AND, m.t_u32, exponent, constant(m, m.t_u32, 1usize)), constant(m, m.t_u32, 0usize))
    let doubled = binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u32, significand, constant(m, m.t_u32, 1usize))
    let normalized = select_u32(m, odd, doubled, significand)
    let radicand = binary(m, OP_SHIFT_LEFT_LOGICAL, ty, convert(m, OP_U_CONVERT, ty, normalized), constant(m, ty, 23usize))
    let floor = integer_sqrt(m, radicand)
    let square = binary(m, OP_I_MUL, ty, floor, floor)
    let remainder = binary(m, OP_I_SUB, ty, radicand, square)
    let round_up = binary(m, OP_U_GREATER_THAN, m.t_bool, remainder, floor)
    let rounded = select_u64(m, round_up, binary(m, OP_I_ADD, ty, floor, constant(m, ty, 1usize)), floor)
    let rounded32 = convert(m, OP_U_CONVERT, m.t_u32, rounded)
    let result_exponent = binary(m, OP_SHIFT_RIGHT_LOGICAL, m.t_u32, binary(m, OP_I_ADD, m.t_u32, exponent, constant(m, m.t_u32, 127usize)), constant(m, m.t_u32, 1usize))
    let result_bits = binary(m, OP_I_ADD, m.t_u32, binary(m, OP_SHIFT_LEFT_LOGICAL, m.t_u32, result_exponent, constant(m, m.t_u32, 23usize)), binary(m, OP_I_SUB, m.t_u32, rounded32, constant(m, m.t_u32, 8388608usize)))
    ret convert(m, OP_BITCAST, m.t_f32, result_bits)
}

fn sqrt_float(m: *Module, value: usize) -> usize {
    let seed = float_sqrt_seed(m, value)
    let bits = float_abs_bits(m, value)
    // Scaling by 2^48 makes every positive subnormal input normal; the root scales
    // back exactly by 2^-24 after the Fma refinement and integer rounding pass.
    let small = binary(m, OP_U_LESS_THAN, m.t_bool, bits, constant(m, m.t_u32, 201326592usize))
    let scaled = float_binary(m, OP_F_MUL, value, constant(m, m.t_f32, 1468006400usize))
    let adjusted = select_float(m, small, scaled, value)
    var root = float_sqrt_seed(m, adjusted)
    var step = 0usize
    while step < 1usize {
        let negative = convert(m, OP_F_NEGATE, m.t_f32, root)
        no_contraction(m, negative)
        let residual = float_fma(m, negative, root, adjusted)
        let half_over_root = divide_core(m, constant(m, m.t_f32, 1056964608usize), root)
        root = float_fma(m, residual, half_over_root, root)
        step += 1usize
    }
    root = exact_sqrt_normal(m, adjusted)
    let root_bits = convert(m, OP_BITCAST, m.t_u32, root)
    let unscaled_bits = binary(m, OP_I_SUB, m.t_u32, root_bits, constant(m, m.t_u32, 201326592usize))
    root = select_float(m, small, convert(m, OP_BITCAST, m.t_f32, unscaled_bits), root)
    let valid = finite_nonzero(m, value)
    let sign = binary(m, OP_BITWISE_AND, m.t_u32, convert(m, OP_BITCAST, m.t_u32, value), constant(m, m.t_u32, 2147483648usize))
    let positive = binary(m, OP_I_EQUAL, m.t_bool, sign, constant(m, m.t_u32, 0usize))
    let refine = binary(m, OP_LOGICAL_AND, m.t_bool, valid, positive)
    let negative = binary(m, OP_LOGICAL_AND, m.t_bool, valid, convert(m, OP_LOGICAL_NOT, m.t_bool, positive))
    var result = select_float(m, refine, root, seed)
    result = select_float(m, negative, constant(m, m.t_f32, 2143289344usize), result)
    ret canonical_float(m, result)
}

fn emit_binary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    let (ty, signed) = value_type(m, instruction.ty)
    if ty == 0usize || values.kind[left] != KIND_SCALAR || KIND_SCALAR != values.kind[right] { ret fail(m, "an arithmetic operation of this type is not yet written as SPIR-V") }
    let opcode = instruction.opcode
    var spirv = 0usize
    if ty == m.t_f32 {
        if opcode == .Add { spirv = OP_F_ADD }
        if opcode == .Subtract { spirv = OP_F_SUB }
        if opcode == .Multiply { spirv = OP_F_MUL }
        if opcode == .Divide {
            scalar(values, instruction.result, divide_float(m, values.id[left], values.id[right]), ty, signed)
            ret ok
        }
        if spirv == 0usize { ret fail(m, "a float operation is not yet written as SPIR-V") }
        let id = binary(m, spirv, ty, values.id[left], values.id[right])
        no_contraction(m, id)
        scalar(values, instruction.result, id, ty, signed)
        ret ok
    }
    if opcode == .Add || opcode == .AddWrap { spirv = OP_I_ADD }
    if opcode == .Subtract || opcode == .SubtractWrap { spirv = OP_I_SUB }
    if opcode == .Multiply || opcode == .MultiplyWrap { spirv = OP_I_MUL }
    if opcode == .Divide {
        spirv = OP_U_DIV
        if signed { spirv = OP_S_DIV }
    }
    if opcode == .Remainder {
        spirv = OP_U_MOD
        if signed { spirv = OP_S_REM }
    }
    if opcode == .BitAnd { spirv = OP_BITWISE_AND }
    if opcode == .BitOr { spirv = OP_BITWISE_OR }
    if opcode == .BitXor { spirv = OP_BITWISE_XOR }
    if opcode == .ShiftLeft { spirv = OP_SHIFT_LEFT_LOGICAL }
    if opcode == .ShiftRight {
        spirv = OP_SHIFT_RIGHT_LOGICAL
        if signed { spirv = OP_SHIFT_RIGHT_ARITHMETIC }
    }
    if spirv == 0usize || ty == m.t_bool { ret fail(m, "an integer operation is not yet written as SPIR-V") }
    scalar(values, instruction.result, binary(m, spirv, ty, values.id[left], values.id[right]), ty, signed)
    ret ok
}

fn emit_sqrt(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    let (ty, signed) = value_type(m, instruction.ty)
    if ty != m.t_f32 || KIND_SCALAR != values.kind[source] { ret fail(m, "a square root of this type is not yet written as SPIR-V") }
    scalar(values, instruction.result, sqrt_float(m, values.id[source]), ty, signed)
    ret ok
}

fn emit_compare(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    if values.kind[left] != KIND_SCALAR || KIND_SCALAR != values.kind[right] { ret fail(m, "a comparison has no operands") }
    let ty = values.ty[left]
    let signed = values.signed[left]
    let opcode = instruction.opcode
    var spirv = 0usize
    if ty == m.t_f32 {
        if opcode == .Equal { spirv = OP_F_ORD_EQUAL }
        if opcode == .NotEqual { spirv = OP_F_UNORD_NOT_EQUAL }
        if opcode == .Less { spirv = OP_F_ORD_LESS_THAN }
        if opcode == .LessEqual { spirv = OP_F_ORD_LESS_THAN_EQUAL }
        if opcode == .Greater { spirv = OP_F_ORD_GREATER_THAN }
        if opcode == .GreaterEqual { spirv = OP_F_ORD_GREATER_THAN_EQUAL }
    } else {
        if ty == m.t_bool { ret fail(m, "a bool comparison is not yet written as SPIR-V") }
        if opcode == .Equal { spirv = OP_I_EQUAL }
        if opcode == .NotEqual { spirv = OP_I_NOT_EQUAL }
        if opcode == .Less {
            spirv = OP_U_LESS_THAN
            if signed { spirv = OP_S_LESS_THAN }
        }
        if opcode == .LessEqual {
            spirv = OP_U_LESS_THAN_EQUAL
            if signed { spirv = OP_S_LESS_THAN_EQUAL }
        }
        if opcode == .Greater {
            spirv = OP_U_GREATER_THAN
            if signed { spirv = OP_S_GREATER_THAN }
        }
        if opcode == .GreaterEqual {
            spirv = OP_U_GREATER_THAN_EQUAL
            if signed { spirv = OP_S_GREATER_THAN_EQUAL }
        }
    }
    scalar(values, instruction.result, binary(m, spirv, m.t_bool, values.id[left], values.id[right]), m.t_bool, false)
    ret ok
}

fn emit_unary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    if KIND_SCALAR != values.kind[source] { ret fail(m, "a unary operation has no operand") }
    let ty = values.ty[source]
    var spirv = OP_NOT
    if instruction.opcode == .Negate {
        spirv = OP_S_NEGATE
        if ty == m.t_f32 { spirv = OP_F_NEGATE }
    }
    if ty == m.t_bool {
        if instruction.opcode != .BitNot { ret fail(m, "a bool operation is not yet written as SPIR-V") }
        spirv = OP_LOGICAL_NOT
    }
    let id = convert(m, spirv, ty, values.id[source])
    if ty == m.t_f32 { no_contraction(m, id) }
    scalar(values, instruction.result, id, ty, values.signed[source])
    ret ok
}

// ---- the binary ------------------------------------------------------------------

// The module's words in SPIR-V's logical layout, little-endian bytes.
fn assemble(a: *mem.Arena, m: *Module) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    if m.full || m.capabilities.full || m.imports.full || m.entries.full || m.modes.full || m.decorations.full || m.types.full || m.code.full { ret (no_bytes, mem.Exhausted) }
    let total = 5usize + m.capabilities.count + m.imports.count + 3usize + m.entries.count + m.modes.count + m.decorations.count + m.types.count + m.code.count
    let (bytes, bytes_error) = mem.alloc[u8](a, total * 4usize)
    if bytes_error != ok { ret (no_bytes, bytes_error) }
    var at = 0usize
    at = put_word(bytes, at, 119734787usize)
    // SPIR-V 1.5, which Vulkan 1.2 accepts and which has PhysicalStorageBuffer64 in core.
    at = put_word(bytes, at, 66816usize)
    at = put_word(bytes, at, 0usize)
    at = put_word(bytes, at, m.bound)
    at = put_word(bytes, at, 0usize)
    at = put_words(bytes, at, m.capabilities)
    at = put_words(bytes, at, m.imports)
    // OpMemoryModel PhysicalStorageBuffer64 GLSL450.
    at = put_word(bytes, at, 3usize * 65536usize + OP_MEMORY_MODEL)
    at = put_word(bytes, at, 5348usize)
    at = put_word(bytes, at, 1usize)
    at = put_words(bytes, at, m.entries)
    at = put_words(bytes, at, m.modes)
    at = put_words(bytes, at, m.decorations)
    at = put_words(bytes, at, m.types)
    at = put_words(bytes, at, m.code)
    ret (bytes[0usize..at], ok)
}

fn put_word(bytes: []u8, at: usize, value: usize) -> usize {
    bytes[at] = u8(value & 255usize)
    bytes[at + 1usize] = u8((value >> 8usize) & 255usize)
    bytes[at + 2usize] = u8((value >> 16usize) & 255usize)
    bytes[at + 3usize] = u8((value >> 24usize) & 255usize)
    ret at + 4usize
}

fn put_words(bytes: []u8, at: usize, w: Words) -> usize {
    var to = at
    var index = 0usize
    while index < w.count {
        to = put_word(bytes, to, usize(w.data[index]))
        index += 1usize
    }
    ret to
}
