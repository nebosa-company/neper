// The JavaScript syntax tree (browser tracker 5.2) shared by the parser (`e.js.parse`) and the interpreter (`e.js.interp`).
//
// The tree is flat: `Program.nodes` holds every node, `Program.kids` holds the child lists, and a node names its children by
// index. A node uses `a`..`d` for children (an index into `nodes`, or `NONE`), or `a` = first index into `kids` and `b` =
// count for a list. `op` is an operator or declaration kind, `flags` the F_ bits, `text` an identifier, string or name, and
// `num` a numeric literal. `hoist_first`/`hoist_count` (functions and the program) name the `var` bindings and function
// declarations the body hoists, as a list of nodes in `kids`.
//
// Patterns reuse expression nodes (the cover grammar): an array or object literal in a binding or assignment position is a
// pattern, `N_ASSIGN` inside it is a default, `N_SPREAD` a rest element.

const NONE: u32 = 4294967295u32

// Expressions.
const N_NUM: u8 = 1u8
const N_STR: u8 = 2u8
const N_TEMPLATE: u8 = 3u8
const N_TAGGED: u8 = 4u8
const N_REGEX: u8 = 5u8
const N_IDENT: u8 = 6u8
const N_THIS: u8 = 7u8
const N_NULL: u8 = 8u8
const N_TRUE: u8 = 9u8
const N_FALSE: u8 = 10u8
const N_ARRAY: u8 = 11u8
const N_OBJECT: u8 = 12u8
const N_PROP: u8 = 13u8
const N_SPREAD: u8 = 14u8
const N_FUNC: u8 = 15u8
const N_CLASS: u8 = 16u8
const N_UNARY: u8 = 17u8
const N_UPDATE: u8 = 18u8
const N_BINARY: u8 = 19u8
const N_LOGICAL: u8 = 20u8
const N_ASSIGN: u8 = 21u8
const N_COND: u8 = 22u8
const N_CALL: u8 = 23u8
const N_NEW: u8 = 24u8
const N_MEMBER: u8 = 25u8
const N_OPTCHAIN: u8 = 26u8
const N_SEQ: u8 = 27u8
const N_YIELD: u8 = 28u8
const N_AWAIT: u8 = 29u8
const N_HOLE: u8 = 30u8
const N_SUPER: u8 = 31u8
const N_NEWTARGET: u8 = 32u8
const N_PRIVATE: u8 = 33u8
const N_BIGINT: u8 = 34u8
const N_IMPORT_META: u8 = 35u8
const N_IMPORT_CALL: u8 = 36u8
const N_PRIVATE_IN: u8 = 37u8

// Statements.
const N_VAR: u8 = 40u8
const N_DECL: u8 = 41u8
const N_EXPR_STMT: u8 = 42u8
const N_BLOCK: u8 = 43u8
const N_IF: u8 = 44u8
const N_FOR: u8 = 45u8
const N_FORIN: u8 = 46u8
const N_FOROF: u8 = 47u8
const N_WHILE: u8 = 48u8
const N_DOWHILE: u8 = 49u8
const N_RETURN: u8 = 50u8
const N_BREAK: u8 = 51u8
const N_CONTINUE: u8 = 52u8
const N_THROW: u8 = 53u8
const N_TRY: u8 = 54u8
const N_CATCH: u8 = 55u8
const N_SWITCH: u8 = 56u8
const N_CASE: u8 = 57u8
const N_LABELED: u8 = 58u8
const N_EMPTY: u8 = 59u8
const N_DEBUGGER: u8 = 60u8
const N_PROGRAM: u8 = 61u8
const N_WITH: u8 = 62u8

// Module items. N_IMPORT: `a`/`b` the list of N_IMPORT_SPEC, `text` the module specifier. N_IMPORT_SPEC: `op` 1 default,
// 2 namespace, 3 named; `text` the imported name, `text2` the local binding. N_EXPORT: `op` is an X_ constant; for X_DECL and
// X_DEFAULT_DECL `a` is the declaration, for X_DEFAULT_EXPR `a` the expression, for X_LIST `a`/`b` the list of N_EXPORT_SPEC
// and `text` the module it re-exports from when `c` is 1, for X_STAR and X_STAR_AS `text` the module and for X_STAR_AS `text2`
// the exported name. N_EXPORT_SPEC: `text` the local (or imported) name, `text2` the exported name.
const N_IMPORT: u8 = 70u8
const N_EXPORT: u8 = 71u8
const N_IMPORT_SPEC: u8 = 72u8
const N_EXPORT_SPEC: u8 = 73u8

