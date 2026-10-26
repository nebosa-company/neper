// The Metal Shading Language emitter (C193, D5232): the program's kernels, lowered by `lower.module` without the CPU frame as the
// SPIR-V emitter takes them (`builder.spirv`), written as one MSL source for a Metal device -- one `kernel` function each.
//
// MSL has no `goto`, so a kernel is a state machine: every NIR block is a `case` of a `switch` on `pc` inside `while (true)`, a
// branch assigns `pc` and continues, a return returns. That needs no structured control flow and no phi (lowering writes none
// for a device build: values that cross blocks live in `Stack` slots), at the price of a dispatch per block that a structured
// emission can remove later.
//
// A NIR value is one of the same kinds the SPIR-V emitter keeps. A scalar is a typed variable `vN`. A device address is a `ulong`
// offset into the device's heap buffer (one `device uchar* heap` argument): a Metal device may not let a kernel use a buffer's
// own address, so the launcher carves every buffer from one shared heap and an address is where in it. A private address -- a
// `Stack` slot, an aggregate parameter's copy -- is a byte offset into the kernel's `frame` array, plus a dynamic offset
// variable. A workgroup address is an offset into the `threadgroup` block. The invocation ids come from `gid3`, `lid3` and
// `wgid3`.
//
// The launch ABI is SPIR-V's: argument 0 is the argument block (an 8-byte fault buffer offset first in a checked build, then
// the parameters at their natural alignment, a slice as `{ u64 offset, u32 len }` in sixteen bytes), argument 1 the heap.
// `usize` is 32 bits, as on `spv`. A float operation that has to be exact to the last bit (division, square root: spec
// section 11) is `Unsupported` here until its sequence is written, so the CPU runs that kernel, as it does for anything the
// emitter cannot write.
use e.mem
use check
use graph
use layout
use nir

type Text = struct { data: []u8, count: usize, full: bool }

const KIND_NONE: u8 = 0u8
const KIND_SCALAR: u8 = 1u8
const KIND_PRIVATE: u8 = 2u8
const KIND_BUILTIN: u8 = 3u8
const KIND_SHARED: u8 = 4u8

// How a scalar is held: 1 bool, 2 u8, 3 i8, 4 u16, 5 i16, 6 u32, 7 i32, 8 u64, 9 i64, 10 f32, 11 f64 (not on Metal).
const T_BOOL: u8 = 1u8
const T_F32: u8 = 10u8

type Values = struct {
    kind: []u8,
    ty: []u8,
    // A builtin's number (1 gid, 2 lid, 3 wgid), or a private value's frame offset.
    offset: []usize,
    // The number of the `uint` variable holding a private or shared address's dynamic byte offset; 0 for none.
    dynamic: []usize,
}

type Module = struct {
    body: Text,
    code: Text,
    kernels: usize,
    checked: bool,
    dynamics: usize,
    frame_bytes: usize,
    has_shared: bool,
    failure: str,
}

error Unsupported

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn fail(m: *Module, message: str) -> err {
    m.failure = message
    ret Unsupported
}

// ---- text --------------------------------------------------------------------

fn put(t: *Text, value: str) {
    var at = 0usize
    while at < value.len {
        if t.count >= t.data.len {
            t.full = true
            ret
        }
        t.data[t.count] = value[at]
        t.count += 1usize
        at += 1usize
    }
}

fn put_number(t: *Text, value: usize) {
    if value >= 10usize { put_number(t, value / 10usize) }
    var digit: [1]u8 = zero
    digit[0usize] = u8(48usize + value % 10usize)
    put(t, digit[0usize..1usize])
}

// `0x` and eight hex digits, for a float's bits and big constants.
fn put_hex(t: *Text, value: usize) {
    put(t, "0x")
    let digits = "0123456789abcdef"
    var shift = 28usize
    var started = false
    while true {
        let nibble = (value >> shift) & 15usize
        var one: [1]u8 = zero
        one[0usize] = digits[nibble]
        put(t, one[0usize..1usize])
        if shift == 0usize { break }
        shift -= 4usize
    }
}

fn line(t: *Text, value: str) {
    put(t, "      ")
    put(t, value)
    put(t, "\n")
}

// ---- types ---------------------------------------------------------------------

fn type_name(code: u8) -> str {
    if code == 1u8 { ret "bool" }
    if code == 2u8 { ret "uchar" }
    if code == 3u8 { ret "char" }
    if code == 4u8 { ret "ushort" }
    if code == 5u8 { ret "short" }
    if code == 6u8 { ret "uint" }
    if code == 7u8 { ret "int" }
    if code == 8u8 { ret "ulong" }
    if code == 9u8 { ret "long" }
    if code == 10u8 { ret "float" }
    ret ""
}

fn type_bytes(code: u8) -> usize {
    if code == 1u8 || code == 2u8 || code == 3u8 { ret 1usize }
    if code == 4u8 || code == 5u8 { ret 2usize }
    if code == 8u8 || code == 9u8 { ret 8usize }
    ret 4usize
}

fn is_signed(code: u8) -> bool {
    ret code == 3u8 || code == 5u8 || code == 7u8 || code == 9u8
}

fn is_float(code: u8) -> bool {
    ret code == 10u8
}

