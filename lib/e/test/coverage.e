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

// Summaries over a counter list (a `snapshot` or a merged report's counters):
// `blocks` counts the regions hit against `total_regions` (a hit region past
// the total is not counted twice; a total of zero is 0%); `branches` reads
// each branch's two outcome regions, an outcome covered when its counter has
// a hit (an absent counter is unhit); `mcdc` finds an independence pair per
// condition of a decision with `n` conditions from evaluated vectors (a
// condition mask and the decision's outcome): two vectors differing in that
// condition alone with different outcomes, the first in vector order.
// ponytail: the pair search is every pair per condition, O(n * v^2), enough
// for the n <= 32 a mask holds and the vectors one decision is tested with.

type Summary = struct { covered: usize, total: usize, percent: f64 }
type Branch = struct { file_id: u32, taken: u32, not_taken: u32 }
type Vector = struct { mask: u32, outcome: bool }
type Pair = struct { found: bool, first: usize, second: usize }

fn hits_of(counters: []const Counter, file_id: u32, region_id: u32) -> u64 {
    var i = 0usize
    while i < counters.len {
        if counters[i].file_id == file_id && counters[i].region_id == region_id { ret counters[i].hits }
        i += 1usize
    }
    ret 0u64
}

fn blocks(counters: []const Counter, total_regions: usize) -> Summary {
    var covered = 0usize
    var i = 0usize
    while i < counters.len {
        if counters[i].hits > 0u64 { covered += 1usize }
        i += 1usize
    }
    if covered > total_regions { covered = total_regions }
    var percent = 0.0f64
    if total_regions > 0usize { percent = f64(covered) * 100.0f64 / f64(total_regions) }
    ret Summary { covered: covered, total: total_regions, percent: percent }
}

fn branches(counters: []const Counter, pairs: []const Branch) -> (usize, usize) {
    var covered = 0usize
    var i = 0usize
    while i < pairs.len {
        if hits_of(counters, pairs[i].file_id, pairs[i].taken) > 0u64 { covered += 1usize }
        if hits_of(counters, pairs[i].file_id, pairs[i].not_taken) > 0u64 { covered += 1usize }
        i += 1usize
    }
    ret (covered, 2usize * pairs.len)
}

// `pairs` receives one entry per condition (`TooLarge` when shorter than `n`);
// answers how many conditions have a pair.
fn mcdc(n: u32, vectors: []const Vector, pairs: []Pair) -> (usize, err) {
    if n > 32u32 || pairs.len < usize(n) { ret (0usize, TooLarge) }
    var covered = 0usize
    var c = 0u32
    while c < n {
        let bit = 1u32 << c
        var found = false
        var i = 0usize
        while i < vectors.len && !found {
            var j = i + 1usize
            while j < vectors.len && !found {
                if (vectors[i].mask ^ vectors[j].mask) == bit && vectors[i].outcome != vectors[j].outcome {
                    pairs[usize(c)] = Pair { found: true, first: i, second: j }
                    found = true
                }
                j += 1usize
            }
            i += 1usize
        }
        if found { covered += 1usize } else { pairs[usize(c)] = Pair { found: false, first: 0usize, second: 0usize } }
        c += 1u32
    }
    ret (covered, ok)
}
