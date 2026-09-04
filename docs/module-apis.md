# neper module API catalogue

Status: exact public-surface proposal for the toolchain modules in `modules.md`.
Implementation has not started. Semantic details already fixed by `spec.md` remain
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
`linalg_tensor`, the explicit alias for `algo.linalg.tensor`; imports themselves are
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
fn copy[T: type](dst: []T, src: []const T)
fn eq[T: type](x: []const T, y: []const T) -> bool
fn cast[P: type, Q: type](p: Q) -> P
fn bitcast[T: type, U: type](x: U) -> T
fn size_of[T: type]() -> usize
fn align_of[T: type]() -> usize
fn stats(a: *const Arena) -> Stats
```

For `cast`, `P` and `Q` must be pointer types; callers spell `P` and inference fills
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
```

Generic numeric operations accept integer and float primitives only; bit operations
accept unsigned integers only.

### `e.str`

```neper
type Sink = struct { ctx: *void, write: fn(ctx: *void, bytes: []const u8) -> err }
type Builder = struct { arena: *mem.Arena, start: usize, len: usize, reserved: usize, sink: Sink, flushing: bool }
error NotOnTop
error BadNumber

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
fn relative(a: *mem.Arena, base: str, target: str, style: Style) -> (str, err)
fn replace_extension(a: *mem.Arena, path: str, ext: str, style: Style) -> (str, err)
```

---

## 3. Containers and traversal

### `e.data.list`

```neper
type List[T: type] = struct { items: []T, len: usize, arena: *mem.Arena }

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
```

### `e.data.deque`

```neper
type Deque[T: type] = struct { items: []T, head: usize, len: usize, arena: *mem.Arena }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Deque[T], err)
fn len[T: type](d: *const Deque[T]) -> usize
fn reserve[T: type](d: *Deque[T], capacity: usize) -> err
fn push_front[T: type](d: *Deque[T], v: T) -> err
fn push_back[T: type](d: *Deque[T], v: T) -> err
fn pop_front[T: type](d: *Deque[T]) -> (T, bool)
fn pop_back[T: type](d: *Deque[T]) -> (T, bool)
fn get[T: type](d: *const Deque[T], index: usize) -> T
fn clear[T: type](d: *Deque[T])
```

### `e.data.ring`

```neper
type Ring[T: type] = struct { items: []T, head: usize, len: usize }

fn init[T: type](storage: []T) -> Ring[T]
fn len[T: type](r: *const Ring[T]) -> usize
fn capacity[T: type](r: *const Ring[T]) -> usize
fn push[T: type](r: *Ring[T], v: T) -> bool
fn push_overwrite[T: type](r: *Ring[T], v: T) -> (T, bool)
fn pop[T: type](r: *Ring[T]) -> (T, bool)
fn peek[T: type](r: *const Ring[T]) -> (T, bool)
fn clear[T: type](r: *Ring[T])
```

### `e.data.map`

```neper
type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }

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
```

### `e.data.sort`

```neper
fn in_place[T: type](items: []T)
fn in_place_by[T: type, Ctx: type](items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32)
fn stable_in_place[T: type](a: *mem.Arena, items: []T) -> err
fn stable_in_place_by[T: type, Ctx: type](a: *mem.Arena, items: []T, ctx: *Ctx, cmp: fn(*Ctx, T, T) -> i32) -> err
fn radix_u32_in_place(a: *mem.Arena, items: []u32) -> err
fn radix_u64_in_place(a: *mem.Arena, items: []u64) -> err
fn is_sorted[T: type](items: []const T) -> bool
```

### `e.data.heap`

```neper
type Heap[T: type] = struct { items: list.List[T] }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Heap[T], err)
fn len[T: type](h: *const Heap[T]) -> usize
fn push[T: type](h: *Heap[T], v: T) -> err
fn peek[T: type](h: *const Heap[T]) -> (T, bool)
fn pop[T: type](h: *Heap[T]) -> (T, bool)
fn clear[T: type](h: *Heap[T])
```

### `e.data.tree`

