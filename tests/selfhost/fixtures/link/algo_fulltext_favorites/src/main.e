// A user's favorites are growable: the 257th distinct ID must not silently
// disappear when the original 256-entry allocation fills.
use e.algo.fulltext as fulltext
use e.mem
use e.os

fn id(bytes: []u8, index: usize) -> str {
    let at = index * 2usize
    bytes[at] = u8(65usize + index / 26usize)
    bytes[at + 1usize] = u8(65usize + index % 26usize)
    ret bytes[at..at + 2usize]
}

fn main() {
    var storage: [16384]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var recents = fulltext.new_recents(&arena, 1usize, 1usize)
    var names: [514]u8 = zero
    var i = 0usize
    while i < 257usize {
        fulltext.favorite(&recents, "user", id(names[0..], i))
        i += 1usize
    }
    if recents.fav_count != 1usize || recents.favs[0usize].count != 257usize { os.exit(1) }
    if recents.favs[0usize].ids.len < 512usize { os.exit(2) }
    if !fulltext.is_favorite(&recents, "user", id(names[0..], 0usize)) { os.exit(3) }
    if !fulltext.is_favorite(&recents, "user", id(names[0..], 256usize)) { os.exit(4) }
    fulltext.unfavorite(&recents, "user", id(names[0..], 128usize))
    if fulltext.is_favorite(&recents, "user", id(names[0..], 128usize)) || recents.favs[0usize].count != 256usize { os.exit(5) }
    os.exit(0)
}
