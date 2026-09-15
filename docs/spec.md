# The neper language — specification (draft 0.1)

Status: design draft. Implementation coverage is tracked milestone by milestone in
[`roadmap.md`](roadmap.md); implemented subsets do not imply full conformance.

The post-M2 design revision is scheduled in
[`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) as the mandatory M2.5 gate
before M3. Its ownership, lifetime, check-policy and tooling proposals do not change
the current rules below until versioned normative amendments land during M2.5.

Neper is a compact, ahead-of-time general-purpose language for model-generated
software, with explicit memory, deterministic semantics, inexpensive abstraction,
native interoperability, and first-class CPU/GPU execution.

---

## 1. What neper is

A small procedural language, designed from the start to be **written by language
models and read by people**. Records, structs and unions live on the stack. Memory
comes from arenas you create explicitly. Code compiles straight to machine code for
CPUs and to SPIR-V/PTX for GPUs, with no LLVM in the path.

### Who writes neper

The expected author is a model; the expected reader is a human reviewing what that
model produced, or a tool searching and amending it. neper is meant to be read
fluently and audited quickly. It is **not** optimised for being typed by hand all
day, and that trade is deliberate rather than incidental.

The consequence runs through every decision in this document: **where verbosity buys
unambiguity, verbosity wins.** Explicit casts, qualified call sites, no overloading,
no macros, one definition per name — each costs keystrokes and each removes a
question the reviewer would otherwise have to answer by reading more code. Keystrokes
are spent by a generator; ambiguity is paid for by the reviewer and by the next model
to touch the file. They are not the same currency.

### Goals

1. **Built for generated code** — every construct is unambiguous to produce, to
   search, to amend in place, to debug and to test (§14). A model should not be able
   to write a line whose meaning depends on context it cannot see.
2. **Readable by a human reviewer** — no hidden control flow, no implicit
   allocation, no invisible conversions. What is on the page is what runs.
3. **Outstanding execution speed** — direct control over layout and SIMD, and a
   direct emitter.
4. **Outstanding compile speed** — target: 1M+ lines/sec/core, whole-project rebuild
   in well under a second. Generated code is regenerated often; a slow compiler taxes
   every iteration.
5. **One language, CPU and GPU** — the same syntax, with a restricted GPU profile.
6. **Easy to debug and test** — checks on in debug builds, precise machine-readable
   diagnostics, built-in testing (§13), GPU kernels runnable on the CPU.

### Non-goals

No classes, inheritance, interfaces, closures, exceptions, garbage collection,
operator overloading, function overloading, textual macros, RTTI, or implicit
numeric conversions. Each of these either costs performance, costs compile time, or
makes a name ambiguous to a grep.

Also a non-goal: **terseness for the typist.** Shorthand that saves a human
keystrokes at the cost of a reader's certainty is a bad trade here, because the
typist is not the constraint.

### The name

A neper (Np) is the natural-log unit of ratio — the quiet sibling of the bel.
Fitting for a language about amplification with nothing wasted.

---

## 2. Files and modules

- Source files use the extension `.e`.
- **One file is one module.** The path below its **source root** is the module
  name, `/` becoming `.`: `lib/e/mem.e` is module `e.mem`, `src/main.e` is
  module `main`, `src/parse/expr.e` is `parse.expr`. The source roots are exactly
  `lib/` and `src/` under the project root; a file elsewhere is not a module unless
  it is the one named to `neper run` or `neper build` (below). A per-target suffix
  (§6) is not part of the name.
- A file that declares `fn main` is a **program root** when it is the file named to
  `neper run` or `neper build`. `neper run <file.e>` (§13)
  takes one; `neper build <file.e>` takes one or any other `.e` file, and compiles a
  file without `main` — `examples/vec3.e`, `examples/list.e` — together with the
  modules it reaches to `.em` files and no executable. The named file is a module
  whether or not it lies under a source root: under one it is named from that root
  as any module is; elsewhere its bare filename is its module name, so
  `examples/hello.e` is module `hello`, `examples/` need not be a package, and a
  program root may be run from any directory. A program root is the **root
  module** of the executable it produces and holds `main`. `main` is special only
  there: in any other module a `fn main` is an ordinary function — any signature,
  called and qualified like any other, `lex.main` — and nothing about it is checked
  or run unless that module is the one named on the command line. The root that
  `neper test` synthesises (§13) reaches the module under test through a
  compiler-internal name that appears in no source file and is exempt from the
  import-name rule below — generated code is not subject to source-level
  invariants — which is also how a module named `main` is tested.
- The **project root** is the nearest ancestor directory of the named file — or,
  for a command that names no file (`neper fmt`, `neper test`, `neper index`, §13),
  of the working directory — that contains a `lib/` or a `src/`; when none does, it
  is the file's own directory or the working directory, and the project has no
  modules of its own. The toolchain's own `lib/`, beside the `neper` binary, is a
  third source root on every command: it is where `e.*` lives, which is how
  `use e.mem` resolves from any directory. A module name is looked up under the
  project's `lib/` and `src/` first and under the toolchain's `lib/` only when
  neither defines it, so a project's `lib/e/mem.e` replaces the toolchain's
  `e.mem` — which is how `lib/e` is built and tested in place: from the
  repository, `neper test` runs the tests of every module under the project's two
  roots, `e.*` among them. A module defined under both project roots —
  `lib/x.e` and `src/x.e` — is a compile error naming both files.
- There is no `module` declaration. The filename is the single source of truth, so
  a glob locates any module without reading a byte of it.
- There are no headers, no forward declarations, and no separate interface files.
  Module scope is order-independent: a declaration may be inserted anywhere.

### Imports

```
use e.mem
use e.io
use vendor.collections.map as vendor_map
```

`use` binds the **last segment** as the qualifier unless an explicit alias is
written. Every cross-module reference is qualified at the point of use:

```
var a = mem.arena_from(buf)
let item = vendor_map.get(...)
```

There are no wildcard imports. An alias is written `use <module> as <qualifier>`, is
local to that importing module, must be `snake_case`, and may not equal another
qualifier or any value/function/error name there. A qualifier may equal a type name,
because those are separate position-selected namespaces (below). If two imported modules would bind the same
last segment, at least one must be aliased. Thus every written qualifier still means
exactly one module while independently generated dependencies do not have to
coordinate their final path segments across the ecosystem. `neper fmt` preserves an
explicit alias even when it equals the default qualifier: source generators may use
that form to make their naming policy explicit.

**The `use` graph is a DAG.** A cycle — `a` uses `b` and `b` uses `a`, directly or
through any number of modules — is a compile error naming every module in the
cycle. Nothing is gained by allowing one: module scope is order-independent within
a file, but a module's interface (§12, §15) is built from the interfaces of the
modules it uses, and a cycle has no first module to build.

A qualifier is a module-scope value-namespace name and falls under §14 invariant 1:
a local, parameter, function, value or error declaration that reuses it is a compile error, so
`mem.alloc[u8](a, n)` can never be a call through a field of some local named `mem`.
Module qualifiers and type names are separate namespaces resolved by position — `str`
the qualifier in `str.eq(x, y)` and `str` the type in `name: str` coexist (§4) — and
the builtin `target` namespace (§6) is reserved the same way as a qualifier.

A name before a `.` is resolved in a fixed order: as a `use` qualifier first, then
as a type — `u8.trunc(x)` (§4), `Node.Tag` (§4), `Kind.Int` (§4) — then as a comptime
type parameter or a comptime type value, whose protocol function is looked up at the
instantiation (`T.hash(v)`, §9), then as a value whose field is named. A protocol
receiver need not be a name at all: any expression whose type is `type` and whose
value is comptime-known stands in that position, `f.ty.format(x, b)` (§9). The order
can never be ambiguous: the first three sets are disjoint, and a name in the
fourth is a type value only when its type is `type`, which has no fields. A
qualifier cannot be redeclared (above); a comptime type parameter is a parameter, so
§5 forbids it from reusing a module-scope type name, a `use` qualifier or a builtin
type name; and the **builtin type names** — the
primitive type names of §4, `Vec`, `Mask` and `Atomic` — are reserved: a `type`,
`fn`, `const`, `var`, parameter or local reusing one is a compile error, and no
module may be named after one. An alias is not reserved: `str` is an alias (§4),
which is why `e.str` is a legal module.

---

## 3. Lexical structure

The normative token and concrete-syntax grammar is
[`grammar.ebnf`](grammar.ebnf). This section explains its consequences; where an
example and the grammar disagree, the grammar controls concrete syntax and this
document controls typing and semantics. A conforming implementation publishes the
grammar revision it accepts through `neper info --json` (§13).

- A source file is valid UTF-8. One leading UTF-8 BOM is accepted and ignored;
  `neper fmt` removes it. Before tokenization, CRLF and bare CR are normalized to LF.
  NUL is always a source error. Every other ASCII control character except LF and
  TAB is forbidden everywhere; normal strings and characters represent controls only
  with the escapes below. TAB is permitted as data inside a raw string or comment,
  but outside a literal or comment it is an error rather than indentation whose width
  differs by tool. Horizontal source whitespace is otherwise ASCII space only. Line
  numbers count normalized LF-separated lines from one.
- Tokens use **longest match**. In particular `...` precedes `..` and `.`, `<<` and
  `>>` precede `<` and `>`, and the wrapping operators `+%`, `-%`, `*%` are single
  tokens. A numeric suffix is part of its literal token and may have no intervening
  whitespace. `1..2` is the three tokens `1`, `..`, `2`; a decimal float therefore
  requires digits on both sides of its dot. A leading sign is always a separate
  prefix token.
- Comments: `//` to end of line. No block comments (they break line-oriented edits).
  A consecutive run of `///` lines immediately before a declaration, field or member
  at the same indentation is its documentation; one optional space after `///` is
  removed and the lines join with LF. A blank line or ordinary `//` breaks attachment.
  Documentation is returned by `neper index`, so API-reading tools do not infer it
  from nearby trivia.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`. Case-sensitive. `_` alone is reserved and
  is not an identifier: it is the discard in a `let` (§5) and the inferred
  length in an array literal (§4), and it can be neither declared nor referenced.
- Integer literals: `123`, `0xFF`, `0b1010`, `0o777`, `1_000_000`, with an optional
  type suffix: `42u64`, `3i32`, `255u8`, `1usize`.
- Float literals: `1.5`, `1e-9`, with an optional type suffix: `1.5f32`, `2.0f64`,
  `1.0f16`, `1.0bf16`.
- Source is UTF-8. String literals: `"..."` with the escapes `\n \t \r \\ \" \' \0
  \xNN`; the bytes between the quotes are stored as written, so a non-ASCII
  character is its UTF-8 sequence. A string literal is a `[]const u8` pointing at
  read-only data. No null terminator unless written.
- A raw string is `r"..."` or `r#"..."#` through eight `#` characters. It has no
  escapes, may contain normalized newlines, and ends only at `"` followed by the
  same number of `#` characters. Its value is the UTF-8 bytes between the delimiters
  and its type is `[]const u8`. `neper fmt` chooses the smallest delimiter count that
  leaves the bytes unchanged, so generated JSON, regular expressions and source text
  need no escape-heavy construction. A raw string cannot serve where a rule
  specifically requires a one-line string literal, such as `@import` or
  `unreachable`'s optional message.
- Character literals: `'a'` is a `u8`. It takes the string escapes — `'\''`,
  `'\n'`, `'\xNN'` — and must denote exactly one byte, so a non-ASCII character
  between the quotes is a compile error; write its bytes with `\xNN`.
- The tokenizer emits every normalized newline as a `NEWLINE` token. The parser
  treats a `NEWLINE` inside an unclosed
  `(` or `[`, inside the `{ }` of a **literal** — a struct, `union`, array, `union
  enum` or `Vec` literal, whose `{` follows a type name — or inside the `{ }` of a
  **type body** — the `{` after `struct`, `union`, `enum T` or `union enum T` in a
  `type` declaration — is whitespace: that is how a call, a literal, a signature or
  a type declaration continues across lines, and it is the only place `neper fmt`
  breaks a line — at 100 columns, one element per line (§14). The `{` that opens a **block** — after a signature,
  `if`, `else`, `while`, `for`, `switch`, `when`, `defer` (its block form, §6) or
  `@nocheck` — does not
  suspend the rule: every newline inside a block ends a statement. A newline
  anywhere else ends the statement; there is no backslash continuation.
- **No continuation crosses a declaration.** A `(`, `[`, or a literal's or type
  body's `{` that is still open when a column-0 declaration keyword is reached —
  `use`, `type`, `const`, `var`, `fn`, `error`, `extern`, or an attribute line
  (§5) — is a compile error, reported at the **opening** bracket and naming the
  keyword that ended it:

  ```
  src/parse.e:312:24: error[E-SYNTAX-0012]: `(` opened here is still unclosed at `fn` on line 318
  ```

  §14 invariant 2 guarantees nothing else begins a line at column 0, so the parser
  has a barrier it can trust: one dropped bracket costs one precise diagnostic
  instead of a cascade that reinterprets the rest of the file. It is the failure
  every implicit-continuation language has, and the invariant that makes `^fn`
  greps exact is what removes it here.
- **No continuation crosses its containing block.** A soft delimiter opened inside
  a block that remains open when the `}` closing that block is reached produces one
  error at the opening delimiter; the parser then resumes after that `}`. In a
  `switch`, `case` and `default` at the switch body's brace depth are additional
  barriers. Recovery affects only which later diagnostics are suppressed, never
  whether an otherwise valid program is accepted. The conformance corpus (§13)
  fixes the required primary diagnostic and recovery point for every delimiter.
- Blocks use `{ }`. Braces are required — there is no single-statement `if`.

### Literals, indices and ranges

An unsuffixed integer or float literal is an **untyped compile-time value**. It takes
the type its immediate context demands — the other operand of a binary operator
(except a shift count, §6), the parameter it is passed to, the field or element it
initialises, the annotation on its binding, the declared return type where it stands
after `ret`, the subject's type where it stands as a `switch` case label, the left
side's type where it stands on the right of a compound assignment (`x += 1`), the
comptime parameter it is bound to in a `[...]` argument, or the
parameter type a checked comptime signature (§9) supplies — and the value must be
representable in that type, or it is a compile error. With no context there is no default: `let x = 3` and `const N =
4096` are compile errors, not `i32`. Write the annotation or the suffix: `let x: i32
= 3`, `let x = 3i32`. A suffixed literal has its suffix's type and supplies context
to whatever it meets. An expression built only from untyped literals and operators —
`64*1024` — is itself an untyped compile-time value: it is folded exactly, at
unbounded precision, and takes its type from context exactly as a single literal
does, so `[64*1024]u8` is well-typed because an array length is `usize` context.
An array length is an expression that must have type `usize` once its literals are
typed: `[N*2]u8` is well-typed with `const N: usize` and a compile error with
`const N: u32`, since nothing widens it (§4).

| Expression | Type |
|---|---|
| `s[i]` on a slice or array | the index `i` is `usize` |
| `s.len` | `usize` |
| `a..b` | the type of its bounds, which must agree after literal typing; two untyped bounds are a compile error |
| `for i in a..b` | `i` has the range's type |
| `for i, v in s` | `i` is `usize` |
| `gpu.gid`, `gpu.lid`, `gpu.wgid` fields (`.x .y .z`) | `u32` (§10) |

So `for i in 0..n` with `n: usize` is well-typed, `for i in 0..1000` is not (write
`0usize..1000` or `0i32..1000`), and indexing a slice with a `u32` invocation id needs
`usize(i)` written down. Under §11 the width of an expression decides where it wraps,
so the type of every literal has to be legible from the line it appears on and the
one signature that line calls — never from anything further away (D27).

### Keywords

```
use type const var let fn ret if else while for in switch case default
break continue defer try struct union enum error when true false nil ok
as zero undef extern unreachable shared
```

`unreachable` is a keyword because `unreachable()` is a builtin that needs no `use`
and cannot be redeclared (§11). `shared` is a keyword because `shared var` is a
statement and `[]shared T` a type, both legal only in device code (§10).

### Naming

Naming is part of the language, not a style guide. `neper fmt --check` rejects a
violation the same way it rejects bad indentation. The point is predictability: if
you know something is a function, you know how it is spelled, so `grep "^fn parse_"`
finds every parser entry point without guessing at casing.

| Kind | Convention | Example |
|---|---|---|
| Functions | `snake_case` | `parse_expr`, `is_power_of_two` |
| Variables, parameters, fields | `snake_case` | `node_count`, `arena` |
| Modules and files | `snake_case` | `e/map.e` |
| Types | `PascalCase` | `Vec3`, `Arena`, `HashMap` |
| Enum members | `PascalCase` | `.Float`, `.NotStarted` |
| Errors | `PascalCase` | `error NotFound` |
| Constants (`const`) | `SCREAMING_SNAKE` | `MAX_NODES` |
| Comptime parameters of kind `type` or `fn` (§9) | `PascalCase` | `T`, `Ctx`, `K` |
| Comptime parameters of a value kind — an integer, `str`, `bool`, an array, a comptime-only struct value (§9) | `SCREAMING_SNAKE` | `N`, `FMT`, `IDX`, `FIELD` |
| Comptime binding from an unrolled `for` (§9) | `snake_case` | `f` in `for f in meta.fields[T]()` |

Casing therefore tells you the kind of a name on sight, with no lookup: `Foo` is a
type, an error or a type-kind comptime parameter, `FOO` is a constant or a
value-kind one, `foo` is a function or a value. The `SCREAMING_SNAKE` rule covers
comptime **parameters** only: the binding an unrolled comptime `for` introduces (§9)
is a local binding like any other and is spelled like one, even though its value is
known at compile time.

---

## 4. Types

### Primitives

| Category | Types |
|---|---|
| Signed | `i8` `i16` `i32` `i64` `isize` |
| Unsigned | `u8` `u16` `u32` `u64` `usize` |
| Float | `f16` `bf16` `f32` `f64` |
| Other | `bool` `void` `err` `type` |

### Aliases

`str` is an alias for `[]const u8` — not a primitive, and not a distinct type: there
is no string type, and `str` is not a reserved name (§2). It is the alias form of
`type` (Composites, below) applied by the language itself.

### Narrow floats

`f16` is IEEE 754 binary16; `bf16` is bfloat16 — same exponent range as `f32`, eight
bits of significand precision. Both are **storage types first**: they halve memory
traffic, which is usually the point. Arithmetic on them is defined as *convert the
operands to `f32`, perform the named `f32` operation, then round once to the narrow
type after every operation*. This widen-operate-narrow sequence is the language
result, including for division and square root; it is deterministic across targets
but is not claimed to equal a hypothetical directly-rounded native narrow operation
in the double-rounding edge cases.

Where a target has native narrow arithmetic, the emitter may use it only when that
instruction is proven to implement the same widen-operate-narrow result; otherwise it
widens, operates and narrows explicitly. `bf16` therefore computes via `f32` on
SPIR-V and, despite native instructions from `sm_80`, uses only instructions or a
sequence that preserves these semantics on PTX. §13 lists available instructions;
availability alone never changes the language result.

There is no implicit conversion between any two float widths (No implicit
conversions, below). `f32(h)` and `f16(x)` are written down like every other cast.

### No implicit conversions

**No implicit conversions**, not even widening. `u32(x)` and `f32(y)` are explicit
casts. This is verbose by design: it makes every conversion greppable and removes a
whole class of silent bugs from generated code.

The sole exception is **losing mutability**: `[]T` converts to `[]const T` and `*T`
to `*const T` implicitly. It is one-way, it can only remove a capability, and
without it every read-only parameter would need a cast at every call site. These
two, with pointer auto-dereference in `a.b`, the `Buf[T]`-to-slice mapping at a
kernel launch, and the compiler-generated address of a mutable iterator, are the
five implicit operations, kept in one place in §6.

### Casts

`T(x)` is the checked conversion form. `T.trunc(x)`, `mem.cast` (Composites, below),
`mem.bitcast` (§8 — the bytes of a value read as another type of the same size)
and `simd.convert` (Vectors, below — lane-wise `T(x)`) are the only other conversion
forms, each greppable by name, and there are no more. A cast is not a typing context
for an untyped literal (§3): `u8(300)` is a compile error because `300` has no type
to be cast from; write `300u16` or a value.

Between integer types `T(x)` is **checked**: the value must be representable in `T`.
`u32(x)` with a negative `x`, or `u8(n)` with `n: u32 = 300`, is a narrowing cast
that fails; in a debug build it traps (§11), in a release build it yields the C
result — the source value sign- or zero-extended as its own type dictates, then cut
to the width of `T`. A truncation that is *meant* is spelled `T.trunc(x)`:
`u8.trunc(x)` keeps the low eight bits in every build mode and says so on the page,
the counterpart of `+%` for arithmetic. A widening cast between integer types can
never fail and costs nothing beyond the extension.

Between and across the other scalar types the rules are these, and `simd.convert`
applies them lane by lane:

| Cast | Result |
|---|---|
| float → integer, `i32(f)` | rounds toward zero; a value outside `T`'s range, or NaN, is a `narrow` check (§11): trap in debug, and in release the result **saturates** — `T`'s minimum or maximum for an out-of-range value, `0` for NaN — on every target: aarch64 does so natively, x64 by a compare sequence around `cvttss2si`. There is no extra form |
| integer → float, `f32(i)` | rounds to nearest, ties to even; never fails |
| float → wider float | exact |
| float → narrower float | rounds to nearest, ties to even; overflow gives the infinity, never a check |
| `f16` ↔ `bf16` | same width, different split: rounds to nearest, ties to even; overflow gives the infinity, never a check |
| `bool` → integer, `u8(b)` | `0` or `1` |
| integer → `bool` | not a cast: write `x != 0` |

An integer-to-`enum` cast, `Kind(x)`, is checked against the declared members the
same way: a value that names no member traps in every build mode. Unlike integer
narrowing there is no useful C result—an invalid discriminant would break exhaustive
switches—so this validity check is never removed.
`u8(k)` on an `enum u8` is always representable. A cast between an `enum` and an
integer of a **different width** goes through the backing type first, then an
integer cast — `u32(u8(k))`, `Kind(u8(x))` — and a direct different-width cast is a
compile error. Casting to or from `err` is not a
cast at all; an `err` is only ever an `error` declaration or `ok` (§7).

### Composites

```
*T              pointer
*const T        pointer to immutable data
[]T             slice — a { ptr, len } pair, 16 bytes on 64-bit
[]const T       slice of immutable data
[N]T            fixed array, passed by value
*void           opaque pointer — C's void*; exists for extern signatures (§5)
```

`const` qualifies the *pointee*, not the binding — `let` already makes a binding
immutable. There is no way to cast it away: if you need to mutate, copy. It qualifies
the pointee of a pointer or slice type — `*const T`, `[]const T`, and §10's
address-space-qualified device forms `*const shared T` and `[]const shared T` — and
those are the only positions it appears in.

`*void` cannot be dereferenced, indexed or sliced. A pointer converts to another
pointer type — `*void` included — only through `mem.cast[*Foo](p)`, an intrinsic of
`e.mem` that reinterprets the address and does nothing else. It **preserves
`const`**: a `*const T` can become only a `*const U`, so the qualifier is never cast
away by this route either. It is CPU-profile only: §10 bans it inside `@gpu`, where
address spaces are distinct.

### Places, `&` and slicing

Whether `&e`, `e[lo..hi]` or an assignment `e[i] = v` / `e.f = v` gets the mutable
or the `const` form is decided by **the innermost pointer or slice step** on the path
to the place — the last `*T`, `*const T`, `[]T` or `[]const T` that was walked
through to reach it. Only when the path has no such step — the place is a value held
directly in a binding: an array, a struct, a scalar — does the binding decide, and
there `var` gives the mutable forms and `let`, a parameter and a `const` give the
`const` forms. A parameter or `let` of pointer or slice type is an immutable binding
whose pointee keeps the qualifier written in its type, so it contributes its own step.

| Innermost step (or the binding, if there is none) | `&e` | `e[lo..hi]` | `e[i] = v`, `e.f = v` |
|---|---|---|---|
| `*T`, `[]T`, or a `var` binding with no step | `*T` | `[]T` | legal |
| `*const T`, `[]const T`, or a `let` / parameter / `const` binding with no step | `*const T` | `[]const T` | compile error |

`*p = v`, assignment through a dereference, is under the same rule with `p`'s own
type as the step: it requires `p: *T` and is a compile error on a `*const T`.

Worked through the shipped examples: in `fn slice[T](l: *List[T]) -> []T { ret
l.items[0..l.len] }` the path is `l` (`*List[T]`) then `.items` (`[]T`); the innermost
step is `[]T`, so the result is `[]T` and the declared return type is right. In
`saxpy(..., y: []f32)`, `y[k] = v`, `&y[k]` (`*f32`) and `y[0..n]` (`[]f32`) are all
mutable, because `y`'s own type is the step. `let v = Vec3{...}; let p = &v; p.x =
1.0` has no step, so `p` is `*const Vec3` and the assignment is a compile error —
the guarantee D18 was recorded for. `let targets = [_]str{...}` sliced as
`targets[0..]` is a `[]const str`, and every read-only library parameter is declared
`[]const T` (Strings, below) so that it fits without a cast.

`e[lo..hi]` is the slice from `lo` (inclusive) to `hi` (exclusive); `e[lo..]` runs to
`e.len`. Bounds are `usize` (§3) and are bounds-checked in debug builds (§11). `.len`
on a slice or an array is `usize`.

`[]const T` is **shallow**: with `T = []u8`, the elements of the outer slice cannot
be reassigned, but the bytes they point at can be written through them. Deep
immutability is spelled out, `[]const []const u8` — which is what `[]const str`
already is.

Array literals name their type, like struct literals, and `_` infers the length:

```
let primes = [4]u8{ 2, 3, 5, 7 }
let names = [_]str{ "x64", "aarch64", "spv" }
```

An array literal supplies exactly `N` elements — a shorter or longer list is a
compile error — and `_` takes the count from the list; a `Vec` literal (Vectors,
below) supplies exactly its `N` lanes. A struct literal names every field exactly
once, in any order, and `neper fmt` writes them in declaration order; an omitted
field is a compile error, never zero, because there is no hidden memset (§5) —
`= zero` is the spelling for all-zero. A `union` literal names exactly one member,
`Value{ i: 42 }`, and the bytes beyond that member are unspecified.

There is no tuple type. `(A, B)` appears only in a return signature, where it
declares multiple return values rather than a value of some product type — see §5.

```
type Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
}

type Value = union {
    i: i64,
    f: f64,
    p: *u8,
}

type Kind = enum u8 {
    None,
    Int,
    Float,
}
```

- `struct` fields are laid out in declaration order with natural alignment. `@packed`
  removes padding. `@align(N)` sets alignment.
- `union` is untagged and unchecked, exactly like C, and it is the **escape hatch**:
  it exists for C ABI compatibility across `extern` (§5) — Win32's `INPUT`,
  Vulkan's `VkClearValue`, `sockaddr` — and for deliberate punning. A value that is
  one of several variants is a `union enum`, below, the default for a variant type;
  a bare `union` on the page signals FFI or a pun, and a pun alone never needs one,
  because `mem.bitcast[T](x)` (§8) reinterprets a value's bytes as `T` without a
  `union`. A bare `union` is banned in device code, and neither `union` form is a
  `gpu.Buf[T]` element type (§10).
- `enum` has an explicit backing integer type and is a distinct type from it. A
  member may carry an explicit value, `enum u8 { A = 3, B, C = 9 }`; a member without
  one takes the previous member's value plus one, the first defaulting to `0`. Two
  members with one value, or a value outside the backing type, is a compile error.
  A member is written `.Int` where the context supplies the type; the qualified
  form `Kind.Int` is legal wherever `.Int` is and required where no context supplies
  the type — `let k = Kind.Int` (§2).
- `type X = T` with any other `T` — a primitive, a pointer, a slice, an array, a
  `Vec`, a named type — declares an **alias**: `X` is `T` itself, interchangeable
  with it everywhere with no conversion in either direction, not a distinct type.
  A distinct type over `u32` is a single-field struct — `struct { raw: u32 }` —
  which is what `e.time` (§16) and `e.os` (§5) do to keep a `Timestamp` or
  a `File` apart from its integer. `str` is exactly such an alias of `[]const u8`
  (Aliases, above).

**Sized and storable types.** A type is *sized* when `mem.size_of[T]()` and
`mem.align_of[T]()` are defined. The integer and float primitives, `bool`, `err`,
pointers, function pointers, enums, and recursively arrays, vectors, structs, bare
unions, tagged unions and atomics of sized types are sized. `void`, `type`, multiple
return lists, argument packs, `Mask[T, N]`, `Field` and `Member` are not. A type is
*runtime-storable* when it is sized and is not a function type; only runtime-storable
types may be a field, array element, slice element, `Atomic` element or
`mem.alloc[T]` argument. Locals additionally admit the register-only `Mask[T, N]`.
Functions and `extern fn` values may be held only through their function-pointer
types.

An array length may be zero. `[0]T` has size zero and alignment `align_of[T]`; its
stride is `size_of[T]` rounded up to `align_of[T]`. An empty `struct` has size one
and alignment one, so distinct objects have distinct addresses. Empty bare unions,
empty enums and empty tagged unions are compile errors. A struct, union, tagged union
or enum may not declare two fields or members with the same name.

A type may refer to itself only through a pointer or function-pointer indirection.
Any alias cycle or by-value size cycle through an array, struct, union or tagged-union
payload is a compile error and the diagnostic prints the cycle.

**Exact aggregate layout.** For a non-packed struct, each field begins at the least
multiple of its alignment at or after the previous field, the struct alignment is the
maximum field alignment, and tail padding rounds its size to that alignment. An array
uses the element stride above. A bare union has the maximum size and alignment of its
members, rounded to that alignment. `@packed` gives every field alignment one and
removes inter-field and tail padding; `@packed` with `@align(N)` keeps packed field
offsets and raises only the aggregate alignment to `N`, adding tail padding as needed.
Without `@packed`, `@align(N)` raises the aggregate alignment and tail rounding but
does not change individual field alignment. Duplicate or non-power-of-two alignment
attributes are errors. Target ABI chapters define pointer, `usize` and aggregate-call
classification; these byte-layout rules do not depend on the host C compiler.

Primitive sizes are their names' bit widths and their natural alignment is their byte
size, capped only where the target ABI chapter says so. `bool` is one byte with
alignment one; `err` is four bytes with alignment four; `usize`, `isize`, data
pointers and function pointers have the target pointer size and alignment. Floats use
their IEEE storage widths. An enum has exactly the size and alignment of its backing
integer. `Atomic[T]` has `T`'s size and at least `T`'s alignment, raised only when the
target's atomic instruction requires it; that target-specific raising is part of the
data-layout version and C ABI mapping.

### Tagged unions

`union enum` is the tagged form. It is what a compiler is mostly made of — tokens,
AST nodes, IR instructions — and it is the optional type: `union enum u8 { Some: T,
None }`, with no keyword of its own.

```
type Node = union enum u8 {
    Lit:   i64,
    BinOp: BinOp,
    Nil,
}

let n = Node{ Lit: 42 }
let z = Node{ Nil }

switch n {
case .Lit as v:
    ... // v: i64, a let binding of the payload
case .BinOp as op:
    ... // op: BinOp
case .Nil:
    ...
}

if n.tag == .Lit { ... } // the tag, an enum with the members' names
let v = n.Lit // payload access, tag-checked in debug (§11)
```

- The backing integer type is the tag's type. Tags are assigned in declaration order
  from `0`. A member without a payload is a bare name.
- Layout on the CPU is the tag followed by one bare-union payload area whose size and
  alignment are the maxima of the payload members; the area begins at its natural
  alignment and the whole value receives normal tail padding — the
  same bytes as the hand-rolled `struct { kind: Kind, u: union { ... } }`. Placing
  the tag hides no cost; it only removes the chance of reading the wrong member. In
  device code the payloads do not overlap (§10); the layout is invisible to the
  program, so both are conforming.
- A literal names exactly one member: `Node{ Lit: 42 }`, `Node{ Nil }`. A member
  without a payload is written `.Nil` where the context supplies the type, as an
  `enum` member is, and `neper fmt` rewrites `Node{ Nil }` to `.Nil` wherever the
  context types it — so the canonical form (§14) has one spelling per position.
- `n.tag` reads the tag; its type is an `enum` of the backing type with the same
  member names, spelled `Node.Tag` where a type is needed. A `union enum` member
  named `Tag`, or a sibling `type` declaration whose name would collide with
  `<Union>.Tag`, is a compile error. `n.Lit` reads or writes
  the payload; in debug builds it is one compare against the tag, and a mismatch
  traps (§11). Assigning a whole value (`n = Node{ Nil }`) changes the variant.
- `case .Lit as v` binds the payload as a `let` for the case's block; `as` is
  omitted for a member without a payload.
- `switch` on a tagged union, like `switch` on an `enum`, must be exhaustive unless
  a `default` case is present (§6). Adding a variant therefore flags every `switch`
  that does not handle it.

### Vectors (SIMD)

`Vec[T, N]` is the vector type: `N` lanes of `T`, a builtin generic in the form every
other parameterised builtin takes (`Atomic[T]`, `gpu.Buf[T]`, D5). There are no
`f32x8`-style names — one spelling, with both parameters visible to a grep. These
are the primary route to vector performance; there is no auto-vectoriser in v1.

```
let a = simd.splat[Vec[f32, 8]](1.0)
let b = a * a + a
let c = Vec[i32, 4]{ 1, 2, 3, 4 }
```

**The legal `(T, N)` pairs are a closed table.** `T` is any integer or float
primitive of §4 — not `usize`, `isize`, `bool` or a composite — and the vector's
width `N * mem.size_of[T]()` (§8) is 16, 32 or 64 bytes. Nothing else is a vector
type; a generator never has to guess whether `Vec[u64, 3]` exists (it does not).

| `T` | Legal `N` | Width |
|---|---|---|
| `i8` `u8` | 16, 32, 64 | 16, 32, 64 bytes |
| `i16` `u16` `f16` `bf16` | 8, 16, 32 | 16, 32, 64 bytes |
| `i32` `u32` `f32` | 4, 8, 16 | 16, 32, 64 bytes |
| `i64` `u64` `f64` | 2, 4, 8 | 16, 32, 64 bytes |

`mem.size_of[Vec[T, N]]()` is the width and its alignment equals its width, in a
struct, an array and on the stack alike. `Mask[T, N]` is the **mask type** of `Vec[T, N]`,
legal for exactly the same pairs: one lane-wide `true`/`false` per lane, produced by
comparisons and consumed by `select` and the masked loads and stores. Its
representation is the target's — a same-width vector of all-ones/all-zeros lanes on
SSE, AVX2 and NEON, a `k` register at `x64-v4` — and the program cannot see which.
`& | ^ ~` apply to masks; `simd.any(m)`, `simd.all(m)` and `simd.bits(m) -> u64`
(bit `i` for lane `i`) read one.

`Mask[T, N]` is **register-only**, on both profiles. It is legal as a `let` or `var`
local, a parameter, a return value — passed and returned as the `Vec[T, N]` it masks,
in the vector class (§5) — and an intrinsic operand, and nowhere else: not a
struct field, an array element, a module-scope `var`, a `gpu.Buf[T]` element (§10)
or the pointee of a pointer — `&m` is a compile error — and `mem.size_of[Mask[T,
N]]()` is a compile error, because the type has no layout the program can name. A
mask that must be stored is converted: `simd.bits(m)` gives the integer bitmask and
`simd.mask[V](bits)` gives it back. `= zero` on a local `Mask` is every lane
`false` (§7).

**Operators** apply lane by lane, both operands the same `Vec[T, N]`, and the result
is that type. On float lanes `+ - * /` are §11's IEEE operations, one rounding each,
never contracted. On integer lanes only the **wrapping** forms `+% -% *%` exist: a
vector unit has no overflow flag, so there is no debug check to elide, and the
language does not let `+` silently mean `+%` — plain `+ - *` on an integer vector is
a compile error, and so is `/` or `%`, which no target implements as one
instruction. `& | ^ ~` apply to integer lanes; `<< >>` shift every lane by one scalar
count, which must be `< width` (§11 `shift`). `== != < <= > >=` are not defined on
vectors; the `simd.cmp_*` intrinsics are, and they return a `Mask[T, N]`. `v[i]`
reads or writes one lane, `i: usize`, bounds-checked in debug (§11).

**The `simd` module** is the operation surface, and every intrinsic that takes a
vector is **comptime-generic on it** per D5: `simd.splat[Vec[f32, 8]](1.0)`,
inferred from a vector argument where §9 allows. `V` is `Vec[T, N]`, `M` is
`Mask[T, N]` for that `V`:

| Intrinsic | Semantics |
|---|---|
| `splat[V](x: T) -> V` | every lane `x` |
| `load[V](s: []const T, off: usize) -> V` | lanes `s[off .. off+N]`, any alignment; `off + N <= s.len` is a `bounds` check (§11) |
| `store[V](s: []T, off: usize, v: V)` | the reverse, same check |
| `load_aligned[V](s: []const T, off: usize) -> V`, `store_aligned[V](...)` | as above, and `&s[off]` must be aligned to the vector's width — an `align` check in debug (§11); the emitter may select the aligned instruction |
| `load_masked[V](s: []const T, off: usize, m: M) -> V` | lanes whose mask lane is `true` are read, the rest are `0`; only the enabled lanes must be within `s`, so a tail of a slice is loaded without a scalar loop |
| `store_masked[V](s: []T, off: usize, m: M, v: V)` | writes the enabled lanes only, same bounds rule |
| `shuffle[V, IDX: [N]u8](a: V, b: V) -> V` | lane `i` of the result is lane `IDX[i]` of the 2N lanes of `a` then `b`; `IDX` is a comptime array (§9), so the permutation is one instruction or a fixed sequence, never a runtime table |
| `cmp_eq cmp_ne cmp_lt cmp_le cmp_gt cmp_ge [V](a: V, b: V) -> M` | lane-wise comparison; on floats, IEEE ordered comparison — a NaN lane is `false` except under `cmp_ne` |
| `select[V](m: M, a: V, b: V) -> V` | lane `i` is `a[i]` where `m[i]`, else `b[i]` |
| `any[V](m: M) -> bool`, `all[V](m: M) -> bool`, `bits[V](m: M) -> u64` | `true` when any, or every, lane of `m` is; `bits` sets bit `i` for lane `i` |
| `mask[V](packed: u64) -> M` | the inverse of `bits`: lane `i` is `true` when bit `i` of `packed` is set, bits at or above `N` ignored — with `bits`, the one way to store a mask, which is register-only (above) |
| `reduce_add reduce_min reduce_max [V](v: V) -> T` | horizontal reduction, in a **fixed pairwise tree** in lane order — `(0+1)+(2+3)` and so on — so a float sum is bit-identical on every target under §11; `min`/`max` are IEEE `minimum`/`maximum`; integer `reduce_add` wraps |
| `convert[V, W](v: V) -> W` | lane-wise `T(x)` to `W`'s lane type, same `N`, with the Casts table above — an integer narrowing that does not fit is a `narrow` trap in debug and truncates in release; float-to-integer rounds toward zero and saturates in release |
| `gather[V](s: []const T, idx: Vec[u32, N]) -> V` | lane `i` is `s[idx[i]]`, each index bounds-checked in debug; legal when `(u32, N)` is in the table, so `N` in {4, 8, 16} |
| `fma[V](a: V, b: V, c: V) -> V` | float lanes only: the lane-wise form of `math.fma`, the only fused multiply-add (§11) |
| `pdep(x: u64, bit_mask: u64) -> u64`, `pext(x: u64, bit_mask: u64) -> u64` | the two scalar bit intrinsics §13 refuses to select on its own; a software bit-loop sequence on every target without the instruction — below `x64-v3`, and on aarch64 and x86-32 |

There is no other way to move a vector to or from memory: a `[]Vec[f32, 8]` slice
and a `Vec` field are ordinary storage, and the intrinsics are how a slice of `T` is
walked eight lanes at a time. In device code the slice parameter of `load`, `store`,
`gather` and the aligned and masked forms is generic over the address space, as
§10's helpers are: it accepts `[]const T` and `[]const shared T` alike (`[]T` and
`[]shared T` for a store), monomorphised per space.

**Every vector width compiles on every target.** A width the hardware supports
natively lowers to one instruction; a wider one is split. `Vec[f32, 8]` becomes a
single `vaddps ymm` under `--cpu=x64-v3` and a pair of SSE instructions under
`x64-v1`; NEON is 16 bytes wide, so every 32- and 64-byte vector splits there; on
SPIR-V a vector of more than four lanes splits into four-lane vectors (§10,
Capabilities). Source stays portable, and the only thing that changes is how many
instructions come out — see §13 for the CPU levels.

**Vectors are a register class.** A `Vec[T, N]` is passed and returned in vector
registers — `xmm`/`ymm`/`zmm` at the level's width, NEON `v` registers — and is
exempt from §5's hidden-reference rule whatever its size; a returned vector comes
back in vector registers, as many as its width needs at the level, up to §5's
per-target vector budget — two on x64 and aarch64, one on x86-32 — and beyond that
budget the set goes to §5's caller slot like any aggregate. It never crosses an `extern` boundary by
value (§5). In device
code `Vec[T, N]` is a device storage and execution type when its lane type is (§10), and every `simd.*` intrinsic is legal except
`pdep`/`pext`; the aligned forms are the unaligned ones there.

Because the width is written in the source rather than inferred by a vectoriser, the
code you wrote is the code you get. That predictability is the trade for having no
auto-vectorisation.

### Strings

A string literal has type `[]const u8` and points at read-only data. It is not
null-terminated, carries its own length, and costs no allocation.

```
let greeting = "hello" // []const u8, len 5
let name: str = "neper"
```

The `const` is what makes `s[0] = 'x'` a compile error rather than a segfault, which
is why it exists at all.

Concatenation allocates, so it takes an arena — there is no `+` operator for
strings, and never will be (§6). Four forms, no more:

```
// `a` is a *mem.Arena, as it is everywhere else (§8, §13)
let msg = try str.concat(a, greeting, name) // exactly two parts
let all = try str.join(a, parts, ", ") // a []const str, plus a separator
let s = try str.format["{}:{}"](a, file, line) // a format string (Formatting, below)

var b = try str.builder(a, 64) // incremental
try str.push(&b, greeting)
try str.push_u64(&b, 42)
let line = str.done(&b)
```

**The `push` family is closed**, one function per name (§14): `str.format` and
`io.printf` expand every verb into `push` calls, or into one call to the argument
type's `format` (§9, Protocols), and into nothing else. `io.printf`'s flushing
belongs to its builder rather than to the expansion (below), so a user `format` body
reached from a verb pushes exactly as any other code does:

| Function | Pushes |
|---|---|
| `push(b: *Builder, s: []const u8)` | the bytes |
| `push_byte(b, c: u8)` | one byte |
| `push_i8(b, v: i8)`, `push_i16(b, v: i16)`, `push_i32(b, v: i32)`, `push_i64(b, v: i64)`, `push_isize(b, v: isize)`, `push_u8(b, v: u8)`, `push_u16(b, v: u16)`, `push_u32(b, v: u32)`, `push_u64(b, v: u64)`, `push_usize(b, v: usize)` | decimal, one per integer type so that no cast is ever needed |
| `push_hex_u32(b, v: u32)`, `push_hex_u64(b, v: u64)`, `push_bin_u32`, `push_bin_u64` | `{x}` and `{b}`: the digits alone, no prefix and no leading zeros |
| `push_f32(b, v: f32)`, `push_f64(b, v: f64)` | `{}`: the shortest digit string that round-trips to the value, in fixed notation when the decimal exponent is in `[-5, 15]` and scientific otherwise — `1.5e-7` — and `inf`, `-inf`, `nan` for the non-finite values |
| `push_f32_fixed(b, v: f32, prec: u8)`, `push_f64_fixed(b, v: f64, prec: u8)` | `{.N}` |
| `push_bool(b, v: bool)` | `true` / `false` |
| `push_err(b, e: err)` | the qualified name (§7) |

Every push returns `err` — `str.NotOnTop`, below; `mem.Exhausted` (§8) on a builder
with no flush sink; the sink's own `err` on one with (below). Each
push writes what the matching `printf` verb writes, so an expansion contains no
source-level conversion. Three readings inside the formatter are not conversions: a
narrow integer widened to the push width under `{x}`/`{b}`, a narrow float widened to
`f32`, and a pointer's address read as a `u64` (Formatting, below). `push_byte` alone
has no verb — it is called by name, and `{}`
on a `u8` is decimal through `push_u8`. The rest of the surface:

```
type Sink    = struct { ctx: *void, write: fn(ctx: *void, bytes: []const u8) -> err }
type Builder = struct { arena: *mem.Arena, start: usize, len: usize, reserved: usize, sink: Sink, flushing: bool }
type Split   = struct { source: str, separator: str, off: usize, finished: bool }
error NotOnTop // something else has allocated from the arena since builder
error BadNumber // a parse function's input is malformed or out of range
error InvalidSeparator // split separator is empty
```

`Sink` is a context pointer and one ordinary neper function pointer (§5) — never an
`extern fn`, so a sink crosses no C boundary and needs no `@cc`. A builder carries at
most one, and a builder that carries one is a **flushing** builder.
`Builder.start` is its byte offset in `arena`, `len` is written bytes and `reserved`
is the current claim; the claim is on top exactly when
`arena.off == start + reserved`. `flushing == false` means `sink` is ignored. These
fields are readable for diagnostics but module functions require their invariants;
callers do not replace them.

| Function | Semantics |
|---|---|
| `fn builder(a: *mem.Arena, cap: usize) -> (Builder, err)` | claims the arena top with `cap` bytes reserved — an initial reservation, not a limit: the builder grows past it in place while it owns the top, and `mem.Exhausted` is the only bound |
| `fn builder_to(a: *mem.Arena, cap: usize, sink: Sink) -> (Builder, err)` | the same claim, carrying `sink`. Where `builder`'s push returns `mem.Exhausted`, this one **flushes**: the bytes pushed so far go to `sink.write`, the claim is reset to its base, and the push proceeds — so `mem.Exhausted` never leaves a push on a flushing builder, a push larger than the whole buffer drains through the sink as it is written, and what a push can return is `str.NotOnTop` or whatever `sink.write` returned. `str.done` gives back the bytes still in the buffer, which the caller sends through the sink itself |
| `fn done(b: *Builder) -> str` | ends the claim; the bytes pushed so far |
| `fn concat(a: *mem.Arena, x: []const u8, y: []const u8) -> (str, err)` | exactly two parts |
| `fn join(a: *mem.Arena, parts: []const str, sep: []const u8) -> (str, err)` | many parts |
| `fn eq(x: []const u8, y: []const u8) -> bool` | byte equality |
| `fn parse_f32(s: []const u8) -> (f32, err)`, `fn parse_f64(s: []const u8) -> (f64, err)` | the whole of `s` as a float, in the notation `push_f32` writes; `str.BadNumber` on anything malformed or out of range |
| `fn parse_i64(s: []const u8) -> (i64, err)`, `fn parse_u64(s: []const u8) -> (u64, err)` | the whole of `s` as a decimal integer, an optional `-` on the signed form; `str.BadNumber` on anything malformed or out of range. Narrower widths go through a cast (§4), which is where a value that does not fit is reported |
| `fn parse_i64_radix(s: str, radix: u8) -> (i64, err)`, `fn parse_u64_radix(s: str, radix: u8) -> (u64, err)` | whole-input parsing for radix `2..36`; ASCII letters are case-insensitive and no prefix is recognized |
| `compare`, `compare_ascii_fold` | three-way byte-lexicographic comparison; the latter folds ASCII letters only |
| `starts_with`, `ends_with`, `contains`, `find`, `find_from`, `rfind`, `count` | byte-substring operations with `(index, found)` results; an empty needle matches every boundary |
| `trim`, `trim_start`, `trim_end`, `trim_bytes` | borrowed subslices; the first three remove ASCII whitespace |
| `split_once`, `split`, `split_next`, `lines` | borrowed, non-copyable traversal preserving empty fields; empty explicit separators return `InvalidSeparator`; lines accept LF and CRLF and omit terminators |
| `replace`, `repeat` | checked arena allocation and non-overlapping replacement |
| `ascii_lower_in_place`, `ascii_upper_in_place`, `is_ascii_space`, `is_ascii_digit`, `is_ascii_alpha`, `is_ascii_alnum` | locale-free ASCII operations; Unicode equivalents remain in `e.text.*` |

Fixed precision `N` is in `0..=99`; a larger runtime `prec` returns `BadNumber`, and
a larger format-literal precision is a compile error. Fixed conversion rounds ties to
even and always writes exactly `N` digits after the decimal point; non-finite values
still write `inf`, `-inf` or `nan` without a fractional suffix.

Parsing consumes every byte and accepts no surrounding whitespace or leading `+`.
Integers require at least one ASCII digit and reject overflow. Floats accept the
shortest/fixed decimal forms emitted above, an optional leading `-`, an optional
lowercase `e` exponent with optional sign and at least one digit, and exactly the
lowercase tokens `inf`, `-inf`, `nan`. They preserve negative zero, return the
canonical NaN of §11, and reject decimal overflow or underflow that would produce an
infinity or zero unless the input was the corresponding explicit token or exact zero.

And `e.io`, which is the one place text leaves the program: `fn print(s: []const
u8) -> err` writes to `os.stdout()` (§5), looping over `os.write` until every byte
is written or a call returns an `err`, which `print` returns; and `fn printf[FMT:
str](args: ...) -> err` (Formatting, below) does the same through a **flushing
builder over a 4 KiB stack arena** of its own — a `[4096]u8 = undef` local under
`mem.arena_from` (§8), its top claimed by `str.builder_to` (above) with a sink whose
`write` is `print`'s loop over `os.write` — so that every verb is a `str.push_*` and
no caller's arena is involved. The flushing is the builder's, not `printf`'s: a push
that fills the buffer drains it through the sink and carries on, a `str` argument
longer than the whole buffer drains through it as it is pushed, and `printf` sends
what `str.done` leaves through the sink once at the end. Output of any length
therefore works; `mem.Exhausted` never reaches the expansion, so a user `format`
(§9) called for a verb is an ordinary sequence of pushes; `str.NotOnTop` cannot arise
because nothing else allocates from that arena; and only `os.write`'s errors
propagate.

**The builder is the fast path.** While it owns the top of an arena, appending is a
bump of the offset — the buffer grows in place with no reallocation and no copying,
because nothing else can have allocated above it. That is a direct payoff from
having no global allocator.

That precondition is **checked, in every build mode**: `str.push` (and every
`str.push_*`) compares the arena's `off` with the builder's end and returns
`str.NotOnTop` when anything else has allocated from the arena since the builder was
created. It is one compare on the fast path, and it turns what would be a silent
overwrite of the other allocation into a definite `err`. `str.done` ends the
builder's claim on the arena top.

Slices are compared with `str.eq(x, y)` or `mem.eq[T](x, y)`, never `==` (§6).

**Every library parameter that is only read is `[]const T`**: `str.join`'s parts,
`str.push`'s text, both operands of `str.eq` and `mem.eq[T]`, the source of
`mem.copy[T]`, `io.print`. Because `[]T` converts to `[]const T` implicitly (above),
a mutable slice, a `let` array and a literal all fit the same parameter; a
parameter is `[]T` only where the function writes through it.

### Formatting

The format string is a **comptime parameter**, so it is parsed at compile time and
the call expands to straight-line pushes with no runtime parsing:

```
try io.printf["{} compiled {} modules in {}ms\n"](name, count, elapsed)
let s = try str.format["{}:{}:{}"](&a, file, line, col)
```

Arity and argument types are checked against the format string at compile time. A
mismatched count or an unformattable type is a compile error, not a runtime one.
**Formattable is every type §9 rule 4 supplies a `format` for, plus any type whose
module declares a `fn <t>_format(v: T, b: *str.Builder) -> err`** — the `format`
protocol of §9, spelled `fn vec3_format` for a `Vec3`. §9 rule 4 is the authority on
the first half, and it reaches the integers, the floats, `bool`, `err`, pointers,
slices — `str` among them — arrays, `Vec`/`Mask`, and every `enum` and `union enum`
whose own module declares no `format`. What the supplied `format` writes, one clause
per shape:

| Shape | `{}` writes |
|---|---|
| an integer, a float, a `bool` | what its `push_*` writes (the push table above) |
| an `err` | its qualified name (§7), or `ok` |
| a pointer | its address in hex, `nil` as `nil` |
| a `[]u8` or `[]const u8` | its bytes, as written — this is `str` (Aliases, above), and it is the one slice that is text rather than a list |
| any other slice, or an array | `[`, its elements under this same rule separated by `, `, `]` |
| a `Vec[T, N]` | its `N` lanes in that form; a `Mask[T, N]` its lanes as `true`/`false` |
| an `enum` | the member's name, `Int` for `Kind.Int` |
| a `union enum` | the member's name, then `: ` and the payload under this rule where it has one |

A verb on a type whose module declares a `format` expands instead to one call to that
function with the builder the expansion is already pushing into, which is why the
expansion is still closed: every verb becomes `push` calls, or one call to that
type's `format`.

Verbs: `{}` default, `{x}` hex, `{b}` binary, `{.N}` float precision. A literal brace
is escaped by doubling: `{{` prints `{` and `}}` prints `}`.

`{}`, `{x}` and `{b}` accept every integer type and print at the value's own width:
`u8` `255` is `ff` under `{x}`, `i16` `-1` is `-1` under `{}`. Under `{x}` and `{b}`
a signed value prints its **two's-complement bits at its own width**, no sign and no
leading zeros — `i16` `-1` is `ffff`, `i8` `5` is `101` under `{b}` — so `{}`
expands to the push of the argument's own type, and `{x}`/`{b}` to `push_hex_u32`
or `push_bin_u32` for a width up to 32 bits and the `u64` form above it, `usize`
and `isize` at the target's width. The widths of the
`push_*` family are an implementation detail of `e.str`; where an expansion
reaches a wider push, the widening is internal to the formatter intrinsic and is
not a source-level conversion, so §6's list of implicit operations stays complete.
A narrow float is under the same exemption: the formatter widens an `f16` or `bf16`
to `f32` internally, so `{}` on one prints through `push_f32` and `{.N}` through
`push_f32_fixed`, and there is no narrow-float push.

### Pointers and nil

`nil` is a valid pointer value, and it is also the zero value of a slice — `ptr`
`nil`, `len` `0` (§7) — so `nil` is the spelling of an empty slice in expression
position: `let xs: []u8 = nil`, `ret (nil, e)`. In debug builds every dereference
is null-checked (§11). There is no optional keyword; where `nil` is not enough, `union enum u8 {
Some: T, None }` (Tagged unions, above) is the optional.

---

## 5. Declarations

Every top-level declaration begins at **column 0** with its keyword. This is
enforced by the formatter and assumed by tooling (§14).

```
use e.mem
type Vec3 = struct { ... }
const MAX_NODES: u32 = 4096
var g_tick: u64 = 0
error NotFound
fn dot(a: Vec3, b: Vec3) -> f32 { ... }
@import("kernel32", "GetTickCount64")
extern fn get_tick_count64() -> u64
```

### Attributes

One or more attributes occupy **their own contiguous lines at column 0, immediately
above the declaration they modify**:

```
@gpu(256)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) { ... }