```neper
type Map[K: type, V: type] = struct { state: *void }
type Set[K: type] = struct { map: Map[K, bool] }

fn init[K: type, V: type](a: *mem.Arena) -> Map[K, V]
fn len[K: type, V: type](m: *const Map[K, V]) -> usize
fn put[K: type, V: type](m: *Map[K, V], key: K, value: V) -> (bool, err)
fn get[K: type, V: type](m: *const Map[K, V], key: K) -> (V, bool)
fn lower_bound[K: type, V: type](m: *const Map[K, V], key: K) -> (K, V, bool)
fn remove[K: type, V: type](m: *Map[K, V], key: K) -> (V, bool)
fn clear[K: type, V: type](m: *Map[K, V])
fn set_init[K: type](a: *mem.Arena) -> Set[K]
fn set_add[K: type](s: *Set[K], key: K) -> (bool, err)
fn set_has[K: type](s: *const Set[K], key: K) -> bool
fn set_remove[K: type](s: *Set[K], key: K) -> bool
```

### `e.data.iter`

```neper
type Map[I: type, T: type, U: type] = struct { it: I, f: fn(T) -> U }
type MapCtx[I: type, T: type, U: type, Ctx: type] = struct { it: I, ctx: *Ctx, f: fn(*Ctx, T) -> U }
type Filter[I: type, T: type] = struct { it: I, pred: fn(T) -> bool }
type FilterCtx[I: type, T: type, Ctx: type] = struct { it: I, ctx: *Ctx, pred: fn(*Ctx, T) -> bool }
type Take[T: type, I: type] = struct { it: I, remaining: usize }
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
```

`take[T](it, n)` and `zip[X, Y](left, right)` write the item type(s) explicitly;
their trailing iterator types are structurally inferred. Other adapters infer their
item types from the callback signatures. No return-context inference is required.

---

## 4. Pure algorithms, text and cryptography

### `algo.rand`

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

### `algo.uuid`

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

### `algo.hash`

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

### `algo.stat`

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

### `algo.bignum`

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

### `algo.linalg.matrix`

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

### `algo.linalg.tensor`

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

### `text.utf8`

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

### `text.unicode`

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

### `text.normalize`

```neper
type Form = enum u8 { Nfc, Nfd, Nfkc, Nfkd }
error Invalid

fn is_normalized(s: str, form: Form) -> (bool, err)
fn normalize(a: *mem.Arena, s: str, form: Form) -> (str, err)
```

### `text.collate`

```neper
type Options = struct { case_sensitive: bool, numeric: bool }

fn codepoint_cmp(a: str, b: str) -> i32
fn natural_cmp(a: str, b: str, options: Options) -> i32
```

Locale-aware collation is deliberately absent and belongs to `x.neper.locale`.

### `text.regex`

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

### `crypto.hash`

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

### `crypto.aead`

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

### `crypto.sign`

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

### `crypto.kx`

```neper
type X25519PublicKey = struct { bytes: [32]u8 }
type X25519SecretKey = struct { bytes: [32]u8 }
type X25519SharedKey = struct { bytes: [32]u8 }
error InvalidKey

fn x25519_public_from_secret(secret: X25519SecretKey) -> X25519PublicKey
fn x25519_exchange(secret: X25519SecretKey, peer: X25519PublicKey) -> (X25519SharedKey, err)
```

The scalar is clamped by the operation. An all-zero shared secret is `InvalidKey`.

