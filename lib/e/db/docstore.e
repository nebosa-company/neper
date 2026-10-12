// An embedded document and event store in one append-only file (L147), in the shape of LiteDB
// and Marten: named collections of documents, an event journal of versioned streams with
// optimistic concurrency, projections that fold the journal into documents, and subscriptions
// that resume from a persisted position. The whole database is one log of CRC-framed records:
//
//     file    := "NDS1" frame*
//     frame   := u32le length | u32le crc32(payload) | payload
//     payload := 1 DocPut:    str collection, str id, str data
//              | 2 DocDelete: str collection, str id
//              | 3 Event:     str stream, u32le version, str kind, str data, i64le at
//              | 4 Mark:      u8 namespace (0 projection, 1 subscription), str name, u64le seq
//     str     := u32le length | bytes
//
// The record framing is the write-ahead log of `e.db.storage` over byte payloads rather than its
// `u64` simulation. State is never written anywhere else: every operation appends its frame and
// then applies that same frame to the in-memory tables, exactly as `restore` does for each frame
// of an existing file, so a reopened database equals the one that wrote it. A document, an id
// and an event's text are slices of the log buffer, not copies.
//
// Recovery: `restore` replays frames until the end or the first frame whose length runs past the
// file or whose CRC does not match, and answers how many bytes it dropped (a torn last write is
// the expected case; the file is then valid up to `used`). `compact` rebuilds the log from the
// live documents, every event (their order, and so their sequence numbers, are kept) and the
// marks. Events are never rewritten or removed; a document's earlier versions and deletions are.
//
// Sequence numbers are global and start at 1; a stream's versions start at 1. `append` takes the
// version the caller expects the stream to be at (`ANY_VERSION` for no check, 0 for a new
// stream); a mismatch is `Concurrency` and writes nothing. A projection's `apply` must be
// idempotent: the mark that records how far it has read is written after a batch, so a crash
// re-applies at most that batch. `rebuild` deletes the projection's collection and folds the
// whole journal again. Lookups are linear scans; an index (the B+tree of `e.db.storage`) is the
// upgrade when collections grow. The store is single-threaded; clustering stays with `e.dist`.

use e.algo.hash
use e.mem
use e.store
use e.str

const ANY_VERSION: i64 = -1i64
const NS_PROJECTION: u8 = 0u8
const NS_SUBSCRIPTION: u8 = 1u8
const KIND_PUT: u8 = 1u8
const KIND_DELETE: u8 = 2u8
const KIND_EVENT: u8 = 3u8
const KIND_MARK: u8 = 4u8

type DocRec = struct { coll: str, id: str, data: str, alive: bool }
type Event = struct { seq: u64, stream: str, version: u32, kind: str, data: str, at: i64 }
type Mark = struct { ns: u8, name: str, seq: u64 }
type Stream = struct { name: str, version: u32 }
type Db = struct { log: []u8, used: usize, docs: []DocRec, ndocs: usize, events: []Event, nevents: usize, marks: []Mark, nmarks: usize, streams: []Stream, nstreams: usize, a: *mem.Arena }
type Limits = struct { log: usize, docs: usize, events: usize, marks: usize, streams: usize }
type Projection = struct { name: str, ctx: *void, apply: fn(*void, *Db, Event) -> err }
type Reader = struct { pos: usize, bad: bool }

error Full
error Concurrency
error Invalid
error Corrupt

fn magic() -> str { ret "NDS1" }

// ---- construction and recovery ----------------------------------------------------------

fn create(a: *mem.Arena, lim: Limits) -> (Db, err) {
    var db: Db = zero
    if lim.log < 4usize { ret (db, Invalid) }
    let (log, e1) = mem.alloc[u8](a, lim.log)
    if e1 != ok { ret (db, e1) }
    let (docs, e2) = mem.alloc[DocRec](a, lim.docs)
    if e2 != ok { ret (db, e2) }
    let (events, e3) = mem.alloc[Event](a, lim.events)
    if e3 != ok { ret (db, e3) }
    let (marks, e4) = mem.alloc[Mark](a, lim.marks)
    if e4 != ok { ret (db, e4) }
    let (streams, e5) = mem.alloc[Stream](a, lim.streams)
    if e5 != ok { ret (db, e5) }
    var i = 0usize
    let m = magic()
    while i < 4usize {
        log[i] = m[i]
        i += 1usize
    }
    db.log = log
    db.used = 4usize
    db.docs = docs
    db.events = events
    db.marks = marks
    db.streams = streams
    db.a = a
    ret (db, ok)
}

