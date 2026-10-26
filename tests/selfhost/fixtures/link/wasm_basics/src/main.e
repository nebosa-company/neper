// The WebAssembly target's first slice (C180, D5213): integers of every width, bool, err and
// pointers, calls with none, one and two results, frames, aggregates by value and by address,
// slices and strings, globals, the arena, and a program that returns an error. It writes a line
// per group to standard output and exits 0, on x64 and on wasm32-wasi alike, so the sweep
// (scripts/wasm-sweep.sh) compares the two byte for byte. With an argument it runs one of the
// checks that must trap -- `overflow`, `divide` or `insert` (an index past an array) -- and the
// trap's text and status are native's, less the frames WebAssembly cannot walk.
use e.mem
use e.os

type Point = struct { x: i64, y: i64, tag: u8 }
type Pack = struct { a: u16, b: bool, c: u32, d: u8 }

var counter: u64 = 7u64
var table: [4]i32 = zero
var scratch: [16]u8 = zero

error Broken
error Odd

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn digit_line(label: str, value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    if rest == 0usize {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest != 0usize {
        at -= 1usize
        digits[at] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
    }
    say(label)
    say(" ")
    let (shown, shown_error) = os.write(os.stdout(), digits[at..20usize])
    say("\n")
}

fn add(a: i64, b: i64) -> i64 { ret a + b }

fn divmod(a: i64, b: i64) -> (i64, i64) { ret (a / b, a % b) }

fn three(a: u8) -> (u8, bool, err) { ret (a +% 250u8, a > 5u8, ok) }

fn point_sum(p: Point) -> i64 { ret p.x + p.y + i64(p.tag) }

fn fill(p: *Point, v: i64) {
    p.x = v
    p.y = v * 2i64
    p.tag = u8(v)
}

fn make(v: i64) -> Point { ret Point { x: v, y: v + 1i64, tag: 3u8 } }

fn fib(n: u32) -> u32 {
    if n < 2u32 { ret n }
    ret fib(n - 1u32) + fib(n - 2u32)
}

fn fails(odd: bool) -> err {
    if odd { ret Odd }
    ret Broken
}

fn check_error() -> err {
    try fails(true)
    ret ok
}

fn sum_slice(items: []const u32) -> u32 {
    var total = 0u32
    var at = 0usize
    while at < items.len {
        total += items[at]
        at += 1usize
    }
    ret total
}

fn widths() -> usize {
    var failed = 0usize
    let a: u8 = 200u8
    let b: u8 = 100u8
    if a +% b != 44u8 { failed += 1usize }
    if b -% a != 156u8 { failed += 1usize }
    if a *% b != 32u8 { failed += 1usize }
    let c: i8 = -100i8
    if c -% 100i8 != 56i8 { failed += 1usize }
    if i32(c) != -100i32 { failed += 1usize }
    let d: i16 = -30000i16
    if d +% d != 5536i16 { failed += 1usize }
    let e: u32 = 4000000000u32
    if e +% e != 3705032704u32 { failed += 1usize }
    if (e >> 4u32) != 250000000u32 { failed += 1usize }
    let f: i64 = -9223372036854775807i64
    if f - 1i64 != -9223372036854775807i64 - 1i64 { failed += 1usize }
    if (f >> 60u32) != -8i64 { failed += 1usize }
    let g: u64 = 18446744073709551615u64
    if g / 3u64 != 6148914691236517205u64 { failed += 1usize }
    if g % 10u64 != 5u64 { failed += 1usize }
    if (g << 63u32) != 9223372036854775808u64 { failed += 1usize }
    if (-7i32 / 2i32) != -3i32 || (-7i32 % 2i32) != -1i32 { failed += 1usize }
    if (0xF0u8 & 0x3Cu8) != 0x30u8 || (0xF0u8 | 0x0Fu8) != 0xFFu8 || (0xF0u8 ^ 0xFFu8) != 0x0Fu8 { failed += 1usize }
    if ~0x0Fu8 != 0xF0u8 { failed += 1usize }
    if -(5i16) != -5i16 { failed += 1usize }
    if u16(300u32) != 300u16 || i8(-5i32) != -5i8 { failed += 1usize }
    ret failed
}

fn aggregates() -> usize {
    var failed = 0usize
    var p = Point { x: 1i64, y: 2i64, tag: 3u8 }
    if point_sum(p) != 6i64 { failed += 1usize }
    fill(&p, 10i64)
    if p.x != 10i64 || p.y != 20i64 || p.tag != 10u8 { failed += 1usize }
    let q = make(5i64)
    var r = q
    r.x = 99i64
    if q.x != 5i64 || r.x != 99i64 || r.y != 6i64 || r.tag != 3u8 { failed += 1usize }
    let pack = Pack { a: 65535u16, b: true, c: 70000u32, d: 9u8 }
    var blank: Pack = zero
    if blank.a != 0u16 || blank.b || blank.c != 0u32 { failed += 1usize }
    blank = pack
    if blank.a != 65535u16 || !blank.b || blank.c != 70000u32 || blank.d != 9u8 { failed += 1usize }
    var values: [5]u32 = zero
    var at = 0usize
    while at < values.len {
        values[at] = u32(at * at)
        at += 1usize
    }
    if sum_slice(values[1usize..4usize]) != 14u32 { failed += 1usize }
    if sum_slice(values[..]) != 30u32 { failed += 1usize }
    ret failed
}

fn calls() -> usize {
    var failed = 0usize
    if add(40i64, 2i64) != 42i64 { failed += 1usize }
    let (quotient, remainder) = divmod(-17i64, 5i64)
    if quotient != -3i64 || remainder != -2i64 { failed += 1usize }
    let (wrapped, bigger, fine) = three(9u8)
    if wrapped != 3u8 || !bigger || fine != ok { failed += 1usize }
    if fib(15u32) != 610u32 { failed += 1usize }
    if check_error() != Odd { failed += 1usize }
    if fails(false) != Broken { failed += 1usize }
    ret failed
}

fn strings_and_globals() -> usize {
    var failed = 0usize
    let word = "wasm"
    if word.len != 4usize || word[0usize] != 119u8 || word[3usize] != 109u8 { failed += 1usize }
    let tail = word[1usize..3usize]
    if tail.len != 2usize || tail[0usize] != 97u8 { failed += 1usize }
    counter += 5u64
    table[2usize] = -9i32
    table[3usize] = table[2usize] * 2i32
    scratch[15usize] = 255u8
    if counter != 12u64 || table[3usize] != -18i32 || table[0usize] != 0i32 || scratch[15usize] != 255u8 { failed += 1usize }
    ret failed
}

fn arena_work(a: *mem.Arena) -> usize {
    var failed = 0usize
    let (numbers, numbers_error) = mem.alloc[u64](a, 1000usize)
    if numbers_error != ok { ret 1usize }
    var at = 0usize
    while at < numbers.len {
        numbers[at] = u64(at) * 3u64
        at += 1usize
    }
    var total = 0u64
    at = 0usize
    while at < numbers.len {
        total += numbers[at]
        at += 1usize
    }
    if total != 1498500u64 { failed += 1usize }
    let mark = mem.mark(a)
    let (more, more_error) = mem.alloc[u8](a, 4096usize)
    if more_error != ok { ret failed + 1usize }
    more[4095usize] = 1u8
    mem.reset(a, mark)
    if mem.mark(a) != mark { failed += 1usize }
    ret failed
}

fn trap_case(name: str) -> usize {
    var zero_divisor = 0i64
    var small: u8 = 250u8
    var items: [3]u8 = zero
    if name.len == 8usize && name[0usize] == 111u8 {
        small = small + 10u8
        ret usize(small)
    }
    if name.len == 6usize && name[0usize] == 100u8 {
        ret usize(10i64 / zero_divisor)
    }
    if name.len == 6usize && name[0usize] == 105u8 {
        ret usize(items[name.len])
    }
    ret 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let trapped = trap_case(args[1usize])
        ret ok
    }
    var failed = 0usize
    say("wasm_basics\n")
    let wide = widths()
    digit_line("widths", wide)
    let shapes = aggregates()
    digit_line("aggregates", shapes)
    let called = calls()
    digit_line("calls", called)
    let strung = strings_and_globals()
    digit_line("strings", strung)
    let arena_failed = arena_work(a)
    digit_line("arena", arena_failed)
    failed = wide + shapes + called + strung + arena_failed
    if failed != 0usize { ret Broken }
    say("ok\n")
    ret ok
}
