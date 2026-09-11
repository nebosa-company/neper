// Adapters over any iterator, and the folds that consume one. An iterator is whatever has a
// `next` -- `I.next(&it)` answering `(T, bool)` -- which every container in `lib/e` gives its
// `Iter` and every adapter here gives itself, so adapters stack: a `Filter` over a `Map` over a
// list's `Iter` is one value, and pulling from it pulls through all three.
//
// The adapters are lazy and allocate nothing: each holds its source by value and a callback,
// and does its work in `_next`. The folds -- `reduce`, `find`, `count`, `collect` and the rest
// -- take the source by pointer and run it to its end, or to the first answer. Only `collect`
// and `partition` allocate, and they say so by taking an arena.
//
// The `try_` family is the same over `next_err`, which answers `(T, bool, err)`: a source or a
// callback that fails ends the adapter, and every call after that is no item and `ok` -- the
// error is reported once, where it happened, and not again on every pull that follows.

use e.data.list
use e.mem

type Map[I: type, T: type, U: type] = struct { it: I, f: fn(T) -> U }
type MapCtx[I: type, T: type, U: type, Ctx: type] = struct { it: I, ctx: *Ctx, f: fn(*Ctx, T) -> U }
type Filter[I: type, T: type] = struct { it: I, pred: fn(T) -> bool }
type FilterCtx[I: type, T: type, Ctx: type] = struct { it: I, ctx: *Ctx, pred: fn(*Ctx, T) -> bool }
type Take[T: type, I: type] = struct { it: I, remaining: usize }
type Skip[T: type, I: type] = struct { it: I, remaining: usize }
type Enumerate[T: type, I: type] = struct { it: I, index: usize }
type Chain[T: type, A: type, B: type] = struct { left: A, right: B, left_done: bool }
type Zip[X: type, Y: type, A: type, B: type] = struct { left: A, right: B }
type TryMap[I: type, T: type, U: type, Ctx: type] = struct { it: *I, ctx: *Ctx, f: fn(*Ctx, T) -> (U, err), ended: bool }
type TryFilter[I: type, T: type, Ctx: type] = struct { it: *I, ctx: *Ctx, pred: fn(*Ctx, T) -> (bool, err), ended: bool }

fn map[I: type, T: type, U: type](it: I, f: fn(T) -> U) -> Map[I, T, U] {
    ret Map[I, T, U] { it: it, f: f }
}

fn map_next[I: type, T: type, U: type](it: *Map[I, T, U]) -> (U, bool) {
    let (value, more) = I.next(&it.it)
    if !more { ret (zero, false) }
    ret (it.f(value), true)
}

fn map_ctx[I: type, T: type, U: type, Ctx: type](it: I, ctx: *Ctx, f: fn(*Ctx, T) -> U) -> MapCtx[I, T, U, Ctx] {
    ret MapCtx[I, T, U, Ctx] { it: it, ctx: ctx, f: f }
}

fn map_ctx_next[I: type, T: type, U: type, Ctx: type](it: *MapCtx[I, T, U, Ctx]) -> (U, bool) {
    let (value, more) = I.next(&it.it)
    if !more { ret (zero, false) }
    ret (it.f(it.ctx, value), true)
}

fn filter[I: type, T: type](it: I, pred: fn(T) -> bool) -> Filter[I, T] {
    ret Filter[I, T] { it: it, pred: pred }
}

fn filter_next[I: type, T: type](it: *Filter[I, T]) -> (T, bool) {
    while true {
        let (value, more) = I.next(&it.it)
        if !more { ret (zero, false) }
        if it.pred(value) { ret (value, true) }
    }
    ret (zero, false)
}

fn filter_ctx[I: type, T: type, Ctx: type](it: I, ctx: *Ctx, pred: fn(*Ctx, T) -> bool) -> FilterCtx[I, T, Ctx] {
    ret FilterCtx[I, T, Ctx] { it: it, ctx: ctx, pred: pred }
}

fn filter_ctx_next[I: type, T: type, Ctx: type](it: *FilterCtx[I, T, Ctx]) -> (T, bool) {
    while true {
        let (value, more) = I.next(&it.it)
        if !more { ret (zero, false) }
        if it.pred(it.ctx, value) { ret (value, true) }
    }
    ret (zero, false)
}

fn take[T: type, I: type](it: I, n: usize) -> Take[T, I] {
    ret Take[T, I] { it: it, remaining: n }
}

// The source is not pulled past the count: a `take` of three from something that would block
// on its fourth item never asks for it.
fn take_next[T: type, I: type](it: *Take[T, I]) -> (T, bool) {
    if it.remaining == 0usize { ret (zero, false) }
    let (value, more) = I.next(&it.it)
    if !more {
        it.remaining = 0usize
        ret (zero, false)
    }
    it.remaining -= 1usize
    ret (value, true)
}