### `crypto.random`

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
type Clock = enum u8 { Wall, Monotonic }
type SeekWhence = enum u8 { Start, Current, End }
type EntryKind = enum u8 { File, Dir, Symlink, Other }
type DirEntry = struct { name: str, kind: EntryKind }
type FileInfo = struct { kind: EntryKind, size: u64 }
type OpenFlags = struct { read: bool, write: bool, create: bool, truncate: bool, append: bool }
type Stdio = struct { stdin: File, stdout: File, stderr: File, inherit: []const Handle }
type SpawnOptions = struct { argv: []const str, env: []const str, inherit_env: bool, cwd: str, stdio: Stdio }
type SocketFamily = enum u8 { Ip4, Ip6 }
type SocketKind = enum u8 { Stream, Datagram }
type SocketShutdown = enum u8 { Read, Write, Both }
type SocketAddress = struct { family: SocketFamily, bytes: [16]u8, scope: u32, port: u16 }
type PollInterest = struct { readable: bool, writable: bool }
type PollEvent = struct { token: usize, readable: bool, writable: bool, closed: bool, failed: bool }
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
fn dlopen(a: *mem.Arena, name: str) -> (Lib, err)
fn dlsym[F: type](a: *mem.Arena, l: Lib, sym: str) -> (F, err)
fn dlclose(l: Lib) -> err
fn last_error() -> i32
```

All path strings use the host convention. `SpawnOptions.cwd == ""` inherits the
current directory; `inherit_env` controls whether `env` overlays the parent
environment (`true`) or is the complete child environment (`false`). Environment
entries are `NAME=VALUE`. `wait_u32` waits indefinitely when `timeout_ns < 0` and
polls once when it is zero. In `SocketAddress`, IPv4 uses the first four bytes and
zeros the remaining twelve. Pollers retain handles, interests and numeric tokens,
never callbacks; callers unregister a handle before closing it.

### `e.io`

```neper
type Reader = struct { ctx: *void, read: fn(*void, []u8) -> (usize, err) }
type Writer = struct { ctx: *void, write: fn(*void, []const u8) -> (usize, err) }
type SliceReader = struct { data: []const u8, off: usize }
type SliceWriter = struct { data: []u8, off: usize }
type BufferedReader = struct { state: *void }
type BufferedWriter = struct { state: *void }
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
fn read(r: *Reader, dst: []u8) -> (usize, err)
fn read_exact(r: *Reader, dst: []u8) -> err
fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> ([]u8, err)
fn read_until(a: *mem.Arena, r: *Reader, delimiter: u8, limit: usize) -> ([]u8, err)
fn write(w: *Writer, src: []const u8) -> (usize, err)
fn write_all(w: *Writer, src: []const u8) -> err
fn flush(w: *Writer) -> err
fn copy(dst: *Writer, src: *Reader, scratch: []u8) -> (u64, err)
fn print(s: str) -> err
fn printf[FMT: str](args: ...) -> err
```

`limit` is a hard maximum; crossing it returns `TooSmall` without retaining a partial
result. A callback returning `(0, ok)` for a non-empty request returns `NoProgress`.

### `e.fs`

```neper
type EntryKind = enum u8 { File, Directory, Symlink, Other }
type Entry = struct { path: str, kind: EntryKind, size: u64 }
type Walk = struct { state: *void }
type WalkOptions = struct { recursive: bool, follow_symlinks: bool }
error NotFound
error Exists
error Denied
error Invalid
error Io

fn exists(a: *mem.Arena, path: str) -> (bool, err)
fn stat(a: *mem.Arena, path: str) -> (Entry, err)
fn make_dir(a: *mem.Arena, path: str) -> err
fn make_dirs(a: *mem.Arena, path: str) -> err
fn remove_file(a: *mem.Arena, path: str) -> err
fn remove_dir(a: *mem.Arena, path: str) -> err
fn copy_file(a: *mem.Arena, src: str, dst: str, scratch: []u8) -> err
fn move(a: *mem.Arena, src: str, dst: str) -> err
fn read_file(a: *mem.Arena, path: str, limit: usize) -> ([]u8, err)
fn write_file(a: *mem.Arena, path: str, data: []const u8) -> err
fn walk(a: *mem.Arena, root: str, options: WalkOptions) -> (Walk, err)
fn walk_next_err(it: *Walk) -> (Entry, bool, err)
```

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
```

An empty `cwd` inherits the parent directory. `inherit_env` has the same overlay vs
replacement meaning as `os.SpawnOptions`; environment entries are `NAME=VALUE`.

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
error Invalid

