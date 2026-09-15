// Checked syntax to canonical NIR lowering. The initial slice lowers parameters and
// literal returns; later increments extend expressions and structured control flow.

use artifact_hash
use check
use e.mem
use decimal
use graph
use layout
use lex
use nir
use parse
use resolve
use syntax

error FunctionNotFound

type Binding = struct {
    name: str,
    ty: check.Type,
    value: usize,
    address: bool,
}

type CallResults = struct {
    call: check.CallInfo,
    values: [16]usize,
    addresses: [16]bool,
    count: usize,
}

type DeferredKind = enum u8 {
    Invalid,
    Call,
    Statement,
    Block,
}

type Deferred = struct {
    kind: DeferredKind,
    call: check.CallInfo,
    callee: usize,
    arguments: [16]usize,
    argument_count: usize,
    token: lex.Token,
    node_index: usize,
}

type DeferState = struct {
    entries: [256]Deferred,
    count: usize,
}

type ReturnLayout = struct {
    offsets: [16]usize,
    size: usize,
    alignment: usize,
    via_slot: bool,
}

type LoopControl = struct {
    active: bool,
    continue_target: usize,
    break_defer_base: usize,
    continue_defer_base: usize,
    breaks: []usize,
    break_count: usize,
}

fn find_binding(bindings: []Binding, count: usize, name: str) -> (Binding, bool) {
    var empty: Binding = zero
    var at = count
    while at > 0usize {
        at = at - 1usize
        if check.same(bindings[at].name, name) { ret (bindings[at], true) }
    }
    ret (empty, false)
}

fn add_binding(bindings: []Binding, count: *usize, binding: Binding) -> err {
    if *count == bindings.len { ret check.Capacity }
    bindings[*count] = binding
    *count += 1usize
    ret ok
}

fn bind_value(c: *check.Checker, g: *graph.Graph, module_index: usize, token: lex.Token, ty: check.Type, value: usize, address_value: bool, mutable: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    if token.kind == .PunctUnderscore { ret ok }
    if token.kind != .Identifier { ret parse.InvalidSyntax }
    var stored_value = value
    var address = address_value
    if aggregate_value(c, ty) {
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        var slots = (info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, ty, true, slots, token)
        if stack_error != ok { ret stack_error }
        let (copy_instruction, ignored, copy_error) = nir.emit(builder, .Copy, ty, false, info.size, token)
        if copy_error != ok { ret copy_error }
        try nir.add_operand(builder, copy_instruction, stack)
        try nir.add_operand(builder, copy_instruction, value)
        stored_value = stack
        address = true
    } else {
    if mutable && !address {
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, ty, true, 0usize, token)
        if stack_error != ok { ret stack_error }
        let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, ty, false, info.size, token)
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, value)
        stored_value = stack
        address = true
    }
    }
    let name = g.modules[module_index].text[token.start..token.end]
    try add_binding(bindings, binding_count, Binding { name: name, ty: ty, value: stored_value, address: address })
    ret check.add_local(c, name, ty, mutable)
}

fn bind_call_results(c: *check.Checker, g: *graph.Graph, module_index: usize, binding_node: syntax.Node, results: *CallResults, mutable: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    var result_at = 0usize
    var token_at = usize(binding_node.token_start)
    while token_at < usize(binding_node.token_end) {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if result_at >= results.count { ret check.ArgumentCount }
            let (ty, type_error) = check.call_return(c, results.call, result_at)
            if type_error != ok { ret type_error }
            try bind_value(c, g, module_index, token, ty, results.values[result_at], results.addresses[result_at], mutable, builder, bindings, binding_count)
            result_at += 1usize
        }
        token_at += 1usize
    }
    if result_at != results.count { ret check.ArgumentCount }
    ret ok
}

fn declaration_name(c: *check.Checker, text: str, node: syntax.Node) -> (str, err) {
    let name_index = usize(node.token_start) + 1usize
    if name_index >= usize(node.token_end) || name_index >= c.token_count { ret ("", parse.InvalidSyntax) }
    let token = c.tokens[name_index]
    if token.kind != .Identifier { ret ("", parse.InvalidSyntax) }
    ret (text[token.start..token.end], ok)
}

fn literal(c: *check.Checker, text: str, node: syntax.Node, expected: check.Type, builder: *nir.Builder) -> (usize, err) {
    if node.kind != .LiteralExpr || usize(node.token_start) >= c.token_count { ret (0usize, check.Unsupported) }
    let token = c.tokens[usize(node.token_start)]
    // Section 4: `nil` is the zero pointer and the empty slice, which is exactly what
    // `zero` is for those two types, so it lowers the same way.
    if (token.kind == .KwZero || token.kind == .KwNil) && aggregate_value(c, expected) {
        let (info, info_error) = layout.type_info(c, expected)
        if info_error != ok { ret (0usize, info_error) }
        var slots = (info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, expected, true, slots, token)
        if stack_error != ok { ret (0usize, stack_error) }
        let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, expected, false, info.size, token)
        if zero_error != ok { ret (0usize, zero_error) }
        let operand_error = nir.add_operand(builder, zero_instruction, stack)
        if operand_error != ok { ret (0usize, operand_error) }
        ret (stack, ok)
    }
    var opcode: nir.Opcode = .Invalid
    var immediate = 0usize
    var ty = expected
    if token.kind == .KwOk {
        opcode = .ConstError
    } else {
        if token.kind == .KwTrue || token.kind == .KwFalse {
            opcode = .ConstBool
            if token.kind == .KwTrue { immediate = 1usize }
        } else {
            if token.kind == .KwZero || token.kind == .KwNil {
                opcode = .Zero
            } else {
                if token.kind == .String || token.kind == .RawString {
                    opcode = .ConstString
                    let (string_index, string_error) = nir.intern_string(builder, text[token.start..token.end])
                    if string_error != ok { ret (0usize, string_error) }
                    immediate = string_index
                } else {
                    if token.kind == .Float {
                        let (pattern, pattern_type, pattern_error) = float_literal_bits(c, text, node, ty)
                        if pattern_error != ok { ret (0usize, pattern_error) }
                        opcode = .ConstFloat
                        immediate = pattern
                        ty = pattern_type
                    } else {
                    if token.kind != .Integer { ret (0usize, check.Unsupported) }
                    let (value, literal_type, value_error) = check.integer_literal_value(c, text, node)
                    if value_error != ok { ret (0usize, value_error) }
                    opcode = .ConstInteger
                    immediate = value
                    if ty.kind == .Invalid { ty = literal_type }
                    }
                }
            }
        }
    }
    let (instruction, result, emit_error) = nir.emit(builder, opcode, ty, true, immediate, token)
    if emit_error != ok { ret (0usize, emit_error) }
    ret (result, ok)
}

// A comptime `str` parameter is a string literal bound at the call site, so reading
// one in the body is the same as writing that literal there: it interns and lowers
// exactly as any other does, escapes and all.
fn lower_comptime_text(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, spelling: str, token: lex.Token, builder: *nir.Builder) -> (usize, check.Type, err) {
    let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if type_error != ok { ret (0usize, result_type, type_error) }
    let (text_index, text_index_error) = nir.intern_string(builder, spelling)
    if text_index_error != ok { ret (0usize, result_type, text_index_error) }
    let (instruction, result, emit_error) = nir.emit(builder, .ConstString, result_type, true, text_index, token)
    ret (result, result_type, emit_error)
}

// A float literal's width comes from the context where there is one and from the
// literal's own suffix otherwise. An untyped float with neither is the same error a
// caller gets for any literal whose type nothing fixes.
fn float_literal_bits(c: *check.Checker, text: str, node: syntax.Node, expected: check.Type) -> (usize, check.Type, err) {
    let token = c.tokens[usize(node.token_start)]
    var ty = expected
    if ty.kind != .Float {
        let literal_type = check.numeric_literal_type(text, token)
        if literal_type.kind != .Float { ret (0usize, ty, check.MissingContext) }
        ty = literal_type
    }
    var width = 0usize
    if check.same(ty.name, "f32") { width = 32usize }
    if check.same(ty.name, "f64") { width = 64usize }
    if width == 0usize { ret (0usize, ty, check.Unsupported) }
    let (pattern, pattern_error) = decimal.literal_bits(text[token.start..token.end], width)
    if pattern_error != ok { ret (0usize, ty, pattern_error) }
    ret (pattern, ty, ok)
}

// Section 8 requires the operand's size to equal the target's, and that comparison
// needs the layout, which the checker cannot reach: `layout` is built on `check`.
// Everything else about the pun -- that neither type holds a pointer, slice or
// callable at any depth -- is settled while checking.
// Reflection is answered while checking (spec section 9 keeps all of it at compile
// time), so a call to `e.meta` lowers to the constant and nothing else.
fn emit_reflection(c: *check.Checker, call: check.CallInfo, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    results.call = call
    results.count = 1usize
    if call.meta_query == .TypeName {
        let (name_index, intern_error) = nir.intern_string(builder, quoted_text(c, call.meta_name))
        if intern_error != ok { ret intern_error }
        let (name_instruction, name, name_error) = nir.emit(builder, .ConstString, call.meta_result, true, name_index, token)
        if name_error != ok { ret name_error }
        results.values[0usize] = name
        ret ok
    }
    // `e.mem`'s layout pair. The checker carried the type rather than the answer,
    // because the answer is here: `layout` is built on `check` and cannot be asked
    // from inside it.
    if call.meta_query == .SizeOf || call.meta_query == .AlignOf {
        let (subject, subject_error) = layout.type_info(c, call.meta_subject)
        if subject_error != ok { ret subject_error }
        var answer = subject.size
        if call.meta_query == .AlignOf { answer = subject.alignment }
        let (layout_instruction, layout_value, layout_error) = nir.emit(builder, .ConstInteger, call.meta_result, true, answer, token)
        if layout_error != ok { ret layout_error }
        results.values[0usize] = layout_value
        ret ok
    }
    let (value_instruction, value, value_error) = nir.emit(builder, .ConstInteger, call.meta_result, true, call.meta_value, token)
    if value_error != ok { ret value_error }
    results.values[0usize] = value
    ret ok
}

// Text that is in no source file, wrapped so `nir.intern_string` can take it: the
// interner works on spellings, and a reflected type name has never been written as a
// literal anywhere. Type names are `[A-Za-z0-9_.]` throughout, so quotes are the whole
// encoding.
fn quoted_text(c: *check.Checker, text: str) -> str {
    let (storage, storage_error) = mem.alloc[u8](c.arena, text.len + 2usize)
    if storage_error != ok { ret "" }
    storage[0usize] = 34u8
    var at = 0usize
    while at < text.len {
        storage[1usize + at] = text[at]
        at += 1usize
    }
    storage[text.len + 1usize] = 34u8
    ret storage[..]
}

// Section 11's `enum` row, which traps in every mode: an integer cast to an enum has to
// name a member. One test block per member -- `Equal` against its bits, taken to the
// block after the check -- and a `.Trap` of kind `enum` carrying the integer where
// none matched. Its message is built here, so it is interned raw rather than quoted.
fn append_text(storage: []u8, write_at: *usize, text: str) -> err {
    var at = 0usize
    while at < text.len {
        if *write_at >= storage.len { ret check.Capacity }
        storage[*write_at] = text[at]
        *write_at += 1usize
        at += 1usize
    }
    ret ok
}

fn emit_enum_check(c: *check.Checker, converted: usize, source: usize, ty: check.Type, builder: *nir.Builder, token: lex.Token) -> err {
    let (aggregate_index, found) = check.aggregate_for_type(c, ty)
    if !found { ret check.InvalidType }
    let aggregate = c.aggregates[aggregate_index]
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    var decisions: [512]usize = zero
    var falses: [512]usize = zero
    var count = 0usize
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret check.InvalidType }
        if count == decisions.len { ret check.Capacity }
        let member = c.aggregate_fields[field_index]
        let (member_bits, member_bits_error) = check.enum_member_bits(aggregate.backing_type, member.enum_value, member.enum_negative)
        if member_bits_error != ok { ret member_bits_error }
        if count != 0usize {
            let test_block = builder.block_count
            let (test_index, test_error) = nir.begin_block(builder)
            if test_error != ok || test_index != test_block { ret nir.InvalidControlFlow }
            falses[count - 1usize] = test_block
        }
        let (member_instruction, member_constant, member_error) = nir.emit(builder, .ConstInteger, ty, true, member_bits, token)
        if member_error != ok { ret member_error }
        let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, converted, member_constant, token)
        if matches_error != ok { ret matches_error }
        let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
        if decision_error != ok { ret decision_error }
        try nir.add_operand(builder, decision, matches)
        decisions[count] = decision
        count += 1usize
        at += 1usize
    }
    if count == 0usize { ret ok }
    let trap_block = builder.block_count
    let (trap_index, trap_block_error) = nir.begin_block(builder)
    if trap_block_error != ok || trap_index != trap_block { ret nir.InvalidControlFlow }
    let prefix = "no member of "
    let suffix = " has value "
    let (storage, storage_error) = mem.alloc[u8](c.arena, prefix.len + ty.name.len + suffix.len)
    if storage_error != ok { ret storage_error }
    var write_at = 0usize
    try append_text(storage[..], &write_at, prefix)
    try append_text(storage[..], &write_at, ty.name)
    try append_text(storage[..], &write_at, suffix)
    let (message, message_error) = nir.intern_string(builder, storage[..])
    if message_error != ok { ret message_error }
    let (trap_instruction, trap_ignored, trap_error) = nir.emit(builder, .Trap, check.make_type(.Other, "enum", ty.module_index), false, message + 1usize, token)
    if trap_error != ok { ret trap_error }
    try nir.add_operand(builder, trap_instruction, source)
    let after_block = builder.block_count
    let (after_index, after_error) = nir.begin_block(builder)
    if after_error != ok || after_index != after_block { ret nir.InvalidControlFlow }
    falses[count - 1usize] = trap_block
    var fix_at = 0usize
    while fix_at < count {
        try nir.set_branch_targets(builder, decisions[fix_at], after_block, falses[fix_at])
        fix_at += 1usize
    }
    ret ok
}

// Section 11's `tag` row: `n.Lit` reads or writes the payload of a tagged union, and the
// tag has to name that member. One compare against the tag at offset 0, and a `.Trap`
// of kind `tag` carrying the tag found. A base behind a pointer is the same value.
fn emit_tag_check(c: *check.Checker, base: usize, base_type: check.Type, field_name: str, builder: *nir.Builder, token: lex.Token) -> err {
    if builder.nocheck { ret ok }
    var subject = base_type
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret ok }
        subject = c.types[subject.element]
    }
    let (aggregate_index, has_aggregate) = layout.aggregate_index(c, subject)
    if !has_aggregate { ret ok }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .TaggedUnion || aggregate.backing_type.kind != .Integer { ret ok }
    let (field_index, found_field) = check.aggregate_field_for_name(c, aggregate, field_name)
    if !found_field { ret ok }
    let field = c.aggregate_fields[field_index]
    let (tag_bits, tag_bits_error) = check.enum_member_bits(aggregate.backing_type, field.enum_value, field.enum_negative)
    if tag_bits_error != ok { ret tag_bits_error }
    let (tag_info, tag_info_error) = layout.type_info(c, aggregate.backing_type)
    if tag_info_error != ok { ret tag_info_error }
    let (address_instruction, tag_address, address_error) = nir.emit(builder, .FieldAddress, aggregate.backing_type, true, 0usize, token)
    if address_error != ok { ret address_error }
    try nir.add_operand(builder, address_instruction, base)
    let (load_instruction, tag, load_error) = nir.emit(builder, .Load, aggregate.backing_type, true, tag_info.size, token)
    if load_error != ok { ret load_error }
    try nir.add_operand(builder, load_instruction, tag_address)
    let (constant_instruction, expected, constant_error) = nir.emit(builder, .ConstInteger, aggregate.backing_type, true, tag_bits, token)
    if constant_error != ok { ret constant_error }
    let boolean = check.make_type(.Bool, "bool", subject.module_index)
    let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, tag, expected, token)
    if matches_error != ok { ret matches_error }
    let trap_block = builder.block_count
    let after_block = builder.block_count + 1usize
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, matches)
    try nir.set_branch_targets(builder, decision, after_block, trap_block)
    let (trap_index, trap_block_error) = nir.begin_block(builder)
    if trap_block_error != ok || trap_index != trap_block { ret nir.InvalidControlFlow }
    let middle = " read while the tag is "
    let (storage, storage_error) = mem.alloc[u8](c.arena, aggregate.name.len + 1usize + field_name.len + middle.len)
    if storage_error != ok { ret storage_error }
    var write_at = 0usize
    try append_text(storage[..], &write_at, aggregate.name)
    try append_text(storage[..], &write_at, ".")
    try append_text(storage[..], &write_at, field_name)
    try append_text(storage[..], &write_at, middle)
    let (message, message_error) = nir.intern_string(builder, storage[..])
    if message_error != ok { ret message_error }
    let (trap_instruction, trap_ignored, trap_error) = nir.emit(builder, .Trap, check.make_type(.Other, "tag", subject.module_index), false, message + 1usize, token)
    if trap_error != ok { ret trap_error }
    try nir.add_operand(builder, trap_instruction, tag)
    let (after_index, after_error) = nir.begin_block(builder)
    if after_error != ok || after_index != after_block { ret nir.InvalidControlFlow }
    ret ok
}

// Section 11's `align` row, debug only: `simd.load_aligned`/`store_aligned` at an
// address that is not a multiple of the vector's width. The library's two are ordinary
// generics that call `load`/`store`, so the check is placed at their call sites, where
// the slice, the offset and the vector type are all in hand: the element address is
// `data + off * size`, wrapping, and its low bits against the width have to be zero.
fn append_decimal(storage: []u8, write_at: *usize, value: usize) -> err {
    if value >= 10usize { try append_decimal(storage, write_at, value / 10usize) }
    if *write_at >= storage.len { ret check.Capacity }
    storage[*write_at] = u8(48usize + value % 10usize)
    *write_at += 1usize
    ret ok
}

fn emit_align_check(c: *check.Checker, g: *graph.Graph, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token) -> err {
    if builder.nocheck || call.function.module_index >= g.count || argument_count < 2usize { ret ok }
    if !check.same(g.modules[call.function.module_index].name, "e.simd") { ret ok }
    let loading = check.same(call.function.name, "load_aligned")
    if !loading && !check.same(call.function.name, "store_aligned") { ret ok }
    if call.function.parameter_count < 2usize || call.function.first_parameter + 2usize > c.parameter_count { ret ok }
    let slice_type = c.parameters[call.function.first_parameter].ty
    var vector_type = check.invalid_type()
    if loading {
        if call.function.return_count != 1usize { ret ok }
        vector_type = c.return_types[call.function.first_return]
    } else {
        if call.function.parameter_count != 3usize { ret ok }
        vector_type = c.parameters[call.function.first_parameter + 2usize].ty
    }
    let (element_type, element_error) = check.index_element_type(c, slice_type, call.function.module_index)
    if element_error != ok { ret element_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let (vector_info, vector_info_error) = layout.type_info(c, vector_type)
    if vector_info_error != ok { ret vector_info_error }
    if vector_info.size < 2usize { ret ok }
    let module_index = call.function.module_index
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if data_address_error != ok { ret data_address_error }
    try nir.add_operand(builder, data_address_instruction, arguments[0usize])
    let (data_load, data, data_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if data_load_error != ok { ret data_load_error }
    try nir.add_operand(builder, data_load, data_address)
    let (size_instruction, size, size_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.size, token)
    if size_error != ok { ret size_error }
    let (scaled_instruction, scaled, scaled_error) = nir.emit(builder, .MultiplyWrap, usize_type, true, 0usize, token)
    if scaled_error != ok { ret scaled_error }
    try nir.add_operand(builder, scaled_instruction, arguments[1usize])
    try nir.add_operand(builder, scaled_instruction, size)
    let (address_instruction, address, address_error) = nir.emit(builder, .AddWrap, usize_type, true, 0usize, token)
    if address_error != ok { ret address_error }
    try nir.add_operand(builder, address_instruction, data)
    try nir.add_operand(builder, address_instruction, scaled)
    let (mask_instruction, mask, mask_error) = nir.emit(builder, .ConstInteger, usize_type, true, vector_info.size - 1usize, token)
    if mask_error != ok { ret mask_error }
    let (low_instruction, low, low_error) = nir.emit(builder, .BitAnd, usize_type, true, 0usize, token)
    if low_error != ok { ret low_error }
    try nir.add_operand(builder, low_instruction, address)
    try nir.add_operand(builder, low_instruction, mask)
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if zero_error != ok { ret zero_error }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (aligned, aligned_error) = emit_supplied_compare(builder, .Equal, boolean, low, zero_value, token)
    if aligned_error != ok { ret aligned_error }
    let trap_block = builder.block_count
    let after_block = builder.block_count + 1usize
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, aligned)
    try nir.set_branch_targets(builder, decision, after_block, trap_block)
    let (trap_index, trap_block_error) = nir.begin_block(builder)
    if trap_block_error != ok || trap_index != trap_block { ret nir.InvalidControlFlow }
    let prefix = "address not a multiple of "
    let (storage, storage_error) = mem.alloc[u8](c.arena, prefix.len + 22usize)
    if storage_error != ok { ret storage_error }
    var write_at = 0usize
    try append_text(storage[..], &write_at, prefix)
    try append_decimal(storage[..], &write_at, vector_info.size)
    try append_text(storage[..], &write_at, ": ")
    let (message, message_error) = nir.intern_string(builder, storage[..write_at])
    if message_error != ok { ret message_error }
    let (trap_instruction, trap_ignored, trap_error) = nir.emit(builder, .Trap, check.make_type(.Other, "align", module_index), false, message + 1usize, token)
    if trap_error != ok { ret trap_error }
    try nir.add_operand(builder, trap_instruction, address)
    let (after_index, after_error) = nir.begin_block(builder)
    if after_error != ok || after_index != after_block { ret nir.InvalidControlFlow }
    ret ok
}

// Section 11's `null` row: a dereference of `nil` traps. Every path that reads or
// writes through a pointer value -- `*p`, `p.field` through the auto-dereference --
// compares the pointer with zero first; a value that is already an address of a stack
// object or an aggregate by address is never nil and never comes here.
fn emit_null_check(c: *check.Checker, pointer: usize, pointer_type: check.Type, builder: *nir.Builder, token: lex.Token) -> err {
    if pointer_type.kind != .Pointer || builder.nocheck { ret ok }
    let usize_type = check.make_type(.Integer, "usize", pointer_type.module_index)
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if zero_error != ok { ret zero_error }
    let boolean = check.make_type(.Bool, "bool", pointer_type.module_index)
    let (nonzero, nonzero_error) = emit_supplied_compare(builder, .NotEqual, boolean, pointer, zero_value, token)
    if nonzero_error != ok { ret nonzero_error }
    let trap_block = builder.block_count
    let after_block = builder.block_count + 1usize
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, nonzero)
    try nir.set_branch_targets(builder, decision, after_block, trap_block)
    let (trap_index, trap_block_error) = nir.begin_block(builder)
    if trap_block_error != ok || trap_index != trap_block { ret nir.InvalidControlFlow }
    var pointee = ""
    if pointer_type.has_element && pointer_type.element < c.type_count { pointee = c.types[pointer_type.element].name }
    let prefix = "nil dereferenced"
    var storage_len = prefix.len
    if pointee.len != 0usize { storage_len += 5usize + pointee.len }
    let (storage, storage_error) = mem.alloc[u8](c.arena, storage_len)
    if storage_error != ok { ret storage_error }
    var write_at = 0usize
    try append_text(storage[..], &write_at, prefix)
    if pointee.len != 0usize {
        try append_text(storage[..], &write_at, " as *")
        try append_text(storage[..], &write_at, pointee)
    }
    let (message, message_error) = nir.intern_string(builder, storage[..write_at])
    if message_error != ok { ret message_error }
    let (trap_instruction, trap_ignored, trap_error) = nir.emit(builder, .Trap, check.make_type(.Other, "null", pointer_type.module_index), false, message + 1usize, token)
    if trap_error != ok { ret trap_error }
    let (after_index, after_error) = nir.begin_block(builder)
    if after_error != ok || after_index != after_block { ret nir.InvalidControlFlow }
    ret ok
}

fn lower_bitcast(c: *check.Checker, source: usize, source_type: check.Type, into: check.Type, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (source_info, source_info_error) = layout.type_info(c, source_type)
    if source_info_error != ok { ret (0usize, source_info_error) }
    let (target_info, target_info_error) = layout.type_info(c, into)
    if target_info_error != ok { ret (0usize, target_info_error) }
    if source_info.size != target_info.size { ret (0usize, check.TypeMismatch) }
    // A scalar is a value in a register and an aggregate is an address. The bytes are
    // the same either way, so a pun that crosses between the two has to move them.
    let source_is_place = aggregate_value(c, source_type)
    let target_is_place = aggregate_value(c, into)
    if source_is_place == target_is_place {
        let (instruction, result, emit_error) = nir.emit(builder, .Bitcast, into, true, 0usize, token)
        if emit_error != ok { ret (0usize, emit_error) }
        let operand_error = nir.add_operand(builder, instruction, source)
        if operand_error != ok { ret (0usize, operand_error) }
        ret (result, ok)
    }
    if target_is_place {
        // Read as an aggregate, the scalar needs somewhere to be read from: it is
        // spilled to a slot of its own and the slot is the result.
        var slots = (target_info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, slot, stack_error) = nir.emit(builder, .Stack, into, true, slots, token)
        if stack_error != ok { ret (0usize, stack_error) }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, source_type, false, source_info.size, token)
        if store_error != ok { ret (0usize, store_error) }
        let address_error = nir.add_operand(builder, store_instruction, slot)
        if address_error != ok { ret (0usize, address_error) }
        let value_error = nir.add_operand(builder, store_instruction, source)
        if value_error != ok { ret (0usize, value_error) }
        ret (slot, ok)
    }
    // The mirror: read as a scalar, the aggregate's bytes are loaded from where they
    // already sit, at the into's width and signedness.
    let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, into, true, target_info.size, token)
    if load_error != ok { ret (0usize, load_error) }
    let address_operand_error = nir.add_operand(builder, load_instruction, source)
    if address_operand_error != ok { ret (0usize, address_operand_error) }
    ret (loaded, ok)
}

fn lower_constant(c: *check.Checker, constant_index: usize, ty: check.Type, token: lex.Token, builder: *nir.Builder) -> (usize, err) {
    if constant_index >= c.constant_count || c.constants[constant_index].state != 2u8 { ret (0usize, check.InvalidConstant) }
    // A bool constant (D222) is its bit.
    if ty.kind == .Bool {
        let (bool_instruction, bool_result, bool_error) = nir.emit(builder, .ConstBool, ty, true, c.constants[constant_index].value.magnitude, token)
        ret (bool_result, bool_error)
    }
    if ty.kind != .Integer { ret (0usize, check.InvalidConstant) }
    let width = check.integer_width(ty)
    if width == 0usize { ret (0usize, check.InvalidType) }
    let immediate = check.integer_bits(c.constants[constant_index].value, width)
    let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, ty, true, immediate, token)
    ret (result, emit_error)
}

// The address of a module-scope `var`, as a pointer to its own type. Interning is what makes one
// variable one address however many places reach it; the address itself is a relocation the
// linker fills, because nothing here knows where the image will put it.
// Every module-scope `var` the program declares, in the checker's order, so that a global's index
// is the same number to the checker, the emitter and the linker.
// Globals are laid out in graph order, module by module (D304): the front end collects
// them in dependency order, and the artifact linker lays them out by artifact, which is
// graph order, so this is what keeps an image byte-equal from either path.
fn declare_globals(c: *check.Checker, builder: *nir.Builder) -> err {
    if builder.global_count != 0usize { ret ok }
    var module_count = 1usize
    if c.has_graph { module_count = c.graph.count }
    var module_at = 0usize
    while module_at < module_count {
        var at = 0usize
        while at < c.global_count {
            let item = c.globals[at]
            if item.module_index == module_at || !c.has_graph {
                let (info, info_error) = layout.type_info(c, item.ty)
                if info_error != ok { ret info_error }
                let (initial, initial_error) = check.global_initial_bits(c, at)
                if initial_error != ok { ret initial_error }
                let (index, add_error) = nir.add_global(builder, item.module_index, item.name, info.size, info.alignment, initial, item.has_expression)
                if add_error != ok { ret add_error }
                c.globals[at].nir_index = index
            }
            at += 1usize
        }
        module_at += 1usize
    }
    ret ok
}

fn global_address(c: *check.Checker, global_index: usize, builder: *nir.Builder, token: lex.Token) -> (usize, check.Type, err) {
    if global_index >= c.global_count || global_index >= builder.global_count { ret (0usize, zero, check.InvalidConstant) }
    let item = c.globals[global_index]
    let index = item.nir_index
    let (element_index, store_error) = check.store_type(c, item.ty)
    if store_error != ok { ret (0usize, item.ty, store_error) }
    var pointer = check.make_type(.Pointer, "", item.module_index)
    pointer.element = element_index
    pointer.has_element = true
    let (instruction, result, emit_error) = nir.emit(builder, .GlobalAddress, pointer, true, index, token)
    ret (result, pointer, emit_error)
}

fn register_return_type(c: *check.Checker, ty: check.Type) -> bool {
    // A function type is an address and comes back in a register, exactly as a pointer does.
    // Leaving it out put `os.dlsym`'s result in a return slot while the lookup it calls returns
    // in registers, and a caller and callee that disagree about that read each other's rubbish --
    // which looked like success the first time, because a fresh slot reads as `ok`.
    if ty.kind == .Bool || ty.kind == .Err || ty.kind == .Integer || ty.kind == .Pointer || ty.kind == .Float || ty.kind == .Function { ret true }
    if ty.kind == .Named || ty.kind == .Tag {
        let (aggregate_index, found) = layout.aggregate_index(c, ty)
        if found && c.aggregates[aggregate_index].kind == .Enum { ret true }
    }
    ret false
}

fn call_return_layout(c: *check.Checker, call: check.CallInfo, result: *ReturnLayout) -> err {
    result.alignment = 1usize
    if call.function.return_count > result.offsets.len { ret check.Capacity }
    var integer_count = 0usize
    var at = 0usize
    while at < call.function.return_count {
        let (ty, type_error) = check.call_return(c, call, at)
        if type_error != ok { ret type_error }
        let (info, info_error) = layout.type_info(c, ty)
        if info_error != ok { ret info_error }
        let (offset, offset_error) = layout.align_up(result.size, info.alignment)
        if offset_error != ok || offset > 18446744073709551615usize - info.size { ret layout.Overflow }
        result.offsets[at] = offset
        result.size = offset + info.size
        if info.alignment > result.alignment { result.alignment = info.alignment }
        if register_return_type(c, ty) { integer_count += 1usize } else { result.via_slot = true }
        at += 1usize
    }
    if integer_count > 2usize { result.via_slot = true }
    if call.mem_alloc { result.via_slot = true }
    let (rounded, rounded_error) = layout.align_up(result.size, result.alignment)
    if rounded_error != ok { ret rounded_error }
    result.size = rounded
    ret ok
}

fn call_parameter_type(c: *check.Checker, call: check.CallInfo, index: usize) -> (check.Type, err) {
    if index >= call.function.parameter_count { ret (check.invalid_type(), check.ArgumentCount) }
    if call.indirect {
        let (signature, has_signature) = check.function_signature_of(c, call.indirect_type)
        if !has_signature { ret (check.invalid_type(), check.InvalidType) }
        let (parameter, has_parameter) = check.function_signature_parameter(c, signature, index)
        if !has_parameter { ret (check.invalid_type(), check.ArgumentCount) }
        ret (parameter, ok)
    }
    if call.protocol_builtin != .None { ret (call.protocol_type, ok) }
    if call.mem_alloc {
        if index == 0usize { ret (call.alloc_arena, ok) }
        ret (check.make_type(.Integer, "usize", call.function.module_index), ok)
    }
    // Synthesized like `mem.alloc`, so its parameters are not in `c.parameters`: the
    // entry point's own type was settled while checking, the context is the bound
    // pointer, and the stack is a size.
    if call.thread_create {
        if index == 0usize { ret (call.thread_entry, ok) }
        if index == 1usize { ret (call.thread_context, ok) }
        ret (check.make_type(.Integer, "usize", call.function.module_index), ok)
    }
    // Also synthesized: `T` came from the pointer while checking, so the value
    // arguments are `T` and the trailing ones are the ordering enum.
    if call.atomic_op != .None { ret (atomic_parameter_type(c, call, index), ok) }
    // Synthesized like the rest: `get` takes the value by pointer, `set` that and the
    // field's own type.
    if call.meta_access {
        if index == 0usize {
            let (stored, store_error) = check.store_type(c, call.meta_subject)
            if store_error != ok { ret (check.invalid_type(), store_error) }
            var pointer = check.make_type(.Pointer, "", call.function.module_index)
            pointer.element = stored
            pointer.has_element = true
            pointer.is_const = !call.meta_writes
            ret (pointer, ok)
        }
        ret (call.meta_field.ty, ok)
    }
    let parameter_index = call.function.first_parameter + index
    if parameter_index >= c.parameter_count { ret (check.invalid_type(), check.InvalidType) }
    ret (c.parameters[parameter_index].ty, ok)
}

fn intrinsic_symbol(name: str) -> (str, err) {
    if check.same(name, "mark") { ret ("neper_mem_mark", ok) }
    if check.same(name, "reset") { ret ("neper_mem_reset", ok) }
    if check.same(name, "stats") { ret ("neper_mem_stats", ok) }
    if check.same(name, "open") { ret ("neper_os_open", ok) }
    if check.same(name, "read") { ret ("neper_os_read", ok) }
    if check.same(name, "write") { ret ("neper_os_write", ok) }
    if check.same(name, "close") { ret ("neper_os_close", ok) }
    if check.same(name, "seek") { ret ("neper_os_seek", ok) }
    if check.same(name, "copy_bytes") { ret ("neper_os_copy_bytes", ok) }
    if check.same(name, "thread_create") { ret ("neper_os_thread_create", ok) }
    if check.same(name, "thread_join") { ret ("neper_os_thread_join", ok) }
    if check.same(name, "thread_detach") { ret ("neper_os_thread_detach", ok) }
    if check.same(name, "stdout") { ret ("neper_os_stdout", ok) }
    if check.same(name, "stderr") { ret ("neper_os_stderr", ok) }
    if check.same(name, "readdir") { ret ("neper_os_readdir", ok) }
    if check.same(name, "spawn") { ret ("neper_os_spawn", ok) }
    if check.same(name, "wait") { ret ("neper_os_wait", ok) }
    if check.same(name, "exit") { ret ("neper_os_exit", ok) }
    if check.same(name, "args") { ret ("neper_os_args", ok) }
    if check.same(name, "reserve") { ret ("neper_os_reserve", ok) }
    if check.same(name, "commit") { ret ("neper_os_commit", ok) }
    if check.same(name, "clock") { ret ("neper_os_clock", ok) }
    if check.same(name, "syscall") { ret ("neper_os_syscall", ok) }
    if check.same(name, "wait_u32") { ret ("neper_os_wait_u32", ok) }
    if check.same(name, "wake_one_u32") { ret ("neper_os_wake_one_u32", ok) }
    if check.same(name, "wake_all_u32") { ret ("neper_os_wake_all_u32", ok) }
    ret ("", check.UnknownCallable)
}

fn store_supplied_cmp_result(builder: *nir.Builder, slot: usize, result_type: check.Type, magnitude: usize, negative: bool, token: lex.Token) -> (usize, err) {
    let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstInteger, result_type, true, magnitude, token)
    if constant_error != ok { ret (0usize, constant_error) }
    var value = constant
    if negative {
        let (negate_instruction, negated, negate_error) = nir.emit(builder, .Negate, result_type, true, 0usize, token)
        if negate_error != ok { ret (0usize, negate_error) }
        let negate_operand_error = nir.add_operand(builder, negate_instruction, constant)
        if negate_operand_error != ok { ret (0usize, negate_operand_error) }
        value = negated
    }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, result_type, false, 0usize, token)
    if store_error != ok { ret (0usize, store_error) }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret (0usize, address_error) }
    let value_error = nir.add_operand(builder, store_instruction, value)
    if value_error != ok { ret (0usize, value_error) }
    let (exit_branch, exit_error) = emit_branch(builder, token)
    ret (exit_branch, exit_error)
}

fn ordering_opcode(opcode: nir.Opcode) -> bool {
    ret opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual
}