@test
fn parse_handles_empty_input(a: *mem.Arena) -> err { ... }
```

Never `@gpu fn saxpy(...)` on one line. The declaration keyword has to stay at
column 0 for §14 to hold — otherwise `grep "^fn saxpy"` misses exactly the functions
that carry attributes, which are the interesting ones. `neper fmt` moves them.

Declaration attributes are `@gpu(X, Y, Z)` (§10), `@test`, `@packed` and `@align(N)`
— legal only on a `type ... = struct` or `type ... = union` declaration, and
`@align(N)` requires `N` a power of two at or above the type's natural alignment
unless `@packed` is also present — `@import(LIB, SYM)` — legal only on an `extern`
declaration — and `@cc(CONV)` — legal on an `extern` declaration, on a plain `fn`
that is to be C-callable — such a `fn` stays an ordinary neper function at every
neper call site, called there under the named convention — or on a `type`
declaration whose right side is an
`extern fn(...) -> R` type (External functions, below). `@nocheck` is a statement-level block (§11) and is the
one attribute that does not take a line of its own.

An attribute may appear at most once on a declaration. Multiple legal attributes
have no source-order semantics; `neper fmt` sorts them by attribute name as specified
in `docs/tooling.md` §6. A blank line or comment inside that attribute block or
between it and the declaration is a syntax error, so attachment never depends on a
tool's trivia policy.

- `const` is compile-time evaluated and has no storage.
- `var` at module scope is mutable static storage, zero-initialised unless given a
  compile-time initialiser. Not permitted in the GPU profile.
- Inside functions: `let` binds immutably, `var` binds mutably. Both infer their
  type from the initialiser unless annotated, and **both require an initialiser**.
  An unused `let`, `var` or parameter is not an error: `args` in a `main` that
  ignores it is legal, and there is no discard spelling for a binding.
- A local or parameter name is declared once per **active lexical scope**. It may
  not reuse a parameter, a binding in an enclosing scope, a module-scope name of
  its own module, a `use` qualifier or a builtin type name (§2). It may be reused
  in disjoint sibling blocks after the earlier binding's scope has ended. This
  permits independently generated blocks to compose without a function-wide name
  allocator while preserving the stronger property a reader needs: at every
  source position, one spelling resolves to exactly one declaration. Two bindings
  in the same block, including two sequential `let (data, e) = ...` bindings, still
  require different names.

### Local initialisers

There is no uninitialised local and no hidden memset. A local whose initial contents
do not matter says so, with one of two spellings that are legal only as the whole
initialiser of an annotated binding:

```
var buf: [4096]u8 = zero // every byte 0 — a visible memset
let v:   Vec3     = zero // a definite constant; legal on let
var buf: [4096]u8 = undef // no store at all; var only
```

`= zero` writes the zero value of the type (§7 defines it for every type) and is
legal on an annotated `let` or `var`. `= undef` is legal on an annotated `var` only:
it emits nothing in release; a debug build fills the storage with `0xCD`, the same
byte fresh arena memory receives (§11), so a read-before-write shows up as a
recognisable value rather than as whatever the stack held. `undef` is banned inside
`@gpu`, and on a `let`, which could never be written afterwards. A module-scope
`var` is zero-initialised already; `= zero` is permitted there and `= undef` is not.

Every other initialiser is an ordinary expression, so what is on the page is what is
stored.

### Functions

```
fn name(p: T, q: U) -> R { ... }
fn name(p: T) -> (R, err) { ... }
fn name(p: T) { ... } // returns void
```

Parameters are immutable bindings. Aggregates larger than two machine words are
passed by hidden reference; this is an ABI detail, not a semantic one — pass `*T`
when you want the callee to mutate. What makes it an ABI detail is one rule,
mirroring D14: **the storage of a by-value argument is not written by anyone for the
duration of the call** — not by the callee, not by the caller through another
pointer, not by another thread. Doing so is undefined behaviour. Under that rule the
compiler may pass the caller's storage by address and never copy, with no alias
analysis; `f(x, &x)` where `f` writes through its second parameter is the program's
bug, not the compiler's. `Vec[T, N]` (§4) is the one exemption from the size rule: a
vector is a register class, passed in vector registers at any width, never by hidden
reference, and returned in them up to the per-target budget (Multiple return
values, below); `Mask[T, N]` (§4), which has no size, is passed and returned as the
`Vec[T, N]` it masks.

Function pointers exist on the CPU: `fn(i32) -> i32` is a type. They are banned in
the GPU profile.

### Multiple return values

`(A, B)` in a return signature is a **calling convention, not a type.** There is no
tuple value in neper: nothing to store in a struct, nothing to pass as a parameter,
nothing to name `.0`.

```
fn divmod(a: i64, b: i64) -> (i64, i64) { ... }

let (q, r) = divmod(17, 5)
```

Returned values are destructured at the call site. The convention is the one a
single return uses, widened. Every returned value belongs to one of two **return
classes**: the **integer class** — integers, pointers, `enum`s, `err` and `bool` —
and the **vector class** — floats of every width, `Vec[T, N]` (§4) and `Mask[T, N]`,
which travels as the `Vec[T, N]` it masks — a same-width vector of all-ones and
all-zeros lanes, in that vector's registers — whatever register the level holds a
mask in between calls. Each class has a per-target budget, counted in values:

| Target | Integer class | Vector class |
|---|---|---|
| x64 (System V and Windows) | 2 (`rax`, `rdx`) | 2, from `xmm0` upward — `ymm`/`zmm` at the level's width |
| aarch64 | 2 (`x0`, `x1`) | 2, from `v0` upward |
| x86-32 | 2 (`eax`, `edx`) | 1, from `xmm0` upward |

The values of each class are assigned to that class's registers **in declaration
order**: the first vector-class value starts at `xmm0`, the next at the first free
register after it, a scalar float taking one register and a `Vec[T, N]`, or the
`Mask[T, N]` of one, as many consecutive registers as its width needs at the level. When either class's budget
is exhausted the **whole set** goes to a caller-provided return slot whose address
travels in a hidden first parameter; a set is never split between registers and
the slot. An **aggregate** — a `struct`, `union`, `union enum`, `[N]T`, a slice or
`str` — belongs to neither class and is never returned in registers: a set
containing one goes entirely through the slot, and only the two scalar classes use
registers. `(i64, f64, err)` is two integer-class values and one vector-class value —
registers on every target; `(f32, Vec[f32, 4])` is two vector-class values, `xmm0`
and `xmm1` on x64, registers on aarch64, and the slot on x86-32, whose vector
budget is one; `Vec[u8, 64]` alone at `x64-v1` is one vector-class value in
`xmm0`–`xmm3`. So `(i64, i64)` and `(*T, err)` come back in registers, and
`(List[T], err)` — 40 bytes — comes back through a slot the caller reserved on its
own stack. The program cannot tell which: there is still
no tuple value, no layout the program can name, and no equality or ordering rule to
define. This convention holds between neper functions only; an `extern` function
(§5) returns one value in the C convention.

Two things follow, and both are deliberate:

- **Anything worth storing gets a named struct.** `result.line` reads; `result.0`
  does not, and positional access is unanchored for search — the same reason §3
  fixes naming and §14 fixes declaration position.
- **There is one way to spell a product type.** Structs and tuples competing for the
  same job is exactly the redundancy a small language cannot afford.

Every returned value must be bound or discarded with `_`. A call that returns
anything cannot stand as a statement on its own — only a call returning `void`
can — so an ignored `err` is written down, `let _ = io.print("x\n")`, where the
reviewer sees it; `try` is the other spelling. `_` binds nothing and may take any
position:

```
let (q, _) = divmod(17, 5)
let _ = os.close(f)
```

### External functions

`extern` declares a function whose body lives in a library the linker resolves. The
foreign name and the calling convention sit on attribute lines above it:

```
@import("kernel32", "WriteFile")
@cc(c)
extern fn write_file(h: *void, buf: *const u8, n: u32, written: *u32, overlapped: *void) -> i32

