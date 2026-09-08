# neper module API catalogue

Status: exact public-surface proposal for the toolchain modules in `modules.md`.
Delivery commitment and presentation order come from `modules.json`'s `core`,
`extended` and `experimental` tiers; this file remains dependency-layer ordered.
This is the next-contract design, not an installed-toolchain availability report.
The coordinated changes in `stdlib-hardening.md` migrate delivered CPU APIs during
M2.5; later facilities retain their stated delivery gates. Semantic details in `spec.md` remain
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
fn push[T: type](l: *List[T], v: T) -> err
fn pop[T: type](l: *List[T]) -> (T, bool)
fn insert[T: type](l: *List[T], index: usize, v: T) -> err
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
fn push_front[T: type](d: *Deque[T], v: T) -> err
fn push_back[T: type](d: *Deque[T], v: T) -> err
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
fn push[T: type](s: *Stack[T], value: T) -> err
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
fn enqueue[T: type](q: *Queue[T], value: T) -> err
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
fn push_front[T: type](l: *List[T], value: T) -> (NodeId, err)
fn push_back[T: type](l: *List[T], value: T) -> (NodeId, err)
fn insert_before[T: type](l: *List[T], at: NodeId, value: T) -> (NodeId, err)
fn insert_after[T: type](l: *List[T], at: NodeId, value: T) -> (NodeId, err)
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
fn push[T: type](r: *Ring[T], v: T) -> bool
fn push_overwrite[T: type](r: *Ring[T], v: T) -> (T, bool)
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
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err)
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
fn push[T: type](h: *Heap[T], v: T) -> err
fn peek[T: type](h: *const Heap[T]) -> (T, bool)
fn pop[T: type](h: *Heap[T]) -> (T, bool)
fn clear[T: type](h: *Heap[T])
fn init_by[T: type, Ctx: type](a: *mem.Arena, capacity: usize, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err)
fn from_slice_by[T: type, Ctx: type](a: *mem.Arena, source: []const T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> (HeapBy[T, Ctx], err)
fn len_by[T: type, Ctx: type](h: *const HeapBy[T, Ctx]) -> usize
fn push_by[T: type, Ctx: type](h: *HeapBy[T, Ctx], value: T) -> err
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

### `e.data.tree`

```neper
type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }
type Iter[K: type, V: type] = struct { state: *const void }
type SetIter[K: type] = struct { inner: Iter[K, bool] }

fn init[K: type, V: type](a: *mem.Arena) -> Map[K, V]
fn len[K: type, V: type](m: *const Map[K, V]) -> usize
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err)
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
fn insert[T: type](m: *SlotMap[T], value: T) -> (Key, err)
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

### `e.algo.rand`

```neper
type Pcg64 = struct { state: u64, stream: u64 }
type Xoshiro256 = struct { s0: u64, s1: u64, s2: u64, s3: u64 }
type Mt19937 = struct { state: [624]u32, index: u32 }

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
fn union(s: *DisjointSet, a: u32, b: u32) -> bool
fn reset(s: *DisjointSet)
```

The caller supplies storage. `count` must fit `u32` and both slices. `find` performs
path compression and `union` uses union by rank; indices outside `count` follow the
ordinary bounds-trap rule.

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
locale-independent Unicode collation mechanism beneath it.

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
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow }
error Invalid

fn defaults() -> Style
fn validate(value: *const Style) -> err
```

Styles are ordinary immutable values. There is no selector engine, cascading global
sheet or reflective property lookup in version 1.

### `e.ui.layout`

```neper
type Axis = enum u8 { Horizontal, Vertical }
type MainAlign = enum u8 { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }
type CrossAlign = enum u8 { Start, End, Center, Stretch, Baseline }
type Constraints = struct { min_width: f32, max_width: f32, min_height: f32, max_height: f32 }
type Flex = struct { axis: Axis, main: MainAlign, cross: CrossAlign, gap: f32 }
type GridTrack = union enum u8 { Px: f32, Flex: f32, Auto }
type Grid = struct { columns: []const GridTrack, rows: []const GridTrack, column_gap: f32, row_gap: f32 }
type Child = struct { desired: geometry.Size, flex: f32 }
type Result = struct { size: geometry.Size, children: []const geometry.Rect }
error Invalid
error Overflow

fn constrain(value: geometry.Size, limits: Constraints) -> geometry.Size
fn flex(a: *mem.Arena, spec: Flex, limits: Constraints, children: []const Child) -> (Result, err)
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
error InvalidKey
error InvalidSignature

fn ed25519_public_from_secret(secret: Ed25519SecretKey) -> (Ed25519PublicKey, err)
fn ed25519_sign(secret: Ed25519SecretKey, message: []const u8) -> (Ed25519Signature, err)
fn ed25519_verify(public: Ed25519PublicKey, message: []const u8, signature: Ed25519Signature) -> bool
```

`Ed25519SecretKey.bytes` is the 32-byte seed form. Verification rejects non-canonical
encodings and small-order public keys.

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
type PublicKey = union enum u8 { Ed25519: sign.Ed25519PublicKey }
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
host trust store, clock or network revocation service implicitly.

---

## 5. Platform and host services

### `e.os`

```neper
type File = struct { raw: usize }
type Proc = struct { raw: usize }
type Thread = struct { raw: usize }
type Lib = struct { raw: usize }
type Handle = struct { raw: usize }
type Socket = struct { raw: usize }
type Poller = struct { raw: usize }
type Mapping = struct { raw: usize, address: *u8, len: usize }
type Watch = struct { raw: usize }
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
fn read(f: File, buf: []u8) -> (usize, err)
fn write(f: File, buf: []const u8) -> (usize, err)
fn seek(f: File, off: i64, whence: SeekWhence) -> (u64, err)
fn close(f: File) -> err
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
fn read_link(a: *mem.Arena, path: str) -> (str, err)
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err
fn current_dir(a: *mem.Arena) -> (str, err)
fn set_current_dir(a: *mem.Arena, path: str) -> err
fn set_mode(a: *mem.Arena, path: str, mode: u32) -> err
fn set_times(a: *mem.Arena, path: str, accessed_ns: i64, modified_ns: i64) -> err
fn pipe() -> (File, File, err)
fn spawn(a: *mem.Arena, argv: []const str, stdio: Stdio) -> (Proc, err)
fn spawn_with_options(a: *mem.Arena, options: SpawnOptions) -> (Proc, err)
fn wait(p: Proc) -> (i32, err)
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
fn thread_create[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err)
fn thread_join(t: Thread) -> err
fn thread_detach(t: Thread) -> err
fn wait_u32(p: *Atomic[u32], expected: u32, timeout_ns: i64) -> err
fn wake_one_u32(p: *Atomic[u32])
fn wake_all_u32(p: *Atomic[u32])
fn socket_open(family: SocketFamily, kind: SocketKind) -> (Socket, err)
fn socket_set_nonblocking(s: Socket, enabled: bool) -> err
fn socket_bind(s: Socket, address: SocketAddress) -> err
fn socket_listen(s: Socket, backlog: u32) -> err
fn socket_accept(s: Socket) -> (Socket, SocketAddress, err)
fn socket_connect(s: Socket, address: SocketAddress) -> err
fn socket_receive(s: Socket, dst: []u8) -> (usize, err)
fn socket_send(s: Socket, src: []const u8) -> (usize, err)
fn socket_receive_from(s: Socket, dst: []u8) -> (usize, SocketAddress, err)
fn socket_send_to(s: Socket, dst: SocketAddress, src: []const u8) -> (usize, err)
fn socket_shutdown(s: Socket, how: SocketShutdown) -> err
fn socket_close(s: Socket) -> err
fn socket_resolve(a: *mem.Arena, host: str, port: u16, family: SocketFamily) -> ([]SocketAddress, err)
fn file_handle(f: File) -> Handle
fn socket_handle(s: Socket) -> Handle
fn poller_open(a: *mem.Arena) -> (Poller, err)
fn poller_register(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err
fn poller_modify(p: Poller, handle: Handle, token: usize, interest: PollInterest) -> err
fn poller_unregister(p: Poller, handle: Handle) -> err
fn poller_wait(p: Poller, events: []PollEvent, timeout_ns: i64) -> (usize, err)
fn poller_wake(p: Poller) -> err
fn poller_close(p: Poller) -> err
fn map_file(f: File, offset: u64, len: usize, writable: bool) -> (Mapping, err)
fn mapping_bytes(m: Mapping) -> []const u8
fn mapping_bytes_mut(m: Mapping) -> ([]u8, err)
fn mapping_flush(m: Mapping) -> err
fn mapping_close(m: Mapping) -> err
fn watch_open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err)
fn watch_read(a: *mem.Arena, w: Watch, events: []WatchEvent) -> (usize, err)
fn watch_close(w: Watch) -> err
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err)
fn dlsym[F: type](a: *mem.Arena, l: Lib, sym: str) -> (F, err)
fn dlclose(l: Lib) -> err
fn last_error_detail(operation: str, subject: str) -> ErrorDetail
fn error_message(a: *mem.Arena, detail: ErrorDetail) -> (str, err)
type Dir = struct { raw: usize }
type FileLock = struct { raw: usize }
type ProcGroup = struct { raw: usize }
type ResolvePolicy = enum u8 { NoSymlinks, Beneath }

fn dir_open(a: *mem.Arena, path: str) -> (Dir, err)
fn dir_close(dir: Dir) -> err
fn open_at(a: *mem.Arena, dir: Dir, relative_path: str, flags: OpenFlags, policy: ResolvePolicy) -> (File, err)
fn remove_at(a: *mem.Arena, dir: Dir, relative_path: str, directory: bool) -> err
fn rename_at(a: *mem.Arena, src_dir: Dir, src_path: str, dst_dir: Dir, dst_path: str, overwrite: bool, durable: bool) -> err
fn file_lock(file: File, exclusive: bool, timeout_ns: i64) -> (FileLock, err)
fn file_unlock(lock: FileLock) -> err
fn proc_group_spawn(a: *mem.Arena, options: SpawnOptions) -> (ProcGroup, Proc, err)
fn proc_group_terminate(group: ProcGroup, force: bool) -> err
fn proc_group_close(group: ProcGroup) -> err

```

`current_dir` is absolute and in the host convention. It and `set_current_dir` are the
one pair here that reads and writes state belonging to the whole process rather than to a
path, so a caller that moves is the one that has to move back.

`read_link` gives back the target string as it was stored, resolving nothing; a path that
is not a link is `Unsupported`. `symlink` stores that string, and a host that records at
creation whether a link names a directory decides that from the target as the link will
see it. Creating one is privileged on some hosts and is `Denied` there.

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
entries are `NAME=VALUE`. `wait_u32` waits indefinitely when `timeout_ns < 0` and
polls once when it is zero. In `SocketAddress`, IPv4 uses the first four bytes and
zeros the remaining twelve. Pollers retain handles, interests and numeric tokens,
never callbacks; callers unregister a handle before closing it.

Every failing `e.os` call records the native code and portable classification in
thread-local runtime state. `last_error_detail` copies that state into an explicit
value and must be called before another `e.os` operation on that thread. Higher-level
APIs may expose a detail snapshot while ordinary callers retain cheap `err`/`try`.
`operation` and `subject` are borrowed caller strings, never inferred global state;
`error_message` is the only locale-dependent rendering operation in `e.os`.


These new primitives are the reviewed platform boundary for SL05/SL06, not permission
for e.fs/e.proc to add externs. Directory-relative operations reject absolute paths,
parent traversal and embedded NULs; NoSymlinks rejects every traversed link/reparse
point. Beneath permits only traversal provably confined under the opened root, or
returns Unsupported. No lexical-prefix or canonicalize-then-open safety claim.
remove_at/rename_at traverse without following symlinks; removing a final symlink
removes the link, not its target. Durable rename may succeed before persistence fails;
report that partial effect. File locks are cooperative unless the platform explicitly
guarantees more. Process groups promise supported descendant containment, not a
security sandbox; unsupported strict containment fails before spawning. SL05 names
platform delivery requirements and escape limitations.

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
type Writer = struct { ctx: *void, write: fn(*void, []const u8) -> (usize, err), flush: fn(*void) -> err }
type SliceReader = struct { data: []const u8, off: usize }
type SliceWriter = struct { data: []u8, off: usize }
type BufferedReader = struct { state: *void }
type BufferedWriter = struct { state: *void }
type Seeker = struct { ctx: *void, seek: fn(*void, i64, os.SeekWhence) -> (u64, err) }
type LimitedReader = struct { source: Reader, remaining: u64 }
type CountingWriter = struct { sink: Writer, count: u64 }
type TeeWriter = struct { left: Writer, right: Writer }
type MemoryWriter = struct { arena: *mem.Arena, start: usize, len: usize }
type BufferState = struct { source: Reader, sink: Writer, buffer: []u8, off: usize, len: usize }
error End
error TooSmall
error NoProgress

fn reader(ctx: *void, read_fn: fn(*void, []u8) -> (usize, err)) -> Reader
fn writer(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err)) -> Writer
fn file_reader(file: *os.File) -> Reader
fn file_writer(file: *os.File) -> Writer
fn slice_reader(state: *SliceReader) -> Reader
fn slice_writer(state: *SliceWriter) -> Writer
fn buffered_reader(a: *mem.Arena, source: Reader, capacity: usize) -> (BufferedReader, err)
fn buffered_writer(a: *mem.Arena, sink: Writer, capacity: usize) -> (BufferedWriter, err)
fn file_seeker(file: *os.File) -> Seeker
fn limited_reader(state: *LimitedReader, source: Reader, limit: u64) -> Reader
fn counting_writer(state: *CountingWriter, sink: Writer) -> Writer
fn tee_writer(state: *TeeWriter, left: Writer, right: Writer) -> Writer
fn memory_writer(a: *mem.Arena, capacity: usize) -> (MemoryWriter, Writer, err)
fn memory_bytes(w: *const MemoryWriter) -> []const u8
fn read(r: *Reader, dst: []u8) -> (usize, err)
fn read_exact(r: *Reader, dst: []u8) -> err
fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> ([]u8, err)
fn read_until(a: *mem.Arena, r: *Reader, delimiter: u8, limit: usize) -> ([]u8, err)
fn write(w: *Writer, src: []const u8) -> (usize, err)
fn write_all(w: *Writer, src: []const u8) -> err
fn flush(w: *Writer) -> err
fn seek(s: *Seeker, off: i64, whence: os.SeekWhence) -> (u64, err)
fn copy(dst: *Writer, src: *Reader, scratch: []u8) -> (u64, err)
fn print(s: str) -> err
fn printf[FMT: str](args: ...) -> err
fn writer_with_flush(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err), flush_fn: fn(*void) -> err) -> Writer
fn buffered_source(buffer: *BufferedReader) -> Reader
fn buffered_sink(buffer: *BufferedWriter) -> Writer
fn file_read(ctx: *void, dst: []u8) -> (usize, err)
fn file_write(ctx: *void, src: []const u8) -> (usize, err)
fn file_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err)
fn slice_read(ctx: *void, dst: []u8) -> (usize, err)
fn slice_write(ctx: *void, src: []const u8) -> (usize, err)
fn limited_read(ctx: *void, dst: []u8) -> (usize, err)
fn counting_write(ctx: *void, src: []const u8) -> (usize, err)
fn tee_write(ctx: *void, src: []const u8) -> (usize, err)
fn memory_write(ctx: *void, src: []const u8) -> (usize, err)
fn buffered_read(ctx: *void, dst: []u8) -> (usize, err)
fn buffered_write(ctx: *void, src: []const u8) -> (usize, err)
fn buffered_writer_flush(ctx: *void) -> err
fn forwarding_flush(ctx: *void) -> err
fn no_flush(ctx: *void) -> err

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
last_error_detail is a legacy M2 bridge pending H07, not the revised checked API's
error-detail transport. H07 migration must preserve partial effects and cleanup errors.

