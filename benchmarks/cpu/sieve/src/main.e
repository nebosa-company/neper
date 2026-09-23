// H25's CPU program workload (D943): the primes below thirty million by the sieve of
// Eratosthenes over one arena buffer; prints how many there are and their sum.
use e.mem
use e.io
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let limit = 30000000usize
    let (marks, marks_error) = mem.alloc[u8](a, limit + 1usize)
    if marks_error != ok { ret marks_error }
    var at = 0usize
    while at < marks.len {
        marks[at] = 0u8
        at += 1usize
    }
    var p = 2usize
    while p * p <= limit {
        if marks[p] == 0u8 {
            var multiple = p * p
            while multiple <= limit {
                marks[multiple] = 1u8
                multiple += p
            }
        }
        p += 1usize
    }
    var count = 0u64
    var sum = 0u64
    at = 2usize
    while at <= limit {
        if marks[at] == 0u8 {
            count += 1u64
            sum = (sum + u64(at)) & 1152921504606846975u64
        }
        at += 1usize
    }
    let (b0, b0_error) = str.builder(a, 64usize)
    if b0_error != ok { ret b0_error }
    var b = b0
    try str.push_i64(&b, i64(count))
    try str.push(&b, " ")
    try str.push_i64(&b, i64(sum))
    try str.push(&b, "\n")
    try io.print(str.done(&b))
    ret ok
}