// The scalar code a NIR type is held in; 0 when this emitter cannot hold it.
fn value_type(ty: check.Type) -> u8 {
    if ty.kind == .Bool { ret 1u8 }
    if ty.kind == .Err { ret 6u8 }
    if ty.kind == .Named && (same(ty.name, "Ordering") || same(ty.name, "Scope")) { ret 6u8 }
    if ty.kind == .Pointer {
        if ty.in_shared { ret 6u8 }
        ret 8u8
    }
    if ty.kind == .Float {
        if same(ty.name, "f32") { ret 10u8 }
        ret 0u8
    }
    if ty.kind == .Integer {
        if same(ty.name, "u8") { ret 2u8 }
        if same(ty.name, "i8") { ret 3u8 }
        if same(ty.name, "u16") { ret 4u8 }
        if same(ty.name, "i16") { ret 5u8 }
        if same(ty.name, "u32") || same(ty.name, "usize") { ret 6u8 }
        if same(ty.name, "i32") || same(ty.name, "isize") { ret 7u8 }
        if same(ty.name, "u64") { ret 8u8 }
        if same(ty.name, "i64") { ret 9u8 }
    }
    ret 0u8
}

fn aggregate(ty: check.Type) -> bool {
    ret ty.kind == .Slice || ty.kind == .Named || ty.kind == .Array || ty.kind == .String
}

fn aggregate_bytes(c: *check.Checker, ty: check.Type) -> (usize, err) {
    if ty.kind == .Slice || ty.kind == .String { ret (16usize, ok) }
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret (0usize, info_error) }
    ret ((info.size + 3usize) / 4usize * 4usize, ok)
}

// ---- the module ------------------------------------------------------------------

// Every kernel among the builder's functions from `first` on, written as MSL source. `message` says why when it fails.
fn emit(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, first: usize, message: *str, has_checks: *bool) -> ([]u8, err) {
    var no_bytes: []u8 = zero
    var m: Module = zero
    *has_checks = false
    let (body, body_error) = mem.alloc[u8](a, 4194304usize)
    if body_error != ok { ret (no_bytes, body_error) }
    let (code, code_error) = mem.alloc[u8](a, 4194304usize)
    if code_error != ok { ret (no_bytes, code_error) }
    m.body.data = body
    m.code.data = code
    var function_at = first
    var kernels = 0usize
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        let (index, found) = check.find_function(c, function.module_index, function.name)
        if found && c.functions[index].gpu { kernels += 1usize }
        function_at += 1usize
    }
    if kernels == 0usize {
        *message = "the program has no kernel to write as MSL"
        ret (no_bytes, Unsupported)
    }
    // A helper call has no body here yet.
    function_at = first
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        let (index, found) = check.find_function(c, function.module_index, function.name)
        var instruction_at = function.first_instruction
        if !found || !c.functions[index].gpu { instruction_at = function.first_instruction + function.instruction_count }
        while instruction_at < function.first_instruction + function.instruction_count {
            if builder.instructions[instruction_at].opcode == .Call {
                *message = "a kernel calls a helper, which the MSL emitter does not write yet"
                ret (no_bytes, Unsupported)
            }
            instruction_at += 1usize
        }
        function_at += 1usize
    }
    m.checked = !builder.nocheck && reachable_checked(builder, first)
    *has_checks = m.checked
    put(&m.body, "#include <metal_stdlib>\nusing namespace metal;\n\n")
    function_at = first
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        let (index, found) = check.find_function(c, function.module_index, function.name)
        if found && c.functions[index].gpu {
            let kernel_error = emit_kernel(a, &m, c, g, builder, function_at, index)
            if kernel_error != ok {
                *message = m.failure
                ret (no_bytes, kernel_error)
            }
        }
        function_at += 1usize
    }
    if m.body.full || m.code.full {
        *message = "the MSL source is longer than the emitter's buffer"
        ret (no_bytes, mem.Exhausted)
    }
    ret (m.body.data[0usize..m.body.count], ok)
}

// Whether any trap, bounds check or slice check can write a fault.
fn reachable_checked(builder: *nir.Builder, first: usize) -> bool {
    var function_at = first
    while function_at < builder.function_count {
        let function = builder.functions[function_at]
        var at = function.first_instruction
        while at < function.first_instruction + function.instruction_count {
            let instruction = builder.instructions[at]
            if instruction.opcode == .Trap { ret true }
            if instruction.opcode == .IndexAddress && instruction.operand_count >= 3usize && !instruction.nocheck { ret true }
            if instruction.opcode == .Slice && !instruction.nocheck { ret true }
            at += 1usize
        }
        function_at += 1usize
    }
    ret false
}

// `module.name` with the dot MSL does not allow written as an underscore: the runtime looks the entry up the same way.
fn put_entry_name(t: *Text, g: *graph.Graph, kernel: check.Function) {
    var module_name = ""
    if kernel.module_index < g.count { module_name = g.modules[kernel.module_index].name }
    var at = 0usize
    while at < module_name.len {
        var one: [1]u8 = zero
        one[0usize] = module_name[at]
        if one[0usize] == 46u8 { one[0usize] = 95u8 }
        put(t, one[0usize..1usize])
        at += 1usize
    }
    put(t, "_")
    put(t, kernel.name)
}