// An enum orders by its backing integer, and only the backing integer says
// whether that ordering is signed. Codegen sees the named type, which does not,
// so the conversion is made explicit here rather than resolved down there.
fn coerce_ordering_operand(c: *check.Checker, ty: check.Type, value: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (backing, is_enum) = check.enum_backing_type(c, ty)
    if !is_enum { ret (value, ok) }
    let (instruction, converted, emit_error) = nir.emit(builder, .Cast, backing, true, 0usize, token)
    if emit_error != ok { ret (0usize, emit_error) }
    let operand_error = nir.add_operand(builder, instruction, value)
    if operand_error != ok { ret (0usize, operand_error) }
    ret (converted, ok)
}

fn emit_supplied_compare(builder: *nir.Builder, opcode: nir.Opcode, boolean: check.Type, left: usize, right: usize, token: lex.Token) -> (usize, err) {
    let (instruction, value, emit_error) = nir.emit(builder, opcode, boolean, true, 0usize, token)
    if emit_error != ok { ret (0usize, emit_error) }
    let left_error = nir.add_operand(builder, instruction, left)
    if left_error != ok { ret (0usize, left_error) }
    let right_error = nir.add_operand(builder, instruction, right)
    if right_error != ok { ret (0usize, right_error) }
    ret (value, ok)
}

// The data pointer and length behind an array, slice or `str`. An array value is
// already its storage and its length is static; a slice and a `str` are a
// {pointer, length} pair, which is also how one sits inside an enclosing sequence.
fn sequence_parts(c: *check.Checker, ty: check.Type, subject: usize, builder: *nir.Builder, token: lex.Token) -> (usize, usize, err) {
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    if ty.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, ty.array_length, token)
        if length_error != ok { ret (0usize, 0usize, length_error) }
        ret (subject, length_value, ok)
    }
    if ty.kind != .Slice && ty.kind != .String { ret (0usize, 0usize, check.Unsupported) }
    let pointer_type = check.make_type(.Pointer, "", ty.module_index)
    let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if data_address_error != ok { ret (0usize, 0usize, data_address_error) }
    let data_address_operand_error = nir.add_operand(builder, data_address_instruction, subject)
    if data_address_operand_error != ok { ret (0usize, 0usize, data_address_operand_error) }
    let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, token)
    if data_load_error != ok { ret (0usize, 0usize, data_load_error) }
    let data_load_operand_error = nir.add_operand(builder, data_load_instruction, data_address)
    if data_load_operand_error != ok { ret (0usize, 0usize, data_load_operand_error) }
    let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, token)
    if length_address_error != ok { ret (0usize, 0usize, length_address_error) }
    let length_address_operand_error = nir.add_operand(builder, length_address_instruction, subject)
    if length_address_operand_error != ok { ret (0usize, 0usize, length_address_operand_error) }
    let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if length_load_error != ok { ret (0usize, 0usize, length_load_error) }
    let length_load_operand_error = nir.add_operand(builder, length_load_instruction, length_address)
    if length_load_operand_error != ok { ret (0usize, 0usize, length_load_operand_error) }
    ret (data_value, length_value, ok)
}

// Spec section 9 rule 4 supplies `cmp` for the single-scalar shapes. There is
// nothing to call, so it is emitted inline. The language has no bool-to-integer
// cast, so the three results come from branches into one slot. The caller owns the
// slot and reads it; every path through here stores, and the builder is left on a
// fresh block.
fn emit_scalar_cmp(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    let (ordered_left, left_coerce_error) = coerce_ordering_operand(c, ty, left, builder, token)
    if left_coerce_error != ok { ret left_coerce_error }
    let (ordered_right, right_coerce_error) = coerce_ordering_operand(c, ty, right, builder, token)
    if right_coerce_error != ok { ret right_coerce_error }
    let (less, less_error) = emit_supplied_compare(builder, .Less, boolean, ordered_left, ordered_right, token)
    if less_error != ok { ret less_error }
    let (less_decision, less_decision_ignored, less_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if less_decision_error != ok { ret less_decision_error }
    let less_decision_operand_error = nir.add_operand(builder, less_decision, less)
    if less_decision_operand_error != ok { ret less_decision_operand_error }

    let below_block = builder.block_count
    let (below_index, below_error) = nir.begin_block(builder)
    if below_error != ok || below_index != below_block { ret nir.InvalidControlFlow }
    let (below_exit, below_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 1usize, true, token)
    if below_exit_error != ok { ret below_exit_error }

    let rest_block = builder.block_count
    let (rest_index, rest_error) = nir.begin_block(builder)
    if rest_error != ok || rest_index != rest_block { ret nir.InvalidControlFlow }
    let (greater, greater_error) = emit_supplied_compare(builder, .Greater, boolean, ordered_left, ordered_right, token)
    if greater_error != ok { ret greater_error }
    let (greater_decision, greater_decision_ignored, greater_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if greater_decision_error != ok { ret greater_decision_error }
    let greater_decision_operand_error = nir.add_operand(builder, greater_decision, greater)
    if greater_decision_operand_error != ok { ret greater_decision_operand_error }

    let above_block = builder.block_count
    let (above_index, above_error) = nir.begin_block(builder)
    if above_error != ok || above_index != above_block { ret nir.InvalidControlFlow }
    let (above_exit, above_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 1usize, false, token)
    if above_exit_error != ok { ret above_exit_error }

    let same_block = builder.block_count
    let (same_index, same_error) = nir.begin_block(builder)
    if same_error != ok || same_index != same_block { ret nir.InvalidControlFlow }
    let (same_exit, same_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 0usize, false, token)
    if same_exit_error != ok { ret same_exit_error }

    let merge_block = builder.block_count
    let (merge_index, merge_error) = nir.begin_block(builder)
    if merge_error != ok || merge_index != merge_block { ret nir.InvalidControlFlow }
    let less_target_error = nir.set_branch_targets(builder, less_decision, below_block, rest_block)
    if less_target_error != ok { ret less_target_error }
    let greater_target_error = nir.set_branch_targets(builder, greater_decision, above_block, same_block)
    if greater_target_error != ok { ret greater_target_error }
    let below_target_error = nir.set_branch_targets(builder, below_exit, merge_block, 0usize)
    if below_target_error != ok { ret below_target_error }
    let above_target_error = nir.set_branch_targets(builder, above_exit, merge_block, 0usize)
    if above_target_error != ok { ret above_target_error }
    ret nir.set_branch_targets(builder, same_exit, merge_block, 0usize)
}

// Rule 4 again: arrays, slices and `str` recurse in index order. The common prefix
// decides where it differs; where it does not, the shorter sequence orders first,
// which for two arrays of one type is the equal-length case and stores zero.
fn emit_sequence_cmp(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (element_type, element_type_error) = check.index_element_type(c, ty, ty.module_index)
    if element_type_error != ok { ret element_type_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    let (left_data, left_length, left_parts_error) = sequence_parts(c, ty, left, builder, token)
    if left_parts_error != ok { ret left_parts_error }
    let (right_data, right_length, right_parts_error) = sequence_parts(c, ty, right, builder, token)
    if right_parts_error != ok { ret right_parts_error }
    let (element_slot_instruction, element_slot, element_slot_error) = nir.emit(builder, .Stack, result_type, true, 0usize, token)
    if element_slot_error != ok { ret element_slot_error }
    let (counter_slot_instruction, counter_slot, counter_slot_error) = nir.emit(builder, .Stack, usize_type, true, 0usize, token)
    if counter_slot_error != ok { ret counter_slot_error }
    let (start_instruction, start, start_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if start_error != ok { ret start_error }
    let (start_store_instruction, start_store_ignored, start_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if start_store_error != ok { ret start_store_error }
    try nir.add_operand(builder, start_store_instruction, counter_slot)
    try nir.add_operand(builder, start_store_instruction, start)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }

    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_slot)
    let (has_left, has_left_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, left_length, token)
    if has_left_error != ok { ret has_left_error }
    let (has_right, has_right_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, right_length, token)
    if has_right_error != ok { ret has_right_error }
    let (both_instruction, has_next, both_error) = nir.emit(builder, .BitAnd, boolean, true, 0usize, token)
    if both_error != ok { ret both_error }
    try nir.add_operand(builder, both_instruction, has_left)
    try nir.add_operand(builder, both_instruction, has_right)
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)

    let increment_block = builder.block_count
    let (increment_index, increment_error) = nir.begin_block(builder)
    if increment_error != ok || increment_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_slot)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, usize_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, usize_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_slot)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)

    let body_block = builder.block_count
    let (body_index, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
    let (body_load_instruction, body_counter, body_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if body_load_error != ok { ret body_load_error }
    try nir.add_operand(builder, body_load_instruction, counter_slot)
    let (left_element, left_element_error) = element_operand(c, element_type, element_info.size, left_data, body_counter, left_length, builder, token)
    if left_element_error != ok { ret left_element_error }
    let (right_element, right_element_error) = element_operand(c, element_type, element_info.size, right_data, body_counter, right_length, builder, token)
    if right_element_error != ok { ret right_element_error }
    let element_error = emit_cmp_into(c, element_type, element_slot, result_type, left_element, right_element, builder, token, depth + 1usize)
    if element_error != ok { ret element_error }
    let (element_load_instruction, element_result, element_load_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
    if element_load_error != ok { ret element_load_error }
    try nir.add_operand(builder, element_load_instruction, element_slot)
    let (element_zero_instruction, element_zero, element_zero_error) = nir.emit(builder, .ConstInteger, result_type, true, 0usize, token)
    if element_zero_error != ok { ret element_zero_error }
    let (differs, differs_error) = emit_supplied_compare(builder, .NotEqual, boolean, element_result, element_zero, token)
    if differs_error != ok { ret differs_error }
    let (element_decision, element_decision_ignored, element_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if element_decision_error != ok { ret element_decision_error }
    try nir.add_operand(builder, element_decision, differs)

    let carry_block = builder.block_count
    let (carry_index, carry_error) = nir.begin_block(builder)
    if carry_error != ok || carry_index != carry_block { ret nir.InvalidControlFlow }
    let (carry_result_instruction, carry_result_ignored, carry_result_error) = nir.emit(builder, .Store, result_type, false, 0usize, token)
    if carry_result_error != ok { ret carry_result_error }
    try nir.add_operand(builder, carry_result_instruction, slot)
    try nir.add_operand(builder, carry_result_instruction, element_result)
    let (carry_exit, carry_exit_error) = emit_branch(builder, token)
    if carry_exit_error != ok { ret carry_exit_error }

    // The common prefix matched, so the shorter sequence orders first. Two arrays
    // of one type reach this with equal lengths and store zero.
    let tail_block = builder.block_count
    let (tail_index, tail_error) = nir.begin_block(builder)
    if tail_error != ok || tail_index != tail_block { ret nir.InvalidControlFlow }
    let length_error = emit_scalar_cmp(c, usize_type, slot, result_type, left_length, right_length, builder, token)
    if length_error != ok { ret length_error }
    let (tail_exit, tail_exit_error) = emit_branch(builder, token)
    if tail_exit_error != ok { ret tail_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, tail_block)
    try nir.set_branch_targets(builder, element_decision, carry_block, increment_block)
    try nir.set_branch_targets(builder, carry_exit, done_block, 0usize)
    ret nir.set_branch_targets(builder, tail_exit, done_block, 0usize)
}

// An element reaches its comparison the way the rest of lowering passes one: an
// aggregate by address, everything else loaded.
fn element_operand(c: *check.Checker, element_type: check.Type, stride: usize, data: usize, index: usize, limit: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (address_instruction, address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, stride, token)
    if address_error != ok { ret (0usize, address_error) }
    let data_operand_error = nir.add_operand(builder, address_instruction, data)
    if data_operand_error != ok { ret (0usize, data_operand_error) }
    let index_operand_error = nir.add_operand(builder, address_instruction, index)
    if index_operand_error != ok { ret (0usize, index_operand_error) }
    let limit_operand_error = nir.add_operand(builder, address_instruction, limit)
    if limit_operand_error != ok { ret (0usize, limit_operand_error) }
    if aggregate_value(c, element_type) { ret (address, ok) }
    let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, element_type, true, stride, token)
    if load_error != ok { ret (0usize, load_error) }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret (0usize, load_operand_error) }
    ret (loaded, ok)
}

// An element whose own module declares `fn <t>_cmp` is compared by calling it --
// the same direct call an ordinary `T.cmp(a, b)` lowers to, and the same reference
// that gives the artifact its dependency edge. Rule 3 passes the receiver by value,
// which for an aggregate is its address, exactly as `element_operand` supplies it.
fn emit_declared_cmp(c: *check.Checker, function: check.Function, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let (function_ref, reference_error) = nir.intern_function(builder, function.owner_module_index, function.name, function.instance_id)
    if reference_error != ok { ret reference_error }
    let (instruction, call_result, emit_error) = nir.emit(builder, .Call, result_type, true, function_ref, token)
    if emit_error != ok { ret emit_error }
    let left_operand_error = nir.add_operand(builder, instruction, left)
    if left_operand_error != ok { ret left_operand_error }
    let right_operand_error = nir.add_operand(builder, instruction, right)
    if right_operand_error != ok { ret right_operand_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, result_type, false, 0usize, token)
    if store_error != ok { ret store_error }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret address_error }
    ret nir.add_operand(builder, store_instruction, call_result)
}

// A component reaches its comparison the way the rest of lowering passes one: an
// aggregate by address, everything else loaded.
fn component_at(c: *check.Checker, ty: check.Type, base: usize, offset: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, ty, true, offset, token)
    if address_error != ok { ret (0usize, address_error) }
    let base_operand_error = nir.add_operand(builder, address_instruction, base)
    if base_operand_error != ok { ret (0usize, base_operand_error) }
    if aggregate_value(c, ty) { ret (address, ok) }
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret (0usize, info_error) }
    let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, ty, true, info.size, token)
    if load_error != ok { ret (0usize, load_error) }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret (0usize, load_operand_error) }
    ret (loaded, ok)
}

// Rule 4 again: a tagged union compares its tag before the live payload. The tags
// decide outright where they differ; where they match, the arm they both name is
// compared through the same dispatch every other component uses. A void arm has
// nothing to compare and is equal to itself, which is what the default arm stores.
fn emit_tagged_union_cmp(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (aggregate_index, found) = check.aggregate_for_type(c, ty)
    if !found { ret check.InvalidType }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .TaggedUnion || aggregate.backing_type.kind != .Integer { ret check.InvalidType }
    let boolean = check.make_type(.Bool, "bool", ty.module_index)
    let tag_type = aggregate.backing_type
    let (tag_info, tag_info_error) = layout.type_info(c, tag_type)
    if tag_info_error != ok { ret tag_info_error }
    let (left_tag, left_tag_error) = component_at(c, tag_type, left, 0usize, builder, token)
    if left_tag_error != ok { ret left_tag_error }
    let (right_tag, right_tag_error) = component_at(c, tag_type, right, 0usize, builder, token)
    if right_tag_error != ok { ret right_tag_error }
    let tag_cmp_error = emit_scalar_cmp(c, tag_type, slot, result_type, left_tag, right_tag, builder, token)
    if tag_cmp_error != ok { ret tag_cmp_error }
    let (tag_result_instruction, tag_result, tag_result_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
    if tag_result_error != ok { ret tag_result_error }
    try nir.add_operand(builder, tag_result_instruction, slot)
    let (tag_zero_instruction, tag_zero, tag_zero_error) = nir.emit(builder, .ConstInteger, result_type, true, 0usize, token)
    if tag_zero_error != ok { ret tag_zero_error }
    let (tags_differ, tags_differ_error) = emit_supplied_compare(builder, .NotEqual, boolean, tag_result, tag_zero, token)
    if tags_differ_error != ok { ret tags_differ_error }
    let (tag_decision, tag_decision_ignored, tag_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if tag_decision_error != ok { ret tag_decision_error }
    try nir.add_operand(builder, tag_decision, tags_differ)

    var tests: [32]usize = zero
    var decisions: [32]usize = zero
    var bodies: [32]usize = zero
    var exits: [32]usize = zero
    var arm_count = 0usize
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret check.InvalidType }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            if arm_count == tests.len { ret check.Capacity }
            let (payload, payload_error) = layout.field(c, ty, arm.name)
            if payload_error != ok { ret payload_error }
            let (arm_bits, arm_bits_error) = check.enum_member_bits(tag_type, arm.enum_value, arm.enum_negative)
            if arm_bits_error != ok { ret arm_bits_error }
            let test_block = builder.block_count
            let (test_index, test_error) = nir.begin_block(builder)
            if test_error != ok || test_index != test_block { ret nir.InvalidControlFlow }
            let (arm_constant_instruction, arm_constant, arm_constant_error) = nir.emit(builder, .ConstInteger, tag_type, true, arm_bits, token)
            if arm_constant_error != ok { ret arm_constant_error }
            let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, left_tag, arm_constant, token)
            if matches_error != ok { ret matches_error }
            let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
            if decision_error != ok { ret decision_error }
            try nir.add_operand(builder, decision, matches)
            let body_block = builder.block_count
            let (body_index, body_error) = nir.begin_block(builder)
            if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
            let (left_payload, left_payload_error) = component_at(c, payload.ty, left, payload.offset, builder, token)
            if left_payload_error != ok { ret left_payload_error }
            let (right_payload, right_payload_error) = component_at(c, payload.ty, right, payload.offset, builder, token)
            if right_payload_error != ok { ret right_payload_error }
            let payload_cmp_error = emit_cmp_into(c, payload.ty, slot, result_type, left_payload, right_payload, builder, token, depth + 1usize)
            if payload_cmp_error != ok { ret payload_cmp_error }
            let (exit, exit_error) = emit_branch(builder, token)
            if exit_error != ok { ret exit_error }
            tests[arm_count] = test_block
            decisions[arm_count] = decision
            bodies[arm_count] = body_block
            exits[arm_count] = exit
            arm_count += 1usize
        }
        at += 1usize
    }

    let default_block = builder.block_count
    let (default_index, default_error) = nir.begin_block(builder)
    if default_error != ok || default_index != default_block { ret nir.InvalidControlFlow }
    let (default_exit, default_exit_error) = store_supplied_cmp_result(builder, slot, result_type, 0usize, false, token)
    if default_exit_error != ok { ret default_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    var dispatch_block = default_block
    if arm_count != 0usize { dispatch_block = tests[0usize] }
    try nir.set_branch_targets(builder, tag_decision, done_block, dispatch_block)
    var patch_at = 0usize
    while patch_at < arm_count {
        var next_block = default_block
        if patch_at + 1usize < arm_count { next_block = tests[patch_at + 1usize] }
        try nir.set_branch_targets(builder, decisions[patch_at], bodies[patch_at], next_block)
        try nir.set_branch_targets(builder, exits[patch_at], done_block, 0usize)
        patch_at += 1usize
    }
    ret nir.set_branch_targets(builder, default_exit, done_block, 0usize)
}

fn emit_cmp_into(c: *check.Checker, ty: check.Type, slot: usize, result_type: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String {
        ret emit_sequence_cmp(c, ty, slot, result_type, left, right, builder, token, depth)
    }
    let (function_index, has_function) = check.element_cmp_function(c, ty)
    if has_function { ret emit_declared_cmp(c, c.functions[function_index], slot, result_type, left, right, builder, token) }
    if check.is_tagged_union_type(c, ty) {
        ret emit_tagged_union_cmp(c, ty, slot, result_type, left, right, builder, token, depth)
    }
    ret emit_scalar_cmp(c, ty, slot, result_type, left, right, builder, token)
}

fn emit_supplied_cmp(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if argument_count != 2usize { ret check.ArgumentCount }
    let result_type = check.make_type(.Integer, "i32", call.protocol_type.module_index)
    let (slot_instruction, slot, slot_error) = nir.emit(builder, .Stack, result_type, true, 0usize, token)
    if slot_error != ok { ret slot_error }
    let cmp_error = emit_cmp_into(c, call.protocol_type, slot, result_type, arguments[0usize], arguments[1usize], builder, token, 0usize)
    if cmp_error != ok { ret cmp_error }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, 0usize, token)
    if load_error != ok { ret load_error }
    let load_operand_error = nir.add_operand(builder, load_instruction, slot)
    if load_operand_error != ok { ret load_operand_error }
    results.call = call
    results.count = 1usize
    results.values[0usize] = result
    results.addresses[0usize] = false
    ret ok
}

// Spec section 9 rule 4: the supplied `hash` is xxHash64 seed 0 over the value's
// canonical little-endian bytes. The compiler does not carry the algorithm; the
// runtime does, as `neper_hash_bytes`, which is the same one-shot form the C
// bootstrap runtime and both embedded runtimes provide and which must agree with
// `e.algo.hash.xxhash64`.
fn emit_hash_bytes(c: *check.Checker, module_index: usize, data: usize, byte_length: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let result_type = check.make_type(.Integer, "u64", module_index)
    let (function_ref, reference_error) = nir.intern_function(builder, module_index, "neper_hash_bytes", 0usize)
    if reference_error != ok { ret (0usize, reference_error) }
    let (instruction, result, emit_error) = nir.emit(builder, .Call, result_type, true, function_ref, token)
    if emit_error != ok { ret (0usize, emit_error) }
    let data_operand_error = nir.add_operand(builder, instruction, data)
    if data_operand_error != ok { ret (0usize, data_operand_error) }
    let length_operand_error = nir.add_operand(builder, instruction, byte_length)
    if length_operand_error != ok { ret (0usize, length_operand_error) }
    ret (result, ok)
}

// The address and byte length of a value that is already one contiguous run of its
// canonical bytes. A scalar has no address of its own, so it is spilled to get one.
fn packed_hash_bytes_of(c: *check.Checker, ty: check.Type, value: usize, builder: *nir.Builder, token: lex.Token) -> (usize, usize, err) {
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    if ty.kind == .Slice || ty.kind == .String {
        let (element_type, element_type_error) = check.index_element_type(c, ty, ty.module_index)
        if element_type_error != ok { ret (0usize, 0usize, element_type_error) }
        let (element_info, element_info_error) = layout.type_info(c, element_type)
        if element_info_error != ok { ret (0usize, 0usize, element_info_error) }
        let (parts_data, parts_length, parts_error) = sequence_parts(c, ty, value, builder, token)
        if parts_error != ok { ret (0usize, 0usize, parts_error) }
        if element_info.size == 1usize { ret (parts_data, parts_length, ok) }
        let (stride_instruction, stride, stride_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.size, token)
        if stride_error != ok { ret (0usize, 0usize, stride_error) }
        let (scale_instruction, scaled, scale_error) = nir.emit(builder, .Multiply, usize_type, true, 0usize, token)
        if scale_error != ok { ret (0usize, 0usize, scale_error) }
        let length_operand_error = nir.add_operand(builder, scale_instruction, parts_length)
        if length_operand_error != ok { ret (0usize, 0usize, length_operand_error) }
        let stride_operand_error = nir.add_operand(builder, scale_instruction, stride)
        if stride_operand_error != ok { ret (0usize, 0usize, stride_operand_error) }
        ret (parts_data, scaled, ok)
    }
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret (0usize, 0usize, info_error) }
    var data = value
    if !aggregate_value(c, ty) {
        let (slot_instruction, slot, slot_error) = nir.emit(builder, .Stack, ty, true, 0usize, token)
        if slot_error != ok { ret (0usize, 0usize, slot_error) }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, ty, false, info.size, token)
        if store_error != ok { ret (0usize, 0usize, store_error) }
        let address_error = nir.add_operand(builder, store_instruction, slot)
        if address_error != ok { ret (0usize, 0usize, address_error) }
        let value_error = nir.add_operand(builder, store_instruction, value)
        if value_error != ok { ret (0usize, 0usize, value_error) }
        data = slot
    }
    let (size_instruction, size_value, size_error) = nir.emit(builder, .ConstInteger, usize_type, true, info.size, token)
    if size_error != ok { ret (0usize, 0usize, size_error) }
    ret (data, size_value, ok)
}

// Where a value's bytes are not contiguous -- a nested slice is a pointer, a tagged
// union payload is padded -- rule 4's recursion folds one hash per component instead
// of hashing one byte run: `acc = H(acc || h)` over the two as little-endian words,
// starting from zero. Every step is the same `neper_hash_bytes`, so no second hash
// construction and no further runtime symbol is needed.
fn emit_hash_mix(c: *check.Checker, module_index: usize, accumulator: usize, component: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let (pair_instruction, pair, pair_error) = nir.emit(builder, .Stack, u64_type, true, 2usize, token)
    if pair_error != ok { ret pair_error }
    let (accumulator_value_instruction, accumulator_value, accumulator_value_error) = nir.emit(builder, .Load, u64_type, true, 8usize, token)
    if accumulator_value_error != ok { ret accumulator_value_error }
    try nir.add_operand(builder, accumulator_value_instruction, accumulator)
    let (low_store_instruction, low_store_ignored, low_store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
    if low_store_error != ok { ret low_store_error }
    try nir.add_operand(builder, low_store_instruction, pair)
    try nir.add_operand(builder, low_store_instruction, accumulator_value)
    let (high_address_instruction, high_address, high_address_error) = nir.emit(builder, .FieldAddress, u64_type, true, 8usize, token)
    if high_address_error != ok { ret high_address_error }
    try nir.add_operand(builder, high_address_instruction, pair)
    let (high_store_instruction, high_store_ignored, high_store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
    if high_store_error != ok { ret high_store_error }
    try nir.add_operand(builder, high_store_instruction, high_address)
    try nir.add_operand(builder, high_store_instruction, component)
    let (width_instruction, width, width_error) = nir.emit(builder, .ConstInteger, usize_type, true, 16usize, token)
    if width_error != ok { ret width_error }
    let (mixed, mixed_error) = emit_hash_bytes(c, module_index, pair, width, builder, token)
    if mixed_error != ok { ret mixed_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, accumulator)
    ret nir.add_operand(builder, store_instruction, mixed)
}

fn emit_hash_seed(c: *check.Checker, module_index: usize, slot: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, u64_type, true, 0usize, token)
    if zero_error != ok { ret zero_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, slot)
    ret nir.add_operand(builder, store_instruction, zero_value)
}

fn emit_declared_hash(c: *check.Checker, function: check.Function, slot: usize, module_index: usize, value: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let (function_ref, reference_error) = nir.intern_function(builder, function.owner_module_index, function.name, function.instance_id)
    if reference_error != ok { ret reference_error }
    let (instruction, call_result, emit_error) = nir.emit(builder, .Call, u64_type, true, function_ref, token)
    if emit_error != ok { ret emit_error }
    let operand_error = nir.add_operand(builder, instruction, value)
    if operand_error != ok { ret operand_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
    if store_error != ok { ret store_error }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret address_error }
    ret nir.add_operand(builder, store_instruction, call_result)
}

fn emit_sequence_hash(c: *check.Checker, ty: check.Type, slot: usize, value: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    let module_index = ty.module_index
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (element_type, element_type_error) = check.index_element_type(c, ty, module_index)
    if element_type_error != ok { ret element_type_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let (data, length, parts_error) = sequence_parts(c, ty, value, builder, token)
    if parts_error != ok { ret parts_error }
    let seed_error = emit_hash_seed(c, module_index, slot, builder, token)
    if seed_error != ok { ret seed_error }
    let (component_slot_instruction, component_slot, component_slot_error) = nir.emit(builder, .Stack, u64_type, true, 0usize, token)
    if component_slot_error != ok { ret component_slot_error }
    let (counter_slot_instruction, counter_slot, counter_slot_error) = nir.emit(builder, .Stack, usize_type, true, 0usize, token)
    if counter_slot_error != ok { ret counter_slot_error }
    let (start_instruction, start, start_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if start_error != ok { ret start_error }
    let (start_store_instruction, start_store_ignored, start_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if start_store_error != ok { ret start_store_error }
    try nir.add_operand(builder, start_store_instruction, counter_slot)
    try nir.add_operand(builder, start_store_instruction, start)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }

    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_slot)
    let (has_next, has_next_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, length, token)
    if has_next_error != ok { ret has_next_error }
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)

    let increment_block = builder.block_count
    let (increment_index, increment_error) = nir.begin_block(builder)
    if increment_error != ok || increment_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_slot)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, usize_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, usize_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_slot)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)

    let body_block = builder.block_count
    let (body_index, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
    let (body_load_instruction, body_counter, body_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if body_load_error != ok { ret body_load_error }
    try nir.add_operand(builder, body_load_instruction, counter_slot)
    let (element, element_error) = element_operand(c, element_type, element_info.size, data, body_counter, length, builder, token)
    if element_error != ok { ret element_error }
    let component_error = emit_hash_component(c, element_type, element, component_slot, builder, token, depth + 1usize)
    if component_error != ok { ret component_error }
    let (component_load_instruction, component_value, component_load_error) = nir.emit(builder, .Load, u64_type, true, 8usize, token)
    if component_load_error != ok { ret component_load_error }
    try nir.add_operand(builder, component_load_instruction, component_slot)
    let mix_error = emit_hash_mix(c, module_index, slot, component_value, builder, token)
    if mix_error != ok { ret mix_error }
    let (body_edge, body_edge_error) = emit_branch(builder, token)
    if body_edge_error != ok { ret body_edge_error }
    try nir.set_branch_targets(builder, body_edge, increment_block, 0usize)

    let exit_block = builder.block_count
    let (exit_index, exit_error) = nir.begin_block(builder)
    if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
    ret nir.set_branch_targets(builder, decision, body_block, exit_block)
}

// Rule 4 again: the tag before the live payload. A void arm contributes nothing
// beyond its tag, which already distinguishes it.
fn emit_tagged_union_hash(c: *check.Checker, ty: check.Type, slot: usize, value: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    let module_index = ty.module_index
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (aggregate_index, found) = check.aggregate_for_type(c, ty)
    if !found { ret check.InvalidType }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .TaggedUnion || aggregate.backing_type.kind != .Integer { ret check.InvalidType }
    let tag_type = aggregate.backing_type
    let (tag_value, tag_value_error) = component_at(c, tag_type, value, 0usize, builder, token)
    if tag_value_error != ok { ret tag_value_error }
    let (component_slot_instruction, component_slot, component_slot_error) = nir.emit(builder, .Stack, u64_type, true, 0usize, token)
    if component_slot_error != ok { ret component_slot_error }
    let seed_error = emit_hash_seed(c, module_index, slot, builder, token)
    if seed_error != ok { ret seed_error }
    let tag_component_error = emit_hash_component(c, tag_type, tag_value, component_slot, builder, token, depth + 1usize)
    if tag_component_error != ok { ret tag_component_error }
    let (tag_hash_instruction, tag_hash, tag_hash_error) = nir.emit(builder, .Load, u64_type, true, 8usize, token)
    if tag_hash_error != ok { ret tag_hash_error }
    try nir.add_operand(builder, tag_hash_instruction, component_slot)
    let tag_mix_error = emit_hash_mix(c, module_index, slot, tag_hash, builder, token)
    if tag_mix_error != ok { ret tag_mix_error }

    var tests: [32]usize = zero
    var decisions: [32]usize = zero
    var bodies: [32]usize = zero
    var exits: [32]usize = zero
    var arm_count = 0usize
    var at = 0usize
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret check.InvalidType }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            if arm_count == tests.len { ret check.Capacity }
            let (payload, payload_error) = layout.field(c, ty, arm.name)
            if payload_error != ok { ret payload_error }
            let (arm_bits, arm_bits_error) = check.enum_member_bits(tag_type, arm.enum_value, arm.enum_negative)
            if arm_bits_error != ok { ret arm_bits_error }
            let test_block = builder.block_count
            let (test_index, test_error) = nir.begin_block(builder)
            if test_error != ok || test_index != test_block { ret nir.InvalidControlFlow }
            if arm_count == 0usize { try nir.set_branch_targets(builder, entry_branch, test_block, 0usize) }
            let (arm_constant_instruction, arm_constant, arm_constant_error) = nir.emit(builder, .ConstInteger, tag_type, true, arm_bits, token)
            if arm_constant_error != ok { ret arm_constant_error }
            let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, tag_value, arm_constant, token)
            if matches_error != ok { ret matches_error }
            let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
            if decision_error != ok { ret decision_error }
            try nir.add_operand(builder, decision, matches)
            let body_block = builder.block_count
            let (body_index, body_error) = nir.begin_block(builder)
            if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
            let (payload_value, payload_value_error) = component_at(c, payload.ty, value, payload.offset, builder, token)
            if payload_value_error != ok { ret payload_value_error }
            let payload_component_error = emit_hash_component(c, payload.ty, payload_value, component_slot, builder, token, depth + 1usize)
            if payload_component_error != ok { ret payload_component_error }
            let (payload_hash_instruction, payload_hash, payload_hash_error) = nir.emit(builder, .Load, u64_type, true, 8usize, token)
            if payload_hash_error != ok { ret payload_hash_error }
            try nir.add_operand(builder, payload_hash_instruction, component_slot)
            let payload_mix_error = emit_hash_mix(c, module_index, slot, payload_hash, builder, token)
            if payload_mix_error != ok { ret payload_mix_error }
            let (exit, exit_error) = emit_branch(builder, token)
            if exit_error != ok { ret exit_error }
            tests[arm_count] = test_block
            decisions[arm_count] = decision
            bodies[arm_count] = body_block
            exits[arm_count] = exit
            arm_count += 1usize
        }
        at += 1usize
    }

    let default_block = builder.block_count
    let (default_index, default_error) = nir.begin_block(builder)
    if default_error != ok || default_index != default_block { ret nir.InvalidControlFlow }
    if arm_count == 0usize { try nir.set_branch_targets(builder, entry_branch, default_block, 0usize) }
    let (default_exit, default_exit_error) = emit_branch(builder, token)
    if default_exit_error != ok { ret default_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    var patch_at = 0usize
    while patch_at < arm_count {
        var next_block = default_block
        if patch_at + 1usize < arm_count { next_block = tests[patch_at + 1usize] }
        try nir.set_branch_targets(builder, decisions[patch_at], bodies[patch_at], next_block)
        try nir.set_branch_targets(builder, exits[patch_at], done_block, 0usize)
        patch_at += 1usize
    }
    ret nir.set_branch_targets(builder, default_exit, done_block, 0usize)
}

fn emit_hash_component(c: *check.Checker, ty: check.Type, value: usize, slot: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let module_index = ty.module_index
    let u64_type = check.make_type(.Integer, "u64", module_index)
    let (function_index, has_function) = check.element_hash_function(c, ty)
    if has_function { ret emit_declared_hash(c, c.functions[function_index], slot, module_index, value, builder, token) }
    if check.hash_packed_shape(c, ty) {
        let (data, byte_length, bytes_error) = packed_hash_bytes_of(c, ty, value, builder, token)
        if bytes_error != ok { ret bytes_error }
        let (hashed, hash_error) = emit_hash_bytes(c, module_index, data, byte_length, builder, token)
        if hash_error != ok { ret hash_error }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, u64_type, false, 8usize, token)
        if store_error != ok { ret store_error }
        let address_error = nir.add_operand(builder, store_instruction, slot)
        if address_error != ok { ret address_error }
        ret nir.add_operand(builder, store_instruction, hashed)
    }
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String {
        ret emit_sequence_hash(c, ty, slot, value, builder, token, depth)
    }
    if check.is_tagged_union_type(c, ty) {
        ret emit_tagged_union_hash(c, ty, slot, value, builder, token, depth)
    }
    ret check.Unsupported
}

fn emit_supplied_hash(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if argument_count != 1usize { ret check.ArgumentCount }
    let ty = call.protocol_type
    let u64_type = check.make_type(.Integer, "u64", ty.module_index)
    let (slot_instruction, slot, slot_error) = nir.emit(builder, .Stack, u64_type, true, 0usize, token)
    if slot_error != ok { ret slot_error }
    let component_error = emit_hash_component(c, ty, arguments[0usize], slot, builder, token, 0usize)
    if component_error != ok { ret component_error }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, u64_type, true, 8usize, token)
    if load_error != ok { ret load_error }
    let load_operand_error = nir.add_operand(builder, load_instruction, slot)
    if load_operand_error != ok { ret load_operand_error }
    results.call = call
    results.count = 1usize
    results.values[0usize] = result
    results.addresses[0usize] = false
    ret ok
}

fn store_supplied_eq_result(builder: *nir.Builder, slot: usize, boolean: check.Type, value: usize, token: lex.Token) -> (usize, err) {
    let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstBool, boolean, true, value, token)
    if constant_error != ok { ret (0usize, constant_error) }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, boolean, false, 0usize, token)
    if store_error != ok { ret (0usize, store_error) }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret (0usize, address_error) }
    let value_error = nir.add_operand(builder, store_instruction, constant)
    if value_error != ok { ret (0usize, value_error) }
    let (exit_branch, exit_error) = emit_branch(builder, token)
    ret (exit_branch, exit_error)
}

