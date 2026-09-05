/*
 * neper bootstrap compiler.
 *
 * Deliberately small C99 implementation of the walking skeleton described by
 * docs/roadmap.md. It accepts M0 plus the implemented neper-0 increments, checks
 * the program-root signature, lowers functions to a compact typed tree, emits x86-64 assembly,
 * asks the platform assembler for an object file, and links with the system
 * linker.  The bootstrap is throwaway code; clarity and deterministic output
 * matter more than cleverness here.
 */

#define _CRT_SECURE_NO_WARNINGS
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef _WIN32
#include <direct.h>
#include <process.h>
#include <windows.h>
#define PATH_SEP '\\'
#define getcwd _getcwd
#else
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#define PATH_SEP '/'
#endif

#define NEPER_VERSION "0.0.61-neper0"
#define MAX_TOKENS 65536
#define MAX_DECLS 1024
#define MAX_PARAMS 32
#define MAX_LOCALS 256
#define MAX_ARGS 16
#define MAX_USES 128
#define MAX_STRINGS 4096
#define MAX_DIAGNOSTICS 4096
#define MAX_TRAP_SITES 4096
#define MAX_PATH_LEN 4096
#define MAX_LOOP_DEPTH 64
#define MAX_ARRAY_ELEMENTS 4096
#define MAX_FIELDS 128
#define MAX_FIELD_PATH 32
#define MAX_SOURCES 128

typedef enum TokenKind {
    TK_EOF,
    TK_NEWLINE,
    TK_IDENT,
    TK_INTEGER,
    TK_STRING,
    TK_USE,
    TK_TYPE,
    TK_STRUCT,
    TK_UNION,
    TK_ENUM,
    TK_ERROR,
    TK_FN,
    TK_LET,
    TK_VAR,
    TK_RET,
    TK_IF,
    TK_ELSE,
    TK_WHILE,
    TK_FOR,
    TK_IN,
    TK_BREAK,
    TK_CONTINUE,
    TK_SWITCH,
    TK_CASE,
    TK_DEFAULT,
    TK_AS,
    TK_DEFER,
    TK_TRY,
    TK_OK,
    TK_TRUE,
    TK_FALSE,
    TK_ZERO,
    TK_UNDEF,
    TK_CONST,
    TK_LPAREN,
    TK_RPAREN,
    TK_LBRACE,
    TK_RBRACE,
    TK_LBRACKET,
    TK_RBRACKET,
    TK_COLON,
    TK_COMMA,
    TK_DOT,
    TK_RANGE,
    TK_AMP,
    TK_STAR,
    TK_ARROW,
    TK_ASSIGN,
    TK_ADD_ASSIGN,
    TK_PLUS,
    TK_MINUS,
    TK_SLASH,
    TK_PERCENT,
    TK_EQ,
    TK_NE,
    TK_LT,
    TK_LE,
    TK_GT,
    TK_GE,
    TK_AND,
    TK_OR,
    TK_BANG
} TokenKind;

typedef struct Token {
    TokenKind kind;
    const char *start;
    int length;
    int line;
    int column;
    int end_line;
    int end_column;
    int column_utf16;
    int end_column_utf16;
    size_t byte_start;
    size_t byte_end;
    int source_id;
} Token;

typedef enum TypeKind {
    TY_INVALID,
    TY_VOID,
    TY_BOOL,
    TY_INT,
    TY_UNTYPED_INT,
    TY_ERR,
    TY_STR,
    TY_ARENA,
    TY_POINTER,
    TY_SLICE,
    TY_ARRAY,
    TY_NAMED
} TypeKind;

typedef struct Expr Expr;

typedef struct Type {
    TypeKind kind;
    char name[96];
    int is_const;
    TypeKind element_kind;
    char element_name[96];
    int element_is_const;
    size_t array_length;
    Expr *array_length_expr;
    struct Type *generic_types[MAX_ARGS];
    Expr *generic_values[MAX_ARGS];
    unsigned char generic_is_type[MAX_ARGS];
    int generic_arg_count;
    struct Type *element;
} Type;

typedef struct ComptimeParam {
    char name[96];
    Token token;
    int is_type;
    Type value_type;
} ComptimeParam;

typedef enum ExprKind {
    EX_INTEGER,
    EX_STRING,
    EX_NAME,
    EX_CALL,
    EX_INDEX,
    EX_FIELD,
    EX_SLICE,
    EX_ARRAY_LITERAL,
    EX_STRUCT_LITERAL,
    EX_ENUM_MEMBER,
    EX_ZERO,
    EX_UNDEF,
    EX_BINARY,
    EX_UNARY
} ExprKind;

struct Expr {
    ExprKind kind;
    Token token;
    Type type;
    int local_index;
    int trap_id;
    int error_code;
    int is_constant;
    int64_t constant_value;
    int field_offsets[MAX_FIELD_PATH];
    unsigned char field_dereferences[MAX_FIELD_PATH];
    unsigned char field_tag_checks[MAX_FIELD_PATH];
    unsigned char field_tag_sizes[MAX_FIELD_PATH];
    int64_t field_tag_values[MAX_FIELD_PATH];
    int field_path_count;
    int place_mutable;
    int is_len;
    Type place_type;
    union {
        int64_t integer;
        struct {
            unsigned char *bytes;
            size_t length;
            int label;
        } string;
        char name[160];
        struct {
            char callee[160];
            Type generic_types[MAX_ARGS];
            Expr *generic_values[MAX_ARGS];
            unsigned char generic_is_type[MAX_ARGS];
            int generic_arg_count;
            Expr *args[MAX_ARGS];
            int arg_count;
        } call;
        struct {
            Expr *base;
            Expr *index;
        } index;
        struct {
            Expr *base;
            char name[96];
            int offset;
            int tag_check;
            int tag_size;
            int64_t tag_value;
        } field;
        struct {
            Expr *base;
            Expr *start;
            Expr *end;
        } slice;
        struct {
            Expr **items;
            int item_count;
            int item_capacity;
            int infer_length;
        } array;
        struct {
            char type_name[96];
            struct StructInit *items;
            int item_count;
            int item_capacity;
        } aggregate;
        struct {
            TokenKind op;
            Expr *left;
            Expr *right;
        } binary;
        struct {
            TokenKind op;
            Expr *value;
        } unary;
    } as;
};

typedef enum StmtKind {
    ST_BIND,
    ST_MULTI_BIND,
    ST_ASSIGN,
    ST_MULTI_ASSIGN,
    ST_INDEX_ASSIGN,
    ST_EXPR,
    ST_TRY,
    ST_RETURN,
    ST_IF,
    ST_WHILE,
    ST_FOR_RANGE,
    ST_FOR_EACH,
    ST_SWITCH,
    ST_DEFER,
    ST_BREAK,
    ST_CONTINUE
} StmtKind;

typedef struct Stmt Stmt;
typedef struct SwitchCase SwitchCase;

struct SwitchCase {
    Token token;
    Expr *values[MAX_ARGS];
    int value_count;
    int is_default;
    char binding[96];
    int local_index;
    int member_index;
    Stmt *body;
    SwitchCase *next;
};

struct Stmt {
    StmtKind kind;
    Token token;
    int debug_label;
    Stmt *next;
    union {
        struct {
            char name[96];
            Type declared_type;
            Expr *value;
            int is_mutable;
            int local_index;
        } bind;
        struct {
            char names[MAX_ARGS][96];
            int local_indices[MAX_ARGS];
            int count;
            int is_mutable;
            Expr *call;
        } multi;
        struct {
            char name[96];
            Expr *target;
            Expr *value;
            int local_index;
            TokenKind op;
        } assign;
        struct {
            Expr *target;
            Expr *value;
            TokenKind op;
        } index_assign;
        Expr *expr;
        struct {
            Expr *value;
            Expr *values[MAX_ARGS];
            int value_count;
        } ret;
        struct {
            Expr *condition;
            Stmt *then_body;
            Stmt *else_body;
        } if_stmt;
        struct {
            Expr *condition;
            Stmt *body;
        } while_stmt;
        struct {
            char name[96];
            Expr *start;
            Expr *end;
            Stmt *body;
            int local_index;
            int end_local_index;
        } for_range;
        struct {
            char index_name[96];
            char value_name[96];
            int has_index;
            Expr *subject;
            Stmt *body;
            int pointer_local_index;
            int length_local_index;
            int index_local_index;
            int value_local_index;
            int is_protocol;
            int iterator_subject_is_pointer;
            int iterator_pointer_local_index;
            int iterator_has_local_index;
            char next_function[96];
        } for_each;
        struct {
            Expr *subject;
            SwitchCase *cases;
        } switch_stmt;
        struct {
            Stmt *body;
            int is_block;
            int is_captured_call;
            Expr *call;
            Expr *capture_values[MAX_ARGS];
            int capture_locals[MAX_ARGS];
            int capture_count;
        } defer_stmt;
    } as;
};

typedef struct Param {
    char name[96];
    Type type;
    Token token;
    int local_index;
} Param;

typedef struct Local {
    char name[96];
    Type type;
    Token token;
    int is_mutable;
    int active;
    int offset;
    int is_indirect;
} Local;

typedef struct Function {
    char name[96];
    char module[96];
    char symbol[112];
    Token token;
    Param params[MAX_PARAMS];
    int param_count;
    ComptimeParam comptime_params[MAX_ARGS];
    int comptime_param_count;
    int is_template;
    int is_intrinsic;
    Type return_type;
    Type return_types[MAX_ARGS];
    int return_count;
    int returns_via_slot;
    size_t return_offsets[MAX_ARGS];
    size_t return_storage_size;
    Stmt *body;
    Local locals[MAX_LOCALS];
    int local_count;
    int frame_size;
    int return_slot_local_index;
    int scalar_return_local_index;
    int return_value_locals[MAX_ARGS];
} Function;

typedef struct UseDecl {
    char name[160];
    char qualifier[96];
    char owner_module[96];
    Token token;
    int loaded;
} UseDecl;

typedef struct ErrorDecl {
    char name[96];
    char module[96];
    Token token;
    int code;
} ErrorDecl;

typedef struct ConstDecl {
    char name[96];
    char module[96];
    Token token;
    Type type;
    Expr *value;
    int64_t integer_value;
    int evaluation_state;
} ConstDecl;

typedef struct FieldDecl {
    char name[96];
    Token token;
    Type type;
    size_t offset;
    int has_payload;
    int64_t value;
} FieldDecl;

typedef enum NamedDeclKind {
    ND_STRUCT,
    ND_UNION,
    ND_ENUM,
    ND_TAGGED_UNION
} NamedDeclKind;

typedef struct StructDecl {
    char name[96];
    char module[96];
    Token token;
    NamedDeclKind kind;
    ComptimeParam comptime_params[MAX_ARGS];
    int comptime_param_count;
    int is_template;
    Type backing_type;
    FieldDecl fields[MAX_FIELDS];
    int field_count;
    size_t size;
    size_t alignment;
    size_t payload_offset;
    int layout_state;
} StructDecl;

typedef struct StructInit {
    char name[96];
    Token token;
    Expr *value;
    int field_index;
} StructInit;

typedef struct Program {
    UseDecl uses[MAX_USES];
    int use_count;
    ErrorDecl errors[MAX_DECLS];
    int error_count;
    ConstDecl constants[MAX_DECLS];
    int constant_count;
    StructDecl structs[MAX_DECLS];
    int struct_count;
    Function functions[MAX_DECLS];
    int function_count;
    Expr *strings[MAX_STRINGS];
    int string_count;
    struct TrapSite {
        Token token;
        char kind[16];
        char function[96];
        char message[MAX_PATH_LEN + 256];
        size_t message_length;
    } trap_sites[MAX_TRAP_SITES];
    int trap_site_count;
} Program;

typedef struct Diagnostic {
    Token token;
    char code[32];
    char message[512];
    int sequence;
} Diagnostic;

typedef struct SourceFile {
    char path[MAX_PATH_LEN];
    char module[96];
    char *text;
    size_t length;
    int parsed;
    int visit_state;
} SourceFile;

typedef struct Compiler {
    const char *source_path;
    char *source;
    size_t source_length;
    Token tokens[MAX_TOKENS];
    int token_count;
    int current;
    int errors;
    int checking_defer;
    Diagnostic diagnostics[MAX_DIAGNOSTICS];
    Program program;
    char executable_dir[MAX_PATH_LEN];
    char project_root[MAX_PATH_LEN];
    char current_module[96];
    char resolution_module[96];
    int current_source_id;
    int root_source_id;
    Token root_token;
    SourceFile sources[MAX_SOURCES];
    int source_count;
} Compiler;

static void copy_text(char *dst, size_t capacity, const char *src, size_t length) {
    if (capacity == 0) return;
    if (length >= capacity) length = capacity - 1;
    memcpy(dst, src, length);
    dst[length] = 0;
}

static int append_text(char *dst, size_t capacity, const char *src) {
    size_t used = strlen(dst), length = strlen(src);
    if (used + length >= capacity) return 0;
    memcpy(dst + used, src, length + 1);
    return 1;
}

static int append_character(char *dst, size_t capacity, char ch) {
    size_t used = strlen(dst);
    if (used + 1 >= capacity) return 0;
    dst[used] = ch;
    dst[used + 1] = 0;
    return 1;
}

static int join_qualified_name(char *out, size_t capacity,
                               const char *module, const char *name) {
    out[0] = 0;
    return append_text(out, capacity, module) &&
           append_character(out, capacity, '.') &&
           append_text(out, capacity, name);
}

static void diagnostic_at(Compiler *c, Token *token, const char *code, const char *message) {
    if (c->errors < MAX_DIAGNOSTICS) {
        Diagnostic *diagnostic = &c->diagnostics[c->errors];
        memset(diagnostic, 0, sizeof(*diagnostic));
        diagnostic->token = *token;
        copy_text(diagnostic->code, sizeof(diagnostic->code), code, strlen(code));
        copy_text(diagnostic->message, sizeof(diagnostic->message), message, strlen(message));
        diagnostic->sequence = c->errors;
    }
    c->errors++;
}

static const char *token_source_path(Compiler *c, const Token *token) {
    if (token->source_id >= 0 && token->source_id < c->source_count)
        return c->sources[token->source_id].path;
    return c->source_path;
}

static int compare_diagnostic(const void *left, const void *right) {
    const Diagnostic *a = (const Diagnostic *)left;
    const Diagnostic *b = (const Diagnostic *)right;
    int order;
    if (a->token.source_id < b->token.source_id) return -1;
    if (a->token.source_id > b->token.source_id) return 1;
    if (a->token.byte_start < b->token.byte_start) return -1;
    if (a->token.byte_start > b->token.byte_start) return 1;
    order = strcmp(a->code, b->code);
    if (order) return order;
    order = strcmp(a->message, b->message);
    if (order) return order;
    return a->sequence - b->sequence;
}

static void print_diagnostics(Compiler *c) {
    int i, count = c->errors < MAX_DIAGNOSTICS ? c->errors : MAX_DIAGNOSTICS;
    qsort(c->diagnostics, (size_t)count, sizeof(Diagnostic), compare_diagnostic);
    for (i = 0; i < count; ++i) {
        Diagnostic *diagnostic = &c->diagnostics[i];
        fprintf(stderr, "%s:%d:%d: error[%s]: %s\n", token_source_path(c, &diagnostic->token),
                diagnostic->token.line, diagnostic->token.column,
                diagnostic->code, diagnostic->message);
    }
    if (c->errors > MAX_DIAGNOSTICS)
        fprintf(stderr, "%s: error[E-TOOL-9999]: diagnostic limit exceeded\n", c->source_path);
}

static void lexical_error(Compiler *c, size_t byte, int line, int column,
                          const char *code, const char *message) {
    Token token;
    memset(&token, 0, sizeof(token));
    token.start = c->source + byte;
    token.line = line;
    token.column = column;
    token.end_line = line;
    token.end_column = column + 1;
    token.column_utf16 = column;
    token.end_column_utf16 = column + 1;
    token.byte_start = byte;
    token.byte_end = byte + 1;
    token.source_id = c->current_source_id;
    diagnostic_at(c, &token, code, message);
}

static TokenKind keyword_kind(const char *s, int n) {
    struct Keyword { const char *text; TokenKind kind; };
    static const struct Keyword keywords[] = {
        {"use", TK_USE}, {"type", TK_TYPE}, {"struct", TK_STRUCT},
        {"union", TK_UNION}, {"enum", TK_ENUM}, {"error", TK_ERROR},
        {"fn", TK_FN}, {"let", TK_LET}, {"var", TK_VAR},
        {"ret", TK_RET}, {"if", TK_IF}, {"else", TK_ELSE},
        {"while", TK_WHILE}, {"for", TK_FOR}, {"in", TK_IN},
        {"break", TK_BREAK}, {"continue", TK_CONTINUE},
        {"switch", TK_SWITCH}, {"case", TK_CASE}, {"default", TK_DEFAULT}, {"as", TK_AS},
        {"defer", TK_DEFER},
        {"try", TK_TRY}, {"ok", TK_OK},
        {"true", TK_TRUE}, {"false", TK_FALSE}, {"zero", TK_ZERO},
        {"undef", TK_UNDEF}, {"const", TK_CONST}
    };
    size_t i;
    for (i = 0; i < sizeof(keywords) / sizeof(keywords[0]); ++i) {
        if ((int)strlen(keywords[i].text) == n &&
            memcmp(s, keywords[i].text, (size_t)n) == 0) return keywords[i].kind;
    }
    return TK_IDENT;
}

static int is_ident_start(unsigned char ch) {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_';
}

static int is_ident_continue(unsigned char ch) {
    return is_ident_start(ch) || (ch >= '0' && ch <= '9');
}

static int validate_utf8(const unsigned char *s, size_t n, size_t *advance);

static void add_token(Compiler *c, TokenKind kind, size_t start, size_t end,
                      int line, int column, int column_utf16) {
    Token *token;
    size_t at;
    int end_line = line, end_column = column, end_utf16 = column_utf16;
    if (c->token_count >= MAX_TOKENS) {
        fprintf(stderr, "%s: error[E-TOOL-9999]: token limit exceeded\n", c->source_path);
        exit(2);
    }
    token = &c->tokens[c->token_count++];
    token->kind = kind;
    token->start = c->source + start;
    token->length = (int)(end - start);
    token->line = line;
    token->column = column;
    token->column_utf16 = column_utf16;
    token->byte_start = start;
    token->byte_end = end;
    token->source_id = c->current_source_id;
    for (at = start; at < end;) {
        unsigned char ch = (unsigned char)c->source[at];
        size_t width = 1;
        if (ch == '\r' || ch == '\n') {
            if (ch == '\r' && at + 1 < end && c->source[at + 1] == '\n') at++;
            end_line++; end_column = 1; end_utf16 = 1; at++; continue;
        }
        if (ch >= 0x80) validate_utf8((unsigned char *)c->source + at, end - at, &width);
        at += width; end_column++; end_utf16 += width == 4 ? 2 : 1;
    }
    token->end_line = end_line;
    token->end_column = end_column;
    token->end_column_utf16 = end_utf16;
}

static int validate_utf8(const unsigned char *s, size_t n, size_t *advance) {
    unsigned char a, b, c, d;
    if (n == 0) return 0;
    a = s[0];
    if (a < 0x80) { *advance = 1; return 1; }
    if (a >= 0xc2 && a <= 0xdf && n >= 2) {
        b = s[1]; if ((b & 0xc0) == 0x80) { *advance = 2; return 1; }
    } else if (a >= 0xe0 && a <= 0xef && n >= 3) {
        b = s[1]; c = s[2];
        if ((b & 0xc0) == 0x80 && (c & 0xc0) == 0x80 &&
            !(a == 0xe0 && b < 0xa0) && !(a == 0xed && b >= 0xa0)) {
            *advance = 3; return 1;
        }
    } else if (a >= 0xf0 && a <= 0xf4 && n >= 4) {
        b = s[1]; c = s[2]; d = s[3];
        if ((b & 0xc0) == 0x80 && (c & 0xc0) == 0x80 && (d & 0xc0) == 0x80 &&
            !(a == 0xf0 && b < 0x90) && !(a == 0xf4 && b >= 0x90)) {
            *advance = 4; return 1;
        }
    }
    *advance = 1;
    return 0;
}

static void lex(Compiler *c) {
    size_t i = 0;
    int line = 1;
    int column = 1;
    int column_utf16 = 1;
    if (c->source_length >= 3 && (unsigned char)c->source[0] == 0xef &&
        (unsigned char)c->source[1] == 0xbb && (unsigned char)c->source[2] == 0xbf) i = 3;
    while (i < c->source_length) {
        size_t start = i;
        int start_col = column;
        int start_utf16 = column_utf16;
        unsigned char ch = (unsigned char)c->source[i];
        if (ch == ' ') { i++; column++; column_utf16++; continue; }
        if (ch == '\t') {
            lexical_error(c, i, line, column, "E-LEX-0002", "tab is forbidden outside a literal");
            i++; column++; column_utf16++; continue;
        }
        if (ch < 0x20 && ch != '\r' && ch != '\n') {
            lexical_error(c, i, line, column, "E-LEX-0002", "forbidden ASCII control character");
            i++; column++; column_utf16++; continue;
        }
        if (ch >= 0x80) {
            size_t advance;
            if (!validate_utf8((unsigned char *)c->source + i, c->source_length - i, &advance))
                lexical_error(c, i, line, column, "E-LEX-0001", "invalid UTF-8");
            else lexical_error(c, i, line, column, "E-LEX-9999", "non-ASCII character is not valid in this token position");
            i += advance; column++; column_utf16 += advance == 4 ? 2 : 1; continue;
        }
        if (ch == '\r' || ch == '\n') {
            if (ch == '\r' && i + 1 < c->source_length && c->source[i + 1] == '\n') i += 2;
            else i++;
            add_token(c, TK_NEWLINE, start, i, line, start_col, start_utf16);
            line++; column = 1; column_utf16 = 1; continue;
        }
        if (ch == '/' && i + 1 < c->source_length && c->source[i + 1] == '/') {
            i += 2; column += 2; column_utf16 += 2;
            while (i < c->source_length && c->source[i] != '\r' && c->source[i] != '\n') {
                size_t adv;
                unsigned char comment_ch = (unsigned char)c->source[i];
                if (comment_ch < 0x20 && comment_ch != '\t') {
                    lexical_error(c, i, line, column, "E-LEX-0002", "forbidden ASCII control character");
                }
                if (!validate_utf8((unsigned char *)c->source + i, c->source_length - i, &adv)) {
                    lexical_error(c, i, line, column, "E-LEX-0001", "invalid UTF-8");
                }
                i += adv; column++; column_utf16 += adv == 4 ? 2 : 1;
            }
            continue;
        }
        if (is_ident_start(ch)) {
            i++; column++; column_utf16++;
            while (i < c->source_length && is_ident_continue((unsigned char)c->source[i])) {
                i++; column++; column_utf16++;
            }
            add_token(c, keyword_kind(c->source + start, (int)(i - start)), start, i, line, start_col, start_utf16);
            continue;
        }
        if (ch >= '0' && ch <= '9') {
            i++; column++; column_utf16++;
            while (i < c->source_length &&
                   (isalnum((unsigned char)c->source[i]) || c->source[i] == '_')) {
                i++; column++; column_utf16++;
            }
            add_token(c, TK_INTEGER, start, i, line, start_col, start_utf16);
            continue;
        }
        if (ch == '"') {
            int terminated = 0;
            i++; column++; column_utf16++;
            while (i < c->source_length) {
                unsigned char x = (unsigned char)c->source[i];
                if (x == '"') { i++; column++; column_utf16++; terminated = 1; break; }
                if (x == '\r' || x == '\n') break;
                if (x == '\\') {
                    i++; column++; column_utf16++;
                    if (i >= c->source_length) break;
                    x = (unsigned char)c->source[i];
                    if (!(x == 'n' || x == 'r' || x == 't' || x == '\\' ||
                          x == '"' || x == '\'' || x == '0' || x == 'x')) {
                        lexical_error(c, i, line, column, "E-LEX-0003", "invalid string escape");
                    }
                    if (x == 'x') {
                        if (i + 2 >= c->source_length || !isxdigit((unsigned char)c->source[i + 1]) ||
                            !isxdigit((unsigned char)c->source[i + 2])) {
                            lexical_error(c, i, line, column, "E-LEX-0003", "\\x requires two hexadecimal digits");
                        } else { i += 2; column += 2; column_utf16 += 2; }
                    }
                    i++; column++; column_utf16++;
                    continue;
                }
                {
                    size_t adv;
                    if (!validate_utf8((unsigned char *)c->source + i, c->source_length - i, &adv)) {
                        lexical_error(c, i, line, column, "E-LEX-0001", "invalid UTF-8");
                    }
                    i += adv; column++; column_utf16 += adv == 4 ? 2 : 1;
                }
            }
            if (!terminated) lexical_error(c, start, line, start_col, "E-LEX-0003", "unterminated string literal");
            add_token(c, TK_STRING, start, i, line, start_col, start_utf16);
            continue;
        }
        {
            TokenKind kind = TK_EOF;
            size_t width = 1;
            if (i + 1 < c->source_length) {
                char a = c->source[i], b = c->source[i + 1];
                if (a == '-' && b == '>') { kind = TK_ARROW; width = 2; }
                else if (a == '=' && b == '=') { kind = TK_EQ; width = 2; }
                else if (a == '!' && b == '=') { kind = TK_NE; width = 2; }
                else if (a == '<' && b == '=') { kind = TK_LE; width = 2; }
                else if (a == '>' && b == '=') { kind = TK_GE; width = 2; }
                else if (a == '&' && b == '&') { kind = TK_AND; width = 2; }
                else if (a == '|' && b == '|') { kind = TK_OR; width = 2; }
                else if (a == '.' && b == '.') { kind = TK_RANGE; width = 2; }
                else if (a == '+' && b == '=') { kind = TK_ADD_ASSIGN; width = 2; }
            }
            if (kind == TK_EOF) {
                switch (ch) {
                    case '(': kind = TK_LPAREN; break; case ')': kind = TK_RPAREN; break;
                    case '{': kind = TK_LBRACE; break; case '}': kind = TK_RBRACE; break;
                    case '[': kind = TK_LBRACKET; break; case ']': kind = TK_RBRACKET; break;
                    case ':': kind = TK_COLON; break; case ',': kind = TK_COMMA; break;
                    case '.': kind = TK_DOT; break; case '*': kind = TK_STAR; break;
                    case '&': kind = TK_AMP; break;
                    case '=': kind = TK_ASSIGN; break; case '+': kind = TK_PLUS; break;
                    case '-': kind = TK_MINUS; break; case '/': kind = TK_SLASH; break;
                    case '%': kind = TK_PERCENT; break; case '<': kind = TK_LT; break;
                    case '>': kind = TK_GT; break; case '!': kind = TK_BANG; break;
                    default:
                        lexical_error(c, i, line, column, "E-LEX-9999", "invalid source byte");
                        i++; column++; column_utf16++; continue;
                }
            }
            i += width; column += (int)width; column_utf16 += (int)width;
            add_token(c, kind, start, i, line, start_col, start_utf16);
        }
    }
    add_token(c, TK_EOF, c->source_length, c->source_length, line, column, column_utf16);
}

static Token *peek(Compiler *c) { return &c->tokens[c->current]; }
static int check(Compiler *c, TokenKind kind) { return peek(c)->kind == kind; }
static int match(Compiler *c, TokenKind kind) {
    if (!check(c, kind)) return 0;
    c->current++;
    return 1;
}

static Token *expect(Compiler *c, TokenKind kind, const char *message) {
    Token *token = peek(c);
    if (token->kind == kind) { c->current++; return token; }
    diagnostic_at(c, token, "E-SYNTAX-9999", message);
    if (token->kind != TK_EOF) c->current++;
    return token;
}

static void skip_newlines(Compiler *c) { while (match(c, TK_NEWLINE)) {} }

static Type type_make(TypeKind kind, const char *name) {
    Type t;
    memset(&t, 0, sizeof(t));
    t.kind = kind;
    if (name) copy_text(t.name, sizeof(t.name), name, strlen(name));
    return t;
}

static void type_set_element(Type *container, Type element) {
    container->element = (Type *)malloc(sizeof(Type));
    if (!container->element) { fputs("neper: out of memory\n", stderr); exit(2); }
    *container->element = element;
    container->element_kind = element.kind;
    copy_text(container->element_name, sizeof(container->element_name),
              element.name, strlen(element.name));
    container->element_is_const = element.is_const;
}

static Type type_array(Type element, size_t length) {
    Type type = type_make(TY_ARRAY, "array");
    type_set_element(&type, element);
    type.array_length = length;
    return type;
}

static Type intrinsic_pointer(Type element, int is_const) {
    Type type = type_make(TY_POINTER, element.name);
    type_set_element(&type, element);
    type.is_const = is_const;
    return type;
}

static Type intrinsic_slice(Type element, int is_const) {
    Type type = type_make(TY_SLICE, element.name);
    type_set_element(&type, element);
    type.is_const = is_const;
    return type;
}

static StructDecl *intrinsic_type(Compiler *c, Token token, const char *name,
                                  NamedDeclKind kind, Type backing) {
    StructDecl *decl = &c->program.structs[c->program.struct_count++];
    memset(decl, 0, sizeof(*decl));
    copy_text(decl->name, sizeof(decl->name), name, strlen(name));
    decl->token = token; decl->kind = kind; decl->backing_type = backing;
    return decl;
}

static void intrinsic_field(StructDecl *decl, Token token, const char *name, Type type,
                            int has_payload, int64_t value) {
    FieldDecl *field = &decl->fields[decl->field_count++];
    memset(field, 0, sizeof(*field));
    copy_text(field->name, sizeof(field->name), name, strlen(name));
    field->token = token; field->type = type; field->has_payload = has_payload; field->value = value;
}

static Function *intrinsic_function(Compiler *c, Token token, const char *name,
                                    const char *symbol) {
    Function *fn = &c->program.functions[c->program.function_count++];
    int i;
    memset(fn, 0, sizeof(*fn));
    copy_text(fn->name, sizeof(fn->name), name, strlen(name));
    copy_text(fn->symbol, sizeof(fn->symbol), symbol, strlen(symbol));
    fn->token = token; fn->is_intrinsic = 1;
    fn->return_slot_local_index = -1; fn->scalar_return_local_index = -1;
    for (i = 0; i < MAX_ARGS; ++i) fn->return_value_locals[i] = -1;
    return fn;
}

static void intrinsic_param(Function *fn, Token token, const char *name, Type type) {
    Param *param = &fn->params[fn->param_count++];
    memset(param, 0, sizeof(*param));
    copy_text(param->name, sizeof(param->name), name, strlen(name));
    param->token = token; param->type = type;
}

static void intrinsic_returns(Function *fn, int count, Type first, Type second) {
    fn->return_count = count;
    if (count > 0) fn->return_types[0] = first;
    if (count > 1) fn->return_types[1] = second;
    fn->return_type = count ? first : type_make(TY_VOID, "void");
}

static void install_os_intrinsics(Compiler *c) {
    static const char *error_names[] = {
        "NotFound", "Denied", "Exists", "Interrupted", "OutOfMemory",
        "Failed", "Timeout", "WouldBlock", "Unsupported"
    };
    Token token = c->tokens[0];
    Type u8 = type_make(TY_INT, "u8"), i32 = type_make(TY_INT, "i32");
    Type i64 = type_make(TY_INT, "i64"), usize = type_make(TY_INT, "usize");
    Type error = type_make(TY_ERR, "err"), arena = type_make(TY_ARENA, "mem.Arena");
    Type string = type_make(TY_STR, "str"), byte_pointer = intrinsic_pointer(u8, 0);
    Type file = type_make(TY_NAMED, "os.File"), proc = type_make(TY_NAMED, "os.Proc");
    Type clock = type_make(TY_NAMED, "os.Clock"), flags = type_make(TY_NAMED, "os.OpenFlags");
    Type handle = type_make(TY_NAMED, "os.Handle"), stdio_type = type_make(TY_NAMED, "os.Stdio");
    Type entry = type_make(TY_NAMED, "os.DirEntry");
    Type arena_pointer = intrinsic_pointer(arena, 0);
    Type bytes = intrinsic_slice(u8, 0), const_bytes = string;
    Type strings = intrinsic_slice(string, 0), const_strings = intrinsic_slice(string, 1);
    Type entries = intrinsic_slice(entry, 0), handles = intrinsic_slice(handle, 1);
    StructDecl *decl;
    Function *fn;
    int i;

    for (i = 0; i < (int)(sizeof(error_names) / sizeof(error_names[0])); ++i) {
        ErrorDecl *decl_error = &c->program.errors[c->program.error_count++];
        memset(decl_error, 0, sizeof(*decl_error));
        copy_text(decl_error->name, sizeof(decl_error->name), error_names[i], strlen(error_names[i]));
        strcpy(decl_error->module, "os"); decl_error->token = token; decl_error->code = i + 2;
    }

    decl = intrinsic_type(c, token, "os.File", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "raw", usize, 1, 0);
    decl = intrinsic_type(c, token, "os.Proc", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "raw", usize, 1, 0);
    decl = intrinsic_type(c, token, "os.Handle", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "raw", usize, 1, 0);
    decl = intrinsic_type(c, token, "os.Clock", ND_ENUM, u8);
    intrinsic_field(decl, token, "Wall", type_make(TY_VOID, "void"), 0, 0);
    intrinsic_field(decl, token, "Monotonic", type_make(TY_VOID, "void"), 0, 1);
    decl = intrinsic_type(c, token, "os.EntryKind", ND_ENUM, u8);
    intrinsic_field(decl, token, "File", type_make(TY_VOID, "void"), 0, 0);
    intrinsic_field(decl, token, "Dir", type_make(TY_VOID, "void"), 0, 1);
    intrinsic_field(decl, token, "Symlink", type_make(TY_VOID, "void"), 0, 2);
    intrinsic_field(decl, token, "Other", type_make(TY_VOID, "void"), 0, 3);
    decl = intrinsic_type(c, token, "os.DirEntry", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "name", string, 1, 0);
    intrinsic_field(decl, token, "kind", type_make(TY_NAMED, "os.EntryKind"), 1, 0);
    decl = intrinsic_type(c, token, "os.OpenFlags", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "read", type_make(TY_BOOL, "bool"), 1, 0);
    intrinsic_field(decl, token, "write", type_make(TY_BOOL, "bool"), 1, 0);
    intrinsic_field(decl, token, "create", type_make(TY_BOOL, "bool"), 1, 0);
    intrinsic_field(decl, token, "truncate", type_make(TY_BOOL, "bool"), 1, 0);
    intrinsic_field(decl, token, "append", type_make(TY_BOOL, "bool"), 1, 0);
    decl = intrinsic_type(c, token, "os.Stdio", ND_STRUCT, type_make(TY_VOID, "void"));
    intrinsic_field(decl, token, "stdin", file, 1, 0);
    intrinsic_field(decl, token, "stdout", file, 1, 0);
    intrinsic_field(decl, token, "stderr", file, 1, 0);
    intrinsic_field(decl, token, "inherit", handles, 1, 0);

#define OS_FN(source_name, native_name) fn = intrinsic_function(c, token, source_name, native_name)
    OS_FN("os.open", "neper_os_open"); intrinsic_param(fn, token, "a", arena_pointer); intrinsic_param(fn, token, "path", string); intrinsic_param(fn, token, "flags", flags); intrinsic_returns(fn, 2, file, error);
    OS_FN("os.read", "neper_os_read"); intrinsic_param(fn, token, "f", file); intrinsic_param(fn, token, "buf", bytes); intrinsic_returns(fn, 2, usize, error);
    OS_FN("os.write", "neper_os_write"); intrinsic_param(fn, token, "f", file); intrinsic_param(fn, token, "buf", const_bytes); intrinsic_returns(fn, 2, usize, error);
    OS_FN("os.close", "neper_os_close"); intrinsic_param(fn, token, "f", file); intrinsic_returns(fn, 1, error, error);
    OS_FN("os.stdout", "neper_os_stdout"); intrinsic_returns(fn, 1, file, error);
    OS_FN("os.stderr", "neper_os_stderr"); intrinsic_returns(fn, 1, file, error);
    OS_FN("os.readdir", "neper_os_readdir"); intrinsic_param(fn, token, "a", arena_pointer); intrinsic_param(fn, token, "path", string); intrinsic_returns(fn, 2, entries, error);
    OS_FN("os.spawn", "neper_os_spawn"); intrinsic_param(fn, token, "a", arena_pointer); intrinsic_param(fn, token, "argv", const_strings); intrinsic_param(fn, token, "stdio", stdio_type); intrinsic_returns(fn, 2, proc, error);
    OS_FN("os.wait", "neper_os_wait"); intrinsic_param(fn, token, "p", proc); intrinsic_returns(fn, 2, i32, error);
    OS_FN("os.exit", "neper_os_exit"); intrinsic_param(fn, token, "code", i32); intrinsic_returns(fn, 0, error, error);
    OS_FN("os.args", "neper_os_args"); intrinsic_param(fn, token, "a", arena_pointer); intrinsic_returns(fn, 2, strings, error);
    OS_FN("os.reserve", "neper_os_reserve"); intrinsic_param(fn, token, "n", usize); intrinsic_returns(fn, 2, byte_pointer, error);
    OS_FN("os.commit", "neper_os_commit"); intrinsic_param(fn, token, "p", byte_pointer); intrinsic_param(fn, token, "n", usize); intrinsic_returns(fn, 1, error, error);
    OS_FN("os.clock", "neper_os_clock"); intrinsic_param(fn, token, "c", clock); intrinsic_returns(fn, 2, i64, error);
#undef OS_FN
}

static Type array_element_type(Type array) {
    if (array.element) return *array.element;
    Type element = type_make(array.element_kind, array.element_name);
    element.is_const = array.element_is_const;
    return element;
}

static Type sequence_element_type(Type sequence) {
    if (sequence.kind == TY_STR) return type_make(TY_INT, "u8");
    if (sequence.kind == TY_ARRAY) return array_element_type(sequence);
    if (sequence.element) return *sequence.element;
    {
        Type element = type_make(sequence.element_kind, sequence.element_name);
        element.is_const = sequence.element_is_const;
        return element;
    }
}

static Expr *parse_expression(Compiler *c);

static Type parse_type(Compiler *c) {
    Type t;
    if (match(c, TK_STAR)) {
        int is_const = match(c, TK_CONST);
        Type inner = parse_type(c);
        t = type_make(TY_POINTER, inner.name);
        t.is_const = is_const;
        type_set_element(&t, inner);
        return t;
    }
    if (match(c, TK_LBRACKET)) {
        if (match(c, TK_RBRACKET)) {
            int is_const = match(c, TK_CONST);
            t = parse_type(c);
            if (is_const && t.kind == TY_INT && strcmp(t.name, "u8") == 0) return type_make(TY_STR, "str");
            {
                Type slice = type_make(TY_SLICE, t.name);
                type_set_element(&slice, t);
                slice.is_const = is_const;
                return slice;
            }
        } else {
            Expr *length_expr = parse_expression(c);
            Type array;
            expect(c, TK_RBRACKET, "expected `]` after array length");
            t = parse_type(c);
            array = type_array(t, 0);
            array.array_length_expr = length_expr;
            return array;
        }
    }
    {
        Token *first = expect(c, TK_IDENT, "expected type name");
        char name[96];
        StructDecl *generic_decl = 0;
        int generic_index;
        copy_text(name, sizeof(name), first->start, (size_t)first->length);
        while (match(c, TK_DOT)) {
            Token *part = expect(c, TK_IDENT, "expected type name after `.`");
            size_t used = strlen(name);
            if (used + 1 < sizeof(name)) name[used++] = '.';
            copy_text(name + used, sizeof(name) - used, part->start, (size_t)part->length);
        }
        for (generic_index = 0; generic_index < c->program.struct_count; ++generic_index)
            if (strcmp(c->program.structs[generic_index].name, name) == 0 &&
                c->program.structs[generic_index].is_template) {
                generic_decl = &c->program.structs[generic_index]; break;
            }
        if (generic_decl && match(c, TK_LBRACKET)) {
            Type generic_type = type_make(TY_NAMED, name);
            if (!check(c, TK_RBRACKET)) {
                do {
                    ComptimeParam *parameter;
                    Type *type_argument;
                    int argument = generic_type.generic_arg_count;
                    if (argument >= MAX_ARGS) {
                        diagnostic_at(c, peek(c), "E-TOOL-9999", "compile-time argument limit exceeded");
                        break;
                    }
                    parameter = argument < generic_decl->comptime_param_count ?
                                &generic_decl->comptime_params[argument] : 0;
                    if (parameter && parameter->is_type) {
                        type_argument = (Type *)calloc(1, sizeof(*type_argument));
                        if (!type_argument) { fputs("neper: out of memory\n", stderr); exit(2); }
                        *type_argument = parse_type(c);
                        generic_type.generic_types[argument] = type_argument;
                        generic_type.generic_is_type[argument] = 1;
                    } else generic_type.generic_values[argument] = parse_expression(c);
                    generic_type.generic_arg_count++;
                } while (match(c, TK_COMMA));
            }
            expect(c, TK_RBRACKET, "expected `]` after compile-time arguments");
            return generic_type;
        }
        if (strcmp(name, "bool") == 0) return type_make(TY_BOOL, name);
        if (strcmp(name, "err") == 0) return type_make(TY_ERR, name);
        if (strcmp(name, "str") == 0) return type_make(TY_STR, name);
        if (strcmp(name, "mem.Arena") == 0) return type_make(TY_ARENA, name);
        if (strcmp(name, "i8") == 0 || strcmp(name, "i16") == 0 ||
            strcmp(name, "i32") == 0 || strcmp(name, "i64") == 0 ||
            strcmp(name, "u8") == 0 || strcmp(name, "u16") == 0 ||
            strcmp(name, "u32") == 0 || strcmp(name, "u64") == 0 ||
            strcmp(name, "isize") == 0 || strcmp(name, "usize") == 0) return type_make(TY_INT, name);
        return type_make(TY_NAMED, name);
    }
}

static Expr *new_expr(ExprKind kind, Token token) {
    Expr *e = (Expr *)calloc(1, sizeof(Expr));
    if (!e) { fputs("neper: out of memory\n", stderr); exit(2); }
    e->kind = kind; e->token = token; e->type = type_make(TY_INVALID, 0);
    e->local_index = -1; e->trap_id = -1; e->error_code = 0;
    return e;
}

static Stmt *new_stmt(StmtKind kind, Token token) {
    Stmt *s = (Stmt *)calloc(1, sizeof(Stmt));
    if (!s) { fputs("neper: out of memory\n", stderr); exit(2); }
    s->kind = kind; s->token = token; s->as.bind.local_index = -1;
    return s;
}

static unsigned char hex_value(char ch) {
    if (ch >= '0' && ch <= '9') return (unsigned char)(ch - '0');
    if (ch >= 'a' && ch <= 'f') return (unsigned char)(ch - 'a' + 10);
    return (unsigned char)(ch - 'A' + 10);
}

static void parse_integer_value(Compiler *c, Token *token, Expr *expr) {
    static const char *suffixes[] = {"usize", "isize", "u64", "u32", "u16", "u8", "i64", "i32", "i16", "i8"};
    char text[128], digits[128];
    size_t length = (size_t)token->length, suffix_length = 0, i, n = 0;
    const char *suffix = 0;
    int base = 10;
    uint64_t value = 0;
    copy_text(text, sizeof(text), token->start, length);
    for (i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); ++i) {
        size_t candidate = strlen(suffixes[i]);
        if (length > candidate && strcmp(text + length - candidate, suffixes[i]) == 0) {
            suffix = suffixes[i]; suffix_length = candidate; break;
        }
    }
    for (i = 0; i < length - suffix_length && n + 1 < sizeof(digits); ++i)
        if (text[i] != '_') digits[n++] = text[i];
    digits[n] = 0;
    i = 0;
    if (n >= 2 && digits[0] == '0') {
        if (digits[1] == 'x' || digits[1] == 'X') { base = 16; i = 2; }
        else if (digits[1] == 'b' || digits[1] == 'B') { base = 2; i = 2; }
        else if (digits[1] == 'o' || digits[1] == 'O') { base = 8; i = 2; }
    }
    if (i == n) diagnostic_at(c, token, "E-LEX-0003", "integer literal has no digits");
    for (; i < n; ++i) {
        unsigned digit;
        if (digits[i] >= '0' && digits[i] <= '9') digit = (unsigned)(digits[i] - '0');
        else if (digits[i] >= 'a' && digits[i] <= 'f') digit = (unsigned)(digits[i] - 'a' + 10);
        else if (digits[i] >= 'A' && digits[i] <= 'F') digit = (unsigned)(digits[i] - 'A' + 10);
        else { diagnostic_at(c, token, "E-LEX-0003", "invalid digit in integer literal"); break; }
        if (digit >= (unsigned)base || value > (UINT64_MAX - digit) / (unsigned)base) {
            diagnostic_at(c, token, "E-TYPE-0004", "integer literal is not representable"); break;
        }
        value = value * (unsigned)base + digit;
    }
    expr->as.integer = (int64_t)value;
    expr->type = suffix ? type_make(TY_INT, suffix) : type_make(TY_UNTYPED_INT, "");
}

static void decode_string(Token *token, unsigned char **out, size_t *out_len) {
    size_t cap = (size_t)token->length + 1, n = 0, i;
    unsigned char *bytes = (unsigned char *)malloc(cap);
    if (!bytes) { fputs("neper: out of memory\n", stderr); exit(2); }
    for (i = 1; i + 1 < (size_t)token->length; ++i) {
        unsigned char ch = (unsigned char)token->start[i];
        if (ch == '\\' && i + 1 < (size_t)token->length - 1) {
            ch = (unsigned char)token->start[++i];
            if (ch == 'n') ch = '\n'; else if (ch == 'r') ch = '\r';
            else if (ch == 't') ch = '\t'; else if (ch == '0') ch = 0;
            else if (ch == 'x' && i + 2 < (size_t)token->length - 1) {
                ch = (unsigned char)((hex_value(token->start[i + 1]) << 4) |
                                     hex_value(token->start[i + 2]));
                i += 2;
            }
        }
        bytes[n++] = ch;
    }
    *out = bytes; *out_len = n;
}

static Expr *parse_expression(Compiler *c);

static void array_add_item(Compiler *c, Expr *array, Expr *item) {
    if (array->as.array.item_count >= MAX_ARRAY_ELEMENTS) {
        diagnostic_at(c, &item->token, "E-TOOL-9999", "array literal element limit exceeded");
        return;
    }
    if (array->as.array.item_count == array->as.array.item_capacity) {
        int capacity = array->as.array.item_capacity ? array->as.array.item_capacity * 2 : 8;
        Expr **items;
        if (capacity > MAX_ARRAY_ELEMENTS) capacity = MAX_ARRAY_ELEMENTS;
        items = (Expr **)realloc(array->as.array.items, (size_t)capacity * sizeof(*items));
        if (!items) { fputs("neper: out of memory\n", stderr); exit(2); }
        array->as.array.items = items;
        array->as.array.item_capacity = capacity;
    }
    array->as.array.items[array->as.array.item_count++] = item;
}

static void aggregate_add_item(Compiler *c, Expr *aggregate, Token *name, Expr *value) {
    StructInit *items;
    StructInit *item;
    if (aggregate->as.aggregate.item_count >= MAX_FIELDS) {
        diagnostic_at(c, name, "E-TOOL-9999", "aggregate literal field limit exceeded");
        return;
    }
    if (aggregate->as.aggregate.item_count == aggregate->as.aggregate.item_capacity) {
        int capacity = aggregate->as.aggregate.item_capacity ?
                       aggregate->as.aggregate.item_capacity * 2 : 8;
        if (capacity > MAX_FIELDS) capacity = MAX_FIELDS;
        items = (StructInit *)realloc(aggregate->as.aggregate.items,
                                     (size_t)capacity * sizeof(*items));
        if (!items) { fputs("neper: out of memory\n", stderr); exit(2); }
        aggregate->as.aggregate.items = items;
        aggregate->as.aggregate.item_capacity = capacity;
    }
    item = &aggregate->as.aggregate.items[aggregate->as.aggregate.item_count++];
    memset(item, 0, sizeof(*item));
    copy_text(item->name, sizeof(item->name), name->start, (size_t)name->length);
    item->token = *name;
    item->value = value;
    item->field_index = -1;
}

static int name_ends_in_type_segment(const char *name) {
    const char *segment = strrchr(name, '.');
    segment = segment ? segment + 1 : name;
    return segment[0] >= 'A' && segment[0] <= 'Z';
}

static int name_is_declared_aggregate(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.struct_count; ++i)
        if (strcmp(c->program.structs[i].name, name) == 0 &&
            c->program.structs[i].kind != ND_ENUM) return 1;
    return 0;
}

static int name_is_declared_error(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.error_count; ++i)
        if (strcmp(c->program.errors[i].name, name) == 0) return 1;
    return 0;
}

static Function *parsed_function_named(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.function_count; ++i)
        if (strcmp(c->program.functions[i].name, name) == 0)
            return &c->program.functions[i];
    return 0;
}

static Expr *parse_primary(Compiler *c) {
    Token *token = peek(c);
    if (match(c, TK_DOT)) {
        Token *member = expect(c, TK_IDENT, "expected enum member after `.`");
        Expr *e = new_expr(EX_ENUM_MEMBER, *token);
        copy_text(e->as.name, sizeof(e->as.name), member->start, (size_t)member->length);
        return e;
    }
    if (match(c, TK_INTEGER)) {
        Expr *e = new_expr(EX_INTEGER, *token);
        parse_integer_value(c, token, e);
        return e;
    }
    if (match(c, TK_STRING)) {
        Expr *e = new_expr(EX_STRING, *token);
        decode_string(token, &e->as.string.bytes, &e->as.string.length);
        e->as.string.label = c->program.string_count;
        if (c->program.string_count < MAX_STRINGS) c->program.strings[c->program.string_count++] = e;
        e->type = type_make(TY_STR, "str");
        return e;
    }
    if (match(c, TK_OK)) {
        Expr *e = new_expr(EX_NAME, *token);
        strcpy(e->as.name, "ok"); e->type = type_make(TY_ERR, "err"); return e;
    }
    if (match(c, TK_TRUE) || match(c, TK_FALSE)) {
        Expr *e = new_expr(EX_INTEGER, *token);
        e->as.integer = token->kind == TK_TRUE ? 1 : 0;
        e->type = type_make(TY_BOOL, "bool"); return e;
    }
    if (match(c, TK_ZERO)) return new_expr(EX_ZERO, *token);
    if (match(c, TK_UNDEF)) return new_expr(EX_UNDEF, *token);
    if (match(c, TK_LBRACKET)) {
        Expr *e = new_expr(EX_ARRAY_LITERAL, *token);
        Type element;
        size_t length = 0;
        Expr *length_expr = 0;
        if (check(c, TK_IDENT) && peek(c)->length == 1 && peek(c)->start[0] == '_') {
            e->as.array.infer_length = 1;
            c->current++;
        } else {
            length_expr = parse_expression(c);
        }
        expect(c, TK_RBRACKET, "expected `]` after array literal length");
        element = parse_type(c);
        expect(c, TK_LBRACE, "expected `{` in array literal");
        skip_newlines(c);
        if (!check(c, TK_RBRACE)) {
            for (;;) {
                skip_newlines(c);
                array_add_item(c, e, parse_expression(c));
                skip_newlines(c);
                if (!match(c, TK_COMMA)) break;
                skip_newlines(c);
                if (check(c, TK_RBRACE)) break;
            }
        }
        expect(c, TK_RBRACE, "expected `}` after array literal");
        if (e->as.array.infer_length) length = (size_t)e->as.array.item_count;
        e->type = type_array(element, length);
        e->type.array_length_expr = length_expr;
        return e;
    }
    if (match(c, TK_LPAREN)) {
        Expr *e = parse_expression(c);
        expect(c, TK_RPAREN, "expected `)` after expression");
        return e;
    }
    if (match(c, TK_IDENT)) {
        Expr *e;
        char name[160];
        Function *generic_function;
        Type generic_types[MAX_ARGS];
        Expr *generic_values[MAX_ARGS] = {0};
        unsigned char generic_is_type[MAX_ARGS] = {0};
        int generic_arg_count = 0;
        Type generic_struct_type;
        int has_generic_struct = 0;
        memset(generic_types, 0, sizeof(generic_types));
        memset(&generic_struct_type, 0, sizeof(generic_struct_type));
        copy_text(name, sizeof(name), token->start, (size_t)token->length);
        while (match(c, TK_DOT)) {
            Token *part = expect(c, TK_IDENT, "expected name after `.`");
            size_t used = strlen(name);
            if (used + 1 < sizeof(name)) name[used++] = '.';
            copy_text(name + used, sizeof(name) - used, part->start, (size_t)part->length);
        }
        generic_function = parsed_function_named(c, name);
        if (generic_function && generic_function->is_template && match(c, TK_LBRACKET)) {
            if (!check(c, TK_RBRACKET)) {
                do {
                    ComptimeParam *parameter;
                    if (generic_arg_count >= MAX_ARGS) {
                        diagnostic_at(c, peek(c), "E-TOOL-9999", "compile-time argument limit exceeded");
                        break;
                    }
                    parameter = generic_arg_count < generic_function->comptime_param_count ?
                                &generic_function->comptime_params[generic_arg_count] : 0;
                    if (parameter && parameter->is_type) {
                        generic_is_type[generic_arg_count] = 1;
                        generic_types[generic_arg_count] = parse_type(c);
                    } else {
                        generic_values[generic_arg_count] = parse_expression(c);
                    }
                    generic_arg_count++;
                } while (match(c, TK_COMMA));
            }
            expect(c, TK_RBRACKET, "expected `]` after compile-time arguments");
        }
        if (!generic_function && check(c, TK_LBRACKET)) {
            StructDecl *generic_decl = 0;
            int declaration_index;
            for (declaration_index = 0; declaration_index < c->program.struct_count; ++declaration_index)
                if (strcmp(c->program.structs[declaration_index].name, name) == 0 &&
                    c->program.structs[declaration_index].is_template) {
                    generic_decl = &c->program.structs[declaration_index]; break;
                }
            if (generic_decl) {
                match(c, TK_LBRACKET);
                generic_struct_type = type_make(TY_NAMED, name);
                while (!check(c, TK_RBRACKET)) {
                    int argument = generic_struct_type.generic_arg_count;
                    ComptimeParam *parameter = argument < generic_decl->comptime_param_count ?
                                                &generic_decl->comptime_params[argument] : 0;
                    if (argument >= MAX_ARGS) break;
                    if (parameter && parameter->is_type) {
                        Type *stored = (Type *)calloc(1, sizeof(*stored));
                        if (!stored) { fputs("neper: out of memory\n", stderr); exit(2); }
                        *stored = parse_type(c);
                        generic_struct_type.generic_types[argument] = stored;
                        generic_struct_type.generic_is_type[argument] = 1;
                    } else generic_struct_type.generic_values[argument] = parse_expression(c);
                    generic_struct_type.generic_arg_count++;
                    if (!match(c, TK_COMMA)) break;
                }
                expect(c, TK_RBRACKET, "expected `]` after generic type arguments");
                has_generic_struct = 1;
            }
        }
        if ((has_generic_struct || name_ends_in_type_segment(name)) &&
            (name_is_declared_aggregate(c, name) ||
             has_generic_struct || (strchr(name, '.') == 0 && !name_is_declared_error(c, name))) &&
            match(c, TK_LBRACE)) {
            e = new_expr(EX_STRUCT_LITERAL, *token);
            if (has_generic_struct) e->type = generic_struct_type;
            copy_text(e->as.aggregate.type_name, sizeof(e->as.aggregate.type_name),
                      name, strlen(name));
            skip_newlines(c);
            if (!check(c, TK_RBRACE)) {
                for (;;) {
                    Token *field = expect(c, TK_IDENT, "expected member name in aggregate literal");
                    Expr *value = 0;
                    if (match(c, TK_COLON)) value = parse_expression(c);
                    aggregate_add_item(c, e, field, value);
                    skip_newlines(c);
                    if (!match(c, TK_COMMA)) break;
                    skip_newlines(c);
                    if (check(c, TK_RBRACE)) break;
                }
            }
            expect(c, TK_RBRACE, "expected `}` after aggregate literal");
        } else if (match(c, TK_LPAREN)) {
            e = new_expr(EX_CALL, *token);
            strcpy(e->as.call.callee, name);
            e->as.call.generic_arg_count = generic_arg_count;
            if (generic_arg_count) {
                int generic_index;
                for (generic_index = 0; generic_index < generic_arg_count; ++generic_index) {
                    e->as.call.generic_is_type[generic_index] = generic_is_type[generic_index];
                    e->as.call.generic_types[generic_index] = generic_types[generic_index];
                    e->as.call.generic_values[generic_index] = generic_values[generic_index];
                }
            }
            if (!check(c, TK_RPAREN)) {
                do {
                    if (e->as.call.arg_count >= MAX_ARGS) {
                        diagnostic_at(c, peek(c), "E-SYNTAX-9999", "too many call arguments");
                        break;
                    }
                    e->as.call.args[e->as.call.arg_count++] = parse_expression(c);
                } while (match(c, TK_COMMA));
            }
            expect(c, TK_RPAREN, "expected `)` after arguments");
        } else {
            if (generic_arg_count)
                diagnostic_at(c, token, "E-SYNTAX-9999",
                              "generic function arguments must be followed by a call");
            e = new_expr(EX_NAME, *token); strcpy(e->as.name, name);
        }
        for (;;) {
            if (match(c, TK_LBRACKET)) {
                Expr *first = 0;
                if (!check(c, TK_RANGE)) first = parse_expression(c);
                if (match(c, TK_RANGE)) {
                    Expr *sliced = new_expr(EX_SLICE, *token);
                    sliced->as.slice.base = e;
                    sliced->as.slice.start = first;
                    if (!check(c, TK_RBRACKET)) sliced->as.slice.end = parse_expression(c);
                    expect(c, TK_RBRACKET, "expected `]` after slice");
                    e = sliced;
                } else {
                    Expr *indexed = new_expr(EX_INDEX, *token);
                    indexed->as.index.base = e;
                    indexed->as.index.index = first;
                    expect(c, TK_RBRACKET, "expected `]` after index");
                    e = indexed;
                }
            } else if (match(c, TK_DOT)) {
                Token *field_name = expect(c, TK_IDENT, "expected field name after `.`");
                Expr *field = new_expr(EX_FIELD, *field_name);
                field->as.field.base = e;
                copy_text(field->as.field.name, sizeof(field->as.field.name),
                          field_name->start, (size_t)field_name->length);
                e = field;
            } else break;
        }
        return e;
    }
    diagnostic_at(c, token, "E-SYNTAX-9999", "expected expression");
    if (token->kind != TK_EOF) c->current++;
    return new_expr(EX_INTEGER, *token);
}

static Expr *parse_unary(Compiler *c) {
    Token *token = peek(c);
    if (match(c, TK_MINUS) || match(c, TK_BANG) ||
        match(c, TK_AMP) || match(c, TK_STAR)) {
        Expr *e = new_expr(EX_UNARY, *token);
        e->as.unary.op = token->kind;
        e->as.unary.value = parse_unary(c);
        return e;
    }
    return parse_primary(c);
}

static Expr *parse_factor(Compiler *c) {
    Expr *e = parse_unary(c);
    while (check(c, TK_STAR) || check(c, TK_SLASH) || check(c, TK_PERCENT)) {
        Token *op = peek(c); c->current++;
        { Expr *b = new_expr(EX_BINARY, *op); b->as.binary.op = op->kind;
          b->as.binary.left = e; b->as.binary.right = parse_unary(c); e = b; }
    }
    return e;
}

static Expr *parse_term(Compiler *c) {
    Expr *e = parse_factor(c);
    while (check(c, TK_PLUS) || check(c, TK_MINUS)) {
        Token *op = peek(c); c->current++;
        { Expr *b = new_expr(EX_BINARY, *op); b->as.binary.op = op->kind;
          b->as.binary.left = e; b->as.binary.right = parse_factor(c); e = b; }
    }
    return e;
}

static Expr *parse_compare(Compiler *c) {
    Expr *e = parse_term(c);
    if (check(c, TK_EQ) || check(c, TK_NE) || check(c, TK_LT) || check(c, TK_LE) ||
        check(c, TK_GT) || check(c, TK_GE)) {
        Token *op = peek(c); c->current++;
        { Expr *b = new_expr(EX_BINARY, *op); b->as.binary.op = op->kind;
          b->as.binary.left = e; b->as.binary.right = parse_term(c); e = b; }
    }
    return e;
}

static Expr *parse_logical_and(Compiler *c) {
    Expr *e = parse_compare(c);
    while (check(c, TK_AND)) {
        Token *op = peek(c); c->current++;
        { Expr *b = new_expr(EX_BINARY, *op); b->as.binary.op = op->kind;
          b->as.binary.left = e; b->as.binary.right = parse_compare(c); e = b; }
    }
    return e;
}

static Expr *parse_expression(Compiler *c) {
    Expr *e = parse_logical_and(c);
    while (check(c, TK_OR)) {
        Token *op = peek(c); c->current++;
        { Expr *b = new_expr(EX_BINARY, *op); b->as.binary.op = op->kind;
          b->as.binary.left = e; b->as.binary.right = parse_logical_and(c); e = b; }
    }
    return e;
}

static Stmt *parse_block(Compiler *c);
static Stmt *parse_statement(Compiler *c);
static Stmt *parse_switch_statement(Compiler *c, Token token);

static Stmt *parse_statement(Compiler *c) {
    Token *token = peek(c);
    if (match(c, TK_LET) || match(c, TK_VAR)) {
        int is_mutable = token->kind == TK_VAR;
        if (match(c, TK_LPAREN)) {
            Stmt *s = new_stmt(ST_MULTI_BIND, *token);
            s->as.multi.is_mutable = is_mutable;
            do {
                Token *name;
                if (s->as.multi.count >= MAX_ARGS) {
                    diagnostic_at(c, peek(c), "E-TOOL-9999", "multiple binding limit exceeded");
                    break;
                }
                name = expect(c, TK_IDENT, "expected name in multiple binding");
                copy_text(s->as.multi.names[s->as.multi.count],
                          sizeof(s->as.multi.names[s->as.multi.count]),
                          name->start, (size_t)name->length);
                s->as.multi.local_indices[s->as.multi.count++] = -1;
            } while (match(c, TK_COMMA));
            expect(c, TK_RPAREN, "expected `)` after multiple binding");
            if (s->as.multi.count < 2)
                diagnostic_at(c, token, "E-SYNTAX-9999", "multiple binding requires at least two names");
            expect(c, TK_ASSIGN, "expected `=` after multiple binding");
            s->as.multi.call = parse_expression(c);
            return s;
        }
        {
        Token *name = expect(c, TK_IDENT, "expected binding name");
        Stmt *s = new_stmt(ST_BIND, *token);
        copy_text(s->as.bind.name, sizeof(s->as.bind.name), name->start, (size_t)name->length);
        s->as.bind.is_mutable = is_mutable;
        if (match(c, TK_COLON)) s->as.bind.declared_type = parse_type(c);
        else s->as.bind.declared_type = type_make(TY_INVALID, 0);
        expect(c, TK_ASSIGN, "expected `=` in binding");
        s->as.bind.value = parse_expression(c);
        return s;
        }
    }
    if (match(c, TK_RET)) {
        Stmt *s = new_stmt(ST_RETURN, *token);
        if (!check(c, TK_NEWLINE) && !check(c, TK_RBRACE)) {
            if (match(c, TK_LPAREN)) {
                do {
                    if (s->as.ret.value_count >= MAX_ARGS) {
                        diagnostic_at(c, peek(c), "E-TOOL-9999", "return value limit exceeded");
                        break;
                    }
                    s->as.ret.values[s->as.ret.value_count++] = parse_expression(c);
                } while (match(c, TK_COMMA) && !check(c, TK_RPAREN));
                expect(c, TK_RPAREN, "expected `)` after return values");
            } else s->as.ret.values[s->as.ret.value_count++] = parse_expression(c);
            if (s->as.ret.value_count) s->as.ret.value = s->as.ret.values[0];
        }
        return s;
    }
    if (match(c, TK_TRY)) {
        Stmt *s = new_stmt(ST_TRY, *token); s->as.expr = parse_expression(c); return s;
    }
    if (match(c, TK_IF)) {
        Stmt *s = new_stmt(ST_IF, *token);
        s->as.if_stmt.condition = parse_expression(c);
        s->as.if_stmt.then_body = parse_block(c);
        if (match(c, TK_ELSE)) s->as.if_stmt.else_body = parse_block(c);
        return s;
    }
    if (match(c, TK_WHILE)) {
        Stmt *s = new_stmt(ST_WHILE, *token);
        s->as.while_stmt.condition = parse_expression(c);
        s->as.while_stmt.body = parse_block(c);
        return s;
    }
    if (match(c, TK_SWITCH)) return parse_switch_statement(c, *token);
    if (match(c, TK_DEFER)) {
        Stmt *s = new_stmt(ST_DEFER, *token);
        if (check(c, TK_LBRACE)) {
            s->as.defer_stmt.is_block = 1;
            s->as.defer_stmt.body = parse_block(c);
        } else {
            Stmt *body = parse_statement(c);
            s->as.defer_stmt.body = body;
            if (!(body->kind == ST_BIND || body->kind == ST_ASSIGN ||
                  body->kind == ST_INDEX_ASSIGN || body->kind == ST_EXPR))
                diagnostic_at(c, &body->token, "E-SYNTAX-9999",
                              "defer single-statement form requires a binding, assignment, or call");
            if (body->kind == ST_EXPR && body->as.expr->kind != EX_CALL)
                diagnostic_at(c, &body->token, "E-SYNTAX-9999",
                              "defer expression statement must be a call");
        }
        return s;
    }
    if (match(c, TK_FOR)) {
        Token *first = expect(c, TK_IDENT, "expected binding after `for`");
        Token *second = 0;
        Expr *subject;
        if (match(c, TK_COMMA)) second = expect(c, TK_IDENT, "expected value binding after `,`");
        expect(c, TK_IN, "expected `in` after for binding");
        subject = parse_expression(c);
        if (match(c, TK_RANGE)) {
            Stmt *s = new_stmt(ST_FOR_RANGE, *token);
            if (second)
                diagnostic_at(c, second, "E-SYNTAX-9999", "a range loop has exactly one binding");
            copy_text(s->as.for_range.name, sizeof(s->as.for_range.name),
                      first->start, (size_t)first->length);
            s->as.for_range.local_index = -1;
            s->as.for_range.end_local_index = -1;
            s->as.for_range.start = subject;
            s->as.for_range.end = parse_expression(c);
            s->as.for_range.body = parse_block(c);
            return s;
        } else {
            Stmt *s = new_stmt(ST_FOR_EACH, *token);
            s->as.for_each.pointer_local_index = -1;
            s->as.for_each.length_local_index = -1;
            s->as.for_each.index_local_index = -1;
            s->as.for_each.value_local_index = -1;
            s->as.for_each.iterator_pointer_local_index = -1;
            s->as.for_each.iterator_has_local_index = -1;
            s->as.for_each.has_index = second != 0;
            if (second) {
                copy_text(s->as.for_each.index_name, sizeof(s->as.for_each.index_name),
                          first->start, (size_t)first->length);
                copy_text(s->as.for_each.value_name, sizeof(s->as.for_each.value_name),
                          second->start, (size_t)second->length);
            } else {
                copy_text(s->as.for_each.value_name, sizeof(s->as.for_each.value_name),
                          first->start, (size_t)first->length);
            }
            s->as.for_each.subject = subject;
            s->as.for_each.body = parse_block(c);
            return s;
        }
    }
    if (match(c, TK_BREAK)) return new_stmt(ST_BREAK, *token);
    if (match(c, TK_CONTINUE)) return new_stmt(ST_CONTINUE, *token);
    if (check(c, TK_LPAREN)) {
        int saved = c->current;
        int count = 0;
        c->current++;
        while (check(c, TK_IDENT)) {
            count++;
            c->current++;
            if (!match(c, TK_COMMA)) break;
        }
        if (count >= 2 && match(c, TK_RPAREN) && match(c, TK_ASSIGN)) {
            Stmt *s = new_stmt(ST_MULTI_ASSIGN, *token);
            int i;
            c->current = saved + 1;
            for (i = 0; i < count; ++i) {
                Token *name = expect(c, TK_IDENT, "expected name in multiple assignment");
                copy_text(s->as.multi.names[i], sizeof(s->as.multi.names[i]),
                          name->start, (size_t)name->length);
                s->as.multi.local_indices[i] = -1;
                if (i + 1 < count) expect(c, TK_COMMA, "expected `,` in multiple assignment");
            }
            s->as.multi.count = count;
            expect(c, TK_RPAREN, "expected `)` after multiple assignment");
            expect(c, TK_ASSIGN, "expected `=` after multiple assignment");
            s->as.multi.call = parse_expression(c);
            return s;
        }
        c->current = saved;
    }
    {
        Expr *left = parse_expression(c);
        if (check(c, TK_ASSIGN) || check(c, TK_ADD_ASSIGN)) {
            TokenKind op = peek(c)->kind;
            Expr *value;
            c->current++;
            value = parse_expression(c);
            if (left->kind == EX_NAME) {
                Stmt *s = new_stmt(ST_ASSIGN, left->token);
                copy_text(s->as.assign.name, sizeof(s->as.assign.name),
                          left->as.name, strlen(left->as.name));
                s->as.assign.target = left;
                s->as.assign.value = value;
                s->as.assign.local_index = -1;
                s->as.assign.op = op;
                return s;
            }
            if (left->kind == EX_INDEX || left->kind == EX_FIELD ||
                (left->kind == EX_UNARY && left->as.unary.op == TK_STAR)) {
                Stmt *s = new_stmt(ST_INDEX_ASSIGN, left->token);
                s->as.index_assign.target = left;
                s->as.index_assign.value = value;
                s->as.index_assign.op = op;
                return s;
            }
            diagnostic_at(c, &left->token, "E-TYPE-9999", "assignment target is not a place");
            return new_stmt(ST_EXPR, left->token);
        }
        { Stmt *s = new_stmt(ST_EXPR, *token); s->as.expr = left; return s; }
    }
}

static Stmt *parse_case_body(Compiler *c) {
    Stmt *head = 0, **tail = &head;
    skip_newlines(c);
    while (!check(c, TK_CASE) && !check(c, TK_DEFAULT) &&
           !check(c, TK_RBRACE) && !check(c, TK_EOF)) {
        Stmt *s = parse_statement(c);
        *tail = s; tail = &s->next;
        if (!check(c, TK_CASE) && !check(c, TK_DEFAULT) && !check(c, TK_RBRACE))
            expect(c, TK_NEWLINE, "expected newline after statement");
        skip_newlines(c);
    }
    return head;
}

static Stmt *parse_switch_statement(Compiler *c, Token token) {
    Stmt *s = new_stmt(ST_SWITCH, token);
    SwitchCase **tail = &s->as.switch_stmt.cases;
    s->as.switch_stmt.subject = parse_expression(c);
    expect(c, TK_LBRACE, "expected `{` after switch subject");
    skip_newlines(c);
    while (!check(c, TK_RBRACE) && !check(c, TK_EOF)) {
        SwitchCase *arm = (SwitchCase *)calloc(1, sizeof(*arm));
        if (!arm) { fputs("neper: out of memory\n", stderr); exit(2); }
        arm->local_index = -1; arm->member_index = -1;
        arm->token = *peek(c);
        if (match(c, TK_DEFAULT)) arm->is_default = 1;
        else {
            expect(c, TK_CASE, "expected `case` or `default` in switch");
            do {
                if (arm->value_count >= MAX_ARGS) {
                    diagnostic_at(c, peek(c), "E-TOOL-9999", "switch case value limit exceeded");
                    break;
                }
                arm->values[arm->value_count++] = parse_expression(c);
            } while (match(c, TK_COMMA));
            if (match(c, TK_AS)) {
                Token *binding = expect(c, TK_IDENT, "expected payload binding after `as`");
                copy_text(arm->binding, sizeof(arm->binding), binding->start, (size_t)binding->length);
            }
        }
        expect(c, TK_COLON, "expected `:` after switch case");
        expect(c, TK_NEWLINE, "switch case body must start on the next line");
        arm->body = parse_case_body(c);
        *tail = arm; tail = &arm->next;
    }
    expect(c, TK_RBRACE, "expected `}` after switch cases");
    return s;
}

static Stmt *parse_block(Compiler *c) {
    Stmt *head = 0, **tail = &head;
    expect(c, TK_LBRACE, "expected `{`");
    skip_newlines(c);
    while (!check(c, TK_RBRACE) && !check(c, TK_EOF)) {
        Stmt *s = parse_statement(c);
        *tail = s; tail = &s->next;
        if (!check(c, TK_RBRACE)) expect(c, TK_NEWLINE, "expected newline after statement");
        skip_newlines(c);
    }
    expect(c, TK_RBRACE, "expected `}`");
    return head;
}

static void qualify_decl_name(Compiler *c, char *out, size_t capacity,
                              const char *name, Token *token) {
    if (!c->current_module[0]) {
        copy_text(out, capacity, name, strlen(name));
        return;
    }
    if (strlen(c->current_module) + strlen(name) + 2 > capacity) {
        diagnostic_at(c, token, "E-MODULE-9999", "qualified declaration name is too long");
        copy_text(out, capacity, name, strlen(name));
        return;
    }
    join_qualified_name(out, capacity, c->current_module, name);
}

static void parse_use(Compiler *c, Token token) {
    UseDecl *use;
    char name[160], qualifier[96];
    Token *part = expect(c, TK_IDENT, "expected module name after `use`");
    copy_text(name, sizeof(name), part->start, (size_t)part->length);
    while (match(c, TK_DOT)) {
        size_t used = strlen(name);
        part = expect(c, TK_IDENT, "expected module name after `.`");
        if (used + 1 < sizeof(name)) name[used++] = '.';
        copy_text(name + used, sizeof(name) - used, part->start, (size_t)part->length);
    }
    {
        const char *last = strrchr(name, '.');
        copy_text(qualifier, sizeof(qualifier), last ? last + 1 : name,
                  strlen(last ? last + 1 : name));
    }
    if (match(c, TK_AS)) {
        Token *alias = expect(c, TK_IDENT, "expected qualifier after `as`");
        copy_text(qualifier, sizeof(qualifier), alias->start, (size_t)alias->length);
    }
    if (c->program.use_count >= MAX_USES) {
        diagnostic_at(c, &token, "E-MODULE-9999", "too many imports"); return;
    }
    use = &c->program.uses[c->program.use_count++];
    memset(use, 0, sizeof(*use)); strcpy(use->name, name);
    strcpy(use->qualifier, qualifier); use->token = token;
    copy_text(use->owner_module, sizeof(use->owner_module), c->current_module,
              strlen(c->current_module));
}

static void parse_error(Compiler *c, Token token) {
    ErrorDecl *error;
    Token *name = expect(c, TK_IDENT, "expected error name");
    if (c->program.error_count >= MAX_DECLS) {
        diagnostic_at(c, &token, "E-ERROR-9999", "too many error declarations"); return;
    }
    error = &c->program.errors[c->program.error_count];
    memset(error, 0, sizeof(*error));
    copy_text(error->name, sizeof(error->name), name->start, (size_t)name->length);
    copy_text(error->module, sizeof(error->module), c->current_module,
              strlen(c->current_module));
    error->token = token;
    error->code = c->program.error_count + 2;
    c->program.error_count++;
}

static void parse_constant(Compiler *c, Token token) {
    ConstDecl *constant;
    Token *name = expect(c, TK_IDENT, "expected constant name");
    if (c->program.constant_count >= MAX_DECLS) {
        diagnostic_at(c, &token, "E-TOOL-9999", "too many constant declarations");
        return;
    }
    constant = &c->program.constants[c->program.constant_count++];
    memset(constant, 0, sizeof(*constant));
    {
        char short_name[96];
        copy_text(short_name, sizeof(short_name), name->start, (size_t)name->length);
        qualify_decl_name(c, constant->name, sizeof(constant->name), short_name, name);
    }
    copy_text(constant->module, sizeof(constant->module), c->current_module,
              strlen(c->current_module));
    constant->token = token;
    expect(c, TK_COLON, "expected `:` after constant name");
    constant->type = parse_type(c);
    expect(c, TK_ASSIGN, "expected `=` in constant declaration");
    constant->value = parse_expression(c);
}

static void parse_type_declaration(Compiler *c, Token token) {
    StructDecl *decl;
    Token *name = expect(c, TK_IDENT, "expected type name");
    if (c->program.struct_count >= MAX_DECLS) {
        diagnostic_at(c, &token, "E-TYPE-9999", "too many type declarations");
        return;
    }
    decl = &c->program.structs[c->program.struct_count++];
    memset(decl, 0, sizeof(*decl));
    {
        char short_name[96];
        copy_text(short_name, sizeof(short_name), name->start, (size_t)name->length);
        qualify_decl_name(c, decl->name, sizeof(decl->name), short_name, name);
    }
    copy_text(decl->module, sizeof(decl->module), c->current_module,
              strlen(c->current_module));
    decl->token = token;
    if (match(c, TK_LBRACKET)) {
        decl->is_template = 1;
        do {
            ComptimeParam *parameter;
            Token *parameter_name;
            if (decl->comptime_param_count >= MAX_ARGS) {
                diagnostic_at(c, peek(c), "E-TOOL-9999", "compile-time parameter limit exceeded");
                break;
            }
            parameter = &decl->comptime_params[decl->comptime_param_count++];
            parameter_name = expect(c, TK_IDENT, "expected compile-time parameter name");
            parameter->token = *parameter_name;
            copy_text(parameter->name, sizeof(parameter->name), parameter_name->start,
                      (size_t)parameter_name->length);
            expect(c, TK_COLON, "expected `:` after compile-time parameter name");
            if (match(c, TK_TYPE)) parameter->is_type = 1;
            else parameter->value_type = parse_type(c);
        } while (match(c, TK_COMMA));
        expect(c, TK_RBRACKET, "expected `]` after compile-time parameters");
    }
    expect(c, TK_ASSIGN, "expected `=` after type name");
    if (match(c, TK_STRUCT)) decl->kind = ND_STRUCT;
    else if (match(c, TK_UNION)) {
        if (match(c, TK_ENUM)) {
            decl->kind = ND_TAGGED_UNION;
            decl->backing_type = parse_type(c);
        } else decl->kind = ND_UNION;
    } else if (match(c, TK_ENUM)) {
        decl->kind = ND_ENUM;
        decl->backing_type = parse_type(c);
    } else {
        diagnostic_at(c, peek(c), "E-SYNTAX-9999", "expected `struct`, `union`, or `enum` after `=`");
    }
    expect(c, TK_LBRACE, "expected `{` after type declaration");
    skip_newlines(c);
    while (!check(c, TK_RBRACE) && !check(c, TK_EOF)) {
        FieldDecl *field;
        Token *field_name;
        if (decl->field_count >= MAX_FIELDS) {
            diagnostic_at(c, peek(c), "E-TOOL-9999", "type member limit exceeded");
            break;
        }
        field = &decl->fields[decl->field_count++];
        memset(field, 0, sizeof(*field));
        field_name = expect(c, TK_IDENT, "expected type member name");
        copy_text(field->name, sizeof(field->name), field_name->start,
                  (size_t)field_name->length);
        field->token = *field_name;
        if (decl->kind == ND_ENUM) {
            if (match(c, TK_ASSIGN)) {
                int negative = match(c, TK_MINUS);
                Token *value_token = expect(c, TK_INTEGER, "enum value must be an integer literal");
                Expr value_expr;
                memset(&value_expr, 0, sizeof(value_expr));
                parse_integer_value(c, value_token, &value_expr);
                field->value = negative ? -value_expr.as.integer : value_expr.as.integer;
            } else if (decl->field_count == 1) field->value = 0;
            else if (decl->fields[decl->field_count - 2].value == INT64_MAX) {
                diagnostic_at(c, field_name, "E-TYPE-0004", "implicit enum member value overflows");
                field->value = INT64_MAX;
            } else field->value = decl->fields[decl->field_count - 2].value + 1;
            field->type = decl->backing_type;
        } else if (decl->kind == ND_TAGGED_UNION) {
            field->value = decl->field_count - 1;
            field->has_payload = match(c, TK_COLON);
            field->type = field->has_payload ? parse_type(c) : type_make(TY_VOID, "void");
        } else {
            expect(c, TK_COLON, "expected `:` after aggregate field name");
            field->has_payload = 1;
            field->type = parse_type(c);
        }
        skip_newlines(c);
        if (!match(c, TK_COMMA)) {
            if (!check(c, TK_RBRACE))
                diagnostic_at(c, peek(c), "E-SYNTAX-9999", "expected `,` after type member");
            break;
        }
        skip_newlines(c);
    }
    expect(c, TK_RBRACE, "expected `}` after type members");
}

static void parse_function(Compiler *c, Token token) {
    Function *fn;
    Token *name;
    if (c->program.function_count >= MAX_DECLS) {
        diagnostic_at(c, &token, "E-NAME-9999", "too many functions"); return;
    }
    fn = &c->program.functions[c->program.function_count++];
    memset(fn, 0, sizeof(*fn)); fn->token = token;
    fn->return_slot_local_index = -1;
    fn->scalar_return_local_index = -1;
    { int i; for (i = 0; i < MAX_ARGS; ++i) fn->return_value_locals[i] = -1; }
    name = expect(c, TK_IDENT, "expected function name");
    {
        char short_name[96];
        size_t at;
        copy_text(short_name, sizeof(short_name), name->start, (size_t)name->length);
        qualify_decl_name(c, fn->name, sizeof(fn->name), short_name, name);
        copy_text(fn->module, sizeof(fn->module), c->current_module,
                  strlen(c->current_module));
        if (!c->current_module[0] && strcmp(short_name, "main") == 0) strcpy(fn->symbol, "neper_main");
        else {
            strcpy(fn->symbol, "neper_fn_");
            for (at = 0; fn->name[at] && strlen(fn->symbol) + 2 < sizeof(fn->symbol); ++at) {
                size_t used = strlen(fn->symbol);
                char ch = fn->name[at];
                fn->symbol[used] = ch == '.' ? '_' : ch;
                fn->symbol[used + 1] = 0;
            }
        }
    }
    if (match(c, TK_LBRACKET)) {
        fn->is_template = 1;
        do {
            ComptimeParam *parameter;
            Token *parameter_name;
            if (fn->comptime_param_count >= MAX_ARGS) {
                diagnostic_at(c, peek(c), "E-TOOL-9999", "compile-time parameter limit exceeded");
                break;
            }
            parameter = &fn->comptime_params[fn->comptime_param_count++];
            memset(parameter, 0, sizeof(*parameter));
            parameter_name = expect(c, TK_IDENT, "expected compile-time parameter name");
            parameter->token = *parameter_name;
            copy_text(parameter->name, sizeof(parameter->name), parameter_name->start,
                      (size_t)parameter_name->length);
            expect(c, TK_COLON, "expected `:` after compile-time parameter name");
            if (match(c, TK_TYPE)) parameter->is_type = 1;
            else parameter->value_type = parse_type(c);
        } while (match(c, TK_COMMA));
        expect(c, TK_RBRACKET, "expected `]` after compile-time parameters");
    }
    expect(c, TK_LPAREN, "expected `(` after function name");
    if (!check(c, TK_RPAREN)) {
        do {
            Param *p;
            Token *pn;
            if (fn->param_count >= MAX_PARAMS) {
                diagnostic_at(c, peek(c), "E-SYNTAX-9999", "too many parameters"); break;
            }
            p = &fn->params[fn->param_count++];
            memset(p, 0, sizeof(*p));
            pn = expect(c, TK_IDENT, "expected parameter name"); p->token = *pn;
            copy_text(p->name, sizeof(p->name), pn->start, (size_t)pn->length);
            expect(c, TK_COLON, "expected `:` after parameter name");
            p->type = parse_type(c);
        } while (match(c, TK_COMMA));
    }
    expect(c, TK_RPAREN, "expected `)` after parameters");
    if (match(c, TK_ARROW)) {
        if (match(c, TK_LPAREN)) {
            do {
                if (fn->return_count >= MAX_ARGS) {
                    diagnostic_at(c, peek(c), "E-TOOL-9999", "return type limit exceeded");
                    break;
                }
                fn->return_types[fn->return_count++] = parse_type(c);
            } while (match(c, TK_COMMA) && !check(c, TK_RPAREN));
            expect(c, TK_RPAREN, "expected `)` after return types");
            if (fn->return_count < 2)
                diagnostic_at(c, &token, "E-SYNTAX-9999", "parenthesized return signature requires at least two types");
            fn->return_type = fn->return_count ? fn->return_types[0] : type_make(TY_INVALID, 0);
        } else {
            fn->return_type = parse_type(c);
            fn->return_types[0] = fn->return_type;
            fn->return_count = 1;
        }
    } else fn->return_type = type_make(TY_VOID, "void");
    fn->body = parse_block(c);
}

static void parse_program(Compiler *c) {
    skip_newlines(c);
    while (!check(c, TK_EOF)) {
        Token token = *peek(c);
        if (match(c, TK_USE)) parse_use(c, token);
        else if (match(c, TK_TYPE)) parse_type_declaration(c, token);
        else if (match(c, TK_ERROR)) parse_error(c, token);
        else if (match(c, TK_CONST)) parse_constant(c, token);
        else if (match(c, TK_FN)) parse_function(c, token);
        else {
            diagnostic_at(c, peek(c), "E-SYNTAX-9999",
                          "the bootstrap currently supports top-level `use`, `type`, `error`, `const`, and `fn`");
            while (!check(c, TK_NEWLINE) && !check(c, TK_EOF)) c->current++;
        }
        if (!check(c, TK_EOF)) expect(c, TK_NEWLINE, "expected newline after declaration");
        skip_newlines(c);
    }
}

static int type_equal(Type a, Type b) {
    if (a.kind == b.kind) {
        if (a.kind == TY_ARRAY)
            return a.array_length == b.array_length &&
                   type_equal(array_element_type(a), array_element_type(b));
        if (a.kind == TY_POINTER || a.kind == TY_SLICE) {
            if (a.is_const != b.is_const) return 0;
            if (a.element && b.element) return type_equal(*a.element, *b.element);
            return a.element_kind == b.element_kind &&
                   strcmp(a.element_name, b.element_name) == 0 &&
                   a.element_is_const == b.element_is_const;
        }
        if (a.kind == TY_NAMED || a.kind == TY_INT)
            return strcmp(a.name, b.name) == 0 && a.is_const == b.is_const;
        return 1;
    }
    return 0;
}

static int type_assignable(Type actual, Type expected) {
    if (type_equal(actual, expected)) return 1;
    if ((actual.kind == TY_POINTER || actual.kind == TY_SLICE) &&
        actual.kind == expected.kind && !actual.is_const && expected.is_const) {
        if (actual.element && expected.element)
            return type_equal(*actual.element, *expected.element);
        if (actual.element_kind == expected.element_kind &&
            strcmp(actual.element_name, expected.element_name) == 0)
            return 1;
    }
    return 0;
}

static int type_lanes(Type t) { return (t.kind == TY_STR || t.kind == TY_SLICE) ? 2 : (t.kind == TY_VOID ? 0 : 1); }

static int type_is_value_aggregate(Compiler *c, Type t);

static size_t scalar_byte_size(Type type) {
    if (type.kind == TY_BOOL) return 1;
    if (type.kind == TY_ERR) return 4;
    if (type.kind == TY_INT) {
        if (strcmp(type.name, "i8") == 0 || strcmp(type.name, "u8") == 0) return 1;
        if (strcmp(type.name, "i16") == 0 || strcmp(type.name, "u16") == 0) return 2;
        if (strcmp(type.name, "i32") == 0 || strcmp(type.name, "u32") == 0) return 4;
        return 8;
    }
    if (type.kind == TY_STR || type.kind == TY_SLICE) return 16;
    return 8;
}

static Function *find_function(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.function_count; ++i)
        if (strcmp(c->program.functions[i].name, name) == 0) return &c->program.functions[i];
    return 0;
}

static int expand_import_qualifier(Compiler *c, const char *owner_module,
                                   const char *name, char *out, size_t capacity) {
    const char *dot = strchr(name, '.');
    size_t qualifier_length;
    int i;
    if (!dot) return 0;
    qualifier_length = (size_t)(dot - name);
    for (i = 0; i < c->program.use_count; ++i) {
        UseDecl *use = &c->program.uses[i];
        if (strcmp(use->owner_module, owner_module) != 0 ||
            strlen(use->qualifier) != qualifier_length ||
            memcmp(use->qualifier, name, qualifier_length) != 0) continue;
        if (strlen(use->name) + strlen(dot) + 1 > capacity) return 0;
        out[0] = 0;
        append_text(out, capacity, use->name);
        append_text(out, capacity, dot);
        return 1;
    }
    return 0;
}

static Function *find_function_scoped(Compiler *c, const char *module, const char *name) {
    char qualified[196], imported[196];
    Function *found;
    if (expand_import_qualifier(c, module, name, imported, sizeof(imported))) {
        found = find_function(c, imported);
        if (found) return found;
    }
    if (module[0] && !strchr(name, '.')) {
        join_qualified_name(qualified, sizeof(qualified), module, name);
        found = find_function(c, qualified);
        if (found) return found;
    }
    return find_function(c, name);
}

static ConstDecl *find_constant(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.constant_count; ++i)
        if (strcmp(c->program.constants[i].name, name) == 0)
            return &c->program.constants[i];
    return 0;
}

static ConstDecl *find_constant_scoped(Compiler *c, const char *module, const char *name) {
    char qualified[196], imported[196];
    ConstDecl *found;
    if (expand_import_qualifier(c, module, name, imported, sizeof(imported))) {
        found = find_constant(c, imported);
        if (found) return found;
    }
    if (module[0] && !strchr(name, '.')) {
        join_qualified_name(qualified, sizeof(qualified), module, name);
        found = find_constant(c, qualified);
        if (found) return found;
    }
    return find_constant(c, name);
}

static void iterator_next_name(Type type, char *out, size_t capacity) {
    const char *name = strrchr(type.name, '.');
    size_t i, n, used = 0;
    name = name ? name + 1 : type.name;
    n = strlen(name);
    for (i = 0; i < n && used + 6 < capacity; ++i) {
        unsigned char ch = (unsigned char)name[i];
        int upper = ch >= 'A' && ch <= 'Z';
        int previous_lower = i > 0 && ((name[i - 1] >= 'a' && name[i - 1] <= 'z') ||
                                      (name[i - 1] >= '0' && name[i - 1] <= '9'));
        int next_lower = i + 1 < n && name[i + 1] >= 'a' && name[i + 1] <= 'z';
        if (upper && i > 0 && (previous_lower || next_lower)) out[used++] = '_';
        out[used++] = (char)(upper ? ch - 'A' + 'a' : ch);
    }
    copy_text(out + used, capacity - used, "_next", 5);
}

static ErrorDecl *find_error(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.error_count; ++i) {
        ErrorDecl *error = &c->program.errors[i];
        if (!error->module[0] && strcmp(error->name, name) == 0) return error;
        if (error->module[0]) {
            char qualified[196];
            snprintf(qualified, sizeof(qualified), "%s.%s", error->module, error->name);
            if (strcmp(qualified, name) == 0) return error;
        }
    }
    return 0;
}

static ErrorDecl *find_error_scoped(Compiler *c, const char *module, const char *name) {
    char qualified[196], imported[196];
    ErrorDecl *found;
    if (expand_import_qualifier(c, module, name, imported, sizeof(imported))) {
        found = find_error(c, imported);
        if (found) return found;
    }
    if (module[0] && !strchr(name, '.')) {
        join_qualified_name(qualified, sizeof(qualified), module, name);
        found = find_error(c, qualified);
        if (found) return found;
    }
    return find_error(c, name);
}

static StructDecl *find_struct(Compiler *c, const char *name) {
    int i;
    for (i = 0; i < c->program.struct_count; ++i)
        if (strcmp(c->program.structs[i].name, name) == 0) return &c->program.structs[i];
    return 0;
}

static StructDecl *find_struct_scoped(Compiler *c, const char *module, const char *name) {
    char qualified[196], imported[196];
    StructDecl *found;
    if (expand_import_qualifier(c, module, name, imported, sizeof(imported))) {
        found = find_struct(c, imported);
        if (found) return found;
    }
    if (module[0] && !strchr(name, '.')) {
        join_qualified_name(qualified, sizeof(qualified), module, name);
        found = find_struct(c, qualified);
        if (found) return found;
    }
    return find_struct(c, name);
}

static void qualify_type_for_module(Compiler *c, Type *type, const char *module) {
    int i;
    if (type->kind == TY_NAMED) {
        StructDecl *decl = find_struct_scoped(c, module, type->name);
        if (decl) copy_text(type->name, sizeof(type->name), decl->name, strlen(decl->name));
    }
    if (type->element) qualify_type_for_module(c, type->element, module);
    for (i = 0; i < type->generic_arg_count; ++i)
        if (type->generic_is_type[i] && type->generic_types[i])
            qualify_type_for_module(c, type->generic_types[i], module);
}

static StructDecl *find_tag_owner(Compiler *c, const char *name) {
    size_t length = strlen(name);
    int i;
    if (length < 5 || strcmp(name + length - 4, ".Tag") != 0) return 0;
    for (i = 0; i < c->program.struct_count; ++i) {
        StructDecl *decl = &c->program.structs[i];
        if (decl->kind == ND_TAGGED_UNION && strlen(decl->name) == length - 4 &&
            memcmp(decl->name, name, length - 4) == 0) return decl;
    }
    return 0;
}

static int type_is_value_aggregate(Compiler *c, Type t) {
    StructDecl *decl;
    if (t.kind == TY_ARRAY) return 1;
    if (t.kind != TY_NAMED) return 0;
    decl = find_struct(c, t.name);
    return decl && decl->kind != ND_ENUM;
}

static void check_known_type(Compiler *c, Type type, Token *token);

static size_t align_up_size(size_t value, size_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static int layout_struct(Compiler *c, StructDecl *decl);

static int type_layout(Compiler *c, Type type, size_t *size, size_t *alignment) {
    if (type.kind == TY_VOID || type.kind == TY_INVALID || type.kind == TY_UNTYPED_INT) return 0;
    if (type.kind == TY_BOOL) { *size = 1; *alignment = 1; return 1; }
    if (type.kind == TY_ERR) { *size = 4; *alignment = 4; return 1; }
    if (type.kind == TY_INT) {
        *size = scalar_byte_size(type); *alignment = *size; return 1;
    }
    if (type.kind == TY_POINTER || type.kind == TY_ARENA) {
        *size = 8; *alignment = 8; return 1;
    }
    if (type.kind == TY_STR || type.kind == TY_SLICE) {
        *size = 16; *alignment = 8; return 1;
    }
    if (type.kind == TY_ARRAY) {
        Type element = array_element_type(type);
        size_t element_size, element_alignment;
        if (!type_layout(c, element, &element_size, &element_alignment)) return 0;
        if (element_size != 0 && type.array_length > SIZE_MAX / element_size) return 0;
        *size = type.array_length * element_size;
        *alignment = element_alignment;
        return 1;
    }
    if (type.kind == TY_NAMED) {
        StructDecl *decl = find_struct(c, type.name);
        if (!decl) decl = find_tag_owner(c, type.name);
        if (!decl || !layout_struct(c, decl)) return 0;
        if (find_tag_owner(c, type.name)) {
            return type_layout(c, decl->backing_type, size, alignment);
        }
        *size = decl->size; *alignment = decl->alignment;
        return 1;
    }
    return 0;
}

static int layout_struct(Compiler *c, StructDecl *decl) {
    size_t size = 0, alignment = 1, payload_size = 0, payload_alignment = 1;
    int i, j;
    if (decl->layout_state == 2) return 1;
    if (decl->layout_state == 3) return 0;
    if (decl->layout_state == 1) {
        diagnostic_at(c, &decl->token, "E-TYPE-9999", "recursive aggregate value layout");
        decl->layout_state = 3;
        return 0;
    }
    decl->layout_state = 1;
    if ((decl->kind == ND_ENUM || decl->kind == ND_TAGGED_UNION) &&
        decl->backing_type.kind != TY_INT) {
        diagnostic_at(c, &decl->token, "E-TYPE-9999", "enum backing type must be an integer");
        decl->layout_state = 3;
        return 0;
    }
    if (decl->kind != ND_STRUCT && decl->field_count == 0) {
        diagnostic_at(c, &decl->token, "E-TYPE-9999", "union and enum declarations may not be empty");
        decl->layout_state = 3;
        return 0;
    }
    for (i = 0; i < decl->field_count; ++i) {
        FieldDecl *field = &decl->fields[i];
        size_t field_size, field_alignment;
        for (j = 0; j < i; ++j)
            if (strcmp(field->name, decl->fields[j].name) == 0)
                diagnostic_at(c, &field->token, "E-NAME-0001", "duplicate type member");
        if (decl->kind == ND_ENUM) {
            int bits = (int)(scalar_byte_size(decl->backing_type) * 8);
            int is_signed = decl->backing_type.name[0] == 'i';
            int64_t minimum = is_signed && bits < 64 ? -(INT64_C(1) << (bits - 1)) : 0;
            uint64_t maximum = bits == 64 ? (is_signed ? (uint64_t)INT64_MAX : UINT64_MAX) :
                               (is_signed ? ((UINT64_C(1) << (bits - 1)) - 1) : ((UINT64_C(1) << bits) - 1));
            if (field->value < minimum || (field->value >= 0 && (uint64_t)field->value > maximum))
                diagnostic_at(c, &field->token, "E-TYPE-0004", "enum member value is outside its backing type");
            for (j = 0; j < i; ++j)
                if (field->value == decl->fields[j].value)
                    diagnostic_at(c, &field->token, "E-NAME-0001", "duplicate enum backing value");
            continue;
        }
        if (decl->kind == ND_TAGGED_UNION && !field->has_payload) continue;
        if (!type_layout(c, field->type, &field_size, &field_alignment)) {
            StructDecl *field_decl = field->type.kind == TY_NAMED ? find_struct(c, field->type.name) : 0;
            if (!field_decl || field_decl->layout_state != 3)
                diagnostic_at(c, &field->token, "E-TYPE-9999", "aggregate member has an unknown or unsized type");
            decl->layout_state = 3;
            return 0;
        }
        if (decl->kind == ND_STRUCT) {
            size = align_up_size(size, field_alignment);
            field->offset = size;
            size += field_size;
            if (field_alignment > alignment) alignment = field_alignment;
        } else {
            if (field_size > payload_size) payload_size = field_size;
            if (field_alignment > payload_alignment) payload_alignment = field_alignment;
            field->offset = 0;
        }
    }
    if (decl->kind == ND_ENUM) {
        type_layout(c, decl->backing_type, &size, &alignment);
    } else if (decl->kind == ND_UNION) {
        alignment = payload_alignment;
        size = align_up_size(payload_size, alignment);
    } else if (decl->kind == ND_TAGGED_UNION) {
        size_t tag_size, tag_alignment;
        int backing_bits = (int)(scalar_byte_size(decl->backing_type) * 8);
        int backing_signed = decl->backing_type.name[0] == 'i';
        uint64_t tag_maximum = backing_bits == 64 ?
                               (backing_signed ? (uint64_t)INT64_MAX : UINT64_MAX) :
                               (backing_signed ? ((UINT64_C(1) << (backing_bits - 1)) - 1) :
                                ((UINT64_C(1) << backing_bits) - 1));
        type_layout(c, decl->backing_type, &tag_size, &tag_alignment);
        if ((uint64_t)(decl->field_count - 1) > tag_maximum)
            diagnostic_at(c, &decl->token, "E-TYPE-0004", "tagged union has too many members for its backing type");
        decl->payload_offset = align_up_size(tag_size, payload_alignment);
        for (i = 0; i < decl->field_count; ++i)
            if (decl->fields[i].has_payload) decl->fields[i].offset = decl->payload_offset;
        alignment = tag_alignment > payload_alignment ? tag_alignment : payload_alignment;
        size = align_up_size(decl->payload_offset + payload_size, alignment);
    } else if (decl->field_count == 0) size = 1;
    decl->alignment = alignment;
    decl->size = align_up_size(size, alignment);
    decl->layout_state = 2;
    return 1;
}

static size_t type_size(Compiler *c, Type type) {
    size_t size = 0, alignment = 1;
    if (!type_layout(c, type, &size, &alignment)) return 0;
    return size;
}

static int find_local(Function *fn, const char *name) {
    int i;
    for (i = fn->local_count - 1; i >= 0; --i)
        if (fn->locals[i].active && strcmp(fn->locals[i].name, name) == 0) return i;
    return -1;
}

static void coerce_untyped_integer(Expr *expr, Type target) {
    if (!expr || target.kind != TY_INT || expr->type.kind != TY_UNTYPED_INT) return;
    expr->type = target;
    if (expr->kind == EX_BINARY) {
        coerce_untyped_integer(expr->as.binary.left, target);
        coerce_untyped_integer(expr->as.binary.right, target);
    } else if (expr->kind == EX_UNARY) {
        coerce_untyped_integer(expr->as.unary.value, target);
    }
}

static FieldDecl *find_struct_field(StructDecl *decl, const char *name, int *index) {
    int i;
    for (i = 0; i < decl->field_count; ++i) {
        if (strcmp(decl->fields[i].name, name) == 0) {
            if (index) *index = i;
            return &decl->fields[i];
        }
    }
    return 0;
}

static StructDecl *enum_decl_for_type(Compiler *c, Type type) {
    StructDecl *decl;
    if (type.kind != TY_NAMED) return 0;
    decl = find_struct(c, type.name);
    if (decl && (decl->kind == ND_ENUM || decl->kind == ND_TAGGED_UNION)) return decl;
    return find_tag_owner(c, type.name);
}

static int resolve_contextual_member(Compiler *c, Expr *e, Type expected) {
    StructDecl *decl;
    FieldDecl *member;
    if (!e || e->kind != EX_ENUM_MEMBER) return 0;
    decl = enum_decl_for_type(c, expected);
    if (!decl) {
        diagnostic_at(c, &e->token, "E-TYPE-0001", "enum member requires an enum or tagged-union context");
        e->type = type_make(TY_INVALID, 0);
        return 0;
    }
    member = find_struct_field(decl, e->as.name, 0);
    if (!member) {
        diagnostic_at(c, &e->token, "E-NAME-9999", "unknown enum member");
        e->type = type_make(TY_INVALID, 0);
        return 0;
    }
    if (decl->kind == ND_TAGGED_UNION && strcmp(expected.name, decl->name) == 0 && member->has_payload) {
        diagnostic_at(c, &e->token, "E-TYPE-9999", "tagged-union member with a payload requires an aggregate literal");
        e->type = type_make(TY_INVALID, 0);
        return 0;
    }
    e->constant_value = member->value;
    e->type = expected;
    return 1;
}

static int resolve_qualified_member(Compiler *c, Expr *e, const char *module) {
    char qualified[160], scoped[196], imported[196], resolved_type[196], *last;
    StructDecl *decl;
    FieldDecl *member;
    copy_text(qualified, sizeof(qualified), e->as.name, strlen(e->as.name));
    last = strrchr(qualified, '.');
    if (!last) return 0;
    *last++ = 0;
    decl = find_struct_scoped(c, module, qualified);
    if (decl && decl->kind == ND_ENUM) {
        copy_text(resolved_type, sizeof(resolved_type), decl->name, strlen(decl->name));
    } else {
        StructDecl *owner = 0;
        if (expand_import_qualifier(c, module, qualified, imported, sizeof(imported)))
            owner = find_tag_owner(c, imported);
        if (!owner) owner = find_tag_owner(c, qualified);
        if (!owner && module[0] && !strchr(qualified, '.')) {
            join_qualified_name(scoped, sizeof(scoped), module, qualified);
            owner = find_tag_owner(c, scoped);
        }
        if (!owner) return 0;
        decl = owner;
        copy_text(resolved_type, sizeof(resolved_type), decl->name, strlen(decl->name));
        append_text(resolved_type, sizeof(resolved_type), ".Tag");
    }
    member = find_struct_field(decl, last, 0);
    if (!member) {
        diagnostic_at(c, &e->token, "E-NAME-9999", "unknown enum member");
        e->type = type_make(TY_INVALID, 0);
        return 1;
    }
    e->kind = EX_ENUM_MEMBER;
    e->constant_value = member->value;
    e->type = type_make(TY_NAMED, resolved_type);
    return 1;
}

static int case_constant_value(Expr *e, int64_t *value) {
    if (e->kind == EX_INTEGER) { *value = e->as.integer; return 1; }
    if (e->kind == EX_ENUM_MEMBER) { *value = e->constant_value; return 1; }
    if (e->kind == EX_NAME && strcmp(e->as.name, "ok") == 0) { *value = 0; return 1; }
    if (e->kind == EX_NAME && e->error_code) { *value = e->error_code; return 1; }
    return 0;
}

static int type_has_zero_at(Compiler *c, Type type, int depth, char *offending, size_t capacity) {
    StructDecl *decl;
    int i;
    if (depth > MAX_FIELD_PATH) return 0;
    if (type.kind == TY_ARRAY)
        return type_has_zero_at(c, array_element_type(type), depth + 1, offending, capacity);
    if (type.kind != TY_NAMED) return 1;
    decl = find_struct(c, type.name);
    if (!decl) decl = find_tag_owner(c, type.name);
    if (!decl) return 0;
    if (decl->kind == ND_ENUM || find_tag_owner(c, type.name)) {
        for (i = 0; i < decl->field_count; ++i) if (decl->fields[i].value == 0) return 1;
        copy_text(offending, capacity, type.name, strlen(type.name));
        return 0;
    }
    for (i = 0; i < decl->field_count; ++i) {
        FieldDecl *field = &decl->fields[i];
        if (decl->kind == ND_TAGGED_UNION && !field->has_payload) continue;
        if (!type_has_zero_at(c, field->type, depth + 1, offending, capacity)) {
            if (!offending[0]) copy_text(offending, capacity, field->name, strlen(field->name));
            return 0;
        }
    }
    return 1;
}

static void check_zeroable(Compiler *c, Expr *value, Type type) {
    char offending[96] = {0};
    if (value && value->kind == EX_ZERO && !type_has_zero_at(c, type, 0, offending, sizeof(offending))) {
        char message[256];
        snprintf(message, sizeof(message), "type `%s` has no zero value because `%s` has no member at 0",
                 type.name[0] ? type.name : "aggregate", offending[0] ? offending : "an enum");
        diagnostic_at(c, &value->token, "E-TYPE-9999", message);
    }
}

static Type pointer_element_type(Type pointer) {
    if (pointer.element) return *pointer.element;
    Type element = type_make(pointer.element_kind, pointer.element_name);
    element.is_const = pointer.element_is_const;
    return element;
}

static Type resolve_name_place(Compiler *c, Function *fn, Expr *e) {
    char path[160], *part, *next;
    int root;
    Type current;
    copy_text(path, sizeof(path), e->as.name, strlen(e->as.name));
    part = path;
    next = strchr(part, '.');
    if (next) *next++ = 0;
    root = find_local(fn, part);
    if (root < 0) return type_make(TY_INVALID, 0);
    current = fn->locals[root].type;
    e->local_index = root;
    e->field_path_count = 0;
    e->place_mutable = fn->locals[root].is_mutable;
    while (next) {
        StructDecl *decl;
        FieldDecl *field;
        int dereference = 0;
        part = next;
        next = strchr(part, '.');
        if (next) *next++ = 0;
        if (strcmp(part, "len") == 0 && !next &&
            (current.kind == TY_ARRAY || current.kind == TY_SLICE || current.kind == TY_STR)) {
            e->is_len = 1;
            e->place_type = current;
            return type_make(TY_INT, "usize");
        }
        if (current.kind == TY_POINTER) {
            e->place_mutable = !current.is_const;
            current = pointer_element_type(current);
            dereference = 1;
        }
        if (current.kind != TY_NAMED || !(decl = find_struct(c, current.name)) || decl->kind == ND_ENUM) {
            diagnostic_at(c, &e->token, "E-TYPE-9999", "field access requires an aggregate value or pointer");
            return type_make(TY_INVALID, 0);
        }
        if (decl->kind == ND_TAGGED_UNION && strcmp(part, "tag") == 0) {
            char tag_name[160];
            snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
            current = type_make(TY_NAMED, tag_name);
            e->field_offsets[e->field_path_count] = 0;
            e->field_dereferences[e->field_path_count] = (unsigned char)dereference;
            e->field_path_count++;
            continue;
        }
        field = find_struct_field(decl, part, 0);
        if (!field) {
            diagnostic_at(c, &e->token, "E-NAME-9999", "unknown aggregate field or member");
            return type_make(TY_INVALID, 0);
        }
        if (e->field_path_count >= MAX_FIELD_PATH) {
            diagnostic_at(c, &e->token, "E-TOOL-9999", "field access path limit exceeded");
            return type_make(TY_INVALID, 0);
        }
        e->field_offsets[e->field_path_count] = (int)field->offset;
        e->field_dereferences[e->field_path_count] = (unsigned char)dereference;
        if (decl->kind == ND_TAGGED_UNION) {
            e->field_tag_checks[e->field_path_count] = 1;
            e->field_tag_sizes[e->field_path_count] = (unsigned char)scalar_byte_size(decl->backing_type);
            e->field_tag_values[e->field_path_count] = field->value;
        }
        e->field_path_count++;
        current = field->type;
    }
    return current;
}

static Type check_expr(Compiler *c, Function *fn, Expr *e);
static int evaluate_constant(Compiler *c, ConstDecl *constant);
static void resolve_type_constants(Compiler *c, Type *type, Token *token);
static int evaluate_integer_expression(Compiler *c, Expr *expr, int64_t *out,
                                       Type *out_type);
static int checked_integer_binary(Compiler *c, Expr *expr, int64_t left,
                                  int64_t right, int64_t *out);
static int instantiate_struct_type(Compiler *c, Type *type, Token *token);

static int template_parameter_index(Function *template_fn, const char *name) {
    int i;
    for (i = 0; i < template_fn->comptime_param_count; ++i)
        if (strcmp(template_fn->comptime_params[i].name, name) == 0) return i;
    return -1;
}

static int evaluate_template_integer(Compiler *c, Function *template_fn,
                                     int64_t *integer_args, Expr *expr, int64_t *out) {
    int parameter_index;
    if (expr->kind == EX_NAME &&
        (parameter_index = template_parameter_index(template_fn, expr->as.name)) >= 0 &&
        !template_fn->comptime_params[parameter_index].is_type) {
        *out = integer_args[parameter_index];
        return 1;
    }
    if (expr->kind == EX_INTEGER) { *out = expr->as.integer; return 1; }
    if (expr->kind == EX_NAME) {
        Type ignored;
        return evaluate_integer_expression(c, expr, out, &ignored);
    }
    if (expr->kind == EX_UNARY && expr->as.unary.op == TK_MINUS) {
        if (!evaluate_template_integer(c, template_fn, integer_args,
                                       expr->as.unary.value, out)) return 0;
        if (*out == INT64_MIN) {
            diagnostic_at(c, &expr->token, "E-TYPE-0004", "compile-time argument overflow");
            return 0;
        }
        *out = -*out;
        return 1;
    }
    if (expr->kind == EX_BINARY) {
        int64_t left, right;
        if (!evaluate_template_integer(c, template_fn, integer_args,
                                       expr->as.binary.left, &left) ||
            !evaluate_template_integer(c, template_fn, integer_args,
                                       expr->as.binary.right, &right)) return 0;
        return checked_integer_binary(c, expr, left, right, out);
    }
    diagnostic_at(c, &expr->token, "E-TYPE-9999",
                  "unsupported expression involving a compile-time integer parameter");
    return 0;
}

static Type specialize_type(Compiler *c, Function *template_fn, Type *type_args,
                            int64_t *integer_args, Type source) {
    int parameter_index, i;
    if (source.kind == TY_NAMED &&
        (parameter_index = template_parameter_index(template_fn, source.name)) >= 0 &&
        template_fn->comptime_params[parameter_index].is_type)
        return type_args[parameter_index];
    if (source.element) {
        Type element = specialize_type(c, template_fn, type_args, integer_args,
                                       *source.element);
        type_set_element(&source, element);
    }
    for (i = 0; i < source.generic_arg_count; ++i) {
        if (source.generic_is_type[i] && source.generic_types[i]) {
            Type specialized = specialize_type(c, template_fn, type_args, integer_args,
                                               *source.generic_types[i]);
            Type *stored = (Type *)calloc(1, sizeof(*stored));
            if (!stored) { fputs("neper: out of memory\n", stderr); exit(2); }
            *stored = specialized;
            source.generic_types[i] = stored;
        } else if (source.generic_values[i]) {
            int64_t value;
            if (evaluate_template_integer(c, template_fn, integer_args,
                                          source.generic_values[i], &value)) {
                Expr *stored = new_expr(EX_INTEGER, source.generic_values[i]->token);
                stored->as.integer = value;
                stored->type = type_make(TY_UNTYPED_INT, "");
                source.generic_values[i] = stored;
            }
        }
    }
    if (source.kind == TY_ARRAY && source.array_length_expr) {
        int64_t length;
        if (evaluate_template_integer(c, template_fn, integer_args,
                                      source.array_length_expr, &length)) {
            if (length < 0)
                diagnostic_at(c, &source.array_length_expr->token, "E-TYPE-0004",
                              "array length is not representable as usize");
            else {
                source.array_length = (size_t)length;
                source.array_length_expr = 0;
            }
        }
    }
    if (source.kind == TY_NAMED && source.generic_arg_count)
        instantiate_struct_type(c, &source, &template_fn->token);
    return source;
}

static Expr *clone_specialized_expr(Compiler *c, Function *template_fn,
                                    Type *type_args, int64_t *integer_args,
                                    Expr *source) {
    Expr *copy;
    int i, parameter_index;
    if (!source) return 0;
    copy = (Expr *)calloc(1, sizeof(*copy));
    if (!copy) { fputs("neper: out of memory\n", stderr); exit(2); }
    *copy = *source;
    copy->type = specialize_type(c, template_fn, type_args, integer_args, source->type);
    copy->local_index = -1;
    copy->trap_id = -1;
    copy->field_path_count = 0;
    copy->place_mutable = 0;
    copy->is_len = 0;
    if (copy->kind == EX_NAME &&
        (parameter_index = template_parameter_index(template_fn, copy->as.name)) >= 0 &&
        !template_fn->comptime_params[parameter_index].is_type) {
        copy->kind = EX_INTEGER;
        copy->as.integer = integer_args[parameter_index];
        copy->type = template_fn->comptime_params[parameter_index].value_type;
        copy->constant_value = copy->as.integer;
        copy->is_constant = 1;
        return copy;
    }
    switch (copy->kind) {
        case EX_CALL:
            for (i = 0; i < copy->as.call.arg_count; ++i)
                copy->as.call.args[i] = clone_specialized_expr(c, template_fn, type_args,
                                                               integer_args, source->as.call.args[i]);
            for (i = 0; i < copy->as.call.generic_arg_count; ++i) {
                if (copy->as.call.generic_is_type[i])
                    copy->as.call.generic_types[i] = specialize_type(c, template_fn, type_args,
                                                                     integer_args, source->as.call.generic_types[i]);
                else copy->as.call.generic_values[i] = clone_specialized_expr(
                    c, template_fn, type_args, integer_args, source->as.call.generic_values[i]);
            }
            break;
        case EX_INDEX:
            copy->as.index.base = clone_specialized_expr(c, template_fn, type_args,
                                                         integer_args, source->as.index.base);
            copy->as.index.index = clone_specialized_expr(c, template_fn, type_args,
                                                          integer_args, source->as.index.index);
            break;
        case EX_FIELD:
            copy->as.field.base = clone_specialized_expr(c, template_fn, type_args,
                                                         integer_args, source->as.field.base);
            break;
        case EX_SLICE:
            copy->as.slice.base = clone_specialized_expr(c, template_fn, type_args,
                                                         integer_args, source->as.slice.base);
            copy->as.slice.start = clone_specialized_expr(c, template_fn, type_args,
                                                          integer_args, source->as.slice.start);
            copy->as.slice.end = clone_specialized_expr(c, template_fn, type_args,
                                                        integer_args, source->as.slice.end);
            break;
        case EX_ARRAY_LITERAL:
            copy->as.array.items = (Expr **)calloc((size_t)(source->as.array.item_count ?
                                                   source->as.array.item_count : 1), sizeof(Expr *));
            if (!copy->as.array.items) { fputs("neper: out of memory\n", stderr); exit(2); }
            copy->as.array.item_capacity = source->as.array.item_count;
            for (i = 0; i < source->as.array.item_count; ++i)
                copy->as.array.items[i] = clone_specialized_expr(c, template_fn, type_args,
                                                                 integer_args, source->as.array.items[i]);
            break;
        case EX_STRUCT_LITERAL:
            copy->as.aggregate.items = (StructInit *)calloc(
                (size_t)(source->as.aggregate.item_count ? source->as.aggregate.item_count : 1),
                sizeof(StructInit));
            if (!copy->as.aggregate.items) { fputs("neper: out of memory\n", stderr); exit(2); }
            copy->as.aggregate.item_capacity = source->as.aggregate.item_count;
            for (i = 0; i < source->as.aggregate.item_count; ++i) {
                copy->as.aggregate.items[i] = source->as.aggregate.items[i];
                copy->as.aggregate.items[i].field_index = -1;
                copy->as.aggregate.items[i].value = clone_specialized_expr(
                    c, template_fn, type_args, integer_args, source->as.aggregate.items[i].value);
            }
            break;
        case EX_BINARY:
            copy->as.binary.left = clone_specialized_expr(c, template_fn, type_args,
                                                          integer_args, source->as.binary.left);
            copy->as.binary.right = clone_specialized_expr(c, template_fn, type_args,
                                                           integer_args, source->as.binary.right);
            break;
        case EX_UNARY:
            copy->as.unary.value = clone_specialized_expr(c, template_fn, type_args,
                                                          integer_args, source->as.unary.value);
            break;
        default: break;
    }
    return copy;
}

static Stmt *clone_specialized_statements(Compiler *c, Function *template_fn,
                                          Type *type_args, int64_t *integer_args,
                                          Stmt *source);

static SwitchCase *clone_specialized_cases(Compiler *c, Function *template_fn,
                                           Type *type_args, int64_t *integer_args,
                                           SwitchCase *source) {
    SwitchCase *head = 0, **tail = &head;
    for (; source; source = source->next) {
        SwitchCase *copy = (SwitchCase *)calloc(1, sizeof(*copy));
        int i;
        if (!copy) { fputs("neper: out of memory\n", stderr); exit(2); }
        *copy = *source; copy->next = 0; copy->local_index = -1; copy->member_index = -1;
        for (i = 0; i < source->value_count; ++i)
            copy->values[i] = clone_specialized_expr(c, template_fn, type_args,
                                                      integer_args, source->values[i]);
        copy->body = clone_specialized_statements(c, template_fn, type_args,
                                                  integer_args, source->body);
        *tail = copy; tail = &copy->next;
    }
    return head;
}

static Stmt *clone_specialized_statements(Compiler *c, Function *template_fn,
                                          Type *type_args, int64_t *integer_args,
                                          Stmt *source) {
    Stmt *head = 0, **tail = &head;
    for (; source; source = source->next) {
        Stmt *copy = (Stmt *)calloc(1, sizeof(*copy));
        int i;
        if (!copy) { fputs("neper: out of memory\n", stderr); exit(2); }
        *copy = *source; copy->next = 0;
        switch (copy->kind) {
            case ST_BIND:
                copy->as.bind.local_index = -1;
                copy->as.bind.declared_type = specialize_type(c, template_fn, type_args,
                                                              integer_args, source->as.bind.declared_type);
                copy->as.bind.value = clone_specialized_expr(c, template_fn, type_args,
                                                             integer_args, source->as.bind.value);
                break;
            case ST_MULTI_BIND: case ST_MULTI_ASSIGN:
                for (i = 0; i < copy->as.multi.count; ++i) copy->as.multi.local_indices[i] = -1;
                copy->as.multi.call = clone_specialized_expr(c, template_fn, type_args,
                                                             integer_args, source->as.multi.call);
                break;
            case ST_ASSIGN:
                copy->as.assign.local_index = -1;
                copy->as.assign.target = clone_specialized_expr(c, template_fn, type_args,
                                                                integer_args, source->as.assign.target);
                copy->as.assign.value = clone_specialized_expr(c, template_fn, type_args,
                                                               integer_args, source->as.assign.value);
                break;
            case ST_INDEX_ASSIGN:
                copy->as.index_assign.target = clone_specialized_expr(c, template_fn, type_args,
                                                                      integer_args, source->as.index_assign.target);
                copy->as.index_assign.value = clone_specialized_expr(c, template_fn, type_args,
                                                                     integer_args, source->as.index_assign.value);
                break;
            case ST_EXPR: case ST_TRY:
                copy->as.expr = clone_specialized_expr(c, template_fn, type_args,
                                                       integer_args, source->as.expr); break;
            case ST_RETURN:
                for (i = 0; i < copy->as.ret.value_count; ++i)
                    copy->as.ret.values[i] = clone_specialized_expr(c, template_fn, type_args,
                                                                   integer_args, source->as.ret.values[i]);
                copy->as.ret.value = copy->as.ret.value_count ? copy->as.ret.values[0] : 0;
                break;
            case ST_IF:
                copy->as.if_stmt.condition = clone_specialized_expr(c, template_fn, type_args,
                                                                    integer_args, source->as.if_stmt.condition);
                copy->as.if_stmt.then_body = clone_specialized_statements(c, template_fn, type_args,
                                                                          integer_args, source->as.if_stmt.then_body);
                copy->as.if_stmt.else_body = clone_specialized_statements(c, template_fn, type_args,
                                                                          integer_args, source->as.if_stmt.else_body);
                break;
            case ST_WHILE:
                copy->as.while_stmt.condition = clone_specialized_expr(c, template_fn, type_args,
                                                                       integer_args, source->as.while_stmt.condition);
                copy->as.while_stmt.body = clone_specialized_statements(c, template_fn, type_args,
                                                                        integer_args, source->as.while_stmt.body);
                break;
            case ST_FOR_RANGE:
                copy->as.for_range.local_index = copy->as.for_range.end_local_index = -1;
                copy->as.for_range.start = clone_specialized_expr(c, template_fn, type_args,
                                                                  integer_args, source->as.for_range.start);
                copy->as.for_range.end = clone_specialized_expr(c, template_fn, type_args,
                                                                integer_args, source->as.for_range.end);
                copy->as.for_range.body = clone_specialized_statements(c, template_fn, type_args,
                                                                       integer_args, source->as.for_range.body);
                break;
            case ST_FOR_EACH:
                copy->as.for_each.pointer_local_index = copy->as.for_each.length_local_index = -1;
                copy->as.for_each.index_local_index = copy->as.for_each.value_local_index = -1;
                copy->as.for_each.iterator_pointer_local_index = copy->as.for_each.iterator_has_local_index = -1;
                copy->as.for_each.subject = clone_specialized_expr(c, template_fn, type_args,
                                                                   integer_args, source->as.for_each.subject);
                copy->as.for_each.body = clone_specialized_statements(c, template_fn, type_args,
                                                                      integer_args, source->as.for_each.body);
                break;
            case ST_SWITCH:
                copy->as.switch_stmt.subject = clone_specialized_expr(c, template_fn, type_args,
                                                                      integer_args, source->as.switch_stmt.subject);
                copy->as.switch_stmt.cases = clone_specialized_cases(c, template_fn, type_args,
                                                                    integer_args, source->as.switch_stmt.cases);
                break;
            case ST_DEFER:
                copy->as.defer_stmt.capture_count = 0;
                copy->as.defer_stmt.is_captured_call = 0;
                copy->as.defer_stmt.call = 0;
                copy->as.defer_stmt.body = clone_specialized_statements(c, template_fn, type_args,
                                                                        integer_args, source->as.defer_stmt.body);
                break;
            default: break;
        }
        *tail = copy; tail = &copy->next;
    }
    return head;
}

static Function *instantiate_function(Compiler *c, Function *template_fn, Expr *call) {
    Type type_args[MAX_ARGS];
    int64_t integer_args[MAX_ARGS] = {0};
    char instance_name[96];
    size_t used;
    Function *instance;
    int i;
    if (call->as.call.generic_arg_count != template_fn->comptime_param_count) {
        diagnostic_at(c, &call->token, "E-TYPE-0003",
                      "compile-time argument count does not match function");
        return 0;
    }
    memset(type_args, 0, sizeof(type_args));
    copy_text(instance_name, sizeof(instance_name), template_fn->name, strlen(template_fn->name));
    used = strlen(instance_name);
    for (i = 0; i < template_fn->comptime_param_count; ++i) {
        ComptimeParam *parameter = &template_fn->comptime_params[i];
        char part[112];
        if (parameter->is_type) {
            if (!call->as.call.generic_is_type[i]) {
                diagnostic_at(c, &call->token, "E-TYPE-0003", "compile-time argument must be a type");
                return 0;
            }
            type_args[i] = call->as.call.generic_types[i];
            snprintf(part, sizeof(part), "$%s", type_args[i].name);
        } else {
            Type actual;
            if (call->as.call.generic_is_type[i] ||
                !evaluate_integer_expression(c, call->as.call.generic_values[i],
                                             &integer_args[i], &actual)) return 0;
            if (actual.kind != TY_UNTYPED_INT && !type_equal(actual, parameter->value_type)) {
                diagnostic_at(c, &call->token, "E-TYPE-0002",
                              "compile-time integer argument has the wrong type");
                return 0;
            }
            snprintf(part, sizeof(part), "$%lld", (long long)integer_args[i]);
        }
        copy_text(instance_name + used, sizeof(instance_name) - used, part, strlen(part));
        used = strlen(instance_name);
    }
    instance = find_function(c, instance_name);
    if (instance) return instance;
    if (c->program.function_count >= MAX_DECLS) {
        diagnostic_at(c, &call->token, "E-TOOL-9999", "function instance limit exceeded");
        return 0;
    }
    instance = &c->program.functions[c->program.function_count++];
    memset(instance, 0, sizeof(*instance));
    copy_text(instance->name, sizeof(instance->name), instance_name, strlen(instance_name));
    strcpy(instance->symbol, "neper_fn_");
    for (i = 0; instance_name[i] && strlen(instance->symbol) + 2 < sizeof(instance->symbol); ++i) {
        size_t at = strlen(instance->symbol);
        char ch = instance_name[i];
        instance->symbol[at] = (ch == '$' || ch == '.' || ch == '*') ? '_' : ch;
        instance->symbol[at + 1] = 0;
    }
    instance->token = template_fn->token;
    copy_text(instance->module, sizeof(instance->module), template_fn->module,
              strlen(template_fn->module));
    instance->return_slot_local_index = instance->scalar_return_local_index = -1;
    for (i = 0; i < MAX_ARGS; ++i) instance->return_value_locals[i] = -1;
    instance->param_count = template_fn->param_count;
    for (i = 0; i < instance->param_count; ++i) {
        instance->params[i] = template_fn->params[i];
        instance->params[i].type = specialize_type(c, template_fn, type_args, integer_args,
                                                   template_fn->params[i].type);
    }
    instance->return_count = template_fn->return_count;
    for (i = 0; i < instance->return_count; ++i)
        instance->return_types[i] = specialize_type(c, template_fn, type_args, integer_args,
                                                    template_fn->return_types[i]);
    instance->return_type = instance->return_count ? instance->return_types[0] : type_make(TY_VOID, "void");
    instance->body = clone_specialized_statements(c, template_fn, type_args, integer_args,
                                                  template_fn->body);
    return instance;
}

static void infer_comptime_from_types(Compiler *c, Function *template_fn,
                                      Type formal, Type actual, Type *type_args,
                                      int64_t *integer_args, unsigned char *inferred,
                                      Token *token) {
    int parameter_index;
    if (formal.kind == TY_NAMED &&
        (parameter_index = template_parameter_index(template_fn, formal.name)) >= 0 &&
        template_fn->comptime_params[parameter_index].is_type) {
        if (!inferred[parameter_index]) {
            type_args[parameter_index] = actual;
            inferred[parameter_index] = 1;
        } else if (!type_equal(type_args[parameter_index], actual))
            diagnostic_at(c, token, "E-TYPE-0002",
                          "conflicting inference for compile-time type parameter");
        return;
    }
    if (formal.kind != actual.kind) return;
    if (formal.kind == TY_ARRAY && formal.array_length_expr &&
        formal.array_length_expr->kind == EX_NAME &&
        (parameter_index = template_parameter_index(template_fn,
                                                     formal.array_length_expr->as.name)) >= 0 &&
        !template_fn->comptime_params[parameter_index].is_type) {
        if (!inferred[parameter_index]) {
            integer_args[parameter_index] = (int64_t)actual.array_length;
            inferred[parameter_index] = 1;
        } else if (integer_args[parameter_index] != (int64_t)actual.array_length)
            diagnostic_at(c, token, "E-TYPE-0002",
                          "conflicting inference for compile-time integer parameter");
    }
    if (formal.element && actual.element)
        infer_comptime_from_types(c, template_fn, *formal.element, *actual.element,
                                  type_args, integer_args, inferred, token);
}

static int infer_function_arguments(Compiler *c, Function *fn, Function *template_fn,
                                    Expr *call) {
    Type type_args[MAX_ARGS];
    int64_t integer_args[MAX_ARGS] = {0};
    unsigned char inferred[MAX_ARGS] = {0};
    int i;
    memset(type_args, 0, sizeof(type_args));
    for (i = 0; i < call->as.call.arg_count && i < template_fn->param_count; ++i) {
        Type actual = check_expr(c, fn, call->as.call.args[i]);
        if (actual.kind == TY_UNTYPED_INT) continue;
        infer_comptime_from_types(c, template_fn, template_fn->params[i].type, actual,
                                  type_args, integer_args, inferred,
                                  &call->as.call.args[i]->token);
    }
    for (i = 0; i < template_fn->comptime_param_count; ++i) {
        if (!inferred[i]) {
            char message[256];
            snprintf(message, sizeof(message),
                     "cannot infer compile-time parameter `%s`",
                     template_fn->comptime_params[i].name);
            diagnostic_at(c, &call->token, "E-TYPE-0001", message);
            return 0;
        }
        if (template_fn->comptime_params[i].is_type) {
            call->as.call.generic_is_type[i] = 1;
            call->as.call.generic_types[i] = type_args[i];
        } else {
            Expr *value = new_expr(EX_INTEGER, call->token);
            value->as.integer = integer_args[i];
            value->type = template_fn->comptime_params[i].value_type;
            call->as.call.generic_values[i] = value;
        }
    }
    call->as.call.generic_arg_count = template_fn->comptime_param_count;
    return 1;
}

static Function *check_declared_call(Compiler *c, Function *fn, Expr *e) {
    Function *callee = find_function_scoped(c, fn->module, e->as.call.callee);
    int i;
    if (callee && strcmp(e->as.call.callee, callee->name) != 0)
        copy_text(e->as.call.callee, sizeof(e->as.call.callee), callee->name,
                  strlen(callee->name));
    if (callee && callee->is_template && !e->as.call.generic_arg_count) {
        if (!infer_function_arguments(c, fn, callee, e)) return 0;
        callee = instantiate_function(c, callee, e);
        if (callee) copy_text(e->as.call.callee, sizeof(e->as.call.callee),
                              callee->name, strlen(callee->name));
    }
    if (callee && callee->is_template && e->as.call.generic_arg_count) {
        callee = instantiate_function(c, callee, e);
        if (callee) copy_text(e->as.call.callee, sizeof(e->as.call.callee),
                              callee->name, strlen(callee->name));
    }
    if (!callee) {
        diagnostic_at(c, &e->token, "E-NAME-9999", "unknown function");
        return 0;
    }
    if (callee->is_template) {
        diagnostic_at(c, &e->token, "E-TYPE-0001",
                      "generic call requires explicit or inferable compile-time arguments");
        return 0;
    }
    if (callee->param_count != e->as.call.arg_count)
        diagnostic_at(c, &e->token, "E-TYPE-0003", "argument count does not match function");
    for (i = 0; i < e->as.call.arg_count && i < callee->param_count; ++i) {
        Type actual;
        if (e->as.call.args[i]->kind == EX_ZERO || e->as.call.args[i]->kind == EX_UNDEF)
            e->as.call.args[i]->type = callee->params[i].type;
        if (e->as.call.args[i]->kind == EX_ENUM_MEMBER)
            resolve_contextual_member(c, e->as.call.args[i], callee->params[i].type);
        actual = check_expr(c, fn, e->as.call.args[i]);
        check_zeroable(c, e->as.call.args[i], callee->params[i].type);
        if (actual.kind == TY_UNTYPED_INT && callee->params[i].type.kind == TY_INT) {
            coerce_untyped_integer(e->as.call.args[i], callee->params[i].type);
            actual = callee->params[i].type;
        }
        if (!type_assignable(actual, callee->params[i].type))
            diagnostic_at(c, &e->as.call.args[i]->token, "E-TYPE-0003",
                          "argument type does not match parameter");
    }
    return callee;
}

static Type check_expr(Compiler *c, Function *fn, Expr *e) {
    int i;
    switch (e->kind) {
        case EX_INTEGER: return e->type;
        case EX_ENUM_MEMBER:
            if (e->type.kind == TY_INVALID)
                diagnostic_at(c, &e->token, "E-TYPE-0001", "unqualified enum member has no typing context");
            return e->type;
        case EX_STRING: return e->type;
        case EX_ZERO: case EX_UNDEF: return e->type;
        case EX_ARRAY_LITERAL: {
            qualify_type_for_module(c, &e->type, fn->module);
            resolve_type_constants(c, &e->type, &e->token);
            Type element = array_element_type(e->type);
            if ((size_t)e->as.array.item_count != e->type.array_length)
                diagnostic_at(c, &e->token, "E-TYPE-9999", "array literal element count does not match its length");
            for (i = 0; i < e->as.array.item_count; ++i) {
                Type item;
                if (e->as.array.items[i]->kind == EX_ZERO || e->as.array.items[i]->kind == EX_UNDEF)
                    e->as.array.items[i]->type = element;
                item = check_expr(c, fn, e->as.array.items[i]);
                check_zeroable(c, e->as.array.items[i], element);
                if (item.kind == TY_UNTYPED_INT && element.kind == TY_INT) {
                    coerce_untyped_integer(e->as.array.items[i], element);
                    item = element;
                }
                if (!type_assignable(item, element))
                    diagnostic_at(c, &e->as.array.items[i]->token, "E-TYPE-0002",
                                  "array literal element has the wrong type");
            }
            return e->type;
        }
        case EX_STRUCT_LITERAL: {
            StructDecl *scoped_decl = find_struct_scoped(c, fn->module,
                                                         e->as.aggregate.type_name);
            if (scoped_decl) {
                copy_text(e->as.aggregate.type_name, sizeof(e->as.aggregate.type_name),
                          scoped_decl->name, strlen(scoped_decl->name));
                copy_text(e->type.name, sizeof(e->type.name), scoped_decl->name,
                          strlen(scoped_decl->name));
            }
            if (e->type.kind == TY_NAMED && e->type.generic_arg_count) {
                resolve_type_constants(c, &e->type, &e->token);
                copy_text(e->as.aggregate.type_name, sizeof(e->as.aggregate.type_name),
                          e->type.name, strlen(e->type.name));
            }
            StructDecl *decl = find_struct(c, e->as.aggregate.type_name);
            unsigned char seen[MAX_FIELDS];
            memset(seen, 0, sizeof(seen));
            if (!decl) {
                diagnostic_at(c, &e->token, "E-NAME-9999", "unknown aggregate type in literal");
                e->type = type_make(TY_INVALID, 0);
                return e->type;
            }
            if (decl->kind == ND_ENUM) {
                diagnostic_at(c, &e->token, "E-TYPE-9999", "enum values use member syntax, not aggregate literals");
                e->type = type_make(TY_INVALID, 0);
                return e->type;
            }
            e->type = type_make(TY_NAMED, decl->name);
            if ((decl->kind == ND_UNION || decl->kind == ND_TAGGED_UNION) &&
                e->as.aggregate.item_count != 1)
                diagnostic_at(c, &e->token, "E-TYPE-9999", "union literal must name exactly one member");
            for (i = 0; i < e->as.aggregate.item_count; ++i) {
                StructInit *item = &e->as.aggregate.items[i];
                int field_index = -1;
                FieldDecl *field = find_struct_field(decl, item->name, &field_index);
                Type actual;
                if (!field) {
                    diagnostic_at(c, &item->token, "E-NAME-9999", "unknown aggregate member in literal");
                    continue;
                }
                item->field_index = field_index;
                if (seen[field_index])
                    diagnostic_at(c, &item->token, "E-NAME-0001", "duplicate field in struct literal");
                seen[field_index] = 1;
                if (!item->value) {
                    if (decl->kind != ND_TAGGED_UNION || field->has_payload)
                        diagnostic_at(c, &item->token, "E-TYPE-9999", "aggregate member requires a value");
                    continue;
                }
                if (item->value->kind == EX_ENUM_MEMBER)
                    resolve_contextual_member(c, item->value, field->type);
                actual = check_expr(c, fn, item->value);
                if (item->value->kind == EX_ZERO || item->value->kind == EX_UNDEF) {
                    item->value->type = field->type;
                    actual = field->type;
                }
                check_zeroable(c, item->value, field->type);
                if (actual.kind == TY_UNTYPED_INT && field->type.kind == TY_INT) {
                    coerce_untyped_integer(item->value, field->type); actual = field->type;
                }
                if (!type_assignable(actual, field->type))
                    diagnostic_at(c, &item->token, "E-TYPE-0002",
                                   "aggregate literal member has the wrong type");
            }
            if (decl->kind == ND_STRUCT)
                for (i = 0; i < decl->field_count; ++i)
                    if (!seen[i]) diagnostic_at(c, &e->token, "E-TYPE-9999", "struct literal omits a field");
            return e->type;
        }
        case EX_NAME:
            if (strcmp(e->as.name, "ok") == 0) return e->type;
            if (resolve_qualified_member(c, e, fn->module)) return e->type;
            {
                ErrorDecl *error = find_error_scoped(c, fn->module, e->as.name);
                if (error) {
                    e->type = type_make(TY_ERR, "err"); e->error_code = error->code; return e->type;
                }
            }
            {
                ConstDecl *constant = find_constant_scoped(c, fn->module, e->as.name);
                if (constant && evaluate_constant(c, constant)) {
                    e->type = constant->type;
                    e->constant_value = constant->integer_value;
                    e->is_constant = 1;
                    return e->type;
                }
            }
            e->type = resolve_name_place(c, fn, e);
            if (e->type.kind == TY_INVALID) {
                if (e->local_index < 0)
                    diagnostic_at(c, &e->token, "E-NAME-9999", "unknown value name");
                return type_make(TY_INVALID, 0);
            }
            return e->type;
        case EX_FIELD: {
            Type base = check_expr(c, fn, e->as.field.base);
            StructDecl *decl;
            FieldDecl *field;
            if (strcmp(e->as.field.name, "len") == 0 &&
                (base.kind == TY_ARRAY || base.kind == TY_SLICE || base.kind == TY_STR)) {
                e->is_len = 1;
                e->place_type = base;
                e->type = type_make(TY_INT, "usize");
                return e->type;
            }
            if (base.kind == TY_POINTER) {
                e->place_mutable = !base.is_const;
                base = pointer_element_type(base);
            } else {
                e->place_mutable = e->as.field.base->place_mutable;
            }
            if (base.kind != TY_NAMED || !(decl = find_struct(c, base.name)) || decl->kind == ND_ENUM) {
                diagnostic_at(c, &e->token, "E-TYPE-9999", "field access requires an aggregate value or pointer");
                e->type = type_make(TY_INVALID, 0);
                return e->type;
            }
            if (decl->kind == ND_TAGGED_UNION && strcmp(e->as.field.name, "tag") == 0) {
                char tag_name[160];
                snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
                e->as.field.offset = 0;
                e->type = type_make(TY_NAMED, tag_name);
                return e->type;
            }
            field = find_struct_field(decl, e->as.field.name, 0);
            if (!field) {
                diagnostic_at(c, &e->token, "E-NAME-9999", "unknown aggregate field or member");
                e->type = type_make(TY_INVALID, 0);
                return e->type;
            }
            e->as.field.offset = (int)field->offset;
            if (decl->kind == ND_TAGGED_UNION) {
                e->as.field.tag_check = 1;
                e->as.field.tag_size = (int)scalar_byte_size(decl->backing_type);
                e->as.field.tag_value = field->value;
            }
            e->type = field->type;
            return e->type;
        }
        case EX_INDEX: {
            Type base = check_expr(c, fn, e->as.index.base);
            Type index = check_expr(c, fn, e->as.index.index);
            if (index.kind == TY_UNTYPED_INT) {
                Type usize_type = type_make(TY_INT, "usize");
                coerce_untyped_integer(e->as.index.index, usize_type); index = usize_type;
            }
            if (index.kind != TY_INT || strcmp(index.name, "usize") != 0)
                diagnostic_at(c, &e->as.index.index->token, "E-TYPE-9999", "slice index must be usize");
            if (base.kind == TY_STR) e->type = type_make(TY_INT, "u8");
            else if (base.kind == TY_SLICE) {
                if (strcmp(base.name, "str") == 0) e->type = type_make(TY_STR, "str");
                else e->type = sequence_element_type(base);
            } else if (base.kind == TY_ARRAY) {
                e->type = array_element_type(base);
            } else {
                diagnostic_at(c, &e->token, "E-TYPE-9999", "indexing requires a slice or array");
                e->type = type_make(TY_INVALID, 0);
            }
            if (base.kind == TY_ARRAY) e->place_mutable = e->as.index.base->place_mutable;
            else if (base.kind == TY_SLICE) e->place_mutable = !base.is_const;
            else e->place_mutable = 0;
            return e->type;
        }
        case EX_SLICE: {
            Type base = check_expr(c, fn, e->as.slice.base);
            Type usize_type = type_make(TY_INT, "usize");
            Type element;
            int is_const = 0;
            if (e->as.slice.start) {
                Type start = check_expr(c, fn, e->as.slice.start);
                if (start.kind == TY_UNTYPED_INT) {
                    coerce_untyped_integer(e->as.slice.start, usize_type); start = usize_type;
                }
                if (!type_equal(start, usize_type))
                    diagnostic_at(c, &e->as.slice.start->token, "E-TYPE-9999",
                                  "slice lower bound must be usize");
            }
            if (e->as.slice.end) {
                Type end = check_expr(c, fn, e->as.slice.end);
                if (end.kind == TY_UNTYPED_INT) {
                    coerce_untyped_integer(e->as.slice.end, usize_type); end = usize_type;
                }
                if (!type_equal(end, usize_type))
                    diagnostic_at(c, &e->as.slice.end->token, "E-TYPE-9999",
                                  "slice upper bound must be usize");
            }
            if (!(base.kind == TY_ARRAY || base.kind == TY_SLICE || base.kind == TY_STR)) {
                diagnostic_at(c, &e->token, "E-TYPE-9999", "slicing requires an array or slice");
                e->type = type_make(TY_INVALID, 0);
                return e->type;
            }
            element = sequence_element_type(base);
            if (base.kind == TY_STR) is_const = 1;
            else if (base.kind == TY_SLICE) is_const = base.is_const;
            else {
                is_const = 1;
                if (e->as.slice.base->kind == EX_NAME && e->as.slice.base->local_index >= 0)
                    is_const = !fn->locals[e->as.slice.base->local_index].is_mutable;
            }
            if (is_const && element.kind == TY_INT && strcmp(element.name, "u8") == 0)
                e->type = type_make(TY_STR, "str");
            else {
                e->type = type_make(TY_SLICE, element.name);
                type_set_element(&e->type, element);
                e->type.is_const = is_const;
            }
            return e->type;
        }
        case EX_CALL: {
            Type result;
            if (strcmp(e->as.call.callee, "io.print") == 0) {
                if (e->as.call.arg_count != 1) diagnostic_at(c, &e->token, "E-TYPE-0003", "io.print expects one argument");
                else if (!type_equal(check_expr(c, fn, e->as.call.args[0]), type_make(TY_STR, "str")))
                    diagnostic_at(c, &e->as.call.args[0]->token, "E-TYPE-0003", "io.print expects str");
                result = type_make(TY_ERR, "err");
            } else {
                Function *callee = check_declared_call(c, fn, e);
                if (!callee) result = type_make(TY_INVALID, 0);
                else {
                    if (callee->return_count > 1) {
                        diagnostic_at(c, &e->token, "E-TYPE-9999",
                                      "a multiple-return call requires destructuring or protocol iteration");
                        result = type_make(TY_INVALID, 0);
                    } else result = callee->return_type;
                }
            }
            e->type = result; return result;
        }
        case EX_BINARY: {
            Type a, b;
            if (e->as.binary.left->kind == EX_ENUM_MEMBER &&
                e->as.binary.right->kind != EX_ENUM_MEMBER) {
                b = check_expr(c, fn, e->as.binary.right);
                resolve_contextual_member(c, e->as.binary.left, b);
                a = check_expr(c, fn, e->as.binary.left);
            } else {
                a = check_expr(c, fn, e->as.binary.left);
                if (e->as.binary.right->kind == EX_ENUM_MEMBER)
                    resolve_contextual_member(c, e->as.binary.right, a);
                b = check_expr(c, fn, e->as.binary.right);
            }
            if (e->as.binary.op == TK_AND || e->as.binary.op == TK_OR) {
                if (a.kind != TY_BOOL || b.kind != TY_BOOL)
                    diagnostic_at(c, &e->token, "E-TYPE-9999", "logical operators require bool operands");
                e->type = type_make(TY_BOOL, "bool");
            } else {
                if (a.kind == TY_UNTYPED_INT && b.kind == TY_INT) {
                    coerce_untyped_integer(e->as.binary.left, b); a = b;
                } else if (b.kind == TY_UNTYPED_INT && a.kind == TY_INT) {
                    coerce_untyped_integer(e->as.binary.right, a); b = a;
                }
                if (a.kind == TY_BOOL || b.kind == TY_BOOL || a.kind == TY_ERR || b.kind == TY_ERR) {
                    if (!type_equal(a, b) || !(e->as.binary.op == TK_EQ || e->as.binary.op == TK_NE))
                        diagnostic_at(c, &e->token, "E-TYPE-9999", "bool and err values support equality only with the same type");
                } else if (a.kind == TY_NAMED || b.kind == TY_NAMED) {
                    if (!type_equal(a, b) || !enum_decl_for_type(c, a) ||
                        !(e->as.binary.op == TK_EQ || e->as.binary.op == TK_NE ||
                          e->as.binary.op == TK_LT || e->as.binary.op == TK_LE ||
                          e->as.binary.op == TK_GT || e->as.binary.op == TK_GE))
                        diagnostic_at(c, &e->token, "E-TYPE-9999", "enum operators require matching enum types and a comparison operator");
                } else if ((a.kind != TY_INT && a.kind != TY_UNTYPED_INT) ||
                           (b.kind != TY_INT && b.kind != TY_UNTYPED_INT))
                    diagnostic_at(c, &e->token, "E-TYPE-9999",
                                  "the bootstrap currently supports integer arithmetic and comparisons");
                else if (a.kind == TY_INT && b.kind == TY_INT && !type_equal(a, b))
                    diagnostic_at(c, &e->token, "E-TYPE-0002", "integer operands have different types");
            }
            if (e->as.binary.op == TK_EQ || e->as.binary.op == TK_NE || e->as.binary.op == TK_LT ||
                e->as.binary.op == TK_LE || e->as.binary.op == TK_GT || e->as.binary.op == TK_GE)
                e->type = type_make(TY_BOOL, "bool");
            else if (e->as.binary.op != TK_AND && e->as.binary.op != TK_OR)
                e->type = a.kind == TY_INT ? a : (b.kind == TY_INT ? b : type_make(TY_UNTYPED_INT, ""));
            if ((e->as.binary.op == TK_EQ || e->as.binary.op == TK_NE || e->as.binary.op == TK_LT ||
                 e->as.binary.op == TK_LE || e->as.binary.op == TK_GT || e->as.binary.op == TK_GE) &&
                a.kind == TY_UNTYPED_INT && b.kind == TY_UNTYPED_INT)
                diagnostic_at(c, &e->token, "E-TYPE-0001", "integer comparison has no typing context");
            return e->type;
        }
        case EX_UNARY:
            e->type = check_expr(c, fn, e->as.unary.value);
            if (e->as.unary.op == TK_AMP) {
                Expr *place = e->as.unary.value;
                int mutable = 0;
                Type pointer;
                if ((place->kind == EX_NAME && !place->is_len) ||
                    (place->kind == EX_FIELD && !place->is_len))
                    mutable = place->place_mutable;
                else if (place->kind == EX_INDEX) {
                    Type base = place->as.index.base->type;
                    if (base.kind == TY_ARRAY) mutable = place->as.index.base->place_mutable;
                    else if (base.kind == TY_SLICE) mutable = !base.is_const;
                } else if (place->kind == EX_UNARY && place->as.unary.op == TK_STAR) {
                    mutable = !place->as.unary.value->type.is_const;
                } else {
                    diagnostic_at(c, &e->token, "E-TYPE-9999", "address-of requires a place");
                    e->type = type_make(TY_INVALID, 0);
                    return e->type;
                }
                pointer = type_make(TY_POINTER, e->type.name);
                type_set_element(&pointer, e->type);
                pointer.is_const = !mutable;
                e->type = pointer;
            } else if (e->as.unary.op == TK_STAR) {
                if (e->type.kind != TY_POINTER) {
                    diagnostic_at(c, &e->token, "E-TYPE-9999", "dereference requires a pointer");
                    e->type = type_make(TY_INVALID, 0);
                } else e->type = pointer_element_type(e->type);
            } else if (e->as.unary.op == TK_BANG) {
                if (e->type.kind != TY_BOOL) diagnostic_at(c, &e->token, "E-TYPE-9999", "`!` requires bool");
                e->type = type_make(TY_BOOL, "bool");
            } else if (e->type.kind != TY_INT && e->type.kind != TY_UNTYPED_INT)
                diagnostic_at(c, &e->token, "E-TYPE-9999", "unary `-` requires an integer");
            return e->type;
    }
    return type_make(TY_INVALID, 0);
}

static void prepare_deferred_call(Compiler *c, Function *fn, Stmt *defer,
                                  Expr *call, int discarded) {
    Type result = check_expr(c, fn, call);
    int i;
    if (!discarded && result.kind != TY_VOID)
        diagnostic_at(c, &call->token, "E-TYPE-9999",
                      "a deferred call returning a value must use `defer let _ = call()`");
    defer->as.defer_stmt.is_captured_call = 1;
    defer->as.defer_stmt.call = call;
    for (i = 0; i < call->as.call.arg_count; ++i) {
        Expr *source = call->as.call.args[i];
        Expr *captured;
        Local *local;
        char name[96];
        if (fn->local_count >= MAX_LOCALS) {
            diagnostic_at(c, &source->token, "E-TOOL-9999", "local limit exceeded by defer captures");
            break;
        }
        local = &fn->locals[fn->local_count];
        memset(local, 0, sizeof(*local));
        snprintf(name, sizeof(name), "$defer_%d_%d", fn->local_count, i);
        strcpy(local->name, name);
        local->type = source->type;
        local->token = source->token;
        local->active = 1;
        defer->as.defer_stmt.capture_values[defer->as.defer_stmt.capture_count] = source;
        defer->as.defer_stmt.capture_locals[defer->as.defer_stmt.capture_count++] = fn->local_count;
        captured = new_expr(EX_NAME, source->token);
        strcpy(captured->as.name, name);
        captured->type = source->type;
        captured->local_index = fn->local_count;
        captured->place_mutable = 0;
        call->as.call.args[i] = captured;
        fn->local_count++;
    }
}

static void check_statements_in_scope(Compiler *c, Function *fn, Stmt *s,
                                      int loop_depth, int break_depth, int close_scope) {
    int scope_start = fn->local_count;
    for (; s; s = s->next) {
        switch (s->kind) {
            case ST_BIND: {
                Type actual;
                if (s->as.bind.declared_type.kind != TY_INVALID) {
                    qualify_type_for_module(c, &s->as.bind.declared_type, fn->module);
                    resolve_type_constants(c, &s->as.bind.declared_type, &s->token);
                }
                if (s->as.bind.declared_type.kind != TY_INVALID &&
                    s->as.bind.value->kind == EX_ENUM_MEMBER)
                    resolve_contextual_member(c, s->as.bind.value, s->as.bind.declared_type);
                actual = check_expr(c, fn, s->as.bind.value);
                Type chosen = s->as.bind.declared_type.kind == TY_INVALID ? actual : s->as.bind.declared_type;
                if (s->as.bind.declared_type.kind != TY_INVALID)
                    check_known_type(c, s->as.bind.declared_type, &s->token);
                if (s->as.bind.value->kind == EX_ZERO || s->as.bind.value->kind == EX_UNDEF) {
                    if (s->as.bind.declared_type.kind == TY_INVALID) {
                        diagnostic_at(c, &s->token, "E-TYPE-0001",
                                      "zero and undef require an explicit binding type");
                    } else {
                        s->as.bind.value->type = s->as.bind.declared_type;
                        actual = chosen = s->as.bind.declared_type;
                        check_zeroable(c, s->as.bind.value, chosen);
                    }
                }
                if (actual.kind == TY_UNTYPED_INT && chosen.kind == TY_INT) {
                    coerce_untyped_integer(s->as.bind.value, chosen); actual = chosen;
                }
                if (s->as.bind.declared_type.kind == TY_INVALID && actual.kind == TY_UNTYPED_INT)
                    diagnostic_at(c, &s->token, "E-TYPE-0001", "integer initializer has no typing context");
                if (s->as.bind.declared_type.kind != TY_INVALID && !type_assignable(actual, chosen))
                    diagnostic_at(c, &s->token, "E-TYPE-0002", "initializer type does not match binding");
                if (chosen.kind == TY_ARRAY) {
                    Type element = array_element_type(chosen);
                    size_t element_size = type_size(c, element);
                    if (element_size != 0 && chosen.array_length > (size_t)INT_MAX / element_size)
                        diagnostic_at(c, &s->token, "E-TYPE-0004", "local array is too large");
                }
                if (chosen.kind == TY_NAMED) {
                    StructDecl *decl = find_struct(c, chosen.name);
                    if (!decl || !layout_struct(c, decl))
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "binding has an unknown named type");
                }
                if (find_local(fn, s->as.bind.name) >= 0)
                    diagnostic_at(c, &s->token, "E-NAME-0001", "duplicate local declaration");
                else if (fn->local_count < MAX_LOCALS) {
                    Local *local = &fn->locals[fn->local_count];
                    memset(local, 0, sizeof(*local)); strcpy(local->name, s->as.bind.name);
                    local->type = chosen; local->token = s->token;
                    local->is_mutable = s->as.bind.is_mutable;
                    local->active = 1;
                    s->as.bind.local_index = fn->local_count++;
                }
                break;
            }
            case ST_MULTI_BIND: {
                Function *callee = 0;
                int i, j;
                if (s->as.multi.call->kind != EX_CALL ||
                    strcmp(s->as.multi.call->as.call.callee, "io.print") == 0) {
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "multiple binding requires a multiple-return function call");
                    break;
                }
                callee = check_declared_call(c, fn, s->as.multi.call);
                if (!callee) break;
                if (callee->return_count != s->as.multi.count) {
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "multiple binding count does not match function results");
                    break;
                }
                s->as.multi.call->type = callee->return_types[0];
                for (i = 0; i < s->as.multi.count; ++i) {
                    Local *local;
                    if (strcmp(s->as.multi.names[i], "_") == 0) continue;
                    for (j = 0; j < i; ++j)
                        if (strcmp(s->as.multi.names[i], s->as.multi.names[j]) == 0)
                            diagnostic_at(c, &s->token, "E-NAME-0001", "duplicate name in multiple binding");
                    if (find_local(fn, s->as.multi.names[i]) >= 0) {
                        diagnostic_at(c, &s->token, "E-NAME-0001", "duplicate local declaration");
                        continue;
                    }
                    if (fn->local_count >= MAX_LOCALS) {
                        diagnostic_at(c, &s->token, "E-TOOL-9999", "local limit exceeded");
                        break;
                    }
                    local = &fn->locals[fn->local_count];
                    memset(local, 0, sizeof(*local));
                    strcpy(local->name, s->as.multi.names[i]);
                    local->type = callee->return_types[i];
                    local->token = s->token;
                    local->is_mutable = s->as.multi.is_mutable;
                    local->active = 1;
                    s->as.multi.local_indices[i] = fn->local_count++;
                }
                break;
            }
            case ST_ASSIGN: {
                Type target = check_expr(c, fn, s->as.assign.target);
                int index = s->as.assign.target->local_index;
                if (s->as.assign.value->kind == EX_ZERO || s->as.assign.value->kind == EX_UNDEF)
                    s->as.assign.value->type = target;
                if (s->as.assign.value->kind == EX_ENUM_MEMBER)
                    resolve_contextual_member(c, s->as.assign.value, target);
                Type actual = check_expr(c, fn, s->as.assign.value);
                check_zeroable(c, s->as.assign.value, target);
                if (index < 0) diagnostic_at(c, &s->token, "E-NAME-9999", "unknown assignment target");
                else {
                    s->as.assign.local_index = index;
                    if (actual.kind == TY_UNTYPED_INT && target.kind == TY_INT) {
                        coerce_untyped_integer(s->as.assign.value, target);
                        actual = target;
                    }
                    if (!s->as.assign.target->place_mutable || s->as.assign.target->is_len)
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "assignment target is immutable");
                    if (!type_assignable(actual, target)) diagnostic_at(c, &s->token, "E-TYPE-0002", "assignment type mismatch");
                    if (s->as.assign.op == TK_ADD_ASSIGN &&
                        (target.kind != TY_INT || actual.kind != TY_INT))
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "`+=` requires integer operands");
                }
                break;
            }
            case ST_MULTI_ASSIGN: {
                Function *callee = 0;
                int i;
                if (s->as.multi.call->kind != EX_CALL ||
                    strcmp(s->as.multi.call->as.call.callee, "io.print") == 0) {
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "multiple assignment requires a multiple-return function call");
                    break;
                }
                callee = check_declared_call(c, fn, s->as.multi.call);
                if (!callee) break;
                if (callee->return_count != s->as.multi.count) {
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "multiple assignment count does not match function results");
                    break;
                }
                s->as.multi.call->type = callee->return_types[0];
                for (i = 0; i < s->as.multi.count; ++i) {
                    int local_index;
                    if (strcmp(s->as.multi.names[i], "_") == 0) continue;
                    local_index = find_local(fn, s->as.multi.names[i]);
                    if (local_index < 0) {
                        diagnostic_at(c, &s->token, "E-NAME-9999",
                                      "unknown target in multiple assignment");
                        continue;
                    }
                    s->as.multi.local_indices[i] = local_index;
                    if (!fn->locals[local_index].is_mutable)
                        diagnostic_at(c, &s->token, "E-TYPE-9999",
                                      "multiple assignment target is immutable");
                    if (!type_assignable(callee->return_types[i], fn->locals[local_index].type))
                        diagnostic_at(c, &s->token, "E-TYPE-0002",
                                      "multiple assignment result type mismatch");
                }
                break;
            }
            case ST_INDEX_ASSIGN: {
                Expr *target_expr = s->as.index_assign.target;
                Type target = check_expr(c, fn, target_expr);
                if (s->as.index_assign.value->kind == EX_ZERO || s->as.index_assign.value->kind == EX_UNDEF)
                    s->as.index_assign.value->type = target;
                if (s->as.index_assign.value->kind == EX_ENUM_MEMBER)
                    resolve_contextual_member(c, s->as.index_assign.value, target);
                Type actual = check_expr(c, fn, s->as.index_assign.value);
                check_zeroable(c, s->as.index_assign.value, target);
                if (actual.kind == TY_UNTYPED_INT && target.kind == TY_INT) {
                    coerce_untyped_integer(s->as.index_assign.value, target);
                    actual = target;
                }
                if (!type_assignable(actual, target))
                    diagnostic_at(c, &s->token, "E-TYPE-0002", "place assignment type mismatch");
                if (target_expr->kind == EX_INDEX) {
                    Expr *base_expr = target_expr->as.index.base;
                    Type base = base_expr->type;
                    if (base.kind == TY_ARRAY) {
                        if (!base_expr->place_mutable)
                            diagnostic_at(c, &s->token, "E-TYPE-9999",
                                          "indexed assignment requires a mutable array binding");
                    } else if (base.kind == TY_STR || base.is_const) {
                        diagnostic_at(c, &s->token, "E-TYPE-9999",
                                      "indexed assignment requires mutable elements");
                    }
                } else if (target_expr->kind == EX_FIELD) {
                    if (!target_expr->place_mutable)
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "assignment target is immutable");
                } else if (target_expr->as.unary.value->type.is_const) {
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "dereference assignment requires a mutable pointer");
                }
                if (s->as.index_assign.op == TK_ADD_ASSIGN &&
                    (target.kind != TY_INT || actual.kind != TY_INT))
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "`+=` requires integer operands");
                break;
            }
            case ST_EXPR: {
                Type result = check_expr(c, fn, s->as.expr);
                if (s->as.expr->kind == EX_CALL && result.kind != TY_VOID)
                    diagnostic_at(c, &s->token, "E-TYPE-9999",
                                  "a call returning a value must be bound, discarded with `let _`, or used by `try`");
                break;
            }
            case ST_TRY:
                if (c->checking_defer)
                    diagnostic_at(c, &s->token, "E-ERROR-9999", "try is not legal inside defer");
                if (check_expr(c, fn, s->as.expr).kind != TY_ERR || fn->return_type.kind != TY_ERR)
                    diagnostic_at(c, &s->token, "E-ERROR-9999", "try requires an err expression in an err-returning function");
                break;
            case ST_RETURN: {
                int return_index;
                if (c->checking_defer)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "ret is not legal inside defer");
                if (s->as.ret.value_count != fn->return_count) {
                    if (!(s->as.ret.value_count == 0 && fn->return_count == 0))
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "return value count does not match function signature");
                }
                for (return_index = 0; return_index < s->as.ret.value_count && return_index < fn->return_count; ++return_index) {
                    Expr *value = s->as.ret.values[return_index];
                    Type expected = fn->return_types[return_index];
                    Type actual;
                    if (value->kind == EX_ZERO || value->kind == EX_UNDEF) value->type = expected;
                    if (value->kind == EX_ENUM_MEMBER) resolve_contextual_member(c, value, expected);
                    actual = check_expr(c, fn, value);
                    check_zeroable(c, value, expected);
                    if (actual.kind == TY_UNTYPED_INT && expected.kind == TY_INT) {
                        coerce_untyped_integer(value, expected); actual = expected;
                    }
                    if (!type_assignable(actual, expected))
                        diagnostic_at(c, &value->token, "E-TYPE-9999", "return type mismatch");
                }
                break;
            }
            case ST_IF:
                if (check_expr(c, fn, s->as.if_stmt.condition).kind != TY_BOOL)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "if condition must be bool");
                check_statements_in_scope(c, fn, s->as.if_stmt.then_body, loop_depth, break_depth, 1);
                check_statements_in_scope(c, fn, s->as.if_stmt.else_body, loop_depth, break_depth, 1);
                break;
            case ST_WHILE:
                if (check_expr(c, fn, s->as.while_stmt.condition).kind != TY_BOOL)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "while condition must be bool");
                if (loop_depth >= MAX_LOOP_DEPTH)
                    diagnostic_at(c, &s->token, "E-TOOL-9999", "loop nesting limit exceeded");
                else
                    check_statements_in_scope(c, fn, s->as.while_stmt.body, loop_depth + 1, break_depth + 1, 1);
                break;
            case ST_FOR_RANGE: {
                Type start = check_expr(c, fn, s->as.for_range.start);
                Type end = check_expr(c, fn, s->as.for_range.end);
                int range_start;
                if (start.kind == TY_UNTYPED_INT && end.kind == TY_INT) {
                    coerce_untyped_integer(s->as.for_range.start, end); start = end;
                } else if (end.kind == TY_UNTYPED_INT && start.kind == TY_INT) {
                    coerce_untyped_integer(s->as.for_range.end, start); end = start;
                }
                if (start.kind == TY_UNTYPED_INT && end.kind == TY_UNTYPED_INT)
                    diagnostic_at(c, &s->token, "E-TYPE-0001", "range bounds have no typing context");
                else if (start.kind != TY_INT || end.kind != TY_INT)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "range bounds must be integers");
                else if (!type_equal(start, end))
                    diagnostic_at(c, &s->token, "E-TYPE-0002", "range bounds have different types");
                if (find_local(fn, s->as.for_range.name) >= 0) {
                    diagnostic_at(c, &s->token, "E-NAME-0003", "range binding shadows an active name");
                    break;
                }
                range_start = fn->local_count;
                if (fn->local_count + 2 <= MAX_LOCALS) {
                    Local *index = &fn->locals[fn->local_count];
                    Local *limit = &fn->locals[fn->local_count + 1];
                    memset(index, 0, sizeof(*index));
                    memset(limit, 0, sizeof(*limit));
                    strcpy(index->name, s->as.for_range.name);
                    snprintf(limit->name, sizeof(limit->name), "$range_end_%d", fn->local_count);
                    index->type = start; index->is_mutable = 0; index->active = 1;
                    limit->type = start; limit->is_mutable = 0; limit->active = 1;
                    index->token = limit->token = s->token;
                    s->as.for_range.local_index = fn->local_count++;
                    s->as.for_range.end_local_index = fn->local_count++;
                    if (loop_depth >= MAX_LOOP_DEPTH)
                        diagnostic_at(c, &s->token, "E-TOOL-9999", "loop nesting limit exceeded");
                    else
                        check_statements_in_scope(c, fn, s->as.for_range.body, loop_depth + 1, break_depth + 1, 1);
                    fn->locals[range_start].active = 0;
                    fn->locals[range_start + 1].active = 0;
                } else {
                    diagnostic_at(c, &s->token, "E-TOOL-9999", "local limit exceeded");
                }
                break;
            }
            case ST_FOR_EACH: {
                Type sequence = check_expr(c, fn, s->as.for_each.subject);
                Type element;
                int local_start, i;
                if (!(sequence.kind == TY_ARRAY || sequence.kind == TY_SLICE || sequence.kind == TY_STR)) {
                    Type iterator_type = sequence;
                    Function *next;
                    Type pointer_type;
                    int subject_is_pointer = sequence.kind == TY_POINTER;
                    if (s->as.for_each.has_index) {
                        diagnostic_at(c, &s->token, "E-TYPE-9999",
                                      "protocol iteration has one value binding; index/value form is only for arrays and slices");
                        break;
                    }
                    if (subject_is_pointer) {
                        if (sequence.is_const) {
                            diagnostic_at(c, &s->token, "E-TYPE-9999", "iterator pointer must be mutable");
                            break;
                        }
                        iterator_type = pointer_element_type(sequence);
                    } else if (s->as.for_each.subject->kind != EX_NAME ||
                               s->as.for_each.subject->field_path_count != 0 ||
                               !s->as.for_each.subject->place_mutable) {
                        diagnostic_at(c, &s->token, "E-TYPE-9999",
                                      "iterator subject must be a mutable variable or a mutable pointer");
                        break;
                    }
                    if (iterator_type.kind != TY_NAMED) {
                        diagnostic_at(c, &s->token, "E-TYPE-9999", "iterator subject has no declaring type");
                        break;
                    }
                    iterator_next_name(iterator_type, s->as.for_each.next_function,
                                       sizeof(s->as.for_each.next_function));
                    next = find_function(c, s->as.for_each.next_function);
                    if (!next) {
                        char message[256];
                        snprintf(message, sizeof(message), "protocol iteration needs `fn %s(it: *%s) -> (T, bool)`",
                                 s->as.for_each.next_function, iterator_type.name);
                        diagnostic_at(c, &s->token, "E-NAME-9999", message);
                        break;
                    }
                    pointer_type = type_make(TY_POINTER, iterator_type.name);
                    type_set_element(&pointer_type, iterator_type);
                    if (next->param_count != 1 || !type_equal(next->params[0].type, pointer_type) ||
                        next->return_count != 2 || next->return_types[1].kind != TY_BOOL) {
                        diagnostic_at(c, &s->token, "E-TYPE-0003",
                                      "iterator next function must have signature `fn <type>_next(it: *I) -> (T, bool)`");
                        break;
                    }
                    element = next->return_types[0];
                    if (find_local(fn, s->as.for_each.value_name) >= 0) {
                        diagnostic_at(c, &s->token, "E-NAME-0003", "for binding shadows an active name");
                        break;
                    }
                    local_start = fn->local_count;
                    if (fn->local_count + 3 <= MAX_LOCALS) {
                        Local *pointer = &fn->locals[fn->local_count];
                        Local *has = &fn->locals[fn->local_count + 1];
                        Local *value = &fn->locals[fn->local_count + 2];
                        memset(pointer, 0, sizeof(*pointer)); memset(has, 0, sizeof(*has)); memset(value, 0, sizeof(*value));
                        snprintf(pointer->name, sizeof(pointer->name), "$iter_ptr_%d", local_start);
                        snprintf(has->name, sizeof(has->name), "$iter_has_%d", local_start);
                        strcpy(value->name, s->as.for_each.value_name);
                        pointer->type = pointer_type; has->type = type_make(TY_BOOL, "bool"); value->type = element;
                        pointer->token = has->token = value->token = s->token;
                        pointer->active = has->active = value->active = 1;
                        s->as.for_each.is_protocol = 1;
                        s->as.for_each.iterator_subject_is_pointer = subject_is_pointer;
                        s->as.for_each.iterator_pointer_local_index = fn->local_count++;
                        s->as.for_each.iterator_has_local_index = fn->local_count++;
                        s->as.for_each.value_local_index = fn->local_count++;
                        if (loop_depth >= MAX_LOOP_DEPTH)
                            diagnostic_at(c, &s->token, "E-TOOL-9999", "loop nesting limit exceeded");
                        else check_statements_in_scope(c, fn, s->as.for_each.body,
                                                       loop_depth + 1, break_depth + 1, 1);
                        for (i = local_start; i < local_start + 3; ++i) fn->locals[i].active = 0;
                    } else diagnostic_at(c, &s->token, "E-TOOL-9999", "local limit exceeded");
                    break;
                }
                element = sequence_element_type(sequence);
                if (find_local(fn, s->as.for_each.value_name) >= 0 ||
                    (s->as.for_each.has_index && find_local(fn, s->as.for_each.index_name) >= 0)) {
                    diagnostic_at(c, &s->token, "E-NAME-0003", "for binding shadows an active name");
                    break;
                }
                if (s->as.for_each.has_index &&
                    strcmp(s->as.for_each.index_name, s->as.for_each.value_name) == 0) {
                    diagnostic_at(c, &s->token, "E-NAME-0001", "duplicate for binding");
                    break;
                }
                local_start = fn->local_count;
                if (fn->local_count + 4 <= MAX_LOCALS) {
                    Type usize_type = type_make(TY_INT, "usize");
                    Type pointer_type = type_make(TY_POINTER, element.name);
                    Local *pointer = &fn->locals[fn->local_count];
                    Local *length = &fn->locals[fn->local_count + 1];
                    Local *index = &fn->locals[fn->local_count + 2];
                    Local *value = &fn->locals[fn->local_count + 3];
                    memset(pointer, 0, sizeof(*pointer)); memset(length, 0, sizeof(*length));
                    memset(index, 0, sizeof(*index)); memset(value, 0, sizeof(*value));
                    snprintf(pointer->name, sizeof(pointer->name), "$for_ptr_%d", local_start);
                    snprintf(length->name, sizeof(length->name), "$for_len_%d", local_start);
                    if (s->as.for_each.has_index) strcpy(index->name, s->as.for_each.index_name);
                    else snprintf(index->name, sizeof(index->name), "$for_index_%d", local_start);
                    strcpy(value->name, s->as.for_each.value_name);
                    type_set_element(&pointer_type, element);
                    pointer->type = pointer_type; length->type = usize_type;
                    index->type = usize_type; value->type = element;
                    pointer->token = length->token = index->token = value->token = s->token;
                    pointer->active = length->active = index->active = value->active = 1;
                    s->as.for_each.pointer_local_index = fn->local_count++;
                    s->as.for_each.length_local_index = fn->local_count++;
                    s->as.for_each.index_local_index = fn->local_count++;
                    s->as.for_each.value_local_index = fn->local_count++;
                    if (loop_depth >= MAX_LOOP_DEPTH)
                        diagnostic_at(c, &s->token, "E-TOOL-9999", "loop nesting limit exceeded");
                    else
                        check_statements_in_scope(c, fn, s->as.for_each.body,
                                                  loop_depth + 1, break_depth + 1, 1);
                    for (i = local_start; i < local_start + 4; ++i) fn->locals[i].active = 0;
                } else {
                    diagnostic_at(c, &s->token, "E-TOOL-9999", "local limit exceeded");
                }
                break;
            }
            case ST_SWITCH: {
                Type subject = check_expr(c, fn, s->as.switch_stmt.subject);
                StructDecl *decl = enum_decl_for_type(c, subject);
                int tagged_subject = decl && decl->kind == ND_TAGGED_UNION &&
                                     strcmp(subject.name, decl->name) == 0;
                Type case_type = subject;
                unsigned char seen[MAX_FIELDS];
                int default_seen = 0;
                SwitchCase *arm;
                memset(seen, 0, sizeof(seen));
                if (tagged_subject) {
                    char tag_name[160];
                    snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
                    case_type = type_make(TY_NAMED, tag_name);
                }
                if (!decl && !(subject.kind == TY_INT || subject.kind == TY_BOOL || subject.kind == TY_ERR))
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "switch subject must be an enum, tagged union, integer, bool, or err");
                for (arm = s->as.switch_stmt.cases; arm; arm = arm->next) {
                    int scope_local = -1, value_index;
                    if (arm->is_default) {
                        if (default_seen++) diagnostic_at(c, &arm->token, "E-NAME-0001", "duplicate default case");
                        if (arm->binding[0]) diagnostic_at(c, &arm->token, "E-TYPE-9999", "default case cannot bind a payload");
                    } else {
                        if (arm->value_count == 0)
                            diagnostic_at(c, &arm->token, "E-SYNTAX-9999", "case requires at least one value");
                        for (value_index = 0; value_index < arm->value_count; ++value_index) {
                            Expr *value = arm->values[value_index];
                            int member_index = -1, prior;
                            int64_t constant = 0;
                            Type actual;
                            if (value->kind == EX_ENUM_MEMBER) resolve_contextual_member(c, value, case_type);
                            actual = check_expr(c, fn, value);
                            if (!case_constant_value(value, &constant))
                                diagnostic_at(c, &value->token, "E-TYPE-9999", "switch case must be a compile-time constant");
                            if (decl) {
                                FieldDecl *member = 0;
                                if (value->kind == EX_ENUM_MEMBER)
                                    member = find_struct_field(decl, value->as.name, &member_index);
                                else if (actual.kind == TY_NAMED && type_equal(actual, case_type)) {
                                    for (prior = 0; prior < decl->field_count; ++prior)
                                        if (decl->fields[prior].value == value->as.integer) { member_index = prior; member = &decl->fields[prior]; break; }
                                }
                                if (!member) {
                                    diagnostic_at(c, &value->token, "E-TYPE-0002", "enum switch case has the wrong type or is not a member");
                                    continue;
                                }
                                value->constant_value = constant = member->value;
                                if (seen[member_index]) diagnostic_at(c, &value->token, "E-NAME-0001", "duplicate switch case value");
                                seen[member_index] = 1;
                                if (arm->value_count == 1) arm->member_index = member_index;
                            } else {
                                SwitchCase *previous;
                                if (actual.kind == TY_UNTYPED_INT && subject.kind == TY_INT) {
                                    coerce_untyped_integer(value, subject); actual = subject;
                                }
                                if (!type_assignable(actual, subject))
                                    diagnostic_at(c, &value->token, "E-TYPE-0002", "switch case has the wrong type");
                                for (previous = s->as.switch_stmt.cases; previous != arm; previous = previous->next) {
                                    int previous_index;
                                    for (previous_index = 0; previous_index < previous->value_count; ++previous_index) {
                                        int64_t previous_constant;
                                        if (case_constant_value(previous->values[previous_index], &previous_constant) &&
                                            previous_constant == constant)
                                            diagnostic_at(c, &value->token, "E-NAME-0001", "duplicate switch case value");
                                    }
                                }
                                for (prior = 0; prior < value_index; ++prior) {
                                    int64_t previous_constant;
                                    if (case_constant_value(arm->values[prior], &previous_constant) &&
                                        previous_constant == constant)
                                        diagnostic_at(c, &value->token, "E-NAME-0001", "duplicate switch case value");
                                }
                            }
                        }
                        if (arm->binding[0]) {
                            FieldDecl *member = tagged_subject && arm->member_index >= 0 ?
                                                &decl->fields[arm->member_index] : 0;
                            if (arm->value_count != 1 || !member || !member->has_payload)
                                diagnostic_at(c, &arm->token, "E-TYPE-9999", "payload binding requires one tagged-union case with a payload");
                            else if (find_local(fn, arm->binding) >= 0)
                                diagnostic_at(c, &arm->token, "E-NAME-0003", "payload binding shadows an active name");
                            else if (fn->local_count < MAX_LOCALS) {
                                Local *local = &fn->locals[fn->local_count];
                                memset(local, 0, sizeof(*local));
                                strcpy(local->name, arm->binding); local->type = member->type;
                                local->token = arm->token; local->active = 1;
                                arm->local_index = scope_local = fn->local_count++;
                            }
                        }
                    }
                    check_statements_in_scope(c, fn, arm->body, loop_depth, break_depth + 1, 1);
                    if (scope_local >= 0) fn->locals[scope_local].active = 0;
                }
                if (decl && !default_seen) {
                    int member_index;
                    for (member_index = 0; member_index < decl->field_count; ++member_index)
                        if (!seen[member_index]) {
                            char message[256];
                            snprintf(message, sizeof(message), "non-exhaustive switch; missing member `%s`", decl->fields[member_index].name);
                            diagnostic_at(c, &s->token, "E-TYPE-9999", message);
                        }
                }
                break;
            }
            case ST_DEFER: {
                Stmt *body = s->as.defer_stmt.body;
                if (!s->as.defer_stmt.is_block && body && body->kind == ST_EXPR &&
                    body->as.expr->kind == EX_CALL) {
                    prepare_deferred_call(c, fn, s, body->as.expr, 0);
                } else if (!s->as.defer_stmt.is_block && body && body->kind == ST_BIND &&
                           strcmp(body->as.bind.name, "_") == 0 && body->as.bind.value &&
                           body->as.bind.value->kind == EX_CALL) {
                    prepare_deferred_call(c, fn, s, body->as.bind.value, 1);
                } else {
                    c->checking_defer++;
                    check_statements_in_scope(c, fn, body, 0, 0, 1);
                    c->checking_defer--;
                }
                break;
            }
            case ST_BREAK:
                if (break_depth == 0)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "break requires an enclosing loop or switch");
                break;
            case ST_CONTINUE:
                if (loop_depth == 0)
                    diagnostic_at(c, &s->token, "E-TYPE-9999", "continue requires an enclosing loop");
                break;
        }
    }
    if (close_scope) {
        int i;
        for (i = scope_start; i < fn->local_count; ++i) fn->locals[i].active = 0;
    }
}

static void check_statements(Compiler *c, Function *fn, Stmt *s) {
    check_statements_in_scope(c, fn, s, 0, 0, 0);
}

static int path_exists(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) return 0; fclose(f); return 1;
}

static int directory_exists(const char *path) {
#ifdef _WIN32
    DWORD attributes = GetFileAttributesA(path);
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
#else
    struct stat info;
    return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
#endif
}

static void slash_path(char *path) {
#ifdef _WIN32
    char *p; for (p = path; *p; ++p) if (*p == '/') *p = '\\';
#else
    char *p; for (p = path; *p; ++p) if (*p == '\\') *p = '/';
#endif
}

static char *read_file(const char *path, size_t *length);

static void join_module_path(char *out, size_t capacity, const char *root,
                             const char *source_root, const char *module) {
    char relative[MAX_PATH_LEN];
    char *p;
    copy_text(relative, sizeof(relative), module, strlen(module));
    for (p = relative; *p; ++p) if (*p == '.') *p = PATH_SEP;
    out[0] = 0;
    if (!append_text(out, capacity, root) ||
        !append_character(out, capacity, PATH_SEP) ||
        !append_text(out, capacity, source_root) ||
        !append_character(out, capacity, PATH_SEP) ||
        !append_text(out, capacity, relative) ||
        !append_text(out, capacity, ".e")) out[0] = 0;
    slash_path(out);
}

static int source_for_module(Compiler *c, const char *module) {
    int i;
    for (i = 0; i < c->source_count; ++i)
        if (strcmp(c->sources[i].module, module) == 0) return i;
    return -1;
}

static int add_source_file(Compiler *c, const char *module, const char *path,
                           Token *import_token) {
    SourceFile *source;
    char *text;
    size_t length;
    if (c->source_count >= MAX_SOURCES) {
        diagnostic_at(c, import_token, "E-MODULE-9999", "source module limit exceeded");
        return -1;
    }
    text = read_file(path, &length);
    if (!text) {
        diagnostic_at(c, import_token, "E-MODULE-0001", "module source could not be read");
        return -1;
    }
    source = &c->sources[c->source_count];
    memset(source, 0, sizeof(*source));
    copy_text(source->path, sizeof(source->path), path, strlen(path));
    copy_text(source->module, sizeof(source->module), module, strlen(module));
    source->text = text;
    source->length = length;
    return c->source_count++;
}

static void parse_source_file(Compiler *c, int source_id, int root) {
    SourceFile *source = &c->sources[source_id];
    int errors_before = c->errors;
    if (source->parsed) return;
    source->parsed = 1;
    c->source_path = source->path;
    c->source = source->text;
    c->source_length = source->length;
    c->current_source_id = source_id;
    c->token_count = 0;
    c->current = 0;
    if (root) c->current_module[0] = 0;
    else copy_text(c->current_module, sizeof(c->current_module), source->module,
                   strlen(source->module));
    lex(c);
    if (root && c->token_count) {
        c->root_token = c->tokens[0];
        if (c->errors == errors_before) install_os_intrinsics(c);
    }
    if (c->errors == errors_before) parse_program(c);
}

static void load_imports(Compiler *c) {
    int at;
    for (at = 0; at < c->program.use_count; ++at) {
        UseDecl *use = &c->program.uses[at];
        char project_lib[MAX_PATH_LEN], project_src[MAX_PATH_LEN];
        char toolchain_lib[MAX_PATH_LEN], message[512];
        int project_lib_exists, project_src_exists, source_id;
        if (use->loaded) continue;
        if (strcmp(use->name, "e.mem") == 0 || strcmp(use->name, "e.io") == 0 ||
            strcmp(use->name, "e.os") == 0) {
            join_module_path(toolchain_lib, sizeof(toolchain_lib), c->executable_dir,
                             "lib", use->name);
            if (!path_exists(toolchain_lib)) {
                snprintf(message, sizeof(message), "module `%s` was not found", use->name);
                diagnostic_at(c, &use->token, "E-MODULE-0001", message);
            }
            use->loaded = 1;
            continue;
        }
        source_id = source_for_module(c, use->name);
        if (source_id >= 0) {
            use->loaded = 1;
            continue;
        }
        join_module_path(project_lib, sizeof(project_lib), c->project_root, "lib", use->name);
        join_module_path(project_src, sizeof(project_src), c->project_root, "src", use->name);
        project_lib_exists = path_exists(project_lib);
        project_src_exists = path_exists(project_src);
        if (project_lib_exists && project_src_exists) {
            snprintf(message, sizeof(message),
                     "module `%s` exists at both `%.180s` and `%.180s`",
                     use->name, project_lib, project_src);
            diagnostic_at(c, &use->token, "E-MODULE-9999", message);
            use->loaded = 1;
            continue;
        }
        if (project_lib_exists || project_src_exists) {
            source_id = add_source_file(c, use->name,
                                        project_lib_exists ? project_lib : project_src,
                                        &use->token);
        } else {
            join_module_path(toolchain_lib, sizeof(toolchain_lib), c->executable_dir,
                             "lib", use->name);
            if (path_exists(toolchain_lib))
                source_id = add_source_file(c, use->name, toolchain_lib, &use->token);
            else {
                snprintf(message, sizeof(message), "module `%s` was not found", use->name);
                diagnostic_at(c, &use->token, "E-MODULE-0001", message);
                source_id = -1;
            }
        }
        use->loaded = 1;
        if (source_id >= 0) parse_source_file(c, source_id, 0);
    }
}

static void append_cycle_name(char *message, size_t capacity, const char *name) {
    size_t used = strlen(message);
    if (used + strlen(name) + 5 >= capacity) return;
    if (used > strlen("module import cycle: ")) strcat(message, " -> ");
    strcat(message, name);
}

static void visit_module_graph(Compiler *c, int source_id, int *stack, int depth) {
    SourceFile *source = &c->sources[source_id];
    int i;
    source->visit_state = 1;
    stack[depth] = source_id;
    for (i = 0; i < c->program.use_count; ++i) {
        UseDecl *use = &c->program.uses[i];
        int target, start, at;
        char message[512];
        if (strcmp(use->owner_module, source->module) != 0) continue;
        target = source_for_module(c, use->name);
        if (target < 0) continue;
        if (c->sources[target].visit_state == 0) {
            visit_module_graph(c, target, stack, depth + 1);
            continue;
        }
        if (c->sources[target].visit_state != 1) continue;
        strcpy(message, "module import cycle: ");
        start = 0;
        while (start <= depth && stack[start] != target) start++;
        for (at = start; at <= depth; ++at)
            append_cycle_name(message, sizeof(message), c->sources[stack[at]].module);
        append_cycle_name(message, sizeof(message), c->sources[target].module);
        diagnostic_at(c, &use->token, "E-MODULE-9999", message);
    }
    source->visit_state = 2;
}

static void check_module_cycles(Compiler *c) {
    int stack[MAX_SOURCES];
    int i;
    for (i = 1; i < c->source_count; ++i)
        if (c->sources[i].visit_state == 0) visit_module_graph(c, i, stack, 0);
}

static void check_imports(Compiler *c) {
    int i, j;
    for (i = 0; i < c->program.use_count; ++i) {
        if (!c->program.uses[i].loaded)
            diagnostic_at(c, &c->program.uses[i].token, "E-MODULE-0001",
                          "module import was not loaded");
        for (j = 0; j < i; ++j)
            if (strcmp(c->program.uses[i].owner_module,
                       c->program.uses[j].owner_module) == 0 &&
                strcmp(c->program.uses[i].qualifier,
                       c->program.uses[j].qualifier) == 0)
                diagnostic_at(c, &c->program.uses[i].token, "E-NAME-0001",
                              "duplicate module qualifier");
    }
}

static void check_known_type(Compiler *c, Type type, Token *token) {
    Type element;
    if (type.kind == TY_NAMED && !find_struct(c, type.name) && !find_tag_owner(c, type.name)) {
        diagnostic_at(c, token, "E-NAME-9999", "unknown named type");
        return;
    }
    if (type.kind != TY_POINTER && type.kind != TY_SLICE && type.kind != TY_ARRAY) return;
    if (type.kind == TY_ARRAY) element = array_element_type(type);
    else if (type.element) element = *type.element;
    else {
        element = type_make(type.element_kind, type.element_name);
        element.is_const = type.element_is_const;
    }
    check_known_type(c, element, token);
}

static int evaluate_integer_expression(Compiler *c, Expr *expr, int64_t *out,
                                       Type *out_type);

static int evaluate_constant(Compiler *c, ConstDecl *constant) {
    Type actual;
    int64_t value;
    if (constant->evaluation_state == 2) return 1;
    if (constant->evaluation_state == 3) return 0;
    if (constant->evaluation_state == 1) {
        diagnostic_at(c, &constant->token, "E-TYPE-9999", "constant dependency cycle");
        constant->evaluation_state = 3;
        return 0;
    }
    constant->evaluation_state = 1;
    if (constant->type.kind != TY_INT) {
        diagnostic_at(c, &constant->token, "E-TYPE-9999",
                      "neper-0 constants currently require an integer type");
        constant->evaluation_state = 3;
        return 0;
    }
    if (!evaluate_integer_expression(c, constant->value, &value, &actual)) {
        constant->evaluation_state = 3;
        return 0;
    }
    if (actual.kind != TY_UNTYPED_INT && !type_equal(actual, constant->type)) {
        diagnostic_at(c, &constant->value->token, "E-TYPE-0002",
                      "constant initializer type does not match its declaration");
        constant->evaluation_state = 3;
        return 0;
    }
    if (strcmp(constant->type.name, "usize") == 0 && value < 0) {
        diagnostic_at(c, &constant->value->token, "E-TYPE-0004",
                      "constant value is not representable as usize");
        constant->evaluation_state = 3;
        return 0;
    }
    constant->integer_value = value;
    constant->value->constant_value = value;
    constant->value->is_constant = 1;
    constant->value->type = constant->type;
    constant->evaluation_state = 2;
    return 1;
}

static int checked_integer_binary(Compiler *c, Expr *expr, int64_t left,
                                  int64_t right, int64_t *out) {
    switch (expr->as.binary.op) {
        case TK_PLUS:
            if ((right > 0 && left > INT64_MAX - right) ||
                (right < 0 && left < INT64_MIN - right)) break;
            *out = left + right; return 1;
        case TK_MINUS:
            if ((right < 0 && left > INT64_MAX + right) ||
                (right > 0 && left < INT64_MIN + right)) break;
            *out = left - right; return 1;
        case TK_STAR:
            if (left == 0 || right == 0) { *out = 0; return 1; }
            if (left == -1 && right == INT64_MIN) break;
            if (right == -1 && left == INT64_MIN) break;
            if (left > 0) {
                if ((right > 0 && left > INT64_MAX / right) ||
                    (right < 0 && right < INT64_MIN / left)) break;
            } else {
                if ((right > 0 && left < INT64_MIN / right) ||
                    (right < 0 && left < INT64_MAX / right)) break;
            }
            *out = left * right; return 1;
        case TK_SLASH:
            if (right == 0) {
                diagnostic_at(c, &expr->token, "E-TYPE-9999",
                              "division by zero in constant expression");
                return 0;
            }
            if (left == INT64_MIN && right == -1) break;
            *out = left / right; return 1;
        case TK_PERCENT:
            if (right == 0) {
                diagnostic_at(c, &expr->token, "E-TYPE-9999",
                              "remainder by zero in constant expression");
                return 0;
            }
            if (left == INT64_MIN && right == -1) { *out = 0; return 1; }
            *out = left % right; return 1;
        default:
            diagnostic_at(c, &expr->token, "E-TYPE-9999",
                          "constant expression requires integer arithmetic");
            return 0;
    }
    diagnostic_at(c, &expr->token, "E-TYPE-0004", "constant integer overflow");
    return 0;
}

static int evaluate_integer_expression(Compiler *c, Expr *expr, int64_t *out,
                                       Type *out_type) {
    if (expr->kind == EX_INTEGER && expr->type.kind != TY_BOOL) {
        *out = expr->as.integer;
        *out_type = expr->type;
        return 1;
    }
    if (expr->kind == EX_NAME) {
        ConstDecl *constant = find_constant_scoped(c, c->resolution_module,
                                                   expr->as.name);
        if (!constant) {
            diagnostic_at(c, &expr->token, "E-NAME-9999",
                          "constant expression references an unknown constant");
            return 0;
        }
        if (!evaluate_constant(c, constant)) return 0;
        *out = constant->integer_value;
        *out_type = constant->type;
        expr->constant_value = *out;
        expr->is_constant = 1;
        expr->type = *out_type;
        return 1;
    }
    if (expr->kind == EX_UNARY && expr->as.unary.op == TK_MINUS) {
        if (!evaluate_integer_expression(c, expr->as.unary.value, out, out_type)) return 0;
        if (*out == INT64_MIN) {
            diagnostic_at(c, &expr->token, "E-TYPE-0004", "constant integer overflow");
            return 0;
        }
        *out = -*out;
        expr->constant_value = *out;
        expr->is_constant = 1;
        expr->type = *out_type;
        return 1;
    }
    if (expr->kind == EX_BINARY) {
        int64_t left, right;
        Type left_type, right_type;
        if (!evaluate_integer_expression(c, expr->as.binary.left, &left, &left_type) ||
            !evaluate_integer_expression(c, expr->as.binary.right, &right, &right_type)) return 0;
        if (left_type.kind == TY_UNTYPED_INT) *out_type = right_type;
        else if (right_type.kind == TY_UNTYPED_INT) *out_type = left_type;
        else if (type_equal(left_type, right_type)) *out_type = left_type;
        else {
            diagnostic_at(c, &expr->token, "E-TYPE-0002",
                          "constant expression operands have different types");
            return 0;
        }
        if (!checked_integer_binary(c, expr, left, right, out)) return 0;
        expr->constant_value = *out;
        expr->is_constant = 1;
        expr->type = *out_type;
        return 1;
    }
    diagnostic_at(c, &expr->token, "E-TYPE-9999",
                  "neper-0 constant expressions allow integer literals, constants, and arithmetic only");
    return 0;
}

static int instantiate_struct_type(Compiler *c, Type *type, Token *token) {
    StructDecl *template_decl = find_struct(c, type->name);
    Function environment;
    Type type_args[MAX_ARGS];
    int64_t integer_args[MAX_ARGS] = {0};
    char instance_name[96];
    size_t used;
    StructDecl *instance;
    int i;
    if (!template_decl || !template_decl->is_template) return 1;
    if (type->generic_arg_count != template_decl->comptime_param_count) {
        diagnostic_at(c, token, "E-TYPE-0003",
                      "compile-time argument count does not match generic type");
        return 0;
    }
    memset(&environment, 0, sizeof(environment));
    memset(type_args, 0, sizeof(type_args));
    environment.comptime_param_count = template_decl->comptime_param_count;
    copy_text(instance_name, sizeof(instance_name), template_decl->name,
              strlen(template_decl->name));
    used = strlen(instance_name);
    for (i = 0; i < template_decl->comptime_param_count; ++i) {
        ComptimeParam *parameter = &template_decl->comptime_params[i];
        char part[112];
        environment.comptime_params[i] = *parameter;
        if (parameter->is_type) {
            if (!type->generic_is_type[i] || !type->generic_types[i]) {
                diagnostic_at(c, token, "E-TYPE-0003", "generic type argument must be a type");
                return 0;
            }
            type_args[i] = *type->generic_types[i];
            resolve_type_constants(c, &type_args[i], token);
            snprintf(part, sizeof(part), "$%s", type_args[i].name);
        } else {
            Type actual;
            if (type->generic_is_type[i] || !type->generic_values[i] ||
                !evaluate_integer_expression(c, type->generic_values[i],
                                             &integer_args[i], &actual)) return 0;
            if (actual.kind != TY_UNTYPED_INT && !type_equal(actual, parameter->value_type)) {
                diagnostic_at(c, token, "E-TYPE-0002",
                              "generic integer argument has the wrong type");
                return 0;
            }
            snprintf(part, sizeof(part), "$%lld", (long long)integer_args[i]);
        }
        copy_text(instance_name + used, sizeof(instance_name) - used, part, strlen(part));
        used = strlen(instance_name);
    }
    instance = find_struct(c, instance_name);
    if (!instance) {
        if (c->program.struct_count >= MAX_DECLS) {
            diagnostic_at(c, token, "E-TOOL-9999", "generic type instance limit exceeded");
            return 0;
        }
        instance = &c->program.structs[c->program.struct_count++];
        memset(instance, 0, sizeof(*instance));
        copy_text(instance->name, sizeof(instance->name), instance_name, strlen(instance_name));
        instance->token = template_decl->token;
        instance->kind = template_decl->kind;
        instance->backing_type = specialize_type(c, &environment, type_args, integer_args,
                                                 template_decl->backing_type);
        instance->field_count = template_decl->field_count;
        for (i = 0; i < instance->field_count; ++i) {
            instance->fields[i] = template_decl->fields[i];
            instance->fields[i].type = specialize_type(c, &environment, type_args,
                                                       integer_args, template_decl->fields[i].type);
            resolve_type_constants(c, &instance->fields[i].type, &instance->fields[i].token);
        }
    }
    copy_text(type->name, sizeof(type->name), instance_name, strlen(instance_name));
    type->generic_arg_count = 0;
    return 1;
}

static void resolve_type_constants(Compiler *c, Type *type, Token *token) {
    if (type->kind == TY_NAMED && type->generic_arg_count)
        instantiate_struct_type(c, type, token);
    if (type->kind == TY_ARRAY) {
        if (type->array_length_expr) {
            int64_t value;
            Type actual;
            if (evaluate_integer_expression(c, type->array_length_expr, &value, &actual)) {
                if (actual.kind != TY_UNTYPED_INT &&
                    !(actual.kind == TY_INT && strcmp(actual.name, "usize") == 0))
                    diagnostic_at(c, &type->array_length_expr->token, "E-TYPE-0002",
                                  "array length must have type usize");
                if (value < 0)
                    diagnostic_at(c, &type->array_length_expr->token, "E-TYPE-0004",
                                  "array length is not representable as usize");
                else type->array_length = (size_t)value;
            }
        }
        if (type->element) resolve_type_constants(c, type->element, token);
    } else if ((type->kind == TY_POINTER || type->kind == TY_SLICE) && type->element) {
        resolve_type_constants(c, type->element, token);
    }
}

static int return_type_uses_integer_register(Compiler *c, Type type) {
    if (type.kind == TY_BOOL || type.kind == TY_ERR || type.kind == TY_INT ||
        type.kind == TY_POINTER || type.kind == TY_ARENA) return 1;
    if (type.kind == TY_NAMED) {
        StructDecl *decl = enum_decl_for_type(c, type);
        return decl && (decl->kind == ND_ENUM || find_tag_owner(c, type.name));
    }
    return 0;
}

static void prepare_return_convention(Compiler *c, Function *fn) {
    size_t offset = 0, maximum_alignment = 1;
    int i;
    fn->returns_via_slot = 0;
    if (fn->is_intrinsic && fn->return_count > 1) fn->returns_via_slot = 1;
    if (fn->return_count > 2) fn->returns_via_slot = 1;
    for (i = 0; i < fn->return_count; ++i) {
        size_t size = 0, alignment = 1;
        check_known_type(c, fn->return_types[i], &fn->token);
        if (!return_type_uses_integer_register(c, fn->return_types[i]))
            fn->returns_via_slot = 1;
        if (!type_layout(c, fn->return_types[i], &size, &alignment)) continue;
        offset = align_up_size(offset, alignment);
        fn->return_offsets[i] = offset;
        offset += size;
        if (alignment > maximum_alignment) maximum_alignment = alignment;
    }
    fn->return_storage_size = align_up_size(offset, maximum_alignment);
    if (fn->returns_via_slot && fn->return_count) {
        Local *slot;
        Type pointer;
        if (fn->local_count >= MAX_LOCALS) {
            diagnostic_at(c, &fn->token, "E-TOOL-9999", "local limit exceeded by return storage");
            return;
        }
        slot = &fn->locals[fn->local_count];
        pointer = type_make(TY_POINTER, fn->return_types[0].name);
        type_set_element(&pointer, fn->return_types[0]);
        memset(slot, 0, sizeof(*slot));
        strcpy(slot->name, "$return_slot");
        slot->type = pointer; slot->active = 1;
        fn->return_slot_local_index = fn->local_count++;
    } else {
        for (i = 0; i < fn->return_count; ++i) {
            Local *slot;
            if (fn->local_count >= MAX_LOCALS) {
                diagnostic_at(c, &fn->token, "E-TOOL-9999", "local limit exceeded by return values");
                break;
            }
            slot = &fn->locals[fn->local_count];
            memset(slot, 0, sizeof(*slot));
            snprintf(slot->name, sizeof(slot->name), "$return_value_%d", i);
            slot->type = fn->return_types[i]; slot->active = 1;
            fn->return_value_locals[i] = fn->local_count++;
        }
        if (fn->return_count) fn->scalar_return_local_index = fn->return_value_locals[0];
    }
}

static void check_program(Compiler *c) {
    int i, j;
    Function *main_fn = 0;
    for (i = 0; i < c->program.error_count; ++i)
        for (j = 0; j < i; ++j)
            if (strcmp(c->program.errors[i].module, c->program.errors[j].module) == 0 &&
                strcmp(c->program.errors[i].name, c->program.errors[j].name) == 0)
                diagnostic_at(c, &c->program.errors[i].token, "E-NAME-0001", "duplicate error declaration");
    for (i = 0; i < c->program.constant_count; ++i) {
        ConstDecl *constant = &c->program.constants[i];
        copy_text(c->resolution_module, sizeof(c->resolution_module), constant->module,
                  strlen(constant->module));
        for (j = 0; j < i; ++j)
            if (strcmp(constant->name, c->program.constants[j].name) == 0)
                diagnostic_at(c, &constant->token, "E-NAME-0001", "duplicate constant declaration");
        qualify_type_for_module(c, &constant->type, constant->module);
        resolve_type_constants(c, &constant->type, &constant->token);
        evaluate_constant(c, constant);
    }
    /* Canonicalize all aggregate field types before computing any layout. An
       earlier-loaded module may embed a type from a dependency parsed later. */
    for (i = 0; i < c->program.struct_count; ++i) {
        StructDecl *decl = &c->program.structs[i];
        if (decl->is_template) continue;
        copy_text(c->resolution_module, sizeof(c->resolution_module), decl->module,
                  strlen(decl->module));
        if (decl->kind == ND_ENUM || decl->kind == ND_TAGGED_UNION) {
            qualify_type_for_module(c, &decl->backing_type, decl->module);
            resolve_type_constants(c, &decl->backing_type, &decl->token);
        }
        for (j = 0; j < decl->field_count; ++j)
            if (decl->fields[j].has_payload || decl->kind == ND_STRUCT || decl->kind == ND_UNION) {
                qualify_type_for_module(c, &decl->fields[j].type, decl->module);
                resolve_type_constants(c, &decl->fields[j].type, &decl->fields[j].token);
            }
    }
    for (i = 0; i < c->program.struct_count; ++i) {
        StructDecl *decl = &c->program.structs[i];
        copy_text(c->resolution_module, sizeof(c->resolution_module), decl->module,
                  strlen(decl->module));
        for (j = 0; j < i; ++j)
            if (strcmp(decl->name, c->program.structs[j].name) == 0)
                diagnostic_at(c, &decl->token, "E-NAME-0001", "duplicate type declaration");
        if (decl->is_template) continue;
        if (decl->kind == ND_ENUM || decl->kind == ND_TAGGED_UNION) {
            qualify_type_for_module(c, &decl->backing_type, decl->module);
            resolve_type_constants(c, &decl->backing_type, &decl->token);
            check_known_type(c, decl->backing_type, &decl->token);
        }
        for (j = 0; j < decl->field_count; ++j)
            if (decl->fields[j].has_payload || decl->kind == ND_STRUCT || decl->kind == ND_UNION) {
                qualify_type_for_module(c, &decl->fields[j].type, decl->module);
                resolve_type_constants(c, &decl->fields[j].type, &decl->fields[j].token);
                check_known_type(c, decl->fields[j].type, &decl->fields[j].token);
            }
        layout_struct(c, decl);
        if (decl->kind == ND_TAGGED_UNION) {
            char tag_name[128];
            snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
            for (j = 0; j < c->program.struct_count; ++j)
                if (strcmp(c->program.structs[j].name, tag_name) == 0)
                    diagnostic_at(c, &c->program.structs[j].token, "E-NAME-0001", "type name collides with an implicit tagged-union tag type");
            for (j = 0; j < decl->field_count; ++j)
                if (strcmp(decl->fields[j].name, "Tag") == 0)
                    diagnostic_at(c, &decl->fields[j].token, "E-NAME-0001", "tagged union may not declare a member named Tag");
        }
    }
    /* Canonicalize every callable signature before checking any body. A root
       module may call an imported function that was parsed later. */
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (fn->is_template) continue;
        copy_text(c->resolution_module, sizeof(c->resolution_module), fn->module,
                  strlen(fn->module));
        for (j = 0; j < fn->return_count; ++j) {
            qualify_type_for_module(c, &fn->return_types[j], fn->module);
            resolve_type_constants(c, &fn->return_types[j], &fn->token);
        }
        if (fn->return_count) fn->return_type = fn->return_types[0];
        for (j = 0; j < fn->param_count; ++j) {
            qualify_type_for_module(c, &fn->params[j].type, fn->module);
            resolve_type_constants(c, &fn->params[j].type, &fn->params[j].token);
        }
    }
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        copy_text(c->resolution_module, sizeof(c->resolution_module), fn->module,
                  strlen(fn->module));
        for (j = 0; j < i; ++j) if (strcmp(fn->name, c->program.functions[j].name) == 0)
            diagnostic_at(c, &fn->token, "E-NAME-0001", "duplicate function declaration");
        if (fn->is_template) continue;
        for (j = 0; j < fn->return_count; ++j) {
            qualify_type_for_module(c, &fn->return_types[j], fn->module);
            resolve_type_constants(c, &fn->return_types[j], &fn->token);
        }
        if (fn->return_count) fn->return_type = fn->return_types[0];
        prepare_return_convention(c, fn);
        if (fn->is_intrinsic) continue;
        for (j = 0; j < fn->param_count; ++j) {
            Local *local = &fn->locals[fn->local_count];
            qualify_type_for_module(c, &fn->params[j].type, fn->module);
            resolve_type_constants(c, &fn->params[j].type, &fn->params[j].token);
            check_known_type(c, fn->params[j].type, &fn->params[j].token);
            memset(local, 0, sizeof(*local)); strcpy(local->name, fn->params[j].name);
            local->type = fn->params[j].type; local->token = fn->params[j].token;
            local->is_mutable = 0; local->active = 1;
            if (type_is_value_aggregate(c, local->type) && type_size(c, local->type) > 16)
                local->is_indirect = 1;
            fn->params[j].local_index = fn->local_count++;
        }
        check_statements(c, fn, fn->body);
        if (strcmp(fn->name, "main") == 0) main_fn = fn;
    }
    if (!main_fn) {
        diagnostic_at(c, &c->root_token, "E-NAME-9999", "program root must declare fn main");
    } else if (main_fn->param_count != 2 || main_fn->params[0].type.kind != TY_POINTER ||
               strcmp(main_fn->params[0].type.name, "mem.Arena") != 0 ||
               main_fn->params[1].type.kind != TY_SLICE || strcmp(main_fn->params[1].type.name, "str") != 0 ||
               main_fn->return_count != 1 || main_fn->return_type.kind != TY_ERR) {
        diagnostic_at(c, &main_fn->token, "E-TYPE-9999",
                      "program entry must be fn main(a: *mem.Arena, args: []str) -> err");
    }
    check_imports(c);
}

static void collect_traps_expr(Compiler *c, Function *fn, Expr *expr) {
    int i;
    const char *kind = 0, *detail = 0;
    if (!expr) return;
    if (expr->kind == EX_INDEX) { kind = "bounds"; detail = "index out of bounds"; }
    else if (expr->kind == EX_SLICE) { kind = "bounds"; detail = "slice bounds out of range"; }
    else if (expr->kind == EX_FIELD && expr->as.field.tag_check) {
        kind = "tag"; detail = "tagged-union payload does not match the active member";
    } else if (expr->kind == EX_NAME) {
        for (i = 0; i < expr->field_path_count; ++i)
            if (expr->field_tag_checks[i]) {
                kind = "tag"; detail = "tagged-union payload does not match the active member"; break;
            }
    }
    else if (expr->kind == EX_BINARY && (expr->as.binary.op == TK_SLASH || expr->as.binary.op == TK_PERCENT)) {
        kind = "divide"; detail = "invalid integer division";
    }
    if (kind && c->program.trap_site_count < MAX_TRAP_SITES) {
        struct TrapSite *site = &c->program.trap_sites[c->program.trap_site_count];
        memset(site, 0, sizeof(*site));
        site->token = expr->token;
        copy_text(site->kind, sizeof(site->kind), kind, strlen(kind));
        copy_text(site->function, sizeof(site->function), fn->name, strlen(fn->name));
        snprintf(site->message, sizeof(site->message),
                 "%s:%d:%d: trap[%s]: %s\n  at %s (%s:%d:%d)\n",
                 c->source_path, expr->token.line, expr->token.column, kind, detail,
                 fn->name, c->source_path, expr->token.line, expr->token.column);
        site->message_length = strlen(site->message);
        expr->trap_id = c->program.trap_site_count++;
    }
    switch (expr->kind) {
        case EX_CALL:
            for (i = 0; i < expr->as.call.arg_count; ++i) collect_traps_expr(c, fn, expr->as.call.args[i]);
            break;
        case EX_ARRAY_LITERAL:
            for (i = 0; i < expr->as.array.item_count; ++i)
                collect_traps_expr(c, fn, expr->as.array.items[i]);
            break;
        case EX_STRUCT_LITERAL:
            for (i = 0; i < expr->as.aggregate.item_count; ++i)
                collect_traps_expr(c, fn, expr->as.aggregate.items[i].value);
            break;
        case EX_INDEX:
            collect_traps_expr(c, fn, expr->as.index.base);
            collect_traps_expr(c, fn, expr->as.index.index);
            break;
        case EX_FIELD:
            collect_traps_expr(c, fn, expr->as.field.base);
            break;
        case EX_SLICE:
            collect_traps_expr(c, fn, expr->as.slice.base);
            collect_traps_expr(c, fn, expr->as.slice.start);
            collect_traps_expr(c, fn, expr->as.slice.end);
            break;
        case EX_BINARY:
            collect_traps_expr(c, fn, expr->as.binary.left);
            collect_traps_expr(c, fn, expr->as.binary.right);
            break;
        case EX_UNARY: collect_traps_expr(c, fn, expr->as.unary.value); break;
        default: break;
    }
}

static void collect_traps_statements(Compiler *c, Function *fn, Stmt *statement) {
    for (; statement; statement = statement->next) {
        switch (statement->kind) {
            case ST_BIND: collect_traps_expr(c, fn, statement->as.bind.value); break;
            case ST_MULTI_BIND: case ST_MULTI_ASSIGN:
                collect_traps_expr(c, fn, statement->as.multi.call); break;
            case ST_ASSIGN: collect_traps_expr(c, fn, statement->as.assign.value); break;
            case ST_INDEX_ASSIGN:
                collect_traps_expr(c, fn, statement->as.index_assign.target);
                collect_traps_expr(c, fn, statement->as.index_assign.value);
                break;
            case ST_EXPR: case ST_TRY: collect_traps_expr(c, fn, statement->as.expr); break;
            case ST_RETURN: {
                int value_index;
                for (value_index = 0; value_index < statement->as.ret.value_count; ++value_index)
                    collect_traps_expr(c, fn, statement->as.ret.values[value_index]);
                break;
            }
            case ST_IF:
                collect_traps_expr(c, fn, statement->as.if_stmt.condition);
                collect_traps_statements(c, fn, statement->as.if_stmt.then_body);
                collect_traps_statements(c, fn, statement->as.if_stmt.else_body);
                break;
            case ST_WHILE:
                collect_traps_expr(c, fn, statement->as.while_stmt.condition);
                collect_traps_statements(c, fn, statement->as.while_stmt.body);
                break;
            case ST_FOR_RANGE:
                collect_traps_expr(c, fn, statement->as.for_range.start);
                collect_traps_expr(c, fn, statement->as.for_range.end);
                collect_traps_statements(c, fn, statement->as.for_range.body);
                break;
            case ST_FOR_EACH:
                collect_traps_expr(c, fn, statement->as.for_each.subject);
                collect_traps_statements(c, fn, statement->as.for_each.body);
                break;
            case ST_SWITCH: {
                SwitchCase *arm;
                collect_traps_expr(c, fn, statement->as.switch_stmt.subject);
                for (arm = statement->as.switch_stmt.cases; arm; arm = arm->next) {
                    int value_index;
                    for (value_index = 0; value_index < arm->value_count; ++value_index)
                        collect_traps_expr(c, fn, arm->values[value_index]);
                    collect_traps_statements(c, fn, arm->body);
                }
                break;
            }
            case ST_DEFER: {
                int capture_index;
                for (capture_index = 0; capture_index < statement->as.defer_stmt.capture_count; ++capture_index)
                    collect_traps_expr(c, fn, statement->as.defer_stmt.capture_values[capture_index]);
                if (statement->as.defer_stmt.is_captured_call)
                    collect_traps_expr(c, fn, statement->as.defer_stmt.call);
                else collect_traps_statements(c, fn, statement->as.defer_stmt.body);
                break;
            }
            case ST_BREAK: case ST_CONTINUE: break;
        }
    }
}

static void collect_traps(Compiler *c) {
    int i;
    for (i = 0; i < c->program.function_count; ++i)
        if (!c->program.functions[i].is_template && !c->program.functions[i].is_intrinsic)
            collect_traps_statements(c, &c->program.functions[i], c->program.functions[i].body);
}

typedef struct Emitter {
    Compiler *compiler;
    FILE *out;
    int windows;
    int label;
    Function *fn;
    int temp_offset;
    int call_base;
    int return_label;
    int debug_label;
    int loop_break[MAX_LOOP_DEPTH];
    int loop_continue[MAX_LOOP_DEPTH];
    int loop_break_scope[MAX_LOOP_DEPTH];
    int loop_continue_scope[MAX_LOOP_DEPTH];
    int loop_depth;
    struct {
        Stmt *items[MAX_LOCALS];
        int count;
    } defer_scopes[MAX_LOOP_DEPTH];
    int defer_scope_depth;
} Emitter;

static const char *symbol_name(Function *fn) { return fn->symbol; }

static int align16(int value) { return (value + 15) & ~15; }

static Type storage_scalar_type(Compiler *c, Type type) {
    StructDecl *decl = enum_decl_for_type(c, type);
    if (decl && (decl->kind == ND_ENUM || find_tag_owner(c, type.name))) return decl->backing_type;
    return type;
}

static int type_is_unsigned(Compiler *c, Type type) {
    type = storage_scalar_type(c, type);
    return type.kind == TY_INT &&
           (type.name[0] == 'u' || strcmp(type.name, "usize") == 0);
}

static int type_is_signed_integer(Compiler *c, Type type) {
    type = storage_scalar_type(c, type);
    return type.kind == TY_INT && type.name[0] == 'i';
}

static void emit_stack_store(Emitter *e, int displacement, Type type) {
    size_t size = type_size(e->compiler, type);
    if (size == 1) fprintf(e->out, "    mov BYTE PTR [rbp-%d], al\n", displacement);
    else if (size == 2) fprintf(e->out, "    mov WORD PTR [rbp-%d], ax\n", displacement);
    else if (size == 4) fprintf(e->out, "    mov DWORD PTR [rbp-%d], eax\n", displacement);
    else {
        fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", displacement);
        if (size == 16) fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", displacement - 8);
    }
}

static void emit_address_load(Emitter *e, Type type) {
    size_t size = type_size(e->compiler, type);
    if (size == 16) fputs("    mov rax, QWORD PTR [r10]\n    mov rdx, QWORD PTR [r10+8]\n", e->out);
    else if (size == 8) fputs("    mov rax, QWORD PTR [r10]\n", e->out);
    else if (size == 4) fputs(type_is_signed_integer(e->compiler, type) ?
        "    movsxd rax, DWORD PTR [r10]\n" : "    mov eax, DWORD PTR [r10]\n", e->out);
    else if (size == 2) fputs(type_is_signed_integer(e->compiler, type) ?
        "    movsx rax, WORD PTR [r10]\n" : "    movzx rax, WORD PTR [r10]\n", e->out);
    else fputs(type_is_signed_integer(e->compiler, type) ?
        "    movsx rax, BYTE PTR [r10]\n" : "    movzx rax, BYTE PTR [r10]\n", e->out);
}

static void emit_address_store(Emitter *e, Type type, TokenKind op) {
    size_t size = type_size(e->compiler, type);
    if (op == TK_ADD_ASSIGN) {
        if (size == 1) fputs("    add BYTE PTR [r10], al\n", e->out);
        else if (size == 2) fputs("    add WORD PTR [r10], ax\n", e->out);
        else if (size == 4) fputs("    add DWORD PTR [r10], eax\n", e->out);
        else fputs("    add QWORD PTR [r10], rax\n", e->out);
    } else if (size == 1) fputs("    mov BYTE PTR [r10], al\n", e->out);
    else if (size == 2) fputs("    mov WORD PTR [r10], ax\n", e->out);
    else if (size == 4) fputs("    mov DWORD PTR [r10], eax\n", e->out);
    else {
        fputs("    mov QWORD PTR [r10], rax\n", e->out);
        if (size == 16) fputs("    mov QWORD PTR [r10+8], rdx\n", e->out);
    }
}

static void assign_offsets(Compiler *c, Function *fn) {
    int i, offset = 0;
    for (i = 0; i < fn->local_count; ++i) {
        size_t bytes = type_size(c, fn->locals[i].type);
        size_t storage = (bytes + 7) & ~(size_t)7;
        if (storage == 0) storage = 8;
        offset += (int)storage;
        fn->locals[i].offset = offset;
    }
    fn->frame_size = align16(offset + 32 * 8 + 64);
}

static int alloc_temp(Emitter *e, int lanes) {
    int offset = e->temp_offset;
    e->temp_offset += lanes * 8;
    return offset;
}

static int alloc_aggregate_temp(Emitter *e, size_t bytes) {
    int lanes = (int)((bytes + 7) / 8);
    if (lanes == 0) lanes = 1;
    int first = alloc_temp(e, lanes);
    return first + (lanes - 1) * 8;
}

static void emit_expr(Emitter *e, Expr *x);

static void emit_trap_call(Emitter *e, Expr *x) {
    struct TrapSite *site = &e->compiler->program.trap_sites[x->trap_id];
    if (e->windows) {
        fprintf(e->out, "    lea rcx, np_trap_site_%d\n    mov edx, %u\n",
                x->trap_id, (unsigned)site->message_length);
    } else {
        fprintf(e->out, "    mov edi, 2\n    lea rsi, np_trap_site_%d[rip]\n    mov edx, %u\n",
                x->trap_id, (unsigned)site->message_length);
    }
    fputs("    call neper_trap_abort\n", e->out);
}

static Type index_element_type(Type base) {
    return sequence_element_type(base);
}

static int emit_index_address(Emitter *e, Expr *index) {
    Type element = index_element_type(index->as.index.base->type);
    size_t size = type_size(e->compiler, element);
    int base_slot = alloc_temp(e, 2);
    int address_slot = alloc_temp(e, 1);
    int ok_label = e->label++;
    emit_expr(e, index->as.index.base);
    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", base_slot);
    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", base_slot + 8);
    emit_expr(e, index->as.index.index);
    fprintf(e->out, "    cmp rax, QWORD PTR [rbp-%d]\n", base_slot + 8);
    fprintf(e->out, "    jb np_index_ok_%d\n", ok_label);
    emit_trap_call(e, index);
    fprintf(e->out, "np_index_ok_%d:\n", ok_label);
    fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", base_slot);
    if (size == 16) fputs("    shl rax, 4\n    add r10, rax\n", e->out);
    else if (size == 8) fputs("    lea r10, [r10+rax*8]\n", e->out);
    else if (size == 4) fputs("    lea r10, [r10+rax*4]\n", e->out);
    else if (size == 2) fputs("    lea r10, [r10+rax*2]\n", e->out);
    else if (size == 1) fputs("    add r10, rax\n", e->out);
    else fprintf(e->out, "    imul rax, %llu\n    add r10, rax\n", (unsigned long long)size);
    fprintf(e->out, "    mov QWORD PTR [rbp-%d], r10\n", address_slot);
    return address_slot;
}

static void emit_tag_check(Emitter *e, Expr *expr, int size, int64_t expected) {
    int ok = e->label++;
    if (size == 1) fputs("    movzx eax, BYTE PTR [r10]\n", e->out);
    else if (size == 2) fputs("    movzx eax, WORD PTR [r10]\n", e->out);
    else if (size == 4) fputs("    mov eax, DWORD PTR [r10]\n", e->out);
    else fputs("    mov rax, QWORD PTR [r10]\n", e->out);
    fprintf(e->out, "    cmp rax, %lld\n    je np_tag_ok_%d\n", (long long)expected, ok);
    emit_trap_call(e, expr);
    fprintf(e->out, "np_tag_ok_%d:\n", ok);
}

static void emit_name_address(Emitter *e, Expr *name) {
    Local *local = &e->fn->locals[name->local_index];
    int i;
    fprintf(e->out, "    lea r10, [rbp-%d]\n", local->offset);
    for (i = 0; i < name->field_path_count; ++i) {
        if (name->field_dereferences[i])
            fputs("    mov r10, QWORD PTR [r10]\n", e->out);
        if (name->field_tag_checks[i])
            emit_tag_check(e, name, name->field_tag_sizes[i], name->field_tag_values[i]);
        if (name->field_offsets[i])
            fprintf(e->out, "    add r10, %d\n", name->field_offsets[i]);
    }
}

static void emit_value_to_stack(Emitter *e, Expr *value, Type type, int displacement);
static int expr_is_place(Expr *value);

static void emit_place_address(Emitter *e, Expr *place) {
    if (place->kind == EX_NAME) emit_name_address(e, place);
    else if (place->kind == EX_INDEX) {
        int address_slot = emit_index_address(e, place);
        fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
    } else if (place->kind == EX_FIELD) {
        if (place->as.field.base->type.kind == TY_POINTER) {
            emit_expr(e, place->as.field.base);
            fputs("    mov r10, rax\n", e->out);
        } else if (expr_is_place(place->as.field.base)) {
            emit_place_address(e, place->as.field.base);
        } else {
            size_t bytes = type_size(e->compiler, place->as.field.base->type);
            int slot = alloc_aggregate_temp(e, bytes);
            emit_value_to_stack(e, place->as.field.base, place->as.field.base->type, slot);
            fprintf(e->out, "    lea r10, [rbp-%d]\n", slot);
        }
        if (place->as.field.tag_check)
            emit_tag_check(e, place, place->as.field.tag_size, place->as.field.tag_value);
        if (place->as.field.offset)
            fprintf(e->out, "    add r10, %d\n", place->as.field.offset);
    } else if (place->kind == EX_UNARY && place->as.unary.op == TK_STAR) {
        emit_expr(e, place->as.unary.value);
        fputs("    mov r10, rax\n", e->out);
    }
}

static void emit_argument_lane(Emitter *e, int lane, const char *source) {
    static const char *win_regs[] = {"rcx", "rdx", "r8", "r9"};
    static const char *sysv_regs[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
    const char *reg = e->windows ? (lane < 4 ? win_regs[lane] : 0) :
                                  (lane < 6 ? sysv_regs[lane] : 0);
    if (reg) fprintf(e->out, "    mov %s, %s\n", reg, source);
    else {
        fprintf(e->out, "    mov rax, %s\n", source);
        if (e->windows) fprintf(e->out, "    mov QWORD PTR [rsp+%d], rax\n", 32 + (lane - 4) * 8);
        else fprintf(e->out, "    mov QWORD PTR [rsp+%d], rax\n", (lane - 6) * 8);
    }
}

static void emit_call(Emitter *e, Expr *x, int aggregate_destination) {
    int slots[MAX_ARGS], lanes[MAX_ARGS], indirect[MAX_ARGS], aggregate[MAX_ARGS], i;
    Function *callee = strcmp(x->as.call.callee, "io.print") == 0 ? 0 :
                       find_function(e->compiler, x->as.call.callee);
    int returns_aggregate = callee && callee->returns_via_slot;
    int result_slot = aggregate_destination;
    int lane = returns_aggregate ? 1 : 0;
    if (returns_aggregate && !result_slot) {
        size_t bytes = type_size(e->compiler, x->type);
        result_slot = alloc_aggregate_temp(e, bytes);
    }
    for (i = 0; i < x->as.call.arg_count; ++i) {
        Type type = x->as.call.args[i]->type;
        indirect[i] = 0;
        aggregate[i] = type_is_value_aggregate(e->compiler, type);
        if (aggregate[i]) {
            size_t bytes = type_size(e->compiler, type);
            int storage_lanes = (int)((bytes + 7) / 8);
            if (storage_lanes == 0) storage_lanes = 1;
            if (bytes > 16 && expr_is_place(x->as.call.args[i])) {
                slots[i] = alloc_temp(e, 1);
                emit_place_address(e, x->as.call.args[i]);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], r10\n", slots[i]);
                indirect[i] = 2;
            } else {
                slots[i] = alloc_aggregate_temp(e, bytes);
                emit_value_to_stack(e, x->as.call.args[i], type, slots[i]);
                indirect[i] = bytes > 16;
            }
            lanes[i] = indirect[i] ? 1 : storage_lanes;
        } else {
            lanes[i] = type_lanes(type);
            slots[i] = alloc_temp(e, lanes[i]);
            emit_expr(e, x->as.call.args[i]);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", slots[i]);
            if (lanes[i] == 2)
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", slots[i] + 8);
        }
    }
    if (returns_aggregate) {
        char source[64];
        fprintf(e->out, "    lea rax, [rbp-%d]\n", result_slot);
        strcpy(source, "rax");
        emit_argument_lane(e, 0, source);
    }
    for (i = 0; i < x->as.call.arg_count; ++i) {
        int k;
        for (k = 0; k < lanes[i]; ++k, ++lane) {
            char source[96];
            if (indirect[i] == 1) {
                fprintf(e->out, "    lea rax, [rbp-%d]\n", slots[i]);
                strcpy(source, "rax");
            } else if (indirect[i] == 2) {
                snprintf(source, sizeof(source), "QWORD PTR [rbp-%d]", slots[i]);
            } else snprintf(source, sizeof(source), "QWORD PTR [rbp-%d]",
                            aggregate[i] ? slots[i] - k * 8 : slots[i] + k * 8);
            emit_argument_lane(e, lane, source);
        }
    }
    if (strcmp(x->as.call.callee, "io.print") == 0) fprintf(e->out, "    call neper_io_print\n");
    else {
        fprintf(e->out, "    call %s\n", callee ? symbol_name(callee) : x->as.call.callee);
    }
    if (returns_aggregate) {
        if (type_is_value_aggregate(e->compiler, x->type))
            fprintf(e->out, "    lea rax, [rbp-%d]\n", result_slot);
        else {
            fprintf(e->out, "    lea r10, [rbp-%d]\n", result_slot);
            emit_address_load(e, x->type);
        }
    }
}

static void emit_expr(Emitter *e, Expr *x) {
    switch (x->kind) {
        case EX_INTEGER:
            fprintf(e->out, "    mov rax, %lld\n", (long long)x->as.integer); break;
        case EX_ENUM_MEMBER:
            fprintf(e->out, "    mov rax, %lld\n", (long long)x->constant_value); break;
        case EX_STRING:
            if (e->windows) fprintf(e->out, "    lea rax, np_str_%d\n", x->as.string.label);
            else fprintf(e->out, "    lea rax, np_str_%d[rip]\n", x->as.string.label);
            fprintf(e->out, "    mov rdx, %llu\n", (unsigned long long)x->as.string.length); break;
        case EX_NAME: {
            if (strcmp(x->as.name, "ok") == 0) { fputs("    xor eax, eax\n", e->out); break; }
            if (x->error_code) { fprintf(e->out, "    mov eax, %d\n", x->error_code); break; }
            if (x->is_constant) {
                fprintf(e->out, "    mov rax, %lld\n", (long long)x->constant_value);
                break;
            }
            {
                int index = x->local_index;
                Local *local = &e->fn->locals[index];
                if (x->is_len) {
                    if (x->place_type.kind == TY_ARRAY)
                        fprintf(e->out, "    mov rax, %llu\n",
                                (unsigned long long)x->place_type.array_length);
                    else {
                        emit_name_address(e, x);
                        fputs("    mov rax, QWORD PTR [r10+8]\n", e->out);
                    }
                } else if (x->type.kind == TY_ARRAY) {
                    emit_name_address(e, x);
                    fputs("    mov rax, r10\n", e->out);
                    fprintf(e->out, "    mov rdx, %llu\n",
                            (unsigned long long)x->type.array_length);
                } else if (x->field_path_count || local->type.kind == TY_NAMED) {
                    emit_name_address(e, x);
                    emit_address_load(e, x->type);
                } else {
                    if (type_lanes(local->type) == 2) {
                        fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", local->offset);
                        fprintf(e->out, "    mov rdx, QWORD PTR [rbp-%d]\n", local->offset - 8);
                    } else {
                        emit_name_address(e, x);
                        emit_address_load(e, local->type);
                    }
                }
            }
            break;
        }
        case EX_CALL: emit_call(e, x, 0); break;
        case EX_INDEX: {
            Type element = index_element_type(x->as.index.base->type);
            int address_slot = emit_index_address(e, x);
            fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
            if (element.kind == TY_ARRAY) {
                fputs("    mov rax, r10\n", e->out);
                fprintf(e->out, "    mov rdx, %llu\n", (unsigned long long)element.array_length);
            } else emit_address_load(e, element);
            break;
        }
        case EX_FIELD:
            if (x->is_len && x->place_type.kind == TY_ARRAY)
                fprintf(e->out, "    mov rax, %llu\n", (unsigned long long)x->place_type.array_length);
            else if (x->is_len) {
                emit_place_address(e, x->as.field.base);
                fputs("    mov rax, QWORD PTR [r10+8]\n", e->out);
            } else {
                emit_place_address(e, x);
                emit_address_load(e, x->type);
            }
            break;
        case EX_SLICE: {
            Type element = sequence_element_type(x->as.slice.base->type);
            size_t size = type_size(e->compiler, element);
            int base_slot = alloc_temp(e, 2);
            int lower_slot = alloc_temp(e, 1);
            int upper_slot = alloc_temp(e, 1);
            int trap_label = e->label++, ok_label = e->label++;
            emit_expr(e, x->as.slice.base);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", base_slot);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", base_slot + 8);
            if (x->as.slice.start) emit_expr(e, x->as.slice.start);
            else fputs("    xor eax, eax\n", e->out);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", lower_slot);
            if (x->as.slice.end) emit_expr(e, x->as.slice.end);
            else fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", base_slot + 8);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", upper_slot);
            fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", lower_slot);
            fprintf(e->out, "    cmp r10, QWORD PTR [rbp-%d]\n", base_slot + 8);
            fprintf(e->out, "    ja np_slice_trap_%d\n", trap_label);
            fprintf(e->out, "    mov r11, QWORD PTR [rbp-%d]\n", upper_slot);
            fprintf(e->out, "    cmp r11, QWORD PTR [rbp-%d]\n", base_slot + 8);
            fprintf(e->out, "    ja np_slice_trap_%d\n    cmp r10, r11\n", trap_label);
            fprintf(e->out, "    ja np_slice_trap_%d\n    jmp np_slice_ok_%d\n", trap_label, ok_label);
            fprintf(e->out, "np_slice_trap_%d:\n", trap_label);
            emit_trap_call(e, x);
            fprintf(e->out, "np_slice_ok_%d:\n", ok_label);
            fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", lower_slot);
            fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", base_slot);
            if (size == 16) fputs("    shl rax, 4\n    add r10, rax\n", e->out);
            else if (size == 8) fputs("    lea r10, [r10+rax*8]\n", e->out);
            else if (size == 4) fputs("    lea r10, [r10+rax*4]\n", e->out);
            else if (size == 2) fputs("    lea r10, [r10+rax*2]\n", e->out);
            else if (size == 1) fputs("    add r10, rax\n", e->out);
            else fprintf(e->out, "    imul rax, %llu\n    add r10, rax\n", (unsigned long long)size);
            fputs("    mov rax, r10\n", e->out);
            fprintf(e->out, "    mov rdx, QWORD PTR [rbp-%d]\n", upper_slot);
            fprintf(e->out, "    sub rdx, QWORD PTR [rbp-%d]\n", lower_slot);
            break;
        }
        case EX_ARRAY_LITERAL: case EX_STRUCT_LITERAL: case EX_ZERO: case EX_UNDEF:
            fputs("    xor eax, eax\n", e->out);
            break;
        case EX_UNARY:
            if (x->as.unary.op == TK_AMP) {
                Expr *place = x->as.unary.value;
                emit_place_address(e, place);
                fputs("    mov rax, r10\n", e->out);
            } else if (x->as.unary.op == TK_STAR) {
                emit_expr(e, x->as.unary.value);
                fputs("    mov r10, rax\n", e->out);
                emit_address_load(e, x->type);
            } else {
                emit_expr(e, x->as.unary.value);
                if (x->as.unary.op == TK_MINUS) fputs("    neg rax\n", e->out);
                else fputs("    test rax, rax\n    sete al\n    movzx rax, al\n", e->out);
            }
            break;
        case EX_BINARY: {
            if (x->as.binary.op == TK_AND || x->as.binary.op == TK_OR) {
                int decided = e->label++, done = e->label++;
                emit_expr(e, x->as.binary.left);
                fputs("    test rax, rax\n", e->out);
                fprintf(e->out, x->as.binary.op == TK_AND ? "    je np_label_%d\n" : "    jne np_label_%d\n", decided);
                emit_expr(e, x->as.binary.right);
                fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", done, decided);
                fputs(x->as.binary.op == TK_AND ? "    xor eax, eax\n" : "    mov eax, 1\n", e->out);
                fprintf(e->out, "np_label_%d:\n", done);
                break;
            }
            int slot = alloc_temp(e, 1);
            emit_expr(e, x->as.binary.left);
            fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", slot);
            emit_expr(e, x->as.binary.right);
            fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", slot);
            switch (x->as.binary.op) {
                case TK_PLUS: fputs("    add r10, rax\n    mov rax, r10\n", e->out); break;
                case TK_MINUS: fputs("    sub r10, rax\n    mov rax, r10\n", e->out); break;
                case TK_STAR: fputs("    imul r10, rax\n    mov rax, r10\n", e->out); break;
                case TK_SLASH: case TK_PERCENT:
                    {
                        int trap_label = e->label++, safe_label = e->label++;
                        fputs("    test rax, rax\n", e->out);
                        fprintf(e->out, "    je np_div_trap_%d\n    cmp rax, -1\n    jne np_div_safe_%d\n", trap_label, safe_label);
                        fputs(e->windows ? "    mov r11, 8000000000000000h\n" :
                                          "    mov r11, 0x8000000000000000\n", e->out);
                        fprintf(e->out, "    cmp r10, r11\n    je np_div_trap_%d\n    jmp np_div_safe_%d\nnp_div_trap_%d:\n",
                                trap_label, safe_label, trap_label);
                        emit_trap_call(e, x);
                        fprintf(e->out, "np_div_safe_%d:\n", safe_label);
                    }
                    fputs("    mov r11, rax\n    mov rax, r10\n    cqo\n    idiv r11\n", e->out);
                    if (x->as.binary.op == TK_PERCENT) fputs("    mov rax, rdx\n", e->out);
                    break;
                default:
                    fputs("    cmp r10, rax\n", e->out);
                    if (x->as.binary.op == TK_EQ) fputs("    sete al\n", e->out);
                    else if (x->as.binary.op == TK_NE) fputs("    setne al\n", e->out);
                    else if (x->as.binary.op == TK_LT) fputs("    setl al\n", e->out);
                    else if (x->as.binary.op == TK_LE) fputs("    setle al\n", e->out);
                    else if (x->as.binary.op == TK_GT) fputs("    setg al\n", e->out);
                    else fputs("    setge al\n", e->out);
                    fputs("    movzx rax, al\n", e->out);
                    break;
            }
            break;
        }
    }
}

static void emit_zero_stack(Emitter *e, int displacement, size_t bytes) {
    size_t at;
    for (at = 0; at + 8 <= bytes; at += 8)
        fprintf(e->out, "    mov QWORD PTR [rbp-%d], 0\n", displacement - (int)at);
    for (; at < bytes; ++at)
        fprintf(e->out, "    mov BYTE PTR [rbp-%d], 0\n", displacement - (int)at);
}

static void emit_integer_stack(Emitter *e, int displacement, Type type, int64_t value) {
    size_t size = type_size(e->compiler, type);
    if (size == 1) fprintf(e->out, "    mov BYTE PTR [rbp-%d], %lld\n", displacement, (long long)value);
    else if (size == 2) fprintf(e->out, "    mov WORD PTR [rbp-%d], %lld\n", displacement, (long long)value);
    else if (size == 4) fprintf(e->out, "    mov DWORD PTR [rbp-%d], %lld\n", displacement, (long long)value);
    else fprintf(e->out, "    mov QWORD PTR [rbp-%d], %lld\n", displacement, (long long)value);
}

static int expr_is_place(Expr *value) {
    return value->kind == EX_NAME || value->kind == EX_INDEX || value->kind == EX_FIELD ||
           (value->kind == EX_UNARY && value->as.unary.op == TK_STAR);
}

static void emit_copy_addresses(FILE *out, size_t bytes) {
    size_t at;
    for (at = 0; at + 8 <= bytes; at += 8) {
        fprintf(out, "    mov rax, QWORD PTR [r11+%llu]\n", (unsigned long long)at);
        fprintf(out, "    mov QWORD PTR [r10+%llu], rax\n", (unsigned long long)at);
    }
    for (; at < bytes; ++at) {
        fprintf(out, "    mov al, BYTE PTR [r11+%llu]\n", (unsigned long long)at);
        fprintf(out, "    mov BYTE PTR [r10+%llu], al\n", (unsigned long long)at);
    }
}

static void emit_value_to_stack(Emitter *e, Expr *value, Type type, int displacement) {
    if (value->kind == EX_CALL) {
        Function *callee = find_function(e->compiler, value->as.call.callee);
        if (callee && callee->returns_via_slot) {
            emit_call(e, value, displacement);
            return;
        }
    }
    if (value->kind == EX_UNDEF) return;
    if (value->kind == EX_ZERO) {
        emit_zero_stack(e, displacement, type_size(e->compiler, type));
        return;
    }
    if (type.kind == TY_NAMED && value->kind == EX_STRUCT_LITERAL) {
        StructDecl *decl = find_struct(e->compiler, type.name);
        int i;
        if (!decl) return;
        if (decl->kind == ND_TAGGED_UNION && value->as.aggregate.item_count == 1) {
            StructInit *item = &value->as.aggregate.items[0];
            FieldDecl *field = item->field_index >= 0 ? &decl->fields[item->field_index] : 0;
            if (!field) return;
            emit_integer_stack(e, displacement, decl->backing_type, field->value);
            if (item->value)
                emit_value_to_stack(e, item->value, field->type, displacement - (int)field->offset);
            return;
        }
        for (i = 0; i < value->as.aggregate.item_count; ++i) {
            StructInit *item = &value->as.aggregate.items[i];
            FieldDecl *field = &decl->fields[item->field_index];
            if (!item->value) continue;
            emit_value_to_stack(e, item->value, field->type,
                                displacement - (int)field->offset);
        }
        return;
    }
    if (type.kind == TY_NAMED && value->kind == EX_ENUM_MEMBER) {
        StructDecl *decl = find_struct(e->compiler, type.name);
        if (decl && decl->kind == ND_TAGGED_UNION)
            emit_integer_stack(e, displacement, decl->backing_type, value->constant_value);
        else emit_integer_stack(e, displacement, type, value->constant_value);
        return;
    }
    if (type.kind == TY_ARRAY && value->kind == EX_ARRAY_LITERAL) {
        Type element = array_element_type(type);
        size_t stride = type_size(e->compiler, element);
        int i;
        for (i = 0; i < value->as.array.item_count; ++i)
            emit_value_to_stack(e, value->as.array.items[i], element,
                                displacement - (int)((size_t)i * stride));
        return;
    }
    if (type_is_value_aggregate(e->compiler, type) && expr_is_place(value)) {
        emit_place_address(e, value);
        fputs("    mov r11, r10\n", e->out);
        fprintf(e->out, "    lea r10, [rbp-%d]\n", displacement);
        emit_copy_addresses(e->out, type_size(e->compiler, type));
        return;
    }
    emit_expr(e, value);
    emit_stack_store(e, displacement, type);
}

static void emit_statements(Emitter *e, Stmt *s);

static void emit_deferred_statement(Emitter *e, Stmt *defer) {
    if (defer->as.defer_stmt.is_captured_call)
        emit_expr(e, defer->as.defer_stmt.call);
    else emit_statements(e, defer->as.defer_stmt.body);
}

static void emit_scope_defers(Emitter *e, int scope) {
    int i;
    for (i = e->defer_scopes[scope].count - 1; i >= 0; --i)
        emit_deferred_statement(e, e->defer_scopes[scope].items[i]);
}

static void emit_defers_to_depth(Emitter *e, int keep_depth) {
    int scope;
    for (scope = e->defer_scope_depth - 1; scope >= keep_depth; --scope)
        emit_scope_defers(e, scope);
}

static void emit_multiple_call(Emitter *e, Stmt *statement) {
    Function *callee = find_function(e->compiler, statement->as.multi.call->as.call.callee);
    int saved[MAX_ARGS] = {0};
    int i;
    if (!callee) return;
    if (callee->returns_via_slot) {
        int result_slot = alloc_aggregate_temp(e, callee->return_storage_size);
        emit_call(e, statement->as.multi.call, result_slot);
        for (i = 0; i < statement->as.multi.count; ++i) {
            int local_index = statement->as.multi.local_indices[i];
            size_t bytes;
            if (local_index < 0) continue;
            bytes = type_size(e->compiler, callee->return_types[i]);
            fprintf(e->out, "    lea r11, [rbp-%d]\n", result_slot);
            if (callee->return_offsets[i])
                fprintf(e->out, "    add r11, %llu\n",
                        (unsigned long long)callee->return_offsets[i]);
            fprintf(e->out, "    lea r10, [rbp-%d]\n", e->fn->locals[local_index].offset);
            emit_copy_addresses(e->out, bytes);
        }
        return;
    }
    emit_call(e, statement->as.multi.call, 0);
    for (i = 0; i < statement->as.multi.count; ++i) {
        saved[i] = alloc_temp(e, 1);
        fprintf(e->out, "    mov QWORD PTR [rbp-%d], %s\n", saved[i], i == 0 ? "rax" : "rdx");
    }
    for (i = 0; i < statement->as.multi.count; ++i) {
        int local_index = statement->as.multi.local_indices[i];
        if (local_index < 0) continue;
        fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", saved[i]);
        emit_stack_store(e, e->fn->locals[local_index].offset, callee->return_types[i]);
    }
}

static void emit_statements(Emitter *e, Stmt *s) {
    int defer_scope = e->defer_scope_depth++;
    e->defer_scopes[defer_scope].count = 0;
    for (; s; s = s->next) {
        if (!e->windows) fprintf(e->out, "    .loc 1 %d %d\n", s->token.line, s->token.column);
        else {
            s->debug_label = e->debug_label++;
            fprintf(e->out, "np_cv_line_%d LABEL BYTE\n", s->debug_label);
        }
        e->temp_offset = e->call_base;
        switch (s->kind) {
            case ST_BIND: {
                Local *local = &e->fn->locals[s->as.bind.local_index];
                if (type_is_value_aggregate(e->compiler, local->type)) {
                    emit_value_to_stack(e, s->as.bind.value, local->type, local->offset);
                } else if (s->as.bind.value->kind != EX_UNDEF) {
                    emit_expr(e, s->as.bind.value);
                    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", local->offset);
                    if (type_lanes(local->type) == 2) fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", local->offset - 8);
                }
                break;
            }
            case ST_MULTI_BIND:
            case ST_MULTI_ASSIGN:
                emit_multiple_call(e, s);
                break;
            case ST_ASSIGN: {
                int address_slot;
                emit_name_address(e, s->as.assign.target);
                address_slot = alloc_temp(e, 1);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], r10\n", address_slot);
                if (type_is_value_aggregate(e->compiler, s->as.assign.target->type)) {
                    size_t bytes = type_size(e->compiler, s->as.assign.target->type);
                    int source_slot = alloc_aggregate_temp(e, bytes);
                    emit_value_to_stack(e, s->as.assign.value,
                                        s->as.assign.target->type, source_slot);
                    fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
                    fprintf(e->out, "    lea r11, [rbp-%d]\n", source_slot);
                    emit_copy_addresses(e->out, bytes);
                } else {
                    emit_expr(e, s->as.assign.value);
                    fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
                    emit_address_store(e, s->as.assign.target->type, s->as.assign.op);
                }
                break;
            }
            case ST_INDEX_ASSIGN: {
                Expr *target = s->as.index_assign.target;
                Type element = target->type;
                int address_slot;
                if (target->kind == EX_INDEX) address_slot = emit_index_address(e, target);
                else if (target->kind == EX_FIELD) {
                    emit_place_address(e, target);
                    address_slot = alloc_temp(e, 1);
                    fprintf(e->out, "    mov QWORD PTR [rbp-%d], r10\n", address_slot);
                } else {
                    emit_expr(e, target->as.unary.value);
                    address_slot = alloc_temp(e, 1);
                    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", address_slot);
                }
                if (type_is_value_aggregate(e->compiler, element)) {
                    size_t bytes = type_size(e->compiler, element);
                    int source_slot = alloc_aggregate_temp(e, bytes);
                    emit_value_to_stack(e, s->as.index_assign.value, element, source_slot);
                    fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
                    fprintf(e->out, "    lea r11, [rbp-%d]\n", source_slot);
                    emit_copy_addresses(e->out, bytes);
                } else {
                    emit_expr(e, s->as.index_assign.value);
                    fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", address_slot);
                    emit_address_store(e, element, s->as.index_assign.op);
                }
                break;
            }
            case ST_EXPR: emit_expr(e, s->as.expr); break;
            case ST_TRY: {
                int success = e->label++;
                Local *return_value = &e->fn->locals[e->fn->scalar_return_local_index];
                emit_expr(e, s->as.expr);
                fputs("    test rax, rax\n", e->out);
                fprintf(e->out, "    je np_label_%d\n", success);
                emit_stack_store(e, return_value->offset, return_value->type);
                emit_defers_to_depth(e, 0);
                fprintf(e->out, "    lea r10, [rbp-%d]\n", return_value->offset);
                emit_address_load(e, return_value->type);
                fprintf(e->out, "    jmp np_ret_%d\nnp_label_%d:\n", e->return_label, success);
                break;
            }
            case ST_RETURN: {
                int return_index;
                if (e->fn->returns_via_slot) {
                    Local *return_slot = &e->fn->locals[e->fn->return_slot_local_index];
                    for (return_index = 0; return_index < s->as.ret.value_count; ++return_index) {
                        Type type = e->fn->return_types[return_index];
                        size_t bytes = type_size(e->compiler, type);
                        int source_slot = alloc_aggregate_temp(e, bytes);
                        emit_value_to_stack(e, s->as.ret.values[return_index], type, source_slot);
                        fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", return_slot->offset);
                        if (e->fn->return_offsets[return_index])
                            fprintf(e->out, "    add r10, %llu\n",
                                    (unsigned long long)e->fn->return_offsets[return_index]);
                        fprintf(e->out, "    lea r11, [rbp-%d]\n", source_slot);
                        emit_copy_addresses(e->out, bytes);
                    }
                    emit_defers_to_depth(e, 0);
                    fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", return_slot->offset);
                } else if (s->as.ret.value_count) {
                    for (return_index = 0; return_index < s->as.ret.value_count; ++return_index) {
                        Local *return_value = &e->fn->locals[e->fn->return_value_locals[return_index]];
                        emit_expr(e, s->as.ret.values[return_index]);
                        emit_stack_store(e, return_value->offset, return_value->type);
                    }
                    emit_defers_to_depth(e, 0);
                    if (s->as.ret.value_count > 1) {
                        Local *second = &e->fn->locals[e->fn->return_value_locals[1]];
                        fprintf(e->out, "    lea r10, [rbp-%d]\n", second->offset);
                        emit_address_load(e, second->type);
                        fputs("    mov rdx, rax\n", e->out);
                    }
                    {
                        Local *first = &e->fn->locals[e->fn->return_value_locals[0]];
                        fprintf(e->out, "    lea r10, [rbp-%d]\n", first->offset);
                        emit_address_load(e, first->type);
                    }
                } else {
                    emit_defers_to_depth(e, 0);
                    fputs("    xor eax, eax\n", e->out);
                }
                fprintf(e->out, "    jmp np_ret_%d\n", e->return_label);
                break;
            }
            case ST_IF: {
                int other = e->label++, done = e->label++;
                emit_expr(e, s->as.if_stmt.condition);
                fputs("    test rax, rax\n", e->out);
                fprintf(e->out, "    je np_label_%d\n", other);
                emit_statements(e, s->as.if_stmt.then_body);
                fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", done, other);
                emit_statements(e, s->as.if_stmt.else_body);
                fprintf(e->out, "np_label_%d:\n", done);
                break;
            }
            case ST_WHILE: {
                int start = e->label++, done = e->label++;
                fprintf(e->out, "np_label_%d:\n", start);
                emit_expr(e, s->as.while_stmt.condition);
                fputs("    test rax, rax\n", e->out);
                fprintf(e->out, "    je np_label_%d\n", done);
                e->loop_break[e->loop_depth] = done;
                e->loop_continue[e->loop_depth] = start;
                e->loop_break_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_continue_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_depth++;
                emit_statements(e, s->as.while_stmt.body);
                e->loop_depth--;
                fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", start, done);
                break;
            }
            case ST_FOR_RANGE: {
                Local *index = &e->fn->locals[s->as.for_range.local_index];
                Local *limit = &e->fn->locals[s->as.for_range.end_local_index];
                int start = e->label++, step = e->label++, done = e->label++;
                emit_expr(e, s->as.for_range.start);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", index->offset);
                emit_expr(e, s->as.for_range.end);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", limit->offset);
                fprintf(e->out, "np_label_%d:\n", start);
                fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", index->offset);
                fprintf(e->out, "    cmp rax, QWORD PTR [rbp-%d]\n", limit->offset);
                fprintf(e->out, type_is_unsigned(e->compiler, index->type) ?
                        "    jae np_label_%d\n" : "    jge np_label_%d\n", done);
                e->loop_break[e->loop_depth] = done;
                e->loop_continue[e->loop_depth] = step;
                e->loop_break_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_continue_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_depth++;
                emit_statements(e, s->as.for_range.body);
                e->loop_depth--;
                fprintf(e->out, "np_label_%d:\n", step);
                fprintf(e->out, "    add QWORD PTR [rbp-%d], 1\n", index->offset);
                fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", start, done);
                break;
            }
            case ST_FOR_EACH: {
                if (s->as.for_each.is_protocol) {
                    Local *pointer = &e->fn->locals[s->as.for_each.iterator_pointer_local_index];
                    Local *has = &e->fn->locals[s->as.for_each.iterator_has_local_index];
                    Local *value = &e->fn->locals[s->as.for_each.value_local_index];
                    Function *next = find_function(e->compiler, s->as.for_each.next_function);
                    Type element = value->type;
                    size_t bytes = type_size(e->compiler, element);
                    int start = e->label++, done = e->label++;
                    int result_slot = 0;
                    if (s->as.for_each.iterator_subject_is_pointer) {
                        emit_expr(e, s->as.for_each.subject);
                    } else {
                        emit_place_address(e, s->as.for_each.subject);
                        fputs("    mov rax, r10\n", e->out);
                    }
                    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", pointer->offset);
                    if (next && next->returns_via_slot)
                        result_slot = alloc_aggregate_temp(e, next->return_storage_size);
                    fprintf(e->out, "np_label_%d:\n", start);
                    if (next && next->returns_via_slot) {
                        fprintf(e->out, "    lea rax, [rbp-%d]\n", result_slot);
                        emit_argument_lane(e, 0, "rax");
                        {
                            char source[64];
                            snprintf(source, sizeof(source), "QWORD PTR [rbp-%d]", pointer->offset);
                            emit_argument_lane(e, 1, source);
                        }
                        fprintf(e->out, "    call %s\n", symbol_name(next));
                        fprintf(e->out, "    lea r10, [rbp-%d]\n", result_slot);
                        if (next->return_offsets[1])
                            fprintf(e->out, "    add r10, %llu\n",
                                    (unsigned long long)next->return_offsets[1]);
                        emit_address_load(e, next->return_types[1]);
                        emit_stack_store(e, has->offset, has->type);
                        fputs("    test rax, rax\n", e->out);
                        fprintf(e->out, "    je np_label_%d\n", done);
                        fprintf(e->out, "    lea r11, [rbp-%d]\n", result_slot);
                        if (next->return_offsets[0])
                            fprintf(e->out, "    add r11, %llu\n",
                                    (unsigned long long)next->return_offsets[0]);
                        fprintf(e->out, "    lea r10, [rbp-%d]\n", value->offset);
                        emit_copy_addresses(e->out, bytes);
                    } else {
                        char source[64];
                        snprintf(source, sizeof(source), "QWORD PTR [rbp-%d]", pointer->offset);
                        emit_argument_lane(e, 0, source);
                        fprintf(e->out, "    call %s\n", next ? symbol_name(next) : s->as.for_each.next_function);
                        fprintf(e->out, "    mov BYTE PTR [rbp-%d], dl\n", has->offset);
                        fputs("    test rdx, rdx\n", e->out);
                        fprintf(e->out, "    je np_label_%d\n", done);
                        emit_stack_store(e, value->offset, element);
                    }
                    e->loop_break[e->loop_depth] = done;
                    e->loop_continue[e->loop_depth] = start;
                    e->loop_break_scope[e->loop_depth] = e->defer_scope_depth;
                    e->loop_continue_scope[e->loop_depth] = e->defer_scope_depth;
                    e->loop_depth++;
                    emit_statements(e, s->as.for_each.body);
                    e->loop_depth--;
                    fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", start, done);
                    break;
                }
                Local *pointer = &e->fn->locals[s->as.for_each.pointer_local_index];
                Local *length = &e->fn->locals[s->as.for_each.length_local_index];
                Local *index = &e->fn->locals[s->as.for_each.index_local_index];
                Local *value = &e->fn->locals[s->as.for_each.value_local_index];
                Type element = value->type;
                size_t size = type_size(e->compiler, element);
                int start = e->label++, step = e->label++, done = e->label++;
                emit_expr(e, s->as.for_each.subject);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", pointer->offset);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", length->offset);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], 0\n", index->offset);
                fprintf(e->out, "np_label_%d:\n", start);
                fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n", index->offset);
                fprintf(e->out, "    cmp rax, QWORD PTR [rbp-%d]\n", length->offset);
                fprintf(e->out, "    jae np_label_%d\n", done);
                fprintf(e->out, "    mov r10, QWORD PTR [rbp-%d]\n", pointer->offset);
                if (size == 16) fputs("    shl rax, 4\n    add r10, rax\n", e->out);
                else if (size == 8) fputs("    lea r10, [r10+rax*8]\n", e->out);
                else if (size == 4) fputs("    lea r10, [r10+rax*4]\n", e->out);
                else if (size == 2) fputs("    lea r10, [r10+rax*2]\n", e->out);
                else if (size == 1) fputs("    add r10, rax\n", e->out);
                else fprintf(e->out, "    imul rax, %llu\n    add r10, rax\n", (unsigned long long)size);
                if (type_is_value_aggregate(e->compiler, element)) {
                    fputs("    mov r11, r10\n", e->out);
                    fprintf(e->out, "    lea r10, [rbp-%d]\n", value->offset);
                    emit_copy_addresses(e->out, size);
                } else {
                    emit_address_load(e, element);
                    fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", value->offset);
                    if (size == 16)
                        fprintf(e->out, "    mov QWORD PTR [rbp-%d], rdx\n", value->offset - 8);
                }
                e->loop_break[e->loop_depth] = done;
                e->loop_continue[e->loop_depth] = step;
                e->loop_break_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_continue_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_depth++;
                emit_statements(e, s->as.for_each.body);
                e->loop_depth--;
                fprintf(e->out, "np_label_%d:\n", step);
                fprintf(e->out, "    add QWORD PTR [rbp-%d], 1\n", index->offset);
                fprintf(e->out, "    jmp np_label_%d\nnp_label_%d:\n", start, done);
                break;
            }
            case ST_SWITCH: {
                Type subject_type = s->as.switch_stmt.subject->type;
                StructDecl *decl = enum_decl_for_type(e->compiler, subject_type);
                int tagged_subject = decl && decl->kind == ND_TAGGED_UNION &&
                                     strcmp(subject_type.name, decl->name) == 0;
                int subject_slot = 0, tag_slot, done = e->label++, default_label = done;
                int arm_count = 0, arm_index = 0;
                int *arm_labels;
                SwitchCase *arm;
                for (arm = s->as.switch_stmt.cases; arm; arm = arm->next) arm_count++;
                arm_labels = (int *)calloc((size_t)(arm_count ? arm_count : 1), sizeof(*arm_labels));
                if (!arm_labels) { fputs("neper: out of memory\n", stderr); exit(2); }
                for (arm_index = 0; arm_index < arm_count; ++arm_index) arm_labels[arm_index] = e->label++;
                if (tagged_subject) {
                    subject_slot = alloc_aggregate_temp(e, type_size(e->compiler, subject_type));
                    emit_value_to_stack(e, s->as.switch_stmt.subject, subject_type, subject_slot);
                    fprintf(e->out, "    lea r10, [rbp-%d]\n", subject_slot);
                    emit_address_load(e, decl->backing_type);
                } else emit_expr(e, s->as.switch_stmt.subject);
                tag_slot = alloc_temp(e, 1);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", tag_slot);
                arm_index = 0;
                for (arm = s->as.switch_stmt.cases; arm; arm = arm->next, ++arm_index) {
                    int value_index;
                    if (arm->is_default) { default_label = arm_labels[arm_index]; continue; }
                    for (value_index = 0; value_index < arm->value_count; ++value_index) {
                        Expr *value = arm->values[value_index];
                        int64_t constant = 0;
                        case_constant_value(value, &constant);
                        fprintf(e->out, "    mov rax, QWORD PTR [rbp-%d]\n    cmp rax, %lld\n    je np_label_%d\n",
                                tag_slot, (long long)constant, arm_labels[arm_index]);
                    }
                }
                fprintf(e->out, "    jmp np_label_%d\n", default_label);
                e->loop_break[e->loop_depth] = done;
                e->loop_continue[e->loop_depth] = -1;
                e->loop_break_scope[e->loop_depth] = e->defer_scope_depth;
                e->loop_continue_scope[e->loop_depth] = -1;
                e->loop_depth++;
                arm_index = 0;
                for (arm = s->as.switch_stmt.cases; arm; arm = arm->next, ++arm_index) {
                    fprintf(e->out, "np_label_%d:\n", arm_labels[arm_index]);
                    if (arm->local_index >= 0 && tagged_subject && arm->member_index >= 0) {
                        FieldDecl *member = &decl->fields[arm->member_index];
                        Local *local = &e->fn->locals[arm->local_index];
                        fprintf(e->out, "    lea r11, [rbp-%d]\n", subject_slot - (int)member->offset);
                        fprintf(e->out, "    lea r10, [rbp-%d]\n", local->offset);
                        emit_copy_addresses(e->out, type_size(e->compiler, member->type));
                    }
                    emit_statements(e, arm->body);
                    fprintf(e->out, "    jmp np_label_%d\n", done);
                }
                e->loop_depth--;
                fprintf(e->out, "np_label_%d:\n", done);
                free(arm_labels);
                break;
            }
            case ST_DEFER: {
                int capture_index;
                for (capture_index = 0; capture_index < s->as.defer_stmt.capture_count; ++capture_index) {
                    Expr *value = s->as.defer_stmt.capture_values[capture_index];
                    Local *local = &e->fn->locals[s->as.defer_stmt.capture_locals[capture_index]];
                    if (type_is_value_aggregate(e->compiler, local->type))
                        emit_value_to_stack(e, value, local->type, local->offset);
                    else {
                        emit_expr(e, value);
                        emit_stack_store(e, local->offset, local->type);
                    }
                }
                if (e->defer_scopes[defer_scope].count < MAX_LOCALS)
                    e->defer_scopes[defer_scope].items[e->defer_scopes[defer_scope].count++] = s;
                break;
            }
            case ST_BREAK:
                emit_defers_to_depth(e, e->loop_break_scope[e->loop_depth - 1]);
                fprintf(e->out, "    jmp np_label_%d\n", e->loop_break[e->loop_depth - 1]);
                break;
            case ST_CONTINUE: {
                int depth = e->loop_depth - 1;
                while (depth >= 0 && e->loop_continue[depth] < 0) depth--;
                if (depth >= 0) {
                    emit_defers_to_depth(e, e->loop_continue_scope[depth]);
                    fprintf(e->out, "    jmp np_label_%d\n", e->loop_continue[depth]);
                }
                break;
            }
        }
    }
    emit_scope_defers(e, defer_scope);
    e->defer_scope_depth--;
}

static void emit_function(Emitter *e, Function *fn) {
    static const char *win_regs[] = {"rcx", "rdx", "r8", "r9"};
    static const char *sysv_regs[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
    int i, lane = 0;
    assign_offsets(e->compiler, fn);
    e->fn = fn; e->return_label = e->label++;
    e->call_base = fn->local_count ? fn->locals[fn->local_count - 1].offset + 16 : 16;
    if (e->windows) {
        fprintf(e->out, "%s PROC FRAME\n", symbol_name(fn));
        fputs("    push rbp\n    .pushreg rbp\n    mov rbp, rsp\n", e->out);
        if (fn->frame_size >= 4096)
            fprintf(e->out, "    mov eax, %d\n    call np_stack_probe\n    sub rsp, rax\n", fn->frame_size);
        else
            fprintf(e->out, "    sub rsp, %d\n", fn->frame_size);
        fprintf(e->out, "    .allocstack %d\n    .endprolog\n", fn->frame_size);
    } else {
        fprintf(e->out, ".globl %s\n.type %s, @function\n%s:\n", symbol_name(fn), symbol_name(fn), symbol_name(fn));
        fprintf(e->out, "    .loc 1 %d %d\n", fn->token.line, fn->token.column);
        fputs("    .cfi_startproc\n    push rbp\n    .cfi_def_cfa_offset 16\n    .cfi_offset rbp, -16\n    mov rbp, rsp\n    .cfi_def_cfa_register rbp\n", e->out);
        if (fn->frame_size >= 4096)
            fprintf(e->out, "    mov eax, %d\n    call np_stack_probe\n    sub rsp, rax\n", fn->frame_size);
        else
            fprintf(e->out, "    sub rsp, %d\n", fn->frame_size);
    }
    if (fn->return_slot_local_index >= 0) {
        Local *slot = &fn->locals[fn->return_slot_local_index];
        const char *reg = e->windows ? win_regs[lane] : sysv_regs[lane];
        fprintf(e->out, "    mov QWORD PTR [rbp-%d], %s\n", slot->offset, reg);
        lane++;
    }
    for (i = 0; i < fn->param_count; ++i) {
        int k, lanes;
        Local *local = &fn->locals[fn->params[i].local_index];
        if (type_is_value_aggregate(e->compiler, fn->params[i].type)) {
            size_t bytes = type_size(e->compiler, fn->params[i].type);
            lanes = local->is_indirect ? 1 : (int)((bytes + 7) / 8);
            if (lanes == 0) lanes = 1;
        } else lanes = type_lanes(fn->params[i].type);
        if (local->is_indirect) {
            size_t bytes = type_size(e->compiler, fn->params[i].type), copied = 0;
            const char *reg = e->windows ? (lane < 4 ? win_regs[lane] : 0) :
                                          (lane < 6 ? sysv_regs[lane] : 0);
            if (reg) fprintf(e->out, "    mov r11, %s\n", reg);
            else if (e->windows) fprintf(e->out, "    mov r11, QWORD PTR [rbp+%d]\n", 48 + (lane - 4) * 8);
            else fprintf(e->out, "    mov r11, QWORD PTR [rbp+%d]\n", 16 + (lane - 6) * 8);
            lane++;
            while (bytes - copied >= 8) {
                fprintf(e->out, "    mov rax, QWORD PTR [r11+%u]\n", (unsigned)copied);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", local->offset - (int)copied);
                copied += 8;
            }
            if (bytes - copied >= 4) {
                fprintf(e->out, "    mov eax, DWORD PTR [r11+%u]\n", (unsigned)copied);
                fprintf(e->out, "    mov DWORD PTR [rbp-%d], eax\n", local->offset - (int)copied);
                copied += 4;
            }
            if (bytes - copied >= 2) {
                fprintf(e->out, "    mov ax, WORD PTR [r11+%u]\n", (unsigned)copied);
                fprintf(e->out, "    mov WORD PTR [rbp-%d], ax\n", local->offset - (int)copied);
                copied += 2;
            }
            if (bytes != copied) {
                fprintf(e->out, "    mov al, BYTE PTR [r11+%u]\n", (unsigned)copied);
                fprintf(e->out, "    mov BYTE PTR [rbp-%d], al\n", local->offset - (int)copied);
            }
            continue;
        }
        for (k = 0; k < lanes; ++k, ++lane) {
            const char *reg = e->windows ? (lane < 4 ? win_regs[lane] : 0) : (lane < 6 ? sysv_regs[lane] : 0);
            if (reg) fprintf(e->out, "    mov QWORD PTR [rbp-%d], %s\n", local->offset - k * 8, reg);
            else if (e->windows) {
                fprintf(e->out, "    mov rax, QWORD PTR [rbp+%d]\n", 48 + (lane - 4) * 8);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", local->offset - k * 8);
            } else {
                fprintf(e->out, "    mov rax, QWORD PTR [rbp+%d]\n", 16 + (lane - 6) * 8);
                fprintf(e->out, "    mov QWORD PTR [rbp-%d], rax\n", local->offset - k * 8);
            }
        }
    }
    emit_statements(e, fn->body);
    fputs("    xor eax, eax\n", e->out);
    fprintf(e->out, "np_ret_%d:\n    mov rsp, rbp\n    pop rbp\n    ret\n", e->return_label);
    if (e->windows) fprintf(e->out, "np_end_%s LABEL BYTE\n%s ENDP\n\n", symbol_name(fn), symbol_name(fn));
    else { fprintf(e->out, "np_end_%s:\n", symbol_name(fn)); fputs("    .cfi_endproc\n", e->out); fprintf(e->out, ".size %s, .-%s\n\n", symbol_name(fn), symbol_name(fn)); }
}

static void emit_bytes(FILE *out, const unsigned char *bytes, size_t n, int windows) {
    size_t i;
    for (i = 0; i < n; ++i) {
        if (i % 12 == 0) fputs(windows ? "    DB " : "    .byte ", out);
        if (windows) fprintf(out, "0%02Xh", bytes[i]);
        else fprintf(out, "0x%02x", bytes[i]);
        if (i % 12 == 11 || i + 1 == n) fputc('\n', out); else fputs(", ", out);
    }
    if (n == 0) fputs(windows ? "    DB 0\n" : "    .byte 0\n", out);
}

#define MAX_DEBUG_TYPES 2048
#define MAX_DEBUG_STRINGS 8192

typedef struct DebugTypeEntry {
    Type type;
    uint32_t codeview_type;
    uint32_t codeview_forward_type;
    uint32_t codeview_field_list;
    uint32_t codeview_const_type;
} DebugTypeEntry;

typedef struct DebugStringEntry {
    char text[192];
} DebugStringEntry;

typedef struct DebugContext {
    DebugTypeEntry types[MAX_DEBUG_TYPES];
    int type_count;
    DebugStringEntry strings[MAX_DEBUG_STRINGS];
    int string_count;
    uint32_t codeview_arg_lists[MAX_DECLS];
    uint32_t codeview_functions[MAX_DECLS];
} DebugContext;

static int debug_visible_local(Local *local) {
    return local->name[0] && local->name[0] != '$' && strcmp(local->name, "_") != 0;
}

static int debug_string(DebugContext *debug, const char *text) {
    int i;
    for (i = 0; i < debug->string_count; ++i)
        if (strcmp(debug->strings[i].text, text) == 0) return i;
    if (debug->string_count >= MAX_DEBUG_STRINGS) return 0;
    copy_text(debug->strings[debug->string_count].text,
              sizeof(debug->strings[debug->string_count].text), text, strlen(text));
    return debug->string_count++;
}

static int debug_find_string(DebugContext *debug, const char *text) {
    int i;
    for (i = 0; i < debug->string_count; ++i)
        if (strcmp(debug->strings[i].text, text) == 0) return i;
    return -1;
}

static void debug_type_name(Type type, char *out, size_t capacity) {
    char element[128];
    if (type.kind == TY_POINTER) {
        debug_type_name(pointer_element_type(type), element, sizeof(element));
        snprintf(out, capacity, type.is_const ? "*const %s" : "*%s", element);
    } else if (type.kind == TY_SLICE) {
        debug_type_name(sequence_element_type(type), element, sizeof(element));
        snprintf(out, capacity, type.is_const ? "[]const %s" : "[]%s", element);
    } else if (type.kind == TY_ARRAY) {
        debug_type_name(array_element_type(type), element, sizeof(element));
        snprintf(out, capacity, "[%llu]%s", (unsigned long long)type.array_length, element);
    } else if (type.kind == TY_BOOL) copy_text(out, capacity, "bool", 4);
    else if (type.kind == TY_ERR) copy_text(out, capacity, "err", 3);
    else if (type.kind == TY_STR) copy_text(out, capacity, "str", 3);
    else if (type.kind == TY_ARENA) copy_text(out, capacity, "mem.Arena", 9);
    else copy_text(out, capacity, type.name, strlen(type.name));
}

static int debug_find_type(DebugContext *debug, Type type) {
    int i;
    for (i = 0; i < debug->type_count; ++i)
        if (type_equal(debug->types[i].type, type)) return i;
    return -1;
}

static int debug_add_type(Compiler *c, DebugContext *debug, Type type) {
    int id = debug_find_type(debug, type), i;
    StructDecl *decl;
    if (id >= 0) return id;
    if (debug->type_count >= MAX_DEBUG_TYPES) return 0;
    id = debug->type_count++;
    debug->types[id].type = type;
    if (type.kind == TY_POINTER) {
        Type element = pointer_element_type(type);
        debug_add_type(c, debug, element);
    } else if (type.kind == TY_SLICE) {
        Type element = sequence_element_type(type);
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element); pointer.is_const = type.is_const;
        debug_add_type(c, debug, element);
        debug_add_type(c, debug, pointer);
        debug_add_type(c, debug, type_make(TY_INT, "usize"));
    } else if (type.kind == TY_STR) {
        Type element = type_make(TY_INT, "u8");
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element); pointer.is_const = 1;
        debug_add_type(c, debug, element);
        debug_add_type(c, debug, pointer);
        debug_add_type(c, debug, type_make(TY_INT, "usize"));
    } else if (type.kind == TY_ARRAY) {
        debug_add_type(c, debug, array_element_type(type));
    } else if (type.kind == TY_ARENA) {
        Type element = type_make(TY_INT, "u8");
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element);
        debug_add_type(c, debug, element);
        debug_add_type(c, debug, pointer);
        debug_add_type(c, debug, type_make(TY_INT, "usize"));
    } else if (type.kind == TY_NAMED) {
        decl = find_struct(c, type.name);
        if (!decl) decl = find_tag_owner(c, type.name);
        if (decl) {
            if (find_tag_owner(c, type.name)) debug_add_type(c, debug, decl->backing_type);
            else if (decl->kind == ND_ENUM) debug_add_type(c, debug, decl->backing_type);
            else if (decl->kind == ND_TAGGED_UNION) {
                char tag_name[160];
                Type tag;
                snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
                tag = type_make(TY_NAMED, tag_name);
                debug_add_type(c, debug, tag);
            }
            for (i = 0; i < decl->field_count; ++i)
                if (decl->kind == ND_STRUCT || decl->kind == ND_UNION ||
                    (decl->kind == ND_TAGGED_UNION && decl->fields[i].has_payload))
                    debug_add_type(c, debug, decl->fields[i].type);
        }
    }
    return id;
}

static void prepare_debug_context(Compiler *c, DebugContext *debug) {
    int i, j;
    char name[160];
    memset(debug, 0, sizeof(*debug));
    debug_string(debug, "neper " NEPER_VERSION);
    debug_string(debug, c->source_path);
    debug_string(debug, ".");
    debug_string(debug, "ptr"); debug_string(debug, "len");
    debug_string(debug, "base"); debug_string(debug, "cap"); debug_string(debug, "off");
    debug_string(debug, "tag");
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (fn->is_template || fn->is_intrinsic) continue;
        debug_string(debug, fn->name); debug_string(debug, fn->symbol);
        for (j = 0; j < fn->return_count; ++j) debug_add_type(c, debug, fn->return_types[j]);
        for (j = 0; j < fn->param_count; ++j) debug_add_type(c, debug, fn->params[j].type);
        for (j = 0; j < fn->local_count; ++j) if (debug_visible_local(&fn->locals[j])) {
            debug_string(debug, fn->locals[j].name);
            debug_add_type(c, debug, fn->locals[j].type);
        }
    }
    for (i = 0; i < debug->type_count; ++i) {
        Type type = debug->types[i].type;
        StructDecl *decl = type.kind == TY_NAMED ? find_struct(c, type.name) : 0;
        if (!decl && type.kind == TY_NAMED) decl = find_tag_owner(c, type.name);
        debug_type_name(type, name, sizeof(name)); debug_string(debug, name);
        if (decl) for (j = 0; j < decl->field_count; ++j)
            debug_string(debug, decl->fields[j].name);
    }
}

static void emit_dwarf_abbrev(FILE *out) {
    fputs(
        ".section .debug_abbrev,\"\",@progbits\nnp_debug_abbrev_start:\n"
        /* compile_unit */
        ".uleb128 1\n.uleb128 0x11\n.byte 1\n"
        ".uleb128 0x25\n.uleb128 0x0e\n.uleb128 0x13\n.uleb128 0x05\n"
        ".uleb128 0x03\n.uleb128 0x0e\n.uleb128 0x1b\n.uleb128 0x0e\n"
        ".uleb128 0x10\n.uleb128 0x17\n.uleb128 0x11\n.uleb128 0x01\n"
        ".uleb128 0x12\n.uleb128 0x07\n.byte 0\n.byte 0\n"
        /* subprogram with return type */
        ".uleb128 2\n.uleb128 0x2e\n.byte 1\n.uleb128 0x3f\n.uleb128 0x19\n"
        ".uleb128 0x03\n.uleb128 0x0e\n.uleb128 0x6e\n.uleb128 0x0e\n"
        ".uleb128 0x3a\n.uleb128 0x0b\n.uleb128 0x3b\n.uleb128 0x06\n"
        ".uleb128 0x49\n.uleb128 0x13\n.uleb128 0x11\n.uleb128 0x01\n"
        ".uleb128 0x12\n.uleb128 0x07\n.uleb128 0x40\n.uleb128 0x18\n.byte 0\n.byte 0\n"
        /* formal_parameter and variable */
        ".uleb128 3\n.uleb128 0x05\n.byte 0\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x3a\n.uleb128 0x0b\n.uleb128 0x3b\n.uleb128 0x06\n"
        ".uleb128 0x49\n.uleb128 0x13\n.uleb128 0x02\n.uleb128 0x18\n.byte 0\n.byte 0\n"
        ".uleb128 4\n.uleb128 0x34\n.byte 0\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x3a\n.uleb128 0x0b\n.uleb128 0x3b\n.uleb128 0x06\n"
        ".uleb128 0x49\n.uleb128 0x13\n.uleb128 0x02\n.uleb128 0x18\n.byte 0\n.byte 0\n"
        /* base, pointer, const */
        ".uleb128 5\n.uleb128 0x24\n.byte 0\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x0b\n.uleb128 0x0b\n.uleb128 0x3e\n.uleb128 0x0b\n.byte 0\n.byte 0\n"
        ".uleb128 6\n.uleb128 0x0f\n.byte 0\n.uleb128 0x0b\n.uleb128 0x0b\n"
        ".uleb128 0x49\n.uleb128 0x13\n.byte 0\n.byte 0\n"
        ".uleb128 7\n.uleb128 0x26\n.byte 0\n.uleb128 0x49\n.uleb128 0x13\n.byte 0\n.byte 0\n"
        /* structure/member, union, enum/enumerator */
        ".uleb128 8\n.uleb128 0x13\n.byte 1\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x0b\n.uleb128 0x06\n.byte 0\n.byte 0\n"
        ".uleb128 9\n.uleb128 0x0d\n.byte 0\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x49\n.uleb128 0x13\n.uleb128 0x38\n.uleb128 0x06\n.byte 0\n.byte 0\n"
        ".uleb128 10\n.uleb128 0x17\n.byte 1\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x0b\n.uleb128 0x06\n.byte 0\n.byte 0\n"
        ".uleb128 11\n.uleb128 0x04\n.byte 1\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x0b\n.uleb128 0x0b\n.uleb128 0x49\n.uleb128 0x13\n.byte 0\n.byte 0\n"
        ".uleb128 12\n.uleb128 0x28\n.byte 0\n.uleb128 0x03\n.uleb128 0x0e\n"
        ".uleb128 0x1c\n.uleb128 0x0d\n.byte 0\n.byte 0\n"
        /* array/subrange */
        ".uleb128 13\n.uleb128 0x01\n.byte 1\n.uleb128 0x49\n.uleb128 0x13\n.byte 0\n.byte 0\n"
        ".uleb128 14\n.uleb128 0x21\n.byte 0\n.uleb128 0x37\n.uleb128 0x0f\n.byte 0\n.byte 0\n"
        /* void subprogram */
        ".uleb128 15\n.uleb128 0x2e\n.byte 1\n.uleb128 0x3f\n.uleb128 0x19\n"
        ".uleb128 0x03\n.uleb128 0x0e\n.uleb128 0x6e\n.uleb128 0x0e\n"
        ".uleb128 0x3a\n.uleb128 0x0b\n.uleb128 0x3b\n.uleb128 0x06\n"
        ".uleb128 0x11\n.uleb128 0x01\n.uleb128 0x12\n.uleb128 0x07\n"
        ".uleb128 0x40\n.uleb128 0x18\n.byte 0\n.byte 0\n.byte 0\n", out);
}

static void emit_dwarf_string_ref(FILE *out, DebugContext *debug, const char *text) {
    int id = debug_find_string(debug, text);
    if (id < 0) { fputs("neper: internal debug string was not prepared\n", stderr); exit(2); }
    fprintf(out, ".long np_dw_str_%d\n", id);
}

static void emit_dwarf_type_ref(FILE *out, DebugContext *debug, Type type) {
    int id = debug_find_type(debug, type);
    if (id < 0) { fputs("neper: internal debug type was not prepared\n", stderr); exit(2); }
    fprintf(out, ".long np_dw_type_%d - np_debug_info_start\n", id);
}

static void emit_dwarf_member(FILE *out, DebugContext *debug, const char *name,
                              Type type, size_t offset) {
    fputs(".uleb128 9\n", out); emit_dwarf_string_ref(out, debug, name);
    emit_dwarf_type_ref(out, debug, type);
    fprintf(out, ".long %u\n", (unsigned)offset);
}

static void emit_dwarf_type(Compiler *c, FILE *out, DebugContext *debug, int id) {
    Type type = debug->types[id].type;
    char name[160];
    size_t size = 0, alignment = 1;
    StructDecl *decl = type.kind == TY_NAMED ? find_struct(c, type.name) : 0;
    StructDecl *tag_owner = type.kind == TY_NAMED ? find_tag_owner(c, type.name) : 0;
    int i;
    debug_type_name(type, name, sizeof(name));
    type_layout(c, type, &size, &alignment);
    fprintf(out, "np_dw_type_%d:\n", id);
    if (type.kind == TY_BOOL || type.kind == TY_ERR || type.kind == TY_INT) {
        int encoding = type.kind == TY_BOOL ? 0x02 : type_is_signed_integer(c, type) ? 0x05 : 0x07;
        fputs(".uleb128 5\n", out); emit_dwarf_string_ref(out, debug, name);
        fprintf(out, ".byte %u\n.byte %d\n", (unsigned)size, encoding);
    } else if (type.kind == TY_POINTER) {
        Type element = pointer_element_type(type);
        fputs(".uleb128 6\n.byte 8\n", out);
        if (type.is_const) {
            fprintf(out, ".long np_dw_const_%d - np_debug_info_start\n", id);
            fprintf(out, "np_dw_const_%d:\n.uleb128 7\n", id);
            emit_dwarf_type_ref(out, debug, element);
        } else emit_dwarf_type_ref(out, debug, element);
    } else if (type.kind == TY_ARRAY) {
        fputs(".uleb128 13\n", out); emit_dwarf_type_ref(out, debug, array_element_type(type));
        fprintf(out, ".uleb128 14\n.uleb128 %llu\n.byte 0\n",
                (unsigned long long)type.array_length);
    } else if (type.kind == TY_STR || type.kind == TY_SLICE) {
        Type element = type.kind == TY_STR ? type_make(TY_INT, "u8") : sequence_element_type(type);
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element); pointer.is_const = type.kind == TY_STR || type.is_const;
        fputs(".uleb128 8\n", out); emit_dwarf_string_ref(out, debug, name); fputs(".long 16\n", out);
        emit_dwarf_member(out, debug, "ptr", pointer, 0);
        emit_dwarf_member(out, debug, "len", type_make(TY_INT, "usize"), 8);
        fputs(".byte 0\n", out);
    } else if (type.kind == TY_ARENA) {
        Type element = type_make(TY_INT, "u8");
        Type pointer = type_make(TY_POINTER, element.name); type_set_element(&pointer, element);
        fputs(".uleb128 8\n", out); emit_dwarf_string_ref(out, debug, name); fputs(".long 24\n", out);
        emit_dwarf_member(out, debug, "base", pointer, 0);
        emit_dwarf_member(out, debug, "cap", type_make(TY_INT, "usize"), 8);
        emit_dwarf_member(out, debug, "off", type_make(TY_INT, "usize"), 16);
        fputs(".byte 0\n", out);
    } else if (tag_owner || (decl && decl->kind == ND_ENUM)) {
        StructDecl *owner = tag_owner ? tag_owner : decl;
        Type backing = owner->backing_type;
        fputs(".uleb128 11\n", out); emit_dwarf_string_ref(out, debug, name);
        fprintf(out, ".byte %u\n", (unsigned)scalar_byte_size(backing));
        emit_dwarf_type_ref(out, debug, backing);
        for (i = 0; i < owner->field_count; ++i) {
            fputs(".uleb128 12\n", out); emit_dwarf_string_ref(out, debug, owner->fields[i].name);
            fprintf(out, ".sleb128 %lld\n", (long long)owner->fields[i].value);
        }
        fputs(".byte 0\n", out);
    } else if (decl) {
        fprintf(out, ".uleb128 %d\n", decl->kind == ND_UNION ? 10 : 8);
        emit_dwarf_string_ref(out, debug, name); fprintf(out, ".long %u\n", (unsigned)decl->size);
        if (decl->kind == ND_TAGGED_UNION) {
            char tag_name[160]; Type tag;
            snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
            tag = type_make(TY_NAMED, tag_name);
            emit_dwarf_member(out, debug, "tag", tag, 0);
        }
        for (i = 0; i < decl->field_count; ++i)
            if (decl->kind != ND_TAGGED_UNION || decl->fields[i].has_payload)
                emit_dwarf_member(out, debug, decl->fields[i].name, decl->fields[i].type,
                                  decl->kind == ND_UNION ? 0 : decl->fields[i].offset);
        fputs(".byte 0\n", out);
    } else {
        fputs(".uleb128 5\n", out); emit_dwarf_string_ref(out, debug, name);
        fputs(".byte 8\n.byte 0x07\n", out);
    }
}

static int function_param_for_local(Function *fn, int local_index) {
    int i;
    for (i = 0; i < fn->param_count; ++i)
        if (fn->params[i].local_index == local_index) return i;
    return -1;
}

static void emit_linux_debug(Compiler *c, FILE *out) {
    DebugContext *debug = (DebugContext *)calloc(1, sizeof(*debug));
    int i, j;
    if (!debug) { fputs("neper: out of memory\n", stderr); exit(2); }
    prepare_debug_context(c, debug);
    fputs(".section .debug_str,\"MS\",@progbits,1\nnp_debug_str_start:\n", out);
    for (i = 0; i < debug->string_count; ++i) {
        fprintf(out, "np_dw_str_%d:\n", i);
        emit_bytes(out, (const unsigned char *)debug->strings[i].text,
                   strlen(debug->strings[i].text) + 1, 0);
    }
    emit_dwarf_abbrev(out);
    fputs(".section .debug_info,\"\",@progbits\nnp_debug_info_start:\n"
          ".long np_debug_info_end - np_debug_info_body\nnp_debug_info_body:\n"
          ".short 4\n.long np_debug_abbrev_start\n.byte 8\n"
          ".uleb128 1\n", out);
    emit_dwarf_string_ref(out, debug, "neper " NEPER_VERSION);
    fputs(".short 0x8000\n", out);
    emit_dwarf_string_ref(out, debug, c->source_path);
    emit_dwarf_string_ref(out, debug, ".");
    fputs(".long 0\n.quad np_user_text_start\n.quad np_user_text_end - np_user_text_start\n", out);
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (fn->is_template || fn->is_intrinsic) continue;
        fprintf(out, ".uleb128 %d\n", fn->return_count ? 2 : 15);
        emit_dwarf_string_ref(out, debug, fn->name);
        emit_dwarf_string_ref(out, debug, fn->symbol);
        fprintf(out, ".byte 1\n.long %d\n", fn->token.line);
        if (fn->return_count) emit_dwarf_type_ref(out, debug, fn->return_types[0]);
        fprintf(out, ".quad %s\n.quad np_end_%s - %s\n.uleb128 1\n.byte 0x56\n",
                fn->symbol, fn->symbol, fn->symbol);
        for (j = 0; j < fn->local_count; ++j) {
            Local *local = &fn->locals[j];
            int parameter = function_param_for_local(fn, j);
            if (!debug_visible_local(local)) continue;
            fprintf(out, ".uleb128 %d\n", parameter >= 0 ? 3 : 4);
            emit_dwarf_string_ref(out, debug, local->name);
            fprintf(out, ".byte 1\n.long %d\n", local->token.line ? local->token.line : fn->token.line);
            emit_dwarf_type_ref(out, debug, local->type);
            fprintf(out, ".uleb128 np_dw_loc_end_%d_%d - np_dw_loc_%d_%d\n"
                         "np_dw_loc_%d_%d:\n.byte 0x91\n.sleb128 -%d\nnp_dw_loc_end_%d_%d:\n",
                    i, j, i, j, i, j, local->offset, i, j);
        }
        fputs(".byte 0\n", out);
    }
    for (i = 0; i < debug->type_count; ++i) emit_dwarf_type(c, out, debug, i);
    fputs(".byte 0\nnp_debug_info_end:\n", out);
    free(debug);
}

static void error_message(Compiler *c, ErrorDecl *error, char *out, size_t capacity) {
    const char *a = strrchr(c->source_path, '/');
    const char *b = strrchr(c->source_path, '\\');
    const char *base = a && (!b || a > b) ? a : b;
    const char *dot;
    size_t module_length;
    if (base) base++; else base = c->source_path;
    dot = strrchr(base, '.');
    module_length = dot ? (size_t)(dot - base) : strlen(base);
    if (error->module[0]) snprintf(out, capacity, "error: %s.%s\n", error->module, error->name);
    else snprintf(out, capacity, "error: %.*s.%s\n", (int)module_length, base, error->name);
}

static void emit_nepersym(Compiler *c, FILE *out, int windows) {
    int i, concrete_count = 0, record_index = 0;
    for (i = 0; i < c->program.function_count; ++i)
        if (!c->program.functions[i].is_template && !c->program.functions[i].is_intrinsic) concrete_count++;
    if (windows) {
        fputs("\n.nepsym SEGMENT READ\nPUBLIC np_nepersym\nnp_nepersym LABEL BYTE\n"
              "DB 'N','E','P','S'\nDW 1,0\n", out);
        fprintf(out, "DD %d\n", concrete_count);
        for (i = 0; i < c->program.function_count; ++i) {
            Function *fn = &c->program.functions[i];
            if (fn->is_template || fn->is_intrinsic) continue;
            fprintf(out, "DQ %s, np_end_%s\nDD %d, %d, %d\n",
                    symbol_name(fn), symbol_name(fn), record_index, concrete_count, record_index);
            record_index++;
        }
        fprintf(out, "DD %d\n", concrete_count + 1);
        for (i = 0; i < c->program.function_count; ++i) {
            Function *fn = &c->program.functions[i];
            if (fn->is_template || fn->is_intrinsic) continue;
            fprintf(out, "DD %u\n", (unsigned)strlen(fn->name));
            emit_bytes(out, (const unsigned char *)fn->name, strlen(fn->name), 1);
        }
        fprintf(out, "DD %u\n", (unsigned)strlen(c->source_path));
        emit_bytes(out, (const unsigned char *)c->source_path, strlen(c->source_path), 1);
        fprintf(out, "DD %d\n", concrete_count);
        for (i = 0; i < c->program.function_count; ++i)
            if (!c->program.functions[i].is_template && !c->program.functions[i].is_intrinsic)
                fprintf(out, "DD 8, %d, %d\n", c->program.functions[i].token.line, c->program.functions[i].token.column);
        fputs(".nepsym ENDS\n\n.code\n", out);
    } else {
        fputs("\n.section .nepersym,\"R\",@progbits\n.globl np_nepersym\nnp_nepersym:\n"
              ".ascii \"NEPS\"\n.short 1\n.short 0\n", out);
        fprintf(out, ".long %d\n", concrete_count);
        for (i = 0; i < c->program.function_count; ++i) {
            Function *fn = &c->program.functions[i];
            if (fn->is_template || fn->is_intrinsic) continue;
            fprintf(out, ".quad %s, np_end_%s\n.long %d, %d, %d\n",
                    symbol_name(fn), symbol_name(fn), record_index, concrete_count, record_index);
            record_index++;
        }
        fprintf(out, ".long %d\n", concrete_count + 1);
        for (i = 0; i < c->program.function_count; ++i) {
            Function *fn = &c->program.functions[i];
            if (fn->is_template || fn->is_intrinsic) continue;
            fprintf(out, ".long %u\n", (unsigned)strlen(fn->name));
            emit_bytes(out, (const unsigned char *)fn->name, strlen(fn->name), 0);
        }
        fprintf(out, ".long %u\n", (unsigned)strlen(c->source_path));
        emit_bytes(out, (const unsigned char *)c->source_path, strlen(c->source_path), 0);
        fprintf(out, ".long %d\n", concrete_count);
        for (i = 0; i < c->program.function_count; ++i)
            if (!c->program.functions[i].is_template && !c->program.functions[i].is_intrinsic)
                fprintf(out, ".long 8, %d, %d\n", c->program.functions[i].token.line, c->program.functions[i].token.column);
        fputs("\n.text\n", out);
    }
}

static int statement_line_count(Stmt *statement) {
    int count = 0;
    for (; statement; statement = statement->next) {
        count++;
        if (statement->kind == ST_IF) {
            count += statement_line_count(statement->as.if_stmt.then_body);
            count += statement_line_count(statement->as.if_stmt.else_body);
        } else if (statement->kind == ST_WHILE) count += statement_line_count(statement->as.while_stmt.body);
        else if (statement->kind == ST_FOR_RANGE) count += statement_line_count(statement->as.for_range.body);
        else if (statement->kind == ST_FOR_EACH) count += statement_line_count(statement->as.for_each.body);
    }
    return count;
}

static void emit_codeview_statement_lines(FILE *out, Function *fn, Stmt *statement) {
    for (; statement; statement = statement->next) {
        fprintf(out, "DD np_cv_line_%d - %s, 080000000h + %d\n",
                statement->debug_label, symbol_name(fn), statement->token.line);
        if (statement->kind == ST_IF) {
            emit_codeview_statement_lines(out, fn, statement->as.if_stmt.then_body);
            emit_codeview_statement_lines(out, fn, statement->as.if_stmt.else_body);
        } else if (statement->kind == ST_WHILE)
            emit_codeview_statement_lines(out, fn, statement->as.while_stmt.body);
        else if (statement->kind == ST_FOR_RANGE)
            emit_codeview_statement_lines(out, fn, statement->as.for_range.body);
        else if (statement->kind == ST_FOR_EACH)
            emit_codeview_statement_lines(out, fn, statement->as.for_each.body);
    }
}

typedef struct CodeviewMember {
    const char *name;
    Type type;
    size_t offset;
    int is_enumerator;
    int64_t value;
} CodeviewMember;

static uint32_t codeview_simple_type(Type type) {
    if (type.kind == TY_VOID) return 0x0003;
    if (type.kind == TY_BOOL) return 0x0030;
    if (type.kind == TY_ERR) return 0x0075;
    if (type.kind != TY_INT) return 0;
    if (strcmp(type.name, "i8") == 0) return 0x0068;
    if (strcmp(type.name, "u8") == 0) return 0x0069;
    if (strcmp(type.name, "i16") == 0) return 0x0072;
    if (strcmp(type.name, "u16") == 0) return 0x0073;
    if (strcmp(type.name, "i32") == 0) return 0x0074;
    if (strcmp(type.name, "u32") == 0) return 0x0075;
    if (strcmp(type.name, "i64") == 0 || strcmp(type.name, "isize") == 0) return 0x0076;
    return 0x0077;
}

static int codeview_type_has_field_list(Compiler *c, Type type) {
    StructDecl *decl;
    if (type.kind == TY_STR || type.kind == TY_SLICE || type.kind == TY_ARENA) return 1;
    if (type.kind != TY_NAMED) return 0;
    decl = find_struct(c, type.name);
    if (!decl) decl = find_tag_owner(c, type.name);
    return decl != 0;
}

static int codeview_type_needs_forward(Compiler *c, Type type) {
    StructDecl *decl = type.kind == TY_NAMED ? find_struct(c, type.name) : 0;
    return decl && decl->kind != ND_ENUM;
}

static void prepare_codeview_indices(Compiler *c, DebugContext *debug) {
    uint32_t next = 0x1000;
    int i;
    for (i = 0; i < debug->type_count; ++i) {
        DebugTypeEntry *entry = &debug->types[i];
        uint32_t simple = codeview_simple_type(entry->type);
        if (simple) {
            entry->codeview_type = simple;
            continue;
        }
        if (codeview_type_needs_forward(c, entry->type))
            entry->codeview_forward_type = next++;
        if (entry->type.kind == TY_POINTER && entry->type.is_const)
            entry->codeview_const_type = next++;
        if (codeview_type_has_field_list(c, entry->type))
            entry->codeview_field_list = next++;
        entry->codeview_type = next++;
    }
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (fn->is_template || fn->is_intrinsic) continue;
        debug->codeview_arg_lists[i] = next++;
        debug->codeview_functions[i] = next++;
    }
}

static uint32_t codeview_type_ref(DebugContext *debug, Type type) {
    uint32_t simple = codeview_simple_type(type);
    int id;
    if (simple) return simple;
    id = debug_find_type(debug, type);
    if (id < 0) { fputs("neper: internal CodeView type was not prepared\n", stderr); exit(2); }
    return debug->types[id].codeview_type;
}

static uint32_t codeview_pointee_ref(DebugContext *debug, Type type) {
    int id = debug_find_type(debug, type);
    if (id >= 0 && debug->types[id].codeview_forward_type)
        return debug->types[id].codeview_forward_type;
    return codeview_type_ref(debug, type);
}

static size_t codeview_numeric_size(int64_t value) {
    return value >= 0 && value < 0x8000 ? 2 : 10;
}

static void emit_codeview_numeric(FILE *out, int64_t value, int is_signed) {
    if (value >= 0 && value < 0x8000) fprintf(out, "DW %u\n", (unsigned)value);
    else if (is_signed) fprintf(out, "DW 08009h\nDQ %lld\n", (long long)value);
    else fprintf(out, "DW 0800Ah\nDQ %llu\n", (unsigned long long)value);
}

static size_t codeview_padding(size_t size) {
    return (4 - (size & 3)) & 3;
}

static void emit_codeview_type_padding(FILE *out, size_t padding) {
    size_t i;
    if (!padding) return;
    fputs("DB ", out);
    for (i = padding; i > 0; --i) {
        fprintf(out, "0F%Xh", (unsigned)i);
        if (i > 1) fputs(",", out);
    }
    fputc('\n', out);
}

static int collect_codeview_members(Compiler *c, Type type, CodeviewMember *members) {
    StructDecl *decl = type.kind == TY_NAMED ? find_struct(c, type.name) : 0;
    StructDecl *tag_owner = type.kind == TY_NAMED ? find_tag_owner(c, type.name) : 0;
    int count = 0, i;
    memset(members, 0, sizeof(CodeviewMember) * (MAX_FIELDS + 4));
    if (type.kind == TY_STR || type.kind == TY_SLICE) {
        Type element = type.kind == TY_STR ? type_make(TY_INT, "u8") : sequence_element_type(type);
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element);
        pointer.is_const = type.kind == TY_STR || type.is_const;
        members[count].name = "ptr"; members[count].type = pointer; members[count++].offset = 0;
        members[count].name = "len"; members[count].type = type_make(TY_INT, "usize"); members[count++].offset = 8;
    } else if (type.kind == TY_ARENA) {
        Type element = type_make(TY_INT, "u8");
        Type pointer = type_make(TY_POINTER, element.name);
        type_set_element(&pointer, element);
        members[count].name = "base"; members[count].type = pointer; members[count++].offset = 0;
        members[count].name = "cap"; members[count].type = type_make(TY_INT, "usize"); members[count++].offset = 8;
        members[count].name = "off"; members[count].type = type_make(TY_INT, "usize"); members[count++].offset = 16;
    } else if (tag_owner || (decl && decl->kind == ND_ENUM)) {
        StructDecl *owner = tag_owner ? tag_owner : decl;
        for (i = 0; i < owner->field_count; ++i) {
            members[count].name = owner->fields[i].name;
            members[count].is_enumerator = 1;
            members[count].value = owner->fields[i].value;
            count++;
        }
    } else if (decl) {
        if (decl->kind == ND_TAGGED_UNION) {
            char tag_name[160];
            snprintf(tag_name, sizeof(tag_name), "%s.Tag", decl->name);
            members[count].name = "tag";
            members[count].type = type_make(TY_NAMED, tag_name);
            members[count++].offset = 0;
        }
        for (i = 0; i < decl->field_count; ++i) {
            if (decl->kind == ND_TAGGED_UNION && !decl->fields[i].has_payload) continue;
            members[count].name = decl->fields[i].name;
            members[count].type = decl->fields[i].type;
            members[count].offset = decl->kind == ND_UNION ? 0 : decl->fields[i].offset;
            count++;
        }
    }
    return count;
}

static size_t codeview_member_size(CodeviewMember *member) {
    size_t raw = (member->is_enumerator ? 4 : 8) +
                 codeview_numeric_size(member->is_enumerator ? member->value : (int64_t)member->offset) +
                 strlen(member->name) + 1;
    return raw + codeview_padding(raw);
}

static void emit_codeview_field_list(Compiler *c, FILE *out, DebugContext *debug,
                                     DebugTypeEntry *entry) {
    CodeviewMember members[MAX_FIELDS + 4];
    int count = collect_codeview_members(c, entry->type, members), i;
    size_t members_size = 0;
    for (i = 0; i < count; ++i) members_size += codeview_member_size(&members[i]);
    fprintf(out, "DW %u, 01203h\n", (unsigned)(2 + members_size));
    for (i = 0; i < count; ++i) {
        CodeviewMember *member = &members[i];
        size_t raw;
        if (member->is_enumerator) {
            fputs("DW 01502h, 3\n", out);
            emit_codeview_numeric(out, member->value, 1);
            emit_bytes(out, (const unsigned char *)member->name, strlen(member->name) + 1, 1);
            raw = 4 + codeview_numeric_size(member->value) + strlen(member->name) + 1;
        } else {
            fputs("DW 0150Dh, 3\n", out);
            fprintf(out, "DD 0%08Xh\n", (unsigned)codeview_type_ref(debug, member->type));
            emit_codeview_numeric(out, (int64_t)member->offset, 0);
            emit_bytes(out, (const unsigned char *)member->name, strlen(member->name) + 1, 1);
            raw = 8 + codeview_numeric_size((int64_t)member->offset) + strlen(member->name) + 1;
        }
        emit_codeview_type_padding(out, codeview_padding(raw));
    }
}

static void emit_codeview_type(Compiler *c, FILE *out, DebugContext *debug, int id) {
    DebugTypeEntry *entry = &debug->types[id];
    Type type = entry->type;
    StructDecl *decl = type.kind == TY_NAMED ? find_struct(c, type.name) : 0;
    StructDecl *tag_owner = type.kind == TY_NAMED ? find_tag_owner(c, type.name) : 0;
    char name[160];
    size_t size = 0, alignment = 1, name_size, raw, padding;
    int member_count = 0;
    CodeviewMember members[MAX_FIELDS + 4];
    if (codeview_simple_type(type)) return;
    debug_type_name(type, name, sizeof(name));
    name_size = strlen(name) + 1;
    type_layout(c, type, &size, &alignment);
    if (type.kind == TY_ARENA) size = 24;
    if (entry->codeview_forward_type) {
        int is_union = decl && decl->kind == ND_UNION;
        raw = (is_union ? 12 : 20) + 2 + name_size;
        padding = codeview_padding(raw);
        fprintf(out, "DW %u, 0%04Xh\nDW 0, 080h\nDD 0\n",
                (unsigned)(raw + padding - 2), is_union ? 0x1506 : 0x1505);
        if (!is_union) fputs("DD 0, 0\n", out);
        fputs("DW 0\n", out);
        emit_bytes(out, (const unsigned char *)name, name_size, 1);
        emit_codeview_type_padding(out, padding);
    }
    if (entry->codeview_const_type) {
        fprintf(out, "DW 10, 01001h\nDD 0%08Xh\nDW 1\n", (unsigned)codeview_pointee_ref(debug, pointer_element_type(type)));
        emit_codeview_type_padding(out, 2);
    }
    if (entry->codeview_field_list) {
        emit_codeview_field_list(c, out, debug, entry);
        member_count = collect_codeview_members(c, type, members);
    }
    if (type.kind == TY_POINTER) {
        uint32_t referent = entry->codeview_const_type ? entry->codeview_const_type :
                            codeview_pointee_ref(debug, pointer_element_type(type));
        fprintf(out, "DW 10, 01002h\nDD 0%08Xh\nDD 00001000Ch\n", (unsigned)referent);
    } else if (type.kind == TY_ARRAY) {
        raw = 12 + codeview_numeric_size((int64_t)size) + name_size;
        padding = codeview_padding(raw);
        fprintf(out, "DW %u, 01503h\nDD 0%08Xh, 000000077h\n",
                (unsigned)(raw + padding - 2), (unsigned)codeview_type_ref(debug, array_element_type(type)));
        emit_codeview_numeric(out, (int64_t)size, 0);
        emit_bytes(out, (const unsigned char *)name, name_size, 1);
        emit_codeview_type_padding(out, padding);
    } else if (tag_owner || (decl && decl->kind == ND_ENUM)) {
        StructDecl *owner = tag_owner ? tag_owner : decl;
        raw = 16 + name_size;
        padding = codeview_padding(raw);
        fprintf(out, "DW %u, 01507h\nDW %d, 0\nDD 0%08Xh, 0%08Xh\n",
                (unsigned)(raw + padding - 2), member_count,
                (unsigned)codeview_type_ref(debug, owner->backing_type),
                (unsigned)entry->codeview_field_list);
        emit_bytes(out, (const unsigned char *)name, name_size, 1);
        emit_codeview_type_padding(out, padding);
    } else if (type.kind == TY_STR || type.kind == TY_SLICE || type.kind == TY_ARENA || decl) {
        int is_union = decl && decl->kind == ND_UNION;
        raw = (is_union ? 12 : 20) + codeview_numeric_size((int64_t)size) + name_size;
        padding = codeview_padding(raw);
        fprintf(out, "DW %u, 0%04Xh\nDW %d, 0\nDD 0%08Xh\n",
                (unsigned)(raw + padding - 2), is_union ? 0x1506 : 0x1505,
                member_count, (unsigned)entry->codeview_field_list);
        if (!is_union) fputs("DD 0, 0\n", out);
        emit_codeview_numeric(out, (int64_t)size, 0);
        emit_bytes(out, (const unsigned char *)name, name_size, 1);
        emit_codeview_type_padding(out, padding);
    }
}

static void emit_codeview_function_type(FILE *out, DebugContext *debug, Function *fn, int index) {
    int i;
    fprintf(out, "DW %u, 01201h\nDD %d\n", 6 + fn->param_count * 4, fn->param_count);
    for (i = 0; i < fn->param_count; ++i)
        fprintf(out, "DD 0%08Xh\n", (unsigned)codeview_type_ref(debug, fn->params[i].type));
    fprintf(out, "DW 14, 01008h\nDD 0%08Xh\nDB 0, 0\nDW %d\nDD 0%08Xh\n",
            (unsigned)(fn->return_count ? codeview_type_ref(debug, fn->return_types[0]) : 0x0003),
            fn->param_count, (unsigned)debug->codeview_arg_lists[index]);
}

static void emit_windows_codeview(Compiler *c, FILE *out) {
    DebugContext *debug = (DebugContext *)calloc(1, sizeof(*debug));
    int i, j;
    size_t path_length = strlen(c->source_path);
    size_t string_size = path_length + 2;
    size_t padded_string_size = (string_size + 3) & ~(size_t)3;
    if (!debug) { fputs("neper: out of memory\n", stderr); exit(2); }
    prepare_debug_context(c, debug);
    prepare_codeview_indices(c, debug);

    fputs(".debug_t_neper SEGMENT DWORD READ DISCARD ALIAS('.debug$T')\nDD 4\n", out);
    for (i = 0; i < debug->type_count; ++i) emit_codeview_type(c, out, debug, i);
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (!fn->is_template && !fn->is_intrinsic) emit_codeview_function_type(out, debug, fn, i);
    }
    fputs(".debug_t_neper ENDS\n\n", out);

    fputs(".debug_s_neper SEGMENT DWORD READ DISCARD ALIAS('.debug$S')\nDD 4\n", out);
    fputs("DD 0F1h, np_cv_symbols_end - np_cv_symbols_body\nnp_cv_symbols_body LABEL BYTE\n", out);
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        size_t name_size;
        if (fn->is_template || fn->is_intrinsic) continue;
        name_size = strlen(fn->name) + 1;
        fprintf(out, "DW %u, 01110h\nDD 0, 0, 0\nDD np_end_%s - %s\nDD 0, np_end_%s - %s\n",
                (unsigned)(37 + name_size), symbol_name(fn), symbol_name(fn),
                symbol_name(fn), symbol_name(fn));
        fprintf(out, "DD 0%08Xh\nDD SECTIONREL %s\nDD SECTIONREL %s + 0%02X000000h\n",
                (unsigned)debug->codeview_functions[i], symbol_name(fn), symbol_name(fn),
                (unsigned)(unsigned char)fn->name[0]);
        emit_bytes(out, (const unsigned char *)fn->name + 1, strlen(fn->name), 1);
        fprintf(out, "DW 28, 01012h\nDD %d, 0, 0, 0, 0\nDW 0\nDD 000028000h\n", fn->frame_size);
        for (j = 0; j < fn->local_count; ++j) {
            Local *local = &fn->locals[j];
            size_t local_name_size;
            if (!debug_visible_local(local)) continue;
            local_name_size = strlen(local->name) + 1;
            fprintf(out, "DW %u, 01111h\nDD -%d\nDD 0%08Xh\nDW 014Eh\n",
                    (unsigned)(12 + local_name_size), local->offset,
                    (unsigned)codeview_type_ref(debug, local->type));
            emit_bytes(out, (const unsigned char *)local->name, local_name_size, 1);
        }
        fputs("DW 2, 00006h\n", out);
    }
    for (i = 0; i < debug->type_count; ++i) {
        DebugTypeEntry *entry = &debug->types[i];
        char name[160];
        size_t name_size;
        if (!entry->codeview_field_list) continue;
        debug_type_name(entry->type, name, sizeof(name));
        name_size = strlen(name) + 1;
        fprintf(out, "DW %u, 01108h\nDD 0%08Xh\n",
                (unsigned)(6 + name_size), (unsigned)entry->codeview_type);
        emit_bytes(out, (const unsigned char *)name, name_size, 1);
    }
    fputs("np_cv_symbols_end LABEL BYTE\nALIGN 4\n", out);
    for (i = 0; i < c->program.function_count; ++i) {
        Function *fn = &c->program.functions[i];
        if (fn->is_template || fn->is_intrinsic) continue;
        int line_count = 1 + statement_line_count(fn->body);
        int block_size = 12 + line_count * 8;
        int subsection_size = 12 + block_size;
        fprintf(out, "DD 0F2h, %d\nDD SECTIONREL %s\nDD SECTIONREL %s\n",
                subsection_size, symbol_name(fn), symbol_name(fn));
        fprintf(out, "DD np_end_%s - %s\nDD 0, %d, %d\n",
                symbol_name(fn), symbol_name(fn), line_count, block_size);
        fprintf(out, "DD 0, 080000000h + %d\n", fn->token.line);
        emit_codeview_statement_lines(out, fn, fn->body);
    }
    fputs("DD 0F4h, 8\nDD 1\nDB 0,0,0,0\n", out);
    fprintf(out, "DD 0F3h, %u\nDB 0\n", (unsigned)string_size);
    emit_bytes(out, (const unsigned char *)c->source_path, path_length, 1);
    fputs("DB 0\n", out);
    for (i = (int)string_size; i < (int)padded_string_size; ++i) fputs("DB 0\n", out);
    fputs(".debug_s_neper ENDS\n\n", out);
    free(debug);
}

static void emit_windows_runtime(Compiler *c, FILE *out) {
    int i;
    fputs(
        "EXTERN GetStdHandle:PROC\nEXTERN WriteFile:PROC\nEXTERN VirtualAlloc:PROC\nEXTERN ExitProcess:PROC\n"
        "EXTERN GetCommandLineW:PROC\nEXTERN WideCharToMultiByte:PROC\nEXTERN LocalFree:PROC\n"
        "EXTERN CommandLineToArgvW:PROC\n"
        "EXTERN neper_os_set_args:PROC\nEXTERN neper_os_open:PROC\nEXTERN neper_os_read:PROC\n"
        "EXTERN neper_os_write:PROC\nEXTERN neper_os_close:PROC\nEXTERN neper_os_stdout:PROC\n"
        "EXTERN neper_os_stderr:PROC\nEXTERN neper_os_readdir:PROC\nEXTERN neper_os_spawn:PROC\n"
        "EXTERN neper_os_wait:PROC\nEXTERN neper_os_exit:PROC\nEXTERN neper_os_args:PROC\n"
        "EXTERN neper_os_reserve:PROC\nEXTERN neper_os_commit:PROC\nEXTERN neper_os_clock:PROC\n\n"
        "np_stack_probe PROC\n"
        "    lea r10, [rsp+8]\n    mov r11, rax\n"
        "np_stack_probe_page:\n    cmp r11, 4096\n    jbe np_stack_probe_last\n"
        "    sub r10, 4096\n    test BYTE PTR [r10], 0\n    sub r11, 4096\n"
        "    jmp np_stack_probe_page\n"
        "np_stack_probe_last:\n    sub r10, r11\n    test BYTE PTR [r10], 0\n    ret\n"
        "np_stack_probe ENDP\n\n"
        "neper_io_print PROC FRAME\n"
        "    sub rsp, 88\n    .allocstack 88\n    .endprolog\n"
        "    mov QWORD PTR [rsp+48], rcx\n    mov QWORD PTR [rsp+56], rdx\n"
        "    mov ecx, -11\n    call GetStdHandle\n    cmp rax, -1\n    je np_print_fail\n"
        "    mov rcx, rax\n    mov rdx, QWORD PTR [rsp+48]\n    mov r8, QWORD PTR [rsp+56]\n"
        "    lea r9, [rsp+40]\n    mov QWORD PTR [rsp+32], 0\n    call WriteFile\n"
        "    test eax, eax\n    je np_print_fail\n    xor eax, eax\n    add rsp, 88\n    ret\n"
        "np_print_fail:\n    mov eax, 1\n    add rsp, 88\n    ret\n"
        "neper_io_print ENDP\n\n"
        "neper_trap_bounds PROC\n    lea rcx, np_trap_bounds_text\n    mov edx, 34\n    jmp neper_trap_abort\n"
        "neper_trap_bounds ENDP\n\n"
        "neper_trap_divide PROC\n    lea rcx, np_trap_divide_text\n    mov edx, 31\n    jmp neper_trap_abort\n"
        "neper_trap_divide ENDP\n\n"
        "neper_trap_abort PROC\n    mov r8d, 134\n    jmp neper_stderr_exit\n"
        "neper_trap_abort ENDP\n\n"
        "neper_error_abort PROC\n    mov r8d, 1\n    jmp neper_stderr_exit\n"
        "neper_error_abort ENDP\n\n"
        "neper_stderr_exit PROC FRAME\n"
        "    sub rsp, 88\n    .allocstack 88\n    .endprolog\n"
        "    mov QWORD PTR [rsp+48], rcx\n    mov QWORD PTR [rsp+56], rdx\n    mov QWORD PTR [rsp+64], r8\n"
        "    mov ecx, -12\n    call GetStdHandle\n"
        "    mov rcx, rax\n    mov rdx, QWORD PTR [rsp+48]\n    mov r8, QWORD PTR [rsp+56]\n"
        "    lea r9, [rsp+40]\n    mov QWORD PTR [rsp+32], 0\n    call WriteFile\n"
        "    mov ecx, DWORD PTR [rsp+64]\n    call ExitProcess\n"
        "neper_stderr_exit ENDP\n\n", out);
    fputs(
        "mainCRTStartup PROC FRAME\n"
        "    sub rsp, 232\n    .allocstack 232\n    .endprolog\n"
        "    xor ecx, ecx\n    mov edx, 67108864\n    mov r8d, 3000h\n    mov r9d, 4\n"
        "    call VirtualAlloc\n    test rax, rax\n    je np_start_fail\n"
        "    mov QWORD PTR [rsp+80], rax\n"
        "    call GetCommandLineW\n    mov rcx, rax\n    lea rdx, [rsp+88]\n    call CommandLineToArgvW\n"
        "    test rax, rax\n    je np_start_args_fail\n    mov QWORD PTR [rsp+96], rax\n"
        "    mov eax, DWORD PTR [rsp+88]\n    shl rax, 4\n    mov QWORD PTR [rsp+104], rax\n"
        "    mov QWORD PTR [rsp+112], 0\n"
        "np_win_arg_loop:\n    mov rax, QWORD PTR [rsp+112]\n    cmp eax, DWORD PTR [rsp+88]\n    jae np_win_args_done\n"
        "    mov r10, QWORD PTR [rsp+96]\n    mov r8, QWORD PTR [r10+rax*8]\n    mov QWORD PTR [rsp+144], r8\n"
        "    mov ecx, 65001\n    xor edx, edx\n    mov r9d, -1\n"
        "    mov QWORD PTR [rsp+32], 0\n    mov QWORD PTR [rsp+40], 0\n    mov QWORD PTR [rsp+48], 0\n    mov QWORD PTR [rsp+56], 0\n"
        "    call WideCharToMultiByte\n    test eax, eax\n    jle np_start_args_fail\n"
        "    mov DWORD PTR [rsp+176], eax\n    dec eax\n    mov DWORD PTR [rsp+152], eax\n"
        "    mov r10, QWORD PTR [rsp+104]\n    mov eax, DWORD PTR [rsp+176]\n    add r10, rax\n    cmp r10, 67108864\n    ja np_start_args_fail\n"
        "    mov rax, QWORD PTR [rsp+80]\n    add rax, QWORD PTR [rsp+104]\n    mov QWORD PTR [rsp+160], rax\n"
        "    mov ecx, 65001\n    xor edx, edx\n    mov r8, QWORD PTR [rsp+144]\n    mov r9d, -1\n"
        "    mov QWORD PTR [rsp+32], rax\n    mov eax, DWORD PTR [rsp+176]\n    mov QWORD PTR [rsp+40], rax\n"
        "    mov QWORD PTR [rsp+48], 0\n    mov QWORD PTR [rsp+56], 0\n    call WideCharToMultiByte\n"
        "    test eax, eax\n    jle np_start_args_fail\n"
        "    mov rax, QWORD PTR [rsp+112]\n    shl rax, 4\n    add rax, QWORD PTR [rsp+80]\n"
        "    mov r10, QWORD PTR [rsp+160]\n    mov QWORD PTR [rax], r10\n    mov r10d, DWORD PTR [rsp+152]\n    mov QWORD PTR [rax+8], r10\n"
        "    mov eax, DWORD PTR [rsp+176]\n    add QWORD PTR [rsp+104], rax\n    inc QWORD PTR [rsp+112]\n    jmp np_win_arg_loop\n"
        "np_win_args_done:\n    mov rcx, QWORD PTR [rsp+96]\n    call LocalFree\n"
        "    mov rax, QWORD PTR [rsp+80]\n    mov QWORD PTR [rsp+120], rax\n    mov QWORD PTR [rsp+128], 67108864\n"
        "    mov rax, QWORD PTR [rsp+104]\n    mov QWORD PTR [rsp+136], rax\n"
        "    mov rcx, QWORD PTR [rsp+80]\n    mov edx, DWORD PTR [rsp+88]\n    call neper_os_set_args\n"
        "    lea rcx, [rsp+120]\n    mov rdx, QWORD PTR [rsp+80]\n    mov r8d, DWORD PTR [rsp+88]\n    call neper_main\n"
        "    test eax, eax\n    jne np_main_error\n    xor ecx, ecx\n    call ExitProcess\n"
        "np_main_error:\n    mov ecx, eax\n    call neper_report_error\n"
        "np_start_fail:\n    lea rcx, np_start_text\n    mov edx, 20\n    jmp neper_error_abort\n"
        "np_start_args_fail:\n    lea rcx, np_start_args_text\n    mov edx, 17\n    jmp neper_error_abort\n"
        "mainCRTStartup ENDP\n\n", out);
    fputs("neper_report_error PROC\n", out);
    for (i = 0; i < c->program.error_count; ++i)
        fprintf(out, "    cmp ecx, %d\n    je np_report_error_%d\n",
                c->program.errors[i].code, c->program.errors[i].code);
    fputs("    lea rcx, np_error_text\n    mov edx, 21\n    jmp neper_error_abort\n", out);
    for (i = 0; i < c->program.error_count; ++i) {
        char message[256];
        error_message(c, &c->program.errors[i], message, sizeof(message));
        fprintf(out, "np_report_error_%d:\n    lea rcx, np_error_%d\n    mov edx, %u\n    jmp neper_error_abort\n",
                c->program.errors[i].code, c->program.errors[i].code, (unsigned)strlen(message));
    }
    fputs("neper_report_error ENDP\n\n", out);
}

static void emit_linux_runtime(Compiler *c, FILE *out) {
    int i;
    fputs(
        ".type np_stack_probe, @function\nnp_stack_probe:\n"
        "    lea r10, [rsp+8]\n    mov r11, rax\n"
        "np_stack_probe_page:\n    cmp r11, 4096\n    jbe np_stack_probe_last\n"
        "    sub r10, 4096\n    test BYTE PTR [r10], 0\n    sub r11, 4096\n"
        "    jmp np_stack_probe_page\n"
        "np_stack_probe_last:\n    sub r10, r11\n    test BYTE PTR [r10], 0\n    ret\n"
        ".size np_stack_probe, .-np_stack_probe\n\n"
        ".globl neper_io_print\n.type neper_io_print, @function\nneper_io_print:\n"
        "    mov rdx, rsi\n    mov rsi, rdi\n    mov edi, 1\n    mov eax, 1\n    syscall\n"
        "    test rax, rax\n    js np_print_fail\n    xor eax, eax\n    ret\n"
        "np_print_fail:\n    mov eax, 1\n    ret\n.size neper_io_print, .-neper_io_print\n\n"
        ".type neper_trap_bounds, @function\nneper_trap_bounds:\n"
        "    mov edi, 2\n    lea rsi, np_trap_bounds_text[rip]\n    mov edx, 34\n    jmp neper_trap_abort\n"
        ".size neper_trap_bounds, .-neper_trap_bounds\n\n"
        ".type neper_trap_divide, @function\nneper_trap_divide:\n"
        "    mov edi, 2\n    lea rsi, np_trap_divide_text[rip]\n    mov edx, 31\n"
        "neper_trap_abort:\n    mov eax, 1\n    syscall\n    mov edi, 134\n    mov eax, 60\n    syscall\n\n"
        ".globl _start\n.type _start, @function\n_start:\n"
        "    mov r12, rsp\n    xor edi, edi\n    mov esi, 67108864\n    mov edx, 3\n"
        "    mov r10d, 34\n    mov r8, -1\n    xor r9d, r9d\n    mov eax, 9\n    syscall\n"
        "    test rax, rax\n    js np_start_fail\n"
        "    mov r13, rax\n    mov r14, QWORD PTR [r12]\n    mov rbx, r14\n    shl rbx, 4\n    xor r15d, r15d\n"
        "np_arg_loop:\n    cmp r15, r14\n    jae np_args_done\n"
        "    mov r8, QWORD PTR [r12+r15*8+8]\n    xor ecx, ecx\n"
        "np_arg_len:\n    cmp BYTE PTR [r8+rcx], 0\n    je np_arg_len_done\n    inc rcx\n    jmp np_arg_len\n"
        "np_arg_len_done:\n    lea r9, [r13+rbx]\n    mov r10, r15\n    shl r10, 4\n"
        "    mov QWORD PTR [r13+r10], r9\n    mov QWORD PTR [r13+r10+8], rcx\n"
        "    mov rdx, rcx\n    mov rsi, r8\n    mov rdi, r9\n    rep movsb\n    add rbx, rdx\n    inc r15\n    jmp np_arg_loop\n"
        "np_args_done:\n    mov rdi, r13\n    mov rsi, r14\n    call neper_os_set_args\n    sub rsp, 32\n"
        "    mov QWORD PTR [rsp], r13\n    mov QWORD PTR [rsp+8], 67108864\n    mov QWORD PTR [rsp+16], rbx\n"
        "    mov rdi, rsp\n    mov rsi, r13\n    mov rdx, r14\n    call neper_main\n"
        "    test eax, eax\n    jne np_main_error\n    xor edi, edi\n    jmp np_exit\n"
        "np_main_error:\n    mov ecx, eax\n    jmp neper_report_error\n"
        "np_start_fail:\n    mov edi, 2\n    lea rsi, np_start_text[rip]\n    mov edx, 20\n    mov eax, 1\n    syscall\n    mov edi, 1\n"
        "np_exit:\n    mov eax, 60\n    syscall\n.size _start, .-_start\n\n", out);
    fputs(".type neper_report_error, @function\nneper_report_error:\n", out);
    for (i = 0; i < c->program.error_count; ++i)
        fprintf(out, "    cmp ecx, %d\n    je np_report_error_%d\n",
                c->program.errors[i].code, c->program.errors[i].code);
    fputs("    lea rsi, np_error_text[rip]\n    mov edx, 21\n    jmp np_report_error_write\n", out);
    for (i = 0; i < c->program.error_count; ++i) {
        char message[256];
        error_message(c, &c->program.errors[i], message, sizeof(message));
        fprintf(out, "np_report_error_%d:\n    lea rsi, np_error_%d[rip]\n    mov edx, %u\n    jmp np_report_error_write\n",
                c->program.errors[i].code, c->program.errors[i].code, (unsigned)strlen(message));
    }
    fputs("np_report_error_write:\n    mov edi, 2\n    mov eax, 1\n    syscall\n    mov edi, 1\n    jmp np_exit\n"
          ".size neper_report_error, .-neper_report_error\n\n", out);
}

static int emit_assembly(Compiler *c, const char *path, int windows) {
    FILE *out = fopen(path, "wb");
    Emitter e;
    int i;
    if (!out) { fprintf(stderr, "neper: cannot write %s: %s\n", path, strerror(errno)); return 0; }
    collect_traps(c);
    memset(&e, 0, sizeof(e)); e.compiler = c; e.out = out; e.windows = windows; e.label = 1; e.debug_label = 1;
    if (windows) {
        fputs("option casemap:none\noption dotname\n\n.data\nnp_error_text DB \"error: program.Error\", 10\nnp_start_text DB \"startup: reserve: 0\", 10\nnp_start_args_text DB \"startup: args: 0\", 10\nnp_trap_bounds_text DB \"trap[bounds]: index out of bounds\", 10\nnp_trap_divide_text DB \"trap[divide]: division by zero\", 10\n", out);
    } else {
        fprintf(out, ".intel_syntax noprefix\n.file 1 \"%s\"\n.section .rodata\nnp_error_text: .ascii \"error: program.Error\\n\"\nnp_start_text: .ascii \"startup: reserve: 0\\n\"\nnp_trap_bounds_text: .ascii \"trap[bounds]: index out of bounds\\n\"\nnp_trap_divide_text: .ascii \"trap[divide]: division by zero\\n\"\n", c->source_path);
    }
    for (i = 0; i < c->program.string_count; ++i) {
        Expr *x = c->program.strings[i];
        fprintf(out, "np_str_%d:\n", x->as.string.label);
        emit_bytes(out, x->as.string.bytes, x->as.string.length, windows);
    }
    for (i = 0; i < c->program.error_count; ++i) {
        char message[256];
        error_message(c, &c->program.errors[i], message, sizeof(message));
        fprintf(out, "np_error_%d:\n", c->program.errors[i].code);
        emit_bytes(out, (const unsigned char *)message, strlen(message), windows);
    }
    for (i = 0; i < c->program.trap_site_count; ++i) {
        struct TrapSite *site = &c->program.trap_sites[i];
        fprintf(out, "np_trap_site_%d:\n", i);
        emit_bytes(out, (const unsigned char *)site->message, site->message_length, windows);
    }
    emit_nepersym(c, out, windows);
    fputs(windows ? "np_user_text_start LABEL BYTE\n" : "np_user_text_start:\n", out);
    for (i = 0; i < c->program.function_count; ++i)
        if (!c->program.functions[i].is_template && !c->program.functions[i].is_intrinsic)
            emit_function(&e, &c->program.functions[i]);
    fputs(windows ? "np_user_text_end LABEL BYTE\n" : "np_user_text_end:\n", out);
    if (windows) { emit_windows_runtime(c, out); emit_windows_codeview(c, out); fputs("END\n", out); }
    else {
        emit_linux_runtime(c, out);
        emit_linux_debug(c, out);
        fputs(".section .note.GNU-stack,\"\",@progbits\n", out);
    }
    fclose(out);
    return 1;
}

static int command_status(const char *command) {
    int rc = system(command);
#ifndef _WIN32
    if (rc != -1 && WIFEXITED(rc)) rc = WEXITSTATUS(rc);
#endif
    return rc;
}

#ifndef _WIN32
static int run_argv(char *const argv[]) {
    pid_t child = fork();
    int status;
    if (child == 0) { execvp(argv[0], argv); _exit(127); }
    if (child < 0 || waitpid(child, &status, 0) < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}
#else
static int run_argv(char *const argv[]) { (void)argv; return -1; }
#endif

static void quote_arg(char *dst, size_t cap, const char *arg) {
    size_t n = 0; const char *p;
    if (cap == 0) return;
    dst[n++] = '"';
    for (p = arg; *p && n + 2 < cap; ++p) {
        if (*p == '"') dst[n++] = '\\';
        dst[n++] = *p;
    }
    if (n + 1 < cap) dst[n++] = '"';
    dst[n] = 0;
}

#ifdef _WIN32
static char *utf8_from_wide(const wchar_t *source) {
    int size = WideCharToMultiByte(CP_UTF8, 0, source, -1, 0, 0, 0, 0);
    char *result;
    if (size <= 0) return 0;
    result = (char *)malloc((size_t)size);
    if (!result || WideCharToMultiByte(CP_UTF8, 0, source, -1, result, size, 0, 0) <= 0) {
        free(result); return 0;
    }
    return result;
}

static wchar_t *wide_from_utf8(const char *source) {
    int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source, -1, 0, 0);
    wchar_t *result;
    if (size <= 0) return 0;
    result = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
    if (!result || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source, -1, result, size) <= 0) {
        free(result); return 0;
    }
    return result;
}

static wchar_t *quote_wide_arg(const wchar_t *source) {
    size_t n = wcslen(source), i, out = 0;
    wchar_t *result = (wchar_t *)malloc((n * 2 + 3) * sizeof(wchar_t));
    if (!result) return 0;
    result[out++] = L'"';
    for (i = 0; i < n; ++i) {
        if (source[i] == L'"') result[out++] = L'\\';
        result[out++] = source[i];
    }
    result[out++] = L'"'; result[out] = 0;
    return result;
}
#endif

static void replace_extension(char *out, size_t cap, const char *path, const char *ext) {
    const char *slash1 = strrchr(path, '/'), *slash2 = strrchr(path, '\\'), *dot = strrchr(path, '.');
    const char *slash = slash1 > slash2 ? slash1 : slash2;
    size_t base = (dot && (!slash || dot > slash)) ? (size_t)(dot - path) : strlen(path);
    if (base + strlen(ext) + 1 > cap) base = cap - strlen(ext) - 1;
    memcpy(out, path, base); strcpy(out + base, ext);
}

#ifdef _WIN32
static uint16_t read_u16_le(const unsigned char *p) {
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t read_u32_le(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
#endif

static int patch_codeview_section_relocations(const char *path) {
#ifdef _WIN32
    FILE *file = fopen(path, "r+b");
    unsigned char *data;
    long file_size;
    uint16_t section_count, optional_size;
    size_t section_table, section_index;
    int patched = 0;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (file_size = ftell(file)) < 20 || fseek(file, 0, SEEK_SET) != 0) {
        if (file) fclose(file); return 0;
    }
    data = (unsigned char *)malloc((size_t)file_size);
    if (!data || fread(data, 1, (size_t)file_size, file) != (size_t)file_size) {
        free(data); fclose(file); return 0;
    }
    section_count = read_u16_le(data + 2);
    optional_size = read_u16_le(data + 16);
    section_table = 20 + optional_size;
    if (section_table + (size_t)section_count * 40 > (size_t)file_size) { free(data); fclose(file); return 0; }
    for (section_index = 0; section_index < section_count; ++section_index) {
        unsigned char *section = data + section_table + section_index * 40;
        uint32_t reloc_offset;
        uint16_t reloc_count;
        size_t i;
        if (memcmp(section, ".debug$S", 8) != 0) continue;
        reloc_offset = read_u32_le(section + 24);
        reloc_count = read_u16_le(section + 32);
        if ((size_t)reloc_offset + (size_t)reloc_count * 10 > (size_t)file_size) continue;
        for (i = 0; i + 1 < reloc_count; ++i) {
            unsigned char *first = data + reloc_offset + i * 10;
            unsigned char *second = first + 10;
            if (read_u16_le(first + 8) == 0x000b && read_u16_le(second + 8) == 0x000b &&
                read_u32_le(second) == read_u32_le(first) + 4 &&
                read_u32_le(second + 4) == read_u32_le(first + 4)) {
                second[8] = 0x0a; second[9] = 0; patched++; i++;
            }
        }
    }
    if (patched == 0 || fseek(file, 0, SEEK_SET) != 0 || fwrite(data, 1, (size_t)file_size, file) != (size_t)file_size) {
        free(data); fclose(file); return 0;
    }
    free(data); fclose(file); return 1;
#else
    (void)path; return 1;
#endif
}

static int assemble_and_link(Compiler *c, const char *asm_path, const char *obj_path,
                             const char *exe_path, int windows) {
    char qa[MAX_PATH_LEN * 2], qo[MAX_PATH_LEN * 2], qe[MAX_PATH_LEN * 2];
    char runtime[MAX_PATH_LEN], qr[MAX_PATH_LEN * 2], command[MAX_PATH_LEN * 12];
    quote_arg(qa, sizeof(qa), asm_path); quote_arg(qo, sizeof(qo), obj_path); quote_arg(qe, sizeof(qe), exe_path);
    if (strlen(c->executable_dir) + 20 >= sizeof(runtime)) {
        fputs("neper: error[E-LINK-9999]: compiler path is too long for the intrinsic runtime\n", stderr);
        return 0;
    }
    strcpy(runtime, c->executable_dir);
    {
        size_t used = strlen(runtime);
        runtime[used++] = PATH_SEP;
        strcpy(runtime + used, windows ? "neper_runtime.obj" : "neper_runtime.o");
    }
    slash_path(runtime);
    if (!path_exists(runtime)) {
        fprintf(stderr, "neper: error[E-LINK-9999]: intrinsic runtime object not found at `%s`\n", runtime);
        return 0;
    }
    quote_arg(qr, sizeof(qr), runtime);
    if (windows) {
        const char *devcmd = getenv("NEPER_VSDEVCMD");
        char qd[MAX_PATH_LEN * 2], batch[MAX_PATH_LEN], qb[MAX_PATH_LEN * 2];
        FILE *f;
        if (!devcmd) devcmd = "D:\\VS\\Community\\Common7\\Tools\\VsDevCmd.bat";
        if (!path_exists(devcmd)) {
            fputs("neper: error[E-LINK-9999]: set NEPER_VSDEVCMD to Visual Studio's VsDevCmd.bat\n", stderr);
            return 0;
        }
        replace_extension(batch, sizeof(batch), asm_path, ".link.bat");
        f = fopen(batch, "wb");
        if (!f) return 0;
        quote_arg(qd, sizeof(qd), devcmd);
        fprintf(f, "@echo off\r\ncall %s -arch=x64 -host_arch=x64 >nul\r\n", qd);
        fprintf(f, "ml64 /nologo /c /Fo%s %s >nul || exit /b 1\r\n", qo, qa);
        fclose(f);
        quote_arg(qb, sizeof(qb), batch);
        snprintf(command, sizeof(command), "cmd.exe /d /c %s", qb);
        if (command_status(command) != 0) return 0;
        if (!patch_codeview_section_relocations(obj_path)) {
            fputs("neper: error[E-LINK-9999]: could not finalize CodeView relocations\n", stderr);
            return 0;
        }
        f = fopen(batch, "wb");
        if (!f) return 0;
        fprintf(f, "@echo off\r\ncall %s -arch=x64 -host_arch=x64 >nul\r\n", qd);
        fprintf(f, "link /nologo /debug:full /include:np_nepersym /subsystem:console /entry:mainCRTStartup /out:%s %s %s kernel32.lib shell32.lib >nul || exit /b 1\r\n", qe, qo, qr);
        fclose(f);
        if (command_status(command) != 0) return 0;
        remove(batch);
    } else {
        char *as_args[] = {"as", "--64", "-o", (char *)obj_path, (char *)asm_path, 0};
        char *link_args[] = {"cc", "-nostartfiles", "-no-pie", "-o", (char *)exe_path,
                             (char *)obj_path, runtime, 0};
        if (run_argv(as_args) != 0 || run_argv(link_args) != 0) return 0;
    }
    return 1;
}

static char *read_file(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb"); long size; char *data;
    if (!f) return 0;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return 0; }
    size = ftell(f); if (size < 0) { fclose(f); return 0; }
    rewind(f); data = (char *)malloc((size_t)size + 1);
    if (!data) { fclose(f); return 0; }
    if (fread(data, 1, (size_t)size, f) != (size_t)size) { free(data); fclose(f); return 0; }
    data[size] = 0; fclose(f); *length = (size_t)size; return data;
}

static void absolute_source_path(char *out, size_t capacity, const char *path) {
#ifdef _WIN32
    if (_fullpath(out, path, capacity)) return;
#else
    if (realpath(path, out)) return;
#endif
    if (path[0] == '/' || (strlen(path) > 2 && path[1] == ':'))
        copy_text(out, capacity, path, strlen(path));
    else {
        char cwd[MAX_PATH_LEN];
        if (!getcwd(cwd, sizeof(cwd))) strcpy(cwd, ".");
        snprintf(out, capacity, "%s%c%s", cwd, PATH_SEP, path);
    }
    slash_path(out);
}

static void parent_directory(char *path) {
    char *a = strrchr(path, '/'), *b = strrchr(path, '\\');
    char *slash = a > b ? a : b;
    if (slash) *slash = 0;
}

static void find_project_root(Compiler *c, const char *absolute_source) {
    char directory[MAX_PATH_LEN], lib_path[MAX_PATH_LEN], src_path[MAX_PATH_LEN];
    copy_text(directory, sizeof(directory), absolute_source, strlen(absolute_source));
    parent_directory(directory);
    for (;;) {
        char previous[MAX_PATH_LEN];
        copy_text(lib_path, sizeof(lib_path), directory, strlen(directory));
        append_character(lib_path, sizeof(lib_path), PATH_SEP);
        append_text(lib_path, sizeof(lib_path), "lib");
        copy_text(src_path, sizeof(src_path), directory, strlen(directory));
        append_character(src_path, sizeof(src_path), PATH_SEP);
        append_text(src_path, sizeof(src_path), "src");
        if (directory_exists(lib_path) || directory_exists(src_path)) break;
        copy_text(previous, sizeof(previous), directory, strlen(directory));
        parent_directory(directory);
        if (!directory[0] || strcmp(previous, directory) == 0) {
            copy_text(directory, sizeof(directory), absolute_source, strlen(absolute_source));
            parent_directory(directory);
            break;
        }
    }
    copy_text(c->project_root, sizeof(c->project_root), directory, strlen(directory));
}

static void executable_directory(char *out, size_t cap, const char *argv0) {
    char full[MAX_PATH_LEN];
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(0, full, (DWORD)sizeof(full));
    if (n == 0 || n >= sizeof(full)) copy_text(full, sizeof(full), argv0, strlen(argv0));
#else
    ssize_t n = readlink("/proc/self/exe", full, sizeof(full) - 1);
    if (n > 0) full[n] = 0; else copy_text(full, sizeof(full), argv0, strlen(argv0));
#endif
    {
        char *a = strrchr(full, '/'), *b = strrchr(full, '\\'), *slash = a > b ? a : b;
        if (slash) *slash = 0; else strcpy(full, ".");
    }
    copy_text(out, cap, full, strlen(full));
}

static void usage(void) {
    fputs("neper " NEPER_VERSION "\n"
          "usage:\n"
          "  neper build <file.e> [--output FILE] [--emit-asm FILE]\n"
          "  neper run <file.e> [-- ARGS...]\n"
          "  neper --version\n", stderr);
}

#ifdef _WIN32
int wmain(int argc, wchar_t **wide_argv) {
    char **argv;
#else
int main(int argc, char **argv) {
#endif
    static Compiler c;
    const char *command, *source_path, *output = 0, *asm_output = 0;
    char absolute_source[MAX_PATH_LEN];
    char asm_path[MAX_PATH_LEN], obj_path[MAX_PATH_LEN], exe_path[MAX_PATH_LEN];
    int i, do_run, windows, run_arg_start = argc;
#ifdef _WIN32
    argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    if (!argv) { fputs("neper: out of memory\n", stderr); return 2; }
    for (i = 0; i < argc; ++i) {
        argv[i] = utf8_from_wide(wide_argv[i]);
        if (!argv[i]) { fputs("neper: cannot decode command line as UTF-8\n", stderr); return 2; }
    }
#endif
    memset(&c, 0, sizeof(c));
    if (argc == 2 && strcmp(argv[1], "--version") == 0) { puts(NEPER_VERSION); return 0; }
    if (argc < 3) { usage(); return 2; }
    command = argv[1]; source_path = argv[2];
    do_run = strcmp(command, "run") == 0;
    if (!do_run && strcmp(command, "build") != 0) { usage(); return 2; }
    for (i = 3; i < argc; ++i) {
        if (strcmp(argv[i], "--") == 0) { run_arg_start = i + 1; break; }
        if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) output = argv[++i];
        else if (strcmp(argv[i], "--emit-asm") == 0 && i + 1 < argc) asm_output = argv[++i];
        else { fprintf(stderr, "neper: error[E-CLI-9999]: unknown option `%s`\n", argv[i]); return 2; }
    }
    absolute_source_path(absolute_source, sizeof(absolute_source), source_path);
    c.source_path = absolute_source;
    c.source = read_file(absolute_source, &c.source_length);
    if (!c.source) { fprintf(stderr, "neper: error[E-CLI-9999]: cannot read `%s`\n", source_path); return 2; }
    executable_directory(c.executable_dir, sizeof(c.executable_dir), argv[0]);
    find_project_root(&c, absolute_source);
    c.source_count = 1;
    c.root_source_id = 0;
    copy_text(c.sources[0].path, sizeof(c.sources[0].path), absolute_source,
              strlen(absolute_source));
    strcpy(c.sources[0].module, "<root>");
    c.sources[0].text = c.source;
    c.sources[0].length = c.source_length;
    parse_source_file(&c, 0, 1);
    if (!c.errors) load_imports(&c);
    if (!c.errors) check_module_cycles(&c);
    c.source_path = c.sources[c.root_source_id].path;
    c.source = c.sources[c.root_source_id].text;
    c.source_length = c.sources[c.root_source_id].length;
    c.current_source_id = c.root_source_id;
    if (!c.errors) check_program(&c);
    if (c.errors) { print_diagnostics(&c); return 1; }
#ifdef _WIN32
    windows = 1;
#else
    windows = 0;
#endif
    if (output) copy_text(exe_path, sizeof(exe_path), output, strlen(output));
    else replace_extension(exe_path, sizeof(exe_path), source_path, windows ? ".exe" : "");
    if (asm_output) copy_text(asm_path, sizeof(asm_path), asm_output, strlen(asm_output));
    else replace_extension(asm_path, sizeof(asm_path), exe_path, windows ? ".asm" : ".s");
    replace_extension(obj_path, sizeof(obj_path), exe_path, windows ? ".obj" : ".o");
    slash_path(asm_path); slash_path(obj_path); slash_path(exe_path);
    if (!emit_assembly(&c, asm_path, windows)) return 2;
    if (!assemble_and_link(&c, asm_path, obj_path, exe_path, windows)) {
        fprintf(stderr, "neper: error[E-LINK-9999]: assembler or system linker failed\n");
        return 1;
    }
    if (do_run) {
#ifdef _WIN32
        int child_count = argc - run_arg_start + 1;
        wchar_t **child_argv = (wchar_t **)calloc((size_t)child_count + 1, sizeof(wchar_t *));
        wchar_t *wide_exe = wide_from_utf8(exe_path);
        int k;
        intptr_t status;
        if (!child_argv || !wide_exe) { fputs("neper: out of memory\n", stderr); return 2; }
        for (k = 0; k < child_count; ++k) {
            const wchar_t *original = k == 0 ? wide_exe : wide_argv[run_arg_start + k - 1];
            child_argv[k] = quote_wide_arg(original);
            if (!child_argv[k]) { fputs("neper: out of memory\n", stderr); return 2; }
        }
        status = _wspawnv(_P_WAIT, wide_exe, (const wchar_t * const *)child_argv);
        for (k = 0; k < child_count; ++k) free(child_argv[k]);
        free(child_argv); free(wide_exe);
        if (status < 0) {
            fprintf(stderr, "neper: error[E-CLI-9999]: cannot run `%s`: %s\n", exe_path, strerror(errno));
            return 2;
        }
        return (int)status;
#else
        int child_count = argc - run_arg_start + 1;
        char **child_argv = (char **)calloc((size_t)child_count + 1, sizeof(char *));
        pid_t child;
        int status;
        if (!child_argv) { fputs("neper: out of memory\n", stderr); return 2; }
        child_argv[0] = exe_path;
        for (i = run_arg_start; i < argc; ++i) child_argv[i - run_arg_start + 1] = argv[i];
        child = fork();
        if (child == 0) {
            execv(exe_path, child_argv);
            fprintf(stderr, "neper: error[E-CLI-9999]: cannot run `%s`: %s\n", exe_path, strerror(errno));
            _exit(127);
        }
        free(child_argv);
        if (child < 0 || waitpid(child, &status, 0) < 0) {
            fprintf(stderr, "neper: error[E-CLI-9999]: cannot run `%s`: %s\n", exe_path, strerror(errno));
            return 2;
        }
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        return 2;
#endif
    }
    puts(exe_path);
    return 0;
}
