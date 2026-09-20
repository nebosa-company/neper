// The coverage runtime: a bounded table of region counters the compiler's
// instrumentation increments, and the four operations the fence names over it.
// The instrumentation contract is `hit(file_id, region_id)`: the first call for
// a pair appends its counter, every call adds one, and past `MAX_COUNTERS`
// (4096: a 64 KB global; 1 MB was past the emitter's capacity) further pairs
// are dropped -- the compiler assigns the identifiers and owns the calls;
// nothing else writes the table. ponytail: one linear lookup per hit; the
// compiler can cache a counter's address per site once it emits them.
//
// `snapshot` copies the live counters into the caller's slice in table order
// (`TooLarge` when it is shorter than the table); `reset` zeroes every count and
// keeps the pairs; `merge` sums reports by (file, region) into one sorted by
// file then region, refusing a report that names a pair twice with
// `InvalidProfile`; `write_json` writes `{"counters":[{"file":F,"region":R,
// "hits":H},...]}` in the report's order.

use e.io
use e.mem
use e.test

type Counter = struct { file_id: u32, region_id: u32, hits: u64 }
type Report = struct { counters: []const Counter }
error InvalidProfile
error TooLarge

const MAX_COUNTERS: usize = 4096usize

var table: [4096]Counter = zero
var used: usize = 0usize

// The instrumentation's entry: one more hit on (file_id, region_id).
fn hit(file_id: u32, region_id: u32) {
    var i = 0usize
    while i < used {
        if table[i].file_id == file_id && table[i].region_id == region_id {
            table[i].hits += 1u64
            ret
        }
        i += 1usize
    }
    if used >= MAX_COUNTERS { ret }
    table[used] = Counter { file_id: file_id, region_id: region_id, hits: 1u64 }
    used += 1usize
}

fn snapshot(dst: []Counter) -> ([]Counter, err) {
    if dst.len < used { ret (zero, TooLarge) }
    var i = 0usize
    while i < used {
        dst[i] = table[i]
        i += 1usize
    }
    ret (dst[..used], ok)
}

fn reset() {
    var i = 0usize
    while i < used {
        table[i].hits = 0u64
        i += 1usize
    }
}

fn before(a: Counter, b: Counter) -> bool {
    if a.file_id != b.file_id { ret a.file_id < b.file_id }
    ret a.region_id < b.region_id
}

fn merge(a: *mem.Arena, profiles: []const Report) -> (Report, err) {
    var total = 0usize
    var p = 0usize
    while p < profiles.len {
        total += profiles[p].counters.len
        p += 1usize
    }
    let (all, all_error) = mem.alloc[Counter](a, total)
    if all_error != ok { ret (zero, all_error) }
    // Every counter, each report checked for a repeated pair as it is copied.
    var n = 0usize
    p = 0usize
    while p < profiles.len {
        let counters = profiles[p].counters
        var i = 0usize
        while i < counters.len {
            var j = 0usize
            while j < i {
                if counters[j].file_id == counters[i].file_id && counters[j].region_id == counters[i].region_id { ret (zero, InvalidProfile) }
                j += 1usize
            }
            all[n] = counters[i]
            n += 1usize
            i += 1usize
        }
        p += 1usize
    }
    // Insertion sort by (file, region), then one pass sums equal pairs.
    var i = 1usize
    while i < n {
        let v = all[i]
        var j = i
        while j > 0usize && before(v, all[j - 1usize]) {
            all[j] = all[j - 1usize]
            j -= 1usize
        }
        all[j] = v
        i += 1usize
    }
    var out = 0usize
    i = 0usize
    while i < n {
        if out > 0usize && all[out - 1usize].file_id == all[i].file_id && all[out - 1usize].region_id == all[i].region_id {
            all[out - 1usize].hits += all[i].hits
        } else {
            all[out] = all[i]
            out += 1usize
        }
        i += 1usize
    }
    ret (Report { counters: all[..out] }, ok)
}

fn put_number(w: *io.Writer, v: u64) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var rest = v
    if rest == 0u64 {
        digits[0] = 48u8
        n = 1usize
    }
    while rest > 0u64 {
        digits[n] = u8(48u64 + rest % 10u64)
        rest = rest / 10u64
        n += 1usize
    }
    var reversed: [20]u8 = zero
    var i = 0usize
    while i < n {
        reversed[i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret io.write_all(w, reversed[..n])
}

fn write_json(writer: *io.Writer, report: *const Report) -> err {
    try io.write_all(writer, "{\"counters\":[")
    var i = 0usize
    while i < report.counters.len {
        if i > 0usize { try io.write_all(writer, ",") }
        let c = report.counters[i]
        try io.write_all(writer, "{\"file\":")
        try put_number(writer, u64(c.file_id))
        try io.write_all(writer, ",\"region\":")
        try put_number(writer, u64(c.region_id))
        try io.write_all(writer, ",\"hits\":")
        try put_number(writer, c.hits)
        try io.write_all(writer, "}")
        i += 1usize
    }
    ret io.write_all(writer, "]}")
}