// A component whose own module declares `fn <t>_eq` is compared by calling it, the
// same direct call an ordinary `T.eq(a, b)` lowers to.
fn emit_declared_eq(c: *check.Checker, function: check.Function, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let (function_ref, reference_error) = nir.intern_function(builder, function.owner_module_index, function.name, function.instance_id)
    if reference_error != ok { ret reference_error }
    let (instruction, call_result, emit_error) = nir.emit(builder, .Call, boolean, true, function_ref, token)
    if emit_error != ok { ret emit_error }
    let left_operand_error = nir.add_operand(builder, instruction, left)
    if left_operand_error != ok { ret left_operand_error }
    let right_operand_error = nir.add_operand(builder, instruction, right)
    if right_operand_error != ok { ret right_operand_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, boolean, false, 0usize, token)
    if store_error != ok { ret store_error }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret address_error }
    ret nir.add_operand(builder, store_instruction, call_result)
}

// Rule 4 supplies `eq` for the same shapes as `cmp` and adds pointers, whose
// equality is address equality. A scalar is one comparison: unlike ordering, nothing
// here depends on signedness, so an enum needs no cast to its backing type.
fn emit_scalar_eq(c: *check.Checker, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let (equal, equal_error) = emit_supplied_compare(builder, .Equal, boolean, left, right, token)
    if equal_error != ok { ret equal_error }
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, boolean, false, 0usize, token)
    if store_error != ok { ret store_error }
    let address_error = nir.add_operand(builder, store_instruction, slot)
    if address_error != ok { ret address_error }
    ret nir.add_operand(builder, store_instruction, equal)
}

// Rule 4's float equality is the container rule, not IEEE's: every NaN equals every other
// and the two zeros are one. `==` already makes the zeros one, so what is added is the pair
// of self-comparisons that only a NaN fails -- `a == b || (a != a && b != b)`.
fn emit_float_eq(c: *check.Checker, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let (equal, equal_error) = emit_supplied_compare(builder, .Equal, boolean, left, right, token)
    if equal_error != ok { ret equal_error }
    let (left_nan, left_nan_error) = emit_supplied_compare(builder, .NotEqual, boolean, left, left, token)
    if left_nan_error != ok { ret left_nan_error }
    let (right_nan, right_nan_error) = emit_supplied_compare(builder, .NotEqual, boolean, right, right, token)
    if right_nan_error != ok { ret right_nan_error }
    let (both_nan_instruction, both_nan, both_nan_error) = nir.emit(builder, .BitAnd, boolean, true, 0usize, token)
    if both_nan_error != ok { ret both_nan_error }
    try nir.add_operand(builder, both_nan_instruction, left_nan)
    try nir.add_operand(builder, both_nan_instruction, right_nan)
    let (either_instruction, either, either_error) = nir.emit(builder, .BitOr, boolean, true, 0usize, token)
    if either_error != ok { ret either_error }
    try nir.add_operand(builder, either_instruction, equal)
    try nir.add_operand(builder, either_instruction, both_nan)
    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, boolean, false, 0usize, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, slot)
    ret nir.add_operand(builder, store_instruction, either)
}

// A slice's `eq` is over its contents, so unequal lengths are unequal outright and
// the walk stops at the first element that differs.
fn emit_sequence_eq(c: *check.Checker, ty: check.Type, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (element_type, element_type_error) = check.index_element_type(c, ty, ty.module_index)
    if element_type_error != ok { ret element_type_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let usize_type = check.make_type(.Integer, "usize", ty.module_index)
    let (left_data, left_length, left_parts_error) = sequence_parts(c, ty, left, builder, token)
    if left_parts_error != ok { ret left_parts_error }
    let (right_data, right_length, right_parts_error) = sequence_parts(c, ty, right, builder, token)
    if right_parts_error != ok { ret right_parts_error }
    let (element_slot_instruction, element_slot, element_slot_error) = nir.emit(builder, .Stack, boolean, true, 0usize, token)
    if element_slot_error != ok { ret element_slot_error }
    let (counter_slot_instruction, counter_slot, counter_slot_error) = nir.emit(builder, .Stack, usize_type, true, 0usize, token)
    if counter_slot_error != ok { ret counter_slot_error }
    let (start_instruction, start, start_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if start_error != ok { ret start_error }
    let (start_store_instruction, start_store_ignored, start_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if start_store_error != ok { ret start_store_error }
    try nir.add_operand(builder, start_store_instruction, counter_slot)
    try nir.add_operand(builder, start_store_instruction, start)
    let (same_length, same_length_error) = emit_supplied_compare(builder, .Equal, boolean, left_length, right_length, token)
    if same_length_error != ok { ret same_length_error }
    let (length_decision, length_decision_ignored, length_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if length_decision_error != ok { ret length_decision_error }
    try nir.add_operand(builder, length_decision, same_length)

    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_slot)
    let (has_next, has_next_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, left_length, token)
    if has_next_error != ok { ret has_next_error }
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)

    let increment_block = builder.block_count
    let (increment_index, increment_error) = nir.begin_block(builder)
    if increment_error != ok || increment_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_slot)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, usize_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, usize_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_slot)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)

    let body_block = builder.block_count
    let (body_index, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
    let (body_load_instruction, body_counter, body_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if body_load_error != ok { ret body_load_error }
    try nir.add_operand(builder, body_load_instruction, counter_slot)
    let (left_element, left_element_error) = element_operand(c, element_type, element_info.size, left_data, body_counter, left_length, builder, token)
    if left_element_error != ok { ret left_element_error }
    let (right_element, right_element_error) = element_operand(c, element_type, element_info.size, right_data, body_counter, right_length, builder, token)
    if right_element_error != ok { ret right_element_error }
    let element_error = emit_eq_into(c, element_type, element_slot, boolean, left_element, right_element, builder, token, depth + 1usize)
    if element_error != ok { ret element_error }
    let (element_load_instruction, element_result, element_load_error) = nir.emit(builder, .Load, boolean, true, 0usize, token)
    if element_load_error != ok { ret element_load_error }
    try nir.add_operand(builder, element_load_instruction, element_slot)
    let (element_decision, element_decision_ignored, element_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if element_decision_error != ok { ret element_decision_error }
    try nir.add_operand(builder, element_decision, element_result)

    let equal_block = builder.block_count
    let (equal_index, equal_error) = nir.begin_block(builder)
    if equal_error != ok || equal_index != equal_block { ret nir.InvalidControlFlow }
    let (equal_exit, equal_exit_error) = store_supplied_eq_result(builder, slot, boolean, 1usize, token)
    if equal_exit_error != ok { ret equal_exit_error }

    let differ_block = builder.block_count
    let (differ_index, differ_error) = nir.begin_block(builder)
    if differ_error != ok || differ_index != differ_block { ret nir.InvalidControlFlow }
    let (differ_exit, differ_exit_error) = store_supplied_eq_result(builder, slot, boolean, 0usize, token)
    if differ_exit_error != ok { ret differ_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, length_decision, condition_block, differ_block)
    try nir.set_branch_targets(builder, decision, body_block, equal_block)
    try nir.set_branch_targets(builder, element_decision, increment_block, differ_block)
    try nir.set_branch_targets(builder, equal_exit, done_block, 0usize)
    ret nir.set_branch_targets(builder, differ_exit, done_block, 0usize)
}

// Rule 4 again: the tag decides first, and only a matching tag reaches the payload.
fn emit_tagged_union_eq(c: *check.Checker, ty: check.Type, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (aggregate_index, found) = check.aggregate_for_type(c, ty)
    if !found { ret check.InvalidType }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .TaggedUnion || aggregate.backing_type.kind != .Integer { ret check.InvalidType }
    let tag_type = aggregate.backing_type
    let (left_tag, left_tag_error) = component_at(c, tag_type, left, 0usize, builder, token)
    if left_tag_error != ok { ret left_tag_error }
    let (right_tag, right_tag_error) = component_at(c, tag_type, right, 0usize, builder, token)
    if right_tag_error != ok { ret right_tag_error }
    let (tags_equal, tags_equal_error) = emit_supplied_compare(builder, .Equal, boolean, left_tag, right_tag, token)
    if tags_equal_error != ok { ret tags_equal_error }
    let (tag_decision, tag_decision_ignored, tag_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if tag_decision_error != ok { ret tag_decision_error }
    try nir.add_operand(builder, tag_decision, tags_equal)

    var tests: [32]usize = zero
    var decisions: [32]usize = zero
    var bodies: [32]usize = zero
    var exits: [32]usize = zero
    var arm_count = 0usize
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret check.InvalidType }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            if arm_count == tests.len { ret check.Capacity }
            let (payload, payload_error) = layout.field(c, ty, arm.name)
            if payload_error != ok { ret payload_error }
            let (arm_bits, arm_bits_error) = check.enum_member_bits(tag_type, arm.enum_value, arm.enum_negative)
            if arm_bits_error != ok { ret arm_bits_error }
            let test_block = builder.block_count
            let (test_index, test_error) = nir.begin_block(builder)
            if test_error != ok || test_index != test_block { ret nir.InvalidControlFlow }
            let (arm_constant_instruction, arm_constant, arm_constant_error) = nir.emit(builder, .ConstInteger, tag_type, true, arm_bits, token)
            if arm_constant_error != ok { ret arm_constant_error }
            let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, left_tag, arm_constant, token)
            if matches_error != ok { ret matches_error }
            let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
            if decision_error != ok { ret decision_error }
            try nir.add_operand(builder, decision, matches)
            let body_block = builder.block_count
            let (body_index, body_error) = nir.begin_block(builder)
            if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
            let (left_payload, left_payload_error) = component_at(c, payload.ty, left, payload.offset, builder, token)
            if left_payload_error != ok { ret left_payload_error }
            let (right_payload, right_payload_error) = component_at(c, payload.ty, right, payload.offset, builder, token)
            if right_payload_error != ok { ret right_payload_error }
            let payload_eq_error = emit_eq_into(c, payload.ty, slot, boolean, left_payload, right_payload, builder, token, depth + 1usize)
            if payload_eq_error != ok { ret payload_eq_error }
            let (exit, exit_error) = emit_branch(builder, token)
            if exit_error != ok { ret exit_error }
            tests[arm_count] = test_block
            decisions[arm_count] = decision
            bodies[arm_count] = body_block
            exits[arm_count] = exit
            arm_count += 1usize
        }
        at += 1usize
    }

    // A void arm carries nothing, so matching tags already settle it.
    let default_block = builder.block_count
    let (default_index, default_error) = nir.begin_block(builder)
    if default_error != ok || default_index != default_block { ret nir.InvalidControlFlow }
    let (default_exit, default_exit_error) = store_supplied_eq_result(builder, slot, boolean, 1usize, token)
    if default_exit_error != ok { ret default_exit_error }

    let differ_block = builder.block_count
    let (differ_index, differ_error) = nir.begin_block(builder)
    if differ_error != ok || differ_index != differ_block { ret nir.InvalidControlFlow }
    let (differ_exit, differ_exit_error) = store_supplied_eq_result(builder, slot, boolean, 0usize, token)
    if differ_exit_error != ok { ret differ_exit_error }

    let done_block = builder.block_count
    let (done_index, done_error) = nir.begin_block(builder)
    if done_error != ok || done_index != done_block { ret nir.InvalidControlFlow }
    var dispatch_block = default_block
    if arm_count != 0usize { dispatch_block = tests[0usize] }
    try nir.set_branch_targets(builder, tag_decision, dispatch_block, differ_block)
    var patch_at = 0usize
    while patch_at < arm_count {
        var next_block = default_block
        if patch_at + 1usize < arm_count { next_block = tests[patch_at + 1usize] }
        try nir.set_branch_targets(builder, decisions[patch_at], bodies[patch_at], next_block)
        try nir.set_branch_targets(builder, exits[patch_at], done_block, 0usize)
        patch_at += 1usize
    }
    try nir.set_branch_targets(builder, default_exit, done_block, 0usize)
    ret nir.set_branch_targets(builder, differ_exit, done_block, 0usize)
}

fn emit_eq_into(c: *check.Checker, ty: check.Type, slot: usize, boolean: check.Type, left: usize, right: usize, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String {
        ret emit_sequence_eq(c, ty, slot, boolean, left, right, builder, token, depth)
    }
    if ty.kind == .Float { ret emit_float_eq(c, slot, boolean, left, right, builder, token) }
    let (function_index, has_function) = check.element_eq_function(c, ty)
    if has_function { ret emit_declared_eq(c, c.functions[function_index], slot, boolean, left, right, builder, token) }
    if check.is_tagged_union_type(c, ty) {
        ret emit_tagged_union_eq(c, ty, slot, boolean, left, right, builder, token, depth)
    }
    ret emit_scalar_eq(c, slot, boolean, left, right, builder, token)
}

fn emit_supplied_eq(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if argument_count != 2usize { ret check.ArgumentCount }
    let boolean = check.make_type(.Bool, "bool", call.protocol_type.module_index)
    let (slot_instruction, slot, slot_error) = nir.emit(builder, .Stack, boolean, true, 0usize, token)
    if slot_error != ok { ret slot_error }
    let eq_error = emit_eq_into(c, call.protocol_type, slot, boolean, arguments[0usize], arguments[1usize], builder, token, 0usize)
    if eq_error != ok { ret eq_error }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, boolean, true, 0usize, token)
    if load_error != ok { ret load_error }
    let load_operand_error = nir.add_operand(builder, load_instruction, slot)
    if load_operand_error != ok { ret load_operand_error }
    results.call = call
    results.count = 1usize
    results.values[0usize] = result
    results.addresses[0usize] = false
    ret ok
}

// `mem.view` is the one arena intrinsic with no runtime symbol behind it: turning a
// base pointer and an offset into a slice is three instructions, so it is emitted
// where it is called rather than through `neper_mem_*`. A slice value is the address
// of a {pointer, length} pair, which is what `sequence_parts` reads back.
fn emit_mem_view(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if argument_count != 3usize { ret check.ArgumentCount }
    let module_index = call.function.module_index
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let (result_type, result_type_error) = check.call_return(c, call, 0usize)
    if result_type_error != ok { ret result_type_error }
    // Arena.base is the first field, so the arena pointer addresses it directly.
    let (base_address_instruction, base_address, base_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if base_address_error != ok { ret base_address_error }
    try nir.add_operand(builder, base_address_instruction, arguments[0usize])
    let (base_instruction, base, base_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, token)
    if base_error != ok { ret base_error }
    try nir.add_operand(builder, base_instruction, base_address)
    let (offset_instruction, offset, offset_error) = nir.emit(builder, .Add, pointer_type, true, 0usize, token)
    if offset_error != ok { ret offset_error }
    try nir.add_operand(builder, offset_instruction, base)
    try nir.add_operand(builder, offset_instruction, arguments[1usize])
    let (slice_instruction, slice, slice_error) = nir.emit(builder, .Stack, result_type, true, 2usize, token)
    if slice_error != ok { ret slice_error }
    let (data_store_instruction, data_store_ignored, data_store_error) = nir.emit(builder, .Store, pointer_type, false, 8usize, token)
    if data_store_error != ok { ret data_store_error }
    try nir.add_operand(builder, data_store_instruction, slice)
    try nir.add_operand(builder, data_store_instruction, offset)
    let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, token)
    if length_address_error != ok { ret length_address_error }
    try nir.add_operand(builder, length_address_instruction, slice)
    let (length_store_instruction, length_store_ignored, length_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if length_store_error != ok { ret length_store_error }
    try nir.add_operand(builder, length_store_instruction, length_address)
    try nir.add_operand(builder, length_store_instruction, arguments[2usize])
    results.call = call
    results.count = 1usize
    results.values[0usize] = slice
    results.addresses[0usize] = true
    ret ok
}

// `T` is settled, so the pointer parameter is `*Atomic[T]`, the value parameters are
// `T` and the trailing ones are the ordering enum.
fn atomic_parameter_type(c: *check.Checker, call: check.CallInfo, index: usize) -> check.Type {
    let ordering = check.make_type(.Named, "Ordering", call.function.module_index)
    if call.atomic_op == .Fence { ret ordering }
    if call.atomic_op == .Init { ret call.atomic_element }
    if index == 0usize {
        let (stored, store_error) = check.store_type(c, check.atomic_wrapper_type(c, call.atomic_element, call.function.module_index))
        if store_error != ok { ret check.invalid_type() }
        var pointer = check.make_type(.Pointer, "", call.function.module_index)
        pointer.element = stored
        pointer.has_element = true
        ret pointer
    }
    var value_positions = 1usize
    if call.atomic_op == .Cas { value_positions = 2usize }
    if call.atomic_op == .Load { value_positions = 0usize }
    if index <= value_positions { ret call.atomic_element }
    ret ordering
}

fn atomic_rmw_kind(op: check.AtomicOp) -> nir.AtomicRmwKind {
    if op == .Add { ret .Add }
    if op == .Sub { ret .Sub }
    if op == .And { ret .And }
    if op == .Or { ret .Or }
    if op == .Xor { ret .Xor }
    if op == .Min { ret .Min }
    if op == .Max { ret .Max }
    ret .Xchg
}

// Section 8's operations, each one instruction. An ordering nobody could read at
// compile time lowers as `SeqCst`: stronger is always safe, and on this target every
// ordering but that one costs nothing anyway.
fn emit_atomic(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    results.call = call
    results.count = call.function.return_count
    let element = call.atomic_element
    let ordering = check.atomic_ordering_rank(call.atomic_success)
    if call.atomic_op == .Fence {
        let (instruction, ignored, emit_error) = nir.emit(builder, .AtomicFence, element, false, ordering, token)
        ret emit_error
    }
    // `init(v)` is the one operation that touches no shared location: it builds the
    // `Atomic[T]` the caller is about to store, so it is an ordinary aggregate value.
    if call.atomic_op == .Init {
        if argument_count != 1usize { ret check.ArgumentCount }
        let wrapper = check.atomic_wrapper_type(c, element, call.function.module_index)
        let (info, info_error) = layout.type_info(c, wrapper)
        if info_error != ok { ret info_error }
        var slots = (info.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, wrapper, true, slots, token)
        if stack_error != ok { ret stack_error }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, element, false, info.size, token)
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, arguments[0usize])
        results.values[0usize] = stack
        results.addresses[0usize] = true
        ret ok
    }
    if argument_count < 2usize { ret check.ArgumentCount }
    if call.atomic_op == .Load {
        let (instruction, value, emit_error) = nir.emit(builder, .AtomicLoad, element, true, ordering, token)
        if emit_error != ok { ret emit_error }
        try nir.add_operand(builder, instruction, arguments[0usize])
        results.values[0usize] = value
        ret ok
    }
    if call.atomic_op == .Store {
        let (instruction, ignored, emit_error) = nir.emit(builder, .AtomicStore, element, false, ordering, token)
        if emit_error != ok { ret emit_error }
        try nir.add_operand(builder, instruction, arguments[0usize])
        try nir.add_operand(builder, instruction, arguments[1usize])
        ret ok
    }
    if call.atomic_op == .Cas {
        if argument_count < 3usize { ret check.ArgumentCount }
        let failure = check.atomic_ordering_rank(call.atomic_failure)
        let (instruction, previous, emit_error) = nir.emit(builder, .AtomicCas, element, true, ordering * 8usize + failure, token)
        if emit_error != ok { ret emit_error }
        try nir.add_operand(builder, instruction, arguments[0usize])
        try nir.add_operand(builder, instruction, arguments[1usize])
        try nir.add_operand(builder, instruction, arguments[2usize])
        // A strong compare-and-swap exchanged exactly when what it found was what was
        // expected, so the `bool` is that comparison and needs no result of its own.
        let bool_type = check.make_type(.Bool, "bool", call.function.module_index)
        let (compare_instruction, won, compare_error) = nir.emit(builder, .Equal, bool_type, true, 0usize, token)
        if compare_error != ok { ret compare_error }
        try nir.add_operand(builder, compare_instruction, previous)
        try nir.add_operand(builder, compare_instruction, arguments[1usize])
        results.values[0usize] = won
        results.values[1usize] = previous
        ret ok
    }
    let (instruction, previous, emit_error) = nir.emit(builder, .AtomicRmw, element, true, nir.atomic_rmw_immediate(atomic_rmw_kind(call.atomic_op), ordering), token)
    if emit_error != ok { ret emit_error }
    try nir.add_operand(builder, instruction, arguments[0usize])
    try nir.add_operand(builder, instruction, arguments[1usize])
    results.values[0usize] = previous
    ret ok
}

// Section 12's cross-module inlining cap: a callee of at most this many NIR instructions
// is copied into its caller rather than called.
fn inline_cap() -> usize { ret 40usize }

fn find_inline_entry(builder: *nir.Builder, module_index: usize, name: str, instance: usize) -> (usize, bool) {
    var at = 0usize
    while at < builder.inline_entry_count {
        let entry = builder.inline_entries[at]
        if entry.module_index == module_index && entry.instance == instance && check.same(entry.name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// The oracle: every non-generic function of every module whose source is short is
// lowered into a builder of its own before the program is, and the ones that came out
// at the cap or under, took no hidden return slot and return at most one value are
// entered. Lowering a function twice is what this costs; the checker's state after it
// is the same, since instances it creates are the ones the program's own lowering
// would create at the same call. The order is the module order, on both link paths.
fn build_inline_oracle(c: *check.Checker, g: *graph.Graph, oracle: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, entries: []nir.InlineEntry, entry_count: *usize) -> err {
    try begin_inline_oracle(c, oracle, entry_count)
    var oracle_defers: DeferState = zero
    var entry_cursor = 0usize
    // The graph order when there is one (D313): the driver's body sweep walks it, and
    // the second oracle's cursor over the first's entries needs the two to agree.
    var order_at = 0usize
    while order_at < g.count {
        var module_index = order_at
        if g.order_count == g.count { module_index = g.order[order_at] }
        try oracle_module(c, g, oracle, signatures, bindings, entries, entry_count, module_index, &entry_cursor, &oracle_defers)
        order_at += 1usize
    }
    ret ok
}

fn begin_inline_oracle(c: *check.Checker, oracle: *nir.Builder, entry_count: *usize) -> err {
    try declare_globals(c, oracle)
    *entry_count = 0usize
    ret ok
}

// One module's share of the oracle (D313): called per module in module order, either
// by `build_inline_oracle` or by the driver's body sweep right after the module's
// bodies are checked, which is the parse the module already had. The cursor and the
// defer stack are the walk's, carried between calls.
fn oracle_module(c: *check.Checker, g: *graph.Graph, oracle: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, entries: []nir.InlineEntry, entry_count: *usize, module_index: usize, cursor: *usize, oracle_defers: *DeferState) -> err {
    // An unparsed module (D322) has nothing the program lowers; both oracles skip it.
    if !g.modules[module_index].has_tree { ret ok }
    // The second oracle visits the first's entries alone (D310), and a module with
    // none of them is not even parsed (D313): with one candidate in a thousand
    // functions kept, the second pass was a parse of the whole program for nothing.
    if oracle.has_oracle {
        if *cursor >= oracle.inline_entry_count { ret ok }
        if oracle.inline_entries[*cursor].walked_in != module_index { ret ok }
    }
    var entry_cursor = *cursor
    var tree: parse.Tree = zero
    try graph.parse_module(g, module_index, &tree)
    try check.tokenize_module(c, g, module_index)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl && usize(node.token_end) - usize(node.token_start) <= 100usize {
            let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
            if name_error != ok { ret name_error }
            let (function_index, found) = check.find_function(c, module_index, name)
            if found {
                let function = c.functions[function_index]
                // The second oracle (D212) is built against the first, and inlining into a
                // body only lengthens it, so a body the first oracle rejected stays
                // rejected: the second visits the first's entries alone (D310). The
                // entries were recorded in this same walk order, so a cursor finds them.
                var wanted = true
                if oracle.has_oracle {
                    wanted = false
                    if entry_cursor < oracle.inline_entry_count {
                        let previous = oracle.inline_entries[entry_cursor]
                        if previous.module_index == function.owner_module_index && previous.instance == function.instance_id && check.same(previous.name, name) {
                            wanted = true
                            entry_cursor += 1usize
                        }
                    }
                }
                if wanted && !function.generic && !function.external && !function.intrinsic && !check.same(name, "main") && function.return_count <= 1usize {
                    // A result that comes back through a slot is decided before any lowering.
                    var hidden = false
                    if function.return_count == 1usize {
                        var function_call: check.CallInfo = zero
                        function_call.function = function
                        var return_layout: ReturnLayout = zero
                        try call_return_layout(c, function_call, &return_layout)
                        hidden = return_layout.via_slot
                    }
                    if hidden {
                        node_index += 1usize
                        continue
                    }
                    let before = oracle.function_count
                    let checkpoint = nir.mark(oracle)
                    let local_checkpoint = c.local_count
                    oracle.limit_base = oracle.instruction_count
                    oracle.instruction_limit = inline_cap() + 1usize
                    let lower_error = lower_function_index(c, g, &tree, module_index, node, function_index, oracle, signatures, bindings, oracle_defers)
                    oracle.instruction_limit = 0usize
                    if lower_error == nir.TooLong {
                        // Past the cap: what was lowered so far goes, and so does the function.
                        nir.reset(oracle, checkpoint)
                        c.local_count = local_checkpoint
                        node_index += 1usize
                        continue
                    }
                    if lower_error != ok { ret lower_error }
                    let lowered = oracle.functions[before]
                    // A body that calls a generic instance stays out: an instance is the
                    // instantiating module's own copy, not the target of anyone's edge,
                    // and a copy of the call in another module would name it anyway.
                    var calls_instance = false
                    var scan_at = lowered.first_instruction
                    while scan_at < lowered.first_instruction + lowered.instruction_count {
                        let scanned = oracle.instructions[scan_at]
                        if (scanned.opcode == .Call || scanned.opcode == .FunctionAddress) && scanned.immediate < oracle.function_ref_count && oracle.function_refs[scanned.immediate].instance != 0usize { calls_instance = true }
                        scan_at += 1usize
                    }
                    if lowered.instruction_count <= inline_cap() && !calls_instance {
                        let entry_at = *entry_count
                        if entry_at == entries.len { ret check.Capacity }
                        var entry: nir.InlineEntry = zero
                        entry.module_index = function.owner_module_index
                        entry.name = name
                        entry.instance = function.instance_id
                        entry.function_index = before
                        entry.walked_in = module_index
                        entry.oracle = oracle
                        entry.checker = c
                        entries[entry_at] = entry
                        *entry_count = entry_at + 1usize
                    } else {
                        nir.reset(oracle, checkpoint)
                    }
                }
            }
        }
        node_index += 1usize
    }
    *cursor = entry_cursor
    ret ok
}

// A type from another worker's checker, made this checker's (D326): the declarations
// are the same rows in both, so a type over them is itself; an element type in the
// other's tail is stored here, an instance aggregate there is instantiated here from
// the same template and arguments, and a function signature there is copied here.
fn import_type(c: *check.Checker, source: *check.Checker, ty: check.Type) -> (check.Type, err) {
    if !ty.has_element { ret (ty, ok) }
    var imported = ty
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if ty.element < c.fork_types { ret (ty, ok) }
        if ty.element >= source.type_count { ret (ty, check.InvalidType) }
        let (element, element_error) = import_type(c, source, source.types[ty.element])
        if element_error != ok { ret (ty, element_error) }
        let (stored, store_error) = check.store_type(c, element)
        if store_error != ok { ret (ty, store_error) }
        imported.element = stored
        ret (imported, ok)
    }
    if ty.kind == .Named || ty.kind == .Tag {
        if ty.element < c.fork_aggregates { ret (ty, ok) }
        let (instance, instance_error) = import_aggregate(c, source, ty.element)
        if instance_error != ok { ret (ty, instance_error) }
        imported.element = instance
        ret (imported, ok)
    }
    if ty.kind == .Function {
        if ty.element < c.fork_signatures { ret (ty, ok) }
        if ty.element >= source.function_signature_count { ret (ty, check.InvalidType) }
        let signature = source.function_signatures[ty.element]
        var parameter_types: [32]check.Type = zero
        var return_types: [8]check.Type = zero
        if signature.parameter_count > parameter_types.len || signature.return_count > return_types.len { ret (ty, check.Capacity) }
        var at = 0usize
        while at < signature.parameter_count {
            if signature.first_parameter + at >= source.type_count { ret (ty, check.InvalidType) }
            let (parameter, parameter_error) = import_type(c, source, source.types[signature.first_parameter + at])
            if parameter_error != ok { ret (ty, parameter_error) }
            parameter_types[at] = parameter
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            if signature.first_return + at >= source.type_count { ret (ty, check.InvalidType) }
            let (returned, returned_error) = import_type(c, source, source.types[signature.first_return + at])
            if returned_error != ok { ret (ty, returned_error) }
            return_types[at] = returned
            at += 1usize
        }
        var copied: check.FunctionSignature = zero
        copied.parameter_count = signature.parameter_count
        copied.return_count = signature.return_count
        copied.first_parameter = c.type_count
        at = 0usize
        while at < signature.parameter_count {
            let (stored, store_error) = check.store_type(c, parameter_types[at])
            if store_error != ok { ret (ty, store_error) }
            at += 1usize
        }
        copied.first_return = c.type_count
        at = 0usize
        while at < signature.return_count {
            let (stored, store_error) = check.store_type(c, return_types[at])
            if store_error != ok { ret (ty, store_error) }
            at += 1usize
        }
        let (index, signature_error) = check.store_function_signature(c, copied)
        if signature_error != ok { ret (ty, signature_error) }
        imported.element = index
        ret (imported, ok)
    }
    ret (ty, ok)
}

// An instance aggregate of another worker's checker, instantiated here from the same
// template and arguments, which finds it when this checker made it already.
fn import_aggregate(c: *check.Checker, source: *check.Checker, index: usize) -> (usize, err) {
    if index >= source.aggregate_count { ret (0usize, check.InvalidType) }
    let instance = source.aggregates[index]
    if !instance.instance || instance.template_index >= c.fork_aggregates { ret (0usize, check.InvalidType) }
    let template = c.aggregates[instance.template_index]
    if c.generic_argument_count + template.comptime_count > c.generic_arguments.len { ret (0usize, check.Capacity) }
    var arguments: [16]check.GenericArgument = zero
    if template.comptime_count > arguments.len { ret (0usize, check.Capacity) }
    var at = 0usize
    while at < template.comptime_count {
        if instance.first_argument + at >= source.generic_argument_count { ret (0usize, check.InvalidType) }
        var argument = source.generic_arguments[instance.first_argument + at]
        let (argument_type, argument_type_error) = import_type(c, source, argument.ty)
        if argument_type_error != ok { ret (0usize, argument_type_error) }
        argument.ty = argument_type
        if (argument.kind == .Field || argument.kind == .Member) && argument.owner >= c.fork_aggregates {
            let (owner, owner_error) = import_aggregate(c, source, argument.owner)
            if owner_error != ok { ret (0usize, owner_error) }
            argument.owner = owner
        }
        arguments[at] = argument
        at += 1usize
    }
    // The block is claimed whole after every argument is imported, as the checker
    // claims its own (D145): an import in between would land in it.
    let first = c.generic_argument_count
    c.generic_argument_count += template.comptime_count
    at = 0usize
    while at < template.comptime_count {
        c.generic_arguments[first + at] = arguments[at]
        at += 1usize
    }
    let (made, make_error) = check.instantiate_aggregate(c, instance.template_index, first)
    if make_error != ok { ret (0usize, make_error) }
    ret (made, ok)
}

// The oracle's function copied in at a call site: the current block branches to a copy
// of the callee's blocks, `Parameter` becomes the argument, `Return` becomes a branch
// to the continuation block, and the result is the returned value when the callee
// returns once, or a stack slot every return stores to when it returns from several
// places. References into the oracle's tables -- functions, strings, globals -- are
// re-interned here. The body edge the artifact needs is recorded on the builder.
fn record_inlined(builder: *nir.Builder, callee_module: usize, name: str, instance: usize) -> err {
    let caller_module = builder.functions[builder.current_function].module_index
    var recorded_at = 0usize
    while recorded_at < builder.inlined_count {
        let prior = builder.inlined[recorded_at]
        if prior.caller_module == caller_module && prior.caller_function == builder.current_function && prior.callee_module == callee_module && prior.instance == instance && check.same(prior.name, name) { ret ok }
        recorded_at += 1usize
    }
    if builder.inlined_count == builder.inlined.len { ret check.Capacity }
    var record: nir.InlinedRef = zero
    record.caller_module = caller_module
    record.caller_function = builder.current_function
    record.callee_module = callee_module
    record.name = name
    record.instance = instance
    builder.inlined[builder.inlined_count] = record
    builder.inlined_count += 1usize
    ret ok
}

fn emit_inlined_call(c: *check.Checker, call: check.CallInfo, entry_index: usize, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    let entry = builder.inline_entries[entry_index]
    let oracle = entry.oracle
    // The body was lowered with another worker's checker (D326) when it was not this
    // one: the types its instructions carry are imported as they are copied.
    let foreign = entry.checker.fork_id != c.fork_id
    let callee = oracle.functions[entry.function_index]
    try record_inlined(builder, entry.module_index, entry.name, entry.instance)
    // The callee's body may itself hold copies (D212): every callee of those is a
    // body edge of this module too, or an edit to it would leave this copy stale.
    var nested_at = 0usize
    while nested_at < oracle.inlined_count {
        let nested = oracle.inlined[nested_at]
        if nested.caller_function == entry.function_index { try record_inlined(builder, nested.callee_module, nested.name, nested.instance) }
        nested_at += 1usize
    }
    var value_map: [128]usize = zero
    var block_map: [64]usize = zero
    if callee.value_count > value_map.len || callee.block_count > block_map.len { ret check.Capacity }
    var return_sites = 0usize
    var instruction_at = callee.first_instruction
    while instruction_at < callee.first_instruction + callee.instruction_count {
        if oracle.instructions[instruction_at].opcode == .Return { return_sites += 1usize }
        instruction_at += 1usize
    }
    var result_type: check.Type = zero
    var slot = 0usize
    var slot_size = 0usize
    if results.count == 1usize {
        let (returned, returned_error) = check.call_return(c, call, 0usize)
        if returned_error != ok { ret returned_error }
        result_type = returned
        if return_sites != 1usize {
            let (info, info_error) = layout.type_info(c, result_type)
            if info_error != ok { ret info_error }
            slot_size = info.size
            var slots = (info.size + 7usize) / 8usize
            if slots == 0usize { slots = 1usize }
            let (slot_instruction, slot_value, slot_error) = nir.emit(builder, .Stack, result_type, true, slots, token)
            if slot_error != ok { ret slot_error }
            slot = slot_value
        }
    }
    let caller_path = builder.current_path
    builder.current_path = callee.path
    let first_block = builder.block_count
    var block_at = 0usize
    while block_at < callee.block_count {
        block_map[block_at] = first_block + block_at
        block_at += 1usize
    }
    let continuation = first_block + callee.block_count
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }
    try nir.set_branch_targets(builder, entry_branch, first_block, 0usize)
    var single_result = 0usize
    block_at = 0usize
    while block_at < callee.block_count {
        let block = oracle.blocks[callee.first_block + block_at]
        let (block_index, block_error) = nir.begin_block(builder)
        if block_error != ok || block_index != block_map[block_at] { ret nir.InvalidControlFlow }
        instruction_at = block.first_instruction
        while instruction_at < block.first_instruction + block.instruction_count {
            let instruction = oracle.instructions[instruction_at]
            if instruction.opcode == .Parameter {
                if instruction.immediate >= argument_count { ret check.ArgumentCount }
                value_map[instruction.result] = arguments[instruction.immediate]
            } else {
                if instruction.opcode == .Return {
                    if instruction.operand_count == 1usize {
                        let returned = value_map[oracle.operands[instruction.first_operand]]
                        if return_sites == 1usize {
                            single_result = returned
                        } else {
                            let (store_instruction, store_ignored, store_error) = nir.emit_at(builder, .Store, result_type, false, slot_size, instruction.site)
                            if store_error != ok { ret store_error }
                            try nir.add_operand(builder, store_instruction, slot)
                            try nir.add_operand(builder, store_instruction, returned)
                        }
                    }
                    let (leave, leave_error) = emit_branch_at(builder, instruction.site)
                    if leave_error != ok { ret leave_error }
                    try nir.set_branch_targets(builder, leave, continuation, 0usize)
                } else {
                    var immediate = instruction.immediate
                    if instruction.opcode == .Call || instruction.opcode == .FunctionAddress {
                        let reference = oracle.function_refs[instruction.immediate]
                        var interned = 0usize
                        if reference.library.len != 0usize {
                            let (imported, import_error) = nir.intern_import(builder, reference.module_index, reference.name, reference.library, reference.symbol)
                            if import_error != ok { ret import_error }
                            interned = imported
                        } else {
                            let (plain, intern_error) = nir.intern_function(builder, reference.module_index, reference.name, reference.instance)
                            if intern_error != ok { ret intern_error }
                            interned = plain
                        }
                        immediate = interned
                    }
                    if instruction.opcode == .ConstString {
                        let (text_index, text_error) = nir.intern_string(builder, oracle.strings[instruction.immediate].spelling)
                        if text_error != ok { ret text_error }
                        immediate = text_index
                    }
                    if instruction.opcode == .Trap && instruction.immediate != 0usize {
                        let (text_index, text_error) = nir.intern_string(builder, oracle.strings[instruction.immediate - 1usize].spelling)
                        if text_error != ok { ret text_error }
                        immediate = text_index + 1usize
                    }
                    if instruction.opcode == .GlobalAddress {
                        if instruction.immediate >= builder.global_count || !check.same(builder.globals[instruction.immediate].name, oracle.globals[instruction.immediate].name) { ret check.Unsupported }
                    }
                    var copied_type = instruction.ty
                    if foreign {
                        let (imported, import_error) = import_type(c, entry.checker, instruction.ty)
                        if import_error != ok { ret import_error }
                        copied_type = imported
                    }
                    let was_nocheck = builder.nocheck
                    builder.nocheck = was_nocheck || instruction.nocheck
                    let (copied, result, copy_error) = nir.emit_at(builder, instruction.opcode, copied_type, instruction.has_result, immediate, instruction.site)
                    builder.nocheck = was_nocheck
                    if copy_error != ok { ret copy_error }
                    if instruction.path.len != 0usize { builder.instructions[copied].path = instruction.path }
                    var operand_at = 0usize
                    while operand_at < instruction.operand_count {
                        try nir.add_operand(builder, copied, value_map[oracle.operands[instruction.first_operand + operand_at]])
                        operand_at += 1usize
                    }
                    if instruction.opcode == .Branch || instruction.opcode == .BranchIf || instruction.opcode == .Switch {
                        var target2 = 0usize
                        if instruction.opcode == .BranchIf { target2 = block_map[instruction.target2 - callee.first_block] }
                        try nir.set_branch_targets(builder, copied, block_map[instruction.target - callee.first_block], target2)
                    }
                    if instruction.has_result { value_map[instruction.result] = result }
                }
            }
            instruction_at += 1usize
        }
        block_at += 1usize
    }
    builder.current_path = caller_path
    let (continuation_index, continuation_error) = nir.begin_block(builder)
    if continuation_error != ok || continuation_index != continuation { ret nir.InvalidControlFlow }
    if results.count == 1usize {
        if return_sites == 1usize {
            results.values[0usize] = single_result
        } else {
            let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, result_type, true, slot_size, token)
            if load_error != ok { ret load_error }
            try nir.add_operand(builder, load_instruction, slot)
            results.values[0usize] = loaded
        }
    }
    ret ok
}