fn skip[T: type, I: type](it: I, n: usize) -> Skip[T, I] {
    ret Skip[T, I] { it: it, remaining: n }
}

fn skip_next[T: type, I: type](it: *Skip[T, I]) -> (T, bool) {
    while it.remaining != 0usize {
        let (dropped, more) = I.next(&it.it)
        if !more {
            it.remaining = 0usize
            ret (zero, false)
        }
        it.remaining -= 1usize
    }
    let (value, more) = I.next(&it.it)
    if !more { ret (zero, false) }
    ret (value, true)
}

fn enumerate[T: type, I: type](it: I) -> Enumerate[T, I] {
    ret Enumerate[T, I] { it: it, index: 0usize }
}

fn enumerate_next[T: type, I: type](it: *Enumerate[T, I]) -> (usize, T, bool) {
    let (value, more) = I.next(&it.it)
    if !more { ret (0usize, zero, false) }
    let index = it.index
    it.index += 1usize
    ret (index, value, true)
}

fn chain[T: type, A: type, B: type](left: A, right: B) -> Chain[T, A, B] {
    ret Chain[T, A, B] { left: left, right: right, left_done: false }
}

fn chain_next[T: type, A: type, B: type](it: *Chain[T, A, B]) -> (T, bool) {
    if !it.left_done {
        let (value, more) = A.next(&it.left)
        if more { ret (value, true) }
        it.left_done = true
    }
    let (value, more) = B.next(&it.right)
    if !more { ret (zero, false) }
    ret (value, true)
}

fn zip[X: type, Y: type, A: type, B: type](left: A, right: B) -> Zip[X, Y, A, B] {
    ret Zip[X, Y, A, B] { left: left, right: right }
}

// Ends with the shorter side. The left is pulled first, so when the left is the shorter the
// right is never asked for the item it would have paired.
fn zip_next[X: type, Y: type, A: type, B: type](it: *Zip[X, Y, A, B]) -> (X, Y, bool) {
    let (left, left_more) = A.next(&it.left)
    if !left_more { ret (zero, zero, false) }
    let (right, right_more) = B.next(&it.right)
    if !right_more { ret (zero, zero, false) }
    ret (left, right, true)
}

fn reduce[I: type, T: type, U: type](it: *I, initial: U, f: fn(U, T) -> U) -> U {
    var accumulator = initial
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        accumulator = f(accumulator, value)
    }
    ret accumulator
}

fn reduce_ctx[I: type, T: type, U: type, Ctx: type](it: *I, initial: U, ctx: *Ctx, f: fn(*Ctx, U, T) -> U) -> U {
    var accumulator = initial
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        accumulator = f(ctx, accumulator, value)
    }
    ret accumulator
}

// The folds that stop early leave the source just past the item that answered, which is what
// lets a caller find the first and then go on from there.
fn find[I: type, T: type](it: *I, pred: fn(T) -> bool) -> (T, bool) {
    while true {
        let (value, more) = I.next(it)
        if !more { ret (zero, false) }
        if pred(value) { ret (value, true) }
    }
    ret (zero, false)
}

fn position[I: type, T: type](it: *I, pred: fn(T) -> bool) -> (usize, bool) {
    var index = 0usize
    while true {
        let (value, more) = I.next(it)
        if !more { ret (0usize, false) }
        if pred(value) { ret (index, true) }
        index += 1usize
    }
    ret (0usize, false)
}

fn any[I: type, T: type](it: *I, pred: fn(T) -> bool) -> bool {
    while true {
        let (value, more) = I.next(it)
        if !more { ret false }
        if pred(value) { ret true }
    }
    ret false
}

fn all[I: type, T: type](it: *I, pred: fn(T) -> bool) -> bool {
    while true {
        let (value, more) = I.next(it)
        if !more { ret true }
        if !pred(value) { ret false }
    }
    ret true
}

fn count[I: type, T: type](it: *I) -> usize {
    var total = 0usize
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        total += 1usize
    }
    ret total
}

// `min` and `max` order by the item's own `cmp`, and the first of equals wins in both -- so a
// stable source gives a stable answer.
fn min[I: type, T: type](it: *I) -> (T, bool) {
    let (first, has_first) = I.next(it)
    if !has_first { ret (zero, false) }
    var best = first
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        if T.cmp(value, best) < 0i32 { best = value }
    }
    ret (best, true)
}

fn max[I: type, T: type](it: *I) -> (T, bool) {
    let (first, has_first) = I.next(it)
    if !has_first { ret (zero, false) }
    var best = first
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        if T.cmp(value, best) > 0i32 { best = value }
    }
    ret (best, true)
}