fn init_values(a: *mem.Arena, values: *Values, count: usize) -> err {
    let (kinds, kinds_error) = mem.alloc[u8](a, count)
    if kinds_error != ok { ret kinds_error }
    let (tys, tys_error) = mem.alloc[u8](a, count)
    if tys_error != ok { ret tys_error }
    let (offsets, offsets_error) = mem.alloc[usize](a, count)
    if offsets_error != ok { ret offsets_error }
    let (dynamics, dynamics_error) = mem.alloc[usize](a, count)
    if dynamics_error != ok { ret dynamics_error }
    var at = 0usize
    while at < count {
        kinds[at] = KIND_NONE
        tys[at] = 0u8
        offsets[at] = 0usize
        dynamics[at] = 0usize
        at += 1usize
    }
    values.kind = kinds
    values.ty = tys
    values.offset = offsets
    values.dynamic = dynamics
    ret ok
}

fn operand(builder: *nir.Builder, instruction: nir.Instruction, index: usize) -> usize {
    ret builder.operands[instruction.first_operand + index]
}

fn scalar(values: *Values, value: usize, ty: u8) {
    values.kind[value] = KIND_SCALAR
    values.ty[value] = ty
}

fn emit_kernel(a: *mem.Arena, m: *Module, c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, function_at: usize, checked: usize) -> err {
    let function = builder.functions[function_at]
    let kernel = c.functions[checked]
    var values: Values = zero
    try init_values(a, &values, function.value_count + 1usize)
    m.code.count = 0usize
    m.dynamics = 0usize
    m.frame_bytes = 0usize
    m.has_shared = false
    // Frame offsets: every private slot and aggregate parameter, in order, eight-byte aligned.
    var at = 0usize
    while at < function.instruction_count {
        let instruction = builder.instructions[function.first_instruction + at]
        var bytes = 0usize
        if instruction.opcode == .Stack {
            if instruction.ty.in_shared && instruction.ty.kind == .Integer {
                if instruction.immediate != 0usize {
                    values.kind[instruction.result] = KIND_SHARED
                    m.has_shared = true
                }
                at += 1usize
                continue
            }
            bytes = instruction.immediate * 8usize
            if bytes == 0usize { bytes = 8usize }
        }
        if instruction.opcode == .Parameter && aggregate(instruction.ty) {
            let (held, held_error) = aggregate_bytes(c, instruction.ty)
            if held_error != ok { ret held_error }
            bytes = held
        }
        if bytes != 0usize && instruction.has_result {
            values.kind[instruction.result] = KIND_PRIVATE
            values.offset[instruction.result] = m.frame_bytes
            m.frame_bytes += (bytes + 7usize) / 8usize * 8usize
        }
        at += 1usize
    }
    // The blocks, each a case of the dispatch.
    var block_index = 0usize
    while block_index < function.block_count {
        put(&m.code, "    case ")
        put_number(&m.code, block_index)
        put(&m.code, ": {\n")
        let record = builder.blocks[function.first_block + block_index]
        var instruction_at = 0usize
        while instruction_at < record.instruction_count {
            let instruction = builder.instructions[record.first_instruction + instruction_at]
            try emit_instruction(m, c, builder, function, kernel, instruction, &values)
            instruction_at += 1usize
        }
        put(&m.code, "    }\n")
        block_index += 1usize
    }
    // The kernel: signature, variables, then the dispatch.
    put(&m.body, "kernel void ")
    put_entry_name(&m.body, g, kernel)
    put(&m.body, "(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]]")
    if m.has_shared { put(&m.body, ", threadgroup uchar* tg [[threadgroup(0)]]") }
    put(&m.body, ") {\n")
    if m.frame_bytes != 0usize {
        put(&m.body, "  thread ulong fr_words[")
        put_number(&m.body, m.frame_bytes / 8usize)
        put(&m.body, "];\n  thread uchar* fr = (thread uchar*)fr_words;\n")
        put(&m.body, "  for (uint z = 0u; z < ")
        put_number(&m.body, m.frame_bytes / 8usize)
        put(&m.body, "u; z += 1u) fr_words[z] = 0ul;\n")
    }
    var value_at = 0usize
    while value_at < function.value_count + 1usize {
        if values.kind[value_at] == KIND_SCALAR {
            put(&m.body, "  ")
            put(&m.body, type_name(values.ty[value_at]))
            put(&m.body, " v")
            put_number(&m.body, value_at)
            put(&m.body, ";\n")
        }
        value_at += 1usize
    }
    var dynamic_at = 1usize
    while dynamic_at <= m.dynamics {
        put(&m.body, "  uint d")
        put_number(&m.body, dynamic_at)
        put(&m.body, ";\n")
        dynamic_at += 1usize
    }
    put(&m.body, "  uint pc = 0u;\n  while (true) {\n    switch (pc) {\n")
    var copied = 0usize
    while copied < m.code.count {
        if m.body.count >= m.body.data.len {
            m.body.full = true
            break
        }
        m.body.data[m.body.count] = m.code.data[copied]
        m.body.count += 1usize
        copied += 1usize
    }
    put(&m.body, "    default: return;\n    }\n  }\n}\n\n")
    ret ok
}

// ---- addresses -------------------------------------------------------------------

