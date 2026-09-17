// Canonical typed SSA-lite IR shared by code generation and .em serialization.

use check
use lex
use lookup

error Capacity
// A body longer than the builder's `instruction_limit` (D310): the inlining oracle
// stops lowering a function the moment it cannot inline it.
error TooLong
error InvalidControlFlow
error InvalidValue

// Numeric values are part of the versioned .em format. Never renumber an opcode.
type Opcode = enum u8 {
    Invalid = 0,
    Parameter = 1,
    ConstInteger = 2,
    ConstBool = 3,
    ConstError = 4,
    ConstString = 5,
    Stack = 6,
    Load = 7,
    Store = 8,
    Copy = 9,
    Zero = 10,
    FieldAddress = 11,
    IndexAddress = 12,
    Slice = 13,
    Cast = 14,
    Add = 15,
    Subtract = 16,
    Multiply = 17,
    Divide = 18,
    Remainder = 19,
    AddWrap = 20,
    SubtractWrap = 21,
    MultiplyWrap = 22,
    ShiftLeft = 23,
    ShiftRight = 24,
    BitAnd = 25,
    BitXor = 26,
    BitOr = 27,
    Negate = 28,
    BitNot = 29,
    Equal = 30,
    NotEqual = 31,
    Less = 32,
    LessEqual = 33,
    Greater = 34,
    GreaterEqual = 35,
    Call = 36,
    Extract = 37,
    Phi = 38,
    Trap = 39,
    Branch = 40,
    BranchIf = 41,
    Switch = 42,
    Return = 43,
    Unreachable = 44,
    FunctionAddress = 45,
    IndirectCall = 46,
    ConstFloat = 47,
    Bitcast = 48,
    // Section 8's atomics. `AtomicRmw` and `AtomicCas` give back the value that was
    // there before, which is what every one of section 8's operations returns; `cas`
    // derives its `bool` from that with an ordinary comparison, so no opcode here
    // produces more than one result.
    AtomicLoad = 49,
    AtomicStore = 50,
    AtomicRmw = 51,
    AtomicCas = 52,
    AtomicFence = 53,
    // The address of a module-scope `var`. The immediate is an index into the builder's globals,
    // and the address is not known until the image is laid out -- so this lowers to a relocation
    // the linker fills, the way a call to an imported symbol does.
    GlobalAddress = 54,
    // `math.sqrt`: the one float operation that is an instruction on every target and has no
    // operator, so it is an opcode of its own rather than a call.
    Sqrt = 55,
}

// `AtomicRmw`'s immediate is `kind * 8 + ordering`, so the two travel in the one
// immediate an instruction has. Never renumber these either: they are in the format.
type AtomicRmwKind = enum u8 {
    Xchg = 0,
    Add = 1,
    Sub = 2,
    And = 3,
    Or = 4,
    Xor = 5,
    Min = 6,
    Max = 7,
}

fn atomic_rmw_immediate(kind: AtomicRmwKind, ordering: usize) -> usize {
    ret atomic_rmw_kind_rank(kind) * 8usize + ordering
}

fn atomic_rmw_kind_rank(kind: AtomicRmwKind) -> usize {
    if kind == .Xchg { ret 0usize }
    if kind == .Add { ret 1usize }
    if kind == .Sub { ret 2usize }
    if kind == .And { ret 3usize }
    if kind == .Or { ret 4usize }
    if kind == .Min { ret 6usize }
    if kind == .Max { ret 7usize }
    ret 5usize
}

type Site = struct {
    start: usize,
    end: usize,
    line: usize,
    column: usize,
}

// The token a site was recorded from, with the fields nothing downstream reads zero.
fn site_token(site: Site) -> lex.Token {
    var token: lex.Token = zero
    token.start = site.start
    token.end = site.end
    ret token
}

type Instruction = struct {
    opcode: Opcode,
    result: usize,
    has_result: bool,
    ty: check.Type,
    first_operand: usize,
    operand_count: usize,
    immediate: usize,
    target: usize,
    target2: usize,
    // Where the instruction came from, as much of the token as anything downstream reads
    // (D306): a whole `lex.Token` is 120 bytes and made an instruction 180.
    site: Site,
    // Emitted inside `@nocheck { ... }`: the debug-only checks are left out of it (D203).
    nocheck: bool,
    // The one-based head of this copied instruction's inline chain in `inlined`;
    // zero for source instructions. A u32 occupies the padding before `path` (D565).
    inline_origin: u32,
    // The source file the instruction came from: its function's, unless it was inlined
    // from another module's function (D207), which a trap record has to name.
    path: str,
}

type Block = struct {
    first_instruction: usize,
    instruction_count: usize,
    terminated: bool,
}

type Function = struct {
    name: str,
    module_index: usize,
    instance: usize,
    // The source file, as a trap record names it (section 11); set by lowering.
    path: str,
    // The module's name, as a backtrace frame names it, `module.function` (D206).
    module_name: str,
    first_block: usize,
    block_count: usize,
    first_instruction: usize,
    instruction_count: usize,
    value_count: usize,
}

type Signature = struct {
    first_parameter_type: usize,
    parameter_count: usize,
    first_return_type: usize,
    return_count: usize,
}

type FunctionRef = struct {
    module_index: usize,
    name: str,
    instance: usize,
    // Both are the prune's working state: whether a surviving function still names this, and
    // where it moved to once the dead ones were dropped.
    live: bool,
    renumbered: usize,
    // An `extern fn` bound by `@import`. A reference carrying a library is called
    // through the image's import table rather than by a relative displacement, so the
    // distinction has to survive as far as the linker.
    library: str,
    symbol: str,
    // The function this reference names, once `codegen_x64.resolve_calls` has looked it
    // up (D306): every relocation to it then reads the index instead of searching.
    target: usize,
    has_target: bool,
}

type StringConstant = struct {
    spelling: str,
}

// One module-scope `var`, as the linker needs it: somewhere to put it, and what to put there.
// `initial` carries a scalar initialiser's bits; a global with none is zero, which is what an
// image gives for free.
type GlobalData = struct {
    module_index: usize,
    name: str,
    size: usize,
    alignment: usize,
    initial: usize,
    has_initial: bool,
}

type Signatures = struct {
    entries: []Signature,
    types: []check.Type,
    count: usize,
}

// One function small enough to inline (section 12's cap of forty NIR instructions),
// lowered ahead of the program into the oracle builder, keyed the way a call names it.
type InlineEntry = struct {
    module_index: usize,
    name: str,
    instance: usize,
    function_index: usize,
    // The module whose tree the declaration was walked in (D313), which is not always
    // the owner: a per-target variant's function is owned by the module it merges into.
    // The second oracle skips a module with no entry recorded under it.
    walked_in: usize,
    // The builder the body was lowered into and the checker it was lowered with
    // (D326): the oracles are built per worker, and a copy taken into another
    // worker's builder carries the types over from that checker.
    oracle: *Builder,
    checker: *check.Checker,
}

// A callee inlined into a module: what section 12 calls a body edge, recorded so the
// artifact carries it and the pruner keeps the callee's own definition.
type InlinedRef = struct {
    caller_module: usize,
    callee_module: usize,
    name: str,
    instance: usize,
    // The function whose body holds the copy, so a nested copy (D212) can carry the
    // refs of the body it copies along to its own caller.
    caller_function: usize,
}