fn collect[I: type, T: type](a: *mem.Arena, it: *I) -> (list.List[T], err) {
    let (held, init_error) = list.init[T](a, 0usize)
    if init_error != ok { ret (zero, init_error) }
    var result = held
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        let push_error = list.push[T](&result, value)
        if push_error != ok { ret (zero, push_error) }
    }
    ret (result, ok)
}

fn partition[I: type, T: type](a: *mem.Arena, it: *I, pred: fn(T) -> bool) -> (list.List[T], list.List[T], err) {
    let (accepted_list, accepted_error) = list.init[T](a, 0usize)
    if accepted_error != ok { ret (zero, zero, accepted_error) }
    let (rejected_list, rejected_error) = list.init[T](a, 0usize)
    if rejected_error != ok { ret (zero, zero, rejected_error) }
    var accepted = accepted_list
    var rejected = rejected_list
    while true {
        let (value, more) = I.next(it)
        if !more { break }
        var push_error = ok
        if pred(value) {
            push_error = list.push[T](&accepted, value)
        } else {
            push_error = list.push[T](&rejected, value)
        }
        if push_error != ok { ret (zero, zero, push_error) }
    }
    ret (accepted, rejected, ok)
}

// --- The `try_` family, over `next_err`.

fn try_map[I: type, T: type, U: type, Ctx: type](it: *I, ctx: *Ctx, f: fn(*Ctx, T) -> (U, err)) -> TryMap[I, T, U, Ctx] {
    ret TryMap[I, T, U, Ctx] { it: it, ctx: ctx, f: f, ended: false }
}

fn try_map_next_err[I: type, T: type, U: type, Ctx: type](it: *TryMap[I, T, U, Ctx]) -> (U, bool, err) {
    if it.ended { ret (zero, false, ok) }
    let (value, more, source_error) = I.next_err(it.it)
    if source_error != ok {
        it.ended = true
        ret (zero, false, source_error)
    }
    if !more {
        it.ended = true
        ret (zero, false, ok)
    }
    let (mapped, map_error) = it.f(it.ctx, value)
    if map_error != ok {
        it.ended = true
        ret (zero, false, map_error)
    }
    ret (mapped, true, ok)
}

fn try_filter[I: type, T: type, Ctx: type](it: *I, ctx: *Ctx, pred: fn(*Ctx, T) -> (bool, err)) -> TryFilter[I, T, Ctx] {
    ret TryFilter[I, T, Ctx] { it: it, ctx: ctx, pred: pred, ended: false }
}

fn try_filter_next_err[I: type, T: type, Ctx: type](it: *TryFilter[I, T, Ctx]) -> (T, bool, err) {
    if it.ended { ret (zero, false, ok) }
    while true {
        let (value, more, source_error) = I.next_err(it.it)
        if source_error != ok {
            it.ended = true
            ret (zero, false, source_error)
        }
        if !more {
            it.ended = true
            ret (zero, false, ok)
        }
        let (keep, pred_error) = it.pred(it.ctx, value)
        if pred_error != ok {
            it.ended = true
            ret (zero, false, pred_error)
        }
        if keep { ret (value, true, ok) }
    }
    ret (zero, false, ok)
}

// Everything the source yields, or nothing: a failure or a source past `limit` gives the arena
// back what this took and answers zero. What the source consumed getting there stays consumed.
// A zero `limit` is no limit, as it is for `e.path`'s globs: the bound exists for input that
// might not end, and a caller who has one names it.
fn try_collect[T: type, I: type](a: *mem.Arena, it: *I, limit: usize) -> (list.List[T], err) {
    let start = mem.mark(a)
    let (held, init_error) = list.init[T](a, 0usize)
    if init_error != ok { ret (zero, init_error) }
    var result = held
    var taken = 0usize
    while true {
        let (value, more, source_error) = I.next_err(it)
        if source_error != ok {
            mem.reset(a, start)
            ret (zero, source_error)
        }
        if !more { break }
        if limit != 0usize && taken == limit {
            mem.reset(a, start)
            ret (zero, mem.Exhausted)
        }
        let push_error = list.push[T](&result, value)
        if push_error != ok {
            mem.reset(a, start)
            ret (zero, push_error)
        }
        taken += 1usize
    }
    ret (result, ok)
}

// The accumulator alongside the error is the last one fully committed: the item that failed
// never reached it.
fn try_reduce[I: type, T: type, U: type, Ctx: type](it: *I, initial: U, ctx: *Ctx, f: fn(*Ctx, U, T) -> (U, err)) -> (U, err) {
    var accumulator = initial
    while true {
        let (value, more, source_error) = I.next_err(it)
        if source_error != ok { ret (accumulator, source_error) }
        if !more { break }
        let (next, step_error) = f(ctx, accumulator, value)
        if step_error != ok { ret (accumulator, step_error) }
        accumulator = next
    }
    ret (accumulator, ok)
}
