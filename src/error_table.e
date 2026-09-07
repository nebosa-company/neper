// Program-wide error-value validation performed before either linker runs.

use artifact_hash
use e.mem
use graph
use resolve

error InvalidTable
error HashZero
error HashCollision

type Conflict = struct {
    value: usize,
    first_module: str,
    first_name: str,
    second_module: str,
    second_name: str,
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var index = 0usize
    while index < left.len {
        if left[index] != right[index] { ret false }
        index += 1usize
    }
    ret true
}

fn symbol_value(r: *resolve.Resolver, g: *graph.Graph, symbol_index: usize) -> (usize, err) {
    if symbol_index >= r.count { ret (0usize, InvalidTable) }
    let symbol = r.symbols[symbol_index]
    if symbol.kind != .Error || symbol.module_index >= g.count { ret (0usize, InvalidTable) }
    let (value, value_error) = artifact_hash.qualified_error_value(g.modules[symbol.module_index].name, symbol.name)
    ret (value, value_error)
}

fn set_first(conflict: *Conflict, r: *resolve.Resolver, g: *graph.Graph, symbol_index: usize, value: usize) {
    let symbol = r.symbols[symbol_index]
    conflict.value = value
    conflict.first_module = g.modules[symbol.module_index].name
    conflict.first_name = symbol.name
    conflict.second_module = ""
    conflict.second_name = ""
}

fn validate_declarations(r: *resolve.Resolver, g: *graph.Graph, conflict: *Conflict) -> err {
    var symbol_index = 0usize
    while symbol_index < r.count {
        if r.symbols[symbol_index].kind == .Error {
            let (value, value_error) = symbol_value(r, g, symbol_index)
            if value_error != ok { ret value_error }
            if value == 0usize {
                set_first(conflict, r, g, symbol_index, value)
                ret HashZero
            }
        }
        symbol_index += 1usize
    }
    ret ok
}

fn validate_link(r: *resolve.Resolver, g: *graph.Graph, conflict: *Conflict) -> err {
    try validate_declarations(r, g, conflict)
    var first = 0usize
    while first < r.count {
        if r.symbols[first].kind == .Error {
            let (first_value, first_error) = symbol_value(r, g, first)
            if first_error != ok { ret first_error }
            var second = first + 1usize
            while second < r.count {
                if r.symbols[second].kind == .Error {
                    let (second_value, second_error) = symbol_value(r, g, second)
                    if second_error != ok { ret second_error }
                    if first_value == second_value {
                        set_first(conflict, r, g, first, first_value)
                        conflict.second_module = g.modules[r.symbols[second].module_index].name
                        conflict.second_name = r.symbols[second].name
                        ret HashCollision
                    }
                }
                second += 1usize
            }
        }
        first += 1usize
    }
    ret ok
}

// The qualified name as a string *literal*, quotes and all. The lowering that reads
// this table interns spellings, not bytes, and an error name is `[A-Za-z0-9_.]`
// throughout -- no escape can appear in one -- so wrapping it in quotes is the whole
// encoding.
fn quoted_name(a: *mem.Arena, module: str, name: str) -> (str, err) {
    let total = module.len + name.len + 3usize
    let (storage, storage_error) = mem.alloc[u8](a, total)
    if storage_error != ok { ret ("", storage_error) }
    storage[0usize] = 34u8
    var at = 0usize
    while at < module.len {
        storage[1usize + at] = module[at]
        at += 1usize
    }
    storage[1usize + module.len] = 46u8
    at = 0usize
    while at < name.len {
        storage[2usize + module.len + at] = name[at]
        at += 1usize
    }
    storage[total - 1usize] = 34u8
    ret (storage[..], ok)
}

// The merged error table: every error declared anywhere in the program, by value.
// `validate_link` has already rejected a program where two names share one, so the
// values here are distinct and the table is a function, not a relation.
//
// Sorted by value on the way in. Nothing depends on the order yet -- `push_err`
// expands to a chain of compares, which a sorted table lets a later pass turn into a
// search -- but an order fixed by the values rather than by declaration order is what
// keeps the same program producing the same binary (spec section 12).
fn build(a: *mem.Arena, r: *resolve.Resolver, g: *graph.Graph, values: []usize, spellings: []str) -> (usize, err) {
    var count = 0usize
    var symbol_index = 0usize
    while symbol_index < r.count {
        if r.symbols[symbol_index].kind == .Error {
            let (value, value_error) = symbol_value(r, g, symbol_index)
            if value_error != ok { ret (0usize, value_error) }
            if count == values.len || count == spellings.len { ret (0usize, InvalidTable) }
            let symbol = r.symbols[symbol_index]
            let (spelling, spelling_error) = quoted_name(a, g.modules[symbol.module_index].name, symbol.name)
            if spelling_error != ok { ret (0usize, spelling_error) }
            var at = count
            while at > 0usize && values[at - 1usize] > value {
                values[at] = values[at - 1usize]
                spellings[at] = spellings[at - 1usize]
                at = at - 1usize
            }
            values[at] = value
            spellings[at] = spelling
            count += 1usize
        }
        symbol_index += 1usize
    }
    ret (count, ok)
}

fn self_test() -> err {
    var modules: [1]graph.Module = zero
    modules[0usize].name = "main"
    var g: graph.Graph = zero
    g.modules = modules[..]
    g.count = 1usize

    var symbols: [2]resolve.Symbol = zero
    symbols[0usize].name = "E49B7D00B"
    symbols[0usize].kind = .Error
    symbols[0usize].module_index = 0usize
    symbols[1usize].name = "E9E692E7E"
    symbols[1usize].kind = .Error
    symbols[1usize].module_index = 0usize
    var r: resolve.Resolver = zero
    r.symbols = symbols[..]
    r.count = 2usize

    var conflict: Conflict = zero
    let validation_error = validate_link(&r, &g, &conflict)
    if validation_error != HashCollision || conflict.value != 2531832999usize { ret InvalidTable }
    if !same(conflict.first_name, "E49B7D00B") || !same(conflict.second_name, "E9E692E7E") { ret InvalidTable }

    // The merged table over a program with two errors. These two collide, which is
    // exactly why they are useful here: it makes the two entries' values equal, so a
    // sort that dropped or duplicated one would still be caught by the count.
    var storage: [4096]u8 = zero
    var scratch = mem.arena_from(storage[..])
    var values: [4]usize = zero
    var spellings: [4]str = zero
    let (count, build_error) = build(&scratch, &r, &g, values[..], spellings[..])
    if build_error != ok { ret build_error }
    if count != 2usize { ret InvalidTable }
    if values[0usize] != 2531832999usize || values[1usize] != 2531832999usize { ret InvalidTable }
    // Quotes and all: what the table carries is a string *literal*, because what
    // reads it interns spellings rather than bytes.
    if !same(spellings[0usize], "\"main.E49B7D00B\"") { ret InvalidTable }
    if !same(spellings[1usize], "\"main.E9E692E7E\"") { ret InvalidTable }

    // An error-free program has an empty table rather than no table.
    r.count = 0usize
    let (empty, empty_error) = build(&scratch, &r, &g, values[..], spellings[..])
    if empty_error != ok { ret empty_error }
    if empty != 0usize { ret InvalidTable }
    ret ok
}