fn rd_u32(data: str, r: *Reader) -> u32 {
    if r.pos + 4usize > data.len {
        r.bad = true
        ret 0u32
    }
    var v = 0u32
    var i = 0usize
    while i < 4usize {
        v |= u32(data[r.pos + i]) << u32(i * 8usize)
        i += 1usize
    }
    r.pos += 4usize
    ret v
}

fn rd_u64(data: str, r: *Reader) -> u64 {
    if r.pos + 8usize > data.len {
        r.bad = true
        ret 0u64
    }
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v |= u64(data[r.pos + i]) << u64(i * 8usize)
        i += 1usize
    }
    r.pos += 8usize
    ret v
}

fn rd_byte(data: str, r: *Reader) -> u8 {
    if r.pos >= data.len {
        r.bad = true
        ret 0u8
    }
    let v = data[r.pos]
    r.pos += 1usize
    ret v
}

// The byte range of a length-prefixed string; the caller slices its own buffer, so the view is
// not tied to the reader.
fn rd_span(data: str, r: *Reader) -> (usize, usize) {
    let n = rd_u32(data, r)
    if r.bad || usize(n) > data.len - r.pos {
        r.bad = true
        ret (0usize, 0usize)
    }
    let start = r.pos
    r.pos += usize(n)
    ret (start, r.pos)
}
fn find_doc(db: *Db, coll: str, id: str) -> (usize, bool) {
    var i = 0usize
    while i < db.ndocs {
        if str.eq(db.docs[i].id, id) && str.eq(db.docs[i].coll, coll) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn find_stream(db: *Db, name: str) -> (usize, bool) {
    var i = 0usize
    while i < db.nstreams {
        if str.eq(db.streams[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn find_mark(db: *Db, ns: u8, name: str) -> (usize, bool) {
    var i = 0usize
    while i < db.nmarks {
        if db.marks[i].ns == ns && str.eq(db.marks[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Applies one payload (a slice of the log) to the tables. Capacity is checked before anything
// changes, so a refused record leaves the tables as they were.
fn apply(db: *Db, payload: str) -> err {
    var r = Reader { pos: 0usize, bad: false }
    let kind = rd_byte(payload, &r)
    if kind == KIND_PUT {
        let (coll_a, coll_b) = rd_span(payload, &r)
        let coll = payload[coll_a..coll_b]
        let (id_a, id_b) = rd_span(payload, &r)
        let id = payload[id_a..id_b]
        let (data_a, data_b) = rd_span(payload, &r)
        let data = payload[data_a..data_b]
        if r.bad || r.pos != payload.len { ret Corrupt }
        let (at, found) = find_doc(db, coll, id)
        if found {
            db.docs[at].data = data
            db.docs[at].alive = true
            ret ok
        }
        if db.ndocs >= db.docs.len { ret Full }
        db.docs[db.ndocs] = DocRec { coll: coll, id: id, data: data, alive: true }
        db.ndocs += 1usize
        ret ok
    }
    if kind == KIND_DELETE {
        let (coll_a, coll_b) = rd_span(payload, &r)
        let coll = payload[coll_a..coll_b]
        let (id_a, id_b) = rd_span(payload, &r)
        let id = payload[id_a..id_b]
        if r.bad || r.pos != payload.len { ret Corrupt }
        let (at, found) = find_doc(db, coll, id)
        if found { db.docs[at].alive = false }
        ret ok
    }
    if kind == KIND_EVENT {
        let (stream_a, stream_b) = rd_span(payload, &r)
        let stream = payload[stream_a..stream_b]
        let version = rd_u32(payload, &r)
        let (ekind_a, ekind_b) = rd_span(payload, &r)
        let ekind = payload[ekind_a..ekind_b]
        let (data_a, data_b) = rd_span(payload, &r)
        let data = payload[data_a..data_b]
        let at_time = mem.bitcast[i64](rd_u64(payload, &r))
        if r.bad || r.pos != payload.len { ret Corrupt }
        if db.nevents >= db.events.len { ret Full }
        let (si, known) = find_stream(db, stream)
        if !known && db.nstreams >= db.streams.len { ret Full }
        db.events[db.nevents] = Event { seq: u64(db.nevents) + 1u64, stream: stream, version: version, kind: ekind, data: data, at: at_time }
        db.nevents += 1usize
        if known {
            db.streams[si].version = version
        } else {
            db.streams[db.nstreams] = Stream { name: stream, version: version }
            db.nstreams += 1usize
        }
        ret ok
    }
    if kind == KIND_MARK {
        let ns = rd_byte(payload, &r)
        let (name_a, name_b) = rd_span(payload, &r)
        let name = payload[name_a..name_b]
        let seq = rd_u64(payload, &r)
        if r.bad || r.pos != payload.len || ns > NS_SUBSCRIPTION { ret Corrupt }
        let (at, found) = find_mark(db, ns, name)
        if found {
            db.marks[at].seq = seq
            ret ok
        }
        if db.nmarks >= db.marks.len { ret Full }
        db.marks[db.nmarks] = Mark { ns: ns, name: name, seq: seq }
        db.nmarks += 1usize
        ret ok
    }
    ret Corrupt
}

// Opens an existing image: replays every sound frame, and answers how many trailing bytes were
// dropped as a torn or damaged tail. `Corrupt` only when the magic is wrong.
fn restore(a: *mem.Arena, image: str, lim: Limits) -> (Db, usize, err) {
    var lim2 = lim
    if lim2.log < image.len { lim2.log = image.len }
    let (db0, create_error) = create(a, lim2)
    if create_error != ok { ret (db0, 0usize, create_error) }
    var db = db0
    if image.len < 4usize || !str.eq(image[0..4], magic()) { ret (db, 0usize, Corrupt) }
    var i = 0usize
    while i < image.len {
        db.log[i] = image[i]
        i += 1usize
    }
    var pos = 4usize
    while pos + 8usize <= image.len {
        var hdr = Reader { pos: pos, bad: false }
        let n = usize(rd_u32(image, &hdr))
        let crc = rd_u32(image, &hdr)
        if n == 0usize || n > image.len - (pos + 8usize) { break }
        let payload = db.log[pos + 8usize..pos + 8usize + n]
        if hash.crc32(payload) != crc { break }
        let apply_error = apply(&db, payload)
        if apply_error != ok { ret (db, image.len - pos, apply_error) }
        pos += 8usize + n
    }
    db.used = pos
    ret (db, image.len - pos, ok)
}

// The log as written so far: the file's contents.
fn bytes(db: *Db) -> str { ret db.log[0..db.used] }

// ---- writing a frame --------------------------------------------------------------------

fn w_byte(db: *Db, v: u8) -> bool {
    if db.used >= db.log.len { ret false }
    db.log[db.used] = v
    db.used += 1usize
    ret true
}

fn w_u32(db: *Db, v: u32) -> bool {
    var i = 0usize
    while i < 4usize {
        if !w_byte(db, u8((v >> u32(i * 8usize)) & 255u32)) { ret false }
        i += 1usize
    }
    ret true
}

fn w_u64(db: *Db, v: u64) -> bool {
    var i = 0usize
    while i < 8usize {
        if !w_byte(db, u8((v >> u64(i * 8usize)) & 255u64)) { ret false }
        i += 1usize
    }
    ret true
}

fn w_str(db: *Db, s: str) -> bool {
    if !w_u32(db, u32(s.len)) { ret false }
    var i = 0usize
    while i < s.len {
        if !w_byte(db, s[i]) { ret false }
        i += 1usize
    }
    ret true
}

// Starts a frame: reserves the 8-byte header; the payload is written after it.
fn begin(db: *Db) -> (usize, bool) {
    let start = db.used
    if db.log.len - db.used < 9usize { ret (start, false) }
    db.used += 8usize
    ret (start, true)
}

// Seals the frame begun at `start` (patches length and CRC) and applies its payload. A frame the
// tables refuse is taken back out of the log.
fn seal(db: *Db, start: usize) -> err {
    let n = db.used - start - 8usize
    let payload = db.log[start + 8usize..db.used]
    let crc = hash.crc32(payload)
    var i = 0usize
    while i < 4usize {
        db.log[start + i] = u8((u32(n) >> u32(i * 8usize)) & 255u32)
        db.log[start + 4usize + i] = u8((crc >> u32(i * 8usize)) & 255u32)
        i += 1usize
    }
    let apply_error = apply(db, payload)
    if apply_error != ok {
        db.used = start
        ret apply_error
    }
    ret ok
}

fn abandon(db: *Db, start: usize) -> err {
    db.used = start
    ret Full
}

// ---- documents --------------------------------------------------------------------------

// Writes `data` as document `id` of `coll`, replacing any earlier version.
fn put(db: *Db, coll: str, id: str, data: str) -> err {
    if coll.len == 0usize || id.len == 0usize { ret Invalid }
    let (start, room) = begin(db)
    if !room { ret Full }
    let wrote = w_byte(db, KIND_PUT) && w_str(db, coll) && w_str(db, id) && w_str(db, data)
    if !wrote { ret abandon(db, start) }
    ret seal(db, start)
}

fn get(db: *Db, coll: str, id: str) -> (str, bool) {
    let (at, found) = find_doc(db, coll, id)
    if !found || !db.docs[at].alive { ret ("", false) }
    ret (db.docs[at].data, true)
}

// Deletes a document; whether there was one.
fn delete(db: *Db, coll: str, id: str) -> (bool, err) {
    let (at, found) = find_doc(db, coll, id)
    if !found || !db.docs[at].alive { ret (false, ok) }
    let (start, room) = begin(db)
    if !room { ret (false, Full) }
    let wrote = w_byte(db, KIND_DELETE) && w_str(db, coll) && w_str(db, id)
    if !wrote { ret (false, abandon(db, start)) }
    let seal_error = seal(db, start)
    ret (seal_error == ok, seal_error)
}

fn count(db: *Db, coll: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < db.ndocs {
        if db.docs[i].alive && str.eq(db.docs[i].coll, coll) { n += 1usize }
        i += 1usize
    }
    ret n
}

// The `n`-th live document of a collection, in first-written order.
fn doc_at(db: *Db, coll: str, n: usize) -> (str, str, bool) {
    var seen = 0usize
    var i = 0usize
    while i < db.ndocs {
        if db.docs[i].alive && str.eq(db.docs[i].coll, coll) {
            if seen == n { ret (db.docs[i].id, db.docs[i].data, true) }
            seen += 1usize
        }
        i += 1usize
    }
    ret ("", "", false)
}

// ---- the event journal ------------------------------------------------------------------

fn stream_version(db: *Db, stream: str) -> u32 {
    let (at, found) = find_stream(db, stream)
    if !found { ret 0u32 }
    ret db.streams[at].version
}

fn write_event(db: *Db, stream: str, version: u32, kind: str, data: str, at: i64) -> err {
    let (start, room) = begin(db)
    if !room { ret Full }
    let wrote = w_byte(db, KIND_EVENT) && w_str(db, stream) && w_u32(db, version) && w_str(db, kind) && w_str(db, data) && w_u64(db, mem.bitcast[u64](at))
    if !wrote { ret abandon(db, start) }
    ret seal(db, start)
}

// Appends an event to `stream`; its global sequence number. `expected` is the version the
// stream must be at (`ANY_VERSION` for no check; 0 for a stream that must not exist yet).
fn append(db: *Db, stream: str, kind: str, data: str, at: i64, expected: i64) -> (u64, err) {
    if stream.len == 0usize || kind.len == 0usize || expected < ANY_VERSION { ret (0u64, Invalid) }
    let current = stream_version(db, stream)
    if expected != ANY_VERSION && i64(current) != expected { ret (0u64, Concurrency) }
    let write_error = write_event(db, stream, current + 1u32, kind, data, at)
    if write_error != ok { ret (0u64, write_error) }
    ret (u64(db.nevents), ok)
}

fn event_count(db: *Db) -> usize { ret db.nevents }

// The events of one stream from `from_version` (inclusive, one-based) into `out`; how many.
fn read_stream(db: *Db, stream: str, from_version: u32, out: []Event) -> usize {
    var n = 0usize
    var i = 0usize
    while i < db.nevents && n < out.len {
        if db.events[i].version >= from_version && str.eq(db.events[i].stream, stream) {
            out[n] = db.events[i]
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// The events after global sequence `after_seq`, in order, into `out`; how many.
fn read_all(db: *Db, after_seq: u64, out: []Event) -> usize {
    var n = 0usize
    var i = usize(after_seq)
    while i < db.nevents && n < out.len {
        out[n] = db.events[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

// ---- marks, projections, subscriptions ----------------------------------------------------

fn mark_of(db: *Db, ns: u8, name: str) -> u64 {
    let (at, found) = find_mark(db, ns, name)
    if !found { ret 0u64 }
    ret db.marks[at].seq
}

fn set_mark(db: *Db, ns: u8, name: str, seq: u64) -> err {
    let (start, room) = begin(db)
    if !room { ret Full }
    let wrote = w_byte(db, KIND_MARK) && w_byte(db, ns) && w_str(db, name) && w_u64(db, seq)
    if !wrote { ret abandon(db, start) }
    ret seal(db, start)
}

// Folds the journal events after the projection's mark through `apply`, at most `limit` of
// them, then records the new mark; how many were applied.
fn project(db: *Db, p: Projection, limit: usize) -> (usize, err) {
    if p.name.len == 0usize { ret (0usize, Invalid) }
    let from = mark_of(db, NS_PROJECTION, p.name)
    var applied = 0usize
    var seq = from
    while usize(seq) < db.nevents && applied < limit {
        let ev = db.events[usize(seq)]
        let apply_error = p.apply(p.ctx, db, ev)
        if apply_error != ok { ret (applied, apply_error) }
        seq += 1u64
        applied += 1usize
    }
    if seq != from {
        let mark_error = set_mark(db, NS_PROJECTION, p.name, seq)
        if mark_error != ok { ret (applied, mark_error) }
    }
    ret (applied, ok)
}

// Deletes every document of `coll`, resets the projection's mark and folds the whole journal.
fn rebuild(db: *Db, p: Projection, coll: str) -> (usize, err) {
    var i = 0usize
    while i < db.ndocs {
        if db.docs[i].alive && str.eq(db.docs[i].coll, coll) {
            let (gone, delete_error) = delete(db, coll, db.docs[i].id)
            if delete_error != ok { ret (0usize, delete_error) }
        }
        i += 1usize
    }
    if mark_of(db, NS_PROJECTION, p.name) != 0u64 {
        let reset_error = set_mark(db, NS_PROJECTION, p.name, 0u64)
        if reset_error != ok { ret (0usize, reset_error) }
    }
    let (applied, project_error) = project(db, p, db.nevents)
    ret (applied, project_error)
}

fn position(db: *Db, name: str) -> u64 { ret mark_of(db, NS_SUBSCRIPTION, name) }

// The events a subscription has not yet acknowledged, in order, into `out`; how many.
fn poll(db: *Db, name: str, out: []Event) -> usize {
    ret read_all(db, position(db, name), out)
}

// Records that the subscription has handled everything up to `seq`. Moving backwards is
// `Invalid`; a position past the journal is `Invalid`.
fn ack(db: *Db, name: str, seq: u64) -> err {
    if name.len == 0usize || seq > u64(db.nevents) || seq < position(db, name) { ret Invalid }
    if seq == position(db, name) { ret ok }
    ret set_mark(db, NS_SUBSCRIPTION, name, seq)
}

// ---- compaction and files ---------------------------------------------------------------

// A new database holding the live documents, every event in order and the marks.
fn compact(db: *Db, a: *mem.Arena, lim: Limits) -> (Db, err) {
    let (fresh0, create_error) = create(a, lim)
    if create_error != ok { ret (fresh0, create_error) }
    var fresh = fresh0
    var i = 0usize
    while i < db.ndocs {
        if db.docs[i].alive {
            let put_error = put(&fresh, db.docs[i].coll, db.docs[i].id, db.docs[i].data)
            if put_error != ok { ret (fresh, put_error) }
        }
        i += 1usize
    }
    i = 0usize
    while i < db.nevents {
        let ev = db.events[i]
        let ev_error = write_event(&fresh, ev.stream, ev.version, ev.kind, ev.data, ev.at)
        if ev_error != ok { ret (fresh, ev_error) }
        i += 1usize
    }
    i = 0usize
    while i < db.nmarks {
        let mark_error = set_mark(&fresh, db.marks[i].ns, db.marks[i].name, db.marks[i].seq)
        if mark_error != ok { ret (fresh, mark_error) }
        i += 1usize
    }
    ret (fresh, ok)
}

// Writes the file to a store key.
fn save(db: *Db, s: *store.Store, key: str) -> err {
    ret store.put(s, db.a, key, bytes(db))
}

// Reads the file from a store key and replays it; the bytes dropped from a damaged tail.
fn open(a: *mem.Arena, s: *store.Store, key: str, lim: Limits) -> (Db, usize, err) {
    let (image, get_error) = store.get(s, a, key, 0usize)
    if get_error != ok {
        var none: Db = zero
        ret (none, 0usize, get_error)
    }
    let (db, dropped, restore_error) = restore(a, image, lim)
    ret (db, dropped, restore_error)
}
