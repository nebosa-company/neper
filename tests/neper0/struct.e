use e.mem
use e.io

type Pair = struct {
    small: u8,
    total: i64,
    name: str,
}

type Link = struct {
    next: *Link,
    value: u64,
}

type Wrapper = struct {
    pair: Pair,
    mark: u8,
}

fn bump(pair: *Pair) {
    pair.small = 9u8
    pair.total += 1i64
}

fn read(pair: *const Pair) -> i64 {
    ret pair.total
}

fn set(value: *u64) {
    *value = 7u64
    *value += 2u64
}

fn set_indirect(value: **u64) {
    **value = 11u64
}

fn main(a: *mem.Arena, args: []str) -> err {
    var pair = Pair{ name: "struct ok\n", total: 41i64, small: 3u8 }
    bump(&pair)
    let observed = *(&pair.total)
    var scalar: u64 = 1u64
    set(&scalar)
    var scalar_pointer = &scalar
    set(&*scalar_pointer)
    set_indirect(&scalar_pointer)
    var blank: Pair = zero
    var tail: Link = undef
    tail.next = &tail
    tail.value = 5u64
    var head = Link{ value: 1u64, next: &tail }
    head.next.next.value += 2u64
    var wrapped = Wrapper{ mark: 6u8, pair: Pair{ small: 4u8, total: 8i64, name: "nested" } }
    if pair.small == 9u8 && read(&pair) == 42i64 && observed == 42i64 && scalar == 11u64 && blank.small == 0u8 && blank.total == 0i64 && blank.name.len == 0usize && tail.value == 7u64 && wrapped.pair.total == 8i64 && wrapped.pair.name.len == 6usize && wrapped.mark == 6u8 {
        try io.print(pair.name)
    } else {
        try io.print("struct failed\n")
    }
    ret ok
}