@import("c", "printf")
extern fn c_printf(fmt: *const u8, ...) -> i32
```

- `extern` is a keyword and a column-0 declaration like `fn`, so §14 holds: one
  `extern` per name per module, found by `grep "^extern fn"`. The neper-side name
  obeys §3 — `write_file`, never `WriteFile` — which is possible because the foreign
  name is a string, not an identifier.
- `@import(LIB, SYM)` is required. `LIB` is the library with no platform prefix or
  suffix: `"kernel32"` is `kernel32.dll`, `"vulkan"` is `libvulkan.so` or
  `libvulkan.dylib`. `SYM` is the exported symbol, verbatim, decoration included. A
  library whose name differs per platform is declared in per-target files (§6).
- `@cc(CONV)` names the calling convention and defaults to `c`, the target's C
  convention: System V on Linux and macOS x64, `win64` on Windows x64, AAPCS64 on
  aarch64, cdecl on x86-32. `sysv` and `win64` name the two x64 conventions
  explicitly and are compile errors on any target other than x64; they exist only
  to force a non-native convention on x64, which is why `kernel32` above is
  `@cc(c)` — the platform's native C convention, correct on every Windows arch.
  `stdcall` is the Win32 API convention on x86-32 and means `c` elsewhere. The
  convention **is part of an `extern fn` pointer type**: two `extern fn(...) -> R`
  types under different conventions are distinct types with no conversion between
  them. A convention is named on a pointer type through a `type` declaration — an
  attribute line `@cc(CONV)` above `type Cb = extern fn(i32) -> i32` gives `Cb`
  that convention — and an `extern fn(...) -> R` type written without one is `c`.
- A trailing `...` declares a **C variadic** — the one runtime-variadic form in the
  language, legal only on `extern`; it is not a pack (§9). Each extra argument
  crosses as its own type under the table below, and C's default promotions are
  not applied for you: an `f32`, or an integer narrower than 32 bits, in that
  position is a compile error — write `f64(x)` or `i32(x)`.
- An `extern` function has no body and no `err`. **`err` may not appear anywhere in
  an `extern` signature**, and `try` on an `extern` call is a compile error. C
  reports failure through a return value and a thread-local code; the wrapper in
  `e.os` (below) is where that becomes an `err`.
- The name of an `extern` function in value position is a function pointer of type
  `extern fn(...) -> R`, the C-convention function-pointer type. A plain `fn` with a
  body takes that type, and becomes callable from C, when it carries a `@cc` line
  of its own — that is how a callback is handed to the OS. A `fn(...) -> R` pointer
  to a function without `@cc` uses the neper convention (§5) and does not cross.
  A `@cc` function may be generic: each instantiation is a separate C-callable
  function, which is how `os.thread_create[Ctx]` (below) builds one trampoline per
  `Ctx` without a cast. The signature rule below — every type crosses, no `err`, no
  multiple return — applies to a `@cc fn` exactly as to an `extern`.
  `@cc` changes call ABI but does not export a stable native symbol: its address is
  handed to foreign code as a callback, and its linker name remains neper's canonical
  module/instance name. Exporting a neper function by external symbol name is not in
  v1; a C-facing shared library therefore needs a future `@export` proposal rather
  than relying on decoration.
- An `extern` cannot take comptime parameters (`[...]`).
- **Banned inside `@gpu`** (§10): the device has no OS and no import table. **Not
  evaluable at compile time** (§9): a `const` initialiser whose evaluation reaches
  an `extern` call is a compile error naming the `const` and the call chain.

**What crosses the boundary.** The ABI is the target C compiler's, and every neper
type either maps onto exactly one C type or does not cross at all:

| neper | C | Crosses |
|---|---|---|
| `i8 i16 i32 i64`, `u8 u16 u32 u64` | `int8_t` … `uint64_t` | yes |
| `isize`, `usize` | `intptr_t`, `size_t` | yes |
| `f32`, `f64` | `float`, `double` | yes |
| `f16`, `bf16` | — | no; pass the bits as `u16` |
| `bool` | `_Bool` — one byte, `0` or `1` | yes |
| `void` | `void` | as a return type only |
| `*T`, `*const T` | `T*`, `const T*` | yes when `T` crosses, is `void`, or is one of the two pointee-only rows below (`Vec[T, N]`, `Atomic[T]`); `nil` is `NULL` |
| `*void` | `void*` | yes |
| `extern fn(...) -> R` | function pointer | yes |
| `fn(...) -> R` | — | no; neper convention |
| `enum T` | its backing integer type | yes |
| `struct` | `struct`, by value under the target's aggregate rules | yes when non-empty and every field crosses or is an `[N]T` of a crossing `T`; empty structs do not cross; `@packed` and `@align(N)` require an explicitly matching C declaration |
| `union` | `union` | yes, under the same condition |
| `union enum` | — | no |
| `[N]T` | — | no by value (C passes arrays as pointers); crosses only as a struct field, as `T[N]`, when `N > 0` and `T` crosses |
| `[]T`, `[]const T`, `str` | — | no; pass `*T` or `*const T` and a `usize` separately |
| `err` | — | no |
| `(A, B)` multiple return | — | no; an `extern` returns one value |
| `Vec[T, N]` | — | no by value; `*Vec[T, N]` crosses as `T*` — a pointer to `N` contiguous `T`, aligned to the vector's width |
| `Atomic[T]` | — | no by value; `*Atomic[T]` crosses as `T*` |
| `type`, comptime parameters | — | no |

"Crosses" means the value is passed and returned exactly as the target C compiler
passes and returns the mapped C type. §4's struct layout is C's, so a struct that
crosses needs no marshalling. A signature naming a type that does not cross is a
compile error at the declaration, not at the call.

An `extern` call is a direct call through the import table (PE) or the PLT/GOT (ELF,
Mach-O): no wrapper, no thunk, nothing saved beyond what the convention requires.
§13 states which linking stage each form needs.

### `e.os`

`e.os` is the host operating-system surface, and the only place ordinary `lib/e`
modules touch
the OS: `io`, `thread`, `time` and the startup code that builds the root arena (§8)
call `os.*` and declare no `extern` of their own. It is written per target in
per-target files (§6): `os.linux.e` over raw system calls, `os.windows.e` over
`kernel32`, `os.macos.e` over `libSystem` — Apple's system-call numbers are not a
stable interface, which is what moved Go onto `libSystem` in 1.12. The Vulkan and
CUDA driver bindings the GPU runtime (§10) needs are `extern` declarations in the
runtime's own modules, over the same mechanism. Those GPU-driver imports are the one
documented exception: they are not host services available to ordinary library code.

Two things in `e.os` are compiler intrinsics because the language cannot express
them: `os.syscall(n: usize, a0: usize, a1: usize, a2: usize, a3: usize, a4: usize,
a5: usize) -> isize`, the raw system call on Linux and the reason a Linux executable
can import nothing (six arguments, always; unused ones are `0`), and
`os.thread_start(stack: []u8, entry: fn(*void), ctx: *void) -> (Thread, err)`, the
`clone` and stack switch beneath `thread_create` on Linux — a new thread running
`entry(ctx)` on `stack`, which `thread_create` carves from a fresh `os.reserve`;
`os.thread_join` releases that stack after the thread has exited, and a detached
thread's stack is released by the thread's own exit path. On
Windows and macOS `thread_create[Ctx]` is neper source: it instantiates a `@cc`
trampoline per `Ctx` (External functions, above) and passes it to `CreateThread` /
`pthread_create`. Everything else is neper source over `extern`. Both intrinsics
are compiler-known (§14) — an intrinsic appears in no `.e` file — and exist on
Linux alone, so on any other target the name is an unknown-name error like any
other.

```
type File      = struct { raw: usize } // fd, or a Windows HANDLE
type Proc      = struct { raw: usize }
type Thread    = struct { raw: usize }
type Lib       = struct { raw: usize }
type Socket    = struct { raw: usize }
type Poller    = struct { raw: usize }
type Mapping   = struct { raw: usize, address: *u8, len: usize }
type Watch     = struct { raw: usize }
type Clock     = enum u8 { Wall, Monotonic }
type SeekWhence = enum u8 { Start, Current, End }
type EntryKind = enum u8 { File, Dir, Symlink, Other }
type DirEntry  = struct { name: str, kind: EntryKind }
type FileInfo  = struct { kind: EntryKind, size: u64 }
type OpenFlags = struct { read: bool, write: bool, create: bool, truncate: bool, append: bool }
type Handle    = struct { raw: usize } // any OS handle: a File's raw, a pipe end
type Stdio     = struct { stdin: File, stdout: File, stderr: File, inherit: []const Handle } // what a child inherits
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }
type ErrorKind = enum u8 { NotFound, Denied, Exists, Interrupted, OutOfMemory, Timeout, WouldBlock, Unsupported, Invalid, Other }
type ErrorDetail = struct { kind: ErrorKind, native_code: i32, operation: str, subject: str }

error NotFound
error Denied
error Exists
error Interrupted
error OutOfMemory
error Failed
error Timeout
error WouldBlock
error Unsupported
```

| Function | Notes |
|---|---|
| `fn open(a: *mem.Arena, path: str, flags: OpenFlags) -> (File, err)` | `a` holds the null-terminated (UTF-16 on Windows) path for the call, under `mark`/`reset` |
| `fn read(f: File, buf: []u8) -> (usize, err)` | short reads are ordinary; `0` at end of file |
| `fn write(f: File, buf: []const u8) -> (usize, err)` | short writes are ordinary |
| `fn seek(f: File, off: i64, whence: SeekWhence) -> (u64, err)` | sets and returns the absolute byte offset; `SeekWhence` is `.Start`, `.Current` or `.End` |
| `fn close(f: File) -> err` | |
| `fn stdin() -> File`, `fn stdout() -> File`, `fn stderr() -> File` | |
| `fn readdir(a: *mem.Arena, path: str) -> ([]DirEntry, err)` | names are allocated in `a` |
| `fn stat(a: *mem.Arena, path: str) -> (FileInfo, err)` | follows a final symlink |
| `fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err)` | classifies a final symlink itself |
| `fn mkdir(a: *mem.Arena, path: str) -> err` | creates one directory; its parent must exist |
| `fn remove_file(a: *mem.Arena, path: str) -> err` | removes a file or symlink, never a directory |
| `fn remove_dir(a: *mem.Arena, path: str) -> err` | removes an empty directory |
| `fn rename(a: *mem.Arena, src: str, dst: str) -> err` | one host-filesystem rename operation |
| `fn read_link(a: *mem.Arena, path: str) -> (str, err)` | target bytes are allocated in `a` |
| `fn pipe() -> (File, File, err)` | a read end and a write end; what `neper test` (§13) uses for each test process's captured streams |
| `fn spawn(a: *mem.Arena, argv: []const str, stdio: Stdio) -> (Proc, err)` | `argv[0]` is the program; the child's three standard streams are the `File`s in `stdio` — `os.stdin()`, `os.stdout()`, `os.stderr()` to inherit, a pipe end to capture. `stdio.inherit` is the extra handles the child inherits beyond those three. Each keeps its `raw` value in the child — an inheritable handle survives `CreateProcess` with its value, and on POSIX `spawn` leaves the descriptor at its own number rather than `dup2`-ing it — so an ordinary parent may format `raw` into an `argv` entry of its choosing. Compiler-reserved test metadata uses a lower startup layer not exposed by this function (§13). |
| `fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err)` | `cwd == ""` inherits the current directory; `inherit_env` chooses whether `env` overlays the parent environment or replaces it |
| `fn wait(p: Proc) -> (i32, err)` | the exit code, or `128 + signal` on a signal |
| `fn kill(p: Proc) -> err` | terminates the child; `wait` still returns |
| `fn exit(code: i32)` | does not return; runs no `defer` |
| `fn args(a: *mem.Arena) -> ([]str, err)` | what `main` receives |
| `fn env(a: *mem.Arena, name: str) -> (str, err)` | `NotFound` when unset |
| `fn random(buf: []u8) -> err` | fills all bytes from the platform cryptographic random source, retrying interruptions; a zero-length buffer succeeds |
| `fn page_size() -> usize` | |
| `fn reserve(n: usize) -> (*u8, err)` | address space, inaccessible until committed; `n` rounds up to pages |
| `fn commit(p: *u8, n: usize) -> err` | readable and writable; the OS zero-fills |
| `fn release(p: *u8, n: usize) -> err` | returns the range `reserve` gave |
| `fn clock(c: Clock) -> (i64, err)` | nanoseconds; `Wall` since the Unix epoch, `Monotonic` from an arbitrary origin |
| `fn thread_create[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err)` | what `thread.spawn` (§8) is; `stack` is the thread's stack size in bytes, written at every call because neper has no default parameters — `thread.DEFAULT_STACK` (1 MiB, §8) when nothing else is called for |
| `fn thread_join(t: Thread) -> err` | |
| `fn thread_detach(t: Thread) -> err` | the thread is never joined; its stack is released by its own exit path (above) |
| `fn wait_u32(p: *Atomic[u32], expected: u32, timeout_ns: i64) -> err` | returns when `*p != expected`, is woken spuriously, or times out; negative timeout means infinite and zero means poll once |
| `fn wake_one_u32(p: *Atomic[u32])`, `fn wake_all_u32(p: *Atomic[u32])` | make one or all current waiters runnable; no count is promised |
| `fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err)` | creates a close-on-exec socket |
| `fn socket_set_nonblocking(s: Socket, enabled: bool) -> err` | controls whether an operation may return `WouldBlock` |
| `fn socket_bind(s: Socket, address: SocketAddress) -> err`, `fn socket_listen(s: Socket, backlog: u32) -> err` | server primitives |
| `fn socket_accept(s: Socket) -> (Socket, SocketAddress, err)`, `fn socket_connect(s: Socket, address: SocketAddress) -> err` | accepted sockets inherit close-on-exec and nonblocking state |
| `fn socket_receive(s: Socket, dst: []u8) -> (usize, err)`, `fn socket_send(s: Socket, src: []const u8) -> (usize, err)` | short transfers are ordinary; receive returns zero only for orderly stream shutdown |
| `fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err)`, `fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err)` | datagram transfers preserve the peer address |
| `fn socket_shutdown(s: Socket, how: SocketShutdown) -> err`, `fn socket_close(s: Socket) -> err` | `socket_close` consumes the socket |
| `fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err)` | results are allocated in `a` and retain platform order |
| `fn file_handle(f: File) -> Handle`, `fn socket_handle(s: Socket) -> Handle` | non-owning values for polling or explicit inheritance |
| `fn poller_open(a: *mem.Arena) -> (Poller, err)` | creates the platform readiness/completion poller |
| `fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err`, `fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err`, `fn poller_unregister(p: Poller, handle: Handle) -> err` | one registration per handle; tokens are returned unchanged |
| `fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err)` | fills a prefix of `events`; negative timeout means infinite and zero means poll once |
| `fn poller_wake(p: Poller) -> err`, `fn poller_close(p: Poller) -> err` | wake interrupts a current or next wait; close consumes the poller |
| `fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err)` | maps a non-empty file range; internal page alignment does not change the exposed bytes |
| `fn mapping_bytes(m: Mapping) -> []const u8` | the exact requested range as a read-only view |
| `fn mapping_bytes_mut(m: Mapping) -> ([]u8, err)` | the exact requested range; returns `Denied` unless the mapping was opened writable |
| `fn mapping_flush(m: Mapping) -> err`, `fn mapping_close(m: Mapping) -> err` | flush requests host persistence; close consumes the mapping and invalidates derived pointers |
| `fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err)` | opens the native directory-change source; `Unsupported` when recursive watching cannot be implemented faithfully |
| `fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err)` | fills a prefix with root-relative paths; `Overflow` requires a rescan |
| `fn watch_close(w: Watch) -> err` | consumes the watch and wakes a blocked read |
| `fn dlopen(a: *mem.Arena, name: str) -> (Lib, err)` | `name` as in `@import`: no prefix, no suffix |
| `fn dlsym[F: type](a: *mem.Arena, l: Lib, sym: str) -> (F, err)` | `F` must be an `extern fn` type |
| `fn dlclose(l: Lib) -> err` | |
| `fn last_error_detail(operation: str, subject: str) -> ErrorDetail` | copies the classified `errno` / `GetLastError` after this thread's most recent failed `os.*` call and borrows the two caller strings |
| `fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err)` | renders the platform message for `native_code` into `a` |

Every failing call returns one of the nine errors above after mapping the platform
code; `Failed` is the catch-all, and `last_error_detail` gives an explicit portable
classification plus the raw code when the mapping is not enough. This list is the v1
surface. A future standard module that needs more
host functionality first adds a reviewed primitive here and a per-target
implementation; it does not declare its own platform `extern`. Direct optional API
bindings, including signals before such a primitive exists, belong in a package
named for its actual external owner; Neper-owned additions extend `e.os`.

`OpenFlags` must request `read`, `write` or both. `truncate` and `append` require
`write` and are mutually exclusive. `create` creates a missing file and otherwise
opens the existing one; newly created files use user read/write permissions subject
to the process umask on POSIX and the ordinary inherited ACL on Windows. `append`
makes each individual `write` append atomically as the platform defines it. An invalid
flag combination returns `Failed` before opening anything and sets the detail code to
the platform's invalid-argument code.

Paths are UTF-8. On Windows an invalid UTF-8 path returns `Failed`; valid input is
converted losslessly to UTF-16. On POSIX every path byte except zero is accepted, so a
directory entry that is not valid UTF-8 is returned with its original bytes in `str`.
`readdir` excludes `.` and `..`, preserves the platform enumeration order, does not
follow symlinks when choosing `EntryKind`, and returns `Symlink` for a symlink or
`Other` for an entry that disappears during classification.

`spawn` inherits the parent's environment and working directory, searches `PATH`
when `argv[0]` contains no separator, and rejects an empty `argv`. Each `str` is one
argument—Windows quoting and POSIX `argv` construction are implementation details and
never reparsed by a shell. Only the three standard streams and handles named in
`stdio.inherit` cross; all other library-created handles are close-on-exec/non-
inheritable. Duplicate inherited handles are harmless and transmitted once.

`spawn_with_options` applies the same argument, handle and `PATH` rules. Its `env`
entries are `NAME=VALUE`. When `inherit_env` is true they overlay the parent
environment, with the last duplicate winning; when false they are the complete child
environment. An empty `cwd` inherits the parent working directory.

`SocketAddress` stores an IPv4 address in the first four bytes and zeros the
remaining twelve; IPv6 uses all sixteen bytes and `scope`. Ports are host-order
values. `socket_resolve` performs no connection and retains the platform result
order. Pollers store handles, interests and numeric tokens, never callbacks. A
handle must be unregistered before its owning file or socket is closed. A wake is
level-like: at least one current or subsequent `poller_wait` returns, and redundant
wakes may coalesce.

`File`, `Proc`, `Thread`, `Lib`, `Socket`, `Poller`, `Mapping` and `Watch` are logically linear handles
even though their raw bits can be copied. `close`, successful `wait`, `thread_join`,
`thread_detach`, `dlclose`, `socket_close`, `poller_close`, `mapping_close` and
`watch_close` consume all copies;
another operation through any consumed copy is undefined
behavior, because the OS may already have reused the raw value and neper keeps no
hidden handle registry. `kill` after successful `wait` and a second `wait` are the
same programmer error. Dropping a live process does not wait for it. On POSIX a signal termination is
reported as `128 + signal`; an ordinary exit code with the same number is
intentionally indistinguishable. Windows exceptions map to `128 +` the low seven
bits of the exception code and leave the full code in the error detail.

Error detail state is per OS thread. A failed `os.*` call sets it before returning; a
successful call leaves it unchanged. `last_error_detail` must be called before the
next failing OS operation on that thread and copies the state into an ordinary value.
A wrapper preserves the detail from the primitive that determines its returned
`err`; it does not perform cleanup first. `operation` and `subject` are explicit
borrowed labels, so neither exceptions nor a process-global message payload are
introduced. `error_message` is the only locale-dependent rendering step.

`reserve`, `commit` and `release` accept page-aligned addresses and page-rounded
lengths after the documented rounding of `reserve`; zero length is `Failed`.
`commit` may cover an uncommitted subrange of one reservation. `release` must name
the exact base and rounded length returned by `reserve`; partial, overlapping or
foreign ranges return `Failed`. Arithmetic is checked without wrapping.

The caller keeps a thread context alive until join or until a detached thread has
finished. Joining twice, joining a detached thread, or detaching twice is undefined
behavior. A trap in an entry terminates the process under §11; `join` therefore
never converts a language trap into an error.

---

## 6. Statements and expressions

```
if cond { } else if cond { } else { }

while cond { }

for i in 0..n { }
for v in slice { }
for i, v in slice { }
for v in it { } // anything with a `next` (§9)

switch k {
case .Int:
    ...
case .Float:
    ...
default:
    ...
}

break
continue
ret // a void function or a kernel
ret expr
defer stmt // runs when the enclosing block exits, in reverse order
defer { ... } // the block form; the same rule
```

- `ret` with no expression is the return of a `void` function or a kernel (§10);
  `ret expr` returns a value from every other function. Either in the other's
  position is a compile error. Reaching the closing brace is an implicit `ret` only
  for a `void` function or kernel. Every reachable path in any other function must
  execute a value-returning `ret`; failure to prove that is a compile error.

- The condition of `if` and `while`, and each operand of `&&`, `||` and `!`, is
  exactly `bool`. There is no truthiness conversion.

- `switch` cases do not fall through. Cases must be compile-time constants.
- A **case body** is the statements between `case X:` (or `default:`) and the next
  `case`, `default` or the closing `}` — an **implicit block**: it has its own
  scope, a `defer` in it runs at its exit, `as v` is bound for exactly that block,
  it takes no braces and never falls through. `neper fmt` puts a case body on its own lines, indented one level; a body never shares the `case` line.
- A `switch` on an `enum` or a tagged union (§4) must be **exhaustive** unless a
  `default` case is present; a missing member is a compile error naming it.
  `case .Member as x:` binds a tagged union's payload for that case's block.
- A `switch` on any other subject — an integer, an `err`, a `bool` — need not be
  exhaustive: without a `default`, a value no case names runs nothing. A case may
  list several values, `case 1, 2:`, `case ok, os.NotFound:`. Exhaustiveness is
  required only for an `enum` and a `union enum` subject.
- Every case value has the subject's type, using the usual contextual typing for an
  untyped literal. A value may occur in at most one case, and a switch has at most
  one `default`; duplicates are compile errors. `break` exits the innermost loop or
  switch. `continue` targets the innermost enclosing loop, including from a switch
  nested inside it. There are no labels.
- `for i in a..b` runs `i` from `a` up to but excluding `b`, in the bounds' type
  (§3); a range with `b <= a` is empty, never reversed and never an error. `for v
  in s` and `for i, v in s` walk a slice or an array: `v` is a `let` **copy** of the
  element for that iteration, never a reference, so writing an element is spelled
  `s[i] = ...` through the index form; `i` is `usize`. An array is iterated as the
  slice of itself.
- `for v in it` over any other subject looks for `I`'s `next` — `fn <i>_next(it: *I)
  -> (T, bool)` in `I`'s module (§9): the loop calls it, stops on `false`, and binds
  `v` to the `T`.
  The subject must be a `var` or a `*I`, since `next` mutates it. This is what makes
  `e.data.iter`, a tree walk and a directory walk ordinary `for` loops rather than three
  different shapes. A `for` over a **comptime** slice is a different thing again — it
  is unrolled (§9).
- `defer stmt` and `defer { ... }` are both legal — a single statement, or a
  block — and either runs when the **enclosing block** exits — by reaching its
  end, by `break` or `continue` leaving a loop body, or by `ret` (a `try` that
  returns included) leaving every open block up to the function's. Deferred
  statements run in reverse order of registration, an inner block's before an
  outer's, after the `ret` expression has been evaluated; a `defer` in a loop body
  runs once per iteration. A trap (§11) and `os.exit` (§5) run none. A
  deferred call cannot `try` — there is nothing to return from — so a fallible one
  is written `defer let _ = f()` (§7). It is the arena idiom's companion: acquire,
  `defer` the release, forget it.
- Registering a `defer` evaluates the receiver and every argument of a deferred call
  immediately, from left to right, and saves their values; only the call itself runs
  at exit. A deferred block captures places rather than snapshots and evaluates its
  statements at exit. This distinction makes `defer close(f)` retain the current
  handle while `defer { inspect(x) }` observes `x` as it stands at block exit. A
  `defer let _ = f(...)` discard is a deferred call for this rule and captures its
  arguments immediately. Any other deferred single statement behaves as a one-
  statement block.
- Control may not leave a deferred body: `ret` and `try` are illegal anywhere inside
  it, and `break` or `continue` may target only a loop or switch lexically inside that
  body. A nested `defer` is legal and runs when its deferred body's own scope exits.
- There is no `goto`, no labelled break in v1, and no expression-level `if`.

### Operators

```
Arithmetic   + - * / %          (overflow of + - * checked in debug, wraps in release;
                                 integer division by zero and MIN / -1 trap in every mode — §11)
Unary        -                  (negation; -MIN is an overflow check like + - *; a compile error on an unsigned operand)
Wrapping     +% -% *%           (explicitly wrapping, all build modes)
Bitwise      & | ^ ~ << >>      (a shift count >= the width traps in debug, is masked in release)
Compare      == != < <= > >=
Logical      && || !            (short-circuit)
Assign       = += -= *= /= %= +%= -%= *%= &= |= ^= <<= >>=
Access       . [] [a..b] & *    (field, index, slice, address-of, dereference)
```

**Precedence and associativity**, tightest first. It is C's, with two changes:
every bitwise operator binds tighter than every comparison, so `a & b == c` is
`(a & b) == c`, and comparisons do not chain, so `a < b < c` is a compile error.

| Level | Operators | Associativity |
|---|---|---|
| 1 | `a.b`, `a[i]`, `a[lo..hi]`, `f(...)`, `f[...]` | left |
| 2 | prefix `-` `!` `~` `&` `*` | right |
| 3 | `* / % *%` | left |
| 4 | `+ - +% -%` | left |
| 5 | `<< >>` | left |
| 6 | `&` | left |
| 7 | `^` | left |
| 8 | `\|` | left |
| 9 | `== != < <= > >=` | none — two in a row is a compile error |
| 10 | `&&` | left |
| 11 | `\|\|` | left |

So `-a % b` is `(-a) % b`, `x << 1 + y` is `x << (1 + y)`, and `a || b && c` is
`a || (b && c)`. Assignment is a statement, not an expression: `a = b = c` does not
parse. `try` is not an operator; it prefixes one call expression and takes its
result (§7). `neper fmt` neither adds nor removes parentheses, so what is on the
page is what parses.

Integer `/` truncates toward zero and `%` takes the sign of the dividend, as in C, so
`a == (a / b) * b + a % b` always holds; `%` is defined on integers only — on a
float operand it is a compile error, and there is no `fmod` in the language. `>>` is arithmetic on a signed operand and
logical on an unsigned one. Unary `-` on an unsigned operand is a compile error:
negate through a signed type, `-i64(x)`, or write `0 -% x` for the wrapping
complement. The right operand of `<<` and `>>` is **independent of
the left**: it must be an unsigned integer type, and an untyped literal count becomes
`u32` — the one binary operand a literal does not take from the other side (§3). The
count is never converted, only checked against the left operand's width: a count
`>=` the width traps in debug and is masked in release (§11). Float `/` follows IEEE 754 in every mode — `x / 0.0` is an
infinity, `0.0 / 0.0` is NaN — and is never a check (§11, Floating point).

No operator overloading — `+` on strings does not exist and will not (§4).

`==` and `!=` apply to primitives, pointers and enums only. On slices they would
silently compare pointer and length rather than contents, which is a trap; use
`str.eq` or `mem.eq[T]`. Structs, unions and arrays are likewise compared by an
explicit function, never by operator.

### Implicit operations

This is the complete list of implicit operations in the language. §4, §10, §14 and
D18 refer here rather than restating it:

| Operation | Where |
|---|---|
| `a.b` reaches through a pointer: `p.x` where `p` is `*Vec3` or `*const Vec3` | any field access |
| `[]T` converts to `[]const T` | any use site |
| `*T` converts to `*const T` | any use site |
| `gpu.Buf[T]` is mapped onto a `[]T`, `[]const T` or `[]Atomic[T]` kernel parameter | `gpu.launch` only (§10) |
| a `for` over a `var` iterator passes the place as `*I` to its generated `next` call | compiler-generated iterator call only (§6, §9); no source expression is rewritten |

Each removes a capability or names a boundary; none changes a value's bits or its
type's width. Everything else — every widening, every narrowing, every
integer-to-float — is a cast written on the page (§4), which is what §14 invariant 6
promises.

**Operator types.** Except for shifts, both operands of a binary arithmetic,
wrapping, bitwise or comparison operator have exactly the same type after contextual
typing of an untyped literal; the language never inserts a conversion. `+ - * /`
accept any integer or float type, `%` and bitwise operators accept integers only, and
wrapping operators accept integers only. Unary `-` accepts signed integers and
floats; `~` accepts integers. Arithmetic returns the operand type. `==` and `!=`
accept integers, floats, `bool`, `err`, pointers of the same type after the one-way
const conversion, and values of the same enum type. Ordering accepts integers,
floats and values of the same enum type; enum ordering is backing-value ordering.
Pointers and function pointers have equality but no ordering. Every comparison
returns `bool`. Floating comparisons are IEEE ordered comparisons: any ordering
comparison with NaN is false, `==` with NaN is false, and `!=` with NaN is true.

**Evaluation order.** Neper evaluates subexpressions left to right. For a call it
evaluates the callee then arguments left to right; for a binary operator it evaluates
the left operand before the right; for assignment it evaluates and saves the target
place before the right-hand side; aggregate literal elements and fields are evaluated
in source order; and a multiple-return expression is evaluated once before its
results are assigned left to right. `&&` and `||` are the only operators that may
skip their right operand. A trap or early return preserves all effects already
performed and performs none to its right.

### Conditional compilation

There is no preprocessor. Target-dependent code uses `when`, which type-checks all
branches and emits one:

```
when target.arch == .X64 {
    ...
} else {
    ...
}
```

Both branches must parse and type-check, so dead configurations cannot rot.

`target` is a builtin comptime namespace: it needs no `use` and cannot be shadowed
(§2). `target.arch` is a `target.Arch`, an enum with members `.X64`, `.Aarch64`,
`.X86`, `.Spv`, `.Ptx`; `target.os` is a `target.Os` with members `.Windows`,
`.Linux`, `.Macos`, and `.None` on the GPU targets — one member per `e.os`
target (§5), so an Android host is deferred with its `os.android.e` (§17).

`when` is a **statement**, legal only inside a function body. It cannot wrap a
module-scope declaration, so invariants 2 and 7 of §14 hold without exception.
A `type`, `const` or `fn` that differs per target goes in a per-target file instead:

```
lib/e/sys.e // module e.sys on every target with no specific file
lib/e/sys.windows.e // module e.sys when target.os == .Windows
lib/e/sys.linux.e // module e.sys when target.os == .Linux
```

The rule: a file `<name>.<suffix>.e` whose suffix is an `Arch` or `Os` member in
lowercase is compiled only for that target and is module `<name>` there; a plain
`<name>.e` serves every target with no matching suffixed file. **At most one
suffixed file may match a target**: two files matching one module on one target is
a compile error. A module may also be split by architecture alone — `sys.x64.e`,
`sys.aarch64.e` — but mixing arch and os suffixes for one module is a compile error
at build time on any target matching both. Each variant is a complete module with
its own declarations, so a glob still finds it and §2 still holds.

---

## 7. Errors

`err` is a builtin distinct type. `ok` is its zero value. Error values are declared
at module scope, one per line:

```
error NotFound
error Truncated
```

### Error names and values

An error name is **module-scoped**, like every other declaration (§14 invariant 1):
`error NotFound` in `e.os` and an `error NotFound` in a module of your own are two
errors, and the module that declares one need know nothing about the other. Inside
its module an error is named bare; from any other module it is qualified through the
`use` qualifier, `os.NotFound`, exactly as a function is (§14 invariant 4).

The value of an error is the **32-bit FNV-1a hash of its fully qualified name** —
the module name from §2 plus the declared name, `e.os.NotFound`; this is the one
place FNV-1a is used, every other hash in the toolchain being xxHash64 (§12).
Nothing is numbered. The value is a function of the source text alone, so it is a compile-time
constant, legal as a `switch` case (§6); it needs no global pass; it does not change
when another module adds an error; and it is the same on every thread and in every
incremental build (§12, §15). `ok` is `0`. A name whose hash is `0` is a compile
error at the declaration, and the fix is to rename it.

Two distinct qualified names with the same hash are a collision, and it is caught
at link time. Every `.em` Interface carries the module's **error table**, value to
qualified name (§12). `neper` merges the tables of every module in the program
before the executable is written — under its own linker or `--linker=system` alike
(§13) — and rejects the link when one value maps to two names, naming both. The
merged table goes into the executable. It is what `main`'s failure line (§13), the
trap protocol (§11) and `neper test` read, and it is the only name-to-value data the
binary carries.

An `err` is **formattable**: `{}` (§4) prints the qualified name, `e.os.NotFound`,
or `ok`. A value absent from the table — reachable only through `undef` (§5) or a
`union` pun — prints as `err(0x<value in hex>)`, `err(0xCDCDCDCD)` for `undef`
storage.

```
use e.os

let (entries, e) = os.readdir(a, path)
switch e {
case ok:
    ...
case os.NotFound:
    ... // qualified: the error belongs to e.os
default:
    ret e
}
```

Fallible functions declare `err` as their last return value (§5):

```
error NotFound