type Builder = struct {
    // The (module, instance, name) index over `function_refs` and the name index over
    // `strings` (D306): both interners scanned their whole table per call site and per
    // literal. Absent, they scan; the CLI attaches them.
    ref_names: lookup.Index,
    string_names: lookup.Index,
    functions: []Function,
    blocks: []Block,
    instructions: []Instruction,
    operands: []usize,
    function_refs: []FunctionRef,
    strings: []StringConstant,
    globals: []GlobalData,
    global_count: usize,
    // How many bytes of the embedded runtime the PE linker kept, which decides how many of the
    // runtime's imports the image declares. Set by `link_pe.write` and read by its layout
    // helpers, which reach everything else through this builder too.
    runtime_prefix: usize,
    // Set while lowering a `@nocheck` block; every instruction emitted carries it.
    nocheck: bool,
    // Bounds proofs (D356, H03): the `while i < x.len` loops open around the point
    // being lowered, innermost last -- the index and the slice by name, the first
    // token in the body that assigns the index, and whether the proof holds at all
    // -- and how many index checks they let the lowering leave out.
    proof_index: [8]str,
    proof_base: [8]str,
    proof_first_assign: [8]usize,
    // The slack of the proof (D385): `while i + K <= x.len` proves `x[i + j]` for
    // `j` below `K`, `while i + K < x.len` for `j` at most `K`; the plain forms have none.
    proof_slack: [8]usize,
    // Two slices known to be the same length (D390): `if a.len != b.len { ret }` for
    // the rest of the block, or `if a.len == b.len { ... }` for its block, so a proof
    // over one covers an index into the other. Innermost last, like the proofs.
    proof_equal_a: [8]str,
    proof_equal_b: [8]str,
    proof_equal_count: usize,
    proof_ok: [8]bool,
    proof_count: usize,
    proof_function_start: usize,
    proof_function_end: usize,
    // The identifiers the function takes the address of, as token indices, collected
    // once when the function is opened (D383): a proof asks this list, not the
    // function's tokens, so the question is not quadratic in the function.
    proof_addressed: [256]usize,
    proof_addressed_count: usize,
    proof_addressed_overflow: bool,
    // The lengths held in a local (D452, H03): every `let n = x.len` of the function,
    // as the token indices of `n` and `x`, collected when the function is opened, so
    // `while i < n` reads as `while i < x.len` when `x` is never written.
    proof_alias_name: [16]usize,
    proof_alias_base: [16]usize,
    proof_alias_count: usize,
    bounds_elided: usize,
    // By-value arguments copied for the call (D358, H05), and those passed by the
    // caller's own storage because nothing can write it during the call.
    snapshots_copied: usize,
    snapshots_elided: usize,
    // Register pressure (D450, H20): the values the allocator placed, the ones it
    // put on the stack, and the functions with any on the stack, over the functions
    // this builder's code was generated from.
    values_allocated: usize,
    values_spilled: usize,
    functions_spilling: usize,
    // The release build (D217): `nocheck` is that too, but `@nocheck` sets it for a
    // block, and section 11's debug fills do not come off with the checks.
    release: bool,
    // The inlining cap (D346, H20): section 12's forty by default, `--inline-cap N`
    // for a measurement; and whether every decision is explained on stderr
    // (`--explain`), as "inline: module.function: <decision>".
    inline_cap: usize,
    explain: bool,
    // Where the explanations go (D408, H20): appended here by the oracle's worker,
    // written out by the driver after the phase in worker order -- as records of the
    // JSON stream under `--json`, as the text lines otherwise -- so eight workers'
    // lines never interleave and the order is the same run to run. `explain_overflow`
    // says the storage ran out and some decisions went unexplained.
    explain_json: bool,
    explain_bytes: []u8,
    explain_count: usize,
    explain_overflow: bool,
    // `--arena` (D225): the root arena's size the linker patches into the image, or
    // zero for the runtime's default.
    arena_bytes: usize,
    // The path every instruction emitted is stamped with: the function's, or the
    // callee's while its body is being copied in.
    current_path: str,
    // The text and line table of the module being lowered (D315): a site's line and
    // column are looked up from the token's offset as the instruction is emitted.
    current_text: str,
    current_lines: []usize,
    // The line the last site fell on and its byte range (D315): consecutive
    // instructions come from the same line far more often than not, so the binary
    // search runs once per line rather than once per instruction.
    site_line: usize,
    site_line_start: usize,
    site_line_end: usize,
    // The inlining oracle (D207): small functions lowered ahead of the program into
    // their own builder, and the sites that took a body from it.
    oracle: *Builder,
    oracle_signatures: *Signatures,
    has_oracle: bool,
    inline_entries: []InlineEntry,
    inline_entry_count: usize,
    inlined: []InlinedRef,
    inlined_count: usize,
    // Inline-origin nodes share the unused tail of `inlined`, growing backwards so
    // provenance adds no second allocation (D565).
    inline_origin_count: usize,
    // An oracle's cap on one body's instructions, measured from `limit_base`; zero is
    // no cap (D310).
    instruction_limit: usize,
    limit_base: usize,
    // Which references one module's instructions name (D319): marked in one walk when
    // its artifact's edges are written, where each edge used to walk every instruction.
    used_marks: []u8,
    used_marks_module: usize,
    used_marks_valid: bool,
    // The instruction defining each value of the function being emitted, plus one
    // (D326), filled by `codegen_x64.function` for `definers_first`'s function: the
    // type of a value was found by walking the function's instructions from the top.
    definers: []usize,
    definers_first: usize,
    definers_valid: bool,
    // The verifier's scratch (D342): words for every value and block of the largest
    // function; empty, and nothing is verified beyond the terminators.
    verify_scratch: []usize,
    // What the verifier refused, for the diagnostic: the instruction and the operand.
    verify_instruction: usize,
    verify_operand: usize,
    // The writer's edge marks (D320), valid with the used marks: which used references
    // record a dependency edge, which inlined entries stand for a body edge, and the
    // index that dedupes both -- the walks they replace were quadratic per module.
    edge_marks: []u8,
    inlined_marks: []u8,
    edge_index: lookup.Index,
    // The marked references by index, in order (D320): a module names a few dozen,
    // and its edges were deduplicated by walking every reference of the program.
    used_list: []usize,
    used_count: usize,
    // The imports in name order (D319), built when the linker first asks.
    import_order: [1024]usize,
    import_order_count: usize,
    imports_ordered: bool,
    // Every reference's target set by whoever made the references (D460): the
    // artifact link, which knows each callee's function from its reach walk, so
    // `resolve_reference_targets` has nothing to search for.
    targets_preset: bool,
    // What `discard_bodies` has let go of (D314): the instructions lowered in all, and
    // the most one module held at once, for `--stats` and for sizing the body pools.
    instruction_total: usize,
    instruction_peak: usize,
    block_total: usize,
    operand_total: usize,
    function_count: usize,
    block_count: usize,
    instruction_count: usize,
    operand_count: usize,
    function_ref_count: usize,
    string_count: usize,
    current_function: usize,
    current_block: usize,
    next_value: usize,
    function_active: bool,
    block_active: bool,
}

// Given separately from `init` because `init` has eight callers and only one of them compiles a
// program: a module's own self-check has no module-scope `var` to describe, and a builder without
// this simply has none.
fn init_globals(builder: *Builder, globals: []GlobalData) -> err {
    if globals.len == 0usize { ret Capacity }
    builder.globals = globals
    builder.global_count = 0usize
    ret ok
}

// Appended in the checker's own order, once per declaration, before anything is lowered. That is
// what makes one variable one address: not a search that has to agree with itself at every use,
// but an index that is the same number on both sides. An earlier version interned per use and got
// a fresh entry each time, which showed up as a data segment far larger than its five variables.
fn add_global(builder: *Builder, module_index: usize, name: str, size: usize, alignment: usize, initial: usize, has_initial: bool) -> (usize, err) {
    if builder.global_count == builder.globals.len { ret (0usize, Capacity) }
    builder.globals[builder.global_count] = GlobalData { module_index: module_index, name: name, size: size, alignment: alignment, initial: initial, has_initial: has_initial }
    builder.global_count += 1usize
    ret (builder.global_count - 1usize, ok)
}

