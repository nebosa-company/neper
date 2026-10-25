// The seven instructions the pseudo-library "wasm" gains for threads (D5672, C186), run on one
// thread: `threads` and `thread.id` differ between a plain and a `--threads` module, a spawn
// is refused by a plain module (-1; only that one tries, since the thread host of a threaded
// one would start a real thread on the record), and the atomics on a word work in both shapes.
// `wait32` runs only where `threads` says the memory is shared. This fixture is wasm-only, so it
// is outside link/ and the sweep; the wasm block of run.sh builds it both ways and compares.
use e.mem
use e.os

@import("wasm", "threads")
extern fn wasm_threads() -> u32

@import("wasm", "thread.id")
extern fn wasm_thread_id() -> u32

@import("wasm", "thread.spawn")
extern fn wasm_thread_spawn(record: u32) -> i32

@import("wasm", "memory.atomic.wait32")
extern fn wasm_wait32(address: u32, expected: u32, timeout_ns: i64) -> u32

@import("wasm", "memory.atomic.notify")
extern fn wasm_notify(address: u32, count: u32) -> u32

@import("wasm", "i32.atomic.rmw.cmpxchg")
extern fn wasm_cas32(address: u32, expected: u32, replacement: u32) -> u32

@import("wasm", "i32.atomic.load")
extern fn wasm_load32(address: u32) -> u32

@import("wasm", "i32.atomic.store")
extern fn wasm_store32(address: u32, value: u32)

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(label: str, value: i64) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    if value < 0i64 { rest = 0i64 - value }
    if rest == 0i64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest != 0i64 {
        at -= 1usize
        digits[at] = u8(48i64 + rest % 10i64)
        rest = rest / 10i64
    }
    say(label)
    say(" ")
    if value < 0i64 { say("-") }
    let (written, write_error) = os.write(os.stdout(), digits[at..20usize])
    say("\n")
}

fn main() -> err {
    var word: [1]u32 = zero
    let address = u32(mem.address_of(&word[0usize]))
    number("threads", i64(wasm_threads()))
    number("thread.id", i64(wasm_thread_id()))
    if wasm_threads() == 0u32 { number("spawn", i64(wasm_thread_spawn(0u32))) }
    wasm_store32(address, 7u32)
    number("load", i64(wasm_load32(address)))
    number("cas hit", i64(wasm_cas32(address, 7u32, 4000000000u32)))
    number("load", i64(wasm_load32(address)))
    number("cas miss", i64(wasm_cas32(address, 7u32, 11u32)))
    number("load", i64(wasm_load32(address)))
    number("notify", i64(wasm_notify(address, 1u32)))
    if wasm_threads() == 1u32 {
        number("wait different", i64(wasm_wait32(address, 7u32, 0i64 - 1i64)))
        number("wait timeout", i64(wasm_wait32(address, 4000000000u32, 1000000i64)))
    }
    ret ok
}
