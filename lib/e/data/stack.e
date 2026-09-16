// A last-in-first-out adapter over `e.data.list`: the list's end is the top.

use e.mem
use e.data.list as list

type Stack[T: type] = struct { items: list.List[T] }
type Iter[T: type] = struct { stack: *const Stack[T], remaining: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Stack[T], err) {
    let (items, init_error) = list.init[T](a, capacity)
    if init_error != ok { ret (zero, init_error) }
    ret (Stack[T] { items: items }, ok)
}

fn len[T: type](s: *const Stack[T]) -> usize { ret s.items.len }

fn reserve[T: type](s: *Stack[T], capacity: usize) -> err { ret list.reserve[T](&s.items, capacity) }

fn push[T: type](s: *Stack[T], value: own T) -> err { ret list.push[T](&s.items, value) }

fn peek[T: type](s: *const Stack[T]) -> (T, bool) {
    if s.items.len == 0usize { ret (zero, false) }
    ret (s.items.items[s.items.len - 1usize], true)
}

fn pop[T: type](s: *Stack[T]) -> (T, bool) {
    let (value, has_value) = list.pop[T](&s.items)
    ret (value, has_value)
}

fn clear[T: type](s: *Stack[T]) { list.clear[T](&s.items) }

// LIFO order: the top first, and the stack itself is not touched.
fn iter[T: type](s: *const Stack[T]) -> Iter[T] {
    ret Iter[T] { stack: s, remaining: s.items.len }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.remaining == 0usize { ret (zero, false) }
    it.remaining -= 1usize
    ret (it.stack.items.items[it.remaining], true)
}