fn emit_call_results(c: *check.Checker, call: check.CallInfo, callee: usize, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    if call.atomic_op != .None { ret emit_atomic(c, call, arguments, argument_count, builder, token, results) }
    if call.meta_access { ret emit_meta_access(c, call, arguments, argument_count, builder, token, results) }
    if call.meta_query != .None { ret emit_reflection(c, call, builder, token, results) }
    if call.function.intrinsic && check.same(call.function.name, "view") {
        ret emit_mem_view(c, call, arguments, argument_count, builder, token, results)
    }
    if call.protocol_builtin == .Cmp { ret emit_supplied_cmp(c, call, arguments, argument_count, builder, token, results) }
    if call.protocol_builtin == .Hash { ret emit_supplied_hash(c, call, arguments, argument_count, builder, token, results) }
    if call.protocol_builtin == .Eq { ret emit_supplied_eq(c, call, arguments, argument_count, builder, token, results) }
    results.call = call
    results.count = call.function.return_count
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    // Section 12's inlining: a callee the oracle holds -- forty NIR instructions or
    // fewer, one register result at most -- is copied in here instead of called (D207).
    if builder.has_oracle && !call.indirect && !call.mem_alloc && !call.function.intrinsic && !call.function.external && !call.function.generic && !return_layout.via_slot && results.count <= 1usize {
        var scalar_result = true
        if results.count == 1usize {
            let (returned, returned_error) = check.call_return(c, call, 0usize)
            if returned_error != ok { ret returned_error }
            scalar_result = !aggregate_value(c, returned)
        }
        if scalar_result {
            let (entry_index, inlinable) = find_inline_entry(builder, call.function.owner_module_index, call.function.name, call.function.instance_id)
            if inlinable { ret emit_inlined_call(c, call, entry_index, arguments, argument_count, builder, token, results) }
        }
    }
    var symbol = call.function.name
    var symbol_instance = call.function.instance_id
    if call.mem_alloc {
        // Section 11's debug fills (D217): the debug build's entry points fill what
        // they hand out with 0xCD and what a reset gives back with 0xDD.
        symbol = "neper_mem_alloc"
        if !builder.release { symbol = "neper_mem_alloc_fill" }
        symbol_instance = 0usize
    } else {
        if call.function.intrinsic {
            let (mapped_symbol, mapped_error) = intrinsic_symbol(symbol)
            if mapped_error != ok { ret mapped_error }
            symbol = mapped_symbol
            if !builder.release && check.same(symbol, "neper_mem_reset") { symbol = "neper_mem_reset_fill" }
            symbol_instance = 0usize
        }
    }
    var function_ref = 0usize
    if !call.indirect {
        // An `extern fn` bound by `@import` is called through the image's import
        // table, so the reference carries the library and the foreign name.
        if call.function.external && call.function.import_library.len != 0usize {
            let (imported, import_error) = nir.intern_import(builder, call.function.owner_module_index, symbol, call.function.import_library, call.function.import_symbol)
            if import_error != ok { ret import_error }
            function_ref = imported
        } else {
            let (interned, function_ref_error) = nir.intern_function(builder, call.function.owner_module_index, symbol, symbol_instance)
            if function_ref_error != ok { ret function_ref_error }
            function_ref = interned
        }
    }
    var slot = 0usize
    if return_layout.via_slot && results.count != 0usize {
        var slots = (return_layout.size + 7usize) / 8usize
        if slots == 0usize { slots = 1usize }
        let slot_type = check.make_type(.Other, "return-slot", call.function.module_index)
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, slot_type, true, slots, token)
        if stack_error != ok { ret stack_error }
        slot = stack
    }
    var allocation_size = 0usize
    var allocation_alignment = 0usize
    if call.mem_alloc {
        if !call.alloc_return.has_element || call.alloc_return.element >= c.type_count { ret check.InvalidType }
        let (element_info, element_info_error) = layout.type_info(c, c.types[call.alloc_return.element])
        if element_info_error != ok { ret element_info_error }
        let usize_type = check.make_type(.Integer, "usize", call.function.module_index)
        let (size_instruction, size_value, size_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.size, token)
        if size_error != ok { ret size_error }
        let (alignment_instruction, alignment_value, alignment_error) = nir.emit(builder, .ConstInteger, usize_type, true, element_info.alignment, token)
        if alignment_error != ok { ret alignment_error }
        allocation_size = size_value
        allocation_alignment = alignment_value
    }
    var call_type: check.Type = zero
    var call_has_result = false
    if !return_layout.via_slot && results.count != 0usize {
        call_has_result = true
        if results.count == 1usize {
            let (single_type, single_type_error) = check.call_return(c, call, 0usize)
            if single_type_error != ok { ret single_type_error }
            call_type = single_type
        } else {
            call_type = check.make_type(.Other, "return-values", call.function.module_index)
        }
    }
    var call_opcode: nir.Opcode = .Call
    if call.indirect { call_opcode = .IndirectCall }
    let (instruction, call_result, emit_error) = nir.emit(builder, call_opcode, call_type, call_has_result, function_ref, token)
    if emit_error != ok { ret emit_error }
    if call.indirect {
        let callee_operand_error = nir.add_operand(builder, instruction, callee)
        if callee_operand_error != ok { ret callee_operand_error }
    }
    if return_layout.via_slot && results.count != 0usize {
        let slot_operand_error = nir.add_operand(builder, instruction, slot)
        if slot_operand_error != ok { ret slot_operand_error }
    }
    var argument_at = 0usize
    while argument_at < argument_count {
        let argument_operand_error = nir.add_operand(builder, instruction, arguments[argument_at])
        if argument_operand_error != ok { ret argument_operand_error }
        argument_at += 1usize
    }
    if call.mem_alloc {
        let size_operand_error = nir.add_operand(builder, instruction, allocation_size)
        if size_operand_error != ok { ret size_operand_error }
        let alignment_operand_error = nir.add_operand(builder, instruction, allocation_alignment)
        if alignment_operand_error != ok { ret alignment_operand_error }
    }
    if results.count == 0usize { ret ok }
    if !return_layout.via_slot {
        if results.count == 1usize {
            results.values[0usize] = call_result
            ret ok
        }
        var result_at = 0usize
        while result_at < results.count {
            let (result_type, result_type_error) = check.call_return(c, call, result_at)
            if result_type_error != ok { ret result_type_error }
            let (extract_instruction, extracted, extract_error) = nir.emit(builder, .Extract, result_type, true, result_at, token)
            if extract_error != ok { ret extract_error }
            let extract_operand_error = nir.add_operand(builder, extract_instruction, call_result)
            if extract_operand_error != ok { ret extract_operand_error }
            results.values[result_at] = extracted
            result_at += 1usize
        }
        ret ok
    }
    var result_at = 0usize
    while result_at < results.count {
        let (result_type, result_type_error) = check.call_return(c, call, result_at)
        if result_type_error != ok { ret result_type_error }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, result_type, true, return_layout.offsets[result_at], token)
        if address_error != ok { ret address_error }
        let address_operand_error = nir.add_operand(builder, address_instruction, slot)
        if address_operand_error != ok { ret address_operand_error }
        if aggregate_value(c, result_type) {
            results.values[result_at] = address
            results.addresses[result_at] = true
        } else {
            let (info, info_error) = layout.type_info(c, result_type)
            if info_error != ok { ret info_error }
            let (load_instruction, value, load_error) = nir.emit(builder, .Load, result_type, true, info.size, token)
            if load_error != ok { ret load_error }
            let load_operand_error = nir.add_operand(builder, load_instruction, address)
            if load_operand_error != ok { ret load_operand_error }
            results.values[result_at] = value
        }
        result_at += 1usize
    }
    ret ok
}

fn lower_call_arguments(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, captured: bool, call_out: *check.CallInfo, callee_out: *usize, arguments: []usize, argument_count: *usize) -> err {
    let (call, call_error) = check.check_call(c, g, tree, module_index, node)
    if call_error != ok { ret call_error }
    *call_out = call
    if call.is_unreachable {
        *callee_out = 0usize
        *argument_count = 0usize
        ret ok
    }
    if call.is_cast || call.function.generic { ret check.Unsupported }
    *callee_out = 0usize
    *argument_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var child_position = 0usize
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_position == 0usize && call.indirect {
                let (callee_value, callee_type, callee_error) = lower_expression(c, g, tree, module_index, parse.child_index_at(tree, at), call.indirect_type, builder, bindings, binding_count)
                if callee_error != ok { ret callee_error }
                *callee_out = callee_value
            }
            if child_position > 0usize {
                if *argument_count == arguments.len { ret check.ArgumentCount }
                var parameter_type = check.invalid_type()
                if *argument_count >= call.function.parameter_count {
                    // Past the declared parameters of a C variadic the argument's own
                    // type is the type it crosses as; the checker has already refused
                    // one that does not.
                    if !call.function.variadic { ret check.ArgumentCount }
                } else {
                    let (declared_type, parameter_type_error) = call_parameter_type(c, call, *argument_count)
                    if parameter_type_error != ok { ret parameter_type_error }
                    parameter_type = declared_type
                }
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, parse.child_index_at(tree, at), parameter_type, builder, bindings, binding_count)
                if value_error != ok { ret value_error }
                var argument = value
                if captured && aggregate_value(c, parameter_type) {
                    let (info, info_error) = layout.type_info(c, parameter_type)
                    if info_error != ok { ret info_error }
                    var slots = (info.size + 7usize) / 8usize
                    if slots == 0usize { slots = 1usize }
                    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, parameter_type, true, slots, c.tokens[usize(node.token_start)])
                    if stack_error != ok { ret stack_error }
                    let (copy_instruction, ignored, copy_error) = nir.emit(builder, .Copy, parameter_type, false, info.size, c.tokens[usize(node.token_start)])
                    if copy_error != ok { ret copy_error }
                    try nir.add_operand(builder, copy_instruction, stack)
                    try nir.add_operand(builder, copy_instruction, value)
                    argument = stack
                }
                arguments[*argument_count] = argument
                *argument_count += 1usize
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if *argument_count < call.function.parameter_count { ret check.ArgumentCount }
    if !call.function.variadic && *argument_count != call.function.parameter_count { ret check.ArgumentCount }
    ret ok
}

fn lower_call_results(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, results: *CallResults) -> err {
    var call: check.CallInfo = zero
    // A format string may carry 32 verbs, so a call may carry 32 arguments plus the
    // arena: the checker already allows it and this is what lowering has to match.
    var arguments: [33]usize = zero
    var argument_count = 0usize
    var callee = 0usize
    let arguments_error = lower_call_arguments(c, g, tree, module_index, node, builder, bindings, binding_count, false, &call, &callee, arguments[..], &argument_count)
    if arguments_error != ok { ret arguments_error }
    if call.is_unreachable {
        // A `.Trap` whose immediate is the message's string constant plus one, or zero
        // for none; the back end builds the record from it (D194). It terminates the
        // block, so what follows in the statement list is dead and not lowered.
        var message = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        var child_position = 0usize
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if child_position == 1usize {
                    let message_node = tree.nodes[parse.child_index_at(tree, at)]
                    let literal_token = c.tokens[usize(message_node.token_start)]
                    let (interned, intern_error) = nir.intern_string(builder, g.modules[module_index].text[literal_token.start..literal_token.end])
                    if intern_error != ok { ret intern_error }
                    message = interned + 1usize
                }
                child_position += 1usize
            }
            at += 1usize
        }
        let (trap_instruction, ignored, trap_error) = nir.emit(builder, .Trap, zero, false, message, c.tokens[usize(node.token_start)])
        if trap_error != ok { ret trap_error }
        results.count = 0usize
        ret ok
    }
    let align_error = emit_align_check(c, g, call, arguments[..], argument_count, builder, c.tokens[usize(node.token_start)])
    if align_error != ok { ret align_error }
    ret emit_call_results(c, call, callee, arguments[..], argument_count, builder, c.tokens[usize(node.token_start)], results)
}

fn lower_call(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (check.CallInfo, usize, err) {
    var empty: check.CallInfo = zero
    var results: CallResults = zero
    let call_error = lower_call_results(c, g, tree, module_index, node, builder, bindings, binding_count, &results)
    if call_error != ok { ret (empty, 0usize, call_error) }
    if results.count != 1usize { ret (results.call, 0usize, check.ArgumentCount) }
    ret (results.call, results.values[0usize], ok)
}

fn binary_opcode(kind: lex.Kind) -> nir.Opcode {
    if kind == .PunctPlus { ret .Add }
    if kind == .PunctMinus { ret .Subtract }
    if kind == .PunctStar { ret .Multiply }
    if kind == .PunctSlash { ret .Divide }
    if kind == .PunctPercent { ret .Remainder }
    if kind == .PunctAddWrap { ret .AddWrap }
    if kind == .PunctSubWrap { ret .SubtractWrap }
    if kind == .PunctMulWrap { ret .MultiplyWrap }
    if kind == .PunctShiftLeft { ret .ShiftLeft }
    if kind == .PunctShiftRight { ret .ShiftRight }
    if kind == .PunctAmp { ret .BitAnd }
    if kind == .PunctCaret { ret .BitXor }
    if kind == .PunctPipe { ret .BitOr }
    if kind == .PunctEqEq { ret .Equal }
    if kind == .PunctBangEq { ret .NotEqual }
    if kind == .PunctLt { ret .Less }
    if kind == .PunctLtEq { ret .LessEqual }
    if kind == .PunctGt { ret .Greater }
    if kind == .PunctGtEq { ret .GreaterEqual }
    ret .Invalid
}

fn compound_opcode(kind: lex.Kind) -> nir.Opcode {
    if kind == .PunctAddAssign { ret .Add }
    if kind == .PunctSubAssign { ret .Subtract }
    if kind == .PunctMulAssign { ret .Multiply }
    if kind == .PunctDivAssign { ret .Divide }
    if kind == .PunctRemAssign { ret .Remainder }
    if kind == .PunctAddWrapAssign { ret .AddWrap }
    if kind == .PunctSubWrapAssign { ret .SubtractWrap }
    if kind == .PunctMulWrapAssign { ret .MultiplyWrap }
    if kind == .PunctShiftLeftAssign { ret .ShiftLeft }
    if kind == .PunctShiftRightAssign { ret .ShiftRight }
    if kind == .PunctBitAndAssign { ret .BitAnd }
    if kind == .PunctBitXorAssign { ret .BitXor }
    if kind == .PunctBitOrAssign { ret .BitOr }
    ret .Invalid
}

fn aggregate_value(c: *check.Checker, ty: check.Type) -> bool {
    if ty.kind == .Array || ty.kind == .Slice || ty.kind == .String { ret true }
    let (index, found) = layout.aggregate_index(c, ty)
    if !found { ret false }
    ret c.aggregates[index].kind != .Enum && ty.kind != .Tag
}

fn lower_slice(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    var bracket: check.BracketInfo = zero
    let bracket_error = check.read_bracket(c, tree, node, &bracket)
    if bracket_error != ok || !bracket.range { ret (0usize, zero, check.Unsupported) }
    let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, bracket.base, check.invalid_type())
    if base_type_error != ok { ret (0usize, base_type, base_type_error) }
    if base_type.kind != .Array && base_type.kind != .Slice && base_type.kind != .String { ret (0usize, base_type, check.Unsupported) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (element_type, element_type_error) = check.index_element_type(c, base_type, module_index)
    if element_type_error != ok { ret (0usize, result_type, element_type_error) }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, result_type, element_info_error) }
    let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, bracket.base, base_type, builder, bindings, binding_count)
    if base_error != ok { ret (0usize, lowered_base_type, base_error) }
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let length_type = check.make_type(.Integer, "usize", module_index)
    var data = base
    var length = 0usize
    if base_type.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, length_type, true, base_type.array_length, c.tokens[usize(node.token_start)])
        if length_error != ok { ret (0usize, result_type, length_error) }
        length = length_value
    } else {
        let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, c.tokens[usize(node.token_start)])
        if data_address_error != ok { ret (0usize, result_type, data_address_error) }
        let data_address_operand_error = nir.add_operand(builder, data_address_instruction, base)
        if data_address_operand_error != ok { ret (0usize, result_type, data_address_operand_error) }
        let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, c.tokens[usize(node.token_start)])
        if data_load_error != ok { ret (0usize, result_type, data_load_error) }
        let data_load_operand_error = nir.add_operand(builder, data_load_instruction, data_address)
        if data_load_operand_error != ok { ret (0usize, result_type, data_load_operand_error) }
        data = data_value
        let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, length_type, true, 8usize, c.tokens[usize(node.token_start)])
        if length_address_error != ok { ret (0usize, result_type, length_address_error) }
        let length_address_operand_error = nir.add_operand(builder, length_address_instruction, base)
        if length_address_operand_error != ok { ret (0usize, result_type, length_address_operand_error) }
        let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, length_type, true, 8usize, c.tokens[usize(node.token_start)])
        if length_load_error != ok { ret (0usize, result_type, length_load_error) }
        let length_load_operand_error = nir.add_operand(builder, length_load_instruction, length_address)
        if length_load_operand_error != ok { ret (0usize, result_type, length_load_operand_error) }
        length = length_value
    }
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, length_type, true, 0usize, c.tokens[usize(node.token_start)])
    if zero_error != ok { ret (0usize, result_type, zero_error) }
    var lower = zero_value
    var upper = length
    if usize(bracket.child_count) == 3usize {
        let (lower_value, lower_type, lower_error) = lower_expression(c, g, tree, module_index, bracket.first, length_type, builder, bindings, binding_count)
        if lower_error != ok { ret (0usize, result_type, lower_error) }
        lower = lower_value
        let (upper_value, upper_type, upper_error) = lower_expression(c, g, tree, module_index, bracket.second, length_type, builder, bindings, binding_count)
        if upper_error != ok { ret (0usize, result_type, upper_error) }
        upper = upper_value
    } else {
        if usize(bracket.child_count) == 2usize {
            var range_at = usize(tree.nodes[bracket.base].token_end)
            while range_at < usize(node.token_end) && c.tokens[range_at].kind != .PunctRange { range_at += 1usize }
            if range_at >= usize(node.token_end) { ret (0usize, result_type, parse.InvalidSyntax) }
            let (bound, bound_type, bound_error) = lower_expression(c, g, tree, module_index, bracket.first, length_type, builder, bindings, binding_count)
            if bound_error != ok { ret (0usize, result_type, bound_error) }
            if usize(tree.nodes[bracket.first].token_start) < range_at { lower = bound } else { upper = bound }
        }
    }
    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, 2usize, c.tokens[usize(node.token_start)])
    if stack_error != ok { ret (0usize, result_type, stack_error) }
    let (slice_instruction, slice_ignored, slice_error) = nir.emit(builder, .Slice, result_type, false, element_info.size, c.tokens[usize(node.token_start)])
    if slice_error != ok { ret (0usize, result_type, slice_error) }
    let destination_error = nir.add_operand(builder, slice_instruction, stack)
    if destination_error != ok { ret (0usize, result_type, destination_error) }
    let data_error = nir.add_operand(builder, slice_instruction, data)
    if data_error != ok { ret (0usize, result_type, data_error) }
    let source_length_error = nir.add_operand(builder, slice_instruction, length)
    if source_length_error != ok { ret (0usize, result_type, source_length_error) }
    let lower_error = nir.add_operand(builder, slice_instruction, lower)
    if lower_error != ok { ret (0usize, result_type, lower_error) }
    let upper_error = nir.add_operand(builder, slice_instruction, upper)
    if upper_error != ok { ret (0usize, result_type, upper_error) }
    ret (stack, result_type, ok)
}

fn lower_index_address(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    var children: [2]usize = zero
    var child_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == children.len { ret (0usize, zero, check.Unsupported) }
            children[child_count] = parse.child_index_at(tree, at)
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count != 2usize { ret (0usize, zero, parse.InvalidSyntax) }
    let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, children[0usize], check.invalid_type())
    if base_type_error != ok { ret (0usize, base_type, base_type_error) }
    let (element_type, element_type_error) = check.index_element_type(c, base_type, module_index)
    if element_type_error != ok { ret (0usize, element_type, element_type_error) }
    let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, children[0usize], base_type, builder, bindings, binding_count)
    if base_error != ok { ret (0usize, lowered_base_type, base_error) }
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let (index, index_type, index_error) = lower_expression(c, g, tree, module_index, children[1usize], usize_type, builder, bindings, binding_count)
    if index_error != ok { ret (0usize, index_type, index_error) }
    var data = base
    var length = 0usize
    let (vector_lanes, is_vector) = check.vector_lanes(c, base_type)
    if base_type.kind == .Array || is_vector {
        var count = base_type.array_length
        if is_vector { count = vector_lanes.array_length }
        let (length_instruction, length_result, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, count, c.tokens[usize(node.token_start)])
        if length_error != ok { ret (0usize, element_type, length_error) }
        length = length_result
    } else {
        if base_type.kind != .Slice && base_type.kind != .String { ret (0usize, element_type, check.Unsupported) }
        let pointer_type = check.make_type(.Pointer, "", module_index)
        let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, c.tokens[usize(node.token_start)])
        if data_address_error != ok { ret (0usize, element_type, data_address_error) }
        let data_address_operand_error = nir.add_operand(builder, data_address_instruction, base)
        if data_address_operand_error != ok { ret (0usize, element_type, data_address_operand_error) }
        let (data_load, data_result, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, c.tokens[usize(node.token_start)])
        if data_load_error != ok { ret (0usize, element_type, data_load_error) }
        let data_load_operand_error = nir.add_operand(builder, data_load, data_address)
        if data_load_operand_error != ok { ret (0usize, element_type, data_load_operand_error) }
        data = data_result
        let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, c.tokens[usize(node.token_start)])
        if length_address_error != ok { ret (0usize, element_type, length_address_error) }
        let length_address_operand_error = nir.add_operand(builder, length_address_instruction, base)
        if length_address_operand_error != ok { ret (0usize, element_type, length_address_operand_error) }
        let (length_load, length_result, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, c.tokens[usize(node.token_start)])
        if length_load_error != ok { ret (0usize, element_type, length_load_error) }
        let length_load_operand_error = nir.add_operand(builder, length_load, length_address)
        if length_load_operand_error != ok { ret (0usize, element_type, length_load_operand_error) }
        length = length_result
    }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, element_type, element_info_error) }
    let (address_instruction, address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, element_info.size, c.tokens[usize(node.token_start)])
    if address_error != ok { ret (0usize, element_type, address_error) }
    let data_operand_error = nir.add_operand(builder, address_instruction, data)
    if data_operand_error != ok { ret (0usize, element_type, data_operand_error) }
    let index_operand_error = nir.add_operand(builder, address_instruction, index)
    if index_operand_error != ok { ret (0usize, element_type, index_operand_error) }
    let length_operand_error = nir.add_operand(builder, address_instruction, length)
    if length_operand_error != ok { ret (0usize, element_type, length_operand_error) }
    ret (address, element_type, ok)
}

fn lower_index(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (address, element_type, address_error) = lower_index_address(c, g, tree, module_index, node_index, builder, bindings, binding_count)
    if address_error != ok { ret (0usize, element_type, address_error) }
    if aggregate_value(c, element_type) { ret (address, element_type, ok) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret (0usize, result_type, element_info_error) }
    let (load_instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, element_info.size, c.tokens[usize(node.token_start)])
    if load_error != ok { ret (0usize, result_type, load_error) }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret (0usize, result_type, load_operand_error) }
    ret (result, result_type, ok)
}

fn lower_place(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (0usize, zero, check.Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (binding, found) = find_binding(bindings, binding_count, name)
        if found {
            if !binding.address { ret (0usize, zero, check.Unsupported) }
            ret (binding.value, binding.ty, ok)
        }
        // Assigning to a module-scope `var` is a store to the same address reading it loads
        // from, which is the whole of what makes it one variable rather than a value per use.
        let (global_index, has_global) = check.find_global(c, module_index, name)
        if has_global {
            let (address, address_type, address_error) = global_address(c, global_index, builder, token)
            if address_error != ok { ret (0usize, address_type, address_error) }
            ret (address, c.globals[global_index].ty, ok)
        }
        ret (0usize, zero, check.Unsupported)
    }
    if node.kind == .BracketPostfix && !check.contains_token(c, usize(node.token_start), usize(node.token_end), .PunctRange) {
        let (address, ty, address_error) = lower_index_address(c, g, tree, module_index, node_index, builder, bindings, binding_count)
        ret (address, ty, address_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, qualified_name, qualified) = check.qualified_member(c, g, tree, module_index, node)
        if qualified { ret (0usize, zero, check.Unsupported) }
        let (base_index, has_base) = check.first_node_child(tree, node)
        if !has_base { ret (0usize, zero, parse.InvalidSyntax) }
        let (field_name, has_field) = check.field_expression_name(c, g.modules[module_index].text, tree, node)
        if !has_field { ret (0usize, zero, parse.InvalidSyntax) }
        let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, base_index, check.invalid_type())
        if base_type_error != ok { ret (0usize, base_type, base_type_error) }
        let (field, field_error) = layout.field(c, base_type, field_name)
        if field_error != ok { ret (0usize, zero, field_error) }
        let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
        if base_error != ok { ret (0usize, lowered_base_type, base_error) }
        let null_error = emit_null_check(c, base, base_type, builder, c.tokens[usize(node.token_start)])
        if null_error != ok { ret (0usize, field.ty, null_error) }
        let tag_error = emit_tag_check(c, base, base_type, field_name, builder, c.tokens[usize(node.token_start)])
        if tag_error != ok { ret (0usize, field.ty, tag_error) }
        let (instruction, address, emit_error) = nir.emit(builder, .FieldAddress, field.ty, true, field.offset, c.tokens[usize(node.token_start)])
        if emit_error != ok { ret (0usize, field.ty, emit_error) }
        let operand_error = nir.add_operand(builder, instruction, base)
        if operand_error != ok { ret (0usize, field.ty, operand_error) }
        ret (address, field.ty, ok)
    }
    if node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctStar {
        let (child_index, found_child) = check.first_node_child(tree, node)
        if !found_child { ret (0usize, zero, parse.InvalidSyntax) }
        let (pointer_type, pointer_type_error) = check.check_expr(c, g, tree, module_index, child_index, check.invalid_type())
        if pointer_type_error != ok || pointer_type.kind != .Pointer || !pointer_type.has_element || pointer_type.element >= c.type_count { ret (0usize, pointer_type, check.InvalidType) }
        let (pointer, lowered_pointer_type, pointer_error) = lower_expression(c, g, tree, module_index, child_index, pointer_type, builder, bindings, binding_count)
        if pointer_error != ok { ret (0usize, lowered_pointer_type, pointer_error) }
        let null_error = emit_null_check(c, pointer, pointer_type, builder, c.tokens[usize(node.token_start)])
        if null_error != ok { ret (0usize, lowered_pointer_type, null_error) }
        ret (pointer, c.types[pointer_type.element], ok)
    }
    ret (0usize, zero, check.Unsupported)
}

fn lower_member(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (aggregate_index, found_aggregate) = layout.aggregate_index(c, result_type)
    if !found_aggregate { ret (0usize, result_type, check.Unsupported) }
    let aggregate = c.aggregates[aggregate_index]
    var member_name = ""
    var token_at = usize(node.token_start)
    while token_at < usize(node.token_end) {
        let token = c.tokens[token_at]
        if token.kind == .Identifier { member_name = g.modules[module_index].text[token.start..token.end] }
        token_at += 1usize
    }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index < c.aggregate_field_count {
            let member = c.aggregate_fields[field_index]
            if check.same(member.name, member_name) {
                if aggregate.kind == .TaggedUnion && result_type.kind == .Named {
                    let (info, info_error) = layout.type_info(c, result_type)
                    if info_error != ok { ret (0usize, result_type, info_error) }
                    var slots = (info.size + 7usize) / 8usize
                    if slots == 0usize { slots = 1usize }
                    let token = c.tokens[usize(node.token_start)]
                    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, slots, token)
                    if stack_error != ok { ret (0usize, result_type, stack_error) }
                    let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, result_type, false, info.size, token)
                    if zero_error != ok { ret (0usize, result_type, zero_error) }
                    let zero_operand_error = nir.add_operand(builder, zero_instruction, stack)
                    if zero_operand_error != ok { ret (0usize, result_type, zero_operand_error) }
                    let tag_error = store_tag(c, aggregate, field_index, stack, token, builder)
                    ret (stack, result_type, tag_error)
                }
                let (member_bits, member_bits_error) = check.enum_member_bits(aggregate.backing_type, member.enum_value, member.enum_negative)
                if member_bits_error != ok { ret (0usize, result_type, member_bits_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, member_bits, c.tokens[usize(node.token_start)])
                ret (result, result_type, emit_error)
            }
        }
        field_at += 1usize
    }
    ret (0usize, result_type, check.InvalidType)
}

fn lower_unary(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (child_index, found_child) = check.first_node_child(tree, node)
    if !found_child { ret (0usize, zero, parse.InvalidSyntax) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let operator = c.tokens[usize(node.token_start)].kind
    if operator == .PunctAmp {
        let (address, place_type, place_error) = lower_place(c, g, tree, module_index, child_index, builder, bindings, binding_count)
        if place_error != ok { ret (0usize, result_type, place_error) }
        ret (address, result_type, ok)
    }
    var operand_expected = result_type
    if operator == .PunctBang { operand_expected = check.make_type(.Bool, "bool", module_index) }
    if operator == .PunctStar {
        let (pointer_type, pointer_type_error) = check.check_expr(c, g, tree, module_index, child_index, check.invalid_type())
        if pointer_type_error != ok { ret (0usize, result_type, pointer_type_error) }
        operand_expected = pointer_type
    }
    let (operand, operand_type, operand_error) = lower_expression(c, g, tree, module_index, child_index, operand_expected, builder, bindings, binding_count)
    if operand_error != ok { ret (0usize, operand_type, operand_error) }
    if operator == .PunctStar {
        let null_error = emit_null_check(c, operand, operand_type, builder, c.tokens[usize(node.token_start)])
        if null_error != ok { ret (0usize, result_type, null_error) }
        if aggregate_value(c, result_type) { ret (operand, result_type, ok) }
        let (info, info_error) = layout.type_info(c, result_type)
        if info_error != ok { ret (0usize, result_type, info_error) }
        let (instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, info.size, c.tokens[usize(node.token_start)])
        if load_error != ok { ret (0usize, result_type, load_error) }
        let add_error = nir.add_operand(builder, instruction, operand)
        if add_error != ok { ret (0usize, result_type, add_error) }
        ret (result, result_type, ok)
    }
    if operator == .PunctBang {
        let (false_instruction, false_value, false_error) = nir.emit(builder, .ConstBool, operand_expected, true, 0usize, c.tokens[usize(node.token_start)])
        if false_error != ok { ret (0usize, result_type, false_error) }
        let (instruction, result, emit_error) = nir.emit(builder, .Equal, result_type, true, 0usize, c.tokens[usize(node.token_start)])
        if emit_error != ok { ret (0usize, result_type, emit_error) }
        let operand_add_error = nir.add_operand(builder, instruction, operand)
        if operand_add_error != ok { ret (0usize, result_type, operand_add_error) }
        let false_add_error = nir.add_operand(builder, instruction, false_value)
        if false_add_error != ok { ret (0usize, result_type, false_add_error) }
        ret (result, result_type, ok)
    }
    var opcode: nir.Opcode = .Invalid
    if operator == .PunctMinus { opcode = .Negate }
    if operator == .PunctTilde { opcode = .BitNot }
    if opcode == .Invalid { ret (0usize, zero, check.Unsupported) }
    if operator == .PunctTilde && check.is_vector_type(c, result_type) {
        let (vector, vector_error) = lower_vector_not(c, node, operand, result_type, builder)
        ret (vector, result_type, vector_error)
    }
    let (instruction, result, emit_error) = nir.emit(builder, opcode, result_type, true, 0usize, c.tokens[usize(node.token_start)])
    if emit_error != ok { ret (0usize, result_type, emit_error) }
    let add_error = nir.add_operand(builder, instruction, operand)
    if add_error != ok { ret (0usize, result_type, add_error) }
    ret (result, result_type, ok)
}

fn store_tag(c: *check.Checker, aggregate: check.Aggregate, field_index: usize, destination: usize, token: lex.Token, builder: *nir.Builder) -> err {
    if field_index >= c.aggregate_field_count { ret check.InvalidType }
    let field = c.aggregate_fields[field_index]
    let (tag_bits, tag_bits_error) = check.enum_member_bits(aggregate.backing_type, field.enum_value, field.enum_negative)
    if tag_bits_error != ok { ret tag_bits_error }
    let (tag_info, tag_info_error) = layout.type_info(c, aggregate.backing_type)
    if tag_info_error != ok { ret tag_info_error }
    let (constant_instruction, tag_value, constant_error) = nir.emit(builder, .ConstInteger, aggregate.backing_type, true, tag_bits, token)
    if constant_error != ok { ret constant_error }
    let (address_instruction, tag_address, address_error) = nir.emit(builder, .FieldAddress, aggregate.backing_type, true, 0usize, token)
    if address_error != ok { ret address_error }
    try nir.add_operand(builder, address_instruction, destination)
    let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, aggregate.backing_type, false, tag_info.size, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, tag_address)
    ret nir.add_operand(builder, store_instruction, tag_value)
}

