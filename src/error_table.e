// Program-wide error-value validation performed before either linker runs.

use artifact_hash
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
    ret ok
}
