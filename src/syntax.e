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

fn node(kind: Kind, token_start: usize, token_end: usize, first_child: usize, child_count: usize) -> Node {
    ret Node { kind: kind, top_level: false, parented: false, token_start: token_start, token_end: token_end, first_child: first_child, child_count: child_count }
}

fn token_child(index: usize) -> Child {
    ret Child { node: false, index: index }
}

fn node_child(index: usize) -> Child {
    ret Child { node: true, index: index }
}