fn lower_aggregate_literal(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let (info, info_error) = layout.type_info(c, result_type)
    if info_error != ok { ret (0usize, result_type, info_error) }
    var slots = (info.size + 7usize) / 8usize
    if slots == 0usize { slots = 1usize }
    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, result_type, true, slots, c.tokens[usize(node.token_start)])
    if stack_error != ok { ret (0usize, result_type, stack_error) }
    let (aggregate_index, has_aggregate) = layout.aggregate_index(c, result_type)
    var tagged = false
    var aggregate: check.Aggregate = zero
    if has_aggregate {
        aggregate = c.aggregates[aggregate_index]
        tagged = aggregate.kind == .TaggedUnion
    }
    if tagged {
        let (zero_instruction, ignored, zero_error) = nir.emit(builder, .Zero, result_type, false, info.size, c.tokens[usize(node.token_start)])
        if zero_error != ok { ret (0usize, result_type, zero_error) }
        let zero_operand_error = nir.add_operand(builder, zero_instruction, stack)
        if zero_operand_error != ok { ret (0usize, result_type, zero_operand_error) }
    }
    var array_element: check.Type = zero
    var array_info: layout.Info = zero
    var positional = result_type.kind == .Array
    var positional_count = result_type.array_length
    if result_type.kind == .Array {
        if !result_type.has_element || result_type.element >= c.type_count { ret (0usize, result_type, check.InvalidType) }
        array_element = c.types[result_type.element]
    }
    // A vector literal is its lanes in order, the array it holds (D159).
    let (vector_lanes, is_vector) = check.vector_lanes(c, result_type)
    if is_vector {
        let (lane, has_lane) = check.vector_lane_type(c, result_type)
        if !has_lane { ret (0usize, result_type, check.InvalidType) }
        array_element = lane
        positional = true
        positional_count = vector_lanes.array_length
    }
    if positional {
        let (element_info, element_info_error) = layout.type_info(c, array_element)
        if element_info_error != ok { ret (0usize, result_type, element_info_error) }
        array_info = element_info
    }
    var item_at = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                var item_type: check.Type = zero
                var item_offset = 0usize
                if positional {
                    if item_at >= positional_count { ret (0usize, result_type, check.ArgumentCount) }
                    item_type = array_element
                    item_offset = item_at * array_info.size
                } else {
                    let (name, has_name) = check.literal_item_name(c, g.modules[module_index].text, item)
                    if !has_name { ret (0usize, result_type, check.Unsupported) }
                    let (field, field_error) = layout.field(c, result_type, name)
                    if field_error != ok { ret (0usize, result_type, field_error) }
                    item_type = field.ty
                    item_offset = field.offset
                    if tagged {
                        let (field_index, found_field) = check.aggregate_field_for_name(c, aggregate, name)
                        if !found_field { ret (0usize, result_type, check.InvalidType) }
                        let tag_error = store_tag(c, aggregate, field_index, stack, c.tokens[usize(item.token_start)], builder)
                        if tag_error != ok { ret (0usize, result_type, tag_error) }
                    }
                }
                let (expression_index, has_expression) = check.first_node_child(tree, item)
                if !has_expression { ret (0usize, result_type, check.Unsupported) }
                let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, expression_index, item_type, builder, bindings, binding_count)
                if value_error != ok { ret (0usize, value_type, value_error) }
                let (item_info, item_info_error) = layout.type_info(c, item_type)
                if item_info_error != ok { ret (0usize, result_type, item_info_error) }
                let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, item_type, true, item_offset, c.tokens[usize(item.token_start)])
                if address_error != ok { ret (0usize, result_type, address_error) }
                let address_operand_error = nir.add_operand(builder, address_instruction, stack)
                if address_operand_error != ok { ret (0usize, result_type, address_operand_error) }
                if aggregate_value(c, item_type) {
                    let (copy_instruction, copy_ignored, copy_error) = nir.emit(builder, .Copy, item_type, false, item_info.size, c.tokens[usize(item.token_start)])
                    if copy_error != ok { ret (0usize, result_type, copy_error) }
                    let copy_address_error = nir.add_operand(builder, copy_instruction, address)
                    if copy_address_error != ok { ret (0usize, result_type, copy_address_error) }
                    let copy_value_error = nir.add_operand(builder, copy_instruction, value)
                    if copy_value_error != ok { ret (0usize, result_type, copy_value_error) }
                } else {
                    let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, item_type, false, item_info.size, c.tokens[usize(item.token_start)])
                    if store_error != ok { ret (0usize, result_type, store_error) }
                    let store_address_error = nir.add_operand(builder, store_instruction, address)
                    if store_address_error != ok { ret (0usize, result_type, store_address_error) }
                    let store_value_error = nir.add_operand(builder, store_instruction, value)
                    if store_value_error != ok { ret (0usize, result_type, store_value_error) }
                }
                item_at += 1usize
            }
        }
        at += 1usize
    }
    ret (stack, result_type, ok)
}

fn lower_expression(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    c.failure_module = module_index
    c.failure_token = c.tokens[usize(node.token_start)]
    c.failure_has_token = true
    if node.kind == .LiteralExpr {
        let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if type_error != ok { ret (0usize, result_type, type_error) }
        let (value, value_error) = literal(c, g.modules[module_index].text, node, result_type, builder)
        ret (value, result_type, value_error)
    }
    if node.kind == .GroupExpr {
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let (group_value, group_type, group_error) = lower_expression(c, g, tree, module_index, parse.child_index_at(tree, at), expected, builder, bindings, binding_count)
                ret (group_value, group_type, group_error)
            }
            at += 1usize
        }
        ret (0usize, zero, parse.InvalidSyntax)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (0usize, zero, check.Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (binding, found) = find_binding(bindings, binding_count, name)
        if !found {
            let (parameter_index, has_parameter) = check.active_comptime_parameter(c, name)
            if has_parameter {
                let (argument, has_argument) = check.active_argument(c, parameter_index)
                if has_argument && argument.kind == .Str && !argument.symbolic {
                    let (text_value, text_type, text_error) = lower_comptime_text(c, g, tree, module_index, node_index, expected, argument.text, token, builder)
                    ret (text_value, text_type, text_error)
                }
                if has_argument && argument.kind == .Array {
                    let (array_value, array_error) = lower_comptime_array(c, argument, token, builder)
                    ret (array_value, argument.ty, array_error)
                }
                if !has_argument || argument.kind != .Integer || argument.symbolic { ret (0usize, zero, check.InvalidConstant) }
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, argument.value, token)
                ret (result, result_type, emit_error)
            }
            let (constant_index, has_constant) = check.find_constant(c, module_index, name)
            if has_constant {
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (constant, constant_error) = lower_constant(c, constant_index, result_type, token, builder)
                ret (constant, result_type, constant_error)
            }
            // A module-scope `var` is storage, so reading it is a load -- the one difference from
            // a local being where the address comes from.
            let (global_index, has_global) = check.find_global(c, module_index, name)
            if has_global {
                let (address, address_type, address_error) = global_address(c, global_index, builder, token)
                if address_error != ok { ret (0usize, address_type, address_error) }
                let value_type = c.globals[global_index].ty
                // The same shape a binding with an address has: an aggregate *is* its address,
                // and only something that fits a register is loaded -- at its own width, which
                // the load carries as its immediate.
                if aggregate_value(c, value_type) { ret (address, value_type, ok) }
                let (info, info_error) = layout.type_info(c, value_type)
                if info_error != ok { ret (0usize, value_type, info_error) }
                let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, value_type, true, info.size, token)
                if load_error != ok { ret (0usize, value_type, load_error) }
                let operand_error = nir.add_operand(builder, load_instruction, address)
                if operand_error != ok { ret (0usize, value_type, operand_error) }
                ret (loaded, value_type, ok)
            }
            let (symbol_index, has_symbol) = resolve.find(c.resolver, module_index, name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, module_index, name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", module_index)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[module_index].name, name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, token)
                ret (result, error_type, emit_error)
            }
            // A function named in a value position becomes a pointer to it.
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                if result_type.kind != .Function { ret (0usize, result_type, check.Unsupported) }
                let (function_ref, function_ref_error) = nir.intern_function(builder, callee.owner_module_index, callee.name, callee.instance_id)
                if function_ref_error != ok { ret (0usize, result_type, function_ref_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .FunctionAddress, result_type, true, function_ref, token)
                ret (result, result_type, emit_error)
            }
            ret (0usize, zero, check.Unsupported)
        }
        let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
        if type_error != ok { ret (0usize, result_type, type_error) }
        if !binding.address { ret (binding.value, result_type, ok) }
        if aggregate_value(c, result_type) { ret (binding.value, result_type, ok) }
        let (info, info_error) = layout.type_info(c, result_type)
        if info_error != ok { ret (0usize, result_type, info_error) }
        let (instruction, result, load_error) = nir.emit(builder, .Load, result_type, true, info.size, token)
        if load_error != ok { ret (0usize, result_type, load_error) }
        let operand_error = nir.add_operand(builder, instruction, binding.value)
        if operand_error != ok { ret (0usize, result_type, operand_error) }
        ret (result, result_type, ok)
    }
    if node.kind == .MemberExpr {
        let (result, result_type, result_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
        ret (result, result_type, result_error)
    }
    if node.kind == .FieldExpr {
        // `target.arch` and `target.os` (D223): the current target's member, a constant.
        let (target_question, is_target) = check.target_member(c, g, tree, module_index, node_index)
        if is_target {
            let (target_value, target_value_error) = check.target_enum_value(c, g, target_question)
            if target_value_error != ok { ret (0usize, zero, target_value_error) }
            let target_type = check.target_enum_type(target_question)
            let (target_instruction, target_result, target_emit_error) = nir.emit(builder, .ConstInteger, target_type, true, target_value, c.tokens[usize(node.token_start)])
            ret (target_result, target_type, target_emit_error)
        }
        // A member of an unrolled `for`'s binding is a constant, and the loop it came
        // from is gone by here.
        let (bound_value, bound_type, bound_handled, bound_error) = lower_binding_member_expr(c, g, tree, module_index, node_index, expected, builder)
        if bound_handled { ret (bound_value, bound_type, bound_error) }
        let (target_module, qualified_name, qualified) = check.qualified_member(c, g, tree, module_index, node)
        if qualified {
            let (constant_index, has_constant) = check.find_constant(c, target_module, qualified_name)
            if has_constant {
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error != ok { ret (0usize, result_type, type_error) }
                let (constant, constant_error) = lower_constant(c, constant_index, result_type, c.tokens[usize(node.token_start)], builder)
                ret (constant, result_type, constant_error)
            }
            let (symbol_index, has_symbol) = resolve.find(c.resolver, target_module, qualified_name, .Value)
            let (intrinsic_function, has_intrinsic_function) = check.find_function(c, target_module, qualified_name)
            if has_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                let error_type = check.make_type(.Err, "err", target_module)
                let (value, value_error) = artifact_hash.qualified_error_value(g.modules[target_module].name, qualified_name)
                if value_error != ok { ret (0usize, error_type, value_error) }
                let (instruction, result, emit_error) = nir.emit(builder, .ConstError, error_type, true, value, c.tokens[usize(node.token_start)])
                ret (result, error_type, emit_error)
            }
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
                if type_error == ok && result_type.kind == .Function {
                    let (function_ref, function_ref_error) = nir.intern_function(builder, callee.owner_module_index, callee.name, callee.instance_id)
                    if function_ref_error != ok { ret (0usize, result_type, function_ref_error) }
                    let (instruction, result, emit_error) = nir.emit(builder, .FunctionAddress, result_type, true, function_ref, c.tokens[usize(node.token_start)])
                    ret (result, result_type, emit_error)
                }
            }
            let (member_value, member_type, member_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
            if member_error == ok { ret (member_value, member_type, ok) }
            ret (0usize, zero, check.Unsupported)
        }
        let (base_index, has_base) = check.first_node_child(tree, node)
        if !has_base { ret (0usize, zero, parse.InvalidSyntax) }
        let (field_name, has_field) = check.field_expression_name(c, g.modules[module_index].text, tree, node)
        if !has_field { ret (0usize, zero, parse.InvalidSyntax) }
        let (base_type, base_type_error) = check.check_expr(c, g, tree, module_index, base_index, check.invalid_type())
        if base_type_error != ok {
            let (member_value, member_type, member_error) = lower_member(c, g, tree, module_index, node_index, expected, builder)
            ret (member_value, member_type, member_error)
        }
        if check.same(field_name, "len") && (base_type.kind == .String || base_type.kind == .Slice || base_type.kind == .Array) {
            let length_type = check.make_type(.Integer, "usize", module_index)
            if base_type.kind == .Array {
                let (instruction, result, emit_error) = nir.emit(builder, .ConstInteger, length_type, true, base_type.array_length, c.tokens[usize(node.token_start)])
                ret (result, length_type, emit_error)
            }
            let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
            if base_error != ok { ret (0usize, lowered_base_type, base_error) }
            let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, length_type, true, 8usize, c.tokens[usize(node.token_start)])
            if address_error != ok { ret (0usize, length_type, address_error) }
            let address_operand_error = nir.add_operand(builder, address_instruction, base)
            if address_operand_error != ok { ret (0usize, length_type, address_operand_error) }
            let (load_instruction, result, load_error) = nir.emit(builder, .Load, length_type, true, 8usize, c.tokens[usize(node.token_start)])
            if load_error != ok { ret (0usize, length_type, load_error) }
            let load_operand_error = nir.add_operand(builder, load_instruction, address)
            if load_operand_error != ok { ret (0usize, length_type, load_operand_error) }
            ret (result, length_type, ok)
        }
        let (field, field_error) = layout.field(c, base_type, field_name)
        if field_error != ok { ret (0usize, zero, check.Unsupported) }
        let (base, lowered_base_type, base_error) = lower_expression(c, g, tree, module_index, base_index, base_type, builder, bindings, binding_count)
        if base_error != ok { ret (0usize, lowered_base_type, base_error) }
        let null_error = emit_null_check(c, base, base_type, builder, c.tokens[usize(node.token_start)])
        if null_error != ok { ret (0usize, field.ty, null_error) }
        let tag_error = emit_tag_check(c, base, base_type, field_name, builder, c.tokens[usize(node.token_start)])
        if tag_error != ok { ret (0usize, field.ty, tag_error) }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, field.ty, true, field.offset, c.tokens[usize(node.token_start)])
        if address_error != ok { ret (0usize, field.ty, address_error) }
        let address_operand_error = nir.add_operand(builder, address_instruction, base)
        if address_operand_error != ok { ret (0usize, field.ty, address_operand_error) }
        if aggregate_value(c, field.ty) { ret (address, field.ty, ok) }
        let (field_info, field_info_error) = layout.type_info(c, field.ty)
        if field_info_error != ok { ret (0usize, field.ty, field_info_error) }
        let (load_instruction, result, load_error) = nir.emit(builder, .Load, field.ty, true, field_info.size, c.tokens[usize(node.token_start)])
        if load_error != ok { ret (0usize, field.ty, load_error) }
        let load_operand_error = nir.add_operand(builder, load_instruction, address)
        if load_operand_error != ok { ret (0usize, field.ty, load_operand_error) }
        ret (result, field.ty, ok)
    }
    if node.kind == .AggregateLiteral {
        let (result, result_type, result_error) = lower_aggregate_literal(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .BracketPostfix && check.contains_token(c, usize(node.token_start), usize(node.token_end), .PunctRange) {
        let (slice, slice_type, slice_error) = lower_slice(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (slice, slice_type, slice_error)
    }
    if node.kind == .BracketPostfix {
        let (result, result_type, result_error) = lower_index(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .UnaryExpr {
        let (result, result_type, result_error) = lower_unary(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (result, result_type, result_error)
    }
    if node.kind == .CallExpr {
        let (call_info, call_info_error) = check.check_call(c, g, tree, module_index, node)
        if call_info_error != ok { ret (0usize, zero, call_info_error) }
        if call_info.is_cast || call_info.mem_cast || call_info.mem_bitcast || call_info.mem_address || call_info.math_sqrt {
            var argument_index = 0usize
            var child_position = 0usize
            let end = usize(node.first_child) + usize(node.child_count)
            var at = usize(node.first_child)
            while at < end {
                if parse.child_is_node_at(tree, at) {
                    if child_position == 1usize { argument_index = parse.child_index_at(tree, at) }
                    child_position += 1usize
                }
                at += 1usize
            }
            if child_position != 2usize { ret (0usize, zero, check.ArgumentCount) }
            let (argument_type, argument_type_error) = check.check_expr(c, g, tree, module_index, argument_index, check.invalid_type())
            if argument_type_error != ok { ret (0usize, argument_type, argument_type_error) }
            let (argument, lowered_argument_type, argument_error) = lower_expression(c, g, tree, module_index, argument_index, argument_type, builder, bindings, binding_count)
            if argument_error != ok { ret (0usize, lowered_argument_type, argument_error) }
            // `mem.cast` only retypes: the pointer handed in is the pointer handed
            // back, so the operand passes through with no instruction of its own.
            if call_info.mem_cast { ret (argument, call_info.cast, ok) }
            // The address is the pointer: `address_of` is a bitcast to `usize`, the
            // same bits under a name that cannot be dereferenced, and the value has to
            // carry that name so arithmetic on it selects (D210).
            if call_info.mem_bitcast || call_info.mem_address {
                let (punned, punned_error) = lower_bitcast(c, argument, lowered_argument_type, call_info.cast, builder, c.tokens[usize(node.token_start)])
                ret (punned, call_info.cast, punned_error)
            }
            if call_info.math_sqrt {
                let (root_instruction, root, root_error) = nir.emit(builder, .Sqrt, call_info.cast, true, 0usize, c.tokens[usize(node.token_start)])
                if root_error != ok { ret (0usize, call_info.cast, root_error) }
                let root_operand_error = nir.add_operand(builder, root_instruction, argument)
                if root_operand_error != ok { ret (0usize, call_info.cast, root_operand_error) }
                ret (root, call_info.cast, ok)
            }
            // `Kind(x)`: the integer already has the backing width, so the value passes
            // through retyped once the members have been checked (D197).
            if call_info.cast.kind == .Named {
                // An enum value lives in a register as its backing bits zero-extended --
                // what a load and a member constant both give -- so a signed integer is
                // first truncated to the unsigned type of its width (a meant one: the
                // member check that follows is the check).
                var unsigned_name = "u64"
                let source_width = check.integer_width(lowered_argument_type)
                if source_width == 8usize { unsigned_name = "u8" }
                if source_width == 16usize { unsigned_name = "u16" }
                if source_width == 32usize { unsigned_name = "u32" }
                let unsigned_type = check.make_type(.Integer, unsigned_name, call_info.cast.module_index)
                let (bits_instruction, bits, bits_error) = nir.emit(builder, .Cast, unsigned_type, true, 1usize, c.tokens[usize(node.token_start)])
                if bits_error != ok { ret (0usize, call_info.cast, bits_error) }
                let bits_operand_error = nir.add_operand(builder, bits_instruction, argument)
                if bits_operand_error != ok { ret (0usize, call_info.cast, bits_operand_error) }
                let enum_check_error = emit_enum_check(c, bits, argument, call_info.cast, builder, c.tokens[usize(node.token_start)])
                if enum_check_error != ok { ret (0usize, call_info.cast, enum_check_error) }
                ret (bits, call_info.cast, ok)
            }
            // A `.Cast` whose immediate is 1 is a meant truncation, `T.trunc(x)`, which the
            // back end never checks (D198).
            var truncating = 0usize
            if call_info.truncating { truncating = 1usize }
            let (instruction, result, emit_error) = nir.emit(builder, .Cast, call_info.cast, true, truncating, c.tokens[usize(node.token_start)])
            if emit_error != ok { ret (0usize, call_info.cast, emit_error) }
            let add_error = nir.add_operand(builder, instruction, argument)
            if add_error != ok { ret (0usize, call_info.cast, add_error) }
            ret (result, call_info.cast, ok)
        }
        let (call, value, call_error) = lower_call(c, g, tree, module_index, node, builder, bindings, binding_count)
        if call_error != ok { ret (0usize, zero, call_error) }
        if call.function.return_count != 1usize { ret (0usize, zero, check.ArgumentCount) }
        let (result_type, result_error) = check.call_return(c, call, 0usize)
        ret (value, result_type, result_error)
    }
    if node.kind == .BinaryExpr {
        let (binary_value, binary_type, binary_error) = lower_binary_expr(c, g, tree, module_index, node_index, expected, builder, bindings, binding_count)
        ret (binary_value, binary_type, binary_error)
    }
    ret (0usize, zero, check.Unsupported)
}

fn lower_try(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    if function.return_count != 1usize { ret check.Unsupported }
    let end = usize(node.first_child) + usize(node.child_count)
    var call_index = 0usize
    var found_call = false
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            call_index = parse.child_index_at(tree, at)
            found_call = true
            break
        }
        at += 1usize
    }
    if !found_call { ret parse.InvalidSyntax }
    let call_node = tree.nodes[call_index]
    let (call, call_result, call_error) = lower_call(c, g, tree, module_index, call_node, builder, bindings, binding_count)
    if call_error != ok { ret call_error }
    if call.function.return_count != 1usize || !check.call_is_fallible(c, call) { ret check.InvalidTry }
    let (caller_error_type, caller_type_error) = check.function_return(c, function, 0usize)
    if caller_type_error != ok { ret caller_type_error }
    if caller_error_type.kind != .Err { ret check.InvalidTry }
    let (ok_instruction, ok_value, ok_error) = nir.emit(builder, .ConstError, caller_error_type, true, 0usize, c.tokens[usize(node.token_start)])
    if ok_error != ok { ret ok_error }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, failed, compare_error) = nir.emit(builder, .NotEqual, boolean, true, 0usize, c.tokens[usize(node.token_start)])
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, call_result)
    try nir.add_operand(builder, compare_instruction, ok_value)
    let error_block = builder.block_count
    let (branch_instruction, ignored, branch_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[usize(node.token_start)])
    if branch_error != ok { ret branch_error }
    try nir.add_operand(builder, branch_instruction, failed)
    let (error_block_index, error_block_error) = nir.begin_block(builder)
    if error_block_error != ok || error_block_index != error_block { ret nir.InvalidControlFlow }
    try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
    // A `try` that fails in `main` is `main` returning an error (section 13), and it
    // wrote nothing (D312): the failure line was on the `ret` path alone. The value is
    // known to be an error here, so the report is called without the comparison.
    if module_index == 0usize && check.same(function.name, "main") {
        try emit_failure_report_call(c, builder, module_index, call_result, c.tokens[usize(node.token_start)])
    }
    let (return_instruction, return_ignored, return_error) = nir.emit(builder, .Return, caller_error_type, false, 0usize, c.tokens[usize(node.token_start)])
    if return_error != ok { ret return_error }
    try nir.add_operand(builder, return_instruction, call_result)
    // The deferred calls may have been inlined, and with them blocks, so the
    // continuation's index is read only now (D207).
    let continue_block = builder.block_count
    try nir.set_branch_targets(builder, branch_instruction, error_block, continue_block)
    let (continue_block_index, continue_block_error) = nir.begin_block(builder)
    if continue_block_error != ok || continue_block_index != continue_block { ret nir.InvalidControlFlow }
    ret ok
}

fn lower_return(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    var values: [16]usize = zero
    var count = 0usize
    var literal_ok = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if count == values.len || count >= function.return_count { ret check.InvalidReturn }
            let returned = tree.nodes[parse.child_index_at(tree, at)]
            if count == 0usize && returned.kind == .LiteralExpr && c.tokens[usize(returned.token_start)].kind == .KwOk { literal_ok = true }
            let (expected, type_error) = check.function_return(c, function, count)
            if type_error != ok { ret type_error }
            let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, parse.child_index_at(tree, at), expected, builder, bindings, binding_count)
            if value_error != ok { ret value_error }
            values[count] = value
            count += 1usize
        }
        at += 1usize
    }
    if count != function.return_count { ret check.InvalidReturn }
    let (return_slot, has_return_slot) = find_binding(bindings, binding_count, "$return")
    if has_return_slot {
        var call: check.CallInfo = zero
        call.function = function
        var return_layout: ReturnLayout = zero
        let layout_error = call_return_layout(c, call, &return_layout)
        if layout_error != ok || !return_layout.via_slot { ret check.InvalidReturn }
        var result_at = 0usize
        while result_at < count {
            let result_type = c.return_types[function.first_return + result_at]
            let (info, info_error) = layout.type_info(c, result_type)
            if info_error != ok { ret info_error }
            let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, result_type, true, return_layout.offsets[result_at], c.tokens[usize(node.token_start)])
            if address_error != ok { ret address_error }
            try nir.add_operand(builder, address_instruction, return_slot.value)
            if aggregate_value(c, result_type) {
                let (copy_instruction, copy_ignored, copy_error) = nir.emit(builder, .Copy, result_type, false, info.size, c.tokens[usize(node.token_start)])
                if copy_error != ok { ret copy_error }
                try nir.add_operand(builder, copy_instruction, address)
                try nir.add_operand(builder, copy_instruction, values[result_at])
            } else {
                let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, result_type, false, info.size, c.tokens[usize(node.token_start)])
                if store_error != ok { ret store_error }
                try nir.add_operand(builder, store_instruction, address)
                try nir.add_operand(builder, store_instruction, values[result_at])
            }
            result_at += 1usize
        }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
        let (instruction, ignored, emit_error) = nir.emit(builder, .Return, zero, false, 0usize, c.tokens[usize(node.token_start)])
        ret emit_error
    }
    try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, binding_count, defers, 0usize)
    var return_type: check.Type = zero
    if function.return_count == 1usize { return_type = c.return_types[function.first_return] }
    // Section 13: `main` returning anything but `ok` writes `error: <qualified name>`
    // to stderr before the exit. The line is written by a function synthesized after
    // the module, `neper_report_failure`, reached only on the failing path.
    if module_index == 0usize && count == 1usize && return_type.kind == .Err && !literal_ok && check.same(function.name, "main") {
        let token = c.tokens[usize(node.token_start)]
        let (ok_instruction, ok_value, ok_error) = nir.emit(builder, .ConstError, return_type, true, 0usize, token)
        if ok_error != ok { ret ok_error }
        let boolean = check.make_type(.Bool, "bool", module_index)
        let (failed, failed_error) = emit_supplied_compare(builder, .NotEqual, boolean, values[0usize], ok_value, token)
        if failed_error != ok { ret failed_error }
        let report_block = builder.block_count
        let return_block = builder.block_count + 1usize
        let (branch_instruction, branch_ignored, branch_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
        if branch_error != ok { ret branch_error }
        try nir.add_operand(builder, branch_instruction, failed)
        try nir.set_branch_targets(builder, branch_instruction, report_block, return_block)
        let (report_index, report_block_error) = nir.begin_block(builder)
        if report_block_error != ok || report_index != report_block { ret nir.InvalidControlFlow }
        try emit_failure_report_call(c, builder, module_index, values[0usize], token)
        let (to_return, to_return_error) = emit_branch(builder, token)
        if to_return_error != ok { ret to_return_error }
        try nir.set_branch_targets(builder, to_return, return_block, 0usize)
        let (return_index, return_block_error) = nir.begin_block(builder)
        if return_block_error != ok || return_index != return_block { ret nir.InvalidControlFlow }
    }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Return, return_type, false, 0usize, c.tokens[usize(node.token_start)])
    if emit_error != ok { ret emit_error }
    at = 0usize
    while at < count {
        try nir.add_operand(builder, instruction, values[at])
        at += 1usize
    }
    ret ok
}

// The call that writes `main`'s failure line, and the note that the function it calls
// has to be synthesized after the module.
fn emit_failure_report_call(c: *check.Checker, builder: *nir.Builder, module_index: usize, value: usize, token: lex.Token) -> err {
    let (report_ref, report_ref_error) = nir.intern_function(builder, module_index, "neper_report_failure", 0usize)
    if report_ref_error != ok { ret report_ref_error }
    let (report_call, report_ignored, report_call_error) = nir.emit(builder, .Call, zero, false, report_ref, token)
    if report_call_error != ok { ret report_call_error }
    try nir.add_operand(builder, report_call, value)
    c.main_reports_failure = true
    ret ok
}

fn lower_binding(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize) -> err {
    var binding_node: syntax.Node = zero
    var found_binding = false
    var initializer_index = 0usize
    var found_initializer = false
    var declared = check.invalid_type()
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .Binding {
                binding_node = child
                found_binding = true
            } else {
                if check.is_type_node(child.kind) {
                    let (resolved, type_error) = check.type_from_node(c, c.resolver, g, tree, module_index, child)
                    if type_error != ok { ret type_error }
                    declared = resolved
                } else {
                    initializer_index = child_index
                    found_initializer = true
                }
            }
        }
        at += 1usize
    }
    if !found_binding { ret check.Unsupported }
    if found_initializer && check.contains_token(c, usize(node.token_start), usize(tree.nodes[initializer_index].token_start), .KwTry) { ret check.Unsupported }
    if c.tokens[usize(binding_node.token_start)].kind == .PunctLParen {
        if !found_initializer || tree.nodes[initializer_index].kind != .CallExpr || declared.kind != .Invalid { ret check.ArgumentCount }
        var results: CallResults = zero
        let results_error = lower_call_results(c, g, tree, module_index, tree.nodes[initializer_index], builder, bindings, *binding_count, &results)
        if results_error != ok { ret results_error }
        let mutable = c.tokens[usize(node.token_start)].kind == .KwVar
        ret bind_call_results(c, g, module_index, binding_node, &results, mutable, builder, bindings, binding_count)
    }
    let (name, has_name) = check.first_name(c, g.modules[module_index].text, binding_node)
    if !has_name { ret parse.InvalidSyntax }
    let mutable = c.tokens[usize(node.token_start)].kind == .KwVar
    var value = 0usize
    var value_type = declared
    var stored_value = 0usize
    var address = false
    if found_initializer {
        let (lowered_value, lowered_type, value_error) = lower_expression(c, g, tree, module_index, initializer_index, declared, builder, bindings, *binding_count)
        if value_error != ok { ret value_error }
        value = lowered_value
        value_type = lowered_type
        stored_value = value
    } else {
        if declared.kind == .Invalid { ret check.MissingContext }
        let is_zero = check.contains_token(c, usize(node.token_start), usize(node.token_end), .KwZero)
        let is_undef = check.contains_token(c, usize(node.token_start), usize(node.token_end), .KwUndef)
        if !is_zero && !is_undef { ret check.Unsupported }
        if aggregate_value(c, declared) {
            let (info, info_error) = layout.type_info(c, declared)
            if info_error != ok { ret info_error }
            var slots = (info.size + 7usize) / 8usize
            if slots == 0usize { slots = 1usize }
            let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, declared, true, slots, c.tokens[usize(node.token_start)])
            if stack_error != ok { ret stack_error }
            if is_zero {
                let (zero_instruction, zero_ignored, zero_error) = nir.emit(builder, .Zero, declared, false, info.size, c.tokens[usize(node.token_start)])
                if zero_error != ok { ret zero_error }
                try nir.add_operand(builder, zero_instruction, stack)
            }
            value = stack
            stored_value = stack
            address = true
        } else {
            if is_zero {
                let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .Zero, declared, true, 0usize, c.tokens[usize(node.token_start)])
                if zero_error != ok { ret zero_error }
                value = zero_value
                stored_value = zero_value
            } else {
                let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, declared, true, 0usize, c.tokens[usize(node.token_start)])
                if stack_error != ok { ret stack_error }
                value = stack
                stored_value = stack
                address = true
            }
        }
    }
    if aggregate_value(c, value_type) {
        address = true
    } else {
    if mutable && !address {
        let (info, info_error) = layout.type_info(c, value_type)
        if info_error != ok { ret info_error }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, value_type, true, 0usize, c.tokens[usize(node.token_start)])
        if stack_error != ok { ret stack_error }
        let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, value_type, false, info.size, c.tokens[usize(node.token_start)])
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, stack)
        try nir.add_operand(builder, store_instruction, value)
        stored_value = stack
        address = true
    }
    }
    ret bind_value(c, g, module_index, c.tokens[usize(binding_node.token_start)], value_type, stored_value, address, mutable, builder, bindings, binding_count)
}

fn store_assignment_value(c: *check.Checker, ty: check.Type, address: usize, value: usize, token: lex.Token, builder: *nir.Builder) -> err {
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret info_error }
    if aggregate_value(c, ty) {
        let (instruction, ignored, emit_error) = nir.emit(builder, .Copy, ty, false, info.size, token)
        if emit_error != ok { ret emit_error }
        try nir.add_operand(builder, instruction, address)
        try nir.add_operand(builder, instruction, value)
        ret ok
    }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Store, ty, false, info.size, token)
    if emit_error != ok { ret emit_error }
    try nir.add_operand(builder, instruction, address)
    try nir.add_operand(builder, instruction, value)
    ret ok
}

fn lower_assignment(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    var children: [17]usize = zero
    var count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if count == children.len { ret parse.InvalidSyntax }
            children[count] = parse.child_index_at(tree, at)
            count += 1usize
        }
        at += 1usize
    }
    if count < 2usize { ret parse.InvalidSyntax }
    if count > 2usize {
        let place_count = count - 1usize
        if place_count > 16usize { ret check.ArgumentCount }
        var addresses: [16]usize = zero
        var place_types: [16]check.Type = zero
        var place_at = 0usize
        while place_at < place_count {
            let (address, place_type, address_error) = lower_place(c, g, tree, module_index, children[place_at], builder, bindings, binding_count)
            if address_error != ok { ret address_error }
            addresses[place_at] = address
            place_types[place_at] = place_type
            place_at += 1usize
        }
        let initializer = tree.nodes[children[place_count]]
        if initializer.kind != .CallExpr { ret check.ArgumentCount }
        var results: CallResults = zero
        let results_error = lower_call_results(c, g, tree, module_index, initializer, builder, bindings, binding_count, &results)
        if results_error != ok { ret results_error }
        if results.count != place_count { ret check.ArgumentCount }
        place_at = 0usize
        while place_at < place_count {
            let (result_type, result_type_error) = check.call_return(c, results.call, place_at)
            if result_type_error != ok { ret result_type_error }
            if !check.type_assignable(c, result_type, place_types[place_at]) { ret check.InvalidType }
            try store_assignment_value(c, place_types[place_at], addresses[place_at], results.values[place_at], c.tokens[usize(node.token_start)], builder)
            place_at += 1usize
        }
        ret ok
    }
    let (address, place_type, address_error) = lower_place(c, g, tree, module_index, children[0usize], builder, bindings, binding_count)
    if address_error != ok { ret address_error }
    let assignment = check.assignment_operator(c, usize(tree.nodes[children[0usize]].token_end), usize(tree.nodes[children[1usize]].token_start))
    if assignment != .PunctAssign {
        let opcode = compound_opcode(assignment)
        if opcode == .Invalid || aggregate_value(c, place_type) { ret check.InvalidOperator }
        let (info, info_error) = layout.type_info(c, place_type)
        if info_error != ok { ret info_error }
        let (load_instruction, current, load_error) = nir.emit(builder, .Load, place_type, true, info.size, c.tokens[usize(node.token_start)])
        if load_error != ok { ret load_error }
        try nir.add_operand(builder, load_instruction, address)
        var expected = place_type
        if opcode == .ShiftLeft || opcode == .ShiftRight { expected = check.invalid_type() }
        let (right, right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], expected, builder, bindings, binding_count)
        if right_error != ok { ret right_error }
        if opcode != .ShiftLeft && opcode != .ShiftRight && !check.type_equal(c, place_type, right_type) { ret check.InvalidType }
        let (binary_instruction, value, binary_error) = nir.emit(builder, opcode, place_type, true, 0usize, c.tokens[usize(node.token_start)])
        if binary_error != ok { ret binary_error }
        try nir.add_operand(builder, binary_instruction, current)
        try nir.add_operand(builder, binary_instruction, right)
        ret store_assignment_value(c, place_type, address, value, c.tokens[usize(node.token_start)], builder)
    }
    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, children[1usize], place_type, builder, bindings, binding_count)
    if value_error != ok { ret value_error }
    // What the checker admitted here is assignability, not equality: a `[]T` into a
    // `[]const T` place, a `*T` into a `*const T`. Both are the same bits.
    if !check.type_assignable(c, value_type, place_type) { ret check.InvalidType }
    ret store_assignment_value(c, place_type, address, value, c.tokens[usize(node.token_start)], builder)
}

fn lower_call_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let call_node = tree.nodes[parse.child_index_at(tree, at)]
            var results: CallResults = zero
            let call_error = lower_call_results(c, g, tree, module_index, call_node, builder, bindings, binding_count, &results)
            if call_error != ok { ret call_error }
            if results.count != 0usize { ret check.ArgumentCount }
            ret ok
        }
        at += 1usize
    }
    ret parse.InvalidSyntax
}

fn emit_branch(builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (instruction, ignored, emit_error) = nir.emit(builder, .Branch, zero, false, 0usize, token)
    ret (instruction, emit_error)
}

fn emit_branch_at(builder: *nir.Builder, site: nir.Site) -> (usize, err) {
    let (instruction, ignored, emit_error) = nir.emit_at(builder, .Branch, zero, false, 0usize, site)
    ret (instruction, emit_error)
}

