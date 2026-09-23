// H25's CPU program workload (D943): four million integers from a linear congruential
// generator, sorted by an iterative quicksort with an insertion sort below sixteen;
// prints a position-weighted checksum of the result.
use e.mem
use e.io
use e.str

error Unsorted

fn insertion(values: []i64, low: usize, high: usize) {
    var at = low + 1usize
    while at <= high {
        let value = values[at]
        var hole = at
        while hole > low && values[hole - 1usize] > value {
            values[hole] = values[hole - 1usize]
            hole = hole - 1usize
        }
        values[hole] = value
        at += 1usize
    }
}

fn partition(values: []i64, low: usize, high: usize) -> usize {
    let middle = low + (high - low) / 2usize
    let pivot = values[middle]
    values[middle] = values[high]
    values[high] = pivot
    var store = low
    var at = low
    while at < high {
        if values[at] < pivot {
            let held = values[at]
            values[at] = values[store]
            values[store] = held
            store += 1usize
        }
        at += 1usize
    }
    values[high] = values[store]
    values[store] = pivot
    ret store
}

fn main(a: *mem.Arena, args: []str) -> err {
    let count = 4000000usize
    let (values, values_error) = mem.alloc[i64](a, count)
    if values_error != ok { ret values_error }
    var state = 20260923i64
    var at = 0usize
    while at < count {
        state = (state * 1103515245i64 + 12345i64) & 2147483647i64
        values[at] = state
        at += 1usize
    }
    let (stack, stack_error) = mem.alloc[usize](a, 256usize)
    if stack_error != ok { ret stack_error }
    var top = 0usize
    stack[0usize] = 0usize
    stack[1usize] = count - 1usize
    top = 2usize
    while top > 0usize {
        let high = stack[top - 1usize]
        let low = stack[top - 2usize]
        top = top - 2usize
        if high - low < 16usize {
            insertion(values, low, high)
        } else {
            let split = partition(values, low, high)
            // The larger side is pushed first, so the stack stays logarithmic; a side of
            // fewer than two values is not pushed at all.
            let left_larger = split - low > high - split
            if left_larger && split > low + 1usize {
                stack[top] = low
                stack[top + 1usize] = split - 1usize
                top += 2usize
            }
            if split + 1usize < high {
                stack[top] = split + 1usize
                stack[top + 1usize] = high
                top += 2usize
            }
            if !left_larger && split > low + 1usize {
                stack[top] = low
                stack[top + 1usize] = split - 1usize
                top += 2usize
            }
        }
    }
    var checksum = 0i64
    at = 1usize
    while at < count {
        if values[at - 1usize] > values[at] { ret Unsorted }
        checksum = (checksum + (values[at] & 65535i64) * i64(at & 65535usize)) & 1152921504606846975i64
        at += 1usize
    }
    let (b0, b0_error) = str.builder(a, 64usize)
    if b0_error != ok { ret b0_error }
    var b = b0
    try str.push_i64(&b, checksum)
    try str.push(&b, "\n")
    try io.print(str.done(&b))
    ret ok
}