// A private or shared address as `base + constant + dynamic`, the base `fr` or `tg`.
fn put_private_address(t: *Text, values: *Values, address: usize, extra: usize) {
    var base = "fr"
    if values.kind[address] == KIND_SHARED { base = "tg" }
    put(t, "(")
    put(t, base)
    put(t, " + ")
    put_number(t, values.offset[address] + extra)
    put(t, "u")
    if values.dynamic[address] != 0usize {
        put(t, " + d")
        put_number(t, values.dynamic[address])
    }
    put(t, ")")
}

fn space_of(values: *Values, address: usize) -> str {
    if values.kind[address] == KIND_SHARED { ret "threadgroup" }
    ret "thread"
}

// ---- instructions ----------------------------------------------------------------

fn write_fault(m: *Module, kind: usize, site: usize) {
    let t = &m.code
    line(t, "{")
    line(t, "  device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);")
    line(t, "  uint expected = 0u;")
    line(t, "  if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {")
    put(t, "      *(device uchar*)((device uchar*)count + 8) = ")
    put_number(t, kind)
    put(t, ";\n      *(device uint*)((device uchar*)count + 12) = ")
    put_number(t, site)
    put(t, "u;\n")
    line(t, "      *(device uint*)((device uchar*)count + 16) = gid3.x;")
    line(t, "      *(device uint*)((device uchar*)count + 20) = gid3.y;")
    line(t, "      *(device uint*)((device uchar*)count + 24) = gid3.z;")
    line(t, "  } else {")
    line(t, "      atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);")
    line(t, "  }")
    line(t, "}")
}

// A check that records a fault and returns from the invocation when `holds` is false.
fn guard(m: *Module, holds: str, value_a: usize, value_b: usize, kind: usize, site: usize) {
    let t = &m.code
    put(t, "      if (!(v")
    put_number(t, value_a)
    put(t, " ")
    put(t, holds)
    put(t, " v")
    put_number(t, value_b)
    put(t, ")) {\n")
    write_fault(m, kind, site)
    line(t, "  return;")
    line(t, "}")
}

fn emit_instruction(m: *Module, c: *check.Checker, builder: *nir.Builder, function: nir.Function, kernel: check.Function, instruction: nir.Instruction, values: *Values) -> err {
    let opcode = instruction.opcode
    let t = &m.code
    if opcode == .Stack { ret ok }
    if opcode == .Parameter { ret emit_parameter(m, c, kernel, instruction, values) }
    if opcode == .Barrier {
        line(t, "threadgroup_barrier(mem_flags::mem_threadgroup);")
        ret ok
    }
    if opcode == .ConstInteger || opcode == .ConstFloat || opcode == .ConstBool || (opcode == .Zero && instruction.has_result) {
        let ty = value_type(instruction.ty)
        if ty == 0u8 { ret fail(m, "a constant of this type is not yet written as MSL") }
        scalar(values, instruction.result, ty)
        put(t, "      v")
        put_number(t, instruction.result)
        put(t, " = ")
        var bits = instruction.immediate
        if opcode == .Zero { bits = 0usize }
        if ty == T_BOOL {
            if bits != 0usize { put(t, "true") } else { put(t, "false") }
        } else if is_float(ty) {
            put(t, "as_type<float>(")
            put_hex(t, bits)
            put(t, "u)")
        } else {
            put(t, "(")
            put(t, type_name(ty))
            put(t, ")")
            put_number(t, bits)
            if type_bytes(ty) == 8usize { put(t, "ul") } else { put(t, "u") }
        }
        put(t, ";\n")
        ret ok
    }
    if opcode == .Zero {
        let address = operand(builder, instruction, 0usize)
        if values.kind[address] != KIND_PRIVATE && values.kind[address] != KIND_SHARED { ret fail(m, "an aggregate zero has no private or shared destination") }
        put(t, "      for (uint z = 0u; z < ")
        put_number(t, instruction.immediate)
        put(t, "u; z += 1u) *(")
        put(t, space_of(values, address))
        put(t, " uchar*)(")
        put_private_address(t, values, address, 0usize)
        put(t, " + z) = 0;\n")
        ret ok
    }
    if opcode == .GlobalAddress { ret emit_global_address(m, builder, instruction, values) }
    if opcode == .FieldAddress { ret emit_field_address(m, builder, instruction, values) }
    if opcode == .IndexAddress { ret emit_index_address(m, builder, instruction, values) }
    if opcode == .Slice { ret emit_slice(m, builder, instruction, values) }
    if opcode == .Load { ret emit_load(m, builder, instruction, values) }
    if opcode == .Store { ret emit_store(m, builder, instruction, values) }
    if opcode == .Cast { ret emit_cast(m, builder, instruction, values) }
    if opcode == .Add || opcode == .AddWrap || opcode == .Subtract || opcode == .SubtractWrap || opcode == .Multiply || opcode == .MultiplyWrap || opcode == .Divide || opcode == .Remainder || opcode == .BitAnd || opcode == .BitOr || opcode == .BitXor || opcode == .ShiftLeft || opcode == .ShiftRight { ret emit_binary(m, builder, instruction, values) }
    if opcode == .Equal || opcode == .NotEqual || opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual { ret emit_compare(m, builder, instruction, values) }
    if opcode == .Negate || opcode == .BitNot { ret emit_unary(m, builder, instruction, values) }
    if opcode == .Copy { ret emit_copy(m, builder, instruction, values) }
    if opcode == .Return {
        if instruction.operand_count != 0usize { ret fail(m, "a kernel returns a value") }
        line(t, "return;")
        ret ok
    }
    if opcode == .Branch {
        put(t, "      pc = ")
        put_number(t, instruction.target - function.first_block)
        put(t, "u; continue;\n")
        ret ok
    }
    if opcode == .BranchIf {
        let condition = operand(builder, instruction, 0usize)
        put(t, "      if (")
        if values.kind[condition] == KIND_SHARED {
            put(t, "true")
        } else if values.kind[condition] == KIND_SCALAR {
            put(t, "v")
            put_number(t, condition)
            if values.ty[condition] != T_BOOL { put(t, " != 0") }
        } else {
            ret fail(m, "a branch has no condition value")
        }
        put(t, ") { pc = ")
        put_number(t, instruction.target - function.first_block)
        put(t, "u; } else { pc = ")
        put_number(t, instruction.target2 - function.first_block)
        put(t, "u; }\n      continue;\n")
        ret ok
    }
    if opcode == .Trap {
        var kind = 99usize
        if same(instruction.ty.name, "null") { kind = 1usize }
        if same(instruction.ty.name, "tag") || same(instruction.ty.name, "enum") || same(instruction.ty.name, "invalid") { kind = 2usize }
        if same(instruction.ty.name, "align") { kind = 3usize }
        if same(instruction.ty.name, "overflow") { kind = 4usize }
        if same(instruction.ty.name, "divide") { kind = 5usize }
        if kind == 99usize { ret fail(m, "this trap kind is not yet written as a device fault") }
        write_fault(m, kind, instruction.site.line)
        line(t, "return;")
        ret ok
    }
    if opcode == .Phi { ret fail(m, "a phi operation is not yet written as MSL") }
    if opcode == .Switch { ret fail(m, "a switch is not yet written as MSL") }
    if opcode == .Unreachable { ret fail(m, "an unreachable operation is not yet written as MSL") }
    if opcode == .Sqrt { ret fail(m, "a square root is not yet written as MSL: it must match the CPU to the last bit") }
    if opcode == .Extract || opcode == .Bitcast || opcode == .AtomicLoad || opcode == .AtomicStore || opcode == .AtomicRmw || opcode == .AtomicCas || opcode == .AtomicFence || opcode == .MemoryBarrier || opcode == .Subgroup { ret fail(m, "an operation in this kernel is not yet written as MSL") }
    ret fail(m, "an operation in this kernel is not yet written as MSL")
}