// Section 6's `when`: the checker settled the condition and checked both blocks; the
// taken one is the only code here (D216).
fn lower_when(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    var condition_index = 0usize
    var found_condition = false
    var branches: [2]usize = zero
    var branch_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if !found_condition {
                condition_index = child_index
                found_condition = true
            } else {
                if branch_count == branches.len { ret check.Unsupported }
                branches[branch_count] = child_index
                branch_count += 1usize
            }
        }
        at += 1usize
    }
    if !found_condition || branch_count == 0usize { ret parse.InvalidSyntax }
    let (taken, condition_error) = check.when_condition(c, g, tree, module_index, condition_index)
    if condition_error != ok { ret condition_error }
    if taken { ret lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count, control, defers) }
    if branch_count == 2usize { ret lower_block(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count, control, defers) }
    ret ok
}

// An `else if` is an IfStmt standing where the else block would (grammar if_stmt): lower it
// as the nested `if` it is, so the chain needs no extra block or merge of its own.
fn lower_branch(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    if node.kind == .IfStmt { ret lower_if(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    ret lower_block(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers)
}

fn lower_if(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    var condition_index = 0usize
    var found_condition = false
    var branches: [2]usize = zero
    var branch_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if !found_condition {
                condition_index = child_index
                found_condition = true
            } else {
                if (child.kind != .Block && child.kind != .IfStmt) || branch_count == branches.len { ret check.Unsupported }
                branches[branch_count] = child_index
                branch_count += 1usize
            }
        }
        at += 1usize
    }
    if !found_condition || branch_count == 0usize { ret parse.InvalidSyntax }
    // The same question the checker asked, on the same tree with the same comptime bindings in
    // place: a settled condition has one arm, and the other was never checked, so emitting it
    // would emit code nothing has looked at. Nothing was remembered from the checker -- asking
    // twice is what keeps the two passes from drifting apart.
    let (taken, settled) = check.comptime_condition(c, g, tree, module_index, condition_index)
    if settled {
        if taken { ret lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count, control, defers) }
        if branch_count == 2usize { ret lower_branch(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count, control, defers) }
        ret ok
    }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (condition, condition_type, condition_error) = lower_expression(c, g, tree, module_index, condition_index, boolean, builder, bindings, *binding_count)
    if condition_error != ok { ret condition_error }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[usize(node.token_start)])
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, condition)

    let true_block = builder.block_count
    let (true_index, true_error) = nir.begin_block(builder)
    if true_error != ok || true_index != true_block { ret nir.InvalidControlFlow }
    try lower_block(c, g, tree, module_index, function, tree.nodes[branches[0usize]], builder, bindings, binding_count, control, defers)
    var true_exit = 0usize
    let true_falls_through = !builder.blocks[builder.current_block].terminated
    if true_falls_through {
        let (branch, branch_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if branch_error != ok { ret branch_error }
        true_exit = branch
    }

    let false_block = builder.block_count
    let (false_index, false_error) = nir.begin_block(builder)
    if false_error != ok || false_index != false_block { ret nir.InvalidControlFlow }
    if branch_count == 2usize { try lower_branch(c, g, tree, module_index, function, tree.nodes[branches[1usize]], builder, bindings, binding_count, control, defers) }
    var false_exit = 0usize
    let false_falls_through = !builder.blocks[builder.current_block].terminated
    if false_falls_through {
        let (branch, branch_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if branch_error != ok { ret branch_error }
        false_exit = branch
    }

    try nir.set_branch_targets(builder, decision, true_block, false_block)
    if true_falls_through || false_falls_through {
        let merge_block = builder.block_count
        let (merge_index, merge_error) = nir.begin_block(builder)
        if merge_error != ok || merge_index != merge_block { ret nir.InvalidControlFlow }
        if true_falls_through { try nir.set_branch_targets(builder, true_exit, merge_block, 0usize) }
        if false_falls_through { try nir.set_branch_targets(builder, false_exit, merge_block, 0usize) }
    }
    ret ok
}

fn lower_while(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    var condition_index = 0usize
    var body_index = 0usize
    var found_condition = false
    var found_body = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if !found_condition {
                condition_index = child_index
                found_condition = true
            } else {
                if found_body || tree.nodes[child_index].kind != .Block { ret check.Unsupported }
                body_index = child_index
                found_body = true
            }
        }
        at += 1usize
    }
    if !found_condition || !found_body { ret parse.InvalidSyntax }
    let (entry_branch, entry_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
    if entry_error != ok { ret entry_error }
    let condition_block = builder.block_count
    let (condition_block_index, condition_block_error) = nir.begin_block(builder)
    if condition_block_error != ok || condition_block_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (condition, condition_type, condition_error) = lower_expression(c, g, tree, module_index, condition_index, boolean, builder, bindings, *binding_count)
    if condition_error != ok { ret condition_error }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[usize(node.token_start)])
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, condition)
    let body_block = builder.block_count
    let (body_block_index, body_block_error) = nir.begin_block(builder)
    if body_block_error != ok || body_block_index != body_block { ret nir.InvalidControlFlow }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: condition_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    try lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    if !builder.blocks[builder.current_block].terminated {
        let (back_edge, back_edge_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if back_edge_error != ok { ret back_edge_error }
        try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_block_index, exit_block_error) = nir.begin_block(builder)
    if exit_block_error != ok || exit_block_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    let condition_node = tree.nodes[condition_index]
    if control.break_count == 0usize && condition_node.kind == .LiteralExpr && c.tokens[usize(condition_node.token_start)].kind == .KwTrue {
        let (unreachable_instruction, unreachable_value, unreachable_error) = nir.emit(builder, .Unreachable, zero, false, 0usize, c.tokens[usize(condition_node.token_start)])
        if unreachable_error != ok { ret unreachable_error }
    }
    ret ok
}

fn lower_iterable_parts(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, expression_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: usize, data: *usize, length: *usize, element_type: *check.Type, stride: *usize) -> err {
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, expression_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    if subject_type.kind != .Array && subject_type.kind != .Slice && subject_type.kind != .String { ret check.Unsupported }
    let (resolved_element, element_error) = check.index_element_type(c, subject_type, module_index)
    if element_error != ok { ret element_error }
    *element_type = resolved_element
    let (element_info, element_info_error) = layout.type_info(c, resolved_element)
    if element_info_error != ok { ret element_info_error }
    *stride = element_info.size
    let (subject, lowered_subject_type, subject_error) = lower_expression(c, g, tree, module_index, expression_index, subject_type, builder, bindings, binding_count)
    if subject_error != ok { ret subject_error }
    *data = subject
    let usize_type = check.make_type(.Integer, "usize", module_index)
    if subject_type.kind == .Array {
        let (length_instruction, length_value, length_error) = nir.emit(builder, .ConstInteger, usize_type, true, subject_type.array_length, c.tokens[usize(tree.nodes[expression_index].token_start)])
        if length_error != ok { ret length_error }
        *length = length_value
        ret ok
    }
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let token = c.tokens[usize(tree.nodes[expression_index].token_start)]
    let (data_address_instruction, data_address, data_address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, 0usize, token)
    if data_address_error != ok { ret data_address_error }
    try nir.add_operand(builder, data_address_instruction, subject)
    let (data_load_instruction, data_value, data_load_error) = nir.emit(builder, .Load, pointer_type, true, 8usize, token)
    if data_load_error != ok { ret data_load_error }
    try nir.add_operand(builder, data_load_instruction, data_address)
    *data = data_value
    let (length_address_instruction, length_address, length_address_error) = nir.emit(builder, .FieldAddress, usize_type, true, 8usize, token)
    if length_address_error != ok { ret length_address_error }
    try nir.add_operand(builder, length_address_instruction, subject)
    let (length_load_instruction, length_value, length_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if length_load_error != ok { ret length_load_error }
    try nir.add_operand(builder, length_load_instruction, length_address)
    *length = length_value
    ret ok
}

fn protocol_next_function(c: *check.Checker, iterator: check.Type) -> (check.Function, err) {
    var empty: check.Function = zero
    var at = 0usize
    while at < c.signature_function_count {
        let candidate = c.functions[at]
        if candidate.module_index == iterator.module_index && check.iterator_next_name_matches(iterator.name, candidate.name) { ret (candidate, ok) }
        at += 1usize
    }
    ret (empty, check.UnknownCallable)
}

fn lower_protocol_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, subject_index: usize, body_index: usize, name: lex.Token, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    let token = c.tokens[usize(node.token_start)]
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, subject_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    var iterator_type = subject_type
    var iterator_pointer = 0usize
    if subject_type.kind == .Pointer {
        if !subject_type.has_element || subject_type.element >= c.type_count { ret check.InvalidType }
        iterator_type = c.types[subject_type.element]
        let (pointer, pointer_type, pointer_error) = lower_expression(c, g, tree, module_index, subject_index, subject_type, builder, bindings, *binding_count)
        if pointer_error != ok { ret pointer_error }
        iterator_pointer = pointer
    } else {
        let (address, place_type, place_error) = lower_place(c, g, tree, module_index, subject_index, builder, bindings, *binding_count)
        if place_error != ok { ret place_error }
        iterator_pointer = address
    }
    let (canonical_iterator, canonical_error) = check.canonical_type(c, iterator_type)
    if canonical_error != ok { ret canonical_error }
    let (next, next_error) = protocol_next_function(c, canonical_iterator)
    if next_error != ok { ret next_error }
    var call: check.CallInfo = zero
    call.function = next
    let (entry_branch, entry_error) = emit_branch(builder, token)
    if entry_error != ok { ret entry_error }
    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    var arguments: [1]usize = zero
    arguments[0usize] = iterator_pointer
    var results: CallResults = zero
    try emit_call_results(c, call, 0usize, arguments[..], 1usize, builder, token, &results)
    if results.count != 2usize { ret check.InvalidType }
    let (element_type, element_type_error) = check.call_return(c, call, 0usize)
    if element_type_error != ok { ret element_type_error }
    let (has_value_type, has_value_type_error) = check.call_return(c, call, 1usize)
    if has_value_type_error != ok || has_value_type.kind != .Bool { ret check.InvalidType }
    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, results.values[1usize])
    let body_block = builder.block_count
    let (body_index_value, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index_value != body_block { ret nir.InvalidControlFlow }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    try bind_value(c, g, module_index, name, element_type, results.values[0usize], results.addresses[0usize], false, builder, bindings, binding_count)
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: condition_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    let lowered_body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    if lowered_body_error != ok { ret lowered_body_error }
    if !builder.blocks[builder.current_block].terminated {
        let (back_edge, back_edge_error) = emit_branch(builder, token)
        if back_edge_error != ok { ret back_edge_error }
        try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_index, exit_error) = nir.begin_block(builder)
    if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    ret ok
}

// Section 9: a `for` over a comptime sequence is unrolled, and nothing of the loop
// survives -- what the emitter sees is the straight-line bodies. The binding is pushed
// on the checker's comptime stack for each copy, which is how the body's `f.name`,
// `f.ty` and `meta.get[f, T]` see a different value each time.
// Split out of `lower_expression`, which is at the bootstrap's per-function local
// limit: every binding here would otherwise be one of its.
// Split out of `lower_expression`, which sits at the bootstrap's per-function local
// limit -- every binding below would otherwise be one of its. The short-circuit
// operators alone account for a third of them.
fn lower_binary_expr(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, check.Type, err) {
    let node = tree.nodes[node_index]
    var children: [2]usize = zero
    var child_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == children.len { ret (0usize, zero, parse.InvalidSyntax) }
            children[child_count] = parse.child_index_at(tree, at)
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count != 2usize { ret (0usize, zero, parse.InvalidSyntax) }
    let (result_type, result_type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if result_type_error != ok { ret (0usize, result_type, result_type_error) }
    let operator = check.binary_operator(c, tree, node)
    if operator == .PunctAndAnd || operator == .PunctOrOr {
        let boolean = check.make_type(.Bool, "bool", module_index)
        let (left, left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], boolean, builder, bindings, binding_count)
        if left_error != ok { ret (0usize, left_type, left_error) }
        let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, boolean, true, 0usize, c.tokens[usize(node.token_start)])
        if stack_error != ok { ret (0usize, boolean, stack_error) }
        let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[usize(node.token_start)])
        if decision_error != ok { ret (0usize, boolean, decision_error) }
        let decision_operand_error = nir.add_operand(builder, decision, left)
        if decision_operand_error != ok { ret (0usize, boolean, decision_operand_error) }

        let right_block = builder.block_count
        let (right_block_index, right_block_error) = nir.begin_block(builder)
        if right_block_error != ok || right_block_index != right_block { ret (0usize, boolean, nir.InvalidControlFlow) }
        let (right, right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], boolean, builder, bindings, binding_count)
        if right_error != ok { ret (0usize, right_type, right_error) }
        let (right_store, right_store_ignored, right_store_error) = nir.emit(builder, .Store, boolean, false, 0usize, c.tokens[usize(node.token_start)])
        if right_store_error != ok { ret (0usize, boolean, right_store_error) }
        let right_address_error = nir.add_operand(builder, right_store, stack)
        if right_address_error != ok { ret (0usize, boolean, right_address_error) }
        let right_value_error = nir.add_operand(builder, right_store, right)
        if right_value_error != ok { ret (0usize, boolean, right_value_error) }
        let (right_exit, right_exit_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if right_exit_error != ok { ret (0usize, boolean, right_exit_error) }

        let short_block = builder.block_count
        let (short_block_index, short_block_error) = nir.begin_block(builder)
        if short_block_error != ok || short_block_index != short_block { ret (0usize, boolean, nir.InvalidControlFlow) }
        var short_immediate = 0usize
        if operator == .PunctOrOr { short_immediate = 1usize }
        let (short_constant_instruction, short_value, short_constant_error) = nir.emit(builder, .ConstBool, boolean, true, short_immediate, c.tokens[usize(node.token_start)])
        if short_constant_error != ok { ret (0usize, boolean, short_constant_error) }
        let (short_store, short_store_ignored, short_store_error) = nir.emit(builder, .Store, boolean, false, 0usize, c.tokens[usize(node.token_start)])
        if short_store_error != ok { ret (0usize, boolean, short_store_error) }
        let short_address_error = nir.add_operand(builder, short_store, stack)
        if short_address_error != ok { ret (0usize, boolean, short_address_error) }
        let short_value_error = nir.add_operand(builder, short_store, short_value)
        if short_value_error != ok { ret (0usize, boolean, short_value_error) }
        let (short_exit, short_exit_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if short_exit_error != ok { ret (0usize, boolean, short_exit_error) }

        let merge_block = builder.block_count
        let (merge_block_index, merge_block_error) = nir.begin_block(builder)
        if merge_block_error != ok || merge_block_index != merge_block { ret (0usize, boolean, nir.InvalidControlFlow) }
        if operator == .PunctAndAnd {
            let target_error = nir.set_branch_targets(builder, decision, right_block, short_block)
            if target_error != ok { ret (0usize, boolean, target_error) }
        } else {
            let target_error = nir.set_branch_targets(builder, decision, short_block, right_block)
            if target_error != ok { ret (0usize, boolean, target_error) }
        }
        let right_target_error = nir.set_branch_targets(builder, right_exit, merge_block, 0usize)
        if right_target_error != ok { ret (0usize, boolean, right_target_error) }
        let short_target_error = nir.set_branch_targets(builder, short_exit, merge_block, 0usize)
        if short_target_error != ok { ret (0usize, boolean, short_target_error) }
        let (load_instruction, result, load_error) = nir.emit(builder, .Load, boolean, true, 0usize, c.tokens[usize(node.token_start)])
        if load_error != ok { ret (0usize, boolean, load_error) }
        let load_operand_error = nir.add_operand(builder, load_instruction, stack)
        if load_operand_error != ok { ret (0usize, boolean, load_operand_error) }
        ret (result, result_type, ok)
    }
    let opcode = binary_opcode(operator)
    if opcode == .Invalid { ret (0usize, zero, check.InvalidOperator) }
    if check.is_vector_type(c, result_type) {
        let (vector, vector_error) = lower_vector_binary(c, g, tree, module_index, node, children[0usize], children[1usize], result_type, opcode, builder, bindings, binding_count)
        ret (vector, result_type, vector_error)
    }
    var operand_expected = result_type
    if check.is_comparison(operator) { operand_expected = check.invalid_type() }
    let (left_type, left_type_error) = check.check_expr(c, g, tree, module_index, children[0usize], operand_expected)
    if left_type_error != ok { ret (0usize, left_type, left_type_error) }
    let (left, lowered_left_type, left_error) = lower_expression(c, g, tree, module_index, children[0usize], left_type, builder, bindings, binding_count)
    if left_error != ok { ret (0usize, lowered_left_type, left_error) }
    var right_expected = left_type
    if operator == .PunctShiftLeft || operator == .PunctShiftRight { right_expected = check.invalid_type() }
    let (right_type, right_type_error) = check.check_expr(c, g, tree, module_index, children[1usize], right_expected)
    if right_type_error != ok { ret (0usize, right_type, right_type_error) }
    let (right, lowered_right_type, right_error) = lower_expression(c, g, tree, module_index, children[1usize], right_type, builder, bindings, binding_count)
    if right_error != ok { ret (0usize, lowered_right_type, right_error) }
    var left_ordered = left
    var right_ordered = right
    if ordering_opcode(opcode) {
        let (left_operand, left_coerce_error) = coerce_ordering_operand(c, left_type, left, builder, c.tokens[usize(node.token_start)])
        if left_coerce_error != ok { ret (0usize, result_type, left_coerce_error) }
        let (right_operand, right_coerce_error) = coerce_ordering_operand(c, right_type, right, builder, c.tokens[usize(node.token_start)])
        if right_coerce_error != ok { ret (0usize, result_type, right_coerce_error) }
        left_ordered = left_operand
        right_ordered = right_operand
    }
    let (instruction, result, emit_error) = nir.emit(builder, opcode, result_type, true, 0usize, c.tokens[usize(node.token_start)])
    if emit_error != ok { ret (0usize, result_type, emit_error) }
    let left_operand_error = nir.add_operand(builder, instruction, left_ordered)
    if left_operand_error != ok { ret (0usize, result_type, left_operand_error) }
    let right_operand_error = nir.add_operand(builder, instruction, right_ordered)
    if right_operand_error != ok { ret (0usize, result_type, right_operand_error) }
    ret (result, result_type, ok)
    ret (0usize, check.invalid_type(), check.Unsupported)
}
// Section 4's lane-wise operators over the one-field representation of a vector
// (D148): both operands are addresses, the result is a fresh slot, and each lane is
// one scalar instruction between a load and a store at the lane's offset. A shift's
// right operand is the one scalar count, applied to every lane.
// ponytail: N scalar instructions per operator; a vector register class selects one.
fn lower_vector_binary(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, left_index: usize, right_index: usize, result_type: check.Type, opcode: nir.Opcode, builder: *nir.Builder, bindings: []Binding, binding_count: usize) -> (usize, err) {
    let token = c.tokens[usize(node.token_start)]
    let (lanes, is_vector) = check.vector_lanes(c, result_type)
    let (lane, has_lane) = check.vector_lane_type(c, result_type)
    if !is_vector || !has_lane { ret (0usize, check.InvalidType) }
    let (lane_info, lane_info_error) = layout.type_info(c, lane)
    if lane_info_error != ok { ret (0usize, lane_info_error) }
    let shifting = opcode == .ShiftLeft || opcode == .ShiftRight
    let (left, left_type, left_error) = lower_expression(c, g, tree, module_index, left_index, result_type, builder, bindings, binding_count)
    if left_error != ok { ret (0usize, left_error) }
    var right_expected = result_type
    if shifting {
        let (count_type, count_error) = check.check_expr(c, g, tree, module_index, right_index, check.invalid_type())
        if count_error != ok { ret (0usize, count_error) }
        right_expected = count_type
        if count_type.kind == .UntypedInteger { right_expected = check.make_type(.Integer, "u32", module_index) }
    }
    let (right, right_type, right_error) = lower_expression(c, g, tree, module_index, right_index, right_expected, builder, bindings, binding_count)
    if right_error != ok { ret (0usize, right_error) }
    let (stack, stack_error) = vector_slot(c, result_type, builder, token)
    if stack_error != ok { ret (0usize, stack_error) }
    var at = 0usize
    while at < lanes.array_length {
        let offset = at * lane_info.size
        let (left_lane, left_lane_error) = component_at(c, lane, left, offset, builder, token)
        if left_lane_error != ok { ret (0usize, left_lane_error) }
        var right_lane = right
        if !shifting {
            let (loaded, right_lane_error) = component_at(c, lane, right, offset, builder, token)
            if right_lane_error != ok { ret (0usize, right_lane_error) }
            right_lane = loaded
        }
        let (instruction, value, emit_error) = nir.emit(builder, opcode, lane, true, 0usize, token)
        if emit_error != ok { ret (0usize, emit_error) }
        let left_operand_error = nir.add_operand(builder, instruction, left_lane)
        if left_operand_error != ok { ret (0usize, left_operand_error) }
        let right_operand_error = nir.add_operand(builder, instruction, right_lane)
        if right_operand_error != ok { ret (0usize, right_operand_error) }
        let store_error = store_lane(c, lane, lane_info.size, stack, offset, value, builder, token)
        if store_error != ok { ret (0usize, store_error) }
        at += 1usize
    }
    ret (stack, ok)
}

// `~v` on integer lanes is the bitwise not of each; on a mask it is each lane's `!`,
// spelled the way `!` is lowered -- equal to `false`.
fn lower_vector_not(c: *check.Checker, node: syntax.Node, operand: usize, result_type: check.Type, builder: *nir.Builder) -> (usize, err) {
    let token = c.tokens[usize(node.token_start)]
    let (lanes, is_vector) = check.vector_lanes(c, result_type)
    let (lane, has_lane) = check.vector_lane_type(c, result_type)
    if !is_vector || !has_lane { ret (0usize, check.InvalidType) }
    let (lane_info, lane_info_error) = layout.type_info(c, lane)
    if lane_info_error != ok { ret (0usize, lane_info_error) }
    let (stack, stack_error) = vector_slot(c, result_type, builder, token)
    if stack_error != ok { ret (0usize, stack_error) }
    var at = 0usize
    while at < lanes.array_length {
        let offset = at * lane_info.size
        let (loaded, load_error) = component_at(c, lane, operand, offset, builder, token)
        if load_error != ok { ret (0usize, load_error) }
        var value = 0usize
        if lane.kind == .Bool {
            let (false_instruction, false_value, false_error) = nir.emit(builder, .ConstBool, lane, true, 0usize, token)
            if false_error != ok { ret (0usize, false_error) }
            let (instruction, flipped, emit_error) = nir.emit(builder, .Equal, lane, true, 0usize, token)
            if emit_error != ok { ret (0usize, emit_error) }
            let loaded_error = nir.add_operand(builder, instruction, loaded)
            if loaded_error != ok { ret (0usize, loaded_error) }
            let false_operand_error = nir.add_operand(builder, instruction, false_value)
            if false_operand_error != ok { ret (0usize, false_operand_error) }
            value = flipped
        } else {
            let (instruction, inverted, emit_error) = nir.emit(builder, .BitNot, lane, true, 0usize, token)
            if emit_error != ok { ret (0usize, emit_error) }
            let loaded_error = nir.add_operand(builder, instruction, loaded)
            if loaded_error != ok { ret (0usize, loaded_error) }
            value = inverted
        }
        let store_error = store_lane(c, lane, lane_info.size, stack, offset, value, builder, token)
        if store_error != ok { ret (0usize, store_error) }
        at += 1usize
    }
    ret (stack, ok)
}

fn vector_slot(c: *check.Checker, ty: check.Type, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let (info, info_error) = layout.type_info(c, ty)
    if info_error != ok { ret (0usize, info_error) }
    var slots = (info.size + 7usize) / 8usize
    if slots == 0usize { slots = 1usize }
    let (stack_instruction, stack, stack_error) = nir.emit(builder, .Stack, ty, true, slots, token)
    ret (stack, stack_error)
}

fn store_lane(c: *check.Checker, lane: check.Type, size: usize, base: usize, offset: usize, value: usize, builder: *nir.Builder, token: lex.Token) -> err {
    let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, lane, true, offset, token)
    if address_error != ok { ret address_error }
    try nir.add_operand(builder, address_instruction, base)
    let (store_instruction, ignored, store_error) = nir.emit(builder, .Store, lane, false, size, token)
    if store_error != ok { ret store_error }
    try nir.add_operand(builder, store_instruction, address)
    ret nir.add_operand(builder, store_instruction, value)
}

// A comptime array in a body is the array its literal spelled, materialised in a slot:
// one constant store per item. ponytail: a data-section constant would do, and the
// register class will fold an index into it away; a slot is what every other array
// literal gets today.
fn lower_comptime_array(c: *check.Checker, argument: check.GenericArgument, token: lex.Token, builder: *nir.Builder) -> (usize, err) {
    let array = argument.ty
    if array.kind != .Array || !array.has_element || array.element >= c.type_count { ret (0usize, check.InvalidType) }
    let element = c.types[array.element]
    let (element_info, element_info_error) = layout.type_info(c, element)
    if element_info_error != ok { ret (0usize, element_info_error) }
    let (stack, stack_error) = vector_slot(c, array, builder, token)
    if stack_error != ok { ret (0usize, stack_error) }
    var at = 0usize
    var item = 0usize
    while item < array.array_length {
        let (value, has_item) = check.comptime_array_item(argument.text, &at)
        if !has_item { ret (0usize, check.InvalidConstant) }
        let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstInteger, element, true, value, token)
        if constant_error != ok { ret (0usize, constant_error) }
        let store_error = store_lane(c, element, element_info.size, stack, item * element_info.size, constant, builder, token)
        if store_error != ok { ret (0usize, store_error) }
        item += 1usize
    }
    ret (stack, ok)
}

fn lower_binding_member_expr(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: check.Type, builder: *nir.Builder) -> (usize, check.Type, bool, err) {
    let node = tree.nodes[node_index]
    let (bound, bound_member, is_bound) = check.comptime_binding_base(c, g.modules[module_index].text, tree, node)
    if !is_bound { ret (0usize, check.invalid_type(), false, ok) }
    let (result_type, type_error) = check.check_expr(c, g, tree, module_index, node_index, expected)
    if type_error != ok { ret (0usize, result_type, true, type_error) }
    let (value, value_error) = lower_comptime_binding_member(c, bound, bound_member, result_type, builder, c.tokens[usize(node.token_start)])
    ret (value, result_type, true, value_error)
}

fn lower_unrolled_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, sequence: check.MetaSequence, name: str, body_index: usize, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    let aggregate = c.aggregates[sequence.aggregate_index]
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let (argument, present) = check.meta_sequence_binding(c, sequence, field_at)
        if present {
            let depth = c.comptime_binding_count
            if name.len != 0usize {
                let push_error = check.push_comptime_binding(c, name, argument)
                if push_error != ok { ret push_error }
            }
            let body_bindings = *binding_count
            // No loop survives, so there is no target for a `break`. The checker does
            // not raise `loop_depth` for an unrolled `for` either, so one in the body
            // is already rejected there as having no enclosing loop.
            var control: LoopControl = zero
            let body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
            *binding_count = body_bindings
            c.comptime_binding_count = depth
            check.begin_call_scope(c)
            if body_error != ok { ret body_error }
        }
        field_at += 1usize
    }
    ret ok
}

// A member of a comptime `Field` or `Member`, as the constant it was all along. The
// offset and size are target layout, which is why the checker kept the aggregate and
// the field index rather than the answers.
fn lower_comptime_binding_member(c: *check.Checker, argument: check.GenericArgument, member: str, result_type: check.Type, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    if check.same(member, "name") {
        let (name_index, intern_error) = nir.intern_string(builder, quoted_text(c, argument.text))
        if intern_error != ok { ret (0usize, intern_error) }
        let (instruction, value, emit_error) = nir.emit(builder, .ConstString, result_type, true, name_index, token)
        if emit_error != ok { ret (0usize, emit_error) }
        ret (value, ok)
    }
    var constant = argument.value
    if argument.kind == .Field {
        let owner = c.aggregates[argument.owner]
        if argument.value >= owner.field_count { ret (0usize, check.InvalidType) }
        let entry = c.aggregate_fields[owner.first_field + argument.value]
        if check.same(member, "size") {
            let (info, info_error) = layout.type_info(c, entry.ty)
            if info_error != ok { ret (0usize, info_error) }
            constant = info.size
        } else {
            let (offset, offset_error) = comptime_field_offset(c, argument)
            if offset_error != ok { ret (0usize, offset_error) }
            constant = offset
        }
    }
    let (instruction, value, emit_error) = nir.emit(builder, .ConstInteger, result_type, true, constant, token)
    if emit_error != ok { ret (0usize, emit_error) }
    ret (value, ok)
}

// Where the field sits in the aggregate it came from. Walked here rather than through
// `layout.field` by name, because a tagged union's payloads share an offset and the
// name lookup would be doing the same walk anyway.
fn comptime_field_offset(c: *check.Checker, argument: check.GenericArgument) -> (usize, err) {
    let owner = c.aggregates[argument.owner]
    if argument.value >= owner.field_count { ret (0usize, check.InvalidType) }
    let entry = c.aggregate_fields[owner.first_field + argument.value]
    var subject = check.make_type(.Named, owner.name, owner.module_index)
    subject.element = argument.owner
    subject.has_element = true
    let (field, field_error) = layout.field(c, subject, entry.name)
    if field_error != ok { ret (0usize, field_error) }
    ret (field.offset, ok)
}

// Section 9: `get` and `set` each compile to one field load or store at the offset
// `FIELD` names, which is why they may run at runtime while `fields` may not.
fn emit_meta_access(c: *check.Checker, call: check.CallInfo, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    results.call = call
    results.count = call.function.return_count
    if argument_count == 0usize { ret check.ArgumentCount }
    let (offset, offset_error) = comptime_field_offset(c, call.meta_field)
    if offset_error != ok { ret offset_error }
    let field_type = call.meta_field.ty
    let (info, info_error) = layout.type_info(c, field_type)
    if info_error != ok { ret info_error }
    let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, field_type, true, offset, token)
    if address_error != ok { ret address_error }
    let address_operand_error = nir.add_operand(builder, address_instruction, arguments[0usize])
    if address_operand_error != ok { ret address_operand_error }
    if call.meta_writes {
        if argument_count != 2usize { ret check.ArgumentCount }
        if aggregate_value(c, field_type) {
            let (copy_instruction, copy_ignored, copy_error) = nir.emit(builder, .Copy, field_type, false, info.size, token)
            if copy_error != ok { ret copy_error }
            try nir.add_operand(builder, copy_instruction, address)
            try nir.add_operand(builder, copy_instruction, arguments[1usize])
            ret ok
        }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, field_type, false, info.size, token)
        if store_error != ok { ret store_error }
        try nir.add_operand(builder, store_instruction, address)
        try nir.add_operand(builder, store_instruction, arguments[1usize])
        ret ok
    }
    // An aggregate field is read as a place, exactly as `v.x` is.
    if aggregate_value(c, field_type) {
        results.values[0usize] = address
        results.addresses[0usize] = true
        ret ok
    }
    let (load_instruction, value, load_error) = nir.emit(builder, .Load, field_type, true, info.size, token)
    if load_error != ok { ret load_error }
    let load_operand_error = nir.add_operand(builder, load_instruction, address)
    if load_operand_error != ok { ret load_operand_error }
    results.values[0usize] = value
    ret ok
}

fn lower_for(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, defers: *DeferState) -> err {
    var names: [2]lex.Token = zero
    var name_count = 0usize
    var token_at = usize(node.token_start) + 1usize
    while token_at < usize(node.token_end) && c.tokens[token_at].kind != .KwIn {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if name_count == names.len { ret check.ArgumentCount }
            names[name_count] = token
            name_count += 1usize
        }
        token_at += 1usize
    }
    if name_count == 0usize || token_at == usize(node.token_end) { ret parse.InvalidSyntax }
    var expressions: [2]usize = zero
    var expression_count = 0usize
    var body_index = 0usize
    var found_body = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind == .Block {
                if found_body { ret parse.InvalidSyntax }
                body_index = child_index
                found_body = true
            } else {
                if expression_count == expressions.len { ret check.ArgumentCount }
                expressions[expression_count] = child_index
                expression_count += 1usize
            }
        }
        at += 1usize
    }
    if !found_body || expression_count == 0usize { ret parse.InvalidSyntax }
    if expression_count == 1usize {
        let (sequence, sequence_error) = check.meta_sequence(c, g, tree, module_index, expressions[0usize])
        if sequence_error != ok { ret sequence_error }
        if sequence.kind != .None {
            if sequence.deferred { ret check.Unsupported }
            var binding_name = ""
            if names[0usize].kind == .Identifier { binding_name = g.modules[module_index].text[names[0usize].start..names[0usize].end] }
            ret lower_unrolled_for(c, g, tree, module_index, function, sequence, binding_name, body_index, builder, bindings, binding_count, defers)
        }
        let (iterable_type, iterable_type_error) = check.check_expr(c, g, tree, module_index, expressions[0usize], check.invalid_type())
        if iterable_type_error != ok { ret iterable_type_error }
        if iterable_type.kind != .Array && iterable_type.kind != .Slice && iterable_type.kind != .String {
            if name_count != 1usize { ret check.ArgumentCount }
            ret lower_protocol_for(c, g, tree, module_index, function, node, expressions[0usize], body_index, names[0usize], builder, bindings, binding_count, defers)
        }
    }
    let token = c.tokens[usize(node.token_start)]
    var counter_type = check.make_type(.Integer, "usize", module_index)
    var initial = 0usize
    var limit = 0usize
    var data = 0usize
    var element_type: check.Type = zero
    var stride = 0usize
    var collection = expression_count == 1usize
    if collection {
        if name_count > 2usize { ret check.ArgumentCount }
        try lower_iterable_parts(c, g, tree, module_index, expressions[0usize], builder, bindings, *binding_count, &data, &limit, &element_type, &stride)
        let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, counter_type, true, 0usize, token)
        if zero_error != ok { ret zero_error }
        initial = zero_value
    } else {
        if name_count != 1usize { ret check.ArgumentCount }
        let (first_type, first_type_error) = check.check_expr(c, g, tree, module_index, expressions[0usize], check.invalid_type())
        if first_type_error != ok { ret first_type_error }
        var second_expected = first_type
        if check.is_untyped(first_type) { second_expected = check.invalid_type() }
        let (second_type, second_type_error) = check.check_expr(c, g, tree, module_index, expressions[1usize], second_expected)
        if second_type_error != ok { ret second_type_error }
        counter_type = first_type
        if check.is_untyped(first_type) { counter_type = second_type }
        let (first_value, lowered_first_type, first_error) = lower_expression(c, g, tree, module_index, expressions[0usize], counter_type, builder, bindings, *binding_count)
        if first_error != ok { ret first_error }
        let (second_value, lowered_second_type, second_error) = lower_expression(c, g, tree, module_index, expressions[1usize], counter_type, builder, bindings, *binding_count)
        if second_error != ok { ret second_error }
        initial = first_value
        limit = second_value
    }
    let (counter_stack_instruction, counter_stack, counter_stack_error) = nir.emit(builder, .Stack, counter_type, true, 0usize, token)
    if counter_stack_error != ok { ret counter_stack_error }
    let (counter_info, counter_info_error) = layout.type_info(c, counter_type)
    if counter_info_error != ok { ret counter_info_error }
    let (initial_store_instruction, initial_store_ignored, initial_store_error) = nir.emit(builder, .Store, counter_type, false, counter_info.size, token)
    if initial_store_error != ok { ret initial_store_error }
    try nir.add_operand(builder, initial_store_instruction, counter_stack)
    try nir.add_operand(builder, initial_store_instruction, initial)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }
    let condition_block = builder.block_count
    let (condition_block_index, condition_block_error) = nir.begin_block(builder)
    if condition_block_error != ok || condition_block_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_stack)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, has_next, compare_error) = nir.emit(builder, .Less, boolean, true, 0usize, token)
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, condition_counter)
    try nir.add_operand(builder, compare_instruction, limit)
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)
    let increment_block = builder.block_count
    let (increment_block_index, increment_block_error) = nir.begin_block(builder)
    if increment_block_error != ok || increment_block_index != increment_block { ret nir.InvalidControlFlow }
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_stack)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, counter_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, counter_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, counter_type, false, counter_info.size, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_stack)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)
    let body_block = builder.block_count
    let (body_block_index, body_block_error) = nir.begin_block(builder)
    if body_block_error != ok || body_block_index != body_block { ret nir.InvalidControlFlow }
    let (body_counter_instruction, body_counter, body_counter_error) = nir.emit(builder, .Load, counter_type, true, counter_info.size, token)
    if body_counter_error != ok { ret body_counter_error }
    try nir.add_operand(builder, body_counter_instruction, counter_stack)
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    if collection {
        var element_value = 0usize
        let (address_instruction, element_address, address_error) = nir.emit(builder, .IndexAddress, element_type, true, stride, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, data)
        try nir.add_operand(builder, address_instruction, body_counter)
        try nir.add_operand(builder, address_instruction, limit)
        var element_address_value = aggregate_value(c, element_type)
        element_value = element_address
        if !element_address_value {
            let (element_info, element_info_error) = layout.type_info(c, element_type)
            if element_info_error != ok { ret element_info_error }
            let (load_instruction, loaded_element, load_error) = nir.emit(builder, .Load, element_type, true, element_info.size, token)
            if load_error != ok { ret load_error }
            try nir.add_operand(builder, load_instruction, element_address)
            element_value = loaded_element
        }
        if name_count == 2usize { try bind_value(c, g, module_index, names[0usize], counter_type, body_counter, false, false, builder, bindings, binding_count) }
        try bind_value(c, g, module_index, names[name_count - 1usize], element_type, element_value, element_address_value, false, builder, bindings, binding_count)
    } else {
        try bind_value(c, g, module_index, names[0usize], counter_type, body_counter, false, false, builder, bindings, binding_count)
    }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: increment_block, break_defer_base: defers.count, continue_defer_base: defers.count, breaks: break_storage[..], break_count: 0usize }
    let body_error = lower_block(c, g, tree, module_index, function, tree.nodes[body_index], builder, bindings, binding_count, &control, defers)
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    if body_error != ok { ret body_error }
    if !builder.blocks[builder.current_block].terminated {
        let (body_edge, body_edge_error) = emit_branch(builder, token)
        if body_edge_error != ok { ret body_edge_error }
        try nir.set_branch_targets(builder, body_edge, increment_block, 0usize)
    }
    let exit_block = builder.block_count
    let (exit_block_index, exit_block_error) = nir.begin_block(builder)
    if exit_block_error != ok || exit_block_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    var break_at = 0usize
    while break_at < control.break_count {
        try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
        break_at += 1usize
    }
    ret ok
}