fn read(path: str, a: *mem.Arena) -> ([]u8, err) {
    var out: []u8 = zero
    ...
    ret (out, NotFound)
}
```

`try` propagates: it evaluates the call, returns early if the `err` is non-`ok`, and
yields the remaining values otherwise. It is only legal in a function whose last
return element is `err`. On that early return every other return slot holds the
**zero value** of its type, so a caller that ignores the `err` sees a definite value,
never stack garbage.

### Zero values

The zero value is defined for every zeroable value type. It is what `= zero` writes
(§5), what a module-scope `var` starts as, and what `try` returns beside a failure.
`void`, `type`, function types, multiple-return lists, argument packs, `Field` and
`Member` are not value types with a zero and may not appear in any of those positions.

| Type | Zero value |
|---|---|
| integers, `usize`, `isize` | `0` |
| floats | `+0.0` |
| `bool` | `false` |
| `err` | `ok` |
| `*T`, `*const T`, function pointers | `nil` |
| `[]T`, `[]const T` | `nil` — `{ ptr: nil, len: 0 }`; `nil` is its spelling in expression position (§4) |
| `[N]T` | `N` zero values of `T` |
| `struct` | every field zero; padding bytes zero |
| `union` | every byte zero |
| `union enum` | tag `0` — the first member — with a zero payload |
| `enum` | the member whose backing value is `0` |
| `Vec[T, N]`, `Atomic[T]` | every lane, or the wrapped value, zero |
| `Mask[T, N]` | every lane `false`; register-only (§4), so `= zero` on a local and a `try` return slot are the only places it is written |

A type has a zero value unless it contains, at any depth — a field, an element, a
payload — an `enum` with no member at `0`. For such a type `= zero`, a module-scope
`var` without an initialiser, and `try` in a function returning it are compile
errors naming the outermost type and the offending field. Every other type has one,
which is why library types built from structs need no rule of their own. The
comptime-only types `meta.Field` and `meta.Member` (§9) are outside the table and
outside that rule: neither has a zero value and neither needs one, because neither is
ever storage — not a field, an element, a local or a pointee — so no `= zero`, no
module-scope `var` and no `try` return slot can name one.

```
let entries = try os.readdir(a, path)
```

### Where `try` may appear

`try` is a **statement-level form**, not an operator inside an expression. It is legal
in exactly three positions:

The spelling is deliberately the keyword `try`, never `?call()`. Both are normally
one lexical token and their model-token cost depends on the tokenizer, while the word
is searchable, announces control flow to a reviewer, and leaves `?` available if an
optional-type proposal ever earns it. The benchmark in `docs/tooling.md` §9 measures
the cost rather than inferring it from character count.

```
try str.push(&b, name) // whole statement; callee returns only `err`
let entries = try os.readdir(a, path) // the entire initialiser of a `let` or `var`
l.items = try mem.alloc[T](a, n) // the entire right-hand side of an assignment
```

Anywhere else is a compile error naming the position: inside an argument list
(`f(try g())`), as an operand (`(try f()) + 1`), inside a literal, an index or a
condition, or after `ret`. Write the temporary:

```
let v = try g()
f(v)
```

This is the same stance the language takes everywhere else — assignment is a
statement, there is no expression-level `if`, comparisons do not chain (§6). Control
flow lives at statement level, and `try` is control flow: a `try` buried in an
argument list is a return point in the middle of an expression, and the arguments to
its right silently never evaluate. One line per return point costs a temporary and
buys a reader who can see every exit from a function by scanning the left margin.

When the call returns more than one non-error result, the binding or assignment names
all of them: `let (a, b) = try f()` and `(a, b) = try f()`. The parenthesized list is
the existing multiple-return binding syntax, not a tuple value. A whole-statement
`try f()` is legal only when `err` is the call's sole result.

Two positions have no enclosing function to return from, so `try` in them is a
compile error with no alternative spelling:

- **Inside `defer`.** A deferred call runs *during* a return; there is nowhere to
  propagate to. A deferred call that returns an `err` is written
  `defer let _ = f()` — discarding it deliberately — or the callee returns `void`.
- **Lexically inside a `const` initialiser, `when` condition, `[...]` argument or
  comptime-only call expression** (§9). Those initiating expressions have no
  enclosing function to return from. A normal helper function reached dynamically by
  the interpreter may contain `try`; if its error reaches the initiating expression,
  evaluation fails with a compile error naming that root and the call chain. This is
  the lexical/dynamic distinction used whenever this document says “comptime
  context.”

To handle rather than propagate, destructure:

```
let (entries, e) = os.readdir(a, path)
if e != ok {
    ...
}
```

There are no exceptions, no unwinding, and no error payloads. An `err` is a 32-bit
value; carrying detail is the caller's business.

---

## 8. Memory

There is no global allocator and no `malloc`. Memory is either stack storage or
comes from an arena you created.

```
type Arena = struct {
    base: *u8,
    cap:  usize,
    off:  usize,
}

type Stats = struct { used: usize, capacity: usize }

error Exhausted // the arena is full (§11)

fn arena_from(buf: []u8) -> Arena
fn alloc[T: type](a: *Arena, n: usize) -> ([]T, err) // aligned to align_of[T]
fn mark(a: *Arena) -> usize
fn reset(a: *Arena, m: usize)
fn copy[T: type](dst: []T, src: []const T) // dst.len < src.len is a bounds check (§11)
fn eq[T: type](x: []const T, y: []const T) -> bool // element-wise value equality; padding is ignored
fn cast[P: type, Q: type](p: Q) -> P // intrinsic (§4); P and Q are pointer types; Q is inferred
fn bitcast[T: type, U: type](x: U) -> T // intrinsic (§4); U is inferred and its size equals size_of[T]
fn address_of[T: type](p: *const T) -> usize // intrinsic; T is inferred; the address as a number
fn size_of[T: type]() -> usize // intrinsic, comptime: §4's layout
fn align_of[T: type]() -> usize // intrinsic, comptime
fn stats(a: *const Arena) -> Stats // derived from off and cap; allocates nothing
```

`alloc` returns `Exhausted` when `n` elements do not fit, the one `err` in §11's
table, and `copy` returns nothing: its only failure is a bounds violation, which is
a check. `copy` has `memmove` semantics — `dst` and `src` may overlap. `stats` derives both
its fields from the arena as it stands — `used` is `off`, `capacity` is `cap` — and
does nothing else, so "how much of this arena did that phase use" is an ordinary line
in every build mode. An `Arena` carries no counters: a high-water mark across `reset`
calls and a count of allocations would each cost a branch and a store in every
`alloc`, and `alloc` being a bump and a bounds compare is what D3 buys. `size_of` and `align_of` are compile-time constants and the only way to
name a type's size. `mem.cast[P](p)` explicitly fills the first comptime parameter
and infers trailing `Q` from `p` under §9; both must be pointer types, and the
intrinsic then applies §4's pointer-cast rules. `mem.bitcast[T](x)` similarly infers
trailing `U` from `x`: `x` is a value of
any type whose size equals `size_of[T]` — a mismatch is a compile error naming both
sizes — and the result is `x`'s bytes read as a `T`, so a pun never needs a `union`
(§4). It is legal only when both types are sized and neither contains a pointer,
slice, function pointer, `type`, `Atomic`, or target address-space value at any depth.
This prevents it from casting away `const`, inventing provenance, changing an address
space or manufacturing a callable address. A pointer or slice operand in device code
is `mem.cast` by another name and is banned with it.

`mem.address_of(p)` is the other direction, and the only one there is: `p`'s address as
a `usize`, with `T` inferred from the pointer. It is not a `bitcast` — that rule refuses
every type holding a pointer, so a pun can never invent provenance, cast away `const` or
manufacture a callable address, and none of the three follows from reading an address
out, because nothing comes back through it. The result is a number: there is no
conversion from an integer to a pointer, so an address that leaves a program returns
only through an interface that takes numbers, which is what a system call is (§5's
`os.syscall`) and what this intrinsic exists for. A slice is a pointer and a length and
so has no one address; `&s[0]` names the element whose address is wanted.

Reading bytes as `bool` requires the result to be `0` or `1`; reading them as an enum
or tagged-union tag requires a declared member. A violation is an `invalid` check: it
traps in debug and is unreachable behaviour in release. `undef` may create such bytes,
but reading the invalid value—not creating its storage—is the violation. A pointer
produced by `mem.cast` retains the source address, provenance, address space and
constness.

`mem.eq` compares values, not object representations. Integers, booleans, errors,
enums and pointers use their ordinary `==`; floats use ordinary IEEE equality;
arrays, vectors and structs recurse in declaration/index order; tagged unions compare
the tag and then the live payload; slices compare their elements. Padding is never read. Bare unions, atomics, masks, function pointers and
types without ordinary equality are rejected at instantiation.

The typical shape:

```
fn process(input: str, out: *mem.Arena) -> err {
    var scratch_buf: [64*1024]u8 = undef // stack; no store, poisoned in debug
    var scratch = mem.arena_from(scratch_buf[0..])
    ...
    ret ok
}
```

`mark`/`reset` give you scoped deallocation without per-object bookkeeping. A
program's root arena is a block reserved from the OS at startup; its size is **64
MiB** unless the link option `--arena SIZE` (§13) raises or lowers it. The startup
code obtains it through `e.os` (§5) before `main` runs —
`os.reserve` for the address range, then `os.commit` for the whole of it, free
under Linux overcommit, charged against the pagefile on Windows, which is why the
size is a link option rather than a large default — and passes it to `main` as its
first parameter (§13). That parameter is the only way to reach it.

An `Arena` is a cursor, not an independently copyable owner. Copying an `Arena`
value is legal only to transfer it to a new binding after the old binding is no
longer used; using two copies derived from the same value is a programmer error and
has undefined behaviour. Library APIs therefore pass `*Arena` and container structs
must not embed duplicate live cursors. `mark(a)` returns an offset valid only for that
arena. `reset(a, m)` requires `m <= a.off`; a larger mark is a bounds check. Resetting
to a mark obtained from a different arena is likewise invalid, although equal numeric
offsets cannot be distinguished at runtime and remain the programmer's responsibility.

`alloc[T](a, n)` first checks multiplication and alignment arithmetic without
wrapping. `n == 0` returns `{ ptr: a.base + a.off, len: 0 }` without advancing `off`;
the pointer may be nil only for an empty nil-backed arena and may not be dereferenced.
Invalid arena invariants (`off > cap`, a nil base with nonzero capacity,
or a base that cannot satisfy its recorded alignment) are `invalid` checks. `reset`
poisons only the released byte range in debug and leaves bytes unchanged in release.

Library values that claim the top of an arena, including `str.Builder`, follow the
same single-live-copy rule. `done` consumes that logical value: any later operation
through it or a copy is an `invalid` check in debug and undefined in release. The
implementation stores enough debug-only generation state to diagnose this without
adding release fields. A sink called by formatting may not allocate from or reset the
builder's arena and may not recursively write to the same builder; violating either
rule is an `invalid` check.

**A growable container must not hand out slices across a `push`.** `list.e`'s
`push` allocates a bigger buffer when the old one is full and abandons the old one
in the arena; a slice taken before that push still points at the abandoned buffer,
which stays readable and is silently stale. No check can catch it, because the
memory is still valid memory. Take the slice after the last push, or take it again.
The debug fill on `reset` (§11) catches the other hazard, a slice that outlives
`mem.reset`; this one is the container's contract, stated in its comment.

Because no function allocates except from an arena it was handed — `gpu.open`'s
arena on the `.Cpu` backend included (§10) — save the driver staging block of
`gpu.upload`/`gpu.write` on a driver backend (§10, D3), the compiler knows a call's
full cost from its signature — which is what makes cross-module inlining across `.em` files
cheap to reason about.

### Threads and atomics

OS threads, and nothing else. No runtime, no scheduler, no green threads, no thread
pool in the language. A scheduler would add latency and unpredictability to the one
thing neper is supposed to be good at.

```
use e.thread

fn worker(ctx: *Ctx) {
    ...
}

var ctx = Ctx{ ... }
let h = try thread.spawn[Ctx](worker, &ctx, thread.DEFAULT_STACK)
try thread.join(h)
```

`thread.spawn[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread,
err)` is `os.thread_create` (§5) under its own name, `thread.join(t: Thread) ->
err` is `os.thread_join`, and `thread.detach(t: Thread) -> err` is
`os.thread_detach`: a detached thread is never joined, and its stack is released by
its own exit path (§5). The stack size is written at every call, because neper
has no default parameters; `const DEFAULT_STACK: usize = 1024*1024` in `e.thread`
is the value to write when nothing else is called for.

**One arena per thread.** This falls out of the arena model above rather than being
added to it: there
is no global allocator, so there is nothing for threads to contend on. Arenas are not
thread-safe and are not meant to be — a shared one is a bug.

**Thread state travels in an explicit context pointer, not thread-local storage.**
Platform TLS (`__thread`, `__declspec(thread)`) costs a lookup on some platforms and
hides state that the rest of the language keeps visible. A parameter is free and
greppable.

**Atomics are builtin types**, lowering to single instructions (`lock xadd`,
`ldaxr`/`stlxr`) with no abstraction to strip. `Atomic[T]` is legal for exactly `T`
an integer type of §4 — `i8` through `u64`, `isize`, `usize` — or a pointer — `*T`,
`*const T`, `*void` or a function pointer, all word-sized;
on the CPU every one is native at its width, and §10 narrows the set to 32- and
64-bit integers in device code:

```
type Counter = struct {
    hits: Atomic[u64],
}

let n = atomic.add(&c.hits, 1, .Relaxed)
let v = atomic.load(&c.hits, .Acquire)
atomic.store(&c.hits, 0, .Release)
let (won, seen) = atomic.cas(&c.hits, old, new, .AcqRel, .Acquire)
atomic.fence(.SeqCst)
```

`atomic.init(v)` constructs an `Atomic[T]` holding `v` — `Counter{ hits:
atomic.init(0u64) }` — and is comptime-evaluable, so it is legal in a struct
literal, a `const` and a module-scope `var` initialiser; the zero value of an
`Atomic[T]` is `0` (§7), so `= zero` needs no constructor.

Orderings are `.Relaxed`, `.Acquire`, `.Release`, `.AcqRel`, `.SeqCst`, with the
acquire-release semantics of the C11/C++11 model — well understood, and a direct map
onto every target's hardware model.

**`e.atomic` is the operation surface**, every function an intrinsic (§14) and
comptime-generic on `T`, inferred from `p` — from `v`, for `init` — per §9. `T` is
any type `Atomic[T]` admits; the arithmetic and bitwise operations take an integer
`T` only, and `init`, `load`, `store`, `xchg` and `cas` take a pointer `T` as well:

```
type Ordering = enum u8 { Relaxed, Acquire, Release, AcqRel, SeqCst }