// Where each global sits within the data area, and how big the whole of it is. One answer for
// every consumer -- both linkers and the emitters -- so a layout cannot drift between them.
fn global_area_offset(builder: *Builder, index: usize) -> usize {
    var offset = 0usize
    var at = 0usize
    while at < builder.global_count {
        let item = builder.globals[at]
        var alignment = item.alignment
        if alignment == 0usize { alignment = 1usize }
        let remainder = offset % alignment
        if remainder != 0usize { offset = offset + alignment - remainder }
        if at == index { ret offset }
        offset = offset + item.size
        at += 1usize
    }
    ret offset
}

fn global_area_size(builder: *Builder) -> usize {
    if builder.global_count == 0usize { ret 0usize }
    let last = builder.global_count - 1usize
    ret global_area_offset(builder, last) + builder.globals[last].size
}

// The two opcodes that name a function: a call, and taking its address. `e.os.thread_create` hands
// an entry point over as a value, so following calls alone would drop a function that is very much
// reached -- just not by a call site in this image.
fn references_function(opcode: Opcode) -> bool {
    ret opcode == .Call || opcode == .FunctionAddress
}

// Every reference matched to its function once, by one pass over the functions (D306):
// `prune_unreachable` and `codegen_x64.resolve_calls` then read the answer instead of
// scanning the functions per call instruction and per relocation.
fn resolve_reference_targets(builder: *Builder) {
    if builder.targets_preset { ret }
    var at = 0usize
    while at < builder.function_ref_count {
        builder.function_refs[at].has_target = false
        at += 1usize
    }
    var function_at = 0usize
    while function_at < builder.function_count {
        let candidate = builder.functions[function_at]
        let (reference_index, found) = find_reference(builder, candidate.module_index, candidate.name, candidate.instance)
        if found && !builder.function_refs[reference_index].has_target {
            builder.function_refs[reference_index].target = function_at
            builder.function_refs[reference_index].has_target = true
        }
        function_at += 1usize
    }
    // A program linked from artifacts carries the same reference more than once, one
    // per artifact that made it; the later ones take the first one's target.
    at = 0usize
    while at < builder.function_ref_count {
        if !builder.function_refs[at].has_target {
            let reference = builder.function_refs[at]
            let (first, found) = find_reference(builder, reference.module_index, reference.name, reference.instance)
            if found && first != at && builder.function_refs[first].has_target {
                builder.function_refs[at].target = builder.function_refs[first].target
                builder.function_refs[at].has_target = true
            }
        }
        at += 1usize
    }
}