fn add_control_exit(control: *LoopControl, branch: usize) -> err {
    if control.break_count == control.breaks.len { ret check.Capacity }
    control.breaks[control.break_count] = branch
    control.break_count += 1usize
    ret ok
}

fn deferred_call_node(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    if node.kind != .CallStmt && node.kind != .BindingStmt { ret (0usize, false) }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind == .CallExpr { ret (child_index, true) }
        }
        at += 1usize
    }
    ret (0usize, false)
}

fn lower_defer(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState) -> err {
    if defers.count == defers.entries.len { ret check.Capacity }
    let (child_index, found_child) = check.first_node_child(tree, node)
    if !found_child { ret parse.InvalidSyntax }
    let child = tree.nodes[child_index]
    var entry: Deferred = zero
    entry.token = c.tokens[usize(node.token_start)]
    let (call_index, has_call) = deferred_call_node(tree, child)
    if has_call {
        entry.kind = .Call
        let arguments_error = lower_call_arguments(c, g, tree, module_index, tree.nodes[call_index], builder, bindings, binding_count, true, &entry.call, &entry.callee, entry.arguments[..], &entry.argument_count)
        if arguments_error != ok { ret arguments_error }
    } else {
        entry.node_index = child_index
        if child.kind == .Block { entry.kind = .Block } else { entry.kind = .Statement }
    }
    defers.entries[defers.count] = entry
    defers.count += 1usize
    ret ok
}

fn emit_deferred_from(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, builder: *nir.Builder, bindings: []Binding, binding_count: usize, defers: *DeferState, base: usize) -> err {
    if base > defers.count { ret nir.InvalidControlFlow }
    var at = defers.count
    while at > base {
        at = at - 1usize
        var entry = defers.entries[at]
        if entry.kind == .Call {
            var results: CallResults = zero
            try emit_call_results(c, entry.call, entry.callee, entry.arguments[..], entry.argument_count, builder, entry.token, &results)
        } else {
            let local_checkpoint = c.local_count
            var current_binding_count = binding_count
            var no_loop: LoopControl = zero
            if entry.kind == .Block {
                try lower_block(c, g, tree, module_index, function, tree.nodes[entry.node_index], builder, bindings, &current_binding_count, &no_loop, defers)
            } else {
                if entry.kind != .Statement { ret nir.InvalidControlFlow }
                try lower_statement(c, g, tree, module_index, function, tree.nodes[entry.node_index], builder, bindings, &current_binding_count, &no_loop, defers)
            }
            c.local_count = local_checkpoint
        }
    }
    ret ok
}

fn lower_switch_arm(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, arm: syntax.Node, subject: usize, subject_type: check.Type, aggregate_index: usize, has_aggregate: bool, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let defer_checkpoint = defers.count
    let (capture, has_capture) = check.switch_capture_name(c, g.modules[module_index].text, arm)
    if has_capture {
        if !has_aggregate || c.aggregates[aggregate_index].kind != .TaggedUnion { ret check.InvalidSwitch }
        var field_index = 0usize
        var found_field = false
        let arm_end = usize(arm.first_child) + usize(arm.child_count)
        var case_at = usize(arm.first_child)
        while case_at < arm_end {
            if parse.child_is_node_at(tree, case_at) {
                let case_index = parse.child_index_at(tree, case_at)
                if !check.check_statement_kind(tree.nodes[case_index].kind) {
                    let (key, candidate, has_candidate, key_error) = check.switch_case_key(c, g, tree, module_index, case_index, subject_type, aggregate_index, true)
                    if key_error != ok { ret key_error }
                    field_index = candidate
                    found_field = has_candidate
                    break
                }
            }
            case_at += 1usize
        }
        if !found_field || field_index >= c.aggregate_field_count { ret check.InvalidSwitch }
        let field = c.aggregate_fields[field_index]
        let (payload, payload_error) = layout.field(c, subject_type, field.name)
        if payload_error != ok { ret payload_error }
        let token = c.tokens[usize(arm.token_start)]
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, field.ty, true, payload.offset, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, subject)
        var value = address
        var address_value = aggregate_value(c, field.ty)
        if !address_value {
            let (info, info_error) = layout.type_info(c, field.ty)
            if info_error != ok { ret info_error }
            let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, field.ty, true, info.size, token)
            if load_error != ok { ret load_error }
            try nir.add_operand(builder, load_instruction, address)
            value = loaded
        }
        var capture_token = token
        var token_at = usize(arm.token_start)
        while token_at < usize(arm.token_end) {
            if c.tokens[token_at].kind == .Identifier && check.same(g.modules[module_index].text[c.tokens[token_at].start..c.tokens[token_at].end], capture) { capture_token = c.tokens[token_at] }
            token_at += 1usize
        }
        try bind_value(c, g, module_index, capture_token, field.ty, value, address_value, false, builder, bindings, binding_count)
    }
    let end = usize(arm.first_child) + usize(arm.child_count)
    var at = usize(arm.first_child)
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if parse.child_is_node_at(tree, at) {
            let statement = tree.nodes[parse.child_index_at(tree, at)]
            if check.check_statement_kind(statement.kind) { try lower_statement(c, g, tree, module_index, function, statement, builder, bindings, binding_count, control, defers) }
        }
        at += 1usize
    }
    if !builder.blocks[builder.current_block].terminated { try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, defer_checkpoint) }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    defers.count = defer_checkpoint
    ret ok
}

fn lower_switch(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, outer_control: *LoopControl, defers: *DeferState) -> err {
    var subject_index = 0usize
    var has_subject = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind != .SwitchArm {
                subject_index = child_index
                has_subject = true
                break
            }
        }
        at += 1usize
    }
    if !has_subject { ret parse.InvalidSyntax }
    let (subject_type, subject_type_error) = check.check_expr(c, g, tree, module_index, subject_index, check.invalid_type())
    if subject_type_error != ok { ret subject_type_error }
    let (subject, lowered_subject_type, subject_error) = lower_expression(c, g, tree, module_index, subject_index, subject_type, builder, bindings, *binding_count)
    if subject_error != ok { ret subject_error }
    let (aggregate_index, has_aggregate) = layout.aggregate_index(c, subject_type)
    var compared = subject
    var compare_type = subject_type
    if has_aggregate && c.aggregates[aggregate_index].kind == .TaggedUnion {
        let (tag, tag_error) = layout.field(c, subject_type, "tag")
        if tag_error != ok { ret tag_error }
        let token = c.tokens[usize(node.token_start)]
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, tag.ty, true, tag.offset, token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, subject)
        let (tag_info, tag_info_error) = layout.type_info(c, tag.ty)
        if tag_info_error != ok { ret tag_info_error }
        let (load_instruction, loaded, load_error) = nir.emit(builder, .Load, tag.ty, true, tag_info.size, token)
        if load_error != ok { ret load_error }
        try nir.add_operand(builder, load_instruction, address)
        compared = loaded
        compare_type = tag.ty
    }
    var break_storage: [256]usize = zero
    var control = LoopControl { active: true, continue_target: outer_control.continue_target, break_defer_base: defers.count, continue_defer_base: outer_control.continue_defer_base, breaks: break_storage[..], break_count: 0usize }
    var default_arm: syntax.Node = zero
    var has_default = false
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let arm = tree.nodes[parse.child_index_at(tree, at)]
            if arm.kind == .SwitchArm {
                if c.tokens[usize(arm.token_start)].kind == .KwDefault {
                    default_arm = arm
                    has_default = true
                } else {
                    var match = 0usize
                    var has_match = false
                    let arm_end = usize(arm.first_child) + usize(arm.child_count)
                    var case_at = usize(arm.first_child)
                    while case_at < arm_end {
                        if parse.child_is_node_at(tree, case_at) {
                            let case_index = parse.child_index_at(tree, case_at)
                            if !check.check_statement_kind(tree.nodes[case_index].kind) {
                                var case_value = 0usize
                                if has_aggregate && c.aggregates[aggregate_index].kind == .TaggedUnion {
                                    let (key, field_index, has_field, key_error) = check.switch_case_key(c, g, tree, module_index, case_index, subject_type, aggregate_index, true)
                                    if key_error != ok || !has_field || field_index >= c.aggregate_field_count { ret check.InvalidSwitch }
                                    let field = c.aggregate_fields[field_index]
                                    let (case_bits, case_bits_error) = check.enum_member_bits(c.aggregates[aggregate_index].backing_type, field.enum_value, field.enum_negative)
                                    if case_bits_error != ok { ret case_bits_error }
                                    let (case_instruction, value, case_error) = nir.emit(builder, .ConstInteger, compare_type, true, case_bits, c.tokens[usize(arm.token_start)])
                                    if case_error != ok { ret case_error }
                                    case_value = value
                                } else {
                                    let (value, value_type, value_error) = lower_expression(c, g, tree, module_index, case_index, subject_type, builder, bindings, *binding_count)
                                    if value_error != ok { ret value_error }
                                    case_value = value
                                }
                                let boolean = check.make_type(.Bool, "bool", module_index)
                                let (equal_instruction, equal, equal_error) = nir.emit(builder, .Equal, boolean, true, 0usize, c.tokens[usize(arm.token_start)])
                                if equal_error != ok { ret equal_error }
                                try nir.add_operand(builder, equal_instruction, compared)
                                try nir.add_operand(builder, equal_instruction, case_value)
                                if has_match {
                                    let (or_instruction, combined, or_error) = nir.emit(builder, .BitOr, boolean, true, 0usize, c.tokens[usize(arm.token_start)])
                                    if or_error != ok { ret or_error }
                                    try nir.add_operand(builder, or_instruction, match)
                                    try nir.add_operand(builder, or_instruction, equal)
                                    match = combined
                                } else {
                                    match = equal
                                    has_match = true
                                }
                            }
                        }
                        case_at += 1usize
                    }
                    if !has_match { ret parse.InvalidSyntax }
                    let (decision, ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, c.tokens[usize(arm.token_start)])
                    if decision_error != ok { ret decision_error }
                    try nir.add_operand(builder, decision, match)
                    let body_block = builder.block_count
                    let (body_index, body_error) = nir.begin_block(builder)
                    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
                    try lower_switch_arm(c, g, tree, module_index, function, arm, subject, subject_type, aggregate_index, has_aggregate, builder, bindings, binding_count, &control, defers)
                    if !builder.blocks[builder.current_block].terminated {
                        let (exit_branch, exit_error) = emit_branch(builder, c.tokens[usize(arm.token_start)])
                        if exit_error != ok { ret exit_error }
                        try add_control_exit(&control, exit_branch)
                    }
                    let next_block = builder.block_count
                    let (next_index, next_error) = nir.begin_block(builder)
                    if next_error != ok || next_index != next_block { ret nir.InvalidControlFlow }
                    try nir.set_branch_targets(builder, decision, body_block, next_block)
                }
            }
        }
        at += 1usize
    }
    if has_default {
        try lower_switch_arm(c, g, tree, module_index, function, default_arm, subject, subject_type, aggregate_index, has_aggregate, builder, bindings, binding_count, &control, defers)
        if !builder.blocks[builder.current_block].terminated {
            let (exit_branch, exit_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
            if exit_error != ok { ret exit_error }
            try add_control_exit(&control, exit_branch)
        }
    } else {
        let (instruction, ignored, unreachable_error) = nir.emit(builder, .Unreachable, zero, false, 0usize, c.tokens[usize(node.token_start)])
        if unreachable_error != ok { ret unreachable_error }
    }
    if control.break_count != 0usize {
        let exit_block = builder.block_count
        let (exit_index, exit_error) = nir.begin_block(builder)
        if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
        var break_at = 0usize
        while break_at < control.break_count {
            try nir.set_branch_targets(builder, control.breaks[break_at], exit_block, 0usize)
            break_at += 1usize
        }
    }
    ret ok
}

fn lower_statement(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    c.failure_module = module_index
    c.failure_token = c.tokens[usize(node.token_start)]
    c.failure_has_token = true
    if node.kind == .ReturnStmt { ret lower_return(c, g, tree, module_index, function, node, builder, bindings, *binding_count, defers) }
    if node.kind == .TryStmt { ret lower_try(c, g, tree, module_index, function, node, builder, bindings, *binding_count, defers) }
    if node.kind == .BindingStmt { ret lower_binding(c, g, tree, module_index, node, builder, bindings, binding_count) }
    if node.kind == .AssignmentStmt { ret lower_assignment(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .CallStmt { ret lower_call_statement(c, g, tree, module_index, node, builder, bindings, *binding_count) }
    if node.kind == .IfStmt { ret lower_if(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    if node.kind == .WhenStmt { ret lower_when(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    if node.kind == .WhileStmt { ret lower_while(c, g, tree, module_index, function, node, builder, bindings, binding_count, defers) }
    if node.kind == .ForStmt { ret lower_for(c, g, tree, module_index, function, node, builder, bindings, binding_count, defers) }
    if node.kind == .SwitchStmt { ret lower_switch(c, g, tree, module_index, function, node, builder, bindings, binding_count, control, defers) }
    if node.kind == .DeferStmt { ret lower_defer(c, g, tree, module_index, node, builder, bindings, *binding_count, defers) }
    // `@nocheck { ... }` (section 11): the block's instructions carry the mark, and the
    // debug-only rows -- bounds, null, tag, overflow, narrow, shift -- are left out of
    // them. The rows that trap in release too are not touched by it.
    if node.kind == .NocheckStmt {
        let was_nocheck = builder.nocheck
        builder.nocheck = true
        var block_error: err = ok
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let child = tree.nodes[parse.child_index_at(tree, at)]
                if child.kind == .Block { block_error = lower_block(c, g, tree, module_index, function, child, builder, bindings, binding_count, control, defers) }
            }
            at += 1usize
        }
        builder.nocheck = was_nocheck
        ret block_error
    }
    if node.kind == .BreakStmt {
        if !control.active || control.break_count == control.breaks.len { ret check.Unsupported }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, control.break_defer_base)
        let (branch, branch_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if branch_error != ok { ret branch_error }
        control.breaks[control.break_count] = branch
        control.break_count += 1usize
        ret ok
    }
    if node.kind == .ContinueStmt {
        if !control.active { ret check.Unsupported }
        try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, control.continue_defer_base)
        let (branch, branch_error) = emit_branch(builder, c.tokens[usize(node.token_start)])
        if branch_error != ok { ret branch_error }
        ret nir.set_branch_targets(builder, branch, control.continue_target, 0usize)
    }
    ret check.Unsupported
}

fn lower_block(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: check.Function, node: syntax.Node, builder: *nir.Builder, bindings: []Binding, binding_count: *usize, control: *LoopControl, defers: *DeferState) -> err {
    if node.kind != .Block { ret parse.InvalidSyntax }
    let local_checkpoint = c.local_count
    let binding_checkpoint = *binding_count
    let defer_checkpoint = defers.count
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if builder.blocks[builder.current_block].terminated { break }
        if parse.child_is_node_at(tree, at) { try lower_statement(c, g, tree, module_index, function, tree.nodes[parse.child_index_at(tree, at)], builder, bindings, binding_count, control, defers) }
        at += 1usize
    }
    if !builder.blocks[builder.current_block].terminated { try emit_deferred_from(c, g, tree, module_index, function, builder, bindings, *binding_count, defers, defer_checkpoint) }
    c.local_count = local_checkpoint
    *binding_count = binding_checkpoint
    defers.count = defer_checkpoint
    ret ok
}

fn lower_function_index(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, defers: *DeferState) -> err {
    check.begin_call_scope(c)
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    c.failure_module = module_index
    c.failure_name = name
    c.failure_token = c.tokens[usize(node.token_start)]
    c.failure_has_token = true
    if function_index >= c.function_count { ret FunctionNotFound }
    let function = c.functions[function_index]
    if function.generic { ret check.Unsupported }
    let (nir_function, begin_error) = nir.begin_function(builder, function.owner_module_index, name, function.instance_id)
    if begin_error != ok { ret begin_error }
    builder.functions[nir_function].path = g.modules[function.module_index].path
    builder.functions[nir_function].module_name = g.modules[function.owner_module_index].name
    builder.current_path = g.modules[function.module_index].path
    builder.current_text = g.modules[function.module_index].text
    builder.current_lines = g.modules[function.module_index].lines
    builder.site_line = 0usize
    try nir.begin_signature(builder, nir_function, signatures)
    var signature_parameter_at = 0usize
    while signature_parameter_at < function.parameter_count {
        try nir.add_parameter_type(builder, nir_function, signatures, c.parameters[function.first_parameter + signature_parameter_at].ty)
        signature_parameter_at += 1usize
    }
    var signature_return_at = 0usize
    while signature_return_at < function.return_count {
        try nir.add_return_type(builder, nir_function, signatures, c.return_types[function.first_return + signature_return_at])
        signature_return_at += 1usize
    }
    let (entry, block_error) = nir.begin_block(builder)
    if block_error != ok { ret block_error }
    let local_checkpoint = c.local_count
    var binding_count = 0usize
    // The defer stack is the caller's, one per module sweep (D306): zeroing its 256
    // entries here cost every function more than lowering its body did.
    defers.count = 0usize
    var hidden_parameters = 0usize
    var function_call: check.CallInfo = zero
    function_call.function = function
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, function_call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    if return_layout.via_slot && function.return_count != 0usize {
        let pointer_type = check.make_type(.Pointer, "", module_index)
        let (return_parameter, return_slot, return_parameter_error) = nir.emit(builder, .Parameter, pointer_type, true, 0usize, c.tokens[usize(node.token_start)])
        if return_parameter_error != ok { ret return_parameter_error }
        try add_binding(bindings, &binding_count, Binding { name: "$return", ty: pointer_type, value: return_slot, address: false })
        hidden_parameters = 1usize
    }
    var parameter_at = 0usize
    while parameter_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_at]
        let (instruction, result, parameter_error) = nir.emit(builder, .Parameter, parameter.ty, true, parameter_at + hidden_parameters, c.tokens[usize(node.token_start)])
        if parameter_error != ok { ret parameter_error }
        try add_binding(bindings, &binding_count, Binding { name: parameter.name, ty: parameter.ty, value: result, address: aggregate_value(c, parameter.ty) })
        try check.add_local(c, parameter.name, parameter.ty, false)
        parameter_at += 1usize
    }
    var found_body = false
    var no_loop: LoopControl = zero
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .Block {
                found_body = true
                try lower_block(c, g, tree, module_index, function, child, builder, bindings, &binding_count, &no_loop, defers)
            }
        }
        at += 1usize
    }
    if !found_body { ret parse.InvalidSyntax }
    if !builder.blocks[builder.current_block].terminated {
        if function.return_count != 0usize { ret check.MissingReturn }
        let (instruction, ignored, return_error) = nir.emit(builder, .Return, zero, false, 0usize, c.tokens[usize(node.token_start)])
        if return_error != ok { ret return_error }
    }
    let end_error = nir.end_function(builder)
    c.local_count = local_checkpoint
    ret end_error
}

fn lower_declaration(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, defers: *DeferState) -> err {
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = check.find_function(c, module_index, name)
    if !found { ret FunctionNotFound }
    if c.functions[function_index].generic { ret ok }
    ret lower_function_index(c, g, tree, module_index, node, function_index, builder, signatures, bindings, defers)
}

fn lower_instance(c: *check.Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, instance_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, defers: *DeferState) -> err {
    check.begin_call_scope(c)
    if instance_index >= c.function_count { ret FunctionNotFound }
    let instance = c.functions[instance_index]
    let instance_generic = c.function_generics[instance_index]
    if !instance_generic.instance || instance_generic.template_index >= c.signature_function_count || instance.generic { ret check.Unsupported }
    let template = c.functions[instance_generic.template_index]
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
            if name_error != ok { ret name_error }
            if check.same(name, template.name) {
                let template_generic = c.function_generics[instance_generic.template_index]
                c.active_first_comptime = template_generic.first_comptime
                c.active_comptime_count = template_generic.comptime_count
                c.active_first_argument = instance_generic.first_argument
                c.active_arguments = true
                let lower_error = lower_function_index(c, g, tree, module_index, node, instance_index, builder, signatures, bindings, defers)
                c.active_first_comptime = 0usize
                c.active_comptime_count = 0usize
                c.active_first_argument = 0usize
                c.active_arguments = false
                ret lower_error
            }
        }
        node_index += 1usize
    }
    ret FunctionNotFound
}

fn pending_instance(c: *check.Checker, owner_module_index: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let generic = c.function_generics[at]
        if generic.instance && !generic.formatter && !generic.lowered && !c.functions[at].generic && c.functions[at].owner_module_index == owner_module_index { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A call into `e.str` from generated code: the callee is found by name, the arguments
// are values already lowered, and `emit_call_results` does the rest -- including the
// hidden slot a `(Builder, err)` return needs.
fn emit_library_call(c: *check.Checker, g: *graph.Graph, module_name: str, name: str, arguments: []usize, argument_count: usize, builder: *nir.Builder, token: lex.Token, results: *CallResults) -> err {
    let (target_module, found_module) = graph.find_module(g, module_name)
    if !found_module { ret FunctionNotFound }
    let (function_index, found_function) = check.find_function(c, target_module, name)
    if !found_function { ret FunctionNotFound }
    var call: check.CallInfo = zero
    call.cast = check.invalid_type()
    call.alloc_return = check.invalid_type()
    call.alloc_arena = check.invalid_type()
    call.function = c.functions[function_index]
    ret emit_call_results(c, call, 0usize, arguments, argument_count, builder, token, results)
}

// The one place a generated formatter returns. `printf` returns `err` in a register;
// `format` returns `(str, err)`, which is wider than a register pair, so it goes
// through the same hidden slot `lower_return` writes for a source-level `ret`.
fn emit_formatter_return(c: *check.Checker, module_index: usize, instance: check.Function, return_slot: usize, text: usize, failure: usize, arena_form: bool, builder: *nir.Builder, token: lex.Token) -> err {
    let error_type = check.make_type(.Err, "err", module_index)
    if !arena_form {
        let (instruction, ignored, emit_error) = nir.emit(builder, .Return, error_type, false, 0usize, token)
        if emit_error != ok { ret emit_error }
        ret nir.add_operand(builder, instruction, failure)
    }
    var call: check.CallInfo = zero
    call.function = instance
    var return_layout: ReturnLayout = zero
    let layout_error = call_return_layout(c, call, &return_layout)
    if layout_error != ok || !return_layout.via_slot { ret check.InvalidReturn }
    var values: [2]usize = zero
    values[0usize] = text
    values[1usize] = failure
    var result_at = 0usize
    while result_at < 2usize {
        let result_type = c.return_types[instance.first_return + result_at]
        let (info, info_error) = layout.type_info(c, result_type)
        if info_error != ok { ret info_error }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, result_type, true, return_layout.offsets[result_at], token)
        if address_error != ok { ret address_error }
        try nir.add_operand(builder, address_instruction, return_slot)
        var opcode: nir.Opcode = .Store
        if aggregate_value(c, result_type) { opcode = .Copy }
        let (move_instruction, move_ignored, move_error) = nir.emit(builder, opcode, result_type, false, info.size, token)
        if move_error != ok { ret move_error }
        try nir.add_operand(builder, move_instruction, address)
        try nir.add_operand(builder, move_instruction, values[result_at])
        result_at += 1usize
    }
    let (instruction, ignored, emit_error) = nir.emit(builder, .Return, zero, false, 0usize, token)
    ret emit_error
}

// The error check every fallible step in an expansion carries. It is the shape `try`
// lowers to, except that the early exit returns rather than propagates: an expansion
// has no caller frame of its own to hand the error back through.
fn emit_formatter_guard(c: *check.Checker, module_index: usize, instance: check.Function, return_slot: usize, failure: usize, arena_form: bool, builder: *nir.Builder, token: lex.Token) -> err {
    let error_type = check.make_type(.Err, "err", module_index)
    let (ok_instruction, ok_value, ok_error) = nir.emit(builder, .ConstError, error_type, true, 0usize, token)
    if ok_error != ok { ret ok_error }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, failed, compare_error) = nir.emit(builder, .NotEqual, boolean, true, 0usize, token)
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, failure)
    try nir.add_operand(builder, compare_instruction, ok_value)
    let failure_block = builder.block_count
    let (branch_instruction, branch_ignored, branch_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if branch_error != ok { ret branch_error }
    try nir.add_operand(builder, branch_instruction, failed)
    let (failure_index, failure_block_error) = nir.begin_block(builder)
    if failure_block_error != ok || failure_index != failure_block { ret nir.InvalidControlFlow }
    var text = 0usize
    if arena_form {
        let text_type = check.make_type(.String, "str", module_index)
        let (empty_index, empty_intern_error) = nir.intern_string(builder, "\"\"")
        if empty_intern_error != ok { ret empty_intern_error }
        let (empty_instruction, empty_value, empty_error) = nir.emit(builder, .ConstString, text_type, true, empty_index, token)
        if empty_error != ok { ret empty_error }
        text = empty_value
    }
    try emit_formatter_return(c, module_index, instance, return_slot, text, failure, arena_form, builder, token)
    let continue_block = builder.block_count
    try nir.set_branch_targets(builder, branch_instruction, failure_block, continue_block)
    let (continue_index, continue_block_error) = nir.begin_block(builder)
    if continue_block_error != ok || continue_index != continue_block { ret nir.InvalidControlFlow }
    ret ok
}

// Which push a verb expands to. Section 4: `{}` is the push of the argument's own
// type, `{x}` and `{b}` take the 32- or 64-bit form, and `{.N}` is the fixed float
// push. Widening to reach one is inside the formatter, not a source-level conversion,
// so section 6's list of implicit operations stays complete.
fn formatter_push_name(c: *check.Checker, ty: check.Type, verb: check.FormatVerb) -> (str, err) {
    let (canonical, canonical_error) = check.canonical_type(c, ty)
    if canonical_error != ok { ret ("", canonical_error) }
    if verb == .Hex || verb == .Binary {
        if canonical.kind != .Integer { ret ("", check.InvalidFormat) }
        let wide = check.integer_width(canonical) == 64usize
        if verb == .Hex {
            if wide { ret ("push_hex_u64", ok) }
            ret ("push_hex_u32", ok)
        }
        if wide { ret ("push_bin_u64", ok) }
        ret ("push_bin_u32", ok)
    }
    if verb == .Fixed {
        if check.same(canonical.name, "f32") { ret ("push_f32_fixed", ok) }
        if check.same(canonical.name, "f64") { ret ("push_f64_fixed", ok) }
        ret ("", check.InvalidFormat)
    }
    // `err` is the one verb whose push is generated rather than exported, so the name
    // is right but the call has to find this module's instance of it.
    if canonical.kind == .Err { ret ("push_err", ok) }
    if canonical.kind == .Bool { ret ("push_bool", ok) }
    if canonical.kind == .String { ret ("push", ok) }
    if canonical.kind == .Integer {
        if check.same(canonical.name, "i8") { ret ("push_i8", ok) }
        if check.same(canonical.name, "i16") { ret ("push_i16", ok) }
        if check.same(canonical.name, "i32") { ret ("push_i32", ok) }
        if check.same(canonical.name, "i64") { ret ("push_i64", ok) }
        if check.same(canonical.name, "isize") { ret ("push_isize", ok) }
        if check.same(canonical.name, "u8") { ret ("push_u8", ok) }
        if check.same(canonical.name, "u16") { ret ("push_u16", ok) }
        if check.same(canonical.name, "u32") { ret ("push_u32", ok) }
        if check.same(canonical.name, "u64") { ret ("push_u64", ok) }
        if check.same(canonical.name, "usize") { ret ("push_usize", ok) }
        ret ("", check.InvalidFormat)
    }
    if canonical.kind == .Float {
        if check.same(canonical.name, "f32") { ret ("push_f32", ok) }
        if check.same(canonical.name, "f64") { ret ("push_f64", ok) }
        ret ("", check.InvalidFormat)
    }
    // Slices, arrays, enums and a type's own `format` go through
    // `emit_formatter_value`'s own emitters; what reaches here has no push at all.
    ret ("", check.Unsupported)
}

// One literal byte of the format string. Text is pushed a byte at a time rather than
// as a string constant, because a run between two verbs is a slice of the *decoded*
// text and interning wants a spelling to re-encode from. A call per byte is the cost;
// a constant per run is the upgrade, and needs an arena lowering does not have.
fn emit_formatter_byte(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, handle: usize, byte: u8, arena_form: bool, builder: *nir.Builder, token: lex.Token) -> err {
    var arguments: [2]usize = zero
    var results: CallResults = zero
    let byte_type = check.make_type(.Integer, "u8", module_index)
    let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstInteger, byte_type, true, usize(byte), token)
    if constant_error != ok { ret constant_error }
    arguments[0usize] = handle
    arguments[1usize] = constant
    try emit_library_call(c, g, "e.str", "push_byte", arguments[..], 2usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    ret emit_formatter_guard(c, module_index, instance, return_slot, results.values[0usize], arena_form, builder, token)
}

// The expansion itself: open a builder, push a piece at a time, and hand back what
// `done` built. Verbs and text are interleaved in one scan of the decoded string, so
// a verb's argument is pushed at exactly the position the format string names it.
// The scan: text and verbs interleaved in one pass over the decoded format string, so
// a verb's argument is pushed at exactly the position the string names it. Both
// expansions share it; they differ only in the builder they open and what they do
// with what `done` leaves.
fn lower_formatter_pieces(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, spelling: str, parameters: []usize, first_verb: usize, handle: usize, arena_form: bool, builder: *nir.Builder, token: lex.Token) -> err {
    var raw = false
    let (body, body_error) = check.literal_contents(spelling, &raw)
    if body_error != ok { ret body_error }
    var verb_index = 0usize
    var at = 0usize
    var next = 0usize
    while at < body.len {
        let (byte, byte_error) = check.literal_byte(body, at, raw, &next)
        if byte_error != ok { ret byte_error }
        at = next
        if byte != 123u8 {
            // A `}` reaching here is the first of the `}}` the checker required.
            if byte == 125u8 {
                let (closer, closer_error) = check.literal_byte(body, at, raw, &next)
                if closer_error != ok { ret closer_error }
                at = next
            }
            let text_error = emit_formatter_byte(c, g, module_index, instance, return_slot, handle, byte, arena_form, builder, token)
            if text_error != ok { ret text_error }
            continue
        }
        let (following, following_error) = check.literal_byte(body, at, raw, &next)
        if following_error != ok { ret following_error }
        if following == 123u8 {
            at = next
            let brace_error = emit_formatter_byte(c, g, module_index, instance, return_slot, handle, 123u8, arena_form, builder, token)
            if brace_error != ok { ret brace_error }
            continue
        }
        while at < body.len {
            let (scan, scan_error) = check.literal_byte(body, at, raw, &next)
            if scan_error != ok { ret scan_error }
            at = next
            if scan == 125u8 { break }
        }
        let (verb, precision, verb_error) = check.format_verb_at(spelling, verb_index)
        if verb_error != ok { ret verb_error }
        let parameter_index = first_verb + verb_index
        if parameter_index >= instance.parameter_count { ret check.ArgumentCount }
        let argument_type = c.parameters[instance.first_parameter + parameter_index].ty
        try emit_formatter_value(c, g, module_index, instance, return_slot, handle, parameters[parameter_index], argument_type, verb, precision, arena_form, builder, token, 0usize)
        verb_index += 1usize
    }
    ret ok
}

// One value into the builder: a scalar, `str`, bool or `err` by its `e.str` push; an
// array or slice as `[` elements `]` with `, ` between, each element through this
// function again, so a slice of slices nests; a `str` is text and not a sequence.
fn emit_formatter_value(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, handle: usize, value: usize, ty: check.Type, verb: check.FormatVerb, precision: u8, arena_form: bool, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    if depth > 8usize { ret check.Unsupported }
    let (canonical, canonical_error) = check.canonical_type(c, ty)
    if canonical_error != ok { ret canonical_error }
    let (vector_lanes, is_vector) = check.vector_lanes(c, canonical)
    if (canonical.kind == .Slice || canonical.kind == .Array) && !is_vector {
        ret emit_formatter_sequence(c, g, module_index, instance, return_slot, handle, value, canonical, verb, precision, arena_form, builder, token, depth)
    }
    let (aggregate_index, is_aggregate) = layout.aggregate_index(c, canonical)
    if is_aggregate && c.aggregates[aggregate_index].kind == .Enum && verb != .Hex && verb != .Binary {
        ret emit_formatter_enum(c, g, module_index, instance, return_slot, handle, value, canonical, aggregate_index, arena_form, builder, token)
    }
    // A type's own `format`: one call with the builder, the way `emit_declared_cmp`
    // calls a declared `cmp`, its `err` guarded like a push's.
    let (format_index, has_format) = check.element_format_function(c, canonical)
    if has_format && verb == .Default {
        let function = c.functions[format_index]
        let (function_ref, reference_error) = nir.intern_function(builder, function.owner_module_index, function.name, function.instance_id)
        if reference_error != ok { ret reference_error }
        let err_type = check.make_type(.Err, "err", module_index)
        let (call_instruction, call_result, call_error) = nir.emit(builder, .Call, err_type, true, function_ref, token)
        if call_error != ok { ret call_error }
        try nir.add_operand(builder, call_instruction, value)
        try nir.add_operand(builder, call_instruction, handle)
        ret emit_formatter_guard(c, module_index, instance, return_slot, call_result, arena_form, builder, token)
    }
    var arguments: [4]usize = zero
    var results: CallResults = zero
    let (push_name, push_name_error) = formatter_push_name(c, canonical, verb)
    if push_name_error != ok { ret push_name_error }
    arguments[0usize] = handle
    arguments[1usize] = value
    var argument_count = 2usize
    if verb == .Fixed {
        let precision_type = check.make_type(.Integer, "u8", module_index)
        let (precision_instruction, precision_value, precision_error) = nir.emit(builder, .ConstInteger, precision_type, true, usize(precision), token)
        if precision_error != ok { ret precision_error }
        arguments[2usize] = precision_value
        argument_count = 3usize
    }
    if check.same(push_name, "push_err") {
        // `push_err` has no exported body: what exists is one generated instance
        // per module, so the call goes to this module's rather than to `e.str`'s.
        let (str_module, found_str) = graph.find_module(g, "e.str")
        if !found_str { ret FunctionNotFound }
        let (push_err_index, push_err_error) = check.error_push_instance(c, module_index, str_module)
        if push_err_error != ok { ret push_err_error }
        var push_err_call: check.CallInfo = zero
        push_err_call.cast = check.invalid_type()
        push_err_call.alloc_return = check.invalid_type()
        push_err_call.alloc_arena = check.invalid_type()
        push_err_call.function = c.functions[push_err_index]
        try emit_call_results(c, push_err_call, 0usize, arguments[..], argument_count, builder, token, &results)
    } else {
        try emit_library_call(c, g, "e.str", push_name, arguments[..], argument_count, builder, token, &results)
    }
    if results.count != 1usize { ret check.ArgumentCount }
    ret emit_formatter_guard(c, module_index, instance, return_slot, results.values[0usize], arena_form, builder, token)
}

