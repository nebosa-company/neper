// Frozen grammar revision 1 syntax-node registry.

type Kind = enum u8 {
    File,
    UseDecl,
    Attribute,
    TypeDecl,
    ConstDecl,
    VarDecl,
    ErrorDecl,
    FnDecl,
    ExternDecl,
    ComptimeParam,
    Parameter,
    ReturnSpec,
    StructType,
    UnionType,
    EnumType,
    UnionEnumType,
    FieldDecl,
    EnumMember,
    UnionMember,
    PointerType,
    SliceType,
    ArrayType,
    FunctionType,
    NamedType,
    Block,
    Binding,
    BindingStmt,
    AssignmentStmt,
    CallStmt,
    TryStmt,
    ReturnStmt,
    DeferStmt,
    NocheckStmt,
    SharedVarStmt,
    BreakStmt,
    ContinueStmt,
    IfStmt,
    WhileStmt,
    ForStmt,
    WhenStmt,
    SwitchStmt,
    SwitchArm,
    UnaryExpr,
    BinaryExpr,
    FieldExpr,
    BracketPostfix,
    CallExpr,
    NameExpr,
    MemberExpr,
    GroupExpr,
    AggregateLiteral,
    LiteralItem,
    LiteralExpr,
    ErrorNode,
}

type Node = struct {
    kind: Kind,
    top_level: bool,
    parented: bool,
    token_start: usize,
    token_end: usize,
    first_child: usize,
    child_count: usize,
}

type Child = struct {
    node: bool,
    index: usize,
}

// A node as the tree stores it (D317): 20 bytes, the way Zig and Carbon keep a node as
// a tag and 32-bit indexes, against the 40 of `Node`. `Node` is what every reader is
// handed, unpacked at the access; a child is one word, its high bit saying node.
type Packed = struct {
    kind: Kind,
    flags: u8,
    token_start: u32,
    token_end: u32,
    first_child: u32,
    child_count: u32,
}

fn pack(n: Node) -> Packed {
    var flags = 0u8
    if n.top_level { flags = flags | 1u8 }
    if n.parented { flags = flags | 2u8 }
    ret Packed { kind: n.kind, flags: flags, token_start: u32(n.token_start), token_end: u32(n.token_end), first_child: u32(n.first_child), child_count: u32(n.child_count) }
}

fn unpack(p: Packed) -> Node {
    ret Node { kind: p.kind, top_level: (p.flags & 1u8) != 0u8, parented: (p.flags & 2u8) != 0u8, token_start: usize(p.token_start), token_end: usize(p.token_end), first_child: usize(p.first_child), child_count: usize(p.child_count) }
}

fn pack_child(c: Child) -> u32 {
    if c.node { ret u32(c.index) | 2147483648u32 }
    ret u32(c.index)
}

fn unpack_child(w: u32) -> Child {
    ret Child { node: (w & 2147483648u32) != 0u32, index: usize(w & 2147483647u32) }
}

fn node(kind: Kind, token_start: usize, token_end: usize, first_child: usize, child_count: usize) -> Node {
    ret Node { kind: kind, top_level: false, parented: false, token_start: token_start, token_end: token_end, first_child: first_child, child_count: child_count }
}

fn token_child(index: usize) -> Child {
    ret Child { node: false, index: index }
}

fn node_child(index: usize) -> Child {
    ret Child { node: true, index: index }
}