// The reference naming a function, through the index when there is one.
fn find_reference(builder: *Builder, module_index: usize, name: str, instance: usize) -> (usize, bool) {
    if index_references(builder) {
        let (found_at, found) = lookup.find(&builder.ref_names, module_index, instance, name)
        ret (found_at, found)
    }
    var at = 0usize
    while at < builder.function_ref_count {
        let reference = builder.function_refs[at]
        if reference.module_index == module_index && reference.instance == instance && check.same(reference.name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn function_for_reference(builder: *Builder, reference: FunctionRef) -> (usize, bool) {
    if reference.has_target { ret (reference.target, true) }
    ret (0usize, false)
}

// Everything `main` can reach, and nothing else. Done here rather than while lowering because the
// order functions are emitted in has to stay exactly what it was: an image linked from `.em`
// artifacts must come out byte for byte the same as one compiled from source, and that holds only
// if both drop the same functions from the same sequence rather than building a new one.
//
// A function whose body was lowered still contributes its own references, so a walk has to start
// at `main` and follow edges -- asking "is this referenced anywhere" would answer yes for
// everything, since dead code refers to things too.
// An inlined callee's own definition stays in an artifact: its Interface hashes the NIR,
// which the body edge a dependent recorded is compared against (D207). An executable
// drops it like any other unreached function, on both link paths alike.
fn inlined_function(builder: *Builder, function: Function) -> bool {
    var at = 0usize
    while at < builder.inlined_count {
        let entry = builder.inlined[at]
        if entry.callee_module == function.module_index && entry.instance == function.instance && check.same(entry.name, function.name) { ret true }
        at += 1usize
    }
    ret false
}

fn prune_unreachable(builder: *Builder, keep: []bool, keep_inlined: bool) -> err {
    resolve_reference_targets(builder)
    if builder.function_count > keep.len { ret Capacity }
    var at = 0usize
    while at < builder.function_count {
        keep[at] = keep_inlined && inlined_function(builder, builder.functions[at])
        at += 1usize
    }
    var root = 0usize
    var rooted = false
    at = 0usize
    while at < builder.function_count {
        if check.same(builder.functions[at].name, "main") {
            root = at
            rooted = true
            break
        }
        at += 1usize
    }
    // No entry point is not this function's problem to report: the linker says so, with a better
    // message than a program of no functions would produce.
    if !rooted { ret ok }
    keep[root] = true
    var progress = true
    while progress {
        progress = false
        var function_at = 0usize
        while function_at < builder.function_count {
            if keep[function_at] {
                let item = builder.functions[function_at]
                var instruction_at = 0usize
                while instruction_at < item.instruction_count {
                    let instruction = builder.instructions[item.first_instruction + instruction_at]
                    if references_function(instruction.opcode) && instruction.immediate < builder.function_ref_count {
                        let (callee, found) = function_for_reference(builder, builder.function_refs[instruction.immediate])
                        if found && !keep[callee] {
                            keep[callee] = true
                            progress = true
                        }
                    }
                    instruction_at += 1usize
                }
            }
            function_at += 1usize
        }
    }
    // Compacted in place, which keeps what survives in the order it was already in.
    var written = 0usize
    at = 0usize
    while at < builder.function_count {
        if keep[at] {
            builder.functions[written] = builder.functions[at]
            written += 1usize
        }
        at += 1usize
    }
    builder.function_count = written
    ret prune_references(builder)
}

// The references a dead function made die with it. This matters beyond tidiness: the imports an
// image asks its loader for are enumerated from this list, so a reference left behind by a
// function nobody calls still puts `DT_NEEDED` in the file -- which is how a program whose only
// `e.os` call was `os.exit` came to depend on libc.
//
// Compacting means the surviving instructions' immediates have to be renumbered, since a
// reference is named by its index.
fn prune_references(builder: *Builder) -> err {
    if builder.function_ref_count == 0usize { ret ok }
    // Marked by walking what is left, which is exactly the set that survived the prune above.
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        builder.function_refs[reference_at].live = false
        reference_at += 1usize
    }
    var function_at = 0usize
    while function_at < builder.function_count {
        let item = builder.functions[function_at]
        var instruction_at = 0usize
        while instruction_at < item.instruction_count {
            let instruction = builder.instructions[item.first_instruction + instruction_at]
            if references_function(instruction.opcode) && instruction.immediate < builder.function_ref_count {
                builder.function_refs[instruction.immediate].live = true
            }
            instruction_at += 1usize
        }
        function_at += 1usize
    }
    assign_reference_numbers(builder)
    // The instructions are renumbered before anything moves. Doing it the other way round reads a
    // mapping out of a slot a later reference has already been moved into, which points a call --
    // or a callback, since taking an address is the same edge -- at the wrong function.
    function_at = 0usize
    while function_at < builder.function_count {
        let item = builder.functions[function_at]
        var instruction_at = 0usize
        while instruction_at < item.instruction_count {
            let position = item.first_instruction + instruction_at
            let instruction = builder.instructions[position]
            if references_function(instruction.opcode) && instruction.immediate < builder.function_ref_count {
                builder.instructions[position].immediate = builder.function_refs[instruction.immediate].renumbered
            }
            instruction_at += 1usize
        }
        function_at += 1usize
    }
    // Only now is the array compacted, which cannot disturb a mapping that has already been used.
    ret compact_references(builder)
}

// Where each surviving reference will end up, recorded in the slot it still occupies.
fn assign_reference_numbers(builder: *Builder) {
    var written = 0usize
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        if builder.function_refs[reference_at].live {
            builder.function_refs[reference_at].renumbered = written
            written += 1usize
        }
        reference_at += 1usize
    }
}

// The live references moved down over the dead ones, after every carrier of a reference
// index has been renumbered.
fn compact_references(builder: *Builder) -> err {
    var moved_to = 0usize
    var reference_at = 0usize
    while reference_at < builder.function_ref_count {
        if builder.function_refs[reference_at].live {
            builder.function_refs[moved_to] = builder.function_refs[reference_at]
            moved_to += 1usize
        }
        reference_at += 1usize
    }
    builder.function_ref_count = moved_to
    builder.imports_ordered = false
    builder.used_marks_valid = false
    // The references moved, so the name index over them is rebuilt from nothing the
    // next time one is asked for (D306).
    if lookup.attached(&builder.ref_names) { try lookup.attach(&builder.ref_names, builder.ref_names.entries) }
    ret ok
}

fn is_terminator(opcode: Opcode) -> bool {
    ret opcode == .Trap || opcode == .Branch || opcode == .BranchIf || opcode == .Switch || opcode == .Return || opcode == .Unreachable
}

fn init(builder: *Builder, functions: []Function, blocks: []Block, instructions: []Instruction, operands: []usize, function_refs: []FunctionRef, strings: []StringConstant) -> err {
    if functions.len == 0usize || blocks.len == 0usize || instructions.len == 0usize || operands.len == 0usize || function_refs.len == 0usize || strings.len == 0usize { ret Capacity }
    builder.functions = functions
    builder.blocks = blocks
    builder.instructions = instructions
    builder.operands = operands
    builder.function_refs = function_refs
    builder.strings = strings
    builder.function_count = 0usize
    builder.block_count = 0usize
    builder.instruction_count = 0usize
    builder.operand_count = 0usize
    builder.function_ref_count = 0usize
    builder.ref_names.entries = builder.ref_names.entries[0usize..0usize]
    builder.string_names.entries = builder.string_names.entries[0usize..0usize]
    builder.runtime_prefix = 0usize
    builder.string_count = 0usize
    builder.current_function = 0usize
    builder.current_block = 0usize
    builder.next_value = 0usize
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn init_signatures(signatures: *Signatures, entries: []Signature, types: []check.Type) -> err {
    if entries.len == 0usize || types.len == 0usize { ret Capacity }
    signatures.entries = entries
    signatures.types = types
    signatures.count = 0usize
    ret ok
}

fn attach_indexes(builder: *Builder, ref_entries: []lookup.Entry, string_entries: []lookup.Entry) -> err {
    try lookup.attach(&builder.ref_names, ref_entries)
    ret lookup.attach(&builder.string_names, string_entries)
}

// Brings the reference index up to the table; answers whether it is complete.
fn index_references(builder: *Builder) -> bool {
    if !lookup.attached(&builder.ref_names) { ret false }
    while builder.ref_names.indexed[0usize] < builder.function_ref_count {
        let row = builder.ref_names.indexed[0usize]
        let insert_error = lookup.insert(&builder.ref_names, builder.function_refs[row].module_index, builder.function_refs[row].instance, builder.function_refs[row].name, row)
        if insert_error != ok { ret false }
        builder.ref_names.indexed[0usize] = row + 1usize
    }
    ret true
}

fn intern_function(builder: *Builder, module_index: usize, name: str, instance: usize) -> (usize, err) {
    if lookup.attached(&builder.ref_names) {
        if index_references(builder) {
            let (found_at, found) = lookup.find(&builder.ref_names, module_index, instance, name)
            if found { ret (found_at, ok) }
            if builder.function_ref_count == builder.function_refs.len { ret (0usize, Capacity) }
            let index = builder.function_ref_count
            builder.function_refs[index] = FunctionRef { module_index: module_index, name: name, instance: instance, live: false, renumbered: 0usize, library: "", symbol: "", target: 0usize, has_target: false }
            builder.function_ref_count += 1usize
            ret (index, ok)
        }
    }
    var at = 0usize
    while at < builder.function_ref_count {
        let reference = builder.function_refs[at]
        if reference.module_index == module_index && reference.instance == instance && check.same(reference.name, name) { ret (at, ok) }
        at += 1usize
    }
    if builder.function_ref_count == builder.function_refs.len { ret (0usize, Capacity) }
    let index = builder.function_ref_count
    builder.function_refs[index] = FunctionRef { module_index: module_index, name: name, instance: instance, live: false, renumbered: 0usize, library: "", symbol: "", target: 0usize, has_target: false }
    builder.function_ref_count += 1usize
    ret (index, ok)
}

// The same reference, bound to an imported symbol. Interning is by neper-side name, so
// the library and symbol are attached to whichever entry that name resolves to.
fn intern_import(builder: *Builder, module_index: usize, name: str, library: str, symbol: str) -> (usize, err) {
    builder.imports_ordered = false
    let (index, intern_error) = intern_function(builder, module_index, name, 0usize)
    if intern_error != ok { ret (0usize, intern_error) }
    builder.function_refs[index].library = library
    builder.function_refs[index].symbol = symbol
    ret (index, ok)
}

// The imports a program needs the loader to bind, enumerated from the references
// themselves. Both linkers ask the same questions of the same two orders -- a library
// joins in the order its first reference appears, and a symbol in the order its first
// reference within that library does -- so the answers live here rather than in either
// of them. A symbol named twice is one entry: one slot, read by both calls.
fn imported_reference(builder: *Builder, index: usize) -> bool {
    ret index < builder.function_ref_count && builder.function_refs[index].library.len != 0usize
}

fn first_reference_for_library(builder: *Builder, index: usize) -> bool {
    if !imported_reference(builder, index) { ret false }
    var prior = 0usize
    while prior < index {
        if imported_reference(builder, prior) && check.same(builder.function_refs[prior].library, builder.function_refs[index].library) { ret false }
        prior += 1usize
    }
    ret true
}

fn first_reference_for_symbol(builder: *Builder, index: usize) -> bool {
    if !imported_reference(builder, index) { ret false }
    var prior = 0usize
    while prior < index {
        if imported_reference(builder, prior) && check.same(builder.function_refs[prior].library, builder.function_refs[index].library) && check.same(builder.function_refs[prior].symbol, builder.function_refs[index].symbol) { ret false }
        prior += 1usize
    }
    ret true
}

// The imports in name order (D319): each distinct library, and each distinct symbol
// within it, ordered by their bytes rather than by which reference came first. The
// source path interns an `@import` when it lowers the declaration and an artifact
// records it at its first call, so first-appearance order made an image linked from
// artifacts differ from the same program built from source by its import table alone.
// Insertion sorted: an image imports dozens of symbols, not thousands.
fn bytes_less(a: str, b: str) -> bool {
    var at = 0usize
    while at < a.len && at < b.len {
        if a[at] != b[at] { ret a[at] < b[at] }
        at += 1usize
    }
    ret a.len < b.len
}

fn import_before(builder: *Builder, left: usize, right: usize) -> bool {
    let a = builder.function_refs[left]
    let b = builder.function_refs[right]
    if !check.same(a.library, b.library) { ret bytes_less(a.library, b.library) }
    ret bytes_less(a.symbol, b.symbol)
}

fn order_imports(builder: *Builder) -> err {
    var count = 0usize
    var at = 0usize
    while at < builder.function_ref_count {
        if first_reference_for_symbol(builder, at) {
            if count == builder.import_order.len { ret Capacity }
            var slot = count
            while slot > 0usize && import_before(builder, at, builder.import_order[slot - 1usize]) {
                builder.import_order[slot] = builder.import_order[slot - 1usize]
                slot = slot - 1usize
            }
            builder.import_order[slot] = at
            count += 1usize
        }
        at += 1usize
    }
    builder.import_order_count = count
    builder.imports_ordered = true
    ret ok
}

// The ordered list is built the first time it is asked for.
fn ensure_import_order(builder: *Builder) {
    if !builder.imports_ordered { let ignored = order_imports(builder) }
}

fn import_library_count(builder: *Builder) -> usize {
    ensure_import_order(builder)
    var count = 0usize
    var at = 0usize
    while at < builder.import_order_count {
        let reference = builder.function_refs[builder.import_order[at]]
        if at == 0usize || !check.same(builder.function_refs[builder.import_order[at - 1usize]].library, reference.library) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn import_library_name(builder: *Builder, library: usize) -> str {
    ensure_import_order(builder)
    var remaining = library
    var at = 0usize
    while at < builder.import_order_count {
        let reference = builder.function_refs[builder.import_order[at]]
        if at == 0usize || !check.same(builder.function_refs[builder.import_order[at - 1usize]].library, reference.library) {
            if remaining == 0usize { ret reference.library }
            remaining = remaining - 1usize
        }
        at += 1usize
    }
    ret ""
}

fn import_symbol_count(builder: *Builder, library: usize) -> usize {
    let wanted = import_library_name(builder, library)
    var count = 0usize
    var at = 0usize
    while at < builder.import_order_count {
        if check.same(builder.function_refs[builder.import_order[at]].library, wanted) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn import_symbol_name(builder: *Builder, library: usize, entry: usize) -> str {
    let wanted = import_library_name(builder, library)
    var remaining = entry
    var at = 0usize
    while at < builder.import_order_count {
        let reference = builder.function_refs[builder.import_order[at]]
        if check.same(reference.library, wanted) {
            if remaining == 0usize { ret reference.symbol }
            remaining = remaining - 1usize
        }
        at += 1usize
    }
    ret ""
}

// Which library and which of its symbols a reference names.
fn import_slot_of(builder: *Builder, index: usize) -> (usize, usize, bool) {
    if !imported_reference(builder, index) { ret (0usize, 0usize, false) }
    let reference = builder.function_refs[index]
    var library = 0usize
    while library < import_library_count(builder) {
        if check.same(import_library_name(builder, library), reference.library) {
            var entry = 0usize
            while entry < import_symbol_count(builder, library) {
                if check.same(import_symbol_name(builder, library, entry), reference.symbol) { ret (library, entry, true) }
                entry += 1usize
            }
        }
        library += 1usize
    }
    ret (0usize, 0usize, false)
}

// Every imported symbol laid end to end, which is the order a single table -- an ELF
// `.dynsym` and the slots beside it -- puts them in.
fn import_symbol_total(builder: *Builder) -> usize {
    var total = 0usize
    var library = 0usize
    while library < import_library_count(builder) {
        total += import_symbol_count(builder, library)
        library += 1usize
    }
    ret total
}

fn import_flat_index(builder: *Builder, library: usize, entry: usize) -> usize {
    var index = entry
    var at = 0usize
    while at < library {
        index += import_symbol_count(builder, at)
        at += 1usize
    }
    ret index
}

fn intern_string(builder: *Builder, spelling: str) -> (usize, err) {
    if lookup.attached(&builder.string_names) {
        while builder.string_names.indexed[0usize] < builder.string_count {
            let row = builder.string_names.indexed[0usize]
            let insert_error = lookup.insert(&builder.string_names, 0usize, 0usize, builder.strings[row].spelling, row)
            if insert_error != ok { break }
            builder.string_names.indexed[0usize] = row + 1usize
        }
        if builder.string_names.indexed[0usize] == builder.string_count {
            let (found_at, found) = lookup.find(&builder.string_names, 0usize, 0usize, spelling)
            if found { ret (found_at, ok) }
            if builder.string_count == builder.strings.len { ret (0usize, Capacity) }
            let index = builder.string_count
            builder.strings[index] = StringConstant { spelling: spelling }
            builder.string_count += 1usize
            ret (index, ok)
        }
    }
    var at = 0usize
    while at < builder.string_count {
        if check.same(builder.strings[at].spelling, spelling) { ret (at, ok) }
        at += 1usize
    }
    if builder.string_count == builder.strings.len { ret (0usize, Capacity) }
    let index = builder.string_count
    builder.strings[index] = StringConstant { spelling: spelling }
    builder.string_count += 1usize
    ret (index, ok)
}

fn begin_function(builder: *Builder, module_index: usize, name: str, instance: usize) -> (usize, err) {
    if builder.function_active { ret (0usize, InvalidControlFlow) }
    if builder.function_count == builder.functions.len { ret (0usize, Capacity) }
    let index = builder.function_count
    builder.functions[index] = Function {
        name: name,
        module_index: module_index,
        instance: instance,
        path: "",
        module_name: "",
        first_block: builder.block_count,
        block_count: 0usize,
        first_instruction: builder.instruction_count,
        instruction_count: 0usize,
        value_count: 0usize,
    }
    builder.function_count += 1usize
    builder.current_function = index
    builder.next_value = 0usize
    builder.function_active = true
    builder.block_active = false
    ret (index, ok)
}

fn begin_signature(builder: *Builder, function_index: usize, signatures: *Signatures) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len { ret InvalidControlFlow }
    signatures.entries[function_index] = Signature { first_parameter_type: signatures.count, parameter_count: 0usize, first_return_type: signatures.count, return_count: 0usize }
    ret ok
}

fn add_parameter_type(builder: *Builder, function_index: usize, signatures: *Signatures, ty: check.Type) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len || signatures.entries[function_index].return_count != 0usize { ret InvalidControlFlow }
    if signatures.count == signatures.types.len { ret Capacity }
    signatures.types[signatures.count] = ty
    signatures.count += 1usize
    signatures.entries[function_index].parameter_count += 1usize
    signatures.entries[function_index].first_return_type = signatures.count
    ret ok
}

fn add_return_type(builder: *Builder, function_index: usize, signatures: *Signatures, ty: check.Type) -> err {
    if !builder.function_active || function_index != builder.current_function || function_index >= signatures.entries.len { ret InvalidControlFlow }
    if signatures.count == signatures.types.len { ret Capacity }
    signatures.types[signatures.count] = ty
    signatures.count += 1usize
    signatures.entries[function_index].return_count += 1usize
    ret ok
}

fn begin_block(builder: *Builder) -> (usize, err) {
    if !builder.function_active { ret (0usize, InvalidControlFlow) }
    if builder.block_active && !builder.blocks[builder.current_block].terminated { ret (0usize, InvalidControlFlow) }
    if builder.block_count == builder.blocks.len { ret (0usize, Capacity) }
    let index = builder.block_count
    builder.blocks[index] = Block { first_instruction: builder.instruction_count, instruction_count: 0usize, terminated: false }
    builder.block_count += 1usize
    builder.current_block = index
    builder.block_active = true
    builder.functions[builder.current_function].block_count += 1usize
    ret (index, ok)
}

fn emit(builder: *Builder, opcode: Opcode, ty: check.Type, has_result: bool, immediate: usize, token: lex.Token) -> (usize, usize, err) {
    if !builder.function_active || !builder.block_active || builder.blocks[builder.current_block].terminated || opcode == .Invalid { ret (0usize, 0usize, InvalidControlFlow) }
    if builder.instruction_count == builder.instructions.len { ret (0usize, 0usize, Capacity) }
    if builder.instruction_limit != 0usize && builder.instruction_count - builder.limit_base >= builder.instruction_limit { ret (0usize, 0usize, TooLong) }
    let instruction_index = builder.instruction_count
    var result = 0usize
    if has_result {
        result = builder.next_value
        builder.next_value += 1usize
    }
    builder.instructions[instruction_index] = Instruction {
        opcode: opcode,
        result: result,
        has_result: has_result,
        ty: ty,
        first_operand: builder.operand_count,
        operand_count: 0usize,
        immediate: immediate,
        target: 0usize,
        target2: 0usize,
        site: site_of(builder, token),
        nocheck: builder.nocheck,
        inline_origin: 0u32,
        path: builder.current_path,
    }
    builder.instruction_count += 1usize
    builder.blocks[builder.current_block].instruction_count += 1usize
    builder.functions[builder.current_function].instruction_count += 1usize
    if is_terminator(opcode) { builder.blocks[builder.current_block].terminated = true }
    ret (instruction_index, result, ok)
}

fn add_operand(builder: *Builder, instruction_index: usize, value: usize) -> err {
    if instruction_index >= builder.instruction_count || instruction_index + 1usize != builder.instruction_count { ret InvalidValue }
    if value >= builder.next_value { ret InvalidValue }
    let instruction = builder.instructions[instruction_index]
    if instruction.has_result && instruction.result == value { ret InvalidValue }
    if builder.operand_count == builder.operands.len { ret Capacity }
    builder.operands[builder.operand_count] = value
    builder.operand_count += 1usize
    builder.instructions[instruction_index].operand_count += 1usize
    ret ok
}

fn set_branch_targets(builder: *Builder, instruction_index: usize, destination: usize, destination2: usize) -> err {
    if !builder.function_active || instruction_index < builder.functions[builder.current_function].first_instruction || instruction_index >= builder.instruction_count { ret InvalidControlFlow }
    let opcode = builder.instructions[instruction_index].opcode
    if opcode != .Branch && opcode != .BranchIf { ret InvalidControlFlow }
    builder.instructions[instruction_index].target = destination
    if opcode == .BranchIf { builder.instructions[instruction_index].target2 = destination2 }
    ret ok
}

fn validate_target(function: Function, destination: usize) -> bool {
    ret destination >= function.first_block && destination < function.first_block + function.block_count
}

fn validate_function(builder: *Builder, function: Function) -> err {
    let block_end = function.first_block + function.block_count
    var block_at = function.first_block
    while block_at < block_end {
        let block = builder.blocks[block_at]
        if !block.terminated || block.instruction_count == 0usize { ret InvalidControlFlow }
        let terminator_index = block.first_instruction + block.instruction_count - 1usize
        let terminator = builder.instructions[terminator_index]
        if terminator.opcode == .Branch {
            if !validate_target(function, terminator.target) { ret InvalidControlFlow }
        } else {
            if terminator.opcode == .BranchIf {
                if !validate_target(function, terminator.target) || !validate_target(function, terminator.target2) { ret InvalidControlFlow }
            }
        }
        block_at += 1usize
    }
    ret ok
}

// The verifier at the lowering boundary (D342, H10): beyond the terminators and
// targets `validate_function` checks, every value is defined once, by the instruction
// that carries it, before any use in program order and in a block that dominates the
// use's; every operand is a value of the function; a `BranchIf` tests a bool and has
// one operand; the two-operand arithmetic and comparisons have two. A function that fails is refused as `Unverified`, and a
// build that reaches the refusal writes nothing. The dominators come from the
// iterative algorithm over a reverse postorder, with predecessors listed once.
error Unverified

fn verify_function(builder: *Builder, function: Function) -> err {
    let block_count = function.block_count
    let value_count = function.value_count
    let scratch = builder.verify_scratch
    // The scratch, in slices: definer block and instruction per value; per block its
    // reverse-postorder index, its idom, its predecessor start and count, and a seen;
    // then the predecessor list (two per block at most) and a stack.
    let need = value_count * 2usize + block_count * 8usize + 16usize
    if need > scratch.len { ret ok }
    let definer_block = scratch[0usize..value_count]
    let definer_index = scratch[value_count..value_count * 2usize]
    var at = value_count * 2usize
    let order = scratch[at..at + block_count]
    at += block_count
    let idom = scratch[at..at + block_count]
    at += block_count
    let pred_start = scratch[at..at + block_count]
    at += block_count
    let pred_count = scratch[at..at + block_count]
    at += block_count
    let seen = scratch[at..at + block_count]
    at += block_count
    let preds = scratch[at..at + block_count * 2usize]
    at += block_count * 2usize
    let stack = scratch[at..at + block_count]
    let none = block_count + 1usize
    var value = 0usize
    while value < value_count {
        definer_block[value] = none
        definer_index[value] = 0usize
        value += 1usize
    }
    var block_at = 0usize
    while block_at < block_count {
        pred_count[block_at] = 0usize
        seen[block_at] = 0usize
        idom[block_at] = none
        order[block_at] = none
        block_at += 1usize
    }
    // Definers, and the predecessor counts from the terminators.
    block_at = 0usize
    while block_at < block_count {
        let block = builder.blocks[function.first_block + block_at]
        var i = block.first_instruction
        let end = block.first_instruction + block.instruction_count
        while i < end {
            let instruction = builder.instructions[i]
            if instruction.has_result {
                if instruction.result >= value_count || definer_block[instruction.result] != none { ret refuse(builder, i, 0usize) }
                definer_block[instruction.result] = block_at
                definer_index[instruction.result] = i
            }
            i += 1usize
        }
        let terminator = builder.instructions[end - 1usize]
        if terminator.opcode == .Branch || terminator.opcode == .BranchIf {
            pred_count[terminator.target - function.first_block] += 1usize
            if terminator.opcode == .BranchIf { pred_count[terminator.target2 - function.first_block] += 1usize }
        }
        block_at += 1usize
    }
    var filled = 0usize
    block_at = 0usize
    while block_at < block_count {
        pred_start[block_at] = filled
        filled += pred_count[block_at]
        pred_count[block_at] = 0usize
        block_at += 1usize
    }
    block_at = 0usize
    while block_at < block_count {
        let block = builder.blocks[function.first_block + block_at]
        let terminator = builder.instructions[block.first_instruction + block.instruction_count - 1usize]
        if terminator.opcode == .Branch || terminator.opcode == .BranchIf {
            let t1 = terminator.target - function.first_block
            preds[pred_start[t1] + pred_count[t1]] = block_at
            pred_count[t1] += 1usize
            if terminator.opcode == .BranchIf {
                let t2 = terminator.target2 - function.first_block
                preds[pred_start[t2] + pred_count[t2]] = block_at
                pred_count[t2] += 1usize
            }
        }
        block_at += 1usize
    }
    // Reverse postorder by an explicit stack: a block is numbered when its
    // successors have been; `seen` is 0 unseen, 1 on the stack, 2 numbered.
    var numbered = block_count
    var top = 0usize
    stack[0usize] = 0usize
    seen[0usize] = 1usize
    top = 1usize
    while top > 0usize {
        let b = stack[top - 1usize]
        let block = builder.blocks[function.first_block + b]
        let terminator = builder.instructions[block.first_instruction + block.instruction_count - 1usize]
        var pushed = false
        if terminator.opcode == .Branch || terminator.opcode == .BranchIf {
            let s1 = terminator.target - function.first_block
            if seen[s1] == 0usize {
                seen[s1] = 1usize
                stack[top] = s1
                top += 1usize
                pushed = true
            } else {
                if terminator.opcode == .BranchIf {
                    let s2 = terminator.target2 - function.first_block
                    if seen[s2] == 0usize {
                        seen[s2] = 1usize
                        stack[top] = s2
                        top += 1usize
                        pushed = true
                    }
                }
            }
        }
        if !pushed {
            top = top - 1usize
            seen[b] = 2usize
            numbered = numbered - 1usize
            order[b] = numbered
        }
    }
    // The blocks by rank, in the stack's words, which the search is done with.
    let by_rank = stack
    block_at = 0usize
    while block_at < block_count {
        by_rank[block_at] = none
        block_at += 1usize
    }
    block_at = 0usize
    while block_at < block_count {
        if seen[block_at] == 2usize { by_rank[order[block_at]] = block_at }
        block_at += 1usize
    }
    // Dominators, iterated to a fixed point over the reachable blocks in reverse
    // postorder; an unreachable block has no dominator and its values dominate nothing.
    idom[0usize] = 0usize
    var changed = true
    while changed {
        changed = false
        var rank = 0usize
        while rank < block_count {
            let b = by_rank[rank]
            if b != none && b != 0usize {
                var candidate = none
                var p = 0usize
                while p < pred_count[b] {
                    let pred = preds[pred_start[b] + p]
                    if idom[pred] != none {
                        if candidate == none {
                            candidate = pred
                        } else {
                            candidate = intersect(order, idom, candidate, pred)
                        }
                    }
                    p += 1usize
                }
                if candidate != none && idom[b] != candidate {
                    idom[b] = candidate
                    changed = true
                }
            }
            rank += 1usize
        }
    }
    // Every use.
    block_at = 0usize
    while block_at < block_count {
        let block = builder.blocks[function.first_block + block_at]
        var i = block.first_instruction
        let end = block.first_instruction + block.instruction_count
        while i < end {
            let instruction = builder.instructions[i]
            var o = 0usize
            while o < instruction.operand_count {
                let operand = builder.operands[instruction.first_operand + o]
                if operand >= value_count || definer_block[operand] == none { ret refuse(builder, i, o) }
                let d = definer_block[operand]
                if d == block_at {
                    if definer_index[operand] >= i { ret refuse(builder, i, o) }
                } else {
                    if !dominates(idom, d, block_at, none) {
                        ret refuse(builder, i, o)
                    }
                }
                o += 1usize
            }
            if instruction.opcode == .BranchIf {
                if instruction.operand_count != 1usize { ret refuse(builder, i, 0usize) }
                let condition = builder.instructions[definer_index[builder.operands[instruction.first_operand]]]
                if condition.ty.kind != .Bool { ret refuse(builder, i, 0usize) }
            }
            if is_binary(instruction.opcode) && instruction.operand_count != 2usize { ret refuse(builder, i, 0usize) }
            i += 1usize
        }
        block_at += 1usize
    }
    ret ok
}


fn refuse(builder: *Builder, instruction: usize, operand: usize) -> err {
    builder.verify_instruction = instruction
    builder.verify_operand = operand
    ret Unverified
}

fn is_binary(opcode: Opcode) -> bool {
    ret opcode == .Add || opcode == .Subtract || opcode == .Multiply || opcode == .Divide || opcode == .Remainder || opcode == .AddWrap || opcode == .SubtractWrap || opcode == .MultiplyWrap || opcode == .ShiftLeft || opcode == .ShiftRight || opcode == .BitAnd || opcode == .BitXor || opcode == .BitOr || opcode == .Equal || opcode == .NotEqual || opcode == .Less || opcode == .LessEqual || opcode == .Greater || opcode == .GreaterEqual
}

// The nearest common dominator of two blocks, by their reverse-postorder ranks.
fn intersect(order: []usize, idom: []usize, a: usize, b: usize) -> usize {
    var x = a
    var y = b
    var steps = 0usize
    while x != y {
        while order[x] > order[y] {
            x = idom[x]
            steps += 1usize
            if steps > order.len * 2usize { ret x }
        }
        while order[y] > order[x] {
            y = idom[y]
            steps += 1usize
            if steps > order.len * 2usize { ret y }
        }
    }
    ret x
}

// Whether `d` dominates `b`: `d` is on `b`'s idom chain.
fn dominates(idom: []usize, d: usize, b: usize, none: usize) -> bool {
    var at = b
    var steps = 0usize
    while steps <= idom.len {
        if at == d { ret true }
        if at == 0usize || idom[at] == none { ret false }
        at = idom[at]
        steps += 1usize
    }
    ret false
}

// Where the builder stands, and back to it (D310): what an oracle lowered and cannot
// inline is discarded rather than kept. References and strings interned meanwhile
// stay -- they are names, and the indexes over them would otherwise point past the
// table.
type Mark = struct {
    function_count: usize,
    block_count: usize,
    instruction_count: usize,
    operand_count: usize,
    inlined_count: usize,
    inline_origin_count: usize,
}

fn mark(builder: *Builder) -> Mark {
    ret Mark { function_count: builder.function_count, block_count: builder.block_count, instruction_count: builder.instruction_count, operand_count: builder.operand_count, inlined_count: builder.inlined_count, inline_origin_count: builder.inline_origin_count }
}

fn reset(builder: *Builder, at: Mark) {
    builder.function_count = at.function_count
    builder.block_count = at.block_count
    builder.instruction_count = at.instruction_count
    builder.operand_count = at.operand_count
    builder.inlined_count = at.inlined_count
    builder.inline_origin_count = at.inline_origin_count
    builder.function_active = false
    builder.block_active = false
}

// A module's bodies, once its code is emitted, are not needed again (D314): the blocks,
// instructions and operands since the mark go, and the functions, references, strings
// and globals stay, since the link reads those. The function headers left behind
// point into space the next module reuses, and nothing reads them.
fn discard_bodies(builder: *Builder, at: Mark) {
    let held = builder.instruction_count - at.instruction_count
    builder.instruction_total += held
    if held > builder.instruction_peak { builder.instruction_peak = held }
    builder.block_total += builder.block_count - at.block_count
    builder.operand_total += builder.operand_count - at.operand_count
    builder.block_count = at.block_count
    builder.instruction_count = at.instruction_count
    builder.operand_count = at.operand_count
    builder.function_active = false
    builder.block_active = false
}

// Where a token lies in the module being lowered, as the trap record and the line table
// name it. A copied instruction keeps its own site (`emit_at`): it came from another
// module's text.
fn site_of(builder: *Builder, token: lex.Token) -> Site {
    var site: Site = zero
    site.start = token.start
    site.end = token.end
    // A zero token is no token: the synthesized functions emit with one, and their
    // instructions have no line -- a real token ends past byte 0.
    if token.end != 0usize && token.start <= builder.current_text.len {
        if builder.site_line == 0usize || token.start < builder.site_line_start || token.start >= builder.site_line_end {
            let line = lex.line_of(builder.current_text, builder.current_lines, token.start)
            builder.site_line = line
            builder.site_line_start = 0usize
            builder.site_line_end = builder.current_text.len + 1usize
            if line - 1usize < builder.current_lines.len { builder.site_line_start = builder.current_lines[line - 1usize] }
            if line < builder.current_lines.len { builder.site_line_end = builder.current_lines[line] }
        }
        site.line = builder.site_line
        site.column = lex.column_from(builder.current_text, builder.site_line_start, token.start)
    }
    ret site
}

// `emit` with a site already known: the inliner's copies keep the callee's positions.
fn emit_at(builder: *Builder, opcode: Opcode, ty: check.Type, has_result: bool, immediate: usize, site: Site) -> (usize, usize, err) {
    let (instruction, result, emit_error) = emit(builder, opcode, ty, has_result, immediate, site_token(site))
    if emit_error != ok { ret (instruction, result, emit_error) }
    builder.instructions[instruction].site = site
    ret (instruction, result, ok)
}

fn end_function(builder: *Builder) -> err {
    if !builder.function_active || !builder.block_active || !builder.blocks[builder.current_block].terminated { ret InvalidControlFlow }
    builder.functions[builder.current_function].value_count = builder.next_value
    try validate_function(builder, builder.functions[builder.current_function])
    if builder.verify_scratch.len != 0usize { try verify_function(builder, builder.functions[builder.current_function]) }
    builder.function_active = false
    builder.block_active = false
    ret ok
}

fn self_test() -> err {
    var functions: [1]Function = zero
    var blocks: [1]Block = zero
    var instructions: [4]Instruction = zero
    var operands: [4]usize = zero
    var function_refs: [1]FunctionRef = zero
    var strings: [1]StringConstant = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..], function_refs[..], strings[..])
    let (function_ref, function_ref_error) = intern_function(&builder, 1usize, "callee", 0usize)
    if function_ref_error != ok || function_ref != 0usize { ret InvalidValue }
    let (same_function_ref, same_function_ref_error) = intern_function(&builder, 1usize, "callee", 0usize)
    if same_function_ref_error != ok || same_function_ref != function_ref || builder.function_ref_count != 1usize { ret InvalidValue }
    let (string_index, string_error) = intern_string(&builder, "\"value\"")
    if string_error != ok || string_index != 0usize { ret InvalidValue }
    let (same_string_index, same_string_error) = intern_string(&builder, "\"value\"")
    if same_string_error != ok || same_string_index != string_index || builder.string_count != 1usize { ret InvalidValue }
    let (function_index, function_error) = begin_function(&builder, 0usize, "main", 0usize)
    if function_error != ok || function_index != 0usize { ret InvalidControlFlow }
    let (block_index, block_error) = begin_block(&builder)
    if block_error != ok || block_index != 0usize { ret InvalidControlFlow }
    var integer: check.Type = zero
    integer.kind = .Integer
    integer.name = "i64"
    let (parameter_instruction, parameter, parameter_error) = emit(&builder, .Parameter, integer, true, 0usize, zero)
    if parameter_error != ok || parameter_instruction != 0usize || parameter != 0usize { ret InvalidValue }
    let (constant_instruction, constant, constant_error) = emit(&builder, .ConstInteger, integer, true, 7usize, zero)
    if constant_error != ok || constant_instruction != 1usize || constant != 1usize { ret InvalidValue }
    let (add_instruction, sum, add_error) = emit(&builder, .Add, integer, true, 0usize, zero)
    if add_error != ok || sum != 2usize { ret InvalidValue }
    try add_operand(&builder, add_instruction, parameter)
    try add_operand(&builder, add_instruction, constant)
    let (return_instruction, ignored, return_error) = emit(&builder, .Return, integer, false, 0usize, zero)
    if return_error != ok { ret return_error }
    try add_operand(&builder, return_instruction, sum)
    try end_function(&builder)
    if builder.function_count != 1usize || builder.block_count != 1usize || builder.instruction_count != 4usize || builder.operand_count != 3usize { ret InvalidValue }
    if builder.functions[0usize].value_count != 3usize || builder.blocks[0usize].instruction_count != 4usize || !builder.blocks[0usize].terminated { ret InvalidValue }
    let (invalid_instruction, invalid_result, invalid_error) = emit(&builder, .ConstInteger, integer, true, 0usize, zero)
    if invalid_error != InvalidControlFlow { ret InvalidControlFlow }
    ret ok
}

// The verifier refuses a use no definition dominates (D342): block 0 branches on a
// bool to block 1, which defines a value and falls to block 2, or straight to block
// 2, which returns the value; and passes the same function with the value defined
// in block 0.
fn verify_self_test() -> err {
    var functions: [2]Function = zero
    var blocks: [8]Block = zero
    var instructions: [16]Instruction = zero
    var operands: [16]usize = zero
    var function_refs: [1]FunctionRef = zero
    var strings: [1]StringConstant = zero
    var scratch: [128]usize = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..], function_refs[..], strings[..])
    builder.verify_scratch = scratch[..]
    var integer: check.Type = zero
    integer.kind = .Integer
    integer.name = "i64"
    var boolean: check.Type = zero
    boolean.kind = .Bool
    boolean.name = "bool"
    var shape = 0usize
    while shape < 2usize {
        let (function_index, function_error) = begin_function(&builder, 0usize, "probe", 0usize)
        if function_error != ok { ret function_error }
        let (entry, entry_error) = begin_block(&builder)
        if entry_error != ok { ret entry_error }
        var early = 0usize
        if shape == 1usize {
            let (early_instruction, early_value, early_error) = emit(&builder, .ConstInteger, integer, true, 7usize, zero)
            if early_error != ok { ret early_error }
            early = early_value
        }
        let (condition_instruction, condition, condition_error) = emit(&builder, .ConstBool, boolean, true, 1usize, zero)
        if condition_error != ok { ret condition_error }
        let (branch_instruction, ignored_branch, branch_error) = emit(&builder, .BranchIf, zero, false, 0usize, zero)
        if branch_error != ok { ret branch_error }
        try add_operand(&builder, branch_instruction, condition)
        let (defining, defining_error) = begin_block(&builder)
        if defining_error != ok { ret defining_error }
        let (late_instruction, late, late_error) = emit(&builder, .ConstInteger, integer, true, 9usize, zero)
        if late_error != ok { ret late_error }
        let (jump_instruction, ignored_jump, jump_error) = emit(&builder, .Branch, zero, false, 0usize, zero)
        if jump_error != ok { ret jump_error }
        let (merge, merge_error) = begin_block(&builder)
        if merge_error != ok { ret merge_error }
        let (return_instruction, ignored_return, return_error) = emit(&builder, .Return, integer, false, 0usize, zero)
        if return_error != ok { ret return_error }
        if shape == 0usize { try add_operand(&builder, return_instruction, late) } else { try add_operand(&builder, return_instruction, early) }
        try set_branch_targets(&builder, branch_instruction, defining, merge)
        try set_branch_targets(&builder, jump_instruction, merge, merge)
        let ended = end_function(&builder)
        if shape == 0usize {
            if ended != Unverified || builder.verify_instruction != return_instruction { ret InvalidValue }
            builder.function_active = false
            builder.block_active = false
        } else {
            if ended != ok { ret ended }
        }
        shape += 1usize
    }
    ret ok
}

