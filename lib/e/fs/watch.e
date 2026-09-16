// Directory watching by path, over `e.os`'s watch: the same actions and events, with
// paths relative to the watched root as the host reports them. A recursive watch is
// `Unsupported` on both hosts today, and the error says so in this module's name.

use e.mem
use e.os

type Watch = struct { raw: os.Watch }
type Action = enum u8 { Added, Removed, Modified, Renamed, Overflow }
type Event = struct { action: Action, path: str, old_path: str }
error Closed
error Unsupported

fn open(a: *mem.Arena, path: str, recursive: bool) -> (Watch, err) {
    let (raw, open_error) = os.watch_open(a, path, recursive)
    if open_error == os.Unsupported { ret (zero, Unsupported) }
    if open_error != ok { ret (zero, open_error) }
    var w: Watch = zero
    w.raw = raw
    ret (w, ok)
}

fn action_of(raw: os.WatchAction) -> Action {
    if raw == .Added { ret .Added }
    if raw == .Removed { ret .Removed }
    if raw == .Modified { ret .Modified }
    if raw == .Renamed { ret .Renamed }
    ret .Overflow
}

// Fills `events` from the host's queue; the count is how many are valid. The host's
// events are read into a stack buffer of the same length, capped at 64 a call.
fn read(a: *mem.Arena, watch: Watch, events: []Event) -> (usize, err) {
    var raw_events: [64]os.WatchEvent = zero
    var take = events.len
    if take > raw_events.len { take = raw_events.len }
    let (count, read_error) = os.watch_read(a, watch.raw, raw_events[..take])
    if read_error != ok { ret (0usize, read_error) }
    var at = 0usize
    while at < count {
        events[at].action = action_of(raw_events[at].action)
        events[at].path = raw_events[at].path
        events[at].old_path = raw_events[at].old_path
        at += 1usize
    }
    ret (count, ok)
}

fn close(watch: own Watch) -> err { ret os.watch_close(watch.raw) }