fn init[T: type](v: T) -> Atomic[T] // comptime-evaluable (above)
fn load[T: type](p: *Atomic[T], o: Ordering) -> T // o: Relaxed, Acquire or SeqCst
fn store[T: type](p: *Atomic[T], v: T, o: Ordering) // o: Relaxed, Release or SeqCst
fn xchg[T: type](p: *Atomic[T], v: T, o: Ordering) -> T // the previous value
fn cas[T: type](p: *Atomic[T], expected: T, desired: T, success: Ordering, failure: Ordering) -> (bool, T)
fn add[T: type](p: *Atomic[T], v: T, o: Ordering) -> T // the previous value; wraps, like +%
fn sub[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn and[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn or[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn xor[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn min[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn max[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn fence(o: Ordering)
```

`cas` is the strong compare-and-swap: it returns `true` and `expected` when the
exchange happened, `false` and the value it found otherwise, and never fails
spuriously. A `load` with a release ordering or a `store` with an acquire one is a
compile error, as C11 has it. A CAS failure ordering may be `.Relaxed`, `.Acquire`
or `.SeqCst`, may not be `.Release` or `.AcqRel`, and may not be stronger than its
success ordering; an invalid constant pair is a compile error and an invalid runtime
pair is an `invalid` check. The device forms are these with a scope (§10).

**There is no compile-time protection against data races.** With no ownership system
(D3), racing is the programmer's responsibility. The compiler assumes non-atomic
accesses are race-free and optimises accordingly; a race on a non-atomic location is
undefined behaviour, exactly as in C. This costs nothing at runtime, which is the
point.

Threads are a CPU-profile feature. Inside `@gpu` there are no threads, no atomics on
host memory, and no function pointers to spawn with — GPU parallelism is the launch
grid (§10).

---

## 9. Compile-time parameters

Anything in square brackets is evaluated at compile time and monomorphised per
distinct instantiation.

```
fn max[T: type](a: T, b: T) -> T {
    if a > b { ret a }
    ret b
}

type Buf[T: type, N: usize] = struct {
    data: [N]T,
    len:  usize,
}

let m = max[i32](3, 9)
var b: Buf[f32, 16] = zero
```

A comptime argument may be inferred from the value arguments whose parameter types
mention it. The inference is **unambiguous** when every such argument that is not an
untyped literal (§3) agrees on one type; the literals are then typed by the
parameter. If no argument fixes it, or two disagree, it is a compile error naming
the parameter. `max(x, 9)` with `x: i32` infers `T = i32` and types `9` as `i32`;
`max(3, 9)` is an error naming `T`; `max(3i32, 9)` is not.

Inference structurally unifies each declared parameter type with the corresponding
typed argument: qualifiers, pointers, slices, arrays and instantiated generic types
are traversed recursively, aliases are replaced by their canonical underlying type,
and array lengths may infer integer comptime parameters. Every occurrence of one
parameter must produce the same value. Explicit arguments fill parameters from the
left and inference fills only omitted trailing parameters; holes are not allowed.
Inference never uses a return context, a protocol result or an untyped literal as its
sole evidence. After inference, every literal is typed and the ordinary call rules run.

A generic declaration is parsed and name-resolved once. Rules independent of a
comptime parameter are type-checked at declaration; any operation whose validity or
type depends on such a parameter is checked at each instantiation and an error reports
both the operation and the instantiation site. There are no declared constraints:
`max[T]` is a valid template, but `max[SomeStruct]` fails unless `>` is defined for
that concrete type.

A bracket after a name **resolved to a function or a type** is a comptime argument
list; after a name resolved to a value it is an index. The concrete parser always
builds the same lossless `BracketPostfix` node and needs no symbol table; name
resolution classifies that node from the symbol table, never from its contents, and
a name is never both (§14 invariant 1). A
generic function appears in a **call** — with its bracket, or with the bracket
inferred as above — or, with its bracket written in full, in value position, where
`f[i32]` is a function pointer to that one instance (which is how
`os.thread_create[Ctx]` hands a `@cc` trampoline to the OS, §5); a generic type
appears only with its bracket. There is no pointer to a generic as such — the
inferred form is never a value — and `f[N]` with `f` a function is always an
instantiation even when `N` is a `const` that could have been an index.

A comptime parameter has a **kind**: `type` (`T: type`), an integer type (`N:
usize`), `str` (`FMT: str`), `bool`, a fixed array of an integer type (`IDX: [N]u8`,
which `simd.shuffle` takes, §4), a comptime-only struct value (`FIELD: Field`,
Compile-time introspection below), or `fn` (`K: fn`). In a comptime position a
function name is a value of kind `fn`, as a type name is a value of kind `type`. The
parameter is bound at compile time and monomorphised per function; inside the body
`K` is called like any function, and its concrete signature is visible after
instantiation. A call involving `K` is checked then; incompatible arity, parameter or
return use is an error at the instantiation site with the declaration site as a note. It is
not a function pointer and forms none, which is why `gpu.launch[K]` (§10) can take a
kernel where a pointer to device code is banned — and why any function, a device
helper included, may declare a `K: fn` parameter of its own: it is monomorphisation,
not indirection. `neper-0` (roadmap) omits the `fn` kind along with packs.

A type expression in a declaration may refer to earlier comptime parameters and to
comptime fields of their values. It is evaluated at instantiation before the body is
checked, which is why `FIELD.ty` can be the result of `meta.get`. It may not refer to
a runtime parameter or a later comptime parameter. This is ordinary dependent
specialization of a monomorphised declaration, not runtime dependent typing, and is
available to user declarations under the same rule as the `e.meta` intrinsics.

**A comptime expression whose type is `type` may be written wherever a type is
written.** It is evaluated at the instantiation like any other comptime expression,
and what it yields is a type in every respect — a return type, a parameter type, a
local's annotation, a `[...]` argument, a protocol receiver. Two forms occur, both in
Compile-time introspection below: `FIELD.ty` as the return type of `meta.get`, and
`f.ty` as the receiver of `f.ty.format(x, b)`.

`const` initialisers are evaluated by the same compile-time interpreter, under the
rules of the next subsection — enough to build lookup tables at compile time.

### Compile-time evaluation

One interpreter evaluates four things: every `[...]` argument, every `const`
initialiser, every `when` condition (§6), and every call to a **comptime-only** core
function — `meta.fields`, `meta.members`, `meta.type_name` (Compile-time
introspection, below) — standing in an ordinary function body with every argument
comptime-known, which is evaluated at the enclosing instantiation and its result
folded in exactly as a `[...]` argument's is. Those four sites are what **comptime
context** means throughout this document, and a comptime-only function called
anywhere else — with an argument the compiler cannot know at that site — is a
compile error naming the function and the argument. It runs neper, not a
second language: any function is callable
at compile time unless its evaluation reaches **runtime state**, which is exactly
this list:

- a module-scope `var`, read or written;
- an `Atomic[T]` operation other than `atomic.init`, or `atomic.fence` (§8);
- `thread.*`, and every `extern` call (§5) — all of `e.os`, `os.syscall`
  included;
- the `gpu.*` builtins and host API (§10).

Everything else is legal: stack arrays, pointers, slices, `union` punning,
`mem.arena_from` over a comptime array and `mem.alloc` from it, `try` inside a function the interpreter executes, `defer`,
`switch`, generic instantiation, `unreachable()` (which fails the evaluation).
Reaching runtime state is a compile error naming the `const` — or the comptime
argument — and the call chain from it to the offending operation.

**Memory.** Interpreter memory is a byte-addressed arena owned by the compiler, one
per evaluation. Every stack frame, array and arena buffer the evaluated code creates
lives in it; `&x`, slicing and `mem.cast` yield addresses into it; and a load or a
store reinterprets the bytes at that address in the **target's layout** — the field
offsets, sizes and alignment of §4 for the target being compiled, and the target's
endianness. `union` punning at compile time therefore gives the bytes the target
would give: writing `.i` and reading `.f` on a `Value` produces the same bits at
compile time as at runtime, and the C bootstrap and the self-hosted compiler must
agree byte for byte here, which is what the M2 determinism harness (roadmap) checks.
A comptime result is target-independent only where its type has no target-dependent
size — `usize`, `isize` and pointers are the target-dependent ones — which is one
reason `.em` files are per target (§12).

**Results.** A `const`'s final value must be **pointer-free**: no `*T`, no `[]T`,
with one exception — a `[]const u8` that refers to **read-only data the compiler
emits**: a string literal, or a compiler-synthesised name, which is what
`meta.type_name[T]()` and a `Field`'s or `Member`'s `name` return (Compile-time
introspection, below). Either has an
address in the executable's read-only data. A value that violates this — a slice into
interpreter memory, a pointer to a comptime stack frame — is a compile error naming
the `const` and the field or element holding the pointer. Everything the value was
built from is discarded when the evaluation ends; the value itself is serialised
into the `.em` (§12) and folded into every use as an immediate or a read-only data
reference.

**Budget.** One evaluation — one `const`, one comptime argument, one `when`
condition, or one comptime-only call folded into a body — is bounded to
**10,000,000 interpreter steps** (one NIR instruction each), a **call depth of
1024**, and **64 MiB of interpreter memory** (the arena above). Exceeding any of the
three is a compile error naming the `const` and the call chain at the point the
budget ran out. The budget is per evaluation, not per module, and
there is no flag to raise it: a table that needs more than ten million steps is
generated into source by a program, where the reviewer can see it. A build cannot
hang on a `const`.

**Caching.** An evaluation's cache key contains the canonical typed root expression,
the fully typed bits of every comptime argument, the target triple and data-layout
version, build mode, language and `.em` format versions, and the body hashes (§12) of
every function it executed. Read-only string values are keyed by contents, not their
temporary interpreter address. A callee edit, argument change, target change or
semantic-version change therefore misses the cache. Pointer equality during an
evaluation compares `(allocation identity, offset)` pairs; allocation identities are
local to that evaluation, deterministic in execution order and may never appear in a
serialized result.

### Protocols

A generic function often needs an operation on its type parameter — hash this key,
compare these two, print that. neper has no interfaces, no traits and no closures, so
the operation is found by **name, at compile time, in the module that declares the
type**.

```
fn get[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool) {
    var out: V = zero
    let h = K.hash(key)
    ...
    if K.eq(m.keys[i], key) {
        ret (m.vals[i], true)
    }
    ret (out, false)
}
```

`K.hash(key)` resolves, at the instantiation, to **`fn <k>_hash`** in the module that
declares `K`, where `<k>` is `K`'s own name in `snake_case`: `Sensor.hash` is
`fn sensor_hash`, `Vec3.format` is `fn vec3_format`. Conversion to snake case scans
Unicode scalar values: a boundary precedes an uppercase letter following a lowercase
letter or digit, and precedes the last uppercase letter of a run when the next letter
is lowercase; ASCII capitals are lowercased, digits and existing underscores are
retained, and adjacent underscores collapse to one. Thus `HTTP2Client` becomes
`http2_client`. Instantiate `get[Sensor, f32]` and the call is a direct call to
`sample.sensor_hash`.

Instantiate `get[str, f32]` and there is no such call, because `str` is the
language's own alias of the structural type `[]const u8` (§4, D48), which has no
declaring module: rule 4 below supplies the slice `hash`, over the bytes. An alias of
a **named nominal type** keeps that type's canonical declaration, declaring module
and protocol name; an alias of a primitive or structural type has none. Protocol
lookup therefore never depends on which alias spelling appears at a call site.

For an instantiated nominal generic type, the protocol stem is the declaration's
uninstantiated name and the matching protocol function carries the same leading type
parameters. For `type Box[T: type] = struct {...}`, lookup for `Box[i32].hash`
requires `fn box_hash[T: type](v: Box[T]) -> u64` and instantiates it with `i32`.
A non-generic declaration with one concrete `Box[...]` parameter is not the protocol
for the generic type; users call such a specialization by its module-qualified name.

The type's name is in the function's name because §14 invariant 1 admits no
overloading: a module that declares `Sensor` and `Reading` would otherwise need two
`fn hash` lines, and `grep -n "^fn hash"` would stop returning exactly one. Prefixing
keeps one definition per name, keeps every protocol function greppable on its own, and
lets one module carry protocols for as many types as it declares.

Five rules keep this from becoming a second way to call a function:

1. **`T.f(...)` is legal only where `T` is a comptime type parameter or a comptime
   type value.** On a type you can name you write the module qualifier — `str.eq(a, b)`
   — because you know the module. The receiver need not be a name: any expression
   whose type is `type` and whose value is comptime-known stands there, which is what
   `f.ty.format(...)` in the introspection example below is (§2). The rule governs
   what an author **writes**; a protocol call the compiler generates on the author's
   behalf — a `for`'s `next` (§6), a format verb's `format` (§4), a container's
   `hash`, `eq` or `cmp` on a concrete element type — appears on no line and is
   outside it. §14 invariant 4 is untouched: every call site whose module is
   knowable, and that someone wrote, names it.
2. **Type-level names win.** Enum members, `<Union>.Tag` and the builtin type
   operations of §4 — `T.trunc(x)`, and the cast `T(x)` — resolve before protocol
   lookup, so `Kind.Int` is the member, `Node.Tag` is the tag type and `T.trunc(x)`
   is the truncating cast whatever the declaring module happens to declare. A member
   and a protocol name can never collide in the first place: §3 spells members
   `PascalCase` and functions `snake_case`.
3. **The first parameter is the type, by value**: `fn sensor_hash(v: Sensor)`, never
   `*Sensor` or `*const Sensor`. A pointer form would need an implicit address-of at
   `T.hash(key)`, a sixth implicit operation §6's closed list does not have; and by
   value costs nothing, since §5 already passes an aggregate larger than two machine
   words by hidden reference. A declaration with the required protocol name but an
   incompatible signature is a hard error at the instantiation site; it never falls
   back, and the diagnostic prints the required and found signatures. `next` is
   the one exception, because its subject is the **iterator** and not an element
   type: it takes `*I`, which is why §6 requires a `for`'s subject to be a `var` or a
   `*I`.
4. **A supplied fallback stands wherever the type's own module declares none.** The
   compiler supplies `hash`, `eq` and `format` for the integers, floats, `bool`,
   `err`, pointers, slices, arrays, `Vec`/`Mask`, and every `enum` and `union enum`;
   it supplies `cmp` for the same set except pointers. For a type of one of those shapes the supplied one is used whenever
   its declaring module declares no `fn` of that name, and whenever it has no
   declaring module at all — a structural alias such as `str` has none (§4, D48) — while a
   `fn` declared in the type's own module always wins over it. A shape outside that
   list, a `struct` being the one that matters, has no fallback, and a missing `fn`
   there is rule 5's error. A slice's `eq` and `hash` are over its contents, which is
   what §6 refuses to give `==`; what the supplied `format` writes for each shape is
   §4's Formatting subsection, and this rule is the authority on which types have
   one. Integer, boolean, error and enum fallbacks use ordinary operators and hash
   canonical little-endian value bytes with xxHash64 seed 0. Pointer equality and
   hashing use the address through the same hash;
   `cmp` is not supplied for pointers. Container float equality treats all NaNs equal
   and both zeros equal, hashing canonicalizes every NaN to one quiet NaN and `-0` to
   `+0`, and float `cmp` is IEEE `totalOrder` after that canonicalization. Arrays,
   slices, vectors and tagged unions recurse in index or declaration order, including
   the tag before the live payload. Every lookup that lands on a fallback is recorded as a lookup edge, so
   declaring the `fn` later is not silently ignored (§12, D36).
5. **A missing function is an error at the instantiation site**, not inside the generic
   body, and it names what is missing and where it goes:
   `instantiating map.get[Vec3, f32] needs fn vec3_hash(v: Vec3) -> u64 in module
   shapes (src/shapes.e); none is declared`.

The names the standard library looks for, by convention rather than by rule:

| Spelled, for a type `Sensor` | Looked for by |
|---|---|
| `fn sensor_hash(v: Sensor) -> u64` | `e.data.map`, hash-based containers |
| `fn sensor_eq(a: Sensor, b: Sensor) -> bool` | `e.data.map`, containers, `e.test` |
| `fn sensor_cmp(a: Sensor, b: Sensor) -> i32` | `e.algo.sort`, ordered containers |
| `fn sensor_format(v: Sensor, b: *str.Builder) -> err` | `printf`/`format` on a user type (§4), `e.log` |
| `fn window_next(it: *Window) -> (T, bool)` | `for` (§6), `e.data.iter` |
| `fn window_next_err(it: *Window) -> (T, bool, err)` | fallible iterator algorithms; never implicit language `for` |

This is not an interface system. Nothing is declared, nothing is implemented, no type
is a subtype of anything, and no value carries a tag. It is name lookup that happens at
compile time, and it costs nothing: the call is direct, monomorphised, inlinable, with
no vtable and no dispatch. `grep -n "^fn sensor_hash"` returns the one line that will
run, from anywhere in the tree.

`next` is deliberately infallible because a language `for` has no visible propagation
site. I/O and parser iterators expose `next_err`; a generic library calls
`I.next_err(it)`, and ordinary code calls the declaring module and destructures or
uses statement-level `try`. The `bool` says whether a value was produced; on
non-`ok` error it is false and the value is its zero value. End of stream is
`(zero, false, ok)`, so end and failure cannot be confused.

### Compile-time introspection

`e.meta` enumerates a type's structure while compiling, and its surface splits in
two. `fields`, `members` and `type_name` are **comptime-only**: they return comptime
values, and calling one outside a comptime context (Compile-time evaluation, above)
is a compile error. `get` and `set` are **comptime-parameterised**, not
comptime-only: only their `FIELD` argument must be comptime, each compiles to an
ordinary field load or store at the offset `FIELD` names, and each is therefore legal
in any body, at runtime, exactly as `v.x` is.

```
type Field = struct {
    name:   str,
    ty:     type,
    offset: usize,
    size:   usize,
}

type Member = struct {
    name:  str,
    value: u64,
}

type TypeKind = enum u8 {
    Int, Float, Bool, Err, Pointer, Slice, Array, Struct, Enum, UnionEnum, Vec,
}

fn fields[T: type]() -> []const Field // struct, or a union enum's payloads
fn members[E: type]() -> []const Member // enum, or a union enum's tags
fn type_name[T: type]() -> str // "shapes.Vec3"
fn kind[T: type]() -> TypeKind
fn element_type[T: type]() -> type // array, slice or Vec; otherwise a compile error
fn array_len[T: type]() -> usize // array or Vec; otherwise a compile error
fn backing_type[E: type]() -> type // enum or union-enum tag; otherwise a compile error
fn get[FIELD: Field, T: type](v: *const T) -> FIELD.ty
fn set[FIELD: Field, T: type](v: *T, x: FIELD.ty)
```

`Field` and `Member` are **comptime-only types**, in the sense §4 gives
register-only `Mask[T, N]`: each is legal as a comptime value and nowhere else — a
comptime parameter, a comptime binding, an element of a comptime slice — and is never
a struct field, an array element, a runtime local or the pointee of a pointer.
`mem.size_of` and `mem.align_of` on either is a compile error, because a `type`-valued
field has no layout to name; neither has a zero value (§7); and neither crosses
`extern` (§5) or reaches device code (§10).

`Member.value` is a `u64` holding the member's backing value **read as two's
complement**, so a member of an `enum i64` with a negative value and a member of an
`enum u64` above `2^63` both fit one field; cast it back through the enum's own
backing type, obtained with `meta.backing_type[E]()`, where the sign matters.

`kind`, `element_type`, `array_len` and `backing_type` are comptime-only with the same
rules as `fields`. They provide enough shape information for a format module to
decode primitives, arrays, vectors, enums and structs recursively. Tagged unions are
not generically constructible in v1 because associating a runtime tag with a
different payload type requires dynamic type selection; a format decoder requires a
type-owned `fn <t>_decode_<format>(...) -> (T, err)` protocol for that shape. Bare
unions, pointers and function pointers likewise require a type-owned decoder or are
rejected by the format module. The language does not pretend that output-only
`format` is a decoder.

`fields` on a bare `union` is a compile error: its members overlap by design (§4) and
there is no fact about which one is live. `meta.get[FIELD, T]` and
`meta.set[FIELD, T]` require that `FIELD` be an element of `meta.fields[T]()`; a
`Field` of any other type is a compile error naming both types, so a field of one
struct is never read at its offset in another.

For a tagged union, `fields` returns one entry for each payload-bearing variant in
declaration order; payloadless variants have no `Field`. Its `name` is the variant
name, `ty` the payload type, and `offset`/`size` the selected target layout. `get`
and `set` additionally require the value's live tag to match that field: the ordinary
tag check of §11 applies. `members` returns every tag, including payloadless ones, in
declaration order. Reflection therefore exposes layout but does not select a runtime
payload type; generic code switches on the tag or uses a type-owned decoder.

**A `for` whose subject is a comptime value is always unrolled.** The interpreter
unrolls it, and the loop variable is a distinct comptime value in each copy — which is
what lets the body use it in a comptime position: a `[...]` argument, a type, a
protocol receiver. There is no condition on the body, because the alternative is a
`[]const Field` surviving to runtime, and that is the type table D53 forbids. The §9
step budget bounds the unrolling. Nothing survives to runtime but the bodies.

Together with protocols that is enough to write one function that serialises every
struct in the program:

```
fn format_struct[T: type](v: *const T, b: *str.Builder) -> err {
    try str.push(b, meta.type_name[T]())
    try str.push(b, "{ ")
    for f in meta.fields[T]() {
        try str.push(b, f.name)
        try str.push(b, ": ")
        try f.ty.format(meta.get[f, T](v), b)
        try str.push(b, " ")
    }
    try str.push(b, "}")
    ret ok
}
```

Every rule that body needs is one of the above. `meta.type_name[T]()` and
`meta.fields[T]()` are comptime-only calls with comptime-known arguments standing in
an ordinary body — the fourth comptime context, folded at the instantiation. `f` is a
**comptime binding from an unrolled `for`**, spelled `snake_case` like any other
local binding (§3). `f.ty` is a comptime expression of type `type`, so it stands
where a type stands and where a protocol receiver stands (above). `meta.get[f, T](v)`
passes a comptime-only struct value as a comptime argument and compiles to one field
load at `f.offset`, which is why it may run at runtime while `meta.fields[T]()` may
not. And `f.ty.format(...)` is a protocol call whose receiver is a comptime type
value, which is exactly what rule 1 admits and what §14 invariant 4 excepts.

`e.fmt.json`, `e.cli` filling a config struct from `argv`, `e.log` writing structured
fields and an `x.<owner>.db.*` driver mapping a row are the same shape. Without this each of them needs
hand-written marshalling per type, which is the boilerplate generated code gets wrong
most often.

The **enumeration** is compile-time only, and that is the whole point: there is no
type table in the binary, dead-code elimination still removes what nothing calls, and
the loop above is gone by codegen — what the emitter sees is the straight-line pushes
and field loads you would have written by hand. Runtime type inspection remains a
non-goal (§1).

### Argument packs

A trailing parameter declared `...` accepts a comptime-known list of arguments. The
function is monomorphised per distinct argument shape, so there is no `va_list`, no
runtime type information, and no boxing — the pack is gone by codegen.

```
fn printf[FMT: str](args: ...) -> err // e.io
fn format[FMT: str](a: *mem.Arena, args: ...) -> (str, err) // e.str
fn launch[K: fn](q: *gpu.Queue, g: gpu.Grid, args: ...) -> err // e.gpu
```

**In v1 a `...` parameter appears only in these three functions, and all three are
compiler intrinsics** (§14). No user code and no other core function can declare
one: `...` in any other signature is a compile error (the C variadic on an `extern`,
§5, is a different thing with a different rule). There is no pack API — no
`args.len`, no iteration, no per-element type query — because a pack exists only for
the compiler to expand: `printf` and `format` expand against the format string into
straight-line pushes, and into a call to a type's own `format` where the argument has
one (§4, Protocols above); `launch` checks the pack against the parameter list of the
`@gpu` function `K` names (§10). Packs are comptime-only: there are no runtime
variadics in neper, and a pack cannot be stored, forwarded at runtime, or inspected.

This is a language exception, and it is recorded as one (D19): three intrinsics
behind a token, not a general mechanism the library could have written. It is the
cheaper of the two honest choices — a comptime pack API with length, indexing and
type dispatch is an interpreter feature with rules of its own — and the three cover
what formatting and kernel launch need. Opening `...` to user code is deferred, not
undecided: it needs that API, and nothing in `lib/e` or the self-hosted compiler
needs it.

Together, comptime parameters, evaluation and these three intrinsic argument packs
cover the use cases that this specification accepts in place of conventional
generics, macros and `#define` constants. Argument packs themselves do not replace
generics, and v1 exposes no additional metaprogramming mechanism.

---

## 10. The GPU profile

A function marked `@gpu` is compiled for GPU targets **and** for the CPU. The CPU
build is not a fallback for production — it is the debugger. Set a breakpoint, step
a single work item, inspect memory, then run the same kernel on the device.

```
use e.gpu

@gpu(256) // workgroup size: 256 invocations along x
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x // u32
    if i >= n { ret } // the grid is rounded up to whole workgroups
    let k = usize(i) // indices are usize (§3)
    y[k] = a*x[k] + y[k] // a multiply, then an add; never fused (§11)
}
```

### Platforms

Two GPU backends, both compute-only. There is no graphics pipeline — no vertex or
fragment stages — and none is planned.

| Backend | Runtime | Reaches |
|---|---|---|
| SPIR-V | Vulkan compute | AMD, NVIDIA, Intel, Qualcomm, ARM Mali — on Windows and Linux; on macOS through the supported second-tier MoltenVK path below |
| PTX | CUDA driver | NVIDIA only, with access to CUDA-side interop |

The floors: **Vulkan 1.2** with the `bufferDeviceAddress` and `scalarBlockLayout`
features, which is what gives a device slice a real address (Device types and
slices, below); **PTX ISA 6.0 on `sm_50`**, with `--cpu sm_50 | sm_70 | sm_80 |
sm_90` (§13) selecting a level above it for a `ptx` module — standalone, or embedded
by a host build, since `--cpu` is given once per target family (§13) — `sm_50` the
default.
Everything optional beyond a floor is a capability (Capabilities, below).

**Apple GPUs.** Apple ships no Vulkan. neper reaches Apple GPUs through
**MoltenVK** — Vulkan translated onto Metal — and that path is *supported but
second-tier*: it is exercised in CI, bugs in it are real bugs, but performance and
feature parity with native backends are not promised, and Metal-only capabilities are
not exposed. A native **Metal backend** (Metal Shading Language or AIR, plus a Metal
runtime) is scheduled as **M5**, after the core CPU and GPU targets land. It is
sequenced there and not earlier because a GPU backend is the most expensive kind of
target to add — an emitter *and* a runtime — and Apple is one vendor.

This is a decision, not an omission. Until M5, "runs on a Mac GPU" means "runs
through MoltenVK".

**Capabilities are per device, and they are checked at launch.** `f64` and `f16`
arithmetic, subgroup operations and 64-bit atomics are optional on real
hardware — SPIR-V gates them behind capabilities, and consumer GPUs frequently lack
`Float64` or run it at a fraction of `f32` speed. A kernel that needs a capability
the device lacks fails at `gpu.launch` with `gpu.Unsupported`, naming the kernel and
the capability. It cannot be a compile-time error, because the compiler does not
know which device the binary will meet.

Not targeted, and not planned: DirectX/DXIL, WebGPU, ROCm/HIP interop (AMD is served
through Vulkan), and OpenCL.

### What runs where

One source tree, one program, one binary: the GPU module is embedded as data in the
executable and loaded by the CPU side at runtime. Which GPU targets a build embeds
is the `--gpu` option (§13, GPU targets in a build). Partitioning is explicit —
neper never decides for you what runs where.

| Code | Compiled for |
|---|---|
| Plain `fn`, reached only from CPU code | CPU |
| `@gpu fn` | GPU **and** CPU |
| Plain `fn` reached from a kernel | Both, by inference |

The third row is what keeps `@gpu` from spreading. A helper like `dot(a, b)` needs no
annotation; if a kernel calls it, it is compiled into the kernel-owning module's GPU
output as well (§12) and must satisfy the restrictions below. `@gpu` marks kernel
*entry points* — the functions `gpu.launch` can name — not everything the device
executes. A helper that uses any `gpu.*` builtin — `gpu.gid`, `gpu.sid`, a barrier,
a `gpu.atomic_*` or subgroup builtin — or names a `shared` type (Address spaces,
below) is **device-only**: callable from a kernel or another device-only helper, and
a compile error to call from plain CPU code, where those builtins have no value (D24).

### Restrictions inside `@gpu`

| Banned | Reason |
|---|---|
| Recursion | No call stack of unbounded depth |
| Function pointers | No indirect calls |
| Module-scope `var` | No mutable global state |
| `try` lexically in the `@gpu` entry function | A kernel entry point returns nothing, so there is nothing to propagate to; `err` is an ordinary value in device code, and reached plain helpers may return `(T, err)` and use `try` among themselves (Device types and slices, below) |
| Arbitrary pointer casts (`mem.cast`) | Address spaces are distinct |
| `extern` calls (§5) | The device has no OS and no import table |
| `thread.*`, `atomic.*` (§8) | GPU parallelism is the launch grid; host atomics have no scope — device atomics are `gpu.atomic_*` (below) |
| `&x`, `x[lo..hi]` on a **private** variable — a `let`, `var` or by-value parameter holding an array, a struct or a scalar in the invocation's own storage | A function-storage pointer cannot be re-based or passed in SPIR-V (Device types and slices, below). A slice parameter or local points at buffer or shared memory, so `x[lo..hi]` and `&x[k]` on it are allowed; a `shared var` is workgroup storage, not a local, and may be sliced and addressed (Shared memory, below) |
| `= undef` (§5) | Nothing on the device fills it; a `shared var` is the one storage in device code with unspecified contents (below) |
| A bare `union` (§4) | SPIR-V's logical addressing cannot reinterpret a local's bytes; `mem.bitcast[T]` (§8) is the pun, and a variant type is a `union enum`, laid out with non-overlapping payloads in device code (Device types and slices, below) |
| `usize`, `isize` in a kernel parameter or a `Buf[T]` element | Their width differs between `spv` and the CPU (below); as locals they are legal |
| `gpu.barrier()` or a subgroup builtin in divergent control flow | Undefined on the device; a `barrier` trap in the CPU build (below) |

Violations are reported at the `@gpu` function that introduces them, with the call
chain that reaches the offending construct.

### Kernels and workgroups

A kernel is a function carrying `@gpu(X)`, `@gpu(X, Y)` or `@gpu(X, Y, Z)`. The
integer literals are its **workgroup size** — invocations per workgroup along each
axis; an omitted axis is `1`. Bare `@gpu` on a function is a compile error naming it:
the workgroup size is what `gpu.lid`, a `shared var` and `gpu.barrier()` are defined
against, so it is on the page, not in a default. It compiles to `LocalSize` in SPIR-V
and to the block size at launch in PTX. Options may follow the integers: `caps(...)`
and `ftz` (Capabilities, below).

Each workgroup dimension is a positive untyped integer literal representable in
`u32`; their product is computed without wrapping and may not exceed 1,024, the
language-wide compile-time ceiling. The device may impose a smaller per-axis or
product limit, checked at launch as `Unsupported`. Each option may occur at most once;
`caps` contains no duplicate member. An unknown option, zero dimension, fourth
dimension or overflow is a compile error at the attribute.

```
@gpu(256)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) { ... }

@gpu(16, 16)
fn transpose(n: u32, src: []const f32, dst: []f32) { ... }
```

Inside a kernel and every helper it reaches, these are values, not calls:

```
gpu.gid // global invocation id, .x .y .z, each u32
gpu.lid // id within the workgroup: 0 <= lid.x < X, and so on
gpu.wgid // workgroup id
gpu.sid // id within the subgroup (Subgroups, below)
```

`gpu.gid`, `gpu.lid` and `gpu.wgid` have the type `gpu.Id` — `type Id = struct {
x: u32, y: u32, z: u32 }` (Host side, below) — so an id is passed to a helper, or
held in a local, under that name; `gpu.sid` is a `u32`.

`gpu.launch[K](q, g, ...)` takes a `gpu.Grid`, an **invocation count** per axis —
`gpu.grid1(n)` is `n` invocations along `x` — and converts it into a workgroup count
by dividing by `K`'s workgroup size and rounding **up**. The invocations in the
rounded-up remainder run; their `gid` lies at or beyond the grid, and the kernel
guards against them, as `saxpy`'s `if i >= n { ret }` does. A workgroup count beyond
the device's limit (Vulkan guarantees 65,535 per axis — 16.7M invocations along one
axis at 256) fails at launch with `gpu.TooLarge`; a workgroup size the device cannot
run (128 invocations are guaranteed, 256 is near-universal, 1,024 is every desktop
part) fails with `gpu.Unsupported`, naming the kernel and the limit.

A zero invocation count on any axis makes the launch an ordered no-op. Grid values,
rounding and products are checked with non-wrapping arithmetic before submission;
an axis above `u32` range or a rounded workgroup count above the backend limit is
`TooLarge`. Consequently every observable `gid`, `lid` and `wgid` fits its `u32`
type.

A kernel returns `void`, takes no comptime parameters, and each of its parameters is
a device storage type or a device slice (below). **`gpu.launch[K]` is its only caller, on
both profiles**: a direct call to an `@gpu` function from CPU code, from another
kernel or from a helper is a compile error naming it, because outside a launch
`gpu.gid`, a `shared var` and `gpu.barrier()` have no meaning. On the CPU the
launch runs the kernel's CPU build (CPU execution model, below).

### Device types and slices

**Device storage types.** A type is a device storage type when it is a fixed-width integer (`i8`
through `u64`), a float, an `enum`, `err` (a `u32` in every layout, §7), a
`Vec[T, N]` of those (§4), an `Atomic[T]` with `T` a 32- or 64-bit integer, or a
`struct`, `[N]T` or `union enum` composed of device storage types. A bare `union` is not a
device storage type and is banned in device code altogether (Restrictions, above). Not device
storage types: `usize` and `isize` — their width differs between `spv` and the CPU (below),
so a struct holding one would have two layouts; they are legal as locals inside a
kernel, where every index and `.len` is one, and nowhere in a buffer or an argument
block. Not device storage types either: `bool` and `Mask[T, N]` — register types inside a
kernel with no storage form in SPIR-V; a buffer holds `u8` or `u32` — and every
pointer and slice, function pointers, `*void` and `type`. `gpu.Buf[T]` requires a
device-storage `T` that is neither `union` form — a `union enum` element, at any depth, is
a compile error naming the element type, because its device layout (below) is not
its CPU layout, and a by-value kernel parameter, which crosses in the argument block
with the same layout, is under the same rule — so device memory holds plain data
and never a pointer: nothing in a buffer means something on only one side of the
boundary.

“Device-executable type” includes device storage types plus register-only `bool`,
`Mask`, local `usize`/`isize`, and device/shared pointers and slices in the positions
defined below. “Kernel argument type” is narrower: a device storage type by value or
a device slice produced from `Buf[T]`. These terms are used independently; being
legal in a register never makes a value legal in a buffer or argument block.

**`err` in device code** is an ordinary `u32`-backed value. A helper reached from a
kernel may return `(T, err)`, and helpers use `try` between themselves as on the
CPU. Only a **kernel entry point** returns nothing, so `try` anywhere in a
kernel body — which would escape the kernel — is the compile error the Restrictions
table names; a kernel reports failure by writing an `err`, or a flag, into a `Buf`.

**Layout** in a buffer is §4's — the same size, alignment and field offsets as on the
CPU — expressed to SPIR-V as explicit offsets under **scalar block layout** (Vulkan
1.2 `scalarBlockLayout`), not std430, whose `vec3` padding and array-stride rules
would give one struct two layouts. An upload is therefore a memcpy. A `union enum`
in device code is the exception, and the reason it is kept out of a `Buf[T]`: its
payloads are laid out **without overlap** — the tag, then each member's payload at
its own offset — because SPIR-V cannot alias two typed members over one storage.
The program cannot observe the difference (§4), and a kernel local, a helper
parameter or a return value of `union enum` type is legal.

**Slices.** The SPIR-V floor is **Vulkan 1.2 with `bufferDeviceAddress`**: every
module uses the `PhysicalStorageBuffer64` addressing model, so a pointer into device
memory is a real 64-bit address, as on the CPU and in PTX. A `[]T` in device code is
§4's `{ ptr, len }` pair — a 64-bit device address and a `usize` — and supports what
it supports on the CPU: `x[k]`, `x[lo..hi]`, `&x[k]`, `x.len`, `for v in x`, passing
to a helper. `gpu.launch` maps a `Buf[T]` onto a `[]T`, `[]const T` or `[]Atomic[T]`
parameter by passing that pair in the kernel's argument block. Under logical
addressing none of this is expressible — a pointer cannot be re-based or stored — so
the floor is what buys one slice type for both profiles. A device below it (Vulkan
1.1, or 1.2 without `bufferDeviceAddress` or `scalarBlockLayout`) is not supported:
`gpu.open` returns `gpu.Unsupported`.

**`usize` on the device** is 32 bits on the `spv` target and 64 bits on `ptx`.
On a CPU it has the target pointer width: 32 bits on `x86`, 64 bits on `x64` and
`aarch64`. Vulkan's buffer ranges and dispatch limits are 32-bit, and 64-bit integers
are an optional capability (`.Int64`, below) that the index type must not depend on.
It is the one type whose width differs between a kernel's CPU build and its SPIR-V
build — §9 already lists `usize` as target-dependent — which is why it is not a
device storage type: it appears in device code only as a local and as the `len` of a slice,
and `gpu.launch` writes each slice's `len` at the device's width when it builds the
argument block, so the slice header is the CPU's `{ address, len }` pair with the
`len` field at 32 bits on `spv`. A `Buf[T]` of more than 2³² − 1 elements cannot be
given to a SPIR-V device: `gpu.alloc` and `gpu.upload` return `gpu.TooLarge` there.

**Address spaces.** Device code has three: *device* memory (buffers), *shared*
memory (the workgroup's, below) and *private* memory (an invocation's locals). A
slice or pointer type names its space. `[]T` and `*T` are device memory; `[]shared T`
and `*shared T`, with the `const` forms `[]const shared T` and `*const shared T`, are
shared memory. They are distinct types with no conversion between them, because in
SPIR-V the storage class is part of the pointer type. A helper that serves both is
written once as a generic over the slice type and monomorphised per space (§9):

```
fn sum[S: type](xs: S) -> f32 { ... } // S = []const f32 or []const shared f32
```

Private memory has no slice or pointer type at all: inside device code, `&x` and
`x[lo..hi]` on a function-local (private) variable — a `let`, `var` or by-value
parameter holding an array, a struct or a scalar in the invocation's own storage,
not a `shared var` — are compile errors, because a function-storage pointer cannot
be re-based or passed in SPIR-V. Index the local in place, or pass the array by
value. A slice parameter or local is not private storage — it points at buffer or
shared memory — so sub-slicing it and `&x[k]` on it are allowed, as the paragraph
above says.
`shared` in a type is legal only in code compiled for the device — a kernel or a
helper it reaches — and makes that helper device-only (What runs where, above). On
the CPU build the qualifier is erased: a `[]shared f32` is an ordinary slice into
the workgroup's storage.

### Shared memory

`shared var` declares **workgroup-shared storage**: one instance per workgroup,
visible to every invocation of it, lowered to the `Workgroup` storage class in
SPIR-V and `.shared` in PTX.

```
@gpu(256)
fn block_sum(xs: []const f32, out: []f32) {
    shared var tile: [256]f32
    // precondition at launch: xs.len is a multiple of 256
    tile[usize(gpu.lid.x)] = xs[usize(gpu.gid.x)]
    gpu.barrier()
    ...
}
```

- `shared` is a keyword (§3). `shared var name: T` is a **statement**, legal only
  directly in the body of an `@gpu` function — not in a nested block or loop, not in
  a helper, never at module scope. Its **storage** lives from workgroup start to
  workgroup end wherever the statement sits; its **name** is in scope from that line
  to the end of the kernel body, like any other local — a use above the line is a
  compile error. `T` is a device storage type; in practice a `[N]T` array, a struct of them,
  or an `Atomic[T]`.
- It takes **no initialiser** — the one local declaration in the language without
  one (a module-scope `var` has a defined zero value; this has none). It belongs to
  the workgroup, not to an invocation, so no single invocation could initialise it. Its contents are unspecified until written; the protocol is write,
  `gpu.barrier()`, read. A debug CPU build fills it with `0xCD` at workgroup start
  (§11), so a read before the barrier is recognisable.
- `tile[lo..hi]` is a `[]shared f32` and `&tile[i]` a `*shared f32`; that is how a
  helper receives it.
- The total per kernel is recorded in its Interface entry (§12) with the workgroup
  size and the capability set, and checked at launch against the device's limit
  (16 KB guaranteed by Vulkan, 48 KB on every NVIDIA part): `gpu.TooLarge`.

### Barriers, memory ordering and atomics

| Builtin | Semantics |
|---|---|
| `gpu.barrier()` | A control barrier at **Workgroup** scope with **AcquireRelease** semantics over **workgroup memory**: every invocation of the workgroup arrives before any leaves, and every `shared` write before it is visible to every invocation after it. It says nothing about device memory. `OpControlBarrier(Workgroup, Workgroup, AcquireRelease \| WorkgroupMemory)`; `bar.sync 0` in PTX. |
| `gpu.memory_barrier(.Workgroup)` | A memory barrier alone, AcquireRelease over workgroup **and** device memory at workgroup scope: this invocation's earlier writes, to buffers and to `shared`, become visible to the workgroup. No control synchronisation. `OpMemoryBarrier`; `membar.cta`. |
| `gpu.memory_barrier(.Device)` | The same at **Device** scope: this invocation's buffer writes become visible to every invocation of the launch that acquires after it. `membar.gl`. |

**Uniformity.** `gpu.barrier()` must be reached by every invocation of the
workgroup — the same barrier, the same number of times. It is legal only in
**uniform control flow**: not under a condition on `gid`, `lid`, `sid` or loaded
data, and not after an early `ret` that some invocations took. A violation is
undefined behaviour on the device — a hang, on most hardware, which does not check
because it cannot cheaply — and a trap of kind `barrier` in the CPU build (CPU
execution model, below), which does.

**Device atomics.** `Atomic[T]` (§8) is a device storage type for `T` in `i32`, `u32`,
`i64`, `u64`, so a buffer element, a slice parameter and a `shared var` can be
atomic: `Buf[Atomic[u32]]` maps onto `[]Atomic[u32]`, and `shared var count:
Atomic[u32]` is legal. Atomic operations in device code are the `gpu.atomic_*`
builtins — §8's operations plus a **scope**:

```
gpu.atomic_add(p, v, .Relaxed, .Device) // p: *Atomic[T] or *shared Atomic[T]
gpu.atomic_load(p, .Acquire, .Workgroup)
gpu.atomic_store(p, v, .Release, .Device)
gpu.atomic_cas(p, old, new, .AcqRel, .Acquire, .Device)
gpu.atomic_sub  atomic_min  atomic_max  atomic_and  atomic_or  atomic_xor  atomic_xchg // (p, v, order, scope)
```

`gpu.Scope` is `.Workgroup` — the invocations of this workgroup — or `.Device` — the
whole launch, and the host after a `gpu.sync`. Orderings are §8's, with the C11
meaning. The scope is the argument with no CPU counterpart, which is why these carry
the `gpu.` qualifier instead of giving `atomic.*` a second signature per name (§14
invariant 1); in the CPU build they lower to §8's atomics, whose scope is the system.
`atomic.*` itself is banned in device code (Restrictions, above). 64-bit atomics
need `.Atomic64` (Capabilities, below). CAS failure ordering follows §8 exactly:
no release semantics and no ordering stronger than success.

An acquire load or acquire part of an atomic operation at scope S that observes a
value written by a release store or release part at scope S synchronizes with it;
all ordinary memory operations sequenced before the release happen before those
sequenced after the acquire. `memory_barrier` orders only the calling invocation and
must be paired with an atomic release/acquire or another specified synchronization;
it does not by itself make another invocation observe a write. `gpu.barrier` supplies
both the control rendezvous and matching release/acquire for shared memory. Races on
non-atomic device or shared memory are undefined as on the CPU.

### Subgroups

A subgroup is the hardware's SIMD group of invocations — a warp, a wave — of a
device-dependent size between 4 and 64. It is never a compile-time constant and
never something a kernel may depend on for correctness. The set is the minimum a
reduction, a scan or a compaction needs, and nothing that names a lane layout:

```
gpu.subgroup_size() -> u32 // uniform across the launch
gpu.sid // this invocation's index in its subgroup, u32
gpu.subgroup_add[T](v: T) -> T // reduction over the subgroup; also _min _max, and _and _or _xor for integer T
gpu.subgroup_all(b: bool) -> bool // also _any
gpu.subgroup_ballot(b: bool) -> u64 // bit i set when lane i passed true; adds .Int64 to the inferred set
gpu.subgroup_broadcast[T](v: T, lane: u32) -> T // lane must be uniform across the subgroup
gpu.subgroup_shuffle[T](v: T, lane: u32) -> T // lane per invocation
gpu.subgroup_elect() -> bool // true in exactly one active invocation
```

`T` is a 32- or 64-bit integer or float — comptime-generic per D5, inferred from `v`
per §9 — except that `_and`, `_or` and `_xor` take an integer `T` only. The `lane` of
`subgroup_broadcast` must be **uniform** across the subgroup — one value in every
invocation, as SPIR-V's `OpGroupNonUniformBroadcast` requires — where `shuffle`'s
is per invocation; a non-uniform `lane` is undefined on the device and a `barrier`
trap in the CPU build. Every subgroup builtin needs uniform control flow within the subgroup, the
rule barriers have at workgroup level, with the same consequence: undefined on the
device, a `barrier` trap in the CPU build. The float `subgroup_add`, `subgroup_min` and `subgroup_max` reductions run in
hardware order and are approximate builtins (§11, Floating point). They require
`.Subgroup` (below): `GroupNonUniform` with `Arithmetic`, `Ballot` and `Shuffle` in
SPIR-V; `shfl.sync` and `vote.sync` in PTX (`redux.sync` from `sm_80`).

A broadcast or shuffle lane must be less than `subgroup_size()` and name an active
invocation. An invalid or inactive source lane is a bounds check: it traps in the CPU
debug build and is undefined in release and on the device. Algorithms that operate
on a partially active subgroup use `subgroup_ballot` to select an active source.

### Capabilities

The compiler **infers each kernel's capability set** from the types and builtins the
kernel and every helper it reaches use, records it in the kernel's Interface entry of
the `.spv.em` or `.ptx.em` (§12), and `gpu.launch` compares it against the device
(D26): a missing capability fails with `gpu.Unsupported`, naming the kernel and the
capability. `gpu.has(dev, cap)` lets a program choose a kernel before launching one.

| Used in a kernel | `gpu.Cap` | SPIR-V capability | Vulkan feature |
|---|---|---|---|
| `i32` `u32` `f32`, `err`, `usize` as a local (32-bit), `enum` up to 32 bits, `bool` in registers | — | `Shader` | none — the floor |
| `Mask[T, N]` (§4) | that of `T` | `OpTypeVector` of `OpTypeBool`, split as `Vec` is; registers only, never in a buffer | — |
| any `[]T`, `Buf[T]`, pointer into device memory | — | `PhysicalStorageBufferAddresses` | `bufferDeviceAddress`, `scalarBlockLayout` — the floor |
| `i8` `u8`, `enum u8` — any value in device code, in a register as in a buffer or in `shared`; `time.to_date` and `time.to_time` (§16), whose results hold `u8` fields | `.Int8` | `Int8`, `StorageBuffer8BitAccess` | `shaderInt8`, `storageBuffer8BitAccess` |
| `i16` `u16`, `enum u16` — any value in device code, as above; `bf16` in storage | `.Int16` | `Int16`, `StorageBuffer16BitAccess` | `shaderInt16`, `storageBuffer16BitAccess` |
| `f16` arithmetic | `.Float16` | `Float16`, plus `.Int16` for storage | `shaderFloat16` |
| `bf16` arithmetic | — | none: computed in `f32` and rounded (§4); stored as 16 bits under `.Int16` | — |
| `i64` `u64`; `time.to_date` and `time.to_time` (§16) | `.Int64` | `Int64` | `shaderInt64` |
| `f64` | `.Float64` | `Float64` | `shaderFloat64` |
| `gpu.atomic_*` on `Atomic[i64]`, `Atomic[u64]` | `.Atomic64` | `Int64Atomics` | `shaderBufferInt64Atomics`, `shaderSharedInt64Atomics` |
| `gpu.subgroup_*`, `gpu.sid` | `.Subgroup` | `GroupNonUniform`, `GroupNonUniformArithmetic`, `GroupNonUniformBallot`, `GroupNonUniformShuffle` | `subgroupSupportedOperations` includes those; `subgroupSize` at most 64 |
| `gpu.subgroup_ballot` | `.Subgroup` and `.Int64` | its `u64` result | as the two rows above |
| `@gpu(..., ftz)` | `.Ftz` | `DenormFlushToZero` execution mode | `shaderDenormFlushToZeroFloat32` |
| `Vec[T, N]` | that of `T` | `OpTypeVector` of 2 to 4 lanes; **`N > 4` is split into `N/4` four-lane vectors** — `Vec[f32, 8]` is two `vec4`, `Vec[u8, 16]` four — the counterpart of §4's split on a narrow CPU; the buffer layout stays §4's | — |

Reported, never required — the device either does it or not, and `gpu.has` says
which: `.DenormPreserve`, the device keeps `f32` denormals (`shaderDenormPreserveFloat32`;
every desktop part), which §11's Floating point rule depends on.

On PTX the floor is `sm_50`, where every row above is available except `f16`
arithmetic (`sm_53`) and native `bf16` (`sm_80`; computed in `f32` below it, as on
every other target). The same `gpu.Cap` values report them.

**`caps(...)` in the attribute is an upper bound**, checked at compile time.
`@gpu(256, caps(.Int64))` declares that the kernel needs `.Int64` and nothing else;
a use that would infer a capability outside the list — a helper three calls down
that touches an `f64` — is a compile error at the kernel with the call chain. It
exists so that a kernel written for a mobile device cannot silently grow a
desktop-only requirement. The inferred set is still what launch checks. `ftz` is the
other option, defined under §11's Floating point.
Omitting `caps` sets no upper bound. A listed capability need not actually be used;
duplicates are errors, and `ftz` both enables the execution mode and infers `.Ftz`.
Inference examines all statically reachable instructions, types, storage declarations
and signatures after `when` selection and generic instantiation, whether or not a
runtime branch is expected to execute.

### Host side

Device memory is a **distinct type**, not a host slice. `gpu.Buf[T]` is a handle to
device memory; a host pointer is meaningless on the device and the reverse, so the
type system keeps them apart rather than trusting a convention.

```
type Backend = enum u8 { Cpu, Vulkan, Cuda }
type DeviceKind = enum u8 { Unknown, Cpu, Integrated, Discrete, Virtual, Other }
type DeviceKey = struct { backend: Backend, uuid: [16]u8 }
type DeviceInfo = struct {
    key: DeviceKey,
    key_valid: bool,
    index: u32,
    name: str,
    kind: DeviceKind,
    memory_bytes: u64,
    memory_known: bool,
    capabilities: []const Cap,
    supported: bool,
}
type Device  = struct { state: *void } // usable from any thread
type Queue   = struct { state: *void } // one thread at a time
type Buf[T: type] = struct { owner: u32, slot: u32, generation: u32, len: usize }
type Grid    = struct { x: usize, y: usize, z: usize } // invocation counts
type Id      = struct { x: u32, y: u32, z: u32 } // gpu.gid, gpu.lid, gpu.wgid (Kernels and workgroups, above)
type Cap     = enum u8 { Int8, Int16, Int64, Float16, Float64, Atomic64, Subgroup, Ftz, DenormPreserve }
type Scope   = enum u8 { Workgroup, Device }

error NoDevice // no currently visible device matches the requested index or key
error AmbiguousDevice // several visible devices match one key; never choose arbitrarily
error Unsupported // below the floor, or a capability, workgroup size or shared size the device lacks
error OutOfMemory // device memory, or the driver's; on .Cpu the open arena's mem.Exhausted instead (open, below)
error TooLarge // a length or grid beyond a device limit; a download destination too small; a write past the end of its buffer
error Lost // the device or driver failed; every later call on it that returns an err returns Lost
error WrongDevice // a queue and buffer/device do not share an owner
error InvalidHandle // released, closed, joined or otherwise consumed handle
```

`Device.state` and `Queue.state` point into the bookkeeping block allocated by
`open`; callers never dereference or replace them. A `Buf` is a value handle:
`owner` identifies the device, `slot` indexes its handle table, `generation`
rejects stale copies, and `len` is the element count. These fields are fixed because
the language has no private-field mechanism; their representation is public, while
their contents remain module-owned invariants.

| Function | Semantics |
|---|---|
| `fn devices(a: *mem.Arena, b: Backend, limit: usize) -> ([]const DeviceInfo, err)` | Enumerates a bounded snapshot of visible devices of `b`, including devices below Neper's floor with `supported == false`. Records, names and capability slices are allocated from `a`. No visible devices returns an empty slice and `ok`; a backend not embedded in the build returns `Unsupported`. More than `limit` records is `TooLarge`, not a silently truncated success. See Device discovery and selection below. |
| `fn open(a: *mem.Arena, b: Backend, index: u32) -> (*Device, err)` | Opens device `index` of backend `b`. `open` takes **one** bookkeeping block from `a` — for the device, its queues and its buffer handles — and the `Device` guards that block with its own lock, so it is the one piece of arena memory in `lib/e` that several threads touch, and `a` stays the caller's. On a driver backend (`.Vulkan`, `.Cuda`) that block is all `a` is used for: `Buf[T]` storage and staging are device and driver memory, and `OutOfMemory` is their failure. `.Cpu` always exists at index `0` and runs the CPU build (below); it has no driver and no staging, so it allocates **every `Buf[T]` from `a`** — once, at `alloc` or `upload`; the only memory source it has, and named on the page as D3 requires — and `upload` and `write` memcpy straight into that storage. Exhaustion surfaces as `a`'s `err`, `mem.Exhausted`, from `alloc` or `upload`. A backend the build did not embed — one absent from `--gpu` (§13) — returns `Unsupported`; `.Cpu` needs no device module and is never absent. |
| `fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err)` | Opens the exact currently visible backend-scoped key, revalidating identity while opening. No match is `NoDevice`; multiple matches are `AmbiguousDevice`; an unavailable compiled backend or a matching device below the floor is `Unsupported`. Never substitutes an index, name, other backend or CPU. Allocation, cleanup and ownership rules are those of `open`. |
| `fn info(a: *mem.Arena, dev: *Device) -> (DeviceInfo, err)` | Copies the selected device's opening-time descriptor into `a`, including owned copies of its name and capability slice. No device-memory allocation or queue synchronization. A closed/stale device is `InvalidHandle`; a lost device is `Lost`. The captured index is informational, not a current locator. |
| `fn close(dev: *Device) -> err` | Atomically begins closing, rejects new operations, waits for every queue, releases every buffer and queue, then the device. A repeated close is `InvalidHandle`; a driver failure is `Lost`. |
| `fn has(dev: *Device, c: Cap) -> bool` | Capability query; returns `false` after closing begins. |
| `fn queue(dev: *Device) -> (*Queue, err)` | A new in-order stream: a hardware queue where the device has a spare one, otherwise a separate command stream on a shared one. The ordering guarantees are the same either way. |
| `fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err)` | `n` elements of device memory, contents unspecified. |
| `fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err)` | Atomically `alloc` then `write`; if staging or submission fails, it reclaims the allocation before returning the error and no handle escapes. |
| `fn len[T: type](b: Buf[T]) -> usize` | The element count `alloc` or `upload` gave it; use through a released or stale handle is an `invalid` check. |
| `fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err` | A **synchronous** copy of `src` into driver-owned staging memory, then an in-order transfer to `dst[off..]` enqueued on `q`. Returns when `src` has been read. It checks `off <= len` and `src.len <= len-off`, without overflowing; failure is `TooLarge`. |
| `fn launch[K: fn](q: *Queue, g: Grid, args: ...) -> err` | Enqueues kernel `K` over `g` with `args`; returns once queued. |
| `fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err` | Validates ownership, liveness and destination length before waiting; then waits for every earlier submission on `q` and copies `gpu.len(src)` elements into `dst`. A small destination is `TooLarge` without blocking. |
| `fn sync(q: *Queue) -> err` | Blocks until every submission on `q` has completed. |
| `fn release[T: type](q: *Queue, b: Buf[T]) -> err` | Consumes the logical handle and enqueues release behind earlier submissions. A stale copy is `InvalidHandle`, a queue from another device is `WrongDevice`, and device loss is `Lost`. |
| `fn grid1(x: usize) -> Grid`, `fn grid2(x: usize, y: usize) -> Grid`, `fn grid3(x: usize, y: usize, z: usize) -> Grid` | Invocation counts; an omitted axis is `1`. |

**The kernel is a comptime parameter.** `gpu.launch[saxpy](q, g, ...)` names the
kernel in the bracket, as `printf[FMT]` names its format string and `thread.spawn[Ctx]`
its context type, and that is what makes the compile-time check of the trailing pack
possible: the compiler can see `saxpy`'s parameter list. `K: fn` declares a comptime
parameter of kind **`fn`**: in a comptime position a function name is a value of kind
`fn`, the way a type name is a value of kind `type` (§9). It is bound at compile time
and monomorphised per kernel; it is not a function pointer, so host code never forms
a pointer to device code. `launch` additionally requires that `K` names an `@gpu`
function; a plain function, a helper reached from a kernel, or a function pointer in
that position is a compile error at the call.

Everything after the grid is the argument pack (§9), matched positionally against
`K`'s parameters at compile time:

| Argument | Parameter | Rule |
|---|---|---|
| `Buf[T]` | `[]T`, `[]const T`, or `[]Atomic[T]` when `T` is `Atomic[T]` | The pair `{ device address, len }` is passed — the one implicit operation of the launch, listed in §6 |
| a value of a device storage type | the same type | By value, in the argument block; no conversion, as everywhere |
| an untyped literal | an integer or float device-storage parameter | Takes the parameter's type (§3); literals never become `bool`, `err` or an enum without its ordinary contextual member syntax |
| anything else — a host slice or pointer | — | Compile error naming the parameter |

Arity, types and address spaces are all checked at the call site; nothing about a
launch is discovered on the device.

### Device discovery and selection

This is an extension of the planned M3 `e.gpu` surface, not an implemented feature
or a new implicit dispatch rule. M2.5 freezes its identity, allocation, error and
tooling contracts; M3 supplies CPU/Vulkan execution evidence and M4 adds CUDA.

**Indices are temporary, keys are exact selectors.** `devices` returns records in
ascending `index` order, using the current backend-visible zero-based enumeration.
Indices can change after hotplug, driver changes, visibility filtering or process
restart. Enumeration does not reserve a device. `open(a, b, index)` selects the
current device at that index; callers needing the identity they inspected must use
`open_id(a, record.key)` when `record.key_valid` is true. An opened device never
retargets if enumeration subsequently changes.

`DeviceKey` equality compares both the backend and all 16 UUID bytes. UUIDs are
opaque bytes, not numbers; no host-endian conversion is applied. Their text form
for configuration/tooling is `cpu:`, `vulkan:` or `cuda:` followed by exactly 32
lowercase hexadecimal digits in byte order. This defines an interchange spelling,
not a new parser API or automatic environment-variable policy. Invalid selectors
are rejected by the consuming tool before opening a device.

- Vulkan uses `VkPhysicalDeviceIDProperties.deviceUUID`; CUDA uses the device UUID,
  with `cuDeviceGetUuid_v2` or equivalent partition-aware identity where available.
  A MIG/virtual partition is a separately selectable compute device, not its parent
  board. If a trustworthy identity for the selectable unit cannot be obtained,
  `key_valid` is false; do not synthesize one from a name, index or PCI model number.
  In that case retain the backend but zero the UUID bytes, and exclude the record
  from `open_id` matching. A zero UUID is not by itself a validity test; use the flag.
- A valid key is stable only to the extent guaranteed by its provider. It is not
  an immutable hardware serial number. Hardware relocation, virtualization and
  partition reconfiguration can invalidate persisted keys. Persisted selection must
  be revalidated and missing/ambiguous identities require an explicit new choice.
- Vulkan and CUDA may expose the same hardware through different keys. Neither
  equal indices nor equal UUID bytes across backends authorize aliasing, deduplication
  or shared handles. Cross-backend physical-device correlation is not promised.
- Duplicate valid keys remain visible as separate enumeration records, but
  `open_id` rejects ambiguity. A display name is never a unique identity. Reordering
  duplicate names must not redirect a saved selector.
- `.Cpu` exposes exactly one record: index `0`, key `{ backend: .Cpu, uuid: zero }`,
  `key_valid == true`, name `Neper CPU`, kind `.Cpu`, `supported == true`. The key
  selects this process's CPU backend, not a particular processor or host. No CPU
  memory capacity is advertised: `memory_known == false`, `memory_bytes == 0`.

**Descriptor meanings.** `name` is display-only UTF-8, copied from driver metadata
with invalid sequences replaced by U+FFFD. It is untrusted data, never instructions
for a harness. `kind` is the provider-reported classification; use `.Unknown` when
it cannot be determined, and do not infer discrete/integrated status from a name.
It is not a performance ranking. A software device exposed by Vulkan may have
kind `.Cpu` while retaining backend `.Vulkan`; this is distinct from Neper's CPU
debugging backend and must not be relabeled as hardware GPU execution.

`memory_bytes` is visible device-local capacity, **not free memory, a reservation
or a guarantee that an allocation succeeds**. Vulkan sums distinct device-local
heaps once, not memory types; CUDA reports total addressable device memory of the
visible unit/partition. Shared/unified capacity is not dedicated VRAM. If capacity
cannot be determined, report `memory_known == false` and zero bytes. Descriptor
memory is an opening/enumeration-time observation, not a live memory-budget query.

`capabilities` contains the reported `Cap` values without duplicates in enum order,
under the same meaning as `gpu.has`. It is advisory before opening; `supported`
means the device satisfies the backend floor, not every kernel's requirements,
memory demand, workgroup shape or availability at a later instant. `open_id` checks
the floor again; launch retains its exact kernel capability/limit checks. H23's
numerical capability corrections apply to this descriptor as well as `gpu.has`.

**Bounded snapshots and failure.** `limit` is a caller-selected record bound, not a
request for the first N devices; zero succeeds only for an empty visible set. A
successful call returns a complete observed list, never a partial list presented
as complete. Reconcile count/list races with at most three complete driver-enumeration
attempts; an unstable inventory after that is `Lost`. Changes after a successful
snapshot are allowed, so opening remains fallible. No call spins indefinitely for
hotplug to settle. Backend absence is `Unsupported`; driver initialization/enumeration
failure is `Lost`, distinct from successful discovery of zero devices. These are
API-level results once program startup succeeds; this extension does not bypass
§13's platform loader/linker requirements or promise recovery from startup failure.

On failure, `devices` returns `(nil, error)` and `info` returns a zero descriptor;
caller-arena exhaustion is `mem.Exhausted`. Failed calls roll back their temporary
caller-arena allocations; the caller must not allocate concurrently from that
arena. Successful records/names/slices remain valid until that arena is reset or
destroyed, independent of device closure. They hold no open-device handles or
reservations. Internal discovery driver resources are released before return; no
hidden persistent inventory allocation, logical-device creation or kernel launch
is implied. Driver discovery/initialization may still perform driver-owned work.

`open_id` resolves one native device handle and verifies its identity through
opening; removal or identity change fails rather than reopening a replacement at
the old ordinal. This protects against ordinary reordering/hotplug, not a malicious
driver forging hardware identity. Capability and descriptor collection for `info`
belongs to the device bookkeeping allocation already charged to `open`/`open_id`.
Failed opens return a nil device and release partial driver resources/bookkeeping;
they do not transfer a half-open resource or reserve the failed ordinal for retry.

**Multiple devices stay explicit.** Several `Device`s may be open simultaneously;
each queue and buffer belongs to one logical open-device identity. Even two opens
of the same physical GPU do not share handles. Cross-device use is `WrongDevice`
for fallible calls; non-fallible operations retain their documented check behavior.
There is no automatic work splitting, migration, peer copy, shared allocation or
cross-device completion-token interoperability. To move data, explicitly download
through the source queue, then upload to the destination queue. Waiting on one
device does not synchronize another. Failure/loss does not trigger transparent
replay elsewhere; dependent application work must handle the failure explicitly.

Selection policy is application-owned: enumerate, filter by kind/capability/capacity,
choose a candidate, and open its exact key. An explicit saved key takes precedence
only when the application says so; Neper does not invent a fastest-device heuristic
or read an ambient GPU-selection variable. CPU fallback remains explicit, and the
CPU backend remains a debugger rather than an optimized production fallback.

Example selecting a supported discrete Vulkan device with `Float64` by its key;
the first matching enumeration entry is this application's policy, not a promise
that it is the fastest GPU. It does not fall back to a different device on an open
failure and does not assert that this capability alone makes every kernel legal:

```neper
use e.gpu
use e.mem

fn open_discrete_f64(a: *mem.Arena) -> (*gpu.Device, err) {
    let candidates = try gpu.devices(a, .Vulkan, 64)
    for candidate in candidates {
        if !candidate.supported || !candidate.key_valid { continue }
        if candidate.kind != .Discrete { continue }
        for capability in candidate.capabilities {
            if capability == .Float64 {
                ret gpu.open_id(a, candidate.key)
            }
        }
    }
    ret (nil, gpu.NoDevice)
}
```

The descriptor storage in this example lives in `a`; repeated selection should use
a separate short-lived discovery arena and copy the value-only `DeviceKey` into
the opening call. Never reset an arena that also owns an open device's bookkeeping.
Returning `NoDevice` for no policy match above is application policy; the raw
`devices` API returns an empty successful list when nothing is visible.

Provider references: [Vulkan device identity](https://docs.vulkan.org/spec/latest/chapters/devsandqueues.html)
and [CUDA device discovery/UUIDs](https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__DEVICE.html).
Their provider limits constrain identity stability; Neper does not strengthen them
into an unconditional cross-reboot, cross-backend or cross-machine identity promise.

### Queues and synchronisation

**`gpu.launch` is asynchronous on Vulkan and CUDA.** It returns once the work is
queued, so the CPU continues while the device runs. The `.Cpu` backend is the explicit
synchronous exception: it executes on the calling thread and returns after the grid.

```
fn run(q: *gpu.Queue, x: []const f32, y: []f32, other: []f32) -> err {
    let dx = try gpu.upload[f32](q, x) // x has been copied out when this returns
    defer let _ = gpu.release(q, dx) // ordered behind everything queued below
    let dy = try gpu.upload[f32](q, y)
    defer let _ = gpu.release(q, dy)

    try gpu.launch[saxpy](q, gpu.grid1(x.len), u32(x.len), 2.0, dx, dy)

    cpu_side_work(other) // runs while the GPU is busy

    try gpu.sync(q) // wait for the queue to drain
    try gpu.download[f32](q, dy, y)
    ret ok
}
```

| Call | Semantics |
|---|---|
| `gpu.launch` | Driver backends queue work and return immediately; `.Cpu` completes the grid before returning |
| `gpu.upload`, `gpu.write` | Copies the source into staging **now**, queues the transfer, returns; the source is free |
| `gpu.download` | **Implicitly synchronises** the queue, then copies back |
| `gpu.sync(q)` | Blocks until the queue drains |
| `gpu.release` | Queued behind prior submissions; the memory goes away when they have finished |

**A queue is an in-order stream.** Everything submitted to one `Queue` — transfers,
launches, releases — completes in submission order, and `gpu.sync(q)` and
`gpu.download` wait for exactly that queue's earlier submissions and nothing else.
`defer let _ = gpu.release(q, dx)` after a launch is therefore safe by construction: the
release is queued behind the launch that reads `dx`. Two queues are unordered with
respect to each other; whether they run concurrently is the device's business. A
`Buf[T]` belongs to the device, not to a queue, and may be used from any queue of
its device — with only what `gpu.sync` gives as ordering between them, so a buffer
written on one queue and read on another without a `sync` between is a race, which
is undefined behaviour under D14.

Every device, queue and buffer carries an opaque owner ID and generation. All host
calls validate them before accessing driver state. A fallible call given a queue or
buffer from another device returns `WrongDevice`; a released buffer, closed device,
destroyed queue or stale copied generation returns `InvalidHandle`. Non-fallible
`has` and `len` follow the special rules below. Handles are logically linear even
though the language can copy their bits: `release` and `close` consume all copies.
`NoDevice` is returned by `open` and `open_id`; `AmbiguousDevice` is returned by
`open_id` for duplicate matching keys. `Unsupported` covers a missing compiled backend,
floor, capability or workgroup feature; `TooLarge` covers validated sizes and grids;
`OutOfMemory` covers allocation and staging; a driver reset or irrecoverable submit,
wait or transfer failure marks the device lost and returns `Lost` thereafter.

**Upload's cost is on the page.** `upload` and `write` are synchronous so that the
double-buffer pattern — upload, refill the host buffer, upload again — is correct
without a lifetime rule the compiler cannot check. The price is one host memcpy of
`src.len * mem.size_of[T]()` bytes into driver-owned, host-visible staging memory,
held until the queued transfer completes; on an integrated GPU, whose device memory
is host-visible, that one copy is the whole transfer. On a driver backend that
staging block is **allocated from the driver on every call, outside every arena**,
and released when the transfer completes: it is the one allocation in `lib/e`
that is not visible as an arena parameter (D3 records the exception), and
`OutOfMemory` is its failure. On `.Cpu` there is no staging: `upload` and `write`
memcpy straight into the `Buf`'s storage, allocated once from the arena passed to
`gpu.open` (Host side, above), and `mem.Exhausted` is `alloc`'s and `upload`'s
failure.
A program that cannot afford the copy keeps its data on the device between launches,
which is what `Buf[T]` is for.

**Threads.** A live `*gpu.Device` may be used from any thread concurrently — `queue`
and `has` — because the runtime guards the bookkeeping block it took
at `open` (Host side, above) with its own lock; nothing else in `lib/e`
synchronises arena memory. Each `*gpu.Queue` is used from one thread at a time: two threads submitting
to one queue without their own synchronisation is undefined behaviour under D14. The
intended shape is one queue per CPU thread, each driving its own stream.
`close` is an exclusive transition: it acquires the device lock, marks the device
closing, waits for operations that entered before the mark, then drains and destroys
the device. New fallible calls return `InvalidHandle`, `has` returns `false`, and
`len` through a stale buffer is an `invalid` check. Concurrent close calls serialize
and all but the first return `InvalidHandle`.

`download` syncing implicitly is the one convenience here, and it is worth it: a
download that returned stale data because you forgot to sync is a silent wrong
answer, which is the failure mode this language works hardest to avoid. Use
`gpu.sync` explicitly when you want to wait without copying.

**Nothing crosses the boundary implicitly.** The device cannot allocate from a host
arena, perform I/O, or call back into CPU code. There is no unified address space and
no shared virtual memory in v1.

### CPU execution model

The CPU build of a kernel is what `gpu.open(a, .Cpu, 0)` runs. It is the debugger
and the test vehicle (§13), and its semantics are the device's — not a serial
approximation in which every missing barrier and every shared-memory race, the
dominant class of kernel bug, quietly disappears.

**The workgroup is the unit.** A `launch` on the CPU backend runs the grid on the
calling thread, one workgroup after another in workgroup-id order, and returns when
the last has finished; `upload`, `write` and `download` are memcpys and `sync` is a
no-op. A workgroup never splits across threads; a later option may spread workgroups
over several host threads, and nothing a kernel can observe distinguishes the two.

**One host thread runs a whole workgroup by barrier loop-fission**, the technique of
pocl and Intel's CPU OpenCL. The compiler cuts the kernel body at every
`gpu.barrier()` (and every subgroup builtin, which is a barrier for its subgroup)
into regions, and emits the workgroup as a sequence of loops: region 0 for every
invocation in `lid` order, then region 1 for every invocation, and so on. A local
that lives across a barrier is given one slot per invocation, an array indexed by
`lid` in the workgroup's frame; a `shared var` is one storage per workgroup, in that
same frame, filled with `0xCD` in debug before region 0. This is exactly the
ordering a barrier guarantees, so a kernel that is correct on the device is correct
here, and a kernel that reads `shared` before the barrier that publishes it reads
`0xCD` here rather than whatever another invocation happened to have written.

“Cuts at every barrier” is a control-flow transformation, not a textual split. The
compiler builds a resumable state machine per invocation with a program-counter slot;
it repeatedly runs every active invocation until its next barrier, verifies that all
active invocations reached the same static barrier and occurrence count, performs the
barrier, then resumes them. Loops may therefore execute a barrier repeatedly. If one
invocation exits, reaches a different barrier or needs another iteration while its
peers do not, the CPU build traps `barrier`; the same program is undefined on a
device. Subgroups use the same machine over each active subgroup.

**Stepping.** A breakpoint in a kernel stops at one invocation's iteration of one
region. `gpu.gid`, `gpu.lid`, `gpu.wgid` and `gpu.sid` are ordinary locals in that
frame, so any debugger reading the §13 subset shows which invocation is stopped; the
workgroup's `shared var`s are locals of the enclosing workgroup frame; a local that
lives across a barrier appears as an array indexed by `lid` in a standard debugger,
and `neper dap` (§13, M4) renders the current invocation's element. "Step a single
work item" means: step through this invocation's iteration, then the next
invocation's, in `lid` order, with the workgroup's state in view throughout.

**Divergence is a checked trap.** A debug CPU build records, per invocation, the
barrier it reached — by source position and by arrival count. When any invocation of
a workgroup reaches a different barrier than the others, or returns before reaching
one the others reached, the build traps with kind `barrier` (§11): `trap[barrier]:
invocation (7,0,0) of workgroup (3,0,0) returned before the barrier at
kern.e:41:5 that invocation (0,0,0) reached`. That is the bug the device would turn
into a hang. The same check covers a subgroup builtin in divergent code.

**What is identical, stated exactly.** Integer and float results of a kernel on the
CPU backend and on a device are bit-identical under §11's Floating point rule, with
these exceptions and no others: the approximate builtins listed there; the width of
`usize` (32 bits on `spv`, above), which matters only to a kernel that overflows it;
denormal `f32` results on a device without `.DenormPreserve`; and the order in which
atomics from different invocations are applied, which the device does not fix
either. Debug checks (§11) fire in the CPU build and not on the device, which
carries no checks — so a kernel that would trap on the CPU is a kernel whose device
result is unspecified, and the CPU build is where it is found. Roadmap M3's criterion
is written in these terms.

**Subgroups on the CPU** are 32 consecutive invocations in `lid` order, and
`gpu.subgroup_size()` reports `32`. A workgroup whose size is not a multiple of 32
has a partial last subgroup, exactly as on a device: `subgroup_size()` still reports
`32`, the absent lanes are inactive, and an inactive lane reads as `false` in
`ballot`, `all` and `any` and contributes nothing to a reduction. A kernel that is
correct only at that size is wrong on some device; the CPU build does not try to
hide that.

The CPU backend is not a performance path. It exists so that a kernel can be
stepped, checked and tested on the machine that compiled it, which is one of the
better arguments for compiling `@gpu` functions both ways (§13).

---

## 11. Build modes and safety

| Check | kind | debug | release |
|---|---|---|---|
| Slice/array bounds | `bounds` | trap | off |
| Null dereference | `null` | trap | off |
| Tagged-union payload access against the wrong tag (§4) | `tag` | trap | off |
| Integer overflow (`+ - *`, unary `-`) | `overflow` | trap | wrap |
| Integer division by zero (`/` `%` on integers; float `/` is IEEE, below) | `divide` | trap | trap |
| Integer division overflow (`MIN / -1`, `MIN % -1`) | `divide` | trap | trap |
| Narrowing cast to a value not representable (§4) | `narrow` | trap | integer: truncate — the C result; float-to-integer: saturate, NaN to `0` |
| Shift by a count `>=` the width (§6) | `shift` | trap | count masked to `width - 1` |
| Integer-to-`enum` cast naming no member (§4) | `enum` | trap | trap |
| Invalid value representation, arena/builder state or consumed debug-tracked handle where a section names an `invalid` check | `invalid` | trap | undefined behavior |
| `simd.load_aligned`/`store_aligned` at an address not aligned to the vector width (§4) | `align` | trap | off |
| `unreachable()` reached | `unreachable` | trap | trap |
| Divergent control flow at `gpu.barrier()` or a subgroup builtin, or a non-uniform `lane` argument to a subgroup operation — the CPU build of a kernel only (§10) | `barrier` | trap | off |
| Arena exhaustion (`mem.Exhausted`, §8) | — | `err` | `err` |

Semantics are identical up to the point a check would fire, so a program that never
trips a check behaves identically in both modes. The rows divide in two. The
**arithmetic rows** — `overflow`, `divide`, `narrow`, `shift`, `enum` — have a
defined release result on every target: wrap, trap, truncate/saturate, mask or trap,
and nothing in those rows is undefined behaviour. Division by
zero and `MIN / -1` trap in every mode because x64 raises `#DE` for them regardless,
and on a target that does not (aarch64 yields `0`) the check is one compare — a
release behaviour that varied by target would break the sentence above. The
**memory/state rows** — `bounds`, `null`, `tag`, `align`, `barrier`, `invalid` — remove
their check in release. The operation then does what the hardware does: an
out-of-range write, a `nil` dereference, a wrong-member read or a misaligned vector
access in a release build is **undefined behaviour**, as in C, and the debug build is
where it is found. Arena exhaustion is an ordinary error in every mode, not a check —
running out of memory is a normal condition.

`@nocheck { ... }` disables the debug-only rows for a block in debug builds, for the
rare hot loop that needs it during development. It cannot disable the rows that trap
in release.

### Trap protocol

A check that fires **traps**, and a trap is one thing in every build mode: the
runtime writes one record to stderr, then a symbolised backtrace, and exits with
code **134** (`128 + SIGABRT`, what every crash pipeline already classifies as an
abort). No unwinding runs; no `defer` runs.

When the compiler-generated test root installs a control handle, the runtime also
writes the same trap as one authenticated framed JSON object to that handle before
writing stderr. The parent creates a random 128-bit nonce through `os.random`; the
startup stub receives it and the handle through reserved OS startup metadata that is
removed before constructing neper `args`. A frame is that nonce, a `u32` little-endian
byte length, then exactly that many UTF-8 JSON bytes. The parent rejects a wrong nonce,
oversized length, invalid JSON or partial frame as a crashed test. Source code cannot
read the installed nonce or handle through a language API, so neither user stderr nor
a guessed raw handle can impersonate a control record.

```
src/lex.e:88:14: trap[bounds]: index 7 out of bounds for len 5
src/lex.e:88:14: trap[overflow]: i32 + overflows: 2147483647 + 1
src/lex.e:88:14: trap[narrow]: 300 does not fit u8
src/lex.e:88:14: trap[tag]: Node.BinOp read while tag is Lit
src/lex.e:88:14: trap[unreachable]: token kind not handled
  at lex.next_token (src/lex.e:88)
  at parse.parse_expr (src/parse.e:412)
  at main.main (src/main.e:19)
```

Each frame is `module.function` under §2's naming rule, so `src/main.e` is module
`main` and its entry point is `main.main`.

The record is `file:line:col: trap[<kind>]: <values>` — the same shape as a
compiler diagnostic (§13), with `trap[kind]` in the place of `error[code]`, so the
tooling of §14 parses one format. `<kind>` is the column of the table above. The
values are the operands the check saw: the index and the length, the operands and
the operator, the value and the target type, the member read and the tag found. The
backtrace comes from the unwind info and the `.nepersym` line-and-symbol section
(`.nepsym` in COFF/PE, whose section-name field is limited to eight bytes)
§13 (Debug information) emits in every build mode, under the own linker and
`--linker=system` alike, which is why it costs nothing to promise it in release. Under
`neper test` the same record is captured into the failing test's JSON object rather
than the summary (§13).

`unreachable()` is the **one always-on builtin**: a call expression, legal in any
function, retained in every build mode, whose only effect is a trap of kind
`unreachable` with the optional `str` literal argument as its values —
`unreachable("token kind not handled")`. The compiler treats the point after it as
dead. It exists because a `switch` `default` that cannot happen, or a violated
invariant, has to be expressible, and because release elides every other check, so
a library could not build one from the constructs it has. Assertion helpers stay
libraries (§13): `test.assert` returns `test.Failed` rather than trap, and
`unreachable()` is for the path that cannot happen. Inside `@gpu` the CPU build carries the message;
the device build lowers `unreachable()` to the backend's trap instruction.

### Debug fills

Two fills exist in debug builds and neither exists in release. `mem.reset(a, m)`
fills `[m, a.off)` with `0xDD` before lowering `off`; `mem.alloc` fills the memory it
hands out with `0xCD`, the same byte `= undef` storage receives (§5). A slice that
outlives the `mem.reset` it should not have survived therefore reads back as
`0xDD 0xDD ...`, a read-before-write as `0xCD 0xCD ...`, and both are recognisable in
a debugger and in a failing test rather than being whatever the previous user left.
The cost is one memset per `reset` and per `alloc`; it buys detection of the one
lifetime hazard the arena model creates (§8) with no per-object bookkeeping, which is
why it fits under D3. These are fills, not checks: nothing traps, and `@nocheck` does
not remove them.

### Floating point

**No implicit contraction, in any build mode, on any target.** Every `f32` and
`f64` operation on the page is one IEEE 754 operation, correctly rounded to its
type: `a*x + y` is a multiply and then an add, two roundings, in a debug build, a
release build, the CPU build of a kernel and the device build alike. The optimiser
does not contract, reassociate, factor, drop a comparison a NaN could change, or
assume the sign of a zero. There is no fast-math flag and there will not be one: a
CPU and a GPU that agree bit for bit is what makes the CPU build a debugger (§10)
and `neper test` a test of a kernel.

Every floating operation that produces NaN returns one canonical positive quiet NaN
for its width (zero payload except the quiet bit); signaling NaN inputs are quieted to
that value. Loads, stores and `mem.bitcast` preserve NaN bits until an arithmetic or
math operation consumes them. This canonicalization, and signed-zero behavior, are
part of code generation on every backend. Scalar comparisons are the ordered rules
of §6; protocol container equality and total ordering are the distinct rules of §9.

Float division is under the same rule and is never a check: `x / 0.0` is `±inf`,
`0.0 / 0.0` is NaN, in every build mode on every target, exactly as IEEE 754 says —
§11's `divide` rows are integer rows.

`math.fma(a, b, c)` — with its lane-wise form `simd.fma` (§4) — is the **only fused
multiply-add** — one rounding, on every target: `vfmadd` at `x64-v3`, `fmadd` on
aarch64, the fused instruction on every GPU, and on `x64-v1`/`v2`, which have none,
a correctly rounded software sequence, slow and exact. A generator that wants the FMA
writes it, and the reviewer sees it. Vector arithmetic (§4) is under the same rule
lane by lane, and `simd.reduce_add` sums in a fixed tree so that it, too, is
bit-identical everywhere.

| Target | How the rule is kept |
|---|---|
| CPU emitters | A `*` feeding a `+` never selects a fused instruction; `math.fma` selects one. `min`/`max` are IEEE 754-2019 `minimum`/`maximum`, NaN-propagating, emitted as compare-and-select where the hardware's instruction is not |
| SPIR-V | Every arithmetic result carries `NoContraction`; no `FastMath` modes. `OpFDiv` and `sqrt` — which Vulkan bounds only to 2.5 ULP and to `inversesqrt`'s precision — are emitted as **correctly rounded sequences** over `Fma` with `NoContraction`, for `f32` and `f64` |
| PTX | `add.rn`, `mul.rn`, `div.rn`, `sqrt.rn`, and `fma.rn` for `math.fma` alone — the `.rn` forms, which `ptxas` does not contract — never `.approx` or `.full` |

For `math.min` and `math.max`, one NaN operand produces the canonical NaN rather than
selecting the number; `min(-0, +0)` is `-0` and `max(-0, +0)` is `+0`, independent
of operand order.

**Denormals are preserved.** The runtime never sets FTZ or DAZ in `MXCSR` or `FZ`
in `FPCR`; a SPIR-V module carries no denormal execution mode and a PTX module no
`.ftz`, so a device preserves `f32` denormals exactly when it does so by default —
which `gpu.has(dev, .DenormPreserve)` (§10) reports, and every desktop part does.
`@gpu(N, ftz)` is the opt-in for a kernel that would rather flush: it sets
`DenormFlushToZero` on SPIR-V (the launch-checked capability `.Ftz`), `.ftz` on
every PTX instruction, and FTZ and DAZ around the CPU build's run of that kernel, so
the three still agree. `f16` and `bf16` follow §4 — computed in `f32` under this
rule, then rounded — which is why their results are deterministic across targets
(D25). `ftz` applies to `f32` operations and therefore to the widened computation of
`f16` and `bf16`; it does not flush `f64`, whose denormals remain preserved.

**Approximate builtins**, the complete list: the transcendental family of
`e.math` — `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `exp` `exp2` `log`
`log2` `log10` `pow` — and `math.rsqrt`, which use the hardware's approximation on
a device and a software one on the CPU, each within a stated bound — on a device the
Vulkan specification's precision table applies; on the CPU every `e.math`
transcendental is within 2 ULP; `math.rsqrt` is within 2 ULP on both; the
per-function bounds are recorded in `lib/e/math.e` when it is implemented — and
not bit-identical to the other; and the float `gpu.subgroup_add`, `_min` and `_max`
reductions, which apply in hardware order. Everything else in `e.math` — `sqrt`,
`fma`, `abs`, `min`, `max`, `floor`, `ceil`, `round`, `trunc`, `copysign` — is exact
and identical everywhere. A kernel that uses no approximate builtin is
**bit-identical** between its CPU build and every device, subject only to the
exceptions §10's CPU execution model lists, and roadmap M3 is done when that holds.

The special-value contract is fixed even for approximate functions. `sqrt(x)` is NaN
for finite `x < 0` except that `sqrt(-0) == -0`; `log*` of a negative value is NaN and
of either zero is `-inf`; `exp*` overflow is `+inf` and underflow rounds normally;
`sin`, `cos` and `tan` of infinity are NaN; `asin` and `acos` outside `[-1, 1]` are
NaN; `atan` accepts infinities; and `atan2` follows IEEE quadrants and signed zeros.
`pow` follows IEEE 754 `pow`: an exponent of zero returns one, a negative finite base
with a non-integer exponent is NaN, and signed zero and infinity follow exponent sign
and odd-integer parity. ULP bounds apply only to finite, mathematically defined
results; these NaN, infinity and signed-zero outcomes are exact requirements.

Every `e.math` function is **comptime-generic over the float type**, one per
name (§14): `math.sqrt[T: type](x: T) -> T` for `T` in `f16`, `bf16`, `f32`, `f64`,
inferred from its argument per §9, so `math.sqrt(dot(v, v))` on an `f32` is
`sqrt[f32]`. `math.fma` is an intrinsic (§14) because the emitter must select the
fused instruction for it and for nothing else.

The functions with more than one argument are `atan2(y, x)`, `pow(x, y)`,
`fma(a, b, c)`, `min(a, b)`, `max(a, b)` and `copysign(x, y)`, every parameter and
the result `T`. `round` rounds **ties to even** — `RoundEven` on SPIR-V, the
round-to-nearest-even instruction on every CPU level — so the device and the host
agree on `round(2.5)`, which is `2.0`.

---

## 12. Compiled modules (`.em`)

Each module compiles to one file per target triple, named `<module>.<target>.em`:

```
math.x64-windows.em   math.aarch64-linux.em   math.x86-windows.em
math.spv.em      math.ptx.em
```

A dotted module name keeps its dots, and the files are written to
`.neper/<mode>/<module>.<target>.em` under the project root (§2) —
`.neper/debug/e.mem.x64-windows.em`, `.neper/release/e.mem.x64-windows.em` — so a debug and
a release `.em` of one module coexist by directory. A module's `.spv.em` or `.ptx.em` holds only its
device-reachable functions (§10, D24) and is produced by a host build for each GPU
target `--gpu` lists (§13, GPU targets in a build).

The final segments `windows`, `linux`, `macos`, `x64`, `x86`, `aarch64`, `spv` and
`ptx`, and compound suffixes formed from them, are reserved for source-target and
artifact selection. A user module or ordinary source basename whose final segment is
one of them is a compile error; this prevents `thing.windows.e` from being interpreted
both as a module and as the Windows variant of `thing`.

### Contents

| Part | Purpose |
|---|---|
| Header | magic `NEPM`, format version, target triple, flags, build mode |
| Strings | deduplicated UTF-8 strings referenced by numeric index from every other section; index 0 is the empty string |
| Interface | exported declarations — every module-scope declaration, the language having no visibility mechanism (§5) — in a compact binary form, each with its **signature hash**; for a `@gpu` kernel, its workgroup size, `shared` byte total and inferred capability set (§10); the module's error table — value to qualified name (§7); and the interface hash over the whole section |
| Deps | fine-grained edges (Incremental rebuilds, below): signature edges for foreign declarations, value edges for foreign constants, body edges for functions inlined, instantiated, comptime-executed or device-compiled, and lookup edges for every protocol name (§9) examined |
| NIR | typed IR for exported and inline-eligible functions and for every generic template, each with its **body hash**; kind 4 is reserved and the section is not written until a reader exists (D320) -- nothing read it, and at two million lines it was most of the artifact bytes |
| Code | machine code (or SPIR-V/PTX) with relocations: the module's own functions, plus the monomorphised instances and device-compiled helpers it emitted under module-local linkage; a relocation names its target by module, name and instance, or the library and symbol an `@import` binds |
| Debug | the standard-format debug sections of §13 — line tables, and the locals-and-types subset in DWARF or CodeView — plus the source hash; from M4, the neper-format side table beside them |
| Imports | the module's `use` declarations in order, each a module name and a qualifier (format 6, D322): a hot build discovers the program's graph from an unchanged module's artifact without parsing it |

The file is little-endian regardless of target. Its fixed 32-byte header is: bytes
`0..3` magic `NEPM`; `u16` format version; `u16` header size; `u32` target-triple
string-table index; `u32` flags; `u8` build mode; three reserved zero bytes; `u32`
section count; `u32` section-directory offset; and `u32` whole-file CRC32C with that
field zeroed. The directory has one 24-byte entry per section: `u32` kind, `u32`
flags, `u64` offset, `u64` length. Sections are ordered by kind, eight-byte aligned,
non-overlapping and contained in the file; unknown optional kinds are skipped and an
unknown required kind rejects the file. The Strings section opens with a `u32`
count and one `u32` offset per string from the section's start (format 5; format 6 adds the Imports section), so a
string is found in one read; each string is UTF-8 encoded as `u32` byte length
followed by bytes, with no terminator. Integers in Interface, Deps and NIR use
fixed-width little-endian fields; lists begin with `u32` counts. Every NIR opcode has
a versioned numeric ID and length-prefixed operands, so an unknown opcode rejects the
module rather than being misparsed. The compiler validates all counts, offsets,
lengths and UTF-8 before allocating from them. A version mismatch is a cache miss,
never a source diagnostic; the module is rebuilt.

Carrying **both** NIR and machine code is deliberate: NIR enables cross-module
inlining and re-emission for a different CPU feature level within the same target
triple and data layout; it does not retarget a target-dependent `.em` to another OS,
architecture or pointer width. Machine code makes linking a memcpy plus relocation
fixups.

### Incremental rebuilds

**Two hashes per declaration.** Every declaration carries a *signature hash* and a
*body hash*. The signature hash covers what a reference needs: the name, the kind,
the full type — parameters and their types, return types, comptime parameters,
struct fields in order, enum members and backing type, an error's qualified name —
and the attributes (§5). The body hash covers the signature hash plus the
declaration's NIR: a function's body, a generic template, a `const`'s evaluated
value. Both are **xxHash64 with seed 0** over the compiler's canonical little-endian
serialization — as is the content hash the own linker uses to find candidate duplicate
instances (§13); FNV-1a 32-bit is the error-value hash
alone (§7) — and are independent of thread count (§15). The interface hash over every exported signature hash survives as a
cheap first check, not as the rule.

**Edges, not module hashes.** While compiling module `A` the compiler records, per
foreign symbol or protocol lookup, the exact observation it depended on:

- a **signature edge** `(B, sym, signature-hash)` for every symbol of `B` that `A`
  calls, takes the address of, names as a type or uses as an error;
- a **value edge** `(B, sym, body-hash)` for every foreign `const` that `A` reads,
  because its evaluated value is compiled into `A`;
- a **body edge** `(B, sym, body-hash)` for every function of `B` whose NIR was
  compiled *into* `A`: inlined at a call site, instantiated with `A`'s comptime
  arguments (§9), executed by the interpreter for one of `A`'s `const`s or comptime
  arguments (§9), or compiled for the device because a kernel in `A` reaches it
  (§10, D24). Body edges are transitive: a body edge to `push[T]` carries body edges
  to everything `push[T]`'s expansion pulled in;
- a **lookup edge** `(B, name, observed-signature-or-absent)` for every protocol name
  (§9) that `A` looked up in `B`, including an incompatible declaration and every lookup that fell back to a
  compiler-supplied `hash`, `eq`, `cmp` or `format`, which records the fallback it
  took. Declaring that name in `B` later changes the edge, so a protocol added after
  an instantiation invalidates the instantiating module instead of being silently
  ignored.

A module is recompiled when its own source hash changes, when any recorded edge no
longer matches the current hash of its target, or when a protocol lookup produces a
different presence or signature. Nothing else recompiles it. Modules
compile in parallel; the edges of one build are the `Deps` of the next. Every edge
follows a `use`, and the `use` graph is acyclic (§2), so no module's edges lead back
to itself and the recompilation set of an edit is finite and ordered.

**What body isolation means.** Editing a function body leaves a dependent untouched
only when the dependent holds a signature edge and no body edge to it: the callee
was called, not inlined; it is not generic; it did not run at compile time; it is
not reachable from one of the dependent's kernels. For everything else the dependent
is recompiled, which is the correct outcome, because the old body is compiled into
it. The earlier rule — "editing a body never disturbs dependents" — would have
shipped the stale copy silently, the failure mode this language works hardest to
eliminate, in the build system itself.

**Inlining cap.** Cross-module inlining is limited to callees whose NIR body is at
most **40 instructions**. A larger callee is called through its exported symbol
however hot the site, and a call takes only a signature edge. The cap keeps body
edges confined to leaf helpers — accessors, arithmetic, a bounds test — so a body
edit in ordinary code recompiles nothing but its own module. Within one module there
is no cap: the module is one unit of recompilation anyway. Later optimiser
heuristics (roadmap M4) may inline less than the cap across a `.em` boundary, never
more.

**Where instances go.** A monomorphised instance of another module's generic, and a
plain function compiled for the device because this module's kernel reaches it, are
emitted into *this* module's `.em` — the instantiating or kernel-owning module —
with **module-local linkage**: not exported, not in the Interface, not the target of
anyone's edge. Two modules that both instantiate `push[i32]` each carry a copy; the
determinism rule (§15) makes the two copies byte-identical, and the own linker
(§13) groups copies by content hash and verifies full identity before folding, so the executable holds one `push[i32]`. Under
`--linker=system` each copy stays a local symbol in its own object and duplicates
cost bytes only. Ownership needs no coordination between modules, which is what
keeps their compilation parallel.

The own linker never treats a 64-bit hash match as identity. It first groups
candidates by hash, then compares their canonical NIR type identity, relocation graph
and emitted bytes; only byte-for-byte and relocation-for-relocation equal instances
fold. Hash collisions therefore affect speed, not correctness.

Canonical serialization fixes field and attribute order, integer widths, UTF-8
string encoding, float bit patterns, and NIR opcode and operand numbering. It contains
no addresses, map iteration order or thread-dependent identifiers. A change to that
serialization increments the `.em` format version and the data-layout version used
by the comptime cache.

**Incremental equals clean.** An incremental rebuild must produce an executable
byte-identical to a clean build of the same sources — §15's requirement across
thread counts, applied across time. The M2 harness (roadmap) checks it, and it is
the property the edge rule exists to deliver.

---

## 13. Toolchain

One binary, named `neper`, does everything — compile, format, index, disassemble.
There is no separate build system and no package manager.

```
neper build <file.e> [--target ARCH-OS|spv|ptx] [--gpu spv,ptx|none] [--cpu LEVEL]...
                     [--release] [--g] [--linker=own|system] [--arena SIZE]
                     [--libpath DIR] [--link LIB] [-j N] [-o PATH]
neper run <file.e> [the build options] [-- ARGS...]
neper fmt [--check] [FILE.e|-]
neper test [--filter PAT] [-j N] [--timeout SECS] [--release] [--test-arena SIZE] [FILE.e]
neper tokens [--path VIRTUAL.e] <FILE.e|->
neper parse [--path VIRTUAL.e] <FILE.e|->
neper index [--all] [--path VIRTUAL.e] [FILE.e|-]
neper dis <file.em> [--symbol NAME]   # disassemble a compiled module
neper dap            # neper's own debug adapter (M4); lldb-dap and codelldb work from neper-0
neper info            # versions, targets and machine-readable capabilities

--json               # every finite command: versioned JSONL from docs/tooling.md; not dap
--absolute-paths     # machine output: opt in to absolute paths; not dap
--language-version V # select an advertised MAJOR.MINOR source version
```

`neper run <file.e>` takes a **program root** — a file that declares `fn main`
(§2) — builds it and runs it, with everything after `--` as its `args`. `neper build
<file.e>` takes a program root and writes the executable, named by `-o PATH` or, by
default, by the root module's name in the working directory (`hello`, `hello.exe`);
or it takes any other `.e` file and writes its `.em` and those of the modules it
reaches, to `.neper/<mode>/` under the project root (§12). A file not under a
source root is module `<filename>`,
and `e.*` comes from the toolchain's own `lib/` (§2), so `neper run
examples/hello.e` builds and runs module `hello` from any working directory, with
no package around it. `--arena SIZE` sizes the root arena (§8; the default is
64 MiB) — `SIZE` is an integer with an optional `K`, `M` or `G` suffix, in binary
units — `--target` defaults to the full host triple, `--linker` selects the linker
(Linking, below), and `-j N` the worker count (§15). `--cpu LEVEL` selects the
instruction level (Target CPU levels, below) and is given **at most once per target
family** — `x64-*`, `aarch64-*` or `x86-*` for the host arch, `sm_*` for a `ptx`
module, embedded or standalone — so a host build with `--gpu ptx` writes `--cpu
x64-v4 --cpu sm_80`; a family given no level keeps its default, and a level whose
family the build does not target — `sm_80` under `--gpu spv`, `aarch64-v8.2` on an
x64 build — is an error.

`-o PATH` names the executable for a program root. For `--target spv|ptx` it names
the one root device `.em`; dependencies remain in `.neper/<mode>`. For a non-root
host module it must name an existing directory, into which that module's `.em` is
copied after the normal cache write; a file path is an option error. `run` accepts
`-o` for the temporary/persistent executable but never for captured program output.

A host target is `x64-windows`, `x64-linux`, `x64-macos`, `aarch64-windows`,
`aarch64-linux`, `aarch64-macos`, `x86-windows` or `x86-linux`; unsupported architecture/OS
combinations are option errors. The OS selects per-target source files and ABI, so it
is never inferred from the build machine after `--target` is written. `neper run`
requires that target to equal the host triple; otherwise it reports an option error
after building nothing. `--cpu native` is accepted only for a host-family target that
equals the host architecture and selects detected host features; it is invalid for
cross-compilation and never applies to SPIR-V or PTX.

`--libpath DIR` adds an ordered library search directory and may repeat. `--link LIB`
adds a static archive or import library by path or logical name and may repeat; logical
names search explicit directories, then the platform defaults. These options imply
`--linker=system` when the own linker cannot consume the named format. `@import` names
search the same directories at link time and use the platform mapping (`name.dll`,
`libname.so`, `libname.dylib`) unless the declaration supplies a filename containing
a separator or suffix. Search order and every resolved input are recorded in
`.neper/<mode>/build-manifest.json`, whose reproducible format is fixed by
`docs/tooling.md` §7. No arbitrary linker-argument escape hatch exists in v1.

**GPU targets in a build.** `--gpu` lists the GPU targets a host build embeds —
`spv`, `ptx` or `spv,ptx` — and defaults to `spv`; `--gpu none` is a host-only
build, and an `@gpu` declaration in the root's reachable module graph is a compile
error naming the kernel. Unreachable files outside that graph do not affect it. A host
build compiles every kernel-owning module — and only the device-reachable functions
in it and in the modules those reach (§10, D24) — once per listed GPU target into
`<module>.<gpu-target>.em` (§12), and embeds those Code sections in the executable
as the data §10 loads at runtime. `--target spv|ptx` alone builds only device
modules, for inspection with `neper dis`, and produces no executable. The device
half of a module never sees `use e.os` or any host-only declaration: device
compilation includes only the device-reachable functions (D24, D37), so `target.os`
is `.None` there and a host-only name is simply absent.

**`neper dis`** prints each function of a `.em` as address, bytes and mnemonic —
machine code for a CPU target, SPIR-V or PTX text for a device one — with a source
line marker, from `.nepersym`/`.nepsym` (Debug information, below), wherever the line
changes. `--symbol NAME` limits the output to one function; the file name carries
the target (§12), so there is no `--target` option. `NAME` is the canonical linkage
name printed by unfiltered output: `module.function` for ordinary functions and
`module.function[canonical-arguments]#content-hash` for module-local generic or
device instances. A non-unique source name is an error listing the canonical matches.

**`neper fmt`, `neper test` and `neper index`** operate on everything under the
project's roots (§2) — every `.e` file, for the first and the third; every module,
for `neper test`. A `FILE.e` argument names one file instead, which is how a file
outside every root — `examples/hello.e`, `examples/sample.e` — is formatted,
indexed, or has its module's `@test` functions run (Testing, below); `neper index
--all` also covers the toolchain's `lib/`. `fmt`, `tokens`, `parse`, and single-file
`index` accept `-` as stdin under the exact `--path` and output rules in
`docs/tooling.md` §4 and §6.

The versioned JSONL envelope, source identifiers, byte-precise spans, diagnostic and
fix records, lossless token/syntax trees, complete symbol/reference index, capability
query, test ordering, build manifest and generated-source maps are normative in
[`tooling.md`](tooling.md). In particular, `index` covers locals, members and
references as well as module-scope definitions, carries `module` explicitly, reports
compiler-generated protocol resolutions, and uses reproducible root-relative paths
unless `--absolute-paths` is requested. A harness never has to parse human output or
duplicate name resolution.

Successful commands exit `0`; source, option and link errors exit `1`; internal
compiler failures exit `2`; and `neper test` exits `1` when any test fails, crashes or
times out. Warnings are disabled in v1: every emitted diagnostic is either a note
attached to an error or an error that makes the command fail.

### Diagnostics

```
src/parse.e:112:9: error[E-TYPE-0003]: cannot pass `i64` where `i32` is expected
```

A code is `E-<CATEGORY>-<NNNN>` from the stable, checked registry
[`diagnostics.md`](diagnostics.md). Categories describe semantics and never depend on
this document's section order; a code is never reused. `--json` uses the versioned
diagnostic, related-location and structured-fix records of `docs/tooling.md` §3. A
runtime trap (§11) is a structured payload of a `run` or `test` record rather than
overloading a compiler diagnostic.

Diagnostics are sorted independently of worker completion: reproducible source
identifier, then byte offset, diagnostic code, and message. A primary error
precedes its notes, whose order is call-chain or source order as applicable. Command-
line and link diagnostics without a file sort before source diagnostics in argument
order. This order is identical in text and JSON modes.

### Program entry

Every executable has exactly one `main`, in the root module — the program root
named to `neper run` or `neper build` (§2, above) — with exactly this signature:

```
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    ...
    ret ok
}
```

It mirrors `@test` (Testing, below): one signature, no variants. A function named
`main` in the root module with any other signature is a compile error naming the
expected one; in any other module `main` is an ordinary function (§2).

- `a` is the **root arena** (§8): the block the startup code reserved and committed
  before `main` ran, sized by `--arena` (above). There is no other way to reach it. A
  program that wants a second arena carves one from this one or from a stack buffer.
- `args` are the command-line arguments, `args[0]` the program as it was invoked,
  each `str` allocated in the root arena by the startup code — what `os.args` (§5)
  returns.
- Returning `ok` exits the process with code `0`. Returning any other value writes
  one line, `error: <qualified name>` — `error: e.os.NotFound` — to stderr from
  the error table (§7), and exits with code `1`. `main`'s own `defer`s have already
  run, as on any `ret`.
- A failed check exits through the trap protocol (§11) with code `134` instead, and
  `os.exit(code)` (§5) exits with the code given and runs nothing.

Nothing runs before `main` except the startup code that builds the arena and the
argument slice: no static initialisers, no constructors, nothing a library can hook
(Testing, below, is the consequence).

If reserving or committing the root arena, decoding arguments, or allocating their
slice fails, startup writes `startup: <operation>: <platform code>` directly through
the platform's raw stderr facility and exits `1`. It cannot return an `err` or run a
`defer` because `main` has not begun. Failure to write the diagnostic still exits `1`.

### Testing

Testing is built in, because in neper a library could not do it. There are no
macros, no reflection, and no static initialisers — nothing runs before `main` — so
a library has no way to discover tests except a hand-maintained registration table.
That means writing every test name twice, and its failure mode is the worst one
available: a test that is written, compiles, and silently never runs.

```
use e.mem
use e.test
use lex

@test
fn parse_handles_empty_input(a: *mem.Arena) -> err {
    let toks = try lex.run("", a)
    if toks.len != 0 {
        ret test.Failed
    }
    ret ok
}
```

A test is a function marked `@test` taking a single arena and returning `err`. One
signature, no variants. Returning non-`ok` is failure. `e.test` is the module a
test imports: it declares `error Failed` for the plain-failure case and holds the
assertion helpers, which are ordinary functions — these four, and no more in
`e.test`:

| Function | Returns `Failed` when |
|---|---|
| `fn assert(cond: bool, msg: str) -> err` | `cond` is `false` |
| `fn eq[T: type](a: T, b: T, msg: str) -> err` | `T.eq(a, b)` is `false`; `T` is a type with an `eq` (§9), which includes every type `==` takes (§6) |
| `fn near(a: f64, b: f64, abs: f64, rel: f64, msg: str) -> err` | the distance between `a` and `b` exceeds both `abs` and `rel` times the larger magnitude |
| `fn fail(msg: str) -> err` | always |

Each returns `ok` otherwise and, on failure, records `msg` in the test's JSON object
(Report, below); none traps, so `try test.assert(toks.len == 0, "empty input lexes
to nothing")` is the idiom. `unreachable()` (§11) stays for the path that cannot
happen. Golden-file comparison is deferred (§17). How `msg` reaches the record:
`e.test` holds a module-scope `var current: *Record` — `type Record = struct {
... }`, the running test's record — which the synthesised root (Execution, below)
sets before each test; `assert`, `eq`, `near` and `fail` append `msg` through it,
and the root writes it out as the test's `end` record.

`near` requires finite, non-negative `abs` and `rel`; invalid tolerances return
`Failed`. Equal infinities pass, unequal infinities fail, and any NaN fails. For
finite operands it first accepts `abs(a-b) <= abs` when the subtraction is finite;
otherwise, or if that test fails, it sets `m = max(abs(a), abs(b))` and accepts when
`m != 0` and `abs(a/m - b/m) <= rel`. Outside a synthesized test root `current` is nil: helpers still
return `ok` or `Failed` normally and simply have no report record to append to. The
hidden pointer exists only in test builds, is initialized and cleared by compiler-
generated calls, and is the sole explicit exception to the library no-hidden-state
rule. Assertion helpers may be called only by the thread executing the test function;
calling them from a spawned worker is undefined behavior. Workers return results to
that thread explicitly before it joins them.

**The compiler owns exactly three things: discovery, isolation, reporting.**

- *Discovery* is free — every declaration is already in the symbol table, so `@test`
  is one bit. No registration, one definition site.
- *Isolation* is a process and fresh arena per test
  (Execution, below). Leak-free by construction, and "did this test exceed its
  memory budget" becomes an ordinary check rather than a tooling project.
- *Reporting* is a summary by default and `--json` for machines — one object per
  test (Report, below). This matters more here than usual: a structured pass/fail
  stream is what the tooling in §14 consumes.

`@test` functions are excluded entirely from non-test builds.

**Execution.** In a debug build the primary way a buggy test fails is a trap (§11),
which ends a process. So `neper test` never runs tests in its own process:

- **The test process's entry point is synthesised.** `neper test` generates a
  program root per module and invokes it once per test: a `main` (Program entry,
  above) that receives, through `args`, the module name and exact test name. The
  inherited control handle and nonce are reserved startup metadata, not program
  arguments. It calls only that test, writing a `begin` record before the call and, after it,
  one JSON record — the test's
  `name`, `outcome`, `error`, `message` and `duration_ms` — as its `end` record to
  the control handle. Every control record uses the trap protocol's length-prefixed
  JSON frame: the begin object is `{"begin": "<name>"}` and the end object is the
  test's result. The generated root imports the module under test under a
  compiler-internal qualifier containing a byte no source identifier can spell, so
  it cannot collide with a source alias or declaration — generated code is not
  subject to source-level invariants — so a module
  named `main`, or one that declares an ordinary `fn main` of its own (§2), is
  tested like any other.
- **One child process per test**, built in **debug**
  mode by default; `--release` is accepted and runs the same tests against release
  semantics (§11) — wrap, truncate, elided memory checks — with nothing else
  changed. The parent — `neper` itself — spawns it through `os.spawn`
  (§5) with its `stdout` and `stderr` on `os.pipe` ends and the write end of a
  control pipe in `Stdio.inherit`, its `raw` number in the child's `args` (§5); reads
  them, kills it with `os.kill` on a timeout, and writes the report; nothing the
  runner needs lies outside `e.os`. The process runs exactly the named test and exits.
- **Tests are scheduled in deterministic module/source order** but up to `-j N`
  child processes run at once (default: one per logical core, §15). Every test starts
  with fresh module-scope variables; no test can affect another's globals.
- **Each test gets a fresh arena** of **16 MiB** by default — `--test-arena SIZE`
  changes it, `SIZE` spelled as `--arena` spells it (above) — carved from the
  test process's root arena (Program entry, above); process exit then reclaims it.
- **stdout and stderr are captured per test.** They are dedicated pipes for that
  process. After it exits the parent drains both pipes to EOF before finalizing the
  record, so control-pipe delivery order cannot misattribute bytes.
- **A crash is an outcome, not the end of the run.** In test mode the trap runtime
  writes its machine-readable trap object to the inherited control pipe and the human
  rendering to stderr. User stderr can therefore never impersonate a trap. An
  abnormal exit without a trap object is still `crashed`; later tests already have
  independent processes and need no restart protocol.
- **Every test has a timeout**, `--timeout SECS`, default **60 seconds**. When it
  expires the parent kills the test process, records outcome `timeout`, and
  records the outcome and continues scheduling the remaining independent tests. The
  timeout uses `Clock.Monotonic`; `SECS` is a finite decimal in `(0, 86400]`, measured
  to the platform clock's millisecond ceiling.
- **`--filter PAT` selects tests** whose `module.test_name` contains `PAT`, with
  `*` as a wildcard for any run of characters: `e.str.*`, `*empty*`.
  Matching is case-sensitive over UTF-8 bytes; `\*` names a literal asterisk and
  `\\` a literal backslash. Any other escape is an option error. Zero matches is a
  successful run with a zero-test summary.
- **A `FILE.e` operand selects one module.** `neper test examples/sample.e` runs the
  `@test` functions of that file's module and nothing else, under every rule above —
  its own child process, a fresh arena per test, source order. The named file is a
  module whether or not it lies under a source root (§2), so this is how the `@test`
  functions of a file outside every root are run at all; with no operand, every
  module under the project's roots runs.
- **A test that spawns threads should join them before it returns.** Any remaining
  threads are terminated with that test's process after output pipes are drained;
  their incomplete work is not reported as a separate failure. Kernels run through the CPU backend
  (§10) inside the same process, so a `barrier` trap is a `crashed` outcome like any
  other.

**Report.** `--json` buffers completed children and emits one `record:"test"` object
per test in deterministic module/source order, never worker-completion order, then
one `record:"test_summary"` and the command `result` object. The common envelope and
summary counters are `docs/tooling.md` §7; each test record carries:

| Field | Value |
|---|---|
| `name`, `module`, `file`, `line` | the `@test` function's declaration |
| `outcome` | `"passed"`, `"failed"` (returned a non-`ok` `err`), `"crashed"`, `"timeout"` |
| `error` | the qualified name of the returned `err` (`"e.test.Failed"`), `"ok"`, or JSON null when the test did not return |
| `message` | the `msg` of the `test.assert` that failed, when one did; JSON null otherwise |
| `duration_ms` | monotonic elapsed time of the process, rounded up to milliseconds |
| `timeout_s` | the limit that applied |
| `stdout`, `stderr` | arbitrary captured bytes; valid UTF-8 is emitted as a JSON string, otherwise an object `{ "encoding": "base64", "data": "..." }` |
| `trap` | the nullable `trapPayload` of `docs/tooling.md`'s schema: `kind`, byte-precise nullable `span`, string `values`, and `backtrace`; for an abnormal exit that is not a language trap, `kind` is `"exit"` and `values` carries the code or signal |

The summary object carries the counts per outcome and the total duration. The
parent's exit code is `0` when every test passed and `1` otherwise; a crashed
test process never becomes the parent's exit code.

**Everything else stays a library**, and can, because none of it needs discovery:
assertion helpers, property generators, fakes, golden-file comparison. They are
ordinary neper functions that a test calls. The line is drawn here deliberately —
fixtures, mocking and parameterised cases are all reasonable requests, and none of
them belong inside a compiler.

**Known limitation:** `neper test` runs host-native tests only. Testing an aarch64
or x86-32 build from an x64 host needs an emulator, which is out of scope; those
targets require an explicit external runner. GPU kernels are tested through their CPU
build (§10), which is one of the better arguments for compiling `@gpu` functions
both ways.

### Linking

neper links its own executables. The compiler already holds the code and
relocations in memory, so the default path writes no object files and spawns no
process: NIR goes to machine code goes to a finished executable, with the
module-local instances of §12 folded by xxHash64 content hash (§12) on the way.

Whichever linker runs, `neper` holds every module's Interface, so it is `neper` that
merges the error tables (§7) into the executable and rejects a hash collision
before any linker is involved.

This is the single largest serial section of a build — everything else parallelises
(§15) — so it caps the speedup no matter how many cores are available. A system
linker costs milliseconds just to spawn, then writes objects to disk only to read
them back, re-parse symbol tables, and redo relocations we already computed. A full
relink runs 100ms–1s; doing it ourselves is realistically sub-10ms.

The work is staged by difficulty, because the two cases are not remotely equal:

| Case | Difficulty |
|---|---|
| Static pure-neper executable: a freestanding ELF, or a PE whose import table names `kernel32.dll` alone | Easy — a header, program headers, code, and one fixed import table. M2 |
| Dynamic imports by name from any `.dll`/`.so`/`.dylib` | Moderate — general import tables, PLT/GOT, load commands, and the PDB writer. Covers libc, Vulkan and the CUDA driver, and therefore most real programs. M4 |
| Static archives (`.a`/`.lib`) | Hard — COMDAT dedup, weak symbols, section GC. Never |

The easy case includes a PE with a fixed import table because without one it would
deliver nothing on Windows: a freestanding executable can do I/O only on Linux, over
raw system calls, and `hello.e`, the self-hosted compiler and `lib/e` all need
`kernel32` on Windows, which is one of the two M0 platforms. `kernel32.dll` is the
one library `os.windows.e` names — files, processes, memory, threads, the clock and
`LoadLibrary`/`GetProcAddress` for `os.dlopen` are all in it — so `e.io`,
`e.thread` and `e.time` on Windows are implemented over dynamic imports by
construction, and a fixed table of that one DLL is a few hundred bytes the linker
writes the same way every time. The general case, any library by name, waits for M4.

The third case is where an own linker stops being worth it, so **`--linker=system`
stays permanently** as the escape hatch for static archives and exotic platform
requirements. It is also what M0 and M1 use while the own linker does not exist yet,
behind a seam thin enough to swap: one function that writes objects and spawns a
process, with nothing about object files leaking into the backend.

Which stage a program needs follows from its `extern` declarations (§5) and from the
target's `e.os`. A program whose only OS surface is `e.os` is the easy case
on Linux, where `os.linux.e` issues raw system calls and imports nothing, and on
Windows, where every import is `kernel32`. Any other `@import` — the program's own,
or `e.os` on macOS (`libSystem`), which is every executable for that target —
needs the dynamic-import stage; the GPU runtime's Vulkan and CUDA driver bindings
(§5) are such imports, so a program that opens a `.Vulkan` or `.Cuda` device links
with `--linker=system` until M4 (roadmap). An `@import` whose `LIB` exists only as a
static archive needs `--linker=system`.

Platform obligations we are taking on: PE import tables and base relocations, SEH
`.pdata`/`.xdata`, ELF `PT_*` headers and `DT_NEEDED`, Mach-O load commands and
chained fixups, **ad-hoc code signing on Apple Silicon**, which is mandatory rather
than optional — an unsigned aarch64 binary will not execute — and, on Windows, **the
PDB**: the MSF container with the DBI, module, symbol and line streams, and no type
stream. That scope is what symbolication, breakpoints and stepping need; the type
stream that would carry the locals-and-types subset (Debug information, below) into
a PDB is not scheduled, so a Windows build that wants locals in the debugger links
with `--linker=system`, whose PDB carries the CodeView records the compiler emits.
The PDB writer lands with the dynamic-import stage at M4. **Until then, Windows
symbolication by any external tool — WinDbg, Visual Studio, ETW, a debugger —
requires `--linker=system`.** The trap protocol's own backtrace (§11) does not,
under either linker: it reads the `.nepersym` section (`.nepsym` on COFF/PE;
Debug information, below),
which the compiler emits into every object file it writes and the own linker writes
directly, and which the runtime finds through the executable's own section table.

### Target CPU levels

Which instructions the emitter may use is a build option, not a property of the
language. Nothing in the front end or in NIR is ISA-aware; instruction selection,
register allocation and scheduling are the emitter's job alone.

For x86-64 we adopt the industry-standard microarchitecture levels verbatim rather
than inventing our own feature flags:

| `--cpu` | Requires | Notes |
|---|---|---|
| `x64-v1` | SSE2 | The 2003 baseline. Maximum compatibility. No narrow-float support: `f16`/`bf16` are widened in software. |
| `x64-v2` | SSE4.2, POPCNT, CMPXCHG16B | |
| **`x64-v3`** | **AVX2, FMA, BMI1/2, LZCNT, MOVBE, F16C** | **Default.** F16C converts `f16`↔`f32` in hardware; arithmetic still widens to `f32`. |
| `x64-v4` | AVX-512F/BW/CD/DQ/VL | Opt-in only — see below. Narrow arithmetic still widens to `f32` here: AVX-512 FP16/BF16 are not part of the level, and the native instructions are selected only under `native` on a machine that has them (Sapphire Rapids, Zen 4+). |

Other targets:

| `--cpu` | Meaning |
|---|---|
| `x86-v1` | i686 baseline with SSE2. **Default** for x86-32, and its only level |
| `aarch64-v8.0` | ARMv8.0-A, NEON (mandatory in the base ISA). `f16` converts natively, computes via `f32`. 2011-era; opt-in |
| **`aarch64-v8.2`** | Adds native FP16 arithmetic and dot product. **Default** for aarch64: Apple Silicon and every recent ARM server qualify |
| `aarch64-v8.6` | Adds native BF16 arithmetic |
| **`sm_50`** | PTX ISA 6.0, the floor (§10). **Default** for `ptx`; `f16` and `bf16` arithmetic widen to `f32` |
| `sm_70` | Adds `f16` arithmetic (available from `sm_53`) and independent thread scheduling |
| `sm_80` | Adds `redux.sync` for the integer subgroup reductions and native `bf16` arithmetic |
| `sm_90` | Hopper; the profile selects no instruction beyond `sm_80`'s, and the level exists so a build can name the part |
| `native` | Detect and target the building machine. Never the default — it produces binaries that fault elsewhere. |

**`x64-v3` is the default, deliberately, and `x64-v4` is not.** AVX-512 is absent
from Alder Lake and later Intel consumer parts, present on Zen 4/5, and on some
earlier Intel server parts it triggers frequency throttling that costs more than the
wider vectors gain. `v3` is close to universal on hardware from the last decade and
carries the instructions that actually matter.

Register allocation is affected as much as instruction selection: `v4` exposes 32
vector registers rather than 16, which changes allocation decisions well beyond the
choice of mnemonic.

**Instructions we will not select implicitly.** `pdep`/`pext` are microcoded and
extremely slow on AMD before Zen 3. They are available as explicit `simd` intrinsics
and are never chosen by the emitter on your behalf.

**Runtime dispatch** — one binary carrying several versions of a hot function,
selected by CPUID at startup — is deferred past M4. When it lands it will be explicit
(an `@cpu("x64-v4")` attribute on the function, the level as a string so the
token is a legal literal), never automatic. Until then `@cpu` is not an attribute
(§5).

**ARM SVE is out of scope.** Its vector length is not known at compile time, which
does not map onto fixed-width types like `Vec[f32, 8]`. aarch64 targets NEON's fixed
128-bit vectors; SVE is a separate problem for later.

**On the GPU**, SPIR-V capabilities and subgroup operations are the equivalent knob,
declared per kernel.

### Debug information

Debug information goes out in the standard formats, in a fixed subset, on the
default path — because the readers already exist and neper's own would not for three
milestones. Neper's own compact form is an optimisation layered on top at M4, not
the route to a working debugger.

**Emitted always, in standard formats, in every build mode:**

| What | Format | Why it is not optional |
|---|---|---|
| Line tables | `.debug_line` (ELF/Mach-O); on Windows, CodeView line records — into the PDB under `--linker=system`, and under the own linker from the M4 PDB writer (Linking, above); the trap protocol reads `.nepersym` (`.nepsym` on COFF/PE) under both | The cheapest part of DWARF — a small state machine, no DIE tree |
| Symbol tables | ELF `.symtab`, Mach-O `LC_SYMTAB`, COFF symbols | Symbolication for every external tool |
| Unwind info | `.eh_frame`, or `.pdata`/`.xdata` on Windows | Correct stack walks, required in release too |

This trio is what perf, VTune, Superluminal, Instruments, ETW and every crash-dump
pipeline actually read. For a language whose whole pitch is hardware utilisation,
users live in a profiler, and a profiler that cannot symbolise is worthless.

**The trap protocol's data source is `.nepersym` (`.nepsym` on COFF/PE).** PE's
`IMAGE_SECTION_HEADER.Name` is eight bytes, so `.nepersym` cannot be represented in
a linked PE image; `.nepsym` is the fixed platform spelling, not linker truncation.
The compiler emits the line
and symbol tables a second time, in its own compact form, as a named non-loaded
section `.nepersym` (or `.nepsym`) in every object file it writes under
`--linker=system`. The
compiler also emits a linker-retention directive (`/include` on COFF, `SHF_GNU_RETAIN`
or a generated linker script on ELF, `no_dead_strip` on Mach-O). Each contribution is
a length-prefixed table with relocatable symbol references; the final link
concatenates contributions, applies relocations and emits a sorted address index.
Duplicate entries with the same address, canonical name and line table fold. The own
linker performs the same merge directly from `.em`s. The runtime locates it through the
executable's own section table — PE, ELF or Mach-O — so §11's symbolised backtrace
has one source in every build mode, whichever linker produced the binary and
whether or not a PDB exists.

The merged `.nepersym`/`.nepsym` begins with `NEPS`, `u16` version, `u16` reserved zero and
`u32` entry count. Each fixed-size entry contains `u64 start`, `u64 end`, and `u32`
indices for canonical function name, file and line-program; entries sort by
`(start,end,name)` and ranges are half-open. A following UTF-8 string table and
delta-encoded line programs use the same bounded length encoding as `.em`. The
runtime binary-searches the address table, applies the executable load bias, and
prints an address with `?` fields when no entry covers it. Malformed or absent data
degrades to raw addresses and never prevents the original trap.

**Emitted in every debug build, from `neper-0` (roadmap) onward, as the default
path: locals and types in a fixed subset of DWARF (ELF, Mach-O) and CodeView
(PE).** The subset is the tags in this table and nothing beyond them:

| Tag | Carries |
|---|---|
| `compile_unit` | one per module: name, producer, language, line-table offset |
| `subprogram` | one per function: name, linkage name, address range, frame base |
| `formal_parameter`, `variable` | name, type, location |
| `base_type` | every primitive of §4, including `f16`, `bf16`, `err` (as `u32`) and `bool` |
| `structure_type`, `member` | `struct`, and the `{ptr, len}` of a slice, the tag-and-payload of a `union enum`, the wrapped value of `Atomic[T]` |
| `union_type` | bare `union` |
| `enumeration_type` | `enum`, and the `Tag` of a `union enum` |
| `pointer_type`, `const_type` | pointers and pointee const qualification |
| `subroutine_type` | the parameter and return signature referenced by every function pointer |
| `array_type` | `[N]T` and `Vec[T, N]` |
| `inlined_subroutine` | one per inlined call site — release builds with `--g` only, below |

Every location is one `DW_OP_fbreg` offset from the frame base (or the CodeView
equivalent, `S_REGREL32` against the frame pointer). A debug build gives every named
local a frame slot for its whole scope and writes it back at every assignment, so
one location covers the scope and there are no location lists, no `.debug_loc`, no
`.debug_ranges`; one abbreviation table, written once, covers every module. That is
hundreds of lines of emitter, not thousands, and it is read by `lldb`, `gdb`,
WinDbg and Visual Studio, and through them by `lldb-dap` and `codelldb` in VS Code
and Zed, from the first milestone that has locals to show. The full generality of
DWARF — location lists, expression programs, type units, DWARF 5 string offsets —
is where its cost lives, and none of it is emitted. A release build carries the
trio only; `--g` adds the subset to a release build, and there every inlined call
site is recorded as an `inlined_subroutine` so a backtrace still names the function
on the page.

**Debug builds do not inline.** The inliner is off in a debug build, in every
module and across every `.em` boundary, so every frame in a backtrace is a real
call, a breakpoint on a function is hit whenever it runs, and a step never enters a
body that is not on the page. The other passes — constant folding, DCE, register
allocation — stay on; none of them moves a local out of its frame slot.

**Neper's own format, at M4, as an optimisation.** The `.em` already carries a
typed NIR and a full type table, so a side table of locals, scopes and locations
over structures that are serialised anyway is nearly free to write, loads in
microseconds, and knows things the standard formats cannot express — that a
`[]const u8` is a string, which arena a slice points into, the poison bytes of §11,
the work item a CPU-built kernel is stepping (§10). It goes into the `Debug`
section beside the standard subset (§12), never instead of it, and it is read by
`neper dap` and the debug engine beneath it (Editor integration, below). It is
sequenced after the standard path because it is worthless without that engine, and
the engine is the expensive part.

### Editor integration

VS Code and Zed are both DAP clients: neither reads DWARF or PDB directly. Both
already ship adapters over `lldb` — `lldb-dap` and `codelldb` — and `lldb` reads
the subset above. From `neper-0`, then, editor debugging costs **zero** adapters: install
the extension, point it at the executable, set a breakpoint, inspect locals. On
Windows the split is this: **symbolication** — backtraces, profilers — works through
the own PDB from M4, which carries module, symbol and line streams and no type
stream (Linking, above); **locals in a debugger** need types, so on Windows they go
through the CodeView records in the object files plus `--linker=system`'s PDB for
as long as the PDB type stream stays deferred (§17).

`neper dap` is neper's own adapter, at M4, over neper's own debug engine, and it
exists for what a generic debugger cannot do: render a slice as its bytes and a
tagged union as its live member, show the arena a pointer belongs to, and step one
work item of a CPU-built kernel with the workgroup's shared state visible (§10). The
adapter itself is a thin JSON-RPC server; the substance is the engine beneath it —
process control (`ptrace` on Linux, Mach exception ports and the debugger
entitlement on macOS, `DebugActiveProcess` on Windows), `int3` breakpoint patching,
single-step, stack walking, and rendering variables from location records — which
is why it is sequenced after the standard path exists, and not before.

Editor *language* smarts — highlighting, go-to-definition, hover — are a separate
concern travelling over LSP, not DAP. `neper index` (§14) is the seed a language
server would grow from; none is scheduled.

### Standard library

The library surfaces this document does not write — `e.algo.sort`, `e.data.map`,
the rest of `e.thread` beyond `spawn`, `join`, `detach` and `DEFAULT_STACK` (§8) — are
specified by their library source and indexed by `neper index` (§14). This
document is authoritative only where it writes a signature; where it does not, the
source is.

---

## 14. Invariants for tooling and generated code

These are language rules, not style advice. They exist so that a search, a glob or a
line-anchored edit is *reliable* rather than probabilistic.

1. **One definition per name per module namespace.** No overloading, ever. The sole
   parallel namespaces are types and qualifier/value names, selected by syntax as
   §2 states; locals may not exploit that separation. `grep -n "^fn dot"` returns
   exactly one line in the module that defines it.
2. **Every top-level declaration starts at column 0** with one of
   `use type const var fn error extern`. The only other thing at column 0 is an attribute
   line (§5), which sits above its declaration rather than in front of it —
   precisely so that the keyword stays first on its own line. A comment line may
   also start at column 0: a comment begins with `//`, never with a keyword, so
   `grep "^fn"` is unaffected. The parser relies on this too: an unclosed bracket
   may not cross one of these keywords (§3), so a dropped `)` is caught at the
   bracket that opened it rather than cascading through the file.
3. **File path is module name.** A glob finds a module without opening it.
4. **Every cross-module reference written by the author is qualified.** A call site
   someone wrote names its module. The invariant governs what is written in source,
   so there are exactly two exceptions and neither appears as an unqualified call on
   any line. The first is a protocol call on a comptime type parameter or a comptime
   type value (§9) — `T.hash(v)`, `f.ty.format(x, b)` — legal only in a generic or
   comptime body, where no concrete module exists yet to name. The second is the
   calls the compiler generates on the author's behalf: `for`'s `next` (§6), a format
   verb's `format` (§4), and a container's `hash`, `eq` or `cmp` on a concrete
   element type — nothing is written at those sites, so there is nothing to qualify.
   What any of them resolves to is
   still one `grep "^fn sensor_hash"` away, and the type is in the name.
5. **No macros, no preprocessor, no textual code generation.** What you read is what
   compiles.
6. **No implicit conversions.** Every cast is written down and greppable; the five
   implicit operations that exist are listed once, in §6.
7. **Order-independent module scope.** An insertion can go anywhere; no forward
   declarations to keep in sync.
8. **One canonical layout**, enforced by `neper fmt --check`. Diffs stay minimal and
   edits are textually predictable. `docs/tooling.md` §6 fixes the complete contract,
   including whitespace, wrapping, blank lines, attributes, imports, comments and
   stdin behavior. It deliberately preserves semantically meaningful author choices
   such as parentheses and numeric base, so it does not overclaim one spelling per
   syntax tree.
9. **`neper index`** emits versioned JSONL of every definition and reference — with
   explicit kind, name, qualified name, module, signature, attributes, byte-precise
   spans and resolved target — so tools do not parse source or duplicate protocol
   lookup. `docs/tooling.md` §5 is the closed schema. An intrinsic (below) has kind
   `intrinsic` and a null span because it is declared in no `.e` file.
10. **Casing is enforced**, by the table in §3, which is canonical: `snake_case`
    for functions and values (variables, parameters, fields), for modules, and for
    the comptime binding an unrolled `for` introduces (§9), which is a local
    binding and not a parameter; `PascalCase` for types, enum members, errors and
    type-kind comptime parameters; `SCREAMING_SNAKE` for constants and value-kind
    comptime parameters. A name's kind is legible without a lookup, and a search
    pattern never has to guess at casing.
11. **Tokens and syntax are public data.** `neper tokens` and `neper parse` expose
    the grammar's lossless, versioned result with original-byte spans. A formatter,
    editor or generation harness never needs a private compiler API.
12. **Generated code keeps provenance.** An optional `.e.map.json` maps generated
    spans to generator inputs without changing language semantics or introducing a
    preprocessor (`docs/tooling.md` §8).

**Intrinsics.** A closed set of core functions has no neper body and no declaration
— an intrinsic appears in no `.e` file; the compiler knows each under its qualified
name: `mem.cast`, `mem.bitcast`, `mem.address_of`, `mem.size_of`
and `mem.align_of` (§4, §8), `meta.*` (§9), `atomic.*` (§8), `os.syscall` and
`os.thread_start` (§5),
`math.fma` (§11), `simd.*` (§4), the `gpu.*` builtins (§10), and the three pack
functions `io.printf`, `str.format` and `gpu.launch` (§9) — the only functions in
the language with a pack parameter; the `...` on an `extern` (§5) is a C variadic,
not a pack. `unreachable()` (§11) is the one builtin that is a keyword rather than a
core function, which is why it alone needs no qualifier. A module whose whole surface is intrinsics — `e.simd` is the only one — still has
its file under `lib/e`, so `use` resolves it as it resolves any module; the file
declares the module's types and nothing else. They are called like any
other function, so invariants 1, 4 and 6 hold at every call site, and `neper index`
lists each with kind `intrinsic` and no file or line, so a tool never searches
`lib/e` for a body that is not there.

---

## 15. Compile speed and parallelism

### Single-thread budget

- Lex → parse → resolve/typecheck → NIR → regalloc → emit. No pass manager, no
  separate optimisation pipeline.
- Optimisations limited to inlining, constant folding, DCE and a good linear-scan
  register allocator. This is roughly `-O1` and it is deliberate. Inlining is off
  in debug builds (§13) and capped at 40 NIR instructions per callee across a
  `.em` boundary (§12).
- All compiler data structures are arena-allocated and never freed; the process
  exits instead.
- Strings interned once at lex time; identifiers compare as integers thereafter.
- No LLVM, and no external linker on the default path once the own linker lands
  (M2 for the easy case, M4 for dynamic imports; `--linker=system` remains for
  static archives, §13).

### Parallelism

Scaling across cores is a design constraint on the compiler's architecture, not an
optimisation applied afterwards. Several earlier decisions exist partly to serve it.

**Phase 1 — lex and parse — is embarrassingly parallel.** Because neper has no
preprocessor, no textual includes, no macros and no order-dependent module scope
(§2, §14), *every source file can be parsed without knowing anything about any other
file*. There is no coordination to do: hand N files to N threads. This is
structurally unavailable to C and C++, where headers make parsing context-dependent,
and to languages whose macros must run before the parse completes.

**Phase 2 — typecheck, NIR, codegen — parallelises at function granularity.**
Interfaces are built in `use` order, which exists because the `use` graph is a DAG
(§2): a module's interface needs only those of the modules it uses, and a cycle
would have no first module to build. Once interfaces exist, each function body is
independent. Function-level rather than
module-level work items matter on high-core-count machines, where a project may have
fewer modules than the machine has threads.

**Work-stealing, not static partitioning.** A fixed thread pool with per-thread
Chase-Lev deques. This is not just a load-balancing nicety: on hybrid CPUs — Intel
P-cores and E-cores, Apple's performance and efficiency cores — an equal static split
strands the whole build behind the slowest E-core. Work-stealing absorbs a 2–3×
per-core speed difference with no special casing.

**Per-thread arenas, and no shared allocator.** This is where §8 pays off. Allocator
contention is the classic reason compilers stop scaling; neper has no global
allocator to contend on. Each worker owns its arena, and per-thread state is padded
to cache-line boundaries to avoid false sharing.

**Two genuinely shared structures: the string intern table and the comptime
instantiation cache (§9).** Both are sharded by hash prefix so contention is spread,
and they are the only places in the compiler where threads meet on the hot path.

**Hyperthreading: default to logical cores, but measure.** SMT helps the branchy,
pointer-chasing, memory-latency-bound work in the front end, and helps much less in
register allocation and emission, which are throughput-bound. The default is one
worker per logical core; `-j N` overrides it. We are not going to claim a number
before there is something to benchmark.

**Determinism is a hard requirement.** Output must be byte-identical regardless of
thread count or scheduling. No thread-order-dependent identifiers, no codegen that
depends on hash iteration order, and diagnostics collected per module then sorted
into source order before printing. A build that varies with `-j` is a build you
cannot cache, diff, or reproduce.

**Known serial points**, listed because Amdahl's law is unforgiving and these are
what will actually cap the speedup:

| Serial section | Mitigation |
|---|---|
| Linking | The reason neper links its own executables (§13) |
| Interface construction for a dependency chain | Parse-only phase 1 shortens it; deep chains still serialise |
| Final executable write | Unavoidable |

NUMA-aware thread pinning and per-node arenas are deferred; they matter only on
large multi-socket machines.

---

## 16. Standard library: time

The coordinated next-contract standard-library changes in
[`stdlib-hardening.md`](stdlib-hardening.md) and D84 apply during M2.5 migration of
delivered CPU surfaces. Their exact declarations are in `module-apis.md`: composable
buffered I/O, common cancellation/deadline control, lossless JSON/data editing,
handle-relative filesystem operations and bounded process supervision. H07 replaces
legacy temporal error-detail transport in that revised checked profile. Until its
versioned implementation lands, the archived M2 compiler retains its original ABI;
do not treat these signatures as proof of current availability. Later crypto,
networking, test-support and image/codecs retain their independent delivery gates.
Ordinary parameter syntax and the §5 shadowing rules are unchanged. The module plan
and actual toolchain capabilities have distinct authorities (SL11).

`e.time` allocates nothing, anywhere. Every type is a plain struct on the stack.

```
type Timestamp = struct { nanos: i64 } // wall clock, UTC, Unix epoch
type Instant   = struct { nanos: i64 } // monotonic, arbitrary epoch
type Duration  = struct { nanos: i64 }
type Date      = struct { year: i32, month: u8, day: u8 }
type Time      = struct { hour: u8, minute: u8, second: u8, nanos: u32 }
type Timer     = struct { started: Instant }
```

The three clock types are `i64` underneath, `Date` and `Time` are civil fields,
`Timer` wraps one `Instant`, and all six are **distinct types**. Because there are
no implicit conversions (§4), the compiler rejects adding two timestamps, passing an
`Instant` where a `Timestamp` belongs, or mixing a duration with a point in time.
The strictness already paid for elsewhere buys this for free.

**`Instant` and `Timestamp` are separate on purpose.** Elapsed time is measured with
the monotonic clock; a wall clock can jump backwards under NTP, a DST change or a
manual set, and measuring a duration with one is a classic production bug. Making
them different types turns that into a compile error.

```
fn now() -> (Timestamp, err) // os.clock(.Wall)
fn monotonic() -> (Instant, err) // os.clock(.Monotonic)
fn timer_start() -> (Timer, err) // Timer{ started: try monotonic() }
fn timer_elapsed(t: Timer) -> Duration // since(t.started)
fn since(start: Instant) -> Duration // monotonic() - start; a clock that read once reads again

let start = try time.monotonic()
...
try io.printf["took {}us\n"](time.as_micros(time.since(start)))
```

Both direct clock reads and `timer_start` are fallible because `os.clock` (§5) is:
the wrapper does not
swallow an `err` the OS returned. `since` is not, because a clock that has already
been read on this thread does not start failing; should the read fail regardless,
`since` traps through `unreachable()` (§11) rather than return a value it did not
measure. `timer_elapsed` has exactly the same post-first-read rule as `since`.

The rest of the surface, every function pure and allocation-free:

| Function | Semantics |
|---|---|
| `fn timestamp_add(t: Timestamp, d: Duration) -> Timestamp`, `fn instant_add(t: Instant, d: Duration) -> Instant` | an ordinary `+` on the `nanos`: an `overflow` check in debug, wraps in release (§11) |
| `fn timestamp_diff(a: Timestamp, b: Timestamp) -> Duration`, `fn instant_diff(a: Instant, b: Instant) -> Duration` | `a - b` |
| `fn duration_add(a: Duration, b: Duration) -> Duration`, `fn duration_sub(a: Duration, b: Duration) -> Duration`, `fn duration_neg(d: Duration) -> Duration`, `fn duration_scale(d: Duration, n: i64) -> Duration` | duration with duration: `+`, `-`, unary `-` and `*` on the `nanos`, each an `overflow` check in debug and wrapping in release (§11) |
| `fn timestamp_cmp(a: Timestamp, b: Timestamp) -> i32` | `-1`, `0`, `1`; likewise `instant_cmp` and `duration_cmp` |
| `fn days(n: i64) -> Duration`, `hours`, `minutes`, `seconds`, `millis`, `micros`, `nanos` | constructors |
| `fn as_days(d: Duration) -> i64`, `as_hours`, `as_minutes`, `as_seconds`, `as_millis`, `as_micros`, `as_nanos` | truncating toward zero |
| `fn to_date(t: Timestamp) -> Date`, `fn to_time(t: Timestamp) -> Time` | civil fields in UTC |
| `fn to_date_at(t: Timestamp, offset_minutes: i32) -> Date`, `to_time_at` | at an explicit zone offset |
| `fn from_civil(d: Date, t: Time) -> (Timestamp, err)` | the inverse; an invalid date is `time.Invalid` |
| `fn format_iso8601(t: Timestamp, buf: []u8) -> str` | `2026-09-04T12:00:00.000000000Z`, 30 bytes; `buf.len < 30` is a `bounds` check |
| `fn parse_iso8601(s: str) -> (Timestamp, err)` | that form, or without the fraction; else `time.Invalid` |

`e.time` declares one error, `Invalid`. The comparators and the arithmetic are
spelled `<t>_<op>` — `timestamp_cmp`, `instant_add`, `duration_scale` — because that
is §9's protocol convention (D52) and not merely a way around having no overloading
(§14): the three clock types are distinct on purpose, and under this spelling
`timestamp_cmp`, `instant_cmp` and `duration_cmp` are exactly what `e.algo.sort` and every
ordered container find when they look up `fn <t>_cmp` in the module that declares the
type, where a bare `cmp` would resolve to nothing and leave a `Timestamp` unsortable.
The constructors, accessors and conversions — `days`, `as_millis`, `to_date`,
`format_iso8601` — carry no prefix: each exists once, over one type, and nothing
looks one up by protocol.

`Date` is valid for years 1677 through 2262, months 1 through 12 and a day present in
that proleptic-Gregorian month. `Time` requires hour 0–23, minute and second 0–59,
and nanos below 1,000,000,000; leap seconds are not accepted. `offset_minutes` is in
`[-1439, 1439]`. `from_civil` rejects a valid civil value whose nanosecond timestamp
does not fit `i64`. Duration constructors and arithmetic use the ordinary debug-
checked/release-wrapping integer rules stated in the table. ISO parsing accepts
exactly `YYYY-MM-DDTHH:MM:SSZ` or that form with `.` followed by one through nine
decimal digits, padded on the right to nanoseconds; no whitespace, lowercase `t/z`,
offset or leap second is accepted. Years remain four digits because the representable
`Timestamp` range lies inside 1677–2262.

**Formatting needs no arena.** A formatted date has a bounded length, so it goes in a
caller-supplied stack buffer and the function returns a slice into it. Strings need
an arena because their length is unbounded; dates never do.

```
var buf: [32]u8 = undef
let s = time.format_iso8601(now, buf[0..])
```

**Civil conversion is pure arithmetic** — days-from-civil, no lookup tables — so
`to_date`, `to_time` and their inverses are usable inside `@gpu` — requiring
`.Int8` for their `u8` fields and `.Int64` for the arithmetic (§10, Capabilities);
`from_civil`'s `err` is an ordinary value in device code (§10). Reading a clock is
an OS call — `time.now` and `time.monotonic` are `os.clock(.Wall)` and
`os.clock(.Monotonic)` (§5) — so they are not.

### UTC only

`e.time` handles UTC and nothing else. Time zones are an explicit offset in minutes:

```
let local = time.to_date_at(now, 120) // UTC+02:00
```

The IANA time zone database is megabytes of data plus file I/O plus a parser. None
of that can live in a freestanding core library that allocates nothing, so a real
tz database is a separate library for programs that need one.

Leap seconds are ignored, following Unix convention.

**Accepted cost:** "what is the local time in Europe/Sofia" is not answerable from
`e.time` alone. That is the right trade for a systems language and the wrong one for
business software, and it is a deliberate choice rather than an oversight.

---

## 17. Open questions

No unresolved semantic design question remains as of 2026-09-04. The concrete
grammar is `docs/grammar.ebnf`; the public token, syntax, index, diagnostic, format,
manifest, source-map and capability contracts are `docs/tooling.md`; stable codes
are allocated in `docs/diagnostics.md`; the module architecture is `docs/modules.md`;
the exact proposed toolchain APIs are `docs/module-apis.md`; and the normalized,
machine-readable library plan is `docs/modules.json`. These companions are normative
parts of this specification, not implementation notes.

Before compiler implementation begins, the documentation phase has four mechanical
exit criteria: every code example parses under the grammar, every rejected example
names a registered diagnostic, the `tests/conformance/` corpus described by
`docs/tooling.md` §9 exists, and the initial multi-tokenizer generated-code benchmark
is recorded. Those are verification deliverables with fixed formats, not choices an
implementer is allowed to make. Character count alone is never used as evidence of
LLM token efficiency. `docs/general-purpose-verification.md` defines the broader
workload corpus, model-generation metrics and release gates without adding language
semantics.

Deliberately deferred rather than undecided, each with its rationale in place:
runtime CPU dispatch and its `@cpu("...")` attribute (§13), ARM SVE (§13),
NUMA-aware thread pinning (§15), auto-vectorisation (§4), static-archive linking
(§13), cross-target test execution (§13), golden-file comparison in `e.test`
(§13), a native Metal backend (§10, scheduled as
M5), an argument-pack API for user code (§9), spreading a CPU-backend launch over
several host threads (§10), a PDB type stream (§13), and an Android host — an
`.Android` member of `target.Os` with its `os.android.e` (§5, §6), which the
Vulkan backend would then reach (§10).

Not targeted at all, so that nobody reads their absence as an oversight: RISC-V,
WebAssembly, 32-bit ARM, any big-endian ISA, iOS, DirectX, WebGPU, graphics
pipelines, and Vulkan 1.1 devices (§10, D22: below the floor, not deferred). Each
CPU ISA is a hand-written emitter and each GPU backend is an emitter plus a
runtime; the list stays short on purpose.
