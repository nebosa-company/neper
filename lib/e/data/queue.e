// A first-in-first-out adapter over `e.data.deque`: enqueue at the back, dequeue at
// the front.

use e.mem
use e.data.deque as deque

type Queue[T: type] = struct { items: deque.Deque[T] }
type Iter[T: type] = struct { queue: *const Queue[T], index: usize }

fn init[T: type](a: *mem.Arena, capacity: usize) -> (Queue[T], err) {
    let (items, init_error) = deque.init[T](a, capacity)
    if init_error != ok { ret (zero, init_error) }
    ret (Queue[T] { items: items }, ok)
}

fn len[T: type](q: *const Queue[T]) -> usize { ret q.items.len }

fn reserve[T: type](q: *Queue[T], capacity: usize) -> err { ret deque.reserve[T](&q.items, capacity) }

fn enqueue[T: type](q: *Queue[T], value: own T) -> err { ret deque.push_back[T](&q.items, value) }

fn peek[T: type](q: *const Queue[T]) -> (T, bool) {
    if q.items.len == 0usize { ret (zero, false) }
    ret (deque.get[T](&q.items, 0usize), true)
}

fn dequeue[T: type](q: *Queue[T]) -> (T, bool) {
    let (value, has_value) = deque.pop_front[T](&q.items)
    ret (value, has_value)
}

fn clear[T: type](q: *Queue[T]) { deque.clear[T](&q.items) }

// FIFO order: the front first, and the queue itself is not touched.
fn iter[T: type](q: *const Queue[T]) -> Iter[T] {
    ret Iter[T] { queue: q, index: 0usize }
}

fn iter_next[T: type](it: *Iter[T]) -> (T, bool) {
    if it.index >= it.queue.items.len { ret (zero, false) }
    let value = deque.get[T](&it.queue.items, it.index)
    it.index += 1usize
    ret (value, true)
}