fn signature_self_test() -> err {
    var functions: [1]Function = zero
    var blocks: [1]Block = zero
    var instructions: [1]Instruction = zero
    var operands: [1]usize = zero
    var function_refs: [1]FunctionRef = zero
    var strings: [1]StringConstant = zero
    var builder: Builder = zero
    try init(&builder, functions[..], blocks[..], instructions[..], operands[..], function_refs[..], strings[..])
    var signature_types: [2]check.Type = zero
    var signature_entries: [1]Signature = zero
    var signatures: Signatures = zero
    try init_signatures(&signatures, signature_entries[..], signature_types[..])
    var integer: check.Type = zero
    integer.kind = .Integer
    integer.name = "i64"
    let (function_index, function_error) = begin_function(&builder, 0usize, "main", 0usize)
    if function_error != ok { ret function_error }
    try begin_signature(&builder, function_index, &signatures)
    try add_parameter_type(&builder, function_index, &signatures, integer)
    try add_return_type(&builder, function_index, &signatures, integer)
    if signatures.entries[0usize].first_parameter_type != 0usize || signatures.entries[0usize].parameter_count != 1usize || signatures.entries[0usize].first_return_type != 1usize || signatures.entries[0usize].return_count != 1usize || signatures.count != 2usize { ret InvalidValue }
    ret ok
}
