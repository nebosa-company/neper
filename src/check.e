// Type-checking foundation. Unsupported forms fail explicitly.

use e.mem
use e.os
use graph
use lookup
use lex
use parse
use resolve
use syntax

// The resource states of a local (D345).
const resource_plain: u8 = 0u8
const resource_owned: u8 = 1u8
const resource_moved: u8 = 2u8
const resource_null: u8 = 3u8
const resource_reserved: u8 = 4u8
const resource_maybe: u8 = 5u8
const resource_unchecked: u8 = 6u8

error Capacity
// The build's deadline passed between two functions of the body sweep (D441, H16).
error Cancelled
error ResourceViolation
error Unsupported
error MissingContext
error TypeMismatch
error InvalidCondition
error InvalidOperator
error InvalidReturn
// `InvalidReturn` used to cover four situations at once, so every one of them was
// reported as the first: "ret is not legal inside defer", in files with no defer.
error ReturnValuesUnexpected
error ReturnCount
error ReturnType
error MissingReturn
error UnknownCallable
error ArgumentCount
error InvalidType
error ImmutableAssignment
error AliasCycle
error ConstantCycle
error ConstantOverflow
error InvalidConstant
// Section 9's compile-time evaluation (D218): a call in a `const` reached something the
// interpreter does not evaluate, or its budget.
error ComptimeUnsupported
error ComptimeBudget
// A constant whose evaluation reached a call before the signatures exist: it is put
// off, not refused, and evaluated once they do (D222).
error ComptimeDeferred
error InvalidFormat
error InvalidTry
// The same, for `try`: the defer case now keeps `InvalidTry` to itself.
error TryCast
error TryNotFallible
error TryNoPropagate
error InvalidSwitch
error DuplicateCase
error NonExhaustiveSwitch

type DiagnosticKind = enum u8 {
    None,
    Generic,
    // Section 11's static resource rules (D345, H01).
    ResourceUseAfterMove,
    ResourceCleanupForgotten,
    ResourcePartialMove,
    ResourceOverwrite,
    ResourceUndef,
    ResourceUnchecked,
    ResourceDeferredConsumed,
    ResourceMovedInLoop,
    ResourceOpaque,
    ResourceCleanupSignature,
    ResourceBorrowConsumed,
    ResourceCopy,
    ResourceMovedWhileBorrowed,
    RegionReset,
    RegionEscape,
    BorrowContract,
    NoEscapeContract,
    ViewMutated,
    ThreadFrameEscape,
    ThreadShared,
    AssignmentImmutable,
    IndexedArrayImmutable,
    IndexedElementsImmutable,
    BreakOutsideControl,
    ReturnInsideDefer,
    ReturnValuesUnexpected,
    ReturnCount,
    ReturnType,
    TryInsideDefer,
    TryCast,
    TryNotFallible,
    TryNoPropagate,
    DeferValue,
    ArrayElementCount,
    ArrayLengthType,
    ConstantDependencyCycle,
    EnumValueRange,
    DuplicateEnumValue,
    MissingZeroValue,
    MissingUndefValue,
    IteratorImmutable,
    IteratorMissing,
    IteratorSignature,
    // A `when` condition that is not a question about `target` (D216).
    WhenCondition,
    // A `const` initialiser's call reached what the interpreter does not evaluate (D218).
    ComptimeEvaluation,
    // A constant put off for the signatures, asked for by a type before them (D222).
    ComptimeDeferredUse,
    RecursiveAggregate,
    InitializerType,
    GenericTypeArity,
    GenericInference,
    NotAType,
    MultipleBindingCount,
    MultipleAssignmentImmutable,
    AggregateMemberUnknown,
    AggregateFieldCount,
    BindingUnknownNamed,
    NonExhaustive,
    ProtocolMissing,
    ProtocolSignature,
    ProtocolGenericType,
    AtomicElement,
    AtomicOrdering,
    VectorShape,
    MetaShape,
    MetaFieldOwner,
    ExternWithoutImport,
    ExternType,
    VariadicArgument,
    // A field the aggregate does not declare (D448, H09).
    FieldMissing,
}

type Kind = enum u8 {
    Invalid,
    Void,
    Bool,
    Err,
    Integer,
    Float,
    String,
    Named,
    Tag,
    Pointer,
    Slice,
    Array,
    TypeParameter,
    UntypedInteger,
    UntypedFloat,
    Function,
    Other,
}

type Type = struct {
    kind: Kind,
    name: str,
    module_index: usize,
    element: usize,
    has_element: bool,
    is_const: bool,
    array_length: usize,
    has_length: bool,
}

type FunctionSignature = struct {
    first_parameter: usize,
    parameter_count: usize,
    first_return: usize,
    return_count: usize,
}

type ComptimeKind = enum u8 {
    Type,
    Integer,
    Str,
    // Section 9's comptime-only types. A `Field` is (name, type, offset) and a
    // `Member` is (name, value); both fit the slots a `GenericArgument` already has,
    // and `Field.size` is the type's own size rather than a fourth slot to keep in
    // step with it.
    Field,
    Member,
    // A comptime array of integers -- `shuffle`'s `IDX: [N]u8`. The argument is a literal
    // of integer literals, kept as its spelling the way a `Str` is (`text`), decoded by
    // whoever needs the items; `ty` is the array type the literal wrote.
    Array,
    // A function chosen in brackets is part of the specialization identity. Its
    // value is the selected function index and `ty` is its checked signature.
    Function,
}

// One name bound by an unrolled `for`, which the enclosing instantiation's contiguous
// comptime window has no room for -- it belongs to the loop, not to the signature.
type ComptimeBinding = struct {
    name: str,
    argument: GenericArgument,
}

type ComptimeParameter = struct {
    name: str,
    kind: ComptimeKind,
    ty: Type,
}

type GenericArgument = struct {
    kind: ComptimeKind,
    ty: Type,
    value: usize,
    // The literal exactly as it was written, quotes and escapes included: nothing
    // here decodes it, so it interns and lowers as any other string literal does.
    text: str,
    expression: usize,
    // The aggregate a comptime `Field` or `Member` came from. Its offset and size are
    // target layout, which only lowering can compute -- `layout` is built on this
    // module, not the other way round -- so what is kept here is where to look them up.
    owner: usize,
    symbolic: bool,
    set: bool,
}

type Parameter = struct {
    name: str,
    ty: Type,
    // `own` (D345): the callee takes ownership of the argument, and its obligation.
    own: bool,
}

type Function = struct {
    name: str,
    module_index: usize,
    owner_module_index: usize,
    source_start: usize,
    source_end: usize,
    first_parameter: usize,
    parameter_count: usize,
    first_return: usize,
    return_count: usize,
    instance_id: usize,
    generic: bool,
    external: bool,
    // `@import(LIB, SYM)` on an `extern fn`: the library to bind against and the name
    // to bind to, which is not the neper-side name -- D11 keeps those independent.
    // External functions store their import library and symbol here. Non-extern
    // functions use those otherwise-empty slots for `@borrows` and the source
    // spelling of `@noescape`'s parameter-name list; checked public identities
    // are positional.
    import_library: str,
    import_symbol: str,
    intrinsic: bool,
    // A trailing `...` on an `extern fn`: section 5's C variadic. The declared
    // parameters are the ones counted; every argument past them crosses as its own type.
    variadic: bool,
}

type FunctionGeneric = struct {
    first_comptime: usize,
    comptime_count: usize,
    template_index: usize,
    first_argument: usize,
    instance: bool,
    checked: bool,
    lowered: bool,
    // A formatter instance has no source: its body is generated from the format
    // string, which is why it carries the string rather than a template index.
    formatter: bool,
    formatter_spelling: str,
    // `push_err` writes a name the library cannot see: the merged error table is
    // program-wide and exists only once every module is known.
    formatter_error: bool,
    // `printf` writes through a `str.Sink`, whose `write` is a function value of a
    // shape no `e.io` declaration has. The compiler generates that function too, and
    // this marks the one instance that is it rather than an expansion.
    formatter_sink: bool,
    // Where the instance was first asked for (D466, H19): the module and the byte
    // offset of the call or protocol use, so a diagnostic in the instance's body can
    // say which use of the template produced it.
    site_module: usize,
    site_offset: usize,
    has_site: bool,
    // The instance whose body asked (D543, H09), or `function_count`'s worth of
    // `u32` when a plain body did: the chain of requests up to the program's own
    // code. A `u32` in the bool's padding, so the record keeps its size.
    site_function: u32,
}

type ProtocolBuiltin = enum u8 {
    None,
    Cmp,
    Hash,
    Eq,
}

type AggregateKind = enum u8 {
    Struct,
    Union,
    TaggedUnion,
    Enum,
}

type Aggregate = struct {
    name: str,
    module_index: usize,
    kind: AggregateKind,
    first_field: usize,
    field_count: usize,
    first_comptime: usize,
    comptime_count: usize,
    template_index: usize,
    first_argument: usize,
    generic: bool,
    instance: bool,
    backing_type: Type,
    token: lex.Token,
    // `resource` (D348): affine; `cleanup` names the consuming function, or is empty.
    resource: bool,
    cleanup: str,
    // The containment answer once asked (D352): 0 unasked, else `affine_kind` + 1;
    // and whether a value holds a pointer (D354), the same way.
    affine_memo: u8,
    pointer_memo: u8,
}

type AggregateField = struct {
    name: str,
    ty: Type,
    enum_value: usize,
    enum_negative: bool,
    has_enum_value: bool,
    token: lex.Token,
}

type Local = struct {
    name: str,
    ty: Type,
    mutable: bool,
}

// A local's resource state (D345-D351), beside the locals rather than in them so
// the name walk stays short: where the value is, the token it was acquired or
// moved at, whether it must be consumed, the `err` local it was bound beside while
// that error is untested; a struct's fields (D348), a state each in the low four
// bits and whether it is owed in the fifth; whether it is borrowed (D349); a
// pointer kept to it (D351), the block depth plus one and the token; and whether
// it is a view, read as wanted and moved by nobody.
type Resource = struct {
    state: u8,
    acquired: usize,
    obligated: bool,
    bound_err: usize,
    has_bound_err: bool,
    fields: []u8,
    // Fixed-array slots use `fields` for their states and keep their individual
    // acquisition/move sites here. Struct fields retain the aggregate's site.
    elements_acquired: []usize,
    borrowed: bool,
    pinned: usize,
    pin_at: usize,
    // A pointer local's target (D393, H02/H04), or a copied mark's original mark
    // (D677), plus one. Pointer reads/stores reach the target; reset reaches the
    // original checkpoint rather than treating its copy as a newer mark.
    points_to: usize,
    // The field the alias runs through (D413): empty for a pointer or slice local,
    // whose every use reaches the target; the member's name for a struct local one
    // of whose fields holds `&x`, where only a use through that field does.
    points_to_field: str,
    // A slice alias into a fixed array: the first array slot represented by index
    // zero, when the range's lower bound is comptime-known. For a named aggregate,
    // these otherwise-unused fields instead hold its second alias target and tag;
    // `mark_arena` holds that alias's field name. ponytail: use a compact side table
    // if H02 fixtures require three independent fields.
    slice_offset: usize,
    slice_offset_known: bool,
    view: bool,
    // H02's lexical subset (D354): a mark local's arena, as written; a region value's
    // mark, plus one; a view's container local, plus one; and why a value dangles
    // -- 1 its region was reset, 2 its container was mutated -- once it is Moved.
    mark_arena: str,
    region: usize,
    view_of: usize,
    dangling: u8,
    // A thread started over `&x` of this frame (D357, H04): the local `x`, plus one,
    // or zero. Joined here, bound here, or stored where `x` outlives the store.
    frame_borrow: usize,
    // Storage lent to a running thread (D365, H04): on the local `x` a thread was
    // started over, the thread local plus one, until that thread is joined; and the
    // token the lending started at.
    lent_to: usize,
    lent_at: usize,
}

// Pointer-bearing fields past a named aggregate's two inline aliases (D696),
// recursively nested pointer paths (D701), and fixed-array element paths (D706).
// ponytail: this sparse table is scanned linearly because ordinary locals allocate
// nothing; add per-local heads only if measured aggregate-heavy code needs them.
type ResourceAlias = struct {
    carrier: usize,
    pointed: usize,
    path: []str,
}

type Alias = struct {
    name: str,
    module_index: usize,
    generic: bool,
    rhs: Type,
    resolved: Type,
    state: u8,
}

type IntegerValue = struct {
    magnitude: usize,
    negative: bool,
}

type SwitchKeyKind = enum u8 {
    Invalid,
    Integer,
    Bool,
    Error,
    Member,
}

type SwitchKey = struct {
    kind: SwitchKeyKind,
    integer: IntegerValue,
    boolean: bool,
    module_index: usize,
    name: str,
}

type CheckedSwitch = struct {
    module_index: usize,
    token_start: usize,
    returns: bool,
}

type ConstantExprKind = enum u8 {
    Literal,
    Name,
    Unary,
    Binary,
    // A call, evaluated by the interpreter (D218): `name` in `module_index`, and the
    // arguments as `argument_count` entries from `first_argument`, each a wrapper
    // whose `left` is the argument's own expression.
    Call,
    Argument,
    // `meta.array_len[X]()` where a length is written, with `X` in `ty` -- a parameter or
    // a still-generic vector until the arguments are bound, and then the array or vector
    // whose length it is. It is how `Mask[T, N]` is spelled for a `V` in `e.simd`.
    ArrayLen,
}

type ConstantExpr = struct {
    kind: ConstantExprKind,
    module_index: usize,
    name: str,
    value: IntegerValue,
    ty: Type,
    op: lex.Kind,
    left: usize,
    right: usize,
    has_right: bool,
    first_argument: usize,
    argument_count: usize,
    site: syntax.Node,
    // Where a call was written (D510, H17): the module of the initializer and the
    // call's byte offset, taken when the expression is copied, since the tokens in
    // hand at evaluation are whichever module's the interpreter is in.
    site_module: usize,
    site_offset: usize,
}

// Spec section 5: `var` at module scope is mutable static storage, zero-initialised unless
// given a compile-time initialiser. Unlike a `const` it has an address and a lifetime, which is
// why it is a separate table: a constant is folded into its uses and this one is loaded from.
type Global = struct {
    name: str,
    module_index: usize,
    ty: Type,
    // The initialiser, evaluated by the same interpreter a `const` uses. Section 5 says
    // zero-initialised when there is none, which is what the linker writes anyway.
    expression: usize,
    has_expression: bool,
    token: lex.Token,
    // The NIR global this became (D304): `declare_globals` lays globals out in graph
    // order whatever order the front end collected them in, so an image links the same
    // from source and from artifacts.
    nir_index: usize,
}

type Constant = struct {
    name: str,
    module_index: usize,
    ty: Type,
    expression: usize,
    value: IntegerValue,
    state: u8,
    token: lex.Token,
}

// What the checker decided at a site (D359, H06), for `explain-file`: a protocol
// dispatch -- the protocol, the receiver, the declared function chosen or the
// supplied rule, or neither -- or a generic instantiation -- the template and its
// arguments. Recorded only while `explains` has room, which the explain command
// alone gives it.
type Explain = struct {
    kind: u8,
    module_index: usize,
    offset: usize,
    protocol: str,
    receiver: Type,
    function_index: usize,
    found: bool,
    builtin: ProtocolBuiltin,
    template_index: usize,
    first_argument: usize,
    argument_count: usize,
    // Why a dispatch found nothing (D430, H06): a function of the protocol's name
    // declared in another module (`function_count` for none), and the first
    // component the supplied rule refused -- kind 1 a struct, which no rule supplies;
    // 2 an arm of a tagged union; 3 an element of a sequence; 4 a scalar the rule
    // does not cover -- with the component's name and type.
    candidate_index: usize,
    reason_kind: u8,
    reason_name: str,
    reason_type: Type,
}

type Diagnostic = struct {
    module_index: usize,
    kind: DiagnosticKind,
    token: lex.Token,
    detail: str,
    detail2: str,
    // The other site the diagnostic is about (D364, H09): where the resource was
    // acquired, moved, borrowed, reset -- as a token of the same module, with the
    // note the stream carries for it.
    related: lex.Token,
    has_related: bool,
    related_note: str,
}

type Checker = struct {
    resolver: *resolve.Resolver,
    // The build's deadline (D441, H16): nanoseconds of the monotonic clock since
    // `started_ns`, zero for none; the body sweep reads the clock between functions
    // and answers `Cancelled` past it, so a cancellation waits for one function and
    // not for a module. Copied into every worker's fork.
    deadline_ns: usize,
    // The deadline inside a function (D540, H16): every statement checked or lowered
    // is a tick, and the clock is read every four thousand and ninety-six of them,
    // so a cancellation waits for a few thousand statements, not for a function;
    // `cancelled_in_function` says the deadline passed there. `fault_cancel_ticks`
    // (`--fault-cancel N`) makes the deadline pass at the Nth tick, for a suite.
    statement_ticks: usize,
    cancelled_in_function: bool,
    fault_cancel_ticks: usize,
    started_ns: usize,
    // Where each module's rows lie in the program-wide tables (D320), for the artifact
    // writer: em's nine tables, a first and an end per module, and how far each table
    // was scanned. The checker only carries them; `em.update_spans` fills them.
    writer_spans: []usize,
    writer_scanned: [9]usize,
    // A function's body hash plus one, by function index, once `em.body_hash` has
    // computed it (D326): zero is not yet. A callee's hash is written into every
    // module that reaches it, and was recomputed from its tokens for each of them.
    // Each worker's checker has a table of its own.
    body_hashes: []usize,
    // Where a worker's private tails begin (D326): the rows below are the program's
    // declarations, the same in every checker forked from the one that made them; a
    // row at or past them is the worker's own, and another worker imports it.
    fork_types: usize,
    fork_aggregates: usize,
    fork_signatures: usize,
    // Which fork this is: zero for the program's checker, a worker's number for its.
    fork_id: usize,
    // The body sweep's answers kept for the lowering (D327): per module, per tree
    // node, the expected and resulting types as ids in `memo_types`, each plus one,
    // packed as `(expected + 1) << 32 | (result + 1)`; zero is no answer. Only a
    // plain body's -- an instance's or an unrolled iteration's answers depend on
    // bindings the node does not say -- and only on a worker's checker (`memo_on`),
    // whose arena keeps the tables from the sweep to the lowering.
    memo_on: bool,
    memo_tables: [][]usize,
    memo_types: []Type,
    memo_type_count: usize,
    memo_slots: []usize,
    // The (module, table, name) index over the declaration tables (D303): table 1 is
    // functions, 2 aggregates, 3 aliases, 4 constants, 5 globals. Absent, the finders scan.
    names: lookup.Index,
    tokens_module: usize,
    has_tokens_module: bool,
    functions: []Function,
    function_generics: []FunctionGeneric,
    parameters: []Parameter,
    return_types: []Type,
    comptime_parameters: []ComptimeParameter,
    generic_arguments: []GenericArgument,
    aggregates: []Aggregate,
    aggregate_fields: []AggregateField,
    checked_switches: []CheckedSwitch,
    function_signatures: []FunctionSignature,
    tokens: []lex.Token,
    locals: []Local,
    resources: []Resource,
    resource_aliases: []ResourceAlias,
    resource_alias_count: usize,
    types: []Type,
    aliases: []Alias,
    constants: []Constant,
    globals: []Global,
    global_count: usize,
    constant_exprs: []ConstantExpr,
    diagnostics: []Diagnostic,
    // The merged error table (src/error_table.e), by value. Filled once the whole
    // program is known, because that is the first point at which it is merged; the
    // expansion of `push_err` is the only thing that reads it so far.
    error_values: []usize,
    error_spellings: []str,
    error_count: usize,
    // Lowering has to build strings that appear in no source text -- a reflected type
    // name, and the qualified error names above -- and interning takes a spelling, so
    // there has to be somewhere to build them.
    arena: *mem.Arena,
    graph: *graph.Graph,
    has_graph: bool,
    // Where each open loop body's and breakable body's locals begin (D345): `continue`
    // and `break` audit the obligations declared inside what they leave.
    loop_locals: [64]usize,
    break_locals: [64]usize,
    // A canonical `i = 0; while i < N { ...; i += 1 }` is an exhaustive
    // sweep. Dynamic affine-array operations under it cover each slot once.
    resource_loop_index: [64]str,
    resource_loop_bound: [64]usize,
    resource_loop_bound_local: [64]usize,
    resource_loop_sweep: [64]bool,
    resource_loop_swept_local: [64]usize,
    // The resource pass runs in the body sweep alone (D345): the lowering re-walks
    // bodies in its own order and partially, and states depend on the walk.
    resources_on: bool,
    // The explain records (D359), when the command asked for them.
    explains: []Explain,
    explain_count: usize,
    explain_overflow: bool,
    // Set while a consumption transfers ownership out of the function -- an `own`
    // argument, a `ret` -- which a borrowed value cannot do (D349).
    resource_transfer: bool,
    // The consumption under way is a thread's join, or a binding in the same frame
    // (D357): the two a frame-borrowing thread allows.
    consuming_join: bool,
    consuming_binding: bool,
    // The store under way, when one is: the local the place is in, plus one.
    consuming_store: usize,
    // How many blocks are open in the body being checked (D351), for the pins; and
    // the pointers the current statement took, pinned at its end when what the
    // statement made can hold one.
    block_depth: usize,
    pin_locals: [16]usize,
    pin_tokens: [16]usize,
    pin_count: usize,
    // How many locals are pinned, so a block's end walks the locals only when one is;
    // and the answer to "is any local affine" with the local count it was given for,
    // so a statement asks in O(1) and only a change of the locals asks again.
    pins_live: usize,
    affine_answer_count: usize,
    affine_answer: bool,
    affine_answer_valid: bool,
    // The interpreter's state (D218): set once the signatures are collected, the per-module
    // trees and tokens it keeps, the constant being evaluated for its reports, its budget.
    signatures_ready: bool,
    interp_ready: bool,
    interp_trees: []parse.Tree,
    interp_parsed: []bool,
    interp_tokens: [][]lex.Token,
    interp_token_counts: []usize,
    interp_constant: str,
    interp_steps: usize,
    // A call's answer, kept for the function being checked or lowered (D318): lowering
    // asks `check_call` for every call again, and once more for every call it is
    // nested in, so a call was checked six times over on average. The generation
    // moves at each function and instance, since a name means something else there.
    call_cache: []CallCacheEntry,
    call_generation: usize,
    // Likewise an expression's type, keyed by the type it was expected to have as well,
    // since an untyped literal takes its type from that.
    expr_cache: []ExprCacheEntry,
    interp_depth: usize,
    function_count: usize,
    parameter_count: usize,
    return_type_count: usize,
    comptime_parameter_count: usize,
    generic_argument_count: usize,
    signature_function_count: usize,
    aggregate_count: usize,
    aggregate_field_count: usize,
    // Section 4's `Vec` and `Mask` are seeded into `e.simd` when that module is in the
    // graph; layout and `e.meta` recognise an instance by this module and the name.
    simd_module: usize,
    // Whether the root module's `main` returned an `err` somewhere: then section 13's
    // failure line needs its reporting function synthesized once the module is lowered.
    main_reports_failure: bool,
    has_simd: bool,
    checked_switch_count: usize,
    function_signature_count: usize,
    token_count: usize,
    local_count: usize,
    type_count: usize,
    alias_count: usize,
    constant_count: usize,
    constant_expr_count: usize,
    diagnostic_count: usize,
    constants_ready: bool,
    expand_aliases: bool,
    // Unrolled `for` bindings, innermost last. Eight is the nesting depth of comptime
    // loops, not of loops: only a comptime subject pushes here.
    comptime_bindings: [8]ComptimeBinding,
    comptime_binding_count: usize,
    active_first_comptime: usize,
    active_comptime_count: usize,
    active_first_argument: usize,
    active_arguments: bool,
    active_owner_module: usize,
    active_owner_set: bool,
    // The instance whose body is being checked (D543), for the request chain.
    active_instance: usize,
    // The quoted `@noescape` parameter list of the body currently being checked.
    // Empty outside that body, including the lowering walk.
    active_noescape: str,
    generic_declaration: bool,
    loop_depth: usize,
    break_depth: usize,
    defer_depth: usize,
    failure_module: usize,
    failure_name: str,
    failure_kind: DiagnosticKind,
    failure_token: lex.Token,
    failure_has_token: bool,
    failure_detail: str,
    failure_detail2: str,
    // A missing protocol's foreign candidate (D430, H09): a function of the name
    // declared outside the receiver's module, `function_count` for none.
    failure_candidate: usize,
    failure_candidate_module: str,
    // The two types of the mismatch being reported (D401, H09): what the context
    // asked for and what the expression had, recorded where they part.
    failure_expected: Type,
    failure_actual: Type,
    // Every interpreter step the checker took (D474, H24): never reset, summed over
    // the workers for `--comptime-steps`. (`failure_has_types` was here: it is
    // `failure_expected.kind != .Invalid`, and the bootstrap holds a struct to 128.)
    interp_total: usize,
    // The expression the mismatch surfaced at (D444, H09), when the outermost frame
    // to see it is one token -- a name or a literal a conversion can wrap without a
    // reading: `failure_fix_at` holds its start under fix kind 3 and this its end,
    // zero for none. A wider expression clears it. (One field: the bootstrap holds
    // a struct to 128.)
    failure_mismatch_end: usize,
    failure_related: lex.Token,
    failure_has_related: bool,
    failure_related_note: str,
    // A fix for the diagnostic (D381, H09): text to insert at a byte offset of the
    // failing module, or empty. The first is `defer <closer>(x)` after an acquisition
    // that is owed at an exit.
    failure_fix_text: str,
    failure_fix_at: usize,
    // Which fix (D382): 1 a deferred cleanup, 2 an error test.
    failure_fix_kind: u8,
    // Whether the body being checked returns a bare `err` (D382): what `ret e` needs.
    body_returns_err: bool,
}

fn append_failure_token(c: *Checker, module_index: usize, token: lex.Token, kind: DiagnosticKind, detail: str, detail2: str) {
    var none: lex.Token = zero
    append_failure_related(c, module_index, token, kind, detail, detail2, none, false, "")
}

fn append_failure_related(c: *Checker, module_index: usize, token: lex.Token, kind: DiagnosticKind, detail: str, detail2: str, related: lex.Token, has_related: bool, note: str) {
    if c.diagnostic_count < c.diagnostics.len {
        c.diagnostics[c.diagnostic_count] = Diagnostic { module_index: module_index, kind: kind, token: token, detail: detail, detail2: detail2, related: related, has_related: has_related, related_note: note }
        c.diagnostic_count += 1usize
    }
    if !c.failure_has_token {
        c.failure_module = module_index
        c.failure_kind = kind
        c.failure_token = token
        c.failure_has_token = true
        c.failure_detail = detail
        c.failure_detail2 = detail2
        c.failure_related = related
        c.failure_has_related = has_related
        c.failure_related_note = note
    }
}

// A resource diagnostic with its other site (D364, H09): the acquisition, the
// move, the borrow, the reset or the mutation it is about, as a related span.
fn record_failure_related(c: *Checker, module_index: usize, node: syntax.Node, kind: DiagnosticKind, detail: str, detail2: str, related_index: usize) {
    if c.failure_has_token { ret }
    if usize(node.token_start) < c.token_count && related_index < c.token_count {
        append_failure_related(c, module_index, c.tokens[usize(node.token_start)], kind, detail, detail2, c.tokens[related_index], true, related_note(kind))
    } else {
        record_failure(c, module_index, node, kind, detail, detail2)
    }
}

fn related_note(kind: DiagnosticKind) -> str {
    if kind == .ResourceUseAfterMove { ret "moved here, or acquired here and never owned" }
    if kind == .ResourceCleanupForgotten || kind == .ResourceOverwrite || kind == .ResourceUnchecked || kind == .ResourceMovedInLoop { ret "acquired here" }
    if kind == .ResourcePartialMove { ret "the aggregate was acquired here" }
    if kind == .ResourceDeferredConsumed { ret "reserved by the deferred call here" }
    if kind == .ResourceBorrowConsumed { ret "borrowed here" }
    if kind == .ResourceMovedWhileBorrowed { ret "the pointer taken here" }
    if kind == .RegionReset { ret "the region reset here" }
    if kind == .RegionEscape { ret "the deferred reset is registered here" }
    if kind == .ViewMutated { ret "the container changed here" }
    if kind == .ThreadFrameEscape { ret "the thread started here" }
    if kind == .ThreadShared { ret "lent to the thread started here" }
    ret "related"
}

fn record_failure(c: *Checker, module_index: usize, node: syntax.Node, kind: DiagnosticKind, detail: str, detail2: str) {
    if c.failure_has_token { ret }
    if usize(node.token_start) < c.token_count {
        append_failure_token(c, module_index, c.tokens[usize(node.token_start)], kind, detail, detail2)
    }
}

fn record_failure_token(c: *Checker, module_index: usize, token: lex.Token, kind: DiagnosticKind, detail: str, detail2: str) {
    if c.failure_has_token { ret }
    append_failure_token(c, module_index, token, kind, detail, detail2)
}

fn default_failure_kind(failure: err, node: syntax.Node) -> DiagnosticKind {
    if failure == ImmutableAssignment { ret .AssignmentImmutable }
    if failure == TypeMismatch { ret .InitializerType }
    if failure == ConstantCycle { ret .ConstantDependencyCycle }
    if failure == NonExhaustiveSwitch { ret .NonExhaustive }
    if node.kind == .ReturnStmt && failure == InvalidReturn { ret .ReturnInsideDefer }
    if node.kind == .TryStmt && failure == InvalidTry { ret .TryInsideDefer }
    // These carry their own situation, so they need no help from the node kind --
    // which matters because a `try` in a binding reaches here as a BindingStmt.
    if failure == ReturnValuesUnexpected { ret .ReturnValuesUnexpected }
    if failure == ReturnCount { ret .ReturnCount }
    if failure == ReturnType { ret .ReturnType }
    if failure == TryCast { ret .TryCast }
    if failure == TryNotFallible { ret .TryNotFallible }
    if failure == TryNoPropagate { ret .TryNoPropagate }
    if node.kind == .DeferStmt && failure == ArgumentCount { ret .DeferValue }
    // Nothing else guesses a diagnostic from the statement it happened in. Each of
    // these used to: a `for` claimed any type error inside it was an iterator
    // signature, and a binding claimed any arity error inside it was a binding count
    // -- which is how a duplicate struct field in a loop body reported "multiple
    // binding count does not match function results". The situations that really are
    // those record themselves where they are raised.
    ret .Generic
}

fn init(c: *Checker, functions: []Function, parameters: []Parameter, return_types: []Type, tokens: []lex.Token, locals: []Local, resources: []Resource, types: []Type, aliases: []Alias, constants: []Constant, globals: []Global, constant_exprs: []ConstantExpr, diagnostics: []Diagnostic) -> err {
    if functions.len == 0usize || parameters.len == 0usize || return_types.len == 0usize || tokens.len == 0usize || locals.len == 0usize || types.len == 0usize || aliases.len == 0usize || constants.len == 0usize || globals.len == 0usize || constant_exprs.len == 0usize || diagnostics.len == 0usize { ret Capacity }
    c.functions = functions
    c.names.entries = c.names.entries[0usize..0usize]
    c.has_tokens_module = false
    c.globals = globals
    c.global_count = 0usize
    c.parameters = parameters
    c.return_types = return_types
    c.tokens = tokens
    c.locals = locals
    c.resources = resources
    var no_resource_aliases: []ResourceAlias = zero
    c.resource_aliases = no_resource_aliases
    c.resource_alias_count = 0usize
    c.types = types
    c.aliases = aliases
    c.constants = constants
    c.constant_exprs = constant_exprs
    c.diagnostics = diagnostics
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    c.signature_function_count = 0usize
    c.aggregate_count = 0usize
    c.aggregate_field_count = 0usize
    c.checked_switch_count = 0usize
    c.function_signature_count = 0usize
    c.token_count = 0usize
    c.local_count = 0usize
    c.type_count = 0usize
    c.alias_count = 0usize
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.diagnostic_count = 0usize
    c.constants_ready = false
    c.expand_aliases = false
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.active_first_argument = 0usize
    c.active_arguments = false
    c.active_owner_module = 0usize
    c.active_owner_set = false
    c.active_noescape = ""
    c.generic_declaration = false
    c.loop_depth = 0usize
    c.break_depth = 0usize
    c.defer_depth = 0usize
    c.failure_module = 0usize
    c.failure_name = ""
    c.failure_kind = .None
    c.failure_has_token = false
    c.failure_detail = ""
    c.failure_detail2 = ""
    c.failure_expected = invalid_type()
    c.failure_mismatch_end = 0usize
    ret ok
}

fn init_generics(c: *Checker, functions: []FunctionGeneric, parameters: []ComptimeParameter, arguments: []GenericArgument) -> err {
    if functions.len < c.functions.len || parameters.len == 0usize || arguments.len == 0usize { ret Capacity }
    c.function_generics = functions
    c.comptime_parameters = parameters
    c.generic_arguments = arguments
    ret ok
}

fn init_aggregates(c: *Checker, aggregates: []Aggregate, fields: []AggregateField) -> err {
    if aggregates.len == 0usize || fields.len == 0usize { ret Capacity }
    c.aggregates = aggregates
    c.aggregate_fields = fields
    ret ok
}

fn init_control(c: *Checker, switches: []CheckedSwitch, signatures: []FunctionSignature) -> err {
    if switches.len == 0usize || signatures.len == 0usize { ret Capacity }
    c.checked_switches = switches
    c.function_signatures = signatures
    ret ok
}

fn store_function_signature(c: *Checker, item: FunctionSignature) -> (usize, err) {
    if c.function_signature_count == c.function_signatures.len { ret (0usize, Capacity) }
    let index = c.function_signature_count
    c.function_signatures[index] = item
    c.function_signature_count += 1usize
    ret (index, ok)
}

fn function_signature_of(c: *Checker, ty: Type) -> (FunctionSignature, bool) {
    var empty: FunctionSignature = zero
    if ty.kind != .Function || !ty.has_element || ty.element >= c.function_signature_count { ret (empty, false) }
    ret (c.function_signatures[ty.element], true)
}

fn function_signature_parameter(c: *Checker, signature: FunctionSignature, index: usize) -> (Type, bool) {
    if index >= signature.parameter_count || signature.first_parameter + index >= c.type_count { ret (invalid_type(), false) }
    ret (c.types[signature.first_parameter + index], true)
}

fn function_signature_return(c: *Checker, signature: FunctionSignature, index: usize) -> (Type, bool) {
    if index >= signature.return_count || signature.first_return + index >= c.type_count { ret (invalid_type(), false) }
    ret (c.types[signature.first_return + index], true)
}

fn build_function_type(c: *Checker, parameters: []const Type, returns: []const Type, module_index: usize) -> (Type, err) {
    let first_parameter = c.type_count
    var at = 0usize
    while at < parameters.len {
        let (stored, store_error) = store_type(c, parameters[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < returns.len {
        let (stored, store_error) = store_type(c, returns[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = parameters.len
    signature.first_return = first_return
    signature.return_count = returns.len
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

fn function_pointer_type(c: *Checker, function: Function, module_index: usize) -> (Type, err) {
    let first_parameter = c.type_count
    var at = 0usize
    while at < function.parameter_count {
        if function.first_parameter + at >= c.parameter_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.parameters[function.first_parameter + at].ty)
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < function.return_count {
        if function.first_return + at >= c.return_type_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.return_types[function.first_return + at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = function.parameter_count
    signature.first_return = first_return
    signature.return_count = function.return_count
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

// The signature a protocol declaration was required to have when its first
// parameter was wrong. The rest of the declaration stays unchanged, so the
// diagnostic compares the exact requested and actual function types.
fn protocol_expected_type(c: *Checker, function: Function, receiver: Type, module_index: usize) -> (Type, err) {
    let first_parameter = c.type_count
    let (stored_receiver, receiver_error) = store_type(c, receiver)
    if receiver_error != ok { ret (invalid_type(), receiver_error) }
    var at = 1usize
    while at < function.parameter_count {
        if function.first_parameter + at >= c.parameter_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.parameters[function.first_parameter + at].ty)
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < function.return_count {
        if function.first_return + at >= c.return_type_count { ret (invalid_type(), InvalidType) }
        let (stored, store_error) = store_type(c, c.return_types[function.first_return + at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = function.parameter_count
    if signature.parameter_count == 0usize { signature.parameter_count = 1usize }
    signature.first_return = first_return
    signature.return_count = function.return_count
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

fn record_protocol_signature_types(c: *Checker, function: Function, receiver: Type) -> err {
    let (actual, actual_error) = function_pointer_type(c, function, function.module_index)
    if actual_error != ok { ret actual_error }
    let (expected, expected_error) = protocol_expected_type(c, function, receiver, function.module_index)
    if expected_error != ok { ret expected_error }
    c.failure_expected = expected
    c.failure_actual = actual
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn ends_with(text: str, suffix: str) -> bool {
    if text.len < suffix.len { ret false }
    ret same(text[text.len - suffix.len..], suffix)
}

fn make_type(kind: Kind, name: str, module_index: usize) -> Type {
    ret Type { kind: kind, name: name, module_index: module_index, element: 0usize, has_element: false, is_const: false, array_length: 0usize, has_length: false }
}

fn store_type(c: *Checker, ty: Type) -> (usize, err) {
    if c.type_count == c.types.len { ret (0usize, Capacity) }
    c.types[c.type_count] = ty
    let index = c.type_count
    c.type_count += 1usize
    ret (index, ok)
}

fn invalid_type() -> Type {
    ret make_type(.Invalid, "", 0usize)
}

fn is_integer_name(name: str) -> bool {
    ret same(name, "i8") || same(name, "i16") || same(name, "i32") || same(name, "i64") || same(name, "isize") || same(name, "u8") || same(name, "u16") || same(name, "u32") || same(name, "u64") || same(name, "usize")
}

fn is_float_name(name: str) -> bool {
    ret same(name, "f16") || same(name, "bf16") || same(name, "f32") || same(name, "f64")
}

fn is_numeric(ty: Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .Float || ty.kind == .UntypedInteger || ty.kind == .UntypedFloat
}

fn is_integer(ty: Type) -> bool {
    ret ty.kind == .Integer || ty.kind == .UntypedInteger
}

fn is_untyped(ty: Type) -> bool {
    ret ty.kind == .UntypedInteger || ty.kind == .UntypedFloat
}

fn is_string_shape(c: *Checker, ty: Type) -> bool {
    if ty.kind == .String { ret true }
    if ty.kind != .Slice || !ty.is_const || !ty.has_element || ty.element >= c.type_count { ret false }
    let element = c.types[ty.element]
    ret element.kind == .Integer && same(element.name, "u8")
}

fn type_equal(c: *Checker, a: Type, b: Type) -> bool {
    if is_string_shape(c, a) || is_string_shape(c, b) { ret is_string_shape(c, a) && is_string_shape(c, b) }
    if a.kind != b.kind { ret false }
    if a.kind == .Named || a.kind == .Tag {
        if a.module_index != b.module_index || !same(a.name, b.name) || a.has_element != b.has_element { ret false }
        if a.has_element {
            if a.element == b.element { ret true }
            // Two instances of one template with the same arguments are one type, whichever
            // path made each: an instance is its template and its arguments, not its index.
            if a.element >= c.aggregate_count || b.element >= c.aggregate_count { ret false }
            let left = c.aggregates[a.element]
            let right = c.aggregates[b.element]
            if !left.instance || !right.instance || left.template_index != right.template_index { ret false }
            ret aggregate_arguments_equal(c, c.aggregates[left.template_index], left.first_argument, right.first_argument)
        }
        ret true
    }
    if a.kind == .TypeParameter { ret a.has_element && b.has_element && a.element == b.element && a.has_length == b.has_length }
    if a.kind == .Integer || a.kind == .Float { ret same(a.name, b.name) }
    if a.kind == .Pointer || a.kind == .Slice {
        if a.is_const != b.is_const || !a.has_element || !b.has_element { ret false }
        if a.element >= c.type_count || b.element >= c.type_count { ret false }
        ret type_equal(c, c.types[a.element], c.types[b.element])
    }
    if a.kind == .Array {
        if !a.has_length || !b.has_length || a.array_length != b.array_length || !a.has_element || !b.has_element { ret false }
        if a.element >= c.type_count || b.element >= c.type_count { ret false }
        ret type_equal(c, c.types[a.element], c.types[b.element])
    }
    if a.kind == .Function {
        let (left, has_left) = function_signature_of(c, a)
        let (right, has_right) = function_signature_of(c, b)
        if !has_left || !has_right { ret false }
        if left.parameter_count != right.parameter_count || left.return_count != right.return_count { ret false }
        var at = 0usize
        while at < left.parameter_count {
            let (left_parameter, has_left_parameter) = function_signature_parameter(c, left, at)
            let (right_parameter, has_right_parameter) = function_signature_parameter(c, right, at)
            if !has_left_parameter || !has_right_parameter || !type_equal(c, left_parameter, right_parameter) { ret false }
            at += 1usize
        }
        at = 0usize
        while at < left.return_count {
            let (left_return, has_left_return) = function_signature_return(c, left, at)
            let (right_return, has_right_return) = function_signature_return(c, right, at)
            if !has_left_return || !has_right_return || !type_equal(c, left_return, right_return) { ret false }
            at += 1usize
        }
        ret true
    }
    if a.kind == .Other || a.kind == .Invalid { ret false }
    ret true
}

fn type_assignable(c: *Checker, actual: Type, expected: Type) -> bool {
    if type_equal(c, actual, expected) { ret true }
    if actual.kind == expected.kind && (actual.kind == .Pointer || actual.kind == .Slice) {
        if actual.is_const || !expected.is_const || !actual.has_element || !expected.has_element { ret false }
        if actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret type_equal(c, c.types[actual.element], c.types[expected.element])
    }
    if expected.kind == .String && actual.kind == .Slice && !actual.is_const && actual.has_element && actual.element < c.type_count {
        let element = c.types[actual.element]
        ret element.kind == .Integer && same(element.name, "u8")
    }
    ret false
}

fn type_depends_on_comptime(c: *Checker, ty: Type) -> bool {
    if ty.kind == .TypeParameter { ret true }
    if ty.kind == .Named && ty.has_element && ty.element < c.aggregate_count { ret c.aggregates[ty.element].generic }
    if ty.kind == .Array && !ty.has_length { ret true }
    if (ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array) && ty.has_element && ty.element < c.type_count {
        ret type_depends_on_comptime(c, c.types[ty.element])
    }
    ret false
}

fn type_shape_unknown(ty: Type) -> bool {
    ret ty.kind == .TypeParameter
}

fn types_may_match_after_instantiation(c: *Checker, actual: Type, expected: Type) -> bool {
    if type_equal(c, actual, expected) { ret true }
    if actual.kind == .TypeParameter || expected.kind == .TypeParameter { ret true }
    if actual.kind != expected.kind { ret false }
    if actual.kind == .Named {
        if actual.module_index != expected.module_index || !same(actual.name, expected.name) { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.aggregate_count || expected.element >= c.aggregate_count { ret false }
        let left = c.aggregates[actual.element]
        let right = c.aggregates[expected.element]
        ret left.template_index == right.template_index && (left.generic || right.generic)
    }
    if actual.kind == .Pointer || actual.kind == .Slice {
        if actual.is_const && !expected.is_const { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret types_may_match_after_instantiation(c, c.types[actual.element], c.types[expected.element])
    }
    if actual.kind == .Array {
        if actual.has_length && expected.has_length && actual.array_length != expected.array_length { ret false }
        if !actual.has_element || !expected.has_element || actual.element >= c.type_count || expected.element >= c.type_count { ret false }
        ret types_may_match_after_instantiation(c, c.types[actual.element], c.types[expected.element])
    }
    // A declaration and the aggregate it constructs number their comptime
    // parameters separately, so two signatures written the same way are not equal
    // until the instantiation binds both.
    if actual.kind == .Function {
        let (left, has_left) = function_signature_of(c, actual)
        let (right, has_right) = function_signature_of(c, expected)
        if !has_left || !has_right { ret false }
        if left.parameter_count != right.parameter_count || left.return_count != right.return_count { ret false }
        var at = 0usize
        while at < left.parameter_count {
            let (left_parameter, has_left_parameter) = function_signature_parameter(c, left, at)
            let (right_parameter, has_right_parameter) = function_signature_parameter(c, right, at)
            if !has_left_parameter || !has_right_parameter { ret false }
            if !types_may_match_after_instantiation(c, left_parameter, right_parameter) { ret false }
            at += 1usize
        }
        at = 0usize
        while at < left.return_count {
            let (left_return, has_left_return) = function_signature_return(c, left, at)
            let (right_return, has_right_return) = function_signature_return(c, right, at)
            if !has_left_return || !has_right_return { ret false }
            if !types_may_match_after_instantiation(c, left_return, right_return) { ret false }
            at += 1usize
        }
        ret true
    }
    ret false
}

// A mismatch of two known types (D401): recorded for the diagnostic, then the error.
fn mismatch(c: *Checker, expected: Type, actual: Type) -> err {
    c.failure_expected = expected
    c.failure_actual = actual
    ret TypeMismatch
}

fn apply_context(c: *Checker, actual: Type, expected: Type) -> (Type, err) {
    if expected.kind == .Invalid { ret (actual, ok) }
    if actual.kind == .UntypedInteger && expected.kind == .Integer { ret (expected, ok) }
    if actual.kind == .UntypedFloat && expected.kind == .Float { ret (expected, ok) }
    if type_assignable(c, actual, expected) {
        c.failure_expected = invalid_type()
        c.failure_mismatch_end = 0usize
        ret (expected, ok)
    }
    if c.generic_declaration && types_may_match_after_instantiation(c, actual, expected) {
        c.failure_expected = invalid_type()
        c.failure_mismatch_end = 0usize
        ret (expected, ok)
    }
    // The pair the diagnostic names (D401): the last mismatch before the failure is
    // the failure's, and a context that matched in between clears a speculative one.
    ret (invalid_type(), mismatch(c, expected, actual))
}

// The module whose tokens `tokens` holds (D304): a phase that asks for the same
// module again pays nothing. Any other tokenize invalidates it.
// The checker's token table is the module's own list (D316): no scan, a slice.
fn tokenize_module(c: *Checker, g: *graph.Graph, module_index: usize) -> err {
    if c.has_tokens_module && c.tokens_module == module_index { ret ok }
    if g.modules[module_index].has_invalid { ret lex.InvalidSource }
    c.tokens = g.modules[module_index].tokens
    c.token_count = c.tokens.len
    c.tokens_module = module_index
    c.has_tokens_module = true
    ret ok
}

fn first_node_child(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) { ret (parse.child_index_at(tree, at), true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn last_node_child(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    var last = 0usize
    var found = false
    while at < end {
        if parse.child_is_node_at(tree, at) {
            last = parse.child_index_at(tree, at)
            found = true
        }
        at += 1usize
    }
    ret (last, found)
}

fn function_name(c: *Checker, text: str, node: syntax.Node) -> (str, err) {
    var saw_fn = false
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .KwFn {
            saw_fn = true
        } else {
            if saw_fn && token.kind == .Identifier { ret (text[token.start..token.end], ok) }
        }
        at += 1usize
    }
    ret ("", parse.InvalidSyntax)
}

fn first_name(c: *Checker, text: str, node: syntax.Node) -> (str, bool) {
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier { ret (text[token.start..token.end], true) }
        at += 1usize
    }
    ret ("", false)
}

fn scalar_type(name: str, module_index: usize) -> Type {
    if is_integer_name(name) { ret make_type(.Integer, name, module_index) }
    if is_float_name(name) { ret make_type(.Float, name, module_index) }
    if same(name, "bool") { ret make_type(.Bool, name, module_index) }
    if same(name, "err") { ret make_type(.Err, name, module_index) }
    if same(name, "void") { ret make_type(.Void, name, module_index) }
    if same(name, "str") { ret make_type(.String, name, module_index) }
    ret invalid_type()
}

// `str` names both a builtin type and the qualifier `use e.str` binds, so a dotted
// path under that name is the module's — `str.Builder`, which section 9 requires in
// every declared `format` — and never the scalar.
fn named_type_is_path(c: *Checker, node: syntax.Node) -> bool {
    var at = usize(node.token_start) + 1usize
    while at < usize(node.token_end) {
        if c.tokens[at].kind == .PunctDot { ret true }
        at += 1usize
    }
    ret false
}

fn active_comptime_parameter(c: *Checker, name: str) -> (usize, bool) {
    var at = 0usize
    while at < c.active_comptime_count {
        let index = c.active_first_comptime + at
        if index < c.comptime_parameter_count && same(c.comptime_parameters[index].name, name) { ret (index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// Innermost first: a nested unrolled loop may reuse an outer loop's binding name.
//
// A `Field` or `Member` parameter of the enclosing instantiation answers here too, and that
// is deliberate: it makes every reader of a comptime value -- `FIELD.ty` as a type, `.name`
// and `.offset` as expressions, `meta.get` and `meta.set`, and lowering's constant for the
// offset -- work on a declared parameter without knowing there is a second way to bind one.
// Only those two kinds fall through: a `T` must not be found here, or `T.anything` would read
// as a member of a comptime value rather than as the type it is.
fn find_comptime_binding(c: *Checker, name: str) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    var at = c.comptime_binding_count
    while at > 0usize {
        at = at - 1usize
        if same(c.comptime_bindings[at].name, name) { ret (c.comptime_bindings[at].argument, true) }
    }
    let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
    if parameter_found {
        let parameter = c.comptime_parameters[parameter_index]
        if parameter.kind == .Field || parameter.kind == .Member {
            let (argument, argument_found) = active_argument(c, parameter_index)
            if argument_found { ret (argument, true) }
            // No argument means the declaration is being checked rather than an instantiation.
            // What a member of this parameter *is* can be answered there; what it holds cannot,
            // and nothing needs it to be -- a declaration's body is never lowered, only every
            // instantiation of it is.
            var pending: GenericArgument = zero
            pending.kind = parameter.kind
            pending.ty = parameter.ty
            ret (pending, true)
        }
    }
    ret (empty, false)
}

fn push_comptime_binding(c: *Checker, name: str, argument: GenericArgument) -> err {
    // A comptime binding changes what a name means: the call cache starts over (D318).
    begin_call_scope(c)
    if c.comptime_binding_count == c.comptime_bindings.len { ret Capacity }
    c.comptime_bindings[c.comptime_binding_count] = ComptimeBinding { name: name, argument: argument }
    c.comptime_binding_count += 1usize
    ret ok
}

fn active_argument(c: *Checker, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if !c.active_arguments || parameter_index < c.active_first_comptime { ret (empty, false) }
    let offset = parameter_index - c.active_first_comptime
    if offset >= c.active_comptime_count { ret (empty, false) }
    let argument_index = c.active_first_argument + offset
    if argument_index >= c.generic_argument_count || !c.generic_arguments[argument_index].set { ret (empty, false) }
    ret (c.generic_arguments[argument_index], true)
}

fn is_type_node(kind: syntax.Kind) -> bool {
    ret kind == .NamedType || kind == .PointerType || kind == .SliceType || kind == .ArrayType || kind == .FunctionType
}

fn attach_index(c: *Checker, entries: []lookup.Entry) -> err {
    ret lookup.attach(&c.names, entries)
}

fn find_alias(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    if lookup.attached(&c.names) {
        fill_indexes(c)
        if c.names.indexed[3usize] == c.alias_count {
            let (found_at, found) = lookup.find(&c.names, module_index, 3usize, name)
            ret (found_at, found)
        }
    }
    var at = 0usize
    while at < c.alias_count {
        if c.aliases[at].module_index == module_index && same(c.aliases[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn canonical_type(c: *Checker, ty: Type) -> (Type, err) {
    if ty.kind == .Named {
        if ty.has_element { ret (ty, ok) }
        let (alias_index, found) = find_alias(c, ty.module_index, ty.name)
        if !found { ret (ty, ok) }
        if c.aliases[alias_index].generic { ret (invalid_type(), Unsupported) }
        if c.aliases[alias_index].state == 2u8 { ret (c.aliases[alias_index].resolved, ok) }
        if c.aliases[alias_index].state == 1u8 { ret (invalid_type(), AliasCycle) }
        c.aliases[alias_index].state = 1u8
        let (resolved, resolve_error) = canonical_type(c, c.aliases[alias_index].rhs)
        if resolve_error != ok { ret (invalid_type(), resolve_error) }
        c.aliases[alias_index].resolved = resolved
        c.aliases[alias_index].state = 2u8
        ret (resolved, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = canonical_type(c, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        if (ty.kind == .Slice || ty.kind == .Array) && element.kind == .Void { ret (invalid_type(), InvalidType) }
        let (element_index, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var resolved = ty
        resolved.element = element_index
        ret (resolved, ok)
    }
    ret (ty, ok)
}

fn composite_const(c: *Checker, node: syntax.Node, child: syntax.Node) -> (bool, err) {
    var is_const = false
    var at = usize(node.token_start)
    while at < usize(child.token_start) {
        if c.tokens[at].kind == .KwConst { is_const = true }
        if c.tokens[at].kind == .KwShared { ret (false, Unsupported) }
        at += 1usize
    }
    ret (is_const, ok)
}

fn integer_digit(byte: u8) -> (usize, bool) {
    let digits = "0123456789abcdef"
    var lower = byte
    if lower >= 65u8 && lower <= 70u8 { lower += 32u8 }
    var at = 0usize
    while at < digits.len {
        if digits[at] == lower { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn integer_literal_value(c: *Checker, text: str, node: syntax.Node) -> (usize, Type, err) {
    if node.kind != .LiteralExpr { ret (0usize, invalid_type(), Unsupported) }
    let token = c.tokens[usize(node.token_start)]
    if token.kind != .Integer { ret (0usize, invalid_type(), TypeMismatch) }
    let parsed_type = numeric_literal_type(text, token)
    let spelling = text[token.start..token.end]
    var base = 10usize
    var at = 0usize
    if spelling.len >= 2usize && spelling[0usize] == 48u8 {
        let prefix = spelling[1usize]
        if prefix == 120u8 || prefix == 88u8 {
            base = 16usize
            at = 2usize
        } else {
            if prefix == 111u8 || prefix == 79u8 {
                base = 8usize
                at = 2usize
            } else {
                if prefix == 98u8 || prefix == 66u8 {
                    base = 2usize
                    at = 2usize
                }
            }
        }
    }
    var value = 0usize
    var digits = 0usize
    let max_value = 18446744073709551615usize
    while at < spelling.len {
        let byte = spelling[at]
        if byte == 95u8 {
            at += 1usize
        } else {
            let (digit, is_digit) = integer_digit(byte)
            if !is_digit || digit >= base { break }
            digits += 1usize
            if value > (max_value - digit) / base { ret (0usize, invalid_type(), ConstantOverflow) }
            value = value * base + digit
            at += 1usize
        }
    }
    if digits == 0usize { ret (0usize, invalid_type(), Unsupported) }
    ret (value, parsed_type, ok)
}

fn evaluate_array_length_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .CallExpr {
        let (subject, is_array_len) = array_len_subject(c, g, tree, module_index, node)
        if !is_array_len {
            // A call in a length or a `[...]` argument goes to the interpreter (D218), as
            // one in a `const` does; its expression is copied for the evaluation and
            // dropped after, since nothing keeps the index.
            if !c.signatures_ready { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
            let expressions_before = c.constant_expr_count
            let (copied, copy_error) = copy_constant_expr(c, g, tree, module_index, node_index)
            if copy_error != ok {
                c.constant_expr_count = expressions_before
                ret (normalized_integer(0usize, false), invalid_type(), copy_error)
            }
            let (called, called_type, call_error) = evaluate_constant_expr(c, copied, expected)
            c.constant_expr_count = expressions_before
            ret (called, called_type, call_error)
        }
        let (length, length_error) = length_of_subject(c, subject)
        if length_error != ok { ret (normalized_integer(0usize, false), invalid_type(), length_error) }
        let (contextual_type, context_error) = apply_context(c, make_type(.Integer, "usize", module_index), expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (normalized_integer(length, false), contextual_type, ok)
    }
    if node.kind == .LiteralExpr {
        let (magnitude, parsed_type, literal_error) = integer_literal_value(c, text, node)
        if literal_error != ok { ret (normalized_integer(0usize, false), invalid_type(), literal_error) }
        let (contextual_type, context_error) = apply_context(c, parsed_type, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        let value = normalized_integer(magnitude, false)
        if contextual_type.kind == .Integer && !integer_representable(value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (value, contextual_type, ok)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let name = text[token.start..token.end]
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
            let (contextual_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        if !c.constants_ready { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        // Section 9 lists a module-scope `var`, read or written, first among the things a
        // compile-time evaluation may not reach. It has storage that exists only at run time,
        // so there is nothing here for the interpreter to read.
        let (runtime_global, is_runtime_global) = find_global(c, module_index, name)
        if is_runtime_global { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (constant_index, found) = find_constant(c, module_index, name)
        if !found || constant_index >= c.constant_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let item = c.constants[constant_index]
        if item.state == 0u8 && !c.signatures_ready { ret (normalized_integer(0usize, false), invalid_type(), ComptimeDeferred) }
        if item.state != 2u8 { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (contextual_type, context_error) = apply_context(c, item.ty, expected)
        if context_error != ok || !integer_representable(item.value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (item.value, contextual_type, ok)
    }
    if node.kind == .FieldExpr {
        if !c.constants_ready { ret (normalized_integer(0usize, false), invalid_type(), Unsupported) }
        let (target_module, member, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (constant_index, constant_found) = find_constant(c, target_module, member)
        if !constant_found || constant_index >= c.constant_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let item = c.constants[constant_index]
        if item.state == 0u8 && !c.signatures_ready { ret (normalized_integer(0usize, false), invalid_type(), ComptimeDeferred) }
        if item.state != 2u8 { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (contextual_type, context_error) = apply_context(c, item.ty, expected)
        if context_error != ok || !integer_representable(item.value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (item.value, contextual_type, ok)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let (value, value_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, child_index, expected)
        ret (value, value_type, value_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let op = c.tokens[usize(node.token_start)].kind
        var operand_expected = expected
        if op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_array_length_expr(c, g, tree, module_index, child_index, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if op == .PunctTilde {
            if operand_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == 2usize { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
                children[count] = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (normalized_integer(0usize, false), invalid_type(), parse.InvalidSyntax) }
        let op = binary_operator(c, tree, node)
        let (left, left_type, left_error) = evaluate_array_length_expr(c, g, tree, module_index, children[0usize], expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_array_length_expr(c, g, tree, module_index, children[1usize], right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (op == .PunctAmp || op == .PunctCaret || op == .PunctPipe || op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && op != .PunctAddWrap && op != .PunctSubWrap && op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
}

fn array_length_value(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, err) {
    let expected = make_type(.Integer, "usize", module_index)
    let (value, value_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, node_index, expected)
    if value_error == Unsupported || value_error == ComptimeDeferred { ret (0usize, value_error) }
    if value_error != ok || value.negative || value_type.kind != .Integer || !same(value_type.name, "usize") { ret (0usize, TypeMismatch) }
    ret (value.magnitude, ok)
}

fn function_type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    // The node carries one Parameter child per parameter and an optional ReturnSpec,
    // the same shape a `fn` declaration uses.
    var parameter_types: [16]Type = zero
    var parameter_count = 0usize
    var return_types: [4]Type = zero
    var return_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .Parameter {
                if parameter_count == parameter_types.len { ret (invalid_type(), Capacity) }
                let (type_index, has_type) = first_node_child(tree, child)
                if !has_type { ret (invalid_type(), parse.InvalidSyntax) }
                let (parameter_type, parameter_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
                if parameter_error != ok { ret (invalid_type(), parameter_error) }
                if parameter_type.kind == .Void { ret (invalid_type(), InvalidType) }
                parameter_types[parameter_count] = parameter_type
                parameter_count += 1usize
            }
            if child.kind == .ReturnSpec {
                let return_end = usize(child.first_child) + usize(child.child_count)
                var return_at = usize(child.first_child)
                while return_at < return_end {
                    if parse.child_is_node_at(tree, return_at) {
                        if return_count == return_types.len { ret (invalid_type(), Capacity) }
                        let (return_type, return_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[parse.child_index_at(tree, return_at)])
                        if return_error != ok { ret (invalid_type(), return_error) }
                        return_types[return_count] = return_type
                        return_count += 1usize
                    }
                    return_at += 1usize
                }
            }
        }
        at += 1usize
    }
    if return_count == 1usize && return_types[0usize].kind == .Void { return_count = 0usize }
    let first_parameter = c.type_count
    at = 0usize
    while at < parameter_count {
        let (stored, store_error) = store_type(c, parameter_types[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    let first_return = c.type_count
    at = 0usize
    while at < return_count {
        let (stored, store_error) = store_type(c, return_types[at])
        if store_error != ok { ret (invalid_type(), store_error) }
        at += 1usize
    }
    var signature: FunctionSignature = zero
    signature.first_parameter = first_parameter
    signature.parameter_count = parameter_count
    signature.first_return = first_return
    signature.return_count = return_count
    let (signature_index, signature_error) = store_function_signature(c, signature)
    if signature_error != ok { ret (invalid_type(), signature_error) }
    var result = make_type(.Function, "", module_index)
    result.element = signature_index
    result.has_element = true
    ret (result, ok)
}

// The comptime arguments of one instantiation, read from a run of child nodes and
// pushed onto `c.generic_arguments`. Both spellings land here: `St[i64]` written as a
// type, and the same thing written in a comptime argument slot, where the parser gives
// a bracket expression rather than a type node.
// `f.ty` written where a type is written -- an annotation, a parameter, a generic
// argument. The comptime `Field` binding carries the type; every other member of one
// is a value and belongs in an expression.
fn comptime_binding_type_path(c: *Checker, text: str, node: syntax.Node) -> (Type, bool) {
    var base = ""
    var member = ""
    var seen = 0usize
    var at = usize(node.token_start)
    while at < usize(node.token_end) && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket { break }
        if token.kind == .Identifier {
            if seen == 0usize { base = text[token.start..token.end] }
            if seen == 1usize { member = text[token.start..token.end] }
            seen += 1usize
        }
        at += 1usize
    }
    if seen != 2usize || !same(member, "ty") { ret (invalid_type(), false) }
    let (argument, found) = find_comptime_binding(c, base)
    if !found || argument.kind != .Field { ret (invalid_type(), false) }
    ret (argument.ty, true)
}

fn collect_generic_arguments(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, template_index: usize, first_child: usize, child_end: usize) -> (usize, err) {
    if template_index >= c.aggregate_count { ret (0usize, InvalidType) }
    if !c.aggregates[template_index].generic { ret (0usize, InvalidType) }
    let template = c.aggregates[template_index]
    if c.generic_argument_count + template.comptime_count > c.generic_arguments.len { ret (0usize, Capacity) }
    let first_argument = c.generic_argument_count
    // The block is claimed whole before any argument is read, because reading one may
    // instantiate a nested generic -- `Pair[Wrap[i64], u8]` -- whose own arguments are
    // collected through this same function and would otherwise land in the slots this call
    // was about to fill, one at a time, as it went (D145).
    c.generic_argument_count += template.comptime_count
    var argument_count = 0usize
    var at = first_child
    while at < child_end {
        if parse.child_is_node_at(tree, at) {
            if argument_count >= template.comptime_count { ret (0usize, ArgumentCount) }
            let parameter = c.comptime_parameters[template.first_comptime + argument_count]
            let argument_node = parse.child_index_at(tree, at)
            var argument: GenericArgument = zero
            argument.kind = parameter.kind
            argument.set = true
            if parameter.kind == .Field || parameter.kind == .Member {
                // As at a call: a comptime value has no spelling of its own, so the argument is
                // a name that already holds one.
                let value_node = tree.nodes[argument_node]
                if value_node.kind != .NameExpr { ret (0usize, TypeMismatch) }
                let value_token = c.tokens[usize(value_node.token_start)]
                if value_token.kind != .Identifier { ret (0usize, TypeMismatch) }
                let (bound, found_bound) = find_comptime_binding(c, g.modules[module_index].text[value_token.start..value_token.end])
                if !found_bound || bound.kind != parameter.kind { ret (0usize, TypeMismatch) }
                argument = bound
                argument.set = true
            } else {
            if parameter.kind == .Type {
                let (argument_type, argument_error) = comptime_type(c, g, tree, module_index, argument_node)
                if argument_error != ok { ret (0usize, argument_error) }
                argument.ty = argument_type
            } else {
                let (value, value_error) = array_length_value(c, g, tree, module_index, argument_node)
                if value_error == ok {
                    argument.value = value
                } else {
                    if c.active_comptime_count == 0usize || c.active_arguments { ret (0usize, value_error) }
                    let (expression, expression_error) = copy_constant_expr(c, g, tree, module_index, argument_node)
                    if expression_error != ok { ret (0usize, value_error) }
                    argument.expression = expression
                    argument.symbolic = true
                }
            }
            }
            c.generic_arguments[first_argument + argument_count] = argument
            argument_count += 1usize
        }
        at += 1usize
    }
    if argument_count != template.comptime_count { ret (0usize, ArgumentCount) }
    ret (first_argument, ok)
}

fn type_from_node(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    if node.kind == .FunctionType {
        let (function_type, function_type_error) = function_type_from_node(c, r, g, tree, module_index, node)
        ret (function_type, function_type_error)
    }
    if node.kind == .PointerType || node.kind == .SliceType {
        let (child_index, has_child) = first_node_child(tree, node)
        if !has_child { ret (invalid_type(), parse.InvalidSyntax) }
        let child = tree.nodes[child_index]
        let (element_type, element_error) = type_from_node(c, r, g, tree, module_index, child)
        if element_error != ok { ret (invalid_type(), element_error) }
        if node.kind == .SliceType && element_type.kind == .Void { ret (invalid_type(), InvalidType) }
        let (element_index, store_error) = store_type(c, element_type)
        if store_error != ok { ret (invalid_type(), store_error) }
        let (is_const, qualifier_error) = composite_const(c, node, child)
        if qualifier_error != ok { ret (invalid_type(), qualifier_error) }
        var result = make_type(.Pointer, "", module_index)
        if node.kind == .SliceType { result.kind = .Slice }
        result.element = element_index
        result.has_element = true
        result.is_const = is_const
        ret (result, ok)
    }
    if node.kind == .ArrayType {
        let end = usize(node.first_child) + usize(node.child_count)
        var element_index = 0usize
        var has_element = false
        var length_index = 0usize
        var has_length = false
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let child_index = parse.child_index_at(tree, at)
                if is_type_node(tree.nodes[child_index].kind) {
                    element_index = child_index
                    has_element = true
                } else {
                    length_index = child_index
                    has_length = true
                }
            }
            at += 1usize
        }
        if !has_element { ret (invalid_type(), parse.InvalidSyntax) }
        if !has_length { ret (invalid_type(), Unsupported) }
        let (element_type, element_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[element_index])
        if element_error != ok { ret (invalid_type(), element_error) }
        if element_type.kind == .Void { ret (invalid_type(), InvalidType) }
        let (stored_element, store_error) = store_type(c, element_type)
        if store_error != ok { ret (invalid_type(), store_error) }
        var length = 0usize
        var has_concrete_length = false
        var length_expression = 0usize
        let (resolved_length, length_error) = array_length_value(c, g, tree, module_index, length_index)
        if length_error == ok {
            length = resolved_length
            has_concrete_length = true
        } else {
            if c.active_comptime_count == 0usize || c.active_arguments {
                if length_error == TypeMismatch { record_failure(c, module_index, tree.nodes[length_index], .ArrayLengthType, "", "") }
                if length_error == ComptimeDeferred { record_failure(c, module_index, tree.nodes[length_index], .ComptimeDeferredUse, "", "") }
                ret (invalid_type(), length_error)
            }
            let (copied_expression, expression_error) = copy_constant_expr(c, g, tree, module_index, length_index)
            if expression_error != ok { ret (invalid_type(), length_error) }
            length_expression = copied_expression
        }
        var result = make_type(.Array, "", module_index)
        result.element = stored_element
        result.has_element = true
        result.array_length = length
        if !has_concrete_length { result.array_length = length_expression }
        result.has_length = has_concrete_length
        ret (result, ok)
    }
    if node.kind != .NamedType {
        record_failure(c, module_index, node, .NotAType, "", "")
        ret (make_type(.Other, "", module_index), Unsupported)
    }
    let first = c.tokens[usize(node.token_start)]
    if first.kind != .Identifier {
        record_failure(c, module_index, node, .NotAType, g.modules[module_index].text[first.start..first.end], "")
        ret (make_type(.Other, "", module_index), Unsupported)
    }
    // A trailing `()` is the only shape a comptime call has here, and it is exactly the last two
    // tokens because that is all the parser accepts. Looking anywhere else in the range would
    // find the parentheses of an ordinary argument -- `Inner[(N << 1u8) | 1usize]` has a `(` in
    // it and is an instantiation, not a call.
    var has_call = false
    if usize(node.token_end) >= usize(node.token_start) + 2usize {
        if c.tokens[usize(node.token_end) - 2usize].kind == .PunctLParen && c.tokens[usize(node.token_end) - 1usize].kind == .PunctRParen { has_call = true }
    }
    if has_call {
        let (derived, derived_error) = named_type_derived(c, g, tree, module_index, node)
        ret (derived, derived_error)
    }
    let base = g.modules[module_index].text[first.start..first.end]
    let scalar = scalar_type(base, module_index)
    if scalar.kind != .Invalid {
        let (scalar_module, scalar_qualified) = resolve.qualifier(r, module_index, base)
        if !scalar_qualified || !named_type_is_path(c, node) { ret (scalar, ok) }
    }
    let (bound_type, is_bound_path) = comptime_binding_type_path(c, g.modules[module_index].text, node)
    if is_bound_path { ret (bound_type, ok) }
    let (parameter_index, parameter_found) = active_comptime_parameter(c, base)
    if parameter_found {
        if c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), InvalidType) }
        let (argument, argument_found) = active_argument(c, parameter_index)
        if argument_found { ret (argument.ty, ok) }
        var parameter_type = make_type(.TypeParameter, base, module_index)
        parameter_type.element = parameter_index
        parameter_type.has_element = true
        ret (parameter_type, ok)
    }
    // `target.Arch` and `target.Os` (D223): section 2's namespace, seeded into the root.
    if same(base, "target") && named_type_is_path(c, node) {
        var member_at = usize(node.token_start) + 1usize
        while member_at < usize(node.token_end) {
            let member_token = c.tokens[member_at]
            if member_token.kind == .Identifier {
                let member = g.modules[module_index].text[member_token.start..member_token.end]
                if same(member, "Arch") { ret (target_enum_type("arch"), ok) }
                if same(member, "Os") { ret (target_enum_type("os"), ok) }
                break
            }
            member_at += 1usize
        }
        record_failure(c, module_index, node, .NotAType, base, "")
        ret (invalid_type(), InvalidType)
    }
    var target_module = module_index
    var name = base
    let (qualified_module, has_qualifier) = resolve.qualifier(r, module_index, base)
    if has_qualifier { target_module = qualified_module }
    var entry_arena = false
    if !has_qualifier && same(base, "mem") {
        var entry_at = usize(node.token_start) + 1usize
        var entry_state = 0usize
        var valid_entry = true
        while entry_at < usize(node.token_end) {
            let entry_token = c.tokens[entry_at]
            if entry_token.kind == .Newline {
                entry_at += 1usize
            } else {
                if entry_state == 0usize && entry_token.kind == .PunctDot {
                    entry_state = 1usize
                } else {
                    if entry_state == 1usize && entry_token.kind == .Identifier {
                        let entry_name = g.modules[module_index].text[entry_token.start..entry_token.end]
                        if same(entry_name, "Arena") {
                            name = entry_name
                            entry_state = 2usize
                        } else {
                            valid_entry = false
                        }
                    } else {
                        valid_entry = false
                    }
                }
                entry_at += 1usize
            }
            if !valid_entry { break }
        }
        if valid_entry && entry_state == 2usize {
            entry_arena = true
            let (memory_module, has_memory_module) = graph.find_module(g, "e.mem")
            if has_memory_module { target_module = memory_module }
        }
    }
    var path_identifiers = 0usize
    var wants_tag = false
    var has_arguments = false
    var at = usize(node.token_start) + 1usize
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket {
            has_arguments = true
            break
        }
        if token.kind == .Identifier {
            let part = g.modules[module_index].text[token.start..token.end]
            if has_qualifier {
                if path_identifiers == 0usize {
                    name = part
                } else {
                    if path_identifiers != 1usize || !same(part, "Tag") { ret (invalid_type(), InvalidType) }
                    wants_tag = true
                }
            } else {
                if entry_arena {
                    path_identifiers += 1usize
                    at += 1usize
                    continue
                }
                if path_identifiers != 0usize || !same(part, "Tag") { ret (invalid_type(), InvalidType) }
                wants_tag = true
            }
            path_identifiers += 1usize
        }
        at += 1usize
    }
    if has_qualifier && path_identifiers == 0usize { ret (invalid_type(), InvalidType) }
    if wants_tag && has_arguments { ret (invalid_type(), InvalidType) }
    // Section 4 reserves `Atomic`, and no module declares it: the bare name is the
    // section 8 builtin wherever it is written.
    var atomic_named = false
    if !has_qualifier && same(name, "Atomic") {
        let (atomic_module, has_atomic) = graph.find_module(g, "e.atomic")
        if has_atomic {
            target_module = atomic_module
            atomic_named = true
        }
    }
    // Section 4 reserves `Vec` and `Mask` the same way; both are the builtins seeded in
    // `e.simd`, and which `(T, N)` they admit is the closed table, checked at the
    // instantiation like `Atomic`'s element.
    var vector_named = false
    if !has_qualifier && (same(name, "Vec") || same(name, "Mask")) && c.has_simd {
        target_module = c.simd_module
        vector_named = true
    }
    var result = make_type(.Named, name, target_module)
    if has_arguments {
        let (template_index, found_template) = find_aggregate(c, target_module, name)
        if !found_template {
            if !c.expand_aliases { ret (make_type(.Other, "", module_index), Unsupported) }
            ret (invalid_type(), InvalidType)
        }
        let (first_argument, collect_error) = collect_generic_arguments(c, g, tree, module_index, template_index, usize(node.first_child), usize(node.first_child) + usize(node.child_count))
        if collect_error != ok { ret (invalid_type(), collect_error) }
        if atomic_named {
            let argument = c.generic_arguments[first_argument]
            if argument.kind != .Type || !atomic_element_legal(argument.ty) {
                record_failure(c, module_index, node, .AtomicElement, argument.ty.name, "")
                ret (invalid_type(), InvalidType)
            }
        }
        if vector_named && !vector_shape_legal(c, first_argument) {
            record_failure(c, module_index, node, .VectorShape, name, "")
            ret (invalid_type(), InvalidType)
        }
        let (instance_index, instance_error) = instantiate_aggregate(c, template_index, first_argument)
        if instance_error != ok { ret (invalid_type(), instance_error) }
        result.element = instance_index
        result.has_element = true
        ret (result, ok)
    }
    if wants_tag {
        let (canonical_subject, canonical_error) = canonical_type(c, result)
        if canonical_error != ok { ret (invalid_type(), canonical_error) }
        let (tag, found_tag) = tagged_union_tag_type(c, canonical_subject)
        if !found_tag { ret (invalid_type(), InvalidType) }
        ret (tag, ok)
    }
    if !c.expand_aliases { ret (result, ok) }
    let (canonical, canonical_error) = canonical_type(c, result)
    if canonical_error != ok { ret (canonical, canonical_error) }
    // `collect_aliases`' first pass runs before any aggregate is registered, so an
    // alias to a generic instantiation defers to `.Other` there. Expanding to that
    // would freeze it into whatever names the alias -- an aggregate's field type,
    // collected before the second pass resolves the alias for real. Keep the name
    // instead and let it canonicalise at use, by which time the alias is resolved.
    // An alias that never resolves is not silently lost: the second pass is strict
    // and fails on the same right-hand side.
    if canonical.kind == .Other { ret (result, ok) }
    ret (canonical, ok)
}

fn declaration_name(c: *Checker, text: str, node: syntax.Node) -> (str, err) {
    let name_index = usize(node.token_start) + 1usize
    if name_index >= usize(node.token_end) || name_index >= c.token_count { ret ("", parse.InvalidSyntax) }
    let token = c.tokens[name_index]
    if token.kind != .Identifier { ret ("", parse.InvalidSyntax) }
    ret (text[token.start..token.end], ok)
}

fn collect_alias_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, allow_deferred: bool) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var rhs_index = 0usize
    var has_rhs = false
    var generic = false
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam { generic = true }
            if is_type_node(child.kind) {
                rhs_index = child_index
                has_rhs = true
            }
        }
        at += 1usize
    }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    if generic {
        if c.alias_count == c.aliases.len { ret Capacity }
        c.aliases[c.alias_count] = Alias { name: name, module_index: module_index, generic: true, rhs: invalid_type(), resolved: invalid_type(), state: 0u8 }
        c.alias_count += 1usize
        ret ok
    }
    if !has_rhs { ret ok }
    if c.alias_count == c.aliases.len { ret Capacity }
    var (rhs, rhs_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[rhs_index])
    if rhs_error != ok {
        if !allow_deferred || rhs_error != Unsupported { ret rhs_error }
        rhs = make_type(.Other, "", module_index)
    }
    c.aliases[c.alias_count] = Alias { name: name, module_index: module_index, generic: false, rhs: rhs, resolved: invalid_type(), state: 0u8 }
    c.alias_count += 1usize
    ret ok
}

fn collect_aliases(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, allow_deferred: bool) -> err {
    c.alias_count = 0usize
    if allow_deferred { c.type_count = 0usize }
    c.expand_aliases = false
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try graph.parse_module(g, module_index, &tree)
        try tokenize_module(c, g, module_index)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .TypeDecl { try collect_alias_declaration(c, r, g, &tree, module_index, node, allow_deferred) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    c.expand_aliases = true
    if allow_deferred { ret ok }
    var alias_index = 0usize
    while alias_index < c.alias_count {
        if !c.aliases[alias_index].generic {
            let (resolved, resolve_error) = canonical_type(c, c.aliases[alias_index].rhs)
            if resolve_error != ok { ret resolve_error }
            c.aliases[alias_index].resolved = resolved
            c.aliases[alias_index].state = 2u8
        }
        alias_index += 1usize
    }
    ret ok
}

fn find_aggregate(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    if lookup.attached(&c.names) {
        fill_indexes(c)
        if c.names.indexed[2usize] == c.aggregate_count {
            let (found_at, found) = lookup.find(&c.names, module_index, 2usize, name)
            ret (found_at, found)
        }
    }
    var at = 0usize
    while at < c.aggregate_count {
        if c.aggregates[at].module_index == module_index && same(c.aggregates[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// A field the aggregate does not declare (D448): the diagnostic at the member's
// token naming the type and the field, and the nearest field within two edits as
// a fix over the token (kind 4, the name a slice of the declaration).
fn note_missing_field(c: *Checker, module_index: usize, node: syntax.Node, base: Type, field: str) {
    if c.failure_has_token { ret }
    var subject = base
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret }
        subject = c.types[subject.element]
    }
    if subject.kind != .Named { ret }
    if usize(node.token_end) == 0usize || usize(node.token_end) > c.token_count { ret }
    let member_token = c.tokens[usize(node.token_end) - 1usize]
    append_failure_token(c, module_index, member_token, .FieldMissing, subject.name, field)
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found || field.len < 3usize { ret }
    let aggregate = c.aggregates[aggregate_index]
    var best = ""
    var best_distance = 3usize
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count {
            let candidate = c.aggregate_fields[field_index].name
            let distance = resolve.edit_distance(candidate, field)
            if candidate.len >= 1usize && distance < best_distance {
                best = candidate
                best_distance = distance
            }
        }
        at += 1usize
    }
    if best.len != 0usize {
        c.failure_fix_text = best
        c.failure_fix_kind = 4u8
        c.failure_fix_at = member_token.start
        c.failure_mismatch_end = member_token.end
    }
}

fn find_aggregate_field(c: *Checker, ty: Type, name: str) -> (usize, bool) {
    var subject = ty
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret (0usize, false) }
        subject = c.types[subject.element]
    }
    if subject.kind != .Named { ret (0usize, false) }
    var aggregate_index = 0usize
    var found = false
    if subject.has_element && subject.element < c.aggregate_count {
        aggregate_index = subject.element
        found = true
    } else {
        (aggregate_index, found) = find_aggregate(c, subject.module_index, subject.name)
    }
    if !found { ret (0usize, false) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance {
        if aggregate.template_index >= c.aggregate_count { ret (0usize, false) }
        aggregate = c.aggregates[aggregate.template_index]
    }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count && same(c.aggregate_fields[field_index].name, name) { ret (field_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn aggregate_for_type(c: *Checker, ty: Type) -> (usize, bool) {
    if ty.kind != .Named && ty.kind != .Tag { ret (0usize, false) }
    if ty.has_element && ty.element < c.aggregate_count { ret (ty.element, true) }
    let (aggregate_index, found) = find_aggregate(c, ty.module_index, ty.name)
    ret (aggregate_index, found)
}

fn is_enum_type(c: *Checker, ty: Type) -> bool {
    if ty.kind == .Tag { ret ty.has_element && ty.element < c.aggregate_count && c.aggregates[ty.element].kind == .TaggedUnion }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    ret found && c.aggregates[aggregate_index].kind == .Enum
}

// An enum member is stored as its backing integer's bits, so a negative member
// is its two's complement at the backing width. Written as `(mask - magnitude) + 1`
// rather than `2^width - magnitude`, which overflows a `usize` at width 64.
fn enum_member_bits(backing: Type, magnitude: usize, negative: bool) -> (usize, err) {
    if !negative { ret (magnitude, ok) }
    if backing.kind != .Integer { ret (0usize, InvalidType) }
    var mask = 18446744073709551615usize
    if same(backing.name, "i8") || same(backing.name, "u8") { mask = 255usize }
    if same(backing.name, "i16") || same(backing.name, "u16") { mask = 65535usize }
    if same(backing.name, "i32") || same(backing.name, "u32") { mask = 4294967295usize }
    if magnitude == 0usize || magnitude > mask { ret (0usize, InvalidType) }
    ret ((mask - magnitude) + 1usize, ok)
}

// An enum's ordering is its backing integer's ordering, so the backing type has
// to be reachable from a value's type. Nothing else about an enum survives past
// lowering.
fn enum_backing_type(c: *Checker, ty: Type) -> (Type, bool) {
    if ty.kind != .Named { ret (invalid_type(), false) }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .Enum { ret (invalid_type(), false) }
    let backing = c.aggregates[aggregate_index].backing_type
    if backing.kind != .Integer { ret (invalid_type(), false) }
    ret (backing, true)
}

fn tagged_union_tag_type(c: *Checker, ty: Type) -> (Type, bool) {
    var subject = ty
    while subject.kind == .Pointer {
        if !subject.has_element || subject.element >= c.type_count { ret (invalid_type(), false) }
        subject = c.types[subject.element]
    }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret (invalid_type(), false) }
    var tag = make_type(.Tag, c.aggregates[aggregate_index].name, c.aggregates[aggregate_index].module_index)
    tag.element = aggregate_index
    tag.has_element = true
    ret (tag, true)
}

fn field_expression_name(c: *Checker, text: str, tree: *parse.Tree, node: syntax.Node) -> (str, bool) {
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret ("", false) }
    let base = tree.nodes[base_index]
    var name = ""
    var at = usize(base.token_end)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier { name = text[token.start..token.end] }
        at += 1usize
    }
    ret (name, name.len != 0usize)
}

fn aggregate_declaration_shape(tree: *parse.Tree, node: syntax.Node) -> (usize, AggregateKind, bool, bool) {
    var body_index = 0usize
    var has_body = false
    var generic = false
    var kind: AggregateKind = .Struct
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam { generic = true }
            if child.kind == .StructType || child.kind == .UnionType || child.kind == .UnionEnumType || child.kind == .EnumType {
                body_index = child_index
                has_body = true
                if child.kind == .UnionType { kind = .Union }
                if child.kind == .UnionEnumType { kind = .TaggedUnion }
                if child.kind == .EnumType { kind = .Enum }
            }
        }
        at += 1usize
    }
    ret (body_index, kind, generic, has_body)
}

fn register_aggregate_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (body_index, kind, generic, has_body) = aggregate_declaration_shape(tree, node)
    if !has_body { ret ok }
    if c.aggregate_count == c.aggregates.len { ret Capacity }
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let aggregate_index = c.aggregate_count
    var aggregate = Aggregate { name: name, module_index: module_index, kind: kind, first_field: 0usize, field_count: 0usize, first_comptime: c.comptime_parameter_count, comptime_count: 0usize, template_index: aggregate_index, first_argument: 0usize, generic: generic, instance: false, backing_type: invalid_type(), token: c.tokens[usize(node.token_start)], resource: false, cleanup: "", affine_memo: 0u8, pointer_memo: 0u8 }
    // `resource` and its cleanup sit between the `=` and the body (D348).
    let (is_resource, cleanup) = resource_declaration(c, g.modules[module_index].text, node, tree.nodes[body_index])
    aggregate.resource = is_resource
    aggregate.cleanup = cleanup
    c.aggregates[aggregate_index] = aggregate
    c.aggregate_count += 1usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .ComptimeParam {
                c.active_first_comptime = aggregate.first_comptime
                c.active_comptime_count = aggregate.comptime_count
                try collect_comptime_parameter(c, r, g, tree, module_index, child)
                aggregate.comptime_count += 1usize
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.aggregates[aggregate_index] = aggregate
    ret ok
}

fn collect_aggregate_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (body_index, kind, generic, has_body) = aggregate_declaration_shape(tree, node)
    if !has_body { ret ok }
    let (name, name_error) = declaration_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (aggregate_index, found_aggregate) = find_aggregate(c, module_index, name)
    if !found_aggregate { ret InvalidType }
    var aggregate = c.aggregates[aggregate_index]
    aggregate.first_field = c.aggregate_field_count
    aggregate.field_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    c.active_first_comptime = aggregate.first_comptime
    c.active_comptime_count = aggregate.comptime_count
    let body = tree.nodes[body_index]
    let body_end = usize(body.first_child) + usize(body.child_count)
    var backing_type = invalid_type()
    if kind == .Enum || kind == .TaggedUnion {
        var backing_at = usize(body.first_child)
        while backing_at < body_end {
            if parse.child_is_node_at(tree, backing_at) {
                let backing_node = tree.nodes[parse.child_index_at(tree, backing_at)]
                if is_type_node(backing_node.kind) {
                    let (resolved_backing, backing_error) = type_from_node(c, r, g, tree, module_index, backing_node)
                    if backing_error != ok { ret backing_error }
                    backing_type = resolved_backing
                    break
                }
            }
            backing_at += 1usize
        }
        if backing_type.kind != .Integer { ret InvalidType }
        aggregate.backing_type = backing_type
    }
    var next_enum_value = 0usize
    var next_enum_negative = false
    var next_enum_valid = true
    at = usize(body.first_child)
    while at < body_end {
        if parse.child_is_node_at(tree, at) {
            let field_node = tree.nodes[parse.child_index_at(tree, at)]
            if field_node.kind == .FieldDecl || field_node.kind == .UnionMember || field_node.kind == .EnumMember {
                if c.aggregate_field_count == c.aggregate_fields.len { ret Capacity }
                let (field_name, has_name) = first_name(c, g.modules[module_index].text, field_node)
                if !has_name { ret parse.InvalidSyntax }
                var field_type = make_type(.Void, "void", module_index)
                let (type_index, has_type) = first_node_child(tree, field_node)
                if has_type && kind != .Enum {
                    let (resolved, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
                    if type_error != ok { ret type_error }
                    field_type = resolved
                } else {
                    // A field whose type is not a type node at all -- `ty: type` is
                    // the one that turns up, `type` being a compile-time parameter
                    // and not something a field can hold. Reported here because the
                    // parse error this used to raise carried no token.
                    if kind != .TaggedUnion && kind != .Enum {
                        record_failure(c, module_index, field_node, .NotAType, field_name, "")
                        ret parse.InvalidSyntax
                    }
                }
                if field_type.kind == .Void && kind != .TaggedUnion && kind != .Enum { ret InvalidType }
                var prior_at = 0usize
                while prior_at < aggregate.field_count {
                    let prior = c.aggregate_fields[aggregate.first_field + prior_at]
                    if same(prior.name, field_name) { ret InvalidType }
                    prior_at += 1usize
                }
                var enum_value = next_enum_value
                var enum_negative = next_enum_negative
                var has_enum_value = kind == .Enum || kind == .TaggedUnion
                if kind == .Enum && has_type {
                    let (explicit_value, explicit_type, value_error) = evaluate_array_length_expr(c, g, tree, module_index, type_index, invalid_type())
                    if value_error != ok { ret value_error }
                    if explicit_type.kind != .Integer && explicit_type.kind != .UntypedInteger { ret InvalidType }
                    enum_value = explicit_value.magnitude
                    enum_negative = explicit_value.negative
                } else {
                    if has_enum_value && !next_enum_valid { ret ConstantOverflow }
                }
                if has_enum_value {
                    let value = normalized_integer(enum_value, enum_negative)
                    prior_at = 0usize
                    while prior_at < aggregate.field_count {
                        let prior = c.aggregate_fields[aggregate.first_field + prior_at]
                        if prior.has_enum_value && prior.enum_value == enum_value && prior.enum_negative == enum_negative {
                            append_failure_token(c, module_index, c.tokens[usize(field_node.token_start)], .DuplicateEnumValue, field_name, "")
                            break
                        }
                        prior_at += 1usize
                    }
                    if !integer_representable(value, backing_type) {
                        append_failure_token(c, module_index, c.tokens[usize(field_node.token_start)], .EnumValueRange, field_name, "")
                    }
                    if enum_negative {
                        if enum_value > 1usize {
                            next_enum_value = enum_value - 1usize
                            next_enum_negative = true
                        } else {
                            next_enum_value = 0usize
                            next_enum_negative = false
                        }
                        next_enum_valid = true
                    } else {
                        if enum_value == 18446744073709551615usize {
                            next_enum_valid = false
                        } else {
                            next_enum_value = enum_value + 1usize
                            next_enum_negative = false
                            next_enum_valid = true
                        }
                    }
                }
                // An aggregate's fields are one contiguous run starting at
                // `first_field`, but resolving a field's type can instantiate a
                // generic aggregate, and an instance appends its own fields --
                // splitting the run this loop is still filling. Move what has been
                // collected so far to the end and keep appending there.
                if c.aggregate_field_count != aggregate.first_field + aggregate.field_count {
                    if c.aggregate_field_count + aggregate.field_count >= c.aggregate_fields.len { ret Capacity }
                    var moved = 0usize
                    while moved < aggregate.field_count {
                        c.aggregate_fields[c.aggregate_field_count + moved] = c.aggregate_fields[aggregate.first_field + moved]
                        moved += 1usize
                    }
                    aggregate.first_field = c.aggregate_field_count
                    c.aggregate_field_count += aggregate.field_count
                }
                if c.aggregate_field_count == c.aggregate_fields.len { ret Capacity }
                c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: field_name, ty: field_type, enum_value: enum_value, enum_negative: enum_negative, has_enum_value: has_enum_value, token: c.tokens[usize(field_node.token_start)] }
                c.aggregate_field_count += 1usize
                aggregate.field_count += 1usize
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    if kind != .Struct && aggregate.field_count == 0usize { ret InvalidType }
    c.aggregates[aggregate_index] = aggregate
    ret ok
}

// Section 2's `target` namespace (D223): `target.Arch` and `target.Os`, enums seeded
// into the root module under names no source can spell, so `target.arch` and
// `target.os` are values of them and a member literal compares against them.
fn seed_target_enum(c: *Checker, name: str, members: []const str) -> err {
    if c.aggregate_count == c.aggregates.len || c.aggregate_field_count + members.len > c.aggregate_fields.len { ret Capacity }
    let backing = make_type(.Integer, "u8", 0usize)
    c.aggregates[c.aggregate_count] = Aggregate { name: name, module_index: 0usize, kind: .Enum, first_field: c.aggregate_field_count, field_count: members.len, first_comptime: c.comptime_parameter_count, comptime_count: 0usize, template_index: c.aggregate_count, first_argument: 0usize, generic: false, instance: false, backing_type: backing, token: zero, resource: false, cleanup: "", affine_memo: 0u8, pointer_memo: 0u8 }
    var at = 0usize
    while at < members.len {
        c.aggregate_fields[c.aggregate_field_count + at] = AggregateField { name: members[at], ty: backing, enum_value: at, enum_negative: false, has_enum_value: true, token: zero }
        at += 1usize
    }
    c.aggregate_field_count += members.len
    c.aggregate_count += 1usize
    ret ok
}

fn target_enum_type(question: str) -> Type {
    if same(question, "arch") { ret make_type(.Named, "target.Arch", 0usize) }
    ret make_type(.Named, "target.Os", 0usize)
}

// The current target's member of the enum, by the spelling rule `target_is` uses.
fn target_enum_value(c: *Checker, g: *graph.Graph, question: str) -> (usize, err) {
    let (aggregate_index, found) = aggregate_for_type(c, target_enum_type(question))
    if !found { ret (0usize, InvalidType) }
    let aggregate = c.aggregates[aggregate_index]
    var current = g.os
    if same(question, "arch") { current = g.arch }
    var at = 0usize
    while at < aggregate.field_count {
        let member = c.aggregate_fields[aggregate.first_field + at]
        if target_is(current, member.name) { ret (member.enum_value, ok) }
        at += 1usize
    }
    ret (0usize, InvalidType)
}

fn seed_intrinsic_aggregates(c: *Checker, g: *graph.Graph) -> err {
    var arch_members: [5]str = zero
    arch_members[0usize] = "X64"
    arch_members[1usize] = "Aarch64"
    arch_members[2usize] = "X86"
    arch_members[3usize] = "Spv"
    arch_members[4usize] = "Ptx"
    try seed_target_enum(c, "target.Arch", arch_members[..])
    var os_members: [4]str = zero
    os_members[0usize] = "Windows"
    os_members[1usize] = "Linux"
    os_members[2usize] = "Macos"
    os_members[3usize] = "None"
    try seed_target_enum(c, "target.Os", os_members[..])
    let (memory_module, has_memory) = graph.find_module(g, "e.mem")
    if has_memory {
        if c.aggregate_count == c.aggregates.len || c.aggregate_field_count + 2usize > c.aggregate_fields.len { ret Capacity }
        let usize_type = make_type(.Integer, "usize", memory_module)
        c.aggregates[c.aggregate_count] = Aggregate { name: "Stats", module_index: memory_module, kind: .Struct, first_field: c.aggregate_field_count, field_count: 2usize, first_comptime: c.comptime_parameter_count, comptime_count: 0usize, template_index: c.aggregate_count, first_argument: 0usize, generic: false, instance: false, backing_type: invalid_type(), token: zero, resource: false, cleanup: "", affine_memo: 0u8, pointer_memo: 0u8 }
        c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: "used", ty: usize_type, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
        c.aggregate_fields[c.aggregate_field_count + 1usize] = AggregateField { name: "capacity", ty: usize_type, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
        c.aggregate_field_count += 2usize
        c.aggregate_count += 1usize
    }
    // Section 8: `Atomic[T]` is a builtin, not a library type, so it is seeded rather
    // than written. One field of type `T` gives it exactly section 4's layout -- `T`'s
    // size and alignment -- and section 7's zero value, the wrapped value zero, with no
    // rule of its own. Which `T` it admits is checked at the instantiation.
    let (atomic_module, has_atomic) = graph.find_module(g, "e.atomic")
    if has_atomic {
        if c.aggregate_count == c.aggregates.len || c.aggregate_field_count == c.aggregate_fields.len { ret Capacity }
        if c.comptime_parameter_count == c.comptime_parameters.len { ret Capacity }
        let parameter_index = c.comptime_parameter_count
        c.comptime_parameters[parameter_index] = ComptimeParameter { name: "T", kind: .Type, ty: invalid_type() }
        c.comptime_parameter_count += 1usize
        var element = make_type(.TypeParameter, "T", atomic_module)
        element.element = parameter_index
        element.has_element = true
        c.aggregates[c.aggregate_count] = Aggregate { name: "Atomic", module_index: atomic_module, kind: .Struct, first_field: c.aggregate_field_count, field_count: 1usize, first_comptime: parameter_index, comptime_count: 1usize, template_index: c.aggregate_count, first_argument: 0usize, generic: true, instance: false, backing_type: invalid_type(), token: zero, resource: false, cleanup: "", affine_memo: 0u8, pointer_memo: 0u8 }
        c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: "value", ty: element, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
        c.aggregate_field_count += 1usize
        c.aggregate_count += 1usize
    }
    // Section 4: `Vec[T, N]` and `Mask[T, N]` are builtins too, seeded into `e.simd`. Each
    // is one field `lanes: [N]T` -- a `[N]bool` for the mask -- which gives the width for
    // free; the alignment, which section 4 says equals the width, is layout's one special
    // case. The lanes field is what `e.simd`'s source works over, lane by lane.
    // ponytail: every operation is a scalar loop over `lanes`; a vector register class and
    // SSE selection are the upgrade path, and nothing in the source changes for it.
    let (simd_module, has_simd) = graph.find_module(g, "e.simd")
    if has_simd {
        c.simd_module = simd_module
        c.has_simd = true
        var which = 0usize
        while which < 2usize {
            if c.aggregate_count == c.aggregates.len || c.aggregate_field_count == c.aggregate_fields.len { ret Capacity }
            if c.comptime_parameter_count + 2usize > c.comptime_parameters.len { ret Capacity }
            let parameter_index = c.comptime_parameter_count
            c.comptime_parameters[parameter_index] = ComptimeParameter { name: "T", kind: .Type, ty: invalid_type() }
            c.comptime_parameters[parameter_index + 1usize] = ComptimeParameter { name: "N", kind: .Integer, ty: make_type(.Integer, "usize", simd_module) }
            c.comptime_parameter_count += 2usize
            var lane = make_type(.TypeParameter, "T", simd_module)
            lane.element = parameter_index
            lane.has_element = true
            if which == 1usize { lane = make_type(.Bool, "bool", simd_module) }
            let (stored_lane, store_error) = store_type(c, lane)
            if store_error != ok { ret store_error }
            var count: ConstantExpr = zero
            count.kind = .Name
            count.module_index = simd_module
            count.name = "N"
            let (count_index, count_error) = store_constant_expr(c, count)
            if count_error != ok { ret count_error }
            var lanes = make_type(.Array, "", simd_module)
            lanes.element = stored_lane
            lanes.has_element = true
            lanes.array_length = count_index
            lanes.has_length = false
            var name = "Vec"
            if which == 1usize { name = "Mask" }
            c.aggregates[c.aggregate_count] = Aggregate { name: name, module_index: simd_module, kind: .Struct, first_field: c.aggregate_field_count, field_count: 1usize, first_comptime: parameter_index, comptime_count: 2usize, template_index: c.aggregate_count, first_argument: 0usize, generic: true, instance: false, backing_type: invalid_type(), token: zero, resource: false, cleanup: "", affine_memo: 0u8, pointer_memo: 0u8 }
            c.aggregate_fields[c.aggregate_field_count] = AggregateField { name: "lanes", ty: lanes, enum_value: 0usize, enum_negative: false, has_enum_value: false, token: zero }
            c.aggregate_field_count += 1usize
            c.aggregate_count += 1usize
            which += 1usize
        }
    }
    ret ok
}

// Section 4's closed table: `T` an integer or float primitive other than `usize` and
// `isize`, and `N * size_of(T)` one of 16, 32 or 64 bytes. Arguments still symbolic --
// a `Vec[T, N]` inside another generic -- are settled when they are bound.
fn vector_shape_legal(c: *Checker, first_argument: usize) -> bool {
    let lane = c.generic_arguments[first_argument]
    let count = c.generic_arguments[first_argument + 1usize]
    if lane.kind != .Type || count.kind != .Integer { ret false }
    if lane.ty.kind == .TypeParameter || count.symbolic { ret true }
    if lane.ty.kind != .Integer && lane.ty.kind != .Float { ret false }
    if same(lane.ty.name, "usize") || same(lane.ty.name, "isize") { ret false }
    var width = 8usize
    if same(lane.ty.name, "i8") || same(lane.ty.name, "u8") { width = 1usize }
    if same(lane.ty.name, "i16") || same(lane.ty.name, "u16") || same(lane.ty.name, "f16") || same(lane.ty.name, "bf16") { width = 2usize }
    if same(lane.ty.name, "i32") || same(lane.ty.name, "u32") || same(lane.ty.name, "f32") { width = 4usize }
    let bytes = count.value * width
    ret bytes == 16usize || bytes == 32usize || bytes == 64usize
}

// A concrete `Vec[T, N]` or `Mask[T, N]` instance, answered as its `lanes` field: the
// `[N]T` whose element and length are the two things `e.meta` asks a vector for.
fn vector_lanes(c: *Checker, ty: Type) -> (Type, bool) {
    if !is_vector_type(c, ty) || c.aggregates[ty.element].generic { ret (invalid_type(), false) }
    let aggregate = c.aggregates[ty.element]
    if aggregate.field_count != 1usize || aggregate.first_field >= c.aggregate_field_count { ret (invalid_type(), false) }
    ret (c.aggregate_fields[aggregate.first_field].ty, true)
}

// Any instance of the two, concrete or not: `Vec[T, N]` inside another generic's
// template is one whose lanes are not known yet, and a question about it defers the
// way one about `T` itself does.
fn is_vector_type(c: *Checker, ty: Type) -> bool {
    if !c.has_simd || ty.kind != .Named || !ty.has_element || ty.element >= c.aggregate_count { ret false }
    let aggregate = c.aggregates[ty.element]
    if aggregate.module_index != c.simd_module || !aggregate.instance { ret false }
    ret same(aggregate.name, "Vec") || same(aggregate.name, "Mask")
}

fn vector_pending(c: *Checker, ty: Type) -> bool {
    ret is_vector_type(c, ty) && c.aggregates[ty.element].generic
}

// The lane type of a concrete vector, for the operator table and for lowering.
fn vector_lane_type(c: *Checker, ty: Type) -> (Type, bool) {
    let (lanes, is_vector) = vector_lanes(c, ty)
    if !is_vector || !lanes.has_element || lanes.element >= c.type_count { ret (invalid_type(), false) }
    ret (c.types[lanes.element], true)
}

// Section 4's operator table, lane by lane: float lanes take the four IEEE operations;
// integer lanes only the wrapping forms, the bitwise ones and a scalar shift, because a
// vector unit has no overflow flag and `/` is no target's one instruction; a mask takes
// the bitwise ones. Comparisons are never operators on a vector -- `simd.cmp_*` are.
fn vector_operator_legal(c: *Checker, ty: Type, op: lex.Kind) -> bool {
    let (lane, is_vector) = vector_lane_type(c, ty)
    if !is_vector { ret false }
    if lane.kind == .Float { ret op == .PunctPlus || op == .PunctMinus || op == .PunctStar || op == .PunctSlash }
    let bitwise = op == .PunctAmp || op == .PunctPipe || op == .PunctCaret || op == .PunctTilde
    if lane.kind == .Bool { ret bitwise }
    if lane.kind != .Integer { ret false }
    ret bitwise || op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap || is_shift(op)
}

// `meta.array_len[X]()` written where a length is: the call's callee is the bracketed
// question and `X` is its one argument, read as a type. Anything else is not one.
fn array_len_subject(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, bool) {
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver { ret (invalid_type(), false) }
    let receiver = tree.nodes[receiver_index]
    if receiver.kind != .BracketPostfix { ret (invalid_type(), false) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count != 2usize { ret (invalid_type(), false) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (invalid_type(), false) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.meta") || !same(member, "array_len") { ret (invalid_type(), false) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (invalid_type(), false) }
    ret (subject, true)
}

// The length `meta.array_len` answers for a subject once it is concrete: an array's, or
// a vector's lane count. A parameter or a still-generic vector has none yet.
fn length_of_subject(c: *Checker, subject: Type) -> (usize, err) {
    if subject.kind == .TypeParameter || vector_pending(c, subject) { ret (0usize, MissingContext) }
    let (lanes, is_vector) = vector_lanes(c, subject)
    if is_vector { ret (lanes.array_length, ok) }
    if subject.kind != .Array || !subject.has_length { ret (0usize, InvalidType) }
    ret (subject.array_length, ok)
}

// Section 8: `Atomic[T]` is legal for exactly an integer type of section 4 or a
// pointer, every one of which is native at its width on the CPU.
fn atomic_element_legal(ty: Type) -> bool {
    if ty.kind == .Pointer || ty.kind == .Function { ret true }
    if ty.kind != .Integer { ret false }
    ret !same(ty.name, "f16") && !same(ty.name, "bf16")
}

fn collect_aggregate_pass(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, register: bool) -> err {
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try graph.parse_module(g, module_index, &tree)
        try tokenize_module(c, g, module_index)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .TypeDecl {
                if register {
                    try register_aggregate_declaration(c, r, g, &tree, module_index, node)
                } else {
                    try collect_aggregate_declaration(c, r, g, &tree, module_index, node)
                }
            }
            node_index += 1usize
        }
        module_index += 1usize
    }
    ret ok
}

// Spec section 14 invariant 7: module scope is order-independent. A field whose
// type instantiates a generic aggregate needs that aggregate's declaration, which
// may come later in the same file or in a module collected later, so every
// aggregate is registered before any field type is resolved.
fn collect_aggregates(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.aggregate_count = 0usize
    c.aggregate_field_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    try seed_intrinsic_aggregates(c, g)
    try collect_aggregate_pass(c, r, g, true)
    try collect_aggregate_pass(c, r, g, false)
    ret refill_aggregate_instances(c)
}

// An instance copies its template's fields when it is created, and a field type is
// what creates one -- so a struct whose field is `other.Thing[i64]` instantiates
// `Thing` while collecting its own fields, which is before `Thing`'s fields are
// collected whenever the other module is walked later. The instance is then born with
// none of them and stays that way, because nothing revisits it.
//
// Templates are never instances, so once the pass above has run every template is
// complete and one sweep settles it. An instance made here is made from a complete
// template and needs no second look, which is why the loop re-reads the count.
fn refill_aggregate_instances(c: *Checker) -> err {
    var at = 0usize
    while at < c.aggregate_count {
        let instance = c.aggregates[at]
        if instance.instance && !instance.generic && instance.template_index < c.aggregate_count {
            let template = c.aggregates[instance.template_index]
            if instance.field_count != template.field_count {
                if c.aggregate_field_count + template.field_count > c.aggregate_fields.len { ret Capacity }
                // Reserve before substituting: a nested instantiation appends fields of
                // its own, exactly as `instantiate_aggregate` guards against.
                let first_field = c.aggregate_field_count
                c.aggregate_field_count += template.field_count
                var field_at = 0usize
                while field_at < template.field_count {
                    let source = c.aggregate_fields[template.first_field + field_at]
                    let (specialized, specialize_error) = substitute_aggregate_type(c, instance.template_index, instance.first_argument, source.ty)
                    if specialize_error != ok { ret specialize_error }
                    c.aggregate_fields[first_field + field_at] = AggregateField { name: source.name, ty: specialized, enum_value: source.enum_value, enum_negative: source.enum_negative, has_enum_value: source.has_enum_value, token: source.token }
                    field_at += 1usize
                }
                c.aggregates[at].first_field = first_field
                c.aggregates[at].field_count = template.field_count
            }
        }
        at += 1usize
    }
    ret ok
}

// A field type is stored fully expanded -- every aggregate lookup and every type
// comparison relies on that. `collect_aggregates` cannot always manage it: an alias
// to a generic instantiation does not resolve in `collect_aliases`' first pass, which
// runs before any aggregate is registered, so a field naming one keeps the alias name.
// The second pass resolves those, and this walk expands what they were holding open.
fn expand_aggregate_field_types(c: *Checker) -> err {
    var at = 0usize
    while at < c.aggregate_field_count {
        let (resolved, resolve_error) = canonical_type(c, c.aggregate_fields[at].ty)
        if resolve_error != ok { ret resolve_error }
        c.aggregate_fields[at].ty = resolved
        at += 1usize
    }
    ret ok
}

fn type_has_value_cycle(c: *Checker, ty: Type, cycle_root: usize, depth: usize) -> (bool, err) {
    let (subject, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret (false, canonical_error) }
    if subject.kind == .Pointer || subject.kind == .Slice { ret (false, ok) }
    if subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret (false, InvalidType) }
        let (cyclic, cycle_error) = type_has_value_cycle(c, c.types[subject.element], cycle_root, depth)
        ret (cyclic, cycle_error)
    }
    if subject.kind != .Named { ret (false, ok) }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found { ret (false, ok) }
    if aggregate_index == cycle_root { ret (true, ok) }
    if depth >= c.aggregate_count { ret (true, ok) }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind == .Enum { ret (false, ok) }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret (false, InvalidType) }
        let (cyclic, cycle_error) = type_has_value_cycle(c, c.aggregate_fields[field_index].ty, cycle_root, depth + 1usize)
        if cycle_error != ok { ret (false, cycle_error) }
        if cyclic { ret (true, ok) }
        at += 1usize
    }
    ret (false, ok)
}

fn validate_aggregate_value_cycles(c: *Checker) -> err {
    ret validate_aggregate_value_cycles_from(c, 0usize)
}

fn validate_aggregate_value_cycles_from(c: *Checker, first: usize) -> err {
    var aggregate_index = first
    while aggregate_index < c.aggregate_count {
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .Enum {
            var at = 0usize
            while at < aggregate.field_count {
                let field_index = aggregate.first_field + at
                if field_index >= c.aggregate_field_count { ret InvalidType }
                let (cyclic, cycle_error) = type_has_value_cycle(c, c.aggregate_fields[field_index].ty, aggregate_index, 0usize)
                if cycle_error != ok { ret cycle_error }
                if cyclic {
                    record_failure_token(c, aggregate.module_index, aggregate.token, .RecursiveAggregate, aggregate.name, "")
                    ret InvalidType
                }
                at += 1usize
            }
        }
        aggregate_index += 1usize
    }
    ret ok
}

fn type_has_zero_value(c: *Checker, ty: Type, depth: usize) -> bool {
    let (subject, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if subject.kind == .Void || subject.kind == .Invalid || subject.kind == .Other { ret false }
    if subject.kind == .TypeParameter { ret true }
    if subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret false }
        ret type_has_zero_value(c, c.types[subject.element], depth)
    }
    if subject.kind != .Named { ret true }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind == .Enum {
        var member_at = 0usize
        while member_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + member_at]
            if field.has_enum_value && field.enum_value == 0usize && !field.enum_negative { ret true }
            member_at += 1usize
        }
        ret false
    }
    if depth >= c.aggregate_count { ret false }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field = c.aggregate_fields[aggregate.first_field + field_at]
        if field.ty.kind != .Void && !type_has_zero_value(c, field.ty, depth + 1usize) { ret false }
        field_at += 1usize
    }
    ret true
}

// Whether every byte pattern is a value of the type (D475, H03): `bool` admits two,
// an enum its members, a tagged union its tags, and a struct or array holding one
// admits no more -- so `undef` of such a type is a value the checked program could
// read as an `invalid` check, which release does not keep. The answer names the
// type that admits only its members, for the diagnostic.
fn type_has_undef_value(c: *Checker, ty: Type, depth: usize) -> (bool, str) {
    let (subject, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret (true, "") }
    if subject.kind == .Bool { ret (false, subject.name) }
    if subject.kind == .Array {
        if !subject.has_element || subject.element >= c.type_count { ret (true, "") }
        let (element_admits, element_culprit) = type_has_undef_value(c, c.types[subject.element], depth)
        ret (element_admits, element_culprit)
    }
    if subject.kind != .Named { ret (true, "") }
    let (aggregate_index, found) = aggregate_for_type(c, subject)
    if !found { ret (true, "") }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind == .Enum || aggregate.kind == .TaggedUnion { ret (false, subject.name) }
    if aggregate.kind != .Struct || depth >= c.aggregate_count { ret (true, "") }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field = c.aggregate_fields[aggregate.first_field + field_at]
        if field.ty.kind != .Void {
            let (field_admits, culprit) = type_has_undef_value(c, field.ty, depth + 1usize)
            if !field_admits { ret (false, culprit) }
        }
        field_at += 1usize
    }
    ret (true, "")
}

fn aggregate_parameter(c: *Checker, template_index: usize, name: str) -> (usize, bool) {
    if template_index >= c.aggregate_count { ret (0usize, false) }
    let template = c.aggregates[template_index]
    var at = 0usize
    while at < template.comptime_count {
        let parameter_index = template.first_comptime + at
        if parameter_index < c.comptime_parameter_count && same(c.comptime_parameters[parameter_index].name, name) { ret (parameter_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn aggregate_argument(c: *Checker, template_index: usize, first_argument: usize, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if template_index >= c.aggregate_count { ret (empty, false) }
    let template = c.aggregates[template_index]
    if parameter_index < template.first_comptime { ret (empty, false) }
    let offset = parameter_index - template.first_comptime
    if offset >= template.comptime_count { ret (empty, false) }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count || !c.generic_arguments[argument_index].set { ret (empty, false) }
    ret (c.generic_arguments[argument_index], true)
}

fn evaluate_aggregate_bound(c: *Checker, template_index: usize, first_argument: usize, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .ArrayLen {
        let (subject, subject_error) = substitute_aggregate_type(c, template_index, first_argument, expression.ty)
        if subject_error != ok { ret (normalized_integer(0usize, false), invalid_type(), subject_error) }
        let (length, length_error) = length_of_subject(c, subject)
        if length_error != ok { ret (normalized_integer(0usize, false), invalid_type(), length_error) }
        let (contextual_type, context_error) = apply_context(c, make_type(.Integer, "usize", expression.module_index), expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (normalized_integer(length, false), contextual_type, ok)
    }
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok || (contextual_type.kind == .Integer && !integer_representable(expression.value, contextual_type)) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (expression.value, contextual_type, ok)
    }
    if expression.kind == .Name {
        var parameter_index = 0usize
        var parameter_found = false
        if template_index < c.aggregate_count && expression.module_index == c.aggregates[template_index].module_index {
            (parameter_index, parameter_found) = aggregate_parameter(c, template_index, expression.name)
        }
        if parameter_found {
            let parameter = c.comptime_parameters[parameter_index]
            if parameter.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
            let (argument, argument_found) = aggregate_argument(c, template_index, first_argument, parameter_index)
            if !argument_found || argument.symbolic { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            let (contextual_type, context_error) = apply_context(c, parameter.ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (contextual_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok || !integer_representable(c.constants[constant_index].value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (c.constants[constant_index].value, contextual_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctTilde {
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (left, left_type, left_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_aggregate_bound(c, template_index, first_argument, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", expression.module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn aggregate_arguments_concrete(c: *Checker, template: Aggregate, first_argument: usize) -> bool {
    var at = 0usize
    while at < template.comptime_count {
        let argument = c.generic_arguments[first_argument + at]
        if !argument.set || argument.symbolic { ret false }
        if argument.kind == .Type && type_still_generic(c, argument.ty) { ret false }
        at += 1usize
    }
    ret true
}

// A type that still mentions a parameter: the parameter itself, an instance built over
// one (`Node[T]` in a template), or a pointer, slice or array of either. An aggregate
// instantiated over such a type is not concrete, whatever its argument's kind says --
// `List[Node[T]]` written in a struct and again in a function name two parameters, and
// only an instance that knows it is still generic can be told to match the other.
fn type_still_generic(c: *Checker, ty: Type) -> bool {
    if ty.kind == .TypeParameter { ret true }
    if ty.kind == .Named {
        if !ty.has_element || ty.element >= c.aggregate_count { ret false }
        ret c.aggregates[ty.element].instance && c.aggregates[ty.element].generic
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret false }
        ret type_still_generic(c, c.types[ty.element])
    }
    ret false
}

fn aggregate_arguments_equal(c: *Checker, template: Aggregate, first: usize, second: usize) -> bool {
    var at = 0usize
    while at < template.comptime_count {
        let left = c.generic_arguments[first + at]
        let right = c.generic_arguments[second + at]
        if !left.set || !right.set || left.kind != right.kind || left.symbolic || right.symbolic { ret false }
        if left.kind == .Type {
            if !type_equal(c, left.ty, right.ty) { ret false }
        } else {
            if left.symbolic != right.symbolic { ret false }
            if left.symbolic {
                if left.expression != right.expression { ret false }
            } else {
                if left.value != right.value { ret false }
            }
        }
        at += 1usize
    }
    ret true
}

fn find_aggregate_instance(c: *Checker, template_index: usize, first_argument: usize) -> (usize, bool) {
    if template_index >= c.aggregate_count { ret (0usize, false) }
    let template = c.aggregates[template_index]
    var at = template_index + 1usize
    while at < c.aggregate_count {
        let candidate = c.aggregates[at]
        if candidate.instance && !candidate.generic && candidate.template_index == template_index && aggregate_arguments_equal(c, template, candidate.first_argument, first_argument) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn substitute_aggregate_type(c: *Checker, template_index: usize, first_argument: usize, ty: Type) -> (Type, err) {
    if ty.kind == .TypeParameter {
        if !ty.has_element { ret (invalid_type(), InvalidType) }
        let (argument, found) = aggregate_argument(c, template_index, first_argument, ty.element)
        if !found || argument.symbolic { ret (invalid_type(), MissingContext) }
        // `FIELD.ty` as the type of a field, which is what a struct built around one comptime
        // field looks like. The same substitution a function's signature gets.
        if argument.kind == .Field { ret (argument.ty, ok) }
        if argument.kind != .Type { ret (invalid_type(), MissingContext) }
        ret (argument.ty, ok)
    }
    if ty.kind == .Named && ty.has_element {
        if ty.element >= c.aggregate_count || !c.aggregates[ty.element].instance { ret (invalid_type(), InvalidType) }
        let source = c.aggregates[ty.element]
        let nested_template = c.aggregates[source.template_index]
        if c.generic_argument_count + nested_template.comptime_count > c.generic_arguments.len { ret (invalid_type(), Capacity) }
        // The block is claimed whole before any argument is substituted: substituting one may
        // instantiate a nested generic -- `list.List[Node[T]]` -- whose own arguments would
        // otherwise land in the slots this instance is about to fill (D145's rule, again).
        let nested_first = c.generic_argument_count
        c.generic_argument_count += nested_template.comptime_count
        var at = 0usize
        while at < nested_template.comptime_count {
            let source_argument = c.generic_arguments[source.first_argument + at]
            var nested_argument = source_argument
            if source_argument.kind == .Type {
                let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source_argument.ty)
                if specialize_error != ok { ret (invalid_type(), specialize_error) }
                nested_argument.ty = specialized
            } else {
                if source_argument.symbolic {
                    let (value, value_type, value_error) = evaluate_aggregate_bound(c, template_index, first_argument, source_argument.expression, make_type(.Integer, "usize", nested_template.module_index))
                    if value_error != ok || value.negative || (value_type.kind != .UntypedInteger && (value_type.kind != .Integer || !same(value_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
                    nested_argument.value = value.magnitude
                    nested_argument.symbolic = false
                }
            }
            c.generic_arguments[nested_first + at] = nested_argument
            at += 1usize
        }
        let (nested_instance, instance_error) = instantiate_aggregate(c, source.template_index, nested_first)
        if instance_error != ok { ret (invalid_type(), instance_error) }
        var result = ty
        result.element = nested_instance
        ret (result, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = substitute_aggregate_type(c, template_index, first_argument, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = ty
        result.element = stored_element
        if ty.kind == .Array && !ty.has_length {
            let (length, length_type, length_error) = evaluate_aggregate_bound(c, template_index, first_argument, ty.array_length, make_type(.Integer, "usize", c.aggregates[template_index].module_index))
            if length_error != ok { ret (invalid_type(), length_error) }
            if length.negative || (length_type.kind != .UntypedInteger && (length_type.kind != .Integer || !same(length_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
            result.array_length = length.magnitude
            result.has_length = true
        }
        ret (result, ok)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = function_signature_of(c, ty)
        if !has_signature { ret (invalid_type(), InvalidType) }
        var parameters: [16]Type = zero
        var returns: [4]Type = zero
        if signature.parameter_count > parameters.len || signature.return_count > returns.len { ret (invalid_type(), Capacity) }
        var at = 0usize
        while at < signature.parameter_count {
            let (source, has_source) = function_signature_parameter(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            parameters[at] = specialized
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (source, has_source) = function_signature_return(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            returns[at] = specialized
            at += 1usize
        }
        let (result, build_error) = build_function_type(c, parameters[..signature.parameter_count], returns[..signature.return_count], ty.module_index)
        ret (result, build_error)
    }
    ret (ty, ok)
}

fn instantiate_aggregate(c: *Checker, template_index: usize, first_argument: usize) -> (usize, err) {
    if template_index >= c.aggregate_count { ret (0usize, InvalidType) }
    let template = c.aggregates[template_index]
    if !template.generic || template.instance { ret (0usize, InvalidType) }
    let concrete = aggregate_arguments_concrete(c, template, first_argument)
    if concrete {
        let (cached, found) = find_aggregate_instance(c, template_index, first_argument)
        if found { ret (cached, ok) }
    }
    if c.aggregate_count == c.aggregates.len { ret (0usize, Capacity) }
    var instance = template
    instance.first_field = c.aggregate_field_count
    instance.field_count = 0usize
    instance.template_index = template_index
    instance.first_argument = first_argument
    instance.generic = !concrete
    instance.instance = true
    // The template's memo describes unresolved type parameters. A concrete
    // instance must classify its substituted fields for itself (D611): Box[File]
    // is affine even when Box[T] was previously memoized as plain.
    instance.affine_memo = 0u8
    instance.pointer_memo = 0u8
    // The instance is registered before its fields are substituted, so that a field
    // naming the instance itself -- `left: *Node[K, V]` inside `Node[K, V]` -- finds it in
    // the cache instead of instantiating it again without end. Its fields are filled in
    // place below; a field read through the pointer meanwhile sees the count already set.
    let index = c.aggregate_count
    c.aggregate_count += 1usize
    if concrete {
        if c.aggregate_field_count + template.field_count > c.aggregate_fields.len { ret (0usize, Capacity) }
        c.aggregate_field_count += template.field_count
        instance.field_count = template.field_count
    }
    c.aggregates[index] = instance
    if concrete {
        var at = 0usize
        while at < template.field_count {
            let source = c.aggregate_fields[template.first_field + at]
            c.aggregate_fields[instance.first_field + at] = AggregateField { name: source.name, ty: invalid_type(), enum_value: source.enum_value, enum_negative: source.enum_negative, has_enum_value: source.has_enum_value, token: source.token }
            at += 1usize
        }
        at = 0usize
        while at < template.field_count {
            let source = c.aggregate_fields[template.first_field + at]
            let (specialized, specialize_error) = substitute_aggregate_type(c, template_index, first_argument, source.ty)
            if specialize_error != ok { ret (0usize, specialize_error) }
            c.aggregate_fields[instance.first_field + at].ty = specialized
            at += 1usize
        }
    }
    ret (index, ok)
}

fn collect_parameter(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.parameter_count == c.parameters.len { ret Capacity }
    let (name, has_name) = first_name(c, g.modules[module_index].text, node)
    if !has_name { ret Unsupported }
    let (type_index, has_type) = first_node_child(tree, node)
    if !has_type { ret Unsupported }
    let (ty, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
    if type_error != ok { ret type_error }
    if ty.kind == .Void { ret InvalidType }
    // `own` sits between the colon and the type's first token.
    var own = false
    var scan = usize(node.token_start)
    while scan < usize(tree.nodes[type_index].token_start) && scan < c.token_count {
        let token = c.tokens[scan]
        if token.kind == .Identifier && same(g.modules[module_index].text[token.start..token.end], "own") && scan > usize(node.token_start) { own = true }
        scan += 1usize
    }
    c.parameters[c.parameter_count] = Parameter { name: name, ty: ty, own: own }
    c.parameter_count += 1usize
    ret ok
}

fn collect_comptime_parameter(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.comptime_parameter_count == c.comptime_parameters.len { ret Capacity }
    let (name, has_name) = first_name(c, g.modules[module_index].text, node)
    if !has_name { ret parse.InvalidSyntax }
    var saw_colon = false
    var kind_found = false
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token_kind = c.tokens[at].kind
        if token_kind == .PunctColon {
            saw_colon = true
        } else {
            if saw_colon && token_kind != .Newline {
                if token_kind == .KwType {
                    kind_found = true
                }
                break
            }
        }
        at += 1usize
    }
    if kind_found {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Type, ty: invalid_type() }
        c.comptime_parameter_count += 1usize
        ret ok
    }
    let (type_index, has_type) = first_node_child(tree, node)
    if !has_type { ret Unsupported }
    let (ty, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[type_index])
    if type_error != ok { ret type_error }
    if ty.kind == .String {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Str, ty: ty }
        c.comptime_parameter_count += 1usize
        ret ok
    }
    // Section 9's two comptime-only types, recognised here by the name they resolve to and
    // turned into a parameter kind. Nothing else in the checker ever holds a `Type` for
    // either of them, which is what comptime-only means rather than something enforced
    // separately: there is no type for a struct field, a local or a pointee to be declared as.
    let (meta_module, has_meta_module) = graph.find_module(g, "e.meta")
    if has_meta_module && ty.kind == .Named && ty.module_index == meta_module {
        if same(ty.name, "Field") || same(ty.name, "Member") {
            // The type stored is a placeholder standing for whatever this parameter will be
            // bound to, which is what the body sees while the declaration itself is checked --
            // section 9 defers everything that depends on a comptime parameter to the
            // instantiation, so `FIELD.ty` has to be *a* type there without being a known one.
            var pending = make_type(.TypeParameter, name, module_index)
            pending.element = c.comptime_parameter_count
            pending.has_element = true
            var pending_kind: ComptimeKind = .Field
            if same(ty.name, "Member") { pending_kind = .Member }
            c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: pending_kind, ty: pending }
            c.comptime_parameter_count += 1usize
            ret ok
        }
    }
    if ty.kind == .Array && ty.has_element && ty.element < c.type_count && c.types[ty.element].kind == .Integer {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Array, ty: ty }
        c.comptime_parameter_count += 1usize
        ret ok
    }
    if ty.kind == .Function {
        c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Function, ty: ty }
        c.comptime_parameter_count += 1usize
        ret ok
    }
    if ty.kind != .Integer || !same(ty.name, "usize") { ret InvalidType }
    c.comptime_parameters[c.comptime_parameter_count] = ComptimeParameter { name: name, kind: .Integer, ty: ty }
    c.comptime_parameter_count += 1usize
    ret ok
}

// A comptime array argument: an array literal whose items are integer literals, each
// representable in the element type, exactly the declared count once that is known.
// What is bound is the literal's spelling and the array type it wrote.
fn bind_array_argument(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function_index: usize, first_argument: usize, parameter_index: usize, node_index: usize) -> err {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    // Forwarding another generic's comptime array by name.
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret TypeMismatch }
        let (outer_index, is_outer) = active_comptime_parameter(c, text[token.start..token.end])
        if !is_outer || c.comptime_parameters[outer_index].kind != .Array { ret TypeMismatch }
        let (outer, has_outer) = active_argument(c, outer_index)
        if !has_outer {
            if !c.generic_declaration { ret MissingContext }
            ret ok
        }
        ret bind_spelled_argument(c, function_index, first_argument, parameter_index, .Array, outer.ty, outer.text)
    }
    if node.kind != .AggregateLiteral { ret TypeMismatch }
    let (bound_array, literal_error) = check_expr(c, g, tree, module_index, node_index, invalid_type())
    if literal_error != ok { ret literal_error }
    if bound_array.kind != .Array || !bound_array.has_element || bound_array.element >= c.type_count { ret TypeMismatch }
    let element = c.types[bound_array.element]
    let declared = c.comptime_parameters[parameter_index].ty
    if !declared.has_element || declared.element >= c.type_count || !type_equal(c, element, c.types[declared.element]) { ret TypeMismatch }
    // The declared length may name an earlier argument (`[meta.array_len[V]()]u8`), bound by
    // now; the literal must have exactly that many items.
    var expected_length = declared
    if !declared.has_length {
        let (substituted, substitute_error) = substitute_type(c, function_index, first_argument, declared)
        if substitute_error == ok { expected_length = substituted }
    }
    if expected_length.has_length && expected_length.array_length != bound_array.array_length { ret TypeMismatch }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                let (expression, has_expression) = literal_item_expression(tree, item)
                if !has_expression { ret parse.InvalidSyntax }
                let (_, _, item_error) = evaluate_array_length_expr(c, g, tree, module_index, expression, element)
                if item_error != ok { ret InvalidConstant }
            }
        }
        at += 1usize
    }
    ret bind_spelled_argument(c, function_index, first_argument, parameter_index, .Array, bound_array, text[c.tokens[usize(node.token_start)].start..c.tokens[usize(node.token_end) - 1usize].end])
}

fn bind_spelled_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize, kind: ComptimeKind, ty: Type, spelling: str) -> err {
    if function_index >= c.signature_function_count { ret InvalidType }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret InvalidType }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret InvalidType }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count { ret Capacity }
    if c.generic_arguments[argument_index].set {
        if c.generic_arguments[argument_index].kind != kind { ret TypeMismatch }
        if !same(c.generic_arguments[argument_index].text, spelling) { ret TypeMismatch }
        ret ok
    }
    c.generic_arguments[argument_index].kind = kind
    c.generic_arguments[argument_index].ty = ty
    c.generic_arguments[argument_index].text = spelling
    c.generic_arguments[argument_index].set = true
    ret ok
}

// The items of a bound comptime array, decoded from its spelling: the integer literals
// between the braces, in order. `at` walks the spelling; each call gives the next item.
fn comptime_array_item(spelling: str, at: *usize) -> (usize, bool) {
    var index = *at
    // Skip to the first digit after the opening brace, or after the previous item.
    if index == 0usize {
        while index < spelling.len && spelling[index] != 123u8 { index += 1usize }
    }
    while index < spelling.len && (spelling[index] < 48u8 || spelling[index] > 57u8) {
        if spelling[index] == 125u8 { ret (0usize, false) }
        index += 1usize
    }
    if index >= spelling.len { ret (0usize, false) }
    var value = 0usize
    while index < spelling.len && spelling[index] >= 48u8 && spelling[index] <= 57u8 {
        value = value * 10usize + usize(spelling[index] - 48u8)
        index += 1usize
    }
    // A width suffix (`3u8`) is letters and digits; step past it.
    while index < spelling.len && spelling[index] != 44u8 && spelling[index] != 125u8 { index += 1usize }
    *at = index
    ret (value, true)
}

fn store_return_type(c: *Checker, ty: Type) -> err {
    if c.return_type_count == c.return_types.len { ret Capacity }
    c.return_types[c.return_type_count] = ty
    c.return_type_count += 1usize
    ret ok
}

// The string an attribute argument spells, without its quotes. Attribute arguments
// are parsed as expressions and never resolved as values, so this is the only place
// their text is read.
fn attribute_string(c: *Checker, text: str, at: usize) -> (str, bool) {
    if at >= c.token_count { ret ("", false) }
    let token = c.tokens[at]
    if token.kind != .String { ret ("", false) }
    let spelling = text[token.start..token.end]
    if spelling.len < 2usize || spelling[0usize] != 34u8 { ret ("", false) }
    ret (spelling[1usize..spelling.len - 1usize], true)
}

// `@import("kernel32", "Sleep")` sitting above the declaration it applies to. The
// parser makes each attribute a top-level node of its own, created before the
// declaration, so the run immediately before it is that declaration's.
fn declaration_import(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (str, str, bool) {
    let text = g.modules[module_index].text
    var at = node_index
    while at > 1usize {
        at = at - 1usize
        let node = tree.nodes[at]
        if !node.top_level { continue }
        if node.kind != .Attribute { ret ("", "", false) }
        var name = ""
        var arguments: [2]str = zero
        var argument_count = 0usize
        var token_at = usize(node.token_start)
        while token_at < usize(node.token_end) && token_at < c.token_count {
            let token = c.tokens[token_at]
            if token.kind == .Identifier && name.len == 0usize { name = text[token.start..token.end] }
            if token.kind == .String {
                let (value, has_value) = attribute_string(c, text, token_at)
                if has_value && argument_count < 2usize {
                    arguments[argument_count] = value
                    argument_count += 1usize
                }
            }
            token_at += 1usize
        }
        if same(name, "import") && argument_count == 2usize { ret (arguments[0usize], arguments[1usize], true) }
    }
    ret ("", "", false)
}

// The string parameters named by a declaration contract. The returned slice keeps
// their quoted source spelling, so a multi-input summary needs no side allocation.
// Malformed or repeated summaries fail before bodies.
fn declaration_parameter_attributes(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, attribute_name: str) -> (str, usize, bool, err) {
    let text = g.modules[module_index].text
    var first_start = 0usize
    var last_end = 0usize
    var result_count = 0usize
    var found = false
    var at = node_index
    while at > 1usize {
        at = at - 1usize
        let node = tree.nodes[at]
        if !node.top_level { continue }
        if node.kind != .Attribute { break }
        var name = ""
        var token_at = usize(node.token_start)
        while token_at < usize(node.token_end) && token_at < c.token_count {
            let token = c.tokens[token_at]
            if token.kind == .Identifier {
                name = text[token.start..token.end]
                break
            }
            token_at += 1usize
        }
        if !same(name, attribute_name) { continue }
        if found { ret ("", 0usize, false, InvalidType) }
        found = true
        let child_end = usize(node.first_child) + usize(node.child_count)
        var child_at = usize(node.first_child)
        while child_at < child_end {
            if parse.child_is_node_at(tree, child_at) {
                let argument = tree.nodes[parse.child_index_at(tree, child_at)]
                if argument.kind != .LiteralExpr { ret ("", 0usize, false, InvalidType) }
                let argument_token = usize(argument.token_start)
                let (value, has_value) = attribute_string(c, text, argument_token)
                if !has_value || value.len == 0usize { ret ("", 0usize, false, InvalidType) }
                let token = c.tokens[argument_token]
                if result_count == 0usize { first_start = token.start }
                last_end = token.end
                result_count += 1usize
            }
            child_at += 1usize
        }
    }
    if result_count == 0usize { ret ("", 0usize, found, ok) }
    ret (text[first_start..last_end], result_count, found, ok)
}

fn contract_name_at(names: str, wanted: usize) -> (str, bool) {
    var at = 0usize
    var index = 0usize
    while at < names.len {
        while at < names.len && names[at] != 34u8 { at += 1usize }
        if at == names.len { break }
        let start = at + 1usize
        at = start
        while at < names.len && names[at] != 34u8 { at += 1usize }
        if at == names.len { ret ("", false) }
        if index == wanted { ret (names[start..at], true) }
        index += 1usize
        at += 1usize
    }
    ret ("", false)
}

fn contract_name_count(names: str, name: str) -> usize {
    var count = 0usize
    var at = 0usize
    while true {
        let (candidate, found) = contract_name_at(names, at)
        if !found { break }
        if same(candidate, name) { count += 1usize }
        at += 1usize
    }
    ret count
}

// Whether the attribute run above a declaration names `name`.
fn declaration_has_attribute(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, name: str) -> bool {
    let text = g.modules[module_index].text
    // The tokens first (D352): what precedes the declaration is a `}`, a bare
    // `@name`, or something the node walk below settles; the walk crosses the
    // previous declaration's whole body, which is most of what a module is.
    var before = usize(tree.nodes[node_index].token_start)
    while before > 0usize && c.tokens[before - 1usize].kind == .Newline { before = before - 1usize }
    if before > 0usize && c.tokens[before - 1usize].kind == .PunctRBrace { ret false }
    if before > 1usize && c.tokens[before - 1usize].kind == .Identifier && c.tokens[before - 2usize].kind == .PunctAt {
        let named = c.tokens[before - 1usize]
        if same(text[named.start..named.end], name) { ret true }
    }
    var at = node_index
    while at > 1usize {
        at = at - 1usize
        let node = tree.nodes[at]
        if !node.top_level { continue }
        if node.kind != .Attribute { ret false }
        var token_at = usize(node.token_start)
        while token_at < usize(node.token_end) && token_at < c.token_count {
            let token = c.tokens[token_at]
            if token.kind == .Identifier {
                if same(text[token.start..token.end], name) { ret true }
                break
            }
            token_at += 1usize
        }
    }
    ret false
}

fn collect_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, node_index: usize) -> err {
    if c.function_count == c.functions.len { ret Capacity }
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    var item: Function = zero
    item.name = name
    item.module_index = module_index
    item.owner_module_index = module_index
    if usize(node.token_start) < usize(node.token_end) && usize(node.token_end) <= c.token_count {
        item.source_start = c.tokens[usize(node.token_start)].start
        item.source_end = c.tokens[usize(node.token_end) - 1usize].end
    }
    item.first_parameter = c.parameter_count
    item.first_return = c.return_type_count
    item.external = node.kind == .ExternDecl
    if item.external {
        let (library, symbol, has_import) = declaration_import(c, g, tree, module_index, node_index)
        if has_import {
            item.import_library = library
            item.import_symbol = symbol
        }
    }
    var generic: FunctionGeneric = zero
    generic.first_comptime = c.comptime_parameter_count
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .ComptimeParam {
                c.active_first_comptime = generic.first_comptime
                c.active_comptime_count = generic.comptime_count
                try collect_comptime_parameter(c, r, g, tree, module_index, child)
                generic.comptime_count += 1usize
                item.generic = true
            }
        }
        at += 1usize
    }
    c.active_first_comptime = generic.first_comptime
    c.active_comptime_count = generic.comptime_count
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .Parameter {
                if usize(child.token_start) < usize(child.token_end) && c.tokens[usize(child.token_start)].kind == .PunctEllipsis {
                    // Legal on an `extern` alone; anywhere else `...` is still refused.
                    if !item.external { ret Unsupported }
                    item.variadic = true
                } else {
                    if item.variadic { ret parse.InvalidSyntax }
                    try collect_parameter(c, r, g, tree, module_index, child)
                    item.parameter_count += 1usize
                }
            }
            if child.kind == .ReturnSpec {
                let return_end = usize(child.first_child) + usize(child.child_count)
                var return_at = usize(child.first_child)
                while return_at < return_end {
                    if parse.child_is_node_at(tree, return_at) {
                        let (return_type, type_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[parse.child_index_at(tree, return_at)])
                        if type_error != ok { ret type_error }
                        try store_return_type(c, return_type)
                        item.return_count += 1usize
                    }
                    return_at += 1usize
                }
            }
        }
        at += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    if item.return_count == 1usize && c.return_types[item.first_return].kind == .Void {
        item.return_count = 0usize
        c.return_type_count = c.return_type_count - 1usize
    }
    if item.external && item.return_count > 1usize { ret InvalidType }
    var return_index = 0usize
    while return_index < item.return_count {
        let return_type = c.return_types[item.first_return + return_index]
        if return_type.kind == .Void { ret InvalidType }
        if item.external && return_type.kind == .Err { ret InvalidType }
        if return_type.kind == .Err && return_index + 1usize != item.return_count { ret InvalidType }
        return_index += 1usize
    }
    let (borrow_names, borrow_count, has_borrow, borrow_error) = declaration_parameter_attributes(c, g, tree, module_index, node_index, "borrows")
    if borrow_error != ok || (has_borrow && borrow_count != 1usize) {
        record_failure(c, module_index, node, .BorrowContract, "", "")
        if borrow_error != ok { ret borrow_error }
        ret InvalidType
    }
    if has_borrow {
        let (borrow_name, has_borrow_name) = contract_name_at(borrow_names, 0usize)
        if !has_borrow_name {
            record_failure(c, module_index, node, .BorrowContract, "", "")
            ret InvalidType
        }
        var parameter_at = 0usize
        while parameter_at < item.parameter_count {
            let parameter = c.parameters[item.first_parameter + parameter_at]
            if same(parameter.name, borrow_name) {
                if item.external || declaration_has_attribute(c, g, tree, module_index, node_index, "unsafe") || parameter.own || !holds_pointer(c, parameter.ty, 0usize) {
                    record_failure(c, module_index, node, .BorrowContract, borrow_name, "")
                    ret InvalidType
                }
                item.import_library = borrow_name
                break
            }
            parameter_at += 1usize
        }
        var pointer_result = false
        return_index = 0usize
        while return_index < item.return_count {
            if holds_pointer(c, c.return_types[item.first_return + return_index], 0usize) { pointer_result = true }
            return_index += 1usize
        }
        if function_borrow_from(c, item) == 0usize || !pointer_result {
            record_failure(c, module_index, node, .BorrowContract, borrow_name, "")
            ret InvalidType
        }
    }
    let (noescape_names, noescape_count, has_noescape, noescape_error) = declaration_parameter_attributes(c, g, tree, module_index, node_index, "noescape")
    if noescape_error != ok || (has_noescape && noescape_count == 0usize) {
        record_failure(c, module_index, node, .NoEscapeContract, "", "")
        if noescape_error != ok { ret noescape_error }
        ret InvalidType
    }
    if has_noescape {
        var name_at = 0usize
        while name_at < noescape_count {
            let (noescape_name, has_noescape_name) = contract_name_at(noescape_names, name_at)
            if !has_noescape_name {
                record_failure(c, module_index, node, .NoEscapeContract, "", "")
                ret InvalidType
            }
            var valid = false
            var parameter_at = 0usize
            while parameter_at < item.parameter_count {
                let parameter = c.parameters[item.first_parameter + parameter_at]
                if same(parameter.name, noescape_name) {
                    valid = !item.external && !declaration_has_attribute(c, g, tree, module_index, node_index, "unsafe") && !parameter.own && holds_pointer(c, parameter.ty, 0usize) && contract_name_count(noescape_names, noescape_name) == 1usize
                    break
                }
                parameter_at += 1usize
            }
            if !valid {
                record_failure(c, module_index, node, .NoEscapeContract, noescape_name, "")
                ret InvalidType
            }
            name_at += 1usize
        }
        item.import_symbol = noescape_names
    }
    // Section 5's closed table of what crosses the C ABI: a parameter or return of an
    // extern naming a type without a C mapping is refused here, at the declaration.
    if item.external && !item.intrinsic {
        var index = 0usize
        while index < item.parameter_count {
            let parameter_type = c.parameters[item.first_parameter + index].ty
            if !type_crosses(c, parameter_type, 0usize) {
                record_failure(c, module_index, node, .ExternType, item.name, crossing_spelling(parameter_type))
                ret InvalidType
            }
            index += 1usize
        }
        if item.return_count == 1usize && !type_crosses(c, c.return_types[item.first_return], 0usize) {
            record_failure(c, module_index, node, .ExternType, item.name, crossing_spelling(c.return_types[item.first_return]))
            ret InvalidType
        }
    }
    c.functions[c.function_count] = item
    c.function_generics[c.function_count] = generic
    c.function_count += 1usize
    ret ok
}

fn seeded_composite_type(c: *Checker, kind: Kind, element: Type, is_const: bool, module_index: usize) -> (Type, err) {
    let (element_index, store_error) = store_type(c, element)
    if store_error != ok { ret (invalid_type(), store_error) }
    var result = make_type(kind, "", module_index)
    result.element = element_index
    result.has_element = true
    result.is_const = is_const
    ret (result, ok)
}

fn add_seeded_function(c: *Checker, module_index: usize, name: str, return_type: Type, fallible: bool) -> (usize, err) {
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    let index = c.function_count
    var return_count = 0usize
    let first_return = c.return_type_count
    if return_type.kind != .Void {
        let store_error = store_return_type(c, return_type)
        if store_error != ok { ret (0usize, store_error) }
        return_count = 1usize
    }
    if fallible {
        let store_error = store_return_type(c, make_type(.Err, "err", module_index))
        if store_error != ok { ret (0usize, store_error) }
        return_count += 1usize
    }
    var item: Function = zero
    item.name = name
    item.module_index = module_index
    item.owner_module_index = module_index
    item.first_parameter = c.parameter_count
    item.first_return = first_return
    item.return_count = return_count
    item.intrinsic = true
    c.functions[index] = item
    var generic: FunctionGeneric = zero
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

fn add_seeded_parameter(c: *Checker, function_index: usize, name: str, ty: Type) -> err {
    if function_index >= c.function_count || c.parameter_count == c.parameters.len { ret Capacity }
    c.parameters[c.parameter_count] = Parameter { name: name, ty: ty, own: false }
    c.parameter_count += 1usize
    c.functions[function_index].parameter_count += 1usize
    ret ok
}

fn seed_memory_signatures(c: *Checker, module_index: usize) -> err {
    let arena = make_type(.Named, "Arena", module_index)
    let stats = make_type(.Named, "Stats", module_index)
    let usize_type = make_type(.Integer, "usize", module_index)
    let (arena_pointer, pointer_error) = seeded_composite_type(c, .Pointer, arena, false, module_index)
    if pointer_error != ok { ret pointer_error }
    let (mark_index, mark_error) = add_seeded_function(c, module_index, "mark", usize_type, false)
    if mark_error != ok { ret mark_error }
    try add_seeded_parameter(c, mark_index, "a", arena_pointer)
    let (reset_index, reset_error) = add_seeded_function(c, module_index, "reset", make_type(.Void, "void", module_index), false)
    if reset_error != ok { ret reset_error }
    try add_seeded_parameter(c, reset_index, "a", arena_pointer)
    try add_seeded_parameter(c, reset_index, "m", usize_type)
    let (stats_index, stats_error) = add_seeded_function(c, module_index, "stats", stats, false)
    if stats_error != ok { ret stats_error }
    try add_seeded_parameter(c, stats_index, "a", arena_pointer)
    // `view` is the one arena operation the language cannot express in source: it
    // turns a base pointer and an offset into a slice, which nothing else does.
    let u8_type = make_type(.Integer, "u8", module_index)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, false, module_index)
    if bytes_error != ok { ret bytes_error }
    let (const_arena_pointer, const_pointer_error) = seeded_composite_type(c, .Pointer, arena, true, module_index)
    if const_pointer_error != ok { ret const_pointer_error }
    let (view_index, view_error) = add_seeded_function(c, module_index, "view", bytes, false)
    if view_error != ok { ret view_error }
    try add_seeded_parameter(c, view_index, "a", const_arena_pointer)
    try add_seeded_parameter(c, view_index, "start", usize_type)
    try add_seeded_parameter(c, view_index, "len", usize_type)
    ret ok
}

fn seed_os_signatures(c: *Checker, os_module: usize, mem_module: usize, has_memory: bool, atomic_module: usize, has_atomic: bool, linux_target: bool) -> err {
    let file = make_type(.Named, "File", os_module)
    let process = make_type(.Named, "Proc", os_module)
    let clock = make_type(.Named, "Clock", os_module)
    let entry = make_type(.Named, "DirEntry", os_module)
    let flags = make_type(.Named, "OpenFlags", os_module)
    let stdio = make_type(.Named, "Stdio", os_module)
    let u8_type = make_type(.Integer, "u8", os_module)
    let usize_type = make_type(.Integer, "usize", os_module)
    let i32_type = make_type(.Integer, "i32", os_module)
    let i64_type = make_type(.Integer, "i64", os_module)
    let string_type = make_type(.String, "str", os_module)
    let error_type = make_type(.Err, "err", os_module)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, false, os_module)
    if bytes_error != ok { ret bytes_error }
    let (entries, entries_error) = seeded_composite_type(c, .Slice, entry, false, os_module)
    if entries_error != ok { ret entries_error }
    let (strings, strings_error) = seeded_composite_type(c, .Slice, string_type, false, os_module)
    if strings_error != ok { ret strings_error }
    let (const_strings, const_strings_error) = seeded_composite_type(c, .Slice, string_type, true, os_module)
    if const_strings_error != ok { ret const_strings_error }
    let (byte_pointer, byte_pointer_error) = seeded_composite_type(c, .Pointer, u8_type, false, os_module)
    if byte_pointer_error != ok { ret byte_pointer_error }
    let (const_bytes, const_bytes_error) = seeded_composite_type(c, .Slice, u8_type, true, os_module)
    if const_bytes_error != ok { ret const_bytes_error }
    // `os.copy_bytes(dst: []u8, src: []const u8)` (D329): the shorter length's worth.
    let (copy_index, copy_error) = add_seeded_function(c, os_module, "copy_bytes", make_type(.Void, "void", os_module), false)
    if copy_error != ok { ret copy_error }
    try add_seeded_parameter(c, copy_index, "dst", bytes)
    try add_seeded_parameter(c, copy_index, "src", const_bytes)
    // `os.sha256_blocks(state: []usize, bytes: []const u8) -> usize` (D332): the whole
    // blocks compressed with the SHA extensions, or none when the CPU has none.
    let (usizes, usizes_error) = seeded_composite_type(c, .Slice, usize_type, false, os_module)
    if usizes_error != ok { ret usizes_error }
    let (sha_index, sha_error) = add_seeded_function(c, os_module, "sha256_blocks", usize_type, false)
    if sha_error != ok { ret sha_error }
    try add_seeded_parameter(c, sha_index, "state", usizes)
    try add_seeded_parameter(c, sha_index, "bytes", const_bytes)
    // `os.crc32c_bytes(crc: []usize, bytes: []const u8) -> usize` (D332): the bytes
    // folded with the CRC32 instruction, or none when the CPU has none.
    let (crc_index, crc_error) = add_seeded_function(c, os_module, "crc32c_bytes", usize_type, false)
    if crc_error != ok { ret crc_error }
    try add_seeded_parameter(c, crc_index, "crc", usizes)
    try add_seeded_parameter(c, crc_index, "bytes", const_bytes)

    // `os.touch(p: *const u8, n: usize)` (D428): the pages of a buffer a kernel call
    // will write, committed before the call.
    let (const_byte_pointer, const_byte_pointer_error) = seeded_composite_type(c, .Pointer, u8_type, true, os_module)
    if const_byte_pointer_error != ok { ret const_byte_pointer_error }
    let (touch_index, touch_error) = add_seeded_function(c, os_module, "touch", make_type(.Void, "void", os_module), false)
    if touch_error != ok { ret touch_error }
    try add_seeded_parameter(c, touch_index, "p", const_byte_pointer)
    try add_seeded_parameter(c, touch_index, "n", usize_type)

    let (read_index, read_error) = add_seeded_function(c, os_module, "read", usize_type, true)
    if read_error != ok { ret read_error }
    try add_seeded_parameter(c, read_index, "f", file)
    try add_seeded_parameter(c, read_index, "buf", bytes)
    let (write_index, write_error) = add_seeded_function(c, os_module, "write", usize_type, true)
    if write_error != ok { ret write_error }
    try add_seeded_parameter(c, write_index, "f", file)
    try add_seeded_parameter(c, write_index, "buf", string_type)
    let (close_index, close_error) = add_seeded_function(c, os_module, "close", error_type, false)
    if close_error != ok { ret close_error }
    try add_seeded_parameter(c, close_index, "f", file)
    let seek_whence = make_type(.Named, "SeekWhence", os_module)
    let (seek_index, seek_error) = add_seeded_function(c, os_module, "seek", make_type(.Integer, "u64", os_module), true)
    if seek_error != ok { ret seek_error }
    try add_seeded_parameter(c, seek_index, "f", file)
    try add_seeded_parameter(c, seek_index, "off", i64_type)
    try add_seeded_parameter(c, seek_index, "whence", seek_whence)
    // `thread_create` is generic and intercepted at the call; these two are ordinary.
    let thread = make_type(.Named, "Thread", os_module)
    let (thread_join_index, thread_join_error) = add_seeded_function(c, os_module, "thread_join", error_type, false)
    if thread_join_error != ok { ret thread_join_error }
    try add_seeded_parameter(c, thread_join_index, "t", thread)
    let (thread_detach_index, thread_detach_error) = add_seeded_function(c, os_module, "thread_detach", error_type, false)
    if thread_detach_error != ok { ret thread_detach_error }
    try add_seeded_parameter(c, thread_detach_index, "t", thread)
    let (stdout_index, stdout_error) = add_seeded_function(c, os_module, "stdout", file, false)
    if stdout_error != ok { ret stdout_error }
    let (stderr_index, stderr_error) = add_seeded_function(c, os_module, "stderr", file, false)
    if stderr_error != ok { ret stderr_error }
    let (wait_index, wait_error) = add_seeded_function(c, os_module, "wait", i32_type, true)
    if wait_error != ok { ret wait_error }
    try add_seeded_parameter(c, wait_index, "p", process)
    let (exit_index, exit_error) = add_seeded_function(c, os_module, "exit", make_type(.Void, "void", os_module), false)
    if exit_error != ok { ret exit_error }
    try add_seeded_parameter(c, exit_index, "code", i32_type)
    let (reserve_index, reserve_error) = add_seeded_function(c, os_module, "reserve", byte_pointer, true)
    if reserve_error != ok { ret reserve_error }
    try add_seeded_parameter(c, reserve_index, "n", usize_type)
    let (commit_index, commit_error) = add_seeded_function(c, os_module, "commit", error_type, false)
    if commit_error != ok { ret commit_error }
    try add_seeded_parameter(c, commit_index, "p", byte_pointer)
    try add_seeded_parameter(c, commit_index, "n", usize_type)
    let (clock_index, clock_error) = add_seeded_function(c, os_module, "clock", i64_type, true)
    if clock_error != ok { ret clock_error }
    try add_seeded_parameter(c, clock_index, "c", clock)

    // Section 5: the raw system call, six arguments always. Its result is the kernel's
    // own -- a negative errno on failure -- so it is an `isize` and not an `err`, and
    // turning one into the other is what the `e.os` wrappers over it are for. Seeded on
    // Linux alone, which is where the intrinsic exists.
    if linux_target {
        let isize_type = make_type(.Integer, "isize", os_module)
        let (syscall_index, syscall_error) = add_seeded_function(c, os_module, "syscall", isize_type, false)
        if syscall_error != ok { ret syscall_error }
        try add_seeded_parameter(c, syscall_index, "n", usize_type)
        try add_seeded_parameter(c, syscall_index, "a0", usize_type)
        try add_seeded_parameter(c, syscall_index, "a1", usize_type)
        try add_seeded_parameter(c, syscall_index, "a2", usize_type)
        try add_seeded_parameter(c, syscall_index, "a3", usize_type)
        try add_seeded_parameter(c, syscall_index, "a4", usize_type)
        try add_seeded_parameter(c, syscall_index, "a5", usize_type)
    }

    // Section 8's blocking primitives. Their pointer is an `Atomic[u32]`, so they are
    // seeded only where `e.atomic` is in the graph -- as the arena calls below are
    // seeded only with `e.mem`.
    if has_atomic {
        let u32_type = make_type(.Integer, "u32", os_module)
        let atomic_u32 = atomic_wrapper_type(c, u32_type, atomic_module)
        if atomic_u32.kind == .Invalid { ret InvalidType }
        let (atomic_pointer, atomic_pointer_error) = seeded_composite_type(c, .Pointer, atomic_u32, false, os_module)
        if atomic_pointer_error != ok { ret atomic_pointer_error }
        let (futex_index, futex_error) = add_seeded_function(c, os_module, "wait_u32", error_type, false)
        if futex_error != ok { ret futex_error }
        try add_seeded_parameter(c, futex_index, "p", atomic_pointer)
        try add_seeded_parameter(c, futex_index, "expected", u32_type)
        try add_seeded_parameter(c, futex_index, "timeout_ns", i64_type)
        let (wake_one_index, wake_one_error) = add_seeded_function(c, os_module, "wake_one_u32", make_type(.Void, "void", os_module), false)
        if wake_one_error != ok { ret wake_one_error }
        try add_seeded_parameter(c, wake_one_index, "p", atomic_pointer)
        let (wake_all_index, wake_all_error) = add_seeded_function(c, os_module, "wake_all_u32", make_type(.Void, "void", os_module), false)
        if wake_all_error != ok { ret wake_all_error }
        try add_seeded_parameter(c, wake_all_index, "p", atomic_pointer)
    }

    if has_memory {
        let arena = make_type(.Named, "Arena", mem_module)
        let (arena_pointer, arena_pointer_error) = seeded_composite_type(c, .Pointer, arena, false, os_module)
        if arena_pointer_error != ok { ret arena_pointer_error }
        let (open_index, open_error) = add_seeded_function(c, os_module, "open", file, true)
        if open_error != ok { ret open_error }
        try add_seeded_parameter(c, open_index, "a", arena_pointer)
        try add_seeded_parameter(c, open_index, "path", string_type)
        try add_seeded_parameter(c, open_index, "flags", flags)
        let (readdir_index, readdir_error) = add_seeded_function(c, os_module, "readdir", entries, true)
        if readdir_error != ok { ret readdir_error }
        try add_seeded_parameter(c, readdir_index, "a", arena_pointer)
        try add_seeded_parameter(c, readdir_index, "path", string_type)
        let (spawn_index, spawn_error) = add_seeded_function(c, os_module, "spawn", process, true)
        if spawn_error != ok { ret spawn_error }
        try add_seeded_parameter(c, spawn_index, "a", arena_pointer)
        try add_seeded_parameter(c, spawn_index, "argv", const_strings)
        try add_seeded_parameter(c, spawn_index, "stdio", stdio)
        let (args_index, args_error) = add_seeded_function(c, os_module, "args", strings, true)
        if args_error != ok { ret args_error }
        try add_seeded_parameter(c, args_index, "a", arena_pointer)
    }
    ret ok
}

// `push_err` is the one `e.str` declaration the library cannot write. Its answer is
// the merged error table, which is a property of the whole program rather than of any
// module, so the compiler supplies the function and `lower` generates its body.
fn seed_str_signatures(c: *Checker, str_module: usize) -> err {
    let builder_type = make_type(.Named, "Builder", str_module)
    let (builder_pointer, pointer_error) = seeded_composite_type(c, .Pointer, builder_type, false, str_module)
    if pointer_error != ok { ret pointer_error }
    let error_type = make_type(.Err, "err", str_module)
    let (push_err_index, push_err_error) = add_seeded_function(c, str_module, "push_err", error_type, false)
    if push_err_error != ok { ret push_err_error }
    try add_seeded_parameter(c, push_err_index, "b", builder_pointer)
    try add_seeded_parameter(c, push_err_index, "v", error_type)
    ret ok
}

fn seed_intrinsic_signatures(c: *Checker, g: *graph.Graph) -> err {
    let (mem_module, has_memory) = graph.find_module(g, "e.mem")
    if has_memory { try seed_memory_signatures(c, mem_module) }
    let (os_module, has_os) = graph.find_module(g, "e.os")
    let (atomic_module, has_atomic) = graph.find_module(g, "e.atomic")
    if has_os { try seed_os_signatures(c, os_module, mem_module, has_memory, atomic_module, has_atomic, same(g.os, "linux")) }
    let (str_module, has_str) = graph.find_module(g, "e.str")
    if has_str { try seed_str_signatures(c, str_module) }
    ret ok
}

// The compiler-origin declarations whose owning modules otherwise have a complete
// source surface. They have no source token range for `index-file` to quote, so this
// is the canonical template spelling beside the checker paths that implement them.
// The surface gate compares these strings with module-apis.md on both targets.
fn intrinsic_signature(module: str, name: str) -> str {
    if same(module, "e.atomic") {
        if same(name, "init") { ret "fn init[T: type](v: T) -> Atomic[T]" }
        if same(name, "load") { ret "fn load[T: type](p: *Atomic[T], o: Ordering) -> T" }
        if same(name, "store") { ret "fn store[T: type](p: *Atomic[T], v: T, o: Ordering)" }
        if same(name, "xchg") { ret "fn xchg[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "cas") { ret "fn cas[T: type](p: *Atomic[T], expected: T, desired: T, success: Ordering, failure: Ordering) -> (bool, T)" }
        if same(name, "add") { ret "fn add[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "sub") { ret "fn sub[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "and") { ret "fn and[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "or") { ret "fn or[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "xor") { ret "fn xor[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "min") { ret "fn min[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "max") { ret "fn max[T: type](p: *Atomic[T], v: T, o: Ordering) -> T" }
        if same(name, "fence") { ret "fn fence(o: Ordering)" }
    }
    if same(module, "e.io") && same(name, "printf") { ret "fn printf[FMT: str](args: ...) -> err" }
    if same(module, "e.str") {
        if same(name, "format") { ret "fn format[FMT: str](a: *mem.Arena, args: ...) -> (str, err)" }
        if same(name, "push_err") { ret "fn push_err(b: *Builder, v: err) -> err" }
    }
    ret ""
}

fn collect_signatures(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.signature_function_count = 0usize
    try seed_intrinsic_signatures(c, g)
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try graph.parse_module(g, module_index, &tree)
        try tokenize_module(c, g, module_index)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && (node.kind == .FnDecl || node.kind == .ExternDecl) {
                try collect_function(c, r, g, &tree, module_index, node, node_index)
            }
            node_index += 1usize
        }
        module_index += 1usize
    }
    c.signature_function_count = c.function_count
    ret ok
}

// The type as the report names it: its name, or its shape when it has none.
fn crossing_spelling(ty: Type) -> str {
    if ty.name.len > 0usize { ret ty.name }
    if ty.kind == .Slice { ret "a slice" }
    if ty.kind == .Array { ret "an array by value" }
    if ty.kind == .Pointer { ret "a pointer to a type that does not cross" }
    if ty.kind == .String { ret "str" }
    if ty.kind == .Err { ret "err" }
    ret "a type without a C mapping"
}

// Whether a type is one row of section 5's table with "yes" in its Crosses column:
// the integers, `f32`/`f64`, `bool`, a pointer to something that crosses or to
// `void`, `Vec`/`Mask` or `Atomic`, a function pointer, an enum by its backing
// integer, and a non-empty struct or union whose every field crosses or is a
// non-empty array of a crossing type. Slices, `str`, `err`, arrays by value, tagged
// unions, `f16`/`bf16` and the two pointee-only builtins by value do not.
//
// ponytail: `fn(...)` and `extern fn(...)` are one `Function` kind to the checker,
// so a neper-convention function pointer passes here; telling them apart is the
// type's, not this table's.
fn type_crosses(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if canonical.kind == .Integer || canonical.kind == .Bool || canonical.kind == .Function { ret true }
    if canonical.kind == .Float { ret same(canonical.name, "f32") || same(canonical.name, "f64") }
    if canonical.kind == .Pointer {
        if !canonical.has_element || canonical.element >= c.type_count { ret false }
        let pointee = c.types[canonical.element]
        if pointee.kind == .Void { ret true }
        let (pointee_canonical, pointee_error) = canonical_type(c, pointee)
        if pointee_error != ok { ret false }
        if is_vector_type(c, pointee_canonical) { ret true }
        if pointee_canonical.kind == .Named && same(pointee_canonical.name, "Atomic") { ret true }
        ret type_crosses(c, pointee, depth + 1usize)
    }
    if canonical.kind != .Named && canonical.kind != .Tag { ret false }
    if is_enum_type(c, canonical) { ret true }
    if is_vector_type(c, canonical) || same(canonical.name, "Atomic") { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, canonical)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .Struct && aggregate.kind != .Union { ret false }
    if aggregate.field_count == 0usize || (aggregate.generic && !aggregate.instance) { ret false }
    var field_at = aggregate.first_field
    let field_end = aggregate.first_field + aggregate.field_count
    while field_at < field_end {
        let field_type = c.aggregate_fields[field_at].ty
        let (field_canonical, field_error) = canonical_type(c, field_type)
        if field_error != ok { ret false }
        if field_canonical.kind == .Array {
            if !field_canonical.has_length || field_canonical.array_length == 0usize || !field_canonical.has_element || field_canonical.element >= c.type_count { ret false }
            if !type_crosses(c, c.types[field_canonical.element], depth + 1usize) { ret false }
        } else {
            if !type_crosses(c, field_type, depth + 1usize) { ret false }
        }
        field_at += 1usize
    }
    ret true
}

// The rows added since the index was last filled, into it (D326): a declaration's
// row only. An instance shares its template's key, and the first row wins, so it was
// never found by name; leaving it out is what lets a body worker's checker, whose
// instances live in a tail of its own, share the index without writing to it.
fn fill_indexes(c: *Checker) {
    if !lookup.attached(&c.names) { ret }
    while c.names.indexed[1usize] < c.function_count {
        let row = c.names.indexed[1usize]
        if !c.function_generics[row].instance {
            let insert_error = lookup.insert(&c.names, c.functions[row].module_index, 1usize, c.functions[row].name, row)
            if insert_error != ok { ret }
        }
        c.names.indexed[1usize] = row + 1usize
    }
    while c.names.indexed[2usize] < c.aggregate_count {
        let row = c.names.indexed[2usize]
        if !c.aggregates[row].instance {
            let insert_error = lookup.insert(&c.names, c.aggregates[row].module_index, 2usize, c.aggregates[row].name, row)
            if insert_error != ok { ret }
        }
        c.names.indexed[2usize] = row + 1usize
    }
    while c.names.indexed[3usize] < c.alias_count {
        let row = c.names.indexed[3usize]
        let insert_error = lookup.insert(&c.names, c.aliases[row].module_index, 3usize, c.aliases[row].name, row)
        if insert_error != ok { ret }
        c.names.indexed[3usize] = row + 1usize
    }
    while c.names.indexed[4usize] < c.constant_count {
        let row = c.names.indexed[4usize]
        let insert_error = lookup.insert(&c.names, c.constants[row].module_index, 4usize, c.constants[row].name, row)
        if insert_error != ok { ret }
        c.names.indexed[4usize] = row + 1usize
    }
    while c.names.indexed[5usize] < c.global_count {
        let row = c.names.indexed[5usize]
        let insert_error = lookup.insert(&c.names, c.globals[row].module_index, 5usize, c.globals[row].name, row)
        if insert_error != ok { ret }
        c.names.indexed[5usize] = row + 1usize
    }
}

fn find_function(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    if lookup.attached(&c.names) {
        fill_indexes(c)
        if c.names.indexed[1usize] == c.function_count {
            let (found_at, found) = lookup.find(&c.names, module_index, 1usize, name)
            ret (found_at, found)
        }
    }
    var i = 0usize
    while i < c.function_count {
        if c.functions[i].module_index == module_index && same(c.functions[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// A module-scope `var`'s starting bits. Section 5 says zero without an initialiser, and the
// initialiser is compile-time, so it is the same interpreter a `const` goes through.
//
// ponytail: a scalar initialiser only. A struct or array one is `Unsupported` rather than
// silently zero -- what it would take is serialising an aggregate's bytes into the image, which
// is worth doing when something wants it.
fn global_initial_bits(c: *Checker, global_index: usize) -> (usize, err) {
    if global_index >= c.global_count { ret (0usize, InvalidConstant) }
    let item = c.globals[global_index]
    if !item.has_expression { ret (0usize, ok) }
    // The interpreter this goes through evaluates integers, so an integer initialiser is what is
    // carried. Anything else -- a `bool`, a struct, an array -- is `Unsupported` rather than
    // quietly zero, and the spelling that works for all of them is to leave the initialiser off:
    // section 5 zero-initialises then, which is what `false` and an empty aggregate already are.
    if item.ty.kind != .Integer {
        record_failure(c, item.module_index, zero, .NotAType, item.name, "")
        ret (0usize, Unsupported)
    }
    let (value, value_type, value_error) = evaluate_constant_expr(c, item.expression, item.ty)
    if value_error != ok { ret (0usize, value_error) }
    let width = integer_width(item.ty)
    if width == 0usize { ret (0usize, InvalidType) }
    ret (integer_bits(value, width), ok)
}

fn find_global(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    if lookup.attached(&c.names) {
        fill_indexes(c)
        if c.names.indexed[5usize] == c.global_count {
            let (found_at, found) = lookup.find(&c.names, module_index, 5usize, name)
            ret (found_at, found)
        }
    }
    var at = 0usize
    while at < c.global_count {
        if c.globals[at].module_index == module_index && same(c.globals[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn find_constant(c: *Checker, module_index: usize, name: str) -> (usize, bool) {
    if lookup.attached(&c.names) {
        fill_indexes(c)
        if c.names.indexed[4usize] == c.constant_count {
            let (found_at, found) = lookup.find(&c.names, module_index, 4usize, name)
            ret (found_at, found)
        }
    }
    var at = 0usize
    while at < c.constant_count {
        if c.constants[at].module_index == module_index && same(c.constants[at].name, name) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn imported_module(g: *graph.Graph, module_index: usize, qualifier: str) -> (usize, bool) {
    let end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var at = g.modules[module_index].first_import
    while at < end {
        if same(g.imports[at].qualifier, qualifier) { ret (g.imports[at].target, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn qualified_member(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (usize, str, bool) {
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret (0usize, "", false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (0usize, "", false) }
    let base_token = c.tokens[usize(base_node.token_start)]
    if base_token.kind != .Identifier { ret (0usize, "", false) }
    let text = g.modules[module_index].text
    let qualifier = text[base_token.start..base_token.end]
    let (target_module, imported) = imported_module(g, module_index, qualifier)
    if !imported { ret (0usize, "", false) }
    var member = ""
    var at = usize(base_node.token_end)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if member.len == 0usize { ret (0usize, "", false) }
    ret (target_module, member, true)
}

fn static_enum_member(c: *Checker, g: *graph.Graph, module_index: usize, node: syntax.Node) -> (Type, bool, bool) {
    var identifiers: [4]str = zero
    var count = 0usize
    let text = g.modules[module_index].text
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier {
            if count == 4usize { ret (invalid_type(), false, false) }
            identifiers[count] = text[token.start..token.end]
            count += 1usize
        }
        at += 1usize
    }
    var target_module = module_index
    var type_name = ""
    var member_name = ""
    var tag_member = false
    if count == 2usize {
        type_name = identifiers[0usize]
        member_name = identifiers[1usize]
    } else {
        if count == 3usize {
            let (imported, found_import) = imported_module(g, module_index, identifiers[0usize])
            if found_import {
                target_module = imported
                type_name = identifiers[1usize]
                member_name = identifiers[2usize]
            } else {
                if !same(identifiers[1usize], "Tag") { ret (invalid_type(), false, false) }
                type_name = identifiers[0usize]
                member_name = identifiers[2usize]
                tag_member = true
            }
        } else {
            if count != 4usize || !same(identifiers[2usize], "Tag") { ret (invalid_type(), false, false) }
            let (imported, found_import) = imported_module(g, module_index, identifiers[0usize])
            if !found_import { ret (invalid_type(), false, false) }
            target_module = imported
            type_name = identifiers[1usize]
            member_name = identifiers[3usize]
            tag_member = true
        }
    }
    let (_, found_type) = resolve.find(c.resolver, target_module, type_name, .Type)
    if !found_type { ret (invalid_type(), false, false) }
    let named = make_type(.Named, type_name, target_module)
    let (canonical, canonical_error) = canonical_type(c, named)
    if canonical_error != ok { ret (invalid_type(), false, false) }
    let (aggregate_index, found_aggregate) = aggregate_for_type(c, canonical)
    if !found_aggregate { ret (invalid_type(), false, false) }
    if tag_member {
        if c.aggregates[aggregate_index].kind != .TaggedUnion { ret (invalid_type(), false, false) }
    } else {
        if c.aggregates[aggregate_index].kind != .Enum { ret (invalid_type(), false, false) }
    }
    let (_, found_member) = aggregate_field_for_name(c, c.aggregates[aggregate_index], member_name)
    if !found_member { ret (invalid_type(), false, true) }
    if !tag_member { ret (canonical, true, true) }
    let (tag, found_tag) = tagged_union_tag_type(c, canonical)
    if !found_tag { ret (invalid_type(), false, false) }
    ret (tag, true, true)
}

fn find_qualified_function(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (usize, bool) {
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
    if !found_member { ret (0usize, false) }
    let (function_index, found) = find_function(c, target_module, member)
    ret (function_index, found)
}

fn store_constant_expr(c: *Checker, item: ConstantExpr) -> (usize, err) {
    if c.constant_expr_count == c.constant_exprs.len { ret (0usize, Capacity) }
    c.constant_exprs[c.constant_expr_count] = item
    let index = c.constant_expr_count
    c.constant_expr_count += 1usize
    ret (index, ok)
}

fn normalized_integer(magnitude: usize, negative: bool) -> IntegerValue {
    if magnitude == 0usize { ret IntegerValue { magnitude: 0usize, negative: false } }
    ret IntegerValue { magnitude: magnitude, negative: negative }
}

fn copy_constant_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    var item: ConstantExpr = zero
    if node.kind == .CallExpr {
        let (subject, is_array_len) = array_len_subject(c, g, tree, module_index, node)
        if is_array_len {
            item.kind = .ArrayLen
            item.module_index = module_index
            item.ty = subject
            let (stored_index, store_error) = store_constant_expr(c, item)
            ret (stored_index, store_error)
        }
        // A call, for the interpreter (D218): the callee by name, the arguments copied
        // first and then listed in a run of wrappers so the call finds them in order.
        var callee_index = 0usize
        var arguments: [16]usize = zero
        var argument_count = 0usize
        var first = true
        let call_end = usize(node.first_child) + usize(node.child_count)
        var call_at = usize(node.first_child)
        while call_at < call_end {
            if parse.child_is_node_at(tree, call_at) {
                if first {
                    callee_index = parse.child_index_at(tree, call_at)
                    first = false
                } else {
                    if argument_count == arguments.len { ret (0usize, InvalidConstant) }
                    let (copied, copy_error) = copy_constant_expr(c, g, tree, module_index, parse.child_index_at(tree, call_at))
                    if copy_error != ok { ret (0usize, copy_error) }
                    arguments[argument_count] = copied
                    argument_count += 1usize
                }
            }
            call_at += 1usize
        }
        if first { ret (0usize, InvalidConstant) }
        let callee = tree.nodes[callee_index]
        item.kind = .Call
        item.module_index = module_index
        item.site = node
        item.site_module = module_index
        if usize(node.token_start) < c.token_count { item.site_offset = c.tokens[usize(node.token_start)].start }
        if callee.kind == .NameExpr {
            let callee_token = c.tokens[usize(callee.token_start)]
            if callee_token.kind != .Identifier { ret (0usize, InvalidConstant) }
            item.name = text[callee_token.start..callee_token.end]
        } else {
            if callee.kind != .FieldExpr { ret (0usize, InvalidConstant) }
            let (target_module, member, found) = qualified_member(c, g, tree, module_index, callee)
            if !found { ret (0usize, InvalidConstant) }
            item.module_index = target_module
            item.name = member
        }
        item.first_argument = c.constant_expr_count
        item.argument_count = argument_count
        var wrap_at = 0usize
        while wrap_at < argument_count {
            var wrapper: ConstantExpr = zero
            wrapper.kind = .Argument
            wrapper.left = arguments[wrap_at]
            let (wrapped_index, wrap_error) = store_constant_expr(c, wrapper)
            if wrap_error != ok { ret (0usize, wrap_error) }
            wrap_at += 1usize
        }
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .LiteralExpr {
        let literal_token = c.tokens[usize(node.token_start)]
        if literal_token.kind == .KwTrue || literal_token.kind == .KwFalse {
            item.kind = .Literal
            var truth = 0usize
            if literal_token.kind == .KwTrue { truth = 1usize }
            item.value = normalized_integer(truth, false)
            item.ty = make_type(.Bool, "bool", module_index)
            let (stored_index, store_error) = store_constant_expr(c, item)
            ret (stored_index, store_error)
        }
        let (magnitude, parsed_type, literal_error) = integer_literal_value(c, text, node)
        if literal_error != ok { ret (0usize, literal_error) }
        item.kind = .Literal
        item.value = normalized_integer(magnitude, false)
        item.ty = parsed_type
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (0usize, InvalidConstant) }
        item.kind = .Name
        item.module_index = module_index
        item.name = text[token.start..token.end]
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .FieldExpr {
        let (target_module, member, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (0usize, InvalidConstant) }
        item.kind = .Name
        item.module_index = target_module
        item.name = member
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (copied_index, copy_error) = copy_constant_expr(c, g, tree, module_index, child_index)
        ret (copied_index, copy_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (0usize, parse.InvalidSyntax) }
        let (copied_index, copy_error) = copy_constant_expr(c, g, tree, module_index, child_index)
        if copy_error != ok { ret (0usize, copy_error) }
        item.kind = .Unary
        item.op = c.tokens[usize(node.token_start)].kind
        item.left = copied_index
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == 2usize { ret (0usize, parse.InvalidSyntax) }
                children[count] = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (0usize, parse.InvalidSyntax) }
        let (left_index, left_error) = copy_constant_expr(c, g, tree, module_index, children[0usize])
        if left_error != ok { ret (0usize, left_error) }
        let (right_index, right_error) = copy_constant_expr(c, g, tree, module_index, children[1usize])
        if right_error != ok { ret (0usize, right_error) }
        item.kind = .Binary
        item.op = binary_operator(c, tree, node)
        item.left = left_index
        item.right = right_index
        item.has_right = true
        let (stored_index, store_error) = store_constant_expr(c, item)
        ret (stored_index, store_error)
    }
    ret (0usize, Unsupported)
}

fn collect_constant_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.constant_count == c.constants.len { ret Capacity }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    var declared_type = invalid_type()
    var expression_index = 0usize
    var has_expression = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if is_type_node(child.kind) {
                let (resolved_type, type_error) = type_from_node(c, r, g, tree, module_index, child)
                if type_error != ok { ret type_error }
                declared_type = resolved_type
            } else {
                expression_index = child_index
                has_expression = true
            }
        }
        at += 1usize
    }
    if !has_expression { ret parse.InvalidSyntax }
    let (copied_expression, expression_error) = copy_constant_expr(c, g, tree, module_index, expression_index)
    if expression_error != ok { ret expression_error }
    c.constants[c.constant_count] = Constant { name: name, module_index: module_index, ty: declared_type, expression: copied_expression, value: normalized_integer(0usize, false), state: 0u8, token: c.tokens[usize(node.token_start)] }
    c.constant_count += 1usize
    ret ok
}

fn add_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if left.negative == right.negative {
        let max_value = 18446744073709551615usize
        if left.magnitude > max_value - right.magnitude { ret (normalized_integer(0usize, false), ConstantOverflow) }
        ret (normalized_integer(left.magnitude + right.magnitude, left.negative), ok)
    }
    if left.magnitude >= right.magnitude { ret (normalized_integer(left.magnitude - right.magnitude, left.negative), ok) }
    ret (normalized_integer(right.magnitude - left.magnitude, right.negative), ok)
}

fn subtract_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    let negated = normalized_integer(right.magnitude, !right.negative)
    let (result, result_error) = add_integer_values(left, negated)
    ret (result, result_error)
}

fn multiply_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    let max_value = 18446744073709551615usize
    if right.magnitude != 0usize && left.magnitude > max_value / right.magnitude { ret (normalized_integer(0usize, false), ConstantOverflow) }
    ret (normalized_integer(left.magnitude * right.magnitude, left.negative != right.negative), ok)
}

fn divide_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if right.magnitude == 0usize { ret (normalized_integer(0usize, false), InvalidConstant) }
    ret (normalized_integer(left.magnitude / right.magnitude, left.negative != right.negative), ok)
}

fn remainder_integer_values(left: IntegerValue, right: IntegerValue) -> (IntegerValue, err) {
    if right.magnitude == 0usize { ret (normalized_integer(0usize, false), InvalidConstant) }
    ret (normalized_integer(left.magnitude % right.magnitude, left.negative), ok)
}

fn constant_result_type(c: *Checker, left: Type, right: Type) -> (Type, err) {
    if !is_integer(left) || !is_integer(right) { ret (invalid_type(), InvalidConstant) }
    if is_untyped(left) {
        if is_untyped(right) { ret (left, ok) }
        ret (right, ok)
    }
    if is_untyped(right) { ret (left, ok) }
    if !type_equal(c, left, right) { ret (invalid_type(), mismatch(c, left, right)) }
    ret (left, ok)
}

fn integer_representable(value: IntegerValue, ty: Type) -> bool {
    if ty.kind != .Integer { ret false }
    if same(ty.name, "u8") { ret !value.negative && value.magnitude <= 255usize }
    if same(ty.name, "u16") { ret !value.negative && value.magnitude <= 65535usize }
    if same(ty.name, "u32") { ret !value.negative && value.magnitude <= 4294967295usize }
    if same(ty.name, "u64") || same(ty.name, "usize") { ret !value.negative }
    if same(ty.name, "i8") {
        if value.negative { ret value.magnitude <= 128usize }
        ret value.magnitude <= 127usize
    }
    if same(ty.name, "i16") {
        if value.negative { ret value.magnitude <= 32768usize }
        ret value.magnitude <= 32767usize
    }
    if same(ty.name, "i32") {
        if value.negative { ret value.magnitude <= 2147483648usize }
        ret value.magnitude <= 2147483647usize
    }
    if same(ty.name, "i64") || same(ty.name, "isize") {
        if value.negative { ret value.magnitude <= 9223372036854775808usize }
        ret value.magnitude <= 9223372036854775807usize
    }
    ret false
}

fn unsigned_integer_type(ty: Type) -> bool {
    if ty.kind != .Integer { ret false }
    ret same(ty.name, "u8") || same(ty.name, "u16") || same(ty.name, "u32") || same(ty.name, "u64") || same(ty.name, "usize")
}

// By the name's shape (D326): `i8`/`u8`, `i16`/`u16`, `i32`/`u32`, and the rest --
// `i64`, `u64`, `isize`, `usize` -- are 64. Codegen asks per instruction.
fn integer_width(ty: Type) -> usize {
    if ty.kind != .Integer { ret 0usize }
    if ty.name.len == 2usize { ret 8usize }
    if ty.name.len == 3usize {
        if ty.name[1usize] == 49u8 { ret 16usize }
        if ty.name[1usize] == 51u8 { ret 32usize }
    }
    ret 64usize
}

fn integer_mask(width: usize) -> usize {
    var result = 0usize
    var at = 0usize
    while at < width {
        result = result * 2usize + 1usize
        at += 1usize
    }
    ret result
}

fn integer_sign_bit(width: usize) -> usize {
    var result = 1usize
    var at = 1usize
    while at < width {
        result = result * 2usize
        at += 1usize
    }
    ret result
}

fn integer_bits(value: IntegerValue, width: usize) -> usize {
    let mask = integer_mask(width)
    if !value.negative { ret value.magnitude }
    if value.magnitude == 0usize { ret 0usize }
    ret mask - (value.magnitude - 1usize)
}

fn integer_from_bits(bits: usize, ty: Type) -> IntegerValue {
    let width = integer_width(ty)
    let mask = integer_mask(width)
    let value = bits
    if unsigned_integer_type(ty) { ret normalized_integer(value, false) }
    let sign = integer_sign_bit(width)
    if value < sign { ret normalized_integer(value, false) }
    ret normalized_integer((mask - value) + 1usize, true)
}

fn bitwise_integer_bits(op: lex.Kind, left: usize, right: usize, width: usize) -> usize {
    var left_rest = left
    var right_rest = right
    var place = 1usize
    var result = 0usize
    var at = 0usize
    while at < width {
        let left_set = left_rest % 2usize != 0usize
        let right_set = right_rest % 2usize != 0usize
        var selected = left_set && right_set
        if op == .PunctPipe { selected = left_set || right_set }
        if op == .PunctCaret { selected = left_set != right_set }
        if selected { result += place }
        left_rest = left_rest / 2usize
        right_rest = right_rest / 2usize
        at += 1usize
        if at < width { place = place * 2usize }
    }
    ret result
}

fn modular_add(left: usize, right: usize, mask: usize) -> usize {
    if left <= mask - right { ret left + right }
    ret left - (mask - right) - 1usize
}

fn modular_subtract(left: usize, right: usize, mask: usize) -> usize {
    if left >= right { ret left - right }
    ret mask - (right - left) + 1usize
}

fn modular_multiply(left: usize, right: usize, mask: usize) -> usize {
    var result = 0usize
    var addend = left
    var multiplier = right
    while multiplier != 0usize {
        if multiplier % 2usize != 0usize { result = modular_add(result, addend, mask) }
        multiplier = multiplier / 2usize
        if multiplier != 0usize { addend = modular_add(addend, addend, mask) }
    }
    ret result
}

fn shift_left_bits(value: usize, count: usize, mask: usize) -> usize {
    var result = value
    var at = 0usize
    while at < count {
        result = modular_add(result, result, mask)
        at += 1usize
    }
    ret result
}

fn shift_right_bits(value: usize, count: usize) -> usize {
    var result = value
    var at = 0usize
    while at < count {
        result = result / 2usize
        at += 1usize
    }
    ret result
}

fn shift_right_signed(value: IntegerValue, count: usize) -> IntegerValue {
    var magnitude = value.magnitude
    var at = 0usize
    while at < count {
        magnitude = magnitude / 2usize + magnitude % 2usize
        at += 1usize
    }
    ret normalized_integer(magnitude, true)
}

fn evaluate_integer_binary(op: lex.Kind, left: IntegerValue, right: IntegerValue, left_type: Type, right_type: Type) -> (IntegerValue, err) {
    if is_shift(op) {
        if left_type.kind != .Integer || right_type.kind != .Integer || !unsigned_integer_type(right_type) || right.negative { ret (normalized_integer(0usize, false), InvalidOperator) }
        let width = integer_width(left_type)
        if right.magnitude >= width { ret (normalized_integer(0usize, false), InvalidConstant) }
        if op == .PunctShiftRight && !unsigned_integer_type(left_type) && left.negative {
            if right.magnitude == 0usize { ret (left, ok) }
            ret (shift_right_signed(left, right.magnitude), ok)
        }
        let left_bits = integer_bits(left, width)
        var result_bits = shift_left_bits(left_bits, right.magnitude, integer_mask(width))
        if op == .PunctShiftRight { result_bits = shift_right_bits(left_bits, right.magnitude) }
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if left_type.kind != .Integer { ret (normalized_integer(0usize, false), InvalidOperator) }
    if op == .PunctAmp || op == .PunctCaret || op == .PunctPipe {
        let width = integer_width(left_type)
        let left_bits = integer_bits(left, width)
        let right_bits = integer_bits(right, width)
        let result_bits = bitwise_integer_bits(op, left_bits, right_bits, width)
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap {
        let width = integer_width(left_type)
        let mask = integer_mask(width)
        let left_bits = integer_bits(left, width)
        let right_bits = integer_bits(right, width)
        var result_bits = modular_add(left_bits, right_bits, mask)
        if op == .PunctSubWrap { result_bits = modular_subtract(left_bits, right_bits, mask) }
        if op == .PunctMulWrap { result_bits = modular_multiply(left_bits, right_bits, mask) }
        ret (integer_from_bits(result_bits, left_type), ok)
    }
    if op == .PunctPlus {
        let (value, value_error) = add_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctMinus {
        let (value, value_error) = subtract_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctStar {
        let (value, value_error) = multiply_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctSlash {
        let (value, value_error) = divide_integer_values(left, right)
        ret (value, value_error)
    }
    if op == .PunctPercent {
        let (value, value_error) = remainder_integer_values(left, right)
        ret (value, value_error)
    }
    ret (normalized_integer(0usize, false), Unsupported)
}

fn evaluate_constant_expr(c: *Checker, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .ArrayLen {
        let (length, length_error) = length_of_subject(c, expression.ty)
        if length_error != ok { ret (normalized_integer(0usize, false), invalid_type(), length_error) }
        let (contextual_type, context_error) = apply_context(c, make_type(.Integer, "usize", expression.module_index), expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (normalized_integer(length, false), contextual_type, ok)
    }
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (expression.value, contextual_type, ok)
    }
    if expression.kind == .Name {
        // A generic instance's integer argument is a constant in its body. Resolve it
        // here as array lengths and explicit generic arguments already do, so a
        // comptime `if N == 0` can discard an unreachable recursive arm.
        if c.active_arguments && c.active_instance < c.function_count && expression.module_index == c.functions[c.active_instance].module_index {
            let (parameter_index, parameter_found) = active_comptime_parameter(c, expression.name)
            if parameter_found {
                let parameter = c.comptime_parameters[parameter_index]
                if parameter.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
                let (argument, argument_found) = active_argument(c, parameter_index)
                if !argument_found { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
                let (argument_type, context_error) = apply_context(c, parameter.ty, expected)
                if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
                ret (normalized_integer(argument.value, false), argument_type, ok)
            }
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (c.constants[constant_index].value, constant_type, ok)
    }
    if expression.kind == .Call {
        if !c.has_graph { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        var values: [16]IntegerValue = zero
        var types: [16]Type = zero
        if expression.argument_count > values.len { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        var argument_at = 0usize
        while argument_at < expression.argument_count {
            let wrapper = c.constant_exprs[expression.first_argument + argument_at]
            let (value, value_type, value_error) = evaluate_constant_expr(c, wrapper.left, invalid_type())
            if value_error != ok { ret (normalized_integer(0usize, false), invalid_type(), value_error) }
            values[argument_at] = value
            types[argument_at] = value_type
            argument_at += 1usize
        }
        c.interp_steps = 0usize
        c.interp_depth = 0usize
        let (result, result_type, call_error) = interp_call(c, c.graph, expression.module_index, expression.name, values[..expression.argument_count], types[..expression.argument_count], expression.site, expression.module_index)
        if call_error != ok { ret (normalized_integer(0usize, false), invalid_type(), call_error) }
        record_explain_comptime_call(c, expression)
        let (contextual_type, context_error) = apply_context(c, result_type, expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (result, contextual_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        if expression.op == .PunctBang { operand_expected = make_type(.Bool, "bool", expression.module_index) }
        let (operand, operand_type, operand_error) = evaluate_constant_expr(c, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctBang {
            if operand_type.kind != .Bool { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            var flipped = 0usize
            if operand.magnitude == 0usize { flipped = 1usize }
            ret (normalized_integer(flipped, false), operand_type, ok)
        }
        if expression.op == .PunctTilde {
            if operand_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if !integer_representable(operand, operand_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        // A comparison, and `&&`/`||`, are bools (D222): the operands under no context
        // for a comparison, and under `bool` for the logical pair.
        if is_comparison(expression.op) || expression.op == .PunctAndAnd || expression.op == .PunctOrOr {
            let boolean = make_type(.Bool, "bool", expression.module_index)
            var operand_expected = invalid_type()
            if !is_comparison(expression.op) { operand_expected = boolean }
            let (compared_left, compared_left_type, compared_left_error) = evaluate_constant_expr(c, expression.left, operand_expected)
            if compared_left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), compared_left_error) }
            var right_context = compared_left_type
            if !is_comparison(expression.op) { right_context = boolean }
            let (compared_right, compared_right_type, compared_right_error) = evaluate_constant_expr(c, expression.right, right_context)
            if compared_right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), compared_right_error) }
            var truth = false
            if is_comparison(expression.op) {
                if compared_left_type.kind == .Bool || compared_right_type.kind == .Bool {
                    if compared_left_type.kind != compared_right_type.kind || (expression.op != .PunctEqEq && expression.op != .PunctBangEq) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
                } else {
                    let (compared_type, compared_error) = constant_result_type(c, compared_left_type, compared_right_type)
                    if compared_error != ok { ret (normalized_integer(0usize, false), invalid_type(), compared_error) }
                }
                truth = interp_compare(expression.op, compared_left, compared_right)
            } else {
                if compared_left_type.kind != .Bool || compared_right_type.kind != .Bool { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
                if expression.op == .PunctAndAnd { truth = compared_left.magnitude != 0usize && compared_right.magnitude != 0usize } else { truth = compared_left.magnitude != 0usize || compared_right.magnitude != 0usize }
            }
            let (boolean_type, boolean_context_error) = apply_context(c, boolean, expected)
            if boolean_context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), boolean_context_error) }
            var bits = 0usize
            if truth { bits = 1usize }
            ret (normalized_integer(bits, false), boolean_type, ok)
        }
        let (left, left_type, left_error) = evaluate_constant_expr(c, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_constant_expr(c, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger {
                right_type = make_type(.Integer, "u32", left_type.module_index)
            }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, result_type)) {
            ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow)
        }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) {
            ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow)
        }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}


// ---- Section 9's compile-time evaluation of a call (D218) --------------------------
//
// A `const` initialiser may call a function. The call is evaluated by walking the
// callee's syntax tree with integer and bool values alone: `let`/`var`, assignment
// and the compound forms, `if`/`else`, `while`, `break`/`continue`, `ret`, the
// arithmetic, bitwise, shift, comparison and logical operators, `!`, `-`, `~`,
// parentheses, module-scope constants, and calls to other such functions, in the
// same module or a qualified one. Anything else is a compile error naming the
// constant and what it reached. The step budget is the section's ten million.
//
// ponytail: integers and bools in locals, nothing addressable. Arrays, structs,
// slices and the arena are the interpreter memory the section describes and the
// upgrade; every `const` written so far is an integer.

type InterpFrame = struct {
    names: [48]str,
    values: [48]IntegerValue,
    types: [48]Type,
    // An array local (D221): `is_array` set, `types` its element type, `bases` and
    // `lengths` its run of cells. Arrays live in their frame and do not cross a call.
    is_array: [48]bool,
    bases: [48]usize,
    lengths: [48]usize,
    cells: [512]IntegerValue,
    cell_count: usize,
    count: usize,
    marks: [16]usize,
    mark_count: usize,
    module_index: usize,
    return_type: Type,
    result: IntegerValue,
    result_type: Type,
}

// An integer or bool type by its name, or an invalid type.
fn primitive_type(name: str, module_index: usize) -> Type {
    if is_integer_name(name) { ret make_type(.Integer, name, module_index) }
    if same(name, "bool") { ret make_type(.Bool, "bool", module_index) }
    ret invalid_type()
}

fn interp_control_next() -> usize { ret 0usize }
fn interp_control_return() -> usize { ret 1usize }
fn interp_control_break() -> usize { ret 2usize }
fn interp_control_continue() -> usize { ret 3usize }

fn interp_fail(c: *Checker, module_index: usize, node: syntax.Node, reason: str) -> err {
    record_failure(c, module_index, node, .ComptimeEvaluation, c.interp_constant, reason)
    ret ComptimeUnsupported
}

fn interp_step(c: *Checker, module_index: usize, node: syntax.Node) -> err {
    c.interp_steps += 1usize
    c.interp_total += 1usize
    // The deadline inside an evaluation (D496, H16): the clock every 65536 steps --
    // a few milliseconds of interpretation -- so a constant that runs for seconds
    // stops when the build's deadline passes, not when it finishes.
    if (c.interp_total & 65535usize) == 0usize && past_deadline(c) { ret Cancelled }
    if c.interp_steps > 10000000usize {
        record_failure(c, module_index, node, .ComptimeEvaluation, c.interp_constant, "ten million steps")
        ret ComptimeBudget
    }
    ret ok
}

// The callee's module, parsed and tokenized once and kept: the graph's node storage
// holds the tree of the module being checked, which a call from its body must not
// disturb, and a call chain may cross modules and come back.
fn interp_module(c: *Checker, g: *graph.Graph, module_index: usize) -> (usize, err) {
    if module_index >= g.count { ret (0usize, InvalidConstant) }
    if !c.interp_ready {
        let (trees, trees_error) = mem.alloc[parse.Tree](c.arena, g.count)
        if trees_error != ok { ret (0usize, trees_error) }
        let (parsed, parsed_error) = mem.alloc[bool](c.arena, g.count)
        if parsed_error != ok { ret (0usize, parsed_error) }
        let (token_tables, token_tables_error) = mem.alloc[[]lex.Token](c.arena, g.count)
        if token_tables_error != ok { ret (0usize, token_tables_error) }
        let (token_counts, token_counts_error) = mem.alloc[usize](c.arena, g.count)
        if token_counts_error != ok { ret (0usize, token_counts_error) }
        var at = 0usize
        while at < g.count {
            parsed[at] = false
            at += 1usize
        }
        c.interp_trees = trees
        c.interp_parsed = parsed
        c.interp_tokens = token_tables
        c.interp_token_counts = token_counts
        c.interp_ready = true
    }
    if c.interp_parsed[module_index] { ret (module_index, ok) }
    // The module's tree is the one the graph keeps (D317), unless that is a header
    // tree (D392) with the callee's body skipped: then the tokens are parsed again
    // into storage of the interpreter's own.
    var kept: parse.Tree = zero
    if g.modules[module_index].has_tree && g.modules[module_index].headers_only {
        let text_length = g.modules[module_index].text.len
        let (nodes, nodes_error) = mem.alloc[syntax.Node](c.arena, text_length / 2usize + 4096usize)
        if nodes_error != ok { ret (0usize, nodes_error) }
        let (children, children_error) = mem.alloc[u32](c.arena, text_length + 4096usize)
        if children_error != ok { ret (0usize, children_error) }
        let init_error = parse.init_tree(&kept, nodes, children)
        if init_error != ok { ret (0usize, init_error) }
        let full_error = parse.parse_tokens(&kept, g.modules[module_index].text, g.modules[module_index].tokens)
        if full_error != ok { ret (0usize, full_error) }
    } else {
        let kept_error = graph.parse_module(g, module_index, &kept)
        if kept_error != ok { ret (0usize, kept_error) }
    }
    c.interp_trees[module_index] = kept
    // The tokens likewise are the module's own (D316).
    c.interp_tokens[module_index] = g.modules[module_index].tokens
    c.interp_token_counts[module_index] = g.modules[module_index].tokens.len
    c.interp_parsed[module_index] = true
    ret (module_index, ok)
}

fn interp_lookup(frame: *InterpFrame, name: str) -> (usize, bool) {
    var at = frame.count
    while at > 0usize {
        at = at - 1usize
        if same(frame.names[at], name) { ret (at, true) }
    }
    ret (0usize, false)
}

fn interp_bind(frame: *InterpFrame, name: str, value: IntegerValue, ty: Type) -> err {
    if frame.count == frame.names.len { ret Capacity }
    frame.names[frame.count] = name
    frame.values[frame.count] = value
    frame.types[frame.count] = ty
    frame.is_array[frame.count] = false
    frame.count += 1usize
    ret ok
}

// An array local of `length` zeroed cells of `element`; the cells are given back
// with the scope, as the locals are.
fn interp_bind_array(c: *Checker, module_index: usize, node: syntax.Node, frame: *InterpFrame, name: str, element: Type, length: usize) -> err {
    if frame.count == frame.names.len { ret Capacity }
    if length > frame.cells.len - frame.cell_count { ret interp_fail(c, module_index, node, "an array past the cells a frame holds") }
    frame.names[frame.count] = name
    frame.values[frame.count] = normalized_integer(0usize, false)
    frame.types[frame.count] = element
    frame.is_array[frame.count] = true
    frame.bases[frame.count] = frame.cell_count
    frame.lengths[frame.count] = length
    var at = 0usize
    while at < length {
        frame.cells[frame.cell_count + at] = normalized_integer(0usize, false)
        at += 1usize
    }
    frame.cell_count += length
    frame.count += 1usize
    ret ok
}

// `t[i]` on an array local: the cell, bounds checked as section 11 would at run time.
fn interp_cell(c: *Checker, g: *graph.Graph, tree: *parse.Tree, frame: *InterpFrame, node: syntax.Node) -> (usize, usize, err) {
    let module_index = frame.module_index
    let text = g.modules[module_index].text
    var base_index = 0usize
    var index_index = 0usize
    var count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if count == 0usize { base_index = parse.child_index_at(tree, at) }
            if count == 1usize { index_index = parse.child_index_at(tree, at) }
            count += 1usize
        }
        at += 1usize
    }
    if count != 2usize { ret (0usize, 0usize, interp_fail(c, module_index, node, "an index of a shape it does not evaluate")) }
    let base = tree.nodes[base_index]
    if base.kind != .NameExpr { ret (0usize, 0usize, interp_fail(c, module_index, node, "an index into something that is not an array local")) }
    let base_token = c.tokens[usize(base.token_start)]
    let (slot, found) = interp_lookup(frame, text[base_token.start..base_token.end])
    if !found || !frame.is_array[slot] { ret (0usize, 0usize, interp_fail(c, module_index, node, "an index into something that is not an array local")) }
    let (index, index_type, index_error) = interp_expr(c, g, tree, frame, index_index, make_type(.Integer, "usize", module_index))
    if index_error != ok { ret (0usize, 0usize, index_error) }
    if index_type.kind != .Integer || index.negative { ret (0usize, 0usize, interp_fail(c, module_index, node, "an index that is not a usize")) }
    if index.magnitude >= frame.lengths[slot] { ret (0usize, 0usize, interp_fail(c, module_index, node, "an index out of bounds")) }
    ret (slot, frame.bases[slot] + index.magnitude, ok)
}

fn interp_bool_type(module_index: usize) -> Type { ret make_type(.Bool, "bool", module_index) }

// A value into the type a binding, parameter or return declares: a typed value has
// to agree, an untyped one has to fit.
fn interp_convert(c: *Checker, module_index: usize, node: syntax.Node, value: IntegerValue, from: Type, into: Type) -> (IntegerValue, Type, err) {
    if into.kind == .Invalid { ret (value, from, ok) }
    if into.kind == .Bool {
        if from.kind != .Bool { ret (value, from, interp_fail(c, module_index, node, "a bool from a number")) }
        ret (value, into, ok)
    }
    if into.kind != .Integer { ret (value, from, interp_fail(c, module_index, node, "a type that is not an integer or bool")) }
    if from.kind == .Bool { ret (value, from, interp_fail(c, module_index, node, "a number from a bool")) }
    if from.kind == .Integer && !type_equal(c, from, into) { ret (value, from, interp_fail(c, module_index, node, "a value of another integer type")) }
    if !integer_representable(value, into) { ret (value, from, interp_fail(c, module_index, node, "a value the type cannot hold")) }
    ret (value, into, ok)
}

fn interp_compare(op: lex.Kind, left: IntegerValue, right: IntegerValue) -> bool {
    var less = false
    var equal = left.negative == right.negative && left.magnitude == right.magnitude
    if left.negative && !right.negative { less = true }
    if !left.negative && !right.negative { less = left.magnitude < right.magnitude }
    if left.negative && right.negative { less = left.magnitude > right.magnitude }
    if op == .PunctEqEq { ret equal }
    if op == .PunctBangEq { ret !equal }
    if op == .PunctLt { ret less }
    if op == .PunctLtEq { ret less || equal }
    if op == .PunctGt { ret !less && !equal }
    ret !less
}

fn interp_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, frame: *InterpFrame, node_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    let module_index = frame.module_index
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    let none = normalized_integer(0usize, false)
    let step_error = interp_step(c, module_index, node)
    if step_error != ok { ret (none, invalid_type(), step_error) }
    if node.kind == .GroupExpr {
        let (inner, found) = first_node_child(tree, node)
        if !found { ret (none, invalid_type(), parse.InvalidSyntax) }
        let (grouped, grouped_type, grouped_error) = interp_expr(c, g, tree, frame, inner, expected)
        ret (grouped, grouped_type, grouped_error)
    }
    if node.kind == .LiteralExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind == .KwTrue { ret (normalized_integer(1usize, false), interp_bool_type(module_index), ok) }
        if token.kind == .KwFalse { ret (none, interp_bool_type(module_index), ok) }
        let (magnitude, spelled_type, literal_error) = integer_literal_value(c, text, node)
        if literal_error != ok { ret (none, invalid_type(), interp_fail(c, module_index, node, "a literal that is not an integer")) }
        var typed = spelled_type
        if is_untyped(typed) && expected.kind == .Integer { typed = expected }
        let value = normalized_integer(magnitude, false)
        if typed.kind == .Integer && !integer_representable(value, typed) { ret (none, invalid_type(), interp_fail(c, module_index, node, "a literal the type cannot hold")) }
        ret (value, typed, ok)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        let name = text[token.start..token.end]
        let (slot, found_local) = interp_lookup(frame, name)
        if found_local { ret (frame.values[slot], frame.types[slot], ok) }
        let (constant_index, found_constant) = find_constant(c, module_index, name)
        if !found_constant { ret (none, invalid_type(), interp_fail(c, module_index, node, "a name that is no local or constant")) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (none, invalid_type(), dependency_error) }
        ret (c.constants[constant_index].value, c.constants[constant_index].ty, ok)
    }
    if node.kind == .BracketPostfix {
        let (slot, cell, cell_error) = interp_cell(c, g, tree, frame, node)
        if cell_error != ok { ret (none, invalid_type(), cell_error) }
        ret (frame.cells[cell], frame.types[slot], ok)
    }
    if node.kind == .FieldExpr {
        // `t.len` of an array local, before a qualified constant is tried.
        let (receiver_index, has_receiver) = first_node_child(tree, node)
        if has_receiver && tree.nodes[receiver_index].kind == .NameExpr {
            let receiver_token = c.tokens[usize(tree.nodes[receiver_index].token_start)]
            let (slot, found_local) = interp_lookup(frame, text[receiver_token.start..receiver_token.end])
            if found_local {
                if !frame.is_array[slot] { ret (none, invalid_type(), interp_fail(c, module_index, node, "a field, which no value here has")) }
                var member_at = usize(node.token_end)
                while member_at > usize(tree.nodes[receiver_index].token_end) {
                    member_at = member_at - 1usize
                    if c.tokens[member_at].kind == .Identifier { break }
                }
                if !same(text[c.tokens[member_at].start..c.tokens[member_at].end], "len") { ret (none, invalid_type(), interp_fail(c, module_index, node, "a field of an array other than `len`")) }
                ret (normalized_integer(frame.lengths[slot], false), make_type(.Integer, "usize", module_index), ok)
            }
        }
        let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
        if !found_member { ret (none, invalid_type(), interp_fail(c, module_index, node, "a field, which no value here has")) }
        let (constant_index, found_constant) = find_constant(c, target_module, member)
        if !found_constant { ret (none, invalid_type(), interp_fail(c, module_index, node, "a qualified name that is no constant")) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (none, invalid_type(), dependency_error) }
        ret (c.constants[constant_index].value, c.constants[constant_index].ty, ok)
    }
    if node.kind == .UnaryExpr {
        let (inner, found) = first_node_child(tree, node)
        if !found { ret (none, invalid_type(), parse.InvalidSyntax) }
        let op = c.tokens[usize(node.token_start)].kind
        if op == .PunctBang {
            let (value, value_type, value_error) = interp_expr(c, g, tree, frame, inner, interp_bool_type(module_index))
            if value_error != ok { ret (none, invalid_type(), value_error) }
            if value_type.kind != .Bool { ret (none, invalid_type(), interp_fail(c, module_index, node, "`!` of a number")) }
            if value.magnitude == 0usize { ret (normalized_integer(1usize, false), value_type, ok) }
            ret (none, value_type, ok)
        }
        if op == .PunctMinus {
            let (value, value_type, value_error) = interp_expr(c, g, tree, frame, inner, expected)
            if value_error != ok { ret (none, invalid_type(), value_error) }
            if value_type.kind == .Bool || (value_type.kind == .Integer && unsigned_integer_type(value_type)) { ret (none, invalid_type(), interp_fail(c, module_index, node, "`-` of an unsigned or bool value")) }
            let negated = normalized_integer(value.magnitude, !value.negative)
            if value_type.kind == .Integer && !integer_representable(negated, value_type) { ret (none, invalid_type(), interp_fail(c, module_index, node, "a negation the type cannot hold")) }
            ret (negated, value_type, ok)
        }
        if op == .PunctTilde {
            let (value, value_type, value_error) = interp_expr(c, g, tree, frame, inner, expected)
            if value_error != ok { ret (none, invalid_type(), value_error) }
            if value_type.kind != .Integer { ret (none, invalid_type(), interp_fail(c, module_index, node, "`~` of a value with no width")) }
            let width = integer_width(value_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(value, width), value_type), value_type, ok)
        }
        ret (none, invalid_type(), interp_fail(c, module_index, node, "an operator it does not evaluate"))
    }
    if node.kind == .BinaryExpr {
        var children: [2]usize = zero
        var count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == children.len { ret (none, invalid_type(), parse.InvalidSyntax) }
                children[count] = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (none, invalid_type(), parse.InvalidSyntax) }
        let op = binary_operator(c, tree, node)
        if op == .PunctAndAnd || op == .PunctOrOr {
            let (left, left_type, left_error) = interp_expr(c, g, tree, frame, children[0usize], interp_bool_type(module_index))
            if left_error != ok { ret (none, invalid_type(), left_error) }
            if left_type.kind != .Bool { ret (none, invalid_type(), interp_fail(c, module_index, node, "`&&` or `||` of a number")) }
            if op == .PunctAndAnd && left.magnitude == 0usize { ret (none, left_type, ok) }
            if op == .PunctOrOr && left.magnitude != 0usize { ret (left, left_type, ok) }
            let (right, right_type, right_error) = interp_expr(c, g, tree, frame, children[1usize], interp_bool_type(module_index))
            if right_error != ok { ret (none, invalid_type(), right_error) }
            if right_type.kind != .Bool { ret (none, invalid_type(), interp_fail(c, module_index, node, "`&&` or `||` of a number")) }
            ret (right, right_type, ok)
        }
        var left_expected = expected
        if is_comparison(op) || is_shift(op) { left_expected = invalid_type() }
        let (left, left_type, left_error) = interp_expr(c, g, tree, frame, children[0usize], left_expected)
        if left_error != ok { ret (none, invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = interp_expr(c, g, tree, frame, children[1usize], right_expected)
        if right_error != ok { ret (none, invalid_type(), right_error) }
        if is_comparison(op) {
            if left_type.kind == .Bool || raw_right_type.kind == .Bool {
                if left_type.kind != raw_right_type.kind || (op != .PunctEqEq && op != .PunctBangEq) { ret (none, invalid_type(), interp_fail(c, module_index, node, "an ordering of bools")) }
            } else {
                let (compared_type, compared_error) = constant_result_type(c, left_type, raw_right_type)
                if compared_error != ok { ret (none, invalid_type(), interp_fail(c, module_index, node, "a comparison of two integer types")) }
            }
            if interp_compare(op, left, right) { ret (normalized_integer(1usize, false), interp_bool_type(module_index), ok) }
            ret (none, interp_bool_type(module_index), ok)
        }
        if left_type.kind == .Bool || raw_right_type.kind == .Bool { ret (none, invalid_type(), interp_fail(c, module_index, node, "arithmetic on a bool")) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", module_index) }
            if result_type.kind == .UntypedInteger && expected.kind == .Integer { result_type = expected }
            if result_type.kind != .Integer { ret (none, invalid_type(), interp_fail(c, module_index, node, "a shift of a value with no width")) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (none, invalid_type(), interp_fail(c, module_index, node, "a shift by a signed count")) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (none, invalid_type(), interp_fail(c, module_index, node, "arithmetic over two integer types")) }
            result_type = resolved_type
            if result_type.kind == .UntypedInteger && expected.kind == .Integer { result_type = expected }
            if (op == .PunctAmp || op == .PunctCaret || op == .PunctPipe || op == .PunctAddWrap || op == .PunctSubWrap || op == .PunctMulWrap) && result_type.kind != .Integer { ret (none, invalid_type(), interp_fail(c, module_index, node, "a bitwise or wrapping operator on a value with no width")) }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, result_type)) { ret (none, invalid_type(), interp_fail(c, module_index, node, "an operand the type cannot hold")) }
        if (op == .PunctSlash || op == .PunctPercent) && right.magnitude == 0usize { ret (none, invalid_type(), interp_fail(c, module_index, node, "a division by zero")) }
        let (result, result_error) = evaluate_integer_binary(op, left, right, result_type, right_type)
        if result_error != ok { ret (none, invalid_type(), interp_fail(c, module_index, node, "an operator it does not evaluate")) }
        if result_type.kind == .Integer && op != .PunctAddWrap && op != .PunctSubWrap && op != .PunctMulWrap && !integer_representable(result, result_type) { ret (none, invalid_type(), interp_fail(c, module_index, node, "a result the type cannot hold")) }
        ret (result, result_type, ok)
    }
    if node.kind == .CallExpr {
        let (value, value_type, call_error) = interp_call_node(c, g, tree, frame, node)
        ret (value, value_type, call_error)
    }
    ret (none, invalid_type(), interp_fail(c, module_index, node, "an expression it does not evaluate"))
}

// `f(a, b)` or `m.f(a, b)` inside an evaluated body; a primitive type name in the
// callee position is section 4's checked cast.
fn interp_call_node(c: *Checker, g: *graph.Graph, tree: *parse.Tree, frame: *InterpFrame, node: syntax.Node) -> (IntegerValue, Type, err) {
    let module_index = frame.module_index
    let text = g.modules[module_index].text
    let none = normalized_integer(0usize, false)
    var callee_index = 0usize
    var arguments: [16]usize = zero
    var argument_count = 0usize
    var first = true
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if first {
                callee_index = parse.child_index_at(tree, at)
                first = false
            } else {
                if argument_count == arguments.len { ret (none, invalid_type(), interp_fail(c, module_index, node, "a call of more than sixteen arguments")) }
                arguments[argument_count] = parse.child_index_at(tree, at)
                argument_count += 1usize
            }
        }
        at += 1usize
    }
    if first { ret (none, invalid_type(), parse.InvalidSyntax) }
    let callee = tree.nodes[callee_index]
    var target_module = module_index
    var name = ""
    if callee.kind == .NameExpr {
        let token = c.tokens[usize(callee.token_start)]
        name = text[token.start..token.end]
        let cast_type = primitive_type(name, module_index)
        if cast_type.kind == .Integer || cast_type.kind == .Bool {
            if argument_count != 1usize { ret (none, invalid_type(), interp_fail(c, module_index, node, "a cast of other than one value")) }
            let (value, value_type, value_error) = interp_expr(c, g, tree, frame, arguments[0usize], invalid_type())
            if value_error != ok { ret (none, invalid_type(), value_error) }
            if cast_type.kind != .Integer || value_type.kind == .Bool { ret (none, invalid_type(), interp_fail(c, module_index, node, "a cast that is not integer to integer")) }
            if !integer_representable(value, cast_type) { ret (none, invalid_type(), interp_fail(c, module_index, node, "a cast of a value the type cannot hold")) }
            ret (value, cast_type, ok)
        }
    } else {
        if callee.kind != .FieldExpr { ret (none, invalid_type(), interp_fail(c, module_index, node, "a call through a value")) }
        let (qualified_module, member, found_member) = qualified_member(c, g, tree, module_index, callee)
        if !found_member { ret (none, invalid_type(), interp_fail(c, module_index, node, "a call through a value")) }
        target_module = qualified_module
        name = member
    }
    var values: [16]IntegerValue = zero
    var types: [16]Type = zero
    var argument_at = 0usize
    while argument_at < argument_count {
        let (value, value_type, value_error) = interp_expr(c, g, tree, frame, arguments[argument_at], invalid_type())
        if value_error != ok { ret (none, invalid_type(), value_error) }
        values[argument_at] = value
        types[argument_at] = value_type
        argument_at += 1usize
    }
    let (result, result_type, call_error) = interp_call(c, g, target_module, name, values[..argument_count], types[..argument_count], node, module_index)
    ret (result, result_type, call_error)
}

// The evaluation of one call: the callee's declaration, its parameters bound, its
// body run. `site` and `site_module` are where the call is written, for the report.
fn interp_call(c: *Checker, g: *graph.Graph, module_index: usize, name: str, arguments: []const IntegerValue, argument_types: []const Type, site: syntax.Node, site_module: usize) -> (IntegerValue, Type, err) {
    let none = normalized_integer(0usize, false)
    if !c.signatures_ready { ret (none, invalid_type(), ComptimeDeferred) }
    // ponytail: the section allows a thousand; a frame is stack, and the stack is the host's.
    if c.interp_depth >= 64usize {
        record_failure(c, site_module, site, .ComptimeEvaluation, c.interp_constant, "a call depth past sixty-four")
        ret (none, invalid_type(), ComptimeBudget)
    }
    // `u8(x)` at the top of an initialiser is section 4's checked cast, as it is in a body.
    let cast_type = primitive_type(name, module_index)
    if cast_type.kind == .Integer {
        if arguments.len != 1usize || argument_types[0usize].kind == .Bool { ret (none, invalid_type(), interp_fail(c, site_module, site, "a cast that is not one integer to an integer")) }
        if !integer_representable(arguments[0usize], cast_type) { ret (none, invalid_type(), interp_fail(c, site_module, site, "a cast of a value the type cannot hold")) }
        ret (arguments[0usize], cast_type, ok)
    }
    let (function_index, found) = find_function(c, module_index, name)
    if !found { ret (none, invalid_type(), interp_fail(c, site_module, site, "a call to a name that is no function")) }
    let function = c.functions[function_index]
    if function.generic || function.external || function.intrinsic { ret (none, invalid_type(), interp_fail(c, site_module, site, "a call to a generic, extern or intrinsic function")) }
    if function.parameter_count != arguments.len { ret (none, invalid_type(), interp_fail(c, site_module, site, "a call with the wrong number of arguments")) }
    if function.return_count != 1usize { ret (none, invalid_type(), interp_fail(c, site_module, site, "a call to a function returning other than one value")) }
    let return_type = c.return_types[function.first_return]
    if return_type.kind != .Integer && return_type.kind != .Bool { ret (none, invalid_type(), interp_fail(c, site_module, site, "a call to a function returning other than an integer or bool")) }
    let (parsed_module, parse_error) = interp_module(c, g, module_index)
    if parse_error != ok { ret (none, invalid_type(), parse_error) }
    // The callee's tokens stand in for the caller's while its body runs.
    let saved_tokens = c.tokens
    let saved_token_count = c.token_count
    c.tokens = c.interp_tokens[module_index]
    c.token_count = c.interp_token_counts[module_index]
    c.interp_depth += 1usize
    let (result, result_type, body_error) = interp_function(c, g, module_index, function_index, function, arguments, argument_types, return_type)
    c.interp_depth = c.interp_depth - 1usize
    c.tokens = saved_tokens
    c.token_count = saved_token_count
    ret (result, result_type, body_error)
}

fn interp_function(c: *Checker, g: *graph.Graph, module_index: usize, function_index: usize, function: Function, arguments: []const IntegerValue, argument_types: []const Type, return_type: Type) -> (IntegerValue, Type, err) {
    let none = normalized_integer(0usize, false)
    let tree = &c.interp_trees[module_index]
    let text = g.modules[module_index].text
    var declaration = 0usize
    var found_declaration = false
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            let (declared_name, name_error) = function_name(c, text, node)
            if name_error == ok && same(declared_name, function.name) {
                declaration = node_index
                found_declaration = true
                break
            }
        }
        node_index += 1usize
    }
    if !found_declaration { ret (none, invalid_type(), interp_fail(c, module_index, tree.nodes[0usize], "a function whose declaration it cannot find")) }
    var frame: InterpFrame = zero
    frame.module_index = module_index
    frame.return_type = return_type
    var parameter_at = 0usize
    while parameter_at < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_at]
        if parameter.ty.kind != .Integer && parameter.ty.kind != .Bool { ret (none, invalid_type(), interp_fail(c, module_index, tree.nodes[declaration], "a parameter that is not an integer or bool")) }
        let (converted, converted_type, convert_error) = interp_convert(c, module_index, tree.nodes[declaration], arguments[parameter_at], argument_types[parameter_at], parameter.ty)
        if convert_error != ok { ret (none, invalid_type(), convert_error) }
        let bind_error = interp_bind(&frame, parameter.name, converted, converted_type)
        if bind_error != ok { ret (none, invalid_type(), bind_error) }
        parameter_at += 1usize
    }
    let declared = tree.nodes[declaration]
    let end = usize(declared.first_child) + usize(declared.child_count)
    var at = usize(declared.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind == .Block {
                let (control, control_error) = interp_block(c, g, tree, &frame, child_index)
                if control_error != ok { ret (none, invalid_type(), control_error) }
                if control != interp_control_return() { ret (none, invalid_type(), interp_fail(c, module_index, tree.nodes[child_index], "the end of a body without `ret`")) }
                ret (frame.result, frame.result_type, ok)
            }
        }
        at += 1usize
    }
    ret (none, invalid_type(), interp_fail(c, module_index, declared, "a function with no body"))
}

fn interp_block(c: *Checker, g: *graph.Graph, tree: *parse.Tree, frame: *InterpFrame, block_index: usize) -> (usize, err) {
    let block = tree.nodes[block_index]
    if frame.mark_count == frame.marks.len { ret (0usize, Capacity) }
    frame.marks[frame.mark_count] = frame.count
    frame.mark_count += 1usize
    var control = interp_control_next()
    let end = usize(block.first_child) + usize(block.child_count)
    var at = usize(block.first_child)
    while at < end && control == interp_control_next() {
        if parse.child_is_node_at(tree, at) {
            let (statement_control, statement_error) = interp_statement(c, g, tree, frame, parse.child_index_at(tree, at))
            if statement_error != ok { ret (0usize, statement_error) }
            control = statement_control
        }
        at += 1usize
    }
    frame.mark_count = frame.mark_count - 1usize
    frame.count = frame.marks[frame.mark_count]
    // The cells of the arrays that went out of scope go with them.
    var cells = 0usize
    var live = 0usize
    while live < frame.count {
        if frame.is_array[live] && frame.bases[live] + frame.lengths[live] > cells { cells = frame.bases[live] + frame.lengths[live] }
        live += 1usize
    }
    frame.cell_count = cells
    ret (control, ok)
}

fn interp_statement(c: *Checker, g: *graph.Graph, tree: *parse.Tree, frame: *InterpFrame, node_index: usize) -> (usize, err) {
    let module_index = frame.module_index
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    let step_error = interp_step(c, module_index, node)
    if step_error != ok { ret (0usize, step_error) }
    if node.kind == .Block {
        let (control, block_error) = interp_block(c, g, tree, frame, node_index)
        ret (control, block_error)
    }
    if node.kind == .BindingStmt {
        var binding_index = 0usize
        var has_binding = false
        var declared_type = invalid_type()
        var initializer_index = 0usize
        var has_initializer = false
        var array_type_index = 0usize
        var has_array_type = false
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let child_index = parse.child_index_at(tree, at)
                let child = tree.nodes[child_index]
                if child.kind == .Binding {
                    binding_index = child_index
                    has_binding = true
                } else {
                    if child.kind == .NamedType {
                        let type_token = c.tokens[usize(child.token_start)]
                        declared_type = primitive_type(text[type_token.start..type_token.end], module_index)
                        if declared_type.kind != .Integer && declared_type.kind != .Bool { ret (0usize, interp_fail(c, module_index, node, "a binding of a type that is not an integer or bool")) }
                    } else {
                        if child.kind == .ArrayType {
                            array_type_index = child_index
                            has_array_type = true
                        } else {
                            if is_type_node(child.kind) { ret (0usize, interp_fail(c, module_index, node, "a binding of a type that is not an integer, bool or array")) }
                            initializer_index = child_index
                            has_initializer = true
                        }
                    }
                }
            }
            at += 1usize
        }
        // `zero` is a token of the statement, not a node of its own.
        let zeroed = contains_token(c, usize(node.token_start), usize(node.token_end), .KwZero)
        if !has_binding || (!has_initializer && !zeroed) { ret (0usize, interp_fail(c, module_index, node, "a binding without a value")) }
        let binding = tree.nodes[binding_index]
        let binding_token = c.tokens[usize(binding.token_start)]
        if binding_token.kind != .Identifier { ret (0usize, interp_fail(c, module_index, node, "a binding that is not one name")) }
        if !has_array_type && !has_initializer {
            if declared_type.kind == .Invalid { ret (0usize, interp_fail(c, module_index, node, "`zero` with no type")) }
            let zero_bind_error = interp_bind(frame, text[binding_token.start..binding_token.end], normalized_integer(0usize, false), declared_type)
            if zero_bind_error != ok { ret (0usize, zero_bind_error) }
            ret (interp_control_next(), ok)
        }
        if has_array_type {
            // `var t: [N]u8 = zero` (D221): a length the length evaluator settles, an
            // element type that is an integer or bool, and `zero` as the value.
            let array_node = tree.nodes[array_type_index]
            var length_index = 0usize
            var element_index = 0usize
            var array_children = 0usize
            let array_end = usize(array_node.first_child) + usize(array_node.child_count)
            var array_at = usize(array_node.first_child)
            while array_at < array_end {
                if parse.child_is_node_at(tree, array_at) {
                    if array_children == 0usize { length_index = parse.child_index_at(tree, array_at) }
                    if array_children == 1usize { element_index = parse.child_index_at(tree, array_at) }
                    array_children += 1usize
                }
                array_at += 1usize
            }
            if array_children != 2usize || tree.nodes[element_index].kind != .NamedType { ret (0usize, interp_fail(c, module_index, node, "an array of a shape it does not evaluate")) }
            let (length, length_error) = array_length_value(c, g, tree, module_index, length_index)
            if length_error != ok { ret (0usize, interp_fail(c, module_index, node, "an array length it cannot settle")) }
            let element_token = c.tokens[usize(tree.nodes[element_index].token_start)]
            let element = primitive_type(text[element_token.start..element_token.end], module_index)
            if element.kind != .Integer && element.kind != .Bool { ret (0usize, interp_fail(c, module_index, node, "an array of elements that are not integers or bools")) }
            if has_initializer || !zeroed { ret (0usize, interp_fail(c, module_index, node, "an array with a value other than `zero`")) }
            let array_bind_error = interp_bind_array(c, module_index, node, frame, text[binding_token.start..binding_token.end], element, length)
            if array_bind_error != ok { ret (0usize, array_bind_error) }
            ret (interp_control_next(), ok)
        }
        let (value, value_type, value_error) = interp_expr(c, g, tree, frame, initializer_index, declared_type)
        if value_error != ok { ret (0usize, value_error) }
        let (converted, converted_type, convert_error) = interp_convert(c, module_index, node, value, value_type, declared_type)
        if convert_error != ok { ret (0usize, convert_error) }
        if converted_type.kind == .UntypedInteger { ret (0usize, interp_fail(c, module_index, node, "a binding with no type to give an untyped literal")) }
        let bind_error = interp_bind(frame, text[binding_token.start..binding_token.end], converted, converted_type)
        if bind_error != ok { ret (0usize, bind_error) }
        ret (interp_control_next(), ok)
    }
    if node.kind == .AssignmentStmt {
        var place_index = 0usize
        var value_index = 0usize
        var count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == 0usize { place_index = parse.child_index_at(tree, at) }
                value_index = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (0usize, interp_fail(c, module_index, node, "an assignment that is not `name op= value`")) }
        let place = tree.nodes[place_index]
        var slot = 0usize
        var cell = 0usize
        var into_cell = false
        if place.kind == .BracketPostfix {
            let (array_slot, found_cell, cell_error) = interp_cell(c, g, tree, frame, place)
            if cell_error != ok { ret (0usize, cell_error) }
            slot = array_slot
            cell = found_cell
            into_cell = true
        } else {
            if place.kind != .NameExpr { ret (0usize, interp_fail(c, module_index, node, "an assignment to a place that is not a local")) }
            let place_token = c.tokens[usize(place.token_start)]
            let (found_slot, found) = interp_lookup(frame, text[place_token.start..place_token.end])
            if !found || frame.is_array[found_slot] { ret (0usize, interp_fail(c, module_index, node, "an assignment to a name that is no scalar local")) }
            slot = found_slot
        }
        let op = assignment_operator(c, usize(place.token_end), usize(tree.nodes[value_index].token_start))
        let slot_type = frame.types[slot]
        var current = frame.values[slot]
        if into_cell { current = frame.cells[cell] }
        let (value, value_type, value_error) = interp_expr(c, g, tree, frame, value_index, slot_type)
        if value_error != ok { ret (0usize, value_error) }
        if op == .PunctAssign {
            let (converted, converted_type, convert_error) = interp_convert(c, module_index, node, value, value_type, slot_type)
            if convert_error != ok { ret (0usize, convert_error) }
            if into_cell { frame.cells[cell] = converted } else { frame.values[slot] = converted }
            ret (interp_control_next(), ok)
        }
        let binary = compound_base_operator(op)
        if binary == .Invalid || slot_type.kind != .Integer { ret (0usize, interp_fail(c, module_index, node, "a compound assignment it does not evaluate")) }
        var right_type = value_type
        if is_shift(binary) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", module_index) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (0usize, interp_fail(c, module_index, node, "a shift by a signed count")) }
        } else {
            let (converted, converted_type, convert_error) = interp_convert(c, module_index, node, value, value_type, slot_type)
            if convert_error != ok { ret (0usize, convert_error) }
            right_type = converted_type
        }
        if (binary == .PunctSlash || binary == .PunctPercent) && value.magnitude == 0usize { ret (0usize, interp_fail(c, module_index, node, "a division by zero")) }
        let (result, result_error) = evaluate_integer_binary(binary, current, value, slot_type, right_type)
        if result_error != ok { ret (0usize, interp_fail(c, module_index, node, "a compound assignment it does not evaluate")) }
        if binary != .PunctAddWrap && binary != .PunctSubWrap && binary != .PunctMulWrap && !integer_representable(result, slot_type) { ret (0usize, interp_fail(c, module_index, node, "a result the type cannot hold")) }
        if into_cell { frame.cells[cell] = result } else { frame.values[slot] = result }
        ret (interp_control_next(), ok)
    }
    if node.kind == .ReturnStmt {
        let (value_index, has_value) = first_node_child(tree, node)
        if !has_value { ret (0usize, interp_fail(c, module_index, node, "a `ret` with no value")) }
        let (value, value_type, value_error) = interp_expr(c, g, tree, frame, value_index, frame.return_type)
        if value_error != ok { ret (0usize, value_error) }
        let (converted, converted_type, convert_error) = interp_convert(c, module_index, node, value, value_type, frame.return_type)
        if convert_error != ok { ret (0usize, convert_error) }
        frame.result = converted
        frame.result_type = converted_type
        ret (interp_control_return(), ok)
    }
    if node.kind == .BreakStmt { ret (interp_control_break(), ok) }
    if node.kind == .ContinueStmt { ret (interp_control_continue(), ok) }
    if node.kind == .ForStmt {
        // `for i in a..b { }` (D221): the name after `for`, the two bounds, the body.
        var parts: [3]usize = zero
        var part_count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if part_count == parts.len { ret (0usize, interp_fail(c, module_index, node, "a `for` of a shape it does not evaluate")) }
                parts[part_count] = parse.child_index_at(tree, at)
                part_count += 1usize
            }
            at += 1usize
        }
        if part_count != 3usize { ret (0usize, interp_fail(c, module_index, node, "a `for` that is not over a range")) }
        let name_token = c.tokens[usize(node.token_start) + 1usize]
        if name_token.kind != .Identifier { ret (0usize, interp_fail(c, module_index, node, "a `for` of a shape it does not evaluate")) }
        let (low, low_type, low_error) = interp_expr(c, g, tree, frame, parts[0usize], invalid_type())
        if low_error != ok { ret (0usize, low_error) }
        let (high, raw_high_type, high_error) = interp_expr(c, g, tree, frame, parts[1usize], low_type)
        if high_error != ok { ret (0usize, high_error) }
        let (range_type, range_error) = constant_result_type(c, low_type, raw_high_type)
        if range_error != ok { ret (0usize, interp_fail(c, module_index, node, "a range over two integer types")) }
        var counter_type = range_type
        if counter_type.kind == .UntypedInteger { counter_type = make_type(.Integer, "usize", module_index) }
        if frame.mark_count == frame.marks.len { ret (0usize, Capacity) }
        frame.marks[frame.mark_count] = frame.count
        frame.mark_count += 1usize
        let bind_error = interp_bind(frame, text[name_token.start..name_token.end], low, counter_type)
        if bind_error != ok { ret (0usize, bind_error) }
        let counter = frame.count - 1usize
        var control = interp_control_next()
        while interp_compare(.PunctLt, frame.values[counter], high) {
            let (body_control, body_error) = interp_statement(c, g, tree, frame, parts[2usize])
            if body_error != ok { ret (0usize, body_error) }
            if body_control == interp_control_return() {
                control = body_control
                break
            }
            if body_control == interp_control_break() { break }
            let one = normalized_integer(1usize, false)
            let (next, next_error) = evaluate_integer_binary(.PunctPlus, frame.values[counter], one, counter_type, counter_type)
            if next_error != ok { ret (0usize, interp_fail(c, module_index, node, "a range it cannot step")) }
            frame.values[counter] = next
        }
        frame.mark_count = frame.mark_count - 1usize
        frame.count = frame.marks[frame.mark_count]
        ret (control, ok)
    }
    if node.kind == .IfStmt || node.kind == .WhileStmt {
        var condition_index = 0usize
        var found_condition = false
        var arms: [2]usize = zero
        var arm_count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if !found_condition {
                    condition_index = parse.child_index_at(tree, at)
                    found_condition = true
                } else {
                    if arm_count == arms.len { ret (0usize, interp_fail(c, module_index, node, "an `if` of a shape it does not evaluate")) }
                    arms[arm_count] = parse.child_index_at(tree, at)
                    arm_count += 1usize
                }
            }
            at += 1usize
        }
        if !found_condition || arm_count == 0usize { ret (0usize, parse.InvalidSyntax) }
        while true {
            let (condition, condition_type, condition_error) = interp_expr(c, g, tree, frame, condition_index, interp_bool_type(module_index))
            if condition_error != ok { ret (0usize, condition_error) }
            if condition_type.kind != .Bool { ret (0usize, interp_fail(c, module_index, node, "a condition that is not a bool")) }
            if node.kind == .IfStmt {
                if condition.magnitude != 0usize {
                    let (taken_control, taken_error) = interp_statement(c, g, tree, frame, arms[0usize])
                    ret (taken_control, taken_error)
                }
                if arm_count == 2usize {
                    let (else_control, else_error) = interp_statement(c, g, tree, frame, arms[1usize])
                    ret (else_control, else_error)
                }
                ret (interp_control_next(), ok)
            }
            if condition.magnitude == 0usize { break }
            let (body_control, body_error) = interp_statement(c, g, tree, frame, arms[0usize])
            if body_error != ok { ret (0usize, body_error) }
            if body_control == interp_control_return() { ret (body_control, ok) }
            if body_control == interp_control_break() { break }
        }
        ret (interp_control_next(), ok)
    }
    ret (0usize, interp_fail(c, module_index, node, "a statement it does not evaluate"))
}

fn compound_base_operator(op: lex.Kind) -> lex.Kind {
    if op == .PunctAddAssign { ret .PunctPlus }
    if op == .PunctSubAssign { ret .PunctMinus }
    if op == .PunctMulAssign { ret .PunctStar }
    if op == .PunctDivAssign { ret .PunctSlash }
    if op == .PunctRemAssign { ret .PunctPercent }
    if op == .PunctAddWrapAssign { ret .PunctAddWrap }
    if op == .PunctSubWrapAssign { ret .PunctSubWrap }
    if op == .PunctMulWrapAssign { ret .PunctMulWrap }
    if op == .PunctShiftLeftAssign { ret .PunctShiftLeft }
    if op == .PunctShiftRightAssign { ret .PunctShiftRight }
    if op == .PunctBitAndAssign { ret .PunctAmp }
    if op == .PunctBitXorAssign { ret .PunctCaret }
    if op == .PunctBitOrAssign { ret .PunctPipe }
    ret .Invalid
}

fn evaluate_constant(c: *Checker, constant_index: usize) -> err {
    if constant_index >= c.constant_count { ret InvalidConstant }
    if c.constants[constant_index].state == 2u8 { ret ok }
    if c.constants[constant_index].state == 1u8 {
        let cyclic = c.constants[constant_index]
        record_failure_token(c, cyclic.module_index, cyclic.token, .ConstantDependencyCycle, cyclic.name, "")
        ret ConstantCycle
    }
    c.constants[constant_index].state = 1u8
    let outer_constant = c.interp_constant
    c.interp_constant = c.constants[constant_index].name
    let (value, actual_type, value_error) = evaluate_constant_expr(c, c.constants[constant_index].expression, c.constants[constant_index].ty)
    c.interp_constant = outer_constant
    // Put off rather than failed (D222): back to unevaluated, and whoever asked before
    // the signatures exist -- a type, another declaration -- reports it.
    if value_error == ComptimeDeferred { c.constants[constant_index].state = 0u8 }
    if value_error != ok { ret value_error }
    var final_type = c.constants[constant_index].ty
    if final_type.kind == .Invalid {
        if actual_type.kind == .UntypedInteger { ret MissingContext }
        // A bool constant (D222): `true`, a comparison, a call, or `&&`/`||`/`!` of those.
        if actual_type.kind != .Integer && actual_type.kind != .Bool { ret InvalidConstant }
        final_type = actual_type
    } else {
        if final_type.kind != .Integer && final_type.kind != .Bool { ret Unsupported }
        if actual_type.kind != .UntypedInteger && !type_equal(c, actual_type, final_type) { ret mismatch(c, final_type, actual_type) }
        if actual_type.kind == .UntypedInteger && final_type.kind == .Bool { ret TypeMismatch }
    }
    if final_type.kind == .Integer && !integer_representable(value, final_type) { ret ConstantOverflow }
    c.constants[constant_index].ty = final_type
    c.constants[constant_index].value = value
    c.constants[constant_index].state = 2u8
    ret ok
}

// The type is required rather than inferred: a static needs a size before any body is checked,
// and section 5 says the initialiser is compile-time, not a shape to read a type from.
fn collect_global_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    if c.global_count == c.globals.len { ret Capacity }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    var declared_type = invalid_type()
    var expression_index = 0usize
    var has_expression = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if is_type_node(child.kind) {
                let (resolved_type, type_error) = type_from_node(c, r, g, tree, module_index, child)
                if type_error != ok { ret type_error }
                declared_type = resolved_type
            } else {
                expression_index = child_index
                has_expression = true
            }
        }
        at += 1usize
    }
    if declared_type.kind == .Invalid {
        record_failure(c, module_index, node, .NotAType, name, "")
        ret InvalidType
    }
    var copied_expression = 0usize
    if has_expression {
        let (copied, expression_error) = copy_constant_expr(c, g, tree, module_index, expression_index)
        if expression_error != ok { ret expression_error }
        copied_expression = copied
    }
    c.globals[c.global_count] = Global { name: name, module_index: module_index, ty: declared_type, expression: copied_expression, has_expression: has_expression, token: c.tokens[usize(node.token_start)], nir_index: 0usize }
    c.global_count += 1usize
    ret ok
}

fn collect_constants(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.constants_ready = false
    var module_index = 0usize
    while module_index < g.count {
        var tree: parse.Tree = zero
        try graph.parse_module(g, module_index, &tree)
        try tokenize_module(c, g, module_index)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .ConstDecl { try collect_constant_declaration(c, r, g, &tree, module_index, node) }
            if node.top_level && node.kind == .VarDecl { try collect_global_declaration(c, r, g, &tree, module_index, node) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    var constant_index = 0usize
    while constant_index < c.constant_count {
        // A constant that reaches a call, directly or through another constant, waits
        // for the signatures (D218, D222); the rest are settled now.
        let early_error = evaluate_constant(c, constant_index)
        if early_error != ok && early_error != ComptimeDeferred { ret early_error }
        constant_index += 1usize
    }
    c.constants_ready = true
    ret ok
}

fn find_local(c: *Checker, name: str) -> (usize, bool) {
    var at = c.local_count
    while at > 0usize {
        at = at - 1usize
        if same(c.locals[at].name, name) { ret (at, true) }
    }
    ret (0usize, false)
}

fn add_local(c: *Checker, name: str, ty: Type, mutable: bool) -> err {
    if c.local_count == c.locals.len { ret Capacity }
    var state = 0u8
    if affine_kind(c, ty, 0usize) != 0u8 { state = 1u8 }
    var no_fields: []u8 = zero
    var no_elements_acquired: []usize = zero
    c.locals[c.local_count] = Local { name: name, ty: ty, mutable: mutable }
    c.resources[c.local_count] = Resource { state: state, acquired: 0usize, obligated: false, bound_err: 0usize, has_bound_err: false, fields: no_fields, elements_acquired: no_elements_acquired, borrowed: false, pinned: 0usize, pin_at: 0usize, view: false, mark_arena: "", region: 0usize, view_of: 0usize, dangling: 0u8, frame_borrow: 0usize, lent_to: 0usize, lent_at: 0usize, points_to: 0usize, points_to_field: "", slice_offset: 0usize, slice_offset_known: false }
    c.local_count += 1usize
    c.affine_answer_valid = false
    ret ok
}

fn numeric_literal_type(text: str, token: lex.Token) -> Type {
    let spelling = text[token.start..token.end]
    if token.kind == .Integer {
        if ends_with(spelling, "isize") { ret make_type(.Integer, "isize", 0usize) }
        if ends_with(spelling, "usize") { ret make_type(.Integer, "usize", 0usize) }
        if ends_with(spelling, "i64") { ret make_type(.Integer, "i64", 0usize) }
        if ends_with(spelling, "i32") { ret make_type(.Integer, "i32", 0usize) }
        if ends_with(spelling, "i16") { ret make_type(.Integer, "i16", 0usize) }
        if ends_with(spelling, "i8") { ret make_type(.Integer, "i8", 0usize) }
        if ends_with(spelling, "u64") { ret make_type(.Integer, "u64", 0usize) }
        if ends_with(spelling, "u32") { ret make_type(.Integer, "u32", 0usize) }
        if ends_with(spelling, "u16") { ret make_type(.Integer, "u16", 0usize) }
        if ends_with(spelling, "u8") { ret make_type(.Integer, "u8", 0usize) }
        ret make_type(.UntypedInteger, "", 0usize)
    }
    if ends_with(spelling, "bf16") { ret make_type(.Float, "bf16", 0usize) }
    if ends_with(spelling, "f64") { ret make_type(.Float, "f64", 0usize) }
    if ends_with(spelling, "f32") { ret make_type(.Float, "f32", 0usize) }
    if ends_with(spelling, "f16") { ret make_type(.Float, "f16", 0usize) }
    ret make_type(.UntypedFloat, "", 0usize)
}

fn literal_type(c: *Checker, text: str, node: syntax.Node) -> Type {
    let token = c.tokens[usize(node.token_start)]
    if token.kind == .Integer || token.kind == .Float { ret numeric_literal_type(text, token) }
    if token.kind == .KwTrue || token.kind == .KwFalse { ret make_type(.Bool, "bool", 0usize) }
    if token.kind == .String || token.kind == .RawString { ret make_type(.String, "str", 0usize) }
    if token.kind == .Character { ret make_type(.Integer, "u8", 0usize) }
    if token.kind == .KwOk { ret make_type(.Err, "err", 0usize) }
    ret make_type(.Other, "", 0usize)
}

fn binary_operator(c: *Checker, tree: *parse.Tree, node: syntax.Node) -> lex.Kind {
    let end = usize(node.first_child) + usize(node.child_count)
    var left_end = usize(node.token_start)
    var right_start = usize(node.token_end)
    var found_left = false
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if !found_left {
                left_end = usize(tree.nodes[parse.child_index_at(tree, at)].token_end)
                found_left = true
            } else {
                right_start = usize(tree.nodes[parse.child_index_at(tree, at)].token_start)
                break
            }
        }
        at += 1usize
    }
    at = left_end
    while at < right_start {
        let kind = c.tokens[at].kind
        if kind != .Newline { ret kind }
        at += 1usize
    }
    ret .Invalid
}

fn is_comparison(kind: lex.Kind) -> bool {
    ret kind == .PunctEqEq || kind == .PunctBangEq || kind == .PunctLt || kind == .PunctLtEq || kind == .PunctGt || kind == .PunctGtEq
}

fn is_equality(kind: lex.Kind) -> bool {
    ret kind == .PunctEqEq || kind == .PunctBangEq
}

fn is_shift(kind: lex.Kind) -> bool {
    ret kind == .PunctShiftLeft || kind == .PunctShiftRight
}

fn is_logical(kind: lex.Kind) -> bool {
    ret kind == .PunctAndAnd || kind == .PunctOrOr
}

fn is_integer_operator(kind: lex.Kind) -> bool {
    ret kind == .PunctPercent || kind == .PunctAmp || kind == .PunctCaret || kind == .PunctPipe || kind == .PunctAddWrap || kind == .PunctSubWrap || kind == .PunctMulWrap
}

fn template_parameter(c: *Checker, function_index: usize, name: str) -> (usize, bool) {
    if function_index >= c.signature_function_count { ret (0usize, false) }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let index = function.first_comptime + at
        if index < c.comptime_parameter_count && same(c.comptime_parameters[index].name, name) { ret (index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn instance_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize) -> (GenericArgument, bool) {
    var empty: GenericArgument = zero
    if function_index >= c.signature_function_count { ret (empty, false) }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret (empty, false) }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret (empty, false) }
    let index = first_argument + offset
    if index >= c.generic_argument_count || !c.generic_arguments[index].set { ret (empty, false) }
    ret (c.generic_arguments[index], true)
}

fn evaluate_bound_expression(c: *Checker, function_index: usize, first_argument: usize, expression_index: usize, expected: Type) -> (IntegerValue, Type, err) {
    if expression_index >= c.constant_expr_count { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
    let expression = c.constant_exprs[expression_index]
    if expression.kind == .ArrayLen {
        let (subject, subject_error) = substitute_type(c, function_index, first_argument, expression.ty)
        if subject_error != ok { ret (normalized_integer(0usize, false), invalid_type(), subject_error) }
        let (length, length_error) = length_of_subject(c, subject)
        if length_error != ok { ret (normalized_integer(0usize, false), invalid_type(), length_error) }
        let (contextual_type, context_error) = apply_context(c, make_type(.Integer, "usize", expression.module_index), expected)
        if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
        ret (normalized_integer(length, false), contextual_type, ok)
    }
    if expression.kind == .Literal {
        let (contextual_type, context_error) = apply_context(c, expression.ty, expected)
        if context_error != ok || (contextual_type.kind == .Integer && !integer_representable(expression.value, contextual_type)) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (expression.value, contextual_type, ok)
    }
    if expression.kind == .Name {
        var parameter_index = 0usize
        var parameter_found = false
        if expression.module_index == c.functions[function_index].module_index {
            (parameter_index, parameter_found) = template_parameter(c, function_index, expression.name)
        }
        if parameter_found {
            let parameter = c.comptime_parameters[parameter_index]
            if parameter.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
            let (argument, argument_found) = instance_argument(c, function_index, first_argument, parameter_index)
            if !argument_found { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            let (contextual_type, context_error) = apply_context(c, parameter.ty, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            ret (normalized_integer(argument.value, false), contextual_type, ok)
        }
        let (constant_index, found) = find_constant(c, expression.module_index, expression.name)
        if !found { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let dependency_error = evaluate_constant(c, constant_index)
        if dependency_error != ok { ret (normalized_integer(0usize, false), invalid_type(), dependency_error) }
        let (contextual_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
        if context_error != ok || !integer_representable(c.constants[constant_index].value, contextual_type) { ret (normalized_integer(0usize, false), invalid_type(), TypeMismatch) }
        ret (c.constants[constant_index].value, contextual_type, ok)
    }
    if expression.kind == .Unary {
        var operand_expected = expected
        if expression.op == .PunctMinus { operand_expected = invalid_type() }
        let (operand, operand_type, operand_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left, operand_expected)
        if operand_error != ok { ret (normalized_integer(0usize, false), invalid_type(), operand_error) }
        if expression.op == .PunctMinus {
            if unsigned_integer_type(operand_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
            let result = normalized_integer(operand.magnitude, !operand.negative)
            let (result_type, context_error) = apply_context(c, operand_type, expected)
            if context_error != ok { ret (normalized_integer(0usize, false), invalid_type(), context_error) }
            if result_type.kind == .Integer && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
            ret (result, result_type, ok)
        }
        if expression.op == .PunctTilde {
            let width = integer_width(operand_type)
            ret (integer_from_bits(integer_mask(width) - integer_bits(operand, width), operand_type), operand_type, ok)
        }
        ret (normalized_integer(0usize, false), invalid_type(), Unsupported)
    }
    if expression.kind == .Binary {
        if !expression.has_right { ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant) }
        let (left, left_type, left_error) = evaluate_bound_expression(c, function_index, first_argument, expression.left, expected)
        if left_error != ok { ret (normalized_integer(0usize, false), invalid_type(), left_error) }
        var right_expected = left_type
        if is_shift(expression.op) { right_expected = invalid_type() }
        let (right, raw_right_type, right_error) = evaluate_bound_expression(c, function_index, first_argument, expression.right, right_expected)
        if right_error != ok { ret (normalized_integer(0usize, false), invalid_type(), right_error) }
        var right_type = raw_right_type
        var result_type = left_type
        if is_shift(expression.op) {
            if right_type.kind == .UntypedInteger { right_type = make_type(.Integer, "u32", expression.module_index) }
            if result_type.kind != .Integer { ret (normalized_integer(0usize, false), invalid_type(), MissingContext) }
            if right_type.kind != .Integer || !unsigned_integer_type(right_type) { ret (normalized_integer(0usize, false), invalid_type(), InvalidOperator) }
        } else {
            let (resolved_type, type_error) = constant_result_type(c, left_type, right_type)
            if type_error != ok { ret (normalized_integer(0usize, false), invalid_type(), type_error) }
            result_type = resolved_type
            if (expression.op == .PunctAmp || expression.op == .PunctCaret || expression.op == .PunctPipe || expression.op == .PunctAddWrap || expression.op == .PunctSubWrap || expression.op == .PunctMulWrap) && result_type.kind != .Integer {
                ret (normalized_integer(0usize, false), invalid_type(), MissingContext)
            }
        }
        if result_type.kind == .Integer && (!integer_representable(left, result_type) || !integer_representable(right, right_type)) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        let (result, result_error) = evaluate_integer_binary(expression.op, left, right, result_type, right_type)
        if result_error != ok { ret (normalized_integer(0usize, false), invalid_type(), result_error) }
        if result_type.kind == .Integer && expression.op != .PunctAddWrap && expression.op != .PunctSubWrap && expression.op != .PunctMulWrap && !integer_representable(result, result_type) { ret (normalized_integer(0usize, false), invalid_type(), ConstantOverflow) }
        ret (result, result_type, ok)
    }
    ret (normalized_integer(0usize, false), invalid_type(), InvalidConstant)
}

fn substitute_type(c: *Checker, function_index: usize, first_argument: usize, ty: Type) -> (Type, err) {
    if ty.kind == .TypeParameter {
        if !ty.has_element { ret (invalid_type(), InvalidType) }
        let (argument, found) = instance_argument(c, function_index, first_argument, ty.element)
        if !found { ret (invalid_type(), MissingContext) }
        // A `Field` parameter in a type position is `FIELD.ty`, and the type the bound field
        // has is what the declaration's placeholder stood for. A `Member` has no type among its
        // members, so there is nothing for one to stand for and it is not accepted here.
        if argument.kind == .Field { ret (argument.ty, ok) }
        if argument.kind != .Type { ret (invalid_type(), MissingContext) }
        if ty.has_length {
            let (derived, derived_error) = derived_from_subject(c, true, argument.ty)
            ret (derived, derived_error)
        }
        ret (argument.ty, ok)
    }
    if ty.kind == .Named && ty.has_element {
        if ty.element >= c.aggregate_count || !c.aggregates[ty.element].instance { ret (invalid_type(), InvalidType) }
        let source = c.aggregates[ty.element]
        let template = c.aggregates[source.template_index]
        if c.generic_argument_count + template.comptime_count > c.generic_arguments.len { ret (invalid_type(), Capacity) }
        // Claimed whole before any argument is substituted, for the same reason as in
        // `substitute_aggregate_type`: a nested instance would otherwise take these slots.
        let aggregate_first = c.generic_argument_count
        c.generic_argument_count += template.comptime_count
        var argument_at = 0usize
        while argument_at < template.comptime_count {
            let source_argument = c.generic_arguments[source.first_argument + argument_at]
            var aggregate_argument_value = source_argument
            if source_argument.kind == .Type {
                let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source_argument.ty)
                if specialize_error != ok { ret (invalid_type(), specialize_error) }
                aggregate_argument_value.ty = specialized
            } else {
                if source_argument.symbolic {
                    let (value, value_type, value_error) = evaluate_bound_expression(c, function_index, first_argument, source_argument.expression, make_type(.Integer, "usize", template.module_index))
                    if value_error != ok || value.negative || (value_type.kind != .UntypedInteger && (value_type.kind != .Integer || !same(value_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
                    aggregate_argument_value.value = value.magnitude
                    aggregate_argument_value.symbolic = false
                }
            }
            c.generic_arguments[aggregate_first + argument_at] = aggregate_argument_value
            argument_at += 1usize
        }
        let (aggregate_instance, aggregate_error) = instantiate_aggregate(c, source.template_index, aggregate_first)
        if aggregate_error != ok { ret (invalid_type(), aggregate_error) }
        var result = ty
        result.element = aggregate_instance
        ret (result, ok)
    }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), InvalidType) }
        let (element, element_error) = substitute_type(c, function_index, first_argument, c.types[ty.element])
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = ty
        result.element = stored_element
        if ty.kind == .Array && !ty.has_length {
            let (length, length_type, length_error) = evaluate_bound_expression(c, function_index, first_argument, ty.array_length, make_type(.Integer, "usize", c.functions[function_index].module_index))
            if length_error != ok { ret (invalid_type(), length_error) }
            if length.negative || (length_type.kind != .UntypedInteger && (length_type.kind != .Integer || !same(length_type.name, "usize"))) { ret (invalid_type(), TypeMismatch) }
            result.array_length = length.magnitude
            result.has_length = true
        }
        ret (result, ok)
    }
    if ty.kind == .Function {
        let (signature, has_signature) = function_signature_of(c, ty)
        if !has_signature { ret (invalid_type(), InvalidType) }
        var parameters: [16]Type = zero
        var returns: [4]Type = zero
        if signature.parameter_count > parameters.len || signature.return_count > returns.len { ret (invalid_type(), Capacity) }
        var at = 0usize
        while at < signature.parameter_count {
            let (source, has_source) = function_signature_parameter(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            parameters[at] = specialized
            at += 1usize
        }
        at = 0usize
        while at < signature.return_count {
            let (source, has_source) = function_signature_return(c, signature, at)
            if !has_source { ret (invalid_type(), InvalidType) }
            let (specialized, specialize_error) = substitute_type(c, function_index, first_argument, source)
            if specialize_error != ok { ret (invalid_type(), specialize_error) }
            returns[at] = specialized
            at += 1usize
        }
        let (result, build_error) = build_function_type(c, parameters[..signature.parameter_count], returns[..signature.return_count], ty.module_index)
        ret (result, build_error)
    }
    ret (ty, ok)
}

// A comptime `str` argument must be a string literal. Nothing else has a value at the
// point the instance is chosen, and the whole reason the parameter is comptime is that
// the body -- or, for `format`, the expansion -- reads it while compiling.
fn bind_text_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize, spelling: str) -> err {
    if function_index >= c.signature_function_count { ret InvalidType }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret InvalidType }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret InvalidType }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count { ret Capacity }
    if c.generic_arguments[argument_index].set {
        if c.generic_arguments[argument_index].kind != .Str { ret TypeMismatch }
        if !same(c.generic_arguments[argument_index].text, spelling) { ret TypeMismatch }
        ret ok
    }
    c.generic_arguments[argument_index].kind = .Str
    c.generic_arguments[argument_index].text = spelling
    c.generic_arguments[argument_index].symbolic = false
    c.generic_arguments[argument_index].set = true
    ret ok
}

fn bind_inferred_argument(c: *Checker, function_index: usize, first_argument: usize, parameter_index: usize, ty: Type, value: usize, kind: ComptimeKind) -> err {
    if function_index >= c.signature_function_count { ret InvalidType }
    let function = c.function_generics[function_index]
    if parameter_index < function.first_comptime { ret InvalidType }
    let offset = parameter_index - function.first_comptime
    if offset >= function.comptime_count { ret InvalidType }
    let argument_index = first_argument + offset
    if argument_index >= c.generic_argument_count { ret Capacity }
    if c.generic_arguments[argument_index].set {
        if c.generic_arguments[argument_index].kind != kind { ret TypeMismatch }
        if kind == .Type {
            if !type_equal(c, c.generic_arguments[argument_index].ty, ty) { ret TypeMismatch }
        } else {
            if c.generic_arguments[argument_index].value != value { ret TypeMismatch }
        }
        ret ok
    }
    c.generic_arguments[argument_index].kind = kind
    c.generic_arguments[argument_index].ty = ty
    c.generic_arguments[argument_index].value = value
    c.generic_arguments[argument_index].set = true
    ret ok
}

fn infer_comptime_type(c: *Checker, function_index: usize, first_argument: usize, formal: Type, actual: Type) -> err {
    if formal.kind == .TypeParameter {
        if is_untyped(actual) || actual.kind == .Invalid || actual.kind == .Other { ret ok }
        if !formal.has_element { ret InvalidType }
        // `meta.element_type[V]()` as a parameter type names a part of `V`, not `V`: nothing
        // to infer from the argument.
        if formal.has_length { ret ok }
        // A `FIELD.ty` parameter is a `TypeParameter` standing for a comptime `Field`, not for a
        // type parameter of its own, and there is nothing to infer: the field was named at the
        // call and its type follows from it. Inferring here would rebind `FIELD` to whatever the
        // argument happened to be, losing the field it names.
        if formal.element < c.comptime_parameter_count && c.comptime_parameters[formal.element].kind != .Type { ret ok }
        ret bind_inferred_argument(c, function_index, first_argument, formal.element, actual, 0usize, .Type)
    }
    if formal.kind != actual.kind { ret ok }
    if formal.kind == .Array && !formal.has_length && actual.has_length && formal.array_length < c.constant_expr_count {
        let expression = c.constant_exprs[formal.array_length]
        if expression.kind == .Name {
            var parameter_index = 0usize
            var parameter_found = false
            if expression.module_index == c.functions[function_index].module_index {
                (parameter_index, parameter_found) = template_parameter(c, function_index, expression.name)
            }
            if parameter_found && c.comptime_parameters[parameter_index].kind == .Integer {
                try bind_inferred_argument(c, function_index, first_argument, parameter_index, invalid_type(), actual.array_length, .Integer)
            }
        }
    }
    if (formal.kind == .Pointer || formal.kind == .Slice || formal.kind == .Array) && formal.has_element && actual.has_element {
        if formal.element >= c.type_count || actual.element >= c.type_count { ret InvalidType }
        ret infer_comptime_type(c, function_index, first_argument, c.types[formal.element], c.types[actual.element])
    }
    ret ok
}

fn generic_arguments_equal(c: *Checker, function_index: usize, first: usize, second: usize) -> bool {
    if function_index >= c.signature_function_count { ret false }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let left = c.generic_arguments[first + at]
        let right = c.generic_arguments[second + at]
        if !left.set || !right.set || left.kind != right.kind { ret false }
        if left.kind == .Type {
            if !type_equal(c, left.ty, right.ty) { ret false }
        } else {
            if left.kind == .Str || left.kind == .Array {
                if !same(left.text, right.text) { ret false }
            } else {
                if left.value != right.value { ret false }
            }
        }
        at += 1usize
    }
    ret true
}

// A NIR function is identified by its owning module, its name and this
// discriminator, so the discriminator has to separate every instance a module
// owns under one name -- including instances of same-named templates declared in
// different modules, such as `list.init` and `heap.init` used by one consumer.
fn owner_instance_count(c: *Checker, owner_module_index: usize, name: str) -> usize {
    var count = 0usize
    var at = c.signature_function_count
    while at < c.function_count {
        let candidate = c.function_generics[at]
        if candidate.instance && c.functions[at].owner_module_index == owner_module_index && same(c.functions[at].name, name) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn instance_owner(c: *Checker, module_index: usize) -> usize {
    if c.active_owner_set { ret c.active_owner_module }
    ret module_index
}

fn find_function_instance(c: *Checker, owner_module_index: usize, template_index: usize, first_argument: usize) -> (usize, bool) {
    var at = c.signature_function_count
    while at < c.function_count {
        let candidate = c.function_generics[at]
        if candidate.instance && candidate.template_index == template_index && c.functions[at].owner_module_index == owner_module_index && generic_arguments_equal(c, template_index, candidate.first_argument, first_argument) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn function_arguments_concrete(c: *Checker, function_index: usize, first_argument: usize) -> bool {
    if function_index >= c.signature_function_count { ret false }
    let function = c.function_generics[function_index]
    var at = 0usize
    while at < function.comptime_count {
        let argument_index = first_argument + at
        if argument_index >= c.generic_argument_count { ret false }
        let argument = c.generic_arguments[argument_index]
        if !argument.set || argument.symbolic { ret false }
        if argument.kind == .Type && type_depends_on_comptime(c, argument.ty) { ret false }
        at += 1usize
    }
    ret true
}

fn instantiate_function(c: *Checker, owner_module_index: usize, template_index: usize, first_argument: usize) -> (usize, err) {
    let (cached, found) = find_function_instance(c, owner_module_index, template_index, first_argument)
    if found { ret (cached, ok) }
    if template_index >= c.signature_function_count || c.function_count == c.functions.len { ret (0usize, Capacity) }
    let template = c.functions[template_index]
    var instance: Function = zero
    instance.name = template.name
    instance.module_index = template.module_index
    instance.owner_module_index = owner_module_index
    // The instance is code in the instantiating module, but its body is still the
    // template's source, so it keeps the template's source range.
    instance.source_start = template.source_start
    instance.source_end = template.source_end
    instance.instance_id = owner_instance_count(c, owner_module_index, template.name) + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = template.parameter_count
    instance.first_return = c.return_type_count
    instance.return_count = template.return_count
    instance.generic = !function_arguments_concrete(c, template_index, first_argument)
    instance.import_library = template.import_library
    instance.import_symbol = template.import_symbol
    var generic: FunctionGeneric = zero
    generic.first_comptime = c.function_generics[template_index].first_comptime
    generic.comptime_count = c.function_generics[template_index].comptime_count
    generic.template_index = template_index
    generic.first_argument = first_argument
    generic.instance = true
    var at = 0usize
    while at < template.parameter_count {
        if c.parameter_count == c.parameters.len { ret (0usize, Capacity) }
        let source = c.parameters[template.first_parameter + at]
        let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, source.ty)
        if specialize_error != ok { ret (0usize, specialize_error) }
        c.parameters[c.parameter_count] = Parameter { name: source.name, ty: specialized, own: source.own }
        c.parameter_count += 1usize
        at += 1usize
    }
    at = 0usize
    while at < template.return_count {
        let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, c.return_types[template.first_return + at])
        if specialize_error != ok { ret (0usize, specialize_error) }
        let store_error = store_return_type(c, specialized)
        if store_error != ok { ret (0usize, store_error) }
        at += 1usize
    }
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

fn bracket_function(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (usize, err) {
    let (base_index, found_base) = first_node_child(tree, receiver)
    if !found_base { ret (0usize, parse.InvalidSyntax) }
    let base = tree.nodes[base_index]
    if base.kind == .NameExpr {
        let token = c.tokens[usize(base.token_start)]
        let name = g.modules[module_index].text[token.start..token.end]
        let (function_index, found) = find_function(c, module_index, name)
        if !found { ret (0usize, UnknownCallable) }
        ret (function_index, ok)
    }
    if base.kind == .FieldExpr {
        let (function_index, found) = find_qualified_function(c, g, tree, module_index, base)
        if !found { ret (0usize, UnknownCallable) }
        ret (function_index, ok)
    }
    ret (0usize, Unsupported)
}

fn specialize_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, call: syntax.Node, receiver: syntax.Node, template_index: usize) -> (usize, err) {
    if template_index >= c.signature_function_count { ret (0usize, UnknownCallable) }
    let template = c.functions[template_index]
    let generic = c.function_generics[template_index]
    if !template.generic || generic.comptime_count == 0usize { ret (0usize, Unsupported) }
    if c.generic_argument_count + generic.comptime_count > c.generic_arguments.len { ret (0usize, Capacity) }
    let first_argument = c.generic_argument_count
    var at = 0usize
    while at < generic.comptime_count {
        let parameter = c.comptime_parameters[generic.first_comptime + at]
        c.generic_arguments[c.generic_argument_count] = GenericArgument { kind: parameter.kind, ty: invalid_type(), value: 0usize, text: "", expression: 0usize, owner: 0usize, symbolic: false, set: false }
        c.generic_argument_count += 1usize
        at += 1usize
    }
    if receiver.kind == .BracketPostfix {
        let end = usize(receiver.first_child) + usize(receiver.child_count)
        var child_position = 0usize
        at = usize(receiver.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if child_position > 0usize {
                    let argument_position = child_position - 1usize
                    if argument_position >= generic.comptime_count { ret (0usize, ArgumentCount) }
                    let parameter = c.comptime_parameters[generic.first_comptime + argument_position]
                    let node_index = parse.child_index_at(tree, at)
                    if parameter.kind == .Field || parameter.kind == .Member {
                        // A comptime `Field` has no way to be written down: it comes from
                        // `meta.fields`, so the argument is always a name that already holds
                        // one -- a loop's binding, or this caller's own parameter.
                        let argument_node = tree.nodes[node_index]
                        if argument_node.kind != .NameExpr { ret (0usize, TypeMismatch) }
                        let argument_token = c.tokens[usize(argument_node.token_start)]
                        if argument_token.kind != .Identifier { ret (0usize, TypeMismatch) }
                        let (bound, found_bound) = find_comptime_binding(c, g.modules[module_index].text[argument_token.start..argument_token.end])
                        if !found_bound || bound.kind != parameter.kind { ret (0usize, TypeMismatch) }
                        let argument_index = first_argument + argument_position
                        c.generic_arguments[argument_index] = bound
                        c.generic_arguments[argument_index].set = true
                    } else {
                    if parameter.kind == .Type {
                        let (ty, type_error) = comptime_type(c, g, tree, module_index, node_index)
                        if type_error != ok { ret (0usize, type_error) }
                        let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, ty, 0usize, .Type)
                        if bind_error != ok { ret (0usize, bind_error) }
                    } else {
                    if parameter.kind == .Array {
                        let bind_error = bind_array_argument(c, g, tree, module_index, template_index, first_argument, generic.first_comptime + argument_position, node_index)
                        if bind_error != ok { ret (0usize, bind_error) }
                    } else {
                    if parameter.kind == .Str {
                        let argument_node = tree.nodes[node_index]
                        if argument_node.kind != .LiteralExpr { ret (0usize, TypeMismatch) }
                        let literal = c.tokens[usize(argument_node.token_start)]
                        if literal.kind != .String && literal.kind != .RawString { ret (0usize, TypeMismatch) }
                        let spelling = g.modules[module_index].text[literal.start..literal.end]
                        let bind_error = bind_text_argument(c, template_index, first_argument, generic.first_comptime + argument_position, spelling)
                        if bind_error != ok { ret (0usize, bind_error) }
                    } else {
                    if parameter.kind == .Function {
                        let argument_node = tree.nodes[node_index]
                        var selected = c.function_count
                        if argument_node.kind == .NameExpr {
                            let argument_token = c.tokens[usize(argument_node.token_start)]
                            let argument_name = g.modules[module_index].text[argument_token.start..argument_token.end]
                            let (outer_index, has_outer) = active_comptime_parameter(c, argument_name)
                            if has_outer && c.comptime_parameters[outer_index].kind == .Function {
                                let (outer, has_argument) = active_argument(c, outer_index)
                                if has_argument {
                                    let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, outer.ty, outer.value, .Function)
                                    if bind_error != ok { ret (0usize, bind_error) }
                                } else {
                                    if !c.generic_declaration { ret (0usize, MissingContext) }
                                    let argument_index = first_argument + argument_position
                                    c.generic_arguments[argument_index].kind = .Function
                                    c.generic_arguments[argument_index].ty = c.comptime_parameters[outer_index].ty
                                    c.generic_arguments[argument_index].value = outer_index
                                    c.generic_arguments[argument_index].symbolic = true
                                    c.generic_arguments[argument_index].set = true
                                }
                            } else {
                                let (found_index, found) = find_function(c, module_index, argument_name)
                                if found { selected = found_index }
                            }
                        }
                        if argument_node.kind == .FieldExpr {
                            let (found_index, found) = find_qualified_function(c, g, tree, module_index, argument_node)
                            if found { selected = found_index }
                        }
                        if selected < c.function_count {
                            let chosen = c.functions[selected]
                            if chosen.generic || chosen.intrinsic || chosen.external { ret (0usize, TypeMismatch) }
                            let (chosen_type, chosen_error) = function_pointer_type(c, chosen, module_index)
                            if chosen_error != ok { ret (0usize, chosen_error) }
                            let (required_type, required_error) = substitute_type(c, template_index, first_argument, parameter.ty)
                            if required_error != ok || !type_equal(c, chosen_type, required_type) { ret (0usize, TypeMismatch) }
                            let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, chosen_type, selected, .Function)
                            if bind_error != ok { ret (0usize, bind_error) }
                        } else {
                            let argument_index = first_argument + argument_position
                            if !c.generic_arguments[argument_index].set { ret (0usize, UnknownCallable) }
                        }
                    } else {
                        let (value, value_error) = array_length_value(c, g, tree, module_index, node_index)
                        if value_error == ok {
                            let bind_error = bind_inferred_argument(c, template_index, first_argument, generic.first_comptime + argument_position, invalid_type(), value, .Integer)
                            if bind_error != ok { ret (0usize, bind_error) }
                        } else {
                            if !c.generic_declaration { ret (0usize, InvalidType) }
                            let (expression, expression_error) = copy_constant_expr(c, g, tree, module_index, node_index)
                            if expression_error != ok { ret (0usize, InvalidType) }
                            let argument_index = first_argument + argument_position
                            c.generic_arguments[argument_index].expression = expression
                            c.generic_arguments[argument_index].symbolic = true
                            c.generic_arguments[argument_index].set = true
                        }
                    }
                    }
                    }
                    }
                    }
                }
                child_position += 1usize
            }
            at += 1usize
        }
    }
    var runtime_count = 0usize
    let call_end = usize(call.first_child) + usize(call.child_count)
    at = usize(call.first_child)
    while at < call_end {
        if parse.child_is_node_at(tree, at) { runtime_count += 1usize }
        at += 1usize
    }
    if runtime_count == 0usize || runtime_count - 1usize != template.parameter_count { ret (0usize, ArgumentCount) }
    var runtime_position = 0usize
    var dependent_runtime = false
    at = usize(call.first_child)
    while at < call_end {
        if parse.child_is_node_at(tree, at) {
            if runtime_position > 0usize {
                let formal = c.parameters[template.first_parameter + runtime_position - 1usize].ty
                var expected = invalid_type()
                let (specialized, specialize_error) = substitute_type(c, template_index, first_argument, formal)
                if specialize_error == ok { expected = specialized }
                if specialize_error != ok && specialize_error != MissingContext { ret (0usize, specialize_error) }
                let (actual, actual_error) = check_expr(c, g, tree, module_index, parse.child_index_at(tree, at), expected)
                if actual_error != ok { ret (0usize, actual_error) }
                if type_depends_on_comptime(c, actual) { dependent_runtime = true }
                let inference_error = infer_comptime_type(c, template_index, first_argument, formal, actual)
                if inference_error != ok { ret (0usize, inference_error) }
            }
            runtime_position += 1usize
        }
        at += 1usize
    }
    at = 0usize
    while at < generic.comptime_count {
        if !c.generic_arguments[first_argument + at].set && (!c.generic_declaration || !dependent_runtime) {
            let parameter = c.comptime_parameters[generic.first_comptime + at]
            record_failure(c, module_index, call, .GenericInference, parameter.name, "")
            ret (0usize, MissingContext)
        }
        at += 1usize
    }
    if c.generic_declaration && !function_arguments_concrete(c, template_index, first_argument) { ret (template_index, ok) }
    let (instance_index, instance_error) = instantiate_function(c, instance_owner(c, module_index), template_index, first_argument)
    if instance_error == ok {
        record_explain_instance(c, module_index, call, template_index, instance_index, first_argument, generic.comptime_count)
        note_instance_site(c, instance_index, module_index, call)
    }
    ret (instance_index, instance_error)
}

type ExprCacheEntry = struct {
    generation: usize,
    token_start: usize,
    token_end: usize,
    expected: Type,
    result: Type,
}

type CallCacheEntry = struct {
    generation: usize,
    token_start: usize,
    token_end: usize,
    info: CallInfo,
}

type CallInfo = struct {
    function: Function,
    cast: Type,
    is_cast: bool,
    // `unreachable()` / `unreachable("why")`: section 11's one always-on builtin. It is
    // a trap of kind `unreachable` with the literal as its values, and nothing follows it.
    is_unreachable: bool,
    // `u8.trunc(x)`: section 4's meant truncation, a cast that keeps the low bits in
    // every build mode and is never a `narrow` check.
    truncating: bool,
    alloc_return: Type,
    alloc_arena: Type,
    mem_alloc: bool,
    // `os.thread_create[Ctx]`. The context type is bound at the call and checked
    // against the entry point here; once lowered both are pointers and it is gone.
    thread_create: bool,
    thread_context: Type,
    thread_entry: Type,
    // `e.meta`'s scalar reflection: which question was asked and the answer, both
    // settled here. Section 9 keeps reflection entirely at compile time, so what
    // reaches lowering is a constant and never the type itself.
    meta_query: MetaQuery,
    meta_value: usize,
    meta_name: str,
    meta_result: Type,
    mem_cast: bool,
    mem_bitcast: bool,
    mem_address: bool,
    // `math.sqrt[F](x)`: the one `e.math` function that is an instruction rather than source,
    // because a correctly rounded square root is the hardware's to give and no software's to
    // approximate. `cast` carries `F`, as it does for the three above.
    math_sqrt: bool,
    // `os.dlsym[F]`. The call that is made is the variant's own address lookup; what this flag
    // changes is only the type of its first result, which is `cast` as it is for the three above.
    dl_symbol: bool,
    formatter: bool,
    formatter_arena: bool,
    formatter_verbs: usize,
    formatter_spelling: str,
    protocol_pending: bool,
    protocol_builtin: ProtocolBuiltin,
    protocol_type: Type,
    indirect: bool,
    indirect_type: Type,
    // Section 8. `T` is inferred from the pointer, so the later arguments are checked
    // against what the first one gave -- as `thread_create` does with its context.
    atomic_op: AtomicOp,
    atomic_element: Type,
    atomic_success: Ordering,
    atomic_failure: Ordering,
    // `meta.get` / `meta.set`: the field is settled here and what reaches lowering is
    // one load or store at its offset.
    meta_writes: bool,
    meta_field: GenericArgument,
    meta_subject: Type,
    meta_access: bool,
}

// The thirteen `e.atomic` intrinsics. `None` is "this call is not one of them".
type AtomicOp = enum u8 {
    None,
    Init,
    Load,
    Store,
    Xchg,
    Cas,
    Add,
    Sub,
    And,
    Or,
    Xor,
    Min,
    Max,
    Fence,
}

// `lib/e/atomic.e`'s `Ordering`, plus `Dynamic` for one that is not a compile-time
// member. The two lists are one list: the values are that enum's, in its order.
type Ordering = enum u8 {
    Relaxed = 0,
    Acquire = 1,
    Release = 2,
    AcqRel = 3,
    SeqCst = 4,
    Dynamic = 5,
}

type AtomicInfo = struct {
    matched: bool,
    op: AtomicOp,
    function: Function,
}

// The compile-time questions that answer with a constant and emit nothing. Three of
// them are `e.meta`'s reflection; the last two are `e.mem`'s layout, which is the same
// shape -- a type in, a number out -- and so takes the same path.
type MetaQuery = enum u8 {
    None,
    Kind,
    ArrayLen,
    TypeName,
    SizeOf,
    AlignOf,
}

type MetaInfo = struct {
    matched: bool,
    query: MetaQuery,
    result: Type,
    value: usize,
    name: str,
    // Only the layout questions use this: their answer is not a constant this side of
    // lowering, so what travels is the type itself.
    subject: Type,
    // The subject was still a type parameter, so `value` is a placeholder and not an answer
    // (D136). A caller that wants to act on the answer has to know the difference; a caller
    // that only wants the result type does not.
    deferred: bool,
    function: Function,
}

type AllocInfo = struct {
    matched: bool,
    function: Function,
    return_type: Type,
    arena_type: Type,
}

type CastInfo = struct {
    matched: bool,
    function: Function,
    target: Type,
}

type BitcastInfo = struct {
    matched: bool,
    function: Function,
    target: Type,
}

type FormatterInfo = struct {
    matched: bool,
    function: Function,
    arena: bool,
    verbs: usize,
    spelling: str,
}

// The two `e.meta` questions that answer with a type rather than a number or a name.
// Both take one type and give back one of its parts, so both are a single step: no
// walking, and no aggregate is built.
//
// `element_type` is for an array or a slice. Section 9 also names a vector, which this
// compiler has no kind for yet; `str` is deliberately not one of them -- section 9 lists
// array, slice and vector, and a string is its own kind here.
fn derived_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver { ret (invalid_type(), InvalidType) }
    let receiver = tree.nodes[receiver_index]
    if receiver.kind != .BracketPostfix { ret (invalid_type(), InvalidType) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count != 2usize { ret (invalid_type(), InvalidType) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (invalid_type(), InvalidType) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.meta") { ret (invalid_type(), InvalidType) }
    var wants_element = false
    var matched = false
    if same(member, "element_type") {
        wants_element = true
        matched = true
    }
    if same(member, "backing_type") { matched = true }
    if !matched { ret (invalid_type(), InvalidType) }
    // The subject is itself a type expression, so one of these may name the other: the
    // element of an array of enums has a backing type of its own.
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (invalid_type(), subject_error) }
    let (answer, answer_error) = derived_from_subject(c, wants_element, subject)
    ret (answer, answer_error)
}

// The part of a type these two answer with, once the subject has been read. Shared, because
// the same question has two spellings: a call in an expression, and a call where a type is
// written.
fn derived_from_subject(c: *Checker, wants_element: bool, subject: Type) -> (Type, err) {
    // In a generic function's template body the subject is the parameter itself: `check_function`
    // checks that body once with no argument bound, and `check_instance` checks it again per
    // instance with the argument in place. There is no derived type to give in the first pass, so
    // the parameter stands for its own answer there and the second pass settles it -- the same
    // deferral `size_of` has always had, which is why that one worked inside a generic and these
    // did not.
    if subject.kind == .TypeParameter {
        // `element_type` of a parameter is a placeholder of its own: the same parameter with
        // `has_length` set, which `substitute_type` answers once the argument is bound. That is
        // how `fn splat[V: type](x: meta.element_type[V]())` keeps `x` as the lane type of `V`.
        var derived = subject
        if wants_element { derived.has_length = true }
        ret (derived, ok)
    }
    if wants_element {
        if vector_pending(c, subject) { ret (make_type(.TypeParameter, "", c.simd_module), ok) }
        var container = subject
        let (lanes, is_vector) = vector_lanes(c, subject)
        if is_vector { container = lanes }
        if container.kind != .Array && container.kind != .Slice { ret (invalid_type(), InvalidType) }
        if !container.has_element || container.element >= c.type_count { ret (invalid_type(), InvalidType) }
        ret (c.types[container.element], ok)
    }
    let (aggregate_index, found_aggregate) = aggregate_for_type(c, subject)
    if !found_aggregate { ret (invalid_type(), InvalidType) }
    let aggregate = c.aggregates[aggregate_index]
    // An enum's backing type, and a union enum's is its tag's -- which is the same field,
    // because a union enum is an enum with payloads hung off it.
    if aggregate.kind != .Enum && aggregate.kind != .TaggedUnion { ret (invalid_type(), InvalidType) }
    if aggregate.backing_type.kind != .Integer { ret (invalid_type(), InvalidType) }
    ret (aggregate.backing_type, ok)
}

// `meta.element_type[T]()` written where a type is written. The parser kept the tokens and
// left the classifying here, so this reads the path from them: two identifiers, then the
// bracket whose one argument is the subject.
fn named_type_derived(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, err) {
    let text = g.modules[module_index].text
    var qualifier = ""
    var member = ""
    var identifiers = 0usize
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .PunctLBracket { break }
        if token.kind == .Identifier {
            if identifiers == 0usize { qualifier = text[token.start..token.end] }
            if identifiers == 1usize { member = text[token.start..token.end] }
            identifiers += 1usize
        }
        at += 1usize
    }
    if identifiers != 2usize { ret (invalid_type(), InvalidType) }
    let (target_module, has_qualifier) = resolve.qualifier(c.resolver, module_index, qualifier)
    if !has_qualifier || !same(g.modules[target_module].name, "e.meta") { ret (invalid_type(), InvalidType) }
    var wants_element = false
    var matched = false
    if same(member, "element_type") {
        wants_element = true
        matched = true
    }
    if same(member, "backing_type") { matched = true }
    if !matched { ret (invalid_type(), InvalidType) }
    // The bracket's argument is this node's only child.
    let (subject_index, has_subject) = first_node_child(tree, node)
    if !has_subject { ret (invalid_type(), InvalidType) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, subject_index)
    if subject_error != ok { ret (invalid_type(), subject_error) }
    let (answer, answer_error) = derived_from_subject(c, wants_element, subject)
    ret (answer, answer_error)
}

fn comptime_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if is_type_node(node.kind) {
        let (parsed, parsed_error) = type_from_node(c, c.resolver, g, tree, module_index, node)
        ret (parsed, parsed_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (invalid_type(), InvalidType) }
        let name = text[token.start..token.end]
        let scalar = scalar_type(name, module_index)
        if scalar.kind != .Invalid { ret (scalar, ok) }
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), InvalidType) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if argument_found { ret (argument.ty, ok) }
            var parameter_type = make_type(.TypeParameter, name, module_index)
            parameter_type.element = parameter_index
            parameter_type.has_element = true
            ret (parameter_type, ok)
        }
        let (_, found) = resolve.find(c.resolver, module_index, name, .Type)
        if !found { ret (invalid_type(), InvalidType) }
        let named = make_type(.Named, name, module_index)
        let (canonical, canonical_error) = canonical_type(c, named)
        ret (canonical, canonical_error)
    }
    if node.kind == .FieldExpr {
        // `f.ty` where `f` is bound by an unrolled `for`: a comptime expression of type
        // `type`, so it stands wherever a type stands.
        let (bound, bound_member, is_bound) = comptime_binding_base(c, text, tree, node)
        if is_bound {
            if bound.kind != .Field || !same(bound_member, "ty") { ret (invalid_type(), InvalidType) }
            ret (bound.ty, ok)
        }
        let (target_module, name, found) = qualified_member(c, g, tree, module_index, node)
        if !found { ret (invalid_type(), InvalidType) }
        let (_, has_type) = resolve.find(c.resolver, target_module, name, .Type)
        if !has_type { ret (invalid_type(), InvalidType) }
        let named = make_type(.Named, name, target_module)
        let (canonical, canonical_error) = canonical_type(c, named)
        ret (canonical, canonical_error)
    }
    // `meta.element_type[T]()` and `meta.backing_type[E]()`: comptime expressions whose
    // type is `type`, which section 9 says stand wherever a type is written. They are
    // answered here rather than in `check_call` because there is nothing for a call like
    // this to produce -- a type is not a value, so the only place it can be asked for is
    // where a type is expected.
    if node.kind == .CallExpr {
        let (derived, derived_error) = derived_type(c, g, tree, module_index, node)
        ret (derived, derived_error)
    }
    // `St[i64]` in a comptime argument slot. The parser gives a bracket expression
    // here rather than a type node -- the two spellings differ only in where they are
    // written -- so the base names the template and the rest are its arguments.
    if node.kind == .BracketPostfix {
        // The base occupies the first child slot; the arguments are the slots after it.
        let child_end = usize(node.first_child) + usize(node.child_count)
        var base_slot = usize(node.first_child)
        while base_slot < child_end && !parse.child_is_node_at(tree, base_slot) { base_slot += 1usize }
        if base_slot >= child_end { ret (invalid_type(), parse.InvalidSyntax) }
        let base_index = parse.child_index_at(tree, base_slot)
        let base = tree.nodes[base_index]
        var target_module = module_index
        var name = ""
        if base.kind == .NameExpr {
            let base_token = c.tokens[usize(base.token_start)]
            if base_token.kind != .Identifier { ret (invalid_type(), InvalidType) }
            name = text[base_token.start..base_token.end]
            let (qualified_module, has_qualifier) = resolve.qualifier(c.resolver, module_index, name)
            if has_qualifier { ret (invalid_type(), InvalidType) }
            if same(name, "Atomic") {
                let (atomic_module, has_atomic) = graph.find_module(g, "e.atomic")
                if has_atomic { target_module = atomic_module }
            }
            if (same(name, "Vec") || same(name, "Mask")) && c.has_simd { target_module = c.simd_module }
        } else {
            let (member_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
            if !found_member { ret (invalid_type(), InvalidType) }
            target_module = member_module
            name = member
        }
        let (template_index, found_template) = find_aggregate(c, target_module, name)
        if !found_template { ret (invalid_type(), InvalidType) }
        let (first_argument, collect_error) = collect_generic_arguments(c, g, tree, module_index, template_index, base_slot + 1usize, child_end)
        if collect_error != ok { ret (invalid_type(), collect_error) }
        if c.has_simd && target_module == c.simd_module && (same(name, "Vec") || same(name, "Mask")) && !vector_shape_legal(c, first_argument) {
            record_failure(c, module_index, node, .VectorShape, name, "")
            ret (invalid_type(), InvalidType)
        }
        let (instance_index, instance_error) = instantiate_aggregate(c, template_index, first_argument)
        if instance_error != ok { ret (invalid_type(), instance_error) }
        var instance = make_type(.Named, name, target_module)
        instance.element = instance_index
        instance.has_element = true
        ret (instance, ok)
    }
    if node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (element, element_error) = comptime_type(c, g, tree, module_index, child_index)
        if element_error != ok { ret (invalid_type(), element_error) }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var pointer = make_type(.Pointer, "", module_index)
        pointer.element = stored_element
        pointer.has_element = true
        pointer.is_const = contains_token(c, usize(node.token_start), usize(tree.nodes[child_index].token_start), .KwConst)
        ret (pointer, ok)
    }
    ret (invalid_type(), InvalidType)
}

// Section 8. A pointer's own bits read as a `usize`. `mem.bitcast` cannot give this:
// it refuses any type holding a pointer, so that a pun can never invent provenance,
// cast away `const` or manufacture a callable address. Reading an address out is the
// direction none of that applies to -- nothing comes back, and the `usize` is a number
// with no way to be dereferenced -- and it is what an operating system interface needs,
// because a system call takes a buffer as an integer.
fn address_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (CastInfo, err) {
    var info: CastInfo = zero
    if receiver.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, receiver)
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "address_of") { ret (info, ok) }
    info.matched = true
    var function: Function = zero
    function.name = "address_of"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = make_type(.Integer, "usize", target_module)
    ret (info, ok)
}

// Spec section 8: `mem.bitcast` is legal only where neither type holds a pointer,
// slice, function pointer, `type` or `Atomic` at any depth. That is what stops a pun
// from casting away `const`, inventing provenance, changing an address space or
// manufacturing a callable address, and it is a property of the type alone -- the
// sizes are compared during lowering, where the layout is reachable.
fn punnable_type(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > c.aggregate_count + 1usize { ret false }
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if canonical.kind == .Bool || canonical.kind == .Err || canonical.kind == .Integer || canonical.kind == .Float { ret true }
    // A type parameter in a template body: whether it can be punned is the instance's question,
    // and the widths are compared in lowering, which only ever sees an instance (D136).
    if canonical.kind == .TypeParameter { ret true }
    if canonical.kind == .Array {
        if !canonical.has_element || canonical.element >= c.type_count { ret false }
        ret punnable_type(c, c.types[canonical.element], depth + 1usize)
    }
    if canonical.kind != .Named && canonical.kind != .Tag { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, canonical)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    // An enum and a tagged union's tag are their backing integer's bytes. Reading
    // bytes that name no member is section 11's `invalid` check, not a type error.
    if aggregate.kind == .Enum || canonical.kind == .Tag { ret punnable_type(c, aggregate.backing_type, depth + 1usize) }
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index >= c.aggregate_field_count { ret false }
        let member = c.aggregate_fields[field_index]
        // A tagged union's void-payload arms carry no bytes of their own.
        if member.ty.kind != .Void || aggregate.kind != .TaggedUnion {
            if !punnable_type(c, member.ty, depth + 1usize) { ret false }
        }
        field_at += 1usize
    }
    if aggregate.kind == .TaggedUnion { ret punnable_type(c, aggregate.backing_type, depth + 1usize) }
    ret true
}

// `mem.bitcast[T](x)` reads `x`'s bytes as a `T`, so a pun never needs a `union`. The
// call names no declared function and is recognised the way `mem.alloc[T]` and
// `mem.cast[P]` are.
fn bitcast_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (BitcastInfo, err) {
    var info: BitcastInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "bitcast") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (punned, punned_error) = comptime_type(c, g, tree, module_index, type_index)
    if punned_error != ok { ret (info, punned_error) }
    if !punnable_type(c, punned, 0usize) { ret (info, InvalidType) }
    var function: Function = zero
    function.name = "bitcast"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = punned
    ret (info, ok)
}

// `math.sqrt[F](x)`. The type argument is the float type, or a type parameter in a template
// body that an instance settles (D136); the one runtime argument is checked against it below.
fn sqrt_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (BitcastInfo, err) {
    var info: BitcastInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    var target_module = module_index
    if base.kind == .FieldExpr {
        let (member_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
        if !found_member || !same(g.modules[member_module].name, "e.math") || !same(member, "sqrt") { ret (info, ok) }
        target_module = member_module
    } else {
        // `sqrt[F](x)` unqualified is the module's own spelling of its own intrinsic, which
        // `rsqrt` needs: a module cannot import itself.
        if base.kind != .NameExpr || !same(g.modules[module_index].name, "e.math") { ret (info, ok) }
        let base_token = c.tokens[usize(base.token_start)]
        if base_token.kind != .Identifier || !same(g.modules[module_index].text[base_token.start..base_token.end], "sqrt") { ret (info, ok) }
    }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (float_type, float_error) = comptime_type(c, g, tree, module_index, type_index)
    if float_error != ok { ret (info, float_error) }
    if float_type.kind != .Float && float_type.kind != .TypeParameter { ret (info, InvalidType) }
    var function: Function = zero
    function.name = "sqrt"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = float_type
    ret (info, ok)
}

// Section 4's verbs. `Text` never reaches a caller: it is the state between verbs.
type FormatVerb = enum u8 {
    Text,
    Default,
    Hex,
    Binary,
    Fixed,
}

// One decoded byte of a string literal, and where the scan continues. The format
// string is the decoded text, not the spelling, so `{` reached through an escape is
// a verb like any other and `{{` is the only way to write a brace that is not one.
fn literal_byte(spelling: str, at: usize, raw: bool, next: *usize) -> (u8, err) {
    if at >= spelling.len { ret (0u8, InvalidType) }
    let byte = spelling[at]
    if raw || byte != 92u8 {
        *next = at + 1usize
        ret (byte, ok)
    }
    if at + 1usize >= spelling.len { ret (0u8, InvalidType) }
    let escaped = spelling[at + 1usize]
    *next = at + 2usize
    if escaped == 110u8 { ret (10u8, ok) }
    if escaped == 116u8 { ret (9u8, ok) }
    if escaped == 114u8 { ret (13u8, ok) }
    if escaped == 92u8 { ret (92u8, ok) }
    if escaped == 34u8 { ret (34u8, ok) }
    if escaped == 39u8 { ret (39u8, ok) }
    if escaped == 48u8 { ret (0u8, ok) }
    if escaped != 120u8 { ret (0u8, InvalidType) }
    if at + 3usize >= spelling.len { ret (0u8, InvalidType) }
    var value = 0u8
    var digit = 0usize
    while digit < 2usize {
        let hex = spelling[at + 2usize + digit]
        var nibble = 16u8
        if hex >= 48u8 && hex <= 57u8 { nibble = hex - 48u8 }
        if hex >= 97u8 && hex <= 102u8 { nibble = hex - 87u8 }
        if hex >= 65u8 && hex <= 70u8 { nibble = hex - 55u8 }
        if nibble == 16u8 { ret (0u8, InvalidType) }
        value = value * 16u8 + nibble
        digit += 1usize
    }
    *next = at + 4usize
    ret (value, ok)
}

// Strips the quotes and the raw-string hashes, leaving the contents and whether
// backslashes inside are escapes or bytes.
fn literal_contents(spelling: str, raw: *bool) -> (str, err) {
    if spelling.len >= 2usize && spelling[0usize] == 34u8 && spelling[spelling.len - 1usize] == 34u8 {
        *raw = false
        ret (spelling[1usize..spelling.len - 1usize], ok)
    }
    if spelling.len < 3usize || spelling[0usize] != 114u8 { ret ("", InvalidType) }
    var at = 1usize
    var hashes = 0usize
    while at < spelling.len && spelling[at] == 35u8 {
        at += 1usize
        hashes += 1usize
    }
    if at >= spelling.len || spelling[at] != 34u8 || spelling.len < at + hashes + 2usize { ret ("", InvalidType) }
    let closing = spelling.len - hashes - 1usize
    if spelling[closing] != 34u8 { ret ("", InvalidType) }
    *raw = true
    ret (spelling[at + 1usize..closing], ok)
}

// Reads the verbs out of a format string in order. `{{` and `}}` are the literal
// braces; a bare `}` is malformed, and so is an unterminated or unknown verb.
fn format_verbs(spelling: str, kinds: []FormatVerb, precisions: []u8) -> (usize, err) {
    var raw = false
    let (body, body_error) = literal_contents(spelling, &raw)
    if body_error != ok { ret (0usize, body_error) }
    var count = 0usize
    var at = 0usize
    while at < body.len {
        var next = 0usize
        let (byte, byte_error) = literal_byte(body, at, raw, &next)
        if byte_error != ok { ret (0usize, byte_error) }
        at = next
        if byte == 125u8 {
            // A closing brace is only legal doubled.
            if at >= body.len { ret (0usize, InvalidFormat) }
            let (following, following_error) = literal_byte(body, at, raw, &next)
            if following_error != ok { ret (0usize, following_error) }
            if following != 125u8 { ret (0usize, InvalidFormat) }
            at = next
            continue
        }
        if byte != 123u8 { continue }
        if at >= body.len { ret (0usize, InvalidFormat) }
        let (following, following_error) = literal_byte(body, at, raw, &next)
        if following_error != ok { ret (0usize, following_error) }
        if following == 123u8 {
            at = next
            continue
        }
        if count == kinds.len || count == precisions.len { ret (0usize, Capacity) }
        var kind: FormatVerb = .Default
        var precision = 0u8
        var scan = at
        var body_byte = following
        var body_next = next
        if body_byte == 120u8 || body_byte == 98u8 {
            if body_byte == 120u8 { kind = .Hex } else { kind = .Binary }
            scan = body_next
            if scan >= body.len { ret (0usize, InvalidFormat) }
            let (closer, closer_error) = literal_byte(body, scan, raw, &body_next)
            if closer_error != ok { ret (0usize, closer_error) }
            if closer != 125u8 { ret (0usize, InvalidFormat) }
            scan = body_next
        } else {
            if body_byte == 46u8 {
                kind = .Fixed
                scan = body_next
                var digits = 0usize
                var value = 0usize
                while scan < body.len {
                    let (digit, digit_error) = literal_byte(body, scan, raw, &body_next)
                    if digit_error != ok { ret (0usize, digit_error) }
                    if digit < 48u8 || digit > 57u8 { break }
                    // Section 4 caps a format-literal precision at 99, and a larger
                    // one is a compile error rather than a runtime `BadNumber`.
                    if digits == 2usize { ret (0usize, InvalidFormat) }
                    value = value * 10usize + usize(digit - 48u8)
                    digits += 1usize
                    scan = body_next
                }
                if digits == 0usize { ret (0usize, InvalidFormat) }
                precision = u8(value)
                if scan >= body.len { ret (0usize, InvalidFormat) }
                let (closer, closer_error) = literal_byte(body, scan, raw, &body_next)
                if closer_error != ok { ret (0usize, closer_error) }
                if closer != 125u8 { ret (0usize, InvalidFormat) }
                scan = body_next
            } else {
                if body_byte != 125u8 { ret (0usize, InvalidFormat) }
                scan = body_next
            }
        }
        kinds[count] = kind
        precisions[count] = precision
        count += 1usize
        at = scan
    }
    ret (count, ok)
}

// The format grammar is small enough to pin exactly, and it is read from a literal's
// spelling, so the cases below are written the way a caller writes them.
fn format_self_test() -> err {
    var kinds: [8]FormatVerb = zero
    var precisions: [8]u8 = zero
    // A verb of each shape, and the precision a fixed one carries.
    let (one, one_error) = format_verbs("\"{}\"", kinds[..], precisions[..])
    if one_error != ok || one != 1usize || kinds[0usize] != .Default { ret InvalidFormat }
    let (hex, hex_error) = format_verbs("\"{x}\"", kinds[..], precisions[..])
    if hex_error != ok || hex != 1usize || kinds[0usize] != .Hex { ret InvalidFormat }
    let (binary, binary_error) = format_verbs("\"{b}\"", kinds[..], precisions[..])
    if binary_error != ok || binary != 1usize || kinds[0usize] != .Binary { ret InvalidFormat }
    let (fixed, fixed_error) = format_verbs("\"{.3}\"", kinds[..], precisions[..])
    if fixed_error != ok || fixed != 1usize || kinds[0usize] != .Fixed || precisions[0usize] != 3u8 { ret InvalidFormat }
    let (none_precision, none_precision_error) = format_verbs("\"{.0}\"", kinds[..], precisions[..])
    if none_precision_error != ok || precisions[0usize] != 0u8 { ret InvalidFormat }
    let (widest, widest_error) = format_verbs("\"{.99}\"", kinds[..], precisions[..])
    if widest_error != ok || precisions[0usize] != 99u8 { ret InvalidFormat }

    // Verbs in order, with text around and between them.
    let (mixed, mixed_error) = format_verbs("\"a{}b{x}c{.2}d\"", kinds[..], precisions[..])
    if mixed_error != ok || mixed != 3usize { ret InvalidFormat }
    if kinds[0usize] != .Default || kinds[1usize] != .Hex || kinds[2usize] != .Fixed { ret InvalidFormat }
    if precisions[2usize] != 2u8 { ret InvalidFormat }

    // A doubled brace is a literal brace and not a verb, in either direction.
    let (doubled, doubled_error) = format_verbs("\"{{}}\"", kinds[..], precisions[..])
    if doubled_error != ok || doubled != 0usize { ret InvalidFormat }
    let (wrapped, wrapped_error) = format_verbs("\"{{{}}}\"", kinds[..], precisions[..])
    if wrapped_error != ok || wrapped != 1usize { ret InvalidFormat }
    let (empty, empty_error) = format_verbs("\"\"", kinds[..], precisions[..])
    if empty_error != ok || empty != 0usize { ret InvalidFormat }
    let (plain, plain_error) = format_verbs("\"no verbs here\"", kinds[..], precisions[..])
    if plain_error != ok || plain != 0usize { ret InvalidFormat }

    // The format string is the decoded text, so a brace reached through an escape is
    // a verb and a raw string's backslash is a byte.
    let (escaped, escaped_error) = format_verbs("\"\\x7b}\"", kinds[..], precisions[..])
    if escaped_error != ok || escaped != 1usize || kinds[0usize] != .Default { ret InvalidFormat }
    let (newline, newline_error) = format_verbs("\"{}\\n\"", kinds[..], precisions[..])
    if newline_error != ok || newline != 1usize { ret InvalidFormat }
    let (raw, raw_error) = format_verbs("r\"{}\"", kinds[..], precisions[..])
    if raw_error != ok || raw != 1usize { ret InvalidFormat }

    // Malformed: an unterminated verb, a bare closing brace, an unknown verb, and a
    // precision that is missing, too long, or unterminated.
    let (open_brace, open_brace_error) = format_verbs("\"{\"", kinds[..], precisions[..])
    if open_brace_error != InvalidFormat { ret InvalidFormat }
    let (close_brace, close_brace_error) = format_verbs("\"}\"", kinds[..], precisions[..])
    if close_brace_error != InvalidFormat { ret InvalidFormat }
    let (unknown, unknown_error) = format_verbs("\"{z}\"", kinds[..], precisions[..])
    if unknown_error != InvalidFormat { ret InvalidFormat }
    let (bare_point, bare_point_error) = format_verbs("\"{.}\"", kinds[..], precisions[..])
    if bare_point_error != InvalidFormat { ret InvalidFormat }
    let (too_wide, too_wide_error) = format_verbs("\"{.100}\"", kinds[..], precisions[..])
    if too_wide_error != InvalidFormat { ret InvalidFormat }
    let (unterminated, unterminated_error) = format_verbs("\"{.1\"", kinds[..], precisions[..])
    if unterminated_error != InvalidFormat { ret InvalidFormat }
    let (trailing, trailing_error) = format_verbs("\"a{\"", kinds[..], precisions[..])
    if trailing_error != InvalidFormat { ret InvalidFormat }
    // A closing brace followed by anything but another one, and a verb body that
    // is not a verb: each is reached only when the string does not also run out,
    // so a shorter spelling of either is caught by the wrong check.
    let (loose_close, loose_close_error) = format_verbs("\"}a\"", kinds[..], precisions[..])
    if loose_close_error != InvalidFormat { ret InvalidFormat }
    let (unknown_body, unknown_body_error) = format_verbs("\"{z}}\"", kinds[..], precisions[..])
    if unknown_body_error != InvalidFormat { ret InvalidFormat }
    ret ok
}

// A format string carries at most this many verbs. It is a limit on one literal, not
// on a program, and reaching it is `Capacity` rather than a wrong expansion.
fn format_verb_limit() -> usize {
    ret 32usize
}

fn format_verb_count(spelling: str) -> (usize, err) {
    var kinds: [32]FormatVerb = zero
    var precisions: [32]u8 = zero
    let (count, count_error) = format_verbs(spelling, kinds[..], precisions[..])
    ret (count, count_error)
}

fn format_verb_at(spelling: str, index: usize) -> (FormatVerb, u8, err) {
    var kinds: [32]FormatVerb = zero
    var precisions: [32]u8 = zero
    let (count, count_error) = format_verbs(spelling, kinds[..], precisions[..])
    if count_error != ok { ret (.Text, 0u8, count_error) }
    if index >= count { ret (.Text, 0u8, ArgumentCount) }
    ret (kinds[index], precisions[index], ok)
}

// Section 4: formattable is every shape rule 4 supplies a `format` for. This is the
// half the checker can decide without reaching a module's own `format`, which is why
// a `Named` type is left to the protocol lookup rather than judged here.
fn formattable_type(c: *Checker, ty: Type, kind: FormatVerb) -> bool {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if kind == .Hex || kind == .Binary { ret canonical.kind == .Integer }
    if kind == .Fixed { ret canonical.kind == .Float }
    if canonical.kind == .Integer || canonical.kind == .Float { ret true }
    if canonical.kind == .Bool || canonical.kind == .Err || canonical.kind == .String { ret true }
    if canonical.kind == .Pointer || canonical.kind == .Slice || canonical.kind == .Array { ret true }
    if canonical.kind == .Named || canonical.kind == .Tag {
        if is_enum_type(c, canonical) { ret true }
        let (function_index, has_format) = element_format_function(c, canonical)
        ret has_format
    }
    ret false
}

// A type's own `format` under section 4: `fn <t>_format(v: T, b: *str.Builder) -> err`
// in the type's module, which the expansion calls with the builder it is pushing
// into. Nothing re-checks the call, so the shape is matched here exactly: the
// receiver by value, a pointer second, one `err` back.
fn element_format_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok || canonical.kind != .Named { ret (0usize, false) }
    let (function_index, found, lookup_error) = protocol_function(c, ty, "format")
    if lookup_error != ok || !found { ret (0usize, false) }
    let function = c.functions[function_index]
    if function.generic || function.parameter_count != 2usize || function.return_count != 1usize { ret (0usize, false) }
    if function.first_parameter + 2usize > c.parameter_count { ret (0usize, false) }
    if !type_equal(c, c.parameters[function.first_parameter].ty, canonical) { ret (0usize, false) }
    if c.parameters[function.first_parameter + 1usize].ty.kind != .Pointer { ret (0usize, false) }
    let (return_type, return_error) = function_return(c, function, 0usize)
    if return_error != ok || return_type.kind != .Err { ret (0usize, false) }
    ret (function_index, true)
}

// Spec section 8: a pointer type -- `*void` included -- is only reached through
// `mem.cast[*Foo](p)`. The call names no declared function, so it is recognised
// here the way `mem.alloc[T]` is, and both its argument and its comptime type have
// to be pointers. The value itself is unchanged: lowering hands the operand back.
// Section 8's `os.dlsym[F]`, whose answer is a value of the caller's own `extern fn` type. That
// is the one thing a library cannot do for itself: section 8 bans manufacturing a callable
// address and D96 bans integer-to-pointer, so the retype belongs to the compiler. Everything
// else about the call is ordinary -- the variant's `dl_lookup` finds the address with the same
// arguments, and only the first result's type is this intrinsic's doing.
fn dl_symbol_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (CastInfo, err) {
    var info: CastInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.os") || !same(member, "dlsym") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (wanted, wanted_error) = comptime_type(c, g, tree, module_index, type_index)
    if wanted_error != ok { ret (info, wanted_error) }
    // The fence requires an `extern fn` type, and a function type is the only thing an address
    // may become: anything else would be manufacturing a value out of one.
    if wanted.kind != .Function { ret (info, InvalidType) }
    // The variant supplies the lookup. A target whose `e.os` has none cannot answer this at all,
    // which is `Unsupported` rather than a missing name.
    let (lookup_index, has_lookup) = find_function(c, target_module, "dl_lookup")
    if !has_lookup { ret (info, Unsupported) }
    info.function = c.functions[lookup_index]
    info.target = wanted
    ret (info, ok)
}

fn cast_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (CastInfo, err) {
    var info: CastInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "cast") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (pointer, pointer_error) = comptime_type(c, g, tree, module_index, type_index)
    if pointer_error != ok { ret (info, pointer_error) }
    if pointer.kind != .Pointer { ret (info, InvalidType) }
    var function: Function = zero
    function.name = "cast"
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    info.target = pointer
    ret (info, ok)
}

// Section 9's kinds, in the order `e.meta.TypeKind` declares them. A reflected kind
// is that enum's value, so the two lists are one list and have to stay so.
fn meta_kind_value(c: *Checker, ty: Type) -> (usize, err) {
    if ty.kind == .Integer || ty.kind == .UntypedInteger { ret (0usize, ok) }
    if ty.kind == .Float || ty.kind == .UntypedFloat { ret (1usize, ok) }
    if ty.kind == .Bool { ret (2usize, ok) }
    if ty.kind == .Err { ret (3usize, ok) }
    if ty.kind == .Pointer { ret (4usize, ok) }
    if ty.kind == .Slice || ty.kind == .String { ret (5usize, ok) }
    if ty.kind == .Array { ret (6usize, ok) }
    if is_vector_type(c, ty) { ret (10usize, ok) }
    if ty.kind == .Named || ty.kind == .Tag {
        let (aggregate_index, found) = aggregate_for_type(c, ty)
        if !found { ret (0usize, InvalidType) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind == .Enum { ret (8usize, ok) }
        if aggregate.kind == .TaggedUnion { ret (9usize, ok) }
        if aggregate.kind == .Struct { ret (7usize, ok) }
        // A bare `union` is the one aggregate section 9's list has no kind for.
        ret (0usize, Unsupported)
    }
    ret (0usize, InvalidType)
}

// `e.meta`'s scalar half: three questions whose answer is a constant the checker
// already holds. `fields`, `members`, `get` and `set` are not here -- they need a
// comptime value of struct type, which the language does not carry yet.
fn meta_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (MetaInfo, err) {
    var info: MetaInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member { ret (info, ok) }
    var query: MetaQuery = .None
    if same(g.modules[target_module].name, "e.meta") {
        if same(member, "kind") { query = .Kind }
        if same(member, "array_len") { query = .ArrayLen }
        if same(member, "type_name") { query = .TypeName }
    }
    // `e.mem`'s two layout questions come here rather than to a path of their own: a
    // type goes in, a number comes out, and nothing survives to run time. What is
    // different is that the number is not known here -- `layout` is built on `check`,
    // so the size of a type is something only lowering can ask for, which is already
    // why `bitcast` compares its widths there.
    if same(g.modules[target_module].name, "e.mem") {
        if same(member, "size_of") { query = .SizeOf }
        if same(member, "align_of") { query = .AlignOf }
    }
    if query == .None { ret (info, ok) }
    info.matched = true
    info.query = query
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (info, subject_error) }
    if subject.kind == .Void || subject.kind == .Invalid { ret (info, InvalidType) }
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = 0usize
    function.return_count = 1usize
    function.intrinsic = true
    info.function = function
    // A subject that is still a type parameter is the template pass of a generic function, where
    // the answer is a constant only an instance can supply (see `derived_from_subject`). The
    // question keeps its result type, so the body around it still checks; the value it folds to
    // is filled in when the instance is checked.
    if subject.kind == .TypeParameter { info.deferred = true }
    if query == .Kind {
        info.result = make_type(.Named, "TypeKind", target_module)
        if subject.kind == .TypeParameter { ret (info, ok) }
        let (value, value_error) = meta_kind_value(c, subject)
        if value_error != ok { ret (info, value_error) }
        info.value = value
        ret (info, ok)
    }
    if query == .ArrayLen {
        info.result = make_type(.Integer, "usize", target_module)
        if subject.kind == .TypeParameter { ret (info, ok) }
        if vector_pending(c, subject) {
            info.deferred = true
            ret (info, ok)
        }
        var counted = subject
        let (lanes, is_vector) = vector_lanes(c, subject)
        if is_vector { counted = lanes }
        if counted.kind != .Array { ret (info, InvalidType) }
        info.value = counted.array_length
        ret (info, ok)
    }
    if query == .SizeOf || query == .AlignOf {
        info.subject = subject
        info.result = make_type(.Integer, "usize", target_module)
        ret (info, ok)
    }
    // A composite has no written name of its own, and building one -- `[]u8`, `*T` --
    // means spelling a nesting and a length, which this does not do yet.
    if subject.name.len == 0usize { ret (info, Unsupported) }
    info.name = subject.name
    info.result = make_type(.String, "str", target_module)
    ret (info, ok)
}

// One side of a foldable condition: a `meta` question whose answer is a number already known
// here. `false` covers every other call, and covers a question whose subject is still a type
// parameter -- in a template body nothing is settled, so nothing may be folded (D136).
fn meta_constant(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, Type, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .CallExpr { ret (0usize, invalid_type(), false) }
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver { ret (0usize, invalid_type(), false) }
    let receiver = tree.nodes[receiver_index]
    if receiver.kind != .BracketPostfix { ret (0usize, invalid_type(), false) }
    let (info, info_error) = meta_info(c, g, tree, module_index, receiver)
    if info_error != ok || !info.matched || info.deferred { ret (0usize, invalid_type(), false) }
    // `mem.size_of[T]()` is answered by lowering in general, since only `layout` knows an
    // aggregate. A scalar's size is a fact the checker holds too, and a branch on it is what
    // lets one generic reinterpret bytes as a `T` of whichever width it turns out to have --
    // the arm for the other width has to be gone, not merely not taken (D144).
    if info.query == .SizeOf {
        let size = scalar_size(info.subject)
        if size == 0usize { ret (0usize, invalid_type(), false) }
        ret (size, info.result, true)
    }
    if info.query != .Kind && info.query != .ArrayLen { ret (0usize, invalid_type(), false) }
    ret (info.value, info.result, true)
}

// The size of a scalar, which is the one layout question that needs no layout. Zero for
// anything that is not one, a type parameter included.
fn scalar_size(ty: Type) -> usize {
    if ty.kind == .Bool { ret 1usize }
    if ty.kind == .Err { ret 4usize }
    if ty.kind == .Pointer { ret 8usize }
    if ty.kind == .Integer { ret integer_width(ty) / 8usize }
    if ty.kind == .Float {
        if same(ty.name, "f16") || same(ty.name, "bf16") { ret 2usize }
        if same(ty.name, "f32") { ret 4usize }
        ret 8usize
    }
    ret 0usize
}

// The other side, read against the type the question answers with: `.Int` is a member of
// `TypeKind` and a length is an ordinary integer, so one of the two evaluators has it.
fn compared_constant(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (usize, bool) {
    let node = tree.nodes[node_index]
    if node.kind == .MemberExpr {
        let (aggregate_index, found_aggregate) = aggregate_for_type(c, expected)
        if !found_aggregate { ret (0usize, false) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .Enum { ret (0usize, false) }
        var member = ""
        var at = usize(node.token_start)
        while at < usize(node.token_end) {
            let token = c.tokens[at]
            if token.kind == .Identifier { member = g.modules[module_index].text[token.start..token.end] }
            at += 1usize
        }
        let (field_index, found_member) = aggregate_field_for_name(c, aggregate, member)
        if !found_member { ret (0usize, false) }
        let field = c.aggregate_fields[field_index]
        if !field.has_enum_value || field.enum_negative { ret (0usize, false) }
        ret (field.enum_value, true)
    }
    let (value, value_error) = array_length_value(c, g, tree, module_index, node_index)
    if value_error != ok { ret (0usize, false) }
    ret (value, true)
}

// `if meta.kind[f.ty]() == .Int` inside an unrolled `for`. The condition is settled before the
// program runs, and the arm that is not taken is not this field's code at all -- so without
// folding it away, that arm still has to type check for a type it was never written for, which
// is exactly what stopped a codec being written over `meta.fields` (D138).
//
// Both the checker and lowering call this, on the same tree with the same comptime bindings in
// place, which is what makes them agree about which arm exists. Nothing is remembered between
// them; the question is simply asked twice.
//
// ponytail: the narrowest rule that does the job. One side must be a `meta` question, so no
// condition an ordinary program writes can be folded by accident and no arm stops being checked
// that a reader would expect to be. A general comptime `if` is the upgrade, and wants the
// interpreter this compiler does not have.
fn comptime_condition(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .BinaryExpr { ret (false, false) }
    let op = binary_operator(c, tree, node)
    if op != .PunctEqEq && op != .PunctBangEq {
        let (folded, settled) = constant_condition(c, g, tree, module_index, node_index)
        ret (folded, settled)
    }
    let (meta_taken, meta_settled) = meta_condition(c, g, tree, module_index, node_index)
    if meta_settled { ret (meta_taken, true) }
    let (folded, settled) = constant_condition(c, g, tree, module_index, node_index)
    ret (folded, settled)
}

// A condition over constants alone (D500): a comparison, `&&` or `||` whose operands
// are constants, literals and operators on them -- no local, no call -- is settled
// by the interpreter that settles a `const`, as `meta_condition` settles a question
// about a type. The expression is copied for the evaluation and dropped after; a
// name the copy cannot resolve as a constant, a call, or a failed evaluation leaves
// the branch to run time, and nothing is recorded of the attempt.
fn constant_condition(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, bool) {
    if !c.signatures_ready || c.constant_exprs.len == 0usize { ret (false, false) }
    let node = tree.nodes[node_index]
    let op = binary_operator(c, tree, node)
    if !is_comparison(op) && op != .PunctAndAnd && op != .PunctOrOr { ret (false, false) }
    let expressions_before = c.constant_expr_count
    let expected_before = c.failure_expected
    let actual_before = c.failure_actual
    let mismatch_before = c.failure_mismatch_end
    let (copied, copy_error) = copy_constant_expr(c, g, tree, module_index, node_index)
    var settled = false
    var truth = false
    if copy_error == ok {
        // A call in the condition is left to run time: the fold is for constants.
        var has_call = false
        var scan = expressions_before
        while scan < c.constant_expr_count {
            if c.constant_exprs[scan].kind == .Call { has_call = true }
            scan += 1usize
        }
        if !has_call {
            let (value, value_type, value_error) = evaluate_constant_expr(c, copied, make_type(.Bool, "bool", module_index))
            if value_error == ok && value_type.kind == .Bool {
                settled = true
                truth = value.magnitude != 0usize
            }
        }
    }
    c.constant_expr_count = expressions_before
    c.failure_expected = expected_before
    c.failure_actual = actual_before
    c.failure_mismatch_end = mismatch_before
    ret (truth, settled)
}

// A question about a type against a constant (D138): `meta.kind[T]() == .Int`.
fn meta_condition(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, bool) {
    let node = tree.nodes[node_index]
    let op = binary_operator(c, tree, node)
    var children: [2]usize = zero
    var count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if count == children.len { ret (false, false) }
            children[count] = parse.child_index_at(tree, at)
            count += 1usize
        }
        at += 1usize
    }
    if count != 2usize { ret (false, false) }
    var question = children[0usize]
    var other = children[1usize]
    let (left_value, left_type, left_known) = meta_constant(c, g, tree, module_index, question)
    var answer = left_value
    var answer_type = left_type
    if !left_known {
        // The question may be written on either side, and only one side may be one: two of them
        // would be a comparison this does not need to fold.
        question = children[1usize]
        other = children[0usize]
        let (right_value, right_type, right_known) = meta_constant(c, g, tree, module_index, question)
        if !right_known { ret (false, false) }
        answer = right_value
        answer_type = right_type
    }
    let (compared, compared_known) = compared_constant(c, g, tree, module_index, other, answer_type)
    if !compared_known { ret (false, false) }
    if op == .PunctEqEq { ret (answer == compared, true) }
    ret (answer != compared, true)
}

// `os.thread_create[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize)`. The two
// pointers have to agree, and this is the only place the context type still exists to
// say so with.
fn thread_create_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (AllocInfo, err) {
    var info: AllocInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.os") || !same(member, "thread_create") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (context, context_error) = comptime_type(c, g, tree, module_index, type_index)
    if context_error != ok { ret (info, context_error) }
    if context.kind == .Void || context.kind == .Invalid || context.kind == .Other { ret (info, InvalidType) }
    let (context_pointer, pointer_error) = seeded_composite_type(c, .Pointer, context, false, target_module)
    if pointer_error != ok { ret (info, pointer_error) }
    info.return_type = make_type(.Named, "Thread", target_module)
    info.arena_type = context_pointer
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = 3usize
    function.return_count = 2usize
    function.intrinsic = true
    info.function = function
    ret (info, ok)
}

fn alloc_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (AllocInfo, err) {
    var info: AllocInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.mem") || !same(member, "alloc") { ret (info, ok) }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (element, element_error) = comptime_type(c, g, tree, module_index, type_index)
    if element_error != ok { ret (info, element_error) }
    if element.kind == .Void || element.kind == .Other || element.kind == .Invalid { ret (info, InvalidType) }
    let (stored_element, store_error) = store_type(c, element)
    if store_error != ok { ret (info, store_error) }
    var result = make_type(.Slice, "", target_module)
    result.element = stored_element
    result.has_element = true
    let arena = make_type(.Named, "Arena", target_module)
    let (stored_arena, arena_error) = store_type(c, arena)
    if arena_error != ok { ret (info, arena_error) }
    var arena_pointer = make_type(.Pointer, "", target_module)
    arena_pointer.element = stored_arena
    arena_pointer.has_element = true
    var function: Function = zero
    function.name = "alloc"
    function.module_index = target_module
    function.parameter_count = 2usize
    function.return_count = 2usize
    function.intrinsic = true
    info.function = function
    info.return_type = result
    info.arena_type = arena_pointer
    ret (info, ok)
}

// Section 4: `str.format[FMT](a, args: ...)` and `io.printf[FMT](args: ...)` are
// expanded rather than called, so the compiler recognises them the way it recognises
// `mem.alloc[T]`. Arity and argument types are checked against the format string
// here, which is what makes a mismatched count or an unformattable type a compile
// error rather than a runtime one.
fn formatter_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (FormatterInfo, err) {
    var info: FormatterInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var format_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                format_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member { ret (info, ok) }
    let module_name = g.modules[target_module].name
    var arena = false
    if same(module_name, "e.str") && same(member, "format") {
        arena = true
    } else {
        if !same(module_name, "e.io") || !same(member, "printf") { ret (info, ok) }
    }
    info.matched = true
    if child_count != 2usize { ret (info, ArgumentCount) }
    let format_node = tree.nodes[format_index]
    if format_node.kind != .LiteralExpr { ret (info, TypeMismatch) }
    let literal = c.tokens[usize(format_node.token_start)]
    if literal.kind != .String && literal.kind != .RawString { ret (info, TypeMismatch) }
    let spelling = g.modules[module_index].text[literal.start..literal.end]
    let (verbs, verbs_error) = format_verb_count(spelling)
    if verbs_error != ok { ret (info, verbs_error) }
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = verbs
    function.return_count = 1usize
    if arena {
        function.parameter_count = verbs + 1usize
        function.return_count = 2usize
    }
    function.intrinsic = true
    info.function = function
    info.arena = arena
    info.verbs = verbs
    info.spelling = spelling
    ret (info, ok)
}

fn formatter_instance_matches(c: *Checker, candidate: usize, owner_module_index: usize, target_module: usize, member: str, spelling: str, argument_types: []const Type) -> bool {
    let generic = c.function_generics[candidate]
    if !generic.formatter || !same(generic.formatter_spelling, spelling) { ret false }
    let function = c.functions[candidate]
    if function.owner_module_index != owner_module_index || function.module_index != target_module { ret false }
    if !same(function.name, member) || function.parameter_count != argument_types.len { ret false }
    var at = 0usize
    while at < argument_types.len {
        if !type_equal(c, c.parameters[function.first_parameter + at].ty, argument_types[at]) { ret false }
        at += 1usize
    }
    ret true
}

// The expansion becomes a function of its own rather than code inlined at the call.
// That keeps every existing path -- the multiple-return call, the error propagation,
// the linker's instance naming -- working unchanged, and cross-module inlining folds
// it back in where it is small enough to be worth it. One instance per calling
// module, formatter, format string and argument-type list, so two calls that agree
// share a body and two that differ do not.
fn formatter_instance(c: *Checker, owner_module_index: usize, target_module: usize, member: str, spelling: str, argument_types: []const Type, arena: bool) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if formatter_instance_matches(c, at, owner_module_index, target_module, member, spelling, argument_types) { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + argument_types.len > c.parameters.len { ret (0usize, Capacity) }
    var instance: Function = zero
    instance.name = member
    instance.module_index = target_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, member) + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = argument_types.len
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    if arena { instance.return_count = 2usize }
    var fill = 0usize
    while fill < argument_types.len {
        c.parameters[c.parameter_count] = Parameter { name: "", ty: argument_types[fill], own: false }
        c.parameter_count += 1usize
        fill += 1usize
    }
    if arena {
        let text_error = store_return_type(c, make_type(.String, "str", target_module))
        if text_error != ok { ret (0usize, text_error) }
    }
    let error_error = store_return_type(c, make_type(.Err, "err", target_module))
    if error_error != ok { ret (0usize, error_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_spelling = spelling
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

// The sink `printf` hands to `str.builder_to`. Its shape -- `fn(*void, []const u8) ->
// err` -- is not one `e.io` declares, and it cannot be added to `e.io` because the
// language has no visibility mechanism and the surface is frozen (spec section 12).
// So the compiler generates it, once per module that calls `printf`, the same way it
// generates the expansions themselves.
fn formatter_sink_instance(c: *Checker, owner_module_index: usize, io_module: usize) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if c.function_generics[at].formatter_sink && c.functions[at].owner_module_index == owner_module_index { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + 2usize > c.parameters.len { ret (0usize, Capacity) }
    let u8_type = make_type(.Integer, "u8", io_module)
    let (bytes, bytes_error) = seeded_composite_type(c, .Slice, u8_type, true, io_module)
    if bytes_error != ok { ret (0usize, bytes_error) }
    var instance: Function = zero
    instance.name = "print_sink"
    instance.module_index = io_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, "print_sink") + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = 2usize
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    c.parameters[c.parameter_count] = Parameter { name: "ctx", ty: make_type(.Pointer, "", io_module), own: false }
    c.parameters[c.parameter_count + 1usize] = Parameter { name: "bytes", ty: bytes, own: false }
    c.parameter_count += 2usize
    let return_error = store_return_type(c, make_type(.Err, "err", io_module))
    if return_error != ok { ret (0usize, return_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_sink = true
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

// One `push_err` body per module that calls it, for the same reason a formatter gets
// one: the body is generated, so it belongs to the module that asked for it rather
// than to `e.str`.
fn error_push_instance(c: *Checker, owner_module_index: usize, str_module: usize) -> (usize, err) {
    var at = c.signature_function_count
    while at < c.function_count {
        if c.function_generics[at].formatter_error && c.functions[at].owner_module_index == owner_module_index { ret (at, ok) }
        at += 1usize
    }
    if c.function_count == c.functions.len { ret (0usize, Capacity) }
    if c.parameter_count + 2usize > c.parameters.len { ret (0usize, Capacity) }
    let (seeded_index, found_seeded) = find_function(c, str_module, "push_err")
    if !found_seeded { ret (0usize, UnknownCallable) }
    let seeded = c.functions[seeded_index]
    var instance: Function = zero
    instance.name = "push_err"
    instance.module_index = str_module
    instance.owner_module_index = owner_module_index
    instance.instance_id = owner_instance_count(c, owner_module_index, "push_err") + 1usize
    instance.first_parameter = c.parameter_count
    instance.parameter_count = 2usize
    instance.first_return = c.return_type_count
    instance.return_count = 1usize
    c.parameters[c.parameter_count] = c.parameters[seeded.first_parameter]
    c.parameters[c.parameter_count + 1usize] = c.parameters[seeded.first_parameter + 1usize]
    c.parameter_count += 2usize
    let return_error = store_return_type(c, make_type(.Err, "err", str_module))
    if return_error != ok { ret (0usize, return_error) }
    var generic: FunctionGeneric = zero
    generic.instance = true
    generic.checked = true
    generic.formatter = true
    generic.formatter_error = true
    let index = c.function_count
    c.functions[index] = instance
    c.function_generics[index] = generic
    c.function_count += 1usize
    ret (index, ok)
}

// Section 8's thirteen intrinsics, by the name written after `atomic.`.
fn atomic_op_for_name(name: str) -> AtomicOp {
    if same(name, "init") { ret .Init }
    if same(name, "load") { ret .Load }
    if same(name, "store") { ret .Store }
    if same(name, "xchg") { ret .Xchg }
    if same(name, "cas") { ret .Cas }
    if same(name, "add") { ret .Add }
    if same(name, "sub") { ret .Sub }
    if same(name, "and") { ret .And }
    if same(name, "or") { ret .Or }
    if same(name, "xor") { ret .Xor }
    if same(name, "min") { ret .Min }
    if same(name, "max") { ret .Max }
    if same(name, "fence") { ret .Fence }
    ret .None
}

fn atomic_op_name(op: AtomicOp) -> str {
    if op == .Init { ret "init" }
    if op == .Load { ret "load" }
    if op == .Store { ret "store" }
    if op == .Xchg { ret "xchg" }
    if op == .Cas { ret "cas" }
    if op == .Add { ret "add" }
    if op == .Sub { ret "sub" }
    if op == .And { ret "and" }
    if op == .Or { ret "or" }
    if op == .Xor { ret "xor" }
    if op == .Min { ret "min" }
    if op == .Max { ret "max" }
    if op == .Fence { ret "fence" }
    ret ""
}

// `init(v)` and `fence(o)` take one argument, `cas` takes five, `load` two, and every
// other operation takes the pointer, a value and an ordering.
fn atomic_arity(op: AtomicOp) -> usize {
    if op == .Init || op == .Fence { ret 1usize }
    if op == .Load { ret 2usize }
    if op == .Cas { ret 5usize }
    ret 3usize
}

// `store` and `fence` give nothing back, `cas` gives the pair, the rest give a `T`.
fn atomic_return_count(op: AtomicOp) -> usize {
    if op == .Store || op == .Fence { ret 0usize }
    if op == .Cas { ret 2usize }
    ret 1usize
}

// The arithmetic and bitwise operations take an integer `T` only; `init`, `load`,
// `store`, `xchg` and `cas` take a pointer `T` as well.
fn atomic_integer_only(op: AtomicOp) -> bool {
    ret op == .Add || op == .Sub || op == .And || op == .Or || op == .Xor || op == .Min || op == .Max
}

fn atomic_ordering_for_name(name: str) -> Ordering {
    if same(name, "Relaxed") { ret .Relaxed }
    if same(name, "Acquire") { ret .Acquire }
    if same(name, "Release") { ret .Release }
    if same(name, "AcqRel") { ret .AcqRel }
    if same(name, "SeqCst") { ret .SeqCst }
    ret .Dynamic
}

fn atomic_ordering_name(o: Ordering) -> str {
    if o == .Relaxed { ret "Relaxed" }
    if o == .Acquire { ret "Acquire" }
    if o == .Release { ret "Release" }
    if o == .AcqRel { ret "AcqRel" }
    if o == .SeqCst { ret "SeqCst" }
    ret "Dynamic"
}

// A `load` with a release ordering or a `store` with an acquire one is a compile
// error, as C11 has it. A CAS failure ordering may not be `.Release` or `.AcqRel`.
fn atomic_ordering_legal(op: AtomicOp, o: Ordering, failure: bool) -> bool {
    if o == .Dynamic { ret true }
    if failure { ret o == .Relaxed || o == .Acquire || o == .SeqCst }
    if op == .Load { ret o == .Relaxed || o == .Acquire || o == .SeqCst }
    if op == .Store { ret o == .Relaxed || o == .Release || o == .SeqCst }
    ret true
}

// Section 8 orders the five: a CAS failure ordering may not be stronger than its
// success ordering. `AcqRel` is not a legal failure ordering, so comparing the enum's
// own order is enough -- `Release` never reaches here either.
fn atomic_ordering_stronger(left: Ordering, right: Ordering) -> bool {
    if left == .Dynamic || right == .Dynamic { ret false }
    ret atomic_ordering_rank(left) > atomic_ordering_rank(right)
}

// The ordering as a number: its strength for the comparison above, and the immediate
// lowering carries on the instruction. `Dynamic` ranks strongest because that is the
// form emitted for an ordering no one could read at compile time.
fn atomic_ordering_rank(o: Ordering) -> usize {
    if o == .Relaxed { ret 0usize }
    if o == .Acquire { ret 1usize }
    if o == .Release { ret 2usize }
    if o == .AcqRel { ret 3usize }
    ret 4usize
}

// `p` is a `*Atomic[T]`; the instance's one field is the `T` it wraps.
fn atomic_pointee_element(c: *Checker, ty: Type) -> (Type, bool) {
    if ty.kind != .Pointer || !ty.has_element || ty.element >= c.type_count { ret (invalid_type(), false) }
    let pointee = c.types[ty.element]
    if pointee.kind != .Named || !same(pointee.name, "Atomic") { ret (invalid_type(), false) }
    let (aggregate_index, found) = aggregate_for_type(c, pointee)
    if !found { ret (invalid_type(), false) }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.field_count != 1usize || aggregate.first_field >= c.aggregate_field_count { ret (invalid_type(), false) }
    ret (c.aggregate_fields[aggregate.first_field].ty, true)
}

// `Atomic[T]` built from a `T` the checker already holds. `init`'s return type is
// written nowhere, so it cannot be read off a type node like every other one.
fn atomic_wrapper_type(c: *Checker, element: Type, atomic_module: usize) -> Type {
    let (template_index, found) = find_aggregate(c, atomic_module, "Atomic")
    if !found { ret invalid_type() }
    if c.generic_argument_count == c.generic_arguments.len { ret invalid_type() }
    let first_argument = c.generic_argument_count
    var argument: GenericArgument = zero
    argument.kind = .Type
    argument.set = true
    argument.ty = element
    c.generic_arguments[first_argument] = argument
    c.generic_argument_count += 1usize
    let (instance_index, instance_error) = instantiate_aggregate(c, template_index, first_argument)
    if instance_error != ok {
        c.generic_argument_count = first_argument
        ret invalid_type()
    }
    // A cached instance kept its own arguments, so this one's slot is dead. Give it
    // back: `call_return` is asked the same question many times per call.
    if c.aggregates[instance_index].first_argument != first_argument { c.generic_argument_count = first_argument }
    var result = make_type(.Named, "Atomic", atomic_module)
    result.element = instance_index
    result.has_element = true
    ret result
}

// `atomic.<op>(...)`, recognised the way `mem.alloc[T]` is. `T` is not written, so the
// signature is not fixed and cannot be seeded: it is built here from the arguments.
fn atomic_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (AtomicInfo, err) {
    var info: AtomicInfo = zero
    if receiver.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, receiver)
    if !found_member || !same(g.modules[target_module].name, "e.atomic") { ret (info, ok) }
    let op = atomic_op_for_name(member)
    if op == .None { ret (info, ok) }
    info.matched = true
    info.op = op
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = atomic_arity(op)
    function.return_count = atomic_return_count(op)
    function.intrinsic = true
    info.function = function
    ret (info, ok)
}

// One argument of an `atomic.*` call. `T` is not written anywhere, so the first
// argument fixes it and every later one is checked against what it gave -- the shape
// `thread_create` uses for its context type.
fn check_atomic_argument(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, child_index: usize, position: usize, info: *CallInfo) -> err {
    let op = info.atomic_op
    let atomic_module = info.function.module_index
    let ordering_type = make_type(.Named, "Ordering", atomic_module)
    // `fence(o)` has no pointer and no `T`; `init(v)` takes the value the atomic will
    // hold, which is what fixes `T` for it.
    if op == .Fence {
        ret check_atomic_ordering(c, g, tree, module_index, child_index, ordering_type, op, false, info)
    }
    if op == .Init {
        let (value, value_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if value_error != ok { ret value_error }
        if is_untyped(value) { ret MissingContext }
        if !atomic_element_legal(value) {
            record_failure_token(c, module_index, c.tokens[usize(tree.nodes[child_index].token_start)], .AtomicElement, value.name, "")
            ret InvalidType
        }
        info.atomic_element = value
        ret ok
    }
    if position == 0usize {
        let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if pointer_error != ok { ret pointer_error }
        let (element, found) = atomic_pointee_element(c, pointer)
        if !found { ret TypeMismatch }
        if atomic_integer_only(op) && element.kind != .Integer {
            record_failure_token(c, module_index, c.tokens[usize(tree.nodes[child_index].token_start)], .AtomicElement, element.name, "")
            ret InvalidType
        }
        info.atomic_element = element
        ret ok
    }
    // `cas(p, expected, desired, success, failure)`: two values then two orderings.
    // Every other operation is `(p, v, o)` and `load` is `(p, o)`.
    var value_positions = 1usize
    if op == .Cas { value_positions = 2usize }
    if op == .Load { value_positions = 0usize }
    if position <= value_positions {
        let (value, value_error) = check_expr(c, g, tree, module_index, child_index, info.atomic_element)
        if value_error != ok { ret value_error }
        ret ok
    }
    let failure = op == .Cas && position == value_positions + 2usize
    ret check_atomic_ordering(c, g, tree, module_index, child_index, ordering_type, op, failure, info)
}

// An ordering argument. A member written at the call is known now, so section 8's
// rules are a compile error rather than a runtime check; one that is not stays
// `Dynamic` and lowering emits the strongest form, which is always safe.
//
// ponytail: a runtime ordering skips section 8's `invalid` check for a bad pair.
// Add it when an `Ordering` computed at runtime turns up in real code -- it costs a
// trap site per operation, and every ordering here is a literal today.
fn check_atomic_ordering(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, child_index: usize, ordering_type: Type, op: AtomicOp, failure: bool, info: *CallInfo) -> err {
    let (given, given_error) = check_expr(c, g, tree, module_index, child_index, ordering_type)
    if given_error != ok { ret given_error }
    var ordering: Ordering = .Dynamic
    let node = tree.nodes[child_index]
    if node.kind == .MemberExpr {
        let (member, has_member) = switch_member_name(c, g.modules[module_index].text, node)
        if has_member { ordering = atomic_ordering_for_name(member) }
    }
    if !atomic_ordering_legal(op, ordering, failure) {
        record_failure_token(c, module_index, c.tokens[usize(node.token_start)], .AtomicOrdering, atomic_op_name(op), atomic_ordering_name(ordering))
        ret InvalidType
    }
    if failure {
        if atomic_ordering_stronger(ordering, info.atomic_success) {
            record_failure_token(c, module_index, c.tokens[usize(node.token_start)], .AtomicOrdering, atomic_op_name(op), atomic_ordering_name(ordering))
            ret InvalidType
        }
        info.atomic_failure = ordering
    } else {
        info.atomic_success = ordering
    }
    ret ok
}

type MetaAccessInfo = struct {
    matched: bool,
    writes: bool,
    field: GenericArgument,
    subject: Type,
    function: Function,
}

// Section 9: `get` and `set` are comptime-*parameterised*, not comptime-only. Only
// `FIELD` must be comptime; each compiles to one field load or store at the offset
// that `FIELD` names, so both are legal in any body at runtime, exactly as `v.x` is.
fn meta_access_info(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (MetaAccessInfo, err) {
    var info: MetaAccessInfo = zero
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let text = g.modules[module_index].text
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var field_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize { base_index = parse.child_index_at(tree, at) }
            if child_count == 1usize { field_index = parse.child_index_at(tree, at) }
            if child_count == 2usize { type_index = parse.child_index_at(tree, at) }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.meta") { ret (info, ok) }
    if !same(member, "get") && !same(member, "set") { ret (info, ok) }
    info.matched = true
    info.writes = same(member, "set")
    if child_count != 3usize { ret (info, ArgumentCount) }
    // The first bracket argument names a comptime `Field`, which today can only come
    // from the binding of an unrolled `for` over `meta.fields[T]()`.
    let field_node = tree.nodes[field_index]
    if field_node.kind != .NameExpr { ret (info, InvalidType) }
    let field_token = c.tokens[usize(field_node.token_start)]
    if field_token.kind != .Identifier { ret (info, InvalidType) }
    let (argument, found_binding) = find_comptime_binding(c, text[field_token.start..field_token.end])
    if !found_binding || argument.kind != .Field { ret (info, InvalidType) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (info, subject_error) }
    // Section 9 requires that `FIELD` be an element of `meta.fields[T]()`: a `Field` of
    // any other type read at its offset in this one is exactly what that forbids.
    //
    // An unset argument is a parameter of a declaration being checked before anything is bound
    // to it, where neither side of that comparison exists yet. Section 9 puts a check that
    // depends on a comptime parameter at the instantiation, and this one runs there -- every
    // instantiation goes through here with the argument set.
    if argument.set {
        let (aggregate_index, found_aggregate) = aggregate_for_type(c, subject)
        if !found_aggregate || aggregate_index != argument.owner {
            record_failure(c, module_index, field_node, .MetaFieldOwner, argument.text, subject.name)
            ret (info, InvalidType)
        }
        if !info.writes && c.resources_on && affine_kind(c, argument.ty, 0usize) != 0u8 {
            record_failure(c, module_index, field_node, .ResourceCopy, argument.text, "`meta.get`")
            ret (info, ResourceViolation)
        }
        if info.writes && c.resources_on && affine_kind(c, argument.ty, 0usize) != 0u8 {
            record_failure(c, module_index, field_node, .ResourceCopy, argument.text, "`meta.set`")
            ret (info, ResourceViolation)
        }
    }
    info.field = argument
    info.subject = subject
    var function: Function = zero
    function.name = member
    function.module_index = target_module
    function.parameter_count = 1usize
    function.return_count = 1usize
    if info.writes {
        function.parameter_count = 2usize
        function.return_count = 0usize
    }
    function.intrinsic = true
    info.function = function
    ret (info, ok)
}

fn check_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (CallInfo, err) {
    let (info, call_error) = check_call_cached(c, g, tree, module_index, node)
    if call_error != ok { ret (info, call_error) }
    let resource_error = resource_call(c, g, tree, module_index, node, info)
    ret (info, resource_error)
}

fn check_call_cached(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (CallInfo, err) {
    var slot = 0usize
    if c.call_cache.len != 0usize && c.call_generation != 0usize {
        slot = (usize(node.token_start) * 31usize + usize(node.token_end)) % c.call_cache.len
        let cached = c.call_cache[slot]
        if cached.generation == c.call_generation && usize(cached.token_start) == usize(node.token_start) && usize(cached.token_end) == usize(node.token_end) { ret (cached.info, ok) }
    }
    let (fresh, fresh_error) = check_call_uncached(c, g, tree, module_index, node)
    if fresh_error == ok && c.call_cache.len != 0usize && c.call_generation != 0usize {
        c.call_cache[slot] = CallCacheEntry { generation: c.call_generation, token_start: usize(node.token_start), token_end: usize(node.token_end), info: fresh }
    }
    // A resolved direct call, for the context query (D361): the callee, or the
    // fact that the target is a value and not known here.
    if fresh_error == ok && c.explains.len != 0usize && !fresh.is_cast && !fresh.protocol_pending && !fresh.is_unreachable {
        if c.explain_count < c.explains.len {
            var offset = 0usize
            if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
            var callee = c.function_count
            if !fresh.indirect { callee = explain_function_index(c, fresh.function) }
            // A synthesized intrinsic (`mem.alloc`, `os.thread_create`) has no
            // declaration to index (D396): the record carries its module and name.
            var intrinsic_name = ""
            var intrinsic_module = 0usize
            if !fresh.indirect && callee == c.function_count {
                intrinsic_name = fresh.function.name
                intrinsic_module = fresh.function.module_index
            }
            c.explains[c.explain_count] = Explain { kind: 4u8, module_index: module_index, offset: offset, protocol: intrinsic_name, receiver: invalid_type(), function_index: callee, found: fresh.indirect, builtin: .None, template_index: intrinsic_module, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
            c.explain_count += 1usize
        } else {
            c.explain_overflow = true
        }
    }
    ret (fresh, fresh_error)
}

// The function or instance whose calls are being checked or lowered changed: what
// the cache holds is no longer about this scope.
fn begin_call_scope(c: *Checker) {
    c.call_generation += 1usize
    c.active_noescape = ""
}

fn check_noescape_argument(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, info: CallInfo, child_index: usize, child_position: usize, parameter_type: Type) -> err {
    if c.active_noescape.len == 0usize || !holds_pointer(c, parameter_type, 0usize) { ret ok }
    var local = 0usize
    while local < c.local_count {
        if contract_name_count(c.active_noescape, c.locals[local].name) != 0usize && expression_borrows_from(c, g, tree, module_index, child_index, local) {
            if !info.indirect && !info.thread_create && function_noescape_at(c, info.function, child_position) { ret ok }
            record_failure(c, module_index, tree.nodes[child_index], .NoEscapeContract, c.locals[local].name, "")
            ret ResourceViolation
        }
        local += 1usize
    }
    ret ok
}

fn check_call_uncached(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (CallInfo, err) {
    var info: CallInfo = zero
    // The formatter's arguments become the parameters of the instance its call
    // resolves to, so they are kept as they are checked.
    var formatter_types: [33]Type = zero
    info.cast = invalid_type()
    info.alloc_return = invalid_type()
    info.alloc_arena = invalid_type()
    if node.kind != .CallExpr { ret (info, parse.InvalidSyntax) }
    let text = g.modules[module_index].text
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    var child_position = 0usize
    var has_function = false
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if child_position == 0usize {
                let receiver = tree.nodes[child_index]
                if receiver.kind == .NameExpr && c.tokens[usize(receiver.token_start)].kind == .KwUnreachable {
                    info.is_unreachable = true
                    info.function.module_index = module_index
                    has_function = true
                } else {
                if receiver.kind == .NameExpr {
                    let token = c.tokens[usize(receiver.token_start)]
                    let name = text[token.start..token.end]
                    let cast = scalar_type(name, module_index)
                    let (callee_local, callee_is_local) = find_local(c, name)
                    if callee_is_local && c.locals[callee_local].ty.kind == .Function {
                        let (signature, has_signature) = function_signature_of(c, c.locals[callee_local].ty)
                        if !has_signature { ret (info, InvalidType) }
                        info.indirect = true
                        info.indirect_type = c.locals[callee_local].ty
                        info.function.module_index = module_index
                        info.function.parameter_count = signature.parameter_count
                        info.function.return_count = signature.return_count
                        has_function = true
                    } else {
                    let (comptime_function, is_comptime_function) = active_comptime_parameter(c, name)
                    if is_comptime_function && c.comptime_parameters[comptime_function].kind == .Function {
                        var callable_type = c.comptime_parameters[comptime_function].ty
                        let (bound_function, has_bound_function) = active_argument(c, comptime_function)
                        if has_bound_function {
                            if bound_function.value >= c.function_count { ret (info, UnknownCallable) }
                            info.function = c.functions[bound_function.value]
                        } else {
                            let (signature, has_signature) = function_signature_of(c, callable_type)
                            if !has_signature { ret (info, InvalidType) }
                            info.indirect = true
                            info.indirect_type = callable_type
                            info.function.module_index = module_index
                            info.function.parameter_count = signature.parameter_count
                            info.function.return_count = signature.return_count
                        }
                        has_function = true
                    } else {
                    // `T(x)` where `T` is this generic's own type parameter: a conversion to
                    // whatever `T` is bound to, the same one a written `u8(x)` is (D139 did this
                    // for a `Field`'s `.ty`; this is the type parameter itself). In the template
                    // pass nothing is bound yet, and the conversion stands as one to a type not
                    // yet known, the way every other question about `T` does there (D136).
                    let (parameter_index, is_parameter) = active_comptime_parameter(c, name)
                    var parameter_cast = invalid_type()
                    if is_parameter && c.comptime_parameters[parameter_index].kind == .Type {
                        let (argument, argument_found) = active_argument(c, parameter_index)
                        if argument_found {
                            parameter_cast = argument.ty
                        } else {
                            parameter_cast = make_type(.TypeParameter, name, module_index)
                            parameter_cast.element = parameter_index
                            parameter_cast.has_element = true
                        }
                    }
                    if parameter_cast.kind == .Integer || parameter_cast.kind == .Float || parameter_cast.kind == .TypeParameter {
                        info.cast = parameter_cast
                        info.is_cast = true
                    } else {
                    let (enum_index, is_enum_name) = find_aggregate(c, module_index, name)
                    if cast.kind == .Integer || cast.kind == .Float {
                        info.cast = cast
                        info.is_cast = true
                    } else {
                    // `Kind(x)`: section 4's integer-to-enum cast, from an integer of the
                    // backing width alone; the value is checked against the members at
                    // run time (section 11's `enum` row, D197).
                    if is_enum_name && c.aggregates[enum_index].kind == .Enum {
                        info.cast = make_type(.Named, name, module_index)
                        info.cast.element = enum_index
                        info.cast.has_element = true
                        info.is_cast = true
                    } else {
                        let (found_index, found) = find_function(c, module_index, name)
                        if !found { ret (info, UnknownCallable) }
                        if c.functions[found_index].generic {
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, found_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        } else {
                            info.function = c.functions[found_index]
                        }
                        has_function = true
                    }
                    }
                    }
                    }
                    }
                } else {
                    if receiver.kind == .BracketPostfix {
                        let (spawner, spawner_error) = thread_create_info(c, g, tree, module_index, receiver)
                        if spawner_error != ok { ret (info, spawner_error) }
                        if spawner.matched {
                            info.function = spawner.function
                            info.thread_create = true
                            info.thread_context = spawner.arena_type
                            info.alloc_return = spawner.return_type
                            has_function = true
                        } else {
                        let (access, access_error) = meta_access_info(c, g, tree, module_index, receiver)
                        if access_error != ok { ret (info, access_error) }
                        if access.matched {
                            info.function = access.function
                            info.meta_access = true
                            info.meta_writes = access.writes
                            info.meta_field = access.field
                            info.meta_subject = access.subject
                            has_function = true
                        } else {
                        let (reflection, reflection_error) = meta_info(c, g, tree, module_index, receiver)
                        if reflection_error != ok { ret (info, reflection_error) }
                        if reflection.matched {
                            info.function = reflection.function
                            info.meta_query = reflection.query
                            info.meta_value = reflection.value
                            info.meta_name = reflection.name
                            info.meta_result = reflection.result
                            info.meta_subject = reflection.subject
                            has_function = true
                            ret (info, ok)
                        }
                        let (allocation, allocation_error) = alloc_info(c, g, tree, module_index, receiver)
                        if allocation_error != ok { ret (info, allocation_error) }
                        if allocation.matched {
                            info.function = allocation.function
                            info.alloc_return = allocation.return_type
                            info.alloc_arena = allocation.arena_type
                            info.mem_alloc = true
                        } else {
                        let (symbol, symbol_error) = dl_symbol_info(c, g, tree, module_index, receiver)
                        if symbol_error != ok { ret (info, symbol_error) }
                        if symbol.matched {
                            info.function = symbol.function
                            info.cast = symbol.target
                            info.dl_symbol = true
                        } else {
                        let (conversion, conversion_error) = cast_info(c, g, tree, module_index, receiver)
                        if conversion_error != ok { ret (info, conversion_error) }
                        if conversion.matched {
                            info.function = conversion.function
                            info.cast = conversion.target
                            info.mem_cast = true
                        } else {
                        let (pun, pun_error) = bitcast_info(c, g, tree, module_index, receiver)
                        if pun_error != ok { ret (info, pun_error) }
                        if pun.matched {
                            info.function = pun.function
                            info.cast = pun.target
                            info.mem_bitcast = true
                        } else {
                        let (root, root_error) = sqrt_info(c, g, tree, module_index, receiver)
                        if root_error != ok { ret (info, root_error) }
                        if root.matched {
                            info.function = root.function
                            info.cast = root.target
                            info.math_sqrt = true
                        } else {
                        let (formatter, formatter_error) = formatter_info(c, g, tree, module_index, receiver)
                        if formatter_error != ok { ret (info, formatter_error) }
                        if formatter.matched {
                            info.function = formatter.function
                            info.formatter = true
                            info.formatter_arena = formatter.arena
                            info.formatter_verbs = formatter.verbs
                            info.formatter_spelling = formatter.spelling
                        } else {
                            let (template_index, template_error) = bracket_function(c, g, tree, module_index, receiver)
                            if template_error != ok { ret (info, template_error) }
                            let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, template_index)
                            if specialize_error != ok { ret (info, specialize_error) }
                            info.function = c.functions[specialized_index]
                        }
                        }
                        }
                        }
                        }
                        }
                        has_function = true
                        }
                        }
                    } else {
                        if receiver.kind == .CallExpr {
                        // `meta.element_type[W]()(x)`: the callee is a type-valued question, so
                        // the call is a conversion to its answer -- how `simd.convert` writes
                        // `T(x)` for a lane type it can only name through `W`.
                        let (derived, derived_error) = derived_type(c, g, tree, module_index, receiver)
                        if derived_error != ok { ret (info, derived_error) }
                        if derived.kind != .Integer && derived.kind != .Float && derived.kind != .TypeParameter { ret (info, InvalidType) }
                        info.cast = derived
                        info.is_cast = true
                        } else {
                        if receiver.kind != .FieldExpr { ret (info, Unsupported) }
                        // `f.ty(x)` where `f` is an unrolled `for`'s binding. The callee is not a
                        // function but a type, so the call is a conversion, the same one a written
                        // `u8(x)` is. It is how a walk over `meta.fields` puts a value into the
                        // field it belongs to: every parser answers in one width and every field
                        // has its own (D139). `comptime_binding_base` only says yes to an actual
                        // binding, so an ordinary `module.function(x)` is untouched.
                        let (bound, bound_member, is_bound) = comptime_binding_base(c, text, tree, receiver)
                        let (truncation, is_truncation) = truncation_cast(c, text, tree, module_index, receiver)
                        if is_truncation {
                            info.cast = truncation
                            info.is_cast = true
                            info.truncating = true
                        } else {
                        if is_bound && bound.kind == .Field && same(bound_member, "ty") && (bound.ty.kind == .Integer || bound.ty.kind == .Float) {
                            info.cast = bound.ty
                            info.is_cast = true
                        } else {
                        let (address, address_error) = address_info(c, g, tree, module_index, receiver)
                        if address_error != ok { ret (info, address_error) }
                        if address.matched {
                            info.function = address.function
                            info.cast = address.target
                            info.mem_address = true
                            has_function = true
                        } else {
                        let (atomics, atomics_error) = atomic_info(c, g, tree, module_index, receiver)
                        if atomics_error != ok { ret (info, atomics_error) }
                        if atomics.matched {
                            info.function = atomics.function
                            info.atomic_op = atomics.op
                            info.atomic_element = invalid_type()
                            info.atomic_success = .Dynamic
                            info.atomic_failure = .Dynamic
                            has_function = true
                        } else {
                        let (protocol_type, protocol_name, is_protocol) = protocol_receiver(c, g, tree, module_index, receiver)
                        if is_protocol {
                            if protocol_type.kind == .Invalid {
                                // The template's own body: the receiver is still
                                // symbolic, so resolution waits for the instantiation.
                                info.protocol_pending = true
                            } else {
                                let (protocol_index, protocol_builtin, protocol_error) = check_protocol_call(c, g, tree, module_index, node, protocol_type, protocol_name)
                                if protocol_error != ok { ret (info, protocol_error) }
                                if protocol_builtin == .None {
                                    info.function = c.functions[protocol_index]
                                } else {
                                    let (supplied_receiver, supplied_error) = canonical_type(c, protocol_type)
                                    if supplied_error != ok { ret (info, supplied_error) }
                                    info.protocol_builtin = protocol_builtin
                                    info.protocol_type = supplied_receiver
                                    info.function.module_index = supplied_receiver.module_index
                                    info.function.parameter_count = supplied_protocol_parameters(protocol_builtin)
                                    info.function.return_count = 1usize
                                }
                            }
                            has_function = true
                        } else {
                            let (found_index, found) = find_qualified_function(c, g, tree, module_index, receiver)
                            if found {
                                if c.functions[found_index].generic {
                                    let (specialized_index, specialize_error) = specialize_call(c, g, tree, module_index, node, receiver, found_index)
                                    if specialize_error != ok { ret (info, specialize_error) }
                                    info.function = c.functions[specialized_index]
                                } else {
                                    info.function = c.functions[found_index]
                                }
                            } else {
                                let (field_type, field_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                                if field_error != ok { ret (info, UnknownCallable) }
                                if field_type.kind != .Function { ret (info, UnknownCallable) }
                                let (signature, has_signature) = function_signature_of(c, field_type)
                                if !has_signature { ret (info, InvalidType) }
                                info.indirect = true
                                info.indirect_type = field_type
                                info.function.module_index = module_index
                                info.function.parameter_count = signature.parameter_count
                                info.function.return_count = signature.return_count
                            }
                            has_function = true
                        }
                        }
                        }
                        }
                        }
                        }
                    }
                }
                }
            } else {
                if info.is_unreachable {
                    // At most one argument, and it is a `str` literal: the message is the
                    // record's values, so it has to be text the back end can lay out.
                    if child_position != 1usize { ret (info, ArgumentCount) }
                    let argument = tree.nodes[child_index]
                    if argument.kind != .LiteralExpr || c.tokens[usize(argument.token_start)].kind != .String { ret (info, TypeMismatch) }
                    child_position += 1usize
                    at += 1usize
                    continue
                }
                if info.is_cast {
                    if child_position != 1usize { ret (info, ArgumentCount) }
                    let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                    if argument_error != ok { ret (info, argument_error) }
                    if is_untyped(argument_type) { ret (info, MissingContext) }
                    if info.truncating && argument_type.kind != .Integer && !(c.generic_declaration && type_shape_unknown(argument_type)) { ret (info, TypeMismatch) }
                    if info.cast.kind == .Named {
                        let (backing, has_backing) = enum_backing_type(c, info.cast)
                        if !has_backing || argument_type.kind != .Integer || integer_width(argument_type) != integer_width(backing) { ret (info, TypeMismatch) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    // A value of a type parameter's type in a template body: whether it is
                    // numeric is the instance's question (D136).
                    if !is_numeric(argument_type) && !(c.generic_declaration && type_shape_unknown(argument_type)) { ret (info, TypeMismatch) }
                } else {
                    if !has_function { ret (info, UnknownCallable) }
                    if info.protocol_pending {
                        let (pending_type, pending_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if pending_error != ok { ret (info, pending_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    let function = info.function
                    if child_position > function.parameter_count {
                        if !function.variadic { ret (info, ArgumentCount) }
                        // A C variadic argument crosses as its own type, with no default
                        // promotion: what C would widen is refused, and the caller writes
                        // the conversion (section 5).
                        let (variadic_type, variadic_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if variadic_error != ok { ret (info, variadic_error) }
                        if is_untyped(variadic_type) { ret (info, MissingContext) }
                        if !type_crosses(c, variadic_type, 0usize) || (variadic_type.kind == .Float && !same(variadic_type.name, "f64")) || (variadic_type.kind == .Integer && integer_width(variadic_type) < 32usize) {
                            record_failure(c, module_index, node, .VariadicArgument, function.name, crossing_spelling(variadic_type))
                            ret (info, TypeMismatch)
                        }
                        let noescape_error = check_noescape_argument(c, g, tree, module_index, info, child_index, child_position, variadic_type)
                        if noescape_error != ok { ret (info, noescape_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    var parameter_type = invalid_type()
                    if info.indirect {
                        let (signature, has_signature) = function_signature_of(c, info.indirect_type)
                        if !has_signature { ret (info, InvalidType) }
                        let (indirect_parameter, has_parameter) = function_signature_parameter(c, signature, child_position - 1usize)
                        if !has_parameter { ret (info, ArgumentCount) }
                        let (indirect_argument, indirect_argument_error) = check_expr(c, g, tree, module_index, child_index, indirect_parameter)
                        if indirect_argument_error != ok { ret (info, indirect_argument_error) }
                        let noescape_error = check_noescape_argument(c, g, tree, module_index, info, child_index, child_position, indirect_parameter)
                        if noescape_error != ok { ret (info, noescape_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.protocol_builtin != .None {
                        parameter_type = info.protocol_type
                        let (supplied_argument, supplied_argument_error) = check_expr(c, g, tree, module_index, child_index, parameter_type)
                        if supplied_argument_error != ok { ret (info, supplied_argument_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_cast {
                        let (source, source_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if source_error != ok { ret (info, source_error) }
                        if source.kind != .Pointer { ret (info, TypeMismatch) }
                        // A pointer to a resource is made from a pointer to that
                        // resource, or from the `*void` one was erased to for a
                        // callback's context (D349): no other bytes become a handle.
                        if c.resources_on && info.cast.has_element && info.cast.element < c.type_count && affine_kind(c, c.types[info.cast.element], 0usize) != 0u8 {
                            var same_pointee = false
                            if source.has_element && source.element < c.type_count { same_pointee = type_equal(c, c.types[source.element], c.types[info.cast.element]) || c.types[source.element].kind == .Void }
                            if !same_pointee {
                                record_failure(c, module_index, node, .ResourceCopy, c.types[info.cast.element].name, "a pointer cast")
                                ret (info, ResourceViolation)
                            }
                        }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_address {
                        let (addressed, addressed_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if addressed_error != ok { ret (info, addressed_error) }
                        // A slice is a pointer and a length, so it has no single
                        // address: `&s[0]` is how one of its bytes is named.
                        if addressed.kind != .Pointer { ret (info, TypeMismatch) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.formatter {
                        var verb_position = child_position - 1usize
                        if info.formatter_arena {
                            if verb_position == 0usize {
                                // `format` writes into the caller's arena; `printf`
                                // has one of its own.
                                let (supplied, supplied_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                                if supplied_error != ok { ret (info, supplied_error) }
                                if supplied.kind != .Pointer || !supplied.has_element || supplied.element >= c.type_count { ret (info, TypeMismatch) }
                                let pointee = c.types[supplied.element]
                                if pointee.kind != .Named || !same(pointee.name, "Arena") { ret (info, TypeMismatch) }
                                if verb_position >= formatter_types.len { ret (info, Capacity) }
                                formatter_types[verb_position] = supplied
                                child_position += 1usize
                                at += 1usize
                                continue
                            }
                            verb_position = verb_position - 1usize
                        }
                        if verb_position >= info.formatter_verbs { ret (info, ArgumentCount) }
                        let (verb, verb_precision, verb_error) = format_verb_at(info.formatter_spelling, verb_position)
                        if verb_error != ok { ret (info, verb_error) }
                        let (supplied, supplied_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if supplied_error != ok { ret (info, supplied_error) }
                        if is_untyped(supplied) { ret (info, MissingContext) }
                        if !formattable_type(c, supplied, verb) { ret (info, InvalidFormat) }
                        if child_position - 1usize >= formatter_types.len { ret (info, Capacity) }
                        formatter_types[child_position - 1usize] = supplied
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_bitcast {
                        let (punned, punned_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                        if punned_error != ok { ret (info, punned_error) }
                        // An untyped literal has no bytes yet, so there is nothing to
                        // read as another type.
                        if is_untyped(punned) { ret (info, MissingContext) }
                        if !punnable_type(c, punned, 0usize) { ret (info, TypeMismatch) }
                        // Neither side of a pun is a resource (D349): the bits of a
                        // handle are not a second handle, and no bytes become one.
                        if c.resources_on && affine_kind(c, punned, 0usize) != 0u8 {
                            record_failure(c, module_index, node, .ResourceCopy, punned.name, "`mem.bitcast`")
                            ret (info, ResourceViolation)
                        }
                        if c.resources_on && affine_kind(c, info.cast, 0usize) != 0u8 {
                            record_failure(c, module_index, node, .ResourceCopy, info.cast.name, "`mem.bitcast`")
                            ret (info, ResourceViolation)
                        }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.math_sqrt {
                        // The argument is the float named in the brackets, and in a template
                        // body both may still be a type parameter.
                        let (radicand, radicand_error) = check_expr(c, g, tree, module_index, child_index, info.cast)
                        if radicand_error != ok { ret (info, radicand_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.thread_create {
                        // The entry point is checked against the context after the
                        // loop, once both have been seen.
                        if child_position == 2usize { parameter_type = info.thread_context }
                        if child_position == 3usize { parameter_type = make_type(.Integer, "usize", function.module_index) }
                        let (entry_type, entry_error) = check_expr(c, g, tree, module_index, child_index, parameter_type)
                        if entry_error != ok { ret (info, entry_error) }
                        let noescape_error = check_noescape_argument(c, g, tree, module_index, info, child_index, child_position, parameter_type)
                        if noescape_error != ok { ret (info, noescape_error) }
                        if child_position == 1usize { info.thread_entry = entry_type }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.meta_access {
                        var wanted = invalid_type()
                        if child_position == 1usize {
                            let (stored, store_error) = store_type(c, info.meta_subject)
                            if store_error != ok { ret (info, store_error) }
                            var pointer = make_type(.Pointer, "", function.module_index)
                            pointer.element = stored
                            pointer.has_element = true
                            pointer.is_const = !info.meta_writes
                            wanted = pointer
                        } else {
                            wanted = info.meta_field.ty
                        }
                        let (supplied, supplied_error) = check_expr(c, g, tree, module_index, child_index, wanted)
                        if supplied_error != ok { ret (info, supplied_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.atomic_op != .None {
                        let atomic_error = check_atomic_argument(c, g, tree, module_index, child_index, child_position - 1usize, &info)
                        if atomic_error != ok { ret (info, atomic_error) }
                        child_position += 1usize
                        at += 1usize
                        continue
                    }
                    if info.mem_alloc {
                        if child_position == 1usize {
                            parameter_type = info.alloc_arena
                        } else {
                            parameter_type = make_type(.Integer, "usize", function.module_index)
                        }
                    } else {
                        parameter_type = c.parameters[function.first_parameter + child_position - 1usize].ty
                    }
                    let (argument_type, argument_error) = check_expr(c, g, tree, module_index, child_index, parameter_type)
                    if argument_error != ok { ret (info, argument_error) }
                    let noescape_error = check_noescape_argument(c, g, tree, module_index, info, child_index, child_position, parameter_type)
                    if noescape_error != ok { ret (info, noescape_error) }
                }
            }
            child_position += 1usize
        }
        at += 1usize
    }
    if info.is_cast {
        if child_position != 2usize { ret (info, ArgumentCount) }
        ret (info, ok)
    }
    if info.is_unreachable { ret (info, ok) }
    if info.thread_create {
        if child_position != 4usize { ret (info, ArgumentCount) }
        let (signature, has_signature) = function_signature_of(c, info.thread_entry)
        if !has_signature { ret (info, TypeMismatch) }
        if signature.parameter_count != 1usize || signature.return_count != 0usize { ret (info, TypeMismatch) }
        let (entry_parameter, has_parameter) = function_signature_parameter(c, signature, 0usize)
        if !has_parameter { ret (info, TypeMismatch) }
        if !type_equal(c, entry_parameter, info.thread_context) { ret (info, mismatch(c, entry_parameter, info.thread_context)) }
        ret (info, ok)
    }
    if !has_function { ret (info, UnknownCallable) }
    if info.protocol_pending { ret (info, ok) }
    let function = info.function
    if child_position == 0usize || child_position - 1usize < function.parameter_count { ret (info, ArgumentCount) }
    if !function.variadic && child_position - 1usize != function.parameter_count { ret (info, ArgumentCount) }
    if function.intrinsic && same(function.name, "push_err") && function.module_index < g.count && same(g.modules[function.module_index].name, "e.str") {
        let (instance_index, instance_error) = error_push_instance(c, module_index, function.module_index)
        if instance_error != ok { ret (info, instance_error) }
        info.function = c.functions[instance_index]
        ret (info, ok)
    }
    if info.formatter {
        let (instance_index, instance_error) = formatter_instance(c, module_index, function.module_index, function.name, info.formatter_spelling, formatter_types[0usize..function.parameter_count], info.formatter_arena)
        if instance_error != ok { ret (info, instance_error) }
        info.function = c.functions[instance_index]
        ret (info, ok)
    }
    if function.generic && !c.generic_declaration { ret (info, Unsupported) }
    // An `extern fn` reaches the loader through `@import`, and nothing else can bind
    // it: without one there is no library to look in and no name to look for. Said
    // here because the linker's report names neither the call nor the declaration.
    if function.external && function.import_library.len == 0usize {
        record_failure(c, module_index, node, .ExternWithoutImport, function.name, "")
        ret (info, InvalidType)
    }
    ret (info, ok)
}

// Spec section 9 rule 1: `T.f(...)` is a protocol call only where T is a comptime
// type parameter. Returns the type bound to T, the protocol name, and whether the
// receiver is one at all. An invalid bound type means T is still symbolic, which is
// the case while a generic template's own body is checked.
fn protocol_receiver(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, receiver: syntax.Node) -> (Type, str, bool) {
    let (base_index, has_base) = first_node_child(tree, receiver)
    if !has_base { ret (invalid_type(), "", false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (invalid_type(), "", false) }
    if usize(base_node.token_start) >= c.token_count { ret (invalid_type(), "", false) }
    let base_token = c.tokens[usize(base_node.token_start)]
    if base_token.kind != .Identifier { ret (invalid_type(), "", false) }
    let text = g.modules[module_index].text
    let base = text[base_token.start..base_token.end]
    let (parameter_index, parameter_found) = active_comptime_parameter(c, base)
    if !parameter_found || c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), "", false) }
    var member = ""
    var at = usize(base_node.token_end)
    while at < usize(receiver.token_end) && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if member.len == 0usize { ret (invalid_type(), "", false) }
    let (argument, argument_found) = active_argument(c, parameter_index)
    if !argument_found { ret (invalid_type(), member, true) }
    ret (argument.ty, member, true)
}

// Spec section 9: the protocol function is `fn <t>_<protocol>` in the module that
// declares the receiver type, and its first parameter is the type by value.
// The index of a call's function, for a record that names it: the declared or
// instance record with the same module and name and parameter range.
fn explain_function_index(c: *Checker, function: Function) -> usize {
    var at = 0usize
    while at < c.function_count {
        if c.functions[at].module_index == function.module_index && c.functions[at].first_parameter == function.first_parameter && same(c.functions[at].name, function.name) { ret at }
        at += 1usize
    }
    // An instance of a generic (D396): its parameters are its own, and the
    // template of that name in that module is the function the fact names.
    at = 0usize
    while at < c.signature_function_count {
        if c.functions[at].module_index == function.module_index && same(c.functions[at].name, function.name) { ret at }
        at += 1usize
    }
    ret c.function_count
}

// A field accessed or named (D420, H17): the explain record of kind 6 carries the
// field's global index as its `function_index` and the member token's offset, so
// `uses-file --symbol module.Type.field` lists every access and a rename plan edits
// every spelling.
// An error value named (D451, H17): kind 7, the name's token and the resolver's
// symbol, for `uses-file` and `plan-rename-file` over `module.Error`.
fn record_explain_error(c: *Checker, module_index: usize, offset: usize, symbol_index: usize) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    c.explains[c.explain_count] = Explain { kind: 7u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: symbol_index, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

fn record_explain_field(c: *Checker, module_index: usize, offset: usize, field_index: usize) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    c.explains[c.explain_count] = Explain { kind: 6u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: field_index, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

// A function named as a value (D362, H17): a root a deletion has to know about.
fn record_explain_value(c: *Checker, module_index: usize, node: syntax.Node, function_index: usize) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 5u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: function_index, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

// The first component of a receiver the supplied rule refuses (D430): the kind of
// refusal, the component's name and its type; kind zero when the rule would have
// applied or the receiver is not a shape the rules read.
fn dispatch_refusal(c: *Checker, canonical: Type, protocol: str) -> (u8, str, Type) {
    var none: Type = zero
    if canonical.kind == .Named {
        let (aggregate_index, found) = aggregate_for_type(c, canonical)
        if !found { ret (0u8, "", none) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .TaggedUnion { ret (1u8, "", none) }
        var at = 0usize
        while at < aggregate.field_count {
            let field_index = aggregate.first_field + at
            if field_index >= c.aggregate_field_count { ret (0u8, "", none) }
            let arm = c.aggregate_fields[field_index]
            if arm.ty.kind != .Void && !component_supplied(c, arm.ty, protocol) { ret (2u8, arm.name, arm.ty) }
            at += 1usize
        }
        ret (0u8, "", none)
    }
    if canonical.kind == .Array || canonical.kind == .Slice || canonical.kind == .String {
        let (element, element_error) = index_element_type(c, canonical, canonical.module_index)
        if element_error != ok { ret (0u8, "", none) }
        if !component_supplied(c, element, protocol) { ret (3u8, "", element) }
        ret (0u8, "", none)
    }
    if canonical.kind == .Float || canonical.kind == .Pointer || canonical.kind == .Function { ret (4u8, "", canonical) }
    ret (0u8, "", none)
}

fn component_supplied(c: *Checker, ty: Type, protocol: str) -> bool {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok { ret false }
    if same(protocol, "cmp") { ret comparable_component(c, ty, canonical, 1usize) }
    if same(protocol, "eq") { ret equatable_component(c, ty, canonical, 1usize) }
    if same(protocol, "hash") { ret hashable_component(c, ty, canonical, 1usize) }
    ret false
}

// A function of the protocol's name for the type declared in a module that is not
// the type's own (D430): rule 4 never reads it, and a harness is told so.
fn foreign_protocol_candidate(c: *Checker, canonical: Type, protocol: str) -> usize {
    var at = 0usize
    while at < c.signature_function_count {
        let candidate = c.functions[at]
        if candidate.module_index != canonical.module_index && protocol_name_matches(canonical.name, candidate.name, protocol) { ret at }
        at += 1usize
    }
    ret c.function_count
}

fn record_explain_dispatch(c: *Checker, module_index: usize, node: syntax.Node, protocol: str, receiver: Type, function_index: usize, found: bool, builtin: ProtocolBuiltin) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    var owner_instance = c.function_count
    if c.active_owner_set { owner_instance = c.active_instance }
    c.explains[c.explain_count] = Explain { kind: 1u8, module_index: module_index, offset: offset, protocol: protocol, receiver: receiver, function_index: function_index, found: found, builtin: builtin, template_index: owner_instance, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    if !found && builtin == .None {
        let (reason_kind, reason_name, reason_type) = dispatch_refusal(c, receiver, protocol)
        c.explains[c.explain_count].reason_kind = reason_kind
        c.explains[c.explain_count].reason_name = reason_name
        c.explains[c.explain_count].reason_type = reason_type
        c.explains[c.explain_count].candidate_index = foreign_protocol_candidate(c, receiver, protocol)
    } else {
        c.explains[c.explain_count].candidate_index = c.function_count
    }
    c.explain_count += 1usize
}

// A call evaluated at compile time (D510, H17): a constant's initializer calls the
// function, which no body check sees, so `uses-file`, the plans and the impact walk
// missed a function only a constant reaches -- a rename plan left its call behind.
// The record is a `call` at the call's site, as a body's would be.
fn record_explain_comptime_call(c: *Checker, expression: ConstantExpr) {
    if c.explains.len == 0usize { ret }
    let (function_index, found) = find_function(c, expression.module_index, expression.name)
    if !found { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    c.explains[c.explain_count] = Explain { kind: 4u8, module_index: expression.site_module, offset: expression.site_offset, protocol: "", receiver: invalid_type(), function_index: function_index, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

// A settled control expression (D463, D670, H06): the condition was answered at
// compile time and one arm is not code; `found` is whether the first arm stands.
fn record_explain_fold(c: *Checker, module_index: usize, node: syntax.Node, construct: str, taken: bool) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 8u8, module_index: module_index, offset: offset, protocol: construct, receiver: invalid_type(), function_index: 0usize, found: taken, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

// A resource consumed (D486, H17): the local's name at the site -- closed, returned,
// rebound or handed to an `own` parameter -- for `context-file`'s `move` facts.
fn record_explain_move(c: *Checker, module_index: usize, node: syntax.Node, name: str) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 9u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: 0usize, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: name, reason_type: invalid_type() }
    c.explain_count += 1usize
}

// A view taken (D487, H17): the local bound to `&x`, `x[a..b]`, `x.items` or a
// literal holding `&x`, and the local it views, for `context-file`'s `borrow` facts.
fn record_explain_borrow(c: *Checker, module_index: usize, node: syntax.Node, name: str, viewed: str) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 10u8, module_index: module_index, offset: offset, protocol: viewed, receiver: invalid_type(), function_index: 0usize, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: name, reason_type: invalid_type() }
    c.explain_count += 1usize
}

// A view ended (D501, H02): the local whose view the call ends -- a `mem.reset` of
// the region it was taken in (1), or a call given the container by mutable pointer
// (2) -- for `context-file`'s facts, at the call.
fn record_explain_view_end(c: *Checker, module_index: usize, node: syntax.Node, name: str, how: u8) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 11u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: 0usize, found: false, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: how, reason_name: name, reason_type: invalid_type() }
    c.explain_count += 1usize
}

// The first request of an instance (D466): kept as its site; later requests of the
// same instance leave it.
fn note_instance_site(c: *Checker, instance_index: usize, module_index: usize, node: syntax.Node) {
    if instance_index >= c.function_count || c.function_generics[instance_index].has_site { ret }
    if usize(node.token_start) >= c.token_count { ret }
    c.function_generics[instance_index].site_module = module_index
    c.function_generics[instance_index].site_offset = c.tokens[usize(node.token_start)].start
    c.function_generics[instance_index].site_function = 4294967295u32
    if c.active_owner_set && c.active_instance < c.function_count { c.function_generics[instance_index].site_function = u32(c.active_instance) }
    c.function_generics[instance_index].has_site = true
}

fn record_explain_instance(c: *Checker, module_index: usize, node: syntax.Node, template_index: usize, instance_index: usize, first_argument: usize, argument_count: usize) {
    if c.explains.len == 0usize { ret }
    if c.explain_count >= c.explains.len {
        c.explain_overflow = true
        ret
    }
    var offset = 0usize
    if usize(node.token_start) < c.token_count { offset = c.tokens[usize(node.token_start)].start }
    c.explains[c.explain_count] = Explain { kind: 2u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: instance_index, found: false, builtin: .None, template_index: template_index, first_argument: first_argument, argument_count: argument_count, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
    c.explain_count += 1usize
}

fn protocol_function(c: *Checker, receiver: Type, protocol: str) -> (usize, bool, err) {
    let (canonical, canonical_error) = canonical_type(c, receiver)
    if canonical_error != ok { ret (0usize, false, canonical_error) }
    if canonical.kind != .Named { ret (0usize, false, ok) }
    var at = 0usize
    while at < c.signature_function_count {
        let candidate = c.functions[at]
        if candidate.module_index == canonical.module_index && protocol_name_matches(canonical.name, candidate.name, protocol) { ret (at, true, ok) }
        at += 1usize
    }
    ret (0usize, false, ok)
}

// An element inside a sequence reaches its comparison as an ordinary call when its
// own module declares one, so the sequence's supplied `cmp` covers `[]Point` as
// well as `[]i64`. The declaration has to match rule 3 exactly -- two parameters of
// the type by value, one `i32` back -- because nothing re-checks it at the call
// this synthesizes. A receiver's own `cmp` never reaches here: `check_protocol_call`
// resolves a declared one before any fallback is considered.
fn element_cmp_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "cmp", make_type(.Integer, "i32", ty.module_index), 2usize)
    ret (index, found)
}

fn element_eq_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "eq", make_type(.Bool, "bool", ty.module_index), 2usize)
    ret (index, found)
}

fn element_hash_function(c: *Checker, ty: Type) -> (usize, bool) {
    let (index, found) = component_protocol_function(c, ty, "hash", make_type(.Integer, "u64", ty.module_index), 1usize)
    ret (index, found)
}

fn component_protocol_function(c: *Checker, ty: Type, protocol: str, expected_return: Type, arity: usize) -> (usize, bool) {
    let (canonical, canonical_error) = canonical_type(c, ty)
    if canonical_error != ok || canonical.kind != .Named { ret (0usize, false) }
    let (function_index, found, lookup_error) = protocol_function(c, ty, protocol)
    if lookup_error != ok || !found { ret (0usize, false) }
    let function = c.functions[function_index]
    if function.generic || function.parameter_count != arity || function.return_count != 1usize { ret (0usize, false) }
    if function.first_parameter + arity > c.parameter_count { ret (0usize, false) }
    var at = 0usize
    while at < arity {
        if !type_equal(c, c.parameters[function.first_parameter + at].ty, canonical) { ret (0usize, false) }
        at += 1usize
    }
    let (return_type, return_error) = function_return(c, function, 0usize)
    if return_error != ok || !type_equal(c, return_type, expected_return) { ret (0usize, false) }
    ret (function_index, true)
}

// Spec section 9 rule 4 supplies `cmp` for the scalar shapes, and for arrays,
// slices and vectors it recurses in index order. Rule 4 excludes pointers; floats
// and tagged unions are shapes rule 4 covers that are not supplied yet. The depth
// bound keeps a pathological alias chain from recursing without end; no honest
// type reaches it.
fn supplied_cmp_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind == .Named { ret tagged_union_comparable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret comparable_component(c, element, canonical_element, depth + 1usize)
}

// A component inside a sequence or a tagged union compares either through a shape
// rule 4 supplies or through its own module's declaration, in that order of
// discovery but with the declaration winning at emission (rule 4 again).
fn comparable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_cmp_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_cmp_function(c, ty)
    ret has_component_function
}

fn is_tagged_union_type(c: *Checker, ty: Type) -> bool {
    if ty.kind != .Named { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    ret found && c.aggregates[aggregate_index].kind == .TaggedUnion
}

// Rule 4 orders a tagged union by its tag and then by the live payload, so every
// arm that carries one has to be comparable. A void arm carries nothing and is
// equal to itself once the tags match.
fn tagged_union_comparable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !comparable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

// Rule 4 hashes a value's canonical little-endian bytes with xxHash64 seed 0, and
// recurses into arrays and slices in index order. Where every leaf is one of these
// shapes that recursion *is* the memory: the elements sit contiguously in exactly
// those bytes, so hashing the whole run in one pass is the same answer as walking
// it. A nested slice, whose bytes are a pointer rather than its contents, and a
// tagged union, whose payload is padded, are rule 4 shapes not supplied yet.
fn packed_hash_bytes(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err || ty.kind == .Pointer { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind != .Array { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret packed_hash_bytes(c, canonical_element, depth + 1usize)
}

// A slice hashes over its contents, which rule 4 states outright for `str`. This is
// the exact condition under which the whole value is one contiguous run of canonical
// bytes and can be hashed in a single pass.
fn hash_packed_shape(c: *Checker, ty: Type) -> bool {
    if packed_hash_bytes(c, ty, 0usize) { ret true }
    if ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret packed_hash_bytes(c, canonical_element, 1usize)
}

// Everything else recurses in index or declaration order the way rule 4's other
// shapes do, folding one hash per component rather than hashing one byte run.
fn supplied_hash_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if hash_packed_shape(c, ty) { ret true }
    if ty.kind == .Named { ret tagged_union_hashable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret hashable_component(c, element, canonical_element, depth + 1usize)
}

fn hashable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_hash_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_hash_function(c, ty)
    ret has_component_function
}

fn tagged_union_hashable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !hashable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

fn supplied_eq_shape(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 8usize { ret false }
    if ty.kind == .Integer || ty.kind == .Bool || ty.kind == .Err || ty.kind == .Pointer || ty.kind == .Float { ret true }
    let (enum_backing, is_enum) = enum_backing_type(c, ty)
    if is_enum && enum_backing.kind == .Integer { ret true }
    if ty.kind == .Named { ret tagged_union_equatable(c, ty, depth) }
    if ty.kind != .Array && ty.kind != .Slice && ty.kind != .String { ret false }
    let (element, element_error) = index_element_type(c, ty, ty.module_index)
    if element_error != ok { ret false }
    let (canonical_element, canonical_error) = canonical_type(c, element)
    if canonical_error != ok { ret false }
    ret equatable_component(c, element, canonical_element, depth + 1usize)
}

fn equatable_component(c: *Checker, ty: Type, canonical: Type, depth: usize) -> bool {
    if supplied_eq_shape(c, canonical, depth) { ret true }
    let (component_function, has_component_function) = element_eq_function(c, ty)
    ret has_component_function
}

fn tagged_union_equatable(c: *Checker, ty: Type, depth: usize) -> bool {
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found || c.aggregates[aggregate_index].kind != .TaggedUnion { ret false }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.backing_type.kind != .Integer { ret false }
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret false }
        let arm = c.aggregate_fields[field_index]
        if arm.ty.kind != .Void {
            let (canonical_arm, canonical_arm_error) = canonical_type(c, arm.ty)
            if canonical_arm_error != ok { ret false }
            if !equatable_component(c, arm.ty, canonical_arm, depth + 1usize) { ret false }
        }
        at += 1usize
    }
    ret true
}

fn supplied_protocol(c: *Checker, canonical: Type, protocol: str) -> ProtocolBuiltin {
    if same(protocol, "cmp") {
        if supplied_cmp_shape(c, canonical, 0usize) { ret .Cmp }
        ret .None
    }
    if same(protocol, "hash") {
        if supplied_hash_shape(c, canonical, 0usize) { ret .Hash }
        ret .None
    }
    if same(protocol, "eq") {
        if supplied_eq_shape(c, canonical, 0usize) { ret .Eq }
        ret .None
    }
    ret .None
}

fn supplied_protocol_parameters(builtin: ProtocolBuiltin) -> usize {
    if builtin == .Hash { ret 1usize }
    ret 2usize
}

fn check_protocol_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, receiver: Type, protocol: str) -> (usize, ProtocolBuiltin, err) {
    let (canonical, canonical_error) = canonical_type(c, receiver)
    if canonical_error != ok { ret (0usize, .None, canonical_error) }
    var found = false
    var function_index = 0usize
    if canonical.kind == .Named {
        let (declared_index, declared, lookup_error) = protocol_function(c, receiver, protocol)
        if lookup_error != ok { ret (0usize, .None, lookup_error) }
        found = declared
        function_index = declared_index
    }
    if !found {
        // Rule 4: a declaration in the type's own module always wins over the
        // supplied one, so this is only reached when there is none.
        let builtin = supplied_protocol(c, canonical, protocol)
        record_explain_dispatch(c, module_index, node, protocol, canonical, 0usize, false, builtin)
        if builtin != .None { ret (0usize, builtin, ok) }
        if !c.failure_has_token {
            c.failure_candidate = foreign_protocol_candidate(c, canonical, protocol)
            c.failure_candidate_module = ""
            if c.failure_candidate < c.function_count && c.functions[c.failure_candidate].module_index < g.count { c.failure_candidate_module = g.modules[c.functions[c.failure_candidate].module_index].name }
        }
        record_failure(c, module_index, node, .ProtocolMissing, canonical.name, protocol)
        ret (0usize, .None, UnknownCallable)
    }
    record_explain_dispatch(c, module_index, node, protocol, canonical, function_index, true, .None)
    var function = c.functions[function_index]
    if function.generic {
        // A generic type's protocol is generic with it -- `iter_next[T]` for `Iter[T]` -- and
        // the receiver instance already holds the arguments it was made with. They bind the
        // function's parameters in order, which is the one convention every `<t>_next` in
        // `lib/e` follows, so `Iter[i64].next` is `iter_next[i64]` (D145).
        let (aggregate_index, found_aggregate) = aggregate_for_type(c, canonical)
        if !found_aggregate || !c.aggregates[aggregate_index].instance {
            record_failure(c, module_index, node, .ProtocolGenericType, canonical.name, protocol)
            ret (0usize, .None, Unsupported)
        }
        let aggregate = c.aggregates[aggregate_index]
        if c.function_generics[function_index].comptime_count != aggregate.comptime_count {
            record_failure(c, module_index, node, .ProtocolGenericType, canonical.name, protocol)
            ret (0usize, .None, Unsupported)
        }
        let (instance_index, instance_error) = instantiate_function(c, instance_owner(c, module_index), function_index, aggregate.first_argument)
        if instance_error != ok { ret (0usize, .None, instance_error) }
        note_instance_site(c, instance_index, module_index, node)
        function_index = instance_index
        function = c.functions[instance_index]
    }
    var expected_receiver = canonical
    if same(protocol, "next") || same(protocol, "next_err") {
        let (stored_receiver, store_error) = store_type(c, canonical)
        if store_error != ok { ret (0usize, .None, store_error) }
        expected_receiver = make_type(.Pointer, "", canonical.module_index)
        expected_receiver.element = stored_receiver
        expected_receiver.has_element = true
    }
    // Rule 3: the first parameter is the receiver type, by value -- except for the iterator
    // protocol, whose receiver is the iterator itself and advances, so it is a pointer to one.
    if function.parameter_count == 0usize || function.first_parameter >= c.parameter_count {
        let signature_error = record_protocol_signature_types(c, function, expected_receiver)
        if signature_error != ok { ret (0usize, .None, signature_error) }
        record_failure(c, module_index, node, .ProtocolSignature, canonical.name, function.name)
        ret (0usize, .None, InvalidType)
    }
    if !type_equal(c, c.parameters[function.first_parameter].ty, expected_receiver) {
        let signature_error = record_protocol_signature_types(c, function, expected_receiver)
        if signature_error != ok { ret (0usize, .None, signature_error) }
        record_failure(c, module_index, node, .ProtocolSignature, canonical.name, function.name)
        ret (0usize, .None, InvalidType)
    }
    ret (function_index, .None, ok)
}

fn function_return(c: *Checker, function: Function, index: usize) -> (Type, err) {
    if index >= function.return_count || function.first_return + index >= c.return_type_count { ret (invalid_type(), InvalidType) }
    ret (c.return_types[function.first_return + index], ok)
}

fn call_return(c: *Checker, call: CallInfo, index: usize) -> (Type, err) {
    // The address the lookup answers with, under the type the caller asked for. The second
    // result is the lookup's own `err` and is read from its signature like any other.
    if call.dl_symbol && index == 0usize { ret (call.cast, ok) }
    if call.indirect {
        let (signature, has_signature) = function_signature_of(c, call.indirect_type)
        if !has_signature { ret (invalid_type(), InvalidType) }
        let (result, has_result) = function_signature_return(c, signature, index)
        if !has_result { ret (invalid_type(), InvalidType) }
        ret (result, ok)
    }
    if call.protocol_builtin == .Cmp {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Integer, "i32", call.protocol_type.module_index), ok)
    }
    if call.protocol_builtin == .Hash {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Integer, "u64", call.protocol_type.module_index), ok)
    }
    if call.protocol_builtin == .Eq {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.Bool, "bool", call.protocol_type.module_index), ok)
    }
    if call.protocol_pending {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (make_type(.TypeParameter, "", 0usize), ok)
    }
    if index >= call.function.return_count { ret (invalid_type(), InvalidType) }
    if call.mem_cast || call.mem_bitcast || call.mem_address || call.math_sqrt {
        if index != 0usize { ret (invalid_type(), InvalidType) }
        ret (call.cast, ok)
    }

    if call.thread_create {
        if index == 0usize { ret (call.alloc_return, ok) }
        if index == 1usize { ret (make_type(.Err, "err", call.function.module_index), ok) }
        ret (invalid_type(), ArgumentCount)
    }
    if call.meta_query != .None {
        if index == 0usize { ret (call.meta_result, ok) }
        ret (invalid_type(), ArgumentCount)
    }
    if call.mem_alloc {
        if index == 0usize { ret (call.alloc_return, ok) }
        if index == 1usize { ret (make_type(.Err, "err", call.function.module_index), ok) }
        ret (invalid_type(), InvalidType)
    }
    // `get` gives back the field's own type -- section 9's dependent return -- and
    // `set` gives nothing.
    if call.meta_access {
        if call.meta_writes || index != 0usize { ret (invalid_type(), InvalidType) }
        ret (call.meta_field.ty, ok)
    }
    // Section 8: `init` gives the `Atomic[T]` back, `cas` the pair, and every other
    // operation with a result gives the `T` it read.
    if call.atomic_op != .None {
        if index != 0usize && !(call.atomic_op == .Cas && index == 1usize) { ret (invalid_type(), InvalidType) }
        if call.atomic_op == .Cas {
            if index == 0usize { ret (make_type(.Bool, "bool", call.function.module_index), ok) }
            ret (call.atomic_element, ok)
        }
        if call.atomic_op == .Init { ret (atomic_wrapper_type(c, call.atomic_element, call.function.module_index), ok) }
        ret (call.atomic_element, ok)
    }
    let (result, result_error) = function_return(c, call.function, index)
    ret (result, result_error)
}

fn call_is_fallible(c: *Checker, call: CallInfo) -> bool {
    if call.function.return_count == 0usize { ret false }
    let (last, last_error) = call_return(c, call, call.function.return_count - 1usize)
    if last_error != ok { ret false }
    ret last.kind == .Err
}

type BracketInfo = struct {
    base: usize,
    first: usize,
    second: usize,
    child_count: usize,
    range: bool,
}

fn read_bracket(c: *Checker, tree: *parse.Tree, node: syntax.Node, info: *BracketInfo) -> err {
    if node.kind != .BracketPostfix { ret parse.InvalidSyntax }
    info.base = 0usize
    info.first = 0usize
    info.second = 0usize
    info.child_count = 0usize
    info.range = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if usize(info.child_count) == 0usize { info.base = child_index }
            if usize(info.child_count) == 1usize { info.first = child_index }
            if usize(info.child_count) == 2usize { info.second = child_index }
            info.child_count += 1usize
        }
        at += 1usize
    }
    if usize(info.child_count) == 0usize { ret parse.InvalidSyntax }
    let base = tree.nodes[info.base]
    at = usize(base.token_end)
    while at < usize(node.token_end) {
        if c.tokens[at].kind == .PunctRange { info.range = true }
        at += 1usize
    }
    ret ok
}

fn index_element_type(c: *Checker, base: Type, module_index: usize) -> (Type, err) {
    if base.kind == .String { ret (make_type(.Integer, "u8", module_index), ok) }
    // Section 4: `v[i]` reads or writes one lane of a vector, bounds-checked like an
    // array's element; a vector still generic answers with a placeholder.
    if vector_pending(c, base) { ret (make_type(.TypeParameter, "", module_index), ok) }
    let (lane, is_vector) = vector_lane_type(c, base)
    if is_vector { ret (lane, ok) }
    if base.kind != .Array && base.kind != .Slice { ret (invalid_type(), InvalidOperator) }
    if !base.has_element || base.element >= c.type_count { ret (invalid_type(), InvalidType) }
    ret (c.types[base.element], ok)
}

fn dependent_expression_type(source: Type, expected: Type, module_index: usize) -> Type {
    if expected.kind != .Invalid { ret expected }
    if source.kind == .TypeParameter { ret source }
    ret make_type(.TypeParameter, "", module_index)
}

fn literal_item_name(c: *Checker, text: str, item: syntax.Node) -> (str, bool) {
    var at = usize(item.token_start)
    while at < usize(item.token_end) {
        let token = c.tokens[at]
        if token.kind == .PunctColon { break }
        if token.kind == .Identifier { ret (text[token.start..token.end], true) }
        at += 1usize
    }
    ret ("", false)
}

fn literal_item_expression(tree: *parse.Tree, item: syntax.Node) -> (usize, bool) {
    let (expression, found) = first_node_child(tree, item)
    ret (expression, found)
}

fn literal_item_named(c: *Checker, tree: *parse.Tree, item: syntax.Node) -> bool {
    let (expression, has_expression) = literal_item_expression(tree, item)
    if !has_expression { ret false }
    var at = usize(item.token_start)
    let expression_start = usize(tree.nodes[expression].token_start)
    while at < expression_start {
        if c.tokens[at].kind == .PunctColon { ret true }
        at += 1usize
    }
    ret false
}

fn aggregate_literal_header(tree: *parse.Tree, node: syntax.Node) -> (usize, usize, err) {
    var header = 0usize
    var has_header = false
    var item_count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind == .LiteralItem {
                item_count += 1usize
            } else {
                if has_header { ret (0usize, 0usize, parse.InvalidSyntax) }
                header = child_index
                has_header = true
            }
        }
        at += 1usize
    }
    if !has_header || item_count == 0usize { ret (0usize, 0usize, parse.InvalidSyntax) }
    ret (header, item_count, ok)
}

fn check_array_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, header_index: usize, item_count: usize, expected: Type) -> (Type, err) {
    let header = tree.nodes[header_index]
    if header.kind != .ArrayType { ret (invalid_type(), InvalidType) }
    var element_index = 0usize
    var has_element = false
    let header_end = usize(header.first_child) + usize(header.child_count)
    var at = usize(header.first_child)
    while at < header_end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if is_type_node(tree.nodes[child_index].kind) {
                element_index = child_index
                has_element = true
            }
        }
        at += 1usize
    }
    if !has_element { ret (invalid_type(), parse.InvalidSyntax) }
    let (element, element_error) = type_from_node(c, c.resolver, g, tree, module_index, tree.nodes[element_index])
    if element_error != ok { ret (invalid_type(), element_error) }
    if element.kind == .Void { ret (invalid_type(), InvalidType) }
    let inferred = contains_token(c, usize(header.token_start), usize(header.token_end), .PunctUnderscore)
    var array = invalid_type()
    if inferred {
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        array = make_type(.Array, "", module_index)
        array.element = stored_element
        array.has_element = true
        array.array_length = item_count
        array.has_length = true
    } else {
        let (declared, declared_error) = type_from_node(c, c.resolver, g, tree, module_index, header)
        if declared_error != ok { ret (invalid_type(), declared_error) }
        if !declared.has_length {
            if !c.generic_declaration { ret (invalid_type(), TypeMismatch) }
        } else {
            if declared.array_length != item_count {
                record_failure(c, module_index, node, .ArrayElementCount, "", "")
                ret (invalid_type(), TypeMismatch)
            }
        }
        array = declared
    }
    let end = usize(node.first_child) + usize(node.child_count)
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                if literal_item_named(c, tree, item) { ret (invalid_type(), InvalidType) }
                let (expression, has_expression) = literal_item_expression(tree, item)
                if !has_expression { ret (invalid_type(), parse.InvalidSyntax) }
                let (_, expression_error) = check_expr(c, g, tree, module_index, expression, element)
                if expression_error != ok { ret (invalid_type(), expression_error) }
            }
        }
        at += 1usize
    }
    let (contextual, context_error) = apply_context(c, array, expected)
    ret (contextual, context_error)
}

fn aggregate_field_for_name(c: *Checker, aggregate: Aggregate, name: str) -> (usize, bool) {
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count && same(c.aggregate_fields[field_index].name, name) { ret (field_index, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn literal_name_seen(c: *Checker, text: str, tree: *parse.Tree, node: syntax.Node, before_child: usize, name: str) -> bool {
    var at = usize(node.first_child)
    while at < before_child {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                let (previous, found) = literal_item_name(c, text, item)
                if found && same(previous, name) { ret true }
            }
        }
        at += 1usize
    }
    ret false
}

fn check_named_aggregate_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, header_index: usize, item_count: usize, expected: Type) -> (Type, err) {
    let header = tree.nodes[header_index]
    if header.kind != .NamedType { ret (invalid_type(), InvalidType) }
    let (constructed_type, type_error) = type_from_node(c, c.resolver, g, tree, module_index, header)
    if type_error != ok { ret (invalid_type(), type_error) }
    if constructed_type.kind != .Named { ret (invalid_type(), InvalidType) }
    var aggregate_index = 0usize
    var found_aggregate = false
    if constructed_type.has_element && constructed_type.element < c.aggregate_count {
        aggregate_index = constructed_type.element
        found_aggregate = true
    } else {
        (aggregate_index, found_aggregate) = find_aggregate(c, constructed_type.module_index, constructed_type.name)
    }
    if !found_aggregate { ret (invalid_type(), InvalidType) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance {
        if aggregate.template_index >= c.aggregate_count { ret (invalid_type(), InvalidType) }
        aggregate = c.aggregates[aggregate.template_index]
    }
    if aggregate.generic && !c.generic_declaration { ret (invalid_type(), Unsupported) }
    if aggregate.kind == .Enum { ret (invalid_type(), InvalidType) }
    if aggregate.kind == .Struct && item_count != aggregate.field_count {
        record_failure(c, module_index, node, .AggregateFieldCount, aggregate.name, "")
        ret (invalid_type(), ArgumentCount)
    }
    if aggregate.kind != .Struct && item_count != 1usize {
        record_failure(c, module_index, node, .AggregateFieldCount, aggregate.name, "")
        ret (invalid_type(), ArgumentCount)
    }
    let text = g.modules[module_index].text
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                let (name, has_name) = literal_item_name(c, text, item)
                if !has_name { ret (invalid_type(), InvalidType) }
                if literal_name_seen(c, text, tree, node, at, name) { ret (invalid_type(), ArgumentCount) }
                let (field_index, found_field) = aggregate_field_for_name(c, aggregate, name)
                if !found_field { ret (invalid_type(), InvalidType) }
                // The literal's naming of the field, for the uses query (D420).
                if usize(item.token_start) < c.token_count { record_explain_field(c, module_index, c.tokens[usize(item.token_start)].start, field_index) }
                let field = c.aggregate_fields[field_index]
                let (expression, has_expression) = literal_item_expression(tree, item)
                let named = literal_item_named(c, tree, item)
                if aggregate.kind == .TaggedUnion && field.ty.kind == .Void {
                    if named || has_expression { ret (invalid_type(), TypeMismatch) }
                } else {
                    if !named || !has_expression { ret (invalid_type(), TypeMismatch) }
                    let (_, expression_error) = check_expr(c, g, tree, module_index, expression, field.ty)
                    if expression_error != ok { ret (invalid_type(), expression_error) }
                }
            }
        }
        at += 1usize
    }
    let (contextual, context_error) = apply_context(c, constructed_type, expected)
    ret (contextual, context_error)
}

fn check_aggregate_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, expected: Type) -> (Type, err) {
    let (header_index, item_count, header_error) = aggregate_literal_header(tree, node)
    if header_error != ok { ret (invalid_type(), header_error) }
    if tree.nodes[header_index].kind == .ArrayType {
        let (array, array_error) = check_array_literal(c, g, tree, module_index, node, header_index, item_count, expected)
        ret (array, array_error)
    }
    if tree.nodes[header_index].kind == .NamedType {
        let (named, named_error) = type_from_node(c, c.resolver, g, tree, module_index, tree.nodes[header_index])
        if named_error == ok && is_vector_type(c, named) {
            let (vector, vector_error) = check_vector_literal(c, g, tree, module_index, node, named, item_count, expected)
            ret (vector, vector_error)
        }
    }
    let (aggregate, aggregate_error) = check_named_aggregate_literal(c, g, tree, module_index, node, header_index, item_count, expected)
    ret (aggregate, aggregate_error)
}

// Section 4: `Vec[i32, 4]{ 1, 2, 3, 4 }` -- one unnamed item per lane, each of the lane
// type, exactly `N` of them. Inside a generic the vector may still be `Vec[T, N]`, and
// then the count and the lane type wait for the instance.
fn check_vector_literal(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, vector: Type, item_count: usize, expected: Type) -> (Type, err) {
    var lane = make_type(.TypeParameter, "", module_index)
    if !vector_pending(c, vector) {
        let (lanes, is_vector) = vector_lanes(c, vector)
        let (lane_type, has_lane) = vector_lane_type(c, vector)
        if !is_vector || !has_lane { ret (invalid_type(), InvalidType) }
        if lanes.array_length != item_count {
            record_failure(c, module_index, node, .ArrayElementCount, "", "")
            ret (invalid_type(), TypeMismatch)
        }
        lane = lane_type
    }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                if literal_item_named(c, tree, item) { ret (invalid_type(), InvalidType) }
                let (expression, has_expression) = literal_item_expression(tree, item)
                if !has_expression { ret (invalid_type(), parse.InvalidSyntax) }
                let (_, expression_error) = check_expr(c, g, tree, module_index, expression, lane)
                if expression_error != ok { ret (invalid_type(), expression_error) }
            }
        }
        at += 1usize
    }
    let (contextual, context_error) = apply_context(c, vector, expected)
    ret (contextual, context_error)
}

fn direct_place_mutable(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, err) {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .Identifier { ret (false, Unsupported) }
        let name = g.modules[module_index].text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if found { ret (c.locals[local_index].mutable, ok) }
        // A module-scope `var` is mutable by the keyword that declares it, so an element or a
        // field of one is assignable wherever the variable is visible.
        let (global_index, global_found) = find_global(c, module_index, name)
        if global_found { ret (true, ok) }
        ret (false, Unsupported)
    }
    if node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (false, parse.InvalidSyntax) }
        let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if pointer_error != ok { ret (false, pointer_error) }
        if pointer.kind != .Pointer {
            if c.generic_declaration && type_shape_unknown(pointer) { ret (true, ok) }
            ret (false, InvalidOperator)
        }
        ret (!pointer.is_const, ok)
    }
    if node.kind == .BracketPostfix {
        var bracket: BracketInfo = zero
        let bracket_error = read_bracket(c, tree, node, &bracket)
        if bracket_error != ok { ret (false, bracket_error) }
        if bracket.range || usize(bracket.child_count) != 2usize { ret (false, Unsupported) }
        let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
        if base_error != ok { ret (false, base_error) }
        if c.generic_declaration && type_shape_unknown(base) { ret (true, ok) }
        if base.kind == .Slice { ret (!base.is_const, ok) }
        if base.kind == .String { ret (false, ok) }
        if base.kind != .Array && !is_vector_type(c, base) { ret (false, InvalidOperator) }
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
        ret (mutable, mutable_error)
    }
    if node.kind == .FieldExpr {
        let (base_index, has_base) = first_node_child(tree, node)
        if !has_base { ret (false, parse.InvalidSyntax) }
        let (base, base_error) = check_expr(c, g, tree, module_index, base_index, invalid_type())
        if base_error != ok { ret (false, base_error) }
        if c.generic_declaration && type_shape_unknown(base) { ret (true, ok) }
        var subject = base
        var through_pointer = false
        var mutable = false
        while subject.kind == .Pointer {
            if !subject.has_element || subject.element >= c.type_count { ret (false, InvalidType) }
            through_pointer = true
            mutable = !subject.is_const
            subject = c.types[subject.element]
        }
        if through_pointer { ret (mutable, ok) }
        let (base_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, base_index)
        ret (base_mutable, mutable_error)
    }
    ret (false, Unsupported)
}

fn check_bracket_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, expected: Type) -> (Type, err) {
    var bracket: BracketInfo = zero
    let bracket_error = read_bracket(c, tree, node, &bracket)
    if bracket_error != ok { ret (invalid_type(), bracket_error) }
    let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
    if base_error != ok { ret (invalid_type(), base_error) }
    let (element, element_error) = index_element_type(c, base, module_index)
    let index_type = make_type(.Integer, "usize", module_index)
    if element_error != ok {
        if !c.generic_declaration || !type_shape_unknown(base) { ret (invalid_type(), element_error) }
        if bracket.range {
            if usize(bracket.child_count) > 3usize { ret (invalid_type(), ArgumentCount) }
            if usize(bracket.child_count) >= 2usize {
                let (_, first_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
                if first_error != ok { ret (invalid_type(), first_error) }
            }
            if usize(bracket.child_count) == 3usize {
                let (_, second_error) = check_expr(c, g, tree, module_index, bracket.second, index_type)
                if second_error != ok { ret (invalid_type(), second_error) }
            }
            let dependent = dependent_expression_type(base, invalid_type(), module_index)
            let (stored_element, store_error) = store_type(c, dependent)
            if store_error != ok { ret (invalid_type(), store_error) }
            var result = make_type(.Slice, "", module_index)
            result.element = stored_element
            result.has_element = true
            let (contextual, context_error) = apply_context(c, result, expected)
            ret (contextual, context_error)
        }
        if usize(bracket.child_count) != 2usize { ret (invalid_type(), ArgumentCount) }
        let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
        if index_error != ok { ret (invalid_type(), index_error) }
        ret (dependent_expression_type(base, expected, module_index), ok)
    }
    if bracket.range {
        if usize(bracket.child_count) > 3usize { ret (invalid_type(), ArgumentCount) }
        if usize(bracket.child_count) >= 2usize {
            let (_, first_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
            if first_error != ok { ret (invalid_type(), first_error) }
        }
        if usize(bracket.child_count) == 3usize {
            let (_, second_error) = check_expr(c, g, tree, module_index, bracket.second, index_type)
            if second_error != ok { ret (invalid_type(), second_error) }
        }
        let (stored_element, store_error) = store_type(c, element)
        if store_error != ok { ret (invalid_type(), store_error) }
        var result = make_type(.Slice, "", module_index)
        result.element = stored_element
        result.has_element = true
        if base.kind == .String {
            result.is_const = true
        } else {
            if base.kind == .Slice {
                result.is_const = base.is_const
            } else {
                let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
                if mutable_error != ok { ret (invalid_type(), mutable_error) }
                result.is_const = !mutable
            }
        }
        let (contextual, context_error) = apply_context(c, result, expected)
        ret (contextual, context_error)
    }
    if usize(bracket.child_count) != 2usize { ret (invalid_type(), ArgumentCount) }
    let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, index_type)
    if index_error != ok { ret (invalid_type(), index_error) }
    let (contextual, context_error) = apply_context(c, element, expected)
    ret (contextual, context_error)
}

fn is_fallible(c: *Checker, function: Function) -> bool {
    if function.return_count == 0usize { ret false }
    let last = c.return_types[function.first_return + function.return_count - 1usize]
    ret last.kind == .Err
}

// A type's id in the memo, interned by every field `same_expectation` compares;
// false when the table is full, and that answer is simply not kept.
fn memo_intern(c: *Checker, ty: Type) -> (usize, bool) {
    if c.memo_slots.len == 0usize { ret (0usize, false) }
    var h = 1469598103934665603usize
    // The kind is compared, not hashed: an enum does not convert to an integer here.
    h = (h ^ ty.module_index) *% 1099511628211usize
    h = (h ^ ty.element) *% 1099511628211usize
    h = (h ^ ty.array_length) *% 1099511628211usize
    var flags = 0usize
    if ty.has_element { flags += 1usize }
    if ty.is_const { flags += 2usize }
    if ty.has_length { flags += 4usize }
    h = (h ^ flags) *% 1099511628211usize
    var at = 0usize
    while at < ty.name.len {
        h = (h ^ usize(ty.name[at])) *% 1099511628211usize
        at += 1usize
    }
    let mask = c.memo_slots.len - 1usize
    var probe = h & mask
    while true {
        let held = c.memo_slots[probe]
        if held == 0usize {
            if c.memo_type_count * 2usize >= c.memo_slots.len || c.memo_type_count == c.memo_types.len { ret (0usize, false) }
            c.memo_types[c.memo_type_count] = ty
            c.memo_slots[probe] = c.memo_type_count + 1usize
            c.memo_type_count += 1usize
            ret (c.memo_type_count - 1usize, true)
        }
        if same_expectation(c.memo_types[held - 1usize], ty) { ret (held - 1usize, true) }
        probe = (probe + 1usize) & mask
    }
    ret (0usize, false)
}

fn memo_wanted(c: *Checker, module_index: usize, node_index: usize) -> bool {
    if !c.memo_on || c.active_arguments || c.comptime_binding_count != 0usize { ret false }
    ret module_index < c.memo_tables.len && node_index < c.memo_tables[module_index].len
}

// A module's memo, made once its tree is known, before its bodies are checked.
fn memo_module(c: *Checker, module_index: usize, node_count: usize) -> err {
    if !c.memo_on || module_index >= c.memo_tables.len || c.memo_tables[module_index].len != 0usize { ret ok }
    let (table, table_error) = mem.alloc[usize](c.arena, node_count + 1usize)
    if table_error != ok { ret table_error }
    var at = 0usize
    while at < table.len {
        table[at] = 0usize
        at += 1usize
    }
    c.memo_tables[module_index] = table
    ret ok
}

fn check_expr(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (Type, err) {
    if memo_wanted(c, module_index, node_index) {
        // No expectation, the common case, is id 1 without a lookup (D330).
        var expected_key = 1usize
        var expected_known = true
        if expected.kind != .Invalid {
            let (expected_id, interned) = memo_intern(c, expected)
            expected_key = expected_id + 2usize
            expected_known = interned
        }
        let entry = c.memo_tables[module_index][node_index]
        if entry != 0usize && expected_known && (entry >> 32usize) == expected_key { ret (c.memo_types[(entry & 4294967295usize) - 1usize], ok) }
        let (fresh, fresh_error) = check_expr_uncached(c, g, tree, module_index, node_index, expected)
        if fresh_error == ok && expected_known {
            let (result_id, result_known) = memo_intern(c, fresh)
            if result_known { c.memo_tables[module_index][node_index] = (expected_key << 32usize) | (result_id + 1usize) }
        }
        if fresh_error == TypeMismatch { note_mismatch_expression(c, tree, node_index) }
        ret (fresh, fresh_error)
    }
    var slot = 0usize
    var start = 0usize
    var end = 0usize
    if c.expr_cache.len != 0usize && c.call_generation != 0usize {
        start = usize(tree.nodes[node_index].token_start)
        end = usize(tree.nodes[node_index].token_end)
        slot = (start * 31usize + end) % c.expr_cache.len
        let cached = c.expr_cache[slot]
        if cached.generation == c.call_generation && usize(cached.token_start) == start && usize(cached.token_end) == end && same_expectation(cached.expected, expected) { ret (cached.result, ok) }
    }
    let (fresh, fresh_error) = check_expr_uncached(c, g, tree, module_index, node_index, expected)
    if fresh_error == ok && c.expr_cache.len != 0usize && c.call_generation != 0usize {
        c.expr_cache[slot] = ExprCacheEntry { generation: c.call_generation, token_start: start, token_end: end, expected: expected, result: fresh }
    }
    if fresh_error == TypeMismatch { note_mismatch_expression(c, tree, node_index) }
    ret (fresh, fresh_error)
}

// The expression a mismatch surfaced at (D444): every frame the error passes
// records itself, so the outermost wins -- a name or a literal keeps its span, and
// so does a whole value (D491, H09): a call, a field read, an index, a group,
// whose conversion converts nothing but its result. An arithmetic expression
// clears it, since which of its parts to convert is a reading.
fn note_mismatch_expression(c: *Checker, tree: *parse.Tree, node_index: usize) {
    if c.failure_expected.kind == .Invalid { ret }
    let node = tree.nodes[node_index]
    let first = usize(node.token_start)
    let last = usize(node.token_end)
    if last <= first || last > c.token_count { ret }
    c.failure_mismatch_end = 0usize
    let whole = node.kind == .CallExpr || node.kind == .FieldExpr || node.kind == .BracketPostfix || node.kind == .GroupExpr
    if last - first == 1usize || whole {
        c.failure_fix_kind = 3u8
        c.failure_fix_at = c.tokens[first].start
        c.failure_mismatch_end = c.tokens[last - 1usize].end
    }
}

fn same_expectation(a: Type, b: Type) -> bool {
    if a.kind != b.kind || a.module_index != b.module_index || a.element != b.element || a.has_element != b.has_element { ret false }
    if a.is_const != b.is_const || a.array_length != b.array_length || a.has_length != b.has_length { ret false }
    ret same(a.name, b.name)
}

fn check_expr_uncached(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, expected: Type) -> (Type, err) {
    let node = tree.nodes[node_index]
    let text = g.modules[module_index].text
    if node.kind == .LiteralExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind == .KwZero || token.kind == .KwUndef {
            if expected.kind == .Invalid { ret (invalid_type(), MissingContext) }
            if token.kind == .KwZero && !type_has_zero_value(c, expected, 0usize) {
                record_failure(c, module_index, node, .MissingZeroValue, expected.name, expected.name)
                ret (invalid_type(), InvalidType)
            }
            if token.kind == .KwUndef {
                let (admits, culprit) = type_has_undef_value(c, expected, 0usize)
                if !admits {
                    record_failure(c, module_index, node, .MissingUndefValue, expected.name, culprit)
                    ret (invalid_type(), InvalidType)
                }
            }
            ret (expected, ok)
        }
        if token.kind == .KwNil {
            if expected.kind == .Pointer || expected.kind == .Slice { ret (expected, ok) }
            ret (invalid_type(), MissingContext)
        }
        let (literal, context_error) = apply_context(c, literal_type(c, text, node), expected)
        ret (literal, context_error)
    }
    if node.kind == .NameExpr {
        let token = c.tokens[usize(node.token_start)]
        if token.kind == .KwUnreachable { ret (make_type(.Void, "void", module_index), ok) }
        let name = text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if found {
            let (local_type, context_error) = apply_context(c, c.locals[local_index].ty, expected)
            ret (local_type, context_error)
        }
        let (parameter_index, parameter_found) = active_comptime_parameter(c, name)
        if parameter_found {
            if c.comptime_parameters[parameter_index].kind == .Function {
                var function_type = c.comptime_parameters[parameter_index].ty
                let (argument, argument_found) = active_argument(c, parameter_index)
                if argument_found { function_type = argument.ty }
                let (contextual_function, function_context_error) = apply_context(c, function_type, expected)
                ret (contextual_function, function_context_error)
            }
            if c.comptime_parameters[parameter_index].kind == .Str {
                let (text_type, text_context_error) = apply_context(c, make_type(.String, "str", module_index), expected)
                ret (text_type, text_context_error)
            }
            if c.comptime_parameters[parameter_index].kind == .Array {
                // The bound literal's own array type; in the template, the declared one.
                var array_type = c.comptime_parameters[parameter_index].ty
                let (array_argument, has_array) = active_argument(c, parameter_index)
                if has_array { array_type = array_argument.ty }
                let (contextual_array, array_context_error) = apply_context(c, array_type, expected)
                ret (contextual_array, array_context_error)
            }
            if c.comptime_parameters[parameter_index].kind != .Integer { ret (invalid_type(), InvalidType) }
            let (argument, argument_found) = active_argument(c, parameter_index)
            if !argument_found {
                if c.generic_declaration {
                    let (parameter_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
                    ret (parameter_type, context_error)
                }
                ret (invalid_type(), MissingContext)
            }
            let (parameter_type, context_error) = apply_context(c, c.comptime_parameters[parameter_index].ty, expected)
            ret (parameter_type, context_error)
        }
        let (constant_index, constant_found) = find_constant(c, module_index, name)
        if constant_found && c.constants[constant_index].state == 2u8 {
            let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
            ret (constant_type, context_error)
        }
        // Mutable static storage, read the way a local is. Nothing about the type depends on
        // where it lives; that only decides how lowering reaches it.
        let (global_index, global_found) = find_global(c, module_index, name)
        if global_found {
            let (global_type, context_error) = apply_context(c, c.globals[global_index].ty, expected)
            ret (global_type, context_error)
        }
        let (symbol_index, found_symbol) = resolve.find(c.resolver, module_index, name, .Value)
        let (intrinsic_function, has_intrinsic_function) = find_function(c, module_index, name)
        if found_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
            if c.resolver.symbols[symbol_index].kind == .Error && usize(node.token_start) < c.token_count { record_explain_error(c, module_index, c.tokens[usize(node.token_start)].start, symbol_index) }
            let (error_type, context_error) = apply_context(c, make_type(.Err, "err", module_index), expected)
            ret (error_type, context_error)
        }
        // Spec section 5: `fn(A) -> R` is a type, so naming a function in a value
        // position yields a pointer to it.
        if has_intrinsic_function {
            let callee = c.functions[intrinsic_function]
            if callee.generic || callee.intrinsic || callee.external { ret (invalid_type(), Unsupported) }
            let (pointer_type, pointer_error) = function_pointer_type(c, callee, module_index)
            if pointer_error != ok { ret (invalid_type(), pointer_error) }
            record_explain_value(c, module_index, node, intrinsic_function)
            let (result_type, context_error) = apply_context(c, pointer_type, expected)
            ret (result_type, context_error)
        }
        ret (invalid_type(), Unsupported)
    }
    if node.kind == .MemberExpr {
        if expected.kind == .Invalid { ret (invalid_type(), MissingContext) }
        let (aggregate_index, found_aggregate) = aggregate_for_type(c, expected)
        if !found_aggregate { ret (invalid_type(), InvalidType) }
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind != .Enum && aggregate.kind != .TaggedUnion { ret (invalid_type(), InvalidType) }
        if expected.kind == .Tag && aggregate.kind != .TaggedUnion { ret (invalid_type(), InvalidType) }
        var member = ""
        var member_at = usize(node.token_start)
        while member_at < usize(node.token_end) {
            let member_token = c.tokens[member_at]
            if member_token.kind == .Identifier { member = text[member_token.start..member_token.end] }
            member_at += 1usize
        }
        let (field_index, found_member) = aggregate_field_for_name(c, aggregate, member)
        if !found_member { ret (invalid_type(), InvalidType) }
        if expected.kind != .Tag && aggregate.kind == .TaggedUnion && c.aggregate_fields[field_index].ty.kind != .Void { ret (invalid_type(), InvalidType) }
        ret (expected, ok)
    }
    if node.kind == .FieldExpr {
        // `target.arch` and `target.os` are values of the seeded enums (D223).
        let (target_question, is_target) = target_member(c, g, tree, module_index, node_index)
        if is_target {
            if !same(target_question, "arch") && !same(target_question, "os") { ret (invalid_type(), InvalidType) }
            let (target_contextual, target_context_error) = apply_context(c, target_enum_type(target_question), expected)
            ret (target_contextual, target_context_error)
        }
        let (bound, bound_member, is_bound) = comptime_binding_base(c, text, tree, node)
        if is_bound {
            let (member_type, has_member) = comptime_binding_member(c, bound, bound_member, module_index)
            if !has_member { ret (invalid_type(), InvalidType) }
            let (contextual, context_error) = apply_context(c, member_type, expected)
            ret (contextual, context_error)
        }
        let (enum_member_type, found_enum_member, enum_target) = static_enum_member(c, g, module_index, node)
        if found_enum_member {
            let (contextual_enum, context_error) = apply_context(c, enum_member_type, expected)
            ret (contextual_enum, context_error)
        }
        if enum_target { ret (invalid_type(), InvalidType) }
        let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
        if found_member {
            let (constant_index, constant_found) = find_constant(c, target_module, member)
            if constant_found && c.constants[constant_index].state == 2u8 {
                let (constant_type, context_error) = apply_context(c, c.constants[constant_index].ty, expected)
                ret (constant_type, context_error)
            }
            let (symbol_index, found_symbol) = resolve.find(c.resolver, target_module, member, .Value)
            let (intrinsic_function, has_intrinsic_function) = find_function(c, target_module, member)
            if found_symbol && (c.resolver.symbols[symbol_index].kind == .Error || (c.resolver.symbols[symbol_index].kind == .Intrinsic && !has_intrinsic_function)) {
                if c.resolver.symbols[symbol_index].kind == .Error && usize(node.token_end) > 0usize && usize(node.token_end) <= c.token_count { record_explain_error(c, module_index, c.tokens[usize(node.token_end) - 1usize].start, symbol_index) }
                let (error_type, context_error) = apply_context(c, make_type(.Err, "err", target_module), expected)
                ret (error_type, context_error)
            }
            // A qualified function named in a value position, like the unqualified
            // case above.
            if has_intrinsic_function {
                let callee = c.functions[intrinsic_function]
                if callee.generic || callee.intrinsic || callee.external { ret (invalid_type(), Unsupported) }
                let (pointer_type, pointer_error) = function_pointer_type(c, callee, target_module)
                if pointer_error != ok { ret (invalid_type(), pointer_error) }
                record_explain_value(c, module_index, node, intrinsic_function)
                let (result_type, context_error) = apply_context(c, pointer_type, expected)
                ret (result_type, context_error)
            }
            ret (invalid_type(), Unsupported)
        }
        let (base_index, has_base) = first_node_child(tree, node)
        if !has_base { ret (invalid_type(), parse.InvalidSyntax) }
        let (field, has_field) = field_expression_name(c, text, tree, node)
        if !has_field { ret (invalid_type(), parse.InvalidSyntax) }
        let (base, base_error) = check_expr(c, g, tree, module_index, base_index, invalid_type())
        if base_error != ok { ret (invalid_type(), base_error) }
        // A resource's representation is its module's alone (D348, E-SAFETY-0010):
        // a field of one read anywhere else, outside an `@unsafe` function, is refused.
        if c.resources_on {
            var opaque_subject = base
            while opaque_subject.kind == .Pointer && opaque_subject.has_element && opaque_subject.element < c.type_count { opaque_subject = c.types[opaque_subject.element] }
            if resource_type(c, opaque_subject) && !seeded_arena(c, opaque_subject) && opaque_subject.module_index != module_index {
                record_failure(c, module_index, node, .ResourceOpaque, opaque_subject.name, "")
                ret (invalid_type(), ResourceViolation)
            }
        }
        if same(field, "len") && (base.kind == .Array || base.kind == .Slice || base.kind == .String) {
            let (length_type, context_error) = apply_context(c, make_type(.Integer, "usize", module_index), expected)
            ret (length_type, context_error)
        }
        if same(field, "tag") {
            let (tag, found_tag) = tagged_union_tag_type(c, base)
            if found_tag {
                let (contextual_tag, context_error) = apply_context(c, tag, expected)
                ret (contextual_tag, context_error)
            }
            if c.generic_declaration && type_shape_unknown(base) { ret (dependent_expression_type(base, expected, module_index), ok) }
        }
        let (field_index, found_field) = find_aggregate_field(c, base, field)
        if !found_field {
            if c.generic_declaration && type_shape_unknown(base) {
                if same(field, "len") {
                    let (length_type, context_error) = apply_context(c, make_type(.Integer, "usize", module_index), expected)
                    ret (length_type, context_error)
                }
                ret (dependent_expression_type(base, expected, module_index), ok)
            }
            note_missing_field(c, module_index, node, base, field)
            ret (invalid_type(), InvalidType)
        }
        // The access, for the uses query (D420, H17): the member's own token.
        if usize(node.token_end) > usize(node.token_start) && usize(node.token_end) - 1usize < c.token_count { record_explain_field(c, module_index, c.tokens[usize(node.token_end) - 1usize].start, field_index) }
        let (field_type, context_error) = apply_context(c, c.aggregate_fields[field_index].ty, expected)
        ret (field_type, context_error)
    }
    if node.kind == .GroupExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (group_type, group_error) = check_expr(c, g, tree, module_index, child_index, expected)
        ret (group_type, group_error)
    }
    if node.kind == .BracketPostfix {
        let (result, result_error) = check_bracket_expr(c, g, tree, module_index, node, expected)
        ret (result, result_error)
    }
    if node.kind == .AggregateLiteral {
        let (result, result_error) = check_aggregate_literal(c, g, tree, module_index, node, expected)
        ret (result, result_error)
    }
    if node.kind == .UnaryExpr {
        let (child_index, found) = first_node_child(tree, node)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let op = c.tokens[usize(node.token_start)].kind
        if op == .PunctBang {
            let (value_type, value_error) = check_expr(c, g, tree, module_index, child_index, make_type(.Bool, "bool", module_index))
            if value_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if value_error != ok { ret (invalid_type(), value_error) }
            let (result_type, context_error) = apply_context(c, value_type, expected)
            ret (result_type, context_error)
        }
        if op == .PunctAmp {
            let place = tree.nodes[child_index]
            var place_type = invalid_type()
            var mutable = false
            if place.kind == .NameExpr {
                let token = c.tokens[usize(place.token_start)]
                let name = text[token.start..token.end]
                let (local_index, local_found) = find_local(c, name)
                if !local_found { ret (invalid_type(), Unsupported) }
                place_type = c.locals[local_index].ty
                mutable = c.locals[local_index].mutable
                resource_pin(c, local_index, usize(node.token_start))
            } else {
                // `&s.f`, `&s.items[i]`: a pointer into `s` pins `s`.
                var base_index = child_index
                while tree.nodes[base_index].kind == .FieldExpr || tree.nodes[base_index].kind == .BracketPostfix {
                    let (inner_index, has_inner) = first_node_child(tree, tree.nodes[base_index])
                    if !has_inner { break }
                    base_index = inner_index
                }
                if tree.nodes[base_index].kind == .NameExpr {
                    let (base_local, base_is_resource) = resource_local_of(c, g, tree, module_index, base_index)
                    if base_is_resource { resource_pin(c, base_local, usize(node.token_start)) }
                }
                if place.kind != .BracketPostfix && place.kind != .FieldExpr && !(place.kind == .UnaryExpr && c.tokens[usize(place.token_start)].kind == .PunctStar) { ret (invalid_type(), Unsupported) }
                let (resolved_place, place_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
                if place_error != ok { ret (invalid_type(), place_error) }
                place_type = resolved_place
                let (place_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, child_index)
                if mutable_error != ok { ret (invalid_type(), mutable_error) }
                mutable = place_mutable
            }
            let (element_index, store_error) = store_type(c, place_type)
            if store_error != ok { ret (invalid_type(), store_error) }
            var pointer = make_type(.Pointer, "", module_index)
            pointer.element = element_index
            pointer.has_element = true
            pointer.is_const = !mutable
            let (result_type, context_error) = apply_context(c, pointer, expected)
            ret (result_type, context_error)
        }
        if op == .PunctStar {
            let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
            if pointer_error != ok { ret (invalid_type(), pointer_error) }
            if pointer.kind != .Pointer || !pointer.has_element || pointer.element >= c.type_count {
                if c.generic_declaration && type_shape_unknown(pointer) { ret (dependent_expression_type(pointer, expected, module_index), ok) }
                ret (invalid_type(), InvalidOperator)
            }
            let element = c.types[pointer.element]
            if element.kind == .Void { ret (invalid_type(), InvalidOperator) }
            let (result_type, context_error) = apply_context(c, element, expected)
            ret (result_type, context_error)
        }
        let (value_type, value_error) = check_expr(c, g, tree, module_index, child_index, expected)
        if value_error != ok { ret (invalid_type(), value_error) }
        if op == .PunctMinus && !is_numeric(value_type) {
            if !c.generic_declaration || !type_shape_unknown(value_type) { ret (invalid_type(), InvalidOperator) }
        }
        if op == .PunctTilde && !is_integer(value_type) && !vector_operator_legal(c, value_type, op) && !vector_pending(c, value_type) {
            if !c.generic_declaration || !type_shape_unknown(value_type) { ret (invalid_type(), InvalidOperator) }
        }
        if op != .PunctMinus && op != .PunctTilde { ret (invalid_type(), Unsupported) }
        ret (value_type, ok)
    }
    if node.kind == .BinaryExpr {
        let end = usize(node.first_child) + usize(node.child_count)
        var children: [2]usize = zero
        var count = 0usize
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == 2usize { ret (invalid_type(), parse.InvalidSyntax) }
                children[count] = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (invalid_type(), parse.InvalidSyntax) }
        let op = binary_operator(c, tree, node)
        if is_shift(op) {
            let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], expected)
            if left_error != ok { ret (invalid_type(), left_error) }
            if !is_integer(left_type) || is_untyped(left_type) {
                if !vector_operator_legal(c, left_type, op) && !vector_pending(c, left_type) {
                    if !c.generic_declaration || !type_shape_unknown(left_type) { ret (invalid_type(), InvalidOperator) }
                }
            }
            let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], invalid_type())
            if right_error != ok { ret (invalid_type(), right_error) }
            var final_right = right_type
            if right_type.kind == .UntypedInteger {
                let (contextual_right, contextual_error) = apply_context(c, right_type, make_type(.Integer, "u32", module_index))
                if contextual_error != ok { ret (invalid_type(), contextual_error) }
                final_right = contextual_right
            }
            if final_right.kind != .Integer || !unsigned_integer_type(final_right) { ret (invalid_type(), InvalidOperator) }
            ret (left_type, ok)
        }
        if is_logical(op) {
            let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], make_type(.Bool, "bool", module_index))
            if left_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if left_error != ok { ret (invalid_type(), left_error) }
            let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], make_type(.Bool, "bool", module_index))
            if right_error == TypeMismatch { ret (invalid_type(), InvalidOperator) }
            if right_error != ok { ret (invalid_type(), right_error) }
            let (result_type, context_error) = apply_context(c, make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        var operand_context = expected
        if is_comparison(op) { operand_context = invalid_type() }
        let (left_type, left_error) = check_expr(c, g, tree, module_index, children[0usize], operand_context)
        if left_error != ok { ret (invalid_type(), left_error) }
        var right_context = left_type
        if is_untyped(left_type) { right_context = operand_context }
        let (right_type, right_error) = check_expr(c, g, tree, module_index, children[1usize], right_context)
        if right_error != ok { ret (invalid_type(), right_error) }
        var final_left = left_type
        var final_right = right_type
        if is_untyped(final_left) && !is_untyped(final_right) {
            let (contextual_left, contextual_error) = apply_context(c, final_left, final_right)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_left = contextual_left
        }
        if is_untyped(final_right) && !is_untyped(final_left) {
            let (contextual_right, contextual_error) = apply_context(c, final_right, final_left)
            if contextual_error != ok { ret (invalid_type(), contextual_error) }
            final_right = contextual_right
        }
        if !type_equal(c, final_left, final_right) {
            if !c.generic_declaration || !types_may_match_after_instantiation(c, final_left, final_right) { ret (invalid_type(), TypeMismatch) }
        }
        if is_comparison(op) {
            if is_untyped(final_left) { ret (invalid_type(), MissingContext) }
            if !is_numeric(final_left) {
                if !is_enum_type(c, final_left) {
                    if !c.generic_declaration || !type_shape_unknown(final_left) {
                        if !is_equality(op) { ret (invalid_type(), InvalidOperator) }
                        if final_left.kind != .Bool && final_left.kind != .Err && final_left.kind != .Pointer { ret (invalid_type(), InvalidOperator) }
                    }
                }
            }
            let (result_type, context_error) = apply_context(c, make_type(.Bool, "bool", module_index), expected)
            ret (result_type, context_error)
        }
        if is_vector_type(c, final_left) {
            if vector_pending(c, final_left) || vector_operator_legal(c, final_left, op) { ret (final_left, ok) }
            ret (invalid_type(), InvalidOperator)
        }
        if !is_numeric(final_left) {
            if c.generic_declaration && type_shape_unknown(final_left) { ret (final_left, ok) }
            ret (invalid_type(), InvalidOperator)
        }
        if is_integer_operator(op) && !is_integer(final_left) { ret (invalid_type(), InvalidOperator) }
        ret (final_left, ok)
    }
    if node.kind == .CallExpr {
        let (call, call_error) = check_call(c, g, tree, module_index, node)
        if call_error != ok { ret (invalid_type(), call_error) }
        if call.is_cast {
            let (result_type, context_error) = apply_context(c, call.cast, expected)
            ret (result_type, context_error)
        }
        // A protocol call in a template body has no signature until the
        // instantiation binds its receiver, so its result follows the context.
        if call.protocol_pending { ret (dependent_expression_type(make_type(.TypeParameter, "", module_index), expected, module_index), ok) }
        let function = call.function
        if function.return_count > 1usize { ret (invalid_type(), ArgumentCount) }
        if function.return_count == 0usize {
            let (result_type, context_error) = apply_context(c, make_type(.Void, "void", module_index), expected)
            ret (result_type, context_error)
        }
        let (return_type, return_error) = call_return(c, call, 0usize)
        if return_error != ok { ret (invalid_type(), return_error) }
        let (result_type, context_error) = apply_context(c, return_type, expected)
        ret (result_type, context_error)
    }
    ret (invalid_type(), Unsupported)
}

fn contains_token(c: *Checker, start: usize, end: usize, kind: lex.Kind) -> bool {
    var at = start
    while at < end {
        if c.tokens[at].kind == kind { ret true }
        at += 1usize
    }
    ret false
}

fn binding_item_count(c: *Checker, binding: syntax.Node) -> usize {
    var count = 0usize
    var at = usize(binding.token_start)
    while at < usize(binding.token_end) {
        let kind = c.tokens[at].kind
        if kind == .Identifier || kind == .PunctUnderscore { count += 1usize }
        at += 1usize
    }
    ret count
}

fn check_try_results(c: *Checker, call: CallInfo, caller: Function) -> (usize, err) {
    // Three different mistakes, and telling them apart is the point: the callee cannot
    // fail, or the caller has no `err` to propagate through.
    if call.function.external || !call_is_fallible(c, call) { ret (0usize, TryNotFallible) }
    if !is_fallible(c, caller) { ret (0usize, TryNoPropagate) }
    ret (call.function.return_count - 1usize, ok)
}

fn bind_return_types(c: *Checker, g: *graph.Graph, module_index: usize, statement: syntax.Node, binding: syntax.Node, call: CallInfo, return_count: usize, declared: Type, mutable: bool) -> err {
    let tuple = c.tokens[usize(binding.token_start)].kind == .PunctLParen
    let item_count = binding_item_count(c, binding)
    if item_count != return_count {
        record_failure(c, module_index, statement, .MultipleBindingCount, "", "")
        ret ArgumentCount
    }
    if tuple && declared.kind != .Invalid { ret InvalidType }
    var result_index = 0usize
    var at = usize(binding.token_start)
    while at < usize(binding.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            let (return_type, return_error) = call_return(c, call, result_index)
            if return_error != ok { ret return_error }
            var result = return_type
            if !tuple {
                let (contextual, context_error) = apply_context(c, result, declared)
                if context_error != ok { ret context_error }
                result = contextual
            }
            if result.kind == .Void { ret TypeMismatch }
            if result.kind == .Other { ret Unsupported }
            if token.kind == .Identifier {
                let name = g.modules[module_index].text[token.start..token.end]
                try add_local(c, name, result, mutable)
            }
            // An `err` bound to `_` is a discard (D360, H07): an explicit choice,
            // and one the explain stream lists, deferred or not.
            if token.kind == .PunctUnderscore && result.kind == .Err && c.explains.len != 0usize && c.explain_count < c.explains.len {
                var offset = 0usize
                if usize(statement.token_start) < c.token_count { offset = c.tokens[usize(statement.token_start)].start }
                var deferred = 0usize
                if c.defer_depth != 0usize { deferred = 1usize }
                c.explains[c.explain_count] = Explain { kind: 3u8, module_index: module_index, offset: offset, protocol: "", receiver: invalid_type(), function_index: 0usize, found: deferred != 0usize, builtin: .None, template_index: 0usize, first_argument: 0usize, argument_count: 0usize, candidate_index: 0usize, reason_kind: 0u8, reason_name: "", reason_type: invalid_type() }
                c.explains[c.explain_count].function_index = explain_function_index(c, call.function)
                c.explain_count += 1usize
            }
            result_index += 1usize
        }
        at += 1usize
    }
    ret ok
}

fn record_generic_type_arity_diagnostics(c: *Checker, g: *graph.Graph, module_index: usize, binding: syntax.Node, named: syntax.Node) {
    if usize(named.token_start) >= c.token_count { ret }
    let name_token = c.tokens[usize(named.token_start)]
    if name_token.kind != .Identifier { ret }
    let name = g.modules[module_index].text[name_token.start..name_token.end]
    let (aggregate_index, found) = find_aggregate(c, module_index, name)
    var reason = name
    if found {
        let aggregate = c.aggregates[aggregate_index]
        var field_at = 0usize
        while field_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + field_at]
            if type_depends_on_comptime(c, field.ty) {
                append_failure_token(c, aggregate.module_index, field.token, .AggregateMemberUnknown, field.name, "")
                if same(reason, name) { reason = field.name }
            }
            field_at += 1usize
        }
    }
    append_failure_token(c, module_index, c.tokens[usize(binding.token_start)], .GenericTypeArity, name, "")
    append_failure_token(c, module_index, c.tokens[usize(binding.token_start)], .BindingUnknownNamed, name, "")
    var at = usize(binding.token_start)
    while at < usize(binding.token_end) {
        if c.tokens[at].kind == .KwZero {
            append_failure_token(c, module_index, c.tokens[at], .MissingZeroValue, name, reason)
            break
        }
        at += 1usize
    }
}

fn check_binding(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var binding_index = 0usize
    var has_binding = false
    var initializer_index = 0usize
    var has_initializer = false
    var declared = invalid_type()
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .Binding {
                binding_index = child_index
                has_binding = true
            } else {
                if child.kind == .NamedType || child.kind == .PointerType || child.kind == .SliceType || child.kind == .ArrayType || child.kind == .FunctionType {
                    let (declared_type, type_error) = type_from_node(c, r, g, tree, module_index, child)
                    if type_error != ok {
                        if type_error == ArgumentCount && child.kind == .NamedType { record_generic_type_arity_diagnostics(c, g, module_index, node, child) }
                        ret type_error
                    }
                    declared = declared_type
                } else {
                    initializer_index = child_index
                    has_initializer = true
                }
            }
        }
        at += 1usize
    }
    if !has_binding { ret parse.InvalidSyntax }
    let binding = tree.nodes[binding_index]
    let tuple = c.tokens[usize(binding.token_start)].kind == .PunctLParen
    var mutable = false
    if c.tokens[usize(node.token_start)].kind == .KwVar { mutable = true }
    if has_initializer && tree.nodes[initializer_index].kind == .CallExpr {
        let initializer = tree.nodes[initializer_index]
        let tried = contains_token(c, usize(node.token_start), usize(initializer.token_start), .KwTry)
        let (call, call_error) = check_call(c, g, tree, module_index, initializer)
        if call_error != ok { ret call_error }
        if call.is_cast {
            if tried { ret TryCast }
            if tuple {
                record_failure(c, module_index, node, .MultipleBindingCount, "", "")
                ret ArgumentCount
            }
            let (actual, context_error) = apply_context(c, call.cast, declared)
            if context_error != ok { ret context_error }
            if actual.kind == .Other { ret Unsupported }
            let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
            if has_name { try add_local(c, name, actual, mutable) }
            ret ok
        }
        // A protocol call in a template body has no signature until the instantiation binds
        // its receiver, so it has no result count to read either: the binding follows the
        // declared type, as `check_expr` already lets an expression of it do.
        if call.protocol_pending {
            if tried { ret TryCast }
            if tuple {
                // How many results the protocol answers with is the instance's to know, so
                // every name here is bound to a type not yet known and the count is checked
                // when it is.
                var item_at = usize(binding.token_start)
                while item_at < usize(binding.token_end) {
                    let item_token = c.tokens[item_at]
                    if item_token.kind == .Identifier {
                        let item_name = g.modules[module_index].text[item_token.start..item_token.end]
                        try add_local(c, item_name, make_type(.TypeParameter, "", module_index), mutable)
                    }
                    item_at += 1usize
                }
                ret ok
            }
            let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
            if has_name { try add_local(c, name, dependent_expression_type(make_type(.TypeParameter, "", module_index), declared, module_index), mutable) }
            ret ok
        }
        let callee = call.function
        var result_count = callee.return_count
        if tried {
            let (remaining, try_error) = check_try_results(c, call, function)
            if try_error != ok { ret try_error }
            result_count = remaining
        }
        if !tuple && result_count == 0usize { ret TypeMismatch }
        // A `try` is an exit before anything is bound (D345).
        if tried { try resource_audit(c, g, module_index, node, 0usize, .ResourceCleanupForgotten) }
        let first_local = c.local_count
        let bind_error = bind_return_types(c, g, module_index, node, binding, call, result_count, declared, mutable)
        // A call's result against the declared type (D491): the whole call is the
        // expression the mismatch surfaced at, as `check_expr` would have noted it.
        if bind_error == TypeMismatch && !tuple { note_mismatch_expression(c, tree, initializer_index) }
        if bind_error != ok { ret bind_error }
        // The resources bound (D345): owned, or unchecked beside the `err` bound last.
        // A `bool` bound last -- a container's `(T, bool)` -- is tested the same way
        // (D353): the value is null on the false path.
        var err_local = c.local_count
        var has_err_local = false
        if !tried && c.local_count > first_local && (c.locals[c.local_count - 1usize].ty.kind == .Err || c.locals[c.local_count - 1usize].ty.kind == .Bool) {
            err_local = c.local_count - 1usize
            has_err_local = true
        }
        var bound_at = first_local
        while bound_at < c.local_count {
            try resource_bind_local(c, g, tree, module_index, bound_at, node, initializer_index, true, true, call, tried, err_local, has_err_local)
            bound_at += 1usize
        }
        ret ok
    }
    if tuple {
        record_failure(c, module_index, node, .MultipleBindingCount, "", "")
        ret ArgumentCount
    }
    var result = declared
    if has_initializer {
        let (actual, expression_error) = check_expr(c, g, tree, module_index, initializer_index, declared)
        if expression_error != ok { ret expression_error }
        result = actual
    } else {
        if declared.kind == .Invalid { ret MissingContext }
        if contains_token(c, usize(node.token_start), usize(node.token_end), .KwZero) && !type_has_zero_value(c, declared, 0usize) {
            var zero_at = usize(node.token_start)
            while zero_at < usize(node.token_end) {
                if c.tokens[zero_at].kind == .KwZero {
                    record_failure_token(c, module_index, c.tokens[zero_at], .MissingZeroValue, declared.name, declared.name)
                    break
                }
                zero_at += 1usize
            }
            ret InvalidType
        }
        // `= undef` of a type that admits only its members (D475, H03).
        if contains_token(c, usize(node.token_start), usize(node.token_end), .KwUndef) {
            let (admits, culprit) = type_has_undef_value(c, declared, 0usize)
            if !admits {
                var undef_at = usize(node.token_start)
                while undef_at < usize(node.token_end) {
                    if c.tokens[undef_at].kind == .KwUndef {
                        record_failure_token(c, module_index, c.tokens[undef_at], .MissingUndefValue, declared.name, culprit)
                        break
                    }
                    undef_at += 1usize
                }
                ret InvalidType
            }
        }
    }
    if is_untyped(result) { ret MissingContext }
    if result.kind == .Void { ret TypeMismatch }
    if result.kind == .Other { ret Unsupported }
    let (name, has_name) = first_name(c, g.modules[module_index].text, binding)
    if !has_name { ret ok }
    try add_local(c, name, result, mutable)
    var no_call: CallInfo = zero
    try resource_bind_local(c, g, tree, module_index, c.local_count - 1usize, node, initializer_index, has_initializer, false, no_call, false, 0usize, false)
    // `var failure = options_error`: the resources bound beside the source error are
    // bound beside this one too from here on.
    if has_initializer && result.kind == .Err && tree.nodes[initializer_index].kind == .NameExpr && c.resources_on {
        let source_token = c.tokens[usize(tree.nodes[initializer_index].token_start)]
        if source_token.kind == .Identifier {
            let (source, source_found) = find_local(c, g.modules[module_index].text[source_token.start..source_token.end])
            if source_found && c.locals[source].ty.kind == .Err {
                var bound_at = 0usize
                while bound_at < c.local_count - 1usize {
                    if c.resources[bound_at].has_bound_err && c.resources[bound_at].bound_err == source { c.resources[bound_at].bound_err = c.local_count - 1usize }
                    bound_at += 1usize
                }
            }
        }
    }
    ret ok
}

fn check_return(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    if c.defer_depth != 0usize { ret InvalidReturn }
    var count = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            count += 1usize
        }
        at += 1usize
    }
    if function.return_count == 0usize {
        if count != 0usize { ret ReturnValuesUnexpected }
        ret ok
    }
    if count != function.return_count { ret ReturnCount }
    var return_index = 0usize
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let (expected, return_type_error) = function_return(c, function, return_index)
            if return_type_error != ok { ret return_type_error }
            let (actual, expression_error) = check_expr(c, g, tree, module_index, parse.child_index_at(tree, at), expected)
            if expression_error == TypeMismatch {
                record_failure(c, module_index, tree.nodes[parse.child_index_at(tree, at)], .ReturnType, "", "")
                ret ReturnType
            }
            if expression_error != ok { ret expression_error }
            let borrow_from = function_borrow_from(c, function)
            if borrow_from != 0usize && holds_pointer(c, expected, 0usize) {
                if !result_borrows_from(c, g, tree, module_index, parse.child_index_at(tree, at), borrow_from - 1usize) {
                    let parameter = c.parameters[function.first_parameter + borrow_from - 1usize]
                    record_failure(c, module_index, tree.nodes[parse.child_index_at(tree, at)], .BorrowContract, parameter.name, "")
                    ret ResourceViolation
                }
            }
            let noescape_from = expression_noescape_from(c, g, tree, module_index, function, parse.child_index_at(tree, at))
            if noescape_from != 0usize && holds_pointer(c, expected, 0usize) {
                let parameter = c.parameters[function.first_parameter + noescape_from - 1usize]
                record_failure(c, module_index, tree.nodes[parse.child_index_at(tree, at)], .NoEscapeContract, parameter.name, "")
                ret ResourceViolation
            }
            try resource_return_value(c, g, tree, module_index, parse.child_index_at(tree, at))
            return_index += 1usize
        }
        at += 1usize
    }
    ret resource_audit(c, g, module_index, node, 0usize, .ResourceCleanupForgotten)
}

// The parameter-local identity retained by a pointer or slice result. Bindings and
// derived places already use the resource alias table, so the contract check follows
// that one source of truth instead of growing a second provenance analysis.
fn result_borrow_origin(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    var (origin, found) = alias_target(c, g, tree, module_index, node_index)
    if !found { (origin, found) = address_argument_local(c, g, tree, module_index, node_index) }
    if !found { (origin, found) = place_base_local(c, g, tree, module_index, node_index) }
    if !found || origin >= c.local_count { ret (0usize, false) }
    var steps = 0usize
    while c.resources[origin].points_to != 0usize && steps < c.local_count {
        origin = c.resources[origin].points_to - 1usize
        if origin >= c.local_count { ret (0usize, false) }
        steps += 1usize
    }
    ret (origin, true)
}

fn pointer_leaf_count(c: *Checker, ty: Type, depth: usize) -> (usize, bool) {
    if depth > 16usize { ret (0usize, false) }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .String || ty.kind == .Function { ret (1usize, true) }
    if ty.kind == .Array {
        if !ty.has_element || !ty.has_length || ty.element >= c.type_count { ret (0usize, false) }
        let (elements, known) = pointer_leaf_count(c, c.types[ty.element], depth + 1usize)
        if !known { ret (0usize, false) }
        ret (elements * ty.array_length, true)
    }
    if ty.kind != .Named { ret (0usize, ty.kind != .TypeParameter) }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret (0usize, false) }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.kind != .Struct { ret (0usize, !holds_pointer(c, ty, 0usize)) }
    var count = 0usize
    var at = 0usize
    while at < aggregate.field_count {
        let field_index = aggregate.first_field + at
        if field_index >= c.aggregate_field_count { ret (0usize, false) }
        let (fields, known) = pointer_leaf_count(c, c.aggregate_fields[field_index].ty, depth + 1usize)
        if !known { ret (0usize, false) }
        count += fields
        at += 1usize
    }
    ret (count, true)
}

fn carrier_borrows_from(c: *Checker, carrier: usize, parameter: usize) -> bool {
    if carrier >= c.local_count { ret false }
    let (wanted, known) = pointer_leaf_count(c, c.locals[carrier].ty, 0usize)
    if !known || wanted == 0usize { ret false }
    var found = 0usize
    if c.resources[carrier].points_to != 0usize {
        if c.resources[carrier].points_to - 1usize != parameter { ret false }
        found += 1usize
    }
    if c.resources[carrier].slice_offset_known {
        if c.resources[carrier].slice_offset - 1usize != parameter { ret false }
        found += 1usize
    }
    var at = 0usize
    while at < c.resource_alias_count {
        let alias = c.resource_aliases[at]
        if alias.carrier == carrier {
            if alias.pointed != parameter { ret false }
            found += 1usize
        }
        at += 1usize
    }
    ret found == wanted
}

fn result_borrows_from(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, parameter: usize) -> bool {
    let (origin, found) = result_borrow_origin(c, g, tree, module_index, node_index)
    if found && origin == parameter { ret true }
    let (carrier, has_carrier) = place_base_local(c, g, tree, module_index, node_index)
    ret has_carrier && carrier_borrows_from(c, carrier, parameter)
}

fn carrier_contains_borrow_from(c: *Checker, carrier: usize, parameter: usize) -> bool {
    if carrier >= c.local_count { ret false }
    if c.resources[carrier].points_to == parameter + 1usize { ret true }
    if c.resources[carrier].slice_offset_known && c.resources[carrier].slice_offset == parameter + 1usize { ret true }
    var at = 0usize
    while at < c.resource_alias_count {
        let alias = c.resource_aliases[at]
        if alias.carrier == carrier && alias.pointed == parameter { ret true }
        at += 1usize
    }
    ret false
}

// Whether an expression retains the named input. Aggregate literals are walked
// directly; named carriers use the same complete alias paths as result-borrow proof.
fn expression_borrows_from(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, parameter: usize) -> bool {
    let (origin, found) = result_borrow_origin(c, g, tree, module_index, node_index)
    if found && origin == parameter { ret true }
    let (carrier, has_carrier) = place_base_local(c, g, tree, module_index, node_index)
    if has_carrier && carrier_contains_borrow_from(c, carrier, parameter) { ret true }
    let node = tree.nodes[node_index]
    if node.kind != .AggregateLiteral && node.kind != .GroupExpr { ret false }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .LiteralItem {
                let (value_index, has_value) = first_node_child(tree, child)
                if has_value && expression_borrows_from(c, g, tree, module_index, value_index, parameter) { ret true }
            } else {
                if node.kind == .GroupExpr && expression_borrows_from(c, g, tree, module_index, child_index, parameter) { ret true }
            }
        }
        at += 1usize
    }
    ret false
}

fn check_children(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) { try check_statement(c, r, g, tree, module_index, parse.child_index_at(tree, at), function) }
        at += 1usize
    }
    ret ok
}

fn check_block(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let checkpoint = c.local_count
    c.block_depth += 1usize
    let block_error = check_children(c, r, g, tree, module_index, node, function)
    // The pointers taken in this block die with it (D351): what they pinned is free.
    if c.pins_live != 0usize {
        var pinned_at = 0usize
        while pinned_at < c.local_count {
            if c.resources[pinned_at].pinned == c.block_depth {
                c.resources[pinned_at].pinned = 0usize
                c.pins_live = c.pins_live - 1usize
            }
            pinned_at += 1usize
        }
    }
    c.block_depth = c.block_depth - 1usize
    // The block's own resources at its end (D345): a `ret` or `try` inside audited
    // everything already, and left nothing owned to find here.
    if block_error == ok && c.local_count > checkpoint && any_affine_local(c) && !resource_diverges(c, g, tree, module_index, node) {
        var closing = node
        if node.token_end > node.token_start { closing.token_start = node.token_end - 1u32 }
        let audit_error = resource_audit(c, g, module_index, closing, checkpoint, .ResourceCleanupForgotten)
        c.local_count = checkpoint
        ret audit_error
    }
    c.local_count = checkpoint
    ret block_error
}

fn check_condition_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    // A settled condition means one of the arms is not code at all, so it is not checked. Only
    // an `if` may fold -- a `while` whose condition never changes is a loop, not a choice -- and
    // only one whose arms are blocks, which is the shape lowering takes too, so the two passes
    // cannot disagree about which arm exists.
    if node.kind == .IfStmt {
        var condition_index = 0usize
        var found_condition = false
        var arms: [2]usize = zero
        var arm_count = 0usize
        var foldable = true
        var scan = usize(node.first_child)
        while scan < end {
            if parse.child_is_node_at(tree, scan) {
                let scanned = parse.child_index_at(tree, scan)
                if !found_condition {
                    condition_index = scanned
                    found_condition = true
                } else {
                    if arm_count == arms.len || tree.nodes[scanned].kind != .Block {
                        foldable = false
                    } else {
                        arms[arm_count] = scanned
                        arm_count += 1usize
                    }
                }
            }
            scan += 1usize
        }
        if found_condition && foldable && arm_count != 0usize {
            let (condition_type, condition_error) = check_expr(c, g, tree, module_index, condition_index, make_type(.Bool, "bool", module_index))
            if condition_error == TypeMismatch { ret InvalidCondition }
            if condition_error != ok { ret condition_error }
            if condition_type.kind != .Bool { ret InvalidCondition }
            let (taken, settled) = comptime_condition(c, g, tree, module_index, condition_index)
            if settled {
                record_explain_fold(c, module_index, node, "if", taken)
                if taken { ret check_block(c, r, g, tree, module_index, tree.nodes[arms[0usize]], function) }
                if arm_count == 2usize { ret check_block(c, r, g, tree, module_index, tree.nodes[arms[1usize]], function) }
                ret ok
            }
        }
    }
    var first = true
    var at = usize(node.first_child)
    var condition_node = 0usize
    // The arms' states (D345): the first arm's, then joined with each later arm's;
    // an arm that diverges leaves no state to join.
    var joined: []u8 = zero
    var joined_count = 0usize
    var arm_total = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if first {
                let (condition_type, condition_error) = check_expr(c, g, tree, module_index, child_index, make_type(.Bool, "bool", module_index))
                if condition_error == TypeMismatch { ret InvalidCondition }
                if condition_error != ok { ret condition_error }
                if condition_type.kind != .Bool { ret InvalidCondition }
                condition_node = child_index
                first = false
            } else {
                if node.kind == .WhileStmt {
                    if c.loop_depth < c.loop_locals.len { c.loop_locals[c.loop_depth] = c.local_count }
                    if c.break_depth < c.break_locals.len { c.break_locals[c.break_depth] = c.local_count }
                    if c.loop_depth < c.resource_loop_sweep.len {
                        let (index_name, bound, bound_local, sweep) = resource_loop_fact(c, g, tree, module_index, node, condition_node, child)
                        c.resource_loop_index[c.loop_depth] = index_name
                        c.resource_loop_bound[c.loop_depth] = bound
                        c.resource_loop_bound_local[c.loop_depth] = bound_local
                        c.resource_loop_sweep[c.loop_depth] = sweep
                        c.resource_loop_swept_local[c.loop_depth] = 0usize
                    }
                    c.loop_depth += 1usize
                    c.break_depth += 1usize
                }
                // The resources before an arm (D345): an `if`'s arms are joined after,
                // a loop's body must leave the outer ones as it found them.
                var before: []u8 = zero
                let tracked = any_affine_local(c)
                if tracked {
                    let (snapshot, snapshot_error) = resource_snapshot(c, c.local_count)
                    if snapshot_error != ok { ret snapshot_error }
                    before = snapshot
                }
                if tracked && node.kind == .IfStmt { resource_narrow_arm(c, g, tree, module_index, condition_node, arm_total) }
                var branch_error = ok
                if child.kind == .Block {
                    branch_error = check_block(c, r, g, tree, module_index, child, function)
                } else {
                    branch_error = check_statement(c, r, g, tree, module_index, child_index, function)
                }
                if node.kind == .WhileStmt {
                    c.loop_depth = c.loop_depth - 1usize
                    c.break_depth = c.break_depth - 1usize
                }
                if branch_error != ok { ret branch_error }
                if tracked {
                    if node.kind == .WhileStmt {
                        try resource_loop_check(c, g, module_index, child, before)
                    } else {
                        let (after, after_error) = resource_snapshot(c, c.local_count)
                        if after_error != ok { ret after_error }
                        resource_restore(c, before)
                        if !resource_diverges(c, g, tree, module_index, child) {
                            if joined_count == 0usize { joined = after } else { resource_join_states(c, joined, after) }
                            joined_count += 1usize
                        }
                        arm_total += 1usize
                    }
                }
            }
        }
        at += 1usize
    }
    // The join (D345): with two arms both states were joined; with one, the arm's
    // state is joined with the fall-through's, which is the state before it. And an
    // `if e != ok { <diverges> }` leaves the resources bound beside `e` owned.
    if node.kind == .IfStmt && arm_total != 0usize && any_affine_local(c) {
        if arm_total == 1usize {
            if joined_count == 1usize {
                // The fall-through is the missing else: for `if e == ok`, the path the
                // error is not ok on, where the resource is null.
                resource_narrow_arm(c, g, tree, module_index, condition_node, 1usize)
                resource_join(c, joined)
            } else {
                resource_narrow(c, g, tree, module_index, condition_node)
            }
        } else {
            if joined_count != 0usize { resource_restore(c, joined) }
        }
    }
    ret ok
}

fn check_call_statement(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let (call, call_error) = check_call(c, g, tree, module_index, tree.nodes[child_index])
    if call_error != ok { ret call_error }
    if call.is_cast { ret ArgumentCount }
    if call.function.return_count != 0usize { ret ArgumentCount }
    ret ok
}

fn check_try_statement(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    if c.defer_depth != 0usize { ret InvalidTry }
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let call_node = tree.nodes[child_index]
    let (call, call_error) = check_call(c, g, tree, module_index, call_node)
    if call_error != ok { ret call_error }
    if call.is_cast { ret TryCast }
    let (remaining, try_error) = check_try_results(c, call, function)
    if try_error != ok { ret try_error }
    if remaining != 0usize { ret ArgumentCount }
    ret resource_audit(c, g, module_index, node, 0usize, .ResourceCleanupForgotten)
}

fn ascii_lower(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

// Spec section 9: `T.f(...)` resolves to `fn <t>_f` in the module declaring T,
// where <t> is T's name in snake_case. A boundary precedes an uppercase letter
// following a lowercase letter or digit, and precedes the last uppercase letter of
// a run when the next letter is lowercase, so `HTTP2Client` becomes `http2_client`.
fn protocol_name_matches(type_name: str, candidate_name: str, protocol: str) -> bool {
    var source = 0usize
    var output_at = 0usize
    while source < type_name.len {
        let byte = type_name[source]
        let upper = byte >= 65u8 && byte <= 90u8
        var previous_lower = false
        if source > 0usize {
            let previous = type_name[source - 1usize]
            previous_lower = (previous >= 97u8 && previous <= 122u8) || (previous >= 48u8 && previous <= 57u8)
        }
        var next_lower = false
        if source + 1usize < type_name.len {
            let next = type_name[source + 1usize]
            next_lower = next >= 97u8 && next <= 122u8
        }
        if upper && source > 0usize && (previous_lower || next_lower) {
            if output_at >= candidate_name.len || candidate_name[output_at] != 95u8 { ret false }
            output_at += 1usize
        }
        if output_at >= candidate_name.len || candidate_name[output_at] != ascii_lower(byte) { ret false }
        source += 1usize
        output_at += 1usize
    }
    if output_at >= candidate_name.len || candidate_name[output_at] != 95u8 { ret false }
    output_at += 1usize
    var suffix_at = 0usize
    while suffix_at < protocol.len {
        if output_at >= candidate_name.len || candidate_name[output_at] != protocol[suffix_at] { ret false }
        output_at += 1usize
        suffix_at += 1usize
    }
    ret output_at == candidate_name.len
}

fn iterator_next_name_matches(type_name: str, candidate_name: str) -> bool {
    ret protocol_name_matches(type_name, candidate_name, "next")
}

fn protocol_iteration_element(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, statement: syntax.Node, subject_index: usize, iterable: Type, name_count: usize) -> (Type, err) {
    if name_count != 1usize { ret (invalid_type(), ArgumentCount) }
    var iterator = iterable
    if iterable.kind == .Pointer {
        if iterable.is_const {
            record_failure(c, module_index, statement, .IteratorImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        if !iterable.has_element || iterable.element >= c.type_count { ret (invalid_type(), InvalidType) }
        iterator = c.types[iterable.element]
    }
    let (canonical_iterator, canonical_error) = canonical_type(c, iterator)
    if canonical_error != ok { ret (invalid_type(), canonical_error) }
    if canonical_iterator.kind != .Named { ret (invalid_type(), InvalidOperator) }
    if iterable.kind != .Pointer {
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, subject_index)
        if mutable_error != ok { ret (invalid_type(), mutable_error) }
        if !mutable {
            record_failure(c, module_index, statement, .IteratorImmutable, canonical_iterator.name, "")
            ret (invalid_type(), ImmutableAssignment)
        }
    }
    var next_index = 0usize
    var found_next = false
    var function_at = 0usize
    while function_at < c.signature_function_count {
        let candidate = c.functions[function_at]
        if candidate.module_index == canonical_iterator.module_index && iterator_next_name_matches(canonical_iterator.name, candidate.name) {
            next_index = function_at
            found_next = true
            break
        }
        function_at += 1usize
    }
    if !found_next {
        record_failure(c, module_index, statement, .IteratorMissing, canonical_iterator.name, "")
        ret (invalid_type(), UnknownCallable)
    }
    let next = c.functions[next_index]
    if next.generic || next.parameter_count != 1usize || next.return_count != 2usize {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    let (stored_iterator, store_error) = store_type(c, canonical_iterator)
    if store_error != ok { ret (invalid_type(), store_error) }
    var expected_parameter = make_type(.Pointer, "", canonical_iterator.module_index)
    expected_parameter.element = stored_iterator
    expected_parameter.has_element = true
    let parameter = c.parameters[next.first_parameter]
    if !type_equal(c, parameter.ty, expected_parameter) {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    let element = c.return_types[next.first_return]
    let has_value = c.return_types[next.first_return + 1usize]
    if element.kind == .Void || has_value.kind != .Bool {
        record_failure(c, module_index, statement, .IteratorSignature, canonical_iterator.name, next.name)
        ret (invalid_type(), InvalidType)
    }
    ret (element, ok)
}

// Section 9: `fields[T]()` and `members[E]()` are comptime-only, and the one place a
// comptime sequence may stand is the subject of a `for`, which is always unrolled.
// There is no runtime `[]const Field`, so there is nothing else to recognise.
type MetaSequenceKind = enum u8 {
    None,
    Fields,
    Members,
}

type MetaSequence = struct {
    kind: MetaSequenceKind,
    subject: Type,
    aggregate_index: usize,
    // A resource outside its declaring module has no reflectable fields. This is
    // a real empty sequence, distinct from a generic subject deferred to an instance.
    empty: bool,
    // The subject is still a comptime parameter, so there is nothing to enumerate
    // yet. The template body is checked symbolically once and each instance is checked
    // again with the parameter bound, and that is where the unrolling belongs.
    deferred: bool,
}

// `meta.fields[T]()` written as a whole call: a bracket receiver under a call node.
fn meta_sequence(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (MetaSequence, err) {
    var info: MetaSequence = zero
    let node = tree.nodes[node_index]
    if node.kind != .CallExpr { ret (info, ok) }
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver { ret (info, ok) }
    let receiver = tree.nodes[receiver_index]
    if receiver.kind != .BracketPostfix { ret (info, ok) }
    let end = usize(receiver.first_child) + usize(receiver.child_count)
    var at = usize(receiver.first_child)
    var child_count = 0usize
    var base_index = 0usize
    var type_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_count == 0usize {
                base_index = parse.child_index_at(tree, at)
            } else {
                type_index = parse.child_index_at(tree, at)
            }
            child_count += 1usize
        }
        at += 1usize
    }
    if child_count == 0usize { ret (info, ok) }
    let base = tree.nodes[base_index]
    if base.kind != .FieldExpr { ret (info, ok) }
    let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, base)
    if !found_member || !same(g.modules[target_module].name, "e.meta") { ret (info, ok) }
    var kind: MetaSequenceKind = .None
    if same(member, "fields") { kind = .Fields }
    if same(member, "members") { kind = .Members }
    if kind == .None { ret (info, ok) }
    info.kind = kind
    if child_count != 2usize { ret (info, ArgumentCount) }
    let (subject, subject_error) = comptime_type(c, g, tree, module_index, type_index)
    if subject_error != ok { ret (info, subject_error) }
    if type_shape_unknown(subject) {
        info.subject = subject
        info.deferred = true
        ret (info, ok)
    }
    let (aggregate_index, found_aggregate) = aggregate_for_type(c, subject)
    if !found_aggregate {
        record_failure(c, module_index, tree.nodes[type_index], .MetaShape, subject.name, member)
        ret (info, InvalidType)
    }
    let aggregate = c.aggregates[aggregate_index]
    // `fields` on a bare union is a compile error: its members overlap by design and
    // there is no fact about which one is live. `members` needs a tag list, which only
    // an enum or a tagged union has.
    if kind == .Fields {
        if aggregate.kind != .Struct && aggregate.kind != .TaggedUnion {
            record_failure(c, module_index, tree.nodes[type_index], .MetaShape, subject.name, member)
            ret (info, InvalidType)
        }
    } else {
        if aggregate.kind != .Enum && aggregate.kind != .TaggedUnion {
            record_failure(c, module_index, tree.nodes[type_index], .MetaShape, subject.name, member)
            ret (info, InvalidType)
        }
    }
    info.subject = subject
    info.aggregate_index = aggregate_index
    if kind == .Fields && resource_type(c, subject) && !seeded_arena(c, subject) && aggregate.module_index != module_index { info.empty = true }
    ret (info, ok)
}

// The comptime value the unrolled body sees for one step. For a tagged union `fields`
// skips the payloadless variants, so the step index and the field index differ; the
// caller walks fields and asks for each in turn.
fn meta_sequence_binding(c: *Checker, sequence: MetaSequence, field_index: usize) -> (GenericArgument, bool) {
    var argument: GenericArgument = zero
    let aggregate = c.aggregates[sequence.aggregate_index]
    if field_index >= aggregate.field_count { ret (argument, false) }
    let entry = c.aggregate_fields[aggregate.first_field + field_index]
    argument.set = true
    argument.text = entry.name
    if sequence.kind == .Members {
        argument.kind = .Member
        argument.owner = sequence.aggregate_index
        argument.value = entry.enum_value
        if entry.enum_negative {
            // Section 9 reads the backing value as two's complement, so one `u64` holds
            // a negative member of a signed enum and a large one of an unsigned enum.
            argument.value = 0usize -% entry.enum_value
        }
        ret (argument, true)
    }
    // A payloadless variant of a tagged union has no `Field`.
    if aggregate.kind == .TaggedUnion && entry.ty.kind == .Void { ret (argument, false) }
    argument.kind = .Field
    argument.ty = entry.ty
    argument.owner = sequence.aggregate_index
    argument.value = field_index
    ret (argument, true)
}

// One checked copy of the body per step. Nothing is added to `c.locals`: the binding
// is a comptime value, not a local, so the body reaches it through the binding stack.
fn check_unrolled_for(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function, sequence: MetaSequence, name: str, block_index: usize) -> err {
    if sequence.empty { ret ok }
    let aggregate = c.aggregates[sequence.aggregate_index]
    var field_at = 0usize
    while field_at < aggregate.field_count {
        let (argument, present) = meta_sequence_binding(c, sequence, field_at)
        if present {
            if c.resources_on && module_is_format_codec(c, module_index) && affine_kind(c, argument.ty, 0usize) != 0u8 {
                record_failure(c, module_index, node, .ResourceCopy, argument.text, "a format codec")
                ret ResourceViolation
            }
            let depth = c.comptime_binding_count
            if name.len != 0usize { try push_comptime_binding(c, name, argument) }
            let checkpoint = c.local_count
            let body_error = check_block(c, r, g, tree, module_index, tree.nodes[block_index], function)
            c.local_count = checkpoint
            c.comptime_binding_count = depth
            begin_call_scope(c)
            if body_error != ok { ret body_error }
        }
        field_at += 1usize
    }
    ret ok
}

// A member of a comptime `Field` or `Member`, which is the only way the body of an
// unrolled `for` reads its binding. `ty` is a type and stands only where a type
// stands, so it is answered by `comptime_type` rather than here.
fn comptime_binding_member(c: *Checker, argument: GenericArgument, member: str, module_index: usize) -> (Type, bool) {
    if argument.kind == .Field {
        if same(member, "name") { ret (make_type(.String, "str", module_index), true) }
        if same(member, "offset") { ret (make_type(.Integer, "usize", module_index), true) }
        if same(member, "size") { ret (make_type(.Integer, "usize", module_index), true) }
        ret (invalid_type(), false)
    }
    if argument.kind == .Member {
        if same(member, "name") { ret (make_type(.String, "str", module_index), true) }
        if same(member, "value") { ret (make_type(.Integer, "u64", module_index), true) }
        ret (invalid_type(), false)
    }
    ret (invalid_type(), false)
}

// The base of `f.name` where `f` is bound by an unrolled `for`.
// `u8.trunc(x)`, or `T.trunc(x)` with `T` a type parameter: the receiver names an integer
// type and the member is `trunc`. In the template pass `T` is not yet bound and the cast
// stands as one to a type not yet known, the way `T(x)` does (D136).
fn truncation_cast(c: *Checker, text: str, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> (Type, bool) {
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret (invalid_type(), false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (invalid_type(), false) }
    let base_token = c.tokens[usize(base_node.token_start)]
    if base_token.kind != .Identifier { ret (invalid_type(), false) }
    var member = ""
    var at = usize(base_node.token_end)
    while at < usize(node.token_end) && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if !same(member, "trunc") { ret (invalid_type(), false) }
    let name = text[base_token.start..base_token.end]
    let scalar = scalar_type(name, module_index)
    if scalar.kind == .Integer { ret (scalar, true) }
    let (parameter_index, is_parameter) = active_comptime_parameter(c, name)
    if !is_parameter || c.comptime_parameters[parameter_index].kind != .Type { ret (invalid_type(), false) }
    let (argument, argument_found) = active_argument(c, parameter_index)
    if argument_found {
        if argument.ty.kind != .Integer { ret (invalid_type(), false) }
        ret (argument.ty, true)
    }
    var parameter_cast = make_type(.TypeParameter, name, module_index)
    parameter_cast.element = parameter_index
    parameter_cast.has_element = true
    ret (parameter_cast, true)
}

fn comptime_binding_base(c: *Checker, text: str, tree: *parse.Tree, node: syntax.Node) -> (GenericArgument, str, bool) {
    var empty: GenericArgument = zero
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret (empty, "", false) }
    let base_node = tree.nodes[base_index]
    if base_node.kind != .NameExpr { ret (empty, "", false) }
    let base_token = c.tokens[usize(base_node.token_start)]
    if base_token.kind != .Identifier { ret (empty, "", false) }
    let (argument, found) = find_comptime_binding(c, text[base_token.start..base_token.end])
    if !found { ret (empty, "", false) }
    var member = ""
    var at = usize(base_node.token_end)
    while at < usize(node.token_end) && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .Identifier { member = text[token.start..token.end] }
        at += 1usize
    }
    if member.len == 0usize { ret (empty, "", false) }
    ret (argument, member, true)
}

fn check_for_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var names: [2]str = zero
    var name_count = 0usize
    var token_at = usize(node.token_start) + 1usize
    let text = g.modules[module_index].text
    while token_at < usize(node.token_end) && c.tokens[token_at].kind != .KwIn {
        let token = c.tokens[token_at]
        if token.kind == .Identifier || token.kind == .PunctUnderscore {
            if name_count == 2usize { ret ArgumentCount }
            if token.kind == .Identifier { names[name_count] = text[token.start..token.end] }
            name_count += 1usize
        }
        token_at += 1usize
    }
    if token_at == usize(node.token_end) || name_count == 0usize { ret parse.InvalidSyntax }
    var expressions: [2]usize = zero
    var expression_count = 0usize
    var block_index = 0usize
    var has_block = false
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if tree.nodes[child_index].kind == .Block {
                block_index = child_index
                has_block = true
            } else {
                if expression_count == 2usize { ret ArgumentCount }
                expressions[expression_count] = child_index
                expression_count += 1usize
            }
        }
        at += 1usize
    }
    if !has_block || expression_count == 0usize { ret parse.InvalidSyntax }
    // Section 9: a `for` whose subject is a comptime value is always unrolled, and the
    // binding is a distinct comptime value in each copy -- which is what lets the body
    // use it where only a comptime value may stand. The body is checked once per step
    // rather than once, because each copy sees a different type in `f.ty`.
    if expression_count == 1usize {
        let (sequence, sequence_error) = meta_sequence(c, g, tree, module_index, expressions[0usize])
        if sequence_error != ok { ret sequence_error }
        if sequence.kind != .None {
            if name_count != 1usize { ret ArgumentCount }
            if sequence.deferred { ret ok }
            ret check_unrolled_for(c, r, g, tree, module_index, node, function, sequence, names[0usize], block_index)
        }
    }
    let checkpoint = c.local_count
    if expression_count == 2usize {
        if name_count != 1usize { ret ArgumentCount }
        let (raw_first, first_error) = check_expr(c, g, tree, module_index, expressions[0usize], invalid_type())
        if first_error != ok { ret first_error }
        var second_expected = raw_first
        if is_untyped(raw_first) { second_expected = invalid_type() }
        let (raw_second, second_error) = check_expr(c, g, tree, module_index, expressions[1usize], second_expected)
        if second_error != ok { ret second_error }
        var first = raw_first
        var second = raw_second
        if is_untyped(first) && !is_untyped(second) {
            let (contextual_first, context_error) = apply_context(c, first, second)
            if context_error != ok { ret context_error }
            first = contextual_first
        }
        if !is_untyped(first) && is_untyped(second) {
            let (contextual_second, context_error) = apply_context(c, second, first)
            if context_error != ok { ret context_error }
            second = contextual_second
        }
        if !type_equal(c, first, second) {
            if !c.generic_declaration || !types_may_match_after_instantiation(c, first, second) { ret TypeMismatch }
        }
        if is_untyped(first) { ret MissingContext }
        if !is_integer(first) {
            if !c.generic_declaration || !type_shape_unknown(first) { ret InvalidType }
        }
        if names[0usize].len != 0usize { try add_local(c, names[0usize], first, false) }
    } else {
        let (iterable, iterable_error) = check_expr(c, g, tree, module_index, expressions[0usize], invalid_type())
        if iterable_error != ok { ret iterable_error }
        let (resolved_element, element_error) = index_element_type(c, iterable, module_index)
        var element = resolved_element
        if element_error != ok {
            if c.generic_declaration && type_shape_unknown(iterable) {
                element = dependent_expression_type(iterable, invalid_type(), module_index)
            } else {
                let (protocol_element, protocol_error) = protocol_iteration_element(c, g, tree, module_index, node, expressions[0usize], iterable, name_count)
                if protocol_error != ok { ret protocol_error }
                element = protocol_element
            }
        }
        if name_count == 1usize {
            if names[0usize].len != 0usize { try add_local(c, names[0usize], element, false) }
        } else {
            if names[0usize].len != 0usize { try add_local(c, names[0usize], make_type(.Integer, "usize", module_index), false) }
            if names[1usize].len != 0usize { try add_local(c, names[1usize], element, false) }
        }
    }
    if c.loop_depth < c.loop_locals.len { c.loop_locals[c.loop_depth] = c.local_count }
    if c.break_depth < c.break_locals.len { c.break_locals[c.break_depth] = c.local_count }
    c.loop_depth += 1usize
    c.break_depth += 1usize
    var before: []u8 = zero
    let tracked = any_affine_local(c)
    if tracked {
        let (snapshot, snapshot_error) = resource_snapshot(c, c.local_count)
        if snapshot_error != ok { ret snapshot_error }
        before = snapshot
    }
    let body_error = check_block(c, r, g, tree, module_index, tree.nodes[block_index], function)
    c.loop_depth = c.loop_depth - 1usize
    c.break_depth = c.break_depth - 1usize
    if body_error == ok && tracked { try resource_loop_check(c, g, module_index, tree.nodes[block_index], before) }
    c.local_count = checkpoint
    ret body_error
}

fn check_statement_kind(kind: syntax.Kind) -> bool {
    ret kind == .BindingStmt || kind == .AssignmentStmt || kind == .CallStmt || kind == .TryStmt || kind == .ReturnStmt || kind == .DeferStmt || kind == .NocheckStmt || kind == .SharedVarStmt || kind == .BreakStmt || kind == .ContinueStmt || kind == .IfStmt || kind == .WhileStmt || kind == .ForStmt || kind == .WhenStmt || kind == .SwitchStmt || kind == .ErrorNode
}

fn switch_member_name(c: *Checker, text: str, node: syntax.Node) -> (str, bool) {
    if node.kind != .MemberExpr && node.kind != .FieldExpr { ret ("", false) }
    var name = ""
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = c.tokens[at]
        if token.kind == .Identifier { name = text[token.start..token.end] }
        at += 1usize
    }
    ret (name, name.len != 0usize)
}

fn unwrap_switch_case(tree: *parse.Tree, node_index: usize) -> usize {
    let node = tree.nodes[node_index]
    if node.kind != .GroupExpr { ret node_index }
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret node_index }
    ret unwrap_switch_case(tree, child_index)
}

fn switch_case_key(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, subject: Type, aggregate_index: usize, has_aggregate: bool) -> (SwitchKey, usize, bool, err) {
    var key: SwitchKey = zero
    let unwrapped_index = unwrap_switch_case(tree, node_index)
    let node = tree.nodes[unwrapped_index]
    let text = g.modules[module_index].text
    if has_aggregate {
        let aggregate = c.aggregates[aggregate_index]
        if aggregate.kind == .TaggedUnion {
            if node.kind != .MemberExpr { ret (key, 0usize, false, InvalidSwitch) }
        } else {
            let (_, case_error) = check_expr(c, g, tree, module_index, unwrapped_index, subject)
            if case_error != ok { ret (key, 0usize, false, case_error) }
        }
        let (member, has_member) = switch_member_name(c, text, node)
        if !has_member { ret (key, 0usize, false, InvalidSwitch) }
        let (field_index, found_field) = aggregate_field_for_name(c, aggregate, member)
        if !found_field { ret (key, 0usize, false, InvalidSwitch) }
        key.kind = .Member
        key.name = member
        ret (key, field_index, true, ok)
    }
    let (_, case_error) = check_expr(c, g, tree, module_index, unwrapped_index, subject)
    if case_error != ok { ret (key, 0usize, false, case_error) }
    if subject.kind == .Integer {
        let checkpoint = c.constant_expr_count
        let (expression_index, copy_error) = copy_constant_expr(c, g, tree, module_index, unwrapped_index)
        if copy_error != ok {
            c.constant_expr_count = checkpoint
            ret (key, 0usize, false, InvalidConstant)
        }
        let (value, value_type, value_error) = evaluate_constant_expr(c, expression_index, subject)
        c.constant_expr_count = checkpoint
        if value_error != ok || !is_integer(value_type) || !integer_representable(value, subject) { ret (key, 0usize, false, InvalidConstant) }
        key.kind = .Integer
        key.integer = value
        ret (key, 0usize, false, ok)
    }
    if subject.kind == .Bool {
        if node.kind != .LiteralExpr { ret (key, 0usize, false, InvalidConstant) }
        let token = c.tokens[usize(node.token_start)]
        if token.kind != .KwTrue && token.kind != .KwFalse { ret (key, 0usize, false, InvalidConstant) }
        key.kind = .Bool
        key.boolean = token.kind == .KwTrue
        ret (key, 0usize, false, ok)
    }
    if subject.kind == .Err {
        key.kind = .Error
        if node.kind == .LiteralExpr && c.tokens[usize(node.token_start)].kind == .KwOk {
            key.name = "ok"
            ret (key, 0usize, false, ok)
        }
        if node.kind == .NameExpr {
            let token = c.tokens[usize(node.token_start)]
            if token.kind != .Identifier { ret (key, 0usize, false, InvalidConstant) }
            key.module_index = module_index
            key.name = text[token.start..token.end]
            ret (key, 0usize, false, ok)
        }
        if node.kind == .FieldExpr {
            let (target_module, member, found_member) = qualified_member(c, g, tree, module_index, node)
            if !found_member { ret (key, 0usize, false, InvalidConstant) }
            key.module_index = target_module
            key.name = member
            ret (key, 0usize, false, ok)
        }
        ret (key, 0usize, false, InvalidConstant)
    }
    ret (key, 0usize, false, InvalidSwitch)
}

fn switch_keys_equal(left: SwitchKey, right: SwitchKey) -> bool {
    if left.kind != right.kind { ret false }
    if left.kind == .Integer { ret left.integer.magnitude == right.integer.magnitude && left.integer.negative == right.integer.negative }
    if left.kind == .Bool { ret left.boolean == right.boolean }
    if left.kind == .Error { ret left.module_index == right.module_index && same(left.name, right.name) }
    if left.kind == .Member { ret same(left.name, right.name) }
    ret false
}

fn switch_case_seen_before(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, switch_node: syntax.Node, current_index: usize, subject: Type, aggregate_index: usize, has_aggregate: bool, current: SwitchKey) -> (bool, err) {
    let end = usize(switch_node.first_child) + usize(switch_node.child_count)
    var at = usize(switch_node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .SwitchArm {
                let arm_end = usize(child.first_child) + usize(child.child_count)
                var arm_at = usize(child.first_child)
                while arm_at < arm_end {
                    if parse.child_is_node_at(tree, arm_at) {
                        let prior_index = parse.child_index_at(tree, arm_at)
                        let prior = tree.nodes[prior_index]
                        if !check_statement_kind(prior.kind) {
                            if prior_index == current_index { ret (false, ok) }
                            let (prior_key, prior_field, prior_has_field, prior_error) = switch_case_key(c, g, tree, module_index, prior_index, subject, aggregate_index, has_aggregate)
                            if prior_error != ok { ret (false, prior_error) }
                            if switch_keys_equal(prior_key, current) { ret (true, ok) }
                        }
                    }
                    arm_at += 1usize
                }
            }
        }
        at += 1usize
    }
    ret (false, ok)
}

fn switch_capture_name(c: *Checker, text: str, arm: syntax.Node) -> (str, bool) {
    var saw_as = false
    var at = usize(arm.token_start)
    while at < usize(arm.token_end) {
        let token = c.tokens[at]
        if token.kind == .KwAs {
            saw_as = true
        } else {
            if saw_as && token.kind == .Identifier { ret (text[token.start..token.end], true) }
        }
        at += 1usize
    }
    ret ("", false)
}

fn store_checked_switch(c: *Checker, module_index: usize, token_start: usize, returns: bool) -> err {
    if c.checked_switch_count == c.checked_switches.len { ret Capacity }
    c.checked_switches[c.checked_switch_count] = CheckedSwitch { module_index: module_index, token_start: token_start, returns: returns }
    c.checked_switch_count += 1usize
    ret ok
}

fn checked_switch_returns(c: *Checker, module_index: usize, token_start: usize) -> bool {
    var at = c.checked_switch_count
    while at > 0usize {
        at = at - 1usize
        let item = c.checked_switches[at]
        if item.module_index == module_index && usize(item.token_start) == token_start { ret item.returns }
    }
    ret false
}

fn switch_arm_returns(c: *Checker, tree: *parse.Tree, module_index: usize, arm: syntax.Node) -> bool {
    let end = usize(arm.first_child) + usize(arm.child_count)
    var at = usize(arm.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if check_statement_kind(child.kind) && statement_returns(c, tree, module_index, child) { ret true }
        }
        at += 1usize
    }
    ret false
}

fn switch_has_member(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, name: str) -> bool {
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let arm = tree.nodes[parse.child_index_at(tree, at)]
            if arm.kind == .SwitchArm && c.tokens[usize(arm.token_start)].kind != .KwDefault {
                let arm_end = usize(arm.first_child) + usize(arm.child_count)
                var arm_at = usize(arm.first_child)
                while arm_at < arm_end {
                    if parse.child_is_node_at(tree, arm_at) {
                        let value = tree.nodes[parse.child_index_at(tree, arm_at)]
                        if !check_statement_kind(value.kind) {
                            let (member, found) = switch_member_name(c, g.modules[module_index].text, value)
                            if found && same(member, name) { ret true }
                        }
                    }
                    arm_at += 1usize
                }
            }
        }
        at += 1usize
    }
    ret false
}

fn check_dependent_switch(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var default_seen = false
    var arm_count = 0usize
    var returning_arm_count = 0usize
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let arm = tree.nodes[parse.child_index_at(tree, at)]
            if arm.kind == .SwitchArm {
                arm_count += 1usize
                let checkpoint = c.local_count
                let is_default = c.tokens[usize(arm.token_start)].kind == .KwDefault
                if is_default {
                    if default_seen { ret DuplicateCase }
                    default_seen = true
                } else {
                    var case_count = 0usize
                    let arm_end = usize(arm.first_child) + usize(arm.child_count)
                    var case_at = usize(arm.first_child)
                    while case_at < arm_end {
                        if parse.child_is_node_at(tree, case_at) && !check_statement_kind(tree.nodes[parse.child_index_at(tree, case_at)].kind) { case_count += 1usize }
                        case_at += 1usize
                    }
                    if case_count == 0usize { ret parse.InvalidSyntax }
                }
                let (capture, has_capture) = switch_capture_name(c, g.modules[module_index].text, arm)
                if has_capture {
                    if is_default { ret InvalidSwitch }
                    let capture_error = add_local(c, capture, make_type(.TypeParameter, "", module_index), false)
                    if capture_error != ok {
                        c.local_count = checkpoint
                        ret capture_error
                    }
                }
                c.break_depth += 1usize
                let arm_end = usize(arm.first_child) + usize(arm.child_count)
                var arm_at = usize(arm.first_child)
                var body_error = ok
                while arm_at < arm_end {
                    if parse.child_is_node_at(tree, arm_at) {
                        let statement_index = parse.child_index_at(tree, arm_at)
                        if check_statement_kind(tree.nodes[statement_index].kind) {
                            body_error = check_statement(c, r, g, tree, module_index, statement_index, function)
                            if body_error != ok { break }
                        }
                    }
                    arm_at += 1usize
                }
                c.break_depth = c.break_depth - 1usize
                if body_error == ok && switch_arm_returns(c, tree, module_index, arm) { returning_arm_count += 1usize }
                c.local_count = checkpoint
                if body_error != ok { ret body_error }
            }
        }
        at += 1usize
    }
    ret store_checked_switch(c, module_index, usize(node.token_start), default_seen && arm_count != 0usize && arm_count == returning_arm_count)
}

fn check_switch_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    // The arms' resource states (D345), joined after the switch.
    var joined: []u8 = zero
    var joined_count = 0usize
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
    let (subject, subject_error) = check_expr(c, g, tree, module_index, subject_index, invalid_type())
    if subject_error != ok { ret subject_error }
    if c.generic_declaration && type_shape_unknown(subject) { ret check_dependent_switch(c, r, g, tree, module_index, node, function) }
    let (aggregate_index, has_aggregate) = aggregate_for_type(c, subject)
    if has_aggregate {
        let aggregate_kind = c.aggregates[aggregate_index].kind
        if aggregate_kind != .Enum && aggregate_kind != .TaggedUnion { ret InvalidSwitch }
    } else {
        if subject.kind != .Integer && subject.kind != .Bool && subject.kind != .Err { ret InvalidSwitch }
    }
    var default_seen = false
    var covered_count = 0usize
    var arm_count = 0usize
    var returning_arm_count = 0usize
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let arm = tree.nodes[parse.child_index_at(tree, at)]
            if arm.kind == .SwitchArm {
                arm_count += 1usize
                let checkpoint = c.local_count
                let is_default = c.tokens[usize(arm.token_start)].kind == .KwDefault
                var case_count = 0usize
                var captured_field_index = 0usize
                var has_captured_field = false
                let arm_end = usize(arm.first_child) + usize(arm.child_count)
                var arm_at = usize(arm.first_child)
                if is_default {
                    if default_seen { ret DuplicateCase }
                    default_seen = true
                } else {
                    while arm_at < arm_end {
                        if parse.child_is_node_at(tree, arm_at) {
                            let case_index = parse.child_index_at(tree, arm_at)
                            if !check_statement_kind(tree.nodes[case_index].kind) {
                                let (key, field_index, has_field, key_error) = switch_case_key(c, g, tree, module_index, case_index, subject, aggregate_index, has_aggregate)
                                if key_error != ok { ret key_error }
                                let (duplicate, duplicate_error) = switch_case_seen_before(c, g, tree, module_index, node, case_index, subject, aggregate_index, has_aggregate, key)
                                if duplicate_error != ok { ret duplicate_error }
                                if duplicate { ret DuplicateCase }
                                case_count += 1usize
                                if has_aggregate { covered_count += 1usize }
                                captured_field_index = field_index
                                has_captured_field = has_field
                            }
                        }
                        arm_at += 1usize
                    }
                    if case_count == 0usize { ret parse.InvalidSyntax }
                }
                let (capture, has_capture) = switch_capture_name(c, g.modules[module_index].text, arm)
                if has_capture {
                    if is_default || subject.kind != .Named || !has_aggregate || c.aggregates[aggregate_index].kind != .TaggedUnion || case_count != 1usize || !has_captured_field { ret InvalidSwitch }
                    let payload = c.aggregate_fields[captured_field_index].ty
                    if payload.kind == .Void { ret InvalidSwitch }
                    let capture_error = add_local(c, capture, payload, false)
                    if capture_error != ok {
                        c.local_count = checkpoint
                        ret capture_error
                    }
                }
                if c.break_depth < c.break_locals.len { c.break_locals[c.break_depth] = checkpoint }
                c.break_depth += 1usize
                // The resources before the arm (D345), for the join after every arm.
                var before: []u8 = zero
                let tracked = any_affine_local(c)
                if tracked {
                    let (snapshot, snapshot_error) = resource_snapshot(c, checkpoint)
                    if snapshot_error != ok { ret snapshot_error }
                    before = snapshot
                }
                arm_at = usize(arm.first_child)
                var body_error = ok
                while arm_at < arm_end {
                    if parse.child_is_node_at(tree, arm_at) {
                        let statement_index = parse.child_index_at(tree, arm_at)
                        if check_statement_kind(tree.nodes[statement_index].kind) {
                            body_error = check_statement(c, r, g, tree, module_index, statement_index, function)
                            if body_error != ok { break }
                        }
                    }
                    arm_at += 1usize
                }
                c.break_depth = c.break_depth - 1usize
                let arm_returns = switch_arm_returns(c, tree, module_index, arm)
                if body_error == ok && arm_returns { returning_arm_count += 1usize }
                if body_error == ok && tracked && !arm_returns && !resource_diverges(c, g, tree, module_index, arm) {
                    var closing = arm
                    if arm.token_end > arm.token_start { closing.token_start = arm.token_end - 1u32 }
                    body_error = resource_audit(c, g, module_index, closing, checkpoint, .ResourceCleanupForgotten)
                    if body_error == ok {
                        let (after, after_error) = resource_snapshot(c, checkpoint)
                        if after_error != ok { ret after_error }
                        if joined_count == 0usize { joined = after } else { resource_join_states(c, joined, after) }
                        joined_count += 1usize
                    }
                }
                if tracked { resource_restore(c, before) }
                c.local_count = checkpoint
                if body_error != ok { ret body_error }
            }
        }
        at += 1usize
    }
    if has_aggregate && !default_seen && covered_count != c.aggregates[aggregate_index].field_count {
        let aggregate = c.aggregates[aggregate_index]
        var missing = ""
        var field_at = 0usize
        while field_at < aggregate.field_count {
            let field = c.aggregate_fields[aggregate.first_field + field_at]
            if !switch_has_member(c, g, tree, module_index, node, field.name) {
                missing = field.name
                break
            }
            field_at += 1usize
        }
        record_failure(c, module_index, node, .NonExhaustive, missing, "")
        ret NonExhaustiveSwitch
    }
    let exhaustive = default_seen || has_aggregate
    ret store_checked_switch(c, module_index, usize(node.token_start), exhaustive && arm_count != 0usize && arm_count == returning_arm_count)
}

fn check_defer_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let (child_index, found) = first_node_child(tree, node)
    if !found { ret parse.InvalidSyntax }
    let checkpoint = c.local_count
    let saved_loop_depth = c.loop_depth
    let saved_break_depth = c.break_depth
    c.loop_depth = 0usize
    c.break_depth = 0usize
    c.defer_depth += 1usize
    let child = tree.nodes[child_index]
    var body_error = ok
    if child.kind == .Block {
        body_error = check_block(c, r, g, tree, module_index, child, function)
    } else {
        body_error = check_statement(c, r, g, tree, module_index, child_index, function)
    }
    c.defer_depth = c.defer_depth - 1usize
    c.loop_depth = saved_loop_depth
    c.break_depth = saved_break_depth
    c.local_count = checkpoint
    if body_error == ArgumentCount && c.failure_kind == .Generic {
        c.failure_kind = .DeferValue
        if c.diagnostic_count != 0usize { c.diagnostics[0usize].kind = .DeferValue }
    }
    ret body_error
}

fn assignment_place_type(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (Type, err) {
    let place = tree.nodes[node_index]
    if place.kind == .NameExpr {
        let token = c.tokens[usize(place.token_start)]
        let name = g.modules[module_index].text[token.start..token.end]
        let (local_index, found) = find_local(c, name)
        if found {
            if !c.locals[local_index].mutable {
                record_failure(c, module_index, place, .AssignmentImmutable, name, "")
                ret (invalid_type(), ImmutableAssignment)
            }
            ret (c.locals[local_index].ty, ok)
        }
        // A module-scope `var` is assignable wherever it is visible. It is mutable by its own
        // keyword -- there is no `const`-spelled static, since that is what `const` already is --
        // so there is no immutability to check here, only whether the name is one.
        let (global_index, global_found) = find_global(c, module_index, name)
        if global_found { ret (c.globals[global_index].ty, ok) }
        ret (invalid_type(), Unsupported)
    }
    if place.kind == .UnaryExpr && c.tokens[usize(place.token_start)].kind == .PunctStar {
        let (child_index, found) = first_node_child(tree, place)
        if !found { ret (invalid_type(), parse.InvalidSyntax) }
        let (pointer, pointer_error) = check_expr(c, g, tree, module_index, child_index, invalid_type())
        if pointer_error != ok { ret (invalid_type(), pointer_error) }
        if pointer.kind != .Pointer || !pointer.has_element || pointer.element >= c.type_count {
            if c.generic_declaration && type_shape_unknown(pointer) { ret (dependent_expression_type(pointer, invalid_type(), module_index), ok) }
            ret (invalid_type(), ImmutableAssignment)
        }
        if pointer.is_const {
            record_failure(c, module_index, place, .AssignmentImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        let element = c.types[pointer.element]
        if element.kind == .Void { ret (invalid_type(), InvalidOperator) }
        ret (element, ok)
    }
    if place.kind == .BracketPostfix {
        var bracket: BracketInfo = zero
        let bracket_error = read_bracket(c, tree, place, &bracket)
        if bracket_error != ok { ret (invalid_type(), bracket_error) }
        if bracket.range || usize(bracket.child_count) != 2usize { ret (invalid_type(), Unsupported) }
        let (base, base_error) = check_expr(c, g, tree, module_index, bracket.base, invalid_type())
        if base_error != ok { ret (invalid_type(), base_error) }
        let (element, element_error) = index_element_type(c, base, module_index)
        if element_error != ok {
            if !c.generic_declaration || !type_shape_unknown(base) { ret (invalid_type(), element_error) }
            let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, make_type(.Integer, "usize", module_index))
            if index_error != ok { ret (invalid_type(), index_error) }
            ret (dependent_expression_type(base, invalid_type(), module_index), ok)
        }
        let (_, index_error) = check_expr(c, g, tree, module_index, bracket.first, make_type(.Integer, "usize", module_index))
        if index_error != ok { ret (invalid_type(), index_error) }
        var mutable = false
        if base.kind == .Slice { mutable = !base.is_const }
        if base.kind == .Array || is_vector_type(c, base) {
            let (place_mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, bracket.base)
            if mutable_error != ok { ret (invalid_type(), mutable_error) }
            mutable = place_mutable
        }
        if !mutable {
            if base.kind == .Array || is_vector_type(c, base) {
                record_failure(c, module_index, place, .IndexedArrayImmutable, "", "")
            } else {
                record_failure(c, module_index, place, .IndexedElementsImmutable, "", "")
            }
            ret (invalid_type(), ImmutableAssignment)
        }
        ret (element, ok)
    }
    if place.kind == .FieldExpr {
        let (field_type, field_error) = check_expr(c, g, tree, module_index, node_index, invalid_type())
        if field_error != ok { ret (invalid_type(), field_error) }
        let (mutable, mutable_error) = direct_place_mutable(c, g, tree, module_index, node_index)
        if mutable_error != ok { ret (invalid_type(), mutable_error) }
        if !mutable {
            record_failure(c, module_index, place, .AssignmentImmutable, "", "")
            ret (invalid_type(), ImmutableAssignment)
        }
        ret (field_type, ok)
    }
    ret (invalid_type(), Unsupported)
}

fn assignment_operator(c: *Checker, left_end: usize, right_start: usize) -> lex.Kind {
    var at = left_end
    while at < right_start {
        let kind = c.tokens[at].kind
        if kind != .Newline { ret kind }
        at += 1usize
    }
    ret .Invalid
}

fn check_compound_assignment(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, place_index: usize, value_index: usize, op: lex.Kind) -> err {
    let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, place_index)
    if place_error != ok { ret place_error }
    if op == .PunctShiftLeftAssign || op == .PunctShiftRightAssign {
        if !is_integer(place_type) || is_untyped(place_type) {
            if !c.generic_declaration || !type_shape_unknown(place_type) { ret InvalidOperator }
        }
        let (right_type, right_error) = check_expr(c, g, tree, module_index, value_index, invalid_type())
        if right_error != ok { ret right_error }
        var count_type = right_type
        if right_type.kind == .UntypedInteger {
            let (contextual, context_error) = apply_context(c, right_type, make_type(.Integer, "u32", module_index))
            if context_error != ok { ret context_error }
            count_type = contextual
        }
        if count_type.kind != .Integer || !unsigned_integer_type(count_type) { ret InvalidOperator }
        ret ok
    }
    let (_, value_error) = check_expr(c, g, tree, module_index, value_index, place_type)
    if value_error != ok { ret value_error }
    if op == .PunctAddAssign || op == .PunctSubAssign || op == .PunctMulAssign || op == .PunctDivAssign {
        if !is_numeric(place_type) && (!c.generic_declaration || !type_shape_unknown(place_type)) { ret InvalidOperator }
        ret ok
    }
    if op == .PunctRemAssign || op == .PunctAddWrapAssign || op == .PunctSubWrapAssign || op == .PunctMulWrapAssign || op == .PunctBitAndAssign || op == .PunctBitXorAssign || op == .PunctBitOrAssign {
        if !is_integer(place_type) && (!c.generic_declaration || !type_shape_unknown(place_type)) { ret InvalidOperator }
        ret ok
    }
    ret Unsupported
}

fn assignment_place_is_global(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> bool {
    var base_index = node_index
    while tree.nodes[base_index].kind == .FieldExpr || tree.nodes[base_index].kind == .BracketPostfix {
        let (child_index, has_child) = first_node_child(tree, tree.nodes[base_index])
        if !has_child { ret false }
        base_index = child_index
    }
    let base = tree.nodes[base_index]
    if base.kind != .NameExpr { ret false }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret false }
    let name = g.modules[module_index].text[token.start..token.end]
    let (_, found) = find_global(c, module_index, name)
    ret found
}

fn check_assignment(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var count = 0usize
    var first_index = 0usize
    var initializer_index = 0usize
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if count == 0usize { first_index = parse.child_index_at(tree, at) }
            initializer_index = parse.child_index_at(tree, at)
            count += 1usize
        }
        at += 1usize
    }
    if count < 2usize { ret Unsupported }
    let initializer = tree.nodes[initializer_index]
    let op = assignment_operator(c, usize(tree.nodes[first_index].token_end), usize(initializer.token_start))
    if op == .Invalid { ret Unsupported }
    let tried = contains_token(c, usize(node.token_start), usize(initializer.token_start), .KwTry)
    if count == 2usize && !tried {
        if op != .PunctAssign { ret check_compound_assignment(c, g, tree, module_index, first_index, initializer_index, op) }
        let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, first_index)
        if place_error != ok { ret place_error }
        let (actual, expression_error) = check_expr(c, g, tree, module_index, initializer_index, place_type)
        if expression_error != ok { ret expression_error }
        let noescape_from = expression_noescape_from(c, g, tree, module_index, function, initializer_index)
        if noescape_from != 0usize && holds_pointer(c, place_type, 0usize) && assignment_place_is_global(c, g, tree, module_index, first_index) {
            let parameter = c.parameters[function.first_parameter + noescape_from - 1usize]
            record_failure(c, module_index, initializer, .NoEscapeContract, parameter.name, "")
            ret ResourceViolation
        }
        // `dst[i] = src[j]` over a resource type copies the bits of a handle (D349):
        // an element read is a view, and a view stored is a second owner.
        if c.resources_on && tree.nodes[first_index].kind == .BracketPostfix && initializer.kind == .BracketPostfix && affine_kind(c, place_type, 0usize) != 0u8 {
            record_failure(c, module_index, node, .ResourceCopy, place_type.name, "an element copied to an element")
            ret ResourceViolation
        }
        var no_call: CallInfo = zero
        ret resource_assign(c, g, tree, module_index, node, first_index, initializer_index, false, no_call, false)
    }
    if initializer.kind != .CallExpr { ret ArgumentCount }
    let (call, call_error) = check_call(c, g, tree, module_index, initializer)
    if call_error != ok { ret call_error }
    if call.is_cast {
        if tried { ret TryCast }
        ret ArgumentCount
    }
    let callee = call.function
    var result_count = callee.return_count
    if tried {
        let (remaining, try_error) = check_try_results(c, call, function)
        if try_error != ok { ret try_error }
        result_count = remaining
    }
    if count - 1usize != result_count { ret ArgumentCount }
    var result_index = 0usize
    at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) && result_index < result_count {
            let (place_type, place_error) = assignment_place_type(c, g, tree, module_index, parse.child_index_at(tree, at))
            if place_error != ok {
                if place_error == ImmutableAssignment && c.failure_kind == .AssignmentImmutable {
                    c.failure_kind = .MultipleAssignmentImmutable
                    if usize(node.token_start) < c.token_count {
                        c.failure_token = c.tokens[usize(node.token_start)]
                        if c.diagnostic_count != 0usize {
                            c.diagnostics[0usize].kind = .MultipleAssignmentImmutable
                            c.diagnostics[0usize].token = c.tokens[usize(node.token_start)]
                        }
                    }
                }
                ret place_error
            }
            let (result_type, return_error) = call_return(c, call, result_index)
            if return_error != ok { ret return_error }
            let (contextual, context_error) = apply_context(c, result_type, place_type)
            if context_error != ok { ret context_error }
            try resource_assign(c, g, tree, module_index, node, parse.child_index_at(tree, at), initializer_index, true, call, tried)
            result_index += 1usize
        }
        at += 1usize
    }
    ret ok
}

// A statement's tick against the deadline (D540): the clock every 4096 statements.
fn statement_tick(c: *Checker) -> err {
    c.statement_ticks += 1usize
    if (c.statement_ticks & 4095usize) == 0usize && past_deadline(c) {
        c.cancelled_in_function = true
        ret Cancelled
    }
    ret ok
}

fn check_statement_inner(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    try statement_tick(c)
    let node = tree.nodes[node_index]
    if node.kind == .Block { ret check_block(c, r, g, tree, module_index, node, function) }
    // The resources a statement reads (D345), before anything it moves.
    if node.kind != .DeferStmt && node.kind != .NocheckStmt && any_affine_local(c) {
        try resource_uses(c, g, tree, module_index, node_index, node.kind == .AssignmentStmt)
    }
    if node.kind == .BindingStmt { ret check_binding(c, r, g, tree, module_index, node, function) }
    if node.kind == .ReturnStmt { ret check_return(c, g, tree, module_index, node, function) }
    if node.kind == .IfStmt || node.kind == .WhileStmt { ret check_condition_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .WhenStmt { ret check_when_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .ForStmt { ret check_for_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .SwitchStmt { ret check_switch_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .BreakStmt {
        if c.break_depth == 0usize {
            record_failure(c, module_index, node, .BreakOutsideControl, "", "")
            ret Unsupported
        }
        try resource_audit(c, g, module_index, node, c.break_locals[c.break_depth - 1usize], .ResourceCleanupForgotten)
        ret ok
    }
    if node.kind == .ContinueStmt {
        if c.loop_depth == 0usize { ret Unsupported }
        try resource_audit(c, g, module_index, node, c.loop_locals[c.loop_depth - 1usize], .ResourceCleanupForgotten)
        ret ok
    }
    if node.kind == .CallStmt { ret check_call_statement(c, g, tree, module_index, node) }
    if node.kind == .TryStmt { ret check_try_statement(c, g, tree, module_index, node, function) }
    if node.kind == .AssignmentStmt { ret check_assignment(c, g, tree, module_index, node, function) }
    if node.kind == .DeferStmt { ret check_defer_statement(c, r, g, tree, module_index, node, function) }
    if node.kind == .NocheckStmt {
        let checkpoint = c.local_count
        let child_error = check_children(c, r, g, tree, module_index, node, function)
        c.local_count = checkpoint
        ret child_error
    }
    ret Unsupported
}

fn check_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, function: Function) -> err {
    let node = tree.nodes[node_index]
    c.pin_count = 0usize
    let locals_before = c.local_count
    let statement_error = check_statement_inner(c, r, g, tree, module_index, node_index, function)
    if statement_error != ok && !c.failure_has_token {
        record_failure(c, module_index, node, default_failure_kind(statement_error, node), "", "")
    }
    // The pointers this statement took (D351): kept by a binding whose type can hold
    // one, by a store of the pointer or a literal, or by a `ret`; dropped otherwise.
    if statement_error == ok && c.pin_count != 0usize {
        var kept = node.kind == .ReturnStmt
        if node.kind == .BindingStmt {
            var local_at = locals_before
            while local_at < c.local_count {
                if holds_pointer(c, c.locals[local_at].ty, 0usize) { kept = true }
                local_at += 1usize
            }
        }
        if node.kind == .AssignmentStmt {
            let (last_index, has_last) = last_node_child(tree, node)
            if has_last && (tree.nodes[last_index].kind == .UnaryExpr || tree.nodes[last_index].kind == .AggregateLiteral) { kept = true }
        }
        if kept { resource_commit_pins(c) }
    }
    c.pin_count = 0usize
    ret statement_error
}

fn contains_loop_break(tree: *parse.Tree, node: syntax.Node) -> bool {
    if node.kind == .BreakStmt { ret true }
    if node.kind == .WhileStmt || node.kind == .ForStmt || node.kind == .SwitchStmt { ret false }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) && contains_loop_break(tree, tree.nodes[parse.child_index_at(tree, at)]) { ret true }
        at += 1usize
    }
    ret false
}

fn statement_returns(c: *Checker, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> bool {
    if node.kind == .ReturnStmt { ret true }
    // `unreachable()` diverges: section 11 says the point after it is dead.
    if node.kind == .CallStmt {
        let (call_index, has_call) = first_node_child(tree, node)
        if !has_call { ret false }
        let (receiver_index, has_receiver) = first_node_child(tree, tree.nodes[call_index])
        if !has_receiver { ret false }
        let receiver = tree.nodes[receiver_index]
        ret receiver.kind == .NameExpr && c.tokens[usize(receiver.token_start)].kind == .KwUnreachable
    }
    if node.kind == .SwitchStmt { ret checked_switch_returns(c, module_index, usize(node.token_start)) }
    if node.kind == .Block {
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) && statement_returns(c, tree, module_index, tree.nodes[parse.child_index_at(tree, at)]) { ret true }
            at += 1usize
        }
        ret false
    }
    if node.kind == .WhileStmt {
        let (condition_index, has_condition) = first_node_child(tree, node)
        if !has_condition { ret false }
        let condition = tree.nodes[condition_index]
        if condition.kind != .LiteralExpr || c.tokens[usize(condition.token_start)].kind != .KwTrue { ret false }
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let child = tree.nodes[parse.child_index_at(tree, at)]
                if child.kind == .Block { ret !contains_loop_break(tree, child) }
            }
            at += 1usize
        }
        ret false
    }
    if node.kind == .IfStmt || node.kind == .WhenStmt {
        let end = usize(node.first_child) + usize(node.child_count)
        var branch_count = 0usize
        var returning_count = 0usize
        var first = true
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if first {
                    first = false
                } else {
                    branch_count += 1usize
                    if statement_returns(c, tree, module_index, tree.nodes[parse.child_index_at(tree, at)]) { returning_count += 1usize }
                }
            }
            at += 1usize
        }
        ret branch_count == 2usize && returning_count == 2usize
    }
    ret false
}

// Section 6's `when`: the condition is a question about the `target` namespace --
// `target.arch` or `target.os` compared with a member, under `!`, `&&`, `||` and
// parentheses -- settled here, and both blocks type check so a dead configuration
// cannot rot; lowering emits the taken one (D216).
//
// ponytail: `target` exists in a `when` condition alone. Section 2 makes it a namespace
// usable anywhere; that wants an enum value the checker can type, and every use so far
// is a `when`.
fn check_when_statement(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var first = true
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if first {
                let (taken, condition_error) = when_condition(c, g, tree, module_index, child_index)
                if condition_error != ok { ret condition_error }
                record_explain_fold(c, module_index, node, "when", taken)
                first = false
            } else {
                try check_block(c, r, g, tree, module_index, tree.nodes[child_index], function)
            }
        }
        at += 1usize
    }
    ret ok
}

fn target_member(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (str, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .FieldExpr { ret ("", false) }
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver || tree.nodes[receiver_index].kind != .NameExpr { ret ("", false) }
    let receiver = tree.nodes[receiver_index]
    let base = c.tokens[usize(receiver.token_start)]
    if base.kind != .Identifier || !same(g.modules[module_index].text[base.start..base.end], "target") { ret ("", false) }
    var at = usize(node.token_end)
    while at > usize(receiver.token_end) {
        at = at - 1usize
        if c.tokens[at].kind == .Identifier { ret (g.modules[module_index].text[c.tokens[at].start..c.tokens[at].end], true) }
    }
    ret ("", false)
}

fn member_spelling(c: *Checker, g: *graph.Graph, tree: *parse.Tree, node_index: usize, module_index: usize) -> (str, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .MemberExpr { ret ("", false) }
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        if c.tokens[at].kind == .Identifier { ret (g.modules[module_index].text[c.tokens[at].start..c.tokens[at].end], true) }
        at += 1usize
    }
    ret ("", false)
}

// The target's own spelling of a member: `x64` is `.X64`, `windows` is `.Windows`.
fn target_is(current: str, member: str) -> bool {
    if current.len != member.len { ret false }
    var at = 0usize
    while at < current.len {
        var byte = current[at]
        if at == 0usize && byte >= 97u8 && byte <= 122u8 { byte = byte - 32u8 }
        if byte != member[at] { ret false }
        at += 1usize
    }
    ret true
}

fn known_target_member(question: str, member: str) -> bool {
    if same(question, "arch") { ret same(member, "X64") || same(member, "Aarch64") || same(member, "X86") || same(member, "Spv") || same(member, "Ptx") }
    ret same(member, "Windows") || same(member, "Linux") || same(member, "Macos") || same(member, "None")
}

fn when_condition(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, err) {
    let node = tree.nodes[node_index]
    if node.kind == .GroupExpr {
        let (inner, found) = first_node_child(tree, node)
        if !found { ret (false, parse.InvalidSyntax) }
        let (grouped, grouped_error) = when_condition(c, g, tree, module_index, inner)
        ret (grouped, grouped_error)
    }
    if node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctBang {
        let (inner, found) = first_node_child(tree, node)
        if !found { ret (false, parse.InvalidSyntax) }
        let (value, inner_error) = when_condition(c, g, tree, module_index, inner)
        ret (!value, inner_error)
    }
    if node.kind == .BinaryExpr {
        let op = binary_operator(c, tree, node)
        var children: [2]usize = zero
        var count = 0usize
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                if count == children.len { ret (false, parse.InvalidSyntax) }
                children[count] = parse.child_index_at(tree, at)
                count += 1usize
            }
            at += 1usize
        }
        if count != 2usize { ret (false, parse.InvalidSyntax) }
        if op == .PunctAndAnd || op == .PunctOrOr {
            let (left, left_error) = when_condition(c, g, tree, module_index, children[0usize])
            if left_error != ok { ret (false, left_error) }
            let (right, right_error) = when_condition(c, g, tree, module_index, children[1usize])
            if right_error != ok { ret (false, right_error) }
            if op == .PunctAndAnd { ret (left && right, ok) }
            ret (left || right, ok)
        }
        if op == .PunctEqEq || op == .PunctBangEq {
            let (left_question, left_has_question) = target_member(c, g, tree, module_index, children[0usize])
            let (right_member, right_has_member) = member_spelling(c, g, tree, children[1usize], module_index)
            let (right_question, right_has_question) = target_member(c, g, tree, module_index, children[1usize])
            let (left_member, left_has_member) = member_spelling(c, g, tree, children[0usize], module_index)
            var question = left_question
            var has_question = left_has_question
            var member = right_member
            var has_member = right_has_member
            if !left_has_question {
                question = right_question
                has_question = right_has_question
                member = left_member
                has_member = left_has_member
            }
            if has_question && has_member && (same(question, "arch") || same(question, "os")) && known_target_member(question, member) {
                var current = g.os
                if same(question, "arch") { current = g.arch }
                let equal = target_is(current, member)
                if op == .PunctEqEq { ret (equal, ok) }
                ret (!equal, ok)
            }
        }
    }
    // Any other condition is section 9's comptime evaluation (D220): the interpreter
    // over this module's tree with no locals in scope, and the answer has to be a bool.
    if c.signatures_ready && c.has_graph {
        var frame: InterpFrame = zero
        frame.module_index = module_index
        let outer_constant = c.interp_constant
        c.interp_constant = ""
        c.interp_steps = 0usize
        c.interp_depth = 0usize
        let (value, value_type, value_error) = interp_expr(c, g, tree, &frame, node_index, interp_bool_type(module_index))
        c.interp_constant = outer_constant
        if value_error != ok { ret (false, value_error) }
        if value_type.kind != .Bool {
            record_failure(c, module_index, node, .WhenCondition, "", "")
            ret (false, InvalidCondition)
        }
        ret (value.magnitude != 0usize, ok)
    }
    record_failure(c, module_index, node, .WhenCondition, "", "")
    ret (false, InvalidCondition)
}

fn check_function_body(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, function: Function) -> err {
    var return_index = 0usize
    while return_index < function.return_count {
        if c.return_types[function.first_return + return_index].kind == .Other { ret Unsupported }
        return_index += 1usize
    }
    c.local_count = 0usize
    c.resource_alias_count = 0usize
    c.block_depth = 0usize
    c.pins_live = 0usize
    c.affine_answer_valid = false
    c.active_noescape = function.import_symbol
    c.body_returns_err = function.return_count == 1usize && c.return_types[function.first_return].kind == .Err
    var parameter_index = 0usize
    while parameter_index < function.parameter_count {
        let parameter = c.parameters[function.first_parameter + parameter_index]
        if parameter.ty.kind == .Other { ret Unsupported }
        try add_local(c, parameter.name, parameter.ty, false)
        var parameter_kind = affine_kind(c, parameter.ty, 0usize)
        if parameter.own && parameter_kind == 0u8 { parameter_kind = affine_slice_kind(c, parameter.ty) }
        if parameter.own && parameter_kind != 0u8 { c.resources[c.local_count - 1usize].state = resource_owned }
        // An `own` parameter carries its obligation into the body (D345), field by
        // field for a struct (D348); a borrowed one is owned by the caller and owes
        // nothing here, its fields views.
        if c.resources[c.local_count - 1usize].state != resource_plain {
            c.resources[c.local_count - 1usize].acquired = usize(node.token_start)
            try resource_init_fields(c, c.local_count - 1usize, resource_owned)
            if parameter.own {
                c.resources[c.local_count - 1usize].obligated = parameter_kind == 2u8
                // The type's own cleanup discharges what it is given by raw means.
                if resource_cleanup_of(c, parameter.ty, function) { c.resources[c.local_count - 1usize].obligated = false }
            } else {
                resource_disown_fields(c, c.local_count - 1usize)
                c.resources[c.local_count - 1usize].borrowed = true
            }
        }
        parameter_index += 1usize
    }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child = tree.nodes[parse.child_index_at(tree, at)]
            if child.kind == .Block {
                let body_error = check_block(c, r, g, tree, module_index, child, function)
                if body_error != ok { ret body_error }
                if function.return_count != 0usize && !statement_returns(c, tree, module_index, child) { ret MissingReturn }
                ret ok
            }
        }
        at += 1usize
    }
    ret ok
}

fn check_function(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, node_index: usize) -> err {
    let resources_before = c.resources_on
    // An `@unsafe` function (D345) is the audited wrapper: it touches a resource's
    // bits and discharges obligations by raw means the checker cannot see.
    c.resources_on = !declaration_has_attribute(c, g, tree, module_index, node_index, "unsafe")
    let checked = check_function_swept(c, r, g, tree, module_index, node)
    c.resources_on = resources_before
    ret checked
}

fn check_function_swept(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    begin_call_scope(c)
    let (name, name_error) = function_name(c, g.modules[module_index].text, node)
    if name_error != ok { ret name_error }
    let (function_index, found) = find_function(c, module_index, name)
    if !found { ret UnknownCallable }
    let function = c.functions[function_index]
    if function.generic {
        let generic = c.function_generics[function_index]
        c.active_first_comptime = generic.first_comptime
        c.active_comptime_count = generic.comptime_count
        c.active_first_argument = 0usize
        c.active_arguments = false
        c.generic_declaration = true
        let declaration_error = check_function_body(c, r, g, tree, module_index, node, function)
        c.active_first_comptime = 0usize
        c.active_comptime_count = 0usize
        c.active_first_argument = 0usize
        c.active_arguments = false
        c.generic_declaration = false
        if declaration_error != ok {
            c.failure_module = module_index
            c.failure_name = name
        }
        ret declaration_error
    }
    let body_error = check_function_body(c, r, g, tree, module_index, node, function)
    if body_error != ok {
        c.failure_module = module_index
        c.failure_name = name
    }
    ret body_error
}

fn check_instance(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, instance_index: usize) -> err {
    begin_call_scope(c)
    if instance_index >= c.function_count { ret UnknownCallable }
    let instance = c.functions[instance_index]
    let instance_generic = c.function_generics[instance_index]
    if !instance_generic.instance || instance_generic.template_index >= c.signature_function_count { ret InvalidType }
    let template = c.functions[instance_generic.template_index]
    let template_generic = c.function_generics[instance_generic.template_index]
    var tree: parse.Tree = zero
    try graph.parse_module(g, instance.module_index, &tree)
    try tokenize_module(c, g, instance.module_index)
    c.active_first_comptime = template_generic.first_comptime
    c.active_comptime_count = template_generic.comptime_count
    c.active_first_argument = instance_generic.first_argument
    c.active_arguments = true
    // A template body walked here belongs to the declaring module, but anything it
    // instantiates is code in the module that asked for this instance.
    c.active_owner_module = instance.owner_module_index
    c.active_owner_set = true
    c.active_instance = instance_index
    var result = UnknownCallable
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            let (name, name_error) = function_name(c, g.modules[instance.module_index].text, node)
            if name_error != ok { result = name_error }
            if name_error == ok && same(name, template.name) {
                // An instance is checked as any body is (D349): a template that
                // copies its `T` fails here when `T` is a resource.
                let resources_before = c.resources_on
                c.resources_on = !declaration_has_attribute(c, g, &tree, instance.module_index, node_index, "unsafe")
                result = check_function_body(c, r, g, &tree, instance.module_index, node, instance)
                c.resources_on = resources_before
                break
            }
        }
        node_index += 1usize
    }
    c.active_first_comptime = 0usize
    c.active_comptime_count = 0usize
    c.active_first_argument = 0usize
    c.active_arguments = false
    c.active_owner_set = false
    c.active_owner_module = 0usize
    if result != ok {
        c.failure_module = instance.module_index
        c.failure_name = template.name
    }
    ret result
}

// The bodies of the modules `skip` does not mark (D224): a module the edge rule keeps
// was checked when its artifact was written, and its instances used elsewhere are
// checked below as instances. An empty `skip` skips nothing.
fn check_bodies(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, skip: []const bool) -> err {
    var module_index = 0usize
    while module_index < g.count {
        if module_index < skip.len && skip[module_index] {
            module_index += 1usize
            continue
        }
        var tree: parse.Tree = zero
        try graph.parse_module(g, module_index, &tree)
        try tokenize_module(c, g, module_index)
        var node_index = 1usize
        while node_index < tree.count {
            let node = tree.nodes[node_index]
            if node.top_level && node.kind == .FnDecl { try check_function(c, r, g, &tree, module_index, node, node_index) }
            node_index += 1usize
        }
        module_index += 1usize
    }
    var instance_index = c.signature_function_count
    while instance_index < c.function_count {
        if c.function_generics[instance_index].instance && !c.function_generics[instance_index].checked && !c.functions[instance_index].generic {
            c.function_generics[instance_index].checked = true
            try check_instance(c, r, g, instance_index)
        }
        instance_index += 1usize
    }
    ret ok
}

// --- The per-module front end (D304) ------------------------------------------------
//
// `run_declarations` and `check_bodies` walk every module once per kind of declaration,
// parsing it each time, because the node pool holds one tree and each pass rebuilds it.
// In dependency order (`graph.order`) a module's imports are complete before it is
// looked at, so the same steps run on one module at a time and its tree is parsed once
// per sweep: declarations for every module, then bodies for every module. Two sweeps,
// not one, because every template must precede every instance in `functions` -- the
// `signature_function_count` boundary the generic paths test -- and bodies are what
// create instances. The global invariants are the same as `run`'s; only the parses go.

fn begin_declarations(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    if c.function_generics.len < c.functions.len || c.comptime_parameters.len == 0usize || c.generic_arguments.len == 0usize || c.aggregates.len == 0usize || c.aggregate_fields.len == 0usize { ret Capacity }
    c.resolver = r
    c.graph = g
    c.has_graph = true
    c.signatures_ready = false
    c.alias_count = 0usize
    c.type_count = 0usize
    c.expand_aliases = false
    c.constant_count = 0usize
    c.constant_expr_count = 0usize
    c.constants_ready = false
    c.aggregate_count = 0usize
    c.aggregate_field_count = 0usize
    c.comptime_parameter_count = 0usize
    c.generic_argument_count = 0usize
    try seed_intrinsic_aggregates(c, g)
    c.function_count = 0usize
    c.parameter_count = 0usize
    c.return_type_count = 0usize
    c.signature_function_count = 0usize
    ret seed_intrinsic_signatures(c, g)
}

// An alias whose right-hand side named an aggregate registered later in its module was
// collected with a placeholder; once the module's aggregates are in, its right-hand
// side is typed again in place. This is what the second `collect_aliases` pass did for
// every alias of every module.
fn retype_alias_declaration(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let end = usize(node.first_child) + usize(node.child_count)
    var rhs_index = 0usize
    var has_rhs = false
    var generic = false
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam { generic = true }
            if is_type_node(child.kind) {
                rhs_index = child_index
                has_rhs = true
            }
        }
        at += 1usize
    }
    if generic || !has_rhs { ret ok }
    let text = g.modules[module_index].text
    let (name, name_error) = declaration_name(c, text, node)
    if name_error != ok { ret name_error }
    let (alias_index, found) = find_alias(c, module_index, name)
    if !found { ret ok }
    let (rhs, rhs_error) = type_from_node(c, r, g, tree, module_index, tree.nodes[rhs_index])
    if rhs_error != ok { ret rhs_error }
    c.aliases[alias_index].rhs = rhs
    ret ok
}

fn declarations_module(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try graph.parse_module(g, module_index, &tree)
    try tokenize_module(c, g, module_index)
    let alias_from = c.alias_count
    let constant_from = c.constant_count
    let aggregate_from = c.aggregate_count
    let field_from = c.aggregate_field_count
    // Aliases, deferring a right-hand side that names something not yet registered.
    c.expand_aliases = false
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .TypeDecl { try collect_alias_declaration(c, r, g, &tree, module_index, node, true) }
        node_index += 1usize
    }
    c.expand_aliases = true
    // Constants and globals; the ones that reach no call are settled now.
    node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .ConstDecl { try collect_constant_declaration(c, r, g, &tree, module_index, node) }
        if node.top_level && node.kind == .VarDecl { try collect_global_declaration(c, r, g, &tree, module_index, node) }
        node_index += 1usize
    }
    var constant_index = constant_from
    while constant_index < c.constant_count {
        let early_error = evaluate_constant(c, constant_index)
        if early_error != ok && early_error != ComptimeDeferred { ret early_error }
        constant_index += 1usize
    }
    c.constants_ready = true
    // Aggregates: every one registered, then every one's fields collected.
    node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .TypeDecl { try register_aggregate_declaration(c, r, g, &tree, module_index, node) }
        node_index += 1usize
    }
    node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .TypeDecl { try collect_aggregate_declaration(c, r, g, &tree, module_index, node) }
        node_index += 1usize
    }
    try refill_aggregate_instances(c)
    if c.diagnostic_count != 0usize { ret InvalidType }
    // Aliases again, now that the aggregates they may name exist, then resolved.
    c.expand_aliases = false
    node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .TypeDecl { try retype_alias_declaration(c, r, g, &tree, module_index, node) }
        node_index += 1usize
    }
    c.expand_aliases = true
    var alias_index = alias_from
    while alias_index < c.alias_count {
        if !c.aliases[alias_index].generic {
            let (resolved, resolve_error) = canonical_type(c, c.aliases[alias_index].rhs)
            if resolve_error != ok { ret resolve_error }
            c.aliases[alias_index].resolved = resolved
            c.aliases[alias_index].state = 2u8
        }
        alias_index += 1usize
    }
    var field_at = field_from
    while field_at < c.aggregate_field_count {
        let (resolved, resolve_error) = canonical_type(c, c.aggregate_fields[field_at].ty)
        if resolve_error != ok { ret resolve_error }
        c.aggregate_fields[field_at].ty = resolved
        field_at += 1usize
    }
    try validate_aggregate_value_cycles_from(c, aggregate_from)
    // Signatures.
    node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && (node.kind == .FnDecl || node.kind == .ExternDecl) {
            try collect_function(c, r, g, &tree, module_index, node, node_index)
        }
        node_index += 1usize
    }
    ret ok
}

// After the last module: every template is in, so instances may follow, and the
// constants that reach a call are evaluated (D218).
fn finish_declarations(c: *Checker) -> err {
    c.signature_function_count = c.function_count
    c.signatures_ready = true
    var constant_index = 0usize
    while constant_index < c.constant_count {
        if c.constants[constant_index].state != 2u8 { try evaluate_constant(c, constant_index) }
        constant_index += 1usize
    }
    ret ok
}

// Whether the build's deadline has passed (D441): the clock read once per function.
fn past_deadline(c: *Checker) -> bool {
    if c.fault_cancel_ticks != 0usize && c.statement_ticks >= c.fault_cancel_ticks { ret true }
    if c.deadline_ns == 0usize { ret false }
    let (ticks, clock_error) = os.clock(.Monotonic)
    if clock_error != ok || ticks < 0i64 { ret false }
    ret usize(ticks) - c.started_ns >= c.deadline_ns
}

// A module's bodies one function at a time (D553, H09): `begin_module_bodies` parses
// and tokenizes the module into the caller's tree, the caller checks each top-level
// function with `check_function` and goes on past a failure once it has read it
// and called `clear_failure`; `bodies_module` below stops at the first.
fn begin_module_bodies(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, module_index: usize, tree: *parse.Tree) -> err {
    try graph.parse_module(g, module_index, tree)
    try tokenize_module(c, g, module_index)
    ret memo_module(c, module_index, tree.count)
}

// The failure read and put down (D553): the next function's is recorded afresh.
fn clear_failure(c: *Checker) {
    c.failure_has_token = false
    c.failure_kind = .None
    c.failure_name = ""
    c.failure_detail = ""
    c.failure_detail2 = ""
    c.failure_expected = invalid_type()
    c.failure_mismatch_end = 0usize
    c.failure_has_related = false
    c.failure_fix_text = ""
    c.failure_fix_kind = 0u8
    c.diagnostic_count = 0usize
}

fn bodies_module(c: *Checker, r: *resolve.Resolver, g: *graph.Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try graph.parse_module(g, module_index, &tree)
    try tokenize_module(c, g, module_index)
    try memo_module(c, module_index, tree.count)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .FnDecl {
            if past_deadline(c) { ret Cancelled }
            try check_function(c, r, g, &tree, module_index, node, node_index)
        }
        node_index += 1usize
    }
    ret ok
}

// After the last module's bodies: the instances they created, checked against their
// templates' modules, exactly as `check_bodies` ends.
fn finish_bodies(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    var instance_index = c.signature_function_count
    while instance_index < c.function_count {
        if c.function_generics[instance_index].instance && !c.function_generics[instance_index].checked && !c.functions[instance_index].generic {
            c.function_generics[instance_index].checked = true
            try check_instance(c, r, g, instance_index)
        }
        instance_index += 1usize
    }
    ret ok
}

fn run(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    try run_declarations(c, r, g)
    var no_skip: [1]bool = zero
    ret check_bodies(c, r, g, no_skip[0usize..0usize])
}

// Everything but the bodies (D224): what the edge rule needs to decide which
// modules are kept, so their bodies need not be checked at all.
fn run_declarations(c: *Checker, r: *resolve.Resolver, g: *graph.Graph) -> err {
    if c.function_generics.len < c.functions.len || c.comptime_parameters.len == 0usize || c.generic_arguments.len == 0usize || c.aggregates.len == 0usize || c.aggregate_fields.len == 0usize { ret Capacity }
    c.resolver = r
    c.graph = g
    c.has_graph = true
    c.signatures_ready = false
    try collect_aliases(c, r, g, true)
    try collect_constants(c, r, g)
    try collect_aggregates(c, r, g)
    if c.diagnostic_count != 0usize { ret InvalidType }
    try collect_aliases(c, r, g, false)
    try expand_aggregate_field_types(c)
    try validate_aggregate_value_cycles(c)
    try collect_signatures(c, r, g)
    c.signatures_ready = true
    try validate_resource_cleanups(c, g)
    // The constants that call are evaluated now (D218), so a failure is reported at
    // the declaration whether or not anything uses it.
    var constant_index = 0usize
    while constant_index < c.constant_count {
        if c.constants[constant_index].state != 2u8 { try evaluate_constant(c, constant_index) }
        constant_index += 1usize
    }
    ret ok
}

fn diagnostic_code(kind: DiagnosticKind) -> str {
    if kind == .ResourceUseAfterMove { ret "E-SAFETY-0001" }
    if kind == .ResourceCleanupForgotten { ret "E-SAFETY-0002" }
    if kind == .ResourcePartialMove { ret "E-SAFETY-0003" }
    if kind == .ResourceOverwrite { ret "E-SAFETY-0006" }
    if kind == .ResourceUndef { ret "E-SAFETY-0007" }
    if kind == .MissingUndefValue { ret "E-SAFETY-0017" }
    if kind == .ResourceUnchecked { ret "E-SAFETY-0008" }
    if kind == .ResourceDeferredConsumed { ret "E-SAFETY-0009" }
    if kind == .ResourceMovedInLoop { ret "E-SAFETY-0011" }
    if kind == .ResourceOpaque { ret "E-SAFETY-0010" }
    if kind == .ResourceCleanupSignature { ret "E-SAFETY-9999" }
    if kind == .ResourceBorrowConsumed { ret "E-SAFETY-0012" }
    if kind == .ResourceCopy { ret "E-SAFETY-0005" }
    if kind == .ResourceMovedWhileBorrowed { ret "E-SAFETY-0004" }
    if kind == .RegionReset { ret "E-SAFETY-0013" }
    if kind == .RegionEscape { ret "E-SAFETY-0018" }
    if kind == .BorrowContract { ret "E-SAFETY-0019" }
    if kind == .NoEscapeContract { ret "E-SAFETY-0020" }
    if kind == .ViewMutated { ret "E-SAFETY-0014" }
    if kind == .ThreadFrameEscape { ret "E-SAFETY-0015" }
    if kind == .ThreadShared { ret "E-SAFETY-0016" }
    if kind == .TryInsideDefer || kind == .TryCast || kind == .TryNotFallible || kind == .TryNoPropagate { ret "E-ERROR-9999" }
    // docs/diagnostics.md: section 9's reflection and section 8's atomics under their
    // own categories (D215). A constant cycle stays E-TYPE-9999: the bootstrap says so
    // and tests/neper0 holds the two to the same words.
    if kind == .MetaShape || kind == .MetaFieldOwner { ret "E-COMPTIME-9999" }
    if kind == .AtomicElement || kind == .AtomicOrdering { ret "E-MEM-9999" }
    if kind == .ReturnCount || kind == .ReturnValuesUnexpected { ret "E-TYPE-0003" }
    if kind == .ReturnType { ret "E-TYPE-0002" }
    if kind == .ArrayLengthType || kind == .InitializerType { ret "E-TYPE-0002" }
    if kind == .GenericTypeArity || kind == .IteratorSignature || kind == .ProtocolSignature { ret "E-TYPE-0003" }
    if kind == .EnumValueRange { ret "E-TYPE-0004" }
    if kind == .DuplicateEnumValue { ret "E-NAME-0001" }
    if kind == .IteratorMissing || kind == .ProtocolMissing { ret "E-NAME-9999" }
    if kind == .GenericInference { ret "E-TYPE-0001" }
    if kind == .WhenCondition || kind == .ComptimeEvaluation || kind == .ComptimeDeferredUse { ret "E-COMPTIME-9999" }
    ret "E-TYPE-9999"
}

// The name of one of this module's own errors, for the report when nothing recorded
// a reason. The merged error table (src/error_table.e) cannot answer this: it holds
// the errors of the program being compiled, and these are the compiler's own.
//
// Keep this beside the declarations above. An error missing from it degrades the
// report to "type checking failed" and nothing worse, which is what the report said
// for every one of them before.
fn error_name(value: err) -> str {
    if value == Capacity { ret "check.Capacity" }
    if value == ResourceViolation { ret "check.ResourceViolation" }
    if value == Unsupported { ret "check.Unsupported" }
    if value == MissingContext { ret "check.MissingContext" }
    if value == TypeMismatch { ret "check.TypeMismatch" }
    if value == InvalidCondition { ret "check.InvalidCondition" }
    if value == InvalidOperator { ret "check.InvalidOperator" }
    if value == InvalidReturn { ret "check.InvalidReturn" }
    if value == ReturnValuesUnexpected { ret "check.ReturnValuesUnexpected" }
    if value == ReturnCount { ret "check.ReturnCount" }
    if value == ReturnType { ret "check.ReturnType" }
    if value == MissingReturn { ret "check.MissingReturn" }
    if value == UnknownCallable { ret "check.UnknownCallable" }
    if value == ArgumentCount { ret "check.ArgumentCount" }
    if value == InvalidType { ret "check.InvalidType" }
    if value == ImmutableAssignment { ret "check.ImmutableAssignment" }
    if value == AliasCycle { ret "check.AliasCycle" }
    if value == ConstantCycle { ret "check.ConstantCycle" }
    if value == ConstantOverflow { ret "check.ConstantOverflow" }
    if value == InvalidConstant { ret "check.InvalidConstant" }
    if value == InvalidFormat { ret "check.InvalidFormat" }
    if value == InvalidTry { ret "check.InvalidTry" }
    if value == TryCast { ret "check.TryCast" }
    if value == TryNotFallible { ret "check.TryNotFallible" }
    if value == TryNoPropagate { ret "check.TryNoPropagate" }
    if value == InvalidSwitch { ret "check.InvalidSwitch" }
    if value == DuplicateCase { ret "check.DuplicateCase" }
    if value == NonExhaustiveSwitch { ret "check.NonExhaustiveSwitch" }
    ret ""
}

fn diagnostic_message(kind: DiagnosticKind) -> str {
    if kind == .AssignmentImmutable { ret "assignment target is immutable" }
    if kind == .IndexedArrayImmutable { ret "indexed assignment requires a mutable array binding" }
    if kind == .IndexedElementsImmutable { ret "indexed assignment requires mutable elements" }
    if kind == .BreakOutsideControl { ret "break requires an enclosing loop or switch" }
    if kind == .ReturnInsideDefer { ret "ret is not legal inside defer" }
    if kind == .ReturnValuesUnexpected { ret "this function returns nothing, so ret takes no value" }
    if kind == .ReturnCount { ret "ret gives a different number of values than this function returns" }
    if kind == .ReturnType { ret "the returned value does not have the declared return type" }
    if kind == .TryInsideDefer { ret "try is not legal inside defer" }
    if kind == .TryCast { ret "try needs a call that can fail; a conversion cannot" }
    if kind == .TryNotFallible { ret "try needs a call whose last result is an err" }
    if kind == .TryNoPropagate { ret "try propagates an err, so the enclosing function must return one" }
    if kind == .DeferValue { ret "a deferred call returning a value must use `defer let _ = call()`" }
    if kind == .ArrayElementCount { ret "array literal element count does not match its length" }
    if kind == .ArrayLengthType { ret "array length must have type usize" }
    if kind == .ConstantDependencyCycle { ret "constant dependency cycle" }
    if kind == .EnumValueRange { ret "enum member value is outside its backing type" }
    if kind == .DuplicateEnumValue { ret "duplicate enum backing value" }
    if kind == .IteratorImmutable { ret "iterator subject must be a mutable variable or a mutable pointer" }
    if kind == .IteratorSignature { ret "iterator next function must have signature `fn <type>_next(it: *I) -> (T, bool)`" }
    if kind == .RecursiveAggregate { ret "recursive aggregate value layout" }
    if kind == .InitializerType { ret "initializer type does not match binding" }
    if kind == .GenericTypeArity { ret "compile-time argument count does not match generic type" }
    if kind == .MultipleBindingCount { ret "multiple binding count does not match function results" }
    if kind == .MultipleAssignmentImmutable { ret "multiple assignment target is immutable" }
    if kind == .AggregateMemberUnknown { ret "aggregate member has an unknown or unsized type" }
    if kind == .BindingUnknownNamed { ret "binding has an unknown named type" }
    if kind == .BorrowContract { ret "@borrows must name one borrowed pointer-bearing parameter of a function with a pointer-bearing result" }
    if kind == .NoEscapeContract { ret "@noescape must name borrowed pointer-bearing parameters and the body must not let them escape" }
    ret "type checking failed"
}

// ---- Resources (D345, M2.5 H01) ------------------------------------------------------
//
// A resource type is affine: a value of it is moved at most once, and one with a
// cleanup is obligated: consumed on every exit of the block that owns it. This pass
// rides the body check: every local of an affine type carries a state, the statement
// checks move it, the arms of an `if` or `switch` join it, a loop's body must leave
// it as it found it, and every exit audits the obligations still live. The seeded
// handles of `e.os` are the resource types for now -- `File`, `Proc` and `Thread` --
// with `close`, `wait`, `wait_usage`, `thread_join` and `thread_detach` consuming
// their first argument and the three standard streams borrowed; a user-declared
// resource and an `own` parameter are the syntax of the next step.
//
// States: Plain (the local is not affine), Owned, Moved, Null (`zero`), Reserved (a
// `defer` consumes it at the block's exit), Maybe (moved on one path and not another),
// Unchecked (returned beside an `err` that has not been tested yet).

fn module_is_os(c: *Checker, module_index: usize) -> bool {
    if !c.has_graph || module_index >= c.graph.count { ret false }
    ret same(c.graph.modules[module_index].name, "e.os")
}

fn module_is_mem(c: *Checker, module_index: usize) -> bool {
    if !c.has_graph || module_index >= c.graph.count { ret false }
    ret same(c.graph.modules[module_index].name, "e.mem")
}

fn module_is_thread(c: *Checker, module_index: usize) -> bool {
    if !c.has_graph || module_index >= c.graph.count { ret false }
    ret same(c.graph.modules[module_index].name, "e.thread")
}

fn module_is_format_codec(c: *Checker, module_index: usize) -> bool {
    if !c.has_graph || module_index >= c.graph.count { ret false }
    let name = c.graph.modules[module_index].name
    ret name.len > 6usize && same(name[0usize..6usize], "e.fmt.")
}

// Why a moved value cannot be used: it was moved, its region was reset, or the
// container it viewed was mutated (D354).
fn dangling_kind(c: *Checker, local_index: usize) -> DiagnosticKind {
    if c.resources[local_index].dangling == 1u8 { ret .RegionReset }
    if c.resources[local_index].dangling == 2u8 { ret .ViewMutated }
    ret .ResourceUseAfterMove
}

// The text of a call's `position`th argument, as written; empty when there is none.
fn call_argument_text(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, call: syntax.Node, position: usize) -> str {
    let (argument_index, found) = call_argument_node(tree, call, position)
    if !found { ret "" }
    let argument = tree.nodes[argument_index]
    if usize(argument.token_end) > c.token_count || argument.token_end <= argument.token_start { ret "" }
    let first = c.tokens[usize(argument.token_start)]
    let last = c.tokens[usize(argument.token_end) - 1usize]
    ret g.modules[module_index].text[first.start..last.end]
}

// The node of a call's `position`th argument: the node children after the callee.
fn call_argument_node(tree: *parse.Tree, call: syntax.Node, position: usize) -> (usize, bool) {
    let end = usize(call.first_child) + usize(call.child_count)
    var at = usize(call.first_child)
    var seen = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if seen == position + 1usize { ret (parse.child_index_at(tree, at), true) }
            seen += 1usize
        }
        at += 1usize
    }
    ret (0usize, false)
}

// The local whose address an argument takes: `&x`, or `&x.f`/`&x[i]` down to `x`.
fn address_argument_local(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, argument_index: usize) -> (usize, bool) {
    let argument = tree.nodes[argument_index]
    if argument.kind != .UnaryExpr || c.tokens[usize(argument.token_start)].kind != .PunctAmp { ret (0usize, false) }
    let (inner_index, has_inner) = first_node_child(tree, argument)
    if !has_inner { ret (0usize, false) }
    let (base_local, is_place) = place_base_local(c, g, tree, module_index, inner_index)
    ret (base_local, is_place)
}

// The storage identity named by a call argument (D673): `x`, `&x`, and a local
// pointer alias of `&x` all spell the same local for region matching.
fn call_argument_storage_text(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, call: syntax.Node, position: usize) -> str {
    let (argument_index, has_argument) = call_argument_node(tree, call, position)
    if !has_argument { ret "" }
    var (storage, found) = address_argument_local(c, g, tree, module_index, argument_index)
    if !found { (storage, found) = alias_target(c, g, tree, module_index, argument_index) }
    if !found { (storage, found) = place_base_local(c, g, tree, module_index, argument_index) }
    if found && storage < c.local_count { ret c.locals[storage].name }
    ret call_argument_text(c, g, tree, module_index, call, position)
}

// The local at the base of a place -- `x`, `x.f`, `x[i]`, `x[a..b]` and their
// nestings -- when there is one (D395).
fn place_base_local(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, inner_index: usize) -> (usize, bool) {
    var base_index = inner_index
    while tree.nodes[base_index].kind == .FieldExpr || tree.nodes[base_index].kind == .BracketPostfix {
        let (deeper_index, has_deeper) = first_node_child(tree, tree.nodes[base_index])
        if !has_deeper { break }
        base_index = deeper_index
    }
    let base = tree.nodes[base_index]
    if base.kind != .NameExpr { ret (0usize, false) }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret (0usize, false) }
    let (local_index, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
    ret (local_index, found)
}

// Whether any of the call's results can hold a pointer: what makes a call an
// accessor (a view comes back) rather than a mutation.
fn call_returns_pointer(c: *Checker, info: CallInfo) -> bool {
    if info.mem_alloc { ret true }
    var at = 0usize
    while at < info.function.return_count {
        let return_index = info.function.first_return + at
        if return_index < c.return_type_count && holds_pointer(c, c.return_types[return_index], 0usize) { ret true }
        at += 1usize
    }
    ret false
}

// The one-based position retained by an `@borrows` result. The attribute name rides
// in an import-library slot that is otherwise empty on every non-extern function;
// this keeps the hot Function record unchanged while its public identity stays the
// positional value serialized by artifacts.
fn function_borrow_from(c: *Checker, function: Function) -> usize {
    if function.external || function.import_library.len == 0usize { ret 0usize }
    var at = 0usize
    while at < function.parameter_count {
        let parameter_index = function.first_parameter + at
        if parameter_index < c.parameter_count && same(c.parameters[parameter_index].name, function.import_library) { ret at + 1usize }
        at += 1usize
    }
    ret 0usize
}

fn function_noescape_at(c: *Checker, function: Function, position: usize) -> bool {
    if function.external || position == 0usize || position > function.parameter_count || function.import_symbol.len == 0usize { ret false }
    let parameter_index = function.first_parameter + position - 1usize
    if parameter_index >= c.parameter_count { ret false }
    ret contract_name_count(function.import_symbol, c.parameters[parameter_index].name) != 0usize
}

// The first one-based parameter promised not to outlive an `@noescape` call. The
// complete quoted name list uses the second import string slot, otherwise empty on
// every non-extern function.
fn function_noescape_from(c: *Checker, function: Function) -> usize {
    ret function_noescape_position_at(c, function, 0usize)
}

fn function_noescape_count(c: *Checker, function: Function) -> usize {
    var count = 0usize
    var at = 0usize
    while at < function.parameter_count {
        if function_noescape_at(c, function, at + 1usize) { count += 1usize }
        at += 1usize
    }
    ret count
}

fn function_noescape_position_at(c: *Checker, function: Function, wanted: usize) -> usize {
    var found = 0usize
    var at = 0usize
    while at < function.parameter_count {
        if function_noescape_at(c, function, at + 1usize) {
            if found == wanted { ret at + 1usize }
            found += 1usize
        }
        at += 1usize
    }
    ret 0usize
}

fn expression_noescape_from(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, function: Function, expression_index: usize) -> usize {
    var position = 1usize
    while position <= function.parameter_count {
        if function_noescape_at(c, function, position) && expression_borrows_from(c, g, tree, module_index, expression_index, position - 1usize) { ret position }
        position += 1usize
    }
    ret 0usize
}

// A plain local bound from a call (D354): a region value when the call took a
// live mark's arena and gives back something that can hold a pointer; a view when
// it took `&c` of a local; from another local, the same as that local.
fn region_bind(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, local_index: usize, statement: syntax.Node, initializer_index: usize, has_initializer: bool, from_call: bool, call: CallInfo) -> err {
    c.resources[local_index].region = 0usize
    c.resources[local_index].view_of = 0usize
    c.resources[local_index].dangling = 0u8
    c.resources[local_index].state = resource_plain
    if !has_initializer || !holds_pointer(c, c.locals[local_index].ty, 0usize) { ret ok }
    var source_index = initializer_index
    var source = tree.nodes[source_index]
    // `s[1..]`, `&s[0]`, `s.items`: what it came from.
    while source.kind == .BracketPostfix || source.kind == .FieldExpr || (source.kind == .UnaryExpr && c.tokens[usize(source.token_start)].kind == .PunctAmp) {
        let (inner_index, has_inner) = first_node_child(tree, source)
        if !has_inner { break }
        source_index = inner_index
        source = tree.nodes[source_index]
    }
    if source.kind == .NameExpr {
        // Only a tagged local -- an owned one -- has anything to hand on.
        if !any_affine_local(c) { ret ok }
        let token = c.tokens[usize(source.token_start)]
        if token.kind != .Identifier { ret ok }
        let (other, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
        if !found || other == local_index { ret ok }
        c.resources[local_index].region = c.resources[other].region
        c.resources[local_index].view_of = c.resources[other].view_of
        if c.resources[local_index].region != 0usize || c.resources[local_index].view_of != 0usize { region_tag(c, local_index, usize(statement.token_start)) }
        ret ok
    }
    if !from_call || source.kind != .CallExpr || !call_returns_pointer(c, call) { ret ok }
    // A checked result-borrow summary is exact: retain the named argument's region
    // or container identity rather than guessing from the first address-like input.
    let declared_borrow = function_borrow_from(c, call.function)
    if declared_borrow != 0usize && declared_borrow <= call.function.parameter_count {
        let parameter_at = declared_borrow - 1usize
        let parameter_index = call.function.first_parameter + parameter_at
        var arena_parameter = false
        if parameter_index < c.parameter_count {
            let parameter_type = c.parameters[parameter_index].ty
            arena_parameter = parameter_type.kind == .Pointer && parameter_type.has_element && parameter_type.element < c.type_count && seeded_arena(c, c.types[parameter_type.element])
        }
        if !arena_parameter {
            let (argument_index, has_argument) = call_argument_node(tree, source, parameter_at)
            if has_argument {
                var (origin, found_origin) = alias_target(c, g, tree, module_index, argument_index)
                if !found_origin { (origin, found_origin) = address_argument_local(c, g, tree, module_index, argument_index) }
                if !found_origin { (origin, found_origin) = place_base_local(c, g, tree, module_index, argument_index) }
                if found_origin && origin < c.local_count && origin != local_index {
                    c.resources[local_index].region = c.resources[origin].region
                    c.resources[local_index].view_of = c.resources[origin].view_of
                    if c.resources[local_index].region == 0usize && c.resources[local_index].view_of == 0usize { c.resources[local_index].view_of = origin + 1usize }
                    region_tag(c, local_index, usize(statement.token_start))
                }
            }
            ret ok
        }
    }
    // A view is a slice, a pointer or a string that came back from a call given
    // `&c`; a call that takes an arena hands back an allocation instead.
    let bound_kind = c.locals[local_index].ty.kind
    let viewable = bound_kind == .Slice || bound_kind == .Pointer || bound_kind == .String
    var address_at = 0usize
    var has_address = false
    while viewable && !has_address {
        let (argument_index, has_argument) = call_argument_node(tree, source, address_at)
        if !has_argument { break }
        var (storage, names_storage) = alias_target(c, g, tree, module_index, argument_index)
        if !names_storage { (storage, names_storage) = address_argument_local(c, g, tree, module_index, argument_index) }
        if names_storage { has_address = true }
        address_at += 1usize
    }
    if !has_address && !any_affine_local(c) { ret ok }
    // The arena argument, if the callee takes one: `mem.alloc[T](a, n)` first, a
    // declared function wherever its `*mem.Arena` parameter is.
    var arena_text = ""
    var allocates = call.mem_alloc
    if call.mem_alloc {
        arena_text = call_argument_storage_text(c, g, tree, module_index, source, 0usize)
    } else {
        var parameter_at = 0usize
        while parameter_at < call.function.parameter_count {
            let parameter_index = call.function.first_parameter + parameter_at
            if parameter_index < c.parameter_count {
                let parameter_type = c.parameters[parameter_index].ty
                if parameter_type.kind == .Pointer && parameter_type.has_element && parameter_type.element < c.type_count && seeded_arena(c, c.types[parameter_type.element]) {
                    arena_text = call_argument_storage_text(c, g, tree, module_index, source, parameter_at)
                    allocates = true
                    break
                }
            }
            parameter_at += 1usize
        }
    }
    if arena_text.len != 0usize && any_affine_local(c) {
        // The innermost live mark of that arena.
        var mark_at = c.local_count
        while mark_at > 0usize {
            mark_at = mark_at - 1usize
            if mark_at != local_index && c.resources[mark_at].mark_arena.len != 0usize && c.resources[mark_at].points_to == 0usize && c.resources[mark_at].state == resource_owned && same(c.resources[mark_at].mark_arena, arena_text) {
                c.resources[local_index].region = mark_at + 1usize
                break
            }
        }
    }
    var argument_at = 0usize
    while !allocates && has_address && c.resources[local_index].view_of == 0usize {
        let (argument_index, has_argument) = call_argument_node(tree, source, argument_at)
        if !has_argument { break }
        // `view(&ctx.target.field)` borrows the local behind `target`, not `ctx`.
        var (container, is_address) = alias_target(c, g, tree, module_index, argument_index)
        if !is_address { (container, is_address) = address_argument_local(c, g, tree, module_index, argument_index) }
        if is_address && container != local_index { c.resources[local_index].view_of = container + 1usize }
        argument_at += 1usize
    }
    if c.resources[local_index].region != 0usize || c.resources[local_index].view_of != 0usize { region_tag(c, local_index, usize(statement.token_start)) }
    ret ok
}

// A region value or a view is followed as an owned view: read as wanted, moved by
// nobody, owed nothing -- and dangling once its region or container goes.
fn region_tag(c: *Checker, local_index: usize, token: usize) {
    c.resources[local_index].state = resource_owned
    c.resources[local_index].view = true
    c.resources[local_index].obligated = false
    c.resources[local_index].acquired = token
    c.affine_answer_valid = false
}

fn invalidate_views_of(c: *Checker, module_index: usize, node: syntax.Node, container: usize) {
    var at = 0usize
    while at < c.local_count {
        if c.resources[at].view_of == container + 1usize && c.resources[at].state == resource_owned {
            c.resources[at].state = resource_moved
            c.resources[at].dangling = 2u8
            c.resources[at].acquired = usize(node.token_start)
            record_explain_view_end(c, module_index, node, c.locals[at].name, 2u8)
        }
        at += 1usize
    }
}

// A call that ends a region or mutates a container (D354): `mem.reset(a, m)` makes
// every region value of `m`, and of any later mark on the same arena, dangling; a
// call given `&c` through a `*T` parameter that gives back nothing holding a
// pointer makes every view of `c` dangling.
fn region_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, info: CallInfo) {
    if module_is_mem(c, info.function.module_index) && same(info.function.name, "reset") {
        let (mark_argument, has_mark) = call_argument_node(tree, node, 1usize)
        if !has_mark || tree.nodes[mark_argument].kind != .NameExpr { ret }
        let mark_token = c.tokens[usize(tree.nodes[mark_argument].token_start)]
        var (mark_index, mark_found) = find_local(c, g.modules[module_index].text[mark_token.start..mark_token.end])
        if !mark_found || c.resources[mark_index].mark_arena.len == 0usize { ret }
        if c.resources[mark_index].points_to != 0usize { mark_index = c.resources[mark_index].points_to - 1usize }
        // A deferred call runs at scope exit, not where it is registered (D675).
        // Reuse otherwise-unused mark fields to remember that boundary without
        // growing every Resource record.
        if c.defer_depth != 0usize {
            c.resources[mark_index].dangling = 3u8
            c.resources[mark_index].lent_at = usize(node.token_start)
            ret
        }
        var at = 0usize
        while at < c.local_count {
            let region = c.resources[at].region
            if region != 0usize && region - 1usize >= mark_index && same(c.resources[region - 1usize].mark_arena, c.resources[mark_index].mark_arena) {
                c.resources[at].state = resource_moved
                c.resources[at].dangling = 1u8
                c.resources[at].acquired = usize(node.token_start)
                record_explain_view_end(c, module_index, node, c.locals[at].name, 1u8)
            }
            at += 1usize
        }
        ret
    }
    if call_returns_pointer(c, info) { ret }
    var argument_at = 0usize
    while argument_at < info.function.parameter_count {
        let (argument_index, has_argument) = call_argument_node(tree, node, argument_at)
        if !has_argument { break }
        let parameter_index = info.function.first_parameter + argument_at
        if parameter_index < c.parameter_count && c.parameters[parameter_index].ty.kind == .Pointer && !c.parameters[parameter_index].ty.is_const {
            if has_dynamic_alias_path(c, g, tree, module_index, argument_index) {
                var wanted = 0usize
                while true {
                    let (container, found) = dynamic_alias_candidate(c, g, tree, module_index, argument_index, wanted)
                    if !found { break }
                    invalidate_views_of(c, module_index, node, container)
                    wanted += 1usize
                }
            } else {
                // Prefer the lexical alias: `&ctx.target.field` mutates the storage
                // behind `target`, not the aggregate carrying that pointer (D687).
                var (container, is_address) = alias_target(c, g, tree, module_index, argument_index)
                // A pointer local bound from `&c` is the same mutable access to `c`.
                // Following it here closes the direct-alias hole in H02's view rule.
                if !is_address { (container, is_address) = address_argument_local(c, g, tree, module_index, argument_index) }
                if is_address { invalidate_views_of(c, module_index, node, container) }
            }
        }
        argument_at += 1usize
    }
}


// `mem.Arena` is affine and owed nothing (D351): an arena lives in one place, and
// what it holds is reclaimed by the process, not a closer.
fn seeded_arena(c: *Checker, ty: Type) -> bool {
    if ty.kind != .Named || !same(ty.name, "Arena") || !c.has_graph || ty.module_index >= c.graph.count { ret false }
    ret same(c.graph.modules[ty.module_index].name, "e.mem")
}

// A pointer taken to a resource local (D351): a candidate until the statement ends,
// pinned then if the statement bound, stored or returned something that can hold
// it; a pointer that is an argument alone is the call's, gone when it returns.
fn resource_pin(c: *Checker, local_index: usize, token: usize) {
    if !c.resources_on || c.resources[local_index].state == resource_plain || c.resources[local_index].pinned != 0usize { ret }
    if c.pin_count >= c.pin_locals.len { ret }
    c.pin_locals[c.pin_count] = local_index
    c.pin_tokens[c.pin_count] = token
    c.pin_count += 1usize
}

// The statement's candidates pinned to the open block, until it ends.
fn resource_commit_pins(c: *Checker) {
    var at = 0usize
    while at < c.pin_count {
        let local_index = c.pin_locals[at]
        if local_index < c.local_count && c.resources[local_index].pinned == 0usize {
            c.resources[local_index].pinned = c.block_depth
            c.resources[local_index].pin_at = c.pin_tokens[at]
            c.pins_live += 1usize
        }
        at += 1usize
    }
    c.pin_count = 0usize
}

// Whether a value of the type can carry a pointer: one, a slice, a function, an
// aggregate or array holding any of them; a type parameter can be anything.
fn holds_pointer(c: *Checker, ty: Type, depth: usize) -> bool {
    if depth > 6usize { ret true }
    if ty.kind == .Pointer || ty.kind == .Slice || ty.kind == .String || ty.kind == .Function || ty.kind == .TypeParameter { ret true }
    if ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret true }
        ret holds_pointer(c, c.types[ty.element], depth + 1usize)
    }
    if ty.kind != .Named { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret true }
    let aggregate = c.aggregates[aggregate_index]
    if aggregate.pointer_memo != 0u8 { ret aggregate.pointer_memo == 2u8 }
    var holds = false
    var field_at = 0usize
    while !holds && field_at < aggregate.field_count {
        let field_index = aggregate.first_field + field_at
        if field_index < c.aggregate_field_count && holds_pointer(c, c.aggregate_fields[field_index].ty, depth + 1usize) { holds = true }
        field_at += 1usize
    }
    if c.signatures_ready {
        c.aggregates[aggregate_index].pointer_memo = 1u8
        if holds { c.aggregates[aggregate_index].pointer_memo = 2u8 }
    }
    ret holds
}

// 0: not affine; 1: affine; 2: affine and obligated. Fixed arrays inherit the
// element's answer and track their slots below; slices remain borrowed views.
fn affine_kind(c: *Checker, ty: Type, depth: usize) -> u8 {
    if depth > 6usize { ret 0u8 }
    if ty.kind == .Array {
        if !ty.has_element || ty.element >= c.type_count { ret 0u8 }
        ret affine_kind(c, c.types[ty.element], depth + 1usize)
    }
    if ty.kind != .Named { ret 0u8 }
    if seeded_arena(c, ty) { ret 1u8 }
    if seeded_handle(c, ty) { ret 2u8 }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret 0u8 }
    var memo_index = aggregate_index
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count {
        memo_index = aggregate.template_index
        aggregate = c.aggregates[aggregate.template_index]
    }
    if aggregate.affine_memo != 0u8 { ret aggregate.affine_memo - 1u8 }
    var worst = 0u8
    var fields = aggregate.field_count
    // Struct fields are tracked separately; a tagged union is affine as a whole
    // when any possible payload is affine (D612). The live arm is runtime state,
    // so the checker deliberately does not invent partial-variant moves.
    if aggregate.kind != .Struct && aggregate.kind != .TaggedUnion { fields = 0usize }
    if aggregate.resource {
        worst = 1u8
        fields = 0usize
        if aggregate.cleanup.len != 0usize { worst = 2u8 }
    }
    // Containment: a struct holding a resource is affine, and owed if it is.
    var at = 0usize
    while at < fields {
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count {
            let field_kind = affine_kind(c, c.aggregate_fields[field_index].ty, depth + 1usize)
            if field_kind > worst { worst = field_kind }
        }
        at += 1usize
    }
    // Remembered once the signatures are collected, when every field's type is known.
    if c.signatures_ready { c.aggregates[memo_index].affine_memo = worst + 1u8 }
    ret worst
}

fn affine_slice_kind(c: *Checker, ty: Type) -> u8 {
    if ty.kind != .Slice || !ty.has_element || ty.element >= c.type_count { ret 0u8 }
    ret affine_kind(c, c.types[ty.element], 0usize)
}

// Whether the type is a resource type itself -- a seeded handle or a declared
// `resource` -- as against a struct that merely holds one.
fn resource_type(c: *Checker, ty: Type) -> bool {
    if ty.kind != .Named { ret false }
    if seeded_handle(c, ty) { ret true }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret false }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    ret aggregate.resource
}

// The struct a tracked local is, when its fields are followed one by one: a struct
// that holds resources and is not a resource itself.
fn resource_tracked_struct(c: *Checker, ty: Type) -> (usize, bool) {
    if ty.kind != .Named || resource_type(c, ty) { ret (0usize, false) }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret (0usize, false) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    if aggregate.kind != .Struct { ret (0usize, false) }
    ret (aggregate_index, affine_kind(c, ty, 0usize) != 0u8)
}

fn field_state(b: u8) -> u8 { ret b & 15u8 }
fn field_owed(b: u8) -> bool {
    let bit = b & 16u8
    ret bit != 0u8
}
fn field_with(state: u8, owed: bool) -> u8 {
    if owed { ret state | 16u8 }
    ret state
}

// A tracked struct local's field bytes made, every affine field in `state`, owed
// when its type names a cleanup; nothing for a local that is not a tracked struct.
fn resource_init_fields(c: *Checker, local_index: usize, state: u8) -> err {
    let local_type = c.locals[local_index].ty
    if local_type.kind == .Array && local_type.has_element && local_type.element < c.type_count {
        let kind = affine_kind(c, c.types[local_type.element], 0usize)
        if kind != 0u8 {
            let (elements, elements_error) = mem.alloc[u8](c.arena, local_type.array_length + 1usize)
            if elements_error != ok { ret elements_error }
            let (acquired, acquired_error) = mem.alloc[usize](c.arena, local_type.array_length + 1usize)
            if acquired_error != ok { ret acquired_error }
            var element_at = 0usize
            while element_at < local_type.array_length {
                elements[element_at] = field_with(state, kind == 2u8 && state != resource_null)
                acquired[element_at] = c.resources[local_index].acquired
                element_at += 1usize
            }
            c.resources[local_index].fields = elements[0usize..local_type.array_length]
            c.resources[local_index].elements_acquired = acquired[0usize..local_type.array_length]
            ret ok
        }
    }
    let (aggregate_index, tracked) = resource_tracked_struct(c, c.locals[local_index].ty)
    if !tracked {
        var none: []u8 = zero
        var no_elements_acquired: []usize = zero
        c.resources[local_index].fields = none
        c.resources[local_index].elements_acquired = no_elements_acquired
        ret ok
    }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    let (fields, fields_error) = mem.alloc[u8](c.arena, aggregate.field_count + 1usize)
    if fields_error != ok { ret fields_error }
    var at = 0usize
    while at < aggregate.field_count {
        fields[at] = 0u8
        let field_index = aggregate.first_field + at
        if field_index < c.aggregate_field_count {
            let kind = affine_kind(c, c.aggregate_fields[field_index].ty, 0usize)
            if kind != 0u8 { fields[at] = field_with(state, kind == 2u8 && state != resource_null) }
        }
        at += 1usize
    }
    c.resources[local_index].fields = fields[0usize..aggregate.field_count]
    ret ok
}

fn resource_set_fields(c: *Checker, local_index: usize, state: u8) {
    var at = 0usize
    while at < c.resources[local_index].fields.len {
        let b = c.resources[local_index].fields[at]
        if b != 0u8 { c.resources[local_index].fields[at] = field_with(state, field_owed(b) && state != resource_null) }
        at += 1usize
    }
}

// `s.f` where `s` is a tracked struct local and `f` an affine field: the local, the
// field's position in it.
fn resource_field_of(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, usize, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .FieldExpr { ret (0usize, 0usize, false) }
    let (base_index, has_base) = first_node_child(tree, node)
    if !has_base { ret (0usize, 0usize, false) }
    let (local_index, is_resource) = resource_local_of(c, g, tree, module_index, base_index)
    if !is_resource || c.resources[local_index].fields.len == 0usize { ret (0usize, 0usize, false) }
    let member = c.tokens[usize(node.token_end) - 1usize]
    if member.kind != .Identifier { ret (0usize, 0usize, false) }
    let name = g.modules[module_index].text[member.start..member.end]
    let (field_index, found) = find_aggregate_field(c, c.locals[local_index].ty, name)
    if !found { ret (0usize, 0usize, false) }
    let (aggregate_index, tracked) = resource_tracked_struct(c, c.locals[local_index].ty)
    if !tracked { ret (0usize, 0usize, false) }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    if field_index < aggregate.first_field { ret (0usize, 0usize, false) }
    let at = field_index - aggregate.first_field
    if at >= c.resources[local_index].fields.len || c.resources[local_index].fields[at] == 0u8 { ret (0usize, 0usize, false) }
    ret (local_index, at, true)
}

fn resource_field_name(c: *Checker, local_index: usize, at: usize) -> str {
    if c.locals[local_index].ty.kind == .Array {
        let base = c.locals[local_index].name
        let index = decimal_text(c, at)
        let (name, name_error) = mem.alloc[u8](c.arena, base.len + index.len + 3usize)
        if name_error != ok { ret base }
        var out = fix_append(name, 0usize, base)
        name[out] = 91u8
        out += 1usize
        out = fix_append(name, out, index)
        name[out] = 93u8
        out += 1usize
        ret name[0usize..out]
    }
    let (aggregate_index, tracked) = resource_tracked_struct(c, c.locals[local_index].ty)
    if !tracked { ret c.locals[local_index].name }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    if aggregate.first_field + at < c.aggregate_field_count { ret c.aggregate_fields[aggregate.first_field + at].name }
    ret c.locals[local_index].name
}

fn resource_part_acquired(c: *Checker, local_index: usize, at: usize) -> usize {
    if at < c.resources[local_index].elements_acquired.len { ret c.resources[local_index].elements_acquired[at] }
    ret c.resources[local_index].acquired
}

fn resource_index_value(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    let checkpoint = c.constant_expr_count
    let expected_before = c.failure_expected
    let actual_before = c.failure_actual
    let mismatch_before = c.failure_mismatch_end
    let (expression, copy_error) = copy_constant_expr(c, g, tree, module_index, node_index)
    var index = normalized_integer(0usize, false)
    var index_type = invalid_type()
    var index_error = copy_error
    if copy_error == ok { (index, index_type, index_error) = evaluate_constant_expr(c, expression, make_type(.Integer, "usize", module_index)) }
    c.constant_expr_count = checkpoint
    c.failure_expected = expected_before
    c.failure_actual = actual_before
    c.failure_mismatch_end = mismatch_before
    if index_error != ok || index.negative || index_type.kind != .Integer { ret (0usize, false) }
    ret (index.magnitude, true)
}

// Recognize the canonical exhaustive index loop used for fixed arrays. The
// initializer must immediately precede the loop, and the body must contain one
// `i += 1`; other writes to the induction local make it non-canonical.
fn resource_loop_fact(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, loop_node: syntax.Node, condition_index: usize, body: syntax.Node) -> (str, usize, usize, bool) {
    let condition = tree.nodes[condition_index]
    if condition.kind != .BinaryExpr || binary_operator(c, tree, condition) != .PunctLt { ret ("", 0usize, 0usize, false) }
    var children: [2]usize = zero
    var count = 0usize
    let child_end = usize(condition.first_child) + usize(condition.child_count)
    var child_at = usize(condition.first_child)
    while child_at < child_end {
        if parse.child_is_node_at(tree, child_at) {
            if count == 2usize { ret ("", 0usize, 0usize, false) }
            children[count] = parse.child_index_at(tree, child_at)
            count += 1usize
        }
        child_at += 1usize
    }
    if count != 2usize || tree.nodes[children[0usize]].kind != .NameExpr { ret ("", 0usize, 0usize, false) }
    let index_token = c.tokens[usize(tree.nodes[children[0usize]].token_start)]
    if index_token.kind != .Identifier { ret ("", 0usize, 0usize, false) }
    let index_name = g.modules[module_index].text[index_token.start..index_token.end]
    let (bound_value, bound_constant) = resource_index_value(c, g, tree, module_index, children[1usize])
    var bound_local = 0usize
    if !bound_constant {
        let right = tree.nodes[children[1usize]]
        let (member, has_member) = field_expression_name(c, g.modules[module_index].text, tree, right)
        var (local_index, has_local) = place_base_local(c, g, tree, module_index, children[1usize])
        if !has_member || !same(member, "len") || !has_local { ret ("", 0usize, 0usize, false) }
        bound_local = local_index + 1usize
    }

    var token_at = 0usize
    let loop_start = usize(loop_node.token_start)
    if loop_start > 12usize { token_at = loop_start - 12usize }
    var initialized_zero = false
    while token_at < loop_start {
        let prior_name = c.tokens[token_at]
        if prior_name.kind == .Identifier && same(g.modules[module_index].text[prior_name.start..prior_name.end], index_name) {
            var assign_at = token_at + 1usize
            while assign_at < loop_start && c.tokens[assign_at].kind == .Newline { assign_at += 1usize }
            var value_at = assign_at + 1usize
            while value_at < loop_start && c.tokens[value_at].kind == .Newline { value_at += 1usize }
            if assign_at < loop_start && value_at < loop_start && c.tokens[assign_at].kind == .PunctAssign && c.tokens[value_at].kind == .Integer {
                let prior_value = c.tokens[value_at]
                let prior_spelling = g.modules[module_index].text[prior_value.start..prior_value.end]
                if prior_spelling.len != 0usize && prior_spelling[0usize] == 48u8 { initialized_zero = true }
            }
        }
        token_at += 1usize
    }
    if !initialized_zero { ret ("", 0usize, 0usize, false) }

    var increments = 0usize
    token_at = usize(body.token_start)
    let token_end = usize(body.token_end)
    while token_at + 1usize < token_end {
        let token = c.tokens[token_at]
        if token.kind == .Identifier && same(g.modules[module_index].text[token.start..token.end], index_name) {
            let next = c.tokens[token_at + 1usize].kind
            if next == .PunctAddAssign {
                if token_at + 2usize >= token_end { ret ("", 0usize, 0usize, false) }
                let step = c.tokens[token_at + 2usize]
                let step_spelling = g.modules[module_index].text[step.start..step.end]
                if step.kind != .Integer || step_spelling.len == 0usize || step_spelling[0usize] != 49u8 { ret ("", 0usize, 0usize, false) }
                increments += 1usize
            } else {
                if next == .PunctAssign || next == .PunctSubAssign || next == .PunctMulAssign || next == .PunctDivAssign || next == .PunctRemAssign { ret ("", 0usize, 0usize, false) }
            }
        }
        token_at += 1usize
    }
    ret (index_name, bound_value, bound_local, increments == 1usize)
}

fn resource_element_is_swept(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, first: usize, end: usize) -> bool {
    if c.loop_depth == 0usize || c.loop_depth > c.resource_loop_sweep.len { ret false }
    let loop_at = c.loop_depth - 1usize
    if !c.resource_loop_sweep[loop_at] || c.resource_loop_bound_local[loop_at] != 0usize || first != 0usize || end != c.resource_loop_bound[loop_at] { ret false }
    let node = tree.nodes[node_index]
    var bracket: BracketInfo = zero
    if read_bracket(c, tree, node, &bracket) != ok || bracket.range || bracket.child_count != 2usize { ret false }
    let index = tree.nodes[bracket.first]
    if index.kind != .NameExpr { ret false }
    let token = c.tokens[usize(index.token_start)]
    ret token.kind == .Identifier && same(g.modules[module_index].text[token.start..token.end], c.resource_loop_index[loop_at])
}

fn resource_owned_slice_is_swept(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, local_index: usize) -> bool {
    if c.loop_depth == 0usize || c.loop_depth > c.resource_loop_sweep.len { ret false }
    let loop_at = c.loop_depth - 1usize
    if !c.resource_loop_sweep[loop_at] || c.resource_loop_bound_local[loop_at] != local_index + 1usize { ret false }
    let node = tree.nodes[node_index]
    var bracket: BracketInfo = zero
    if read_bracket(c, tree, node, &bracket) != ok || bracket.range { ret false }
    let index = tree.nodes[bracket.first]
    if index.kind != .NameExpr { ret false }
    let token = c.tokens[usize(index.token_start)]
    ret token.kind == .Identifier && same(g.modules[module_index].text[token.start..token.end], c.resource_loop_index[loop_at])
}

// The possible slots of a fixed affine array element. A comptime index names one;
// a runtime index names every slot reachable through the direct array or a slice
// whose owner and lower bound are known.
fn resource_element_candidates(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, usize, usize, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .BracketPostfix { ret (0usize, 0usize, 0usize, false) }
    var bracket: BracketInfo = zero
    if read_bracket(c, tree, node, &bracket) != ok || bracket.range || bracket.child_count != 2usize { ret (0usize, 0usize, 0usize, false) }
    let base = tree.nodes[bracket.base]
    if base.kind != .NameExpr { ret (0usize, 0usize, 0usize, false) }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret (0usize, 0usize, 0usize, false) }
    let (base_local, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
    if !found { ret (0usize, 0usize, 0usize, false) }
    var local_index = base_local
    var offset = 0usize
    var offset_known = true
    if c.locals[base_local].ty.kind == .Slice {
        if c.resources[base_local].points_to == 0usize { ret (0usize, 0usize, 0usize, false) }
        local_index = c.resources[base_local].points_to - 1usize
        offset_known = c.resources[base_local].slice_offset_known
        if offset_known { offset = c.resources[base_local].slice_offset }
    }
    if local_index >= c.local_count || c.locals[local_index].ty.kind != .Array || c.resources[local_index].fields.len == 0usize || offset >= c.resources[local_index].fields.len { ret (0usize, 0usize, 0usize, false) }
    let (relative, is_constant) = resource_index_value(c, g, tree, module_index, bracket.first)
    if !offset_known { ret (local_index, 0usize, c.resources[local_index].fields.len, true) }
    if !is_constant { ret (local_index, offset, c.resources[local_index].fields.len, true) }
    if relative > c.resources[local_index].fields.len || offset > c.resources[local_index].fields.len - relative { ret (0usize, 0usize, 0usize, false) }
    let index = offset + relative
    if index >= c.resources[local_index].fields.len { ret (0usize, 0usize, 0usize, false) }
    ret (local_index, index, index + 1usize, true)
}

// A comptime-indexed slot of a fixed affine array, reached either directly or
// through a known full-slice alias.
fn resource_element_of(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, usize, bool) {
    let (local_index, first, end, found) = resource_element_candidates(c, g, tree, module_index, node_index)
    if !found || end != first + 1usize { ret (0usize, 0usize, false) }
    ret (local_index, first, true)
}

fn resource_owned_slice_of(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .BracketPostfix { ret (0usize, false) }
    var bracket: BracketInfo = zero
    if read_bracket(c, tree, node, &bracket) != ok || bracket.range { ret (0usize, false) }
    let base = tree.nodes[bracket.base]
    if base.kind != .NameExpr { ret (0usize, false) }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret (0usize, false) }
    let (local_index, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
    if !found || c.locals[local_index].ty.kind != .Slice || c.resources[local_index].state == resource_plain || c.resources[local_index].borrowed { ret (0usize, false) }
    ret (local_index, affine_slice_kind(c, c.locals[local_index].ty) != 0u8)
}

// `resource(cleanup)` between a type declaration's `=` and its body.
fn resource_declaration(c: *Checker, text: str, node: syntax.Node, body: syntax.Node) -> (bool, str) {
    var at = usize(node.token_start)
    var after_assign = false
    var is_resource = false
    var cleanup = ""
    while at < usize(body.token_start) && at < c.token_count {
        let token = c.tokens[at]
        if token.kind == .PunctAssign { after_assign = true }
        if after_assign && token.kind == .Identifier {
            let spelled = text[token.start..token.end]
            if !is_resource && same(spelled, "resource") {
                is_resource = true
            } else {
                if is_resource && cleanup.len == 0usize { cleanup = spelled }
            }
        }
        at += 1usize
    }
    ret (is_resource, cleanup)
}

// Every declared resource's cleanup is `fn cleanup(x: own T) -> ...` in its module.
fn validate_resource_cleanups(c: *Checker, g: *graph.Graph) -> err {
    var at = 0usize
    while at < c.aggregate_count {
        let aggregate = c.aggregates[at]
        if aggregate.resource && aggregate.cleanup.len != 0usize && !aggregate.instance {
            let (function_index, found) = find_function(c, aggregate.module_index, aggregate.cleanup)
            var valid = found
            if found {
                let function = c.functions[function_index]
                if function.parameter_count == 0usize { valid = false }
                if valid {
                    let owned_at = function.first_parameter + function.parameter_count - 1usize
                    if owned_at >= c.parameter_count || !c.parameters[owned_at].own { valid = false }
                    if valid {
                        let owned = c.parameters[owned_at].ty
                        if owned.kind != .Named || !same(owned.name, aggregate.name) || owned.module_index != aggregate.module_index { valid = false }
                    }
                }
            }
            if !valid {
                record_failure_token(c, aggregate.module_index, aggregate.token, .ResourceCleanupSignature, aggregate.name, aggregate.cleanup)
                ret ResourceViolation
            }
        }
        at += 1usize
    }
    ret ok
}

// Whether the callee's parameter takes ownership: declared `own`, or the seeded
// closers' first.
fn parameter_consumes(c: *Checker, function: Function, index: usize) -> bool {
    if index < function.parameter_count && function.first_parameter + index < c.parameter_count && c.parameters[function.first_parameter + index].own { ret true }
    if index != 0usize || !module_is_os(c, function.module_index) { ret false }
    ret same(function.name, "close") || same(function.name, "wait") || same(function.name, "wait_usage") || same(function.name, "thread_join") || same(function.name, "thread_detach")
}

// Whether the callee hands out a handle the process owns: no obligation on it.
fn producer_borrowed(c: *Checker, function: Function) -> bool {
    if !module_is_os(c, function.module_index) { ret false }
    ret same(function.name, "stdin") || same(function.name, "stdout") || same(function.name, "stderr")
}

// The lent local a place reaches through a pointer alias (D393): the base name of
// the place, a local bound from `&x`, with `x` lent to a running thread.
fn alias_of_lent(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    let (pointed, has_target) = alias_target(c, g, tree, module_index, node_index)
    if has_target && c.resources[pointed].lent_to != 0usize { ret (pointed, true) }
    var wanted = 0usize
    while true {
        let (candidate, found) = dynamic_alias_candidate(c, g, tree, module_index, node_index, wanted)
        if !found { break }
        if c.resources[candidate].lent_to != 0usize { ret (candidate, true) }
        wanted += 1usize
    }
    ret (0usize, false)
}

fn clear_resource_aliases(c: *Checker, carrier: usize) {
    var read = 0usize
    var write = 0usize
    while read < c.resource_alias_count {
        if c.resource_aliases[read].carrier != carrier {
            c.resource_aliases[write] = c.resource_aliases[read]
            write += 1usize
        }
        read += 1usize
    }
    c.resource_alias_count = write
}

fn grow_resource_aliases(c: *Checker) -> err {
    if c.resource_alias_count < c.resource_aliases.len { ret ok }
    var capacity = 8usize
    if c.resource_aliases.len != 0usize { capacity = c.resource_aliases.len * 2usize }
    let (aliases, aliases_error) = mem.alloc[ResourceAlias](c.arena, capacity)
    if aliases_error != ok { ret aliases_error }
    var at = 0usize
    while at < c.resource_alias_count {
        aliases[at] = c.resource_aliases[at]
        at += 1usize
    }
    c.resource_aliases = aliases
    ret ok
}

fn same_resource_path(left: []str, right: []str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if !same(left[at], right[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn set_sparse_resource_alias(c: *Checker, carrier: usize, path: []str, pointed: usize) -> err {
    var at = 0usize
    while at < c.resource_alias_count {
        if c.resource_aliases[at].carrier == carrier && same_resource_path(c.resource_aliases[at].path, path) {
            c.resource_aliases[at].pointed = pointed
            ret ok
        }
        at += 1usize
    }
    let (stored, stored_error) = mem.alloc[str](c.arena, path.len)
    if stored_error != ok { ret stored_error }
    at = 0usize
    while at < path.len {
        stored[at] = path[at]
        at += 1usize
    }
    try grow_resource_aliases(c)
    c.resource_aliases[c.resource_alias_count] = ResourceAlias { carrier: carrier, pointed: pointed, path: stored }
    c.resource_alias_count += 1usize
    ret ok
}

fn set_resource_alias(c: *Checker, carrier: usize, field: str, pointed: usize) -> err {
    if c.resources[carrier].points_to == 0usize || same(field, c.resources[carrier].points_to_field) {
        c.resources[carrier].points_to = pointed + 1usize
        c.resources[carrier].points_to_field = field
        ret ok
    }
    if !c.resources[carrier].slice_offset_known || same(field, c.resources[carrier].mark_arena) {
        c.resources[carrier].slice_offset = pointed + 1usize
        c.resources[carrier].slice_offset_known = true
        c.resources[carrier].mark_arena = field
        ret ok
    }
    var path: [1]str = zero
    path[0usize] = field
    ret set_sparse_resource_alias(c, carrier, path[0usize..1usize], pointed)
}

fn set_resource_path_alias(c: *Checker, carrier: usize, path: []str, pointed: usize) -> err {
    if path.len == 1usize { ret set_resource_alias(c, carrier, path[0usize], pointed) }
    ret set_sparse_resource_alias(c, carrier, path, pointed)
}

// `members` is the written field chain from the outside back toward its base. A
// stored alias path runs from that base outward and may be a prefix: in
// `ctx.inner.target.hits`, `inner.target` identifies the pointer and `hits` is in
// the pointed-to value.
fn resource_path_matches(path: []str, members: []str) -> bool {
    if path.len == 0usize || path.len > members.len { ret false }
    var at = 0usize
    while at < path.len {
        let member = members[members.len - at - 1usize]
        if !same(member, "*") && !same(path[at], member) { ret false }
        at += 1usize
    }
    ret true
}

fn resource_members_dynamic(members: []str) -> bool {
    var at = 0usize
    while at < members.len {
        if same(members[at], "*") { ret true }
        at += 1usize
    }
    ret false
}

// The nth possible target of a runtime-indexed alias path. Only aliases at the
// longest matching path participate, preserving the exact-path rule above.
fn resource_alias_candidate(c: *Checker, carrier: usize, members: []str, wanted: usize) -> (usize, bool) {
    if members.len == 0usize { ret (0usize, false) }
    var longest = 0usize
    var at = 0usize
    while at < c.resource_alias_count {
        let alias = c.resource_aliases[at]
        if alias.carrier == carrier && alias.path.len > longest && resource_path_matches(alias.path, members) { longest = alias.path.len }
        at += 1usize
    }
    let field = members[members.len - 1usize]
    if longest < 1usize && c.resources[carrier].points_to != 0usize && (same(field, "*") || same(field, c.resources[carrier].points_to_field)) { longest = 1usize }
    if longest < 1usize && c.resources[carrier].slice_offset_known && (same(field, "*") || same(field, c.resources[carrier].mark_arena)) { longest = 1usize }
    if longest == 0usize { ret (0usize, false) }
    var ordinal = 0usize
    if longest == 1usize && c.resources[carrier].points_to != 0usize && (same(field, "*") || same(field, c.resources[carrier].points_to_field)) {
        if ordinal == wanted { ret (c.resources[carrier].points_to - 1usize, true) }
        ordinal += 1usize
    }
    if longest == 1usize && c.resources[carrier].slice_offset_known && (same(field, "*") || same(field, c.resources[carrier].mark_arena)) {
        if ordinal == wanted { ret (c.resources[carrier].slice_offset - 1usize, true) }
        ordinal += 1usize
    }
    at = 0usize
    while at < c.resource_alias_count {
        let alias = c.resource_aliases[at]
        if alias.carrier == carrier && alias.path.len == longest && resource_path_matches(alias.path, members) {
            if ordinal == wanted { ret (alias.pointed, true) }
            ordinal += 1usize
        }
        at += 1usize
    }
    ret (0usize, false)
}

fn resource_alias_target(c: *Checker, carrier: usize, members: []str) -> (usize, bool) {
    if resource_members_dynamic(members) { ret (0usize, false) }
    var pointed = 0usize
    var longest = 0usize
    var at = 0usize
    while at < c.resource_alias_count {
        let alias = c.resource_aliases[at]
        if alias.carrier == carrier && alias.path.len > longest && resource_path_matches(alias.path, members) {
            pointed = alias.pointed
            longest = alias.path.len
        }
        at += 1usize
    }
    if longest != 0usize { ret (pointed, true) }
    if members.len == 0usize { ret (0usize, false) }
    let field = members[members.len - 1usize]
    if c.resources[carrier].points_to != 0usize && same(field, c.resources[carrier].points_to_field) {
        ret (c.resources[carrier].points_to - 1usize, true)
    }
    if c.resources[carrier].slice_offset_known && same(field, c.resources[carrier].mark_arena) {
        ret (c.resources[carrier].slice_offset - 1usize, true)
    }
    ret (0usize, false)
}

fn record_literal_alias_paths(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, carrier: usize, literal_index: usize, fields: []str, depth: usize) -> err {
    let literal = tree.nodes[literal_index]
    let text = g.modules[module_index].text
    let (header_index, _, header_error) = aggregate_literal_header(tree, literal)
    let indexed = header_error == ok && tree.nodes[header_index].kind == .ArrayType
    let end = usize(literal.first_child) + usize(literal.child_count)
    var at = usize(literal.first_child)
    var item_index = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item = tree.nodes[parse.child_index_at(tree, at)]
            if item.kind == .LiteralItem {
                let (value_index, has_value) = first_node_child(tree, item)
                if has_value {
                    if depth == fields.len { ret Capacity }
                    var has_segment = indexed
                    if indexed {
                        fields[depth] = decimal_text(c, item_index)
                    } else {
                        let (field, found_field) = literal_item_name(c, text, item)
                        fields[depth] = field
                        has_segment = found_field
                    }
                    if has_segment {
                        var (pointed, found) = address_argument_local(c, g, tree, module_index, value_index)
                        if !found { (pointed, found) = alias_target(c, g, tree, module_index, value_index) }
                        if !found {
                            let (source, is_place) = place_base_local(c, g, tree, module_index, value_index)
                            if is_place && holds_pointer(c, c.locals[source].ty, 0usize) {
                                pointed = source
                                found = true
                            }
                        }
                        if found && pointed != carrier { try set_resource_path_alias(c, carrier, fields[0usize..depth + 1usize], pointed) }
                        if !found && tree.nodes[value_index].kind == .AggregateLiteral {
                            try record_literal_alias_paths(c, g, tree, module_index, carrier, value_index, fields, depth + 1usize)
                        }
                    }
                }
                item_index += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

fn record_literal_aliases(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, carrier: usize, literal_index: usize) -> err {
    var fields: [128]str = zero
    ret record_literal_alias_paths(c, g, tree, module_index, carrier, literal_index, fields[0usize..fields.len], 0usize)
}

// What a local aliases after a binding or an assignment (D393, D395, D413, D416):
// `&x` for a pointer, a place of `x` for a slice, a literal with `&x` in a field
// for a struct; nothing otherwise, which also ends an alias the local had. And a
// slice local rebound ends the aliases other slices held of its old storage: they
// view what it viewed, not what it views now.
fn record_alias(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, local_index: usize, initializer_index: usize, has_initializer: bool) -> err {
    c.resources[local_index].points_to = 0usize
    c.resources[local_index].points_to_field = ""
    if c.locals[local_index].ty.kind == .Named && c.resources[local_index].slice_offset_known { c.resources[local_index].mark_arena = "" }
    c.resources[local_index].slice_offset = 0usize
    c.resources[local_index].slice_offset_known = false
    clear_resource_aliases(c, local_index)
    if c.locals[local_index].ty.kind == .Slice {
        var other = 0usize
        while other < c.local_count {
            if other != local_index && c.resources[other].points_to == local_index + 1usize && c.locals[other].ty.kind == .Slice { c.resources[other].points_to = 0usize }
            other += 1usize
        }
    }
    if !has_initializer { ret ok }
    if (c.locals[local_index].ty.kind == .Named || c.locals[local_index].ty.kind == .Array) && tree.nodes[initializer_index].kind == .AggregateLiteral {
        try record_literal_aliases(c, g, tree, module_index, local_index, initializer_index)
    }
    if (c.locals[local_index].ty.kind == .Named || c.locals[local_index].ty.kind == .Array) && tree.nodes[initializer_index].kind == .NameExpr {
        let token = c.tokens[usize(tree.nodes[initializer_index].token_start)]
        let (source, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
        if found && (c.locals[source].ty.kind == .Named || c.locals[source].ty.kind == .Array) {
            if c.resources[source].points_to != 0usize {
                c.resources[local_index].points_to = c.resources[source].points_to
                c.resources[local_index].points_to_field = c.resources[source].points_to_field
                if c.resources[source].slice_offset_known {
                    c.resources[local_index].slice_offset = c.resources[source].slice_offset
                    c.resources[local_index].slice_offset_known = true
                    c.resources[local_index].mark_arena = c.resources[source].mark_arena
                }
            }
            // Preserve sparse field and element identities across a lexical carrier
            // copy; stop at the old tail because appending grows this table.
            let source_alias_count = c.resource_alias_count
            var alias_at = 0usize
            while alias_at < source_alias_count {
                let alias = c.resource_aliases[alias_at]
                if alias.carrier == source { try set_sparse_resource_alias(c, local_index, alias.path, alias.pointed) }
                alias_at += 1usize
            }
        }
    }
    if c.locals[local_index].ty.kind == .Pointer {
        var (pointed, is_address) = address_argument_local(c, g, tree, module_index, initializer_index)
        // Copying a pointer local copies its borrow, not an unrelated identity.
        if !is_address { (pointed, is_address) = alias_target(c, g, tree, module_index, initializer_index) }
        // A parameter pointer has no local pointee, so its first copy names the
        // parameter as the lexical identity shared by later copies (D676).
        if !is_address {
            let (source, is_place) = place_base_local(c, g, tree, module_index, initializer_index)
            if is_place && c.locals[source].ty.kind == .Pointer {
                pointed = source
                is_address = true
            }
        }
        if is_address && pointed != local_index { c.resources[local_index].points_to = pointed + 1usize }
    }
    if c.locals[local_index].ty.kind == .Slice {
        let (viewed, is_place) = place_base_local(c, g, tree, module_index, initializer_index)
        if is_place && viewed != local_index && (c.locals[viewed].ty.kind == .Slice || c.locals[viewed].ty.kind == .Array || c.locals[viewed].ty.kind == .Named) {
            c.resources[local_index].points_to = viewed + 1usize
            var owner = viewed
            var base_offset = 0usize
            var base_known = c.locals[viewed].ty.kind == .Array
            if c.locals[viewed].ty.kind == .Slice && c.resources[viewed].points_to != 0usize {
                owner = c.resources[viewed].points_to - 1usize
                c.resources[local_index].points_to = owner + 1usize
                if c.resources[viewed].slice_offset_known {
                    base_offset = c.resources[viewed].slice_offset
                    base_known = true
                }
            }
            let initializer = tree.nodes[initializer_index]
            if initializer.kind == .BracketPostfix {
                var bracket: BracketInfo = zero
                if read_bracket(c, tree, initializer, &bracket) == ok && bracket.range && base_known {
                    var lower = 0usize
                    var lower_known = true
                    var range_at = usize(tree.nodes[bracket.base].token_end)
                    while range_at < usize(initializer.token_end) && c.tokens[range_at].kind != .PunctRange { range_at += 1usize }
                    if bracket.child_count >= 2usize && usize(tree.nodes[bracket.first].token_start) < range_at { (lower, lower_known) = resource_index_value(c, g, tree, module_index, bracket.first) }
                    if lower_known && base_offset <= c.resources[owner].fields.len && lower <= c.resources[owner].fields.len - base_offset {
                        c.resources[local_index].slice_offset = base_offset + lower
                        c.resources[local_index].slice_offset_known = true
                    }
                }
            } else {
                if base_known {
                    c.resources[local_index].slice_offset = base_offset
                    c.resources[local_index].slice_offset_known = true
                }
            }
        }
    }
    // The view, as a fact (D487): the local and what it views.
    if c.resources[local_index].points_to != 0usize {
        record_explain_borrow(c, module_index, tree.nodes[initializer_index], c.locals[local_index].name, c.locals[c.resources[local_index].points_to - 1usize].name)
    }
    ret ok
}

// The target of a place's pointer alias (D393): the base name, a local bound from
// `&x`, and `x`.
fn local_field_path(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, members: []str) -> (usize, usize, bool) {
    var base_index = node_index
    var member_count = 0usize
    while tree.nodes[base_index].kind == .FieldExpr || tree.nodes[base_index].kind == .BracketPostfix || tree.nodes[base_index].kind == .UnaryExpr {
        let (deeper_index, has_deeper) = first_node_child(tree, tree.nodes[base_index])
        if !has_deeper { break }
        if tree.nodes[base_index].kind == .FieldExpr {
            let (member, found_member) = field_expression_name(c, g.modules[module_index].text, tree, tree.nodes[base_index])
            if found_member {
                if member_count == members.len { ret (0usize, 0usize, false) }
                members[member_count] = member
                member_count += 1usize
            }
        }
        if tree.nodes[base_index].kind == .BracketPostfix {
            var bracket: BracketInfo = zero
            if read_bracket(c, tree, tree.nodes[base_index], &bracket) != ok || bracket.range || bracket.child_count != 2usize { ret (0usize, 0usize, false) }
            let (index, index_known) = resource_index_value(c, g, tree, module_index, bracket.first)
            if member_count == members.len { ret (0usize, 0usize, false) }
            if index_known { members[member_count] = decimal_text(c, index) } else { members[member_count] = "*" }
            member_count += 1usize
        }
        base_index = deeper_index
    }
    let base = tree.nodes[base_index]
    if base.kind != .NameExpr { ret (0usize, 0usize, false) }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret (0usize, 0usize, false) }
    let (local_index, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
    ret (local_index, member_count, found)
}

fn alias_target(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    var members: [128]str = zero
    let (pointer_local, member_count, found) = local_field_path(c, g, tree, module_index, node_index, members[0usize..members.len])
    if !found { ret (0usize, false) }
    if c.resources[pointer_local].points_to != 0usize && c.resources[pointer_local].points_to_field.len == 0usize {
        let pointed = c.resources[pointer_local].points_to - 1usize
        if pointed >= c.local_count { ret (0usize, false) }
        ret (pointed, true)
    }
    let (pointed, has_target) = resource_alias_target(c, pointer_local, members[0usize..member_count])
    if !has_target { ret (0usize, false) }
    if pointed >= c.local_count { ret (0usize, false) }
    ret (pointed, true)
}

fn dynamic_alias_candidate(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, wanted: usize) -> (usize, bool) {
    var members: [128]str = zero
    let (carrier, member_count, found) = local_field_path(c, g, tree, module_index, node_index, members[0usize..members.len])
    if !found || !resource_members_dynamic(members[0usize..member_count]) { ret (0usize, false) }
    let (pointed, has_target) = resource_alias_candidate(c, carrier, members[0usize..member_count], wanted)
    if !has_target || pointed >= c.local_count { ret (0usize, false) }
    ret (pointed, true)
}

fn has_dynamic_alias_path(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> bool {
    var members: [128]str = zero
    let (_, member_count, found) = local_field_path(c, g, tree, module_index, node_index, members[0usize..members.len])
    ret found && resource_members_dynamic(members[0usize..member_count])
}

// The first field of a struct literal given `&x` of a local (D413): which local, and
// the field's name.
fn literal_address_field(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, literal_index: usize) -> (usize, str, bool) {
    let (pointed, member, found) = literal_address_field_after(c, g, tree, module_index, literal_index, "")
    ret (pointed, member, found)
}

// The first address under a top-level field other than `after`.
fn literal_address_field_after(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, literal_index: usize, after: str) -> (usize, str, bool) {
    let literal = tree.nodes[literal_index]
    let text = g.modules[module_index].text
    let end = usize(literal.first_child) + usize(literal.child_count)
    var at = usize(literal.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item_index = parse.child_index_at(tree, at)
            let item = tree.nodes[item_index]
            if item.kind == .LiteralItem {
                let name_token = c.tokens[usize(item.token_start)]
                let (value_index, has_value) = first_node_child(tree, item)
                if name_token.kind == .Identifier && has_value {
                    let member = text[name_token.start..name_token.end]
                    if after.len == 0usize || !same(member, after) {
                        let (pointed, is_address) = address_argument_local(c, g, tree, module_index, value_index)
                        if is_address { ret (pointed, member, true) }
                        if tree.nodes[value_index].kind == .AggregateLiteral {
                            let (nested, _, nested_address) = literal_address_field(c, g, tree, module_index, value_index)
                            if nested_address { ret (nested, member, true) }
                        }
                    }
                }
            }
        }
        at += 1usize
    }
    ret (0usize, "", false)
}

// The alias's target when a region reset or a container's change made it dangle (D394).
fn alias_of_dangling(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    let (pointed, has_target) = alias_target(c, g, tree, module_index, node_index)
    if has_target && c.resources[pointed].dangling != 0u8 {
        let state = c.resources[pointed].state
        if state == resource_moved || state == resource_maybe { ret (pointed, true) }
    }
    var wanted = 0usize
    while true {
        let (candidate, found) = dynamic_alias_candidate(c, g, tree, module_index, node_index, wanted)
        if !found { break }
        let state = c.resources[candidate].state
        if c.resources[candidate].dangling != 0u8 && (state == resource_moved || state == resource_maybe) { ret (candidate, true) }
        wanted += 1usize
    }
    ret (0usize, false)
}

fn resource_local_of(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (usize, bool) {
    let node = tree.nodes[node_index]
    if node.kind != .NameExpr { ret (0usize, false) }
    let token = c.tokens[usize(node.token_start)]
    if token.kind != .Identifier { ret (0usize, false) }
    let name = g.modules[module_index].text[token.start..token.end]
    let (local_index, found) = find_local(c, name)
    if !found || c.resources[local_index].state == resource_plain { ret (0usize, false) }
    ret (local_index, true)
}

fn any_affine_local(c: *Checker) -> bool {
    if !c.resources_on { ret false }
    if c.affine_answer_valid && c.affine_answer_count == c.local_count { ret c.affine_answer }
    var found = false
    var at = 0usize
    while at < c.local_count {
        if c.resources[at].state != resource_plain {
            found = true
            break
        }
        at += 1usize
    }
    c.affine_answer = found
    c.affine_answer_count = c.local_count
    c.affine_answer_valid = true
    ret found
}

fn line_detail(c: *Checker, g: *graph.Graph, module_index: usize, token_index: usize) -> str {
    if token_index >= c.token_count { ret "" }
    let line = lex.line_of(g.modules[module_index].text, g.modules[module_index].lines, c.tokens[token_index].start)
    ret decimal_text(c, line)
}

fn decimal_text(c: *Checker, value: usize) -> str {
    var digits: [24]u8 = zero
    var v = value
    var n = 0usize
    if v == 0usize {
        digits[23usize] = 48u8
        n = 1usize
    }
    while v > 0usize {
        digits[23usize - n] = u8(48usize + v % 10usize)
        v = v / 10usize
        n += 1usize
    }
    let (text, text_error) = mem.alloc[u8](c.arena, n)
    if text_error != ok { ret "" }
    var at = 0usize
    while at < n {
        text[at] = digits[24usize - n + at]
        at += 1usize
    }
    ret text[0usize..n]
}

// The uses in a statement's expressions, before the statement moves anything: a
// moved, maybe-moved or unchecked resource read here is the error, at its use. The
// walk stops at a block, whose statements are checked on their own, and skips an
// assignment's place, which is written, not read.
fn resource_uses(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, skip_first_name: bool) -> err {
    ret resource_uses_under(c, g, tree, module_index, node_index, skip_first_name, .Block)
}

fn resource_uses_under(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize, skip_first_name: bool, parent: syntax.Kind) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .Block { ret ok }
    // `&x` of a lent local is the sanctioned way to reach it -- an atomic, another
    // thread -- and not a read (D365).
    if node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctAmp {
        let (pointed, is_address) = address_argument_local(c, g, tree, module_index, node_index)
        if is_address && c.resources[pointed].lent_to != 0usize { ret ok }
        // `&p.field` with `p` an alias of a lent local is an address too (D393).
        if is_address && c.resources[pointed].points_to != 0usize && c.resources[pointed].points_to - 1usize < c.local_count && c.resources[c.resources[pointed].points_to - 1usize].lent_to != 0usize { ret ok }
    }
    // `*p`, `p.field`, `p[i]` with `p` bound from `&x` while `x` is lent to a thread
    // (D393): a read or a store of `x` by another name.
    if node.kind == .FieldExpr || node.kind == .BracketPostfix || (node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctStar) {
        let (lent_local, through_alias) = alias_of_lent(c, g, tree, module_index, node_index)
        if through_alias {
            record_failure_related(c, module_index, node, .ThreadShared, c.locals[lent_local].name, line_detail(c, g, module_index, c.resources[lent_local].lent_at), c.resources[lent_local].lent_at)
            ret ResourceViolation
        }
        // The same alias into storage a region reset or a container's change took
        // away (D394): the read is the local's, and refused as its own would be --
        // except `.len`, which reads no memory (D354).
        let (gone_local, through_gone) = alias_of_dangling(c, g, tree, module_index, node_index)
        var reads_length = false
        if through_gone && node.kind == .FieldExpr {
            let (member, has_member) = field_expression_name(c, g.modules[module_index].text, tree, node)
            reads_length = has_member && same(member, "len")
        }
        if through_gone && !reads_length {
            record_failure_related(c, module_index, node, dangling_kind(c, gone_local), c.locals[gone_local].name, line_detail(c, g, module_index, c.resources[gone_local].acquired), c.resources[gone_local].acquired)
            ret ResourceViolation
        }
    }
    if node.kind == .BracketPostfix {
        let (local_index, first, end, is_element) = resource_element_candidates(c, g, tree, module_index, node_index)
        var at = first
        while is_element && at < end {
            let byte = c.resources[local_index].fields[at]
            let state = field_state(byte)
            if field_owed(byte) && (state == resource_moved || state == resource_maybe) {
                let acquired = resource_part_acquired(c, local_index, at)
                record_failure_related(c, module_index, node, .ResourceUseAfterMove, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
                ret ResourceViolation
            }
            if field_owed(byte) && state == resource_unchecked {
                let acquired = resource_part_acquired(c, local_index, at)
                record_failure_related(c, module_index, node, .ResourceUnchecked, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
                ret ResourceViolation
            }
            at += 1usize
        }
        if is_element { ret ok }
    }
    if node.kind == .FieldExpr {
        let (local_index, at, is_field) = resource_field_of(c, g, tree, module_index, node_index)
        if is_field {
            let state = field_state(c.resources[local_index].fields[at])
            if state == resource_moved || state == resource_maybe {
                let acquired = resource_part_acquired(c, local_index, at)
                record_failure_related(c, module_index, node, .ResourceUseAfterMove, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
                ret ResourceViolation
            }
        }
        // A field of a tracked struct is its own question: the struct's whole state
        // does not gate a read of one field, plain or affine, only its own does. The
        // length of a dangling slice reads no memory (D354).
        let (base_index, has_base) = first_node_child(tree, node)
        if has_base && tree.nodes[base_index].kind == .NameExpr {
            let (base_local, base_is_resource) = resource_local_of(c, g, tree, module_index, base_index)
            if base_is_resource && c.resources[base_local].fields.len != 0usize { ret ok }
            let member = c.tokens[usize(node.token_end) - 1usize]
            if base_is_resource && c.resources[base_local].dangling != 0u8 && same(g.modules[module_index].text[member.start..member.end], "len") { ret ok }
        }
    }
    if node.kind == .NameExpr {
        let (local_index, is_resource) = resource_local_of(c, g, tree, module_index, node_index)
        if !is_resource { ret ok }
        let state = c.resources[local_index].state
        if c.resources[local_index].lent_to != 0usize {
            record_failure_related(c, module_index, node, .ThreadShared, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].lent_at), c.resources[local_index].lent_at)
            ret ResourceViolation
        }
        if state == resource_moved || state == resource_maybe {
            record_failure_related(c, module_index, node, dangling_kind(c, local_index), c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
            ret ResourceViolation
        }
        // An unchecked value may be moved whole into another binding, which takes the
        // untested error along, or returned beside its error; it cannot be read.
        let moved_whole = parent == .BindingStmt || parent == .AssignmentStmt || parent == .ReturnStmt
        if state == resource_unchecked && !moved_whole {
            record_failure_related(c, module_index, node, .ResourceUnchecked, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
            resource_fix_test(c, g, module_index, local_index)
            ret ResourceViolation
        }
        ret ok
    }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    var first = true
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let child_index = parse.child_index_at(tree, at)
            if !(first && skip_first_name && tree.nodes[child_index].kind == .NameExpr) {
                try resource_uses_under(c, g, tree, module_index, child_index, false, node.kind)
            }
            first = false
        }
        at += 1usize
    }
    ret ok
}

// A local consumed: by a move into another binding or an aggregate, by an `own`
// argument, by `ret`. It has to be owned to be consumed.
fn resource_consume(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    if !any_affine_local(c) { ret ok }
    let node = tree.nodes[node_index]
    if node.kind == .FieldExpr { ret resource_consume_field(c, g, tree, module_index, node_index) }
    if node.kind == .BracketPostfix {
        let (consumed_slice, slice_error) = resource_consume_full_slice(c, g, tree, module_index, node_index)
        if consumed_slice { ret slice_error }
        ret resource_consume_element(c, g, tree, module_index, node_index)
    }
    var (local_index, is_resource) = resource_local_of(c, g, tree, module_index, node_index)
    // `*p` where `p` was bound from `&f` is a move of `f`, not an unrelated
    // value (D610). The kept pointer pins `f`, so the ordinary rule below rejects
    // closing or transferring it until the block ends.
    if !is_resource && node.kind == .UnaryExpr && c.tokens[usize(node.token_start)].kind == .PunctStar {
        let (pointed, through_pointer) = alias_target(c, g, tree, module_index, node_index)
        if through_pointer && c.resources[pointed].state != resource_plain {
            local_index = pointed
            is_resource = true
        }
    }
    if !is_resource { ret ok }
    let state = c.resources[local_index].state
    // A struct moved whole must be whole: a field moved out of it stays out.
    var field_at = 0usize
    while field_at < c.resources[local_index].fields.len {
        let field_byte = c.resources[local_index].fields[field_at]
        let one = field_state(field_byte)
        if field_byte != 0u8 && (one == resource_moved || one == resource_maybe || one == resource_reserved) {
            let acquired = resource_part_acquired(c, local_index, field_at)
            record_failure_related(c, module_index, node, .ResourcePartialMove, resource_field_name(c, local_index, field_at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        field_at += 1usize
    }
    if state == resource_reserved {
        record_failure_related(c, module_index, node, .ResourceDeferredConsumed, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    // A null resource may be handed on -- `ret (file, Unsupported)` is the contract
    // for a failed acquisition -- and nothing is owed for it.
    if state == resource_null { ret ok }
    // What is borrowed cannot be given away: closed, handed to an `own` parameter,
    // or returned as the caller's to close.
    // A thread over this frame's storage (D357) is joined here, or bound to another
    // name here; detached, handed on, returned or stored, it would outlive what it
    // reads.
    let frame = c.resources[local_index].frame_borrow
    let stored_inside = c.consuming_store != 0usize && c.consuming_store >= frame
    if frame != 0usize && state == resource_owned && !c.consuming_join && !c.consuming_binding && !stored_inside {
        record_failure_related(c, module_index, node, .ThreadFrameEscape, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    if c.resource_transfer && c.resources[local_index].borrowed && state == resource_owned {
        record_failure_related(c, module_index, node, .ResourceBorrowConsumed, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    // A view -- a borrowed producer's handle, a field read of something that owns it
    // -- owes nothing and is moved by nobody; it is read as often as wanted.
    if state == resource_owned && (c.resources[local_index].view || c.resources[local_index].borrowed) && c.resources[local_index].fields.len == 0usize { ret ok }
    if state != resource_owned {
        record_failure_related(c, module_index, node, dangling_kind(c, local_index), c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    // Consumed by a deferred call: reserved, and discharged at the block's exit.
    if c.defer_depth != 0usize {
        c.resources[local_index].state = resource_reserved
        c.resources[local_index].acquired = usize(node.token_start)
        ret ok
    }
    // Joined: what the thread was given is the parent's again (D365). Moved
    // anywhere else -- into an array of threads the loop joins by element -- the
    // lending is beyond what one local's state can follow, and ends here too.
    var lent_at = 0usize
    while lent_at < c.local_count {
        if c.resources[lent_at].lent_to == local_index + 1usize {
            c.resources[lent_at].lent_to = 0usize
            if c.resources[lent_at].region == 0usize && c.resources[lent_at].view_of == 0usize { c.resources[lent_at].state = resource_plain }
        }
        lent_at += 1usize
    }
    // A pointer to it is live until its block ends: nothing moves out from under it.
    if c.resources[local_index].pinned != 0usize {
        record_failure_related(c, module_index, node, .ResourceMovedWhileBorrowed, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].pin_at), c.resources[local_index].pin_at)
        ret ResourceViolation
    }
    c.resources[local_index].state = resource_moved
    c.resources[local_index].acquired = usize(node.token_start)
    resource_set_fields(c, local_index, resource_moved)
    record_explain_move(c, module_index, node, c.locals[local_index].name)
    ret ok
}

fn resource_consume_full_slice(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> (bool, err) {
    let node = tree.nodes[node_index]
    var bracket: BracketInfo = zero
    if read_bracket(c, tree, node, &bracket) != ok || !bracket.range || bracket.child_count == 0usize || bracket.child_count > 2usize { ret (false, ok) }
    let base = tree.nodes[bracket.base]
    if base.kind != .NameExpr { ret (false, ok) }
    let token = c.tokens[usize(base.token_start)]
    if token.kind != .Identifier { ret (false, ok) }
    let (local_index, found) = find_local(c, g.modules[module_index].text[token.start..token.end])
    if !found || c.locals[local_index].ty.kind != .Array || c.resources[local_index].fields.len == 0usize { ret (false, ok) }
    var first = 0usize
    if bracket.child_count == 2usize {
        var range_at = usize(base.token_end)
        while range_at < usize(node.token_end) && c.tokens[range_at].kind != .PunctRange { range_at += 1usize }
        if range_at == usize(node.token_end) || usize(tree.nodes[bracket.first].token_start) > range_at { ret (false, ok) }
        let (lower, lower_constant) = resource_index_value(c, g, tree, module_index, bracket.first)
        if !lower_constant || lower > c.resources[local_index].fields.len {
            record_failure_related(c, module_index, node, .ResourcePartialMove, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
            ret (true, ResourceViolation)
        }
        first = lower
    }
    var at = first
    while at < c.resources[local_index].fields.len {
        let byte = c.resources[local_index].fields[at]
        if field_owed(byte) && field_state(byte) != resource_owned {
            let acquired = resource_part_acquired(c, local_index, at)
            record_failure_related(c, module_index, node, .ResourceUseAfterMove, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
            ret (true, ResourceViolation)
        }
        at += 1usize
    }
    at = first
    while at < c.resources[local_index].fields.len {
        let byte = c.resources[local_index].fields[at]
        if field_owed(byte) {
            c.resources[local_index].fields[at] = field_with(resource_moved, true)
            c.resources[local_index].elements_acquired[at] = usize(node.token_start)
        }
        at += 1usize
    }
    c.resources[local_index].acquired = usize(node.token_start)
    ret (true, ok)
}

// The arguments of a checked call that its callee consumes: moved. `resource_uses`
// ran before, so `f(x, x)` fails at the second argument here, as a move of a moved.
fn resource_call(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node, info: CallInfo) -> err {
    if !c.resources_on || info.is_cast || info.protocol_pending || !any_affine_local(c) { ret ok }
    region_call(c, g, tree, module_index, node, info)
    c.consuming_join = (module_is_os(c, info.function.module_index) && same(info.function.name, "thread_join")) || (module_is_thread(c, info.function.module_index) && same(info.function.name, "join"))
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    var child_position = 0usize
    while at < end {
        if parse.child_is_node_at(tree, at) {
            if child_position != 0usize && parameter_consumes(c, info.function, child_position - 1usize) {
                c.resource_transfer = true
                let consumed = resource_consume(c, g, tree, module_index, parse.child_index_at(tree, at))
                c.resource_transfer = false
                if consumed != ok { ret consumed }
            }
            child_position += 1usize
        }
        at += 1usize
    }
    c.consuming_join = false
    ret ok
}

fn lend_thread_storage(c: *Checker, thread_local: usize, pointed_index: usize, token: usize) {
    var pointed = pointed_index
    if c.resources[pointed].points_to != 0usize && (c.locals[pointed].ty.kind == .Slice || c.locals[pointed].ty.kind == .Pointer) {
        pointed = c.resources[pointed].points_to - 1usize
    }
    if c.resources[thread_local].frame_borrow == 0usize && c.locals[pointed].ty.kind != .Slice && c.locals[pointed].ty.kind != .Pointer {
        c.resources[thread_local].frame_borrow = pointed + 1usize
    }
    if pointed != thread_local && c.locals[pointed].ty.kind != .Pointer {
        if c.resources[pointed].state == resource_plain { region_tag(c, pointed, token) }
        c.resources[pointed].lent_to = thread_local + 1usize
        c.resources[pointed].lent_at = token
    }
}

// A local bound to a resource-typed value: from a call's result -- owned when the
// call cannot fail or was `try`d, unchecked until its error is tested otherwise,
// nothing at all from a borrowed producer -- from another local, which is moved,
// or from `zero`.
fn resource_bind_local(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, local_index: usize, statement: syntax.Node, initializer_index: usize, has_initializer: bool, from_call: bool, call: CallInfo, tried: bool, err_local: usize, has_err_local: bool) -> err {
    if !c.resources_on { ret ok }
    // `let m = mem.mark(a)` opens a region (D354): the mark is followed from here, and
    // it is what makes the pass look at this body at all.
    if from_call && !has_err_local && module_is_mem(c, call.function.module_index) && same(call.function.name, "mark") {
        c.resources[local_index].state = resource_owned
        c.resources[local_index].view = true
        c.resources[local_index].acquired = usize(statement.token_start)
        c.resources[local_index].mark_arena = call_argument_storage_text(c, g, tree, module_index, tree.nodes[initializer_index], 0usize)
        c.affine_answer_valid = false
        ret ok
    }
    // `let p = &x` (D393): `p` points at `x` until it is bound again. A slice bound
    // from a place of `x` -- `x[a..b]`, `x.items`, `x` itself a slice -- views the
    // same storage and is recorded the same way (D395); a struct literal with `&x` in
    // a field aliases `x` through that field (D413). An assignment records the same
    // (D416), in `resource_assign`.
    try record_alias(c, g, tree, module_index, local_index, initializer_index, has_initializer)
    if has_initializer && tree.nodes[initializer_index].kind == .NameExpr {
        let source_token = c.tokens[usize(tree.nodes[initializer_index].token_start)]
        let (source_local, source_found) = find_local(c, g.modules[module_index].text[source_token.start..source_token.end])
        if source_found && c.resources[source_local].mark_arena.len != 0usize && !c.resources[source_local].slice_offset_known {
            c.resources[local_index].mark_arena = c.resources[source_local].mark_arena
            c.resources[local_index].points_to = source_local + 1usize
            if c.resources[source_local].points_to != 0usize { c.resources[local_index].points_to = c.resources[source_local].points_to }
            c.resources[local_index].state = resource_owned
            c.resources[local_index].view = true
            c.resources[local_index].obligated = false
            c.affine_answer_valid = false
            ret ok
        }
    }
    let kind = affine_kind(c, c.locals[local_index].ty, 0usize)
    if kind == 0u8 { ret region_bind(c, g, tree, module_index, local_index, statement, initializer_index, has_initializer, from_call, call) }
    c.resources[local_index].acquired = usize(statement.token_start)
    c.resources[local_index].obligated = kind == 2u8
    c.resources[local_index].borrowed = false
    c.resources[local_index].view = false
    c.resources[local_index].frame_borrow = 0usize
    c.resources[local_index].lent_to = 0usize
    if contains_token(c, usize(statement.token_start), usize(statement.token_end), .KwUndef) {
        record_failure(c, module_index, statement, .ResourceUndef, c.locals[local_index].name, "")
        ret ResourceViolation
    }
    if !has_initializer || contains_token(c, usize(statement.token_start), usize(statement.token_end), .KwZero) {
        c.resources[local_index].state = resource_null
        c.resources[local_index].obligated = false
        ret resource_init_fields(c, local_index, resource_null)
    }
    if from_call {
        // A thread started over the address of this frame's storage (D357): an
        // argument `&x` where `x` is a local that is not a slice or a pointer.
        if seeded_handle(c, c.locals[local_index].ty) && same(c.locals[local_index].ty.name, "Thread") {
            var argument_at = 0usize
            while true {
                let (argument_index, has_argument) = call_argument_node(tree, tree.nodes[initializer_index], argument_at)
                if !has_argument { break }
                if has_dynamic_alias_path(c, g, tree, module_index, argument_index) {
                    var wanted = 0usize
                    while true {
                        let (pointed, found) = dynamic_alias_candidate(c, g, tree, module_index, argument_index, wanted)
                        if !found { break }
                        lend_thread_storage(c, local_index, pointed, usize(statement.token_start))
                        wanted += 1usize
                    }
                } else {
                    // Prefer the lexical alias: `&ctx.target.hits` names the storage
                    // behind `ctx.target`, not the aggregate carrying that pointer.
                    var (pointed, is_address) = alias_target(c, g, tree, module_index, argument_index)
                    // Starting through a pointer alias lends the aliased storage just
                    // as spelling `&x` at the call does (D674, D686).
                    if !is_address { (pointed, is_address) = address_argument_local(c, g, tree, module_index, argument_index) }
                    // What the thread was given is its until the join (D365): the
                    // parent neither reads nor writes it, except through an address.
                    if is_address { lend_thread_storage(c, local_index, pointed, usize(statement.token_start)) }
                }
                argument_at += 1usize
            }
        }
        if producer_borrowed(c, call.function) {
            c.resources[local_index].state = resource_owned
            c.resources[local_index].obligated = false
            c.resources[local_index].borrowed = true
            c.resources[local_index].view = true
            try resource_init_fields(c, local_index, resource_owned)
            resource_disown_fields(c, local_index)
            ret ok
        }
        c.resources[local_index].state = resource_owned
        if !tried && has_err_local {
            c.resources[local_index].state = resource_unchecked
            c.resources[local_index].bound_err = err_local
            c.resources[local_index].has_bound_err = true
        }
        // A struct that came back from a call is affine, but what its fields hold
        // is the callee's business unless the type names its cleanup: a `Sink` over
        // the standard streams owes nothing, a writer over a file it opened says so
        // by being a `resource(close)`.
        try resource_init_fields(c, local_index, resource_owned)
        resource_disown_fields(c, local_index)
        ret ok
    }
    // Not a call: another local, moved; or an expression that made a value (an
    // aggregate literal moving its fields), owned.
    let initializer = tree.nodes[initializer_index]
    if initializer.kind == .NameExpr {
        let (source_index, source_is_resource) = resource_local_of(c, g, tree, module_index, initializer_index)
        if source_is_resource && c.resources[source_index].state == resource_unchecked {
            // Moved before its error was tested: the state and the error come along.
            c.resources[local_index].state = resource_unchecked
            c.resources[local_index].bound_err = c.resources[source_index].bound_err
            c.resources[local_index].has_bound_err = c.resources[source_index].has_bound_err
            try resource_copy_fields(c, local_index, source_index)
            c.resources[source_index].state = resource_moved
            resource_set_fields(c, source_index, resource_moved)
            record_explain_move(c, module_index, initializer, c.locals[source_index].name)
            ret ok
        }
        // The fields come across as they stood, before the source is moved whole.
        if source_is_resource { try resource_copy_fields(c, local_index, source_index) }
        c.consuming_binding = true
        let bound = resource_consume(c, g, tree, module_index, initializer_index)
        c.consuming_binding = false
        if bound != ok { ret bound }
        c.resources[local_index].state = resource_owned
        if source_is_resource {
            if !c.resources[source_index].obligated { c.resources[local_index].obligated = false }
            if c.resources[source_index].borrowed { c.resources[local_index].borrowed = true }
            if c.resources[source_index].view { c.resources[local_index].view = true }
            if c.resources[source_index].frame_borrow != 0usize { c.resources[local_index].frame_borrow = c.resources[source_index].frame_borrow }
        }
        if !source_is_resource { try resource_init_fields(c, local_index, resource_owned) }
        ret ok
    }
    if initializer.kind == .FieldExpr {
        // A field moved out into its own binding, or a view of something untracked.
        let (source_index, source_at, is_field) = resource_field_of(c, g, tree, module_index, initializer_index)
        if is_field {
            try resource_consume(c, g, tree, module_index, initializer_index)
            c.resources[local_index].state = resource_owned
            // A field of a borrowed struct is as borrowed as the struct.
            if c.resources[source_index].borrowed {
                c.resources[local_index].borrowed = true
                c.resources[local_index].obligated = false
            }
            ret resource_init_fields(c, local_index, resource_owned)
        }
        c.resources[local_index].state = resource_owned
        c.resources[local_index].obligated = false
        c.resources[local_index].view = true
        try resource_init_fields(c, local_index, resource_owned)
        resource_disown_fields(c, local_index)
        ret ok
    }
    if initializer.kind == .BracketPostfix {
        let (source_index, source_first, source_end, is_element) = resource_element_candidates(c, g, tree, module_index, initializer_index)
        if is_element {
            var source_at = source_first
            var owed = false
            while source_at < source_end {
                if field_owed(c.resources[source_index].fields[source_at]) { owed = true }
                source_at += 1usize
            }
            try resource_consume(c, g, tree, module_index, initializer_index)
            c.resources[local_index].state = resource_owned
            c.resources[local_index].obligated = owed
            if c.resources[source_index].borrowed {
                c.resources[local_index].borrowed = true
                c.resources[local_index].obligated = false
            }
            ret resource_init_fields(c, local_index, resource_owned)
        }
        c.resources[local_index].state = resource_owned
        c.resources[local_index].obligated = false
        c.resources[local_index].view = true
        try resource_init_fields(c, local_index, resource_owned)
        resource_disown_fields(c, local_index)
        ret ok
    }
    try resource_literal_moves(c, g, tree, module_index, initializer_index)
    c.resources[local_index].state = resource_owned
    try resource_init_fields(c, local_index, resource_owned)
    resource_literal_owed(c, g, tree, module_index, local_index, initializer_index)
    ret ok
}

// What a literal's fields owe: a field given a local that owed nothing, a literal of
// bits, or a borrowed producer's handle owes nothing itself.
fn resource_literal_owed(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, local_index: usize, literal_index: usize) {
    let literal = tree.nodes[literal_index]
    if literal.kind != .AggregateLiteral || c.resources[local_index].fields.len == 0usize { ret }
    let text = g.modules[module_index].text
    let end = usize(literal.first_child) + usize(literal.child_count)
    var at = usize(literal.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) {
            let item_index = parse.child_index_at(tree, at)
            let item = tree.nodes[item_index]
            if item.kind == .LiteralItem {
                let name_token = c.tokens[usize(item.token_start)]
                let (value_index, has_value) = first_node_child(tree, item)
                if name_token.kind == .Identifier && has_value {
                    let (field_index, found) = find_aggregate_field(c, c.locals[local_index].ty, text[name_token.start..name_token.end])
                    let first = resource_field_global(c, local_index, 0usize)
                    if found && field_index >= first && field_index - first < c.resources[local_index].fields.len {
                        let field_at = field_index - first
                        let byte = c.resources[local_index].fields[field_at]
                        if byte != 0u8 {
                            var owed = field_owed(byte)
                            let value = tree.nodes[value_index]
                            if value.kind == .AggregateLiteral { owed = false }
                            if value.kind == .NameExpr {
                                let value_token = c.tokens[usize(value.token_start)]
                                if value_token.kind == .Identifier {
                                    let (source, source_found) = find_local(c, text[value_token.start..value_token.end])
                                    if source_found && c.resources[source].state != resource_plain && !c.resources[source].obligated { owed = false }
                                }
                            }
                            if value.kind == .CallExpr {
                                let (info, info_error) = check_call(c, g, tree, module_index, value)
                                if info_error == ok && (producer_borrowed(c, info.function) || !resource_type(c, c.aggregate_fields[field_index].ty)) { owed = false }
                            }
                            c.resources[local_index].fields[field_at] = field_with(field_state(byte), owed)
                        }
                    }
                }
            }
        }
        at += 1usize
    }
}

// A view -- of a field, an element, a borrowed producer -- owes nothing, field by field.
fn resource_disown_fields(c: *Checker, local_index: usize) {
    var at = 0usize
    while at < c.resources[local_index].fields.len {
        let b = c.resources[local_index].fields[at]
        if b != 0u8 { c.resources[local_index].fields[at] = field_state(b) }
        at += 1usize
    }
}

// A value that names a resource local outright is moved by what takes it -- a
// binding, a `ret`, a store into a field or an element. One named inside an
// aggregate literal is not, in this step: aggregates are not tracked yet.
fn resource_move_literal_fields(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr || node.kind == .FieldExpr { ret resource_consume(c, g, tree, module_index, node_index) }
    ret ok
}

// Every obligation still live among the locals from `from` up is reported at the
// exit `node`; a reserved one is discharged by its `defer` at that exit.
fn resource_audit(c: *Checker, g: *graph.Graph, module_index: usize, node: syntax.Node, from: usize, exit_kind: DiagnosticKind) -> err {
    if !any_affine_local(c) { ret ok }
    var at = from
    while at < c.local_count {
        let local = c.resources[at]
        let live = local.state == resource_owned || local.state == resource_maybe || local.state == resource_unchecked
        if local.fields.len != 0usize {
            // A struct owes what its owed fields still hold, while it is here itself.
            if live {
                var field_at = 0usize
                while field_at < local.fields.len {
                    let b = local.fields[field_at]
                    let one = field_state(b)
                    if field_owed(b) && (one == resource_owned || one == resource_maybe || one == resource_unchecked) {
                        let acquired = resource_part_acquired(c, at, field_at)
                        record_failure_related(c, module_index, node, exit_kind, resource_field_name(c, at, field_at), line_detail(c, g, module_index, acquired), acquired)
                        ret ResourceViolation
                    }
                    field_at += 1usize
                }
            }
        } else {
            if local.obligated && live {
                record_failure_related(c, module_index, node, exit_kind, c.locals[at].name, line_detail(c, g, module_index, local.acquired), local.acquired)
                if exit_kind == .ResourceCleanupForgotten { resource_fix_defer(c, g, module_index, at) }
                ret ResourceViolation
            }
        }
        at += 1usize
    }
    ret ok
}

// The fix for a forgotten cleanup (D381, H09): `defer <closer>(x)` on its own line
// after the acquiring statement, indented as that line is. The closer is the type's
// declared cleanup, qualified as this module imports its module, or the seeded
// closer of an `os` handle; a type with neither gets no fix.
fn resource_fix_defer(c: *Checker, g: *graph.Graph, module_index: usize, local_index: usize) {
    c.failure_fix_text = ""
    let ty = c.locals[local_index].ty
    if ty.kind != .Named { ret }
    var closer = ""
    let (aggregate_index, has_aggregate) = find_aggregate(c, ty.module_index, ty.name)
    if has_aggregate && c.aggregates[aggregate_index].cleanup.len != 0usize { closer = c.aggregates[aggregate_index].cleanup }
    if closer.len == 0usize && module_is_os(c, ty.module_index) {
        if same(ty.name, "File") { closer = "close" }
        if same(ty.name, "Process") { closer = "wait" }
        if same(ty.name, "Thread") { closer = "thread_join" }
    }
    if closer.len == 0usize { ret }
    var qualifier = ""
    if ty.module_index != module_index {
        var import_at = g.modules[module_index].first_import
        let import_end = import_at + g.modules[module_index].import_count
        while import_at < import_end {
            if g.imports[import_at].target == ty.module_index { qualifier = g.imports[import_at].qualifier }
            import_at += 1usize
        }
        if qualifier.len == 0usize { ret }
    }
    // The acquiring line: its indentation, and the newline that ends it.
    let text = g.modules[module_index].text
    let acquired = c.tokens[c.resources[local_index].acquired]
    var line_start = acquired.start
    while line_start > 0usize && text[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
    var indent = 0usize
    while line_start + indent < text.len && (text[line_start + indent] == 32u8 || text[line_start + indent] == 9u8) { indent += 1usize }
    var line_end = acquired.end
    while line_end < text.len && text[line_end] != 10u8 { line_end += 1usize }
    var pieces: [8]str = zero
    pieces[0usize] = "defer "
    pieces[1usize] = qualifier
    if qualifier.len != 0usize { pieces[2usize] = "." }
    pieces[3usize] = closer
    pieces[4usize] = "("
    pieces[5usize] = c.locals[local_index].name
    pieces[6usize] = ")"
    resource_fix_line(c, text, line_start, indent, line_end, pieces[..])
    c.failure_fix_kind = 1u8
}

// The fix for an untested acquisition (D382, H09): `if e != ok { ret e }` after the
// acquiring statement, when it was returned beside an `err` and the function
// returns a bare `err`; a flag, or another result shape, gets no fix.
fn resource_fix_test(c: *Checker, g: *graph.Graph, module_index: usize, local_index: usize) {
    c.failure_fix_text = ""
    if !c.resources[local_index].has_bound_err || !c.body_returns_err { ret }
    let err_local = c.resources[local_index].bound_err
    if err_local >= c.local_count || c.locals[err_local].ty.kind != .Err { ret }
    let text = g.modules[module_index].text
    let acquired = c.tokens[c.resources[local_index].acquired]
    var line_start = acquired.start
    while line_start > 0usize && text[line_start - 1usize] != 10u8 { line_start = line_start - 1usize }
    var indent = 0usize
    while line_start + indent < text.len && (text[line_start + indent] == 32u8 || text[line_start + indent] == 9u8) { indent += 1usize }
    var line_end = acquired.end
    while line_end < text.len && text[line_end] != 10u8 { line_end += 1usize }
    var pieces: [8]str = zero
    pieces[0usize] = "if "
    pieces[1usize] = c.locals[err_local].name
    pieces[2usize] = " != ok { ret "
    pieces[3usize] = c.locals[err_local].name
    pieces[4usize] = " }"
    resource_fix_line(c, text, line_start, indent, line_end, pieces[..])
    c.failure_fix_kind = 2u8
}

// A fix that is one inserted line: a newline, the acquiring line's indentation, the
// pieces; inserted at the end of that line.
fn resource_fix_line(c: *Checker, text: str, line_start: usize, indent: usize, line_end: usize, pieces: []str) {
    var total = indent + 1usize
    var piece = 0usize
    while piece < pieces.len {
        total += pieces[piece].len
        piece += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](c.arena, total)
    if buffer_error != ok { ret }
    var at = 0usize
    buffer[at] = 10u8
    at += 1usize
    var pad = 0usize
    while pad < indent {
        buffer[at] = text[line_start + pad]
        at += 1usize
        pad += 1usize
    }
    piece = 0usize
    while piece < pieces.len {
        at = fix_append(buffer, at, pieces[piece])
        piece += 1usize
    }
    c.failure_fix_text = buffer[0usize..at]
    c.failure_fix_at = line_end
}

fn fix_append(buffer: []u8, at: usize, piece: str) -> usize {
    var i = 0usize
    while i < piece.len {
        buffer[at + i] = piece[i]
        i += 1usize
    }
    ret at + piece.len
}

// The states of the locals below `count`, kept for a join.
// The states of the locals below `count` and of their fields, in one run: a local's
// byte, then its fields' bytes.
fn resource_snapshot(c: *Checker, count: usize) -> ([]u8, err) {
    var size = 0usize
    var at = 0usize
    while at < count {
        size += 1usize + c.resources[at].fields.len
        at += 1usize
    }
    let (states, states_error) = mem.alloc[u8](c.arena, size + 1usize)
    if states_error != ok { ret (states, states_error) }
    var out = 0usize
    at = 0usize
    while at < count {
        states[out] = c.resources[at].state
        out += 1usize
        var field_at = 0usize
        while field_at < c.resources[at].fields.len {
            states[out] = c.resources[at].fields[field_at]
            out += 1usize
            field_at += 1usize
        }
        at += 1usize
    }
    ret (states[0usize..size], ok)
}

fn resource_restore(c: *Checker, states: []const u8) {
    var at = 0usize
    var cursor = 0usize
    while at < c.local_count && cursor < states.len {
        c.resources[at].state = states[cursor]
        cursor += 1usize
        var field_at = 0usize
        while field_at < c.resources[at].fields.len && cursor < states.len {
            c.resources[at].fields[field_at] = states[cursor]
            cursor += 1usize
            field_at += 1usize
        }
        at += 1usize
    }
}

// The join of two arms: the same state stays; anything else is Maybe, which no later
// use or exit accepts, since one path moved the value and the other did not.
// Two arms' states joined into the first.
// Two flat snapshots joined into the first: the same layout, since both were taken
// over the same locals; a local's byte joins as a state, a field's as a field.
fn resource_join_states(c: *Checker, into: []u8, other: []const u8) {
    var at = 0usize
    var cursor = 0usize
    while at < c.local_count && cursor < into.len && cursor < other.len {
        into[cursor] = resource_join_one(into[cursor], other[cursor])
        cursor += 1usize
        var field_at = 0usize
        while field_at < c.resources[at].fields.len && cursor < into.len && cursor < other.len {
            into[cursor] = resource_join_field(into[cursor], other[cursor])
            cursor += 1usize
            field_at += 1usize
        }
        at += 1usize
    }
}

// The same state stays; nothing owned on either path -- moved, or null -- is moved;
// anything else is Maybe, which no later use or exit accepts.
fn resource_join_one(a: u8, b: u8) -> u8 {
    // Plain is untracked: the other path's answer stands (a view made on one arm).
    if a == b || a == resource_plain { ret a }
    if b == resource_plain { ret b }
    let a_gone = a == resource_moved || a == resource_null
    let b_gone = b == resource_moved || b == resource_null
    if a_gone && b_gone { ret resource_moved }
    // Unchecked on one path and null on the other is still the error's to decide.
    if a == resource_unchecked && b == resource_null { ret a }
    if b == resource_unchecked && a == resource_null { ret b }
    ret resource_maybe
}

fn resource_join(c: *Checker, other: []const u8) {
    var at = 0usize
    var cursor = 0usize
    while at < c.local_count && cursor < other.len {
        c.resources[at].state = resource_join_one(c.resources[at].state, other[cursor])
        cursor += 1usize
        var field_at = 0usize
        while field_at < c.resources[at].fields.len && cursor < other.len {
            c.resources[at].fields[field_at] = resource_join_field(c.resources[at].fields[field_at], other[cursor])
            cursor += 1usize
            field_at += 1usize
        }
        at += 1usize
    }
}

fn resource_join_field(a: u8, b: u8) -> u8 {
    if a == 0u8 || b == 0u8 { ret a }
    ret field_with(resource_join_one(field_state(a), field_state(b)), field_owed(a) || field_owed(b))
}

// After a loop's body: an outer local it consumed would be used moved by the next
// iteration, unless the body owned it again before the end.
fn resource_loop_check(c: *Checker, g: *graph.Graph, module_index: usize, node: syntax.Node, before: []const u8) -> err {
    var at = 0usize
    var cursor = 0usize
    while at < c.local_count && cursor < before.len {
        // A view invalidated in the body is not consumed: its next use is the error.
        if c.resources[at].state != before[cursor] && before[cursor] == resource_owned && c.resources[at].dangling == 0u8 {
            let swept = c.loop_depth < c.resource_loop_swept_local.len && c.resource_loop_swept_local[c.loop_depth] == at + 1usize && c.resources[at].state == resource_moved
            if !swept {
                record_failure_related(c, module_index, node, .ResourceMovedInLoop, c.locals[at].name, line_detail(c, g, module_index, c.resources[at].acquired), c.resources[at].acquired)
                ret ResourceViolation
            }
        }
        cursor += 1usize
        var field_at = 0usize
        while field_at < c.resources[at].fields.len && cursor < before.len {
            if c.resources[at].fields[field_at] != before[cursor] && field_state(before[cursor]) == resource_owned {
                let swept = c.loop_depth < c.resource_loop_swept_local.len && c.resource_loop_swept_local[c.loop_depth] == at + 1usize && field_state(c.resources[at].fields[field_at]) == resource_moved
                if !swept {
                    let acquired = resource_part_acquired(c, at, field_at)
                    record_failure_related(c, module_index, node, .ResourceMovedInLoop, resource_field_name(c, at, field_at), line_detail(c, g, module_index, acquired), acquired)
                    ret ResourceViolation
                }
            }
            cursor += 1usize
            field_at += 1usize
        }
        at += 1usize
    }
    ret ok
}

// A condition over an `err` local: which, and its local. 0: neither; 1: `e != ok`;
// 2: `e == ok`; 3: `e == Error`; 4: `e != Error`, for one particular error.
fn resource_err_test(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, condition_index: usize) -> (usize, usize) {
    var condition = tree.nodes[condition_index]
    // `found` reads as `e == ok`, `!found` as `e != ok` (D353).
    var flag_which = 2usize
    if condition.kind == .UnaryExpr && c.tokens[usize(condition.token_start)].kind == .PunctBang {
        let (inner_index, has_inner) = first_node_child(tree, condition)
        if !has_inner { ret (0usize, 0usize) }
        condition = tree.nodes[inner_index]
        flag_which = 1usize
    }
    if condition.kind == .NameExpr {
        let flag_token = c.tokens[usize(condition.token_start)]
        let (flag_index, flag_found) = find_local(c, g.modules[module_index].text[flag_token.start..flag_token.end])
        if !flag_found || c.locals[flag_index].ty.kind != .Bool { ret (0usize, 0usize) }
        ret (flag_which, flag_index)
    }
    if condition.kind != .BinaryExpr { ret (0usize, 0usize) }
    let (left_index, has_left) = first_node_child(tree, condition)
    if !has_left { ret (0usize, 0usize) }
    let left = tree.nodes[left_index]
    if left.kind != .NameExpr { ret (0usize, 0usize) }
    var which = 0usize
    var against_ok = false
    var scan = usize(left.token_end)
    while scan < usize(condition.token_end) {
        if c.tokens[scan].kind == .PunctBangEq { which = 1usize }
        if c.tokens[scan].kind == .PunctEqEq { which = 2usize }
        if c.tokens[scan].kind == .KwOk { against_ok = true }
        scan += 1usize
    }
    if which == 0usize { ret (0usize, 0usize) }
    if !against_ok {
        if which == 2usize { which = 3usize } else { which = 4usize }
    }
    let token = c.tokens[usize(left.token_start)]
    let name = g.modules[module_index].text[token.start..token.end]
    let (err_index, found) = find_local(c, name)
    if !found || c.locals[err_index].ty.kind != .Err { ret (0usize, 0usize) }
    ret (which, err_index)
}

fn resource_set_bound(c: *Checker, err_index: usize, state: u8) {
    var at = 0usize
    while at < c.local_count {
        if c.resources[at].state == resource_unchecked && c.resources[at].has_bound_err && c.resources[at].bound_err == err_index {
            c.resources[at].state = state
            resource_set_fields(c, at, state)
        }
        at += 1usize
    }
}

// `if e != ok { <diverges> }`: the resources bound beside `e` are owned past the if.
fn resource_narrow(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, condition_index: usize) {
    let (which, err_index) = resource_err_test(c, g, tree, module_index, condition_index)
    // `!= ok` diverged: ok here, owned. `== ok` diverged: an error here, null.
    // `!= Error` diverged: that error here, null. `== Error` diverged: unknown still.
    if which == 1usize { resource_set_bound(c, err_index, resource_owned) }
    if which == 2usize || which == 4usize { resource_set_bound(c, err_index, resource_null) }
}

// Inside an arm of `if e == ok` / `if e != ok`: owned in the arm the error is ok in,
// null in the other.
fn resource_narrow_arm(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, condition_index: usize, arm: usize) {
    let (which, err_index) = resource_err_test(c, g, tree, module_index, condition_index)
    if which == 0usize { ret }
    if which <= 2usize {
        var owned_arm = 1usize
        if which == 2usize { owned_arm = 0usize }
        if arm == owned_arm { resource_set_bound(c, err_index, resource_owned) } else { resource_set_bound(c, err_index, resource_null) }
        ret
    }
    // Against one particular error: null where it is that error, unknown elsewhere.
    var null_arm = 0usize
    if which == 4usize { null_arm = 1usize }
    if arm == null_arm { resource_set_bound(c, err_index, resource_null) }
}

// An assignment: a place that is an owned resource cannot be overwritten; a place
// that is a resource local is bound again as a `let` binds; a right-hand side that
// names a resource local moves it, wherever it goes.
fn resource_assign(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, statement: syntax.Node, place_index: usize, initializer_index: usize, from_call: bool, call: CallInfo, tried: bool) -> err {
    // `p = &y`, `s = x[..]`, `t = other` (D416): the local's alias is what it is
    // assigned, or nothing; an alias it held ends.
    let place = tree.nodes[place_index]
    if place.kind == .NameExpr && c.tokens[usize(place.token_start)].kind == .Identifier {
        let place_token = c.tokens[usize(place.token_start)]
        let (assigned_local, found_assigned) = find_local(c, g.modules[module_index].text[place_token.start..place_token.end])
        if found_assigned { try record_alias(c, g, tree, module_index, assigned_local, initializer_index, true) }
    }
    // `s.p = &x` or `items[i] = &x`: the carrier aliases `x` through that
    // complete comptime field/element path from here (D413, D704, D709).
    if place.kind == .FieldExpr || place.kind == .BracketPostfix {
        var fields: [128]str = zero
        let (struct_local, field_count, found_struct) = local_field_path(c, g, tree, module_index, place_index, fields[0usize..fields.len])
        if found_struct && field_count != 0usize && (c.locals[struct_local].ty.kind == .Named || c.locals[struct_local].ty.kind == .Array) {
            // `local_field_path` reads the syntax from leaf to base; stored paths run
            // from the carrier outward.
            var left = 0usize
            while left < field_count / 2usize {
                let right = field_count - left - 1usize
                let held = fields[left]
                fields[left] = fields[right]
                fields[right] = held
                left += 1usize
            }
            var (pointed, is_address) = address_argument_local(c, g, tree, module_index, initializer_index)
            if !is_address { (pointed, is_address) = alias_target(c, g, tree, module_index, initializer_index) }
            if !is_address {
                let (source, is_place) = place_base_local(c, g, tree, module_index, initializer_index)
                if is_place && holds_pointer(c, c.locals[source].ty, 0usize) {
                    pointed = source
                    is_address = true
                }
            }
            if is_address && pointed != struct_local {
                try set_resource_path_alias(c, struct_local, fields[0usize..field_count], pointed)
            }
            if !is_address && tree.nodes[initializer_index].kind == .AggregateLiteral {
                try record_literal_alias_paths(c, g, tree, module_index, struct_local, initializer_index, fields[0usize..fields.len], field_count)
            }
        }
    }
    if !any_affine_local(c) { ret ok }
    // The local the place is in, for a thread over this frame (D357): a store into
    // storage declared after what the thread reads is a store that dies first.
    c.consuming_store = 0usize
    var place_base = place_index
    while tree.nodes[place_base].kind == .FieldExpr || tree.nodes[place_base].kind == .BracketPostfix {
        let (inner_index, has_inner) = first_node_child(tree, tree.nodes[place_base])
        if !has_inner { break }
        place_base = inner_index
    }
    if place_base != place_index && tree.nodes[place_base].kind == .NameExpr {
        let base_token = c.tokens[usize(tree.nodes[place_base].token_start)]
        if base_token.kind == .Identifier {
            let (base_local, base_found) = find_local(c, g.modules[module_index].text[base_token.start..base_token.end])
            if base_found && c.locals[base_local].ty.kind != .Pointer { c.consuming_store = base_local + 1usize }
        }
    }
    // Storage lent to a running thread is not written (D365): the place's local.
    var lent_local = c.consuming_store
    if lent_local == 0usize && tree.nodes[place_index].kind == .NameExpr {
        let (place_local, is_place_local) = resource_local_of(c, g, tree, module_index, place_index)
        if is_place_local { lent_local = place_local + 1usize }
    }
    if lent_local != 0usize && c.resources[lent_local - 1usize].lent_to != 0usize {
        record_failure_related(c, module_index, statement, .ThreadShared, c.locals[lent_local - 1usize].name, line_detail(c, g, module_index, c.resources[lent_local - 1usize].lent_at), c.resources[lent_local - 1usize].lent_at)
        c.consuming_store = 0usize
        ret ResourceViolation
    }
    // A store through a pointer bound from `&x` while `x` is lent (D393), or after
    // `x` was taken away by a reset or a container's change (D394).
    let (aliased, through_alias) = alias_of_lent(c, g, tree, module_index, place_index)
    if through_alias {
        record_failure_related(c, module_index, statement, .ThreadShared, c.locals[aliased].name, line_detail(c, g, module_index, c.resources[aliased].lent_at), c.resources[aliased].lent_at)
        c.consuming_store = 0usize
        ret ResourceViolation
    }
    let (gone, through_gone) = alias_of_dangling(c, g, tree, module_index, place_index)
    if through_gone {
        record_failure_related(c, module_index, statement, dangling_kind(c, gone), c.locals[gone].name, line_detail(c, g, module_index, c.resources[gone].acquired), c.resources[gone].acquired)
        c.consuming_store = 0usize
        ret ResourceViolation
    }
    let assigned = resource_assign_inner(c, g, tree, module_index, statement, place_index, initializer_index, from_call, call, tried)
    c.consuming_store = 0usize
    ret assigned
}

fn resource_assign_inner(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, statement: syntax.Node, place_index: usize, initializer_index: usize, from_call: bool, call: CallInfo, tried: bool) -> err {
    let (candidate_local, candidate_first, candidate_end, has_candidates) = resource_element_candidates(c, g, tree, module_index, place_index)
    if has_candidates && candidate_end != candidate_first + 1usize {
        var candidate_at = candidate_first
        while candidate_at < candidate_end {
            let old = c.resources[candidate_local].fields[candidate_at]
            let old_state = field_state(old)
            if old_state == resource_reserved || ((old_state == resource_owned || old_state == resource_maybe || old_state == resource_unchecked) && field_owed(old)) {
                let acquired = resource_part_acquired(c, candidate_local, candidate_at)
                record_failure_related(c, module_index, statement, .ResourceOverwrite, resource_field_name(c, candidate_local, candidate_at), line_detail(c, g, module_index, acquired), acquired)
                ret ResourceViolation
            }
            candidate_at += 1usize
        }
        let candidate_element = c.types[c.locals[candidate_local].ty.element]
        var owed = affine_kind(c, candidate_element, 0usize) == 2u8
        // Worker arrays are commonly discharged by a helper over a slice. Until
        // owned resource-slice summaries exist, retain D616's view behavior for
        // this one seeded boundary instead of inventing an obligation the caller
        // has no way to prove discharged.
        if candidate_element.kind == .Named && module_is_os(c, candidate_element.module_index) && same(candidate_element.name, "Thread") { owed = false }
        let initializer_node = tree.nodes[initializer_index]
        if contains_token(c, usize(statement.token_start), usize(statement.token_end), .KwZero) && initializer_node.kind != .CallExpr { owed = false }
        if initializer_node.kind == .BracketPostfix {
            owed = false
            let (source_local, source_first, source_end, source_is_element) = resource_element_candidates(c, g, tree, module_index, initializer_index)
            if source_is_element {
                var source_at = source_first
                while source_at < source_end {
                    if field_owed(c.resources[source_local].fields[source_at]) { owed = true }
                    source_at += 1usize
                }
                try resource_consume(c, g, tree, module_index, initializer_index)
            }
        } else {
            if initializer_node.kind == .NameExpr {
                let (source_local, source_is_resource) = resource_local_of(c, g, tree, module_index, initializer_index)
                if source_is_resource && !c.resources[source_local].obligated && c.resources[source_local].fields.len == 0usize { owed = false }
            }
            if !from_call { try resource_move_literal_fields(c, g, tree, module_index, initializer_index) }
        }
        var producer = call
        var from_producer = from_call
        if !from_call && initializer_node.kind == .CallExpr {
            let (info, info_error) = check_call(c, g, tree, module_index, initializer_node)
            if info_error == ok {
                producer = info
                from_producer = true
            }
        }
        if from_producer && producer_borrowed(c, producer.function) { owed = false }
        var next_state = resource_owned
        if owed { next_state = resource_maybe }
        if resource_element_is_swept(c, g, tree, module_index, place_index, candidate_first, candidate_end) { next_state = resource_owned }
        candidate_at = candidate_first
        while candidate_at < candidate_end {
            c.resources[candidate_local].fields[candidate_at] = field_with(next_state, owed)
            c.resources[candidate_local].elements_acquired[candidate_at] = usize(statement.token_start)
            candidate_at += 1usize
        }
        c.resources[candidate_local].state = resource_owned
        c.resources[candidate_local].acquired = usize(statement.token_start)
        ret ok
    }
    let (element_local, element_at, is_element) = resource_element_of(c, g, tree, module_index, place_index)
    if is_element {
        let old = c.resources[element_local].fields[element_at]
        let old_state = field_state(old)
        if old_state == resource_reserved || ((old_state == resource_owned || old_state == resource_maybe || old_state == resource_unchecked) && field_owed(old)) {
            let acquired = resource_part_acquired(c, element_local, element_at)
            record_failure_related(c, module_index, statement, .ResourceOverwrite, resource_field_name(c, element_local, element_at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        if contains_token(c, usize(statement.token_start), usize(statement.token_end), .KwZero) && tree.nodes[initializer_index].kind != .CallExpr {
            c.resources[element_local].fields[element_at] = field_with(resource_null, false)
            ret ok
        }
        let element_type = c.types[c.locals[element_local].ty.element]
        var owed = affine_kind(c, element_type, 0usize) == 2u8
        let initializer_node = tree.nodes[initializer_index]
        if initializer_node.kind == .BracketPostfix {
            owed = false
            let (source_local, source_at, source_is_element) = resource_element_of(c, g, tree, module_index, initializer_index)
            if source_is_element {
                owed = field_owed(c.resources[source_local].fields[source_at])
                try resource_consume(c, g, tree, module_index, initializer_index)
            }
        } else {
            if initializer_node.kind == .NameExpr {
                let (source_local, source_is_resource) = resource_local_of(c, g, tree, module_index, initializer_index)
                if source_is_resource && !c.resources[source_local].obligated && c.resources[source_local].fields.len == 0usize { owed = false }
            }
            if !from_call { try resource_move_literal_fields(c, g, tree, module_index, initializer_index) }
        }
        var producer = call
        var from_producer = from_call
        if !from_call && initializer_node.kind == .CallExpr {
            let (info, info_error) = check_call(c, g, tree, module_index, initializer_node)
            if info_error == ok {
                producer = info
                from_producer = true
            }
        }
        if from_producer && producer_borrowed(c, producer.function) { owed = false }
        c.resources[element_local].fields[element_at] = field_with(resource_owned, owed)
        c.resources[element_local].state = resource_owned
        c.resources[element_local].acquired = usize(statement.token_start)
        c.resources[element_local].elements_acquired[element_at] = usize(statement.token_start)
        ret ok
    }
    let (field_local, field_at, is_field) = resource_field_of(c, g, tree, module_index, place_index)
    if is_field {
        // A store into a tracked struct's field: the field's old value cannot be owed.
        let old = c.resources[field_local].fields[field_at]
        let old_state = field_state(old)
        if old_state == resource_reserved || ((old_state == resource_owned || old_state == resource_maybe || old_state == resource_unchecked) && field_owed(old)) {
            record_failure_related(c, module_index, statement, .ResourceOverwrite, resource_field_name(c, field_local, field_at), line_detail(c, g, module_index, c.resources[field_local].acquired), c.resources[field_local].acquired)
            ret ResourceViolation
        }
        let field_type = c.aggregate_fields[resource_field_global(c, field_local, field_at)].ty
        var owed = affine_kind(c, field_type, 0usize) == 2u8
        // A struct that came back from a call owes nothing by containment (as a local
        // bound from one); a resource itself does.
        if !resource_type(c, field_type) && tree.nodes[initializer_index].kind == .CallExpr { owed = false }
        // A field or element read: a view, unless it is an owed field of a tracked
        // struct, which the store moves.
        let initializer_node = tree.nodes[initializer_index]
        if initializer_node.kind == .FieldExpr || initializer_node.kind == .BracketPostfix {
            owed = false
            let (source_local, source_at, source_is_field) = resource_field_of(c, g, tree, module_index, initializer_index)
            if source_is_field && field_owed(c.resources[source_local].fields[source_at]) { owed = true }
        }
        if initializer_node.kind == .NameExpr {
            let (source_local, source_is_resource) = resource_local_of(c, g, tree, module_index, initializer_index)
            if source_is_resource && !c.resources[source_local].obligated && c.resources[source_local].fields.len == 0usize { owed = false }
        }
        var producer = call
        var from_producer = from_call
        if !from_call && tree.nodes[initializer_index].kind == .CallExpr {
            // `s.file = os.stdout()` through the plain assignment path: the call again,
            // cached, to know its producer.
            let (info, info_error) = check_call(c, g, tree, module_index, tree.nodes[initializer_index])
            if info_error == ok {
                producer = info
                from_producer = true
            }
        }
        if from_producer && producer_borrowed(c, producer.function) { owed = false }
        if contains_token(c, usize(statement.token_start), usize(statement.token_end), .KwZero) && tree.nodes[initializer_index].kind != .CallExpr {
            c.resources[field_local].fields[field_at] = field_with(resource_null, false)
            ret ok
        }
        if !from_call { try resource_move_literal_fields(c, g, tree, module_index, initializer_index) }
        c.resources[field_local].fields[field_at] = field_with(resource_owned, owed)
        if c.resources[field_local].state == resource_null { c.resources[field_local].state = resource_owned }
        c.resources[field_local].acquired = usize(statement.token_start)
        ret ok
    }
    let (local_index, is_resource) = resource_local_of(c, g, tree, module_index, place_index)
    // A store into a field of something untracked, or an element, moves the value
    // into the aggregate, which owns it from then on.
    if !is_resource {
        if !from_call {
            resource_err_copied(c, g, tree, module_index, place_index, initializer_index)
            try resource_move_literal_fields(c, g, tree, module_index, initializer_index)
        }
        ret ok
    }
    let state = c.resources[local_index].state
    if state == resource_owned || state == resource_reserved || state == resource_unchecked || state == resource_maybe {
        if c.resources[local_index].obligated || state == resource_reserved {
            record_failure_related(c, module_index, statement, .ResourceOverwrite, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
            ret ResourceViolation
        }
    }
    ret resource_bind_local(c, g, tree, module_index, local_index, statement, initializer_index, true, from_call, call, tried, 0usize, false)
}

// `open_error = retry_error`: the resources bound beside the source error are bound
// beside the destination from here on, so a test of it narrows them.
fn resource_err_copied(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, place_index: usize, initializer_index: usize) {
    let place = tree.nodes[place_index]
    let initializer = tree.nodes[initializer_index]
    if place.kind != .NameExpr || initializer.kind != .NameExpr { ret }
    let text = g.modules[module_index].text
    let place_token = c.tokens[usize(place.token_start)]
    let source_token = c.tokens[usize(initializer.token_start)]
    if place_token.kind != .Identifier || source_token.kind != .Identifier { ret }
    let (dest, dest_found) = find_local(c, text[place_token.start..place_token.end])
    let (source, source_found) = find_local(c, text[source_token.start..source_token.end])
    if !dest_found || !source_found || c.locals[dest].ty.kind != c.locals[source].ty.kind || (c.locals[dest].ty.kind != .Err && c.locals[dest].ty.kind != .Bool) { ret }
    var at = 0usize
    while at < c.local_count {
        if c.resources[at].has_bound_err && c.resources[at].bound_err == source { c.resources[at].bound_err = dest }
        at += 1usize
    }
}

// Whether a statement leaves the function for good: it returns (the checker's rule
// for `ret`, `try` and the arms that all do), or it ends in `os.exit` or
// `unreachable`, after which nothing is owed. A block ending so is not audited.
fn resource_diverges(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> bool {
    if statement_returns(c, tree, module_index, node) { ret true }
    var last = node
    if node.kind == .Block || node.kind == .SwitchArm {
        var found = false
        let end = usize(node.first_child) + usize(node.child_count)
        var at = usize(node.first_child)
        while at < end {
            if parse.child_is_node_at(tree, at) {
                let child = tree.nodes[parse.child_index_at(tree, at)]
                if check_statement_kind(child.kind) {
                    last = child
                    found = true
                }
            }
            at += 1usize
        }
        if !found { ret false }
        if last.kind == .Block { ret resource_diverges(c, g, tree, module_index, last) }
    }
    // `break` and `continue` leave the block too (D353), auditing what they leave.
    if last.kind == .BreakStmt || last.kind == .ContinueStmt { ret true }
    if last.kind != .CallStmt { ret false }
    let (call_index, has_call) = first_node_child(tree, last)
    if !has_call { ret false }
    let call = tree.nodes[call_index]
    if call.kind != .CallExpr { ret false }
    let (callee_index, has_callee) = first_node_child(tree, call)
    if !has_callee { ret false }
    let callee = tree.nodes[callee_index]
    let text = g.modules[module_index].text
    if callee.kind == .NameExpr {
        let token = c.tokens[usize(callee.token_start)]
        ret token.kind == .KwUnreachable
    }
    if callee.kind == .FieldExpr || callee.kind == .MemberExpr {
        // `os.exit(...)`: the qualifier and the member, as spelled.
        let first = c.tokens[usize(callee.token_start)]
        let member = c.tokens[usize(callee.token_end) - 1usize]
        ret same(text[first.start..first.end], "os") && same(text[member.start..member.end], "exit")
    }
    ret false
}

// A returned value that names a resource local: moved out to the caller, whatever
// its state but moved -- an unchecked one goes with the error it was bound beside.
fn resource_return_value(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    var (local_index, is_resource) = resource_local_of(c, g, tree, module_index, node_index)
    // A pointer copied out of an aggregate field still names the region local
    // recorded by that aggregate's alias fact (D682).
    let (aliased, has_alias) = alias_target(c, g, tree, module_index, node_index)
    if has_alias && c.resources[aliased].region != 0usize {
        local_index = aliased
        is_resource = true
    }
    let dynamic_path = has_dynamic_alias_path(c, g, tree, module_index, node_index)
    if !has_alias && dynamic_path {
        var wanted = 0usize
        while true {
            let (candidate, found) = dynamic_alias_candidate(c, g, tree, module_index, node_index, wanted)
            if !found { break }
            if c.resources[candidate].region != 0usize {
                local_index = candidate
                is_resource = true
                break
            }
            wanted += 1usize
        }
    }
    if !has_alias && !dynamic_path {
        let (carrier, has_carrier) = place_base_local(c, g, tree, module_index, node_index)
        if has_carrier {
            if c.resources[carrier].points_to != 0usize {
                let carried = c.resources[carrier].points_to - 1usize
                if carried < c.local_count && c.resources[carried].region != 0usize {
                    local_index = carried
                    is_resource = true
                }
                if !is_resource && c.resources[carrier].slice_offset_known {
                    let second = c.resources[carrier].slice_offset - 1usize
                    if second < c.local_count && c.resources[second].region != 0usize {
                        local_index = second
                        is_resource = true
                    }
                }
            }
            // A third or later aggregate pointer field is retained in the sparse
            // alias table and is the same carrier escape (D697, D702), including
            // a nested-only carrier which has no inline alias.
            var alias_at = 0usize
            while !is_resource && alias_at < c.resource_alias_count {
                let alias = c.resource_aliases[alias_at]
                if alias.carrier == carrier && alias.pointed < c.local_count && c.resources[alias.pointed].region != 0usize {
                    local_index = alias.pointed
                    is_resource = true
                }
                alias_at += 1usize
            }
        }
    }
    if !is_resource && tree.nodes[node_index].kind == .BracketPostfix {
        var bracket: BracketInfo = zero
        if read_bracket(c, tree, tree.nodes[node_index], &bracket) == ok && bracket.range {
            (local_index, is_resource) = place_base_local(c, g, tree, module_index, node_index)
            if is_resource { is_resource = c.resources[local_index].region != 0usize }
        }
    }
    if !is_resource && tree.nodes[node_index].kind == .UnaryExpr && c.tokens[usize(tree.nodes[node_index].token_start)].kind == .PunctAmp {
        let (inner_index, has_inner) = first_node_child(tree, tree.nodes[node_index])
        if has_inner {
            (local_index, is_resource) = place_base_local(c, g, tree, module_index, inner_index)
            if is_resource { is_resource = c.resources[local_index].region != 0usize }
        }
    }
    if !is_resource && !any_affine_local(c) { ret ok }
    if is_resource && c.resources[local_index].region != 0usize {
        let region_mark = c.resources[local_index].region - 1usize
        var mark_at = 0usize
        while mark_at <= region_mark && mark_at < c.local_count {
            if c.resources[mark_at].dangling == 3u8 && same(c.resources[mark_at].mark_arena, c.resources[region_mark].mark_arena) {
                record_failure_related(c, module_index, tree.nodes[node_index], .RegionEscape, c.locals[local_index].name, line_detail(c, g, module_index, c.resources[mark_at].lent_at), c.resources[mark_at].lent_at)
                ret ResourceViolation
            }
            mark_at += 1usize
        }
    }
    c.resource_transfer = true
    let returned = resource_return_transfer(c, g, tree, module_index, node_index)
    c.resource_transfer = false
    ret returned
}

fn resource_return_transfer(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    if tree.nodes[node_index].kind == .FieldExpr { ret resource_consume(c, g, tree, module_index, node_index) }
    let (local_index, is_resource) = resource_local_of(c, g, tree, module_index, node_index)
    if !is_resource { ret ok }
    if c.resources[local_index].state == resource_unchecked {
        c.resources[local_index].state = resource_moved
        record_explain_move(c, module_index, tree.nodes[node_index], c.locals[local_index].name)
        ret ok
    }
    ret resource_consume(c, g, tree, module_index, node_index)
}

// `s.f` consumed: moved out of `s`, which keeps the rest. Inside a `defer`, reserved.
fn resource_consume_field(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    let (local_index, at, is_field) = resource_field_of(c, g, tree, module_index, node_index)
    if !is_field { ret ok }
    let node = tree.nodes[node_index]
    let byte = c.resources[local_index].fields[at]
    let state = field_state(byte)
    if state == resource_reserved {
        record_failure_related(c, module_index, node, .ResourceDeferredConsumed, resource_field_name(c, local_index, at), line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    if state == resource_null { ret ok }
    if state == resource_unchecked {
        record_failure_related(c, module_index, node, .ResourceUnchecked, resource_field_name(c, local_index, at), line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    if state != resource_owned {
        record_failure_related(c, module_index, node, .ResourceUseAfterMove, resource_field_name(c, local_index, at), line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    if c.resource_transfer && c.resources[local_index].borrowed {
        record_failure_related(c, module_index, node, .ResourceBorrowConsumed, resource_field_name(c, local_index, at), line_detail(c, g, module_index, c.resources[local_index].acquired), c.resources[local_index].acquired)
        ret ResourceViolation
    }
    // A field that is not owed holds a view of someone else's handle: read as often
    // as wanted, moved by nobody.
    if !field_owed(byte) { ret ok }
    if c.defer_depth != 0usize {
        c.resources[local_index].fields[at] = field_with(resource_reserved, field_owed(byte))
        ret ok
    }
    if c.resources[local_index].pinned != 0usize {
        record_failure_related(c, module_index, node, .ResourceMovedWhileBorrowed, resource_field_name(c, local_index, at), line_detail(c, g, module_index, c.resources[local_index].pin_at), c.resources[local_index].pin_at)
        ret ResourceViolation
    }
    c.resources[local_index].fields[at] = field_with(resource_moved, field_owed(byte))
    c.resources[local_index].acquired = usize(node.token_start)
    ret ok
}

// A fixed-array element consumed through an exact index moves one slot. A runtime
// index may move any candidate, so every owed candidate becomes maybe-moved.
fn resource_consume_element(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    let (local_index, first, end, is_element) = resource_element_candidates(c, g, tree, module_index, node_index)
    if !is_element {
        let (slice_local, owned_slice) = resource_owned_slice_of(c, g, tree, module_index, node_index)
        if owned_slice {
            let node = tree.nodes[node_index]
            if resource_owned_slice_is_swept(c, g, tree, module_index, node_index, slice_local) {
                c.resources[slice_local].state = resource_moved
                c.resources[slice_local].acquired = usize(node.token_start)
                c.resource_loop_swept_local[c.loop_depth - 1usize] = slice_local + 1usize
                ret ok
            }
            record_failure_related(c, module_index, node, .ResourcePartialMove, c.locals[slice_local].name, line_detail(c, g, module_index, c.resources[slice_local].acquired), c.resources[slice_local].acquired)
            ret ResourceViolation
        }
        ret ok
    }
    let node = tree.nodes[node_index]
    var at = first
    var owed = false
    while at < end {
        let byte = c.resources[local_index].fields[at]
        if !field_owed(byte) {
            at += 1usize
            continue
        }
        let state = field_state(byte)
        let acquired = resource_part_acquired(c, local_index, at)
        if state == resource_reserved {
            record_failure_related(c, module_index, node, .ResourceDeferredConsumed, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        if state == resource_unchecked {
            record_failure_related(c, module_index, node, .ResourceUnchecked, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        if state != resource_owned && state != resource_null {
            record_failure_related(c, module_index, node, .ResourceUseAfterMove, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        if state == resource_owned && c.resource_transfer && c.resources[local_index].borrowed {
            record_failure_related(c, module_index, node, .ResourceBorrowConsumed, resource_field_name(c, local_index, at), line_detail(c, g, module_index, acquired), acquired)
            ret ResourceViolation
        }
        if state == resource_owned && field_owed(byte) { owed = true }
        at += 1usize
    }
    if !owed { ret ok }
    if c.resources[local_index].pinned != 0usize {
        record_failure_related(c, module_index, node, .ResourceMovedWhileBorrowed, resource_field_name(c, local_index, first), line_detail(c, g, module_index, c.resources[local_index].pin_at), c.resources[local_index].pin_at)
        ret ResourceViolation
    }
    var next = resource_maybe
    if end == first + 1usize {
        next = resource_moved
        if c.defer_depth != 0usize { next = resource_reserved }
    } else {
        if resource_element_is_swept(c, g, tree, module_index, node_index, first, end) {
            next = resource_moved
            c.resource_loop_swept_local[c.loop_depth - 1usize] = local_index + 1usize
        }
    }
    at = first
    while at < end {
        let byte = c.resources[local_index].fields[at]
        if field_state(byte) == resource_owned && field_owed(byte) {
            c.resources[local_index].fields[at] = field_with(next, true)
            c.resources[local_index].elements_acquired[at] = usize(node.token_start)
        }
        at += 1usize
    }
    c.resources[local_index].acquired = usize(node.token_start)
    ret ok
}

// The locals named as values of an aggregate literal's items are moved into it.
fn resource_literal_moves(c: *Checker, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    let node = tree.nodes[node_index]
    if node.kind == .NameExpr { ret resource_consume(c, g, tree, module_index, node_index) }
    if node.kind == .FieldExpr { ret resource_consume(c, g, tree, module_index, node_index) }
    if node.kind != .AggregateLiteral && node.kind != .LiteralItem { ret ok }
    let end = usize(node.first_child) + usize(node.child_count)
    var at = usize(node.first_child)
    while at < end {
        if parse.child_is_node_at(tree, at) { try resource_literal_moves(c, g, tree, module_index, parse.child_index_at(tree, at)) }
        at += 1usize
    }
    ret ok
}

fn resource_field_global(c: *Checker, local_index: usize, at: usize) -> usize {
    let (aggregate_index, tracked) = resource_tracked_struct(c, c.locals[local_index].ty)
    if !tracked { ret 0usize }
    var aggregate = c.aggregates[aggregate_index]
    if aggregate.generic && aggregate.instance && aggregate.template_index < c.aggregate_count { aggregate = c.aggregates[aggregate.template_index] }
    ret aggregate.first_field + at
}

// The seeded handles' `raw` stays readable for now: the fixed surface has no
// `file_handle` for the bootstrap-compiled programs that need the bits.
fn seeded_handle(c: *Checker, ty: Type) -> bool {
    if seeded_arena(c, ty) { ret true }
    ret ty.kind == .Named && module_is_os(c, ty.module_index) && (same(ty.name, "File") || same(ty.name, "Proc") || same(ty.name, "Thread"))
}

// The source's field bytes copied into the destination's own run.
fn resource_copy_fields(c: *Checker, local_index: usize, source_index: usize) -> err {
    let count = c.resources[source_index].fields.len
    if count == 0usize {
        var none: []u8 = zero
        var no_elements_acquired: []usize = zero
        c.resources[local_index].fields = none
        c.resources[local_index].elements_acquired = no_elements_acquired
        ret ok
    }
    let (fields, fields_error) = mem.alloc[u8](c.arena, count)
    if fields_error != ok { ret fields_error }
    var at = 0usize
    while at < count {
        fields[at] = c.resources[source_index].fields[at]
        at += 1usize
    }
    c.resources[local_index].fields = fields[0usize..count]
    if c.resources[source_index].elements_acquired.len == count {
        let (acquired, acquired_error) = mem.alloc[usize](c.arena, count + 1usize)
        if acquired_error != ok { ret acquired_error }
        at = 0usize
        while at < count {
            acquired[at] = c.resources[source_index].elements_acquired[at]
            at += 1usize
        }
        c.resources[local_index].elements_acquired = acquired[0usize..count]
    }
    ret ok
}

// Whether `function` is the cleanup the resource type names.
fn resource_cleanup_of(c: *Checker, ty: Type, function: Function) -> bool {
    if ty.kind != .Named { ret false }
    let (aggregate_index, found) = aggregate_for_type(c, ty)
    if !found { ret false }
    let aggregate = c.aggregates[aggregate_index]
    ret aggregate.resource && aggregate.module_index == function.module_index && same(aggregate.cleanup, function.name)
}