### `e.fs.mmap`

```neper
type Mapping = struct { raw: os.Mapping }
error Empty
error Invalid

fn open(a: *mem.Arena, path: str, writable: bool, offset: u64, len: usize) -> (Mapping, err)
fn bytes(m: Mapping) -> []u8
fn flush(m: Mapping) -> err
fn close(m: Mapping) -> err
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
fn close(watch: Watch) -> err
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
const DEFAULT_STACK: usize = 1048576

fn spawn[Ctx: type](entry: fn(*Ctx), ctx: *Ctx, stack: usize) -> (Thread, err)
fn join(thread: Thread) -> err
fn detach(thread: Thread) -> err
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
error Invalid

fn mutex() -> Mutex
fn mutex_lock(m: *Mutex)
fn mutex_try_lock(m: *Mutex) -> bool
fn mutex_lock_for(m: *Mutex, timeout: time.Duration) -> bool
fn mutex_unlock(m: *Mutex)
fn rwlock() -> RwLock
fn rwlock_read_lock(l: *RwLock)
fn rwlock_try_read_lock(l: *RwLock) -> bool
fn rwlock_read_lock_for(l: *RwLock, timeout: time.Duration) -> bool
fn rwlock_read_unlock(l: *RwLock)
fn rwlock_write_lock(l: *RwLock)
fn rwlock_try_write_lock(l: *RwLock) -> bool
fn rwlock_write_lock_for(l: *RwLock, timeout: time.Duration) -> bool
fn rwlock_write_unlock(l: *RwLock)
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
fn send[T: type](c: *Channel[T], value: T) -> err
fn try_send[T: type](c: *Channel[T], value: T) -> (bool, err)
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
fn push[T: type](q: *Queue[T], value: T) -> err
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
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err)
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
type Buf[T: type] = struct { owner: u32, slot: u32, generation: u32, len: usize }
type Grid = struct { x: usize, y: usize, z: usize }
type Id = struct { x: u32, y: u32, z: u32 }
type Cap = enum u8 { Int8, Int16, Int64, Float16, Float64, Atomic64, Subgroup, Ftz, DenormPreserve }
type Scope = enum u8 { Workgroup, Device }
error NoDevice
error AmbiguousDevice
error Unsupported
error OutOfMemory
error TooLarge
error Lost
error WrongDevice
error InvalidHandle

fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err)
fn devices(a: *mem.Arena, backend: Backend, limit: usize) -> ([]const DeviceInfo, err)
fn open_id(a: *mem.Arena, key: DeviceKey) -> (*Device, err)
fn info(a: *mem.Arena, device: *Device) -> (DeviceInfo, err)
fn close(device: *Device) -> err
fn has(device: *Device, capability: Cap) -> bool
fn queue(device: *Device) -> (*Queue, err)
fn alloc[T: type](q: *Queue, n: usize) -> (Buf[T], err)
fn upload[T: type](q: *Queue, src: []const T) -> (Buf[T], err)
fn len[T: type](buf: Buf[T]) -> usize
fn write[T: type](q: *Queue, dst: Buf[T], off: usize, src: []const T) -> err
fn launch[K: fn](q: *Queue, grid: Grid, args: ...) -> err
fn download[T: type](q: *Queue, src: Buf[T], dst: []T) -> err
fn sync(q: *Queue) -> err
fn release[T: type](q: *Queue, buf: Buf[T]) -> err
fn grid1(x: usize) -> Grid
fn grid2(x: usize, y: usize) -> Grid
fn grid3(x: usize, y: usize, z: usize) -> Grid
```

