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

// A node as the tree stores it and as every reader takes it (D318): a kind, two flag
// bytes and four 32-bit indexes, 20 bytes, the way Zig and Carbon keep a node as a tag
// and offsets. A reader widens an index as it reads it; a child is one 32-bit word
// whose high bit says node.
type Node = struct {
    kind: Kind,
    top_level: bool,
    parented: bool,
    token_start: u32,
    token_end: u32,
    first_child: u32,
    child_count: u32,
}

type Child = struct {
    node: bool,
    index: usize,
}

fn pack_child(c: Child) -> u32 {
    if c.node { ret u32(c.index) | 2147483648u32 }
    ret u32(c.index)
}

fn unpack_child(w: u32) -> Child {
    let flagged = w & 2147483648u32
    ret Child { node: flagged != 0u32, index: usize(w & 2147483647u32) }
}

fn node(kind: Kind, token_start: usize, token_end: usize, first_child: usize, child_count: usize) -> Node {
    ret Node { kind: kind, top_level: false, parented: false, token_start: u32(token_start), token_end: u32(token_end), first_child: u32(first_child), child_count: u32(child_count) }
}

fn token_child(index: usize) -> Child {
    ret Child { node: false, index: index }
}

fn node_child(index: usize) -> Child {
    ret Child { node: true, index: index }
}