// A parameter from the argument block: a scalar loaded, a slice's header copied into its frame slot.
fn emit_parameter(m: *Module, c: *check.Checker, kernel: check.Function, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let index = instruction.immediate
    var offset = 0usize
    if m.checked { offset = 8usize }
    var at = 0usize
    while at <= index {
        let ty = c.parameters[kernel.first_parameter + at].ty
        var size = 16usize
        var align = 8usize
        if aggregate(ty) {
            if ty.kind != .Slice { ret fail(m, "a kernel parameter of this type is not yet written as MSL") }
        } else {
            let held = value_type(ty)
            if held == 0u8 || held == T_BOOL { ret fail(m, "a kernel parameter of this type is not yet written as MSL") }
            size = type_bytes(held)
            align = size
        }
        offset = (offset + align - 1usize) / align * align
        if at == index { break }
        offset += size
        at += 1usize
    }
    if !aggregate(instruction.ty) {
        let ty = value_type(instruction.ty)
        if ty == 0u8 { ret fail(m, "a kernel parameter of this type is not yet written as MSL") }
        scalar(values, instruction.result, ty)
        put(t, "      v")
        put_number(t, instruction.result)
        put(t, " = *(device const ")
        put(t, type_name(ty))
        put(t, "*)(args + ")
        put_number(t, offset)
        put(t, "u);\n")
        ret ok
    }
    if values.kind[instruction.result] != KIND_PRIVATE { ret fail(m, "a slice parameter has no frame slot") }
    let slot = values.offset[instruction.result]
    put(t, "      *(thread ulong*)(fr + ")
    put_number(t, slot)
    put(t, "u) = *(device const ulong*)(args + ")
    put_number(t, offset)
    put(t, "u);\n      *(thread uint*)(fr + ")
    put_number(t, slot + 8usize)
    put(t, "u) = *(device const uint*)(args + ")
    put_number(t, offset + 8usize)
    put(t, "u);\n      *(thread uint*)(fr + ")
    put_number(t, slot + 12usize)
    put(t, "u) = 0u;\n")
    ret ok
}

fn emit_global_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let index = instruction.immediate
    if index >= builder.global_count { ret fail(m, "a kernel names a global that is not there") }
    let global = builder.globals[index]
    var which = 0usize
    if same(global.name, "gid") { which = 1usize }
    if same(global.name, "lid") { which = 2usize }
    if same(global.name, "wgid") { which = 3usize }
    if which == 0usize { ret fail(m, "a kernel reads a module-scope variable other than the invocation ids") }
    values.kind[instruction.result] = KIND_BUILTIN
    values.offset[instruction.result] = which
    ret ok
}