const X_DECL: u8 = 1u8
const X_DEFAULT_EXPR: u8 = 2u8
const X_DEFAULT_DECL: u8 = 3u8
const X_LIST: u8 = 4u8
const X_STAR: u8 = 5u8
const X_STAR_AS: u8 = 6u8

// Declaration kinds (`op` of N_VAR and N_FORIN/N_FOROF heads).
const D_VAR: u8 = 1u8
const D_LET: u8 = 2u8
const D_CONST: u8 = 3u8

// Member kinds (`op` of N_PROP).
const M_INIT: u8 = 1u8
const M_METHOD: u8 = 2u8
const M_GET: u8 = 3u8
const M_SET: u8 = 4u8
const M_FIELD: u8 = 5u8
const M_STATIC_BLOCK: u8 = 6u8
const M_SPREAD: u8 = 7u8

// Flags.
const F_COMPUTED: u16 = 1u16
const F_SHORTHAND: u16 = 2u16
const F_STATIC: u16 = 4u16
const F_OPTIONAL: u16 = 8u16
const F_PREFIX: u16 = 16u16
const F_ARROW: u16 = 32u16
const F_ASYNC: u16 = 64u16
const F_GENERATOR: u16 = 128u16
const F_EXPR_BODY: u16 = 256u16
const F_STRICT: u16 = 512u16
const F_DECL: u16 = 1024u16
const F_USES_ARGS: u16 = 2048u16
const F_DELEGATE: u16 = 4096u16
const F_METHOD: u16 = 8192u16
const F_COVER_INIT: u16 = 16384u16
const F_DERIVED: u16 = 32768u16

// Operators: unary, update, binary and assignment.
const O_NEG: u8 = 1u8
const O_PLUS: u8 = 2u8
const O_NOT: u8 = 3u8
const O_BITNOT: u8 = 4u8
const O_TYPEOF: u8 = 5u8
const O_VOID: u8 = 6u8
const O_DELETE: u8 = 7u8
const O_INC: u8 = 8u8
const O_DEC: u8 = 9u8
const O_ADD: u8 = 10u8
const O_SUB: u8 = 11u8
const O_MUL: u8 = 12u8
const O_DIV: u8 = 13u8
const O_MOD: u8 = 14u8
const O_EXP: u8 = 15u8
const O_SHL: u8 = 16u8
const O_SHR: u8 = 17u8
const O_USHR: u8 = 18u8
const O_BITAND: u8 = 19u8
const O_BITOR: u8 = 20u8
const O_BITXOR: u8 = 21u8
const O_LT: u8 = 22u8
const O_GT: u8 = 23u8
const O_LE: u8 = 24u8
const O_GE: u8 = 25u8
const O_EQ: u8 = 26u8
const O_NE: u8 = 27u8
const O_SEQ: u8 = 28u8
const O_SNE: u8 = 29u8
const O_IN: u8 = 30u8
const O_INSTANCEOF: u8 = 31u8
const O_AND: u8 = 32u8
const O_OR: u8 = 33u8
const O_NULLISH: u8 = 34u8
const O_ASSIGN: u8 = 35u8

type Node = struct {
    kind: u8, op: u8, flags: u16, a: u32, b: u32, c: u32, d: u32,
    hoist_first: u32, hoist_count: u32, line: u32, text: str, text2: str, num: f64
}

// A template literal's strings live in `strs`: `cooked`, `raw`, `valid` per string, starting at a node's `a` (count `b`).
type TemplateStr = struct { cooked: str, raw: str, valid: bool }

type Program = struct {
    nodes: []const Node, kids: []const u32, strs: []const TemplateStr, root: u32, source: str, url: str, module: *void, is_module: bool
}