Discovery/selection is specified in [spec §10](spec.md#device-discovery-and-selection).
`devices` is a bounded, caller-arena-owned snapshot, including copied names and
capability lists; exceeding the limit fails rather than returning a partial success.
Indices are temporary backend ordinals. `open_id` requires an exact backend-scoped
UUID match, rejects duplicate matches with `AmbiguousDevice`, and never silently
falls back. `key_valid == false` means stable-key selection is unavailable, not that
a fabricated index/name hash may substitute. `info` copies the opening-time descriptor
of the selected device. Memory is reported capacity, not free or reserved storage.
Every queue/buffer belongs to one open device, including when two opens address the
same GPU. These additions are planned for M3 CPU/Vulkan, with CUDA in M4; they do not
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
fn close(socket: Socket) -> err
fn reader(socket: *Socket) -> io.Reader
fn writer(socket: *Socket) -> io.Writer
fn resolve_with_control(a: *mem.Arena, host: str, port: u16, family: Family, control: cancel.Control) -> ([]Endpoint, err)
fn tcp_connect_with_control(endpoint: Endpoint, control: cancel.Control) -> (Socket, err)
fn receive_with_control(socket: Socket, dst: []u8, control: cancel.Control) -> (usize, err)
fn send_with_control(socket: Socket, src: []const u8, control: cancel.Control) -> (usize, err)

```


Controlled operations use e.cancel and preserve byte counts on failure. DNS may
require bounded worker isolation; completion is not acknowledged while caller-owned
buffers remain in use. Unsupported cancellation guarantees are reported explicitly,
not implemented as a blocking call ignoring its deadline.

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
cannot be advertised until SHA-384/HKDF-SHA384 exists. The current Ed25519-only public
signature surface does not establish compatibility with typical RSA/ECDSA certificate
chains; those profiles require explicit reviewed additions or remain unsupported.
Do not silently weaken certificate/hostname verification to improve connectivity.
Entropy seeds require sufficient fresh caller entropy per independent handshake;
copied/reused config bytes are not permission to repeat ephemeral randomness.

### `e.net.http`

```neper
type Method = enum u8 { Get, Head, Post, Put, Patch, Delete, Options, Connect, Trace }
type Version = enum u8 { Http10, Http11 }
type Header = struct { name: str, value: str }
type Request = struct { method: Method, target: str, version: Version, headers: []const Header, body: []const u8 }
type Response = struct { version: Version, status: u16, reason: str, headers: []const Header, body: []const u8 }
type Limits = struct { start_line: usize, header_bytes: usize, header_count: usize, body_bytes: usize }
type Reader = struct { state: *void }
type Writer = struct { state: *void }
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
fn upload_image(r: *Renderer, image_view: image.ConstImage) -> (TextureId, err)
fn update_image(r: *Renderer, texture: TextureId, image_view: image.ConstImage) -> err
fn release_image(r: *Renderer, texture: TextureId) -> err
fn compile(r: *Renderer, list: DisplayList) -> (SceneId, err)
fn render(r: *Renderer, scene: SceneId, render_target: Target, size: geometry.Size) -> err
fn release_scene(r: *Renderer, scene: SceneId) -> err
fn close(r: *Renderer) -> err
```

Display lists borrow their paths, gradients and text layouts until `compile`
returns. A renderer owns bounded generation-checked GPU caches. Compilation may
retain tessellation and glyph data but never application widget pointers. Rendering
is explicit queue work followed by presentation through the target surface.

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
type Metrics = struct { logical_size: geometry.Size, framebuffer_width: u32, framebuffer_height: u32, scale: f32, focused: bool, visible: bool }
error Unsupported
error Invalid
error Closed

fn open(a: *mem.Arena, device: *gpu.Device, options: Options) -> (Window, err)
fn metrics(window: *const Window) -> (Metrics, err)
fn target(window: *const Window) -> (scene.Target, err)
fn title(window: *Window, value: str) -> err
fn cursor(window: *Window, value: Cursor) -> err
fn visible(window: *Window, value: bool) -> err
fn request_frame(window: *Window) -> err
fn clipboard_get(a: *mem.Arena, window: *Window) -> (str, err)
fn clipboard_set(window: *Window, value: str) -> err
fn close(window: *Window) -> err
```

Windows are logically linear handles backed only by reviewed `e.os` primitives.
Coordinates exposed above the module are logical pixels; framebuffer dimensions are
physical pixels. `target` is non-owning and becomes invalid when the window closes.

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
type Event = union enum u8 { Frame: window.Id, Close: window.Id, Resize: window.Metrics, Focus: window.Id, Blur: window.Id, PointerDown: Pointer, PointerUp: Pointer, PointerMove: Pointer, Scroll: Pointer, KeyDown: KeyEvent, KeyUp: KeyEvent, Text: TextEvent, Composition: Composition }
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

### `e.ui.widget`

```neper
type Key = u64
type ElementId = struct { slot: u32, generation: u32 }
type StateId = struct { slot: u32, generation: u32 }
type Action = struct { ctx: *void, invoke: fn(*void, input.Event) -> err }
type Text = struct { value: str, style: layout.Style, color: paint.Color }
type Button = struct { action: Action, enabled: bool }
type Image = struct { texture: scene.TextureId, fit: Fit }
type Scroll = struct { axis: ui_layout.Axis, offset: f32 }
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom }
type Node = struct { key: Key, kind: Kind, style: style.Style, children: []const Node }
type Fit = enum u8 { Fill, Contain, Cover, None }
type BuildContext = struct { runtime: *Runtime, element: ElementId, frame: u64 }
type Runtime = struct { state: *void }
type Limits = struct { max_elements: usize, max_states: usize, state_bytes: usize, state_classes: u16, max_depth: u16, max_commands: usize }
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
fn state[T: type](ctx: *BuildContext, key: Key, initial: T) -> (*T, StateId, err)
fn invalidate(widget_runtime: *Runtime, element: ElementId)
fn reconcile(widget_runtime: *Runtime, frame_arena: *mem.Arena, root: Node, constraints: ui_layout.Constraints) -> (scene.SceneId, err)
fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err
fn focus(widget_runtime: *Runtime, element: ElementId) -> err
fn close(widget_runtime: *Runtime) -> err
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
type Role = enum u8 { Application, Window, Group, Button, Checkbox, Radio, Text, TextField, Image, Link, List, ListItem, Table, Row, Cell, Slider, Progress, Scrollbar }
type State = struct { disabled: bool, focused: bool, selected: bool, checked: bool, expanded: bool, hidden: bool }
type Action = enum u8 { Focus, Press, Increment, Decrement, SetValue, Scroll }
type Node = struct { id: Id, role: Role, label: str, value: str, hint: str, state: State, bounds: geometry.Rect, actions: []const Action, children: []const Id }
type Tree = struct { root: Id, nodes: []const Node }
error Unsupported
error Invalid

fn build(a: *mem.Arena, runtime: *const widget.Runtime) -> (Tree, err)
fn publish(window_value: window.Id, tree: *const Tree) -> err
fn perform(runtime: *widget.Runtime, id: Id, action: Action, value: str) -> err
```

The semantics tree is separate from paint order but uses the same stable element
identities. Publication crosses a reviewed `e.os` accessibility bridge and retains
no caller strings after returning.

### `e.ui.testing`

```neper
type Harness = struct { state: *void }
type Match = struct { element: widget.ElementId, count: usize }
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
fn close(h: *Harness) -> err
```

The harness uses the deterministic CPU rendering backend and a synthetic window. It
does not require a display server and never sleeps; tests supply frame time.

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