fn emit_field_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let base = operand(builder, instruction, 0usize)
    let result = instruction.result
    if values.kind[base] == KIND_PRIVATE || values.kind[base] == KIND_SHARED {
        values.kind[result] = values.kind[base]
        values.offset[result] = values.offset[base] + instruction.immediate
        values.dynamic[result] = values.dynamic[base]
        ret ok
    }
    if values.kind[base] == KIND_BUILTIN {
        // A builtin's component: the offset is kept beside the builtin's number.
        values.kind[result] = KIND_BUILTIN
        values.offset[result] = values.offset[base] + instruction.immediate * 4usize
        ret ok
    }
    if values.kind[base] != KIND_SCALAR { ret fail(m, "a field address has no base") }
    scalar(values, result, 8u8)
    put(&m.code, "      v")
    put_number(&m.code, result)
    put(&m.code, " = v")
    put_number(&m.code, base)
    put(&m.code, " + ")
    put_number(&m.code, instruction.immediate)
    put(&m.code, "ul;\n")
    ret ok
}

fn emit_index_address(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let base = operand(builder, instruction, 0usize)
    let index = operand(builder, instruction, 1usize)
    let result = instruction.result
    if values.kind[index] != KIND_SCALAR { ret fail(m, "an index has no value") }
    if instruction.operand_count >= 3usize && !instruction.nocheck {
        let length = operand(builder, instruction, 2usize)
        guard(m, "<", index, length, 0usize, instruction.site.line)
    }
    if values.kind[base] == KIND_PRIVATE || values.kind[base] == KIND_SHARED {
        m.dynamics += 1usize
        put(t, "      d")
        put_number(t, m.dynamics)
        put(t, " = ")
        if values.dynamic[base] != 0usize {
            put(t, "d")
            put_number(t, values.dynamic[base])
            put(t, " + ")
        }
        put(t, "(uint)v")
        put_number(t, index)
        put(t, " * ")
        put_number(t, instruction.immediate)
        put(t, "u;\n")
        values.kind[result] = values.kind[base]
        values.offset[result] = values.offset[base]
        values.dynamic[result] = m.dynamics
        ret ok
    }
    if values.kind[base] != KIND_SCALAR { ret fail(m, "an indexed address has no base") }
    if value_bytes_of(values, index) != 4usize { ret fail(m, "an index wider than 32 bits is not yet written as MSL") }
    scalar(values, result, 8u8)
    put(t, "      v")
    put_number(t, result)
    put(t, " = v")
    put_number(t, base)
    put(t, " + (ulong)v")
    put_number(t, index)
    put(t, " * ")
    put_number(t, instruction.immediate)
    put(t, "ul;\n")
    ret ok
}

fn value_bytes_of(values: *Values, value: usize) -> usize {
    ret type_bytes(values.ty[value])
}

fn emit_slice(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    if instruction.operand_count != 5usize || instruction.immediate == 0usize { ret fail(m, "a slice has an unexpected shape") }
    let destination = operand(builder, instruction, 0usize)
    let data = operand(builder, instruction, 1usize)
    let length = operand(builder, instruction, 2usize)
    let lower = operand(builder, instruction, 3usize)
    let upper = operand(builder, instruction, 4usize)
    if values.kind[destination] != KIND_PRIVATE { ret fail(m, "a slice has no private header") }
    if values.kind[length] != KIND_SCALAR || values.kind[lower] != KIND_SCALAR || values.kind[upper] != KIND_SCALAR { ret fail(m, "a slice has no bounds") }
    if !instruction.nocheck {
        guard(m, "<=", lower, upper, 0usize, instruction.site.line)
        guard(m, "<=", upper, length, 0usize, instruction.site.line)
    }
    let slot = values.offset[destination] + 0usize
    if values.kind[data] == KIND_SHARED {
        put(t, "      *(thread uint*)(fr + ")
        put_number(t, slot)
        put(t, "u) = ")
        put_shared_offset(t, values, data)
        put(t, " + v")
        put_number(t, lower)
        put(t, " * ")
        put_number(t, instruction.immediate)
        put(t, "u;\n      *(thread uint*)(fr + ")
        put_number(t, slot + 4usize)
        put(t, "u) = 0u;\n")
    } else {
        if values.kind[data] != KIND_SCALAR { ret fail(m, "a slice has no device or shared base") }
        put(t, "      *(thread ulong*)(fr + ")
        put_number(t, slot)
        put(t, "u) = v")
        put_number(t, data)
        put(t, " + (ulong)v")
        put_number(t, lower)
        put(t, " * ")
        put_number(t, instruction.immediate)
        put(t, "ul;\n")
    }
    put(t, "      *(thread uint*)(fr + ")
    put_number(t, slot + 8usize)
    put(t, "u) = v")
    put_number(t, upper)
    put(t, " - v")
    put_number(t, lower)
    put(t, ";\n      *(thread uint*)(fr + ")
    put_number(t, slot + 12usize)
    put(t, "u) = 0u;\n")
    ret ok
}

// A shared address as a plain `uint` expression: the constant offset plus the dynamic one.
fn put_shared_offset(t: *Text, values: *Values, address: usize) {
    put_number(t, values.offset[address])
    put(t, "u")
    if values.dynamic[address] != 0usize {
        put(t, " + d")
        put_number(t, values.dynamic[address])
    }
}

