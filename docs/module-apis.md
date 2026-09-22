# neper module API catalogue

Status: exact public-surface proposal for the toolchain modules in `modules.md`.
Delivery commitment and presentation order come from `modules.json`'s `core`,
`extended` and `experimental` tiers; this file remains dependency-layer ordered.
This is the next-contract design, not an installed-toolchain availability report.
The coordinated changes in `stdlib-hardening.md` migrate delivered CPU APIs during
M2.5-core or T2 according to ownership; later facilities retain their stated delivery gates. Semantic details in `spec.md` remain
authoritative; this file fixes names, public value shapes and signatures. A module
implements no additional public declaration unless this file is amended.

Notation follows neper source except where a compiler intrinsic's signature uses the
explicit dependent metavariables documented with that intrinsic. `type X = struct {
state: *void }` is the uniform one-word handle for arena-allocated implementation
state. Such a value is physically copyable, but only one copy may remain live for
operations that consume or mutate the state; copying never creates a second owner.
Callback context is always explicit; there are no closures. Read-only slices are
`[]const T`.

Qualified names in signatures resolve through that module's `direct_dependencies`
in `modules.json`. They use the dependency's final segment except
`linalg_tensor`, the explicit alias for `e.algo.linalg.tensor`; `e.ui.widget` additionally
uses `layout` for `e.text.layout` and `ui_layout` for `e.ui.layout`; `e.async.io` uses
`cancel_api` for `e.cancel` because it declares `cancel`. Imports themselves are
not public declarations. The catalogue's declaration fragments intentionally omit
function bodies and are not standalone modules.

The extraction contract is intentionally mechanical: each module occurs exactly once
as a level-three code heading, and the first and only `neper` fence before the next
level-three heading contains all of that module's public declarations in canonical
order. Prose after the fence adds constraints but no declaration. A harness locates a
surface by exact heading; it never scans the whole document for a short name.

---

## 1. Language foundations

### `e.mem`

```neper
type Arena = struct { base: *u8, cap: usize, off: usize }
type Stats = struct { used: usize, capacity: usize }
error Exhausted

fn arena_from(buf: []u8) -> Arena
fn alloc[T: type](a: *Arena, n: usize) -> ([]T, err)
fn mark(a: *Arena) -> usize
fn reset(a: *Arena, m: usize)
fn view(a: *const Arena, start: usize, len: usize) -> []u8
fn copy[T: type](dst: []T, src: []const T)
fn eq[T: type](x: []const T, y: []const T) -> bool
fn cast[P: type, Q: type](p: Q) -> P
fn bitcast[T: type, U: type](x: U) -> T
fn address_of[T: type](p: *const T) -> usize
fn size_of[T: type]() -> usize
fn align_of[T: type]() -> usize
fn stats(a: *const Arena) -> Stats
```

`view` exposes arena storage the caller already owns as a slice, which is how a
structure that records an offset rather than a slice reaches its own bytes; `start`
and `len` follow the ordinary bounds-trap rule. For `cast`, `P` and `Q` must be pointer types; callers spell `P` and inference fills
the trailing `Q` from `p`. For `bitcast`, callers spell `T` and inference fills `U`
from `x`; the representation restrictions are those in spec §4 and §8.

### `e.meta`

```neper
type Field = struct { name: str, ty: type, offset: usize, size: usize }
type Member = struct { name: str, value: u64 }
type TypeKind = enum u8 { Int, Float, Bool, Err, Pointer, Slice, Array, Struct, Enum, UnionEnum, Vec }

fn fields[T: type]() -> []const Field
fn members[E: type]() -> []const Member
fn type_name[T: type]() -> str
fn kind[T: type]() -> TypeKind
fn signed[T: type]() -> bool
fn element_type[T: type]() -> type
fn array_len[T: type]() -> usize
fn backing_type[E: type]() -> type
fn get[FIELD: Field, T: type](v: *const T) -> FIELD.ty
fn set[FIELD: Field, T: type](v: *T, x: FIELD.ty)
```

`Field` and `Member` are comptime-only types exactly as specified by spec §9.

### `e.math`

Every function is generic over `F`, which must be `f16`, `bf16`, `f32` or `f64`.

```neper
fn sqrt[F: type](x: F) -> F
fn rsqrt[F: type](x: F) -> F
fn fma[F: type](a: F, b: F, c: F) -> F
fn abs[F: type](x: F) -> F
fn min[F: type](a: F, b: F) -> F
fn max[F: type](a: F, b: F) -> F
fn floor[F: type](x: F) -> F
fn ceil[F: type](x: F) -> F
fn round[F: type](x: F) -> F
fn trunc[F: type](x: F) -> F
fn copysign[F: type](x: F, y: F) -> F
fn sin[F: type](x: F) -> F
fn cos[F: type](x: F) -> F
fn tan[F: type](x: F) -> F
fn asin[F: type](x: F) -> F
fn acos[F: type](x: F) -> F
fn atan[F: type](x: F) -> F
fn atan2[F: type](y: F, x: F) -> F
fn exp[F: type](x: F) -> F
fn exp2[F: type](x: F) -> F
fn log[F: type](x: F) -> F
fn log2[F: type](x: F) -> F
fn log10[F: type](x: F) -> F
fn pow[F: type](x: F, y: F) -> F
```

### `e.simd`

`V` is a legal `Vec[T,N]`; `M` is its `Mask[T,N]`; `I` is an integer vector with
the same lane count where required.

```neper
fn splat[V: type](x: T) -> V
fn load[V: type](s: []const T, off: usize) -> V
fn store[V: type](s: []T, off: usize, v: V)
fn load_aligned[V: type](s: []const T, off: usize) -> V
fn store_aligned[V: type](s: []T, off: usize, v: V)
fn load_masked[V: type](s: []const T, off: usize, m: M) -> V
fn store_masked[V: type](s: []T, off: usize, m: M, v: V)
fn gather[V: type](s: []const T, indices: Vec[u32, N]) -> V
fn shuffle[V: type, IDX: [N]u8](a: V, b: V) -> V
fn cmp_eq[V: type](a: V, b: V) -> M
fn cmp_ne[V: type](a: V, b: V) -> M
fn cmp_lt[V: type](a: V, b: V) -> M
fn cmp_le[V: type](a: V, b: V) -> M
fn cmp_gt[V: type](a: V, b: V) -> M
fn cmp_ge[V: type](a: V, b: V) -> M
fn select[V: type](m: M, yes: V, no: V) -> V
fn any[V: type](m: M) -> bool
fn all[V: type](m: M) -> bool
fn bits[V: type](m: M) -> u64
fn mask[V: type](packed: u64) -> M
fn reduce_add[V: type](v: V) -> T
fn reduce_min[V: type](v: V) -> T
fn reduce_max[V: type](v: V) -> T
fn convert[V: type, W: type](v: V) -> W
fn fma[V: type](a: V, b: V, c: V) -> V
fn pdep(x: u64, bit_mask: u64) -> u64
fn pext(x: u64, bit_mask: u64) -> u64
```

Here `V = Vec[T,N]`, `M = Mask[T,N]`, and `W` is another vector with `N` lanes. `T`,
`N` and `M` in these signatures are dependent names inferred from `V`, matching the
notation already used by spec §4; they add no runtime reflection.

### `e.atomic`

```neper
type Ordering = enum u8 { Relaxed, Acquire, Release, AcqRel, SeqCst }

fn init[T: type](v: T) -> Atomic[T]
fn load[T: type](p: *Atomic[T], o: Ordering) -> T
fn store[T: type](p: *Atomic[T], v: T, o: Ordering)
fn xchg[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn cas[T: type](p: *Atomic[T], expected: T, desired: T, success: Ordering, failure: Ordering) -> (bool, T)
fn add[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn sub[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn and[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn or[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn xor[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn min[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn max[T: type](p: *Atomic[T], v: T, o: Ordering) -> T
fn fence(o: Ordering)
```

---

## 2. Pure foundations

### `e.bytes`

```neper
type Endian = enum u8 { Little, Big }
type Base64Alphabet = enum u8 { Standard, Url }
type Base32Alphabet = enum u8 { Standard, Hex }
type Base85Alphabet = enum u8 { Ascii85, Z85 }
type Reader = struct { data: []const u8, off: usize }
type Writer = struct { data: []u8, off: usize }
error End
error Invalid
error TooLarge

fn reader(data: []const u8) -> Reader
fn writer(data: []u8) -> Writer
fn remaining_reader(r: *const Reader) -> usize
fn remaining_writer(w: *const Writer) -> usize
fn skip(r: *Reader, n: usize) -> err
fn read[T: type](r: *Reader, endian: Endian) -> (T, err)
fn write[T: type](w: *Writer, v: T, endian: Endian) -> err
fn read_bytes(r: *Reader, n: usize) -> ([]const u8, err)
fn write_bytes(w: *Writer, src: []const u8) -> err
fn load[T: type](src: []const u8, off: usize, endian: Endian) -> (T, err)
fn store[T: type](dst: []u8, off: usize, v: T, endian: Endian) -> err
fn reverse_in_place(data: []u8)
fn rotate_left[T: type](v: T, n: u32) -> T
fn rotate_right[T: type](v: T, n: u32) -> T
fn count_ones[T: type](v: T) -> u32
fn leading_zeros[T: type](v: T) -> u32
fn trailing_zeros[T: type](v: T) -> u32
fn base64_encoded_len(n: usize, padded: bool) -> (usize, err)
fn base64_encode(dst: []u8, src: []const u8, alphabet: Base64Alphabet, padded: bool) -> (str, err)
fn base64_decode(dst: []u8, src: str, alphabet: Base64Alphabet) -> ([]u8, err)
fn base32_encoded_len(n: usize, padded: bool) -> (usize, err)
fn base32_encode(dst: []u8, src: []const u8, alphabet: Base32Alphabet, padded: bool) -> (str, err)
fn base32_decode(dst: []u8, src: str, alphabet: Base32Alphabet) -> ([]u8, err)
fn base85_encoded_len(n: usize, alphabet: Base85Alphabet) -> (usize, err)
fn base85_encode(dst: []u8, src: []const u8, alphabet: Base85Alphabet) -> (str, err)
fn base85_decode(dst: []u8, src: str, alphabet: Base85Alphabet) -> ([]u8, err)
```

Generic numeric operations accept integer and float primitives only; bit operations
accept unsigned integers only. Base32 accepts the RFC 4648 standard and extended-hex
alphabets with optional canonical padding. Base85 supports unframed ASCII85 and Z85;
Z85 rejects input outside its four-byte or five-character quantum.

### `e.str`

```neper
type Sink = struct { ctx: *void, write: fn(ctx: *void, bytes: []const u8) -> err }
type Builder = struct { arena: *mem.Arena, start: usize, len: usize, reserved: usize, sink: Sink, flushing: bool }
type Split = struct { source: str, separator: str, off: usize, finished: bool }
error NotOnTop
error BadNumber
error InvalidSeparator

fn builder(a: *mem.Arena, cap: usize) -> (Builder, err)
fn builder_to(a: *mem.Arena, cap: usize, sink: Sink) -> (Builder, err)
fn done(b: *Builder) -> str
fn concat(a: *mem.Arena, x: str, y: str) -> (str, err)
fn join(a: *mem.Arena, parts: []const str, sep: str) -> (str, err)
fn eq(x: str, y: str) -> bool
fn format[FMT: str](a: *mem.Arena, args: ...) -> (str, err)
fn parse_i64(s: str) -> (i64, err)
fn parse_u64(s: str) -> (u64, err)
fn parse_f32(s: str) -> (f32, err)
fn parse_f64(s: str) -> (f64, err)
fn parse_i64_radix(s: str, radix: u8) -> (i64, err)
fn parse_u64_radix(s: str, radix: u8) -> (u64, err)
fn compare(x: str, y: str) -> i32
fn compare_ascii_fold(x: str, y: str) -> i32
fn starts_with(s: str, prefix: str) -> bool
fn ends_with(s: str, suffix: str) -> bool
fn contains(s: str, needle: str) -> bool
fn find(s: str, needle: str) -> (usize, bool)
fn find_from(s: str, needle: str, start: usize) -> (usize, bool)
fn rfind(s: str, needle: str) -> (usize, bool)
fn count(s: str, needle: str) -> usize
fn trim(s: str) -> str
fn trim_start(s: str) -> str
fn trim_end(s: str) -> str
fn trim_bytes(s: str, bytes: str) -> str
fn split_once(s: str, separator: str) -> (str, str, bool)
fn split(s: str, separator: str) -> (Split, err)
fn split_next(it: *Split) -> (str, bool)
fn lines(s: str) -> Split
fn replace(a: *mem.Arena, s: str, needle: str, replacement: str) -> (str, err)
fn repeat(a: *mem.Arena, s: str, repeat_count: usize) -> (str, err)
fn ascii_lower_in_place(s: []u8)
fn ascii_upper_in_place(s: []u8)
fn is_ascii_space(b: u8) -> bool
fn is_ascii_digit(b: u8) -> bool
fn is_ascii_alpha(b: u8) -> bool
fn is_ascii_alnum(b: u8) -> bool
fn push(b: *Builder, s: str) -> err
fn push_byte(b: *Builder, v: u8) -> err
fn push_bool(b: *Builder, v: bool) -> err
fn push_err(b: *Builder, v: err) -> err
fn push_i8(b: *Builder, v: i8) -> err
fn push_i16(b: *Builder, v: i16) -> err
fn push_i32(b: *Builder, v: i32) -> err
fn push_i64(b: *Builder, v: i64) -> err
fn push_isize(b: *Builder, v: isize) -> err
fn push_u8(b: *Builder, v: u8) -> err
fn push_u16(b: *Builder, v: u16) -> err
fn push_u32(b: *Builder, v: u32) -> err
fn push_u64(b: *Builder, v: u64) -> err
fn push_usize(b: *Builder, v: usize) -> err
fn push_hex_u32(b: *Builder, v: u32) -> err
fn push_hex_u64(b: *Builder, v: u64) -> err
fn push_bin_u32(b: *Builder, v: u32) -> err
fn push_bin_u64(b: *Builder, v: u64) -> err
fn push_f32(b: *Builder, v: f32) -> err
fn push_f64(b: *Builder, v: f64) -> err
fn push_f32_fixed(b: *Builder, v: f32, precision: u8) -> err
fn push_f64_fixed(b: *Builder, v: f64, precision: u8) -> err
```

All search indices and slices are byte offsets. The trim functions without an
explicit byte set remove ASCII whitespace only; Unicode whitespace and case mapping
belong to `e.text.unicode`. An empty `needle` is found at the requested valid starting
offset, `rfind` returns `s.len`, and `count` returns `s.len + 1`; replacement follows
the same non-overlapping boundary rule. `split` returns `InvalidSeparator` for an
empty separator and otherwise preserves empty fields. `lines` recognizes LF and CRLF,
removes the terminator and does not synthesize a final empty line. Radices are in
`2..36`.

### `e.path`

Paths are pure strings and always name the convention being applied; host behavior is
never inferred inside this module.

```neper
type Style = enum u8 { Posix, Windows }
type Parts = struct { root: str, dir: str, base: str, stem: str, ext: str }
error Invalid

fn separator(style: Style) -> u8
fn is_absolute(path: str, style: Style) -> bool
fn split(path: str, style: Style) -> Parts
fn basename(path: str, style: Style) -> str
fn dirname(path: str, style: Style) -> str
fn extension(path: str, style: Style) -> str
fn stem(path: str, style: Style) -> str
fn join(a: *mem.Arena, parts: []const str, style: Style) -> (str, err)
fn normalize(a: *mem.Arena, path: str, style: Style) -> (str, err)
fn relative(a: *mem.Arena, base: str, target_path: str, style: Style) -> (str, err)
fn replace_extension(a: *mem.Arena, path: str, ext: str, style: Style) -> (str, err)
type Glob = struct { state: *const void }
type GlobOptions = struct { style: Style, case_sensitive: bool, max_pattern_bytes: usize, max_steps: usize }
error TooLarge

fn glob(a: *mem.Arena, pattern: str, options: GlobOptions) -> (Glob, err)
fn glob_match(pattern: *const Glob, path: str) -> (bool, err)

```

Globs are pure matching over relative paths, not filesystem traversal. * and ? match
within a component; a whole ** component matches zero or more components. Bracket
classes support ASCII ranges and ! negation; malformed patterns are Invalid.
Pattern separators are /; input separators follow the explicit Style. Matching is
byte-exact unless ASCII case folding is requested, never host-locale dependent.
Literal dotfiles are not implicitly excluded. Parent/absolute paths are Invalid;
matching proves no filesystem containment. Work-limit exhaustion is TooLarge, not
false. Ignore-file precedence/negation is application policy, not an implicit glob rule.

---

## 3. Containers and traversal

### `e.data.list`

```neper
type List[T: type] = struct { items: []T, len: usize, arena: *mem.Arena }
type Iter[T: type] = struct { items: []const T, index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (List[T], err)
fn from_slice[T: type](a: *mem.Arena, src: []const T) -> (List[T], err)
fn slice[T: type](l: *List[T]) -> []T
fn slice_const[T: type](l: *const List[T]) -> []const T
fn reserve[T: type](l: *List[T], capacity: usize) -> err
fn push[T: type](l: *List[T], v: own T) -> err
fn pop[T: type](l: *List[T]) -> (T, bool)
fn insert[T: type](l: *List[T], index: usize, v: own T) -> err
fn remove[T: type](l: *List[T], index: usize) -> T
fn clear[T: type](l: *List[T])
fn iter[T: type](l: *const List[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

### `e.data.deque`

```neper
type Deque[T: type] = struct { items: []T, head: usize, len: usize, arena: *mem.Arena }
type Iter[T: type] = struct { deque: *const Deque[T], index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Deque[T], err)
fn len[T: type](d: *const Deque[T]) -> usize
fn reserve[T: type](d: *Deque[T], capacity: usize) -> err
fn push_front[T: type](d: *Deque[T], v: own T) -> err
fn push_back[T: type](d: *Deque[T], v: own T) -> err
fn pop_front[T: type](d: *Deque[T]) -> (T, bool)
fn pop_back[T: type](d: *Deque[T]) -> (T, bool)
fn get[T: type](d: *const Deque[T], index: usize) -> T
fn clear[T: type](d: *Deque[T])
fn iter[T: type](d: *const Deque[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

### `e.data.stack`

```neper
type Stack[T: type] = struct { items: list.List[T] }
type Iter[T: type] = struct { stack: *const Stack[T], remaining: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Stack[T], err)
fn len[T: type](s: *const Stack[T]) -> usize
fn reserve[T: type](s: *Stack[T], capacity: usize) -> err
fn push[T: type](s: *Stack[T], value: own T) -> err
fn peek[T: type](s: *const Stack[T]) -> (T, bool)
fn pop[T: type](s: *Stack[T]) -> (T, bool)
fn clear[T: type](s: *Stack[T])
fn iter[T: type](s: *const Stack[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

Iteration is LIFO order and does not mutate the stack.

### `e.data.queue`

```neper
type Queue[T: type] = struct { items: deque.Deque[T] }
type Iter[T: type] = struct { queue: *const Queue[T], index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Queue[T], err)
fn len[T: type](q: *const Queue[T]) -> usize
fn reserve[T: type](q: *Queue[T], capacity: usize) -> err
fn enqueue[T: type](q: *Queue[T], value: own T) -> err
fn peek[T: type](q: *const Queue[T]) -> (T, bool)
fn dequeue[T: type](q: *Queue[T]) -> (T, bool)
fn clear[T: type](q: *Queue[T])
fn iter[T: type](q: *const Queue[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

Iteration is FIFO order and does not mutate the queue.

### `e.data.linked`

```neper
type NodeId = u32
const NONE: NodeId = 4294967295
type Node[T: type] = struct { value: T, previous: NodeId, next: NodeId, live: bool }
type List[T: type] = struct { nodes: list.List[Node[T]], first: NodeId, last: NodeId, len: usize }
type Iter[T: type] = struct { list: *const List[T], next: NodeId }
error InvalidNode
error TooLarge

fn init[T: type](a: *mem.Arena, capacity: usize) -> (List[T], err)
fn len[T: type](l: *const List[T]) -> usize
fn first[T: type](l: *const List[T]) -> (NodeId, bool)
fn last[T: type](l: *const List[T]) -> (NodeId, bool)
fn node[T: type](l: *const List[T], id: NodeId) -> (*const Node[T], err)
fn push_front[T: type](l: *List[T], value: own T) -> (NodeId, err)
fn push_back[T: type](l: *List[T], value: own T) -> (NodeId, err)
fn insert_before[T: type](l: *List[T], at: NodeId, value: own T) -> (NodeId, err)
fn insert_after[T: type](l: *List[T], at: NodeId, value: own T) -> (NodeId, err)
fn remove[T: type](l: *List[T], id: NodeId) -> (T, err)
fn clear[T: type](l: *List[T])
fn iter[T: type](l: *const List[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

Node identifiers remain stable across insertions and removals because removed slots
are not reused. A removed identifier and every identifier issued before `clear`
returns `InvalidNode`. Insertion returns `TooLarge` before a node identifier would
overflow. The nodes and list borrow the arena for their lifetime.

### `e.data.ring`

```neper
type Ring[T: type] = struct { items: []T, head: usize, len: usize }
type Iter[T: type] = struct { ring: *const Ring[T], index: usize }

fn init[T: type](storage: []T) -> Ring[T]
fn len[T: type](r: *const Ring[T]) -> usize
fn capacity[T: type](r: *const Ring[T]) -> usize
fn push[T: type](r: *Ring[T], v: own T) -> bool
fn push_overwrite[T: type](r: *Ring[T], v: own T) -> (T, bool)
fn pop[T: type](r: *Ring[T]) -> (T, bool)
fn peek[T: type](r: *const Ring[T]) -> (T, bool)
fn clear[T: type](r: *Ring[T])
fn iter[T: type](r: *const Ring[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

### `e.data.map`

```neper
type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }
type Iter[K: type, V: type] = struct { state: *const void, slot: usize }
type SetIter[K: type] = struct { inner: Iter[K, bool] }

fn init[K: type, V: type](a: *mem.Arena, capacity: usize) -> (Map[K, V], err)
fn len[K: type, V: type](m: *const Map[K, V]) -> usize
fn reserve[K: type, V: type](m: *Map[K, V], capacity: usize) -> err
fn put[K: type, V: type](m: *Map[K, V], key: K, value: own V) -> (bool, err)
fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool)
fn get_ptr[K: type, V: type](m: *Map[K, V], key: K) -> (*V, bool)
fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool)
fn clear[K: type, V: type](m: *Map[K, V])
fn set_init[K: type](a: *mem.Arena, capacity: usize) -> (Set[K], err)
fn set_add[K: type](s: *Set[K], key: K) -> (bool, err)
fn set_has[K: type](s: *const Set[K], key: K) -> bool
fn set_remove[K: type](s: *Set[K], key: K) -> bool
fn iter[K: type, V: type](m: *const Map[K, V]) -> Iter[K, V]
fn iter_next[K: type, V: type](it: *Iter[K, V]) -> (K, V, bool)
fn set_iter[K: type](s: *const Set[K]) -> SetIter[K]
fn set_iter_next[K: type](it: *SetIter[K]) -> (K, bool)
```

### `e.data.heap`

```neper
type Heap[T: type] = struct { items: list.List[T] }
type HeapBy[T: type, Ctx: type] = struct { items: list.List[T], ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32 }
type Iter[T: type] = struct { items: []const T, index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Heap[T], err)
fn from_slice[T: type](a: *mem.Arena, source: []const T) -> (Heap[T], err)
fn len[T: type](h: *const Heap[T]) -> usize
fn push[T: type](h: *Heap[T], v: own T) -> err
fn peek[T: type](h: *const Heap[T]) -> (T, bool)
fn pop[T: type](h: *Heap[T]) -> (T, bool)
fn clear[T: type](h: *Heap[T])
fn init_by[T: type, Ctx: type](a: *mem.Arena, capacity: usize, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err)
fn from_slice_by[T: type, Ctx: type](a: *mem.Arena, source: []const T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err)
fn len_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> usize
fn push_by[T: type, Ctx: type](h: *HeapBy[T, Ctx], value: own T) -> err
fn peek_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> (T, bool)
fn pop_by[T: type, Ctx: type](h: *HeapBy[T, Ctx]) -> (T, bool)
fn clear_by[T: type, Ctx: type](h: *HeapBy[T, Ctx])
fn heapify_in_place[T: type](items: []T)
fn heapify_in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32)
fn iter[T: type](h: *const Heap[T]) -> Iter[T]
fn iter_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (T, bool)
```

The default heap is a min-heap under `T.cmp`; `HeapBy` uses `cmp`. Bulk construction
is linear time. Iteration exposes internal heap order, not sorted order.

### `e.data.fenwick`

```neper
type Fenwick = struct { tree: []i64 }
error TooSmall

fn init(tree: []i64) -> Fenwick
fn from_values(tree: []i64) -> Fenwick
fn len(f: *const Fenwick) -> usize
fn add(f: *Fenwick, index: usize, delta: i64)
fn prefix_sum(f: *const Fenwick, count: usize) -> i64
fn range_sum(f: *const Fenwick, low: usize, high: usize) -> i64
fn get(f: *const Fenwick, index: usize) -> i64
fn set(f: *Fenwick, index: usize, value: i64)
fn lower_bound(f: *const Fenwick, total: i64) -> usize
```

`tree.len` is the element count and the storage; `from_values` builds in place in
`O(n)`. `lower_bound` assumes non-negative elements and answers `len + 1` when no
prefix reaches the total.

### `e.data.sparse_table`

```neper
type SparseTable[T: type] = struct { table: []T, count: usize, levels: usize, prefer_max: bool }
type DisjointTable = struct { table: []i64, count: usize, levels: usize }
error TooSmall
error Invalid

fn levels_for(count: usize) -> usize
fn build[T: type](storage: []T, values: []const T, prefer_max: bool) -> (SparseTable[T], err)
fn query[T: type](t: *const SparseTable[T], low: usize, high: usize) -> (T, err)
fn disjoint_build(storage: []i64, values: []const i64) -> (DisjointTable, err)
fn disjoint_query(t: *const DisjointTable, low: usize, high: usize) -> (i64, err)
```

`storage.len >= n * levels_for(n)`. `build` orders by `T.cmp` (min, or max with
`prefer_max`) and `query` is `O(1)` over a half-open range; the disjoint table answers
sums, which are not idempotent, in the same time.

### `e.data.segment_tree`

```neper
type SegmentTree[T: type] = struct { nodes: []T, count: usize, identity: T }
type Lazy = struct { sums: []i64, mins: []i64, pending: []i64, count: usize }
type Persistent = struct { left: []u32, right: []u32, sums: []i64, used: usize, count: usize }
error TooSmall
error Invalid

fn build[T: type, Ctx: type](nodes: []T, values: []const T, identity: T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (SegmentTree[T], err)
fn build_node[T: type, Ctx: type](t: *SegmentTree[T], node: usize, low: usize, high: usize, values: []const T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T)
fn update[T: type, Ctx: type](t: *SegmentTree[T], index: usize, value: T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> err
fn query[T: type, Ctx: type](t: *const SegmentTree[T], low: usize, high: usize, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (T, err)
fn query_node[T: type, Ctx: type](t: *const SegmentTree[T], node: usize, low: usize, high: usize, from: usize, to: usize, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> T
fn lazy_build(sums: []i64, mins: []i64, pending: []i64, values: []const i64) -> (Lazy, err)
fn lazy_build_node(t: *Lazy, node: usize, low: usize, high: usize, values: []const i64)
fn lazy_apply(t: *Lazy, node: usize, width: usize, delta: i64)
fn lazy_push(t: *Lazy, node: usize, low: usize, high: usize)
fn lazy_add(t: *Lazy, low: usize, high: usize, delta: i64) -> err
fn lazy_add_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize, delta: i64)
fn lazy_sum(t: *Lazy, low: usize, high: usize) -> (i64, err)
fn lazy_sum_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize) -> i64
fn lazy_min(t: *Lazy, low: usize, high: usize) -> (i64, err)
fn lazy_min_node(t: *Lazy, node: usize, low: usize, high: usize, from: usize, to: usize) -> i64
fn persistent_build(left: []u32, right: []u32, sums: []i64, values: []const i64) -> (Persistent, u32, err)
fn persistent_build_node(t: *Persistent, low: usize, high: usize, values: []const i64) -> u32
fn persistent_add(t: *Persistent, root: u32, index: usize, delta: i64) -> (u32, err)
fn persistent_add_node(t: *Persistent, old: u32, low: usize, high: usize, index: usize, delta: i64) -> u32
fn persistent_sum(t: *const Persistent, root: u32, low: usize, high: usize) -> (i64, err)
fn persistent_sum_node(t: *const Persistent, node: u32, low: usize, high: usize, from: usize, to: usize) -> i64
```

`SegmentTree[T]` folds any associative `combine` with an identity over `4 * n`
nodes; `Lazy` is the `i64` tree with range addition and range sum and minimum;
`Persistent` keeps every version in a node pool (`2 * n` for the build plus
`ceil(log2 n) + 1` per update) and answers a root per version.

### `e.data.spatial`

```neper
type KdTree = struct { points: []const f64, d: usize, order: []usize }
type QuadTree = struct { x0: f64, y0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, used: usize, items: usize, xs: []f64, ys: []f64 }
type OcTree = struct { x0: f64, y0: f64, z0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, used: usize, items: usize, xs: []f64, ys: []f64, zs: []f64 }
type IntervalTree = struct { starts: []const f64, ends: []const f64, order: []usize, left: []u32, right: []u32, centre: []f64, first: []u32, count: []u32, used: usize }
type Best = struct { node: usize, distance: f64 }
type HashGrid = struct { cell: f64, x0: f64, y0: f64, columns: usize, rows: usize, head: []u32, next: []u32, xs: []f64, ys: []f64, count: usize }
type RTree = struct { items: []const f64, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8, used: usize, root: usize }
type Bvh = struct { boxes: []const f64, order: []usize, box: []f64, left: []u32, right: []u32, first: []u32, count: []u32, used: usize }
type RangeTree = struct { xs: []const f64, ys: []const f64, n: usize, order: []usize, pool: []usize, levels: usize }
type BallTree = struct { tree: KdTree, centre: []f64, radius: []f64 }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn coordinate(t: *const KdTree, i: usize, axis: usize) -> f64
fn build_range(t: *const KdTree, lo: usize, hi: usize, depth: usize)
fn kd_build(points: []const f64, n: usize, d: usize, order: []usize) -> (KdTree, err)
fn distance_squared(t: *const KdTree, i: usize, query: []const f64) -> f64
fn nearest_range(t: *const KdTree, lo: usize, hi: usize, depth: usize, query: []const f64, best: *Best)
fn kd_nearest(t: *const KdTree, query: []const f64) -> (usize, f64, err)
fn quadtree(x0: f64, y0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, xs: []f64, ys: []f64) -> (QuadTree, err)
fn quadrant(x: f64, y: f64, cx: f64, cy: f64) -> usize
fn quadtree_insert(t: *QuadTree, x: f64, y: f64) -> (usize, err)
fn quadtree_range(t: *const QuadTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err)
fn quadtree_range_node(t: *const QuadTree, node: usize, nx: f64, ny: f64, size: f64, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize, found: *usize) -> err
fn octree(x0: f64, y0: f64, z0: f64, size: f64, capacity: usize, child: []u32, first: []u32, count: []u32, next: []u32, xs: []f64, ys: []f64, zs: []f64) -> (OcTree, err)
fn octant(x: f64, y: f64, z: f64, cx: f64, cy: f64, cz: f64) -> usize
fn octree_insert(t: *OcTree, x: f64, y: f64, z: f64) -> (usize, err)
fn octree_range(t: *const OcTree, x1: f64, y1: f64, z1: f64, x2: f64, y2: f64, z2: f64, out: []usize) -> (usize, err)
fn octree_range_node(t: *const OcTree, node: usize, nx: f64, ny: f64, nz: f64, size: f64, x1: f64, y1: f64, z1: f64, x2: f64, y2: f64, z2: f64, out: []usize, found: *usize) -> err
fn interval_build(starts: []const f64, ends: []const f64, n: usize, order: []usize, left: []u32, right: []u32, centre: []f64, first: []u32, count: []u32) -> (IntervalTree, err)
fn interval_node(t: *IntervalTree, head: usize) -> (u32, err)
fn interval_overlap(t: *const IntervalTree, lo: f64, hi: f64, out: []usize) -> (usize, err)
fn interval_overlap_node(t: *const IntervalTree, node: usize, lo: f64, hi: f64, out: []usize, found: *usize) -> err
fn hash_grid(x0: f64, y0: f64, cell: f64, columns: usize, rows: usize, head: []u32, next: []u32, xs: []f64, ys: []f64) -> (HashGrid, err)
fn cell_of(g: *const HashGrid, x: f64, y: f64) -> (usize, usize)
fn hash_grid_insert(g: *HashGrid, x: f64, y: f64) -> (usize, err)
fn hash_grid_near(g: *const HashGrid, x: f64, y: f64, radius: f64, out: []usize) -> (usize, err)
fn rtree(items: []const f64, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8) -> (RTree, err)
fn rtree_new_node(t: *RTree, is_leaf: bool) -> (usize, err)
fn rtree_entry_box(t: *const RTree, node: usize, e: u32, out: []f64)
fn box_area(b: []const f64) -> f64
fn box_union(a: []const f64, b: []const f64, out: []f64)
fn box_intersects(a: []const f64, b: []const f64) -> bool
fn rtree_fit(t: *RTree, node: usize)
fn rtree_split(t: *RTree, node: usize, extra: u32) -> (usize, err)
fn rtree_insert(t: *RTree, item: usize) -> err
fn rtree_search(t: *const RTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err)
fn rtree_search_node(t: *const RTree, node: usize, query: []const f64, out: []usize, found: *usize) -> err
fn hilbert_index(order: u32, x: u64, y: u64) -> u64
fn sift_keys(keys: []u64, order: []usize, start: usize, end: usize)
fn sort_by_key(keys: []u64, order: []usize, n: usize)
fn rtree_hilbert(items: []const f64, n: usize, fanout: usize, box: []f64, child: []u32, count: []u32, leaf: []u8, keys: []u64, order: []usize) -> (RTree, err)
fn bvh_centroid(b: *const Bvh, p: usize, axis: usize) -> f64
fn bvh_node(b: *Bvh, lo: usize, hi: usize, leaf_size: usize) -> (u32, err)
fn bvh_build(boxes: []const f64, n: usize, leaf_size: usize, order: []usize, box: []f64, left: []u32, right: []u32, first: []u32, count: []u32) -> (Bvh, err)
fn ray_hits_box(box: []const f64, origin: []const f64, direction: []const f64) -> bool
fn bvh_traverse(b: *const Bvh, origin: []const f64, direction: []const f64, out: []usize) -> (usize, err)
fn range_tree_fill(t: *RangeTree, level: usize, lo: usize, hi: usize) -> err
fn range_tree_build(xs: []const f64, ys: []const f64, n: usize, order: []usize, pool: []usize) -> (RangeTree, err)
fn range_tree_query_node(t: *const RangeTree, level: usize, lo: usize, hi: usize, x1: f64, x2: f64, y1: f64, y2: f64, out: []usize, found: *usize) -> err
fn range_tree_query(t: *const RangeTree, x1: f64, y1: f64, x2: f64, y2: f64, out: []usize) -> (usize, err)
fn ball_fill(b: *BallTree, lo: usize, hi: usize)
fn ball_tree_build(points: []const f64, n: usize, d: usize, order: []usize, centre: []f64, radius: []f64) -> (BallTree, err)
fn ball_nearest_range(b: *const BallTree, lo: usize, hi: usize, query: []const f64, best: *Best)
fn ball_tree_nearest(b: *const BallTree, query: []const f64) -> (usize, f64, err)
```

Spatial indexes over caller storage: implicit k-d tree (`kd_build`, `kd_nearest`), quadtree
and octree with node pools (`quadtree_insert/range`, `octree_insert/range`), a centred
interval tree (`interval_build`, `interval_overlap`), a hash grid (`hash_grid_insert/near`),
an R-tree with quadratic splits (`rtree_insert/search`) and Hilbert bulk loading
(`rtree_hilbert`, `hilbert_index`), a BVH with ray traversal (`bvh_build/traverse`), a
2-d range tree (`range_tree_build/query`) and a ball tree (`ball_tree_build/nearest`).

### `e.data.succinct`

```neper
type BitVector = struct { bits: []u64, counts: []u32, n: usize }
type WaveletMatrix = struct { levels: []BitVector, zeros: []usize, n: usize }
type Csa = struct { psi: []u32, sampled: []u32, n: usize, rate: usize }
type FmIndex = struct { bwt: WaveletMatrix, starts: []u32, sampled: []u32, n: usize, rate: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn popcount(x: u64) -> usize
fn words_for(n: usize) -> usize
fn bit_vector(bits: []u64, n: usize, counts: []u32) -> (BitVector, err)
fn get_bit(v: *const BitVector, i: usize) -> bool
fn set_bit(bits: []u64, i: usize, on: bool)
fn rank(v: *const BitVector, i: usize) -> usize
fn rank0(v: *const BitVector, i: usize) -> usize
fn select(v: *const BitVector, k: usize) -> usize
fn select0(v: *const BitVector, k: usize) -> usize
fn louds_encode(first_child: []const u32, next_sibling: []const u32, n: usize, root: usize, bits: []u64, counts: []u32, queue: []u32, order: []usize) -> (BitVector, err)
fn louds_degree(v: *const BitVector, i: usize) -> usize
fn louds_child(v: *const BitVector, i: usize, k: usize) -> usize
fn louds_parent(v: *const BitVector, i: usize) -> usize
fn bp_encode(first_child: []const u32, next_sibling: []const u32, n: usize, root: usize, bits: []u64, counts: []u32, stack: []u32, order: []usize) -> (BitVector, err)
fn bp_find_close(v: *const BitVector, i: usize) -> usize
fn bp_enclose(v: *const BitVector, i: usize) -> usize
fn bp_subtree_size(v: *const BitVector, i: usize) -> usize
fn bp_preorder(v: *const BitVector, i: usize) -> usize
fn wavelet_build(symbols: []const u8, n: usize, bits: []u64, counts: []u32, levels: []BitVector, zeros: []usize, scratch: []u8) -> (WaveletMatrix, err)
fn wavelet_access(w: *const WaveletMatrix, i: usize) -> u8
fn wavelet_rank(w: *const WaveletMatrix, c: u8, i: usize) -> usize
fn wavelet_quantile(w: *const WaveletMatrix, lo: usize, hi: usize, k: usize) -> (u8, err)
fn wavelet_select(w: *const WaveletMatrix, c: u8, k: usize) -> usize
fn csa_build(text: str, rate: usize, psi: []u32, sampled: []u32, sa: []usize, scratch: []usize) -> (Csa, err)
fn csa_lookup(c: *const Csa, i: usize) -> usize
fn csa_search(c: *const Csa, text: str, pattern: str) -> (usize, usize)
fn fm_build(text: str, rate: usize, starts: []u32, sampled: []u32, sa: []usize, scratch: []usize, bwt_bytes: []u8, bits: []u64, counts: []u32, levels: []BitVector, zeros: []usize, wave_scratch: []u8) -> (FmIndex, err)
fn fm_search(f: *const FmIndex, pattern: str) -> (usize, usize)
fn fm_count(f: *const FmIndex, pattern: str) -> usize
fn fm_locate(f: *const FmIndex, i: usize) -> usize
```

`BitVector` with `rank`, `rank0`, `select`, `select0` over a count per word; `louds_encode`
with `louds_degree/child/parent`; `bp_encode` with `bp_find_close/enclose/subtree_size`;
a `WaveletMatrix` (`wavelet_build/access/rank/select/quantile`); `Csa` (Ψ plus sampled
positions: `csa_build/lookup/search`) and `FmIndex` (`fm_build/search/count/locate`)
over a BWT held in the wavelet matrix.

### `e.data.rope`

```neper
type Rope = struct { text: []u8, used: usize, weight: []u32, left: []u32, right: []u32, start: []u32, nodes: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32
const LEAF: usize = 64usize

fn rope(text: []u8, weight: []u32, left: []u32, right: []u32, start: []u32) -> Rope
fn new_node(r: *Rope, weight: u32, left: u32, right: u32, start: u32) -> (u32, err)
fn from_text(r: *Rope, text: []const u8) -> (u32, err)
fn len(r: *const Rope, root: u32) -> usize
fn byte_at(r: *const Rope, root: u32, i: usize) -> (u8, bool)
fn concat(r: *Rope, a: u32, b: u32) -> (u32, err)
fn split(r: *Rope, root: u32, i: usize) -> (u32, u32, err)
fn insert(r: *Rope, root: u32, i: usize, text: []const u8) -> (u32, err)
fn remove(r: *Rope, root: u32, i: usize, count: usize) -> (u32, err)
fn report(r: *const Rope, root: u32, out: []u8) -> (usize, err)
fn build(r: *Rope, lo: usize, hi: usize) -> (u32, err)
fn rebalance(r: *Rope, root: u32) -> (u32, err)
```

A rope over caller pools (leaves reference a text pool, internal nodes carry the left
weight): `from_text`, `len`, `byte_at`, `concat`, `split`, `insert`, `remove`, `report`
(flatten) and `rebalance` (rebuilt from a flat copy).

### `e.data.cartesian_tree`

```neper
type Tree = struct { left: []u32, right: []u32, parent: []u32, n: usize, root: u32 }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn build[T: type](keys: []const T, left: []u32, right: []u32, parent: []u32) -> (Tree, err)
fn depth(t: *const Tree, i: usize) -> usize
fn lca(t: *const Tree, i: usize, j: usize) -> (usize, err)
fn range_min(t: *const Tree, lo: usize, hi: usize) -> (usize, err)
fn is_valid[T: type](keys: []const T, t: *const Tree) -> bool
```

`build[T]` (stack construction, leftmost minimum on ties), `lca` by parent walking,
`range_min` as the LCA of the range ends and `is_valid`.

### `e.data.bitmap`

```neper
type Roaring = struct { keys: []u16, kind: []u8, count: []u32, slot: []u32, pool: []u16, n: usize }
type Wah = struct { words: []u32, used: usize, bits: usize }
error TooSmall
error Invalid
const CHUNK: usize = 4096usize
const ARRAY: u8 = 0u8
const BITSET: u8 = 1u8
const WAH_FILL: u32 = 0x80000000u32
const WAH_ONES: u32 = 0x7fffffffu32
const WAH_RUN: u32 = 0x3fffffffu32
const NO_END: usize = 4611686018427387904usize

fn roaring(keys: []u16, kind: []u8, count: []u32, slot: []u32, pool: []u16) -> Roaring
fn find_key(r: *const Roaring, key: u16) -> (usize, bool)
fn chunk_of(r: *const Roaring, pos: usize) -> []u16
fn array_find(c: []const u16, count: usize, low: u16) -> (usize, bool)
fn bit_at(c: []const u16, low: u16) -> bool
fn set_bit(c: []u16, low: u16)
fn clear_bit(c: []u16, low: u16)
fn container_has(c: []const u16, kind: u8, count: usize, low: u16) -> bool
fn zero_chunk(c: []u16)
fn chunk_ones(c: []const u16) -> u32
fn to_bitset(c: []u16, count: usize)
fn to_array(c: []u16)
fn or_into(c: []u16, src: []const u16, kind: u8, count: usize)
fn new_container(r: *Roaring, pos: usize, key: u16) -> err
fn roaring_add(r: *Roaring, x: u32) -> err
fn roaring_contains(r: *const Roaring, x: u32) -> bool
fn roaring_remove(r: *Roaring, x: u32) -> bool
fn roaring_count(r: *const Roaring) -> usize
fn roaring_to_list(r: *const Roaring, out: []u32) -> (usize, err)
fn roaring_and(a: *const Roaring, b: *const Roaring, out: *Roaring) -> err
fn roaring_or(a: *const Roaring, b: *const Roaring, out: *Roaring) -> err
fn wah_push_fill(out: []u32, used: usize, value: u32, run: usize) -> (usize, err)
fn wah_push_literal(out: []u32, used: usize, literal: u32) -> (usize, err)
fn groups_for(n: usize) -> usize
fn group_of(bits: []const u64, n: usize, g: usize) -> u32
fn put_group(bits: []u64, g: usize, v: u32)
fn wah(bits: []const u64, n: usize, out: []u32) -> (Wah, err)
fn wah_decode(w: *const Wah, bits: []u64) -> err
fn wah_count(w: *const Wah) -> usize
fn wah_peek(w: *const Wah, i: usize, done: usize) -> (u32, usize, bool)
fn wah_skip(w: *const Wah, i: usize, done: usize, k: usize) -> (usize, usize)
fn wah_merge(a: *const Wah, b: *const Wah, out: []u32, is_and: bool) -> (Wah, err)
fn wah_and(a: *const Wah, b: *const Wah, out: []u32) -> (Wah, err)
fn wah_or(a: *const Wah, b: *const Wah, out: []u32) -> (Wah, err)
```

Roaring bitmaps over caller pools (array or bitset containers keyed by the high
half: `roaring_add/contains/remove/count/to_list`, `roaring_and/or`) and word-aligned
hybrid bit vectors (`wah` encode, `wah_decode`, `wah_count`, `wah_and/or` directly over
the encoded streams, canonical fills).

### `e.data.hamt`

```neper
type Hamt = struct { bitmap: []u32, first: []u32, key: []u64, value: []u64, slots: []u32, used: usize, slots_used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn hamt(bitmap: []u32, first: []u32, key: []u64, value: []u64, slots: []u32) -> Hamt
fn mix(key: u64) -> u64
fn lane(hash: u64, shift: u32) -> u32
fn is_leaf(h: *const Hamt, node: u32) -> bool
fn new_node(h: *Hamt) -> (u32, err)
fn new_leaf(h: *Hamt, key: u64, value: u64) -> (u32, err)
fn new_branch(h: *Hamt, bitmap: u32, width: usize) -> (u32, err)
fn pair(h: *Hamt, old: u32, old_hash: u64, key: u64, value: u64, hash: u64, shift: u32) -> (u32, err)
fn put_at(h: *Hamt, node: u32, hash: u64, shift: u32, key: u64, value: u64) -> (u32, err)
fn put(h: *Hamt, root: u32, key: u64, value: u64) -> (u32, err)
fn get(h: *const Hamt, root: u32, key: u64) -> (u64, bool)
fn remove_at(h: *Hamt, node: u32, hash: u64, shift: u32, key: u64) -> (u32, bool, err)
fn remove(h: *Hamt, root: u32, key: u64) -> (u32, err)
fn count(h: *const Hamt, root: u32) -> usize
```

A persistent hash array mapped trie over caller pools (32-way bitmap nodes indexed by
popcount): `put`, `get`, `remove` and `count`; every version shares structure with the
last and only the path to the change is copied.

### `e.data.link_cut`

```neper
type LinkCut = struct { n: usize, left: []u32, right: []u32, parent: []u32, rev: []bool, value: []i64, sum: []i64 }
type Euler = struct { n: usize, left: []u32, right: []u32, parent: []u32, edge_u: []u32, edge_v: []u32 }
error TooSmall
error Invalid

fn link_cut(n: usize, left: []u32, right: []u32, parent: []u32, rev: []bool, value: []i64, sum: []i64) -> (LinkCut, err)
fn valid(t: *const LinkCut, v: u32) -> bool
fn is_root(t: *const LinkCut, x: u32) -> bool
fn push(t: *LinkCut, x: u32)
fn update(t: *LinkCut, x: u32)
fn push_path(t: *LinkCut, x: u32)
fn rotate(left: []u32, right: []u32, parent: []u32, x: u32)
fn rotate_up(t: *LinkCut, x: u32)
fn splay(t: *LinkCut, x: u32)
fn access(t: *LinkCut, v: u32) -> err
fn make_root(t: *LinkCut, v: u32) -> err
fn find_root(t: *LinkCut, v: u32) -> (u32, err)
fn connected(t: *LinkCut, u: u32, v: u32) -> bool
fn link(t: *LinkCut, u: u32, v: u32) -> err
fn cut(t: *LinkCut, u: u32, v: u32) -> err
fn path_sum(t: *LinkCut, u: u32, v: u32) -> (i64, err)
fn set_value(t: *LinkCut, v: u32, x: i64) -> err
fn euler_tour_tree(n: usize, left: []u32, right: []u32, parent: []u32, edge_u: []u32, edge_v: []u32) -> (Euler, err)
fn ett_splay(t: *Euler, x: u32)
fn concat(t: *Euler, a: u32, b: u32) -> u32
fn reroot(t: *Euler, v: u32)
fn ett_connected(t: *Euler, u: u32, v: u32) -> bool
fn ett_link(t: *Euler, u: u32, v: u32) -> err
fn ett_cut(t: *Euler, u: u32, v: u32) -> err
```

A link-cut tree over caller arrays (splay trees of preferred paths with lazy reversal):
`access`, `make_root`, `find_root`, `connected`, `link`, `cut`, `path_sum`, `set_value`;
and a dynamic Euler tour tree (`euler_tour_tree`, `ett_link`, `ett_cut`, `ett_connected`).

### `e.data.stream`

```neper
type Watermark = struct { lateness: u64, max_seen: u64, mark: u64, seen: bool, late: u64 }
type Merge = struct { marks: []u64, last: []u64, idle: u64, mark: u64 }
type Window = struct { start: u64, count: u64, sum: u64 }
type WindowBuffer = struct { size: u64, slide: u64, windows: []Window, used: usize, late: u64 }
error TooSmall
error Invalid

fn watermark(lateness: u64) -> Watermark
fn watermark_is_late(w: *const Watermark, event_time: u64) -> bool
fn watermark_observe(w: *Watermark, event_time: u64) -> u64
fn watermark_current(w: *const Watermark) -> u64
fn merge(marks: []u64, last: []u64, idle: u64) -> (Merge, err)
fn merge_update(m: *Merge, source: usize, mark: u64, now: u64) -> (u64, err)
fn merge_at(m: *Merge, now: u64) -> u64
fn window_start(event_time: u64, size: u64) -> u64
fn sliding_windows(event_time: u64, size: u64, slide: u64, out: []u64) -> (usize, err)
fn window_buffer(size: u64, slide: u64, windows: []Window) -> (WindowBuffer, err)
fn window_add(b: *WindowBuffer, event_time: u64, value: u64, mark: u64) -> err
fn window_fire(b: *WindowBuffer, mark: u64, out: []Window) -> (usize, err)
```

Event-time watermarks (`watermark`, `watermark_observe/is_late/current`), a merge over
sources with an idle timeout (`merge`, `merge_update/at`), tumbling and sliding window
assignment (`window_start`, `sliding_windows`) and a window buffer that fires by the
watermark (`window_buffer`, `window_add`, `window_fire`).

### `e.data.treap`

```neper
type Treap[K: type] = struct { keys: []K, priority: []u64, left: []u32, right: []u32, used: usize }
type Implicit[T: type] = struct { values: []T, priority: []u64, left: []u32, right: []u32, size: []u32, used: usize }
error TooSmall
error Invalid

fn treap[K: type](keys: []K, priority: []u64, left: []u32, right: []u32) -> Treap[K]
fn new_node[K: type](t: *Treap[K], key: K, r: *rand.Pcg64) -> (u32, err)
fn split[K: type](t: *Treap[K], root: u32, key: K) -> (u32, u32)
fn merge[K: type](t: *Treap[K], a: u32, b: u32) -> u32
fn insert[K: type](t: *Treap[K], root: u32, key: K, r: *rand.Pcg64) -> (u32, err)
fn remove[K: type](t: *Treap[K], root: u32, key: K) -> (u32, bool)
fn contains[K: type](t: *const Treap[K], root: u32, key: K) -> bool
fn collect[K: type](t: *const Treap[K], root: u32, out: []K) -> (usize, err)
fn persistent_insert[K: type](t: *Treap[K], root: u32, key: K, r: *rand.Pcg64) -> (u32, err)
fn copy_node[K: type](t: *Treap[K], from: u32) -> (u32, err)
fn persistent_split[K: type](t: *Treap[K], root: u32, key: K) -> (u32, u32, err)
fn persistent_merge[K: type](t: *Treap[K], a: u32, b: u32) -> (u32, err)
fn implicit[T: type](values: []T, priority: []u64, left: []u32, right: []u32, size: []u32) -> Implicit[T]
fn implicit_size[T: type](t: *const Implicit[T], n: u32) -> u32
fn implicit_fix[T: type](t: *Implicit[T], n: u32)
fn split_at[T: type](t: *Implicit[T], root: u32, count: usize) -> (u32, u32)
fn implicit_merge[T: type](t: *Implicit[T], a: u32, b: u32) -> u32
fn insert_at[T: type](t: *Implicit[T], root: u32, position: usize, value: T, r: *rand.Pcg64) -> (u32, err)
fn remove_at[T: type](t: *Implicit[T], root: u32, position: usize) -> (u32, err)
fn at[T: type](t: *const Implicit[T], root: u32, position: usize) -> (T, err)
```

Over a caller node pool (node 0 empty): `Treap[K]` by `K.cmp` with `split`, `merge`,
`insert`, `remove`, `contains`, `collect`, and `persistent_insert` copying the path so
every version stays readable; `Implicit[T]` over a sequence with `split_at`,
`implicit_merge`, `insert_at`, `remove_at`, `at` and `implicit_size`.

### `e.data.skip_list`

```neper
type SkipList[K: type] = struct { keys: []K, forward: []u32, height: []u8, levels: usize, used: usize, free: u32, count: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn skip_list[K: type](keys: []K, forward: []u32, height: []u8, levels: usize) -> (SkipList[K], err)
fn link[K: type](s: *const SkipList[K], node: u32, level: usize) -> u32
fn insert[K: type](s: *SkipList[K], key: K, r: *rand.Pcg64) -> err
fn remove[K: type](s: *SkipList[K], key: K) -> bool
fn contains[K: type](s: *const SkipList[K], key: K) -> bool
fn lower_bound[K: type](s: *const SkipList[K], key: K) -> u32
fn next[K: type](s: *const SkipList[K], node: u32) -> u32
fn collect[K: type](s: *const SkipList[K], out: []K) -> (usize, err)
```

`SkipList[K]` over caller pools with `levels` levels and geometric heights from the
caller's PCG: `insert` (a duplicate is `Invalid`), `remove` (slots go to a free list),
`contains`, `lower_bound`, `next` along the bottom chain and `collect`.

### `e.data.splay`

```neper
type Splay[T: type] = struct { values: []T, left: []u32, right: []u32, parent: []u32, size: []u32, reversed: []bool, used: usize }
error TooSmall
error Invalid

fn splay_tree[T: type](values: []T, left: []u32, right: []u32, parent: []u32, size: []u32, reversed: []bool) -> Splay[T]
fn build[T: type](t: *Splay[T], items: []const T) -> (u32, err)
fn build_range[T: type](t: *Splay[T], items: []const T, parent: u32) -> u32
fn push[T: type](t: *Splay[T], n: u32)
fn fix[T: type](t: *Splay[T], n: u32)
fn rotate[T: type](t: *Splay[T], n: u32)
fn splay[T: type](t: *Splay[T], n: u32) -> u32
fn find[T: type](t: *Splay[T], root: u32, position: usize) -> u32
fn at[T: type](t: *Splay[T], root: u32, position: usize) -> (T, u32, err)
fn reverse_range[T: type](t: *Splay[T], root: u32, low: usize, high: usize) -> (u32, err)
fn collect[T: type](t: *Splay[T], root: u32, out: []T) -> (usize, err)
```

`Splay[T]` holds a sequence by position over caller pools with a lazy reversal flag:
`build` (balanced), `splay` (zig, zig-zig, zig-zag to the root), `find`/`at` by
position, `reverse_range` by splitting the range out and tagging it, `collect`.

### `e.data.window`

```neper
type MonotonicQueue = struct { values: []i64, positions: []u64, head: usize, tail: usize, width: usize, pushed: u64, minimum: bool }
type TwoStack[T: type] = struct { front: []T, front_folds: []T, back: []T, front_count: usize, back_count: usize, identity: T }
type ExponentialHistogram = struct { sizes: []u64, stamps: []u64, count: usize, width: u64, k: usize, now: u64 }
error TooSmall
error Invalid

fn monotonic_queue(values: []i64, positions: []u64, width: usize, minimum: bool) -> (MonotonicQueue, err)
fn dominated(q: *const MonotonicQueue, kept: i64, incoming: i64) -> bool
fn monotonic_push(q: *MonotonicQueue, value: i64)
fn monotonic_extreme(q: *const MonotonicQueue) -> (i64, err)
fn two_stack[T: type](front: []T, front_folds: []T, back: []T, identity: T) -> TwoStack[T]
fn two_stack_push[T: type](w: *TwoStack[T], value: T) -> err
fn two_stack_pop[T: type, Ctx: type](w: *TwoStack[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (T, err)
fn two_stack_query[T: type, Ctx: type](w: *const TwoStack[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> T
fn exponential_histogram(sizes: []u64, stamps: []u64, width: u64, k: usize) -> (ExponentialHistogram, err)
fn histogram_push(h: *ExponentialHistogram, bit: bool) -> err
fn histogram_estimate(h: *const ExponentialHistogram) -> u64
```

`MonotonicQueue` answers the minimum or maximum of the last `width` values;
`TwoStack[T]` folds any associative `combine` over a FIFO window (`two_stack_push`,
`two_stack_pop`, `two_stack_query`); `ExponentialHistogram` counts the ones of the
last `width` bits within `1 / k` (`histogram_push`, `histogram_estimate`).

### `e.data.btree`

```neper
type Btree = struct { keys: []u64, values: []u32, count: []u32, leaf: []bool, next: []u32, order: usize, root: u32, used: usize, height: usize, free: u32 }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn btree(keys: []u64, values: []u32, count: []u32, leaf: []bool, next: []u32, order: usize) -> (Btree, err)
fn key_at(t: *const Btree, node: u32, i: usize) -> u64
fn set_key(t: *Btree, node: u32, i: usize, k: u64)
fn value_at(t: *const Btree, node: u32, i: usize) -> u32
fn set_value(t: *Btree, node: u32, i: usize, v: u32)
fn lower_bound(t: *const Btree, node: u32, key: u64) -> usize
fn child_for(t: *const Btree, node: u32, key: u64) -> usize
fn get(t: *const Btree, key: u64) -> (u32, bool)
fn new_node(t: *Btree, is_leaf: bool) -> (u32, err)
fn split_node(t: *Btree, node: u32) -> (u32, u64, err)
fn insert_into(t: *Btree, node: u32, key: u64, value: u32) -> (u32, u64, bool, err)
fn insert(t: *Btree, key: u64, value: u32) -> err
fn release(t: *Btree, node: u32)
fn merge_node(t: *Btree, node: u32, c: usize)
fn minimum_fill(t: *const Btree) -> usize
fn remove_from(t: *Btree, node: u32, key: u64) -> bool
fn remove(t: *Btree, key: u64) -> bool
fn scan(t: *const Btree, low: u64, high: u64, keys: []u64, values: []u32) -> (usize, err)
```

A B+ tree of `order` over caller pools with `u64` keys and `u32` values, leaves
chained: `insert` (`split_node` promotes a separator), `remove` (borrow or
`merge_node`, freed nodes reused), `get` and `scan` over a key range.

### `e.data.bk_tree`

```neper
type BkTree[T: type] = struct { items: []T, first_child: []u32, next_sibling: []u32, edge: []u32, used: usize }
error TooSmall
const NONE: u32 = 4294967295u32

fn bk_tree[T: type](items: []T, first_child: []u32, next_sibling: []u32, edge: []u32) -> BkTree[T]
fn insert[T: type, Ctx: type](t: *BkTree[T], item: T, ctx: *Ctx, distance: fn(*Ctx, T, T) -> u32) -> err
fn search[T: type, Ctx: type](t: *const BkTree[T], query: T, radius: u32, ctx: *Ctx, distance: fn(*Ctx, T, T) -> u32, on_hit: fn(*Ctx, T, u32), stack: []u32) -> (usize, err)
```

`BkTree[T]` over a caller node pool with the caller's metric `distance(ctx, a, b)`:
`insert` hangs an item under its parent by their distance and `search` visits every
item within a radius, pruning by the triangle inequality, through `on_hit`.

### `e.data.cache`

```neper
type Lru = struct { keys: []u64, values: []u64, prev: []u32, next: []u32, index: []u32, head: u32, tail: u32, len: usize, free: u32 }
type Fifo = struct { order: []u32, head: usize, len: usize }
type Clock = struct { referenced: []u8, filled: []u8, hand: usize }
type Lfu = struct { hits: []u64, filled: []u8 }
type Slru = struct { prev: []u32, next: []u32, protected: []u8, probation_head: u32, probation_tail: u32, protected_head: u32, protected_tail: u32, protected_len: usize, protected_cap: usize }
type TwoQueue = struct { prev: []u32, next: []u32, main: []u8, ghosts: []u64, ghost_at: usize, in_head: u32, in_tail: u32, in_len: usize, in_cap: usize, main_head: u32, main_tail: u32 }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn lru_init(keys: []u64, values: []u64, prev: []u32, next: []u32, index: []u32, capacity: usize) -> (Lru, err)
fn lru_len(c: *const Lru) -> usize
fn lru_hash(key: u64) -> u64
fn lru_find(c: *const Lru, key: u64) -> (usize, bool)
fn lru_unlink(c: *Lru, slot: u32)
fn lru_push_front(c: *Lru, slot: u32)
fn lru_get(c: *Lru, key: u64) -> (u64, bool)
fn lru_contains(c: *const Lru, key: u64) -> bool
fn lru_index_remove(c: *Lru, cell: usize)
fn lru_put(c: *Lru, key: u64, value: u64) -> (u64, bool)
fn lru_remove(c: *Lru, key: u64) -> bool
fn lru_oldest(c: *const Lru) -> (u64, bool)
fn fifo_init(order: []u32, capacity: usize) -> (Fifo, err)
fn fifo_evict(f: *const Fifo) -> (u32, bool)
fn fifo_insert(f: *Fifo, slot: u32)
fn clock_init(referenced: []u8, filled: []u8, capacity: usize) -> (Clock, err)
fn clock_touch(k: *Clock, slot: u32)
fn clock_insert(k: *Clock, slot: u32)
fn clock_evict(k: *Clock) -> u32
fn lfu_init(hits: []u64, filled: []u8, capacity: usize) -> (Lfu, err)
fn lfu_touch(l: *Lfu, slot: u32)
fn lfu_insert(l: *Lfu, slot: u32)
fn lfu_evict(l: *const Lfu) -> u32
fn slru_init(prev: []u32, next: []u32, protected: []u8, capacity: usize, protected_cap: usize) -> (Slru, err)
fn slru_unlink(s: *Slru, slot: u32)
fn slru_push_probation(s: *Slru, slot: u32)
fn slru_push_protected(s: *Slru, slot: u32)
fn slru_insert(s: *Slru, slot: u32)
fn slru_touch(s: *Slru, slot: u32)
fn slru_evict(s: *Slru) -> u32
fn slru_is_protected(s: *const Slru, slot: u32) -> bool
fn two_queue_init(prev: []u32, next: []u32, main: []u8, ghosts: []u64, capacity: usize, in_cap: usize) -> (TwoQueue, err)
fn two_queue_remembers(q: *const TwoQueue, key: u64) -> bool
fn two_queue_unlink(q: *TwoQueue, slot: u32)
fn two_queue_push(q: *TwoQueue, slot: u32, to_main: bool)
fn two_queue_insert(q: *TwoQueue, slot: u32, key: u64)
fn two_queue_touch(q: *TwoQueue, slot: u32)
fn two_queue_evict(q: *TwoQueue, keys: []const u64) -> u32
fn two_queue_in_main(q: *const TwoQueue, slot: u32) -> bool
```

`Lru` is a complete keyed cache (`u64` to `u64`, an open-addressing index in the
same storage); the other policies order slot numbers `0..capacity` for a caller that
keeps its own key index: `evict` names the slot to reuse, `insert` and `touch` report
fills and hits. `Lfu` scans linearly.

### `e.data.trie`

```neper
type Trie = struct { bytes: []u8, first: []u32, next: []u32, terminal: []u8, values: []u64, used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn init(bytes: []u8, first: []u32, next: []u32, terminal: []u8, values: []u64, capacity: usize) -> (Trie, err)
fn len(t: *const Trie) -> usize
fn child(t: *const Trie, node: u32, b: u8) -> u32
fn insert(t: *Trie, key: []const u8, value: u64) -> (bool, err)
fn get(t: *const Trie, key: []const u8) -> (u64, bool)
fn contains(t: *const Trie, key: []const u8) -> bool
fn has_prefix(t: *const Trie, prefix: []const u8) -> bool
fn any_terminal(t: *const Trie, node: u32) -> bool
fn remove(t: *Trie, key: []const u8) -> bool
fn longest_prefix(t: *const Trie, text: []const u8) -> (usize, u64, bool)
fn prefix_iter[Ctx: type](t: *const Trie, prefix: []const u8, scratch: []u8, ctx: *Ctx, visit: fn(*Ctx, []const u8, u64) -> bool) -> (bool, err)
fn walk[Ctx: type](t: *const Trie, node: u32, depth: usize, scratch: []u8, ctx: *Ctx, visit: fn(*Ctx, []const u8, u64) -> bool) -> (bool, err)
```

Node 0 is the root; the five slices need `capacity` entries. Children hang off a
sibling list, `remove` clears a terminal without reclaiming nodes, and `prefix_iter`
visits keys in byte order with the key assembled in caller scratch.

### `e.data.tree`

```neper
type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }
type Iter[K: type, V: type] = struct { state: *const void }
type SetIter[K: type] = struct { inner: Iter[K, bool] }

fn init[K: type, V: type](a: *mem.Arena) -> Map[K, V]
fn len[K: type, V: type](m: *const Map[K, V]) -> usize
fn put[K: type, V: type](m: *Map[K, V], key: K, value: own V) -> (bool, err)
fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool)
fn lower_bound[K: type, V: type](m: *const Map[K, V], key: K) -> (K, V, bool)
fn upper_bound[K: type, V: type](m: *const Map[K, V], key: K) -> (K, V, bool)
fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool)
fn clear[K: type, V: type](m: *Map[K, V])
fn set_init[K: type](a: *mem.Arena) -> Set[K]
fn set_add[K: type](s: *Set[K], key: K) -> (bool, err)
fn set_has[K: type](s: *const Set[K], key: K) -> bool
fn set_remove[K: type](s: *Set[K], key: K) -> bool
fn iter[K: type, V: type](m: *const Map[K, V]) -> Iter[K, V]
fn iter_from[K: type, V: type](m: *const Map[K, V], key: K) -> Iter[K, V]
fn iter_next[K: type, V: type](it: *Iter[K, V]) -> (K, V, bool)
fn set_iter[K: type](s: *const Set[K]) -> SetIter[K]
fn set_iter_next[K: type](it: *SetIter[K]) -> (K, bool)
```

Tree iteration is ascending by key. `iter_from` begins at the first key not less
than `key`.

### `e.data.graph`

```neper
type NodeId = u32
const NONE: NodeId = 4294967295
type Edge[E: type] = struct { from: NodeId, to: NodeId, value: E }
type Builder[E: type] = struct { node_count: usize, edges: list.List[Edge[E]] }
type Graph[E: type] = struct { node_count: usize, offsets: []const usize, edges: []const Edge[E] }
type Neighbors[E: type] = struct { edges: []const Edge[E], index: usize }
type Nodes = struct { next: NodeId, end: NodeId }
error InvalidNode
error TooLarge

fn builder[E: type](a: *mem.Arena, initial_nodes: usize, edge_capacity: usize) -> (Builder[E], err)
fn add_directed[E: type](b: *Builder[E], from: NodeId, to: NodeId, value: E) -> err
fn add_undirected[E: type](b: *Builder[E], a: NodeId, b_node: NodeId, value: E) -> err
fn finish[E: type](a: *mem.Arena, b: *const Builder[E]) -> (Graph[E], err)
fn node_count[E: type](g: *const Graph[E]) -> usize
fn edge_count[E: type](g: *const Graph[E]) -> usize
fn nodes[E: type](g: *const Graph[E]) -> Nodes
fn nodes_next(it: *Nodes) -> (NodeId, bool)
fn neighbors[E: type](g: *const Graph[E], node: NodeId) -> (Neighbors[E], err)
fn neighbors_next[E: type](it: *Neighbors[E]) -> (Edge[E], bool)
```

`finish` constructs immutable compressed-sparse-row adjacency, preserving insertion
order among edges from the same node. An undirected edge is stored as two directed
edges; it reserves both first and leaves the builder unchanged on error. Nodes are
dense `0..node_count`; node counts that do not fit `u32` return `TooLarge`.
Graphs own no resources beyond their caller arena.

### `e.data.slot_map`

```neper
type Key = struct { slot: u32, generation: u32 }
type SlotMap[T: type] = struct { state: *void }
type Iter[T: type] = struct { state: *const void, slot: u32 }
error Full
error TooLarge

fn init[T: type](a: *mem.Arena, initial_capacity: usize) -> (SlotMap[T], err)
fn len[T: type](m: *const SlotMap[T]) -> usize
fn capacity[T: type](m: *const SlotMap[T]) -> usize
fn insert[T: type](m: *SlotMap[T], value: own T) -> (Key, err)
fn get[T: type](m: *const SlotMap[T], key: Key) -> (*const T, bool)
fn get_mut[T: type](m: *SlotMap[T], key: Key) -> (*T, bool)
fn remove[T: type](m: *SlotMap[T], key: Key) -> (T, bool)
fn clear[T: type](m: *SlotMap[T])
fn iter[T: type](m: *const SlotMap[T]) -> Iter[T]
fn iter_next[T: type](it: *Iter[T]) -> (Key, T, bool)
```

Capacity is fixed and caller-funded. Removal increments the slot generation before
reuse; a generation never wraps, and a slot whose next generation would wrap is
retired permanently. `clear` invalidates every key. This is the standard facility
for independently retired arena values and stable externally stored handles.

### `e.data.iter`

```neper
type Map[I: type, T: type, U: type] = struct { it: I, f: fn(T) -> U }
type MapCtx[I: type, T: type, U: type, Ctx: type] = struct { it: I, ctx: *Ctx, f: fn(*Ctx, T) -> U }
type Filter[I: type, T: type] = struct { it: I, pred: fn(T) -> bool }
type FilterCtx[I: type, T: type, Ctx: type] = struct { it: I, ctx: *Ctx, pred: fn(*Ctx, T) -> bool }
type Take[T: type, I: type] = struct { it: I, remaining: usize }
type Skip[T: type, I: type] = struct { it: I, remaining: usize }
type Enumerate[T: type, I: type] = struct { it: I, index: usize }
type Chain[T: type, A: type, B: type] = struct { left: A, right: B, left_done: bool }
type Zip[X: type, Y: type, A: type, B: type] = struct { left: A, right: B }

fn map[I: type, T: type, U: type](it: I, f: fn(T) -> U) -> Map[I, T, U]
fn map_next[I: type, T: type, U: type](it: *Map[I, T, U]) -> (U, bool)
fn map_ctx[I: type, T: type, U: type, Ctx: type](it: I, ctx: *Ctx, f: fn(*Ctx, T) -> U) -> MapCtx[I, T, U, Ctx]
fn map_ctx_next[I: type, T: type, U: type, Ctx: type](it: *MapCtx[I, T, U, Ctx]) -> (U, bool)
fn filter[I: type, T: type](it: I, pred: fn(T) -> bool) -> Filter[I, T]
fn filter_next[I: type, T: type](it: *Filter[I, T]) -> (T, bool)
fn filter_ctx[I: type, T: type, Ctx: type](it: I, ctx: *Ctx, pred: fn(*Ctx, T) -> bool) -> FilterCtx[I, T, Ctx]
fn filter_ctx_next[I: type, T: type, Ctx: type](it: *FilterCtx[I, T, Ctx]) -> (T, bool)
fn take[T: type, I: type](it: I, n: usize) -> Take[T, I]
fn take_next[T: type, I: type](it: *Take[T, I]) -> (T, bool)
fn zip[X: type, Y: type, A: type, B: type](left: A, right: B) -> Zip[X, Y, A, B]
fn zip_next[X: type, Y: type, A: type, B: type](it: *Zip[X, Y, A, B]) -> (X, Y, bool)
fn reduce[I: type, T: type, U: type](it: *I, initial: U, f: fn(U, T) -> U) -> U
fn reduce_ctx[I: type, T: type, U: type, Ctx: type](it: *I, initial: U, ctx: *Ctx, f: fn(*Ctx, U, T) -> U) -> U
fn skip[T: type, I: type](it: I, n: usize) -> Skip[T, I]
fn skip_next[T: type, I: type](it: *Skip[T, I]) -> (T, bool)
fn enumerate[T: type, I: type](it: I) -> Enumerate[T, I]
fn enumerate_next[T: type, I: type](it: *Enumerate[T, I]) -> (usize, T, bool)
fn chain[T: type, A: type, B: type](left: A, right: B) -> Chain[T, A, B]
fn chain_next[T: type, A: type, B: type](it: *Chain[T, A, B]) -> (T, bool)
fn find[I: type, T: type](it: *I, pred: fn(T) -> bool) -> (T, bool)
fn position[I: type, T: type](it: *I, pred: fn(T) -> bool) -> (usize, bool)
fn any[I: type, T: type](it: *I, pred: fn(T) -> bool) -> bool
fn all[I: type, T: type](it: *I, pred: fn(T) -> bool) -> bool
fn count[I: type, T: type](it: *I) -> usize
fn min[I: type, T: type](it: *I) -> (T, bool)
fn max[I: type, T: type](it: *I) -> (T, bool)
fn collect[I: type, T: type](a: *mem.Arena, it: *I) -> (list.List[T], err)
fn partition[I: type, T: type](a: *mem.Arena, it: *I, pred: fn(T) -> bool) -> (list.List[T], list.List[T], err)
type TryMap[I: type, T: type, U: type, Ctx: type] = struct { it: *I, ctx: *Ctx, f: fn(*Ctx, T) -> (U, err), ended: bool }
type TryFilter[I: type, T: type, Ctx: type] = struct { it: *I, ctx: *Ctx, pred: fn(*Ctx, T) -> (bool, err), ended: bool }

fn try_map[I: type, T: type, U: type, Ctx: type](it: *I, ctx: *Ctx, f: fn(*Ctx, T) -> (U, err)) -> TryMap[I, T, U, Ctx]
fn try_map_next_err[I: type, T: type, U: type, Ctx: type](it: *TryMap[I, T, U, Ctx]) -> (U, bool, err)
fn try_filter[I: type, T: type, Ctx: type](it: *I, ctx: *Ctx, pred: fn(*Ctx, T) -> (bool, err)) -> TryFilter[I, T, Ctx]
fn try_filter_next_err[I: type, T: type, Ctx: type](it: *TryFilter[I, T, Ctx]) -> (T, bool, err)
fn try_collect[T: type, I: type](a: *mem.Arena, it: *I, limit: usize) -> (list.List[T], err)
fn try_reduce[I: type, T: type, U: type, Ctx: type](it: *I, initial: U, ctx: *Ctx, f: fn(*Ctx, U, T) -> (U, err)) -> (U, err)

```

`take[T](it, n)` and `zip[X, Y](left, right)` write the item type(s) explicitly;
their trailing iterator types are structurally inferred. Other adapters infer their
item types from the callback signatures. No return-context inference is required.

Every collection iterator borrows its source until exhaustion. Any mutation of that
source invalidates all of its live iterators; using an invalid iterator is a debug
`invalid` trap and release undefined behavior. Iteration never allocates or mutates
the collection. Lists, deques, rings and queues use logical element order; stacks use
LIFO order; hash maps use deterministic table-slot order; trees use ascending key
order; heaps expose heap storage order. Set iterators expose only keys.

Try adapters require I.next_err and borrow the source; they never close it. Source
errors and callback errors propagate once and put the adapter in terminal state;
later next_err returns no item and ok. Failure's value is not a valid yielded item.
try_collect returns a zero result and rolls back its allocations on error/limit,
but cannot undo consumed input. The source and callbacks must not allocate from
that result arena during collection. try_reduce returns its last fully committed
accumulator alongside an error. Ordinary for never silently consumes next_err.

---

## 4. Pure algorithms, text and cryptography

### `e.algo.combin`

```neper
error Invalid
error TooSmall

fn binomial(n: u64, k: u64) -> (u64, bool)
fn gcd(a: u64, b: u64) -> u64
fn factorial(n: u64) -> (u64, bool)
fn next_permutation[T: type](items: []T) -> bool
fn reverse[T: type](items: []T)
fn permutations[T: type, Ctx: type](items: []T, scratch: []usize, ctx: *Ctx, visit: fn(*Ctx, []const T) -> bool) -> (bool, err)
fn next_combination(indices: []usize, n: usize) -> bool
fn subsets[Ctx: type](count: u32, ctx: *Ctx, visit: fn(*Ctx, u64) -> bool) -> (bool, err)
fn next_subset_same_popcount(mask: u64) -> u64
fn next_submask(sub: u64, mask: u64) -> (u64, bool)
fn subsets_of_mask[Ctx: type](mask: u64, ctx: *Ctx, visit: fn(*Ctx, u64) -> bool) -> bool
fn subset_sums(values: []i64, bits: u32) -> err
fn subset_sums_inverse(values: []i64, bits: u32) -> err
fn superset_sums(values: []i64, bits: u32) -> err
```

Enumerators either step caller-held state in place (`next_*`, `false` when exhausted,
leaving the first element) or call a visitor per element and stop on `false`. Masks are
`u64`; the transforms work in place over `1 << bits` entries.

### `e.algo.dp`

```neper
type Line = struct { slope: i64, intercept: i64 }
type LiChao = struct { lines: []Line, filled: []u8, low: i64, high: i64 }
error TooSmall
error Invalid

fn knapsack(weights: []const u64, values: []const i64, capacity: usize, table: []i64) -> (i64, err)
fn knapsack_unbounded(weights: []const u64, values: []const i64, capacity: usize, table: []i64) -> (i64, err)
fn knapsack_fractional(weights: []const f64, values: []const f64, capacity: f64, order: []usize) -> (f64, err)
fn lis(values: []const i64, tails: []i64) -> (usize, err)
fn lcs[T: type](a: []const T, b: []const T, scratch: []usize) -> (usize, err)
fn shortest_common_supersequence[T: type](a: []const T, b: []const T, scratch: []usize) -> (usize, err)
fn longest_palindromic_subsequence(s: []const u8, scratch: []usize) -> (usize, err)
fn coin_change_min(coins: []const u64, amount: usize, table: []u64) -> (u64, bool, err)
fn coin_change_ways(coins: []const u64, amount: usize, table: []u64) -> (u64, err)
fn subset_sum(values: []const u64, wanted: usize, table: []u8) -> (bool, err)
fn partition_equal(values: []const u64, table: []u8) -> (bool, err)
fn max_subarray(values: []const i64) -> (i64, usize, usize)
fn max_product_subarray(values: []const i64) -> i64
fn matrix_chain(dims: []const u64, table: []u64) -> (u64, err)
fn optimal_bst(frequencies: []const u64, table: []u64) -> (u64, err)
fn largest_rectangle_histogram(heights: []const u64, stack: []usize) -> (u64, usize, usize, err)
fn previous_smaller(values: []const i64, out: []usize, stack: []usize) -> err
fn li_chao_init(lines: []Line, filled: []u8, low: i64, high: i64) -> (LiChao, err)
fn li_chao_insert(t: *LiChao, line: Line)
fn li_chao_query(t: *const LiChao, x: i64) -> (i64, bool)
fn hull_add(hull: []Line, count: usize, line: Line) -> (usize, err)
fn hull_query(hull: []const Line, count: usize, pointer: *usize, x: i64) -> (i64, bool)
```

Each routine states the scratch it needs and answers `TooSmall` when short; values
are `i64` and never checked for overflow. The Li Chao tree covers an integer domain
with `4 * (high - low + 1)` nodes; the convex hull trick wants lines in decreasing
slope order and queries at increasing `x`.

### `e.algo.geom`

```neper
type Point = struct { x: f64, y: f64 }
type Circle = struct { center: Point, radius: f64 }
error TooSmall
error Invalid

fn point(x: f64, y: f64) -> Point
fn orient(a: Point, b: Point, c: Point) -> f64
fn distance_squared(a: Point, b: Point) -> f64
fn in_circle(a: Point, b: Point, c: Point, d: Point) -> bool
fn on_segment(a: Point, b: Point, p: Point) -> bool
fn segments_intersect(a: Point, b: Point, c: Point, d: Point) -> bool
fn segment_intersection(a: Point, b: Point, c: Point, d: Point) -> (Point, bool)
fn polygon_area(polygon: []const Point) -> f64
fn is_convex(polygon: []const Point) -> bool
fn point_in_polygon(polygon: []const Point, p: Point) -> bool
fn winding_number(polygon: []const Point, p: Point) -> i32
fn hull(points: []Point, out: []Point) -> (usize, err)
fn sort_points(points: []Point)
fn hull_jarvis(points: []const Point, out: []Point) -> (usize, err)
fn closest_pair(points: []Point) -> (usize, usize, f64, err)
fn farthest_pair(hull_points: []const Point) -> (usize, usize, f64, err)
fn min_bounding_rect(hull_points: []const Point, out: []Point) -> (f64, err)
fn sqrt_f64(x: f64) -> f64
fn enclosing_circle(points: []const Point) -> Circle
fn circle_contains(c: Circle, p: Point) -> bool
fn circle_two(a: Point, b: Point) -> Circle
fn circle_three(a: Point, b: Point, c: Point) -> Circle
fn lattice_points(polygon: []const Point) -> (i64, i64)
fn morton_encode(x: u32, y: u32) -> u64
fn spread(v: u32) -> u64
fn morton_decode(code: u64) -> (u32, u32)
fn compact(v: u64) -> u32
```

Points are `f64` pairs; polygons are point slices in either winding and
`polygon_area` is signed (positive counter-clockwise). `hull` sorts its input in
place and needs `out.len >= points.len + 1`; `closest_pair` also sorts. Predicates
are plain floating point.

### `e.algo.geom.clip`

```neper
type Rect = struct { min: geom.Point, max: geom.Point }
error TooSmall
error Invalid

fn clip_convex(subject: []const geom.Point, window: []const geom.Point, out: []geom.Point, scratch: []geom.Point) -> (usize, err)
fn line_intersection(a: geom.Point, b: geom.Point, c: geom.Point, d: geom.Point) -> (geom.Point, bool)
fn outcode(r: Rect, p: geom.Point) -> u32
fn clip_line(r: Rect, a: geom.Point, b: geom.Point) -> (geom.Point, geom.Point, bool)
fn clip_line_liang_barsky(r: Rect, a: geom.Point, b: geom.Point) -> (geom.Point, geom.Point, bool)
fn triangulate_ear_clip(polygon: []const geom.Point, triangles: []usize, scratch: []usize) -> (usize, err)
fn simplify_douglas_peucker(points: []const geom.Point, tolerance: f64, keep: []u8, stack: []usize) -> err
fn point_segment_distance_squared(p: geom.Point, a: geom.Point, b: geom.Point) -> f64
fn simplify_visvalingam(points: []const geom.Point, min_area: f64, keep: []u8) -> err
```

`clip_convex` wants a convex counter-clockwise window and `2 * subject.len +
window.len` points of `out` and `scratch`; `triangulate_ear_clip` writes
`3 * (n - 2)` indices for a simple polygon in either winding; the simplifiers
mark kept points with 1 in `keep`.

### `e.algo.rand`

```neper
type Pcg64 = struct { state: u64, stream: u64 }
type Xoshiro256 = struct { s0: u64, s1: u64, s2: u64, s3: u64 }
type Mt19937 = struct { state: [624]u32, index: u32 }
type Reservoir[T: type] = struct { items: []T, seen: u64 }

fn pcg64(seed: u64, stream: u64) -> Pcg64
fn pcg64_next(r: *Pcg64) -> u64
fn pcg64_bounded(r: *Pcg64, upper: u64) -> u64
fn pcg64_f64(r: *Pcg64) -> f64
fn xoshiro256(seed: [4]u64) -> Xoshiro256
fn xoshiro256_next(r: *Xoshiro256) -> u64
fn xoshiro256_bounded(r: *Xoshiro256, upper: u64) -> u64
fn xoshiro256_f64(r: *Xoshiro256) -> f64
fn mt19937(seed: u32) -> Mt19937
fn mt19937_next(r: *Mt19937) -> u32
fn shuffle[T: type](r: *Pcg64, items: []T)
fn cycle_permutation[T: type](r: *Pcg64, items: []T)
fn reservoir[T: type](items: []T) -> Reservoir[T]
fn reservoir_offer[T: type](s: *Reservoir[T], r: *Pcg64, item: T)
fn reservoir_sample[T: type](s: *const Reservoir[T]) -> []T
```

`bounded(..., 0)` returns zero; otherwise it is unbiased rejection sampling.

### `e.algo.uuid`

```neper
type Uuid = struct { bytes: [16]u8 }
error Invalid

fn v4(random: [16]u8) -> Uuid
fn v7(unix_millis: u64, random: [10]u8) -> (Uuid, err)
fn parse(s: str) -> (Uuid, err)
fn format(uuid: Uuid, dst: []u8) -> (str, err)
fn version(uuid: Uuid) -> u8
fn variant(uuid: Uuid) -> u8
fn uuid_eq(a: Uuid, b: Uuid) -> bool
fn uuid_cmp(a: Uuid, b: Uuid) -> i32
fn uuid_hash(uuid: Uuid) -> u64
fn uuid_format(uuid: Uuid, b: *str.Builder) -> err
```

`format` writes the 36-byte lowercase hyphenated form. Entropy and time are supplied
by the caller; this module never reads `e.os`.

### `e.algo.consistent_hash`

```neper
type Point = struct { position: u64, node: u64 }
error TooSmall
error Invalid

fn mix(x: u64) -> u64
fn ring_position(node: u64, replica: u32) -> u64
fn ring_build(points: []Point, nodes: []const u64, replicas: u32) -> ([]Point, err)
fn point_before(a: Point, b: Point) -> bool
fn ring_sift(ring: []Point, at: usize, end: usize)
fn ring_lookup(ring: []const Point, key: u64) -> (u64, bool)
fn ring_successors(ring: []const Point, key: u64, out: []u64) -> usize
fn rendezvous(nodes: []const u64, key: u64) -> (usize, bool)
fn jump(key: u64, buckets: u32) -> u32
```

Nodes are `u64` identifiers and keys are hashes the caller computed. `ring_build`
places `replicas` points per node in caller storage and sorts them; `rendezvous`
needs no state; `jump` numbers buckets `0..count`.

### `e.algo.graph.flow`

```neper
type Network = struct { head: []u32, next: []u32, to: []u32, capacity: []i64, arcs: usize, nodes: usize, source: u32, sink: u32 }
error InvalidNode
error InvalidCapacity
const NONE: u32 = 4294967295u32

fn build[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], source: graph.NodeId, sink: graph.NodeId, ctx: *Ctx, capacity: fn(*Ctx, graph.Edge[E]) -> i64) -> (Network, err)
fn add_arc(net: *Network, from: u32, to: u32, capacity: i64)
fn edmonds_karp(a: *mem.Arena, net: *Network) -> (i64, err)
fn dinic(a: *mem.Arena, net: *Network) -> (i64, err)
fn push_relabel(a: *mem.Arena, net: *Network) -> (i64, err)
fn min_cut(a: *mem.Arena, net: *const Network, side: []u8) -> err
fn edge_flow(net: *const Network, edge_index: usize) -> i64
```

`build` turns a graph and a capacity function into a residual network in the
arena; `edmonds_karp`, `dinic` and `push_relabel` each compute the maximum flow on
it (a saturated network answers 0 to a second call), `min_cut` marks the source
side afterwards and `edge_flow` reads the flow on an input edge by its CSR index.

### `e.algo.graph.match`

```neper
error Invalid
error TooSmall
const NONE: u32 = 4294967295u32
const NONE_USIZE: usize = 18446744073709551615usize

fn hopcroft_karp[E: type](a: *mem.Arena, g: *const graph.Graph[E], left: usize, match_left: []u32, match_right: []u32) -> (usize, err)
fn hungarian(costs: []const f64, n: usize, assignment: []usize, scratch: []f64, used: []usize) -> (f64, err)
fn stable_marriage(proposer_prefs: []const usize, receiver_prefs: []const usize, n: usize, match_proposer: []usize, scratch: []usize) -> err
fn blossom[E: type](a: *mem.Arena, g: *const graph.Graph[E], mate: []u32) -> (usize, err)
fn lowest_common_base(base: []u32, parent: []u32, mate: []u32, a: u32, b: u32, root: u32, mark: []u8, n: usize) -> u32
fn mark_path(base: []u32, parent: []u32, mate: []u32, in_blossom: []u8, from: u32, common: u32, child: u32)
```

`hopcroft_karp` reads edges from left nodes `0..left` to right nodes; `hungarian`
minimises over a row-major cost matrix (scratch `4 * (n + 1)` floats and `2 * (n + 1)`
indices); `stable_marriage` is proposer-optimal over preference lists; `blossom`
matches a general graph. `NONE` marks an unmatched node.

### `e.algo.graph.path`

```neper
type Route = struct { nodes: []const graph.NodeId, cost: f64 }
error NegativeCycle
error InvalidNode
error TooSmall
error NoPath

fn infinity() -> f64
fn path_to(a: *mem.Arena, previous: []const graph.NodeId, start: graph.NodeId, goal: graph.NodeId) -> ([]const graph.NodeId, err)
fn bellman_ford[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (algo.Paths, err)
fn floyd_warshall[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err)
fn dial[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, max_weight: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> usize) -> ([]usize, err)
fn johnson[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err)
fn astar[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, heuristic: fn(*Ctx, graph.NodeId) -> f64) -> (Route, err)
fn bidirectional[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId) -> (Route, err)
fn iddfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, max_depth: usize) -> (Route, err)
fn ida_star[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, goal: graph.NodeId, max_depth: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, heuristic: fn(*Ctx, graph.NodeId) -> f64) -> (Route, err)
```

Distances are `f64` with `infinity()` for unreachable; `bellman_ford`,
`floyd_warshall` and `johnson` answer `NegativeCycle`; `dial` wants non-negative
integer weights at most `max_weight`; `astar` and `ida_star` take a heuristic over
nodes; `bidirectional` and `iddfs` count edges.

### `e.algo.graph.tree`

```neper
type Rooted = struct { parent: []graph.NodeId, depth: []u32, size: []u32, order: []graph.NodeId }
type Lifting = struct { up: []graph.NodeId, depth: []const u32, levels: usize, count: usize }
type EulerTour = struct { entry: []u32, exit: []u32, sequence: []graph.NodeId }
type HeavyLight = struct { head: []graph.NodeId, position: []u32, parent: []graph.NodeId, depth: []const u32 }
error InvalidNode
error NotATree
error TooSmall

fn root_at[E: type](a: *mem.Arena, g: *const graph.Graph[E], root: graph.NodeId) -> (Rooted, err)
fn lifting(a: *mem.Arena, tree: *const Rooted) -> (Lifting, err)
fn ancestor(l: *const Lifting, v: graph.NodeId, steps: u32) -> graph.NodeId
fn lca(l: *const Lifting, a: graph.NodeId, b: graph.NodeId) -> graph.NodeId
fn distance(l: *const Lifting, a: graph.NodeId, b: graph.NodeId) -> u32
fn lca_offline[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted, queries: []const graph.NodeId, out: []graph.NodeId) -> err
fn euler_tour[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted) -> (EulerTour, err)
fn heavy_light(a: *mem.Arena, tree: *const Rooted) -> (HeavyLight, err)
fn path_ranges(h: *const HeavyLight, a: graph.NodeId, b: graph.NodeId, out: []u32) -> (usize, err)
fn centroid_decompose[E: type](a: *mem.Arena, g: *const graph.Graph[E], centroid_parent: []graph.NodeId, centroid_level: []u32) -> err
fn prufer_encode[E: type](a: *mem.Arena, g: *const graph.Graph[E], out: []graph.NodeId) -> err
fn prufer_decode(a: *mem.Arena, code: []const graph.NodeId, edges: []graph.NodeId) -> err
fn ahu_labels[E: type](a: *mem.Arena, g: *const graph.Graph[E], tree: *const Rooted, label: []u64, scratch: []u64) -> err
```

`root_at` turns an undirected tree into parents, depths, sizes and a BFS order
(`NotATree` for a cycle or a disconnected node); `lifting` and `lca` answer
ancestors in `O(log n)`, `lca_offline` a batch in one walk; `euler_tour`,
`heavy_light` with `path_ranges`, `centroid_decompose`, Prüfer codes and AHU
labels each work over that rooting.

### `e.algo.graph.span`

```neper
type Forest = struct { edges: []const usize, weight: f64, trees: usize }
error InvalidNode
error TooSmall
error NotEulerian

fn kruskal[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err)
fn sort_by_weight(order: []usize, weights: []const f64)
fn lighter(weights: []const f64, a: usize, b: usize) -> bool
fn sift(order: []usize, weights: []const f64, at: usize, end: usize)
fn prim[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err)
fn boruvka[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Forest, err)
fn twin[E: type](g: *const graph.Graph[E], k: usize) -> usize
fn bridges_and_cuts[E: type](a: *mem.Arena, g: *const graph.Graph[E], is_bridge: []u8, is_cut: []u8) -> err
fn euler_path[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn transitive_closure[E: type](g: *const graph.Graph[E], reach: []u8) -> err
```

Undirected input is the `add_undirected` form (both copies present); the MSTs
answer one CSR index per chosen edge (the `from < to` copy) and the tree count;
`bridges_and_cuts` marks the same copies; `euler_path` works on a digraph and
answers the node sequence; `transitive_closure` fills an `n x n` byte matrix.

### `e.algo.align`

```neper
type Scores = struct { match_score: i64, mismatch: i64, gap: i64 }
type Op = enum u8 { Match, Insert, Delete }
error TooSmall

fn score_pair(s: Scores, a: u8, b: u8) -> i64
fn max3(a: i64, b: i64, c: i64) -> i64
fn global(a: str, b: str, s: Scores, scratch: []i64) -> (i64, err)
fn local(a: str, b: str, s: Scores, scratch: []i64) -> (i64, usize, usize, err)
fn affine_gap(a: str, b: str, s: Scores, open: i64, extend: i64, scratch: []i64) -> (i64, err)
fn last_row(a: str, b: str, s: Scores, reverse: bool, row: []i64, work: []i64)
fn global_linear_space(a: str, b: str, s: Scores, ops: []Op, scratch: []i64) -> (i64, usize, err)
fn hirschberg(a: str, b: str, s: Scores, ops: []Op, at: usize, scratch: []i64) -> usize
```

Byte sequences scored by `Scores` (match, mismatch, gap): `global` (Needleman-Wunsch),
`local` (Smith-Waterman, the score and the end positions), `affine_gap` (Gotoh with
opening and extension penalties) and `global_linear_space` (Hirschberg, the global
score with the alignment as `Op`s over two rows of storage).

### `e.algo.schedule`

```neper
error TooSmall
error Invalid
const NONE: usize = 18446744073709551615usize

fn sort_by(order: []usize, keys: []const i64)
fn activity_selection(starts: []const i64, ends: []const i64, chosen: []usize, order: []usize) -> (usize, err)
fn interval_cover(starts: []const i64, ends: []const i64, points: []i64, order: []usize) -> (usize, err)
fn find_slot(parent: []usize, slot: usize) -> usize
fn jobs_with_deadlines(deadlines: []const usize, profits: []const i64, slots: []usize, parent: []usize, order: []usize) -> (i64, usize, err)
fn cooldown(tasks: []const usize, kinds: usize, gap: usize, counts: []usize) -> (usize, err)
```

Greedy scheduling over intervals and jobs: `activity_selection` (earliest end first),
`interval_cover` (fewest points touching every interval), `jobs_with_deadlines` (most
profitable first into the latest free slot, disjoint sets over slots) and `cooldown`
(the shortest schedule bound with a gap between repeats).

### `e.algo.timeseries`

```neper
type Cusum = struct { centre: f64, drift: f64, threshold: f64, high: f64, low: f64 }
type PageHinkley = struct { delta: f64, threshold: f64, count: u64, mean: f64, sum: f64, least: f64 }
type Adwin = struct { values: []f64, head: usize, count: usize, delta: f64 }
type GarchFit = struct { returns: []const f64 }
error TooSmall
error Invalid

fn holt_winters(series: []const f64, period: usize, alpha: f64, beta: f64, gamma: f64, horizon: usize, forecast: []f64, season: []f64) -> (f64, f64, err)
fn loess(series: []const f64, window: usize, out: []f64) -> err
fn stl(series: []const f64, period: usize, window: usize, trend: []f64, seasonal: []f64, remainder: []f64, scratch: []f64) -> err
fn cusum(centre: f64, drift: f64, threshold: f64) -> Cusum
fn cusum_step(c: *Cusum, value: f64) -> bool
fn page_hinkley(delta: f64, threshold: f64) -> PageHinkley
fn page_hinkley_step(p: *PageHinkley, value: f64) -> bool
fn adwin(values: []f64, delta: f64) -> (Adwin, err)
fn adwin_at(a: *const Adwin, i: usize) -> f64
fn adwin_step(a: *Adwin, value: f64) -> bool
fn adwin_mean(a: *const Adwin) -> f64
fn garch_log_likelihood(omega: f64, alpha: f64, beta: f64, returns: []const f64) -> f64
fn garch_objective(fit: *GarchFit, p: []const f64) -> f64
fn garch_fit(returns: []const f64, p: []f64, iterations: u32, scratch: []f64) -> (f64, err)
fn garch_forecast(omega: f64, alpha: f64, beta: f64, last_return: f64, last_variance: f64, horizon: usize, out: []f64) -> err
fn hawkes_intensity(mu: f64, alpha: f64, beta: f64, events: []const f64, t: f64) -> f64
fn hawkes_log_likelihood(mu: f64, alpha: f64, beta: f64, events: []const f64, horizon: f64) -> f64
fn hawkes_simulate(mu: f64, alpha: f64, beta: f64, horizon: f64, r: *rand.Pcg64, out: []f64) -> (usize, err)
```

`holt_winters` (additive triple smoothing with forecasts), `loess` and `stl` (a LOESS
trend, phase-mean season, two passes), the streaming detectors `Cusum`, `PageHinkley`
and `Adwin` (a ring of recent values cut by the Hoeffding bound), GARCH(1,1)
(`garch_log_likelihood`, `garch_fit` by Nelder-Mead, `garch_forecast`) and the Hawkes
process (`hawkes_intensity`, `hawkes_log_likelihood`, `hawkes_simulate` by thinning).

### `e.algo.exact_cover`

```neper
type Links = struct { left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32, columns: usize, nodes: usize }
error TooSmall
error Invalid
error Unsolvable

fn links(matrix: []const u8, rows: usize, columns: usize, left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32) -> (Links, err)
fn cover(l: *Links, header: u32)
fn uncover(l: *Links, header: u32)
fn search(l: *Links, chosen: []usize, depth: usize) -> (usize, bool)
fn solve(l: *Links, chosen: []usize) -> (usize, err)
fn sudoku(grid: []u8, matrix: []u8, left: []u32, right: []u32, up: []u32, down: []u32, column: []u32, row: []u32, size: []u32, chosen: []usize) -> err
```

`links` threads a 0/1 matrix into dancing links over caller arrays, `solve` runs
Algorithm X (fewest-ones column first) for the first cover, and `sudoku` maps a 9 × 9
grid onto the 729 × 324 cover matrix and back.

### `e.algo.graph.centrality`

```neper
error TooSmall
error Invalid

fn out_degree[E: type](g: *const graph.Graph[E], v: usize) -> usize
fn pagerank[E: type](g: *const graph.Graph[E], damping: f64, tolerance: f64, max_iterations: u32, scores: []f64, scratch: []f64) -> (u32, err)
fn normalise(v: []f64)
fn sqrt(x: f64) -> f64
fn hits[E: type](g: *const graph.Graph[E], tolerance: f64, max_iterations: u32, authority: []f64, hub: []f64) -> (u32, err)
fn eigenvector[E: type](g: *const graph.Graph[E], tolerance: f64, max_iterations: u32, scores: []f64, scratch: []f64) -> (u32, err)
fn closeness[E: type](g: *const graph.Graph[E], scores: []f64, queue: []u32, distance: []u32) -> err
fn betweenness[E: type](g: *const graph.Graph[E], halve: bool, scores: []f64, order: []u32, distance: []u32, sigma: []f64, delta: []f64, first_pred: []u32, pred: []u32, next_pred: []u32) -> err
```

`pagerank` (power iteration with damping, dangling mass spread), `hits` (hubs and
authorities, unit length), `eigenvector` (power iteration on the adjacency), `closeness`
(reached over the hop-distance sum) and `betweenness` (Brandes over unweighted paths,
halved for an undirected graph), all into caller storage.

### `e.algo.graph.color`

```neper
error TooSmall

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize
fn smallest_free[E: type](g: *const graph.Graph[E], v: usize, colors: []const u32, used: []usize, stamp: usize) -> u32
fn greedy[E: type](g: *const graph.Graph[E], colors: []u32, order: []usize, used: []usize) -> (usize, err)
fn dsatur[E: type](g: *const graph.Graph[E], colors: []u32, saturation: []usize, used: []usize) -> (usize, err)
fn is_proper[E: type](g: *const graph.Graph[E], colors: []const u32) -> bool
```

`greedy` (Welsh-Powell, nodes by falling degree) and `dsatur` (most saturated node
next) colour an undirected graph into caller storage and answer the colour count;
`is_proper` checks a colouring.

### `e.algo.graph.community`

```neper
error TooSmall
error Invalid

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize
fn modularity[E: type](g: *const graph.Graph[E], labels: []const u32) -> f64
fn label_propagation[E: type](g: *const graph.Graph[E], labels: []u32, counts: []usize, max_sweeps: u32) -> (u32, err)
fn compact(labels: []u32, n: usize, map: []u32) -> usize
fn local_moving(w: []const f64, strength: []const f64, k: usize, two_m: f64, community: []u32, total: []f64, link: []f64) -> bool
fn louvain[E: type](a: *mem.Arena, g: *const graph.Graph[E], labels: []u32) -> (f64, err)
fn edge_betweenness[E: type](g: *const graph.Graph[E], removed: []const u8, scores: []f64, order: []u32, distance: []u32, sigma: []f64, delta: []f64) -> err
fn components[E: type](g: *const graph.Graph[E], removed: []const u8, labels: []u32, stack: []u32) -> usize
fn girvan_newman[E: type](g: *const graph.Graph[E], removed: []u8, scores: []f64, labels: []u32, order: []u32, distance: []u32, sigma: []f64, delta: []f64) -> (usize, err)
```

`modularity` of a labelling; `label_propagation` to a fixed point; `louvain` (local
moving then aggregation over a dense community matrix in the arena, repeated while it
improves); `edge_betweenness`, `components` and `girvan_newman` (the highest-betweenness
edge removed until a component splits).

### `e.algo.graph.cut`

```neper
error TooSmall
error Invalid

fn stoer_wagner(w: []f64, n: usize, side: []u8, scratch: []f64, marks: []usize) -> (f64, err)
fn find(parent: []u32, v: u32) -> u32
fn karger[E: type](a: *mem.Arena, g: *const graph.Graph[E], r: *rand.Pcg64, side: []u8) -> (usize, err)
fn karger_best[E: type](a: *mem.Arena, g: *const graph.Graph[E], runs: usize, r: *rand.Pcg64, best_side: []u8, side: []u8) -> (usize, err)
```

`stoer_wagner` over a dense weight matrix answers the global minimum cut and one side;
`karger` contracts random edges of a graph through a disjoint set in the arena and
`karger_best` keeps the best of several runs.

### `e.algo.graph.iso`

```neper
error TooSmall

fn degree[E: type](g: *const graph.Graph[E], v: usize) -> usize
fn adjacent[E: type](g: *const graph.Graph[E], v: usize, w: usize) -> bool
fn feasible[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []const u32, used: []const u8, p: usize, t: usize, induced: bool) -> bool
fn search[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []u32, used: []u8, p: usize, induced: bool) -> bool
fn subgraph_vf2[E: type](pattern: *const graph.Graph[E], host: *const graph.Graph[E], mapping: []u32, used: []u8) -> (bool, err)
fn isomorphic[E: type](a: *const graph.Graph[E], b: *const graph.Graph[E], mapping: []u32, used: []u8) -> (bool, err)
```

`subgraph_vf2` finds a monomorphism of a pattern into a host graph by VF2-style
backtracking (degree and adjacency feasibility), `isomorphic` an isomorphism between two
graphs of one size (non-edges checked too); `adjacent` reads an edge.

### `e.algo.combopt`

```neper
error TooSmall
error Invalid

fn at(d: []const f64, n: usize, i: usize, j: usize) -> f64
fn tour_length(d: []const f64, n: usize, tour: []const usize) -> f64
fn tsp_nearest_neighbor(d: []const f64, n: usize, start: usize, tour: []usize, visited: []u8) -> (f64, err)
fn reverse(tour: []usize, i: usize, j: usize)
fn tsp_two_opt(d: []const f64, n: usize, tour: []usize) -> (f64, usize, err)
fn tsp_or_opt(d: []const f64, n: usize, tour: []usize, scratch: []usize) -> (f64, usize, err)
fn tsp_held_karp(d: []const f64, n: usize, tour: []usize, table: []f64, parent: []usize) -> (f64, err)
fn set_cover_greedy(membership: []const u8, sets: usize, universe: usize, chosen: []usize, covered: []u8) -> (usize, err)
fn bin_pack_ffd(sizes: []const f64, capacity: f64, bins: []usize, loads: []f64, order: []usize) -> (usize, err)
fn vrp_savings(d: []const f64, n: usize, demand: []const f64, capacity: f64, route: []usize, next: []usize, previous: []usize, load: []f64, savings: []f64, order: []usize) -> (usize, err)
fn knapsack_branch_and_bound(weights: []const f64, values: []const f64, capacity: f64, taken: []u8, order: []usize, current: []u8) -> (f64, err)
fn density(weights: []const f64, values: []const f64, i: usize) -> f64
fn knapsack_bound(weights: []const f64, values: []const f64, capacity: f64, order: []const usize, from: usize, weight: f64, value: f64) -> f64
fn knapsack_search(weights: []const f64, values: []const f64, capacity: f64, order: []const usize, from: usize, weight: f64, value: f64, best: f64, current: []u8, taken: []u8) -> (f64, bool)
fn branch_and_bound[Ctx: type](ctx: *Ctx, leaf_depth: fn(*Ctx) -> usize, choices: fn(*Ctx, usize) -> usize, bound: fn(*Ctx, usize) -> f64, branch: fn(*Ctx, usize, usize), undo: fn(*Ctx, usize, usize), record: fn(*Ctx), start: f64) -> (f64, usize)
fn bb_search[Ctx: type](ctx: *Ctx, leaf_depth: fn(*Ctx) -> usize, choices: fn(*Ctx, usize) -> usize, bound: fn(*Ctx, usize) -> f64, branch: fn(*Ctx, usize, usize), undo: fn(*Ctx, usize, usize), record: fn(*Ctx), depth: usize, best: f64) -> (f64, usize)
fn large_neighborhood_search[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, iterations: usize, start: f64, destroy: fn(*Ctx, *rand.Pcg64), repair: fn(*Ctx, *rand.Pcg64) -> f64, accept: fn(*Ctx), restore: fn(*Ctx)) -> (f64, usize)
```

Tours over a distance matrix: `tsp_nearest_neighbor`, `tsp_two_opt`, `tsp_or_opt`,
`tsp_held_karp` (exact, `n <= 16`), `tour_length`; `set_cover_greedy`, `bin_pack_ffd`,
`vrp_savings` (Clarke-Wright under a capacity), `knapsack_branch_and_bound`, the generic
`branch_and_bound` over caller callbacks and `large_neighborhood_search` over caller
destroy and repair.

### `e.algo.sat`

```neper
type Cnf = struct { literals: []i32, starts: []usize, clauses: usize, variables: usize }
error TooSmall
error Invalid
error Unsatisfiable

fn cnf(literals: []i32, starts: []usize, variables: usize) -> (Cnf, err)
fn fresh(f: *Cnf) -> i32
fn add_clause(f: *Cnf, lits: []const i32) -> err
fn abs(x: i32) -> i32
fn clause1(f: *Cnf, a: i32) -> err
fn clause2(f: *Cnf, a: i32, b: i32) -> err
fn clause3(f: *Cnf, a: i32, b: i32, c3: i32) -> err
fn tseitin_and(f: *Cnf, a: i32, b: i32) -> (i32, err)
fn tseitin_or(f: *Cnf, a: i32, b: i32) -> (i32, err)
fn tseitin_xor(f: *Cnf, a: i32, b: i32) -> (i32, err)
fn tseitin_not(a: i32) -> i32
fn at_most(f: *Cnf, lits: []const i32, k: usize) -> err
fn pseudo_boolean(f: *Cnf, lits: []const i32, coefficients: []const u32, bound: u32, memo: []i32) -> err
fn pb_node(f: *Cnf, lits: []const i32, coefficients: []const u32, bound: u32, memo: []i32, index: usize, sum: u32) -> (i32, err)
fn value_of(assignment: []const i8, lit: i32) -> i8
fn solve(f: *const Cnf, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize, max_conflicts: usize) -> err
fn propagate(f: *const Cnf, assignment: []i8, trail: []u32, level: []u32, trail_len: *usize, decisions: usize, learned: []const i32, learned_starts: []const usize, learned_count: usize) -> bool
fn satisfied(f: *const Cnf, assignment: []const i8) -> bool
fn walksat(f: *const Cnf, assignment: []i8, p: f64, flips: usize, r: *rand.Pcg64) -> (bool, err)
fn preprocess(f: *Cnf, fixed: []i8) -> err
fn equivalent(f: *Cnf, left: i32, right: i32, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize) -> (bool, err)
```

`Cnf` over caller literal and clause arrays (`add_clause`, `clause1..3`, `fresh`);
`solve` (DPLL with unit propagation, flipping backtrack and a learned clause per
conflict), `walksat`, `preprocess`, `satisfied`; `tseitin_and/or/xor/not`, `at_most`
(sequential counter), `pseudo_boolean` (a decision diagram over partial sums) and
`equivalent` (a miter solved).

### `e.algo.csp`

```neper
error TooSmall
error Invalid
error Unsatisfiable

fn count(domains: []const u8, k: usize, x: usize) -> usize
fn revise[Ctx: type](domains: []u8, k: usize, x: usize, y: usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool) -> bool
fn ac3[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, queue: []usize, queued: []u8) -> err
fn solve[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, saved: []u8, queue: []usize, queued: []u8) -> (bool, err)
fn mac[Ctx: type](domains: []u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, saved: []u8, queue: []usize, queued: []u8, depth: usize) -> bool
fn limited_discrepancy[Ctx: type](domains: []const u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, max_discrepancies: usize, assignment: []usize) -> (bool, usize, err)
fn consistent[Ctx: type](pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []const usize, x: usize) -> bool
fn lds[Ctx: type](domains: []const u8, n: usize, k: usize, pairs: []const usize, ctx: *Ctx, allowed: fn(*Ctx, usize, usize, usize, usize) -> bool, assignment: []usize, x: usize, budget: usize) -> bool
fn augment(domains: []const u8, k: usize, vars: []const usize, x: usize, match_value: []usize, seen: []u8) -> bool
fn all_different(domains: []u8, k: usize, vars: []const usize, match_value: []usize, seen: []u8) -> err
fn element(domains: []u8, k: usize, index: usize, result: usize, array: []const usize) -> err
fn table(domains: []u8, k: usize, vars: []const usize, tuples: []const usize, rows: usize) -> err
fn cumulative(domains: []u8, k: usize, starts: []const usize, duration: []const usize, demand: []const usize, capacity: usize, horizon: usize, profile: []usize) -> err
```

Domains as `n × k` bytes and binary constraints as the caller's `allowed(ctx, x, y, a, b)`
over listed pairs: `ac3`, `solve` (maintained arc consistency, smallest domain first),
`limited_discrepancy`; the filters `all_different` (matching-based pruning), `element`,
`table` and `cumulative` (a time-table capacity check).

### `e.algo.logic`

```neper
type Implicant = struct { value: u32, care: u32 }
error TooSmall
error Invalid

fn popcount(x: u32) -> usize
fn prime_implicants(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []Implicant, work: []Implicant, merged: []u8) -> (usize, err)
fn covers(p: Implicant, m: u32) -> bool
fn cover(minterms: []const u32, primes: []const Implicant, chosen: []usize, covered: []u8) -> (usize, err)
fn quine_mccluskey(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []Implicant, chosen: []usize, work: []Implicant, merged: []u8, covered: []u8) -> (usize, usize, err)
fn verify(n: usize, minterms: []const u32, dont_cares: []const u32, primes: []const Implicant, chosen: []const usize) -> bool
```

Quine-McCluskey: `prime_implicants` merges minterms (with don't cares) into
`Implicant`s (value and care masks), `cover` takes the essential primes then a greedy
cover, `quine_mccluskey` does both and `verify` checks a cover against the function.

### `e.algo.bdd`

```neper
type Bdd = struct { variable: []u32, low: []u32, high: []u32, used: usize, variables: usize }
type Op = enum u8 { And, Or, Xor }
error TooSmall
error Invalid

fn bdd(variable: []u32, low: []u32, high: []u32, variables: usize) -> (Bdd, err)
fn make(b: *Bdd, v: u32, lo: u32, hi: u32) -> (u32, err)
fn var_node(b: *Bdd, v: usize) -> (u32, err)
fn constant(value: bool) -> u32
fn op_apply(op: Op, a: bool, c: bool) -> bool
fn apply(b: *Bdd, op: Op, f: u32, g: u32, memo_keys: []u64, memo_values: []u32, memo_count: *usize) -> (u32, err)
fn negate(b: *Bdd, f: u32, memo_keys: []u64, memo_values: []u32, memo_count: *usize) -> (u32, err)
fn evaluate(b: *const Bdd, f: u32, assignment: []const bool) -> bool
fn count(b: *const Bdd, f: u32) -> u64
fn count_from(b: *const Bdd, f: u32, from: u32) -> u64
```

Reduced ordered BDDs over a caller node pool with a unique table: `var_node`, `apply`
(and, or, xor with a caller memo, reset per operation), `negate`, `evaluate`, `count`
(satisfying assignments).

### `e.algo.ecc`

```neper
type Field = struct { exp: [512]u8, log: [256]u8, order: usize }
error Invalid
error TooSmall

fn field() -> Field
fn field16() -> Field
fn mul(f: *const Field, a: u8, b: u8) -> u8
fn inverse(f: *const Field, a: u8) -> u8
fn alpha_pow(f: *const Field, e: usize) -> u8
fn alpha_neg(f: *const Field, e: usize) -> u8
fn poly_eval(f: *const Field, p: []const u8, x: u8) -> u8
fn code_eval(f: *const Field, c: []const u8, x: u8) -> u8
fn poly_mul(f: *const Field, a: []const u8, b: []const u8, out: []u8)
fn berlekamp_massey(f: *const Field, seq: []const u8, lambda: []u8, prior: []u8, scratch: []u8) -> usize
fn chien(f: *const Field, p: []const u8, n: usize, roots: []usize) -> usize
fn reed_solomon_encode(f: *const Field, data: []const u8, parity: usize, out: []u8) -> (usize, err)
fn reed_solomon_decode(f: *const Field, code: []u8, parity: usize, erasures: []const usize) -> (usize, err)
fn reed_solomon_erasure_encode(f: *const Field, data: []const u8, k: usize, parity: []u8, m: usize) -> err
fn reed_solomon_erasure_decode(f: *const Field, chunks: []u8, k: usize, m: usize, missing: []const usize) -> err
fn bch_encode(generator: u32, data: u32) -> u32
fn bch_decode(word: u32, t: usize) -> (u32, usize, err)
fn convolutional_encode(bits: []const u8, out: []u8) -> (usize, err)
fn viterbi_decode(received: []const u8, out: []u8, survivors: []u8) -> (usize, err)
fn ldpc_check(h: []const u8, rows: usize, cols: usize, word: []const u8) -> bool
fn ldpc_decode(h: []const u8, rows: usize, cols: usize, word: []u8, messages: []f64, iterations: usize) -> (usize, err)
fn hamming_encode(nibble: u8) -> u8
fn hamming_syndrome(word: u8) -> u8
fn hamming_nibble(word: u8) -> u8
fn hamming_decode(word: u8) -> (u8, bool, bool)
fn secded_encode(nibble: u8) -> u8
fn secded_decode(word: u8) -> (u8, bool, bool)
```

Reed-Solomon over GF(2^8) (`reed_solomon_encode/decode` with errors and erasures by
Berlekamp-Massey, Chien and Forney; K+M `reed_solomon_erasure_encode/decode`), BCH over
GF(2^4) (`bch_encode/decode`), a rate-1/2 K=3 convolutional code (`convolutional_encode`,
`viterbi_decode`), min-sum LDPC (`ldpc_check`, `ldpc_decode`) and Hamming (7,4) with
SECDED (8,4).

### `e.algo.geom3`

```neper
type Vec3 = struct { x: f64, y: f64, z: f64 }
type BarnesHut = struct { xs: []const f64, ys: []const f64, zs: []const f64, masses: []const f64, x0: f64, y0: f64, z0: f64, size: f64, child: []u32, body: []u32, mass: []f64, cx: []f64, cy: []f64, cz: []f64, used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn vec3(x: f64, y: f64, z: f64) -> Vec3
fn add(a: Vec3, b: Vec3) -> Vec3
fn sub(a: Vec3, b: Vec3) -> Vec3
fn scale(a: Vec3, s: f64) -> Vec3
fn dot(a: Vec3, b: Vec3) -> f64
fn cross(a: Vec3, b: Vec3) -> Vec3
fn length(a: Vec3) -> f64
fn normalize(a: Vec3) -> Vec3
fn component(v: Vec3, axis: usize) -> f64
fn same(a: Vec3, b: Vec3) -> bool
fn ray_box(origin: Vec3, direction: Vec3, box_min: Vec3, box_max: Vec3) -> (bool, f64)
fn ray_triangle(origin: Vec3, direction: Vec3, a: Vec3, b: Vec3, c: Vec3) -> (bool, f64, f64, f64)
fn ray_sphere(origin: Vec3, direction: Vec3, center: Vec3, radius: f64) -> (bool, f64)
fn ray_plane(origin: Vec3, direction: Vec3, point: Vec3, normal: Vec3) -> (bool, f64)
fn ray_disk(origin: Vec3, direction: Vec3, center: Vec3, normal: Vec3, radius: f64) -> (bool, f64)
fn project(points: []const Vec3, axis: Vec3) -> (f64, f64)
fn separating_axis(a: []const Vec3, b: []const Vec3, axes: []const Vec3) -> bool
fn obb_axes(a: []const Vec3, b: []const Vec3, out: []Vec3) -> (usize, err)
fn push_axis(out: []Vec3, n: *usize, v: Vec3) -> err
fn polytope_axes(a: []const Vec3, a_faces: []const u32, b: []const Vec3, b_faces: []const u32, out: []Vec3) -> (usize, err)
fn support(points: []const Vec3, d: Vec3) -> Vec3
fn minkowski_support(a: []const Vec3, b: []const Vec3, d: Vec3) -> Vec3
fn closest_on_triangle(a: Vec3, b: Vec3, c: Vec3) -> (Vec3, u32)
fn keep_triangle(s: []Vec3, base: usize, bits: u32) -> usize
fn closest_on_simplex(s: []Vec3, n: usize) -> (Vec3, usize)
fn gjk(a: []const Vec3, b: []const Vec3, simplex: []Vec3) -> (bool, f64, usize, err)
fn face_normal(vertices: []const Vec3, faces: []const u32, f: usize) -> Vec3
fn face_sees(vertices: []const Vec3, faces: []const u32, f: usize, p: Vec3, tolerance: f64) -> bool
fn expand_polytope(vertices: []const Vec3, faces: []u32, count: usize, edges: []u32, p_index: usize, tolerance: f64) -> (usize, err)
fn complete_tetrahedron(a: []const Vec3, b: []const Vec3, vertices: []Vec3, count: usize) -> (usize, err)
fn epa(a: []const Vec3, b: []const Vec3, simplex: []const Vec3, count: usize, vertices: []Vec3, faces: []u32, edges: []u32, tolerance: f64, max_iterations: usize) -> (Vec3, f64, err)
fn octant(x: f64, y: f64, z: f64, cx: f64, cy: f64, cz: f64) -> usize
fn clear_node(t: *BarnesHut, node: usize)
fn insert_body(t: *BarnesHut, b: usize) -> err
fn barnes_hut_build(xs: []const f64, ys: []const f64, zs: []const f64, masses: []const f64, child: []u32, body: []u32, mass: []f64, cx: []f64, cy: []f64, cz: []f64) -> (BarnesHut, err)
fn force_node(t: *const BarnesHut, node: usize, size: f64, i: usize, theta: f64, acc: *Vec3)
fn barnes_hut_force(t: *const BarnesHut, i: usize, theta: f64) -> Vec3
fn rotate(rotation: []const f64, v: Vec3) -> Vec3
fn mean_point(points: []const Vec3) -> Vec3
fn kabsch(p: []const Vec3, q: []const Vec3, rotation: []f64) -> (Vec3, err)
fn kabsch_rmsd(p: []const Vec3, q: []const Vec3, rotation: []const f64, translation: Vec3) -> f64
fn farthest_from_plane(points: []const Vec3, a: Vec3, normal: Vec3) -> (usize, f64)
fn hull(points: []const Vec3, faces: []u32, edges: []u32, tolerance: f64) -> (usize, err)
fn hull_volume(points: []const Vec3, faces: []const u32, count: usize) -> f64
fn hull_area(points: []const Vec3, faces: []const u32, count: usize) -> f64
```

`Vec3` helpers; ray tests (`ray_box`, `ray_triangle`, `ray_sphere`, `ray_plane`,
`ray_disk`); `separating_axis` with `obb_axes` and `polytope_axes`; `gjk` (closest-point
GJK leaving its simplex) and `epa`; `barnes_hut_build/force` over an octree of masses;
`kabsch` (Horn's quaternion) with `rotate` and `kabsch_rmsd`; `hull` (quickhull) with
`hull_volume` and `hull_area`.

### `e.algo.hash`

```neper
type XxHash64 = struct { seed: u64, total: u64, v1: u64, v2: u64, v3: u64, v4: u64, buffer: [32]u8, buffered: u8 }
type Crc32 = struct { value: u32 }

fn fnv1a32(data: []const u8) -> u32
fn fnv1a64(data: []const u8) -> u64
fn xxhash64(data: []const u8, seed: u64) -> u64
fn xxhash64_init(seed: u64) -> XxHash64
fn xxhash64_update(h: *XxHash64, data: []const u8)
fn xxhash64_done(h: *const XxHash64) -> u64
fn crc32(data: []const u8) -> u32
fn crc32_init() -> Crc32
fn crc32_update(h: *Crc32, data: []const u8)
fn crc32_done(h: *const Crc32) -> u32
fn adler32(data: []const u8) -> u32
```

### `e.algo.deflate`

```neper
type Encoder = struct { state: *void }
type Decoder = struct { state: *void }
type Level = enum u8 { Fast, Balanced, Best }
type Status = enum u8 { NeedInput, NeedOutput, Finished }
error Invalid
error TooLarge

fn encoder(storage: []u8, level: Level) -> (Encoder, err)
fn decoder(storage: []u8, window_limit: usize) -> (Decoder, err)
fn encode(e: *Encoder, input: []const u8, output: []u8, finish: bool) -> (usize, usize, Status, err)
fn decode(d: *Decoder, input: []const u8, output: []u8, finish: bool) -> (usize, usize, Status, err)
fn encoder_storage(level: Level) -> usize
fn decoder_storage(window_limit: usize) -> (usize, err)
```

The calls return consumed input and written output. State uses caller storage and
performs no allocation. This module implements raw RFC 1951 DEFLATE only; gzip and
ZIP framing belong to `e.fmt.gzip` and `e.fmt.zip`.

### `e.algo.graph`

```neper
type Traversal = struct { order: []const graph.NodeId, parent: []const graph.NodeId }
type Components = struct { component: []const u32, count: u32 }
type Paths = struct { distance: []const f64, previous: []const graph.NodeId }
error Cycle
error InvalidWeight
error TooLarge

fn bfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err)
fn dfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err)
fn topological[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn weak_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err)
fn strong_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err)
fn dijkstra[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Paths, err)
```

Traversal order is deterministic from node order and each adjacency list's insertion
order. An unreachable node has parent `graph.NONE`; the start is its own parent.
Topological sorting returns the lexicographically smallest available node first and
returns `Cycle` without a partial order. Component identifiers are assigned by the
smallest node in each component. Dijkstra rejects negative, NaN and infinite weights
as `InvalidWeight`; unreachable distance is positive infinity and its predecessor is
`graph.NONE`. All returned slices are arena-owned.

### `e.algo.disjoint_set`

```neper
type DisjointSet = struct { parent: []u32, rank: []u8, sets: usize }
error TooLarge
error TooSmall

fn init(parent: []u32, rank: []u8, count: usize) -> (DisjointSet, err)
fn len(s: *const DisjointSet) -> usize
fn set_count(s: *const DisjointSet) -> usize
fn find(s: *DisjointSet, value: u32) -> u32
fn same(s: *DisjointSet, a: u32, b: u32) -> bool
fn join(s: *DisjointSet, a: u32, b: u32) -> bool
fn reset(s: *DisjointSet)
```

The caller supplies storage. `count` must fit `u32` and both slices. `find` performs
path compression and `join` uses union by rank (it is not spelled `union`: that is a
keyword, D161); indices outside `count` follow the ordinary bounds-trap rule.

### `e.algo.rand.quasi`

```neper
type Sobol = struct { index: u64, x: [8]u64, dims: usize }
error Invalid
error TooSmall

fn direction(d: usize, bit: u32) -> u64
fn sobol(index: u64, out: []f64) -> err
fn sobol_start(dims: usize) -> (Sobol, err)
fn sobol_next(s: *Sobol, out: []f64) -> err
fn van_der_corput(index: u64, base: u64) -> f64
fn halton(index: u64, base: u64) -> f64
fn halton_point(index: u64, out: []f64) -> err
fn prime(d: usize) -> u64
```

Low-discrepancy sequences: `sobol` and the incremental `sobol_start`/`sobol_next` in
Gray-code order over Joe-Kuo direction numbers (eight dimensions), `van_der_corput`,
`halton` and `halton_point` over the first sixteen primes.

### `e.algo.rand.dist`

```neper
type Alias = struct { probability: []f64, alias: []usize }
type WeightedReservoir = struct { items: []u64, keys: []f64, count: usize }
error TooSmall
error Invalid

fn uniform_open(r: *rand.Pcg64) -> f64
fn normal(r: *rand.Pcg64) -> f64
fn normal_box_muller(r: *rand.Pcg64) -> (f64, f64)
fn exponential(r: *rand.Pcg64, rate: f64) -> f64
fn poisson(r: *rand.Pcg64, mean: f64) -> u64
fn binomial(r: *rand.Pcg64, n: u64, p: f64) -> u64
fn gamma(r: *rand.Pcg64, shape: f64, scale: f64) -> f64
fn beta(r: *rand.Pcg64, alpha: f64, b: f64) -> f64
fn dirichlet(r: *rand.Pcg64, alphas: []const f64, out: []f64) -> err
fn cholesky(covariance: []const f64, n: usize, factor: []f64) -> err
fn multivariate_normal(r: *rand.Pcg64, mean: []const f64, factor: []const f64, n: usize, out: []f64, scratch: []f64) -> err
fn inverse_transform[Ctx: type](r: *rand.Pcg64, ctx: *Ctx, quantile: fn(*Ctx, f64) -> f64) -> f64
fn rejection[Ctx: type](r: *rand.Pcg64, low: f64, high: f64, bound: f64, max_tries: u32, ctx: *Ctx, density: fn(*Ctx, f64) -> f64) -> (f64, bool)
fn importance_weight[Ctx: type](x: f64, ctx: *Ctx, target_density: fn(*Ctx, f64) -> f64, proposal_density: fn(*Ctx, f64) -> f64) -> f64
fn alias_build(weights: []const f64, probability: []f64, alias: []usize, scratch: []usize) -> (Alias, err)
fn alias_sample(t: *const Alias, r: *rand.Pcg64) -> usize
fn weighted_reservoir(items: []u64, keys: []f64) -> (WeightedReservoir, err)
fn weighted_reservoir_offer(s: *WeightedReservoir, r: *rand.Pcg64, item: u64, weight: f64)
fn stratified(r: *rand.Pcg64, out: []f64)
fn latin_hypercube(r: *rand.Pcg64, points: usize, dims: usize, out: []f64, scratch: []usize) -> err
fn radical_inverse(index: u64, base: u64) -> f64
fn halton(index: u64, out: []f64) -> err
fn sobol(index: u64, out: []f64) -> err
fn direction(d: usize, bit: u64) -> u64
```

Variates draw from a `*rand.Pcg64`. `binomial` inverts the CDF below a mean of 30
and uses the normal approximation above; `poisson` likewise past 500. The alias
table and weighted reservoir live in caller storage; `sobol` covers four
dimensions from Joe-Kuo direction numbers and `halton` sixteen.

### `e.algo.stat.test`

```neper
type Result = struct { statistic: f64, p_value: f64 }
error TooSmall
error Invalid

fn mean(values: []const f64) -> f64
fn sample_variance(values: []const f64) -> f64
fn two_sided_t(t: f64, df: f64) -> f64
fn two_sided_normal(z: f64) -> f64
fn t_test(values: []const f64, mu: f64) -> (Result, err)
fn t_test_two(a: []const f64, b: []const f64) -> (Result, err)
fn welch(a: []const f64, b: []const f64) -> (Result, err)
fn ranks(values: []const f64, out: []f64, order: []usize) -> (f64, err)
fn mann_whitney(a: []const f64, b: []const f64, scratch: []f64, order: []usize) -> (Result, err)
fn wilcoxon(a: []const f64, b: []const f64, scratch: []f64, order: []usize) -> (Result, err)
fn chi_squared(observed: []const f64, expected: []const f64) -> (Result, err)
fn fisher_exact(a: u64, b: u64, c: u64, d: u64) -> Result
fn table_log_probability(x: u64, row1: u64, row2: u64, col1: u64, log_total: f64) -> f64
fn sort_floats(values: []f64)
fn kolmogorov_smirnov(a: []f64, b: []f64) -> (Result, err)
fn anova(values: []const f64, sizes: []const usize) -> (Result, err)
fn kruskal_wallis(values: []const f64, sizes: []const usize, scratch: []f64, order: []usize) -> (Result, err)
fn permutation(r: *rand.Pcg64, a: []const f64, b: []const f64, rounds: u32, scratch: []f64) -> (Result, err)
fn bonferroni(p_values: []f64)
fn benjamini_hochberg(p_values: []f64, order: []usize) -> err
```

Every test answers a statistic and a two-sided p-value. The rank tests use the
normal approximation with continuity and tie correction; `kolmogorov_smirnov`
sorts its inputs and uses the Numerical Recipes small-sample correction;
`fisher_exact` sums every table at least as unlikely as the observed one.
Scratch: `mann_whitney` `2 * (a.len + b.len)` floats, `wilcoxon` `3 * a.len`,
`kruskal_wallis` the total, each with as many indices in `order`.

### `e.algo.stat`

```neper
type Moments = struct { count: u64, mean: f64, m2: f64, min: f64, max: f64 }
type Regression = struct { count: u64, mean_x: f64, mean_y: f64, m2_x: f64, m2_y: f64, cov: f64 }

fn moments() -> Moments
fn moments_add(s: *Moments, x: f64)
fn moments_merge(dst: *Moments, src: *const Moments)
fn variance_population(s: *const Moments) -> (f64, bool)
fn variance_sample(s: *const Moments) -> (f64, bool)
fn standard_deviation_population(s: *const Moments) -> (f64, bool)
fn standard_deviation_sample(s: *const Moments) -> (f64, bool)
fn regression() -> Regression
fn regression_add(s: *Regression, x: f64, y: f64)
fn regression_slope(s: *const Regression) -> (f64, bool)
fn regression_intercept(s: *const Regression) -> (f64, bool)
fn correlation(s: *const Regression) -> (f64, bool)
```

### `e.algo.bitset`

```neper
type BitSet = struct { words: []u64, len: usize }
error TooSmall

fn init(storage: []u64, bit_count: usize) -> (BitSet, err)
fn len(s: *const BitSet) -> usize
fn clear_all(s: *BitSet)
fn fill_all(s: *BitSet)
fn get(s: *const BitSet, index: usize) -> bool
fn set(s: *BitSet, index: usize)
fn unset(s: *BitSet, index: usize)
fn toggle(s: *BitSet, index: usize)
fn count(s: *const BitSet) -> usize
fn first_set(s: *const BitSet) -> (usize, bool)
fn next_set(s: *const BitSet, after: usize) -> (usize, bool)
fn union_in_place(dst: *BitSet, src: *const BitSet)
fn intersect_in_place(dst: *BitSet, src: *const BitSet)
fn difference_in_place(dst: *BitSet, src: *const BitSet)
fn complement_in_place(s: *BitSet)
fn is_subset(a: *const BitSet, b: *const BitSet) -> bool
fn eq(a: *const BitSet, b: *const BitSet) -> bool
```

Bits at indices `len..storage.len*64` are always zero. Operations requiring two
sets require equal logical lengths; a mismatch is a debug bounds trap and release
undefined behavior, like incompatible slice bounds in other pure primitives.

### `e.algo.sort`

```neper
fn in_place[T: type](items: []T)
fn in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32)
fn stable_in_place[T: type](a: *mem.Arena, items: []T) -> err
fn stable_in_place_by[T: type, Ctx: type](a: *mem.Arena, items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> err
fn radix_u32_in_place(a: *mem.Arena, items: []u32) -> err
fn radix_u64_in_place(a: *mem.Arena, items: []u64) -> err
fn is_sorted[T: type](items: []const T) -> bool
```

### `e.algo.search`

```neper
fn binary[T: type](items: []const T, key: T) -> (usize, bool)
fn binary_by[T: type, Ctx: type](items: []const T, ctx: *Ctx, probe: fn(*Ctx, T) -> i32) -> (usize, bool)
fn lower_bound[T: type](items: []const T, key: T) -> usize
fn upper_bound[T: type](items: []const T, key: T) -> usize
fn equal_range[T: type](items: []const T, key: T) -> (usize, usize)
fn linear[T: type](items: []const T, key: T) -> (usize, bool)
fn exponential[T: type](items: []const T, key: T) -> (usize, bool)
fn interpolation(items: []const i64, key: i64) -> (usize, bool)
fn ternary_max[Ctx: type](low: i64, high: i64, ctx: *Ctx, f: fn(*Ctx, i64) -> i64) -> i64
fn matrix_sorted[T: type](items: []const T, columns: usize, key: T) -> (usize, usize, bool)
fn kth[T: type](items: []T, k: usize) -> T
fn kth_deterministic[T: type](items: []T, k: usize) -> T
fn cycle_floyd[Ctx: type](start: u64, ctx: *Ctx, next: fn(*Ctx, u64) -> u64) -> (usize, usize)
fn cycle_brent[Ctx: type](start: u64, ctx: *Ctx, next: fn(*Ctx, u64) -> u64) -> (usize, usize)
```

Sorted-slice entry points order by `T.cmp` and answer an index; the `_by` form takes
a probe comparing an element against the wanted key. `kth` and `kth_deterministic`
reorder their slice. The cycle finders answer the tail length and the cycle length.

### `e.algo.sketch`

```neper
type Bloom = struct { bits: []u64, hashes: u32 }
type CountingBloom = struct { counts: []u8, hashes: u32 }
type CountMin = struct { counts: []u32, width: usize, depth: usize }
type HyperLogLog = struct { registers: []u8, precision: u8 }
type Counter = struct { key: u64, count: u64 }
error Invalid
error TooSmall

fn bloom_size(items: usize, rate: f64) -> (usize, u32)
fn bloom_init(bits: []u64, hashes: u32) -> (Bloom, err)
fn bloom_insert(b: *Bloom, item: []const u8)
fn bloom_contains(b: *const Bloom, item: []const u8) -> bool
fn bloom_merge(dst: *Bloom, src: *const Bloom) -> err
fn counting_bloom_init(counts: []u8, hashes: u32) -> (CountingBloom, err)
fn counting_bloom_insert(b: *CountingBloom, item: []const u8)
fn counting_bloom_remove(b: *CountingBloom, item: []const u8) -> bool
fn counting_bloom_contains(b: *const CountingBloom, item: []const u8) -> bool
fn count_min_init(counts: []u32, width: usize, depth: usize) -> (CountMin, err)
fn count_min_add(s: *CountMin, item: []const u8, amount: u32)
fn count_min_add_conservative(s: *CountMin, item: []const u8, amount: u32)
fn count_min_estimate(s: *const CountMin, item: []const u8) -> u32
fn hll_init(registers: []u8, precision: u8) -> (HyperLogLog, err)
fn hll_add(h: *HyperLogLog, item: []const u8)
fn hll_estimate(h: *const HyperLogLog) -> f64
fn hll_merge(dst: *HyperLogLog, src: *const HyperLogLog) -> err
fn counters_clear(counters: []Counter)
fn misra_gries_add(counters: []Counter, key: u64)
fn space_saving_add(counters: []Counter, key: u64)
fn counter_get(counters: []const Counter, key: u64) -> (u64, bool)
fn minhash_mix(key: u64, permutation: u64) -> u64
fn minhash(keys: []const u64, signature: []u64)
fn minhash_similarity(a: []const u64, b: []const u64) -> f64
fn simhash(features: []const u64, weights: []const u32) -> u64
fn simhash_distance(a: u64, b: u64) -> u32
```

Every summary lives in caller storage; items are bytes hashed with
`e.algo.hash.xxhash64`, and the heavy-hitter and signature entry points take `u64`
keys. `hll_init` takes a precision in `4..=18` over `1 << precision` registers.
`bloom_size` answers a bit count that is a multiple of 64.

### `e.algo.coding`

```neper
type BitWriter = struct { out: []u8, bits: usize }
type BitReader = struct { data: []const u8, bits: usize }
type Huffman = struct { lengths: [256]u8, codes: [256]u32 }
error TooSmall
error Invalid

fn rle_encode(src: []const u8, dst: []u8) -> (usize, err)
fn rle_decode(src: []const u8, dst: []u8) -> (usize, err)
fn varint_encode(value: u64, dst: []u8) -> (usize, err)
fn varint_decode(src: []const u8) -> (u64, usize, err)
fn vlq_encode(value: u64, dst: []u8) -> (usize, err)
fn vlq_decode(src: []const u8) -> (u64, usize, err)
fn zigzag_encode(value: i64) -> u64
fn zigzag_decode(value: u64) -> i64
fn delta_encode(values: []i64)
fn delta_decode(values: []i64)
fn delta_delta_encode(values: []i64)
fn delta_delta_decode(values: []i64)
fn bit_width(values: []const u64) -> u32
fn bit_writer(out: []u8) -> BitWriter
fn write_bits(w: *BitWriter, value: u64, width: u32) -> err
fn written(w: *const BitWriter) -> usize
fn bit_reader(data: []const u8) -> BitReader
fn read_bits(r: *BitReader, width: u32) -> (u64, err)
fn bits_left(r: *const BitReader) -> usize
fn bit_pack(values: []const u64, width: u32, dst: []u8) -> (usize, err)
fn bit_unpack(src: []const u8, width: u32, values: []u64) -> err
fn for_encode(values: []const u64, dst: []u8) -> (usize, err)
fn for_decode(src: []const u8, values: []u64) -> err
fn elias_gamma_write(w: *BitWriter, value: u64) -> err
fn elias_gamma_read(r: *BitReader) -> (u64, err)
fn rice_write(w: *BitWriter, value: u64, k: u32) -> err
fn rice_read(r: *BitReader, k: u32) -> (u64, err)
fn move_to_front_encode(src: []const u8, dst: []u8) -> err
fn move_to_front_decode(src: []const u8, dst: []u8) -> err
fn bwt_encode(src: []const u8, dst: []u8, scratch: []usize) -> (usize, err)
fn bwt_sift(src: []const u8, scratch: []usize, at: usize, end: usize)
fn bwt_compare(src: []const u8, a: usize, b: usize) -> i32
fn bwt_decode(src: []const u8, row: usize, dst: []u8, scratch: []usize) -> err
fn huffman_build(frequencies: []const u64, limit: u32) -> (Huffman, err)
fn huffman_canonical(h: *Huffman)
fn huffman_encode(h: *const Huffman, src: []const u8, w: *BitWriter) -> err
fn huffman_decode(h: *const Huffman, r: *BitReader, dst: []u8) -> err
```

Encoders write into caller storage and answer the length used; decoders answer
`Invalid` for input they cannot read to the end. Bit-level codes share one
`BitWriter`/`BitReader` cursor, most significant bit first. `huffman_build` yields
canonical code lengths of at most `limit` bits (`1..=32`); a single used symbol
gets a one-bit code.

### `e.algo.complex`

```neper
type Complex[F: type] = struct { re: F, im: F }

fn make[F: type](re: F, im: F) -> Complex[F]
fn add[F: type](a: Complex[F], b: Complex[F]) -> Complex[F]
fn sub[F: type](a: Complex[F], b: Complex[F]) -> Complex[F]
fn mul[F: type](a: Complex[F], b: Complex[F]) -> Complex[F]
fn div[F: type](a: Complex[F], b: Complex[F]) -> Complex[F]
fn neg[F: type](z: Complex[F]) -> Complex[F]
fn conj[F: type](z: Complex[F]) -> Complex[F]
fn abs[F: type](z: Complex[F]) -> F
fn arg[F: type](z: Complex[F]) -> F
fn exp[F: type](z: Complex[F]) -> Complex[F]
fn log[F: type](z: Complex[F]) -> Complex[F]
fn sqrt[F: type](z: Complex[F]) -> Complex[F]
fn pow[F: type](z: Complex[F], w: Complex[F]) -> Complex[F]
fn sin[F: type](z: Complex[F]) -> Complex[F]
fn cos[F: type](z: Complex[F]) -> Complex[F]
fn tan[F: type](z: Complex[F]) -> Complex[F]
```

`F` is `f32` or `f64`. Branch cuts and signed-zero behavior follow C99 Annex G;
operations inherit `e.math`'s NaN canonicalization and no-contraction rules.

### `e.algo.decimal`

```neper
type Coefficient = struct { low: u64, high: i64 }
type Decimal = struct { coefficient: Coefficient, scale: u8 }
type Rounding = enum u8 { ToEven, AwayFromZero, TowardZero, Floor, Ceiling }
error Invalid
error Overflow
error Inexact

fn make(coefficient: Coefficient, scale: u8) -> (Decimal, err)
fn normalize(value: Decimal) -> Decimal
fn add(a: Decimal, b: Decimal) -> (Decimal, err)
fn sub(a: Decimal, b: Decimal) -> (Decimal, err)
fn mul(a: Decimal, b: Decimal) -> (Decimal, err)
fn div(a: Decimal, b: Decimal, scale: u8, rounding: Rounding) -> (Decimal, err)
fn quantize(value: Decimal, scale: u8, rounding: Rounding) -> (Decimal, err)
fn compare(a: Decimal, b: Decimal) -> i32
fn parse(source: str) -> (Decimal, err)
fn format(value: Decimal, b: *str.Builder) -> err
fn to_i64(value: Decimal, rounding: Rounding) -> (i64, err)
fn from_i64(value: i64, scale: u8) -> (Decimal, err)
```

`scale` is `0..38`; value is `coefficient * 10^-scale`. Arithmetic never silently
rounds: only operations carrying a `Rounding` argument may discard decimal digits.
Parsing is locale-free and consumes the complete ordinary or scientific decimal.

### `e.algo.bignum`

```neper
type Sign = enum u8 { Zero, Positive, Negative }
type Int = struct { sign: Sign, limbs: []u32, arena: *mem.Arena }
type Rat = struct { num: Int, den: Int }
error DivideByZero
error Invalid

fn int_zero(a: *mem.Arena) -> Int
fn int_from_i64(a: *mem.Arena, v: i64) -> (Int, err)
fn int_parse(a: *mem.Arena, s: str, radix: u8) -> (Int, err)
fn int_format(v: Int, b: *str.Builder, radix: u8) -> err
fn int_cmp(a: Int, b: Int) -> i32
fn int_add(a: *mem.Arena, x: Int, y: Int) -> (Int, err)
fn int_sub(a: *mem.Arena, x: Int, y: Int) -> (Int, err)
fn int_mul(a: *mem.Arena, x: Int, y: Int) -> (Int, err)
fn int_divmod(a: *mem.Arena, x: Int, y: Int) -> (Int, Int, err)
fn int_gcd(a: *mem.Arena, x: Int, y: Int) -> (Int, err)
fn rat_make(a: *mem.Arena, num: Int, den: Int) -> (Rat, err)
fn rat_add(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err)
fn rat_sub(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err)
fn rat_mul(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err)
fn rat_div(a: *mem.Arena, x: Rat, y: Rat) -> (Rat, err)
fn rat_cmp(a: Rat, b: Rat) -> i32
fn rat_format(v: Rat, b: *str.Builder) -> err
```

### `e.algo.linalg.matrix`

```neper
type Matrix[T: type] = struct { data: []T, rows: usize, cols: usize, stride: usize }
type ConstMatrix[T: type] = struct { data: []const T, rows: usize, cols: usize, stride: usize }
error Shape
error Singular

fn view[T: type](data: []T, rows: usize, cols: usize, stride: usize) -> (Matrix[T], err)
fn view_const[T: type](data: []const T, rows: usize, cols: usize, stride: usize) -> (ConstMatrix[T], err)
fn get[T: type](m: Matrix[T], row: usize, col: usize) -> T
fn set[T: type](m: Matrix[T], row: usize, col: usize, v: T)
fn transpose[T: type](m: Matrix[T]) -> Matrix[T]
fn fill[T: type](m: Matrix[T], v: T)
fn copy[T: type](dst: Matrix[T], src: ConstMatrix[T]) -> err
fn add[T: type](dst: Matrix[T], a: ConstMatrix[T], b: ConstMatrix[T]) -> err
fn multiply[T: type](dst: Matrix[T], a: ConstMatrix[T], b: ConstMatrix[T]) -> err
fn determinant_f64(a: *mem.Arena, m: ConstMatrix[f64]) -> (f64, err)
fn inverse_f64(a: *mem.Arena, dst: Matrix[f64], src: ConstMatrix[f64]) -> err
```

### `e.algo.linalg.tensor`

```neper
type Tensor[T: type] = struct { data: []T, shape: []const usize, stride: []const usize }
type ConstTensor[T: type] = struct { data: []const T, shape: []const usize, stride: []const usize }
error Shape

fn view[T: type](data: []T, shape: []const usize, stride: []const usize) -> (Tensor[T], err)
fn contiguous[T: type](a: *mem.Arena, data: []T, shape: []const usize) -> (Tensor[T], err)
fn as_const[T: type](tensor: Tensor[T]) -> ConstTensor[T]
fn elements[T: type](t: Tensor[T]) -> usize
fn offset[T: type](t: Tensor[T], index: []const usize) -> usize
fn reshape[T: type](a: *mem.Arena, t: Tensor[T], shape: []const usize) -> (Tensor[T], err)
fn fill[T: type](tensor: Tensor[T], value: T)
fn copy[T: type](dst: Tensor[T], src: ConstTensor[T]) -> err
fn add[T: type](dst: Tensor[T], x: ConstTensor[T], y: ConstTensor[T]) -> err
```

### `e.text.encoding`

```neper
type Encoding = enum u8 { Utf8, Utf16Le, Utf16Be, Utf32Le, Utf32Be }
type InvalidPolicy = enum u8 { Reject, Replace }
type Decoder = struct { encoding: Encoding, policy: InvalidPolicy, pending: [4]u8, pending_len: u8, bom_seen: bool }
type Encoder = struct { encoding: Encoding, emit_bom: bool, started: bool }
error Invalid
error Incomplete
error TooSmall

fn detect_bom(src: []const u8) -> (Encoding, usize, bool)
fn decoder(encoding: Encoding, policy: InvalidPolicy, consume_bom: bool) -> Decoder
fn encoder(encoding: Encoding, emit_bom: bool) -> Encoder
fn decode(d: *Decoder, src: []const u8, dst_utf8: []u8, final: bool) -> (usize, usize, err)
fn encode(e: *Encoder, src_utf8: str, dst: []u8, final: bool) -> (usize, usize, err)
fn decoded_len(encoding: Encoding, src: []const u8, policy: InvalidPolicy) -> (usize, err)
fn encoded_len(encoding: Encoding, src_utf8: str, emit_bom: bool) -> (usize, err)
fn to_utf8(a: *mem.Arena, encoding: Encoding, src: []const u8, policy: InvalidPolicy) -> (str, err)
fn from_utf8(a: *mem.Arena, encoding: Encoding, src: str, emit_bom: bool) -> ([]u8, err)
```

The streaming calls return consumed source bytes followed by written destination
bytes. `TooSmall` is resumable and consumes only complete scalar values. `final`
reports a trailing partial sequence as `Incomplete`; `Replace` emits U+FFFD for each
maximal invalid subsequence. This toolchain module intentionally excludes locale and
legacy code pages.

### `e.text.utf8`

```neper
type Decode = struct { scalar: u32, width: u8 }
type Iterator = struct { data: str, off: usize }
error Invalid
error TooSmall

fn validate(s: str) -> bool
fn decode(s: str, off: usize) -> (Decode, err)
fn encode(scalar: u32, dst: []u8) -> (u8, err)
fn count(s: str) -> (usize, err)
fn byte_offset(s: str, scalar_index: usize) -> (usize, err)
fn iterator(s: str) -> Iterator
fn iterator_next(it: *Iterator) -> (u32, bool)
fn iterator_next_err(it: *Iterator) -> (u32, bool, err)
```

### `e.text.search`

```neper
type Automaton = struct { next: []u32, fail: []u32, output: []u32, length: []u32, states: usize }
error TooLong
error TooSmall

fn kmp_table(pattern: str, table: []usize) -> err
fn kmp(text: str, pattern: str, table: []const usize) -> (usize, bool)
fn horspool(text: str, pattern: str) -> (usize, bool)
fn boyer_moore_table(pattern: str, good_suffix: []usize) -> err
fn boyer_moore(text: str, pattern: str, good_suffix: []const usize) -> (usize, bool)
fn rabin_karp(text: str, pattern: str) -> (usize, bool)
fn aho_corasick_build(a: *mem.Arena, patterns: []const str) -> (Automaton, err)
fn aho_corasick_find[Ctx: type](m: *const Automaton, text: str, ctx: *Ctx, on_match: fn(*Ctx, usize, usize) -> bool) -> bool
fn z_array(s: str, z: []usize) -> err
fn bitap(text: str, pattern: str, errors: u32) -> (usize, bool)
fn longest_palindrome(s: str, scratch: []usize) -> (usize, usize, err)
```

Every finder answers the byte offset of the leftmost match and whether one exists;
an empty pattern matches at 0. `kmp_table` needs `pattern.len` entries and
`boyer_moore_table` `2 * pattern.len + 2`. The automaton is arena-held and dense:
`(total pattern bytes + 1) * 256` transitions. `bitap` allows `errors` edits over
a pattern of at most 64 bytes.

### `e.text.distance`

```neper
error TooSmall
error Mismatch

fn levenshtein(a: str, b: str, scratch: []usize) -> (usize, err)
fn damerau_levenshtein(a: str, b: str, scratch: []usize) -> (usize, err)
fn hamming(a: str, b: str) -> (usize, err)
fn jaro(a: str, b: str, scratch: []u8) -> (f64, err)
fn jaro_winkler(a: str, b: str, scale: f64, scratch: []u8) -> (f64, err)
fn longest_common_substring(a: str, b: str, scratch: []usize) -> (usize, usize, usize, err)
fn trigram(a: str, b: str, scratch: []u32) -> (f64, err)
```

All distances count bytes. Scratch sizes: `levenshtein` and
`longest_common_substring` need `2 * (b.len + 1)`, `damerau_levenshtein`
`3 * (b.len + 1)`, `jaro`/`jaro_winkler` and `trigram` `a.len + b.len`.

### `e.text.casing`

```neper
type Style = enum u8 { Camel, Pascal, Snake, Kebab, Screaming }
error TooSmall

fn is_upper(c: u8) -> bool
fn is_lower(c: u8) -> bool
fn is_digit(c: u8) -> bool
fn is_alnum(c: u8) -> bool
fn to_lower(c: u8) -> u8
fn to_upper(c: u8) -> u8
fn boundary(name: str, i: usize) -> bool
fn words(name: str, bounds: []usize) -> (usize, err)
fn convert(name: str, style: Style, out: []u8, bounds: []usize) -> (str, err)
fn slug(text: str, out: []u8) -> (str, err)
fn is_small_word(word: str) -> bool
fn title(text: str, out: []u8) -> (str, err)
```

`words` splits an ASCII identifier at separators and case boundaries (`HTTPServer`
is two words, digits stay with their neighbours) into (start, end) pairs; `convert`
rewrites it as camelCase, PascalCase, snake_case, kebab-case or SCREAMING_SNAKE;
`slug` folds text to lowercase alphanumerics joined by single hyphens; `title`
capitalises every word but the small words of the usual style guides except at
either end.

### `e.text.phonetic`

```neper
error TooSmall

fn upper(c: u8) -> u8
fn lower(c: u8) -> u8
fn is_vowel(c: u8) -> bool
fn is_upper_vowel(c: u8) -> bool
fn is_letter(c: u8) -> bool
fn soundex_digit(c: u8) -> u8
fn soundex(name: str, out: []u8) -> (str, err)
fn at(s: str, i: usize) -> u8
fn in_iey(c: u8) -> bool
fn in_oa(c: u8) -> bool
fn metaphone(name: str, out: []u8) -> (str, err)
fn starts(s: []const u8, n: usize, p: str) -> bool
fn ends(s: []const u8, n: usize, p: str) -> bool
fn nysiis(name: str, out: []u8, scratch: []u8) -> (str, err)
```

`soundex` (a letter and three digits, doubles collapsed across H and W),
`metaphone` (the original 1990 transformation table, `0` for TH) and `nysiis` (the
1970 rules) code an ASCII name into `out`; the empty name codes to nothing.

### `e.text.stem`

```neper
error TooSmall

fn lower(c: u8) -> u8
fn is_vowel_letter(c: u8) -> bool
fn is_consonant(w: []const u8, i: usize) -> bool
fn measure(w: []const u8, n: usize) -> usize
fn contains_vowel(w: []const u8, n: usize) -> bool
fn ends_double_consonant(w: []const u8, n: usize) -> bool
fn ends_cvc(w: []const u8, n: usize) -> bool
fn ends_with(w: []const u8, n: usize, suffix: str) -> bool
fn append(w: []u8, n: usize, s: str) -> usize
fn apply_rules(w: []u8, n: usize, rules: str, condition: u8) -> usize
fn porter(word: str, out: []u8) -> (str, err)
fn is_lancaster_vowel(c: u8) -> bool
fn lancaster_acceptable(w: []const u8, n: usize, remove: usize) -> bool
fn lancaster_rules() -> str
fn lancaster(word: str, out: []u8) -> (str, err)
fn strip_affixes(word: str, prefixes: []const str, suffixes: []const str, minimum: usize) -> str
fn starts_at(word: str, start: usize, p: str) -> bool
```

`porter` is the 1980 algorithm as published, `lancaster` the Paice/Husk stemmer
over its standard 115 rules (kept as the original rule text and interpreted), and
`strip_affixes` removes the caller's prefixes and suffixes longest first, repeatedly,
never below `minimum` bytes.

### `e.text.wrap`

```neper
error TooSmall
error Invalid

fn words(text: str, bounds: []usize) -> (usize, err)
fn greedy(text: str, width: usize, lines: []usize, scratch: []usize) -> (usize, err)
fn optimal(text: str, width: usize, lines: []usize, scratch: []usize) -> (usize, err)
fn justify(line: str, width: usize, out: []u8, scratch: []usize) -> (str, err)
```

`greedy` and `optimal` (Knuth's minimum-raggedness dynamic programme, the last line
free) break space-separated words into lines answered as (start, end) byte pairs, an
overlong word alone on its line; `justify` spreads a line's words to `width` columns
with the extra spaces from the left.

### `e.text.metric`

```neper
type Rouge = struct { precision: f64, recall: f64, f1: f64 }
error TooSmall
error Invalid

fn split(text: str, bounds: []usize) -> (usize, err)
fn word_equal(a: str, ab: []const usize, i: usize, b: str, bb: []const usize, j: usize) -> bool
fn gram_equal(a: str, ab: []const usize, i: usize, b: str, bb: []const usize, j: usize, n: usize) -> bool
fn clipped(c: str, cb: []const usize, cn: usize, r: str, rb: []const usize, rn: usize, n: usize) -> usize
fn bounds_of(candidate: str, reference: str, scratch: []usize) -> (usize, usize, err)
fn bleu(candidate: str, reference: str, max_n: usize, scratch: []usize) -> (f64, err)
fn rouge_of(matched: usize, candidate_count: usize, reference_count: usize) -> Rouge
fn rouge_n(candidate: str, reference: str, n: usize, scratch: []usize) -> (Rouge, err)
fn rouge_l(candidate: str, reference: str, scratch: []usize) -> (Rouge, err)
fn meteor(candidate: str, reference: str, scratch: []usize) -> (f64, err)
```

Over one reference of space-separated words: `bleu` (clipped n-gram precisions to
`max_n`, geometric mean, brevity penalty, zero when an order has no match),
`rouge_n` and `rouge_l` (precision, recall and F1 over n-grams and over the longest
common subsequence) and `meteor` over exact matches with the fragmentation penalty.

### `e.text.suffix`

```neper
type Automaton = struct { link: []u32, length: []u32, first_edge: []u32, edge_byte: []u8, edge_to: []u32, edge_next: []u32, states: usize, edges: usize }
type Tree = struct { text: str, parent: []u32, depth: []u32, first_child: []u32, next_sibling: []u32, suffix: []u32, nodes: usize }
error TooSmall
error TooLong
const NONE: u32 = 4294967295u32

fn array_build(text: str, sa: []usize, scratch: []usize) -> err
fn lcp_array(text: str, sa: []const usize, lcp: []usize, scratch: []usize) -> err
fn compare_at(text: str, at: usize, pattern: str) -> i32
fn array_search(text: str, sa: []const usize, pattern: str) -> (usize, usize)
fn automaton_edge(m: *const Automaton, state: usize, c: u8) -> u32
fn automaton_add_edge(m: *Automaton, from: usize, c: u8, to: u32)
fn automaton_set_edge(m: *Automaton, from: usize, c: u8, to: u32)
fn automaton_build(a: *mem.Arena, text: str) -> (Automaton, err)
fn automaton_contains(m: *const Automaton, pattern: str) -> bool
fn automaton_distinct_substrings(m: *const Automaton) -> u64
fn tree_build(a: *mem.Arena, text: str, sa: []const usize, lcp: []const usize) -> (Tree, err)
fn tree_detach(t: *Tree, parent: usize, child: usize)
fn tree_edge(t: *const Tree, node: usize) -> str
fn tree_contains(t: *const Tree, pattern: str) -> bool
```

`array_build` (prefix doubling with counting sorts) and `lcp_array` (Kasai) fill
caller storage; `array_search` answers the range of the array whose suffixes start
with a pattern; `automaton_build` is the suffix automaton in the arena (edges as
sibling lists; `automaton_contains`, `automaton_distinct_substrings`) and
`tree_build` the suffix tree derived from the array and LCP array (`tree_edge`,
`tree_contains`; a suffix that prefixes another gets an internal node, as a
terminator would give it).

### `e.text.diff`

```neper
type Op = enum u8 { Keep, Delete, Insert }
type Edit = struct { op: Op, line: str }
type Range = struct { start: usize, end: usize }
error TooSmall
error Mismatch

fn same(a: str, b: str) -> bool
fn myers_scratch(n: usize, m: usize) -> usize
fn myers(a: []const str, b: []const str, edits: []Edit, scratch: []usize) -> (usize, err)
fn patch(text: []const str, edits: []const Edit, out: []str) -> (usize, err)
fn patience(a: []const str, b: []const str, edits: []Edit, scratch: []usize) -> (usize, err)
fn hunks_of(edits: []const Edit, produced: usize, hunks: []usize) -> (usize, err)
fn side_lines(edits: []const Edit, produced: usize, s: usize, e: usize, out: []str, n: usize, write: bool) -> (usize, usize, err)
fn next_line(edits: []const Edit, produced: usize, s: usize, e: usize, i: usize, base: usize) -> (bool, str, usize, usize)
fn sides_agree(ours: []const Edit, our_count: usize, theirs: []const Edit, their_count: usize, s: usize, e: usize) -> bool
fn walk(base: []const str, ours: []const Edit, our_count: usize, theirs: []const Edit, their_count: usize, out: []str, write: bool, found: []Range, record: bool, scratch: []usize) -> (usize, usize, err)
fn both_scripts(base: []const str, ours: []const str, theirs: []const str, edits: []Edit, scratch: []usize) -> (usize, usize, err)
fn merge3(base: []const str, ours: []const str, theirs: []const str, out: []str, edits: []Edit, scratch: []usize) -> (usize, usize, err)
fn conflicts(base: []const str, ours: []const str, theirs: []const str, edits: []Edit, found: []Range, scratch: []usize) -> (usize, err)
fn similarity(a: []const str, b: []const str, scratch: []usize) -> (f64, err)
```

Texts are slices of lines and a script is `Edit`s carrying their line: `myers` (the
O(ND) greedy algorithm, every frontier kept for the trace back), `patience` (unique
lines anchored by longest increasing subsequence, `myers` between anchors), `patch`
(replays a script, checking every kept and deleted line), `merge3` (one-sided changes
taken, identical ones once, the rest between `<<<<<<<`, `=======`, `>>>>>>>` lines),
`conflicts` (the base ranges `merge3` would mark) and `similarity` (twice the common
subsequence over the total).

### `e.text.rank`

```neper
error TooSmall
error Invalid

fn same(a: str, b: str) -> bool
fn word_count(doc: str) -> usize
fn term_frequency(doc: str, term: str) -> usize
fn document_frequency(docs: []const str, term: str) -> usize
fn tf_idf(docs: []const str, index: usize, term: str) -> f64
fn bm25(docs: []const str, index: usize, query: str, k1: f64, b: f64) -> f64
fn reciprocal_rank_fusion(rankings: []const usize, starts: []const usize, k: f64, scores: []f64, order: []usize) -> (usize, err)
fn maximal_marginal_relevance(relevance: []const f64, similarity: []const f64, lambda: f64, count: usize, order: []usize, scratch: []usize) -> (usize, err)
```

Documents are strings of space-separated words: `term_frequency`, `document_frequency`,
`tf_idf` (share of the words times `ln(N / df)`), `bm25` (Okapi, Lucene's idf);
`reciprocal_rank_fusion` merges flat rankings by `1 / (k + rank)` into scores and an
order; `maximal_marginal_relevance` re-ranks by relevance minus the largest similarity
to what is already chosen.

### `e.text.index`

```neper
type Index = struct { terms: []str, starts: []usize, postings: []u32, documents: usize }
error TooSmall
error Invalid

fn compare(a: str, b: str) -> i32
fn count_words(doc: str) -> usize
fn sort_pairs(words: []const str, docs: []const u32, order: []usize, scratch: []usize, low: usize, high: usize)
fn build(a: *mem.Arena, docs: []const str) -> (Index, err)
fn lookup(x: *const Index, term: str) -> []const u32
fn intersect(a: []const u32, b: []const u32, out: []u32) -> (usize, err)
fn unite(a: []const u32, b: []const u32, out: []u32) -> (usize, err)
fn low_bits(n: usize, universe: u32) -> u32
fn set_bit(bits: []u8, at: usize)
fn get_bit(bits: []const u8, at: usize) -> bool
fn elias_fano_size(n: usize, universe: u32) -> usize
fn elias_fano_encode(values: []const u32, universe: u32, out: []u8) -> (usize, err)
fn elias_fano_decode(bytes: []const u8, n: usize, universe: u32, values: []u32) -> err
```

`build` makes an inverted index in the arena (terms in byte order, sorted postings);
`lookup` is a binary search, `intersect` and `unite` merge posting lists. Elias-Fano:
`elias_fano_size`, `elias_fano_encode` (low bits packed, high bits unary) and
`elias_fano_decode` over a sorted list below a universe.

### `e.text.tokenize`

```neper
type Bpe = struct { left: []str, right: []str, count: usize }
error TooSmall
error Invalid
error Unknown

fn same(a: str, b: str) -> bool
fn shingles(text: str, k: usize, out: []str) -> (usize, err)
fn word_shingles(text: str, k: usize, out: []str, scratch: []usize) -> (usize, err)
fn word_break(text: str, dictionary: []const str, breaks: []usize, scratch: []usize) -> (usize, err)
fn bpe_train(a: *mem.Arena, corpus: []const str, merges: usize) -> (Bpe, err)
fn token_at(word: str, starts: []const usize, base: usize, live: usize, t: usize) -> str
fn pair_at(word: str, starts: []const usize, base: usize, live: usize, t: usize) -> (str, str)
fn seen_before(corpus: []const str, starts: []const usize, first: []const usize, live: []const usize, w: usize, t: usize, l: str, r: str) -> bool
fn count_pair(corpus: []const str, starts: []const usize, first: []const usize, live: []const usize, l: str, r: str) -> usize
fn merge_word(word: str, starts: []usize, base: usize, live: usize, l: str, r: str) -> usize
fn bpe_encode(b: *const Bpe, word: str, out: []str, scratch: []usize) -> (usize, err)
fn wordpiece(word: str, vocabulary: []const str, out: []str) -> (usize, err)
fn unigram(word: str, vocabulary: []const str, log_probability: []const f64, out: []str, scores: []f64, scratch: []usize) -> (usize, err)
fn collect(word: str, from: []const usize, n: usize, out: []str) -> usize
fn unigram_sample(word: str, vocabulary: []const str, log_probability: []const f64, temperature: f64, r: *rand.Pcg64, out: []str, scores: []f64, scratch: []usize) -> (usize, err)
fn log_add(a: f64, b: f64) -> f64
```

`shingles` and `word_shingles` cut windows; `word_break` segments into dictionary
words, fewest first; `bpe_train` learns byte-pair merges in the arena (most frequent
pair, earliest seen on ties) and `bpe_encode` applies them; `wordpiece` is greedy
longest-match-first over `##` continuation pieces; `unigram` is the Viterbi
segmentation over log probabilities and `unigram_sample` draws one by forward
filtering and backward sampling under a temperature.

### `e.text.hyphen`

```neper
error Invalid
error TooSmall
error TooLong
const MAX_WORD: usize = 64usize

fn english() -> str
fn fold(c: u8) -> u8
fn is_digit(c: u8) -> bool
fn token(s: str, at: usize) -> (usize, usize, usize)
fn exception_matches(e: str, w: []const u8) -> bool
fn break_points(patterns: str, exceptions: str, word: str, left_min: usize, right_min: usize, out: []usize) -> (usize, err)
fn hyphenate(patterns: str, exceptions: str, word: str, left_min: usize, right_min: usize, hyphen: u8, out: []u8) -> (usize, err)
```

Liang's algorithm: `break_points` over space-separated TeX patterns with an exceptions
list and left/right minimums, `hyphenate`, and `english` (the pattern subset that
hyphenates the fixture words as the full hyph_en_US dictionary does).

### `e.text.collab`

```neper
type Kind = enum u8 { Insert, Delete }
type Op = struct { kind: Kind, pos: usize, len: usize, text: str }
type Id = struct { site: u32, counter: u32 }
type CrdtOp = struct { insert: bool, after: Id, id: Id, byte: u8 }
type Doc = struct { site: []u32, counter: []u32, byte: []u8, dead: []u8, link: []u32, used: usize }
error TooSmall
error Invalid

fn digits() -> str
fn insert(pos: usize, text: str) -> Op
fn delete(pos: usize, len: usize) -> Op
fn shift(x: usize, lo: usize, hi: usize) -> usize
fn transform(a: Op, b: Op, a_wins: bool) -> Op
fn apply(text: []const u8, op: Op, out: []u8) -> (usize, err)
fn doc(site: []u32, counter: []u32, byte: []u8, dead: []u8, link: []u32) -> Doc
fn id_less(a: Id, b: Id) -> bool
fn crdt_find(d: *const Doc, id: Id) -> usize
fn crdt_insert(d: *Doc, after: Id, id: Id, byte: u8) -> err
fn crdt_delete(d: *Doc, id: Id) -> err
fn crdt_apply(d: *Doc, op: CrdtOp) -> err
fn crdt_text(d: *const Doc, out: []u8) -> (usize, err)
fn crdt_len(d: *const Doc) -> usize
fn crdt_id_at(d: *const Doc, index: usize) -> (Id, err)
fn digit_value(b: u8) -> (usize, bool)
fn valid_key(k: str) -> bool
fn tail(k: str, from: usize) -> str
fn between(a: str, b: str, out: []u8) -> (usize, err)
fn order_key_between(a: str, b: str, out: []u8) -> (usize, err)
```

Operational transformation of insert/delete ops (`transform`, `apply`), an RGA text
CRDT over parallel arrays with tombstones (`crdt_insert/delete/apply/text/find`) and
fractional indexing (`order_key_between`, base 62).

### `e.text.unicode`

```neper
type Category = enum u8 { Lu, Ll, Lt, Lm, Lo, Mn, Mc, Me, Nd, Nl, No, Pc, Pd, Ps, Pe, Pi, Pf, Po, Sm, Sc, Sk, So, Zs, Zl, Zp, Cc, Cf, Cs, Co, Cn }
type Graphemes = struct { text: str, off: usize }

fn category(scalar: u32) -> Category
fn combining_class(scalar: u32) -> u8
fn is_whitespace(scalar: u32) -> bool
fn is_alphabetic(scalar: u32) -> bool
fn is_numeric(scalar: u32) -> bool
fn to_lower_simple(scalar: u32) -> u32
fn to_upper_simple(scalar: u32) -> u32
fn casefold(a: *mem.Arena, s: str) -> (str, err)
fn graphemes(s: str) -> Graphemes
fn graphemes_next(it: *Graphemes) -> (str, bool)
```

### `e.text.normalize`

```neper
type Form = enum u8 { Nfc, Nfd, Nfkc, Nfkd }
error Invalid

fn is_normalized(s: str, form: Form) -> (bool, err)
fn normalize(a: *mem.Arena, s: str, form: Form) -> (str, err)
```

### `e.text.collate`

```neper
type Options = struct { case_sensitive: bool, numeric: bool }

fn codepoint_cmp(a: str, b: str) -> i32
fn natural_cmp(a: str, b: str, options: Options) -> i32
```

Locale-aware collation is exposed by `e.text.locale`; this module remains the
locale-independent Unicode collation mechanism beneath it. The delivered natural
comparison recognizes ASCII decimal runs, compares their magnitude without fixed-width
conversion, and applies ASCII case folding when case sensitivity is disabled. Full
locale and multi-scalar case folding remain owned by `e.text.locale`.

### `e.text.locale`

```neper
type Database = struct { state: *void }
type Locale = struct { state: *const void }
type NumberOptions = struct { minimum_fraction: u8, maximum_fraction: u8, grouping: bool, sign_always: bool }
type CurrencyOptions = struct { code: str, accounting: bool }
type DateStyle = enum u8 { Short, Medium, Long, Full }
error InvalidData
error NotFound
error Invalid

fn load(a: *mem.Arena, source: []const u8) -> (Database, err)
fn builtin(a: *mem.Arena) -> (Database, err)
fn version(db: *const Database) -> str
fn locale(db: *const Database, tag: str) -> (Locale, err)
fn canonical_tag(a: *mem.Arena, tag: str) -> (str, err)
fn format_i64(a: *mem.Arena, selected_locale: Locale, value: i64, options: NumberOptions) -> (str, err)
fn format_f64(a: *mem.Arena, selected_locale: Locale, value: f64, options: NumberOptions) -> (str, err)
fn parse_f64(selected_locale: Locale, value: str) -> (f64, err)
fn format_currency(a: *mem.Arena, selected_locale: Locale, value: decimal.Decimal, options: CurrencyOptions) -> (str, err)
fn format_date(a: *mem.Arena, selected_locale: Locale, value: calendar.DateTime, style: DateStyle) -> (str, err)
fn compare(selected_locale: Locale, a: str, b: str) -> i32
fn lower(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err)
fn upper(a: *mem.Arena, selected_locale: Locale, value: str) -> (str, err)
```

`builtin` uses the CLDR release pinned to the toolchain and reported by `version`;
`load` accepts explicit compatible data. Parsing consumes the whole input. Currency
codes are caller-supplied ISO 4217 identifiers. No process-global locale exists.

### `e.text.template`

```neper
type Template = struct { state: *void }
type Options = struct { max_bytes: usize, max_nodes: usize, max_depth: u16 }
type Value = union enum u8 { Null, Bool: bool, I64: i64, U64: u64, F64: f64, Text: str, Bytes: []const u8 }
type Binding = struct { name: str, value: Value }
error InvalidTemplate
error MissingValue
error TooDeep
error TooLarge

fn parse(a: *mem.Arena, source: str, options: Options) -> (Template, err)
fn execute(template: *const Template, writer: *io.Writer, bindings: []const Binding) -> err
fn validate[T: type](template: *const Template) -> err
fn execute_typed[T: type](template: *const Template, writer: *io.Writer, value: *const T) -> err
```

Templates provide deterministic interpolation, conditionals and bounded iteration
over explicit values or compile-time-inspected structs. The core engine performs no
contextual escaping; specialized output modules such as `e.fmt.html.template` own it.

### `e.text.regex`

```neper
type Regex = struct { state: *void }
type Match = struct { start: usize, end: usize }
type Captures = struct { whole: Match, groups: []const Match }
type Options = struct { case_insensitive: bool, multiline: bool, dot_matches_newline: bool }
error InvalidPattern
error TooComplex

fn compile(a: *mem.Arena, pattern: str, options: Options) -> (Regex, err)
fn is_match(r: *const Regex, text: str) -> bool
fn find(r: *const Regex, text: str, from: usize) -> (Match, bool)
fn captures(a: *mem.Arena, r: *const Regex, text: str, from: usize) -> (Captures, bool, err)
fn replace_all(a: *mem.Arena, r: *const Regex, text: str, replacement: str) -> (str, err)
```

The accepted syntax is regular only: no backreferences, recursion or lookbehind.

### `e.gfx.geometry`

```neper
type Point = struct { x: f32, y: f32 }
type Size = struct { width: f32, height: f32 }
type Rect = struct { x: f32, y: f32, width: f32, height: f32 }
type Insets = struct { left: f32, top: f32, right: f32, bottom: f32 }
type Radius = struct { x: f32, y: f32 }
type RRect = struct { rect: Rect, top_left: Radius, top_right: Radius, bottom_right: Radius, bottom_left: Radius }
type Transform = struct { m00: f32, m01: f32, m02: f32, m10: f32, m11: f32, m12: f32 }
type PathVerb = enum u8 { Move, Line, Quad, Cubic, Close }
type Path = struct { verbs: []const PathVerb, points: []const Point }
type PathBuilder = struct { state: *void }
error Invalid
error TooLarge

fn rect(x: f32, y: f32, width: f32, height: f32) -> Rect
fn contains(r: Rect, p: Point) -> bool
fn intersect(a: Rect, b: Rect) -> Rect
fn union_rect(a: Rect, b: Rect) -> Rect
fn transform_identity() -> Transform
fn transform_translate(x: f32, y: f32) -> Transform
fn transform_scale(x: f32, y: f32) -> Transform
fn transform_rotate(radians: f32) -> Transform
fn transform_multiply(a: Transform, b: Transform) -> Transform
fn transform_point(t: Transform, p: Point) -> Point
fn path_builder(a: *mem.Arena, max_verbs: usize, max_points: usize) -> (PathBuilder, err)
fn move_to(b: *PathBuilder, p: Point) -> err
fn line_to(b: *PathBuilder, p: Point) -> err
fn quad_to(b: *PathBuilder, control: Point, end: Point) -> err
fn cubic_to(b: *PathBuilder, first: Point, second: Point, end: Point) -> err
fn close_path(b: *PathBuilder) -> err
fn finish(b: *PathBuilder) -> Path
```

Coordinates are logical pixels. Values must be finite; rectangles and sizes have
non-negative dimensions. Paths and transforms allocate nothing after builder
creation and are independent of any rendering backend.

### `e.gfx.paint`

```neper
type Color = struct { red: f32, green: f32, blue: f32, alpha: f32 }
type Blend = enum u8 { SourceOver, Source, DestinationOver, Multiply, Screen, Overlay, Darken, Lighten }
type StrokeCap = enum u8 { Butt, Round, Square }
type StrokeJoin = enum u8 { Miter, Round, Bevel }
type Stroke = struct { width: f32, cap: StrokeCap, join: StrokeJoin, miter_limit: f32 }
type Stop = struct { offset: f32, color: Color }
type Brush = union enum u8 { Solid: Color, Linear: LinearGradient, Radial: RadialGradient }
type LinearGradient = struct { start: geometry.Point, end: geometry.Point, stops: []const Stop }
type RadialGradient = struct { center: geometry.Point, radius: f32, stops: []const Stop }
error Invalid

fn rgba(red: f32, green: f32, blue: f32, alpha: f32) -> Color
fn srgb8(red: u8, green: u8, blue: u8, alpha: u8) -> Color
fn premultiply(color: Color) -> Color
fn validate(brush: *const Brush) -> err
```

Colors are linear-light floating-point RGBA; `srgb8` performs the defined sRGB
transfer. Gradient stops are borrowed, ordered and bounded to `0..1`.

### `e.gfx.image`

```neper
type Format = enum u8 { R8, Rgba8, Bgra8, Rgba16Float }
type Alpha = enum u8 { Opaque, Straight, Premultiplied }
type Info = struct { width: u32, height: u32, format: Format, alpha: Alpha, frames: u32 }
type Image = struct { pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
type ConstImage = struct { pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha }
error Invalid
error TooLarge

fn required_bytes(width: u32, height: u32, format: Format, stride: usize) -> (usize, err)
fn make(pixels: []u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (Image, err)
fn make_const(pixels: []const u8, width: u32, height: u32, stride: usize, format: Format, alpha: Alpha) -> (ConstImage, err)
fn allocate(a: *mem.Arena, width: u32, height: u32, format: Format, alpha: Alpha) -> (Image, err)
fn clear(image: Image, color: paint.Color)
fn copy(dst: Image, src: ConstImage, dst_origin: geometry.Point) -> err
```

Images are pixel views, not codecs or GPU resources. Encoders and decoders belong in
`e.fmt.*`; upload and caching belong in `e.gfx.scene`.

### `e.text.shape`

```neper
type FontId = u32
type Direction = enum u8 { LeftToRight, RightToLeft }
type Font = struct { id: FontId, data: []const u8, face_index: u32 }
type Feature = struct { tag: u32, value: u32, start: usize, end: usize }
type Glyph = struct { id: u32, cluster: usize, advance_x: f32, advance_y: f32, offset_x: f32, offset_y: f32 }
type Run = struct { font: FontId, direction: Direction, script: u32, language: str, glyphs: []const Glyph }
type Options = struct { direction: Direction, script: u32, language: str, features: []const Feature }
error InvalidFont
error InvalidText
error Unsupported
error TooLarge

fn validate_font(font: Font) -> err
fn shape(a: *mem.Arena, font: Font, source: str, options: Options) -> (Run, err)
```

Shaping is deterministic over caller-provided OpenType font bytes and the toolchain's
pinned Unicode tables. It performs substitutions and positioning but no line
breaking, font discovery, fallback, rasterization or hidden file access.

### `e.text.layout`

```neper
type Align = enum u8 { Start, End, Center, Justify }
type Wrap = enum u8 { None, Word, Character }
type FontChoice = struct { font: shape.Font, size: f32 }
type Style = struct { fonts: []const FontChoice, language: str, line_height: f32 }
type GlyphRun = struct { run: shape.Run, origin: geometry.Point, size: f32 }
type Line = struct { runs: []const GlyphRun, bounds: geometry.Rect, baseline: f32, start: usize, end: usize }
type Layout = struct { source: str, lines: []const Line, bounds: geometry.Rect }
type Options = struct { width: f32, max_lines: u32, align: Align, wrap: Wrap, ellipsis: str }
error MissingGlyph
error Invalid
error TooLarge

fn layout(a: *mem.Arena, source: str, style: Style, options: Options) -> (Layout, err)
fn hit_test(value: *const Layout, point: geometry.Point) -> usize
fn caret(value: *const Layout, byte_offset: usize) -> geometry.Rect
fn selection(a: *mem.Arena, value: *const Layout, start: usize, end: usize) -> ([]geometry.Rect, err)
```

The module performs Unicode bidi resolution, line breaking, fallback and visual
placement. Byte offsets always identify UTF-8 boundaries in `source`.

### `e.ui.style`

```neper
type Length = union enum u8 { Auto, Px: f32, Percent: f32, Flex: f32 }
type EdgeLengths = struct { left: Length, top: Length, right: Length, bottom: Length }
type Display = enum u8 { Flex, Grid, Stack, None }
type Position = enum u8 { Flow, Absolute }
type Overflow = enum u8 { Visible, Clip, Scroll }
type Border = struct { width: f32, color: paint.Color }
type Shadow = struct { offset: geometry.Point, color: paint.Color }
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow, border: Border, radius: f32, shadow: Shadow }
error Invalid

type ColorRole = enum u8 { Background, Surface, SurfaceVariant, Primary, OnPrimary, Secondary, OnSecondary, Text, TextMuted, Border, Focus, Error, OnError, Selection }
type TextRole = enum u8 { Body, BodySmall, Title, Heading, Label, Caption, Code }
type TextStyle = struct { size: f32, line_height: f32, weight: u16, italic: bool }
type Spacing = struct { xs: f32, sm: f32, md: f32, lg: f32, xl: f32 }
type Radii = struct { sm: f32, md: f32, lg: f32, full: f32 }
type Borders = struct { hairline: f32, regular: f32, thick: f32 }
type Motion = struct { fast_ms: u32, normal_ms: u32, slow_ms: u32, reduced: bool }
type Metrics = struct { hit_target: f32, control_height: f32, density: f32, focus_ring: f32, focus_offset: f32 }
type Palette = enum u8 { Light, Dark, HighContrast, Custom }
type Profile = enum u8 { Neper, DesktopDense, Touch, MaterialLike, CupertinoLike }
type Direction = enum u8 { LeftToRight, RightToLeft }
type ThemeTokens = struct { palette: Palette, profile: Profile, direction: Direction, colors: [14]paint.Color, text: [7]TextStyle, spacing: Spacing, radii: Radii, borders: Borders, elevation: [4]f32, motion: Motion, metrics: Metrics }
type ControlState = struct { hovered: bool, pressed: bool, focused: bool, selected: bool, disabled: bool, read_only: bool, invalid: bool }
type ControlVariant = enum u8 { Filled, Outlined, Plain }
type ResolvedControl = struct { background: paint.Color, foreground: paint.Color, border: paint.Color, border_width: f32, focus_ring: f32, opacity: f32, radius: f32 }
type SizeClass = enum u8 { Compact, Medium, Expanded }
type Capabilities = struct { hover: bool, fine_pointer: bool, keyboard: bool, touch: bool, pen: bool, resizable: bool, multi_window: bool, insets: geometry.Insets }
type Adaptation = struct { size: SizeClass, capabilities: Capabilities, profile: Profile }

fn defaults() -> Style
fn validate(value: *const Style) -> err
fn color(t: *const ThemeTokens, role: ColorRole) -> paint.Color
fn text_style(t: *const ThemeTokens, role: TextRole) -> TextStyle
fn reference(palette: Palette) -> ThemeTokens
fn validate_theme(t: *const ThemeTokens) -> err
fn resolve(t: *const ThemeTokens, variant: ControlVariant, state: ControlState) -> ResolvedControl
fn size_class(width: f32) -> SizeClass
fn adapt(t: *const ThemeTokens, a: Adaptation) -> ThemeTokens
```

Styles are ordinary immutable values. There is no selector engine, cascading global
sheet or reflective property lookup in version 1.

A style's border, radius and shadow (D814) are painted by the widget runtime: the
shadow is the background's shape filled in its colour at its offset under everything,
the background and a clip are rounded by the radius, and the border is stroked inside
the bounds on the rounded shape.

Theme tokens (D805, widget plan P0-01) are values too: `reference` makes the Neper
profile in a palette, `resolve` a control's look under its state, `adapt` a theme for
a size class, a host's capabilities and a presentation profile, and `validate_theme`
the guard. A component resolves its look during build from the tokens it is handed;
nothing is looked up by name.

### `e.ui.layout`

```neper
type Axis = enum u8 { Horizontal, Vertical }
type MainAlign = enum u8 { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }
type CrossAlign = enum u8 { Start, End, Center, Stretch, Baseline }
type Constraints = struct { min_width: f32, max_width: f32, min_height: f32, max_height: f32 }
type Flex = struct { axis: Axis, main: MainAlign, cross: CrossAlign, gap: f32 }
type GridTrack = union enum u8 { Px: f32, Flex: f32, Auto }
type Grid = struct { columns: []const GridTrack, rows: []const GridTrack, column_gap: f32, row_gap: f32 }
type Wrap = struct { axis: Axis, main_gap: f32, cross_gap: f32 }
type Child = struct { desired: geometry.Size, flex: f32 }
type Result = struct { size: geometry.Size, children: []const geometry.Rect }
error Invalid
error Overflow

fn constrain(value: geometry.Size, limits: Constraints) -> geometry.Size
fn flex(a: *mem.Arena, spec: Flex, limits: Constraints, children: []const Child) -> (Result, err)
fn wrap(a: *mem.Arena, spec: Wrap, limits: Constraints, children: []const Child) -> (Result, err)
fn grid(a: *mem.Arena, spec: Grid, limits: Constraints, children: []const Child) -> (Result, err)
```

Layout is a deterministic pure constraint solver. Scroll state, widget measurement
and render-tree traversal remain in `e.ui.widget`.

### `e.crypto.hash`

```neper
type Sha256 = struct { h: [8]u32, block: [64]u8, block_len: u8, total: u64 }
type Sha512 = struct { h: [8]u64, block: [128]u8, block_len: u8, total_hi: u64, total_lo: u64 }
type Sha3_256 = struct { lanes: [25]u64, block: [136]u8, block_len: u8 }
type Sha3_512 = struct { lanes: [25]u64, block: [72]u8, block_len: u8 }

fn sha256(data: []const u8) -> [32]u8
fn sha512(data: []const u8) -> [64]u8
fn sha3_256(data: []const u8) -> [32]u8
fn sha3_512(data: []const u8) -> [64]u8
fn sha256_init() -> Sha256
fn sha256_update(h: *Sha256, data: []const u8)
fn sha256_done(h: *Sha256) -> [32]u8
fn sha512_init() -> Sha512
fn sha512_update(h: *Sha512, data: []const u8)
fn sha512_done(h: *Sha512) -> [64]u8
fn sha3_256_init() -> Sha3_256
fn sha3_256_update(h: *Sha3_256, data: []const u8)
fn sha3_256_done(h: *Sha3_256) -> [32]u8
fn sha3_512_init() -> Sha3_512
fn sha3_512_update(h: *Sha3_512, data: []const u8)
fn sha3_512_done(h: *Sha3_512) -> [64]u8
fn legacy_sha1(data: []const u8) -> [20]u8
fn legacy_md5(data: []const u8) -> [16]u8
fn equal_constant_time(a: []const u8, b: []const u8) -> bool
```

### `e.crypto.mac`

```neper
type HmacSha256 = struct { inner: hash.Sha256, outer: hash.Sha256 }
type HmacSha512 = struct { inner: hash.Sha512, outer: hash.Sha512 }

fn hmac_sha256(key: []const u8, message: []const u8) -> [32]u8
fn hmac_sha512(key: []const u8, message: []const u8) -> [64]u8
fn verify_sha256(key: []const u8, message: []const u8, tag: [32]u8) -> bool
fn verify_sha512(key: []const u8, message: []const u8, tag: [64]u8) -> bool
fn sha256_init(key: []const u8) -> HmacSha256
fn sha256_update(state: *HmacSha256, bytes: []const u8)
fn sha256_done(state: *HmacSha256) -> [32]u8
fn sha512_init(key: []const u8) -> HmacSha512
fn sha512_update(state: *HmacSha512, bytes: []const u8)
fn sha512_done(state: *HmacSha512) -> [64]u8
```

HMAC follows RFC 2104; verification compares fixed-length tags in constant time.
Inputs are borrowed only for the call; bounded internal stack state is declared.
No key generation, entropy read, truncation or secret logging is implicit.
Streaming state lets HKDF process multiple input segments without concatenating
unbounded caller data. done consumes the message state; reinitialize before reuse.

### `e.crypto.kdf`

```neper
error TooLarge

fn hkdf_sha256_extract(salt: []const u8, input_key: []const u8) -> [32]u8
fn hkdf_sha256_expand(dst: []u8, prk: [32]u8, info: []const u8) -> err
fn hkdf_sha512_extract(salt: []const u8, input_key: []const u8) -> [64]u8
fn hkdf_sha512_expand(dst: []u8, prk: [64]u8, info: []const u8) -> err
```

HKDF follows RFC 5869. Expand rejects output longer than 255 hash blocks before
writing dst; salt omission has the RFC-defined zero-salt behavior. Output aliases
with key/info inputs are forbidden unless separately proven safe. HKDF is not a
password-storage KDF; no password-hashing security claim or custom construction is
introduced. Release requires published independent vectors and boundary tests.

### `e.crypto.aead`

```neper
error InvalidKey
error InvalidNonce
error TooSmall
error Authentication

fn aes128_gcm_seal(dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err)
fn aes128_gcm_open(dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err)
fn aes256_gcm_seal(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err)
fn aes256_gcm_open(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err)
fn chacha20_poly1305_seal(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err)
fn chacha20_poly1305_open(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err)
```

The sealed representation is ciphertext followed by the 16-byte authentication tag.

### `e.crypto.sign`

```neper
type Ed25519PublicKey = struct { bytes: [32]u8 }
type Ed25519SecretKey = struct { bytes: [32]u8 }
type Ed25519Signature = struct { bytes: [64]u8 }
type P256PublicKey = struct { bytes: [65]u8 }
error InvalidKey
error InvalidSignature

fn ed25519_public_from_secret(secret: Ed25519SecretKey) -> (Ed25519PublicKey, err)
fn ed25519_sign(secret: Ed25519SecretKey, message: []const u8) -> (Ed25519Signature, err)
fn ed25519_verify(public: Ed25519PublicKey, message: []const u8, signature: Ed25519Signature) -> bool
fn p256_verify(public: P256PublicKey, message: []const u8, signature_der: []const u8) -> bool
```

`Ed25519SecretKey.bytes` is the 32-byte seed form. Verification rejects non-canonical
encodings and small-order public keys. `P256PublicKey` is the uncompressed SEC1 point;
P-256 verification hashes with SHA-256 and accepts strict DER ECDSA signatures.

### `e.crypto.kx`

```neper
type X25519PublicKey = struct { bytes: [32]u8 }
type X25519SecretKey = struct { bytes: [32]u8 }
type X25519SharedKey = struct { bytes: [32]u8 }
error InvalidKey

fn x25519_public_from_secret(secret: X25519SecretKey) -> X25519PublicKey
fn x25519_exchange(secret: X25519SecretKey, peer: X25519PublicKey) -> (X25519SharedKey, err)
```

The scalar is clamped by the operation. An all-zero shared secret is `InvalidKey`.

### `e.crypto.random`

```neper
type ChaCha20 = struct { key: [32]u8, nonce: [12]u8, counter: u32, block: [64]u8, used: u8 }
error Exhausted

fn chacha20_init(key: [32]u8, nonce: [12]u8, counter: u32) -> ChaCha20
fn chacha20_fill(r: *ChaCha20, dst: []u8) -> err
fn chacha20_next_u64(r: *ChaCha20) -> (u64, err)
fn chacha20_bounded(r: *ChaCha20, upper: u64) -> (u64, err)
```

The counter never wraps; a request that would do so returns `Exhausted` before
reusing a block. `chacha20_bounded(..., 0)` returns zero and otherwise uses rejection
sampling.

### `e.crypto.x509`

```neper
type PublicKey = union enum u8 { Ed25519: sign.Ed25519PublicKey, P256: sign.P256PublicKey, Unsupported: []const u8 }
type Certificate = struct { der: []const u8, subject: str, issuer: str, dns_names: []const str, not_before: time.Instant, not_after: time.Instant, public_key: PublicKey, is_ca: bool }
type Pool = struct { certificates: []const Certificate }
type VerifyOptions = struct { roots: Pool, intermediates: Pool, dns_name: str, now: time.Instant, usage: KeyUsage, max_depth: u16 }
type KeyUsage = enum u8 { ServerAuth, ClientAuth, CodeSigning, EmailProtection, Any }
type Chain = struct { certificates: []const Certificate }
error InvalidCertificate
error UnknownAuthority
error Expired
error NameMismatch
error InvalidUsage
error TooDeep

fn parse(a: *mem.Arena, der: []const u8) -> (Certificate, err)
fn parse_pem(a: *mem.Arena, source: str) -> ([]const Certificate, err)
fn pool(a: *mem.Arena, certificates: []const Certificate) -> Pool
fn verify(a: *mem.Arena, leaf: Certificate, options: VerifyOptions) -> (Chain, err)
fn verify_signature(certificate: Certificate, issuer: Certificate) -> err
```

Parsing and verification use the DER and PEM modules and the algorithm set pinned to
the toolchain. Verification receives roots and time explicitly; it never consults a
host trust store, clock or network revocation service implicitly. The delivered set
verifies Ed25519 and uncompressed P-256 keys with Ed25519 or ECDSA/SHA-256 signatures;
unsupported chain suffixes parse but cannot authenticate a link.

---

## 5. Platform and host services

### `e.os`

```neper
type File = struct { raw: usize }
type Proc = struct { raw: usize }
type ProcUsage = struct { exit_code: i32, peak_memory: usize }
type Thread = struct { raw: usize }
type Lib = resource(dlclose) struct { raw: usize }
type Handle = struct { raw: usize }
type Socket = resource(socket_close) struct { raw: usize }
type Poller = resource(poller_close) struct { state: *void }
type Mapping = resource(mapping_close) struct { raw: usize, address: *u8, len: usize }
type Watch = resource(watch_close) struct { state: *void }
type WatchAction = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type WatchEvent = struct { action: WatchAction, path: str, old_path: str }
type Clock = enum u8 { Wall, Monotonic }
type SeekWhence = enum u8 { Start, Current, End }
type EntryKind = enum u8 { File, Dir, Symlink, Other }
type DirEntry = struct { name: str, kind: EntryKind }
type FileInfo = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, mode: u32, file_id: u64, link_count: u64 }
type OpenFlags = struct { read: bool, write: bool, create: bool, truncate: bool, append: bool }
type Stdio = struct { stdin: File, stdout: File, stderr: File, inherit: []const Handle }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }
type ErrorKind = enum u8 { NotFound, Denied, Exists, Interrupted, OutOfMemory, Timeout, WouldBlock, Unsupported, Invalid, Other }
type ErrorDetail = struct { kind: ErrorKind, native_code: i32, operation: str, subject: str }
type Window = struct { raw: usize }
type WindowOptions = struct { title: str, width: u32, height: u32, resizable: bool, visible: bool }
type WindowMetrics = struct { width: u32, height: u32, scale_percent: u32, focused: bool, visible: bool }
type WindowEventKind = enum u8 { Close, Resize, Focus, Blur, PointerMove, PointerDown, PointerUp, Scroll, KeyDown, KeyUp, Text, Paint }
type WindowEvent = struct { kind: WindowEventKind, window: Window, x: i32, y: i32, width: u32, height: u32, button: u8, key: u32, modifiers: u8, delta: i32, codepoint: u32, repeat: bool }
type CursorShape = enum u8 { Arrow, Text, Hand, Crosshair, ResizeHorizontal, ResizeVertical, Hidden }
type MonitorInfo = struct { x: i32, y: i32, width: u32, height: u32, scale_percent: u32, primary: bool }
type AccessibleNode = struct { id: u32, parent: u32, has_parent: bool, role: u8, label: str, value: str, hint: str, flags: u8, actions: u8, x: f32, y: f32, width: f32, height: f32 }
error NotFound
error Denied
error Exists
error Interrupted
error OutOfMemory
error Failed
error Timeout
error WouldBlock
error Unsupported

fn open(a: *mem.Arena, path: str, flags: OpenFlags) -> (File, err)
fn create_new(a: *mem.Arena, path: str) -> (File, err)
fn read(f: File, buf: []u8) -> (usize, err)
fn write(f: File, buf: []const u8) -> (usize, err)
fn read_detail(f: File, buf: []u8, detail: *ErrorDetail) -> (usize, err)
fn write_detail(f: File, buf: []const u8, detail: *ErrorDetail) -> (usize, err)
fn seek(f: File, off: i64, whence: SeekWhence) -> (u64, err)
fn copy_bytes(dst: []u8, src: []const u8)
fn touch(p: *const u8, n: usize)
fn sha256_blocks(state: []usize, bytes: []const u8) -> usize
fn crc32c_bytes(crc: []usize, bytes: []const u8) -> usize
fn close(f: own File) -> err
fn stdin() -> File
fn stdout() -> File
fn stderr() -> File
fn readdir(a: *mem.Arena, path: str) -> ([]DirEntry, err)
fn stat(a: *mem.Arena, path: str) -> (FileInfo, err)
fn lstat(a: *mem.Arena, path: str) -> (FileInfo, err)
fn mkdir(a: *mem.Arena, path: str) -> err
fn remove_file(a: *mem.Arena, path: str) -> err
fn remove_dir(a: *mem.Arena, path: str) -> err
fn rename(a: *mem.Arena, src: str, dst: str) -> err
fn replace(a: *mem.Arena, src: str, dst: str, overwrite: bool, durable: bool) -> err
fn read_link(a: *mem.Arena, path: str) -> (str, err)
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err
fn current_dir(a: *mem.Arena) -> (str, err)
fn set_current_dir(a: *mem.Arena, path: str) -> err
fn executable_path(a: *mem.Arena) -> (str, err)
fn canonical(a: *mem.Arena, path: str) -> (str, err)
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err
fn pipe() -> (File, File, err)
fn pipe_read(f: File, buf: []u8) -> (usize, err)
fn dup(f: File) -> (File, err)
fn spawn(a: *mem.Arena, argv: []const str, stdio: Stdio) -> (Proc, err)
fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err)
fn wait(p: own Proc) -> (i32, err)
fn wait_usage(p: own Proc) -> (ProcUsage, err)
fn kill(p: Proc) -> err
fn exit(code: i32)
fn args(a: *mem.Arena) -> ([]str, err)
fn env(a: *mem.Arena, name: str) -> (str, err)
fn random(buf: []u8) -> err
fn page_size() -> usize
fn reserve(n: usize) -> (*u8, err)
fn commit(p: *u8, n: usize) -> err
fn release(p: *u8, n: usize) -> err
fn clock(c: Clock) -> (i64, err)
fn peak_memory() -> (usize, err)
fn thread_create[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err)
fn thread_join(t: own Thread) -> err
fn thread_detach(t: own Thread) -> err
fn wait_u32(p: *Atomic[u32], expected: u32, timeout_ns: i64) -> err
fn wake_one_u32(p: *Atomic[u32])
fn wake_all_u32(p: *Atomic[u32])
fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err)
fn socket_set_nonblocking(s: Socket, enabled: bool) -> err
fn socket_bind(s: Socket, address: SocketAddress) -> err
fn socket_local_address(s: Socket) -> (SocketAddress, err)
fn socket_listen(s: Socket, backlog: u32) -> err
fn socket_accept(s: Socket) -> (Socket, SocketAddress, err)
fn socket_connect(s: Socket, address: SocketAddress) -> err
fn socket_receive(s: Socket, dst: []u8) -> (usize, err)
fn socket_send(s: Socket, src: []const u8) -> (usize, err)
fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err)
fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err)
fn socket_shutdown(s: Socket, how: SocketShutdown) -> err
fn socket_close(s: own Socket) -> err
fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err)
fn file_handle(f: File) -> Handle
fn socket_handle(s: Socket) -> Handle
fn poller_open(a: *mem.Arena) -> (Poller, err)
fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err
fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err
fn poller_unregister(p: Poller, handle: Handle) -> err
fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err)
fn poller_wake(p: Poller) -> err
fn poller_close(p: own Poller) -> err
fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err)
fn mapping_bytes(m: Mapping) -> []const u8
fn mapping_bytes_mut(m: Mapping) -> ([]u8, err)
fn mapping_flush(m: Mapping) -> err
fn mapping_close(m: own Mapping) -> err
fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err)
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err)
fn watch_close(w: own Watch) -> err
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err)
fn dlsym[F: type](a: *mem.Arena, l: Lib, sym: str) -> (F, err)
fn dlclose(l: own Lib) -> err
fn last_error_detail(operation: str, subject: str) -> ErrorDetail
fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err)
fn window_open(a: *mem.Arena, options: WindowOptions) -> (Window, err)
fn window_close(w: Window) -> err
fn window_poll(timeout_ns: i64) -> (WindowEvent, bool, err)
fn window_metrics(w: Window) -> (WindowMetrics, err)
fn window_title(w: Window, value: str) -> err
fn window_visible(w: Window, value: bool) -> err
fn window_cursor(w: Window, shape: CursorShape) -> err
fn window_capture(w: Window, on: bool) -> err
fn window_present(w: Window, pixels: []const u32, width: u32, height: u32) -> err
fn window_native(w: Window) -> (usize, usize, err)
fn monitors(a: *mem.Arena, limit: usize) -> ([]const MonitorInfo, err)
fn clipboard_text(a: *mem.Arena) -> (str, err)
fn set_clipboard_text(value: str) -> err
fn accessibility_publish(w: Window, nodes: []const AccessibleNode) -> err
fn stat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err)
fn dir_open_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (Dir, err)
fn open_detail(a: *mem.Arena, path: str, flags: OpenFlags, detail: *ErrorDetail) -> (File, err)
fn lstat_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (FileInfo, err)
fn mkdir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err
fn remove_file_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err
fn remove_dir_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> err
fn rename_detail(a: *mem.Arena, src: str, dst: str, detail: *ErrorDetail) -> err
fn create_new_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (File, err)
fn read_link_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err)
fn canonical_detail(a: *mem.Arena, path: str, detail: *ErrorDetail) -> (str, err)
type Dir = resource(dir_close) struct { raw: usize }
type FileLock = resource(file_unlock) struct { raw: usize }
type ProcGroup = resource(proc_group_close) struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

fn dir_open(a: *mem.Arena, path: str) -> (Dir, err)
fn dir_close(dir: own Dir) -> err
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err)
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err
fn rename_at(a: *mem.Arena, src_dir: Dir, src_path: str, dst_dir: Dir, dst_path: str, overwrite: bool, durable: bool) -> err
fn file_lock(file: File, exclusive: bool, timeout_ns: i64) -> (FileLock, err)
fn file_unlock(lock: own FileLock) -> err
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err)
fn proc_group_terminate(group: ProcGroup, force: bool) -> err
fn proc_group_close(group: own ProcGroup) -> err

```

`replace` is `rename` with the two questions a caller actually has: whether an existing
destination is replaced or the call fails with `Exists`, and whether the result is on the
disk before it returns. It is atomic within one filesystem and refuses to cross one, so a
move between devices is `Unsupported` rather than a copy nothing asked for.

`create_new` creates a file that was not there and fails with `Exists` if it was, opened
for reading and writing with no sharing. It is the one call that makes a name safe to hand
out, since the name is taken before it is returned; `OpenFlags` has no exclusive form
because that has to be one operation, not a check and then an open.

`canonical` is absolute with every symbolic link, `.` and `..` resolved, and it requires
the path to exist: both hosts answer it by opening the path and asking what was opened, so
there is nothing to resolve for a name that leads nowhere.

`executable_path` is absolute and names the running image. It is what the host records,
which is not the same thing on both: Linux answers with symbolic links already resolved
and Windows with the path the process was started from.

`current_dir` is absolute and in the host convention. It and `set_current_dir` are the
one pair here that reads and writes state belonging to the whole process rather than to a
path, so a caller that moves is the one that has to move back.

`read_link` gives back the target string as it was stored, resolving nothing; a path that
is not a link is `Unsupported`. `symlink` stores that string, and a host that records at
creation whether a link names a directory decides that from the target as the link will
see it. Creating one is privileged on some hosts and is `Denied` there.

`peak_memory` is the most memory this process has had resident at once, in bytes, and
`wait_usage` is `wait` that also answers that for the child: the peak is only readable
while the child is still known to the host, which on both is inside the wait, so it
cannot be a separate call after one. Each host rounds it its own way (pages on one,
kilobytes on the other) and one counts resident pages lazily, so a process that touched
only a few may read as zero: it is a measurement and not a number to compare exactly.

`set_mode` takes the same `mode` `stat` reports, and `set_times` the same nanoseconds:
a negative one leaves that stamp as it is, which is the `-1` that means "not recorded" on
the way out. A host that keeps no permission bits honours the write bit and nothing else,
and a filesystem that enforces no modes at all may honour none of it while still
succeeding — reading back is the only way to know.

`FileInfo.mode` is the POSIX permission bits; a host without them synthesises the
portable read-only/executable subset and answers the same for owner, group and other
rather than a narrower split nothing enforces. `FileInfo.file_id` is unique within its
volume or device, so two paths naming one object compare equal. Timestamps are
Unix-epoch nanoseconds and an unavailable one is `-1`, never zero — Linux keeps no
creation time in the structure `stat` reads, so `created_ns` is `-1` there.

All path strings use the host convention. `SpawnOptions.cwd == ""` inherits the
current directory; `inherit_env` controls whether `env` overlays the parent
environment (`true`) or is the complete child environment (`false`). Environment
entries are `NAME=VALUE`, and an entry whose name an inherited record also sets replaces
it rather than joining it. A `Stdio` stream left zero is the parent's own, so a caller that
only wants the child's output redirected sets that one field. `Stdio.inherit` names handles
the child must receive; neither host confines it to that set -- Linux passes every
descriptor without close-on-exec and Windows every inheritable handle. `wait_u32` waits
indefinitely when `timeout_ns < 0` and polls once when it is zero. In `SocketAddress`, IPv4 uses the first four bytes and
zeros the remaining twelve. Binding to port zero asks the host to choose one, and
`socket_local_address` is the only way the choice comes back -- so a server that does not
want to guess a free port needs it, and so does anything that has to tell a peer where to
reach it. `socket_resolve` answers with the caller's port rather than looking a service name
up, and a name that exists with no address of the family asked for is `NotFound` -- there is
nothing there to connect to either way. What it consults differs by host and cannot be made to
agree: Windows hands the name to its own resolver, which is a literal, the hosts file, the cache,
DNS and whatever else that host is configured to consult; Linux has no resolver to hand it to, so
it is a literal, `/etc/hosts`, then plain UDP DNS to the servers in `/etc/resolv.conf`. Two
consequences are worth naming rather than discovering: an unqualified name that a search-suffix
list would complete resolves on Windows and not on Linux, and an IPv6 literal with a zone suffix
(`fe80::1%3`) is accepted on Windows and not on Linux. Pollers retain handles, interests and numeric tokens,
never callbacks; callers unregister a handle before closing it. A poller holds its
registrations in the arena `poller_open` is given, which is why it carries a pointer where
every other resource here carries a handle: what it retains is a set, and no host offers a
single handle that is one. Only handles the host can report readiness for may be registered
— sockets everywhere, and pipes where the host has them; a handle it cannot poll comes back
as a failed event rather than being ignored.
`pipe_read` is the cross-host zero-time pipe probe: it returns `WouldBlock` while a writer
exists but no byte is ready, zero on EOF, and otherwise reads only bytes already available.
It is what lets process supervision bound its final drain on Windows, whose poller accepts
sockets but not anonymous pipe handles.

Every failing `e.os` call records the native code and portable classification in
thread-local runtime state. `last_error_detail` copies that state into an explicit
value and marks it read; a failing cleanup (`dir_close`, `socket_close`,
`mapping_close`, `watch_close`, `poller_close`, `dlclose`, `proc_group_close`,
`file_unlock`, `wait_usage`) records over it only once it has been read (D360), so
the detail an acquire-fail-close path leaves is the acquisition's. It must be called
before another failing non-cleanup `e.os` operation on that thread. The `_detail`
forms (D417, D443) remove that order: `stat_detail`, `dir_open_detail`, `open_detail`,
`lstat_detail`, `mkdir_detail`, `remove_file_detail`, `remove_dir_detail`,
`rename_detail`, `create_new_detail`, `read_link_detail` and `canonical_detail`
take the caller's `*ErrorDetail` and write the failure into it at the failing
call, before any cleanup or later failure on the thread, and leave it untouched on
success; the caller then holds the detail as ordinary data. Higher-level APIs may
expose a detail snapshot while ordinary callers retain cheap `err`/`try`.
`read_detail` and `write_detail` are the checked byte-I/O path (D614). They copy
the host failure directly into the caller's value rather than recovering it from
the compatibility slot, so overlapping calls do not compete for diagnostic state.
Their count has the same exact partial-progress meaning as `read` and `write`;
success leaves `detail` unchanged. A file handle retains no path label, so these
two operations use an empty `subject`.
`operation` and `subject` are borrowed caller strings, never inferred global state;
`error_message` is the only locale-dependent rendering operation in `e.os`. A `Watch` carries a
pointer for the same reason a `Poller` does: the host reports a change by a name relative to
what is being watched, so the watch has to remember the path to give `WatchEvent` one, and
that lives in the arena `watch_open` is given. A watch needs a filesystem that
reports changes, and one that does not is **not** an error a caller can see: opening the watch
succeeds and the read simply never returns. A network or translation layer — a 9p or DrvFS
mount among them — is the case, so a caller that may be pointed at arbitrary paths should not
assume a watch will ever fire. `recursive` is not yet honoured on either
host and asks for `Unsupported`: one of them takes it as a parameter and the other needs a
watch per directory and a table mapping each back to its path, so honouring it on one alone
would make a program that works there fail on the other.


These new primitives are the reviewed platform boundary for SL05/SL06, not permission
for e.fs/e.proc to add externs. Directory-relative operations reject absolute paths,
parent traversal and embedded NULs with `Denied`, before the host is asked; NoSymlinks rejects every traversed link/reparse
point. Beneath permits only traversal provably confined under the opened root, or
returns Unsupported. No lexical-prefix or canonicalize-then-open safety claim.
remove_at/rename_at traverse without following symlinks; removing a final symlink
removes the link, not its target. Durable rename may succeed before persistence fails;
report that partial effect. File locks are cooperative unless the platform explicitly
guarantees more. Process groups promise supported descendant containment, not a
security sandbox; unsupported strict containment fails before spawning. SL05 names
platform delivery requirements and escape limitations.

### `e.os.shell`

```neper
type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool, notices: bool, notice_actions: bool, notice_remove: bool, clipboard_text: bool, clipboard_typed: bool, drop_target: bool, drag_source: bool, file_dialogs: bool, recent_documents: bool, associations: bool, startup: bool, single_instance: bool, hotkeys: bool, power_inhibit: bool, lifecycle_events: bool, restart: bool, printing: bool, print_dialogs: bool, permissions: bool, credentials: bool, screen_capture: bool, biometrics: bool, photo_picker: bool }
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open, NoticeSelect, NoticeDismiss }
type NoticePermission = enum u8 { Granted, Denied, Unavailable }
type ContentKind = enum u8 { Text, Files, Image, Bytes, Promise }
type Content = struct { kind: ContentKind, mime: str, text: str, paths: []const str, image: Icon, bytes: []const u8 }
type Drop = struct { x: i32, y: i32, items: []const Content }
type DragResult = enum u8 { Copied, Moved, Cancelled }
type DialogKind = enum u8 { Open, Save, Folder }
type FileFilter = struct { label: str, pattern: str }
type FileDialog = struct { kind: DialogKind, title: str, filters: []const FileFilter, multiple: bool, initial: str, default_extension: str, folder: str }
type ActivationKind = enum u8 { Launch, File, Url }
type Activation = struct { kind: ActivationKind, payload: str, args: []const str }
type Hotkey = struct { control: bool, alt: bool, shift: bool, super: bool, key: u32 }
type Permission = enum u8 { Granted, Denied, Unavailable }
type LifecycleEvent = enum u8 { Shutdown, Suspend, Resume }
type Printer = struct { device: usize, from_page: u32, to_page: u32, copies: u32 }
type PrintPage = struct { width: u32, height: u32, dpi_x: u32, dpi_y: u32 }
type PageSetup = struct { paper_width: u32, paper_height: u32, margin_left: u32, margin_top: u32, margin_right: u32, margin_bottom: u32 }
type PrintJob = struct { device: usize, id: i32, pages: u32, open: bool }
type Capability = enum u8 { Camera, Microphone, Location, Screen, Biometric, Photos }
type Credential = struct { user: str, secret: []const u8 }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }
type ProgressState = enum u8 { None, Indeterminate, Normal, Paused, Error }
type JumpTask = struct { title: str, program: str, arguments: str, description: str }
error Unsupported
error Invalid
error NotFound
error Failed
error Cancelled
fn capabilities() -> Capabilities
fn tray_add(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err
fn tray_update(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err
fn tray_remove(a: *mem.Arena, id: u32) -> err
fn tray_poll() -> (TrayEvent, bool)
fn popup_menu(a: *mem.Arena, items: []const MenuItem, x: i32, y: i32) -> (u32, bool, err)
fn open_uri(a: *mem.Arena, uri: str) -> err
fn reveal(a: *mem.Arena, path: str) -> err
fn trash(a: *mem.Arena, path: str) -> err
fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err
fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err
fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err
fn jump_list_clear(a: *mem.Arena) -> err
fn notice_permission(a: *mem.Arena) -> NoticePermission
fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err)
fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err
fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err
fn clipboard_write(a: *mem.Arena, items: []const Content) -> err
fn clipboard_has(a: *mem.Arena, kind: ContentKind, mime: str) -> bool
fn clipboard_read(a: *mem.Arena, kind: ContentKind, mime: str) -> (Content, err)
fn clipboard_sequence() -> u32
fn drop_target_register(a: *mem.Arena, w: os.Window, storage: *mem.Arena) -> err
fn drop_target_unregister(a: *mem.Arena, w: os.Window) -> err
fn drop_poll() -> (Drop, bool)
fn drag_start(a: *mem.Arena, items: []const Content, allow_move: bool) -> (DragResult, err)
fn file_dialog(a: *mem.Arena, w: os.Window, dialog: FileDialog) -> ([]const str, err)
fn recent_add(a: *mem.Arena, path: str) -> err
fn activation_of(a: *mem.Arena, args: []const str) -> Activation
fn associate_file(a: *mem.Arena, extension: str, program_id: str, description: str) -> err
fn dissociate_file(a: *mem.Arena, extension: str, program_id: str) -> err
fn associate_protocol(a: *mem.Arena, scheme: str, description: str) -> err
fn dissociate_protocol(a: *mem.Arena, scheme: str) -> err
fn startup_set(a: *mem.Arena, id: str, enabled: bool) -> err
fn startup_enabled(a: *mem.Arena, id: str) -> (bool, err)
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err)
fn activation_poll() -> (Activation, bool)
fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err
fn hotkey_unregister(a: *mem.Arena, id: u32) -> err
fn hotkey_poll() -> (u32, bool)
fn background_permission(a: *mem.Arena) -> Permission
fn power_inhibit(a: *mem.Arena, keep_display: bool) -> err
fn power_release(a: *mem.Arena) -> err
fn lifecycle_poll() -> (LifecycleEvent, bool)
fn restart_register(a: *mem.Arena, arguments: str) -> err
fn restart_unregister(a: *mem.Arena) -> err
fn printer_open(a: *mem.Arena, name: str) -> (Printer, err)
fn printer_close(a: *mem.Arena, p: Printer) -> err
fn printer_page(p: Printer) -> PrintPage
fn print_dialog(a: *mem.Arena, w: os.Window, min_page: u32, max_page: u32) -> (Printer, err)
fn page_setup_dialog(a: *mem.Arena, w: os.Window, current: PageSetup) -> (PageSetup, err)
fn print_job_start(a: *mem.Arena, p: Printer, document: str, output: str) -> (PrintJob, err)
fn print_page(a: *mem.Arena, job: *PrintJob, page: Icon) -> err
fn print_job_end(a: *mem.Arena, job: *PrintJob) -> err
fn print_job_cancel(a: *mem.Arena, job: *PrintJob) -> err
fn permission_status(a: *mem.Arena, c: Capability) -> Permission
fn permission_request(a: *mem.Arena, c: Capability) -> (Permission, err)
fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err
fn credential_read(a: *mem.Arena, target_name: str) -> (Credential, err)
fn credential_delete(a: *mem.Arena, target_name: str) -> err
fn screen_capture(a: *mem.Arena) -> (Icon, err)
fn biometric_verify(a: *mem.Arena, reason: str) -> (Permission, err)
fn photo_picker(a: *mem.Arena, w: os.Window, multiple: bool) -> ([]const str, err)
```

The host's shell services (D885, the widget plan's `native-shell-api`), written per
target like `e.os`. `capabilities` says what this host answers; a service the host
has no standard for is `Unsupported`, never emulated in a window. A tray item is the
caller's pixels (`0xAARRGGBB`, rows top-down) and tooltip under a caller-chosen id;
`tray_poll` pumps the item's messages and answers its activations at the cursor.
`popup_menu` is the shell's own menu at a screen point, blocking until a choice or a
dismissal; a zero id on anything but a separator is `Invalid`. `open_uri` is the
shell's open verb (`ShellExecuteW`; `xdg-open` by its exit code), `reveal` the file
manager at the item (selected on Windows; the item's directory on Linux) and `trash`
the recycle bin or the freedesktop home trash with its `.trashinfo`. An empty
argument is `Invalid` and a missing item `NotFound` before the host is asked.

The taskbar and the jump list (D887) are COM on Windows, reached through D32's
`extern fn` pointer types by vtable slot: `taskbar_progress` is the window's button
state and, for a determinate one, `completed` of `total` (`Invalid` past it or over
nothing); `taskbar_overlay` an icon from the caller's pixels on the button with a
spoken description, cleared by an icon of no width; `jump_list` the application's
tasks replaced whole, each a title, a program, its arguments and a description, and
`jump_list_clear` the list removed. Linux has no desktop standard for any of the
three, so they are `Unsupported` and the record says so.

A notice (D889, the plan's `native-notification-api`) is the shell's balloon on a
tray item the caller holds on Windows -- shown as a toast, kept in the action
centre, its activation and dismissal arriving as the item's `NoticeSelect` and
`NoticeDismiss` tray events, taken down by `notice_remove` -- and the desktop's
notification daemon through `notify-send` on Linux, where the tray id is ignored,
`notice_publish` answers the daemon's id, `notice_update` replaces by it and
`notice_remove` is `Unsupported`. `notice_permission` is `Granted` where nothing
gates a notice and `Unavailable` where the tool or the session bus is missing; a
notice with no body is `Invalid`; buttons are `notice_actions`, false on both.

Data exchange (D890, the plan's `native-data-exchange-api`) is one `Content` per
representation -- text, paths, an image as pixels, or bytes under a MIME name --
and on Windows the shell's clipboard and OLE: `clipboard_write` replaces the
clipboard with one global block per item (`CF_UNICODETEXT`, an `HDROP`, a 32-bit
`CF_DIB`, a format registered under the name), `clipboard_has` asks without
reading, `clipboard_read` copies one representation into the arena (`NotFound`
when absent, `Unsupported` for a DIB it does not decode) and `clipboard_sequence`
is the shell's change counter for a monitor to poll. `drop_target_register` puts
an `IDropTarget` on the caller's window and copies each representation a drop
carries into `storage`, `drop_poll` answers the drops in order, and `drag_start`
offers items as an `IDataObject` to `DoDragDrop`, blocking until the receiver
copies, moves or the drag is cancelled. Linux has no selection in `e.os` and no
XDND here, so every verb is `Unsupported` and the record says so.

A `.Promise` (D892) is a file the receiver writes out itself -- its name in `text`,
its contents in `bytes` -- and in a drag it is the shell's `FileGroupDescriptorW`
and `FileContents` pair, one descriptor block for all the promises and the
contents by index; a drop from another program carries its promised files back
the same way, one `.Promise` item each. A promise has no clipboard format here,
so `clipboard_write` answers `Unsupported` for one.

A file dialog (D894, the plan's `native-file-access-api`) is the shell's
`IFileOpenDialog` or `IFileSaveDialog` on Windows -- the kind's options, the
filters as label and pattern pairs, an initial name, a default extension, shown
modally over the caller's window or none -- answering the chosen file system
paths (every one for a multiple open), `Cancelled` when closed without a choice,
and `Invalid` for more than sixteen filters or a multiple save or folder pick;
`recent_add` is `SHAddToRecentDocs` of an existing item. Linux has neither the
portal nor a toolkit here, so both are `Unsupported` and the record says so.

Activation (D896, the plan's `native-activation-api`): `activation_of` reads a
command line as a launch, a file that exists, or a URL with a scheme, on every
host. On Windows an association is the per-user registry under
`Software\Classes` -- the extension naming the program id, the program id's
open command naming this executable with `%1`, a scheme marked `URL Protocol` --
removed again by `dissociate_*` (`NotFound` when absent, `Invalid` for a name
with a separator or a quote); startup is the `Run` key's value under the id;
a single instance is a named mutex, the first holder titling the hidden window
with the id and receiving later instances' arguments as `WM_COPYDATA`, which
`activation_poll` answers as activations from `storage`, a later instance
handing its arguments over and answering false. Linux writes and removes the
freedesktop autostart entry under `$XDG_CONFIG_HOME/autostart`; associations
and a single instance are `Unsupported` there and the record says so.

Lifecycle (D898, the plan's `native-lifecycle-api`): on Windows a hotkey is
`RegisterHotKey` on the hidden window under the caller's id (1 to 49151, the
modifiers as given, `Failed` when another program holds the combination), its
presses drained by `hotkey_poll`; the session's `WM_QUERYENDSESSION` and
`WM_POWERBROADCAST` become `Shutdown`, `Suspend` and `Resume` from
`lifecycle_poll`; `power_inhibit` is the thread's execution state until
`power_release`; `restart_register` is `RegisterApplicationRestart` with at most
1024 characters of arguments. Background work needs no permission on either
host. Linux inhibits through `systemd-inhibit` holding a child until released,
and answers `Unsupported` for hotkeys, lifecycle events and restart.

Printing (D900, the plan's `native-print-api`): on Windows a `Printer` is a GDI
device from `WINSPOOL` by name or the default, `printer_page` its printable area
in device pixels and its resolution, `print_dialog` the user's printer with the
range and copies (`PD_RETURNDC`; `Cancelled` on close, `Invalid` for a range not
inside 1 to 65535), `page_setup_dialog` the paper and margins in hundredths of a
millimetre; a `PrintJob` is `StartDocW` under the document's name -- to the
output path instead of the spool when one is given, which the PDF printer writes
-- each `print_page` a 32-bit DIB stretched over the printable area, `print_job_end`
and `print_job_cancel` `EndDoc` and `AbortDoc`. Linux is `Unsupported` throughout
and the record says so.

Permissions (D902, the plan's `native-permission-api`): on Windows the camera,
the microphone and the location are the user's consent in the privacy settings
as the registry's `ConsentStore` records it, per capability and for unpackaged
programs -- `permission_status` reads it (`Granted`, `Denied`, `Unavailable` when
no record exists) and `permission_request` opens the capability's settings page
on a denial, since a desktop program has no prompt of its own; the screen and
the photos need no consent; biometrics are `Unavailable` and `biometric_verify`
`Unsupported`. A credential is the Credential Manager's generic entry under a
target name (`credential_store` at most 2560 bytes, `credential_read` the secret
and the user, `credential_delete`; `NotFound` when absent). `screen_capture` is
the primary screen through GDI as pixels. `photo_picker` is the open dialog over
the Pictures folder with image filters; a `FileDialog` may now name its `folder`.
Linux answers `Unavailable` for every status, `Unsupported` for the picker, the
screen and biometrics, and keeps credentials through `secret-tool` where it is
installed.

### `e.cancel`

```neper
type Token = struct { state: Atomic[u32] }
type Control = struct { token: *const Token, deadline: time.Instant, has_deadline: bool }
error Cancelled
error Timeout

fn token() -> Token
fn request(t: *Token)
fn requested(t: *const Token) -> bool
fn check(control: Control, now: time.Instant) -> err
```

Token is non-copyable after sharing and needs no allocation or worker pool.
request is thread-safe and idempotent; requested(nil) is false. Control borrows
its token until the operation acknowledges completion. has_deadline=false means
no deadline; zero is a valid clock value, not a sentinel. check observes an explicit
monotonic now: cancellation takes precedence when both conditions hold at that
observation. Requesting cancellation does not join work or release its buffers.
No ambient values, automatic timer, parent registry or hidden allocation is added.
See stdlib-hardening.md SL03 for operation-level completion/partial-progress rules.

### `e.io`

```neper
type Reader = struct { ctx: *void, read: fn(*void, []u8) -> (usize, err) }
type DetailReader = struct { ctx: *void, read: fn(*void, []u8, *os.ErrorDetail) -> (usize, err) }
type Writer = struct { ctx: *void, write: fn(*void, []const u8) -> (usize, err), flush: fn(*void) -> err }
type DetailWriter = struct { ctx: *void, write: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err), flush: fn(*void, *os.ErrorDetail) -> err }
type SliceReader = struct { data: []const u8, off: usize }
type SliceWriter = struct { data: []u8, off: usize }
type BufferedReader = struct { state: *void }
type BufferedWriter = struct { state: *void }
type DetailBufferedReader = struct { state: *void }
type DetailBufferedWriter = struct { state: *void }
type Seeker = struct { ctx: *void, seek: fn(*void, i64, os.SeekWhence) -> (u64, err) }
type LimitedReader = struct { source: Reader, remaining: u64 }
type CountingWriter = struct { sink: Writer, count: u64 }
type TeeWriter = struct { left: Writer, right: Writer }
type MemoryWriter = struct { arena: *mem.Arena, start: usize, len: usize }
type BufferState = struct { source: Reader, sink: Writer, buffer: []u8, off: usize, len: usize }
type DetailBufferState = struct { source: DetailReader, sink: DetailWriter, buffer: []u8, off: usize, len: usize, pending_error: err, pending_detail: os.ErrorDetail }
error End
error TooSmall
error NoProgress

fn reader(ctx: *void, read_fn: fn(*void, []u8) -> (usize, err)) -> Reader
fn detail_reader(ctx: *void, read_fn: fn(*void, []u8, *os.ErrorDetail) -> (usize, err)) -> DetailReader
fn writer(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err)) -> Writer
fn detail_writer(ctx: *void, write_fn: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err)) -> DetailWriter
fn file_reader(file: *os.File) -> Reader
fn file_detail_reader(file: *os.File) -> DetailReader
fn file_writer(file: *os.File) -> Writer
fn file_detail_writer(file: *os.File) -> DetailWriter
fn slice_reader(state: *SliceReader) -> Reader
fn slice_detail_reader(state: *SliceReader) -> DetailReader
fn slice_writer(state: *SliceWriter) -> Writer
fn slice_detail_writer(state: *SliceWriter) -> DetailWriter
fn buffered_reader(a: *mem.Arena, source: Reader, capacity: usize) -> (BufferedReader, err)
fn buffered_writer(a: *mem.Arena, sink: Writer, capacity: usize) -> (BufferedWriter, err)
fn buffered_detail_reader(a: *mem.Arena, source: DetailReader, capacity: usize, detail: *os.ErrorDetail) -> (DetailBufferedReader, err)
fn buffered_detail_writer(a: *mem.Arena, sink: DetailWriter, capacity: usize, detail: *os.ErrorDetail) -> (DetailBufferedWriter, err)
fn file_seeker(file: *os.File) -> Seeker
fn limited_reader(state: *LimitedReader, source: Reader, limit: u64) -> Reader
fn counting_writer(state: *CountingWriter, sink: Writer) -> Writer
fn tee_writer(state: *TeeWriter, left: Writer, right: Writer) -> Writer
fn memory_writer(a: *mem.Arena, capacity: usize) -> (MemoryWriter, Writer, err)
fn memory_bytes(w: *const MemoryWriter) -> []const u8
fn read(r: *Reader, dst: []u8) -> (usize, err)
fn read_detail(r: *DetailReader, dst: []u8, detail: *os.ErrorDetail) -> (usize, err)
fn read_exact(r: *Reader, dst: []u8) -> err
fn read_exact_detail(r: *DetailReader, dst: []u8, detail: *os.ErrorDetail) -> (usize, err)
fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> ([]u8, err)
fn read_all_detail(a: *mem.Arena, r: *DetailReader, limit: usize, detail: *os.ErrorDetail) -> ([]u8, err)
fn read_until(a: *mem.Arena, r: *Reader, delimiter: u8, limit: usize) -> ([]u8, err)
fn write(w: *Writer, src: []const u8) -> (usize, err)
fn write_detail(w: *DetailWriter, src: []const u8, detail: *os.ErrorDetail) -> (usize, err)
fn write_all_progress(w: *Writer, src: []const u8) -> (usize, err)
fn write_all(w: *Writer, src: []const u8) -> err
fn write_all_detail(w: *DetailWriter, src: []const u8, detail: *os.ErrorDetail) -> (usize, err)
fn flush(w: *Writer) -> err
fn flush_detail(w: *DetailWriter, detail: *os.ErrorDetail) -> err
fn seek(s: *Seeker, off: i64, whence: os.SeekWhence) -> (u64, err)
fn copy(dst: *Writer, src: *Reader, scratch: []u8) -> (u64, err)
fn copy_detail(dst: *DetailWriter, src: *DetailReader, scratch: []u8, detail: *os.ErrorDetail) -> (u64, err)
fn print(s: str) -> err
fn printf[FMT: str](args: ...) -> err
fn writer_with_flush(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err), flush_fn: fn(*void) -> err) -> Writer
fn detail_writer_with_flush(ctx: *void, write_fn: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err), flush_fn: fn(*void, *os.ErrorDetail) -> err) -> DetailWriter
fn buffered_source(buffer: *BufferedReader) -> Reader
fn buffered_sink(buffer: *BufferedWriter) -> Writer
fn buffered_detail_source(buffer: *DetailBufferedReader) -> DetailReader
fn buffered_detail_sink(buffer: *DetailBufferedWriter) -> DetailWriter
fn file_read(ctx: *void, dst: []u8) -> (usize, err)
fn file_read_detail(ctx: *void, dst: []u8, detail: *os.ErrorDetail) -> (usize, err)
fn file_write(ctx: *void, src: []const u8) -> (usize, err)
fn file_write_detail(ctx: *void, src: []const u8, detail: *os.ErrorDetail) -> (usize, err)
fn file_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err)
fn slice_read(ctx: *void, dst: []u8) -> (usize, err)
fn slice_read_detail(ctx: *void, dst: []u8, detail: *os.ErrorDetail) -> (usize, err)
fn slice_write(ctx: *void, src: []const u8) -> (usize, err)
fn slice_write_detail(ctx: *void, src: []const u8, detail: *os.ErrorDetail) -> (usize, err)
fn limited_read(ctx: *void, dst: []u8) -> (usize, err)
fn counting_write(ctx: *void, src: []const u8) -> (usize, err)
fn tee_write(ctx: *void, src: []const u8) -> (usize, err)
fn memory_write(ctx: *void, src: []const u8) -> (usize, err)
fn buffered_read(ctx: *void, dst: []u8) -> (usize, err)
fn buffered_write(ctx: *void, src: []const u8) -> (usize, err)
fn buffered_writer_flush(ctx: *void) -> err
fn buffered_detail_read(ctx: *void, dst: []u8, detail: *os.ErrorDetail) -> (usize, err)
fn buffered_detail_write(ctx: *void, src: []const u8, detail: *os.ErrorDetail) -> (usize, err)
fn buffered_detail_writer_flush(ctx: *void, detail: *os.ErrorDetail) -> err
fn forwarding_flush(ctx: *void) -> err
fn no_flush(ctx: *void) -> err
fn no_flush_detail(ctx: *void, detail: *os.ErrorDetail) -> err

```

`BufferedReader` and `BufferedWriter` hold their state behind a `*void` so that the
surface does not fix it, but the state has a layout and the layout is a type;
`BufferState` is it, one type serving both directions. It is named here for the
reason the callbacks are: it is public either way.

The callbacks are declarations (D94). A constructor has to supply one, and the
language has no visibility mechanism (section 12) and no closures, so each is a public
symbol; a surface that omitted them described a module that could not be written. They
are named after the constructor that installs them and are not otherwise useful: pass
one to `reader`/`writer` and it will read whatever `ctx` you hand it as the state that
constructor expects. `no_flush` is the flush of a sink that buffers nothing, and
succeeds without work; `forwarding_flush` is the flush of an adapter that owns no
buffer of its own and passes it to the sink it wraps.

`limit` is a hard maximum; crossing it returns `TooSmall` without retaining a partial
result. A callback returning `(0, ok)` for a non-empty request returns `NoProgress`.
`tee_writer` writes each input to the left sink before the right sink and stops on
the first error; it therefore does not promise transactional duplication.


Buffered adapters borrow their wrapper and transitively its source/sink and arena.
They never close the underlying stream. writer constructs an unbuffered sink whose
flush callback is nil (flush succeeds without work); writer_with_flush supplies an
explicit callback. buffered_sink flushes buffered bytes before forwarding flush.
Partial writes retain only the unwritten suffix; a failed flush is not a rollback.
Compression finish, protocol shutdown, and durable filesystem sync are distinct
operations, never implied by generic flush. See stdlib-hardening.md SL02.

The additive `DetailReader`/`DetailWriter` family carries a caller-owned
`os.ErrorDetail` through file, buffered and copy operations without changing the
established callback ABI. Success and end-of-stream leave the value unchanged.
Library limit, no-progress and allocation failures use native code zero and name the
operation and failed constraint; native file failures retain the host code captured
by `e.os` at that call.

### `e.text.io`

```neper
type Reader = struct { state: *void }
type Writer = struct { state: *void }
type Newline = enum u8 { Lf, CrLf, Native }
error End
error TooLarge
error Invalid

fn reader(a: *mem.Arena, source: io.Reader, source_encoding: encoding.Encoding, policy: encoding.InvalidPolicy, capacity: usize) -> (Reader, err)
fn reader_bom(a: *mem.Arena, source: io.Reader, fallback: encoding.Encoding, policy: encoding.InvalidPolicy, capacity: usize) -> (Reader, err)
fn read_line(a: *mem.Arena, r: *Reader, limit: usize) -> (str, err)
fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> (str, err)
fn writer(a: *mem.Arena, sink: io.Writer, source_encoding: encoding.Encoding, emit_bom: bool, newline: Newline, capacity: usize) -> (Writer, err)
fn write(w: *Writer, text: str) -> err
fn write_line(w: *Writer, text: str) -> err
fn flush(w: *Writer) -> err
```

Returned text is UTF-8. `read_line` accepts LF, CRLF, or a final unterminated line
and excludes its terminator; a bare CR is content. `Newline.Native` is resolved when
the writer is constructed. Reader and writer state is arena-owned and non-copyable.

### `e.fs`

```neper
type EntryKind = enum u8 { File, Directory, Symlink, Other }
type Entry = struct { path: str, kind: EntryKind, size: u64 }
type Permissions = struct { owner_read: bool, owner_write: bool, owner_exec: bool, group_read: bool, group_write: bool, group_exec: bool, other_read: bool, other_write: bool, other_exec: bool }
type Metadata = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, permissions: Permissions, file_id: u64, link_count: u64 }
type Walk = struct { state: *void }
type WalkOptions = struct { recursive: bool, follow_symlinks: bool }
type ReplaceOptions = struct { overwrite: bool, durable: bool }
error NotFound
error Exists
error Denied
error Invalid
error Io

fn exists(a: *mem.Arena, path_text: str) -> (bool, err)
fn stat(a: *mem.Arena, path_text: str) -> (Entry, err)
fn metadata(a: *mem.Arena, path_text: str, follow_symlinks: bool) -> (Metadata, err)
fn set_permissions(a: *mem.Arena, path_text: str, permissions: Permissions) -> err
fn set_times(a: *mem.Arena, path_text: str, accessed_ns: i64, modified_ns: i64) -> err
fn make_dir(a: *mem.Arena, path_text: str) -> err
fn make_dirs(a: *mem.Arena, path_text: str) -> err
fn remove_file(a: *mem.Arena, path_text: str) -> err
fn remove_dir(a: *mem.Arena, path_text: str) -> err
fn copy_file(a: *mem.Arena, src: str, dst: str, scratch: []u8) -> err
fn move(a: *mem.Arena, src: str, dst: str) -> err
fn replace(a: *mem.Arena, src: str, dst: str, options: ReplaceOptions) -> err
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err
fn read_link(a: *mem.Arena, path_text: str) -> (str, err)
fn canonical(a: *mem.Arena, path_text: str) -> (str, err)
fn current_dir(a: *mem.Arena) -> (str, err)
fn set_current_dir(a: *mem.Arena, path_text: str) -> err
fn executable_path(a: *mem.Arena) -> (str, err)
fn temp_dir(a: *mem.Arena) -> (str, err)
fn temp_file(a: *mem.Arena, dir: str, prefix: str) -> (str, os.File, err)
fn home_dir(a: *mem.Arena) -> (str, err)
fn read_file(a: *mem.Arena, path_text: str, limit: usize) -> ([]u8, err)
fn write_file(a: *mem.Arena, path_text: str, data: []const u8) -> err
fn walk(a: *mem.Arena, root_path: str, options: WalkOptions) -> (Walk, err)
fn walk_next_err(it: *Walk) -> (Entry, bool, err)
fn last_error_detail(operation: str, subject: str) -> os.ErrorDetail
fn stat_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> (Entry, err)
fn metadata_detail(a: *mem.Arena, path_text: str, follow_symlinks: bool, detail: *os.ErrorDetail) -> (Metadata, err)
fn make_dir_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> err
fn make_dirs_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> err
fn remove_file_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> err
fn remove_dir_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> err
fn move_detail(a: *mem.Arena, src: str, dst: str, detail: *os.ErrorDetail) -> err
fn read_link_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> (str, err)
fn canonical_detail(a: *mem.Arena, path_text: str, detail: *os.ErrorDetail) -> (str, err)
fn read_file_detail(a: *mem.Arena, path_text: str, limit: usize, detail: *os.ErrorDetail) -> ([]u8, err)
fn write_file_detail(a: *mem.Arena, path_text: str, data: []const u8, detail: *os.ErrorDetail) -> err
type Root = struct { dir: os.Dir }

fn root(a: *mem.Arena, path_text: str) -> (Root, err)
fn root_close(r: *Root) -> err
fn open_at(a: *mem.Arena, r: *const Root, relative_path: str, flags: os.OpenFlags, policy: os.ResolvePolicy) -> (os.File, err)
fn remove_at(a: *mem.Arena, r: *const Root, relative_path: str, directory: bool) -> err
fn replace_at(a: *mem.Arena, src_root: *const Root, src_path: str, dst_root: *const Root, dst_path: str, options: ReplaceOptions) -> err
fn walk_close(it: *Walk) -> err

```

Unavailable creation times are `-1`; timestamps are Unix-epoch nanoseconds. Windows
permissions map only the portable read-only/executable subset and unsupported changes
return `os.Unsupported`. `temp_file` creates a new file atomically with exclusive
access and never returns a predictable uncreated name. `replace` is atomic within one
filesystem or returns `Invalid`; `durable` requests file and parent-directory
persistence. `last_error_detail` snapshots the underlying failure without another
host operation and is called before any cleanup that could replace it.


Root owns its directory handle and follows H01; its methods retain the SL06
handle-relative semantics rather than normalizing strings then using path APIs.
walk_close releases an abandoned traversal and is required on early exit; exhaustion
releases OS traversal handles. Path functions remain convenience APIs, not sandboxes.
last_error_detail is a legacy M2 bridge; the `_detail` forms (D479, H07) are the
checked API's transport: each writes the host's account of its own failing call into
the caller's `os.ErrorDetail` at that call, before any cleanup, naming the `e.os`
operation that failed (`stat` under `read_file`, `rename` under `move`) and its path;
`make_dirs_detail` names the component that could not be made. Partial effects are
the plain form's: what was made before the failing step stays made.

### `e.fs.mmap`

```neper
type Mapping = struct { raw: os.Mapping }
error Empty
error Invalid

fn open(a: *mem.Arena, path: str, writable: bool, offset: u64, len: usize) -> (Mapping, err)
fn bytes(m: Mapping) -> []u8
fn flush(m: Mapping) -> err
fn close(m: own Mapping) -> err
```

Offset and length are byte values; the implementation performs page alignment
without changing the returned slice. Zero length returns `Empty`. `close` consumes
the mapping and invalidates every derived pointer or slice.

### `e.fs.watch`

```neper
type Watch = struct { raw: os.Watch }
type Action = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type Event = struct { action: Action, path: str, old_path: str }
error Closed
error Unsupported

fn open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err)
fn read(a: *mem.Arena, watch: Watch, events: []Event) -> (usize, err)
fn close(watch: own Watch) -> err
```

Paths are relative to the watched root. `Renamed` supplies both paths when the host
can pair them and otherwise appears as remove/add. `Overflow` means callers must
rescan. Events may coalesce and no operation assumes one event per host change.

### `e.proc`

```neper
type Command = struct { program: str, args: []const str, env: []const str, inherit_env: bool, cwd: str }
type Streams = struct { stdin: os.File, stdout: os.File, stderr: os.File }
type Child = struct { process: os.Proc, streams: Streams }
type Output = struct { status: i32, stdout: []u8, stderr: []u8 }
error TooLarge

fn spawn(a: *mem.Arena, command: Command, streams: Streams) -> (Child, err)
fn spawn_piped(a: *mem.Arena, command: Command) -> (Child, err)
fn wait(child: *Child) -> (i32, err)
fn kill(child: *Child) -> err
fn output(a: *mem.Arena, command: Command, limit: usize) -> (Output, err)
fn spawn_detail(a: *mem.Arena, command: Command, streams: Streams, detail: *os.ErrorDetail) -> (Child, err)
fn spawn_piped_detail(a: *mem.Arena, command: Command, detail: *os.ErrorDetail) -> (Child, err)
fn output_detail(a: *mem.Arena, command: Command, limit: usize, detail: *os.ErrorDetail) -> (Output, err)
type Outcome = enum u8 { Exited, Cancelled, TimedOut, OutputLimit }
type RunOptions = struct { control: cancel.Control, stdout_limit: usize, stderr_limit: usize, terminate_grace: time.Duration, contain_tree: bool }
type RunResult = struct { outcome: Outcome, status: i32, status_known: bool, stdout: []const u8, stderr: []const u8, stdout_bytes: u64, stderr_bytes: u64, truncated: bool }

fn run(a: *mem.Arena, command: Command, options: RunOptions) -> (RunResult, err)

```

An empty `cwd` inherits the parent directory. `inherit_env` has the same overlay vs
replacement meaning as `os.SpawnOptions`; environment entries are `NAME=VALUE`.


run drains stdout/stderr concurrently, enforces independent capture budgets, and
returns only after reaping its child and closing its capture pipes. Exited includes
nonzero status; cancellation/timeout/output limit are explicit outcomes, not API
success of the child. Overflow retains bounded prefixes, initiates termination,
and records truncation and observed byte totals. Infrastructure failure returns err
and a valid possibly partial RunResult; callers must inspect err first.
A control deadline governs running work; terminate_grace bounds cooperative shutdown
before forced termination. A separate bounded drain follows, then inherited pipe
writers are closed locally and truncation recorded. contain_tree requires a
supported containment facility established before child code executes; unsupported
containment is rejected before spawning. No shell is inserted. Child-only mode
does not promise descendant cleanup. See SL05 for platform limits and test cases.

### `e.thread`

```neper
type Thread = os.Thread
type Group = resource(join_all) struct { threads: []Thread, count: usize }
const DEFAULT_STACK: usize = 1048576usize

fn spawn[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err)
fn join(thread: own Thread) -> err
fn detach(thread: own Thread) -> err
fn spawn_all[Ctx: type](a: *mem.Arena, entry: fn(*Ctx), contexts: []Ctx, stack: usize) -> (Group, err)
fn join_all(g: own Group) -> err
```

### `e.sync`

```neper
type Mutex = struct { state: Atomic[u32] }
type RwLock = struct { state: Atomic[u32] }
type Condition = struct { state: Atomic[u32] }
type Semaphore = struct { state: Atomic[u32] }
type Event = struct { state: Atomic[u32], manual_reset: bool }
type Once = struct { state: Atomic[u32] }
type Barrier = struct { state: *void }
type Guard = resource(release) struct { m: *Mutex }
type ReadGuard = resource(read_release) struct { l: *RwLock }
type WriteGuard = resource(write_release) struct { l: *RwLock }
error Invalid

fn mutex() -> Mutex
fn mutex_lock(m: *Mutex)
fn mutex_try_lock(m: *Mutex) -> bool
fn mutex_lock_for(m: *Mutex, timeout: time.Duration) -> bool
fn mutex_unlock(m: *Mutex)
fn guard(m: *Mutex) -> Guard
fn try_guard(m: *Mutex) -> (Guard, err)
fn release(g: own Guard)
fn rwlock() -> RwLock
fn rwlock_read_lock(l: *RwLock)
fn rwlock_try_read_lock(l: *RwLock) -> bool
fn rwlock_read_lock_for(l: *RwLock, timeout: time.Duration) -> bool
fn rwlock_read_unlock(l: *RwLock)
fn rwlock_write_lock(l: *RwLock)
fn rwlock_try_write_lock(l: *RwLock) -> bool
fn rwlock_write_lock_for(l: *RwLock, timeout: time.Duration) -> bool
fn rwlock_write_unlock(l: *RwLock)
fn read_guard(l: *RwLock) -> ReadGuard
fn try_read_guard(l: *RwLock) -> (ReadGuard, err)
fn read_release(g: own ReadGuard)
fn write_guard(l: *RwLock) -> WriteGuard
fn try_write_guard(l: *RwLock) -> (WriteGuard, err)
fn write_release(g: own WriteGuard)
fn condition() -> Condition
fn condition_wait(c: *Condition, m: *Mutex)
fn condition_wait_for(c: *Condition, m: *Mutex, timeout: time.Duration) -> bool
fn condition_signal(c: *Condition)
fn condition_broadcast(c: *Condition)
fn semaphore(initial: u32) -> Semaphore
fn semaphore_wait(s: *Semaphore)
fn semaphore_try_wait(s: *Semaphore) -> bool
fn semaphore_wait_for(s: *Semaphore, timeout: time.Duration) -> bool
fn semaphore_post(s: *Semaphore, count: u32) -> err
fn event(manual_reset: bool, signaled: bool) -> Event
fn event_set(e: *Event)
fn event_reset(e: *Event)
fn event_wait(e: *Event)
fn event_wait_for(e: *Event, timeout: time.Duration) -> bool
fn once() -> Once
fn once_call[Ctx: type](o: *Once, ctx: *Ctx, f: fn(*Ctx) -> err) -> err
fn barrier(a: *mem.Arena, parties: u32) -> (Barrier, err)
fn barrier_wait(b: *Barrier) -> bool
fn barrier_close(b: *Barrier)
```

All waits recheck their state after `os.wait_u32`, so spurious wakes are invisible to
callers. `semaphore_post` returns `Invalid` instead of wrapping the count.
Timed waits return `false` only on timeout. A negative duration is invalid and zero
polls once. `once_call` publishes completion only after `f` returns `ok`; an error
permits a later caller to retry. Exactly one participant receives `true` from each
barrier generation.

### `e.channel`

```neper
type Channel[T: type] = struct { state: *void }
error Closed

fn init[T: type](a: *mem.Arena, cap: usize) -> (Channel[T], err)
fn send[T: type](c: *Channel[T], value: own T) -> err
fn try_send[T: type](c: *Channel[T], value: own T) -> (bool, err)
fn receive[T: type](c: *Channel[T]) -> (T, err)
fn try_receive[T: type](c: *Channel[T]) -> (T, bool, err)
fn close[T: type](c: *Channel[T]) -> err
fn len[T: type](c: *const Channel[T]) -> usize
fn capacity[T: type](c: *const Channel[T]) -> usize
```

A capacity of zero is invalid. Closing wakes all waiters; buffered values remain
receivable before `Closed` is returned.

### `e.concurrent.queue`

```neper
type Queue[T: type] = struct { state: *void }
error Closed
error Invalid

fn init[T: type](a: *mem.Arena, initial_capacity: usize) -> (Queue[T], err)
fn try_push[T: type](q: *Queue[T], value: T) -> (bool, err)
fn push[T: type](q: *Queue[T], value: own T) -> err
fn push_for[T: type](q: *Queue[T], value: T, timeout: time.Duration) -> (bool, err)
fn try_pop[T: type](q: *Queue[T]) -> (T, bool, err)
fn pop[T: type](q: *Queue[T]) -> (T, err)
fn pop_for[T: type](q: *Queue[T], timeout: time.Duration) -> (T, bool, err)
fn close[T: type](q: *Queue[T]) -> err
fn len[T: type](q: *const Queue[T]) -> usize
fn capacity[T: type](q: *const Queue[T]) -> usize
```

This is a bounded multi-producer/multi-consumer FIFO. Closing wakes every waiter;
buffered values remain readable before `Closed`. Timed calls return `false` only on
timeout. Capacity is fixed and all state is allocated during `init`.

### `e.concurrent.map`

```neper
type Map[K: type, V: type] = struct { state: *void }
error Closed
error Full
error Invalid

fn init[K: type, V: type](a: *mem.Arena, capacity: usize, shards: u16) -> (Map[K, V], err)
fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool, err)
fn put[K: type, V: type](m: *Map[K, V], key: K, value: own V) -> (bool, err)
fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool, err)
fn len[K: type, V: type](m: *const Map[K, V]) -> (usize, err)
fn close[K: type, V: type](m: *Map[K, V]) -> err
```

The map is fixed-capacity and sharded. Individual operations are linearizable;
`len` is a point-in-time sum and not a transaction with surrounding operations.
User hash/equality protocol functions must be thread-safe. Iteration and borrowed
value pointers are deliberately absent because concurrent mutation would invalidate
them. `init` returns `Invalid` for zero capacity or shards; insertion of a new key
into a full map returns `Full`, while replacing an existing key still succeeds.

### `e.task`

```neper
type Pool = struct { state: *void }
type Task = struct { state: *void }
type Future[T: type] = struct { state: *void }
type Cancel = cancel.Token
type Status = enum u8 { Pending, Running, Succeeded, Failed, Cancelled }
type Options = struct { workers: u32, queue_capacity: usize, stack_size: usize }
error Cancelled
error Closed
error Invalid

fn pool(a: *mem.Arena, options: Options) -> (Pool, err)
fn submit[Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> err) -> (Task, err)
fn future[T: type, Ctx: type](p: *Pool, cancel_token: *Cancel, ctx: *Ctx, f: fn(*Ctx, *const Cancel) -> (T, err)) -> (Future[T], err)
fn status(t: *const Task) -> Status
fn wait(t: *Task) -> err
fn wait_for(t: *Task, timeout: time.Duration) -> (bool, err)
fn future_get[T: type](f: *Future[T]) -> (T, err)
fn wait_any(tasks: []*Task, timeout: time.Duration) -> (usize, bool, err)
fn wait_all(tasks: []*Task) -> err
fn parallel_for[Ctx: type](p: *Pool, cancel_token: *Cancel, begin: usize, end: usize, grain: usize, ctx: *Ctx, body: fn(*Ctx, usize, usize, *const Cancel) -> err) -> err
fn close(p: *Pool) -> err
```

The pool and all task records borrow their arena for the pool lifetime. Submission is
bounded and never allocates secretly. Cancellation is cooperative: queued work may
become `Cancelled`, while running work observes the shared e.cancel token; construct/request it through that module.
The Cancel alias preserves a named task parameter type, not a second token system. `close` rejects new work,
cancels queued work and joins every worker. `wait_all` returns the first error in
input order, not completion order. `parallel_for` partitions `[begin..end)` into
deterministic ranges no smaller than `grain` except the last; scheduling order is not
observable and callers synchronize shared state explicitly.

### `e.time`

```neper
type Timestamp = struct { nanos: i64 }
type Instant = struct { nanos: i64 }
type Duration = struct { nanos: i64 }
type Date = struct { year: i32, month: u8, day: u8 }
type Time = struct { hour: u8, minute: u8, second: u8, nanos: u32 }
type Timer = struct { started: Instant }
error Invalid

fn now() -> (Timestamp, err)
fn monotonic() -> (Instant, err)
fn timer_start() -> (Timer, err)
fn timer_elapsed(t: Timer) -> Duration
fn since(start: Instant) -> Duration
fn timestamp_add(t: Timestamp, d: Duration) -> Timestamp
fn timestamp_diff(a: Timestamp, b: Timestamp) -> Duration
fn timestamp_cmp(a: Timestamp, b: Timestamp) -> i32
fn instant_add(t: Instant, d: Duration) -> Instant
fn instant_diff(a: Instant, b: Instant) -> Duration
fn instant_cmp(a: Instant, b: Instant) -> i32
fn duration_add(a: Duration, b: Duration) -> Duration
fn duration_sub(a: Duration, b: Duration) -> Duration
fn duration_neg(d: Duration) -> Duration
fn duration_scale(d: Duration, n: i64) -> Duration
fn duration_cmp(a: Duration, b: Duration) -> i32
fn days(n: i64) -> Duration
fn hours(n: i64) -> Duration
fn minutes(n: i64) -> Duration
fn seconds(n: i64) -> Duration
fn millis(n: i64) -> Duration
fn micros(n: i64) -> Duration
fn nanos(n: i64) -> Duration
fn as_days(d: Duration) -> i64
fn as_hours(d: Duration) -> i64
fn as_minutes(d: Duration) -> i64
fn as_seconds(d: Duration) -> i64
fn as_millis(d: Duration) -> i64
fn as_micros(d: Duration) -> i64
fn as_nanos(d: Duration) -> i64
fn to_date(t: Timestamp) -> Date
fn to_time(t: Timestamp) -> Time
fn to_date_at(t: Timestamp, offset_minutes: i32) -> Date
fn to_time_at(t: Timestamp, offset_minutes: i32) -> Time
fn from_civil(d: Date, t: Time) -> (Timestamp, err)
fn format_iso8601(t: Timestamp, buf: []u8) -> str
fn parse_iso8601(s: str) -> (Timestamp, err)
```

### `e.time.calendar`

```neper
type DateTime = struct { date: time.Date, time: time.Time }
type Weekday = enum u8 { Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday }
type IsoWeek = struct { year: i32, week: u8 }
type Components = struct { year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8, nanos: u32, weekday: Weekday, day_of_year: u16 }
error Invalid

fn is_leap_year(year: i32) -> bool
fn days_in_month(year: i32, month: u8) -> (u8, err)
fn valid_date(date: time.Date) -> bool
fn valid_time(value: time.Time) -> bool
fn weekday(date: time.Date) -> (Weekday, err)
fn day_of_year(date: time.Date) -> (u16, err)
fn iso_week(date: time.Date) -> (IsoWeek, err)
fn compare(a: DateTime, b: DateTime) -> i32
fn add_days(value: DateTime, days: i64) -> (DateTime, err)
fn add_months(value: DateTime, months: i64) -> (DateTime, err)
fn add_years(value: DateTime, years: i64) -> (DateTime, err)
fn difference_days(a: DateTime, b: DateTime) -> i64
fn components(value: DateTime) -> (Components, err)
fn from_components(value: Components) -> (DateTime, err)
fn format[PATTERN: str](value: DateTime, dst: []u8) -> (str, err)
fn parse[PATTERN: str](source: str) -> (DateTime, err)
```

This is proleptic Gregorian calendar arithmetic with ISO-8601 weekdays and weeks.
Adding months or years clamps the day to the last valid day of the target month.
Patterns are compile-time strings over the closed verbs `yyyy MM dd HH mm ss SSSSSSSSS`;
punctuation is literal and locale names are deliberately absent. Named zones and
daylight-saving ambiguity belong to `e.tz`.

### `e.tz`

```neper
type Database = struct { state: *void }
type Zone = struct { state: *const void }
type Local = struct { date: time.Date, time: time.Time }
type Offset = struct { seconds: i32, daylight: bool, abbreviation: str }
type Resolve = union enum u8 { Unique: time.Timestamp, Ambiguous: [2]time.Timestamp, Missing: [2]time.Timestamp }
error InvalidData
error NotFound
error TooLarge

fn load(a: *mem.Arena, source: []const u8) -> (Database, err)
fn builtin(a: *mem.Arena) -> (Database, err)
fn version(db: *const Database) -> str
fn zone(db: *const Database, name: str) -> (Zone, err)
fn offset_at(selected_zone: Zone, instant: time.Timestamp) -> Offset
fn to_local(selected_zone: Zone, instant: time.Timestamp) -> Local
fn resolve(selected_zone: Zone, local: Local) -> (Resolve, err)
fn names(db: *const Database) -> []const str
```

`builtin` exposes the IANA Time Zone Database release pinned by the toolchain and
reported by `version`; therefore a toolchain upgrade is the only implicit data
upgrade. `load` permits an explicitly supplied compatible database for reproducible
historical work. `Ambiguous` timestamps are ascending. `Missing` contains the
timestamps immediately before and after the local-time gap. Neither function consults
mutable host time-zone state.

---

## 6. Language-owned runtimes

### `e.asset`

```neper
type Attribute = struct { name: str, value: str }
type Asset = struct { name: str, media_type: str, bytes: []const u8, sha256: [32]u8, attributes: []const Attribute }

fn count() -> usize
fn at(index: usize) -> (Asset, bool)
fn get(name: str) -> (Asset, bool)
fn attribute(value: Asset, name: str) -> (str, bool)
```

The linker generates one immutable registry from the current target's `project.yaml`
asset declarations. Entries are sorted by UTF-8 logical name; lookup is allocation-free
and returns executable-backed slices valid for the process lifetime. Asset contents,
names, media types, attributes and SHA-256 values are part of the executable and build
identity. A build with no assets exposes an empty registry. This module never opens a
file and provides no mutation, decompression or global cache.

### `e.gpu`

```neper
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
type Device = struct { state: *void }
type Queue = struct { state: *void }
type StagingLimits = struct { blocks: u32, block_bytes: usize }
type Buf[T: type] = struct { owner: u32, slot: u32, generation: u32, len: usize }
type Token = struct { owner: u32, queue: u32, serial: u64 }
type Grid = struct { x: usize, y: usize, z: usize }
type Id = struct { x: u32, y: u32, z: u32 }
type FaultKind = enum u8 { Bounds, Null, Tag, Alignment, Overflow, DivideByZero }
type FaultRecord = struct { kernel: u32, kind: FaultKind, site: u32, gid: Id }
type Cap = enum u8 { Int8, Int16, Int64, Float16, Float64, Atomic64, Subgroup, Ftz, DenormPreserve }
type Scope = enum u8 { Workgroup, Device }
type Format = enum u8 { Rgba8, Bgra8 }
type Image = struct { data: Buf[u32], width: u32, height: u32, format: Format }
type SurfaceKind = enum u8 { Offscreen, Win32, X11, Wayland, Cocoa }
type Surface = struct { kind: SurfaceKind, handle: *void, context: *void }
type Target = struct { state: *void }
type Frame = struct { image: Image, serial: u64 }
error NoDevice
error AmbiguousDevice
error Unsupported
error OutOfMemory
error TooLarge
error Lost
error WrongDevice
error InvalidHandle
error Fault
error Outdated

fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err)
fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err)
fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err)
fn info(a: *mem.Arena, device: *Device) -> (DeviceInfo, err)
fn close(device: *Device) -> err
fn has(device: *Device, capability: Cap) -> bool
fn queue(device: *Device) -> (*Queue, err)
fn queue_with(device: *Device, limits: StagingLimits) -> (*Queue, err)
fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err)
fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err)
fn len[T: type](buf: Buf[T]) -> usize
fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err
fn launch[K: fn](q: *Queue, grid: Grid, args: ...) -> err
fn token(q: *Queue) -> (Token, err)
fn wait_for(q: *Queue, dependency: Token) -> err
fn done(token_value: Token) -> (bool, err)
fn wait(token_value: Token) -> err
fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err
fn sync(q: *Queue) -> err
fn last_fault(q: *Queue) -> (FaultRecord, bool)
fn release[T: type](q: *Queue, buf: Buf[T]) -> err
fn grid1(x: usize) -> Grid
fn grid2(x: usize, y: usize) -> Grid
fn grid3(x: usize, y: usize, z: usize) -> Grid
fn image(q: *Queue, width: u32, height: u32, format: Format) -> (Image, err)
fn write_image(q: *Queue, dst: Image, x: u32, y: u32, width: u32, height: u32, src: []const u32) -> err
fn read_image(q: *Queue, src: Image, dst: []u32) -> err
fn release_image(q: *Queue, img: Image) -> err
fn open_target(q: *Queue, surface: Surface, width: u32, height: u32, format: Format) -> (*Target, err)
fn extent(t: *Target) -> (u32, u32)
fn resize(t: *Target, width: u32, height: u32) -> err
fn acquire(t: *Target) -> (Frame, err)
fn present(q: *Queue, t: *Target, frame: Frame) -> (Token, err)
fn presented(t: *Target) -> (Image, err)
fn close_target(t: *Target) -> err
```

Presentation (spec section 10, D791) is images over kernels: an `Image` is a `Buf[u32]`
of packed pixels a kernel writes, a `Target` presents frames to an offscreen pair on
every backend or to a native `Surface` on a driver backend, and there is no
fixed-function pipeline.

Discovery/selection is specified in [spec §10](spec.md#device-discovery-and-selection).
`devices` is a bounded, caller-arena-owned snapshot, including copied names and
capability lists; exceeding the limit fails rather than returning a partial success.
Indices are temporary backend ordinals. `open_id` requires an exact backend-scoped
UUID match, rejects duplicate matches with `AmbiguousDevice`, and never silently
falls back. `key_valid == false` means stable-key selection is unavailable, not that
a fabricated index/name hash may substitute. `info` copies the opening-time descriptor
of the selected device. Memory is reported capacity, not free or reserved storage.
Every queue/buffer belongs to one open device, including when two opens address the
same GPU. A check failing in a kernel writes the queue's one `FaultRecord` and ends
that invocation; the next `sync` or `download` answers `Fault` once and `last_fault`
answers the record behind the last `Fault` the queue reported (D785). These additions are planned for M3 CPU/Vulkan, with CUDA in M4; they do not
claim implementation or an optimized production CPU fallback.

The device-only intrinsics are exactly `gid`, `lid`, `wgid`, `barrier`,
`subgroup_size`, `subgroup_lane`, `subgroup_ballot`, `subgroup_any`, `subgroup_all`,
`subgroup_broadcast`, `subgroup_add`, `subgroup_min`, `subgroup_max`, and the scoped
atomic family specified by spec §10.

### `e.gpu.tensor`

```neper
type Tensor[T: type] = struct { data: gpu.Buf[T], shape: []const usize, stride: []const usize }
error Shape

fn upload[T: type](a: *mem.Arena, queue: *gpu.Queue, src: linalg_tensor.ConstTensor[T]) -> (Tensor[T], err)
fn download[T: type](queue: *gpu.Queue, src: Tensor[T], dst: linalg_tensor.Tensor[T]) -> err
fn add[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err
fn matmul[T: type](queue: *gpu.Queue, dst: Tensor[T], x: Tensor[T], y: Tensor[T]) -> err
fn release[T: type](queue: *gpu.Queue, tensor_view: Tensor[T]) -> err
```

The import of `e.algo.linalg.tensor` uses the deterministic alias `linalg_tensor`.
Every operation is an explicit queue submission; this module never opens a device or
allocates a host arena implicitly.

### `e.test`

```neper
error Failed

fn assert(cond: bool, msg: str) -> err
fn eq[T: type](a: T, b: T, msg: str) -> err
fn near(a: f64, b: f64, abs: f64, rel: f64, msg: str) -> err
fn fail(msg: str) -> err
```

Discovery, process isolation and reporting belong to `neper test`, not this module.

### `e.test.support`

```neper
type Clock = struct { instant: time.Instant, timestamp: time.Timestamp }
type ReadStep = struct { bytes: []const u8, failure: err }
type WriteStep = struct { max_bytes: usize, failure: err }
type ScriptedReader = struct { state: *void }
type ScriptedWriter = struct { state: *void }
type Schedule = struct { state: *void }

fn clock(instant: time.Instant, timestamp: time.Timestamp) -> Clock
fn advance(c: *Clock, elapsed: time.Duration) -> err
fn scripted_reader(a: *mem.Arena, steps: []const ReadStep) -> (ScriptedReader, err)
fn scripted_writer(a: *mem.Arena, steps: []const WriteStep, capacity: usize) -> (ScriptedWriter, err)
fn reader(script: *ScriptedReader) -> io.Reader
fn writer(script: *ScriptedWriter) -> io.Writer
fn captured(script: *const ScriptedWriter) -> []const u8
fn schedule(a: *mem.Arena, turns: []const u64) -> (Schedule, err)
fn checkpoint(s: *Schedule, participant: u64) -> (bool, err)
fn complete(s: *const Schedule) -> bool
```

These are caller-owned deterministic test doubles, never replacements for ambient
OS state. Script steps are copied; input bytes remain borrowed until the scripted
reader is released with its arena. Partial data plus an error is intentional.
Script/capture exhaustion is explicit; no callback runs unboundedly. Clock advance
rejects negative durations and overflow. Schedule is a single-threaded cooperative
test driver: checkpoint advances only the prescribed participant, returning false
for others; exhaustion returns test.Failed. It is not an OS-thread scheduler or race
proof. Production APIs accept explicit clock/I/O/control inputs where applicable.

### `e.test.coverage`

```neper
type Counter = struct { file_id: u32, region_id: u32, hits: u64 }
type Report = struct { counters: []const Counter }
error InvalidProfile
error TooLarge

fn snapshot(dst: []Counter) -> ([]Counter, err)
fn reset()
fn merge(a: *mem.Arena, profiles: []const Report) -> (Report, err)
fn write_json(writer: *io.Writer, report: *const Report) -> err
```

The compiler assigns stable file and region identifiers and owns instrumentation.
This runtime only snapshots, resets, merges and serializes bounded counters.

### `e.test.fuzz`

```neper
type Input = struct { bytes: []const u8, seed: u64 }
type Options = struct { max_input: usize, max_runs: u64, deadline: time.Instant }
type Result = struct { runs: u64, failing: Input, failed: bool }
type Target = fn(input: Input) -> err
error InvalidCorpus
error Limit

fn run(a: *mem.Arena, target_fn: Target, corpus: []const Input, options: Options) -> (Result, err)
fn minimize(a: *mem.Arena, target_fn: Target, failing: Input, deadline: time.Instant) -> (Input, err)
```

Mutation is deterministic from each explicit seed. Corpus persistence, subprocess
isolation and reproduction commands belong to `neper test --fuzz`.

### `e.test.prop`

```neper
type Kind = enum u8 { Int, Bytes, Choice, List }
type Gen = struct { kind: Kind, lo: i64, hi: i64, max_len: usize, choices: []const i64 }
type Value = struct { int: i64, len: usize }
error TooSmall

fn int_gen(lo: i64, hi: i64) -> Gen
fn bytes_gen(max_len: usize) -> Gen
fn choice_gen(choices: []const i64) -> Gen
fn list_gen(max_len: usize, lo: i64, hi: i64) -> Gen
fn gen_int(r: *rand.Pcg64, lo: i64, hi: i64) -> i64
fn gen_bytes(r: *rand.Pcg64, out: []u8, max_len: usize) -> usize
fn gen_choice(r: *rand.Pcg64, choices: []const i64) -> i64
fn gen_list(r: *rand.Pcg64, out: []i64, max_len: usize, lo: i64, hi: i64) -> usize
fn generate(r: *rand.Pcg64, g: Gen, bytes: []u8, ints: []i64) -> Value
fn shrink[Ctx: type](ctx: *Ctx, fails: fn(*Ctx, i64) -> bool, x: i64) -> i64
fn shrink_bytes[Ctx: type](ctx: *Ctx, fails: fn(*Ctx, []const u8) -> bool, data: []u8, len: usize, scratch: []u8) -> (usize, err)
```

Generators (`gen_int`, `gen_bytes`, `gen_choice`, `gen_list` and `Gen` descriptors
through `generate`) and shrinkers (`shrink` toward zero by halving then steps,
`shrink_bytes` by delta debugging then per-byte).

### `e.test.sim`

```neper
type Message = struct { from: u32, to: u32, kind: u32, value: i64, due: u64 }
type Sim = struct { actors: usize, pool: []Message, in_flight: []u8, rng: rand.Pcg64, clock: u64, max_delay: u64, drop_per_mille: u64, delivered: u64, dropped: u64, trace: u64 }
error TooSmall
error Invalid

fn mix(h: u64, v: u64) -> u64
fn sim(actors: usize, pool: []Message, in_flight: []u8, seed: u64, max_delay: u64, drop_per_mille: u64) -> Sim
fn enqueue(s: *Sim, m: Message) -> err
fn send(s: *Sim, from: u32, to: u32, kind: u32, value: i64) -> err
fn timer(s: *Sim, actor: u32, delay: u64, kind: u32, value: i64) -> err
fn pending(s: *const Sim) -> usize
fn choose(s: *Sim) -> (usize, bool)
fn run[Ctx: type](s: *Sim, ctx: *Ctx, steps: usize, step: fn(*Ctx, *Sim, u32, Message)) -> usize
```

A deterministic simulation scheduler: actors with a caller message pool, seeded
delays and drops, timers, `run` over a step callback, and a delivery trace hash that
replays per seed.

### `e.test.linearize`

```neper
type Op = enum u8 { Read, Write, Cas }
type Model = enum u8 { Register, Counter, Set }
type Event = struct { call_time: u64, return_time: u64, op: Op, arg: i64, arg2: i64, result: i64 }
error TooSmall
error Invalid

fn step(model: Model, state: i64, e: Event) -> (i64, bool)
fn search(history: []const Event, model: Model, state: i64, placed: []u8, remaining: usize) -> bool
fn check(history: []const Event, model: Model, initial: i64, placed: []u8) -> (bool, err)
```

`check`: Wing-Gong backtracking linearizability of a history of timed calls against a
register, counter or set model.

### `e.debug`

```neper
type Frame = struct { address: usize, function: str, file: str, line: u32 }

fn backtrace(dst: []Frame) -> []Frame
fn symbolize(address: usize) -> Frame
```

Both functions allocate nothing. Missing symbol data yields empty strings and line
zero while preserving the address.

---

## 7. Application facilities and networking

### `e.metrics`

```neper
type Counter = struct { value: Atomic[u64] }
type Gauge = struct { value: Atomic[i64] }
type Histogram = struct { bounds: []const f64, counts: []Atomic[u64], sum_bits: Atomic[u64] }
type Snapshot = struct { count: u64, sum: f64, buckets: []const u64 }
error Invalid

fn counter() -> Counter
fn counter_add(c: *Counter, value: u64)
fn counter_get(c: *Counter) -> u64
fn gauge() -> Gauge
fn gauge_set(g: *Gauge, value: i64)
fn gauge_add(g: *Gauge, value: i64)
fn gauge_get(g: *Gauge) -> i64
fn histogram(a: *mem.Arena, bounds: []const f64) -> (Histogram, err)
fn histogram_observe(h: *Histogram, value: f64)
fn histogram_snapshot(a: *mem.Arena, h: *const Histogram) -> (Snapshot, err)
```

Bounds must be finite and strictly increasing. The final implicit bucket is positive
infinity.

### `e.log`

```neper
type Level = enum u8 { Trace, Debug, Info, Warn, Error }
type Value = union enum u8 { Bool: bool, I64: i64, U64: u64, F64: f64, String: str, Error: err }
type Field = struct { name: str, value: Value }
type Record = struct { timestamp: time.Timestamp, level: Level, message: str, fields: []const Field, frames: []const debug.Frame }
type Sink = struct { ctx: *void, write: fn(*void, *const Record) -> err }
type Logger = struct { sinks: []const Sink, minimum: Level }

fn logger(sinks: []const Sink, minimum: Level) -> Logger
fn enabled(l: *const Logger, level: Level) -> bool
fn write(l: *Logger, level: Level, message: str, fields: []const Field) -> err
fn write_with_backtrace(l: *Logger, level: Level, message: str, fields: []const Field, scratch: []debug.Frame) -> err
fn console_sink(file: *os.File) -> Sink
fn jsonl_sink(writer: *io.Writer) -> Sink
```

The caller owns every string and field until all synchronous sink calls return. There
is no global logger.

### `e.cli`

```neper
type ValueKind = enum u8 { Bool, I64, U64, F64, String }
type Option = struct { long: str, short: u8, kind: ValueKind, required: bool, repeated: bool, env: str, help: str }
type Command = struct { name: str, help: str, options: []const Option, subcommands: []const Command }
type Value = union enum u8 { Bool: bool, I64: i64, U64: u64, F64: f64, String: str }
type ParsedOption = struct { name: str, values: []const Value }
type Result = struct { command: str, options: []const ParsedOption, positionals: []const str }
error InvalidSpec
error InvalidArgument
error Missing
error Unknown

fn validate(command: *const Command) -> err
fn parse(a: *mem.Arena, command: *const Command, args: []const str) -> (Result, err)
fn parse_into[T: type](a: *mem.Arena, args: []const str) -> (T, err)
fn option(result: *const Result, name: str) -> (ParsedOption, bool)
fn help(a: *mem.Arena, command: *const Command, width: u16) -> (str, err)
```

`parse_into` uses `e.meta` field shape and field-owned parsing protocols; it does not
introduce runtime reflection.

### `e.async`

```neper
type Loop = struct { state: *void }
type Token = struct { value: usize }
type Interest = struct { readable: bool, writable: bool }
type Event = struct { token: Token, readable: bool, writable: bool, closed: bool, failed: bool }
error Unsupported
error Invalid

fn init(a: *mem.Arena) -> (Loop, err)
fn register(loop: *Loop, handle: os.Handle, token: Token, interest: Interest) -> err
fn modify(loop: *Loop, handle: os.Handle, token: Token, interest: Interest) -> err
fn unregister(loop: *Loop, handle: os.Handle) -> err
fn poll(loop: *Loop, events: []Event, timeout: time.Duration) -> (usize, err)
fn wake(loop: *Loop) -> err
fn close(loop: *Loop) -> err
```

This is readiness/completion polling only. It introduces no futures, coroutines,
scheduler, callback registry or hidden state-machine transformation.

### `e.async.io`

```neper
type Op[T: type] = struct { state: *void }
type AnyOp = struct { state: *void }
type State = enum u8 { Pending, Succeeded, Failed, Cancelled, TimedOut }
error Cancelled
error Timeout
error Closed

fn read(a: *mem.Arena, loop: *async.Loop, source: io.Reader, dst: []u8, control: cancel_api.Control) -> (Op[usize], err)
fn write(a: *mem.Arena, loop: *async.Loop, sink: io.Writer, src: []const u8, control: cancel_api.Control) -> (Op[usize], err)
fn accept(a: *mem.Arena, loop: *async.Loop, listener: os.Socket, control: cancel_api.Control) -> (Op[os.Socket], err)
fn connect(a: *mem.Arena, loop: *async.Loop, socket: os.Socket, address: os.SocketAddress, control: cancel_api.Control) -> (Op[bool], err)
fn state[T: type](op: *const Op[T]) -> State
fn erase[T: type](op: *Op[T]) -> AnyOp
fn take[T: type](op: *Op[T]) -> (T, err)
fn wait[T: type](loop: *async.Loop, op: *Op[T]) -> (T, err)
fn wait_any(loop: *async.Loop, ops: []AnyOp, timeout: time.Duration) -> (usize, bool, err)
fn cancel[T: type](op: *Op[T]) -> (bool, err)
type Progress = struct { bytes: u64, known: bool }
fn progress[T: type](op: *const Op[T]) -> Progress

```

Submission never blocks and every operation completes exactly once. Buffers, handles,
contexts and cancellation tokens must outlive completion. Control uses e.cancel's explicit deadline flag. cancel returns whether it newly
requested cancellation; it does not acknowledge completion. A completed operation
wins a later cancellation request. Otherwise cancellation is cooperative and the
terminal state reports Cancelled/TimedOut with observable partial effects preserved.
No consumed bytes or transmitted bytes are silently reported as rolled back. `wait` drives
the supplied loop; applications may instead poll it directly. `take` consumes a
completed operation and returns its exact I/O error. `erase` is a non-owning typed
conversion used only to build a heterogeneous `wait_any` slice; the original `Op[T]`
must remain live.


Progress is a monotonic observation, not completion acknowledgement. Byte operations
report exact completed bytes at terminal state even on failure/cancellation; operations
without a byte metric report known=false. take remains mandatory to consume a terminal
operation. An uncancellable blocking callback cannot be advertised as promptly
cancellable: reject an incompatible submission or keep resources pinned until it ends.

### `e.net`

```neper
type Socket = os.Socket
type Ip4 = struct { bytes: [4]u8 }
type Ip6 = struct { bytes: [16]u8, scope: u32 }
type Address = union enum u8 { Ip4: Ip4, Ip6: Ip6 }
type Endpoint = struct { address: Address, port: u16 }
type Family = enum u8 { Any, Ip4, Ip6 }
type Shutdown = enum u8 { Read, Write, Both }
error NotFound
error Refused
error Reset
error Timeout
error AddressInUse
error Unreachable
error Failed

fn parse_ip(s: str) -> (Address, err)
fn format_ip(address: Address, dst: []u8) -> (str, err)
fn resolve(a: *mem.Arena, host: str, port: u16, family: Family) -> ([]Endpoint, err)
fn tcp_connect(endpoint: Endpoint) -> (Socket, err)
fn tcp_listen(endpoint: Endpoint, backlog: u32) -> (Socket, err)
fn tcp_accept(listener: Socket) -> (Socket, Endpoint, err)
fn udp_bind(endpoint: Endpoint) -> (Socket, err)
fn receive(socket: Socket, dst: []u8) -> (usize, err)
fn send(socket: Socket, src: []const u8) -> (usize, err)
fn receive_from(socket: Socket, dst: []u8) -> (usize, Endpoint, err)
fn send_to(socket: Socket, dst: Endpoint, src: []const u8) -> (usize, err)
fn shutdown(socket: Socket, how: Shutdown) -> err
fn close(socket: own Socket) -> err
fn reader(socket: *Socket) -> io.Reader
fn writer(socket: *Socket) -> io.Writer
fn resolve_with_control(a: *mem.Arena, host: str, port: u16, family: Family, control: cancel.Control) -> ([]Endpoint, err)
fn tcp_connect_with_control(endpoint: Endpoint, control: cancel.Control) -> (Socket, err)
fn receive_with_control(socket: Socket, dst: []u8, control: cancel.Control) -> (usize, err)
fn send_with_control(socket: Socket, src: []const u8, control: cancel.Control) -> (usize, err)

```

`parse_ip` accepts strict dotted-decimal IPv4 and RFC 4291 IPv6 literals, including
embedded IPv4 and an optional numeric `%scope` suffix. Ambiguous IPv4 leading zeroes,
interface-name scopes and trailing text are rejected. `format_ip` uses lowercase RFC
5952-style hexadecimal, suppresses leading zeroes and compresses the first longest run
of at least two zero groups. A nonzero scope is emitted as decimal. The returned string
borrows `dst`; insufficient destination space fails without allocation.

The blocking transport functions are thin portable ownership and error-mapping wrappers
over `e.os` sockets. `tcp_listen` and `udp_bind` open and bind the requested address;
failure closes the new socket. `tcp_accept` reports the peer endpoint. `reader` maps an
orderly zero-byte stream receive to `io.End`; `writer` retries nothing and leaves partial
write handling to `io.write_all`. `resolve(Family.Any)` returns IPv4 answers followed by
IPv6 answers, with the caller's port attached, and keeps at most the platform fence's
bounded result set. No function silently enables nonblocking mode.


Controlled operations use e.cancel and preserve byte counts on failure. DNS may
require bounded worker isolation; completion is not acknowledged while caller-owned
buffers remain in use. Unsupported cancellation guarantees are reported explicitly,
not implemented as a blocking call ignoring its deadline.

The controlled socket operations temporarily use nonblocking mode and the `e.os` poller,
observing the token/deadline at intervals no greater than one millisecond. Completion of
a host transfer wins a later request; a wait observes cancellation before timeout and
restores blocking mode before acknowledging either. The synchronous host resolver cannot
provide that bound: after the common precheck, a still-live token or deadline returns
`os.Unsupported`; an uncontrolled `Control` uses the ordinary resolver.

### `e.net.tls`

```neper
type Version = enum u8 { Tls13 }
type ClientConfig = struct { server_name: str, trust_roots: []const u8, alpn: []const str, entropy: []const u8, now: time.Timestamp }
type ServerConfig = struct { certificate_chain: []const u8, private_key: []const u8, alpn: []const str, entropy: []const u8 }
type Stream = struct { state: *void }
error InvalidCertificate
error Handshake
error Protocol
error Closed
error Unsupported

fn client(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ClientConfig) -> (Stream, err)
fn server(a: *mem.Arena, source: io.Reader, sink: io.Writer, config: ServerConfig) -> (Stream, err)
fn handshake(stream: *Stream) -> err
fn reader(stream: *Stream) -> io.Reader
fn writer(stream: *Stream) -> io.Writer
fn protocol(stream: *const Stream) -> Version
fn negotiated_alpn(stream: *const Stream) -> str
fn close(stream: *Stream) -> err
fn handshake_with_control(stream: *Stream, control: cancel.Control) -> err

```

Version 1 implements TLS 1.3 only. Trust roots, certificate time and entropy are
explicit inputs; the module never reads host trust state, clocks or randomness.
Certificate and key inputs are bounded DER encodings. The cryptographic algorithms
and validation profiles supported by a toolchain release are reported by `neper info`
and tested against published protocol and malformed-peer vectors.


The release contract must name its cipher suites, signature/certificate algorithms,
key schedule and entropy requirements; reporting merely TLS 1.3 is insufficient.
HKDF/HMAC come from reviewed e.crypto.kdf/e.crypto.mac surfaces. SHA-384-based suites
cannot be advertised until SHA-384/HKDF-SHA384 exists. Ed25519 and P-256/SHA-256 do
not establish compatibility with RSA, P-384 or other public-Web certificate chains;
those profiles require explicit reviewed additions or remain unsupported.
Do not silently weaken certificate/hostname verification to improve connectivity.
Entropy seeds require sufficient fresh caller entropy per independent handshake;
copied/reused config bytes are not permission to repeat ephemeral randomness.

The delivered profile is TLS 1.3 with `TLS_AES_128_GCM_SHA256`, X25519 key exchange,
Ed25519 plus ECDSA P-256/SHA-256 verification, and X.509 chains supplied as concatenated
DER (leaf first for a server, roots for a client). Server private keys remain Ed25519
PKCS#8 under RFC 8410. The SHA-256 key
schedule composes `e.crypto.kdf`/`e.crypto.mac`; each independent handshake requires
at least 64 fresh caller bytes, split into its random and ephemeral secret. Certificate
messages are capped at 16 KiB and verified to depth eight. RSA, P-384, SHA-384 suites,
client certificates, PSK, resumption, 0-RTT and post-handshake authentication are
unsupported. Constructors remain inert; `reader` and `writer` expose no plaintext
until `handshake` succeeds, and `close` exchanges an authenticated close notification.

### `e.net.http`

```neper
type Method = enum u8 { Get, Head, Post, Put, Patch, Delete, Options, Connect, Trace }
type Version = enum u8 { Http10, Http11 }
type Header = struct { name: str, value: str }
type Request = struct { method: Method, target: str, version: Version, headers: []const Header, body: []const u8 }
type Response = struct { version: Version, status: u16, reason: str, headers: []const Header, body: []const u8 }
type Limits = struct { start_line: usize, header_bytes: usize, header_count: usize, body_bytes: usize }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer }
error Invalid
error TooLarge
error Unsupported

fn reader(a: *mem.Arena, source: io.Reader, limits: Limits) -> (Reader, err)
fn writer(sink: io.Writer) -> Writer
fn read_request(a: *mem.Arena, r: *Reader) -> (Request, err)
fn read_response(a: *mem.Arena, r: *Reader) -> (Response, err)
fn write_request(w: *Writer, req: *const Request) -> err
fn write_response(w: *Writer, response: *const Response) -> err
fn request(a: *mem.Arena, endpoint: net.Endpoint, req: *const Request, limits: Limits) -> (Response, err)
fn request_tls(a: *mem.Arena, endpoint: net.Endpoint, config: tls.ClientConfig, req: *const Request, limits: Limits) -> (Response, err)
fn header(headers: []const Header, name: str) -> (str, bool)
fn reason(status: u16) -> str
type ResponseHead = struct { version: Version, status: u16, reason: str, headers: []const Header }
type ResponseStream = struct { state: *void }
type SseEvent = struct { event: str, data: str, id: str, has_id: bool, retry_ms: u64, has_retry: bool }
type SseState = struct { id: str, has_id: bool, retry_ms: u64, has_retry: bool }
type SseReader = struct { state: *void }
type SseLimits = struct { line_bytes: usize, event_bytes: usize }

fn request_stream(a: *mem.Arena, endpoint: net.Endpoint, req: *const Request, limits: Limits, control: cancel.Control) -> (ResponseStream, err)
fn request_tls_stream(a: *mem.Arena, endpoint: net.Endpoint, config: tls.ClientConfig, req: *const Request, limits: Limits, control: cancel.Control) -> (ResponseStream, err)
fn response_head(stream: *const ResponseStream) -> ResponseHead
fn response_read(stream: *ResponseStream, dst: []u8) -> (usize, err)
fn response_close(stream: *ResponseStream) -> err
fn sse_reader(a: *mem.Arena, source: io.Reader, limits: SseLimits) -> (SseReader, err)
fn sse_next_err(it: *SseReader) -> (SseEvent, bool, err)
fn sse_state(it: *const SseReader) -> SseState

```

Chunked transfer encoding is supported. `request_tls` performs and verifies one TLS
connection using the explicit configuration. Automatic redirects, cookies,
compression and connection pooling remain outside the version-1 surface.

The delivered plain `request` opens one TCP connection, writes one request, reads one
bounded full response and closes the connection on every path. HEAD retains response
headers but consumes no body; CONNECT returns Unsupported because its successful result
is a tunnel rather than a full HTTP response. `request_stream` provides the controlled
incremental form over plain TCP. `request_tls` and `request_tls_stream` provide the
matching verified TLS forms with caller-supplied trust, time, entropy and control.

ResponseStream owns the connection; headers borrow its arena and response_read
incrementally decodes framing without buffering a complete body. Limits.body_bytes
is a total transfer cap (zero permits no body), not a mandatory allocation. Control
applies through reads/close; closing early disposes the connection without draining
an unbounded peer. No automatic replay, redirect or credential forwarding.
Existing convenience request functions remain bounded full-body wrappers.
SSE incrementally handles UTF-8, CR/LF/CRLF, comments, repeated data lines, id,
event and decimal retry fields under the standard event-stream algorithm. Returned
fields borrow reader storage until next call. The decoder ignores an initial UTF-8
BOM and replaces malformed UTF-8 with U+FFFD. An id containing NUL and a
non-decimal retry field are ignored; a valid decimal retry exceeding u64 or an
exceeded size limit fails TooLarge. EOF does not dispatch an unterminated event.
The reader retains valid id/retry updates even in blocks without data;
sse_state exposes that state, including after EOF. Its strings have the same
borrow lifetime as event fields. Event id/retry fields report the effective
retained values; has_id records whether a valid id was seen, including an empty
id that resets it. Reconnection, persistence across readers and retry policy
belong to the caller. An io.Reader adapter can wrap response_read for SSE; its
lifetime and cancellation remain those of ResponseStream.

### `e.net.ws`

```neper
type Opcode = enum u8 { Continuation, Text, Binary, Close, Ping, Pong }
type Frame = struct { final: bool, opcode: Opcode, payload: []const u8 }
type Connection = struct { state: *void }
error InvalidHandshake
error InvalidFrame
error TooLarge
error Closed

fn client_key(entropy: [16]u8, dst: []u8) -> (str, err)
fn client_upgrade(a: *mem.Arena, stream: io.Reader, sink: io.Writer, host: str, target_path: str, entropy: [16]u8) -> (Connection, err)
fn server_upgrade(a: *mem.Arena, stream: io.Reader, sink: io.Writer, request: *const http.Request) -> (Connection, err)
fn receive(a: *mem.Arena, connection: *Connection, limit: usize) -> (Frame, err)
fn send(connection: *Connection, frame: Frame, mask: [4]u8) -> err
fn ping(connection: *Connection, payload: []const u8, mask: [4]u8) -> err
fn close(connection: *Connection, code: u16, reason: str, mask: [4]u8) -> err
```

Client masking material and handshake entropy are caller-supplied. The module never
reads OS randomness implicitly.

The delivered surface uses allocation-free standard padded Base64 over exactly the
sixteen supplied entropy bytes. Both upgrade directions validate the bounded RFC 6455
HTTP exchange and preserve the first frame boundary. `receive` enforces role masking,
minimal lengths, control bounds and fragmentation state while allocating only the
accepted payload in the caller arena. `send`, `ping` and `close` provide bounded output,
including extended lengths and fragmentation state.

### `e.db`

```neper
type Connection = struct { ctx: *void, driver: *const Driver }
type Statement = struct { ctx: *void, driver: *const Driver }
type Rows = struct { ctx: *void, driver: *const Driver }
type Transaction = struct { ctx: *void, driver: *const Driver }
type Value = union enum u8 { Null, Bool: bool, I64: i64, U64: u64, F64: f64, Text: str, Bytes: []const u8, Time: time.Instant }
type Parameter = struct { name: str, value: Value }
type Column = struct { name: str, kind: ValueKind, nullable: bool }
type ValueKind = enum u8 { Null, Bool, I64, U64, F64, Text, Bytes, Time }
type Driver = struct { close: fn(ctx: *void) -> err, prepare: fn(ctx: *void, sql: str) -> (Statement, err), execute: fn(ctx: *void, sql: str, params: []const Parameter) -> (u64, err), query: fn(ctx: *void, sql: str, params: []const Parameter) -> (Rows, err), begin: fn(ctx: *void) -> (Transaction, err), statement_close: fn(ctx: *void) -> err, statement_execute: fn(ctx: *void, params: []const Parameter) -> (u64, err), statement_query: fn(ctx: *void, params: []const Parameter) -> (Rows, err), rows_columns: fn(ctx: *void) -> []const Column, rows_next: fn(ctx: *void, dst: []Value) -> (bool, err), rows_close: fn(ctx: *void) -> err, transaction_execute: fn(ctx: *void, sql: str, params: []const Parameter) -> (u64, err), transaction_query: fn(ctx: *void, sql: str, params: []const Parameter) -> (Rows, err), transaction_commit: fn(ctx: *void) -> err, transaction_rollback: fn(ctx: *void) -> err }
error Closed
error InvalidQuery
error Constraint
error Busy
error Unsupported

fn close(connection: *Connection) -> err
fn prepare(connection: *Connection, sql: str) -> (Statement, err)
fn execute(connection: *Connection, sql: str, params: []const Parameter) -> (u64, err)
fn query(connection: *Connection, sql: str, params: []const Parameter) -> (Rows, err)
fn close_statement(statement: *Statement) -> err
fn execute_statement(statement: *Statement, params: []const Parameter) -> (u64, err)
fn query_statement(statement: *Statement, params: []const Parameter) -> (Rows, err)
fn columns(rows: *Rows) -> []const Column
fn reader_next_err(rows: *Rows, dst: []Value) -> (bool, err)
fn close_rows(rows: *Rows) -> err
fn begin(connection: *Connection) -> (Transaction, err)
fn execute_transaction(transaction: *Transaction, sql: str, params: []const Parameter) -> (u64, err)
fn query_transaction(transaction: *Transaction, sql: str, params: []const Parameter) -> (Rows, err)
fn commit(transaction: *Transaction) -> err
fn rollback(transaction: *Transaction) -> err
```

`e.db` defines the generic SQL connection, prepared-statement, transaction and
streaming row-reader contract. Concrete database drivers are owner-qualified
packages—initially `x.sqlite.sqlite`, `x.oracle.mysql` and
`x.postgresql.libpq`; queries, parameters and row buffers are always explicit, and the module
does not discover drivers or allocate hidden connection pools.

---

## 8. Declarative GPU UI

### `e.gfx.curve`

```neper
type Point = struct { x: f64, y: f64, z: f64 }
error Invalid
error TooSmall
const MAX_DEGREE: usize = 15usize

fn point(x: f64, y: f64, z: f64) -> Point
fn lerp(a: Point, b: Point, t: f64) -> Point
fn distance(a: Point, b: Point) -> f64
fn bezier(points: []const Point, scratch: []Point, t: f64) -> (Point, err)
fn bezier_split(points: []const Point, t: f64, left: []Point, right: []Point) -> err
fn span_of(knots: []const f64, degree: usize, count: usize, t: f64) -> usize
fn bspline(points: []const Point, knots: []const f64, degree: usize, t: f64) -> (Point, err)
fn uniform_knots(count: usize, degree: usize, out: []f64) -> err
fn catmull_rom(points: []const Point, t: f64, alpha: f64) -> (Point, err)
fn ratio(s: f64, lo: f64, hi: f64) -> f64
fn basis(knots: []const f64, degree: usize, k: usize, t: f64, out: []f64)
fn nurbs_surface(grid: []const Point, weights: []const f64, count_u: usize, count_v: usize, knots_u: []const f64, knots_v: []const f64, degree_u: usize, degree_v: usize, u: f64, v: f64) -> (Point, err)
```

`bezier` (de Casteljau) and `bezier_split`, `bspline` (de Boor) with `uniform_knots`,
`catmull_rom` (Barry-Goldman, centripetal by default) and `nurbs_surface`.

### `e.gfx.mesh`

```neper
type HalfEdge = struct { vertex: []u32, twin: []u32, next: []u32, face: []u32, count: usize, sides: usize }
type BooleanOp = enum u8 { Union, Intersection, Difference }
type Csg = struct { tri: []f64, plane: []f64, link: []u32, tri_count: usize, node_plane: []f64, node_front: []u32, node_back: []u32, node_polys: []u32, node_count: usize }
type Operator = struct { triangles: []const u32, cot: []const f64, mass: []const f64, t: f64, kind: usize, pin_a: usize, pin_b: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32
const OP_HEAT: usize = 0usize
const OP_POISSON: usize = 1usize
const OP_LSCM: usize = 2usize

fn infinity() -> f64
fn csg_epsilon() -> f64
fn point(v: []const f64, i: usize) -> g3.Vec3
fn put(v: []f64, i: usize, p: g3.Vec3)
fn add_to(v: []f64, i: usize, p: g3.Vec3)
fn fill(v: []f64, x: f64)
fn fill_u32(v: []u32, x: u32)
fn face_normal(vertices: []const f64, triangles: []const u32, f: usize) -> g3.Vec3
fn volume(vertices: []const f64, triangles: []const u32) -> f64
fn soup_volume(soup: []const f64) -> f64
fn half_edge(faces: []const u32, sides: usize, vertex: []u32, twin: []u32, next_he: []u32, face: []u32, scratch: []u32) -> (HalfEdge, err)
fn edge_key(h: *HalfEdge, e: usize) -> u64
fn edge_order(h: *HalfEdge, a: u32, b: u32) -> i32
fn is_closed(h: *HalfEdge) -> bool
fn number_edges(h: *HalfEdge, base: usize, ids: []u32) -> usize
fn vertex_normals(vertices: []const f64, triangles: []const u32, normals: []f64) -> err
fn estimate_normals(points: []const f64, k: usize, normals: []f64, near: []u32, near_d: []f64) -> err
fn smallest_eigenvector(m: []f64) -> g3.Vec3
fn laplacian_step(vertices: []f64, triangles: []const u32, factor: f64, scratch: []f64) -> err
fn smooth_laplacian(vertices: []f64, triangles: []const u32, lambda: f64, iterations: usize, scratch: []f64) -> err
fn smooth_taubin(vertices: []f64, triangles: []const u32, lambda: f64, mu: f64, iterations: usize, scratch: []f64) -> err
fn boundary_rule(h: *HalfEdge, vertices: []const f64, acc: []f64, valence: []u32)
fn subdivide_loop(vertices: []const f64, triangles: []const u32, out_vertices: []f64, out_triangles: []u32, scratch: []u32) -> (usize, usize, err)
fn subdivide_catmull_clark(vertices: []const f64, quads: []const u32, out_vertices: []f64, out_quads: []u32, scratch: []u32) -> (usize, usize, err)
fn quadric_optimum(q: []const f64, a: g3.Vec3, b: g3.Vec3) -> (g3.Vec3, f64)
fn quadric_error(q: []const f64, p: g3.Vec3) -> f64
fn decimate(vertices: []f64, triangles: []u32, goal: usize, quadrics: []f64, scratch: []u32) -> (usize, usize, err)
fn marching_squares(field: []const f64, width: usize, height: usize, iso: f64, out: []f64) -> (usize, err)
fn cube_corners() -> str
fn cube_edges() -> str
fn cube_table() -> str
fn marching_cubes(field: []const f64, nx: usize, ny: usize, nz: usize, iso: f64, out: []f64) -> (usize, err)
fn dual_contouring[Ctx: type](ctx: *Ctx, sdf: fn(*Ctx, f64, f64, f64) -> f64, nx: usize, ny: usize, nz: usize, x0: f64, y0: f64, z0: f64, cell: f64, out_vertices: []f64, out_triangles: []u32, field: []f64, scratch: []u32) -> (usize, usize, err)
fn signed_distance(vertices: []const f64, triangles: []const u32, x: f64, y: f64, z: f64) -> f64
fn fast_marching_update(vertices: []const f64, ta: f64, tb: f64, a: usize, b: usize, c: usize) -> f64
fn geodesic_fast_marching(vertices: []const f64, triangles: []const u32, source: u32, distance: []f64, state: []u8) -> err
fn cotangents(vertices: []const f64, triangles: []const u32, cot: []f64, mass: []f64)
fn apply(op: *const Operator, x: []const f64, y: []f64)
fn conjugate_gradient(op: *const Operator, b: []const f64, x: []f64, r: []f64, p: []f64, q: []f64, iterations: usize)
fn geodesic_heat(vertices: []const f64, triangles: []const u32, source: u32, iterations: usize, distance: []f64, scratch: []f64) -> err
fn parameterize_lscm(vertices: []const f64, triangles: []const u32, pin_a: u32, pin_b: u32, iterations: usize, uv: []f64, scratch: []f64) -> err
fn ball_centre(points: []const f64, normals: []const f64, rho: f64, i: usize, j: usize, k: usize) -> (bool, g3.Vec3)
fn ball_empty(points: []const f64, centre: g3.Vec3, rho: f64, i: usize, j: usize, k: usize) -> bool
fn front_edge(edges: []u32, count: *usize, a: u32, b: u32, c: u32) -> err
fn push_triangle(out: []u32, count: *usize, a: u32, b: u32, c: u32) -> err
fn reconstruct_ball_pivot(points: []const f64, normals: []const f64, rho: f64, out_triangles: []u32, scratch: []u32) -> (usize, err)
fn reconstruct_poisson(points: []const f64, normals: []const f64, nx: usize, ny: usize, nz: usize, x0: f64, y0: f64, z0: f64, cell: f64, iterations: usize, field: []f64, scratch: []f64) -> (f64, err)
fn csg(tri: []f64, plane: []f64, link: []u32, node_plane: []f64, node_front: []u32, node_back: []u32, node_polys: []u32) -> Csg
fn csg_triangle(c: *Csg, a: g3.Vec3, b: g3.Vec3, d: g3.Vec3) -> (u32, err)
fn csg_node(c: *Csg) -> (u32, err)
fn csg_push(c: *Csg, head: *u32, t: u32)
fn csg_concat(c: *Csg, a: u32, b: u32) -> u32
fn csg_has_plane(c: *Csg, node: u32) -> bool
fn csg_split(c: *Csg, node: u32, t: u32, coplanar_front: *u32, coplanar_back: *u32, front: *u32, back: *u32) -> err
fn csg_build(c: *Csg, node: u32, list: u32) -> err
fn csg_invert(c: *Csg, node: u32)
fn csg_clip_polygons(c: *Csg, node: u32, list: u32) -> (u32, err)
fn csg_clip_to(c: *Csg, node: u32, other: u32) -> err
fn csg_all_polygons(c: *Csg, node: u32, list: *u32)
fn csg_load(c: *Csg, vertices: []const f64, triangles: []const u32) -> (u32, err)
fn boolean_bsp(c: *Csg, a_vertices: []const f64, a_triangles: []const u32, b_vertices: []const f64, b_triangles: []const u32, op: BooleanOp, out: []f64) -> (usize, err)
fn revolve(profile: []const f64, segments: usize, out_vertices: []f64, out_triangles: []u32) -> (usize, usize, err)
```

Over indexed triangle (and quad) meshes in caller arrays: `half_edge` with `is_closed`,
`vertex_normals`, `estimate_normals` (PCA over k nearest), `smooth_laplacian`,
`smooth_taubin`, `subdivide_loop`, `subdivide_catmull_clark`, `decimate` (quadric edge
collapse), `marching_squares`, `marching_cubes` (a generated 256-case table),
`dual_contouring` over a caller SDF, `signed_distance` (pseudo-normal sign),
`geodesic_fast_marching`, `geodesic_heat`, `parameterize_lscm`,
`reconstruct_ball_pivot`, `reconstruct_poisson` (one uniform grid), `boolean_bsp`
(csg.js over caller pools), `revolve`, `volume`.

### `e.gfx.raster`

```neper
type Pixel = struct { x: i32, y: i32 }
type Coverage = struct { x: i32, y: i32, coverage: f64 }
error TooSmall

fn push(out: []Pixel, n: *usize, x: i32, y: i32) -> err
fn abs32(v: i32) -> i32
fn line(x0: i32, y0: i32, x1: i32, y1: i32, out: []Pixel) -> (usize, err)
fn push_aa(out: []Coverage, n: *usize, x: i32, y: i32, c: f64) -> err
fn floor64(v: f64) -> f64
fn round64(v: f64) -> f64
fn fpart(v: f64) -> f64
fn rfpart(v: f64) -> f64
fn pair(out: []Coverage, n: *usize, steep: bool, major: f64, minor: f64, gap: f64) -> err
fn line_aa(x0: f64, y0: f64, x1: f64, y1: f64, out: []Coverage) -> (usize, err)
fn octants(out: []Pixel, n: *usize, cx: i32, cy: i32, x: i32, y: i32) -> err
fn circle(cx: i32, cy: i32, radius: i32, out: []Pixel) -> (usize, err)
fn quadrants(out: []Pixel, n: *usize, cx: i32, cy: i32, x: i32, y: i32) -> err
fn ellipse(cx: i32, cy: i32, rx: i32, ry: i32, out: []Pixel) -> (usize, err)
fn edge(ax: f64, ay: f64, bx: f64, by: f64, px: f64, py: f64) -> f64
fn top_left(ax: f64, ay: f64, bx: f64, by: f64) -> bool
fn fill_triangle(x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, out: []Pixel) -> (usize, err)
```

`line` (Bresenham), `line_aa` (Xiaolin Wu coverage), `circle` and `ellipse` (midpoint)
and `fill_triangle` (edge functions with the top-left rule), each appending to a caller
pixel list.

### `e.gfx.shade`

```neper
type Vec3 = struct { x: f64, y: f64, z: f64 }
type Rgb = struct { red: f64, green: f64, blue: f64 }

fn pi() -> f64
fn vec3(x: f64, y: f64, z: f64) -> Vec3
fn rgb(red: f64, green: f64, blue: f64) -> Rgb
fn add(a: Vec3, b: Vec3) -> Vec3
fn sub(a: Vec3, b: Vec3) -> Vec3
fn scale(a: Vec3, s: f64) -> Vec3
fn dot(a: Vec3, b: Vec3) -> f64
fn cross(a: Vec3, b: Vec3) -> Vec3
fn length(a: Vec3) -> f64
fn rgb_scale(c: Rgb, s: f64) -> Rgb
fn rgb_mul(a: Rgb, b: Rgb) -> Rgb
fn rgb_add(a: Rgb, b: Rgb) -> Rgb
fn normalize(a: Vec3) -> Vec3
fn alpha_of(roughness: f64) -> f64
fn brdf_lambert(albedo: Rgb) -> Rgb
fn fresnel_schlick(cos_theta: f64, f0: Rgb) -> Rgb
fn ggx_d(n_dot_h: f64, roughness: f64) -> f64
fn ggx_v(n_dot_v: f64, n_dot_l: f64, roughness: f64) -> f64
fn brdf_ggx(n: Vec3, v: Vec3, l: Vec3, roughness: f64, f0: Rgb) -> Rgb
fn onb(n: Vec3) -> (Vec3, Vec3)
fn ggx_sample(r: *rand.Pcg64, roughness: f64, n: Vec3) -> Vec3
fn reflect(v: Vec3, h: Vec3) -> Vec3
fn ggx_pdf(n: Vec3, v: Vec3, h: Vec3, roughness: f64) -> f64
```

`brdf_ggx` (GGX distribution, height-correlated Smith visibility, Schlick Fresnel),
`brdf_lambert`, `fresnel_schlick`, `ggx_sample` with `ggx_pdf`, `reflect` and an
orthonormal basis.

### `e.gfx.trace`

```neper
type Sphere = struct { center: shade.Vec3, radius: f64, albedo: shade.Rgb, emission: shade.Rgb }
type Camera = struct { origin: shade.Vec3, forward: shade.Vec3, right: shade.Vec3, up: shade.Vec3, tan_half: f64 }
type Ray = struct { origin: shade.Vec3, direction: shade.Vec3 }
type Job = struct { spheres: []const Sphere, camera: Camera, width: usize, height: usize, samples: usize, max_depth: usize, roulette_depth: usize }
type Mode = enum u8 { Naive, Nee, Mis }
type CsgKind = enum u8 { Sphere, Box, Union, Intersection, Difference }
type CsgNode = struct { kind: CsgKind, left: u32, right: u32, center: shade.Vec3, radius: f64, lo: shade.Vec3, hi: shade.Vec3 }
type Interval = struct { enter: f64, exit: f64 }
error Invalid
error TooSmall

fn epsilon() -> f64
fn two_pi() -> f64
fn sphere(center: shade.Vec3, radius: f64, albedo: shade.Rgb, emission: shade.Rgb) -> Sphere
fn camera(origin: shade.Vec3, aim: shade.Vec3, up: shade.Vec3, vertical_fov: f64) -> Camera
fn camera_ray(c: Camera, sx: f64, sy: f64, aspect: f64) -> Ray
fn sphere_span(origin: shade.Vec3, direction: shade.Vec3, center: shade.Vec3, radius: f64) -> (bool, f64, f64)
fn intersect(spheres: []const Sphere, ray: Ray) -> (bool, usize, f64)
fn is_emissive(s: Sphere) -> bool
fn max_channel(c: shade.Rgb) -> f64
fn cone_cos(p: shade.Vec3, s: Sphere) -> (bool, f64)
fn balance(a: f64, b: f64) -> f64
fn direction_about(axis: shade.Vec3, cos_theta: f64, phi: f64) -> shade.Vec3
fn direct_light(spheres: []const Sphere, p: shade.Vec3, n: shade.Vec3, albedo: shade.Rgb, r: *rand.Pcg64, mode: Mode) -> shade.Rgb
fn radiance(job: *const Job, first: Ray, r: *rand.Pcg64, mode: Mode) -> shade.Rgb
fn render(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb, mode: Mode) -> err
fn path_trace(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err
fn next_event_estimation(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err
fn multiple_importance(job: *const Job, r: *rand.Pcg64, out: []shade.Rgb) -> err
fn csg_sphere(center: shade.Vec3, radius: f64) -> CsgNode
fn csg_box(lo: shade.Vec3, hi: shade.Vec3) -> CsgNode
fn csg_op(kind: CsgKind, left: u32, right: u32) -> CsgNode
fn axis_of(v: shade.Vec3, axis: usize) -> f64
fn box_span(origin: shade.Vec3, direction: shade.Vec3, lo: shade.Vec3, hi: shade.Vec3) -> (bool, f64, f64)
fn inside_list(list: []const Interval, t: f64) -> bool
fn admits(kind: CsgKind, in_left: bool, in_right: bool) -> bool
fn combine(kind: CsgKind, out: []Interval, base: usize, nl: usize, nr: usize, scratch: []f64) -> (usize, err)
fn evaluate(nodes: []const CsgNode, index: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, base: usize, scratch: []f64) -> (usize, err)
fn csg(nodes: []const CsgNode, root: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, scratch: []f64) -> (usize, err)
fn csg_hit(nodes: []const CsgNode, root: u32, origin: shade.Vec3, direction: shade.Vec3, out: []Interval, scratch: []f64) -> (bool, f64, err)
```

A sphere-scene path tracer over caller storage: `camera` and `camera_ray`, `intersect`,
`radiance` in three modes (`path_trace`, `next_event_estimation`,
`multiple_importance` with the balance heuristic), and CSG of spheres and boxes by
interval lists (`csg`, `csg_hit`).

### `e.gfx.texture`

```neper
type Format = enum u8 { Bc1, Bc3, Bc4, Bc5 }
error Invalid
error TooSmall
error Unsupported

fn nearest_third(x: u32) -> u32
fn put4(out: []u8, at: usize, r: u32, g: u32, b: u32, a: u32)
fn expand565(c: u32) -> (u32, u32, u32)
fn bc_colors(block: []const u8, at: usize, four: bool, out: []u8)
fn bc_ramp(block: []const u8, at: usize, channel: usize, out: []u8)
fn bc_decode(block: []const u8, format: Format, out: []u8) -> err
fn quant_bits(q: usize) -> u32
fn quant_trit(q: usize) -> bool
fn quant_quint(q: usize) -> bool
fn ise_bits(n: usize, q: usize) -> usize
fn bit_at(block: []const u8, i: usize) -> u32
fn field(block: []const u8, lo: usize, n: usize) -> u32
fn seq_bit(block: []const u8, base: usize, limit: usize, reversed: bool, i: usize) -> u32
fn seq_bits(block: []const u8, base: usize, limit: usize, reversed: bool, pos: usize, n: u32) -> u32
fn trits_of(t: u32, out: []u32)
fn quints_of(q: u32, out: []u32)
fn ise_decode(block: []const u8, base: usize, limit: usize, reversed: bool, n: usize, q: usize, values: []u32, extras: []u32)
fn replicate(v: u32, bits: u32, width: u32) -> u32
fn bit_of(v: u32, i: u32) -> u32
fn unquant_color(v: u32, extra: u32, q: usize) -> u32
fn unquant_weight(v: u32, extra: u32, q: usize) -> u32
fn hash52(seed: u32) -> u32
fn select_partition(index: u32, x0: u32, y0: u32, count: u32, small: bool) -> u32
fn block_mode(m: u32) -> (u32, usize, usize, usize, bool)
fn clamp8(v: i32) -> u32
fn transfer(values: []i32, o: usize, b: usize)
fn blue_contract(e: []i32, r: i32, g: i32, b: i32, a: i32)
fn set4(e: []i32, r: i32, g: i32, b: i32, a: i32)
fn endpoints(cem: u32, v: []i32, e0: []i32, e1: []i32) -> err
fn clamp_all(e: []i32)
fn astc_decode(block: []const u8, width: usize, height: usize, srgb: bool, out: []u8) -> err
fn infill(weights: []const u32, count: usize, planes: usize, plane: usize, v0: usize, grid_w: usize, w00: usize, w01: usize, w10: usize, w11: usize) -> u32
fn grid_weight(weights: []const u32, count: usize, planes: usize, plane: usize, i: usize) -> usize
```

`bc_decode` (BC1, BC3, BC4, BC5) and `astc_decode` (LDR 2-d: every footprint from 4x4
to 12x12, void extents, partitions, trit and quint sequences, all ten colour endpoint
modes, dual planes, infill).

### `e.gfx.filter`

```neper
type Rect = struct { x: usize, y: usize, w: usize, h: usize, area: usize }
error TooSmall
error Invalid
error TooLarge

fn inf() -> f64
fn reflect(i: i64, n: usize) -> usize
fn conv_h(src: []const f64, w: usize, h: usize, r: usize, k: []const f64, dst: []f64)
fn conv_v(src: []const f64, w: usize, h: usize, r: usize, k: []const f64, dst: []f64)
fn gaussian_blur(src: []const f64, w: usize, h: usize, sigma: f64, dst: []f64, scratch: []f64) -> err
fn sobel(src: []const f64, w: usize, h: usize, gx: []f64, gy: []f64, magnitude: []f64) -> err
fn canny(src: []const f64, w: usize, h: usize, low: f64, high: f64, sigma: f64, edges: []u8, scratch: []f64) -> (usize, err)
fn median(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err
fn bilateral(src: []const f64, w: usize, h: usize, sigma_s: f64, sigma_r: f64, dst: []f64) -> err
fn box_mean(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err
fn guided(src: []const f64, guide: []const f64, w: usize, h: usize, radius: usize, eps: f64, dst: []f64, scratch: []f64) -> err
fn integral_image(src: []const f64, w: usize, h: usize, out: []f64) -> err
fn integral_sum(integral: []const f64, w: usize, x: usize, y: usize, rw: usize, rh: usize) -> f64
fn integral_image_u8(src: []const u8, w: usize, h: usize, out: []u64) -> err
fn integral_sum_u64(integral: []const u64, w: usize, x: usize, y: usize, rw: usize, rh: usize) -> u64
fn threshold_otsu(src: []const u8, w: usize, h: usize) -> u8
fn morph_extreme(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, dilate: bool) -> err
fn morph_erode(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64) -> err
fn morph_dilate(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64) -> err
fn morph_open(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err
fn morph_close(src: []const f64, w: usize, h: usize, radius: usize, dst: []f64, scratch: []f64) -> err
fn uf_find(parent: []u32, a: u32) -> u32
fn uf_union(parent: []u32, a: u32, b: u32)
fn label_components(src: []const u8, w: usize, h: usize, connectivity: u32, labels: []u32, parent: []u32) -> (u32, err)
fn flood_fill(image: []u8, w: usize, h: usize, x: usize, y: usize, new_value: u8, stack: []u32) -> (usize, err)
fn flood_fill_scanline(image: []u8, w: usize, h: usize, x: usize, y: usize, new_value: u8, stack: []u32) -> (usize, err)
fn dt1d(f: []const f64, n: usize, d: []f64, v: []f64, z: []f64)
fn distance_transform(binary: []const u8, w: usize, h: usize, out: []f64, scratch: []f64) -> err
fn godunov(a: f64, b: f64, f: f64) -> f64
fn eikonal_update(t: []const f64, speed: []const f64, w: usize, h: usize, x: usize, y: usize, known: []const u32) -> f64
fn heap_less(key: []const f64, tie: []const u32, i: u32, j: u32) -> bool
fn heap_swap(heap: []u32, pos: []u32, a: usize, b: usize)
fn sift_up(key: []const f64, tie: []const u32, heap: []u32, pos: []u32, start: usize)
fn sift_down(key: []const f64, tie: []const u32, heap: []u32, pos: []u32, size: usize, start: usize)
fn fast_marching(speed: []const f64, w: usize, h: usize, sources: []const u32, out: []f64, heap: []u32, pos: []u32) -> err
fn fast_sweeping(speed: []const f64, w: usize, h: usize, sources: []const u32, out: []f64, sweeps: usize) -> err
fn half(n: usize) -> usize
fn tap(k: usize) -> f64
fn pyramid_size(w: usize, h: usize, levels: usize) -> usize
fn reduce(src: []const f64, w: usize, h: usize, dst: []f64, tmp: []f64)
fn up_sample(line: []const f64, stride: usize, i: i64, n: usize) -> f64
fn expand(src: []const f64, w2: usize, h2: usize, w: usize, h: usize, dst: []f64, tmp: []f64)
fn laplacian_pyramid(src: []const f64, w: usize, h: usize, levels: usize, out: []f64, scratch: []f64) -> err
fn laplacian_collapse(pyramid: []const f64, w: usize, h: usize, levels: usize, dst: []f64, scratch: []f64) -> err
fn level_width(n: usize, level: usize) -> usize
fn max_rectangle(binary: []const u8, w: usize, h: usize, heights: []u32, stack: []u32) -> (Rect, err)
fn mean_shift(src: []const f64, w: usize, h: usize, hs: f64, hr: f64, iterations: usize, dst: []f64, modes: []f64) -> (usize, err)
fn watershed(gradient: []const f64, w: usize, h: usize, markers: []const u32, labels: []u32, heap: []u32, age: []u32) -> err
```

Grid filters over caller `[]f64`/`[]u8`: `gaussian_blur`, `sobel`, `canny` (bilinear
non-maximum suppression, hysteresis), `median`, `bilateral`, `box_mean`, `guided`,
`integral_image`/`integral_sum` (and the exact u8/u64 pair), `threshold_otsu`,
`morph_erode/dilate/open/close`, `label_components` (union-find), `flood_fill` and
`flood_fill_scanline`, `distance_transform` (Felzenszwalb-Huttenlocher), `fast_marching`,
`fast_sweeping`, `laplacian_pyramid`/`laplacian_collapse`, `max_rectangle`, `mean_shift`
and `watershed` (Meyer priority flood).

### `e.gfx.vision`

```neper
type Point = struct { x: f64, y: f64 }
type Keypoint = struct { x: f64, y: f64, angle: f64, response: f64, scale: f64 }
type Line = struct { rho: f64, theta: f64, votes: u32 }
error TooSmall
error Invalid

fn pi() -> f64
fn clamp_index(v: i64, n: usize) -> usize
fn pixel(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64
fn bilinear(img: []const f64, w: usize, h: usize, x: f64, y: f64) -> f64
fn grad_x(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64
fn grad_y(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64
fn gaussian_radius(sigma: f64) -> usize
fn gaussian_kernel(sigma: f64, kernel: []f64) -> usize
fn gaussian_blur(src: []const f64, dst: []f64, w: usize, h: usize, sigma: f64, tmp: []f64) -> err
fn harris_corners(img: []const f64, w: usize, h: usize, k: f64, sigma: f64, threshold: f64, out: []Keypoint, scratch: []f64) -> (usize, err)
fn hough_lines(edges: []const bool, w: usize, h: usize, rho_bins: usize, theta_bins: usize, threshold: u32, accumulator: []u32, out: []Line) -> (usize, err)
fn mul3(a: []const f64, b: []const f64, out: []f64)
fn transpose3(a: []const f64, out: []f64)
fn det3(m: []const f64) -> f64
fn normalise_matrix(m: []f64)
fn svd3(m: []const f64, u: []f64, s: []f64, v: []f64) -> err
fn normalisation(points: []const Point, n: usize) -> (f64, f64, f64)
fn similarity(cx: f64, cy: f64, s: f64, out: []f64)
fn accumulate9(ata: []f64, row: []const f64)
fn null_vector9(ata: []f64, out: []f64) -> err
fn homography(src: []const Point, dst: []const Point, out: []f64) -> err
fn apply_homography(hm: []const f64, p: Point) -> Point
fn fundamental_matrix(a: []const Point, b: []const Point, out: []f64) -> err
fn epipolar_residual(f: []const f64, a: Point, b: Point) -> f64
fn ransac[Ctx: type](ctx: *Ctx, n: usize, sample_size: usize, iterations: u32, threshold: f64, fit: fn(*Ctx, []const usize) -> bool, residual: fn(*Ctx, usize) -> f64, r: *rand.Pcg64, inliers: []bool, sample: []usize) -> (usize, err)
fn fft2(re: []f64, im: []f64, w: usize, h: usize, inverse: bool, col: []f64) -> err
fn phase_correlate(a: []const f64, b: []const f64, w: usize, h: usize, scratch: []f64) -> (f64, f64, f64, err)
fn optical_flow_lk(a: []const f64, b: []const f64, w: usize, h: usize, points: []const Point, window: usize, iterations: u32, out: []Point) -> err
fn poly_expand(img: []const f64, w: usize, h: usize, window: usize, ginv: []const f64, coeff: []f64)
fn optical_flow_farneback(a: []const f64, b: []const f64, w: usize, h: usize, window: usize, out: []Point, scratch: []f64) -> err
fn icp(p: []const geom3.Vec3, q: []const geom3.Vec3, iterations: u32, rotation: []f64, matched: []geom3.Vec3) -> (geom3.Vec3, f64, err)
fn orb_pattern() -> str
fn pattern_entry(i: usize) -> i64
fn fast_offset(i: usize) -> (i64, i64)
fn fast9(img: []const f64, w: usize, h: usize, x: i64, y: i64, threshold: f64) -> bool
fn harris7(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64
fn centroid_angle(img: []const f64, w: usize, h: usize, x: i64, y: i64) -> f64
fn brief(img: []const f64, w: usize, h: usize, x: i64, y: i64, angle: f64, out: []u8)
fn orb(img: []const f64, w: usize, h: usize, threshold: f64, out: []Keypoint, descriptors: []u8) -> (usize, err)
fn hamming(a: []const u8, b: []const u8) -> u32
fn sift_sigma(level: usize) -> f64
fn wrap_angle(a: f64) -> f64
fn sift_orientation(img: []const f64, w: usize, h: usize, x: i64, y: i64, sigma: f64) -> f64
fn sift_descriptor(img: []const f64, w: usize, h: usize, x: i64, y: i64, ori: f64, sigma: f64, out: []f64)
fn sift(img: []const f64, w: usize, h: usize, threshold: f64, out: []Keypoint, descriptors: []f64, scratch: []f64) -> (usize, err)
fn zhang_row(hm: []const f64, i: usize, j: usize, out: []f64)
fn calibrate_camera(model: []const Point, image: []const Point, views: usize, out: []f64) -> err
fn triangulate(rotation: []const f64, t: []const f64, a: Point, b: Point) -> (geom3.Vec3, bool)
fn to_normalised(kinv: []const f64, p: Point) -> Point
fn structure_from_motion(k: []const f64, a: []const Point, b: []const Point, rotation: []f64, translation: []f64, points: []geom3.Vec3, scratch: []Point) -> err
fn pose_candidate(u: []const f64, r1: []const f64, r2: []const f64, pose: usize, rotation: []f64, t: []f64)
```

`harris_corners`, `hough_lines` (skimage-identical accumulator), `homography` (normalised
DLT) with `apply_homography`, `fundamental_matrix` (eight-point, rank two) with
`epipolar_residual`, a generic `ransac` over caller fit and residual callbacks,
`phase_correlate`, `optical_flow_lk` and `optical_flow_farneback`, `icp` (Kabsch),
`orb` (FAST-9, Harris ranking, rBRIEF with the OpenCV pattern), `sift` (three octaves,
4x4x8 descriptors), `calibrate_camera` (Zhang) and `structure_from_motion` (essential
matrix, cheirality, linear triangulation); `svd3`, `hamming`.

### `e.gfx.scene`

```neper
type TextureId = struct { slot: u32, generation: u32 }
type SceneId = struct { slot: u32, generation: u32 }
type Clip = union enum u8 { Rect: geometry.Rect, Rounded: geometry.RRect, Path: geometry.Path }
type Command = union enum u8 { Save, Restore, Transform: geometry.Transform, Clip: Clip, FillRect: FillRect, FillPath: FillPath, StrokePath: StrokePath, Image: DrawImage, Text: DrawText, OpacityLayer: OpacityLayer }
type FillRect = struct { rect: geometry.Rect, brush: paint.Brush }
type FillPath = struct { path: geometry.Path, brush: paint.Brush }
type StrokePath = struct { path: geometry.Path, brush: paint.Brush, stroke: paint.Stroke }
type DrawImage = struct { texture: TextureId, source: geometry.Rect, destination: geometry.Rect, opacity: f32 }
type DrawText = struct { layout: *const layout.Layout, origin: geometry.Point, brush: paint.Brush }
type OpacityLayer = struct { bounds: geometry.Rect, opacity: f32 }
type DisplayList = struct { commands: []const Command }
type Builder = struct { state: *void }
type Renderer = struct { state: *void }
type Target = struct { state: *void }
error Invalid
error TooLarge
error OutOfMemory
error Lost

fn builder(a: *mem.Arena, max_commands: usize) -> (Builder, err)
fn push(b: *Builder, command: Command) -> err
fn finish(b: *Builder) -> DisplayList
fn renderer(a: *mem.Arena, device: *gpu.Device, queue: *gpu.Queue, max_scenes: u32, max_textures: u32) -> (Renderer, err)
fn register_font(r: *Renderer, font: shape.Font) -> err
fn upload_image(r: *Renderer, image_view: image.ConstImage) -> (TextureId, err)
fn update_image(r: *Renderer, texture: TextureId, image_view: image.ConstImage) -> err
fn release_image(r: *Renderer, texture: TextureId) -> err
fn compile(r: *Renderer, list: DisplayList) -> (SceneId, err)
fn render(r: *Renderer, scene: SceneId, render_target: Target, size: geometry.Size) -> err
fn release_scene(r: *Renderer, scene: SceneId) -> err
fn close(r: *Renderer) -> err
fn target_of(a: *mem.Arena, t: *gpu.Target) -> (Target, err)
fn queue_of(r: *Renderer) -> *gpu.Queue
```

Display lists borrow their paths, gradients and text layouts until `compile`
returns. A renderer owns bounded generation-checked GPU caches. Compilation may
retain tessellation and glyph data but never application widget pointers. Rendering
is explicit queue work followed by presentation through the target surface.

Delivered as the CPU reference renderer (D796): one signed-area accumulation
rasteriser draws fills, strokes as outlines, glyph outlines from a registered font's
`glyf`, clips as coverage masks and opacity layers into a premultiplied canvas the
frame's `gpu.Image` receives; `register_font` hands the renderer the bytes behind a
shaper font id, and `target_of` wraps an `e.gpu` target -- a window's or an
offscreen one. A driver backend draws the same list with the same arithmetic in
kernels.

### `e.ui.asset`

```neper
type Theme = enum u8 { Any, Light, Dark }
type Request = struct { scale: f32, locale: str, theme: Theme }
type ImageDecoder = struct { ctx: *void, decode: fn(*void, *mem.Arena, []const u8) -> (image.Image, err) }
type Cache = struct { state: *void }
error Missing
error InvalidVariant
error Decode
error Full

fn select(base: str, request: Request) -> (asset.Asset, err)
fn font(base: str, request: Request, face_index: u32) -> (shape.Font, err)
fn cache(a: *mem.Arena, renderer: *scene.Renderer, capacity: usize) -> (Cache, err)
fn texture(texture_cache: *Cache, scratch: *mem.Arena, base: str, request: Request, decoder: ImageDecoder) -> (scene.TextureId, err)
fn evict(texture_cache: *Cache, renderer: *scene.Renderer, base: str) -> err
fn clear(texture_cache: *Cache, renderer: *scene.Renderer) -> err
fn close(texture_cache: *Cache, renderer: *scene.Renderer) -> err
```

Variants share a manifest `base` attribute. Selection first filters by base, then
chooses exact locale (falling back by removing subtags and finally to
an empty locale), exact theme before `Any`, and the smallest scale not below the
request or otherwise the largest scale. UTF-8 asset name breaks any remaining tie.
The algorithm reads only `e.asset` metadata and is deterministic on every host.

`font` returns executable-backed OpenType bytes without copying. `texture` invokes
the caller-supplied decoder into `scratch`, uploads before returning, and keys the
bounded cache by selected asset SHA-256 plus decoder identity. The cache owns its
texture entries but not the renderer; eviction and closure explicitly release them.
No image codec, filesystem lookup or unbounded global cache is hidden here.

### `e.ui.window`

```neper
type Id = struct { slot: u32, generation: u32 }
type Window = struct { state: *void, id: Id }
type Mode = enum u8 { Windowed, Maximized, Fullscreen }
type Cursor = enum u8 { Arrow, Text, Hand, Crosshair, ResizeHorizontal, ResizeVertical, Hidden }
type Options = struct { title: str, width: u32, height: u32, min_width: u32, min_height: u32, resizable: bool, transparent: bool, mode: Mode }
type Lifecycle = enum u8 { Active, Inactive, Background, Suspended }
type Orientation = enum u8 { Landscape, Portrait }
type Screen = struct { bounds: geometry.Rect, work_area: geometry.Rect, scale: f32, primary: bool }
type Metrics = struct { logical_size: geometry.Size, framebuffer_width: u32, framebuffer_height: u32, scale: f32, focused: bool, visible: bool }
error Unsupported
error Invalid
error Closed

fn open(a: *mem.Arena, device: *gpu.Device, options: Options) -> (Window, err)
fn metrics(window: *const Window) -> (Metrics, err)
fn draw_target(window: *const Window) -> (scene.Target, err)
fn host_window(window: *const Window) -> (os.Window, err)
fn title(window: *Window, value: str) -> err
fn cursor(window: *Window, value: Cursor) -> err
fn visible(window: *Window, value: bool) -> err
fn request_frame(window: *Window) -> err
fn clipboard_get(a: *mem.Arena, window: *Window) -> (str, err)
fn clipboard_set(window: *Window, value: str) -> err
fn capabilities(window: *const Window) -> (style.Capabilities, err)
fn safe_insets(window: *const Window) -> (geometry.Insets, err)
fn keyboard_insets(window: *const Window) -> (geometry.Insets, err)
fn orientation(window: *const Window) -> (Orientation, err)
fn lifecycle(window: *const Window) -> (Lifecycle, err)
fn screens(a: *mem.Arena, limit: usize) -> ([]const Screen, err)
fn close(window: *Window) -> err
```

Windows are logically linear handles backed only by reviewed `e.os` primitives.
Coordinates exposed above the module are logical pixels; framebuffer dimensions are
physical pixels. `draw_target` (named so because `target` is a reserved word, D797) is
non-owning and becomes invalid when the window closes.

The host capability model (D811, widget plan P0-08): `capabilities` answers what a
window's host can do as the `style.Capabilities` that `style.adapt` takes -- every
host today is a desktop with a hovering fine pointer, a keyboard, no touch or pen,
other windows and no insets; `safe_insets` and `keyboard_insets` are what a mobile
host would report and are none here; `orientation` follows the logical size;
`screens` are the host's monitors in logical pixels (the work area is the screen
until a host reports its shell's edges); `lifecycle` is active when focused and
visible, inactive when visible without the focus, background when hidden, and
suspended only when a host says so.

### `e.ui.input`

```neper
type DeviceId = u32
type PointerId = u32
type Key = struct { physical: u32, logical: u32 }
type Modifiers = struct { shift: bool, control: bool, alt: bool, meta: bool, caps_lock: bool, num_lock: bool }
type PointerButton = enum u8 { Primary, Secondary, Middle, Back, Forward }
type PointerKind = enum u8 { Mouse, Touch, Pen }
type Pointer = struct { window: window.Id, device: DeviceId, pointer: PointerId, kind: PointerKind, position: geometry.Point, buttons: u32, changed: PointerButton }
type KeyEvent = struct { window: window.Id, key: Key, modifiers: Modifiers, repeat: bool }
type TextEvent = struct { window: window.Id, text: str }
type Composition = struct { window: window.Id, text: str, selection_start: usize, selection_end: usize }
type LifecycleEvent = struct { window: window.Id, state: window.Lifecycle }
type InsetsEvent = struct { window: window.Id, safe: geometry.Insets, keyboard: geometry.Insets }
type Event = union enum u8 { Frame: window.Id, Close: window.Id, Resize: window.Metrics, Focus: window.Id, Blur: window.Id, PointerDown: Pointer, PointerUp: Pointer, PointerMove: Pointer, Scroll: Pointer, KeyDown: KeyEvent, KeyUp: KeyEvent, Text: TextEvent, Composition: Composition, Lifecycle: LifecycleEvent, Insets: InsetsEvent, Back: window.Id }
type Queue = struct { state: *void }
error Closed
error TooLarge

fn queue(a: *mem.Arena, capacity: usize) -> (Queue, err)
fn poll(q: *Queue, timeout: time.Duration) -> (Event, bool, err)
fn capture(q: *Queue, window_value: window.Id, pointer: PointerId) -> err
fn release_capture(q: *Queue, window_value: window.Id, pointer: PointerId) -> err
fn composition_rect(q: *Queue, window_value: window.Id, rect: geometry.Rect) -> err
fn close(q: *Queue) -> err
```

Events preserve native ordering and borrow transient text until the next `poll`.
Platform key codes are normalized into stable physical and Unicode-oriented logical
values. Gesture recognition is built by widgets from pointer streams rather than
being hidden in the OS boundary.

Lifecycle events (D811): a `Lifecycle` event follows the `Focus` or `Blur` that
implied it (active, inactive) on the next poll; `Insets` and `Back` are what a
mobile host sends and a desktop host never does. The widget runtime takes the
first two quietly and treats `Back` as Escape, the nearest scope's cancel action.

### `e.ui.widget`

```neper
type Key = u64
type ElementId = struct { slot: u32, generation: u32 }
type StateId = struct { slot: u32, generation: u32 }
type Action = struct { ctx: *void, invoke: fn(*void, input.Event) -> err }
type Text = struct { value: str, style: layout.Style, color: paint.Color, wrap: layout.Wrap, align: layout.Align, max_lines: u32, ellipsis: str }
type Button = struct { action: Action, enabled: bool }
type Image = struct { texture: scene.TextureId, fit: Fit }
type Overscroll = enum u8 { Clamp, Bounce }
type Scroll = struct { axis: ui_layout.Axis, offset: f32, overscroll: Overscroll, momentum: bool, scrollbar: bool, thumb: paint.Color, change: Change[f32], virtual_first: usize, virtual_count: usize, virtual_extent: f32 }
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err }
type Change[T: type] = struct { ctx: *void, invoke: fn(*void, T) -> err }
type Submit = struct { ctx: *void, invoke: fn(*void) -> err }
type Drag = struct { start: geometry.Point, position: geometry.Point, delta: geometry.Point }
type Gesture = union enum u8 { Tap: geometry.Point, DragStart: geometry.Point, DragMove: Drag, DragEnd: geometry.Point, Hover: geometry.Point, HoverEnd, Drop: Dropped }
type Dropped = struct { position: geometry.Point, payload: u64 }
type GestureAction = struct { ctx: *void, invoke: fn(*void, Gesture) -> err }
type Region = struct { gesture: GestureAction, gestures: u8, enabled: bool, focusable: bool }
type Shortcut = struct { key: u32, modifiers: input.Modifiers, action: Submit }
type Scope = struct { traps_focus: bool, shortcuts: []const Shortcut, default_action: Submit, cancel_action: Submit, keys: Change[input.KeyEvent] }
type Edit = struct { buffer: []u8, len: usize, style: layout.Style, color: paint.Color, selection: paint.Color, change: Change[str], submit: Submit, enabled: bool, read_only: bool, multiline: bool, secret: bool }
type Semantics = struct { role: u8, label: str, value: str, hint: str, states: u32, actions: u32, live: u8, level: u8, labelled_by: Key, described_by: Key, error_by: Key, controls: Key, active: Key, row: u32, column: u32, row_count: u32, column_count: u32, hidden: bool, on_action: Change[u32] }
type Placement = enum u8 { Below, Above, Right, Left, Center }
type Overlay = struct { anchor: Key, placement: Placement, offset: geometry.Point, modal: bool, dismiss: Submit }
type Alignment = enum u8 { Start, Center, End }
type Scrollbar = struct { viewport: Key, axis: ui_layout.Axis }
type Interaction = struct { hovered: bool, pressed: bool, focused: bool }
type Slider = struct { value: f32, second: f32, range: bool, low: f32, high: f32, step: f32, vertical: bool, track: paint.Color, fill: paint.Color, thumb: paint.Color, change: Change[f32], change_second: Change[f32], enabled: bool }
type ZoomState = struct { scale: f32, offset: geometry.Point }
type Zoom = struct { state: ZoomState, min_scale: f32, max_scale: f32, change: Change[ZoomState] }
type ClipboardCommands = struct { copy: bool, cut: bool, paste: bool }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom, Region: Region, Scope: Scope, Edit: Edit, Semantics: Semantics, Overlay: Overlay, Wrap: ui_layout.Wrap, Aspect: f32, Fitted, Scrollbar: Scrollbar, Slider: Slider, Zoom: Zoom }
type Node = struct { key: Key, kind: Kind, style: style.Style, children: []const Node }
type Fit = enum u8 { Fill, Contain, Cover, None }
type BuildContext = struct { runtime: *Runtime, element: ElementId, frame: u64 }
type Runtime = struct { state: *void }
type Limits = struct { max_elements: usize, max_states: usize, state_bytes: usize, state_classes: u16, max_depth: u16, max_commands: usize }
type Summary = struct { id: ElementId, kind: u8, parent: ElementId, has_parent: bool, bounds: geometry.Rect, has_action: bool, enabled: bool, focused: bool, text: str, first_child: ElementId, has_child: bool, next_sibling: ElementId, has_sibling: bool, semantics: Semantics, has_semantics: bool, value: str, selection_start: usize, selection_end: usize, read_only: bool }
error DuplicateKey
error InvalidTree
error TooDeep
error TooLarge
error StateType

fn runtime(a: *mem.Arena, renderer: *scene.Renderer, limits: Limits) -> (Runtime, err)
fn box(key: Key, value_style: style.Style, children: []const Node) -> Node
fn flex(key: Key, spec: ui_layout.Flex, value_style: style.Style, children: []const Node) -> Node
fn grid(key: Key, spec: ui_layout.Grid, value_style: style.Style, children: []const Node) -> Node
fn stack(key: Key, value_style: style.Style, children: []const Node) -> Node
fn text(key: Key, value: Text, value_style: style.Style) -> Node
fn button(key: Key, value: Button, value_style: style.Style, children: []const Node) -> Node
fn image(key: Key, value: Image, value_style: style.Style) -> Node
fn scroll(key: Key, value: Scroll, value_style: style.Style, children: []const Node) -> Node
fn region(key: Key, value: Region, value_style: style.Style, children: []const Node) -> Node
fn scope(key: Key, value: Scope, value_style: style.Style, children: []const Node) -> Node
fn edit(key: Key, value: Edit, value_style: style.Style) -> Node
fn semantics(key: Key, value: Semantics, value_style: style.Style, children: []const Node) -> Node
fn overlay(key: Key, value: Overlay, value_style: style.Style, children: []const Node) -> Node
fn row(key: Key, gap: f32, value_style: style.Style, children: []const Node) -> Node
fn column(key: Key, gap: f32, value_style: style.Style, children: []const Node) -> Node
fn wrap(key: Key, spec: ui_layout.Wrap, value_style: style.Style, children: []const Node) -> Node
fn positioned(key: Key, x: f32, y: f32, value_style: style.Style, children: []const Node) -> Node
fn aligned(key: Key, horizontal: Alignment, vertical: Alignment, value_style: style.Style, children: []const Node) -> Node
fn center(key: Key, value_style: style.Style, children: []const Node) -> Node
fn padded(key: Key, left: f32, top: f32, right: f32, bottom: f32, value_style: style.Style, children: []const Node) -> Node
fn spacer(key: Key, share: f32) -> Node
fn constrained(key: Key, min_width: f32, max_width: f32, min_height: f32, max_height: f32, value_style: style.Style, children: []const Node) -> Node
fn aspect_ratio(key: Key, ratio: f32, value_style: style.Style, children: []const Node) -> Node
fn fitted(key: Key, value_style: style.Style, children: []const Node) -> Node
fn responsive(width: f32, compact: Node, medium: Node, expanded: Node) -> Node
fn scroll_view(a: *mem.Arena, key: Key, axis: ui_layout.Axis, value_style: style.Style, children: []const Node) -> (Node, err)
fn scrollbar(key: Key, viewport: Key, axis: ui_layout.Axis, value_style: style.Style) -> Node
fn slider(key: Key, value: Slider, value_style: style.Style) -> Node
fn zoom(key: Key, value: Zoom, value_style: style.Style, children: []const Node) -> Node
fn zoom_state_of(widget_runtime: *const Runtime, element: ElementId) -> (ZoomState, bool)
fn begin_drag(widget_runtime: *Runtime, payload: u64) -> err
fn dragging(widget_runtime: *const Runtime) -> (u64, bool)
fn clipboard_commands(widget_runtime: *Runtime) -> ClipboardCommands
fn clipboard_copy(widget_runtime: *Runtime) -> err
fn clipboard_cut(widget_runtime: *Runtime) -> err
fn clipboard_paste(widget_runtime: *Runtime) -> err
fn clipboard_set(widget_runtime: *Runtime, value: str) -> err
fn clipboard_get(widget_runtime: *Runtime, a: *mem.Arena) -> (str, err)
fn safe_area(key: Key, insets: geometry.Insets, value_style: style.Style, children: []const Node) -> Node
fn keyboard_avoiding(key: Key, keyboard: geometry.Insets, value_style: style.Style, children: []const Node) -> Node
fn fire_change[T: type](c: Change[T], value: T) -> err
fn fire_submit(a: Submit) -> err
fn fire_gesture(a: GestureAction, g: Gesture) -> err
fn state[T: type](ctx: *BuildContext, key: Key, initial: T) -> (*T, StateId, err)
fn invalidate(widget_runtime: *Runtime, element: ElementId)
fn reconcile(widget_runtime: *Runtime, frame_arena: *mem.Arena, root: Node, constraints: ui_layout.Constraints) -> (scene.SceneId, err)
fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err
fn focus(widget_runtime: *Runtime, element: ElementId) -> err
fn focused(widget_runtime: *const Runtime) -> (ElementId, bool)
fn interaction(widget_runtime: *const Runtime, key: Key) -> Interaction
fn slider_value_of(widget_runtime: *const Runtime, element: ElementId) -> (f32, f32, bool)
fn edit_value(widget_runtime: *const Runtime, element: ElementId) -> (str, bool)
fn edit_selection(widget_runtime: *const Runtime, element: ElementId) -> (usize, usize, bool)
fn scroll_to(widget_runtime: *Runtime, element: ElementId, offset: f32) -> err
fn scroll_offset_of(widget_runtime: *const Runtime, element: ElementId) -> (f32, bool)
fn visible_range(offset: f32, viewport: f32, count: usize, extent: f32) -> (usize, usize)
fn semantic_action(widget_runtime: *Runtime, element: ElementId, bit: u32) -> err
fn edit_set(widget_runtime: *Runtime, element: ElementId, value: str) -> err
fn edit_select(widget_runtime: *Runtime, element: ElementId, start: usize, end: usize) -> err
fn overlay_bounds_of(widget_runtime: *const Runtime, element: ElementId) -> (geometry.Rect, bool)
fn close(widget_runtime: *Runtime) -> err
fn bounds_of(widget_runtime: *const Runtime, element: ElementId) -> (geometry.Rect, bool)
fn renderer_of(widget_runtime: *Runtime) -> *scene.Renderer
fn queue_of(widget_runtime: *Runtime) -> *gpu.Queue
fn element_count(widget_runtime: *const Runtime) -> usize
fn root_of(widget_runtime: *const Runtime) -> (ElementId, bool)
fn summary_at(widget_runtime: *const Runtime, slot: usize) -> (Summary, bool)
```

`Node` is the declarative syntax: ordinary literals and the allocation-free convenience
constructors create
an immutable tree in a resettable frame arena. Reconciliation matches siblings by
nonzero key and kind, otherwise by position and kind. Persistent elements and typed
state occupy bounded generation-checked slots owned by `Runtime`; widgets themselves
are never retained. Removed state is destroyed logically at the reconciliation
boundary and its size/alignment cell enters a bounded runtime free list. A reused
`Action.ctx` must outlive the element that retains it; passing frame-arena context is
`InvalidTree` in debug validation and undefined in release.

Delivered (D799) over the CPU renderer: `reconcile` rebuilds, lays out and paints the
whole tree each frame and compiles it into the renderer, releasing the previous
frame's scene; `bounds_of` answers an element's last laid-out bounds for a harness or
an accessibility tree.

Typed actions, gesture regions and scopes (D806, widget plan P0-02/P0-03): a
`Change[T]` carries a value and a `Submit` nothing, and firing an unset one is a
no-op. A `Region` takes part in the gestures its mask names (1 tap, 2 drag, 4
hover) and the runtime's single gesture arena settles them from the raw pointer
events: a press and release inside the region within the slop is a tap, a press
that travels past the slop is a drag when the region takes one and is otherwise
released to whatever scrolls, and a move over a hovering region enters it and
leaves the last. A `Scope` bounds Tab and Shift+Tab to its focusable descendants
when it traps focus, holds up to eight shortcuts, and answers Enter with its
default action and Escape with its cancel action; a key down walks the scopes from
the focused element upward and the first that takes it wins.

Editable text (D807, widget plan P0-04): an `Edit` node edits the caller's buffer
in place and reports each new value through `change`; a `len` the caller changes
between frames replaces the value, one it leaves alone keeps the runtime's edits. A
press places the caret by hit test and a drag selects; Left, Right, Home and End
move (Shift extends), Up and Down move between a multiline editor's lines, Backspace
and Delete erase, Enter fires `submit` in a single line and breaks a multiline one;
Control with A, C, X, V, Z and Y (or Shift+Z) select all, copy, cut, paste, undo and
redo, over the host clipboard with a runtime fallback and a bounded history that
coalesces typed runs; a composition shows at the caret with an underline until its
text commits it. A value that would not fit its buffer is left as it is. A `secret` editor (D823) shows an asterisk per byte, so every
offset stands where the value's does, and never copies. Key codes
are Windows virtual codes; the X keysyms the editor and the scopes read map onto
them.

Viewports (D808, widget plan P0-05): a `Scroll` node stacks its children and clips
them, moved along its axis by the wheel (40 px a notch), by a drag of the content
past the slop -- including one a tap-only region released -- carried on by momentum
over the frames after the drag when asked, and by `scroll_to`; its `offset` follows
the editor's rule and every move is reported through `change`. Past its ends a
clamped viewport stops and a bouncing one overshoots at half speed up to half its
extent, springing back over the frames once let go. A `virtual_count` makes the
viewport lazy: the content is that many items of `virtual_extent`, the children are
the items from `virtual_first` on -- the ones `visible_range` names for the offset,
with one of overscan beyond each end -- placed at their item positions, and the
caller's keys let the reconciler recycle the elements that scrolled out. A
`scrollbar` paints a thumb on the trailing edge, not dragged.

Semantics (D809, widget plan P0-06): a `Semantics` node says what its subtree is to
the accessibility tree beyond what the kinds imply -- `e.ui.accessibility`'s role
code, a label, value and hint copied into the element, its state and action bits,
live-region politeness, relationships to other elements by key, a place in a
collection and a level -- and a hidden one leaves the tree with its subtree. A
platform action it offers reaches `on_action` as its bit through `semantic_action`;
`edit_set` and `edit_select` are the platform's way into an editor. The summary
carries all of it, and an editor's value, selection and read-only state.

Overlays (D810, widget plan P0-07): an `Overlay` node's children leave the flow --
it measures as nothing where it sits -- and are placed after the whole tree, painted
last, stacked in the rect `placement` and `offset` put against the element `anchor`
names by key (the window for none), kept inside the window. Up to eight overlays
stack in tree order; a pointer event starts at the topmost overlay under it, and a
modal one keeps the pointer from what is under it, firing `dismiss` on a press
outside instead. A modal overlay takes the focus into its first focusable element
when it appears, bounds Tab to its subtree, and gives the focus back to the element
that had it when it goes.

The primary layouts (D815, widget plan P1-03): `row` and `column` are flexes along
an axis with a gap; `wrap` is `ui_layout.wrap`, lines broken where the next child
would pass the main limit; `positioned` is a box whose margin is its offset, which a
stack places it by; `box`, `flex`, `grid` and `stack` are D799's.

The layout adapters (D816, P1-04): `aligned` and `center` are a flex whose main
and cross alignment place the child in the box -- a placed flex lays its children
out within all of its settled size now, so alignment holds in a sized box; `padded`
and `constrained` set the style's padding and size bounds; `spacer` takes a flex
share of both axes; an `Aspect` box is as wide as it may be and the ratio tall; a
`Fitted` box paints its content at its natural size scaled down about its origin to
fit, its elements' bounds unscaled; `responsive` picks a subtree by the size class
of a width when the tree is built.

Scrolling and insets (D817, P1-05): `scroll_view` stacks its children along its
axis in a clamped viewport with momentum and a thumb; a `Scrollbar` node stands
apart from the viewport it names by key -- its style's background the track and
its border colour the thumb -- and a drag of it moves the viewport by the content's
share of the distance along the bar; `safe_area` and `keyboard_avoiding` pad by
the host's insets (D811) rather than scroll.

`interaction` (D818) answers what the pointer and the focus are doing to a keyed
element -- hovered, pressed while the pointer is down on it, focused -- for the look
a control resolves; and Enter or Space on a focused tap region is a tap at its
centre, before the scopes see the key.

A `Slider` node (D820) is a value in `low..high` the runtime moves: a press sets it
from the point along the track (the nearer thumb of a range), a drag follows, the
arrow keys step it (a hundredth of the range when `step` is 0) and Home and End jump
to the ends when it has the focus, each change snapped to the step and reported;
the track, its filled part and the round thumbs paint in the colours given, and
the caller's value follows the editor's rule.

### `e.ui.animation`

```neper
type Curve = enum u8 { Linear, EaseIn, EaseOut, EaseInOut }
type Controller = struct { start: time.Instant, duration: time.Duration, curve: Curve, repeating: bool, reverse: bool }

fn controller(now: time.Instant, duration: time.Duration, curve: Curve) -> Controller
fn value(c: *const Controller, now: time.Instant) -> f32
fn finished(c: *const Controller, now: time.Instant) -> bool
fn restart(c: *Controller, now: time.Instant)
fn request(runtime: *widget.Runtime, element: widget.ElementId)
```

Animation state is explicit. Sampling never reads a clock; the application supplies
`now`, making animation deterministic in tests.

### `e.ui.accessibility`

```neper
type Id = widget.ElementId
type Role = enum u8 { Application, Window, Group, Button, Checkbox, Radio, Text, TextField, Image, Link, List, ListItem, Table, Row, Cell, Slider, Progress, Scrollbar, Switch, Tab, TabList, Menu, MenuItem, Dialog, Alert, Heading, Status, Tooltip, Tree, TreeItem, Grid, RowHeader, ColumnHeader }
type State = struct { disabled: bool, focused: bool, selected: bool, checked: bool, expanded: bool, hidden: bool, mixed: bool, busy: bool, invalid: bool, required: bool, read_only: bool, modal: bool, current: bool }
type Action = enum u8 { Focus, Press, Increment, Decrement, SetValue, Scroll, Dismiss, Expand, Collapse, Select, ShowMenu, SetSelection }
type Relations = struct { labelled_by: Id, described_by: Id, error_by: Id, controls: Id, active: Id }
type Live = enum u8 { Off, Polite, Assertive }
type Position = struct { row: u32, column: u32, row_count: u32, column_count: u32 }
type Node = struct { id: Id, role: Role, label: str, value: str, hint: str, state: State, bounds: geometry.Rect, actions: []const Action, children: []const Id, relations: Relations, live: Live, position: Position, level: u8, selection_start: usize, selection_end: usize }
type Tree = struct { root: Id, nodes: []const Node }
error Unsupported
error Invalid
const STATE_DISABLED: u32 = 1u32
const STATE_FOCUSED: u32 = 2u32
const STATE_SELECTED: u32 = 4u32
const STATE_CHECKED: u32 = 8u32
const STATE_EXPANDED: u32 = 16u32
const STATE_HIDDEN: u32 = 32u32
const STATE_MIXED: u32 = 64u32
const STATE_BUSY: u32 = 128u32
const STATE_INVALID: u32 = 256u32
const STATE_REQUIRED: u32 = 512u32
const STATE_READ_ONLY: u32 = 1024u32
const STATE_MODAL: u32 = 2048u32
const STATE_CURRENT: u32 = 4096u32
const ACTION_FOCUS: u32 = 1u32
const ACTION_PRESS: u32 = 2u32
const ACTION_INCREMENT: u32 = 4u32
const ACTION_DECREMENT: u32 = 8u32
const ACTION_SET_VALUE: u32 = 16u32
const ACTION_SCROLL: u32 = 32u32
const ACTION_DISMISS: u32 = 64u32
const ACTION_EXPAND: u32 = 128u32
const ACTION_COLLAPSE: u32 = 256u32
const ACTION_SELECT: u32 = 512u32
const ACTION_SHOW_MENU: u32 = 1024u32
const ACTION_SET_SELECTION: u32 = 2048u32

fn build(a: *mem.Arena, runtime: *const widget.Runtime) -> (Tree, err)
fn publish(window_value: window.Id, tree: *const Tree) -> err
fn perform(runtime: *widget.Runtime, id: Id, action: Action, value: str) -> err
```

The semantics tree is separate from paint order but uses the same stable element
identities. Publication crosses a reviewed `e.os` accessibility bridge and retains
no caller strings after returning.

Delivered (D802) as the tree and the actions; `publish` flattens the tree into
`os.AccessibleNode` records and answers `Unsupported` until a host bridge is written,
so the framework does not claim accessibility yet.

The semantics node (D809, widget plan P0-06): a `widget.Semantics` on an element
sets its role from the role code, its label, value and hint, adds its state and
action bits (the constants above), names its relationships by key, its live-region
politeness, its place in a collection and its level; a hidden element and its
subtree leave the tree. An editor is a `TextField` with its value and selection and
the `SetValue` and `SetSelection` operations; `perform` routes them into the editor
(`SetSelection` takes "start:end") and every other offered action to the semantics'
callback as its bit. Not here: custom named actions, which wait on the host bridge
whose record would carry the names; the `os.AccessibleNode` record keeps the six
state and action bits it had until that bridge is written.

### `e.ui.testing`

```neper
type Harness = struct { state: *void }
type Match = struct { element: widget.ElementId, count: usize }
type Gallery = struct { presses: usize, checked: bool, field: [32]u8, field_len: usize, scrolled: f32 }
error NotFound
error Ambiguous
error GoldenMismatch

fn harness(a: *mem.Arena, runtime: *widget.Runtime, width: u32, height: u32, scale: f32) -> (Harness, err)
fn pump(h: *Harness, root: widget.Node, now: time.Instant) -> err
fn send(h: *Harness, event: input.Event) -> err
fn by_key(h: *const Harness, key: widget.Key) -> Match
fn by_text(h: *const Harness, text: str) -> Match
fn snapshot(h: *Harness, a: *mem.Arena) -> (image.Image, err)
fn compare(actual: image.ConstImage, expected: image.ConstImage, tolerance: u8) -> err
fn tap(h: *Harness, x: f32, y: f32) -> err
fn drag(h: *Harness, from: geometry.Point, to: geometry.Point, steps: usize) -> err
fn hover(h: *Harness, x: f32, y: f32) -> err
fn wheel(h: *Harness, x: f32, y: f32, notches: i32) -> err
fn press_key(h: *Harness, code: u32, modifiers: input.Modifiers) -> err
fn tab(h: *Harness, backward: bool) -> err
fn focused(h: *const Harness) -> (widget.ElementId, bool)
fn type_text(h: *Harness, text: str) -> err
fn compose(h: *Harness, text: str) -> err
fn commit(h: *Harness, text: str) -> err
fn semantics(h: *const Harness) -> (accessibility.Tree, err)
fn by_role(h: *const Harness, role: accessibility.Role) -> Match
fn by_label(h: *const Harness, label: str) -> Match
fn overlay_of(h: *const Harness, element: widget.ElementId) -> (geometry.Rect, bool)
fn visible(h: *const Harness, element: widget.ElementId) -> bool
fn fake_host(h: *Harness, host: style.Capabilities, safe: geometry.Insets, keyboard: geometry.Insets) -> err
fn capabilities(h: *const Harness) -> style.Capabilities
fn insets(h: *const Harness) -> (geometry.Insets, geometry.Insets)
fn gallery(a: *mem.Arena, t: *const style.ThemeTokens, text_style: layout.Style, gallery_state: *Gallery) -> (widget.Node, err)
fn close(h: *Harness) -> err
```

The harness uses the deterministic CPU rendering backend and a synthetic window. It
does not require a display server and never sleeps; tests supply frame time.

The widget harness (D812, widget plan P0-09) adds what the proposal's section 8
asks of it: gesture sequences (`tap`, `drag` in steps, `hover`, `wheel`), keys and
focus traversal (`press_key`, `tab`, `focused`), the fake IME (`type_text` one code
point at a time, `compose`, `commit`), semantic queries over the tree built now
(`semantics`, `by_role`, `by_label` -- the first match in slot order and the count),
overlay lookup, viewport visibility (inside the surface and every viewport above),
and the host fixture (`fake_host` sets the capabilities and insets the harness
stands in for and sends the insets event). `gallery` is the reference page: one of
each primitive under a theme -- a heading, a filled button, an outlined field, a
checkbox, a list in a viewport, a tooltip overlay -- with stable keys 1..9 and 20..25
and its state in a `Gallery` the caller owns.

### `e.ui.control`

```neper
type Theme = struct { tokens: *const style.ThemeTokens, fonts: []const shape.Font, language: str, runtime: *widget.Runtime }
type ButtonOptions = struct { variant: style.ControlVariant, enabled: bool }
type TextOptions = struct { role: style.TextRole, color: style.ColorRole, align: layout.Align, wrap: layout.Wrap, max_lines: u32, ellipsis: str }
type Span = struct { value: str, role: style.TextRole, color: style.ColorRole, link: widget.Submit }
type SurfaceOptions = struct { background: style.ColorRole, bordered: bool, radius: f32, elevation: u8, padding: f32 }
type FieldOptions = struct { placeholder: str, enabled: bool, read_only: bool, invalid: bool, width: f32, rows: u32 }
type Validity = enum u8 { Valid, Warning, Invalid }
type Message = struct { validity: Validity, text: str }
type ChipKind = enum u8 { Assist, Filter, Input, Suggestion }
type Chord = struct { key: u32, modifiers: input.Modifiers }
type Format = struct { ctx: *void, accept: fn(*void, str) -> bool, format: fn(*void, []u8, str) -> usize }
type PickerForm = enum u8 { Popup, Sheet }
type Notice = struct { text: str, action_label: str, action: widget.Submit, dismiss: widget.Submit }
type Severity = enum u8 { Info, Success, Warning, Error }
error TooLarge

fn text_options() -> TextOptions
fn text_style(a: *mem.Arena, t: *const Theme, role: style.TextRole) -> (layout.Style, err)
fn text(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions) -> (widget.Node, err)
fn selectable_text(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions) -> (widget.Node, err)
fn rich_text(a: *mem.Arena, key: widget.Key, spans: []const Span, t: *const Theme) -> (widget.Node, err)
fn icon(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err)
fn image(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, width: f32, height: f32, fit: widget.Fit, label: str) -> (widget.Node, err)
fn canvas(a: *mem.Arena, key: widget.Key, custom: widget.Custom, label: str) -> (widget.Node, err)
fn surface_options(t: *const Theme) -> SurfaceOptions
fn surface_style(t: *const Theme, options: SurfaceOptions) -> style.Style
fn surface(a: *mem.Arena, key: widget.Key, t: *const Theme, options: SurfaceOptions, children: []const widget.Node) -> (widget.Node, err)
fn panel(a: *mem.Arena, key: widget.Key, t: *const Theme, children: []const widget.Node) -> (widget.Node, err)
fn card(a: *mem.Arena, key: widget.Key, t: *const Theme, children: []const widget.Node) -> (widget.Node, err)
fn group_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, children: []const widget.Node) -> (widget.Node, err)
fn divider(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: ui_layout.Axis, length: f32) -> (widget.Node, err)
fn badge(a: *mem.Arena, key: widget.Key, t: *const Theme, value: str) -> (widget.Node, err)
fn avatar(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err)
fn placeholder(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32) -> (widget.Node, err)
fn button_options() -> ButtonOptions
fn control_state(t: *const Theme, key: widget.Key, enabled: bool, selected: bool) -> style.ControlState
fn button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err)
fn icon_button(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err)
fn toggle_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, selected: bool, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err)
fn link(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit) -> (widget.Node, err)
fn checkbox(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, checked: bool, mixed: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err)
fn radio(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, selected: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err)
fn radio_group(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, selected: usize, actions: []const widget.Submit, enabled: bool) -> (widget.Node, err)
fn switch_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, on: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err)
fn segmented_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, selected: usize, actions: []const widget.Submit, enabled: bool) -> (widget.Node, err)
fn slider(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, step: f32, change: widget.Change[f32], enabled: bool) -> (widget.Node, err)
fn range_slider(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, first: f32, second: f32, low: f32, high: f32, step: f32, change: widget.Change[f32], change_second: widget.Change[f32], enabled: bool) -> (widget.Node, err)
fn progress_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, width: f32) -> (widget.Node, err)
fn progress_ring(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, size: f32) -> (widget.Node, err)
fn field_options() -> FieldOptions
fn text_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions) -> (widget.Node, err)
fn password_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions) -> (widget.Node, err)
fn search_field(a: *mem.Arena, key: widget.Key, t: *const Theme, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, clear: *const widget.Submit, options: FieldOptions) -> (widget.Node, err)
fn text_area(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], options: FieldOptions) -> (widget.Node, err)
fn select(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit) -> (widget.Node, err)
fn list_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, picks: []const widget.Submit, rows: u32, width: f32) -> (widget.Node, err)
fn field_label(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, for_key: widget.Key, required: bool) -> (widget.Node, err)
fn field_message(a: *mem.Arena, key: widget.Key, t: *const Theme, message: Message, for_key: widget.Key) -> (widget.Node, err)
fn form_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, control_key: widget.Key, control_node: widget.Node, help: str, message: Message, required: bool) -> (widget.Node, err)
fn form(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, width: f32, fields: []const widget.Node, submit: widget.Submit, cancel: widget.Submit) -> (widget.Node, err)
fn validation_summary(a: *mem.Arena, key: widget.Key, t: *const Theme, messages: []const Message, field_keys: []const widget.Key, jumps: []const widget.Submit) -> (widget.Node, err)
fn disclosure(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err)
fn expander(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err)
fn tabs(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit) -> (widget.Node, err)
fn tab_view(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit, pages: []const widget.Node) -> (widget.Node, err)
fn resizable_pane(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: layout.Axis, size: f32, low: f32, high: f32, change: widget.Change[f32], content: widget.Node) -> (widget.Node, err)
fn split_view(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: layout.Axis, first: widget.Node, second: widget.Node, position: f32, min_first: f32, min_second: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err)
fn split_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, open: bool, toggle: *const widget.Submit) -> (widget.Node, err)
fn speed_dial(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, actions: []const widget.Submit, open: bool, toggle: *const widget.Submit) -> (widget.Node, err)
fn chip(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, kind: ChipKind, selected: bool, action: *const widget.Submit, remove: *const widget.Submit) -> (widget.Node, err)
fn rating(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: u32, max: u32, change: widget.Change[u32]) -> (widget.Node, err)
fn stepper(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64]) -> (widget.Node, err)
fn spin_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64], typed: widget.Change[str]) -> (widget.Node, err)
fn dial(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, change: widget.Change[f32], size: f32) -> (widget.Node, err)
fn shortcut_recorder(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, chord: Chord, recording: bool, start: *const widget.Submit, capture: widget.Change[Chord]) -> (widget.Node, err)
fn formatted_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, adapter: Format, typed: widget.Change[str], change: widget.Change[str], options: FieldOptions) -> (widget.Node, err)
fn autocomplete(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], suggestions: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], dismiss: *const widget.Submit, options: FieldOptions) -> (widget.Node, err)
fn combo_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], choices: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], toggle: *const widget.Submit, options: FieldOptions) -> (widget.Node, err)
fn token_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, tokens: []const str, removes: []const widget.Submit, buffer: []u8, len: usize, typed: widget.Change[str], add: widget.Submit, suggestions: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
fn picker(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit, presentation: PickerForm) -> (widget.Node, err)
fn multi_select_list(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: []const bool, toggles: []const widget.Submit, rows: u32, width: f32) -> (widget.Node, err)
fn gauge(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, size: f32) -> (widget.Node, err)
fn level(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, warn: f32, danger: f32, width: f32) -> (widget.Node, err)
fn snackbar(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32) -> (widget.Node, err)
fn toast(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32) -> (widget.Node, err)
fn banner(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, width: f32) -> (widget.Node, err)
fn info_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
fn skeleton(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32, phase: f32) -> (widget.Node, err)
fn empty_state(a: *mem.Arena, key: widget.Key, t: *const Theme, icon_texture: scene.TextureId, title: str, message: str, action_label: str, action: *const widget.Submit, width: f32) -> (widget.Node, err)
fn accordion(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, contents: []const widget.Node, expanded: usize, toggles: []const widget.Submit) -> (widget.Node, err)
fn font_picker(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, families: []const str, family: usize, styles: []const str, style_index: usize, size: i64, sample: str, pick_family: widget.Change[usize], pick_style: widget.Change[usize], change_size: widget.Change[i64], rows: u32, width: f32) -> (widget.Node, err)
fn notification_list(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, notices: []const Notice, clear: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err)
```

The catalogue's controls (D813, widget plan phase 1) are functions that return node
subtrees into the caller's frame arena under a `Theme` -- the tokens, the fonts in
preference order and the language a page is set in. A control is `e.ui.widget`'s
primitives composed with the looks `e.ui.style` resolves, its internals keyed
positionally under the caller's key, and its semantics said through a `Semantics`
node; nothing here is a new primitive. Section 3.1, content (P1-01): `text` in a
text role with the layout's alignment, wrapping, line budget and ellipsis;
`selectable_text` is a read-only editor over the caller's buffer, so selection and
copy are the editor's; `rich_text` lays its spans side by side, a linked span a tap
region with the link role whose `Submit` the caller's spans must keep alive (spans
sit on one line until a span-aware layout wraps them); `icon` and `image` carry a
semantic label, an unlabelled image leaving the tree; `canvas` is the caller's
custom paint with a label. An icon is not tinted until the renderer has an image
brush.

Surfaces (D814, P1-02): `surface_style` turns a `SurfaceOptions` -- a background
role, a border, a radius, an elevation level (the theme's shadow strength, falling
two pixels a level) and padding -- into a style, and `surface` is a box with it;
`panel` is the variant surface bordered and square, `card` the surface raised one
level, rounded and hairline-bordered; `group_box` labels a bordered surface as a
group; `divider` is a hairline the tree leaves out; `badge` is a status pill in the
primary colour; `avatar` clips an image to a circle; `placeholder` is a rounded block
that is busy in the tree.

The button family (D818, P1-06): the theme carries the page's runtime, and
`control_state` reads what the pointer and the focus are doing to a keyed element
(`widget.interaction`) with what the caller says of it, so a control resolves its
look from its state each frame; `button`, `icon_button` and `toggle_button` are a
tap-and-hover region in the resolved look, at least the control height and the hit
target, with a button's semantics, and `link` a region with the link role; each
fires the `Submit` the caller keeps alive on a tap and, focused, on Enter or Space.

Discrete selection (D819, P1-07): `checkbox` and `radio` are a mark beside a label
in a tap-and-hover region centred in a box at least the hit target, the mark filled
when chosen (a bar when mixed), with the checkbox or radio role and the checked,
mixed and disabled states; `radio_group` and `segmented_control` are one per label
keyed `key + 1 + index`, each firing its own action from a slice the caller keeps
alive, a group in the tree; `switch_control` is a track with its knob at the right
when on, the filled variant then and the outlined one off, a switch in the tree.
The caller keeps the chosen value and passes it back each frame.

Range selection (D820, P1-08): `slider` and `range_slider` are a `widget.Slider`
in the theme's colours -- the track in the border colour, the filled part and the
thumbs in the primary -- 120 px long at the control height with the label beside,
a slider in the tree offering increment, decrement and set value.

Progress (D822, P1-09): `progress_bar` is a rounded track in the variant surface
with the filled part (keyed `key + 1`) in the primary colour as wide as the value
says, a quarter-wide segment a quarter in when indeterminate; `progress_ring` is a
custom-painted ring, the track and the arc from the top through the value's share
of the turn as stroked cubic quarter turns, a quarter when indeterminate. Both are
progress in the tree, busy when indeterminate; neither animates -- an indeterminate
one shows a still segment until the animation system drives it.

Text fields (D823, P1-10): every one is a `field` -- an outlined surface in the
resolved look (the border in the error colour when invalid, the focus ring when
focused) holding the editor (keyed `key`, at least its rows tall) over a placeholder
shown while the value is empty, the label above, a group in the tree with the label
and the invalid state; `text_field` is one line, `password_field` a secret editor,
`search_field` submits on Enter and shows a plain "Clear" button (keyed `key + 1`,
the caller's action) while it holds anything, `text_area` is `rows` lines tall (two
at least) and does not scroll its overflow.

Basic choice (D824, P1-11): `select` is an outlined button showing the chosen
option that fires `toggle` for the caller to open or close it; open, a modal
overlay below it (keyed `key + 1`) lists the options as menu items keyed
`key + 2 + index`, each firing its own action, a press outside firing `toggle`
again; the caller keeps `selected` and `open`. `list_box` is a clamped viewport
`rows` tall of tap regions keyed `key + 1 + index`, the selected one in the
selection colour; the viewport is a list of list items in the tree.

### `e.ui.overlay`

```neper
type MenuItem = struct { label: str, action: widget.Submit, enabled: bool }
type DialogAction = enum u8 { Plain, Default, Cancel, Destructive }
type DialogButton = struct { label: str, action: widget.Submit, kind: DialogAction }
error TooLarge
fn tooltip_wanted(t: *const control.Theme, anchor: widget.Key) -> bool
fn tooltip(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, text: str, shown: bool) -> (widget.Node, err)
fn menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err)
fn menu_button(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const MenuItem, open: bool, toggle: *const widget.Submit) -> (widget.Node, err)
fn alert_dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, message: str, buttons: []const DialogButton, open: bool) -> (widget.Node, err)
fn dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool) -> (widget.Node, err)
fn popup(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, content: widget.Node, open: bool) -> (widget.Node, err)
fn flyout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err)
fn popover(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err)
fn sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
fn bottom_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, height: f32) -> (widget.Node, err)
fn action_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err)
fn calendar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, shown: time.Date, selected: time.Date, has_selected: bool, ranged: bool, from: time.Date, to: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err)
fn date_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Date, has_value: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err)
fn date_range_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, from: time.Date, to: time.Date, has_range: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err)
fn time_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Time, seconds: bool, change: widget.Change[time.Time]) -> (widget.Node, err)
fn duration_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Duration, change: widget.Change[time.Duration]) -> (widget.Node, err)
fn color_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: paint.Color, with_alpha: bool, change: widget.Change[paint.Color], width: f32) -> (widget.Node, err)
```

### `e.ui.navigation`

```neper
type Action = struct { label: str, action: widget.Submit, icon: scene.TextureId, enabled: bool }
type DestinationForm = enum u8 { Bottom, Rail, Sidebar }
type MenuBarItem = struct { label: str, items: []const overlay.MenuItem }
error TooLarge
fn app_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, leading: []const Action, trailing: []const Action, width: f32) -> (widget.Node, err)
fn toolbar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const Action) -> (widget.Node, err)
fn status_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, sections: []const str, width: f32) -> (widget.Node, err)
fn navigation_stack(a: *mem.Arena, key: widget.Key, t: *const control.Theme, titles: []const str, pages: []const widget.Node, pop: *const widget.Submit, width: f32) -> (widget.Node, err)
fn destination_form(width: f32) -> DestinationForm
fn destination_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, form: DestinationForm, extent: f32) -> (widget.Node, err)
fn menu_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, menus: []const MenuBarItem, open: usize, toggles: []const widget.Submit) -> (widget.Node, err)
fn context_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const overlay.MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err)
fn navigation_split(a: *mem.Arena, key: widget.Key, t: *const control.Theme, primary: widget.Node, detail: widget.Node, showing_detail: bool, position: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err)
fn navigation_drawer(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
fn navigation_rail(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err)
fn bottom_navigation(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err)
fn sidebar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err)
fn breadcrumbs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, picks: []const widget.Submit) -> (widget.Node, err)
fn document_tabs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove]) -> (widget.Node, err)
fn dock_panel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, close: *const widget.Submit) -> (widget.Node, err)
fn dock_layout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, left: widget.Node, centre: widget.Node, right: widget.Node, bottom: widget.Node, sizes: DockSizes, change: widget.Change[DockSizes], width: f32, height: f32) -> (widget.Node, err)
fn multi_document_workspace(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, view: widget.Node, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove], width: f32, height: f32) -> (widget.Node, err)
fn wizard(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, steps: []const str, current: usize, content: widget.Node, can_advance: bool, back: *const widget.Submit, next: *const widget.Submit, finish: *const widget.Submit, cancel: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err)
fn window_switcher(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
fn command_palette(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], commands: []const str, active: usize, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err)
```

### `e.ui.collection`

```neper
type Source = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, build: fn(*void, *mem.Arena, usize, *widget.Node) -> err }
type Reorder = struct { from: usize, to: usize }
type Column = struct { title: str, width: f32 }
type TableSource = struct { ctx: *void, count: fn(*void) -> usize, key: fn(*void, usize) -> widget.Key, cell: fn(*void, *mem.Arena, usize, usize, *widget.Node) -> err }
type ColumnResize = struct { column: usize, width: f32 }
type CellSource = struct { ctx: *void, cell: fn(*void, *mem.Arena, widget.Key, usize, *widget.Node) -> err }
type TreeSource = struct { ctx: *void, count: fn(*void, widget.Key) -> usize, key: fn(*void, widget.Key, usize) -> widget.Key, has_children: fn(*void, widget.Key) -> bool, build: fn(*void, *mem.Arena, widget.Key, *widget.Node) -> err }
type Property = struct { key: widget.Key, name: str, group: str }
type PropertySource = struct { ctx: *void, count: fn(*void) -> usize, property: fn(*void, usize) -> Property, editor: fn(*void, *mem.Arena, usize, *widget.Node) -> err }
type Pair = struct { name: []u8, name_len: usize, value: []u8, value_len: usize }
type PairEdit = struct { index: usize, value: bool, text: str }
error TooLarge
fn list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, selected: []const widget.Key, separators: bool, width: f32) -> (widget.Node, err)
fn virtual_list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: Source, selected: []const widget.Key, extent: f32, offset: f32, change: widget.Change[f32], separators: bool, width: f32, height: f32) -> (widget.Node, err)
fn grid_view(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, selected: []const widget.Key, cell_size: geometry.Size, gap: f32, width: f32) -> (widget.Node, err)
fn virtual_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: Source, selected: []const widget.Key, cell_size: geometry.Size, gap: f32, offset: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err)
fn page_view(a: *mem.Arena, key: widget.Key, t: *const control.Theme, pages: []const widget.Node, current: usize, turn: widget.Change[usize], width: f32, height: f32) -> (widget.Node, err)
fn page_indicator(a: *mem.Arena, key: widget.Key, t: *const control.Theme, count: usize, current: usize, turn: widget.Change[usize]) -> (widget.Node, err)
fn pagination(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: usize, current: usize, window: usize, turn: widget.Change[usize]) -> (widget.Node, err)
fn carousel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, pages: []const widget.Node, current: usize, turn: widget.Change[usize], width: f32, height: f32) -> (widget.Node, err)
fn reorderable_list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const widget.Node, keys: []const widget.Key, extent: f32, move: widget.Change[Reorder], width: f32) -> (widget.Node, err)
fn pull_to_refresh(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, refreshing: bool, refresh: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err)
fn swipe_actions(a: *mem.Arena, key: widget.Key, t: *const control.Theme, content: widget.Node, labels: []const str, actions: []const widget.Submit, revealed: bool, reveal: widget.Change[bool], width: f32, height: f32) -> (widget.Node, err)
fn table(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32) -> (widget.Node, err)
fn data_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TableSource, selected: []const widget.Key, sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], pick: widget.Change[widget.Key], extent: f32, offset: f32, change: widget.Change[f32], height: f32) -> (widget.Node, err)
fn tree(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err)
fn outline(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: TreeSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], extent: f32, width: f32) -> (widget.Node, err)
fn tree_table(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, columns: []const Column, source: TreeSource, cells_of: CellSource, expanded: []const widget.Key, selected: []const widget.Key, toggle: widget.Change[widget.Key], pick: widget.Change[widget.Key], sort_column: usize, descending: bool, sort: widget.Change[usize], reorder: widget.Change[Reorder], resize: widget.Change[ColumnResize], extent: f32) -> (widget.Node, err)
fn property_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, source: PropertySource, collapsed: []const widget.Key, toggle: widget.Change[widget.Key], name_width: f32, width: f32) -> (widget.Node, err)
fn key_value_editor(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, pairs: []const Pair, edit: widget.Change[PairEdit], remove: widget.Change[usize], add: *const widget.Submit, width: f32) -> (widget.Node, err)
```

### `e.ui.app`

```neper
type App = struct { state: *void }
type Builder[Ctx: type] = struct { ctx: *Ctx, build: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err) }
type Options = struct { window: window.Options, widget_limits: widget.Limits, frame_arena_bytes: usize, event_capacity: usize, backend: gpu.Backend }
error Closed
error Failed

fn init[Ctx: type](a: *mem.Arena, options: Options, builder: Builder[Ctx]) -> (App, err)
fn step(app: *App, timeout: time.Duration) -> (bool, err)
fn run(app: *App) -> err
fn stop(app: *App)
fn close(app: *App) -> err
fn frames_of(app: *const App) -> u64
type Tray = struct { id: u32, width: u32, height: u32, source: []const u32, composed: []u32, tooltip: str, badge: u32, menu: []const shell.MenuItem, open: bool }
type TrayActivationKind = enum u8 { Select, Open, Command, Dismissed, NoticeSelect, NoticeDismiss }
type Notification = struct { title: str, body: str, silent: bool }
type ContentType = struct { kind: shell.ContentKind, mime: str }
type DataProvider = struct { ctx: *void, provide: fn(*void, *mem.Arena, ContentType, *shell.Content) -> err }
type DataOffer = struct { types: []const ContentType, provider: DataProvider }
type DragOperation = struct { allow_move: bool }
type ClipboardMonitor = struct { sequence: u32 }
type DocumentGrant = struct { path: str }
type FileDialogOptions = struct { title: str, filters: []const shell.FileFilter, initial: str, default_extension: str, folder: str }
type TrayActivation = struct { kind: TrayActivationKind, command: u32, x: i32, y: i32 }
fn tray_supported() -> bool
fn tray_open(a: *mem.Arena, id: u32, icon: shell.Icon, tooltip: str) -> (Tray, err)
fn tray_set_icon(a: *mem.Arena, t: *Tray, icon: shell.Icon) -> err
fn tray_set_tooltip(a: *mem.Arena, t: *Tray, tooltip: str) -> err
fn tray_set_badge(a: *mem.Arena, t: *Tray, count: u32) -> err
fn tray_set_menu(t: *Tray, items: []const shell.MenuItem)
fn tray_poll(a: *mem.Arena, t: *Tray) -> (TrayActivation, bool, err)
fn tray_close(a: *mem.Arena, t: *Tray) -> err
fn taskbar_supported() -> bool
fn jump_list_supported() -> bool
fn taskbar_progress(a: *mem.Arena, app: *App, state: shell.ProgressState, completed: u64, total: u64) -> err
fn taskbar_overlay(a: *mem.Arena, app: *App, icon: shell.Icon, description: str) -> err
fn jump_list(a: *mem.Arena, tasks: []const shell.JumpTask) -> err
fn jump_list_clear(a: *mem.Arena) -> err
fn shell_capabilities() -> shell.Capabilities
fn open_uri(a: *mem.Arena, uri: str) -> err
fn reveal_in_file_manager(a: *mem.Arena, path: str) -> err
fn move_to_trash(a: *mem.Arena, path: str) -> err
fn notification_permission(a: *mem.Arena) -> shell.NoticePermission
fn notification_supported() -> bool
fn notification_actions_supported() -> bool
fn notify(a: *mem.Arena, t: *const Tray, n: Notification) -> (u32, err)
fn notification_update(a: *mem.Arena, t: *const Tray, notice_id: u32, n: Notification) -> err
fn notification_remove(a: *mem.Arena, t: *const Tray, notice_id: u32) -> err
fn content_type_name(t: ContentType) -> str
fn content_type_of(name: str) -> ContentType
fn content_type_of_content(c: shell.Content) -> ContentType
fn same_type(x: ContentType, y: ContentType) -> bool
fn offer_materialize(a: *mem.Arena, offer: DataOffer) -> ([]shell.Content, err)
fn offer_of(a: *mem.Arena, items: []const shell.Content) -> (DataOffer, err)
fn drag_source_supported() -> bool
fn drop_target_supported() -> bool
fn drag_offer(a: *mem.Arena, offer: DataOffer, operation: DragOperation) -> (shell.DragResult, err)
fn drop_target_open(a: *mem.Arena, app: *App, storage: *mem.Arena) -> err
fn drop_target_close(a: *mem.Arena, app: *App) -> err
fn drop_take() -> (shell.Drop, bool)
fn promised_file(name: str, contents: []const u8) -> shell.Content
fn clipboard_supported() -> bool
fn clipboard_offer(a: *mem.Arena, offer: DataOffer) -> err
fn clipboard_holds(a: *mem.Arena, t: ContentType) -> bool
fn clipboard_take(a: *mem.Arena, t: ContentType) -> (shell.Content, err)
fn clipboard_monitor() -> ClipboardMonitor
fn clipboard_changed(m: *ClipboardMonitor) -> bool
fn share_supported() -> bool
fn share_target_supported() -> bool
fn share(a: *mem.Arena, offer: DataOffer) -> err
fn share_target_take() -> (shell.Drop, bool)
fn file_dialogs_supported() -> bool
fn recent_documents_supported() -> bool
fn grant_of(path: str) -> DocumentGrant
fn grant_path(g: DocumentGrant) -> str
fn open_file(a: *mem.Arena, owner: *App, options: FileDialogOptions, multiple: bool) -> ([]DocumentGrant, err)
fn save_file(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err)
fn pick_folder(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err)
fn recent_add(a: *mem.Arena, g: DocumentGrant) -> err
fn activation(a: *mem.Arena, args: []const str) -> shell.Activation
fn associations_supported() -> bool
fn startup_supported() -> bool
fn single_instance_supported() -> bool
fn register_file_type(a: *mem.Arena, extension: str, program_id: str, description: str) -> err
fn unregister_file_type(a: *mem.Arena, extension: str, program_id: str) -> err
fn register_protocol(a: *mem.Arena, scheme: str, description: str) -> err
fn unregister_protocol(a: *mem.Arena, scheme: str) -> err
fn startup_registration(a: *mem.Arena, id: str, enabled: bool) -> err
fn startup_registered(a: *mem.Arena, id: str) -> (bool, err)
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err)
fn activation_poll() -> (shell.Activation, bool)
type GlobalShortcutSession = struct { registered: u32 }
type PowerInhibitor = struct { held: bool }
fn global_shortcuts_supported() -> bool
fn power_inhibit_supported() -> bool
fn lifecycle_events_supported() -> bool
fn session_restore_supported() -> bool
fn global_shortcut_session() -> GlobalShortcutSession
fn global_shortcut_add(a: *mem.Arena, session: *GlobalShortcutSession, id: u32, key: shell.Hotkey) -> err
fn global_shortcut_remove(a: *mem.Arena, session: *GlobalShortcutSession, id: u32) -> err
fn global_shortcut_poll() -> (u32, bool)
fn background_permission(a: *mem.Arena) -> shell.Permission
fn login_item_set(a: *mem.Arena, id: str, enabled: bool) -> err
fn login_item_enabled(a: *mem.Arena, id: str) -> (bool, err)
fn power_inhibitor_acquire(a: *mem.Arena, keep_display: bool) -> (PowerInhibitor, err)
fn power_inhibitor_release(a: *mem.Arena, inhibitor: *PowerInhibitor) -> err
fn lifecycle_poll() -> (shell.LifecycleEvent, bool)
fn session_restore_register(a: *mem.Arena, arguments: str) -> err
fn session_restore_unregister(a: *mem.Arena) -> err
fn printing_supported() -> bool
fn print_dialogs_supported() -> bool
fn print_dialog(a: *mem.Arena, owner: *App, min_page: u32, max_page: u32) -> (shell.Printer, err)
fn page_setup_dialog(a: *mem.Arena, owner: *App, current: shell.PageSetup) -> (shell.PageSetup, err)
fn printer_open(a: *mem.Arena, name: str) -> (shell.Printer, err)
fn printer_close(a: *mem.Arena, printer: shell.Printer) -> err
fn printer_page(printer: shell.Printer) -> shell.PrintPage
fn print_job_start(a: *mem.Arena, printer: shell.Printer, document: str, output: str) -> (shell.PrintJob, err)
fn print_job_page(a: *mem.Arena, job: *shell.PrintJob, page: shell.Icon) -> err
fn print_job_end(a: *mem.Arena, job: *shell.PrintJob) -> err
fn print_job_cancel(a: *mem.Arena, job: *shell.PrintJob) -> err
fn permission_status(a: *mem.Arena, c: shell.Capability) -> shell.Permission
fn permission_request(a: *mem.Arena, c: shell.Capability) -> (shell.Permission, err)
fn camera_access(a: *mem.Arena) -> (shell.Permission, err)
fn microphone_access(a: *mem.Arena) -> (shell.Permission, err)
fn location_access(a: *mem.Arena) -> (shell.Permission, err)
fn photo_picker_supported() -> bool
fn pick_photos(a: *mem.Arena, owner: *App, multiple: bool) -> ([]DocumentGrant, err)
fn biometrics_supported() -> bool
fn biometric_verify(a: *mem.Arena, reason: str) -> (shell.Permission, err)
fn credentials_supported() -> bool
fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err
fn credential_read(a: *mem.Arena, target_name: str) -> (shell.Credential, err)
fn credential_delete(a: *mem.Arena, target_name: str) -> err
fn screen_capture_supported() -> bool
fn screen_capture(a: *mem.Arena) -> (shell.Icon, err)
```

`step` drains ordered input, rebuilds only invalidated subtrees, reconciles, lays out,
compiles a scene and presents when a frame is due. It returns `false` after the last
window closes or `stop` is called. `run` is exactly a loop over `step`; applications
retain control by calling `step` themselves. All memory comes from the application
arena plus a bounded frame arena reset after presentation.

All document decoders allocate retained strings and nodes in the arena passed to the
call. Streaming readers retain only their documented scratch state. Every writer uses
`io.Writer`; no format module opens files.

---

## 9. Interchange formats

### `e.fmt.json`

```neper
type Number = struct { lexeme: str }
type Member = struct { key: str, value: Value }
type Value = union enum u8 { Null, Bool: bool, Number: Number, String: str, Array: []const Value, Object: []const Member }
type Event = union enum u8 { Null, Bool: bool, Number: Number, String: str, Key: str, BeginArray, EndArray, BeginObject, EndObject }
type Reader = struct { state: *void }
type Options = struct { allow_duplicate_keys: bool, max_depth: u16 }
error Invalid
error TooDeep
error DuplicateKey
error TooLarge

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err)
fn reader_next_err(r: *Reader) -> (Event, bool, err)
fn parse(a: *mem.Arena, source: str, options: Options) -> (Value, err)
fn write(writer: *io.Writer, value: *const Value) -> err
fn write_pretty(writer: *io.Writer, value: *const Value, indent: u8) -> err
fn encode[T: type](writer: *io.Writer, value: *const T) -> err
fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err)
error InvalidPointer
error PatchFailed

fn number(source: str) -> (Number, err)
fn number_i64(value: Number) -> (i64, err)
fn number_u64(value: Number) -> (u64, err)
fn number_f64(value: Number) -> (f64, err)
fn number_from_i64(a: *mem.Arena, value: i64) -> (Number, err)
fn number_from_u64(a: *mem.Arena, value: u64) -> (Number, err)
fn number_from_f64(a: *mem.Arena, value: f64) -> (Number, err)
fn pointer(root: *const Value, path: str) -> (*const Value, err)
fn patch(a: *mem.Arena, root: *const Value, operations: *const Value, max_operations: usize, max_depth: u16) -> (Value, err)

```

Numbers preserve their validated JSON lexeme, including large integers, exponent
spelling and negative zero. parse borrows number lexemes from source; streaming
events borrow reader-owned storage until the next reader call. Writers revalidate
public Number values and never silently round them through f64. number_i64/u64
accept mathematically integral values exactly in range (including exponent forms);
number_f64 explicitly rounds to nearest ties-to-even and rejects nonfinite overflow.
Typed integer encode/decode never takes a floating-point detour. Object order is
preserved; duplicate keys are rejected unless Options explicitly allows them.
These are semantic round trips, not whitespace-preserving source edits. Structural
encoding/decoding still uses spec §9. See stdlib-hardening.md SL04.


pointer follows RFC 6901 JSON Pointer, including the empty root pointer and ~0/~1
escapes; URI-fragment notation is not accepted by this function. patch implements
RFC 6902 add/remove/replace/move/copy/test into a new arena-owned tree. It never
mutates root; all output strings and number lexemes are copied. Failure rolls back
its own arena allocations and returns zero. Duplicate-key objects anywhere in a
patch input are rejected. Numeric test equality is exact mathematical equality,
not f64 equality. Limits, invalid array indices, move-into-descendant and missing
targets fail explicitly. Source-file edits additionally require H09 transactions.

### `e.fmt.json.schema`

```neper
type Checker = struct { arena: *mem.Arena, root: *const json.Value, path: []u8 }
error Invalid
error TooSmall
error TooDeep
const MAX_DEPTH: usize = 256usize

fn member(members: []const json.Member, name: str) -> (usize, bool)
fn append_byte(c: *Checker, n: usize, byte: u8) -> (usize, err)
fn append_key(c: *Checker, n: usize, key: str) -> (usize, err)
fn append_index(c: *Checker, n: usize, index: usize) -> (usize, err)
fn is_integer(v: *const json.Value) -> bool
fn type_matches(name: str, v: *const json.Value) -> (bool, err)
fn schema_f64(s: *const json.Value) -> (f64, err)
fn schema_usize(s: *const json.Value) -> (usize, err)
fn code_points(s: str) -> usize
fn resolve_ref(c: *Checker, reference: str) -> (*const json.Value, err)
fn check_number(s: []const json.Member, v: f64) -> (bool, err)
fn check_string(c: *Checker, s: []const json.Member, v: str) -> (bool, err)
fn check_array(c: *Checker, s: []const json.Member, items: []const json.Value, n: usize, depth: usize) -> (bool, usize, err)
fn check_object(c: *Checker, s: []const json.Member, members: []const json.Member, n: usize, depth: usize) -> (bool, usize, err)
fn subschemas(s: []const json.Member, name: str) -> ([]const json.Value, bool, err)
fn check(c: *Checker, schema: *const json.Value, v: *const json.Value, n: usize, depth: usize) -> (bool, usize, err)
fn validate_value(a: *mem.Arena, root: *const json.Value, doc: *const json.Value, path: []u8) -> (bool, usize, err)
fn validate(a: *mem.Arena, schema_json: str, doc_json: str, path: []u8) -> (bool, usize, err)
```

`validate` and `validate_value` over parsed e.fmt.json trees: type, enum, const,
numeric bounds and multipleOf, string lengths and pattern (e.text.regex), array bounds,
uniqueItems, items, required, properties, additionalProperties, allOf/anyOf/oneOf/not,
boolean schemas and `$ref` to `#` and `#/$defs/name`; the first failing pointer is written
to a caller buffer.

### `e.fmt.csv`

```neper
type Dialect = struct { delimiter: u8, quote: u8, crlf: bool, header: bool }
type Row = struct { fields: []const str }
type Reader = struct { state: *void }
error Invalid
error TooLarge

fn csv() -> Dialect
fn tsv() -> Dialect
fn reader(a: *mem.Arena, source: io.Reader, dialect: Dialect, field_limit: usize, row_limit: usize) -> (Reader, err)
fn reader_next_err(r: *Reader) -> (Row, bool, err)
fn write_row(writer: *io.Writer, row: Row, dialect: Dialect) -> err
fn decode_rows[T: type](a: *mem.Arena, source: io.Reader, dialect: Dialect) -> ([]T, err)
fn encode_rows[T: type](writer: *io.Writer, rows: []const T, dialect: Dialect) -> err
```

### `e.fmt.ini`

```neper
type Entry = struct { section: str, key: str, value: str }
type Document = struct { entries: []const Entry }
type Reader = struct { state: *void }
type Options = struct { case_sensitive: bool, allow_duplicate_keys: bool }
error Invalid
error DuplicateKey
error TooLarge

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err)
fn reader_next_err(r: *Reader) -> (Entry, bool, err)
fn parse(a: *mem.Arena, source: str, options: Options) -> (Document, err)
fn get(document: *const Document, section: str, key: str) -> (str, bool)
fn write(writer: *io.Writer, document: *const Document) -> err
fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err)
fn encode[T: type](writer: *io.Writer, value: *const T) -> err
```

The accepted syntax is sections, `key=value`, `;`/`#` line comments, quoted values,
and backslash escapes. It deliberately excludes interpolation and includes.

### `e.fmt.semver`

```neper
type Version = struct { major: u64, minor: u64, patch: u64, prerelease: str, build: str }
type Partial = struct { major: u64, minor: u64, patch: u64, prerelease: str, x_major: bool, x_minor: bool, x_patch: bool }
type SetState = struct { all: bool, prerelease_allowed: bool }
error Invalid
error TooSmall
const DOT: u8 = 46u8
const DASH: u8 = 45u8
const PLUS: u8 = 43u8
const ZERO: u8 = 48u8
const NINE: u8 = 57u8
const LOWER_X: u8 = 120u8
const UPPER_X: u8 = 88u8
const STAR: u8 = 42u8
const LOWER_V: u8 = 118u8
const EQUALS: u8 = 61u8
const LESS: u8 = 60u8
const GREATER: u8 = 62u8
const CARET: u8 = 94u8
const TILDE: u8 = 126u8
const BAR: u8 = 124u8
const OP_ANY: u8 = 0u8
const OP_EQ: u8 = 1u8
const OP_LT: u8 = 2u8
const OP_LE: u8 = 3u8
const OP_GT: u8 = 4u8
const OP_GE: u8 = 5u8
const OP_CARET: u8 = 6u8
const OP_TILDE: u8 = 7u8

fn is_digit(b: u8) -> bool
fn is_ident_byte(b: u8) -> bool
fn is_numeric(s: str) -> bool
fn parse_number(s: str) -> (u64, err)
fn valid_identifiers(s: str, strict: bool) -> bool
fn core_end(s: str) -> usize
fn parse_tails(s: str, from: usize) -> (str, str, err)
fn parse(text: str) -> (Version, err)
fn cmp_u64(a: u64, b: u64) -> i32
fn cmp_identifier(a: str, b: str) -> i32
fn next_identifier(s: str, at: usize) -> (str, usize)
fn cmp_prerelease(a: str, b: str) -> i32
fn cmp(a: Version, b: Version) -> i32
fn put_byte(out: []u8, at: *usize, b: u8) -> err
fn put_text(out: []u8, at: *usize, s: str) -> err
fn put_number(out: []u8, at: *usize, value: u64) -> err
fn format(v: Version, out: []u8) -> (usize, err)
fn put_version(v: Version, out: []u8, at: *usize) -> err
fn is_x(s: str) -> bool
fn partial_component(s: str, present: bool) -> (u64, bool, err)
fn parse_partial(text: str) -> (Partial, err)
fn version_of(major: u64, minor: u64, patch: u64, prerelease: str) -> Version
fn test_op(op: u8, bound: Version, v: Version) -> bool
fn apply(s: *SetState, op: u8, bound: Version, v: Version)
fn apply_caret(s: *SetState, p: Partial, v: Version)
fn apply_tilde(s: *SetState, p: Partial, v: Version)
fn apply_xrange(s: *SetState, op: u8, p: Partial, v: Version)
fn apply_hyphen(s: *SetState, from: Partial, to: Partial, v: Version)
fn split_op(token: str) -> (u8, usize)
fn next_token(s: str, at: *usize) -> (str, bool)
fn satisfies_set(v: Version, set: str) -> (bool, err)
fn satisfies(v: Version, range: str) -> (bool, err)
```

`parse` (SemVer 2.0.0 with an optional `v`), `cmp` (spec precedence; build ignored),
`format` and `satisfies` over node-style ranges (`^ ~ = < <= > >=`, wildcards, hyphen
ranges, whitespace AND, `||` OR) desugared as read.

### `e.fmt.cbor`

```neper
type Encoder = struct { out: []u8, len: usize }
type Decoder = struct { data: []const u8, at: usize }
type Item = struct { major: u8, info: u8, value: u64, indefinite: bool }
error Invalid
error Truncated
error TooSmall
error Mismatch
const MAJOR_UINT: u8 = 0u8
const MAJOR_NEGATIVE: u8 = 1u8
const MAJOR_BYTES: u8 = 2u8
const MAJOR_TEXT: u8 = 3u8
const MAJOR_ARRAY: u8 = 4u8
const MAJOR_MAP: u8 = 5u8
const MAJOR_TAG: u8 = 6u8
const MAJOR_SIMPLE: u8 = 7u8
const SIMPLE_FALSE: u64 = 20u64
const SIMPLE_TRUE: u64 = 21u64
const SIMPLE_NULL: u64 = 22u64
const SIMPLE_UNDEFINED: u64 = 23u64
const INFO_INDEFINITE: u8 = 31u8
const BREAK: u8 = 255u8

fn encoder(out: []u8) -> Encoder
fn encoded(e: *const Encoder) -> []const u8
fn put(e: *Encoder, b: u8) -> err
fn put_all(e: *Encoder, data: []const u8) -> err
fn put_be(e: *Encoder, value: u64, width: usize) -> err
fn encode_head(e: *Encoder, major: u8, value: u64) -> err
fn encode_uint(e: *Encoder, value: u64) -> err
fn encode_int(e: *Encoder, value: i64) -> err
fn encode_negative(e: *Encoder, argument: u64) -> err
fn encode_bytes(e: *Encoder, data: []const u8) -> err
fn encode_text(e: *Encoder, text: str) -> err
fn encode_array(e: *Encoder, count: usize) -> err
fn encode_map(e: *Encoder, count: usize) -> err
fn encode_tag(e: *Encoder, tag: u64) -> err
fn encode_bool(e: *Encoder, value: bool) -> err
fn encode_null(e: *Encoder) -> err
fn encode_undefined(e: *Encoder) -> err
fn encode_simple(e: *Encoder, value: u8) -> err
fn encode_f64(e: *Encoder, value: f64) -> err
fn encode_f32(e: *Encoder, value: f32) -> err
fn begin_array(e: *Encoder) -> err
fn begin_map(e: *Encoder) -> err
fn encode_break(e: *Encoder) -> err
fn decoder(data: []const u8) -> Decoder
fn remaining(d: *const Decoder) -> usize
fn take(d: *Decoder) -> (u8, err)
fn take_be(d: *Decoder, width: usize) -> (u64, err)
fn decode_head(d: *Decoder) -> (Item, err)
fn at_break(d: *const Decoder) -> bool
fn expect(d: *Decoder, major: u8) -> (Item, err)
fn decode_uint(d: *Decoder) -> (u64, err)
fn decode_int(d: *Decoder) -> (i64, err)
fn payload(d: *Decoder, major: u8) -> ([]const u8, err)
fn decode_bytes(d: *Decoder) -> ([]const u8, err)
fn decode_text(d: *Decoder) -> (str, err)
fn decode_array_len(d: *Decoder) -> (usize, bool, err)
fn decode_map_len(d: *Decoder) -> (usize, bool, err)
fn decode_tag(d: *Decoder) -> (u64, err)
fn decode_bool(d: *Decoder) -> (bool, err)
fn decode_null(d: *Decoder) -> err
fn pow2(exponent: i64) -> f64
fn f16_to_f64(bits: u64) -> f64
fn decode_f64(d: *Decoder) -> (f64, err)
fn skip(d: *Decoder) -> err
```

A streaming `Encoder` over a caller buffer (`encode_uint/int/negative/bytes/text/
array/map/tag/bool/null/undefined/simple/f64/f32`, indefinite `begin_array/begin_map`,
`encode_break`) and a `Decoder` (`decode_head` for the whole grammar, typed readers,
`decode_f64` over f16/f32/f64, `skip` over nested and indefinite items).

### `e.fmt.toml`

```neper
type Kind = enum u8 { String, Integer, Float, Bool, Datetime, ArrayStart, ArrayEnd, InlineTableStart, InlineTableEnd }
type EventKind = enum u8 { End, TableStart, ArrayTableStart, Key, Value }
type Value = struct { kind: Kind, text: str, integer: i64, float: f64, boolean: bool }
type Event = struct { kind: EventKind, path: []const str, value: Value }
type Parser = struct { source: str, at: usize, keys: []str, scratch: []u8, used: usize, stack: [MAX_DEPTH]u8, depth: usize, need_eol: bool }
error Invalid
error TooLarge
error TooDeep
const MAX_DEPTH: usize = 32usize
const ARRAY_FIRST: u8 = 1u8
const ARRAY_MORE: u8 = 2u8
const TABLE_FIRST: u8 = 3u8
const TABLE_MORE: u8 = 4u8
const TAB: u8 = 9u8
const LF: u8 = 10u8
const CR: u8 = 13u8
const SPACE: u8 = 32u8
const HASH: u8 = 35u8
const DQUOTE: u8 = 34u8
const SQUOTE: u8 = 39u8
const BACKSLASH: u8 = 92u8

fn parser(source: str, keys: []str, scratch: []u8) -> Parser
fn peek(p: *Parser) -> u8
fn peek_at(p: *Parser, ahead: usize) -> u8
fn skip_space(p: *Parser)
fn skip_comment(p: *Parser)
fn skip_blank(p: *Parser)
fn expect_eol(p: *Parser) -> err
fn put(p: *Parser, byte: u8) -> err
fn put_utf8(p: *Parser, point: u32) -> err
fn hex_value(byte: u8) -> (u32, bool)
fn escape(p: *Parser, multi: bool) -> err
fn basic(p: *Parser) -> (str, err)
fn multi_basic(p: *Parser) -> (str, err)
fn literal(p: *Parser) -> (str, err)
fn multi_literal(p: *Parser) -> (str, err)
fn is_bare(c: u8) -> bool
fn key_path(p: *Parser) -> ([]const str, err)
fn is_digit(c: u8) -> bool
fn strip_underscores(p: *Parser, text: str) -> (str, err)
fn looks_like_datetime(text: str) -> bool
fn datetime_ok(text: str) -> bool
fn number(p: *Parser, text: str) -> (Value, err)
fn push_container(p: *Parser, state: u8) -> err
fn value(p: *Parser) -> (Value, err)
fn pop(p: *Parser)
fn parse(p: *Parser) -> (Event, err)
```

A pull parser: `parser` over the source with caller key slots and a decode scratch,
`parse` yielding table, array-table, key and value events (dotted, basic and literal
keys; every string form and escape; integers with `_` and radix prefixes; floats with
`inf`/`nan`; datetimes as text; nested arrays and inline tables as start/end events).

### `e.fmt.markdown`

```neper
type BlockKind = enum u8 { ParagraphStart, ParagraphEnd, HeadingStart, HeadingEnd, FencedCodeStart, FencedCodeEnd, IndentedCodeStart, IndentedCodeEnd, ThematicBreak, BlockQuoteStart, BlockQuoteEnd, BulletListStart, BulletListEnd, OrderedListStart, OrderedListEnd, ItemStart, ItemEnd, Line }
type Block = struct { kind: BlockKind, level: u32, start: usize, len: usize, indent: usize, loose: bool, extra_start: usize, extra_len: usize }
type InlineKind = enum u8 { Text, Code, Emph, Strong, Link, Image, Autolink, Email, SoftBreak, HardBreak }
type Inline = struct { kind: InlineKind, start: usize, len: usize, extra_start: usize, extra_len: usize, title_start: usize, title_len: usize }
type Blocks = struct { text: str, out: []Block, count: usize, kind: [MAX_DEPTH]u8, data: [MAX_DEPTH]usize, marker: [MAX_DEPTH]u8, ordered: [MAX_DEPTH]bool, blank_pending: [MAX_DEPTH]bool, loose: [MAX_DEPTH]bool, open: usize, leaf: u8, leaf_index: usize, fence_char: u8, fence_len: usize, fence_indent: usize, pending_blanks: usize }
type Delimiter = struct { pos: usize, count: usize, original: usize, ch: u8, can_open: bool, can_close: bool, active: bool, removed: bool, node: usize }
type Inlines = struct { text: str, out: []Inline, count: usize, delimiters: [MAX_DELIMITERS]Delimiter, delimiter_count: usize }
error TooLarge
error TooDeep
const MAX_DEPTH: usize = 32usize
const MAX_DELIMITERS: usize = 128usize
const TAB: u8 = 9u8
const LF: u8 = 10u8
const CR: u8 = 13u8
const SPACE: u8 = 32u8
const QUOTE: u8 = 1u8
const LIST: u8 = 2u8
const ITEM: u8 = 3u8
const LEAF_NONE: u8 = 0u8
const LEAF_PARAGRAPH: u8 = 1u8
const LEAF_FENCED: u8 = 2u8
const LEAF_INDENTED: u8 = 3u8

fn emit(s: *Blocks, kind: BlockKind, start: usize, len: usize) -> (usize, err)
fn spaces_from(text: str, at: usize, stop: usize) -> usize
fn close_leaf(s: *Blocks) -> err
fn close_from(s: *Blocks, from: usize) -> err
fn close_unmatched(s: *Blocks, matched: usize) -> err
fn push(s: *Blocks, kind: u8, data: usize) -> err
fn settle_lists(s: *Blocks)
fn note_blank(s: *Blocks)
fn open_leaf(s: *Blocks, kind: BlockKind, leaf: u8) -> err
fn is_break_char(c: u8) -> bool
fn is_thematic(text: str, at: usize, stop: usize) -> bool
fn only_spaces(text: str, at: usize, stop: usize) -> bool
fn heading_content(text: str, at: usize, stop: usize) -> (usize, usize)
fn line(s: *Blocks, at: usize, stop: usize) -> err
fn process(s: *Blocks, at: usize, stop: usize) -> err
fn parse_blocks(text: str, out: []Block) -> (usize, err)
fn add(s: *Inlines, kind: InlineKind, start: usize, len: usize) -> (usize, err)
fn add_delimiter(s: *Inlines, d: Delimiter) -> err
fn is_punct(c: u8) -> bool
fn is_white(c: u8) -> bool
fn is_scheme_char(c: u8) -> bool
fn autolink(text: str, at: usize) -> (usize, bool, bool)
fn code_span(text: str, at: usize, run_end: usize) -> (usize, usize, usize, bool)
fn link_tail(text: str, at: usize) -> (usize, usize, usize, usize, usize, bool)
fn process_emphasis(s: *Inlines, bottom: usize) -> err
fn flush_text(s: *Inlines, from: usize, to: usize) -> err
fn parse_inlines(text: str, out: []Inline) -> (usize, err)
fn is_container(kind: InlineKind) -> bool
fn later(a: Inline, b: Inline) -> bool
```

`parse_blocks` (a container-stack line parser: ATX and setext headings, thematic
breaks, fenced and indented code, nested block quotes, bullet and ordered lists with
tight/loose, paragraphs with lazy continuation) and `parse_inlines` (the delimiter-run
algorithm for emphasis, code spans, links and images with titles, autolinks, hard and
soft breaks, escapes), both as caller arrays of spans over the input.

### `e.fmt.pretty`

```neper
type Kind = enum u8 { Text, Line, SoftLine, Nest, Concat, Group }
type Doc = struct { kind: Kind, content: str, indent: u32, first: u32, second: u32 }
type Pool = struct { docs: []Doc, used: usize }
type Frame = struct { doc: u32, indent: u32, flat: bool }
error TooSmall
error Invalid

fn pool(docs: []Doc) -> (Pool, err)
fn add(p: *Pool, d: Doc) -> (u32, err)
fn text(p: *Pool, s: str) -> (u32, err)
fn line(p: *Pool) -> (u32, err)
fn soft_line(p: *Pool) -> (u32, err)
fn nest(p: *Pool, amount: u32, child: u32) -> (u32, err)
fn concat(p: *Pool, a: u32, b: u32) -> (u32, err)
fn group(p: *Pool, child: u32) -> (u32, err)
fn fits(p: *const Pool, stack: []Frame, base: usize, top: usize, depth: usize, remaining: i64) -> (bool, err)
fn emit(out: []u8, n: usize, byte: u8) -> (usize, err)
fn layout(p: *const Pool, root: u32, width: usize, out: []u8, stack: []Frame) -> (usize, err)
```

Wadler-style layout over a caller document pool (`text`, `line`, `soft_line`, `nest`,
`concat`, `group`) rendered by `layout` with a lazy `fits` lookahead over a caller frame
stack.

### `e.fmt.css`

```neper
type Element = struct { tag: str, id: str, class_lo: u32, class_hi: u32, attr_lo: u32, attr_hi: u32, parent: u32, prev: u32 }
type Attribute = struct { name: str, value: str }
type Dom = struct { elements: []const Element, classes: []const str, attributes: []const Attribute }
type Origin = enum u8 { UserAgent, User, Author }
type Decl = struct { origin: Origin, important: bool, specificity: u32, order: u32 }
error Invalid
error TooSmall
const NONE: u32 = 4294967295u32

fn is_ident(b: u8) -> bool
fn ident_end(s: str, from: usize) -> usize
fn is_combinator(b: u8) -> bool
fn find_top(s: str, from: usize, sep: u8) -> (usize, bool, err)
fn has_class(d: *const Dom, e: Element, name: str) -> bool
fn attribute(d: *const Dom, e: Element, name: str) -> (str, bool)
fn word_in(list: str, word: str) -> bool
fn match_attribute(d: *const Dom, e: Element, body: str) -> (bool, err)
fn skip_spaces(s: str, from: usize) -> usize
fn digits(s: str, from: usize) -> (i64, usize)
fn parse_nth(arg: str) -> (i64, i64, err)
fn position(d: *const Dom, index: usize) -> i64
fn match_pseudo(d: *const Dom, index: usize, name: str, arg: str, has_arg: bool) -> (bool, err)
fn match_compound(d: *const Dom, index: usize, c: str) -> (bool, err)
fn match_complex(d: *const Dom, index: usize, sel: str) -> (bool, err)
fn matches(d: *const Dom, index: usize, selector: str) -> (bool, err)
fn select(d: *const Dom, selector: str, out: []u32) -> (usize, err)
fn specificity_one(sel: str) -> (u32, err)
fn specificity(selector: str) -> (u32, err)
fn rank(decl: Decl) -> u32
fn precedes(x: Decl, y: Decl) -> bool
fn cascade(decls: []const Decl, out_order: []u32) -> err
```

Selectors matched right to left over a caller element table (`matches`, `select`:
type, id, class, attribute operators, `:first-child`, `:nth-child`, the four
combinators and lists), `specificity` packed as three bytes and `cascade` ordering
declarations by origin, importance, specificity and source order.

### `e.fmt.uri`

```neper
type Uri = struct { scheme: str, authority: str, userinfo: str, host: str, port: str, path: str, query: str, fragment: str }
type EncodeSet = enum u8 { Path, PathSegment, Query, QueryComponent, Fragment, UserInfo }
error Invalid

fn parse(source: str) -> (Uri, err)
fn resolve(a: *mem.Arena, base: Uri, reference: Uri) -> (Uri, err)
fn normalize(a: *mem.Arena, value: Uri) -> (Uri, err)
fn format(a: *mem.Arena, value: Uri) -> (str, err)
fn percent_encode(a: *mem.Arena, source: []const u8, set: EncodeSet) -> (str, err)
fn percent_decode(a: *mem.Arena, source: str) -> ([]u8, err)
fn query_get(query: str, name: str) -> (str, bool, err)
```

Parsing follows RFC 3986 and returns borrowed slices. Percent decoding never treats
`+` as space; HTML form encoding is a separate concern.

### `e.fmt.mime`

```neper
type Parameter = struct { name: str, value: str }
type MediaType = struct { major: str, subtype: str, parameters: []const Parameter }
type Header = struct { name: str, value: str }
error Invalid
error TooLarge

fn parse_media_type(a: *mem.Arena, source: str, limit: usize) -> (MediaType, err)
fn format_media_type(a: *mem.Arena, value: MediaType) -> (str, err)
fn extension_type(extension: str) -> (str, bool)
fn parse_headers(a: *mem.Arena, source: io.Reader, byte_limit: usize, count_limit: usize) -> ([]Header, err)
fn header(headers: []const Header, name: str) -> (str, bool)
```

Header names compare by ASCII case folding. Obsolete line folding is rejected.

### `e.fmt.asn1`

```neper
type Class = enum u8 { Universal, Application, Context, Private }
type Tag = struct { class: Class, number: u32, constructed: bool }
type Value = struct { tag: Tag, content: []const u8, encoded: []const u8 }
type Reader = struct { data: []const u8, off: usize, depth: u16, max_depth: u16 }
error Invalid
error NonCanonical
error TooDeep
error TooLarge

fn reader(data: []const u8, max_depth: u16) -> Reader
fn reader_next_err(source_reader: *Reader) -> (Value, bool, err)
fn children(value: Value, max_depth: u16) -> (Reader, err)
fn decode[T: type](a: *mem.Arena, source: []const u8, max_depth: u16) -> (T, err)
fn encoded_len[T: type](value: *const T) -> (usize, err)
fn encode[T: type](dst: []u8, value: *const T) -> ([]u8, err)
```

The version-1 surface accepts and emits canonical DER only. Lengths, nesting and
integer encodings are validated before typed decoding exposes a value.

### `e.fmt.pem`

```neper
type Block = struct { label: str, headers: []const mime.Header, bytes: []const u8 }
error Invalid
error TooLarge

fn decode(a: *mem.Arena, source: str, byte_limit: usize) -> (Block, str, err)
fn encode(writer: *io.Writer, block: *const Block) -> err
```

`decode` returns the first strict PEM block and the unconsumed suffix. Base64 is
decoded through `e.bytes`; encrypted legacy PEM headers are not interpreted.

### `e.fmt.multipart`

```neper
type Part = struct { headers: []const mime.Header, body: io.Reader }
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error InvalidBoundary
error Invalid
error TooLarge

fn reader(storage: []u8, source: io.Reader, boundary: str, part_limit: u32, byte_limit: u64) -> (Reader, err)
fn reader_next_err(source_reader: *Reader) -> (Part, bool, err)
fn writer(storage: []u8, sink: io.Writer, boundary: str) -> (Writer, err)
fn start_part(sink_writer: *Writer, headers: []const mime.Header) -> (io.Writer, err)
fn finish(sink_writer: *Writer) -> err
```

Bodies stream without implicit buffering. Boundaries are caller-supplied for writing,
making output reproducible; nested multipart content uses another explicit reader.

### `e.fmt.quoted_printable`

```neper
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid

fn reader(storage: []u8, source: io.Reader) -> Reader
fn read(source_reader: *Reader, dst: []u8) -> (usize, err)
fn writer(storage: []u8, sink: io.Writer, line_limit: u8) -> (Writer, err)
fn write(sink_writer: *Writer, src: []const u8) -> (usize, err)
fn finish(sink_writer: *Writer) -> err
```

Decoding is strict RFC 2045. Encoding uses canonical uppercase hex escapes and
caller-selected line limits.

### `e.fmt.mail`

```neper
type Address = struct { name: str, address: str }
type Message = struct { headers: []const mime.Header, body: io.Reader }
type Date = struct { instant: i64, offset_minutes: i16 }
error InvalidAddress
error InvalidDate
error InvalidMessage
error TooLarge

fn parse_address(a: *mem.Arena, source: str) -> (Address, err)
fn parse_address_list(a: *mem.Arena, source: str) -> ([]const Address, err)
fn format_address(a: *mem.Arena, value: Address) -> (str, err)
fn parse_date(source: str) -> (Date, err)
fn read_message(a: *mem.Arena, source: io.Reader, header_limit: usize) -> (Message, err)
fn decode_header(a: *mem.Arena, source: str, output_limit: usize) -> (str, err)
```

The module parses Internet message headers and addresses without SMTP transport.
MIME bodies are consumed through `e.fmt.mime`, `e.fmt.multipart` and
`e.fmt.quoted_printable`; charset conversion is explicit through `e.text.encoding`.

### `e.fmt.gzip`

```neper
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid
error Checksum

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err)
fn read(r: *Reader, dst: []u8) -> (usize, err)
fn writer(storage: []u8, sink: io.Writer, level: deflate.Level) -> (Writer, err)
fn write(w: *Writer, src: []const u8) -> (usize, err)
fn finish(w: *Writer) -> err
fn storage_required(level: deflate.Level) -> usize
```

The reader validates RFC 1952 headers, trailer size and CRC32. The output limit is
checked before exposing bytes. `finish` writes the final DEFLATE blocks and trailer.

### `e.fmt.zstd`

```neper
type Reader = struct { state: *void }
type Writer = struct { state: *void }
type Level = enum u8 { Fast, Balanced, Best }
error Invalid
error Checksum
error Unsupported

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err)
fn read(r: *Reader, dst: []u8) -> (usize, err)
fn writer(storage: []u8, sink: io.Writer, level: Level) -> (Writer, err)
fn write(w: *Writer, src: []const u8) -> (usize, err)
fn finish(w: *Writer) -> err
fn reader_storage(window_limit: usize) -> (usize, err)
fn writer_storage(level: Level) -> usize
```

Version 1 supports standard frames without dictionaries. Window and decompressed
output limits are mandatory; unsupported skippable or dictionary frames return
`Unsupported`.

### `e.fmt.bzip2`

```neper
type Reader = struct { state: *void }
error Invalid
error Checksum
error TooLarge

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err)
fn read(source_reader: *Reader, dst: []u8) -> (usize, err)
fn storage_required(block_limit: usize) -> (usize, err)
```

Version 1 provides bounded bzip2 decompression. Compression is deliberately omitted
until a workload justifies its larger implementation and memory surface.

### `e.fmt.lzw`

```neper
type Order = enum u8 { LeastSignificant, MostSignificant }
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid
error TooLarge

fn reader(storage: []u8, source: io.Reader, order: Order, literal_width: u8, output_limit: u64) -> (Reader, err)
fn read(source_reader: *Reader, dst: []u8) -> (usize, err)
fn writer(storage: []u8, sink: io.Writer, order: Order, literal_width: u8) -> (Writer, err)
fn write(sink_writer: *Writer, src: []const u8) -> (usize, err)
fn finish(sink_writer: *Writer) -> err
fn storage_required(literal_width: u8) -> (usize, err)
```

Bit order and literal width are explicit so GIF- and TIFF-style streams cannot be
silently confused.

### `e.fmt.zlib`

```neper
type Reader = struct { state: *void }
type Writer = struct { state: *void }
error Invalid
error Checksum

fn reader(storage: []u8, source: io.Reader, output_limit: u64) -> (Reader, err)
fn read(source_reader: *Reader, dst: []u8) -> (usize, err)
fn writer(storage: []u8, sink: io.Writer, level: deflate.Level) -> (Writer, err)
fn write(sink_writer: *Writer, src: []const u8) -> (usize, err)
fn finish(sink_writer: *Writer) -> err
fn storage_required(level: deflate.Level) -> usize
```

The reader and writer implement RFC 1950 framing around `e.algo.deflate` and validate
the Adler-32 trailer before successful completion.

### `e.fmt.zip`

```neper
type Archive = struct { state: *void }
type Entry = struct { name: str, compressed_size: u64, size: u64, method: u16, crc32: u32, directory: bool }
type Limits = struct { entries: usize, name_bytes: usize, entry_bytes: u64, total_bytes: u64 }
error Invalid
error Unsupported
error Checksum
error TooLarge

fn open(a: *mem.Arena, source: io.Reader, seeker: io.Seeker, limits: Limits) -> (Archive, err)
fn entries(archive: *const Archive) -> []const Entry
fn entry_reader(storage: []u8, archive: *Archive, index: usize) -> (io.Reader, err)
fn extract(a: *mem.Arena, archive: *Archive, index: usize) -> ([]u8, err)
```

Version 1 reads stored and DEFLATE entries, ZIP64 sizes and UTF-8 names. It rejects
encrypted entries, absolute paths and names containing a `..` segment. CRC and all
per-entry/aggregate limits are checked before successful extraction.

### `e.fmt.tar`

```neper
type Reader = struct { state: *void }
type Entry = struct { name: str, size: u64, kind: u8, mode: u32, modified: i64, link: str }
error Invalid
error Unsupported
error TooLarge

fn reader(a: *mem.Arena, source: io.Reader, entry_limit: usize, byte_limit: u64) -> (Reader, err)
fn next(r: *Reader) -> (Entry, bool, err)
fn content(r: *Reader) -> io.Reader
fn skip(r: *Reader) -> err
```

The reader supports POSIX ustar and PAX path/size records. Each entry's content must
be consumed or skipped before `next`. Absolute paths and `..` segments are rejected.

### `e.fmt.yaml`

```neper
type Pair = struct { key: Value, value: Value }
type Value = union enum u8 { Null, Bool: bool, Integer: i64, Float: f64, String: str, Sequence: []const Value, Mapping: []const Pair }
type Options = struct { max_depth: u16, allow_duplicate_keys: bool }
error Invalid
error TooDeep
error DuplicateKey
error Unsupported

fn parse(a: *mem.Arena, source: str, options: Options) -> (Value, err)
fn write(writer: *io.Writer, value: *const Value, indent: u8) -> err
fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err)
fn encode[T: type](writer: *io.Writer, value: *const T) -> err
```

The subset is block mappings/sequences, flow collections, plain/single/double-quoted
scalars, literal/folded blocks and `null`/boolean/integer/float core tags. Anchors,
aliases, merge keys, directives, custom tags and multiple documents are `Unsupported`.

### `e.fmt.xml`

```neper
type Attribute = struct { name: str, value: str }
type Event = union enum u8 { Start: StartElement, End: str, Text: str, Comment: str, Processing: Processing }
type StartElement = struct { name: str, attributes: []const Attribute, empty: bool }
type Processing = struct { target: str, data: str }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer, depth: u16 }
type Options = struct { max_depth: u16, preserve_comments: bool }
error Invalid
error TooDeep
error Unsupported

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err)
fn reader_next_err(r: *Reader) -> (Event, bool, err)
fn writer(sink: io.Writer) -> Writer
fn start(w: *Writer, name: str, attributes: []const Attribute) -> err
fn text(w: *Writer, value: str) -> err
fn comment(w: *Writer, value: str) -> err
fn end(w: *Writer, name: str) -> err
```

XML 1.0 names, namespaces and entity escaping are supported. External entities and
DTDs are always `Unsupported`; the module never performs hidden I/O.

### `e.fmt.html`

```neper
type NodeId = u32
const NONE: NodeId = 4294967295
type NodeKind = enum u8 { Document, Doctype, Element, Text, Comment }
type Namespace = enum u8 { Html, Svg, MathMl }
type Attribute = struct { namespace: Namespace, name: str, value: str }
type Node = struct { kind: NodeKind, namespace: Namespace, name: str, value: str, attributes: []const Attribute, parent: NodeId, first_child: NodeId, last_child: NodeId, previous_sibling: NodeId, next_sibling: NodeId }
type Document = struct { nodes: []const Node, root: NodeId }
type Children = struct { document: *const Document, next: NodeId }
type Options = struct { max_bytes: usize, max_nodes: usize, max_attributes: usize, max_depth: u16, preserve_comments: bool }
error InvalidEncoding
error TooDeep
error TooLarge

fn parse(a: *mem.Arena, source: str, options: Options) -> (Document, err)
fn parse_reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Document, err)
fn node(document: *const Document, id: NodeId) -> *const Node
fn children(document: *const Document, parent: NodeId) -> Children
fn children_next(it: *Children) -> (NodeId, bool)
fn attribute(element: *const Node, name: str) -> (str, bool)
fn text_content(a: *mem.Arena, document: *const Document, root: NodeId) -> (str, err)
fn write(writer: *io.Writer, document: *const Document) -> err
```

The input is UTF-8 with an optional UTF-8 BOM; invalid UTF-8 returns
`InvalidEncoding`. `parse_reader` reads no more than `max_bytes`, and `parse` rejects
an input longer than that limit before allocating nodes. Ordinary malformed HTML is
recovered rather than returned as an error. Tokenization, character-reference
decoding, insertion modes, implied elements, foster parenting, raw-text elements and
HTML/SVG/MathML namespace transitions follow the WHATWG HTML parsing algorithm as
frozen by the toolchain version. The conformance snapshot and html5lib
tree-construction fixtures used by a release are recorded in its build manifest.

`Document.nodes` is arena-owned and read-only. `NodeId` values are indices into that
slice; `NONE` denotes a missing relation. The document node is `root`, has
`namespace == .Html`, and has no name or value. Element names are ASCII-lowercase in
the HTML namespace and preserve adjusted foreign names elsewhere. Text, comments,
names and decoded attribute values are arena-owned. Attributes and children preserve
source/tree-construction order. `attribute` uses ASCII-insensitive comparison for
HTML elements and exact comparison for foreign elements. `text_content` concatenates
descendant text nodes in tree order. `write` implements the matching HTML fragment
serialization rules and performs no pretty-print rewrite.

The module does not open files, fetch subresources, execute scripts, apply CSS,
construct a browser DOM or expose mutable tree operations. A caller loads a file
through `e.fs` or supplies an `e.io.Reader`. Legacy encoding sniffing and conversion
must occur before parsing and are outside the version-1 surface.

### `e.fmt.html.template`

```neper
type Template = struct { inner: template.Template }
type Options = struct { max_bytes: usize, max_nodes: usize, max_depth: u16 }
error InvalidTemplate
error UnsafeContext
error MissingValue
error TooLarge

fn parse(a: *mem.Arena, source: str, options: Options) -> (Template, err)
fn execute(value: *const Template, writer: *io.Writer, bindings: []const template.Binding) -> err
fn validate[T: type](value: *const Template) -> err
fn execute_typed[T: type](value: *const Template, writer: *io.Writer, data: *const T) -> err
```

HTML templates track text, attribute, URI, CSS and script contexts and apply the
matching escaping rules. Ambiguous or unsafe context transitions fail at parse time;
trusted raw insertion is intentionally absent from version 1.

### `e.fmt.png`

```neper
type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64, verify_crc: bool }
type EncodeOptions = struct { compression: deflate.Level, interlace: bool }
error Invalid
error Unsupported
error Checksum
error TooLarge

fn inspect(source: io.Reader) -> (image.Info, err)
fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err)
fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err
```

PNG decoding supports the standard grayscale, RGB, indexed and alpha color types and
rejects dimensions before pixel allocation. Encoding is deterministic for identical
pixels and options.

### `e.fmt.jpeg`

```neper
type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
type EncodeOptions = struct { quality: u8, progressive: bool }
error Invalid
error Unsupported
error TooLarge

fn inspect(source: io.Reader) -> (image.Info, err)
fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err)
fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err
```

Version 1 supports baseline and progressive Huffman JPEG with bounded dimensions.
Arithmetic coding and embedded color-profile conversion return `Unsupported`.

### `e.fmt.webp`

```neper
type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64, first_frame_only: bool }
type EncodeOptions = struct { quality: f32, lossless: bool }
error Invalid
error Unsupported
error TooLarge

fn inspect(source: io.Reader) -> (image.Info, err)
fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err)
fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err
```

The module supports lossy and lossless WebP. Animation is inspectable; decoding more
than the first frame remains `Unsupported` until a frame-sequence image type exists.

### `e.fmt.bson`

```neper
type Element = struct { key: str, value: Value }
type Binary = struct { subtype: u8, data: []const u8 }
type Value = union enum u8 { Double: f64, String: str, Document: []const Element, Array: []const Value, Binary: Binary, Bool: bool, Null, I32: i32, I64: i64 }
error Invalid
error TooDeep
error TooLarge

fn parse(a: *mem.Arena, source: []const u8, max_depth: u16) -> (Value, err)
fn size(value: *const Value) -> (usize, err)
fn write(writer: *io.Writer, value: *const Value) -> err
fn decode[T: type](a: *mem.Arena, source: []const u8, max_depth: u16) -> (T, err)
fn encode[T: type](writer: *io.Writer, value: *const T) -> err
```

Unsupported BSON element tags are `Invalid`; JavaScript, regex and deprecated tags
are intentionally absent from the value model.

### `e.fmt.msgpack`

```neper
type Pair = struct { key: Value, value: Value }
type Ext = struct { kind: i8, data: []const u8 }
type Value = union enum u8 { Nil, Bool: bool, I64: i64, U64: u64, F64: f64, String: str, Binary: []const u8, Array: []const Value, Map: []const Pair, Ext: Ext }
type Reader = struct { state: *void }
error Invalid
error TooDeep
error TooLarge

fn reader(a: *mem.Arena, source: io.Reader, max_depth: u16) -> (Reader, err)
fn read_value(a: *mem.Arena, r: *Reader) -> (Value, err)
fn write(writer: *io.Writer, value: *const Value) -> err
fn decode[T: type](a: *mem.Arena, source: io.Reader, max_depth: u16) -> (T, err)
fn encode[T: type](writer: *io.Writer, value: *const T) -> err
```

### `e.fmt.protobuf`

```neper
type WireType = enum u8 { Varint, Fixed64, Bytes, Fixed32 }
type Key = struct { number: u32, wire: WireType }
type Reader = struct { input: bytes.Reader }
error Invalid
error TooLarge

fn reader(source: []const u8) -> Reader
fn reader_next_err(r: *Reader) -> (Key, bool, err)
fn read_u64(r: *Reader) -> (u64, err)
fn read_i64(r: *Reader) -> (i64, err)
fn read_sint64(r: *Reader) -> (i64, err)
fn read_fixed32(r: *Reader) -> (u32, err)
fn read_fixed64(r: *Reader) -> (u64, err)
fn read_bytes(r: *Reader) -> ([]const u8, err)
fn skip(r: *Reader, wire: WireType) -> err
fn size_key(number: u32, wire: WireType) -> (usize, err)
fn size_varint(value: u64) -> usize
fn size_bytes(n: usize) -> (usize, err)
fn write_key(w: *io.Writer, number: u32, wire: WireType) -> err
fn write_u64(w: *io.Writer, value: u64) -> err
fn write_i64(w: *io.Writer, value: i64) -> err
fn write_sint64(w: *io.Writer, value: i64) -> err
fn write_fixed32(w: *io.Writer, value: u32) -> err
fn write_fixed64(w: *io.Writer, value: u64) -> err
fn write_bytes(w: *io.Writer, value: []const u8) -> err
```

These are protobuf wire-format primitives for generated message code.
`reader_next_err` reads
only a field key; the generated decoder calls the matching `read_*` or `skip` and
enforces message-specific cardinality, required fields, recursion depth, packed
encoding and oneof semantics. Field numbers are 1..536870911 excluding
19000..19999. Signed non-zigzag values use protobuf's ten-byte two's-complement
varint; `sint64` is zigzag. Length-delimited results borrow `source`. The module does
not invent field numbers from reflection and contains no descriptor runtime.

---

## 10. External packages

The `x.*` rows in `modules.md` are package reservations, not implicit toolchain
modules. Each package publishes `docs/packages/<owner>/<package>.md` before
implementation. That specification pins the upstream ABI/data version and lists
every public declaration using the same format as this catalogue. `x.neper.*` is not
a legal package namespace: Neper-owned facilities live in `e.*`, `e.algo.*`, `e.text.*`,
`e.crypto.*`, `e.fmt.*`, `e.gfx.*` or `e.ui.*`. A remaining vendor reservation without a package specification
promises zero functions and structures.

### `e.time.sync`

```neper
error TooSmall
error Invalid

fn marzullo(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, i64, usize, err)
fn marzullo_estimate(lows: []const i64, highs: []const i64, n: usize, scratch: []i64) -> (i64, err)
fn berkeley(offsets: []const i64, n: usize, tolerance: i64, out: []i64) -> err
fn cristian(t0_send: i64, t_server: i64, t1_receive: i64, min_one_way: i64) -> (i64, i64)
```

`marzullo` (the interval covered by the most sources) and `marzullo_estimate`,
`berkeley` (median-filtered average adjustments) and `cristian` (round-trip halving
with an error bound).

### `e.time.cron`

```neper
type Schedule = struct { seconds: u64, minutes: u64, hours: u32, doms: u32, months: u16, dows: u8, dom_restricted: bool, dow_restricted: bool, offset_minutes: i32 }
error Invalid

fn parse(a: *mem.Arena, expr: str, offset_minutes: i32) -> (Schedule, err)
fn matches(s: Schedule, t: time.Timestamp) -> bool
fn next(s: Schedule, after: time.Timestamp) -> (time.Timestamp, err)
```

The delivered parser accepts six numeric fields with lists, inclusive ranges and steps;
Sunday is 0 or 7. Day-of-month and day-of-week use Vixie cron's OR rule when both are
restricted. `next` is strictly after its input and searches no more than one complete
400-year Gregorian cycle or the representable timestamp range.

### `e.ratelimit`

```neper
type TokenBucket = struct { capacity: u64, refill: u64, interval: u64, level: u64, last: u64 }
type LeakyBucket = struct { capacity: u64, leak: u64, interval: u64, water: u64, last: u64 }
type FixedWindow = struct { limit: u64, width: u64, window: u64, count: u64 }
type SlidingLog = struct { limit: u64, width: u64, stamps: []u64, head: usize, len: usize }
type SlidingWindow = struct { limit: u64, width: u64, window: u64, count: u64, previous: u64 }
error Invalid

fn token_bucket(capacity: u64, refill: u64, interval: u64, now: u64) -> (TokenBucket, err)
fn token_bucket_refill(b: *TokenBucket, now: u64)
fn token_bucket_allow(b: *TokenBucket, now: u64, cost: u64) -> bool
fn token_bucket_tokens(b: *TokenBucket, now: u64) -> u64
fn leaky_bucket(capacity: u64, leak: u64, interval: u64, now: u64) -> (LeakyBucket, err)
fn leaky_bucket_drain(b: *LeakyBucket, now: u64)
fn leaky_bucket_allow(b: *LeakyBucket, now: u64, cost: u64) -> bool
fn leaky_bucket_level(b: *LeakyBucket, now: u64) -> u64
fn fixed_window(limit: u64, width: u64) -> (FixedWindow, err)
fn fixed_window_allow(w: *FixedWindow, now: u64, cost: u64) -> bool
fn sliding_log(limit: u64, width: u64, stamps: []u64) -> (SlidingLog, err)
fn sliding_log_evict(l: *SlidingLog, now: u64)
fn sliding_log_allow(l: *SlidingLog, now: u64) -> bool
fn sliding_log_count(l: *SlidingLog, now: u64) -> u64
fn sliding_window(limit: u64, width: u64) -> (SlidingWindow, err)
fn sliding_window_roll(w: *SlidingWindow, now: u64)
fn sliding_window_count(w: *SlidingWindow, now: u64) -> u64
fn sliding_window_allow(w: *SlidingWindow, now: u64, cost: u64) -> bool
```

Limiters over the caller's clock in exact integer arithmetic: `token_bucket`,
`leaky_bucket`, `fixed_window`, `sliding_log` (a caller ring of timestamps) and
`sliding_window`, each with `_allow` and a level or count query.

### `e.resilience`

```neper
type BreakerState = enum u8 { Closed, Open, HalfOpen }
type Breaker = struct { state: BreakerState, failure_threshold: u32, open_timeout: u64, half_open_probes: u32, failures: u32, probes: u32, opened_at: u64 }
type Heartbeat = struct { ids: []u64, last_seen: []u64, count: usize }
type Shedder = struct { load: f64, alpha: f64, thresholds: []const f64 }
type Bulkhead = struct { limits: []const u32, used: []u32 }
type Health = enum u8 { Live, Degraded, NotReady, Dead }
error TooSmall
error Invalid

fn circuit_breaker(failure_threshold: u32, open_timeout: u64, half_open_probes: u32) -> Breaker
fn breaker_allow(b: *Breaker, now: u64) -> bool
fn breaker_success(b: *Breaker)
fn breaker_failure(b: *Breaker, now: u64)
fn backoff_exponential(attempt: u32, base: u64, cap: u64) -> u64
fn backoff(attempt: u32, base: u64, cap: u64, rng: *rand.Pcg64) -> u64
fn backoff_decorrelated(previous: u64, base: u64, cap: u64, rng: *rand.Pcg64) -> u64
fn heartbeat(ids: []u64, last_seen: []u64) -> Heartbeat
fn heartbeat_find(h: *const Heartbeat, id: u64) -> usize
fn heartbeat_observe(h: *Heartbeat, id: u64, now: u64) -> err
fn heartbeat_alive(h: *const Heartbeat, id: u64, now: u64, timeout: u64) -> bool
fn heartbeat_sweep(h: *Heartbeat, now: u64, timeout: u64, out_dead: []u64) -> (usize, err)
fn load_shed(alpha: f64, thresholds: []const f64) -> Shedder
fn load_shed_observe(s: *Shedder, sample: f64)
fn load_shed_admit(s: *const Shedder, priority: usize) -> bool
fn bulkhead(limits: []const u32, used: []u32) -> Bulkhead
fn bulkhead_acquire(b: *Bulkhead, partition: usize) -> bool
fn bulkhead_release(b: *Bulkhead, partition: usize)
fn bulkhead_available(b: *const Bulkhead, partition: usize) -> u32
fn health(up: []const bool, critical: []const bool) -> Health
fn health_live(h: Health) -> bool
fn health_ready(h: Health) -> bool
fn fnv_feed(h: u32, s: str) -> u32
fn rollout_bucket(user_id: str, salt: str) -> u32
fn rollout_enabled(user_id: str, salt: str, basis_points: u32) -> bool
```

`circuit_breaker` (closed, open, half-open with probes), `backoff` (exponential, full
jitter, decorrelated), `heartbeat` tables with `heartbeat_sweep`, `load_shed` (EWMA load
against per-priority thresholds), `bulkhead` permits per partition, `health` aggregation
(live, degraded, not ready, dead) and `rollout_bucket` by FNV-1a.

### `e.valid`

```neper
error Invalid

fn is_digit(c: u8) -> bool
fn is_separator(c: u8) -> bool
fn digits(s: str, out: []u8) -> usize
fn luhn(s: str) -> bool
fn luhn_sum(d: []const u8, shifted: bool) -> u32
fn luhn_check_digit(s: str) -> (u8, err)
fn weighted_mod10(s: str, count: usize, first: u32) -> bool
fn ean13(s: str) -> bool
fn ean8(s: str) -> bool
fn upc_a(s: str) -> bool
fn isbn13(s: str) -> bool
fn isbn10(s: str) -> bool
fn iban_length(a: u8, b: u8) -> usize
fn mod97(r: u32, s: str) -> (u32, bool)
fn iban(s: str) -> bool
```

Identifier checks: `luhn` and `luhn_check_digit`, `isbn13`, `isbn10`, `ean13`, `ean8`,
`upc_a` (one weighted mod-10 helper) and `iban` (mod 97 digit by digit with a country
length table).

### `e.control`

```neper
type Pid = struct { kp: f64, ki: f64, kd: f64, integral: f64, previous_error: f64, out_min: f64, out_max: f64, kb: f64 }
type Tuning = enum u8 { P, PI, PID }
type Feedforward = struct { gain: f64, feedback: Pid }
error TooSmall
error Singular

fn pid(kp: f64, ki: f64, kd: f64) -> Pid
fn pid_step(p: *Pid, setpoint: f64, measured: f64, dt: f64) -> f64
fn pid_anti_windup(kp: f64, ki: f64, kd: f64, out_min: f64, out_max: f64, kb: f64) -> Pid
fn clamp(x: f64, lo: f64, hi: f64) -> f64
fn pid_anti_windup_step(p: *Pid, setpoint: f64, measured: f64, dt: f64) -> f64
fn pid_reset(p: *Pid)
fn pid_tune_ziegler_nichols(ku: f64, tu: f64, kind: Tuning) -> (f64, f64, f64)
fn bang_bang(measured: f64, setpoint: f64, hysteresis: f64, on: bool) -> bool
fn feedforward(f: *Feedforward, setpoint: f64, measured: f64, dt: f64) -> f64
fn sliding_mode(error_value: f64, error_rate: f64, c: f64, k: f64, boundary: f64) -> f64
fn identity(out: []f64, n: usize)
fn lqr(a: []const f64, b: []const f64, q: []const f64, r: []const f64, n: usize, m: usize, k: []f64, scratch: []f64, iterations: usize, tolerance: f64) -> (usize, err)
fn characteristic(re: []const f64, im: []const f64, out: []f64, scratch: []f64) -> err
fn pole_placement(a: []const f64, b: []const f64, n: usize, poles_re: []const f64, poles_im: []const f64, k: []f64, scratch: []f64) -> err
fn observer_gain(a: []const f64, c: []const f64, n: usize, poles_re: []const f64, poles_im: []const f64, l: []f64, scratch: []f64) -> err
fn observer_step(x_hat: []f64, a: []const f64, b: []const f64, c: []const f64, l: []const f64, n: usize, m: usize, p: usize, u: []const f64, y: []const f64, scratch: []f64) -> err
```

`pid` and `pid_step`, `pid_anti_windup` (clamped output with back-calculation),
`pid_tune_ziegler_nichols`, `bang_bang`, `feedforward`, `sliding_mode`, `lqr` (discrete
Riccati iteration), `pole_placement` (Ackermann, single input), `observer_gain` on the
dual and `observer_step` (Luenberger); matrices row-major in caller storage.

### `e.parse`

```neper
type Token = struct { kind: u8, start: usize, len: usize }
type Op = struct { text: str, kind: u8, prec: u8, right: bool }
type Ast = struct { kind: []u8, a: []u32, b: []u32, tok: []u32, used: usize }
type Grammar = struct { lhs: []const u32, rhs: []const u32, rule_start: []const usize, terminals: u32 }
type Item = struct { rule: u32, dot: u32, origin: u32 }
type Peg = struct { op: []const u8, a: []const u32, b: []const u32, rules: []const u32 }
type Parser = struct { tokens: []const Token, text: str, ops: []const Op, pos: usize }
error TooSmall
error Invalid
const IDENT: u8 = 1u8
const INT: u8 = 2u8
const STRING: u8 = 3u8
const OP: u8 = 4u8
const INDENT: u8 = 5u8
const DEDENT: u8 = 6u8
const PREFIX: u8 = 0u8
const INFIX: u8 = 1u8
const POSTFIX: u8 = 2u8
const LEAF: u8 = 1u8
const NODE_PREFIX: u8 = 2u8
const NODE_INFIX: u8 = 3u8
const NODE_POSTFIX: u8 = 4u8
const PEG_CHAR: u8 = 1u8
const PEG_RANGE: u8 = 2u8
const PEG_ANY: u8 = 3u8
const PEG_SEQ: u8 = 4u8
const PEG_CHOICE: u8 = 5u8
const PEG_STAR: u8 = 6u8
const PEG_PLUS: u8 = 7u8
const PEG_OPT: u8 = 8u8
const PEG_NOT: u8 = 9u8
const PEG_AND: u8 = 10u8
const PEG_RULE: u8 = 11u8
const PEG_EMPTY: u8 = 12u8

fn is_ident_start(c: u8) -> bool
fn is_digit(c: u8) -> bool
fn is_punct(c: u8) -> bool
fn starts_at(text: str, at_pos: usize, s: str) -> bool
fn push_token(out: []Token, n: usize, kind: u8, start: usize, len: usize) -> err
fn lex(text: str, operators: []const str, out: []Token) -> (usize, err)
fn lex_indent(text: str, stack: []usize, out: []Token) -> (usize, err)
fn is_char(text: str, t: Token, c: u8) -> bool
fn find_op(ops: []const Op, text: str, t: Token, kind: u8) -> (usize, bool)
fn shunting_yard(tokens: []const Token, text: str, ops: []const Op, out: []Token, stack: []Token) -> (usize, err)
fn ast(kind: []u8, a: []u32, b: []u32, tok: []u32) -> Ast
fn ast_node(t: *Ast, kind: u8, a: u32, b: u32, tok: u32) -> (u32, err)
fn ast_child(t: *const Ast, node: u32, which: usize) -> u32
fn pratt(tokens: []const Token, text: str, ops: []const Op, t: *Ast) -> (u32, err)
fn pratt_expr(p: *Parser, t: *Ast, min_bp: u8) -> (u32, err)
fn recursive_descent(tokens: []const Token, text: str, t: *Ast) -> (u32, err)
fn peek_char(p: *const Parser, c: u8) -> bool
fn rd_binary(p: *Parser, t: *Ast, lhs: u32, rhs: u32) -> (u32, err)
fn rd_expr(p: *Parser, t: *Ast) -> (u32, err)
fn rd_term(p: *Parser, t: *Ast) -> (u32, err)
fn rd_unary(p: *Parser, t: *Ast) -> (u32, err)
fn rd_power(p: *Parser, t: *Ast) -> (u32, err)
fn rd_atom(p: *Parser, t: *Ast) -> (u32, err)
fn evaluate(t: *const Ast, node: u32, tokens: []const Token, text: str) -> (f64, err)
fn grammar(lhs: []const u32, rhs: []const u32, rule_start: []const usize, terminals: u32) -> Grammar
fn rule_count(g: *const Grammar) -> usize
fn rule_len(g: *const Grammar, rule: usize) -> usize
fn rule_symbol(g: *const Grammar, rule: usize, at_pos: usize) -> u32
fn cyk(g: *const Grammar, start: u32, sentence: []const u32, chart: []u64) -> (bool, err)
fn nullable_set(g: *const Grammar) -> u64
fn earley_add(items: []Item, from: usize, used: usize, it: Item) -> (usize, err)
fn earley_run(g: *const Grammar, start: u32, sentence: []const u32, items: []Item, sets: []usize) -> (usize, err)
fn earley(g: *const Grammar, start: u32, sentence: []const u32, items: []Item, sets: []usize) -> (bool, usize, err)
fn next_terminals(g: *const Grammar, start: u32, prefix: []const u32, out: []u32, items: []Item, sets: []usize) -> (usize, err)
fn peg(p: *const Peg, rule: usize, text: str, memo: []i64) -> (usize, bool, err)
fn peg_rule(p: *const Peg, rule: usize, text: str, pos: usize, memo: []i64) -> (usize, bool)
fn peg_match(p: *const Peg, node: u32, text: str, pos: usize, memo: []i64) -> (usize, bool)
```

`lex` (table scanner with a caller operator list), `lex_indent` (off-side rule),
`shunting_yard`, an AST pool (`ast`, `ast_node`, `ast_child`), `pratt` and
`recursive_descent` producing the same shapes, `evaluate`; a shared `grammar`
representation for `cyk` (CNF, bitset chart), `earley` (any grammar, epsilon and
ambiguity), `next_terminals` (constrained decoding by Earley prediction) and `peg`
(packrat over a node table with a caller memo).

### `e.trace`

```neper
type TraceContext = struct { trace_id: [16]u8, span_id: [8]u8, flags: u8 }
error Invalid
error TooSmall
const HEADER_LEN: usize = 55usize
const MAX_MEMBERS: usize = 32usize
const FLAG_SAMPLED: u8 = 1u8

fn nibble(c: u8) -> (u8, bool)
fn unhex(s: str, at: usize, out: []u8) -> bool
fn hex(bytes: []const u8, out: []u8)
fn parse_traceparent(s: str) -> (TraceContext, err)
fn format_traceparent(c: *const TraceContext, out: []u8) -> (usize, err)
fn all_zero(bytes: []const u8) -> bool
fn child(parent: *const TraceContext, new_span_id: []const u8) -> (TraceContext, err)
fn propagate(parent: *const TraceContext, new_span_id: []const u8, out: []u8) -> (usize, err)
fn sampled(c: *const TraceContext) -> bool
fn span_id_from(r: *rand.Pcg64) -> [8]u8
fn trace_id_from(r: *rand.Pcg64) -> [16]u8
fn fill(r: *rand.Pcg64, out: []u8)
fn member(state: str, at: usize) -> (str, str, usize, bool)
fn tracestate_get(state: str, key: str) -> (str, bool)
fn tracestate_set(state: str, key: str, value: str, out: []u8) -> (usize, err)
fn append(out: []u8, n: usize, s: str) -> (usize, err)
```

W3C Trace Context: `parse_traceparent`, `format_traceparent`, `child`, `propagate`,
`sampled`, `span_id_from`/`trace_id_from` over a generator, and `tracestate_get`/
`tracestate_set` (move to front, 32 members).

### `e.dist.clock`

```neper
type Lamport = struct { time: u64 }
type Hlc = struct { physical: u64, logical: u64 }
type Order = enum u8 { Before, After, Equal, Concurrent }

fn lamport() -> Lamport
fn lamport_tick(c: *Lamport) -> u64
fn lamport_send(c: *Lamport) -> u64
fn lamport_receive(c: *Lamport, stamp: u64) -> u64
fn vector_tick(v: []u64, node: usize) -> u64
fn vector_merge(dst: []u64, src: []const u64)
fn vector_receive(v: []u64, src: []const u64, node: usize) -> u64
fn vector_cmp(a: []const u64, b: []const u64) -> Order
fn hlc() -> Hlc
fn hlc_now(c: *Hlc, physical: u64) -> Hlc
fn hlc_receive(c: *Hlc, physical: u64, remote: Hlc) -> Hlc
fn hlc_cmp(a: Hlc, b: Hlc) -> i32
```

Lamport clocks (`lamport_tick/send/receive`), vector clocks over caller arrays
(`vector_tick/merge/receive/cmp` answering before, after, equal or concurrent) and
hybrid logical clocks (`hlc_now`, `hlc_receive`, `hlc_cmp`).

### `e.dist.election`

```neper
type Kind = enum u8 { Election, Ok, Coordinator }
type Message = struct { kind: Kind, from: u32, to: u32 }
type Sent = struct { out: []Message, count: usize }
error TooSmall
error Invalid

fn push(s: *Sent, kind: Kind, from: usize, to: usize)
fn highest_alive(alive: []const bool) -> usize
fn bully(alive: []const bool, initiator: usize, out: []Message) -> (usize, usize, err)
fn ring(alive: []const bool, ring_order: []const usize, initiator: usize, out: []Message) -> (usize, usize, err)
```

Simulated leader election over an alive table with the messages recorded: `bully`
(election, ok and coordinator rounds) and `ring` (Chang-Roberts around a caller ring order).

### `e.dist.gossip`

```neper
type Gossip = struct { state: []u8, fanout: usize, informed: usize }
type Status = enum u8 { Alive, Suspect, Dead }
type Member = struct { id: u32, incarnation: u32, status: Status, heartbeat: u64 }
type Membership = struct { members: []Member, count: usize }
error TooSmall

fn gossip(state: []u8, fanout: usize, origin: usize) -> Gossip
fn informed(g: *const Gossip, node: usize) -> bool
fn gossip_round(g: *Gossip, r: *rand.Pcg64) -> usize
fn gossip_rounds_until_all(g: *Gossip, r: *rand.Pcg64, limit: usize) -> usize
fn membership(members: []Member) -> Membership
fn membership_find(t: *const Membership, id: u32) -> (usize, bool)
fn rank(s: Status) -> u32
fn supersedes(incoming: Member, held: Member) -> bool
fn membership_apply(t: *Membership, incoming: Member) -> (bool, err)
fn membership_merge(t: *Membership, incoming: []const Member) -> (usize, err)
fn set_status(t: *Membership, id: u32, from: Status, to: Status, now: u64) -> bool
fn membership_suspect(t: *Membership, id: u32, now: u64) -> bool
fn membership_confirm(t: *Membership, id: u32, now: u64) -> bool
fn membership_refute(t: *Membership, id: u32, now: u64) -> u32
fn membership_sweep(t: *Membership, now: u64, timeout: u64) -> usize
```

Rumour spread by push/pull rounds over a generator (`gossip_round`,
`gossip_rounds_until_all`) and a SWIM-style membership table (`membership_merge` with
incarnation precedence, `membership_suspect/confirm/refute/sweep`).

### `e.dist.failure_detector`

```neper
type Detector = struct { intervals: []u64, count: usize, head: usize, last: u64, seen: bool, min_std_dev: f64 }

fn detector(intervals: []u64, min_std_dev: f64) -> Detector
fn heartbeat(d: *Detector, now: u64)
fn stats(d: *const Detector) -> (f64, f64)
fn phi(d: *const Detector, now: u64) -> f64
fn suspect(d: *const Detector, now: u64, threshold: f64) -> bool
```

The phi accrual detector over a caller ring of inter-arrival times: `heartbeat`,
`stats`, `phi` (the exact normal tail through erfc) and `suspect` against a threshold.

### `e.parse.ll`

```neper
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn bit(t: u32) -> u64
fn max_symbol(g: *const base.Grammar) -> usize
fn symbol_count(g: *const base.Grammar) -> usize
fn nullable(g: *const base.Grammar, out: []bool) -> err
fn first_of(g: *const base.Grammar, nullable_set: []const bool, first_sets: []const u64, rule: usize, from: usize) -> (u64, bool)
fn first(g: *const base.Grammar, nullable_set: []const bool, first_sets: []u64) -> err
fn follow(g: *const base.Grammar, start: u32, nullable_set: []const bool, first_sets: []const u64, follow_sets: []u64) -> err
fn table(g: *const base.Grammar, start: u32, nullable_set: []bool, first_sets: []u64, follow_sets: []u64, out: []u32) -> (usize, err)
fn parse(g: *const base.Grammar, start: u32, tbl: []const u32, sentence: []const u32, stack: []u32, out_rules: []u32) -> (usize, err)
```

Over `e.parse` grammars: `nullable`, `first`, `first_of`, `follow` as bitsets,
`table` (the LL(1) table with a conflict count) and `parse` (leftmost derivation as
rule indices).

### `e.parse.lr`

```neper
type Item = struct { rule: u32, dot: u32, la: u32 }
type Collection = struct { items: []Item, set_start: []usize, trans: []u32, nullable: []bool, first: []u64, follow: []u64, states: usize, symbols: usize, used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32
const ERROR: u32 = 0u32
const SHIFT: u32 = 1u32
const REDUCE: u32 = 2u32
const ACCEPT: u32 = 3u32

fn collection(pool: []Item, set_start: []usize, trans: []u32, nullable: []bool, first: []u64, follow: []u64) -> Collection
fn tag(action: u32) -> u32
fn value(action: u32) -> u32
fn encode(kind: u32, v: u32) -> u32
fn body_len(g: *const base.Grammar, rule: usize) -> usize
fn body_symbol(g: *const base.Grammar, start: u32, rule: usize, k: usize) -> u32
fn add_item(c: *Collection, from: usize, it: Item) -> err
fn closure(g: *const base.Grammar, start: u32, c: *Collection, from: usize, lr1: bool) -> err
fn same_set(c: *const Collection, s: usize, from: usize) -> bool
fn build(g: *const base.Grammar, start: u32, c: *Collection, lr1: bool) -> err
fn items(g: *const base.Grammar, start: u32, c: *Collection) -> err
fn items1(g: *const base.Grammar, start: u32, c: *Collection) -> err
fn set_action(action: []u32, cell: usize, kind: u32, v: u32, conflicts: usize) -> usize
fn fill(g: *const base.Grammar, start: u32, c: *const Collection, merged: []const u32, states: usize, slr: bool, action: []u32, gotos: []u32) -> (usize, err)
fn identity(merged: []u32, states: usize) -> err
fn slr_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err)
fn canonical_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err)
fn same_core(c: *const Collection, s: usize, t: usize) -> bool
fn lalr_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err)
fn parse(g: *const base.Grammar, action: []const u32, gotos: []const u32, sentence: []const u32, stack: []u32, out_rules: []u32) -> (usize, err)
```

LR(0) and LR(1) canonical collections over caller item pools (`items`, `items1`),
`slr_table`, `canonical_table` and `lalr_table` (LR(1) states merged on equal cores)
with shift-preferring conflict counts, and `parse` answering the reduce sequence.

### `e.dist.consensus`

```neper
type Kind = enum u8 { None, RequestVote, VoteResponse, AppendEntries, AppendResponse, InstallSnapshot, SnapshotResponse, Prepare, Promise, Accept, Accepted, VrPrepare, VrPrepareOk, VrCommit, StartViewChange, DoViewChange, StartView }
type Entry = struct { term: u64, value: i64, cfg_old: u64, cfg_new: u64 }
type Message = struct { from: u32, to: u32, kind: Kind, term: u64, index: u64, term2: u64, commit: u64, value: i64, flag: bool, entry: Entry }
type Pool = struct { items: []Message, len: usize }
type Role = enum u8 { Follower, Candidate, Leader }
type Node = struct { id: u32, role: Role, term: u64, voted_for: u32, votes: u64, leader: u32, log: []Entry, log_len: usize, snap_index: u64, snap_term: u64, snap_state: i64, commit: u64, applied: u64, state: i64, next_index: []u64, match_index: []u64, cfg_old: u64, cfg_new: u64, timeout_at: u64, heartbeat_at: u64 }
type Cluster = struct { nodes: []Node, rng: rand.Pcg64, timeout_min: u64, timeout_max: u64, heartbeat: u64 }
type Acceptor = struct { promised: u64, accepted_n: u64, accepted_value: i64 }
type Proposer = struct { round: u64, n: u64, value: i64, phase: u8, promises: u64, best_n: u64, best_value: i64, learned_n: u64, learned_mask: u64, decided: bool, decided_value: i64 }
type Paxos = struct { acceptors: []Acceptor, proposers: []Proposer }
type MpNode = struct { promised: u64, slot_n: []u64, slot_value: []i64, ballot: u64, leading: bool, promises: u64, next_slot: u64, proposed: []i64, accept_mask: []u64, decided: []bool }
type MultiPaxos = struct { nodes: []MpNode }
type VrStatus = enum u8 { Normal, ViewChange }
type VrNode = struct { id: u32, view: u64, status: VrStatus, last_normal: u64, op: u64, commit: u64, state: i64, log: []i64, prepare_ok: []u64, svc_mask: u64, dvc_sent: bool, dvc_mask: u64, best_from: u32, best_view: u64, best_op: u64, best_commit: u64 }
type Vr = struct { nodes: []VrNode }
error TooSmall
error Invalid
error NotLeader
const NONE: u32 = 4294967295u32

fn pool(items: []Message) -> Pool
fn pool_push(p: *Pool, m: Message) -> err
fn pool_take(p: *Pool, at: usize) -> Message
fn pool_pop(p: *Pool) -> Message
fn has_bit(mask: u64, i: u32) -> bool
fn majority(mask: u64, cfg: u64) -> bool
fn has_majority(n: *const Node, mask: u64) -> bool
fn raft_node(id: u32, log: []Entry, next_index: []u64, match_index: []u64, config: u64) -> Node
fn raft_cluster(nodes: []Node, seed: u64, timeout_min: u64, timeout_max: u64, heartbeat: u64) -> Cluster
fn reset_timeout(c: *Cluster, n: *Node, now: u64)
fn last_index(n: *const Node) -> u64
fn term_at(n: *const Node, index: u64) -> u64
fn step_down(n: *Node, term: u64)
fn append_entry(n: *Node, e: Entry) -> err
fn apply(n: *Node) -> err
fn broadcast(c: *Cluster, n: *const Node, out: *Pool, m: Message) -> err
fn become_leader(c: *Cluster, n: *Node, now: u64, out: *Pool) -> err
fn send_append(c: *Cluster, n: *const Node, to: u32, out: *Pool) -> err
fn send_appends(c: *Cluster, n: *Node, now: u64, out: *Pool) -> err
fn raft_election_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err
fn advance_commit(c: *Cluster, n: *Node) -> err
fn raft_replicate_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err
fn raft_propose(c: *Cluster, node: usize, value: i64) -> (u64, err)
fn membership_change(c: *Cluster, node: usize, new_config: u64) -> err
fn raft_snapshot(c: *Cluster, node: usize) -> err
fn raft_snapshot_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err
fn raft_step(c: *Cluster, node: usize, now: u64, msg: *const Message, out: *Pool) -> err
fn paxos(acceptors: []Acceptor, proposers: []Proposer) -> Paxos
fn simple_majority(mask: u64, count: usize) -> bool
fn to_all(count: usize, out: *Pool, m: Message) -> err
fn paxos_propose(p: *Paxos, node: usize, value: i64, out: *Pool) -> err
fn paxos_step(p: *Paxos, node: usize, msg: *const Message, out: *Pool) -> err
fn multi_paxos(nodes: []MpNode) -> MultiPaxos
fn mp_node(slot_n: []u64, slot_value: []i64, proposed: []i64, accept_mask: []u64, decided: []bool) -> MpNode
fn multi_paxos_lead(m: *MultiPaxos, node: usize, out: *Pool) -> err
fn multi_paxos_propose(m: *MultiPaxos, node: usize, value: i64, out: *Pool) -> (u64, err)
fn multi_paxos_step(m: *MultiPaxos, node: usize, msg: *const Message, out: *Pool) -> err
fn viewstamped(nodes: []VrNode) -> Vr
fn vr_node(id: u32, log: []i64, prepare_ok: []u64) -> VrNode
fn vr_primary(v: *const Vr, view: u64) -> u32
fn vr_execute(n: *VrNode, up_to: u64)
fn vr_others(v: *const Vr, node: usize, out: *Pool, m: Message) -> err
fn vr_request(v: *Vr, node: usize, value: i64, out: *Pool) -> err
fn vr_primary_dead(v: *Vr, node: usize, out: *Pool) -> err
fn vr_copy_log(v: *Vr, node: usize, from: u32, count: u64)
fn vr_step(v: *Vr, node: usize, msg: *const Message, out: *Pool) -> err
```

Simulated consensus over caller message pools (node ids as mask bits): Raft
(`raft_election_step`, `raft_replicate_step`, `raft_propose`, `raft_snapshot` and
`raft_snapshot_step`, `membership_change` by joint consensus, `raft_step`), single-decree
`paxos` (`paxos_propose`, `paxos_step`), `multi_paxos` with a stable leader and
viewstamped replication (`vr_request`, `vr_primary_dead`, `vr_step`).

### `e.dist.commit`

```neper
type Kind = enum u8 { None, Prepare, VoteYes, VoteNo, PreCommit, Ack, Commit, Abort, Execute, StepDone, StepFailed, Compensate, Compensated }
type Message = struct { from: u32, to: u32, kind: Kind, step: u32 }
type Pool = struct { items: []Message, len: usize }
type CoordState = enum u8 { Init, Waiting, PreCommitting, Committed, Aborted }
type PartState = enum u8 { Init, Prepared, PreCommitted, Committed, Aborted }
type Participant = struct { state: PartState, vote_yes: bool, deadline: u64 }
type Commit = struct { three: bool, state: CoordState, parts: []Participant, yes: u64, acks: u64, deadline: u64, timeout: u64 }
type SagaState = enum u8 { Running, Completed, Compensating, Aborted }
type Saga = struct { orchestrated: bool, state: SagaState, done: []u8, fail_at: u32 }
type TccState = enum u8 { Free, Tried, Confirmed, Cancelled }
type Reservation = struct { state: TccState, expires: u64 }
type Tcc = struct { parts: []Reservation, ttl: u64, state: SagaState }
error TooSmall
error Invalid
error Expired
const NONE: u32 = 4294967295u32

fn pool(items: []Message) -> Pool
fn pool_push(p: *Pool, m: Message) -> err
fn pool_pop(p: *Pool) -> Message
fn send(out: *Pool, from: u32, to: u32, kind: Kind, step: u32) -> err
fn send_all(t: *const Commit, kind: Kind, out: *Pool) -> err
fn all_mask(t: *const Commit) -> u64
fn two_phase(parts: []Participant, timeout: u64) -> Commit
fn three_phase(parts: []Participant, timeout: u64) -> Commit
fn commit_begin(t: *Commit, now: u64, out: *Pool) -> err
fn decide(t: *Commit, state: CoordState, kind: Kind, out: *Pool) -> err
fn commit_step(t: *Commit, node: usize, now: u64, msg: *const Message, out: *Pool) -> err
fn commit_blocked(t: *const Commit, node: usize, now: u64) -> bool
fn saga_choreography(done: []u8, fail_at: u32) -> Saga
fn saga_orchestrate(done: []u8, fail_at: u32) -> Saga
fn saga_start(s: *Saga, out: *Pool) -> err
fn saga_step(s: *Saga, node: usize, msg: *const Message, out: *Pool) -> err
fn tcc(parts: []Reservation, ttl: u64) -> Tcc
fn tcc_try(t: *Tcc, node: usize, now: u64) -> err
fn tcc_expire(t: *Tcc, now: u64) -> usize
fn tcc_confirm(t: *Tcc, now: u64) -> err
fn tcc_cancel(t: *Tcc)
```

`two_phase` and `three_phase` commit (`commit_begin`, `commit_step`, `commit_blocked`),
sagas by choreography and orchestration (`saga_start`, `saga_step` with compensations
in reverse) and try-confirm-cancel (`tcc_try/confirm/cancel/expire`).

### `e.dist.replica`

```neper
type Replica = struct { clock: []u64, value: i64, up: bool }
type Store = struct { replicas: []Replica, r: usize, w: usize }
type Handoff = struct { target: []u32, value: []i64, clocks: []u64, width: usize, len: usize }
error Invalid
error NoQuorum
error TooSmall

fn quorum(n: usize, r: usize, w: usize) -> (bool, err)
fn replica(stamp: []u64) -> Replica
fn store(replicas: []Replica, r: usize, w: usize) -> Store
fn hinted_handoff(targets: []u32, values: []i64, clocks: []u64, width: usize) -> Handoff
fn handoff_store(h: *Handoff, to: u32, value: i64, stamp: []const u64) -> err
fn copy_clock(dst: []u64, src: []const u64)
fn quorum_write(s: *Store, coordinator: usize, value: i64, h: *Handoff) -> (usize, err)
fn read_set(s: *const Store, chosen: []usize) -> (usize, bool, err)
fn quorum_read(s: *const Store) -> (usize, bool, err)
fn read_repair(s: *Store, stale: []usize) -> (usize, err)
fn handoff_replay(h: *Handoff, s: *Store, to: u32) -> usize
```

`quorum` arithmetic, `quorum_write` with hints for down replicas, `quorum_read` by vector
clock (latest or conflict), `read_repair` of the stale, and `hinted_handoff` stores with
`handoff_replay` on recovery.

### `e.dist.collective`

```neper
type Op = enum u8 { Sum, Max }
type Collective = struct { vectors: []f64, n: usize, d: usize }
error Invalid

fn collective(vectors: []f64, n: usize, d: usize) -> (Collective, err)
fn chunk_lo(c: *const Collective, chunk: usize) -> usize
fn move_chunk(c: *Collective, from: usize, to: usize, chunk: usize, op: Op, reduce: bool)
fn all_reduce_ring(c: *Collective, op: Op) -> (usize, usize)
fn copy_row(c: *Collective, from: usize, to: usize)
fn broadcast(c: *Collective, root: usize) -> (usize, usize)
fn scatter(c: *Collective, root: usize) -> usize
fn gather(c: *Collective, root: usize) -> usize
```

`all_reduce_ring` (reduce-scatter then all-gather, transfers and steps counted),
binomial `broadcast`, `scatter` and `gather` over an n-by-d matrix.

### `e.robot.kinematics`

```neper
type Pose = struct { x: f64, y: f64, theta: f64 }
type Dh = struct { theta: f64, d: f64, a: f64, alpha: f64 }
error TooSmall
error Singular

fn pose(x: f64, y: f64, theta: f64) -> Pose
fn dh(theta: f64, d: f64, a: f64, alpha: f64) -> Dh
fn wrap_angle(angle: f64) -> f64
fn arc_step(p: Pose, distance: f64, turn: f64) -> Pose
fn dead_reckon(p: Pose, speed: f64, heading_rate: f64, dt: f64) -> Pose
fn odometry(p: Pose, left_ticks: i64, right_ticks: i64, ticks_per_metre: f64, wheel_base: f64) -> Pose
fn differential_drive(v: f64, omega: f64, wheel_base: f64) -> (f64, f64)
fn differential_drive_wheels(v_left: f64, v_right: f64, wheel_base: f64) -> (f64, f64)
fn ackermann(speed: f64, steering_angle: f64, wheel_base: f64) -> (f64, f64)
fn ackermann_step(p: Pose, speed: f64, steering_angle: f64, wheel_base: f64, dt: f64) -> Pose
fn dh_transform(theta: f64, d: f64, a: f64, alpha: f64, out: []f64) -> err
fn forward(params: []const Dh, joints: []const f64, out_pose: []f64, scratch: []f64) -> err
fn jacobian(params: []const Dh, joints: []f64, goal: []const f64, jac: []f64, err_out: []f64, scratch: []f64) -> err
fn norm3(v: []const f64) -> f64
fn ik_jacobian(params: []const Dh, joints: []f64, goal: []const f64, iterations: usize, step: f64, scratch: []f64) -> (f64, err)
fn ik_damped_least_squares(params: []const Dh, joints: []f64, goal: []const f64, iterations: usize, lambda: f64, scratch: []f64) -> (f64, err)
```

`Pose` and `Dh` records; `dead_reckon`, `odometry` and `ackermann_step` over one exact
arc model; `differential_drive` and its inverse; `ackermann`; `dh_transform` and
`forward` over 4x4 row-major matrices; `jacobian` by forward differences, `ik_jacobian`
(transpose) and `ik_damped_least_squares`.

### `e.robot.motion`

```neper
type Profile = struct { distance: f64, sign: f64, v_peak: f64, a_max: f64, t_acc: f64, t_flat: f64, total: f64 }
type SCurve = struct { distance: f64, sign: f64, v_peak: f64, a_peak: f64, j_max: f64, tj: f64, ta: f64, tv: f64, total: f64 }
type Agent = struct { x: f64, y: f64, vx: f64, vy: f64, radius: f64, pref_vx: f64, pref_vy: f64, v_max: f64 }
type DwaState = struct { x: f64, y: f64, theta: f64, v: f64, omega: f64 }
type DwaParams = struct { v_min: f64, v_max: f64, omega_max: f64, a_max: f64, alpha_max: f64, dt: f64, horizon: f64, v_samples: usize, omega_samples: usize, heading_weight: f64, clearance_weight: f64, velocity_weight: f64, radius: f64, clearance_cap: f64 }
error TooSmall
error Invalid

fn agent(x: f64, y: f64, vx: f64, vy: f64, radius: f64, pref_vx: f64, pref_vy: f64, v_max: f64) -> Agent
fn sign_of(x: f64) -> f64
fn trapezoid_profile(distance: f64, v_max: f64, a_max: f64) -> Profile
fn trapezoid_at(p: Profile, t: f64) -> (f64, f64)
fn s_curve_profile(distance: f64, v_max: f64, a_max: f64, j_max: f64) -> SCurve
fn s_curve_segment(p: SCurve, k: usize) -> (f64, f64)
fn s_curve_at(p: SCurve, t: f64) -> (f64, f64, f64)
fn min_jerk(start: f64, end: f64, duration: f64, t: f64) -> (f64, f64, f64)
fn spline_trajectory(times: []const f64, waypoints: []const f64, n: usize, d: usize, m: []f64, scratch: []f64) -> err
fn spline_at(times: []const f64, waypoints: []const f64, m: []const f64, n: usize, d: usize, t: f64, pos: []f64, vel: []f64) -> err
fn nearest_point(p: kin.Pose, path: []const f64) -> usize
fn pure_pursuit(p: kin.Pose, path: []const f64, lookahead: f64, wheel_base: f64) -> (f64, f64, err)
fn stanley(p: kin.Pose, path: []const f64, k: f64, speed: f64) -> (f64, err)
fn sample(lo: f64, hi: f64, index: usize, count: usize) -> f64
fn dynamic_window(s: DwaState, goal_x: f64, goal_y: f64, obstacles: []const f64, params: DwaParams) -> (f64, f64)
fn time_to_collision(a: Agent, b: Agent, vx: f64, vy: f64) -> f64
fn velocity_obstacles(a: Agent, others: []const Agent, candidates: []const f64, horizon: f64) -> usize
fn det(ax: f64, ay: f64, bx: f64, by: f64) -> f64
fn lp1(lines: []const f64, line_no: usize, radius: f64, opt_x: f64, opt_y: f64, direction_opt: bool, result: []f64) -> bool
fn lp2(lines: []const f64, count: usize, radius: f64, opt_x: f64, opt_y: f64, direction_opt: bool, result: []f64) -> usize
fn lp3(lines: []const f64, count: usize, begin: usize, radius: f64, result: []f64, proj: []f64)
fn orca(agents: []const Agent, i: usize, tau: f64, time_step: f64, out: []f64, scratch: []f64) -> err
fn repulsive(x: f64, y: f64, obstacles: []const f64, k_rep: f64, rho0: f64) -> (f64, f64)
fn potential_field(x: f64, y: f64, goal_x: f64, goal_y: f64, obstacles: []const f64, k_att: f64, k_rep: f64, rho0: f64) -> (f64, f64)
fn elastic_band(path: []f64, obstacles: []const f64, iterations: usize, k_internal: f64, k_external: f64, rho0: f64)
```

`trapezoid_profile`/`trapezoid_at`, `s_curve_profile`/`s_curve_at` (seven segments with
the triangular fallbacks), `min_jerk`, natural cubic `spline_trajectory`/`spline_at`,
`pure_pursuit`, `stanley`, `dynamic_window`, `velocity_obstacles`, `orca` (the RVO2
linear programs), `potential_field` and `elastic_band`.

### `e.robot.plan`

```neper
type Circle = struct { x: f64, y: f64, r: f64 }
type Pool = struct { xs: []f64, ys: []f64, th: []f64, parent: []u32, cost: []f64, used: usize }
type Config = struct { min_x: f64, min_y: f64, max_x: f64, max_y: f64, step: f64, radius: f64, goal_bias: f64, goal_tolerance: f64, iterations: usize }
type Kino = struct { v_min: f64, v_max: f64, omega_max: f64, dt: f64, substeps: usize, controls: usize }
type Grid = struct { cell: f64, w: usize, h: usize, headings: usize, arc: f64, radius: f64, substeps: usize }
type Heap = struct { key: []f64, node: []u32, used: usize }
error TooSmall
error Invalid
const NONE: u32 = 4294967295u32

fn two_pi() -> f64
fn pool(xs: []f64, ys: []f64, parent: []u32, cost: []f64) -> Pool
fn pool_th(xs: []f64, ys: []f64, th: []f64, parent: []u32, cost: []f64) -> Pool
fn add_node(p: *Pool, x: f64, y: f64, th: f64, parent: u32, cost: f64) -> (u32, err)
fn distance(x0: f64, y0: f64, x1: f64, y1: f64) -> f64
fn collision_free(x0: f64, y0: f64, x1: f64, y1: f64, obstacles: []const Circle) -> bool
fn point_free(x: f64, y: f64, obstacles: []const Circle) -> bool
fn nearest(p: *const Pool, x: f64, y: f64) -> u32
fn sample(cfg: *const Config, rng: *rand.Pcg64, gx: f64, gy: f64) -> (f64, f64)
fn steer(p: *const Pool, n: u32, sx: f64, sy: f64, step: f64) -> (f64, f64, f64)
fn rrt(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err)
fn propagate(p: *Pool)
fn best_goal(p: *const Pool, gx: f64, gy: f64, tolerance: f64) -> u32
fn sample_ellipse(cfg: *const Config, rng: *rand.Pcg64, sx: f64, sy: f64, gx: f64, gy: f64, c_min: f64, c_best: f64) -> (f64, f64)
fn rrt_star_run(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64, informed: bool) -> (u32, err)
fn rrt_star(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err)
fn rrt_informed(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, err)
fn extend(cfg: *const Config, obstacles: []const Circle, t: *Pool, qx: f64, qy: f64) -> (u32, bool, err)
fn connect_toward(cfg: *const Config, obstacles: []const Circle, t: *Pool, qx: f64, qy: f64) -> (u32, bool, err)
fn rrt_connect(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, a: *Pool, b: *Pool, sx: f64, sy: f64, gx: f64, gy: f64) -> (u32, u32, err)
fn roll_out(kino: *const Kino, obstacles: []const Circle, x0: f64, y0: f64, th0: f64, v: f64, omega: f64) -> (bool, f64, f64, f64)
fn rrt_kinodynamic(cfg: *const Config, kino: *const Kino, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, sx: f64, sy: f64, sth: f64, gx: f64, gy: f64) -> (u32, err)
fn node_distance(p: *const Pool, a: usize, b: usize) -> f64
fn link(obstacles: []const Circle, p: *const Pool, n: usize, k: usize, who: usize, adj: []u32)
fn prm_build(cfg: *const Config, obstacles: []const Circle, rng: *rand.Pcg64, p: *Pool, n: usize, k: usize, adj: []u32) -> err
fn heap_push(h: *Heap, key: f64, node: u32) -> err
fn heap_pop(h: *Heap) -> (f64, u32)
fn relax(p: *Pool, h: *Heap, u: usize, v: usize) -> err
fn prm_query(obstacles: []const Circle, p: *Pool, n: usize, k: usize, adj: []u32, sx: f64, sy: f64, gx: f64, gy: f64, heap_key: []f64, heap_node: []u32, closed: []u8) -> (u32, err)
fn advance(x: f64, y: f64, th: f64, length: f64, curvature: f64) -> (f64, f64, f64)
fn trace(grid: *const Grid, obstacles: []const Circle, x0: f64, y0: f64, th0: f64, curvature: f64) -> (bool, f64, f64, f64)
fn wrap_heading(th: f64) -> f64
fn cell_of(cfg: *const Config, grid: *const Grid, x: f64, y: f64, th: f64) -> (usize, bool)
fn curvature_of(grid: *const Grid, which: usize) -> f64
fn search_ready(p: *Pool, grid: *const Grid, closed: []u8, cell_node: []u32) -> err
fn offer(p: *Pool, h: *Heap, closed: []u8, cell_node: []u32, c: usize, x: f64, y: f64, th: f64, parent: u32, g: f64, priority: f64) -> err
fn hybrid_astar(cfg: *const Config, grid: *const Grid, obstacles: []const Circle, p: *Pool, closed: []u8, cell_node: []u32, heap_key: []f64, heap_node: []u32, sx: f64, sy: f64, sth: f64, gx: f64, gy: f64) -> (u32, err)
fn lattice_primitives(grid: *const Grid, prims: []i64) -> err
fn lattice_centre(cfg: *const Config, grid: *const Grid, ix: usize, iy: usize) -> (f64, f64)
fn state_lattice(cfg: *const Config, grid: *const Grid, obstacles: []const Circle, prims: []const i64, p: *Pool, closed: []u8, cell_node: []u32, heap_key: []f64, heap_node: []u32, sx: f64, sy: f64, sh: usize, gx: f64, gy: f64) -> (u32, err)
fn cell_node_of(cfg: *const Config, grid: *const Grid, p: *const Pool, u: usize) -> u32
fn path_length(xs: []const f64, ys: []const f64, n: usize) -> f64
fn path_extract(p: *const Pool, node: u32, out_x: []f64, out_y: []f64) -> (usize, f64, err)
fn path_join(a: *const Pool, a_node: u32, b: *const Pool, b_node: u32, out_x: []f64, out_y: []f64) -> (usize, f64, err)
```

Sampling planners over circle obstacles and caller node pools with a stated draw
order: `rrt`, `rrt_star`, `rrt_informed`, `rrt_connect` (with `path_join`),
`rrt_kinodynamic`, `prm_build`/`prm_query`; `hybrid_astar` over heading bins and
`state_lattice` over precomputed primitives; `path_extract`, `path_length`,
`collision_free`.

### `e.robot.map`

```neper
type Occupancy = struct { grid: []f64, w: usize, h: usize, resolution: f64 }
type Segment = struct { x0: f64, y0: f64, x1: f64, y1: f64 }
type Edge = struct { i: u32, j: u32, dx: f64, dy: f64, dth: f64, info_xy: f64, info_th: f64 }
type Particles = struct { xs: []f64, ys: []f64, ths: []f64, weights: []f64, scratch: []f64, n: usize }
type Motion = struct { dx: f64, dy: f64, dth: f64, noise_xy: f64, noise_th: f64 }
type Sensor = struct { field: []const f64, max_range: f64, sigma: f64, off_grid: f64 }
error TooSmall
error Invalid

fn two_pi() -> f64
fn wrap_angle(th: f64) -> f64
fn abs_i64(v: i64) -> i64
fn occupancy(grid: []f64, w: usize, h: usize, resolution: f64) -> (Occupancy, err)
fn cell_x(o: *const Occupancy, x: f64) -> i64
fn inside(o: *const Occupancy, ix: i64, iy: i64) -> bool
fn bump(o: *Occupancy, ix: i64, iy: i64, delta: f64)
fn occupancy_update(o: *Occupancy, px: f64, py: f64, pth: f64, ranges: []const f64, angles: []const f64, max_range: f64, l_occ: f64, l_free: f64) -> err
fn occupancy_probability(l: f64) -> f64
fn occupied(o: *const Occupancy, ix: i64, iy: i64, threshold: f64) -> bool
fn raycast(o: *const Occupancy, x: f64, y: f64, angle: f64, max_range: f64, threshold: f64) -> f64
fn likelihood_field(o: *const Occupancy, threshold: f64, field: []f64) -> err
fn nearest_on(s: Segment, x: f64, y: f64) -> (f64, f64)
fn scan_match(px: []const f64, py: []const f64, lines: []const Segment, x: f64, y: f64, th: f64, iterations: usize) -> (f64, f64, f64, f64)
fn target_of(lines: []const Segment, wx: f64, wy: f64) -> (f64, f64)
fn particles(xs: []f64, ys: []f64, ths: []f64, weights: []f64, scratch: []f64, n: usize) -> (Particles, err)
fn gaussian(rng: *rand.Pcg64) -> f64
fn particles_init(s: *Particles, rng: *rand.Pcg64, x: f64, y: f64, th: f64, spread_xy: f64, spread_th: f64)
fn amcl_predict(s: *Particles, m: *const Motion, rng: *rand.Pcg64)
fn amcl_weigh(s: *Particles, o: *const Occupancy, sensor: *const Sensor, ranges: []const f64, angles: []const f64) -> err
fn amcl_resample(s: *Particles, rng: *rand.Pcg64)
fn amcl_mean(s: *const Particles) -> (f64, f64, f64)
fn localize_amcl(s: *Particles, m: *const Motion, o: *const Occupancy, sensor: *const Sensor, ranges: []const f64, angles: []const f64, rng: *rand.Pcg64) -> (f64, f64, f64, err)
fn edge_error(xs: []const f64, ys: []const f64, ths: []const f64, e: Edge) -> (f64, f64, f64)
fn residual(xs: []const f64, ys: []const f64, ths: []const f64, edges: []const Edge) -> f64
fn cholesky_solve(hm: []f64, b: []f64, m: usize) -> err
fn accumulate(hm: []f64, b: []f64, m: usize, ja: []const f64, col_a: usize, jb: []const f64, col_b: usize, ex: f64, ey: f64, eth: f64, wxy: f64, wth: f64)
fn pose_graph_optimize(xs: []f64, ys: []f64, ths: []f64, edges: []const Edge, iterations: usize, scratch: []f64) -> (f64, err)
```

`occupancy_update` (Bresenham log-odds) with `occupancy_probability`, `raycast` and
`likelihood_field`; `scan_match` (point-to-line ICP); `localize_amcl` over `particles`
with predict, weigh and low-variance resample; `pose_graph_optimize` (Gauss-Newton with
analytic Jacobians and a dense Cholesky).

### `e.dsp`

```neper
type Window = enum u8 { Rectangular, Hann, Hamming, Blackman }
error Invalid
error TooSmall
error NoConvergence

fn ipow(t: f64, e: usize) -> f64
fn coefficient(c: []const f64, i: usize) -> f64
fn sinc(t: f64) -> f64
fn asinh(x: f64) -> f64
fn clear(xs: []f64)
fn moving_average(x: []const f64, k: usize, out: []f64) -> err
fn ema(x: []const f64, alpha: f64, out: []f64) -> err
fn savitzky_golay_coefficients(width: usize, order: usize, out: []f64, scratch: []f64) -> err
fn savitzky_golay(x: []const f64, width: usize, order: usize, out: []f64, scratch: []f64) -> err
fn zero_crossings(x: []const f64) -> usize
fn fir(x: []const f64, taps: []const f64, out: []f64) -> err
fn iir(x: []const f64, b: []const f64, a: []const f64, out: []f64, state: []f64) -> err
fn one_pole(x: []const f64, c: f64, out: []f64) -> err
fn comb(x: []const f64, delay: usize, gain: f64, out: []f64, feedforward: bool) -> err
fn biquad(x: []const f64, c: []const f64, out: []f64, state: []f64) -> err
fn biquad_cookbook(kind: u8, frequency: f64, q: f64, gain_db: f64, out: []f64) -> err
fn biquad_lowpass(frequency: f64, q: f64, out: []f64) -> err
fn biquad_highpass(frequency: f64, q: f64, out: []f64) -> err
fn biquad_peak(frequency: f64, q: f64, gain_db: f64, out: []f64) -> err
fn window(kind: Window, n: usize, out: []f64) -> err
fn design_windowed_sinc(taps: usize, cutoff: f64, kind: Window, out: []f64) -> err
fn remez_value(x: f64, xs: []const f64, ys: []const f64, ad: []const f64) -> f64
fn design_parks_mcclellan(taps: usize, bands: []const f64, desired: []const f64, weights: []const f64, out: []f64, scratch: []f64) -> err
fn cmul(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64)
fn cdiv(ar: f64, ai: f64, br: f64, bi: f64) -> (f64, f64)
fn poly(rr: []const f64, ri: []const f64, cr: []f64, ci: []f64)
fn bilinear_transform(zr: []const f64, zi: []const f64, pr: []const f64, pi: []const f64, gain: f64, fs: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn finish_lowpass(zr: []f64, zi: []f64, pr: []f64, pi: []f64, gain: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn design_butterworth(order: usize, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn design_chebyshev(order: usize, ripple_db: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn horner(c: []const f64, zr: f64, zi: f64) -> (f64, f64, f64, f64)
fn poly_roots(c: []const f64, rr: []f64, ri: []f64) -> err
fn design_bessel(order: usize, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn agm_k(b0: f64) -> f64
fn ellipk(m: f64) -> f64
fn ellipkm1(p: f64) -> f64
fn ellipj(u: f64, m: f64) -> (f64, f64, f64)
fn arc_sc1(w: f64, m: f64) -> f64
fn ellipdeg(n: usize, m1: f64) -> f64
fn design_elliptic(order: usize, ripple_db: f64, attenuation_db: f64, cutoff: f64, b: []f64, a: []f64, scratch: []f64) -> err
fn stft(x: []const f64, frame: usize, hop: usize, win: []const f64, re: []f64, im: []f64) -> (usize, err)
fn istft(re: []const f64, im: []const f64, frames: usize, frame: usize, hop: usize, win: []const f64, out: []f64, scratch: []f64) -> err
fn hz_to_mel(f: f64) -> f64
fn mel_to_hz(m: f64) -> f64
fn mfcc(x: []const f64, sample_rate: f64, frame: usize, hop: usize, n_mels: usize, n_coeffs: usize, out: []f64, scratch: []f64) -> (usize, err)
fn cqt(x: []const f64, sample_rate: f64, f_min: f64, bins_per_octave: usize, n_bins: usize, re: []f64, im: []f64) -> err
fn cepstrum(x: []const f64, out: []f64, scratch: []f64) -> err
fn spectral_subtract(magnitude: []const f64, noise: []const f64, alpha: f64, floor: f64, out: []f64) -> err
fn wiener(x: []const f64, noise_variance: f64, frame: usize, out: []f64, scratch: []f64) -> err
fn levinson_durbin(r: []const f64, order: usize, out: []f64, scratch: []f64) -> (f64, err)
fn lpc(x: []const f64, order: usize, out: []f64, scratch: []f64) -> (f64, err)
fn dtw(a: []const f64, b: []const f64, cost: []f64) -> (f64, err)
fn dtw_path(cost: []const f64, na: usize, nb: usize, path_a: []usize, path_b: []usize) -> (usize, err)
fn tap_input(x: []const f64, n: usize, k: usize) -> f64
fn lms_core(x: []const f64, d: []const f64, mu: f64, eps: f64, normalised: bool, w: []f64, out_error: []f64) -> err
fn lms(x: []const f64, d: []const f64, mu: f64, w: []f64, out_error: []f64) -> err
fn nlms(x: []const f64, d: []const f64, mu: f64, eps: f64, w: []f64, out_error: []f64) -> err
fn rls(x: []const f64, d: []const f64, lambda: f64, delta: f64, w: []f64, p: []f64, scratch: []f64, out_error: []f64) -> err
fn resample_polyphase(x: []const f64, up: usize, down: usize, taps: []const f64, out: []f64) -> (usize, err)
fn resample_sinc(x: []const f64, ratio: f64, half_width: usize, out: []f64) -> err
```

Smoothing (`moving_average`, `ema`, `savitzky_golay`), filters (`fir`, `iir`, `one_pole`,
`comb`, `biquad` with cookbook makers), windows and FIR design (`window`,
`design_windowed_sinc`, `design_parks_mcclellan`), IIR prototypes with
`bilinear_transform` (`design_butterworth/chebyshev/bessel/elliptic`), spectral tools
(`stft`, `istft`, `mfcc`, `cqt`, `cepstrum`, `spectral_subtract`, `wiener`), prediction
and alignment (`levinson_durbin`, `lpc`, `dtw`, `dtw_path`, `zero_crossings`), adaptive
filters (`lms`, `nlms`, `rls`) and resampling (`resample_polyphase`, `resample_sinc`).

### `e.dist.anti_entropy`

```neper
type Entry = struct { key: u64, version: u64 }
type Merkle = struct { hashes: []u64, width: u64 }
error TooSmall
error Invalid

fn fnv_offset() -> u64
fn fnv_word(h: u64, v: u64) -> u64
fn leaves(m: *const Merkle) -> usize
fn merkle_build(entries: []const Entry, width: u64, hashes: []u64) -> (Merkle, err)
fn sync_node(a: *const Merkle, b: *const Merkle, node: usize, out: []usize, count: *usize, comparisons: *usize)
fn merkle_sync(a: *const Merkle, b: *const Merkle, out: []usize) -> (usize, usize, err)
fn lower_bound(entries: []const Entry, key: u64) -> usize
fn emit(out: []u64, count: *usize, key: u64)
fn merkle_diff_keys(a: []const Entry, b: []const Entry, width: u64, buckets: []const usize, out: []u64) -> (usize, err)
```

`merkle_build` over key-range buckets (FNV-1a leaves in a heap-ordered caller tree),
`merkle_sync` (top-down comparison answering the differing buckets and the comparison
count) and `merkle_diff_keys`.

### `e.dist.crdt`

```neper
type GCounter = struct { counts: []u64 }
type PnCounter = struct { pos: []u64, neg: []u64 }
type Lww = struct { value: u64, stamp: u64, site: u32 }
type Tag = struct { site: u32, counter: u32 }
type OrElem = struct { element: u64, tag: Tag, removed: bool }
type OrSet = struct { elems: []OrElem, count: usize, site: u32, counter: u32 }
type Kind = enum u8 { GCounter, PnCounter, Lww, OrSet }
type Crdt = struct { kind: Kind, gcounter: GCounter, pncounter: PnCounter, lww: Lww, orset: OrSet }
error TooSmall

fn fill(xs: []u64)
fn max_into(dst: []u64, src: []const u64)
fn sum(xs: []const u64) -> u64
fn gcounter(counts: []u64) -> GCounter
fn gcounter_increment(c: *GCounter, site: usize, by: u64)
fn gcounter_merge(dst: *GCounter, src: *const GCounter)
fn gcounter_value(c: *const GCounter) -> u64
fn pncounter(pos: []u64, neg: []u64) -> PnCounter
fn pncounter_increment(c: *PnCounter, site: usize, by: u64)
fn pncounter_decrement(c: *PnCounter, site: usize, by: u64)
fn pncounter_merge(dst: *PnCounter, src: *const PnCounter)
fn pncounter_value(c: *const PnCounter) -> i64
fn lww() -> Lww
fn lww_wins(stamp: u64, site: u32, over: *const Lww) -> bool
fn lww_set(r: *Lww, value: u64, stamp: u64, site: u32) -> bool
fn lww_merge(dst: *Lww, src: *const Lww) -> bool
fn orset(elems: []OrElem, site: u32) -> OrSet
fn orset_add(s: *OrSet, element: u64) -> err
fn orset_remove(s: *OrSet, element: u64) -> usize
fn orset_contains(s: *const OrSet, element: u64) -> bool
fn orset_find(s: *const OrSet, tag: Tag) -> (usize, bool)
fn orset_merge(dst: *OrSet, src: *const OrSet) -> err
fn merge(a: *Crdt, b: *const Crdt) -> err
```

State-based CRDTs over caller storage: G-counter, PN-counter, LWW-register and an OR-set
with (site, counter) tags and tombstones, each with `_merge`, and `merge` dispatching on
the kind.

### `e.dist.deadlock`

```neper
type Edge = struct { from: u32, to: u32 }
type Probe = struct { initiator: u32, from: u32, to: u32 }
type Chase = struct { edges: []const Edge, site: []const u32, initiator: u32, probes: []Probe, sent: usize, seen: []bool }
error TooSmall
error Invalid

fn dfs(edges: []const Edge, n: usize, u: usize, colour: []usize, depth: []usize) -> (bool, usize)
fn wait_for_graph_cycle(edges: []const Edge, n: usize, scratch: []usize) -> (bool, usize, err)
fn spread(c: *Chase, u: usize)
fn chandy_misra_haas(edges: []const Edge, site: []const u32, initiator: usize, probes: []Probe, scratch: []bool) -> (bool, usize, err)
```

`wait_for_graph_cycle` (three-colour DFS) and `chandy_misra_haas` (edge-chasing probes
through a FIFO pool, deadlock when a probe returns to its initiator).

### `e.dist.dht`

```neper
error TooSmall
error Invalid

fn between(x: u64, a: u64, b: u64) -> bool
fn between_closed(x: u64, a: u64, b: u64) -> bool
fn chord_successor(nodes: []const u64, key: u64) -> usize
fn chord_finger_tables(nodes: []const u64, bits: u32, fingers: []u32) -> err
fn chord_lookup(nodes: []const u64, bits: u32, fingers: []const u32, start: usize, key: u64) -> (usize, usize)
fn kademlia_bucket(self_id: u64, other: u64) -> u32
fn kademlia_buckets(nodes: []const u64, self: usize, counts: []usize) -> err
fn knows(nodes: []const u64, i: usize, j: usize, k: usize) -> bool
fn kademlia_lookup(nodes: []const u64, start: usize, goal: u64, k: usize, alpha: usize, out: []usize, scratch: []usize) -> (usize, usize, err)
fn closest_u(nodes: []const u64, goal: u64, state: []const usize, k: usize, out: []usize) -> usize
```

Chord (`chord_successor`, `chord_finger_tables`, `chord_lookup` answering owner and hops)
and Kademlia (`kademlia_bucket`, `kademlia_buckets`, `kademlia_lookup` with k and alpha
over an in-memory node set).

### `e.dist.lock`

```neper
type Instance = struct { up: bool, skew: i64, latency: u64, holder: u64, expires: u64 }
type Lease = struct { holder: u64, granted: u64, expires: u64 }

fn instance(skew: i64, latency: u64) -> Instance
fn local_time(inst: *const Instance, now: u64) -> u64
fn instance_free(inst: *const Instance, now: u64) -> bool
fn redlock_acquire(instances: []Instance, token: u64, now: u64, ttl: u64, drift: u64) -> (bool, u64)
fn redlock_release(instances: []Instance, token: u64) -> usize
fn redlock_held(instances: []const Instance, token: u64, now: u64) -> usize
fn lease() -> Lease
fn lease_expired(l: *const Lease, now: u64) -> bool
fn lease_acquire(l: *Lease, holder: u64, now: u64, ttl: u64) -> bool
fn lease_renew(l: *Lease, holder: u64, now: u64, ttl: u64) -> bool
fn lease_due(l: *const Lease, now: u64, num: u64, den: u64) -> bool
```

Redlock over simulated instances with skew and latency (`redlock_acquire` needing a
majority inside the validity window, `redlock_release`, `redlock_held`) and leases
(`lease_acquire`, `lease_renew`, `lease_expired`, `lease_due`).

### `e.dist.mutex`

```neper
type Kind = enum u8 { Request, Reply, Token }
type Message = struct { kind: Kind, from: u32, to: u32, stamp: u64 }
type Sent = struct { out: []Message, count: usize }
type RaNode = struct { clock: u64, requesting: bool, stamp: u64, replies: usize, in_cs: bool }
type Ra = struct { nodes: []RaNode, deferred: []bool }
type RayNode = struct { holder: u32, asked: bool, in_cs: bool, head: usize, count: usize }
type Raymond = struct { nodes: []RayNode, queue: []u32 }
error TooSmall
error Invalid

fn sent(out: []Message) -> Sent
fn push(s: *Sent, kind: Kind, from: usize, to: usize, stamp: u64)
fn ra(nodes: []RaNode, deferred: []bool) -> (Ra, err)
fn ra_request(r: *Ra, i: usize, s: *Sent)
fn ra_receive(r: *Ra, m: Message, s: *Sent) -> bool
fn ra_release(r: *Ra, i: usize, s: *Sent)
fn raymond(nodes: []RayNode, queue: []u32, parent: []const u32, root: usize) -> (Raymond, err)
fn enqueue(t: *Raymond, i: usize, who: usize)
fn dequeue(t: *Raymond, i: usize) -> usize
fn settle(t: *Raymond, i: usize, s: *Sent) -> bool
fn raymond_request(t: *Raymond, i: usize, s: *Sent) -> bool
fn raymond_receive(t: *Raymond, m: Message, s: *Sent) -> bool
fn raymond_release(t: *Raymond, i: usize, s: *Sent)
```

Ricart-Agrawala (`ra_request`, `ra_receive`, `ra_release`: Lamport-stamped requests
with deferred replies) and Raymond's token tree (`raymond_request`, `raymond_receive`,
`raymond_release`: holder pointers and per-node queues), messages counted into a
caller pool.

### `e.dist.snapshot`

```neper
type Message = struct { from: u32, to: u32, marker: bool, amount: u64 }
type Sent = struct { out: []Message, count: usize }
type Proc = struct { state: u64, recorded: bool, snapshot: u64, markers: usize }
type Channel = struct { recording: bool, count: usize, total: u64 }
type Snapshot = struct { procs: []Proc, channels: []Channel }
error TooSmall
error Invalid

fn sent(out: []Message) -> Sent
fn push(s: *Sent, from: usize, to: usize, marker: bool, amount: u64)
fn snapshot(procs: []Proc, channels: []Channel, initial: []const u64) -> (Snapshot, err)
fn snapshot_send(s: *Snapshot, from: usize, to: usize, amount: u64, out: *Sent) -> err
fn record(s: *Snapshot, i: usize, except: usize, out: *Sent)
fn snapshot_initiate(s: *Snapshot, i: usize, out: *Sent) -> err
fn snapshot_step(s: *Snapshot, m: Message, out: *Sent) -> bool
fn snapshot_complete(s: *const Snapshot) -> bool
fn snapshot_total(s: *const Snapshot) -> u64
fn snapshot_live(s: *const Snapshot) -> u64
```

Chandy-Lamport over caller FIFO channels: `snapshot_send`, `snapshot_initiate`,
`snapshot_step` (markers and recorded channel states), `snapshot_complete`,
`snapshot_total` and `snapshot_live`.

### `e.grep`

```neper
type Match = struct { path: str, line: u32, column: u32, text: str }
type Index = struct { root: str, trigrams: u32 }
error Invalid

fn build_index(a: *mem.Arena, root: str) -> (Index, err)
fn search(a: *mem.Arena, root: str, pattern: str) -> ([]Match, err)
fn search_index(a: *mem.Arena, ix: Index, pattern: str) -> ([]Match, err)
```

Search is recursive literal byte matching with one-based line and byte-column positions;
each result retains its full matching line in the caller arena. Empty patterns are
invalid. The frozen `Index` value contains no state handle or postings, so `build_index`
records the root and bounded trigram count while `search_index` performs a fresh walk;
it is a compatibility entry point, not a hidden process-global cache.

### `e.audio`

```neper
type SampleFormat = enum u8 { I16, I32, F32 }
type Format = struct { rate: u32, channels: u8, sample: SampleFormat }
// Interleaved. `count` is frames, never samples: one frame is `channels` samples.
type Frames = struct { bytes: []u8, format: Format, count: usize }
error Unsupported
error Truncated

fn sample_bytes(s: SampleFormat) -> usize
fn frame_bytes(f: Format) -> usize
fn frames_in(f: Format, bytes: usize) -> usize
fn view(bytes: []u8, f: Format) -> (Frames, err)
fn sample_i32(fr: Frames, frame: usize, channel: u8) -> (i32, err)
fn set_sample_i32(fr: *Frames, frame: usize, channel: u8, value: i32) -> err
fn convert(a: *mem.Arena, src: Frames, to: SampleFormat) -> (Frames, err)
fn silence(fr: *Frames) -> err
```

The delivered base uses interleaved little-endian samples on every target. `sample_i32`
is the canonical signed full-scale representation: I16 occupies its high sixteen bits,
I32 is exact and F32 maps [-1, 1] with saturation. Views reject partial frames; convert
allocates exactly the target frame bytes in the caller arena and reads no device state.

### `e.audio.mixer`

```neper
// Gain is Q16, so 65536 is unity. Mixing accumulates in i32 and clips, which keeps a
// mix bit-identical on every target rather than depending on float rounding.
type Voice = struct { source: audio.Frames, position: usize, gain: i32, loops: bool, playing: bool }
type Mixer = struct { format: audio.Format, voices: []Voice, count: usize, master: i32 }
error Full
error Unsupported

fn init(m: *Mixer, f: audio.Format, voices: []Voice) -> err
fn play(m: *Mixer, source: audio.Frames, gain: i32, loops: bool) -> (usize, err)
fn stop(m: *Mixer, voice: usize) -> err
fn set_gain(m: *Mixer, voice: usize, gain: i32) -> err
fn active(m: Mixer) -> usize
fn mix_into(m: *Mixer, out: *audio.Frames) -> (usize, err)
fn resample(a: *mem.Arena, src: audio.Frames, rate: u32) -> (audio.Frames, err)
```

### `e.fmt.wav`

```neper
type Decoder = struct { bytes: []const u8, data_start: usize, at: usize, format: audio.Format, frames: usize }
error Invalid
error Unsupported

fn open(a: *mem.Arena, source_bytes: []const u8) -> (Decoder, err)
fn format(d: Decoder) -> audio.Format
fn frame_count(d: Decoder) -> usize
fn decode_into(d: *Decoder, out: *audio.Frames) -> (usize, err)
fn seek(d: *Decoder, frame: usize) -> err
fn encode(a: *mem.Arena, src: audio.Frames) -> ([]u8, err)
```

### `e.fmt.mp3`

```neper
type Decoder = struct { bytes: []const u8, at: usize, format: audio.Format, frames: usize, granule: usize, state: *void }
error Invalid
error Unsupported

fn open(a: *mem.Arena, source_bytes: []const u8) -> (Decoder, err)
fn format(d: Decoder) -> audio.Format
fn frame_count(d: Decoder) -> usize
fn decode_into(d: *Decoder, out: *audio.Frames) -> (usize, err)
fn seek(d: *Decoder, frame: usize) -> err
```

### `e.math.ntheory`

```neper
error TooSmall
error Invalid

fn gcd(a: u64, b: u64) -> u64
fn lcm(a: u64, b: u64) -> u64
fn extended_gcd(a: i64, b: i64) -> (i64, i64, i64)
fn add_mod(a: u64, b: u64, m: u64) -> u64
fn mul_mod(a: u64, b: u64, m: u64) -> u64
fn pow_mod(base: u64, exponent: u64, m: u64) -> u64
fn inverse_mod(a: u64, m: u64) -> (u64, bool)
fn is_prime(n: u64) -> bool
fn sieve(limit: usize, flags: []u8) -> err
fn sieve_segmented(low: u64, high: u64, flags: []u8, scratch: []u8) -> err
fn sieve_linear(limit: usize, spf: []u32, primes: []u32) -> (usize, err)
fn factor_trial(n: u64, factors: []u64, exponents: []u32) -> (usize, err)
fn factor_rho(n: u64) -> u64
fn factor_p_minus_1(n: u64, bound: u64) -> (u64, bool)
fn crt_garner(residues: []const u64, moduli: []const u64, mixed: []u64) -> (u64, bool)
fn crt(residues: []const u64, moduli: []const u64) -> (u64, u64, bool)
fn totient(n: u64) -> u64
fn discrete_log_bsgs(base: u64, wanted: u64, m: u64, bound: u64, scratch: []u64) -> (u64, bool)
fn pairs_swap(pairs: []u64, a: usize, b: usize)
fn pairs_sift(pairs: []u64, at: usize, end: usize)
fn discrete_log_pohlig_hellman(base: u64, wanted: u64, p: u64, scratch: []u64) -> (u64, bool)
fn discrete_log_kangaroo(base: u64, wanted: u64, m: u64, low: u64, high: u64) -> (u64, bool)
fn sqrt_mod(n: u64, p: u64) -> (u64, bool)
fn stern_brocot_search(x: f64, tolerance: f64, max_den: u64) -> (u64, u64)
fn farey_next(a: u64, c: u64, b: u64, d: u64, n: u64) -> (u64, u64)
fn farey(n: u64, out: []u64) -> (usize, err)
```

Exact over the full `u64` range: `mul_mod` never overflows and `is_prime` is the
deterministic Miller-Rabin test. Tables are caller storage: `sieve` needs
`flags.len > limit`, `sieve_segmented` `flags.len > high - low` and `scratch.len > sqrt(high)`,
`factor_trial` fifteen slots for any 64-bit value, `discrete_log_bsgs` `2 * ceil(sqrt(bound))`
words. `crt` takes pairwise coprime moduli whose product fits a `u64`.

### `e.math.root`

```neper
type Result = struct { x: f64, iterations: u32, converged: bool }

fn bisect[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, low: f64, high: f64, tolerance: f64, max_iterations: u32) -> Result
fn newton[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, df: fn(*Ctx, f64) -> f64, start: f64, tolerance: f64, max_iterations: u32) -> Result
fn halley[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, df: fn(*Ctx, f64) -> f64, d2f: fn(*Ctx, f64) -> f64, start: f64, tolerance: f64, max_iterations: u32) -> Result
fn secant[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, first: f64, second: f64, tolerance: f64, max_iterations: u32) -> Result
fn brent[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, low: f64, high: f64, tolerance: f64, max_iterations: u32) -> Result
```

Every method takes the function as a value over borrowed context and stops when
successive estimates are within `tolerance` or `f(x)` is exactly zero. The bracketing
methods answer `converged: false` without iterating when `f(low)` and `f(high)` share a
sign; the open methods answer `false` on a vanishing derivative or an exhausted budget.

### `e.math.special`

```neper
fn nan() -> f64
fn lgamma(x: f64) -> f64
fn gamma(x: f64) -> f64
fn erf(x: f64) -> f64
fn erfc(x: f64) -> f64
fn gamma_p(a: f64, x: f64) -> f64
fn gamma_q(a: f64, x: f64) -> f64
fn beta_i(a: f64, b: f64, x: f64) -> f64
fn beta_fraction(a: f64, b: f64, x: f64) -> f64
fn normal_cdf(z: f64) -> f64
fn normal_quantile(p: f64) -> f64
fn t_cdf(t: f64, df: f64) -> f64
fn chi_squared_cdf(x: f64, df: f64) -> f64
fn f_cdf(x: f64, d1: f64, d2: f64) -> f64
fn choose(n: f64, k: f64) -> f64
```

Lanczos log-gamma, series and continued-fraction incomplete gamma and beta,
Acklam's normal quantile refined by a Newton step; arguments outside a domain
answer NaN. Accurate to about fifteen digits away from the tails.

### `e.math.fft`

```neper
error Invalid
error TooSmall
const MODULUS: u64 = 998244353u64
const ROOT: u64 = 3u64

fn is_power_of_two(n: usize) -> bool
fn bit_reverse(re: []f64, im: []f64)
fn fft(re: []f64, im: []f64) -> err
fn ifft(re: []f64, im: []f64) -> err
fn transform(re: []f64, im: []f64, inverse: bool)
fn convolve(x: []const f64, y: []const f64, out: []f64, scratch: []f64) -> err
fn mul_mod(a: u64, b: u64) -> u64
fn pow_mod(base: u64, exponent: u64) -> u64
fn ntt(values: []u64) -> err
fn intt(values: []u64) -> err
fn ntt_transform(values: []u64, inverse: bool)
fn convolve_mod(x: []const u64, y: []const u64, out: []u64, scratch: []u64) -> err
fn fwht(values: []i64) -> err
fn dct2(x: []const f64, out: []f64) -> err
fn dct3(x: []const f64, out: []f64) -> err
```

`fft`/`ifft` transform split real and imaginary arrays of a power-of-two length in
place (`Invalid` otherwise); `convolve` multiplies two real sequences through them over
caller scratch; `ntt`/`intt` and `convolve_mod` are the same over the prime
998244353; `fwht` is the Walsh-Hadamard transform over `i64` and `dct2`/`dct3` the
cosine transforms of any length, unnormalised, `dct3` the inverse of `dct2` up to `2 / N`.

### `e.math.ode`

```neper
error TooSmall

fn euler[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, scratch: []f64) -> err
fn rk4[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, scratch: []f64) -> err
fn rkf45[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, tolerance: f64, scratch: []f64) -> (f64, f64, err)
fn root4(x: f64) -> f64
fn sqrt_f64(x: f64) -> f64
fn verlet[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err
fn leapfrog[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err
fn yoshida[Ctx: type](ctx: *Ctx, acceleration: fn(*Ctx, []const f64, []f64), x: []f64, v: []f64, h: f64, scratch: []f64) -> err
fn euler_maruyama[Ctx: type](ctx: *Ctx, drift: fn(*Ctx, f64, []const f64, []f64), diffusion: fn(*Ctx, f64, []const f64, []f64), t: f64, y: []f64, h: f64, noise: []const f64, scratch: []f64) -> err
```

Every stepper advances the caller's state by one step of `h` in place over caller
scratch: `euler` and `rk4` for `y' = f(t, y)`, `rkf45` adaptively (answering the step
taken, 0 when rejected, and the step to try next), `verlet`, `leapfrog` and `yoshida`
for second-order `x'' = a(x)` over separate position and velocity, and
`euler_maruyama` for `dy = drift dt + diffusion dW` with the caller's normal draws.

### `e.math.filter`

```neper
error TooSmall
error Singular

fn mat_mul(a: []const f64, b: []const f64, c: []f64, r: usize, k: usize, cols: usize)
fn mat_transpose(a: []const f64, out: []f64, r: usize, c: usize)
fn mat_inverse(a: []const f64, out: []f64, n: usize, scratch: []f64) -> err
fn kalman_predict(x: []f64, p: []f64, f: []const f64, q: []const f64, n: usize, scratch: []f64) -> err
fn kalman_update(x: []f64, p: []f64, h: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err
fn ekf_predict[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), jacobian: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, n: usize, scratch: []f64) -> err
fn ekf_update[Ctx: type](ctx: *Ctx, observe: fn(*Ctx, []const f64, []f64), jacobian: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err
fn ukf_step[Ctx: type](ctx: *Ctx, transition: fn(*Ctx, []const f64, []f64), observe: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, q: []const f64, r: []const f64, z: []const f64, n: usize, m: usize, scratch: []f64) -> err
fn cholesky(p: []const f64, n: usize, out: []f64) -> err
fn particle_step[Ctx: type](ctx: *Ctx, r: *rand.Pcg64, propagate: fn(*Ctx, *rand.Pcg64, []f64), likelihood: fn(*Ctx, []const f64, []const f64) -> f64, particles: []f64, weights: []f64, count: usize, n: usize, z: []const f64, scratch: []f64) -> err
fn particle_mean(particles: []const f64, weights: []const f64, count: usize, n: usize, out: []f64) -> err
fn complementary(angle: f64, rate: f64, accelerometer_angle: f64, dt: f64, alpha: f64) -> f64
fn quaternion_normalize(q: []f64)
fn madgwick(q: []f64, gx: f64, gy: f64, gz: f64, ax: f64, ay: f64, az: f64, dt: f64, beta: f64) -> err
fn mahony(q: []f64, integral: []f64, gx: f64, gy: f64, gz: f64, ax: f64, ay: f64, az: f64, dt: f64, kp: f64, ki: f64) -> err
fn quaternion_to_euler(q: []const f64) -> (f64, f64, f64)
```

Row-major matrices in caller storage: `kalman_predict`/`kalman_update` are the linear
filter, `ekf_*` take the caller's transition, observation and Jacobians, `ukf_step` the
unscented form over sigma points (with `cholesky` as its square root); `particle_step`
propagates, weights and resamples a particle set and `particle_mean` reads it; the
attitude filters `complementary`, `madgwick` and `mahony` update an angle or a
quaternion from gyroscope and accelerometer readings, `quaternion_to_euler` reads it.

### `e.math.opt`

```neper
type Result = struct { value: f64, iterations: u32, converged: bool }
error TooSmall
error Infeasible
error Unbounded
error Invalid

fn dot(a: []const f64, b: []const f64) -> f64
fn norm(a: []const f64) -> f64
fn line_search[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []const f64, fx: f64, gradient: []const f64, direction: []const f64, trial: []f64, initial: f64) -> f64
fn line_search_wolfe[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []const f64, fx: f64, gradient: []const f64, direction: []const f64, trial: []f64, trial_gradient: []f64) -> f64
fn gradient_descent[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, step: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn conjugate_gradient[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn bfgs[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn lbfgs[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), x: []f64, memory: usize, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn nelder_mead[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, x: []f64, scale: f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn replace_vertex(vertices: []f64, values: []f64, index: usize, point: []const f64, value: f64, n: usize)
fn simplex(c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tableau: []f64, basis: []usize) -> (f64, err)
fn pivot(t: []f64, width: usize, rows: usize, leave: usize, enter: usize)
```

An objective is `f(ctx, x)` with gradient `g(ctx, x, out)`; `gradient_descent`,
`conjugate_gradient` (Polak-Ribière), `bfgs` (dense inverse Hessian) and `lbfgs`
(`memory` pairs, Wolfe line search) improve the caller's `x` in place until the
gradient norm is under `tolerance`; `nelder_mead` needs no gradient; `simplex` solves
`max c·x, A x <= b, x >= 0` by the two-phase dense method, answering `Infeasible` or
`Unbounded`. Scratch is sized per declaration.

### `e.math.opt.meta`

```neper
type Result = struct { value: f64, iterations: u32 }
error TooSmall
error Invalid

fn copy(out: []f64, from: []const f64)
fn distance2(a: []const f64, b: []const f64) -> f64
fn seed_population(r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64) -> err
fn clamp(x: []f64, low: []const f64, high: []const f64)
fn simulated_annealing[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, start: f64, finish: f64, steps: u32, scratch: []f64) -> (Result, err)
fn hill_climb[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, patience: u32, max_iterations: u32, scratch: []f64) -> (Result, err)
fn tabu[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, neighbor: fn(*Ctx, *rand.Pcg64, []const f64, []f64), r: *rand.Pcg64, x: []f64, candidates: usize, tenure: usize, radius: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn evaluate_all[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, population: []const f64, count: usize, n: usize, values: []f64)
fn best_of(values: []const f64, count: usize) -> usize
fn genetic[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64, mutation_rate: f64, mutation_scale: f64, generations: u32, x: []f64, scratch: []f64) -> (Result, err)
fn tournament(r: *rand.Pcg64, values: []const f64, count: usize) -> usize
fn particle_swarm[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, positions: []f64, count: usize, n: usize, low: []const f64, high: []const f64, inertia: f64, cognitive: f64, social: f64, iterations: u32, x: []f64, scratch: []f64) -> (Result, err)
fn differential_evolution[Ctx: type](ctx: *Ctx, f: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, population: []f64, count: usize, n: usize, low: []const f64, high: []const f64, weight: f64, crossover: f64, generations: u32, x: []f64, scratch: []f64) -> (Result, err)
fn ant_colony(r: *rand.Pcg64, distance: []const f64, n: usize, ants: usize, alpha: f64, beta: f64, evaporation: f64, iterations: u32, tour: []usize, scratch: []f64, marks: []usize) -> (f64, err)
```

Minimisers needing no gradient: `simulated_annealing`, `hill_climb` and `tabu` move
by the caller's `neighbor(ctx, r, x, out)`; `genetic`, `particle_swarm` and
`differential_evolution` evolve a caller population seeded by `seed_population` in a
box; `ant_colony` builds a short closed tour over a distance matrix. Every method
draws from a `*rand.Pcg64` and leaves the best point in `x`.

### `e.math.float`

```neper
type Fields = struct { negative: bool, exponent: u32, mantissa: u64 }

fn unpack64(x: f64) -> Fields
fn unpack32(x: f32) -> Fields
fn pack64(f: Fields) -> f64
fn pack32(f: Fields) -> f32
fn exponent_of(x: f64) -> i32
fn round_shift(bits: u32, shift: u32) -> u32
fn to_f16(x: f32) -> u16
fn from_f16(h: u16) -> f32
fn to_bf16(x: f32) -> u16
fn from_bf16(h: u16) -> f32
```

`unpack64`/`unpack32` split a float into sign, biased exponent and mantissa and
`pack64`/`pack32` rebuild it; `exponent_of` is the unbiased exponent. `to_f16`/`from_f16`
convert `f32` and binary16 (round to nearest even, subnormals, infinities, a quiet NaN),
`to_bf16`/`from_bf16` the same for bfloat16.

### `e.math.gf`

```neper
error Invalid
error TooSmall

fn add(a: u8, b: u8) -> u8
fn mul(a: u8, b: u8, polynomial: u8) -> u8
fn pow(a: u8, exponent: u32, polynomial: u8) -> u8
fn inverse(a: u8, polynomial: u8) -> (u8, err)
fn tables(generator: u8, polynomial: u8, exp: []u8, log: []u8) -> err
fn mul_table(a: u8, b: u8, exp: []const u8, log: []const u8) -> u8
fn clmul(a: u64, b: u64) -> (u64, u64)
fn reduce(high: u64, low: u64, polynomial: u64) -> u64
```

GF(2^8) with the caller's reducing polynomial (0x1b AES, 0x1d Reed-Solomon): `add`,
`mul`, `pow`, `inverse`, and `tables` over a generator for `mul_table`. `clmul` is the
128-bit carry-less product of two 64-bit polynomials and `reduce` folds it modulo
`x^64 + polynomial`.

### `e.math.mc`

```neper
type Estimate = struct { mean: f64, standard_error: f64, count: usize }
error Invalid

fn estimate[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, r: *rand.Pcg64, count: usize) -> (Estimate, err)
fn antithetic[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, r: *rand.Pcg64, count: usize) -> (Estimate, err)
fn control_variate[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, g: fn(*Ctx, f64) -> f64, g_mean: f64, r: *rand.Pcg64, count: usize, samples: []f64) -> (Estimate, err)
fn finish(sum: f64, sum2: f64, count: usize) -> Estimate
```

`estimate`, `antithetic` and `control_variate` estimate `E[f(Z)]` over a standard
normal `Z` from the caller's PCG draws, answering the mean, its standard error and the
count; the control variate's coefficient is estimated from the same sample, kept in
`samples` (`2 * count`).

### `e.math.mcmc`

```neper
type Chain = struct { accepted: usize, proposed: usize }
error TooSmall
error Invalid

fn copy(out: []f64, from: []const f64)
fn dot(a: []const f64, b: []const f64) -> f64
fn metropolis_hastings[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, r: *rand.Pcg64, x: []f64, step: f64, samples: []f64, count: usize, scratch: []f64) -> (Chain, err)
fn gibbs[Ctx: type](ctx: *Ctx, draw: fn(*Ctx, *rand.Pcg64, usize, []f64), r: *rand.Pcg64, x: []f64, samples: []f64, count: usize) -> err
fn leapfrog[Ctx: type](ctx: *Ctx, g: fn(*Ctx, []const f64, []f64), x: []f64, p: []f64, gradient: []f64, step: f64)
fn hmc[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []f64, step: f64, leaps: usize, samples: []f64, count: usize, scratch: []f64) -> (Chain, err)
fn tree_row(record: []f64, row: usize, n: usize) -> []f64
fn no_u_turn(record: []f64, n: usize) -> bool
fn build_tree[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []const f64, p: []const f64, log_slice: f64, direction: f64, depth: usize, step: f64, out: []f64, regions: []f64, gradient: []f64, momentum: []f64, n: usize) -> (usize, bool)
fn nuts[Ctx: type](ctx: *Ctx, log_density: fn(*Ctx, []const f64) -> f64, g: fn(*Ctx, []const f64, []f64), r: *rand.Pcg64, x: []f64, step: f64, max_depth: usize, samples: []f64, count: usize, scratch: []f64) -> (Chain, err)
```

Every sampler starts at the caller's `x`, writes `count` rows into `samples` and leaves
`x` at the last state: `metropolis_hastings` with an isotropic normal proposal, `gibbs`
through the caller's conditional draw, `hmc` with a fixed leapfrog trajectory, and
`nuts` (algorithm 3, slice form, trees of at most `max_depth` doublings over
`(5 * max_depth + 14) * n` scratch). A `Chain` counts accepted and proposed moves.

### `e.math.opt.convex`

```neper
type Result = struct { value: f64, iterations: u32 }
error TooSmall
error Invalid
error Stalled
error Singular

fn interior_point(c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn quadratic_program(q: []const f64, c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn solve(q: []const f64, c: []const f64, a: []const f64, b: []const f64, m: usize, n: usize, linear: bool, x: []f64, tolerance: f64, max_iterations: u32, scratch: []f64) -> (Result, err)
fn objective(q: []const f64, c: []const f64, n: usize, linear: bool, x: []const f64) -> f64
fn gaussian_solve(matrix: []f64, rhs: []f64, n: usize) -> err
```

One infeasible-start primal-dual interior-point method behind `interior_point`
(`max c·x`) and `quadratic_program` (`min ½ x·Q x + c·x`), both subject to `A x <= b`,
`x >= 0`; an equality is two inequalities. A programme that is infeasible or unbounded
is `Stalled` when `max_iterations` runs out; scratch is `(n + m)^2 + 4 (n + m)`.

### `e.ml.linear`

```neper
error TooSmall
error Singular
error Invalid

fn solve(matrix: []f64, rhs: []f64, k: usize) -> err
fn at(x: []const f64, d: usize, i: usize, j: usize) -> f64
fn normal_equations(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, matrix: []f64, rhs: []f64)
fn ols(x: []const f64, y: []const f64, n: usize, d: usize, coefficients: []f64, scratch: []f64) -> err
fn ridge(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, coefficients: []f64, scratch: []f64) -> err
fn lasso(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, tolerance: f64, max_sweeps: u32, coefficients: []f64, scratch: []f64) -> err
fn sigmoid(z: f64) -> f64
fn predict(x: []const f64, d: usize, i: usize, coefficients: []const f64) -> f64
fn predict_probability(x: []const f64, d: usize, i: usize, coefficients: []const f64) -> f64
fn logistic(x: []const f64, y: []const f64, n: usize, d: usize, lambda: f64, tolerance: f64, max_iterations: u32, coefficients: []f64, scratch: []f64) -> (u32, err)
```

Row-major samples (`n` rows of `d`), coefficients `d + 1` with the intercept last:
`ols` and `ridge` solve the normal equations (`Singular` without a unique solution),
`lasso` is cyclic coordinate descent with soft thresholding on
`(1 / 2n) Σ (y - Xβ)² + λ Σ |β|`, `logistic` is Newton on the log loss with a ridge
of `lambda`; `predict` and `predict_probability` apply the coefficients.

### `e.ml.cluster`

```neper
type Linkage = enum u8 { Single, Complete, Average }
error TooSmall
error Invalid

fn distance_squared(x: []const f64, d: usize, i: usize, y: []const f64, j: usize) -> f64
fn nearest(x: []const f64, d: usize, i: usize, centroids: []const f64, k: usize) -> (usize, f64)
fn kmeans(x: []const f64, n: usize, d: usize, k: usize, centroids: []f64, labels: []usize, max_iterations: u32, scratch: []usize) -> (u32, err)
fn kmeans_pp_init(x: []const f64, n: usize, d: usize, k: usize, r: *rand.Pcg64, centroids: []f64, scratch: []f64) -> err
fn kmeans_online(sample: []const f64, d: usize, k: usize, centroids: []f64, counts: []usize) -> (usize, err)
fn vector_quantize(x: []const f64, n: usize, d: usize, k: usize, epsilon: f64, centroids: []f64, labels: []usize, max_iterations: u32, scratch: []usize) -> (u32, err)
fn medoid_cost(x: []const f64, n: usize, d: usize, medoids: []const usize, k: usize) -> f64
fn kmedoids(x: []const f64, n: usize, d: usize, k: usize, medoids: []usize, labels: []usize, max_iterations: u32) -> (u32, err)
fn agglomerative(x: []const f64, n: usize, d: usize, linkage: Linkage, k: usize, labels: []usize, distances: []f64) -> err
fn neighbor_joining(distance: []const f64, n: usize, work: []f64, joins: []usize, lengths: []f64, scratch: []usize) -> (usize, err)
fn row_sum(work: []const f64, n: usize, ids: []const usize, dead: usize, i: usize) -> f64
fn gmm_em(x: []const f64, n: usize, d: usize, k: usize, means: []f64, variances: []f64, weights: []f64, responsibilities: []f64, tolerance: f64, max_iterations: u32) -> (f64, u32, err)
```

`kmeans` runs Lloyd's iterations from caller centroids (`kmeans_pp_init` seeds them,
`kmeans_online` updates them per streamed sample, `vector_quantize` grows them by LBG
splitting); `kmedoids` is PAM; `agglomerative` merges under single, complete or
average linkage over a caller distance matrix; `gmm_em` fits a diagonal Gaussian
mixture; `neighbor_joining` builds the tree of a distance matrix as joins and branch
lengths.

### `e.ml.cluster.density`

```neper
error TooSmall
error Invalid
const NOISE: usize = 18446744073709551615usize

fn distance(x: []const f64, d: usize, i: usize, j: usize) -> f64
fn neighbour_count(x: []const f64, n: usize, d: usize, i: usize, eps: f64) -> usize
fn dbscan(x: []const f64, n: usize, d: usize, eps: f64, min_points: usize, labels: []usize, scratch: []usize) -> (usize, err)
fn core_distance(x: []const f64, n: usize, d: usize, i: usize, eps: f64, min_points: usize, work: []f64) -> f64
fn infinity() -> f64
fn optics(x: []const f64, n: usize, d: usize, eps: f64, min_points: usize, order: []usize, reachability: []f64, scratch: []f64, work: []f64, marks: []usize) -> err
```

`dbscan` labels clusters and `NOISE` from `eps` and `min_points` (the point itself
counted) over a full scan; `optics` answers the processing order and a reachability
per sample, `1e300` for the unreached.

### `e.ml.knn`

```neper
error TooSmall
error Invalid

fn neighbors(x: []const f64, n: usize, d: usize, query: []const f64, k: usize, indices: []usize, distances: []f64) -> err
fn classify(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, query: []const f64, k: usize, scratch: []usize, distances: []f64) -> (usize, err)
fn regress(x: []const f64, y: []const f64, n: usize, d: usize, query: []const f64, k: usize, indices: []usize, distances: []f64) -> (f64, err)
```

`neighbors` finds the `k` nearest by a full Euclidean scan into caller storage;
`classify` takes the majority label (ties to the smallest) and `regress` the mean
target of those neighbours.

### `e.ml.bayes`

```neper
error TooSmall
error Invalid

fn gaussian_fit(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, means: []f64, variances: []f64, priors: []f64, scratch: []usize) -> err
fn gaussian_log_posterior(query: []const f64, d: usize, c: usize, means: []const f64, variances: []const f64, priors: []const f64) -> f64
fn gaussian_predict(query: []const f64, d: usize, classes: usize, means: []const f64, variances: []const f64, priors: []const f64) -> usize
fn multinomial_fit(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, alpha: f64, log_probability: []f64, log_prior: []f64, scratch: []usize) -> err
fn multinomial_predict(query: []const f64, d: usize, classes: usize, log_probability: []const f64, log_prior: []const f64) -> usize
```

`gaussian_fit`/`gaussian_predict` keep a mean and variance per class and feature
(a floor keeps a constant feature usable); `multinomial_fit`/`multinomial_predict` keep
Laplace-smoothed feature log probabilities from count features; both predict the
largest log posterior.

### `e.ml.tree`

```neper
type Node = struct { feature: usize, threshold: f64, left: u32, right: u32, value: f64 }
type Tree = struct { nodes: []Node, count: usize, classes: usize }
type Forest = struct { trees: []Tree, count: usize, classes: usize }
type Boost = struct { trees: []Tree, count: usize, base: f64, rate: f64 }
error TooSmall
error Invalid
const LEAF: u32 = 4294967295u32

fn impurity(x: []const f64, y: []const f64, rows: []const usize, count: usize, classes: usize, bins: []usize) -> f64
fn leaf_value(y: []const f64, rows: []const usize, count: usize, classes: usize, bins: []usize) -> f64
fn partition(x: []const f64, d: usize, rows: []usize, count: usize, feature: usize, threshold: f64) -> usize
fn best_split(x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, classes: usize, features: []const usize, feature_count: usize, bins: []usize, order: []usize) -> (usize, f64, f64)
fn grow(t: *Tree, x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, depth: usize, max_depth: usize, min_samples: usize, features: []usize, feature_count: usize, subset: usize, r: *rand.Pcg64, bins: []usize, order: []usize) -> (u32, err)
fn grow_tree(a: *mem.Arena, x: []const f64, y: []const f64, d: usize, rows: []usize, count: usize, classes: usize, max_depth: usize, min_samples: usize, subset: usize, r: *rand.Pcg64) -> (Tree, err)
fn cart(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, classes: usize, max_depth: usize, min_samples: usize) -> (Tree, err)
fn predict(t: *const Tree, sample: []const f64) -> f64
fn random_forest(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, classes: usize, trees: usize, subset: usize, max_depth: usize, min_samples: usize, r: *rand.Pcg64) -> (Forest, err)
fn forest_predict(f: *const Forest, sample: []const f64, bins: []usize) -> (f64, err)
fn gradient_boost(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, d: usize, rounds: usize, rate: f64, max_depth: usize, min_samples: usize, residuals: []f64) -> (Boost, err)
fn boost_predict(b: *const Boost, sample: []const f64) -> f64
```

Trees live in the arena as `Node`s (`LEAF` marks a leaf): `cart` grows one by the
best threshold split (Gini for `classes > 0`, squared error for regression) to
`max_depth`/`min_samples`; `random_forest` grows bootstrap trees with `subset`
random features per split and `forest_predict` votes or averages; `gradient_boost`
fits regression trees to residuals at a learning rate and `boost_predict` sums them.

### `e.ml.svm`

```neper
type Kind = enum u8 { Linear, Polynomial, Rbf }
type Kernel = struct { kind: Kind, gamma: f64, degree: f64, offset: f64 }
type Model = struct { alphas: []f64, bias: f64, kernel: Kernel }
error TooSmall
error Invalid

fn kernel(k: Kernel, x: []const f64, d: usize, i: usize, y: []const f64, j: usize) -> f64
fn decide(m: *const Model, x: []const f64, y: []const f64, n: usize, d: usize, q: []const f64, j: usize) -> f64
fn smo(x: []const f64, y: []const f64, n: usize, d: usize, k: Kernel, c: f64, tolerance: f64, passes: u32, max_sweeps: u32, r: *rand.Pcg64, alphas: []f64) -> (Model, u32, err)
```

`kernel` evaluates the linear, polynomial or RBF kernel of two samples; `smo` trains
the dual on labels `±1` by the simplified sequential minimal optimisation (random
partner per violating multiplier, box `c`, KKT `tolerance`); `decide` is the kernel
expansion over the support vectors.

### `e.ml.optim`

```neper
error TooSmall
error Invalid

fn sgd(parameters: []f64, gradient: []const f64, rate: f64) -> err
fn momentum(parameters: []f64, gradient: []const f64, velocity: []f64, rate: f64, beta: f64) -> err
fn rmsprop(parameters: []f64, gradient: []const f64, cache: []f64, rate: f64, decay: f64, epsilon: f64) -> err
fn adamw(parameters: []f64, gradient: []const f64, first: []f64, second: []f64, t: u64, rate: f64, beta1: f64, beta2: f64, epsilon: f64, weight_decay: f64) -> err
fn adam(parameters: []f64, gradient: []const f64, first: []f64, second: []f64, t: u64, rate: f64, beta1: f64, beta2: f64, epsilon: f64) -> err
fn cosine_schedule(base: f64, minimum: f64, step: u64, period: u64) -> f64
fn online_gd(parameters: []f64, gradient: []const f64, t: u64, base: f64) -> (f64, err)
```

One step each over flat parameter and gradient vectors: `sgd`, `momentum`,
`rmsprop`, `adam`, `adamw` (decoupled weight decay), `online_gd` (`base / sqrt(t)`),
and `cosine_schedule` with warm restarts; state vectors are the caller's.

### `e.ml.loss`

```neper
error TooSmall
error Invalid

fn dot(a: []const f64, b: []const f64, d: usize, i: usize, j: usize) -> f64
fn log_sum_exp(values: []const f64, n: usize) -> f64
fn info_nce(anchor: []const f64, candidates: []const f64, count: usize, d: usize, positive: usize, temperature: f64, scratch: []f64) -> (f64, err)
fn distance_squared(a: []const f64, b: []const f64, d: usize) -> f64
fn triplet(anchor: []const f64, positive: []const f64, negative: []const f64, d: usize, margin: f64) -> (f64, err)
fn distillation_kl(teacher: []const f64, student: []const f64, n: usize, temperature: f64, scratch: []f64) -> (f64, err)
fn log_add(a: f64, b: f64) -> f64
fn ctc(log_probabilities: []const f64, frames: usize, classes: usize, blank: usize, labels: []const usize, scratch: []f64) -> (f64, err)
```

`info_nce` (softmax over scaled dot products with one positive), `triplet` (the
hinge on squared distances), `distillation_kl` (`T² KL(teacher || student)` at a
temperature) and `ctc` (the forward algorithm in log space over `frames × classes`
log probabilities and a label sequence).

### `e.ml.sample`

```neper
error TooSmall
error Invalid

fn softmax(logits: []const f64, temperature: f64, out: []f64) -> err
fn rank(probabilities: []const f64, order: []usize)
fn draw(probabilities: []const f64, order: []const usize, count: usize, r: *rand.Pcg64) -> usize
fn top_k(logits: []const f64, temperature: f64, k: usize, r: *rand.Pcg64, probabilities: []f64, order: []usize) -> (usize, err)
fn top_p(logits: []const f64, temperature: f64, p: f64, r: *rand.Pcg64, probabilities: []f64, order: []usize) -> (usize, err)
fn contrastive(expert: []const f64, amateur: []const f64, alpha: f64, scratch: []f64) -> (usize, err)
fn beam_search[Ctx: type](ctx: *Ctx, score: fn(*Ctx, []const usize, []f64), n: usize, width: usize, length: usize, out: []usize, tokens: []usize, scores: []f64) -> (f64, err)
```

`softmax` at a temperature, `top_k` and `top_p` draws through the caller's PCG,
`contrastive` decoding (expert against amateur above a plausibility floor), and
`beam_search` over a caller's scoring step keeping the `width` best prefixes.

### `e.ml.nn`

```neper
type Op = enum u8 { Input, Add, Sub, Mul, Div, Neg, Exp, Log, Tanh, Relu, Sigmoid }
type Tape = struct { op: []Op, left: []usize, right: []usize, value: []f64, gradient: []f64, count: usize }
error TooSmall
error Invalid

fn perceptron_epoch(x: []const f64, y: []const f64, n: usize, d: usize, weights: []f64, rate: f64) -> (usize, err)
fn perceptron_predict(sample: []const f64, weights: []f64) -> f64
fn tape(op: []Op, left: []usize, right: []usize, value: []f64, gradient: []f64) -> Tape
fn record(t: *Tape, op: Op, left: usize, right: usize, value: f64) -> (usize, err)
fn input(t: *Tape, value: f64) -> (usize, err)
fn add(t: *Tape, a: usize, b: usize) -> (usize, err)
fn sub(t: *Tape, a: usize, b: usize) -> (usize, err)
fn mul(t: *Tape, a: usize, b: usize) -> (usize, err)
fn div(t: *Tape, a: usize, b: usize) -> (usize, err)
fn neg(t: *Tape, a: usize) -> (usize, err)
fn exp(t: *Tape, a: usize) -> (usize, err)
fn log(t: *Tape, a: usize) -> (usize, err)
fn tanh(t: *Tape, a: usize) -> (usize, err)
fn relu(t: *Tape, a: usize) -> (usize, err)
fn sigmoid(t: *Tape, a: usize) -> (usize, err)
fn backward(t: *Tape, root: usize) -> err
fn attention(queries: []const f64, keys: []const f64, values: []const f64, n: usize, m: usize, d: usize, dv: usize, causal: bool, out: []f64, scratch: []f64) -> err
fn matmul(x: []const f64, w: []const f64, n: usize, d: usize, e: usize, out: []f64)
fn multi_head_attention(x: []const f64, n: usize, d: usize, heads: usize, wq: []const f64, wk: []const f64, wv: []const f64, wo: []const f64, causal: bool, out: []f64, scratch: []f64) -> err
fn rope(x: []f64, p: u64, base: f64) -> err
```

`perceptron_epoch`/`perceptron_predict` are the perceptron rule; a `Tape` over caller
arrays records scalar operations (`input`, `add`, `sub`, `mul`, `div`, `neg`, `exp`,
`log`, `tanh`, `relu`, `sigmoid`) and `backward` fills every gradient in reverse;
`attention` is scaled dot-product attention (optionally causal), `multi_head_attention`
projects with caller `d × d` matrices and attends per head, `rope` rotates pairs of a
vector by their position.

### `e.ml.hmm`

```neper
error TooSmall
error Invalid

fn forward(start: []const f64, transition: []const f64, emission: []const f64, s: usize, k: usize, observed: []const usize, scratch: []f64) -> (f64, err)
fn viterbi(start: []const f64, transition: []const f64, emission: []const f64, s: usize, k: usize, observed: []const usize, path: []usize, scratch: []f64, back: []usize) -> (f64, err)
fn baum_welch(start: []f64, transition: []f64, emission: []f64, s: usize, k: usize, observed: []const usize, scratch: []f64) -> (f64, err)
```

Discrete-emission models as row-major probabilities: `forward` (scaled log
likelihood), `viterbi` (the most probable path and its log probability) and
`baum_welch` (one re-estimation pass in place, answering the likelihood before it).

### `e.ml.rl`

```neper
error TooSmall
error Invalid

fn greedy(q: []const f64, actions: usize, state: usize) -> usize
fn epsilon_greedy(q: []const f64, actions: usize, state: usize, epsilon: f64, r: *rand.Pcg64) -> usize
fn q_learning(q: []f64, actions: usize, state: usize, action: usize, reward: f64, next: usize, terminal: bool, rate: f64, gamma: f64) -> (f64, err)
fn sarsa(q: []f64, actions: usize, state: usize, action: usize, reward: f64, next: usize, next_action: usize, terminal: bool, rate: f64, gamma: f64) -> (f64, err)
```

Tabular action values (`states × actions`): `q_learning` and `sarsa` apply one
temporal-difference update, `epsilon_greedy` and `greedy` choose actions.

### `e.ml.reduce`

```neper
error TooSmall
error Invalid

fn symmetric_eigen(a: []f64, d: usize, values: []f64, vectors: []f64, tolerance: f64, sweeps: u32) -> err
fn pca(x: []const f64, n: usize, d: usize, mean: []f64, variances: []f64, components: []f64, scratch: []f64) -> err
fn pca_project(sample: []const f64, mean: []const f64, components: []const f64, d: usize, k: usize, out: []f64) -> err
fn pca_online(w: []f64, sample: []const f64, rate: f64) -> (f64, err)
fn frequent_directions_insert(sketch: []f64, rows: usize, d: usize, filled: *usize, sample: []const f64, scratch: []f64) -> err
fn tsne(x: []const f64, n: usize, d: usize, perplexity: f64, iterations: u32, rate: f64, momentum: f64, y: []f64, scratch: []f64) -> err
```

`symmetric_eigen` (cyclic Jacobi) serves `pca` (mean, falling variances, components
by row) and `pca_project`; `pca_online` is Oja's rule; `frequent_directions_insert`
maintains the deterministic sketch; `tsne` is exact t-SNE with a perplexity search
and momentum gradient descent into two dimensions.

### `e.ml.ann`

```neper
type Graph = struct { first: []u32, count: []u32, neighbours: []u32, m: usize, n: usize }
type IvfPq = struct { coarse: []f64, codebooks: []f64, codes: []u8, cell_start: []usize, cell_items: []u32, cells: usize, subspaces: usize, codebook_size: usize, d: usize, n: usize }
error TooSmall
error Invalid

fn minhash(set: []const u64, seed: u64, signature: []u64) -> err
fn jaccard_estimate(a: []const u64, b: []const u64) -> f64
fn lsh_match(a: []const u64, b: []const u64, bands: usize, rows: usize) -> bool
fn distance_squared(x: []const f64, d: usize, i: usize, q: []const f64, j: usize) -> f64
fn beam_insert(ids: []u32, dists: []f64, count: usize, cap: usize, candidate: u32, dist: f64) -> usize
fn graph_build(a: *mem.Arena, x: []const f64, n: usize, d: usize, m: usize, ef: usize, scratch: []f64, visited: []u32) -> (Graph, err)
fn graph_search(g: *const Graph, x: []const f64, d: usize, query: []const f64, k: usize, ef: usize, ids: []f64, dists: []f64, scratch: []f64, visited: []u32) -> (usize, err)
fn float_beam_insert(ids: []f64, dists: []f64, count: usize, cap: usize, candidate: usize, dist: f64) -> usize
fn ivf_pq_train(a: *mem.Arena, x: []const f64, n: usize, d: usize, cells: usize, subspaces: usize, codebook_size: usize, r: *rand.Pcg64, scratch: []f64, labels: []usize, marks: []usize) -> (IvfPq, err)
fn ivf_pq_search(index: *const IvfPq, query: []const f64, probes: usize, k: usize, ids: []u32, dists: []f64, scratch: []f64) -> (usize, err)
```

`minhash`/`jaccard_estimate`/`lsh_match` estimate and band set similarity;
`graph_build`/`graph_search` are a navigable small-world graph (the base layer of
HNSW) in the arena; `ivf_pq_train`/`ivf_pq_search` build an inverted file over k-means
cells with product-quantised residuals and search by asymmetric distance.

### `e.math.fixed`

```neper
// Q16.16 in i32. Every operation is integer, so a result is bit-identical on every
// target -- the basis for lockstep, rollback and replay. Angles are turns, not radians:
// one turn is ONE, so reducing an angle is masking and sin is defined for any i32.
type Fx = i32
type Fx64 = i64
error DivideByZero
error Domain

const ONE: Fx
const HALF: Fx
const QUARTER: Fx
const EIGHTH: Fx

fn from_int(n: i32) -> Fx
fn to_int(x: Fx) -> i32
fn from_ratio(num: i32, den: i32) -> (Fx, err)
fn mul(a: Fx, b: Fx) -> Fx
fn div(a: Fx, b: Fx) -> (Fx, err)
fn floor(x: Fx) -> i32
fn ceil(x: Fx) -> i32
fn round(x: Fx) -> i32
fn abs(x: Fx) -> Fx
fn min(a: Fx, b: Fx) -> Fx
fn max(a: Fx, b: Fx) -> Fx
fn clamp(x: Fx, lo: Fx, hi: Fx) -> Fx
fn lerp(a: Fx, b: Fx, t: Fx) -> Fx
fn isqrt64(value: i64) -> i64
fn sqrt(x: Fx) -> (Fx, err)
fn sin(angle: Fx) -> Fx
fn cos(angle: Fx) -> Fx
fn tan(angle: Fx) -> (Fx, err)
fn atan2(y: Fx, x: Fx) -> Fx
fn length(x: Fx, y: Fx) -> Fx
fn normalize(x: Fx, y: Fx) -> (Fx, Fx)
```

### `e.net.snapshot`

```neper
// Bit-packed state under a quantised field schema, written whole or as a delta against
// the baseline a peer has acknowledged.
type Field = struct { offset: usize, bits: u8, signed: bool, lo: i32, hi: i32 }
type Schema = struct { fields: []const Field, state_bytes: usize }
type Writer = struct { bytes: []u8, bit: usize }
type Reader = struct { bytes: []const u8, bit: usize }
error Invalid
error Full

fn writer(storage: []u8) -> Writer
fn reader(source: []const u8) -> Reader
fn bits_written(w: Writer) -> usize
fn bytes_written(w: Writer) -> usize
fn put_bits(w: *Writer, value: u32, count: u8) -> err
fn get_bits(r: *Reader, count: u8) -> (u32, err)
fn load(state: []const u8, offset: usize) -> i32
fn store(state: []u8, offset: usize, value: i32)
fn write_full(w: *Writer, s: Schema, state: []const u8) -> err
fn write_delta(w: *Writer, s: Schema, baseline: []const u8, state: []const u8) -> err
fn read_full(r: *Reader, s: Schema, out: []u8) -> err
fn read_delta(r: *Reader, s: Schema, baseline: []const u8, out: []u8) -> err
fn quantize(value: i32, f: Field) -> u32
fn dequantize(code: u32, f: Field) -> i32
```

### `e.game.ecs`

```neper
type Entity = struct { slot: u32, generation: u32 }
type Column = struct { id: u16, stride: usize, bytes: []u8, present: []u64 }
type Store = struct { columns: []Column, generations: []u32, free: []u32, count: usize, free_count: usize }
type Query = struct { store: *Store, ids: []const u16, at: usize }
error Full
error Unknown
error Stale
error Size

fn init(s: *Store, columns: []Column, generations: []u32, free: []u32) -> err
fn spawn(s: *Store) -> (Entity, err)
fn despawn(s: *Store, e: Entity) -> err
fn alive(s: Store, e: Entity) -> bool
fn attach(s: *Store, e: Entity, id: u16, value: []const u8) -> err
fn detach(s: *Store, e: Entity, id: u16) -> err
fn has(s: Store, e: Entity, id: u16) -> bool
fn get(s: Store, e: Entity, id: u16) -> ([]u8, err)
fn query(s: *Store, ids: []const u16) -> Query
fn next(q: *Query) -> (Entity, bool)
fn live_count(s: Store) -> usize
```

### `e.game.loop`

```neper
// A fixed step with an accumulator: `advance` returns how many whole steps to run and
// `alpha` the remainder, for interpolating a render between them. The clock is given
// the elapsed time rather than reading one, so a scripted clock replays exactly.
type Clock = struct { step: fixed.Fx, accumulator: fixed.Fx, ticks: u64 }
type Timer = struct { remaining: fixed.Fx, period: fixed.Fx, repeating: bool }
error Invalid

fn init(c: *Clock, step: fixed.Fx) -> err
fn advance(c: *Clock, elapsed: fixed.Fx, max_steps: usize) -> usize
fn alpha(c: Clock) -> fixed.Fx
fn timer(period: fixed.Fx, repeating: bool) -> Timer
fn tick(t: *Timer, step: fixed.Fx) -> bool
fn ready(t: Timer) -> bool
fn reset(t: *Timer) -> err

// Easing lives here rather than in a module of its own: these are a handful of Q16
// curves, and `e.ui.animation` is layer 6 and bound to the widget tree, so the game
// core cannot reach it.
fn ease_in(t: fixed.Fx) -> fixed.Fx
fn ease_out(t: fixed.Fx) -> fixed.Fx
fn ease_in_out(t: fixed.Fx) -> fixed.Fx
fn ease_back(t: fixed.Fx) -> fixed.Fx
fn ease_elastic(t: fixed.Fx) -> fixed.Fx
```

### `e.game.sprite`

```neper
// Frames and transitions, not pixels: a clip names a run of atlas regions and how long
// each is held, and a player walks it one tick at a time.
type Region = struct { x: u16, y: u16, w: u16, h: u16, pivot_x: i16, pivot_y: i16 }
type Atlas = struct { regions: []const Region, names: []const str }
type Clip = struct { first: u16, count: u16, hold: u16, loops: bool, then: u16 }
type Player = struct { clip: u16, frame: u16, timer: u16, finished: bool }
error Unknown
error Invalid

const NONE: u16

fn region(at: Atlas, name: str) -> (Region, err)
fn play(p: *Player, clip: u16) -> err
fn advance(p: *Player, clips: []const Clip) -> err
fn frame(p: Player, clips: []const Clip) -> u16
fn region_at(atlas: Atlas, index: u16) -> (Region, err)
fn finished(p: Player) -> bool
fn progress(p: Player, clips: []const Clip) -> (u16, u16)
```

### `e.game.tilemap`

```neper
type Layer = struct { tiles: []u16, width: u32, height: u32 }
type Map = struct { layers: []Layer, tile_w: u32, tile_h: u32, solid: []u64, opaque: []u64, elevation: []u8 }
error Bounds
error Size

fn cells(m: Map) -> usize
fn width(m: Map) -> u32
fn height(m: Map) -> u32

fn init(m: *Map, layers: []Layer, tile_w: u32, tile_h: u32, solid: []u64, opaque: []u64, elevation: []u8) -> err
fn at(m: Map, layer: usize, x: i32, y: i32) -> (u16, err)
fn set(m: *Map, layer: usize, x: i32, y: i32, tile: u16) -> err
fn is_solid(m: Map, x: i32, y: i32) -> bool
fn is_opaque(m: Map, x: i32, y: i32) -> bool
fn in_bounds(m: Map, x: i32, y: i32) -> bool
fn to_tile(m: Map, wx: fixed.Fx, wy: fixed.Fx) -> (i32, i32)
fn to_world(m: Map, tx: i32, ty: i32) -> (fixed.Fx, fixed.Fx)
fn height_at(m: Map, x: i32, y: i32) -> u8
fn set_solid(m: *Map, x: i32, y: i32, value: bool) -> err
fn set_opaque(m: *Map, x: i32, y: i32, value: bool) -> err
fn set_height(m: *Map, x: i32, y: i32, value: u8) -> err
fn derive(m: *Map, layer: usize, solid_ids: []const u16, opaque_ids: []const u16) -> err
```

### `e.game.collide2d`

```neper
type Aabb = struct { x: fixed.Fx, y: fixed.Fx, half_w: fixed.Fx, half_h: fixed.Fx }
type Hit = struct { hit: bool, time: fixed.Fx, normal_x: i32, normal_y: i32 }
type Grid = struct { heads: []u32, next: []u32, width: u32, height: u32, cell: fixed.Fx }
error Bounds
error Size

fn aabb(x: fixed.Fx, y: fixed.Fx, half_w: fixed.Fx, half_h: fixed.Fx) -> Aabb
fn miss() -> Hit

fn overlaps(a: Aabb, b: Aabb) -> bool
fn sweep(a: Aabb, dx: fixed.Fx, dy: fixed.Fx, b: Aabb) -> Hit
fn sweep_tiles(a: Aabb, dx: fixed.Fx, dy: fixed.Fx, m: tilemap.Map) -> Hit
fn ray_tiles(m: tilemap.Map, x: fixed.Fx, y: fixed.Fx, dx: fixed.Fx, dy: fixed.Fx, limit: fixed.Fx) -> Hit
fn grid_init(g: *Grid, heads: []u32, next: []u32, width: u32, height: u32, cell: fixed.Fx) -> err
fn grid_clear(g: *Grid) -> err
fn grid_insert(g: *Grid, id: u32, box: Aabb) -> err
fn grid_near(g: Grid, box: Aabb, out: []u32) -> (usize, err)
```

### `e.game.vision`

```neper
// Recursive shadowcasting over integer slopes -- no float comparison, so who can see
// what is identical on every machine, which is what lockstep requires.
type Cell = enum u8 { Unseen, Explored, Visible }
type Field = struct { width: u32, height: u32, visible: []u64, explored: []u64 }
error Bounds
error Size

fn init(f: *Field, width: u32, height: u32, visible: []u64, explored: []u64) -> err
fn clear_visible(f: *Field) -> err
fn cast(f: *Field, m: tilemap.Map, x: i32, y: i32, radius: u32) -> err
fn line_of_sight(m: tilemap.Map, x0: i32, y0: i32, x1: i32, y1: i32) -> bool
fn cell(f: Field, x: i32, y: i32) -> Cell
fn is_visible(f: Field, x: i32, y: i32) -> bool
fn is_explored(f: Field, x: i32, y: i32) -> bool
fn merge(dst: *Field, src: Field) -> err
fn visible_count(f: Field) -> usize
```

### `e.game.ai`

```neper
type Agent = struct { x: fixed.Fx, y: fixed.Fx, vx: fixed.Fx, vy: fixed.Fx, max_speed: fixed.Fx }
type Steer = struct { x: fixed.Fx, y: fixed.Fx }
type Kind = enum u8 { Sequence, Selector, Invert, Condition, Action }
type Behavior = struct { kind: Kind, first_child: u16, child_count: u16, id: u16 }
type Status = enum u8 { Running, Success, Failure }
// The search's working memory, sized by the caller: nothing here allocates.
type Scratch = struct { came_from: []u32, cost: []u32, heap: []u32, heap_f: []u32, heap_count: usize, seen: []u64 }
error Unreachable
error Size
error Bounds

fn steer(x: fixed.Fx, y: fixed.Fx) -> Steer
fn limit(s: Steer, most: fixed.Fx) -> Steer

fn seek(a: Agent, tx: fixed.Fx, ty: fixed.Fx) -> Steer
fn flee(a: Agent, tx: fixed.Fx, ty: fixed.Fx) -> Steer
fn arrive(a: Agent, tx: fixed.Fx, ty: fixed.Fx, slow_radius: fixed.Fx) -> Steer
fn wander(a: Agent, state: *rand.Pcg64, jitter: fixed.Fx) -> Steer
fn separate(a: Agent, others: []const Agent, radius: fixed.Fx) -> Steer
fn combine(parts: []const Steer, weights: []const fixed.Fx) -> Steer
fn run(tree: []const Behavior, at: u16, conditions: []const bool, action: *u16) -> Status
fn path_grid(m: tilemap.Map, sx: i32, sy: i32, gx: i32, gy: i32, s: *Scratch, out: []u32) -> (usize, err)
```

### `e.game.nav`

```neper
type Rect = struct { x: u32, y: u32, w: u32, h: u32 }
type Portal = struct { a: u32, b: u32, x0: u32, y0: u32, x1: u32, y1: u32 }
type Pt = struct { x: f64, y: f64 }
type Hpa = struct { walk: []const u8, w: usize, h: usize, c: usize, node_cell: []u32, node_of: []u32, node_count: usize, edge_from: []u32, edge_to: []u32, edge_cost: []u32, edge_count: usize, dist: []u32, came: []u32, queue: []u32, adist: []u32, acame: []u32, heap: []u64 }
error TooSmall
error Invalid
error Unreachable
const NONE: u32 = 4294967295u32

fn min_u32(a: u32, b: u32) -> u32
fn max_u32(a: u32, b: u32) -> u32
fn neighbour(w: usize, h: usize, cell: usize, d: usize) -> (usize, bool)
fn portal_between(ia: u32, ra: Rect, ib: u32, rb: Rect) -> (Portal, bool)
fn build_navmesh(walk: []const u8, w: usize, h: usize, regions: []Rect, portals: []Portal, region_of: []u32) -> (usize, usize, err)
fn tri_area2(a: Pt, b: Pt, c: Pt) -> f64
fn same(a: Pt, b: Pt) -> bool
fn portal_at(start: Pt, goal: Pt, left: []const Pt, right: []const Pt, i: usize) -> (Pt, Pt)
fn push_corner(out: []Pt, count: *usize, p: Pt) -> err
fn funnel(start: Pt, goal: Pt, left: []const Pt, right: []const Pt, out: []Pt) -> (usize, err)
fn heap_push(heap: []u64, count: *usize, v: u64) -> err
fn heap_pop(heap: []u64, count: *usize) -> u64
fn flow_field(cost: []const u8, w: usize, h: usize, goal: usize, dist: []u32, dir: []u8, heap: []u64) -> err
fn cluster_of(g: *Hpa, cell: usize) -> usize
fn add_edge(g: *Hpa, from: u32, to: u32, cost: u32) -> err
fn node_at(g: *Hpa, cell: usize) -> (u32, err)
fn entrance(g: *Hpa, ca: usize, cb: usize) -> err
fn place(g: *Hpa, first: usize, last: usize, edge: usize, vertical: bool) -> err
fn bfs_cluster(g: *Hpa, source: usize)
fn connect(g: *Hpa, node: u32, source: usize, reverse: bool) -> err
fn build_hpa(g: *Hpa) -> err
fn abstract_search(g: *Hpa, s: u32, total: usize) -> err
fn adjacent(w: usize, a: usize, b: usize) -> bool
fn push_cell(out: []u32, count: *usize, cell: u32) -> err
fn hierarchical_astar(g: *Hpa, start: usize, goal: usize, out: []u32) -> (u32, usize, err)
fn query(g: *Hpa, s: u32, t: u32, start: usize, goal: usize, out: []u32) -> (u32, usize, err)
```

`build_navmesh` (greedy maximal rectangles with portals), `funnel` (simple stupid
funnel), `flow_field` (Dijkstra distances and a direction per cell) and hierarchical
A* over clusters (`build_hpa`, `hierarchical_astar`).

### `e.game.procgen`

```neper
type Perm = struct { p: [512]u8 }
error Invalid
error TooSmall

fn perm(seed: u64) -> Perm
fn look(p: *const Perm, i: usize) -> usize
fn fade(t: f64) -> f64
fn lerp(t: f64, a: f64, b: f64) -> f64
fn grad(hash: usize, x: f64, y: f64, z: f64) -> f64
fn lattice(v: f64) -> (usize, f64)
fn perlin3(p: *const Perm, xin: f64, yin: f64, zin: f64) -> f64
fn perlin(p: *const Perm, x: f64, y: f64) -> f64
fn grad2(gi: usize, x: f64, y: f64) -> f64
fn corner(t0: f64, gi: usize, x: f64, y: f64) -> f64
fn simplex(p: *const Perm, xin: f64, yin: f64) -> f64
fn wrap(v: i64) -> u64
fn cell_seed(ix: i64, iy: i64, seed: u64) -> u64
fn worley(x: f64, y: f64, seed: u64) -> (f64, f64)
fn neighbour(w: usize, h: usize, cell: usize, d: usize) -> (usize, bool)
fn nth_bit(v: u64, k: u64) -> u32
fn wave_function_collapse(allow: []const u64, tiles: usize, w: usize, h: usize, r: *rand.Pcg64, domains: []u64, stack: []u32, out: []u8) -> err
```

`perm` (the reference Perlin table or a seeded shuffle), `perlin`/`perlin3`,
`simplex` (Gustavson), `worley` (F1 and F2) and `wave_function_collapse` over tile
adjacency masks with a documented collapse and propagation order.

### `e.game.physics`

```neper
type Constraint = struct { a: u32, b: u32, rest: f64, stiffness: f64, compliance: f64 }
type Contact = struct { a: u32, b: u32, nx: f64, ny: f64, bias: f64, friction: f64 }
type Aabb = struct { min_x: f64, min_y: f64, max_x: f64, max_y: f64 }
type Pair = struct { a: u32, b: u32 }
type Circle = struct { x: f64, y: f64, radius: f64, vx: f64, vy: f64 }
type SphParams = struct { h: f64, mass: f64, rest_density: f64, stiffness: f64, viscosity: f64, gravity: f64 }
type MacGrid = struct { w: usize, h: usize, u: []f64, v: []f64, p: []f64, div: []f64, u_next: []f64, v_next: []f64 }
error TooSmall
error Invalid

fn pi() -> f64
fn distance(pos: []const f64, a: usize, b: usize) -> (f64, f64, f64)
fn predict(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, gravity_y: f64, dt: f64) -> err
fn derive_velocity(pos: []const f64, vel: []f64, prev: []const f64, n: usize, dt: f64)
fn check_constraints(constraints: []const Constraint, n: usize) -> err
fn pbd_step(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, constraints: []const Constraint, gravity_y: f64, dt: f64, iterations: usize) -> err
fn xpbd_step(pos: []f64, vel: []f64, inv_mass: []const f64, prev: []f64, lambda: []f64, constraints: []const Constraint, gravity_y: f64, dt: f64, iterations: usize) -> err
fn clamp(x: f64, lo: f64, hi: f64) -> f64
fn solve_gauss_seidel(contacts: []const Contact, vel: []f64, inv_mass: []const f64, normal: []f64, tangent: []f64, iterations: usize) -> err
fn ccd_conservative(a: Circle, b: Circle, tolerance: f64) -> (f64, bool)
fn sweep_and_prune(boxes: []const Aabb, order: []u32, out: []Pair) -> (usize, err)
fn sph(pos: []f64, vel: []f64, density: []f64, pressure: []f64, fx: []f64, fy: []f64, params: SphParams, dt: f64) -> err
fn mac_init(g: *MacGrid, w: usize, h: usize, u: []f64, v: []f64, p: []f64, div: []f64, u_next: []f64, v_next: []f64) -> err
fn sample(field: []const f64, nx: usize, ny: usize, ox: f64, oy: f64, x: f64, y: f64) -> f64
fn sample_u(g: *MacGrid, x: f64, y: f64) -> f64
fn sample_v(g: *MacGrid, x: f64, y: f64) -> f64
fn fluid_mac(g: *MacGrid, gravity_y: f64, dt: f64, iterations: usize) -> err
fn mac_divergence(g: *MacGrid) -> f64
```

2-d dynamics over packed caller arrays: `pbd_step`, `xpbd_step` (compliance and
multipliers), `solve_gauss_seidel` (projected impulses with friction),
`ccd_conservative`, `sweep_and_prune`, `sph` (poly6, spiky, viscosity) and a MAC-grid
fluid step (`mac_init`, `fluid_mac`, `mac_divergence`).

### `e.game.anim`

```neper
type Vec3 = struct { x: f64, y: f64, z: f64 }
type Quat = struct { x: f64, y: f64, z: f64, w: f64 }
type DualQuat = struct { real: Quat, dual: Quat }
error TooSmall
error Invalid

fn vec3(x: f64, y: f64, z: f64) -> Vec3
fn add(a: Vec3, b: Vec3) -> Vec3
fn sub(a: Vec3, b: Vec3) -> Vec3
fn scale(a: Vec3, s: f64) -> Vec3
fn dot(a: Vec3, b: Vec3) -> f64
fn cross(a: Vec3, b: Vec3) -> Vec3
fn length(a: Vec3) -> f64
fn get(xs: []const f64, i: usize) -> Vec3
fn put(xs: []f64, i: usize, v: Vec3)
fn quat(x: f64, y: f64, z: f64, w: f64) -> Quat
fn quat_identity() -> Quat
fn quat_conjugate(q: Quat) -> Quat
fn quat_dot(a: Quat, b: Quat) -> f64
fn quat_add(a: Quat, b: Quat) -> Quat
fn quat_scale(q: Quat, s: f64) -> Quat
fn quat_mul(a: Quat, b: Quat) -> Quat
fn quat_normalize(q: Quat) -> Quat
fn quat_from_axis_angle(axis: Vec3, angle: f64) -> Quat
fn quat_between(from: Vec3, to: Vec3) -> Quat
fn quat_rotate(q: Quat, v: Vec3) -> Vec3
fn dq_from(rotation: Quat, translation: Vec3) -> DualQuat
fn dq_identity() -> DualQuat
fn dq_add(a: DualQuat, b: DualQuat) -> DualQuat
fn dq_scale(d: DualQuat, s: f64) -> DualQuat
fn dq_mul(a: DualQuat, b: DualQuat) -> DualQuat
fn dq_normalize(d: DualQuat) -> DualQuat
fn dq_translation(d: DualQuat) -> Vec3
fn dq_transform(d: DualQuat, v: Vec3) -> Vec3
fn dq_blend(bones: []const DualQuat, indices: []const u32, weights: []const f64) -> (DualQuat, err)
fn skin_dual_quaternion(bones: []const DualQuat, positions: []const f64, indices: []const u32, weights: []const f64, out: []f64) -> err
fn transform_affine(m: []const f64, v: Vec3) -> Vec3
fn skin_linear_blend(bones: []const f64, positions: []const f64, indices: []const u32, weights: []const f64, out: []f64) -> err
fn measure(joints: []const f64, lengths: []f64) -> (usize, f64, err)
fn straighten(joints: []f64, lengths: []const f64, n: usize, goal: Vec3)
fn ik_fabrik(joints: []f64, lengths: []f64, goal: Vec3, iterations: usize, tolerance: f64) -> (f64, err)
fn ik_ccd(joints: []f64, lengths: []f64, goal: Vec3, iterations: usize, tolerance: f64) -> (f64, err)
```

Quaternion and dual-quaternion helpers, `ik_fabrik` and `ik_ccd` over a joint chain,
`skin_linear_blend` (3x4 bones) and `skin_dual_quaternion` (blended with a hemisphere
flip).

### `e.game.dialog`

```neper
type Op = enum u8 { Always, FlagSet, FlagClear, VarEq, VarGe, VarLt }
type Condition = struct { op: Op, key: u16, value: i32 }
type Choice = struct { text: str, target: u16, show_if: Condition, set_flag: u16, add_key: u16, delta: i32 }
type Node = struct { text: str, speaker: u16, first_choice: u16, choice_count: u16, then: u16 }
type Tree = struct { nodes: []const Node, choices: []const Choice }
type State = struct { at: u16, flags: []u64, vars: []i32, finished: bool }
error Invalid
error Bounds

const NONE: u16
const END: u16

fn always() -> Condition
fn holds(s: State, c: Condition) -> bool
fn set_flag(s: *State, key: u16) -> err
fn add_value(s: *State, key: u16, delta: i32) -> err
fn finished(s: State) -> bool

fn start(s: *State, t: Tree, flags: []u64, vars: []i32) -> err
fn node(s: State, t: Tree) -> (Node, err)
fn available(s: State, t: Tree, out: []u16) -> (usize, err)
fn choose(s: *State, t: Tree, choice: u16) -> err
fn advance(s: *State, t: Tree) -> err
fn flag(s: State, key: u16) -> bool
fn value(s: State, key: u16) -> i32
```

### `e.game.particle`

```neper
type Particle = struct { x: fixed.Fx, y: fixed.Fx, vx: fixed.Fx, vy: fixed.Fx, life: u16, max_life: u16, kind: u16 }
type Emitter = struct { x: fixed.Fx, y: fixed.Fx, facing: fixed.Fx, spread: fixed.Fx, speed: fixed.Fx, life_min: u16, life_max: u16, kind: u16 }
type Pool = struct { particles: []Particle, count: usize }
error Full
error Size

fn init(p: *Pool, particles: []Particle) -> err
fn emit(p: *Pool, e: Emitter, state: *rand.Pcg64) -> (usize, err)
fn burst(p: *Pool, e: Emitter, state: *rand.Pcg64, count: u16) -> (usize, err)
fn step(p: *Pool, gravity_x: fixed.Fx, gravity_y: fixed.Fx, damping: fixed.Fx) -> usize
fn clear(p: *Pool) -> err
fn alive(p: Pool) -> usize
fn capacity(p: Pool) -> usize
fn age(particle: Particle) -> fixed.Fx
```

### `e.game.netsync`

```neper
// The half of netcode that is not a socket: an input ring, prediction ahead of the
// server, and reconciliation when an authoritative frame arrives.
type Input = struct { tick: u64, bits: u32 }
type Peer = struct { acked: u64, baseline: []u8 }
type Predictor = struct { inputs: []Input, head: usize, confirmed: u64, predicted: u64, divergences: u32 }
error Late
error Size

fn init(p: *Predictor, inputs: []Input) -> err
fn init_peer(peer: *Peer, baseline: []u8) -> err
fn known(p: Predictor, tick: u64) -> bool
fn replay_span(p: Predictor) -> u64
fn recoverable(p: Predictor) -> bool
fn divergences(p: Predictor) -> u32
fn record(p: *Predictor, sample: Input) -> err
fn predict(p: Predictor, tick: u64) -> (Input, err)
fn confirm(p: *Predictor, tick: u64, authoritative: []const u8, local: []const u8) -> (bool, err)
fn rollback_from(p: Predictor) -> u64
fn encode(w: *snapshot.Writer, s: snapshot.Schema, peer: *Peer, tick: u64, state: []const u8) -> err
fn decode(r: *snapshot.Reader, s: snapshot.Schema, peer: *Peer, tick: u64, out: []u8) -> err
```

### `e.game.camera`

```neper
// The viewport transform and the ordered draw list: what is on screen, and in what
// order it has to be drawn. Deciding the order is engine logic; drawing is not.
type Camera = struct { x: fixed.Fx, y: fixed.Fx, zoom: fixed.Fx, width: fixed.Fx, height: fixed.Fx, dead_w: fixed.Fx, dead_h: fixed.Fx, shake: fixed.Fx, shake_ticks: u16, shake_x: fixed.Fx, shake_y: fixed.Fx }
type Bounds = struct { min_x: fixed.Fx, min_y: fixed.Fx, max_x: fixed.Fx, max_y: fixed.Fx }
type Item = struct { id: u32, layer: i16, sort: fixed.Fx }
error Size
error Bounds

fn init(c: *Camera, width: fixed.Fx, height: fixed.Fx) -> err
fn set_deadzone(c: *Camera, width: fixed.Fx, height: fixed.Fx) -> err
fn set_zoom(c: *Camera, zoom: fixed.Fx) -> err
fn view_half_width(c: Camera) -> fixed.Fx
fn view_half_height(c: Camera) -> fixed.Fx
fn follow(c: *Camera, tx: fixed.Fx, ty: fixed.Fx) -> err
fn clamp_to(c: *Camera, b: Bounds) -> err
fn shake(c: *Camera, amount: fixed.Fx, ticks: u16) -> err
fn step(c: *Camera, state: *rand.Pcg64) -> err
fn to_screen(c: Camera, wx: fixed.Fx, wy: fixed.Fx, parallax: fixed.Fx) -> (fixed.Fx, fixed.Fx)
fn to_world(c: Camera, sx: fixed.Fx, sy: fixed.Fx) -> (fixed.Fx, fixed.Fx)
fn visible(c: Camera, box: collide2d.Aabb) -> bool
fn cull(c: Camera, boxes: []const collide2d.Aabb, out: []u32) -> (usize, err)
fn order(items: []Item) -> err
fn after(a: Item, b: Item) -> bool
```

### `e.game.grid`

```neper
// Square, isometric and hex coordinates over one integer vocabulary. Isometric is a
// coordinate transform plus a depth order, which is most of what 2.5D means in practice.
type Shape = enum u8 { Square, IsoDiamond, HexPointy, HexFlat }
type Coord = struct { q: i32, r: i32 }
error Bounds

fn coord(q: i32, r: i32) -> Coord
fn equal(a: Coord, b: Coord) -> bool
fn hexed(s: Shape) -> bool

fn to_world(s: Shape, c: Coord, tile_w: u32, tile_h: u32) -> (fixed.Fx, fixed.Fx)
fn from_world(s: Shape, wx: fixed.Fx, wy: fixed.Fx, tile_w: u32, tile_h: u32) -> Coord
fn neighbours(s: Shape, c: Coord, out: []Coord) -> (usize, err)
fn distance(s: Shape, a: Coord, b: Coord) -> u32
fn line(s: Shape, a: Coord, b: Coord, out: []Coord) -> (usize, err)
fn ring(s: Shape, centre: Coord, radius: u32, out: []Coord) -> (usize, err)
fn area(s: Shape, centre: Coord, radius: u32, out: []Coord) -> (usize, err)
fn depth(s: Shape, c: Coord, elevation: u8) -> i32
```

### `e.game.input`

```neper
// Action maps over device codes, and the buffering an action game needs: a press a few
// ticks early still lands, and an ordered run of presses inside a window is a combo.
// `e.ui.input` is the device layer at layer 6; this is the pure logic above it.
type Action = struct { id: u16, primary: u16, secondary: u16 }
type Axis = struct { id: u16, negative: u16, positive: u16 }
type Combo = struct { id: u16, first: u16, count: u16, window: u16 }
type State = struct { held: []u64, pressed: []u64, released: []u64, buffer: []u16, ages: []u16, head: usize }
error Unknown
error Size

const NONE: u16

fn init(s: *State, held_bits: []u64, pressed_bits: []u64, released_bits: []u64, buffer: []u16, ages: []u16) -> err
fn bound(a: Action, code: u16) -> bool

fn begin(s: *State) -> err
fn apply(s: *State, code: u16, down: bool) -> err
fn held(s: State, a: Action) -> bool
fn pressed(s: State, a: Action) -> bool
fn released(s: State, a: Action) -> bool
fn buffered(s: State, a: Action, window: u16) -> bool
fn consume(s: *State, a: Action) -> bool
fn axis(s: State, x: Axis) -> fixed.Fx
fn combo(s: State, c: Combo, steps: []const u16) -> bool
fn rebind(a: *Action, primary: u16, secondary: u16) -> err
```

### `e.audio.analysis`

```neper
error Invalid
error TooSmall

fn abs(x: f64) -> f64
fn parabolic(ym: f64, y0: f64, yp: f64) -> f64
fn magnitudes(re: []f64, im: []const f64, count: usize)
fn yin_difference(x: []const f64, out: []f64) -> (usize, err)
fn yin_pick(cmnd: []const f64, threshold: f64) -> (usize, f64)
fn yin_frequency(cmnd: []const f64, tau: usize, sample_rate: f64) -> f64
fn pitch_yin(x: []const f64, sample_rate: f64, threshold: f64, scratch: []f64) -> (f64, f64, err)
fn pitch_pyin(x: []const f64, sample_rate: f64, thresholds: []const f64, scratch: []f64) -> (f64, f64, err)
fn autocorrelation_lag(x: []const f64, tau: usize) -> f64
fn pitch_autocorrelation(x: []const f64, sample_rate: f64, f_min: f64, f_max: f64, scratch: []f64) -> (f64, err)
fn pitch_hps(x: []const f64, sample_rate: f64, harmonics: usize, scratch: []f64) -> (f64, err)
fn frame_count(n: usize, frame: usize, hop: usize) -> usize
fn onset_strength(x: []const f64, frame: usize, hop: usize, scratch: []f64, out: []f64) -> (usize, err)
fn onsets_pick(envelope: []const f64, threshold: f64, out: []usize) -> (usize, err)
fn onsets(x: []const f64, frame: usize, hop: usize, threshold: f64, scratch: []f64, out: []usize) -> (usize, err)
fn tempo(envelope: []const f64, hop: usize, sample_rate: f64) -> (f64, err)
fn beats(envelope: []const f64, bpm: f64, hop: usize, sample_rate: f64, tightness: f64, scratch: []f64, out: []usize) -> (usize, err)
fn chroma(x: []const f64, sample_rate: f64, frame: usize, hop: usize, scratch: []f64, out: []f64) -> (usize, err)
fn block_loudness(z: f64) -> f64
fn loudness_lufs(x: []const f64, sample_rate: f64, scratch: []f64) -> (f64, err)
fn voice_activity(x: []const f64, frame: usize, energy: f64, zcr: f64, flatness: f64, scratch: []f64, out: []bool) -> (usize, err)
```

Pitch (`pitch_yin`, `pitch_pyin`, `pitch_autocorrelation`, `pitch_hps`), onsets
(`onset_strength`, `onsets_pick`, `onsets`), `tempo` and `beats` (Ellis dynamic
programming), `chroma`, `loudness_lufs` (BS.1770-4 at 48 kHz) and `voice_activity`.

### `e.audio.fx`

```neper
error Invalid
error TooSmall

fn abs(x: f64) -> f64
fn db_to_gain(db: f64) -> f64
fn gain_to_db(g: f64) -> f64
fn coefficient(seconds: f64, sample_rate: f64) -> f64
fn compressor_gain(level_db: f64, threshold_db: f64, ratio: f64, knee_db: f64) -> f64
fn compressor(x: []const f64, threshold_db: f64, ratio: f64, attack: f64, release: f64, knee_db: f64, makeup_db: f64, sample_rate: f64, out: []f64) -> err
fn limiter(x: []const f64, ceiling: f64, lookahead: usize, release: f64, sample_rate: f64, out: []f64) -> err
fn gate(x: []const f64, threshold_db: f64, attack: f64, release: f64, sample_rate: f64, out: []f64) -> err
fn equalizer(x: []const f64, bands: []const f64, sample_rate: f64, out: []f64, scratch: []f64) -> err
fn echo_cancel(mic: []const f64, reference: []const f64, mu: f64, w: []f64, out: []f64) -> err
fn comb_delay(i: usize) -> usize
fn allpass_step(buffer: []f64, n: usize, input: f64) -> f64
fn reverb_schroeder(x: []const f64, feedback: f64, damp: f64, out: []f64, scratch: []f64) -> err
fn reverb_fdn(x: []const f64, delays: []const usize, feedback: f64, out: []f64, scratch: []f64) -> err
fn reverb_convolution(x: []const f64, impulse: []const f64, out: []f64) -> (usize, err)
fn wrap_phase(p: f64) -> f64
fn synthesis_hop(hop: usize, ratio: f64) -> usize
fn time_stretch_len(x_len: usize, ratio: f64, frame: usize, hop: usize) -> usize
fn time_stretch_scratch(x_len: usize, ratio: f64, frame: usize, hop: usize) -> usize
fn time_stretch(x: []const f64, ratio: f64, frame: usize, hop: usize, out: []f64, scratch: []f64) -> (usize, err)
fn pitch_shift(x: []const f64, semitones: f64, frame: usize, hop: usize, out: []f64, scratch: []f64) -> err
fn psola(x: []const f64, marks: []const usize, ratio: f64, out: []f64) -> err
```

`compressor` (soft-knee gain computer with a smoothed detector), `limiter` (look-ahead),
`gate`, `equalizer` (cascaded peaking biquads), `echo_cancel` (NLMS), `reverb_schroeder`
(Freeverb constants), `reverb_fdn` (Householder), `reverb_convolution`, `time_stretch`
and `pitch_shift` (phase vocoder over the STFT) and `psola`.

### `e.audio.synth`

```neper
type Stage = enum u8 { Idle, Attack, Decay, Sustain, Release }
type Adsr = struct { attack: f64, decay: f64, sustain: f64, release: f64, stage: Stage, level: f64 }
type Waveform = enum u8 { Saw, Square, Triangle }
type Interpolation = enum u8 { Linear, Cubic }
error Invalid
error TooSmall

fn fract(x: f64) -> f64
fn rate(seconds: f64, sample_rate: f64) -> f64
fn adsr(attack: f64, decay: f64, sustain: f64, release: f64, sample_rate: f64) -> Adsr
fn adsr_gate(e: *Adsr, on: bool)
fn adsr_next(e: *Adsr) -> f64
fn polyblep(t: f64, dt: f64) -> f64
fn oscillator_naive(kind: Waveform, phase: f64) -> f64
fn oscillator_polyblep(kind: Waveform, phase: f64, increment: f64) -> f64
fn wavetable_build(table: []f64, harmonics: usize) -> err
fn wavetable(table: []const f64, phase: f64, interpolation: Interpolation) -> f64
fn karplus_strong(frequency: f64, sample_rate: f64, decay: f64, r: *rand.Pcg64, out: []f64) -> err
```

`adsr` envelopes (`adsr_gate`, `adsr_next`), `oscillator_polyblep` (saw, square,
triangle) beside `oscillator_naive`, `wavetable_build`/`wavetable` (linear and
Catmull-Rom) and `karplus_strong`.

### `e.audio.spatial`

```neper
// A source at a point in the world becomes a gain and a pan on a mixer voice. Integer
// throughout, so a positioned mix stays as reproducible as an unpositioned one.
type Listener = struct { x: fixed.Fx, y: fixed.Fx, facing: fixed.Fx }
type Source = struct { x: fixed.Fx, y: fixed.Fx, gain: i32, min_distance: fixed.Fx, max_distance: fixed.Fx }
type Cue = struct { id: u16, first_variant: u16, variant_count: u16, gain: i32, cooldown: u16, remaining: u16 }
error Unknown

fn pan(l: Listener, s: Source) -> i32
fn attenuate(l: Listener, s: Source) -> i32
fn place(m: *mixer.Mixer, voice: usize, l: Listener, s: Source) -> err
fn trigger(m: *mixer.Mixer, c: *Cue, variants: []const audio.Frames, state: *rand.Pcg64, l: Listener, s: Source) -> (usize, err)
fn step_cues(cues: []Cue) -> err
```