fn mutex() -> Mutex
fn mutex_lock(m: *Mutex)
fn mutex_try_lock(m: *Mutex) -> bool
fn mutex_unlock(m: *Mutex)
fn rwlock() -> RwLock
fn rwlock_read_lock(l: *RwLock)
fn rwlock_try_read_lock(l: *RwLock) -> bool
fn rwlock_read_unlock(l: *RwLock)
fn rwlock_write_lock(l: *RwLock)
fn rwlock_try_write_lock(l: *RwLock) -> bool
fn rwlock_write_unlock(l: *RwLock)
fn condition() -> Condition
fn condition_wait(c: *Condition, m: *Mutex)
fn condition_signal(c: *Condition)
fn condition_broadcast(c: *Condition)
fn semaphore(initial: u32) -> Semaphore
fn semaphore_wait(s: *Semaphore)
fn semaphore_try_wait(s: *Semaphore) -> bool
fn semaphore_post(s: *Semaphore, count: u32) -> err
```

All waits recheck their state after `os.wait_u32`, so spurious wakes are invisible to
callers. `semaphore_post` returns `Invalid` instead of wrapping the count.

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

---

## 6. Language-owned runtimes

### `e.gpu`

```neper
type Backend = enum u8 { Cpu, Vulkan, Cuda }
type Device = struct { state: *void }
type Queue = struct { state: *void }
type Buf[T: type] = struct { owner: u32, slot: u32, generation: u32, len: usize }
type Grid = struct { x: usize, y: usize, z: usize }
type Id = struct { x: u32, y: u32, z: u32 }
type Cap = enum u8 { Int8, Int16, Int64, Float16, Float64, Atomic64, Subgroup, Ftz, DenormPreserve }
type Scope = enum u8 { Workgroup, Device }
error NoDevice
error Unsupported
error OutOfMemory
error TooLarge
error Lost
error WrongDevice
error InvalidHandle

fn open(a: *mem.Arena, backend: Backend, index: u32) -> (*Device, err)
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
fn release[T: type](queue: *gpu.Queue, tensor: Tensor[T]) -> err
```

The import of `algo.linalg.tensor` uses the deterministic alias `linalg_tensor`.
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
```

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
fn header(headers: []const Header, name: str) -> (str, bool)
fn reason(status: u16) -> str
```

Chunked transfer encoding is supported. Automatic redirects, cookies, compression,
TLS and connection pooling are deliberately outside this module.

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
fn client_upgrade(a: *mem.Arena, stream: io.Reader, sink: io.Writer, host: str, target: str, entropy: [16]u8) -> (Connection, err)
fn server_upgrade(a: *mem.Arena, stream: io.Reader, sink: io.Writer, request: *const http.Request) -> (Connection, err)
fn receive(a: *mem.Arena, connection: *Connection, limit: usize) -> (Frame, err)
fn send(connection: *Connection, frame: Frame, mask: [4]u8) -> err
fn ping(connection: *Connection, payload: []const u8, mask: [4]u8) -> err
fn close(connection: *Connection, code: u16, reason: str, mask: [4]u8) -> err
```

Client masking material and handshake entropy are caller-supplied. The module never
reads OS randomness implicitly.

---

## 8. Interchange formats

All document decoders allocate retained strings and nodes in the arena passed to the
call. Streaming readers retain only their documented scratch state. Every writer uses
`io.Writer`; no format module opens files.

### `fmt.json`

```neper
type Member = struct { key: str, value: Value }
type Value = union enum u8 { Null, Bool: bool, Number: f64, String: str, Array: []const Value, Object: []const Member }
type Event = union enum u8 { Null, Bool: bool, Number: f64, String: str, Key: str, BeginArray, EndArray, BeginObject, EndObject }
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
```

Numbers use finite `f64`; overflow and non-finite output are `Invalid`. `encode` and
`decode` use the structural subset and type-owned protocols from spec §9.

### `fmt.csv`

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

### `fmt.ini`

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

### `fmt.yaml`

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

### `fmt.xml`

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

### `fmt.bson`

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

### `fmt.msgpack`

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

### `fmt.protobuf`

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

## 9. External packages

The `x.*` rows in `modules.md` are package reservations, not modules with invented
surfaces. Each package must publish its own file in `docs/packages/<owner>/<package>.md`
before implementation. That specification pins the upstream ABI/data version and
lists every public declaration using the same format as this catalogue. Until such a
file exists, the package has exactly zero promised functions and structures.