fn component(offset: usize) -> str {
    if offset == 0usize { ret "x" }
    if offset == 4usize { ret "y" }
    ret "z"
}

fn emit_load(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let address = operand(builder, instruction, 0usize)
    let result = instruction.result
    if instruction.ty.kind == .Pointer && instruction.ty.in_shared {
        // A workgroup pointer read from a slice header: the header's first word is its offset.
        if values.kind[address] != KIND_PRIVATE || !m.has_shared { ret fail(m, "a shared pointer is not loaded from a slice header") }
        m.dynamics += 1usize
        put(t, "      d")
        put_number(t, m.dynamics)
        put(t, " = *(thread uint*)")
        put_private_address(t, values, address, 0usize)
        put(t, ";\n")
        values.kind[result] = KIND_SHARED
        values.offset[result] = 0usize
        values.dynamic[result] = m.dynamics
        ret ok
    }
    let ty = value_type(instruction.ty)
    if ty == 0u8 { ret fail(m, "a load of this type is not yet written as MSL") }
    if values.kind[address] == KIND_BUILTIN {
        let which = values.offset[address]
        // `which` is the builtin number for the bare address and number plus component for a field of it.
        if ty != 6u8 { ret fail(m, "an invocation id is read in an unexpected shape") }
        let number = which % 4usize
        let part = which / 4usize
        if part > 2usize { ret fail(m, "an invocation id is read in an unexpected shape") }
        var source = "gid3"
        if number == 2usize { source = "lid3" }
        if number == 3usize { source = "wgid3" }
        scalar(values, result, ty)
        put(t, "      v")
        put_number(t, result)
        put(t, " = ")
        put(t, source)
        put(t, ".")
        put(t, component(part * 4usize))
        put(t, ";\n")
        ret ok
    }
    if values.kind[address] == KIND_PRIVATE || values.kind[address] == KIND_SHARED {
        scalar(values, result, ty)
        put(t, "      v")
        put_number(t, result)
        put(t, " = ")
        if ty == T_BOOL {
            put(t, "(*(")
            put(t, space_of(values, address))
            put(t, " uchar*)")
            put_private_address(t, values, address, 0usize)
            put(t, ") != 0")
        } else {
            put(t, "*(")
            put(t, space_of(values, address))
            put(t, " ")
            put(t, type_name(ty))
            put(t, "*)")
            put_private_address(t, values, address, 0usize)
        }
        put(t, ";\n")
        ret ok
    }
    if values.kind[address] != KIND_SCALAR { ret fail(m, "a load has no address") }
    if ty == T_BOOL { ret fail(m, "a bool in device memory is not a device storage type") }
    scalar(values, result, ty)
    put(t, "      v")
    put_number(t, result)
    put(t, " = *(device ")
    put(t, type_name(ty))
    put(t, "*)(heap + v")
    put_number(t, address)
    put(t, ");\n")
    ret ok
}

fn emit_store(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let address = operand(builder, instruction, 0usize)
    let value = operand(builder, instruction, 1usize)
    if values.kind[value] == KIND_SHARED && values.kind[address] == KIND_PRIVATE {
        put(t, "      *(thread uint*)")
        put_private_address(t, values, address, 0usize)
        put(t, " = ")
        put_shared_offset(t, values, value)
        put(t, ";\n")
        ret ok
    }
    if values.kind[value] != KIND_SCALAR { ret fail(m, "a store of an aggregate is not yet written as MSL") }
    let ty = values.ty[value]
    if values.kind[address] == KIND_PRIVATE || values.kind[address] == KIND_SHARED {
        if ty == T_BOOL {
            put(t, "      *(")
            put(t, space_of(values, address))
            put(t, " uchar*)")
            put_private_address(t, values, address, 0usize)
            put(t, " = v")
            put_number(t, value)
            put(t, " ? 1 : 0;\n")
            ret ok
        }
        put(t, "      *(")
        put(t, space_of(values, address))
        put(t, " ")
        put(t, type_name(ty))
        put(t, "*)")
        put_private_address(t, values, address, 0usize)
        put(t, " = v")
        put_number(t, value)
        put(t, ";\n")
        ret ok
    }
    if values.kind[address] != KIND_SCALAR { ret fail(m, "a store has no address") }
    if ty == T_BOOL { ret fail(m, "a bool in device memory is not a device storage type") }
    put(t, "      *(device ")
    put(t, type_name(ty))
    put(t, "*)(heap + v")
    put_number(t, address)
    put(t, ") = v")
    put_number(t, value)
    put(t, ";\n")
    ret ok
}

fn emit_copy(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let t = &m.code
    let destination = operand(builder, instruction, 0usize)
    let source = operand(builder, instruction, 1usize)
    if (values.kind[destination] != KIND_PRIVATE && values.kind[destination] != KIND_SHARED) || (values.kind[source] != KIND_PRIVATE && values.kind[source] != KIND_SHARED) { ret fail(m, "an aggregate copy has no private or shared operand") }
    put(t, "      for (uint z = 0u; z < ")
    put_number(t, instruction.immediate)
    put(t, "u; z += 1u) *(")
    put(t, space_of(values, destination))
    put(t, " uchar*)(")
    put_private_address(t, values, destination, 0usize)
    put(t, " + z) = *(")
    put(t, space_of(values, source))
    put(t, " uchar*)(")
    put_private_address(t, values, source, 0usize)
    put(t, " + z);\n")
    ret ok
}

