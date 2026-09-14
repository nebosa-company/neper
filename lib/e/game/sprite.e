// Atlas regions, clips and the playback that walks them (D249).
//
// Frames and transitions, not pixels. A clip names a run of atlas regions and how long
// each is held; a `Player` is a cursor over one clip, advanced a tick at a time. Nothing
// here rasterises, samples or knows what a texture is -- which is what lets the animation
// state of a game be simulated, replayed and compared without a machine to draw on.
//
// A clip ends by naming what follows: `then` is the clip to run next, so an attack that
// returns to idle is data rather than a branch in the game. A looping clip names itself
// implicitly by setting `loops`, and the two are distinct -- a loop never finishes, and a
// finished clip stays finished until something plays another.

use e.mem
use e.str

// A rectangle in the atlas, plus the point the sprite is positioned by. The pivot is
// signed because it is usually inside the region but need not be.
type Region = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
    pivot_x: i16,
    pivot_y: i16,
}

type Atlas = struct {
    regions: []const Region,
    names: []const str,
}

// `first` and `count` are a run in the atlas; `hold` is the ticks each frame lasts.
type Clip = struct {
    first: u16,
    count: u16,
    hold: u16,
    loops: bool,
    then: u16,
}

type Player = struct {
    clip: u16,
    frame: u16,
    timer: u16,
    finished: bool,
}

error Unknown
error Invalid

const NONE: u16 = 65535u16

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

fn region(at: Atlas, name: str) -> (Region, err) {
    var empty: Region = zero
    var index = 0usize
    while index < at.names.len && index < at.regions.len {
        if same(at.names[index], name) { ret (at.regions[index], ok) }
        index += 1usize
    }
    ret (empty, Unknown)
}

fn region_at(atlas: Atlas, index: u16) -> (Region, err) {
    var empty: Region = zero
    if usize(index) >= atlas.regions.len { ret (empty, Unknown) }
    ret (atlas.regions[usize(index)], ok)
}

// Starting a clip resets the cursor, so replaying the clip already running restarts it
// rather than continuing it. A game that wants "keep going if already in this state"
// tests `p.clip` first; the other way round cannot be written by the caller.
fn play(p: *Player, clip: u16) -> err {
    p.clip = clip
    p.frame = 0u16
    p.timer = 0u16
    p.finished = false
    ret ok
}

// One tick. A clip whose hold is zero is treated as one tick per frame, so a table with
// a forgotten hold animates fast rather than standing still forever.
fn advance(p: *Player, clips: []const Clip) -> err {
    if usize(p.clip) >= clips.len { ret Unknown }
    if p.finished { ret ok }
    let running = clips[usize(p.clip)]
    if running.count == 0u16 { ret Invalid }
    var hold = running.hold
    if hold == 0u16 { hold = 1u16 }
    p.timer = p.timer + 1u16
    if p.timer < hold { ret ok }
    p.timer = 0u16
    if p.frame + 1u16 < running.count {
        p.frame = p.frame + 1u16
        ret ok
    }
    if running.loops {
        p.frame = 0u16
        ret ok
    }
    if running.then != NONE && usize(running.then) < clips.len {
        ret play(p, running.then)
    }
    // Nothing follows: hold the last frame and say so, rather than wrapping or blanking.
    p.finished = true
    ret ok
}

// The atlas index of the frame now showing.
fn frame(p: Player, clips: []const Clip) -> u16 {
    if usize(p.clip) >= clips.len { ret 0u16 }
    let running = clips[usize(p.clip)]
    if running.count == 0u16 { ret 0u16 }
    var offset = p.frame
    if offset >= running.count { offset = running.count - 1u16 }
    ret running.first + offset
}

fn finished(p: Player) -> bool {
    ret p.finished
}

// How far through the clip the cursor is, as frames elapsed over frames total. What a
// caller uses to drive something alongside the animation without recomputing the timing.
fn progress(p: Player, clips: []const Clip) -> (u16, u16) {
    if usize(p.clip) >= clips.len { ret (0u16, 0u16) }
    ret (p.frame, clips[usize(p.clip)].count)
}