// An enum by its variant's name: one comparison per variant, the match pushing the
// name a byte at a time and leaving; a value no variant declares pushes nothing.
fn emit_formatter_enum(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, handle: usize, value: usize, ty: check.Type, aggregate_index: usize, arena_form: bool, builder: *nir.Builder, token: lex.Token) -> err {
    let aggregate = c.aggregates[aggregate_index]
    let boolean = check.make_type(.Bool, "bool", module_index)
    var exits: [256]usize = zero
    var exit_count = 0usize
    var field_at = aggregate.first_field
    let field_end = aggregate.first_field + aggregate.field_count
    while field_at < field_end {
        let member = c.aggregate_fields[field_at]
        let (member_bits, member_bits_error) = check.enum_member_bits(aggregate.backing_type, member.enum_value, member.enum_negative)
        if member_bits_error != ok { ret member_bits_error }
        let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstInteger, ty, true, member_bits, token)
        if constant_error != ok { ret constant_error }
        let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, value, constant, token)
        if matches_error != ok { ret matches_error }
        let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
        if decision_error != ok { ret decision_error }
        try nir.add_operand(builder, decision, matches)
        let name_block = builder.block_count
        let (name_index, name_error) = nir.begin_block(builder)
        if name_error != ok || name_index != name_block { ret nir.InvalidControlFlow }
        var at = 0usize
        while at < member.name.len {
            try emit_formatter_byte(c, g, module_index, instance, return_slot, handle, member.name[at], arena_form, builder, token)
            at += 1usize
        }
        if exit_count == exits.len { ret check.Capacity }
        let (leave, leave_error) = emit_branch(builder, token)
        if leave_error != ok { ret leave_error }
        exits[exit_count] = leave
        exit_count += 1usize
        let next_block = builder.block_count
        let (next_index, next_error) = nir.begin_block(builder)
        if next_error != ok || next_index != next_block { ret nir.InvalidControlFlow }
        try nir.set_branch_targets(builder, decision, name_block, next_block)
        field_at += 1usize
    }
    // The block after the last comparison is where every name's branch lands too.
    let (join, join_error) = emit_branch(builder, token)
    if join_error != ok { ret join_error }
    let exit_block = builder.block_count
    let (exit_index, exit_error) = nir.begin_block(builder)
    if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, join, exit_block, 0usize)
    var i = 0usize
    while i < exit_count {
        try nir.set_branch_targets(builder, exits[i], exit_block, 0usize)
        i += 1usize
    }
    ret ok
}

// A sequence in index order, the loop in the shape `emit_sequence_cmp` uses: a
// counter on the stack, a condition block, a body that pushes `, ` after the first
// element and the element itself, and the exit block that closes the bracket.
fn emit_formatter_sequence(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, handle: usize, value: usize, ty: check.Type, verb: check.FormatVerb, precision: u8, arena_form: bool, builder: *nir.Builder, token: lex.Token, depth: usize) -> err {
    let (element_type, element_type_error) = check.index_element_type(c, ty, ty.module_index)
    if element_type_error != ok { ret element_type_error }
    let (element_info, element_info_error) = layout.type_info(c, element_type)
    if element_info_error != ok { ret element_info_error }
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let boolean = check.make_type(.Bool, "bool", module_index)
    try emit_formatter_byte(c, g, module_index, instance, return_slot, handle, 91u8, arena_form, builder, token)
    let (data, length, parts_error) = sequence_parts(c, ty, value, builder, token)
    if parts_error != ok { ret parts_error }
    let (counter_slot_instruction, counter_slot, counter_slot_error) = nir.emit(builder, .Stack, usize_type, true, 0usize, token)
    if counter_slot_error != ok { ret counter_slot_error }
    let (start_instruction, start, start_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if start_error != ok { ret start_error }
    let (start_store_instruction, start_store_ignored, start_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if start_store_error != ok { ret start_store_error }
    try nir.add_operand(builder, start_store_instruction, counter_slot)
    try nir.add_operand(builder, start_store_instruction, start)
    let (entry_branch, entry_branch_error) = emit_branch(builder, token)
    if entry_branch_error != ok { ret entry_branch_error }

    let condition_block = builder.block_count
    let (condition_index, condition_error) = nir.begin_block(builder)
    if condition_error != ok || condition_index != condition_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, entry_branch, condition_block, 0usize)
    let (condition_load_instruction, condition_counter, condition_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if condition_load_error != ok { ret condition_load_error }
    try nir.add_operand(builder, condition_load_instruction, counter_slot)
    let (has_next, has_next_error) = emit_supplied_compare(builder, .Less, boolean, condition_counter, length, token)
    if has_next_error != ok { ret has_next_error }
    let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if decision_error != ok { ret decision_error }
    try nir.add_operand(builder, decision, has_next)

    // The body: the separator after the first element, then the element.
    let body_block = builder.block_count
    let (body_index, body_error) = nir.begin_block(builder)
    if body_error != ok || body_index != body_block { ret nir.InvalidControlFlow }
    let (first_load_instruction, first_counter, first_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if first_load_error != ok { ret first_load_error }
    try nir.add_operand(builder, first_load_instruction, counter_slot)
    let (zero_instruction, zero_value, zero_error) = nir.emit(builder, .ConstInteger, usize_type, true, 0usize, token)
    if zero_error != ok { ret zero_error }
    let (is_later, is_later_error) = emit_supplied_compare(builder, .Greater, boolean, first_counter, zero_value, token)
    if is_later_error != ok { ret is_later_error }
    let (separator_decision, separator_ignored, separator_decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if separator_decision_error != ok { ret separator_decision_error }
    try nir.add_operand(builder, separator_decision, is_later)
    let separator_block = builder.block_count
    let (separator_index, separator_error) = nir.begin_block(builder)
    if separator_error != ok || separator_index != separator_block { ret nir.InvalidControlFlow }
    try emit_formatter_byte(c, g, module_index, instance, return_slot, handle, 44u8, arena_form, builder, token)
    try emit_formatter_byte(c, g, module_index, instance, return_slot, handle, 32u8, arena_form, builder, token)
    let (separator_branch, separator_branch_error) = emit_branch(builder, token)
    if separator_branch_error != ok { ret separator_branch_error }
    let element_block = builder.block_count
    let (element_index, element_block_error) = nir.begin_block(builder)
    if element_block_error != ok || element_index != element_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, separator_decision, separator_block, element_block)
    try nir.set_branch_targets(builder, separator_branch, element_block, 0usize)
    let (element_load_instruction, element_counter, element_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if element_load_error != ok { ret element_load_error }
    try nir.add_operand(builder, element_load_instruction, counter_slot)
    let (element, element_error) = element_operand(c, element_type, element_info.size, data, element_counter, length, builder, token)
    if element_error != ok { ret element_error }
    try emit_formatter_value(c, g, module_index, instance, return_slot, handle, element, element_type, verb, precision, arena_form, builder, token, depth + 1usize)
    let (increment_load_instruction, increment_counter, increment_load_error) = nir.emit(builder, .Load, usize_type, true, 8usize, token)
    if increment_load_error != ok { ret increment_load_error }
    try nir.add_operand(builder, increment_load_instruction, counter_slot)
    let (one_instruction, one, one_error) = nir.emit(builder, .ConstInteger, usize_type, true, 1usize, token)
    if one_error != ok { ret one_error }
    let (add_instruction, incremented, add_error) = nir.emit(builder, .Add, usize_type, true, 0usize, token)
    if add_error != ok { ret add_error }
    try nir.add_operand(builder, add_instruction, increment_counter)
    try nir.add_operand(builder, add_instruction, one)
    let (increment_store_instruction, increment_store_ignored, increment_store_error) = nir.emit(builder, .Store, usize_type, false, 8usize, token)
    if increment_store_error != ok { ret increment_store_error }
    try nir.add_operand(builder, increment_store_instruction, counter_slot)
    try nir.add_operand(builder, increment_store_instruction, incremented)
    let (back_edge, back_edge_error) = emit_branch(builder, token)
    if back_edge_error != ok { ret back_edge_error }
    try nir.set_branch_targets(builder, back_edge, condition_block, 0usize)

    let exit_block = builder.block_count
    let (exit_index, exit_error) = nir.begin_block(builder)
    if exit_error != ok || exit_index != exit_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, decision, body_block, exit_block)
    ret emit_formatter_byte(c, g, module_index, instance, return_slot, handle, 93u8, arena_form, builder, token)
}

// `format` builds into the caller's arena and hands back what `done` leaves, so the
// result outlives the expansion exactly as an allocation does.
fn lower_formatter_open(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, return_slot: usize, spelling: str, parameters: []usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    var arguments: [2]usize = zero
    var results: CallResults = zero
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let (capacity_instruction, capacity, capacity_error) = nir.emit(builder, .ConstInteger, usize_type, true, 64usize, token)
    if capacity_error != ok { ret (0usize, capacity_error) }
    arguments[0usize] = parameters[0usize]
    arguments[1usize] = capacity
    let builder_call_error = emit_library_call(c, g, "e.str", "builder", arguments[..], 2usize, builder, token, &results)
    if builder_call_error != ok { ret (0usize, builder_call_error) }
    if results.count != 2usize { ret (0usize, check.ArgumentCount) }
    let handle = results.values[0usize]
    let open_guard_error = emit_formatter_guard(c, module_index, instance, return_slot, results.values[1usize], true, builder, token)
    if open_guard_error != ok { ret (0usize, open_guard_error) }
    let pieces_error = lower_formatter_pieces(c, g, module_index, instance, return_slot, spelling, parameters, 1usize, handle, true, builder, token)
    if pieces_error != ok { ret (0usize, pieces_error) }
    arguments[0usize] = handle
    let done_error = emit_library_call(c, g, "e.str", "done", arguments[..], 1usize, builder, token, &results)
    if done_error != ok { ret (0usize, done_error) }
    if results.count != 1usize { ret (0usize, check.ArgumentCount) }
    ret (results.values[0usize], ok)
}

// Two words side by side in a stack slot: the `{ptr, len}` of a slice and the
// `{ctx, write}` of a `str.Sink` have the same shape, and neither needs a bounds
// check, so building them by hand is smaller than reaching for the `Slice` opcode.
fn emit_word_pair(c: *check.Checker, module_index: usize, first: usize, second: usize, builder: *nir.Builder, token: lex.Token) -> (usize, err) {
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let pair_type = check.make_type(.Other, "word-pair", module_index)
    let (stack_instruction, pair, stack_error) = nir.emit(builder, .Stack, pair_type, true, 2usize, token)
    if stack_error != ok { ret (0usize, stack_error) }
    var offset = 0usize
    while offset < 16usize {
        var word = first
        if offset == 8usize { word = second }
        let (address_instruction, address, address_error) = nir.emit(builder, .FieldAddress, pointer_type, true, offset, token)
        if address_error != ok { ret (0usize, address_error) }
        let address_operand_error = nir.add_operand(builder, address_instruction, pair)
        if address_operand_error != ok { ret (0usize, address_operand_error) }
        let (store_instruction, store_ignored, store_error) = nir.emit(builder, .Store, pointer_type, false, 8usize, token)
        if store_error != ok { ret (0usize, store_error) }
        let destination_error = nir.add_operand(builder, store_instruction, address)
        if destination_error != ok { ret (0usize, destination_error) }
        let word_error = nir.add_operand(builder, store_instruction, word)
        if word_error != ok { ret (0usize, word_error) }
        offset += 8usize
    }
    ret (pair, ok)
}

// `printf` is `format` over a buffer of its own: a `[4096]u8` local under
// `mem.arena_from`, its top claimed by `str.builder_to` with a sink that writes
// through `io.print`. The flushing is the builder's, so a push that exhausts the
// arena drains it and carries on and output of any length works; `mem.Exhausted`
// therefore never reaches the expansion, and no caller's arena is involved.
fn lower_printf_body(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, sink_index: usize, spelling: str, parameters: []usize, builder: *nir.Builder, token: lex.Token) -> err {
    var arguments: [4]usize = zero
    var results: CallResults = zero
    let usize_type = check.make_type(.Integer, "usize", module_index)
    let pointer_type = check.make_type(.Pointer, "", module_index)
    let buffer_type = check.make_type(.Other, "printf-buffer", module_index)
    let (buffer_instruction, buffer, buffer_error) = nir.emit(builder, .Stack, buffer_type, true, 512usize, token)
    if buffer_error != ok { ret buffer_error }
    let (size_instruction, size, size_error) = nir.emit(builder, .ConstInteger, usize_type, true, 4096usize, token)
    if size_error != ok { ret size_error }
    let (bytes, bytes_error) = emit_word_pair(c, module_index, buffer, size, builder, token)
    if bytes_error != ok { ret bytes_error }
    arguments[0usize] = bytes
    try emit_library_call(c, g, "e.mem", "arena_from", arguments[..], 1usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    let arena = results.values[0usize]

    let sink = c.functions[sink_index]
    let (function_ref, function_ref_error) = nir.intern_function(builder, sink.owner_module_index, sink.name, sink.instance_id)
    if function_ref_error != ok { ret function_ref_error }
    let (write_instruction, write, write_error) = nir.emit(builder, .FunctionAddress, pointer_type, true, function_ref, token)
    if write_error != ok { ret write_error }
    // The sink never reads its context: what it writes to is `os.stdout()`, which it
    // asks for itself. A null keeps the field from carrying a stale address.
    let (context_instruction, context, context_error) = nir.emit(builder, .ConstInteger, pointer_type, true, 0usize, token)
    if context_error != ok { ret context_error }
    let (sink_value, sink_value_error) = emit_word_pair(c, module_index, context, write, builder, token)
    if sink_value_error != ok { ret sink_value_error }

    // An eighth of the buffer, so the doubling in `push` has somewhere to go before
    // the arena is exhausted and the first drain happens.
    let (capacity_instruction, capacity, capacity_error) = nir.emit(builder, .ConstInteger, usize_type, true, 512usize, token)
    if capacity_error != ok { ret capacity_error }
    arguments[0usize] = arena
    arguments[1usize] = capacity
    arguments[2usize] = sink_value
    try emit_library_call(c, g, "e.str", "builder_to", arguments[..], 3usize, builder, token, &results)
    if results.count != 2usize { ret check.ArgumentCount }
    let handle = results.values[0usize]
    try emit_formatter_guard(c, module_index, instance, 0usize, results.values[1usize], false, builder, token)
    try lower_formatter_pieces(c, g, module_index, instance, 0usize, spelling, parameters, 0usize, handle, false, builder, token)
    arguments[0usize] = handle
    try emit_library_call(c, g, "e.str", "done", arguments[..], 1usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    // What `done` leaves is the tail the drains did not take, and it goes the same way.
    arguments[0usize] = results.values[0usize]
    try emit_library_call(c, g, "e.io", "print", arguments[..], 1usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    ret emit_formatter_return(c, module_index, instance, 0usize, 0usize, results.values[0usize], false, builder, token)
}

// One entry of the merged table: if the value matches, push that name and return.
// The compare chain is straight-line, so it needs no loop and no table in the binary;
// a sorted table is what would let a later pass turn it into a search.
fn emit_error_case(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, handle: usize, value: usize, spelling: str, subject: usize, builder: *nir.Builder, token: lex.Token) -> err {
    var arguments: [2]usize = zero
    var results: CallResults = zero
    let error_type = check.make_type(.Err, "err", module_index)
    let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstError, error_type, true, value, token)
    if constant_error != ok { ret constant_error }
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (compare_instruction, matched, compare_error) = nir.emit(builder, .Equal, boolean, true, 0usize, token)
    if compare_error != ok { ret compare_error }
    try nir.add_operand(builder, compare_instruction, subject)
    try nir.add_operand(builder, compare_instruction, constant)
    let hit_block = builder.block_count
    let miss_block = builder.block_count + 1usize
    let (branch_instruction, branch_ignored, branch_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
    if branch_error != ok { ret branch_error }
    try nir.add_operand(builder, branch_instruction, matched)
    try nir.set_branch_targets(builder, branch_instruction, hit_block, miss_block)
    let (hit_index, hit_error) = nir.begin_block(builder)
    if hit_error != ok || hit_index != hit_block { ret nir.InvalidControlFlow }
    let text_type = check.make_type(.String, "str", module_index)
    let (name_index, name_intern_error) = nir.intern_string(builder, spelling)
    if name_intern_error != ok { ret name_intern_error }
    let (name_instruction, name, name_error) = nir.emit(builder, .ConstString, text_type, true, name_index, token)
    if name_error != ok { ret name_error }
    arguments[0usize] = handle
    arguments[1usize] = name
    try emit_library_call(c, g, "e.str", "push", arguments[..], 2usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    try emit_formatter_return(c, module_index, instance, 0usize, 0usize, results.values[0usize], false, builder, token)
    let (miss_index, miss_error) = nir.begin_block(builder)
    if miss_error != ok || miss_index != miss_block { ret nir.InvalidControlFlow }
    ret ok
}

// `push_err` writes the qualified name (spec section 7). The names come from the
// merged error table, which is why this cannot be library source: the table is a
// property of the whole program, and `e.str` sees one module at a time.
fn lower_error_push_body(c: *check.Checker, g: *graph.Graph, module_index: usize, instance: check.Function, parameters: []usize, builder: *nir.Builder, token: lex.Token) -> err {
    var arguments: [2]usize = zero
    var results: CallResults = zero
    let handle = parameters[0usize]
    let subject = parameters[1usize]
    try emit_error_case(c, g, module_index, instance, handle, 0usize, "\"ok\"", subject, builder, token)
    var at = 0usize
    while at < c.error_count {
        try emit_error_case(c, g, module_index, instance, handle, c.error_values[at], c.error_spellings[at], subject, builder, token)
        at += 1usize
    }
    // A value the table does not carry is reachable only through `undef` or a union
    // pun, and prints as its own hexadecimal rather than as a name it does not have.
    let text_type = check.make_type(.String, "str", module_index)
    let (open_index, open_intern_error) = nir.intern_string(builder, "\"err(0x\"")
    if open_intern_error != ok { ret open_intern_error }
    let (open_instruction, open_text, open_error) = nir.emit(builder, .ConstString, text_type, true, open_index, token)
    if open_error != ok { ret open_error }
    arguments[0usize] = handle
    arguments[1usize] = open_text
    try emit_library_call(c, g, "e.str", "push", arguments[..], 2usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    try emit_formatter_guard(c, module_index, instance, 0usize, results.values[0usize], false, builder, token)
    let error_type = check.make_type(.Err, "err", module_index)
    let unsigned = check.make_type(.Integer, "u32", module_index)
    let (raw, raw_error) = lower_bitcast(c, subject, error_type, unsigned, builder, token)
    if raw_error != ok { ret raw_error }
    arguments[0usize] = handle
    arguments[1usize] = raw
    try emit_library_call(c, g, "e.str", "push_hex_u32", arguments[..], 2usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    try emit_formatter_guard(c, module_index, instance, 0usize, results.values[0usize], false, builder, token)
    let (close_index, close_intern_error) = nir.intern_string(builder, "\")\"")
    if close_intern_error != ok { ret close_intern_error }
    let (close_instruction, close_text, close_error) = nir.emit(builder, .ConstString, text_type, true, close_index, token)
    if close_error != ok { ret close_error }
    arguments[0usize] = handle
    arguments[1usize] = close_text
    try emit_library_call(c, g, "e.str", "push", arguments[..], 2usize, builder, token, &results)
    if results.count != 1usize { ret check.ArgumentCount }
    ret emit_formatter_return(c, module_index, instance, 0usize, 0usize, results.values[0usize], false, builder, token)
}

// A formatter instance is the one function in the program with no source: its
// signature comes from the call that asked for it and its body from the format
// string. Everything around the body -- the hidden return slot, the parameters, the
// symbol -- is what `lower_function_index` builds for an ordinary function.
fn lower_formatter_instance(c: *check.Checker, g: *graph.Graph, module_index: usize, instance_index: usize, builder: *nir.Builder, signatures: *nir.Signatures) -> err {
    if instance_index >= c.function_count { ret FunctionNotFound }
    let instance = c.functions[instance_index]
    let generic = c.function_generics[instance_index]
    if !generic.formatter { ret check.Unsupported }
    if instance.parameter_count > 32usize { ret check.ArgumentCount }
    var token: lex.Token = zero
    c.failure_module = module_index
    c.failure_name = instance.name
    c.failure_has_token = false
    let arena_form = instance.return_count == 2usize
    let (nir_function, begin_error) = nir.begin_function(builder, instance.owner_module_index, instance.name, instance.instance_id)
    if begin_error != ok { ret begin_error }
    // An instance's tokens are the template's, so the record names the template's file.
    builder.functions[nir_function].path = g.modules[instance.module_index].path
    builder.functions[nir_function].module_name = g.modules[instance.owner_module_index].name
    builder.current_path = g.modules[instance.module_index].path
    builder.current_text = g.modules[instance.module_index].text
    builder.current_lines = g.modules[instance.module_index].lines
    builder.site_line = 0usize
    try nir.begin_signature(builder, nir_function, signatures)
    var signature_at = 0usize
    while signature_at < instance.parameter_count {
        try nir.add_parameter_type(builder, nir_function, signatures, c.parameters[instance.first_parameter + signature_at].ty)
        signature_at += 1usize
    }
    signature_at = 0usize
    while signature_at < instance.return_count {
        try nir.add_return_type(builder, nir_function, signatures, c.return_types[instance.first_return + signature_at])
        signature_at += 1usize
    }
    let (entry, block_error) = nir.begin_block(builder)
    if block_error != ok { ret block_error }
    var call: check.CallInfo = zero
    call.function = instance
    var return_layout: ReturnLayout = zero
    let return_layout_error = call_return_layout(c, call, &return_layout)
    if return_layout_error != ok { ret return_layout_error }
    var hidden = 0usize
    var return_slot = 0usize
    if return_layout.via_slot {
        let pointer_type = check.make_type(.Pointer, "", module_index)
        let (slot_instruction, slot, slot_error) = nir.emit(builder, .Parameter, pointer_type, true, 0usize, token)
        if slot_error != ok { ret slot_error }
        return_slot = slot
        hidden = 1usize
    }
    var parameters: [33]usize = zero
    var parameter_at = 0usize
    while parameter_at < instance.parameter_count {
        let parameter = c.parameters[instance.first_parameter + parameter_at]
        let (instruction, result, parameter_error) = nir.emit(builder, .Parameter, parameter.ty, true, parameter_at + hidden, token)
        if parameter_error != ok { ret parameter_error }
        parameters[parameter_at] = result
        parameter_at += 1usize
    }
    if generic.formatter_error {
        try lower_error_push_body(c, g, module_index, instance, parameters[..], builder, token)
        ret nir.end_function(builder)
    }
    if generic.formatter_sink {
        // The sink is one call: `io.print` already loops over `os.write` until every
        // byte is gone. It needs a body of its own only because the arities differ --
        // a sink takes the context `print` has no parameter for.
        var sink_results: CallResults = zero
        var sink_arguments: [1]usize = zero
        sink_arguments[0usize] = parameters[1usize]
        try emit_library_call(c, g, "e.io", "print", sink_arguments[..], 1usize, builder, token, &sink_results)
        if sink_results.count != 1usize { ret check.ArgumentCount }
        try emit_formatter_return(c, module_index, instance, 0usize, 0usize, sink_results.values[0usize], false, builder, token)
        ret nir.end_function(builder)
    }
    if !arena_form {
        let (io_module, found_io) = graph.find_module(g, "e.io")
        if !found_io { ret FunctionNotFound }
        let (sink_index, sink_error) = check.formatter_sink_instance(c, module_index, io_module)
        if sink_error != ok { ret sink_error }
        try lower_printf_body(c, g, module_index, instance, sink_index, generic.formatter_spelling, parameters[..], builder, token)
        ret nir.end_function(builder)
    }
    let (text, body_error) = lower_formatter_open(c, g, module_index, instance, return_slot, generic.formatter_spelling, parameters[..], builder, token)
    if body_error != ok { ret body_error }
    let error_type = check.make_type(.Err, "err", module_index)
    let (ok_instruction, ok_value, ok_error) = nir.emit(builder, .ConstError, error_type, true, 0usize, token)
    if ok_error != ok { ret ok_error }
    try emit_formatter_return(c, module_index, instance, return_slot, text, ok_value, arena_form, builder, token)
    ret nir.end_function(builder)
}

fn pending_formatter(c: *check.Checker, owner_module_index: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let generic = c.function_generics[at]
        if generic.formatter && !generic.lowered && c.functions[at].owner_module_index == owner_module_index { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A concrete instance is code in the module that instantiated it, but its body is
// the template's source, so lowering it needs the declaring module's tree. Each
// pass parses one declaring module and lowers every pending instance from it;
// instances that pass creates in turn are picked up by the next one.
fn lower_owned_instances(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    var defers: DeferState = zero
    while true {
        // A formatter instance has no declaring module to parse, so it is drained
        // first and on its own; either kind can create the other.
        let (formatter, found_formatter) = pending_formatter(c, module_index)
        if found_formatter {
            c.function_generics[formatter].lowered = true
            try lower_formatter_instance(c, g, module_index, formatter, builder, signatures)
            continue
        }
        let (first, found) = pending_instance(c, module_index)
        if !found { ret ok }
        let template_module = c.functions[c.function_generics[first].template_index].module_index
        if template_module >= g.count { ret FunctionNotFound }
        var tree: parse.Tree = zero
        try graph.parse_module(g, template_module, &tree)
        try check.tokenize_module(c, g, template_module)
        var at = first
        let end = c.function_count
        while at < end {
            let generic = c.function_generics[at]
            if generic.instance && !generic.lowered && !c.functions[at].generic && c.functions[at].owner_module_index == module_index && c.functions[generic.template_index].module_index == template_module {
                c.function_generics[at].lowered = true
                c.active_owner_module = module_index
                c.active_owner_set = true
                let lower_error = lower_instance(c, g, &tree, template_module, at, builder, signatures, bindings, &defers)
                c.active_owner_set = false
                c.active_owner_module = 0usize
                if lower_error != ok { ret lower_error }
            }
            at += 1usize
        }
    }
    ret ok
}

fn module(c: *check.Checker, g: *graph.Graph, module_index: usize, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding) -> err {
    if module_index >= g.count { ret FunctionNotFound }
    var defers: DeferState = zero
    var tree: parse.Tree = zero
    try graph.parse_module(g, module_index, &tree)
    try check.tokenize_module(c, g, module_index)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl { try lower_declaration(c, g, &tree, module_index, node, builder, signatures, bindings, &defers) }
        node_index += 1usize
    }
    if module_index == 0usize && c.main_reports_failure {
        c.main_reports_failure = false
        try synthesize_failure_report(c, g, builder, signatures)
    }
    ret lower_owned_instances(c, g, module_index, builder, signatures, bindings)
}

// `error: <qualified name>` on stderr, for the value `main` returned (section 13). The
// program-wide error table is the resolver's error symbols, so the function is one
// compare per declared error and a write of its name; a value none of them has --
// reachable only through `undef` -- prints as `err(?)`. It writes through the runtime's
// own `neper_os_stderr` and `neper_os_write`, which every image carries, so nothing
// here depends on `e.os` being in the graph.
fn emit_report_write(builder: *nir.Builder, module_index: usize, write_ref: usize, file_slot: usize, spelling: str, token: lex.Token) -> err {
    let string_type = check.make_type(.String, "str", module_index)
    let (text_index, text_error) = nir.intern_string(builder, spelling)
    if text_error != ok { ret text_error }
    let (text_instruction, text, text_emit_error) = nir.emit(builder, .ConstString, string_type, true, text_index, token)
    if text_emit_error != ok { ret text_emit_error }
    let (write_call, write_ignored, write_error) = nir.emit(builder, .Call, zero, false, write_ref, token)
    if write_error != ok { ret write_error }
    try nir.add_operand(builder, write_call, file_slot)
    ret nir.add_operand(builder, write_call, text)
}

fn synthesize_failure_report(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures) -> err {
    let module_index = 0usize
    var token: lex.Token = zero
    let error_type = check.make_type(.Err, "err", module_index)
    let boolean = check.make_type(.Bool, "bool", module_index)
    let (nir_function, begin_error) = nir.begin_function(builder, module_index, "neper_report_failure", 0usize)
    if begin_error != ok { ret begin_error }
    builder.functions[nir_function].path = g.modules[module_index].path
    builder.functions[nir_function].module_name = g.modules[module_index].name
    builder.current_path = g.modules[module_index].path
    builder.current_text = g.modules[module_index].text
    builder.current_lines = g.modules[module_index].lines
    builder.site_line = 0usize
    try nir.begin_signature(builder, nir_function, signatures)
    try nir.add_parameter_type(builder, nir_function, signatures, error_type)
    let (entry, entry_error) = nir.begin_block(builder)
    if entry_error != ok { ret entry_error }
    let (value_instruction, value, value_error) = nir.emit(builder, .Parameter, error_type, true, 0usize, token)
    if value_error != ok { ret value_error }
    let (slot_instruction, file_slot, slot_error) = nir.emit(builder, .Stack, check.make_type(.Other, "file-slot", module_index), true, 1usize, token)
    if slot_error != ok { ret slot_error }
    let (stderr_ref, stderr_ref_error) = nir.intern_function(builder, module_index, "neper_os_stderr", 0usize)
    if stderr_ref_error != ok { ret stderr_ref_error }
    let (stderr_call, stderr_ignored, stderr_call_error) = nir.emit(builder, .Call, zero, false, stderr_ref, token)
    if stderr_call_error != ok { ret stderr_call_error }
    try nir.add_operand(builder, stderr_call, file_slot)
    let (write_ref, write_ref_error) = nir.intern_function(builder, module_index, "neper_os_write", 0usize)
    if write_ref_error != ok { ret write_ref_error }
    try emit_report_write(builder, module_index, write_ref, file_slot, quoted_text(c, "error: "), token)
    var decisions: [1024]usize = zero
    // The errors in value order (D329), as the merged error table holds them: the
    // resolver's order is the order the modules were declared in, which a hot build
    // that parses late what it must rebuild does not share with a cold one.
    var ordered: [1024]usize = zero
    var ordered_values: [1024]usize = zero
    var ordered_count = 0usize
    var symbol_index = 0usize
    while symbol_index < c.resolver.count {
        let symbol = c.resolver.symbols[symbol_index]
        if symbol.kind == .Error && symbol.module_index < g.count {
            if ordered_count == ordered.len { ret check.Capacity }
            let (error_value, error_value_error) = artifact_hash.qualified_error_value(g.modules[symbol.module_index].name, symbol.name)
            if error_value_error != ok { ret error_value_error }
            var sort_at = ordered_count
            while sort_at > 0usize && ordered_values[sort_at - 1usize] > error_value {
                ordered_values[sort_at] = ordered_values[sort_at - 1usize]
                ordered[sort_at] = ordered[sort_at - 1usize]
                sort_at = sort_at - 1usize
            }
            ordered_values[sort_at] = error_value
            ordered[sort_at] = symbol_index
            ordered_count += 1usize
        }
        symbol_index += 1usize
    }
    var count = 0usize
    var ordered_at = 0usize
    while ordered_at < ordered_count {
        symbol_index = ordered[ordered_at]
        ordered_at += 1usize
        let symbol = c.resolver.symbols[symbol_index]
        if true {
            if count == decisions.len { ret check.Capacity }
            let module_name = g.modules[symbol.module_index].name
            let qualified = ordered_values[ordered_at - 1usize]
            let (constant_instruction, constant, constant_error) = nir.emit(builder, .ConstError, error_type, true, qualified, token)
            if constant_error != ok { ret constant_error }
            let (matches, matches_error) = emit_supplied_compare(builder, .Equal, boolean, value, constant, token)
            if matches_error != ok { ret matches_error }
            let hit_block = builder.block_count
            let next_block = builder.block_count + 1usize
            let (decision, decision_ignored, decision_error) = nir.emit(builder, .BranchIf, zero, false, 0usize, token)
            if decision_error != ok { ret decision_error }
            try nir.add_operand(builder, decision, matches)
            try nir.set_branch_targets(builder, decision, hit_block, next_block)
            let (hit_index, hit_error) = nir.begin_block(builder)
            if hit_error != ok || hit_index != hit_block { ret nir.InvalidControlFlow }
            let (storage, storage_error) = mem.alloc[u8](c.arena, module_name.len + 1usize + symbol.name.len)
            if storage_error != ok { ret storage_error }
            var write_at = 0usize
            try append_text(storage[..], &write_at, module_name)
            try append_text(storage[..], &write_at, ".")
            try append_text(storage[..], &write_at, symbol.name)
            try emit_report_write(builder, module_index, write_ref, file_slot, quoted_text(c, storage[..]), token)
            let (to_tail, to_tail_error) = emit_branch(builder, token)
            if to_tail_error != ok { ret to_tail_error }
            decisions[count] = to_tail
            count += 1usize
            let (next_index, next_error) = nir.begin_block(builder)
            if next_error != ok || next_index != next_block { ret nir.InvalidControlFlow }
        }
        symbol_index += 1usize
    }
    try emit_report_write(builder, module_index, write_ref, file_slot, quoted_text(c, "err(?)"), token)
    let (to_tail_last, to_tail_last_error) = emit_branch(builder, token)
    if to_tail_last_error != ok { ret to_tail_last_error }
    let tail_block = builder.block_count
    let (tail_index, tail_error) = nir.begin_block(builder)
    if tail_error != ok || tail_index != tail_block { ret nir.InvalidControlFlow }
    try nir.set_branch_targets(builder, to_tail_last, tail_block, 0usize)
    var fix_at = 0usize
    while fix_at < count {
        try nir.set_branch_targets(builder, decisions[fix_at], tail_block, 0usize)
        fix_at += 1usize
    }
    try emit_report_write(builder, module_index, write_ref, file_slot, quoted_text(c, "\n"), token)
    let (return_instruction, return_ignored, return_error) = nir.emit(builder, .Return, zero, false, 0usize, token)
    if return_error != ok { ret return_error }
    ret nir.end_function(builder)
}

// Every module of the graph in graph order, for the artifacts (D214): a `.em` is the
// module compiled, whichever functions of it this program reaches, and one the edge
// rule keeps is not lowered at all -- `skip` marks those, and they count as done.
fn all_modules(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, lowered: []bool, skip: []bool) -> err {
    if g.count == 0usize || g.count > lowered.len || g.count > skip.len { ret FunctionNotFound }
    try declare_globals(c, builder)
    var module_index = 0usize
    while module_index < g.count {
        if !skip[module_index] { try module(c, g, module_index, builder, signatures, bindings) }
        lowered[module_index] = true
        module_index += 1usize
    }
    ret ok
}

fn reachable_modules(c: *check.Checker, g: *graph.Graph, builder: *nir.Builder, signatures: *nir.Signatures, bindings: []Binding, lowered: []bool) -> err {
    if g.count == 0usize || g.count > lowered.len { ret FunctionNotFound }
    try declare_globals(c, builder)
    var module_index = 0usize
    while module_index < g.count {
        lowered[module_index] = false
        module_index += 1usize
    }
    try module(c, g, 0usize, builder, signatures, bindings)
    lowered[0usize] = true
    // A module reached only by inlining (D207) has no reference to discover it by, and
    // its artifact still needs the callee's own definition; both lists are walked to
    // a fixed point, since either kind of lowering adds to both.
    var progress = true
    while progress {
        progress = false
        var reference_at = 0usize
        while reference_at < builder.function_ref_count {
            let target_module = builder.function_refs[reference_at].module_index
            if target_module >= g.count { ret FunctionNotFound }
            if !lowered[target_module] {
                try module(c, g, target_module, builder, signatures, bindings)
                lowered[target_module] = true
                progress = true
            }
            reference_at += 1usize
        }
        var inlined_at = 0usize
        while inlined_at < builder.inlined_count {
            let target_module = builder.inlined[inlined_at].callee_module
            if target_module >= g.count { ret FunctionNotFound }
            if !lowered[target_module] {
                try module(c, g, target_module, builder, signatures, bindings)
                lowered[target_module] = true
                progress = true
            }
            inlined_at += 1usize
        }
    }
    ret ok
}