fn emit_cast(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    let ty = value_type(instruction.ty)
    if ty == 0u8 || values.kind[source] != KIND_SCALAR { ret fail(m, "a conversion of this type is not yet written as MSL") }
    let from = values.ty[source]
    if (from == 8u8 || ty == 8u8) && from != ty && (instruction.ty.kind == .Pointer || from == 8u8 && false) { ret fail(m, "a conversion between an address and an integer is not written as MSL") }
    scalar(values, instruction.result, ty)
    put(&m.code, "      v")
    put_number(&m.code, instruction.result)
    put(&m.code, " = ")
    if ty == T_BOOL {
        put(&m.code, "v")
        put_number(&m.code, source)
        put(&m.code, " != 0")
    } else {
        put(&m.code, "(")
        put(&m.code, type_name(ty))
        put(&m.code, ")v")
        put_number(&m.code, source)
    }
    put(&m.code, ";\n")
    ret ok
}

fn emit_binary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    let ty = value_type(instruction.ty)
    if ty == 0u8 || values.kind[left] != KIND_SCALAR || values.kind[right] != KIND_SCALAR { ret fail(m, "an arithmetic operation of this type is not yet written as MSL") }
    if ty == T_BOOL { ret fail(m, "an integer operation is not yet written as MSL") }
    let opcode = instruction.opcode
    var symbol = ""
    if opcode == .Add || opcode == .AddWrap { symbol = "+" }
    if opcode == .Subtract || opcode == .SubtractWrap { symbol = "-" }
    if opcode == .Multiply || opcode == .MultiplyWrap { symbol = "*" }
    if is_float(ty) {
        // Division and the other exact float sequences are the CPU's until they are written.
        if symbol.len == 0usize { ret fail(m, "a float operation is not yet written as MSL") }
    } else {
        if opcode == .Divide { symbol = "/" }
        if opcode == .Remainder { symbol = "%" }
        if opcode == .BitAnd { symbol = "&" }
        if opcode == .BitOr { symbol = "|" }
        if opcode == .BitXor { symbol = "^" }
        if opcode == .ShiftLeft { symbol = "<<" }
        if opcode == .ShiftRight { symbol = ">>" }
    }
    if symbol.len == 0usize { ret fail(m, "an integer operation is not yet written as MSL") }
    scalar(values, instruction.result, ty)
    put(&m.code, "      v")
    put_number(&m.code, instruction.result)
    put(&m.code, " = (")
    put(&m.code, type_name(ty))
    put(&m.code, ")(v")
    put_number(&m.code, left)
    put(&m.code, " ")
    put(&m.code, symbol)
    put(&m.code, " v")
    put_number(&m.code, right)
    put(&m.code, ");\n")
    ret ok
}

fn emit_compare(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let left = operand(builder, instruction, 0usize)
    let right = operand(builder, instruction, 1usize)
    if values.kind[left] != KIND_SCALAR || values.kind[right] != KIND_SCALAR { ret fail(m, "a comparison has no operands") }
    if values.ty[left] == T_BOOL { ret fail(m, "a bool comparison is not yet written as MSL") }
    let opcode = instruction.opcode
    var symbol = "=="
    if opcode == .NotEqual { symbol = "!=" }
    if opcode == .Less { symbol = "<" }
    if opcode == .LessEqual { symbol = "<=" }
    if opcode == .Greater { symbol = ">" }
    if opcode == .GreaterEqual { symbol = ">=" }
    scalar(values, instruction.result, T_BOOL)
    put(&m.code, "      v")
    put_number(&m.code, instruction.result)
    put(&m.code, " = v")
    put_number(&m.code, left)
    put(&m.code, " ")
    put(&m.code, symbol)
    put(&m.code, " v")
    put_number(&m.code, right)
    put(&m.code, ";\n")
    ret ok
}

fn emit_unary(m: *Module, builder: *nir.Builder, instruction: nir.Instruction, values: *Values) -> err {
    let source = operand(builder, instruction, 0usize)
    if values.kind[source] != KIND_SCALAR { ret fail(m, "a unary operation has no operand") }
    let ty = values.ty[source]
    scalar(values, instruction.result, ty)
    put(&m.code, "      v")
    put_number(&m.code, instruction.result)
    put(&m.code, " = ")
    if ty == T_BOOL {
        if instruction.opcode != .BitNot { ret fail(m, "a bool operation is not yet written as MSL") }
        put(&m.code, "!v")
    } else if instruction.opcode == .Negate {
        put(&m.code, "(")
        put(&m.code, type_name(ty))
        put(&m.code, ")(-v")
        put_number(&m.code, source)
        put(&m.code, ");\n")
        ret ok
    } else {
        put(&m.code, "(")
        put(&m.code, type_name(ty))
        put(&m.code, ")(~v")
        put_number(&m.code, source)
        put(&m.code, ");\n")
        ret ok
    }
    put_number(&m.code, source)
    put(&m.code, ";\n")
    ret ok
}
