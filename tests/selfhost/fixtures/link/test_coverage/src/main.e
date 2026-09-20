// `e.test.coverage`: hits recorded through the instrumentation entry appear in a
// snapshot in first-seen order with their counts; a short destination is
// `TooLarge`; `reset` zeroes the counts and keeps the pairs; `merge` sums three
// reports by (file, region) into one sorted by file then region and refuses a
// report naming a pair twice; `write_json` is the documented shape.

use e.io
use e.mem
use e.os
use e.test.coverage

fn main(a: *mem.Arena, args: []str) -> err {
    var empty: [4]coverage.Counter = zero
    let (none, none_error) = coverage.snapshot(empty[0..])
    if none_error != ok || none.len != 0usize { os.exit(1i32) }
    coverage.hit(1u32, 7u32)
    coverage.hit(1u32, 3u32)
    coverage.hit(1u32, 7u32)
    coverage.hit(2u32, 1u32)
    coverage.hit(1u32, 7u32)
    var dst: [4]coverage.Counter = zero
    let (seen, seen_error) = coverage.snapshot(dst[0..])
    if seen_error != ok || seen.len != 3usize { os.exit(2i32) }
    if seen[0].file_id != 1u32 || seen[0].region_id != 7u32 || seen[0].hits != 3u64 { os.exit(3i32) }
    if seen[1].region_id != 3u32 || seen[1].hits != 1u64 || seen[2].file_id != 2u32 || seen[2].hits != 1u64 { os.exit(4i32) }
    var short: [2]coverage.Counter = zero
    let (_, short_error) = coverage.snapshot(short[0..])
    if short_error != coverage.TooLarge { os.exit(5i32) }
    coverage.reset()
    let (cleared, cleared_error) = coverage.snapshot(dst[0..])
    if cleared_error != ok || cleared.len != 3usize || cleared[0].hits != 0u64 || cleared[0].region_id != 7u32 { os.exit(6i32) }
    coverage.hit(2u32, 1u32)
    let (after, after_error) = coverage.snapshot(dst[0..])
    if after_error != ok || after.len != 3usize || after[2].hits != 1u64 { os.exit(7i32) }

    // Merge: sums by pair, sorted by file then region.
    let first: [2]coverage.Counter = [2]coverage.Counter{ coverage.Counter { file_id: 2u32, region_id: 1u32, hits: 5u64 }, coverage.Counter { file_id: 1u32, region_id: 9u32, hits: 1u64 } }
    let second: [2]coverage.Counter = [2]coverage.Counter{ coverage.Counter { file_id: 1u32, region_id: 9u32, hits: 4u64 }, coverage.Counter { file_id: 1u32, region_id: 2u32, hits: 7u64 } }
    let third: [1]coverage.Counter = [1]coverage.Counter{ coverage.Counter { file_id: 2u32, region_id: 1u32, hits: 1u64 } }
    let reports: [3]coverage.Report = [3]coverage.Report{ coverage.Report { counters: first[0..] }, coverage.Report { counters: second[0..] }, coverage.Report { counters: third[0..] } }
    let (merged, merged_error) = coverage.merge(a, reports[0..])
    if merged_error != ok || merged.counters.len != 3usize { os.exit(8i32) }
    if merged.counters[0].file_id != 1u32 || merged.counters[0].region_id != 2u32 || merged.counters[0].hits != 7u64 { os.exit(9i32) }
    if merged.counters[1].region_id != 9u32 || merged.counters[1].hits != 5u64 || merged.counters[2].file_id != 2u32 || merged.counters[2].hits != 6u64 { os.exit(10i32) }
    let doubled: [2]coverage.Counter = [2]coverage.Counter{ coverage.Counter { file_id: 1u32, region_id: 1u32, hits: 1u64 }, coverage.Counter { file_id: 1u32, region_id: 1u32, hits: 2u64 } }
    let bad: [1]coverage.Report = [1]coverage.Report{ coverage.Report { counters: doubled[0..] } }
    let (_, bad_error) = coverage.merge(a, bad[0..])
    if bad_error != coverage.InvalidProfile { os.exit(11i32) }
    let (nothing, nothing_error) = coverage.merge(a, reports[0usize..0usize])
    if nothing_error != ok || nothing.counters.len != 0usize { os.exit(12i32) }

    // JSON.
    var buffer: [256]u8 = zero
    var sink = io.SliceWriter { data: buffer[0..], off: 0usize }
    var w = io.slice_writer(&sink)
    try coverage.write_json(&w, &merged)
    let expected = "{\"counters\":[{\"file\":1,\"region\":2,\"hits\":7},{\"file\":1,\"region\":9,\"hits\":5},{\"file\":2,\"region\":1,\"hits\":6}]}"
    if sink.off != expected.len { os.exit(13i32) }
    var i = 0usize
    while i < expected.len {
        if buffer[i] != expected[i] { os.exit(14i32) }
        i += 1usize
    }
    sink.off = 0usize
    try coverage.write_json(&w, &nothing)
    if sink.off != 15usize { os.exit(15i32) }

    try io.print("test coverage ok\n")
    ret ok
}
